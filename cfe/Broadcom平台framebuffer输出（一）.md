##Broadcom平台framebuffer输出（一）CFE 命令行输出到LCD

##1. 简述

`CFE`默认只支持串口输出，我刚接触`CFE`的时候就特别期望能将`CFE`的命令行输出到显示器上。

借鉴`u-boot`的`lcd`驱动，在`cfe`上实现将命令行输出到显示器上。

>环境：
>
+ 硬件平台：`BCM97583`
+ `CFE` 版本：`bcm97583 cfe v3.7`
+ 输出方式：`HDMI`或`HDMI`转`DVI`

>很容易基于这个版本的代码将实现移植到最新的`cfe`(`mips`平台)或`bolt`(`arm`平台)代码上。

##2. 效果预览
`CFE`命令行(`720x576`)通过`HDMI`转`DVI`输出到显示器：

![CFE命令行输出到LCD](https://github.com/guyongqiangx/blog/blob/dev/cfe/images/cfe.jpg?raw=true)

##3. 代码实现
###3.1 显示综述
官方`CFE`代码不支持`framebuffer`驱动，所以不能进行任意的输出控制。但是`CFE`有个`SPLASH`功能，可以将存放在`flash`上的`BMP`图像作为开机`logo`显示。

对于`SPLASH`，实现分为几个步骤：

1. 指定显示使用的`surface memory`
2. 将`BMP`图像读取到内存
3. 加载预先生成的显示和输出相关寄存器
4. 将内存中的`BMP`图像输出到`surface memory`相应位置

显然，通过上一节中的步骤1和4，机顶盒已经完成了显示的初始化，具备了基本的显示能力，例如显示一个单色屏幕。

基于这个显示基础，通过操纵`surface memory`，实现命令行的输出。

功能上代码实现分为4个部分：

+ 字库数据（`font_8x16.h`）
+ 显示设备管理（`dev_lcd.c`）
+ 显示内容管理（`fbcon.c`）
+ 显示的初始化和调用（`cfe_main.c`, `cfe_console.c`）

###3.2 字库数据

`font_8x16.h`表述了字符数据信息：
```
#define VIDEO_FONT_CHARS    256
#define VIDEO_FONT_WIDTH    8
#define VIDEO_FONT_HEIGHT   16
#define VIDEO_FONT_SIZE     (VIDEO_FONT_CHARS * VIDEO_FONT_HEIGHT)

static unsigned char video_fontdata[VIDEO_FONT_SIZE] =
{
    ...
}
```

包括：

+ 字符数量：`VIDEO_FONT_CHARS`
+ 字符宽度：`VIDEO_FONT_WIDTH`
+ 字符高度：`VIDEO_FONT_HEIGHT`
+ 字符数据大小：`VIDEO_FONT_SIZE`
>（每个`bit`描述一个`pixel`，`256`个`8x16`的字符，占用大小为`256x(8x16)/8=256x16`字节）

+ 字符数据内容：`video_fontdata[VIDEO_FONT_SIZE]`

这里直接采用`Linux`下的等宽字库数据`font_8x16.h`，也是最经典的命令行字库，从小到大看到的命令行基本上都是采用这个字库。等宽字符的优点很明显，可以通过`ascii`码以及字符的高和宽线性计算字符数据的起始地址从而获得所需的点阵数据。
也可以根据喜好更换为其它等宽字库数据。



###3.3 数据结构

`dev_lcd.h`定义了`lcd`驱动所用到的结构体，主要包括3类：

+ `lcd_probe_t`

`lcd_probe_t`定义了用于设备初始化操作`probe`的结构体：
```
typedef struct lcd_probe_s {
    /* 旋转标识，暂时没有用到 */
    uint8_t rotation;   /* rotation of display (0, 1, 2, 3) */
    /* 单个像素占用的比特数，可计算转换为单个像素占用的字节数 */
    uint8_t bpp;        /* bits per pixel */

    /* 显示设备的宽和高 */
    uint32_t width, height;

    /* 显示输出使用的前景和背景色 */
    uint32_t bg_color, fg_color; /* background/foreground color */

    /* 定义console的区域 */
    win_t win;

    /* framebuffer基址 */
    void *base;         /* buffer */
}lcd_probe_t;
```

__`console`默认宽高和设备宽高一致，也可以通过`win`指定`console`的宽和高，使其只占用一部分显示区域。__

+ `fbcon_t`

`fbcon_t`是结构体`fbcon_s`的`typedef`：`typedef struct fbcon_s fbcon_t;`

其定义了`console`的详细信息和操作：
```
struct fbcon_s {
    /* 起始位置(左上角) */
    uint32_t x, y;
    /* 宽、高 */
    uint32_t w, h;

    /* 总列和行数量（按字符统计） */
    int32_t cols, rows;

    /* 当前cursor位置 */
    int32_t cur_col, cur_row;

    /* 在全屏坐标位置(x, y)输出字符c */
    void (*putc_xy)(fbcon_t *con, uint32_t x, uint32_t y, char c);
    /* 移动rowsrc行到rowdst */
    void (*moverow)(fbcon_t *con, uint32_t rowdst, uint32_t rowsrc);
    /* 使用颜色color清除row位置的整行 */
    void (*setrow)(fbcon_t *con, uint32_t row, uint32_t color);

    /* framebuffer基址 */
    void *start;    /* framebuffer start addr */
    /* 预留，未使用 */
    void *cmap;     /* color map */
    /* 指向显示设备的指针 */
    lcddev_t *lcd;  /* lcd device */
};
```

__`start`指向`framebuffer`基址，如果`console`起始位置为(0,0)，则`start`指向显示设备的`base`__

__`lcd`指向结构体`lcddev_t`的指针，便于访问设备的`rotation`和`bg_color`、`fg_color`等信息__

+ `lcddev_t`

`lcddev_t`是结构体`lcddev_s`的`typedef`：`typedef struct lcddev_s lcddev_t;`

```
struct lcddev_s {
    uint8_t rotation;               /* rotation of displays */
    uint8_t bpp;                    /* bits per pixel */
    uint32_t width, height;
    uint32_t pitch;                 /* line pitch in bytes */
    uint32_t bg_color, fg_color;

    fbcon_t con;                  /* consoles */

    void *base;                     /* buffer */
};
```

###3.4 显示设备管理

`dev_lcd.c`实现了显示设备的管理，主要围绕`CFE`设备管理的两个结构体进行操作：

```
/*
 * device dispatch
 */
const static cfe_devdisp_t lcddrv_dispatch = {
    lcddrv_open,
    NULL /* lcddrv_read */,
    NULL /* lcddrv_inpstat */,
    lcddrv_write,
    NULL /* lcddrv_ioctl */,
    lcddrv_close,
    NULL /* lcddrv_poll */,
    NULL
};

const cfe_driver_t lcddrv = {
    "LCD Console",
    "lcd",
    CFE_DEV_OTHER,
    &lcddrv_dispatch,
    lcddrv_probe
};
```

这里将显示使用的`surface memory`虚拟为一个`lcd`设备，由结构体`lcddrv`进行管理，并对这个设备进行操作：

+ `lcddrv_probe`

结构体`lcddrv`的成员`lcddrv_probe`会根据传入的参数对`lcd`进行初始化：
```

static void lcddrv_probe(cfe_driver_t *drv,
               unsigned long probe_a, unsigned long probe_b,
               void *probe_ptr)
{
    lcddev_t *softc;
    lcd_probe_t *probe;
    win_t win;

    bvn_init *init = NULL;
    char descr[80];

    char buffer[40];
    BPXL_Format format;

    /*
     * Now, on with the probing:
     *  probe_a is the bvn_init function address
     *  probe_b is unused
     *  probe_ptr is probe structure pointer
     */

    /*
     * probe_a：指向显示的BVN(Braodcom Video Network)初始化函数
     * probe_b：未使用
     * probe_ptr：指向lcd_probe_t结构体
     */
    probe = (lcd_probe_t *)probe_ptr;

    softc = (lcddev_t *)KMALLOC(sizeof(lcddev_t), 0);
    if (softc)
    {
        memset(softc, 0, sizeof(lcddev_t));

        if (probe)
        {
            /* 根据probe信息初始化设备管理结构体softc */
            softc->rotation = probe->rotation;
            softc->bpp = probe->bpp;
            softc->width = probe->width;
            softc->height = probe->height;
            softc->pitch = probe->width * NBYTES(probe->bpp);
            softc->bg_color = probe->bg_color;
            softc->fg_color = probe->fg_color;

            softc->base = probe->base;

            debug("fb range: [0x%08x - 0x%08x]\n", softc->base, (char *)softc->base + softc->pitch * softc->height);

            /* 定义显示的console子窗口 */
            if (probe->win.w == 0 || probe->win.h == 0)
            {
                /* construt a default window */
                memset(&win, 0, sizeof(win));
                win.w = probe->width;
                win.h = probe->height;
            }
            else
            {
                /* preset window */
                memcpy(&win, &probe->win, sizeof(win));
            }

            /* 初始化console */
            fbcon_init(&softc->con, &win, softc);

            /* ...其它操作... */

            /* 更新设备描述信息，用于show devices命令显示 */
            /* description */
            xsprintf(descr, "%s at 0x%08x, size [%d,%d,%d,%d]",
                drv->drv_description, softc->base,
                win.x, win.y, win.x + win.w, win.y + win.h);

            /* 添加设备到cfe的设备管理队列 */
            cfe_attach(drv, softc, NULL, descr);

            /*
             * 各项结构体初始化完成后调用bvn_init初始化显示相关寄存器
             * 完成后输出的格式就确定下来了
             */
            /* call init */
            init = (bvn_init *)probe_a;
            if (init != NULL)
            {
                /* reg, heap, surface */
                init(NULL, NULL, softc->base);
            }

            /* 清理显存区域，可用于显示默认的logo图像或提示信息 */
            /* clear whole screen with background color */
            lcd_clear(softc);
        }
    }

    return;
}
```
+ `ldcdrv_dispatch`

结构体`lcddrv`的成员`lcddrv_dispatch`链接了`lcd`设备的各种操作接口，当上层调用文件系统接口`cfe_open`，`cfe_close`，`cfe_read`, `cfe_write`, `cfe_ioctl`时，具体操作由`lcddrv_displath`链接的函数来执行。
如果支持所有操作，需要实现以下接口：

>
- `int (*dev_open)(cfe_devctx_t *ctx)`
- `int (*dev_read)(cfe_devctx_t *ctx,iocb_buffer_t *buffer)`
- `int (*dev_inpstat)(cfe_devctx_t *ctx,iocb_inpstat_t *inpstat)`
- `int (*dev_write)(cfe_devctx_t *ctx,iocb_buffer_t *buffer)`
- `int (*dev_ioctl)(cfe_devctx_t *ctx,iocb_buffer_t *buffer)`
- `int (*dev_close)(cfe_devctx_t *ctx)`
- `void (*dev_poll)(cfe_devctx_t *ctx,int64_t ticks)`
- `void (*dev_reset)(void *softc)`

由于`lcd`只支持简单的输出显示，这里只实现了`open`, `write`和`close`接口，可以根据需要进一步丰富`lcd`的操作。

+ `lcddrv_open`

```
static int lcddrv_open(cfe_devctx_t *ctx)
{
    lcddev_t *lcd = ctx->dev_softc;

    fbcon_set_cursor(&lcd->con, 0, 0);

    return 0;
}
```

应用操作调用`cfe_open`时会被转发到这里的`lcddrv_open`来，`open`时调用`fbcon_set_cursor`设置字符输出的起始位置。

+ `lcddrv_write`

```
static int lcddrv_write(cfe_devctx_t *ctx,iocb_buffer_t *buffer)
{
    lcddev_t *lcd = ctx->dev_softc;
    fbcon_t *con = &lcd->con;

    unsigned char *bptr;
    int blen;

    bptr = buffer->buf_ptr;
    blen = buffer->buf_length;

    while ( blen > 0 )
    {
        fbcon_putc(con, *bptr);

        bptr++;
        blen--;
    }

    buffer->buf_retlen = buffer->buf_length - blen;

    lcd_sync(lcd);

    return 0;
}
```

应用操作调用`cfe_write`时会被转发到这里的`lcddrv_write`来，`write`操作只是调用`fbcon_putc`来逐个输出缓冲区的字符。

__`CFE`串口输出的是xterm格式，但这里原样逐个输出字符，实际上还需要在调用`fbcon_putc`前过滤处理转意字符，此处略去实现。__

+ `lcddrv_close`

```
static int lcddrv_close(cfe_devctx_t *ctx)
{
    return 0;
}
```

应用操作调用`cfe_close`时会被转发到这里的`lcddrv_write`来，`close`操作需要处理`open`时打开的一些资源，但由于`open`并没有分配额外的资源，这里的`close`就没有做任何操作。

+ 其它

    + 应用操作调用`cfe_ioctl`来进行一些额外的设置，如清屏，指定输出位置，指定输出颜色等，这部分操作可以通过定义`lcddrv_ioctl`来扩展。
    + 如果定义了`pull`操作，则`cfe`会在`background`任务中通过`PULL`操作来实现一些定期的任务，例如这里可以定义`lcddrv_poll`来实现光标的显示。

###3.5 显示内容管理

`fbcon.c`实现了显示内容的管理，主要围绕显示内容的更新操作，例如屏幕滚动，特殊字符的输出等。

+ `fbcon_set_cursor`

```
void fbcon_set_cursor(fbcon_t *con, int32_t row, int32_t col)
{
    con->cur_row = min(row, con->rows - 1);
    con->cur_col = min(row, con->cols - 1);

    return;
}
```

`fbcon_set_cursor`根据传入的参数设置当前的输出位置。

+ `fbcon_putc_xy`

```
static void fbcon_putc_xy(fbcon_t *con, uint32_t x, uint32_t y, char c)
{
    lcddev_t *lcd;
    uint32_t bg_color, fg_color;
    int i, row;
    fbptr_t *dst;

    lcd = con->lcd;
    bg_color = lcd->bg_color;
    fg_color = lcd->fg_color;

    dst = (fbptr_t *)con->start + y * lcd->width + x;

    for (row=0; row<VIDEO_FONT_HEIGHT; row++)
    {
        uint8_t bits = video_fontdata[c * VIDEO_FONT_HEIGHT + row];
        for (i=0; i<VIDEO_FONT_WIDTH; i++)
        {
            *dst++ = (bits & 0x80) ? fg_color : bg_color;
            bits <<= 1;
        }
        dst += (lcd->width - VIDEO_FONT_WIDTH);
    }
    return;
}
```

`fbcon_putc_xy`根据传入的位置参数和字符，从字库数据中获取对应字符的点阵并输出到屏幕上。

+ `fbcon_moverow`

```
static void fbcon_moverow(fbcon_t *con, uint32_t rowdst, uint32_t rowsrc)
{
    lcddev_t *lcd = con->lcd;
    int i;
    fbptr_t *src, *dst;

    /*
     * Note: this only works in full screen console
     */

    dst = (fbptr_t *)con->start + rowdst * VIDEO_FONT_HEIGHT * lcd->width;
    src = (fbptr_t *)con->start + rowsrc * VIDEO_FONT_HEIGHT * lcd->width;

    for (i=0; i<(VIDEO_FONT_HEIGHT * lcd->width); i++)
    {
        *dst++ = *src++;
    }
    return;
}
```

`fbcon_moverow`实现行复制，将指定的rowsrc行复制到rowdst行上。

+ `fbcon_setrow`

```
static void fbcon_setrow(fbcon_t *con, uint32_t row, uint32_t color)
{
    lcddev_t *lcd = con->lcd;
    int32_t i;
    fbptr_t *dst;

    /*
     * Note: this only works in full screen console
     */

    dst = (fbptr_t *)con->start + row * VIDEO_FONT_HEIGHT * lcd->width;

    for (i=0; i<(VIDEO_FONT_HEIGHT * lcd->width); i++)
    {
        *dst++ = color;
    }
    return;
}
```

`fbcon_setrow`使用指定的颜色color将制定的row行清空。

+ `fbcon_back`

```
static void fbcon_back(fbcon_t *con)
{
    if (--con->cur_col < 0)
    {
        con->cur_col = con->cols - 1;
        if (--con->cur_row < 0)
        {
            con->cur_row = 0;
        }
    }

    con->putc_xy(con,
        con->cur_col * VIDEO_FONT_WIDTH,
        con->cur_row * VIDEO_FONT_HEIGHT,
        ' ');

    return;
}
```

`fbcon_back`实现退格键'\b'的效果（光标往前移动一个位置，并将当前光标位置设置为空白）。

+ `fbcon_newline`

```
static void fbcon_newline(fbcon_t *con)
{
    lcddev_t *lcd = con->lcd;
    const int rows = CONSOLE_SCROLL_LINES;
    uint32_t i, bg_color = lcd->bg_color;

    con->cur_col = 0;

    /* Check if we need to scroll to the terminal */
    if (++con->cur_row >= con->rows)
    {
        for (i=0; i<con->rows-rows; i++)
            con->moverow(con, i, i+rows);
        for (i=0; i<rows; i++)
            con->setrow(con, con->rows-i-1, bg_color);
        con->cur_row -= rows;
    }
}
```

`fbcon_newline`调整光标位置，实现换行输出，如果换行的时候需要滚动屏幕，则还需要实现滚动屏幕的效果。

+ `fbcon_putc`

```
void fbcon_putc(fbcon_t *con, const char c)
{
    switch(c)
    {
    case '\r':
        con->cur_col = 0;
        break;
    case '\n':
        fbcon_newline(con);
        break;
    case '\t': /* Tab (8 chars alignment) */
        con->cur_col += 8;
        con->cur_col &= ~7;

        if (con->cur_col >= con->cols)
            fbcon_newline(con);
        break;
    case '\b':
        fbcon_back(con);
        break;
    default:
        con->putc_xy(con,
            con->cur_col * VIDEO_FONT_WIDTH,
            con->cur_row * VIDEO_FONT_HEIGHT,
            c);

        if (++con->cur_col >= con->cols)
            fbcon_newline(con);
        break;
    }

    return;
}
```

`fbcon_putc`在屏幕的当前位置输出指定的字符，是整个`fbcon`的字符输出接口，实现了退格、换行和制表等功能。

+ `fbcon_init`

```
void fbcon_init(fbcon_t *con, win_t *win, lcddev_t *lcd)
{
    con->x = win->x;
    con->y = win->y;
    con->w = win->w;
    con->h = win->h;

    con->cols = win->w / VIDEO_FONT_WIDTH;
    con->rows = win->h / VIDEO_FONT_HEIGHT;
    con->cur_col = 0;
    con->cur_row = 0;
    con->putc_xy = fbcon_putc_xy;
    con->moverow = fbcon_moverow;
    con->setrow = fbcon_setrow;
    con->start = (char *)lcd->base + (win->y * lcd->width + win->x) * NBYTES(lcd->bpp); /* console buffer maybe not continous */
    con->cmap = NULL;

    con->lcd = lcd;

    return;
}
```

`fbcon_init`根据传入的位置参数和`lcddev_t`参数初始化`fbcon_t`结构体。

###3.6 显示的初始化和调用
####1. 显示的初始化

+ `cfe_lcd_init`

在`cfe_min.c`文件中定义一个`cfe_lcd_init`函数，用于`lcd`设备的初始化：
```
/* 导入相关头文件 */
#include "dev_lcd.h"
#include "splash_script_load.h"

extern cfe_driver_t lcddrv;

/* 定义lcd设备的全局handle */
int hLcd = -1;
static void cfe_lcd_init(void)
{
    lcd_probe_t probe;

    memset(&probe, 0, sizeof(lcd_probe_t));

    probe.rotation = 0;
    probe.bpp = LCD_COLOR16;

    splash_get_surf_dimensions(&probe.width, &probe.height);

    probe.bg_color = CONSOLE_COLOR_BLACK;
    probe.fg_color = CONSOLE_COLOR_WHITE;

    /* console layout */
    probe.win.x = 0;
    probe.win.y = 0;
    probe.win.w = probe.width;
    probe.win.h = probe.height;

    //splash_get_surf_address(&probe.base, &pitch);
    probe.base = (void *)PHYS_TO_K0(SURFACE_MEM_ADDRS);

    /* 添加lcd设备 */
    cfe_add_device(&lcddrv, (unsigned long)&splash_bvn_init, NULL, &probe);

    /* 打开添加的设备并保存设备handle到全局变量hLcd中 */
    hLcd = cfe_open("lcd0");
    if (hLcd < 0) 
    {
        xprintf("cannot open lcd0\n");
        return;
    }

    return;
}
```

+ `cfe_main`

在函数`cfe_main`中，串口初始化后随即初始化`lcd`设备，以确保`lcd`能够输跟串口一样的信息而不会遗漏。

```
void cfe_main(int a,int b)
{
    ...

    /*
     * Initialize the console.  It is done before the other devices
     * get turned on.  The console init also sets the variable that
     * contains the CPU speed.
     */

    console_init();

    /* init lcd console */
    cfe_lcd_init();

    ...
}
```

####2. 显示输出调用

在串口输出的同时，根据初始化打开的`hLcd`句柄，调用`cfe_write`将内容输出到`lcd`上：

```
extern int hLcd;
int console_write(unsigned char *buffer,int length)
{
    ...

    /*
     * Do nothing if no console
     */

    if (console_handle == -1) return -1;

    /*
     * Write text to device
     */

    for (;;) {
    res = cfe_write(console_handle,buffer,length);
    if (hLcd != -1)
        cfe_write(hLcd, buffer, length);
        
    ...
    }

    if (res < 0) return -1;
    return 0;            
}
```

自此，当串口进行输出时，同时会将这些内容送往`lcd`显示。

###4. 其它
此版本的`cfe`中，`HDMI`默认的输出格式为`PAL`制的576p（即分辨率为720x576），如果需要更改为其它格式，如720P，1080i或VESA格式，则需要根据Broadcom的SDK中splashgen工具生成对应格式的显示寄存器再应用到`cfe`中。

最新的`cfe`中，`splash`显示部分有些变化，会针对高标清分别输出，所以在获取`surface`参数时有些不同，如果将这里的代码移植到最新的`cfe`上，需要对调用`splash_get_surf_xxx`函数进行调整。具体有如下几个函数：

+ `splash_get_surf_dimensions`
+ `splash_bvn_init`
+ `splash_get_surf_format`

由于博通`MIPS`平台机顶盒引导程序`CFE`和`ARM`平台的引导程序`BOLT`的设备管理操作和结构是一致的，所以也很容易将这部分代码实现移植到上`BOLT`上。**`BOLT`采用`device tree`向`linux`传递参数，这点跟`CFE`采用环境变量传递参数不一样，所以`BOLT上还需要将一些`lcd`参数更新到`device tree`中**









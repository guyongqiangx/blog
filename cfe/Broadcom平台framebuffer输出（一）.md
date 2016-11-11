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
###3.1 `SPLASH`显示
官方`CFE`代码不支持`framebuffer`驱动，所以不能进行任意的输出控制。但是`CFE`有个`SPLASH`功能，可以将存放在`flash`上的`BMP`图像作为开机`logo`显示。

对于`SPLASH`，实现分为几个步骤：

1. 指定显示使用的`surface memory`
2. 将`BMP`图像读取到内存
3. 加载预先生成的显示和输出相关寄存器
4. 将内存中的`BMP`图像输出到`surface memory`相应位置

###3.2 实现
显然，通过上一节中的步骤1和4，机顶盒已经完成了显示的初始化，具备了基本的显示能力，例如显示一个单色屏幕。

基于这个显示基础，通过操纵`surface memory`，实现命令行的输出。

功能上代码实现分为4个部分：

+ 字库数据（`font_8x16.h`）
+ 显示设备管理（`dev_lcd.c`）
+ 显示内容管理（`fbcon.c`）
+ 显示的初始化和调用（`cfe_main.c`, `cfe_console.c`）

####3.2.1 字库数据

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



####3.2.2 显示设备管理
`dev_lcd.c`中主要是围绕`CFE`设备管理的两个结构体进行操作：

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

+ 成员`lcddrv_probe`会根据传入的参数对`lcd`进行初始化
+ 成员`lcddrv_dispatch`提供了`lcd`设备的各种操作接口
+ 实现了open, write和close接口

####3.2.3 显示内容管理

####3.2.4 显示的初始化和调用










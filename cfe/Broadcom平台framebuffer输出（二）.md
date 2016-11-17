##Broadcom平台framebuffer输出（二）之Linux命令行输出到LCD

Broadcom平台framebuffer输出分为两部分：

+ 第一部分是bootloader，即CFE支持framebuffer的命令行显示；
+ 第二部分是linux，将linux的命令行通过framebuffer输出显示；

一旦bootloader和linux两部分都支持framebuffer，机顶盒一开机就能通过HDMI输出显示的命令行到外部设备。

>环境：
>
+ 硬件平台：`BCM97583`
+ `CFE` 版本：`bcm97583 cfe v3.7`
+ `Linux`版本：`stblinux-3.3-4.0` （`linux 3.3.8`的定制版本）
+ 输出方式：`HDMI`或`HDMI`转`DVI`

本文详细讲述第二部分，linux将命令行输出到LCD的实现。

##1. 简述
在第一部分<<__CFE 命令行输出到LCD__>>中已经实现了基于framebuffer的命令行显示，进入linux后需要基于CFE已经实现的framebuffer继续输出命令行。

__实际上进入linux后，linux也可以根据需要，不再复用CFE实现的framebuffer，而是自己再次进行显示的初始化和输出设置操作，但再次初始化可能会出现过渡时黑屏或者干扰的情况，直接使用CFE初始化好的显示和framebuffer会比较简单。__

`Linux`复用`CFE`的`framebuffer`需要在代码中实现`simplefb`驱动的支持，这个功能最初于2013-05-24出现在主分支上:
[`drivers/video: implement a simple framebuffer driver`](https://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/commit/?id=26549c8d36a64d9130e4c0f32412be7ba6180923)。

提交的描述中关于`simplefb`是这样写的：
>__drivers/video: implement a simple framebuffer driver__
>
>`A simple frame-buffer describes a raw memory region that may be rendered
to, with the assumption that the display hardware has already been set
up to scan out from that buffer.`
>
>`This is useful in cases where a bootloader exists and has set up the
display hardware, but a Linux driver doesn't yet exist for the display
hardware.`

好吧，支持`simplefb`的第一版代码是`3.10`，当前我们使用的`linux`版本为`3.3`，还没有实现对`simplefb`的支持，所以需要将`simplefb`从新版本的`linux`（本文基于`3.14.28`）向后移植到当前使用的`stblinux-3.3-4.0`中。

##2. 效果预览
`Linux`命令行(`720x576`)通过`HDMI`转`DVI`输出到显示器：

![Linux命令行输出到LCD](https://github.com/guyongqiangx/blog/blob/dev/cfe/images/kernel.jpg?raw=true)

`linux`启动后可以直接插上USB键盘，进行跟PC一样的终端输入，可以不再依赖串口进行输入输出控制了。

##3. 代码实现

###3.1 `simplefb`移植

从`linux 3.14.28`上移植`simplefb`驱动到`stblinux-3.3-4.0`比较简单：

+ 复制文件`simplefb.c`到`drivers\video`目录
+ 复制文件`simplefb.h`到`include\linux\platform_data`目录
+ 修改`drivers\video\Kconfig`，添加`FB_SIMPLE`配置节：
```
config FB_SIMPLE
    bool "Simple framebuffer support"
    depends on (FB = y)
    select FB_CFB_FILLRECT
    select FB_CFB_COPYAREA
    select FB_CFB_IMAGEBLIT
    help
      Say Y if you want support for a simple frame-buffer.

      This driver assumes that the display hardware has been initialized
      before the kernel boots, and the kernel will simply render to the
      pre-allocated frame buffer surface.

      Configuration re: surface address, size, and format must be provided
      through device tree, or plain old platform data.
```
+ 修改`drivers\video\Makefile`，添加对`simplefb.o`的编译，使`FB_SIMPLE`配置生效：
```
obj-$(CONFIG_FB_SIMPLE)           += simplefb.o
```

这个时候打开`CONFIG_FB_SIMPLE`选项已经可以通过编译了，然而光这样做并没有卵用，因为`simplefb`模块还需要参数进行初始化。

###3.2 `simplefb`参数
文档`documentation\devicetree\bindings\video\simple-framebuffer.txt`有提到对`simplefb`支持的说明：

```
Simple Framebuffer
A simple frame-buffer describes a raw memory region that may be rendered to, with the assumption that the display hardware has already been set up to scan out from that buffer.
Required properties:
- compatible: "simple-framebuffer"
- reg: Should contain the location and size of the framebuffer memory.
- width: The width of the framebuffer in pixels.
- height: The height of the framebuffer in pixels.
- stride: The number of bytes in each line of the framebuffer.
- format: The format of the framebuffer surface. Valid values are:
  - r5g6b5 (16-bit pixels, d[15:11]=r, d[10:5]=g, d[4:0]=b).
  - a8b8g8r8 (32-bit pixels, d[31:24]=a, d[23:16]=b, d[15:8]=g, d[7:0]=r).
Example:
    framebuffer { compatible = "simple-framebuffer";
        reg = <0x1d385000 (1600 * 1200 * 2)>;
        width = <1600>;
        height = <1200>;
        stride = <(1600 * 2)>;
        format = "r5g6b5";
    }; 
```

可见，实现`simplefb`支持还需要提供一系列的属性参数，在ARM平台下这些参数都是通过`devicetree`机制传递和设置。

但`MIPS`平台并不支持`devicetree`，那如何解决这个问题呢？

检查代码`simplefb_probe`，`probe`过程中会先调用`dev_get_platdata`看否能够获取`platdata`，如果成功，则使用获取的参数进行初始化，否则才解析`devicetree`获取参数：

```
static int simplefb_probe(struct platform_device *pdev)
{
    int ret;
    struct simplefb_params params;
    struct fb_info *info;
    struct resource *mem;

    ...
    /* 尝试获取platform data */
    if (dev_get_platdata(&pdev->dev))
        ret = simplefb_parse_pd(pdev, &params); /* 解析platform data */
    /* 获取platform data失败后检查device tree */
    else if (pdev->dev.of_node)
        ret = simplefb_parse_dt(pdev, &params); /* 解析device tree */

    if (ret)
        return ret;

    /*
     * 获取注册的resource
     *      device tree机制通过reg属性关联，启动时自动解析
     *      非device tree机制需要在初始化时调用platform_device_add_resources来关联
     */
    mem = platform_get_resource(pdev, IORESOURCE_MEM, 0);
    if (!mem) {
        dev_err(&pdev->dev, "No memory resource\n");
        return -EINVAL;
    }
    ...

    return 0;
}
```

既然不支持`devicetree`，那就构造一个`platform_data`让`simplefb`模块在初始化时进行解析吧，这样我们留不需要修改`simplefb`驱动本身了。

`simplefb.h`中定义了一个`simplefb_platform_data`结构用于在`simplefb_parse_pd`内解析参数：

`simplefb.h`:
```
/*
 * Simple-Framebuffer description
 * If the arch-boot code creates simple-framebuffers without DT support, it
 * can pass the width, height, stride and format via this platform-data object.
 * The framebuffer location must be given as IORESOURCE_MEM resource.
 * @format must be a format as described in "struct simplefb_format" above.
 */
struct simplefb_platform_data {
    u32 width;
    u32 height;
    u32 stride;
    const char *format;
};
```

`simplefb.c`:
```
static int simplefb_parse_pd(struct platform_device *pdev,
                 struct simplefb_params *params)
{
    struct simplefb_platform_data *pd = dev_get_platdata(&pdev->dev);
    int i;

    params->width = pd->width;
    params->height = pd->height;
    params->stride = pd->stride;

    params->format = NULL;
    for (i = 0; i < ARRAY_SIZE(simplefb_formats); i++) {
        if (strcmp(pd->format, simplefb_formats[i].name))
            continue;

        params->format = &simplefb_formats[i];
        break;
    }

    if (!params->format) {
        dev_err(&pdev->dev, "Invalid format value\n");
        return -EINVAL;
    }

    return 0;
}
```

那就在初始化时构造一个`platform data`数据给`simplefb`模块使用吧。


###3.3 注册`simplefb`参数
在`drivers\brcmstb\setup.c`中定义一个函数`brcm_register_simplefb`用于准备`simplefb`模块需要的参数：

```
#ifdef CONFIG_FB_SIMPLE
/* Display/Framebuffer */
unsigned long brcm_surface_start;       /* framebuffer起始地址 */
unsigned long brcm_surface_len;         /* framebuffer大小 */
unsigned long brcm_disp_width;          /* display输出的width，以pixel为单位 */
unsigned long brcm_disp_heigth;         /* display输出的height，以pixel为单位 */
unsigned long brcm_disp_stride;         /* display时每一行占用的字节数，也称为pitch */
char brcm_disp_format[CFE_STRING_SIZE]; /* display的像素格式字符串，如`r5g6b5` */

static int __init brcm_register_simplefb(void)
{
    struct resource res;
    struct platform_device *pdev;
    struct simplefb_platform_data pdata;

    if (brcm_surface_len == 0)
        return -ENODEV;

    /* 根据framebuffer的起始地址和大小构造一个resource结构，类型是内存数据IORESOURCE_MEM */
    memset(&res, 0, sizeof(res));
    res.start = brcm_surface_start;
    res.end = res.start + brcm_surface_len - 1;
    res.flags = IORESOURCE_MEM;

    /* 使用width, height, stride和format数据填充platform data */
    memset(&pdata, 0, sizeof(pdata));
    pdata.width = brcm_disp_width;
    pdata.height = brcm_disp_heigth;
    pdata.stride = brcm_disp_stride;
    pdata.format = brcm_disp_format;

    /* 分配一个simple-framebuffer结构体 */
    pdev = platform_device_alloc("simple-framebuffer", -1);
    if (!pdev ||
        /* 与device关联构造的resource */
        platform_device_add_resources(pdev, &res, 1) ||
        /* 与device关联构造的platform data */
        platform_device_add_data(pdev, &pdata, sizeof(pdata)) ||
        /* 将device设备添加到platform总线 */
        platform_device_add(pdev)) {
        printk(KERN_WARNING
            "%s: register simple-framebuffer device failed\n", __func__);
        platform_device_put(pdev);
        return -ENODEV;
    }
    else
    {
        printk(KERN_WARNING "Register simple-framebuffer device\n");
    }

    return 0;
}
#endif
```

在`platform_device_setup`中调用`brcm_register_simplefb`注册`simplefb`参数：
```
static int __init platform_devices_setup(void)
{
    ...

    /* 注册simplefb参数 */
#if defined(CONFIG_FB_SIMPLE)
    brcm_register_simplefb();
#endif

    return 0;
}
```

这里定义了一组用于填充`resource`和`platform data`的变量：
```
unsigned long brcm_surface_start;
unsigned long brcm_surface_len;
unsigned long brcm_disp_width;
unsigned long brcm_disp_heigth;
unsigned long brcm_disp_stride;
char brcm_disp_format[CFE_STRING_SIZE];
```
那这些变量该设置什么值，以及如何设置呢？

###3.4 从`CFE`获取设置`simplefb`属性的变量：

`simplefb`所采用的参数实际上在`CFE`里面已经定义好了，比如`framebuffer`的地址和大小，显示输出的width, height以及各式等。显然，用于`simplefb`设置的这些参数最好是从`CFE`中获取。

通常，`bootloader`可以通过`ATAGS`或`devicetree`来传递参数，也可以通过`SLRAM`设备来传递数据（见[`bootloader`使用`SLRAM`设备向`Kernel`传递块数据](http://blog.csdn.net/guyongqiangx/article/details/52201642)）。
在`Broadcom`的`MIPS`平台上，没有采用以上方式，而采用了一个特别的方法使`linux`从`CFE`获取环境变量：

__`CFE`启动`Kernel`时会通过寄存器`a2`传递一个句柄参数`cpu_apientry`__
`cpu_apientry`是一个函数，是外部程序调用`CFE`函数的入口，具体信息见函数注释：
```
/*  *********************************************************************
    *  cpu_apientry(handle,iocb)
    *
    *  API entry point for external apps.
    *  
    *  Input parameters: 
    *      a0 - firmware handle (used to determine the location of
    *           our relocated data)
    *      a1 - pointer to IOCB to execute
    *      
    *  Return value:
    *      v0 - return code, 0 if ok
    ********************************************************************* */
LEAF(cpu_apientry)

        ...

        HAZARD
        j   ra
        nop

END(cpu_apientry)
```

<font color="red">`kernel`启动时保存寄存器`a2`的参数，即这里的`cpu_apientry`，用于回调获取`CFE`的环境变量。关于`linux`回调获取`CFE`环境变量的机制后面我会专门写一遍博客来分析，此处暂且略过。</font>

文件`arch\mips\brcmstb\prom.c`中，函数`cfe_read_configuration`用于获取`CFE`的环境变量，在其中添加对`simplefb`相关的环境变量的获取，并存放到相应的变量中：

```
/* kernel读取CFE运行时设置的环境变量 */
static void __init __maybe_unused cfe_read_configuration(void)
{
    int fetched = 0;

    /* 检查signature */
    printk(KERN_INFO "Fetching vars from bootloader... ");
    if (cfe_seal != CFE_EPTSEAL) {
        printk(KERN_CONT "none present, using defaults.\n");
        return;
    }

    ...

    /* FETCH宏用于从CFE获取单个环境变量 */
#define FETCH(name, fn, arg) do { \
    if (cfe_getenv(name, cfe_buf, COMMAND_LINE_SIZE) == CFE_OK) { \
        DPRINTK("Fetch var '%s' = '%s'\n", name, cfe_buf); \
        fn(cfe_buf, arg); \
        fetched++; \
    } else { \
        DPRINTK("Could not fetch var '%s'\n", name); \
    } \
    } while (0)

    ...

    /* 从CFE获取framebuffer显示的属性 */
#ifdef CONFIG_FB_SIMPLE
    FETCH("LCD_SURFACE_ADDR", parse_hex, &brcm_surface_start);
    FETCH("LCD_SURFACE_SIZE", parse_hex, &brcm_surface_len);
    FETCH("LCD_DISP_WIDTH", parse_ulong, &brcm_disp_width);
    FETCH("LCD_DISP_HEIGHT", parse_ulong, &brcm_disp_heigth);
    FETCH("LCD_DISP_STRIDE", parse_ulong, &brcm_disp_stride);
    FETCH("LCD_DISP_FORMAT", parse_string, brcm_disp_format);
#endif

    printk(KERN_CONT "found %d vars.\n", fetched);
}
```

通过以上操作，`kernel`可以获取`CFE`的`framebuffer`设置了。接下来就需要在`CFE`下设置这几个环境变量。

###3.5 `CFE`设置`framebuffer`相关环境变量

`dev_lcd.c`中，初始化显示设备时将`framebuffer`信息写入环境变量，这样在`kernel`启动后就可以读取这些设置了：

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

    probe = (lcd_probe_t *)probe_ptr;

    softc = (lcddev_t *)KMALLOC(sizeof(lcddev_t), 0);
    if (softc)
    {
        memset(softc, 0, sizeof(lcddev_t));

        if (probe)
        {
            ...

            fbcon_init(&softc->con, &win, softc);

            /* 设置framebuffer相关环境变量 */
            /* setup simple-framebuffer envs */

            /* framebuffer基址 */
            xsprintf(buffer,"%x", K0_TO_PHYS((unsigned long)softc->base));
            env_setenv("LCD_SURFACE_ADDR", buffer, ENV_FLG_BUILTIN | ENV_FLG_READONLY);
            /* framebuffer大小 */
            xsprintf(buffer,"%x", softc->pitch * softc->height);
            env_setenv("LCD_SURFACE_SIZE", buffer, ENV_FLG_BUILTIN | ENV_FLG_READONLY);

            /* display输出的width，以pixel为单位 */
            xsprintf(buffer,"%d", softc->width);
            env_setenv("LCD_DISP_WIDTH",buffer, ENV_FLG_BUILTIN | ENV_FLG_READONLY);
            /* display输出的height，以pixel为单位 */
            xsprintf(buffer,"%d", softc->height);
            env_setenv("LCD_DISP_HEIGHT", buffer, ENV_FLG_BUILTIN | ENV_FLG_READONLY);
            /* display时每一行占用的字节数，也称为pitch */
            xsprintf(buffer,"%d", softc->pitch);
            env_setenv("LCD_DISP_STRIDE", buffer, ENV_FLG_BUILTIN | ENV_FLG_READONLY);

            /* display的像素格式字符串，如`r5g6b5 */
            splash_get_surf_format(&format);
            if (format == BPXL_eA8_R8_G8_B8)
            {
                xsprintf(buffer, "%s", "a8r8g8b8");
            }
            else /* (format == BPXL_eR5_G6_B5 ) */
            {
                xsprintf(buffer,"%s", "r5g6b5");
            }
            env_setenv("LCD_DISP_FORMAT", buffer, ENV_FLG_BUILTIN | ENV_FLG_READONLY);

            ...
        }
    }

    return;
}
```

以上几步操作逆序来看（这是正常的启动顺序）：
+ `CFE`启动显示输出，并将`framebuffer`属性写入环境变量
+ `linux`启动后从`CFE`获取环境变量
+ `linux`用所获取的环境变量构造`simplefb_platform_data`数据，并添加到`platform`总线上
+ `linux`模块初始化时会匹配`simplefb_platform_data`数据相应的模块`simplefb`，并调用`simplefb`的`probe`函数注册`framebuffer`

经过以上几步操作，`linux`里面`simplefb`模块就可以正常加载了。

###3.5 `linux`命令行`console`输出到`fb0`

`linux`的`simplefb`加载后会在`/dev`下添加`fb0`设备，为了让`linux`将命令行`console`输出到`fb0`，还需要在配置`linux`时打开一些宏设置：

+ 勾选`framebuffer`选项 `[CONFIG_FB=y]`
```
Device Drivers --->
    Graphics support --->
        <*> Support for frame buffer devices --->
```

+ 勾选`framebuffer`选项下的`simplefb`子选项 `[CONFIG_FB_SIMPLE=y]`
```
Device Drivers  --->
    Graphics support --->
        <*> Support for frame buffer devices --->
            --- Support for frame buffer devices
            [*] Simple framebuffer support
```
根据`drivers\video\Kconfig`中`config FB_SIMPLE`一节的设置，当启用`CONFIG_FB_SIMPLE=y`后会自动设置以下选项：
>
>     * `CONFIG_FB_CFB_FILLRECT=y`
>     * `CONFIG_FB_CFB_COPYAREA=y`
>     * `CONFIG_FB_CFB_IMAGEBLIT=y`


+ 勾选`framebuffer console`选项 `[CONFIG_FRAMEBUFFER_CONSOLE=y]`
```
Device Drivers --->
    Graphics support --->
        Console display driver support --->
            <*> Framebuffer Console support
```

+ 勾选`VGA 8x16 font`选项 `[CONFIG_FONTS=y, CONFIG_FONT_8x16=y]`
```
Device Drivers --->
    Graphics support --->
        Console display driver support --->
            [*] Select compiled-in fonts
                [ ] VGA 8x8 font
                [*] VGA 8x16 font
```

打开`framebuffer console`选项后，默认会编译`VGA 8x8 font`和`VGA 8x16 font`两种字体，所以这里也可以不用考虑，让`linux`自动包含默认的字体。

+ 勾选`Bootup logo`选项 `[CONFIG_LOGO=y]`
```
Device Drivers --->
    Graphics support --->
        Console display driver support --->
            [*] Bootup logo --->
                --- Bootup logo
                [ ] Standard black and white Linux logo
                [ ] Standard 16-color Linux logo
                [*] Standard 224-color Linux logo
```

如果需要在屏幕的左上角显示`logo`，则勾选这里的`Bootup logo`选项，默认会包含3中可选的`logo`，这里只选择了224色的`log` `[CONFIG_LOGO_LINUX_CLUT224=y]`

也可以不用选择显示`logo`图案 `[CONFIG_LOGO=n]`

+ 勾选`Support for console on virtual terminal`选项 `[CONFIG_VT_CONSOLE=y]`
```
Device Drivers --->
    Character devices --->
        [*] Virtual terminal
            [ ] Enable character tranlsations in console
            [*] Support for console on virtual terminal
            [ ] Support for binding and unbingding console drivers
```

只有设置了这一项以后，`linux`才会将终端显示的字符送往`framebuffer`。另外，这里勾选后也会自动打开选项`[CONFIG_VT_CONSOLE_SLEEP=y]`，即当终端没有活动时，10分钟后`linux`将关闭`framebuffer`输出，当终端有活动时再打开`framebuffer`显示。

完成配置后重新编译`kernel`，这里我默认编译带文件系统的`vmlinuz-initrd-7584a0`，这样我测试时就不再需要另外单独准备文件系统了。

##4. `CFE`启动`linux`

这里测试时通过`tftp`加载编译的`kernel`文件：
```
CFE> boot -z -elf 192.168.1.100:7584a0/vmlinuz-initrd-7584a0 'console=tty0'
```

这里需要特别指定参数`console=tty0`，这样在`linux`启动后才会将`console`输出到`tty0`对应的终端`fb0`，即我们指定的`framebuffer`，否则还会继续将信息发送到串口。

##5. 其它

完整的启动`log`信息如下：

```
CFE> boot -z -elf 192.168.1.95:vmlinuz-initrd-7584a0 'console=tty0'
Loader:elf Filesys:tftp Dev:eth0 File:192.168.1.95:vmlinuz-initrd-7584a0 Options:console=tty0
Loading: 0x80001000/12051456 0x80b7f400/118032 Entry address is 0x80470260
Closing network.
Starting program at 0x80470260

Linux version 3.3.8-4.0pre (ygu@fs-ygu.corp.ad.temp.com) (gcc version 4.5.4 (Broadcom stbgcc-4.5.4-2.9) ) #65 SMP Thu Nov 17 16:26:40 CST 2016
Fetching vars from bootloader... found 20 vars.
Options: moca=0 sata=1 pcie=0 usb=1
Using 512 MB + 0 MB RAM (from CFE)
bootconsole [early0] enabled
CPU revision is: 0002a065 (Broadcom BMIPS4380)
FPU revision is: 00130001
Determined physical RAM map:
 memory: 10000000 @ 00000000 (usable)
 memory: 10000000 @ 20000000 (usable)
bmem: adding 192 MB RESERVED region at 64 MB (0x0c000000@0x04000000)
Initrd not found or empty - disabling initrd
Zone PFN ranges:
  Normal   0x00000000 -> 0x00030000
Movable zone start PFN for each node
Early memory PFN ranges
    0: 0x00000000 -> 0x00010000
    0: 0x00020000 -> 0x00030000
PERCPU: Embedded 7 pages/cpu @81606000 s5120 r8192 d15360 u32768
Built 1 zonelists in Zone order, mobility grouping on.  Total pages: 129536
Kernel command line: console=tty0
PID hash table entries: 2048 (order: 1, 8192 bytes)
Dentry cache hash table entries: 65536 (order: 6, 262144 bytes)
Inode-cache hash table entries: 32768 (order: 5, 131072 bytes)
Primary instruction cache 32kB, VIPT, 2-way, linesize 64 bytes.
Primary data cache 64kB, 4-way, VIPT, cache aliases, linesize 64 bytes
Memory: 309160k/524288k available (4629k kernel code, 215128k reserved, 1110k data, 6032k init, 0k highmem)
Hierarchical RCU implementation.
NR_IRQS:160
Measuring MIPS counter frequency...
Detected MIPS clock frequency: 742 MHz (371.267 MHz counter)
Console: colour dummy device 80x25
console [tty0] enabled, bootconsole disabled
```

但这里存在的一个问题是，最后一行输出`console [tty0] enabled, bootconsole disabled`之后，控制完全转移到了`HDMI`输出终端（即显示器），串口不再响应输入，也没有输出。

这样比较不方便，可以通过修改`uclinux-rootfs\skel\etc`文件夹下的`inittab`文件，让系统启动后在串口`ttyS0`启动一个`shell`来响应串口的输入，更改如下：
```
# Put a shell on the serial port
ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt102
```

这样在`linux`启动后串口又可以工作了，只是此时串口`ttyS0`和`HDMI`输出`tty0`是两个不同的终端了。

##6. `patch`

##1. `CFE`中的`splash`

`CFE`启动后，初始化各种设备，然后初始化显示相关的寄存器，从`flash`中读取图片`splash.bmp`并绘制到`surface memory`区域。

由于`splash`存放在`flash`的分区中，所以必须要等待`flash`驱动完成初始化后，读取出图像`splash.bmp`才能显示。

那如果想`CFE`一启动就显示`splash`呢？显然最好是将`splash.bmp`嵌入到代码中。

本文基于机顶盒上使用的`CFE v15.2`版本将`splash.bmp`编译嵌入到`cfe.bin`中，并在启动时显示图像。

##2. 生成可连接的目标文件`splash.bmp.o`

`GNU binutils`的`objcopy`工具用途比较广泛，其中一项就是各种目标文件之间的转换。
因此使用`objcopy`可以将任意文件转换为可以连接的目标文件，参与生成最终的可以执行文件。

###2.1 `sde-objcopy`
`CFE`编译使用`MIPS`提供的工具套件`MIPS SDE v5.03`，这是一个相当老的工具套件了，`gcc`版本只有`2.96`，`objcopy`版本为`2.9`，如下：
```
ygu@ubuntu:/opt/cfe_v15.2$ sde-gcc -v
Reading specs from /opt/toolchains/sde-v5.03/bin/../lib/gcc-lib/sde/2.96-mipssde-031117/specs
gcc version 2.96-mipssde-031117

ygu@ubuntu:/opt/cfe_v15.2$ sde-objcopy -V
GNU objcopy 2.9-mipssde-031003
Copyright 1997, 98, 99, 2000 Free Software Foundation, Inc.
This program is free software; you may redistribute it under the terms of
the GNU General Public License.  This program has absolutely no warranty.
```

对于`sde-objcopy`甚至还不支持`-B`选项，我曾经尝试用`sde-objcopy`去转换`splash.bmp`，但最终都失败了。最后手动用编译应用的`mipsel-linux-objcopy`将`splash.bmp`转换为可连接的目标文件`splash.bmp.o`后，再将这个可连接文件用于最终`CFE`的生成。


###2.2 使用`mipsel-linux-objcopy`工具进行转换
####2.2.1 `-B mipsisa32`选项
转换命令如下（此处使用的是`stbgcc-4.5.4-2.9`包中的`objcopy`）：

```
ygu@ubuntu:/opt/cfe_v15.2$ mipsel-linux-objcopy -I binary -O elf32-tradlittlemips -B mipsisa32 splash.bmp splash.bmp.o
```

用`file`命令查看生成的可连接文件：
```
ygu@ubuntu:/opt/cfe_v15.2$ file splash.bmp.o 
splash.bmp.o: ELF 32-bit LSB  relocatable, MIPS, MIPS32 version 1 (SYSV), not stripped
```

再用`file`查看下`cfe`编译生成的其它文件，如`cfe_main.o`：
```
ygu@ubuntu:/opt/cfe_v15.2/build/7584$ file cfe_main.o
cfe_main.o: ELF 32-bit LSB  relocatable, MIPS, MIPS32 version 1 (SYSV), not stripped
```

可见手动生成的`splash.bmp.o`和`cfe_main.o`格式是一致的。

####2.2.2 `-B mips`选项
如果`objcopy`使用`-B mips`而不是`-B mipsisa32`选项进行转换，则由于指定`cpu`架构不一致而存在问题。
```
ygu@ubuntu:/opt/cfe_v15.2$ mipsel-linux-objcopy -I binary -O elf32-tradlittlemips -B mips splash.bmp splash.bmp.o
ygu@ubuntu:/opt/cfe_v15.2$ file splash.bmp.o 
splash.bmp.o: ELF 32-bit LSB  relocatable, MIPS, MIPS-I version 1 (SYSV), not stripped
```

仔细查看`file`命令的输出，这里生成的是`MIPS-I version 1`的格式，跟`CFE`原生编译生成的格式不一样。

###2.3 使用`nm`工具检查符号

使用`objcopy`工具生成的可连接文件`objfile`会内置三个位置相关的符号变量`_binary_objfile_start`, `_binary_objfile_end`和`_binary_objfile_size`，可以用`nm`工具查看。

这里使用`mipsel-linux-nm`检查生成文件`splash.bmp.o`中的符号：

```
ygu@ubuntu:/opt/cfe_v15.2$ mipsel-linux-nm -a splash.bmp.o  
00000000 d .data
0006b892 D _binary_splash_bmp_end
0006b892 A _binary_splash_bmp_size
00000000 D _binary_splash_bmp_start
```

可见生成了三个符号变量，名字也很直观：
+ `_binary_splash_bmp_start`指示`bmp`数据开始的位置
+ `_binary_splash_bmp_end`指示`bmp`数据结束的位置
+ `_binary_splash_bmp_size`指示`bmp`数据的大小

##3. `CFE`链接`splash.bmp.o`

将生成的`splash.bmp.o`放到`splash`目录下，然后在编译系统中添加对`splash.bmp.o`的编译引用：

###3.1 链接`splash.bmp.o`生成`ssbl`
在`cfe_link.mk`文件中修改`ssbl`的生成规则，让其链接`splash.bmp.o`:
```
ssbl ssbl.bin:  $(DEV_OBJS) $(COMMON_OBJS) $(ECM_OBJS) $(LIBCFE) splash.bmp.o
    $(GLD) -o ssbl -Map ssbl.map $(SSBL_LDFLAGS) -L.  $(DEV_OBJS) $(COMMON_OBJS) $(ECM_OBJS) splash.bmp.o -lcfe  $(LDLIBS)
```

###3.2 复制`splash.bmp.o`到编译目录
3.1节中指定的`splash.bmp.o`默认的位置在`build/7xxx`下，即跟编译生成的文件在同一个地方，但我们预先生成了`splash.bmp.o`，所以还需要添加规则将`splash.bmp.o`从`splash`目录复制到当前目录来。
在`cfe.mk`中添加这个规则：
```
# copy splash/splash.bmp.o to build dir
splash.bmp.o : ../../splash/splash.bmp.o
    @echo 'copy $(notdir $<)'
    @cp -rf $< $@
```

添加以上两个规则后，就可以顺利将`splash.bmp.o`嵌入到生成的`cfe.bin`中了。

###3.3 编译时生成``splash.bmp.o`
如果预先设置了`mipsel-linux-objcopy`的路径也可以在编译时才生成`splash.bmp.o`，则`cfe.mk`中生成`splash.bmp.o`的规则如下：
```
splash.bmp.o : splash.bmp
   @echo 'mipsel-linux-objcopy $(notdir $<)'
   @mipsel-linux-objcopy -I binary -O elf32-tradlittlemips -B mipsisa32 $^ $@
```

###4. `CFE`中引用`splash.bmp.o`的数据

默认情况下，`CFE`的`cfe_splash`函数会先从`flash`中读取图片，然后再显示。
这里我们对这个函数稍作修改，使其直接显示`cfe.bin`中内嵌的图片，修改如下：
(`cfe_main.c`中的`cfe_splash`函数)

```
/* 声明splash.bmp.o中的位置相关的外部变量 */
extern unsigned long _binary_splash_bmp_start;
extern unsigned long _binary_splash_bmp_end;
extern unsigned long _binary_splash_bmp_size;

void cfe_splash()
{
    BMP_HEADER_INFO bmpinfo[2];
    int x,y;
    void *surfaceMemory[2];
    void *bmpMemory[2];
    int ii;

    /* PORT POINT: if you have more than 2 surfaces */
    surfaceMemory[0] = (void *)PHYS_TO_K0(SURFACE_MEM_ADDRS);
    surfaceMemory[1] = (void *)PHYS_TO_K0(SURFACE_MEM_ADDRS_1);

    /* 直接引用bmp数据的起始地址 */
    bmpMemory[0] = (void *)&_binary_splash_bmp_start;;
    bmpMemory[1] = (void *)&_binary_splash_bmp_start;;

    for(ii=0; ii<g_ulNumSurface; ii++)
    {
        /* 解析bmp头部结构，获取bmp图片信息 */
        if(splash_bmp_getinfo(bmpMemory[ii], &bmpinfo[ii]) != 0 ||
            bmpinfo[ii].header.size > SPLASH_IMAGE_SIZE ||
            bmpinfo[ii].header.offset > SPLASH_HDR_SIZE)
        {
            if (ii == 0)
            {
                xprintf("No valid image found in " SPLASH_IMAGE_FILE " - disabling splash\n");
                return ;
            }
            else
            {
                bmpinfo[ii] = bmpinfo[0];
            }
        }

        /* 输出bmp的一些调试信息 */
        xprintf("Found splash image %d - Width = %d Height = %d at: [0x%08x - 0x%08x, %d bytes]\n",
                ii, bmpinfo[ii].info.width, bmpinfo[ii].info.height,
                (unsigned long *)&_binary_splash_bmp_start,
                (unsigned long *)&_binary_splash_bmp_end,
                (unsigned long)&_binary_splash_bmp_size);

#ifdef SPLASH_SURFACE_SELECT_ENABLED
        surfaceMemory[ii] = g_pvSplashSurfaceAddr[ii];
#endif
        BMEM_ConvertAddressToOffset(NULL, surfaceMemory[ii], &g_SplashInfo.aulSurfaceBufOffset[ii]);
    }

    splash_bvn_init(NULL, &g_SplashInfo);
    
    /* 以下部分没有修改，同原函数 */
    ...
}

```

修改后编译生成`cfe.bin`，烧写到机顶盒上就可以在开机启动时显示内嵌到`cfe`里面的图像数据。

##5. 其它
不仅可以转换图片数据，`objcopy`还可以将任何格式的文件转换为可连接的目标文件，如字体、固件等，比较灵活也比较方便。

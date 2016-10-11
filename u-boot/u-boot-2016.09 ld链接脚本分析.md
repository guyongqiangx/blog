# u-boot-2016.09 ld链接脚本分析

##1. 链接脚本的生成

###1.1 指定脚本文件源码
顶层`Makefile`中会根据设置指定链接的脚本文件：
```makefile
# If board code explicitly specified LDSCRIPT or CONFIG_SYS_LDSCRIPT, use
# that (or fail if absent).  Otherwise, search for a linker script in a
# standard location.

ifndef LDSCRIPT
    #LDSCRIPT := $(srctree)/board/$(BOARDDIR)/u-boot.lds.debug
    ifdef CONFIG_SYS_LDSCRIPT
        # need to strip off double quotes
        LDSCRIPT := $(srctree)/$(CONFIG_SYS_LDSCRIPT:"%"=%)
    endif
endif

# If there is no specified link script, we look in a number of places for it
ifndef LDSCRIPT
    ifeq ($(wildcard $(LDSCRIPT)),)
        LDSCRIPT := $(srctree)/board/$(BOARDDIR)/u-boot.lds
    endif
    ifeq ($(wildcard $(LDSCRIPT)),)
        LDSCRIPT := $(srctree)/$(CPUDIR)/u-boot.lds
    endif
    ifeq ($(wildcard $(LDSCRIPT)),)
        LDSCRIPT := $(srctree)/arch/$(ARCH)/cpu/u-boot.lds
    endif
endif
```

对于树莓派3来说，生成链接脚本使用模板文件：`arch/arm/cpu/u-boot.lds`

###1.2 脚本文件生成规则

`u-boot`链接最终所使用的`u-boot.lds`位于根目录下，需要通过编译才能生成。

+ 顶层`Makefile`中定义的的生成规则：
```makefile
quiet_cmd_cpp_lds = LDS     $@
cmd_cpp_lds = $(CPP) -Wp,-MD,$(depfile) $(cpp_flags) $(LDPPFLAGS) \
        -D__ASSEMBLY__ -x assembler-with-cpp -P -o $@ $<

u-boot.lds: $(LDSCRIPT) prepare FORCE
    $(call if_changed_dep,cpp_lds)
```

+ `.u-boot.lds.cmd`中关于生成`u-boot.lds`的命令：
```shell
cmd_u-boot.lds := arm-linux-gnueabi-gcc -E -Wp,-MD,./.u-boot.lds.d \
    -D__KERNEL__ -D__UBOOT__   -D__ARM__ \
    -marm -mno-thumb-interwork  -mabi=aapcs-linux  -mword-relocations  \
    -fno-pic  -mno-unaligned-access  \
    -ffunction-sections -fdata-sections \
    -fno-common -ffixed-r9  \
    -msoft-float   -pipe  -march=armv7-a \
    -D__LINUX_ARM_ARCH__=7  \
    -I./arch/arm/mach-bcm283x/include -Iinclude   \
    -I./arch/arm/include -include ./include/linux/kconfig.h  \
    -nostdinc -isystem /usr/lib/gcc-cross/arm-linux-gnueabi/4.7/include \
    -ansi -include ./include/u-boot/u-boot.lds.h \
    -DCPUDIR=arch/arm/cpu/armv7  -D__ASSEMBLY__ \
    -x assembler-with-cpp -P -o u-boot.lds arch/arm/cpu/u-boot.lds
```

> 编译命令中`-E`和`-P`选项比较特别：
> 
> + `-E` 指示`gcc`只进行编译，不进行链接
> + `-P` 指示`gcc`在输出文件中不输出`linemarkers`，适合预处理器对`u-boot.lds`这样的非`C`代码的预处理。

##2. 链接脚本析
+ `UEFI`支持

`u-boot`自`2016.05`版本开始增加对`UEFI`的支持。

> `UEFI`参考：
> 
> + [Unified Extensible Firmware Interface](https://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface)
> + [U-Boot Now Supports UEFI on 32-bit and 64-bit ARM Platforms](http://www.cnx-software.com/2016/08/11/u-boot-now-supports-uefi-on-32-bit-and-64-bit-arm-platforms/)
> + [\[U-Boot\] \[PATCH 00/16\] EFI payload / application support v3](http://lists.denx.de/pipermail/u-boot/2016-February/244378.html)

`u-boot.lds`中对`UEFI`的支持的部分：
```
 . = ALIGN(4);
 .__efi_runtime_start : {
  *(.__efi_runtime_start)
 }
 .efi_runtime : {
  *(efi_runtime_text)
  *(efi_runtime_data)
 }
 .__efi_runtime_stop : {
  *(.__efi_runtime_stop)
 }
 .efi_runtime_rel_start :
 {
  *(.__efi_runtime_rel_start)
 }
 .efi_runtime_rel : {
  *(.relefi_runtime_text)
  *(.relefi_runtime_data)
 }
 .efi_runtime_rel_stop :
 {
  *(.__efi_runtime_rel_stop)
 }
```

+ 重定位支持

> _[<<关于uboot重定位方面的总结和问题>>](http://www.360doc.com/content/14/0207/22/15708445_350570989.shtml) 是这样解释重定位的：_
> 
> _在老的`uboot`中，如果我们想要`uboot`启动后把自己拷贝到内存中的某个地方，只要把要拷贝的地址写给`TEXT_BASE`即可，然后`boot`启动后就会把自己拷贝到`TEXT_BASE`内的地址处运行，在拷贝之前的代码都是相对的，不能出现绝对的跳转，否则会跑飞。在新版的`uboot`里（`2013.07`），`TEXT_BASE`的含义改变了。它表示用户要把这段代码加载到哪里，通常是通过串口等工具。然后搬移的时候由`uboot`自己计算一个地址来进行搬移。新版的`uboot`采用了动态链接技术，在lds文件中有`__rel_dyn_start`和`__rel_dyn_end`，这两个符号之间的区域存放着动态链接符号，只要给这里面的符号加上一定的偏移，拷贝到内存中代码的后面相应的位置处，就可以在绝对跳转中找到正确的函数。_
> 

```
 .rel_dyn_start :
 {
  *(.__rel_dyn_start)
 }
 .rel.dyn : {
  *(.rel*)
 }
 .rel_dyn_end :
 {
  *(.__rel_dyn_end)
 }
```

> 至于`u-boot`中，代码的重定位是如何工作的，请看： 
_[uboot的relocation原理详细分析](http://blog.csdn.net/skyflying2012/article/details/37660265)_

在`u-boot`的编译过程中会生成3个符号表文件：

+ `u-boot.map`
+ `u-boot.sym`
+ `System.map`

查看`.u-boot.cmd`显示`u-boot`的链接命令：
```shell
cmd_u-boot := arm-linux-gnueabi-ld.bfd   -pie  --gc-sections -Bstatic \
    -Ttext 0x00008000 -o u-boot -T u-boot.lds \
    arch/arm/cpu/armv7/start.o \
    --start-group  \
        arch/arm/cpu/built-in.o \
        arch/arm/cpu/armv7/built-in.o \
        arch/arm/lib/built-in.o \
        arch/arm/mach-bcm283x/built-in.o \
        board/raspberrypi/rpi/built-in.o \
        cmd/built-in.o \
        ... \
        fs/built-in.o  \
        lib/built-in.o  \
        net/built-in.o \
    --end-group \
    arch/arm/lib/eabi_compat.o  arch/arm/lib/lib.a \
    -Map u-boot.map
```
其中选项`-pie`，在`ld`的手册上是这样说的：
> _[http://sourceware.org/binutils/docs/ld/Options.html#Options](http://sourceware.org/binutils/docs/ld/Options.html#Options)_<br>
    ```
    -pie
    --pic-executable
    Create a position independent executable. This is currently only supported on ELF platforms. Position independent executables are similar to shared libraries in that they are relocated by the dynamic linker to the virtual address the OS chooses for them (which can vary between invocations). Like normal dynamically linked executables they can be executed and symbols defined in the executable cannot be overridden by shared libraries.
    ```


#u-boot-2016.09 make编译过程分析（二）

##综述
`u-boot`自`v2014.10`版本开始引入`KBuild`系统，同更改前的编译系统相比，由于`Kbuild`系统的原因，其`Makefile`变得更加复杂。

u-boot的编译跟kernel编译一样，分两步执行：

+ 第一步：配置，执行`make xxx_defconfig`进行各项配置，生成`.config`文件
+ 第二部：编译，执行`make`进行编译，生成可执行的二进制文件u-boot.bin或u-boot.elf

**Makefile的核心是依赖和命令。对于每个目标，首先会检查依赖，如果依赖存在，则执行命令更新目标；如果依赖不存在，则会以依赖为目标，先生成依赖，待依赖生成后，再执行命令生成目标。**

+ 博客《[u-boot-2016.09 make配置过程分析](http://blog.csdn.net/guyongqiangx/article/details/52558087 "u-boot-2016.09 make配置过程分析")》详尽解释了第一步的操作，在这一步中，u-boot执行配置命令`make xxx_defconfig`时先搜集所有默认的`Kconfig`配置，然后再用命令行指定的`xxx_defconfig`配置进行更新并输出到根目录的`.config`文件中。

+ 配置完成后执行make命令生成二进制文件的过程，由于涉及的依赖和命令很多，也将make编译过程分析分为两部分，目标依赖和命令执行。
    + 博客《[u-boot-2016.09 make编译过程分析（一）](http://blog.csdn.net/guyongqiangx/article/details/52565493 "u-boot-2016.09 make编译过程分析（一）")》中描述了`make`过程中的依赖关系
    + 本篇主要分析`make`过程中的通过命令生成各个目标的依赖，从而一步一步更新目标，直至更新并生成顶层目标`u-boot.bin`。

##第二部分、执行命令更新目标
将上面的依赖关系并到一起，就得到了一个完整的`u-boot`目标依赖图：
![完整的目标依赖关系](http://img.blog.csdn.net/20160917232812279)
（完整的关系图较大，可以将图片拖到浏览器的其他窗口看大图）

这些依赖有两类：

+ 依赖本身通过执行命令生成，但不存在进一步的依赖；
+ 依赖自身还有进一步的依赖，在生成了进一步依赖的基础上，执行命令生成依赖；

**完成目标依赖分析后，剩下的就是基于完整的目标依赖关系图，从最底层的依赖开始，逐层运行命令生成目标，直到生成顶层目标。**

《[u-boot-2016.09 make编译过程分析（一）](http://blog.csdn.net/guyongqiangx/article/details/52565493 "u-boot-2016.09 make编译过程分析（一）")》分析依赖关系时采用自顶向下的方法，从顶层目标开始到最原始的依赖结束。
此处采用自下而上的方式，先从最原始的依赖开始，一步一步，执行命令生成目标。

###1. `prepare`系列目标依赖

完整的`prepare`系列的目标依赖：
![完整的`prepare`系列的目标依赖](https://github.com/guyongqiangx/blog/blob/dev/u-boot/make-targets-and-dependencies/all-targets-in-prepare-stage.png?raw=true)
依次从最右边的依赖说起：

####1.1 `scripts/kconfig/conf`生成的文件
+ `.config`

`.config`在执行`make rpi_3_32b_defconfig`配置时生成，`scripts/kconfig/Makefile`中有规则：
```makefile
%_defconfig: $(obj)/conf
    $(Q)$< $(silent) --defconfig=arch/$(SRCARCH)/configs/$@ $(Kconfig)
```
这里展开后为：
```makefile
rpi_3_32b_defconfig: scripts/kconfig/conf
    scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig
```
`scripts/kconfig/conf`会从根目录开始读取`Kconfig`，输出到根目录下的`.config`中。

+ `include/generated/autoconf.h`
+ `include/config/auto.conf.cmd`
+ `include/config/tristate.conf`
+ `include/config/auto.conf`

以上4个文件在执行`make`编译命令的开始会检查`%.conf`的依赖规则：
```makefile
include/config/%.conf: $(KCONFIG_CONFIG) include/config/auto.conf.cmd
    $(Q)$(MAKE) -f $(srctree)/Makefile silentoldconfig
    $(Q)$(MAKE) -f $(srctree)/scripts/Makefile.autoconf || \
        { rm -f include/config/auto.conf; false; }
    $(Q)touch include/config/auto.conf
```
调用`make -f ./Makefile silentoldconfig`的最终结果是执行`scripts/kconfig/Makefile`中的规则：
```makefile
silentoldconfig: $(obj)/conf
    $(Q)mkdir -p include/config include/generated
    $< $(silent) --$@ $(Kconfig)
```
这个规则展开为：
```makefile
silentoldconfig: scripts/kconfig/conf
    mkdir -p include/config include/generated
    scripts/kconfig/conf --silentoldconfig Kconfig
```
`scripts/kconfig/conf`会从根目录开始读取`Kconfig`，同时检查并更新配置阶段生成的`.config`文件，再把最终结果输出到以上的4个文件中。

>所生成的4个文件中，`include/config/auto.conf`依赖于`include/config/auto.conf.cmd`，但是这里的依赖文件`include/config/auto.conf.cmd`文件并非由`fixdep`生成，而是直接由`conf`工具生成，算是`*.cmd`文件生成的特例。

_`scripts/kconfig/conf`生成了图中右侧的依赖：`include/config/auto.conf`，`$(KCONIFG_CONFIG)/.config`和`include/config/auto.conf.cmd`_

####1.2 目标`include/config/auto.conf`的规则

在生成`include/config/auto.conf`的规则中：
```makefile
# If .config is newer than include/config/auto.conf, someone tinkered
# with it and forgot to run make oldconfig.
# if auto.conf.cmd is missing then we are probably in a cleaned tree so
# we execute the config step to be sure to catch updated Kconfig files
include/config/%.conf: $(KCONFIG_CONFIG) include/config/auto.conf.cmd
    $(Q)$(MAKE) -f $(srctree)/Makefile silentoldconfig
    @# If the following part fails, include/config/auto.conf should be
    @# deleted so "make silentoldconfig" will be re-run on the next build.
    $(Q)$(MAKE) -f $(srctree)/scripts/Makefile.autoconf || \
        { rm -f include/config/auto.conf; false; }
    @# include/config.h has been updated after "make silentoldconfig".
    @# We need to touch include/config/auto.conf so it gets newer
    @# than include/config.h.
    @# Otherwise, 'make silentoldconfig' would be invoked twice.
    $(Q)touch include/config/auto.conf
```
除了执行`$(MAKE) -f $(srctree)/Makefile silentoldconfig`外，还执行`$(MAKE) -f $(srctree)/scripts/Makefile.autoconf`

在`scripts/Makefile.autoconf`的头部是这样的：
```makefile
# This helper makefile is used for creating
#  - symbolic links (arch/$ARCH/include/asm/arch
#  - include/autoconf.mk, {spl,tpl}/include/autoconf.mk
#  - include/config.h
#
# When our migration to Kconfig is done
# (= When we move all CONFIGs from header files to Kconfig)
# this makefile can be deleted.
#
# SPDX-License-Identifier:  GPL-2.0
#

__all: include/autoconf.mk include/autoconf.mk.dep

ifeq ($(shell grep -q '^CONFIG_SPL=y' include/config/auto.conf 2>/dev/null && echo y),y)
__all: spl/include/autoconf.mk
endif

ifeq ($(shell grep -q '^CONFIG_TPL=y' include/config/auto.conf 2>/dev/null && echo y),y)
__all: tpl/include/autoconf.mk
endif
```

此处没有设置`CONFIG_SPL=y`或`CONFIG_TPL=y`，所以整个`makefile`的`__all`的依赖有：

+ `include/autoconf.mk`
+ `include/autoconf.mk.dep`

然而`include/autoconf.mk`还要进一步依赖于`config.h`

#####1.2.1 **`include/config.h`的规则**
所有的`autoconf.mk`都依赖于`include/config.h`（`rpi_3_32b_defconfig`配置只需要`include/autoconf.mk`）：
```makefile
include/autoconf.mk include/autoconf.mk.dep \
    spl/include/autoconf.mk tpl/include/autoconf.mk: include/config.h
```

实际上`include/config.h`由宏`filechk_config_h`生成：
```makefile
# include/config.h
# Prior to Kconfig, it was generated by mkconfig. Now it is created here.
define filechk_config_h
    (echo "/* Automatically generated - do not edit */";        \
    for i in $$(echo $(CONFIG_SYS_EXTRA_OPTIONS) | sed 's/,/ /g'); do \
        echo \#define CONFIG_$$i                \
        | sed '/=/ {s/=/    /;q; } ; { s/$$/    1/; }'; \
    done;                               \
    echo \#define CONFIG_BOARDDIR board/$(if $(VENDOR),$(VENDOR)/)$(BOARD);\
    echo \#include \<config_defaults.h\>;               \
    echo \#include \<config_uncmd_spl.h\>;              \
    echo \#include \<configs/$(CONFIG_SYS_CONFIG_NAME).h\>;     \
    echo \#include \<asm/config.h\>;                \
    echo \#include \<config_fallbacks.h\>;)
endef

include/config.h: scripts/Makefile.autoconf create_symlink FORCE
    $(call filechk,config_h)
```

最终生成的`include/config.h`也比较简单，不妨看看：
```c
/* Automatically generated - do not edit */
#define CONFIG_BOARDDIR board/raspberrypi/rpi
#include <config_defaults.h>
#include <config_uncmd_spl.h>
#include <configs/rpi.h>
#include <asm/config.h>
#include <config_fallbacks.h>
```

生成`config.h`之前，还要应用`create_symlink`生成相应的符号链接。

#####1.2.2 **`create_symlink`的规则**

```makefile
# symbolic links
# If arch/$(ARCH)/mach-$(SOC)/include/mach exists,
# make a symbolic link to that directory.
# Otherwise, create a symbolic link to arch/$(ARCH)/include/asm/arch-$(SOC).
PHONY += create_symlink
create_symlink:
ifdef CONFIG_CREATE_ARCH_SYMLINK
ifneq ($(KBUILD_SRC),)
    $(Q)mkdir -p include/asm
    $(Q)if [ -d $(KBUILD_SRC)/arch/$(ARCH)/mach-$(SOC)/include/mach ]; then \
        dest=arch/$(ARCH)/mach-$(SOC)/include/mach;         \
    else                                    \
        dest=arch/$(ARCH)/include/asm/arch-$(if $(SOC),$(SOC),$(CPU));  \
    fi;                                 \
    ln -fsn $(KBUILD_SRC)/$$dest include/asm/arch
else
    $(Q)if [ -d arch/$(ARCH)/mach-$(SOC)/include/mach ]; then   \
        dest=../../mach-$(SOC)/include/mach;            \
    else                                \
        dest=arch-$(if $(SOC),$(SOC),$(CPU));           \
    fi;                             \
    ln -fsn $$dest arch/$(ARCH)/include/asm/arch
endif
endif
```

注释已经很好解释了`create_symlink`的行为：

+ 如果`arch/$(ARCH)/math-$(SOC)/include/mach`存在，则生成符号链接：`arch/$(ARCH)/include/asm/arch --> arch/$(ARCH)/math-$(SOC)`
+ 否则生成符号链接`arch/$(ARCH)/include/asm/arch --> arch/$(ARCH)`

对基于`arm v7`架构的`bcm2837`芯片，`arch/arm/math-bcm283x`文件夹存在，所以生成链接：
`arch/arm/include/asm --> arch/arm/mach-bcm283x/include/mach`

简单说来，`create_symlink`就是将芯片指定的`arch/$(ARCH)math-$(SOC)`连接到跟芯片名字无关的`arch/$(ARCH)/include/asm`下。

###1.2.3 **`include/autoconf.mk`的规则**
```makefile
# We are migrating from board headers to Kconfig little by little.
# In the interim, we use both of
#  - include/config/auto.conf (generated by Kconfig)
#  - include/autoconf.mk      (used in the U-Boot conventional configuration)
# The following rule creates autoconf.mk
# include/config/auto.conf is grepped in order to avoid duplication of the
# same CONFIG macros
quiet_cmd_autoconf = GEN     $@
      cmd_autoconf = \
    $(CPP) $(c_flags) $2 -DDO_DEPS_ONLY -dM $(srctree)/include/common.h > $@.tmp && { \
        sed -n -f $(srctree)/tools/scripts/define2mk.sed $@.tmp |       \
        while read line; do                         \
            if [ -n "${KCONFIG_IGNORE_DUPLICATES}" ] ||         \
               ! grep -q "$${line%=*}=" include/config/auto.conf; then  \
                echo "$$line";                      \
            fi                              \
        done > $@;                              \
        rm $@.tmp;                              \
    } || {                                      \
        rm $@.tmp; false;                           \
    }

include/autoconf.mk: FORCE
    $(call cmd,autoconf)
```

从`cmd_autoconf`来看，这里会根据`include/common.h`的依赖，然后调用`tools/scripts/define2mk.sed`，并合并之前生成的`include/config/auto.conf`生成最终的`autoconf.mk`

#####1.2.4 **`include/autoconf.mk.dep`的规则**

```makefile
quiet_cmd_autoconf_dep = GEN     $@
      cmd_autoconf_dep = $(CC) -x c -DDO_DEPS_ONLY -M -MP $(c_flags) \
    -MQ include/config/auto.conf $(srctree)/include/common.h > $@ || {  \
        rm $@; false;                           \
    }
include/autoconf.mk.dep: FORCE
    $(call cmd,autoconf_dep)
```
这个规则比较简单，由于`autoconf.mk`由`common.h`和`auto.conf`而来，因此直接处理这两个文件的依赖并合并到`autoconf.mk.dep`中。

####1.3 `include/config/uboot.release`
```makefile
define filechk_uboot.release
    echo "$(UBOOTVERSION)$$($(CONFIG_SHELL) $(srctree)/scripts/setlocalversion $(srctree))"
endef

# Store (new) UBOOTRELEASE string in include/config/uboot.release
include/config/uboot.release: include/config/auto.conf FORCE
    $(call filechk,uboot.release)
```

命令`$(call filechk,uboot.release)`展开后就是调用宏`filechk_uboot.release`，最终将字符串`2016.09`写入`include/config/uboot.release`中。

####1.4 `timestamp.h`和`version.h`的规则

```makefile
version_h := include/generated/version_autogenerated.h
timestamp_h := include/generated/timestamp_autogenerated.h

...

# Generate some files
# ---------------------------------------------------------------------------

define filechk_version.h
    (echo \#define PLAIN_VERSION \"$(UBOOTRELEASE)\"; \
    echo \#define U_BOOT_VERSION \"U-Boot \" PLAIN_VERSION; \
    echo \#define CC_VERSION_STRING \"$$(LC_ALL=C $(CC) --version | head -n 1)\"; \
    echo \#define LD_VERSION_STRING \"$$(LC_ALL=C $(LD) --version | head -n 1)\"; )
endef

# The SOURCE_DATE_EPOCH mechanism requires a date that behaves like GNU date.
# The BSD date on the other hand behaves different and would produce errors
# with the misused '-d' switch.  Respect that and search a working date with
# well known pre- and suffixes for the GNU variant of date.
define filechk_timestamp.h
    (if test -n "$${SOURCE_DATE_EPOCH}"; then \
        SOURCE_DATE="@$${SOURCE_DATE_EPOCH}"; \
        DATE=""; \
        for date in gdate date.gnu date; do \
            $${date} -u -d "$${SOURCE_DATE}" >/dev/null 2>&1 && DATE="$${date}"; \
        done; \
        if test -n "$${DATE}"; then \
            LC_ALL=C $${DATE} -u -d "$${SOURCE_DATE}" +'#define U_BOOT_DATE "%b %d %C%y"'; \
            LC_ALL=C $${DATE} -u -d "$${SOURCE_DATE}" +'#define U_BOOT_TIME "%T"'; \
            LC_ALL=C $${DATE} -u -d "$${SOURCE_DATE}" +'#define U_BOOT_TZ "%z"'; \
            LC_ALL=C $${DATE} -u -d "$${SOURCE_DATE}" +'#define U_BOOT_DMI_DATE "%m/%d/%Y"'; \
        else \
            return 42; \
        fi; \
    else \
        LC_ALL=C date +'#define U_BOOT_DATE "%b %d %C%y"'; \
        LC_ALL=C date +'#define U_BOOT_TIME "%T"'; \
        LC_ALL=C date +'#define U_BOOT_TZ "%z"'; \
        LC_ALL=C date +'#define U_BOOT_DMI_DATE "%m/%d/%Y"'; \
    fi)
endef

$(version_h): include/config/uboot.release FORCE
    $(call filechk,version.h)

$(timestamp_h): $(srctree)/Makefile FORCE
    $(call filechk,timestamp.h)
```

+ **include/generated/version_autogenerated.h**

根据`include/config/uboot.release`文件，规则调用`filechk_version.h`宏生成版本相关字符串文件`include/generated/version_autogenerated.h`，如下：
```c
#define PLAIN_VERSION "2016.09"
#define U_BOOT_VERSION "U-Boot " PLAIN_VERSION
#define CC_VERSION_STRING "arm-linux-gnueabi-gcc (Ubuntu/Linaro 4.7.3-12ubuntu1) 4.7.3"
#define LD_VERSION_STRING "GNU ld (GNU Binutils for Ubuntu) 2.24"
```

+ **include/generated/timestamp_autogenerated.h**

调用宏`filechk_timestamp.h`生成编译的时间戳文件，如下：
```c
#define U_BOOT_DATE "Oct 02 2016"
#define U_BOOT_TIME "21:54:42"
#define U_BOOT_TZ "+0800"
#define U_BOOT_DMI_DATE "10/02/2016"
```

####1.5 `outputmakefile`的规则

```makefile
PHONY += outputmakefile
# outputmakefile generates a Makefile in the output directory, if using a
# separate output directory. This allows convenient use of make in the
# output directory.
outputmakefile:
ifneq ($(KBUILD_SRC),)
    $(Q)ln -fsn $(srctree) source
    $(Q)$(CONFIG_SHELL) $(srctree)/scripts/mkmakefile \
        $(srctree) $(objtree) $(VERSION) $(PATCHLEVEL)
endif
```

+ 如果编译没有设置`O`，即输出和代码都在同一个目录下，则`outputmakefile`的规则什么都不做；
+ 如果编译指定了输出目录`O`，则调用`scripts/mkmakefile`在`O`选项指定的目录下生成一个简单的`makefile`

####1.6 `scripts_basic`的规则
```makefile
# Basic helpers built in scripts/
PHONY += scripts_basic
scripts_basic:
    $(Q)$(MAKE) $(build)=scripts/basic
    $(Q)rm -f .tmp_quiet_recordmcount
```
`scripts_basic`的执行结果就是编译生成`scripts/basic/fixdep`工具，该工具是`u-boot`编译系统中最常用的工具，用于在编译过程中修正每一个生成文件的依赖关系。

####1.7 `parepare0`的规则
```makefile
prepare0: archprepare FORCE
    $(Q)$(MAKE) $(build)=.
```

展开后为：
```makefile
prepare0: archprepare FORCE
    make -f ./scripts/Makefile.build obj=.
```

编译时，命令`make -f ./scripts/Makefile.build obj=.`不会生成任何目标。

####1.8 `prepare`系列目标总结
`prepare`阶段主要做了以下工作：

+ `scripts_basic`规则生成`fixdep`工具，用于对整个系统生成目标文件相应依赖文件的更新；
+ 配置阶段，`scripts/kconfig/conf`根据传入的指定配置文件在根目录下生成`.config`文件
+ 编译阶段，`scripts/kconfig/conf`读取配置阶段生成的`.config`，并检查最新配置生成以下文件：
    * `include/generated/autoconf.h`
    * `include/config/auto.conf.cmd`
    * `include/config/tristate.conf`
    * `include/config/auto.conf`
+ 调用宏`filechk_config_h`生成`include/config.h`文件
+ 调用命令`cmd_autoconf_dep`生成`autoconf.mk`和`autoconf.mk.cmd`文件
+ 调用宏`filechk_uboot.release`生成`include/config/uboot.release`文件
+ 调用宏`filechk_version.h`生成`include/generated/version_autogenerated.h`文件
+ 调用宏`filechk_timestamp.h`生成`include/generated/timestamp_autogenerated.h`文件
+ 调用宏`create_symlink`将芯片指定的arch/$(ARCH)math-$(SOC)连接到跟芯片名字无关的arch/$(ARCH)/include/asm下

###2. `u-boot`文件系列目标依赖

![`u-boot`文件系列目标依赖关系](https://github.com/guyongqiangx/blog/blob/dev/u-boot/make-targets-and-dependencies/main-targets-in-uboot-file-stage.png?raw=true)

从图上可见，除了`prepare`依赖外，`u-boot`还依赖于文件`$(head-y)`，`$(libs-y)`和`$(LDSCRIPT)`，即依赖于：

+ 启动文件`arch/arm/cpu/$(CPU)/start.o`
+ 各个目录下的`build-in.o`
+ 链接脚本文件`arch/arm/cpu/u-boot.lds`

####2.1 启动文件`start.o`
`$(head-y)`在`arch/arm/Makefile`中被直接指定：
```
head-y := arch/arm/cpu/$(CPU)/start.o
```

在顶层`makefile`中被指定给变量`u-boot-init`：
```
u-boot-init := $(head-y)
```

####2.2 各目录下的`build-in.o`
`$(libs-y)`在顶层的`makefile`中被指定为各个子目录下的`build-in.o`的集合：
```
libs-y += lib/
...
libs-y += fs/
libs-y += net/
libs-y += disk/
libs-y += drivers/
...

libs-y += $(if $(BOARDDIR),board/$(BOARDDIR)/)

libs-y := $(sort $(libs-y))

...

libs-y      := $(patsubst %/, %/built-in.o, $(libs-y))

...
u-boot-main := $(libs-y)
```
以上脚本中，先将`$(libs-y)`设置为各子目录的集合，最后调用`patsubst`函数将`$(libs-y)`设置为这些目录下的`built-in.o`文件的集合，最后赋值给变量`u-boot-main`作为链接的主体文件。

+ **各目录下的`built-in.o`是如何生成的呢？**

以`drivers/mmc/built-in.o`为例，先查看生成的依赖文件`drivers/mmc/.built-in.o.cmd`：
```
cmd_drivers/mmc/built-in.o :=  arm-linux-gnueabi-ld.bfd     -r -o drivers/mmc/built-in.o drivers/mmc/mmc_legacy.o drivers/mmc/bcm2835_sdhci.o drivers/mmc/mmc.o drivers/mmc/sdhci.o drivers/mmc/mmc_write.o 

```

从生成命令`cmd_drivers/mmc/built-in.o`可以看到，`built-in.o`是由目录下各个编译生成的`*.o`文件通过链接操作`ld -r`而来。

+ **`ld`的`-r`选项是什么作用呢？**
在[`ld`的手册](http://sourceware.org/binutils/docs/ld/Options.html#Options)中是这样介绍`-r`选项的：
```
-r
--relocatable
    Generate relocatable output—i.e., generate an output file that can in turn serve as input to ld. This is often called partial linking. As a side effect, in environments that support standard Unix magic numbers, this option also sets the output file's magic number to OMAGIC. If this option is not specified, an absolute file is produced. When linking C++ programs, this option will not resolve references to constructors; to do that, use `-Ur'.

    When an input file does not have the same format as the output file, partial linking is only supported if that input file does not contain any relocations. Different output formats can have further restrictions; for example some a.out-based formats do not support partial linking with input files in other formats at all.

    This option does the same thing as `-i'.
```

简单说来，`ld`通过`-r`选项来产生可重定位的输出，相当于部分链接。

在这里就是通过`ld -r`选项将目录`drivers/mmc/`下的`*.o`文件先链接为单一文件`build-in.o`，但其并不是最终的生成文件，而是一个可进行重定位的文件.在下一阶段的链接中，`ld`会将各个目录下的`built-in.o`链接生成最终的`u-boot`。

+ **`built-in.o`的规则**

生成`built-in.o`的规则在`scripts/Makefile.build`中定义：
```makefile
#
# Rule to compile a set of .o files into one .o file
#
ifdef builtin-target
quiet_cmd_link_o_target = LD      $@
# If the list of objects to link is empty, just create an empty built-in.o
cmd_link_o_target = $(if $(strip $(obj-y)),\
              $(LD) $(ld_flags) -r -o $@ $(filter $(obj-y), $^) \
              $(cmd_secanalysis),\
              rm -f $@; $(AR) rcs$(KBUILD_ARFLAGS) $@)

$(builtin-target): $(obj-y) FORCE
    $(call if_changed,link_o_target)

targets += $(builtin-target)
endif # builtin-target
```

####2.3 链接脚本`u-boot.lds`
链接脚本的规则如下：
```makefile
quiet_cmd_cpp_lds = LDS     $@
cmd_cpp_lds = $(CPP) -Wp,-MD,$(depfile) $(cpp_flags) $(LDPPFLAGS) \
        -D__ASSEMBLY__ -x assembler-with-cpp -P -o $@ $<

u-boot.lds: $(LDSCRIPT) prepare FORCE
    $(call if_changed_dep,cpp_lds)
```

####2.4 生成`u-boot`规则
顶层`Makefile`中定义了生成`u-boot`文件的规则：
```
# Rule to link u-boot
# May be overridden by arch/$(ARCH)/config.mk
quiet_cmd_u-boot__ ?= LD      $@
      cmd_u-boot__ ?= $(LD) $(LDFLAGS) $(LDFLAGS_u-boot) -o $@ \
      -T u-boot.lds $(u-boot-init)                             \
      --start-group $(u-boot-main) --end-group                 \
      $(PLATFORM_LIBS) -Map u-boot.map

...

u-boot: $(u-boot-init) $(u-boot-main) u-boot.lds FORCE
    $(call if_changed,u-boot__)
...
```

`u-boot`文件的生成很简单，调用`ld`命令，将`$(u-boot-init)`和`$(u-boot-main)`指定的一系列文件通过脚本`u-boot.lds`连接起来。

`u-boot`针对`raspberry pi 3`生成的命令是这样的（由于原命令太长，这里用`\`分割为多行）：
```shell
  arm-linux-gnueabi-ld.bfd   -pie  --gc-sections -Bstatic \
  -Ttext 0x00008000 \
  -o u-boot \
  -T u-boot.lds \
  arch/arm/cpu/armv7/start.o \
  --start-group  \
                 arch/arm/cpu/built-in.o  \
                 arch/arm/cpu/armv7/built-in.o  \
                 arch/arm/lib/built-in.o  \
                 arch/arm/mach-bcm283x/built-in.o  \
                 board/raspberrypi/rpi/built-in.o  \
                 cmd/built-in.o  \
                 common/built-in.o  \
                 disk/built-in.o  \
                 drivers/built-in.o  \
                 drivers/dma/built-in.o  \
                 drivers/gpio/built-in.o  \
                ...
                 lib/built-in.o  \
                 net/built-in.o  \
                 test/built-in.o  \
                 test/dm/built-in.o \
--end-group \
 arch/arm/lib/eabi_compat.o  \
 arch/arm/lib/lib.a \
 -Map u-boot.map
```

生成了`u-boot`文件后，后续就是针对`u-boot`文件的各种处理了。

###3. 顶层目标依赖
![顶层目标依赖](https://github.com/guyongqiangx/blog/blob/dev/u-boot/make-targets-and-dependencies/u-boot-top-targets-and-dependencies.png?raw=true)

显然，在生成了`u-boot`的基础上，进一步生成所需要的各种目标文件：

+ `u-boot.srec`
```makefile
# Normally we fill empty space with 0xff
quiet_cmd_objcopy = OBJCOPY $@
cmd_objcopy = $(OBJCOPY) --gap-fill=0xff $(OBJCOPYFLAGS) \
    $(OBJCOPYFLAGS_$(@F)) $< $@
...
OBJCOPYFLAGS_u-boot.hex := -O ihex

OBJCOPYFLAGS_u-boot.srec := -O srec

u-boot.hex u-boot.srec: u-boot FORCE
    $(call if_changed,objcopy)
```

调用`objcopy`命令，通过`-O ihex`或`-O srec`指定生成`u-boot.hex`或`u-boot.srec`格式文件。

+ `u-boot.sym`
```makefile
quiet_cmd_sym ?= SYM     $@
      cmd_sym ?= $(OBJDUMP) -t $< > $@
u-boot.sym: u-boot FORCE
    $(call if_changed,sym)
```
调用`$(OBJDUMP)`命令生成符号表文件`u-boot.sym`。

+ `System.map`
```
SYSTEM_MAP = \
        $(NM) $1 | \
        grep -v '\(compiled\)\|\(\.o$$\)\|\( [aUw] \)\|\(\.\.ng$$\)\|\(LASH[RL]DI\)' | \
        LC_ALL=C sort
System.map: u-boot
        @$(call SYSTEM_MAP,$<) > $@
```
调用`$(NM)`命令打印`u-boot`文件的符号表，并用`grep -v`处理后得到`System.map`文件，里面包含了最终使用到的各个符号的位置信息。

+ `u-boot.bin`和`u-boot-nodtb.bin`

```makefile
PHONY += dtbs
dtbs: dts/dt.dtb
    @:
dts/dt.dtb: checkdtc u-boot
    $(Q)$(MAKE) $(build)=dts dtbs

quiet_cmd_copy = COPY    $@
      cmd_copy = cp $< $@

ifeq ($(CONFIG_OF_SEPARATE),y)
u-boot-dtb.bin: u-boot-nodtb.bin dts/dt.dtb FORCE
    $(call if_changed,cat)

u-boot.bin: u-boot-dtb.bin FORCE
    $(call if_changed,copy)
else
u-boot.bin: u-boot-nodtb.bin FORCE
    $(call if_changed,copy)
endif
```
由于这里没有使用`device tree`设置，即编译没有定义`CONFIG_OF_SEPARATE`，因此`u-boot.bin`和`u-boot-nodtb.bin`是一样的。

至于生成`u-boot-nodtb.bin`的规则：
```makefile
u-boot-nodtb.bin: u-boot FORCE
    $(call if_changed,objcopy)
    $(call DO_STATIC_RELA,$<,$@,$(CONFIG_SYS_TEXT_BASE))
    $(BOARD_SIZE_CHECK)
```

显然，`u-boot-nodtb.bin`是`u-boot`文件通过`objcopy`得到。


+ `u-boot.cfg`
`u-boot.cfg`中包含了所有用到的宏定义，其生成规则如下：
```
# Create a file containing the configuration options the image was built with
quiet_cmd_cpp_cfg = CFG     $@
cmd_cpp_cfg = $(CPP) -Wp,-MD,$(depfile) $(cpp_flags) $(LDPPFLAGS) -ansi \
    -DDO_DEPS_ONLY -D__ASSEMBLY__ -x assembler-with-cpp -P -dM -E -o $@ $<
...
u-boot.cfg: include/config.h FORCE
    $(call if_changed,cpp_cfg)
```

因此，阅读源码时如果不确定某个宏的值，可以检查`u-boot.cfg`文件。

自此，生成了所有的目标文件，完成了整个编译过程的分析。





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

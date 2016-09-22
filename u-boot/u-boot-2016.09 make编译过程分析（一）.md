#u-boot-2016.09 make编译过程分析（一）

##综述
`u-boot`自`v2014.10`版本开始引入`KBuild`系统，Makefile的管理和组织跟以前版本的代码有了很大的不同，其Makefile更加复杂。整个Makefile中，嵌套了很多其它不同用途的Makefile，各种目标和依赖也很多，make分析很容易陷进去，让人摸不着头脑。

u-boot的编译跟kernel编译一样，分两步执行：
- 第一步：配置，执行`make xxx_defconfig`进行各项配置，生成`.config`文件
- 第二部：编译，执行`make`进行编译，生成可执行的二进制文件u-boot.bin或u-boot.elf

上一篇博客《[u-boot-2016.09 make配置过程分析](http://blog.csdn.net/guyongqiangx/article/details/52558087 "u-boot-2016.09 make配置过程分析")》详尽解释了第一步的操作，在这一步中，u-boot执行配置命令`make xxx_defconfig`时先搜集所有默认的`Kconfig`配置，然后再用命令行指定的`xxx_defconfig`配置进行更新并输出到根目录的`.config`文件中。
本文着眼第二步，即配置完成后执行make命令生成二进制文件的过程，由于涉及的依赖和命令很多，也将make编译过程分析分为两部分，目标依赖和命令执行。

**Makefile的核心是依赖和命令。对于每个目标，首先会检查依赖，如果依赖存在，则执行命令更新目标；如果依赖不存在，则会以依赖为目标，先生成依赖，待依赖生成后，再执行命令生成目标。**

##第一部分、目标依赖
现在来分析u-boot编译执行make命令的依赖关系。
目标依赖分析采用自顶向下方式，从顶层目标开始，逐次向下分解每一层依赖，直到不能分解位置。
###1.	顶层目标依赖
####a). `_all`和`all`对`$(ALL-y)`的依赖
从顶层Makefile开始查找，首先找到的是`_all`伪目标：

```makefile
# That's our default target when none is given on the command line
PHONY := _all
_all:

```
紧接着会对`_all`伪目标添加`all`伪目标的依赖：

```makefile
# If building an external module we do not care about the all: rule
# but instead _all depend on modules
PHONY += all
ifeq ($(KBUILD_EXTMOD),)
_all: all
else
_all: modules
endif

```

`all`自身依赖于`$(ALL-y)`

```makefile
all: $(ALL-y)
```

####b).	`$(ALL-y)`对`u-boot`目标文件的依赖
`$(ALL-y)`定义了最终需要生成所有文件：

```makefile
# Always append ALL so that arch config.mk's can add custom ones
ALL-y += u-boot.srec u-boot.bin u-boot.sym System.map u-boot.cfg binary_size_check

ALL-$(CONFIG_ONENAND_U_BOOT) += u-boot-onenand.bin
ifeq ($(CONFIG_SPL_FSL_PBL),y)
ALL-$(CONFIG_RAMBOOT_PBL) += u-boot-with-spl-pbl.bin
else
ifneq ($(CONFIG_SECURE_BOOT), y)
# For Secure Boot The Image needs to be signed and Header must also
# be included. So The image has to be built explicitly
ALL-$(CONFIG_RAMBOOT_PBL) += u-boot.pbl
endif
endif
ALL-$(CONFIG_SPL) += spl/u-boot-spl.bin
ALL-$(CONFIG_SPL_FRAMEWORK) += u-boot.img
ALL-$(CONFIG_TPL) += tpl/u-boot-tpl.bin
ALL-$(CONFIG_OF_SEPARATE) += u-boot.dtb
ifeq ($(CONFIG_SPL_FRAMEWORK),y)
ALL-$(CONFIG_OF_SEPARATE) += u-boot-dtb.img
endif
ALL-$(CONFIG_OF_HOSTFILE) += u-boot.dtb
ifneq ($(CONFIG_SPL_TARGET),)
ALL-$(CONFIG_SPL) += $(CONFIG_SPL_TARGET:"%"=%)
endif
ALL-$(CONFIG_REMAKE_ELF) += u-boot.elf
ALL-$(CONFIG_EFI_APP) += u-boot-app.efi
ALL-$(CONFIG_EFI_STUB) += u-boot-payload.efi

ifneq ($(BUILD_ROM),)
ALL-$(CONFIG_X86_RESET_VECTOR) += u-boot.rom
endif

# enable combined SPL/u-boot/dtb rules for tegra
ifeq ($(CONFIG_TEGRA)$(CONFIG_SPL),yy)
ALL-y += u-boot-tegra.bin u-boot-nodtb-tegra.bin
ALL-$(CONFIG_OF_SEPARATE) += u-boot-dtb-tegra.bin
endif

```

以上的`$(ALL-y)`目标中看起来非常复杂，但除了第一行的通用目标外，其余目标都只在特殊条件下才生成，这里略去不提。只分析通用目标依赖：

```
ALL-y += u-boot.srec u-boot.bin u-boot.sym System.map u-boot.cfg binary_size_check
```
#####i.	依赖`u-boot.srec`

依赖`u-boot.srec`：

```
u-boot.hex u-boot.srec: u-boot FORCE
	$(call if_changed,objcopy)

```
#####ii. 依赖`u-boot.bin`
依赖`u-boot.bin`：

```
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

如果打开了device tree支持，则有依赖关系：
`u-boot.bin --> u-boot-dtb.bin --> u-boot-nodtb.bin + dts/dt.dtb`
这里没有打开device tree支持，所以：
`u-boot.bin --> u-boot-nodtb.bin`

进一步，对于`u-boot-nodtb.bin`，其规则是：

```
u-boot-nodtb.bin: u-boot FORCE
	$(call if_changed,objcopy)
	$(call DO_STATIC_RELA,$<,$@,$(CONFIG_SYS_TEXT_BASE))
	$(BOARD_SIZE_CHECK)
```
#####iii. 依赖`u-boot.sym`
依赖`u-boot.sym`：

```
u-boot.sym: u-boot FORCE
	$(call if_changed,sym)
```
#####iv. 依赖`System.map`
依赖`System.map`：

```
System.map:	u-boot
		@$(call SYSTEM_MAP,$<) > $@
```

#####v. 依赖`u-boot.cfg`
依赖`u-boot.cfg`：

```
u-boot.cfg:	include/config.h FORCE
	$(call if_changed,cpp_cfg)
```

#####vi. 依赖`binary_size_check`

依赖`binary_size_check`：
```
binary_size_check: u-boot-nodtb.bin FORCE
	@file_size=$(shell wc -c u-boot-nodtb.bin | awk '{print $$1}') ; \
	map_size=$(shell cat u-boot.map | \
		awk '/_image_copy_start/ {start = $$1} /_image_binary_end/ {end = $$1} END {if (start != "" && end != "") print "ibase=16; " toupper(end) " - " toupper(start)}' \
		| sed 's/0X//g' \
		| bc); \
	if [ "" != "$$map_size" ]; then \
		if test $$map_size -ne $$file_size; then \
			echo "u-boot.map shows a binary size of $$map_size" >&2 ; \
			echo "  but u-boot-nodtb.bin shows $$file_size" >&2 ; \
			exit 1; \
		fi \
	fi

```
显然对于`binary_size_check`有下列依赖关系：
`binary_size_check --> u-boot-nodtb.bin --> u-boot`

####vii.	 `$(ALL-y)`依赖目标的共同点
以上通用目标`$(ALL-y)`的依赖有一个共同点，除了`u-boot.cfg`依赖于`include/config.h`外，其余目标全都依赖于`u-boot`（实际上除了依赖于`u-boot`外，还依赖于`FORCE`，由于`FORCE`依赖本身是一个空目标，为了方便，这里略去了对`FORCE`依赖的描述），如下：
![u-boot顶层目标的依赖关系](http://img.blog.csdn.net/20160917230843739)

###2. `u-boot`文件目标依赖
####a). 依赖`u-boot`
依赖`u-boot`：
```
u-boot:	$(u-boot-init) $(u-boot-main) u-boot.lds FORCE
	$(call if_changed,u-boot__)
ifeq ($(CONFIG_KALLSYMS),y)
	$(call cmd,smap)
	$(call cmd,u-boot__) common/system_map.o
endif
```

其中`$(u-boot-init)`和`$(u-boot-main)`分别被定义为：
```
u-boot-init := $(head-y)
u-boot-main := $(libs-y)
```
#####i. 依赖`$(head-y)`
`$(head-y)`在`arch/arm/Makefile`被定义为：
```
head-y := arch/arm/cpu/$(CPU)/start.o
```

#####ii. 依赖`$(libs-y)`
在顶层Makefile中搜索一下`$(libs-y)`，其被定义为各层驱动目录下`build-in.o`的集合：
```shell
ygu@ubuntu:/opt/work/u-boot/u-boot-2016.09$ grep -nw libs-y Makefile
629:libs-y += lib/
632:libs-y += fs/
633:libs-y += net/
634:libs-y += disk/
635:libs-y += drivers/
636:libs-y += drivers/dma/
637:libs-y += drivers/gpio/
638:libs-y += drivers/i2c/
639:libs-y += drivers/mmc/
640:libs-y += drivers/mtd/
642:libs-y += drivers/mtd/onenand/
644:libs-y += drivers/mtd/spi/
645:libs-y += drivers/net/
646:libs-y += drivers/net/phy/
647:libs-y += drivers/pci/
648:libs-y += drivers/power/ \
655:libs-y += drivers/spi/
659:libs-y += drivers/serial/
660:libs-y += drivers/usb/dwc3/
661:libs-y += drivers/usb/common/
662:libs-y += drivers/usb/emul/
663:libs-y += drivers/usb/eth/
664:libs-y += drivers/usb/gadget/
665:libs-y += drivers/usb/gadget/udc/
666:libs-y += drivers/usb/host/
667:libs-y += drivers/usb/musb/
668:libs-y += drivers/usb/musb-new/
669:libs-y += drivers/usb/phy/
670:libs-y += drivers/usb/ulpi/
671:libs-y += cmd/
672:libs-y += common/
675:libs-y += test/
676:libs-y += test/dm/
680:libs-y += $(if $(BOARDDIR),board/$(BOARDDIR)/)
682:libs-y := $(sort $(libs-y))
684:u-boot-dirs	:= $(patsubst %/,%,$(filter %/, $(libs-y))) tools examples
688:libs-y		:= $(patsubst %/, %/built-in.o, $(libs-y))
691:u-boot-main := $(libs-y)
```
第一行的搜索命令`grep -nw libs-y Makefile`参数：
- `-n` 表示搜索结果显示行号
- `-w` 表示仅搜索完成的单词
-  `Makefile` 表示仅在当前目录的文件`Makefile`中搜索

以上搜索结果，从629~682的各个匹配行都是将驱动的各个目录包含进来，第688行上会在每个目录名称的后面添加`build-in.o`，例如`libs-y`中的mtd驱动目录`drivers/mtd/`会变成`drivers/mtd/build-in.o`，这样就仅相当于链接每个驱动目录下的`build-in.o`文件。
为什么只是每个目录下的`build-in.o`文件呢？答案是编译时将同一个目录下的多个`*.o`输出文件合并到一起生成一个`build-in.o`文件，后面会有另外的博客对此专门说明。


####b). 依赖`u-boot.lds`
依赖`u-boot.lds`：
```
u-boot.lds: $(LDSCRIPT) prepare FORCE
	$(call if_changed_dep,cpp_lds)
```
其中`$(LDSCRIPT)`的定义如下：
```
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
如果没有定义`LDSCRIPT`和`CONFIG_SYS_LDSCRIPT`，则默认使用u-boot自带的lds文件。包括`board/$(BOARDIDR)`和`$(CPUDIR)`目录下定制的针对board或cpu的lds文件，如果没有定制的lds文件，则采用`arch/$(ARCH)/cpu`目录下默认的`u-boot.lds`
我们分析针对树莓派3代平台，其配置`rpi_3_32b_defconfig`没有对应任何特定的lds文件，所以使用默认文件`arch/arm/cpu/u-boot.lds`


#####依赖`prepare`
`u-boot.lds`的另一个依赖就是伪目标`prepare`。

####`u-boot`文件目标依赖
u-boot文件目标的依赖总体起来就是这样：
![u-boot文件的依赖关系](http://img.blog.csdn.net/20160917231811307)

###3.	 `prepare`系列目标依赖
####a). `prepare`系列依赖的规则
实际上`prepare`是一系列`prepare`伪目标和动作的组合，完成编译前的准备工作：
```
# Things we need to do before we recursively start building the kernel
# or the modules are listed in "prepare".
# A multi level approach is used. prepareN is processed before prepareN-1.
# archprepare is used in arch Makefiles and when processed asm symlink,
# version.h and scripts_basic is processed / created.

# Listed in dependency order
PHONY += prepare archprepare prepare0 prepare1 prepare2 prepare3

# prepare3 is used to check if we are building in a separate output directory,
# and if so do:
# 1) Check that make has not been executed in the kernel src $(srctree)
prepare3: include/config/uboot.release
ifneq ($(KBUILD_SRC),)
	@$(kecho) '  Using $(srctree) as source for U-Boot'
	$(Q)if [ -f $(srctree)/.config -o -d $(srctree)/include/config ]; then \
		echo >&2 "  $(srctree) is not clean, please run 'make mrproper'"; \
		echo >&2 "  in the '$(srctree)' directory.";\
		/bin/false; \
	fi;
endif

# prepare2 creates a makefile if using a separate output directory
prepare2: prepare3 outputmakefile

prepare1: prepare2 $(version_h) $(timestamp_h) \
                   include/config/auto.conf
ifeq ($(wildcard $(LDSCRIPT)),)
	@echo >&2 "  Could not find linker script."
	@/bin/false
endif

archprepare: prepare1 scripts_basic

prepare0: archprepare FORCE
	$(Q)$(MAKE) $(build)=.

# All the preparing..
prepare: prepare0
```

伪目标`prepare`，`prepare0`，`archprepare`，`prepare1`，`prepare2`，`prepare3`之间的依赖如下：
![`prepare`系列伪目标之间的依赖关系](http://img.blog.csdn.net/20160917232040681)

####b). `prepare`系列其他的依赖规则
在`prepare1`的依赖列表中，除了`include/config/auto.conf`外，还有`$(version_h)`和`$(timestamp_h)`，他们的依赖分别为：
```
$(version_h): include/config/uboot.release FORCE
	$(call filechk,version.h)

$(timestamp_h): $(srctree)/Makefile FORCE
	$(call filechk,timestamp.h)
```
这里的两个`filechk`函数调用会动态生成`version.h`和`timestamp.h`。

对于最里层的`prepare3`的依赖`include/config/uboot.release`，还存在下一级依赖：
```
# Store (new) UBOOTRELEASE string in include/config/uboot.release
include/config/uboot.release: include/config/auto.conf FORCE
	$(call filechk,uboot.release)
```
对于`include/config/auto.conf`，Makefile中有一个匹配的规则：
```
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
所以`include/config/auto.conf`依赖于`$(KCONFIG_CONFIG)`和`include/config/auto.conf.cmd`。
- `$(KCONFIG_CONFIG)`实际上就是`.config`文件；
- `include/config/auto.conf.cmd`是由`fixdep`在编译时生成的依赖文件；

####c). `prepare`系列伪目标完整的依赖关系
整个`prepare`部分的依赖关系如下：
![整个`prepare`部分的依赖关系](http://img.blog.csdn.net/20160917232559734)

###4. 完整的目标依赖
将上面的依赖关系并到一起，就得到了一个完整的`u-boot`目标依赖图：
![完整的目标依赖关系](http://img.blog.csdn.net/20160917232812279)
（完整的关系图较大，可以将图片拖到浏览器的其他窗口看大图）

**完成目标依赖分析后，剩下的就是基于完整的目标依赖关系图，从最底层的依赖开始，逐层运行命令生成目标，直到生成顶层目标。**
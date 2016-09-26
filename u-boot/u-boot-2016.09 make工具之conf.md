[TOC]

#u-boot-2016.09 make工具之conf

##1. 概述
`conf`工具的源码位于`scripts/kconfig`.

##2. `conf`的编译
`u-boot`编译配置执行`make rpi_3_32b_defconfig V=1`，对应于顶层makefile中的`%config`目标：
```
%config: scripts_basic outputmakefile FORCE
    $(Q)$(MAKE) $(build)=scripts/kconfig $@
```
在这里展开后相当于：
```
rpi_3_32b_defconfig: scripts_basic outputmakefile FORCE
    make -f ./scripts/Makefile.build obj=scripts/kconfig rpi_3_32b_defconfig
```
这个规则中，生成`rpi_3_32b_defconfig`后，会指定参数`obj=scripts/kconfig`和`rpi_3_32b_defconfig`进入`scripts/Makefile.build`进行编译。

`scripts/Makefile.build`中会根据`obj=scripts/kconfig`包含`scripts/kconfig`文件夹下的子`Makefile`：
```
# The filename Kbuild has precedence over Makefile
kbuild-dir := $(if $(filter /%,$(src)),$(src),$(srctree)/$(src))
kbuild-file := $(if $(wildcard $(kbuild-dir)/Kbuild),$(kbuild-dir)/Kbuild,$(kbuild-dir)/Makefile)
include $(kbuild-file)
```

`scripts/kconfig/Makefile`中相应的规则为：
```
%_defconfig: $(obj)/conf
    $(Q)$< $(silent) --defconfig=arch/$(SRCARCH)/configs/$@ $(Kconfig)
```
在这里展开为：
```
rpi_3_32b_defconfig: scripts/kconfig/conf
    scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig
```
由于`rpi_3_32b_defconfig`依赖于`scripts/kconfig/conf`，所以`conf`将会被编译。
`conf`依赖于`conf.c`和`zconf.tab.c`，后者进一步包含所需要的词法分析文件，整个编译链接过程如下：
```shell
make -f ./scripts/Makefile.build obj=scripts/kconfig rpi_3_32b_defconfig
  cc -Wp,-MD,scripts/kconfig/.conf.o.d -Wall -Wstrict-prototypes -O2 -fomit-frame-pointer   -I/usr/include/ncursesw   -DCURSES_LOC="<ncurses.h>" -DLOCALE   -c -o scripts/kconfig/conf.o scripts/kconfig/conf.c
  cat scripts/kconfig/zconf.tab.c_shipped > scripts/kconfig/zconf.tab.c
  cat scripts/kconfig/zconf.lex.c_shipped > scripts/kconfig/zconf.lex.c
  cat scripts/kconfig/zconf.hash.c_shipped > scripts/kconfig/zconf.hash.c
  cc -Wp,-MD,scripts/kconfig/.zconf.tab.o.d -Wall -Wstrict-prototypes -O2 -fomit-frame-pointer   -I/usr/include/ncursesw   -DCURSES_LOC="<ncurses.h>" -DLOCALE  -Iscripts/kconfig -c -o scripts/kconfig/zconf.tab.o scripts/kconfig/zconf.tab.c
  cc  -o scripts/kconfig/conf scripts/kconfig/conf.o scripts/kconfig/zconf.tab.o  
```

（执行`make xxx_defconfig`时打开`V=1`选项可以看到整个过程）

除了`make xxx_defconfig`配置过程外，`u-boot`正式编译过程中也会有对应的依赖，见顶层的makefile：
```
include/config/%.conf: $(KCONFIG_CONFIG) include/config/auto.conf.cmd
    $(Q)$(MAKE) -f $(srctree)/Makefile silentoldconfig
```
在这个规则中也会根据`silentoldconfig`再次检查并更新`scripts/kconfig/conf`文件。

##2. `conf`的调用
整个u-boot的配置和编译过程中`conf`被调用了2次。
###2.1 `make`配置过程调用

`u-boot`的make配置过程中，完成`conf`的编译后会随即调用命令：
```
scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig
```
去生成根目录下的`.config`文件。


###2.2 `make`编译过程调用
`u-boot`完成后，执行`make`命令开始编译时，会检查`.config`是否比`include/config/auto.conf`更新，规则如下：
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

这个规则的make输出log如下：
```shell
make -f ./scripts/Makefile.build obj=scripts/kconfig silentoldconfig
mkdir -p include/config include/generated
scripts/kconfig/conf  --silentoldconfig Kconfig
make -f ./scripts/Makefile.autoconf || \
        { rm -f include/config/auto.conf; false; }
if [ -d arch/arm/mach-bcm283x/include/mach ]; then  \
        dest=../../mach-bcm283x/include/mach;           \
    else                                \
        dest=arch-bcm283x;          \
    fi;                             \
    ln -fsn $dest arch/arm/include/asm/arch
...这里省略部分log...
touch include/config/auto.conf
```

实际执行`$(Q)$(MAKE) -f $(srctree)/Makefile silentoldconfig`命令的结果就是检查并更新`scripts/kconfig/conf`文件，然后调用之：
`scripts/kconfig/conf  --silentoldconfig Kconfig`。

为了检查这个命令的输出，可以直接在命令行上执行命令：
```
ygu@ubuntu:/opt/work/u-boot/u-boot-2016.09$ make -f ./Makefile silentoldconfig V=1
make -f ./scripts/Makefile.build obj=scripts/basic
rm -f .tmp_quiet_recordmcount
make -f ./scripts/Makefile.build obj=scripts/kconfig silentoldconfig
mkdir -p include/config include/generated
scripts/kconfig/conf  --silentoldconfig Kconfig
```

其实跟命令行上运行`make silentoldconfig`是一样的效果。
执行结果就是：

+ 在`include/config`下生成`auto.conf`和`auto.conf.cmd`，以及`tristate.conf`；
+ 在`include/generated`下生成`autoconf.h`文件；

###2.3 调用简述
简而言之：

+ 第一次调用生成`.config`

    `scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig`

+ 第二次调用生成`auto.conf`和`autoconf.h`

    `scripts/kconfig/conf  --silentoldconfig Kconfig`

##3. `conf`的源码分析
`conf`由`conf.o`和`zconf.tab.o`链接而来:
`conf.c`生成`conf.o`，是整个应用的主程序
`zconf.tab.c`生成`zconf.tab.o`，完成具体的词法和语法分析任务。

`zconf.tab.c`较为复杂，也比较枯燥，此处只是简单带过。

###3.1 第一次调用
`scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig`

###3.2 第二次调用
`scripts/kconfig/conf  --silentoldconfig Kconfig`
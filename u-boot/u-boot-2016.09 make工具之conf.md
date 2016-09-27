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

##3. `conf`的调用
整个u-boot的配置和编译过程中`conf`被调用了2次。
###3.1 `make`配置过程调用

`u-boot`的make配置过程中，完成`conf`的编译后会随即调用命令：
```
scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig
```
去生成根目录下的`.config`文件。
以下是生成前后的对比：
![make rpi_3_32b_defconfig 文件变化对比](https://github.com/guyongqiangx/blog/blob/dev/u-boot/make-tool-images-conf/make-rpi_3_32b_defconfig.png?raw=true)

###3.2 `make`编译过程调用
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

先执行`make rpi_3_32b_defconfig`，在执行`make silentoldconfig`的对比结果如下：
![make silentoldconfig后的文件变化](https://github.com/guyongqiangx/blog/blob/dev/u-boot/make-tool-images-conf/make-silentoldconfig.png?raw=true)

###3.3 调用简述
简而言之：

+ 第一次调用生成`.config`

    `scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig`

+ 第二次调用生成`auto.conf`和`autoconf.h`

    `scripts/kconfig/conf  --silentoldconfig Kconfig`

##4. `conf`的源码分析
`conf`由`conf.o`和`zconf.tab.o`链接而来，其中`conf.c`生成`conf.o`，是整个应用的主程序；`zconf.tab.c`生成`zconf.tab.o`，完成具体的词法和语法分析任务。

###4.1 `zconf.tab.c`
`zconf.tab.c`用于读取并分析整个`Kconfig`系统的文件，较为复杂，也比较枯燥，此处略过。

###4.2 `conf.c`
`conf.c`是`conf`主程序的文件，通过分析`main`函数可以大致了解操作流程：

####4.2.1 解析参数部分
```c
while ((opt = getopt_long(ac, av, "s", long_opts, NULL)) != -1) {
        if (opt == 's') {
            conf_set_message_callback(NULL);
            continue;
        }
        input_mode = (enum input_mode)opt;
        switch (opt) {
        case silentoldconfig:
            sync_kconfig = 1;
            break;
        case defconfig:
        case savedefconfig:
            defconfig_file = optarg;
            break;
        ...
        }
    }
    if (ac == optind) {
        printf(_("%s: Kconfig file missing\n"), av[0]);
        conf_usage(progname);
        exit(1);
    }
    name = av[optind];
    ...
```

**第一次调用** `scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig`

参数解析后：

+ `input_mode`: `defconfig_file`
+ `defconfig_file`: `arch/../configs/rpi_3_32b_defconfig`
+ `name` = `av[optind]`: `Kconfig`


**第二次调用** `scripts/kconfig/conf  --silentoldconfig Kconfig`

参数解析后：

+ `input_mode`: `silentoldconfig`，并设置`sync_kconfig`为1
+ `name` = `av[optind]`: `Kconfig`

####4.2.2 读取`Kconfig`系统配置文件

设置好`input_mode`和`name`后：

```c
    conf_parse(name);
    //zconfdump(stdout);
    if (sync_kconfig) {
        name = conf_get_configname();
        if (stat(name, &tmpstat)) {
            fprintf(stderr, _("***\n"
                "*** Configuration file \"%s\" not found!\n"
                "***\n"
                "*** Please run some configurator (e.g. \"make oldconfig\" or\n"
                "*** \"make menuconfig\" or \"make xconfig\").\n"
                "***\n"), name);
            exit(1);
        }
    }
```

+ 调用`conf_parse(name)`从`$(srctree)`目录下依次查找名为`Kconfig`的文件，然后将取得的信息存放到链表中。
+ 如果是`silentoldconfig`，即`sync_kconfig=1`，还要调用`conf_get_configname()`并检查顶层目录下的`.config`文件是否存在。

####4.2.3 读取指定的配置文件
```c
    switch (input_mode) {
    case defconfig:
        if (!defconfig_file)
            defconfig_file = conf_get_default_confname();
        if (conf_read(defconfig_file)) {
            printf(_("***\n"
                "*** Can't find default configuration \"%s\"!\n"
                "***\n"), defconfig_file);
            exit(1);
        }
        break;
    case savedefconfig:
    case silentoldconfig:
    case ...:
        conf_read(NULL);
        break;
    ...
    default:
        break;
    }
```

+ 如果是`defconfig`，调用`conf_read(defconfig_file)`读取指定的配置文件`arch/../configs/rpi_3_32b_defconfig`
+ 如果是`silentoldconfig`，调用`conf_read(NULL)`读取生成的`.config`。（`conf_read`传入的参数为`NULL`，在`conf_read_simple`会将读取的文件指向`.config`）

####4.2.4 检查更行设置
接下来：
```c
    if (sync_kconfig) {
        if (conf_get_changed()) {
            name = getenv("KCONFIG_NOSILENTUPDATE");
            if (name && *name) {
                fprintf(stderr,
                    _("\n*** The configuration requires explicit update.\n\n"));
                return 1;
            }
        }
        valid_stdin = tty_stdio;
    } 

    switch (input_mode) {
    case ...:
        break;
    case defconfig:
        conf_set_all_new_symbols(def_default);
        break;
    case savedefconfig:
        break;
    case ...:
    case silentoldconfig:
        /* Update until a loop caused no more changes */
        do {
            conf_cnt = 0;
            check_conf(&rootmenu);
        } while (conf_cnt &&
             (input_mode != listnewconfig &&
              input_mode != olddefconfig));
        break;
    }
```

+ 如果是`silentoldconfig`，检查`.config`是否被改动过，并检查各项设置的有效性
+ 如果是`defconfig`，设置默认值

####4.2.5 更新`.config`，生成相应文件
最后：
```c 
    if (sync_kconfig) {
        /* silentoldconfig is used during the build so we shall update autoconf.
         * All other commands are only used to generate a config.
         */
        if (conf_get_changed() && conf_write(NULL)) {
            fprintf(stderr, _("\n*** Error during writing of the configuration.\n\n"));
            exit(1);
        }
        if (conf_write_autoconf()) {
            fprintf(stderr, _("\n*** Error during update of the configuration.\n\n"));
            return 1;
        }
    } else if (input_mode == savedefconfig) {
        if (conf_write_defconfig(defconfig_file)) {
            fprintf(stderr, _("n*** Error while saving defconfig to: %s\n\n"),
                defconfig_file);
            return 1;
        }
    } else if (input_mode != listnewconfig) {
        if (conf_write(NULL)) {
            fprintf(stderr, _("\n*** Error during writing of the configuration.\n\n"));
            exit(1);
        }
    }
```

+ 如果是`silentoldconfig`：

    * 调用`conf_get_changed()`检查是否更新过，然后调用`conf_write(NULL)`将更新的项写入到`.config`文件中
    * 调用`conf_write_autoconf()`更新以下文件：
        - `include/generated/autoconf.h`
        - `include/config/auto.conf.cmd`
        - `include/config/tristate.conf`
        - `include/config/auto.conf`

+ 如果是`defconfig`，进入最后一个`(input_mode != listnewconfig)`分支，调用`conf_write(NULL)`，将读取到的所有配置写入`.config`文件中

##5. 总结
+ 配置时执行`make rpi_3_32b_defconfig`会根据规则生成`scripts/kconfig/conf`：

```
    rpi_3_32b_defconfig: scripts_basic outputmakefile FORCE
        make -f ./scripts/Makefile.build obj=scripts/kconfig rpi_3_32b_defconfig
```
+ 生成`conf`工具后立即调用并根据默认配置在根目录下生成`.config`文件:
```
    scripts/kconfig/conf  --defconfig=arch/../configs/rpi_3_32b_defconfig Kconfig
```
+ 编译时执行`silentoldconfig`
```
    scripts/kconfig/conf --silentoldconfig Kconfig
```

    * 检查并分析系统中各个`Kconfig`文件
    * 同配置时生成的`.config`比较，更新`.config`文件
    * 生成相应的其它文件供下一步编译使用：
        - `include/generated/autoconf.h`
        - `include/config/auto.conf.cmd`
        - `include/config/tristate.conf`
        - `include/config/auto.conf`


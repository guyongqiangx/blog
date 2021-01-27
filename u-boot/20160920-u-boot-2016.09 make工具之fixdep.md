[TOC]

#u-boot-2016.09 make工具之fixdep

##1. 概述
`fixdep`工具的源码位于`scripts/basic/fixdep.c`，代码本身并不复杂。但作用是什么？哪里调用，如何调用，输入和输出是什么？咋一看却不甚清楚。
本文废话太多，如果只想看结论，请直接跳转到文末查看“TL;DR”一节。

##2. 哪里调用？

到底哪里调用了fixdep？
###2.1 直接搜索fixdep
不妨在u-boot代码里搜索下：
```shell
ygu@ubuntu:/opt/work/u-boot/u-boot-2016.09$ grep -rnw fixdep . --exclude-dir=basic
./scripts/Kbuild.include:230:# if_changed_dep  - as if_changed, but uses fixdep to reveal dependencies
./scripts/Kbuild.include:266:   scripts/basic/fixdep $(depfile) $@ '$(make-cmd)' > $(dot-target).tmp;\
./scripts/Makefile.build:272:   scripts/basic/fixdep $(depfile) $@ '$(call make-cmd,cc_o_c)' >    \
./board/bosch/shc/README:30:  HOSTCC  scripts/basic/fixdep
```

>`grep`参数说明:<br>
>`-r`，递归搜索目录<br>
>`-n`，显示匹配结果的行号<br>
>`-w`，按单词搜索<br>
>`--exclude-dir=basic`，忽略basic子目录，此目录是`fixdep.c`自身的代码目录

总共有4条匹配结果，只有在`scripts/Kbuild.include`的266行和`scripts/Makefile.build`的272行有调用，其余都跟fixdep调用无关。

####2.1.1 `if_changed_dep`调用`fixdep`
`scripts/Kbuild.include`中的匹配结果是自定义函数`if_changed_dep`调用了`fixdep`：
```makefile
# Execute the command and also postprocess generated .d dependencies file.
if_changed_dep = $(if $(strip $(any-prereq) $(arg-check) ),                  \
	@set -e;                                                             \
	$(echo-cmd) $(cmd_$(1));                                             \
	scripts/basic/fixdep $(depfile) $@ '$(make-cmd)' > $(dot-target).tmp;\
	rm -f $(depfile);                                                    \
	mv -f $(dot-target).tmp $(dot-target).cmd)
```
进一步搜索对`if_changed_dep`的调用：
```
ygu@ubuntu:/opt/work/u-boot/u-boot-2016.09$ grep -rnw if_changed_dep .
./scripts/Makefile.spl:299:     $(call if_changed_dep,cpp_lds)
./scripts/Makefile.lib:299:     $(call if_changed_dep,dtc)
./scripts/Kbuild.include:229:# if_changed_dep  - as if_changed, but uses fixdep to reveal dependencies
./scripts/Kbuild.include:263:if_changed_dep = $(if $(strip $(any-prereq) $(arg-check) ),                  \
./scripts/Makefile.build:175:   $(call if_changed_dep,cc_s_c)
./scripts/Makefile.build:181:   $(call if_changed_dep,cc_i_c)
./scripts/Makefile.build:296:   $(call if_changed_dep,cc_lst_c)
./scripts/Makefile.build:310:   $(call if_changed_dep,as_s_S)
./scripts/Makefile.build:316:   $(call if_changed_dep,as_o_S)
./scripts/Makefile.build:328:   $(call if_changed_dep,cpp_lds_S)
./scripts/Makefile.host:99:     $(call if_changed_dep,host-csingle)
./scripts/Makefile.host:116:    $(call if_changed_dep,host-cobjs)
./scripts/Makefile.host:133:    $(call if_changed_dep,host-cxxobjs)
./Kbuild:44:    $(call if_changed_dep,cc_s_c)
./Kbuild:65:    $(call if_changed_dep,cc_s_c)
./arch/arm/imx-common/Makefile:48:      $(call if_changed_dep,cpp_cfg)
./arch/sandbox/cpu/Makefile:22: $(call if_changed_dep,cc_os.o)
./arch/sandbox/cpu/Makefile:24: $(call if_changed_dep,cc_os.o)
./arch/sandbox/cpu/Makefile:33: $(call if_changed_dep,cc_eth-raw-os.o)
./examples/api/Makefile:64:     $(call if_changed_dep,as_o_S)
./Makefile:1118:        $(call if_changed_dep,cpp_lds)
./Makefile:1328:        $(call if_changed_dep,cpp_lds)
```

**检查以上所有对`if_changed_dep`调用的地方，都有一个共同点。那就是新生成一个目标时，调用`if_changed_dep`去生成它的依赖文件。**

例如，

+ `scripts/Makefile.lib`中将`%.dts`编译输出为`%.dtb`：
```
$(obj)/%.dtb: $(src)/%.dts FORCE
	$(call if_changed_dep,dtc)
```
+ `scripts/Makefile.build`中将`%.S`编译输出为`%.o`：
```
$(obj)/%.o: $(src)/%.S FORCE
	$(call if_changed_dep,as_o_S)
```
+ `scripts/Makefile.host`中将`%.c`编译输出为可执行文件`%`：`
```
$(host-csingle): $(obj)/%: $(src)/%.c FORCE
	$(call if_changed_dep,host-csingle)
```

**以上所有对`if_changed_dep`调用的地方，还有另外一个共同点，`if_changed_dep`的调用也还有另外一个特别的地方，就是除了`Makefile.host`中调用`if-_changed_dep`，是将`%.c`编译输出为`%.o`外，还没有其它的调用是用于编译`%.c`文件的。**

`Makefile.host`在`Kbuild`体系中，用于编译在在主机上运行的程序，而不是编译`u-boot`自身的文件。

####2.1.2 `rule_cc_o_c`调用`fixdep`
`scripts/Makefile.build`中的匹配结果是自定义宏`rule_cc_o_c`调用了`fixdep`：
```makefile
define rule_cc_o_c
	$(call echo-cmd,checksrc) $(cmd_checksrc)			  \
	$(call echo-cmd,cc_o_c) $(cmd_cc_o_c);				  \
	$(cmd_modversions)						  \
	$(call echo-cmd,record_mcount)					  \
	$(cmd_record_mcount)						  \
	scripts/basic/fixdep $(depfile) $@ '$(call make-cmd,cc_o_c)' >    \
	                                              $(dot-target).tmp;  \
	rm -f $(depfile);						  \
	mv -f $(dot-target).tmp $(dot-target).cmd
endef
```

进一步搜索对`rule_cc_o_c`的调用：
```shell
ygu@ubuntu:/opt/work/u-boot/u-boot-2016.09$ grep -rnw rule_cc_o_c .               
./scripts/Makefile.build:201:# (See cmd_cc_o_c + relevant part of rule_cc_o_c)
./scripts/Makefile.build:266:define rule_cc_o_c
```
结果显示除了定义之外，并没有显示`rule_cc_o_c`被引用。那换一种方式，搜索`cc_o_c`：
```shell
ygu@ubuntu:/opt/work/u-boot/u-boot-2016.09$ grep -rnw cc_o_c .     
./scripts/Makefile.build:268:   $(call echo-cmd,cc_o_c) $(cmd_cc_o_c);                            \
./scripts/Makefile.build:272:   scripts/basic/fixdep $(depfile) $@ '$(call make-cmd,cc_o_c)' >    \
./scripts/Makefile.build:281:   $(call if_changed_rule,cc_o_c)
./scripts/Makefile.build:287:   $(call if_changed_rule,cc_o_c)
./examples/api/Makefile:60:     $(call if_changed_rule,cc_o_c)
```
得到5项搜索结果，其前两行实际上是宏`rule_cc_o_c`定义本身，最后一行是`u-boot`例子里面的调用，也可以忽略。
重点是`scripts/Makefile.build`的中间两项：
```
# Built-in and composite module parts
$(obj)/%.o: $(src)/%.c $(recordmcount_source) FORCE
	$(call cmd,force_checksrc)
	$(call if_changed_rule,cc_o_c)

# Single-part modules are special since we need to mark them in $(MODVERDIR)

$(single-used-m): $(obj)/%.o: $(src)/%.c $(recordmcount_source) FORCE
	$(call cmd,force_checksrc)
	$(call if_changed_rule,cc_o_c)
	@{ echo $(@:.o=.ko); echo $@; } > $(MODVERDIR)/$(@F:.o=.mod)
```

很显然，`$(simple-used-m)`规则从字面上看是用于生成`.ko`文件的，而`u-boot`并不生成模块文件，所以实际上用于编译`%.c`生成`%.o`的是前一个规则。

###2.1.3 `fixdep`调用结论
从前两节的分析看，以下情况会调用`fixdep`进行处理：

+ 新生成一个目标时，调用`if_changed_dep`检测并更新依赖文件，其中`if_changed_dep`会调用`fixdep`去处理依赖文件，但是将用于生成`u-boot`的`%.c`文件编译为`%.o`规则除外
+ 将生成`u-boot`的`%.c`编译为`%.o`时会调用`rule_cc_o_c`，`rule_cc_o_c`中又会调用`fixdep`生成`%.o`的依赖文件`.%.cmd`

##3. 如何调用？

通过`fixdep.c`的`usage()`函数，我们可以看到`fixdep`的用法：
```
fixdep <depfile> <target> <cmdline>
```
`fixdep`接收三个参数，分别是：

+ `<depfile>`：编译产生的依赖文件*.d
+ `<target>`：编译生成的目标
+ `<cmdline>`：编译使用的命令


##4. 输入和输出
看一看调用`if_changed_dep`的实例：
修改`if_changed_dep`中，显示调用`fixdep`的命令，并保留原有的依赖文件:
```
if_changed_dep = $(if $(strip $(any-prereq) $(arg-check) ),                  \
	@set -e;                                                             \
	$(echo-cmd) $(cmd_$(1));                                             \
	echo 'call fixdep: scripts/basic/fixdep $(depfile) $@ "$(make-cmd)"';\
	scripts/basic/fixdep $(depfile) $@ '$(make-cmd)' > $(dot-target).tmp;\
	mv -f $(dot-target).tmp $(dot-target).cmd)
```
重新执行`make rpi_3_32b_defconfig`，得到如下log:
```shell
ygu@fs-ygu:/opt/work/u-boot/u-boot-2016.09$ make rpi_3_32b_defconfig
  HOSTCC  scripts/basic/fixdep
call fixdep: scripts/basic/fixdep scripts/basic/.fixdep.d scripts/basic/fixdep "cc -Wp,-MD,scripts/basic/.fixdep.d -Wall -Wstrict-prototypes -O2 -fomit-frame-pointer      -o scripts/basic/fixdep scripts/basic/fixdep.c  "
  HOSTCC  scripts/kconfig/conf.o
call fixdep: scripts/basic/fixdep scripts/kconfig/.conf.o.d scripts/kconfig/conf.o "cc -Wp,-MD,scripts/kconfig/.conf.o.d -Wall -Wstrict-prototypes -O2 -fomit-frame-pointer    -I/usr/include/ncursesw   -DCURSES_LOC="<ncurses.h>" -DLOCALE   -c -o scripts/kconfig/conf.o scripts/kconfig/conf.c"
  SHIPPED scripts/kconfig/zconf.tab.c
  SHIPPED scripts/kconfig/zconf.lex.c
  SHIPPED scripts/kconfig/zconf.hash.c
  HOSTCC  scripts/kconfig/zconf.tab.o
call fixdep: scripts/basic/fixdep scripts/kconfig/.zconf.tab.o.d scripts/kconfig/zconf.tab.o "cc -Wp,-MD,scripts/kconfig/.zconf.tab.o.d -Wall -Wstrict-prototypes -O2 -fomit-frame-pointer    -I/usr/include/ncursesw   -DCURSES_LOC="<ncurses.h>" -DLOCALE  -Iscripts/kconfig -c -o scripts/kconfig/zconf.tab.o scripts/kconfig/zconf.tab.c"
  HOSTLD  scripts/kconfig/conf
#
# configuration written to .config
#
```
从log可以看到，执行`make rpi_3_32b_defconfig`一共调用了3次`fixdep`，以处理`scripts/basic/.fixdep.d`为例，调用的命令的参数分别为：

+ `depfile = scripts/basic/.fixdep.d`
+ `target  = scripts/basic/fixdep`
+ `cmdline = "cc -Wp,-MD,scripts/basic/.fixdep.d -Wall -Wstrict-prototypes -O2 -fomit-frame-pointer      -o scripts/basic/fixdep scripts/basic/fixdep.c  "`

###4.1 输入和输出
编译过程中生成的依赖文件`.fixdep.d`作为输入，经过处理得到`.fixdep.cmd`文件，对比其中的变化：

原来的`.fixdep.d`:
```makefile
fixdep.o: scripts/basic/fixdep.c /usr/include/stdc-predef.h \
 ... \ /* 省略中间的若干头文件 */
 /usr/include/x86_64-linux-gnu/bits/in.h
```

新生成的`.fixdep.cmd`：
```makefile
cmd_scripts/basic/fixdep := "cc -Wp,-MD,...scripts/basic/fixdep.c"

source_scripts/basic/fixdep := scripts/basic/fixdep.c

deps_scripts/basic/fixdep := xxx.h \
    $(wildcard include/config/his/driver.h) \
    $(wildcard include/config/my/option.h) \
    $(wildcard include/config/.h) \
    $(wildcard include/config/foo.h) \
    $(wildcard include/config/boom.h) \
    $(wildcard include/config/is/.h) \
  /usr/include/stdc-predef.h \
  ... \ /* 省略中间的若干头文件，同.fixdep.d */
  /usr/include/x86_64-linux-gnu/bits/in.h \

scripts/basic/fixdep: $(deps_scripts/basic/fixdep)

$(deps_scripts/basic/fixdep):
```

新的`.fixdep.cmd`中增加了跟目标相关的变量`cmd_xxx`，`source_xxx`，`deps_xxx`和目标`xxx`对`deps_xxx`的依赖规则。

`fixdep.c`的代码操作比较简单，这里略去对代码的分析。

>
>**有个疑问，没搞懂`dep_xxx`开始部分匹配`wildcard`包含的头文件到底是如何来的？
>很明显，这部分是由`use_config()`函数生成的，具体如何生成，大神们的请来指点下。**

###4.2 `.*.cmd`的引用

顶层Makefile是这样引用`.*.cmd`文件的：
```makefile
# read all saved command lines

targets := $(wildcard $(sort $(targets)))
cmd_files := $(wildcard .*.cmd $(foreach f,$(targets),$(dir $(f)).$(notdir $(f)).cmd))

ifneq ($(cmd_files),)
  $(cmd_files): ;	# Do not try to update included dependency files
  include $(cmd_files)
endif
```
根据待生成的目标`targets`生成`cmd_files`列表，然后用`include`指令包含所有这些`.*.cmd`文件。
以生成的`arm/cpu/armv7/.start.o.cmd`为例，文件中包含：
```makefile
cmd_arch/arm/cpu/armv7/start.o := arm-linux-gnueabi-gcc ... -c -o arch/arm/cpu/armv7/start.o arch/arm/cpu/armv7/start.S

source_arch/arm/cpu/armv7/start.o := arch/arm/cpu/armv7/start.S

deps_arch/arm/cpu/armv7/start.o := \
    $(wildcard include/config/omap44xx.h) \
    $(wildcard include/config/spl/build.h) \
    ...

arch/arm/cpu/armv7/start.o: $(deps_arch/arm/cpu/armv7/start.o)

$(deps_arch/arm/cpu/armv7/start.o):
```

实际上只用到了依赖规则：
```makefile
deps_arch/arm/cpu/armv7/start.o := \
    $(wildcard include/config/omap44xx.h) \
    $(wildcard include/config/spl/build.h) \
    ...

arch/arm/cpu/armv7/start.o: $(deps_arch/arm/cpu/armv7/start.o)

$(deps_arch/arm/cpu/armv7/start.o):
```
对于`cmd_arch/arm/cpu/armv7/start.o`和`source_arch/arm/cpu/armv7/start.o`，u-boot编译时并没有用到。

至于cmd_xxx和source_xxx，我能够想到的用处就是存放一些编译用到的信息，例如cmd_xxx表示生成所用的命令，source_xxx表示生成目标的source code，如果想看某一个文件时如何生成的，去检查`.*.cmd`文件就行了。其实这也是蛮有用的。

例如，我想看看文件`u-boot.bin`是如何生成的，那就去检查`.u-boot.bin.cmd`，一目了然了：
```makefile
cmd_u-boot.bin := cp u-boot-nodtb.bin u-boot.bin
```

我去，编译生成的`u-boot.bin`竟然是`u-boot-nodtb.bin`通过`cp`来的~~哈哈。


##5. TL;DR 
上面部分主要表述整个分析的过程，废话太多。以下简略说明重点。

编译时，编译器会根据选项`-MD`自动生成依赖文件`*.d`，用`fixdep`更新`*.d`文件生成新的依赖文件`.*.cmd`。

`fixdep`被两个地方调用：

+ `rule_cc_o_c`：编译u-boot自身的`*.c`文件时，`rule_cc_o_c`调用`fixdep`去更新生成`%.c`的依赖文件`.%.cmd`

+ `if_changed_dep`：适用于除了上述的`rule_cc_o_c`外的其它目标依赖文件的生成，例如生成主机上执行的程序，处理dts文件等，也包括汇编文件生成`*.o`，生成`*.s`，`*.lst`等。

通过查看`fixdep`输出的`.*.cmd`文件可以知道对应的目标文件`*`是如何生成的。





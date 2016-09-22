备注：如果只关心shell问题和解决的办法，请直接阅读第2节和第5节。

#1. 问题的由来
这是以前遇到的一个问题，最近调试makefile想起来了，总结一下。
当时编译一个公司早期发布的linux代码，但在我Ubuntu 14.04上编译的时候却出现了一个错误：

```
cp -f defconfigs/defconfig-brcm-uclinux-rootfs-7400d0_be .config
rm -f linux-2.6.x/.config
(. .config; \
        echo "cp -f vendors///config.linux-2.6.x /.config;"; \
                cp -f vendors///config.linux-2.6.x /.config; \
        )
/bin/sh: line 0: .: .config: file not found
make[2]: *** [vmlinuz-initrd-7400d0_be] Error 1

```
可以肯定的是这个代码包在正式发布的时候一定是可以编译的，所以我相信这是一个环境相关的问题，从错误信息看，实际上是用“.”去执行一个shell脚本时报错。

#2. 问题的复现
经简化，可以用一个简单的make工程来复现这个问题：

```
.PHONY: all clean

all: hello.sh
	. hello.sh

clean:
	rm -rf hello.sh

hello.sh:
	@echo "#!/bin/bash" > hello.sh
	@echo "" >> hello.sh
	@echo "echo 'hello'" >> hello.sh

```

在这个makefile中先生成一个hello.sh的脚本（脚本只是简单回显一个“hello”字符串），然后再运行命令“. hello.sh”命令执行脚本，错误信息如下：

```
ygu@fs-ygu:/opt/work/make-example$ make
. hello.sh
/bin/sh: line 0: .: hello.sh: file not found
make: *** [all] Error 1

```
#3. 几个关于错误的实验
在Ubuntu命令行用“. hello.sh”单独执行是可以的：
```
ygu@fs-ygu:/opt/work/make-example$ . hello.sh
hello

```
##a.	用“source”命令执行shell脚本
如果将“. hello.sh”修改为“source hello.sh”:
```
.PHONY: all clean

all: hello.sh
	source hello.sh

clean:
	rm -rf hello.sh

hello.sh:
	@echo "#!/bin/bash" > hello.sh
	@echo "" >> hello.sh
	@echo "echo 'hello'" >> hello.sh

```
make时会报错：
```
ygu@fs-ygu:/opt/work/make-example$ make
source hello.sh
make: source: Command not found
make: *** [all] Error 127

```
##b. 直接执行shell脚本
###i. 直接执行脚本
如果将“. hello.sh”修改为“./hello.sh”:

```
.PHONY: all clean

all: hello.sh
	./hello.sh

clean:
	rm -rf hello.sh

hello.sh:
	@echo "#!/bin/bash" > hello.sh
	@echo "" >> hello.sh
	@echo "echo 'hello'" >> hello.sh

```

则make时报另外一个错误：

```
gu@fs-ygu:/opt/work/make-example$ make
./hello.sh
make: execvp: ./hello.sh: Permission denied
make: *** [all] Error 127

```
###ii.	给脚本增加可执行权限
进一步修改，让hello.sh具有可执行权限：

```
.PHONY: all clean

all: hello.sh
	chmod a+x hello.sh
	./hello.sh

clean:
	rm -rf hello.sh

hello.sh:
	@echo "#!/bin/bash" > hello.sh
	@echo "" >> hello.sh
	@echo "echo 'hello'" >> hello.sh

```
则可以正确运行：

```
ygu@fs-ygu:/opt/work/make-example$ make
chmod a+x hello.sh
./hello.sh
hello
```
##c.	makefile中SHELL的检查
当前我的Ubuntu上默认执行的shell是/bin/bash，但makefile执行提示的是/bin/sh，可以在makefile中检查SHELL的环境变量和当前makefile中的设定：

```
.PHONY: all clean

all: hello.sh
	@echo 'Linux SHELL='$$SHELL
	@echo ' Make SHELL='$(SHELL)
	. hello.sh

clean:
	rm -rf hello.sh

hello.sh:
	@echo "#!/bin/bash" > hello.sh
	@echo "" >> hello.sh
	@echo "echo 'hello'" >> hello.sh

```

执行结果：

```
ygu@fs-ygu:/opt/work/make-example$ make
Linux SHELL=/bin/bash
 Make SHELL=/bin/sh
. hello.sh
/bin/sh: line 0: .: hello.sh: file not found
make: *** [all] Error 1

```
从打印输出的信息看，系统环境变量SHELL为/bin/bash，而makefile的变量SHELL确实为/bin/sh

##d. 实验结论
以上实验说明脚本本身是没有问题的，问题就在命令“. hello.sh”上。

#4.	make手册的说明
查阅make手册：https://www.gnu.org/software/make/manual/make.html
其中关于shell的设置，其中5.3.2节有如下描述：

> 5.3.2 Choosing the Shell
> 
>    The program used as the shell is taken from the variable SHELL. If this variable is not set in your makefile, the program /bin/sh is used as the shell. The argument(s) passed to the shell are taken from the variable .SHELLFLAGS. The default value of .SHELLFLAGS is -c normally, or -ec in POSIX-conforming mode.
>   
>   Unlike most variables, the variable SHELL is never set from the environment. This is because the SHELL environment variable is used to specify your personal choice of shell program for interactive use. It would be very bad for personal choices like this to affect the functioning of makefiles. 

大意是说make使用SHELL变量来指定执行shell命令的程序，如果makefile中没有设置SHELL变量，则默认使用/bin/sh。但是跟其他大多数变量不一样的是SHELL变量并不从系统环境变量中继承，这是因为系统环境变量“SHELL”用于指定哪个程序被用来作为用户和系统交互的接口程序，他对于不存在交互过程的makefile是不合适的。

#5. makefile中设置SHELL
通过在makefile中设置SHELL=/bin/bash，问题得到了解决：

```
SHELL=/bin/bash

.PHONY: all clean

all: hello.sh
	. hello.sh

clean:
	rm -rf hello.sh

hello.sh:
	@echo "#!/bin/bash" > hello.sh
	@echo "" >> hello.sh
	@echo "echo 'hello'" >> hello.sh

```

makefile的执行：

```
ygu@fs-ygu:/opt/work/make-example$ make
. hello.sh
hello

```
执行的结果跟预期一致，问题得到了解决。
#6. 关于/bin/sh和/bin/bash的疑问
现在还有一个问题是，在我当前Ubuntu 14.04的机器上，/bin/sh是软链接到/bin/bash的，如下：

```
ygu@fs-ygu:/opt/work/make-example$ ls -l /bin
-rwxr-xr-x 1 root root 1021112 Oct  8  2014 bash
lrwxrwxrwx 1 root root       4 Aug 14  2014 sh -> bash
```

为什么/bin/bash可以正确执行而/bin/sh却不能呢？

这就涉及到/bin/sh和/bin/bash的区别了，这里有一篇文章谈到了这个问题：
《/bin/bash和/bin/sh的区别》： http://www.cnblogs.com/baizhantang/archive/2012/09/11/2680453.html

大体而言，现在的linux中sh一般设置为bash的软链接，使用sh调用执行脚本相当于打开了bash的POSIX标准模式，也就是说 /bin/sh 相当于 /bin/bash --posix
我们可以修改makefile来验证一下：

```
SHELL=/bin/bash --posix
#SHELL=/bin/bash

.PHONY: all clean

all: hello.sh
        . hello.sh

clean:
        rm -rf hello.sh

hello.sh:
        @echo "#!/bin/bash" > hello.sh
        @echo "" >> hello.sh
        @echo "echo 'hello'" >> hello.sh

```
make时会报错：

```
ygu@fs-ygu:/opt/work/make-example$ make
. hello.sh
/bin/bash: line 0: .: hello.sh: file not found
make: *** [all] Error 1

```
这个错误跟默认SHELL为/bin/sh的错误一样。

#7. 结语
- 以前在很多makefile中也看到过对SHELL的设置，但是没看到哪里有引用，不清楚为什么要设置SHELL；
- 以前在很多make工程中没有设置SHELL执行起来也好像没有问题，所以一直也没有发现SHELL问题；
建议：当执行makefile中的shell命令不成功时，先检查下SHELL变量的设置。

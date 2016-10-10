##1. 错误描述
新搭建的`build server`，编译`kernel`时报错：
```
'make menuconfig' requires the ncurses libraries.
```

详细的错误信息如下：
```
ygu@stb-lab-04:/opt/linux/3.14-1.14/rootfs$ make menuconfig-linux
make -C linux ARCH=arm menuconfig
make[1]: Entering directory `/opt/linux/3.14-1.14/linux'
*** Unable to find the ncurses libraries or the
*** required header files.
*** 'make menuconfig' requires the ncurses libraries.
*** 
 *** Install ncurses (ncurses-devel) and try again.
*** 
make[2]: *** [scripts/kconfig/dochecklxdialog] Error 1
make[1]: *** [menuconfig] Error 2
make[1]: Leaving directory `/opt/linux/3.14-1.14/linux'
make: *** [menuconfig-linux] Error 2
```

##2. 解决办法
这个是新安装系统后编译`kernel`时最常见的错误。

**为什么会出错呢？这跟`ncurses`的用途有关。**

维基百科上是这么介绍的：
>[https://en.wikipedia.org/wiki/Ncurses](https://en.wikipedia.org/wiki/Ncurses)

>**ncurses** (new curses) is a programming library providing an application programming interface (API) that allows the programmer to write text-based user interfaces in a terminal-independent manner. It is a toolkit for developing "GUI-like" application software that runs under a terminal emulator. It also optimizes screen changes, in order to reduce the latency experienced when using remote shells.

简单说来，就是`ncurses`在字符终端（`terminal`）提供了类`GUI`的用户接口，如下：
![linux menuconfig]()

安装`libncurses5-dev`包得以解决：
```
sudo apt-get install libncurses5-dev
```
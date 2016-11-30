
##`Bootchart`简介
`Bootchart`官网[`http://www.bootchart.org`](http://www.bootchart.org)，已经很久没有更新了。

`Bootchart`的目的是将启动阶段的性能可视化（`Boot Process Performance Visualization`）。具体做法是在启动阶段通过采样`/proc`文件系统来搜集启动阶段的信息（如`CPU`负载，进程信息，磁盘访问等），然后通过另外的工具将搜集到的数据以可视化的方式进行输出。

因此，`bootchart`分为两个部分：

+ 采样程序`bootchartd`，系统启动后的第一个进程，采样并搜集启动过程中的`/proc`数据，启动完成后将采样数据压缩存放到`/var/log/bootchart/bootlog.tgz`文件中
+ 外部工具`pybootchartgui`，处理`bootlog.tgz`文件，输出为图片
	- 对于`PC`，系统会在启动完成后自动生成`bootlog.png`文件
	- 对于嵌入式系统，需要将`bootlog.tgz`导出到`PC`上进行处理

下图是一个嵌入式系统上的`bootchart`输出的示例图片：
![`bootchart`示例输出](https://github.com/guyongqiangx/blog/blob/dev/bootchart/images/bootchart-example.png?raw=true)

我在虚拟机上安装`bootchart`并抓取了启动过程数据，[点这里查看`Ubuntu 12.04`启动后生成的图片](https://github.com/guyongqiangx/blog/blob/dev/bootchart/images/vm-ubuntu-precise-20161130.png?raw=true)。

在`bootchart`生成的图像中，可以清楚的看到启动过程中`CPU`负载、磁盘吞吐和各进程实时的情况。



##`Bootchart`配置

`Busybox`从[`v1.17`](https://git.busybox.net/busybox/tag/?h=1_17_0)版本开始引入`bootchartd`。
相比`PC`，嵌入式系统没有完备的`Bootchart`工具，启动过程中采样的数据需要导出在`PC`上进行处理。

`Busybox`上通过执行`make menuconfig`配置`bootchartd`，具体位置如下：

```
ygu@ubuntu:/opt/work/busybox$ make menuconfig

    Busybox Settings   --->
--- Applets
    ...
    Init Utilities   --->
        [*] bootchartd
        [*]   Compatible, bloated header
        [*]   Support bootchartd.conf
    ...
```

默认设置打开所有`bootchartd`设置：

![`Busybox`中`bootchartd`的配置](https://github.com/guyongqiangx/blog/blob/dev/bootchart/images/busybox-bootchartd-details-1.21.1.png?raw=true)

设置总共有3项：

+ 选项`[*] bootchartd`，设置`[BOOTCHARTD =y]`，是`bootchart`功能开关
+ 选项`[*]   Compatible, bloated header`，设置`[FEATURE_BOOTCHARTD_BLOATED_HEADER =y]`，设置后`bootchartd`会生成一个包含类似如下信息的`header`文件：
```
version = 0.8
title = Boot chart for (none) (Thu Jan  1 00:01:05 UTC 1970)
system.uname = Linux 3.3.8-4.0 #6 SMP Tue Nov 29 14:23:14 CST 2016 mips
system.kernel.options = ubiroot init=/sbin/bootchartd ubi.mtd=rootfs rootfstype=ubifs root=ubi0:rootfs
```
+ 选项`[*]   Support bootchartd.conf`，设置`[FEATURE_BOOTCHARTD_CONFIG_FILE =y]`，设置后`bootchartd`启动时会尝试读取并解析配置文件`/etc/bootchartd.conf`，配置文件的格式类似如下：
```
#
# supported options:
#

# Sampling period (in seconds)
SAMPLE_PERIOD=0.2

#
# not yet supported:
#

# tmpfs size
# (32 MB should suffice for ~20 minutes worth of log data, but YMMV)
TMPFS_SIZE=32m

# Whether to enable and store BSD process accounting information.  The
# kernel needs to be configured to enable v3 accounting
# (CONFIG_BSD_PROCESS_ACCT_V3). accton from the GNU accounting utilities
# is also required.
PROCESS_ACCOUNTING="no"

# Tarball for the various boot log files
BOOTLOG_DEST=/var/log/bootchart.tgz

# Whether to automatically stop logging as the boot process completes.
# The logger will look for known processes that indicate bootup completion
# at a specific runlevel (e.g. gdm-binary, mingetty, etc.).
AUTO_STOP_LOGGER="yes"

# Whether to automatically generate the boot chart once the boot logger
# completes.  The boot chart will be generated in $AUTO_RENDER_DIR.
# Note that the bootchart package must be installed.
AUTO_RENDER="no"
```
从`busybox`中`bootchartd`实现的代码来看，仅支持`SAMPLE_PERIOD`和`SAMPLE_PERIOD`两个选项。当然，也可以不用设置`/etc/bootchartd.conf`而使用代码中默认的设置。

##`Bootchart`运行

`bootchart`的帮助信息：
```
Usage: bootchartd start [PROG ARGS]|stop|init

Options:
start: start background logging; with PROG, run PROG, then kill logging with USR1
stop: send USR1 to all bootchartd processes
init: start background logging; stop when getty/xdm is seen (for init scripts)
Under PID 1: start background logging, then execute $bootchart_init, /init, /sbin/init
This makes it possible to start bootchartd even before init by booting kernel with:
init=/sbin/bootchartd bootchart_init=/path/to/regular/init
```

从帮助信息可见`bootchartd`有两个用途：

+ `linux`启动时运行用于采样`linux`启动过程中的各项数据
+ 启动完成后运行，用于监测系统或指定应用程序

###1. `linux`启动时运行
这是使用最多的方式，在`linux`启动的命令行中指定`/sbin/bootchartd`为`init`进程。

+ 带`initramfs`的系统，需要在命令行指定`rdinit`
`rdinit=/sbin/bootchartd`

+ 非`initramfs`的系统，需要在命令行指定`init`
`init=/sbin/bootchartd`

`linux`启动中，会用`/sbin/bootchartd`创建第一个进程，然后在`bootchartd`中再`fork`一个真正的`init`进程。如果在启动的同时通过命令行指定了`bootchart_init`参数，则用这个参数指定的程序用于`fork`生成的`init`进程，否则依次使用默认的`/init`或`/sbin/init`作为`init`进程。如：

`init=/sbin/bootchartd bootchart_init=/path/to/regular/init`

###2. 监测系统或应用程序的运行情况
用于监测运行情况时需要给`bootchartd`指定参数，`start`参数开始监测，`stop`参数停止监测。

不过，系统启动后可以监测的手段较多，`bootchartd`工具并不是最优选择，非本文的介绍重点，暂略。

##`Bootchartd`源码分析


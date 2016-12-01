
##一、`Bootchart`简介
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



##二、`Bootchart`配置

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

##三、`Bootchart`运行

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

以下是我在博通7583参考平台上使用带文件系统的kernel启动的log:
```
CFE> 
CFE> boot -z -elf 192.168.1.95:7584a0/vmlinuz-initrd-7584a0 'rdinit=/sbin/bootchartd quiet'
Loader:elf Filesys:tftp Dev:eth0 File:192.168.1.95:7584a0/vmlinuz-initrd-7584a0 Options:rdinit=/sbin/bootchartd quiet
Loading: 0x80001000/11957248 0x80b68400/110224 Entry address is 0x8045f360
Closing network.
Starting program at 0x8045f360

Linux version 3.3.8-4.0 (ygu@fs-ygu) (gcc version 4.5.4 (Broadcom stbgcc-4.5.4-2.9) ) #5 SMP Tue Nov 29 14:23:04 CST 2016
Fetching vars from bootloader... found 14 vars.
Options: moca=0 sata=1 pcie=0 usb=1
Using 512 MB + 0 MB RAM (from CFE)
bootconsole [early0] enabled
CPU revision is: 0002a065 (Broadcom BMIPS4380)
FPU revision is: 00130001
Determined physical RAM map:
 memory: 10000000 @ 00000000 (usable)
 memory: 10000000 @ 20000000 (usable)
No PHY detected, not registering interface:1
starting pid 429, tty '': '/etc/init.d/rcS'
Mounting virtual filesystems
Starting mdev
* WARNING: THIS STB CONTAINS GPLv3 SOFTWARE
* GPLv3 programs must be removed in order to enable security.
* See: http://www.gnu.org/licenses/gpl-faq.html#Tivoization
Configuring eth0 interface
Configuring lo interface
Starting network services
starting pid 459, tty '': '/bin/cttyhack /bin/sh -l'
# 
# shell-init: error retrieving current directory: getcwd: cannot access parent directories: Success
#
# ls -lh /var/log/            
-rw-r--r--    1 root     root       28.9K Jan  1 00:01 bootlog.tgz
#
```

可以看到，系统启动完成后会在`/var/log`目录下生成`bootlog.tgz`文件（`PC`上采样的数据文件位于`/var/log/bootchartd/`目录下）。将文件`/var/log/bootlog.tgz`复制到`PC`上备用。

在主机上安装`bootchart`工具，安装的同时还会安装`pybootchartgui`用于将采集的数据转换为图片。
```
ygu@ubuntu:~$ sudo apt-get install bootchart
[sudo] password for ygu: 
Reading package lists... Done
Building dependency tree       
Reading state information... Done
The following NEW packages will be installed:
  bootchart
0 upgraded, 1 newly installed, 0 to remove and 0 not upgraded.
Need to get 0 B/11.0 kB of archives.
After this operation, 127 kB of additional disk space will be used.
Selecting previously unselected package bootchart.
(Reading database ... 170788 files and directories currently installed.)
Unpacking bootchart (from .../bootchart_0.90.2-8ubuntu1_i386.deb) ...
Processing triggers for ureadahead ...
Setting up bootchart (0.90.2-8ubuntu1) ...
update-initramfs: Generating /boot/initrd.img-3.13.0-32-generic
ygu@ubuntu:~$ scp ygu@192.168.1.95:/opt/bootchartd/bootlog.tgz work/bootchart
bootlog.tgz                                   100%   29KB  29.3KB/s   00:00    
ygu@ubuntu:~$ cd work/bootchart
```

使用`pybootchartgui`处理`bootlog.tgz`：
```
ygu@ubuntu:~/work/bootchart$ ls -lh
total 32K
-rw-r--r-- 1 ygu ygu 30K Dec  1 10:28 bootlog.tgz
ygu@ubuntu:~/work/bootchart$ 
ygu@ubuntu:~/work/bootchart$ pybootchartgui bootlog.tgz 
parsing 'bootlog.tgz'
parsing 'header'
parsing 'proc_diskstats.log'
parsing 'proc_ps.log'
warning: no parent for pid '2' with ppid '0'
parsing 'proc_stat.log'
merged 0 logger processes
pruned 29 process, 0 exploders, 0 threads, and 0 runs
False
Traceback (most recent call last):
  File "/usr/bin/pybootchartgui", line 23, in <module>
    sys.exit(main())
  File "/usr/lib/pymodules/python2.7/pybootchartgui/main.py", line 137, in main
    render()
  File "/usr/lib/pymodules/python2.7/pybootchartgui/main.py", line 128, in render
    batch.render(writer, res, options, filename)
  File "/usr/lib/pymodules/python2.7/pybootchartgui/batch.py", line 41, in render
    draw.render(ctx, options, *res)
  File "/usr/lib/pymodules/python2.7/pybootchartgui/draw.py", line 256, in render
    curr_y = draw_header(ctx, headers, off_x, duration)
  File "/usr/lib/pymodules/python2.7/pybootchartgui/draw.py", line 340, in draw_header
    txt = headertitle + ': ' + mangle(headers.get(headerkey))
TypeError: cannot concatenate 'str' and 'NoneType' objects
ygu@ubuntu:~/work/bootchart$ 
```

如上，由于`Ubuntu`版本的`pybootchartgui`不能解析`busybox`上的`bootchart`数据，所以这里出现了错误，需要用另外一个版本[`bootchart2`](https://github.com/xrmx/bootchart.git)的工具来处理。

用`git`下载`bootchart2`后需要执行`make`后才能使用`pybootchartgui`：
```
ygu@ubuntu:~/work/bootchart$ git clone https://github.com/xrmx/bootchart.git
Cloning into 'bootchart'...
remote: Counting objects: 2560, done.
remote: Total 2560 (delta 0), reused 0 (delta 0), pack-reused 2560
Receiving objects: 100% (2560/2560), 1.79 MiB | 228 KiB/s, done.
Resolving deltas: 100% (1600/1600), done.
ygu@ubuntu:~/work/bootchart$ cd bootchart/
ygu@ubuntu:~/work/bootchart/bootchart$ make
cc -g -Wall -O0  -pthread \
		-DEARLY_PREFIX='""' \
		-DLIBDIR='"/lib"' \
		-DPKGLIBDIR='"/lib/bootchart"' \
		-DPROGRAM_PREFIX='""' \
		-DPROGRAM_SUFFIX='""' \
		-DVERSION='"0.14.8"' \
		 \
		-c collector/collector.c -o collector/collector.o
...
cc -g -Wall -O0  -pthread -Icollector -o bootchart-collector collector/collector.o collector/output.o collector/tasks.o collector/tasks-netlink.o collector/dump.o
sed -s -e "s:@LIBDIR@:/lib:g" -e "s:@PKGLIBDIR@:/lib/bootchart:" -e "s:@PROGRAM_PREFIX@::" -e "s:@PROGRAM_SUFFIX@::" -e "s:@EARLY_PREFIX@::" -e "s:@VER@:0.14.8:" bootchartd.in > bootchartd
...
sed -s -e "s:@LIBDIR@:/lib:g" -e "s:@PKGLIBDIR@:/lib/bootchart:" -e "s:@PROGRAM_PREFIX@::" -e "s:@PROGRAM_SUFFIX@::" -e "s:@EARLY_PREFIX@::" -e "s:@VER@:0.14.8:" pybootchartgui/main.py.in > pybootchartgui/main.py
ygu@ubuntu:~/work/bootchart/bootchart$ 
```

如果不编译，直接调用`pybootchartgui`会出现找不到`main`函数的错误：
```
ygu@ubuntu:~/work/bootchart$ ./bootchart/pybootchartgui.py bootlog.tgz 
Traceback (most recent call last):
  File "./bootchart/pybootchartgui.py", line 20, in <module>
    from pybootchartgui.main import main
ImportError: No module named main
ygu@ubuntu:~/work/bootchart$ 
```

编译完成后，再次调用`pybootchartgui.py`处理`bootlog.tgz`：
```
ygu@ubuntu:~/work/bootchart$ ./bootchart/pybootchartgui.py bootlog.tgz 
parsing 'bootlog.tgz'
parsing 'header'
parsing 'proc_diskstats.log'
parsing 'proc_ps.log'
parsing 'proc_stat.log'
merged 0 logger processes
pruned 29 process, 0 exploders, 0 threads, and 0 runs
bootchart written to 'bootchart.png'
ygu@ubuntu:~/work/bootchart$ ls -lh
total 96K
drwxr-xr-x 6 ygu ygu 4.0K Dec  1 10:45 bootchart
-rw-rw-r-- 1 ygu ygu  59K Dec  1 10:46 bootchart.png
-rw-r--r-- 1 ygu ygu  30K Dec  1 10:28 bootlog.tgz
ygu@ubuntu:~/work/bootchart$ 
```
将采集的数据转换为图片bootchart.png了，如下：
![`bootlog.tgz`的可视化图片](https://github.com/guyongqiangx/blog/blob/dev/bootchart/images/bootchart-busybox-1.21.1-initrd.png?raw=true)

由于这里整个`linux`系统启动的任务比较简单，所以从`bootchart.png`上可见的任务也较少，这里寄希望于`bootchart`的结果来进行启动时间优化还是有些难度。

###2. 监测系统或应用程序的运行情况
用于监测运行情况时需要给`bootchartd`指定参数，`start`参数开始监测，`stop`参数停止监测。

不过，系统启动后可以监测的手段较多，`bootchartd`工具并不是最优选择，非本文的介绍重点，暂略。

##四、`Bootchartd`源码分析

`busybox\init\bootchartd.c`：

+ `bootchartd_main`
```C
/* bootchart的main函数入口 */
int bootchartd_main(int argc UNUSED_PARAM, char **argv)
{
	unsigned sample_period_us;
	pid_t parent_pid, logger_pid;
	smallint cmd;
	int process_accounting;

	/* bootchart的命令类型 */
	enum {
		CMD_STOP = 0,	/* STOP命令，用于'bootchart stop' */
		CMD_START,		/* START命令， 用于'bootchart start [PROG ARGS]' */
		CMD_INIT,		/* INIT命令， 用于'bootchart init'，实际上并没有使用 */
		CMD_PID1, /* used to mark pid 1 case */ /* 作为linux启动的init进程时使用，init=/sbin/bootchartd */
	};

	INIT_G();

	/* 获取当前进程pid，init进程的pid为1 */
	parent_pid = getpid();
	if (argv[1]) { /* 检查bootchartd命令参数 */
		cmd = index_in_strings("stop\0""start\0""init\0", argv[1]);
		if (cmd < 0)
			bb_show_usage();
		if (cmd == CMD_STOP) { /* 检查是否是`bootchart stop'命令，如果是，则结束之前所有的'bootchartd'进程，停止监测 */
			pid_t *pidList = find_pid_by_name("bootchartd");
			while (*pidList != 0) {
				if (*pidList != parent_pid)
					kill(*pidList, SIGUSR1);
				pidList++;
			}
			return EXIT_SUCCESS;
		}
	} else { /* 不带参数时调用 */
		if (parent_pid != 1) /* 检查是否是init进程，如果不是init进程，则说明是在命令行调用不带参数的bootchartd，显示usage */
			bb_show_usage();
		cmd = CMD_PID1;
	}

	/* Here we are in START, INIT or CMD_PID1 state */

	/* 以下读取配置文件，实际上只读取了SAMPLE_PERIOD和PROCESS_ACCOUNTING选项 */
	/* 默认采样周期sample_period_us为200ms
	 * 如果process_accounting=1，用户程序可以让内核将该过程的统计资料情况存到文件里，默认如果process_accounting为0
	 */
	/* Read config file: */
	sample_period_us = 200 * 1000;
	process_accounting = 0;
	if (ENABLE_FEATURE_BOOTCHARTD_CONFIG_FILE) {
		char* token[2];
		parser_t *parser = config_open2("/etc/bootchartd.conf" + 5, fopen_for_read);
		if (!parser)
			parser = config_open2("/etc/bootchartd.conf", fopen_for_read);
		while (config_read(parser, token, 2, 0, "#=", PARSE_NORMAL & ~PARSE_COLLAPSE)) {
			if (strcmp(token[0], "SAMPLE_PERIOD") == 0 && token[1])
				sample_period_us = atof(token[1]) * 1000000;
			if (strcmp(token[0], "PROCESS_ACCOUNTING") == 0 && token[1]
			 && (strcmp(token[1], "on") == 0 || strcmp(token[1], "yes") == 0)
			) {
				process_accounting = 1;
			}
		}
		config_close(parser);
		if ((int)sample_period_us <= 0)
			sample_period_us = 1; /* prevent division by 0 */
	}

	/* 创建用于采样子进程 */
	/* Create logger child: */
	logger_pid = fork_or_rexec(argv);

	if (logger_pid == 0) { /* child */ /* 新创建的采样子进程 */
		char *tempdir;

		bb_signals(0
			+ (1 << SIGUSR1)
			+ (1 << SIGUSR2)
			+ (1 << SIGTERM)
			+ (1 << SIGQUIT)
			+ (1 << SIGINT)
			+ (1 << SIGHUP)
			, record_signo);

		/* 就绪后向父进程发送信号 */
		if (DO_SIGNAL_SYNC)
			/* Inform parent that we are ready */
			raise(SIGSTOP);

		/* If we are started by kernel, PATH might be unset.
		 * In order to find "tar", let's set some sane PATH:
		 */
		if (cmd == CMD_PID1 && !getenv("PATH"))
			putenv((char*)bb_PATH_root_path);

		/* 生成存放采样数据的临时目录 */
		tempdir = make_tempdir();
		/* 通过`/proc`文件系统进行采样 */
		do_logging(sample_period_us, process_accounting);
		/* 打包log信息文件，并清理中间生成的tempdir目录 */
		finalize(tempdir, cmd == CMD_START ? argv[2] : NULL, process_accounting);
		/* 退出子进程 */
		return EXIT_SUCCESS;
	}

	/* parent */

	USE_FOR_NOMMU(argv[0][0] &= 0x7f); /* undo fork_or_rexec() damage */

	/* 检查子进程发送的信号 */
	if (DO_SIGNAL_SYNC) {
		/* Wait for logger child to set handlers, then unpause it.
		 * Otherwise with short-lived PROG (e.g. "bootchartd start true")
		 * we might send SIGUSR1 before logger sets its handler.
		 */
		waitpid(logger_pid, NULL, WUNTRACED);
		kill(logger_pid, SIGCONT);
	}

	/* 如果当前bootchartd作为init进程，则需要启动真正的init进程 */
	if (cmd == CMD_PID1) {
		char *bootchart_init = getenv("bootchart_init");
		if (bootchart_init) /* 执行参数bootchart_init制定的进程 */
			execl(bootchart_init, bootchart_init, NULL);
		/* 执行/init作为真正的init进程，成功后不会再返回 */
		execl("/init", "init", NULL);
		/* 执行/sbin/init作为真正的进程，成功后不会再返回 */
		execl("/sbin/init", "init", NULL);
		/* 没有找到init进程或执行失败，显示错误信息 */
		bb_perror_msg_and_die("can't execute '%s'", "/sbin/init");
	}

	/* 在命令行运行START命令'bootchart start [PROG ARGS]'的情况，启动需要运行的进程 */
	if (cmd == CMD_START && argv[2]) { /* "start PROG ARGS" */
		pid_t pid = xvfork();
		if (pid == 0) { /* child */
			argv += 2;
			BB_EXECVP_or_die(argv);
		}
		/* parent */
		waitpid(pid, NULL, 0);
		kill(logger_pid, SIGUSR1);
	}

	return EXIT_SUCCESS;
}
```

+ `make_tempdir`
```C
/* 创建临时的内存文件系统目录 */
static char *make_tempdir(void)
{
	char template[] = "/tmp/bootchart.XXXXXX";
	char *tempdir = xstrdup(mkdtemp(template)); /* 使用模板/tmp/bootchart.XXXXXX创建一个临时目录，并返回目录名称字符串 */
	if (!tempdir) { /* 临时目录创建失败，尝试其他挂载点挂载作为临时目录 */
#ifdef __linux__
		/* /tmp is not writable (happens when we are used as init).
		 * Try to mount a tmpfs, them cd and lazily unmount it.
		 * Since we unmount it at once, we can mount it anywhere.
		 * Try a few locations which are likely ti exist.
		 */
		static const char dirs[] = "/mnt\0""/tmp\0""/boot\0""/proc\0";
		const char *try_dir = dirs;
		while (mount("none", try_dir, "tmpfs", MS_SILENT, "size=16m") != 0) {
			try_dir += strlen(try_dir) + 1;
			if (!try_dir[0])
				bb_perror_msg_and_die("can't %smount tmpfs", "");
		}
		//bb_error_msg("mounted tmpfs on %s", try_dir);
		xchdir(try_dir);
		if (umount2(try_dir, MNT_DETACH) != 0) {
			bb_perror_msg_and_die("can't %smount tmpfs", "un");
		}
#else
		bb_perror_msg_and_die("can't create temporary directory");
#endif
	} else {
		xchdir(tempdir);
	}
	return tempdir;
}
```

+ `do_logging`
```C
/* 采样/proc文件系统的数据 */
static void do_logging(unsigned sample_period_us, int process_accounting)
{
	FILE *proc_stat = xfopen("proc_stat.log", "w");
	FILE *proc_diskstats = xfopen("proc_diskstats.log", "w");
	//FILE *proc_netdev = xfopen("proc_netdev.log", "w");
	FILE *proc_ps = xfopen("proc_ps.log", "w");
	int look_for_login_process = (getppid() == 1);
	unsigned count = 60*1000*1000 / sample_period_us; /* ~1 minute */

	/* 如果process_accounting=1，生成kernel_pacct文件，不清楚为什么要通过acct("kernel_pacct")创建这个文件 */
	if (process_accounting) {
		close(xopen("kernel_pacct", O_WRONLY | O_CREAT | O_TRUNC));
		acct("kernel_pacct");
	}

	/* 采样 */
	while (--count && !bb_got_signal) {
		char *p;
		int len = open_read_close("/proc/uptime", G.jiffy_line, sizeof(G.jiffy_line)-2);
		if (len < 0)
			goto wait_more;
		/* /proc/uptime has format "NNNNNN.MM NNNNNNN.MM" */
		/* we convert it to "NNNNNNMM\n" (using first value) */
		G.jiffy_line[len] = '\0';
		p = strchr(G.jiffy_line, '.');
		if (!p)
			goto wait_more;
		while (isdigit(*++p))
			p[-1] = *p;
		p[-1] = '\n';
		p[0] = '\0';

		/* 采样/proc/stat，输出到proc_stat.log文件 */
		dump_file(proc_stat, "/proc/stat");
		/* 采样/proc/diskstats，输出到proc_diskstats.log文件 */
		dump_file(proc_diskstats, "/proc/diskstats");
		//dump_file(proc_netdev, "/proc/net/dev");
		/* 采样当前进程活动信息/proc/pid/stat，输出到proc_ps.log文件 */
		if (dump_procs(proc_ps, look_for_login_process)) {
			/* dump_procs saw a getty or {g,k,x}dm
			 * stop logging in 2 seconds:
			 */
			if (count > 2*1000*1000 / sample_period_us)
				count = 2*1000*1000 / sample_period_us;
		}
		fflush_all();
 wait_more:
		usleep(sample_period_us);
	}
}
```

+ `finalize`
```C
/* 将采样信息转移到/var/log/bootlogtgz文件并清理临时目录 */
static void finalize(char *tempdir, const char *prog, int process_accounting)
{
	//# Stop process accounting if configured
	//local pacct=
	//[ -e kernel_pacct ] && pacct=kernel_pacct

	FILE *header_fp = xfopen("header", "w");

	/* 清楚临时文件夹下的kernel_pacct文件
	 * kernel_pacct在统计开始时创建，统计结束时销毁
	 * kernel_pacct是用于向系统标记当前是一个统计进程吗？
	 */
	if (process_accounting)
		acct(NULL);

	/* 如果针对单个进程统计，则往header文件输出采样目标进程的名字 */
	if (prog)
		fprintf(header_fp, "profile.process = %s\n", prog);

	/* 往header文件输出bootchart版本信息 */
	fputs("version = "BC_VERSION_STR"\n", header_fp);
	/* 设置FEATURE_BOOTCHARTD_BLOATED_HEADER选项后，向header文件输出时间、系统版本、命令行参数等信息 */
	if (ENABLE_FEATURE_BOOTCHARTD_BLOATED_HEADER) {
		char *hostname;
		char *kcmdline;
		time_t t;
		struct tm tm_time;
		/* x2 for possible localized weekday/month names */
		char date_buf[sizeof("Mon Jun 21 05:29:03 CEST 2010") * 2];
		struct utsname unamebuf;

		hostname = safe_gethostname();
		time(&t);
		localtime_r(&t, &tm_time);
		strftime(date_buf, sizeof(date_buf), "%a %b %e %H:%M:%S %Z %Y", &tm_time);
		fprintf(header_fp, "title = Boot chart for %s (%s)\n", hostname, date_buf);
		if (ENABLE_FEATURE_CLEAN_UP)
			free(hostname);

		uname(&unamebuf); /* never fails */
		/* same as uname -srvm */
		fprintf(header_fp, "system.uname = %s %s %s %s\n",
				unamebuf.sysname,
				unamebuf.release,
				unamebuf.version,
				unamebuf.machine
		);

		//system.release = `cat /etc/DISTRO-release`
		//system.cpu = `grep '^model name' /proc/cpuinfo | head -1` ($cpucount)

		kcmdline = xmalloc_open_read_close("/proc/cmdline", NULL);
		/* kcmdline includes trailing "\n" */
		fprintf(header_fp, "system.kernel.options = %s", kcmdline);
		if (ENABLE_FEATURE_CLEAN_UP)
			free(kcmdline);
	}
	fclose(header_fp);

	/* 除kernel_pacct文件外，将临时目录里的所有*.log文件打包到/var/log/bootlog.tgz中 */
	/* Package log files */
	system(xasprintf("tar -zcf /var/log/bootlog.tgz header %s *.log", process_accounting ? "kernel_pacct" : ""));
	/* 清除临时文件目录 */
	/* Clean up (if we are not in detached tmpfs) */
	if (tempdir) {
		unlink("header");
		unlink("proc_stat.log");
		unlink("proc_diskstats.log");
		//unlink("proc_netdev.log");
		unlink("proc_ps.log");
		if (process_accounting)
			unlink("kernel_pacct");
		rmdir(tempdir);
	}

	/* shell-based bootchartd tries to run /usr/bin/bootchart if $AUTO_RENDER=yes:
	 * /usr/bin/bootchart -o "$AUTO_RENDER_DIR" -f $AUTO_RENDER_FORMAT "$BOOTLOG_DEST"
	 */
}
```

+ `dump_file`和`dump_procs`
```C
/* 将filename的内容写入fp文件 */
static void dump_file(FILE *fp, const char *filename)
{
	int fd = open(filename, O_RDONLY);
	if (fd >= 0) {
		fputs(G.jiffy_line, fp);
		fflush(fp);
		bb_copyfd_eof(fd, fileno(fp));
		close(fd);
		fputc('\n', fp);
	}
}

/* 获取/proc/pid/stat信息并写入fp文件 */
static int dump_procs(FILE *fp, int look_for_login_process)
{
	struct dirent *entry;
	DIR *dir = opendir("/proc");
	int found_login_process = 0;

	fputs(G.jiffy_line, fp);
	while ((entry = readdir(dir)) != NULL) {
		char name[sizeof("/proc/%u/cmdline") + sizeof(int)*3];
		int stat_fd;
		unsigned pid = bb_strtou(entry->d_name, NULL, 10);
		if (errno)
			continue;

		/* Android's version reads /proc/PID/cmdline and extracts
		 * non-truncated process name. Do we want to do that? */

		 /* 打开/proc/pid/stat文件 */
		sprintf(name, "/proc/%u/stat", pid);
		stat_fd = open(name, O_RDONLY);
		if (stat_fd >= 0) {
			char *p;
			char stat_line[4*1024];
			int rd = safe_read(stat_fd, stat_line, sizeof(stat_line)-2);

			close(stat_fd);
			if (rd < 0)
				continue;
			stat_line[rd] = '\0';
			p = strchrnul(stat_line, '\n');
			*p++ = '\n';
			*p = '\0';
			fputs(stat_line, fp);
			if (!look_for_login_process)
				continue;
			p = strchr(stat_line, '(');
			if (!p)
				continue;
			p++;
			strchrnul(p, ')')[0] = '\0';
			/* Is it gdm, kdm or a getty? */
			if (((p[0] == 'g' || p[0] == 'k' || p[0] == 'x') && p[1] == 'd' && p[2] == 'm')
			 || strstr(p, "getty")
			) {
				found_login_process = 1;
			}
		}
	}
	closedir(dir);
	fputc('\n', fp);
	return found_login_process;
}
```

##五、结论
`Bootchart`的原理和使用都比较简单，输出也比较直观，通过图片对整个启动系统有个总览，包括`CPU`在启动各时间段的负载和磁盘的吞吐情况，也呈现了启动过程中各进程的先后顺序和持续时间。但是在嵌入式系统中，`CPU`能力普遍不强，`Bootchartd`本身采样的开销也比较客观，甚至连日志输出的打包也会占用不少时间。另外，由于`bootchartd`启动上替代了`init`进程，因此在`init`进程启动之前的部分，`bootchartd`也无法反应。
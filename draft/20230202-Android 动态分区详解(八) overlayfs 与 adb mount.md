# 20230202-Android 动态分区详解(八) overlayfs 与 adb remount 操作

最开始学习 Android 动态分区源码的时候，比较代码发现 `system/core/fs_mgr` 目录下多了一个名为 `fs_mgr_overlayfs.cpp` 的文件，一直不知道什么时候会用到 overlayfs。

后来在 Android 官方文档中也提到 overlayfs 用于 adb remount 操作，但没有重视。

总打算等系统学习 overlayfs 以后再发一篇长文，不过一直在"打算"阶段。

直到 OTA 讨论群里越来越多小伙伴报了与 overlayfs 相关的各种问题后，是时候觉得有必要说明这个问题了。



## 1. 什么是 overlayfs?

Overlayfs是一种类似 aufs (advanced multi-layered unification filesystem) 的一种堆叠文件系统, 于 2014 年正式合入Linux-3.18主线内核, 目前其功能已经基本稳定(虽然还存在一些特性尚未实现)且被逐渐推广, 特别在容器技术中更是势头难挡。

Overlayfs 依赖并建立在其它的文件系统之上(例如 ext4fs 和 xfs 等等)，并不直接参与磁盘空间结构的划分，仅仅将原来底层文件系统中不同的目录进行“合并”，然后向用户呈现。因此对于用户来说，它所见到的overlay文件系统根目录下的内容就来自挂载时所指定的不同目录的“合集”。如图 1。

![img](images-20230202-Android 动态分区详解(八) overlayfs 与 adb mount/Center.jpeg)

图1. Overlayfs 基本结构

上图中 Lower Dir A / Lower Dir B 目录和 Upper Dir 目录为来自底层文件系统的不同目录，用户可以自行指定, 内部包含了用户想要合并的文件和目录。Merge Dir 目录为挂载点。

当文件系统挂载后，在 merge 目录下将会同时看到来自各 lower 和 upper 目录下的内容，并且用户也无法（无需）感知这些文件分别哪些来自 Lower Dir，哪些来自 Upper Dir，用户看见的只是一个普通的文件系统根目录而已（Lower Dir 可以有多个也可以只有一个）。

虽然 overlayfs 将不同的各层目录进行合并，但是 Upper Dir 和各 Lower Dir 这几个不同的目录并不完全等价，存在层次关系。首先当 Upper Dir 和 Lower Dir 两个目录存在同名文件时，Lower Dir 的文件将会被隐藏，用户只能看见来自 Upper Dir 的文件，然后各个 Lower Dir 也存在相同的层次关系，较上层屏蔽叫下层的同名文件。

除此之外，如果存在同名的目录，那就继续合并(Lower Dir 和 Upper Dir 合并到挂载点目录其实就是合并一个典型的例子）。

各层目录中的 Upper Dir 是可读写的目录，当用户通过 Merge Dir 向其中一个来自 Upper Dir 的文件写入数据时，那数据将直接写入Upper Dir下原来的文件中，删除文件也是同理；而各 Lower Dir 则是只读的，在 overlayfs 挂载后无论如何操作 merge 目录中对应来自 Lower Dir 的文件或目录，Lower Dir 中的内容均不会发生任何的改变（理论设计如此，但实际在一些极端场景存在偏差，后面我会详细介绍）。

既然 Lower Dir 是只读的，那当用户想要往来自 lower 层的文件添加或修改内容时，overlayfs 首先会的拷贝一份Lower Dir 中的文件副本到 Upper Dir 中，后续的写入和修改操作将会在 Upper Dir 下的 copy-up 的副本文件中进行，Lower Dir 原文件被隐藏。

以上就是 overlayfs 最基本的特性，简单的总结为以下3点：

1. 上下层同名目录合并；
2. 上下层同名文件覆盖；
3. Lower Dir文件写时拷贝。

这三点对用户都是不感知的。

> 以上关于 overlayfs 的介绍来自：[《深入理解overlayfs（一）：初识》](https://blog.csdn.net/luckyapple1028/article/details/77916194)，文章链接: https://blog.csdn.net/luckyapple1028/article/details/77916194。十分感谢作者 [luckyapple1028](https://blog.csdn.net/luckyapple1028) 的详细介~



综合来说，overlayfs 是一种堆叠的文件系统，可以用一个目录的内容叠加到另外一个目录之上。特别适合以下场景：

1. 多人对同一个目录进行独立的访问，但又不希望修改公共目录内容的情况，此时只需要将个人的目录叠加到公共的目录上即可。所有未改动的内容来自公共目录，所有改动过的数据都保存在个人目录中。

   比如，系统中的多个 docker 就属于这种情形，每个 docker 看起来都是一个独立的环境，通过使用 overlayfs，多人共享公共的数据，可以极大的减少对存储空间的占用。

2. 对只读文件系统进行修改。

   比如 Android 调试时，临时改动 system 分区验证问题，只需要在只读的 /system 目录上叠加一个可读写的 overlayfs，所有 system 改动都保存到 overlayfs 的空间中。

## 2. Linux 驱动中的 overlayfs

Linux 下 overlayfs:

- 代码位于 `fs/overlayfs` 目录，
- 文档位于 `Documentation/filesystems/overlayfs.txt `

Linux 编译 overlayfs 的开关:

![image-20230203113102498](images-20230202-Android 动态分区详解(八) overlayfs 与 adb mount/image-20230203113102498.png)

在 linux 下面可以通过 `/proc/filesystems` 查看系统支持的文件系统:

```bash
console:/ # cat /proc/filesystems                                              
nodev   sysfs
nodev   tmpfs
nodev   bdev
nodev   proc
nodev   cgroup
nodev   cgroup2
nodev   devtmpfs
nodev   configfs
nodev   debugfs
nodev   tracefs
nodev   sockfs
nodev   bpf
nodev   pipefs
nodev   ramfs
nodev   devpts
        ext3
        ext2
        ext4
        cramfs
        squashfs
        vfat
        msdos
        iso9660
nodev   jffs2
        fuseblk
nodev   fuse
nodev   fusectl
nodev   overlay
nodev   incremental-fs
        udf
        f2fs
nodev   mqueue
nodev   selinuxfs
nodev   binder
nodev   ubifs
nodev   pstore
nodev   functionfs
console:/ #
```

上面是在一个 Android 盒子上通过命令 `cat /proc/filesystems` 查看支持的文件系统情况。

第一列显示是否已经有设备挂载了该文件系统，"nodev" 表示还没有设备挂载。

第二列显示文件系统的名称。

这里可以看到，这个设备支持 overlay，但是没有设备挂载。



## 3. Android 系统的 overlayfs

Android 的系统分区，包括 system 和 vendor 在运行时都是以只读的方式挂载的，但在开发中常常又需要修改 system 或 vendor 目录。

因此，Android 在动态分区版本中引入了 overlayfs，以下是官方文档对这个改动的介绍:



![image-20230202225853684](images-20230202-Android 动态分区详解(八) overlayfs 与 adb mount/image-20230202225853684.png)

图 2. Android 官方介绍 overlayfs 用于 adb remount 操作

上面这个截图来自 Android 官方文档[《实现动态分区》](https://source.android.google.cn/docs/core/ota/dynamic_partitions/implement?hl=zh-cn#adb-remount)。



Android 系统的 overlayfs 基于 linux 底层驱动进行了扩展，其实现代码位于：

```bash
system/core/fs_mgr/fs_mgr_overlayfs.cpp
```



当 adb 发送 remount 命令时，系统会调用命令行工具 `/system/bin/remount` 来执行具体的 remount 操作。这个工具由文件 `system/core/fs_mgr/fs_mgr_remount.cpp` 编译而成，在执行具体挂载操作的 `do_remount` 函数中创建 overlayfs 文件系统分区并挂在到 `/mnt/scratch` 目录下。



特别注意的是 remount 只有在以下条件下才能操作:

1. userdebug build 或者 eng build 版本( user build 版本不行)
2. dmverity 处于 disable 状态



更多关于 Android 下 overlayfs 的信息请参考 `fs_mgr`目录下的 overlayfs 自述文，路径位于:

```
system/core/fs_mgr/README.overlayfs.md
```

如果一开始读不懂这个文档，建议多读几遍。



在 Android Q(10) 及后续版本上，

- 对于支持 A/B 系统的设备，挂载点位于: `/mnt/scratch/overlay`
- 对于非 A/B 系统设备，挂载点位于: `/cache/overlay` 



从代码中可见，overlayfs 生成的分区会写入 super 分区头部的 metadata 区域中。该区域存储的是 super 分区的分区表，这也就意味着所创建的 overlayfs 是持久的，系统重启以后仍然存在，直到将 overlayfs 文件系统所在分区从 metadata 中清除。



## 4. overlayfs 相关操作

这里不再详细分析 Android overlayfs 的源码，主要提供一些操作 overlayfs 操作演示说明。

### 1. Linux 上 overlayfs 的演示操作

Linux 下将多个目录挂载为 overlayfs 的命令为:

```bash
mount -t overlay overlay -o lowerdir=lowerdir,upperdir=upperdir,workdir=workdir mountpoint
```

如果 lowerdir 有多个，每个之间使用冒号(:)分隔。

对于 overlay 相关的参数，在 mount 的 man 手册中是这么说的:

![image-20230203163404618](images-20230202-Android 动态分区详解(八) overlayfs 与 adb mount/image-20230203163404618.png)

对于这里的 lowerdir, upperdir, workdir 分别表示：

```bash
lowerdir=directory
       Any filesystem, does not need to be on a writable filesystem.

upperdir=directory
       The upperdir is normally on a writable filesystem.

workdir=directory
       The workdir needs to be an empty directory on the same filesystem as upperdir.
```

简而言之，

- lowerdir 是底层被覆盖的基本目录，挂载后这个目录的内容会被 upper 目录的内容覆盖
- upperdir 是上层目录，对堆叠以后目录的写入会保存在 upper 目录中
- workdir 是用于各种处理工作的目录，对用户透明，用户也不需要关心
- mountpoint 是最终 lowerdir 和 upperdir 合并后的挂载点



在 [《深入理解overlayfs（二）：使用与原理分析》](https://blog.csdn.net/luckyapple1028/article/details/78075358) 提供了一个非常好的例子，转载如下:

```bash
$ mkdir -p lower{1,2}/dir upper/dir worker merge
$ touch lower1/foo1 lower2/foo2 upper/foo3
$ touch lower1/dir/{aa,bb} lower2/dir/aa upper/dir/bb
$ echo "from lower1" > lower1/dir/aa 
$ echo "from lower2" > lower2/dir/aa 
$ echo "from lower1" > lower1/dir/bb
$ echo "from upper" > upper/dir/bb 
$ sudo mount -t overlay overlay -o lowerdir=lower1:lower2,upperdir=upper,workdir=worker merge
$ tree merge
merge
├── dir
│   ├── aa
│   └── bb
├── foo1
├── foo2
└── foo3

1 directory, 5 files
$ cat merge/dir/aa 
from lower1
$ cat merge/dir/bb 
from upper
```

下面是将实验中将目录 lower1, lower2 和 upper 进行叠加操作到 merge 目录的示意图。

![img](images-20230202-Android 动态分区详解(八) overlayfs 与 adb mount/Center.jpeg)

图1 overlayfs基本挂载示例



更多实验，建议转到 [《深入理解overlayfs（二）：使用与原理分析》](https://blog.csdn.net/luckyapple1028/article/details/78075358) 进行详细学习。

也十分感谢博主 luckyapple1028 设计的操作示例。



### 2. Android 上的 overlayfs 演示操作

在 Android 上执行 remount 操作时，系统自动为 system, vendor 等只读分区创建 overlayfs 文件系统的挂载点。

按照 overlayfs 自述文档的说法，可以使用以下指令顺序执行 remount:

```bash
$ adb root
$ adb disable-verity
$ adb reboot
$ adb wait-for-device
$ adb root
$ adb remount
```

然后执行以下步骤后，系统自动为所有分区创建 overlayfs 挂载:

```bash
$ adb shell stop
$ adb sync
$ adb shell start
$ adb reboot
```





可以在串口命令行执行 `mount | grep overlay` 查看 overlayfs 的挂载情况，如下:

```bash
console:/ # mount | grep overlay
overlay on /system type overlay (ro,seclabel,noatime,lowerdir=/system,upperdir=/mnt/scratch/overlay/system/upper,workdir=/mnt/scratch/overlay/system/work,override_creds=off)
overlay on /vendor type overlay (ro,seclabel,noatime,lowerdir=/vendor,upperdir=/mnt/scratch/overlay/vendor/upper,workdir=/mnt/scratch/overlay/vendor/work,override_creds=off)
```



## 5. Android 中 overlayfs 相关的问题





参考文章:

- [《深入理解overlayfs（一）：初识》](https://blog.csdn.net/luckyapple1028/article/details/77916194)
  - https://blog.csdn.net/luckyapple1028/article/details/77916194

- [《深入理解overlayfs（二）：使用与原理分析》](https://blog.csdn.net/luckyapple1028/article/details/78075358)
  - https://blog.csdn.net/luckyapple1028/article/details/78075358
- [《Android Q开关AVB remount分区，导致OTA升级super分区resize fail》](https://blog.csdn.net/Donald_Zhuang/article/details/108090117)
  - https://blog.csdn.net/Donald_Zhuang/article/details/108090117
- [《adb remount之后，OTA 升级失败的问题》](https://blog.csdn.net/xuyewen288/article/details/127637034)
  - https://blog.csdn.net/xuyewen288/article/details/127637034

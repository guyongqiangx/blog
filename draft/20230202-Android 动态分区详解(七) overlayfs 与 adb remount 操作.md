# 20230202-Android 动态分区详解(七) overlayfs 与 adb remount 操作

![android_dynamic_partitions_7_title](images-20230202-Android 动态分区详解(七)/android_dynamic_partitions_7_title.png)

## 0. 导读

最开始学习 Android 动态分区源码的时候，比较代码发现 `system/core/fs_mgr` 目录下多了一个名为 `fs_mgr_overlayfs.cpp` 的文件，一直不知道什么时候会用到 overlayfs。

后来在 Android 官方文档中也提到 overlayfs 用于 adb remount 操作，但没有重视。

总打算等系统学习 overlayfs 以后再发一篇长文，不过一直在"打算"阶段。

最近突发奇想，在 OTA 讨论群里搜索一下 remount 相关的聊天记录，这个问题引起的话题实在是太多了，所以是时候觉得有必要详细说明 overlay 和 remount 这个问题了。



本文从 overlay 文件系统的基本原理出发，简单介绍了 Linux 和 Android 系统中的 overlay 文件系统及相关内容，重点在 Android 中的 remount 操作会从 super 设备或 data 分区分配空间用于 overlay 文件系统。

所以文章内容很长，如果只对结论感兴趣，请直接跳转到第 6 节，总结查看本文提到的一些操作和结论。

最后也提供了意思思考题，如果你能请清晰的回答这些问题，我相信你已经对 overlay 或 remount 已经有了比较清晰的认识。



本文作为动态分区系列的第七篇，实际上在动态分区以后的虚拟 A/B 上也适用。

动态分区系列前六篇包括：

- [《Android 动态分区详解(一) 5 张图让你搞懂动态分区原理》](https://blog.csdn.net/guyongqiangx/article/details/123899602)

- [《Android 动态分区详解(二) 核心模块和相关工具介绍》](https://blog.csdn.net/guyongqiangx/article/details/123931356)
- [《Android 动态分区详解(三) 动态分区配置及super.img的生成》](https://blog.csdn.net/guyongqiangx/article/details/124052932)
- [《Android 动态分区详解(四) OTA 中对动态分区的处理》](https://blog.csdn.net/guyongqiangx/article/details/124224206)
- [《Android 动态分区详解(五) 为什么没有生成 super.img?》](https://blog.csdn.net/guyongqiangx/article/details/128005251)
- [《Android 动态分区详解(六) 动态分区的底层机制》](https://blog.csdn.net/guyongqiangx/article/details/128305482)



> 如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。

## 1. 什么是 overlayfs?

Overlayfs是一种类似 aufs (advanced multi-layered unification filesystem) 的一种堆叠文件系统, 于 2014 年正式合入Linux-3.18主线内核, 目前其功能已经基本稳定(虽然还存在一些特性尚未实现)且被逐渐推广, 特别在容器技术中更是势头难挡。

Overlayfs 依赖并建立在其它的文件系统之上(例如 ext4fs 和 xfs 等等)，并不直接参与磁盘空间结构的划分，仅仅将原来底层文件系统中不同的目录进行“合并”，然后向用户呈现。因此对于用户来说，它所见到的overlay文件系统根目录下的内容就来自挂载时所指定的不同目录的“合集”。如图 1。

![img](images-20230202-Android 动态分区详解(七)/overlayfs-example.png)

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

> 以上关于 overlayfs 的介绍来自：[《深入理解overlayfs（一）：初识》](https://blog.csdn.net/luckyapple1028/article/details/77916194)，链接: https://blog.csdn.net/luckyapple1028/article/details/77916194。



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

![image-20230203113102498](images-20230202-Android 动态分区详解(七)/linux-overlayfs-switch.png)

图 2. Linux 中 overlayfs 的编译开关



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



![image-20230202225853684](images-20230202-Android 动态分区详解(七)/android-adb-remount.png)

图 3. Android 官方介绍 overlayfs 用于 adb remount 操作



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

![image-20230203163404618](images-20230202-Android 动态分区详解(七)/overlayfs-mount-options.png)

图 4. mount 命令中关于 overlay 文件系统的选项参数



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

![img](images-20230202-Android 动态分区详解(七)/overlayfs-example.png)

图5. overlayfs基本挂载示例



更多实验，建议转到 [《深入理解overlayfs（二）：使用与原理分析》](https://blog.csdn.net/luckyapple1028/article/details/78075358) 进行详细学习。

也再次感谢博主 luckyapple1028 设计的操作示例。



### 2. Android 上的 overlayfs 演示操作

在 Android 上执行 remount 操作时，系统自动为 system, vendor 等只读分区创建 overlayfs 文件系统的挂载点。



#### 关闭 dm-verity, 执行 remount

按照 overlayfs 自述文档的说法，可以使用以下指令顺序执行 remount 操作:

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

以下步骤往指定分区推送内容，只创建相应分区的 overlayfs:

```bash
$ adb push <source> <destination>
$ adb reboot
```



文档中也提到，对于上面的指令

```bash
$ adb disable-verity
$ adb reboot
```

和

```bash
$ adb remount
```

都可以用一条指令来替代:

```bash
$ adb remount -R
```



上面一大串指令看起来很繁琐，实际操作中可以简单使用以下指令进行 remount:

```bash
$ adb root
$ adb disable-verity
$ adb remount
$ adb reboot
```



在 disable-verity 以后可以通过命令 `getprop | grep verity` 查看当前的 verity 状态:

```bash
$ adb shell getprop | grep verity
[ro.boot.veritymode]: [disabled]
```



可以通过执行 `mount | grep overlay` 查看 overlayfs 的挂载情况，以下是在一个 Android R 的设备上执行 remount 以后得到的输出:

```bash
$ adb shell mount | grep overlay
overlay on /system type overlay (ro,seclabel,noatime,lowerdir=/system,upperdir=/mnt/scratch/overlay/system/upper,workdir=/mnt/scratch/overlay/system/work,override_creds=off)
overlay on /vendor type overlay (ro,seclabel,noatime,lowerdir=/vendor,upperdir=/mnt/scratch/overlay/vendor/upper,workdir=/mnt/scratch/overlay/vendor/work,override_creds=off)
...
```

从上面的输出中可以看到，此时 `/system` 和 `/vendor` 都已经通过 overlay 的方式重新挂载了，其修改的内容会存放在 upperdir 目录(`/mnt/scratch/overlay`)中。



#### 打开 dm-verity, 执行 unmount

在 remount 以后，可以通过 `adb enable-verity` 来卸载 overlay 的文件系统，并重新打开 verity 状态。

```bash
$ adb root
$ adb enable-verity
$ adb reboot
```



以下是在关闭 verity 的状态下重新打开 verity 并执行各种检查的操作记录:

```bash
$ adb root
restarting adbd as root

# 当前 dm-verity 处于 disable 状态
$ adb shell getprop | grep verity
[ro.boot.veritymode]: [disabled]

# 重新打开 dm-verity
$ adb enable-verity
disabling overlayfs
Successfully enabled verity
Now reboot your device for settings to take effect

# 重启系统让 dm-verity 打开生效
$ adb reboot

$ adb root
restarting adbd as root

# 当前 dm-verity 处于 enforcing 状态
$ adb shell getprop | grep verity
[ro.boot.veritymode]: [enforcing]

# 检查已经挂在的 overlay 文件系统，没有输出说明已经没有挂载任何 overlay 文件系统了
$ adb shell mount | grep overlay
```



#### overlay 文件系统的空间

鉴于篇幅的关系，不就不再长篇累牍分析 overlay 文件系统的空间来源了。

- 在 Android Q(10) 动态分区上，当打开 verity 时，默认会从 super 分配空间用于挂载 overlay 文件系统，相应 scratch 分区的信息写入到 super 设备头部 metadata 的分区表中，可以使用 lpdump 工具查看。

- 在 Android R(11) 及后续版本打开了 Virtual A/B 以后，默认会先从 data 分配空间用于挂载 overlay 文件系统，scratch 分区的 metadata 数据会写入到文件:

  ```bash
  /metadata/gsi/remount/lp_metadata
  ```

## 5. Android 中 overlayfs 相关的问题

偶尔会有小伙伴会在群里问一些 OTA 升级中空间异常的问题，这类问题除了规划时空间确实不够之外，很可能因为启用了 overlay 文件系统在 super 或 data 分区上分配数据，导致升级时空间不够了。

这里我总结一下网上关于这类问题的文章。

### 1. MTK 平台, adb remount之后，OTA 升级失败

```bash
 473   473 I update_engine: [1101/114216.247577:INFO:dynamic_partition_control_android.cc(197)] Loaded metadata from slot A in /dev/block/platform/bootdevice/by-name/super
 473   473 I update_engine: [1101/114216.247946:INFO:boot_control_android.cc(312)] Removing group main_b
 473   473 I update_engine: [1101/114216.248105:INFO:boot_control_android.cc(343)] Added group main_b with size 1844969472
 473   473 I /system/bin/update_engine: [liblp]Partition vendor_b will resize from 0 bytes to 327540736 bytes
 473   473 I update_engine: [1101/114216.248254:INFO:boot_control_android.cc(360)] Added partition vendor_b to group main_b with size 327540736
 473   473 I /system/bin/update_engine: [liblp]Partition product_b will resize from 0 bytes to 252170240 bytes
 473   473 I update_engine: [1101/114216.248382:INFO:boot_control_android.cc(360)] Added partition product_b to group main_b with size 252170240
 473   473 E /system/bin/update_engine: [liblp]Not enough free space to expand partition: system_b
 473   473 E update_engine: [1101/114216.248480:ERROR:boot_control_android.cc(356)] Cannot resize partition system_b to size 1154273280. Not enough space?
 473   473 E update_engine: [1101/114216.248544:ERROR:delta_performer.cc(998)] Unable to initialize partition metadata for slot B
 473   473 E update_engine: [1101/114216.248630:ERROR:download_action.cc(336)] Error ErrorCode::kInstallDeviceOpenError (7) in DeltaPerformer's Write method when processing the received payload -- Terminating processing
 473   473 I update_engine: [1101/114216.249175:INFO:multi_range_http_fetcher.cc(177)] Received transfer terminated.
 473   473 I update_engine: [1101/114216.249358:INFO:multi_range_http_fetcher.cc(129)] TransferEnded w/ code 200
 473   473 I update_engine: [1101/114216.249451:INFO:multi_range_http_fetcher.cc(131)] Terminating.
1236  1524 V FespxProcessor: onMultibfDataReceived: 8 index 0 size 4096 mPreUploadRollbackDataSize 131072
 473   473 I update_engine: [1101/114216.253259:INFO:action_processor.cc(116)] ActionProcessor: finished DownloadAction with code ErrorCode::kInstallDeviceOpenError
 473   473 I update_engine: [1101/114216.253452:INFO:action_processor.cc(121)] ActionProcessor: Aborting processing due to failure.
 473   473 I update_engine: [1101/114216.253521:INFO:update_attempter_android.cc(454)] Processing Done.
 473   473 I update_engine: [1101/114216.253568:INFO:dynamic_partition_control_android.cc(151)] Destroying [] from device mapper
3254  3272 D clifeOTA: onStatusUpdate  status: 0
 473   473 I update_engine: [1101/114216.254265:INFO:metrics_repo
```

> 来源: [《adb remount之后，OTA 升级失败的问题》](https://blog.csdn.net/xuyewen288/article/details/127637034)
>
> 链接: https://blog.csdn.net/xuyewen288/article/details/127637034

### 2. Android Q 上 remount 分区，导致 OTA 升级 super 分区 resize fail

```bash
[liblp]Partition vendor will resize from 0 bytes to 217198592 bytes
[liblp]Not enough free space to expand partition: system
Failed to resize partition system to size 1719984128.
script aborted: assert failed: update_dynamic_partitions(package_extract_file("dynamic_partitions_op_list"))
E:Error in @/cache/recovery/block.map (status 7)
```

> 来源: [《Android Q开关AVB remount分区，导致OTA升级super分区resize fail》](https://blog.csdn.net/Donald_Zhuang/article/details/108090117)
>
> 链接: https://blog.csdn.net/Donald_Zhuang/article/details/108090117

## 6. 总结

### 1. 综述

overlayfs 是一种堆叠文件系统，由 upperdir 和至少一个 lowerdir 构成，看起来就好像是 upperdir 叠加在 lowerdir 之上，所有对堆叠目录的修改都会保存到 upperdir 中，而 lowerdir 保持不变。

适合以下场景:

1. 多人对同一个目录进行独立的访问，但又不希望修改公共目录内容的情况，此时只需要将个人的目录叠加到公共的目录上即可。所有未改动的内容来自公共目录，所有改动过的数据都保存在个人目录中。

2. 对只读文件系统进行修改。Android 启动后，默认 system 分区以只读方式挂载，调试时需要临时改动 system 分区验证问题，只需要在只读的 /system 目录上叠加一个可读写的 overlayfs，所有 system 改动都保存到 overlayfs 的空间中。



### 2. Linux 下的挂载命令

Linux 下将多个目录挂载为 overlayfs 的命令为:

```bash
mount -t overlay overlay -o lowerdir=lowerdir,upperdir=upperdir,workdir=workdir mountpoint
```

如果 lowerdir 有多个，每个之间使用冒号(:)分隔。



### 3. Android overlayfs 的挂载和卸载

Android 下可以通过以下指令执行 remout，达到关闭 verity 并挂载 overlay 文件系统，使能对 system, vendor 等目录修改的目的:

```shell
$ adb root
$ adb disable-verity
$ adb remount
$ adb reboot
```



可以通过以下操作打开 verity，关闭 remount，并卸载 overlay 文件系统，对 system, vendor 等目录进行还原:

```bash
$ adb root
$ adb enable-verity
$ adb reboot
```



### 4. Android overlayfs 的挂载点

在 Android Q(10) 及后续版本上，

- 对于支持 A/B 系统的设备，挂载点位于: `/mnt/scratch/overlay`
- 对于非 A/B 系统设备，挂载点位于: `/cache/overlay` 



### 5. Android overlayfs 空间的来源

在 Android Q(10) 动态分区上，当打开 verity 时，默认会从 super 分配空间用于挂载 overlay 文件系统，相应的分区写入到 super 设备头部 metadata 的分区表中，可以使用 lpdump 工具查看。



在 Android R(11) 及后续版本打开了 Virtual A/B 以后，默认会先从 data 分配空间用于挂载 overlay 文件系统，分区的 metadata 数据会写入到文件:

```
/metadata/gsi/remount/lp_metadata
```



### 6. 思考题

在本文快要结束的时候，还是应该留下一些思考题：

1. Android 在执行 remount 挂载 overlay 文件系统，以及关闭 overlay 文件系统时执行了一大堆 adb 指令，你知道每一个指令都背后都做了什么操作吗？

   包括:

   - 关闭 verity，执行 remount

   ```bash
   $ adb root
   $ adb disable-verity
   $ adb reboot
   $ adb wait-for-device
   $ adb root
   $ adb remount
   ```

2. - 下面这一组操作我也没搞懂到底干了嘛？感觉不做也可以，知道的麻烦的科普下。

3. ```bash
   $ adb shell stop
   $ adb sync
   $ adb shell start
   ```

4. - 打开 verity

   ```bash
   $ adb root
   $ adb enable-verity
   $ adb reboot
   ```

2. 在上面的这些操作中，为什么有时候需要执行 `adb reboot` 来重启设备，不重启不行吗？
3. 你知道如何查看一个系统的 verity，以及 overlay 文件系统的挂载情况吗?(包括从哪里分配空间，挂载到哪里，以及挂载时使用了哪些参数)



## 7. 参考阅读

本文除了 Android 自带的 overlayfs 自述文件外，还参考了以下文章，特别感谢

- [《深入理解overlayfs（一）：初识》](https://blog.csdn.net/luckyapple1028/article/details/77916194)
  - https://blog.csdn.net/luckyapple1028/article/details/77916194

- [《深入理解overlayfs（二）：使用与原理分析》](https://blog.csdn.net/luckyapple1028/article/details/78075358)
  - https://blog.csdn.net/luckyapple1028/article/details/78075358
- [《Android Q开关AVB remount分区，导致OTA升级super分区resize fail》](https://blog.csdn.net/Donald_Zhuang/article/details/108090117)
  - https://blog.csdn.net/Donald_Zhuang/article/details/108090117
- [《adb remount之后，OTA 升级失败的问题》](https://blog.csdn.net/xuyewen288/article/details/127637034)
  - https://blog.csdn.net/xuyewen288/article/details/127637034



尤其深入理解 overlayfs 的文章，写得非常好，干货满满。



如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。

如果您从事 Android OTA 升级相关工作或对 OTA 升级感兴趣，欢迎到 Android OTA 交流群一起讨论。

如果大家有任何疑问，又或者发现描述有错误的地方，也欢迎加我微信讨论，请在公众号(“洛奇看世界”)后台回复 “wx” 获取二维码。

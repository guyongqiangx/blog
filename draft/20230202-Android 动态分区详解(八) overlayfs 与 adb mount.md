# 20230202-Android 动态分区详解(八) overlayfs 与 adb remount 操作

最开始学习 Android 动态分区源码的时候，比较代码就发现 `system/core/fs_mgr` 目录下多了一个名为 `fs_mgr_overlayfs.cpp` 的文件，一直不知道到底有什么用。

Android 在官方文档中也提到过 overlayfs 用于 adb remount 操作，但没有重视。

总打算等系统学习 overlayfs 以后再发一篇长文，不过一直在"打算"阶段。

直到 OTA 讨论群里越来越多小伙伴报了与 overlayfs 相关的各种问题后，是时候觉得有必要说明这个问题了。



## 1. 什么是 overlayfs?

Overlayfs是一种类似 aufs (advanced multi-layered unification filesystem) 的一种堆叠文件系统, 于2014年正式合入Linux-3.18主线内核, 目前其功能已经基本稳定(虽然还存在一些特性尚未实现)且被逐渐推广, 特别在容器技术中更是势头难挡。

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



## 2. Android 系统的 overlayfs

从上一节对 overlayfs 的介绍可见，基于 overlayfs 的文件系统可以修改某个目录的内容，而不会改变原来的文件系统，因为修改的内容保存到另外一个目录中了。

Android 的系统分区，包括 system 和 vendor 在运行时都是以只读的方式挂载的，但在开发中常常又需要修改 system 或 vendor 目录。

因此，Android 在动态分区版本中引入了 overlayfs，以下是官方文档对这个改动的介绍:



![image-20230202225853684](images-20230202-Android 动态分区详解(八) overlayfs 与 adb mount/image-20230202225853684.png)

图 2. Android 官方介绍 overlayfs 用于 adb remount 操作



> - 参考: [《实现动态分区》](https://source.android.google.cn/docs/core/ota/dynamic_partitions/implement?hl=zh-cn#adb-remount)
>
> - 链接: https://source.android.google.cn/docs/core/ota/dynamic_partitions/implement?hl=zh-cn#adb-remount



Android 系统的 overlayfs 基于 linux 底层驱动进行了扩展，其实现代码位于：

```bash
system/core/fs_mgr/fs_mgr_overlayfs.cpp
```



当 adb 发送 remount 命令时，系统会调用命令行工具 `/system/bin/remount` 来执行具体的 remount 操作。这个工具由文件 `system/core/fs_mgr/fs_mgr_remount.cpp` 编译而成，在执行具体挂载操作的 `do_remount` 函数中创建 overlayfs 文件系统分区并挂在到 `/mnt/scratch` 目录下。



特别注意的是 remount 只有在以下条件下才能操作:

1. userdebug build 或者 eng build 版本( user build 版本不行)
2. dmverity 处于 disable 状态



更多关于 Android 下 overlayfs 的信息请参考 `fs_mgr`目录下的 overlayfs 说明文档，路径位于:

```
system/core/fs_mgr/README.overlayfs.md
```

如果一开始读不懂这个文档，建议多读几遍。



在 Android Q(10) 及后续版本上，

- 对于支持 A/B 系统的设备，挂载点位于: `/mnt/scratch/overlay`
- 对于非 A/B 系统设备，挂载点位于: `/cache/overlay` 



从代码中可见，overlayfs 生成的分区会写入 super 分区头部的 metadata 区域中。该区域存储的是 super 分区的分区表，这也就意味着所创建的 overlayfs 是持久的，系统重启以后仍然存在，直到将 overlayfs 文件系统所在分区从 metadata 中清除。



## 3. overlayfs 空间的打开与关闭






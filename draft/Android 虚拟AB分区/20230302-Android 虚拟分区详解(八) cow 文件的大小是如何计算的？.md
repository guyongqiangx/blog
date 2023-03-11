# 20230302-Android 虚拟 A/B 详解(八) cow 文件的大小是如何计算的？

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 原文链接：



> Android 虚拟 A/B 分区[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列，更新中，文章列表：
>
> - [Android 虚拟 A/B 详解(一) 参考资料推荐](https://blog.csdn.net/guyongqiangx/article/details/128071692)
> - [Android 虚拟 A/B 详解(二) 虚拟分区布局](https://blog.csdn.net/guyongqiangx/article/details/128167054)
> - [Android 虚拟 A/B 详解(三) 分区状态变化](https://blog.csdn.net/guyongqiangx/article/details/128517578)
> - [Android 虚拟 A/B 详解(四) 编译开关](https://blog.csdn.net/guyongqiangx/article/details/128567582)
> - [Android 虚拟 A/B 详解(五) BootControl 接口的变化](https://blog.csdn.net/guyongqiangx/article/details/128824984)
> - [Android 虚拟 A/B 详解(六) 升级中的状态数据保存在哪里？](https://blog.csdn.net/guyongqiangx/article/details/129094203)
> - [Android 虚拟 A/B 详解(七) 升级中用到了哪些标识文件？](https://guyongqiangx.blog.csdn.net/article/details/129098176)
>
> 对 linux 快照(snapshot) 的了解可以增加对虚拟 A/B 分区的理解：
>
> - [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
> - [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。



在虚拟 A/B 升级的过程中，假设当前运行在 A 槽位，即将升级 B 槽位的分区，因此系统需要为 B 槽位的分区(比如 system_b) 创建相应的 snapshot (快照) 设备，而创建快照时需要提供快照的 cow 文件，而这个文件显然是升级准备阶段创建的。



问题来了，cow 是提前分配一个固定大小的文件吗？答案是否定的，那系统是如何计算快照设备大小的呢？





你现在能够解释下面这段 log 了吗？



```
I update_engine: [liblp]Partition system_b will resize from 1263054848 bytes to 1263079424 bytes
I update_engine:  dap_metadata.cow_version(): 0 writer.GetCowVersion(): 2
I update_engine: Remaining free space for COW: 119177216 bytes
I update_engine: For partition system_b, device size = 1263079424, snapshot size = 1263079424, cow partition size = 119177216, cow file size = 1148841984
I update_engine: [liblp]Partition system_b-cow will resize from 0 bytes to 119177216 bytes
I update_engine: Successfully created snapshot partition for system_b
I update_engine: Remaining free space for COW: 0 bytes
I update_engine: For partition vendor_b, device size = 80506880, snapshot size = 80506880, cow partition size = 0, cow file size = 80826368
I update_engine: Successfully created snapshot partition for vendor_b
I update_engine: Allocating CoW images.
I update_engine: Successfully created snapshot for system_b
I update_engine: Successfully created snapshot for vendor_b
I update_engine: Successfully unmapped snapshot system_b
I update_engine: Mapped system_b-cow-img to /dev/block/dm-5
I update_engine: Mapped COW device for system_b at /dev/block/dm-6
I update_engine: Zero-filling COW device: /dev/block/dm-6
I update_engine: Successfully unmapped snapshot vendor_b
I update_engine: Mapped vendor_b-cow-img to /dev/block/dm-5
I update_engine: Mapped COW image for vendor_b at vendor_b-cow-img
I update_engine: Zero-filling COW device: /dev/block/dm-5
I update_engine: [liblp]Updated logical partition table at slot 1 on device super
I bcm-bootc: setSnapshotMergeStatus()
I update_engine: Successfully created all snapshots for target slot _b
```




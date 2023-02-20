# 20230219-Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl

Android 虚拟 A/B 分区推出快三年了，不论是 google 还是百度结果，除了源代码之外，竟然没有人提到这个 Android Virtual A/B  的调试工具 ，着实让人感觉意外。

所以我相信还有不少人不知道 Android OTA 到底都有哪些调试工具，这些工具又该如何使用？所以决定开一个专栏，专门介绍 Android OTA 相关的各种工具。



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
> 文章链接：



有下图为证，到目前位置，百度结果还没有 snapshotctl 相关内容：

![image-20230219214827241](images-20230219-Android OTA 相关工具(一) /image-20230219214827241.png)



对于 snapshotctl，除了 Android 自家的开发者之外，肯定有下游开发者用过，但没有人分享过这个工具，因此本篇算是全网对 snapshotctl 介绍的第一篇，我相信还有不少人连这个工具都没有听说过。



> 本文基于 Android 代码版本: android-11.0.0_r21，但后续版本也大同小异
>
> 在线代码：http://aospxref.com/android-11.0.0_r21/



其实 snapshotctl 的工具使用并不复杂，源码也还算简单，代码位于：

> system/core/fs_mgr/libsnapshot/snapshotctl.cpp

这里不再详细分析代码，主要演示 snapshotct 工具的使用。



## 1. snapshotctl 的功能

在早期版本(android-11.0.0_r21)中，snapshotctl 支持 dump 和 map 操作，后面又增加了 unmap 操作。

snapshotctl 的帮助信息:

```bash
console:/ # snapshotctl -h                                                     
snapshotctl: Control snapshots.
Usage: snapshotctl [action] [flags]
Actions:
  dump
    Print snapshot states.
  merge
    Deprecated.
  map
    Map all partitions at /dev/block/mapper
64|console:/ # 
```



## 2. dump 操作

dump 操作是 snapshtctl 最有用的操作，可以输出系统升级中的各种状态。

以下是我的一块板子上运行 `snapshotctl dump` 的输出:

```bash
console:/ # snapshotctl dump                                                   
snapshotctl W 10-10 21:43:54  3770  3770 snapshot.cpp:247] Cannot read /metadata/ota/snapshot-boot: No such file or directory
Update state: initiated
Compression: 0
Current slot: _a
Boot indicator: booting from unknown slot
Rollback indicator: No such file or directory
Forward merge indicator: No such file or directory
Source build fingerprint: google/inuvik/inuvik:11/RVC/eng.rocky.20221010.210616:userdebug/dev-keys
Snapshot: system_b
    state: CREATED
    device size (bytes): 1263079424
    snapshot size (bytes): 1263079424
    cow partition size (bytes): 119177216
    cow file size (bytes): 949866496
    allocated sectors: 0
    metadata sectors: 0
    compression: none
Snapshot: vendor_b
    state: CREATED
    device size (bytes): 80506880
    snapshot size (bytes): 80506880
    cow partition size (bytes): 0
    cow file size (bytes): 978944
    allocated sectors: 0
    metadata sectors: 0
    compression: none
console:/ # 
```



## 3. map 操作

如果升级中出现了问题，可以通过 `snapshotctl map` 操作把系统中的各种 base, cow 和 cow-img 等文件都映射成设备方便检查。



以下是一个映射示例：

```bash
console:/ # snapshotctl map
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:2525] Successfully unmapped snapshot system_b
snapshotctl I 10-11 19:59:53  6127  6127 fs_mgr_dm_linear.cpp:247] [libfs_mgr]Created logical partition system_b-base on device /dev/block/dm-4
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:638] Mapped system_b-cow-img to /dev/block/dm-5
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:2596] Mapped COW device for system_b at /dev/block/dm-6
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:2490] Mapped system_b as snapshot device at /dev/block/dm-7
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:2525] Successfully unmapped snapshot vendor_b
snapshotctl I 10-11 19:59:53  61[10577.688566] audit: rate limit exceeded
27  6127 fs_mgr_dm_linear.cpp:247] [libfs_mgr]Created logical partition vendor_b-base on device /dev/block/dm-8
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:638] Mapped vendor_b-cow-img to /dev/block/dm-9
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:2556] Mapped COW image for vendor_b at vendor_b-cow-img
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:2490] Mapped vendor_b as snapshot device at /dev/block/dm-10
snapshotctl I 10-11 19:59:53  6127  6127 snapshot.cpp:2741] MapAllSnapshots succeeded.
console:/ # 
```



上面的 map 操作映射了下面的文件：

```bash
console:/ # ls -lh data/gsi/ota/
total 454M
-rw------- 1 root root   26 2022-10-11 00:00 system_b-cow-img.img
-rw------- 1 root root 906M 2022-10-11 00:00 system_b-cow-img.img.0000
-rw------- 1 root root   26 2022-10-11 00:00 vendor_b-cow-img.img
-rw------- 1 root root 956K 2022-10-11 00:00 vendor_b-cow-img.img.0000
```

如果 super 空间有分配用于升级也会被映射，具体我还没有详细检查。



一旦映射了分区，就可以通过其它工具对升级的镜像进行检查了，例如使用 dmctl 工具查看映射的状态，如下：

```bash
console:/ # dmctl 
usage: dmctl <command> [command options]
       dmctl -f file
commands:
  create <dm-name> [-ro] <targets...>
  delete <dm-name>
  list <devices | targets> [-v]
  getpath <dm-name>
  getuuid <dm-name>
  info <dm-name>
  status <dm-name>
  resume <dm-name>
  suspend <dm-name>
  table <dm-name>
  help

-f file reads command and all parameters from named file

Target syntax:
  <target_type> <start_sector> <num_sectors> [target_data]
234|console:/ # dmctl table
Invalid arguments, see 'dmctl help'
234|console:/ # su
console:/ # dmctl list devices
Available Device Mapper Devices:
userdata             : 252:3
system_b             : 252:7
vendor_b             : 252:10
vendor_b-base        : 252:8
system_a             : 252:0
vendor_b-cow-img     : 252:9
vendor_a             : 252:1
system_b-base        : 252:4
system_b-cow-img     : 252:5
system_b-cow         : 252:6
scratch              : 252:2
console:/ # 
console:/ # dmctl info vendor_b-base
device        : vendor_b-base
active        : true
access        : rw 
activeTable   : true
inactiveTable : false
bufferFull    : false
console:/ # 
console:/ # dmctl info vendor_b-cow-img
device        : vendor_b-cow-img
active        : true
access        : rw 
activeTable   : true
inactiveTable : false
bufferFull    : false
console:/ # 
console:/ # 
console:/ # dmctl table vendor_b-cow-img
Targets in the device-mapper table for vendor_b-cow-img:
0-1912: linear, 259:4 6107136
console:/ # 
console:/ # dmctl table system_b-cow
Targets in the device-mapper table for system_b-cow:
0-888: linear, 259:3 2469000
888-232768: linear, 259:3 2627128
232768-2087976: linear, 252:5 0
console:/ #
console:/ # dmctl table system_b-cow-img
Targets in the device-mapper table for system_b-cow-img:
0-4096: linear, 259:4 569344
4096-8192: linear, 259:4 675840
8192-12288: linear, 259:4 1134592
12288-16384: linear, 259:4 1155072
16384-20480: linear, 259:4 1179648
20480-28672: linear, 259:4 1187840
28672-65536: linear, 259:4 1200128
65536-69632: linear, 259:4 1253376
69632-73728: linear, 259:4 1269760
73728-77824: linear, 259:4 1302528
77824-86016: linear, 259:4 1318912
86016-102400: linear, 259:4 1351680
102400-106496: linear, 259:4 1376256
106496-118784: linear, 259:4 1384448
118784-131072: linear, 259:4 1466368
131072-155648: linear, 259:4 1482752
155648-159744: linear, 259:4 1515520
159744-163840: linear, 259:4 1699840
163840-172032: linear, 259:4 1712128
172032-176128: linear, 259:4 1773568
176128-184320: linear, 259:4 1867776
184320-192512: linear, 259:4 2097152
192512-196608: linear, 259:4 2109440
196608-204800: linear, 259:4 2134016
204800-208896: linear, 259:4 2158592
208896-212992: linear, 259:4 2170880
212992-217088: linear, 259:4 2187264
217088-221184: linear, 259:4 2215936
221184-225280: linear, 259:4 2244608
225280-249856: linear, 259:4 2310144
249856-253952: linear, 259:4 2355200
253952-294912: linear, 259:4 2449408
294912-311296: linear, 259:4 2912256
311296-323584: linear, 259:4 4030464
323584-372736: linear, 259:4 4050944
372736-376832: linear, 259:4 4149248
376832-385024: linear, 259:4 4165632
385024-389120: linear, 259:4 4325376
389120-516096: linear, 259:4 4620288
516096-557056: linear, 259:4 4751360
557056-565248: linear, 259:4 4796416
565248-1855208: linear, 259:4 4812800
console:/ # 
```



## 4. unmap 操作

可以通过 `snapshotctl unmap` 将前面映射的分区卸载。



```bash
console:/ # snapshotctl unmap                                                  
snapshotctl I 10-11 19:59:48  6120  6120 snapshot.cpp:2525] Successfully unmapped snapshot system_b
snapshotctl I 10-11 19:59:48  6120  6120 snapshot.cpp:2525] Successfully unmapped snapshot vendor_b
console:/ # 
```



## 5. merge 操作

目前 snapshotctl 工具中的 merge 操作已经取消。

```bash
console:/ # snapshotctl merge
snapshotctl W 10-11 19:43:10  5986  5986 snapshotctl.cpp:66] Deprecated. Call update_engine_client --merge instead.
70|console:/ # 
```

这里的提示指出，如果需要进行 merge，可以通过命令：" `update_engine_client --merge`" 来进行。



所以，如果虚拟分区升级出现问题，可以先通过 `snapshotctl dump` 查看一些基本信息，然后通过 `snapshotctl map` 将所有虚拟分区设备映射出来进行检查，具体有哪些检查的手段，这个看每个人自己的工具储备了，也可以多关注我的博客["洛奇看世界(https://blog.csdn.net/guyongqiangx)"](https://blog.csdn.net/guyongqiangx)，后面陆续为您分享更多 OTA 工具，包括一些洛奇自己开发的工具。



## 6. 其它

到目前为止，我写过 Android OTA 升级相关的话题包括：
- 基础入门：《Android A/B 系统》系列
- 核心模块：《Android Update Engine 分析》 系列
- 动态分区：《Android 动态分区》 系列
- 虚拟 A/B：《Android 虚拟 A/B 分区》系列
- 升级工具：《Android OTA 相关工具》系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题。

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。

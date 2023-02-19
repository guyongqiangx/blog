# 20230219-Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl



Android 虚拟 A/B 分区推出都快三年了，百度搜索了一下 snapshotctl，网上竟然还没有关于虚拟 A/B 调试工具 snapshotctl 的介绍，这不得不说挺让我意外。

![image-20230219214827241](images-20230219-Android OTA 相关工具(一) /image-20230219214827241.png)

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



```bash
console:/ # snapshotctl dump                                                   
snapshotctl W 10-10 21:43:54  3770  3770 snapshot.cpp:247] Cannot read /metadata/ota/snapshot-boot: No such file or directory
Update state: initiated
Compression: 0
Current slot: _a
Boot indicator: booting from unknown slot
Rollback indicator: No such file or directory
Forward merge indicator: No such file or directory
Source build fingerprint: google/inuvik/inuvik:11/RVC/eng.rg9357.20221010.210616:userdebug/dev-keys
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



```bash
console:/ # snapshotctl unmap                                                  
snapshotctl I 10-11 19:59:48  6120  6120 snapshot.cpp:2525] Successfully unmapped snapshot system_b
snapshotctl I 10-11 19:59:48  6120  6120 snapshot.cpp:2525] Successfully unmapped snapshot vendor_b
console:/ # 
console:/ # 
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
console:/ # 
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
console:/ # 
console:/ # dmctl info system_b
device        : system_b
active        : true
access        : rw 
activeTable   : true
inactiveTable : false
bufferFull    : false
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
console:/ # 
console:/ # dmctl table system_b
Targets in the device-mapper table for system_b:
0-2466952: snapshot, 252:4 252:6 PO 8
console:/ # 
console:/ # 
console:/ # dmctl table system_b-base
Targets in the device-mapper table for system_b-base:
0-2466952: linear, 259:3 2048
console:/ # 
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
console:/ # dmctl table system_b-cow
Targets in the device-mapper table for system_b-cow:
0-888: linear, 259:3 2469000
888-232768: linear, 259:3 2627128
232768-2087976: linear, 252:5 0
console:/
```


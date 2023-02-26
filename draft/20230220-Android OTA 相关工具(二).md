# 20230220-Android OTA 相关工具(二) 动态分区之 dmctl

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
> 文章链接：https://guyongqiangx.blog.csdn.net/article/details/129229115

我在上一篇[《Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl》](https://blog.csdn.net/guyongqiangx/article/details/129122159) 中介绍了从虚拟 A/B 系统 (Android R)开始引入的 snapshot 调试工具 snapshotctl。

snapshotctl 本身可以做不少事情，比方说 dump 升级信息, map 和 unmap 各种虚拟分区等。

这一篇介绍动态分区调试工具 dmctl，配合 snapshotctl 工具，对各种 dm 开头的动态分区和虚拟分区进行调试更加方便。

为什么叫各种 ctl? 这里的 ctl 是 control 的简写，sanpshotctl 就是 snapshot control, 而 dmctl 就是 device mapper control。

因此，顾名思义，dmctl 就是用来操作控制 device mapper 设备的。Android 中用到的 device mapper 设备包括:

- `Linear`，线性映射设备，将 super 设备上的各个区域映射为单独分区就使用 `linear` 设备
- `Snapshot`，快照类设备，在虚拟 A/B 系统上引入了快照类设备包括:
  -  `snapshot-origin` 设备
  - `snapshot` 设备
  - `snapshot-merge` 设备
- `Verity`，一致性设备，Android 打开启动时验证以后，使用 `verity` 设备来确保分区完整



> 更多关于 Android OTA 升级相关文章的列表和内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303) 
>
> 如果您已经订阅了收费专栏，请务必加我微信，拉你进相应专栏的答疑群。

> 本文基于 Android 代码版本: android-11.0.0_r21，但后续版本也大同小异
>
> 在线代码：http://aospxref.com/android-11.0.0_r21/



我其实在[《Android 动态分区详解(二) 核心模块和相关工具介绍》](https://guyongqiangx.blog.csdn.net/article/details/123931356)已经展示过 dmctl 工具的简单用法了。

这一篇专门介绍 dmctl 工具。

## 1. dmctl 的帮助信息

dmctl 工具的功能很多，学习 dmctl 的入口就是查看其帮助信息。

```bash
console:/ # dmctl help
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
console:/ # 
```

## 2. create 操作

通过 create 操作可以创建各种设备，目前的实现包括 zero, linear, verity, snapshot, snapshot-origin 等设备。

在使用 create 操作时，每一个设备都需要一组通用参数：

```
<target_type> <start_sector> <num_sectors>
```

这一组参数主要是指定**目标设备**的类型以及大小



除了通用参数外，对每一类 device mapper 设备，还需要提供相应的 `<targets>`参数，各设备详细的 `<targets>` 参数如下:

| 设备类型        | Targets 参数                                        |
| --------------- | --------------------------------------------------- |
| Zero            | 无                                                  |
| Linear          | `<block_device> <sector>`                           |
| Android-verity  | `<public-key-id> <block_device>`                    |
| Bow             | `<block_devices>`                                   |
| Snapshot-origin | `<block_devices>`                                   |
| Snapshot        | `<block_device> <block_device> <mode> <chunk_size>` |
| Snapshot-merge  | `<block_device> <block_device> <chunk_size>`        |

`<targets>`参数主要是指定**源设备**信息，以及附加参数。

> dmctl 的 `<targets>`参数对应于 dmsetup 工具的 `--table` 信息。在代码中，dmctl 将 `<targets>` 参数转换为 table 信息，传递给底层创建设备。



所以，一个完整的 `dmctl create <dm-name>` 的参数应该是这样:

```bash
# 通用参数格式
dmctl create <dm-name> <target_type> <start_sector> <num_sectors> <targets>

# Zero
dmctl create <dm-name> zero <start_sector> <num_sectors>

# Linear
dmctl create <dm-name> linear <start_sector> <num_sectors> <block_device> <sector>

# Android-verity
dmctl create <dm-name> android-verity <start_sector> <num_sectors> <public-key-id> <block_device>

# Bow
dmctl create <dm-name> bow <start_sector> <num_sectors> <block_devices>

# Snapshot-origin
dmctl create <dm-name> snapshot-origin <start_sector> <num_sectors> <block_devices>

# Snapshot
dmctl create <dm-name> snapshot <start_sector> <num_sectors> <block_device> <block_device> <mode> <chunk_size>

# Snapshot-merge
dmctl create <dm-name> snapshot <start_sector> <num_sectors> <block_device> <block_device> <chunk_size>
```



> device mapper 设备基于最小的单位 sector 进行操作，sector 的大小可以配置，但通常都是默认的 512 bytes。
>
> 有些 device mapper 设备基于 chunk 进行操作，这里的 chunk 是比 sector 大的数据块。
>
> 例如快照设备基于 chunk 进行操作，其大小在创建 snapshot 时通过 chunksize 设置。
>
> 比如设置 chunksize = 8，表明 1 个 chunk 由 8 个 sector 构成，因此 1 x chunk = 8 x sector = 4KB。
>
> snapshot 驱动中默认的 chunksize 为 32，对应 chunk 大小为 16KB。



### Zero

代码里面说支持创建 zero 类型的设备，但是当我尝试创建时，提示失败，原因是"unknow target type":

```bash
console:/ # dmctl create dm-rocky-zero zero 0 2048
[ 1031.230156] device-mapper: table: 252:5: zero: unknown target type
dmctl E 10-11 17:26:57  3840  3840 dm.cpp:262] DM_TABLE_LOAD failed: Invalid argument
Failed to create device-mapper device with name: dm-rocky-zero
```

这个 zero 类型的设备类似系统自带的 `/dev/zero`，用于产生 0 的 device mapper 虚拟块设备，很少用到。



### Linear

将在 super 设备内的 2048 sector 开始的 2466912 个 sector 映射为 dm-rocky 设备。

```bash
# 使用 dmctl create 创建虚拟设备 dm-rocky
# 映射信息: "linear 0 2466912 /dev/block/by-name/super 2048"
console:/ # dmctl create dm-rocky linear 0 2466912 /dev/block/by-name/super 2048
console:/ # ls -lh /dev/block/mapper/
total 0
drwxr-xr-x 2 root root 200 2022-04-02 15:55 by-uuid
lrwxrwxrwx 1 root root  15 2022-04-02 15:55 dm-rocky -> /dev/block/dm-7
lrwxrwxrwx 1 root root  15 2015-01-01 08:00 system-verity -> /dev/block/dm-3
lrwxrwxrwx 1 root root  15 2015-01-01 08:00 system_a -> /dev/block/dm-0
lrwxrwxrwx 1 root root  15 2015-01-01 08:00 userdata -> /dev/block/dm-6
lrwxrwxrwx 1 root root  15 2015-01-01 08:00 vendor-verity -> /dev/block/dm-4
lrwxrwxrwx 1 root root  15 2015-01-01 08:00 vendor_a -> /dev/block/dm-1
lrwxrwxrwx 1 root root  15 2015-01-01 08:00 vendor_dlkm-verity -> /dev/block/dm-5
lrwxrwxrwx 1 root root  15 2015-01-01 08:00 vendor_dlkm_a -> /dev/block/dm-2

console:/ # dmctl table dm-rocky
Targets in the device-mapper table for dm-rocky:
0-2466912: linear, 259:3 2048

# 查看 system_a 的映射表
console:/ # dmctl table system_a
Targets in the device-mapper table for system_a:
0-2466912: linear, 259:3 2048

# 查看当前系统中的所有 device mapper 设备
console:/ # dmctl list devices
Available Device Mapper Devices:
userdata             : 252:4
system_a             : 252:0
vendor-verity        : 252:3
vendor_a             : 252:1
system-verity        : 252:2
dm-rocky             : 252:5
```

从上面看到，dm-rocky 和现在 system_a 分区的映射信息是一样的，此时系统将映射给 system_a 分区的部分又再次映射为新的分区设备 `/dev/block/by-name/dm-rocky`。



### Snapshot，Snapshot-origin 和 Snapshot-merge

创建 snapshot, snapshot-origin 和 snapshot-merge 的操作相对复杂，这里暂时不再详细列出来，后续考虑增加。

更多关于快照原理和操作的文章，请参考我介绍快照原理和实践的两篇文章：

- [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
  - 链接：https://blog.csdn.net/guyongqiangx/article/details/128494795
- [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)
  - 链接：https://blog.csdn.net/guyongqiangx/article/details/128496471



> 关于 `dmctl create` 创建各种 device mapper 设备的示例，实际使用较少，后续陆续补充完善。

## 3. list 操作

使用 `dmctl list` 列举当前系统的所有 device mapper 设备：

```bash
console:/ # dmctl list devices
Available Device Mapper Devices:
userdata             : 252:6
vendor_dlkm-verity   : 252:5
system_a             : 252:0
vendor-verity        : 252:4
vendor_dlkm_a        : 252:2
vendor_a             : 252:1
system-verity        : 252:3
```



如果希望查看更多的详细信息，可以使用 `-v` 选项:

```bash
console:/ # dmctl list devices -v
Available Device Mapper Devices:
userdata             : 252:4
  target#1: 0-11534336: default-key, aes-xts-plain64 - 0 259:4 0 3 allow_discards sector_size:4096 iv_large_sectors
system_a             : 252:0
  target#1: 0-2466912: linear, 259:3 2048
vendor-verity        : 252:3
  target#1: 0-154592: verity, 1 252:1 252:1 4096 4096 19324 19324 sha1 758e924ff5378790707d7a890e656611a281e6ca 26cd8465eda1b97b94af4a2f95786b73cf61c777 10 restart_on_corruption ignore_zero_blocks use_fec_from_device 252:1 fec_blocks 19478 fec_start 19478 fec_roots 2
vendor_a             : 252:1
  target#1: 0-157240: linear, 259:3 2469888
system-verity        : 252:2
  target#1: 0-2427824: verity, 1 252:0 252:0 4096 4096 303478 303478 sha1 de3446b6b2b4e86e9b941df4f7714824e4a60e29 21f2e10d1358ed8ac32df838ba446c3fe6bf883a 10 restart_on_corruption ignore_zero_blocks use_fec_from_device 252:0 fec_blocks 305869 fec_start 305869 fec_roots 2
console:/ # 
```

当 `-v` 选项以后，不仅可以列举所有的 device mapper 设备，还能显示设备详细的映射信息。

## 4. suspend 和 resume 操作

使用 `dmctl suspend` 操作暂停对指定 device mapper 设备新的 I/O 操作，已经在进行中的 I/O 操作不受影响。

```bash
console:/ # dmctl info system_a
device        : system_a
active        : true
access        : ro 
activeTable   : true
inactiveTable : false
bufferFull    : false
console:/ # 
console:/ # 
console:/ # dmctl suspend system_a
console:/ # dmctl info system_a
device        : system_a
active        : false
access        : ro 
activeTable   : true
inactiveTable : false
bufferFull    : false
console:/ # 
```

从上面的操作可见，

在 `dmctl suspend` 操作之前，通过 `dmctl info system_a` 看到的 active 状态为 true；

在 `dmctl suspend ` 操作之后，通过 `dmctl info system_a` 看到的 active 状态为 false;



使用 `dmctl resume` 操作恢复对指定 device mapper 设备(已经 suspend 暂停的设备)的 I/O 操作。

```bash
console:/ # dmctl resume system_a
console:/ # dmctl info system_a
device        : system_a
active        : true
access        : ro 
activeTable   : true
inactiveTable : false
bufferFull    : false
```

在 `dmctl resume` 之后，通过 `dmctl info system_a` 看到的 active 状态恢复为 true;

## 5. delete 操作

使用 `dmctl delete  `删除指定名称的 device mapper 设备: 

```bash
# 查看当前所有的 device mapper 设备
console:/ # dmctl list devices
Available Device Mapper Devices:
userdata             : 252:4
system_a             : 252:0
vendor-verity        : 252:3
vendor_a             : 252:1
system-verity        : 252:2
dm-rocky             : 252:5

# 删除名为 dm-rocky 的设备
console:/ # dmctl delete dm-rocky

# 再次查看设备列表时，已经没有 dm-rocky 设备了
console:/ # dmctl list devices
Available Device Mapper Devices:
userdata             : 252:4
system_a             : 252:0
vendor-verity        : 252:3
vendor_a             : 252:1
system-verity        : 252:2
```

## 6. getpath 操作

使用 `dmctl getpath` 查看 system_a 分区的路径。

```bash
console:/ # dmctl getpath system_a
/dev/block/dm-0
```

## 7. getuuid 操作

使用 `dmctl getuuid` 获取分区 system_a 的 UUID:

```bash
console:/ # dmctl getuuid system_a
a8f76dd5-278d-4800-973a-0c9fc8607ff2
```

## 8. info 操作

使用 `dmctl info` 查看 system_a 分区的信息:

```bash
console:/ # dmctl info system_a
device        : system_a
active        : true
access        : ro 
activeTable   : true
inactiveTable : false
bufferFull    : false
```

## 9. status 操作

使用 `dmctl status` 查看 system_a 分区的状态:

```bash
console:/ # dmctl status system_a
Targets in the device-mapper table for system_a:
0-2498104: linear
```

## 10. table 操作

使用 `dmctl table` 查看 system_a 分区的映射信息:

```bash
console:/ # dmctl table system_a
Targets in the device-mapper table for system_a:
0-2498104: linear, 259:3 2048
```

## 11. 其它

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

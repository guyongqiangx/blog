## 20240716-Android Update Engine 分析（三一）Android 能在升级时新增分区吗?

- 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
- 原文链接：https://blog.csdn.net/guyongqiangx/article/details/140508309


## 0. 背景

经常在讨论群和答疑群看到有同学问这个问题，私聊咨询问这个问题的也不在少数。

例如：

![](./images-20240716-Android Update Engine 分析（三一）Android 能在升级时新增分区吗？/1-new-partition-1.png)

又例如：

![](./images-20240716-Android Update Engine 分析（三一）Android 能在升级时新增分区吗？/2-new-partition-2.png)

这里打算分两篇来介绍这个问题：

- 第一篇，介绍分区调整的基本原理
  - 包括普通分区的增加，以及 super 设备上分区的增加
- 第二篇，新增分区实战
  - 基于 Android 12(S) 代码，提供一个新增分区的实例



作为第一篇，本文从原理角度出发，详细分析分区更新的底层逻辑，让你对升级时能否增加、修改和删除分区，以及修改分区可能的风险有一个彻底的认识。



> 核心代码[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html)系列，文章列表：
>
> - [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)
>
> - [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)
>
> - [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)
>
> - [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)
>
> - [Android Update Engine分析（五）服务端核心之Action机制](https://blog.csdn.net/guyongqiangx/article/details/82226079)
>
> - [Android Update Engine分析（六）服务端核心之Action详解](https://blog.csdn.net/guyongqiangx/article/details/82390015)
>
> - [Android Update Engine分析（七） DownloadAction之FileWriter](https://blog.csdn.net/guyongqiangx/article/details/82805813)
>
> - [Android Update Engine分析（八）升级包制作脚本分析](https://blog.csdn.net/guyongqiangx/article/details/82871409)
>
> - [Android Update Engine分析（九） delta_generator 工具的 6 种操作](https://blog.csdn.net/guyongqiangx/article/details/122351084)
>
> - [Android Update Engine分析（十） 生成 payload 和 metadata 的哈希](https://blog.csdn.net/guyongqiangx/article/details/122393172)
>
> - [Android Update Engine分析（十一） 更新 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122597314)
>
> - [Android Update Engine分析（十二） 验证 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122634221)
>
> - [Android Update Engine分析（十三） 提取 payload 的 property 数据](https://blog.csdn.net/guyongqiangx/article/details/122646107)
>
> - [Android Update Engine分析（十四） 生成 payload 数据](https://blog.csdn.net/guyongqiangx/article/details/122753185)
>
> - [Android Update Engine分析（十五） FullUpdateGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122767273)
>
> - [Android Update Engine分析（十六） ABGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122886150)
>
> - [Android Update Engine分析（十七）10 类 InstallOperation 数据的生成和应用](https://blog.csdn.net/guyongqiangx/article/details/122942628)
>
> - [Android Update Engine分析（十八）差分数据到底是如何更新的？](https://blog.csdn.net/guyongqiangx/article/details/129464805)
>
> - [Android Update Engine分析（十九）Extent 到底是个什么鬼？](https://blog.csdn.net/guyongqiangx/article/details/132389438)
>
> - [Android Update Engine分析（二十）为什么差分包比全量包小，但升级时间却更长？](https://blog.csdn.net/guyongqiangx/article/details/132343017)
>
> - [Android Update Engine分析（二一）Android A/B 的更新过程](https://blog.csdn.net/guyongqiangx/article/details/132536383)
>
> - [Android Update Engine分析（二二）OTA 降级限制之 timestamp](https://blog.csdn.net/guyongqiangx/article/details/133191750)
>
> - [Android Update Engine分析（二三）如何在升级后清除用户数据？](https://blog.csdn.net/guyongqiangx/article/details/133274277)
>
> - [Android Update Engine分析（二四）制作降级包时，到底发生了什么？](https://blog.csdn.net/guyongqiangx/article/details/133421556)
>
> - [Android Update Engine分析（二五）升级状态 prefs 是如何保存的？](https://blog.csdn.net/guyongqiangx/article/details/133421560)
>
> - [Android Update Engine分析（二六）OTA 更新后不切换 Slot 会怎样？](https://blog.csdn.net/guyongqiangx/article/details/133691683)
>
> - [Android Update Engine分析（二七）如何实现 OTA 更新但不切换 Slot？](https://blog.csdn.net/guyongqiangx/article/details/133849661)
>
> - [Android Update Engine分析（二八）payload.bin 文件还能再压缩吗？](https://blog.csdn.net/guyongqiangx/article/details/138014834)
>
> - [Android Update Engine分析（二九）如何进行连续多个版本的升级？](https://blog.csdn.net/guyongqiangx/article/details/138849767)
>
> - [Android Update Engine分析（三十）有了A/B系统，为什么还要 Recovery？](https://blog.csdn.net/guyongqiangx/article/details/140345412)
>
> - [Android Update Engine分析（三一）Android 能在升级时新增分区吗?](https://blog.csdn.net/guyongqiangx/article/details/140508309)

> 如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。



## 1. 分区的基本原理

在开始正式话题之前，先看下分区的基本原理。

### 1.1 分区划分

#### 单个物理设备分区

所谓分区，就是将一个物理存储设备(如硬盘、SSD，eMMC, SD 卡等)划分为多个独立的逻辑单元(区域)。每个逻辑单元(分区)在操作系统中被视为一个独立的"磁盘"。

这是最简单最传统的方式。

例如，在我上大学的年代，主流的硬盘是 40G，通常喜欢将其分为 C, D, E, F 四个分区。现在比较懒了，新买的笔记本 2T，直接就做一个逻辑分区，因此只有一个 C 盘。

又例如，Android 手机的 eMMC 存储设备，会被划分为 bootloader, boot, recovery, firmware, data 等分区。



#### 多个物理设备合并后分区

前面提到的分区主要是将一个物理设备划分成多个逻辑分区。

现在也有将多个物理设备通过映射形成一个设备的情况。典型的如 RAID 磁盘阵列，先将多个物理设备通过某种特定的管理映射为一个设备，然后再在此基础上划分成多个分区。



例如，RAID-0 阵列，可以简单理解为将多个物理磁盘拼接为一个大磁盘。当然，这种 RAID-0 阵列只要有一个盘坏了，那整个拼接的磁盘就坏了，因此很少使用。



#### 物理设备域映射成分区

随着虚拟化技术的出现，现在可以将物理设备上一个或多个区域映射成一个单独的逻辑分区。

例如，在实现了动态分区的 Android 设备上，将 super 分区的某一个或几个区域映射成 system 或 vendor 分区。

在 VAB 的 Android 系统上，升级时从 /data 分区下分配多个连续的数据文件，然后将这些数据文件映射成快照 COW 分区。



### 1.2 分区表数据

现在问题来了，设备划分了分区之后，系统是如何知道设备的哪个部分是属于哪个分区的呢？

答案就是分区表。系统通过读取并解析分区表数据，从而明确设备的哪个部分属于哪个分区。



#### 单个物理设备分区

对于单个设备，最常见的分区表包括:

- MBR (Master Boot Record)
- GPT (GUID Partition Table)



在较早的 DOS 和 Windows 时代，在设备头部有一个 MBR 分区表，但 MBR 有较多的限制，例如只能支持4个主分区，单个分区最大容量为2TB（因为MBR使用32位来表示分区的起始和结束扇区，每个扇区通常为512字节或4096字节（4KB）。因此，MBR分区表的分区大小限制为2TB），只支持传统的BIOS启动方式，不支持 UEFI（统一可扩展固件接口）等。

所以随后发展出了 GPT 分区表。



单个物理设备划分成多个分区的情况，基本上都是在设备上维护一个 MBR 或 GPT 分区表。例如 eMMC 在 *User Data* *Area* 开始存放的 GPT数据。

> 关于 GPT 分区，请参考：[《博通机顶盒平台GPT分区和制作工具》](https://blog.csdn.net/guyongqiangx/article/details/68924436)



#### 多个物理设备合并后分区



对于多个设备组成磁盘阵列的情况，一般在磁盘阵列控制器内部维护了一个分区表来管理多个设备。当外部向控制器发起读写请求时，控制器根据内部维护的分区表，来决定将读写请求分发给相应的物理设备。



如果是通过软件实现的磁盘阵列，同样也会在系统的某个位置维护一个分区表来管理多个设备。



#### 物理设备域映射成分区



至于将物理设备的部分映射成多个分区的情况，一般在某个地方也会维护一个分区表。

例如，对于 Android 上 super 内部的动态分区，其分区表存放在 super 设备开始的地方，叫做 lpmetadata。

关于 super 区域上分区表的细节，请参考文章[《Android 动态分区详解(一) 5 张图让你搞懂动态分区原理》](https://blog.csdn.net/guyongqiangx/article/details/123899602)。

至于 VAB 升级时，从 /data 下分配多个数据文件，然后将这些数据文件映射成快照分区（COW）的情况，其对应的分区数据位于：`/metadata/gsi/ota/lp_metadata`。

因为 COW 的快照分区表数据位于 `/metadata` 分区，这也就是为什么在升级完成前不能擦除 `/metadata` 分区的原因。因为一旦擦除了 `/metadata` 分区，就无法再映射出快照分区了。

> 更多关于 COW  设备的细节，请参考[《Android 虚拟 A/B 详解(九) cow 的存储是如何分配的？》](https://blog.csdn.net/guyongqiangx/article/details/129494397)



## 2. 增加或调整分区

有了前面第 1 节的基础，我们现在进一步深入下。

如果我们要修改分区，例如增加，调整或删除一个分区，其实质就是修改对应的分区表数据。

修改了分区表数据，当系统重新解析分区表时，就能够看到新的分区了。



那系统什么时候解析分区表呢？



### 2.1 GPT 分区表

对于 MBR 和 GPT 这样的分区表，在设备启动过程中, bootloader 会读取分区表，并传递给主系统(如 linux)。如果 bootloader 没有将分区表专递给 kernel，则在 kernel 的启动过程中会解析分区表，在内存中建立分区结构。

一旦系统启动后，看到的分区就无法改动了。除非设备重启，bootloader 或 kernel 再次读取并解析分区表。这就是为什么你的设备更新了 GPT 分区数据后，需要重启生效的原因。



### 2.2 super 设备的分区表

对于 Android 设备上的动态分区，其本身位于 super 头部开始的地方，称为 metadata。在 Android 系统进入 Linux 后，完成第一阶段的初始化之后，系统读取和解析 super 头部的 metadata 映射加载 system, vendor, product 等分区。

通过修改 super 头部的 metadata 就达到了修改动态分区的目的。

必须要强调的是，尽管 super 内部的分区，可以通过修改 metadata 随意调整的。但 super 自身是一个静态分区，相应的分区数据位于 GPT 中，系统一旦启动加载了 GPT 数据，就意味着 super 大小已经确定了。这就是为什么 super 的大小需要在设计时就要定下来的原因，因为一旦写入 GPT，就修改不了了。



super 上的分区表 metadata 是什么时候更新的呢？

有两种情况，

一种就是设备出厂时写入 super 镜像，相应的 metadata 也随之更新。

另一种情况是 OTA 更新时，系统会读取 payload 中新的分区槽位数据，然后更新到 super 的 metadata 数据中。

具体操作是这样的：

当前系统运行在 A 槽位，通过 OTA 升级更新 B 槽位。在升级一开始，系统会删除 super 头部 metadata 中 B 槽位的全部分区映射信息，然后根据 payload 中新的分区信息，在 super 的 metadata 中重建 B 槽位的分区表。

驱动根据 B 槽位的分区表，映射出完整的 B 槽位分区，完成后开始 B 槽位的更新操作。



我们可以看到，一旦 Android 设备启动后，当前槽位的分区数据不能再更改，但目标槽位的分区数据其实是可以任意修改的。无非就是在修改前，先取消目标槽位分区的映射，然后修改分区数据，再重新映射得到新的目标槽位分区。



### 2.3 COW 设备的分区表

VAB 版本的 Android 在更新时，会从 /data 下分配多个连续的数据文件(为了简化，暂时不考虑从 super 上分配 COW 的情况)，然后将这些数据文件通过映射得到快照设备 COW。在此基础上，基于旧槽位分区 A 和快照设备 COW，得到新槽位分区 B，整个过程异常复杂。



对于 /data 下分配的多个连续数据文件，系统是如何知道该如何映射为 COW 分区的呢？

答案也是分区表，只不过这个分区表不在 GPT 中，也不在 super 头部的 metadata 中，而是保存在文件 `/metadata/gsi/ota/lp_metadata` 内。



系统通过读取并解析 `/metadata/gsi/ota/lp_metadata` 文件，就知道 /data 下用于 COW 快照设备的多个数据文件的映射参数，从而映射出 COW 设备。



## 3. 能在升级时新增分区吗？

### 3.1 GPT 分区

如果想在 super 之外新增分区，显然就需要修改储存设备的分区表，即 GPT。

理论上是可以通过修改 GPT 分区表，然后重启看到新分区或修改后分区的。



但问题是，修改 GPT 的风险太大，不建议通过修改 GPT 来增加分区。

理由如下：

GPT 数据是全局的，更新 GPT 时一旦发生断电，程序中断等情况，导致 GPT 分区并没有完全更新甚至出现 GPT 数据被破坏时，系统重启后可能出现无法启动的情况，设备基本等于变砖了。

你可能会说，这种情况发生的几率很低。但很低不代表没有，一旦当你已经出厂的几十万，上百万设备因为这种情况导致设备不能启动时，代价会很大。

了解 GPT 的会说，在设备上不是还有一个 GPT 镜像数据吗？但其实很多程序的代码并不完善，所谓的 GPT 镜像数据因此就成了摆设。



如果实在要通过更新 GPT 来增加或调整分区，以下是一些建议：

- 仔细规划 GPT 分区更改
- GPT 更新前备份所有重要数据
- 确保电源稳定，尽量避免中断
- 先进行完整测试，稳定后再部署



更新 GPT 没有万一，因为万一发生了，代价太大了。



### 3.2  super 上的分区

super 上的分区属于动态分区，通过调整 super 上的 metadata 即可。

所以，完全可以在升级时，在 super 上执行新增，修改或删除分区操作，唯一要确保的就是分区大小要合理。



至于 super 上如何新增分区，后续单独写一篇详细介绍。



## 4. 其它

到目前为止，我写过 Android OTA 升级相关的话题包括：

- 基础入门：《Android A/B 系统》系列
- 核心模块：《Android Update Engine 分析》 系列
- 动态分区：《Android 动态分区》 系列
- 虚拟 A/B：《Android 虚拟 A/B 分区》系列
- 升级工具：《Android OTA 相关工具》系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题。

我有几个 Android OTA 升级讨论群，里面现在有小几百的朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 交流”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。

另外，我近期在群里找了个合伙人整理 OTA 讨论群的问题，放到知识星球，如果你对这些问题感兴趣，欢迎加入星球查阅。知识星球的更多信息，请参考：[《Android OTA 问题交流微信群和知识星球》](https://blog.csdn.net/guyongqiangx/article/details/137981377)










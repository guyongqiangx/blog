## 20240716-Android Update Engine 分析（三一）Android 能在升级时新增分区吗?

- 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
- 原文链接：



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
> - [Android Update Engine分析（三一）Android 能在升级时新增分区吗?]()

> 如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。



## 1. 分区的基本原理



Claude

存储设备分区的基本原理涉及将物理存储介质划分为多个逻辑单元。以下是存储设备分区的主要原理和概念:

1. 分区的定义:
分区是将一个物理存储设备(如硬盘、SSD等)划分为多个独立的逻辑单元。每个分区在操作系统中被视为一个独立的"磁盘"。

2. 分区表:
分区信息存储在分区表中,通常位于存储设备的开头。常见的分区表格式包括:
- MBR (Master Boot Record)
- GPT (GUID Partition Table)

3. 分区类型:
- 主分区:可以直接用于安装操作系统和存储数据
- 扩展分区:用于容纳逻辑分区
- 逻辑分区:在扩展分区内创建的分区

4. 分区的目的:
- 组织和管理数据
- 安装多个操作系统
- 分离系统文件和用户数据
- 提高性能和安全性

5. 文件系统:
每个分区通常会被格式化为特定的文件系统,如:
- Windows: NTFS, FAT32
- Linux: ext4, XFS
- macOS: APFS, HFS+

6. 分区大小和对齐:
分区的大小和起始位置通常会按照特定的扇区边界对齐,以优化性能。

7. 分区工具:
常用的分区工具包括:
- Windows: Disk Management
- Linux: fdisk, parted
- 第三方工具: GParted, Partition Magic

8. 动态分区:
一些现代操作系统支持动态分区,允许在不重启的情况下调整分区大小。

9. 分区加密:
可以对单个分区进行加密,以提高数据安全性。

10. 虚拟化和逻辑卷管理:
现代系统还支持更高级的存储管理技术,如LVM(Logical Volume Management)。

分区是存储设备管理的基础,理解这些原理有助于更好地组织和管理数据存储。您是否希望我详细解释其中的某个具体方面?



存储设备分区是将一个物理存储设备（如硬盘驱动器、固态硬盘等）划分成多个逻辑部分的过程。这样做可以提高数据管理的灵活性和效率，同时也有助于数据的安全性和系统的稳定性。以下是存储设备分区的基本原理和步骤：

1. **物理存储设备**：
   - 物理存储设备是指实际的硬件，如硬盘驱动器（HDD）、固态硬盘（SSD）等。

2. **分区表**：
   - 分区表是存储在存储设备上的一个数据结构，它定义了存储设备上的分区信息。常见的分区表类型有MBR（主引导记录）和GPT（全局唯一标识符分区表）。

3. **主分区与扩展分区**：
   - 在MBR分区表中，一个硬盘可以有最多4个主分区，或者3个主分区加一个扩展分区。扩展分区可以进一步划分为多个逻辑分区。
   - GPT分区表则没有主分区和扩展分区的概念，它支持更多的分区数量。

4. **文件系统**：
   - 文件系统是用于存储和组织文件的一种数据结构。常见的文件系统有FAT32、NTFS、EXT4、APFS等。每个分区都需要一个文件系统来管理其上的数据。

5. **分区过程**：
   - **初始化**：首先，需要对存储设备进行初始化，这通常包括低级格式化和创建分区表。
   - **创建分区**：在分区表中定义分区的大小和类型。这可以通过磁盘管理工具或操作系统的安装程序完成。
   - **格式化分区**：为每个分区选择一个文件系统并进行格式化。格式化会创建文件系统的元数据结构，如目录树、文件分配表等。
   - **挂载分区**：在操作系统中将分区挂载到一个目录路径，使其可以被访问和使用。

6. **分区管理**：
   - 分区管理包括调整分区大小、合并分区、转换分区类型等操作。这些操作可以通过磁盘管理工具或命令行工具完成。

7. **数据恢复与备份**：
   - 分区可以提高数据的安全性，因为一个分区的损坏不会影响到其他分区。因此，定期备份分区数据是非常重要的。

8. **安全性**：
   - 分区还可以用于提高系统的安全性。例如，可以将操作系统和用户数据分开存储在不同的分区，这样即使用户数据被破坏，操作系统仍然可以正常运行。

通过以上步骤，存储设备分区不仅能够提高数据管理的灵活性和效率，还能增强数据的安全性和系统的稳定性。




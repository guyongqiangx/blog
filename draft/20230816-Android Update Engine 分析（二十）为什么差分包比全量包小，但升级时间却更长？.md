# 20230816-Android Update Engine 分析（二十）为什么差分包比全量包小，但升级时间却更长？

![1692259893](images-20230816-Android Update Engine 分析（二十）为什么差分包比全量包小，但升级时间却更长？/android_update_engine_20_title.png)

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 原文链接：https://blog.csdn.net/guyongqiangx/article/details/132343017

## 0. 导读

时不时有同学在 OTA 讨论群和 VIP 答疑群问升级速度的问题，其中一个典型的问题是：

**为什么差分包比全量包小，但升级时间却更长？**



与几百 M 甚至几个 G 的全量包相比，差分包相对较小，有时候甚至小到只有几个 M，这么小的差分包，意味携带的 payload 数据很少，写入很少的数据耗时应该很少才是。但为什么现实中差分升级时，差分包很小，但升级时间却比大很多的全量包升级更长。



前段时间又有类似话题出现在 VIP 答疑群，几经讨论，这个问题算是彻底弄清楚了。本篇专门探讨这个问题为你揭晓答案。



本文中，全量升级又称为整包升级，差分升级又称为增量升级。因此：

- 全量升级 = 整包升级，全量包 = 整包
- 增量升级 = 差分升级，增量包 = 差分包



> 本文基于 android-11 进行演示，但也适用于其它支持 A/B 分区升级的 Android 版本。
>

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
> - [Android Update Engine分析（二十）为什么差分包比全量包小，但升级时间却更长？](https://blog.csdn.net/guyongqiangx/article/details/132343017)

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。

## 1. 结论

直入主题，先上结论。

升级文件 payload.bin 主要由两部分组成，前面部分的 manifest 数据以及随后的 payload 数据。

差分包比全量包小，只能说明差分包的 payload 数据少。

由于差分升级需要从源分区读取数据，实际的 I/O 操作会更多。并不是新版本和旧版本相比，改动了 1M 的地方就只操作这 1M 的数据。所有其它没有修改过的地方，也需要从源分区读取，并写入到目标分区。

另外，如果差分的差异较多，在还需要在内存中进行大量的差分数据还原计算。相比于全量升级需要在内存中解压缩数据，大量的差分还原对 CPU 和内存的要求都更高。

因此出现了差分包不大，但升级时间却不短的现象。



## 2. 升级原理

在进一步分析升级包数据之前，先回顾总结下差分升级和整包升级的的原理。

### 2.1 差分升级的 3 个阶段

这里把 《Android Update Engine 分析（十八）差分数据到底是如何更新的？》中提到的系统差分升级的 3 个阶段再复习一下：

从宏观上说，整个差分升级过程大致分成三步：

假设升级前的旧系统为 V1, 升级后的新系统为 V2, 差分数据为 Delta

1. 制作差分包

   利用新旧的镜像文件生成差分数据，并打包到 payload.bin 文件中，得到差分包升级文件；

   即：V2(新) - V1(旧) = Delta(差分)

   

2. 传输差分包

   服务端将差分包数据传输给设备端。可以是网络传输，也可以是通过 U 盘复制；

   即：Server(Delta) -> Device(Delta)

   

3. 还原差分包

   设备端接收到差分包升级文件后，基于旧分区，在内存中使用差分数据还原，得到新分区数据并写入；

   即：V1(旧) + Delta(差分) = V2(新)



通过上面的这 3 个步骤，利用系统上已有的旧系统 V1 的镜像，通过差分数据 Delta，而不需要传输新系统 V2 的全部镜像文件即可完成升级。



所以，差分还原，需要读取系统上已有旧系统 V1 的数据到内存中，再加上差分数据 Delta，在内存中还原得到新系统 V2 的数据，再将 V2 写入到新系统中。



### 2.2 整包升级的 3 个阶段

和差分升级一样，宏观上，整包(全量)升级也分成三步:

1. 制作全量包

   基于编译生成的各个分区 image 进行分块处理，主要是把每一块的数据经过处理后打包到 payload.bin 文件中，得到全量包升级文件。

   即: Data1 -> Data2(压缩)

   > 问题 1：既然主要操作是压缩，那为什么不直接将分区 image 进行压缩处理，而是要先分块呢？

   

2. 传输全量包

   服务端将整包数据栓递给设备端，可以是网络传输，也可以是通过 U 盘复制;

   即: Server(Data2) -> Device(Data2)

   

3. 还原全量包

   设备端接收到全量包升级文件后，在内存中将相关数据还原(主要是解压缩)，得到原始数据并写入到分区中；

   即: Data2 -> Data1(解压缩)

   

通过上面这 3 个步骤，将全量包中的数据还原并写入到相应分区中完成升级。



> 本文为洛奇看世界(guyongqiangx)原创
>
> 链接：https://blog.csdn.net/guyongqiangx/article/details/132343017
>
> 如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。

## 3. 查看 payload 信息

为了检查全量包和差分包到底有什么不同，我们需要查看和分析全量包和差分包的 payload 信息。

如果你知道如何查看和分析 payload 信息，请直接跳过本节阅读下一部分。



### 3.1 准备工作

为了演示这个实验，我在 Broadcom 的某个平台上编译了两个版本的升级包，唯一的差别是新版本在旧版本的基础上，新加入了一个名为 bootctl 的工具。



#### 1. 编译第 1 版代码

在设置了相关环境以后，使用以下方式编译第 1 版代码，并将 dist 发布的文件输出到 `out/dist-old` 目录中：

```bash
$ source build/envsetup.sh
$ lunch inuvik-userdebug
$ make dist DIST_DIR=out/dist-old
```



#### 2. 制作全量包

直接基于 dist 发布的 target files 文件(inuvik-target_files-eng.rocky.zip) 制作全量升级包。

```bash
$ ota_from_target_files out/dist-old/inuvik-target_files-eng.rocky.zip out/dist-old/update.zip
```



> 在你自己的平台上，target files 文件名字可能会有所不同，但遵循以下格式:
>
> `${platform}-target_files-eng.${user}.zip`



#### 3 修改代码

新代码唯一的修改是在旧版本的基础上，新加入了一个名为 bootctl 的工具，如下：

```bash
$ repo diff device/broadcom/common

project device/broadcom/common/
diff --git a/headed.mk b/headed.mk
index a4dc89df..fe1a8616 100644
--- a/headed.mk
+++ b/headed.mk
@@ -801,6 +801,7 @@ ifneq ($(TARGET_BUILD_PDK),true)
 ifeq ($(HW_AB_UPDATE_SUPPORT),y)
 PRODUCT_PACKAGES            += update_engine update_engine_client update_verifier
 PRODUCT_PACKAGES            += update_engine_sideload
+PRODUCT_PACKAGES            += bootctl
 PRODUCT_PACKAGES            += bootctrl.$(TARGET_BOARD_PLATFORM).recovery
 endif
 endif
```

你也可以根据自己的需要修改代码。



#### 4. 编译第 2 版代码

在设置了相关环境以后，使用以下方式编译第 2 版代码，并将 dist 发布的文件输出到新的 `out/dist-new-bootctl` 目录中：

```bash
$ source build/envsetup.sh
$ lunch inuvik-userdebug
$ make dist DIST_DIR=out/dist-new-bootctl
```



这里在第 1 版的基础上修改代码，并编译到同一个 out 输出目录下，唯一的差别是 dist 的输出目录不同，修改前是 `out/dist-old`，修改后为 `out/dist-new-bootctl`。



#### 5. 制作增量包

基于前面第 1 步和第 4 步两个版本 dist 发布的 target files 文件制作增量升级包:

```bash
$ ota_from_target_files -i out/dist-old/inuvik-target_files-eng.rocky.zip out/dist-new-bootctl/inuvik-target_files-eng.rocky.zip out/dist-old/update-delta.zip 
```



> 工具 `ota_from_target_files` 的详细用法请参考其帮助信息。



通过以上步骤，我们分别得到了全量(update.zip)和增量(update-delta.zip)两个升级包：

```bash
$ ls -lh out/dist-old/update*.zip
-rw-r--r-- 1 rocky users  92K Aug 16 21:58 out/dist-old/update-delta.zip
-rw-r--r-- 1 rocky users 585M Aug 16 00:51 out/dist-old/update.zip
```



将全量包 update.zip 解压缩到 update 目录，将增量包 update-delta.zip 解压缩到 update-delta 目录:

```bash
$ ls -lh out/dist-old/update*/
out/dist-old/update/:
total 585M
-rw-r--r-- 1 rocky users  239 Jan  1  2009 care_map.pb
drwxr-sr-x 3 rocky users 4.0K Aug 16 21:51 META-INF
-rw-r--r-- 1 rocky users 585M Jan  1  2009 payload.bin
-rw-r--r-- 1 rocky users  154 Jan  1  2009 payload_properties.txt

out/dist-old/update-delta/:
total 100K
-rw-r--r-- 1 rocky users  239 Jan  1  2009 care_map.pb
drwxr-sr-x 3 rocky users 4.0K Aug 16 21:59 META-INF
-rw-r--r-- 1 rocky users  88K Jan  1  2009 payload.bin
-rw-r--r-- 1 rocky users  150 Jan  1  2009 payload_properties.txt
```



从这里看到，全量包的 payload.bin 为 585M，增量包的 payload.bin 为 88K，差别相当大。



### 3.2 查看 payload.bin 信息

在[《Android OTA 相关工具(四) 查看 payload 文件信息》](https://blog.csdn.net/guyongqiangx/article/details/129228856)中，我介绍过如何使用工具 `payload_info.py` 查看 payload.bin 文件信息。

#### 1. 查看全量包 payload.bin 信息

使用 payload_info.py 工具的 `--stats` 选项查看汇总信息:

```
$ python3 system/update_engine/scripts/payload_info.py --stats out/dist-old/update/payload.bin 
Payload version:             2
Manifest length:             39774
Number of partitions:        6
  Number of "boot" ops:      36
  Number of "system" ops:    603
  Number of "vendor" ops:    39
  Number of "dtbo" ops:      1
  Number of "vbmeta" ops:    1
  Number of "vendor_boot" ops: 20
  Timestamp for boot:        
  Timestamp for system:      
  Timestamp for vendor:      
  Timestamp for dtbo:        
  Timestamp for vbmeta:      
  Timestamp for vendor_boot: 
  COW Size for boot:         0
  COW Size for system:       0
  COW Size for vendor:       0
  COW Size for dtbo:         0
  COW Size for vbmeta:       0
  COW Size for vendor_boot:  0
Block size:                  4096
Minor version:               0
Blocks read:                 356963
Blocks written:              356963
Seeks when writing:          0
```

我们对上面的输出进行处理，可以得到 6 个分区一共产生了 700 个 operation:

```bash
$ python3 system/update_engine/scripts/payload_info.py --stats out/dist-old/update/payload.bin | awk -F: '/Number of "\w+" ops/{ sum += $2 } END { print sum }'
700
```

> 说明:
>
> `awk -F: '/Number of "\w+" ops/{ sum += $2 } END { print sum }'` 
>
> 用于筛选打印满足格式 "`Number of "boot" ops:      36` "这样的行，并累加末尾的整数值。



使用 payload_info.py 工具的 `--list_ops` 选项可以查看所有详细的 install operation 信息，类似这样：

```bash
$ python3 system/update_engine/scripts/payload_info.py --list_ops out/dist-old/update/payload.bin 
Payload version:             2
...
Block size:                  4096
Minor version:               0

boot install operations:
  0: REPLACE_XZ
    Data offset: 0
    Data length: 720312
    Destination: 1 extent (512 blocks)
      (0,512)
  1: REPLACE_XZ
    Data offset: 720312
    Data length: 758296
    Destination: 1 extent (512 blocks)
      (512,512)
  2: REPLACE_XZ
    Data offset: 1478608
    Data length: 785828
    Destination: 1 extent (512 blocks)
      (1024,512)
  3: REPLACE_XZ
    Data offset: 2264436
    Data length: 763856
    Destination: 1 extent (512 blocks)
      (1536,512)
  4: REPLACE_XZ
  ...
```



我们这里进一步统计所有 install operations 的种类和数量：

```bash
$ python3 system/update_engine/scripts/payload_info.py --list_ops out/dist-old/update/payload.bin | awk -F: '/\s+[0-9]+: \w+/{print $2}' | sort | uniq -c 
     21  REPLACE
     42  REPLACE_BZ
    637  REPLACE_XZ
```

> 说明:
>
> `awk -F: '/\s+[0-9]+: \w+/{print $2}'` 用于筛选打印满足格式 "  2: REPLACE_XZ" 这样的行



可以看到，全量包的 700 个 install operations 里一共有 3 种操作，分别是:

- 21 个 REPLACE 操作
- 42 个 REPLACE_BZ 操作
- 637 个 REPLACE_XZ 操作



#### 2. 查看增量包 payload.bin 信息

操作命令和上一节的一样，使用 payload_info.py 工具的 `--stats` 选项查看汇总信息并统计总 operations 数量:

```bash
$ python3 system/update_engine/scripts/payload_info.py --stats out/dist-old/update-delta/payload.bin
Payload version:             2
Manifest length:             53586
Number of partitions:        6
  Number of "boot" ops:      67
  Number of "system" ops:    784
  Number of "vendor" ops:    42
  Number of "dtbo" ops:      4
  Number of "vbmeta" ops:    1
  Number of "vendor_boot" ops: 23
  Timestamp for boot:        
  Timestamp for system:      
  Timestamp for vendor:      
  Timestamp for dtbo:        
  Timestamp for vbmeta:      
  Timestamp for vendor_boot: 
  COW Size for boot:         0
  COW Size for system:       0
  COW Size for vendor:       0
  COW Size for dtbo:         0
  COW Size for vbmeta:       0
  COW Size for vendor_boot:  0
Block size:                  4096
Minor version:               7
Blocks read:                 1059875
Blocks written:              351848
Seeks when writing:          101
$
$ python3 system/update_engine/scripts/payload_info.py --stats out/dist-old/update-delta/payload.bin | awk -F: '/Number of "\w+" ops/{ sum += $2 } END { print sum }'
921
```



从这里看到，增量包中总的 operations 数量从全量包的 700 个增加到了 921 个。



统计所有 install operations 的种类和数量：

```bash
$ python3 system/update_engine/scripts/payload_info.py --list_ops out/dist-old/update-delta/payload.bin | awk -F: '/\s+[0-9]+: \w+/{print $2}' | sort | uniq -c 
     74  BROTLI_BSDIFF
      1  PUFFDIFF
     57  REPLACE_BZ
    743  SOURCE_COPY
     46  ZERO
```



可以看到，增量包的 921 个 installl operations 里一共有 5 种操作，分别是:

- 74 个 BROTLI_BSDIFF 操作
- 1 个 PUFFDIFF 操作
- 57 个 REPLACE_BZ 操作
- 743 个 SOURCE_COPY 操作
- 46 个 ZERO 操作



## 4. 全量和增量升级的差别

通过上一节中的编译和检查 payload 信息，在我们的实验环境中得到了下面的数据。



在旧版代码上新增加 bootctl 工具(比较小的修改)得到新版代码，编译新旧两版代码：

- 基于旧版代码制作了全量包，大小为 585M
- 基于新旧两版代码制作了差分包，大小为 92K

全量包和差分包大小差异非常明显，差分包竟然只有 92K，我都有点怀疑是不是搞错了。



在大小为 585M 的全量包中，一共包含了 700 个 install operations 操作，分别是：

- 21 个 REPLACE 操作
- 42 个 REPLACE_BZ 操作
- 637 个 REPLACE_XZ 操作

在大小为 92K 的增量包总，一共包含了 921 个 install operations 操作，分别是:

- 74 个 BROTLI_BSDIFF 操作
- 1 个 PUFFDIFF 操作
- 57 个 REPLACE_BZ 操作
- 743 个 SOURCE_COPY 操作
- 46 个 ZERO 操作



### 4.1 全量升级的操作

前面得到全量升级的 3 个操作：REPLACE, REPLACE_BZ 和 REPLACE_XZ。

所以在设备端接收到升级数据以后，这 3 个操作的动作基本一致：

1. 获取 payload 中 install operation 数据;
2. 如果是 REPLACE_BZ 和 REPLACE_XZ 操作，则在内存中将这些压缩后的数据解压缩还原得到原始数据;
3. 将还原得到的数据写入到目标分区;

所以，这里的操作主要是先解压缩(BZ 和 XZ 只是算法不一样)，然后通过一次 I/O 将数据写入到目标分区。



### 4.2 增量升级的操作

前面得到的增量升级的 5 个操作：BROTLI_BSDIFF, PUFFDIFF, REPLACE_BZ, SOURCE_COPY 和 ZERO。

在设备端接收到升级数据以后，根据是否需要读取源分区以及是否需要在内存中还原，这5 个操作又分成 4 类：

1. 需要读取源分区，需要在内存中还原

   - BROTLI_BSDIFF, PUFFDIFF

   这 2 个操作需要先读取源分区数据到内存，然后在内存中使用差分的反向操作将数据还原，整个差分还原操作比较消耗计算资源。还原后，再将还原后的数据写入到目标分区。

   涉及两次 I/O，和一次计算。

   

2. 需要读取源分区，不需要在内存中还原

   - SOURCE_COPY 

   SOURCE_COPY 操作是差分包中最常见的操作，就是将源分区的数据复制到目标分区。涉及两次 I/O，分别是从源分区读数据，和将数据写入目标分区。

   

3. 不需要读取源分区，但需要在内存中还原

   - REPLACE_BZ

   和全量升级时一样，只需要再内存中将这些压缩后的数据还原得到原始数据，然后经过一次 I/O 写入到目标分区。



4. 不需要读取源分区，不需要在内存中还原

   - ZERO

   ZERO 操作比较简单，就是直接将目标分区的相应位置设置为全 0 数据，需要一次 I/O 写入操作。



### 4.3 全量和差分升级的差别

对比全量和增量升级操作，可以发现增量升级多了一个从源分区读取数据的 I/O 操作，所以整体的 I/O 基本上多了一倍。



另外，根据个人经验，差分升级时，需要在内存中根据差分算法还原数据；而全量升级需要在内存中解压缩数据。在同等数据情况下，差分还原比解压缩对 CPU 计算资源消耗大，尤其当需要差分还原的数据量大时表现更为明显。



除了同样数量的 I/O 写入操作外，多了相同数量的 I/O 读取操作，再加上差分还原操作对 CPU 计算的消耗，整体上就导致了差分包升级时间比全量包更长。



## 5. 一个有趣的场景

在 VIP 讨论群，有个小伙伴分享了一个有趣的场景：

她说边下边升，升级过程中个别地方进度很慢，整个升级用时不到 20 分钟，但升级 4G 的 system 花了 17 分钟。

后来她解决了这个问题，说 I/O 没问题，就是差分升级时版本差异太大，设备配置低，只能跑这么快。

她的解决办法是，既然差异大，就把 system 整体升级。结果整升除了升级包大了不少外，升级速度优化明显。



我自己对这个问题的解释是：

> 1. 版本差异小，payload 中的操作集中在
> a. 很多 SOURCE_COPY 操作和
> b. 少量 BSDIFF 操作
>
> 因此，升级的时候:
>
> - 多数 SOURCE_COPY: 有很多从源分区的 read 和往目标分区的 write 操作
> - 少数 DIFF 操作: 从源分区 read，然后在内存中还原，再 write 到目标分区。
>
> 
>
> 2. 版本差异大，payload 中的操作集中在:
> a. 少数 SOURCE_COPY 操作和
> b. 大量的 BSDIFF 操作
>
> 因此，升级的时候:
>
> - 少数 SOURCE_COPY: 从源分区的 read 和往目标分区的 write 操作
> - 大量 DIFF 操作: 大量从源分区 read，然后在大量在内存中还原操作，再大量的 write 到目标分区。
>
> DIFF 操作对 CPU 和内存的要求较高，同时可见 read/write 的 io 并不会减少。
>
> 
>
> 而对于整包升级，不会涉及从源分区读，以及在内存中 DIFF 还原的操作。
> 所以，整包升级(全量)会比差分快不少。



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


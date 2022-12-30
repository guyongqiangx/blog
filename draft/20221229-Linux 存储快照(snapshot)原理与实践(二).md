# Linux 快照 (snapshot) 原理与实践(二) 快照功能实践

![linux_snapshot_2_title](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/linux_snapshot_2_title.png)

作者: 顾永强 (洛奇看世界)

博客: https://blog.csdn.net/guyongqiangx

> 本文为顾永强原创，转载请注明出处~
>
> 原文链接: https://blog.csdn.net/guyongqiangx/article/details/128496471

本文目录如下:

[TOC]

## 0. 概要

上一篇[《Linux 快照 (snapshot) 原理与实践(一)》]( https://blog.csdn.net/guyongqiangx/article/details/128494795)中简单介绍了快照的基本原理，并着重介绍了 Linux 下 snapshot 快照的实现，这应该是目前全网唯一一篇介绍 Linux 下 snapshot 模型的文章。

对一线工程师来说，只有理论是远远不够的，于是我又另外设计了本文这一组实验操作来验证 Linux 下 snapshot 快照模型的各种功能，以此加深对 snapshot 快照的理解。

具体的实验包括：

- snapshot-origin 目标的创建 (第 2 节)
- snapshot 目标的创建 (第 3 节)

- COW 模式 (第 4 节)
  - 第一次写入数据的验证 (第 4.1 节)
  - 第二次写入数据的验证 (第 4.2 节)
- ROW 模式 (第 5 节)
  - 第一次写入数据的验证 (第 5.1 节)
  - 第二次写入数据的验证 (第 5.2 节)
- snapshot-merge 目标的创建 (第 6 节)
- 合并 (merge) 操作中 COW 模式和 ROW 模式数据变化 (第 7 节)

由于这些实验一环套一环，所以建议从第一节开始，跟随我提供的各种操作命令在你的本地把这些实验重复一遍，并亲自去检查数据的变化，这样才能达到比较好的效果。

> 本文使用到了以下 Linux 的命令行工具:
>
> echo, tr, dd, md5, hexdump, xxd, losetup, dmsetup 
>
> 最后 3 个命令比较少见，但很重要：
>
> - xxd, 超好用的二进制工具，也可以很方便的用于文件的修改
> - losetup，用于 loop 设备的管理操作
> - dmsetup，用于 device mapper 虚拟设备的管理操作

## 1. 准备演示数据

为了方便演示，这里创建两个数据文件 data-base.img 和 data-cow.img 分别代表场景中的源卷和快照卷。

- 源卷 data-base.img，大小为 100M，全 0xFF，但在 0x0000 和 0x1000 (4K) 位置写入了特殊字符串方便后续操作。

- 快照卷 data-cow.img，大小为 50M，全 0x00

这里特意将源卷和快照卷的数据分别设置为 0xFF 和 0x00，所以如果有源卷中的数据进入到快照卷中，通过查看快照卷就能发现。



为了方便描述和引用，我对所有步骤进行了编号，如 step 1a, step 1b...

```bash
#
# step 1. 准备源卷数据 data-base.img
#
# step 1a. data-base.img, 100M 全 0xff, 100M = 1024 x 102400
$ tr '\000' '\377' < /dev/zero | dd of=data-base.img bs=1024 count=102400
$ hexdump -C data-base.img 
00000000  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 1b. 把 "Great China!" 写入到 0x0000 开始的地方
$ echo -n "Great China!" | xxd
00000000: 4772 6561 7420 4368 696e 6121            Great China!
$ echo -n "00000000: 4772 6561 7420 4368 696e 6121" | xxd -r - data-base.img 
$ hexdump -C data-base.img 
00000000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 1c. 把 "Rocky Can Do It!" 写入到 0x1000(4096) 开始的地方
$ echo -n 'Rocky Can Do It!' | xxd
00000000: 526f 636b 7920 4361 6e20 446f 2049 7421  Rocky Can Do It!
# 这里记得将偏移地址调整为 00001000 (4096), 如下
$ echo -n "00001000: 526f 636b 792c 2053 7570 6572 6d61 6e21" | xxd -r - data-base.img  
$ hexdump -C data-base.img 
00000000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  52 6f 63 6b 79 20 43 61  6e 20 44 6f 20 49 74 21  |Rocky Can Do It!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

#
# step 2. 准备快照卷数据 data-cow.img
#
# step 2a. data-cow.img, 50M 全 0, 50M = 1024 x 51200
$ dd if=/dev/zero of=data-cow.img bs=1024 count=51200
$ hexdump -C data-cow.img 
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
03200000

#
# step 3. 将源卷和快照卷数据文件挂载为 loop 设备
#
# step 3a. 计算 data-base.img 和 data-cow.img 的 md5 值
$ md5sum data-base.img data-cow.img
54bc2af511613f6405b27144c410fb94  data-base.img
25e317773f308e446cc84c503a6d1f85  data-cow.img

# step 3b. 将 data-base.img 和 data-cow 挂载为 loop 设备
$ sudo losetup -f data-base.img --show
/dev/loop3
$ sudo losetup -f data-cow.img --show
/dev/loop6

# step 3c. 再次查看数据文件和 loop 设备的 md5
$ sudo md5sum /dev/loop3 data-base.img /dev/loop6 data-cow.img 
54bc2af511613f6405b27144c410fb94  /dev/loop3
54bc2af511613f6405b27144c410fb94  data-base.img
25e317773f308e446cc84c503a6d1f85  /dev/loop6
25e317773f308e446cc84c503a6d1f85  data-cow.img
```

总结一下上面的所有操作：

1. 准备了 100M 的源卷文件 data-base.img，全 0xFF，但两个地方写入了特殊数据备用；
2. 准备了 50M 的快照卷文件 data-cow.img，全 0x00
3. 分别将 data-base.img 和 data-cow.img 挂载成 loop 设备 /dev/loop3 和 /dev/loop6;



源卷文件 data-base.img 中的特殊数据包括:

- 在 0x0000 开始的地方，写入字符串 "Great China!"

- 在 0x1000 开始的地方(偏移地址 4096)，写入字符串 "Rocky Can Do It!"



在步骤 step 3c 中，我们使用 md5 计算了两个数据文件及其对应 loop 设备的 md5 哈希值，来证明数据文件和对应的 loop 设备内容完全一样。由于存在数据和 loop 文件不同步的问题，后面不再单独计算 loop 设备的 md5 值，而仅计算数据文件的 md5 值。



> **数据文件和使用数据文件挂载的 loop 设备之间的同步问题**
>
> 我在实验中发现数据文件在某些情况下被改动后，如果不重新挂载，loop 设备不会反映这个修改。
>
> google 一搜，发现好多人都提出过这个同步问题，但并没有很好的解决办法。我还没研究过 loop 设备驱动，如果有大佬知道如何解决同步问题，烦请指定一二，感激不尽~



> 本文使用了 xxd 命令来转换和修改十六进制的内容，这是一个非常非常有用的技能。
>
> 关于如何高效使用 xxd 请参考我的文章: [《别找了，这个命令让你在字符串和十六进制间自由转换》](https://blog.csdn.net/guyongqiangx/article/details/118097756)

## 2. 创建 snapshot-origin 目标

```bash
#
# step 4. 基于源卷映射的 loop 设备创建 snapshot-origin 目标设备
#
# step 4a. 获取 /dev/loop3 和 /dev/loop6 的 sector 数量(每个 sector 为 512 字节)
$ sudo blockdev --getsz /dev/loop3 /dev/loop6
204800
102400

# step 4b. 基于 /dev/loop3 创建 snapshot-origin 设备 /dev/mapper/origin
$ sudo dmsetup create origin --table "0 204800 snapshot-origin /dev/loop3"
$ sudo dmsetup table origin
0 204800 snapshot-origin 7:4

# step 4c. 检查数据文件和虚拟设备的 md5
$ sudo md5sum data-base.img /dev/mapper/origin data-cow.img
54bc2af511613f6405b27144c410fb94  data-base.img
54bc2af511613f6405b27144c410fb94  /dev/mapper/origin
25e317773f308e446cc84c503a6d1f85  data-cow.img
```

从上面可见，虚拟设备 /dev/mapper/origin 和 data-base.img 的内容一样。

## 3. 创建 snapshot 目标

```bash
#
# step 5. 基于源卷和快照卷的 loop 设备创建 snapshot 目标
#         必须用 /dev/loop3 (对应 data-base.img)创建快照，不能使用 /dev/mapper/origin
# step 5a. 基于源卷和快照卷的 loop 设备创建 snapshot 目标设备
$ sudo dmsetup create snapshot --table "0 204800 snapshot /dev/loop3 /dev/loop6 P 8"            
$ sudo dmsetup table snapshot
0 204800 snapshot 7:3 7:6 P 8

# step 5b. 检查数据文件和虚拟设备的 md5
$ sudo md5sum data-base.img /dev/mapper/origin /dev/mapper/snapshot data-cow.img
54bc2af511613f6405b27144c410fb94  data-base.img
54bc2af511613f6405b27144c410fb94  /dev/mapper/origin
54bc2af511613f6405b27144c410fb94  /dev/mapper/snapshot
f0cb475bc4c1a84c31ba9c9053445daf  data-cow.img
```

> 特别解释一下创建 snapshot 设备时的 `--table` 参数:
>
> ```bash
> --table "0 204800 snapshot /dev/loop3 /dev/loop6 P 8"
> ```
>
> - "0 204800 snapshot", 分别指定映射的虚拟设备的起始位置(0 sector)和长度(204800 sector)，以及创建的虚拟设备的类型(snapshot)
> - "/dev/loop3", 基于设备  /dev/loop3 创建快照
> - "/dev/loop6", 快照的 cow 设备为 /dev/loop6
> - "P", 指定使用持久化的方式创建快照，所谓持久化，就是数据保存在外存里(即 cow 设备)
> - "8", 指定创建的 snapshot 的 chunk size 大小为 8，即每个 chunk 的实际大小为 512 x 8 = 4096，常用的参数为 8 或 16，表示每个 chunk 大小为 4K 或 8K
>
> 对于 device mapper 设备的基本单位是 sector，每一个 sector 为 512 字节。



仔细观察上面最后一步 step 5b 计算 data-cow.img 的 md5 值，其和前面 step 4c 的 md5 值相比，已经发生了变化。

![image-20221229184854465](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/md5-diff-for-snapshot-creation.png)

**图 1. 创建 snapshot 目标前后各设备 md5 值对比**



最主要是因为在创建 snapshot 时会往 cow 设备的头部写入 16 字节的 disk header 数据:

```bash
# step 5c. 创建 snapshot 目标后查看快照卷 data-cow.img 的内容
$ hexdump -C data-cow.img 
00000000  53 6e 41 70 01 00 00 00  01 00 00 00 08 00 00 00  |SnAp............|
00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
03200000
```

刚创建好 snapshot，没有任何 COW 或 ROW 操作，所以初始只往 cow 设备的起始位置写入 disk header 数据，余下数据还全是 0。



到此为止，我们创建的 snapshot 设备间的关系模型如下:

![image-20221229190315521](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/snapshot-device-relations.png)

**图 2. snapshot 实验的设备间关系**



## 4. 验证 COW 操作

验证 COW 操作需要在 origin 设备上进行。

根据在[《Linux 快照 (snapshot) 原理与实践(一)》]( https://blog.csdn.net/guyongqiangx/article/details/128494795)一文中的结论，对于 COW：

在新数据第一次写入到 origin 设备的某个存储位置时：

1. 先将源卷 data-base.img 中原有的内容读取出来，写到快照卷 data-cow.img 中;
2. 然后再将新数据写入到源卷 data-base.img 中。

操作 1 只在第一次写入数据时发生，下次针对这一位置的写操作直接将新数据写入到源卷中，不再执行写时复制 (COW) 操作。



### 4.1 第一次写数据

往 origin 设备 0x0000 开始的地方写入字符串 "Wonderful World!"，预期会产生 Copy-On-Write 操作:

- 将 0x0000 开始的 1 个 chunk 的旧数据(字符串"Great China!")写入到快照卷 data-cow.img (cow 设备)中，
- 新数据将直接写入到源卷 data-base.img 中 0x0000 开始的位置。



```bash
#
# step 6. 第一次往 orgin 设备的 0x0000 写数据触发 Copy-On-Write 操作
#
# step 6a. 把 "Wonderful World!" 写入到 origin 设备 0x0000 开始的地方
$ echo -n "Wonderful World!" | xxd
00000000: 576f 6e64 6572 6675 6c20 576f 726c 6421  Wonderful World!
$ echo -n "00000000: 576f 6e64 6572 6675 6c20 576f 726c 6421" | sudo  xxd -r - /dev/mapper/origin 

# step 6b. 查看 origin 设备的内容
$ sudo hexdump -C /dev/mapper/origin
00000000  57 6f 6e 64 65 72 66 75  6c 20 57 6f 72 6c 64 21  |Wonderful World!|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  52 6f 63 6b 79 20 43 61  6e 20 44 6f 20 49 74 21  |Rocky Can Do It!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 6c. 查看源卷 data-base.img 的内容
$ hexdump -C data-base.img
00000000  57 6f 6e 64 65 72 66 75  6c 20 57 6f 72 6c 64 21  |Wonderful World!|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  52 6f 63 6b 79 20 43 61  6e 20 44 6f 20 49 74 21  |Rocky Can Do It!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 6d. 第一次往 orgin 写入数据后查看 md5 值
$ sudo md5sum data-base.img /dev/mapper/origin /dev/mapper/snapshot data-cow.img 
feaabda81f5f031cba6ed20c1914dff1  data-base.img
feaabda81f5f031cba6ed20c1914dff1  /dev/mapper/origin
54bc2af511613f6405b27144c410fb94  /dev/mapper/snapshot
b7ce3102b418858009e5a3662d8a6a5a  data-cow.img
```

上面检查数据文件和虚拟设备的 md5 时，和写入数据前的值比较，data-base.img, /dev/mapper/origin 和 data-cow.img 已经发生了 变化。/dev/mapper/snapshot 因为没有操作，所以 md5 没有改变。

![image-20221229192802603](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/md5-diff-for-cow-1st-modification.png)

**图 3. 第一次往 origin 写入数据前后各中设备的 md5 值变化**



数据文件 data-base.img 和 /dev/mapper/origin 的变化很容理解，因为我们改变了源卷 0x0000 位置的内容，将原来的 "Great China!" 修改成了 "Wonderful World!"



对于COW 设备，到底数据如何变化的呢？我们不妨看下设备的数据:

```bash
# step 6e. 查看 data-cow.img 文件的数据
$ hexdump -C data-cow.img 
00000000  53 6e 41 70 01 00 00 00  01 00 00 00 08 00 00 00  |SnAp............|
00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001000  00 00 00 00 00 00 00 00  02 00 00 00 00 00 00 00  |................|
00001010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00002000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00002010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00003000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
03200000
```

在开始解释这个数据之前，回顾下在创建 snapshot 设备时指定的 chunksize 为 8，所以 1 个 chunk 的大小为 4K (0x1000)。

现在我来解释下这里的结果：

1. 区域: 0x00000000-0x0000fff，1 个 chunk，里面存放了包含以下信息的 disk header:

   - magic: `53 6e 41 70`, 对应于 "SnAp"；
   - valid: `01 00 00 00`，值为 1；
   - version: `01 00 00 00`，值为 1；
   - chunk_size: `08 00 00 00`，值为 8，对应于 512 x 8 = 4KB 的 chunk 数据

   disk header 之外的部分，全部填充为 0；

2. 区域: 0x00001000-0x00001fff, 1 个 chunk，现在里面只存放了 COW 的映射表，有一块进行了映射，所以内容比较简单，其余数据全部为 0。

3. 区域: 0x00002000-0x00002fff, 1 个 chunk，里面存放了来自 origin 设备第一个 chunk (0x0000~0x0fff)的内容。

综上，我们已经看到，第一次往源卷 origin 的 0x0000 位置写数据时，源卷 origin 中的旧数据保存到 cow 设备中的第 2 个 chunk (编号从 0 开始)，新数据直接写入到源卷 origin 中。



### 4.2 第二次写数据

往 origin 设备 0x0000 开始的地方再次写入字符串 "Go away, COVID-19!"，预期不会产生任何 Copy-On-Write 操作:

- 第二次新数据将直接写入到源卷 data-base.img 中。

```bash
#
# step 7. 第二次往 orgin 设备的 0x0000 写数据不会触发 Copy-On-Write 操作
#
# step 7a. 把 "Go away, COVID-19!" 写入到 origin 设备 0x0000 开始的地方
$ echo -n "Go away, COVID-19!" | xxd -c 18
00000000: 476f 2061 7761 792c 2043 4f56 4944 2d31 3921  Go away, COVID-19!
$ echo -n "00000000: 476f 2061 7761 792c 2043 4f56 4944 2d31 3921" | sudo xxd -r - /dev/mapper/origin

# step 7b. 查看设备 origin 的内容
$ sudo hexdump -C /dev/mapper/origin
00000000  47 6f 20 61 77 61 79 2c  20 43 4f 56 49 44 2d 31  |Go away, COVID-1|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  52 6f 63 6b 79 20 43 61  6e 20 44 6f 20 49 74 21  |Rocky Can Do It!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 7c. 查看源卷 data-base.img 的内容
$ hexdump -C data-base.img
00000000  47 6f 20 61 77 61 79 2c  20 43 4f 56 49 44 2d 31  |Go away, COVID-1|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  52 6f 63 6b 79 20 43 61  6e 20 44 6f 20 49 74 21  |Rocky Can Do It!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 7d. 第二次往 orgin 写入数据后查看 md5 值
$ sudo md5sum data-base.img /dev/mapper/origin /dev/mapper/snapshot data-cow.img
b566e218b059f01f4aac7ad185845fe8  data-base.img
b566e218b059f01f4aac7ad185845fe8  /dev/mapper/origin
54bc2af511613f6405b27144c410fb94  /dev/mapper/snapshot
b7ce3102b418858009e5a3662d8a6a5a  data-cow.img
```



对比第一次写入数据时的 md5 值，data-base.img 和 /dev/mapper/origin 的 md5 值变了，但快照卷 data-cow.img 并没有变化，所以确定第二次修改同一块数据并不会产生 COW 操作。

![image-20221229194958063](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/md5-diff-for-cow-2nd-modification.png)

**图 4. 第二次往 origin 写入数据前后各中设备的 md5 值变化**



也可以通过查看快照卷 data-cow.img 的内容来确认:

```bash
# step 7e. 查看 data-cow.img 文件的数据
$ hexdump -C data-cow.img 
00000000  53 6e 41 70 01 00 00 00  01 00 00 00 08 00 00 00  |SnAp............|
00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001000  00 00 00 00 00 00 00 00  02 00 00 00 00 00 00 00  |................|
00001010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00002000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00002010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00003000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
03200000
```



所以，第二次往 origin 设备的 0x0000 位置写数据时，新数据直接写入到源卷 data-base.img 中，而不会对快照卷 data-cow.img 有任何写入操作。

## 5. 验证 ROW 操作

验证 ROW 操作需要在 snapshot 设备上进行。

根据在[《Linux 快照 (snapshot) 原理与实践(一)》]( https://blog.csdn.net/guyongqiangx/article/details/128494795)一文中的结论，对于 ROW：

- 在新数据第一次写入到 snapshot 设备时，将会被重定向写入到快照卷 data-cow.img 中，源卷 data-base.img 不发生变化。

- 当同一位置的数据被再次改写时，系统会保持源卷 data-base.img 中的数据不变，继续重定向到快照卷 data-cow.img 中。



### 5.1 第一次写数据

往 snapshot 设备 0x1000 开始的地方写入字符串 "You Can Do It!!!"，预期会产生 Redirect-On-Write 操作:

- 将新数据 "You Can Do It!!!" 直接重定向写入到快照卷 data-cow.img 中；
-  源卷 data-base.img 中的数据不变

```bash
#
# step 8. 第一次往 snapshot 设备的 0x1000 (4KB) 写数据触发 Redirect-On-Write 操作
#
# step 8a. 把 "You Can Do It!!!" 写入到 snapshot 设备的 0x1000 开始的地方
$ echo -n 'You Can Do It!!!' | xxd
00000000: 596f 7520 4361 6e20 446f 2049 7421 2121  You Can Do It!!!

# 务必记得调整地址为 00001000
$ echo -n "00001000: 596f 7520 4361 6e20 446f 2049 7421 2121" | sudo xxd -r - /dev/mapper/snapshot

# step 8b. 查看设备 snapshot 的内容
$ sudo hexdump -C /dev/mapper/snapshot 
00000000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  59 6f 75 20 43 61 6e 20  44 6f 20 49 74 21 21 21  |You Can Do It!!!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 8c. 查看源卷 data-base.img 的内容
$ hexdump -C data-base.img 
00000000  47 6f 20 61 77 61 79 2c  20 43 4f 56 49 44 2d 31  |Go away, COVID-1|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  52 6f 63 6b 79 20 43 61  6e 20 44 6f 20 49 74 21  |Rocky Can Do It!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 8d. 第一次往 snapshot 写入数据后查看 md5 值
$ sudo md5sum data-base.img /dev/mapper/origin /dev/mapper/snapshot data-cow.img 
b566e218b059f01f4aac7ad185845fe8  data-base.img
b566e218b059f01f4aac7ad185845fe8  /dev/mapper/origin
27ceb83bde809ec2288a2cb3493cf033  /dev/mapper/snapshot
effae9af0f5a4aa453af2185b741e300  data-cow.img
```

这一次，snapshot 设备中的数据发生了改变，快照卷 data-cow.img 也发生了改变，但源卷 data-base.img 中没有变化，如下图：

![image-20221229200537014](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/md5-diff-for-row-1st-modification.png)

**图 5. 第一次往 snapshot 设备写入数据前后的 md5 变化**



再来看看快照卷 data-cow.img 中的内容:

```bash
# step 8e. 查看 data-cow.img 文件的数据
$ hexdump -C data-cow.img 
00000000  53 6e 41 70 01 00 00 00  01 00 00 00 08 00 00 00  |SnAp............|
00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001000  00 00 00 00 00 00 00 00  02 00 00 00 00 00 00 00  |................|
00001010  01 00 00 00 00 00 00 00  03 00 00 00 00 00 00 00  |................|
00001020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00002000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00002010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00003000  59 6f 75 20 43 61 6e 20  44 6f 20 49 74 21 21 21  |You Can Do It!!!|
00003010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00004000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
03200000
```



可见往 snapshot 设备中写入的数据 "You Can Do It!!!" 出现在了快照卷 data-cow.img 中。



我再来解释下快照卷 data-cow.img 内容：

1. 区域: 0x00000000-0x0000fff，1 个 chunk，存放了 16 字节的 disk header，其余全部填充为 0；

   > ```bash
   > # 16 字节 disk header
   > 00000000  53 6e 41 70 01 00 00 00  01 00 00 00 08 00 00 00  |SnAp............|
   > 
   > # 剩余部分全部填充为 0
   > 00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
   > *
   > ```

2. 区域: 0x00001000-0x00001fff, 1 个 chunk，现在里面不仅存放了验证 COW 操作时生成的 COW 映射表，也存放了这里进行 ROW 验证生成的 ROW 的映射表，其余数据全部为 0。

   > ```bash
   > # COW 映射表
   > 00001000  00 00 00 00 00 00 00 00  02 00 00 00 00 00 00 00  |................|
   > 
   > # ROW 映射表
   > 00001010  01 00 00 00 00 00 00 00  03 00 00 00 00 00 00 00  |................|
   > 
   > # 剩余部分全部填充为 0
   > 00001020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
   > *
   > ```

3. 区域: 0x00002000-0x00002fff, 1 个 chunk，存放了验证 COW 操作第一次写数据的内容。

   > ```bash
   > 00002000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
   > 00002010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
   > *
   > ```

4. 区域: 0x00003000-0x00003fff, 1 个 chunk，存放这里写入重定向的数据。

   > ```bash
   > 00003000  59 6f 75 20 43 61 6e 20  44 6f 20 49 74 21 21 21  |You Can Do It!!!|
   > 00003010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
   > *
   > ```



### 5.2 第二次写数据

再次改写 snapshot 设备 0x1000 开始的数据，写入字符串 "Everyone Can Do!":

- 新数据 "Everyone Can Do!" 也将重定向到快照卷 data-cow.img 中。
- 源卷 data-base.img 中的数据不变
- 留意下上一次重定向的数据 "You Can Do It!!!" 是否会被保留？

```bash
#
# step 9. 第二次往 snapshot 设备的 0x1000 (4KB) 写数据触发 Redirect-On-Write 操作
#
# step 9a. 把 "Everyone Can Do!" 写入到 snapshot 设备 0x1000 开始的地方
$ echo -n 'Everyone Can Do!' | xxd
00000000: 4576 6572 796f 6e65 2043 616e 2044 6f21  Everyone Can Do!

# 这里记得调整地址为 00001000
$ echo -n '00001000: 4576 6572 796f 6e65 2043 616e 2044 6f21' | sudo xxd -r - /dev/mapper/snapshot 

# step 9b. 查看设备 snapshot 的内容
$ sudo hexdump -C /dev/mapper/snapshot 
00000000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  45 76 65 72 79 6f 6e 65  20 43 61 6e 20 44 6f 21  |Everyone Can Do!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 9c. 查看源卷 data-base.img 的内容
$ hexdump -C data-base.img 
00000000  47 6f 20 61 77 61 79 2c  20 43 4f 56 49 44 2d 31  |Go away, COVID-1|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  52 6f 63 6b 79 20 43 61  6e 20 44 6f 20 49 74 21  |Rocky Can Do It!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 9d. 第二次往 snapshot 写入数据后查看 md5 值
$ sudo md5sum data-base.img /dev/mapper/origin /dev/mapper/snapshot data-cow.img
b566e218b059f01f4aac7ad185845fe8  data-base.img
b566e218b059f01f4aac7ad185845fe8  /dev/mapper/origin
5e974c6c78213a70a77d4757cb0b8205  /dev/mapper/snapshot
7766259753fa0a3a75798e4a6416e2bc  data-cow.img
```

以下是 md5 值对比结果:

![image-20221229201818801](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/md5-diff-for-row-2nd-modification.png)

**图 6. 第二次往 snapshot 设备写入数据前后的 md5 变化**

从上面的内容可见，snapshot 的内容已经发生了变化。因为写入重定向的原因，所以新数据也写入到快照卷 data-cow.img 中了。源卷 data-base.img 的内容并没有变化。



让我们来看看快照卷 data-cow.img 的内容:

```bash
# step 9e. 查看 data-cow.img 文件的数据
$ hexdump -C data-cow.img 
00000000  53 6e 41 70 01 00 00 00  01 00 00 00 08 00 00 00  |SnAp............|
00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001000  00 00 00 00 00 00 00 00  02 00 00 00 00 00 00 00  |................|
00001010  01 00 00 00 00 00 00 00  03 00 00 00 00 00 00 00  |................|
00001020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00002000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00002010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00003000  45 76 65 72 79 6f 6e 65  20 43 61 6e 20 44 6f 21  |Everyone Can Do!|
00003010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00004000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
03200000
```

从这里可以看到，快照卷 data-cow.img 中上次 (step 8e) 写入重定向的 "You Can Do It!!!" 已经被新数据 "Everyone Can Do!" 替换了。



## 6. 创建 snapshot-merge 目标

根据在[《Linux 快照 (snapshot) 原理与实践(一)》]( https://blog.csdn.net/guyongqiangx/article/details/128494795)一文中的结论，snapshot-merge 的作用就是将快照卷 data-cow.img 中的数据合并 (merge) 回源卷 data-base.img:

- 对 COW 操作来说，源卷 data-base.img 保存了最新数据，合并 (merge) 操作会将源卷 data-base.img 回滚到快照时间点的数据。

- 对 ROW 操作来说，源卷 data-base.img 保存的是快照时间点的数据，合并 (merge) 操作会将源卷 data-base.img 更新成最新的数据。



snapshot-merge 的功能要求其和另外两个目标 snapshot-origin 和 snapshot 存在关联：

- snapshot-merge 和 snapshot 使用同样的参数，只在持久快照 (persistent snapshot)下有效
- snapshot-merge 承担 snapshot-origin 的角色，如果源卷还存在 snapshot-origin 设备，则不得加载



平时可以直接通过以下操作创建一个 snapshot-merge 目标设备 merge:

```bash
# step 10. 直接基于源卷和快照卷的 loop 设备创建一个新的 snapshot-merge 目标设备
$ sudo dmsetup create merge --table '0 204800 snapshot-merge /dev/loop3 /dev/loop6 P 8'
```



但是在这里，如图2 所示，源卷 data-base.img 目前还同两个设备相关：

- 一个 snapshot-origin 设备 origin，
- 还有一个 snapshot 设备 snapshot。

所以不能直接使用上面 step 10 的命令创建 snapshot-merge 目标设备。



在创建 snapshot-merge 目标的设备前，先停止源卷 data-base.img 映射的 snapshot-origin 设备。

由于 snapshot-merge 承担 snapshot-origin 的角色，所以可以直接考虑像下面来创建 snapshot-merge 设备:

```bash
#
# step 11. 基于源卷和快照卷的 loop 设备创建 snapshot-merge 目标设备
#
# step 11a. 暂停源卷 data-base.img 绑定的 snapshot-origin 目标设备 origin
$ sudo dmsetup suspend origin
# step 11b. 移除源卷 data-base.img 映射的 snapshot 目标设备 origin
$ sudo dmsetup remove snapshot
# step 11c. 使用 reload 操作将原来的 snapshot-origin 目标改变成 snapshot-merge 目标
$ sudo dmsetup reload origin --table '0 204800 snapshot-merge /dev/loop3 /dev/loop6 P 8'
# step 11d. 恢复 origin 设备的运行，但此时 origin 已经是 snapshot-merge 目标设备了
$ sudo dmsetup resume origin
```



创建 snapshot-merge 设备经历了以下这几个步骤：

1. 暂停 origin 设备；
2. 取消 snapshot 映射；
3. 重新使用 snapshot 的参数，将原来的 origin 设备从 snapshot-origin 目标更改为 snapshot-merge 目标；
4. 恢复 origin 设备运行，由于已经是 snapshot-merge 目标设备，所以内部开始执行 merge 操作；



## 7. 验证 merge 操作

snapshot-merge 目标的设备 origin 开始工作以后，该如何确认合并 (merge) 操作执行完成了呢？

答案是通过检查 snapshot-merge 设备的状态来判断。



对于我们这里的演示，就是检查当前 snapshot-merge 设备，即 origin 的 status:

```bash
# step 12a. 查看 origin 设备的状态
$ sudo dmsetup status origin
0 204800 snapshot-merge 16/102400 16
```

这里 `dmsetup status` 显示的状态的后三项，是这样的：

```bash
# <sectors_allocated>/<total_sectors> <metadata_sectors>
  16                 /102400          16
```

`<sectors_allocated>` 和 `<total_sectors>` 都包含数据和元数据。



在合并过程中，分配的扇区数量会越来越少。

当保存数据的扇区数为零时合并完成，换句话说 `<sectors_allocated> == <metadata_sectors>`。



这里 step 12 返回的是快照卷设备中的状态，对于 50M 的快照卷 data-cow.img：

- `<total_sectors>` 表明整个设备总共为 102400 sector，因为 50M = 512 x 102400
- `<sectors_allocated>` 表明当前分配了 16 sector
- 前面分析过 disk header 和映射表各占用了 1 chunk，总计 2 x chunk = 16 sector，这就是为什么说元数据 (metadata) 有 16 个 sector 的原因

所以，当前快照的状态信息表明：

设备总共分配了 16 sector，而元数据刚好占用完了这 16 sector，之前存放修改数据的空间都被释放了，也就意味着合并 (merge) 完成了。

因为我们这里演示时只修改了两个 chunk，也就是两个 4K 空间。而完成两个 4K 的合并写入，基本上就是瞬间的事情。所以当我这里重新恢复 origin 以后，再立即查看快照状态就已经显示合并完成了。



我们再看下合并(merge)完成以后源卷 data-base.img 和快照卷 data-cow.img 中的数据。

先看源卷 data-base.img:

```bash
# step 12b. 查看设备 origin 的内容
$ sudo hexdump -C /dev/mapper/origin 
00000000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  45 76 65 72 79 6f 6e 65  20 43 61 6e 20 44 6f 21  |Everyone Can Do!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000

# step 12c. 查看源卷 data-base.img 的内容
$ hexdump -C data-base.img 
00000000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00000010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  45 76 65 72 79 6f 6e 65  20 43 61 6e 20 44 6f 21  |Everyone Can Do!|
00001010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
06400000
```

从这里可以看到，COW 操作和 ROW 操作存储在快照卷中的数据都已经合并回源卷中了。

- 对 COW 操作的数据，源卷 data-base.img 中区域 0x0000 - 0x0fff (1 个 chunk) 已经用快照卷 data-cow.img 中的旧数据还原了。

- 对 ROW 操作的数据，源卷 data-base.img 中区域 0x1000 - 0x1fff (1 个 chunk) 已经用快照卷 data-cow.img 中的新数据更新了。



再看快照卷 data-cow.img:

```bash
# step 12d. 查看 data-cow.img 文件的数据
$ hexdump -C data-cow.img 
00000000  53 6e 41 70 01 00 00 00  01 00 00 00 08 00 00 00  |SnAp............|
00000010  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00002000  47 72 65 61 74 20 43 68  69 6e 61 21 ff ff ff ff  |Great China!....|
00002010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00003000  45 76 65 72 79 6f 6e 65  20 43 61 6e 20 44 6f 21  |Everyone Can Do!|
00003010  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00004000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
03200000
```

恍然一看，跟之前差不多，但又总觉得少了点什么。

下面是合并前后的数据对比图:

![image-20221229174920123](images-20221229-Linux 存储快照(snapshot)原理与实践(二)/md5-diff-for-merge.png)

对比之下，很明显，合并后映射表区域  (0x1000-0x1fff) 的数据被清零 0 了，换言之所有映射都失效了。

> 思考:
>
> **为啥合并后快照卷 data-cow.img 中的数据 (0x2000-0x2fff 以及 0x3000-0x3fff) 没被清空？**



在合并完成以后，可以移除 snapshot-merge 映射的目标 orgin:

```bash
# step 13. 移除 origin 设备
$ sudo dmsetup remove origin
```



或者根据需要，也可以将 origin 设备从 snapshot-merge 还原回 snapshot-origin 目标:

```bash
#
# step 14. 将 origin 设备从 snapshot-merge 目标更改为 snapshot-origin 目标
#
# step 14a. 暂停 origin 设备
$ sudo dmsetup suspend origin
# step 14b. 偷天换日，使用 reload 方式将 origin 更改为 snapshot-origin 目标设备
$ sudo dmsetup reload origin --table "0 204800 snapshot-origin /dev/loop3"
# step 14c. 恢复 origin 设备的运行
$ sudo dmsetup resume origin
```



至此，我们关于 snapshot 原理验证的实验全部都完成了。

至此，《Linux 快照 (snapshot) 原理与实践》的原理介绍和实践操作两篇都完成了。

## 8. 后记

《Linux 快照 (snapshot) 原理与实践》的两篇文章从筹划到最终成稿，前后花了接近一个月，中间改了很多次稿，调整了很多次实验的内容。

即使 Linux snapshot 快照原理以及实验都讲了，但文字的表达能力终究有限，我发现仍然有不少问题还没有交代清楚，比如:

- Linux 下快照设备的各种行为关系，
- COW 设备的细节，
- 对驱动代码进行分析，
- 如何对快照设备扩容，
- 如何对快照设备进行调试等。

只不过写作本文的初衷已经达成，所以对 Linux 下快照设备的介绍算是告一段落，至于是否还要继续深入完善本系列，后续待定。



不过最近分析发现 linux 下的 device mapper 真是个宝藏，所以后面真可以考虑继续挖掘。



如果大家有任何疑问，又或者发现描述有错误的地方，欢迎加我微信讨论，请在公众号("洛奇看世界")后台回复 "wx" 获取二维码。

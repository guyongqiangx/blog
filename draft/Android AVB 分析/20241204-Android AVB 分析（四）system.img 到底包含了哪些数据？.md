# 20241204-system.img 到底包含了哪些数据？

## 1. 前言

在上一篇[《Android AVB 分析（三）boot.img 到底包含了哪些数据？》](https://blog.csdn.net/guyongqiangx/article/details/144479713)中分析了使用 `add_hash_footer` 操作的 boot.img 镜像的格式。

本篇进一步分析 `add_hashtree_footer` 操作的 system.img 镜像的格式。



因此，system.img 都包含哪些数据，你有尝试亲自去分析 system.img 吗？

一个 system 分区的镜像，为了满足 AVB 需要，需要进行如何处理？



本文以实际操作的形式，带你查看 system.img 镜像，包括 avbtool 的多个操作，以及如何如何手动解析 AVB Footer，如何使用 shell 命令验证带有 salt 的镜像 hash 值。



如果觉得实际操作比较返回，请转到第 4 节，查看 avbtool 命令，以及 system.img 的格式总结。

## 2. 环境

具体的环境搭建，请参考[《Android AVB 分析（三）boot.img 到底包含了哪些数据？》](https://blog.csdn.net/guyongqiangx/article/details/144479713)第二节中关于环境搭建的内容。

这里就基于其生成的 system.img 进行分析分析。



## 3. 操作

### 1. 使用 avbtool 处理 system.img

在编译 log 文件 `make-dist-20241202-avbtool.log` 中查看 avbtool 用于 system.img 的操作，再回到完整的 log 文件中查看，原始的对 system.img 操作的 log 是这样的：

```bash
2024-12-02 14:54:27 - common.py - INFO    :   Running: "/local/public/users/rocky/android-13.0.0_r41/out/host/linux-x86/bin/avbtool add_hashtree_footer --partition_size 886812672 --partition_name system --image /local/public/users/rocky/android-13.0.0_r41/out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img --salt 6902f6b436dd8f08a2ecd512d4576a03325e14db8e6b1bb72b68d22f20a6a6d3 --hash_algorithm sha256 --prop com.android.build.system.os_version:13 --prop com.android.build.system.fingerprint:Android/aosp_panther/panther:13/TQ2A.230405.003.E1/rocky12021421:userdebug/test-keys --prop com.android.build.system.security_patch:2023-04-05"
```

> 特别注意：这里的 avbtool 处理的是 target 包目录 `aosp_panther-target_files-eng.rocky/IMAGES` 下的 `system.img`。
>
> 对于 `out/target/product/panther/system.img`，其处理也类似。



根据 log 中的信息，看起来是对 `aosp_panther-target_files-eng.rocky/IMAGES` 文件夹下面的 system.img 进行处理。

为了显示方便，整理一下具体的处理命令，如下：

```bash
avbtool add_hashtree_footer \
	--partition_size 886812672 \
	--partition_name system \
	--image aosp_panther-target_files-eng.rocky/IMAGES/system.img \
	--salt 6902f6b436dd8f08a2ecd512d4576a03325e14db8e6b1bb72b68d22f20a6a6d3 \
	--hash_algorithm sha256 \
	--prop com.android.build.system.os_version:13 \
	--prop com.android.build.system.fingerprint:Android/aosp_panther/panther:13/TQ2A.230405.003.E1/rocky12021421:userdebug/test-keys \
	--prop com.android.build.system.security_patch:2023-04-05
```



简单来说，就是对 system.img 执行 `add_hashtree_footer` 操作。

> 注意：这里并没有传入 `--key` 参数，所以不会对 `system.img` 进行签名。如果希望进行签名，可以参考 `boot.img` 的命令，传入 `--key` (指定 key文件)和 `--algorithm`(指定签名算法)，例如：
>
> ```bash
> avbtool add_hashtree_footer \
> 	--partition_size 886812672 \
> 	--partition_name system \
> 	--image aosp_panther-target_files-eng.rocky/IMAGES/system.img \
> 	--salt 6902f6b436dd8f08a2ecd512d4576a03325e14db8e6b1bb72b68d22f20a6a6d3 \
> 	--hash_algorithm sha256 \
> 	--key external/avb/test/data/testkey_rsa2048.pem \
> 	--algorithm SHA256_RSA2048 \
> 	--prop com.android.build.system.os_version:13 \
> 	--prop com.android.build.system.fingerprint:Android/aosp_panther/panther:13/TQ2A.230405.003.E1/rocky12021421:userdebug/test-keys \
> 	--prop com.android.build.system.security_patch:2023-04-05	
> ```
>
> 



### 2. 使用 avbtool 查看 system.img

我们使用 avbtool 工具的 `info_image` 查看下生成的 boot.img 文件：

```bash
$ avbtool info_image --image out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img
Footer version:           1.0
Image size:               886812672 bytes
Original image size:      872734720 bytes
VBMeta offset:            886571008
VBMeta size:              832 bytes
--
Minimum libavb version:   1.0
Header Block:             256 bytes
Authentication Block:     0 bytes
Auxiliary Block:          576 bytes
Algorithm:                NONE
Rollback Index:           0
Flags:                    0
Rollback Index Location:  0
Release String:           'avbtool 1.2.0'
Descriptors:
    Hashtree descriptor:
      Version of dm-verity:  1
      Image Size:            872734720 bytes
      Tree Offset:           872734720
      Tree Size:             6881280 bytes
      Data Block Size:       4096 bytes
      Hash Block Size:       4096 bytes
      FEC num roots:         2
      FEC offset:            879616000
      FEC size:              6955008 bytes
      Hash Algorithm:        sha256
      Partition Name:        system
      Salt:                  6902f6b436dd8f08a2ecd512d4576a03325e14db8e6b1bb72b68d22f20a6a6d3
      Root Digest:           e2b0749496127b3b0dd589ea54bf6ccb113fa05d587b1e361a55d3bc0ea6f068
      Flags:                 0
    Prop: com.android.build.system.os_version -> '13'
    Prop: com.android.build.system.fingerprint -> 'Android/aosp_panther/panther:13/TQ2A.230405.003.E1/rocky12021421:userdebug/test-keys'
    Prop: com.android.build.system.security_patch -> '2023-04-05'
```



主要部分和上一篇[《AVB 数据实战之 boot.img》]()的基本一样，但又略有不同，多了 Hashtree 和 FEC 相关的信息，如下：

![](images-20241204-Android AVB 分析（四）system.img 到底包含了哪些数据？/system-image-info.png)

这里的数据重点如下：

- AVB Footer 数据

  - AVB Footer 版本: `1.0`

  - 处理后的 system.img 镜像大小为 886812672 字节( 4K 粒度对齐)，给 avbtool 传入的参数指定了这个值。

  - 原始的不带任何额外数据的 system.img 镜像为 872734720 字节 (可以通过 `avbtool erase_footer` 移除额外的 AVB 数据来还原原始的镜像)

  - AVB 的元数据 VBMeta 大小为 832 字节，位于偏移量为 886571008 的位置(FEC 数据结束的地方)

- VBMeta 数据

  - 头部各块数据大小(Header, Authentication, Auxiliary 等数据)

  - Authentication Block 大小为 0，所以不带有签名数据(在 vbmeta_system.img 中单独处理)

  - 回滚 Index 值：0

  - 包含了 1 个哈希树(hashtree)描述符
    - hashtree 位置: 872734720，大小: 6881280
    - FEC 位置: 879616000, 大小: 6955008
    - Salt 值和 Root 哈希值

  - 包含了 3 个 Prop 属性



### 3. 使用 avbtool 添加的额外数据

当使用 avbtool 对原来的 `system.img` 执行 `add_hashtree_footer` 操作时到底添加了哪些数据呢？

1. 写入原始未经处理的镜像 system.img，共 872734720 字节(0x3404E000)
2. 计算原始镜像的 hashtree，并从原始数据结束的地方开始写入 (0x3404E000)，大小为 6881280 字节(即 0x69000)
3. 计算原始镜像和 hashtree 数据的 FEC 数据，用于纠错。FEC 数据从 hashtree 结束的地方(879616000=872734720+6881280，即 0x346DE000)开始写入，大小 6955008字节(0x6A2000)。
4. 将原始镜像 system.img 计算得到的 VBMeta 元数据存放在 FEC 数据结束的地方(886571008=879616000+6955008，即 0x34D80000)，大小为 832 字节(占用 4K Block)
5. 将新镜像填充到指定大小 886812672 字节(通过参数指定:`--partition_size 886812672`)
6. 在新镜像的最后 4K block 的最后 64 字节写入 AVB Footer 内容



> 注：所有操作都按照 4K 页面进行
>
> 例如：
>
> 1. 原始镜像大小为 4K block 整数倍，结束的地方 4K 对齐
> 2. hashtree 数据大小为 4K  block 整数倍
> 3. FEC 数据大小为 4K block 整数倍
> 4. VBMeta 存放在 4K 起始位置，并且填充到 4K 对齐(这里实际 832 字节，最终占用 4K)
> 5. 如果需要填充，则填充到指定大小 - 4K，因为最后 4K 放 AVB Footer
> 6. 最后 1 个 4K 结束位置的 64 字节写入 AVB Footer



所以，最终的 system.img 格式如下：

```bash
system.img layout (4K aligned):
+--------------------------------+ 0x0
|      Original System Image     |
|      (system partition)        |
+--------------------------------+ original_image_size
|                                |
|      Hash Tree                 |
|      (Merkle Tree)             |
|                                |
+--------------------------------+ tree_offset + tree_size
|                                |
|      FEC Data                  | (Optional)
|                                |
+--------------------------------+ fec_offset + fec_size
|      AVB VBMeta                |
|      - Header                  |
|      - Authentication Block    |
|      - Hashtree Descriptor     |
|      - Properties              |
+--------------------------------+ vbmeta_offset + vbmeta_size
|                                |
|      Padding                   |
|                                |
+--------------------------------+  <-- Last 4KB offset
|      (4KB)                     |
|      AVB Footer                |  <-- Last 64 bytes
+--------------------------------+  <-- partition_size
```



总体来说，使用 `add_hashtree_footer` 操作的镜像处理后包含以下 5 块数据：

- 原始分区镜像
- hashtree 数据，位置从原始镜像结束开始
- FEC 数据，位置从 hashtree 数据结束开始
- AVB 元数据 (VBMeta)，位置从 FEC 数据结束开始
- AVB Footer 数据，最后一个 4K block 的最后 64 个字节



### 4. 查验 system.img 中额外添加的数据

为了证实上一节的结论，即：使用 `add_hashtree_footer` 操作的镜像处理后包含以下 5 块数据：

- 原始分区镜像
- hashtree 数据，位置从原始镜像结束开始
- FEC 数据，位置从 hashtree 数据结束开始
- AVB 元数据 (VBMeta)，位置从 FEC 数据结束开始
- AVB Footer 数据，最后一个 4K block 的最后 64 个字节

#### 查看 AVB Footer

整个 64M 镜像最后 4K 的起始地址为 0x34DB A000 (886808576=886812672-4096)，这里查看从 0x34DB A000 开始的 4096 字节：

```
$ hexdump -C -s 0x34DBA000 -n 4096 out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img
34dba000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
34dbafc0  41 56 42 66 00 00 00 01  00 00 00 00 00 00 00 00  |AVBf............|
34dbafd0  34 04 e0 00 00 00 00 00  34 d8 00 00 00 00 00 00  |4.......4.......|
34dbafe0  00 00 03 40 00 00 00 00  00 00 00 00 00 00 00 00  |...@............|
34dbaff0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
34dbb000
```

可以看到，这里最后 64 直接为 AVB Footer。

可以根据文件 `external/avb/libavb/avb_footer.h` 中定义的 AVB Footer 来手动解析一下：

```c
/* Magic for the footer. */
#define AVB_FOOTER_MAGIC "AVBf"
#define AVB_FOOTER_MAGIC_LEN 4

/* Size of the footer. */
#define AVB_FOOTER_SIZE 64

/* The current footer version used - keep in sync with avbtool. */
#define AVB_FOOTER_VERSION_MAJOR 1
#define AVB_FOOTER_VERSION_MINOR 0

/* The struct used as a footer used on partitions, used to find the
 * AvbVBMetaImageHeader struct. This struct is always stored at the
 * end of a partition.
 */
typedef struct AvbFooter {
  /*   0: Four bytes equal to "AVBf" (AVB_FOOTER_MAGIC). */
  uint8_t magic[AVB_FOOTER_MAGIC_LEN];
  /*   4: The major version of the footer struct. */
  uint32_t version_major;
  /*   8: The minor version of the footer struct. */
  uint32_t version_minor;

  /*  12: The original size of the image on the partition. */
  uint64_t original_image_size;

  /*  20: The offset of the |AvbVBMetaImageHeader| struct. */
  uint64_t vbmeta_offset;

  /*  28: The size of the vbmeta block (header + auth + aux blocks). */
  uint64_t vbmeta_size;

  /*  36: Padding to ensure struct is size AVB_FOOTER_SIZE bytes. This
   * must be set to zeroes.
   */
  uint8_t reserved[28];
} AVB_ATTR_PACKED AvbFooter;
```



解析结果：

```
              magic( 4): 41 56 42 66              -> magic: "AVBf"
      version_major( 4): 00 00 00 01              -> major: 1
      version_minor( 4): 00 00 00 00              -> minor: 0
original_image_size( 8): 00 00 00 00  34 04 e0 00 -> 0x00000000 3404e000 = 872734720
      vbmeta_offset( 8): 00 00 00 00  34 d8 00 00 -> 0x00000000 34d80000 = 886571008
        vbmeta_size( 8): 00 00 00 00  00 00 03 40 -> 0x00000000 00000680 = 832
```

所以，通过最后 64 字节的 AVB Footer 解析得到以下内容：

```
Footer version:           1.0
Image size:               886812672 bytes
Original image size:      872734720 bytes
VBMeta offset:            886571008
VBMeta size:              832 bytes
```



#### 查看 hashtree 数据

从前面可以看到，原始镜像大小为 872734720 字节，hashtree 数据紧挨着这个位置存放，所以偏移位置 0x3404E000 开始就是 hashtree 数据了：

```
$ hexdump -C -s 0x3404E000 -n 128 out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img
3404e000  c0 e9 8a bf 42 81 e0 b3  c4 00 77 91 9b ad 59 df  |....B.....w...Y.|
3404e010  71 93 89 01 9b 9f f0 85  58 68 08 46 cb 6a f0 59  |q.......Xh.F.j.Y|
3404e020  14 bf ba ec e2 08 0d 74  a0 34 a3 da 98 22 59 dd  |.......t.4..."Y.|
3404e030  14 bc 8b ea 80 44 99 ce  02 a0 71 1c 15 77 83 43  |.....D....q..w.C|
3404e040  e8 79 a6 b1 b9 2e 58 4c  0d 08 9e 3f 25 39 b2 14  |.y....XL...?%9..|
3404e050  a4 bd 62 4f c5 47 b9 45  4b 10 a1 05 12 f2 08 6c  |..bO.G.EK......l|
3404e060  8b 23 76 09 53 72 09 25  9d 90 cd b8 98 9a 10 39  |.#v.Sr.%.......9|
3404e070  9c d1 7d 82 11 26 64 63  ae 15 2d 4e bd 10 1a 39  |..}..&dc..-N...9|
3404e080
```



实际上，对于 872734720 字节的镜像数据，在生成 hashtree 时需要 3 个层级(level 0, level 1 和 level 2)的哈希计算。

但在保存哈希计算结果时，先保存顶层块 level 2 的哈希；最后才是 level 0 层级的 hash。

经过计算，level 0 在 hashtree 内部的哈希偏移为 61440，在整个镜像中的偏移为 872734720+61440。



下面我们通过手动计算第 1 块数据的哈希，并在处理好的 system.img 镜像中找到对应的 hash 结果数据。

由于引入了 Salt，所以第一块数据的 hash 值应该基于 32 字节的 Salt 数据，以及第一块 4K 数据进行计算。

我们试着计算第一块 hash 数据：

```
# 1. convert system salt string to binary data
$ echo -n "6902f6b436dd8f08a2ecd512d4576a03325e14db8e6b1bb72b68d22f20a6a6d3" | xxd -r -ps > system-salt.bin
$ hexdump -Cv system-salt.bin 
00000000  69 02 f6 b4 36 dd 8f 08  a2 ec d5 12 d4 57 6a 03  |i...6........Wj.|
00000010  32 5e 14 db 8e 6b 1b b7  2b 68 d2 2f 20 a6 a6 d3  |2^...k..+h./ ...|
00000020

# 2. first 4K data of system.img
$ dd if=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img of=system-1st-4k.bin bs=4096 count=1
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.000316474 s, 12.9 MB/s

# 3. calculate first sha256 of (system-salt.bin + system-1st-4k.bin)
$ cat system-salt.bin system-1st-4k.bin | sha256sum
1e09183f5367d7ccde785b4cea8afead6b859058fc72d1181711eaecbcbd22ef  -
```

我们再看下 system.img 中，level 0 层级 hash 数据开始位置的 64 字节内容：

```
# level 0 hash data offset: 872734720 + 57344 = 872796160 = 0x3405D000
$ hexdump -Cv -s 0x3405D000 -n 32 out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img 
3405d000  1e 09 18 3f 53 67 d7 cc  de 78 5b 4c ea 8a fe ad  |...?Sg...x[L....|
3405d010  6b 85 90 58 fc 72 d1 18  17 11 ea ec bc bd 22 ef  |k..X.r........".|
3405d020  7e 05 9a 40 93 da 40 59  0c 31 10 f8 4b 0f 8e cd  |~..@..@Y.1..K...|
3405d030  cd e6 f1 f3 92 3e 4b b7  d0 fb 1b b1 f0 5d d5 61  |.....>K......].a|
3405d040
```

显然，这里镜像中的 hash 结果和我们手动计算的结果是一致的。



#### 查看 FEC 数据

根据 avbtool 查看镜像输出的信息，FEC 数据紧挨着 hashtree 数据的后面存放，偏移位置为: 879616000 =  0x346DE000。

```bash
# 查看 0x346DE000 开始的 FEC 数据
$ hexdump -Cv -s 0x346DE000 -n 128 system.img
346de000  08 7c 53 c3 8b c0 68 bd  3a 51 ce 73 9a 5a 3c 5c  |.|S...h.:Q.s.Z<\|
346de010  4b 0b ad 9d ff 30 13 98  90 22 30 54 7e 78 5d 00  |K....0..."0T~x].|
346de020  c6 a5 68 d1 01 14 6c 00  2e 98 b2 35 34 9a 43 26  |..h...l....54.C&|
346de030  cb 8c c1 e1 ad a0 e7 f9  72 3f 28 10 b7 52 5c 11  |........r?(..R\.|
346de040  7b 69 3b 00 35 ae 10 fd  f4 25 a7 8f 74 7e b9 8c  |{i;.5....%..t~..|
346de050  db a2 e5 f3 2d f2 d7 39  54 a9 2f 93 07 32 51 17  |....-..9T./..2Q.|
346de060  e8 69 a1 1f ac 68 03 99  f7 7b 9c f4 79 44 fb 4d  |.i...h...{..yD.M|
346de070  31 e5 25 b6 de 90 ed 51  02 ff 8a 2a 70 ae 2f 41  |1.%....Q...*p./A|
346de080
```



这部分确实就是镜像的 FEC 数据，实际上，这里的 FEC 数据是根据前面所有的数据(`原始镜像内容 + hashtree 数据` )进行编码得到的，也就是说，不论是镜像的原始数据出错了，还是计算得到的 hashtree 数据出错了，在可以复原的范围内，都可以使用 FEC 数据进行还原。

具体的 FEC 数据原理不在这里展开，后续考虑单独开篇讨论。



> **特别注意**
>
> avbtool 中，使用 fec 工具计算得到的 fec 数据实际上还包含一个 FEC FOOTER （4096 字节)，但 avbtool 在处理 fec 数据时，会提取 FEC FOOTER 中的 fec size 成员写入到 Hashtree descriptor 中，然后忽略整个 4096 字节的 FEC FOOTER 数据。
>
> 因此，无法在 avbtool 处理后的 system.img 中找到 FEC 数据的 Magic Number(0xFECFECFE，按照小端存放的话，用十六进制编辑器看应该为 "`fe ec cf fe`")



#### 查看 VBMeta 数据

这里的重点是解析 AVB Footer，并提取信息查看 VBMeta 的具体位置。但关于 VBMeta 数据具体内容的解析不是这里的重点，所以暂时略过。



### 5. 还原原始的 system.img 镜像

可以通过 avbtool 的 `erase_footer` 命令来还原原始镜像。

为了不破坏原始数据，这里先将生成的 system.img 复制为 system1.img，然后基于 system1.img 进行操作：

```bash
$ $ cp out/target/product/panther/system.img system1.img
$ avbtool erase_footer --image system1.img 
$ ls -al system1.img 
-rw-r--r-- 1 rocky users 872734720 Dec 15 12:20 system1.img
```

从这里可以看到，使用 `erase_footer` 操作后，system1.img 恢复到了原始镜像的 872734720 字节大小。

实际上移除的数据包括：hashtree 数据，FEC 数据, VBMeta 数据, 填充数据以及 AVB Footer。



## 4. 总结

当使用 avbtool 对原始的 system.img 镜像执行 `add_hashtree_footer` 操作时，主要发生了以下变化：

1. 写入原始未经处理的镜像 system.img，共 872734720 字节(0x3404E000)
2. 计算原始镜像的 hashtree，并从原始数据结束的地方开始写入 (0x3404E000)，大小为 6881280 字节(即 0x69000)
3. 计算原始镜像和 hashtree 数据的 FEC 数据，用于纠错。FEC 数据从 hashtree 结束的地方(879616000=872734720+6881280，即 0x346DE000)开始写入，大小 6955008字节(0x6A2000)。
4. 将原始镜像 system.img 计算得到的 VBMeta 元数据存放在 FEC 数据结束的地方(886571008=879616000+6955008，即 0x34D80000)，大小为 832 字节(占用 4K Block)
5. 将新镜像填充到指定大小 886812672 字节(通过参数指定:`--partition_size 886812672`)
6. 在新镜像的最后 4K block 的最后 64 字节写入 AVB Footer 内容

> 注：所有操作都按照 4K 页面对齐进行



所以，最终的 system.img 格式如下：

```bash
+--------------------------------+ 0x0
|      Original System Image     |
|      (system partition)        |
+--------------------------------+ original_image_size
|                                |
|      Hash Tree                 |
|      (Merkle Tree)             |
|                                |
+--------------------------------+ tree_offset + tree_size
|                                |
|      FEC Data                  | (Optional)
|                                |
+--------------------------------+ fec_offset + fec_size
|      AVB VBMeta                |
|      - Header                  |
|      - Authentication Block    |
|      - Hashtree Descriptor     |
|      - Properties              |
+--------------------------------+ vbmeta_offset + vbmeta_size
|                                |
|      Padding                   |
|                                |
+--------------------------------+  <-- Last 4KB offset
|      (4KB)                     |
|      AVB Footer                |  <-- Last 64 bytes
+--------------------------------+  <-- partition_size
```



总体来说，使用 `add_hashtree_footer` 操作的镜像处理后包含以下 5 块数据：

- Original System Image: 原始 System 分区镜像
- Hash Tree Data: 基于原始 System 镜像数据生成的 hashtree 数据
- FEC Data: 基于原始 System 镜像，以及 hashtree 数据计算得到的 FEC 数据
- VBMeta: AVB 元数据 (VBMeta)，位置从 FEC 数据结束开始
- AVB Footer: AVB Footer 数据，最后一个 4K 页面的最后 64 个字节

本文的内容除了分析 system.img 之外，也适合任何其它基于 `add_hashtree_footer` 操作的镜像，例如 vendor.img，或者 product.img 这类大分区镜像。

特别说明的是，如果使用 avbtool 时，指定选项 `--do_not_generate_fec`，则不会生成 FEC 数据。

## 5. 其它

我创建了一个 Android AVB 讨论群，主要讨论 Android 设备的 AVB 验证问题。

我还几个 Android OTA 升级讨论群，主要讨论 Android 设备的 OTA 升级话题。

欢迎您加群和我们一起交流，请在加我微信时注明“Android AVB 交流”或“Android OTA 交流”。

仅限 Android 相关的开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。


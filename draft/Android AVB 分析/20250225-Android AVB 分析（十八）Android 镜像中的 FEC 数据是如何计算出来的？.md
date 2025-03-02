# 20250225-Android AVB 分析（十八）Android 镜像中的 FEC 数据是如何计算出来的？

在[《Android AVB 分析（六）FEC 数据到底是如何生成的？》](https://blog.csdn.net/guyongqiangx/article/details/144487615)中，我分析了 Android 镜像的 FEC 是如何生成的。当我回头再看这篇文章的时候，这篇文章的标题有点过头了。这篇文章主要分析了 Android 编译过程中，如何调用 avbtool 生成 FEC 数据的过程。实际上，avbtool 自己并不直接生成 FEC，而是进一步调用 fec 工具处理带有 HashTree 的镜像得到 FEC 数据。

主要的命令如下：

```bash
# 根据实际用于计算的镜像数据来预估 FEC 的大小
$ fec --print-fec-size 879616000 --roots 2
6959104

# 计算镜像文件的 FEC 数据
$ fec --encode --roots 2 system-with-hash.img system-with-hash-fec.bin
encoding RS(255, 253) to 'system-with-hash-fec.bin' for input files:
        1: 'system-with-hash.img'
```



尽管这篇文章没有分析具体上 fec 工具是如何生成 FEC 数据的，但在 Android 编译的镜像处理层面上，已经分析了 FEC 数据生成的总体脉络，仍然值得一读。



在[《Android AVB 分析（十三）dm-verity 设备是如何映射的？》](https://blog.csdn.net/guyongqiangx/article/details/145211172)中，我演示了如何手动将带有 HashTree 和 FEC 数据的镜像映射为 dm-verity 设备，并且演示了如何制造一个带有错误数据的镜像，挂载后 dm-verity 驱动通过 FEC 纠错还原数据。



在[《Android AVB 分析（十六）5 个例子彻底理解 FEC(Reed-Solomon) 的工作原理》](https://blog.csdn.net/guyongqiangx/article/details/145865175) 和 [《Android AVB 分析（十七）程序员的RS(Reed-Solomon)编码实战》](https://blog.csdn.net/guyongqiangx/article/details/145865276) 中，详细介绍了 FEC 的工作原理，并从程序员的角度设计了一些例子来加深对里德所罗门编码的理解。



有了前面两篇关于 FEC 的基础，在本篇，我们将彻底解决关于 Android 镜像中 FEC 数据是如何生成的所有疑问。

本篇的重点如下：

1. Android 中用于生成 FEC(Reed-Solomen) 编码的 fec 工具介绍
2. Android 中 FEC 的参数
3. Android 中 FEC 计算的交织编码
4. 手动验证 Android 镜像的 FEC 数据(这回真的是徒手撸，而不是用 fec 工具)



## 1. fec 工具

在 Android 编译生成镜像时通过下面两条命令预估 FEC 镜像数据，以及生成最终的 FEC 数据:

```bash
# 根据实际用于计算的镜像数据来预估 FEC 的大小
$ fec --print-fec-size 879616000 --roots 2

# 计算镜像文件的 FEC 数据
$ fec --encode --roots 2 system-with-hash.img system-with-hash-fec.bin
```

关于这两条命令的来历，请参考[《Android AVB 分析（六）FEC 数据到底是如何生成的？》](https://blog.csdn.net/guyongqiangx/article/details/144487615)

我们这里只关注 fec 工具。



### 1.1 fec 源码

在[《Android AVB 分析（十）AVB 有哪些相关的源码？》](https://blog.csdn.net/guyongqiangx/article/details/144936814)提到了 Android 中 AVB 相关源码，不过那一篇中漏掉了 fec 工具源码。

总体上，fec 工具源码由 3 部分组成：

- `external/fec`
- `system/extras/libfec`
- `system/extras/verity/fec`

其中, 

- `external/fec` 是 Reed-Solomon 编码的开源实现，纯 FEC 编码计算，用于生成 `libfec_rs` 库。

- `system/extras/libfec` 是 Android AVB 中对 FEC 处理的实现，主要是从 Android 镜像中解析和提取 FEC 数据，这里的代码用于生成 `libfec` 库。(你有没有 `libfec_rs` 和 `libfec` 库功能分不清的情况? )

- `system/extras/verifty/fec` 才是 fec 工具的源码，这里的 fec 工具基于前面的 `libfec_rs` 和 `libfec` 库。fec 工具先对 Android 镜像镜像数据进行交织处理，然后使用 `libfec_rs` 对交织的数据编码，最后通过 `libfec` 库将 fec 数据写回到 Android 镜像中。

对 fec 使用者来说，最重要的是 ``system/extras/libfec/include/fec` 中包含的头文件 `ecc.h` 和 `io.h`。

文件 `ecc.h` 包含了 Android 中 fec 处理的一些核心参数:

```c
/* parameters to init_rs_char */
#define FEC_PARAMS(roots) \
    8,          /* symbol size in bits */ \
    0x11d,      /* field generator polynomial coefficients */ \
    0,          /* first root of the generator */ \
    1,          /* primitive element to generate polynomial roots */ \
    (roots),    /* polynomial degree (number of roots) */ \
    0           /* padding bytes at the front of shortened block */
```



文件 `io.h` 包含了 Android 中 fec footer 的结构定义：

```c
#ifndef SHA256_DIGEST_LENGTH
#define SHA256_DIGEST_LENGTH 32
#endif

#define FEC_BLOCKSIZE 4096
#define FEC_DEFAULT_ROOTS 2

#define FEC_MAGIC 0xFECFECFE
#define FEC_VERSION 0

/* disk format for the header */
struct fec_header {
    uint32_t magic;
    uint32_t version;
    uint32_t size;
    uint32_t roots;
    uint32_t fec_size;
    uint64_t inp_size;
    uint8_t hash[SHA256_DIGEST_LENGTH];
} __attribute__ ((packed));
```



如果你打算深入研究 Android 的 FEC，这两个头文件建议详细阅读。



### 1.2 fec 功能

可以直接看源码，或者通过 `--help` 选项查看 fec 工具的功能。

```bash
$ out/host/linux-x86/bin/fec -h
fec: a tool for encoding and decoding files using RS(255, N).

usage: fec <mode> [ <options> ] [ <data> <fec> [ <output> ] ]
mode:
  -e  --encode                      encode (default)
  -d  --decode                      decode
  -s, --print-fec-size=<data size>  print FEC size
  -E, --get-ecc-start=data          print ECC offset in data
  -V, --get-verity-start=data       print verity offset
options:
  -h                                show this help
  -v                                enable verbose logging
  -r, --roots=<bytes>               number of parity bytes
  -j, --threads=<threads>           number of threads to use
  -S                                treat data as a sparse file
encoding options:
  -p, --padding=<bytes>             add padding after ECC data
decoding options:
  -i, --inplace                     correct <data> in place
```



fec 工具主要有 3 个功能：encode, decode, print-fec-size，其它功能较少用到。

注意这里的 decode 还有个选项 `-i`，用于对数据纠错，并在原地更新.



## 2. FEC 参数

默认情况下 Android 使用 RS(255, 253) 编码，具体的参数参考 `ecc.h` 文件中的 FEC_PARAMS 定义，包括：

- symbol: 符号大小为 8，即 8 bit 为 1 个符号单位
- 每个编码的符号块总大小为 255，包括原始数据 253 字节和冗余数据 2 字节
- 每个编码块最大可以纠正 t=2 字节(在提供错误位置的前提下)，没有提供位置则可以纠正 t/2=1 字节
- 计算 FEC 时的数据块大小为 4096



## 3. FEC 交织编码

### 3.1 为什么要交织编码？

Android 中的 RS(255, 253) 编码，整个编码的数据块大小为 255 字节。因此，如果这 255 字节集中存放的话，那一旦这 255 字节所在的 block 坏了，就无法纠错了。



因此，为了提高纠错性能，引入了交织编码技术(interleaving coding)。



所谓交织编码，就是将数据交错开来，例如：

我们刚好有  253 块数据，每块数据的大小为 253 字节，这样在 RS(255, 253)编码时，可以将第 1 块，第 2 块，第 3 块，...，第 253 块数据的第一个字节单独提取出来形成一个 253 字节的数据块进行编码；将第 1 块，第 2 块，第 3 块，...，第 253 块数据的第二个字节单独提取出来形成又一个 253 字节的数据块进行编码。



这样的结果就是这 253 块数据，通过分别取每一块的第 1 字节，第 2 字节，第 3 字节... 分别生成了一个新的 253 数据块。这种交错重新组织数据的方式就称为交错编码。



现在假设这些数据中的第 2 块坏了。对于交织后的数据来说，相当于每个编码数据块中的第 2 个字节坏了。对于 RS(255, 253) 来说，1 个字节的错误可以通过 FEC 冗余数据纠正回来。因此，这坏掉的第二块 253 字节数据，完全可以恢复回来。



但是，Android 中的存储是按照 4K block 进行组织的，这基本上对应于大多数存储的 4k 存储块。

如果还是按照前面 `253 * 253` 的交织方式，那一个 4K 块相当于坏掉了 17 块( `4096/253=16.19=17`)，肯定是无法恢复了。



这种情况下，要想恢复整个 4K 的块，可以从每个 4K 块中取 1 个字节，这个 253 个 4K 的块进行交织生成 4096 个 253 字节的数据块就可以恢复了。

例如，253 个 4K 块，每个 4K 块的第 1，2，3，4，... 字节分别生成一个新的 253 字节的块编码。如果有一个 4K块坏掉，那相当于新的编码中每个编码块坏掉 1 个字节，然后通过这 4096 个 253 字节的 FEC 就可以将整个 4K 数据恢复回来。



进一步扩展，上面的情况是每隔 4K 取 1 个字节交织可以纠正 4K 块；那如果每隔 2*4K=8K 取 1 个字节交织就可以纠正 8K 的块了，这实际上是将 253 个 8K 块转变成 8K 个 253 字节的数据块。



为了让恢复数据的可能最大化，最佳的方法就是将整个文件分成 253 块进行交织，这样只要是这 1/253 坏了，都可以恢复回来。



### 3.2 Android 镜像的交织编码

实际上也是这样。

Android 镜像的数据按照 4096 (4K) 对齐。但是为了方便进行 RS(255, 253) 编码，需要将其调整为按照 253 * 4096 = 1036288 字节对齐。为什么要这样对齐呢？

假设你有个数据，刚好 254 个 4K 块，前面的 253 刚好可以交错编码，那剩余 1 个 4K 没法进行单独交织，该怎么办？此时最好的办法就是将剩余的 4K 经过填充对齐到 253 * 4096 = 1036288 的字节边界，需要填充 252 个 4K 数据。然后将得到的 506 个 4K 数据进行交织编码就可以了。 



因此，在对 Android 镜像进行 FEC 编码时，最小的数据单位就是 253 * 4096 = 1036288 = 1012K，这个也成为 FEC 交织的超级块。

整个 Android 分区镜像按照 1012K 的超级块对齐后，然后将其等分为 253 块进行交织，从而就能使得整个 Android 镜像纠错能力的最大化。



### 3.3 Android 镜像交织实例

这里还是按照本系列文章使用 `android-13.0.0_r41` 源码基于 `aosp_panther` 设备编译生成的 system 分区镜像 system.img 为例演示。

```bash
$ avbtool info_image --image system.img 
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
    Prop: com.android.build.system.fingerprint -> 'Android/aosp_panther/panther:13/TQ2A.230405.003.E1/rocky12021421:userdebug/test-ke
ys'
    Prop: com.android.build.system.security_patch -> '2023-04-05'
```

这里的 system.img 原始镜像大小为 872734720 字节，基于原始镜像生成的 hash tree 大小为 6881280 字节，基于原始镜像和 hash tree 生成的 FEC 数据紧挨着在后面存放，所以 offset=872734720+6881280=879616000。

```
Descriptors:
    Hashtree descriptor:
      ...
      FEC num roots:         2
      FEC offset:            879616000
      FEC size:              6955008 bytes
```



以下是计算 FEC 数据大小的推理过程：

用于计算 FEC 的数据大小为 879616000 字节，一共 214750 个 4K block，以每 253 个  4K 为一组，一共有 849 组。

```bash
# 实际镜像总大小
$ echo $((872734720+6881280))
879616000

# 实际镜像总 4K block 数
$ echo $(((872734720+6881280)/4096))
214750

# 总的 super block 数
$ echo $(((214750+252)/253))
849

# 填充后总 4K block 数
$ echo $((849*253))
214797
```

所以，实际是按照 849 个 253 * 4096 超级块进行交织的。交织的实际数据大小为 `253 * 4096 * 849 = 879808512`, 交织时对于不够的，向上填充部分的数据为 0。

在 fec 进行交织时，并没有先去填充生成一个新的镜像，而是在读取 879616000~879808512 范围内的数据时返回 0 而已。



对于填充后的总共 214797 块 4K 数据进行交织：

- 总共编码数：214797 * 4096 / 253 = 3477504 组
- FEC 数据大小: 3477504 * 2 + 4096 = 6955008 + 4096 = 6959104 字节 (其中 4096 为 fec footer block)
- 交织距离：214797 / 253 * 4096 = 3477504 = 3396K

由于交织距离为 3396K, 对每个交织编码的数据块，第 0, 1, 2, ..., i 个字节分别来自原来镜像的 i+3477504 的位置。

我们可以用下面这段示例的 bash 脚本来提取生成交织后的数据块:

```bash
$ cat interleaving.sh

# input filename: system-with-hash.img
if=system-with-hash.img

# extract data and hashtree from system.img
dd if=system.img of=$if bs=4096 count=$((879616000/4096)) status=none

# output filename base: system-with-hash
of_base=${if%.*}

# input file size: 879616000
if_size=$(ls -l $if | awk '{print $5}')

# input file block count: 214750
blocks=$((if_size/4096))

# superblock count: 949
rounds=$(((blocks+252)/253))

# superblock size: 1036288
round_size=$((4096*253))

# interleaving distance: 3477504
interleaving=$((round_size*$rounds/253))

# fec data size: 6955008
fec_data_size=$((round_size*$rounds/253*2))
printf "         image: %d\n" $if_size
printf "        blocks: %d\n" $blocks
printf "        rounds: %d\n" $rounds
printf "    round size: %d\n" $round_size
printf "  interleaving: %d\n" $interleaving
printf " fec data size: %d\n" $fec_data_size

# create interleaving data for 4 sample blocks, and show bytes offset of each block
for i in $(seq 0 4)
do
	echo "block $i offset:"
	of=$of_base-interleaving-block$i.bin
	rm -rf $of
	for j in $(seq 0 252)
	do
		offset=$((i+interleaving*j))
		echo -n "$offset "
		if [ $offset -lt $if_size ]; then
			# extract 1 byte at $offset from the image
			dd if=$if bs=1 skip=$offset count=1 status=none >> $of
		else
		    # using 0 if it is in padding area
			dd if=/dev/zero bs=1 count=1 status=none >> $of
		fi
	done
echo ""
done
```



这个脚本的输出如下：

```bash
$ bash interleaving.sh 
         image: 879616000
        blocks: 214750
        rounds: 849
    round size: 1036288
  interleaving: 3477504
 fec data size: 6955008
block 0 offset:
0 3477504 6955008 10432512 13910016 17387520 20865024 24342528 27820032 31297536 34775040 38252544 41730048 45207552 48685056 ... ... 872853504 876331008 879808512 
block 1 offset:
1 3477505 6955009 10432513 13910017 17387521 20865025 24342529 27820033 31297537 34775041 38252545 41730049 45207553 48685057 ... ... 872853505 876331009 879808513 
block 2 offset:
2 3477506 6955010 10432514 13910018 17387522 20865026 24342530 27820034 31297538 34775042 38252546 41730050 45207554 48685058 ... ... 872853506 876331010 879808514 
block 3 offset:
3 3477507 6955011 10432515 13910019 17387523 20865027 24342531 27820035 31297539 34775043 38252547 41730051 45207555 48685059 ... ... 872853507 876331011 879808515 
block 4 offset:
4 3477508 6955012 10432516 13910020 17387524 20865028 24342532 27820036 31297540 34775044 38252548 41730052 45207556 48685060 ... ... 872853508 876331012 879808516
```

以及 5 个交织后的 block 数据:

```bash
$ ls -al system-with-hash*
-rwxrwxrwx 1 rocky rocky       253 Mar  2 11:19 system-with-hash-interleaving-block0.bin
-rwxrwxrwx 1 rocky rocky       253 Mar  2 11:19 system-with-hash-interleaving-block1.bin
-rwxrwxrwx 1 rocky rocky       253 Mar  2 11:19 system-with-hash-interleaving-block2.bin
-rwxrwxrwx 1 rocky rocky       253 Mar  2 11:19 system-with-hash-interleaving-block3.bin
-rwxrwxrwx 1 rocky rocky       253 Mar  2 11:19 system-with-hash-interleaving-block4.bin
-rwxrwxrwx 1 rocky rocky 879616000 Mar  2 11:19 system-with-hash.img

$ hexdump -Cv system-with-hash-interleaving-block0.bin
00000000  00 59 a0 98 0a c6 9f a3  b9 83 0c 73 68 0a e0 e6  |.Y.........sh...|
00000010  76 de d2 05 00 02 65 4f  99 6c 39 3e e0 18 3c 5f  |v.....eO.l9>..<_|
00000020  e9 d8 7a 65 d4 39 48 04  e7 c4 00 72 d2 00 03 7f  |..ze.9H....r....|
00000030  04 00 00 00 e0 30 29 45  08 ac ff ff 24 31 0a 16  |.....0)E....$1..|
00000040  90 08 9b 00 a9 a9 08 f3  0c ff 50 53 ec 00 71 36  |..........PS..q6|
00000050  6c 74 01 cd 90 66 10 fb  94 c0 cd 86 36 f9 13 86  |lt...f......6...|
00000060  83 97 92 7d 1f 84 7e 00  59 f0 34 0d b0 d3 10 58  |...}..~.Y.4....X|
00000070  a0 20 00 c5 c2 3b 34 5d  fd 09 a4 ba 52 73 08 00  |. ...;4]....Rs..|
00000080  02 64 40 54 05 0d d1 b6  6e 41 04 f6 7e 43 f0 04  |.d@T....nA..~C..|
00000090  22 7e 4f 0f 30 00 e1 22  f0 02 f8 70 78 c0 cb f8  |"~O.0.."...px...|
000000a0  59 6f 04 0e 04 ce 01 61  61 d2 dd 1f 02 f4 01 4f  |Yo.....aa......O|
000000b0  78 6f a7 61 f0 44 76 00  84 f9 1a 7f 4d 04 60 00  |xo.a.Dv.....M.`.|
000000c0  36 a4 a9 17 69 f0 00 68  0a 09 1f f6 2b e1 08 00  |6...i..h....+...|
000000d0  c0 14 69 7a 1c df 14 75  72 72 e0 09 e5 24 70 29  |..iz...urr...$p)|
000000e0  c8 e8 80 81 6c 40 18 72  e0 28 69 09 63 00 12 2f  |....l@.r.(i.c../|
000000f0  01 70 ab 12 e1 43 6c a4  8a 7e 23 ad c1           |.p...Cl..~#..|
000000fd
```



将上一篇中用于 RS(255, 253) 编码的例子修改一下即可计算这里 block0 的 FEC 编码：

```python
from reedsolo import RSCodec
from construct.lib.hex import hexdump

if __name__ == "__main__":
    print("RS(255, 253) Encoding Demo:")

    with open('system-with-hash-interleaving-block0.bin', mode='rb') as file:
        data = file.read()

    print("Original Data:")
    print(hexdump(data, linesize=16))

    rs = RSCodec(nsize=255, nsym=2)

    res = rs.encode(data)
    print("FEC Data:")
    print(hexdump(res[253: ], linesize=16))

    print("Done!")
```



运行这个脚本:

```bash
$ python reedsolo-encoding-example.py 
RS(255, 253) Encoding Demo:
Original Data:
hexundump("""
0000   00 59 A0 98 0A C6 9F A3 B9 83 0C 73 68 0A E0 E6   .Y.........sh...
0010   76 DE D2 05 00 02 65 4F 99 6C 39 3E E0 18 3C 5F   v.....eO.l9>..<_
0020   E9 D8 7A 65 D4 39 48 04 E7 C4 00 72 D2 00 03 7F   ..ze.9H....r...
0030   04 00 00 00 E0 30 29 45 08 AC FF FF 24 31 0A 16   .....0)E....$1..
0040   90 08 9B 00 A9 A9 08 F3 0C FF 50 53 EC 00 71 36   ..........PS..q6
0050   6C 74 01 CD 90 66 10 FB 94 C0 CD 86 36 F9 13 86   lt...f......6...
0060   83 97 92 7D 1F 84 7E 00 59 F0 34 0D B0 D3 10 58   ...}..~.Y.4....X
0070   A0 20 00 C5 C2 3B 34 5D FD 09 A4 BA 52 73 08 00   . ...;4]....Rs..
0080   02 64 40 54 05 0D D1 B6 6E 41 04 F6 7E 43 F0 04   .d@T....nA..~C..
0090   22 7E 4F 0F 30 00 E1 22 F0 02 F8 70 78 C0 CB F8   "~O.0.."...px...
00A0   59 6F 04 0E 04 CE 01 61 61 D2 DD 1F 02 F4 01 4F   Yo.....aa......O
00B0   78 6F A7 61 F0 44 76 00 84 F9 1A 7F 4D 04 60 00   xo.a.Dv....M.`.
00C0   36 A4 A9 17 69 F0 00 68 0A 09 1F F6 2B E1 08 00   6...i..h....+...
00D0   C0 14 69 7A 1C DF 14 75 72 72 E0 09 E5 24 70 29   ..iz...urr...$p)
00E0   C8 E8 80 81 6C 40 18 72 E0 28 69 09 63 00 12 2F   ....l@.r.(i.c../
00F0   01 70 AB 12 E1 43 6C A4 8A 7E 23 AD C1            .p...Cl..~#..
""")

FEC Data:
hexundump("""
0000   08 7C                                             .|
""")

Done!
```



可以看到这个 block 经过 RS(255, 253) 编码后的 FEC 数据为 `0x08 0x7C`。

由于这块数据是最开始的第 0 块，所以我们可以查看下 system.img 镜像中的前两个字节：

```bash
$ hexdump -Cv -s 879616000 -n 32 system.img
346de000  08 7c 53 c3 8b c0 68 bd  3a 51 ce 73 9a 5a 3c 5c  |.|S...h.:Q.s.Z<\|
346de010  4b 0b ad 9d ff 30 13 98  90 22 30 54 7e 78 5d 00  |K....0..."0T~x].|
346de020
```

我们这里看到，system.img 中 FEC 数据的前两字节 `08 7c` 和我们手工计算的结果一样。

同样的方式，你也可以计算其它交织数据块的 FEC 同 system.img 中的结果进行比较。



## 4. 使用 fec 纠错

前面我们用 fec 工具计算了 `system-with-hash.img` 文件的 FEC 数据，这里我们故意在 `system-with-hash.img` 中生成 4K 的错误数据，看看是否可以恢复。

准备错误数据

```bash
# 生成 system-with-hash-4k-err.img 用于测试
$ cp system-with-hash.img system-with-hash-4k-err.img

# 生成 1 个 4K 全 0xff 的数据
$ dd if=/dev/zero bs=4096 count=1 | tr '\000' '\377' > 4096ff.bin
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 4.1386e-05 s, 99.0 MB/s
$ hexdump -C 4096ff.bin 
00000000  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000

# 使用 4k 0xff 的数据替换 system-with-hash-4k-err.img 前 4096 字节
$ dd if=4096ff.bin of=system-with-hash-4k-err.img bs=4096 seek=0 count=1 conv=notrunc
1+0 records in
1+0 records out
4096 bytes (4.1 kB, 4.0 KiB) copied, 0.0010622 s, 3.9 MB/s
$ hexdump -C -n $((4096+64)) system-with-hash-4k-err.img
00000000  ff ff ff ff ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
*
00001000  02 00 00 00 03 00 00 00  04 00 00 00 00 00 00 00  |................|
00001010  39 00 00 00 00 00 00 00  00 00 00 00 00 00 0d 73  |9..............s|
00001020  02 80 00 00 03 80 00 00  04 80 00 00 00 00 00 00  |................|
00001030  12 00 00 00 00 00 00 00  00 00 00 00 00 00 17 77  |...............w|
00001040

# 对比原始数据中的前 4096 字节
$ hexdump -C -n $((4096+64)) system-with-hash.img
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00000400  b0 0c 00 00 4e 40 03 00  00 00 00 00 8c 02 00 00  |....N@..........|
00000410  32 00 00 00 00 00 00 00  02 00 00 00 02 00 00 00  |2...............|
00000420  00 80 00 00 00 80 00 00  d0 01 00 00 00 00 00 00  |................|
00000430  80 07 5c 49 00 00 ff ff  53 ef 01 00 01 00 00 00  |..\I....S.......|
00000440  80 07 5c 49 00 00 00 00  00 00 00 00 01 00 00 00  |..\I............|
00000450  00 00 00 00 0b 00 00 00  00 01 00 00 28 00 00 00  |............(...|
00000460  42 00 00 00 7b 40 00 00  2f 87 0f 2b 48 49 54 05  |B...{@../..+HIT.|
00000470  90 6a ad ce 3f 32 88 03  2f 00 00 00 00 00 00 00  |.j..?2../.......|
00000480  00 00 00 00 00 00 00 00  2f 00 00 00 00 00 00 00  |......../.......|
00000490  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
000004e0  00 00 00 00 00 00 00 00  00 00 00 00 6b ce 97 f7  |............k...|
000004f0  90 37 52 3c a7 9f 00 7c  64 6d ad a4 01 00 00 00  |.7R<...|dm......|
00000500  0c 00 00 00 00 00 00 00  80 07 5c 49 00 00 00 00  |..........\I....|
00000510  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00000550  00 00 00 00 00 00 00 00  00 00 00 00 20 00 20 00  |............ . .|
00000560  01 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00000570  00 00 00 00 00 00 00 00  05 87 0d 00 00 00 00 00  |................|
00000580  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00000640  00 00 00 00 00 00 00 00  e1 00 00 00 00 00 00 00  |................|
00000650  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001000  02 00 00 00 03 00 00 00  04 00 00 00 00 00 00 00  |................|
00001010  39 00 00 00 00 00 00 00  00 00 00 00 00 00 0d 73  |9..............s|
00001020  02 80 00 00 03 80 00 00  04 80 00 00 00 00 00 00  |................|
00001030  12 00 00 00 00 00 00 00  00 00 00 00 00 00 17 77  |...............w|
00001040
```



使用 FEC 恢复错误数据

```bash
# 查看 fec 哈希值
$ md5sum system-with-hash.img system-with-hash-4k-err.img 
f5714d8dc3af9b417e9884bbdc0593f5  system-with-hash.img
40e60917fdb5fcd6fb5582933b7d74b3  system-with-hash-4k-err.img

# 使用正确的镜像生成 fec 数据
$ fec -e --roots=2 system-with-hash.img system-with-hash-fec.bin 
encoding RS(255, 253) to 'system-with-hash-fec.bin' for input files:
        1: 'system-with-hash.img'

# 检查 fec 数据但不修复
$ fec -d --roots=2 system-with-hash-4k-err.img system-with-hash-fec.bin 
decoding 'system-with-hash-4k-err.img' to '' using RS(255, 253) from 'system-with-hash-fec.bin'
corrected 4094 errors

# 检查 fec 数据，并在原地修复
$ cp system-with-hash-4k-err.img system-with-hash-4k-err-inplace.img
$ fec -d --roots=2 --inplace system-with-hash-4k-err.img system-with-hash-fec.bin 
correcting 'system-with-hash-4k-err.img' using RS(255, 253) from 'system-with-hash-fec.bin'
corrected 4094 errors

# system-with-hash.img 和 system-with-hash-4k-err.img 一样，说明已经在原地修复了错误数据
$ md5sum system-with-hash*.img
f5714d8dc3af9b417e9884bbdc0593f5  system-with-hash-4k-err.img
40e60917fdb5fcd6fb5582933b7d74b3  system-with-hash-4k-err-inplace.img
f5714d8dc3af9b417e9884bbdc0593f5  system-with-hash.img
```

## 5. 总结

本文从代码构成分析了 fec 工具, fec 代码由 3 部分构成。

- `external/fec` 是 Reed-Solomon 编码的开源实现，纯 FEC 编码计算，用于生成 `libfec_rs` 库。

- `system/extras/libfec` 是 Android AVB 中对 FEC 处理的实现，主要是从 Android 镜像中解析和提取 FEC 数据，这里的代码用于生成 `libfec` 库。(你有没有 `libfec_rs` 和 `libfec` 库功能分不清的情况? )

- `system/extras/verifty/fec` 才是 fec 工具的源码，这里的 fec 工具基于前面的 `libfec_rs` 和 `libfec` 库。fec 工具先对 Android 镜像镜像数据进行交织处理，然后使用 `libfec_rs` 对交织的数据编码，最后通过 `libfec` 库将 fec 数据写回到 Android 镜像中。



编译生成的 fec 工具可以用来 encode, decode, print-fec-size 操作 FEC 数据：

```bash
$ out/host/linux-x86/bin/fec -h
fec: a tool for encoding and decoding files using RS(255, N).

usage: fec <mode> [ <options> ] [ <data> <fec> [ <output> ] ]
mode:
  -e  --encode                      encode (default)
  -d  --decode                      decode
  -s, --print-fec-size=<data size>  print FEC size
  -E, --get-ecc-start=data          print ECC offset in data
  -V, --get-verity-start=data       print verity offset
options:
  -h                                show this help
  -v                                enable verbose logging
  -r, --roots=<bytes>               number of parity bytes
  -j, --threads=<threads>           number of threads to use
  -S                                treat data as a sparse file
encoding options:
  -p, --padding=<bytes>             add padding after ECC data
decoding options:
  -i, --inplace                     correct <data> in place
```



默认情况下 Android 使用 RS(255, 253) 进行 FEC 编码，具体的参数参考 `ecc.h` 文件中的 FEC_PARAMS 定义，包括：

- symbol: 符号大小为 8，即 8 bit 为 1 个符号单位
- 每个编码的符号块总大小为 255，包括原始数据 253 字节和冗余数据 2 字节
- 每个编码块最大可以纠正 t=2 字节(在提供错误位置的前提下)，没有提供位置则可以纠正 t/2=1 字节
- 计算 FEC 时的数据块大小为 4096



为了增加纠错能力，Android 中使用了交错编码技术。

具体做法上，Android 镜像的数据按照 4096 (4K) 对齐。但是为了方便进行 RS(255, 253) 编码，需要将其调整为按照 253 * 4096 = 1036288 (1012K) 字节对齐。

整个 Android 分区镜像按照 1012K 的超级块对齐后，然后将其等分为 253 块进行交织，从而就能使得整个 Android 镜像纠错能力的最大化。



对于大小为 879616000 字节的镜像，交织的实际数据大小为 `253 * 4096 * 849 = 879808512`, 交织时对于不够的，向上填充部分的数据为 0。

在 fec 进行交织时，并没有先去填充生成一个新的镜像，而是在读取 879616000~879808512 范围内的数据时返回 0 而已。



对于填充后的总共 214797 块 4K 数据进行交织：

- 总共编码数：214797 * 4096 / 253 = 3477504 组
- FEC 数据大小: 3477504 * 2 + 4096 = 6955008 + 4096 = 6959104 字节 (其中 4096 为 fec footer block)
- 交织距离：214797 / 253 * 4096 = 3477504 = 3396K

由于交织距离为 3396K, 对每个交织编码的数据块，第 0, 1, 2, ..., i 个字节分别来自原来镜像的 i+3477504 的位置。



使用以下脚本，从原始镜像中提取交织后的数据:

```bash
$ cat interleaving.sh 
if=system-with-hash.img
dd if=system.img of=$if bs=4096 count=$((879616000/4096)) status=none
of_base=${if%.*}
if_size=$(ls -l $if | awk '{print $5}')
blocks=$((if_size/4096))
rounds=$(((blocks+252)/253))
round_size=$((4096*253))
interleaving=$((round_size*$rounds/253))
fec_data_size=$((round_size*$rounds/253*2))
printf "         image: %d\n" $if_size
printf "        blocks: %d\n" $blocks
printf "        rounds: %d\n" $rounds
printf "    round size: %d\n" $round_size
printf "  interleaving: %d\n" $interleaving
printf " fec data size: %d\n" $fec_data_size
for i in $(seq 0 4)
do
        echo "block $i offset:"
        of=$of_base-interleaving-block$i.bin
        rm -rf $of;
        for j in $(seq 0 252)
        do
                offset=$((i+interleaving*j))
                echo -n "$offset "
                if [ $offset -lt $if_size ]; then
                        dd if=$if bs=1 skip=$offset count=1 status=none >> $of
                else
                        dd if=/dev/zero bs=1 count=1 status=none >> $of
                fi
        done
echo ""
done
```



最后使用 Python 的 reedsolo 库，使用一个简单例子验证了 FEC 数据的生成。

我会在下一篇详细演示 Android 镜像在挂载时的纠错实战。

## 6. 其它

我创建了一个 Android AVB 讨论群，主要讨论 Android 设备的 AVB 验证问题。

我还有几个 Android OTA 升级讨论群，主要讨论 Android 设备的 OTA 升级话题。

欢迎您加群和我们一起交流，请在加我微信时注明“Android AVB 交流”或“Android OTA 交流”。

仅限 Android 相关的开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。









 










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

1. Android 中用于生成 FEC(Reed-Solomen) 编码的 fec 工具解析
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

`external/fec` 是 Reed-Solomon 编码的开源实现，纯 FEC 编码计算，用于生成 `libfec_rs` 库。

`system/extras/libfec` 是 Android AVB 中对 FEC 处理的实现，主要是从 Android 镜像中解析和提取 FEC 数据，这里的代码用于生成 `libfec` 库。(你有没有 `libfec_rs` 和 `libfec` 库功能分不清的情况? )

`system/extras/verifty/fec` 才是 fec 工具的源码，这里的 fec 工具基于前面的 `libfec_rs` 和 `libfec` 库。fec 工具先对 Android 镜像镜像数据进行交织处理，然后使用 `libfec_rs` 对交织的数据编码，最后通过 `libfec` 库将 fec 数据写回到 Android 镜像中。

对 fec 使用者来说，最重要的是 ``system/extras/libfec/include/fec` 中包含的头文件 `ecc.h` 和 `io.h`:

```bash
$ ls -lh system/extras/libfec/include/fec/
total 12K
-rw-r--r-- 1 rocky users 2.1K Aug 16  2023 ecc.h
-rw-r--r-- 1 rocky users 4.9K Aug 16  2023 io.h
```

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




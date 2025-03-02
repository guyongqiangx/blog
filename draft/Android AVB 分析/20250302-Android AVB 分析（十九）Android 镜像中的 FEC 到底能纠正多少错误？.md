# 20250302-Android AVB 分析（十九）Android 镜像中的 FEC 到底能纠正多少错误？

我在 [《Android AVB 分析（十三）dm-verity 设备是如何映射的？》](https://blog.csdn.net/guyongqiangx/article/details/145211172)中做过一个 system 分区镜像 system.img 进行 dm-verity 映射，加载和 FEC 纠错的例子。

在那个纠错的例子中，我修改了磁盘中某个字节的 3 个 bit，有了前面的基础，我们就知道这对于 RS(255, 253) 编码来说，和几个 bit 没有关系，不论是 1 bit，2 bit, 3 bit 或者 8 bit, 都对应于 1 个符号(symbol)。所以实际上就是破坏了 1 个符号，完全可以通过 FEC 纠正回来。



有个小伙伴看了我的这篇文章，然后他也做了破坏试验，然后发现及时他破坏了 16 个字节，系统也仍然可以恢复。于是他私信问我最多可以就纠正多少内容。



![](./images-20250302-Android AVB 分析（十九）Android 镜像中的 FEC 到底能纠正多少错误？/fec-capability-16bytes.png)

我当时还没有深入研究 Android 上 FEC 的纠错能力，所以估计肯定不止 16 字节，大概 4K 吧。然后请他去做个实验验证。



对于 RS(255, 253) 编码来说，其 t=2, 因此每 253 字节最多可以纠正 t/2=1 个字节，但是在提供了错误位置的前提下，最多可以纠正 t 个符号，即 2 个字节。

Android 镜像由于采用了 FEC 交织编码，因此纠错能力得到了大大的增强。那到底可以纠正多少呢？具体要看交织编码的情况。

对于我们示例的 system.img 镜像，其原始镜像大小为 872734720 (832.31 M)字节，然后计算得到其  hashtree 数据 6881280 (6.57 M)字节。基于原始镜像和 hastree 进行编码，得到的 FEC 数据大小为 6955008 (6.64 M)字节。

我们在上一篇中计算过 Android 镜像交织编码的情况，对于 879616000 (838.87 M)字节的数据，需要按照 253 * 4096 填充对齐后再交织编码。

为了达到最大的纠错能力，因此将交织编码扩散到整个文件，换句话说，对于 RS(255, 253) 编码，其原始数据的 253 字节来自整个镜像数据。

所以，两个交织编码字节之间的距离为：3477504 字节，即 3396 K。所以任意破坏连续的 3396K 数据，在交织后，实际上就破坏了 3377504 组 RS(255, 253) 编码中每一个编码的 1 个字节。而对于 RS(255, 253) 编码来说，破坏 1 个符号(即 1 字节) 是可以进行恢复的。

好了，到了这里，我亲自做个实验吧。

## 实验 1. 将镜像破坏 3396K 字节

```bash
$ cp system-with-hash.img system-with-hash-3396k-err.img
$ dd if=/dev/zero bs=1024 count=3396 | tr '\000' '\377' > 3396ff.bin
$ ls -al 3396ff.bin 
-rw-r--r-- 1 rocky users 3477504 Mar  2 21:15 3396ff.bin

$ dd if=3396kff.bin of=system-with-hash-3396k-err.img bs=4096 seek=0 count=$((3377504/4096)) conv=notrunc

$ md5sum system-with-hash.img system-with-hash-3396k-err.img 
f5714d8dc3af9b417e9884bbdc0593f5  system-with-hash.img
3693eac1093fc31cb69c0c9031b96019  system-with-hash-3396k-err.img

$ fec -d --roots=2 --inplace system-with-hash-3396k-err.img system-with-hash-fec.bin 
correcting 'system-with-hash-3396k-err.img' using RS(255, 253) from 'system-with-hash-fec.bin'
corrected 3348648 errors

$ md5sum system-with-hash.img system-with-hash-3396k-err.img 
f5714d8dc3af9b417e9884bbdc0593f5  system-with-hash.img
f5714d8dc3af9b417e9884bbdc0593f5  system-with-hash-3396k-err.img
```



这里我们看到，直接使用 fec 工具修复了这个 3396K 的错误。具体修复的编码为 3348648 组。

> 问题 1：
>
> 我们使用 3377504 个全  0xFF 的数据去修改，理论上会有 3377504 组，为什么恢复时纠错只有 3348648 组呢？



## 实验 2. 将镜像破坏 4000K 字节

理论上连续破坏超过 3477504 (3396K) 数据就无法恢复了，为了操作方便，我们这里再演示 1 个破坏 4000K 内容的数据，看看是不是就不能修复了。

> 我自己还尝试做过一个写入 3397k 字符 0xff 的例子，结果最终实际破坏的编码为 3450549 组，少于 3477504  个错误。
>
> ```bash
> $ fec -d --roots=2 --inplace system-with-hash-3397k-err.img system-with-hash-fec.bin 
> correcting 'system-with-hash-3397k-err.img' using RS(255, 253) from 'system-with-hash-fec.bin'
> corrected 3450549 errors
> ```

```bash
$ cp system-with-hash.img system-with-hash-4000k-err.img
$ dd if=/dev/zero bs=1024 count=4000 | tr '\000' '\377' > 4000kff.bin

$ dd if=4000kff.bin of=system-with-hash-4000k-err.img bs=4096 seek=0 count=1000 conv=notrunc
$ md5sum system-with-hash.img system-with-hash-4000k-err.img
f5714d8dc3af9b417e9884bbdc0593f5  system-with-hash.img
71e852010afcf738616c0cfb1c27ffd8  system-with-hash-4000k-err.img

$ fec -d --roots=2 --inplace system-with-hash-4000k-err.img system-with-hash-fec.bin 
correcting 'system-with-hash-4000k-err.img' using RS(255, 253) from 'system-with-hash-fec.bin'
failed to recover [70702621, 70702874)
```

我们看到这里使用 FEC 数据纠错失败了。



从这里看，验证了我们之前的猜想，对于我们的镜像数据，使用 RS(255, 253) 以及交织编码，最多可以纠正 3396K连续破坏的数据。



当然，如果是非连续的破坏，而这些破坏又刚好只有 1 个字节落在交织编码的 RS(255, 253) 数据块内，那可以纠错的内容就更多了。



现在，让我们将分区镜像挂载为 dm-verity 设备，看看此时的纠错能力。



## 实验 3. 将镜像破坏 6792K 字节

为什么选择 6792K 字节呢？因为 `6792K = 3392K * 2`。



## 实验 4. 将镜像破坏 6800K 字节



## 结论








# 20250225-Android AVB 分析（十八）Android 镜像中的 FEC 数据是如何计算出来的？

在[《Android AVB 分析（六）FEC 数据到底是如何生成的？》](https://blog.csdn.net/guyongqiangx/article/details/144487615)中，我分析了 Android 镜像的 FEC 是如何生成的。当我回头再看这篇文章的时候，这篇文章的标题有点过头了。这篇文章主要分析了 Android 编译过程中，如何调用 avbtool 生成 FEC 数据的过程。实际上，avbtool 自己并不直接生成 FEC，而是进一步调用 fec 工具处理带有 HashTree 的镜像得到 FEC 数据。

尽管这篇文章没有分析具体上 fec 工具是如何生成 FEC 数据的，但在 Android 编译的镜像处理层面上，已经分析了 FEC 数据生成的总体脉络，仍然值得一读。



在[《Android AVB 分析（十三）dm-verity 设备是如何映射的？》](https://blog.csdn.net/guyongqiangx/article/details/145211172)中，我演示了如何手动将带有 HashTree 和 FEC 数据的镜像映射为 dm-verity 设备，并且演示了如何制造一个带有错误数据的镜像，挂载后 dm-verity 驱动通过 FEC 纠错还原数据。



在[《Android AVB 分析（十六）5 个例子彻底理解 FEC(Reed-Solomon) 的工作原理》](https://blog.csdn.net/guyongqiangx/article/details/145865175) 和 [《Android AVB 分析（十七）程序员的RS(Reed-Solomon)编码实战》](https://blog.csdn.net/guyongqiangx/article/details/145865276) 中，详细介绍了 FEC 的工作原理，并从程序员的角度设计了一些例子来加深对里德所罗门编码的理解。



有了前面两篇关于 FEC 的基础，在本篇，我们将彻底解决关于 Android 镜像中 FEC 数据是如何生成的所有疑问。

本篇的重点如下：

1. Android 中 FEC(Reed-Solomen) 编码的参数
2. 关于交织编码
3. 手动验证 Android 镜像的 FEC 数据(这回真的是徒手撸，而不是用 fec 工具)
4. Android 的 FEC 到底能够纠正多少错误数据？




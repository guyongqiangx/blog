# 20250105-Android AVB 分析（一一）bootloader 是如何进行 verify boot 检查的？

上一篇[《Android AVB 分析（十）AVB 有哪些相关的源码？》](https://blog.csdn.net/guyongqiangx/article/details/144936814)中分析了 AVB 源码结构，本篇正式深入 AVB 源码，看看在 bootloader 中是如何使用 libavb 进行 verify boot 检查验证的。



对于 bootloader 中的启动验证，这一块属于厂家自己的代码，因为各个厂家的 bootloader 都可能不一样, 有的用 u-boot，有的基于 UEFI，有的可能是私有的 bootloader。而 Android 官方只要求集成 libavb 完成验证即可。



我不可能公开分享某一家公司不开源的 bootloader 源码，因此这里就以公开的 u-boot 源码进行分析，看看 u-boot 中是如何使用 libavb 进行启动验证的。

> 本文基于写作时最新的 u-boot 源码进行分析: v2025.01-rc6
>
> - https://github.com/u-boot/u-boot/tree/v2025.01-rc6
>
> 并参考 u-boot 关于 AVB 2.0 的参考文档:
>
> - https://docs.u-boot.org/en/latest/android/avb2.html

虽然是基于 u-boot 最新的源码分析，但实际上 u-boot 中集成的 libavb 库并不是最新的 v1.3 版，而是 v1.1 版本。

```c
u-boot-v2025.01$ grep -n AVB_VERSION_MAJOR -C 2 lib/libavb/avb_version.h
18-
19-/* The version number of AVB - keep in sync with avbtool. */
20:#define AVB_VERSION_MAJOR 1
21-#define AVB_VERSION_MINOR 1
22-#define AVB_VERSION_SUB 0
```

所以本文基于 u-boot 中的 libavb v1.1 版本的代码进行分析。

后面看情况再决定是否跟踪分析 libavb v1.1, v1.2 和 v1.3 版本的变更。






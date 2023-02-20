# 20230221-Android OTA 相关工具(三) A/B 系统之 bootctl

前面两篇:

- [《Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl》](https://blog.csdn.net/guyongqiangx/article/details/129122159)
- [《Android OTA 相关工具(二) 动态分区之 dmctl》]()

分别介绍了调试动态分区和虚拟 A/B 分区最常用的工具 snapshotctl 和 dmctl，这一篇介绍 bootctl，一个专门用于设置 BootControl HAL 接口的工具。

这个工具最常用的地方就是用来切换 A/B 系统。

我最早在 [《Android A/B System OTA分析（三）主系统和bootloader的通信》](https://blog.csdn.net/guyongqiangx/article/details/72480154) 介绍过基本用法，本篇则对这个工具进行详细介绍。



> bootctl 的全称是 boot control



> 本文基于 Android 代码版本: android-11.0.0_r21，但后续版本也大同小异
>
> 在线代码：http://aospxref.com/android-11.0.0_r21/



bootctl 工具的源码位于:

```bash
system/extras/bootctl/bootctl.c
```

> 在线代码：http://aospxref.com/android-11.0.0_r21/xref/system/extras/bootctl/bootctl.cpp


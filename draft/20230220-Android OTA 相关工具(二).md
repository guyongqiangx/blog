# 20230220-Android OTA 相关工具(二) 动态分区之 dmctl



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
> 文章链接：



我在上一篇[《Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl》](https://blog.csdn.net/guyongqiangx/article/details/129122159) 中介绍了从虚拟 A/B 系统 (Android R)开始引入的 snapshot 调试工具 snapshotctl。

snapshotctl 本身可以做不少事情，比方说 dump 升级信息, map 和 unmap 各种虚拟分区等。

这一篇介绍动态分区调试工具 dmctl，配合 snapshotctl 工具，对各种 dm 开头的动态分区和虚拟分区进行调试更加方便。

> snapshotctl 的全称是 snapshot control
>
> dmctl 的全称是 device mapper control



dmctl 工具的源码位于:

```bash
system/core/fs_mgr/tools/dmctl.cpp
```






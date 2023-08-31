# 20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/



从 Android 10(Q) 开始，引入了动态分区，伴随的就是一组动态分区内容数据增删改查相关的操作，以及这些操作所需要的工具，包括 lpdump, lpmake, lpunpack, lpadd, lpflash。



工具名称前缀 lp 表示是 logic partition，即逻辑分区。

所谓逻辑分区，是相对于物理分区而言，因为动态分区内部的各种分区并不是实际的物理分区。

因此，可以说动态分区本身的 super 是物理分区，但 super 内包含的各种分区就是逻辑分区。



前面两篇分别介绍了 lpdump 和 lpmake，本篇介绍 lpunpack。

本文基于 android-13.0.0_r41 编译生成的 lpunpack 介绍该工具的使用，但也适用于 Android 10(Q) 开始的其它 Android 版本。



> [《Android OTA 相关工具》](https://blog.csdn.net/guyongqiangx/category_12211864.html)系列，目前已有文章列表：
>
> - [《Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl》](https://blog.csdn.net/guyongqiangx/article/details/129122159)
> - [《Android OTA 相关工具(二) 动态分区之 dmctl》](https://blog.csdn.net/guyongqiangx/article/details/129229115)
> - [《Android OTA 相关工具(三) A/B 系统之 bootctl 工具》](https://blog.csdn.net/guyongqiangx/article/details/129310109)
> - [《Android OTA 相关工具(四) 查看 payload 文件信息》](https://blog.csdn.net/guyongqiangx/article/details/129228856)
> - [《Android OTA 相关工具(五) 使用 lpdump 查看动态分区》](https://blog.csdn.net/guyongqiangx/article/details/129785777)
> - [《Android OTA 相关工具(六) 使用 lpmake 打包生成 super.img》](https://blog.csdn.net/guyongqiangx/article/details/132581720)
> - [《Android OTA 相关工具(七) 使用 lpunpack 解包 super.img》](https://blog.csdn.net/guyongqiangx/article/details/132598451)
> - [《Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img》]()



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/



## 1. lpadd 的编译

lpmake 工具从 Android Q 版代码开始引入，源码位于 `system/extras/partition_tools` 目录下，默认编译 Android 后输出到 `out/host/linux-x86/bin/lpmake` ，第一次编译以后，通过 source 和 lunch 操作设置 Android 编译环境后就可以引用。

例如:

```bash
$ source build/envsetup.sh 
$ lunch aosp_panther-userdebug
$ which lpunpack 
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpunpack
```



当然，也可以将 `out/host/linux-x86/bin` 添加到当前目录下使用：

```bash
$ echo $PATH
/home/rocky/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$ export PATH=${PWD}/out/host/linux-x86/bin:$PATH
$ echo $PATH
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin:/home/rocky/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$ which lpunpack 
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpunpack
```



两种方式都差不多，不过个人推荐前者。

## 2. lpadd 的帮助信息

lpunpack 的帮助信息非常简单：

```bash
android-13.0.0_r41$ lpunpack -h
lpunpack - command-line tool for extracting partition images from super

Usage:
  lpunpack [options...] SUPER_IMAGE [OUTPUT_DIR]

Options:
  -p, --partition=NAME     Extract the named partition. This can
                           be specified multiple times.
  -S, --slot=NUM           Slot number (default is 0).
```





## 3. lpadd 的用法





## 4. 其它

- 到目前为止，我写过 Android OTA 升级相关的话题包括：
  - 基础入门：[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html)系列
  - 核心模块：[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html) 系列
  - 动态分区：[《Android 动态分区》](https://blog.csdn.net/guyongqiangx/category_12140166.html) 系列
  - 虚拟 A/B：[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列
  - 升级工具：[《Android OTA 相关工具》](https://blog.csdn.net/guyongqiangx/category_12211864.html)系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题，此群仅限专栏订阅者参与~

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。






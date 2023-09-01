# 20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img

我一直以为没有人会使用 lpadd 工具，就像我以为没有人会去使用 lpmake 手动生成 super.img 一样。

然鹅，真的有小伙伴使用 lpadd 和 lpmake 去学习和了解 super.img。话说 lpadd 和 lpmake 还真是一个修改 super.img 的好工具。





前几篇分别介绍了 lpdump, lpmake 和 lpunpack，本篇介绍 lpadd。

本文基于 android-13.0.0_r41 编译生成的 lpadd 介绍该工具的使用，但也适用于 Android 11 (R)) 开始的其它 Android 版本。



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

lpadd 工具从 Android 11(R) 后引入的逻辑分区工具，源码位于 `system/extras/partition_tools` 目录下，默认不会编译 lpadd。

由于 lpadd 只支持在 host 上运行，所以如果需要编译 lpadd，需要将其添加到 `PRODUCT_HOST_PACKAGES` 中：

```makefile
PRODUCT_HOST_PACKAGES += lpadd
```



我这里使用 Android 参考设备 panther 进行编译，修改如下：

```bash
android-13.0.0_r41$ repo diff device/google/pantah/device-panther.mk 
project device/google/pantah/
diff --git a/device-panther.mk b/device-panther.mk
index 3c61c6d..e9e2f6c 100644
--- a/device-panther.mk
+++ b/device-panther.mk
@@ -143,6 +143,8 @@ PRODUCT_PROPERTY_OVERRIDES += \
 PRODUCT_PACKAGES += \
        libspatialaudio
 
+PRODUCT_HOST_PACKAGES += lpadd 
+
 # Bluetooth hci_inject test tool
 PRODUCT_PACKAGES_DEBUG += \
     hci_inject
```

进行以上修改后，再编译。



除了这种办法外，也可以直接在根目录下使用 mmm 编译 lpadd 所在的 partition_tools 模块:

```bash
android-13.0.0_r41$ mmm system/extras/partition_tools
android-13.0.0_r41$ which lpadd
/local/public/users/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpadd
```



编译 Android 后输出到 `out/host/linux-x86/bin/lpadd` ，第一次编译以后，通过 source 和 lunch 操作设置 Android 编译环境后就可以引用。

例如:

```bash
$ source build/envsetup.sh 
$ lunch aosp_panther-userdebug
$ which lpadd 
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpadd
```



当然，也可以将 `out/host/linux-x86/bin` 添加到当前目录下使用：

```bash
$ echo $PATH
/home/rocky/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$ export PATH=${PWD}/out/host/linux-x86/bin:$PATH
$ echo $PATH
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin:/home/rocky/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$ which lpadd 
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpadd
```



两种方式都差不多，不过个人推荐前者。

## 2. lpadd 的帮助信息

lpadd 工具自带的帮助信息：

```bash
android-13.0.0_r41$ lpadd -h
lpadd - command-line tool for adding partitions to a super.img

Usage:
 lpadd [options] SUPER PARTNAME PARTGROUP [IMAGE]

  SUPER                         Path to the super image. It can be sparsed or
                                unsparsed. If sparsed, it will be unsparsed
                                temporarily and re-sparsed over the original
                                file. This will consume extra space during the
                                execution of lpadd.
  PARTNAME                      Name of the partition to add.
  PARTGROUP                     Name of the partition group to use. If the
                                partition can be updated over OTA, the group
                                should match its updatable group.
  IMAGE                         If specified, the contents of the given image
                                will be added to the super image. If the image
                                is sparsed, it will be temporarily unsparsed.
                                If no image is specified, the partition will
                                be zero-sized.

Extra options:
  --readonly                    The partition should be mapped read-only.
  --replace                     The partition contents should be replaced with
                                the input image.

```

除了上面的 help 信息，Android 源码中自带的文档 `system/extras/partition_tools/README.md` 也包含了对 lpadd 的一些解释说明，如下：

![1693458967(1)](images-20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img/1693458967(1).png)

## 3. lpadd 的用法

### 3.1 添加新分区和镜像

### 3.2 添加新分区到分区组

### 3.3 更新现有分区镜像 



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






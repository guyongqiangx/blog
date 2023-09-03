# 20230829-Android OTA 相关工具(九) 使用 lpflash 往 super 分区写入镜像

前几篇分别介绍了 lpdump, lpmake, lpunpack 和 lpadd。

既然已经有了 lpadd，可以添加分区，并将相应的镜像写入到 super.img 中为什么还需要一个 lpflash 呢？

这是因为 lpadd 只能在 host 主机上执行，而不能在 device 设备上运行。所以如果设备已经起来以后，需要写入分区镜像，就可以通过 lpflash 来执行。



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
> - [《Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img》](https://blog.csdn.net/guyongqiangx/article/details/132635213)



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/



## 1. lpflash 的编译

编译 Android 镜像时默认不会编译 lpflash，所以如果需要 lpflash 工具，需要将其添加到 `PRODUCT_PACKAGES` 中：

```makefile
PRODUCT_PACKAGES += lpflash

```



我这里使用 Android 参考设备 panther 进行编译，修改如下：

```bash
$ repo diff device/google/pantah/device-panther.mk 
project device/google/pantah/
diff --git a/device-panther.mk b/device-panther.mk
index 3c61c6d..56aab22 100644
--- a/device-panther.mk
+++ b/device-panther.mk
@@ -143,6 +143,10 @@ PRODUCT_PROPERTY_OVERRIDES += \
 PRODUCT_PACKAGES += \
        libspatialaudio
 
+PRODUCT_HOST_PACKAGES += lpadd 
+
+PRODUCT_PACKAGES += lpflash
+
 # Bluetooth hci_inject test tool
 PRODUCT_PACKAGES_DEBUG += \
     hci_inject
```

进行以上修改后，再编译。



或者直接在设置了环境以后编译 partition_tools 所有工具:

```bash
```

除了这种办法外，也可以直接在根目录下使用 mmm 编译 lpadd 所在的 partition_tools 模块:

```bash
android-13.0.0_r41$ mmm system/extras/partition_tools
android-13.0.0_r41$ which lpflash
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpflash
```



## 2. lpflash 的帮助信息



## 3. lpflash 的用法



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


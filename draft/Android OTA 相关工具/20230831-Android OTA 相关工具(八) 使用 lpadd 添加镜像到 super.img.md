# 20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img

我一直以为没有人会使用 lpadd 工具，就像我以为没有人会去使用 lpmake 手动生成 super.img 一样。

然鹅，真的有小伙伴使用 lpadd 和 lpmake 去学习和了解 super.img。

![lpadd-not-found](images-20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img/lpadd-not-found.jpg)

话说 lpmake 和 lpadd 还真是一个学习 super.img 的好工具，要是再有一个 lpdelete/remove 就更好了。当然，这些都是非常低频甚至几乎不会用到的小工具，以至于在上一篇提到的 lpunpack 中有 bug 也一直没有修复。

> 其实 lpmake 在官方代码的 README.md 中介绍的命令也是有 bug 的。



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
> - [《Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img》](https://blog.csdn.net/guyongqiangx/article/details/132635213)



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/132635213



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

![lpadd official description](images-20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img/lpadd-official-doc.png)

按照 Android 官方文档的说法，在我看来有以下重点：

- lpadd 可以用来往 super.img 中添加分区镜像文件，或者往 super_empty.img 中添加分区。有利于在各种分开或者混合编译的情况，例如 radio.img 和 system.img 由不同的部门或公司管理的不同的代码编译，但都希望最后添加到一个 super.img 中。
- 增加的分区名字 PART_NAME 必须是还没有存在的。
- 不能往 super_empty.img 中添加分区镜像文件。
- lpadd 会消耗大量 TMPDIR 空间，所以如果默认的 TMPDIR 不够空间的话，通过命令行变量 TMPDIR 临时指定一个位置。

## 3. lpadd 的用法

### 3.1 准备工作

为了方便演示，我这里手动生成了 3 个名为 rocky 的 super 设备镜像，分别是：

- empty 的 super 设备镜像: rocky_empty.img
- raw 格式的 super 设备镜像: rocky_raw.img
- sparse 格式的 super 设备镜像: rocky_sparse.img

super 设备的大小为 10G (10000M):

- 包含 2 个大小为 4G(4000M)的 "guyognqiangx_a", "guyongqiangx_b" 以及默认 "default" 分组 group
- 分组 "guyognqiangx_a" 和 "guyongqiangx_b" 分别包含大小为 20M 的 "boot_a" 和 "boot_b"
- 默认分组 "default" 包含一个大小为 100M 的 "radio" 分组

另外，我是基于 `android-13.0.0_r41` 上编译谷歌的 panther 设备进行这个实验的，如果下载代码和编译 panther，请参考手把手文章[《如何下载和编译 Android 源码？》](https://blog.csdn.net/guyongqiangx/article/details/132125431)

因为制作 raw 格式和 sparse 格式镜像时，指定的分区需要先转换成 sparse 格式，所以我这里把 radio.img 和 system.img 转换成了 sparse 格式的 sradio.img 和 ssystem.img:

```bash
$ img2simg out/target/product/panther/radio.img sradio.img 
$ img2simg out/target/product/panther/system.img ssystem.img 
$ ls -lh out/target/product/panther/{radio,system}.img {sradio,ssystem}.img
-rw-r--r-- 1 rocky users  77M Aug 16 00:29 out/target/product/panther/radio.img
-rw-r--r-- 1 rocky users 846M Aug 16 00:58 out/target/product/panther/system.img
-rw-r--r-- 1 rocky users  68M Sep  2 09:36 sradio.img
-rw-r--r-- 1 rocky users 843M Sep  2 09:36 ssystem.img
```



#### empty 的 super 设备镜像

不包含任何分区镜像

```bash
$ lpmake --device-size 10485760000 \
        --metadata-size 65536     \
        --metadata-slots 2        \
        -g guyongqiangx_a:4194304000 \
        -g guyongqiangx_b:4194304000 \
        -p "radio:readonly:104857600" \
        -p "boot_a:none:2197520:guyongqiangx_a" \
        -p "boot_b:none:2197520:guyongqiangx_b" \
        -o rocky_empty.img
```



#### raw 格式的 super 设备镜像

"default" 组内的 "radio" 分区使用镜像 "sradio.img"

```bash
$ lpmake --device-size 10485760000 \
       --metadata-size 65536     \
       --metadata-slots 2        \
       -g guyongqiangx_a:4194304000 \
       -g guyongqiangx_b:4194304000 \
       -p "radio:readonly:104857600" \
       -i "radio=sradio.img" \
       -p "boot_a:none:2197520:guyongqiangx_a" \
       -p "boot_b:none:2197520:guyongqiangx_b" \
       -o rocky_raw.img
```



#### sparse 格式的 super 设备镜像

- "default" 组内的 "radio" 分区使用镜像 "sradio.img"
- "guyongqiangx_a" 组内的 "system_a" 分区使用镜像 "ssystem.img"
- 使用 "-S" 指定输出 sparse 格式的镜像

```bash
$ lpmake --device-size 10485760000 \
       --metadata-size 65536     \
       --metadata-slots 2        \
       -g guyongqiangx_a:4194304000 \
       -g guyongqiangx_b:4194304000 \
       -p "radio:readonly:104857600" \
       -i "radio=sradio.img" \
       -p "system_a:readonly:1048576000:guyongqiangx_a" \
       -i "system_a=ssystem.img" \
       -p "boot_a:none:2197520:guyongqiangx_a" \
       -p "boot_b:none:2197520:guyongqiangx_b" \
       -S -o rocky_sparse.img
```



三种格式的分区镜像添加完成以后，可以使用 lpdump 查看分区镜像情况。

后续操作主要使用 raw 格式的分区镜像 rocky_raw.img。



### 3.1 lpadd 分区操作示例

> 建议: 在下面的各个 lpmake 和 lpadd 的步骤完成后，建议再使用 lpdump 或 lpunpack 来检查 lpadd 的结果，以加深对 lpadd 和 super 动态分区设备的理解。



rocky_raw.img 的 "guyongqiangx_a" 组内添加新分区 "vendor_a"和镜像:

```
$ lpadd rocky_raw.img vendor_a guyongqiangx_a out/target/product/panther/vendor.img
```



在 "guyognqiangx_a" 分组内添加 readonly 的分区 "radio_a"

```bash
$ lpadd rocky_raw.img --readonly radio_a guyongqiangx_a
```



在上一步的基础上，直接给 radio_a 分区添加镜像失败，需要使用 "--replace" 选项添加分区镜像:

```bash
$ lpadd rocky_raw.img radio_a guyongqiangx_a out/target/product/panther/radio.img
[liblp]Attempting to create duplication partition with name: radio_a
Could not add partition: radio_a
$ lpadd rocky_raw.img --replace radio_a guyongqiangx_a out/target/product/panther/radio.img
Writing data for partition radio_a...
Done.
```

> 因为默认使用 lpadd 时默认是向 super 设备添加新分区，如果分区已经存在，需要更新分区镜像，则需要使用 "--replace" 选项。



将 radio_a 分区镜像从原来的 radio.img 替换为 bootloader.img:

```bash
$ lpadd rocky_raw.img --replace radio_a guyongqiangx_a out/target/product/panther/bootloader.img
Writing data for partition radio_a...
Done.
```



直接给 empty 的 super 设备添加分区和镜像会失败:

```bash
$ lpadd rocky_empty.img radio_a guyongqiangx_a out/target/product/panther/radio.img
Cannot add a partition image to an empty super file.
```

但是可以给 empty 的 super 设备添加分区:

```bash
$ lpadd rocky_empty.img radio_a guyongqiangx_a
Done.
```



> 对于逻辑分区的管理，再添加一个 lpdelete 或者 lpremove 来从 super 设备移除分区就完美了，因为这样整个分区的增删改查操作就都具备了，可惜没有~

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






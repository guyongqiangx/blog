# 20230829-Android OTA 相关工具(六)  使用 lpmake 打包生成 super.img

我在 [《Android 动态分区详解(二) 核心模块和相关工具介绍》](https://blog.csdn.net/guyongqiangx/article/details/123931356) 介绍过 lpmake 工具的使用，这里再专门开一篇详解介绍下 lpmake 工具。



> [《Android OTA 相关工具》](https://blog.csdn.net/guyongqiangx/category_12211864.html)系列，文章列表：
>
> - [《Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl》](https://blog.csdn.net/guyongqiangx/article/details/129122159)
> - [《Android OTA 相关工具(二) 动态分区之 dmctl》](https://blog.csdn.net/guyongqiangx/article/details/129229115)
> - [《Android OTA 相关工具(三) A/B 系统之 bootctl 工具》](https://blog.csdn.net/guyongqiangx/article/details/129310109)
> - [《Android OTA 相关工具(四) 查看 payload 文件信息》](https://blog.csdn.net/guyongqiangx/article/details/129228856)
> - [《Android OTA 相关工具(五) 使用 lpdump 查看动态分区》](https://blog.csdn.net/guyongqiangx/article/details/129785777)



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/



## 1. lpmake 的编译



## 2. lpmake 的帮助信息

```bash
android-13.0.0_r41$ lpmake help
lpmake - command-line tool for creating Android Logical Partition images.

Usage:
  lpmake [options]

Required options:
  -d,--device-size=[SIZE|auto]  Size of the block device for logical partitions.
                                Can be set to auto to automatically calculate the
                                minimum size, the sum of partition sizes plus
                                metadata-size times the number of partitions.
  -m,--metadata-size=SIZE       Maximum size to reserve for partition metadata.
  -s,--metadata-slots=COUNT     Number of slots to store metadata copies.
  -p,--partition=DATA           Add a partition given the data, see below.
  -o,--output=FILE              Output file.

Optional:
  -b,--block-size=SIZE          Physical block size, defaults to 4096.
  -a,--alignment=N              Optimal partition alignment in bytes.
  -O,--alignment-offset=N       Alignment offset in bytes to device parent.
  -S,--sparse                   Output a sparse image for fastboot.
  -i,--image=PARTITION=FILE     If building a sparse image for fastboot, include
                                the given file (or sparse file) as initial data for
                                the named partition.
  -g,--group=GROUP:SIZE         Define a named partition group with the given
                                maximum size.
  -D,--device=DATA              Add a block device that the super partition
                                spans over. If specified, then -d/--device-size
                                and alignments must not be specified. The format
                                for DATA is listed below.
  -n,--super-name=NAME          Specify the name of the block device that will
                                house the super partition.
  -x,--auto-slot-suffixing      Mark the block device and partition names needing
                                slot suffixes before being used.
  -F,--force-full-image         Force a full image to be written even if no
                                partition images were specified. Normally, this
                                would produce a minimal super_empty.img which
                                cannot be flashed; force-full-image will produce
                                a flashable image.
  --virtual-ab                  Add the VIRTUAL_AB_DEVICE flag to the metadata
                                header. Note that the resulting super.img will
                                require a liblp capable of parsing a v1.2 header.

Partition data format:
  <name>:<attributes>:<size>[:group]
  Attrs must be 'none' or 'readonly'.

Device data format:
  <partition_name>:<size>[:<alignment>:<alignment_offset>]
  The partition name is the basename of the /dev/block/by-name/ path of the
  block device. The size is the device size in bytes. The alignment and
  alignment offset parameters are the same as -a/--alignment and 
  -O/--alignment-offset.
```



## 3. lpmake 的用法

Android 编译时，`build_super_image.py` 脚本会准备命令并调用 lpmake 生成 super.img，直接在 Android 编译的 log 中搜索 lpmake 就可以看到详细的命令。

这里以 Android 13 中编译参考设备 panther 为例，看看 `build_super_image.py` 是如何调用 lpmake 的:

```bash
$ source build/envsetup.sh 
$ lunch aosp_panther-userdebug
$ make dist -j80 2>&1 | tee make-dist.log
$ grep -ni lpmake make-dist.log
56:2023-08-30 02:26:10 - common.py - INFO    :   Running: "/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpmake --metadata-size 65536 --super-name super --metadata-slots 3 --virtual-ab --device super:8531214336 --group google_dynamic_partitions_a:8527020032 --group google_dynamic_partitions_b:8527020032 --partition system_a:readonly:886816768:google_dynamic_partitions_a --image system_a=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img --partition system_b:readonly:27312128:google_dynamic_partitions_b --image system_b=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system_other.img --partition system_dlkm_a:readonly:348160:google_dynamic_partitions_a --image system_dlkm_a=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system_dlkm.img --partition system_dlkm_b:readonly:0:google_dynamic_partitions_b --partition system_ext_a:readonly:301395968:google_dynamic_partitions_a --image system_ext_a=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system_ext.img --partition system_ext_b:readonly:0:google_dynamic_partitions_b --partition product_a:readonly:368046080:google_dynamic_partitions_a --image product_a=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/product.img --partition product_b:readonly:0:google_dynamic_partitions_b --partition vendor_a:readonly:621752320:google_dynamic_partitions_a --image vendor_a=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/vendor.img --partition vendor_b:readonly:0:google_dynamic_partitions_b --partition vendor_dlkm_a:readonly:43040768:google_dynamic_partitions_a --image vendor_dlkm_a=out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:google_dynamic_partitions_b --sparse --output out/target/product/panther/obj/PACKAGING/super.img_intermediates/super.img"
```



这里因为分区很多，所以 lpmake 的命令参数非常长，手动对这个 lpmake 命令整理一下会清楚很多:

```shell
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpmake \
	--metadata-size 65536 \
	--super-name super \
	--metadata-slots 3 \
	--virtual-ab \
	--device super:8531214336 \
	--group google_dynamic_partitions_a:8527020032 \
	--group google_dynamic_partitions_b:8527020032 \
	--partition system_a:readonly:886816768:google_dynamic_partitions_a \
	--image system_a=out/target/product/panther/system.img \
	--partition system_b:readonly:27312128:google_dynamic_partitions_b \
	--image system_b=out/target/product/panther/system_other.img \
	--partition system_dlkm_a:readonly:348160:google_dynamic_partitions_a \
	--image system_dlkm_a=out/target/product/panther/system_dlkm.img \
	--partition system_dlkm_b:readonly:0:google_dynamic_partitions_b \
	--partition system_ext_a:readonly:301395968:google_dynamic_partitions_a \
	--image system_ext_a=out/target/product/panther/system_ext.img \
	--partition system_ext_b:readonly:0:google_dynamic_partitions_b \
	--partition product_a:readonly:368046080:google_dynamic_partitions_a \
	--image product_a=out/target/product/panther/product.img \
	--partition product_b:readonly:0:google_dynamic_partitions_b \
	--partition vendor_a:readonly:621752320:google_dynamic_partitions_a \
	--image vendor_a=out/target/product/panther/vendor.img \
	--partition vendor_b:readonly:0:google_dynamic_partitions_b \
	--partition vendor_dlkm_a:readonly:43040768:google_dynamic_partitions_a \
	--image vendor_dlkm_a=out/target/product/panther/vendor_dlkm.img \
	--partition vendor_dlkm_b:readonly:0:google_dynamic_partitions_b \
	--sparse \
	--output out/target/product/panther/super.img
```

> 这里我把 `--image` 的路径进行了简化，将类似下面这样的完整路径:
>
> `out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/system.img`
>
> 使用另外一个比较简短的路径替代:
>
> `out/target/product/panther/system.img`



说下这里 lpmake 命令的参数重点：

- `--metadata-size 65536`
- `--super-name super`
- `--metadata-slots 3`
- `--virtual-ab`
- `--device super:8531214336`
- `--group google_dynamic_partitions_a:8527020032`
- `--partition system_a:readonly:886816768:google_dynamic_partitions_a`
- `--image system_a=out/target/product/panther/system.img`
- `--sparse`
- `--output out/target/product/panther/super.img`



## 4. 几个思考题

到这里差不多应该结束了，给大家留三个思考题：

1. `system.img` 和 `system_other.img`

仔细观察上面第 3 节 lpmake 的命令中，`system_a` 分区和 `system_b` 分区传入的镜像文件竟然不一样:

```bash
/public/rocky/android-13.0.0_r41/out/host/linux-x86/bin/lpmake \
	--metadata-size 65536 \
	--super-name super \
	--metadata-slots 3 \
	--virtual-ab \
	--device super:8531214336 \
	--group google_dynamic_partitions_a:8527020032 \
	--group google_dynamic_partitions_b:8527020032 \
	--partition system_a:readonly:886816768:google_dynamic_partitions_a \
	--image system_a=out/target/product/panther/system.img \
	--partition system_b:readonly:27312128:google_dynamic_partitions_b \
	--image system_b=out/target/product/panther/system_other.img \
	...
	--sparse \
	--output out/target/product/panther/super.img
```

其中:

- `system_a` 的 image 为: `out/target/product/panther/system.img`
- `system_b` 的 image 为: `out/target/product/panther/system_other.img`

按照我的理解是 `system_a` 和 `system_b` 分区，制作镜像时可以提供一样的文件，或者像其他分区一样，`system_b` 不提供任何文件，仅保留一个空分区记录。

但为什么这里会传递 `system_other.img` 给 `system_b` 分区呢？

镜像文件 `system_other.img` 和 `system.img` 有什么区别？



2. 按照我上面的方法，研究下 `super_empty.img` 是如何生成的？

3. 为什么这位群友生成的 `super.img` 只有几十 K?





## 5. 其它

- 到目前为止，我写过 Android OTA 升级相关的话题包括：
  - 基础入门：[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html)系列
  - 核心模块：[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html) 系列
  - 动态分区：[《Android 动态分区》](https://blog.csdn.net/guyongqiangx/category_12140166.html) 系列
  - 虚拟 A/B：[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列
  - 升级工具：[《Android OTA 相关工具》](https://blog.csdn.net/guyongqiangx/category_12211864.html)系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题。

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。


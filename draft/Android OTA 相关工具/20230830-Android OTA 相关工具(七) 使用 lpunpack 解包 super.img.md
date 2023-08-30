# 20230829-Android OTA 相关工具(七) 使用 lpunpack 解包 super.img

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
> - [《Android OTA 相关工具(七) 使用 lpunpack 解包 super.img》]()



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/



## 1. lpunpack 的编译

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

## 2. lpunpack 的帮助信息

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



直接将 raw 格式的 super 镜像解包到指定的输出目录。

> lpunpack 不能识别 sparse 镜像格式，所以如果 super.img 是 sparse 格式，则需要先将其转换成 raw 格式。



有两个可选参数"--partition" 和 "--slot"，分别用于指定提取镜像的分区名称(name)和槽位(slot)，如果没有提供选项参数，则默认提取所有存在的分区镜像。



## 3. lpunpack 的用法

从上一节的帮助信息可以看到，lpunpack 的用法比较简单，主要分成两步：

1. 将 sparse 格式的 super.img 转换成 raw 格式
2. 提取 raw 格式的 super.img 内部的分区镜像



这里以 android-13.0.0_r41 代码编译参考设备 panther 得到的 super.img 为例演示 lpunpack 的操作



准备工作：

```bash
# 设置环境
$ source build/envsetup.sh 
$ lunch aosp_panther-userdebug

# 编译 dist 输出
$ make dist -j80

# 查找系统的 super.img 镜像
$ find out -type f -name super.img
out/target/product/panther/obj/PACKAGING/super.img_intermediates/super.img
out/dist/super.img

# 把 dist 下的 sparse 格式的 super.img 转换成 raw 格式
$ file out/dist/super.img 
out/dist/super.img: Android sparse image, version: 1.0, Total of 2082816 4096-byte output blocks in 159 input chunks.

# 使用 simg2img 将 sparse 格式转换成 raw 格式
$ simg2img out/dist/super.img super_raw.img 

# 查看 super 分区的信息
$ lpdump super_raw.img 
Slot 0:
Metadata version: 10.2
Metadata size: 1256 bytes
Metadata max size: 65536 bytes
Metadata slot count: 3
Header flags: virtual_ab_device
Partition table:
------------------------
  Name: system_a
  Group: google_dynamic_partitions_a
  Attributes: readonly
  Extents:
    0 .. 1732063 linear super 2048
------------------------
  Name: system_b
  Group: google_dynamic_partitions_b
  Attributes: readonly
  Extents:
    0 .. 53343 linear super 1734656
------------------------
  Name: system_dlkm_a
  Group: google_dynamic_partitions_a
  Attributes: readonly
  Extents:
    0 .. 679 linear super 1789952
------------------------
  Name: system_dlkm_b
  Group: google_dynamic_partitions_b
  Attributes: readonly
  Extents:
------------------------
  Name: system_ext_a
  Group: google_dynamic_partitions_a
  Attributes: readonly
  Extents:
    0 .. 588663 linear super 1792000
------------------------
  Name: system_ext_b
  Group: google_dynamic_partitions_b
  Attributes: readonly
  Extents:
------------------------
  Name: product_a
  Group: google_dynamic_partitions_a
  Attributes: readonly
  Extents:
    0 .. 718839 linear super 2381824
------------------------
  Name: product_b
  Group: google_dynamic_partitions_b
  Attributes: readonly
  Extents:
------------------------
  Name: vendor_a
  Group: google_dynamic_partitions_a
  Attributes: readonly
  Extents:
    0 .. 1214359 linear super 3100672
------------------------
  Name: vendor_b
  Group: google_dynamic_partitions_b
  Attributes: readonly
  Extents:
------------------------
  Name: vendor_dlkm_a
  Group: google_dynamic_partitions_a
  Attributes: readonly
  Extents:
    0 .. 84063 linear super 4315136
------------------------
  Name: vendor_dlkm_b
  Group: google_dynamic_partitions_b
  Attributes: readonly
  Extents:
------------------------
Super partition layout:
------------------------
super: 2048 .. 1734112: system_a (1732064 sectors)
super: 1734656 .. 1788000: system_b (53344 sectors)
super: 1789952 .. 1790632: system_dlkm_a (680 sectors)
super: 1792000 .. 2380664: system_ext_a (588664 sectors)
super: 2381824 .. 3100664: product_a (718840 sectors)
super: 3100672 .. 4315032: vendor_a (1214360 sectors)
super: 4315136 .. 4399200: vendor_dlkm_a (84064 sectors)
------------------------
Block device table:
------------------------
  Partition name: super
  First sector: 2048
  Size: 8531214336 bytes
  Flags: none
------------------------
Group table:
------------------------
  Name: default
  Maximum size: 0 bytes
  Flags: none
------------------------
  Name: google_dynamic_partitions_a
  Maximum size: 8527020032 bytes
  Flags: none
------------------------
  Name: google_dynamic_partitions_b
  Maximum size: 8527020032 bytes
  Flags: none
------------------------
```



总结下 super 分区内的镜像内容:

- 槽位 A 中包含 system_a, system_dlkm_a, system_ext_a, product_a, vendor_a 和 vendor_dlkm_a 镜像
- 槽位 B 中包含 system_b 镜像(大小和 system_a 的镜像不一样)



> 关于如何下载 Android 代码并基于 Google 官方的参考设备进行编译，请参考：
>
> [《如何下载和编译 Android 源码？》](https://blog.csdn.net/guyongqiangx/article/details/13212543)



### 1. 解包所有镜像

不带参数解包所有分区镜像。

```bash
$ mkdir temp
$ lpunpack super_raw.img temp/
$ ls -lh temp/
total 2.1G
-rw-r--r-- 1 rocky users 351M Aug 29 14:09 product_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 product_b.img
-rw-r--r-- 1 rocky users 846M Aug 29 14:09 system_a.img
-rw-r--r-- 1 rocky users  27M Aug 29 14:09 system_b.img
-rw-r--r-- 1 rocky users 340K Aug 29 14:09 system_dlkm_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 system_dlkm_b.img
-rw-r--r-- 1 rocky users 288M Aug 29 14:09 system_ext_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 system_ext_b.img
-rw-r--r-- 1 rocky users 593M Aug 29 14:09 vendor_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 vendor_b.img
-rw-r--r-- 1 rocky users  42M Aug 29 14:09 vendor_dlkm_a.img
-rw-r--r-- 1 rocky users    0 Aug 29 14:09 vendor_dlkm_b.img
```



### 2. 解包指定名称分区镜像

使用 "-p" 参数解包单个分区 system_a 的镜像：

```bash
$ rm -rf temp/*
$ lpunpack -p system_a super_raw.img temp/
$ ls -lh temp/
total 843M
-rw-r--r-- 1 rocky users 846M Aug 30 19:48 system_a.img
```



使用多个 "-p" 参数解包多个分区(system_a 和 vendor_a)镜像：

```bash
$ rm -rf temp/*
$ lpunpack -p system_a -p vendor_a super_raw.img temp/
$ ls -lh temp/
total 1.5G
-rw-r--r-- 1 rocky users 846M Aug 30 19:50 system_a.img
-rw-r--r-- 1 rocky users 593M Aug 30 19:50 vendor_a.img
```



### 3. 解包指定槽位分区镜像

使用 "-s" 选项指定槽位，解包单个槽位镜像。

```bash
```






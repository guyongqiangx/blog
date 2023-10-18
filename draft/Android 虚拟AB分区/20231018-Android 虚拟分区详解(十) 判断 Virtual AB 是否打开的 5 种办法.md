# 20231018-Android 虚拟 A/B 详解(十) 判断 Virtual A/B 是否打开的 5 种办法.md

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 原文链接：



> Android 虚拟 A/B 分区[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列，更新中，文章列表：
>
> - [Android 虚拟 A/B 详解(一) 参考资料推荐](https://blog.csdn.net/guyongqiangx/article/details/128071692)
> - [Android 虚拟 A/B 详解(二) 虚拟分区布局](https://blog.csdn.net/guyongqiangx/article/details/128167054)
> - [Android 虚拟 A/B 详解(三) 分区状态变化](https://blog.csdn.net/guyongqiangx/article/details/128517578)
> - [Android 虚拟 A/B 详解(四) 编译开关](https://blog.csdn.net/guyongqiangx/article/details/128567582)
> - [Android 虚拟 A/B 详解(五) BootControl 接口的变化](https://blog.csdn.net/guyongqiangx/article/details/128824984)
> - [Android 虚拟 A/B 详解(六) 升级中的状态数据保存在哪里？](https://blog.csdn.net/guyongqiangx/article/details/129094203)
> - [Android 虚拟 A/B 详解(七) 升级中用到了哪些标识文件？](https://blog.csdn.net/guyongqiangx/article/details/129098176)
> - [Android 虚拟 A/B 详解(八) cow 的大小是如何计算的？](https://blog.csdn.net/guyongqiangx/article/details/129470881)
> - [Android 虚拟 A/B 详解(九) cow 的存储是如何分配的？](https://blog.csdn.net/guyongqiangx/article/details/129494397)
>
> 对 linux 快照(snapshot) 的了解可以增加对虚拟 A/B 分区的理解：
>
> - [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
> - [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

## 0. 导读

这是一篇临时加入的文章，计划中的第十篇并不是准备分析这个，只不过因为时常会有小伙伴在 OTA 讨论群和专栏答疑群里问如何判断一个设备是否打开了虚拟分区(Virtual A/B)功能。

![01-question-on-virtual-ab-switch.png](images-20231018-Android 虚拟分区详解(十) 判断 Virtual AB 是否打开的 5 种办法/01-question-on-virtual-ab-switch.png)

**图 1. 如何判断设备开启了虚拟 AB 的问题**



本文总结我知道的 5 种办法，主要分成 3 中情况。

1. 从源码判断
2. 从编译输出判断
3. 从 image 镜像文件判断
4. 从 payload 文件判断
5. 从运行的设备判断



## 1. Virtual A/B 的开关

[《Android 虚拟 A/B 详解(四) 编译开关》](https://blog.csdn.net/guyongqiangx/article/details/128567582)一文详细分析过 Virtual A/B 的编译开关，以及这些编译开关是如何起作用的。现在简单总结如下：

### 1.1 编译开关

对于原生设备：

```make
PRODUCT_VIRTUAL_AB_OTA := true
```

对于升级改造设备：

```make
PRODUCT_VIRTUAL_AB_OTA := true
PRODUCT_VIRTUAL_AB_OTA_RETROFIT := true
```



### 1.2 编译开关的定义位置

对于 Android 11(R)，上面这些开关位于以下文件中:

```
build/make/target/product/virtual_ab_ota.mk
build/make/target/product/virtual_ab_ota_retrofit.mk
```

对于 Android 12(S) 和 Android 13(T)，以及 Android 14(U), 上面这些开关位于以下目录中：

```bash
build/make/target/product/virtual_ab_ota
```



### 1.3 编译开关的作用

基于上面的编译开关，在系统编译时，会设置只读属性：

```make
ro.virtual_ab.enabled=true
```

同时在生成 super 分区镜像时，会往头部的 metadata 数据的 LpMetadataHeader 结构中写入标记 “`LP_HEADER_FLAG_VIRTUAL_AB_DEVICE`"



如果对这些开关的设置，编译的作用，以及最终用途的细节感兴趣，请转到[《Android 虚拟 A/B 详解(四) 编译开关》](https://blog.csdn.net/guyongqiangx/article/details/128567582)查看详细分析。



## 2. Virtual A/B 开关检查

### 方法 1. 从源码判断

仔细观察上面 1.1 节以及 1.2 节中开关和位置，不论是哪一个都包含字符串 "VIRTUAL_AB_OTA" 或 "virtual_ab_ota" 的其中一个。而且巧了，这两个字符串刚好是大小写关系。

所以，我们可以使用 grep 工具搜索源码 device 目录下文件中的字符串 "virtual_ab_ota" 来确定是否打开了 Virtual A/B。

#### 示例 1. Broadcom 平台

这里以 Broadcom 某产品的 Android 11(R) 代码为例，直接使用命令:

```bash
grep -rni virtual_ab_ota device/broadcom -C 5
```

搜索 `device/broadcom` 目录：

![02-virtual-ab-on-broadcom.png](images-20231018-Android 虚拟分区详解(十) 判断 Virtual AB 是否打开的 5 种办法/02-virtual-ab-on-broadcom.png)

**图 2. 在 Broadcom 平台上查找 virtual_ab_ota 示例**



这里看到在文件 `device/broadcom/common/headed.mk` 第 70 的地方有包含 `virtual_ab_ota.mk` 文件，到这里有两个办法进行检查：

1. 检查外层的两个开关 `HW_AB_UPDATE_SUPPORT` 和 `HW_VIRT_AB_UPDATE_SUPPORT` 是否打开
2. 在第 70 行的地方使用 info 或 warnning 指令打印消息或认为制造一个编译错误，看是否走到这里



#### 示例 2. Google 平台

这里以 AOSP 的 android-13.0.0_r41 版本源码为例，使用 grep 搜索 `device/google` 目录:

```bash
android-13.0.0_r41$ grep -rni virtual_ab_ota device
```

以下是我直接搜索 device 目录的结果：

![03-virtual-ab-on-google.png](images-20231018-Android 虚拟分区详解(十) 判断 Virtual AB 是否打开的 5 种办法/03-virtual-ab-on-google.png)

**图 3. 在 Google 平台上查找 virtual_ab_ota 示例**



然后再根据你具体的平台查看相应的 makefile 文件。



当然，你也可以搜索 device + build 目录，说不定有意外惊喜。



看到这里你可能有点失望，因为这里给出的只是线索，而不是线程的 ON/OFF 那种设置开关。不过没关系，沿着这个线索，查看外层开关或者编译一把就有答案了。



### 方法 2、从编译输出判断

由于在系统编译时，会设置只读属性：

```make
ro.virtual_ab.enabled=true
```

所以，我们就查找编译输出的文本 txt 和属性文件 *.prop 中相关的内容即可。



例如，我基于 android-13.0.0_r41 的 AOSP 源码，编译了 panther 设备，因此使用 grep 搜索 out 目录下的 txt 和 prop 文件:

```
android-13.0.0_r41$ grep -rni virtual_ab out --include=*.{prop,txt}
```

结果如下：

![04-grep-virtual-ab-in-out-dir.png](images-20231018-Android 虚拟分区详解(十) 判断 Virtual AB 是否打开的 5 种办法/04-grep-virtual-ab-in-out-dir.png)

**图 4. 在 out 目录下的 *.txt 和 *.prop 文件中查找 virtual_ab**



这下答案直接明了，在 `out/target/product/panther/misc_info.txt` 文件中直接写了:

```bash
virtual_ab=true
```



### 方法 3、从 image 镜像文件判断

要解析虚拟分区镜像，这里会用到 lpdump 工具解析 super 分区镜像，具体用法请参考 [《Android OTA 相关工具(五) 使用 lpdump 查看动态分区》](https://blog.csdn.net/guyongqiangx/article/details/129785777)



#### 示例 1. 从 super.img 判断

在解析 super.img 前需要将 super.img 从 sparse 格式转换为 raw 格式。

```bash
# 查找 out 目录下的 super*.img 文件
android-13.0.0_r41$ find out -type f -iname "super*.img"
out/target/product/panther/super_empty.img
out/target/product/panther/obj/PACKAGING/super.img_intermediates/super.img
out/target/product/panther/obj/PACKAGING/target_files_intermediates/aosp_panther-target_files-eng.rocky/IMAGES/super_empty.img
out/dist/super.img
out/dist/super_empty.img
android-13.0.0_r41$ 

# 将 super.img 从 sparse 格式转换成 raw 格式
android-13.0.0_r41$ simg2img out/dist/super.img out/dist/super_raw.img
android-13.0.0_r41$ 

# 使用 lpdump 查看 raw 格式的 super 文件
android-13.0.0_r41$ lpdump out/dist/super_raw.img 
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
    0 .. 1734111 linear super 2048
------------------------
...
```

看到了吗，lpdump 的结果里面清清楚楚的写了: `Header flags: virtual_ab_device`，说明这是一个支持 Virtual A/B 的设备。



#### 示例 2. 从 super_empty.img 判断

和解析 super.img 类似，不同的是 super_empty.img 默认就是 raw 格式，不需要转换:

```bash
android-13.0.0_r41$ lpdump out/dist/super_empty.img
Metadata version: 10.2
Metadata size: 1088 bytes
Metadata max size: 65536 bytes
Metadata slot count: 3
Header flags: virtual_ab_device
Partition table:
------------------------
  Name: system_a
  Group: google_dynamic_partitions_a
  Attributes: readonly
  Extents:
------------------------
...
```



解析 super.img 和 super_empty.img 的实质还是读取 super 分区开始的动态分区 header 数据。

> 如果 lpdump 的版本太老，不支持识别虚拟分区标识的话，这种方式会失败。



### 方法 4、从运行设备的系统属性判断

在运行的设备上检查是否支持虚拟分区的办法又有 3 种，这里检查系统属性 `ro.virtual_ab.enabled` 是最确定的一种。

#### 

在命令行检查系统的 `virtual_ab` 属性：

```bash
console:/ # getprop | grep -i virtual_ab
[ro.virtual_ab.enabled]: [true]
```



### 方法 5、从运行设备的 super 分区数据判断

#### 示例 1. 使用 lpdump 查看 super 设备的 header 标识

和方法 3 检查编译好的 super.img 一样，都是读取动态分区的 metadata 进行判断。

```bash
console:/ # lpdump /dev/block/by-name/super
Slot 1:
Metadata version: 10.2
Metadata size: 716 bytes
Metadata max size: 65536 bytes
Metadata slot count: 3
Header flags: virtual_ab_device
Partition table:
------------------------
  Name: system_b
  Group: bcm_ref_b
  Attributes: readonly,updated
  Extents:
    0 .. 2466951 linear super 2048
------------------------
```

这种方法有两点要求：

1. 设备上有 lpdump 工具
2. lpdump 工具的版本不能太老



#### 示例 2. 使用 lpdump 查看 super 设备的 cow 分区

对于升级过的设备，还可以使用 lpdump 查看 super 上是否有 cow 分区来判断是否支持 Virtual A/B。

对于 Virtual A/B 设备，升级时，会优先在 super 上开辟空间用于系统快照 cow。

所以对于升级过的设备，如果 super 上存在名字包含 cow 的分区(`system_b-cow`)，例如: 

```bash
console:/ # lpdump /dev/block/by-name/super                                
Slot 1:
Metadata version: 10.2
Metadata size: 716 bytes
Metadata max size: 65536 bytes
Metadata slot count: 3
Header flags: virtual_ab_device
Partition table:
------------------------
  Name: system_b
  Group: bcm_ref_b
  Attributes: readonly,updated
  Extents:
    0 .. 2466951 linear super 2048
------------------------
  Name: vendor_b
  Group: bcm_ref_b
  Attributes: readonly,updated
  Extents:
    0 .. 157239 linear super 2469888
------------------------
  Name: system_b-cow
  Group: cow
  Attributes: none
  Extents:
    0 .. 887 linear super 2469000
    888 .. 232767 linear super 2627128
------------------------
```

显然，这个设备支持 Virtual A/B。



## 3. 总结



根据 Virtual A/B 的 Makefile 开关，以及开关的使用流程，有很多方法可以用来检查 Virtual A/B 是否打开。

这些方法包括：

1. 检查平台的 makefile 文件
2. 检查编译输出的 misc_info.txt 或 build.prop 文件
3. 检查编译生成的 super.img 后 super_empty.img 文件
4. 检查设备上系统的 `virtual_ab` 属性
5. 检查设备上系统的 super 分区数据



我记得好像还可以通过检查升级的 payload 文件来确定，不过已经有这么多方法，就不打算再深入了。



## 4. 其它

到目前为止，我写过 Android OTA 升级相关的话题包括：

- 基础入门：《Android A/B 系统》系列
- 核心模块：《Android Update Engine 分析》 系列
- 动态分区：《Android 动态分区》 系列
- 虚拟 A/B：《Android 虚拟 A/B 分区》系列
- 升级工具：《Android OTA 相关工具》系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题。

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。


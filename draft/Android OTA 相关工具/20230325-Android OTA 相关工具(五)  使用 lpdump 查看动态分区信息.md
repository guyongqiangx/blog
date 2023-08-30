# 20230325-Android OTA 相关工具(五) 使用 lpdump 查看动态分区

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/129785777



## 0. 导读

### 0.1 背景

在 Android 10(Q) 开始引入动态分区，super 设备内的分区信息存放在头部的 lpmetadata 中，设备异常时经常需要检查分区情况，动态分区工具 lpdump 就是最常用的工具。



lpdump 默认的源码位于: `system/extras/partition_tools/lpdumpd.cc`

编译 Android 源码时，默认会编译 lpdump 的 host 和 android 两个版本，分别在 x86 PC 和 Android 设备上运行。



对于 host 版本(x86 PC)的 lpdump, 位于以下两个目录中:

- out/soong/host/linux-x86/bin/lpdump
- out/host/linux-x86/bin/lpdump

运行时需要直接指定路径，或将其路径 export 到环境变量 PATH 中。



对于 target 版本(Android 设备) 上的 lpdump, 编译后位于:

- out/target/product/xxx/system/bin/lpdump

烧写 image，设备跑起来后位于 `/system/bin/` 目录下。 



### 0.2 章节导读

如果只想了解 lpdump 的详细用法，请转到第 2 节，详细介绍了使用 lpdump 解析 super 文件和分区的各种操作；

如果很好奇系统上都有哪些地方可能会存放 lp_metadata 信息，请转到第 3 节；

如果你在 PC 上运行 lpdump 遇到了错误，请转到第 4 节，看看是不是路径的原因；



> 更多关于 Android OTA 升级相关文章的列表和内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303) 
>
> 如果您已经订阅了收费专栏，请务必加我微信，拉你进相应专栏的答疑群。

> 本文基于 Android 代码版本: android-11.0.0_r21，但后续版本也大同小异
>
> 在线代码：http://aospxref.com/android-11.0.0_r21/



## 1. lpdump 的功能

lpdump 的使用比较简单，以下就是 lpdump 工具的整个帮助信息。



```bash
console:/ # lpdump -h
lpdump - command-line tool for dumping Android Logical Partition images.

Usage:
  lpdump [-s <SLOT#>|--slot=<SLOT#>] [-j|--json] [FILE|DEVICE]

Options:
  -s, --slot=N     Slot number or suffix.
  -j, --json       Print in JSON format.
  -d, --dump-metadata-size
                   Print the space reserved for metadata to stdout
                   in bytes.
  -a, --all        Dump all slots (not available in JSON mode).
```



lpdump 接收一个 FILE 或 DEVICE 参数，可以用于：

1. 查看 lpmake 生成的非 sparse 格式文件的分区信息，例如 super_empty.img 或 super.img

   > Android 默认生成的 super.img 为 sparse 格式，需要先将其转换成 raw 格式才能使用 lpdump 工具查看

2. 查看一个带有 lpmetadata 的文件或设备的分区信息，例如 super 设备的分区信息



## 2. lpdump 用法示例

### 2.1 sparse 格式转换

lpdump 只能解析非 sparse 格式的 image，如果是在 x86 PC 上运行 lpdum 进行解析，则需要提前使用 simg2img 将 Android 编译生成的 sparse 格式的 super.img 转换成 raw 格式。

```bash
$ simg2img out/target/product/xxx/super.img out/super_raw.img
```



这里为了让后面显示的路径更短，将 raw 格式的 super 文件保存到 out 目录下。

> simg2img 的全称是 sparse image to image



### 2.2 文件解析示例

- 默认解析 Slot 0 的分区信息

  ```bash
  $ lpdump /public/android-r/out/super_raw.img
  ```

- 解析 Slot 1 的分区信息

  ```bash
  $ lpdump -slot 1 /public/android-r/out/super_raw.img
  ```

- 解析全部的分区信息

  ```bash
  $ lpdump -a /public/android-r/out/super_raw.img
  ```

- 解析空的 super image 中的分区信息

  ```bash
  # 使用相对路径
  $ lpdump -a out/target/product/xxx/super_empty.img
  
  # 使用绝对路径
  $ lpdump -a /public/android-r/out/target/product/inuvik/super_empty.img
  ```

- 查看 metadata 的大小

  > metadata 是指整个 metadata 的大小，没有 slot 概念，不分 slot 0 和 1，因此不需要指定 slot。

  ```bash
  # 查看空的 super image 中 metadata 的大小
  # 相对路径
  $ lpdump -d out/target/product/xxx/super_empty.img 
  1048576
  # 绝对路径
  $ lpdump -d /public/android-r/out/target/product/inuvik/super_empty.img 
  1048576
  
  # 查看完整的 super image 中 metadata 的大小
  $ lpdump -d /public/android-r/out/super_raw.img 
  1048576
  ```

- 使用 json 格式显示 metadata 的分区信息

  ```bash
  $ lpdump -j /public/android-r/out/super_raw.img 
  ```

### 2.2 super 设备解析示例

- 默认不带参数解析 super 设备当前 slot 的分区信息

  ```bash
  # 查看当前 slot 信息，位于 slot b 即 slot 1
  console:/ # getprop | grep slot
  [ro.boot.slot]: [b]
  [ro.boot.slot_suffix]: [_b]
  
  # 显示 super 设备上 slot 1 的分区信息
  console:/ # lpdump
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
  Super partition layout:
  ------------------------
  super: 2048 .. 2469000: system_b (2466952 sectors)
  super: 2469000 .. 2469888: system_b-cow (888 sectors)
  super: 2469888 .. 2627128: vendor_b (157240 sectors)
  super: 2627128 .. 2859008: system_b-cow (231880 sectors)
  ------------------------
  Block device table:
  ------------------------
    Partition name: super
    First sector: 2048
    Size: 1463812096 bytes
    Flags: none
  ------------------------
  Group table:
  ------------------------
    Name: default
    Maximum size: 0 bytes
    Flags: none
  ------------------------
    Name: bcm_ref_b
    Maximum size: 1459617792 bytes
    Flags: none
  ------------------------
    Name: cow
    Maximum size: 0 bytes
    Flags: none
  ------------------------
  console:/ # 
  ```

- 解析 super 设备 Slot 1 的分区信息

  ```bash
  # 解析 super 设备的 slot 1 的分区信息
  # 不使用绝对路径，字符串 super 会最终被补充为: /dev/block/by-name/super
  $ lpdump -slot 1 super
  
  # 使用绝对路径
  $ lpdump -slot 1 /dev/block/by-name/super
  ```

- 解析 super 设备 全部的分区信息

  ```bash
  # 使用相对路径
  $ lpdump -a super
  
  # 使用绝对路径
  $ lpdump -a /dev/block/by-name/super
  ```

- 查看 super 设备 metadata 的大小

  ```bash
  # 查看完整的 super image 中 metadata 的大小
  
  # 使用默认的 super 设备
  $ lpdump -d
  1048576
  
  # 不使用绝对路径
  $ lpdump -d super
  1048576
  
  # 使用绝对路径
  $ lpdump -d /dev/block/by-name/super
  1048576
  ```

- 使用 json 格式显示 super 设备 metadata 的分区信息

  ```bash
  $ lpdump -j /dev/block/by-name/super
  ```



## 3. 哪些地方会存储 metadata?

你知道设备上有哪些地方会存放类似 super 设备头部的 metadata 吗？

如果你以为只有 super 设备的头部这一个地方，这里想跟你说的是，错了~~至少说，不完全。



目前我所知，Android 系统中有 3 个可能存储分区 metadata 的地方:

1. 默认 super 设备头部存放 super 分区的分区表信息 metadata

2. 在设备进行 remount 以后，Android 11 及以后的系统会在 `/metadata/gsi/remount/lp_metadata` 存放 scratch 分区的 metadata。

   > 在 Android R(11) 及后续版本打开了 Virtual A/B 以后，默认会先从 data 分配空间用于挂载 overlay 文件系统，生成 /scratch 分区。
   >
   > 更多 remount 相关信息，请参考：[《Android 动态分区详解(七) overlayfs 与 adb remount 操作》](https://blog.csdn.net/guyongqiangx/article/details/128881282)

3. 在 Virtual A/B 系统升级中，系统会在 `/metadata/gsi/ota/lp_metadata` 存放 /data 目录下分配的 cow 文件的信息



涨知识了吗？赶紧用 lpdump 去解析这些地方的 lp_metadata 看看吧。

## 4. PC 上运行 lpdump 错误

VIP 答疑群里有个小伙伴问我一个 PC 上运行 lpdump 分区错误的问题，例如:

```
$ simg2img out/target/product/inuvik/super.img out/super_raw.img
$ lpdump out/super_raw.img
lpdump E 03-26 16:58:57 1662664 1662664 reader.cpp:443] [liblp]std::unique_ptr<LpMetadata> android::fs_mgr::ReadMetadata(const android::fs_mgr::IPartitionOpener &, const std::string &, uint32_t) open failed: out/super_raw.img: No such file or directory
Failed to read metadata.
```

我原来也遇到过很多次这个错误，有时候使用 lpdump 工作，有时候又不能工作，经常被搞得莫名奇妙的。

我其实一开始也没留意这个问题，以为是没有正确跳过 super 开始的 4096 字节的缘故。

北冥有鱼 提示说需要提供完整的绝对路径才行。

### 4.1 解决办法

正确做法是提供 image 的绝对路径给 lpdump 进行解析，如下:

```bash
$ lpdump /public/android-r/out/super_raw.img
```



不过有一个例外，如果是解析空的 super image，例如 Android 默认编译生成的 super_empty.img，则使用相对路径也可以：

```bash
$ lpdump out/target/product/xxx/super_empty.img 
```

原因是 lpdump 会提前判断是否为 empy super image 并解析，和解析完整的 super image 不走同一条路径。



### 4.2 问题的根源

通过使用 lldb 调试，发现这个问题错误的根源在于：

实际读取文件或分区设备的 metadata 时，会通过 `path = GetPartitionAbsolutePath(partition_name)` 返回文件或分区的完整路径。如下：

```c++
/* file: system/core/fs_mgr/liblp/partition_opener.cpp */
unique_fd PartitionOpener::Open(const std::string& partition_name, int flags) const {
    /*
     * 调用 GetPartitionAbsolutePath 获取 partition_name 指定的完整的绝对路径
     */
    std::string path = GetPartitionAbsolutePath(partition_name);
    return GetControlFileOrOpen(path.c_str(), flags | O_CLOEXEC);
}
```



问题就出在 `GetPartitionAbsolutePath` 函数中：

```c++
/* file: system/core/fs_mgr/liblp/partition_opener.cpp */
std::string GetPartitionAbsolutePath(const std::string& path) {
    /*
     * 1. 如果传入以 "/" 开始的绝对路径，则直接返回
     */
    if (android::base::StartsWith(path, "/")) {
        return path;
    }

    /*
     * 2. 如果传入的不是绝对路径，则在前面添加 "/dev/block/by-name/"
     *    例如，如果使用 lpdump out/super_raw.img 解析，
     *    则在这里会变成: /dev/block/by-name/out/super_raw.img
     */
    auto by_name = "/dev/block/by-name/" + path;
    if (access(by_name.c_str(), F_OK) != 0) {
        // If the by-name symlink doesn't exist, as a special case we allow
        // certain devices to be used as partition names. This can happen if a
        // Dynamic System Update is installed to an sdcard, which won't be in
        // the boot device list.
        //
        // We whitelist because most devices in /dev/block are not valid for
        // storing fiemaps.
        /*
         * 3. 如果传入的不是绝对路径，并且以 mmcblk 开头，则在前面添加 "/dev/block/"
         *    例如：mmcblk0, 则会查找 /dev/block/mmcblk0 设备。
         */
        if (android::base::StartsWith(path, "mmcblk")) {
            return "/dev/block/" + path;
        }
    }
    return by_name;
}
```

简而言之，GetPartitionAbsolutePath 是这样处理 path 路径的：

- 如果传入的 path 为绝对路径，则直接返回 path;

- 如果传入的 path 不是绝对路径，则返回 /dev/block/by-name/path;

- 如果传入的是 mmcblkx 这样的设备，则返回 /dev/block/mmcblkx



### 4.3 为错误致歉

所以，当你因为参考[《Android 动态分区详解(二) 核心模块和相关工具介绍》](https://guyongqiangx.blog.csdn.net/article/details/123931356) ，在 host 上用 lpdump 分析 super_raw.img 时也会遇到这个错误。下面截图中的内容应该是我在写作时为了简化路径，经过特殊处理过的。但没有预料到简化为相对路径后会有问题。

如果您参考我的博客遇到了这个问题，非常抱歉。

![image-20230326170023451](images-20230325-Android OTA 相关工具(五)  使用 lpdump 查看动态分区信息/image-20230326170023451.png)

> 特别感谢 潇 提出这个问题，以及 北冥有鱼 指出这个问题的根源是需要提供绝对路径。



## 5. 其它

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

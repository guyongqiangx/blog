# Android A/B System 分析

Android从7.0开始引入新的OTA升级方式，`A/B System Updates`，这里将其叫做`A/B`系统。

## 1. `A/B`系统的特点

顾名思义，`A/B`系统就是设备上有`A`和`B`两套可以工作的系统（用户数据只有一份，为两套系统共用），这两套系统版本可能一样；也可能不一样，其中一个是新版本，另外一个旧版本，通过升级，将旧版本也更新为新版本。当然，设备出厂时这两套系统肯定是一样的。

> 之所以叫套，而不是个，是因为Android系统不是由一个分区组成，其系统包括`boot`分区的kernel和ramdisk，`system`和`vendor`分区的应用程序和库文件，以及`userdata`分区的数据

`A/B`系统实现了无缝升级(`seamless updates`)，有以下特点：

- 出厂时设备上有两套可以正常工作的系统，升级时确保设备上始终有一个可以工作的系统，减少设备变砖的可能性，方便维修和售后。
- OTA升级在Android系统的后台进行，所以更新过程中，用户可以正常使用设备，数据更新完成后，仅需要用户重启一次设备进入新系统
- 如果OTA升级失败，设备可以回退到升级前的旧系统，并且可以尝试再次更新升级。

Android 7.0上传统OTA方式和新的`A/B`系统方式都存在，只是编译时只能选择其中的一种OTA方式。由于`A/B`系统在分区上与传统OTA的分区设计不一样，二者无法兼容，所以7.0以前的系统无法通过OTA方式升级为`A/B`系统。

> 啰嗦一下7.0以前传统的OTA方式：
>
> 设备上有一个Android主系统和一个Recovery系统，Android主系统运行时检测是否需要升级，如果需要升级，则将升级的数据包下载并存放到`cache`分区，重启系统后进入`Recovery`系统，并用`cache`分区下载好的数据更新Android主系统，更新完成后重新启动进入Android主系统。如果更新失败，设备重启后就不能正常使用了，唯一的办法就是重新升级，直到成功为止。


`A/B`系统主要由运行在Android后台的`update_engine`和两套分区`‘slot A’`和`‘slot B’`组成。Android系统从其中一套分区启动，在后台运行`update_engine`监测升级信息并下载升级数据，然后将数据更新到另外一套分区，写入数据完成后从更新的分区启动。

与传统OTA方式相比，`A/B`系统的变化主要有：

1. 系统的分区设置
   - 传统方式只有一套分区
   - `A/B`系统有两套分区，称为`slot A`和`slot B`
2. 跟bootloader沟通的方式
   - 传统方式bootloader通过读取`misc`分区信息来决定是进入Android主系统还是Recovery系统
   - `A/B`系统的bootloader通过特定的分区信息来决定从`slot A`还是`slot B`启动
3. 系统的编译过程
   - 传统方式在编译时会生成`boot.img`和`recovery.img`分别用于Android主系统和Recovery系统的ramdisk
   - `A/B`系统只有`boot.img`，而不再生成单独的`recovery.img`
4. OTA更新包的生成方式
   - `A/B`系统生成OTA包的工具和命令跟传统方式一样，但是生成内容的格式不一样了

由于内容较多，分多篇文章来详细分析整个`A/B`系统。

本文主要从分区和总体操作流程上来描述`A/B`系统，也可以参考Android官方对`A/B`系统的说明：[`"A/B System Updates"`](https://source.android.com/devices/tech/ota/ab_updates)。

## 2. `A/B`系统的分区

### 2.1 传统OTA的分区

传统OTA方式下的分区主要包括：

   - `bootloader`

      存放用于引导linux的bootloader
   - `boot`

     存放Android主系统的linux kernel文件和用于挂载system和其他分区的ramdisk
   - `system`

     Android主系统分区，包括Android的系统应用程序和库文件
   - `vendor`

     Android主系统分区，主要是包含开发厂商定制的一些应用和库文件，很多时候开发厂商也直接将这个分区的内容直接放入system分区
     
   - `userdata`

     用户数据分区，存放用户数据，包括用户安装的应用程序和使用时生成的数据

   - `cache`

     临时存放数据的分区，通常用于存放OTA的升级包
   - `recovery`

     存放Recovery系统的linux kernel文件和ramdisk
   - `misc`

     存放Android主系统和Recovery系统跟bootloader通信的数据

### 2.2 `A/B`系统的分区

   - `bootloader`

     存放用于引导linux的bootloader
   - `boot_a`和`boot_b`

     分别用于存放
   - `system_a`和`system_b`
   - `vendor_a`和`vendor_b`
   - `userdata`
   - `misc`或其他名字分区
   - 其他分区


### 2.3 一张图比较传统分区和`A/B`系统分区

![Legacy Partitions VS. A/B System Partitions](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/legacy-vs-ab-system-partitions.png?raw=true)

## 3. `A/B`系统的流程

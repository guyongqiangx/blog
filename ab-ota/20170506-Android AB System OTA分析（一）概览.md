# Android A/B System OTA分析（一）概览

Android从7.0开始引入新的OTA升级方式，`A/B System Updates`，这里将其叫做`A/B`系统。

`A/B`系统涉及的内容较多，分多篇对`A/B`系统的各个方面进行分析。本文为第一篇，概览。

> 版权声明：
> 本文为[guyongqiangx](http://blog.csdn.net/guyongqiangx)原创，欢迎转载，请注明出处：</br>
> [Android A/B System OTA分析（一）概览： http://blog.csdn.net/guyongqiangx/article/details/71334889](http://blog.csdn.net/guyongqiangx/article/details/71334889)

## 1. `A/B`系统的特点

顾名思义，`A/B`系统就是设备上有`A`和`B`两套可以工作的系统（用户数据只有一份，为两套系统共用），简单来讲，可以理解为一套系统分区，另外一套为备份分区。其系统版本可能一样；也可能不一样，其中一个是新版本，另外一个旧版本，通过升级，将旧版本也更新为新版本。当然，设备出厂时这两套系统肯定是一样的。

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

     分别用于存放两套系统各自的linux kernel文件和用于挂载system和其他分区的ramdisk

   - `system_a`和`system_b`

     Android主系统分区，分别用于存放两套系统各自的系统应用程序和库文件

   - `vendor_a`和`vendor_b`

     Android主系统分区， 分别用于存放两套系统各自的开发厂商定制的一些应用和库文件，很多时候开发厂商也直接将这个分区的内容直接放入system分区

   - `userdata`

     用户数据分区，存放用户数据，包括用户安装的应用程序和使用时生成的数据

   - `misc`或其他名字分区

     存放Android主系统和Recovery系统跟bootloader通信的数据，由于存放方式和分区名字没有强制要求，所以部分实现上保留了`misc`分区（代码中可见`Brillo`和`Intel`的平台），另外部分实现采用其他分区存放数据（`Broadcom`机顶盒平台采用名为`eio`的分区）。

### 2.3 一张图比较传统分区和`A/B`系统分区

关于分区的区别，文字描述不够直观，采用图片清楚多了。

![Legacy Partitions VS. A/B System Partitions](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/legacy-vs-ab-system-partitions.png?raw=true)

主要区别在于`A/B`系统：

1. `boot`，`system`和`vendor`系统分区从传统的一套变为两套，叫做`slot A`和`slot B`；
2. 不再需要`cache`和`recovery`分区
3. `misc`分区不是必须

> 关于`cache`和`misc`分区：
>
> - 仍然有部分厂家保留`cache`分区，用于一些其他的用途，相当于`temp`文件夹，但不是用于存放下载的`OTA`数据。
> - 部分厂家使用`misc`分区存放`Android`系统同`bootloader`通信数据，另有部分厂家使用其它名字的分区存储这类数据。

## 3. `A/B`系统的状态

### 3.1 系统分区属性

对于`A/B`系统的`slot A`和`slot B`分区，其都存在以下三个属性：

- `active`

    系统的活动分区标识，这是一个排他属性，系统只能有一个分区设置为`active`属性，启动时`bootloader`选取设置为`active`的分区进行启动。

- `bootable`

    分区可启动标识，设置为`bootable`的分区表明该分区包含了一个完整的可以启动的系统。

- `successful`

    分区成功运行标识，设置为`successful`的分区表明该分区在上一次启动或当前启动中可以正确运行。

### 3.2 系统的典型场景

典型的应用场景有以下4个（假定当前从B分区启动）：

![A/B System Example Scenarios](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/ab-system-example-scenarios.png?raw=true)

图中：

- 当前运行的系统（`current`）用绿色方框表示，当前没有用的系统（`unused`）用灰色方框表示。
- 属性标识为红色，表示该状态下相应属性被设置，标识为灰色标识该状态下属性没有设置或设置为相反属性，如：
	- "<font color="red">`active`</font>" 表示已经设置`active`属性，当前为活动分区；"<font color="gray">`active`</font>" 表示没有设置`active`属性
	- "<font color="red">`bootable`</font>" 表示已经设置`bootable`属性；"<font color="gray">`bootable`</font>" 表示设置为`unbootable`或没有设置`bootable`属性
	- "<font color="red">`successful`</font>" 表示已经设置`successful`属性，"<font color="gray">`successful`</font>" 表示没有设置`successful`属性

每个场景详细说明如下：

1. 普通场景（`Normal cases`）

    最常见的情形，例如设备出厂时，A分区和B分区都可以成功启动并正确运行，所以两个分区都设置为`bootable`和`successful`，但由于是从B分区启动，所以只有B分区设置为`active`。
    
2. 升级中（`Update in progress`）

    B分区检测到升级数据，在A分区进行升级，此时将A分区标识为`unbootable`，另外清除`successful`标识；B分区仍然为`active`，`bootable`和`successful`。

3. 更新完成，等待重启（`Update applied, reboot pending`）

    B分区将A分区成功更新后，将A分区标识为`bootable`。另外，由于重启后需要从A分区启动，所以也需要将A分区设置为`active`，但是由于还没有验证过A分区是否能成功运行，所以不设置`successful`；B分区的状态变为`bootable`和`successful`，但没有`active`。

4. 从新系统成功启动（`System rebooted into new update`）

    设备重启后，`bootloader`检测到A分区为`active`，所以加载A分区系统。进入A系统后如果能正确运行，需要将A分区标识为`successful`。对比第1个普通场景，A和B系统都设置为`bootable`和`successful`，但`active`从B分区切换到A分区。至此，B分区成功更新并切换到A分区，设备重新进入普通场景。

## 4. `A/B`系统的更新流程

整个`A/B`系统的升级更新在后台完成，升级中任何时间点都是可中断和可恢复的，相当于下载中的断点续传，更新操作对用户是透明的，在不影响用户操作的情况下完成升级。

设备可以设置数据下载、更新升级的场景和策略，例如：

- 只有在WiFi连接时才下载数据
- 电量较少时不下载数据、不进行更新
- 用户没有活动时才进行数据下载和更新等

具体有哪些策略依赖于开发者和用户的设置。

<<未完，待续>>


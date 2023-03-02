# 20230221-Android OTA 相关工具(三) A/B 系统之 bootctl

前面两篇:

- [《Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl》](https://blog.csdn.net/guyongqiangx/article/details/129122159)
- [《Android OTA 相关工具(二) 动态分区之 dmctl》](https://blog.csdn.net/guyongqiangx/article/details/129229115)

分别介绍了调试动态分区和虚拟 A/B 分区最常用的工具 snapshotctl 和 dmctl，这一篇介绍 bootctl(boot control)，一个专门用于设置 BootControl HAL 接口的工具。

这个工具最常用的地方就是在 Android 系统命令行下用来检查 A/B 系统的槽位状态以及切换系统。

我最早在 [《Android A/B System OTA分析（三）主系统和bootloader的通信》](https://blog.csdn.net/guyongqiangx/article/details/72480154) 介绍过基本用法，本篇则对这个工具进行详细介绍。

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
> 文章链接：https://guyongqiangx.blog.csdn.net/article/details/129310109



> 本文基于 Android 版本: android-11.0.0_r21，但后续版本也大同小异
>
> 在线代码：http://aospxref.com/android-11.0.0_r21/

## 1. bootctl 的编译

默认情况下 bootctl 不会编译进系统，需要在 device 目录下相应的 makefile 中将 bootctl 添加到 `PRODUCT_PACKAGES` 变量中。

不清楚如何添加就在 device 目录下执行 grep 命令看下 google 的参考设备是如何添加的。

例如，在 Android 11 上的 crosshatch 设备，bootctl 被包含在 `PRODUCT_PACKAGES_DEBUG` 中，如下：

> http://aospxref.com/android-11.0.0_r21/raw/device/google/crosshatch/device.mk

```
# The following modules are included in debuggable builds only.
PRODUCT_PACKAGES_DEBUG += \
    bootctl \
    update_engine_client
```

由于这里是 `PRODUCT_PACKAGES_DEBUG`，所以只有在 userdebug 版本才会包含 bootctl。

如果希望在其他版本都包含 bootctl，则建议把 bootctl 添加到 `PRODUCT_PACKAGES` 中。

## 2. bootctl 的帮助信息

bootctl 的命令比较直观，基本都可以见名知意：

```
console:/ # bootctl -h                                                                                                                                                                                                                                          
bootctl - command-line wrapper for the boot HAL.

Usage:
  bootctl COMMAND

Commands:
  hal-info                       - Show info about boot_control HAL used.
  get-number-slots               - Prints number of slots.
  get-current-slot               - Prints currently running SLOT.
  mark-boot-successful           - Mark current slot as GOOD.
  set-active-boot-slot SLOT      - On next boot, load and execute SLOT.
  set-slot-as-unbootable SLOT    - Mark SLOT as invalid.
  is-slot-bootable SLOT          - Returns 0 only if SLOT is bootable.
  is-slot-marked-successful SLOT - Returns 0 only if SLOT is marked GOOD.
  get-suffix SLOT                - Prints suffix for SLOT.
  set-snapshot-merge-status STAT - Sets whether a snapshot-merge of any dynamic
                                   partition is in progress. Valid STAT values
                                   are: none, unknown, snapshotted, merging,
                                   or cancelled.
  get-snapshot-merge-status      - Prints the current snapshot-merge status.

SLOT parameter is the zero-based slot-number.
```



在 Android 11 上新增了两个命令：

- `set-snapshot-merge-status STAT`
- `get-snapshot-merge-status`

这两个命令专门用来设置和查看虚拟 A/B 分区的 snapshot 状态。



关于 BootControl HAL 接口的具体信息，请参考下面两篇：

- [《Android A/B System OTA分析（三）主系统和bootloader的通信》](https://blog.csdn.net/guyongqiangx/article/details/72480154) 
- [《Android 虚拟分区详解(五) BootControl 接口的变化》](https://blog.csdn.net/guyongqiangx/article/details/128824984)

前一篇分析了 BootControl 的代码实现，后一篇分析了为了支持虚拟 A/B 分区，系统在 BootControl 接口上的变化。



## 3. bootctl 的用法

下面是设备上执行 bootctl 命令的一些典型用法。

### 1. hal-info

Hal-info 命令查看当前的 IBootControl 接口的 HAL 信息:

- 在  Android 7.1 系统上执行 hal-info 命令
```bash
console:/ # bootctl hal-info
HAL name:            boot control hal for bcm platform
HAL author:          Broadcom
HAL module version:  0.1
```

- 在 Android 11 上执行 hal-info 命令
```bash
console:/ # bootctl hal-info
HAL Version: android.hardware.boot@1.1::IBootControl
```



### 2. get-number-slots

get-number-slots 用于打印当前系统的槽位 (slot) 数量，A/B 系统一般都是两个。

```bash
console:/ # bootctl get-number-slots
2
```



### 3. get-current-slot

get-current-slot 用于打印当前系统运行的槽位 (slot):

``` bash
console:/ # bootctl get-current-slot
1
```



A/B 系统一般由两个槽位 (slot)，分别是 0 和 1，这里的系统运行在槽位 1 上。



### 4. mark-boot-successful

mark-boot-successful 将当前运行的系统标记为成功启动

```bash
console:/ # bootctl mark-boot-successful 
```



### 5. set-active-boot-slot

set-active-boot-slot 设置系统下次启动的 slot，

```bash
console:/ # bootctl get-current-slot                                           
1
```



这里显示当前系统运行在 slot 1 (B 槽位)上，运行:

```bash
console:/ # bootctl set-active-boot-slot 0
```

将把另外一个 slot 0 (A 槽位)设置为下次启动。



相当于通过 fastboot 执行命令:

```bash
fastboot set_active a
```



### 6. set-slot-as-unbootable

set-slot-as-unbootable 将相应的 slot 标记为无效。

下面的命令将 slot 0(A 槽位) 标记为无效，不可启动:

```bash
console:/ # bootctl set-slot-as-unbootable 0
```



### 7. is-slot-bootable

is-slot-bootable 命令查看指定的 slot 是否可以启动



当指定的 slot 可以启动时返回 0，在 console 上显示为命令正常退出。

当指定的 slot 不可启动时，在 console 上显示为命令异常退出。



```bash
console:/ # bootctl is-slot-bootable 1
console:/ # bootctl is-slot-bootable 0                                         
70|console:/ # 
```

在上面的命令中，slot 1 可以正常启动(命令正常结束)，但 slot 0 不能启动(命令异常退出)



### 8. is-slot-marked-successful

is-slot-marked-successful 返回相应的 slot 是否被标记为成功启动



当指定的 slot 被标记为成功启动时返回 0，在 console 上显示为命令正常退出。

当指定的 slot 没有被标记为成功启动时，在 console 上显示为命令异常退出。



```bash
console:/ # bootctl is-slot-marked-successful 1
console:/ # 
console:/ # bootctl is-slot-marked-successful 0
70|console:/ # 
```



这里的执行结果显示，slot 1 已经被标记为成功启动，slot 0 没有被标记为成功启动。



### 9. get-suffix

get-suffix 返回指定 slot 的后缀

```bash
console:/ # bootctl get-suffix 0
_a
console:/ # bootctl get-suffix 1
_b
```

这里显示系统两个 slot (槽位)的后缀分别为 `_a` 和 `_b`。



### 10. set-snapshot-merge-status

set-snapshot-merge-status 设置系统当前的 merge status，Android 11 以后适用。

操作的有效值包括: none, unknown, snapshotted, merging 和 cancelled。

```bash
console:/ # bootctl get-snapshot-merge-status 
none
console:/ # bootctl set-snapshot-merge-status unknown
console:/ # bootctl get-snapshot-merge-status                                  
unknown
console:/ # bootctl set-snapshot-merge-status cancelled                        
console:/ # bootctl get-snapshot-merge-status 
cancelled
console:/ # bootctl set-snapshot-merge-status active                           
bootctl - command-line wrapper for the boot HAL.

Usage:
  bootctl COMMAND

Commands:
  hal-info                       - Show info about boot_control HAL used.
  get-number-slots               - Prints number of slots.
  get-current-slot               - Prints currently running SLOT.
  mark-boot-successful           - Mark current slot as GOOD.
  set-active-boot-slot SLOT      - On next boot, load and execute SLOT.
  set-slot-as-unbootable SLOT    - Mark SLOT as invalid.
  is-slot-bootable SLOT          - Returns 0 only if SLOT is bootable.
  is-slot-marked-successful SLOT - Returns 0 only if SLOT is marked GOOD.
  get-suffix SLOT                - Prints suffix for SLOT.
  set-snapshot-merge-status STAT - Sets whether a snapshot-merge of any dynamic
                                   partition is in progress. Valid STAT values
                                   are: none, unknown, snapshotted, merging,
                                   or cancelled.
  get-snapshot-merge-status      - Prints the current snapshot-merge status.

SLOT parameter is the zero-based slot-number.
64|console:/ # 
```



上面的最后一个操作中，试图将 merge status 设置为无效值 active 失败。



### 11. get-snapshot-merge-status

get-snapshot-merge-status 获取当前系统的 merge status，Android 11 以后适用。

```bash
console:/ # bootctl get-snapshot-merge-status 
none
```



## 4. 思考题

IBootContol 定义的 HAL 接口在几个地方实现并被使用。

1. Android 主系统中实现 IBootControl 接口，通过 BootControl Service 向上层提供服务，包括 Update Engine 和这里的 bootctl 工具。

2. bootloader 中实现 IBootControl 相应的结构，用于在 bootloader 中操作 IBootControl 在外部设备(flash, eMMC) 上存放的数据(通常是 misc 分区)

   fastboot 工具的一些 slot 相关操作也是通过 bootloader 实现的 IBootControl 接口来工作的。



现在问题来了，你知道于 bootctl 工具命令对应的 fastboot 命令吗？

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

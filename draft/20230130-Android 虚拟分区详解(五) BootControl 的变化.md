# Android 虚拟分区详解(五) BootControl 接口的变化

![android_virutal_ab_5_title](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/android_virutal_ab_5_title.png)

> Android Virtual A/B 系统简称 VAB，我将其称为虚拟分区。
>
> 本系列文章基于 Android R(11) 进行分析，如果没有特别说明，均基于代码版本 android-11.0.0_r46
>
> 代码在线阅读: http://aospxref.com/android-11.0.0_r21/



本系列到目前为止一共更新了六篇:

- [《Linux 快照 (snapshot) 原理与实践(一) 快照基本原理》](https://blog.csdn.net/guyongqiangx/article/details/128494795)
- [《Linux 快照 (snapshot) 原理与实践(二) 快照功能实践》](https://blog.csdn.net/guyongqiangx/article/details/128496471)

- [《Android 虚拟分区详解(一) 参考资料推荐》](https://blog.csdn.net/guyongqiangx/article/details/128071692)
- [《Android 虚拟分区详解(二) 虚拟分区布局》](https://blog.csdn.net/guyongqiangx/article/details/128167054)
- [《Android 虚拟分区详解(三) 分区状态变化》](https://blog.csdn.net/guyongqiangx/article/details/128517578)

- [《Android 虚拟分区详解(四) 编译开关》](https://blog.csdn.net/guyongqiangx/article/details/128567582)

## 1. 导读

前段时间有朋友在 OTA 讨论群里说他的设备升级以后无法启动了，想要解析 metadata 分区的数据来查看整个系统升级的 merge 状态，因为他怀疑 merge 过程失败导致系统无法启动。

实际上，记录系统 merge 状态的 merge status 数据不在 metadata 分区，而是在 misc 分区，这一切和 BootControl 为支持 Virtual A/B 的升级变化有关。

因此，我打算分两篇来介绍系统升级过程中 merge 状态数据的存放和各种状态转换的问题。



本篇主要分析 Android R 上 BootControl HAL 接口的变化。只要弄清楚了 BootControl 的变化，merge status 数据也就弄清楚了。



> Android 官方将 BootControl 翻译为"启动控件"，总觉得有些别扭，所以本文仍然使用 BootControl 这一术语。



## 2. 为什么需要更新 BootControl 接口?

实现虚拟分区为什么需要更新 BootControl 接口呢？主要还是和虚拟分区的更新流程有关。



OTA 升级时(系统运行在 slot A)，使用 super 设备上的空闲空间，或者在 userdata 上分配空间用于虚拟出升级需要的 slot B，更新时往 slot B 分区写入数据。

换而言之，slot B 并没有真实存在，而是用 super 或 userdata 分区的几块空间拼接出来的，所以叫做虚拟。在更新完 slot B 以后，还需要将 slot B 对应的数据(即 super 或 userdata 分区的几块数据)写入到真实的分区中，才能算是真正完成一次升级。

有一个问题，如果不经过重启，在 slot B 更新后就将 slot B 的数据合并写回到真实分区可以吗？

答案是不可以，这样会有两个问题：

1. 这里说的真实分区，就是当前系统正在运行的 slot A，在运行时是以只读的方式挂载的，无法写入。

2. 在没有验证 slot B 分区的系统能正常工作的前提下(系统能够从 slot B 启动)，贸然修改 slot A 的数据，如果升级失败，会导致 slot A 和 slot B 两套系统都无法使用。

   因为 slot B 升级失败(不可用)，而 slot A 也被修改了(也不可用)。

所以，在往 slot B 写完升级数据以后，

第一步，要先让系统重启，并从 slot B 启动，验证虚拟分区 slot B 升级成功。

第二部，在虚拟分区 slot B 升级成功的基础上，将数据合并回 slot A。合并结束，删除用于构建虚拟分区 slot B 的数据。

通过这种方式，才能确保任何时候都有一套可以运行的系统。

在这个过程中，bootloader , fastboot 以及 Android 系统本身都可能需要查询当前系统合并的状态。

比如，使用 fastboot 发送命令擦除 userdata。这个操作中，bootloader 是命令的实际执行者。

fastboot 先发送 erase 命令给 bootloader，bootloader 收到命令后，需要读取系统的状态。如果系统处于 merge 的阶段，userdata 分区中还有用于构建虚拟分区的数据，擦除 userdata 分区会导致 slot B 被破坏。此时 bootloader 应该拒绝执行操作反馈给 fastboot 工具。



那为什么是 BootControl 接口呢，不用 BootControl, 使用其他方式不行吗？

理论上肯定是可以的，不管用什么方式，只要能正确解析和操作就行。

但因为 fastboot 是和 bootloader 配合工作的，fastboot 查询系统的 merge 状态最终要通过 bootloader 来操作。根据目前的设计，bootloader 和 Android 主系统沟通的方式就是通过 BootControl 接口，因此查询系统 merge 状态的接口就放在了 BootControl 中。

## 3. BootControl v1.1 接口的变化

文档[《实现虚拟 A/B》](https://source.android.google.cn/docs/core/ota/virtual_ab/implement?hl=zh-cn)描述了 BootControl v1.1 在接口上的变化，这里直接截图贴一下原文:

![bootcontrol_hal_update](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/bootcontrol_hal_update.png)

图 1. Android 官方对 BootControl HAL 变化的描述



总体上，IBootControl.hal 从原来的 v1.0 升级到了 v1.1，变化有:

- 新增一个状态数据 `MergeStatus` 

- 新增两个操作(读、写)状态数据 MergeStatus 的接口

  - `getSnapshotMergeStatus()`,  用与获取 `MergeStatus`
- `setSnapshotMergeStatus()`，用于设置 `MergeStatus`

新版本的 MergeStatus 状态和 BootControl v1.1 接口定义分别位于以下两个文件中：

- hardware/interfaces/boot/1.1/types.hal
- hardware/interfaces/boot/1.1/IBootControl.hal

文件 types.hal 和 IBootControl.hal 都包含了详细的注释，建议仔细阅读，可能会有一些意外的收获。



## 4. BootControl v1.1 接口的实现

按照惯例，Android 系统只是定义了 BootControl 的接口，接口之下的实现由各芯片厂家负责，因此各家 BootControl 的代码都不一样。

我在[《Android A/B System OTA分析（三）主系统和bootloader的通信》](https://blog.csdn.net/guyongqiangx/article/details/72480154)详细分析过 Android 7.1 版本上各家 A/B 系统的 BootControl 实现代码，本篇主要集中在 BootControl v1.1 新版本的变动上，不再对 BootControl v1.0 及以前的部分详细分析。



对于 BootControl v1.1 的接口，Android 在目录 `/hardware/interfaces/boot/1.1/default` 下提供了一组默认的参考实现。尽管各芯片厂家有自己的实现代码，但基本上和 Android 默认实现大同小异。



下面详细分析 MergeStatus 数据的存储，以及 getSnapshotMergeStatus 和 setSnapshotMergeStatus 接口的实现。



### 4.1 MergeStatus 数据

BootControl v1.1 接口定义了一个名为 MergeStatus 的数据来表示系统的合并状态。

为了保存 MergeStatus 信息，在 Android 的 BootControl v1.1 的默认实现中，扩展了 BootControl 分区 "misc" 的数据，新增加了 system sapce 一节，大小为 32K。

具体上，system space 由 `misc_system_space_layout` 结构描述，里面包含了一个 `misc_virtual_ab_message` 子结构体，定义如下：

```c
// Holds Virtual A/B merge status information. Current version is 1. New fields
// must be added to the end.
struct misc_virtual_ab_message {
  uint8_t version;
  uint32_t magic;
  uint8_t merge_status;  // IBootControl 1.1, MergeStatus enum.
  uint8_t source_slot;   // Slot number when merge_status was written.
  uint8_t reserved[57];
} __attribute__((packed));

#define MISC_VIRTUAL_AB_MESSAGE_VERSION 2
#define MISC_VIRTUAL_AB_MAGIC_HEADER 0x56740AB0

#if (__STDC_VERSION__ >= 201112L) || defined(__cplusplus)
static_assert(sizeof(struct misc_virtual_ab_message) == 64,
              "struct misc_virtual_ab_message has wrong size");
#endif
```



所以 misc 分区最终形成了一个 64K 的数据布局，为了直观期间，我画了下面这个结构框图：

![bootloader_message_vab](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/bootloader_message_vab.png)

图 2. Android 参考实现中 misc 分区布局



其中右下角 `misc_virtual_ab_message` 中的 `merge_status` 就是系统当前的 merge 状态。



>  思考题:
>
> 1. 在 bootloader 无法正常工作的情况下，如何检查系统的 merge 状态？



### 4.2 BootControl 服务的注册

在 AOSP 的参考代码中，`hardware/interfaces/boot/1.1/default` 目录下的代码被编译为名为 `android.hardware.boot@1.1-service` 的应用程序，通过脚本 `android.hardware.boot@1.1-service.rc` 在 Android 系统启动过程中执行，如下：

```bash
# hardware/interfaces/boot/1.1/default/android.hardware.boot@1.1-service.rc
service vendor.boot-hal-1-1 /vendor/bin/hw/android.hardware.boot@1.1-service
    interface android.hardware.boot@1.0::IBootControl default
    interface android.hardware.boot@1.1::IBootControl default
    class early_hal
    user root
    group root
```

整个应用程序的入口在 `service.cpp` 中:

```c++
/* hardware/interfaces/boot/1.1/default/service.cpp */
#define LOG_TAG "android.hardware.boot@1.1-service"

#include <android/hardware/boot/1.1/IBootControl.h>
#include <hidl/LegacySupport.h>

using android::hardware::defaultPassthroughServiceImplementation;
using IBootControl_V1_0 = android::hardware::boot::V1_0::IBootControl;
using IBootControl_V1_1 = android::hardware::boot::V1_1::IBootControl;

int main(int /* argc */, char* /* argv */[]) {
    return defaultPassthroughServiceImplementation<IBootControl_V1_0, IBootControl_V1_1>();
}
```

这里通过 `defaultPassthroughServiceImplementation` 注册 IBootControl 服务接口供上层使用。



其他厂家的方案，代码应该在 vendor 或其它目录下。如果不知道在哪里查找，可以在 Android 的目录树下直接搜索 IBootControl，虽然搜索会有点慢，但在结果中肯定可以找到，除非不提供源码。

```bash
$ grep -rnw IBootControl . --exclude-dir=out
```



### 4.3 getSnapshotMergeStatus 接口

getSnapshotMergeStatus 接口通过 IBootControl 服务向上层提供服务。

那接口之下具体是如何实现的呢？

Android 默认的 BootControl v1.1 相关代码位于以下文件中：

- hardware/interfaces/boot/1.1/default/BootControl.cpp
- bootable/recovery/bootloader_message/bootloader_message.cpp
- bootable/recovery/bootloader_message/bootloader_message.cpp



为了避免贴代码导致文章变得很冗长，这里我将 getSnapshotMergeStatus 接口实现的调用关系画成了一张图:

![getSnapshotMergeStatus](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/getSnapshotMergeStatus.png)

图 3.  BootControl v1.1 参考代码中 getSnapshotMergeStatus 调用关系图



总体如下：

- BootControl.cpp 中实现了 IBootControl v1.1 的各种功能，并通过 IBootControl.hal 定义的接口向外提供服务。

- BootControl.cpp 主要是接口的封装，代码实现位于 libboot_control.cpp 中。

- libboot_control.cpp 调用 bootloader_message.cpp 中的函数来实现对 misc 分区的操作。



从上面的图中可见，getSnapshotMergeStatus 最终会读取 misc 分区位于 `SYSTEM_SPACE_OFFSEt_IN_MISC`位置的数据来获取系统的 merge 状态。

### 4.3 setSnapshotMergeStatus 接口

 下面是 setSnapshotMergeStatus 接口实现的调用关系图:



![setSnapshotMergeStatus](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/setSnapshotMergeStatus.png)

图 4.  BootControl v1.1 参考代码中 setSnapshotMergeStatus 调用关系图



setSnapshotMergeStatus 会先读取 misc 分区位于 `SYSTEM_SPACE_OFFSEt_IN_MISC`位置的数据来获取系统的 merge 状态数据，然后修改读取到数据的 merge_status 变量，并写回到 misc 分区中。



## 5. fastboot 工具的变化

由于整个升级中多了一个需要进行数据 merge 合并的阶段，所以 fastboot 工具也会多一些限制。

下面是官方文档中对 fastboot 工具变更的说明：

![fastboot_update](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/fastboot_update.png)

图 5.  fastboot 工具针对系统 merge 状态提供的操作



> 思考题：
>
> 2. 查看系统的 merge 状态都有哪些方式？

## 6. 其它

如果您已经订阅了本专栏，请务必加我微信，拉你进专栏 VIP 答疑群。

如果大家有任何疑问，又或者发现描述有错误的地方，欢迎加我微信讨论，请在公众号(“洛奇看世界”)后台回复 “wx” 获取二维码。


# Android 虚拟分区详解(五) BootControl 的变化

![android_virtual_ab_4_title](/Volumes/work/guyongqiangx/draft/images-20230102-Android 虚拟分区详解(四) 编译开关/android_virtual_ab_4_title.png)

> Android Virtual A/B 系统简称 VAB，我将其称为虚拟分区。
>
> 本系列文章基于 Android R(11) 进行分析，如果没有特别说明，均基于代码版本 android-11.0.0_r46
>
> 代码在线阅读: http://aospxref.com/android-11.0.0_r21/

前段时间有朋友在 OTA 讨论群里说他的设备升级以后无法启动了，想要解析 metadata 分区的数据来查看整个系统升级的 merge 状态，因为他怀疑 merge 过程失败导致系统无法启动。

实际上系统升级时的 merge status 数据不在 metadata 分区，而是在 misc 分区里。



我打算分两篇来介绍 merge 时状态数据 merge status 的存放和升级时的状态转换问题。

本篇主要讨论 merge status 数据的存放，实质上是分析 Android R 上 BootControl HAL 接口的变化。

> Android 官方将 BootControl 翻译为"启动控件"，总觉得有些别扭，所以本文仍然使用 BootControl 这一术语。



## 为什么需要更新 BootControl 接口?

实现虚拟分区为什么需要更新 BootControl 接口呢？主要还是和虚拟分区的更新流程有关。

OTA 升级时(系统运行在 slot A)，使用 super 设备上的空闲空间，或者在 userdata 分区分配空间用于虚拟出升级需要的 slot B，然后往 slot B 分区写入数据。

注意这里的 slot B 并不是真实分区，而是虚拟出来的。所以需要将 slot B 对应的数据写入到真实的分区中，才能算是真正完成一次升级。

如果不经过重启，直接在向 slot B 写完数据后就开始将 slot B 的数据写回到真实分区会遇到两个问题：

1. 真实分区就是当前系统正在运行的 slot A，此时是以只读的方式挂载的，无法写入。

2. 在没有验证 slot B 分区的系统能正常工作的前提下(系统能够从 slot B 启动)，贸然修改 slot A 的数据，如果升级失败，会导致 slot A 和 slot B 两套系统都无法使用。

   因为 slot B 升级失败(不可用)，而 slot A 又被修改了(也不可用)。

所以，在往 slot B 写完升级数据以后，系统重启并从 slot B 启动，验证 slot B 分区升级成功，才开始将数据合并回 slot A。一旦合并结束，删除用于构建虚拟分区 slot B 的数据。通过这种方式，才能确保任何时候都有一套可以运行的系统。

因此，bootloader , fastboot 工具以及系统本身都可能需要查询当前系统合并的状态，来决定下一步的操作。

比如，使用 fastboot 发送命令擦除 userdata，需要根据当前合并的状态来决定是否允许执行操作。如果系统处于 merge 的阶段，userdata 分区中还有用于构建虚拟分区的数据，此时擦除 userdata 分区会导致 slot B 被破坏。



那为什么是通过 BootControl 接口来查询呢？不用 BootControl, 而是写入到 metadata 分区或其它方式不行吗？

理论上肯定是可以的，不管用什么方式，只要能正确解析和操作就行。

但因为 fastboot 是和 bootloader 配合工作的，fastboot 查询系统的 merge 状态最终要通过 bootloader 来操作。根据目前的设计，bootloader 和主系统沟通的方式就是通过 BootControl 接口，因此查询系统 merge 状态的接口就放在了 BootControl 中。



## 如何查看系统的 merge 状态？

要查看系统的 merge 状态可以使用以下两种方式:

```bash
bootctl get-snapshot-merge-status

fastboot getvar snapshot-update-status
```



## BootControl v1.1 接口的变化

官方对 BootControl 在 Android 11 上的变化是这样描述的:

![image-20230130212857675](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/image-20230130212857675.png)

总体上，IBootControl.hal 从原来的 v1.0 升级到了 v1.1，新增了:

- 一个状态数据 `MergeStatus` 

- 两个操作(读、写)状态数据的接口

  - `setSnapshotMergeStatus()`，用于设置 `MergeStatus`

  - `getSnapshotMergeStatus()`,  用与获取 `MergeStatus`

新版本的 MergeStatus 状态和 BootControl 接口定义分别位于以下两个文件中：

```
/hardware/interfaces/boot/1.1/types.hal
/hardware/interfaces/boot/1.1/IBootControl.hal
```

文件 types.hal 和 IBootControl.hal 中包含了详细的注释，建议仔细阅读，可能会有一些意外的收获。



## BootControl v1.1 接口的实现

Android 系统只是定义了 BootControl 的接口，各芯片厂家的具体实现可能不一样。

我在[《Android A/B System OTA分析（三）主系统和bootloader的通信》](https://blog.csdn.net/guyongqiangx/article/details/72480154)详细分析过各家 A/B 系统的 BootControl 实现代码，有需要的可以回到该篇了解。



对于 BootControl v1.1 新增的接口，Android 默认在目录 `/hardware/interfaces/boot/1.1/default` 目录下提供了一组实现，各家实现和默认实现也基本上大同小异。



在 Android 的 BootControl v1.1 的默认实现中，扩展了 BootControl 数据所在分区 "misc" 的数据，新增加了两节，新的结构一共 64K，布局如下：



 另外定义了两个接口用于读取

```c
/*
 * file: bootable/recovery/bootloader_message/include/bootloader_message/bootloader_message.h
 */
// Read or write the Virtual A/B message from system space in /misc.
bool ReadMiscVirtualAbMessage(misc_virtual_ab_message* message, std::string* err);
bool WriteMiscVirtualAbMessage(const misc_virtual_ab_message& message, std::string* err);
```

具体代码如下:

```c++
/*
 * file: /bootable/recovery/bootloader_message/bootloader_message.cpp
 */
static bool ReadMiscPartitionSystemSpace(void* data, size_t size, size_t offset, std::string* err) {
  if (!ValidateSystemSpaceRegion(offset, size, err)) {
    return false;
  }
  auto misc_blk_device = get_misc_blk_device(err);
  if (misc_blk_device.empty()) {
    return false;
  }
  return read_misc_partition(data, size, misc_blk_device, SYSTEM_SPACE_OFFSET_IN_MISC + offset,
                             err);
}

static bool WriteMiscPartitionSystemSpace(const void* data, size_t size, size_t offset,
                                          std::string* err) {
  if (!ValidateSystemSpaceRegion(offset, size, err)) {
    return false;
  }
  auto misc_blk_device = get_misc_blk_device(err);
  if (misc_blk_device.empty()) {
    return false;
  }
  return write_misc_partition(data, size, misc_blk_device, SYSTEM_SPACE_OFFSET_IN_MISC + offset,
                              err);
}

bool ReadMiscVirtualAbMessage(misc_virtual_ab_message* message, std::string* err) {
  return ReadMiscPartitionSystemSpace(message, sizeof(*message),
                                      offsetof(misc_system_space_layout, virtual_ab_message), err);
}

bool WriteMiscVirtualAbMessage(const misc_virtual_ab_message& message, std::string* err) {
  return WriteMiscPartitionSystemSpace(&message, sizeof(message),
                                       offsetof(misc_system_space_layout, virtual_ab_message), err);
}
```

这里实际的操作是通过 `read_misc_partition` 和 `read_misc_partition` 函数来操作 misc 分区位于 `SYSTEM_SPACE_OFFSET_IN_MISC + offset` 偏移处的数据。

这个数据刚好就是存放 merge status 的结构体 `misc_virtual_ab_message`。



在默认的 BootControl v1.1 的实现中：

```c++
/*
 * file: hardware/interfaces/boot/1.1/default/boot_control/libboot_control.cpp
 */
bool SetMiscVirtualAbMergeStatus(unsigned int current_slot,
                                 android::hardware::boot::V1_1::MergeStatus status) {
  std::string err;
  misc_virtual_ab_message message;

  if (!ReadMiscVirtualAbMessage(&message, &err)) {
    LOG(ERROR) << "Could not read merge status: " << err;
    return false;
  }

  message.merge_status = static_cast<uint8_t>(status);
  message.source_slot = current_slot;
  if (!WriteMiscVirtualAbMessage(message, &err)) {
    LOG(ERROR) << "Could not write merge status: " << err;
    return false;
  }
  return true;
}

bool GetMiscVirtualAbMergeStatus(unsigned int current_slot,
                                 android::hardware::boot::V1_1::MergeStatus* status) {
  std::string err;
  misc_virtual_ab_message message;

  if (!ReadMiscVirtualAbMessage(&message, &err)) {
    LOG(ERROR) << "Could not read merge status: " << err;
    return false;
  }

  // If the slot reverted after having created a snapshot, then the snapshot will
  // be thrown away at boot. Thus we don't count this as being in a snapshotted
  // state.
  *status = static_cast<MergeStatus>(message.merge_status);
  if (*status == MergeStatus::SNAPSHOTTED && current_slot == message.source_slot) {
    *status = MergeStatus::NONE;
  }
  return true;
}
```

然后

```c++
/*
 * file: hardware/interfaces/boot/1.1/default/boot_control/libboot_control.cpp
 */
bool BootControl::SetSnapshotMergeStatus(MergeStatus status) {
  return SetMiscVirtualAbMergeStatus(current_slot_, status);
}

MergeStatus BootControl::GetSnapshotMergeStatus() {
  MergeStatus status;
  if (!GetMiscVirtualAbMergeStatus(current_slot_, &status)) {
    return MergeStatus::UNKNOWN;
  }
  return status;
}
```







![image-20230130213259569](images-20230130-Android 虚拟分区详解(五) BootControl 的变化/image-20230130213259569.png)
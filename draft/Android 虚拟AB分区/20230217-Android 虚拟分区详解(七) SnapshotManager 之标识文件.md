# Android 虚拟 A/B 详解(七) SnapshotManager 之标识文件

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 原文链接：https://blog.csdn.net/guyongqiangx/article/details/129098176



> Android 虚拟 A/B 分区[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列，更新中，文章列表：
>
> - [Android 虚拟 A/B 详解(一) 参考资料推荐](https://blog.csdn.net/guyongqiangx/article/details/128071692)
> - [Android 虚拟 A/B 详解(二) 虚拟分区布局](https://blog.csdn.net/guyongqiangx/article/details/128167054)
> - [Android 虚拟 A/B 详解(三) 分区状态变化](https://blog.csdn.net/guyongqiangx/article/details/128517578)
> - [Android 虚拟 A/B 详解(四) 编译开关](https://blog.csdn.net/guyongqiangx/article/details/128567582)
> - [Android 虚拟 A/B 详解(五) BootControl 接口的变化](https://blog.csdn.net/guyongqiangx/article/details/128824984)
> - [Android 虚拟 A/B 详解(六) SnapshotManager 之状态数据](https://blog.csdn.net/guyongqiangx/article/details/129094203)
>
> 对 linux 快照(snapshot) 的了解可以增加对虚拟 A/B 分区的理解：
>
> - [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
> - [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。



## 0. 导读

上一篇[《Android 虚拟 A/B 详解(六) SnapshotManager 之状态数据》](https://blog.csdn.net/guyongqiangx/article/details/129094203)中有提到多个状态文件，包括：

- 系统升级状态的 state 文件: `/metadata/ota/state`
- 系统合并状态的 merge state 文件: `/metadata/ota/merge_state`
- 虚拟分区的快照设备状态文件：`/metadata/ota/snapshots/system_b`



除了这些状态文件外，SnapshotManager 在管理虚拟分区时，还有一些其它的标识文件，例如：

- BootIndicator: `/metadata/ota/snapshot-boot`
- RollbackIndicator: `/metadata/ota/rollback-indicator`
- ForwardMergeIndicator: `/metadata/ota/allow-forward-merge`

如果你在分析某个问题是，碰巧遇到了这些标识文件，你都知道这些标识(indicator)文件中写了什么内容，是做什么用的吗？你知道这些文件是何时创建，何时更新，何时销毁的吗？



本文带这这些疑问，阅读 SnapshotManager 代码，向你介绍这些文件的各种操作和用途。

本文的前面 3 节分别详细分析这些标识文件的增删改查操作来理解标识文件的用途，由于是代码分析，因此篇幅很长，比较啰嗦。

如果你只关心这 3 个标识文件的用途和结论，请直接跳转到第 4 节。



> 本文基于 Android 11.0.0_r21 版本的代码进行分析。
>
> 在线地址：http://aospxref.com/android-11.0.0_r21/

## 1. BootIndicator 文件

### 1. GetSnapshotBootIndicatorPath 函数

GetSnapshotBootIndicatorPath 函数返回 BootIndicator 文件的路径 `/metadata/ota/snapshot-boot`

```c++
std::string SnapshotManager::GetSnapshotBootIndicatorPath() {
    return metadata_dir_ + "/" + android::base::Basename(kBootIndicatorPath);
}
```



### 2. FinishedSnapshotWrites 函数

FinishedSnapshotWrites 函数创建 BootIndicator 文件，并将当前分区的后缀写入到文件中

```c++
bool SnapshotManager::FinishedSnapshotWrites(bool wipe) {
    auto lock = LockExclusive();
    if (!lock) return false;

    // 1. 从 state 文件(/metadata/ota/state) 读取系统当前的升级状态
    // 在完成快照设备写入的时候，当前系统状态不应该是 Unverified, Initiated
    auto update_state = ReadUpdateState(lock.get());
    if (update_state == UpdateState::Unverified) {
        LOG(INFO) << "FinishedSnapshotWrites already called before. Ignored.";
        return true;
    }

    if (update_state != UpdateState::Initiated) {
        LOG(ERROR) << "Can only transition to the Unverified state from the Initiated state.";
        return false;
    }

    // 2. 检查当前所有的快照设备是否有溢出
    // 溢出的意思是，往快照设备写入的数据超过了快照设备的大小，此时快照设备处于一种不可用的状态
    // 因此，必须确保快照设备没有溢出
    if (!EnsureNoOverflowSnapshot(lock.get())) {
        LOG(ERROR) << "Cannot ensure there are no overflow snapshots.";
        return false;
    }

    // 3. 更新 ForwardMergeIndicator 文件(/metadata/ota/allow-forward-merge)
    if (!UpdateForwardMergeIndicator(wipe)) {
        return false;
    }

    // 4. 移除 RollbackIndicator 文件(/metadata/ota/rollback-indicator)
    // 因为 Rollback 是启动早期创建的，所以升级的重启前，要确保 RollbackIndicator 文件不存在
    // This file is written on boot to detect whether a rollback occurred. It
    // MUST NOT exist before rebooting, otherwise, we're at risk of deleting
    // snapshots too early.
    if (!RemoveFileIfExists(GetRollbackIndicatorPath())) {
        return false;
    }

    // 5. 读取当前系统的 Slot Suffix，写入到 BootIndicator 文件中
    // This file acts as both a quick indicator for init (it can use access(2)
    // to decide how to do first-stage mounts), and it stores the old slot, so
    // we can tell whether or not we performed a rollback.
    auto contents = device_->GetSlotSuffix();
    auto boot_file = GetSnapshotBootIndicatorPath();
    if (!WriteStringToFileAtomic(contents, boot_file)) {
        PLOG(ERROR) << "write failed: " << boot_file;
        return false;
    }
  
    // 6. 将新的系统状态 Unverified 写入到 state 文件(/metadata/ota/state)中
    return WriteUpdateState(lock.get(), UpdateState::Unverified);
}
```

从这段代码的函数名字可见，更新过程中，当完成对快照设备的写入后，会调用这里的 FinishedSnapshotWrites 函数，执行以下几件事情：

1. 从 state 文件读取系统当前的升级状态，确保当前不处于 Unverified 和 Initiated 状态;
1. 检查当前所有的快照设备是否有溢出，确保所有虚拟分区的快照文件都正常；
1. 更新 ForwardMergeIndicator 文件；
1. 移除 RollbackIndicator 文件；(升级重启前，要确保 RollbackIndicator 文件不存在)
1. 读取当前系统的 Slot Suffix，写入到 BootIndicator 文件中，因此 BootIndicator 存放的是升级时的源分区后缀；
1. 将新的系统状态 Unverified 写入到 state 文件;



那在什么时候调用 FinishedSnapshotWrites 呢？答案是 FinishUpdate:

```c++
bool DynamicPartitionControlAndroid::FinishUpdate(bool powerwash_required) {
  // 如果 metadata 分区有挂载
  if (ExpectMetadataMounted()) {
    // 如果当前系统状态为 Initiated，调用 FinishedSnapshotWrites
    if (snapshot_->GetUpdateState() == UpdateState::Initiated) {
      LOG(INFO) << "Snapshot writes are done.";
      return snapshot_->FinishedSnapshotWrites(powerwash_required);
    }
  } else {
    LOG(INFO) << "Skip FinishedSnapshotWrites() because /metadata is not "
              << "mounted";
  }
  return true;
}
```



那又什么时候调用 FinishUpdate 呢？答案是 

```c++
void PostinstallRunnerAction::CompletePostinstall(ErrorCode error_code) {
  // We only attempt to mark the new slot as active if all the postinstall
  // steps succeeded.
  if (error_code == ErrorCode::kSuccess) {
    if (install_plan_.switch_slot_on_reboot) {
      // 执行 FinishUpdate 操作，并且将 target_slot 设置为 Active
      if (!boot_control_->GetDynamicPartitionControl()->FinishUpdate(
              install_plan_.powerwash_required) ||
          !boot_control_->SetActiveBootSlot(install_plan_.target_slot)) {
        error_code = ErrorCode::kPostinstallRunnerError;
      } else {
        // Schedules warm reset on next reboot, ignores the error.
        hardware_->SetWarmReset(true);
      }
    } else {
      error_code = ErrorCode::kUpdatedButNotActive;
    }
  }

  //...
}
```



因此，在 PostinstallRunnerAction 执行时，在快照设备上的更新已经完成。

此时通过 FinishedSnapshotWrites 函数，确保所有快照设备没有溢出，可以正常工作，因为重启后需要从快照设备上的系统启动；另外，更新标识文件 ForwardMergeIndicator, RollbackIndicator, BootIndicator 为合适的状态，为系统重启切换到快照设备上的系统做好准备。



### 3. ReadUpdateSourceSlotSuffix 函数

ReadUpdateSourceSlotSuffix 函数读取 BootIndicator 文件，并返回其内容

```c++
std::string SnapshotManager::ReadUpdateSourceSlotSuffix() {
    auto boot_file = GetSnapshotBootIndicatorPath();
    std::string contents;
    // 读取 BootIndicator 文件内容
    if (!android::base::ReadFileToString(boot_file, &contents)) {
        PLOG(WARNING) << "Cannot read " << boot_file;
        return {};
    }
    return contents;
}

SnapshotManager::Slot SnapshotManager::GetCurrentSlot() {
    auto contents = ReadUpdateSourceSlotSuffix();
    if (contents.empty()) {
        return Slot::Unknown;
    }
    // BootIndicator 文件存放的是升级源分区后缀
    // 如果当前分区和升级源分区后缀一样，那当前分区即为 Source，否则为 Target
    if (device_->GetSlotSuffix() == contents) {
        return Slot::Source;
    }
    return Slot::Target;
}
```



### 4. RemoveAllUpdateState 函数

在 RemoveAllUpdateState 中会删除所有的标识文件，包括 BootIndicator, RollbackIndicator, ForwareMergeIndecator 等

```c++
bool SnapshotManager::RemoveAllUpdateState(LockedFile* lock, const std::function<bool()>& prolog) {
    if (prolog && !prolog()) {
        LOG(WARNING) << "Can't RemoveAllUpdateState: prolog failed.";
        return false;
    }

    LOG(INFO) << "Removing all update state.";

    // 1. 移除所有的设备快照
    if (!RemoveAllSnapshots(lock)) {
        LOG(ERROR) << "Could not remove all snapshots";
        return false;
    }

    // 2. 删除所有的标识文件，包括:
    // BootIndicator (/metadata/ota/snapshot-boot),
    // RollbackIndicator (/metadata/ota/rollback-indicator), 
    // ForwareMergeIndecator (/metadata/ota/allow-forward-merge) 等
  
    // It's okay if these fail:
    // - For SnapshotBoot and Rollback, first-stage init performs a deeper check after
    // reading the indicator file, so it's not a problem if it still exists
    // after the update completes.
    // - For ForwardMerge, FinishedSnapshotWrites asserts that the existence of the indicator
    // matches the incoming update.
    std::vector<std::string> files = {
            GetSnapshotBootIndicatorPath(),
            GetRollbackIndicatorPath(),
            GetForwardMergeIndicatorPath(),
    };
    for (const auto& file : files) {
        RemoveFileIfExists(file);
    }

    // 3. 将 UpdateState::None 写入到 state 文件中(/metadata/ota/state)
    // If this fails, we'll keep trying to remove the update state (as the
    // device reboots or starts a new update) until it finally succeeds.
    return WriteUpdateState(lock, UpdateState::None);
}
```

RemoveAllUpdateState 的功能是复位系统的状态，该函数主要做了 3 件事：

1. 移除所有设备快照；
2. 删除所有的标识文件，包括 BootIndicator, RollbackIndicator 和 ForwardMergeIndicator；
3. 更新系统的升级状态为 UpdateState::None，并写入到 state 文件中；



### 5. BootIndicator 文件总结

对于 BootIndicator 文件，总结起来就是：

- 作用

  用于指示当前升级的 Source 槽位，保存了 Source 槽位的后缀

- 创建

  升级过程中，在完成对快照设备的写入后，在 Postinstall 阶段，函数 FinishedSnapshotWrites 中创建 BootIndicator 文件，并将升级源分区的后缀写入到文件中；

- 访问

  在完成对快照设备写入以后的各种操作中，比如重启后进行 merge，通过 GetCurrentSlot 来读取 BootIndicator 文件的内容，来判断当前是 Source 还是 Target 系统；

- 删除

  在 RemoveAllUpdateState 时，销毁 BootIndicator 文件；

> 思考题：
>
> 什么时候会调用 RemoveAllUpdateState 函数？



## 2. RollbackIndicator 文件

### 1. GetRollbackIndicatorPath 函数

GetRollbackIndicatorPath 函数返回 RollbackIndicator 文件的路径 `/metadata/ota/rollback-indicator`

```c++
std::string SnapshotManager::GetRollbackIndicatorPath() {
    return metadata_dir_ + "/" + android::base::Basename(kRollbackIndicatorPath);
}
```

### 2. NeedSnapshotsInFirstStageMount 函数

```c++
bool SnapshotManager::NeedSnapshotsInFirstStageMount() {
    // If we fail to read, we'll wind up using CreateLogicalPartitions, which
    // will create devices that look like the old slot, except with extra
    // content at the end of each device. This will confuse dm-verity, and
    // ultimately we'll fail to boot. Why not make it a fatal error and have
    // the reason be clearer? Because the indicator file still exists, and
    // if this was FATAL, reverting to the old slot would be broken.
  
    // 1. 获取当前系统槽位分区类型，Slot::Source 或者 Slot::Target
    auto slot = GetCurrentSlot();

    // 2. 如果当前槽位不是 Target 槽位，创建 RollbackIndicator 文件，并写入 1
    //    表示当前处于可以 Rollback 的状态
    if (slot != Slot::Target) {
        if (slot == Slot::Source) {
            // Device is rebooting into the original slot, so mark this as a
            // rollback.
            auto path = GetRollbackIndicatorPath();
            if (!android::base::WriteStringToFile("1", path)) {
                PLOG(ERROR) << "Unable to write rollback indicator: " << path;
            } else {
                LOG(INFO) << "Rollback detected, writing rollback indicator to " << path;
            }
        }
        LOG(INFO) << "Not booting from new slot. Will not mount snapshots.";
        return false;
    }

    // If we can't read the update state, it's unlikely anything else will
    // succeed, so this is a fatal error. We'll eventually exhaust boot
    // attempts and revert to the old slot.
    auto lock = LockShared();
    if (!lock) {
        LOG(FATAL) << "Could not read update state to determine snapshot status";
        return false;
    }
    // 3. 从 state 文件读取系统状态，如果是 Unverified, Merging, MergeFailed，返回 true
    switch (ReadUpdateState(lock.get())) {
        case UpdateState::Unverified:
        case UpdateState::Merging:
        case UpdateState::MergeFailed:
            return true;
        default:
            return false;
    }
}
```

NeedSnapshotsInFirstStageMount 在 Android 启动的早期用于判断是否需要挂载快照设备，以下状态都需要快照设备参与：

- Unverified, 升级中系统往虚拟分区写完数据重启后，系统需要从虚拟分区启动；
- Merging, 系统处于 Merging 状态，此时 Source 槽位已经被更改，不可用，需要从虚拟分区启动；
- MergeFailed, 说明 Merge 失败，此时 Source 槽位已经被破坏，只能从虚拟分区启动；

因此，系统启动后，如果当前处于 Source 槽位，则往 RollbackIndicator 写入 1 来创建文件，并通过返回 false 表示当前启动不需要加载基于快照的虚拟分区；

> 思考题：
>
> 实际上只有当 BootIndicator 文件存在时，才会在启动阶段创建 RollbackIndicator 并写入 1，为什么？

### 3. RemoveAllUpdateState 和 FinishedSnapshotWrites 函数

这两个函数都包含了移除 RollbackIndicator  文件的操作。

- RemoveAllUpdateState 

  在前面分析 RemoveAllUpdateState  中说过，RemoveAllUpdateState 复位系统状态，删除所有快照以及相关的标识文件，包括 RollbackIndicator 

- FinishedSnapshotWrites 

  系统更新过程中，完成快照设备写入后，调用 FinishedSnapshotWrites  移除 RollbackIndicator 文件，只有当虚拟分区完成升级数据写入，但不能成功启动时才需要创建 RollbackIndicator 文件；

### 4. HandleCancelledUpdate 函数

```c++
bool SnapshotManager::HandleCancelledUpdate(LockedFile* lock,
                                            const std::function<bool()>& before_cancel) {
    // 获取当前系统槽位分区类型，Slot::Source 或者 Slot::Target，确保不是 Slot::Unknown
    auto slot = GetCurrentSlot();
    if (slot == Slot::Unknown) {
        return false;
    }

    // 1. 检查所有快照分区的状态是 UPDATED(false) 或 FLASHED(true)
    // If all snapshots were reflashed, then cancel the entire update.
    if (AreAllSnapshotsCancelled(lock)) {
        LOG(WARNING) << "Detected re-flashing, cancelling unverified update.";
        // 调用 RemoveAllUpdateState 移除所有快照，删除所有标识文件，并设置系统状态为 None
        return RemoveAllUpdateState(lock, before_cancel);
    }

    // 2. 获取当前系统槽位分区类型，Slot::Source 或者 Slot::Target
    //    如果当前在 Target 上，则无法执行 Cancel Update
    // If update has been rolled back, then cancel the entire update.
    // Client (update_engine) is responsible for doing additional cleanup work on its own states
    // when ProcessUpdateState() returns UpdateState::Cancelled.
    auto current_slot = GetCurrentSlot();
    if (current_slot != Slot::Source) {
        LOG(INFO) << "Update state is being processed while booting at " << current_slot
                  << " slot, taking no action.";
        return false;
    }

    // 3. 检查 RollbackIndicator 文件(/metadata/ota/rollback-indicator)是否可以访问
    // current_slot == Source. Attempt to detect rollbacks.
    if (access(GetRollbackIndicatorPath().c_str(), F_OK) != 0) {
        // This unverified update is not attempted. Take no action.
        PLOG(INFO) << "Rollback indicator not detected. "
                   << "Update state is being processed before reboot, taking no action.";
        return false;
    }

    // 4. 调用 RemoveAllUpdateState 复位系统状态，包括：
    //    移除所有快照，删除所有标识文件，并设置系统状态为 None
    LOG(WARNING) << "Detected rollback, cancelling unverified update.";
    return RemoveAllUpdateState(lock, before_cancel);
}
```

HandleCancelledUpdate 函数做了以下操作：

1. 检查所有快照分区的状态是 UPDATED(false) 或 FLASHED(true)，如果处于 FLASHED 状态，复位所有的系统状态；
2. 获取当前系统槽位分区类型，如果当前是升级的 Target 槽位，则取消操作；
3. 检查 RollbackIndicator 文件是否存在，如果不存在说明不能回滚了，不做任何取消操作；
4. 调用 RemoveAllUpdateState 复位系统状态为 None;



AreAllSnapshotsCancelled 函数检查所有快照分区的状态是 UPDATED(false) 或 FLASHED(true)，详细注释如下：

```c++
// 返回 super 设备中 metadata 数据保存的快照设备分区状态 UPDATED(false) 或 FLASHED(true)
bool SnapshotManager::AreAllSnapshotsCancelled(LockedFile* lock) {
    std::vector<std::string> snapshots;
    // 1. 检查 /metadata/ota/snapshots 目录，获取所有虚拟分区的快照设备名字并存放到 snapshots 中;
    if (!ListSnapshots(lock, &snapshots)) {
        LOG(WARNING) << "Failed to list snapshots to determine whether device has been flashed "
                     << "after applying an update. Assuming no snapshots.";
        // Let HandleCancelledUpdate resets UpdateState.
        return true;
    }

    std::map<std::string, bool> flashing_status;

    // 2. 检查所有快照分区的 flash 刷新状态
    //    GetSnapshotFlashingStatus 主要有以下操作：
    //    2.1 读取 super 设备中 Target 的 metadata 数据;
    //    2.2 遍历快照设备列表 snapshots 中的分区，并检查该分区在 metadata 分区表数据中的 attributes
    //        - 如果快照设备处于 UPDATED 状态，则 flashing_status 字典键值对的值为 false
    //        - 如果快照设备处于 FLASHED 状态，则 flashing_status 字典键值对的值为 true
    if (!GetSnapshotFlashingStatus(lock, snapshots, &flashing_status)) {
        LOG(WARNING) << "Failed to determine whether partitions have been flashed. Not"
                     << "removing update states.";
        return false;
    }

    // 3. 返回所有快照设备的 flashing_status 字典的键值对的值(UPDATED: false; FLASHED: true)
    // std::all_of：容器中是否所有元素都满足某个条件，是，则返回 true，否则返回 false
    bool all_snapshots_cancelled = std::all_of(flashing_status.begin(), flashing_status.end(),[](const auto& pair) { return pair.second; });

    if (all_snapshots_cancelled) {
        LOG(WARNING) << "All partitions are re-flashed after update, removing all update states.";
    }
    
    // 4. 返回所有快照设备是否为 UPDATED(false) 或 FLASHED(true) 状态
    return all_snapshots_cancelled;
}
```



### 5. RollbackIndicator 文件总结

对于 RollbackIndicator 文件，总结起来就是：

- 作用

  RollbackIndicator 文件用于指示当前系统在升级过程中是否处于可以回滚的，只有在升级过程中这个文件才有可能存在；

- 创建

  在系统启动的早期，通过 NeedSnapshotsInFirstStageMount 判断是否需要挂载快照设备，如果当前是 Source 槽位，就会通过写入"1"的方式来创建 RollbackIndicator 文件，表示系统处于可以回滚的状态；

- 访问

  在调用 HandleCancelledUpdate  取消升级时，如果查询 RollbackIndicator 文件，如果文件不存在，说明当前升级已经无法回滚了，因此 Cancel Update 不做任何操作；

- 删除

  - 在升级过程中，往虚拟分区写入升级数据完成后的重启前，FinishedSnapshotWrites  会删除 RollbackIndicator 文件，确保只有在升级重启后才会创建 RollbackIndicator 文件；
  - 在调用 RemoveAllUpdateState 复位系统状态时，删除所有快照以及相关的标识文件，包括 RollbackIndicator；

## 3. ForwardMergeIndicator

### 1. GetForwardMergeIndicatorPath 函数

GetForwardMergeIndicatorPath 函数返回 ForwareMergeIndicator 文件的路径 `/metadata/ota/allow-forward-merge`

```c++
std::string SnapshotManager::GetForwardMergeIndicatorPath() {
    return metadata_dir_ + "/allow-forward-merge";
}
```

### 

### 2. UpdateForwardMergeIndicator 函数

```c++
bool SnapshotManager::UpdateForwardMergeIndicator(bool wipe) {
    auto path = GetForwardMergeIndicatorPath();

    // 如果不执行 user data 分区的清除工作，则删除 ForwardMergeIndicator 文件
    if (!wipe) {
        LOG(INFO) << "Wipe is not scheduled. Deleting forward merge indicator.";
        return RemoveFileIfExists(path);
    }

    // TODO(b/152094219): Don't forward merge if no CoW file is allocated.

    // 如果要执行 user data 分区的清除工作，则在这里创建 ForwardMergeIndicator 文件
    LOG(INFO) << "Wipe will be scheduled. Allowing forward merge of snapshots.";
    if (!android::base::WriteStringToFile("1", path)) {
        PLOG(ERROR) << "Unable to write forward merge indicator: " << path;
        return false;
    }

    return true;
}
```

如果制作 OTA 包时，指定了 '--wipe_user_data' 选项，要求 Install 时擦除数据分区，则这里的 wipe 参数为 true，否则为 false。

有意思的是，如果不执行 wipe 操作，则这里需要删除 ForwardMergeIndicator 文件；

否则，如果要执行 wipe 操作，这里需要通过往 ForwardMergeIndicator 文件写入 1 来创建该文件；



因此，在 Postinstall 阶段，调用函数 FinishedSnapshotWrites，如果不需要清除 user data 分区，就删除 ForwardMergeIndicator 文件，否则就通过往文件写入 1 来创建。



按照目前我的理解是，清除 user data 分区的操作，需要进入 recovery 系统，所以需要创建 ForwardMergeIndicator  给 recovery 系统使用。



### 3. ProcessUpdateStateOnDataWipe 函数

在 recovery 环境下执行 Data Wipe 操作时调用 ProcessUpdateStateOnDataWipe 函数:

```c++
bool SnapshotManager::ProcessUpdateStateOnDataWipe(bool allow_forward_merge,
                                                   const std::function<bool()>& callback) {
    // 获取当前系统的 Slot Number
    auto slot_number = SlotNumberForSlotSuffix(device_->GetSlotSuffix());
    UpdateState state = ProcessUpdateState(callback);
    LOG(INFO) << "Update state in recovery: " << state;
    switch (state) {
        case UpdateState::MergeFailed:
            LOG(ERROR) << "Unrecoverable merge failure detected.";
            return false;
        case UpdateState::Unverified: {
            // If an OTA was just applied but has not yet started merging:
            //
            // - if forward merge is allowed, initiate merge and call
            // ProcessUpdateState again.
            //
            // - if forward merge is not allowed, we
            // have no choice but to revert slots, because the current slot will
            // immediately become unbootable. Rather than wait for the device
            // to reboot N times until a rollback, we proactively disable the
            // new slot instead.
            //
            // Since the rollback is inevitable, we don't treat a HAL failure
            // as an error here.
            // 在 recovery 环境中，如果当前是 Target 分区
            auto slot = GetCurrentSlot();
            if (slot == Slot::Target) {
                if (allow_forward_merge &&
                    access(GetForwardMergeIndicatorPath().c_str(), F_OK) == 0) {
                    LOG(INFO) << "Forward merge allowed, initiating merge now.";
                    // 开始 merge 操作，并且结束时通过传入 allow_forward_merge = false，将当前分区设置为不可启动
                    return InitiateMerge() &&
                           ProcessUpdateStateOnDataWipe(false /* allow_forward_merge */, callback);
                }

                // 当 allow_forward_merge = false 时，将当前的 Target 设置为不可启动(Unbootable)
                LOG(ERROR) << "Reverting to old slot since update will be deleted.";
                device_->SetSlotAsUnbootable(slot_number);
            } else {
                LOG(INFO) << "Booting from " << slot << " slot, no action is taken.";
            }
            break;
        }
        case UpdateState::MergeNeedsReboot:
            // We shouldn't get here, because nothing is depending on
            // logical partitions.
            LOG(ERROR) << "Unexpected merge-needs-reboot state in recovery.";
            break;
        default:
            break;
    }
    return true;
}
```



所以，在 recovery 环境下，调用 wipe data 时会检查 ForwardMergeIndicator 文件，如果存在，则开始执行 merge 操作，并在完成后将当前槽位(Target)设置为不能启动。



### 4. RemoveAllUpdateState 函数

前面 1.4 节详细分析过 RemoveAllUpdateState 函数，其作用是复位系统状态，因此在此时会删除 ForwardMergeIndicator 文件。



### 5. ForwardMergeIndicator 文件总结

对于 ForwardMergeIndicator 文件，总结起来就是：

- 作用

  ForwardMergeIndicator 文件用于指示当前系统是否支持 allow_forward_merge

- 创建

  在更新的 Postinstall 阶段，调用函数 FinishedSnapshotWrites，如果不需要清除 user data 分区，就删除 ForwardMergeIndicator 文件，否则就通过往文件写入 1 来创建。

- 访问

  在 recovery 环境下，调用 wipe data 时会检查 ForwardMergeIndicator 文件，如果存在，则开始执行 merge 操作，并在完成后将当前槽位(Target)设置为不能启动。

- 删除

   调用 RemoveAllUpdateState 函数时，复位系统状态，会删除 ForwardMergeIndicator 文件。



> 目前我对 allow_forward_merge 的具体使用场景还不是十分确定。
>
> 根据现在的代码理解是这样的，在虚拟分区写入数据完成后的 Postinstall 阶段，FinishedSnapshotWrites 函数根据是否需要清除用户分区执行不同的操作。
>
> 如果不需要清除 userdata 分区，而当前 ForwardMergeIndicator  文件又存在的话，就删除它。
>
> 如果需要清除 userdata 分区，就创建 ForwardMergeIndicator，然后再 recovery 环境下执行 userdata 分区的 wipe 操作时，会检查 ForwardMergeIndicator 文件。
>
> 如果此时 ForwardMergeIndicator 存在，就在 recovery 下开始 merge 操作，成功后将虚拟分区设置为不可启动(Unbootable)。



## 4. 标识文件总结

### 1. BootIndicator 文件

BootIndicator 文件位于 `/metadata/ota/snapshot-boot`，保存了 Source 槽位的后缀，用来指示当前升级的 Source 槽位。

在升级的 Postinstall 阶段，完成快照设备的数据更新后，函数 FinishedSnapshotWrites 中创建 BootIndicator 文件，并将升级源分区 Source 槽位的后缀写入到文件中。

后面的各种操作中，不管是在哪个系统，不管是在 Source(真实) 还是 Target(虚拟) 槽位，通过读取 BootIndicator 就能知道升级到的 Source 槽位。

在升级完成或错误处理中，调用 RemoveAllUpdateState 复位系统状态时，销毁 BootIndicator 文件；



### 2. RollbackIndicator 文件

RollbackIndicator 文件位于 /metadata/ota/rollback-indicator，其内容为 1，用于指示当前系统在升级过程中是否处于可以回滚的，只有在升级过程中这个文件才有可能存在；

在系统启动的早期，通过 NeedSnapshotsInFirstStageMount 判断是否需要挂载快照设备，如果当前是 Source 槽位，就会通过写入"1"的方式来创建 RollbackIndicator 文件，表示系统处于可以回滚的状态；

在调用 HandleCancelledUpdate  取消升级时，如果查询 RollbackIndicator 文件，如果文件不存在，说明当前升级已经无法回滚了，因此 Cancel Update 不做任何操作；

有两个地方可能会执行 RollbackIndicator 文件的删除操作：

- 在升级过程中，往虚拟分区写入升级数据完成后的重启前，FinishedSnapshotWrites  会删除 RollbackIndicator 文件，确保只有在升级重启后才会创建 RollbackIndicator 文件；

- 在调用 RemoveAllUpdateState 复位系统状态时，删除所有快照以及相关的标识文件，包括 RollbackIndicator；



### 5. ForwardMergeIndicator 文件

ForwardMergeIndicator 文件位于 `/metadata/ota/allow-forward-merge`，用于指示当前系统是否支持 allow_forward_merge 操作。

在更新的 Postinstall 阶段，调用函数 FinishedSnapshotWrites，如果不需要清除 user data 分区，就删除 ForwardMergeIndicator 文件，否则就通过往文件写入 1 来创建。

在 recovery 环境下，调用 wipe data 时会检查 ForwardMergeIndicator 文件，如果存在，则开始执行 merge 操作，并在完成后将当前槽位(Target)设置为不能启动。

调用 RemoveAllUpdateState 函数时，复位系统状态，会删除 ForwardMergeIndicator 文件。



> 目前我对 allow_forward_merge 的具体使用场景还不是十分确定。
>
> 根据现在的代码理解是这样的，在虚拟分区写入数据完成后的 Postinstall 阶段，FinishedSnapshotWrites 函数根据是否需要清除用户分区执行不同的操作。
>
> 如果不需要清除 userdata 分区，而当前 ForwardMergeIndicator  文件又存在的话，就删除它。
>
> 如果需要清除 userdata 分区，就创建 ForwardMergeIndicator，然后再 recovery 环境下执行 userdata 分区的 wipe 操作时，会检查 ForwardMergeIndicator 文件。
>
> 如果此时 ForwardMergeIndicator 存在，就在 recovery 下开始 merge 操作，成功后将虚拟分区设置为不可启动(Unbootable)。



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




# Android 虚拟 A/B 分区详解(六) SnapshotManager 之 状态数据



我在《Android 虚拟 A/B 详解(五) BootControl 的变化》中提到，打算分两篇来介绍系统升级过程中 merge 状态数据的存放和各种状态转换的问题。

上一篇详细分析了 merge 状态数据的的存放。按理说这一篇应该分析 merge 状态的转换，我甚至把状态转换的图都画好了，但不巧的是，随着我对代码阅读的深入，发现我在上一篇的一开始的表述是错误的：

> 实际上，记录系统 merge 状态的 merge status 数据不在 metadata 分区，而是在 misc 分区，这一切和 BootControl 为支持 Virtual A/B 的升级变化有关。

正确的表述应该是：

> 记录系统 merge 状态的 merge status 数据不仅存储在 misc 分区上，更详细的数据在 metadata 分区内，这一切和 Virtual A/B 的升级变化有关。



> 本文基于 Android 11.0.0_r21 版本的代码进行分析。
>
> 在线地址：http://aospxref.com/android-11.0.0_r21/



对于虚拟 A/B 系统来说，其虚拟的基础是 snapshot，核心是 libsnapshot 库，而 libsnapshot 中，一切操作都又交由类 SnapshotManager 处理，所以如没有搞懂 SnapshotManager 类的行为，很难说你掌握了 Android 虚拟 A/B 系统的运作方式。

libsnapshot 的源码位于 `system/core/fs_mgr/libsnapshot` 目录下面,，本篇和接下来的几篇会详细分析 libsnapshot 代码，完成后再回到虚拟 A/B 升级流程上。



## 1. snapshot.proto 文件

在 libsnapshot 的代码中，有一个文件 snapshot.proto，不知道你是否有留意到。这个文件的内容看起来不起眼，但其实相当重要。文件的内容如下：

```protobuf
// file: system/core/fs_mgr/libsnapshot/android/snapshot/snapshot.proto
syntax = "proto3";
package android.snapshot;

option optimize_for = LITE_RUNTIME;

// Next: 4
enum SnapshotState {
    // No snapshot is found.
    NONE = 0;

    // The snapshot has been created and possibly written to. Rollbacks are
    // possible by destroying the snapshot.
    CREATED = 1;

    // Changes are being merged. No rollbacks are possible beyond this point.
    MERGING = 2;

    // Changes have been merged, Future reboots may map the base device
    // directly.
    MERGE_COMPLETED = 3;
}

// Next: 9
message SnapshotStatus {
    // Name of the snapshot. This is usually the name of the snapshotted
    // logical partition; for example, "system_b".
    string name = 1;

    SnapshotState state = 2;

    // Size of the full (base) device.
    uint64 device_size = 3;

    // Size of the snapshot. This is the sum of lengths of ranges in the base
    // device that needs to be snapshotted during the update.
    // This must be less than or equal to |device_size|.
    // This value is 0 if no snapshot is needed for this device because
    // no changes
    uint64 snapshot_size = 4;

    // Size of the "COW partition". A COW partition is a special logical
    // partition represented in the super partition metadata. This partition and
    // the "COW image" form the "COW device" that supports the snapshot device.
    //
    // When SnapshotManager creates a COW device, it first searches for unused
    // blocks in the super partition, and use those before creating the COW
    // image if the COW partition is not big enough.
    //
    // This value is 0 if no space in super is left for the COW partition.
    // |cow_partition_size + cow_file_size| must not be zero if |snapshot_size|
    // is non-zero.
    uint64 cow_partition_size = 5;

    // Size of the "COW file", or "COW image". A COW file / image is created
    // when the "COW partition" is not big enough to store changes to the
    // snapshot device.
    //
    // This value is 0 if |cow_partition_size| is big enough to hold all changes
    // to the snapshot device.
    uint64 cow_file_size = 6;

    // Sectors allocated for the COW device. Recording this value right after
    // the update and before the merge allows us to infer the progress of the
    // merge process.
    // This is non-zero when |state| == MERGING or MERGE_COMPLETED.
    uint64 sectors_allocated = 7;

    // Metadata sectors allocated for the COW device. Recording this value right
    // before the update and before the merge allows us to infer the progress of
    // the merge process.
    // This is non-zero when |state| == MERGING or MERGE_COMPLETED.
    uint64 metadata_sectors = 8;
}

// Next: 8
enum UpdateState {
    // No update or merge is in progress.
    None = 0;

    // An update is applying; snapshots may already exist.
    Initiated = 1;

    // An update is pending, but has not been successfully booted yet.
    Unverified = 2;

    // The kernel is merging in the background.
    Merging = 3;

    // Post-merge cleanup steps could not be completed due to a transient
    // error, but the next reboot will finish any pending operations.
    MergeNeedsReboot = 4;

    // Merging is complete, and needs to be acknowledged.
    MergeCompleted = 5;

    // Merging failed due to an unrecoverable error.
    MergeFailed = 6;

    // The update was implicitly cancelled, either by a rollback or a flash
    // operation via fastboot. This state can only be returned by WaitForMerge.
    Cancelled = 7;
};

// Next: 5
message SnapshotUpdateStatus {
    UpdateState state = 1;

    // Total number of sectors allocated in the COW files before performing the
    // merge operation.  This field is used to keep track of the total number
    // of sectors modified to monitor and show the progress of the merge during
    // an update.
    uint64 sectors_allocated = 2;

    // Total number of sectors of all the snapshot devices.
    uint64 total_sectors = 3;

    // Sectors allocated for metadata in all the snapshot devices.
    uint64 metadata_sectors = 4;
}

// Next: 4
message SnapshotMergeReport {
    // Status of the update after the merge attempts.
    UpdateState state = 1;

    // Number of reboots that occurred after issuing and before completeing the
    // merge of all the snapshot devices.
    int32 resume_count = 2;

    // Total size of all the COW images before the update.
    uint64 cow_file_size = 3;
}
```

这个 snapshot.proto 文件在编译后会生成相应的 protobuf 数据类 SnapshotStatus, SnapshotUpdateStatus 和 SnapshotMergeReport。



在很长一段时间内，我都没搞懂这个文件定义的数据结构到底是干嘛用的~

在这个文件中，定义了两个 enum 表示状态的枚举字段，分别是：

- enum SnapshotState
- enum UpdateState

以及三个 message 表示 Snapshot 状态的消息字段：

- message SnapshotStatus
- message SnapshotUpdateStatus
- message SnapshotMergeReport

这 5 个东西非常接近，尤其是 State 和 Status，字面意思都是"状态"，真的，我一看就傻眼了，感觉这里的 5 个数据都一样，搞的什么鬼？完全懵逼了。

所以，如果您明白这 5 个定义的区别和用途，尤其是后面三个 message 的用途，那本篇可以不用看了。



为了直观一点，我把这里定义的数据用框图表示:

![MergeStatus](images-20230216-Android 虚拟分区详解(六) SnapshotManager 之 UpdateState/MergeStatus.png)

后面依次讲述这两三个 message 结构的用途



## 2. SnapshotUpdateStatus 结构

SnapshotUpdateStatus 表示当前系统的升级状态，相关的状态数据存储在设备的 state 文件 (`/metadata/ota/state`)中。

> 系统中，将 `/metadata/ota/state` 称为 state 文件

state 文件的读写操作通过以下两个函数来完成：

- `SnapshotManager::ReadUpdateState()`
- `SnapshotManager::WriteUpdateState(state)`

所以代码中如果调用这两个函数，那就是在读写 state 文件。



以下是我的某个设备上的 state 文件及其内容:

```bash
# 查看 state 文件
console:/ # ls -lh /metadata/ota/state                                         
-rw------- 1 root root 77 2022-10-11 00:00 /metadata/ota/state

# 查看 state 文件的内容
console:/ # xxd -g 1 /metadata/ota/state                                       
00000000: 08 01 42 49 67 6f 6f 67 6c 65 2f 69 6e 75 76 69  ..BIgoogle/inuvi
00000010: 6b 2f 69 6e 75 76 69 6b 3a 31 31 2f 52 56 43 2f  k/inuvik:11/RVC/
00000020: 65 6e 67 2e 72 67 39 33 35 37 2e 32 30 32 32 31  eng.rg9357.20221
00000030: 30 31 30 2e 32 31 30 36 31 36 3a 75 73 65 72 64  010.210616:userd
00000040: 65 62 75 67 2f 64 65 76 2d 6b 65 79 73           ebug/dev-keys
```



### 1. ReadUpdateState 函数

```c++
// system/core/fs_mgr/libsnapshot/snapshot.cpp
UpdateState SnapshotManager::ReadUpdateState(LockedFile* lock) {
    /* 调用 ReadSnapshotUpdateStatus 函数完成实际的操作 */
    SnapshotUpdateStatus status = ReadSnapshotUpdateStatus(lock);
    return status.state();
}

SnapshotUpdateStatus SnapshotManager::ReadSnapshotUpdateStatus(LockedFile* lock) {
    CHECK(lock);

    SnapshotUpdateStatus status = {};
    std::string contents;
    /* 读取 state 文件(/metadata/ota/state)的 protobuf 数据 */
    if (!android::base::ReadFileToString(GetStateFilePath(), &contents)) {
        PLOG(ERROR) << "Read state file failed";
        status.set_state(UpdateState::None);
        return status;
    }

    /* 将读取的 protobuf 数据转换成 SnapshotUpdateStatus 结构 */
    if (!status.ParseFromString(contents)) {
        LOG(WARNING) << "Unable to parse state file as SnapshotUpdateStatus, using the old format";

        // Try to rollback to legacy file to support devices that are
        // currently using the old file format.
        // TODO(b/147409432)
        status.set_state(UpdateStateFromString(contents));
    }

    /* 返回读取到的 SnapshotUpdateStatus 数据 */
    return status;
}
```

从上面可见，ReadUpdateState() 函数的实现比较简单，主要做了两件事：

- 读取 /metadata/ota/state 的内容(protobuf 数据)
- 将读取到的数据还原成 SnapshotUpdateStatus



### 2. WriteUpdateState 函数

```c++
// system/core/fs_mgr/libsnapshot/snapshot.cpp
bool SnapshotManager::WriteUpdateState(LockedFile* lock, UpdateState state) {
    SnapshotUpdateStatus status = {};
    status.set_state(state);
  /* 调用 WriteSnapshotUpdateStatus 函数完成对 state 文件的写入操作 */
    return WriteSnapshotUpdateStatus(lock, status);
}

bool SnapshotManager::WriteSnapshotUpdateStatus(LockedFile* lock,
                                                const SnapshotUpdateStatus& status) {
    CHECK(lock);
    CHECK(lock->lock_mode() == LOCK_EX);

    std::string contents;
    /* 1. 先把 SnapshotUpdateStatus 串行化为 protobuf 数据 */
    if (!status.SerializeToString(&contents)) {
        LOG(ERROR) << "Unable to serialize SnapshotUpdateStatus.";
        return false;
    }

/* LIBSNAPSHOT_USE_HAL 在 system/core/fs_mgr/libsnapshot/Android.bp 文件中定义 */
#ifdef LIBSNAPSHOT_USE_HAL
    /* 2. 将系统当前的 SnapshotUpdateStatus 转换成 MergeStatus */
    auto merge_status = MergeStatus::UNKNOWN;
    switch (status.state()) {
        // The needs-reboot and completed cases imply that /data and /metadata
        // can be safely wiped, so we don't report a merge status.
        case UpdateState::None:
        case UpdateState::MergeNeedsReboot:
        case UpdateState::MergeCompleted:
        case UpdateState::Initiated:
            merge_status = MergeStatus::NONE;
            break;
        case UpdateState::Unverified:
            merge_status = MergeStatus::SNAPSHOTTED;
            break;
        case UpdateState::Merging:
        case UpdateState::MergeFailed:
            merge_status = MergeStatus::MERGING;
            break;
        default:
            // Note that Cancelled flows to here - it is never written, since
            // it only communicates a transient state to the caller.
            LOG(ERROR) << "Unexpected update status: " << status.state();
            break;
    }

    /*
     * 3. 将串行化的 SnapshotUpdateStatus 数据写入到 state 文件中，同时更新系统的 MergeStatus
     */

    /* 3.1 对于 MergeStatus 为 SNAPSHOTTED 和 MERGING 的情况，
     * 先调用 SetBootControlMergeStatus 把状态写入到 misc 分区的结构中
     */
    bool set_before_write =
            merge_status == MergeStatus::SNAPSHOTTED || merge_status == MergeStatus::MERGING;
    if (set_before_write && !device_->SetBootControlMergeStatus(merge_status)) {
        return false;
    }
#endif

    /* 3.2 将串行化的 protobuf 数据写入 state 文件中 */
    if (!WriteStringToFileAtomic(contents, GetStateFilePath())) {
        PLOG(ERROR) << "Could not write to state file";
        return false;
    }

    /* 3.3 对于 MergeStatus 为 None 的情况，
     * 可以在更新完 state 文件再调用 SetBootControlMergeStatus 写入 misc 分区
     */
#ifdef LIBSNAPSHOT_USE_HAL
    if (!set_before_write && !device_->SetBootControlMergeStatus(merge_status)) {
        return false;
    }
#endif
    return true;
}
```

这里 WriteUpdateState 也是做了 3 件事：

1. 将系统的 SnapshotUpdateStatus 串行化为 protobuf 数据，方便写入
2. 将系统的 SnapshotUpdateStatus 转换为对应的 MergeStatus
3. 将系统的 SnapshotUpdateStatus 写入 state 文件，将 MergeStatus 通过 IBootControl 的接口 setSnapshotMergeStatus 写入到 misc 分区中;

这里的 setSnapshotMergeStatus，就是上一篇中分析的 IBootControl 接口实现的函数了。具体由各 OEM 厂家实现，但大多数都和 Android 的参考实现差不多。



> 思考题 1：
>
> 这里的函数 ReadUpdateState 和 WriteUpdateState 分别用于 state 文件的读写，那 state 文件是什么时候创建？又是什么时候删除的呢？

### 3. UpdateState 状态

系统定义的 UpdateState 状态有 8 个，分别是：

- None
- Initiated
- Unverified
- Merging
- MergeNeedsReboot
- MergeCompleted
- MergeFailed
- Cancelled

我们可以搜索代码看下什么时候会调用 `WriteUpdateState()` 函数设置：

从这里可以看到，

- 在 **BeginUpdate()** 中会往 state 文件写入状态 Initiated；

- 在 **RemoveAllUpdateState()** 中会往 state 文件写入状态 None;

- 在 **FinishedSnapshotWrites()** 中会会往 state 文件写入状态 Unverified;

- 在 **InitiateMerge()** 中有两处设置状态的地方：

  - 当开始合并(merge)时，会调用 WriteSnapshotUpdateStatus 会往 state 文件写入状态 Merging;

  - 如果系统切换到快照的 Merge 目标失败，则调用 WriteUpdateState 会往 state 文件写入状态 MergeFailed;

- 在 **CheckMergeState()** 中，如果合并(merge)完成要求重启，会往 state 文件写入状态 MergeNeedsReboot;

- 在确认合并成功的函数 **AcknowledgeMergeSuccess()** 中，
  - 如果当前是 recovery 系统会往 state 文件写入状态 MergeCompleted, 
  - 如果当前不是 recovery 系统，则调用 RemoveAllUpdateState() 会往 state 文件写入状态 None;

- 我在系统中没有找到将 Cancelled 写入 state 文件的地方



> 思考题 2：
>
> 什么情况下会调用上面的 BeginUpdate(), RemoveAllUpdate(), FinishedSnapshotWrites(), InitateMerge(), CheckMergeState() 和 AcknowledgeMergeSuccess() 函数？



这里讨论的是 state 文件中保存的 UpdateState 状态。

实际上，在 CleanupPreviousUpdateAction 类中，有一个关于当前系统状态 UpdateState 的状态机，用于在每次启动 Update Engine 服务时，基于当前系统的 UpdateState 进行相应状态的切换。

CleanupPreviousUpdateAction  类的状态切换操作比较复杂，值得后面单独一篇说明，这里不再深入。

## 3. SnapshotMergeReport 结构

SnapshotMergeReport  结构被封装在 SnapshotMergeStats 类的内部，其结构数据存储在设备的 merge state(`/metadata/ota/merge_state`) 文件中。

> 系统中，将 `/metadata/ota/merge_state` 称为 merge state 文件



特别注意的是，这里是 SnapshotMergeStats 类中的是 Stats，不是 Status，表示的是统计的意思。按照我的理解，大概就是用来统计 merge 进行了几次，花费了多少时间。



### 1. SnapshotMergeStats 类的操作

SnapshotMergeStats  在 `system/core/fs_mgr/libsnapshot/snapshot_stats.cpp`文件中实现。

通过 SnapshotMergeStats 类的函数来操作 merge state 文件，这些函数包括：

- `SnapshotMergeStats::ReadState()`，读 merge state 文件
- `SnapshotMergeStats::WriteState()`，写 merge state 文件
- `SnapshotMergeStats::DeleteState()`, 删除 merge state 文件
- `SnapshotMergeStats::Start()`， 记录本次 merge 开始时间，如果 merge state 文件已经存在，则对其 resume count 字段 +1，如果不存在，则设置 resume count 字段为 0
- `SnapshotMergeStats::set_state(state)`，更新 merge state 文件的 state 字段
- `SnapshotMergeStats::set_cow_file_size(cow_file_size)`，更新 merge state 文件的 cow file size 字段
- `SnapshotMergeStats::cow_file_size()`，获取 merge state 文件的 cow file size 字段
- `SnapshotMergeStats::Result SnapshotMergeStats::Finish()`，如果当前 merge 操作正在进行，返回从调用 Start() 到当前调用 Finish() 所花费的总时间，由于明确调用了 Finsh() 表示完成，所以会一并删除 merge state 文件



>  思考题 3：
>
> 这里再 DeleteState 时会删除 merge state 文件，那又是什么时候创建的 merge state 文件的呢？

那什么时候会去调用 SnapshotMergeStats 的这些统计操作呢？不妨去代码中找找看。

### 2. ReadState(), WriteState(), DeleteState() 操作

ReadState(), WriteState(), DeleteState() 只有在 SnapshotMergeStats 类自己的实现中才有调用，所以不用关心。



### 3. Start() 操作

在每次启动 Update Engine 服务一开始的 CleanupPreviousUpdateAction 操作中会调用 Start() 操作，

```c++
void CleanupPreviousUpdateAction::CheckSlotMarkedSuccessfulOrSchedule() {
  TEST_AND_RETURN(running_);
  
  //...

  if (!merge_stats_->Start()) {
    // Not an error because CleanupPreviousUpdateAction may be paused and
    // resumed while kernel continues merging snapshots in the background.
    LOG(WARNING) << "SnapshotMergeStats::Start failed.";
  }
  LOG(INFO) << "Waiting for any previous merge request to complete. "
            << "This can take up to several minutes.";
  WaitForMergeOrSchedule();
}
```



### 4. set_state() 和 set_cow_file_size() 操作

同样，在 CleanupPreviousUpdateAction 的 WaitForMergeOrSchedule() 和 InitiateMergeAndWait() 操作中会调用 set_state() 去将当前系统的状态设置到 merge state 文件中。

- WaitForMergeOrSchedule() 函数

```c++
void CleanupPreviousUpdateAction::WaitForMergeOrSchedule() {
  TEST_AND_RETURN(running_);
  auto state = snapshot_->ProcessUpdateState(
      std::bind(&CleanupPreviousUpdateAction::OnMergePercentageUpdate, this),
      std::bind(&CleanupPreviousUpdateAction::BeforeCancel, this));
  /* 将 ProcessUpdateState 返回的状态写入到 merge state 文件中 */
  merge_stats_->set_state(state);

  // ...
}
```

- InitiateMergeAndWait() 函数

```c++
void CleanupPreviousUpdateAction::InitiateMergeAndWait() {
  TEST_AND_RETURN(running_);
  //...

  uint64_t cow_file_size;
  if (snapshot_->InitiateMerge(&cow_file_size)) {
    merge_stats_->set_cow_file_size(cow_file_size);
    WaitForMergeOrSchedule();
    return;
  }

  LOG(WARNING) << "InitiateMerge failed.";
  auto state = snapshot_->GetUpdateState();
  merge_stats_->set_state(state);
  if (state == UpdateState::Unverified) {
    // We are stuck at unverified state. This can happen if the update has
    // been applied, but it has not even been attempted yet (in libsnapshot,
    // rollback indicator does not exist); for example, if update_engine
    // restarts before the device reboots, then this state may be reached.
    // Nothing should be done here.
    LOG(WARNING) << "InitiateMerge leaves the device at "
                 << "UpdateState::Unverified. (Did update_engine "
                 << "restarted?)";
    processor_->ActionComplete(this, ErrorCode::kSuccess);
    return;
  }

  // ...
  return;
}
```

注意，这里除了调用 `set_state()` 往 merge state 文件写入当前系统的升级状态之前，还会调用 `set_cow_file_size()` 写入当前的 cow file size 信息。



### 5. cow_file_size() 和 Finish() 操作

在 CleanupPreviousUpdateAction 类的 ReportMergeStats 函数中，可以看到 SnapshotMergeReport 的真正用途。

```c++
void CleanupPreviousUpdateAction::ReportMergeStats() {
  /* 通过 SnapshotMergeStats 类的 Finish() 操作返回 SnapshotMergeStats::Result 类 */
  auto result = merge_stats_->Finish();
  if (result == nullptr) {
    LOG(WARNING) << "Not reporting merge stats because "
                    "SnapshotMergeStats::Finish failed.";
    return;
  }

#ifdef __ANDROID_RECOVERY__
  LOG(INFO) << "Skip reporting merge stats in recovery.";
#else
  /* report() 操作返回 SnapshotMergeStats 内部的 SnapshotMergeReport 结构 */
  const auto& report = result->report();

  if (report.state() == UpdateState::None ||
      report.state() == UpdateState::Initiated ||
      report.state() == UpdateState::Unverified) {
    LOG(INFO) << "Not reporting merge stats because state is "
              << android::snapshot::UpdateState_Name(report.state());
    return;
  }

  /* merge_time() 操作返回从调用Start() 到当前调用 Finish() 的时间差 */
  auto passed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
      result->merge_time());

  bool vab_retrofit = boot_control_->GetDynamicPartitionControl()
                          ->GetVirtualAbFeatureFlag()
                          .IsRetrofit();

  /* 报告当前的系统状态，中间 resume 操作的次数，以及 cow 文件的大小 */
  LOG(INFO) << "Reporting merge stats: "
            << android::snapshot::UpdateState_Name(report.state()) << " in "
            << passed_ms.count() << "ms (resumed " << report.resume_count()
            << " times), using " << report.cow_file_size()
            << " bytes of COW image.";
  android::util::stats_write(android::util::SNAPSHOT_MERGE_REPORTED,
                             static_cast<int32_t>(report.state()),
                             static_cast<int64_t>(passed_ms.count()),
                             static_cast<int32_t>(report.resume_count()),
                             vab_retrofit,
                             static_cast<int64_t>(report.cow_file_size()));
#endif
}
```



从文件名字看，这里是要报告 merge 状态。

因此，SnapshotMergeReport 结构最终用来在 ReportMergeStats() 调用时显示：

- 此次 merge 从 Start() 调用到 Finish() 的时间；
- 从开始 merge 到调用 Finsh() 中间停止和恢复的次数；
- 使用的 cow 文件的大小



到这里，SnapshotMergeStats 的所有操作都跟踪完了。

## 4. SnapshotStatus 结构

### 1. 快照设备状态文件

SnapshotStatus 表示系统中某个虚拟分区设备的状态，相关的状态数据存储在快照设备状态文件(SnapshotStatusFile)中，一个快照设备对应一个快照设备状态文件，多个快照设备就有多个快照设备状态文件，这些状态文件位于目录 /metadata/ota/snapshots 下，例如：

- system_b 的快照设备状态文件：`/metadata/ota/snapshots/system_b`
- vendor_b 的快照设备状态文件: `/metadata/ota/snpahsots/vendor_b`



为了方便起见，后面统一以 system_b 分区为例。

> 系统中，将 `/metadata/ota/snapshots/system_b` 称为 system_b分区的快照设备状态文件



以下是我的某个设备上的快照设备状态文件及其内容：

```bash
# 查看 /metadata/ota/snapshots/ 目录下的文件
console:/ # ls -lh /metadata/ota/snapshots/                                    
total 8.0K
-rw------- 1 root root 47 2022-10-11 00:00 system_b
-rw------- 1 root root 37 2022-10-11 00:00 vendor_b

# 查看 /metadata/ota/snapshots/{system_b,vendor_b} 的文件内容
console:/ # xxd -g 1 /metadata/ota/snapshots/system_b                          
00000000: 0a 08 73 79 73 74 65 6d 5f 62 10 01 18 80 a0 a4  ..system_b......
00000010: da 04 20 80 a0 a4 da 04 28 80 80 ea 38 30 80 a0  .. .....(...80..
00000020: f7 c4 03 50 80 80 a3 da 04 5a 04 6e 6f 6e 65     ...P.....Z.none
console:/ # xxd -g 1 /metadata/ota/snapshots/vendor_b                          
00000000: 0a 08 76 65 6e 64 6f 72 5f 62 10 01 18 80 e0 b1  ..vendor_b......
00000010: 26 20 80 e0 b1 26 30 80 e0 3b 50 80 e0 b1 26 5a  & ...&0..;P...&Z
00000020: 04 6e 6f 6e 65                                   .none
console:/ # 
```



### 2. 快照设备状态文件的读写

快照设备状态文件的读写操作通过以下两个函数来完成：

- `SnapshotManager::ReadSnapshotStatus(name, &status)`
- `SnapshotManager::WriteSnapshotStatus(status)`

所以代码中如果调用这两个函数，那就是在读写名为 name 的分区的快照设备状态文件，即：

```bash
/metadata/ota/snapshots/name
```



这两个函数的代码实现也十分直观：

- 读取快照设备状态文件

```c++
bool SnapshotManager::ReadSnapshotStatus(LockedFile* lock, const std::string& name,
                                         SnapshotStatus* status) {
    CHECK(lock);
    /* 获取分区名为 name 的快照设备状态文件路径，例如：/metadata/ota/snapshots/system_b */
    auto path = GetSnapshotStatusFilePath(name);

    unique_fd fd(open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
    if (fd < 0) {
        PLOG(ERROR) << "Open failed: " << path;
        return false;
    }

    /* 解析快照设备状态文件的 protobuf 数据 */
    if (!status->ParseFromFileDescriptor(fd.get())) {
        PLOG(ERROR) << "Unable to parse " << path << " as SnapshotStatus";
        return false;
    }

    /* 检查实际读取的快照设备状态文件内的 name 和这里传入分区名称 name 是否一致 */
    if (status->name() != name) {
        LOG(WARNING) << "Found snapshot status named " << status->name() << " in " << path;
        status->set_name(name);
    }

    return true;
}

bool SnapshotManager::WriteSnapshotStatus(LockedFile* lock, const SnapshotStatus& status) {
    // The caller must take an exclusive lock to modify snapshots.
    CHECK(lock);
    CHECK(lock->lock_mode() == LOCK_EX);
    CHECK(!status.name().empty());

    /* 获取分区名为 name 的快照设备状态文件路径，例如：/metadata/ota/snapshots/system_b */
    auto path = GetSnapshotStatusFilePath(status.name());

    std::string content;
    /* 将当前的 SnapshotStatus 串行化为 protobuf 数据 */
    if (!status.SerializeToString(&content)) {
        LOG(ERROR) << "Unable to serialize SnapshotStatus for " << status.name();
        return false;
    }

    /* 将串行化的 SnapshotStatus 数据写入到相应的快照设备状态文件中 */
    if (!WriteStringToFileAtomic(content, path)) {
        PLOG(ERROR) << "Unable to write SnapshotStatus to " << path;
        return false;
    }

    return true;
}
```



### 3. 快照设备状态文件的删除

前一节提到快照设备状态文件的读写，留意一下代码就会发现，这里也没有关于快照设备状态文件的创建和删除操作。

那快照设备状态文件到底是在哪里创建，又是在什么时候删除的呢？

搜索代码就能发现，在 DeleteSnapshot() 操作中删除快照设备状态文件

```c++
bool SnapshotManager::DeleteSnapshot(LockedFile* lock, const std::string& name) {
    CHECK(lock);
    CHECK(lock->lock_mode() == LOCK_EX);
    //...

    std::string error;
    /* 获取当前虚拟分区的快照设备状态文件的路径，并删除 */
    auto file_path = GetSnapshotStatusFilePath(name);
    if (!android::base::RemoveFileIfExists(file_path, &error)) {
        LOG(ERROR) << "Failed to remove status file " << file_path << ": " << error;
        return false;
    }
    return true;
}
```



> 思考题 4：
>
> 到底是在哪里创建的快照设备状态文件呢？例如：/metadata/ota/snapshots/system_b



### 4. 对 WriteSnapshotStatus() 的调用

代码中调用 WriteSnapshotStatus() 的地方主要有 3 处：

- CreateSnapshot

```c++
bool SnapshotManager::CreateSnapshot(LockedFile* lock, SnapshotStatus* status) {
    CHECK(lock);
    CHECK(lock->lock_mode() == LOCK_EX);
    CHECK(status);

    /* 这里省略了对传入的 status 的一顿各种检查 */

    status->set_state(SnapshotState::CREATED);
    status->set_sectors_allocated(0);
    status->set_metadata_sectors(0);

    /* 更新分区快照设备状态文件 */
    if (!WriteSnapshotStatus(lock, *status)) {
        PLOG(ERROR) << "Could not write snapshot status: " << status->name();
        return false;
    }
    return true;
}
```

在创建快照的函数 CreateSnapshot 中似乎就只是做了一个更新分区快照设备状态文件的操作，真是名不副实。

- SwitchSnapshotToMerge

```c++
bool SnapshotManager::SwitchSnapshotToMerge(LockedFile* lock, const std::string& name) {
    SnapshotStatus status;
    if (!ReadSnapshotStatus(lock, name, &status)) {
        return false;
    }
    // ...将快照目标 snapshot 切换成 snapshot-merge 目标

    status.set_state(SnapshotState::MERGING);

    DmTargetSnapshot::Status dm_status;
    if (!QuerySnapshotStatus(dm_name, nullptr, &dm_status)) {
        LOG(ERROR) << "Could not query merge status for snapshot: " << dm_name;
    }
    status.set_sectors_allocated(dm_status.sectors_allocated);
    status.set_metadata_sectors(dm_status.metadata_sectors);
  
    /* 更新分区快照设备状态文件 */
    if (!WriteSnapshotStatus(lock, status)) {
        LOG(ERROR) << "Could not update status file for snapshot: " << name;
    }
    return true;
}
```

- CheckTargetMergeState

```c++
UpdateState SnapshotManager::CheckTargetMergeState(LockedFile* lock, const std::string& name) {
    SnapshotStatus snapshot_status;
    if (!ReadSnapshotStatus(lock, name, &snapshot_status)) {
        return UpdateState::MergeFailed;
    }

    //...这里省略了各种这样那样的操作
  
    // Merging is done. First, update the status file to indicate the merge
    // is complete. We do this before calling OnSnapshotMergeComplete, even
    // though this means the write is potentially wasted work (since in the
    // ideal case we'll immediately delete the file).
    //
    // This makes it simpler to reason about the next reboot: no matter what
    // part of cleanup failed, first-stage init won't try to create another
    // snapshot device for this partition.
  
    /* 更新分区快照设备状态文件，将状态设置为 MERGE_COMPLETED */
    snapshot_status.set_state(SnapshotState::MERGE_COMPLETED);
    if (!WriteSnapshotStatus(lock, snapshot_status)) {
        return UpdateState::MergeFailed;
    }
    //...
    return UpdateState::MergeCompleted;
}
```

总结一下，调用 WriteSnapshotStatus 更新分区快照设备状态文件的地方有 3 个，分别是创建快照，将快照从 snapshot 切换到 snapshot-merge 目标时，以及 merge 完成的检查中，将分区的快照设备状态更新为 MERGE_COMPLETED。



### 5. 对 ReadSnapshotStatus() 的调用

调用 ReadSnapshotStatus 读取分区快照设备状态文件的地方很多，这里列举几个我找到的：

- CreateCowImage
- MapSnapshot
- InitiateMerge
- SwitchSnapshotToMerge
- CheckTargetMergeState
- ReadSnapshotStatus
- MapPartitionWithSnapshot
- Dump

具体的调用操作函数这里不再详细跟踪，总体上，凡是要对分区快照设备进行操作的地方，都可以调用 ReadSnapshotStatus 查询分区快照设备的状态，可以自行试着去了解各个地方去读取快照设备状态的具体用途。

## 5. 总结

上面啰啰嗦嗦说了一大堆，大致就是说 snapshot.proto 文件

> 位置: system/core/fs_mgr/libsnapshot/android/snapshot/snapshot.proto

在编译时会生成 3 个类:

- SnapshotStatus 类
- SnapshotUpdateStatus 类
- SnapshotMergeReport 类

和 2 个枚举类型数据：

- SnapshotState 枚举
- UpdateState 枚举



## 6. 思考题汇总








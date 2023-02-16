# Android 虚拟 A/B 分区详解(六) SnapshotManager 之 UpdateState



我在《Android 虚拟 A/B 详解(五) BootControl 的变化》中提到，打算分两篇来介绍系统升级过程中 merge 状态数据的存放和各种状态转换的问题。

上一篇详细分析了 merge 状态数据的的存放。按理说这一篇应该分析 merge 状态的转换，我甚至把状态转换的图都画好了，但不巧的是，随着我对代码阅读的深入，发现我在上一篇的一开始的表述是错误的：

> 实际上，记录系统 merge 状态的 merge status 数据不在 metadata 分区，而是在 misc 分区，这一切和 BootControl 为支持 Virtual A/B 的升级变化有关。

正确的表述应该是：

> 记录系统 merge 状态的 merge status 数据不仅存储在 misc 分区上，更详细的数据在 metadata 分区内，这一切和 Virtual A/B 的升级变化有关。



对于虚拟 A/B 系统来说，其虚拟的基础是 snapshot，核心是 libsnapshot 库，而 libsnapshot 中，一切操作都又交由类 SnapshotManager 处理，所以如没有搞懂 SnapshotManager 类的行为，很难说你掌握了 Android 虚拟 A/B 系统的运作方式。

libsnapshot 的源码位于 `system/core/fs_mgr/libsnapshot` 目录下面,，本篇和接下来的几篇会详细分析 libsnapshot 代码，完成后再回到虚拟 A/B 升级流程上。



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



在很长一段时间内，我都没搞懂这个文件定义的数据结构到底是干嘛用的~

在这个文件中，定义了两个 enum 表示状态的枚举字段，分别是：

- enum SnapshotState
- enum UpdateState

以及三个 message 表示 Snapshot 状态的消息字段：

- message SnapshotStatus
- message SnapshotUpdateStatus
- message SnapshotMergeReport

这 5 个东西非常接近，尤其是 State 和 Status，字面意思都是"状态"，真的，我一看就傻眼了，感觉这里的 5 个数据都一样，搞的什么鬼？完全懵逼了。

所以，如果您明白这 5 个定义的区别和用户，尤其是后面三个 message 的用途，那本篇可以不用看了。



把这里的成员换成框图的形式，如下：








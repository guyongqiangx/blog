# 20230312-Android 虚拟 A/B 详解(九) cow 的存储位置是如何确定的？

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
>
> 对 linux 快照(snapshot) 的了解可以增加对虚拟 A/B 分区的理解：
>
> - [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
> - [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。



## 0. 导读

上一篇[《Android 虚拟 A/B 详解(八) cow 的大小是如何计算的？》](https://blog.csdn.net/guyongqiangx/article/details/129470881)详细分析了快照(snapshot)设备的后端 COW 空间所需大小是如何计算的。

文档 Android_VirtualAB_Design_Performance_Caveats.pdf 中有提到，VAB 在升级更新分区时，对于 COW 设备，可能由 super 设备上的空闲块，以及 `/data` 分区中的文件构成，如下：

![snapshot of system_b partition](images-20230312-Android 虚拟分区详解(九)/snapshot-of-system_b.png)

**图 1. system_b 快照设备的构成**



简而言之，在升级创建 COW 设备时，会先利用 super 设备上的空闲分区，不够的部分再从 userdata 分区(/data) 下分配文件，然后把这两部分拼接映射出 COW 设备。

具体上是如何操作的呢？本文通过跟踪代码为您解开这个答案。



> 本文基于 Android 11.0.0_r21 版本的代码进行分析。
>
> 在线地址：http://aospxref.com/android-11.0.0_r21/



## 1. OTA 更新的核心流程

虚拟 A/B 分区的重点就是升级过程中对虚拟分区的处理，包括虚拟分区的创建，管理和删除。

> 这里的虚拟分区实际上就是基于某个实体分区创建的快照设备(snapshot)



那么，OTA 升级中，虚拟分区是在什么时候被创建的呢？

让我们先从整个 OTA 的更新流程说起。

我在好几篇里面都提到过，升级更新最核心的函数是 `DeltaPerformer::Write()`。

> 参考:
>
> - [《Android Update Engine 分析（七） DownloadAction 之 FileWriter》](https://blog.csdn.net/guyongqiangx/article/details/82805813)
>
> - [《Android Update Engine 分析（十八）差分数据到底是如何更新的？》](https://guyongqiangx.blog.csdn.net/article/details/129464805)

在 Android  11 代码中，这个 Write() 函数主要的调用层次关系如下：(`-->` 表示函数调用)

```
DeltaPerformer::Write()
   --> DeltaPerformer::UpdateOverallProgress()
   --> DeltaPerformer::ParsePayloadMetadata()
   --> DeltaPerformer::ValidateManifest()
   --> DeltaPerformer::ParseManifestPartitions()
      --> DynamicPartitionControlAndroid::PreparePartitionsForUpdate(&required_size)
         --> DynamicPartitionControlAndroid::PrepareSnapshotPartitionsForUpdate()
            --> SnapshotManager::CreateUpdateSnapshots(manifest)
               --> SnapshotManager::CreateUpdateSnapshotsInternal()
                  --> PartitionCowCreator::Run()
                  --> SnapshotManager::CreateSnapshot(status)
                  --> MetadataBuilder::AddPartition(name)
                  --> MetadataBuilder::ResizePartition(name)
                  --> SnapshotManager::CreateCowImage(name)
               --> SnapshotManager::InitializeUpdateSnapshots(metadata, target_suffix)
                  --> SnapshotManager::MapCowDevices()
                  --> CreateDmTable(table)
                  --> DeviceMapper::CreateDevice(name, uuid)
                  --> InitializeCow(device)
                  --> UpdatePartitionTable(super, metadata,slot_number)
   --> DeltaPerformer::PrimeUpdateState()
   --> DeltaPerformer::OpenCurrentPartition() 
   --> DeltaPerformer::ValidateOperationHash(operation)
   --> DeltaPerformer::PerformXxxOperation(operation.type)
   --> DeltaPerformer::HandleOpResult(op_result,op_type_name)
   --> DeltaPerformer::UpdateOverallProgress()
   --> DeltaPerformer::CheckpointUpdateProgress(false)
```

从上面这个层次关系可以看到，升级中所有关于分区准备的工作在 `DeltaPerformer::ParseManifestPartitions()` 中完成了。

一旦虚拟分区准备完成，我们就把虚拟分区当成传统的另外一个真实槽位分区，因此剩余的更新工作还是和虚拟分区之前的情况一样。甚至和刚引入 A/B 系统的 Android 7.1.2_r39 中的流程都是一样的。

> Android 7.1.2_r39 在线代码: http://aospxref.com/android-7.1.2_r39



在 `DeltaPerformer::ParseManifestPartitions()` 内部的重重调用中，最终的虚拟分区创建工作由 SnapshotManager 类的 `CreateUpdateSnapshots(manifest)` 函数来完成。

`CreateUpdateSnapshots` 函数内部主要分成两部分：

- CreateUpdateSnapshotsInternal，主要用于虚拟分区快照相关 COW 文件的分配和创建
- InitializeUpdateSnapshots，主要基于上一步创建好的 COW 文件，最终映射出虚拟分区



既然本文聚焦于 COW 文件是如何创建的，那我们的焦点自然就是 `CreateUpdateSnapshotsInternal()` 函数。



## 2.



如图 1 所说，创建虚拟虚拟分区快照，需要 COW 文件的参与。



整个虚拟快照创建的核心流程在 CreateUpdateSnapshotsInternal 函数。



```c++
/* system/core/fs_mgr/libsnapshot/snapshot.cpp */
Return SnapshotManager::CreateUpdateSnapshotsInternal(
        LockedFile* lock, const DeltaArchiveManifest& manifest, PartitionCowCreator* cow_creator,
        AutoDeviceList* created_devices,
        std::map<std::string, SnapshotStatus>* all_snapshot_status) {
    CHECK(lock);

    auto* target_metadata = cow_creator->target_metadata;
    const auto& target_suffix = cow_creator->target_suffix;

    if (!target_metadata->AddGroup(kCowGroupName, 0)) {
        LOG(ERROR) << "Cannot add group " << kCowGroupName;
        return Return::Error();
    }

    std::map<std::string, const RepeatedPtrField<InstallOperation>*> install_operation_map;
    std::map<std::string, std::vector<Extent>> extra_extents_map;
    for (const auto& partition_update : manifest.partitions()) {
        auto suffixed_name = partition_update.partition_name() + target_suffix;
        auto&& [it, inserted] =
                install_operation_map.emplace(suffixed_name, &partition_update.operations());
        if (!inserted) {
            LOG(ERROR) << "Duplicated partition " << partition_update.partition_name()
                       << " in update manifest.";
            return Return::Error();
        }

        auto& extra_extents = extra_extents_map[suffixed_name];
        if (partition_update.has_hash_tree_extent()) {
            extra_extents.push_back(partition_update.hash_tree_extent());
        }
        if (partition_update.has_fec_extent()) {
            extra_extents.push_back(partition_update.fec_extent());
        }
    }

    for (auto* target_partition : ListPartitionsWithSuffix(target_metadata, target_suffix)) {
        cow_creator->target_partition = target_partition;
        cow_creator->operations = nullptr;
        auto operations_it = install_operation_map.find(target_partition->name());
        if (operations_it != install_operation_map.end()) {
            cow_creator->operations = operations_it->second;
        }

        cow_creator->extra_extents.clear();
        auto extra_extents_it = extra_extents_map.find(target_partition->name());
        if (extra_extents_it != extra_extents_map.end()) {
            cow_creator->extra_extents = std::move(extra_extents_it->second);
        }

        // Compute the device sizes for the partition.
        auto cow_creator_ret = cow_creator->Run();
        if (!cow_creator_ret.has_value()) {
            return Return::Error();
        }

        LOG(INFO) << "For partition " << target_partition->name()
                  << ", device size = " << cow_creator_ret->snapshot_status.device_size()
                  << ", snapshot size = " << cow_creator_ret->snapshot_status.snapshot_size()
                  << ", cow partition size = "
                  << cow_creator_ret->snapshot_status.cow_partition_size()
                  << ", cow file size = " << cow_creator_ret->snapshot_status.cow_file_size();

        // Delete any existing snapshot before re-creating one.
        if (!DeleteSnapshot(lock, target_partition->name())) {
            LOG(ERROR) << "Cannot delete existing snapshot before creating a new one for partition "
                       << target_partition->name();
            return Return::Error();
        }

        // It is possible that the whole partition uses free space in super, and snapshot / COW
        // would not be needed. In this case, skip the partition.
        bool needs_snapshot = cow_creator_ret->snapshot_status.snapshot_size() > 0;
        bool needs_cow = (cow_creator_ret->snapshot_status.cow_partition_size() +
                          cow_creator_ret->snapshot_status.cow_file_size()) > 0;
        CHECK(needs_snapshot == needs_cow);

        if (!needs_snapshot) {
            LOG(INFO) << "Skip creating snapshot for partition " << target_partition->name()
                      << "because nothing needs to be snapshotted.";
            continue;
        }

        // Store these device sizes to snapshot status file.
        if (!CreateSnapshot(lock, &cow_creator_ret->snapshot_status)) {
            return Return::Error();
        }
        created_devices->EmplaceBack<AutoDeleteSnapshot>(this, lock, target_partition->name());

        // Create the COW partition. That is, use any remaining free space in super partition before
        // creating the COW images.
        if (cow_creator_ret->snapshot_status.cow_partition_size() > 0) {
            CHECK(cow_creator_ret->snapshot_status.cow_partition_size() % kSectorSize == 0)
                    << "cow_partition_size == "
                    << cow_creator_ret->snapshot_status.cow_partition_size()
                    << " is not a multiple of sector size " << kSectorSize;
            auto cow_partition = target_metadata->AddPartition(GetCowName(target_partition->name()),
                                                               kCowGroupName, 0 /* flags */);
            if (cow_partition == nullptr) {
                return Return::Error();
            }

            if (!target_metadata->ResizePartition(
                        cow_partition, cow_creator_ret->snapshot_status.cow_partition_size(),
                        cow_creator_ret->cow_partition_usable_regions)) {
                LOG(ERROR) << "Cannot create COW partition on metadata with size "
                           << cow_creator_ret->snapshot_status.cow_partition_size();
                return Return::Error();
            }
            // Only the in-memory target_metadata is modified; nothing to clean up if there is an
            // error in the future.
        }

        all_snapshot_status->emplace(target_partition->name(),
                                     std::move(cow_creator_ret->snapshot_status));

        LOG(INFO) << "Successfully created snapshot partition for " << target_partition->name();
    }

    LOG(INFO) << "Allocating CoW images.";

    for (auto&& [name, snapshot_status] : *all_snapshot_status) {
        // Create the backing COW image if necessary.
        if (snapshot_status.cow_file_size() > 0) {
            auto ret = CreateCowImage(lock, name);
            if (!ret.is_ok()) return AddRequiredSpace(ret, *all_snapshot_status);
        }

        LOG(INFO) << "Successfully created snapshot for " << name;
    }

    return Return::Ok();
}
```


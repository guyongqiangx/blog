# 20230312-Android 虚拟 A/B 详解(九) cow 的存储是如何分配的？

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 原文链接：https://blog.csdn.net/guyongqiangx/article/details/129494397



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
> - [Android 虚拟 A/B 详解(九) cow 的存储是如何分配的？](https://blog.csdn.net/guyongqiangx/article/details/129494397)
>
> 对 linux 快照(snapshot) 的了解可以增加对虚拟 A/B 分区的理解：
>
> - [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
> - [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

## 0. 导读

上一篇[《Android 虚拟 A/B 详解(八) cow 的大小是如何计算的？》](https://blog.csdn.net/guyongqiangx/article/details/129470881)详细分析了快照(snapshot)设备的后端 COW 空间所需大小是如何计算的。

文档 Android_VirtualAB_Design_Performance_Caveats.pdf 中有提到，虚拟 A/B 在升级更新分区时，对于 COW 设备，可能由 super 设备上的空闲块，以及 `/data` 分区中的文件构成，原文如下：

![snapshot of system_b partition](images-20230312-Android 虚拟分区详解(九)/snapshot-of-system_b.png)

**图 1. system_b 快照设备的构成**



简而言之，在升级创建 COW 设备时，会先利用 super 设备上的空闲分区，不够的部分再从 userdata 分区(/data) 下分配文件，然后把这两部分拼接映射出 COW 设备。

具体上是如何操作的呢？本文通过跟踪代码为您解开这个答案。



由于涉及代码注释，所以看起来难免有些啰嗦。

如果只关心虚拟分区创建的大致流程，请转到第 1 节；

如果只想知道 COW 倒是是如何创建出来的，请跳转到第 3 节；

如果只想知道 COW 内部是如何判断要在 super 设备还是 /data 目录创建文件，请跳转到第 4 节；

如果只想知道 COW 设备创建的流程，又不想深入代码，请跳转到第 5 节查看总结。



> 本文基于 Android 11.0.0_r21 版本的代码进行分析。
>
> 在线地址：http://aospxref.com/android-11.0.0_r21/

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。

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
> - [《Android Update Engine 分析（十八）差分数据到底是如何更新的？》](https://blog.csdn.net/guyongqiangx/article/details/129464805)

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

- CreateUpdateSnapshotsInternal，主要用于虚拟分区快照相关 COW 文件的计算和创建
- InitializeUpdateSnapshots，主要基于上一步创建好的 COW 文件，最终映射出虚拟分区



既然本文聚焦于 COW 文件是如何创建的，那我们的焦点自然就是 `CreateUpdateSnapshotsInternal()` 函数。



## 2. 快照 COW 文件的创建

上一节说了，CreateUpdateSnapshotsInternal() 函数主要用于虚拟分区快照相关 COW 文件的计算和创建。

虚拟 A/B 在创建快照分区时，其 COW 空间对应的 cow 文件，先从 super 设备上的空闲块分配，不够的部分再从 `/data` 文件夹( userdata 分区)分配。

如果 super 设备上的空闲块足够分配 COW 所需空间，比如从 Android 10 动态分区系统升级上来的设备，super 设备上包含了 A/B 两套系统的空间，此时就会直接从 super 上分配空间给 cow，不再另外从 `/data` 目录下分配。



### 1. CreateUpdateSnapshotsInternal 是如何被调用的？

在开始详细注释 `CreateUpdateSnapshotsInternal()` 代码之前，先看下这个函数在 `CreateUpdateSnapshots()`中是如何被调用的:

```c++
Return SnapshotManager::CreateUpdateSnapshots(const DeltaArchiveManifest& manifest) {
    // ...

    /*
     * 1. 准备 all_snapshot_status，用于保存创建 cow 的所有快照的状态
     */
    std::map<std::string, SnapshotStatus> all_snapshot_status;

    // In case of error, automatically delete devices that are created along the way.
    // Note that "lock" is destroyed after "created_devices", so it is safe to use |lock| for
    // these devices.
    /*
     * 2. 准备 created_devices 用于保存所有创建快照分区的名字构建的 AutoDeleteSnapshot, 失败时会自动删除相应 snapshot
     */
    AutoDeviceList created_devices;

    /*
     * 3. 准备 cow_creator, 用于计算各种空间需求
     */
    PartitionCowCreator cow_creator{
            .target_metadata = target_metadata.get(),
            .target_suffix = target_suffix,
            .target_partition = nullptr,
            .current_metadata = current_metadata.get(),
            .current_suffix = current_suffix,
            .operations = nullptr,
            .extra_extents = {},
    };

    /*
     * 4. 传入 manifest 数据，根据内部的分区，计算并分配快照需要的 cow 文件
     */
    auto ret = CreateUpdateSnapshotsInternal(lock.get(), manifest, &cow_creator, &created_devices, &all_snapshot_status);
    if (!ret.is_ok()) return ret;

    //...

    return Return::Ok();
}
```



这里提取的只是 CreateUpdateSnapshots 中调用 CreateUpdateSnapshotsInternal  函数的关键代码点而已，

事实上，整个 CreateUpdateSnapshots 函数基本上都是在为调用 CreateUpdateSnapshotsInternal 做准备。

主要的准备包括：

- all_snapshot_status 用于返回所有快照分区的状态信息，供后面操作使用
- created_devices 用于保存所有以快照分区名字构建的 AutoDeleteSnapshot, 创建失败时自动销毁 snapshot
- cow_creator 用于计算创建 snapshot 的各种空间需求

然后将 manifest 数据传递给 CreateUpdateSnapshotsInternal 函数，后者在内部借助 cow_creator  计算并分配虚拟分区的 cow 文件。



### 2. CreateUpdateSnapshotsInternal  详细注释

整个虚拟快照创建的核心流程在 CreateUpdateSnapshotsInternal 函数，以下是函数的详细注释：

```c++
/* file: system/core/fs_mgr/libsnapshot/snapshot.cpp */
Return SnapshotManager::CreateUpdateSnapshotsInternal(
        LockedFile* lock, const DeltaArchiveManifest& manifest, PartitionCowCreator* cow_creator,
        AutoDeviceList* created_devices,
        std::map<std::string, SnapshotStatus>* all_snapshot_status) {
    CHECK(lock);

    auto* target_metadata = cow_creator->target_metadata;
    const auto& target_suffix = cow_creator->target_suffix;

    /*
     * 1. 在目标槽位对应的动态分区 metadata 中添加名为 cow 的 group, 参数 0 表示大小没有限制。
     *    动态分区的 metadata 默认有 3 个 group，以 google 参考设备为例，默认包含了：
     *    - default, 
     *    - google_dynamic_partitions_a, 
     *    - google_dynamic_partitions_b
     */
    if (!target_metadata->AddGroup(kCowGroupName, 0)) {
        LOG(ERROR) << "Cannot add group " << kCowGroupName;
        return Return::Error();
    }

    /*
     * 2. 遍历 manifest 中的所有分区，提取每个分区的 operations，以及其 hash tree 和 fec 的 extents
     */
    std::map<std::string, const RepeatedPtrField<InstallOperation>*> install_operation_map;
    std::map<std::string, std::vector<Extent>> extra_extents_map;
    for (const auto& partition_update : manifest.partitions()) {
        // 获取带有后缀的目标分区名字，例如 system_b, vendor_b
        auto suffixed_name = partition_update.partition_name() + target_suffix;
        // 获取所有目标分区的 operation，保存到 install_operation_map 中
        auto&& [it, inserted] =
                install_operation_map.emplace(suffixed_name, &partition_update.operations());
        if (!inserted) {
            LOG(ERROR) << "Duplicated partition " << partition_update.partition_name()
                       << " in update manifest.";
            return Return::Error();
        }

        // 检查所有目标分区是否存在 hash tree 和 fec 相关的区段，并将其数据保存到 extra_extents 中
        auto& extra_extents = extra_extents_map[suffixed_name];
        if (partition_update.has_hash_tree_extent()) {
            extra_extents.push_back(partition_update.hash_tree_extent());
        }
        if (partition_update.has_fec_extent()) {
            extra_extents.push_back(partition_update.fec_extent());
        }
    }

    /*
     * 3. 遍历所有以 target_suffix 结尾的分区(例如所有以 '_b' 结尾的分区)，计算所需 cow，分配快照空间
     */
    for (auto* target_partition : ListPartitionsWithSuffix(target_metadata, target_suffix)) {
        cow_creator->target_partition = target_partition;
        cow_creator->operations = nullptr;
        /*
         * 3.1 保存从 manifest 中提取的分区 operations，用于计算 cow
         */
        auto operations_it = install_operation_map.find(target_partition->name());
        if (operations_it != install_operation_map.end()) {
            cow_creator->operations = operations_it->second;
        }

        /*
         * 3.2 保存从 manifest 中提取的分区 extra extents，用于计算 cow
         */
        cow_creator->extra_extents.clear();
        auto extra_extents_it = extra_extents_map.find(target_partition->name());
        if (extra_extents_it != extra_extents_map.end()) {
            cow_creator->extra_extents = std::move(extra_extents_it->second);
        }

        /*
         * 3.3 cow_creator->Run() 函数内部计算 cow 所需空间，设置从 super 和 /data 分配空间的大小
         *     1). 计算 super 设备的空闲块，
         *     2). 以及通过分区 operation 和 extra extents 计算 COW 所需空间的大小，
         *     3). 设置从 super 分配 cow 的大小(cow_partition_size)，
         *     4). 以及从 /data 分配 cow 文件的大小(cow_file_size)。
         *     输出 log: "Remaining free space for COW: 119177216 bytes"
         */
        // Compute the device sizes for the partition.
        auto cow_creator_ret = cow_creator->Run();
        if (!cow_creator_ret.has_value()) {
            return Return::Error();
        }

        /*
         * 3.4 输出 cow 状态信息 log：
         * "For partition system_b, device size = 1263079424, snapshot size = 1263079424, cow partition size = 119177216, cow file size = 1148841984"
         */
        LOG(INFO) << "For partition " << target_partition->name()
                  << ", device size = " << cow_creator_ret->snapshot_status.device_size()
                  << ", snapshot size = " << cow_creator_ret->snapshot_status.snapshot_size()
                  << ", cow partition size = "
                  << cow_creator_ret->snapshot_status.cow_partition_size()
                  << ", cow file size = " << cow_creator_ret->snapshot_status.cow_file_size();

        /*
         * 3.5 删除目标分区已有的快照设备
         */
        // Delete any existing snapshot before re-creating one.
        if (!DeleteSnapshot(lock, target_partition->name())) {
            LOG(ERROR) << "Cannot delete existing snapshot before creating a new one for partition "
                       << target_partition->name();
            return Return::Error();
        }

        /*
         * 3.6 检查是否需要进行快照
         *     1). snapshot_size > 0 说明需要对设备做快照
         *     2). cow_partition_size 表示从 super 设备上分批用于 cow 的空间大小
         *     3). cow_file_size 表示从 /data 分区分配用于 cow 文件的大小
         *     4). 只有当需要从 super 设备或 /data 分区分配 cow 时，才说明需要快照，即 needs_cow = 1
         */
        // It is possible that the whole partition uses free space in super, and snapshot / COW
        // would not be needed. In this case, skip the partition.
        bool needs_snapshot = cow_creator_ret->snapshot_status.snapshot_size() > 0;
        bool needs_cow = (cow_creator_ret->snapshot_status.cow_partition_size() +
                          cow_creator_ret->snapshot_status.cow_file_size()) > 0;
        CHECK(needs_snapshot == needs_cow);

        /*
         * 不需要快照的情况下，直接跳过当前分区所有创建 snapshot 的操作
         */
        if (!needs_snapshot) {
            LOG(INFO) << "Skip creating snapshot for partition " << target_partition->name()
                      << "because nothing needs to be snapshotted.";
            continue;
        }

        /*
         * 3.7 创建当前分区快照状态文件
         *     例如: /metadata/ota/snapshots/system_b
         */
        // Store these device sizes to snapshot status file.
        if (!CreateSnapshot(lock, &cow_creator_ret->snapshot_status)) {
            return Return::Error();
        }
        created_devices->EmplaceBack<AutoDeleteSnapshot>(this, lock, target_partition->name());

        /*
         * 3.8 根据 cow_partition_size，在 super 设备上创建相应大小的 cow 分区
         */
        // Create the COW partition. That is, use any remaining free space in super partition before
        // creating the COW images.
        if (cow_creator_ret->snapshot_status.cow_partition_size() > 0) {
            CHECK(cow_creator_ret->snapshot_status.cow_partition_size() % kSectorSize == 0)
                    << "cow_partition_size == "
                    << cow_creator_ret->snapshot_status.cow_partition_size()
                    << " is not a multiple of sector size " << kSectorSize;
            /*
             * a. 在 metadata 中添加 cow 分区，例如：system_b，新创建的分区为 system_b-cow
             */
            auto cow_partition = target_metadata->AddPartition(GetCowName(target_partition->name()),
                                                               kCowGroupName, 0 /* flags */);
            if (cow_partition == nullptr) {
                return Return::Error();
            }

            /*
             * b. 在 metadata 中设置 cow 分区大小
             *    输出 log: "Partition system_b-cow will resize from 0 bytes to 119177216 bytes"
             */
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

        /*
         * 3.9 将分区的快照状态保存到 all_snapshot_status 给外界使用
         */
        all_snapshot_status->emplace(target_partition->name(),
                                     std::move(cow_creator_ret->snapshot_status));

        LOG(INFO) << "Successfully created snapshot partition for " << target_partition->name();
    }

    /*
     * 4. 遍历所有分区的快照状态数据，如果状态信息中 cow_file_size > 0, 则在目录 /data/gsi/ota/ 下创建相应分区的 cow 文件
     *   例如: /data/gsi/ota/system_b-cow-img
     */
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

汇总一下 CreateUpdateSnapshotsInternal 函数所做的事情：

1. 在目标槽位对应的动态分区 metadata 中添加名为 cow 的 group。
    对于动态分区，默认有 3 个 group，以 google 参考设备为例，分别是 `default`, `google_dynamic_partitions_a` 和 `google_dynamic_partitions_b`。
    对于虚拟分区，由于 super 设备上只有一个槽位数据，所以 A/B 槽位的 slot 只有一个。

2. 遍历 manifest 中的所有分区，提取每个分区的 operations，以及其 hash tree 和 fec 的 extents 用于后面计算各分区需要的 cow 大小。

3. 遍历 metadata 中所有以 target_suffix 结尾的分区(例如所有以 '_b' 结尾的分区)，执行以下操作:
  1. 保存从 manifest 中提取的分区 operations，用于计算 cow
  2. 保存从 manifest 中提取的分区 extra extents，用于计算 cow
  3. 调用 `PartitionCowCreator::Run()` 函数，计算快照的 cow 所需空间，设置 cow_partition_size 和 cow_file_size

    1). 计算 super 设备的空闲块，
    2). 通过分区 operations 和 extra extents 计算 COW 所需空间的大小，
    3). 设置从 super 分配 cow 的大小(`cow_partition_size`)，
    4). 以及从 /data 分配 cow 文件的大小(`cow_file_size`)。
    5). 输出 log: "`Remaining free space for COW: 119177216 bytes`"
  4. 输出 cow 状态信息 log："`For partition system_b, device size = 1263079424, snapshot size = 1263079424, cow partition size = 119177216, cow file size = 1148841984`"
  5. 如果目标分区存在快照设备，则删除目标分区现有的快照设备
  6. 检查当前分区是否需要进行快照

    1). `snapshot_size` 表示分区快照设备的大小， snapshot_size > 0 说明需要对设备做快照
    2). `cow_partition_size` 表示从 super 设备上分批用于 cow 的空间大小
    3). `cow_file_size` 表示从 /data 分区分配用于 cow 文件的大小
    4). 只有当需要从 super 设备或 /data 分区分配 cow 时，才说明需要快照，即 `needs_cow = 1`
  7. 创建当前分区快照状态文件，例如: `/metadata/ota/snapshots/system_b`
  8. 根据 `cow_partition_size`，在 super 设备上创建相应大小的 cow 分区，例如: system_b-cow
  9. 将分区的快照状态数据保存到 `all_snapshot_status` 中


4. 遍历所有分区的快照状态数据，如果状态信息中 `cow_file_size > 0`, 则在目录 /data/gsi/ota/ 下创建相应分区的 cow 文件。例如: `system_b-cow-img.img`

  ```bash
  console:/ # ls -lh /data/gsi/ota/                                                
  total 454M
  -rw------- 1 root root   26 2022-10-11 00:00 system_b-cow-img.img
  -rw------- 1 root root 906M 2022-10-11 00:00 system_b-cow-img.img.0000
  -rw------- 1 root root   26 2022-10-11 00:00 vendor_b-cow-img.img
  -rw------- 1 root root 956K 2022-10-11 00:00 vendor_b-cow-img.img.0000
  console:/ # xxd -g 1 /data/gsi/ota/system_b-cow-img.img                          
  00000000: 73 79 73 74 65 6d 5f 62 2d 63 6f 77 2d 69 6d 67  system_b-cow-img
  00000010: 2e 69 6d 67 2e 30 30 30 30 0a                    .img.0000.
  ```

### 3. PartitionCowCreator::Run() 函数

在上一节注释 CreateUpdateSnapshotsInternal  函数时，步骤 3.3 只做了简单说明，这里将这个函数展开详细分析。

这个 Run 函数主要是计算快照分区 COW 所需空间，并将计算的内容保存在 snapshot_status 结构中。

snapshot_status 是定义在 snapshot.proto 文件中 SnapshotStatus 消息结构的实例对象。

> snapshot.proto 文件位于: system/core/fs_mgr/libsnapshot/android/snapshot/snapshot.proto

```c++
/* file: system/core/fs_mgr/libsnapshot/partition_cow_creator.cpp */
std::optional<PartitionCowCreator::Return> PartitionCowCreator::Run() {
    CHECK(current_metadata->GetBlockDevicePartitionName(0) == LP_METADATA_DEFAULT_PARTITION_NAME &&
          target_metadata->GetBlockDevicePartitionName(0) == LP_METADATA_DEFAULT_PARTITION_NAME);

    const uint64_t logical_block_size = current_metadata->logical_block_size();
    CHECK(logical_block_size != 0 && !(logical_block_size & (logical_block_size - 1)))
            << "logical_block_size is not power of 2";

    /*
     * 1. 设置 snapshot_status 的 name, device_size 和 snapshot_size
     */
    Return ret;
    ret.snapshot_status.set_name(target_partition->name());
    ret.snapshot_status.set_device_size(target_partition->size());
    ret.snapshot_status.set_snapshot_size(target_partition->size());

    /*
     * 2. 如果设备的 snapshot_size =0，则说明该设备不需要快照，直接返回
     */
    if (ret.snapshot_status.snapshot_size() == 0) {
        LOG(INFO) << "Not creating snapshot for partition " << ret.snapshot_status.name();
        ret.snapshot_status.set_cow_partition_size(0);
        ret.snapshot_status.set_cow_file_size(0);
        return ret;
    }

    /*
     * 3. 计算 super 设备上的空闲区域
     */
    // Being the COW partition virtual, its size doesn't affect the storage
    // memory that will be occupied by the target.
    // The actual storage space is affected by the COW file, whose size depends
    // on the chunks that diverged between |current| and |target|.
    // If the |target| partition is bigger than |current|, the data that is
    // modified outside of |current| can be written directly to |current|.
    // This because the data that will be written outside of |current| would
    // not invalidate any useful information of |current|, thus:
    // - if the snapshot is accepted for merge, this data would be already at
    // the right place and should not be copied;
    // - in the unfortunate case of the snapshot to be discarded, the regions
    // modified by this data can be set as free regions and reused.
    // Compute regions that are free in both current and target metadata. These are the regions
    // we can use for COW partition.
    auto target_free_regions = target_metadata->GetFreeRegions();
    auto current_free_regions = current_metadata->GetFreeRegions();
    auto free_regions = Interval::Intersect(target_free_regions, current_free_regions);
    uint64_t free_region_length = 0;
    for (const auto& interval : free_regions) {
        free_region_length += interval.length();
    }
    free_region_length *= kSectorSize;

    /*
     * 4. 计算快照设备所需要的 COW 空间大小
     */
    LOG(INFO) << "Remaining free space for COW: " << free_region_length << " bytes";
    auto cow_size = GetCowSize();

    /*
     * 5. 设置 COW 在 super 设备上使用的空间大小 cow_partition_size
     *    如果 super 上剩余空间比所需的 COW 空间还大，则全部 COW 都从 super 设备的空闲块分配；
     *    如果 super 上剩余空间小于 COW 空间，则先使用完 super 设备上的空闲空间；
     */
    // Compute the COW partition size.
    uint64_t cow_partition_size = std::min(cow_size, free_region_length);
    // Round it down to the nearest logical block. Logical partitions must be a multiple
    // of logical blocks.
    cow_partition_size &= ~(logical_block_size - 1);
    ret.snapshot_status.set_cow_partition_size(cow_partition_size);
    // Assign cow_partition_usable_regions to indicate what regions should the COW partition uses.
    ret.cow_partition_usable_regions = std::move(free_regions);

    /*
     * 6. 设置 COW 在 /data 目录下分配的 cow 文件大小 cow_file_size
     *    如果 COW 空间都在 super 设备上分配，则此时 cow_file_size = 0，不再需要从 /data 目录分配文件；
     */
    auto cow_file_size = cow_size - cow_partition_size;
    // Round it up to the nearest sector.
    cow_file_size += kSectorSize - 1;
    cow_file_size &= ~(kSectorSize - 1);
    ret.snapshot_status.set_cow_file_size(cow_file_size);

    return ret;
}
```



`PartitionCowCreator::Run()` 函数内部的计算过程如下：

1. 设置 snapshot_status 的 name, device_size 和 snapshot_size

2. 如果设备的 snapshot_size =0，则说明该设备不需要快照，直接返回

3. 计算 super 设备上的空闲区域

4. 计算快照设备所需要的 COW 空间大小

5. 设置 COW 在 super 设备上使用的空间大小 cow_partition_size

   如果 super 上剩余空间比所需的 COW 空间还大，则全部 COW 都从 super 设备的空闲块分配；

   如果 super 上剩余空间小于 COW 空间，则先使用完 super 设备上的空闲空间；

6. 设置 COW 在 /data 目录下分配的 cow 文件大小 cow_file_size

   如果 COW 空间都在 super 设备上分配，则此时 cow_file_size = 0，不再需要从 /data 目录分配文件；



特别需要说明的是，snapshot.proto 文件中 SnapshotStatus 消息结构有两个成员 `cow_partition_size` 和 `cow_file_size`，分别用于表示快照从 super 设备分配空间用于 cow 的大小，和从 `/data` 目录下分配 cow 文件的大小。二者之和，就是整个快照设备 cow 的大小，即：

`cow_size = cow_partition_size + cow_file_size`



更新某个分区创建快照设备所需 cow 文件大小的计算，请参考上一篇 [《Android 虚拟 A/B 详解(八) cow 的大小是如何计算的？》](https://blog.csdn.net/guyongqiangx/article/details/129470881)



## 3. 快照 COW 文件的存储

在前一节中提到，`PartitionCowCreator::Run()` 函数会根据 manifest 中的 InstallOperation, 以及 hash tree 和 fec 数据，计算快照分区 COW 所需空间。

如果 super 设备上还有空闲空间，则 `cow_partition_size` 表示 super 分区上分配用于 COW 的空间大小；剩余不足的部分从 userdata 分区(/data 目录)分配，这部分大小由 `cow_file_size` 表示。

这一节我们详细分析 super 设备和 `/data` 目录下的 COW 到底是如何存储的。

### 1. super 设备上的 COW

在 CreateUpdateSnapshotsInternal()  函数中是这样处理 `cow_partition_size > 0` 的情况的：

> 假设当前系统运行在 system_a 上，以升级虚拟的 system_b 为例。

```c++
// Create the COW partition. That is, use any remaining free space in super partition before
// creating the COW images.
if (cow_creator_ret->snapshot_status.cow_partition_size() > 0) {
    CHECK(cow_creator_ret->snapshot_status.cow_partition_size() % kSectorSize == 0)
            << "cow_partition_size == "
            << cow_creator_ret->snapshot_status.cow_partition_size()
            << " is not a multiple of sector size " << kSectorSize;
    /*
     * 1. 在 super 设备名为 cow 的 group 上创建名为 system_b-cow 的分区
     */
    auto cow_partition = target_metadata->AddPartition(GetCowName(target_partition->name()),
                                                       kCowGroupName, 0 /* flags */);
    if (cow_partition == nullptr) {
        return Return::Error();
    }

    /*
     * 2. 根据 cow_partition_size 和 super 设备上可用的区域调整 system_b-cow 分区大小
     */
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
```



在 super 设备上分配 COW 主要有以下两个操作：

1. 在 super 设备名为 "cow" 的 group 上创建名为 `system_b-cow` 的分区；
2. 根据 `cow_partition_size` 调整 super 设备上 `system_b-cow` 分区大小(主要是对齐调整)



### 2. /data 目录中的 COW

在 CreateUpdateSnapshotsInternal()  函数中是这样处理 `cow_file_size > 0` 的情况的：

```c++
LOG(INFO) << "Allocating CoW images.";

/* 遍历所有虚拟分区的 snapshot_status */
for (auto&& [name, snapshot_status] : *all_snapshot_status) {
    // Create the backing COW image if necessary.
    if (snapshot_status.cow_file_size() > 0) {
        /* 根据 name，在 /data 下分配相应分区的 cow 文件 */
        auto ret = CreateCowImage(lock, name);
        /* 分配 cow 文件失败，计算并打印所需空间信息 */
        if (!ret.is_ok()) return AddRequiredSpace(ret, *all_snapshot_status);
    }

    LOG(INFO) << "Successfully created snapshot for " << name;
}
```

这里从 /data 下分配 cow 比较简单，直接传入分区名字，然后一个调用 `CreateCowImage(lock, name)` 搞定。



####CreateCowImage 函数 

具体是怎么做的呢？让我们深入一层往下看看 `CreateCowImage()` 函数的实现：

```c++
/* file: system/core/fs_mgr/libsnapshot/snapshot.cpp */
Return SnapshotManager::CreateCowImage(LockedFile* lock, const std::string& name) {
    CHECK(lock);
    CHECK(lock->lock_mode() == LOCK_EX);
    /*
     * 1. 基于 ota 目录创建 IImageManager 对象，该对象的 metadata 位于 /metadata/gsi/ota 目录，data 位于 /data/gsi/ota 目录
     */
    if (!EnsureImageManager()) return Return::Error();

    /*
     * 2. 根据分区名读取快照状态文件，
     *    例如 system_b 的快照状态文件位于: /metadata/ota/snapshots/system_b
     */
    SnapshotStatus status;
    if (!ReadSnapshotStatus(lock, name, &status)) {
        return Return::Error();
    }

    // The COW file size should have been rounded up to the nearest sector in CreateSnapshot.
    // Sanity check this.
    if (status.cow_file_size() % kSectorSize != 0) {
        LOG(ERROR) << "Snapshot " << name << " COW file size is not a multiple of the sector size: "
                   << status.cow_file_size();
        return Return::Error();
    }

    /*
     * 3. 调用 ImageManager::CreateBackingImage() 分配 cow 文件
     */
    std::string cow_image_name = GetCowImageDeviceName(name);
    int cow_flags = IImageManager::CREATE_IMAGE_DEFAULT;
    return Return(images_->CreateBackingImage(cow_image_name, status.cow_file_size(), cow_flags));
}
```

说来说去，CreateCowImage() 函数并不是真正干活的那位，它干的事情主要有：

1. 确保基于 ota 目录创建的 IImageManager 对象被正确初始化。

   该对象的 metadata 位于 /metadata/gsi/ota 目录，data 位于 /data/gsi/ota 目录

2. 根据分区名读取快照状态文件(例如: /metadata/ota/snapshots/system_b)，提取快照的 `cow_file_size`数据

3. 把 name 和 `cow_file_size`作为参数传递给 `CreateBackingImage()`，让它真正去干文件分配的活。



所以，最后真正干活的是 `ImageManager::CreateBackingImage()` 函数。



#### CreateBackingImage 函数

```c++
/* file: system/core/fs_mgr/libfiemap/image_manager.cpp */
FiemapStatus ImageManager::CreateBackingImage(
        const std::string& name, uint64_t size, int flags,
        std::function<bool(uint64_t, uint64_t)>&& on_progress) {
    /*
     * 1. 获取 cow image 在 ota data 目录下的路径名称(例如: /data/gsi/ota/system_b-cow-img.img)
     *    对于 IImageManager 对象，其 data 目录在 EnsureImageManager()已经初始化为 /data/gsi/ota
     *    所以如果这里要创建 system_b 的 cow 文件，则相应的路径为:
     *    /data/gsi/ota/system_b-cow-img.img
     */
    auto data_path = GetImageHeaderPath(name);
    std::unique_ptr<SplitFiemap> fw;

    /*
     * 2. 使用 SplitFiemap 的方式在 /data/gsi/ota 下创建文件，如果申请一个超大文件，将会被分成多个子文件存放，每个 2GB 大小，编号分别是 0000, 0001...
     *    以分配 system_b-cow 分区的文件为例，将生成以下文件:
     *    1). 列表文件: /data/gsi/ota/system_b-cow-img.img
     *    2). COW 文件: /data/gsi/ota/system_b-cow-img.img.0000
     */
    auto status = SplitFiemap::Create(data_path, size, 0, &fw, on_progress);
    if (!status.is_ok()) {
        return status;
    }

    bool reliable_pinning;
    if (!FilesystemHasReliablePinning(data_path, &reliable_pinning)) {
        return FiemapStatus::Error();
    }
    if (!reliable_pinning && !IsUnreliablePinningAllowed(data_path)) {
        // For historical reasons, we allow unreliable pinning for certain use
        // cases (DSUs, testing) because the ultimate use case is either
        // developer-oriented or ephemeral (the intent is to boot immediately
        // into DSUs). For everything else - such as snapshots/OTAs or adb
        // remount, we have a higher bar, and require the filesystem to support
        // proper pinning.
        LOG(ERROR) << "File system does not have reliable block pinning";
        SplitFiemap::RemoveSplitFiles(data_path);
        return FiemapStatus::Error();
    }

    // Except for testing, we do not allow persisting metadata that references
    // device-mapper devices. It just doesn't make sense, because the device
    // numbering may change on reboot. We allow it for testing since the images
    // are not meant to survive reboot. Outside of tests, this can only happen
    // if device-mapper is stacked in some complex way not supported by
    // FiemapWriter.
    auto device_path = GetDevicePathForFile(fw.get());
    if (android::base::StartsWith(device_path, "/dev/block/dm-") && !IsTestDir(metadata_dir_)) {
        LOG(ERROR) << "Cannot persist images against device-mapper device: " << device_path;

        fw = {};
        SplitFiemap::RemoveSplitFiles(data_path);
        return FiemapStatus::Error();
    }

    bool readonly = !!(flags & CREATE_IMAGE_READONLY);
    if (!UpdateMetadata(metadata_dir_, name, fw.get(), size, readonly)) {
        return FiemapStatus::Error();
    }

    if (flags & CREATE_IMAGE_ZERO_FILL) {
        auto res = ZeroFillNewImage(name, 0);
        if (!res.is_ok()) {
            DeleteBackingImage(name);
            return res;
        }
    }
    return FiemapStatus::Ok();
}
```

CreateBackingImage 中调用创建 cow 文件的操作也比较复杂，这里不再详细分析，后面专门用一篇单独说明 Fiemap 文件的分配原理。

总体来说，这里 cow 文件的创建路径如下：

```
SnapshotManager::CreateCowImage(name)
   --> EnsureImageManager()
   --> ReadSnapshotStatus(name, &status)
   --> ImageManagerBinder::CreateBackingImage(cow_image_name, cow_file_size, flags)
      --> ImageService::createBackingImage(name, size, flags)
         --> ImageManager::CreateBackingImage(name, size, flags)
            --> SplitFiemap::Create(data_path, size, 0)
               --> SplitFiemap::RemoveSplitFiles(file_path)
               --> FiemapWriter::Open(chunk_path, chunk_size)
               --> WriteFully(file_path, line.data(), line.size())
            --> UpdateMetadata(metadata_dir_, name, fw, size, readonly)
            --> ImageManager::ZeroFillNewImage(name, 0)
```

COW 文件创建完成后，将会在以下两个目录中生成文件：

1. 在 ota data 目录下(/data/gsi/ota) 得到：(以 system_b 为例)
   - 分区 cow 的文件列表: /data/gsi/ota/system_b-cow-img.img
   - 分区 cow 的分块数据文件，/data/gsi/ota/system_b-cow-img.img.0000

2. 在 ota metadata 目录下(/metadata/gsi/ota) 得到:
   - 所有 cow 文件的 metadata 描述数据: /metadata/gsi/ota/lp_metadata

系统在更新完成准备 merge 的 first init 阶段，通过读取 /metadata/gsi/ota/lp_metadata 得到所有分区在 /data 下的 cow 文件信息，在加上分区在 super 设备上分配的 COW 空间一起，构成了分区完整的 COW 设备，再这基础上得到更新时的快照设备。

## 4. 总结和思考

### 1. 分区的总体准备流程

虚拟 A/B 分区的重点就是升级过程中对虚拟分区的处理，包括虚拟分区的创建，管理和删除。

升级更新最核心的函数是 `DeltaPerformer::Write()`，在 Write() 函数中通过调用 `ParseManifestPartitions()`完成虚拟分区的创建和加载，整个调用过程如下：

```
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
```

最终的虚拟分区创建工作由 SnapshotManager 类的 `CreateUpdateSnapshots(manifest)` 函数来完成。

`CreateUpdateSnapshots` 函数内部主要分成两部分：

- CreateUpdateSnapshotsInternal，主要用于虚拟分区快照相关 COW 文件的计算和创建
- InitializeUpdateSnapshots，主要基于上一步创建好的 COW 文件，最终映射出虚拟分区



### 2. COW 的分配流程

虚拟 A/B 在创建快照分区时，其 COW 空间对应的 cow 文件，先从 super 设备上的空闲块分配，不够的部分再从 `/data` 文件夹( userdata 分区)分配。

如果 super 设备上的空闲块足够分配 COW 所需空间，比如从 Android 10 动态分区系统升级上来的设备，super 设备上包含了 A/B 两套系统的空间，此时就会直接从 super 上分配空间给 cow，不再另外从 `/data` 目录下分配。



为创建快照设备，分配 COW 的过程如下(CreateUpdateSnapshotsInternal 函数)：

1. 在目标槽位对应的动态分区 metadata 中添加名为 cow 的 group。

2. 遍历 manifest 中的所有分区，提取每个分区的 operations，以及其 hash tree 和 fec 的 extents 用于后面计算各分区需要的 cow 大小。

3. 遍历 metadata 中所有以 target_suffix 结尾的分区(例如所有以 '_b' 结尾的分区)，执行以下操作:
   1. 保存从 manifest 中提取的分区 operations，用于计算 cow
   2. 保存从 manifest 中提取的分区 extra extents，用于计算 cow
   3. 调用 `PartitionCowCreator::Run()` 函数，计算快照的 cow 所需空间，设置 cow_partition_size 和 cow_file_size
      1). 计算 super 设备的空闲块，
      2). 通过分区 operations 和 extra extents 计算 COW 所需空间的大小，
      3). 设置从 super 分配 cow 的大小(`cow_partition_size`)，
      4). 以及从 /data 分配 cow 文件的大小(`cow_file_size`)。
      5). 输出 log: "`Remaining free space for COW: 119177216 bytes`"
   4. 输出 cow 状态信息 log："`For partition system_b, device size = 1263079424, snapshot size = 1263079424, cow partition size = 119177216, cow file size = 1148841984`"
   5. 如果目标分区存在快照设备，则删除目标分区现有的快照设备
   6. 检查当前分区是否需要进行快照
      1). `snapshot_size` 表示分区快照设备的大小， snapshot_size > 0 说明需要对设备做快照
      2). `cow_partition_size` 表示从 super 设备上分批用于 cow 的空间大小
      3). `cow_file_size` 表示从 /data 分区分配用于 cow 文件的大小
      4). 只有当需要从 super 设备或 /data 分区分配 cow 时，才说明需要快照，即 `needs_cow = 1`
   7. 创建当前分区快照状态文件，例如: `/metadata/ota/snapshots/system_b`
   8. 根据 `cow_partition_size`，在 super 设备上创建相应大小的 cow 分区，例如: system_b-cow
   9. 将分区的快照状态数据保存到 `all_snapshot_status` 中

4. 遍历所有分区的快照状态数据，如果状态信息中 `cow_file_size > 0`, 则在目录 /data/gsi/ota/ 下创建相应分区的 cow 文件。例如: `system_b-cow-img.img`



### 3. Super 设备上的 COW

如果 super 设备上还有空闲空间，则 `cow_partition_size` 表示 super 分区上分配用于 COW 的空间大小；

先在 super 设备的 metadata 中名为 "cow" 的 group 上创建名为 `system_b-cow` 的分区；

然后根据 `cow_partition_size` 调整 super 设备上 `system_b-cow` 分区大小(主要是对齐调整)



### 4. /data 目录中的 COW

`cow_file_size` 表示从 /data 目录中分配的 COW 空间的大小。

/data 目录下的 COW 文件创建完成后，将会在以下两个目录中生成文件 COW 相关文件：

1. 在 ota data 目录下(/data/gsi/ota) 得到：(以 system_b 为例)
   - 分区 cow 的文件列表: /data/gsi/ota/system_b-cow-img.img
   - 分区 cow 的分块数据文件，/data/gsi/ota/system_b-cow-img.img.0000

2. 在 ota metadata 目录下(/metadata/gsi/ota) 得到:
   - 所有 cow 文件的 metadata 描述数据: /metadata/gsi/ota/lp_metadata

系统在更新完成准备 merge 的 first init 阶段，通过读取 /metadata/gsi/ota/lp_metadata 得到所有分区在 /data 下的 cow 文件信息，在加上分区在 super 设备上分配的 COW 空间一起，构成了分区完整的 COW 设备，再这基础上得到更新时的快照设备。



> 思考题：
>
> 1. 为什么通过统计 manifest 中分区的 InstallOperations 以及 hash tree 和 fec 等数据就能得到 COW 的大小？
> 2. super 设备上的空闲空间到底是如何计算出来的？
> 3. 分区完整的 COW 设备到底是如何构成的？
> 4. 在分配 COW 的过程中，一共修改或创建了哪些文件？



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


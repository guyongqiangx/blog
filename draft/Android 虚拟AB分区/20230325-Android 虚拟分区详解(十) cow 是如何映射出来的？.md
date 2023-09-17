# 20230325-Android 虚拟分区详解(十) cow 是如何映射出来的？.md

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
> - [Android 虚拟 A/B 详解(九) cow 的存储是如何分配的？](https://blog.csdn.net/guyongqiangx/article/details/129494397)
>
> 对 linux 快照(snapshot) 的了解可以增加对虚拟 A/B 分区的理解：
>
> - [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
> - [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

## 0. 导读

### 1. 虚拟分区的总体准备流程

在开始正文之前，先回顾下虚拟分区的总体准备流程：

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



`SnapshotManager::CreateUpdateSnapshots(manifest)` 函数的作用如下：

创建 OTA 升级中必要的 COW device 和 image，新的逻辑分区将被添加到目标槽位对应 metadata 数据的 "cow" 组中。当前运行槽位的在 super 中的分区，将会进行快照，并被写保护起来以防止破坏。



`CreateUpdateSnapshots` 函数除了为创建虚拟分区操作进行一些准备工作外，创建虚拟分区主要分成两部分：

- CreateUpdateSnapshotsInternal，主要用于虚拟分区快照相关 COW 文件的计算和创建
- InitializeUpdateSnapshots，主要基于上一步创建好的 COW 文件，最终映射出虚拟分区



### 2. COW 逻辑分区和文件分配流程

上一篇[《Android 虚拟 A/B 详解(九) cow 的存储是如何分配的？》](https://blog.csdn.net/guyongqiangx/article/details/129494397)重点基于 CreateUpdateSnapshotsInternal 函数分析快照 (snapshot) 设备的 COW 是如何分配和存储的。

这里以升级 B 槽位的  "system_b" 分区为例把这个分配过程复述一遍：

1. 往 B 槽位对应 metadata 中添加名为 "cow" 的 group
2. 遍历 manifest 中的 "system_b" 分区的所有操作，计算创建快照 cow 所需空间
3. 根据 super 设备的空闲块，计算 cow partition 和 cow image 的大小
   - cow partition 表示基于 super 空闲块创建的逻辑分区，对应大小为 "cow_partition_size"
   - cow image 表示从 /data 目录下分配文件用于创建快照文件，对应大小为 "cow_image_size"
4. 如果 B 槽位的 "system_b" 分区存在快照设备，则删除已有的快照设备
5. 创建 "system_b" 分区快照状态文件，例如: "/metadata/ota/snapshots/system_b"
6. 根据 "cow_partition_size"，在 super 设备上创建 "system_b" 对应的 cow 逻辑分区，例如: "system_b-cow"
7. 将 "system_b" 分区的快照状态保存到快照状态文件("/metadata/ota/snapshots/system_b")中
8. 如果 "cow_file_size > 0"，则在目录 /data/gsi/ota/ 下创建 cow 文件。例如: "/data/gsi/ota/system_b-cow-img.img"
9. 分配好 "system_b" 升级所需的 cow 分区和文件以后，会生成以下文件:
   - "system_b" 分区快照状态文件: "/metadata/ota/snapshots/system_b"
   - "system_b" 分区的 cow 文件列表: "/data/gsi/ota/system_b-cow-img.img"
   - "system_b" 分区的 cow 数据文件(从 0000 开始的多个文件): "/data/gsi/ota/system_b-cow-img.img.0000"
   - 描述所有分区 cow 文件的 metadata 数据: "/metadata/gsi/ota/lp_metadata"

> 对于 lp_metadata 文件，系统在更新重启准备 merge 的 first init 阶段，通过读取 /metadata/gsi/ota/lp_metadata 得到所有分区在 /data 下的 cow 文件信息，在加上分区在 super 设备上分配的 cow 空间一起，得到该分区完整的 cow 空间。



在上一篇介绍如何分配出快照设备所需要的空间和文件后，本篇将基于 InitializeUpdateSnapshots 函数介绍系统如何使用分配好的 cow 逻辑分区和文件映射出升级所需要的完整的快照设备。

因此，本篇的重点是分析 "InitializeUpdateSnapshots()" 以及随后的 "UpdatePartitionTable()" 函数。



> 相关文章阅读：
>
> - [《Android 虚拟 A/B 详解(八) cow 的大小是如何计算的？》](https://blog.csdn.net/guyongqiangx/article/details/129470881)
>   - 分析快照 (snapshot) 设备的 COW 大小是如何计算的
>
> - [《Android 虚拟 A/B 详解(九) cow 的存储是如何分配的？》](https://blog.csdn.net/guyongqiangx/article/details/129494397)
>   - 分析快照 (snapshot) 设备的 COW 是如何分配和存储的



> 本文基于 Android 11.0.0_r21 版本的代码进行分析。
>
> 在线地址：http://aospxref.com/android-11.0.0_r21/

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。



## 1. InitializeUpdateSnapshots 函数详细注释

总体来说， `InitializeUpdateSnapshots()` 函数的作用是做一些快照初始化的工作，为后面的映射做准备。初始化的工作包括映射 COW 分区，以及用 0 初始化头部数据。

```c++
/* file: system/core/fs_mgr/libsnapshot/snapshot.cpp */
Return SnapshotManager::InitializeUpdateSnapshots(
        LockedFile* lock, MetadataBuilder* target_metadata,
        const LpMetadata* exported_target_metadata, const std::string& target_suffix,
        const std::map<std::string, SnapshotStatus>& all_snapshot_status) {
    CHECK(lock);

    /*
     * 1. 准备生成逻辑分区的 cow_params
     */
    CreateLogicalPartitionParams cow_params{
            .block_device = LP_METADATA_DEFAULT_PARTITION_NAME,
            .metadata = exported_target_metadata,
            .timeout_ms = std::chrono::milliseconds::max(),
            .partition_opener = &device_->GetPartitionOpener(),
    };
    /*
     * 2. 遍历 metadata 中所有后缀为 target_suffix 的分区
     *    例如当前在 A 槽位运行，则遍历 metadata 中所有后缀为 _b 的分区, system_b, vendor_b 等
     */
    for (auto* target_partition : ListPartitionsWithSuffix(target_metadata, target_suffix)) {
        AutoDeviceList created_devices_for_cow;

        /*
         * 2.1 卸载所有 system_b 相关的 snapshot 和 cow 设备
         */
        if (!UnmapPartitionWithSnapshot(lock, target_partition->name())) {
            LOG(ERROR) << "Cannot unmap existing COW devices before re-mapping them for zero-fill: "
                       << target_partition->name();
            return Return::Error();
        }

        /*
         * 2.2 根据分区名查找对应的快照状态文件
         *     例如，查找 system_b 分区快照状态文件 /metadata/gsi/ota/system_b
         */
        auto it = all_snapshot_status.find(target_partition->name());
        if (it == all_snapshot_status.end()) continue;
        cow_params.partition_name = target_partition->name();
        std::string cow_name;
      
        /*
         * 2.3 根据 cow_params 参数映射分区的 cow 设备
         */
        if (!MapCowDevices(lock, cow_params, it->second, &created_devices_for_cow, &cow_name)) {
            return Return::Error();
        }

        std::string cow_path;
        if (!images_->GetMappedImageDevice(cow_name, &cow_path)) {
            LOG(ERROR) << "Cannot determine path for " << cow_name;
            return Return::Error();
        }

        auto ret = InitializeCow(cow_path);
        if (!ret.is_ok()) {
            LOG(ERROR) << "Can't zero-fill COW device for " << target_partition->name() << ": "
                       << cow_path;
            return AddRequiredSpace(ret, all_snapshot_status);
        }
        // Let destructor of created_devices_for_cow to unmap the COW devices.
    };
    return Return::Ok();
}
```



`MapCowDevices()` 函数的作用映射 COW 设备，包括用 super 上分配的 cow_partition 空间和 /data 分区下分配的 cow_file 的 image 镜像文件用来映射成累死名称为 `/dev/block/dm-1` 这样的设备。

```c++
/* file: system/core/fs_mgr/libsnapshot/snapshot.cpp */
bool SnapshotManager::MapCowDevices(LockedFile* lock, const CreateLogicalPartitionParams& params,
                                    const SnapshotStatus& snapshot_status,
                                    AutoDeviceList* created_devices, std::string* cow_name) {
    CHECK(lock);
    CHECK(snapshot_status.cow_partition_size() + snapshot_status.cow_file_size() > 0);
    auto begin = std::chrono::steady_clock::now();

    /* partition_name = "system_b" */
    std::string partition_name = params.GetPartitionName();
    /* cow_image_name = "system_b-cow-img" */
    std::string cow_image_name = GetCowImageDeviceName(partition_name);
    /* cow_name = "system_b-cow" */
    *cow_name = GetCowName(partition_name);

    auto& dm = DeviceMapper::Instance();

    // Map COW image if necessary.
    /* 如果 /data 下存在 cow 的镜像文件，先进行映射 */
    if (snapshot_status.cow_file_size() > 0) {
        /* EnsureImageManager() 函数的作用:
         * 使用 gsid_dir_=“ota” 初始化得到变量:
         *     metadata_dir: /metadata/gsi/ota
         *         data_dir: /data/gsi/ota
         * install_dir_file: /metadata/gsi/dsu/ota/install_dir
         * 并用 metadata_dir 和 data_dir 初始化 ImageManager 并返回该对象
         */
        if (!EnsureImageManager()) return false;
        auto remaining_time = GetRemainingTime(params.timeout_ms, begin);
        if (remaining_time.count() < 0) return false;

        /* MapCowImage 用于映射此前用 CreateCowImage 创建的 image 文件:
         * 索引: /data/gsi/ota/system_b-cow-img.img
         * 数据: /data/gsi/ota/system_b-cow-img.img.0000
         *      /data/gsi/ota/system_b-cow-img.img.0001
         */
        if (!MapCowImage(partition_name, remaining_time).has_value()) {
            LOG(ERROR) << "Could not map cow image for partition: " << partition_name;
            return false;
        }
        created_devices->EmplaceBack<AutoUnmapImage>(images_.get(), cow_image_name);

        // If no COW partition exists, just return the image alone.
        if (snapshot_status.cow_partition_size() == 0) {
            *cow_name = std::move(cow_image_name);
            LOG(INFO) << "Mapped COW image for " << partition_name << " at " << *cow_name;
            return true;
        }
    }

    auto remaining_time = GetRemainingTime(params.timeout_ms, begin);
    if (remaining_time.count() < 0) return false;

    CHECK(snapshot_status.cow_partition_size() > 0);

    /*
     * 基于 super 上的 cow_partition 创建名为 "system_b-cow" 的 COW 设备 DmTable
     *
     */
    // Create the DmTable for the COW device. It is the DmTable of the COW partition plus
    // COW image device as the last extent.
    CreateLogicalPartitionParams cow_partition_params = params;
    cow_partition_params.partition = nullptr;
    cow_partition_params.partition_name = *cow_name;
    cow_partition_params.device_name.clear();
    DmTable table;
    if (!CreateDmTable(cow_partition_params, &table)) {
        return false;
    }
  
    /*
     * 如果还有 COW image，则添加到末尾
     */
    // If the COW image exists, append it as the last extent.
    if (snapshot_status.cow_file_size() > 0) {
        std::string cow_image_device;
        /* 获取 system_b-cow-img 映射出来的设备路径 */
        if (!GetMappedImageDeviceStringOrPath(cow_image_name, &cow_image_device)) {
            LOG(ERROR) << "Cannot determine major/minor for: " << cow_image_name;
            return false;
        }
        /* 计算 cow_partition 的 sector 数量 */
        auto cow_partition_sectors = snapshot_status.cow_partition_size() / kSectorSize;
        /* 计算 cow_image 的 sector 数量 */
        auto cow_image_sectors = snapshot_status.cow_file_size() / kSectorSize;
        /* 使用 cow_partition 和 cow_image 的信息构建得到最终完整的分区表 */
        table.Emplace<DmTargetLinear>(cow_partition_sectors, cow_image_sectors, cow_image_device,
                                      0);
    }

    /*
     * 基于完整的分区表，映射得到快照设备 "system_b-cow"
     */
    // We have created the DmTable now. Map it.
    std::string cow_path;
    if (!dm.CreateDevice(*cow_name, table, &cow_path, remaining_time)) {
        LOG(ERROR) << "Could not create COW device: " << *cow_name;
        return false;
    }
    created_devices->EmplaceBack<AutoUnmapDevice>(&dm, *cow_name);
    LOG(INFO) << "Mapped COW device for " << params.GetPartitionName() << " at " << cow_path;
    return true;
}
```

所以这里执行 map 的时候，可能得到类似下面这样的 log 信息:

```bash
console:/ # snapshotctl map
Successfully unmapped snapshot system_b
[libfs_mgr]Created logical partition system_b-base on device /dev/block/dm-4
Mapped system_b-cow-img to /dev/block/dm-5
Mapped COW device for system_b at /dev/block/dm-6
Mapped system_b as snapshot device at /dev/block/dm-7
Successfully unmapped snapshot vendor_b
[libfs_mgr]Created logical partition vendor_b-base on device /dev/block/dm-8
Mapped vendor_b-cow-img to /dev/block/dm-9
Mapped COW image for vendor_b at vendor_b-cow-img
Mapped vendor_b as snapshot device at /dev/block/dm-10
MapAllSnapshots succeeded.
```



```c++
/* file: system/core/fs_mgr/libsnapshot/snapshot.cpp */
std::optional<std::string> SnapshotManager::MapCowImage(
        const std::string& name, const std::chrono::milliseconds& timeout_ms) {
    if (!EnsureImageManager()) return std::nullopt;
    /* 传入 name = "system_b", 则 cow_image_name = "system_b-cow-img" */
    auto cow_image_name = GetCowImageDeviceName(name);

    bool ok;
    std::string cow_dev;
    if (has_local_image_manager_) {
        // If we forced a local image manager, it means we don't have binder,
        // which means first-stage init. We must use device-mapper.
        const auto& opener = device_->GetPartitionOpener();
        /* 在 first-stage init 阶段，使用 device mapper 进行映射:
         * 内部调用 MapWithDmLinear(), 使用 image 文件以及存储在 lp_metadata 中的 extents 信息进行映射
         */
        ok = images_->MapImageWithDeviceMapper(opener, cow_image_name, &cow_dev);
    } else {
        /* 升级过程中创建 Cow 使用  */
        ok = images_->MapImageDevice(cow_image_name, timeout_ms, &cow_dev);
    }

    if (ok) {
        LOG(INFO) << "Mapped " << cow_image_name << " to " << cow_dev;
        return cow_dev;
    }
    LOG(ERROR) << "Could not map image device: " << cow_image_name;
    return std::nullopt;
}
```

对于 `MapImageDevice()` 函数:

```c++
/* file: system/core/fs_mgr/libfiemap/image_manager.cpp */
bool ImageManager::MapImageDevice(const std::string& name,
                                  const std::chrono::milliseconds& timeout_ms, std::string* path) {
    if (IsImageMapped(name)) {
        LOG(ERROR) << "Backing image " << name << " is already mapped";
        return false;
    }

    /* 如果是映射 system_b-cow-img 分区，则设置 image header 的路径为:
     * image_header = "/data/gsi/ota/system_b-cow-img.img"
     * image_header 里面包含了什么呢？就是所有 cow-img 的文件列表，例如:
     *   system_b-cow-img.img.0000
     *   system_b-cow-img.img.0001
     */
    auto image_header = GetImageHeaderPath(name);

#if !defined __ANDROID_RECOVERY__
    // If there is a device-mapper node wrapping the block device, then we're
    // able to create another node around it; the dm layer does not carry the
    // exclusion lock down the stack when a mount occurs.
    //
    // If there is no intermediate device-mapper node, then partitions cannot be
    // opened writable due to sepolicy and exclusivity of having a mounted
    // filesystem. This should only happen on devices with no encryption, or
    // devices with FBE and no metadata encryption. For these cases it suffices
    // to perform normal file writes to /data/gsi (which is unencrypted).
    std::string block_device;
    bool can_use_devicemapper;
    /* 调用函数 GetBlockDeviceForFile() 检查是否可以使用 device mapper 进行映射 */
    if (!FiemapWriter::GetBlockDeviceForFile(image_header, &block_device, &can_use_devicemapper)) {
        LOG(ERROR) << "Could not determine block device for " << image_header;
        return false;
    }

    /* 如果可以使用 device mapper 直接映射，则调用函数 MapWithDmLinear()  */
    if (can_use_devicemapper) {
        if (!MapWithDmLinear(*partition_opener_.get(), name, timeout_ms, path)) {
            return false;
        }
    } else if (!MapWithLoopDevice(name, timeout_ms, path)) {
    /* 不能使用 device mapper 时，使用 loop device 的方式，逐个获取列表文件的信息 */
        return false;
    }
#else
    /* recovery 模式下，只能通过 device-mapper 的方式进行映射，因为此时 /data 分区没有挂载 */
    // In recovery, we can *only* use device-mapper, since partitions aren't
    // mounted. That also means we cannot call GetBlockDeviceForFile.
    if (!MapWithDmLinear(*partition_opener_.get(), name, timeout_ms, path)) {
        return false;
    }
#endif

    // Set a property so we remember this is mapped.
    auto prop_name = GetStatusPropertyName(name);
    if (!android::base::SetProperty(prop_name, *path)) {
        UnmapImageDevice(name, true);
        return false;
    }
    return true;
}
```



你肯定很好奇这个 image header 文件的内容到底是什么:

```bash
console:/data/gsi/ota # xxd -g 1 system_b-cow-img.img      
00000000: 73 79 73 74 65 6d 5f 62 2d 63 6f 77 2d 69 6d 67  system_b-cow-img
00000010: 2e 69 6d 67 2e 30 30 30 30 0a                    .img.0000.
```

其实就是所有文件列表。



完成 COW 设备创建以后，调用函数 `InitializeCow()`:

```c++
Return InitializeCow(const std::string& device) {
    // When the kernel creates a persistent dm-snapshot, it requires a CoW file
    // to store the modifications. The kernel interface does not specify how
    // the CoW is used, and there is no standard associated.
    // By looking at the current implementation, the CoW file is treated as:
    // - a _NEW_ snapshot if its first 32 bits are zero, so the newly created
    // dm-snapshot device will look like a perfect copy of the origin device;
    // - an _EXISTING_ snapshot if the first 32 bits are equal to a
    // kernel-specified magic number and the CoW file metadata is set as valid,
    // so it can be used to resume the last state of a snapshot device;
    // - an _INVALID_ snapshot otherwise.
    // To avoid zero-filling the whole CoW file when a new dm-snapshot is
    // created, here we zero-fill only the first chunk to be compliant with
    // lvm.
    constexpr ssize_t kDmSnapZeroFillSize = kSectorSize * kSnapshotChunkSize;

    std::vector<uint8_t> zeros(kDmSnapZeroFillSize, 0);
    android::base::unique_fd fd(open(device.c_str(), O_WRONLY | O_BINARY));
    if (fd < 0) {
        PLOG(ERROR) << "Can't open COW device: " << device;
        return Return(FiemapStatus::FromErrno(errno));
    }

    LOG(INFO) << "Zero-filling COW device: " << device;
    if (!android::base::WriteFully(fd, zeros.data(), kDmSnapZeroFillSize)) {
        PLOG(ERROR) << "Can't zero-fill COW device for " << device;
        return Return(FiemapStatus::FromErrno(errno));
    }
    return Return::Ok();
}

```


# 20230302-Android 虚拟 A/B 详解(八) cow 的大小是如何计算的？

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 原文链接：https://guyongqiangx.blog.csdn.net/article/details/129470881



> Android 虚拟 A/B 分区[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列，更新中，文章列表：
>
> - [Android 虚拟 A/B 详解(一) 参考资料推荐](https://blog.csdn.net/guyongqiangx/article/details/128071692)
> - [Android 虚拟 A/B 详解(二) 虚拟分区布局](https://blog.csdn.net/guyongqiangx/article/details/128167054)
> - [Android 虚拟 A/B 详解(三) 分区状态变化](https://blog.csdn.net/guyongqiangx/article/details/128517578)
> - [Android 虚拟 A/B 详解(四) 编译开关](https://blog.csdn.net/guyongqiangx/article/details/128567582)
> - [Android 虚拟 A/B 详解(五) BootControl 接口的变化](https://blog.csdn.net/guyongqiangx/article/details/128824984)
> - [Android 虚拟 A/B 详解(六) 升级中的状态数据保存在哪里？](https://blog.csdn.net/guyongqiangx/article/details/129094203)
> - [Android 虚拟 A/B 详解(七) 升级中用到了哪些标识文件？](https://guyongqiangx.blog.csdn.net/article/details/129098176)
> - [Android 虚拟 A/B 详解(八) cow 的大小是如何计算的？](https://guyongqiangx.blog.csdn.net/article/details/129470881)
>
> 对 linux 快照(snapshot) 的了解可以增加对虚拟 A/B 分区的理解：
>
> - [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
> - [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。



## 0. 导读

在虚拟 A/B 升级的过程中，假设当前运行在 A 槽位，即将升级 B 槽位的分区，因此系统需要为 B 槽位的分区(比如 system_b) 创建相应的 snapshot (快照) 设备，而创建快照时需要提供快照的 cow 文件。

创建 cow 设备时，cow 所需空间会先从 super 分区的空闲空间分配，然后剩余的部分从 userdata 分区分配，并以文件的形式保存在 userdata 分区的目录下：。

这里先不讨论 cow 到底从哪里分配，而是讨论 cow 的大小到底是如何确定的？



是提前随便分配一个指定大小的 cow 文件吗？比方说提前分配一个 1GB 的 cow 文件？

如果不是，那 cow 文件的大小是如何确定的呢？



本文尽量最初想尽量写得清楚简单，但一不小心又有点啰嗦了，所以：

如果想了解 COW 文件的布局，请转到第 1 节；

如果想知道代码中 COW 的大小是如何计算的，请转到第 2 节；

如果只想从大方向的原则上了解 COW 的大小是如何计算的，请转到第 3 节，看看总结描述。



> 本文基于 Android 11.0.0_r21 版本的代码进行分析。
>
> 在线地址：http://aospxref.com/android-11.0.0_r21/



## 1.  COW 的背景知识

关于 linux 下快照，强烈推荐我的两篇文章，如果不清楚快照原理，不妨先看下：

- [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)
- [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)



对于 Android 虚拟 A/B 来说，升级开始时，对于每一个需要更新的分区(例如 system)，首先从 super 分区的空闲区块中分配空间给 cow，不够的情况下，再从 userdata 内以文件的形式补足 cow 需要的空间，并将这两处分配的 cow 空间拼接在一起形成，形成一个完整的 cow 空间。



### 1. COW 设备的布局

根据我 linux 快照中介绍的基本内容，一个快照卷设备大致的结构如下所示：

![image-20221230105656510](images-20230302-Android 虚拟分区详解(八)/cow-device-diagram.png)

**图 1.  COW 设备的结构**



在一个快照卷 COW 设备中：

1. 一开始的头部是 1 个 chunk 的 disk header；

2. 接下来就是查找表(mapping talbe)

   如果查找表很小，则占用 1 个 chunk；如果很大，可能会占用多个 chunk；

3. 然后就是查找表对应的被修改的数据块区域，以 chunk 为单位，每 1 个 chunk 对应于查找表中的 1 条记录；

4. 在数据块区域结束后是空闲块；



COW 的 disk header 和查找表到底长什么样呢？

以下是 linux 中定义的代码:

```c
struct disk_header {
	__le32 magic;

	/*
	 * Is this snapshot valid.  There is no way of recovering
	 * an invalid snapshot.
	 */
	__le32 valid;

	/*
	 * Simple, incrementing version. no backward
	 * compatibility.
	 */
	__le32 version;

	/* In sectors */
	__le32 chunk_size;
} __packed;

struct disk_exception {
	__le64 old_chunk;
	__le64 new_chunk;
} __packed;
```

> 在线代码: https://elixir.bootlin.com/linux/v4.19.275/source/drivers/md/dm-snap-persistent.c

其中，`disk_exception` 结构就是一条查找表的记录格式，在一个查找表中，每 16 bytes 为 1 条记录，前 8 byte 记录的是在原始设备中的 chunk 序号，后 8 bytes 记录的时候该修改的 chunk 在 COW 设备中的 chunk 序号。

例如，[《Linux 快照 (snapshot) 原理与实践(二) 快照功能实践》](https://blog.csdn.net/guyongqiangx/article/details/128496471) 的 5.2 节，有提供一个 cow 文件的内容输出，如下：

![cow-device-example](images-20230302-Android 虚拟分区详解(八)/cow-device-example.png)

**图 2. 一个 COW 设备的内容示例**

这里：

- chunk 0 为 disk header
- chunk 1 是一个查找表，每一行的 16 字节为一个查找表项，前 8 字节表示被修改数据在原设备的 chunk id，后 8 字节表示被修改数在 COW 中的 chunk id
  - 第 6 行表示原设备的第 0 个 chunk 被修改了，新数据位于 COW 文件的第 2 个 chunk
  - 第 7 行表示原设备的第 1 个 chunk 被修改了，新数据位于 COW 文件的第 3 个 chunk
- chunk2 和 chunk3 分别是原设备中两个被修改的 chunk 在 COW 文件中的内容

上图中，用 hexdump 输出时，有好几处用星号"`*`"表示的内容，这这里星号"`*`"表示此处省略的数据和紧接着的前一行的内容一样。



### 2. Android COW 设备的分布

对于 Androie 的 COW 设备，是根据所需要的实际 cow 大小分配的，所以 Android 的 cow 中不存在空闲块。

查看代码注释，在 Android 中这个 COW device 的结构是这样表述的：

```c++
/* file: system/core/fs_mgr/libsnapshot/dm_snapshot_internals.h */
    /*
     * The COW device has a precise internal structure as follows:
     *
     * - header (1 chunk)
     * - #0 map and chunks
     *   - map (1 chunk)
     *   - chunks addressable by previous map (exceptions_per_chunk)
     * - #1 map and chunks
     *   - map (1 chunk)
     *   - chunks addressable by previous map (exceptions_per_chunk)
     * ...
     * - #n: map and chunks
     *   - map (1 chunk)
     *   - chunks addressable by previous map (exceptions_per_chunk)
     * - 1 extra chunk
     */
    uint64_t cow_size_chunks() const {
        uint64_t modified_chunks_count = 0;
        uint64_t cow_chunks = 0;

        for (const auto& c : modified_chunks_) {
            if (c) {
                ++modified_chunks_count;
            }
        }

        /* disk header + padding = 1 chunk */
        cow_chunks += 1;

        /* snapshot modified chunks */
        cow_chunks += modified_chunks_count;

        /* snapshot chunks index metadata */
        cow_chunks += 1 + modified_chunks_count / exceptions_per_chunk;

        return cow_chunks;
    }
```

从上面这段注释来说，这里的 COW 内部结构是先 COW Header，然后第 1 个索引表(map)和相应修改的 chunk 数据，接着是第 2 个索引表(map)和相应修改的 chunk 数据，这样一直到所有修改的索引表及其数据。最后是 1 个额外的 chunk。

> 这里提到的布局和前面我说的 linux COW device 布局不一致，很有可能是我之前对 linux COW 设备的布局理解错了，请先以这里 Android 注释说的布局为准，待我后面核实后再给统一的结论。



## 2. OTA 时如何计算所需 COW 空间的大小？

### 1. GetCowSize 函数

在 `partition_cow_creator.cpp` 文件中，专门有一个函数 `GetCowSize()` 用来获取当前更新分区所需 cow 的大小。这里直接上代码和注释：

```c++
/* file: system/core/fs_mgr/libsnapshot/partition_cow_creator.cpp */
uint64_t PartitionCowCreator::GetCowSize() {
    /*
     * 1. 根据各种基本单位，并用来初始化 DmSnapCownSizeCalculator
     *    包括: 
     *        logic block size(逻辑块大小)
     *        sector size(扇区大小)
     *        snapshot chunk size(每个 snapshot chunk 的 sector 数量)
     */
    // WARNING: The origin partition should be READ-ONLY
    const uint64_t logical_block_size = current_metadata->logical_block_size();
    const unsigned int sectors_per_block = logical_block_size / kSectorSize;
    DmSnapCowSizeCalculator sc(kSectorSize, kSnapshotChunkSize);

    /*
     * 2. 将 extra_extents 中的 block 所在 chunk 的状态 modified_chunks_[chunk_id] 设置为 true，表示该 chunk 会被改动，对应于在 cow 文件占用一个 chunk 的空间；
     *   Extent 是按照 block 计算的，转换为 sector 需要使用 sectors_per_block
     */
    // Allocate space for extra extents (if any). These extents are those that can be
    // used for error corrections or to store verity hash trees.
    for (const auto& de : extra_extents) {
        WriteExtent(&sc, de, sectors_per_block);
    }

    /*
     * 3. 如果 operation 集合为空，则根据已有 modified_chunks_ 内被修改的 chunk 数返回当前 cow 的 size
     */
    if (operations == nullptr) return sc.cow_size_bytes();

    /*
     * 4. 遍历所有的 InstallOperation, 通过其 Extent 数据统计需要被修改的 chunk 数
     */
    for (const auto& iop : *operations) {
        const InstallOperation* written_op = &iop;
        InstallOperation buf;
        /*
         * 这里对 SOURCE_COPY 的操作有个特别的优化，用来减小 cow 文件的大小，这里暂时忽略这个优化的内容。
         */
        // Do not allocate space for extents that are going to be skipped
        // during OTA application.
        if (iop.type() == InstallOperation::SOURCE_COPY && OptimizeSourceCopyOperation(iop, &buf)) {
            written_op = &buf;
        }

        for (const auto& de : written_op->dst_extents()) {
            WriteExtent(&sc, de, sectors_per_block);
        }
    }

    /*
     * 5. 根据 modified_chunks_ 内被修改的 chunk 数返回 cow size
     */
    return sc.cow_size_bytes();
}
```

上面的 GetCowSize() 函数，主要做了以下事情：

1. 根据各种基本单位，并用来初始化 DmSnapCownSizeCalculator
2. 将 extra_extents 中的 block 所在 chunk 的状态 modified_chunks_[chunk_id] 设置为 true，表示该 chunk 会被改动，对应于在 cow 文件占用一个 chunk 的空间；
3. 如果 operation 集合为空，则根据已有 modified_chunks_ 内被修改的 chunk 数返回当前 cow 的 size
4. 遍历所有的 InstallOperation, 通过其 Extent 数据统计需要被修改的 chunk 数
5. 根据 modified_chunks_ 内被修改的 chunk 数返回 cow size



### 2. PartitionCowCreator 辅助类

总体来说，PartitionCowCreator 是一个辅助类，用于辅助创建一个分区设备的 COW 空间。

在 PartitionCowCreator 内部，有一个名为 `modified_chunks_` 的向量成员(数组)，以 bool 值的形式保存了一个目标分区设备上所有 chunk 的状态，可以根据 chunk id 查询该 chunk 的状态。

如果某个 chunk id 对应的 `modified_chunks_[chunk id]` 为 true, 则表示该 chunk 在升级时会被修改。

所以，当遍历完一个待更新分区的所有 InstallOperation 后，就知道所有需要修改的 block，而 snapshot 是以 chunk 为基本统计，所以也就知道哪些 chunk 会被修改。

再加上其他需要更新的内容(extra_extents)，包括 Hash Tree 和 FEC 数据等占用的空间。

以及 cow 文件本身的元数据。

因此，这时更新一个分区所需要的 cow 大小就完全可以确定下来。



函数 `cow_size_bytes()` 内部会调用 `cow_size_chunks()`统计 COW 所需要的 3 类消耗(包括 disk header chunk, disk exception chunk, data chunk) 的 chunk 数，并以 bytes 的单位返回 COW 所占用的大小。



### 3. 关于 extra extents

在 GetCowSize() 函数中有提到 extra extents，这些 extra extents 到底包含哪些内容呢？

在 CreateUpdateSnapshotsInternal() 函数中，会遍历所有待更新分区，获取每个分区 hash tree 和 fec 数据对应的 extents，并存放到 `extra_extents_map` 中，传递给辅助类的成员 `cow_creator->extra_extents`。

通过这个操作，辅助类 `cow_creator` 就拥有了每个分区的 extra extents 信息。



```c++
Return SnapshotManager::CreateUpdateSnapshotsInternal(
        LockedFile* lock, const DeltaArchiveManifest& manifest, PartitionCowCreator* cow_creator,
        AutoDeviceList* created_devices,
        std::map<std::string, SnapshotStatus>* all_snapshot_status) {
    
    //...

    std::map<std::string, const RepeatedPtrField<InstallOperation>*> install_operation_map;
    std::map<std::string, std::vector<Extent>> extra_extents_map;
    /*
     * 遍历 manifest 中每一个待更新的分区
     */
    for (const auto& partition_update : manifest.partitions()) {
        /*
         * 获取每个分区的名字，并提取分区的所有 operations
         */
        auto suffixed_name = partition_update.partition_name() + target_suffix;
        auto&& [it, inserted] =
                install_operation_map.emplace(suffixed_name, &partition_update.operations());
        if (!inserted) {
            LOG(ERROR) << "Duplicated partition " << partition_update.partition_name()
                       << " in update manifest.";
            return Return::Error();
        }

        /*
         * 获取分区的 hash tree 和 fec 对一个的 extent，并存放到 extra extent 中
         */
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
        /*
         * 将每个分区对应的 operations 传递给辅助类成员 cow_creator->operations 
         */
        auto operations_it = install_operation_map.find(target_partition->name());
        if (operations_it != install_operation_map.end()) {
            cow_creator->operations = operations_it->second;
        }

        /*
         * 将每个分区对应的 extra extents map 传递给辅助类成员 cow_creator->extra_extents
         */
        cow_creator->extra_extents.clear();
        auto extra_extents_it = extra_extents_map.find(target_partition->name());
        if (extra_extents_it != extra_extents_map.end()) {
            cow_creator->extra_extents = std::move(extra_extents_it->second);
        }

        /*
         * 辅助类调用 Run() 函数计算空间需求
         */
        // Compute the device sizes for the partition.
        auto cow_creator_ret = cow_creator->Run();
        if (!cow_creator_ret.has_value()) {
            return Return::Error();
        }

        // ...

    return Return::Ok();
}
```



所以，现在你知道每一个待更新分区的 COW 是如何计算的了吗？



## 3. 总结

manifest 中包含了每个分区更新需要的所有 InstallOperation 操作。

对每个 InstallOperation 操作，其成员 dst_extents 附带了目标分区的 Extent 区段信息，包括修改的起始 block 位置和数量。

通过统计目标分区修改的 block 起始位置和数量，并将其转换为快照 COW 的 chunk 信息，就可以得到 COW 空间需要存放多少要修改的 chunk 数据。



再加上每个 COW 空间需要的元数据，包括 disk header 和索引表(disk exception table，本文前面也有称为映射表)，就能准确的计算每个分区升级需要的 COW 设备的大小了。



知道了所需 COW 的大小，下一步就是如何准备 cow 文件的问题。

总体上，是先从 super 设备的空闲空间分配，不够再从 userdata 分区以文件的形式分配，再将这两个 cow 空间通过 device mapper 的方式拼接起来形成一个整体的 cow 空间。



下一篇将详细分析 COW 设备的 cow 文件到底是如何分配的？



## 4. 其它

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



---

你现在能够解释下面这段 log 了吗？



```
I update_engine: [liblp]Partition system_b will resize from 1263054848 bytes to 1263079424 bytes
I update_engine:  dap_metadata.cow_version(): 0 writer.GetCowVersion(): 2
I update_engine: Remaining free space for COW: 119177216 bytes
I update_engine: For partition system_b, device size = 1263079424, snapshot size = 1263079424, cow partition size = 119177216, cow file size = 1148841984
I update_engine: [liblp]Partition system_b-cow will resize from 0 bytes to 119177216 bytes
I update_engine: Successfully created snapshot partition for system_b
I update_engine: Remaining free space for COW: 0 bytes
I update_engine: For partition vendor_b, device size = 80506880, snapshot size = 80506880, cow partition size = 0, cow file size = 80826368
I update_engine: Successfully created snapshot partition for vendor_b
I update_engine: Allocating CoW images.
I update_engine: Successfully created snapshot for system_b
I update_engine: Successfully created snapshot for vendor_b
I update_engine: Successfully unmapped snapshot system_b
I update_engine: Mapped system_b-cow-img to /dev/block/dm-5
I update_engine: Mapped COW device for system_b at /dev/block/dm-6
I update_engine: Zero-filling COW device: /dev/block/dm-6
I update_engine: Successfully unmapped snapshot vendor_b
I update_engine: Mapped vendor_b-cow-img to /dev/block/dm-5
I update_engine: Mapped COW image for vendor_b at vendor_b-cow-img
I update_engine: Zero-filling COW device: /dev/block/dm-5
I update_engine: [liblp]Updated logical partition table at slot 1 on device super
I bcm-bootc: setSnapshotMergeStatus()
I update_engine: Successfully created all snapshots for target slot _b
```




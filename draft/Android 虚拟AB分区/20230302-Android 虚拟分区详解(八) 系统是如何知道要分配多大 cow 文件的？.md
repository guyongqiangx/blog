# 20230302-Android 虚拟 A/B 详解(八) 系统是如何知道要分配多大 cow 文件的？



在虚拟 A/B 升级的过程中，系统需要根据当前要升级的目标设备(比如 system_b) 创建相应的 snapshot (快照) 设备(system_b-cow)，创建快照时需要提供快照的 cow 文件，而这个文件又是动态分配的。

是提前分配一个固定的文件吗？不是，系统是根据实际情况计算的，那问题来了，系统是如何计算快照设备大小的？





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




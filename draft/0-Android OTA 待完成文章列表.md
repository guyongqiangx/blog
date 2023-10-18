# 0-Android OTA 待完成文章列表



## A/B 系统

- [x] 20230227-Android Update Engine 分析（十九）Extent 到底是个什么鬼？
- [x] 20230816-Android Update Engine 分析（二十）为什么差分包比全量包小，但升级时间却更长？
- [x] 20230817-Android Update Engine 分析（二十一）Android A/B 更新过程
- [x] 20230922-Android Update Engine 分析（二十二）OTA 降级限制之 timestamp
- [x] 20230924-Android Update Engine 分析（二十三）如何在升级后清除用户数据？
- [ ] 20230925-Android Update Engine 分析（二十四）制作降级包时，到底发生了什么？
- [x] 20230926-Android Update Engine 分析（二十五）升级状态 prefs 是如何保存的？
- [x] 20230930-Android Update Engine 分析（二十六）OTA 更新后不切换 Slot 会怎样？
- [x] 20231014-Android Update Engine 分析（二十七）如何实现 OTA 更新但不切换 Slot？
- [ ] 20231008-Android Update Engine 分析（二十八）检查点 CheckPoint 是如何实现的？
- [ ] 20230929-Android Update Engine 分析（二十三）OTA 降级限制之 security patch level
- [ ] OTA 的流式更新是如何实现的？
- [ ] OTA 的 CheckPoint 是如何实现的？
- [ ] 如何只升级部分分区？partial_update
- 升级后如何同步两个槽位？
- postinstall 阶段到底都干了什么？
- update.zip 是如何打包生成的？
- 如何使用 lldb 调试 host 应用?
- 如何使用 lldb 调试 update engine?
- 升级中有哪些检查校验哈希的地方？
- 升级中哪些地方会进行大量的 IO 操作?
- update.zip 包中的那些文件都是干嘛用的？
- 升级中的进度是如何计算的？
- 各个 Action 流程是如何衔接的？
- update_metadata.proto 结构 (Android 13)

## OTA 定制

- 如何添加新分区参与 A/B 升级？
- 如何让部分分区全量升级，部分分区增量升级？
- 如何将非 A/B 分区参与升级？



## 动态分区

- super.img 分区到底是如何生成的？
- super.img 分区是如何写入到存储设备中的?



## 虚拟分区

- [x] 20231018-Android 虚拟 A/B 详解(十) 判断 Virtual A/B 是否打开的 5 种办法.md
- [ ] 20230325-Android 虚拟分区详解(十一) cow 是如何映射出来的？.md



## OTA 相关工具

- [x] 20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img
- lpflash
- simg2img, img2simg, append2simg
- simg_dump.py
- make_cow_from_ab_ota
- 关于 google.protobuf 错误
- remount
- mkbootfs
- mkbootimg
- unpack_bootimg
- repack_bootimg
- certify_bootimg
- update_engine_sideload
- update_engine_client
- lz4diff
- cow_converter
- ota_extractor
- update_device.py
- make_cow_from_ab_ota
- estimate_cow_from_nonab_ota
- inspect_cow



## 其它

- Linux 存储快照(snapshot)原理与实践(三)-快照的物理结构

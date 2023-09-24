# 0-Android OTA 待完成文章列表



## A/B 系统

- [x] 20230227-Android Update Engine 分析（十九）Extent 到底是个什么鬼？
- [x] 20230816-Android Update Engine 分析（二十）为什么差分包比全量包小，但升级时间却更长？
- [x] 20230817-Android Update Engine 分析（二十一）Android A/B 更新过程
- [x] 20230922-Android Update Engine 分析（二十二）OTA 降级限制之 timestamp
- [ ] 20230924-Android Update Engine 分析（二十三）如何在升级后清除用户数据？
- [ ] 20230929-Android Update Engine 分析（二十三）OTA 降级限制之 security patch level
- [ ] 关于 OTA 升级中的 security_patch_level 说明
- [ ] 如何只升级部分分区？partial_update
- 如何在升级后清除用户数据(userdata)? `--wipe-user-data`
- 制作升级包时指定"--downgrade"，随后都发生了什么？
- 升级后如何同步两个槽位？
- postinstall 阶段到底都干了什么？
- 升级状态保存在哪里？
- check point 是如何实现的？
- update.zip 是如何打包生成的？
- 如何使用 lldb 调试 host 应用?
- 如何使用 lldb 调试 update engine?
- 升级中有哪些检查校验哈希的地方？
- 升级中哪些地方会进行大量的 IO 操作?

## 动态分区

- super.img 分区到底是如何生成的？
- super.img 分区是如何写入到存储设备中的?



## 虚拟分区

- [ ] 20230325-Android 虚拟分区详解(十) cow 是如何映射出来的？.md



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


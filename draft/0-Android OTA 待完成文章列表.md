# 0-Android OTA 待完成文章列表



## A/B 系统

- 20230227-Android Update Engine 分析（十九）Extent 到底是个什么鬼？
- 20230816-Android Update Engine 分析（二十）为什么差分包比全量包小，但升级时间却更长？
- 20230817-Android Update Engine 分析（二十一）Android A/B 更新过程
- 升级后如何自动清除用户数据(userdata)? `--wipe-data`
- update.zip 是如何打包生成的？
- 升级后如何同步两个槽位？
- 如何使用 lldb 调试 host 应用?
- 如何使用 lldb 调试 update engine?
- 升级中有哪些检查校验哈希的地方？
- 升级过程中到底做了哪些 IO?

## 动态分区

- super.img 分区到底是如何生成的？
- super.img 分区是如何写入到存储设备中的?



## 虚拟分区



## OTA 相关工具

- 20230831-Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img
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

Linux 存储快照(snapshot)原理与实践(三)-快照的物理结构


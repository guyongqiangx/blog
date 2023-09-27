# 0-Android OTA 待完成文章列表



## A/B 系统

- [x] 20230227-Android Update Engine 分析（十九）Extent 到底是个什么鬼？
- [x] 20230816-Android Update Engine 分析（二十）为什么差分包比全量包小，但升级时间却更长？
- [x] 20230817-Android Update Engine 分析（二十一）Android A/B 更新过程
- [x] 20230922-Android Update Engine 分析（二十二）OTA 降级限制之 timestamp
- [x] 20230924-Android Update Engine 分析（二十三）如何在升级后清除用户数据？
- [ ] 20230925-Android Update Engine 分析（二十四）制作降级包时，到底发生了什么？
- [ ] 20230926-Android Update Engine 分析（二十五）升级状态是如何保存的？
- [ ] 20230929-Android Update Engine 分析（二十三）OTA 降级限制之 security patch level
- [ ] 关于 OTA 升级中的 security_patch_level 说明
- [ ] 如何只升级部分分区？partial_update
- 如何在升级后清除用户数据(userdata)? `--wipe-user-data`
- 制作升级包时指定"--downgrade"，随后都发生了什么？
- 升级后如何同步两个槽位？
- postinstall 阶段到底都干了什么？
- check point 是如何实现的？
- update.zip 是如何打包生成的？
- 如何使用 lldb 调试 host 应用?
- 如何使用 lldb 调试 update engine?
- 升级中有哪些检查校验哈希的地方？
- 升级中哪些地方会进行大量的 IO 操作?
- update.zip 中的哪些文件都是干嘛用的？

## OTA 定制

- 如何添加新分区参与 A/B 升级？
- 如何让部分分区全量升级，部分分区增量升级？
- 如何将非 A/B 分区参与升级？



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

```bash
$ awk -F '&' '/static constexpr const auto& kPrefs/{print $2; if(index($2,";")==0){getline; print}}' common/constants.h
$ awk -F '&' '/kPrefs/{print $2; if(index($2,";")==0){getline; print}}' common/constants.h
 kPrefsSubDirectory = "prefs";
 kPrefsAttemptInProgress = "attempt-in-progress";
 kPrefsBackoffExpiryTime = "backoff-expiry-time";
 kPrefsBootId = "boot-id";
 kPrefsCurrentBytesDownloaded = "current-bytes-downloaded";
 kPrefsCurrentResponseSignature = "current-response-signature";
 kPrefsCurrentUrlFailureCount = "current-url-failure-count";
 kPrefsCurrentUrlIndex = "current-url-index";
 kPrefsDailyMetricsLastReportedAt = "daily-metrics-last-reported-at";
 kPrefsDeltaUpdateFailures = "delta-update-failures";
 kPrefsDynamicPartitionMetadataUpdated = "dynamic-partition-metadata-updated";
 kPrefsFullPayloadAttemptNumber = "full-payload-attempt-number";
 kPrefsInstallDateDays = "install-date-days";
 kPrefsLastActivePingDay = "last-active-ping-day";
 kPrefsLastRollCallPingDay = "last-roll-call-ping-day";
 kPrefsManifestMetadataSize = "manifest-metadata-size";
 kPrefsManifestSignatureSize = "manifest-signature-size";
 kPrefsMetricsAttemptLastReportingTime = "metrics-attempt-last-reporting-time";
 kPrefsMetricsCheckLastReportingTime = "metrics-check-last-reporting-time";
 kPrefsNoIgnoreBackoff = "no-ignore-backoff";
 kPrefsNumReboots = "num-reboots";
 kPrefsNumResponsesSeen = "num-responses-seen";
 kPrefsOmahaCohort = "omaha-cohort";
 kPrefsOmahaCohortHint = "omaha-cohort-hint";
 kPrefsOmahaCohortName = "omaha-cohort-name";
 kPrefsOmahaEolDate = "omaha-eol-date";
 kPrefsP2PEnabled = "p2p-enabled";
 kPrefsP2PFirstAttemptTimestamp = "p2p-first-attempt-timestamp";
 kPrefsP2PNumAttempts = "p2p-num-attempts";
 kPrefsPayloadAttemptNumber = "payload-attempt-number";
 kPrefsTestUpdateCheckIntervalTimeout = "test-update-check-interval-timeout";
 kPrefsPingActive = "active";
 kPrefsPingLastActive = "date_last_active";
 kPrefsPingLastRollcall = "date_last_rollcall";
 kPrefsLastFp = "last-fp";
 kPrefsPostInstallSucceeded = "post-install-succeeded";
 kPrefsPreviousVersion = "previous-version";
 kPrefsResumedUpdateFailures = "resumed-update-failures";
 kPrefsRollbackHappened = "rollback-happened";
 kPrefsRollbackVersion = "rollback-version";
 kPrefsChannelOnSlotPrefix = "channel-on-slot-";
 kPrefsSystemUpdatedMarker = "system-updated-marker";
 kPrefsTargetVersionAttempt = "target-version-attempt";
 kPrefsTargetVersionInstalledFrom = "target-version-installed-from";
 kPrefsTargetVersionUniqueId = "target-version-unique-id";
 kPrefsTotalBytesDownloaded = "total-bytes-downloaded";
 kPrefsUpdateCheckCount = "update-check-count";
 kPrefsUpdateCheckResponseHash = "update-check-response-hash";
 kPrefsUpdateCompletedBootTime = "update-completed-boot-time";
 kPrefsUpdateCompletedOnBootId = "update-completed-on-boot-id";
 kPrefsUpdateDurationUptime = "update-duration-uptime";
 kPrefsUpdateFirstSeenAt = "update-first-seen-at";
 kPrefsUpdateOverCellularPermission = "update-over-cellular-permission";
 kPrefsUpdateOverCellularTargetVersion = "update-over-cellular-target-version";
 kPrefsUpdateOverCellularTargetSize = "update-over-cellular-target-size";
 kPrefsUpdateServerCertificate = "update-server-cert";
 kPrefsUpdateStateNextDataLength = "update-state-next-data-length";
 kPrefsUpdateStateNextDataOffset = "update-state-next-data-offset";
 kPrefsUpdateStateNextOperation = "update-state-next-operation";
 kPrefsUpdateStatePayloadIndex = "update-state-payload-index";
 kPrefsUpdateStateSHA256Context = "update-state-sha-256-context";
 kPrefsUpdateStateSignatureBlob = "update-state-signature-blob";
 kPrefsUpdateStateSignedSHA256Context = "update-state-signed-sha-256-context";
 kPrefsUpdateBootTimestampStart = "update-boot-timestamp-start";
 kPrefsUpdateTimestampStart ="update-timestamp-start";
 kPrefsUrlSwitchCount = "url-switch-count";
 kPrefsVerityWritten = "verity-written";
 kPrefsWallClockScatteringWaitPeriod = "wall-clock-wait-period";
 kPrefsWallClockStagingWaitPeriod = "wall-clock-staging-wait-period";
 kPrefsManifestBytes = "manifest-bytes";
 kPrefsPreviousSlot = "previous-slot";
```



| ID   | Name | String | Commnets |      |
| ---- | ---- | ------ | -------- | ---- |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |
|      |      |        |          |      |


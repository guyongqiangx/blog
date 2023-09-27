# 20230926-Android Update Engine 分析（二十五）升级状态是如何保存的？



## 1. Prefs 的底层实现

## 2. 到底定义了哪些 prefs?

### 1. 所有 prefs 变量

所有 update engine 使用到的 prefs 都定义在文件 `system/update_engine/common/constants.h` 中，在我统计所使用的的代码版本 android-13.0.0_r41 中，这个文件中一共定义了 70 个 prefs，全部如下:

> 其中第一个 `kPrefsSubDirectory = "prefs";` 并不是真正的 prefs 变量，而是指定 `/data/misc/update_engine` 目录下存储 prefs 所使用的子目录名称，即：
>
> `/data/misc/update_engine/prefs`

```bash
 kPrefsSubDirectory = "prefs"
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



### 2. 使用的 prefs 变量示例

在我用于调试的盒子上，在 `/data/misc/update_engine/prefs` 下，我能看到这些文件:

```bash
console:/ # ls -lh /data/misc/update_engine/prefs/                             
total 58K
-rw------- 1 root root  36 2015-01-01 08:00 boot-id
-rw------- 1 root root   1 2023-02-27 18:07 delta-update-failures
-rw------- 1 root root  88 2023-02-27 18:05 dynamic-partition-metadata-updated
-rw------- 1 root root 39K 2023-02-27 18:05 manifest-bytes
-rw------- 1 root root   5 2023-02-27 18:05 manifest-metadata-size
-rw------- 1 root root   3 2023-02-27 18:05 manifest-signature-size
-rw------- 1 root root   4 2023-02-27 18:07 post-install-succeeded
-rw------- 1 root root  26 2015-01-01 08:00 previous-version
-rw------- 1 root root   1 2023-02-27 18:05 resumed-update-failures
-rw------- 1 root root  17 2023-02-27 18:07 system-updated-marker
-rw------- 1 root root   1 2023-02-27 18:07 total-bytes-downloaded
-rw------- 1 root root  88 2023-02-27 18:05 update-check-response-hash
-rw------- 1 root root  36 2023-02-27 18:07 update-completed-on-boot-id
-rw------- 1 root root   1 2023-02-27 18:07 update-state-next-data-length
-rw------- 1 root root   9 2023-02-27 18:07 update-state-next-data-offset
-rw------- 1 root root   3 2023-02-27 18:07 update-state-next-operation
-rw------- 1 root root 112 2023-02-27 18:07 update-state-sha-256-context
-rw------- 1 root root 267 2023-02-27 18:07 update-state-signature-blob
-rw------- 1 root root 112 2023-02-27 18:07 update-state-signed-sha-256-context
-rw------- 1 root root   4 2023-02-27 18:07 verity-written
console:/ # 
```

在 OTA 升级过程中，可能有更多变量被使用，在升级完成后随即被删除了。



在 Android 下可以使用 cat 其它命令查看，但我自己习惯使用 xxd 命令查看原始的十六进制以及 ASCII 格式的内容，例如:
```bash
# 1. 查看 boot-id
console:/data/misc/update_engine/prefs # xxd -g 1 boot-id
00000000: 38 62 38 37 34 64 63 36 2d 38 63 62 61 2d 34 62  8b874dc6-8cba-4b
00000010: 64 34 2d 61 36 64 30 2d 39 63 66 32 38 39 39 32  d4-a6d0-9cf28992
00000020: 35 64 62 66                                      5dbf

# 2. 查看 manifest-metadata-size
console:/data/misc/update_engine/prefs # xxd -g 1 manifest-metadata-size
00000000: 33 39 37 39 39                                   39799

# 3. 查看 total-bytes-downloaded
console:/data/misc/update_engine/prefs # xxd -g 1 total-bytes-downloaded
00000000: 30                                               0
```



## 3. 重要的 prefs 举例

### 1. 对所有 prefs 排序

你肯定会说，70 个 prefs，那么多，我怎么可能知道这些 prefs 都是干什么用的。

的确，70 个 prefs 不可能每一个都仔细排查，不过，我对这些 prefs 进行过一些初步统计，或许能突出一些重点。

### 

我写了个 python 脚本从 update engine 中抓取所有定义的 prefs 被使用的地方，除了在 common/constant.h 中的定义外，根据其在代码和注释中被引用的次数作为热度进行了排序。

全部 70 个 prefs 中有 40 个 prefs 只有定义，没有被使用。其余 30 个 prefs 按照被引用情况的情况排序如下：

> Refs(used): 表示该 prefs 在代码中实际被引用的次数，不包括 "//" 开头的注释
>
> Refs(all): 表示该 prefs 在代码中出现的次数，包括 "//" 开头的注释行
>
> 所有搜索都排除了 *test.cc 或 *unittest.cc 的测试文件。
> 



| ID | Prefs 名称 | Prefs 值 | 引用次数<br />(不含注释) | 引用次数<br />(含注释) |
| ---- | ---- | ------ | -------- | ---- |
| 1 | kPrefsDynamicPartitionMetadataUpdated | "dynamic-partition-metadata-updated" | 6 | 6 |
| 2 | kPrefsManifestMetadataSize | "manifest-metadata-size" | 5 | 5 |
| 3 | kPrefsManifestSignatureSize | "manifest-signature-size" | 5 | 5 |
| 4 | kPrefsNumReboots | "num-reboots" | 5 | 8 |
| 5 | kPrefsPayloadAttemptNumber | "payload-attempt-number" | 5 | 9 |
| 6 | kPrefsPreviousVersion | "previous-version" | 5 | 6 |
| 7 | kPrefsUpdateCompletedOnBootId | "update-completed-on-boot-id" | 5 | 5 |
| 8 | kPrefsUpdateStateNextDataOffset | "update-state-next-data-offset" | 5 | 5 |
| 9 | kPrefsPreviousSlot | "previous-slot" | 5 | 5 |
| 10 | kPrefsCurrentBytesDownloaded | "current-bytes-downloaded" | 4 | 6 |
| 11 | kPrefsResumedUpdateFailures | "resumed-update-failures" | 4 | 4 |
| 12 | kPrefsTotalBytesDownloaded | "total-bytes-downloaded" | 4 | 5 |
| 13 | kPrefsUpdateStateNextOperation | "update-state-next-operation" | 4 | 4 |
| 14 | kPrefsUpdateStateSHA256Context | "update-state-sha-256-context" | 4 | 4 |
| 15 | kPrefsVerityWritten | "verity-written" | 4 | 4 |
| 16 | kPrefsSystemUpdatedMarker | "system-updated-marker" | 3 | 9 |
| 17 | kPrefsUpdateCheckResponseHash | "update-check-response-hash" | 3 | 4 |
| 18 | kPrefsUpdateStateNextDataLength | "update-state-next-data-length" | 3 | 3 |
| 19 | kPrefsUpdateStateSignatureBlob | "update-state-signature-blob" | 3 | 3 |
| 20 | kPrefsUpdateStateSignedSHA256Context | "update-state-signed-sha-256-context" | 3 | 3 |
| 21 | kPrefsUpdateBootTimestampStart | "update-boot-timestamp-start" | 3 | 7 |
| 22 | kPrefsUpdateTimestampStart | "update-timestamp-start" | 3 | 7 |
| 23 | kPrefsBootId | "boot-id" | 2 | 3 |
| 24 | kPrefsPostInstallSucceeded | "post-install-succeeded" | 2 | 2 |
| 25 | kPrefsManifestBytes | "manifest-bytes" | 2 | 2 |
| 26 | kPrefsDeltaUpdateFailures | "delta-update-failures" | 1 | 1 |
| 27 | kPrefsUpdateServerCertificate | "update-server-cert" | 1 | 1 |
| 28 | kPrefsUpdateStatePayloadIndex | "update-state-payload-index" | 1 | 1 |
| 29 | kPrefsOmahaCohort | "omaha-cohort" | 0 | 2 |
| 30 | kPrefsPingActive | "active" | 0 | 1 |



由于 prefs 个数实在太多，不可能在本篇中一一列举其作用或意义。

以下提供一些研究 prefs 的方法。

```bash
android-13.0.0_r41/system/update_engine$ grep -rn kPrefsBootId --exclude="*test.cc" .
./common/constants.h:46:static constexpr const auto& kPrefsBootId = "boot-id";
./aosp/update_attempter_android.h:203:  //   |kPrefsBootId|, |kPrefsPreviousVersion|
./aosp/update_attempter_android.cc:161:  if (!prefs->GetString(kPrefsBootId, &old_boot_id)) {
./aosp/update_attempter_android.cc:988:  prefs_->SetString(kPrefsBootId, current_boot_id);
```

> 这里使用选项 `--exclude="*test.cc"` 来排除所有的 unittest.cc 测试文件。

在所有的 4 个搜索结果中：

第 1 条，kPrefsBootId 的定义；

第 2 条，注释释，没有实质内容；

第 3 条，调用 GetString 获取现有的 "boot-id"；

第 4 条，调用 SetString 设置新的 "boot-id"；

那到底啥时候读取 "boot-id"，啥时候设置新的 "boot-id" 呢？







关于 update engine 服务端进程如如何启动的，请参考:[《Android Update Engine分析（四）服务端进程》](https://blog.csdn.net/guyongqiangx/article/details/82116213)

下面是简单说明：

Update Engine 服务端进程(代码 `main.cc`)在 main 函数中先解析命令行参数并进行简单初始化，随后创建`update_engine_daemon` 对象，并调用对象的 `Run()`方法进入服务等待状态。

在 `Run()` 中进入主循环前，通过 `OnInit()`初始化生成两个业务对象 `binder_service`_和 `daemon_state_`，前者负责 binder 服务对外的工作，后者则负责 Update Engine 后台的实际业务。

`binder_service_` 接收到客户端的服务请求后，将其交给 `daemon_state_` 的成员 `update_attempter_` 去完成，所以 `update_attempter_` 是 Update Engine 服务端业务的核心。

而 `update_attermpter_` 就是 `UpdateAttempterAndroid` 类的对象。



所以，Update Engine 启动的流程如下:

```
--> main(argc, argv)
  --> daemon = chromeos_update_engine::DaemonBase::CreateInstance() (返回 DaemonAndroid 实例)
  --> daemon->Run() (即: DaemonAndroid::Run())
    --> Deamon::Run() (执行父类的 Run())
      --> Daemon::OnInit() (虚函数，执行子类的 OnInit())
        --> DaemonAndroid::OnInit()
          --> daemon_state_ = new DaemonStateAndroid()
          --> daemon_state_->AddObserver(binder_service_)
          --> daemon_state_->StartUpdater() (即: DaemonStateAndroid::StartUpdater())
            --> update_attempter_->Init() (即: UpdateAttempterAndroid::Init())
    --> message_loop_.PostTask(Daemon::OnEventLoopStartedTask)
    --> message_loop_.Run() (消息主循环)
    --> Daemon::OnShutdown(&exit_code_)
```







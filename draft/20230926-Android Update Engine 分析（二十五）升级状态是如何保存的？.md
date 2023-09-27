# 20230926-Android Update Engine 分析（二十五）升级状态是如何保存的？



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

## all (1-71)

| ID   | Name                                  | String                                | Count | Comments |
| ---- | ------------------------------------- | ------------------------------------- | ----- | -------- |
| 1    | kPrefsAttemptInProgress               | "attempt-in-progress"                 | 0     |          |
| 2    | kPrefsBackoffExpiryTime               | "backoff-expiry-time"                 | 0     |          |
| 3    | kPrefsBootId                          | "boot-id"                             | 3     |          |
| 4    | kPrefsCurrentBytesDownloaded          | "current-bytes-downloaded"            | 6     |          |
| 5    | kPrefsCurrentResponseSignature        | "current-response-signature"          | 0     |          |
| 6    | kPrefsCurrentUrlFailureCount          | "current-url-failure-count"           | 0     |          |
| 7    | kPrefsCurrentUrlIndex                 | "current-url-index"                   | 0     |          |
| 8    | kPrefsDailyMetricsLastReportedAt      | "daily-metrics-last-reported-at"      | 0     |          |
| 9    | kPrefsDeltaUpdateFailures             | "delta-update-failures"               | 1     |          |
| 10   | kPrefsDynamicPartitionMetadataUpdated | "dynamic-partition-metadata-updated"  | 6     |          |
| 11   | kPrefsFullPayloadAttemptNumber        | "full-payload-attempt-number"         | 0     |          |
| 12   | kPrefsInstallDateDays                 | "install-date-days"                   | 0     |          |
| 13   | kPrefsLastActivePingDay               | "last-active-ping-day"                | 0     |          |
| 14   | kPrefsLastRollCallPingDay             | "last-roll-call-ping-day"             | 0     |          |
| 15   | kPrefsManifestMetadataSize            | "manifest-metadata-size"              | 5     |          |
| 16   | kPrefsManifestSignatureSize           | "manifest-signature-size"             | 5     |          |
| 17   | kPrefsMetricsAttemptLastReportingTime | "metrics-attempt-last-reporting-time" | 0     |          |
| 18   | kPrefsMetricsCheckLastReportingTime   | "metrics-check-last-reporting-time"   | 0     |          |
| 19   | kPrefsNoIgnoreBackoff                 | "no-ignore-backoff"                   | 0     |          |
| 20   | kPrefsNumReboots                      | "num-reboots"                         | 8     |          |
| 21   | kPrefsNumResponsesSeen                | "num-responses-seen"                  | 0     |          |
| 22   | kPrefsOmahaCohort                     | "omaha-cohort"                        | 2     |          |
| 23   | kPrefsOmahaCohortHint                 | "omaha-cohort-hint"                   | 0     |          |
| 24   | kPrefsOmahaCohortName                 | "omaha-cohort-name"                   | 0     |          |
| 25   | kPrefsOmahaEolDate                    | "omaha-eol-date"                      | 0     |          |
| 26   | kPrefsP2PEnabled                      | "p2p-enabled"                         | 0     |          |
| 27   | kPrefsP2PFirstAttemptTimestamp        | "p2p-first-attempt-timestamp"         | 0     |          |
| 28   | kPrefsP2PNumAttempts                  | "p2p-num-attempts"                    | 0     |          |
| 29   | kPrefsPayloadAttemptNumber            | "payload-attempt-number"              | 9     |          |
| 30   | kPrefsTestUpdateCheckIntervalTimeout  | "test-update-check-interval-timeout"  | 0     |          |
| 31   | kPrefsPingActive                      | "active"                              | 1     |          |
| 32   | kPrefsPingLastActive                  | "date_last_active"                    | 0     |          |
| 33   | kPrefsPingLastRollcall                | "date_last_rollcall"                  | 0     |          |
| 34   | kPrefsLastFp                          | "last-fp"                             | 0     |          |
| 35   | kPrefsPostInstallSucceeded            | "post-install-succeeded"              | 2     |          |
| 36   | kPrefsPreviousVersion                 | "previous-version"                    | 6     |          |
| 37   | kPrefsResumedUpdateFailures           | "resumed-update-failures"             | 4     |          |
| 38   | kPrefsRollbackHappened                | "rollback-happened"                   | 0     |          |
| 39   | kPrefsRollbackVersion                 | "rollback-version"                    | 0     |          |
| 40   | kPrefsChannelOnSlotPrefix             | "channel-on-slot-"                    | 0     |          |
| 41   | kPrefsSystemUpdatedMarker             | "system-updated-marker"               | 9     |          |
| 42   | kPrefsTargetVersionAttempt            | "target-version-attempt"              | 0     |          |
| 43   | kPrefsTargetVersionInstalledFrom      | "target-version-installed-from"       | 0     |          |
| 44   | kPrefsTargetVersionUniqueId           | "target-version-unique-id"            | 0     |          |
| 45   | kPrefsTotalBytesDownloaded            | "total-bytes-downloaded"              | 5     |          |
| 46   | kPrefsUpdateCheckCount                | "update-check-count"                  | 0     |          |
| 47   | kPrefsUpdateCheckResponseHash         | "update-check-response-hash"          | 4     |          |
| 48   | kPrefsUpdateCompletedBootTime         | "update-completed-boot-time"          | 0     |          |
| 49   | kPrefsUpdateCompletedOnBootId         | "update-completed-on-boot-id"         | 5     |          |
| 50   | kPrefsUpdateDurationUptime            | "update-duration-uptime"              | 0     |          |
| 51   | kPrefsUpdateFirstSeenAt               | "update-first-seen-at"                | 0     |          |
| 52   | kPrefsUpdateOverCellularPermission    | "update-over-cellular-permission"     | 0     |          |
| 53   | kPrefsUpdateOverCellularTargetVersion | "update-over-cellular-target-version" | 0     |          |
| 54   | kPrefsUpdateOverCellularTargetSize    | "update-over-cellular-target-size"    | 0     |          |
| 55   | kPrefsUpdateServerCertificate         | "update-server-cert"                  | 1     |          |
| 56   | kPrefsUpdateStateNextDataLength       | "update-state-next-data-length"       | 3     |          |
| 57   | kPrefsUpdateStateNextDataOffset       | "update-state-next-data-offset"       | 5     |          |
| 58   | kPrefsUpdateStateNextOperation        | "update-state-next-operation"         | 4     |          |
| 59   | kPrefsUpdateStatePayloadIndex         | "update-state-payload-index"          | 1     |          |
| 60   | kPrefsUpdateStateSHA256Context        | "update-state-sha-256-context"        | 4     |          |
| 61   | kPrefsUpdateStateSignatureBlob        | "update-state-signature-blob"         | 3     |          |
| 62   | kPrefsUpdateStateSignedSHA256Context  | "update-state-signed-sha-256-context" | 3     |          |
| 63   | kPrefsUpdateBootTimestampStart        | "update-boot-timestamp-start"         | 7     |          |
| 64   | kPrefsUpdateTimestampStart            | "update-timestamp-start"              | 7     |          |
| 65   | kPrefsUrlSwitchCount                  | "url-switch-count"                    | 0     |          |
| 66   | kPrefsVerityWritten                   | "verity-written"                      | 4     |          |
| 67   | kPrefsWallClockScatteringWaitPeriod   | "wall-clock-wait-period"              | 0     |          |
| 68   | kPrefsWallClockStagingWaitPeriod      | "wall-clock-staging-wait-period"      | 0     |          |
| 69   | kPrefsManifestBytes                   | "manifest-bytes"                      | 2     |          |
| 70   | kPrefsPreviousSlot                    | "previous-slot"                       | 5     |          |

## unsort order

| ID   | Name                                  | String                                | Count | Comments |
| ---- | ------------------------------------- | ------------------------------------- | ----- | -------- |
| 3    | kPrefsBootId                          | "boot-id"                             | 3     |          |
| 4    | kPrefsCurrentBytesDownloaded          | "current-bytes-downloaded"            | 6     |          |
| 9    | kPrefsDeltaUpdateFailures             | "delta-update-failures"               | 1     |          |
| 10   | kPrefsDynamicPartitionMetadataUpdated | "dynamic-partition-metadata-updated"  | 6     |          |
| 15   | kPrefsManifestMetadataSize            | "manifest-metadata-size"              | 5     |          |
| 16   | kPrefsManifestSignatureSize           | "manifest-signature-size"             | 5     |          |
| 20   | kPrefsNumReboots                      | "num-reboots"                         | 8     |          |
| 22   | kPrefsOmahaCohort                     | "omaha-cohort"                        | 2     |          |
| 29   | kPrefsPayloadAttemptNumber            | "payload-attempt-number"              | 9     |          |
| 31   | kPrefsPingActive                      | "active"                              | 1     |          |
| 35   | kPrefsPostInstallSucceeded            | "post-install-succeeded"              | 2     |          |
| 36   | kPrefsPreviousVersion                 | "previous-version"                    | 6     |          |
| 37   | kPrefsResumedUpdateFailures           | "resumed-update-failures"             | 4     |          |
| 41   | kPrefsSystemUpdatedMarker             | "system-updated-marker"               | 9     |          |
| 45   | kPrefsTotalBytesDownloaded            | "total-bytes-downloaded"              | 5     |          |
| 47   | kPrefsUpdateCheckResponseHash         | "update-check-response-hash"          | 4     |          |
| 49   | kPrefsUpdateCompletedOnBootId         | "update-completed-on-boot-id"         | 5     |          |
| 55   | kPrefsUpdateServerCertificate         | "update-server-cert"                  | 1     |          |
| 56   | kPrefsUpdateStateNextDataLength       | "update-state-next-data-length"       | 3     |          |
| 57   | kPrefsUpdateStateNextDataOffset       | "update-state-next-data-offset"       | 5     |          |
| 58   | kPrefsUpdateStateNextOperation        | "update-state-next-operation"         | 4     |          |
| 59   | kPrefsUpdateStatePayloadIndex         | "update-state-payload-index"          | 1     |          |
| 60   | kPrefsUpdateStateSHA256Context        | "update-state-sha-256-context"        | 4     |          |
| 61   | kPrefsUpdateStateSignatureBlob        | "update-state-signature-blob"         | 3     |          |
| 62   | kPrefsUpdateStateSignedSHA256Context  | "update-state-signed-sha-256-context" | 3     |          |
| 63   | kPrefsUpdateBootTimestampStart        | "update-boot-timestamp-start"         | 7     |          |
| 64   | kPrefsUpdateTimestampStart            | "update-timestamp-start"              | 7     |          |
| 66   | kPrefsVerityWritten                   | "verity-written"                      | 4     |          |
| 69   | kPrefsManifestBytes                   | "manifest-bytes"                      | 2     |          |
| 70   | kPrefsPreviousSlot                    | "previous-slot"                       | 5     |          |

## filter out

| ID   | Name                                  | String                                | Count | Comments |
| ---- | ------------------------------------- | ------------------------------------- | ----- | -------- |
| 0    | kPrefsSubDirectory                    | "prefs"                               | 1     |          |
| 1    | kPrefsBootId                          | "boot-id"                             | 3     |          |
| 2    | kPrefsCurrentBytesDownloaded          | "current-bytes-downloaded"            | 6     |          |
| 3    | kPrefsDeltaUpdateFailures             | "delta-update-failures"               | 1     |          |
| 4    | kPrefsDynamicPartitionMetadataUpdated | "dynamic-partition-metadata-updated"  | 6     |          |
| 5    | kPrefsManifestMetadataSize            | "manifest-metadata-size"              | 5     |          |
| 6    | kPrefsManifestSignatureSize           | "manifest-signature-size"             | 5     |          |
| 7    | kPrefsNumReboots                      | "num-reboots"                         | 8     |          |
| 8    | kPrefsOmahaCohort                     | "omaha-cohort"                        | 2     |          |
| 9    | kPrefsPayloadAttemptNumber            | "payload-attempt-number"              | 9     |          |
| 10   | kPrefsPingActive                      | "active"                              | 1     |          |
| 11   | kPrefsPostInstallSucceeded            | "post-install-succeeded"              | 2     |          |
| 12   | kPrefsPreviousVersion                 | "previous-version"                    | 6     |          |
| 13   | kPrefsResumedUpdateFailures           | "resumed-update-failures"             | 4     |          |
| 14   | kPrefsSystemUpdatedMarker             | "system-updated-marker"               | 9     |          |
| 15   | kPrefsTotalBytesDownloaded            | "total-bytes-downloaded"              | 5     |          |
| 16   | kPrefsUpdateCheckResponseHash         | "update-check-response-hash"          | 4     |          |
| 17   | kPrefsUpdateCompletedOnBootId         | "update-completed-on-boot-id"         | 5     |          |
| 18   | kPrefsUpdateServerCertificate         | "update-server-cert"                  | 1     |          |
| 19   | kPrefsUpdateStateNextDataLength       | "update-state-next-data-length"       | 3     |          |
| 20   | kPrefsUpdateStateNextDataOffset       | "update-state-next-data-offset"       | 5     |          |
| 21   | kPrefsUpdateStateNextOperation        | "update-state-next-operation"         | 4     |          |
| 22   | kPrefsUpdateStatePayloadIndex         | "update-state-payload-index"          | 1     |          |
| 23   | kPrefsUpdateStateSHA256Context        | "update-state-sha-256-context"        | 4     |          |
| 24   | kPrefsUpdateStateSignatureBlob        | "update-state-signature-blob"         | 3     |          |
| 25   | kPrefsUpdateStateSignedSHA256Context  | "update-state-signed-sha-256-context" | 3     |          |
| 26   | kPrefsUpdateBootTimestampStart        | "update-boot-timestamp-start"         | 7     |          |
| 27   | kPrefsUpdateTimestampStart            | "update-timestamp-start"              | 7     |          |
| 28   | kPrefsVerityWritten                   | "verity-written"                      | 4     |          |
| 29   | kPrefsManifestBytes                   | "manifest-bytes"                      | 2     |          |
| 30   | kPrefsPreviousSlot                    | "previous-slot"                       | 5     |          |

## filter out with order

| ID   | Name                                  | String                                | Count | Comments |
| ---- | ------------------------------------- | ------------------------------------- | ----- | -------- |
| 1    | kPrefsPayloadAttemptNumber            | "payload-attempt-number"              | 9     |          |
| 2    | kPrefsSystemUpdatedMarker             | "system-updated-marker"               | 9     |          |
| 3    | kPrefsNumReboots                      | "num-reboots"                         | 8     |          |
| 4    | kPrefsUpdateBootTimestampStart        | "update-boot-timestamp-start"         | 7     |          |
| 5    | kPrefsUpdateTimestampStart            | "update-timestamp-start"              | 7     |          |
| 6    | kPrefsCurrentBytesDownloaded          | "current-bytes-downloaded"            | 6     |          |
| 7    | kPrefsDynamicPartitionMetadataUpdated | "dynamic-partition-metadata-updated"  | 6     |          |
| 8    | kPrefsPreviousVersion                 | "previous-version"                    | 6     |          |
| 9    | kPrefsManifestMetadataSize            | "manifest-metadata-size"              | 5     |          |
| 10   | kPrefsManifestSignatureSize           | "manifest-signature-size"             | 5     |          |
| 11   | kPrefsTotalBytesDownloaded            | "total-bytes-downloaded"              | 5     |          |
| 12   | kPrefsUpdateCompletedOnBootId         | "update-completed-on-boot-id"         | 5     |          |
| 13   | kPrefsUpdateStateNextDataOffset       | "update-state-next-data-offset"       | 5     |          |
| 14   | kPrefsPreviousSlot                    | "previous-slot"                       | 5     |          |
| 15   | kPrefsResumedUpdateFailures           | "resumed-update-failures"             | 4     |          |
| 16   | kPrefsUpdateCheckResponseHash         | "update-check-response-hash"          | 4     |          |
| 17   | kPrefsUpdateStateNextOperation        | "update-state-next-operation"         | 4     |          |
| 18   | kPrefsUpdateStateSHA256Context        | "update-state-sha-256-context"        | 4     |          |
| 19   | kPrefsVerityWritten                   | "verity-written"                      | 4     |          |
| 20   | kPrefsBootId                          | "boot-id"                             | 3     |          |
| 21   | kPrefsUpdateStateNextDataLength       | "update-state-next-data-length"       | 3     |          |
| 22   | kPrefsUpdateStateSignatureBlob        | "update-state-signature-blob"         | 3     |          |
| 23   | kPrefsUpdateStateSignedSHA256Context  | "update-state-signed-sha-256-context" | 3     |          |
| 24   | kPrefsOmahaCohort                     | "omaha-cohort"                        | 2     |          |
| 25   | kPrefsPostInstallSucceeded            | "post-install-succeeded"              | 2     |          |
| 26   | kPrefsManifestBytes                   | "manifest-bytes"                      | 2     |          |
| 27   | kPrefsDeltaUpdateFailures             | "delta-update-failures"               | 1     |          |
| 28   | kPrefsPingActive                      | "active"                              | 1     |          |
| 29   | kPrefsUpdateServerCertificate         | "update-server-cert"                  | 1     |          |
| 30   | kPrefsUpdateStatePayloadIndex         | "update-state-payload-index"          | 1     |          |



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
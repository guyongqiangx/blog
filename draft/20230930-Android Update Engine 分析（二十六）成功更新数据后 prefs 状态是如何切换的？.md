# 20230930-Android Update Engine 分析（二十六）成功更新数据后 prefs 状态是如何切换的？

![image-20230930003407777](images-20230930-Android Update Engine 分析（二十六）成功更新数据后 prefs 状态是如何切换的？/image-20230930003407777.png)

![image-20230930003353770](images-20230930-Android Update Engine 分析（二十六）成功更新数据后 prefs 状态是如何切换的？/image-20230930003353770.png)



这里以 kPrefsBootId 为例，提供一些研究 prefs 的方法。

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

这个话题要从升级完成时的操作说起。

系统升级完成时调用 WriteUpdateCompleteMarker() 函数：

1. 获取当前启动的 boot_id，保存到 `kPrefsUpdateCompletedOnBootId` 中。
2. 将当前系统的分区后缀保存到 `kPrefsPreviousSlot` 中，因为当前升级完成以后，会伴随系统的重启以及分区的切换(切换到升级的新系统中)。

![image-20230929232120723](images-20230930-Android Update Engine 分析（二十六）成功更新数据后 prefs 状态是如何切换的？/image-20230929232120723.png)`

> 对 linux 系统来说，每次启动都会在文件 "/proc/sys/kernel/random/boot_id" 中保存一个唯一的 id，任意的两次启动都不会有相同的 id。所以，如果两次获取的 boot_id 一样，则说明当前处于系统同一次启动的生命周期内。

Update Engine 启动后，读取当前系统的 boot_id 和上次成功写入数据时记录的 boot_id 比较，如果两个 boot_id 一样，说明系统自从成功写入数据后还没有重启过，此时发送状态通知：更新后需要重启。

![image-20230929233359090](images-20230930-Android Update Engine 分析（二十六）成功更新数据后 prefs 状态是如何切换的？/image-20230929233359090.png)



如果系统升级写入数据后，并且重启了，此时的调用 GetOTAUpdateResult() 获取 OTA 升级结果。函数 GetOTAUpdateResult() 对升级结果的检查也十分精彩：

![image-20230930000036110](images-20230930-Android Update Engine 分析（二十六）成功更新数据后 prefs 状态是如何切换的？/image-20230930000036110.png)

一般情况下，升级数据写入成功后写入标记，系统重启，并切换 slot 槽位。

所以，自然而然，这里的 OTA 结果就需要检查 3 个条件并综合判断：

1. 检查升级数据写入成功后的标记 kPrefsUpdateCompleteOnBootId
2. 检查系统是否重启了
3. 检查系统 slot 槽位是否发生了切换

根据 3 个条件的结果，这里分成多种情况：

如果检查到系统上次升级数据成功后写入的标记，并且系统重启了，而且槽位发生了切换，返回结果：升级成功(OTA_SUCCESSFUL)。

如果检查到系统上次升级数据成功后写入的标记，系统也重启了，但是槽位没有发生切换，那说明系统升级可能在哪里发生问题了导致系统槽位没有切换成功，返回结果：系统回滚(ROLLED_BACK)。

如果检查到系统上次升级数据成功后写入的标记，系统还没重启，返回结果：系统需要重启(UPDATED_NEED_REBOOT)。

如果连系统上次升级数据成功后写入的标记都没有检查到，那说明系统没有升级，返回结果：没有尝试过升级(NOT_ATTEMPTED)。



如果当前系统的 boot_id 和上次成功写入数据时记录的 boot_id 比较，如果两个 boot_id 不一样，说明系统升级成功写入数据已经重启过了，此时调用 GetOTAUpdateResult() 检查 OTA 升级结果。

并将升级结果的 4 种情况传递给 UpdateStateAfterReboot() 函数。






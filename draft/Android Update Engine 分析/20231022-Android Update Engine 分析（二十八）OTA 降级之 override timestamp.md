# 20231022-Android Update Engine 分析（二十八）OTA 降级之 override timestamp

在本篇之前，我已经写过 3 篇降级相关的文章，分别是:

- [Android Update Engine分析（二十二）OTA 降级限制之 timestamp](https://blog.csdn.net/guyongqiangx/article/details/133191750)

  介绍 OTA 更新中，对分区槽位 max_timestamp 的检查。如果 payload 文件的 manifest 中存放的 max_timestamp 时间戳小于当前系统的编译时间，说明当前系统的编译时间(hardware_->GetBuildTimestamp())比制作 payload 的所用的 source 和 target 槽位镜像都要新，那可以断定是进行了降级操作。

- [Android Update Engine分析（二十三）如何在升级后清除用户数据？](https://blog.csdn.net/guyongqiangx/article/details/133274277)

  介绍了制作 OTA 更新包时，指定 "--wipe_user_data" 选项后，这个选项从如何制作生成 payload，一直到系统更新重启，然后进入 Recovery 擦除 "/cache", "/data" 和 "/metadata" 等分区的过程。

- [Android Update Engine分析（二十四）制作降级包时，到底发生了什么？](https://blog.csdn.net/guyongqiangx/article/details/133421556)

  介绍了制作 OTA 更新包时，指定 "--downgrade" 制作降级包，以及随后被分解为 "downgrade" 和 "wipe-user-data" 两个选项，用 "downgrade" 选项影响 max_timestamp 检查，以及使用 "wipe-user-data" 选项在升级后进入 Recovery 擦除用户数据的过程。

本篇降介绍另外一个降级操作 "--override_timestamp" 选项，以及这个选项和使用 "--downgrade" 进行降级的区别。

## 1. 使用 "--downgrade" 制作降级包

在正式开始介绍 "--override_timestamp" 选项之前，先回顾下使用选项 "--downgrade" 制作降级包的过程。



使用 "--downgrade" 参数制作降级包，命令如下：

```bash
$ ota_from_target_files --downgrade -i new-target_files.zip old-target_files.zip downgrade.zip
```



在解析命令行参数后，"--downgrade" 参数被转换成两个选项"OPTIONS.downgrade=True"  和 "OPTIONS.wide_user_data=True"。



对于 "OPTIONS.downgrade=True" 选项：

1. 提取 source 槽位的编译时间戳 (即: Build Property 数据中的 “ro.build.date.utc”)，用来设置 max_timestamp 参数，最终用于设置 manifest.max_timestamp，并输出到 payload.bin 文件中。
2. 升级过程中，当接收完 manifest 数据后，将其传递给 ValidateManifest() 函数进行检查验证，用于检查当前的系统的编译时间和 payload 中的 max_timestamp 指定的时间。进行一般性的时间戳判断。



对于 "OPTIONS.wide_user_data=True" 选项：

1. 制作 OTA 更新包时，`POWERWASH=1` 被写入到payload_properties.txt 文件中。

2. 升级时，将 `POWERWASH=1` 作为 headers 参数的内容传递给 update engine 服务端程序。
3. 在升级后期的 PostinstallRunnerAction 中，往 BCB(bootloader message block) 区域写入命令 “boot-recovery”，并携带两个参数 “`–wipe_data`” 和 “`–reason=wipe_data_from_ota`”。
4. 系统更新后重启，进入 Recovery 模式。
5. recovery 应用程序读取 BCB 区域，解析得到 “wipe_data” 参数，调用 WipeData 函数执行数据清理工作：
   - 擦除 “/data” 分区
   - 擦除 “/cache” 分区
   - 擦除 “/metadata” 分区
6. 做完这一系列工作后，退出 recovery 系统，重启进入 Android 新系统。



## 2. 使用 "--override_timestamp" 制作降级包

从上一节回顾 "--downgrade" 参数的操作可以看到，使用降级包更新时，会重启两次：

先重启进入 Recovery 系统，擦除用户数据；然后再次重启进入更新后的系统。



擦除用户数据，在有的时候很不方便。

比方说开发过程中，只是临时从一个分支切换到另外一个分支去工作。




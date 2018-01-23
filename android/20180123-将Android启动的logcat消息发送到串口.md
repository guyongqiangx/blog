最近在Android 8.0上做启动时间优化，对部分service优化后Android无法正常启动了，此时shell和adb都不可用，service的调试输出信息是通过logcat输出的，串口无法看到。凭经验猜测原因，调试起来比较困难。于是想到在Android启动中将logcat消息发送到kmsg，通过串口输出。

将logcat消息发送到串口还是有意义的，主要有以下两种需求：
- shell和adb不可用时，需要检查logcat消息 （也就是我前面提到的需求）
- 将kmesg和logcat消息合并到一起，用于启动时间优化时进行时间点检查

  这样做有两点局限
  - logcat其自身消息机制的原因，得到的消息并不是实时的(有待进一步检验)
  - 将很多logcat消息发往串口低速设备，大量I/O会影响启动时间


网上很多地方也提到了通过logcat的`"-f"`选项将输出重定向到`"/dev/kmsg"`
```
service logcat /system/bin/logcat -f /dev/kmsg 
    oneshot
```

这里没有为service指定class，其默认为"default"，也可以将其指定为其它名称，这样就能以`"class_start xxx"`的方式启动。

在Android 8.0上默认情况下，由于selinux的原因，只添加上面的service无法使用，有两种方式设置selinux:

- 启动Android的命令行中指定`"androidboot.selinux=permissive"`抑制selinux操作

  这里的`permissive`选项表示selinux会执行权限检查，对于不符合规则的审查会显示警告信息，但会授予权限。适合开发时使用。

- 添加selinux规则，授予logcat操作的权限

  根据规则，在Android的sepolicy指定目录下新建`logpersist.te`文件，包含以下规则：
    ```
    allow logpersist device:dir { open read };
    allow logpersist kmsg_device:chr_file { open append getattr };
    ```
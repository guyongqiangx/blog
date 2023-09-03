# 20230902-Android OTA 相关工具(十) 使用 update_device.py 进行升级测试

我以前是这样进行 OTA 升级测试的:



本文基于 android-13.0.0_r41 代码中的 update_device.py 进行介绍，如果你的版本早于这里的版本，可能这里提到的部分功能不可用。



> [《Android OTA 相关工具》](https://blog.csdn.net/guyongqiangx/category_12211864.html)系列，目前已有文章列表：
>
> - [《Android OTA 相关工具(一) 虚拟 A/B 之 snapshotctl》](https://blog.csdn.net/guyongqiangx/article/details/129122159)
> - [《Android OTA 相关工具(二) 动态分区之 dmctl》](https://blog.csdn.net/guyongqiangx/article/details/129229115)
> - [《Android OTA 相关工具(三) A/B 系统之 bootctl 工具》](https://blog.csdn.net/guyongqiangx/article/details/129310109)
> - [《Android OTA 相关工具(四) 查看 payload 文件信息》](https://blog.csdn.net/guyongqiangx/article/details/129228856)
> - [《Android OTA 相关工具(五) 使用 lpdump 查看动态分区》](https://blog.csdn.net/guyongqiangx/article/details/129785777)
> - [《Android OTA 相关工具(六) 使用 lpmake 打包生成 super.img》](https://blog.csdn.net/guyongqiangx/article/details/132581720)
> - [《Android OTA 相关工具(七) 使用 lpunpack 解包 super.img》](https://blog.csdn.net/guyongqiangx/article/details/132598451)
> - [《Android OTA 相关工具(八) 使用 lpadd 添加镜像到 super.img》](https://blog.csdn.net/guyongqiangx/article/details/132635213)



> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/132635213



## 1. update_device.py 环境

update_device.py 是一个 python 脚本，位于 `system/update_engine/scripts` 目录下。

建议在设置 Android 编译环境后，再把 update_device.py 所在的 scripts 目录也添加到 PATH 环境变量中：

```bash
$ source build/envsetup.sh 
$ lunch aosp_panther-userdebug
$ export PATH=$PWD/system/update_engine/scripts:$PATH
$ which update_device.py
/public/rocky/android-13.0.0_r41/system/update_engine/scripts/update_device.py
```

当然，你也更改 update engine 的 Android.bp，把 update_device.py 工具在编译时复制到 out/host/linux-x86/bin 目录下，但由于 update_device.py 依赖于 update_payload 库，所以也需要把这个库复制过去才行。

不过，直接将 `system/update_engine/scripts` 设置到 PATH 环境变量中是最方便的办法。

## 2. update_device.py 的帮助信息

update_device.py 工具自带的帮助信息：

```bash
android-13.0.0_r41$ update_device.py --help
usage: update_device.py [-h] [--file] [--no-push] [-s DEVICE] [--no-verbose] [--public-key PUBLIC_KEY] [--extra-headers EXTRA_HEADERS] [--secondary] [--no-slot-switch] [--no-postinstall] [--allocate-only] [--verify-only] [--no-care-map] [--perform-slot-switch] [--perform-reset-slot-switch] [--wipe-user-data] PAYLOAD

Android A/B OTA helper.

positional arguments:
  PAYLOAD               the OTA package file (a .zip file) or raw payload if device uses Omaha.

optional arguments:
  -h, --help            show this help message and exit
  --file                Push the file to the device before updating.
  --no-push             Skip the "push" command when using --file
  -s DEVICE             The specific device to use.
  --no-verbose          Less verbose output
  --public-key PUBLIC_KEY
                        Override the public key used to verify payload.
  --extra-headers EXTRA_HEADERS
                        Extra headers to pass to the device.
  --secondary           Update with the secondary payload in the package.
  --no-slot-switch      Do not perform slot switch after the update.
  --no-postinstall      Do not execute postinstall scripts after the update.
  --allocate-only       Allocate space for this OTA, instead of actually applying the OTA.
  --verify-only         Verify metadata then exit, instead of applying the OTA.
  --no-care-map         Do not push care_map.pb to device.
  --perform-slot-switch
                        Perform slot switch for this OTA package
  --perform-reset-slot-switch
                        Perform reset slot switch for this OTA package
  --wipe-user-data      Wipe userdata after installing OTA
```



```bash
http://127.0.0.1:1234/payload
```



## 3. update_device.py 的用法





## 4. 其它

- 到目前为止，我写过 Android OTA 升级相关的话题包括：
  - 基础入门：[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html)系列
  - 核心模块：[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html) 系列
  - 动态分区：[《Android 动态分区》](https://blog.csdn.net/guyongqiangx/category_12140166.html) 系列
  - 虚拟 A/B：[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列
  - 升级工具：[《Android OTA 相关工具》](https://blog.csdn.net/guyongqiangx/category_12211864.html)系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题，此群仅限专栏订阅者参与~

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。






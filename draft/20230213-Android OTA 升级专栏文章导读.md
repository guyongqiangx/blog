# Android OTA 升级专栏文章导读

[TOC]

从 2017 年起，我陆续写了一些 Android OTA 升级相关的文章，主要介绍从 Android 7.1 开始引入的 A/B 升级系统，包括从早前的 A/B 系统，到后来的动态分区，再到最近的虚拟 A/B 分区，以及最新的一些 Android OTA 话题。

> 毫不夸张的说，这是目前全网关于 Android OTA 升级最系统，最全面的专栏，没有之一。



从今年初开始，决定投入更多精力到 Android OTA 上来，我将详细分析 Android Q(10) 和 Android R(11) 的新特性，并在年内尽快跟踪到最新 Android 版本。

请原谅我将部分专栏从原来的免费改成了付费，因为每一篇文章我都投入了相当大的精力，每一篇都力图把问题的前因后果解释清楚，如果完全免费，实在没有动力更新。感谢您的理解和包容~~也十分感谢订阅的朋友们对我的支持和认可。

> 如果您已经订阅了付费专栏，请务必加我微信，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。
>
> 公众号“洛奇看世界”后台回复“wx”获取个人微信。



到目前为止，我写过 Android OTA 升级相关的文章包括以下几个系列：

- 基础入门：[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html) 系列
- 核心模块：[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html) 系列
- 动态分区：[《Android 动态分区》](https://blog.csdn.net/guyongqiangx/category_12140166.html) 系列
- 虚拟分区：[《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html) 系列
- 相关工具：《Android OTA 相关工具》系列

> 注：工具系列还在筹划中，后面会陆续更新，主要包括已有 Android OTA 相关工具的分析讨论，以及发布一些我自己写的 OTA 工具。



本文将这几个系列的所有文章汇总到本篇，并逐一加以说明，方便选择性阅读和系统学习。

本文主要分成两个部分：

- 第一部分是快速入口，提供了所有文章的链接，点击直接跳转;

- 第二部分对每一篇文章内容做一个简要介绍，可以根据需要，挑选感兴趣的话题进行阅读。

## 1. 快速入口

基础入门[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html) 系列，已完结。

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140293.html

- [Android A/B System OTA分析（一）概览](https://blog.csdn.net/guyongqiangx/article/details/71334889)

- [Android A/B System OTA分析（二）系统image的生成](https://blog.csdn.net/guyongqiangx/article/details/71516768)

- [Android A/B System OTA分析（三）主系统和bootloader的通信](https://blog.csdn.net/guyongqiangx/article/details/72480154)

- [Android A/B System OTA分析（四）系统的启动和升级](https://blog.csdn.net/guyongqiangx/article/details/72604355)

- [Android A/B System OTA分析（五）客户端参数](https://blog.csdn.net/guyongqiangx/article/details/122430246)

- [Android A/B System OTA分析（六）如何获取 payload 的 offset 和 size](https://blog.csdn.net/guyongqiangx/article/details/122498561)

  

核心代码[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html)系列，已完结。

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140296.html

- [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)

- [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)

- [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)

- [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)

- [Android Update Engine分析（五）服务端核心之Action机制](https://blog.csdn.net/guyongqiangx/article/details/82226079)

- [Android Update Engine分析（六）服务端核心之Action详解](https://blog.csdn.net/guyongqiangx/article/details/82390015)

- [Android Update Engine分析（七） DownloadAction之FileWriter](https://blog.csdn.net/guyongqiangx/article/details/82805813)

- [Android Update Engine分析（八）升级包制作脚本分析](https://blog.csdn.net/guyongqiangx/article/details/82871409)

- [Android Update Engine分析（九） delta_generator 工具的 6 种操作](https://blog.csdn.net/guyongqiangx/article/details/122351084)

- [Android Update Engine分析（十） 生成 payload 和 metadata 的哈希](https://blog.csdn.net/guyongqiangx/article/details/122393172)

- [Android Update Engine分析（十一） 更新 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122597314)

- [Android Update Engine 分析（十二） 验证 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122634221)

- [Android Update Engine分析（十三） 提取 payload 的 property 数据](https://blog.csdn.net/guyongqiangx/article/details/122646107)

- [Android Update Engine分析（十四） 生成 payload 数据](https://blog.csdn.net/guyongqiangx/article/details/122753185)

- [Android Update Engine 分析（十五） FullUpdateGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122767273)

- [Android Update Engine 分析（十六） ABGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122886150)

- [Android Update Engine 分析（十七）10 类 InstallOperation 数据的生成和应用](https://blog.csdn.net/guyongqiangx/article/details/122942628)

  

动态分区[《Android 动态分区》](https://blog.csdn.net/guyongqiangx/category_12140166.html) 系列，更新中。

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140166.html

- [Android 动态分区详解(一) 5 张图让你搞懂动态分区原理](https://blog.csdn.net/guyongqiangx/article/details/123899602)

- [Android 动态分区详解(二) 核心模块和相关工具介绍](https://blog.csdn.net/guyongqiangx/article/details/123931356)

- [Android 动态分区详解(三) 动态分区配置及super.img的生成](https://blog.csdn.net/guyongqiangx/article/details/124052932)

- [Android 动态分区详解(四) OTA 中对动态分区的处理](https://blog.csdn.net/guyongqiangx/article/details/124224206)

- [Android 动态分区详解(五) 为什么没有生成 super.img?](https://blog.csdn.net/guyongqiangx/article/details/128005251)

- [Android 动态分区详解(六) 动态分区的底层机制](https://blog.csdn.net/guyongqiangx/article/details/128305482)

- [Android 动态分区详解(七) overlayfs 与 adb remount 操作](https://blog.csdn.net/guyongqiangx/article/details/128881282)



虚拟 A/B [《Android 虚拟 A/B 分区》](https://blog.csdn.net/guyongqiangx/category_12121868.html)系列，更新中。

专栏地址：https://blog.csdn.net/guyongqiangx/category_12121868.html

- [Android 虚拟分区详解(一) 参考资料推荐](https://blog.csdn.net/guyongqiangx/article/details/128071692)

- [Android 虚拟分区详解(二) 虚拟分区布局](https://blog.csdn.net/guyongqiangx/article/details/128167054)

- [Android 虚拟分区详解(三) 分区状态变化](https://blog.csdn.net/guyongqiangx/article/details/128517578)

- [Android 虚拟分区详解(四) 编译开关](https://blog.csdn.net/guyongqiangx/article/details/128567582)

- [Android 虚拟分区详解(五) BootControl 接口的变化](https://blog.csdn.net/guyongqiangx/article/details/128824984)



升级工具《Android OTA 相关工具》系列，待更新。



其它文章

- [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)

- [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)



## 2. 简要介绍

### 1. 基础入门：《Android A/B 系统》系列

[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html) 系列作为整个 A/B 系统的入门系列，如果你以前没有接触过 Android 的 A/B 系统，建议先阅读本专栏的文章，对 A/B 系统有个大致的了解。

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140293.html



- [Android A/B System OTA分析（一）概览](https://blog.csdn.net/guyongqiangx/article/details/71334889)

  链接：https://blog.csdn.net/guyongqiangx/article/details/71334889

  主要介绍了:

  - 什么是 A/B 系统
  - A/B 系统的分区
  - A/B 系统的状态和
  - A/B 系统的升级切换

  

- [Android A/B System OTA分析（二）系统image的生成](https://blog.csdn.net/guyongqiangx/article/details/71516768)

  链接：https://blog.csdn.net/guyongqiangx/article/details/71516768

  基于 AOSP 7.1.1_r23 介绍了:

  - A/B 系统镜像和传统 OTA 升级方式下镜像内容的区别
  - A/B 系统相关的 Makefile 变量
  - A/B 系统镜像文件的生成，包括 recovery.img, boot.img, system.img, userdata.img, cache.img, vendor.img



- [Android A/B System OTA分析（三）主系统和bootloader的通信](https://blog.csdn.net/guyongqiangx/article/details/72480154)

  链接：https://blog.csdn.net/guyongqiangx/article/details/72480154

  主要介绍了：

  - 传统 OTA 升级时 Android 主系统是如何同 bootloder 通信的

  - 详细分析了 A/B 系统中 Android 主系统同 bootloader 通信的 boot_control HAL 接口

    - boot_control 的接口定义和实现

      - Google 平台 Brillo 的实现
      - Intel 平台 edison 的实现
      - QualComm 平台的实现
      - Broadcom 机顶盒平台的实现

    - boot_control 的测试工具 bootctl

    - boot_control 的调用

      - bootloader 调用 boot_control

      - Android 主系统 boot_control_android 调用 boot_control

      - update_verifier 调用 boot_control

        

- [Android A/B System OTA分析（四）系统的启动和升级](https://blog.csdn.net/guyongqiangx/article/details/72604355)

  链接：https://blog.csdn.net/guyongqiangx/article/details/72604355

  主要介绍了：

  - bootloader 读取并检查 boot_control 的流程
  - linux 系统是如何启动并挂在 Android 系统分区的
  - Android 主系统和 recovery 系统是如何启动的
  - A/B 系统升级包的制作
    - 全量包的制作
    - 增量包/差分包的制作
  - Update Engine 的升级样本日志

  

- [Android A/B System OTA分析（五）客户端参数](https://blog.csdn.net/guyongqiangx/article/details/122430246)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122430246

  主要介绍了：

  - update_engine_client 客户端支持的参数

  - update_engine_client 客户段的参数是如何解析并传递给 update engine 服务的

  - 如何使用远程文件和本地文件进行升级

  - 如何设置升级时的 offset 和 size 参数

    

- [Android A/B System OTA分析（六）如何获取 payload 的 offset 和 size](https://blog.csdn.net/guyongqiangx/article/details/122498561)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122498561

  主要介绍了：

  - zip 文件的格式
  - 获取 A/B 系统升级包 update.zip 中 payload.bin 的 offset 和 size 的 3 种方式
    - Android O 开始自动生成 offset 和 size 数据
    - 使用 zipinfo 手动计算 offset 和 size 数据
    - 使用 zip_info.py 脚本工具计算 offset 和 size 数据

  

### 2. 核心模块：《Android Update Engine 分析》系列

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140296.html



- [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)

链接：https://blog.csdn.net/guyongqiangx/article/details/77650362

- [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)

链接：https://blog.csdn.net/guyongqiangx/article/details/80819901

- [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)

链接：https://blog.csdn.net/guyongqiangx/article/details/80820399

- [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)

链接：https://blog.csdn.net/guyongqiangx/article/details/82116213

- [Android Update Engine分析（五）服务端核心之Action机制](https://blog.csdn.net/guyongqiangx/article/details/82226079)

链接：https://blog.csdn.net/guyongqiangx/article/details/82226079

- [Android Update Engine分析（六）服务端核心之Action详解](https://blog.csdn.net/guyongqiangx/article/details/82390015)

链接：https://blog.csdn.net/guyongqiangx/article/details/82390015

- [Android Update Engine分析（七） DownloadAction之FileWriter](https://blog.csdn.net/guyongqiangx/article/details/82805813)

链接：https://blog.csdn.net/guyongqiangx/article/details/82805813

- [Android Update Engine分析（八）升级包制作脚本分析](https://blog.csdn.net/guyongqiangx/article/details/82871409)

链接：https://blog.csdn.net/guyongqiangx/article/details/82871409

- [Android Update Engine分析（九） delta_generator 工具的 6 种操作](https://blog.csdn.net/guyongqiangx/article/details/122351084)

链接：https://blog.csdn.net/guyongqiangx/article/details/122351084

- [Android Update Engine分析（十） 生成 payload 和 metadata 的哈希](https://blog.csdn.net/guyongqiangx/article/details/122393172)

链接：https://blog.csdn.net/guyongqiangx/article/details/122393172

- [Android Update Engine分析（十一） 更新 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122597314)

链接：https://blog.csdn.net/guyongqiangx/article/details/122597314

- [Android Update Engine 分析（十二） 验证 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122634221)

链接：https://blog.csdn.net/guyongqiangx/article/details/122634221

- [Android Update Engine分析（十三） 提取 payload 的 property 数据](https://blog.csdn.net/guyongqiangx/article/details/122646107)

链接：https://blog.csdn.net/guyongqiangx/article/details/122646107

- [Android Update Engine分析（十四） 生成 payload 数据](https://blog.csdn.net/guyongqiangx/article/details/122753185)

链接：https://blog.csdn.net/guyongqiangx/article/details/122753185

- [Android Update Engine 分析（十五） FullUpdateGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122767273)

链接：https://blog.csdn.net/guyongqiangx/article/details/122767273

- [Android Update Engine 分析（十六） ABGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122886150)

链接：https://blog.csdn.net/guyongqiangx/article/details/122886150

- [Android Update Engine 分析（十七）10 类 InstallOperation 数据的生成和应用](https://blog.csdn.net/guyongqiangx/article/details/122942628)

链接：https://blog.csdn.net/guyongqiangx/article/details/122942628



### 3. 动态分区：《Android 动态分区》 系列

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140166.html



- [Android 动态分区详解(一) 5 张图让你搞懂动态分区原理](https://blog.csdn.net/guyongqiangx/article/details/123899602)

链接：https://blog.csdn.net/guyongqiangx/article/details/123899602

- [Android 动态分区详解(二) 核心模块和相关工具介绍](https://blog.csdn.net/guyongqiangx/article/details/123931356)

链接：https://blog.csdn.net/guyongqiangx/article/details/123931356

- [Android 动态分区详解(三) 动态分区配置及super.img的生成](https://blog.csdn.net/guyongqiangx/article/details/124052932)

链接：https://blog.csdn.net/guyongqiangx/article/details/124052932

- [Android 动态分区详解(四) OTA 中对动态分区的处理](https://blog.csdn.net/guyongqiangx/article/details/124224206)

链接：https://blog.csdn.net/guyongqiangx/article/details/124224206

- [Android 动态分区详解(五) 为什么没有生成 super.img?](https://blog.csdn.net/guyongqiangx/article/details/128005251)

链接：https://blog.csdn.net/guyongqiangx/article/details/128005251

- [Android 动态分区详解(六) 动态分区的底层机制](https://blog.csdn.net/guyongqiangx/article/details/128305482)

链接：https://blog.csdn.net/guyongqiangx/article/details/128305482

- [Android 动态分区详解(七) overlayfs 与 adb remount 操作](https://blog.csdn.net/guyongqiangx/article/details/128881282)

链接：https://blog.csdn.net/guyongqiangx/article/details/128881282



### 4. 虚拟分区：《Android 虚拟 A/B 分区》系列

专栏地址：https://blog.csdn.net/guyongqiangx/category_12121868.html



- [Android 虚拟分区详解(一) 参考资料推荐](https://blog.csdn.net/guyongqiangx/article/details/128071692)

链接：https://blog.csdn.net/guyongqiangx/article/details/128071692

- [Android 虚拟分区详解(二) 虚拟分区布局](https://blog.csdn.net/guyongqiangx/article/details/128167054)

链接：https://blog.csdn.net/guyongqiangx/article/details/128167054

- [Android 虚拟分区详解(三) 分区状态变化](https://blog.csdn.net/guyongqiangx/article/details/128517578)

链接：https://blog.csdn.net/guyongqiangx/article/details/128517578

- [Android 虚拟分区详解(四) 编译开关](https://blog.csdn.net/guyongqiangx/article/details/128567582)

链接：https://blog.csdn.net/guyongqiangx/article/details/128567582

- [Android 虚拟分区详解(五) BootControl 接口的变化](https://blog.csdn.net/guyongqiangx/article/details/128824984)

链接：https://blog.csdn.net/guyongqiangx/article/details/128824984



### 5. 升级工具：《Android OTA 相关工具》系列



### 6. 其它文章

- [Linux 快照 (snapshot) 原理与实践(一) 快照基本原理](https://blog.csdn.net/guyongqiangx/article/details/128494795)

链接：https://blog.csdn.net/guyongqiangx/article/details/128494795

- [Linux 快照 (snapshot) 原理与实践(二) 快照功能实践](https://blog.csdn.net/guyongqiangx/article/details/128496471)

链接：https://blog.csdn.net/guyongqiangx/article/details/128496471



## 3. 其它

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题。

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。
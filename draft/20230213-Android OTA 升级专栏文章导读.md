# Android OTA 升级系列专栏文章导读

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

[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html) 系列基于 A/B 系统早期的代码 AOSP 7.1.1_r23，尽管代码版本比较老了，一部分内容在 Android 10(Q) 引入动态分区后不再适用，但大部分内容或操作在 Android 11(R) 以后仍然具有参考价值。 

作为整个 A/B 系统的入门系列，如果你以前没有接触过 Android 的 A/B 系统，建议先阅读本专栏的文章，对 A/B 系统有个大致的了解。

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

  主要介绍了:

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

[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html) 系列基于 A/B 系统早期的代码 AOSP 7.1.1_r23，尽管代码版本比较老了，Update Engine 分区处理部分的内容在 Android 9(P), Andrid 10(Q) 和 Android 11(R) 以及后续陆续有更新，但 Update Engine 本身的核心流程并没有什么变化，所以即使您基于动态分区或虚拟 A/B 的 Android 版本工作，但 Update Engine 核心流程仍然具有参考价值，相对于最新代码来说，A/B 系统早期的代码更简单，更易于理解。

例如，整个 A/B 系统，编译打包，使用 Update Engine Client 进行更新，Update Engine Service 接收数据，解析 payload 并将数据写入分区的总体操作在 Android 10(Q) 和 Android 11(R) 上仍然一样。



不同的是，Android 10(Q) 在接收完 payload 的 manifest 开始更新时，动态分区会先使用 manifest 中的数据更新 super 设备头部动态分区的分区表(lpmetadata)，分区表更新完以后，根据分区表中的数据将 super 设备的某些部分映射成另外一个槽位，然后基于这两个槽位进行和以前一样的更新。



对于 Android 11(R) 开始的虚拟 A/B 系统，在接收完 payload 的 manifest 开始更新时，虚拟 A/B 分区会先使用 manifest 中的数据更新 super 设备头部动态分区的分区表(lpmetadata)，然后从 super 设备的空闲区域，或者从 data 分区中分配空间用于构建和映射另外一个槽位。

因此，和动态分区不同的是，虚拟 A/B 的另外一个槽位在系统中并不存在(动态分区时是真实存在的)，是通过 super 设备的空闲空间，或 data 分区的文件映射出来的，这就是为什么被称为虚拟 A/B 的原因，因为设备上真正存在的只有一套。

虚拟设备映射好以后，系统基于一个真实的槽位和一个虚拟的槽位进行和以前的 A/B 系统一样的更新。更新完成后，系统重启并从虚拟的槽位启动，如果虚拟槽位启动成功，则开始将虚拟槽位的数据合并(merge)到真实槽位中。如果虚拟槽位启动失败，则系统回退到真实槽位中。



所以，除了对分区的处理不同之外(虚拟 A/B 还会有一个合并 merge 操作)，Update Engine 的流程从 Android 7(N) 到最新的版本，核心流程基本上都差不多。

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140296.html



- [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)

  链接：https://blog.csdn.net/guyongqiangx/article/details/77650362

  这篇文章主要基于 Android 7.1.1 的代码逐行分析了 Update Engine 的 Makefile 文件，从而得到整个 update engine 代码的模块结构，包括生成了哪些库和可执行文件，有哪些可以用的调试工具等。

  在 Android 10(Q) 中，Update Engine 模块的 Android.mk 被 Androi.bp 取代，原来对 Android.mk 的分析不再适用，但依然建议你按照我的思路去阅读 Androi.bp 文件来了解整个 Update Engine 的模块结构。

  

- [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)

  链接：https://blog.csdn.net/guyongqiangx/article/details/80819901

  主要介绍了：

  - 描述 payload 结构的 update_metadata.proto 文件，后续在 Android 10(Q) 的动态分区引入前，这个文件有些小更新，但重点变化不大。
  - 描述 Update Engine 服务接口的 IUpdateEngine.aidl 文件，并基于接口编译出来的文件分析了 Update Engine 的 binder 服务和接口见的层次关系。

  关于 AIDL 如何编译转化，以及和 binder 服务的实现关系比较复杂了，我个人认为没有只要知道大概是如何关联即可，没有必要投入太多时间到这部分。

  

- [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)

  链接：https://blog.csdn.net/guyongqiangx/article/details/80820399

  主要围绕 Update Engine 的客户端进行 update_engine_client 进行分析，包括：

  - update_engine_client 文件的依赖关系

  - update_eingine_client 的参数处理

    - 如何解析命令行参数

    - 如何处理 suspend, resume, cancel, reset_status, follow, update 等操作，并进一步调用 Update Engine Service 服务

      

- [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)

  链接：https://blog.csdn.net/guyongqiangx/article/details/82116213

  主要围绕 Update Engine 服务端进程 update_engine 进行分析，包括：

  - Update Engine 服务端文件的依赖关系
  - 入口文件 main.cc 逐行分析
  - update_engine_daemon 是如何初始化，并创建出 binder 服务的
  - Update Engine 是如何实现回调通知的

  

- [Android Update Engine分析（五）服务端核心之Action机制](https://blog.csdn.net/guyongqiangx/article/details/82226079)

  链接：https://blog.csdn.net/guyongqiangx/article/details/82226079

  主要介绍了：

  - Action 机制的构成模块，包括 Action, Action Processor 和 Action Pipe
  - 分析了 Action 机制的处理操作，包括开始和停止处理，暂停和恢复处理，结束的收尾工作
  - 多个 Action 的层次关系
    - AbstractAction, Action
    - InstallPlanAction, DownloadAction, FilesystemVerifierAction, PostinstallRunnerAction
  - ApplyPayload 收到升级请求后，如何构建 ActionPipe 并开始升级
  - suspend, resume, cancel 和 resetStatus 等操作是如何创建 Action 并执行的

  

- [Android Update Engine分析（六）服务端核心之Action详解](https://blog.csdn.net/guyongqiangx/article/details/82390015)

  链接：https://blog.csdn.net/guyongqiangx/article/details/82390015

  详细分析了 Update Engine 的 4 个核心 Action 的实现代码：

  - InstallPlanAction

  - DownloadAction

  - FilesystemVerifierAction

  - PostinstallRunnerAction

    

- [Android Update Engine分析（七） DownloadAction之FileWriter](https://blog.csdn.net/guyongqiangx/article/details/82805813)

  链接：https://blog.csdn.net/guyongqiangx/article/details/82805813

  进一步详细分析了 DownloadAction 操作，其中的 FileWrite 是整个升级写入数据的核心：

  - DownloadAction 何时写入接收到的数据？
  - Payload 文件的详细结构
  - 接收到的升级数据到底是如何写入的？(DeltaPerformer 的 Write 操作)
    - 如何更新数据接收进度信息？
    - 如何解析升级包的头部数据，得到 DeltaArchiveManifest 数据？
    - 如何校验签名？
    - 如从 DeltaArchiveManifest 中提取分区信息？
    - 如何更新升级状态信息？
    - 如何提取各分区的InstallOperation，并检查payload数据的hash？
    - 详细执行 InstallOperation 的更新操作
    - 如何提取升级数据的signature？

  这部分的代码位于函数 `DeltaPerformer::Write()`, 对于这个函数的重要性，无论如何强调都不过分。所以这一篇是整个 Update Engine 的重中之重，值得反复阅读。

  后面的动态分区和虚拟 A/B 的很多变化就位于 `Write()`的处理流程中。

  到这篇为止，Android 设备上的流程分析完了。

  

- [Android Update Engine分析（八）升级包制作脚本分析](https://blog.csdn.net/guyongqiangx/article/details/82871409)

  链接：https://blog.csdn.net/guyongqiangx/article/details/82871409

  主要介绍了：

  - 如何制作全量和增量升级包？
  - 逐行分析升级包制作工具 ota_from_target_files
  - 逐行分析 payload 生成脚本 brillo_update_payload
    - 如何生成 payload 文件
    - 如何生成 payload 数据和 metadata 数据的哈希
    - 如何将 payload 和 metadata 的签名写回 payload 文件
    - 如何提取 payload 文件的 properties 数据

  如果想了解详细的升级包制作过程，这一篇建议详细阅读。并在文章的最后总结了使用 delta_generator 生成 payload 的命令行步骤。

  

- [Android Update Engine分析（九） delta_generator 工具的 6 种操作](https://blog.csdn.net/guyongqiangx/article/details/122351084)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122351084

  主要介绍了编译时生成差分数据的 delta_generator 工具：

  - 回顾使用 delta_genertor 生成 payload 文件的步骤
  - delta_generator 的主程序源码分析
  - delta_generator 支持的 6 种操作

  

- [Android Update Engine分析（十） 生成 payload 和 metadata 的哈希](https://blog.csdn.net/guyongqiangx/article/details/122393172)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122393172

  主要介绍了 delta_generator 是如何生成 payload 和 metadata 哈希的：

  - 如何计算 payload 和 metadata 的哈希
  - 如何将计算得到的哈希写回 payload 文件
  - 如何手动在命令行计算 payload 和 metadata 的哈希
  - 如何手动解析 payload 的头部数据
  - 如何手动计算并验证 payload 的哈希

  

- [Android Update Engine分析（十一） 更新 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122597314)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122597314

  主要介绍了：

  - 总结 payload 数据的生成和处理

  - 如何更新 payload 文件签名

    

- [Android Update Engine 分析（十二） 验证 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122634221)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122634221

  主要介绍了：

  - 如何生成验证使用的公钥

  - 如何使用公钥验证 payload 签名

  - payload 的签名验证流程

  - 如何手动使用命令行工具验证签名

  - 如何使用 protobuf 工具还原 metadata 签名数据

    

- [Android Update Engine分析（十三） 提取 payload 的 property 数据](https://blog.csdn.net/guyongqiangx/article/details/122646107)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122646107

  主要介绍了：

  - delta_generator 如何从 payload 中提取 properties 数据
  - 如何手动提取 payload 的属性数据

  

- [Android Update Engine分析（十四） 生成 payload 数据](https://blog.csdn.net/guyongqiangx/article/details/122753185)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122753185

  主要介绍了：

  - 回顾了 payload 生成的流程
  - delta_generator 生成 payload 的源码分析
  - 介绍了生成 payload 数据的 payload_config 结构
  - payload 数据最终是如何组装的？



- [Android Update Engine 分析（十五） FullUpdateGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122767273)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122767273

  主要介绍了全量包的生成策略以及整个调用流程。

  

- [Android Update Engine 分析（十六） ABGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122886150)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122886150

  主要介绍了差分包的生成策略以及调用流程，想对于全量包的策略，差分包的生成流程较为复杂，建议跟着文章详细阅读源代码。

  

- [Android Update Engine 分析（十七）10 类 InstallOperation 数据的生成和应用](https://blog.csdn.net/guyongqiangx/article/details/122942628)

  链接：https://blog.csdn.net/guyongqiangx/article/details/122942628

  详细分析了 payload 文件中用于升级数据生成和写入的 10 种操作：

  - ZERO, REPLACE_XZ, REPLACE_BZ 和 REPLACE 操作
  - REPLACE_XZ, REPLACE_BZ 和 REPLACE 操作
  - ZERO 操作
  - DISCARD 操作
  - MOVE 和 SOURCE_COPY 操作
  - BSDIFF 和 SOURCE_BSDIFF 操作以及 IMGDIFF 操作



### 3. 动态分区：《Android 动态分区》 系列

Android A/B 系统从 Android 10(Q) 开始引入动态分区，原来的 A/B 系统两个槽位内的各个分区都是预先分配好，大小固定大小。在支持动态分区以后，A/B 系统两个槽位包含在 super 设备上，A/B 系统的槽位分区表信息由 super 设备头部的 LpMetadata 数据表述。这样的一个好处就是槽位内分区大小可以动态调整，带来的问题就是在升级时需要处理 super 设备上的分区表信息，系统启动时也需要正确解析 super 设备上的分区并进行加载。

[《Android 动态分区》](https://blog.csdn.net/guyongqiangx/category_12140166.html)系列在[《Android A/B 系统》](https://blog.csdn.net/guyongqiangx/category_12140293.html) 和 [《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html) 系列的基础上，基于 android-10.0.0_r47 代码，主要聚焦于 A/B 系统引入动态分区以后的改动。

专栏地址：https://blog.csdn.net/guyongqiangx/category_12140166.html



- [Android 动态分区详解(一) 5 张图让你搞懂动态分区原理](https://blog.csdn.net/guyongqiangx/article/details/123899602)

  链接：https://blog.csdn.net/guyongqiangx/article/details/123899602

  主要介绍了：

  - 动态分区的本质就是围绕分区表数据 LpMetadata 的增删改查
  - 支持动态分区的 device mapper 机制的原理
  - Android 动态分区和描述数据 LpMetadata 的布局
    - 宏观：super 分区
    - 中观：metadata 数据
    - 微观：gemoetry 和 metadata 的数据结构
  - 动态分区的核心数据结构 LpMetadata
  - 提供了一个 Android 动态分区映射的示例
  - super.img 的编译和生成
  - super.img 的解析
  - super.img 的映射

  如果希望通过一篇大致了解动态分区组成的基本原理，那读这一篇就够了。

  

- [Android 动态分区详解(二) 核心模块和相关工具介绍](https://blog.csdn.net/guyongqiangx/article/details/123931356)

  链接：https://blog.csdn.net/guyongqiangx/article/details/123931356

  主要介绍了：

  - 动态分区相关的核心模块
    - liblp (logic partition lib)
    - libdm (device mapper lib)
    - libfs_mgr (filesystem manager lib)
    - libsparse (sparse image lib)
  - 动态分区相关调试工具
    - lpmake, lpdump, lpflash, lpunpack
    - dmctl, dmuserd
    - simg2img, img2simg, append2simg, simg_dump.py

  如果希望在调试动态分区或查看动态分区信息，lpdump 和 dmctl 是最常用的工具。

  

- [Android 动态分区详解(三) 动态分区配置及super.img的生成](https://blog.csdn.net/guyongqiangx/article/details/124052932)

  链接：https://blog.csdn.net/guyongqiangx/article/details/124052932

  主要介绍了：

  - 动态分区的配置选项开关，包括原生动态分区的配置和改造 (retrofit) 动态分区的配置
  - 动态分区的配置示例分析
    -  crosshatch (Pixel 3 XL)
    - bonito (Pixel 3a XL)
    - 模拟器 cuttlefish
  - 动态分区的参数检查
  - Makefile 中动态分区的参数处理和追踪
    - 动态分区相关参数最终到底设置在哪里？
  - 原生动态分区 super.img 的编译生成分析
    - dist 模式的 super.img
    - debug 模式的 super.img
    - super_empty.img
    - build_super_image.py 脚本分析

  如果不清楚动态分区要如何配置，这些配置又是如何生效的，请参考本篇的分析。

  

- [Android 动态分区详解(四) OTA 中对动态分区的处理](https://blog.csdn.net/guyongqiangx/article/details/124224206)

  链接：https://blog.csdn.net/guyongqiangx/article/details/124224206

  主要介绍了：

  - payload 中的动态分区数据分析
  - 如何制作动态分区的升级包
  - 制作升级包时
    - 如何打包动态分区数据
    - 动态分区数据如何输出到 payload 文件中
    - 动态分区数据的打包流程
  - 更新升级时
    - 如何处理接收到的 manifest 数据
    - 如何更新 super 设备的动态分区数据
    - 动态分区的更新和映射流程

  这一篇主要集中于制作升级包时，动态分区信息如何输出到 payload 文件；更新升级时又是如何从 payload 中解析动态分区信息并用于动态分区升级的。

  

- [Android 动态分区详解(五) 为什么没有生成 super.img?](https://blog.csdn.net/guyongqiangx/article/details/128005251)

  链接：https://blog.csdn.net/guyongqiangx/article/details/128005251

  主要介绍了编译 AOSP 参考设备时，明明打开了动态分区，但为什么会没有生成 super.img

  

- [Android 动态分区详解(六) 动态分区的底层机制](https://blog.csdn.net/guyongqiangx/article/details/128305482)

  链接：https://blog.csdn.net/guyongqiangx/article/details/128305482

  主要介绍了：

  - 动态分区的两重含义，用户态下的动态分区
  - device mapper 原理
  - 作为动态分区基础的 linear 设备映射原理
    - 手动进行分区 linear 设备映射的示例
  - dmsetup create 参数解释
  - 手动使用 dmsetup 工具对 super 设备进行映射

  主要是通过一些 linux 命令行工具来模拟动态分区映射，加深对动态分区机制的理解。

  

- [Android 动态分区详解(七) overlayfs 与 adb remount 操作](https://blog.csdn.net/guyongqiangx/article/details/128881282)

  链接：https://blog.csdn.net/guyongqiangx/article/details/128881282

  主要介绍了：

  - overlayfs 的底层原理
  - Linux 下如何编译配置 overlayfs，以及运行时如何检查 overlayfs
  - Android 系统中为什么引入 overlayfs
  - Andnroid 上关闭 dm-verity，执行 remount 的流程
  - Android 上打开 dm-verity，执行 unmuount 的流程
  - Android 中执行 remount 后引起的 OTA 升级问题
    - adb remount之后，OTA 升级失败
    - adb remount 分区，导致 OTA 升级 super 分区 resize fail

  主要针对 OTA 讨论群中经常问到的 remount 后引起一些列问题的分析和总结。



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
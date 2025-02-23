# 20241202-Android AVB 分析（二）AVB 2.0 自述文档(强哥注释版)



本文基于 AVB 自述 REAME.md 文档 v1.3 版，时间戳为：20250118



原来的第二篇打算是汇总下我所知道的 AVB 相关的资料。所以我一开始并没有打算要翻译这个 Android 自带的 AVB 2.0 自述文档，因为网上已经有很多篇这个文档了，简直不计其数。



但是 AVB 自述文档 (platform/external/avb/README.md) 又实在是太重要了，所以如果只推荐一篇文档的话，那肯定就是官方这篇。



所以，我这里也不免俗，将最新的 Android Verified Boot 2.0 最新的文档(2025/01/18) 翻译在这里，并附上我的部分解读。



如果你希望深入学习 Android AVB 的细节，那这篇文章建议你至少阅读 10 遍。不是那种一口气反复阅读 10 遍，而是先阅读遍，有个大概印象，然后去阅读代码，再回来阅读文档。也就是文档和代码交替阅读来增强对 AVB 的学习。



另外，除了阅读翻译后的本文之外，我也建议你对比英文原文以加深理解。因为有些东西，英语表述经过翻译之后内容就会变得奇奇怪怪的。例如，在我看来 bootloader 这样的词本身很清楚，就是指类似 u-boot 这样的一个启动加载程序，但有些文档中翻译成“启动器”或者“启动加载器”有，又或者“引导加载程序”(这个最常见)。说实话，从字面意思看，这些翻译一点问题没有，但对我自己而言，如果只看到“启动加载器”，真的要反应一会儿才能和 bootloader 这个每天都要接触的词语联系在一起。



#  Android 验证启动 2.0

------

此仓库包含用于处理 Android 验证启动 2.0 (Android Verified Boot 2.0)的工具和库。通常，AVB 用于指代此代码。

> 强哥注：
>
> - 本地代码: `platform/external/avb`
> - 远程代码: https://android.googlesource.com/platform/external/avb

#  目录

-  这是什么？
  - [ VBMeta 结构](https://android.googlesource.com/platform/external/avb/+/main/README.md#the-vbmeta-struct)
  - [ 回滚保护](https://android.googlesource.com/platform/external/avb/+/main/README.md#rollback-Protection)
  - [ A/B 支持](https://android.googlesource.com/platform/external/avb/+/main/README.md#a_b-Support)
  - [ VBMeta 摘要](https://android.googlesource.com/platform/external/avb/+/main/README.md#the-vbmeta-digest)
-  工具和库
  - [ avbtool 和 libavb](https://android.googlesource.com/platform/external/avb/+/main/README.md#avbtool-and-libavb)
  - [ 文件和目录](https://android.googlesource.com/platform/external/avb/+/main/README.md#files-and-directories)
  - [ 便携性](https://android.googlesource.com/platform/external/avb/+/main/README.md#portability)
  - [版本和兼容性](https://android.googlesource.com/platform/external/avb/+/main/README.md#versioning-and-compatibility)
  - [ 添加新功能](https://android.googlesource.com/platform/external/avb/+/main/README.md#adding-new-features)
  - [ 使用 avbtool](https://android.googlesource.com/platform/external/avb/+/main/README.md#using-avbtool)
  - [构建系统集成](https://android.googlesource.com/platform/external/avb/+/main/README.md#build-system-integration)
-  设备集成
  - [ 系统依赖](https://android.googlesource.com/platform/external/avb/+/main/README.md#system-dependencies)
  - [锁定和解锁模式](https://android.googlesource.com/platform/external/avb/+/main/README.md#locked-and-unlocked-mode)
  - [ 防篡改存储](https://android.googlesource.com/platform/external/avb/+/main/README.md#tamper_evident-storage)
  - [ 命名持久值](https://android.googlesource.com/platform/external/avb/+/main/README.md#named-persistent-values)
  - [ 持久性摘要](https://android.googlesource.com/platform/external/avb/+/main/README.md#persistent-digests)
  - [更新存储的回滚索引](https://android.googlesource.com/platform/external/avb/+/main/README.md#updating-stored-rollback-indexes)
  -  推荐引导流程
    - [ 启动到恢复模式](https://android.googlesource.com/platform/external/avb/+/main/README.md#booting-into-recovery)
  - [处理 dm-verity 错误](https://android.googlesource.com/platform/external/avb/+/main/README.md#handling-dm_verity-errors)
  - [安卓特定集成](https://android.googlesource.com/platform/external/avb/+/main/README.md#android-specific-integration)
  - [ 设备特定说明](https://android.googlesource.com/platform/external/avb/+/main/README.md#device-specific-notes)
- [ 版本历史](https://android.googlesource.com/platform/external/avb/+/main/README.md#version-history)

# 这是什么？

验证启动是确保设备上运行的软件完整性的过程。它通常从设备的只读固件部分开始，该部分加载代码并在通过密码学验证代码是真实且没有已知安全漏洞后执行它。AVB 是验证启动的一种实现。

> 强哥注：
>
> 这段话主要强调的是系统启动时建立的安全信任链，例如：固化在芯片内部只读存储区域的安全固件验证 bootloader，然后通过 bootloader 验证 kernel，再在 kernel 中验证应用。通过这样的上一级代码验证下一级代码，逐级验证保证了整个启动环境都是经过认证和安全的，也就是所谓的启动验证(或者说验证过的启动)。
>
> 这里主要强调 Android 的 AVB 其实只是这种验证启动的其中一种实现。

## VBMeta 结构

AVB 中使用的中心数据结构是 VBMeta 结构。此数据结构包含多个描述符（以及其他元数据），所有这些数据都是经过加密签名的。描述符用于图像哈希、图像哈希树元数据和所谓的链式分区。一个简单的例子如下：

![AVB with boot, system, and vendor](./images-20241202-Android AVB 分析（二）AVB 2.0 自述文档(v1.3 版-20250118)/avb-integrity-data-in-vbmeta.png)

`vbmeta` 分区存储了哈希描述符中 `boot` 分区的哈希值。对于 `system` 和 `vendor` 分区，哈希树跟随文件系统数据， `vbmeta` 分区存储了哈希树的根哈希、随机盐和偏移量。因为 `vbmeta` 分区中的 VBMeta 结构是经过加密签名的，引导加载程序可以检查签名并验证它是由 `key0` （例如，通过嵌入 `key0` 的公钥部分）的拥有者制作的，从而信任用于 `boot` 、 `system` 和 `vendor` 的哈希值。

链式分区描述符用于委派权限 - 它包含委派权限的分区名称以及用于此特定分区签名的受信任公钥。例如，考虑以下设置：

![AVB with a chained partition](./images-20241202-Android AVB 分析（二）AVB 2.0 自述文档(v1.3 版-20250118)/avb-chained-partition.png)

在这个配置中， `xyz` 分区有一个用于完整性检查的哈希树。哈希树之后是一个 VBMeta 结构，其中包含哈希树描述符和哈希树元数据（根哈希、随机盐、偏移量等），并且这个结构用 `key1` 签名。最后，在分区的末尾是一个包含 VBMeta 结构偏移量的页脚。

此设置允许引导加载程序使用链式分区描述符在分区末尾找到页脚（使用链式分区描述符中的名称），这反过来有助于定位 VBMeta 结构并验证它是否由 `key1` 签名（使用存储在链式分区描述符中的 `key1_pub` ）。关键的是，因为有带有偏移量的页脚，可以更新 `xyz` 分区，而无需对 `vbmeta` 分区进行任何更改。

VBMeta 结构足够灵活，允许任何分区的哈希描述符和哈希树描述符存在于 `vbmeta` 分区中，即它们用于完整性检查（通过链分区描述符）的分区，或任何其他分区（通过链分区描述符）。这允许广泛的组织和管理关系。

链式分区无需使用页脚 - 链式分区可以指向 VBMeta 结构位于起始位置的分区（例如，就像 `vbmeta` 分区一样）。这在所有由整个组织拥有的分区的哈希和哈希树描述符都存储在专用分区中的用例中很有用，例如 `vbmeta_google` 。在这个例子中， `system` 的哈希树描述符位于 `vbmeta_google` 分区，这意味着引导加载程序根本不需要访问 `system` 分区，这对于如果 `system` 分区作为逻辑分区（例如通过 LVM 技术或类似技术）进行管理非常有帮助。

> 强哥注：
>
> 我好几年前刚接触 AVB 时看了这段话，当时完全是懵逼的，对所讲的东西完全不知道是什么。
>
> 如果你有和我一样的感觉，千万不要自责，不要纠结，你不是唯一的，很多人都这样。
>
> 我建议你参考我的文章，去解析一个 VBMeta 数据后再回来读，可能会有更深切的理解。
>
> 简单说了， VBMeta 是 AVB 的核心数据。
>
> 所有的操作都是围绕这个核心数据：
>
> - 编译阶段，生成各个分区以及 vbmeta 分区的 VBMeta 数据。

## 回滚保护

AVB 包括回滚保护，用于防止已知的安全漏洞。每个 VBMeta 结构体都内置了一个回滚索引，如下所示：

![AVB rollback indexes](./images-20241202-Android AVB 分析（二）AVB 2.0 自述文档(v1.3 版-20250118)/avb-rollback-indexes.png)

这些数字被称为 `rollback_index[n]` ，并且随着发现并修复安全漏洞而逐个图像增加。此外，设备在防篡改存储中存储最后看到的回滚索引：

![AVB stored rollback indexes](./images-20241202-Android AVB 分析（二）AVB 2.0 自述文档(v1.3 版-20250118)/avb-stored-rollback-indexes.png)

这些被称为 `stored_rollback_index[n]` 。

回滚保护是指设备拒绝一个图像，除非对于所有 `n` ， `rollback_index[n]` >= `stored_rollback_index[n]` ，并且设备随时间增加 `stored_rollback_index[n]` 。具体如何实现，请参阅更新存储回滚索引部分。

## A/B 支持

AVB 已被设计为与 A/B 一起工作，要求 A/B 后缀在任何存储在描述符中的分区名称中都不使用。以下是一个包含两个插槽的示例：

![AVB with A/B partitions](./images-20241202-Android AVB 分析（二）AVB 2.0 自述文档(v1.3 版-20250118)/avb-ab-partitions.png)

注意回滚索引在不同槽位之间的差异 - 对于槽位 A，回滚索引是 `[42, 101]` ，而对于槽位 B，它们是 `[43, 103]` 。

在版本 1.1 或更高版本中，avbtool 支持 `--do_not_use_ab` 用于 `add_hash_footer` 和 `add_hashtree_footer` 操作。这使得可以处理不使用 A/B 且不应有前缀的分区。这对应于 `AVB_HASH[TREE]_DESCRIPTOR_FLAGS_DO_NOT_USE_AB` 标志。

在版本 1.3 中，avbtool 支持 `chain_partition_do_not_use_ab` 用于 `make_vbmeta_image` 操作。这使得可以与不使用 A/B 且不应有后缀的链分区一起工作。这对应于 `AVB_CHAIN_PARTITION_DESCRIPTOR_FLAGS_DO_NOT_USE_AB` 标志。

## VBMeta 摘要

VBMeta 摘要是对所有 VBMeta 结构（包括根结构，例如在 `vbmeta` 分区中）以及链式分区中所有 VBMeta 结构的摘要。此摘要可以在构建时使用 `avbtool calculate_vbmeta_digest` 计算，也可以在运行时使用 `avb_slot_verify_data_calculate_vbmeta_digest()` 函数计算。它还设置为内核命令行上的 `androidboot.vbmeta.digest` ，有关详细信息，请参阅 `avb_slot_verify()` 文档。

本摘要可用于与 `libavb` 一起在加载的操作系统用户空间内验证 vbmeta 结构的有效性。如果信任根和/或存储的回滚索引仅在引导加载程序运行时可用，则此功能很有用。

此外，如果 VBMeta 摘要包含在硬件支持的声明数据中，依赖方可以提取摘要并将其与已知良好操作系统的摘要列表进行比较，如果找到，这将为应用程序运行在的设备提供额外的保证。

对于 Pixel 3 及以后设备的工厂镜像，位于 `tools/transparency` 的 `pixel_factory_image_verify.py` 是一个用于下载、验证和计算 VBMeta 摘要的便捷工具。

```
$ pixel_factory_image_verify.py https://dl.google.com/dl/android/aosp/image.zip
Fetching file from: https://dl.google.com/dl/android/aosp/image.zip
Successfully downloaded file.
Successfully unpacked factory image.
Successfully unpacked factory image partitions.
Successfully verified VBmeta.
Successfully calculated VBMeta Digest.
The VBMeta Digest for factory image is: 1f329b20a2dd69425e7a29566ca870dad51d2c579311992d41c9ba9ba05e170e
```

如果给定的参数不是一个 URL，则被视为本地文件：

```
$ pixel_factory_image_verify.py image.zip
```



# 工具和库

本节包含有关 AVB 中包含的工具和库的信息。

## avbtool 和 libavb

`avbtool` 的主要任务是创建 `vbmeta.img` ，这是验证启动的最高级对象。此镜像设计用于放入 `vbmeta` 分区（或，如果使用 A/B，则放入相应的槽位，例如 `vbmeta_a` 或 `vbmeta_b` ），并保持最小尺寸（用于带外更新）。vbmeta 镜像经过加密签名，并包含用于验证 `boot.img` 、 `system.img` 和其他分区/镜像的验证数据（例如加密摘要）。

vbmeta 镜像还可以包含对其他分区的引用，其中存储了验证数据，以及一个公钥，指示谁应该对验证数据进行签名。这种间接引用提供了委托，即允许第三方通过在 `vbmeta.img` 中包含他们的公钥来控制特定分区上的内容。按照设计，可以通过简单地用新的分区描述符更新 `vbmeta.img` 来轻松撤销这种权限。

存储在其它图像上的签名验证数据 - 例如 `boot.img` 和 `system.img` - 也使用 `avbtool` 进行。

运行 `avbtool` 的最小要求是安装 Python 3.5 或使用 `m avbtool` 构建带有嵌入式启动器的 avbtool，然后在构建工件目录中运行它： `out/soong/host/linux-x86/bin/avbtool`

除了 `avbtool` ，还提供了一个库 - `libavb` 。这个库在设备端执行所有验证，例如，它首先加载 `vbmeta` 分区，检查签名，然后继续加载 `boot` 分区进行验证。这个库旨在在引导加载程序和 Android 内部使用。它为系统依赖提供了一个简单的抽象（见 `avb_sysdeps.h` ），以及引导加载程序或操作系统预期要实现的操作（见 `avb_ops.h` ）。验证的主要入口点是 `avb_slot_verify()` 。

一个可选的扩展 `libavb_cert` 还提供了一个基于证书的可伸缩授权机制。基本 `libavb` 要求设备手动实现公钥验证（参见 `avb_validate_vbmeta_public_key()` 在 `avb_ops.h` 中），当处理的不是单个硬编码的密钥时可能会很复杂。 `libavb_cert` 提供了这个功能的实现，它内置了对密钥轮换等功能的支持。

`libavb_cert` 之前被称为 `libavb_atx` （Android Things eXtension），但已被重命名为更好地体现其作为通用扩展的实用性，而不是仅针对 Android Things 项目的特定内容。

## 文件和目录

- ```
  libavb/
  ```

  - 图像验证的实现。此代码设计为高度可移植，以便尽可能多地用于各种环境。此代码需要符合 C99 标准的 C 编译器。此代码的一部分被视为实现内部，不应在实现之外使用。例如，这适用于 `avb_rsa.[ch]` 和 `avb_sha.[ch]` 文件。平台应提供的系统依赖项定义在 `avb_sysdeps.h` 中。如果平台提供标准 C 运行时 `avb_sysdeps_posix.c` ，则可以使用。

- ```
  libavb_cert/
  ```

  - A libavb 证书授权扩展。

- ```
  libavb_user/
  ```

  - 包含适用于 Android 用户空间的 `AvbOps` 实现。此实现用于 `boot_control.avb` 和 `avbctl` 。

- ```
  libavb_ab/
  ```

  - 一个用于引导加载程序和 AVB 示例的实验性 A/B 实现。注意：此代码已弃用，您必须定义 `AVB_AB_I_UNDERSTAND_LIBAVB_AB_IS_DEPRECATED` 才能使用它。代码将于 2018 年 6 月 1 日被移除。

- ```
  boot_control/
  ```

  - Android `boot_control` HAL 的实现，用于与使用实验性的 `libavb_ab` A/B 栈的引导加载程序一起使用。注意：此代码已弃用，将于 2018 年 6 月 1 日删除。

- ```
  Android.bp
  ```

  - 构建 `libavb` （用于设备的静态库）的说明、主机端库（用于单元测试）和单元测试。

- ```
  avbtool
  ```

  - 一个用于处理与验证启动相关的图像的 Python 编写工具。

- ```
  test/
  ```

  - 单元测试为 `abvtool` ， `libavb` ， `libavb_ab` 和 `libavb_cert` 。

- ```
  tools/avbctl/
  ```

  - 包含用于在 Android 运行时控制 AVB 的工具的源代码。

- ```
  examples/uefi/
  ```

  - 包含基于 UEFI 的引导加载程序的源代码，利用 `libavb/` 和 `libavb_ab/` 。

- ```
  examples/cert/
  ```

  - 包含使用 `avb_cert` 扩展的示例源代码

- ```
  README.md
  ```

  -  这是一个文件。

- ```
  docs/
  ```

  - 包含文档文件。

##  便携性

`libavb` 代码旨在用于将 Android 或其他操作系统加载到设备中的引导加载程序。建议的方法是将前一部分中提到的适当头文件和 C 文件复制到引导加载程序中，并按需集成。

随着 `libavb/` 代码库随时间发展，集成应尽可能不具侵入性。目标是保持库的 API 稳定，但在必要时可以破坏。至于可移植性，库旨在高度可移植，适用于小端和大端架构以及 32 位和 64 位。它还旨在在没有标准 C 库和运行时的情况下在非标准环境中工作。

如果设置了 `AVB_ENABLE_DEBUG` 预处理器符号，代码将包含有用的调试信息和运行时检查。生产构建不应使用此功能。仅在编译库时应设置预处理器符号 `AVB_COMPILATION` 。代码必须编译成单独的库。

应用程序使用编译的 `libavb` 库时，必须仅包含 `libavb/libavb.h` 文件（其中将包含所有公共接口），并且不得设置 `AVB_COMPILATION` 预处理器符号。这是为了确保可能在未来更改的内部代码（例如 `avb_sha.[ch]` 和 `avb_rsa.[ch]` ）不会对应用程序代码可见。

## 版本和兼容性

AVB 使用一个包含三个字段的版本号 - 主版本、次版本和子版本。以下是一个示例版本号

```
                     1.4.3
                     ^ ^ ^
                     | | |
the major version ---+ | |
the minor version -----+ |
  the sub version -------+
```

主版本号仅在兼容性破坏时增加，例如结构体字段已被删除或更改。次版本号仅在引入新功能时增加，例如添加了新的算法或描述符。子版本号在修复错误或进行不影响兼容性的其他更改时增加。

`AvbVBMetaImageHeader` 结构（如 `avb_vbmeta_image.h` 中定义的）携带了用于验证相关结构的 `libavb` 主版本号和次版本号。这些存储在 `required_libavb_version_major` 和 `required_libavb_version_minor` 字段中。此外，此结构还包含一个文本字段，其中包含用于创建结构的 `avbtool` 版本，例如“avbtool 1.4.3”或“avbtool 1.4.3 some_board Git-4589fbec”。

请注意，完全有可能有一个 `AvbVBMetaImageHeader` 结构体

```
required_libavb_version_major = 1
required_libavb_version_minor = 0
avbtool_release_string = "avbtool 1.4.3"
```

如果，例如，创建一个不使用 AVB 1.0 版本后添加的任何功能的图像。

##  添加新功能

如果添加新功能，例如新算法或新描述符，那么在 `avb_version.h` 和 `avbtool` 中 `AVB_VERSION_MINOR` 必须升级，并且 `AVB_VERSION_SUB` 应设置为零。

单元测试必须添加以检查

- 该功能仅在传递适当的命令/选项给 `avbtool` 时使用。
- 该 `required_version_minor` 字段仅在功能使用时设置为弹跳值。另外，添加测试以检查当使用 `--print_required_libavb_version` 时输出正确的值。

如果自上次发布以来 `AVB_VERSION_MINOR` 已经被更新，显然没有必要再次更新它。

##  使用 avbtool

vbmeta 分区的内容可以按以下方式生成：

```
$ avbtool make_vbmeta_image                                                                  \
    [--output OUTPUT]                                                                        \
    [--algorithm ALGORITHM] [--key /path/to/key_used_for_signing_or_pub_key]                 \
    [--public_key_metadata /path/to/pkmd.bin]                                                \
    [--rollback_index NUMBER] [--rollback_index_location NUMBER]                             \
    [--include_descriptors_from_image /path/to/image.bin]                                    \
    [--setup_rootfs_from_kernel /path/to/image.bin]                                          \
    [--chain_partition part_name:rollback_index_location:/path/to/key1.bin]                  \
    [--chain_partition_do_not_use_ab part_name:rollback_index_location:/path/to/key.bin]     \
    [--signing_helper /path/to/external/signer]                                              \
    [--signing_helper_with_files /path/to/external/signer_with_files]                        \
    [--print_required_libavb_version]                                                        \
    [--append_to_release_string STR]
```

一个包含整个分区哈希值的完整性页脚可以按以下方式添加到现有镜像中：

```
$ avbtool add_hash_footer                                                      \
    --partition_name PARTNAME --partition_size SIZE                            \
    [--image IMAGE]                                                            \
    [--algorithm ALGORITHM] [--key /path/to/key_used_for_signing_or_pub_key]   \
    [--public_key_metadata /path/to/pkmd.bin]                                  \
    [--rollback_index NUMBER] [--rollback_index_location NUMBER]               \
    [--hash_algorithm HASH_ALG] [--salt HEX]                                   \
    [--include_descriptors_from_image /path/to/image.bin]                      \
    [--setup_rootfs_from_kernel /path/to/image.bin]                            \
    [--output_vbmeta_image OUTPUT_IMAGE] [--do_not_append_vbmeta_image]        \
    [--signing_helper /path/to/external/signer]                                \
    [--signing_helper_with_files /path/to/external/signer_with_files]          \
    [--print_required_libavb_version]                                          \
    [--append_to_release_string STR]                                           \
    [--calc_max_image_size]                                                    \
    [--do_not_use_ab]                                                          \
    [--use_persistent_digest]
```

有效值包括 `sha1` 和 `sha256` 。

一个包含分区哈希树的根摘要和盐的完整性页脚可以按以下方式添加到现有镜像中。哈希树也附加到镜像中。

```
$ avbtool add_hashtree_footer                                                  \
    --partition_name PARTNAME --partition_size SIZE                            \
    [--image IMAGE]                                                            \
    [--algorithm ALGORITHM] [--key /path/to/key_used_for_signing_or_pub_key]   \
    [--public_key_metadata /path/to/pkmd.bin]                                  \
    [--rollback_index NUMBER] [--rollback_index_location NUMBER]               \
    [--hash_algorithm HASH_ALG] [--salt HEX] [--block_size SIZE]               \
    [--include_descriptors_from_image /path/to/image.bin]                      \
    [--setup_rootfs_from_kernel /path/to/image.bin]                            \
    [--setup_as_rootfs_from_kernel]                                            \
    [--output_vbmeta_image OUTPUT_IMAGE] [--do_not_append_vbmeta_image]        \
    [--do_not_generate_fec] [--fec_num_roots FEC_NUM_ROOTS]                    \
    [--signing_helper /path/to/external/signer]                                \
    [--signing_helper_with_files /path/to/external/signer_with_files]          \
    [--print_required_libavb_version]                                          \
    [--append_to_release_string STR]                                           \
    [--calc_max_image_size]                                                    \
    [--do_not_use_ab]                                                          \
    [--no_hashtree]                                                            \
    [--use_persistent_digest]                                                  \
    [--check_at_most_once]
```

有效值包括 `sha1` 、 `sha256` 和 `blake2b-256` 。

图像带版权脚注的大小可以使用 `resize_image` 命令更改：

```
$ avbtool resize_image                                                         \
    --image IMAGE                                                              \
    --partition_size SIZE
```

图像的完整性页脚可以从图像中移除。哈希树可以保留。

```
$ avbtool erase_footer --image IMAGE [--keep_hashtree]
```

对于哈希和哈希树图像，vbmeta 结构也可以通过 `--output_vbmeta_image` 选项写入外部文件，并且还可以指定不要将 vbmeta 结构和页脚添加到正在操作的画面中。

图像中的哈希树和 FEC 数据可以使用以下命令清零：

```
$ avbtool zero_hashtree --image IMAGE
```

这对于在运行时重新计算哈希树和 FEC 以换取压缩图像大小是有用的。如果这样做，哈希树和 FEC 数据将被设置为 0，除了前八个字节被设置为魔法 `ZeRoHaSH` 。哈希树或 FEC 数据或两者都可以这样设置为 0，因此应用程序应在两个地方检查魔法。应用程序可以使用魔法来检测是否需要重新计算。

计算在执行了 `avbtool add_hash_footer` 或 `avbtool add_hashtree_footer` 命令后，将适合给定大小的分区中的最大图像大小的选项为 `--calc_max_image_size` ：

```
$ avbtool add_hash_footer --partition_size $((10*1024*1024)) \
    --calc_max_image_size
10416128

$ avbtool add_hashtree_footer --partition_size $((10*1024*1024)) \
    --calc_max_image_size
10330112
```

计算在使用 `make_vbmeta_image` 、 `add_hash_footer` 和 `add_hashtree_footer` 命令时，应放入 vbmeta 结构中的所需 libavb 版本，请使用 `--print_required_libavb_version` 选项：

```
$ avbtool make_vbmeta_image \
    --algorithm SHA256_RSA2048 --key /path/to/key.pem \
    --include_descriptors_from_image /path/to/boot.img \
    --include_descriptors_from_image /path/to/system.img \
    --print_required_libavb_version
1.0
```

否则，可以使用 `--no_hashtree` 与 `avbtool add_hashtree_footer` 命令。如果提供了 `--no_hashtree` ，则省略 hashtree blob，仅将其描述符添加到 vbmeta 结构中。描述符表示 hashtree 的大小为 0，这告诉应用程序需要重新计算 hashtree。

`--signing_helper` 选项可用于 `make_vbmeta_image` 、 `add_hash_footer` 和 `add_hashtree_footer` 命令中，用于指定任何外部程序进行哈希签名。要签名的数据（包括填充，例如 PKCS1-v1.5）通过 `STDIN` 提供，签名的数据通过 `STDOUT` 返回。如果命令行中存在 `--signing_helper` ，则 `--key` 选项只需包含公钥。签名辅助程序的参数为 `algorithm` 和 `public key` 。如果签名辅助程序以非零退出码退出，则表示失败。

这是一个示例调用：

```
/path/to/my_signing_program SHA256_RSA2048 /path/to/publickey.pem
```

`--signing_helper_with_files` 与 `--signing_helper` 类似，只是使用临时文件与辅助程序通信，而不是使用 `STDIN` 和 `STDOUT` 。这在签名辅助程序使用输出诊断信息到 `STDOUT` 而不是 `STDERR` 的代码的情况下很有用。以下是一个调用示例

```
/path/to/my_signing_program_with_files SHA256_RSA2048 \
  /path/to/publickey.pem /tmp/path/to/communication_file
```

该位置参数的最后一个参数是一个包含要签名数据的文件。辅助程序应将签名写入此文件。

`append_vbmeta_image` 命令可以用来将整个 vbmeta blob 附加到另一个图像的末尾。这在不需要任何 vbmeta 分区的情况下很有用，例如：

```
$ cp boot.img boot-with-vbmeta-appended.img
$ avbtool append_vbmeta_image                       \
    --image boot-with-vbmeta-appended.img           \
    --partition_size SIZE_OF_BOOT_PARTITION         \
    --vbmeta_image vbmeta.img
$ fastboot flash boot boot-with-vbmeta-appended.img
```

关于图像的信息可以使用 `info_image` 命令获取。此命令的输出不应被依赖，信息结构的方式可能会改变。

`verify_image` 命令可用于同时验证多个图像文件的内容。在图像上调用时，将执行以下检查：

- 如果图像具有 VBMeta 结构，则签名将与嵌入的公钥进行比对。如果图像看起来不像 `vbmeta.img` ，则将寻找并使用（如果存在）页脚。
- 如果传递了选项 `--key` ，则期望一个 `.pem` 文件，并检查该 VBMeta 结构中嵌入的公钥是否与给定的密钥匹配。
- 所有 VBMeta 结构中的描述符都按以下方式进行检查：
  - 对于一个哈希描述符，加载与分区名称对应的图像文件，并检查其摘要与描述符中的摘要是否一致。
  - 对于一个哈希树描述符，加载与分区名称对应的图像文件，计算哈希树并比较其根摘要与描述符中的摘要。
  - 对于一个链式分区描述符，其内容与通过 `--expected_chain_partition` 选项传递的内容进行比较。此选项的格式类似于 `--chain_partition` 选项。如果没有为链式分区描述符提供 `--expected_chain_partition` 描述符，则检查失败。

这是一个示例，其中 `boot.img` 和 `system.img` 的摘要存储在 `vbmeta.img` 中，该摘要由 `my_key.pem` 签名。它还检查分区 `foobar` 的链分区使用回滚索引 8，并且 AVB 格式的公钥与文件 `foobar_vendor_key.avbpubkey` 中的公钥匹配。

```
$ avbtool verify_image \
     --image /path/to/vbmeta.img \
     --key my_key.pem \
     --expect_chained_partition foobar:8:foobar_vendor_key.avbpubkey

Verifying image /path/to/vbmeta.img using key at my_key.pem
vbmeta: Successfully verified SHA256_RSA4096 vbmeta struct in /path_to/vbmeta.img
boot: Successfully verified sha256 hash of /path/to/boot.img for image of 10543104 bytes
system: Successfully verified sha1 hashtree of /path/to/system.img for image of 1065213952 bytes
foobar: Successfully verified chain partition descriptor matches expected data
```

在这个示例中， `verify_image` 命令验证目录 `/path/to` 中的文件 `vbmeta.img` 、 `boot.img` 和 `system.img` 。给定图像的目录和文件扩展名（例如， `/path/to/vbmeta.img` ）与分区名称一起用于描述符中，以计算包含哈希和哈希树图像的图像文件名。

`verify_image` 命令也可以用来检查自定义签名助手是否按预期工作。

`calculate_vbmeta_digest` 命令可用于同时计算多个图像文件的 vbmeta 摘要。结果以十六进制字符串形式打印在 `STDOUT` 或提供的路径上（使用 `--output` 选项）。

```
$ avbtool calculate_vbmeta_digest \
     --hash_algorithm sha256 \
     --image /path/to/vbmeta.img
a20fdd01a6638c55065fe08497186acde350d6797d59a55d70ffbcf41e95c2f5
```

在这个示例中， `calculate_vbmeta_digest` 命令加载 `vbmeta.img` 文件。如果此映像有一个或多个链分区描述符，则使用与 `verify_image` 命令相同的逻辑来加载这些文件的文件（例如，它假定与给定映像相同的目录和文件扩展名）。一旦所有 vbmeta 结构都已加载，就会计算摘要（使用 `--hash_algorithm` 选项给出的哈希算法）并打印出来。

打印嵌入在验证元数据中的哈希和哈希树摘要，请使用 `print_partition_digests` 命令，如下所示：

```
$ avbtool print_partition_digests --image /path/to/vbmeta.img
system: ddaa513715fd2e22f3c1cea3c1a1f98ccb515fc6
boot: 5cba9a418e04b5f9e29ee6a250f6cdbe30c6cec867c59d388f141c3fedcb28c1
vendor: 06993a9e85e46e53d3892881bb75eff48ecadaa8
```

对于具有哈希描述符的分区，此操作将打印出摘要；对于具有哈希树描述符的分区，将打印出根摘要。类似于 `calculate_vbmeta_digest` 和 `verify_image` 命令，链分区也会被跟踪。要使用 JSON 格式输出，请使用 `--json` 选项。

如果需要记录所有 avbtool 调用的命令行以进行与其他工具集成的调试，可以配置环境变量 AVB_INVOCATION_LOGFILE，指定日志文件的名称：

```
$ export AVB_INVOCATION_LOGFILE='/tmp/avb_invocation.log'
$ ./avbtool.py version
$ ./avbtool.py version
$ cat /tmp/avb_invocation.log
./avbtool.py version
./avbtool.py version
```

## 构建系统集成

在 Android 中，通过 `BOARD_AVB_ENABLE` 变量启用 AVB

```
BOARD_AVB_ENABLE := true
```

这将使构建系统创建 `vbmeta.img` ，其中将包含 `boot.img` 的哈希描述符、 `system.img` 的哈希树描述符、用于设置 `dm-verity` 以 `system.img` 的内核命令行描述符，并将哈希树附加到 `system.img` 。如果构建系统设置为构建 `vendor.img` / `product.img` / `system_ext.img` / `odm.img` 中的任何一个或多个，则相应地也将它们的哈希树附加到镜像中，并将它们的哈希树描述符包括到 `vbmeta.img` 中。

默认情况下，使用来自 `external/avb/test/data` 目录的测试密钥与算法 `SHA256_RSA4096` 一起使用。这可以通过 `BOARD_AVB_ALGORITHM` 和 `BOARD_AVB_KEY_PATH` 变量来覆盖，例如使用 4096 位 RSA 密钥和 SHA-512：

```
BOARD_AVB_ALGORITHM := SHA512_RSA4096
BOARD_AVB_KEY_PATH := /path/to/rsa_key_4096bits.pem
```

记住，此密钥的公共部分需要可供设备引导加载程序使用，以验证生成的映像。使用 `avbtool extract_public_key` 以预期格式提取密钥（以下为 `AVB_pk` ）。如果设备使用不同于 `AVB_pk` 的信任根，则可以使用 `--public_key_metadata` 选项嵌入 blob（以下为 `AVB_pkmd` ），该 blob 可用于例如派生 `AVB_pk` 。在验证槽位时， `AVB_pk` 和 `AVB_pkmd` 都传递给 `validate_vbmeta_public_key()` 操作。

某些设备可能支持最终用户配置要使用的信任根，请参阅设备特定说明部分以获取详细信息。

设备可以配置为创建额外的 `vbmeta` 分区，作为链式分区以更新部分分区而不改变顶级 `vbmeta` 分区。例如，以下变量创建 `vbmeta_system.img` 作为包含 `system.img` 、 `system_ext.img` 和 `product.img` 的哈希树描述符的链式 `vbmeta` 镜像。 `vbmeta_system.img` 本身将由指定的密钥和算法进行签名。

```
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1
```

请注意， `system.img` 、 `system_ext.img` 和 `product.img` 的哈希树描述符仅包含在 `vbmeta_system.img` 中，但不包含在 `vbmeta.img` 中。以上设置下，分区 `system.img` 、 `system_ext.img` 、 `product.img` 和 `vbmeta_system.img` 可以独立更新——但作为一个组——与其他分区一起，或者作为更新所有分区的传统更新的一部分。

当前构建系统支持构建链式 `vbmeta` 图像的 `vbmeta_system.img` （ `BOARD_AVB_VBMETA_SYSTEM` ）和 `vbmeta_vendor.img` （ `BOARD_AVB_VBMETA_VENDOR` ）。

为防止回滚攻击，应定期增加回滚索引。回滚索引可以通过 `BOARD_AVB_ROLLBACK_INDEX` 变量设置：

```
 BOARD_AVB_ROLLBACK_INDEX := 5
```

如果此设置未设置，回滚索引默认为 0。

变量 `BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS` 可用于指定传递给 `avbtool make_vbmeta_image` 的附加选项。此处通常使用的选项包括 `--prop` 、 `--prop_from_file` 、 `--chain_partition` 、 `--public_key_metadata` 和 `--signing_helper` 。

该变量 `BOARD_AVB_BOOT_ADD_HASH_FOOTER_ARGS` 可用于指定传递给 `avbtool add_hash_footer` 用于 `boot.img` 的附加选项。此处通常使用的选项包括 `--hash_algorithm` 和 `--salt` 。

该变量 `BOARD_AVB_SYSTEM_ADD_HASHTREE_FOOTER_ARGS` 可用于指定传递给 `avbtool add_hashtree_footer` 用于 `system.img` 的附加选项。此处通常使用的选项包括 `--hash_algorithm` 、 `--salt` 、 `--block_size` 和 `--do_not_generate_fec` 。

该变量 `BOARD_AVB_VENDOR_ADD_HASHTREE_FOOTER_ARGS` 可用于指定传递给 `avbtool add_hashtree_footer` 用于 `vendor.img` 的附加选项。此处通常使用的选项包括 `--hash_algorithm` 、 `--salt` 、 `--block_size` 和 `--do_not_generate_fec` 。

该变量 `BOARD_AVB_DTBO_ADD_HASH_FOOTER_ARGS` 可用于指定传递给 `avbtool add_hash_footer` 用于 `dtbo.img` 的附加选项。此处通常使用的选项包括 `--hash_algorithm` 和 `--salt` 。

构建系统变量（如 `PRODUCT_SUPPORTS_VERITY_FEC` ）用于 Android 先前版本的验证启动，在 AVB 中未使用。

A/B 相关的构建系统变量可以在这里找到。

#  设备集成

本节讨论了将 `libavb` 与设备引导加载程序集成的建议和最佳实践。重要的是强调，这些只是建议，因此对 `must` 一词的使用应谨慎。

此外，本章中使用术语 HLOS 来指代高级操作系统。这显然包括 Android（包括除手机以外的其他形态）但也可以是其他操作系统。

##  系统依赖

该 `libavb` 库以可移植的方式编写，适用于任何具有 C99 编译器的系统。它不需要标准 C 库，但是引导加载程序必须实现 `libavb` 所需的一系列简单系统原语，例如 `avb_malloc()` 、 `avb_free()` 和 `avb_print()` 。

除了系统原语之外， `libavb` 通过提供的 `AvbOps` 结构体与引导加载程序接口。这包括从分区读取和写入数据、读取和写入回滚索引、检查用于生成签名的公钥是否应该被接受等操作。

##  锁定和解锁模式

AVB 已设计为支持设备处于锁定状态或解锁状态的概念，正如在 Android 中使用的。

在 AVB 的上下文中，LOCKED 状态意味着验证错误是致命的，而在 UNLOCKED 状态下则不是。如果设备处于 UNLOCKED 状态，则在 `avb_slot_verify()` 的 `flags` 参数中传递 `AVB_SLOT_VERIFY_FLAGS_ALLOW_VERIFICATION_ERROR` 标志，并处理包括验证错误在内的

- `AVB_SLOT_VERIFY_RESULT_ERROR_PUBLIC_KEY_REJECTED`
- `AVB_SLOT_VERIFY_RESULT_ERROR_VERIFICATION`
- `AVB_SLOT_VERIFY_RESULT_ERROR_ROLLBACK_INDEX`

如果设备处于锁定状态，不要在 `avb_slot_verify()` 的 `flags` 参数中传递 `AVB_SLOT_VERIFY_FLAGS_ALLOW_VERIFICATION_ERROR` 标志，仅将 `AVB_SLOT_VERIFY_RESULT_OK` 视为非致命错误。

在 Android 上，可以通过 fastboot 接口使用，例如 `fastboot flashing lock` （切换到 LOCKED 状态）和 `fastboot flashing unlock` （切换到 UNLOCKED 状态）来更改设备状态。

设备必须在确认用户物理存在后，才允许状态转换（例如从锁定到解锁或从解锁到锁定）。如果设备有显示屏和按钮，这通常是通过显示对话框并要求用户使用物理按钮确认或取消来完成的。

所有用户数据在从锁定状态过渡到解锁状态时必须清除（包括 `userdata` 分区和任何 NVRAM 空间）。此外，所有 `stored_rollback_index[n]` 位置必须清除（所有元素必须设置为零）。在从解锁状态过渡到锁定状态时，也应采取类似行动（擦除 `userdata` 、NVRAM 空间和 `stored_rollback_index[n]` 位置）。如果设备需要使用全盘加密，则从解锁状态到锁定状态需要更温和的擦除。根据设备形态和预期用途，应在删除任何数据之前提示用户确认。

##  防篡改存储

在此文档中，防篡改意味着可以检测到 HLOS 是否篡改了数据，例如，如果它已被覆盖。

防篡改存储必须用于存储回滚索引、用于验证的密钥、设备状态（设备是否被锁定或解锁）以及命名持久值。如果检测到篡改，相应的 `AvbOps` 操作应失败，例如通过返回 `AVB_IO_RESULT_ERROR_IO` 。特别重要的是，验证密钥不能被篡改，因为它们代表了信任的根源。

如果验证密钥可变，则只能由最终用户设置，例如，绝不能在工厂、商店或最终用户之前的任何中间点设置。此外，只有在设备处于解锁状态时才能设置或清除密钥。

##  命名持久值

AVB 1.1 引入了对命名持久值的支持，这些值必须是防篡改的，并允许 AVB 存储任意键值对。集成商可以将对这些值的支持限制为一组固定的已知名称、最大值大小以及/或最大值数量。

##  持久摘要

使用分区持久性摘要意味着摘要（或哈希树的情况下的根摘要）不是存储在描述符中，而是存储在命名的持久值中。这允许配置数据（可能因设备而异）通过 AVB 进行验证。当设备处于 LOCKED 状态时，不应可能修改持久摘要，除非摘要不存在，此时可以初始化。

指定描述符应使用持久性摘要，请使用 `--use_persistent_digest` 选项进行 `add_hash_footer` 或 `add_hashtree_footer` avbtool 操作。然后，在验证描述符时，AVB 将在名为持久性值 `avb.persistent_digest.$(partition_name)` 中查找摘要，而不是在描述符本身中。

对于使用持久性摘要的 hashtree 描述符，摘要值将可用于替换内核命令行描述符，使用形式为 `$(AVB_FOO_ROOT_DIGEST)` 的令牌，其中‘FOO’是大写分区名称，在这种情况下，对于名为‘foo’的分区。该令牌将被十六进制形式的摘要所替换。

默认情况下，当使用 `--use_persistent_digest` 选项与 `add_hash_footer` 或 `add_hashtree_footer` 一起使用时，avbtool 将生成一个不带盐的描述符，而不是生成随机盐的典型默认值。这是因为摘要值存储在持久存储中，因此不能随时间改变。另一种选择是手动使用 `--salt` 提供随机盐，但一旦写入持久摘要值，此盐需要保持不变，直到设备寿命结束。

## 更新存储的回滚索引

为了使回滚保护功能正常工作，引导加载程序需要在将控制权传递给 HLOS 之前更新设备上的 `stored_rollback_indexes[n]` 数组。如果不使用 A/B，这很简单——只需将其更新为启动前 AVB 元数据中指定槽位的内容。在伪代码中，它看起来是这样的：

```
// The |slot_data| parameter should be the AvbSlotVerifyData returned
// by avb_slot_verify() for the slot we're about to boot.
//
bool update_stored_rollback_indexes_for_slot(AvbOps* ops,
                                             AvbSlotVerifyData* slot_data) {
    for (int n = 0; n < AVB_MAX_NUMBER_OF_ROLLBACK_INDEX_LOCATIONS; n++) {
        uint64_t rollback_index = slot_data->rollback_indexes[n];
        if (rollback_index > 0) {
            AvbIOResult io_ret;
            uint64_t current_stored_rollback_index;

            io_ret = ops->read_rollback_index(ops, n, &current_stored_rollback_index);
            if (io_ret != AVB_IO_RESULT_OK) {
                return false;
            }

            if (rollback_index > current_stored_rollback_index) {
                io_ret = ops->write_rollback_index(ops, n, rollback_index);
                if (io_ret != AVB_IO_RESULT_OK) {
                    return false;
                }
            }
        }
    }
    return true;
}
```

然而，如果使用 A/B 测试，则必须更加小心，以确保在更新失败时设备仍能回退到旧槽位。

对于像 Android 这样的 HLOS，只有当更新的操作系统版本被发现无法工作时才支持回滚， `stored_rollback_index[n]` 应仅从标记为“成功”的 A/B 元数据槽位更新。相应的伪代码如下，其中 `is_slot_is_marked_as_successful()` 来自正在使用的 A/B 堆栈：

```
if (is_slot_is_marked_as_successful(slot->ab_suffix)) {
    if (!update_stored_rollback_indexes_for_slot(ops, slot)) {
        // TODO: handle error.
    }
}
```

此逻辑理想情况下应在 HLOS 之外实现。一种可能的实现方式是在成功槽位启动时更新回滚索引。这意味着当启动到尚未标记为成功的全新操作系统时，不会更新回滚索引。槽位成功后的第一次重启将触发回滚索引的更新。

对于支持回滚到先前版本的 HLOS， `stored_rollback_index[n]` 应设置为可能的最大值，以允许所有可引导槽位启动。这种方法在 AVB 的实验性（现在已弃用）A/B 堆栈 `libavb_ab` 中实现，请参阅 `avb_ab_flow()` 实现。请注意，这需要在每次启动时验证所有可引导槽位，这可能会影响启动时间。

##  推荐引导流程

推荐使用 AVB 的设备的启动流程如下：

![Recommended AVB boot flow](./images-20241202-Android AVB 分析（二）AVB 2.0 自述文档(v1.3 版-20250118)/avb-recommended-boot-flow.png)



 注意：

- 该设备预计将搜索所有 A/B 槽位，直到找到有效的操作系统进行引导。处于锁定状态的槽位在解锁状态下可能不会被拒绝（例如，在解锁状态下，任何密钥都可以使用，并且允许回滚索引失败），因此选择槽位的算法取决于设备所处的状态。
- 如果找不到有效的操作系统（即没有可启动的 A/B 槽），设备无法启动并必须进入维修模式。设备的外观取决于设备本身。如果设备有屏幕，它必须将此状态传达给用户。
- 如果设备处于锁定状态，则只能接受由嵌入式验证密钥签名的操作系统（参见上一节）。此外，存储在已验证镜像中的 `rollback_index[n]` 必须大于或等于设备上的 `stored_rollback_index[n]` （对于所有 `n` ），并且预期 `stored_rollback_index[n]` 数组将根据上一节所述进行更新。
  - 如果用于验证的密钥是由最终用户设置的，并且设备有屏幕，则必须在设备启动自定义操作系统时显示带有密钥指纹的警告，以传达设备正在启动自定义操作系统。警告必须在启动过程继续之前至少显示 10 秒。如果设备没有屏幕，则必须使用其他方式传达设备正在启动自定义操作系统（灯光条、LED 等）。
- 如果设备已解锁，则无需检查用于签名操作系统的密钥，也不需要检查或更新设备上的回滚 `stored_rollback_index[n]` 。因此，必须始终向用户显示有关验证未发生的警告。
  - 设备依赖实现方式，因为这与设备形态和预期用途有关。如果设备有屏幕和按钮（例如，如果是手机），则在启动过程继续之前至少显示 10 秒警告。如果设备没有屏幕，则必须使用其他方式来传达设备已解锁（灯条、LED 等）。

###  启动至恢复模式

在未使用 A/B 测试的 Android 设备上， `recovery` 分区通常不会与其他分区一起更新，因此无法从主 `vbmeta` 分区引用。

仍然可以通过签名这些分区并传递 `AVB_SLOT_VERIFY_FLAGS_NO_VBMETA_PARTITION` 标志到 `avb_slot_verify()` 来使用 AVB 保护这个分区（以及其他分区）。在此模式下，用于签名每个请求分区的密钥由 `validate_public_key_for_partition()` 操作验证，该操作也用于返回要使用的回滚索引位置。

## 处理 dm-verity 错误

设计上，哈希树验证错误由 HLOS 检测，而不是引导加载程序。AVB 提供了一种通过 `avb_slot_verify()` 函数中的 `hashtree_error_mode` 参数指定如何处理错误的方法。可能的值包括

- `AVB_HASHTREE_ERROR_MODE_RESTART_AND_INVALIDATE` 表示 HLOS 将使当前槽位失效并重新启动。在具有 A/B 的设备上，这会导致尝试启动另一个槽位（如果它被标记为可启动）或可能导致无法启动任何操作系统的情况（例如某种形式的修复模式）。在 Linux 中，这需要使用 `CONFIG_DM_VERITY_AVB` 构建的内核。
- `AVB_HASHTREE_ERROR_MODE_RESTART` 表示操作系统将在不使当前槽无效的情况下重启。请谨慎无条件使用此模式，因为它可能在每次启动时遇到相同的哈希树验证错误时引入引导循环。
- `AVB_HASHTREE_ERROR_MODE_EIO` 表示将返回一个 `EIO` 错误给应用程序。
- `AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO` 表示根据状态，使用 RESTART 或 EIO 模式。此模式实现了一个状态机，其中默认使用 RESTART，当将 `AVB_SLOT_VERIFY_FLAGS_RESTART_CAUSED_BY_HASHTREE_CORRUPTION` 传递给 `avb_slot_verify()` 时，模式转换为 EIO。检测到新操作系统后，设备将返回到 RESTART 模式。
  - 为此需要持久化存储 - 具体来说，这意味着传入的 `AvbOps` 将需要实现 `read_persistent_value()` 和 `write_persistent_value()` 操作。使用的持久化值名称为 avb.managed_verity_mode，需要 32 字节存储空间。
- `AVB_HASHTREE_ERROR_MODE_LOGGING` 表示错误将被记录，损坏的数据可能会返回给应用程序。此模式应仅用于诊断和调试。除非允许验证错误，否则不能使用。
- `AVB_HASHTREE_ERROR_MODE_PANIC` 表示如果没有使当前插槽失效，操作系统将会崩溃。使用此模式时要小心，因为它可能在每次启动时遇到相同的哈希树验证错误时引发引导崩溃。此模式自 1.7.0（内核 5.9）以来可用。

传入的值 `hashtree_error_mode` 实际上只是通过以下方式通过 `androidboot.veritymode` 、 `androidboot.veritymode.managed` 和 `androidboot.vbmeta.invalidate_on_error` 内核命令行参数传递给 HLOS：

|                                                   |            `androidboot.veritymode`            | `androidboot.veritymode.managed` | `androidboot.vbmeta.invalidate_on_error` |
| :-----------------------------------------------: | :--------------------------------------------: | :------------------------------: | :--------------------------------------: |
| `AVB_HASHTREE_ERROR_MODE_RESTART_AND_INVALIDATE`  |                    **执行**                    |              未设置              |                 **是的**                 |
|         `AVB_HASHTREE_ERROR_MODE_RESTART`         |                    **执行**                    |              未设置              |                  未设置                  |
|           `AVB_HASHTREE_ERROR_MODE_EIO`           | **eio （输入文本为代码或专有名词，无需翻译）** |              未设置              |                  未设置                  |
| `AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO` |                 eio 或强制执行                 |             **是的**             |                  未设置                  |
|         `AVB_HASHTREE_ERROR_MODE_LOGGING`         |             **ignore_corruption**              |              未设置              |                  未设置                  |
|          `AVB_HASHTREE_ERROR_MODE_PANIC`          |                    **恐慌**                    |              未设置              |                  未设置                  |

该表唯一的例外是，如果顶级 vbmeta 中设置了 `AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED` 标志，则 `androidboot.veritymode` 设置为禁用，而 `androidboot.veritymode.managed` 和 `androidboot.vbmeta.invalidate_on_error` 被取消设置。

该函数中 `hashtree_error_mode` 参数的不同值可以分为三类：

- `AVB_HASHTREE_ERROR_MODE_RESTART_AND_INVALIDATE` ，需要在内核配置中设置 `CONFIG_DM_VERITY_AVB` 以使内核使当前插槽无效并重新启动。这保留在此处是为了兼容旧版 Android Things 设备，不建议用于其他设备形态。
- 引导加载程序处理 `AVB_HASHTREE_ERROR_MODE_RESTART` 和 `AVB_HASHTREE_ERROR_MODE_EIO` 之间的切换。这需要在设备上有一个持久存储来存储 vbmeta 摘要，以便引导加载程序检测设备是否曾经收到更新。一旦新操作系统安装完成，如果设备处于 EIO 模式，引导加载程序应切换回 RESTART 模式。
- `AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO` : `libavb` 帮助引导加载程序管理 EIO/RESTART 状态转换。引导加载程序需要实现 `AvbOps->read_persistent_value()` 和 `AvbOps->write_persistent_value()` 的回调，以便将 vbmeta 摘要存储到 `libavb` 中，以检测是否安装了新的操作系统。

### 我应该使用哪种模式为我的设备？

这完全取决于设备，设备的使用方式和期望的用户体验。

对于 Android 设备，应使用 `AVB_HASHTREE_ERROR_MODE_MANAGED_RESTART_AND_EIO` 模式。另请参阅 source.android.com 上的引导流程部分，了解引导加载器应实现的 UX 和 UI 类型。

如果设备没有屏幕或者如果 HLOS 支持同时支持多个可启动槽位，那么直接使用 `AVB_HASHTREE_ERROR_MODE_RESTART_AND_INVALIDATE` 可能更有意义。

## 安卓特定集成

在 Android 上，引导加载程序必须在内核命令行上设置 `androidboot.verifiedbootstate` 参数以指示引导状态。它应使用以下值：

- 绿色：如果在锁定状态下，用于验证的密钥未由最终用户设置。
- 黄色：如果在锁定状态下，用于验证的密钥是由最终用户设置的。
- 如果处于解锁状态。

## GKI 2.0 集成

从 Android 12 开始，搭载内核版本 5.10 或更高版本的设备必须配备 GKI 内核。详情请见 GKI 2.0。

在将认证的 GKI `boot.img` 集成到设备代码库时，应配置以下板变量。下面显示的设置只是一个示例，需要根据设备进行调整。

```
# Uses a prebuilt boot.img
TARGET_NO_KERNEL := true
BOARD_PREBUILT_BOOTIMAGE := device/${company}/${board}/boot.img

# Enables chained vbmeta for the boot.img so it can be updated independently,
# without updating the vbmeta.img. The following configs are optional.
# When they're absent, the hash of the boot.img will be stored then signed in
# the vbmeta.img.
BOARD_AVB_BOOT_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_BOOT_ALGORITHM := SHA256_RSA4096
BOARD_AVB_BOOT_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_BOOT_ROLLBACK_INDEX_LOCATION := 2
```

注意：经过认证的 GKI `boot.img` 未签名以进行验证启动。对于预构建的 GKI `boot.img` ，仍应配置特定于设备的验证启动链。

## 设备特定说明

本节包含有关如何将 AVB 集成到特定设备中的信息。这不是一个详尽的列表。

### Pixel 2 及以后

在 Pixel 2、Pixel 2 XL 及后续的 Pixel 型号上，引导加载器支持名为 `avb_custom_key` 的虚拟分区。此分区烧录和擦除仅在解锁状态下有效。设置自定义密钥的方法如下：

```
avbtool extract_public_key --key key.pem --output pkmd.bin
fastboot flash avb_custom_key pkmd.bin
```

擦除密钥是通过擦除虚拟分区来完成的：

```
fastboot erase avb_custom_key
```

当自定义密钥设置且设备处于锁定状态时，它将启动使用内置密钥和自定义密钥签名的映像。所有其他安全功能（包括回滚保护）均生效，例如，唯一的区别是使用的信任根。

启动使用自定义密钥签名的映像时，启动过程中将显示黄色屏幕，以提醒用户正在使用自定义密钥。

# 版本历史

### 版本 1.3

版本 1.3 增加了以下支持：

- 一个 32 位 `flags` 元素被添加到链描述符中。
- 支持不使用 A/B 的链分区。

### 版本 1.2

版本 1.2 增加了以下支持：

- 主 vbmeta 头字段 `rollback_index_location` 。
- `check_at_most_once` 哈希树描述符中的 dm-verity 参数。

### 版本 1.1

版本 1.1 添加了对以下内容的支持：

- 一个 32 位 `flags` 元素被添加到哈希和哈希树描述符中。
- 支持不使用 A/B 的分区。
- 防篡改命名持久值。
- 持久化哈希或哈希树描述符摘要。

### 版本 1.0

所有未在后续版本中明确列出的功能均由 1.0 版本支持。


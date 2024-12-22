# 20241202-Android AVB 到底该如何学习？

强哥最近在深入学习 Android AVB (Android Verify Boot) 机制，打算发布一些 AVB 相关的博客。

下面分享一些强哥学习 Android AVB 的一些想法。



关于程序，从宏观上看，程序由数据和围绕数据的一系列操作构成，所谓的操作主要是数据的增删改查，在类似 Android 这样的系统中，还包括配置和编译。

例如，Android 的 AVB，核心机制是 dm-verity，而这个核心机制依赖的是 vbmeta(verify boot meta) 数据，所以整个 AVB 就围绕 vbmeta 数据的配置，生成和使用(包括启动前的验证，以及 Android 启动过程中的文件系统的加载和映射)，以及一些其他操作如 rollback。



## AVB 的目的和原理

AVB 的核心是 dm-verity，对于 dm-verity，主要用于在 Android 系统启动后对 system, vendor 等分区的校验上，除了运行时的校验，还需要在启动时校验 boot 等分区。



所以，Android 启动时的校验(boot, dtbo等分区)，加上 Android 运行时的校验(system, vendor 等分区)，构成了 AVB。



对于 dm-verity，从较高的角度概括就是：

dm-verity 是一个 Linux 内核的块设备完整性验证机制，它通过在每次读取块设备时实时验证数据块的哈希值与预先计算好的 Merkle 哈希树进行比对，从而确保块设备内容未被篡改，主要用于保护 Android 设备的系统分区等只读分区的完整性。



具体上，

Android 系统在编译生成分区镜像时，预先计算各分区的 hash 值(小分区计算 hash 值，大分区通过 hash tree 的方式最终得到一个 root hash)，并保存起来。

在系统启动过程中，计算分区(boot, dtbo)的 hash 值，如果分区哪怕有 1 个 bit 被修改，分区的 hash 值都会发生改变。

此时，使用分区计算得到的 hash 同预先保存的 hash 值进行比较，来确保系统的分区没有被修改，例如 boot 分区。



但由于 system 这样的分区非常大，每次都去遍历一次 system 分区计算哈希需要较多资源(例如读取整个分区所需要的 IO，以及计算 hash 需要的 CPU)，导致每次都去重新计算 root hash 完全不现实。

因此，在 Android 系统启动后，通过 dm-verity 来保证 system 分区没有被篡改。



从整理上来说，Android AVB 是通过以下方式建议信任链(trust chain)来保证系统没有被篡改的：

1. 芯片中使用预先写入的 key 来校验 bootloader。 (这个 key 可能存储在芯片的 OTP 区域，或者加密后存放在外部存储上)
2. bootloader 叫验通过后，使用另一级的 key 来校验 boot 分区。（这个 key 可能存储在芯片的 OTP，或者嵌入在 bootloader 自身的代码中，或者其他不会被篡改的方式)
3. boot 分区启动后，通过 dm-verity 机制来确保 system, vendor 等分区没有被篡改。

因此，从 bootloader，到 kernel，到 Android 系统的整个信任链就建立起来了，保证了 Android 每一步的加载和启动，都是经过验证过的，因此称为 Android Verified Boot。



在大方向上了解了 AVB 的原理之后，接下来就是围绕核心数据 vbmeta 展开的一些列操作。
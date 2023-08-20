# 20230817-Android Update Engine 分析（二十一）Payload 科普

更新Payload生成

更新Payload生成是将一组分区/文件转换为既能被更新客户端(特别是较旧版本)理解,也能安全验证的格式的过程。这个过程涉及将输入分区分解成较小的组件并压缩以帮助下载Payload时的网络带宽。

`delta_generator`是一个具有广泛选项的工具,用于生成不同类型的更新Payload。其代码位于`update_engine/payload_generator`中。这个目录包含生成更新Payload的所有相关源代码。这个目录中的文件不应包含或用于`delta_generator`之外的任何其他库/可执行文件中,这意味着这个目录没有编译到更新引擎的其他工具中。

但是,不推荐直接使用`delta_generator`,因为它有太多的标志。应该使用像ota_from_target_files或OTA Generator这样的包装器。



更新Payload文件规范
每个更新Payload文件都有下表中定义的特定结构:

字段	大小(字节)	类型	描述
Magic Number	4	char[4]	魔数"CrAU",标识这是一个更新Payload
Major Version	8	uint64	Payload主版本号
Manifest Size	8	uint64	清单大小,以字节为单位
Manifest Signature Size	4	uint32	清单签名blob大小(字节),仅在主版本2中存在
Manifest	变化	DeltaArchiveManifest	要执行的操作列表
Manifest Signature	变化	Signatures	前五个字段的签名。如果密钥发生变化,可以有多个签名。
Payload Data	变化	List of raw or compressed data blobs	元数据中操作使用的二进制blob列表
Payload Signature Size	变化	uint64	Payload签名的大小
Payload Signature	变化	Signatures	整个Payload的签名,不包括元数据签名。如果密钥发生变化,可以有多个签名。



###  完整更新Payload vs 增量更新Payload

有两种类型的Payload:完整和增量。完整Payload仅从目标镜像(我们要更新到的镜像)生成,包含更新非活动分区所需的所有数据。因此,完整Payload的大小可能非常大。另一方面,增量Payload是通过比较源镜像(活动分区)和目标镜像并生成这两者之间的差异而生成的差异更新。它基本上是一个类似于`diff`或`bsdiff`等应用程序的差异更新。因此,使用增量Payload更新系统需要系统读取活动分区的部分内容,以便更新非活动分区(或重构目标分区)。增量Payload明显小于完整Payload。两种类型的Payload结构相同。

Payload生成非常耗费资源,其工具实现了高度的并行化。



#### 生成完整Payload

完整Payload是通过将分区划分为2MiB(可配置)的块,然后使用bzip2或XZ算法对其进行压缩,或者根据哪种可以生成更小的数据而保持为原始数据来生成的。与增量Payload相比,完整Payload要大得多,因此如果网络带宽受限,它们需要更长的下载时间。另一方面,应用完整Payload稍快一些,因为系统不需要从源分区读取数据。



#### 生成增量Payload

增量Payload是通过在文件和元数据级别(更精确地说是每个适当分区上的文件系统级别)查看源镜像数据和目标镜像数据来生成的。我们可以生成增量Payload的原因是Chrome OS分区是只读的。所以我们可以非常确定客户设备上活动分区的位比特与图像生成/签名阶段中生成的原始分区完全相同。生成增量Payload的过程大致如下:

1. 在目标分区上找到所有填充零的值块,并为它们生成“ZERO”操作。“ZERO”操作基本上会丢弃相关的块(取决于具体实现)。
2. 通过直接逐块比较源分区和目标分区,找到在源和目标分区之间未发生更改的所有块,并生成“SOURCE_COPY”操作。
3. 列出源分区和目标分区中的所有文件(及其相关块),并删除我们在最后两步中已经生成了操作的块(和文件)。将每个分区的剩余元数据(inode等)分配为一个文件。
4. 如果文件是新文件,根据哪个可以生成更小的数据块来为其数据块生成“REPLACE”、“REPLACE_XZ”或“REPLACE_BZ”操作。
5. 对于每个其他文件,比较源块和目标块,并根据哪个可以生成更小的数据块来生成“SOURCE_BSDIFF”或“PUFFDIFF”操作。这两个操作在源数据块和目标数据块之间生成二进制差异。(有关此类二进制差异程序的详细信息,请参阅bsdiff和puffin!)
6. 根据目标分区的块偏移量对操作进行排序。
7. 可选地将相邻的相同或相似操作合并为较大的操作,以提高效率和潜在的生成较小的Payload。

完整Payload只能包含“REPLACE”、“REPLACE_BZ”和“REPLACE_XZ”操作。增量Payload可以包含任何操作。



### 主版本号和次版本号

主版本号和次版本号分别指定更新Payload文件的格式以及更新客户端接受某些类型更新Payload的能力。这些数字在更新客户端中是硬编码的。

主版本号基本上就是上述更新Payload文件规范中的更新Payload文件版本(第二个字段)。每个更新客户端支持一系列主版本号。目前只有两个主版本:1和2。Chrome OS和Android目前都在主版本2上(主版本1正在被弃用)。每当有新添加的不能装入Manifest protobuf的内容时,我们需要提升主版本号。提升主版本号需要非常谨慎,因为旧客户端不知道如何处理新的版本。在Chrome OS中任何主版本号提升都应该与GoldenEye步进石相关联。

次版本号定义了更新客户端接受某些操作或执行某些操作的能力。每个更新客户端支持一系列次版本号。例如,次版本号为4(或更低)的更新客户端不知道如何处理“PUFFDIFF”操作。因此,在为次版本号为4(或更低)的镜像生成增量Payload时,我们不能为它生成PUFFDIFF操作。Payload生成过程会查看源镜像的次版本号以决定它支持的操作类型,并只生成符合那些限制的Payload。类似地,如果某个特定次版本号的客户端存在bug,提升次版本号有助于避免生成会导致该bug出现的Payload。但是,提升次版本号在可维护性方面代价也很高,并且可能容易出错。所以进行这种更改时也需要谨慎。

次版本号在完整Payload中无关紧要。完整Payload应该总是能够应用于非常旧的客户端。原因是更新客户端可能不会发送它们当前的版本,所以如果我们有不同类型的完整Payload,我们就不会知道为客户端提供哪个版本。



###  签名Payload vs 未签名Payload

更新Payload可以使用公钥/私钥对进行签名以用于生产环境,或者保持未签名状态以用于测试。像`delta_generator`这样的工具可以帮助生成元数据和Payload哈希或者使用给定的私钥对Payload进行签名。

对于生产环境,必须使用签名的Payload以确保安全性。未签名的Payload只应在测试环境中使用。

签名Payload需要额外的签名数据和验证过程,会增加Payload的大小。但这是确保更新过程安全所必需的。

生成签名Payload需要私钥。而验证签名需要对应的公钥。Key管理对于保证更新系统的安全至关重要。

总之,签名Payload用于生产以防止恶意修改。未签名Payload用于测试以加速开发。两者在使用场景上有明确区分。



## Update Payload Generation

The update payload generation is the process of converting a set of partitions/files into a format that is both understandable by the updater client (especially if it's a much older version) and is securely verifiable. This process involves breaking the input partitions into smaller components and compressing them in order to help with network bandwidth when downloading the payloads.

`delta_generator` is a tool with a wide range of options for generating different types of update payloads. Its code is located in `update_engine/payload_generator`. This directory contains all the source code related to mechanics of generating an update payload. None of the files in this directory should be included or used in any other library/executable other than the `delta_generator` which means this directory does not get compiled into the rest of the update engine tools.

However, it is not recommended to use `delta_generator` directly, as it has way too many flags. Wrappers like [ota*from*target_files](https://cs.android.com/android/platform/superproject/+/master:build/make/tools/releasetools/ota_from_target_files.py) or [OTA Generator](https://github.com/google/ota-generator) should be used.

### Update Payload File Specification

Each update payload file has a specific structure defined in the table below:

| Field                   | Size (bytes) | Type                                                         | Description                                                  |
| ----------------------- | ------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| Magic Number            | 4            | char[4]                                                      | Magic string "CrAU" identifying this is an update payload.   |
| Major Version           | 8            | uint64                                                       | Payload major version number.                                |
| Manifest Size           | 8            | uint64                                                       | Manifest size in bytes.                                      |
| Manifest Signature Size | 4            | uint32                                                       | Manifest signature blob size in bytes (only in major version 2). |
| Manifest                | Varies       | [DeltaArchiveManifest](http://aospxref.com/update_metadata.proto#302) | The list of operations to be performed.                      |
| Manifest Signature      | Varies       | [Signatures](http://aospxref.com/update_metadata.proto#122)  | The signature of the first five fields. There could be multiple signatures if the key has changed. |
| Payload Data            | Varies       | List of raw or compressed data blobs                         | The list of binary blobs used by operations in the metadata. |
| Payload Signature Size  | Varies       | uint64                                                       | The size of the payload signature.                           |
| Payload Signature       | Varies       | [Signatures](http://aospxref.com/update_metadata.proto#122)  | The signature of the entire payload except the metadata signature. There could be multiple signatures if the key has changed. |

### Delta vs. Full Update Payloads

There are two types of payload: Full and Delta. A full payload is generated solely from the target image (the image we want to update to) and has all the data necessary to update the inactive partition. Hence, full payloads can be quite large in size. A delta payload, on the other hand, is a differential update generated by comparing the source image (the active partitions) and the target image and producing the diffs between these two images. It is basically a differential update similar to applications like `diff` or `bsdiff`. Hence, updating the system using the delta payloads requires the system to read parts of the active partition in order to update the inactive partition (or reconstruct the target partition). The delta payloads are significantly smaller than the full payloads. The structure of the payload is equal for both types.

Payload generation is quite resource intensive and its tools are implemented with high parallelism.

#### Generating Full Payloads

A full payload is generated by breaking the partition into 2MiB (configurable) chunks and either compressing them using bzip2 or XZ algorithms or keeping it as raw data depending on which produces smaller data. Full payloads are much larger in comparison to delta payloads hence require longer download time if the network bandwidth is limited. On the other hand, full payloads are a bit faster to apply because the system doesn’t need to read data from the source partition.

#### Generating Delta Payloads

Delta payloads are generated by looking at both the source and target images data on a file and metadata basis (more precisely, the file system level on each appropriate partition). The reason we can generate delta payloads is that Chrome OS partitions are read only. So with high certainty we can assume the active partitions on the client’s device is bit-by-bit equal to the original partitions generated in the image generation/signing phase. The process for generating a delta payload is roughly as follows:

1. Find all the zero-filled blocks on the target partition and produce `ZERO` operation for them. `ZERO` operation basically discards the associated blocks (depending on the implementation).
2. Find all the blocks that have not changed between the source and target partitions by directly comparing one-to-one source and target blocks and produce `SOURCE_COPY` operation.
3. List all the files (and their associated blocks) in the source and target partitions and remove blocks (and files) which we have already generated operations for in the last two steps. Assign the remaining metadata (inodes, etc) of each partition as a file.
4. If a file is new, generate a `REPLACE`, `REPLACE_XZ`, or `REPLACE_BZ` operation for its data blocks depending on which one generates a smaller data blob.
5. For each other file, compare the source and target blocks and produce a `SOURCE_BSDIFF` or `PUFFDIFF` operation depending on which one generates a smaller data blob. These two operations produce binary diffs between a source and target data blob. (Look at [bsdiff](https://android.googlesource.com/platform/external/bsdiff/+/master) and [puffin](https://android.googlesource.com/platform/external/puffin/+/master) for details of such binary differential programs!)
6. Sort the operations based on their target partitions’ block offset.
7. Optionally merge same or similar operations next to each other into larger operations for better efficiency and potentially smaller payloads.

Full payloads can only contain `REPLACE`, `REPLACE_BZ`, and `REPLACE_XZ` operations. Delta payloads can contain any operations.

### Major and Minor versions

The major and minor versions specify the update payload file format and the capability of the updater client to accept certain types of update payloads respectively. These numbers are [hard coded](http://aospxref.com/update_engine.conf) in the updater client.

Major version is basically the update payload file version specified in the [update payload file specification](http://aospxref.com/android-13.0.0_r3/xref/system/update_engine/#update-payload-file-specification) above (second field). Each updater client supports a range of major versions. Currently, there are only two major versions: 1, and 2. And both Chrome OS and Android are on major version 2 (major version 1 is being deprecated). Whenever there are new additions that cannot be fitted in the [Manifest protobuf](http://aospxref.com/update_metadata.proto), we need to uprev the major version. Upreving major version should be done with utmost care because older clients do not know how to handle the newer versions. Any major version uprev in Chrome OS should be associated with a GoldenEye stepping stone.

Minor version defines the capability of the updater client to accept certain operations or perform certain actions. Each updater client supports a range of minor versions. For example, the updater client with minor version 4 (or less) does not know how to handle a `PUFFDIFF` operation. So when generating a delta payload for an image which has an updater client with minor version 4 (or less) we cannot produce PUFFDIFF operation for it. The payload generation process looks at the source image’s minor version to decide the type of operations it supports and only a payload that confirms to those restrictions. Similarly, if there is a bug in a client with a specific minor version, an uprev in the minor version helps with avoiding to generate payloads that cause that bug to manifest. However, upreving minor versions is quite expensive too in terms of maintainability and it can be error prone. So one should practice caution when making such a change.

Minor versions are irrelevant in full payloads. Full payloads should always be able to be applied for very old clients. The reason is that the updater clients may not send their current version, so if we had different types of full payloads, we would not have known which version to serve to the client.

### Signed vs Unsigned Payloads

Update payloads can be signed (with private/public key pairs) for use in production or be kept unsigned for use in testing. Tools like `delta_generator` help with generating metadata and payload hashes or signing the payloads given private keys.



---

好的,我来翻译这篇文章的内容:

Chrome OS更新过程

内容提要

A/B更新的生命周期
生成
分发/配置
安装
更新引擎守护进程  
交互式vs非交互式vs强制更新
网络
日志
更新Payload生成
更新Payload文件规范
增量vs完整更新Payload
主要和次要版本号
签名vs未签名Payload
update_payload脚本
安装后步骤
构建更新引擎
设置
构建
运行单元测试
启动配置的更新
开发者和维护者须知
不要破坏向后兼容性
考虑未来
优先不要在更新客户端实现您的功能
尊重其他代码库
从Android(或其他代码库)合并

在较现代的操作系统(如Chrome OS和Android)中,系统更新被称为A/B更新、无线(OTA)更新、无缝更新或简单的自动更新。与需要启动到特殊模式来重写系统分区的更原始的系统更新(如Windows或macOS)相比,A/B更新有几个优点,包括但不限于:

- 更新可以在系统运行时进行(通常开销很小),不会中断用户。用户唯一的缺点是需要重新启动(或在Chrome OS中注销,如果执行了需要重新启动的更新,重新启动大约需要10秒,与正常重新启动无异)。

- 用户不需要(尽管可以)请求更新。后台会定期检查更新。  

- 如果更新失败,用户不受影响。用户将继续使用旧版本系统,系统将在以后某个时间再次尝试应用更新。

- 如果更新正确应用但无法启动,系统将回滚到旧分区,用户仍然可以像往常一样使用系统。

- 用户不需要为更新预留足够的空间。系统已经通过两个分区副本(A和B)预留了足够的空间。系统甚至不需要任何磁盘缓存,一切都从网络无缝地通过内存传输到非活动分区。

A/B更新的生命周期

在支持A/B更新的系统中,每个分区(如内核或根目录)都有两个副本。我们将这两个副本称为活动(A)和非活动(B)。系统启动到活动分区(根据哪个副本在启动时具有更高优先级),当有新的更新可用时,它将被写入非活动分区。成功重启后,之前的非活动分区变成活动的,旧的活动分区变成非活动的。

生成

但一切都始于为每个新系统镜像在(谷歌)服务器上生成OTA软件包。这是通过调用带有源和目标构建的ota_from_target_files脚本完成的。此脚本需要target_file.zip才能工作,镜像文件是不够的。

分发/配置  

生成OTA包后,使用特定密钥对其进行签名并存储在更新服务器(GOTA)已知的位置。然后,GOTA将通过公共URL使该OTA更新可用。可选地,运营商可以选择仅针对特定子集的设备提供此OTA更新。

安装

当设备的更新客户端启动更新(周期性地或用户启动)时,它首先会查询不同的设备策略以查看是否允许更新检查。例如,设备策略可以在一天中的某些时间防止更新检查,或者要求随机分散更新检查时间等。

一旦策略允许更新检查,更新客户端就会向更新服务器发送请求(所有此通信都是通过HTTPS进行的),并标识其参数,如其应用程序ID、硬件ID、版本、板等。

服务器上的一些策略可能会阻止设备获取特定的OTA更新,这些服务器端策略通常由运营商设置。例如,运营商可能希望仅将测试软件的版本交付给一子集设备。

但是,如果更新服务器决定提供更新包,它将以执行更新所需的所有参数做出响应,如Payload下载URL、元数据签名、Payload大小和哈希值等。在不同状态变化后,更新客户端会继续与更新服务器通信,比如报告它开始下载Payload或完成更新,或者使用特定错误代码报告更新失败等。

然后,设备将实际安装OTA更新。这大致分为3个步骤。

下载和安装

每个Payload由两个主要部分组成:元数据和额外数据。元数据基本上是要执行的操作列表。额外数据包含某些或所有这些操作所需的数据blob。更新客户端首先下载元数据,并使用更新服务器响应中提供的签名对其进行加密验证。一旦验证元数据有效,则可以轻松使用加密(主要通过SHA256哈希)验证Payload的其余部分。

接下来,更新客户端将非活动分区标记为不可启动(因为它需要将新更新写入其中)。至此,系统无法再回滚到非活动分区。

然后,更新客户端按照元数据中出现的顺序执行定义的操作(当这些操作需要其数据时会逐步下载其余的Payload)。一次操作完成后,其数据将被丢弃。这消除了在应用之前缓存整个Payload的需要。在此过程中,更新客户端会定期检查上一个执行的操作,以便在出现故障或系统关闭等情况时,它可以从错过的点继续,而不必从头重新执行所有操作。

在下载期间,更新客户端会对下载的字节进行哈希运算,当下载完成时,它会检查Payload签名(位于Payload末尾)。如果无法验证签名,则拒绝更新。

哈希验证和校验计算

在非活动分区更新后,更新客户端将为每个分区计算前向错误校正码(也称为FEC、校验),并将计算的校验数据写入非活动分区。在某些更新中,校验数据包含在额外数据中,所以此步骤将被跳过。 

然后,重新读取整个分区、计算哈希并与元数据中传递的哈希值进行比较,以确保更新已成功写入分区。此步骤中计算的哈希值包括上一步中写入的校验码。

安装后步骤

在下一步中,如果有的话,调用Postinstall脚本。从OTA的角度来看,这些Postinstall脚本就是黑盒。通常Postinstall脚本将优化存在的应用程序和运行文件系统垃圾回收,以便设备可以在OTA后快速启动。但这些是由其他团队管理的。

最后调整

然后,更新客户端进入一种状态,指示更新已完成,用户需要重新启动系统。在这一点上,在用户重新启动(或注销)之前,更新客户端即使有更新的更新也不会执行任何更多的系统更新。但是,它确实会继续执行定期的更新检查,以便我们可以统计字段中的活动设备数量。

证明更新成功后,非活动分区被标记为具有更高的优先级(在启动时,具有更高优先级的分区会先启动)。一旦用户重新启动系统,它将启动更新后的分区,并将其标记为活动分区。在重新启动后,update_verifier程序会运行,读取所有dm-verity设备以确保分区没有损坏,然后标记更新为成功。

此时A/B更新就被认为已完成。虚拟A/B更新之后还有一步称为“合并”。合并通常需要几分钟,之后虚拟A/B更新被认为是完整的。

更新引擎守护进程

update_engine是一个单线程守护进程,始终运行。这个进程是自动更新的核心。它在后台以较低优先级运行,是系统启动后最后启动的进程之一。不同的客户端(如GMS Core或其他服务)可以向更新引擎发送更新检查请求。关于如何将请求传递给更新引擎的详情因系统而异,但在Chrome OS中是D-Bus。查看D-Bus接口以获取所有可用方法的列表。在Android上是binder。

更新引擎中嵌入了许多弹性功能,使自动更新强大,包括但不限于:

- 如果更新引擎崩溃,它将自动重启。

- 在活动更新期间,它会定期检查更新状态,如果无法继续更新或在中间崩溃,它将从最后一个检查点继续。

- 它会重试失败的网络通信。

- 如果由于活动分区上的位变化导致增量Payload应用失败几次,它会切换到完整Payload。

更新客户端会将其活动首选项写入/data/misc/update_engine/prefs。这些首选项有助于跟踪更新客户端生命周期中的更改,并允许在失败尝试或崩溃后正确继续更新过程。

交互式 vs 非交互式 vs 强制更新

非交互式更新是更新引擎定期计划的更新,在后台进行。另一方面,交互式更新发生在用户明确请求更新检查时(例如,通过点击Chrome OS“关于”页面上的“检查更新”按钮)。

根据更新服务器的策略,交互式更新比非交互式更新具有更高的优先级(通过携带标记提示)。当服务器负载繁忙时等,它们可以决定不提供更新。这两种类型的更新之间也存在其他内部差异。例如,交互式更新试图更快地安装更新。

强制更新类似于交互式更新(由某种用户操作启动),但它们也可以配置为像非交互式一样运行。由于非交互式更新定期发生,强制非交互式更新会在请求时立即触发非交互式更新,而不是在稍后时间。我们可以使用以下命令调用强制非交互式更新:

update_engine_client --interactive=false --check_for_update

网络

根据设备连接的网络,更新客户端可以通过以太网、WiFi或蜂窝网络下载Payload。通过蜂窝网络下载会需要用户许可,因为它可能会消耗大量数据。

日志

在Chrome OS中,update_engine日志位于/var/log/update_engine目录中。每当update_engine启动时,它都会使用当前日期时间格式启动一个新的日志文件,日志文件名中包含日期时间(update_engine.log-DATE-TIME)。在更新引擎重新启动或系统重新启动几次后,/var/log/update_engine中会出现许多日志文件。最新的活动日志通过符号链接/var/log/update_engine.log链接。

在Android中,update_engine日志位于/data/misc/update_engine_log中。

更新Payload生成

更新Payload生成是将一组分区/文件转换为既能被更新客户端(特别是较旧版本)理解,也能安全验证的格式的过程。这个过程涉及将输入分区分解成较小的组件并压缩以帮助下载Payload时的网络带宽。

delta_generator是一个具有广泛选项的工具,用于生成不同类型的更新Payload。其代码位于update_engine/payload_generator中。这个目录包含生成更新Payload的所有相关源代码。这个目录中的文件不应包含或用于delta_generator之外的任何其他库/可执行文件中,这意味着这个目录没有编译到更新引擎的其他工具中。

但是,不推荐直接使用delta_generator,因为它有太多的标志。应该使用像ota_from_target_files或OTA Generator这样的包装器。

更新Payload文件规范

每个更新Payload文件都有下表中定义的特定结构:

字段	大小(字节)	类型	描述
Magic Number	4	char[4]	魔数"CrAU",标识这是一个更新Payload
Major Version	8	uint64	Payload主版本号  
Manifest Size	8	uint64	清单大小,以字节为单位
Manifest Signature Size	4	uint32	清单签名blob大小(字节),仅在主版本2中存在
Manifest	变化	DeltaArchiveManifest	要执行的操作列表  
Manifest Signature	变化	Signatures	前五个字段的签名。如果密钥发生变化,可以有多个签名。
Payload Data	变化	List of raw or compressed data blobs	元数据中操作使用的二进制blob列表
Payload Signature Size	变化	uint64	Payload签名的大小
Payload Signature	变化	Signatures	整个Payload的签名,不包括元数据签名。如果密钥发生变化,可以有多个签名。

增量 vs 完整更新Payload

有两种类型的Payload:完整和增量。完整Payload仅从目标镜像(我们要更新到的镜像)生成,包含更新非活动分区所需的所有数据。因此,完整Payload的大小可能非常大。另一方面,增量Payload是通过比较源镜像(活动分区)和目标镜像并生成这两者之间的差异而生成的差异更新。它基本上是一个类似于diff或bsdiff等应用程序的差异更新。因此,使用增量Payload更新系统需要系统读取活动分区的部分内容,以便更新非活动分区(或重构目标分区)。增量Payload明显小于完整Payload。两种类型的Payload结构相同。

Payload生成非常耗费资源,其工具实现了高度的并行化。 

生成完整Payload

完整Payload是通过将分区划分为2MiB(可配置)的块,然后使用bzip2或XZ算法对其进行压缩,或者根据哪种可以生成更小的数据而保持为原始数据来生成的。与增量Payload相比,完整Payload要大得多,因此如果网络带宽受限,它们需要更长的下载时间。另一方面,应用完整Payload稍快一些,因为系统不需要从源分区读取数据。

生成增量Payload

增量Payload是通过在文件和元数据级别(更精确地说是每个适当分区上的文件系统级别)查看源镜像数据和目标镜像数据来生成的。我们可以生成增量Payload的原因是Chrome OS分区是只读的。所以我们可以非常确定客户设备上活动分区的位比特与图像生成/签名阶段中生成的原始分区完全相同。生成增量Payload的过程大致如下: 

1. 在目标分区上找到所有填充零的值块,并为它们生成“ZERO”操作。“ZERO”操作基本上会丢弃相关的块(取决于具体实现)。

2. 通过直接逐块比较源分区和目标分区,找到在源和目标分区之间未发生更改的所有块,并生成“SOURCE_COPY”操作。

3. 列出源分区和目标分区中的所有文件(及其相关块),并删除我们在最后两步中已经生成了操作的块(和文件)。将每个分区的剩余元数据(inode等)分配为一个文件。

4. 如果文件是新文件,根据哪个可以生成更小的数据块来为其数据块生成“REPLACE”、“REPLACE_XZ”或“REPLACE_BZ”操作。 

5. 对于每个其他文件,比较源块和目标块,并根据哪个可以生成更小的数据块来生成“SOURCE_BSDIFF”或“PUFFDIFF”操作。这两个操作在源数据块和目标数据块之间生成二进制差异。(有关此类二进制差异程序的详细信息,请参阅bsdiff和puffin!)

6. 根据目标分区的块偏移量对操作进行排序。 

7. 可选地将相邻的相同或

类似操作合并为较大的操作,以提高效率和潜在的生成较小的Payload。

完整Payload只能包含“REPLACE”、“REPLACE_BZ”和“REPLACE_XZ”操作。增量Payload可以包含任何操作。

主要和次要版本号

主版本号和次版本号分别指定更新Payload文件的格式以及更新客户端接受某些类型更新Payload的能力。这些数字在更新客户端中是硬编码的。

主版本号基本上就是上述更新Payload文件规范中的更新Payload文件版本(第二个字段)。每个更新客户端支持一系列主版本号。目前只有两个主版本:1和2。Chrome OS和Android目前都在主版本2上(主版本1正在被弃用)。每当有新添加的不能装入Manifest protobuf的内容时,我们需要提升主版本号。提升主版本号需要非常谨慎,因为旧客户端不知道如何处理新的版本。在Chrome OS中任何主版本号提升都应该与GoldenEye步进石相关联。

次版本号定义了更新客户端接受某些操作或执行某些操作的能力。每个更新客户端支持一系列次版本号。例如,次版本号为4(或更低)的更新客户端不知道如何处理“PUFFDIFF”操作。所以在为次版本号为4(或更低)的镜像生成增量Payload时,我们不能为它生成PUFFDIFF操作。Payload生成过程会查看源镜像的次版本号以决定它支持的操作类型,并只生成符合那些限制的Payload。类似地,如果某个特定次版本号的客户端存在bug,提升次版本号有助于避免生成会导致该bug出现的Payload。但是,提升次版本号在可维护性方面代价也很高,并且可能容易出错。所以进行这种更改时也需要谨慎。  

次版本号在完整Payload中无关紧要。完整Payload应该总是能够应用于非常旧的客户端。原因是更新客户端可能不会发送它们当前的版本,所以如果我们有不同类型的完整Payload,我们就不会知道为客户端提供哪个版本。

签名 vs 未签名Payload

更新Payload可以使用公钥/私钥对进行签名以用于生产环境,或者保持未签名状态以用于测试。像delta_generator这样的工具可以帮助生成元数据和Payload哈希或者使用给定的私钥对Payload进行签名。

对于生产环境,必须使用签名的Payload以确保安全性。未签名的Payload只应在测试环境中使用。

签名Payload需要额外的签名数据和验证过程,会增加Payload的大小。但这是确保更新过程安全所必需的。

生成签名Payload需要私钥。而验证签名需要对应的公钥。Key管理对于保证更新系统的安全至关重要。

总之,签名Payload用于生产以防止恶意修改。未签名Payload用于测试以加速开发。两者在使用场景上有明确区分。

update_payload脚本

update_payload包含一组python脚本,主要用于验证Payload生成和应用。我们通常使用实际设备(实时测试)来测试更新Payload。brillo_update_payload脚本可用于在主机设备上生成和测试应用payload。这些测试可以看作是没有实际设备的动态测试。其他update_payload脚本(如check_update_payload)可用于静态检查payload是否处于正确状态以及其应用是否正常工作。这些脚本实际上是静态应用payload,而不运行payload_consumer中的代码。

安装后步骤 

Postinstall是在更新客户端将新镜像构件写入非活动分区后调用的过程。Postinstall的主要职责之一是在根分区末尾重新创建dm-verity树哈希。除此之外,它还会安装新的固件更新或任何特定的板卡流程。Postinstall在新安装的分区内的一个单独的chroot中运行。所以它与活动运行的系统是完全分离的。在更新之后和设备重启之前需要完成的任何事情都应该在postinstall中实现。

构建更新引擎

你可以像构建其他平台应用程序一样构建update_engine:

设置

在构建任何内容之前,请在Android存储库顶部运行这些命令。每个shell只需要执行一次。

source build/envsetup.sh
lunch aosp_cf_x86_64_only_phone-userdebug(或用自己的目标替换aosp_cf_x86_64_only_phone-userdebug)

构建

m update_engine update_engine_client delta_generator

运行单元测试

运行单元测试类似于其他平台:

atest update_engine_unittests 你需要一个连接到笔记本电脑并通过ADB可访问的设备来执行此操作。Cuttlefish也可以使用。

atest update_engine_host_unittests 在主机上运行一部分测试,不需要设备。

启动配置的更新

有几种方法可以启动更新:

- 单击“设置”的“关于”页面上的“检查更新”按钮。无法配置此更新检查方式。

- 使用 [scripts/update_device.py] 程序并传递OTA zip文件的路径。

开发者和维护者须知

更改update engine源代码时要特别小心这些事项:

不要破坏向后兼容性

在每个发布周期,我们都应该能够生成完整和增量Payload,可以正确应用于运行旧版本更新引擎客户端的旧设备。例如,在元数据proto文件中删除、不传递参数可能会损坏旧客户端。或者传递旧客户端不理解的操作也会损坏它们。无论何时更改Payload生成过程中的任何内容,都要问自己这个问题:它能在旧客户端上工作吗?如果不行,我需要用次要版本或任何其他方式来控制它吗。

特别是关于企业回滚,新的更新客户端应该能够接受较旧的更新Payload。通常这是通过完整Payload完成的,但应该注意不要破坏这种兼容性。

考虑未来

在update engine中进行更改时,要考虑5年后的情况:

- 如何实现此更改,以使5年后的旧客户端不会中断?

- 5年后如何维护它?

- 如何进行更改以方便未来的更改而不破坏旧客户端或增加沉重的维护成本?

优先不要在更新客户端实现您的功能

如果一个功能可以通过服务器端实现,请不要在客户端更新程序中实现它。因为客户端更新程序在某些点上可能脆弱,小错误可能会造成灾难性后果。例如,如果在更新客户端中引入一个导致其在检查更新之前崩溃的bug,并且我们无法及早在发布过程中捕捉到此bug,那么已经升级到新bug系统的生产设备就可能不再接收自动更新了。因此,总是要考虑是否可以通过服务器端实现要实现的功能(可能对客户端更新程序进行最小更改)?或者该功能是否可以移至与更新客户端接口最小的其他服务中?回答这些问题在未来会有很大回报。

尊重其他代码库

~~当前的update engine代码库在许多项目(如Android)中使用。~~

Android和ChromeOS代码库已正式分支。

我们经常在这两个项目之间同步代码库。请注意不要破坏Android或其他共享update engine代码的系统。每当提交更改时,务必考虑Android是否需要该更改:

- 它将如何影响Android?

- 是否可以将更改移动到接口,并实现存根实现,以免影响Android?  

- Chrome OS或Android特定的代码是否可以用宏进行保护?

作为一个基本措施,如果添加/删除/重命名代码,请确保同时更改build.gn和Android.bp。不要将Chrome OS特定的代码(例如system_api或dlcservice中的其他库)带入update_engine的通用代码。尽量使用最佳软件工程实践来区分这些问题。

从Android(或其他代码库)合并

Chrome OS将Android代码作为上游分支跟踪。要将Android代码合并到Chrome OS(反之亦然),只需将该分支合并到Chrome OS中,使用任何方法测试它,然后上传合并提交。

repo start merge-aosp
git merge --no-ff --strategy=recursive -X patience cros/upstream  
repo upload --cbr --no-verify .
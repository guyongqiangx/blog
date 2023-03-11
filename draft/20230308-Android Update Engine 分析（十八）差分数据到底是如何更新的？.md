# 20230308-Android Update Engine 分析（十八）差分数据到底是如何更新的？

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 原文链接：https://blog.csdn.net/guyongqiangx/article/details/129464805

## 0. 导读

过去一直以来陆续有朋友问，差分数据到底是如何更新的？其实我一开始在这个问题上也犯了错误，没搞清楚整个分区更新流程。本文详细跟踪差分数据接收到以后，manifest 数据时如何被解析和使用，InstallOperation 数据又是如何被用于更新的。



如果只想了解差分升级的基本原理，请参考第 1 节，系统升级的 3 个阶段；

如果想了解数据被设备接收到后，又是如何被 Write() 函数调用的，请参考第 2 节；

如果只想了解 payload.bin 的数据结构，请参考 3.1 节 payload.bin 结构图；

如果想看 Wirte() 函数的详细注释，请参考 3.2 节；

如果想了解分区文件描述符在哪里打开，又在哪里被使用，请参考第 3.3， 3.4 节；



如果觉得全文分析代码都太啰嗦，请直接跳转到第 4 节看下总结。



> 核心代码[《Android Update Engine 分析》](https://blog.csdn.net/guyongqiangx/category_12140296.html)系列，文章列表：
>
> - [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)
>
> - [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)
>
> - [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)
>
> - [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)
>
> - [Android Update Engine分析（五）服务端核心之Action机制](https://blog.csdn.net/guyongqiangx/article/details/82226079)
>
> - [Android Update Engine分析（六）服务端核心之Action详解](https://blog.csdn.net/guyongqiangx/article/details/82390015)
>
> - [Android Update Engine分析（七） DownloadAction之FileWriter](https://blog.csdn.net/guyongqiangx/article/details/82805813)
>
> - [Android Update Engine分析（八）升级包制作脚本分析](https://blog.csdn.net/guyongqiangx/article/details/82871409)
>
> - [Android Update Engine分析（九） delta_generator 工具的 6 种操作](https://blog.csdn.net/guyongqiangx/article/details/122351084)
>
> - [Android Update Engine分析（十） 生成 payload 和 metadata 的哈希](https://blog.csdn.net/guyongqiangx/article/details/122393172)
>
> - [Android Update Engine分析（十一） 更新 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122597314)
>
> - [Android Update Engine 分析（十二） 验证 payload 签名](https://blog.csdn.net/guyongqiangx/article/details/122634221)
>
> - [Android Update Engine分析（十三） 提取 payload 的 property 数据](https://blog.csdn.net/guyongqiangx/article/details/122646107)
>
> - [Android Update Engine分析（十四） 生成 payload 数据](https://blog.csdn.net/guyongqiangx/article/details/122753185)
>
> - [Android Update Engine 分析（十五） FullUpdateGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122767273)
>
> - [Android Update Engine 分析（十六） ABGenerator 策略](https://blog.csdn.net/guyongqiangx/article/details/122886150)
>
> - [Android Update Engine 分析（十七）10 类 InstallOperation 数据的生成和应用](https://blog.csdn.net/guyongqiangx/article/details/122942628)
>
> - [Android Update Engine 分析（十八）差分数据到底是如何更新的？](https://blog.csdn.net/guyongqiangx/article/details/129464805)

>  如果您已经订阅了本专栏，请务必加我微信，拉你进“动态分区 & 虚拟分区专栏 VIP 答疑群”。

## 1. 系统升级的 3 个阶段

从宏观上说，整个差分升级过程大致分成三步：

假设升级前的旧系统为 V1, 升级后的新系统为 V2, 差分数据为 Delta

1. 制作差分包

   利用新旧的镜像文件生成差分数据，并打包到 payload.bin 文件中，得到差分包升级文件；

   即：V2(新) - V1(旧) = Delta(差分)

   

2. 传输差分包

   服务端将差分包数据传输给设备端。可以是网络传输，也可以是通过 U 盘复制；

   即：Server(Delta) -> Device(Delta)

   

3. 还原差分包

   设备端接收到差分包升级文件后，基于旧分区，使用差分数据还原，得到新分区数据；

   即：V1(旧) + Delta(差分) = V2(新)



通过上面的这 3 个步骤，利用系统上已有的旧系统 V1 的镜像，通过差分数据 Delta，而不需要传输新系统 V2 的全部镜像文件即可完成升级。



我们这一些系列前面的很多篇都在分析差分包是如何制作，如何传输的。

系统升级，设备端的核心是如何利用接收到的差分数据，基于旧分区数据还原得到新分区。

回到代码上，这个核心就是函数 `DeltaPerformer::Write`。要想了解数据到底是如何更新的，那就离不开这个函数。



## 2. DelaterPerformer 类的 Write 函数是如何被调用的？

在[《Android Update Engine分析（七） DownloadAction之FileWriter》](https://guyongqiangx.blog.csdn.net/article/details/82805813)分析过，通过网络接收到数据，或者通过文件读取到数据以后，DownloadAction 的`ReceivedBytes()`函数被回调，在其内部会进一步调用 DownloadAction 内部成员 `writer_` 的`Write()`函数写入接收到的数据。

具体内容请参考下面关于函数 `RecivedBytes` 的注释：

```c++
void DownloadAction::ReceivedBytes(HttpFetcher* fetcher,
                                   const void* bytes,
                                   size_t length) {
  // Note that bytes_received_ is the current offset.
  if (!p2p_file_id_.empty()) {
    WriteToP2PFile(bytes, length, bytes_received_);
  }

  /*
   * 1. 累加接收到的数据长度，保存在 bytes_received_ 中
   */
  bytes_received_ += length;
  
  /*
   * 2. 回调 delegate_ 对象的 BytesReceived 函数对数据进行处理
   */
  if (delegate_ && download_active_) {
    delegate_->BytesReceived(
        length, bytes_received_, install_plan_.payload_size);
  }
  
  /*
   * 3. 回调 writer_ 对象的 Write 函数对接收到的数据进行处理
   */
  if (writer_ && !writer_->Write(bytes, length, &code_)) {
    LOG(ERROR) << "Error " << code_ << " in DeltaPerformer's Write method when "
               << "processing the received payload -- Terminating processing";
    // Delete p2p file, if applicable.
    if (!p2p_file_id_.empty())
      CloseP2PSharingFd(true);
    // Don't tell the action processor that the action is complete until we get
    // the TransferTerminated callback. Otherwise, this and the HTTP fetcher
    // objects may get destroyed before all callbacks are complete.
    TerminateProcessing();
    return;
  }

  // Call p2p_manager_->FileMakeVisible() when we've successfully
  // verified the manifest!
  if (!p2p_visible_ && system_state_ && delta_performer_.get() &&
      delta_performer_->IsManifestValid()) {
    LOG(INFO) << "Manifest has been validated. Making p2p file visible.";
    system_state_->p2p_manager()->FileMakeVisible(p2p_file_id_);
    p2p_visible_ = true;
  }
}
```

这个函数中，除了 `p2p_file_id_` 相关的代码外，剩余的代码做了 3 件事：

1. 累加接收到的数据长度，保存在 bytes_received_ 中；
2. 回调 delegate_ 对象的 BytesReceived 函数对数据进行处理；
3. 回调 writer_ 对象的 Write 函数对接收到的进行处理

而这里的 `delegate_ ` 对象，在 DownloadAction 的构造函数中初始化为 `delegate_(nullptr)`，所以这里的第 2 步并没有被执行。



至于 writer_ 成员，是在哪里初始化的呢？这里我不再卖关子了，DownloadAction 的 writer_ 成员在 `PerformActionn()` 中被设置为 DeltaPerformer 类的对象。

下面的 `PerformAction()` 展示了 writer_ 成员被初始化为 DeltaPerformer 的类对象：

```c++
/* file: system/update_engine/payload_consumer/download_action.cc */
void DownloadAction::PerformAction() {
  http_fetcher_->set_delegate(this);

  // Get the InstallPlan and read it
  CHECK(HasInputObject());
  install_plan_ = GetInputObject();
  bytes_received_ = 0;

  install_plan_.Dump();

  LOG(INFO) << "Marking new slot as unbootable";
  if (!boot_control_->MarkSlotUnbootable(install_plan_.target_slot)) {
    LOG(WARNING) << "Unable to mark new slot "
                 << BootControlInterface::SlotName(install_plan_.target_slot)
                 << ". Proceeding with the update anyway.";
  }

  // 在 DownloadAction 的构造函数中，writer 成员被初始化为空指针: writer_(nullptr)，所以这里走 else
  if (writer_) {
    LOG(INFO) << "Using writer for test.";
  } else {
    // 使用 DeltaPerformer 的类对象初始化 writer_ 成员
    delta_performer_.reset(new DeltaPerformer(
        prefs_, boot_control_, hardware_, delegate_, &install_plan_));
    writer_ = delta_performer_.get();
  }
  download_active_ = true;

  //...
}
```



所以，回到 DownloadAction 的 ReceivedBytes() 函数:

 `writer_->Write()` 实质上就是 `DeltaPerformer->Write()`



所以本文后面的内容都围绕 DeltaPerformer 类的 `Write()` 函数进行。



> 思考题：DownloadAction 的`ReceivedBytes()`函数是如何被调用的？或者说是在哪里被调用的？

## 3. 分区数据更新流程分析

DeltaPerformer 类的 Write 函数是整个升级的核心，了解了 Write 函数的操作流程，你就知道设备端接收到升级数据以后到底是如何进行处理的。



### 1. payload 数据结构

Write 函数操作的对象是 payload 数据，所以，这里对照 payload 数据的结构进行理解会更佳，我这里附上很早以前画的基于 Android 7.1 的 payload 数据结构框图:

![img](images-20230308-Android Update Engine 分析（十八）/70.png)

图 1. payload 数据结构框图



更多关于 payload 数据结构定义的细节，请参考 update_engine 中 payload 数据的 protobuf 定义：

`system/update_engine/update_metadata.proto`



### 2. DeltaPerformer 类的 Write 函数注释

我在[《Android Update Engine分析（七） DownloadAction之FileWriter》](https://guyongqiangx.blog.csdn.net/article/details/82805813)分析过这个 Write 函数，我在这里再把 Write 函数简单注释总结一下：

```c++
/* file: system/update_engine/payload_consumer/delta_performer.cc */

// Wrapper around write. Returns true if all requested bytes
// were written, or false on any error, regardless of progress
// and stores an action exit code in |error|.
bool DeltaPerformer::Write(const void* bytes, size_t count, ErrorCode *error) {
  *error = ErrorCode::kSuccess;

  const char* c_bytes = reinterpret_cast<const char*>(bytes);

  /*
   * 1. 根据当前要处理的字节数 count，更新接收进度，
   *    输出进度日志: "Completed 23/377 operations (6%), 40302425/282164983 bytes downloaded (14%), overall progress 10%"
   */
  // Update the total byte downloaded count and the progress logs.
  total_bytes_received_ += count;
  UpdateOverallProgress(false, "Completed ");

  /*
   * 2. 解析 manifest 数据，提取 partitions 和 InstallOperations 信息
   */
  /*
   * 当 manifest 数据没有完成解析时: manifest_valid_=false
   * 执行这里的 while 循环，用于处理 manifest 数据
   */
  while (!manifest_valid_) {
    // Read data up to the needed limit; this is either maximium payload header
    // size, or the full metadata size (once it becomes known).
    /*
     * 2.1 复制 payload 头部的 Payload Header 数据到缓冲区
     */
    const bool do_read_header = !IsHeaderParsed();
    CopyDataToBuffer(&c_bytes, &count,
                     (do_read_header ? kMaxPayloadHeaderSize :
                      metadata_size_ + metadata_signature_size_));

    /*
     * 2.2 解析 payload 的 Header 数据，得到 manifest 和 metadata signature 的 size，方便后续操作
     */
    MetadataParseResult result = ParsePayloadMetadata(buffer_, error);
    if (result == kMetadataParseError)
      return false;
    if (result == kMetadataParseInsufficientData) {
      // If we just processed the header, make an attempt on the manifest.
      if (do_read_header && IsHeaderParsed())
        continue;

      return true;
    }

    /*
     * 2.3 检查验证 manifest 数据
     *     具体包括：
     *     1). 是否包含 old kernel 和 old rootfs 信息，如果是，则说明是差分升级;
     *     2). 检查差分升级和整包升级的各种版本信息;
     *     3). 输出类似日志: "Detected a 'full' payload."
     *     4). 检查 manifest 中的时间戳和当前运行系统的编译时间信息
     */
    // Checks the integrity of the payload manifest.
    if ((*error = ValidateManifest()) != ErrorCode::kSuccess)
      return false;
    manifest_valid_ = true;

    // Clear the download buffer.
    DiscardBuffer(false, metadata_size_);

    /*
     * 2.4 提取 manifest 中的 partitions 信息存放到 partitions_ 和 install_plan.partitions 中
     *     打印输出包含 old 和 new 分区 sha256 和 size 的 log:
     *     "PartitionInfo old system sha256:  size: 0"
     *     "PartitionInfo new system sha256: kFXbYza...OuXZuCh9yw0= size: 769654784"
     */
    // This populates |partitions_| and the |install_plan.partitions| with the
    // list of partitions from the manifest.
    if (!ParseManifestPartitions(error))
      return false;

    /*
     * 2.5 遍历所有 partitions，根据每个分区的 InstallOperation 数计算每个分区的结束的 operation 序号
     * 例如 boot, system, vendor 分区各自有 5, 20, 18 个 InstallOperation，
     * 则相应的结束 operation 序号为：{5, 25, 43}，实际上就是下一个分区的起始序号
     */
    num_total_operations_ = 0;
    for (const auto& partition : partitions_) {
      num_total_operations_ += partition.operations_size();
      acc_num_operations_.push_back(num_total_operations_);
    }

    LOG_IF(WARNING, !prefs_->SetInt64(kPrefsManifestMetadataSize,
                                      metadata_size_))
        << "Unable to save the manifest metadata size.";
    LOG_IF(WARNING, !prefs_->SetInt64(kPrefsManifestSignatureSize,
                                      metadata_signature_size_))
        << "Unable to save the manifest signature size.";

    /*
     * 2.6 初始化升级的 state，如果此前升级被中断了，则在这里提取上一次升级保存在 prefs 中的信息
     *     Prime 在这里是"事先准备"的意思，相当于 prepare.
     *     提取的信息用于初始化的对象包括: 
     *     kPrefsUpdateStateNextOperation --> next_operation
     *     kPrefsUpdateStateNextDataOffset --> next_data_offset
     *     kPrefsUpdateStateSignedSHA256Context --> signed_hash_calculator_
     *     kPrefsUpdateStateSignatureBlob --> signatures_message_data_
     *     kPrefsUpdateStateSHA256Context --> payload_hash_calculator_
     *     kPrefsManifestMetadataSize --> metadata_size_
     *     kPrefsManifestSignatureSize --> metadata_signature_size_
     *     kPrefsResumedUpdateFailures --> resumed_update_failures
     */
    if (!PrimeUpdateState()) {
      *error = ErrorCode::kDownloadStateInitializationError;
      LOG(ERROR) << "Unable to prime the update state.";
      return false;
    }

    /*
     * 2.7 获取当前要操作分区的文件路径，打开分区文件并将文件描述符保存起来。
     *     对于全新升级，打开要操作的第 1 个分区；对于恢复升级，打开上次中断时要操作的分区；
     *     如果是整包升级(全量包)，目标分区路径和文件描述符保存在 target_path_ 和 target_fd_ 中
     *     如果是差分升级(增量包)，源分区和目标分区的路径和描述符分别保存在 {source_path_, target_path_} 和 {source_fd_, target_fd_} 中
     */
    if (!OpenCurrentPartition()) {
      *error = ErrorCode::kInstallDeviceOpenError;
      return false;
    }

    /*
     * 2.8 根据 PrimeUpdateState 函数准备的状态信息 next_operation_num_, 如果下一个操作序号不是 0，则打印日志 "Resuming after ...."
     */
    if (next_operation_num_ > 0)
      UpdateOverallProgress(true, "Resuming after ");
    LOG(INFO) << "Starting to apply update payload operations";
  }

  /*
   * 3. 升级 InstallOperation 的分区还原操作
   */
  while (next_operation_num_ < num_total_operations_) {
    /*
     * 3.1 检查当前升级是否已经取消
     */
    // Check if we should cancel the current attempt for any reason.
    // In this case, *error will have already been populated with the reason
    // why we're canceling.
    if (download_delegate_ && download_delegate_->ShouldCancel(error))
      return false;

    /*
     * 3.2 检查操作分区的路径和描述符
     *     如果下一个要操作的 operation 需要已经超过当前分区的累计 operation 数，说明当前打开分区已经升级完成，打开下一个升级的分区，准备分区的路径和文件描述符。
     */
    // We know there are more operations to perform because we didn't reach the
    // |num_total_operations_| limit yet.
    while (next_operation_num_ >= acc_num_operations_[current_partition_]) {
      CloseCurrentPartition();
      current_partition_++;
      if (!OpenCurrentPartition()) {
        *error = ErrorCode::kInstallDeviceOpenError;
        return false;
      }
    }
    /*
     * 3.3 获取当前分区要操作的 operation 数量和操作集合
     */
    const size_t partition_operation_num = next_operation_num_ - (
        current_partition_ ? acc_num_operations_[current_partition_ - 1] : 0);

    const InstallOperation& op =
        partitions_[current_partition_].operations(partition_operation_num);

    CopyDataToBuffer(&c_bytes, &count, op.data_length());

    /*
     * 3.4 检查当前要操作的 operation 数据是否已经接收完整
     */
    // Check whether we received all of the next operation's data payload.
    if (!CanPerformInstallOperation(op))
      return true;

    /*
     * 3.5 检查当前 operation 的哈希
     *     计算当前 operation 数据的哈希，并同其描述数据中的 data_sha256_hash 进行比较。
     *     InstallOperation 的描述数据保存在 manifest 中，metadata 的 signature 在 manifest 数据之后，所以如果 metadata_signature 数据存在，则说明 manifest 接收完成了，也就是说所有 operation 的描述数据也接收完成了，可以对 operation 进行各种检查。
     */
    // Validate the operation only if the metadata signature is present.
    // Otherwise, keep the old behavior. This serves as a knob to disable
    // the validation logic in case we find some regression after rollout.
    // NOTE: If hash checks are mandatory and if metadata_signature is empty,
    // we would have already failed in ParsePayloadMetadata method and thus not
    // even be here. So no need to handle that case again here.
    if (!install_plan_->metadata_signature.empty()) {
      // Note: Validate must be called only if CanPerformInstallOperation is
      // called. Otherwise, we might be failing operations before even if there
      // isn't sufficient data to compute the proper hash.
      *error = ValidateOperationHash(op);
      if (*error != ErrorCode::kSuccess) {
        if (install_plan_->hash_checks_mandatory) {
          LOG(ERROR) << "Mandatory operation hash check failed";
          return false;
        }

        // For non-mandatory cases, just send a UMA stat.
        LOG(WARNING) << "Ignoring operation validation errors";
        *error = ErrorCode::kSuccess;
      }
    }

    // Makes sure we unblock exit when this operation completes.
    ScopedTerminatorExitUnblocker exit_unblocker =
        ScopedTerminatorExitUnblocker();  // Avoids a compiler unused var bug.

    /*
     * 3.6 根据当前 operation 的类型，对数据执行相应的还原操作
     */
    bool op_result;
    switch (op.type()) {
      case InstallOperation::REPLACE:
      case InstallOperation::REPLACE_BZ:
      case InstallOperation::REPLACE_XZ:
        op_result = PerformReplaceOperation(op);
        break;
      case InstallOperation::ZERO:
      case InstallOperation::DISCARD:
        op_result = PerformZeroOrDiscardOperation(op);
        break;
      case InstallOperation::MOVE:
        op_result = PerformMoveOperation(op);
        break;
      case InstallOperation::BSDIFF:
        op_result = PerformBsdiffOperation(op);
        break;
      case InstallOperation::SOURCE_COPY:
        op_result = PerformSourceCopyOperation(op, error);
        break;
      case InstallOperation::SOURCE_BSDIFF:
        op_result = PerformSourceBsdiffOperation(op, error);
        break;
      default:
       op_result = false;
    }
    /*
     * 3.7 检查当前 operation 还原操作的结果
     */
    if (!HandleOpResult(op_result, InstallOperationTypeName(op.type()), error))
      return false;

    /*
     * 3.8 更新下一个 operation 的序号和升级进度，创建 CheckPoint，开始下一个 operation 操作
     */
    next_operation_num_++;
    UpdateOverallProgress(false, "Completed ");
    CheckpointUpdateProgress();
  }

  /*
   * 对于 Android 升级，前面已经处理过 signature 信息，所以这部分代码不会执行
   */
  // In major version 2, we don't add dummy operation to the payload.
  // If we already extracted the signature we should skip this step.
  if (major_payload_version_ == kBrilloMajorPayloadVersion &&
      manifest_.has_signatures_offset() && manifest_.has_signatures_size() &&
      signatures_message_data_.empty()) {
    if (manifest_.signatures_offset() != buffer_offset_) {
      LOG(ERROR) << "Payload signatures offset points to blob offset "
                 << manifest_.signatures_offset()
                 << " but signatures are expected at offset "
                 << buffer_offset_;
      *error = ErrorCode::kDownloadPayloadVerificationError;
      return false;
    }
    CopyDataToBuffer(&c_bytes, &count, manifest_.signatures_size());
    // Needs more data to cover entire signature.
    if (buffer_.size() < manifest_.signatures_size())
      return true;
    if (!ExtractSignatureMessage()) {
      LOG(ERROR) << "Extract payload signature failed.";
      *error = ErrorCode::kDownloadPayloadVerificationError;
      return false;
    }
    DiscardBuffer(true, 0);
    // Since we extracted the SignatureMessage we need to advance the
    // checkpoint, otherwise we would reload the signature and try to extract
    // it again.
    CheckpointUpdateProgress();
  }

  return true;
}
```



总结下这里 DeltaPerformer 的 Write 操作：

1. 根据当前要处理的字节数 count，更新接收进度
  
   输出进度日志: "Completed 23/377 operations (6%), 40302425/282164983 bytes downloaded (14%), overall progress 10%"

2. 如果当前还没有完整的 manifest 数据，则解析 manifest 数据，提取 partitions 和 InstallOperations 信息
   1. 复制 payload 头部的 Payload Header 数据到缓冲区
   2. 解析 payload 的 Header 数据，得到 manifest 和 metadata signature 的 size，方便后续操作
   3. 对接收到的 manifest 数据进行检查验证
   4. 提取 manifest 中的 partitions 信息存放到 partitions_ 和 install_plan.partitions 中
   5. 遍历所有 partitions，根据每个分区的 InstallOperation 数计算每个分区的结束的 operation 序号
   6. 初始化升级的 state，如果此前升级被中断了，则在这里提取上一次升级保存在 prefs 中的信息
   7. 获取当前要操作分区的文件路径，打开分区文件并将文件描述符保存起来
      1. 如果是整包升级(全量包)，目标分区路径和文件描述符保存在 `target_path_` 和 `target_fd_` 中
      2. 如果是差分升级(增量包)，源分区和目标分区的路径和描述符分别保存在 {`source_path_`, `target_path_`} 和 {`source_fd_`, `target_fd_`} 中
   8. 根据 PrimeUpdateState 函数准备的状态信息 next_operation_num_
3. 升级 InstallOperation 的数据还原操作
   1. 检查当前升级是否已经取消
   2. 检查操作分区的路径和描述符，如果当前分区升级完成，则保存下一个分区的路径和描述符
   3. 获取当前分区要操作的 operation 数量和操作集合
   4. 检查当前要操作的 operation 数据是否已经接收完整
   5. 检查当前 operation 的哈希
   6. 根据当前 operation 的类型，对数据执行相应的还原操作
   7. 检查当前 operation 还原操作的结果
   8. 更新下一个 operation 的序号和升级进度，创建 CheckPoint, 开始下一个 operation 操作



所以，总体上 Write() 函数操作分 3 部分：

第一部分：更新进度，打印进度日志；

第二部分：解析 manifest 数据；

根据接收到的数据提取 manifest 数据。

如果 manifest 数据接收完成，则验证 metadata 签名(包含 header 数据和 manifest 数据)，解析 manifest 数据，提取分区 partitions 和分区对应的 InstallOperation 信息;

第三部分：还原 InstallOperation 数据

如果 manifest 数据已经解析完成，则后续接收到的就是 InstallOperation 数据，在每一个分区上执行 InstallOperation 数据的还原操作。



### 3. 打开分区文件描述符

注意，在上一节的步骤 2.7 和 3.2 中，会调用 OpenCurrentPartition() 函数打开要操作的分区，并将分区设备的路径和文件操作符保存起来。

相比于前一节的 Write 函数，OpenCurrentPartition 函数逻辑比较简单，容易理解：

```c++
/* system/update_engine/payload_consumer/delta_performer.cc */
bool DeltaPerformer::OpenCurrentPartition() {
  if (current_partition_ >= partitions_.size())
    return false;

  /*
   * 1. 获取当前操作分区的信息
   *    partitions_ 保存了从 manifest 中提取的分区信息，current_partition_ 指示当前要操作的分区
   */
  const PartitionUpdate& partition = partitions_[current_partition_];
  
  /*
   * 2. 如果当前是增量升级，保存源分区路径名称，提前打开源分区并保存源分区的文件描述符到 source_fd_ 中
   *    1). 获取源分区的 source_path 保存在 source_path_ 中
   *    2). 打开 source_path_ 指定的分区，并将文件描述符保存在 source_fd_ 中
   */
  // Open source fds if we have a delta payload with minor version >= 2.
  if (install_plan_->payload_type == InstallPayloadType::kDelta &&
      GetMinorVersion() != kInPlaceMinorPayloadVersion) {
    source_path_ = install_plan_->partitions[current_partition_].source_path;
    int err;
    source_fd_ = OpenFile(source_path_.c_str(), O_RDONLY, &err);
    if (!source_fd_) {
      LOG(ERROR) << "Unable to open source partition "
                 << partition.partition_name() << " on slot "
                 << BootControlInterface::SlotName(install_plan_->source_slot)
                 << ", file " << source_path_;
      return false;
    }
  }

  /*
   * 3. 保存目标分区路径名称，提前打开目标分区并保存目标分区文件描述符到 target_fd_ 中
   *    1). 获取目标分区的 target_path 保存在 target_path_ 中
   *    2). 打开 target_path_ 指定的分区，并将文件描述符保存在 target_fd_ 中
   */
  target_path_ = install_plan_->partitions[current_partition_].target_path;
  int err;
  target_fd_ = OpenFile(target_path_.c_str(), O_RDWR, &err);
  if (!target_fd_) {
    LOG(ERROR) << "Unable to open target partition "
               << partition.partition_name() << " on slot "
               << BootControlInterface::SlotName(install_plan_->target_slot)
               << ", file " << target_path_;
    return false;
  }

  /*
   * 4. 输出分区更新日志
   *    例如: Applying 10 operations to partition "boot"
   */
  LOG(INFO) << "Applying " << partition.operations().size()
            << " operations to partition \"" << partition.partition_name()
            << "\"";

  /*
   * 5. 如果已经打开的目标分区比升级后的目标分区大，则丢弃多余的数据块(清零)
   */
  // Discard the end of the partition, but ignore failures.
  DiscardPartitionTail(
      target_fd_, install_plan_->partitions[current_partition_].target_size);

  return true;
}
```

所以，函数 OpenCurrentPartition() 内部进行了以下几个操作：

1. 获取当前操作分区的信息
2. 如果当前是增量升级，保存源分区路径名称到 `source_path_` 中，提前打开源分区并保存源分区的文件描述符到 `source_fd_` 中
3. 保存目标分区路径名称到 `target_path_` 中，提前打开目标分区并保存目标分区文件描述符到 `target_fd_` 中
4. 输出分区更新日志，例如: Applying 10 operations to partition "boot"
5. 如果已经打开的目标分区比升级后的目标分区大，则丢弃多余的数据块(清零)

> 思考题：既然都打开分区了，只保存分区文件描述符 `source_fd_` 和 `target_fd_` 不就行了吗？为什么还要保存分区文件路径 `source_path_` 和 `target_path_` 呢？



### 4. 使用分区文件描述符

在上一节中，我们分析了打开分区的代码 OpenCurrentPartition()，在函数中打开分区并保存相应分区的文件描述符。那这些分区文件描述符又是哪里被使用的呢？



在 DelterPerformer 的 Write 函数中，会根据 InstallOperation 的 Type 来决定对数据如何使用。正是在这些具体的使用中，会使用分区的文件描述符，去操作分区，从源分区读取数据，并将其写入到目标分区中。



```c++
/* file: system/update_engine/payload_consumer/delta_performer.cc */

// Wrapper around write. Returns true if all requested bytes
// were written, or false on any error, regardless of progress
// and stores an action exit code in |error|.
bool DeltaPerformer::Write(const void* bytes, size_t count, ErrorCode *error) {
    //...
  
		bool op_result;
    switch (op.type()) {
      case InstallOperation::REPLACE:
      case InstallOperation::REPLACE_BZ:
      case InstallOperation::REPLACE_XZ:
        op_result = PerformReplaceOperation(op);
        break;
      case InstallOperation::ZERO:
      case InstallOperation::DISCARD:
        op_result = PerformZeroOrDiscardOperation(op);
        break;
      case InstallOperation::MOVE:
        op_result = PerformMoveOperation(op);
        break;
      case InstallOperation::BSDIFF:
        op_result = PerformBsdiffOperation(op);
        break;
      case InstallOperation::SOURCE_COPY:
        op_result = PerformSourceCopyOperation(op, error);
        break;
      case InstallOperation::SOURCE_BSDIFF:
        op_result = PerformSourceBsdiffOperation(op, error);
        break;
      default:
       op_result = false;
    }
    if (!HandleOpResult(op_result, InstallOperationTypeName(op.type()), error))
      return false;
  
  	// ...
}
```



在 Android 7.1 中，定义了 9 种 Operation Type，在 Android 11 (VAB) 上，Operation Type 增加到 11 种，其中的 MOVE(2) 和 BSDIFF(3) 被标记为 deprecated 不再使用，并将原来的 IMGDIFF(9) 替换为 PUFFDIFF(9)。

在 Android 13 中会再增加 3 个操作: ZUCCHINI(11), LZ4DIFF_BSDIFF(12) 和 LZ4DIFF_PUFFDIFF(13)。



虽然 Operation Type 有变化，但数据更新的整理 Write() 结构仍然基本一样。



我们通过对类型为 SOURCE_COPY 的 InstallOperation 的操作 `PerformSourceCopyOperation(op, error)`，来看看分区的文件描述符是如何被使用的：

```c++
/* file: system/update_engine/payload_consumer/delta_performer.cc */
bool DeltaPerformer::PerformSourceCopyOperation(
    const InstallOperation& operation, ErrorCode* error) {
  /*
   * 1. 检查 src 和 dst 分区操作信息
   *    1.1 检查 operation 的 src 和 dst 分区的操作长度以 block_size 对齐。
   */
  if (operation.has_src_length())
    TEST_AND_RETURN_FALSE(operation.src_length() % block_size_ == 0);
  if (operation.has_dst_length())
    TEST_AND_RETURN_FALSE(operation.dst_length() % block_size_ == 0);

  /*
   *    1.2 针对 Copy 操作，检查 src 分区读取和 dst 分区写入的总 block 数量，二者需要一致
   */
  uint64_t blocks_to_read = GetBlockCount(operation.src_extents());
  uint64_t blocks_to_write = GetBlockCount(operation.dst_extents());
  TEST_AND_RETURN_FALSE(blocks_to_write ==  blocks_to_read);

  /*
   * 2. 将 src 和 dst 操作的分区，从 extents 的数据段转换成 block 块数组
   */
  // Create vectors of all the individual src/dst blocks.
  vector<uint64_t> src_blocks;
  vector<uint64_t> dst_blocks;
  ExtentsToBlocks(operation.src_extents(), &src_blocks);
  ExtentsToBlocks(operation.dst_extents(), &dst_blocks);
  DCHECK_EQ(src_blocks.size(), blocks_to_read);
  DCHECK_EQ(src_blocks.size(), dst_blocks.size());

  /*
   * 3. 遍历所有需要 Copy 的数据块，将数据从 src 分区读取并写入到 dst 分区。
   */
  brillo::Blob buf(block_size_);
  ssize_t bytes_read = 0;
  HashCalculator source_hasher;
  // Read/write one block at a time.
  for (uint64_t i = 0; i < blocks_to_read; i++) {
    ssize_t bytes_read_this_iteration = 0;
    uint64_t src_block = src_blocks[i];
    uint64_t dst_block = dst_blocks[i];

    /*
     * 3.1 通过 source_fd_ 文件描述符，从源分区(src) 读取数据
     */
    // Read in bytes.
    TEST_AND_RETURN_FALSE(
        utils::PReadAll(source_fd_,
                        buf.data(),
                        block_size_,
                        src_block * block_size_,
                        &bytes_read_this_iteration));

    /*
     * 3.2 通过 target_fd_ 文件描述符，将数据写入到目标分区(dst)
     */
    // Write bytes out.
    TEST_AND_RETURN_FALSE(
        utils::PWriteAll(target_fd_,
                         buf.data(),
                         block_size_,
                         dst_block * block_size_));

    bytes_read += bytes_read_this_iteration;
    TEST_AND_RETURN_FALSE(bytes_read_this_iteration ==
                          static_cast<ssize_t>(block_size_));

    /*
     * 3.3 累积计算 src 分区读取数据的 sha256 哈希值，读取完所有 block 以后得到当前 operation 数据的哈希值
     */
    if (operation.has_src_sha256_hash())
      TEST_AND_RETURN_FALSE(source_hasher.Update(buf.data(), buf.size()));
  }

  /*
   * 4. 检查操作数据的哈希和长度
   *
   *    4.1 将从 src 分区读取数据累积计算得到的 sha256 哈希，和做包时保存在 operation 的哈希进行比较
   *    如果不一致，则会打印类似如下的日志:
   *    The hash of the source data on disk for this operation doesn't match the expected value. This could mean that the delta update payload was targeted for another version, or that the source partition was modified after it was installed, for example, by mounting a filesystem.
   *    Expected:   sha256|hex = 8661B0B46426C664E5E27585184D2B4AA70950677EABE3F155A10BA3DFD4A46E
   *    Calculated: sha256|hex = 9EE617335ACDC2447769174C6CE6B65C01B88A88E94E26969177FE2ABF7F4C54
   *    Operation source (offset:size) in blocks: 9445:1
   */
  if (operation.has_src_sha256_hash()) {
    TEST_AND_RETURN_FALSE(source_hasher.Finalize());
    TEST_AND_RETURN_FALSE(
        ValidateSourceHash(source_hasher.raw_hash(), operation, error));
  }

  /*
   *    4.2 检查数据操作的长度
   */
  DCHECK_EQ(bytes_read, static_cast<ssize_t>(blocks_to_read * block_size_));
  return true;
}
```

所以，对 Copy 操作的汇总如下：

1. 检查 src 和 dst 分区操作信息
2. 将 src 和 dst 操作的分区，从 extents 的数据段转换成 block 块数组
3. 遍历所有需要 Copy 的数据块，将数据从 src 分区读取并写入到 dst 分区。
   1. 通过 source_fd_ 文件描述符，从源分区(src) 读取数据
   2. 通过 target_fd_ 文件描述符，将数据写入到目标分区(dst)
   3. 累积计算 src 分区读取数据的 sha256 哈希值，读取完所有 block 以后得到当前 operation 数据的哈希值
4. 检查操作数据的哈希和长度



所有 10 类 Android 7.1 支持的 InstallOperation 我在文章 [《Android Update Engine 分析（十七）10 类 InstallOperation 数据的生成和应用》](https://guyongqiangx.blog.csdn.net/article/details/122942628) 中逐一分析过，这里也再次分析了 Copy 操作的实现，对其余 Operation 感兴趣，请转到该文章详细阅读。



### 5. 整包升级(全量升级)的更新

前面重点分析了差分升级(增量升级)的分区写入过程，那全量升级又是怎样的呢？

全量升级和增量升级的流程基本一致，不同的是，全量升级的数据不再需要源分区，因为所有目标分区的数据都来自 InstallOperation 自身的数据。

因此，对于全量升级，就不存在所有需要两个分区参与的操作，包括：

MOVE, BSDIFF, SOURCE_COPY, SOURCE_BSDIFF, IMGDIFF 等。



在全量升级中，由于不需要源分区，所以不会再有 `source_path_` 保存源分区路径，不会再有 `source_fd_` 保存源分区文件描述符。所需要的只是目标分区的路径 `target_path_` 和目标分区的描述符 `target_fd_`。



## 4. 总结

Update Engine 通过网络接收到数据，或者通过文件读取到数据以后，DownloadAction 的`ReceivedBytes()`函数被回调，在其内部会进一步调用 DownloadAction 内部成员 `writer_` 的`Write()`函数写入接收到的数据。



Write() 函数主要有 3 个部分：

第一部分：更新进度，打印进度日志；

第二部分：解析 manifest 数据；

根据接收到的数据提取 manifest 数据。

如果 manifest 数据接收完成，则验证 metadata 签名(包含 header 数据和 manifest 数据)，解析 manifest 数据，提取分区 partitions 和分区对应的 InstallOperation 信息;

第三部分：还原 InstallOperation 数据

如果 manifest 数据已经解析完成，则后续接收到的就是 InstallOperation 数据，在每一个分区上执行 InstallOperation 数据的还原操作。



详细来说，DeltaPerformer 的 Write() 函数做了以下操作：

1. 根据当前要处理的字节数 count，更新接收进度

   输出进度日志: "Completed 23/377 operations (6%), 40302425/282164983 bytes downloaded (14%), overall progress 10%"

2. 如果当前还没有完整的 manifest 数据，则解析 manifest 数据，提取 partitions 和 InstallOperations 信息
   1. 复制 payload 头部的 Payload Header 数据到缓冲区
   2. 解析 payload 的 Header 数据，得到 manifest 和 metadata signature 的 size，方便后续操作
   3. 对接收到的 manifest 数据进行检查验证
   4. 提取 manifest 中的 partitions 信息存放到 partitions_ 和 install_plan.partitions 中
   5. 遍历所有 partitions，根据每个分区的 InstallOperation 数计算每个分区的结束的 operation 序号
   6. 初始化升级的 state，如果此前升级被中断了，则在这里提取上一次升级保存在 prefs 中的信息
   7. 获取当前要操作分区的文件路径，打开分区文件并将文件描述符保存起来
      1. 如果是整包升级(全量包)，目标分区路径和文件描述符保存在 `target_path_` 和 `target_fd_` 中
      2. 如果是差分升级(增量包)，源分区和目标分区的路径和描述符分别保存在 {`source_path_`, `target_path_`} 和 {`source_fd_`, `target_fd_`} 中
   8. 根据 PrimeUpdateState 函数准备的状态信息 next_operation_num_
3. 升级 InstallOperation 的数据还原操作
   1. 检查当前升级是否已经取消
   2. 检查操作分区的路径和描述符，如果当前分区升级完成，则保存下一个分区的路径和描述符
   3. 获取当前分区要操作的 operation 数量和操作集合
   4. 检查当前要操作的 operation 数据是否已经接收完整
   5. 检查当前 operation 的哈希
   6. 根据当前 operation 的类型，对数据执行相应的还原操作
   7. 检查当前 operation 还原操作的结果
   8. 更新下一个 operation 的序号和升级进度，创建 CheckPoint, 开始下一个 operation 操作



其中，

在步骤 2.7 或 3.2 中，调用函数 OpenCurrentPartition() 打开要操作的分区，保存分区文件路径`target_path_`和分区文件描述符`target_fd_`。

在步骤 3.6 中，根据不同的 InstallOperation 的 Type，调用相应的操作，使用前面打开的分区文件描述符`target_fd_`，从源分区(`source_fd_`)读取数据，并写入到目标分区(`target_fd_`)中。



## 5. 其它

到目前为止，我写过 Android OTA 升级相关的话题包括：

- 基础入门：《Android A/B 系统》系列
- 核心模块：《Android Update Engine 分析》 系列
- 动态分区：《Android 动态分区》 系列
- 虚拟 A/B：《Android 虚拟 A/B 分区》系列
- 升级工具：《Android OTA 相关工具》系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题。

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。

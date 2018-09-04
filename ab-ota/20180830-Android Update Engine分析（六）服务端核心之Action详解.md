# Android Update Engine分析（六）服务端核心之Action详解

本系列到现在为止的前五篇分别分析了Makefile，Protobuf和AIDL相关文件, Update Engine的客户端进程，Update Engine的服务端及Action机制:

- [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)
- [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)
- [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)
- [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)
- [Android Update Engine分析（五）服务端核心之Action机制](https://blog.csdn.net/guyongqiangx/article/details/82226079)

但基本上还在比较高的层面，并没有涉及到升级的具体细节，即每一个任务到底是如何实现的？

在上一篇Action机制中我们谈到了，类`UpdateAttempterAndroid`的函数`BuildUpdateActions()`会在更新开始前构建升级所需要的4个Action任务对象，包括构建：

- InstallPlanAction: `install_plan_action`
- DownloadAction: `download_action`
- FilesystemVerifierAction: `dst_filesystem_verifier_action`
- PostinstallRunnerAction: `postinstall_runner_action`

然后使用ActionPipe将这4个Action连接起来并将其添加到ActionProcessor的管理队列中。

本篇将详细分析这里4个Action任务的具体实现。

由于涉及到4个Action的具体代码分析，所以本篇内容会非常长，我在有道云笔记里用Markdown写完后切换到预览都要很久。一开始是想将每个Action分别写一篇的，但那样篇数太多了，所以最后决定将所有Action的分析都放到一篇里面。

为了帮助阅读，以下是针对各主要部分的跳转提示，想了解特定内容请点击链接跳转：

1. 了解单个Action:
    - 了解InstallPlanAction，请转到：__[InstallPlanAction](#InstallPlanAction)__
    - 了解DownloadAction，请转到：__[DownloadAction](#DownloadAction)__
    - 了解FilesystemVerifierAction，请转到：__[FilesystemVerifierAction](#FilesystemVerifierAction)__
    - 了解PostinstallRunnerAction，请转到：__[PostinstallRunnerAction](#PostinstallRunnerAction)__
2. 了解DownloadAction的总结，请转到：__[DownloadAction总结](#DownloadSummary)__
3. 了解FilesystemVerifierAction的总结，请转到：__[FilesystemVerifierAction总结](#VerifierSummary)__
4. 了解PostinstallRunnerAction的总结，请转到：__[PostinstallRunnerAction总结](#PostInstallSummary)__
5. 了解4个Action是如何衔接的，请转到： __[Action间的管道操作](#pipeflow)__
6. 了解整个Action执行的流程总结，请转到：__[Action的执行流程](#Summary)__

> 本文涉及的Android代码版本：android‐7.1.1_r23 (NMF27D)

## <span id="InstallPlanAction">1. InstallPlanAction</span>

### 1.1 InstallPlanAction的实现

`BuildUpdateActions()`构建的4个Action中，其第一个InstallPlanAction最为简单，所有代码都包含在类定义中，没有单独的代码实现：
```
// Basic action that only receives and sends Install Plans.
// Can be used to construct an Install Plan to send to any other Action that
// accept an InstallPlan.
class InstallPlanAction : public Action<InstallPlanAction> {
 public:
  InstallPlanAction() {}
  explicit InstallPlanAction(const InstallPlan& install_plan):
    install_plan_(install_plan) {}

  void PerformAction() override {
    if (HasOutputPipe()) {
      SetOutputObject(install_plan_);
    }
    processor_->ActionComplete(this, ErrorCode::kSuccess);
  }

  InstallPlan* install_plan() { return &install_plan_; }

  static std::string StaticType() { return "InstallPlanAction"; }
  std::string Type() const override { return StaticType(); }

  typedef ActionTraits<InstallPlanAction>::InputObjectType InputObjectType;
  typedef ActionTraits<InstallPlanAction>::OutputObjectType OutputObjectType;

 private:
  InstallPlan install_plan_;

  DISALLOW_COPY_AND_ASSIGN(InstallPlanAction);
};
```

InstallPlanAction除了是Action任务队列中4个Action任务的第1个之外，他其实也是其余3个Action的父类，如果你要自定义自己的Action任务，那InstallPlanAction也应该是自定义Action任务的起点，即父类。

### 1.2 InstallPlanAction的初始化

在`BuildUpdateActions()`的一开始，就是用私有成员`install_plan_`作为参数构造`install_plan_action`:
```
void UpdateAttempterAndroid::BuildUpdateActions(const string& url) {
  ...

  // 用私有成员install_plan_构建一个InstallPlanAction
  // Actions:
  shared_ptr<InstallPlanAction> install_plan_action(
      new InstallPlanAction(install_plan_));

  ...
}
```

在InstallPlanAction的实现中，有一个私有的`install_plan_`成员，使用构造函数中传入的InstallPlan(即`UpdateAttemterAndroid`的私有成员`install_plan_`)进行初始化，而构造函数本身却什么都没做:
```
  explicit InstallPlanAction(const InstallPlan& install_plan):
    install_plan_(install_plan) {}
```

### 1.3 InstallPlanAction的功能操作

作为ActionProcessor队列中的第1个Action，所以会被ActionProcessor作为第1个Action任务运行。`PerformAction()`是所有Action执行具体操作的地方，我们看看InstallPlanAction的`PerformAction()`操作：
```
  void PerformAction() override {
    if (HasOutputPipe()) {
      SetOutputObject(install_plan_);
    }
    processor_->ActionComplete(this, ErrorCode::kSuccess);
  }
```
这里`PerformAction`做的唯一一件事情就是将`install_plan_`设置为OutoutObject，然后就告诉processor自身的处理完成了，processor收到通知会挑选Action队列中的下一个Action任务开始运行。

由于所有的Action是通过ActionPipe连接起来的，在`BuildUpdateActions()`中，`BondActions(install_plan_action.get(), download_action.get())`操作会将`install_plan_action`的输出同`download_action`的输入连接起来，所以InstallPlanAction的OutputObject(即`install_plan_`)就会成为随后DownloadAction的InputObject。

### <span id="pipeflow">1.4 Action间的管道操作</span>

从InstallPlanAction类定义开始前的注释我们也可以看到，InstallPlanAction属于基础Action，只接收和发送InstallPlan，所以目的主要是构建InstallPlan结构体并将其传递给其它接收InstallPlan的Action。
> ```
> // Basic action that only receives and sends Install Plans.</br>
> // Can be used to construct an Install Plan to send to any other Action that </br>
> // accept an InstallPlan.
> ```

事实上，随后的DownloaderAction, FilesystemVerifierAction和PostinstallRunnerAction也都使用InstallPlan来存储升级的基本信息，这3个Action有一个共同点，就是在`PerformAction()`调用的开始，通过`install_plan_ = GetInputObject()`来取得上一个Action的输出，并设置`install_plan_`。然后在本Action成功结束的地方，再将`install_plan_`设置为OutputObject，如果是失败或操作终止，则不会设置输出的OutputObject。

还是来看看具体代码吧。
- DownloadAction
```
void DownloadAction::PerformAction() {
  ...
  
  // 在管道连接操作 BondActions(install_plan_action.get(), download_action.get())后，确保这里HasInputObject()为真
  // Get the InstallPlan and read it
  CHECK(HasInputObject());
  // 获取InstallPlanAction通过PerformAction()操作设置的OutputObject, 即install_plan_
  install_plan_ = GetInputObject();

  ...
}

void DownloadAction::TransferComplete(HttpFetcher* fetcher, bool successful) {
  ...

  // 如果操作成功了ErrorCode::kSuccess，那就将install_plan_设置为OubputObject使其继续向后传递
  // 显然，失败的情况下，不会调用SetOutputObject传递install_plan_
  // Write the path to the output pipe if we're successful.
  if (code == ErrorCode::kSuccess && HasOutputPipe())
    SetOutputObject(install_plan_);
  processor_->ActionComplete(this, code);
}

void DownloadAction::TransferTerminated(HttpFetcher *fetcher) {
  // 如果是终止操作，也不会调用SetOutputObject去传递install_plan_
  if (code_ != ErrorCode::kSuccess) {
    processor_->ActionComplete(this, code_);
  }
}
```

DownloadAction分别在`PerformAction()`和`TransferComplete()`操作中从管道获取或设置`install_plan_`作为输入和输出。

- FilesystemVerifierAction
```
void FilesystemVerifierAction::PerformAction() {
  ...

  // 要是没有InputObject，那就拿不到install_plan_，你让Filesystem Verification工作如何搞？
  // 放心，在管道连接操作 BondActions(download_action.get(), dst_filesystem_verifier_action.get())后，就确保着这里HasInputObject()为真
  if (!HasInputObject()) {
    LOG(ERROR) << "FilesystemVerifierAction missing input object.";
    return;
  }
  // 获取DownloadAction传输完成时在TransferComplete()操作中设置的OutputObject, 即install_plan_
  install_plan_ = GetInputObject();

  ...
  // 如果没有分区需要验证，那Filesystem Verification这事也算是完成了
  if (install_plan_.partitions.empty()) {
    LOG(INFO) << "No partitions to verify.";
    // 管道连接操作 BondActions(dst_filesystem_verifier_action.get(), postinstall_runner_action.get()) 
    // 确保本Action的输出还会被下一个Action使用，所以继续传递install_plan_
    if (HasOutputPipe())
      SetOutputObject(install_plan_);
    abort_action_completer.set_code(ErrorCode::kSuccess);
    return;
  }

  ...
}

void FilesystemVerifierAction::Cleanup(ErrorCode code) {
  ...
  
  // 管道连接操作:
  // BondActions(dst_filesystem_verifier_action.get(), postinstall_runner_action.get())
  // 确保本dst_filesystem_verifier_action的输出还会被下一个Action使用。
  // 如果本dst_filesystem_verifier_action操作结果是成功的，所以继续传递install_plan_，否则就不需要了。
  if (code == ErrorCode::kSuccess && HasOutputPipe())
    SetOutputObject(install_plan_);
  processor_->ActionComplete(this, code);
}
```
FilesystemVerifierAction分别在`PerformAction()`和`Cleanup()`操作中从管道获取或设置`install_plan_`作为输入和输出。
如果在`PerformAction()`中没有发现需要操作的分区，那么也会认为操作成功，并将`install_plan_`设置为输出传递给下一个Action。

- PostinstallRunnerAction
```
void PostinstallRunnerAction::PerformAction() {
  // 在管道连接操作 BondActions(dst_filesystem_verifier_action.get(), postinstall_runner_action.get())后，确保这里HasInputObject()为真
  CHECK(HasInputObject());
  // 获取FilesystemVerifierAction成功操作后设置的OutputObject, 即install_plan_
  install_plan_ = GetInputObject();

  ...
}

void PostinstallRunnerAction::CompletePostinstall(ErrorCode error_code) {
  ...

  LOG(INFO) << "All post-install commands succeeded";
  // 在 BuildUpdateActions() 中 PostinstallRunnerAction 后续没有绑定操作，所以预计这里不会执行。
  // 如果后续还有其他操作，那么install_plan_会在这里被继续往下传递
  if (HasOutputPipe()) {
    SetOutputObject(install_plan_);
  }
}
```

FilesystemVerifierAction分别在`PerformAction()`和`CompletePostinstall()`操作中从管道获取或设置`install_plan_`作为输入和输出。但由于PostinstallRunnerAction后续并没有其他操作，所以管道操作到此终止了。

一句话，InstallPlanAction的存在就是为了构建InstallPlan并传递给其它Action，最终在ActionPipe间流转的就是`install_plan_`。

## <span id="DownloadAction">2. DownloadAction</span>

DownloadAction负责升级数据的下载和更新，是所有4个Action中最复杂的一个。

在开始DownloadAction分析之前，说一个被问得很多的问题，我想好多朋友都可能有这个问题，包括我自己：升级时是数据下载完了才开始更新还是一边下载一边更新呢？如果是下载完才更新，那下载的数据是存放到哪里的呢？如果是边下载边更新，那它的操作细节是怎样的呢？

看完看完DownloadAction的细节，就明白这个问题该如何回答了。即使回答不了细节，也知道在哪里可以找到答案。

### 2.1 DownloadAction的初始化

在`BuildUpdateActions()`中根据传入的url是否以字符串"`file:///`开头决定构造实际用于下载的`download_fetcher`:
- 字符串`file:///`开头，基于`FileFetcher`类构造数据下载对象
- 非字符串`file:///`，例如以`http://`或`https://`开头，基于`LibcurlHttpFetcher`类构造数据下载对象。

然后将构建的数据下载对象`download_fetcher`二次包装为`MultiRangeHttpFetcher`类的私有对象，并用后者初始化DownloadAction类的对象`download_action`:

```
void UpdateAttempterAndroid::BuildUpdateActions(const string& url) {
  ...

  HttpFetcher* download_fetcher = nullptr;
  // 如果url以"file:///"开始，则构建FileFetcher
  if (FileFetcher::SupportedUrl(url)) {
    DLOG(INFO) << "Using FileFetcher for file URL.";
    download_fetcher = new FileFetcher();
  } else {
#ifdef _UE_SIDELOAD
    LOG(FATAL) << "Unsupported sideload URI: " << url;
#else
    // 非"file:///"开始的，则构建LibcurlHttpFetcher
    LibcurlHttpFetcher* libcurl_fetcher =
        new LibcurlHttpFetcher(&proxy_resolver_, hardware_);
    libcurl_fetcher->set_server_to_check(ServerToCheck::kDownload);
    download_fetcher = libcurl_fetcher;
#endif  // _UE_SIDELOAD
  }
  // 创建DownloadAction的类对象download_action
  shared_ptr<DownloadAction> download_action(new DownloadAction(
      prefs_,
      boot_control_,
      hardware_,
      nullptr,                                        // system_state, not used.
      new MultiRangeHttpFetcher(download_fetcher)));  // passes ownership
  ...

  // 将UpdateAttempterAndroid的类对象update_attempter_设置为download_action的委托对象，用于向外发送通知
  download_action->set_delegate(this);
  download_action_ = download_action;
  ...
}
```

在`DownloadAction`构造函数的实现中，传入的参数较多，初始化的私有成员也很多：
```
DownloadAction::DownloadAction(PrefsInterface* prefs,
                               BootControlInterface* boot_control,
                               HardwareInterface* hardware,
                               SystemState* system_state,
                               HttpFetcher* http_fetcher)
    : prefs_(prefs),               // 用于读取和写入各种配置数据
      boot_control_(boot_control), // 用于对boot flag进行各种标记
      hardware_(hardware),         // 用于获取hardware的状态
      system_state_(system_state), // 初始化传入的参数为nullptr
      http_fetcher_(http_fetcher), // 数据获取的对象MultiRangeHttpFetcher，内部包含download_fetcher
      writer_(nullptr),            // 数据下载后进行写入操作的对象
      code_(ErrorCode::kSuccess),
      delegate_(nullptr),          // 指向外层的UpdateAttempterAndroid类对象update_attempter_
      bytes_received_(0),          // 接收到的字节数
      p2p_sharing_fd_(-1),         // p2p的文件句柄，android项目没有使用
      p2p_visible_(true) {         // p2p相关接口，android项目没有使用
}
```

#### 关于数据获取类`HttpFetcher`, `FileFetcher`,`LibcurlHttpFetcher`和`MultiRangeHttpFetcher`

从字面上看，这4个类看起来差不多，似乎是并行的一样功能的类，但其实不然：
- `HttpFetcher`是其余3个类的基类
- `FileFetcher`和`LibcurlHttpFetcher`是继承自`HttpFetcher`的具体实现类，前者基于文件的"`file:///`"协议，后者基于网络的"`http://`"协议
- `MultiRangeHttpFetcher`也继承自`HttpFetcher`, 具体的数据获取操作会转交给内部的`HttpFetcher`实现类(如`FileFetcher`或`LibcurlHttpFetcher`)，自身在此基础上实现了数据基于某个范围的获取，即我们常说的断点续传功能。

这4个类的关系如下图所示：

![`HttpFetcher`, `FileFetcher`,`LibcurlHttpFetcher`和`MultiRangeHttpFetcher`关系图](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/update_engine_http_fetcher_arch.png?raw=true)

从图上可见，DownloadAction的`http_fetcher_`指向`MultiRangeHttpFetcher`，而后者将具体的数据获取操作`base_fetcher_`成员交由`FileFetcher`或`LibcurlHttpFetcher`。

### 2.2 DownloadAction的功能操作

#### `DownloadAction`类的`PerformAction()`
在InstallPlanAction结束后，ActionProcessor会挑选InstallPlanAction的下一个Action(即DownloadAction)，并调用其`PerformAction()`操作。

DownloadAction的`PerformAction()`看起来有点复杂，其实很简单，因为`system_state_`被初始化为空指针`nullptr`导致其中的一大段逻辑都不会执行了，如下：
```
void DownloadAction::PerformAction() {
  // 将自己(即download_action对象)设置为http_fetcher_的委托对象，http_fetcher_通过委托对象向外发送通知
  http_fetcher_->set_delegate(this);

  //
  // 获取上一个Action，即InstallPlanAction传递过来的install_plan_，里面包含了升级相关的元数据
  //
  // Get the InstallPlan and read it
  CHECK(HasInputObject());
  install_plan_ = GetInputObject();
  bytes_received_ = 0;

  // 在中断打印install_plan_的详细信息
  install_plan_.Dump();

  //
  // 开始升级下载前，将target_slot设置为不可启动的unbootable状态
  //
  // 在整个升级操作完成的最后一步(PostinstallRunnerAction::CompletePostinstall)会重新将target_slot设置为active状态。
  LOG(INFO) << "Marking new slot as unbootable";
  if (!boot_control_->MarkSlotUnbootable(install_plan_.target_slot)) {
    LOG(WARNING) << "Unable to mark new slot "
                 << BootControlInterface::SlotName(install_plan_.target_slot)
                 << ". Proceeding with the update anyway.";
  }

  //
  // 初始化DeltaPerformer类对象delta_performer_作为数据写入的writer_
  // 对下载后数据如何解析和写入的重点都在writer_里
  //
  if (writer_) {
    LOG(INFO) << "Using writer for test.";
  } else {
    delta_performer_.reset(new DeltaPerformer(
        prefs_, boot_control_, hardware_, delegate_, &install_plan_));
    writer_ = delta_performer_.get();
  }
  download_active_ = true;

  // 类构造函数中根据传入参数初始化system_state_为nullptr，所以这里跳过if语句
  if (system_state_ != nullptr) {
    const PayloadStateInterface* payload_state = system_state_->payload_state();
    string file_id = utils::CalculateP2PFileId(install_plan_.payload_hash,
                                               install_plan_.payload_size);
    if (payload_state->GetUsingP2PForSharing()) {
      // If we're sharing the update, store the file_id to convey
      // that we should write to the file.
      p2p_file_id_ = file_id;
      LOG(INFO) << "p2p file id: " << p2p_file_id_;
    } else {
      // Even if we're not sharing the update, it could be that
      // there's a partial file from a previous attempt with the same
      // hash. If this is the case, we NEED to clean it up otherwise
      // we're essentially timing out other peers downloading from us
      // (since we're never going to complete the file).
      FilePath path = system_state_->p2p_manager()->FileGetPath(file_id);
      if (!path.empty()) {
        if (unlink(path.value().c_str()) != 0) {
          PLOG(ERROR) << "Error deleting p2p file " << path.value();
        } else {
          LOG(INFO) << "Deleting partial p2p file " << path.value()
                    << " since we're not using p2p to share.";
        }
      }
    }

    // Tweak timeouts on the HTTP fetcher if we're downloading from a
    // local peer.
    if (payload_state->GetUsingP2PForDownloading() &&
        payload_state->GetP2PUrl() == install_plan_.download_url) {
      LOG(INFO) << "Tweaking HTTP fetcher since we're downloading via p2p";
      http_fetcher_->set_low_speed_limit(kDownloadP2PLowSpeedLimitBps,
                                         kDownloadP2PLowSpeedTimeSeconds);
      http_fetcher_->set_max_retry_count(kDownloadP2PMaxRetryCount);
      http_fetcher_->set_connect_timeout(kDownloadP2PConnectTimeoutSeconds);
    }
  }

  //
  // 调用http_fetcher_开始数据传输，这里的http_fetcher_是MultiRangeHttpFetcher的类对象
  //
  http_fetcher_->BeginTransfer(install_plan_.download_url);
}
```

所以以上`PerformAction()`的操作简化为：
1. 获取ActionPipe包含升级元数据的`install_plan_`对象
2. 将升级分区target_slot设置为不可启动的unbootable状态
3. 初始化解析和写入升级数据的DeltaPerformer类对象`writer_`
4. 调用成员`http_fetcher_`的方法`BeginTransfer()`开始数据传输

函数最后的调用操作`http_fetcher_->BeginTransfer()`实际是`MultiRangeHttpFetcher`类的`BeginTransfer()`函数。

#### `MultiRangeHttpFetcher`类的`BeginTransfer()`
```
void MultiRangeHttpFetcher::BeginTransfer(const std::string& url) {
  //
  // 传输开始前检查系统状态
  //
  CHECK(!base_fetcher_active_) << "BeginTransfer but already active.";
  CHECK(!pending_transfer_ended_) << "BeginTransfer but pending.";
  CHECK(!terminating_) << "BeginTransfer but terminating.";

  //
  // 检查传输的ranges
  //
  if (ranges_.empty()) {
    // Note that after the callback returns this object may be destroyed.
    if (delegate_)
      delegate_->TransferComplete(this, true);
    return;
  }
  url_ = url;
  current_index_ = 0;
  bytes_received_this_range_ = 0;
  LOG(INFO) << "starting first transfer";
  //
  // 真正的数据传输由base_fetcher_来实现，基于url指定的协议，可能是FileFetcher或LibcurlHttpFetcher的对象
  //
  base_fetcher_->set_delegate(this);
  StartTransfer();
}
```

函数最后的调用操作`StartTransfer()`实际是`MultiRangeHttpFetcher`类的`StartTransfer()`函数。

#### `MultiRangeHttpFetcher`类的`StartTransfer()`

`StartTransfer()`中，还是进一步将`MultiRangeHttpFetcher`中下载数据相关的信息下发给`base_fetcher_`, 包括offset, length等。

```
// State change: Stopped or Downloading -> Downloading
void MultiRangeHttpFetcher::StartTransfer() {
  // 每一段数据由一个range指定，可以定义多个range，意味着下载多段数据
  // 看看当前是否已经下载完所有的ranges
  if (current_index_ >= ranges_.size()) {
    return;
  }

  // 获取current_index_指定的range
  Range range = ranges_[current_index_];
  LOG(INFO) << "starting transfer of range " << range.ToString();

  // 将current_index_指定的range的offset, length等信息下发给base_fetcher_
  bytes_received_this_range_ = 0;
  base_fetcher_->SetOffset(range.offset());
  if (range.HasLength())
    base_fetcher_->SetLength(range.length());
  else
    base_fetcher_->UnsetLength();
  // 同时向外城的delegate_对象通知当前下载数据的offset
  if (delegate_)
    delegate_->SeekToOffset(range.offset());
  base_fetcher_active_ = true;
  // base_fetcher开始正式工作
  base_fetcher_->BeginTransfer(url_);
}
```

当需要下载的数据段信息设置完成后，`base_fetcher_`调用`BeginTransfer()`开始真正的数据传输。

在`BuildUpdateActions()`中，根据升级数据URL开头的字符，`MultiRangeHttpFetcher`的`base_fetcher_`可能基于文件协议的`FileFetcher`类对象，也可能基于网络协议的`LibcurlHttpFetcher`类对象。

相比`LibcurlHttpFetcher`类，`FileFetcher`类的实现比较简单，无论选择这里的哪一个，对我们分析`base_fetcher_`的行为都不会有影响。为了避免陷入更多繁琐的细节，这里的讨论基于`FileFetcher`类的实现展开。如果需要了解`LibcurlHttpFetcher`，可以另外开篇分析。

基于`FileFetcher`类分析的`base_fetcher_->BeginTransfer()`调用实际上是`FileFetcher`类的`BeginTransfer()`函数。

#### `FileFetcher`类的`BeginTransfer()`操作

在`FileFetcher`的`BeginTransfer()`中，以FileStream流的方式打开文件，然后对文件进行寻址和并开始读取操作，如下：

```
// Begins the transfer, which must not have already been started.
void FileFetcher::BeginTransfer(const string& url) {
  // 检查传输状态
  CHECK(!transfer_in_progress_);

  // 再次检查下url是否以"file:///"字符串开头，因为FileFetcher中是以FileStream的方式进行操作的
  if (!SupportedUrl(url)) {
    LOG(ERROR) << "Unsupported file URL: " << url;
    // No HTTP error code when the URL is not supported.
    http_response_code_ = 0;
    CleanUp();
    if (delegate_)
      delegate_->TransferComplete(this, false);
    return;
  }

  // 从url中提取文件路径
  string file_path = url.substr(strlen("file://"));
  // FileStream以Read的方式打开文件
  stream_ =
      brillo::FileStream::Open(base::FilePath(file_path),
                               brillo::Stream::AccessMode::READ,
                               brillo::FileStream::Disposition::OPEN_EXISTING,
                               nullptr);

  // 如果打开失败，将此错误模拟成HTTP响应的kHttpResponseNotFound错误码
  if (!stream_) {
    LOG(ERROR) << "Couldn't open " << file_path;
    http_response_code_ = kHttpResponseNotFound;
    CleanUp();
    if (delegate_)
      delegate_->TransferComplete(this, false);
    return;
  }
  // 正常打开的情况下，模拟HTTP成功响应kHttpResponseOk
  http_response_code_ = kHttpResponseOk;

  // 根据offset对流文件进行寻址，定位读取的起始位置
  if (offset_)
    stream_->SetPosition(offset_, nullptr);
  // 初始化已经读取的字节数为0
  bytes_copied_ = 0;
  transfer_in_progress_ = true;
  // 数据读取操作
  ScheduleRead();
}
```

函数`BeginTransfer()`最后一步调用`ScheduleRead`调用就是当前`FileFetcher`类的`ScheduleRead()`函数。

#### `FileFetcher`类的`ScheduleRead()`操作

`ScheduleRead()`函数包含了具体的读取操作，我们可以看到这里是通过异步读取的方式操作的。

调用异步读取操作接口`ReadAsync()`，将流文件中的数据读取到`buffer_`指定的缓冲区中，读取成功执行`OnReadDoneCallback()`回调操作；读取失败执行`OnReadErrorCallback()`回调操作。

```
void FileFetcher::ScheduleRead() {
  // 检查读取状态
  // transfer_paused_为true表示暂停，ongoing_read_为true表示异步读取操作已经开始(在结束后会被设置为false)
  if (transfer_paused_ || ongoing_read_ || !transfer_in_progress_)
    return;

  // 设置缓冲区大小
  buffer_.resize(kReadBufferSize);
  // 根据缓冲区大小和剩余字节数决定需要读取的字节数
  size_t bytes_to_read = buffer_.size();
  if (data_length_ >= 0) {
    bytes_to_read = std::min(static_cast<uint64_t>(bytes_to_read),
                             data_length_ - bytes_copied_);
  }

  // bytes_to_read为0，表示数据读取完了
  // 调用通过OnReadDoneCallback(0)通知外层代理对象MultiRangeHttpFetcher数据读取完成了。
  if (!bytes_to_read) {
    OnReadDoneCallback(0);
    return;
  }

  // 发起异步读取操作，设置读取操作成功和失败的回调函数
  // 如果操作异步读取调用成功，则ongoing_read_会被设置为true，否则设置为false
  // 因此ongoing_read_为true表示已经开始了数据的异步读取
  ongoing_read_ = stream_->ReadAsync(
      buffer_.data(),
      bytes_to_read,
      base::Bind(&FileFetcher::OnReadDoneCallback, base::Unretained(this)),
      base::Bind(&FileFetcher::OnReadErrorCallback, base::Unretained(this)),
      nullptr);

  // 异步操作读取失败，通知外层代理对象读取失败
  if (!ongoing_read_) {
    LOG(ERROR) << "Unable to schedule an asynchronous read from the stream.";
    CleanUp();
    if (delegate_)
      delegate_->TransferComplete(this, false);
  }
}
```

从上面`ScheduleRead()`可以看到，数据并不是一次性读完，而是每次只读取`bytes_to_read`大小的数据。成功读取后调用`OnReadDoneCallback()`，在`OnReadDoneCallback()`内部再次触发`ScheduleRead()`，依次循环，直到读取完所有数据。

```
void FileFetcher::OnReadDoneCallback(size_t bytes_read) {
  // 将ongoing_read_设置为false，说明read操作结束，只有这样才能在ScheduleRead()继续读取
  ongoing_read_ = false;
  // 如果待读取的字节数为0，说明所有读取已经完成
  // delegate_->TransferComplete()操作向外层的download_action_对象通知传输完成
  // download_action_会在TransferComplete()操作中使用processor_->ActionComplete通知ActionProcessor任务完成
  // ActionProcessor接收到任务完成通知后，会挑选下一个任务进行操作
  // 
  if (bytes_read == 0) {
    CleanUp();
    // 通知外层的download_action_对象传输完成
    if (delegate_)
      delegate_->TransferComplete(this, true);
  } else {
    // 如果待读取的字节数不为0，说明当前发起的异步读取操作完成，获取到bytes_read字节的数据
    // delegate_->ReceivedBytes()操作向外层的download_action_对象通知接收到bytes_read字节的数据
    // download_action_会在ReceivedBytes()中调用DeltaPerformer类的实例writer_通过Write操作解析的数据并更新到相应分区
    // 所以关于分区数据的更新重点在download_action_->writer_->Write()操作。
    //
  
    // 递增已经复制的字节数
    bytes_copied_ += bytes_read;
    // 通知外层的download_action_对象目前读取到了bytes_read字节的数据
    if (delegate_)
      delegate_->ReceivedBytes(this, buffer_.data(), bytes_read);
    ScheduleRead();
  }
}
```

- 所有数据传输完成，`OnReadDoneCallback()`通过`delegate_->TransferComplete()`操作通知外层的`download_action_`对象通知传输完成
- 接收到传输数据，`OnReadDoneCallback()`通过`delegate_->ReceivedBytes()`操作向外层的`download_action_`对象通知接收到bytes_read字节的数据

如果`ScheduleRead()`函数发起的异步读取操作失败，则回调处理比较简单，就是通过`delegate_->TransferComplete()`操作通知外层的`download_action_`对象传输失败。
```
void FileFetcher::OnReadErrorCallback(const brillo::Error* error) {
  LOG(ERROR) << "Asynchronous read failed: " << error->GetMessage();
  CleanUp();
  if (delegate_)
    delegate_->TransferComplete(this, false);
}
```

在异步读取成功的回调函数`OnReadDoneCallback()`中会调用外层代理对象的`ReceivedBytes()`和`TransferComplete()`函数。在这里，外层代理对象对应的类就是`DownloadAction`。

#### `DownloadAction`类的`ReceivedBytes()`和`TransferComplete()`操作

在`FileFetcher`中发起异步数据成功读取后，如果全部数据已经读取完成，则调用`DownloadAction`的`TransferComplete()`结束数据传输；在没有读取完之前，每次接收到数据会调用`DownloadAction`的`ReceivedBytes()`操作。

我们先来看看收到数据时`DownloadAction`类的`ReceivedBytes()`操作：
```
void DownloadAction::ReceivedBytes(HttpFetcher* fetcher,
                                   const void* bytes,
                                   size_t length) {
  // 如果是p2p方式，更新接收到的数据信息，Android系统默认不使用p2p方式，不做讨论
  // Note that bytes_received_ is the current offset.
  if (!p2p_file_id_.empty()) {
    WriteToP2PFile(bytes, length, bytes_received_);
  }

  // 更新已经收到的数据长度信息bytes_received_
  bytes_received_ += length;
  if (delegate_ && download_active_) {
    // 通知download_aciton_的外层委托对象update_attempter_接收到了length字节的数据
    // 在update_attempter_的BytesReceived()函数中会更新下载的进度并向Update Engine客户端发送进度通知
    delegate_->BytesReceived(
        length, bytes_received_, install_plan_.payload_size);
  }
  //
  // 重点来了，DownloadAction的成员writer_实际上是DeltaPerformer的类对象
  // DeltaPerformer类在Write操作中会解析下载得到的数据，得到如何写入的具体信息，例如：
  // 包括下载数据的元数据，分区信息，具体的写入操作信息等。
  // 关于DeltaPerformer类，会另起一篇博客详细分析。
  //
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

  // 跟p2p相关，Android没有使用p2p方式，不用管
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

`DownloadAction`在接收到数据后会调用`ReceivedBytes()`，在其中主要就是两件事：
1. 告知外层的`update_attempter_`新收到了数据，`update_attempter_`最终会向客户端发送进度更新的数据
2. 调用`DeltaPerformer`类对象`writer_`解析下载的数据并更新到相应的分区中

再来看看所有数据接收完成时，`DownloadAction`类的`TransferComplete()`操作:
```
void DownloadAction::TransferComplete(HttpFetcher* fetcher, bool successful) {
  // 如果DeltaPerformer类对象writer_还健在，那就先关闭。有开有关，有来有去。
  if (writer_) {
    LOG_IF(WARNING, writer_->Close() != 0) << "Error closing the writer.";
    writer_ = nullptr;
  }
  
  // 好吧，下载已经结束了，所以download_active_设置为false
  download_active_ = false;
  ErrorCode code =
      successful ? ErrorCode::kSuccess : ErrorCode::kDownloadTransferError;
  // 根据升级时传入的payload参数，再同下载得到的参数比较下
  if (code == ErrorCode::kSuccess && delta_performer_.get()) {
    code = delta_performer_->VerifyPayload(install_plan_.payload_hash,
                                           install_plan_.payload_size);
    if (code != ErrorCode::kSuccess) {
      LOG(ERROR) << "Download of " << install_plan_.download_url
                 << " failed due to payload verification error.";
      // Delete p2p file, if applicable.
      if (!p2p_file_id_.empty())
        CloseP2PSharingFd(true);
    }
  }

  // 将install_plan_设置为当前Action的OutputObject
  // Write the path to the output pipe if we're successful.
  if (code == ErrorCode::kSuccess && HasOutputPipe())
    SetOutputObject(install_plan_);
  // 通知ActionProcessor，当前操作完成啦
  processor_->ActionComplete(this, code);
}
```

完成所有数据的接收后，`DownloadAction`调用`TransferComplete()`，在其中也主要就两件事：
1. 校验下载的数据跟升级传入的hash是否一致，如果不一致，那当然是出错了
2. 通知ActionProcessor当前操作完成了，这样ActionProcessor就选择下一阶段的Action运行

### <span id="DownloadSummary">2.3 DownloadAction总结</span>

总体来说，Upload Engine服务端更新时是一边下载一边写入的。

所以DownloadAction操作包含两个部分，升级数据的下载和写入。前者交由`MultiRangeHttpFetcher`的类对象`http_fetcher_`实现，后者交由`DeltaPerformer`的类对象`writer_`实现。

下载部分，根据升级传入的url起始字节是否包含"file:///"字符串决定是使用FileFetcher还是LibcurlHttpFetcher作为具体的数据下载器，实现上FileFetcher比较简单，主要是对文件流进行读取。

所以以FileFetcher为例，分析了DownloadAction数据下载的具体流程。

DownloadAction设置数据下载的范围，FileFetcher每次异步读取128K数据，成功后通知DownloadAction进行处理。DownloadAction收到通知后，一方面向外通知新收到了数据，另一方面调用`DeltaPerformer`的类对象`writer_`对下载的数据进行处理。

写入部分，DownloadAction`DeltaPerformer`的类对象`writer_`对下载的数据先进行分析，提取分区和各种操作信息，最后根据这些信息将数据写入相应的分区中。下载数据的分析，元数据的提取和分区的更新都在`DeltaPerformer`类中实现，后续会单独用一篇对`DeltaPerformer`类进行分析。

## <span id="FilesystemVerifierAction">3. FilesystemVerifierAction</span>

### 3.1 FilesystemVerifierAction的初始化

在`BuildUpdateActions()`中通过传入`boot_control_`和`VerifierMode::kVerifyTargetHash`用于构造FilesystemVerifierAction的对象`dst_filesystem_verifier_action`:
```
void UpdateAttempterAndroid::BuildUpdateActions(const string& url) {
  ...
  shared_ptr<FilesystemVerifierAction> dst_filesystem_verifier_action(
      new FilesystemVerifierAction(boot_control_,
                                   VerifierMode::kVerifyTargetHash));

  ...
}
```

在构造函数的实现中，传入的两个参数分别用于设置`boot_control_`和`verifier_mode_`成员：
```
FilesystemVerifierAction::FilesystemVerifierAction(
    const BootControlInterface* boot_control,
    VerifierMode verifier_mode)
    : verifier_mode_(verifier_mode),
      boot_control_(boot_control) {}
```

### 3.2 FilesystemVerifierAction的功能操作

#### `FilesystemVerifierAction`类的`PerformAction()`

在DownloadAction结束后，ActionProcessor会挑选DownloadAction的下一个Action，即FilesystemVerifierAction并调用其`PerformAction()`操作：

```
void FilesystemVerifierAction::PerformAction() {
  // Will tell the ActionProcessor we've failed if we return.
  ScopedActionCompleter abort_action_completer(processor_, this);

  //
  // 获取上一个Action，即DownloadAction传递过来的install_plan_，里面包含了升级相关的元数据
  //
  if (!HasInputObject()) {
    LOG(ERROR) << "FilesystemVerifierAction missing input object.";
    return;
  }
  install_plan_ = GetInputObject();

  //
  // 如果当前:
  // 1). 以增量方式(InstallPayloadType::kDelta)升级
  // 2). install_plan_中分区信息partitions为空
  // 3). 需要计算source partition的Hash(VerifierMode::kComputeSourceHash)
  // 4). DeltaPerformer::kSupportedMinorPayloadVersion < kOpSrcHashMinorPayloadVersion
  // 如果满足以上4个条件，则提取当前source的system和boot分区信息填充到install_plan_.partitions中。
  // 这里不太清楚为什么需要满足第4个条件？
  //
  // For delta updates (major version 1) we need to populate the source
  // partition hash if not pre-populated.
  if (install_plan_.payload_type == InstallPayloadType::kDelta &&
      install_plan_.partitions.empty() &&
      verifier_mode_ == VerifierMode::kComputeSourceHash &&
      DeltaPerformer::kSupportedMinorPayloadVersion <
          kOpSrcHashMinorPayloadVersion) {
    LOG(INFO) << "Using legacy partition names.";
    InstallPlan::Partition part;
    string part_path;

    // 指定名为kLegacyPartitionNameRoot的分区("system")
    part.name = kLegacyPartitionNameRoot;
    // 取得source槽中"system"分区的路径，例如：/dev/block/by-name/system_0
    if (!boot_control_->GetPartitionDevice(
        part.name, install_plan_.source_slot, &part_path))
      return;
    int block_count = 0, block_size = 0;
    // 取得source槽中"system"分区的block cound和block size信息，用于计算分区size
    // 由于"system"分区是基于文件系统的，所以这里使用GetFilesystemSize()接口
    if (utils::GetFilesystemSize(part_path, &block_count, &block_size)) {
      part.source_size = static_cast<int64_t>(block_count) * block_size;
      LOG(INFO) << "Partition " << part.name << " size: " << part.source_size
                << " bytes (" << block_count << "x" << block_size << ").";
    }
    // 将source槽对应"system"分区信息添加到install_plan_的partitions中
    install_plan_.partitions.push_back(part);

    // 指定名为kLegacyPartitionNameKernel的分区("boot")
    part.name = kLegacyPartitionNameKernel;
    // 取得source槽中"boot"分区的路径，例如：/dev/block/by-name/boot_0
    if (!boot_control_->GetPartitionDevice(
        part.name, install_plan_.source_slot, &part_path))
      return;
    // 取得source槽中"boot"分区的size信息
    // 由于"boot"分区不带文件系统，所以直接通过设备文件的路径获取其容量大小
    off_t kernel_part_size = utils::FileSize(part_path);
    if (kernel_part_size < 0)
      return;
    LOG(INFO) << "Partition " << part.name << " size: " << kernel_part_size
              << " bytes.";
    part.source_size = kernel_part_size;
    // 将source槽对应"boot"分区信息添加到install_plan_的partitions中
    install_plan_.partitions.push_back(part);
  }

  // 如果install_plan_中不包含任何分区信息，说明不需要对分区进行校验，这里就成功结束PerformAction操作
  if (install_plan_.partitions.empty()) {
    LOG(INFO) << "No partitions to verify.";
    if (HasOutputPipe())
      SetOutputObject(install_plan_);
    abort_action_completer.set_code(ErrorCode::kSuccess);
    return;
  }

  // 正式开始分区Hash的计算
  StartPartitionHashing();
  abort_action_completer.set_should_complete(false);
}
```

在`PerformAction()`的最后会调用`StartPartitionHashing()`开始计算各个分区的Hash，因此接下来看看`StartPartitionHashing()`的实现。

#### `FilesystemVerifierAction`类的`StartPartitionHashing()`

```
void FilesystemVerifierAction::StartPartitionHashing() {
  // install_plan_.partitions 存放了当前所有要操作的分区信息
  // 如果 partition_index_ == install_plan_.partitions.size(), 即指向了最后一个分区之后，则说明已经操作完了所有分区
  // 从下面的注释可见：
  // 验证完最后一个分区之后，不应该是VerifierMode::kVerifySourceHash的方式，因为只有当出现错误的时候才需要通过kVerifySourceHash计算source槽的Hash
  // 如果出现这种情况，则应当退出。
  // 正常情况下，如果验证完最后一个分区(partition_index_ == install_plan_.partitions.size())，则操作成功(ErrorCode::kSuccess)，并执行清理工作并返回
  if (partition_index_ == install_plan_.partitions.size()) {
    // We never called this action with kVerifySourceHash directly, if we are in
    // this mode, it means the target partition verification has failed, so we
    // should set the error code to reflect the error in target.
    if (verifier_mode_ == VerifierMode::kVerifySourceHash)
      Cleanup(ErrorCode::kNewRootfsVerificationError);
    else
      Cleanup(ErrorCode::kSuccess);
    return;
  }
  InstallPlan::Partition& partition =
      install_plan_.partitions[partition_index_];

  string part_path;
  // 根据不同verifier_mode_来决定是获取source槽，还是target槽的分区path以及待进行Hash操作的remaining_size_
  switch (verifier_mode_) {
    case VerifierMode::kComputeSourceHash:
    case VerifierMode::kVerifySourceHash:
      boot_control_->GetPartitionDevice(
          partition.name, install_plan_.source_slot, &part_path);
      remaining_size_ = partition.source_size;
      break;
    case VerifierMode::kVerifyTargetHash:
      boot_control_->GetPartitionDevice(
          partition.name, install_plan_.target_slot, &part_path);
      remaining_size_ = partition.target_size;
      break;
  }
  LOG(INFO) << "Hashing partition " << partition_index_ << " ("
            << partition.name << ") on device " << part_path;
  if (part_path.empty())
    return Cleanup(ErrorCode::kFilesystemVerifierError);

  // 根据分区路径，将分区以FileStream方式打开进行操作
  brillo::ErrorPtr error;
  src_stream_ = brillo::FileStream::Open(
      base::FilePath(part_path),
      brillo::Stream::AccessMode::READ,
      brillo::FileStream::Disposition::OPEN_EXISTING,
      &error);

  // 分区打开失败处理
  if (!src_stream_) {
    LOG(ERROR) << "Unable to open " << part_path << " for reading";
    return Cleanup(ErrorCode::kFilesystemVerifierError);
  }

  // 指定每次计算Hash的缓冲区大小为kReadFileBufferSize, 即：128 * 1024
  buffer_.resize(kReadFileBufferSize);
  // 设置读取完成标识为false，如果整个分区被读取完了，则read_done_被设置为true
  read_done_ = false;
  // 构造Hash计算器, 用于计算所读取数据的Hash
  hasher_.reset(new HashCalculator());

  // 开始读取第一块数据进行Hash计算
  // Start the first read.
  ScheduleRead();
}
```

到这里，发现FilesystemVerifierAction还没有开始正式工作，之前操作都是为数据读取和校验做准备。真正的数据读取由函数最后的`ScheduleRead()`调用执行。

#### `FilesystemVerifierAction`类的`ScheduleRead()`,`OnReadDoneCallback()`和`OnReadErrorCallback()`

从`ScheduleRead()`的名字看，似乎只是对数据读取进行Schedule调度，有点像异步操作的样子，不放看看代码实现:
```
void FilesystemVerifierAction::ScheduleRead() {
  // 实际读取的数据大小bytes_to_read取缓冲区大小和
  size_t bytes_to_read = std::min(static_cast<int64_t>(buffer_.size()),
                                  remaining_size_);
  // 如果需要读取的数据为0，说明操作已经进行完成了，因此调用OnReadDoneCallback完成操作
  if (!bytes_to_read) {
    OnReadDoneCallback(0);
    return;
  }

  // 以异步方式发起读取动作
  // 并注册两个回调函数：OnReadDoneCallback和OnReadErrorCallback，分别对应于数据读取成功和失败的情况
  bool read_async_ok = src_stream_->ReadAsync( // 采用ReadAsync异步方式读取数据
    buffer_.data(), // 指定数据读取缓冲区
    bytes_to_read,  // 指定数据读取字节数
    base::Bind(&FilesystemVerifierAction::OnReadDoneCallback,  // 数据读取成功执行的回调操作
               base::Unretained(this)),
    base::Bind(&FilesystemVerifierAction::OnReadErrorCallback, // 数据读取失败的毁掉操作
               base::Unretained(this)),
    nullptr);

  // 异步读取操作ReadAsync失败，则调用Cleanup并错误
  if (!read_async_ok) {
    LOG(ERROR) << "Unable to schedule an asynchronous read from the stream.";
    Cleanup(ErrorCode::kError);
  }
}
```

分别来看看数据的异步读取成功和失败的回调操作。

- 数据异步读取成功

实际上，当异步数据读取成功后，读取到的数据会存放在`buffer_`对应的缓冲区中, 读取到的数据大小通过函数参数传递过来：
```
void FilesystemVerifierAction::OnReadDoneCallback(size_t bytes_read) {
  // 如果读取到的数据为0，说明读取完成了。
  if (bytes_read == 0) {
    read_done_ = true;
  } else { // 读取到的数据不为0，需要继续读取
    remaining_size_ -= bytes_read;  // 计算剩余数据
    CHECK(!read_done_);
    // 对读取到的数据进行Hash操作(实际上是SHA256_Update操作)
    // 注意这里是Update操作，在很多情况下，由于需要计算Hash操作的数据很多，例如2G数据，一次性计算所有数据的Hash显然不可能，因此选择分片累积进行
    // 所以此次的Hash计算需要基于上一次的Hash计算结果和当前的数据进行，从而得到到目前为止所有数据的Hash
    if (!hasher_->Update(buffer_.data(), bytes_read)) {
      LOG(ERROR) << "Unable to update the hash.";
      Cleanup(ErrorCode::kError);
      return;
    }
  }

  // 如果当前操作被取消(ActionProcessor调用TerminateProcessing操作), 那么就设置ErrorCode::kError错误并进行相应的清理工作
  // We either terminate the current partition or have more data to read.
  if (cancelled_)
    return Cleanup(ErrorCode::kError);

  // 如果读取完成(read_done_ == true)或者没有剩余数据remaining_size_了， 则调用FinishPartitionHashing()进行收尾工作
  if (read_done_ || remaining_size_ == 0) {
    // 如果read_done_ == true的情况，但此时又还有没有读取的数据，那肯定就是出错了，设置ErrorCode::kFilesystemVerifierError错误
    if (remaining_size_ != 0) {
      LOG(ERROR) << "Failed to read the remaining " << remaining_size_
                 << " bytes from partition "
                 << install_plan_.partitions[partition_index_].name;
      return Cleanup(ErrorCode::kFilesystemVerifierError);
    }
    
    // 执行分区Hash的收尾工作
    return FinishPartitionHashing();
  }
  
  // 如果读取还没有完成，则发起下一次的异步读取校验操作
  ScheduleRead();
}
```
在数据读取成功的情况下，需要累积对数据进行Hash计算操作。如果所有读取都完成了，则调用`FinishPartitionHashing()`进行后续的收尾工作，否则调用`ScheduleRead()`发起下一次的异步读取和Hash计算操作。

- 数据异步读取失败

数据异步读取失败的回调操作比较简单，设置ErrorCode::kError错误并进行相应的清理工作

```
void FilesystemVerifierAction::OnReadErrorCallback(
      const brillo::Error* error) {
  // TODO(deymo): Transform the read-error into an specific ErrorCode.
  LOG(ERROR) << "Asynchronous read failed.";
  Cleanup(ErrorCode::kError);
}
```

我们再来看看数据操作的两个相关操作：数据读取完毕的收尾工作和清理工作。

- 数据读取完毕的收尾工作

既然FilesystemVerifierAction的工作就是计算分区的Hash，那数据读取的最后一步就是将前面的Hash综合起来得到最终的Hash结果。

```
void FilesystemVerifierAction::FinishPartitionHashing() {
  // 通过Finalize()操作计算最终的Hash结果
  if (!hasher_->Finalize()) {
    LOG(ERROR) << "Unable to finalize the hash.";
    return Cleanup(ErrorCode::kError);
  }
  InstallPlan::Partition& partition =
      install_plan_.partitions[partition_index_];
  LOG(INFO) << "Hash of " << partition.name << ": " << hasher_->hash();

  // 根据verifier_mode_的模式，决定计算的hash应该是source槽还是target槽
  switch (verifier_mode_) {
    // 计算source槽的Hash结果自然要存放到source_hash中
    case VerifierMode::kComputeSourceHash:
      partition.source_hash = hasher_->raw_hash();
      partition_index_++;
      break;
    // 如果预先保存的target_hash同计算得到的raw_hash不一致，则进一步检查source槽的hash
    case VerifierMode::kVerifyTargetHash:
      if (partition.target_hash != hasher_->raw_hash()) {
        LOG(ERROR) << "New '" << partition.name
                   << "' partition verification failed.";
        if (DeltaPerformer::kSupportedMinorPayloadVersion <
            kOpSrcHashMinorPayloadVersion)
          return Cleanup(ErrorCode::kNewRootfsVerificationError);
        // If we support per-operation source hash, then we skipped source
        // filesystem verification, now that the target partition does not
        // match, we need to switch to kVerifySourceHash mode to check if it's
        // because the source partition does not match either.
        verifier_mode_ = VerifierMode::kVerifySourceHash;
        partition_index_ = 0;
      } else {
        partition_index_++; // 切换到下一个分区
      }
      break;
    // 如果预先保存的source_hash同计算得到的raw_hash不一致，那就出现错误了
    case VerifierMode::kVerifySourceHash:
      if (partition.source_hash != hasher_->raw_hash()) {
        LOG(ERROR) << "Old '" << partition.name
                   << "' partition verification failed.";
        return Cleanup(ErrorCode::kDownloadStateInitializationError);
      }
      partition_index_++; // 切换到下一个分区
      break;
  }
  
  // 当前分区的计算完成了，所以清空hash计算结果和数据读取缓冲区
  // Start hashing the next partition, if any.
  hasher_.reset();
  buffer_.clear();
  // 计算当前分区时得到stream, 结束时将stream关闭
  src_stream_->CloseBlocking(nullptr);
  // 计算下一个分区的Hash，如果已经计算完所有分区的Hash，则StartPartitionHashing()会执行清理工作
  StartPartitionHashing();
}
```

- 清理工作
```
void FilesystemVerifierAction::Cleanup(ErrorCode code) {
  // 复位src_stream_
  src_stream_.reset();
  // 清空缓冲区
  // This memory is not used anymore.
  buffer_.clear();

  if (cancelled_)
    return;
  // 如果当前操作成功完成，则将install_plan_设置为Action的OutpubObject
  if (code == ErrorCode::kSuccess && HasOutputPipe())
    SetOutputObject(install_plan_);
  // 通知ActionProcessor当前文件系统校验工作已经完成(ErrorCode包含了具体的完成状态)
  processor_->ActionComplete(this, code);
}
```

清理工作很简单，就是清理文件操作流和数据读取缓冲区，然后将最后的状态错误码通过`ActionComplete()`调用传递给ActionProcessor。

### <span id="VerifierSummary">3.3 FilesystemVerifierAction操作总结</span>

DownloadAction结束后，ActionProcessor会调用FilesystemVerifierAction进行文件系统的Hash校验工作，具体操作是逐个打开`install_plan_`里`partitions`成员包含的分区，以流文件的方式逐块读取(块大小为128*1024，即128K)分区内的数据并计算得到相应的Hash，再将计算得到的Hash同预先存放的Hash(`install_plan_`里`partitions`对应分区的`target_hash`)进行比较。所有分区的Hash比较完成后，ActionProcessor调度下一个Action执行。

换句话说，升级包制作程序会用升级前后的分区进行对比，因此升级包制作程序能够计算升级后的分区Hash信息并存放到升级包文件中。Update Engine下载升级包文件后通过解析可以得到预期升级完成后分区的Hash信息。

当升级数据下载完成并更新到磁盘后，分区内容理论上应该和预期升级完成后的分区是一样的，因此其Hash也应该一样。此时，读取升级分区的数据并计算得到实际Hash值，将其同下载的升级包里面的Hash进行比较。这就是FilesystemVerifierAction的工作任务。

## <span id="PostinstallRunnerAction">4. PostinstallRunnerAction</span>

### 4.1 PostinstallRunnerAction的初始化

在`BuildUpdateActions()`中通过传入`boot_control_`和`hardware_`用于构造PostinstallRunnerAction的对象`postinstall_runner_action`:

```
void UpdateAttempterAndroid::BuildUpdateActions(const string& url) {
  ...

  shared_ptr<PostinstallRunnerAction> postinstall_runner_action(
      new PostinstallRunnerAction(boot_control_, hardware_));

  ...
  postinstall_runner_action->set_delegate(this);

  ...
}
```

在构造函数的实现中，传入的两个参数分别用于设置`boot_control_`和`hardware_`成员：
```
  PostinstallRunnerAction(BootControlInterface* boot_control,
                          HardwareInterface* hardware)
      : boot_control_(boot_control), hardware_(hardware) {}
```

### 4.2 PostinstallRunnerAction的执行操作

#### `PostinstallRunnerAction`类的`PerformAction()`

在FilesystemVerifierAction结束后，ActionProcessor会挑选FilesystemVerifierAction的下一个Action，即PostinstallRunnerAction并调用其`PerformAction()`操作：

```
void PostinstallRunnerAction::PerformAction() {
  CHECK(HasInputObject());
  // 获取上一个Action，即FilesystemVerifierAction传递过来的install_plan_，里面包含了升级相关的元数据
  install_plan_ = GetInputObject();

  // 检查powerwash_required是否为true, 然后触发相应的动作，
  // 但是我检查代码，发现这里始终都是false, 具体分析见后面。
  if (install_plan_.powerwash_required) {
    if (hardware_->SchedulePowerwash()) {
      powerwash_scheduled_ = true;
    } else {
      return CompletePostinstall(ErrorCode::kPostinstallPowerwashError);
    }
  }

  // 将partition_weight_向量的数量调整为跟分区数一致，这样一个向量对应于一个分区
  // Initialize all the partition weights.
  partition_weight_.resize(install_plan_.partitions.size());
  total_weight_ = 0;
  // 遍历install_plan_.partitions包含的分区
  for (size_t i = 0; i < install_plan_.partitions.size(); ++i) {
    // TODO(deymo): This code sets the weight to all the postinstall commands,
    // but we could remember how long they took in the past and use those
    // values.
    // 逐个分区中run_postinstall的数值保存到partition_weight_数组中
    partition_weight_[i] = install_plan_.partitions[i].run_postinstall;
    // 累积所有分区的run_postinstall数值总和
    total_weight_ += partition_weight_[i];
  }
  accumulated_weight_ = 0;
  // 向外通知当前的更新进度
  ReportProgress(0);

  // 这里才是真正开始post install操作的地方
  PerformPartitionPostinstall();
}
```

> 关于一开始的`powerwash_required`检查，我其实不太明白到底是做什么的，好歹影响不大。
> 
> 我尝试在`update_engine`目录下使用grep搜索`powerwash_required`，以下是除开包含`unittest`的搜索结果：
> ```
> src/system/update_engine$ grep -rn powerwash_required . | grep -v unittest
> ./update_attempter_android.cc:181:  install_plan_.powerwash_required =
> ./payload_consumer/postinstall_runner_action.cc:58:  if (install_plan_.powerwash_required) {
> ./payload_consumer/install_plan.h:108:  bool powerwash_required{false};
> ./payload_consumer/install_plan.cc:84:            << ", powerwash_required: " << utils::ToString(powerwash_required);
> ./update_attempter.cc:725:  install_plan.powerwash_required = powerwash;
> ./omaha_response_handler_action.cc:124:    install_plan_.powerwash_required = true;
> ```
> 
> 其中，`update_attempter.cc`和`omaha_response_handler_action.cc`并没有被项目使用，所以`update_attempter_android.cc`的第181行是唯一设置`powerwash_required`的地方：
> ```
> src/system/update_engine$ grep -n powerwash_required update_attempter_android.cc -A 3 -B 3 
> 178-  install_plan_.target_slot = install_plan_.source_slot == 0 ? 1 : 0;
> 179-
> 180-  int data_wipe = 0;
> 181:  install_plan_.powerwash_required =
> 182-      base::StringToInt(headers[kPayloadPropertyPowerwash], &data_wipe) &&
> 183-      data_wipe != 0;
> 184-
> ```
> 由于第180行的`data_wipe=0`，所以第181~183行中`powerwash_required`计算的结果总是为false。

`PerformAction()`中，先检查`powerwash_required`进行相应操作，实际上我发现判断的结果总是为false，所以不考虑对应的操作。

然后保存各个分区需要进行post install的操作数量，并调用`ReportProgress()`向外通知进度。最后通过`PerformPartitionPostinstall()`开始真正的post install script的操作。

先来看看`PerformAction()`中调用的`ReportProgress()`的实现。

#### `PostinstallRunnerAction`类的`ReportProgress()`

`PerformAction()`调用的函数中，`ReportProgress(0)`比较简单：
```
void PostinstallRunnerAction::ReportProgress(double frac) {
  // 如果没有指定委托对象，则什么都不需要做
  if (!delegate_)
    return;
  // 当前分区指定的位置已经在所有分区的后面，说明已经遍历完了所有分区，将进度指示为"1.0"
  if (current_partition_ >= partition_weight_.size()) {
    delegate_->ProgressUpdate(1.);
    return;
  }
  if (!isfinite(frac) || frac < 0)
    frac = 0;
  if (frac > 1)
    frac = 1;
  // 计算post install action的进度
  double postinst_action_progress =
      (accumulated_weight_ + partition_weight_[current_partition_] * frac) /
      total_weight_;
  // 向外通知 post install action的进度
  delegate_->ProgressUpdate(postinst_action_progress);
}
```

这里主要是计算升级进度，调用`delegate_`的接口向外发送通知，这里的`delegate_`实际上就是`UpdateAttempterAndroid`类的对象`update_attempter_`。
因此这里`delegate_->ProgressUpdate()`执行的函数就是`UpdateAttempterAndroid`类的`ProgressUpdate()`函数。

分析完`ReportProgress()`再来看看`PerformAction()`中最后调用的`PerformPartitionPostinstall()`的实现。

#### `PostinstallRunnerAction`类的`PerformPartitionPostinstall()`

在`PerformAction()`的最后，调用`PerformPartitionPostinstall()`真正的去执行post install script的内容:
```
void PostinstallRunnerAction::PerformPartitionPostinstall() {
  // 检查download_url
  if (install_plan_.download_url.empty()) {
    LOG(INFO) << "Skipping post-install during rollback";
    // 在CompletePostinstall()中执行脚本安装的收尾工作
    return CompletePostinstall(ErrorCode::kSuccess);
  }

  // 如果当前分区的run_postinstall数量为0，那就检查下一个分区，直到检查完所有分区
  // Skip all the partitions that don't have a post-install step.
  while (current_partition_ < install_plan_.partitions.size() &&
         !install_plan_.partitions[current_partition_].run_postinstall) {
    VLOG(1) << "Skipping post-install on partition "
            << install_plan_.partitions[current_partition_].name;
    current_partition_++;
  }
  // 遍历完分区发现已经指向所有分区的最后了，那说明没有分区需要执行post install script操作
  // 也就意味着可以以成功的方式执行收尾工作了
  if (current_partition_ == install_plan_.partitions.size())
    return CompletePostinstall(ErrorCode::kSuccess);

  // 如果有分区需要执行post install script操作，那就取得对应分区的信息
  const InstallPlan::Partition& partition =
      install_plan_.partitions[current_partition_];

  // 获取需要执行操作的分区的名字
  const string mountable_device =
      utils::MakePartitionNameForMount(partition.target_path);
  // 取得的名字为空，显然出错了，执行错误处理
  if (mountable_device.empty()) {
    LOG(ERROR) << "Cannot make mountable device from " << partition.target_path;
    return CompletePostinstall(ErrorCode::kPostinstallRunnerError);
  }

  // 指定post install操作的目录
  // Perform post-install for the current_partition_ partition. At this point we
  // need to call CompletePartitionPostinstall to complete the operation and
  // cleanup.
#ifdef __ANDROID__
  fs_mount_dir_ = "/postinstall";
#else   // __ANDROID__
  TEST_AND_RETURN(
      utils::MakeTempDirectory("au_postint_mount.XXXXXX", &fs_mount_dir_));
#endif  // __ANDROID__

  // postinstall_path不能是绝对路径
  base::FilePath postinstall_path(partition.postinstall_path);
  if (postinstall_path.IsAbsolute()) {
    LOG(ERROR) << "Invalid absolute path passed to postinstall, use a relative"
                  "path instead: "
               << partition.postinstall_path;
    return CompletePostinstall(ErrorCode::kPostinstallRunnerError);
  }

  // postinstall_path是相对于/postinstall的路径，构建完整的绝对路径
  string abs_path =
      base::FilePath(fs_mount_dir_).Append(postinstall_path).value();
  // 再次检查abs_path是否是以"/postinstall"开始的路径      
  if (!base::StartsWith(
          abs_path, fs_mount_dir_, base::CompareCase::SENSITIVE)) {
    LOG(ERROR) << "Invalid relative postinstall path: "
               << partition.postinstall_path;
    return CompletePostinstall(ErrorCode::kPostinstallRunnerError);
  }

#ifdef __ANDROID__
  // In Chromium OS, the postinstall step is allowed to write to the block
  // device on the target image, so we don't mark it as read-only and should
  // be read-write since we just wrote to it during the update.

  // 将执行post-install的分区设置为read-only
  // Mark the block device as read-only before mounting for post-install.
  if (!utils::SetBlockDeviceReadOnly(mountable_device, true)) {
    return CompletePartitionPostinstall(
        1, "Error marking the device " + mountable_device + " read only.");
  }
#endif  // __ANDROID__

  // 将执行post-install的分区以read-only方式挂载
  if (!utils::MountFilesystem(mountable_device,
                              fs_mount_dir_,
                              MS_RDONLY,
                              partition.filesystem_type,
                              constants::kPostinstallMountOptions)) {
    return CompletePartitionPostinstall(
        1, "Error mounting the device " + mountable_device);
  }

  LOG(INFO) << "Performing postinst (" << partition.postinstall_path << " at "
            << abs_path << ") installed on device " << partition.target_path
            << " and mountable device " << mountable_device;

  // Logs the file format of the postinstall script we are about to run. This
  // will help debug when the postinstall script doesn't match the architecture
  // of our build.
  LOG(INFO) << "Format file for new " << partition.postinstall_path
            << " is: " << utils::GetFileFormat(abs_path);

  // 使用abs_path, target_slot, kPostinstallStatusFd和target_path填充command构造运行的参数
  // Runs the postinstall script asynchronously to free up the main loop while
  // it's running.
  vector<string> command = {abs_path};
#ifdef __ANDROID__
  // In Brillo and Android, we pass the slot number and status fd.
  command.push_back(std::to_string(install_plan_.target_slot));
  command.push_back(std::to_string(kPostinstallStatusFd));
#else
  // Chrome OS postinstall expects the target rootfs as the first parameter.
  command.push_back(partition.target_path);
#endif  // __ANDROID__

  // 相当于异步执行命令："abs_path target_slot kPostinstallStatusFd target_path"
  // 返回值current_command_是子进程的pid
  current_command_ = Subprocess::Get().ExecFlags(
      command,
      Subprocess::kRedirectStderrToStdout,
      {kPostinstallStatusFd},
      base::Bind(&PostinstallRunnerAction::CompletePartitionPostinstall,
                 base::Unretained(this)));
  // Subprocess::Exec should never return a negative process id.
  CHECK_GE(current_command_, 0);

  // 如果current_command_为0
  if (!current_command_) {
    CompletePartitionPostinstall(1, "Postinstall didn't launch");
    return;
  }

  // Monitor the status file descriptor.
  progress_fd_ =
      Subprocess::Get().GetPipeFd(current_command_, kPostinstallStatusFd);
  int fd_flags = fcntl(progress_fd_, F_GETFL, 0) | O_NONBLOCK;
  if (HANDLE_EINTR(fcntl(progress_fd_, F_SETFL, fd_flags)) < 0) {
    PLOG(ERROR) << "Unable to set non-blocking I/O mode on fd " << progress_fd_;
  }

  progress_task_ = MessageLoop::current()->WatchFileDescriptor(
      FROM_HERE,
      progress_fd_,
      MessageLoop::WatchMode::kWatchRead,
      true,
      base::Bind(&PostinstallRunnerAction::OnProgressFdReady,
                 base::Unretained(this)));
}
```

函数中，完成单个分区的post install操作时会调用`CompletePartitionPostinstall()`进行一些必要的处理。

#### `PostinstallRunnerAction`类的`CompletePartitionPostinstall()`

```
void PostinstallRunnerAction::CompletePartitionPostinstall(
    int return_code, const string& output) {
  current_command_ = 0;
  Cleanup();

  if (return_code != 0) {
    LOG(ERROR) << "Postinst command failed with code: " << return_code;
    ErrorCode error_code = ErrorCode::kPostinstallRunnerError;

    if (return_code == 3) {
      // This special return code means that we tried to update firmware,
      // but couldn't because we booted from FW B, and we need to reboot
      // to get back to FW A.
      error_code = ErrorCode::kPostinstallBootedFromFirmwareB;
    }

    if (return_code == 4) {
      // This special return code means that we tried to update firmware,
      // but couldn't because we booted from FW B, and we need to reboot
      // to get back to FW A.
      error_code = ErrorCode::kPostinstallFirmwareRONotUpdatable;
    }

    // If postinstall script for this partition is optional we can ignore the
    // result.
    if (install_plan_.partitions[current_partition_].postinstall_optional) {
      LOG(INFO) << "Ignoring postinstall failure since it is optional";
    } else {
      return CompletePostinstall(error_code);
    }
  }
  accumulated_weight_ += partition_weight_[current_partition_];
  current_partition_++;
  ReportProgress(0);

  PerformPartitionPostinstall();
}
```

`PerformPartitionPostinstall()`中，当完成所有分区的post install操作时会调用`CompletePostinstall()`进行收尾工作。

#### `PostinstallRunnerAction`类的`CompletePostinstall()`

```
void PostinstallRunnerAction::CompletePostinstall(ErrorCode error_code) {
  //
  // 在DownloadAction::PerformAction()的一开始就将target_slot对应分区设置为unbootable，即不可启动。
  // 如果post install成功执行，则将target_slot对应分区标记为Active Slot，可以启动。
  // 
  // We only attempt to mark the new slot as active if all the postinstall
  // steps succeeded.
  if (error_code == ErrorCode::kSuccess &&
      !boot_control_->SetActiveBootSlot(install_plan_.target_slot)) {
    // 分区标记失败则设置错误ErrorCode::kPostinstallRunnerError
    error_code = ErrorCode::kPostinstallRunnerError;
  }

  ScopedActionCompleter completer(processor_, this);
  completer.set_code(error_code);

  // 在前面操作失败的情况下，如果需要powerwash_操作，则取消该操作
  if (error_code != ErrorCode::kSuccess) {
    LOG(ERROR) << "Postinstall action failed.";

    // Undo any changes done to trigger Powerwash.
    if (powerwash_scheduled_)
      hardware_->CancelPowerwash();

    return;
  }

  // 如果ActionPipe中PostinstallRunnerAction后面还有其它Action需要用到PostinstallRunnerAction的Output
  // 则将install_plan_设置为其OutputObject
  // 实际上，在BuildUpdateActions()中构建的Action，PostinstallRunnerAction属于最后一个，所以这里不会再执行了。
  LOG(INFO) << "All post-install commands succeeded";
  if (HasOutputPipe()) {
    SetOutputObject(install_plan_);
  }
}
```

所有分区处理结束后的收尾工作很简单，将`target_slot`标记为Active分区，如果后续还有其它Action，则设置`install_plan_`为ActionPipe的输出作为下一个Action的输入。

### <span id="PostInstallSummary">4.3 PostinstallRunnerAction的总结</span>

我编译了一个全量(full)的更新包，从升级的日志看，里面并没有生成post install script，所以升级在PostinstallRunnerAction任务的这一步并没有执行特别的script，而只是将`target_slot`标记为活动(active)分区而已。

后续会分析升级数据的内容，到时候再检查实际是否跟这里的结论一样(默认没有post install script)。

## <span id="Summary">5. Action的执行流程</span>

在调用`ApplyPayload()`进行升级时，`UpdateAttempterAndroid`类默认会在`BuildUpdateActions()`函数内构建4个Action:
- InstallPlanAction: `install_plan_action`
- DownloadAction: `download_action`
- FilesystemVerifierAction: `dst_filesystem_verifier_action`
- PostinstallRunnerAction: `postinstall_runner_action`

这4个Action随后会通过`BondActions()`操作，将上一个Action的OutputObject与下一个Action的InputObject连接起来，类似管道那样，其中传递的信息就是`install_plan_`，包含了升级信息数据。

构建的4个Action操作也会进入ActionProcessor的Action队列，当调用`StartProcessing()`后，ActionProcessor会逐个取出Action队列的Action，然后调用每个Action的`PerformAction()`操作。当一个Action结束后，会通知ActionProcessor调用`ActionComplete()`选择下一个Action执行，直到ActionProcessor的Action队列中不再有任务为止。

### InstallPlanAction

InstallPlanAction的任务就是将构建的`install_plan_`传递给DownloadAction，没有其他的功能代码。

InstallPlanAction任务结束后，ActionProcessor会挑选下一个任务DownloadAction来执行。

### DownloadAction

DownloadAction获取InstallPlanAction传递过来的`install_plan_`信息，并构建`http_fetcher_`用于升级数据下载，`http_fetcher_`下载部分数据后会通过`ReceivedBytes()`通知DownloadAction收到了数据，DownloadAction会使用DeltaPerformer类对象`writer_`的`Write()`方法解析下载的数据，并将其更新到相应分区中。所以`http_fetcher_`下载数据，`writer_`将解析下载的数据并更新，然后`http_fetcher_`继续下载数据，`writer_`继续解析新下载的数据并更新到分区，这样的操作一直到所有数据下载完成，此时所有的升级数据也会被写入相应分区。

DownloadAction任务结束后，ActionProcessor会挑选下一个任务FilesystemVerifierAction来执行。

### FilesystemVerifierAction

FilesystemVerifierAction获取DownloadAction传递过来的`install_plan_`信息，这里接收到的`install_plan_`数据同InstallPlanAction传递给DownloadAction的数据已经不一样了。因为DownloadAction在接收到升级数据后，会解析数据，并更新`install_plan_`，例如有哪些分区需要更新，每个分区的volume多大，每个分区的更新操作是如何的，每个分区更新完成后的期望Hash值等等。FilesystemVerifierAction根据`install_plan_`中需要校验的分区，读取相应分区的所有数据计算Hash，并同分区期望的Hash数据进行比较，如果一致，则说明DownloadAction中的下载更新是成功的，否则会报错。

FilesystemVerifierAction任务结束后，ActionProcessor继续挑选下一个任务PostinstallRunnerAction来执行。

### PostinstallRunnerAction

DownloadAction下载更新的`install_plan_`会包含每个分区在更新完成后需要执行的post install script脚本，PostinstallRunnerAction对每个分区执行相应的post install script脚本。执行完所有分区的post install script脚本后，PostInstallRunnerAction结束。

### 其它

在DownloadAction开始数据下载前，会将`target_slot`设置为不可启动(unbootable)的状态；在PostInstallRunnerAction成功执行post install script后，又会重新将`target_slot`设置为活动(active)状态。

PostInstallRunnerAction任务执行结束后，ActionProcessor的Action队列为空，整个Action队列的调度操作结束。

此时ActionProcessor通知`update_attempter_`对象执行`ProcessingDone()`操作。该操作会在系统中写入一个标记Update Complete的BootId，然后将`UpdateStatus`设置为`UPDATED_NEED_REBOOT`并通知Update Engine的客户端进程。

到此，Update Engine升级中的4个Action执行完毕并通知了客户端进程，可以说是数据的下载，更新和验证操作完成了。但至于整个系统的更新，还需要重启进入新系统，将新系统分区的boot flag标记为sucessful才算一个升级流程真正结束。

好吧，又长又臭的一篇代码分析终于结束了~~

## 6. 联系和福利

- 个人微信公众号“洛奇看世界”，一个大龄码农的救赎之路。
  - 公众号回复关键词“Android电子书”，获取超过150本Android相关的电子书和文档。电子书包含了Android开发相关的方方面面，从此你再也不需要到处找Android开发的电子书了。
  - 公众号回复关键词“个人微信”，获取个人微信联系方式。<font color="red">我组建了一个Android OTA的讨论组，联系我，说明Android OTA，拉你进组一起讨论。</font>

  ![image](https://img-blog.csdn.net/20180507223120679)
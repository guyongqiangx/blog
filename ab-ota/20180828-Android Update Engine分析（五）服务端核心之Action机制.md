# Android Update Engine分析（五）服务端核心之Action机制

前面四篇分别分析了Makefile，Protobuf和AIDL相关文件, Update Engine的客户端进程`update_engine_client`以及Update Engine的服务端:

- [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)
- [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)
- [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)
- [Android Update Engine分析（四）服务端进程](https://blog.csdn.net/guyongqiangx/article/details/82116213)

本篇开始分析Update Engine服务端进程的核心，Action机制。

> 本文涉及的Android代码版本：android‐7.1.1_r23 (NMF27D)

## 1. 什么是Action机制？

Action机制是整个Update Engine服务端进程运行的核心，不清楚Action机制，就无法了解整个Update Engine服务端是如何运作的。

Action机制主要有三个部分组成: Action, ActionProcessor和ActionPipe。

### 1.1 Action
基于Action机制，Update Engine里面的每一个任务都被封装为一个Action，例如下载任务被封装为DownloadAction, 文件系统验证的任务被封装为FilesystemVerifierAction，更新完成后所有收尾动作被封装为PostinstallRunnerAction。

当然，这个Action机制很灵活，你甚至可以根据需要定义自己特有的Action。例如，将数据解密的操作定义为DecryptAction，在DownloadAction下载完数据后需要先通过DecryptAction将数据解密，再将解密后的数据送往下一个操作。

总之，Action就是一个基本的任务单元，只干一件事。
> 好吧，如果你想定义一个Action来完成多个事情，貌似也是可以的，参考官方Action Twiki的SubAction描述。</br>
> Action机制的实现最初来源于项目 [Google Update Engine](http://code.google.com/p/update-engine/) 项目，该项目基于Mac OS X的框架使用Objectiv-C实现。 </br>
> 关于Action机制的官方描述，请参考：[The Update Engine Action System](https://code.google.com/archive/p/update-engine/wikis/ActionProcessor.wiki)

Update Engine代码中，默认定义了4个Action，分别为：`InstallPlanAction`, `DownloadAction`, `FilesystemVerifierAction`, `PostinstallRunnerAction`。这些Action的名字都很直观，见名知意。

单个Action执行的时间不是固定的。例如，基于不同的网络状况，有的`DownloadAction`很快就可以完成，但有的`DownloadAction`可能需要很久。因此代码上，Action都是异步执行的，对Action调用`PerformAction()`使其开始工作，但这个函数返回只表明Action开始了，并不代表执行结束（有可能结束，也有可能刚开始）。

例如DownloadAction，调用`PerformAction()`对数据下载进行初始化设置，然后底层的数据传输开始工作，函数返回时数据传输并没有完成。在数据传输完成时底层会触发调用`TransferComplete()`进行通知。

### 1.2 Action Processor

既然Update Engine里定义了多个Action，那这些Action是如何组织运行的呢？此时就需要有一个Action的管理者，这就是ActionProcessor.

在ActionProcessor里面定义了一个Action的队列, 在Update Engine准备更新时，会根据当前传入的参数构造多个Action并放入ActionProcessor的Action队列。

除了Action队列，ActionProcessor中还有一个指针，用于指示当前正在运行的Action。

ActionProcessor通过`StartProcessing()`操作开始工作，先挑选队列中的第一个Action作为当前Action。然后当前Action调用`PerformAction()`开始工作，Action结束后会调用ActionProcessor的`ActionComplete()`接口通知当前Action已经完成。随后ActionProcessor通过`StartNextActionOrFinish()`挑选队列中的下一个Action进行操作。循环往复，直到队列中的所有Action都完成操作。

### 1.3 Action Pipe

类似于Unix系统的管道，Action机制中，也会通过管道ActionPipe将这些Action链接在一起。上一个Action的输出会作为下一个Action的输入。

因此在Update Engine中，所有的Action之间有一个先后关系。例如，只有`DownloadAction`完成操作了，才能开始`FilesystemVerifierAction`操作；也只有`FilesystemVerifierAction`结束了，才会开始`PostinstallRunnerAction`操作。

## 2. Action机制实现分析

### 2.1 ActionProcessor类

抛开Action实现的细节，先来看看Action的组织管理者ActionProcessor是如何运作的。

ActionProcessor工作的中心是管理Action，所以基本上所有操作是围绕Action队列进行的，包括:
- Action入队操作：`EnqueueAction`
- 开始和停止处理：`StartProcessing`/`StopProcessing`
- 暂停和恢复处理：`SuspendProcessing`/`ResumeProcessing`
- 当前Action结束的收尾工作：`ActionComplete`
- 选择下一Action操作：`StartNextActionOrFinish`

#### 2.1.1 Action入队操作
Action的入对操作`EnqueueAction`比较简单，就是将传入的Action添加到管理的队列`actions_`中，并将将自己设置为Action的管理者。

```
void ActionProcessor::EnqueueAction(AbstractAction* action) {
  // 将传入的action添加到队列尾部
  actions_.push_back(action);
  // 将自己设置为Action的Processor
  action->SetProcessor(this);
}
```

在`update_attempter_`调用`BuildUpdateActions()`操作时，生成多个action并保存到临时队列`actions_`中，函数的最后通过`EnqueueAction`操作将临时队列中的action逐个添加到管理者`processor_`的队列中，如下:
```
void UpdateAttempterAndroid::BuildUpdateActions(const string& url) {
  // 创建多个action，并将action添加到临时队列actions_中
  ...

  // 将临时队列actions_中的action逐个添加到ActionProcessor的队列中
  // Enqueue the actions.
  for (const shared_ptr<AbstractAction>& action : actions_)
    processor_->EnqueueAction(action.get());
}
```

#### 2.1.2 开始和停止处理

当调用`StartProcessing()`开始处理工作时，先取得队列前端的Action，并将其存放到指示当前Action的指针`current_action_`中，然后调用Action对应的`PerformAction()`开始Action工作。

```
void ActionProcessor::StartProcessing() {
  CHECK(!IsRunning());
  // Action队列不为空时，开始工作
  if (!actions_.empty()) {
    // current_action_指向队列中的第一个action
    current_action_ = actions_.front();
    LOG(INFO) << "ActionProcessor: starting " << current_action_->Type();
    // 当前工作的action从队列中出列
    actions_.pop_front();
    // 开始当前Action的工作
    current_action_->PerformAction();
  }
}
```

当调用`StopProcessing()`停止处理工作时，会先通知当前Action停止工作，然后将Action队列清空，并调用`ProcessingStopped(this)`向外通知ActionProcessor已经停止工作了。
```
void ActionProcessor::StopProcessing() {
  // 检查是否有在运行
  CHECK(IsRunning());
  // 如果当前有正在处理的action，则终止当前action的活动
  if (current_action_) {
    current_action_->TerminateProcessing();
    current_action_->SetProcessor(nullptr);
  }
  LOG(INFO) << "ActionProcessor: aborted "
            << (current_action_ ? current_action_->Type() : "")
            << (suspended_ ? " while suspended" : "");
  // 将当前action指针置空，并设置suspended_状态为false
  current_action_ = nullptr;
  suspended_ = false;
  // Delete all the actions before calling the delegate.
  // 队列中的action逐个移除processor设置，不再被当前ActionProcessor管理
  for (auto action : actions_)
    action->SetProcessor(nullptr);
  // 清空action队列
  actions_.clear();
  // 向外通知processor已经停止工作了
  if (delegate_)
    delegate_->ProcessingStopped(this);
}
```

#### 2.1.3 暂停和恢复处理

调用`SuspendProcessing()`和`ResumeProcessing()`暂停和恢复当前processor的处理工作。

```
void ActionProcessor::SuspendProcessing() {
  // 如果已经是暂停状态或当前没有action在处理(还没开始或已经结束了)，此时暂停操作没有意义
  // No current_action_ when not suspended means that the action processor was
  // never started or already finished.
  if (suspended_ || !current_action_) {
    LOG(WARNING) << "Called SuspendProcessing while not processing.";
    return;
  }
  // 设置暂停标识suspended_为true
  suspended_ = true;

  // 暂停当前正在运行的action
  // If there's a current action we should notify it that it should suspend, but
  // the action can ignore that and terminate at any point.
  LOG(INFO) << "ActionProcessor: suspending " << current_action_->Type();
  current_action_->SuspendAction();
}

void ActionProcessor::ResumeProcessing() {
  // 如果不是暂停状态，使用恢复操作也没有意义……
  if (!suspended_) {
    LOG(WARNING) << "Called ResumeProcessing while not suspended.";
    return;
  }
  // 取消暂停标识，将其suspended_设置为false
  suspended_ = false;
  // 如果暂停前当前有Action在操作(即调用了SuspendAction())，则需要继续Action的处理
  if (current_action_) {
    // The current_action_ did not call ActionComplete while suspended, so we
    // should notify it of the resume operation.
    LOG(INFO) << "ActionProcessor: resuming " << current_action_->Type();
    current_action_->ResumeAction();
  } else { 
    // 如果暂停前没有Action在操作(当前Action刚好结束了)，那就挑选队列中的下一个Action运行
    // The last action called ActionComplete while suspended, so there is
    // already a log message with the type of the finished action. We simply
    // state that we are resuming processing and the next function will log the
    // start of the next action or processing completion.
    LOG(INFO) << "ActionProcessor: resuming processing";
    StartNextActionOrFinish(suspended_error_code_);
  }
}
```

#### 2.1.4 当前Action结束的收尾工作

当前Action操作结束后通知ActionProcessor结束了，此时processor会进行一些列的收尾工作。包括通知外部当前Action已经结束，不再管理已经完成的action，挑选队列中的下一个action进行处理等。

```
void ActionProcessor::ActionComplete(AbstractAction* actionptr,
                                     ErrorCode code) {
  CHECK_EQ(actionptr, current_action_);
  // 通知外部当前action已经结束了(运行时这里的delegate_就是update_attempter_)
  if (delegate_)
    delegate_->ActionCompleted(this, actionptr, code);
  string old_type = current_action_->Type();
  // 调用action的ActionCompleted操作更新状态
  current_action_->ActionCompleted(code);
  // 将action的processor置空，不再管理这个action了
  current_action_->SetProcessor(nullptr);
  current_action_ = nullptr;
  LOG(INFO) << "ActionProcessor: finished "
            << (actions_.empty() ? "last action " : "") << old_type
            << (suspended_ ? " while suspended" : "")
            << " with code " << utils::ErrorCodeToString(code);
  // 如果当前action_队列中还有待操作的action，但是当前的action又失败了，那就清空队列中的剩余action
  // 因为已经失败了，不用继续搞了啊，收工。
  if (!actions_.empty() && code != ErrorCode::kSuccess) {
    LOG(INFO) << "ActionProcessor: Aborting processing due to failure.";
    actions_.clear();
  }
  // 巧了，如果当前action完成了，发现processor也暂停了，那就不再继续执行下一个action了。
  if (suspended_) {
    // If an action finished while suspended we don't start the next action (or
    // terminate the processing) until the processor is resumed. This condition
    // will be flagged by a nullptr current_action_ while suspended_ is true.
    suspended_error_code_ = code;
    return;
  }
  // 当前action完成了，那就继续队列中下一个action的处理吧。
  StartNextActionOrFinish(code);
}
```

#### 2.1.5 选择下一Action操作
通过`StartNextActionOrFinish()`来选择队列中的下一个Action，如果队列中不再有待处理的Action，那整个操作就完成了。
```
void ActionProcessor::StartNextActionOrFinish(ErrorCode code) {
  // Action队列已经被掏空，好吧，那就通知外部处理已经完成了
  if (actions_.empty()) {
    if (delegate_) {
      // 运行时这里的delegate_就是update_attempter_，所以调用update_attempter_->ProcessingDone
      delegate_->ProcessingDone(this, code);
    }
    return;
  }
  // 来吧，队列中的下一位兄弟，该你上班了
  current_action_ = actions_.front();
  // 队列中的第1位兄弟已经工作了，所以就不要给他留位置了。
  actions_.pop_front();
  LOG(INFO) << "ActionProcessor: starting " << current_action_->Type();
  // 当前Action，该干嘛干嘛去吧。
  current_action_->PerformAction();
}
```

#### 2.1.6 ActionProcessor总结

所以整个ActionProcessor的操作也比较直观，就是不断挑选队列中的Action去干活：
- 如果当前的Action操作完成，那就告诉外面当前Action已经完成了，并挑选下一个去干活；
- 如果外面通知要求暂停或终止活动，那就转达告知当前的Action暂停或取消活动。

### 2.2 Action类

Action类的关系几句话说不清楚，那就上图吧：

![Action类之间的继承关系](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/update_engine_action_mechanism.png?raw=true)

要点如下：
- AbstractAction
  - 整个Action的抽象基类，提供各种Action调用的公共接口
- Action 
  - 继承自 AbstractAction，是一个模板类，实现了管道操作的接口，因此其子类支持ActionPipe的管道操作
- InstallPlanAction 
  - Update Engine系统中，所有具体Action任务类的基类，其成员`install_plan_`包含了升级需要的元数据信息
- DownloadAction
  - 载数据的具体任务类
- FilesystemVerifierAction 
  - 数据下载完成后进行数据验证的具体任务类
- PostinstallRunnerAction
  - 安装收尾工作的具体任务类

所以想了解哪个阶段的细节，就去debug相应阶段的代码就好了。例如想知道如何下载的，那就去看看DownloadAction的实现代码；想知道下载完成后数据是如何验证的，那就去看看FilesystemVerifierAction的实现代码。

后面也打算专门针对每一个Action进行详细分析，看看这些Action是如何工作的。

### 2.3 ActionPipe类

ActionPipe就是将两个Action粘接在一起，前一个Action的output连接上后一个Action的input形成管道。ActionPipe基于Action类的层面，所以所有Action类的子类都支持管道特性。

ActionPipe类的代码比较简单，但也非常抽象，不容易有直观的认识，因此我们重点看看`UpdateAttempterAndroid`是如何将各个管道粘接在一起的：
```
void UpdateAttempterAndroid::BuildUpdateActions(const string& url) {
  ...

  // 生成install_plan_action
  // Actions:
  shared_ptr<InstallPlanAction> install_plan_action(
      new InstallPlanAction(install_plan_));

  ...
  // 生成download_action
  shared_ptr<DownloadAction> download_action(new DownloadAction(
      prefs_,
      boot_control_,
      hardware_,
      nullptr,                                        // system_state, not used.
      new MultiRangeHttpFetcher(download_fetcher)));  // passes ownership
  // 生成dst_filesystem_verifier_action
  shared_ptr<FilesystemVerifierAction> dst_filesystem_verifier_action(
      new FilesystemVerifierAction(boot_control_,
                                   VerifierMode::kVerifyTargetHash));

  // postinstall_runner_action
  shared_ptr<PostinstallRunnerAction> postinstall_runner_action(
      new PostinstallRunnerAction(boot_control_, hardware_));

  ...

  // 这里调用BondActions()操作将前面生成的4个Action粘接在一起，形成管道
  // Bond them together. We have to use the leaf-types when calling
  // BondActions().
  BondActions(install_plan_action.get(), download_action.get());
  BondActions(download_action.get(), dst_filesystem_verifier_action.get());
  BondActions(dst_filesystem_verifier_action.get(),
              postinstall_runner_action.get());

  ...
}
```

到这里，Action机制的三大组件Action, ActionProcessor, ActionPipe都做过介绍了，下面我们来看看UpdateAttempterAndroid类基于Action机制是如何工作的。

## 3. UpdateAttempterAndroid类

上一篇说到，Update Engine服务端除去回调操作外，基本上所有调用最后都会交由`DaemonStateAndroid`类的私有成员`update_attempter_`处理，所以`update_attempter_`是Update Engine服务端的核心对象。其对应的类`UpdateAttempterAndroid`也就是整个Update Engine的核心类。

就`UpdateAttempterAndroid`类自身来说，最重要的功能是将客户端传递过来的升级请求打包生成各种Action任务，然后交由ActionProcessor进行管理。ActionProcessor管理各任务Action的调度和执行，并在适当的时间向`UpdateAttempterAndroid`类报告Action任务的执行结果。例如，报告当前某个Action执行完成了，又或者报告当前所有Action都执行完成了。

沿着这条主线，我们看看`UpdateAttempterAndroid`是如何操作的。

### 3.1 函数`ApplyPayload()`

Update Engine的客户端发起升级请求后，所有请求的参数通过Binder服务，最后通过`ApplyPayload()`接口传递给`UpdateAttempterAndroid`类。

`ApplyPayload()`函数的有110行，咋一看还有点云里雾里的，你可能以为客户端发起升级请求后，`ApplyPayload`解析升级参数，然后通过各种搞搞搞就完成了升级。因为曾经有个哥们问我说，`ApplyPayload`中还没看到哪里接收数据，咋就在最后调用`UpdateBootFlags()`操作去更新boot flag了啊？他以为`UpdateBootFlags()`是更新完成后的操作，其实我一开始也是这么认为的。额，其实不是的，因为`ApplyPayload`是异步执行的，`ApplyPayload`返回只是表明升级开始了~

ApplyPayload做的事情前后主要有以下几件：
1. 判断升级条件，决定是否要升级
2. 解析传入参数
3. 使用传入的参数构建`install_plan_`
4. 构建打包升级的各种Action
5. 设置下载升级参数
6. 通过回调通知升级进度并更新启动标识

以下是对`ApplyPayload`函数的详细注释：
```
bool UpdateAttempterAndroid::ApplyPayload(
    const string& payload_url,
    int64_t payload_offset,
    int64_t payload_size,
    const vector<string>& key_value_pair_headers,
    brillo::ErrorPtr* error) {
  //
  // 1. 判断升级条件，决定是否要升级
  //
  // 刚完成升级，目前需要重启，不需要升级
  if (status_ == UpdateStatus::UPDATED_NEED_REBOOT) {
    return LogAndSetError(
        error, FROM_HERE, "An update already applied, waiting for reboot");
  }
  // 升级正在进行中，所以不需要再次重新升级
  if (ongoing_update_) {
    return LogAndSetError(
        error, FROM_HERE, "Already processing an update, cancel it first.");
  }
  // 确保当前是IDLE状态
  DCHECK(status_ == UpdateStatus::IDLE);

  //
  // 2. 解析传入参数
  //
  std::map<string, string> headers;
  for (const string& key_value_pair : key_value_pair_headers) {
    string key;
    string value;
    if (!brillo::string_utils::SplitAtFirst(
            key_value_pair, "=", &key, &value, false)) {
      return LogAndSetError(
          error, FROM_HERE, "Passed invalid header: " + key_value_pair);
    }
    if (!headers.emplace(key, value).second)
      return LogAndSetError(error, FROM_HERE, "Passed repeated key: " + key);
  }

  //
  // 3. 使用传入的参数构建install_plan_
  //    我现在一点都不想去关心到底设置了哪些字段
  //
  // Unique identifier for the payload. An empty string means that the payload
  // can't be resumed.
  string payload_id = (headers[kPayloadPropertyFileHash] +
                       headers[kPayloadPropertyMetadataHash]);

  // Setup the InstallPlan based on the request.
  install_plan_ = InstallPlan();

  install_plan_.download_url = payload_url;
  install_plan_.version = "";
  base_offset_ = payload_offset;
  install_plan_.payload_size = payload_size;
  if (!install_plan_.payload_size) {
    if (!base::StringToUint64(headers[kPayloadPropertyFileSize],
                              &install_plan_.payload_size)) {
      install_plan_.payload_size = 0;
    }
  }
  install_plan_.payload_hash = headers[kPayloadPropertyFileHash];
  if (!base::StringToUint64(headers[kPayloadPropertyMetadataSize],
                            &install_plan_.metadata_size)) {
    install_plan_.metadata_size = 0;
  }
  install_plan_.metadata_signature = "";
  // The |public_key_rsa| key would override the public key stored on disk.
  install_plan_.public_key_rsa = "";

  install_plan_.hash_checks_mandatory = hardware_->IsOfficialBuild();
  install_plan_.is_resume = !payload_id.empty() &&
                            DeltaPerformer::CanResumeUpdate(prefs_, payload_id);
  if (!install_plan_.is_resume) {
    if (!DeltaPerformer::ResetUpdateProgress(prefs_, false)) {
      LOG(WARNING) << "Unable to reset the update progress.";
    }
    if (!prefs_->SetString(kPrefsUpdateCheckResponseHash, payload_id)) {
      LOG(WARNING) << "Unable to save the update check response hash.";
    }
  }
  // The |payload_type| is not used anymore since minor_version 3.
  install_plan_.payload_type = InstallPayloadType::kUnknown;

  install_plan_.source_slot = boot_control_->GetCurrentSlot();
  install_plan_.target_slot = install_plan_.source_slot == 0 ? 1 : 0;

  int data_wipe = 0;
  install_plan_.powerwash_required =
      base::StringToInt(headers[kPayloadPropertyPowerwash], &data_wipe) &&
      data_wipe != 0;

  NetworkId network_id = kDefaultNetworkId;
  if (!headers[kPayloadPropertyNetworkId].empty()) {
    if (!base::StringToUint64(headers[kPayloadPropertyNetworkId],
                              &network_id)) {
      return LogAndSetError(
          error,
          FROM_HERE,
          "Invalid network_id: " + headers[kPayloadPropertyNetworkId]);
    }
    if (!network_selector_->SetProcessNetwork(network_id)) {
      LOG(WARNING) << "Unable to set network_id, continuing with the update.";
    }
  }

  LOG(INFO) << "Using this install plan:";
  install_plan_.Dump();

  //
  // 4. 构建打包升级的各种Action
  //
  BuildUpdateActions(payload_url);
  //
  // 5. 设置下载升级参数
  //
  SetupDownload();
  // Setup extra headers.
  HttpFetcher* fetcher = download_action_->http_fetcher();
  if (!headers[kPayloadPropertyAuthorization].empty())
    fetcher->SetHeader("Authorization", headers[kPayloadPropertyAuthorization]);
  if (!headers[kPayloadPropertyUserAgent].empty())
    fetcher->SetHeader("User-Agent", headers[kPayloadPropertyUserAgent]);

  //
  // 6. 通过回调通知升级进度并更新启动标识
  //
  cpu_limiter_.StartLimiter();
  // 回调通知客户端当前进度为0
  SetStatusAndNotify(UpdateStatus::UPDATE_AVAILABLE);
  // 设置当前状态为升级中
  ongoing_update_ = true;

  // 更新启动标识
  // Just in case we didn't update boot flags yet, make sure they're updated
  // before any update processing starts. This will start the update process.
  UpdateBootFlags();
  return true;
}
```

### 3.2 函数`BuildUpdateActions()`

`ApplyPayload()`的代码中，最重要的就是调用`BuildUpdateActions()`构建升级中的各种Action。我们不妨看看到底都需要哪些Action，这些Action都是如何构建的。

从比较粗的粒度上看`BuildUpdateActions()`，构建Action的活动包括：
1. 构建InstallPlanAction: `install_plan_action`
2. 构建DownloadAction: `download_action`
3. 构建FilesystemVerifierAction: `dst_filesystem_verifier_action`
4. 构建PostinstallRunnerAction: `postinstall_runner_action`
5. 使用ActionPipe将4个Action连接起来
6. 将Action添加到ActionProcessor的管理队列中

```
void UpdateAttempterAndroid::BuildUpdateActions(const string& url) {
  // 检查ActionProcessor是否已经处于Running状态
  CHECK(!processor_->IsRunning());
  // 将自己设置为ActionProcessor的代理对象，ActionProcessor只需要通过代理对象就可以向外发送通知
  processor_->set_delegate(this);

  //
  // 1. 构建install_plan_action
  //
  // Actions:
  shared_ptr<InstallPlanAction> install_plan_action(
      new InstallPlanAction(install_plan_));

  // 检查数据下载的传输地址协议
  HttpFetcher* download_fetcher = nullptr;
  // 如果是"file:///"就使用FileFetcher进行下载
  if (FileFetcher::SupportedUrl(url)) {
    DLOG(INFO) << "Using FileFetcher for file URL.";
    download_fetcher = new FileFetcher();
  } else { // 如果是其它的协议，则使用libcurl库进行下载;
#ifdef _UE_SIDELOAD
    LOG(FATAL) << "Unsupported sideload URI: " << url;
#else
    LibcurlHttpFetcher* libcurl_fetcher =
        new LibcurlHttpFetcher(&proxy_resolver_, hardware_);
    libcurl_fetcher->set_server_to_check(ServerToCheck::kDownload);
    download_fetcher = libcurl_fetcher;
#endif  // _UE_SIDELOAD
  }
  //
  // 2. 构建download_action
  //
  shared_ptr<DownloadAction> download_action(new DownloadAction(
      prefs_,
      boot_control_,
      hardware_,
      nullptr,                                        // system_state, not used.
      new MultiRangeHttpFetcher(download_fetcher)));  // passes ownership
  //
  // 3. 构建dst_filesystem_verifier_action
  //
  shared_ptr<FilesystemVerifierAction> dst_filesystem_verifier_action(
      new FilesystemVerifierAction(boot_control_,
                                   VerifierMode::kVerifyTargetHash));

  //
  // 4. 构建postinstall_runner_action
  //
  shared_ptr<PostinstallRunnerAction> postinstall_runner_action(
      new PostinstallRunnerAction(boot_control_, hardware_));

  download_action->set_delegate(this);
  download_action_ = download_action;
  postinstall_runner_action->set_delegate(this);

  // 将前面构建的4个Action添加到actions_向量中
  actions_.push_back(shared_ptr<AbstractAction>(install_plan_action));
  actions_.push_back(shared_ptr<AbstractAction>(download_action));
  actions_.push_back(
      shared_ptr<AbstractAction>(dst_filesystem_verifier_action));
  actions_.push_back(shared_ptr<AbstractAction>(postinstall_runner_action));

  //
  // 5. 使用ActionPipe将4个Action连接起来
  //
  // Bond them together. We have to use the leaf-types when calling
  // BondActions().
  BondActions(install_plan_action.get(), download_action.get());
  BondActions(download_action.get(), dst_filesystem_verifier_action.get());
  BondActions(dst_filesystem_verifier_action.get(),
              postinstall_runner_action.get());

  // 
  // 6. 将Action添加到ActionProcessor的管理队列中
  //
  // Enqueue the actions.
  for (const shared_ptr<AbstractAction>& action : actions_)
    processor_->EnqueueAction(action.get());
}
```

### 3.3 函数`UpdateBootFlags()`

回到`ApplyPayload()`函数，调用`BuildUpdateActions()`构建升级的Action后，使用`SetupDownload()`设置详细的数据下载细节，这一切完成后就通过`SetStatusAndNotify()`向客户端发起回调通知当前的下载进度(如果是全新升级，那这里的进度就是0；如果是继续之前未完成的下载，那就是实际的下载进度)。

最后一步就是调用`UpdateBootFlags()`，从字面上看是更新启动标识，注意在这个函数之前，还没有地方指示去开始升级，所以千万不要以为这里是升级结束更新启动标识。

那到底是什么呢？其实，在这里更新的启动标识只是将当前的分区标记为成功启动。因为在升级中，另外一个升级的分区会被设置为不可启动，这样确保即使升级失败，那下次启动会进入到当前成功启动的分区，而不是去启动升级失败的分区，代码如下：

```
void UpdateAttempterAndroid::UpdateBootFlags() {
  // updated_boot_flags_默认为false，表示没有更新过启动标识
  if (updated_boot_flags_) {
    LOG(INFO) << "Already updated boot flags. Skipping.";
    // 如果已经更新过启动标识，那就直接开始升级
    CompleteUpdateBootFlags(true);
    return;
  }
  
  // 如果还没有更新过启动标识，那这里就先调用boot_control_更新启动标识
  // 实际上在MarkBootSuccessfulAsync()函数主要是标记当前分区为成功启动的分区
  // This is purely best effort.
  LOG(INFO) << "Marking booted slot as good.";
  // 不清楚这里为什么要采用异步方式？
  if (!boot_control_->MarkBootSuccessfulAsync(
          Bind(&UpdateAttempterAndroid::CompleteUpdateBootFlags,
               base::Unretained(this)))) {
    LOG(ERROR) << "Failed to mark current boot as successful.";
    CompleteUpdateBootFlags(false);
  }
}
```

> 这里最大的疑问是，不清楚为什么要采用异步的方式`MarkBootSuccessfulAsync()`来标记分区？谁来解释下？

这里最具有迷惑性的函数就是`CompleteUpdateBootFlags()`了，这个函数命名就是指示ActionProcessor开始升级操作，但不清楚为什么偏偏要命名为`CompleteUpdateBootFlags`，难道是指更新完启动标识后的收尾动作吗？

以下是`CompleteUpdateBootFlags()`的相关实现：
```
void UpdateAttempterAndroid::CompleteUpdateBootFlags(bool successful) {
  updated_boot_flags_ = true;
  ScheduleProcessingStart();
}

void UpdateAttempterAndroid::ScheduleProcessingStart() {
  LOG(INFO) << "Scheduling an action processor start.";
  brillo::MessageLoop::current()->PostTask(
      FROM_HERE, Bind([this] { this->processor_->StartProcessing(); }));
}
```
这里可见，调用`CompleteUpdateBootFlags()`最终是让ActionProcessor执行`StartProcessing()`，后者意味着升级的Action队列开始工作了。

所以，真正的升级，从这里才开始。明白了为什么`ApplyPayload()`为什么是异步的了吗？

### 3.4 其它函数

前面已经分析了`UpdateAttempterAndroid`在功能上最重要的函数，下面来看看其它的函数。

#### 1. `Init()`和`UpdateCompletedOnThisBoot()`

`Init()`函数主要检查当前是否刚完成过升级，如果刚完成升级，那就将系统设置为需要重启的状态。
```
void UpdateAttempterAndroid::Init() {
  // In case of update_engine restart without a reboot we need to restore the
  // reboot needed state.
  if (UpdateCompletedOnThisBoot())
    SetStatusAndNotify(UpdateStatus::UPDATED_NEED_REBOOT);
  else
    SetStatusAndNotify(UpdateStatus::IDLE);
}

...

bool UpdateAttempterAndroid::UpdateCompletedOnThisBoot() {
  // In case of an update_engine restart without a reboot, we stored the boot_id
  // when the update was completed by setting a pref, so we can check whether
  // the last update was on this boot or a previous one.
  string boot_id;
  TEST_AND_RETURN_FALSE(utils::GetBootId(&boot_id));

  string update_completed_on_boot_id;
  return (prefs_->Exists(kPrefsUpdateCompletedOnBootId) &&
          prefs_->GetString(kPrefsUpdateCompletedOnBootId,
                            &update_completed_on_boot_id) &&
          update_completed_on_boot_id == boot_id);
}
```
其中，`UpdateCompletedOnThisBoot()`主要是从磁盘文件上读取boot id，然后同更新完成需要重启的boot id(来自kPrefsUpdateCompletedOnBootId)进行比较，如果二者相等，则说明刚完成过升级。

#### 2. `SuspendUpdate()`, `ResumeUpdate()`，`CancelUpdate()`和`ResetStatus()`

关于更新的`Suspend`，`Resume`和`Cancel`操作，Update Engine的Binder服务类`BinderUpdateEngineAndroidService`通过`service_delegate_`成员传递给`UpdateAttempterAndroid`类，后者在收到请求后再次将其转发给了Action队列的管理者ActionProcessor，由ActionProcessor对当前正在执行的Action采取相应的操作。

```
bool UpdateAttempterAndroid::SuspendUpdate(brillo::ErrorPtr* error) {
  if (!ongoing_update_)
    return LogAndSetError(error, FROM_HERE, "No ongoing update to suspend.");
  processor_->SuspendProcessing();
  return true;
}

bool UpdateAttempterAndroid::ResumeUpdate(brillo::ErrorPtr* error) {
  if (!ongoing_update_)
    return LogAndSetError(error, FROM_HERE, "No ongoing update to resume.");
  processor_->ResumeProcessing();
  return true;
}

bool UpdateAttempterAndroid::CancelUpdate(brillo::ErrorPtr* error) {
  if (!ongoing_update_)
    return LogAndSetError(error, FROM_HERE, "No ongoing update to cancel.");
  processor_->StopProcessing();
  return true;
}
```

至于`ResetStatus`操作，目的就是将系统恢复到`UpdateStatus::IDLE`状态。因此会根据当前Update Engine系统的状态，采取一些额外的措施使系统处于`UpdateStatus::IDLE`状态：

```
bool UpdateAttempterAndroid::ResetStatus(brillo::ErrorPtr* error) {
  LOG(INFO) << "Attempting to reset state from "
            << UpdateStatusToString(status_) << " to UpdateStatus::IDLE";

  // 根据系统当前的状态决定切换到UpdateStatus::IDLE状态要做什么操作
  switch (status_) {
    // 本来就是UpdateStatus::IDLE，所以什么都不用做
    case UpdateStatus::IDLE:
      return true;

    // 如果是刚升完级处于需要REBOOT的状态，那就清理升级的痕迹，把当前分区恢复为活动分区
    case UpdateStatus::UPDATED_NEED_REBOOT:  {
      // 清理通过Perfs方式存储的kPrefsUpdateCompletedOnBootId
      // Remove the reboot marker so that if the machine is rebooted
      // after resetting to idle state, it doesn't go back to
      // UpdateStatus::UPDATED_NEED_REBOOT state.
      bool ret_value = prefs_->Delete(kPrefsUpdateCompletedOnBootId);

      // 将当前分区设置为正常的活动分区
      // Update the boot flags so the current slot has higher priority.
      if (!boot_control_->SetActiveBootSlot(boot_control_->GetCurrentSlot()))
        ret_value = false;

      if (!ret_value) {
        return LogAndSetError(
            error,
            FROM_HERE,
            "Failed to reset the status to ");
      }

      // 更新系统状态为UpdateStatus::IDLE
      SetStatusAndNotify(UpdateStatus::IDLE);
      LOG(INFO) << "Reset status successful";
      return true;
    }

    // 其它状态都处于升级中，不能直接调用reset操作，需要先取消升级
    default:
      return LogAndSetError(
          error,
          FROM_HERE,
          "Reset not allowed in this state. Cancel the ongoing update first");
  }
}

```

#### 3. `ProcessingDone()`, `ProcessingStopped()`和`ActionCompleted()`

这3个操作都是由ActionProcessor发起调用的。

当ActionProcessor处理完Action队列中的所有Action后，通过`delegate_->ProcessingDone()`的方式通知`UpdateAttempterAndroid`类所有Action操作都完成了。此时就需要检查Action完成的退出状态，看看是否有错，并进行相应的处理：

```
void UpdateAttempterAndroid::ProcessingDone(const ActionProcessor* processor,
                                            ErrorCode code) {
  LOG(INFO) << "Processing Done.";

  switch (code) {
    // 一切都好，升级顺利完成
    case ErrorCode::kSuccess:
      // 在磁盘上写入更新成功标记(实际上是设置kPrefsUpdateCompletedOnBootId)
      // Update succeeded.
      WriteUpdateCompletedMarker();
      prefs_->SetInt64(kPrefsDeltaUpdateFailures, 0);
      DeltaPerformer::ResetUpdateProgress(prefs_, false);
      LOG(INFO) << "Update successfully applied, waiting to reboot.";
      break;

    // 我去，更新中出现了各种错误，那就复位各种状态吧
    case ErrorCode::kFilesystemCopierError:
    case ErrorCode::kNewRootfsVerificationError:
    case ErrorCode::kNewKernelVerificationError:
    case ErrorCode::kFilesystemVerifierError:
    case ErrorCode::kDownloadStateInitializationError:
      // Reset the ongoing update for these errors so it starts from the
      // beginning next time.
      DeltaPerformer::ResetUpdateProgress(prefs_, false);
      LOG(INFO) << "Resetting update progress.";
      break;

    default:
      // Ignore all other error codes.
      break;
  }

  // 结束升级，通知客户端和其它模块当前的升级状态
  TerminateUpdateAndNotify(code);
}
```

`UpdateAttempterAndroid`收到`CancelUpdate`通知，会将其转给ActionProcessor处理。ActionProcessor在完成操作后会反过来让`UpdateAttempterAndroid`使用`ProcessingStopped`去通知客户端和其它模块升级处于`kUserCanceled`状态：
```
void UpdateAttempterAndroid::ProcessingStopped(
    const ActionProcessor* processor) {
  TerminateUpdateAndNotify(ErrorCode::kUserCanceled);
}
```

Action队列中的每个Action处理结束后，ActionProcessor调用`ActionCompleted()`通知当前Action已经执行完成，`UpdateAttempterAndroid`据此做一些系统更新工作，包括数据下载进度更新和客户端即其它模块的通知。

```
void UpdateAttempterAndroid::ActionCompleted(ActionProcessor* processor,
                                             AbstractAction* action,
                                             ErrorCode code) {
  // Reset download progress regardless of whether or not the download
  // action succeeded.
  const string type = action->Type();
  // 如果当前是DownloadAction，那就重新把download_progress_设置为0
  if (type == DownloadAction::StaticType()) {
    download_progress_ = 0;
  }
  if (code != ErrorCode::kSuccess) {
    // If an action failed, the ActionProcessor will cancel the whole thing.
    return;
  }
  // 通知所有客户端当前的状态
  if (type == DownloadAction::StaticType()) {
    SetStatusAndNotify(UpdateStatus::FINALIZING);
  }
}
```

#### 4. `BytesReceived()`, `ShouldCancel()`, `DownloadComplete()`和`ProgressUpdate()`

这四个都是基于DownloadAction的动作，每次有数据到来时都需要根据情况使用`ProgressUpdate()`更新数据下载的进度，然后通知客户端。其中`ShouldCancel()`和`DownloadComplete()`都是空操作，你也可以在这里自定义针对这些操作的行为。

```
void UpdateAttempterAndroid::BytesReceived(uint64_t bytes_progressed,
                                           uint64_t bytes_received,
                                           uint64_t total) {
  double progress = 0;
  if (total)
    progress = static_cast<double>(bytes_received) / static_cast<double>(total);
  if (status_ != UpdateStatus::DOWNLOADING || bytes_received == total) {
    download_progress_ = progress;
    SetStatusAndNotify(UpdateStatus::DOWNLOADING);
  } else {
    ProgressUpdate(progress);
  }
}

bool UpdateAttempterAndroid::ShouldCancel(ErrorCode* cancel_reason) {
  // TODO(deymo): Notify the DownloadAction that it should cancel the update
  // download.
  return false;
}

void UpdateAttempterAndroid::DownloadComplete() {
  // Nothing needs to be done when the download completes.
}

void UpdateAttempterAndroid::ProgressUpdate(double progress) {
  // Self throttle based on progress. Also send notifications if progress is
  // too slow.
  if (progress == 1.0 ||
      progress - download_progress_ >= kBroadcastThresholdProgress ||
      TimeTicks::Now() - last_notify_time_ >=
          TimeDelta::FromSeconds(kBroadcastThresholdSeconds)) {
    download_progress_ = progress;
    SetStatusAndNotify(status_);
  }
}
```

#### 5. `SetupDownload()`

`SetupDownload()`根据`ApplyPayload()`接收到的参数计算下载数据(偏移量和大小等)，等到后续分析DownloadAction时再详细分析。
```
void UpdateAttempterAndroid::SetupDownload() {
  MultiRangeHttpFetcher* fetcher =
      static_cast<MultiRangeHttpFetcher*>(download_action_->http_fetcher());
  fetcher->ClearRanges();
  if (install_plan_.is_resume) {
    // Resuming an update so fetch the update manifest metadata first.
    int64_t manifest_metadata_size = 0;
    int64_t manifest_signature_size = 0;
    prefs_->GetInt64(kPrefsManifestMetadataSize, &manifest_metadata_size);
    prefs_->GetInt64(kPrefsManifestSignatureSize, &manifest_signature_size);
    fetcher->AddRange(base_offset_,
                      manifest_metadata_size + manifest_signature_size);
    // If there're remaining unprocessed data blobs, fetch them. Be careful not
    // to request data beyond the end of the payload to avoid 416 HTTP response
    // error codes.
    int64_t next_data_offset = 0;
    prefs_->GetInt64(kPrefsUpdateStateNextDataOffset, &next_data_offset);
    uint64_t resume_offset =
        manifest_metadata_size + manifest_signature_size + next_data_offset;
    if (!install_plan_.payload_size) {
      fetcher->AddRange(base_offset_ + resume_offset);
    } else if (resume_offset < install_plan_.payload_size) {
      fetcher->AddRange(base_offset_ + resume_offset,
                        install_plan_.payload_size - resume_offset);
    }
  } else {
    if (install_plan_.payload_size) {
      fetcher->AddRange(base_offset_, install_plan_.payload_size);
    } else {
      // If no payload size is passed we assume we read until the end of the
      // stream.
      fetcher->AddRange(base_offset_);
    }
  }
}
```

## 4. 总结

至此，我们看到Update Engine的核心是Action机制，同时也在比较粗的粒度上分析了`UpdateAttempterAndroid`类的函数和功能，简单总结如下：

- 通过`ApplyPayload`接收到升级请求时，创建一个ActionProcessor，并根据升级的各种参数构建了4个Action，然后将这4个Action交由ActionProcessor管理。ActionProcessor对内部Action队列的任务进行调度，每执行完一个Action，都会向`UpdateAttempterAndroid`类发送通知汇报状态。

- Update Engine的Binder服务收到客户端的`suspend`, `resume`, `cancel`和`resetStatus`请求时，将其交由`UpdateAttempterAndroid`处理。除了`resetStatus`操作外，其余的三个都会再交由ActionProcessor去执行，执行完成后通知`UpdateAttempterAndroid`类，然后后者通过回调函数通知客户端结果。

一句话，`UpdateAttempterAndroid`类负责创建Action任务并交由ActionProcessor管理，再向客户端反馈系统和各种Action执行的状态。

啰啰嗦嗦说了半天，最后发现，看完`UpdateAttempterAndroid`也还没有讲到系统到底是如何下载数据，如何验证，如何升级的。你说闹不闹心？

不过有点安慰的是，知道整个Update Engine系统是按照任务去组织的，包括Download, Verify和PostInstall三个阶段，如果哪个阶段有疑问，那就去相应Action对应的代码去看看吧:

- `DownloadAction`: `./payload_consumer/download_action.cc`
- `FilesystemVerifierAction`: `./payload_consumer/filesystem_verifier_action.cc`
- `PostinstallRunnerAction`: `./payload_consumer/postinstall_runner_action.cc`

## 5. 联系和福利


- 个人微信公众号“洛奇看世界”，一个大龄码农的救赎之路。
  - 公众号回复关键词“Android电子书”，获取超过150本Android相关的电子书和文档。电子书包含了Android开发相关的方方面面，从此你再也不需要到处找Android开发的电子书了。
  - 公众号回复关键词“个人微信”，获取个人微信联系方式。<font color="red">我组建了一个Android OTA的讨论组，联系我，说明Android OTA，拉你进组一起讨论。</font>

  ![image](https://img-blog.csdn.net/20180507223120679)
# Android Update Engine分析（三）客户端update_engine_client

> 技术文章直入主题，展示结论，容易让人知其然，不知其所以然。</br>
> 我个人更喜欢在文章中展示如何阅读代码，逐步分析解决问题的思路和过程。这样的思考比知道结论更重要，希望我的分析能让你有所收获。

前面两篇分别分析了Makefile，Protobuf和AIDL相关文件，从本篇开始正式深入功能实现的代码文件去探究Update Engine。

## 1. `update_engine_client`的文件依赖

Android自带的`update_engine`客户端`update_engine_client`应用很简单，只涉及到几个代码文件。

依赖的文件:
```
update_engine_client
  --> files (
        binder_bindings/android/os/IUpdateEngine.aidl
        binder_bindings/android/os/IUpdateEngineCallback.aidl
        common/error_code_utils.cc
        update_engine_client_android.cc
        update_status_utils.cc
      )
  --> shared libraries (
        libbrillo-stream
        libbrillo
        libchrome
        libbinder
        libbinderwrapper
        libbrillo-binder
        libutils
      )
```

这里可以看到，Android自带的客户端demo进程`update_engine_client`的依赖比较简单，代码设计的文件比较少。


## 2. `update_engine_client`代码分析

### 2.1 命令行参数
在开始逐行分析代码前，我们来看看这个客户端都有哪些参数和功能。

我们在命令行运行`update_engine_client --help`，其输出如下：
```
bcm7252ssffdr4:/ # update_engine_client --help 
Android Update Engine Client

  --cancel  (Cancel the ongoing update and exit.)  type: bool  default: false
  --follow  (Follow status update changes until a final state is reached. Exit status is 0 if the update succeeded, and 1 otherwise.)  type: bool  default: false
  --headers  (A list of key-value pairs, one element of the list per line. Used when --update is passed.)  type: string  default: ""
  --help  (Show this help message)  type: bool  default: false
  --offset  (The offset in the payload where the CrAU update starts. Used when --update is passed.)  type: int64  default: 0
  --payload  (The URI to the update payload to use.)  type: string  default: "http://127.0.0.1:8080/payload"
  --reset_status  (Reset an already applied update and exit.)  type: bool  default: false
  --resume  (Resume a suspended update.)  type: bool  default: false
  --size  (The size of the CrAU part of the payload. If 0 is passed, it will be autodetected. Used when --update is passed.)  type: int64  default: 0
  --suspend  (Suspend an ongoing update and exit.)  type: bool  default: false
  --update  (Start a new update, if no update in progress.)  type: bool  default: false
```

我们在《Android A/B System OTA分析（四）系统的启动和升级》中有提到一个具体的升级场景，调用参数如下：
```
bcm7252ssffdr4:/ # update_engine_client \
--payload=http://stbszx-bld-5/public/android/full-ota/payload.bin \
--update \
--headers="\
  FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY= \
  FILE_SIZE=282164983
  METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg= \
  METADATA_SIZE=21023 \
"
```

### 2.2 代码分析

在开始代码逐行分析之前，通过检查类UpdateEngineClientAndroid的定义，我画了一个类图，便于查看各个类之间的关系：

![image](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/UpdateEngineClientAndroid.png?raw=true)

图1. UpdateEngineClientAndroid类图

下面从`update_engine_client`入口main函数开始分析：
```
# system\update_engine\update_engine_client_android.cc
int main(int argc, char** argv) {
  chromeos_update_engine::internal::UpdateEngineClientAndroid client(
      argc, argv);
  return client.Run();
}
```

这个main函数真是简单，就两句话，先初始化生成一个UpdateEngineClientAndroid对象client，然后执行对象client.Run()方法~~
纳尼?这就结束了？这就是`update_engine_client`的全部？

先看看UpdateEngineClientAndroid的初始化：
```
# system\update_engine\update_engine_client_android.cc
class UpdateEngineClientAndroid : public brillo::Daemon {
  public:
    // 用传入的参数argc, argv初始化私有成员变量argc_, argv_
    UpdateEngineClientAndroid(int argc, char** argv) : argc_(argc), argv_(argv) {
  }
  ...
  private:
    // 下面定义了私有成员变量argc_和argv_用于存放main函数接收到的参数
    // Copy of argc and argv passed to main().
    int argc_;
    char** argv_;
  ...
}
```

紧接着调用client.Run()，这个方法在UpdateEngineClientAndroid的父类中定义：
```
# external\libbrillo\brillo\daemons\daemon.h
class BRILLO_EXPORT Daemon : public AsynchronousSignalHandlerInterface {
 public:
  ...

  // Performs proper initialization of the daemon and runs the message loop.
  // Blocks until the daemon is finished. The return value is the error
  // code that should be returned from daemon's main(). Returns EX_OK (0) on
  // success.
  virtual int Run();
  ...
 protected:
  ...
  virtual int OnInit();
}
```
实现上，由于这里Run()定义为virtual虚函数，所以运行时会先执行子类的同名函数UpdateEngineClientAndroid::Run()，但这里子类UpdateEngineClientAndroid并没有定义Run()函数，所以会执行父类brillo::Daemon的Run()函数，如下：
```
# external\libbrillo\brillo\daemons\daemon.cc
int Daemon::Run() {
  // 1. 执行OnInit函数进行初始化
  int exit_code = OnInit();
  if (exit_code != EX_OK)
    return exit_code;

  // 2. 初始化完成后调用brillo_message_loop_.Run()进入消息循环处理模式
  brillo_message_loop_.Run();

  // 3. 调用OnShutdown
  OnShutdown(&exit_code_);

  // 4. 进入while循环等待退出消息
  // base::RunLoop::QuitClosure() causes the message loop to quit
  // immediately, even if pending tasks are still queued.
  // Run a secondary loop to make sure all those are processed.
  // This becomes important when working with D-Bus since dbus::Bus does
  // a bunch of clean-up tasks asynchronously when shutting down.
  while (brillo_message_loop_.RunOnce(false /* may_block */)) {}

  return exit_code_;
}
```
这里先后有4个操作：
1. 执行OnInit函数进行初始化
2. 初始化完成后调用`brillo_message_loop_.Run()`进入消息循环处理模式
3. 调用OnShutdown
4. 进入while循环等待退出消息

下面逐个来看这4个操作：
1. 执行OnInit函数进行初始化
由于`int Daemon::OnInit()`定义为虚函数：
```
# external\libbrillo\brillo\daemons\daemon.h
class BRILLO_EXPORT Daemon : public AsynchronousSignalHandlerInterface {
  ...
  protected:
    // 定义了OnInit为虚函数，运行时如果子类实现了OnInit，则执行的是子类的OnInit函数
    virtual int OnInit();
}
```

所以运行时执行的是Daemon对应子类UpdateEngineClientAndroid的OnInit()函数，如下：
```
# system\update_engine\update_engine_client_android.cc
int UpdateEngineClientAndroid::OnInit() {
  // 这里在子类中调用父类的OnInit操作，注册信号SIGTERM, SIGINT和SIGHUP的处理函数
  int ret = Daemon::OnInit();
  if (ret != EX_OK)
    return ret;
```

这里先调用父类的Daemon::OnInit()函数，
```
# external\libbrillo\brillo\daemons\daemon.cc
int Daemon::OnInit() {
  async_signal_handler_.Init();
  for (int signal : {SIGTERM, SIGINT}) {
    async_signal_handler_.RegisterHandler(
        signal, base::Bind(&Daemon::Shutdown, base::Unretained(this)));
  }
  async_signal_handler_.RegisterHandler(
      SIGHUP, base::Bind(&Daemon::Restart, base::Unretained(this)));
  return EX_OK;
}
```
这里Daemon::OnInit()也没有做什么特别的，就是调用RegisterHandler注册了两个信号SIGTERM和SIGINT的handler，即Daemon::Shutdown和Daemon::Restart，但这两个handler其实是空的，什么都没做，如下：
```
# external\libbrillo\brillo\daemons\daemon.cc
void Daemon::OnShutdown(int* /* exit_code */) {
  // Do nothing.
}

bool Daemon::OnRestart() {
  // Not handled.
  return false;  // Returning false will shut down the daemon instead.
}
```

然后通过DEFINE_bool定义了一组参数：
```
  // 定义"update"参数，bool类型，默认为false
  DEFINE_bool(update, false, "Start a new update, if no update in progress.");
  // 定义"payload"参数, string类型
  DEFINE_string(payload,
                "http://127.0.0.1:8080/payload",
                "The URI to the update payload to use.");
  // 定义"offset"参数，int64类型
  DEFINE_int64(offset, 0,
               "The offset in the payload where the CrAU update starts. "
               "Used when --update is passed.");
  // 定义"size"参数，int64类型
  DEFINE_int64(size, 0,
               "The size of the CrAU part of the payload. If 0 is passed, it "
               "will be autodetected. Used when --update is passed.");
  // 定义"headers"参数，字符串类型
  DEFINE_string(headers,
                "",
                "A list of key-value pairs, one element of the list per line. "
                "Used when --update is passed.");
  // 定义"suspend"参数，bool类型，默认为false
  DEFINE_bool(suspend, false, "Suspend an ongoing update and exit.");
  // 定义"resume"参数，bool类型，默认为false
  DEFINE_bool(resume, false, "Resume a suspended update.");
  // 定义"cancel"参数，bool类型，默认为false
  DEFINE_bool(cancel, false, "Cancel the ongoing update and exit.");
  // 定义"reset_status"参数，bool类型，默认为false
  DEFINE_bool(reset_status, false, "Reset an already applied update and exit.");
  // 定义"follow"参数，bool类型，默认为false
  DEFINE_bool(follow,
              false,
              "Follow status update changes until a final state is reached. "
              "Exit status is 0 if the update succeeded, and 1 otherwise.");

  // 用argc_, argv_初始化命令行解析器
  // Boilerplate init commands.
  base::CommandLine::Init(argc_, argv_);
  // 我的理解是在这里解析argc_和argv_参数，如果不带参数，则显示错误并返回
  brillo::FlagHelper::Init(argc_, argv_, "Android Update Engine Client");
  if (argc_ == 1) {
    LOG(ERROR) << "Nothing to do. Run with --help for help.";
    return 1;
  }

  // 检查位置参数，没有详细去看，但不影响对整体的理解
  // Ensure there are no positional arguments.
  const std::vector<std::string> positional_args =
      base::CommandLine::ForCurrentProcess()->GetArgs();
  if (!positional_args.empty()) {
    LOG(ERROR) << "Found a positional argument '" << positional_args.front()
               << "'. If you want to pass a value to a flag, pass it as "
                  "--flag=value.";
    return 1;
  }
```

参考`2.1`节的命令行参数，显然，命令行处理选项将宏`DEFINE_xxx`展开，最终得到`FLAGS_xxx`变量，因此命令行选项和生成的`FLAGS_xxx`变量的对应关系为：

- `update` --> `FLAGS_update`, 
- `payload` --> `FLAGS_payload`, 
- `offset` --> `FLAGS_offset`, 
- `size` --> `FLAGS_size`, 
- `headers` --> `FLAGS_headers`, 
- `suspend` --> `FLAGS_suspend`, 
- `resume` --> `FLAGS_resume`, 
- `cancel` --> `FLAGS_cancel`, 
- `reset_status` --> `FLAGS_reset_status`, 
- `follow` --> `FLAGS_follow`

我没有深入看过base::CommandLine和brillo::FlagHelper类，从网上的介绍看是进行命令行处理的，从后面的操作看，这里应该是对`argc_`, `argv_`里面包含的命令行参数进行解析。

联想到我们命令行调用的操作：
```
bcm7252ssffdr4:/ # update_engine_client \
--payload=http://stbszx-bld-5/public/android/full-ota/payload.bin \
--update \
--headers="\
  FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY= \
  FILE_SIZE=282164983
  METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg= \
  METADATA_SIZE=21023 \
"
```
所以这里有：
```
FLAGS_payload: "http://stbszx-bld-5/public/android/full-ota/payload.bin"
FLAGS_update: true
FLAGS_headers: "FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY= \
                FILE_SIZE=282164983
                METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg= \
                METADATA_SIZE=21023"
```

分析完命令行选项解析后，继续查看后面的代码：

```
  bool keep_running = false;
  // 初始化Log操作
  brillo::InitLog(brillo::kLogToStderr);

  // Initialize a binder watcher early in the process before any interaction
  // with the binder driver.
  // binder_watcher_的初始化，对`binder_watcher_`具体作用还不太了解，这里先不做深入。
  binder_watcher_.Init();
```

接下来获取`"android.os.UpdateEngineService"`服务，并将其代理对象存放到`service_`中，可以简单理解为所有`UpdateEngineService`服务的操作都可以调用`service_`成员的相应方法来实现。
```
  // 获取名为"android.os.UpdateEngineService"的服务对象
  android::status_t status = android::getService(
      android::String16("android.os.UpdateEngineService"), &service_);
  // 服务获取失败，提示错误并退出
  if (status != android::OK) {
    LOG(ERROR) << "Failed to get IUpdateEngine binder from service manager: "
               << Status::fromStatusT(status).toString8();
    return ExitWhenIdle(1);
  }
```

剩下的就是将命令行`update_engine_client`提供的各种操作，如`suspend`, `resume`, `cancel`, `reset_status`, `follow`, `update`通过代理对象`service_`通知服务进程UpdateEngineService。
```
  // 调用服务进程的"suspend"操作
  if (FLAGS_suspend) {
    return ExitWhenIdle(service_->suspend());
  }

  // 调用服务进程的"resume"操作
  if (FLAGS_resume) {
    return ExitWhenIdle(service_->resume());
  }

  // 调用服务进程的"cancel"操作
  if (FLAGS_cancel) {
    return ExitWhenIdle(service_->cancel());
  }

  // 调用服务进程的"resetStatus"操作
  if (FLAGS_reset_status) {
    return ExitWhenIdle(service_->resetStatus());
  }

  // 如果指定"follow"选项，则绑定回调操作UECallback
  if (FLAGS_follow) {
    // Register a callback object with the service.
    callback_ = new UECallback(this);
    bool bound;
    if (!service_->bind(callback_, &bound).isOk() || !bound) {
      LOG(ERROR) << "Failed to bind() the UpdateEngine daemon.";
      return 1;
    }
    keep_running = true;
  }

  // 如果指定"update"操作，则解析"headers"参数
  if (FLAGS_update) {
    // 解析"headers"，生成键值对列表
    std::vector<std::string> headers = base::SplitString(
        FLAGS_headers, "\n", base::KEEP_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
    std::vector<android::String16> and_headers;
    for (const auto& header : headers) {
      and_headers.push_back(android::String16{header.data(), header.size()});
    }
    // 调用服务进程的"applyPlayload"操作
    Status status = service_->applyPayload(
        android::String16{FLAGS_payload.data(), FLAGS_payload.size()},
        FLAGS_offset,
        FLAGS_size,
        and_headers);
    if (!status.isOk())
      return ExitWhenIdle(status);
  }

  if (!keep_running)
    return ExitWhenIdle(EX_OK);
```
前面几个`suspend`, `resume`, `cancel`和`reset_status`都比较直接，直接通过无参数调用`service_->suspend()`, `service_->resume()`, `service_->cancel()`和`service_->resetStatus()`通知服务进程UpdateEngineService。

对于`follow`操作，则生成一个`UECallback`对象，并通过`service_->bind(callback_, &bound)`将其绑定到UpdateEngineService服务端的IUpdateEngineCallback对象上。

对于update操作，
```
  if (FLAGS_update) {
    std::vector<std::string> headers = base::SplitString(
        FLAGS_headers, "\n", base::KEEP_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
    std::vector<android::String16> and_headers;
    for (const auto& header : headers) {
      and_headers.push_back(android::String16{header.data(), header.size()});
    }
    Status status = service_->applyPayload(
        android::String16{FLAGS_payload.data(), FLAGS_payload.size()},
        FLAGS_offset,
        FLAGS_size,
        and_headers);
    if (!status.isOk())
      return ExitWhenIdle(status);
  }
```
这里先将`FLAGS_headers`按照换行符"`\n`"进行拆分，并存放到headers中，
然后将headers的每一项通`过push_back`操作存放到容器`and_headers`中。
可以简单理解为将headers操作的每一行对分别存放到容器`and_header`中，这样`and_header`中的每一项都是一个键值对字符串：
```
FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY=
FILE_SIZE=282164983
METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg=
METADATA_SIZE=21023
```
然后将`payload`, `offset`, `size`参数和解析得到的`and_headers`一并传递给`service_->applyPayload()`方法，此时服务端`UpdateEngineService`进程会调用`applyPayload`进行升级更新。

如果`service_->applyPayload()`调用操作失败，则调用`ExitWhenIdle(status)`并退出：
```
    if (!status.isOk())
      return ExitWhenIdle(status);
```

由于follow状态需要一直跟踪server端的状态，因此要求一直运行，但除follow操作外的其它操作，在执行完后就完成了，不再需要继续执行，所以如果`keep_runing`为false，则退出：
```
  if (!keep_running)
    return ExitWhenIdle(EX_OK);
```

接下来就是client运行在follow状态才出现的情况了？需要一直follow到永远吗？原则上是的。但是如果server端挂掉了，再follow就没有意义了，所以注册一个事件来检查server端是否已经挂掉：
```
  // When following updates status changes, exit if the update_engine daemon
  // dies.
  android::BinderWrapper::Create();
  android::BinderWrapper::Get()->RegisterForDeathNotifications(
      android::os::IUpdateEngine::asBinder(service_),
      base::Bind(&UpdateEngineClientAndroid::UpdateEngineServiceDied,
                 base::Unretained(this)));

  return EX_OK;
}
```

对OnInit()函数总体描述如下：
1. 解析可执行程序的命令行参数
2. 根据命令行参数指定的操作，调用服务端的相应接口
3. 如果是`follow`操作，则向服务端注册`callback`的客户端调用接口`callback_`
4. 如果是`update`操作，则解析`payload`的相关参数，并将其传递给服务端的`service_->applyPayload`操作
5. 对于`follow`操作，客户端需要一直跟踪服务端`update_engine`状态，如果`update_engine`进程退出了，那客户端也需要收到通知并退出

回到`client.Run()`实际执行的`Daemon::Run()`函数，其实会发现除了前面分析的`OnInit`函数，剩下的就很简单了：
```
# external\libbrillo\brillo\daemons\daemon.cc
int Daemon::Run() {
  int exit_code = OnInit();
  if (exit_code != EX_OK)
    return exit_code;

  brillo_message_loop_.Run();

  OnShutdown(&exit_code_);

  // base::RunLoop::QuitClosure() causes the message loop to quit
  // immediately, even if pending tasks are still queued.
  // Run a secondary loop to make sure all those are processed.
  // This becomes important when working with D-Bus since dbus::Bus does
  // a bunch of clean-up tasks asynchronously when shutting down.
  while (brillo_message_loop_.RunOnce(false /* may_block */)) {}

  return exit_code_;
}
```

完成`OnInit()`操作后，如果`OnInit`返回了非`EX_OK`值，说明操作失败，直接退出程序。

成功执行`OnInit(`)操作后，进程调用`brillo_message_loop_.Run()`来循环处理消息。

# 3. 总结

分析完`update_engine_client`的代码，我们发现整个操作还是比较简单，一句话总结如下：

`update_engine_client`解析命令行的各种操作(`suspend`/`resume`/`cancel`/`reset_status`/`follow`/`update`)，并将这些操作和参数通过binder机制，转发为对服务端进程`UpdateEngineService`相应操作的调用。

所以，剩下的事就是根据`update_engine_client`的各种操作和传入参数，分析服务端进程`UpdateEngineService`的行为。

## 4. 联系和福利

- 个人微信公众号“洛奇看世界”，一个大龄码农的救赎之路。
  - 公众号回复关键词“Android电子书”，获取超过150本Android相关的电子书和文档。电子书包含了Android开发相关的方方面面，从此你再也不需要到处找Android开发的电子书了。
  - 公众号回复关键词“个人微信”，获取个人微信联系方式。<font color="red">我组建了一个Android OTA的讨论组，联系我，说明Android OTA，拉你进组一起讨论。</font>

  ![image](https://img-blog.csdn.net/20180507223120679)
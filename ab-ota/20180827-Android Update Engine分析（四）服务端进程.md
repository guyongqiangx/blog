# Android Update Engine分析（四）服务端进程

前面三篇分别分析了Makefile，Protobuf和AIDL相关文件以及Update Engine的客户端进程`update_engine_client`，

- [Android Update Engine分析（一）Makefile](https://blog.csdn.net/guyongqiangx/article/details/77650362)
- [Android Update Engine分析（二）Protobuf和AIDL文件](https://blog.csdn.net/guyongqiangx/article/details/80819901)
- [Android Update Engine分析（三）客户端进程](https://blog.csdn.net/guyongqiangx/article/details/80820399)

本篇开始分析Update Engine的服务端进程`update_engine`。

> 本文涉及的Android代码版本：android‐7.1.1_r23 (NMF27D)

## 1. `update_engine`的文件依赖关系

老规矩，在开始代码之前，先看看文件的依赖关系。

有人或许会问，分析代码就分析代码，干嘛还在先去列举依赖的文件？岂不多此一举？

当你尝试阅读代码就会明白，代码中涉及多个分支的条件编译时，有些函数在多个分支实现中都会存在，这时到底应该分析哪个文件就是个问题。如果将这些文件的依赖都列举出来，很容易就知道哪些文件有参与编译，哪些文件没有被使用。如果不确定，那就回头来看看代码的文件依赖关系就知道了。

例如名为`update_engine_client.cc`的文件，里面有`main`函数，有各种实现代码，看起来像是客户端的入口，那这个文件真的是客户端`update_engine_client`的入口吗？

又例如，名为`update_attempter.cc`的文件，里面也实现了一套Update Engine的核心逻辑，那应该分析这个文件吗？

单从文件命名上来看，根本无法确定上面提到的这两个文件是否有参与编译。如果你有文件依赖列表，你就知道客户端进程的代码是`update_engine_client_android.cc`；而Android上Update Engine中使用的是`update_attempter_android.cc`而不是`update_attempter.cc`。

Android Update Engine的服务端守护进程自身的代码文件只有一个，那就是`main.cc`，其余是对各种库的依赖，以下列举服务端守护进程`update_engine`和Update Engine相关库和文件的依赖关系。

服务端守护进程`update_engine`：
```
update_engine
  --> files (
        main.cc
      )
  --> static libraries (
        libupdate_engine_android
        libpayload_consumer
        libfs_mgr
        update_metadata-protos
        libxz-host
        libbz
      )
  --> shared libraries (
        libcrypto-host
        libprotobuf-cpp-lite
        libandroid
        libbinder
        libbinderwrapper
        libcutils
        libcurl
        libhardware
        libssl
        libssl
      )
```

服务端守护进程`update_engine`除去依赖Android的公共静态和动态库之外，跟Update Engine相关的库主要有三个：
- `libupdate_engine_android`
- `libpayload_consumer`
- `update_metadata-protos`

我们的目标是分析`Update Engine`相关内容，因此这里对公共的静态和动态库不做展开说明。

下面是Update Engine三个主要的库文件依赖关系：
```
libupdate_engine_android (STATIC_LIBRARIES)
  --> binder_bindings/android/os/IUpdateEngine.aidl
      binder_bindings/android/os/IUpdateEngineCallback.aidl
      binder_service_android.cc
      boot_control_android.cc
      certificate_checker.cc
      daemon.cc
      daemon_state_android.cc
      hardware_android.cc
      libcurl_http_fetcher.cc
      network_selector_android.cc
      proxy_resolver.cc
      update_attempter_android.cc
      update_status_utils.cc
      utils_android.cc

libpayload_consumer (STATIC_LIBRARIES)
  --> common/action_processor.cc
      common/boot_control_stub.cc
      common/clock.cc
      common/constants.cc
      common/cpu_limiter.cc
      common/error_code_utils.cc
      common/hash_calculator.cc
      common/http_common.cc
      common/http_fetcher.cc
      common/file_fetcher.cc
      common/hwid_override.cc
      common/multi_range_http_fetcher.cc
      common/platform_constants_android.cc
      common/prefs.cc
      common/subprocess.cc
      common/terminator.cc
      common/utils.cc
      payload_consumer/bzip_extent_writer.cc
      payload_consumer/delta_performer.cc
      payload_consumer/download_action.cc
      payload_consumer/extent_writer.cc
      payload_consumer/file_descriptor.cc
      payload_consumer/file_writer.cc
      payload_consumer/filesystem_verifier_action.cc
      payload_consumer/install_plan.cc
      payload_consumer/payload_constants.cc
      payload_consumer/payload_verifier.cc
      payload_consumer/postinstall_runner_action.cc
      payload_consumer/xz_extent_writer.cc

update_metadata-protos (STATIC_LIBRARIES)
  --> update_metadata.proto
```

如果阅读代码时不清楚文件是否有用，回头来看看这个列表吧。

闲话到此位置，以下对代码展开分析。

## 2. `update_engine`代码分析

### 2.1 main.cc

服务端进程`update_engine`的入口在`main.cc`文件中，因此这里从`main`函数入手。

```
// 文件: system\update_engine\main.cc
int main(int argc, char** argv) {
  DEFINE_bool(logtostderr, false,
              "Write logs to stderr instead of to a file in log_dir.");
  DEFINE_bool(foreground, false,
              "Don't daemon()ize; run in foreground.");

  chromeos_update_engine::Terminator::Init();
  brillo::FlagHelper::Init(argc, argv, "Chromium OS Update Engine");
  chromeos_update_engine::SetupLogging(FLAGS_logtostderr);
  if (!FLAGS_foreground)
    PLOG_IF(FATAL, daemon(0, 0) == 1) << "daemon() failed";

  LOG(INFO) << "Chrome OS Update Engine starting";

  // xz-embedded requires to initialize its CRC-32 table once on startup.
  xz_crc32_init();

  // Ensure that all written files have safe permissions.
  // This is a mask, so we _block_ all permissions for the group owner and other
  // users but allow all permissions for the user owner. We allow execution
  // for the owner so we can create directories.
  // Done _after_ log file creation.
  umask(S_IRWXG | S_IRWXO);

  chromeos_update_engine::UpdateEngineDaemon update_engine_daemon;
  int exit_code = update_engine_daemon.Run();

  LOG(INFO) << "Chrome OS Update Engine terminating with exit code "
            << exit_code;
  return exit_code;
}
```

整个main函数看起来比较简单：
1. 定义入口参数并进行初始化；
2. 初始化CRC-32 table；
3. 生成`update_engine_daemon`，并调用其Run()方法；

- 定义入口参数并进行初始化

```
  # 定义参数logtostderr
  DEFINE_bool(logtostderr, false,
              "Write logs to stderr instead of to a file in log_dir.");
  # 定义参数foreground
  DEFINE_bool(foreground, false,
              "Don't daemon()ize; run in foreground.");

  # 初始化Terminator
  chromeos_update_engine::Terminator::Init();
  # 解析参数
  brillo::FlagHelper::Init(argc, argv, "Chromium OS Update Engine");
  chromeos_update_engine::SetupLogging(FLAGS_logtostderr);
  if (!FLAGS_foreground)
    PLOG_IF(FATAL, daemon(0, 0) == 1) << "daemon() failed";

  LOG(INFO) << "Chrome OS Update Engine starting";
```
通过`DEFINE_bool`宏定义了两个参数`logtostderr`, `foreground`，展开后得到两个变量`FLAGS_logtostderr`和`FLAGS_foreground`。前者用于设置日志输出重定向，后者用于指定  `update_engine`进程是否以forground方式运行。

- 初始化CRC-32 table

```
  // xz-embedded requires to initialize its CRC-32 table once on startup.
  xz_crc32_init();

  // Ensure that all written files have safe permissions.
  // This is a mask, so we _block_ all permissions for the group owner and other
  // users but allow all permissions for the user owner. We allow execution
  // for the owner so we can create directories.
  // Done _after_ log file creation.
  umask(S_IRWXG | S_IRWXO);
```

这段代码目前不清楚后面哪里会用到，看起来像是创建一个查找表，用于解压缩时提高性能。不是分析重点，不解释。

`umask`操作设置当前进程的文件操作权限。

- 生成`update_engine_daemon`对象，并调用其`Run()`方法

Update Engine服务端守护进程的核心`update_engine_daemon`对象。

```
  chromeos_update_engine::UpdateEngineDaemon update_engine_daemon;
  int exit_code = update_engine_daemon.Run();

  LOG(INFO) << "Chrome OS Update Engine terminating with exit code "
            << exit_code;
  return exit_code;
```

`update_engine`跟客户端进程`update_engine_client`一样，都是派生于`brillo::Daemon`类，所以这里会执行父类`brillo::Daemon`的`Run()`方法:

```
// 文件: external\libbrillo\brillo\daemons\daemon.cc
int Daemon::Run() {
  // 1. 执行OnInit函数进行初始化
  int exit_code = OnInit();
  if (exit_code != EX_OK)
    return exit_code;

  // 2. 初始化完成后调用brillo_message_loop_.Run()进入消息循环处理模式
  brillo_message_loop_.Run();

  // 3. 调用OnShutdown
  OnShutdown(&exit_code_);

  // 4. 等待退出消息
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
1. 执行`OnInit()`函数进行初始化
2. 初始化完成后调用`brillo_message_loop_.Run()`进入消息循环处理模式
3. 从`Run()`退出则调用`OnShutdown()`，其实`OnShutdown()`操作里面什么都没做。
4. 等待退出消息

总体上，整个进程的结构比较简单，就是基于`brillo::Daemon`类的结构，进行初始化，启动`brilllo::MessageLoop`机制进行消息循环处理直到退出。这4个操作中，重点是文件`system\update_engine\daemon.cc`中的`OnInit()`函数。

### 2.2 `UpdateEngineDaemon`类

文件`system\update_engine\daemon.cc`提供了类`UpdateEngineDaemon`的实现。

留意跟Update Engine相关的`daemon.cc`文件有两个，分别是：
- `external\libbrillo\brillo\daemons\daemon.cc`
- `system\update_engine\daemon.cc`

前者定义了`brillo::Daemon`类，作为`update_engine`系统的消息处理框架。后者定义了`UpdateEngineDaemon`类, 继承自前者，在`update_engine`守护进程中实例化生成业务对象`update_engine_daemon`。

`update_engine_daemon.Run()`会执行父类的`Daemon::Run()`方法，在该方法中调用`OnInit()`函数进行初始化时，由于`int Daemon::OnInit()`定义为虚函数，所以这里执行的是其子类`UpdateEngineDaemon`的`OnInit()`函数，这是整个Update Engine初始化最重要的部分:
```
// 文件: system\update_engine\daemon.cc

int UpdateEngineDaemon::OnInit() {
  // Register the |subprocess_| singleton with this Daemon as the signal
  // handler.
  subprocess_.Init(this);

  // 调用父类brillo::Daemon的OnInit()方法，注册SIGTERM, SIGINT, SIGHUP的处理函数
  int exit_code = Daemon::OnInit();
  if (exit_code != EX_OK)
    return exit_code;

  // Android.mk中分析过USE_WEAVE=0, USE_BINDER=1，以下代码会被编译
#if USE_WEAVE || USE_BINDER
  android::BinderWrapper::Create();
  binder_watcher_.Init();
#endif  // USE_WEAVE || USE_BINDER

  // Android.mk中分析过，这里USE_DBUS=0, 不会编译以下代码，略过
#if USE_DBUS
  // We wait for the D-Bus connection for up two minutes to avoid re-spawning
  // the daemon too fast causing thrashing if dbus-daemon is not running.
  scoped_refptr<dbus::Bus> bus = dbus_connection_.ConnectWithTimeout(
      base::TimeDelta::FromSeconds(kDBusSystemMaxWaitSeconds));

  if (!bus) {
    // TODO(deymo): Make it possible to run update_engine even if dbus-daemon
    // is not running or constantly crashing.
    LOG(ERROR) << "Failed to initialize DBus, aborting.";
    return 1;
  }

  CHECK(bus->SetUpAsyncOperations());
#endif  // USE_DBUS

  // 由于没有定义__BRILLO__和__CHROMEOS__，所以这里应该走else路径
#if defined(__BRILLO__) || defined(__CHROMEOS__)
  // Initialize update engine global state but continue if something fails.
  // TODO(deymo): Move the daemon_state_ initialization to a factory method
  // avoiding the explicit re-usage of the |bus| instance, shared between
  // D-Bus service and D-Bus client calls.
  RealSystemState* real_system_state = new RealSystemState(bus);
  daemon_state_.reset(real_system_state);
  LOG_IF(ERROR, !real_system_state->Initialize())
      << "Failed to initialize system state.";
#else  // !(defined(__BRILLO__) || defined(__CHROMEOS__))
  // 针对非__BRILLO__和__CHROMEOS__的路径
  // 初始化一个类DaemonStateAndroid的实例，赋值到daemon_state_android
  // 对于DaemonStateAndroid，其构造函数DaemonStateAndroid()为空，没有任何操作：
  // DaemonStateAndroid() = default;
  DaemonStateAndroid* daemon_state_android = new DaemonStateAndroid();
  // 用指针daemon_state_android设置daemon_state_成员
  daemon_state_.reset(daemon_state_android);
  
  // 接下来调用DaemonStateAndroid类的方法Initialize()进行初始化
  // update_engine进程真正的初始化开始啦……
  LOG_IF(ERROR, !daemon_state_android->Initialize())
      << "Failed to initialize system state.";
#endif  // defined(__BRILLO__) || defined(__CHROMEOS__)

  // USE_BINDER=1，以下代码会被编译
#if USE_BINDER
  // Create the Binder Service.
#if defined(__BRILLO__) || defined(__CHROMEOS__) // 由于没有定义__BRILLO__和__CHROMEOS__，所以这里应该走else路径
  binder_service_ = new BinderUpdateEngineBrilloService{real_system_state};
#else  // !(defined(__BRILLO__) || defined(__CHROMEOS__))
  // 生成Binder服务对象`binder_service_`
  binder_service_ = new BinderUpdateEngineAndroidService{
      daemon_state_android->service_delegate()};
#endif  // defined(__BRILLO__) || defined(__CHROMEOS__)
  // 使用`binder_service_`向系统注册名为`"android.os.UpdateEngineService"`的服务
  auto binder_wrapper = android::BinderWrapper::Get();
  if (!binder_wrapper->RegisterService(binder_service_->ServiceName(),
                                       binder_service_)) {
    LOG(ERROR) << "Failed to register binder service.";
  }

  // 以观察者模式将`binder_service`添加到`daemon_state_`的观察者集合中
  // 观察者设计模式中，被观察对象以广播方式向注册的观察者发送消息，降低各对象的耦合度
  daemon_state_->AddObserver(binder_service_.get());
#endif  // USE_BINDER

// Android.mk中分析过，这里USE_DBUS=0, 不会编译以下代码，略过
#if USE_DBUS  
  // Create the DBus service.
  dbus_adaptor_.reset(new UpdateEngineAdaptor(real_system_state, bus));
  daemon_state_->AddObserver(dbus_adaptor_.get());

  dbus_adaptor_->RegisterAsync(base::Bind(&UpdateEngineDaemon::OnDBusRegistered,
                                          base::Unretained(this)));
  LOG(INFO) << "Waiting for DBus object to be registered.";
#else  // !USE_DBUS
  // 从字面`StartUpdater`看，这里开始Update Engine的核心工作
  daemon_state_->StartUpdater();
#endif  // USE_DBUS
  return EX_OK;
}

```

这段代码使用的宏特别多，看起来很凌乱，整理一下，主要有以下几件事:

- 创建一个`DaemonStateAndroid`类的对象`daemon_state_android`，并对其进行初始化
  ```
  DaemonStateAndroid* daemon_state_android = new DaemonStateAndroid();
  daemon_state_.reset(daemon_state_android);
  LOG_IF(ERROR, !daemon_state_android->Initialize())
      << "Failed to initialize system state.";
  ```
  `UpdateEngineDaemon`中通过`unique_ptr`指针`daemon_state_`访问`daemon_state_android`。

- 类对象`daemon_state_android`调用`service_delegate()`返回一个委托对象，用于构造提供Binder服务的私有私有智能指针`binder_service_`
  ```
  binder_service_ = new BinderUpdateEngineAndroidService{
      daemon_state_android->service_delegate()};
  ```

  其实`binder_service_`也是通过`daemon_state_`实现的。从代码可见，通过调用`daemon_state_android`的`service_delegate()`接口:

    ```
    ServiceDelegateAndroidInterface* DaemonStateAndroid::service_delegate() {
      return update_attempter_.get();
    }
    ```
  将其私有成员`update_attempter_`传递给`BinderUpdateEngineAndroidService`类的构造函数：
    ```
    BinderUpdateEngineAndroidService::BinderUpdateEngineAndroidService(
        ServiceDelegateAndroidInterface* service_delegate)
        : service_delegate_(service_delegate) {
    }
    ```
  所以这里就是将`daemon_state_`的私有成员`update_attempter_`委托给`binder_service_`的私有成员`service_delegate_`。
  
  在`BinderUpdateEngineAndroidService`的实现中，`applyPayload/suspend/resume/cancel/resetStatus`操作都会转发给成员`service_delegate_`，所以这些操作最终由`update_attempter_`来执行。可以这么理解，`binder_service_`也是通过`daemon_state_`来实现。
  
  > 实际上，如果机械的理解"`binder_service_`是通过`daemon_state_`来实现"是有问题的，因为除了上面提到的"`applyPayload / suspend / resume / cancel / resetStatus`"部分，`binder_service_`在运行中还有调用`callback`进行的状态更新操作，这些`callback`操作接口是使用`bind`调用的传入参数设置的，并非来自`daemon_state_`，所以不是由`daemon_state_`实现。
  >
  > 所以这里只是粗略的将`binder_service_`想象为是通过`daemon_state_`来实现而已。

- 使用私有的`binder_service_`对象向系统注册名为`"android.brillo.UpdateEngineService"`的系统服务
  ```
  auto binder_wrapper = android::BinderWrapper::Get();
  if (!binder_wrapper->RegisterService(binder_service_->ServiceName(),
                                       binder_service_)) {
    LOG(ERROR) << "Failed to register binder service.";
  }
  ```

- 将`binder_service`添加为`daemon_state_`的观察对象，并通过`StartUpdater()`调用升级的主类`UpdateAttempterAndroid`进行各种处理
  ```
  daemon_state_->AddObserver(binder_service_.get());
  ...
  daemon_state_->StartUpdater();
  ```
  
  进行完上面的设置，整个Update Engine服务端的业务基本上也就交由`daemon_state_`的私有成员`update_attempter_`来处理了。所以`daemon_state_`对象对应的类`DaemonStateAndroid`，是真正的Update Engine业务实现者，而其私有成员`update_attempter_`所在的类才是整个Update Engine服务端的核心类。


综述一下，代码看起来很复杂，但简化理解起来也还算简单。为什么这么说呢？

服务端进程的业务对象`update_engine_daemon`是`UpdateEngineDaemon`类的实例，通过继承`brillo::Daemon`类构建了daemon进程的基本功能，包含了3个重要的私有指针成员：
- `binder_watcher_`
- `binder_service_`
- `daemon_state_`

这里`binder_watcher_`是构建Binder服务的公共基础设施。`binder_service_`通过`binder_watcher_`的`RegisterService`接口进行注册，从而向外界提供名为`android.brillo.UpdateEngineService`的Binder服务。

因此客户端对IUpdateEngine接口的调用会转化为对`binder_service_`调用，这些操作会进一步被转发为`daemon_state_`私有成员`update_attempter_`的相应操作。

以下是省略掉`binder_watcher`后服务端进程对象`update_engine_daemon`简单的示意图。所以`daemon_state_`对象对应的的类`DaemonStateAndroid`，是真正的Update Engine业务实现者。

![update_engine_daemon-instance](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/update_engine_daemon-instance.png?raw=true)

`daemon_state_`调用`AddObserver()`将`binder_service_`添加到私有的`service_observers_`集合中去：
```
daemon_state_->AddObserver(binder_service_.get())
```
因为每个service在bind时会注册相应的callback接口，所以服务端可以通过调用每个观察者的callback接口向每个使用服务的客户端广播消息，例如升级进度。

`daemon_state_`调用`StartUpdater()`开始Update Engine的正式工作了。
```
daemon_state_->StartUpdater()
```
阅读代码就会发现，`StartUpdater()`是其私有成员`update_attempter_`调用`Init()`操作，这之后的工作就基本上交给`update_attempter_`了。
```
bool DaemonStateAndroid::StartUpdater() {
  // The DaemonState in Android is a passive daemon. It will only start applying
  // an update when instructed to do so from the exposed binder API.
  update_attempter_->Init();
  return true;
}
```

好了，工作转到`update_attempter_`以后我们就不需要再关心外层的`update_engine_daemon`是干什么的了。余下的重点就是对象`binder_service_`对应的类`BinderUpdateEngineAndroidService`和对象`daemon_state_`对应的类`DaemonStateAndroid`进行分析。

### 2.3 `BinderUpdateEngineAndroidService`类

`update_engine_daemon`的私有指针`binder_service_`对应的类为`BinderUpdateEngineAndroidService`，该类提供了IUpdateEngine操作和IUpdateEngineCallback回调接口的实现。其对应的代码位于文件`system\update_engine\binder_service_android.cc`中。

```
# file: system\update_engine\binder_service_android.h

class BinderUpdateEngineAndroidService : public android::os::BnUpdateEngine,
                                         public ServiceObserverInterface {
 public:
  BinderUpdateEngineAndroidService(
      ServiceDelegateAndroidInterface* service_delegate);
  ~BinderUpdateEngineAndroidService() override = default;

  const char* ServiceName() const {
    return "android.os.UpdateEngineService";
  }

  // ServiceObserverInterface overrides.
  void SendStatusUpdate(int64_t last_checked_time,
                        double progress,
                        update_engine::UpdateStatus status,
                        const std::string& new_version,
                        int64_t new_size) override;
  void SendPayloadApplicationComplete(ErrorCode error_code) override;

  // Channel tracking changes are ignored.
  void SendChannelChangeUpdate(const std::string& tracking_channel) override {}

  // android::os::BnUpdateEngine overrides.
  android::binder::Status applyPayload(
      const android::String16& url,
      int64_t payload_offset,
      int64_t payload_size,
      const std::vector<android::String16>& header_kv_pairs) override;
  android::binder::Status bind(
      const android::sp<android::os::IUpdateEngineCallback>& callback,
      bool* return_value) override;
  android::binder::Status suspend() override;
  android::binder::Status resume() override;
  android::binder::Status cancel() override;
  android::binder::Status resetStatus() override;

 private:
  // Remove the passed |callback| from the list of registered callbacks. Called
  // whenever the callback object is destroyed.
  void UnbindCallback(android::os::IUpdateEngineCallback* callback);

  // List of currently bound callbacks.
  std::vector<android::sp<android::os::IUpdateEngineCallback>> callbacks_;

  // Cached copy of the last status update sent. Used to send an initial
  // notification when bind() is called from the client.
  int last_status_{-1};
  double last_progress_{0.0};

  ServiceDelegateAndroidInterface* service_delegate_;
};
```

从定义看，类`BinderUpdateEngineAndroidService`继承自`BnUpdateEngine`类和`ServiceObserverInterface`类，实际上这两个类都属于接口类，主要用于统一定义接口，然后由子类来实现。这方面，C#和Java就比较方便，可以直接定义接口类型实现接口继承。
`BinderUpdateEngineAndroidService`的父类中:
- `BnUpdateEngine`主要是用于实现`IUpdateEngine`接口；
- `ServiceObserverInterface`类用于实现回调通知接口，包括：`SendStatusUpdate`，`SendPayloadApplicationComplete`和`SendChannelChangeUpdate`。

除去以上的接口，我们可以看到`BinderUpdateEngineAndroidService`类还有两个重要的私有成员，`IUpdateEngineCallback`类型的回调对象`callbacks_`和Binder服务的委托对象`service_delegate_`。

前一节中分析过，`BinderUpdateEngineAndroidService`的构造函数中，直接将传递进来的参数用于构造`binder_service_`的委托对象`service_delegate_`。

一句话，`BinderUpdateEngineAndroidService`的`service_delegate_`就是`DaemonStateAndroid`类的私有成员`update_attempter_`。所有对`service_delegate_`的操作实际上转化为对`update_attempter_`相应方法的调用，如下：

```
Status BinderUpdateEngineAndroidService::applyPayload(
    const android::String16& url,
    int64_t payload_offset,
    int64_t payload_size,
    const std::vector<android::String16>& header_kv_pairs) {
  const std::string payload_url{android::String8{url}.string()};
  std::vector<std::string> str_headers;
  str_headers.reserve(header_kv_pairs.size());
  for (const auto& header : header_kv_pairs) {
    str_headers.emplace_back(android::String8{header}.string());
  }

  brillo::ErrorPtr error;
  if (!service_delegate_->ApplyPayload(
          payload_url, payload_offset, payload_size, str_headers, &error)) {
    return ErrorPtrToStatus(error);
  }
  return Status::ok();
}

Status BinderUpdateEngineAndroidService::suspend() {
  brillo::ErrorPtr error;
  if (!service_delegate_->SuspendUpdate(&error))
    return ErrorPtrToStatus(error);
  return Status::ok();
}

Status BinderUpdateEngineAndroidService::resume() {
  brillo::ErrorPtr error;
  if (!service_delegate_->ResumeUpdate(&error))
    return ErrorPtrToStatus(error);
  return Status::ok();
}

Status BinderUpdateEngineAndroidService::cancel() {
  brillo::ErrorPtr error;
  if (!service_delegate_->CancelUpdate(&error))
    return ErrorPtrToStatus(error);
  return Status::ok();
}

Status BinderUpdateEngineAndroidService::resetStatus() {
  brillo::ErrorPtr error;
  if (!service_delegate_->ResetStatus(&error))
    return ErrorPtrToStatus(error);
  return Status::ok();
}
```

另外，在`BinderUpdateEngineAndroidService`的`bind`操作时，会使用传入的callback参数设置私有的`callbacks_`成员:
```
Status BinderUpdateEngineAndroidService::bind(
    const android::sp<IUpdateEngineCallback>& callback, bool* return_value) {
  callbacks_.emplace_back(callback);

  auto binder_wrapper = android::BinderWrapper::Get();
  binder_wrapper->RegisterForDeathNotifications(
      IUpdateEngineCallback::asBinder(callback),
      base::Bind(&BinderUpdateEngineAndroidService::UnbindCallback,
                 base::Unretained(this),
                 base::Unretained(callback.get())));

  // Send an status update on connection (except when no update sent so far),
  // since the status update is oneway and we don't need to wait for the
  // response.
  if (last_status_ != -1)
    callback->onStatusUpdate(last_status_, last_progress_);

  *return_value = true;
  return Status::ok();
}
```

另外两个方法`SendStatusUpdate`和`SendPayloadApplicationComplete`用于实现`IUpdateEngineCallback`接口，对这两个方法的调用，最后都是对`bind`操作传入的`callback`的调用(`callback`参数被保存到`callback_`私有成员中了)：
```
void BinderUpdateEngineAndroidService::SendStatusUpdate(
    int64_t /* last_checked_time */,
    double progress,
    update_engine::UpdateStatus status,
    const std::string& /* new_version  */,
    int64_t /* new_size */) {
  last_status_ = static_cast<int>(status);
  last_progress_ = progress;
  for (auto& callback : callbacks_) {
    callback->onStatusUpdate(last_status_, last_progress_);
  }
}

void BinderUpdateEngineAndroidService::SendPayloadApplicationComplete(
    ErrorCode error_code) {
  for (auto& callback : callbacks_) {
    callback->onPayloadApplicationComplete(static_cast<int>(error_code));
  }
}
```

总结下`BinderUpdateEngineAndroidService`类，主要是将外部服务接收到的请求发送到`DaemonStateAndroid`类的`update_attempter_`对象，如果有状态更新，则调用`bind`操作时传入的`IUpdateEngineCallback`类型的回调函数通知外部应用。

### 2.4 `DaemonStateAndroid`类

`UpdateEngineDaemon`的私有指针`binder_service_`对应的类为`BinderUpdateEngineAndroidService`，该类提供了IUpdateEngine操作和IUpdateEngineCallback回调接口的实现。其对应的代码位于文件`system\update_engine\binder_service_android.cc`中。

`UpdateEngineDaemon`的私有指针`daemon_state_`对应的类为`DaemonStateAndroid`，是整个Update Engine业务的实现这，看完代码会发现这个实现者还有个核心，那就是`update_attempter_`。

废话少数，先来看看`DaemonStateAndroid`类的实现文件`system\update_engine\daemon_state_android.cc`。

文件中总共定义了5个函数：
- `Initialize()`
- `StartUpdater()`
- `AddObserver(* observer)` (这里*表示是observer的指针)
- `RemoveObserver(* observer)` (这里*表示是observer的指针)
- `service_delegate()`

我们看看这几个函数在`UpdateEngineDaemon::OnInit()`中是如何使用的吧。还记得吗？再啰嗦一下吧：
```
// file: system\update_engine\daemon.cc

int UpdateEngineDaemon::OnInit() {

  ...

  DaemonStateAndroid* daemon_state_android = new DaemonStateAndroid();
  daemon_state_.reset(daemon_state_android);
  LOG_IF(ERROR, !daemon_state_android->Initialize())
      << "Failed to initialize system state.";

  ...
  
  binder_service_ = new BinderUpdateEngineAndroidService{
      daemon_state_android->service_delegate()};

  auto binder_wrapper = android::BinderWrapper::Get();
  if (!binder_wrapper->RegisterService(binder_service_->ServiceName(),
                                       binder_service_)) {
    LOG(ERROR) << "Failed to register binder service.";
  }

  daemon_state_->AddObserver(binder_service_.get());

  daemon_state_->StartUpdater();
}
```

以上是经过简化后的`UpdateEngineDaemon::OnInit()`函数，这里只突出了`DaemonStateAndroid`类及其对象的活动，下面对这些活动逐个分析。

#### 初始化`daemon_state_`

```
  DaemonStateAndroid* daemon_state_android = new DaemonStateAndroid();
  daemon_state_.reset(daemon_state_android);
```
使用new操作构造一个`DaemonStateAndroid`类的对象`daemon_state_android`，并用这个对象初始化指针成员`daemon_state_`。
实际上其构造函数是一个空操作，啥也没做：
```
class DaemonStateAndroid : public DaemonStateInterface {
 public:
  DaemonStateAndroid() = default;
  ~DaemonStateAndroid() override = default;
  
  ...

}
```
留意`daemon_state_`实际上是`DaemonStateAndroid`父类`DaemonStateInterface`的指针，这里指向了子类的对象。

#### 调用`Initialize()`

接下来调用`Initialize()`进行对`daemon_state_android`进行初始化：
```
  LOG_IF(ERROR, !daemon_state_android->Initialize())
      << "Failed to initialize system state.";
```

`Initialize`函数代码如下：
```
bool DaemonStateAndroid::Initialize() {
  // 调用CreateBootControl创建boot_control_，连接BootControl的HAL模块
  boot_control_ = boot_control::CreateBootControl();
  if (!boot_control_) {
    LOG(WARNING) << "Unable to create BootControl instance, using stub "
                 << "instead. All update attempts will fail.";
    boot_control_.reset(new BootControlStub());
  }

  // 调用CreateHardware创建hardware_，连接Hardware的HAL模块
  hardware_ = hardware::CreateHardware();
  if (!hardware_) {
    LOG(ERROR) << "Error intializing the HardwareInterface.";
    return false;
  }

  // 检查boot mode和official build
  LOG_IF(INFO, !hardware_->IsNormalBootMode()) << "Booted in dev mode.";
  LOG_IF(INFO, !hardware_->IsOfficialBuild()) << "Booted non-official build.";

  // Initialize prefs.
  base::FilePath non_volatile_path;
  // TODO(deymo): Fall back to in-memory prefs if there's no physical directory
  // available.
  if (!hardware_->GetNonVolatileDirectory(&non_volatile_path)) {
    LOG(ERROR) << "Failed to get a non-volatile directory.";
    return false;
  }
  Prefs* prefs = new Prefs();
  prefs_.reset(prefs);
  if (!prefs->Init(non_volatile_path.Append(kPrefsSubDirectory))) {
    LOG(ERROR) << "Failed to initialize preferences.";
    return false;
  }

  // The CertificateChecker singleton is used by the update attempter.
  certificate_checker_.reset(
      new CertificateChecker(prefs_.get(), &openssl_wrapper_));
  certificate_checker_->Init();

  // Initialize the UpdateAttempter before the UpdateManager.
  update_attempter_.reset(new UpdateAttempterAndroid(
      this, prefs_.get(), boot_control_.get(), hardware_.get()));

  return true;
}
```

上面这段代码的思路比较清晰，主要操作包括：
- 使用`BootControlAndroid`类的`CreateBootControl()`方法创建类对象并初始化`boot_control_`变量
- 使用`HardwareAndroid`类的`CreateHardware()`方法创建类对象并初始化`hardware_`变量
- 创建`Prefs`类的对象并初始化`prefs_`变量
- 创建`CertificateChecker`类的对象，并初始化`certificate_checker_`变量，然后执行`Init()`操作
- 使用当前`DaemonStateAndroid`类的对象`this`和前面生成的`prefs_`，`boot_control_`，`hardware_`变量来构造一个`UpdateAttempterAndroid`类对象用于设置`update_attempter_`变量

为了避免陷进代码的细节，这里不再深入下一层代码。最后总结一下，整个`Initialize()`函数主要就是初始化`certificate_checker_`和`update_attempter_`。

#### 创建`binder_service_`对象

创建`binder_service_`对象：
```
  binder_service_ = new BinderUpdateEngineAndroidService{
      daemon_state_android->service_delegate()};
```
这里使用`daemon_state_android->service_delegate()`操作返回的对象来创建`binder_service_`对象。

`service_deletegate()`操作到底做了什么？
```
ServiceDelegateAndroidInterface* DaemonStateAndroid::service_delegate() {
  return update_attempter_.get();
}
```
我去，这里就是返回私有成员`update_attempter_`而已。

比较有意思的是，我们来看看`BinderUpdateEngineAndroidService`的构造函数：
```
BinderUpdateEngineAndroidService::BinderUpdateEngineAndroidService(
    ServiceDelegateAndroidInterface* service_delegate)
    : service_delegate_(service_delegate) {
}
```
这里干嘛了？就是将外部传入的参数`service_delegate`(这里实际上是`update_attempter_`)设置给`service_delegate_`成员。

从名字`service_delegate_`看，这也是一个委托对象。浏览下`BinderUpdateEngineAndroidService`代码，关于`IUpdateEngine`接口(包括`applyPayload`, `suspend`, `resume`, `cancel`, `resetStatus`)的调用都是直接将其转发给了`service_delegate_`对象，这意味这所有这些对象最终都是调用`update_attemper_`的相应操作！！

#### 注册Update Engine的Binder服务

注册Update Engine的Binder服务，并将`binder_service_`添加到`daemon_state`的观察对象中：

```
  if (!binder_wrapper->RegisterService(binder_service_->ServiceName(),
                                       binder_service_)) {
    LOG(ERROR) << "Failed to register binder service.";
  }

  daemon_state_->AddObserver(binder_service_.get());
```
这里的`AddObserver`干了什么呢？不妨看看代码实现：
```
void DaemonStateAndroid::AddObserver(ServiceObserverInterface* observer) {
  service_observers_.insert(observer);
}
```
真简单，就是把传入的`observer`参数(这里为`binder_service_`)添加到`service_observers_`集合中去。这里的`service_observers_`有什么用呢？在`DaemonStateAndroid`的实现代码中没有提到，我开始也是一脸懵逼，直到我看了`UpdateAttempterAndroid`的代码。

先转到`UpdateAttempterAndroid`中，构造函数是这样的：
```
UpdateAttempterAndroid::UpdateAttempterAndroid(
    DaemonStateInterface* daemon_state,
    PrefsInterface* prefs,
    BootControlInterface* boot_control,
    HardwareInterface* hardware)
    : daemon_state_(daemon_state),
      prefs_(prefs),
      boot_control_(boot_control),
      hardware_(hardware),
      processor_(new ActionProcessor()) {
  network_selector_ = network::CreateNetworkSelector();
}
```
仔细留意这里的`daemon_state_(daemon_state)`，这里用传入的`daemon_state`初始化私有的`daemon_state_`成员。有两个成员函数会使用到`daemon_state_`成员，如下：
```
void UpdateAttempterAndroid::TerminateUpdateAndNotify(ErrorCode error_code) {
  if (status_ == UpdateStatus::IDLE) {
    LOG(ERROR) << "No ongoing update, but TerminatedUpdate() called.";
    return;
  }

  // Reset cpu shares back to normal.
  cpu_limiter_.StopLimiter();
  download_progress_ = 0;
  actions_.clear();
  UpdateStatus new_status =
      (error_code == ErrorCode::kSuccess ? UpdateStatus::UPDATED_NEED_REBOOT
                                         : UpdateStatus::IDLE);
  SetStatusAndNotify(new_status);
  ongoing_update_ = false;

  for (auto observer : daemon_state_->service_observers())
    observer->SendPayloadApplicationComplete(error_code);
}

void UpdateAttempterAndroid::SetStatusAndNotify(UpdateStatus status) {
  status_ = status;
  for (auto observer : daemon_state_->service_observers()) {
    observer->SendStatusUpdate(
        0, download_progress_, status_, "", install_plan_.payload_size);
  }
  last_notify_time_ = TimeTicks::Now();
}
```
这两个函数分别在Update结束和状态更新时对`service_observers`集合的成员逐个调用`SendPayloadApplicationComplete`和`SendStatusUpdate`，目的是向外界发送通知状态更新。

## 3. Update Engine的回调通知是如何实现的？

前面的第2.4节说道，对`daemon_state_`的`service_observers`集合成员逐个调用`SendPayloadApplicationComplete`和`SendStatusUpdate`，外接就能接收到通知。这是如何实现的呢？

让我们先回到`service_observers`所属的类`BinderUpdateEngineAndroidService`中代码实现：
```
void BinderUpdateEngineAndroidService::SendStatusUpdate(
    int64_t /* last_checked_time */,
    double progress,
    update_engine::UpdateStatus status,
    const std::string& /* new_version  */,
    int64_t /* new_size */) {
  last_status_ = static_cast<int>(status);
  last_progress_ = progress;
  for (auto& callback : callbacks_) {
    callback->onStatusUpdate(last_status_, last_progress_);
  }
}

void BinderUpdateEngineAndroidService::SendPayloadApplicationComplete(
    ErrorCode error_code) {
  for (auto& callback : callbacks_) {
    callback->onPayloadApplicationComplete(static_cast<int>(error_code));
  }
}
```

这里的两个方法`SendStatusUpdate`和`SendPayloadApplicationComplete`，实际上是调用`callbacks_`的`onStatusUpdate`和`onPayloadApplicationComplete`。

`callbacks_`是`IUpdateEngineCallback`的集合，是在`bind`操作是作为参数传入的：
```
Status BinderUpdateEngineAndroidService::bind(
    const android::sp<IUpdateEngineCallback>& callback, bool* return_value) {
  // 将传入的参数callback保存到callbacks_中
  callbacks_.emplace_back(callback);

  auto binder_wrapper = android::BinderWrapper::Get();
  binder_wrapper->RegisterForDeathNotifications(
      IUpdateEngineCallback::asBinder(callback),
      base::Bind(&BinderUpdateEngineAndroidService::UnbindCallback,
                 base::Unretained(this),
                 base::Unretained(callback.get())));

  // Send an status update on connection (except when no update sent so far),
  // since the status update is oneway and we don't need to wait for the
  // response.
  if (last_status_ != -1)
    callback->onStatusUpdate(last_status_, last_progress_);

  *return_value = true;
  return Status::ok();
}
```
代码扯得有点远了，云里雾里的，我们以Android自带的demo应用`update_engine_client_android`看看到底是怎么回事。

在文件`update_engine_client_android.cc`中，以`BnUpdateEngineCallback`为基类定义了一个`UECallback`类，这个类只有两个函数`onStatusUpdate`和`onPayloadApplicationComplete`：
```
  class UECallback : public android::os::BnUpdateEngineCallback {
   public:
    explicit UECallback(UpdateEngineClientAndroid* client) : client_(client) {}

    // android::os::BnUpdateEngineCallback overrides.
    Status onStatusUpdate(int status_code, float progress) override;
    Status onPayloadApplicationComplete(int error_code) override;

   private:
    UpdateEngineClientAndroid* client_;
  };
```

函数的详细实现如下：
```
Status UpdateEngineClientAndroid::UECallback::onStatusUpdate(
    int status_code, float progress) {
  update_engine::UpdateStatus status =
      static_cast<update_engine::UpdateStatus>(status_code);
  LOG(INFO) << "onStatusUpdate(" << UpdateStatusToString(status) << " ("
            << status_code << "), " << progress << ")";
  return Status::ok();
}

Status UpdateEngineClientAndroid::UECallback::onPayloadApplicationComplete(
    int error_code) {
  ErrorCode code = static_cast<ErrorCode>(error_code);
  LOG(INFO) << "onPayloadApplicationComplete(" << utils::ErrorCodeToString(code)
            << " (" << error_code << "))";
  client_->ExitWhenIdle(code == ErrorCode::kSuccess ? EX_OK : 1);
  return Status::ok();
}
```

这两个函数本身比较简单，通过打印的方式输出状态信息。

然后在`OnInit()`函数的`bind`操作时生成回调对象`callback_`并向服务端注册进行注册，如下：
```
int UpdateEngineClientAndroid::OnInit() {
  ...

  android::status_t status = android::getService(
      android::String16("android.os.UpdateEngineService"), &service_);
  if (status != android::OK) {
    LOG(ERROR) << "Failed to get IUpdateEngine binder from service manager: "
               << Status::fromStatusT(status).toString8();
    return ExitWhenIdle(1);
  }

  ...

  if (FLAGS_follow) {
    // 创建包含onStatusUpdate和onPayloadApplicationComplete实现的回调对象callback_
    // Register a callback object with the service.
    callback_ = new UECallback(this);
    bool bound;
    // 调用bind，向"android.os.UpdateEngineService"服务注册回调对象callback_
    if (!service_->bind(callback_, &bound).isOk() || !bound) {
      LOG(ERROR) << "Failed to bind() the UpdateEngine daemon.";
      return 1;
    }
    keep_running = true;
  }

  ...

  return EX_OK;
}
```
在执行bind操作时，服务端函数`BinderUpdateEngineAndroidService::bind(...)`会接收到传入的`callback_`，并被保存在`binder_service_`的`callbacks_`中。相应地，服务端`binder_service_`对象中的`callbacks_`就是这里客户端定义的回调函数类对应的模板对象。

所以服务端`callback->onStatusUpdate`和`callback->onPayloadApplicationComplete`分别是客户端实现的`UECallback::onStatusUpdate`和`UECallback::onPayloadApplicationComplete`函数。

## 4. 总结

总结一下:

服务端进程(代码`main.cc`)在main函数中先解析命令行参数并进行简单初始化，随后创建`update_engine_daemon`对象，并调用对象的`Run()`方法进入服务等待状态。

在`Run()`中进入主循环前，通过`OnInit()`初始化生成两个业务对象`binder_service_`和`daemon_state_`，前者负责binder服务对外的工作，后者则负责后台的实际业务。

`binder_service_`在客户端调用`bind`操作时会保存客户端注册的回调函数，从而在适当的时候通过回调函数告知客户端升级的状态信息；同时`binder_service_`接收到客户端的服务请求后，将其交给`daemon_state_`的成员`update_attempter_`去完成，所以`update_attempter_`才是Update Engine服务端业务的核心。

可以看到，目前基本上所有调用最后都会转到`update_attempter_`中，代码分析都在涉及到`update_attempter_`的操作时停止。所以`update_attempter_`是Update Engine服务端的核心对象，代码比较复杂，我们另外开篇分析。

## 5. 联系和福利


- 个人微信公众号“洛奇看世界”，一个大龄码农的救赎之路。
  - 公众号回复关键词“Android电子书”，获取超过150本Android相关的电子书和文档。电子书包含了Android开发相关的方方面面，从此你再也不需要到处找Android开发的电子书了。
  - 公众号回复关键词“个人微信”，获取个人微信联系方式。<font color="red">我组建了一个Android OTA的讨论组，联系我，说明Android OTA，拉你进组一起讨论。</font>

  ![image](https://img-blog.csdn.net/20180507223120679)

# 服务端deamon进程update_engine

Android Update Engine的daemon进程自身的代码只有一个main.cc，剩余的都是对各种库的依赖，以下列举服务端守护进程`update_engine`和Update Engine相关库和文件的依赖关系：

服务端守护进程`update_engine`:

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

libupdate_engine_android
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

服务端守护进程`update_engine`依赖Update Engine相关的库包括：
- `libupdate_engine_android`
- `libpayload_consumer`
- `update_metadata-protos`

除了Update Engine相关的静态库外，其还依赖一些其他公共的静态和动态库，这里略去不表。

具体分析从daemon进程的main函数开始：

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

整个main函数比较简单：
1. 定义参数格式并进行解析；
2. 初始化CRC-32 table；
3. 生成`update_engine_daemon`，并调用其Run()方法；

## 1. 定义参数格式并进行解析
通过`DEFINE_bool`宏定义了两个参数logtostderr, foreground，展开后得到两个变量`FLAGS_logtostderr`和`FLAGS_foreground`。
其中， `FLAGS_logtostderr`用于设置日志输出重定向；`FLAGS_foreground`用于指定update_engine线程是否以forground方式运行。
```
  DEFINE_bool(logtostderr, false,
              "Write logs to stderr instead of to a file in log_dir.");
  DEFINE_bool(foreground, false,
              "Don't daemon()ize; run in foreground.");

  chromeos_update_engine::Terminator::Init();
  brillo::FlagHelper::Init(argc, argv, "Chromium OS Update Engine");
  chromeos_update_engine::SetupLogging(FLAGS_logtostderr);
  if (!FLAGS_foreground)
    PLOG_IF(FATAL, daemon(0, 0) == 1) << "daemon() failed";
```

## 2. 初始化CRC-32 table

```
  LOG(INFO) << "Chrome OS Update Engine starting";

  // xz-embedded requires to initialize its CRC-32 table once on startup.
  xz_crc32_init();
```

这段代码不解释

## 3. 生成`update_engine_daemon`，并调用其Run()方法

```
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
```

`update_engine_daemon`是`update_engine`的核心。
`update_engine`跟客户端进程`update_engine_client`一样，都是派生于`brillo::Daemon`类，所以这里会执行父类`brillo::Daemon`的Run()方法。
实现上：
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
2. 初始化完成后调用brillo_message_loop_.Run()进入消息循环处理模式
3. 调用OnShutdown
4. 进入while循环等待退出消息

总体上，整个进程的结构比较简单，就是基于`brillo::Daemon`类的结构，进行初始化，启动`brilllo::MessageLoop`机制进行消息循环处理直到退出。

下面逐个来看这4个操作。

## `UpdateEngineDaemon::OnInit()`函数分析

执行OnInit函数进行初始化时，由于`int Daemon::OnInit()`定义为虚函数，所以这里执行的是其子类`UpdateEngineDaemon`的`OnInit`函数，这个才是真正的初始化函数。
```
// file: system\update_engine\daemon.cc

int UpdateEngineDaemon::OnInit() {
  // Register the |subprocess_| singleton with this Daemon as the signal
  // handler.
  subprocess_.Init(this);

  // 调用父类DAemon的OnInit()方法，注册信号：SIGTERM, SIGINT, SIGHUP的处理函数
  int exit_code = Daemon::OnInit();
  if (exit_code != EX_OK)
    return exit_code;

  // Android.mk中分析过USE_WEAVE=0, USE_BINDER=1
#if USE_WEAVE || USE_BINDER
  android::BinderWrapper::Create();
  binder_watcher_.Init();
#endif  // USE_WEAVE || USE_BINDER

  // Android.mk中分析过，这里USE_DBUS=0, 略过
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

#if USE_BINDER
  // Create the Binder Service.
#if defined(__BRILLO__) || defined(__CHROMEOS__)
  binder_service_ = new BinderUpdateEngineBrilloService{real_system_state};
#else  // !(defined(__BRILLO__) || defined(__CHROMEOS__))
  binder_service_ = new BinderUpdateEngineAndroidService{
      daemon_state_android->service_delegate()};
#endif  // defined(__BRILLO__) || defined(__CHROMEOS__)
  auto binder_wrapper = android::BinderWrapper::Get();
  if (!binder_wrapper->RegisterService(binder_service_->ServiceName(),
                                       binder_service_)) {
    LOG(ERROR) << "Failed to register binder service.";
  }

  daemon_state_->AddObserver(binder_service_.get());
#endif  // USE_BINDER

#if USE_DBUS
  // Create the DBus service.
  dbus_adaptor_.reset(new UpdateEngineAdaptor(real_system_state, bus));
  daemon_state_->AddObserver(dbus_adaptor_.get());

  dbus_adaptor_->RegisterAsync(base::Bind(&UpdateEngineDaemon::OnDBusRegistered,
                                          base::Unretained(this)));
  LOG(INFO) << "Waiting for DBus object to be registered.";
#else  // !USE_DBUS
  daemon_state_->StartUpdater();
#endif  // USE_DBUS
  return EX_OK;
}

```

headers:
```
FILE_HASH=ozGgyQEcnkI5ZaX+Wbjo5I/PCR7PEZka9fGd0nWa+oY=
FILE_SIZE=282164983
METADATA_HASH=GLIKfE6KRwylWMHsNadG/Q8iy5f7ENWTatvMdBlpoPg=
METADATA_SIZE=21023
```
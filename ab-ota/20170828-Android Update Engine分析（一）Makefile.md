# Android Update Engine分析（一）Makefile

写完《Android AB System OTA分析》系列后打算一口气将Update Engine也写了的，但一直由于各种借口，最终没有完成。后来6月份的时候陆陆续续读了Update Engine部分代码，记了点笔记，本打算等彻底读完再分享的，但按照目前的进度不知道读完是哪一天，所以先将笔记贴在这里，如果我的这几篇笔记能对您阅读或理解Update Engine机制有一丝帮助，那花时间整理也是值得的，由于个人水平有限，如果发现错误，恳请指出，我会更正以免误导别人。

> 技术文章直入主题，展示结论，容易让人知其然，不知其所以然。</br>
> 我个人更喜欢在文章中展示如何阅读代码，逐步分析解决问题的思路和过程。这样的思考比知道结论更重要，希望我的分析能让你有所收获。

> 这篇文章最初发布于2017年8月份，最近打算完成整个Update Engine分析系列，因此在2018年6月中对本文做了一些更新。
> 更新主要包括：
> - 从代码确定宏BRILLO没有定义
> - 从编译结果确认宏BRILLO没有定义
> - `libupdate_engine_client`与非BRILLO平台无关
> - 缩减代码分析范围，确认那些代码参与编译

《Android A/B System OTA分析》主要从功能上分析A/B系统的特点、设置和操作，Update Engine分析深入A/B系统的底层实现，所以相对于前者，需要更加深入代码。

> 本文涉及的Android代码版本：android‐7.1.1_r23 (NMF27D)

## 0. Update Engine代码统计

Android Update Engine模块涉及的代码较多，这里主要以`system/update_engine`目录的代码为主，其它部分代码会编译为库的形式供`system/update_engine`下的代码调用。
如果只看`update_engine`目录，用`find`命令统计下：
```
ygu@stbszx-bld-5:/public/android/src/system/update_engine$ find . -type f | wc -l
416
ygu@stbszx-bld-5:/public/android/src/system/update_engine$ find . -type f -iname '*.cc' | wc -l  
186
```
这个目录下共有416个文件，除去makefile，资源文件，头文件等，仅`.cc`后缀的文件就有186个，虽然少了一大半，但是面对这么多文件从哪里着手，显然也是个问题。

分析复杂的代码，makefile是最好的入手点，分析makefile的好处有很多，最主要一条是对项目的组织结构有一个大方向的认识，代码入口点在哪里，由哪些模块构成，哪些模块有依赖关系，预定义了哪些条件编译的宏，哪些宏定义会传入到代码中等。分析整个Android工程如此，分析Update Engine模块也是如此。

对于Update Engine模块的makefile文件`system/update_engine/Android.mk`，初一看比较复杂。首先Android.mk里面定义的模块很多，各种模块加起来20+个，模块之间还有前后依赖；其次，Android.mk文件开始定义了一些需要求值的makefile变量，并根据变量的取值进行条件编译使得Makefile看起来更加复杂。如果先整理好条件变量的设置，再进行下一步的分析会比较简单。

## 1. `Android.mk`代码逐行分析

以下对`system/update_engine/Androi.mk`文件进行逐行分析。
这里分析makefile的主要目的是理清各模块的编译涉及的文件和模块间的关系，对于模块具体是如何编译的并不关心，具体的编译在单个模块分析时再深入介绍。所以这里的任务比较简单，分析也比较粗略，

### 第1~15行
版权申明，这里略过。

### 第16~68行

```
...

LOCAL_PATH := $(my-dir)

# Default values for the USE flags. Override these USE flags from your product
# by setting BRILLO_USE_* values. Note that we define local variables like
# local_use_* to prevent leaking our default setting for other packages.
local_use_binder := $(if $(BRILLO_USE_BINDER),$(BRILLO_USE_BINDER),1)
local_use_dbus := $(if $(BRILLO_USE_DBUS),$(BRILLO_USE_DBUS),0)
local_use_hwid_override := \
    $(if $(BRILLO_USE_HWID_OVERRIDE),$(BRILLO_USE_HWID_OVERRIDE),0)
# "libcros" gates the LibCrosService exposed by the Chrome OS' chrome browser to
# the system layer.
local_use_libcros := $(if $(BRILLO_USE_LIBCROS),$(BRILLO_USE_LIBCROS),0)
local_use_mtd := $(if $(BRILLO_USE_MTD),$(BRILLO_USE_MTD),0)
local_use_power_management := \
    $(if $(BRILLO_USE_POWER_MANAGEMENT),$(BRILLO_USE_POWER_MANAGEMENT),0)
local_use_weave := $(if $(BRILLO_USE_WEAVE),$(BRILLO_USE_WEAVE),0)

ue_common_cflags := \
    -DUSE_BINDER=$(local_use_binder) \
    -DUSE_DBUS=$(local_use_dbus) \
    -DUSE_HWID_OVERRIDE=$(local_use_hwid_override) \
    -DUSE_LIBCROS=$(local_use_libcros) \
    -DUSE_MTD=$(local_use_mtd) \
    -DUSE_POWER_MANAGEMENT=$(local_use_power_management) \
    -DUSE_WEAVE=$(local_use_weave) \
    -D_FILE_OFFSET_BITS=64 \
    -D_POSIX_C_SOURCE=199309L \
    -Wa,--noexecstack \
    -Wall \
    -Werror \
    -Wextra \
    -Wformat=2 \
    -Wno-psabi \
    -Wno-unused-parameter \
    -ffunction-sections \
    -fstack-protector-strong \
    -fvisibility=hidden
ue_common_cppflags := \
    -Wnon-virtual-dtor \
    -fno-strict-aliasing \
    -std=gnu++11
ue_common_ldflags := \
    -Wl,--gc-sections
ue_common_c_includes := \
    $(LOCAL_PATH)/client_library/include \
    external/gtest/include \
    system
ue_common_shared_libraries := \
    libbrillo-stream \
    libbrillo \
    libchrome

```

总体上看，上面的代码定义了以下两类模块相关的变量：

- 逻辑控制类，标识是否需要相应模块，用于条件编译
  ```
  local_use_binder, 
  local_use_dbus, 
  local_use_hwid_override, 
  local_use_libcros, 
  local_use_mtd, 
  local_use_power_management, 
  local_use_weave
  ```

- 编译参数类，存储cflags/cppflags/ldflags等参数，传递给工具链进行编译和连接
  ```
  ue_common_cflags, 
  ue_common_cppflags, 
  ue_common_ldflags, 
  ue_common_c_includes, 
  ue_common_shared_libraries
  ```

> 在定义逻辑控制类变量时，代码中大量使用了makefile的if函数。还记得if函数吗？
>
> if 函数语法如下：
>```
>$(if CONDITION,THEN-PART[,ELSE-PART])
>```
>对于参数“CONDITION”，在函数执行时忽略其前导和结尾空字符并展开：
>  - 如果展开结果非空，则条件为真，就将第二个参数“THEN_PATR”作为函数的计算表达式，函数的返回值就是“THEN-PART”的计算结果；
>  - 如果展开结果为空，将第三个参数“ELSE-PART”作为函数的表达式，返回结果为表达式“ELSE-PART”的计算结果。
>
> 详细的`if`函数，可以参考make手册：[GNU Make](https://www.gnu.org/software/make/manual/make.pdf)

这里分别检查以下变量是否定义：
  - `BRILLO_USE_BINDER`
  - `BRILLO_USE_DBUS`
  - `BRILLO_USE_HWID_OVERRIDE`
  - `BRILLO_USE_LIBCROS`
  - `BRILLO_USE_MTD`
  - `BRILLO_USE_POWER_MANAGEMENT`
  - `BRILLO_USE_WEAVE`

我完全不记得也不知道哪里有定义过这些变量了，如果你跟我一样不记得或不知道，没关系，那就在代码根目录下用`grep`命令找找吧：
```
$ grep -rn "BRILLO_USE_" . --exclude-dir=out
./system/update_engine/Android.mk:20:# by setting BRILLO_USE_* values. Note that we define local variables like
./system/update_engine/Android.mk:22:local_use_binder := $(if $(BRILLO_USE_BINDER),$(BRILLO_USE_BINDER),1)
./system/update_engine/Android.mk:23:local_use_dbus := $(if $(BRILLO_USE_DBUS),$(BRILLO_USE_DBUS),0)
./system/update_engine/Android.mk:25:    $(if $(BRILLO_USE_HWID_OVERRIDE),$(BRILLO_USE_HWID_OVERRIDE),0)
./system/update_engine/Android.mk:28:local_use_libcros := $(if $(BRILLO_USE_LIBCROS),$(BRILLO_USE_LIBCROS),0)
./system/update_engine/Android.mk:29:local_use_mtd := $(if $(BRILLO_USE_MTD),$(BRILLO_USE_MTD),0)
./system/update_engine/Android.mk:31:    $(if $(BRILLO_USE_POWER_MANAGEMENT),$(BRILLO_USE_POWER_MANAGEMENT),0)
./system/update_engine/Android.mk:32:local_use_weave := $(if $(BRILLO_USE_WEAVE),$(BRILLO_USE_WEAVE),0)
./external/libbrillo/Android.mk:16:# by setting BRILLO_USE_* values. Note that we define local variables like
./external/libbrillo/Android.mk:18:local_use_dbus := $(if $(BRILLO_USE_DBUS),$(BRILLO_USE_DBUS),1)
./external/libchrome/Android.mk:16:# by setting BRILLO_USE_* values. Note that we define local variables like
./external/libchrome/Android.mk:18:local_use_dbus := $(if $(BRILLO_USE_DBUS),$(BRILLO_USE_DBUS),1)
```

根据搜索结果，在我目前工程中，一共在3个文件中出现过`BRILLO_USE_xxx`变量，但这些地方都是对变量的引用而非设置。因此，可以肯定这些`BRILLO_USE_xxx`都未定义，其引用为空，进一步可以得到所有逻辑控制类变量都是取if函数的"[ELSE-PART]"的值，例如:
```
local_use_binder := $(if $(BRILLO_USE_BINDER),$(BRILLO_USE_BINDER),1)
```
由于`if`的`CONDITION`中`$(BRILLO_USE_BINDER)`变量没有定义，所以取值为空，`local_use_binder`的取值是if函数的`ELSE-PART`部分，即1。

因此，上面所有变量取值如下：

```
local_use_binder = 1,
local_use_dbus = 0,
local_use_hwid_override = 0, 
local_use_libcros = 0, 
local_use_mtd = 0, 
local_use_power_management = 0, 
local_use_weave = 0
```

拿到了这些控制变量的值，剩下的事情就简单多了。

对于编译参数类变量 `ue_common_{cflags, cppflags, ldflags, c_includes, shared_libraries}`，在具体的模块编译时会将其传递给编译器或链接器，这里不再展开分析。
  
### 第69~82行
```
#依赖于local_use_dbus的条件编译，如果定义了BRILLO_USE_DBUS，则进程间基于DBUS机制进行通信
ifeq ($(local_use_dbus),1)

# update_engine_client-dbus-proxies (from generate-dbus-proxies.gypi)
# ========================================================
include $(CLEAR_VARS)
LOCAL_MODULE := update_engine_client-dbus-proxies
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_SRC_FILES := \
    dbus_bindings/dbus-service-config.json \
    dbus_bindings/org.chromium.UpdateEngineInterface.dbus-xml
LOCAL_DBUS_PROXY_PREFIX := update_engine
include $(BUILD_STATIC_LIBRARY)

endif  # local_use_dbus == 1
```
由于"`local_use_debus=0`"，显然这里不会包含这个模块，不需要关心模块`update_engine_client-dbus-proxies`。

### 第83~112行

```

# update_metadata-protos (type: static_library)
# ========================================================
# Protobufs.
ue_update_metadata_protos_exported_static_libraries := \
    update_metadata-protos
ue_update_metadata_protos_exported_shared_libraries := \
    libprotobuf-cpp-lite

ue_update_metadata_protos_src_files := \
    update_metadata.proto

# Build for the host.
include $(CLEAR_VARS)
LOCAL_MODULE := update_metadata-protos
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_IS_HOST_MODULE := true
generated_sources_dir := $(call local-generated-sources-dir)
LOCAL_EXPORT_C_INCLUDE_DIRS := $(generated_sources_dir)/proto/system
LOCAL_SRC_FILES := $(ue_update_metadata_protos_src_files)
include $(BUILD_HOST_STATIC_LIBRARY)

# Build for the target.
include $(CLEAR_VARS)
LOCAL_MODULE := update_metadata-protos
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
generated_sources_dir := $(call local-generated-sources-dir)
LOCAL_EXPORT_C_INCLUDE_DIRS := $(generated_sources_dir)/proto/system
LOCAL_SRC_FILES := $(ue_update_metadata_protos_src_files)
include $(BUILD_STATIC_LIBRARY)
```
以上代码定义了静态库模块`update_metadata-protos`，分别用于host和target环境。

### 第114~136行
```
ifeq ($(local_use_dbus),1)

# update_engine-dbus-adaptor (from generate-dbus-adaptors.gypi)
# ========================================================
# Chrome D-Bus bindings.
include $(CLEAR_VARS)
LOCAL_MODULE := update_engine-dbus-adaptor
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_SRC_FILES := \
    dbus_bindings/org.chromium.UpdateEngineInterface.dbus-xml
include $(BUILD_STATIC_LIBRARY)

# update_engine-dbus-libcros-client (from generate-dbus-proxies.gypi)
# ========================================================
include $(CLEAR_VARS)
LOCAL_MODULE := update_engine-dbus-libcros-client
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_SRC_FILES := \
    dbus_bindings/org.chromium.LibCrosService.dbus-xml
LOCAL_DBUS_PROXY_PREFIX := libcros
include $(BUILD_STATIC_LIBRARY)

endif  # local_use_dbus == 1
```
由于"`local_use_dbus=0`"，所以这里的模块也不用管了。

### 第137~227行

```
# libpayload_consumer (type: static_library)
# ========================================================
# The payload application component and common dependencies.
ue_libpayload_consumer_exported_static_libraries := \
    update_metadata-protos \
    libxz-host \
    libbz \
    $(ue_update_metadata_protos_exported_static_libraries)
ue_libpayload_consumer_exported_shared_libraries := \
    libcrypto-host \
    $(ue_update_metadata_protos_exported_shared_libraries)

ue_libpayload_consumer_src_files := \
    common/action_processor.cc \
    common/boot_control_stub.cc \
    common/clock.cc \
    common/constants.cc \
    common/cpu_limiter.cc \
    common/error_code_utils.cc \
    common/hash_calculator.cc \
    common/http_common.cc \
    common/http_fetcher.cc \
    common/file_fetcher.cc \
    common/hwid_override.cc \
    common/multi_range_http_fetcher.cc \
    common/platform_constants_android.cc \
    common/prefs.cc \
    common/subprocess.cc \
    common/terminator.cc \
    common/utils.cc \
    payload_consumer/bzip_extent_writer.cc \
    payload_consumer/delta_performer.cc \
    payload_consumer/download_action.cc \
    payload_consumer/extent_writer.cc \
    payload_consumer/file_descriptor.cc \
    payload_consumer/file_writer.cc \
    payload_consumer/filesystem_verifier_action.cc \
    payload_consumer/install_plan.cc \
    payload_consumer/payload_constants.cc \
    payload_consumer/payload_verifier.cc \
    payload_consumer/postinstall_runner_action.cc \
    payload_consumer/xz_extent_writer.cc

ifeq ($(HOST_OS),linux)
# Build for the host.
include $(CLEAR_VARS)
LOCAL_MODULE := libpayload_consumer
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes) \
    external/e2fsprogs/lib
LOCAL_STATIC_LIBRARIES := \
    update_metadata-protos \
    $(ue_libpayload_consumer_exported_static_libraries) \
    $(ue_update_metadata_protos_exported_static_libraries)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libpayload_consumer_exported_shared_libraries) \
    $(ue_update_metadata_protos_exported_shared_libraries)
LOCAL_SRC_FILES := $(ue_libpayload_consumer_src_files)
include $(BUILD_HOST_STATIC_LIBRARY)
endif  # HOST_OS == linux

# Build for the target.
include $(CLEAR_VARS)
LOCAL_MODULE := libpayload_consumer
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes) \
    external/e2fsprogs/lib
LOCAL_STATIC_LIBRARIES := \
    update_metadata-protos \
    $(ue_libpayload_consumer_exported_static_libraries:-host=) \
    $(ue_update_metadata_protos_exported_static_libraries)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libpayload_consumer_exported_shared_libraries:-host=) \
    $(ue_update_metadata_protos_exported_shared_libraries)
LOCAL_SRC_FILES := $(ue_libpayload_consumer_src_files)
include $(BUILD_STATIC_LIBRARY)
```

以上代码定义了静态库模块`libpayload_consumer`，分别用于host和target环境。
由于`ue_libpayload_consumer_exported_static_libraries`包含了`update_metadata-protos`，所以明白了为什么需要编译`update_metadata-protos`模块。

### 第228~424行

```
ifdef BRILLO

# libupdate_engine (type: static_library)
# ========================================================
# The main daemon static_library with all the code used to check for updates
# with Omaha and expose a DBus daemon.
ue_libupdate_engine_exported_c_includes := \
    $(LOCAL_PATH)/include \
    external/cros/system_api/dbus
ue_libupdate_engine_exported_static_libraries := \
    libpayload_consumer \
    update_metadata-protos \
    update_engine-dbus-adaptor \
    update_engine-dbus-libcros-client \
    update_engine_client-dbus-proxies \
    libbz \
    libfs_mgr \
    $(ue_libpayload_consumer_exported_static_libraries) \
    $(ue_update_metadata_protos_exported_static_libraries)
ue_libupdate_engine_exported_shared_libraries := \
    libdbus \
    libbrillo-dbus \
    libchrome-dbus \
    libmetrics \
    libshill-client \
    libexpat \
    libbrillo-policy \
    libhardware \
    libcurl \
    libcutils \
    libssl \
    $(ue_libpayload_consumer_exported_shared_libraries) \
    $(ue_update_metadata_protos_exported_shared_libraries)
ifeq ($(local_use_binder),1)
ue_libupdate_engine_exported_shared_libraries += \
    libbinder \
    libbinderwrapper \
    libbrillo-binder \
    libutils
endif  # local_use_binder == 1
ifeq ($(local_use_weave),1)
ue_libupdate_engine_exported_shared_libraries += \
    libbinderwrapper \
    libbrillo-binder \
    libweaved
endif  # local_use_weave == 1

include $(CLEAR_VARS)
LOCAL_MODULE := libupdate_engine
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_EXPORT_C_INCLUDE_DIRS := $(ue_libupdate_engine_exported_c_includes)
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes) \
    $(ue_libupdate_engine_exported_c_includes) \
    bootable/recovery
LOCAL_STATIC_LIBRARIES := \
    libpayload_consumer \
    update_metadata-protos \
    update_engine-dbus-adaptor \
    update_engine-dbus-libcros-client \
    update_engine_client-dbus-proxies \
    $(ue_libupdate_engine_exported_static_libraries:-host=) \
    $(ue_libpayload_consumer_exported_static_libraries:-host=) \
    $(ue_update_metadata_protos_exported_static_libraries)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libupdate_engine_exported_shared_libraries:-host=) \
    $(ue_libpayload_consumer_exported_shared_libraries:-host=) \
    $(ue_update_metadata_protos_exported_shared_libraries)
LOCAL_SRC_FILES := \
    boot_control_android.cc \
    certificate_checker.cc \
    common_service.cc \
    connection_manager.cc \
    daemon.cc \
    dbus_service.cc \
    hardware_android.cc \
    image_properties_android.cc \
    libcros_proxy.cc \
    libcurl_http_fetcher.cc \
    metrics.cc \
    metrics_utils.cc \
    omaha_request_action.cc \
    omaha_request_params.cc \
    omaha_response_handler_action.cc \
    p2p_manager.cc \
    payload_state.cc \
    proxy_resolver.cc \
    real_system_state.cc \
    shill_proxy.cc \
    update_attempter.cc \
    update_manager/boxed_value.cc \
    update_manager/chromeos_policy.cc \
    update_manager/default_policy.cc \
    update_manager/evaluation_context.cc \
    update_manager/policy.cc \
    update_manager/real_config_provider.cc \
    update_manager/real_device_policy_provider.cc \
    update_manager/real_random_provider.cc \
    update_manager/real_shill_provider.cc \
    update_manager/real_system_provider.cc \
    update_manager/real_time_provider.cc \
    update_manager/real_updater_provider.cc \
    update_manager/state_factory.cc \
    update_manager/update_manager.cc \
    update_status_utils.cc \
    utils_android.cc \
    weave_service_factory.cc
ifeq ($(local_use_binder),1)
LOCAL_AIDL_INCLUDES += $(LOCAL_PATH)/binder_bindings
LOCAL_SRC_FILES += \
    binder_bindings/android/brillo/IUpdateEngine.aidl \
    binder_bindings/android/brillo/IUpdateEngineStatusCallback.aidl \
    binder_service_brillo.cc \
    parcelable_update_engine_status.cc
endif  # local_use_binder == 1
ifeq ($(local_use_weave),1)
LOCAL_SRC_FILES += \
    weave_service.cc
endif  # local_use_weave == 1
ifeq ($(local_use_libcros),1)
LOCAL_SRC_FILES += \
    chrome_browser_proxy_resolver.cc
endif  # local_use_libcros == 1
include $(BUILD_STATIC_LIBRARY)

else  # !defined(BRILLO)
...
```
以上if-else中间的代码定义了BRILLO平台上的`libupdate_engine`库模块，由于我们是非BRILLO平台，但并不需要我们去关心。不管里面是神马，写了神马，定义了神马，`we don't care`。

> 2018/06/13补充，关于BRILLO宏没有定义是如何确认的？如果对这部分不感兴趣，请直接跳过这里的分析。
>
> 有人可能会问：我怎么知道当前BRILLO平台有没有定义呢? 
>
> 没关系，同前面搜索`"BRILLO_USE_*"`宏一样，可以尝试在代码里面搜索下所有可能的BRILLO定义，个人觉得定义BRILLO最可能的地方是build和device以及system目录。如果不放心，为了保险起见，我们可以搜索除了out目录以外的所有android代码。当然，在整个android源码中搜索BRILLO字符串，可能需要花点时间。
> 
> 注意，在整个代码中包含BRILLO的字符串的地方特别多，所以需要进一步精确搜索，可能的办法有：
> 1. 搜索非代码文件；
> 2. 搜索精确匹配"BRILLO"的字符串；
> 
> 以下是我在Android源码中除`{.h, .c, .cc, .cpp, .py}`文件中搜索"BRILLO"的结果，有点长，不喜欢的可以跳过。
> ```
> src$ grep -rn "BRILLO" --exclude-dir=out --exclude=*.h --exclude=*.c --exclude=*.cc --exclude=*.cpp --exclude=*.py                                           
> frameworks/wilhelm/src/Android.mk:197:ifndef BRILLO
> bionic/libc/Android.mk:1415:ifdef BRILLO
> system/core/metricsd/Android.mk:202:ifdef BRILLO
> system/core/metricsd/Android.mk:220:ifdef BRILLO
> system/core/crash_reporter/Android.mk:103:# Optionally populate the BRILLO_CRASH_SERVER variable from a product
> system/core/crash_reporter/Android.mk:105:LOADED_BRILLO_CRASH_SERVER := $(call cfgtree-get-if-exists,brillo/crash_server)
> system/core/crash_reporter/Android.mk:109:$(LOCAL_BUILT_MODULE): BRILLO_CRASH_SERVER ?= "$(LOADED_BRILLO_CRASH_SERVER)"
> system/core/crash_reporter/Android.mk:112:      echo $(BRILLO_CRASH_SERVER) > $@
> system/core/crash_reporter/Android.mk:138:ifdef BRILLO
> system/core/crash_reporter/README.md:42:- The `BRILLO_CRASH_SERVER` make variable should be set in the `product.mk`
> system/core/crash_reporter/README.md:47:- The `BRILLO_PRODUCT_ID` make variable should be set in the `product.mk` file
> system/core/crash_reporter/crash_sender:20:BRILLO_PRODUCT=Brillo
> system/core/crash_reporter/crash_sender:386:    product="${BRILLO_PRODUCT}"
> system/core/crash_reporter/crash_sender:416:  if [ "${product}" != "${BRILLO_PRODUCT}" ]; then
> system/extras/brillo_config/Android.mk:28:LOADED_BRILLO_PRODUCT_ID := $(call cfgtree-get-if-exists,brillo/product_id)
> system/extras/brillo_config/Android.mk:32:$(LOCAL_BUILT_MODULE): BRILLO_PRODUCT_ID ?= "$(LOADED_BRILLO_PRODUCT_ID)"
> system/extras/brillo_config/Android.mk:35:      echo $(BRILLO_PRODUCT_ID) > $@
> system/extras/brillo_config/Android.mk:47:ifeq ($(BRILLO_PRODUCT_VERSION),)
> system/extras/brillo_config/Android.mk:49:BRILLO_PRODUCT_VERSION := $(call cfgtree-get-if-exists,brillo/product_version)
> system/extras/brillo_config/Android.mk:52:ifeq ($(BRILLO_PRODUCT_VERSION),)
> system/extras/brillo_config/Android.mk:53:BRILLO_PRODUCT_VERSION := "0.0.0"
> system/extras/brillo_config/Android.mk:55:ifeq ($(shell echo $(BRILLO_PRODUCT_VERSION) | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$$'),)
> system/extras/brillo_config/Android.mk:56:$(error Invalid BRILLO_PRODUCT_VERSION "$(BRILLO_PRODUCT_VERSION)", must be \
> system/extras/brillo_config/Android.mk:68:      echo $(BRILLO_PRODUCT_VERSION).$(BUILD_NUMBER) > $@
> system/extras/brillo_config/Android.mk:70:      echo $(BRILLO_PRODUCT_VERSION).$(BUILD_DATETIME) > $@
> system/nativepower/daemon/Android.mk:94:ifdef BRILLO
> system/nativepower/client/Android.mk:51:ifdef BRILLO
> system/tools/aidl/Android.mk:23:ifdef BRILLO
> system/tools/aidl/Android.mk:181:ifndef BRILLO
> system/tools/aidl/Android.mk:201:endif  # not defined BRILLO
> system/firewalld/Android.mk:70:ifdef BRILLO
> system/weaved/Android.mk:57:ifdef BRILLO
> system/weaved/Android.mk:122:ifdef BRILLO
> system/webservd/test-client/Android.mk:26:ifdef BRILLO
> system/webservd/webservd/Android.mk:32:ifdef BRILLO
> system/webservd/webservd/Android.mk:57:ifdef BRILLO
> system/update_engine/Android.mk:20:# by setting BRILLO_USE_* values. Note that we define local variables like
> system/update_engine/Android.mk:22:local_use_binder := $(if $(BRILLO_USE_BINDER),$(BRILLO_USE_BINDER),1)
> system/update_engine/Android.mk:23:local_use_dbus := $(if $(BRILLO_USE_DBUS),$(BRILLO_USE_DBUS),0)
> system/update_engine/Android.mk:25:    $(if $(BRILLO_USE_HWID_OVERRIDE),$(BRILLO_USE_HWID_OVERRIDE),0)
> system/update_engine/Android.mk:28:local_use_libcros := $(if $(BRILLO_USE_LIBCROS),$(BRILLO_USE_LIBCROS),0)
> system/update_engine/Android.mk:29:local_use_mtd := $(if $(BRILLO_USE_MTD),$(BRILLO_USE_MTD),0)
> system/update_engine/Android.mk:31:    $(if $(BRILLO_USE_POWER_MANAGEMENT),$(BRILLO_USE_POWER_MANAGEMENT),0)
> system/update_engine/Android.mk:32:local_use_weave := $(if $(BRILLO_USE_WEAVE),$(BRILLO_USE_WEAVE),0)
> system/update_engine/Android.mk:229:ifdef BRILLO
> system/update_engine/Android.mk:360:else  # !defined(BRILLO)
> system/update_engine/Android.mk:424:endif  # !defined(BRILLO)
> system/update_engine/Android.mk:450:ifdef BRILLO
> system/update_engine/Android.mk:458:else  # !defined(BRILLO)
> system/update_engine/Android.mk:464:endif  # !defined(BRILLO)
> system/update_engine/Android.mk:601:ifdef BRILLO
> system/update_engine/Android.mk:607:else  # !defined(BRILLO)
> system/update_engine/Android.mk:624:endif  # !defined(BRILLO)
> system/update_engine/Android.mk:770:ifdef BRILLO
> system/update_engine/Android.mk:782:    $(eval $(ifeq $(BRILLO), 1, LOCAL_MODULE_TAGS := eng)) \
> system/update_engine/Android.mk:792:    $(eval $(ifeq $(BRILLO), 1, LOCAL_MODULE_TAGS := eng)) \
> system/update_engine/Android.mk:814:    $(eval $(ifeq $(BRILLO), 1, LOCAL_MODULE_TAGS := eng)) \
> system/update_engine/Android.mk:843:ifdef BRILLO
> system/update_engine/Android.mk:865:ifdef BRILLO
> system/update_engine/Android.mk:976:endif  # BRILLO
> system/update_engine/Android.mk:989:ifdef BRILLO
> system/update_engine/Android.mk:998:endif  # BRILLO
> system/connectivity/shill/Android.mk:352:ifdef BRILLO
> system/connectivity/shill/Android.mk:356:endif # BRILLO
> system/connectivity/shill/Android.mk:378:ifdef BRILLO
> system/connectivity/shill/Android.mk:381:endif # BRILLO
> system/connectivity/shill/Android.mk:394:ifdef BRILLO
> system/connectivity/shill/Android.mk:396:endif # BRILLO
> system/connectivity/shill/Android.mk:613:ifdef BRILLO
> system/connectivity/shill/Android.mk:615:endif # BRILLO
> system/connectivity/apmanager/Android.mk:106:ifdef BRILLO
> system/connectivity/apmanager/Android.mk:108:endif # BRILLO
> system/tpm/trunks/Android.mk:87:ifeq ($(BRILLOEMULATOR),true)
> system/tpm/trunks/Android.mk:91:ifeq ($(BRILLOEMULATOR),true)
> system/tpm/trunks/Android.mk:102:ifeq ($(BRILLOEMULATOR),true)
> external/minijail/Android.mk:34:ifndef BRILLO
> external/minijail/Android.mk:143:ifdef BRILLO
> external/minijail/Android.mk:167:ifdef BRILLO
> external/minijail/Android.mk:188:ifdef BRILLO
> external/libbrillo/Android.mk:16:# by setting BRILLO_USE_* values. Note that we define local variables like
> external/libbrillo/Android.mk:18:local_use_dbus := $(if $(BRILLO_USE_DBUS),$(BRILLO_USE_DBUS),1)
> external/libbrillo/Android.mk:374:ifdef BRILLO
> external/libchrome/Android.mk:16:# by setting BRILLO_USE_* values. Note that we define local variables like
> external/libchrome/Android.mk:18:local_use_dbus := $(if $(BRILLO_USE_DBUS),$(BRILLO_USE_DBUS),1)
> external/libchrome/Android.mk:566:ifdef BRILLO
> external/libchrome/Android.mk:585:ifdef BRILLO
> external/icu/icu4c/source/common/Android.mk:239:ifndef BRILLO
> external/icu/icu4c/source/common/Android.mk:284:ifndef BRILLO
> device/generic/goldfish-opengl/system/gralloc/Android.mk:26:endif  # defined(BRILLO)
> device/intel/edison/BoardConfig.mk:62:BRILLO_VENDOR_PARTITIONS := \
> device/intel/edison/flash_tools/brillo-flashall-edison.sh:28:    "${BRILLO_OUT_DIR}" \
> build/core/config.mk:771:ifdef BRILLO
> build/core/config.mk:772:# Add a C define that identifies Brillo targets. __BRILLO__ should only be used
> build/core/config.mk:777:TARGET_GLOBAL_CFLAGS += -D__BRILLO__
> build/core/config.mk:779:$(TARGET_2ND_ARCH_VAR_PREFIX)TARGET_GLOBAL_CFLAGS += -D__BRILLO__
> build/core/Makefile:712:ifeq ($(BRILLO),)
> build/core/soong.mk:43: echo '    "Brillo": $(if $(BRILLO),true,false),'; \
> build/soong/cc/cc.go:989:                       flags.GlobalFlags = append(flags.GlobalFlags, "-D__BRILLO__")
> build/tools/signapk/Android.mk:29:ifeq ($(BRILLO),)  
>
> src$ 
> ```
> 这里的搜索结果大约有100条，仔细观察上面的每一条结果，没有任何一个地方是关于“BRILLO”宏定义的，在这一节的后面我们再对“BRILLO没有定义”的结果进行确认。
> 


下面这部分才是非BRILLO平台的`libupdate_engine_android`库：

```

ifneq ($(local_use_binder),1)
$(error USE_BINDER is disabled but is required in non-Brillo devices.)
endif  # local_use_binder == 1

# libupdate_engine_android (type: static_library)
# ========================================================
# The main daemon static_library used in Android (non-Brillo). This only has a
# loop to apply payloads provided by the upper layer via a Binder interface.
ue_libupdate_engine_android_exported_static_libraries := \
    libpayload_consumer \
    libfs_mgr \
    $(ue_libpayload_consumer_exported_static_libraries)
ue_libupdate_engine_android_exported_shared_libraries := \
    $(ue_libpayload_consumer_exported_shared_libraries) \
    libandroid \
    libbinder \
    libbinderwrapper \
    libbrillo-binder \
    libcutils \
    libcurl \
    libhardware \
    libssl \
    libutils

include $(CLEAR_VARS)
LOCAL_MODULE := libupdate_engine_android
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes) \
    bootable/recovery
#TODO(deymo): Remove external/cros/system_api/dbus once the strings are moved
# out of the DBus interface.
LOCAL_C_INCLUDES += \
    external/cros/system_api/dbus
LOCAL_STATIC_LIBRARIES := \
    $(ue_libupdate_engine_android_exported_static_libraries:-host=)
LOCAL_SHARED_LIBRARIES += \
    $(ue_common_shared_libraries) \
    $(ue_libupdate_engine_android_exported_shared_libraries:-host=)
LOCAL_AIDL_INCLUDES := $(LOCAL_PATH)/binder_bindings
LOCAL_SRC_FILES += \
    binder_bindings/android/os/IUpdateEngine.aidl \
    binder_bindings/android/os/IUpdateEngineCallback.aidl \
    binder_service_android.cc \
    boot_control_android.cc \
    certificate_checker.cc \
    daemon.cc \
    daemon_state_android.cc \
    hardware_android.cc \
    libcurl_http_fetcher.cc \
    network_selector_android.cc \
    proxy_resolver.cc \
    update_attempter_android.cc \
    update_status_utils.cc \
    utils_android.cc
include $(BUILD_STATIC_LIBRARY)

endif  # !defined(BRILLO)
```
以上代码定义了target上编译其它模块需要的`libupdate_engine_android`静态库模块。
有一点值得注意的是，其模块的`LOCAL_C_INCLUDES`变量竟然有对传统recovery目录的引用`bootable/recovery`：
```
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes) \
    bootable/recovery
```

> 2018/06/13补充：
>
> 从这一节的分析可见，如果是BRILLO平台，则这里定义了`libupdate_engine`静态库模块的编译规则；如果是非BRILLO平台，则这里定义了`libupdate_engine_android`静态库模块的编译规则。显然，这里BRILLO宏的定义与否，会影响生成静态库的名字。
>
> 所以，我们只需要在编译结果中检查生成的static_library是`libupdate_engine`还是`libupdate_engine_android`就能反过来验证BRILLO到底有没有定义了。
> 
> 以下是我在生成的STATIC_LIBRARY目录中查找"update_engine"相关模块的结果：
> ```
> src/out/target/product/bcm7252ssffdr4/obj$ find STATIC_LIBRARIES -type d -iname "*update_engine*"
> STATIC_LIBRARIES/libupdate_engine_android_intermediates
> STATIC_LIBRARIES/update_metadata-protos_intermediates/proto/system/update_engine
> src/out/target/product/bcm7252ssffdr4/obj$ 
> ```
> 显然，从这里编译生成的目录“libupdate_engine_android_intermediates”可以反推，我们前面看到的BRILLO是没有定义的。

### 第425~467行
```
# update_engine (type: executable)
# ========================================================
# update_engine daemon.
include $(CLEAR_VARS)
LOCAL_MODULE := update_engine
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_REQUIRED_MODULES := \
    bspatch \
    cacerts_google
ifeq ($(local_use_weave),1)
LOCAL_REQUIRED_MODULES += updater.json
endif  # local_use_weave == 1
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries)
LOCAL_SRC_FILES := \
    main.cc

ifdef BRILLO
LOCAL_C_INCLUDES += \
    $(ue_libupdate_engine_exported_c_includes)
LOCAL_STATIC_LIBRARIES := \
    libupdate_engine \
    $(ue_libupdate_engine_exported_static_libraries:-host=)
LOCAL_SHARED_LIBRARIES += \
    $(ue_libupdate_engine_exported_shared_libraries:-host=)
else  # !defined(BRILLO)
LOCAL_STATIC_LIBRARIES := \
    libupdate_engine_android \
    $(ue_libupdate_engine_android_exported_static_libraries:-host=)
LOCAL_SHARED_LIBRARIES += \
    $(ue_libupdate_engine_android_exported_shared_libraries:-host=)
endif  # !defined(BRILLO)

LOCAL_INIT_RC := update_engine.rc
include $(BUILD_EXECUTABLE)
```
以上代码定义了生成target环境可执行应用update_engine的规则，其源码很简单，就只有一个main.cc。
这里的`update_engine`应用是Update Engine服务端的守护进程，通过binder方式向客户端提供服务。

库依赖方面，对于BRILLO平台和非BRILLO平台，update_engine依赖于不同的静态和动态库。
对于我们这里分析的非BRILLO平台，依赖于以下静态和共享库：
```
LOCAL_STATIC_LIBRARIES := \
    libupdate_engine_android \
    $(ue_libupdate_engine_android_exported_static_libraries:-host=)
LOCAL_SHARED_LIBRARIES += \
    $(ue_libupdate_engine_android_exported_shared_libraries:-host=)
```

并有一个相应的init rc脚本：`update_engine.rc`

### 第468~535行

```
# update_engine_sideload (type: executable)
# ========================================================
# A static binary equivalent to update_engine daemon that installs an update
# from a local file directly instead of running in the background.
include $(CLEAR_VARS)
LOCAL_MODULE := update_engine_sideload
LOCAL_FORCE_STATIC_EXECUTABLE := true
LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)/sbin
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_REQUIRED_MODULES := \
    bspatch_recovery
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := \
    $(ue_common_cflags) \
    -D_UE_SIDELOAD
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes) \
    bootable/recovery
#TODO(deymo): Remove external/cros/system_api/dbus once the strings are moved
# out of the DBus interface.
LOCAL_C_INCLUDES += \
    external/cros/system_api/dbus
LOCAL_SRC_FILES := \
    boot_control_android.cc \
    hardware_android.cc \
    network_selector_stub.cc \
    proxy_resolver.cc \
    sideload_main.cc \
    update_attempter_android.cc \
    update_status_utils.cc \
    utils_android.cc
LOCAL_STATIC_LIBRARIES := \
    libfs_mgr \
    libpayload_consumer \
    update_metadata-protos \
    $(ue_libpayload_consumer_exported_static_libraries:-host=) \
    $(ue_update_metadata_protos_exported_static_libraries)
# We add the static versions of the shared libraries since we are forcing this
# binary to be a static binary, so we also need to include all the static
# library dependencies of these static libraries.
LOCAL_STATIC_LIBRARIES += \
    $(ue_common_shared_libraries) \
    libcutils \
    libcrypto_static \
    $(ue_update_metadata_protos_exported_shared_libraries) \
    libevent \
    libmodpb64 \
    liblog

ifeq ($(strip $(PRODUCT_STATIC_BOOT_CONTROL_HAL)),)
# No static boot_control HAL defined, so no sideload support. We use a fake
# boot_control HAL to allow compiling update_engine_sideload for test purposes.
ifeq ($(strip $(AB_OTA_UPDATER)),true)
$(warning No PRODUCT_STATIC_BOOT_CONTROL_HAL configured but AB_OTA_UPDATER is \
true, no update sideload support.)
endif  # AB_OTA_UPDATER == true
LOCAL_SRC_FILES += \
    boot_control_recovery_stub.cc
else  # PRODUCT_STATIC_BOOT_CONTROL_HAL != ""
LOCAL_STATIC_LIBRARIES += \
    $(PRODUCT_STATIC_BOOT_CONTROL_HAL)
endif  # PRODUCT_STATIC_BOOT_CONTROL_HAL != ""

include $(BUILD_EXECUTABLE)
```
以上代码定义了生成target上可执行模块`update_engine_sideload`的规则。
从`LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)/sbin`看，生成的文件位于recovery/bin目录下，显然这个应用是在`recovery`系统下才有的。

从名字中包含`sideload`看，跟`recovery`系统中的`sideload`升级方式有关。实际上在`recovery`系统下，没有了`update_engine`的服务端进程，所有升级都通过一个可执行的`update_engine_sideload`搞定。


另外，这个模块规则的最后指出，如果平台没有单独定义`boot_control`HAL的静态库实现，即`PRODUCT_STATIC_BOOT_CONTROL_HAL`，默认会编译`boot_control_recovery_stub.cc`文件来替代，但后者其实是个空文件，此时`update_engine_sideload`并不真正支持sideload方式，而只能用于测试用途。

### 第536~586行

```
# libupdate_engine_client (type: shared_library)
# ========================================================
include $(CLEAR_VARS)
LOCAL_MODULE := libupdate_engine_client
LOCAL_CFLAGS := \
    -Wall \
    -Werror \
    -Wno-unused-parameter \
    -DUSE_DBUS=$(local_use_dbus) \
    -DUSE_BINDER=$(local_use_binder)
LOCAL_CLANG := true
LOCAL_CPP_EXTENSION := .cc
# TODO(deymo): Remove "external/cros/system_api/dbus" when dbus is not used.
LOCAL_C_INCLUDES := \
    $(LOCAL_PATH)/client_library/include \
    external/cros/system_api/dbus \
    system \
    external/gtest/include
LOCAL_EXPORT_C_INCLUDE_DIRS := $(LOCAL_PATH)/client_library/include
LOCAL_SHARED_LIBRARIES := \
    libchrome \
    libbrillo
LOCAL_SRC_FILES := \
    client_library/client.cc \
    update_status_utils.cc

# We can only compile support for one IPC mechanism. If both "binder" and "dbus"
# are defined, we prefer binder.
ifeq ($(local_use_binder),1)
LOCAL_AIDL_INCLUDES := $(LOCAL_PATH)/binder_bindings
LOCAL_SHARED_LIBRARIES += \
    libbinder \
    libbrillo-binder \
    libutils
LOCAL_SRC_FILES += \
    binder_bindings/android/brillo/IUpdateEngine.aidl \
    binder_bindings/android/brillo/IUpdateEngineStatusCallback.aidl \
    client_library/client_binder.cc \
    parcelable_update_engine_status.cc
else  # local_use_binder != 1
LOCAL_STATIC_LIBRARIES := \
    update_engine_client-dbus-proxies
LOCAL_SHARED_LIBRARIES += \
    libchrome-dbus \
    libbrillo-dbus
LOCAL_SRC_FILES += \
    client_library/client_dbus.cc
endif  # local_use_binder == 1

include $(BUILD_SHARED_LIBRARY)
```
以上定义了生成静态库`libupdate_engine_client`的规则，从字面看，这个静态库应该是用于`update_engine`的客户端的。从后面的分析可以看到，这个`libupdate_engine_client`只有在BRILLO有定义时才会被`update_engine_client`引用，否则就不会引用。

### 第587~625行

```
# update_engine_client (type: executable)
# ========================================================
# update_engine console client.
include $(CLEAR_VARS)
LOCAL_MODULE := update_engine_client
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := $(ue_common_c_includes)
LOCAL_SHARED_LIBRARIES := $(ue_common_shared_libraries)
ifdef BRILLO
LOCAL_SHARED_LIBRARIES += \
    libupdate_engine_client
LOCAL_SRC_FILES := \
    update_engine_client.cc \
    common/error_code_utils.cc
else  # !defined(BRILLO)
#TODO(deymo): Remove external/cros/system_api/dbus once the strings are moved
# out of the DBus interface.
LOCAL_C_INCLUDES += \
    external/cros/system_api/dbus
LOCAL_SHARED_LIBRARIES += \
    libbinder \
    libbinderwrapper \
    libbrillo-binder \
    libutils
LOCAL_AIDL_INCLUDES := $(LOCAL_PATH)/binder_bindings
LOCAL_SRC_FILES := \
    binder_bindings/android/os/IUpdateEngine.aidl \
    binder_bindings/android/os/IUpdateEngineCallback.aidl \
    common/error_code_utils.cc \
    update_engine_client_android.cc \
    update_status_utils.cc
endif  # !defined(BRILLO)
include $(BUILD_EXECUTABLE)
```
以上定义了生成target可执行应用`update_engine_client`，这个是Android自带的uploade_engine客户端demo应用，实际各Android设备产商会开发自己的Update Engine客户端应用。

> 2018/06/13补充：
> 留意以下宏：
> ```
> ifdef BRILLO
> LOCAL_SHARED_LIBRARIES += \
>     libupdate_engine_client
> LOCAL_SRC_FILES := \
>     update_engine_client.cc \
>     common/error_code_utils.cc
> else  # !defined(BRILLO)
> ...
> endif  # !defined(BRILLO)
> ```
> 这里说明，只有在定义了BRILLO的情况下，`update_engine_client`才会依赖于`libupdate_engine_client`，对于非BRILLO平台，我们甚至不需要去分析`libupdate_engine_client`模块。又少一个不用看的模块，哈哈，有没有觉得轻松一点。

### 第626~714行
```
# libpayload_generator (type: static_library)
# ========================================================
# server-side code. This is used for delta_generator and unittests but not
# for any client code.
ue_libpayload_generator_exported_static_libraries := \
    libpayload_consumer \
    update_metadata-protos \
    liblzma \
    $(ue_libpayload_consumer_exported_static_libraries) \
    $(ue_update_metadata_protos_exported_static_libraries)
ue_libpayload_generator_exported_shared_libraries := \
    libext2fs-host \
    $(ue_libpayload_consumer_exported_shared_libraries) \
    $(ue_update_metadata_protos_exported_shared_libraries)

ue_libpayload_generator_src_files := \
    payload_generator/ab_generator.cc \
    payload_generator/annotated_operation.cc \
    payload_generator/blob_file_writer.cc \
    payload_generator/block_mapping.cc \
    payload_generator/bzip.cc \
    payload_generator/cycle_breaker.cc \
    payload_generator/delta_diff_generator.cc \
    payload_generator/delta_diff_utils.cc \
    payload_generator/ext2_filesystem.cc \
    payload_generator/extent_ranges.cc \
    payload_generator/extent_utils.cc \
    payload_generator/full_update_generator.cc \
    payload_generator/graph_types.cc \
    payload_generator/graph_utils.cc \
    payload_generator/inplace_generator.cc \
    payload_generator/payload_file.cc \
    payload_generator/payload_generation_config.cc \
    payload_generator/payload_signer.cc \
    payload_generator/raw_filesystem.cc \
    payload_generator/tarjan.cc \
    payload_generator/topological_sort.cc \
    payload_generator/xz_android.cc

ifeq ($(HOST_OS),linux)
# Build for the host.
include $(CLEAR_VARS)
LOCAL_MODULE := libpayload_generator
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := $(ue_common_c_includes)
LOCAL_STATIC_LIBRARIES := \
    libpayload_consumer \
    update_metadata-protos \
    liblzma \
    $(ue_libpayload_consumer_exported_static_libraries) \
    $(ue_update_metadata_protos_exported_static_libraries)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libpayload_generator_exported_shared_libraries) \
    $(ue_libpayload_consumer_exported_shared_libraries) \
    $(ue_update_metadata_protos_exported_shared_libraries)
LOCAL_SRC_FILES := $(ue_libpayload_generator_src_files)
include $(BUILD_HOST_STATIC_LIBRARY)
endif  # HOST_OS == linux

# Build for the target.
include $(CLEAR_VARS)
LOCAL_MODULE := libpayload_generator
LOCAL_MODULE_CLASS := STATIC_LIBRARIES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := $(ue_common_c_includes)
LOCAL_STATIC_LIBRARIES := \
    libpayload_consumer \
    update_metadata-protos \
    liblzma \
    $(ue_libpayload_consumer_exported_static_libraries:-host=) \
    $(ue_update_metadata_protos_exported_static_libraries)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libpayload_generator_exported_shared_libraries:-host=) \
    $(ue_libpayload_consumer_exported_shared_libraries:-host=) \
    $(ue_update_metadata_protos_exported_shared_libraries)
LOCAL_SRC_FILES := $(ue_libpayload_generator_src_files)
include $(BUILD_STATIC_LIBRARY)
```

以上定义了生成`libpayload_generator`静态库的两条规则，分别用于host和target。

### 第715~766行

```
# delta_generator (type: executable)
# ========================================================
# server-side delta generator.
ue_delta_generator_src_files := \
    payload_generator/generate_delta_main.cc

ifeq ($(HOST_OS),linux)
# Build for the host.
include $(CLEAR_VARS)
LOCAL_MODULE := delta_generator
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := $(ue_common_c_includes)
LOCAL_STATIC_LIBRARIES := \
    libpayload_consumer \
    libpayload_generator \
    $(ue_libpayload_consumer_exported_static_libraries) \
    $(ue_libpayload_generator_exported_static_libraries)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libpayload_consumer_exported_shared_libraries) \
    $(ue_libpayload_generator_exported_shared_libraries)
LOCAL_SRC_FILES := $(ue_delta_generator_src_files)
include $(BUILD_HOST_EXECUTABLE)
endif  # HOST_OS == linux

# Build for the target.
include $(CLEAR_VARS)
LOCAL_MODULE := delta_generator
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := $(ue_common_c_includes)
LOCAL_STATIC_LIBRARIES := \
    libpayload_consumer \
    libpayload_generator \
    $(ue_libpayload_consumer_exported_static_libraries:-host=) \
    $(ue_libpayload_generator_exported_static_libraries:-host=)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libpayload_consumer_exported_shared_libraries:-host=) \
    $(ue_libpayload_generator_exported_shared_libraries:-host=)
LOCAL_SRC_FILES := $(ue_delta_generator_src_files)
include $(BUILD_EXECUTABLE)
```

以上定义了生成可执行应用`delta_generator`的规则，分别对应于host和target。

### 第767~976行

```

# TODO(deymo): Enable the unittest binaries in non-Brillo builds once the DBus
# dependencies are removed or placed behind the USE_DBUS flag.
ifdef BRILLO

# Private and public keys for unittests.
# ========================================================
# Generate a module that installs a prebuilt private key and a module that
# installs a public key generated from the private key.
#
# $(1): The path to the private key in pem format.
define ue-unittest-keys
    $(eval include $(CLEAR_VARS)) \
    $(eval LOCAL_MODULE := ue_$(1).pem) \
    $(eval LOCAL_MODULE_CLASS := ETC) \
    $(eval $(ifeq $(BRILLO), 1, LOCAL_MODULE_TAGS := eng)) \
    $(eval LOCAL_SRC_FILES := $(1).pem) \
    $(eval LOCAL_MODULE_PATH := \
        $(TARGET_OUT_DATA_NATIVE_TESTS)/update_engine_unittests) \
    $(eval LOCAL_MODULE_STEM := $(1).pem) \
    $(eval include $(BUILD_PREBUILT)) \
    \
    $(eval include $(CLEAR_VARS)) \
    $(eval LOCAL_MODULE := ue_$(1).pub.pem) \
    $(eval LOCAL_MODULE_CLASS := ETC) \
    $(eval $(ifeq $(BRILLO), 1, LOCAL_MODULE_TAGS := eng)) \
    $(eval LOCAL_MODULE_PATH := \
        $(TARGET_OUT_DATA_NATIVE_TESTS)/update_engine_unittests) \
    $(eval LOCAL_MODULE_STEM := $(1).pub.pem) \
    $(eval include $(BUILD_SYSTEM)/base_rules.mk) \
    $(eval $(LOCAL_BUILT_MODULE) : $(LOCAL_PATH)/$(1).pem ; \
        openssl rsa -in $$< -pubout -out $$@)
endef

$(call ue-unittest-keys,unittest_key)
$(call ue-unittest-keys,unittest_key2)

# Sample images for unittests.
# ========================================================
# Generate a prebuilt module that installs a sample image from the compressed
# sample_images.tar.bz2 file used by the unittests.
#
# $(1): The filename in the sample_images.tar.bz2
define ue-unittest-sample-image
    $(eval include $(CLEAR_VARS)) \
    $(eval LOCAL_MODULE := ue_unittest_$(1)) \
    $(eval LOCAL_MODULE_CLASS := EXECUTABLES) \
    $(eval $(ifeq $(BRILLO), 1, LOCAL_MODULE_TAGS := eng)) \
    $(eval LOCAL_MODULE_PATH := \
        $(TARGET_OUT_DATA_NATIVE_TESTS)/update_engine_unittests/gen) \
    $(eval LOCAL_MODULE_STEM := $(1)) \
    $(eval include $(BUILD_SYSTEM)/base_rules.mk) \
    $(eval $(LOCAL_BUILT_MODULE) : \
        $(LOCAL_PATH)/sample_images/sample_images.tar.bz2 ; \
        tar -jxf $$< -C $$(dir $$@) $$(notdir $$@) && touch $$@)
endef

$(call ue-unittest-sample-image,disk_ext2_1k.img)
$(call ue-unittest-sample-image,disk_ext2_4k.img)
$(call ue-unittest-sample-image,disk_ext2_4k_empty.img)
$(call ue-unittest-sample-image,disk_ext2_unittest.img)

# Zlib Fingerprint
# ========================================================
include $(CLEAR_VARS)
LOCAL_MODULE := zlib_fingerprint
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_DATA_NATIVE_TESTS)/update_engine_unittests
LOCAL_PREBUILT_MODULE_FILE := $(TARGET_OUT_COMMON_GEN)/zlib_fingerprint
include $(BUILD_PREBUILT)

# test_http_server (type: executable)
# ========================================================
# Test HTTP Server.
include $(CLEAR_VARS)
LOCAL_MODULE := test_http_server
ifdef BRILLO
  LOCAL_MODULE_TAGS := eng
endif
LOCAL_MODULE_PATH := $(TARGET_OUT_DATA_NATIVE_TESTS)/update_engine_unittests
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := $(ue_common_c_includes)
LOCAL_SHARED_LIBRARIES := $(ue_common_shared_libraries)
LOCAL_SRC_FILES := \
    common/http_common.cc \
    test_http_server.cc
include $(BUILD_EXECUTABLE)

# update_engine_unittests (type: executable)
# ========================================================
# Main unittest file.
include $(CLEAR_VARS)
LOCAL_MODULE := update_engine_unittests
ifdef BRILLO
  LOCAL_MODULE_TAGS := eng
endif
LOCAL_REQUIRED_MODULES := \
    ue_unittest_disk_ext2_1k.img \
    ue_unittest_disk_ext2_4k.img \
    ue_unittest_disk_ext2_4k_empty.img \
    ue_unittest_disk_ext2_unittest.img \
    ue_unittest_key.pem \
    ue_unittest_key.pub.pem \
    ue_unittest_key2.pem \
    ue_unittest_key2.pub.pem \
    zlib_fingerprint
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_CPP_EXTENSION := .cc
LOCAL_CLANG := true
LOCAL_CFLAGS := $(ue_common_cflags)
LOCAL_CPPFLAGS := $(ue_common_cppflags)
LOCAL_LDFLAGS := $(ue_common_ldflags)
LOCAL_C_INCLUDES := \
    $(ue_common_c_includes) \
    $(ue_libupdate_engine_exported_c_includes)
LOCAL_STATIC_LIBRARIES := \
    libupdate_engine \
    libpayload_generator \
    libbrillo-test-helpers \
    libgmock \
    libgtest \
    libchrome_test_helpers \
    $(ue_libupdate_engine_exported_static_libraries:-host=) \
    $(ue_libpayload_generator_exported_static_libraries:-host=)
LOCAL_SHARED_LIBRARIES := \
    $(ue_common_shared_libraries) \
    $(ue_libupdate_engine_exported_shared_libraries:-host=) \
    $(ue_libpayload_generator_exported_shared_libraries:-host=)
LOCAL_SRC_FILES := \
    certificate_checker_unittest.cc \
    common/action_pipe_unittest.cc \
    common/action_processor_unittest.cc \
    common/action_unittest.cc \
    common/cpu_limiter_unittest.cc \
    common/fake_prefs.cc \
    common/file_fetcher_unittest.cc \
    common/hash_calculator_unittest.cc \
    common/http_fetcher_unittest.cc \
    common/hwid_override_unittest.cc \
    common/mock_http_fetcher.cc \
    common/prefs_unittest.cc \
    common/subprocess_unittest.cc \
    common/terminator_unittest.cc \
    common/test_utils.cc \
    common/utils_unittest.cc \
    common_service_unittest.cc \
    connection_manager_unittest.cc \
    fake_shill_proxy.cc \
    fake_system_state.cc \
    metrics_utils_unittest.cc \
    omaha_request_action_unittest.cc \
    omaha_request_params_unittest.cc \
    omaha_response_handler_action_unittest.cc \
    p2p_manager_unittest.cc \
    payload_consumer/bzip_extent_writer_unittest.cc \
    payload_consumer/delta_performer_integration_test.cc \
    payload_consumer/delta_performer_unittest.cc \
    payload_consumer/download_action_unittest.cc \
    payload_consumer/extent_writer_unittest.cc \
    payload_consumer/file_writer_unittest.cc \
    payload_consumer/filesystem_verifier_action_unittest.cc \
    payload_consumer/postinstall_runner_action_unittest.cc \
    payload_consumer/xz_extent_writer_unittest.cc \
    payload_generator/ab_generator_unittest.cc \
    payload_generator/blob_file_writer_unittest.cc \
    payload_generator/block_mapping_unittest.cc \
    payload_generator/cycle_breaker_unittest.cc \
    payload_generator/delta_diff_utils_unittest.cc \
    payload_generator/ext2_filesystem_unittest.cc \
    payload_generator/extent_ranges_unittest.cc \
    payload_generator/extent_utils_unittest.cc \
    payload_generator/fake_filesystem.cc \
    payload_generator/full_update_generator_unittest.cc \
    payload_generator/graph_utils_unittest.cc \
    payload_generator/inplace_generator_unittest.cc \
    payload_generator/payload_file_unittest.cc \
    payload_generator/payload_generation_config_unittest.cc \
    payload_generator/payload_signer_unittest.cc \
    payload_generator/tarjan_unittest.cc \
    payload_generator/topological_sort_unittest.cc \
    payload_generator/zip_unittest.cc \
    payload_state_unittest.cc \
    update_attempter_unittest.cc \
    update_manager/boxed_value_unittest.cc \
    update_manager/chromeos_policy_unittest.cc \
    update_manager/evaluation_context_unittest.cc \
    update_manager/generic_variables_unittest.cc \
    update_manager/prng_unittest.cc \
    update_manager/real_config_provider_unittest.cc \
    update_manager/real_device_policy_provider_unittest.cc \
    update_manager/real_random_provider_unittest.cc \
    update_manager/real_shill_provider_unittest.cc \
    update_manager/real_system_provider_unittest.cc \
    update_manager/real_time_provider_unittest.cc \
    update_manager/real_updater_provider_unittest.cc \
    update_manager/umtest_utils.cc \
    update_manager/update_manager_unittest.cc \
    update_manager/variable_unittest.cc \
    testrunner.cc
ifeq ($(local_use_libcros),1)
LOCAL_SRC_FILES += \
    chrome_browser_proxy_resolver_unittest.cc
endif  # local_use_libcros == 1
include $(BUILD_NATIVE_TEST)
endif  # BRILLO
```

从一开始的注释看，以上定义了BRILLO平台的一些单元测试的东东，目前是非BRILLO平台，暂不打算去关心里面到底做了什么，还是那句话，不管你的makefile有多长多复杂，`we don't care`。

### 第977~985行
```
# Weave schema files
# ========================================================
include $(CLEAR_VARS)
LOCAL_MODULE := updater.json
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_ETC)/weaved/traits
LOCAL_SRC_FILES := weaved/traits/$(LOCAL_MODULE)
include $(BUILD_PREBUILT)
```
定义了预编译的模块`updater.json`，目前我还不清楚这个模块到底是做什么用途的，知道的大神来指点下。

### 第986~998行

```
# Update payload signing public key.
# ========================================================
ifdef BRILLO
include $(CLEAR_VARS)
LOCAL_MODULE := brillo-update-payload-key
LOCAL_MODULE_CLASS := ETC
LOCAL_MODULE_PATH := $(TARGET_OUT_ETC)/update_engine
LOCAL_MODULE_STEM := update-payload-key.pub.pem
LOCAL_SRC_FILES := update_payload_key/brillo-update-payload-key.pub.pem
LOCAL_BUILT_MODULE_STEM := update_payload_key/brillo-update-payload-key.pub.pem
include $(BUILD_PREBUILT)
endif  # BRILLO
```
定义了预编译规则，用于复制BRILLO平台的公钥，我也不打算去关心了，制作升级包时可能会使用到这个公钥，具体分析升级包制作时再说吧。

### 第999到1013行

```
# Brillo update payload generation script
# ========================================================
ifeq ($(HOST_OS),linux)
include $(CLEAR_VARS)
LOCAL_SRC_FILES := scripts/brillo_update_payload
LOCAL_MODULE := brillo_update_payload
LOCAL_MODULE_CLASS := EXECUTABLES
LOCAL_IS_HOST_MODULE := true
LOCAL_MODULE_TAGS := optional
LOCAL_REQUIRED_MODULES := \
    delta_generator \
    shflags
include $(BUILD_PREBUILT)
endif  # HOST_OS == linux

```

这里定义了预编译规则，用于复制脚本`brillo_update_payload`，但是我很不理解的是，为啥不将这个应用包含到ifdef BRILLO宏中去呢？

## 2. `Android.mk`模块总结

盘点一下Android.mk中生成的各模块，针对非BRILLO平台主要有以下4类：
```
# 静态库模块
STATIC_LIBRARIES:
	update_metadata-protos		(host, target)
	libpayload_consumer 		(host, target)
	libupdate_engine_android 	(target)
	libpayload_generator		(host, target)

# 可执行模块
EXECUTABLES:
	update_engine 			(target)
	update_engine_sideload 		(target)
	update_engine_client 		(target)
	delta_generator 		(host, target)

# 共享库模块
SHARED_LIBRARIES:
	libupdate_engine_client 	(target)
# 事实上，只有定义了BRILLO的情况下，update_engine_client才会引用libupdate_engine_client

# 预编译模块
PREBUILT:
	updater.json 			(target)
	brillo_update_payload 		(host)
```

从各模块规则的库依赖规则看，简化后从可执行应用开始的各模块依赖关系如下（仅列举了模块内部相关的库依赖，未列出对非update_engine模块的库依赖，各级箭头表示依赖关系）：
```
update_engine (target)
  --> libupdate_engine_android
    --> libpayload_consumer
      --> update_metadata-protos

update_engine_sideload (target)
  --> update_engine_sideload
    --> update_metadata-protos

update_engine_client (target)

delta_generator (host)
  --> libpayload_generator
    --> libpayload_consumer
      --> update_metadata-protos
```

> !!! 注意了，实际上只有在BRILLO平台上，`update_engine_client`才会依赖于`libupdate_engine_client`：
> ```
> update_engine_client (target)
>   --> libupdate_engine_client
> ```

可执行应用后面的括号表示该应用运行的环境，target或host。

__总体上，共生成了4可执行个应用，具体为android主系统使用的的服务端`update_engine`和客户端`update_engine_client`, recovery系统使用的`update_engine_sideload`，以及host上的升级包工具`delta_generator`。这4个可执行应用，部分依赖于4个静态库（`update_metadata-protos, libpayload_consumer, libupdate_engine_android, libpayload_generator`）和1个共享库（`libupdate_engine_client`）。__

## 3. Update Engine各模块的文件依赖

啰嗦一点，再将上面的各个可执行应用或库文件目标的依赖详细列举出来，如下（没有列举依赖的非Update Engine的库）

> 后续分析中，如果不确定代码是否有起作用，是否有参与编译时可能还需要反复检查这里的文件依赖列表

```
update_metadata-protos (STATIC_LIBRARIES)
  --> update_metadata.proto <注意：这里是.proto文件>

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

libupdate_engine_android (STATIC_LIBRARIES)
  --> binder_bindings/android/os/IUpdateEngine.aidl         <注意：这里是.aidl文件>
      binder_bindings/android/os/IUpdateEngineCallback.aidl <注意：这里是.aidl文件>
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

update_engine (EXECUTABLES)
  --> main.cc

update_engine_sideload (EXECUTABLES)
  --> boot_control_android.cc
      hardware_android.cc
      network_selector_stub.cc
      proxy_resolver.cc
      sideload_main.cc
      update_attempter_android.cc
      update_status_utils.cc
      utils_android.cc
      boot_control_recovery_stub.cc

update_engine_client (EXECUTABLES)
  --> binder_bindings/android/os/IUpdateEngine.aidl         <注意：这里是.aidl文件>
      binder_bindings/android/os/IUpdateEngineCallback.aidl <注意：这里是.aidl文件>
      common/error_code_utils.cc
      update_engine_client_android.cc
      update_status_utils.cc

libpayload_generator (STATIC_LIBRARIES)
  --> payload_generator/ab_generator.cc
      payload_generator/annotated_operation.cc
      payload_generator/blob_file_writer.cc
      payload_generator/block_mapping.cc
      payload_generator/bzip.cc
      payload_generator/cycle_breaker.cc
      payload_generator/delta_diff_generator.cc
      payload_generator/delta_diff_utils.cc
      payload_generator/ext2_filesystem.cc
      payload_generator/extent_ranges.cc
      payload_generator/extent_utils.cc
      payload_generator/full_update_generator.cc
      payload_generator/graph_types.cc
      payload_generator/graph_utils.cc
      payload_generator/inplace_generator.cc
      payload_generator/payload_file.cc
      payload_generator/payload_generation_config.cc
      payload_generator/payload_signer.cc
      payload_generator/raw_filesystem.cc
      payload_generator/tarjan.cc
      payload_generator/topological_sort.cc
      payload_generator/xz_android.cc

delta_generator (EXECUTABLES)
  --> payload_generator/generate_delta_main.cc
```

> 2018/06/13补充：
> 
> 上面依赖的目标大部分是`.cc`文件，但除了`.cc`文件外，还依赖`update_metadata.proto`文件和`IUpdateEngine.aidl`以及`IUpdateEngineCallback.aidl`这两个`aidl`文件。后续会对`.proto`和`.aidl`文件进行分析。
>
> 另外，仔细看这些模块所依赖的代码目录路径，主要有：
> - update_engine的根目录
> - common
> - payload_consumer
> - binder_bindings/android/os
> - payload_generator
> 
> update_engine目录共有13个子目录，这里除了根目录外只用到了4个子目录的代码，可见实际使用的代码只是其中一部分，整体涉及的文件数大大减少，不到100个文件。
>
> 所以不要看到目录和文件很多担心无从下手，其实并没有想象的那么难。
> 如果不确定某个模块到底依赖于哪些文件，则可以到out目录的相应位置查找。
> 例如：模块`update_engine_client`到底依赖于哪些代码文件？由于`update_engine_client`是在target运行的可执行文件，则需要到out/target下的EXECUTABLE目录下查找。
> ```
> src/out/target/product/bcm7252ssffdr4/obj$ tree EXECUTABLES/update_engine_client_intermediates/
> EXECUTABLES/update_engine_client_intermediates/
> |-- LINKED
> |   `-- update_engine_client
> |-- PACKED
> |   `-- update_engine_client
> |-- aidl-generated
> |   |-- include
> |   |   `-- android
> |   |       `-- os
> |   |           |-- BnUpdateEngine.h
> |   |           |-- BnUpdateEngineCallback.h
> |   |           |-- BpUpdateEngine.h
> |   |           |-- BpUpdateEngineCallback.h
> |   |           |-- IUpdateEngine.h
> |   |           `-- IUpdateEngineCallback.h
> |   `-- src
> |       `-- binder_bindings
> |           `-- android
> |               `-- os
> |                   |-- IUpdateEngine.cc
> |                   |-- IUpdateEngine.o
> |                   |-- IUpdateEngineCallback.cc
> |                   `-- IUpdateEngineCallback.o
> |-- common
> |   `-- error_code_utils.o
> |-- export_includes
> |-- import_includes
> |-- update_engine_client
> |-- update_engine_client_android.o
> `-- update_status_utils.o
> 
> 11 directories, 18 files
> ```
> 这里对应的`.o`文件包括：
> - aidl-generated/src/binder_bindings/android/os/IUpdateEngine.o
> - aidl-generated/src/binder_bindings/android/os/IUpdateEngineCallback.o
> - common/error_code_utils.o
> - update_engine_client_android.o
> - update_status_utils.o
> 
> 再对比看看我们前面分析得到的5个代码文件，是不是觉得简单多了？

细分到目标对库和文件的依赖后，看起好好像没有那么漫无目的、无从下手的感觉了。

基于上面提出的目标和文件依赖关系，后续可以自顶向下或自底向上对代码进行分析：

- 自顶向下从顶层代码入手，向下分析各层模块，直到最底层的实现，好处是对代码容易有全局观，坏处是开始对底层实现不清楚。
- 自底向上从最底层的小模块开始，层层向上分析，直到最上层的应用逻辑，好处是一开始就了解代码的底层实现，坏处是容易陷入到各个模块中，没有全局观，弄不清楚各模块的关系。

可以考虑从升级场景入手，先分析较简单的客户端`update_engine_client`，再分析代码复杂的服务端`update_engine`。

## 联系和福利

- 本文原创发布于微信公众号“洛奇看世界”，一个大龄2b码农的世界。
- 关注微信公众号“洛奇看世界”
  - 回复关键词“Android电子书”，获取超过150本Android相关的电子书和文档。电子书包含了Android开发相关的方方面面，从此你再也不需要到处找Android开发的电子书了。
  ![image](https://github.com/guyongqiangx/blog/blob/dev/shell/images/qrcode-public-account.jpg?raw=true)

---

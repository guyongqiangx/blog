# Android Update Engine分析（二）Protobuf和AIDL文件

> 技术文章直入主题，展示结论，容易让人知其然，不知其所以然。</br>
> 我个人更喜欢在文章中展示如何阅读代码，逐步分析解决问题的思路和过程。这样的思考比知道结论更重要，希望我的分析能让你有所收获。

在上一篇《Android Update Engine分析（一）Makefile》的最后"`3. 模块对Update Engine文件的依赖`"一节时有提到3个特殊的`.proto`和`.aidl`文件，如下：
```
update_metadata-protos (STATIC_LIBRARIES)
  --> update_metadata.proto <注意：这里是.proto文件>

...

libupdate_engine_android (STATIC_LIBRARIES)
  --> binder_bindings/android/os/IUpdateEngine.aidl         <注意：这里是.aidl文件>
      binder_bindings/android/os/IUpdateEngineCallback.aidl <注意：这里是.aidl文件>
      binder_service_android.cc
      boot_control_android.cc
...

update_engine_client (EXECUTABLES)
  --> binder_bindings/android/os/IUpdateEngine.aidl         <注意：这里是.aidl文件>
      binder_bindings/android/os/IUpdateEngineCallback.aidl <注意：这里是.aidl文件>
      common/error_code_utils.cc
      update_engine_client_android.cc
      update_status_utils.cc
...
```

可见，
- `update_metadata-protos`静态库依赖`update_metadata.proto`文件
- `libupdate_engine_android`静态库依赖`IUpdateEngine.aidl`和`IUpdateEngineCallback.aidl`文件
- `update_engine_client`可执行应用依赖`IUpdateEngine.aidl`和`IUpdateEngineCallback.aidl`文件

这里的文件一类是`.proto`结尾，另外一类是`.aidl`结尾。

> 注：本文主要分析Update Engine相关代码中三个`.proto`和`.aidl`文件内容和编译结果，并不是对Protobuf和AIDL格式协议或处理流程的分析。对于后者，如果想详细了解，可以借助于google的文档或搜索引擎。如果你此前对这两者没有深入了解，并不会影响本文的阅读。总体上大致需要知道这两类文件的作用就可以了，真的不需要深入，否则很容易就陷进代码的细节去了。看看自动生成的那些冗长的代码，实在让人头晕。

下面详细来分析下这两类文件。

## 1. Protobuf 文件

打开`update_metadata.proto`文件一看，我去，这都是什么鬼？完全不明白啊。

在阅读update_engine代码前，我从来没有接触过Protobuf，所以如果你也刚好跟我一样没有接触过，那也不用担心，我们可以一起探索下到Protobuf底是什么东西。

搜索一下，网上介绍Protobuf原理和用途的文章很多，这里就不再赘述，这里找到一篇：
- [Protobuf的简单介绍、使用和分析](https://blog.csdn.net/shuliwuflying/article/details/50814123)

以下是我读这篇文章得到的3个重点：

__Protobuf是什么？__

Protobuf(Google Protocol Buffers)是Google提供一个具有高效的协议数据交换格式工具库(类似Json)，但相比于Json，Protobuf有更高的转化效率，时间效率和空间效率都是JSON的3-5倍。

__Protobuf有什么？__

- 关键字message: 代表了实体结构，由多个消息字段(field)组成。
  - 消息字段(field): 包括数据类型、字段名、字段规则、字段唯一标识、默认值
- 数据类型：常见的原子类型都支持
- 字段规则
  - required：必须初始化字段，如果没有赋值，在数据序列化时会抛出异常
  - optional：可选字段，可以不必初始化。
  - repeated：数据可以重复(相当于java 中的Array或List)
  - 字段唯一标识：序列化和反序列化将会使用到。
- 默认值：在定义消息字段时可以给出默认值。

__Protobuf有什么用？__

Protobuf和Xml、Json序列化的方式不同，采用了二进制字节的序列化方式，用字段索引和字段类型通过算法计算得到字段之前的关系映射，从而达到更高的时间效率和空间效率，特别适合对数据大小和传输速率比较敏感的场合使用。

到这里，对Protobuf的功能有了基本了解，继续回到我们的代码。

检查`update_metadata.proto`文件，主要定义了以下几个message:
(注意，这里我们只关心到底定义了哪些message，不要去关注每一个message的详细结构，因为这一阶段我们只关心`update_metadata.proto`是做什么用的)
```
Extent
Signatures
PartitionInfo
ImageInfo
InstallOperation
PartitionUpdate
DeltaArchiveManifest
```

我们再来看看围绕`update_metadata.proto`都生成了哪些文件，检查静态库`update_metadata-protos`的输出目录：
```
src$ tree out/target/product/bcm7252ssffdr4/obj/STATIC_LIBRARIES/update_metadata-protos_intermediates/
out/target/product/bcm7252ssffdr4/obj/STATIC_LIBRARIES/update_metadata-protos_intermediates/
|-- export_includes
|-- import_includes
|-- proto
|   `-- system
|       `-- update_engine
|           |-- update_metadata.pb.cpp
|           |-- update_metadata.pb.h
|           `-- update_metadata.pb.o
`-- update_metadata-protos.a

3 directories, 6 files
```
从上面的结果可见，基于`update_metadata.proto`在`STATIC_LIBRARIES`的相应目录内生成了`update_metadata.pb.cpp`和`update_metadata.pb.h`文件，通过编译这两个文件得到`update_metadata.pu.o`文件，最后打包为库文件`update_metadata-protos.a`。

我们再看看基于`update_metadata.proto`生成的`update_metadata.pb.h`和`update_metadata.pb.cpp`。 

打开文件一看，傻眼了，这两个文件太特么长了，头文件`update_metadata.pb.h`竟然有3200+行，cpp文件`update_metadata.pb.cpp`也有3000+行，这还咋搞啊？

其实完全不用担心，像这种同时有`.h`和`.cpp`存在的代码，通常`.h`文件包含了类的定义和操作接口，`.cpp`文件包含了具体的实现，当我们在粗粒度上阅读代码的时候，只需要关注在头文件中类的定义和接口就好了，知道有哪些类，这些类大致有什么样的接口，实现了哪些功能；此时不需要去关注具体实现的每一个细节。

所以一句话，我们只需要关注`update_metadata.pb.h`就好了，但实际上光是这个头文件的内容也太多，那我们就简单看看这个头文件的特征吧。

文件在包含了必要的头文件后，有下面这段代码：
```
namespace chromeos_update_engine {

// Internal implementation detail -- do not call these.
void  protobuf_AddDesc_system_2fupdate_5fengine_2fupdate_5fmetadata_2eproto();
void protobuf_AssignDesc_system_2fupdate_5fengine_2fupdate_5fmetadata_2eproto();
void protobuf_ShutdownFile_system_2fupdate_5fengine_2fupdate_5fmetadata_2eproto();

class Extent;
class Signatures;
class Signatures_Signature;
class PartitionInfo;
class ImageInfo;
class InstallOperation;
class PartitionUpdate;
class DeltaArchiveManifest;

enum InstallOperation_Type {
  InstallOperation_Type_REPLACE = 0,
  InstallOperation_Type_REPLACE_BZ = 1,
  InstallOperation_Type_MOVE = 2,
  InstallOperation_Type_BSDIFF = 3,
  InstallOperation_Type_SOURCE_COPY = 4,
  InstallOperation_Type_SOURCE_BSDIFF = 5,
  InstallOperation_Type_ZERO = 6,
  InstallOperation_Type_DISCARD = 7,
  InstallOperation_Type_REPLACE_XZ = 8,
  InstallOperation_Type_IMGDIFF = 9
};
bool InstallOperation_Type_IsValid(int value);
const InstallOperation_Type InstallOperation_Type_Type_MIN = InstallOperation_Type_REPLACE;
const InstallOperation_Type InstallOperation_Type_Type_MAX = InstallOperation_Type_IMGDIFF;
const int InstallOperation_Type_Type_ARRAYSIZE = InstallOperation_Type_Type_MAX + 1;
```

这段代码主要有4部分：
1. 整个代码位于`chromeos_update_engine`命名空间；
2. 定义了3个名字又臭又长的函数
```
// Internal implementation detail -- do not call these.
void  protobuf_AddDesc_system_2fupdate_5fengine_2fupdate_5fmetadata_2eproto();
void protobuf_AssignDesc_system_2fupdate_5fengine_2fupdate_5fmetadata_2eproto();
void protobuf_ShutdownFile_system_2fupdate_5fengine_2fupdate_5fmetadata_2eproto();
```
注释写了这三个函数是内部实现，不要去调用，所以我们也不需要去关心；
3. 定义了8个class，这些class都是从`.proto`文件中的`message`结构转换过来的：
```
class Extent;
class Signatures;
class Signatures_Signature;
class PartitionInfo;
class ImageInfo;
class InstallOperation;
class PartitionUpdate;
class DeltaArchiveManifest;
```
4. 定义了枚举类型InstallOperation_Type和相关的一些变量以及操作
```
enum InstallOperation_Type {
  InstallOperation_Type_REPLACE = 0,
  InstallOperation_Type_REPLACE_BZ = 1,
  InstallOperation_Type_MOVE = 2,
  InstallOperation_Type_BSDIFF = 3,
  InstallOperation_Type_SOURCE_COPY = 4,
  InstallOperation_Type_SOURCE_BSDIFF = 5,
  InstallOperation_Type_ZERO = 6,
  InstallOperation_Type_DISCARD = 7,
  InstallOperation_Type_REPLACE_XZ = 8,
  InstallOperation_Type_IMGDIFF = 9
};
bool InstallOperation_Type_IsValid(int value);
const InstallOperation_Type InstallOperation_Type_Type_MIN = InstallOperation_Type_REPLACE;
const InstallOperation_Type InstallOperation_Type_Type_MAX = InstallOperation_Type_IMGDIFF;
const int InstallOperation_Type_Type_ARRAYSIZE = InstallOperation_Type_Type_MAX + 1;
```

文件中，除了上面分析的这部分代码之外，剩下的就是对前面提到的8个class的具体定义了，代码看起来有些繁琐，不过我们还没有深入实现，所以不需要去管它。

所以，到这里`update_metadata.proto`文件就分析完了，总结一下吧：
1. `update_metadata.proto`文件中定义了8个message
2. 编译时Protobuf工具将`.proto`文件转换为`.h`和`.cpp`文件
3. `.proto`文件中的8个message被转换为`.h`文件中的8个class

如果要看每个message或class的细节，我们再回`.proto`文件去看就好了。

这样就分析完了`update_metadata.proto`文件了？有没有意犹未尽的感觉？
以目前的分析，完全够了，再往细看你就要陷进去了。记住，有时候看代码，不要太计较那些细节，要注意在整体上的把握。

## 2. AIDL文件

AIDL文件也是一样，惭愧，我对android研究不全面，在update_engine分析中也是第一次接触`.aidl`文件。

遇到不熟悉的东西不用怕，否则畏难情绪会影响你的思维。

我们先来看看这两个`aidl`文件到底有什么？幸好这两个文件的内容都比较简单。

- `IUpdateEngine.aidl`
```
src/system/update_engine/binder_bindings/android/os$ cat IUpdateEngine.aidl 
...
package android.os;

import android.os.IUpdateEngineCallback;

interface IUpdateEngine {
  void applyPayload(String url,
                    in long payload_offset,
                    in long payload_size,
                    in String[] headerKeyValuePairs);
  boolean bind(IUpdateEngineCallback callback);
  void suspend();
  void resume();
  void cancel();
  void resetStatus();
}
```
从这里可见，`IUpdateEngine.aidl`定义了一个`IUpdateEngine`接口，该接口包含5个函数。

- `IUpdateEngineCallback.aidl`
```
src/system/update_engine/binder_bindings/android/os$ cat IUpdateEngineCallback.aidl 
...
package android.os;

oneway interface IUpdateEngineCallback {
  void onStatusUpdate(int status_code, float percentage);
  void onPayloadApplicationComplete(int error_code);
}
```
从这里可见，`IUpdateEngineCallback.aidl`定义了另外一个接口`IUpdateEngineCallback`，该接口包含2个函数。从字面看，这个接口用于Callback机制。

> 一个小问题： 什么是callback机制？回答不上来的同学面壁完去度娘吧。

看完了aidl文件的内容，我们再看看基于这两个aidl都生成了哪些文件？由于这里aidl文件被两个模块"`libupdate_engine_android`"和"`update_engine_client`"引用，所以我们去检查下这两个模块的out目录，进入这两个模块的输出目录，我们发现竟然有一个"aidl-generated"子目录，里面包含了aidl文件的输出文件。我们从整体上看看这两个模块的out目录都有哪些文件：
```
out/target/product/bcm7252ssffdr4/obj$ tree STATIC_LIBRARIES/libupdate_engine_android_intermediates/
STATIC_LIBRARIES/libupdate_engine_android_intermediates/
|-- aidl-generated
|   |-- include
|   |   `-- android
|   |       `-- os
|   |           |-- BnUpdateEngine.h
|   |           |-- BnUpdateEngineCallback.h
|   |           |-- BpUpdateEngine.h
|   |           |-- BpUpdateEngineCallback.h
|   |           |-- IUpdateEngine.h
|   |           `-- IUpdateEngineCallback.h
|   `-- src
|       `-- binder_bindings
|           `-- android
|               `-- os
|                   |-- IUpdateEngine.cc
|                   |-- IUpdateEngine.o
|                   |-- IUpdateEngineCallback.cc
|                   `-- IUpdateEngineCallback.o
|-- binder_service_android.o
|-- boot_control_android.o
|-- certificate_checker.o
|-- daemon.o
|-- daemon_state_android.o
|-- export_includes
|-- hardware_android.o
|-- import_includes
|-- libcurl_http_fetcher.o
|-- libupdate_engine_android.a
|-- network_selector_android.o
|-- proxy_resolver.o
|-- update_attempter_android.o
|-- update_status_utils.o
`-- utils_android.o

8 directories, 25 files
src/out/target/product/bcm7252ssffdr4/obj$ tree EXECUTABLES/update_engine_client_intermediates/
EXECUTABLES/update_engine_client_intermediates/
|-- LINKED
|   `-- update_engine_client
|-- PACKED
|   `-- update_engine_client
|-- aidl-generated
|   |-- include
|   |   `-- android
|   |       `-- os
|   |           |-- BnUpdateEngine.h
|   |           |-- BnUpdateEngineCallback.h
|   |           |-- BpUpdateEngine.h
|   |           |-- BpUpdateEngineCallback.h
|   |           |-- IUpdateEngine.h
|   |           `-- IUpdateEngineCallback.h
|   `-- src
|       `-- binder_bindings
|           `-- android
|               `-- os
|                   |-- IUpdateEngine.cc
|                   |-- IUpdateEngine.o
|                   |-- IUpdateEngineCallback.cc
|                   `-- IUpdateEngineCallback.o
|-- common
|   `-- error_code_utils.o
|-- export_includes
|-- import_includes
|-- update_engine_client
|-- update_engine_client_android.o
`-- update_status_utils.o

11 directories, 18 files
```

可见，这两个模块的`aidl-generated`目录下的代码文件是一样的，废话，一样的aidl文件生成的代码，能不一样吗？

我们来看其中一个模块下的`aidl-generated`目录：
```
$ tree EXECUTABLES/update_engine_client_intermediates/aidl-generated 
EXECUTABLES/update_engine_client_intermediates/aidl-generated
|-- include
|   `-- android
|       `-- os
|           |-- BnUpdateEngine.h
|           |-- BnUpdateEngineCallback.h
|           |-- BpUpdateEngine.h
|           |-- BpUpdateEngineCallback.h
|           |-- IUpdateEngine.h
|           `-- IUpdateEngineCallback.h
`-- src
    `-- binder_bindings
        `-- android
            `-- os
                |-- IUpdateEngine.cc
                |-- IUpdateEngine.o
                |-- IUpdateEngineCallback.cc
                `-- IUpdateEngineCallback.o

7 directories, 10 files
```
这里生成的代码跟前面的`.proto`文件就不一样了，`.proto`文件生成的代码是一对一的，一个`.proto`文件就生成一个`.h`和一个`.cpp`文件。
但这里一个`.aidl`文件似乎生成了多个`.h`和`.cc`文件，如下：
```
`IUpdateEngine.aidl`
  --> IUpdateEngine.h, IUpdateEngine.cc
  --> BnUpdateEngine.h
  --> BpUpdateEngine.h

`IUpdateEngineCallback.aidl`
  --> IUpdateEngineCallback.h, IUpdateEngineCallback.cc
  --> BnUpdateEngineCallback.h
  --> BpUpdateEngineCallback.h
```

这里生成的文件跟Binder机制有关，具体的Binder细节请自行度娘。

### 2.1 `IUpdateEngine.aidl`

简单说来，会生成一个`IUpdateEngine.h`的接口类定义文件，然后再分别生成两个Binder的Native和Proxy相关的类文件`BnUpdateEngine.h`和`BpUpdateEngine.h`，这两个文件分别用于实现Bind的Native端接口和Proxy端接口。

这3个类的继承定义如下：
```
class IUpdateEngine : public ::android::IInterface
class BpUpdateEngine : public ::android::BpInterface<IUpdateEngine>
class BnUpdateEngine : public ::android::BnInterface<IUpdateEngine>
```

这里`BpUpdateEngine`和`BnUpdateEngine`分别是继承自`BpInterface`和`BnInterface`的模板类，模板数据类型是IUpdateEngine；

实际上这里`IUpdateEngine`定义了整个服务的接口，`BnUpdateEnging`和`BpUpdateEngine`通过模板类的方式，支持所有`IUpdateEngine`的操作。

通过搜索，可以看到整个`update_engine`文件夹没有对`BpUpdateEngine`的引用，所以这个类没有被使用。除了`BpUpdateEngine`，我这里整理了下`IUpdateEngine`，`BnUpdateEngine`的在`update_engine`服务端的关系类图，如下：

![image](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/BnUpdateEngine.png?raw=true)

图1. `BnUpdateEngine`在服务端进程`UpdateEngineDaemon`中的类关系

后面深入读代码的时候再详细分析类关系。

> 这里BnInterface是一个模板类(模板数据类型是IUpdateEngine)，我在Visio上没有找到模板类如何画，所以将IUpdateEngine画成了依赖关系。有大神指导如何在Visio上话模板类的请指导下，非常感谢！

### 2.2 `IUpdateEngineCallback.aidl`

跟前面的`IUpdateEngine.aidl`一样，这里也会生成以下的类：
```
class IUpdateEngineCallback : public ::android::IInterface
class BpUpdateEngineCallback : public ::android::BpInterface<IUpdateEngineCallback> 
class BnUpdateEngineCallback : public ::android::BnInterface<IUpdateEngineCallback>
```

再次搜索，也可以看到整个`update_engine`文件夹没有对`BpUpdateEngineCallback`的引用。
以下是`IUpdateEngineCallback`，`BnUpdateEngineCallback`在客户端`update_engine_client`的关系类图，如下：

![image](https://github.com/guyongqiangx/blog/blob/dev/ab-ota/images/BnUpdateEngineCallback.png?raw=true)

图2. `BnUpdateEngineCallback`在客户端进程`UpdateEngineClientAndroid`中的类关系

有意思的是，UECallback是定义在UpdateEngineClientAndroid内部的命名空间中，两个类内部互相都有指针成员指向对方：
```
# system\update_engine\update_engine_client_android.cc
class UpdateEngineClientAndroid : public brillo::Daemon {
 ...

 private:
  # 这里定义的UECallback定义在UpdateEngineClientAndroid命名空间中
  class UECallback : public android::os::BnUpdateEngineCallback {
   public:
    explicit UECallback(UpdateEngineClientAndroid* client) : client_(client) {}

    ...

   private:
    # client_指针指向实际调用的客户端
    UpdateEngineClientAndroid* client_;
  };

  ...
  # callback_指针指向客户端需要处理的回调函数
  android::sp<android::os::BnUpdateEngineCallback> callback_;

  ...
};
```

UpdateEngineClientAndroid在OnInit()函数中用自己的this指针初始化UECallback的`client_`成员，然后类UECallback创建完毕后赋值回自己的`callback_`指针，如下：
```
# system\update_engine\update_engine_client_android.cc
int UpdateEngineClientAndroid::OnInit() {
  ...

  if (FLAGS_follow) {
    // Register a callback object with the service.
    # 先用this初始化UECallback->client_成员，然后将创建的UECallback对象赋值给自身的callback_指针
    callback_ = new UECallback(this);
    bool bound;
    # 这里将callback_对象绑定到service_对象上，后续会在service_服务中合适的时候调用callback_
    if (!service_->bind(callback_, &bound).isOk() || !bound) {
      LOG(ERROR) << "Failed to bind() the UpdateEngine daemon.";
      return 1;
    }
    keep_running = true;
  }

  ...
}
```

## 3. 其它

读到这里，难免会有疑问，分析Update Engine的代码为什么不直接进入main函数进行分析，反而在这里扯Protobuf和AIDL文件的闲篇？这里分析Protobuf和AIDL有什么用？

其实我想说，我还没有完整的看完代码，我也不知道分析Protobuf和AIDL到底会不会做无用功。

但可以肯定的是，从依赖结构看，如果要分析系统升级过程中最后patch的操作，肯定需要根据`update_metadata.proto`定义的元数据来进行分析处理；

另外，Update Engine涉及的类比较多，通过对AIDL文件的分析，很容易搞清楚service服务相关的类BnUpdateEngine和回调函数类BnUpdateEngineCallback在整个Update Engine中与其他类的关系。

## 4. 联系和福利

- 个人微信公众号“洛奇看世界”，一个大龄码农的救赎之路。
  - 公众号回复关键词“Android电子书”，获取超过150本Android相关的电子书和文档。电子书包含了Android开发相关的方方面面，从此你再也不需要到处找Android开发的电子书了。
  - 公众号回复关键词“个人微信”，获取个人微信联系方式。<font color="red">我组建了一个Android OTA的讨论组，联系我，说明Android OTA，我拉你进讨论组一起讨论。</font>

  ![image](https://img-blog.csdn.net/20180507223120679)
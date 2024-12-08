## 20240802-Android Update Engine 分析（三四）OTA 签名都支持哪些算法?

- 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
- 原文链接：


## 0. 背景

写了几十篇还没涉及到 OTA 签名算法细节，OTA 讨论群也很少问这个，毕竟签名算法纯理论的问题，一旦实现好就极少需要改动，只需要进行一些配置，准备好签名的秘钥和证书就可以了。



限于签名的算法理论太过于抽象，本篇不讨论签名算法细节，但会总结一些签名操作。以及 Android OTA 包支持的签名算法。



## 1. OTA 签名支持的算法

先说结论，到 Android 14 (版本号 android-14.0.0_r2) 为止，Android OTA 包签名支持的算法包括：

- 使用 SHA256 哈希算法，基于 PKCS v1.5 填充的 RSA2048 和 RSA4096 签名算法
- 使用 SHA256 算法，基于 NIST P-256 曲线的 ECDSA 签名算法

上面两条基本上囊括了签名算法的主要细节，如果还希望再简要一些就是：

- RSA2048 签名
- RSA4096 签名
- ECDSA 签名



## 2. 非对称秘钥体系

要谈到签名，就离不开非对称秘钥。我试图用直白的内容来介绍下非对称秘钥的概念。



### 对称秘钥

我们平时谈到的加密和解密是这样操作的：

**加密**：给定一段数据 D，用一个秘钥 K 进行加密，得到加密后的数据 E。

**解密**：然后对加密后的数据 E，再次使用秘钥 K 进行还原就可以得到原始数据 D。

这就有点像一把锁，我用一把钥匙锁上后，可以再用同一把钥匙打开。

这里加密和解密使用的秘钥是一样的，所以称为对称秘钥。



举个生活中的例子，你沿着一条台阶路从山脚下登山(加密)，到达山顶后，你还能从山顶原路返回到山脚下登山的地方(解密)，这个路径就是对称的。



### 非对称秘钥

所谓非对称秘钥，就是指加密和解密使用的秘钥是不一样的，两边操作不对称。

非对称听起来很不可思议，怎么会通过一种方法加密后，只能另外一种方法解密呢？但数学中真的存在不少这样的操作，通常叫做陷阱门(Trap Door)，只能单向通过。

生活中也有不少这样单向的例子，例如：高处水池中的水，通过水管自然留到低处的水潭中。但是，低处水潭中的水就再也没法原路返回到高处的水池中。只能通过其它途径，例如人工挑，使用机器抽等办法才能将水从水潭弄回到水池中。

所以，在这种情形下，就有两个秘钥，一个称为公钥，一个称为私钥。

所谓公钥，就是公开的那个。私钥就是只有自己持有的那个。



你通过密码学手段生成一对公钥和私钥，你把公钥向全班同学公开，每个人都知道；私钥自己持有，只有你一个人知道。关于公钥和私钥的用途，有两个典型的场景。

场景1：加密和解密

当有一个倾慕你的异性同学想给你发情书时，使用你的公钥对情书内容进行加密，因为非对称秘钥的原因，加密后的内容不能再用这个公钥解密，而只有你持有的私钥能够解密。这样就确保了她发出来的情书，即使被其它同学拿到了，因为无法解密器内容，因此只有你一个人能用私钥查看。



场景2：签名和验证签名(验签)

同样，如果你发布了一个喜欢某个同学的爱的宣言，然后提取宣言内容每一行的第一个字符，使用你的秘钥进行加密，并把加密的内容添加在宣言的结尾作为附加信息，密码学续上把这个附加信息通常称为签名(这个签名有别于手写的那个签名，但是本质是一样的)。

同学们看到这个宣言后，怎么确定这个宣言就是你发布的，而不是其他人借你的名义伪造的呢？

办法就是，他们使用手中的公钥，对爱的宣言后面附加的签名进行解密，理论上解密的内容就是由宣言每一行的第一个字符组成的。

> 因为这段数据是你使用自己的私钥加密，所以同学们可以用私钥对应的公钥进行解密

然后，再提取宣言每一行的第一个字符，通公钥解密后的内容进行比较，如果一样，那么就能确认这个宣言就是你发出的。



我们这里可以看到，签名和验签，其底层还是基于加解密实现的。



另外，对于生成的两个秘钥中，理论上哪个秘钥做公钥，哪个秘钥做私钥，都是一样的。你也可以把之前公开的那个公钥留在自己手上作为私钥，把原来自己手上的私钥公开作为公钥。之所以一个叫公钥，只不过是因为这个秘钥公开了；另外一个叫私钥，是因为那个秘钥不公开，只有你自己一个人持有。不能将两个秘钥都同时公开，那就坏事了。



总体上讲，公钥和私钥的用途可以用两句话概述：

1. 公钥加密，私钥解密
2. 私钥签名，公钥验证



## 3. 签名和验签到底是如何操作的？

### 3.1 RSA 签名和验证

我几年前写过两篇用 OpenSSL 命令和 Python 两种方式验证使用 RSA 加密/解密，以及 RSA 签名和验签。

对细节感兴趣的可以查看下面两篇文章：

- 《OpenSSL和Python实现RSA Key公钥加密私钥解密》
  - https://blog.csdn.net/guyongqiangx/article/details/74732434
- 《OpenSSL和Python实现RSA Key数字签名和验证》
  - https://blog.csdn.net/guyongqiangx/article/details/74454969



这里主要总结一些 RSA 签名和验证签名(验签)的步骤：

#### **私钥签名**

第1步，计算待签名数据的哈希值

- 具体的哈希算法可以通过参数指定，可以是 MD5, SHA256, SHA512等

第2步，对哈希结果进行 BER 编码，并使用进行填充

- 为了抵抗对 RSA 算法的攻击，需要对哈希结果进行编码和填充，填充的方式有多种，包括 PKCS v1.5 和 OAEP 等，最常见的就是 PKCS v1.5 的填充方式

第3步，使用私钥对填充后的内容进行加密得到签名结果

- 这一步才真正使用 RSA 算法进行加密，加密输出的结果就是数据的签名



#### **公钥验证**

验签方式一：

第1步，使用公钥解密签名数据

- 签名的最后一步是通过私钥加密得到的，在验签时用公钥解密签名数据

第2步，对解密的签名数据去掉填充，得到BER编码后的格式
第3步，从BER编码中提取哈希数据
第4步，计算原始数据的哈希，并同签名文件中得到的哈希进行比较

- 和签名时使用同样的算法对数据记性哈希，并和第 3 步的哈希结果进行比较



这里的第 2，3 步可以合并到一起进行。

也可以不进行第 2,3 步去掉填充提取哈希，而是计算原始数据的哈希，进行编码和填充后比较。



验签方式二：

第1步，使用公钥解密签名数据

- 签名的最后一步是通过私钥加密得到的，在验签时用公钥解密签名数据

第2步，计算原始数据的哈希

- 和签名时使用同样的算法对数据进行哈希操作

第3步，对哈希结果进行 BER 编码，并使用进行填充

- 为了抵抗对 RSA 算法的攻击，需要对哈希结果进行编码和填充，填充的方式有多种，包括 PKCS v1.5 和 OAEP 等，最常见的就是 PKCS v1.5 的填充方式

第3步，使用公钥解密签名的结果和第 3 步填充后的数据进行比较



### 3.2 EC 签名和验证

EC(Elliptic Curve，椭圆曲线)算法理论提出很多年了，但直到最近十多年随着算力的进步才开始火起来。

使用椭圆曲线的签名 ECDSA 的全称是 Elliptic Curve Digital Signature Algorithm，即椭圆曲线数字签名算法。

我研究过 ECDSA 的算法，但没有详细去研究 ECDSA 签名标准中的操作步骤，下面是基于 AI 总结的 ECDSA 签名步骤：



#### ECDSA 签名

第 1 步，对签名数据进行哈希，获取哈希值

- 具体的哈希算法可以通过参数指定，可以是 SHA256, SHA512等

第 2 步，使用随机数 k 和椭圆曲线上的基点 G，计算 R。R 是一个点在椭圆曲线上，它将是签名的一部分。

第 3 步，使用 k，R 点的 x 坐标，以及私钥计算得到结果 s

第 4 步，R 的 x 坐标以及 s 构成了数据的签名

总结起来就是两句话，对数据进行哈希，然后使用 ECDSA 算法将哈希结果转变成签名。相比于 RSA 没有了 BER 编码和密码学填充。



#### ECDSA 验签

第 1 步，对验证数据进行解密，获取哈希值

第 2 步，提取签名中的 R 和 s，通过其它方法获取 R  的坐标

第 3 步，提取的 x 坐标 x1与签名中的 r 进行比较

通过这些步骤，接收者可以验证签名是否由对应的私钥持有者生成，从而确保消息的完整性和不可否认性。



## 4. OTA 签名代码分析

制作升级包时，是什么时候进行签名的呢？

在[《Android Update Engine分析（八）升级包制作脚本分析》](https://blog.csdn.net/guyongqiangx/article/details/82871409)一文中总结过升级包 update.zip 生成的步骤，不清楚的可以再回到这篇复习一下。

在[《Android Update Engine分析（十一） 更新 payload 签名》](https://blog.csdn.net/guyongqiangx/article/details/122597314)中详细跟踪分析 payload 的签名流程。

总体上讲，`delta_generator` 中的签名代码实现位于：

- `system/update_engine/payload_generator/payload_signer.h`

- `system/update_engine/payload_generator/payload_signer.cc`

> 在线代码：http://aospxref.com/android-14.0.0_r2/xref/system/update_engine/payload_generator/payload_signer.cc



从头文件 `payload_signer.h` 中可以看到，跟签名(sign)相关的函数有三个，分别是：

- `SignHash()`
- `SignHashWithKeys()`
- `SignPayload()`

查看函数代码就会发现，`SignPayload()` 内部通过 `SignHashWithKeys()` 来实现，而对于后者，又是通过调用 `SignHash()` 来实现。

因此，最终关于签名的函数就只有一个，即：`SignHash()`

关于 `SignHash()` 的粗略注释如下：

### 4.1 RSA 签名

![1727274390190](C:\Work\github\blog\draft\Android Update Engine 分析\images-20240802-Android Update Engine 分析（三四）OTA 签名都支持哪些算法\01-SignHash.png)

从这里的代码中看不出来支持哪些 RSA 长度的算法，但我们不妨看下 SHA256 哈希的填充函数：`PadRSASHA256Hash()`

密码学标准中，对 RSA 签名，要求对数据先进行哈希操作，获取哈希结果，然后根据 RSA 密钥强度(长度)，对哈希结果进行填充。

- 对于 RSA2048，在用 RSA Key 加密前需要将哈希数据填充到 256 字节；

- 对于 RSA4096，在用 RSA Key 加密前，需要将哈希数据填充到 512 字节；

![ab43245dcf017475552d69d6d3b8d62](C:\Work\github\blog\draft\Android Update Engine 分析\images-20240802-Android Update Engine 分析（三四）OTA 签名都支持哪些算法\02-PadRSASHA256Hash.png)

### 4.2 ECDSA 签名

![4996986f37ca9a949b76d6b0edf7e8f](C:\Work\github\blog\draft\Android Update Engine 分析\images-20240802-Android Update Engine 分析（三四）OTA 签名都支持哪些算法\03-ECDSA-Signing.png)

与 RSA 签名比起来，ECDSA 签名的步骤相对少一些，直接对 SHA256 的哈希结果进行 ECDSA 的加密。

特别留意的是，不论是 RSA2048/RSA4096 还是 ECDSA 签名结果，这里最后都转换成小端字节序。

## 5. OTA 验签代码分析

对于 `delta_generator` 工具，当传入 payload 文件和公钥 public key 时，会使用这个公钥去验证 payload 中的签名，命令如下：

```shell
delta_generator --in_file=payload.bin --public_key=key-pub.key
```

在 [《Android Update Engine 分析（十二） 验证 payload 签名》](https://blog.csdn.net/guyongqiangx/article/details/122634221)中有对使用 `delta_generator` 工具验证签名的流程进行详细分析。



除了 `delta_generator` 可以验证签名外，实际上在 OTA 升级过程中，接收完 metadata 以及整个 payload 数据后，也会验证相应的签名。

验证签名的代码位于：

- `system/update_engine/payload_consumer/payload_verifier.h`
- `system/update_engine/payload_consumer/payload_verifier.cc`

> 在线代码：http://aospxref.com/android-14.0.0_r2/xref/system/update_engine/payload_consumer/payload_verifier.cc

### 5.1 升级验证签名的时机

前面简略提到，在 OTA 升级过程中，在接收完 metadata 以及整个 payload 数据后，会验证相应签名。

#### metadata 的签名

关于 metadata 的验证流程大概是这样的：

在升级开始后，`update_engine` 服务端进程会根据应用程传入的地址参数，从远程服务器获取 payload 数据，每收到一小段数据，就会调用 `DeltaPerformer::Write()` 函数进行处理。

`DeltaPerformer::Write()` 会不断检查当前下载数据的进度，当已经接收到完整的 payload 头部的 metadata 后，就会调用函数 `DeltaPerformer::ParsePayloadMetadata()` 解析 metadata，其中一个操作就是使用函数 `PayloadMetadata::ValidateMetadataSignature()` 去验证 metadata 的签名。

在`PayloadMetadata::ValidateMetadataSignature()`中，实际上是调用 `PayloadVerifier::VerifyRawSignature()`或`PayloadVerifier::VerifySignature()` 进行操作，从而验证 metadata 签名。

![1727279796327](C:\Work\github\blog\draft\Android Update Engine 分析\images-20240802-Android Update Engine 分析（三四）OTA 签名都支持哪些算法\04-ValidateMetadataSignature.png)

> 在线代码: http://aospxref.com/android-14.0.0_r2/xref/system/update_engine/payload_consumer/payload_metadata.cc#156

#### payload 签名

对于整个 payload 数据，一边下载数据，一边对接收到的数据累积计算哈希，等到全部的 payload 都接收完，整个 payload 的哈希也计算出来了。

此时，在 `DownloadAction::TransferComplete()`中，调用 `VerifyPayload()` 函数校验整个 payload 的哈希：

![1727281274073](C:\Work\github\blog\draft\Android Update Engine 分析\images-20240802-Android Update Engine 分析（三四）OTA 签名都支持哪些算法\05-VerifyPayload.png)

在这里的 `VerifyPayload()`函数内部，调用函数`PayloadVerifier::VerifySignature()`完成签名的检查。



### 5.2 RSA 验签

在下载 OTA 的过程中，会不断计算 payload 数据的 SHA256 哈希，当数据 payload 下载完毕，我们同时也就拿到整个 payload 哈希了。

因此这里的 RSA 验签时，直接使用 RSA 的公钥解密签名数据，将解密后的数据和填充后的 SHA256 哈希进行比较即可。

![be6f3d558b0ddf3155c358f554ce184](C:\Work\github\blog\draft\Android Update Engine 分析\images-20240802-Android Update Engine 分析（三四）OTA 签名都支持哪些算法\06-VErifyRawSignature-RSA.png)

### 5.3 ECDSA 验签

ECDSA 签名时，不需要像 RSA 那样要对哈希进行填充，因此更简单直接：

使用公钥经过 ECDSA 算法解密，将解密数据和下载中计算得到的 SHA256 哈希进行比较。


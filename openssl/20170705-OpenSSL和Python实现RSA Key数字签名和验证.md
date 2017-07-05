基于非对称算法的RSA Key主要有两个用途，数字签名和验证（私钥签名，公钥验证），以及非对称加解密（公钥加密，私钥解密）。本文提供一个基于OpenSSL命令行和Python的数字签名和验证过程的例子，另外会另起一篇使用OpenSSL和Python进行非对称加解密的例子。

## 1. OpenSSL实现数字签名和验证

### 1.1 生成私钥

生成2048 bit的PEM格式的RSA Key：Key.pem
```
# 生成私钥文件Key.pem
$ openssl genrsa -out Key.pem -f4 2048
Generating RSA private key, 2048 bit long modulus
.+++
...................................................................+++
e is 65537 (0x10001)
# 查看私钥文件内容
$ cat Key.pem 
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEAoZZKNO89UcDkEgdulOtAK0d9dQ0xfnpt4QNUg16ISeNuAFYv
OeXn/ToGounX67+bkYpH92dXCnNpOsERLogenWQT533tsRU9KByeCz+PRgjc5cBn
wAA6z+F7JFUkY3GAaZDe7dmSIES/FH+9YKjRSe7+h2sF7va3tGPn8cLpDUoLLk2e
ugWvmuWgEpCE6Wyed7UV3Vzdf2R+9oya9jkAoHI14hrz3xDssg0wlHqbptwsmwAQ
1ZBDSB1MpqaLCaUvV8NvtSBLDsZlzwkOj7bPiFZJRFIqRRg0UNWkUBR+BJhWZ7Zc
Dud2kJcH0mX8/rfthfFa5Oy38Iz8UQOW0uZRlQIDAQABAoIBABTN+uPx4Z1DDppb
pps55tsrqzWE61hzfu43tYvsgfOxeppEfnQf68yoye3z2b8avnbwrO9nuMc5sNTF
wuaQ1BBDsGRfzFi+eU9Oz/J2zoWf4oEaUsFfxjK5v1cgNz0ugfAVnP5Wwv+wmkGT
aNinI7s3MEJTP0JTNbfeHSD9jXAOYhXH1M6/gq+TxLlsFISbQgmIbnDkDU/biXC+
b4r4/3xBieaeYOSV5s7pziXcxPmZCrWdcggtcxxJeDFtvQbSU4PXM7n7NgcsGQiX
kwlHF3TiSQpQRuthV1ioW4FFFtwKw38mwzYcexem5Pyv353xSfb4vGg2+mcUEaf9
oNYYasECgYEA0tpP8th2L1zVT4eyumE5KE95iH4Nr6RWkQpfWQ84MDmiK7cNFeBL
0l4kwUo4oQeNEfDHYlxZ/guaflDLOKJ7DampMEuc+Dl8hmwXhdhqeQzxNRnaoDV1
iIyyHUs9c/9ormjTsycas2VfH1sPm3SrwH2rQe4ttkVBS8mcouNlg3kCgYEAxC+G
qgsN+IifgVoeHIw2ak0MxTdt0LfGWcygx4hzXCpYrnqns080Z4vGDxClhqfdM9OJ
0Y6GkaNIHay/4bUIsBYFoV78vV80oQykHs6nwdJqLZJeQohBUlO2LlGzatPtWWuc
v3N9W/OjSd3q6UgApmFT4+cMmEUZjB7QsHhau/0CgYBRotDdd02a3NiB6Eocu1PD
9bFaVWO7I2eY1GlCNBBPK6FMR507YRI6KtUUOUZfomrODWlE/fih0aBJU8K69L2r
9opY9o2Z1bgO237oBXiD0az6ID5zVP9ilQbJLL5oUPUYweFlNbiyyIbhvwH18GAn
MQDDkBIGxh2X2EFbF6vQEQKBgHW5Bxe2dnWylfQqvXLn+CclgQo+zpi2DkIIdloF
WSPvDTP1yffhCVMxHnIfzRPWWvgkccjbu4hc8INOC/5GgaYYMNy6gPKp1IznZvxN
iYDW4HvkHsfRt1DNhr6YrA7oiL5lwrNne8vXkR5cGgBOAoXUVWCmXnpozIG2ZAfg
0KGJAoGANO46bePCNaVlP37hW3vjraW4gzKPS0xscG7pLnLrv+T628PnFS7j7D7a
6v6BBBSgBTFnuEOk2F4bfIRvE04m2S9vzg6Mt2aJHn6RQjQVZPZF+qFvrXxjzqRU
4R+06Hk2Zm2D3x/XJTu2QmzT1kqp6AtsnfOCz3M0a1oyd5eCVdk=
-----END RSA PRIVATE KEY-----
```

### 1.2 导出公钥

从私钥导出公钥：Key_pub.pem

```
# 从私钥导出公钥，很简单，使用参数-pubout就可以
$ openssl rsa -in Key.pem -pubout -out Key_pub.pem
writing RSA key
# 查看公钥文件内容
$ cat Key_pub.pem 
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoZZKNO89UcDkEgdulOtA
K0d9dQ0xfnpt4QNUg16ISeNuAFYvOeXn/ToGounX67+bkYpH92dXCnNpOsERLoge
nWQT533tsRU9KByeCz+PRgjc5cBnwAA6z+F7JFUkY3GAaZDe7dmSIES/FH+9YKjR
Se7+h2sF7va3tGPn8cLpDUoLLk2eugWvmuWgEpCE6Wyed7UV3Vzdf2R+9oya9jkA
oHI14hrz3xDssg0wlHqbptwsmwAQ1ZBDSB1MpqaLCaUvV8NvtSBLDsZlzwkOj7bP
iFZJRFIqRRg0UNWkUBR+BJhWZ7ZcDud2kJcH0mX8/rfthfFa5Oy38Iz8UQOW0uZR
lQIDAQAB
-----END PUBLIC KEY-----
```

### 1.3 准备签名数据

为了简单起见，生成16字节全0的数据作为测试文件：data.bin

```
# 使用dd命令生成16字节的data.bin
$ dd if=/dev/zero of=data.bin bs=1 count=16
16+0 records in
16+0 records out
16 bytes (16 B) copied, 0.000189593 s, 84.4 kB/s
# 使用hexdump查看data.bin的内容，16个字节全都是0
$ hexdump -Cv data.bin 
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00000010
```

### 1.4 计算sha256哈希

直接计算data.bin的sha256哈希值：
```
# 调用openssl dgst计算sha256
$ openssl dgst -sha256 data.bin 
SHA256(data.bin)= 374708fff7719dd5979ec875d56cd2286f6d3cf7ec317a3b25632aab28ec37bb
```

也可以将data.bin的sha256哈希值存储到单独的文件：data.bin.sha256
```
# 将sha256结果输出到文件data.bin.sha256
$ openssl dgst -sha256 -binary -out data.bin.sha256 data.bin    
# 使用hexdump查看data.bin.sha256文件的内容
$ hexdump -Cv data.bin.sha256 
00000000  37 47 08 ff f7 71 9d d5  97 9e c8 75 d5 6c d2 28  |7G...q.....u.l.(|
00000010  6f 6d 3c f7 ec 31 7a 3b  25 63 2a ab 28 ec 37 bb  |om<..1z;%c*.(.7.|
00000020
```

### 1.5 私钥签名

对数据data.bin使用私钥Key.pem进行签名，生成签名文件：data.bin.signature

```
# 使用Key.pem对data.bin进行签名，并将签名结果输出到文件data.bin.signature
$ openssl dgst -sha256 -out data.bin.signature -sign Key.pem data.bin
# 使用hexdump查看签名结果文件data.bin.signature的内容
$ hexdump -Cv data.bin.signature 
00000000  7e 59 0f b5 b2 d9 31 f6  af 95 34 79 8d d8 5a a4  |~Y....1...4y..Z.|
00000010  69 02 b9 29 a9 f5 1d 00  6d 84 93 69 8c 65 d3 c9  |i..)....m..i.e..|
00000020  9b 6e 52 48 46 c7 1a b2  71 83 c6 6e 2e bb 6a b0  |.nRHF...q..n..j.|
00000030  bb cf 48 16 49 4d 57 f7  9b e9 0c a6 87 7b 15 cd  |..H.IMW......{..|
00000040  f0 ef ac 39 47 ff 81 95  20 eb 67 29 f4 bb 90 bb  |...9G... .g)....|
00000050  a2 f8 77 5b 14 14 e4 41  26 cc 1a cd 79 22 de 50  |..w[...A&...y".P|
00000060  d6 c3 8c bc 79 68 38 1d  0c 65 fc 21 72 48 a9 97  |....yh8..e.!rH..|
00000070  4c 55 fc 7e 33 7b 65 0c  d9 67 2c 64 01 3f 81 5b  |LU.~3{e..g,d.?.[|
00000080  50 16 54 12 7a eb 96 b8  26 a2 13 28 68 8a 6e 7e  |P.T.z...&..(h.n~|
00000090  b9 12 ee 49 3e 51 5c 43  ff fd 5d 3a 90 5e 5f 2f  |...I>Q\C..]:.^_/|
000000a0  f1 4e 93 73 aa 86 6f 00  e2 b6 0d dc 3d dd 90 da  |.N.s..o.....=...|
000000b0  df 7b e7 ae 15 2b 55 04  81 af c3 16 c6 36 79 3b  |.{...+U......6y;|
000000c0  74 63 7b 72 f1 ac c8 9f  6f c0 4f 45 74 36 38 27  |tc{r....o.OEt68'|
000000d0  73 2b c2 0b 99 ca 58 14  2b 1e 39 d9 6d 8b 5d e3  |s+....X.+.9.m.].|
000000e0  05 40 99 ef 0e 47 e8 e0  ec d4 c6 f6 a3 50 55 0e  |.@...G.......PU.|
000000f0  4a 00 50 d3 80 a0 61 73  38 3a 98 57 15 11 eb 47  |J.P...as8:.W...G|
00000100
```

这里使用：
- `-out`选项指定将签名结果存放到data.bin.signature
- `-sign`选项指定签名使用的私钥Key.pem

这里data.bin.signature是如何生成的呢？
- 第1步，计算sha256的哈希值
- 第2步，对sha256哈希结果进行BER编码，并使用PKCS #1.5进行填充
- 第3步，使用私钥对第2步填充后的内容进行加密得到签名结果

下一节会对这个操作进行验证

### 1.6 公钥验证

使用公钥Key_pub.pem验证签名文件data.bin.signature：
```
$ openssl dgst -sha256 -verify Key_pub.pem -signature data.bin.signature data.bin
Verified OK
```

这里使用：
- `-verify`选项指定用于验证签名的公钥文件
- `-signature`选项指定需要待验证的签名，此处指定待验证的签名文件时data.bin.signature文件

输出比较简单，只显示了验证结果为"Verified OK"。

根据上一节签名结果的生成过程，我们不妨反推下验证过程：
- 第1步，使用公钥解密签名数据
- 第2步，对解密的签名数据去掉填充，得到BER编码后的格式
- 第3步，从BER编码中提取哈希数据
- 第4步，计算原始数据的sha256哈希，并同签名文件中得到的哈希进行比较

找遍了`openssl`的命令，就是没有找到如何使用公钥进行解密的~~
我所知的OpenSSL跟解密相关的两个命令：
- `openssl rsautl -decrypt` 需要指定私钥进行解密
- `openssl enc -d` 基于对称密钥进行解密，这里的非对称加解密显然不适合

哪位大神知道的请指点下，这里如何使用公钥解密签名数据？

不过，OpenSSL提供了一个命令`openssl rsautil -verify`，该命令使用公钥验证签名，可以使用这个命令来达到解密签名数据的效果：
- 解密原始的签名数据（使用BER编码，且带PKCS #1.5填充）
```
$ openssl rsautl -in data.bin.signature -inkey Key_pub.pem -pubin -verify -hexdump -raw
0000 - 00 01 ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0010 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0020 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0030 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0040 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0050 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0060 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0070 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0080 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
0090 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
00a0 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
00b0 - ff ff ff ff ff ff ff ff-ff ff ff ff ff ff ff ff   ................
00c0 - ff ff ff ff ff ff ff ff-ff ff ff ff 00 30 31 30   .............010
00d0 - 0d 06 09 60 86 48 01 65-03 04 02 01 05 00 04 20   ...`.H.e....... 
00e0 - 37 47 08 ff f7 71 9d d5-97 9e c8 75 d5 6c d2 28   7G...q.....u.l.(
00f0 - 6f 6d 3c f7 ec 31 7a 3b-25 63 2a ab 28 ec 37 bb   om<..1z;%c*.(.7.
```

- 解密原始的签名数据（BER编码，但不带填充）
```
$ openssl rsautl -in data.bin.signature -inkey Key_pub.pem -pubin -verify -hexdump
0000 - 30 31 30 0d 06 09 60 86-48 01 65 03 04 02 01 05   010...`.H.e.....
0010 - 00 04 20 37 47 08 ff f7-71 9d d5 97 9e c8 75 d5   .. 7G...q.....u.
0020 - 6c d2 28 6f 6d 3c f7 ec-31 7a 3b 25 63 2a ab 28   l.(om<..1z;%c*.(
0030 - ec 37 bb                                          .7.
```

填充与不填充的区别在于`-raw`选项。

以上操作以签名结果data.bin.signature作为输入，并非使用原始数据data.bin作为输入。对比sha256的输出文件data.bin.sha256，解密结果的最后32个字节（对于填充输出，刚好是最后两行）就是原始数据的哈希，所以验证成功。

## 2. Python实现数字签名和验证

Python签名和验证操作复用OpenSSL生成的文件：
- 私钥 Key.pem
- 公钥 Key_pub.pem
- 数据 data.bin

### 2.1 安装`cryptography`库

数字签名和验证基于Python3下的`cryptograhpy`库，所以需要预先安装：
```
$ sudo pip3 install cryptography
```

由于`cryptography`依赖于`cffi`库，安装中可能会出错，此时只需要先安装`libcffi-dev`，再重新安装就好了。
```
$ sudo apt-get install libffi-dev
```

> 本文验证环境：
> ```
> $ python3 --version
> Python 3.4.3
> $ pip3 list
> ...
> cryptography (1.9)
> ...
> ```
>
> `cryptograhpy`库的官方文档： [https://cryptography.io/en/latest/](https://cryptography.io/en/latest/)

### 2.2 私钥签名

`rsa-sign.py`使用指定的私钥Key.pem对数据文件data.bin进行签名，并将签名结果输出到文件signature.bin中，代码如下：

```python

# 导入cryptography库的相关模块和函数
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding


# 签名函数
def sign(data_file_name, signature_file_name, private_key_file_name):
    """
    签名函数使用指定的私钥Key对文件进行签名，并将签名结果写入文件中
    :param data_file_name: 待签名的数据文件
    :param signature_file_name: 存放签名结果的文件
    :param private_key_file_name: 用于签名的私钥文件
    :return: 签名数据
    """

    # 读取待签名数据
    data_file = open(data_file_name, 'rb')
    data = data_file.read()
    data_file.close()

    # 从PEM文件中读取私钥数据
    key_file = open(private_key_file_name, 'rb')
    key_data = key_file.read()
    key_file.close()

    # 从PEM文件数据中加载私钥
    private_key = serialization.load_pem_private_key(
        key_data,
        password=None,
        backend=default_backend()
    )

    # 使用私钥对数据进行签名
    # 指定填充方式为PKCS1v15
    # 指定hash方式为sha256
    signature = private_key.sign(
        data,
        padding.PKCS1v15(),
        hashes.SHA256()
    )

    # 将签名数据写入结果文件中
    signature_file = open(signature_file_name, 'wb')
    signature_file.write(signature)
    signature_file.close()

    # 返回签名数据
    return signature


if __name__ == '__main__':
    # 指定数据文件
    data_file = r'data.bin'
    # 指定签名结果文件
    signature_file = r'signature.bin'
    # 指定签名的私钥
    private_key_file = r'Key.pem'

    # 签名并返回签名结果
    signature = sign(data_file, signature_file, private_key_file)
    # 打印签名数据
    [print('%02x' % x, end='') for x in signature]
```

运行，控制台会打印一长窜签名结果数据：
```
$ python3 rsa-sign.py 
7e590fb5b2d931f6af9534798dd85aa46902b929a9f51d006d8493698c65d3c99b6e524846c71ab27183c66e2ebb6ab0bbcf4816494d57f79be90ca6877b15cdf0efac3947ff819520eb6729f4bb90bba2f8775b1414e44126cc1acd7922de50d6c38cbc7968381d0c65fc217248a9974c55fc7e337b650cd9672c64013f815b501654127aeb96b826a21328688a6e7eb912ee493e515c43fffd5d3a905e5f2ff14e9373aa866f00e2b60ddc3ddd90dadf7be7ae152b550481afc316c636793b74637b72f1acc89f6fc04f4574363827732bc20b99ca58142b1e39d96d8b5de3054099ef0e47e8e0ecd4c6f6a350550e4a0050d380a06173383a98571511eb47
```
比较Python脚本生成的签名文件signature.bin和使用OpenSSL计算得到的结果：
```
$ md5sum data.bin.signature signature.bin           
2778de7c17b259d8d0a34538622e2338  data.bin.signature
2778de7c17b259d8d0a34538622e2338  signature.bin
```
二者的md5结果一致，说明其内容是一样的。


### 2.3 公钥验证

`rsa-verify.py`使用指定的公钥Key.pem对对上一节生成的签名文件signature.bin进行验证，代码如下：

```
#!/usr/bin/env python3

# 导入cryptography库的相关模块和函数
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

from cryptography.exceptions import InvalidSignature

# 验证函数
def verify(data_file_name, signature_file_name, public_key_file_name):
    """
    验证函数使用指定的公钥对签名结果进行验证
    :param data_file_name: 原始数据文件
    :param signature_file_name: 签名验证文件
    :param public_key_file_name: 用于验证的公钥文件
    :return: 成功返回True, 失败返回False
    """

    # 读取原始数据
    data_file = open(data_file_name, 'rb')
    data = data_file.read()
    data_file.close()

    # 读取待验证的签名数据
    signature_file = open(signature_file_name, 'rb')
    signature = signature_file.read()
    signature_file.close()

    # 从PEM文件中读取公钥数据
    key_file = open(public_key_file_name, 'rb')
    key_data = key_file.read()
    key_file.close()

    # 从PEM文件数据中加载公钥
    public_key = serialization.load_pem_public_key(
        key_data,
        backend=default_backend()
    )

    # 验证结果，默认为False
    verify_ok = False

    try:
        # 使用公钥对签名数据进行验证
        # 指定填充方式为PKCS1v15
        # 指定hash方式为sha256
        public_key.verify(
            signature,
            data,
            padding.PKCS1v15(),
            hashes.SHA256()
        )
    # 签名验证失败会触发名为InvalidSignature的exception
    except InvalidSignature:
        # 打印失败消息
        print('invalid signature!')
    else:
        # 验证通过，设置True
        verify_ok = True

    # 返回验证结果
    return verify_ok


if __name__ == '__main__':
    data_file = r'data.bin'
    signature_file = r'signature.bin'
    public_key_file = r'Key_pub.pem'

    verify_ok = verify(data_file, signature_file, public_key_file)
    if verify_ok:
        print('verify ok!')
    else:
        print('verify fail!')
```

运行脚本，对前一节生成的签名数据进行验证，控制台打印"verify ok!"：
```
$ python3 rsa-verify.py 
verify ok!
```

### 2.4 源码下载

点击这里下载本文提到的Python源码：[example-rsa-sign.tar.bz2](https://github.com/guyongqiangx/blog/blob/dev/openssl/source/example-rsa-sign.tar.bz2?raw=true)
用私钥对二进制文件进行签名时，在生成文件中，除了包含原始数据和签名结果外，往往还包含了私钥对应的公钥数据，包括公钥指数Exponent(e)和模数Modulus(n)。程序需要从二进制文件中提取(e, n)构建公钥，再使用构建的公钥对数据签名进行验证。

本文演示Python如何从一个签名的二进制文件中提取(e, n)来构建公钥。

# 1. 公钥数据

用私钥对数据文件data.bin签名时，签名工具同时也将模数n嵌入到生成文件中了，原始key的Modulus与嵌入的模数n对比如下：

![原始key与嵌入公钥指数对比](https://github.com/guyongqiangx/blog/blob/dev/openssl/images/pub-key-in-big-vs-little-endian.png?raw=true)

- 左边

  - openssl 工具生成的模数Modulus，其按照big endian的格式使用和存储
  - 公钥指数 65537


- 右边

  - 签名工具将模数以little endian格式嵌入到生成文件中
  - 没有嵌入公钥指数，默认为65537

因此在从二进制文件中提取公钥模数时，需要将little endian的数据转换为big endian格式。

# 2. 从Exponent和Modulus数据(e, n)构建公钥

Python的第三方库`cryptography`提供了类RSAPublicNumbers和RSAPrivateNumbers用于从各个指数加载并转化为公钥和私钥数据。

> 安装`cryptography`库
>
> ```
> $ sudo pip3 install cryptography
> ```
>
> 由于`cryptography`依赖于`cffi`库，安装中可能会出错，此时只需要先安装`libcffi-dev`，再重新安装就好了。
> ```
> $ sudo apt-get install libffi-dev
> ```

先使用(e, n)数据初始化RSAPublicNumbers，再通过方法public_key得到公钥，示例代码片段如下：

```
# construct public modulus n and exponent e
n = int(...)
e = 65537

# use (e, n) to initialize RSAPublicNumbers, then use public_key method to get public key
key = rsa.RSAPublicNumbers(e, n).public_key(default_backend())
# use public key to do other stuffs
...

```

> `pyOpenSSL`库没有提供直接用各指数构建公钥和私钥的接口，但是类PKey提供了方法：
>
> - `from_cryptography_key`
> - `from_cryptography_key`
> 用于同`cryptography`库的`crypto_key`之间进行转换。

# 3. 提取公钥

在进行签名验证时，需要打开文件，提取模数n并构建公钥。

## 3.1 第一版代码

我的第一版代码是从0x260-0x35F处以小端方式提取二进制数据，然后将其转换为大端格式的字符串，再将字符串转换为大整数用于构建公钥，代码如下：

```
#
# pupulate-pub-key-v1.py
#
import struct

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import rsa


# 从little-endian格式的数据缓冲data中解析公钥模数并构建公钥
def populate_public_key(data):
    # 先将little-endian格式的数据转换为big-endian格式的字符串
    msb_key_str = ''

    # 从缓冲末端逐个对数据进行操作，将其转换为大端格式的字符串
    for idx in range(len(data), 0, -4):
        msb_key_str += '%08x' % struct.unpack('<I', data[idx-4:idx])[0]

    # print('msb key str: %s' % msb_key_str)

    # 将16进制大端格式字符串转换为大整数
    # convert msb_key_str to integer
    n = int(msb_key_str, 16)
    e = 65537

    # 使用(e, n)初始化RSAPublicNumbers，并通过public_key方法得到公钥
    # construct key with parameter (e, n)
    key = rsa.RSAPublicNumbers(e, n).public_key(default_backend())

    return key

if __name__ == '__main__':
    data_file = r'data.bin.sign'

    # 读取数据文件，并从中提取公钥 
    with open(data_file, 'rb') as f:
        # 将数据读取到缓冲data
        data = f.read()

        # little-endian格式的公钥模数存放在0x260-0x35F处，将其传入populate_public_key进行解析
        pub_key = populate_public_key(data[0x260:0x360])
        print(pub_key)

```

## 3.2 第二版代码

多年来已经完全习惯了先进行大小端转换，然后再对转换的数据进行操作的思维。
好吧，在Python下，这种思维完全out了。

偶然发现直接使用内置的`int.from_bytes`和`int.to_bytes`在`int`和`bytes`类型间转换很方便有木有？
至于大小端嘛，转换时设置`byteorder`为`big`/`little`就搞定了……

以下是第二版代码，真的很简洁：

```
#
# pupulate-pub-key-v2.py
#
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import rsa

# 从little-endian格式的数据缓冲data中解析公钥模数并构建公钥
def populate_public_key(data):
    # convert bytes to integer with int.from_bytes
    # 指定从little格式将bytes转换为int，一句话就得到了公钥模数，省了多少事
    n = int.from_bytes(data, byteorder='little')
    e = 65537

    # 使用(e, n)初始化RSAPublicNumbers，并通过public_key方法得到公钥
    # construct key with parameter (e, n)
    key = rsa.RSAPublicNumbers(e, n).public_key(default_backend())

    return key


if __name__ == '__main__':
    data_file = r'data.bin.sign'

    # 读取数据文件，并从中提取公钥 
    with open(data_file, 'rb') as f:
        # 将数据读取到缓冲data
        data = f.read()

        # little-endian格式的公钥模数存放在0x260-0x35F处，将其传入populate_public_key进行解析
        pub_key = populate_public_key(data[0x260:0x360])
        print(pub_key)
```

# 4. 将公钥输出到PEM文件

既然都已经成功构建公钥了，不妨再多一步，将公钥保存为pem文件，代码如下：
```
#
# pupulate-pub-key-v3.py
#
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

# 从little-endian格式的数据缓冲data中解析公钥模数并构建公钥
def populate_public_key(data):
    # convert bytes to integer with int.from_bytes
    # 指定从little格式将bytes转换为int，一句话就得到了公钥模数，省了多少事
    n = int.from_bytes(data, byteorder='little')
    e = 65537

    # 使用(e, n)初始化RSAPublicNumbers，并通过public_key方法得到公钥
    # construct key with parameter (e, n)
    key = rsa.RSAPublicNumbers(e, n).public_key(default_backend())

    return key


# 将公钥以PEM格式保存到文件中
def save_pub_key(pub_key, pem_name):
    # 将公钥编码为PEM格式的数据
    pem = pub_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )

    # print(pem)

    # 将PEM个数的数据写入文本文件中
    with open(pem_name, 'w+') as f:
        f.writelines(pem.decode())

    return

if __name__ == '__main__':
    data_file = r'data.bin.sign'

    # 读取数据文件，并从中提取公钥 
    with open(data_file, 'rb') as f:
        # 将数据读取到缓冲data
        data = f.read()

        # little-endian格式的公钥模数存放在0x260-0x35F处，将其传入populate_public_key进行解析
        pub_key = populate_public_key(data[0x260:0x360])

        # 将公钥输出到pub_key.pem文件中
        pem_file = r'pub_key.pem'
        save_pub_key(pub_key, pem_file)
```

查看公钥输出的PEM文件：
```
$ cat pub_key.pem 
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuZ6gqkv2f16lSAfWSMXA
L6DXaG6Cwz0S/R5+oQFkBS0CLKzHxm6QKv2Esf9Fh8EJR0BI+cL44s5V++WRjEcW
USBGIntQ4vXoqAuWCKY6G9YFcboHEK44mswrNgcsuhwib7+HHHFr4He940rMaSLT
ce9bSZOHWMQ83WSJpJm1Aoz8QVYL3Wnvm5uo0+sL9/XRRsan2BKm7A/HjvWiKj2I
eIiXNMppha3sHWeoC2C9PGRC3PN5C0GXzQmAVnxaClGKyUX06NloxBARuDRUmVs+
8tqr7x9yAKi1ObajEwMaesNg58vZVUZjZqeVOtwgFQkQw/r9xHN+vOk39soZkfFo
YwIDAQAB
-----END PUBLIC KEY-----
```

或者以明文方式查看：
```
$ openssl rsa -in pub_key.pem -pubin -text      
Public-Key: (2048 bit)
Modulus:
    00:b9:9e:a0:aa:4b:f6:7f:5e:a5:48:07:d6:48:c5:
    c0:2f:a0:d7:68:6e:82:c3:3d:12:fd:1e:7e:a1:01:
    64:05:2d:02:2c:ac:c7:c6:6e:90:2a:fd:84:b1:ff:
    45:87:c1:09:47:40:48:f9:c2:f8:e2:ce:55:fb:e5:
    91:8c:47:16:51:20:46:22:7b:50:e2:f5:e8:a8:0b:
    96:08:a6:3a:1b:d6:05:71:ba:07:10:ae:38:9a:cc:
    2b:36:07:2c:ba:1c:22:6f:bf:87:1c:71:6b:e0:77:
    bd:e3:4a:cc:69:22:d3:71:ef:5b:49:93:87:58:c4:
    3c:dd:64:89:a4:99:b5:02:8c:fc:41:56:0b:dd:69:
    ef:9b:9b:a8:d3:eb:0b:f7:f5:d1:46:c6:a7:d8:12:
    a6:ec:0f:c7:8e:f5:a2:2a:3d:88:78:88:97:34:ca:
    69:85:ad:ec:1d:67:a8:0b:60:bd:3c:64:42:dc:f3:
    79:0b:41:97:cd:09:80:56:7c:5a:0a:51:8a:c9:45:
    f4:e8:d9:68:c4:10:11:b8:34:54:99:5b:3e:f2:da:
    ab:ef:1f:72:00:a8:b5:39:b6:a3:13:03:1a:7a:c3:
    60:e7:cb:d9:55:46:63:66:a7:95:3a:dc:20:15:09:
    10:c3:fa:fd:c4:73:7e:bc:e9:37:f6:ca:19:91:f1:
    68:63
Exponent: 65537 (0x10001)
writing RSA key
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuZ6gqkv2f16lSAfWSMXA
L6DXaG6Cwz0S/R5+oQFkBS0CLKzHxm6QKv2Esf9Fh8EJR0BI+cL44s5V++WRjEcW
USBGIntQ4vXoqAuWCKY6G9YFcboHEK44mswrNgcsuhwib7+HHHFr4He940rMaSLT
ce9bSZOHWMQ83WSJpJm1Aoz8QVYL3Wnvm5uo0+sL9/XRRsan2BKm7A/HjvWiKj2I
eIiXNMppha3sHWeoC2C9PGRC3PN5C0GXzQmAVnxaClGKyUX06NloxBARuDRUmVs+
8tqr7x9yAKi1ObajEwMaesNg58vZVUZjZqeVOtwgFQkQw/r9xHN+vOk39soZkfFo
YwIDAQAB
-----END PUBLIC KEY-----
```

很好，很方便。

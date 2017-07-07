基于非对称算法的RSA Key主要有两个用途，数字签名和验证（私钥签名，公钥验证），以及非对称加解密（公钥加密，私钥解密）。本文提供一个基于OpenSSL和Python进行非对称加解密的例子。

## 1. OpenSSL实现非对称加解密

### 1.1 生成私钥，并导出公钥

生成2048 bit的PEM格式的RSA Key：Key.pem
```
$ openssl genrsa -out Key.pem -f4 2048
Generating RSA private key, 2048 bit long modulus
.+++
...................................................................+++
e is 65537 (0x10001)
```

从私钥导出公钥：Key_pub.pem

```
$ openssl rsa -in Key.pem -pubout -out Key_pub.pem
writing RSA key
```

### 1.2 准备测试数据

为了简便起见，这里将字符串"Hello Rocky!"存放到文件msg.bin作为测试数据：
```
$ echo -n "Hello Rocky!" > msg.bin
$ hexdump -Cv msg.bin 
00000000  48 65 6c 6c 6f 20 52 6f  63 6b 79 21              |Hello Rocky!|
0000000c
```

### 1.3 公钥加密

使用公钥Key_pub.pem对测试数据msg.bin进行加密生成msg.bin.enc，并查看加密后的数据：
```
$ openssl rsautl -in msg.bin -out msg.bin.enc -inkey Key_pub.pem -pubin -encrypt -pkcs
$ hexdump -Cv msg.bin.enc 
00000000  8d a3 c8 7f fd 4c 32 ee  29 58 c8 38 56 bd 8b 78  |.....L2.)X.8V..x|
00000010  cc eb ae f5 fa 1f 79 bb  4c 9c f1 39 34 75 94 62  |......y.L..94u.b|
00000020  97 59 c7 28 b3 c4 6a 0c  41 18 d6 2d 04 45 6d e1  |.Y.(..j.A..-.Em.|
00000030  3f 03 94 74 fa ac 02 f1  fb 10 1a a2 6b 6b 57 56  |?..t........kkWV|
00000040  39 a4 cb 7f e0 34 a6 b1  68 c7 2b 67 20 ee 31 70  |9....4..h.+g .1p|
00000050  1f c4 da 37 af 20 d6 49  1a f1 56 4f e2 37 80 39  |...7. .I..VO.7.9|
00000060  ab 85 9b c8 d0 33 57 1e  64 cd ea 43 c8 3e 3d 21  |.....3W.d..C.>=!|
00000070  a8 0f 95 ec e3 60 45 43  80 55 c6 7f d9 ad 6e 4c  |.....`EC.U....nL|
00000080  df 51 4e 70 ea c7 89 24  55 6b ba d0 cc e4 32 1f  |.QNp...$Uk....2.|
00000090  88 80 d2 7e 72 ea d9 4a  6b ac d4 df c8 83 25 57  |...~r..Jk.....%W|
000000a0  d0 a3 f2 53 f1 40 bd 99  bf c7 a1 57 54 e2 da 2f  |...S.@.....WT../|
000000b0  73 e0 ef 96 4c c8 1e d9  87 6b c4 0a 3a d5 fc 8b  |s...L....k..:...|
000000c0  98 ab 35 1c 8e 6d 6d 38  9a d0 70 2e 26 0d dc f4  |..5..mm8..p.&...|
000000d0  8f ff e1 22 20 70 d5 83  7d 02 89 13 67 e5 e6 34  |..." p..}...g..4|
000000e0  53 95 b1 25 9e 43 a3 40  f3 1b 21 31 4d 96 24 91  |S..%.C.@..!1M.$.|
000000f0  28 2d b3 1e 60 e3 5e 04  82 fc 48 55 38 3e ae de  |(-..`.^...HU8>..|
00000100
```

这里使用：
- `-in` 选项指定原始数据文件msg.bin
- `-out` 选项指定加密后的输出文件msg.bin.enc
- `-inkey` 选项指定用于加密的公钥Key_pub.pem，由于输入是公钥，所以需要使用选项`-pubin`来指出
- `-encrypt` 选项表明这里是进行加密操作
- `-pkcs` 选项指定加密处理过程中数据的填充方式，对于填充，可选项有：`-pkcs, -oaep, -ssl, -raw`，默认是`-pkcs`，即按照PKCS#1 v1.5规范进行填充

### 1.4 私钥解密

使用私钥Key.pem对加密后的数据msg.bin.enc进行解密，并将结果存放到msg.bin.dec文件中：
```
$ openssl rsautl -in msg.bin.enc -out msg.bin.dec -inkey Key.pem -decrypt -pkcs
$ hexdump -Cv msg.bin.dec 
00000000  48 65 6c 6c 6f 20 52 6f  63 6b 79 21              |Hello Rocky!|
0000000c
```

这里使用：
- `-in` 选项指定待解密的数据文件msg.bin.enc
- `-out` 选项指定解密后的输出文件msg.bin.dec
- `-inkey` 选项指定用于解密的私钥Key.pem，由于输入是私钥，所以不再需要使用选项`-pubin`
- `-decrypt` 选项表明这里是进行解密操作
- `-pkcs` 选项指定解密处理过程中数据的填充方式，对于填充，可选项有：`-pkcs, -oaep, -ssl, -raw`，默认是`-pkcs`，即按照PKCS#1 v1.5规范进行填充

从上面hexdump的结果可见，已经成功解密，另外也可以通过对原始数据和解密后的数据计算md5校验和来确定：
```
$ md5sum msg.bin msg.bin.dec 
53fdc7c239dbd79fe76cb9525fadcd85  msg.bin
53fdc7c239dbd79fe76cb9525fadcd85  msg.bin.dec
```
显然，msg.bin和msg.bin.dec的md5校验和是一样的额。

## 2. Python实现非对称加解密

本文的加解密基于Python3下的`cryptograhpy`库，所以需要预先安装：
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

为了和使用`openssl rsault`命令得到的结果进行对比，这里使用同样的Key和数据，包括：
- Key：`Key.pem`和`Key_pub.pem`
- 数据：`msg.bin`

这里不再将加密和解密分成两个文件进行讲解，而是将加密和解密都放到同一个文件中，先对数据msg.bin进行加密得到msg.bin.encrypted文件，然后再对加密后的数据进行解密，将解密的结果输出到文件msg.bin.decrypted中，代码文件rsa-enc-dec.py的内容如下：

```
#!/usr/bin/env python3

# 导入cryptography库的相关模块和函数
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

from cryptography.hazmat.primitives.asymmetric import padding

# 定义辅助函数，用于打印16进制数据
def dump_hex(buffer, sep=' ', indent=0, line_size=16):
    """
    辅助函数，将bytes数组以如下格式打印输出：
    0000: 40 71 37 d0 80 32 7f 04 d9 6d fb fc f7 6a 7d d4
    0010: 48 ad 75 79 7a 0d 6c 55 01 ed 45 d5 1e 75 33 a6
    :param buffer: 待打印数据
    :param sep: 各16进制数据之间的分隔符，默认用空格' '分隔
    :param indent: 打印输出前是否需要缩进，默认不缩进
    :param line_size: 每行输出16进制的数量，默认1行输出16个
    :return: 无返回值
    """
    # 计算缩进空格数
    leading = '%s' % ' '*indent
    # 循环打印每行16进制数据
    for x in range(0, len(buffer), line_size):
        # 打印缩进字符和当前行数据的起始地址
        print('%s%04X: ' % (leading, x), end='')
        # 将当前行数据制作成列表list，并打印
        line = ['%02x' % i for i in buffer[x:x+line_size]]
        print(*line, sep=sep, end='\n')


# 加密函数
def encrypt(src_file_name, dst_file_name, public_key_file_name):
    """
    对原始数据文件使用指定的公钥进行加密，并将加密输出到目标文件中
    :param src_file_name: 原始数据文件
    :param dst_file_name: 加密输出文件
    :param public_key_file_name: 用于加密的公钥
    :return: 加密结果的bytes数组
    """
    # 读取原始数据
    data_file = open(src_file_name, 'rb')
    data = data_file.read()
    data_file.close()

    # 读取公钥数据
    key_file = open(public_key_file_name, 'rb')
    key_data = key_file.read()
    key_file.close()

    # 从公钥数据中加载公钥 
    public_key = serialization.load_pem_public_key(
        key_data,
        backend=default_backend()
        )

    # 使用公钥对原始数据进行加密，使用PKCS#1 v1.5的填充方式
    out_data = public_key.encrypt(
        data,
        padding.PKCS1v15()
    )

    # 将加密结果输出到目标文件中
    # write encrypted data
    out_data_file = open(dst_file_name, 'wb')
    out_data_file.write(out_data)
    out_data_file.close()

    # 返回加密结果
    return out_data


# 解密函数
def decrypt(src_file_name, dst_file_name, private_key_file_name):
    """
    对原始数据文件使用指定的私钥进行解密，并将结果输出到目标文件中
    :param src_file_name: 原始数据文件
    :param dst_file_name: 解密输出文件
    :param private_key_file_name: 用于解密的私钥
    :return: 解密结果的bytes数组
    """
    # 读取原始数据
    data_file = open(src_file_name, 'rb')
    data = data_file.read()
    data_file.close()

    # 读取私钥数据
    key_file = open(private_key_file_name, 'rb')
    key_data = key_file.read()
    key_file.close()

    # 从私钥数据中加载私钥
    private_key = serialization.load_pem_private_key(
        key_data,
        password=None,
        backend=default_backend()
    )

    # 使用私钥对数据进行解密，使用PKCS#1 v1.5的填充方式
    out_data = private_key.decrypt(
        data,
        padding.PKCS1v15()
    )

    # 将解密结果输出到目标文件中
    out_data_file = open(dst_file_name, 'wb')
    out_data_file.write(out_data)
    out_data_file.close()

    # 返回解密结果
    return out_data

if __name__ == "__main__":
    data_file_name = r'msg.bin'
    encrypted_file_name = r'msg.bin.encrypted'
    decrypted_file_name = r'msg.bin.decrypted'

    private_key_file_name = r'Key.pem'
    public_key_file_name = r'Key_pub.pem'

    # 先对数据加密
    data = encrypt(data_file_name, encrypted_file_name, public_key_file_name)
    # 打印加密结果
    print("encrypted data:")
    dump_hex(data)

    # 对数据进行解密
    data = decrypt(encrypted_file_name, decrypted_file_name, private_key_file_name)
    # 打印解密结果
    print("decrypted data:")
    dump_hex(data)
```

运行rsa-enc-dec.py，控制台结果如下：
```
$ python3 rsa-enc-dec.py 
encrypted data:
0000: 1c a3 be d5 e6 b0 58 57 06 ee a3 49 f4 2f 54 da
0010: 6a 27 13 90 71 6e ca 26 ca 54 ef d2 d1 6d 69 99
0020: a4 31 fc 75 c7 bf 39 08 7e ee c8 59 d4 31 f0 62
0030: c7 6e 75 71 fd d2 b1 e1 67 ae 10 78 e4 a3 40 f7
0040: b2 6d 73 bd 49 f2 90 0d 75 d7 37 5e b2 00 35 94
0050: 3f 24 64 6e 48 5b f5 34 13 f5 80 c7 5f 0c 46 af
0060: fa 36 5d f0 79 13 5d 53 20 0f 97 79 d2 c2 31 ef
0070: c7 30 fe 1d 65 13 37 12 f0 3e 27 49 a5 2b 30 c0
0080: c3 8d be 4e 5e 8e 68 54 88 f9 1e d3 a6 5e b6 a9
0090: c9 29 cb f5 72 28 44 e8 81 be bc 36 e8 68 c5 dc
00A0: ef ad 3c cb 13 3a a5 07 ff b3 eb 3b 82 93 e9 b9
00B0: 56 7c 3b 0a e5 fb 87 49 f1 15 15 a5 a3 77 75 d0
00C0: 9f b6 66 ec 51 64 26 f0 5b c4 5f e6 16 31 17 b1
00D0: 18 82 56 32 d8 8d 49 ef 06 b1 84 a6 e0 d8 ce cf
00E0: d1 8b ea d3 06 0d 20 05 48 88 3c 9e 8c 9c 78 22
00F0: 2e 97 56 c4 6c 39 1e 71 19 1b 91 dc 70 0c a0 4d
decrypted data:
0000: 48 65 6c 6c 6f 20 52 6f 63 6b 79 21
```

对于解密后的数据msg.bin.decrypted和原始数据msg.bin，二者的md5校验值是一样的，说明加密后又成功进行了解密：
```
$ md5sum msg.bin msg.bin.decrypted 
53fdc7c239dbd79fe76cb9525fadcd85  msg.bin
53fdc7c239dbd79fe76cb9525fadcd85  msg.bin.decrypted
```

## 3. 非对称加解密的疑问

在对比Python和openssl命令的加密结果时，竟然发现二者居然不一样！！！纳尼？
但是Python和openssl又能够将这个加密的结果解密回原始数据！

然后，进一步实验，尝试用openssl命令对同一数据分别进行两次加密操作，结果也是不一样，如下：
```
$ openssl rsautl -in msg.bin -inkey Key_pub.pem -pubin -encrypt -hexdump -pkcs  
0000 - a0 6b 39 46 aa 27 9e 34-51 a2 62 0a fd fe a3 64   .k9F.'.4Q.b....d
0010 - b8 29 3b ca 1f 5e 08 1d-53 3f f4 66 3e e7 2f b6   .);..^..S?.f>./.
0020 - d5 e3 43 3b c7 c5 33 2b-3d b7 73 20 c0 01 97 39   ..C;..3+=.s ...9
0030 - 00 11 62 60 55 5f 19 cf-17 4d 7b 9d eb 9b a5 e0   ..b`U_...M{.....
0040 - 8c e6 08 a0 ed ee ea 2a-71 59 75 bf 5b 8f 67 c8   .......*qYu.[.g.
0050 - f6 a9 be ba d1 bf 18 77-ee 10 d7 01 5c 37 f2 03   .......w....\7..
0060 - 87 26 ae 66 de ea 51 c0-cf 1b 79 ad 85 cf dd b6   .&.f..Q...y.....
0070 - c0 25 37 74 26 c5 57 d1-a2 4a 42 cc 89 a3 ba 23   .%7t&.W..JB....#
0080 - f7 dc 75 e3 cb 95 9a 63-31 f7 9a 24 17 29 03 66   ..u....c1..$.).f
0090 - 15 05 0a f6 fa 93 ef 47-c9 2c 27 9b e1 0d c1 b9   .......G.,'.....
00a0 - 3c 50 b5 f5 56 fb bb 62-db 48 7a 02 31 7e 63 03   <P..V..b.Hz.1~c.
00b0 - 39 1d d3 bb d3 97 65 9f-f1 74 9f b4 6e 72 4b 85   9.....e..t..nrK.
00c0 - 35 33 7c 7c a2 f8 48 98-60 fb a8 84 cb c6 18 70   53||..H.`......p
00d0 - 4d 33 de 44 fd 6d b4 8a-ed fb 10 b6 fb 7f 32 6a   M3.D.m........2j
00e0 - af 0b ee 22 bf 43 fd 42-fc 18 3f 38 73 5b b7 6b   ...".C.B..?8s[.k
00f0 - f8 3d 0a d5 cf c6 97 69-27 24 a3 2f f6 a7 9d f1   .=.....i'$./....
$
$ openssl rsautl -in msg.bin -inkey Key_pub.pem -pubin -encrypt -hexdump -pkcs
0000 - 70 5f 69 06 e0 59 b1 56-33 1f 05 54 03 29 8a a2   p_i..Y.V3..T.)..
0010 - 31 5e c9 68 a2 68 ac f7-e0 5c 89 23 47 fb 86 f9   1^.h.h...\.#G...
0020 - d3 d5 6b 19 ec 14 83 35-60 12 7d bf a5 de 7c d5   ..k....5`.}...|.
0030 - 74 0c 50 77 34 50 63 1a-d9 ae c4 74 c9 bd ce 72   t.Pw4Pc....t...r
0040 - 09 60 6d fd 55 9f e3 5e-4a 0e 3d 20 ec d8 2f 5c   .`m.U..^J.= ../\
0050 - e2 fe 21 64 a3 aa 65 67-1e d5 a1 70 4c 59 9f 8d   ..!d..eg...pLY..
0060 - 79 6c cf 8d d6 f0 cd 66-bd e2 be 74 6a 7b 53 5c   yl.....f...tj{S\
0070 - da 2e 43 23 1c 0a 59 5e-81 f7 76 aa 17 cd 3b ca   ..C#..Y^..v...;.
0080 - d5 1d 45 3a 2c 35 cf 9a-cf 33 ff a8 1d 91 37 e1   ..E:,5...3....7.
0090 - 20 ad 71 f3 87 bc db e1-d2 52 86 30 eb 02 0c 1f    .q......R.0....
00a0 - 4e a2 73 81 f0 84 6c 31-2e 4a c1 04 c9 3f e9 6c   N.s...l1.J...?.l
00b0 - e5 30 63 d0 3b fc 74 0a-b7 53 29 0a d8 a3 b6 a6   .0c.;.t..S).....
00c0 - 1d 8f e6 ec f0 8f 20 c6-e4 f6 bf 29 34 0f 0b a1   ...... ....)4...
00d0 - a9 19 2a cf 0a dc aa 3d-e4 6a 44 06 99 be 37 35   ..*....=.jD...75
00e0 - 59 57 43 f1 fb df 8d 19-45 64 eb 06 b7 d5 23 c9   YWC.....Ed....#.
00f0 - e3 19 98 a1 c9 80 6b 54-aa c6 d4 73 04 d9 06 fd   ......kT...s....
```

个人猜测可能是加密中引入了随机变量，导致加密结果不一样，例如此处原始数据只有12字节，通过随机填充再进行加密，导致结果不一样了。
由于以前并没有对非对称加密进行过详细研究，所以这里暂时还不能给出答案！

后续会针对这个问题进行分析，并给出解答！

## 4. 源码下载

点击这里下载本文提到的Python源码：[example-rsa-enc-dec.tar.bz2](https://github.com/guyongqiangx/blog/blob/dev/openssl/source/example-rsa-enc-dec.tar.bz2?raw=true)

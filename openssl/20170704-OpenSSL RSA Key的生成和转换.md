最近做一些芯片高级安全文件签名的反向验证工作，较多都是进行密钥转换、签名验证和加解密相关的操作，在这里顺带把其中的一些RSA格式转换操作总结一下。

## 1. RSA Key的生成

- 生成2048 bit的私钥
```
$ openssl genrsa -out Key0.pem -f4 2048
Generating RSA private key, 2048 bit long modulus
....................................+++
.................................+++
e is 65537 (0x10001)
$ cat Key0.pem 
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA1IJ2tHYgAQ9/SbGPgc/pgAq/gfcp/HsOpJyQgOTBMWbD6CBz
BJh4FzxP+RuJflOm7ILXc3QOO+ccJIT/6P8yuRp4JgWnd8r5wvAwBCzYrRV8zz6Y
tgbBO7ORtd/lPtHzdLXj52/aAbrRu4L8qu3C8acOrM6EjY6nKUdtbYRhm2VssSE5
ApU3pPKW6/QYXrUGypj8E8pujtYbtQIir4OXpMzJ2+AYeZOvjqSTuDSvet2As3qj
BdpBTXWfNC44FHAolcWI6U8Q/L6QKO2H8P11IZAA8aHZva2vudcxVwKz2QiOR1yV
ey4iXk2BhbOJQxC0XT3cc8k7Pbr+BHCDjR7i8wIDAQABAoIBAQCHlsJUfDYJVzD4
/SC6S8UJHFJ6gxA39vAt2XNduhcGBTKkLegVG48sDCBeqdI9VvRfXVBIatkWIWxU
ZMO/jux3LEtSvzLN/SUE2ylX0KFjNh2PQbpAEelCxV0H9VYYke7LHa7PIQ+xINjm
0jmSeedzNgrn+VCb3VQMw3UvdlKsyYx6j2AKx4qmML2T6qhwn/racKqTArH/9I2h
y47cxZYYACWwMD4R4NVj/UVy1yc4JU0HrtgyIo9fZL2CpGx/ZxQ0fKBGa5pI3xmn
TZZzbTUy3SGORijr1R5dYe48ZnxYc7n4G7/E9aiytrvDuny3b4crPu2UAyqsDfBK
j8ercULpAoGBAPqeKEC9J+hMGy4U1Ssu5ZqaNXxvLUEfT/ge+s/iVdh/dCtYEeqh
iR8MFJ7cqGUZt/ecR9remF/xGdXob0YssfaZiBEYu8mgr5mR4/xhF15fJHTmuyla
K3xsjOpMYTcF5KGQdwNnIXfodgL58xbel0ksx70qS/OOH60XF30Oe5KFAoGBANkS
y79dRokQDVqMDIPNswfxA7kFteL6wgXXnVgTqTCDZm7L3TnTBxwj5ZETxUm0RuA/
FdY46L54eiWcOpHcdMlKyf4Re9H855/25bUQf28e7LLRciuGUCZxNRKQ6r3IIERi
q0/9q5Hdec81kWOL7i8O8qeyP3wC1yiXSynM0aUXAoGAW3i+WGKx3idpBDi2VTyY
sQT34KLzcYFsPrOP97A0hQB/9hH++BRdZ+eQ3yrKi5wHeWihEVGNa/cj5t8fPg2y
Jr+C2jqcz8rGTNbiz4rgbKFtPP258i3nEVLNW/bkxKByAkYoKiXKIWnHKO7xurcj
oKGnhXOapRqKlTKIcCyJDcECgYAUGGRaQ9VKzPyffEWQUhOX0Z0JnNi4uYQKrGo5
hCBuiEuMSD0jpECNP1l6M71Y1GKXUd/ApCYPs/GC19KoPCNnmw/WAGJZDzOWIHIl
b/CMJe29pBwQoW98D5DdNiM1DHjIO+YmEpK2fy1OnGPoNkUHgDfAhITSAyVN8auY
pAhoYwKBgAMHL7a52J2oI1gM5lKA+odLXIIScm4TC3CCqkcVajrY3XbCqVz+oRFK
gzZoGIYOpBaYD/zy8vdL5Ds4Tg0ueo4yTyqnmSG34ydNabTnVyyj6z0W1Q/nhnJ8
KiYJx4ZGR1/xLWfk0XDQmKEwwU2jDUN/++nm5XXVkUI6tHKOvhf4
-----END RSA PRIVATE KEY-----
```

由于`-inform`和`-outform`的默认参数为`PEM`，所以这里的完整命令为：
```
$ openssl genrsa -outform=PEM -out Key0.pem -f4 2048 
```

- 从私钥导出公钥
```
$ openssl rsa -in Key0.pem -pubout -out Key0_pub.pem
writing RSA key
$ cat Key0_pub.pem 
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1IJ2tHYgAQ9/SbGPgc/p
gAq/gfcp/HsOpJyQgOTBMWbD6CBzBJh4FzxP+RuJflOm7ILXc3QOO+ccJIT/6P8y
uRp4JgWnd8r5wvAwBCzYrRV8zz6YtgbBO7ORtd/lPtHzdLXj52/aAbrRu4L8qu3C
8acOrM6EjY6nKUdtbYRhm2VssSE5ApU3pPKW6/QYXrUGypj8E8pujtYbtQIir4OX
pMzJ2+AYeZOvjqSTuDSvet2As3qjBdpBTXWfNC44FHAolcWI6U8Q/L6QKO2H8P11
IZAA8aHZva2vudcxVwKz2QiOR1yVey4iXk2BhbOJQxC0XT3cc8k7Pbr+BHCDjR7i
8wIDAQAB
-----END PUBLIC KEY-----
```

## 2. RSA Key的转换

在用`openssl rsa`命令生成RSA Key时有3种可选格式，分别为PEM，DER和NET，通过`-inform`参数指定，默认为`PEM`。
- DER: 原始的RSA Key按照ASN1 DER编码的方式存储
- PEM: DER经过base64编码转换为PEM格式
- NET: OpenSSL的帮助提示显示，NET是一个同老式的Netscape server和微软IIS .key文件兼容的格式（不过我没有详细研究过这种格式）

除了上面提到的3种格式外，最常见的还有可读性较好的文本格式，这里称为TXT格式。以下是PEM，DER和TXT格式之间的相互转换。

### 2.1 PEM转DER格式

直接通过`openssl rsa`进行输入格式和输出格式的转换。

```
# 私钥：PEM --(convert)--> DER
$ openssl rsa -inform PEM -in Key0.pem -outform DER -out Key0.der
$
# 公钥：PEM --(convert)> DER
$ openssl rsa -inform PEM -in Key0_pub.pem -pubin -outform DER -out Key0_pub.der
```

既然PEM是DER格式进行base64编码的格式，那PEM通过base64解码应为DER格式：

```
# 私钥：PEM --(decryption)--> DER
$ openssl base64 -d -in Key0.pem -out Key0.bin
$
# 公钥：PEM --(decryption)--> DER
$ openssl base64 -d -in Key0_pub.pem -out Key0_pub.bin
```

比较以上两种方法生成的文件Key0.der和Key0.bin，以及Key0_pub.der和Key0_pub.bin，其md5sum的结果一样，说明内容一样：
```
$ md5sum Key0.der Key0.bin Key0_pub.der Key0_pub.bin 
f6fa3ec1e35866578fccd507cb106f08  Key0.der
f6fa3ec1e35866578fccd507cb106f08  Key0.bin
fd15765f1656cc3332992cf6e979217f  Key0_pub.der
fd15765f1656cc3332992cf6e979217f  Key0_pub.bin
```

### 2.2 DER转PEM格式

跟PEM转DER格式一样，可以通过`openssl rsa`命令和`openssl base64`命令进行转换。

使用`openssl rsa`命令转换：
```
# 私钥：DER --(convert)--> PEM
$ openssl rsa -inform DER -in Key0.der -outform PEM -out Key0.PEM 
$
# 公钥：DER --(convert)--> PEM
$ openssl rsa -inform DER -in Key0_pub.der -pubin -outform PEM -out Key0_pub.PEM
```

使用`openssl base64`命令转换：
```
# 私钥：DER --(encryption)--> PEM
$ openssl base64 -e -in Key0.der -out Key0.pem
$
# 公钥：DER --(encryption)--> PEM
$ openssl base64 -e -in Key0_pub.der -out Key0_pub.pem
```

以下是两种转换方式得到的内容，略有不同。
```
$ cat Key0_pub.PEM
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1IJ2tHYgAQ9/SbGPgc/p
gAq/gfcp/HsOpJyQgOTBMWbD6CBzBJh4FzxP+RuJflOm7ILXc3QOO+ccJIT/6P8y
uRp4JgWnd8r5wvAwBCzYrRV8zz6YtgbBO7ORtd/lPtHzdLXj52/aAbrRu4L8qu3C
8acOrM6EjY6nKUdtbYRhm2VssSE5ApU3pPKW6/QYXrUGypj8E8pujtYbtQIir4OX
pMzJ2+AYeZOvjqSTuDSvet2As3qjBdpBTXWfNC44FHAolcWI6U8Q/L6QKO2H8P11
IZAA8aHZva2vudcxVwKz2QiOR1yVey4iXk2BhbOJQxC0XT3cc8k7Pbr+BHCDjR7i
8wIDAQAB
-----END PUBLIC KEY-----
$ cat Key0_pub.pem 
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1IJ2tHYgAQ9/SbGPgc/p
gAq/gfcp/HsOpJyQgOTBMWbD6CBzBJh4FzxP+RuJflOm7ILXc3QOO+ccJIT/6P8y
uRp4JgWnd8r5wvAwBCzYrRV8zz6YtgbBO7ORtd/lPtHzdLXj52/aAbrRu4L8qu3C
8acOrM6EjY6nKUdtbYRhm2VssSE5ApU3pPKW6/QYXrUGypj8E8pujtYbtQIir4OX
pMzJ2+AYeZOvjqSTuDSvet2As3qjBdpBTXWfNC44FHAolcWI6U8Q/L6QKO2H8P11
IZAA8aHZva2vudcxVwKz2QiOR1yVey4iXk2BhbOJQxC0XT3cc8k7Pbr+BHCDjR7i
8wIDAQAB
```
其唯一不同的后者Key0_pub.pem是通过`openssl base64`命令得到的文件，丢失了"`-----BEGIN PUBLIC KEY-----`"和"`-----END PUBLIC KEY-----`"这两条注释信息。

### 2.3 PEM转TXT格式

直接通过`openssl rsa`命令的`-text`参数输出可读的TXT格式：
```
# 私钥：PEM --> TXT
$ openssl rsa -inform PEM -in Key0.PEM -text -out Key0.txt
$
# 公钥：PEM --> TXT
$ openssl rsa -inform PEM -in Key0_pub.PEM -pubin -text -out Key0_pub.txt
```

实践发现，转换为TXT的PEM文件需要包含"`-----BEGIN PUBLIC KEY-----`"和"`-----END PUBLIC KEY-----`"标记，没有这个标记转换会失败。
例如，以下将DER通过`openssl base64`命令加密为PEM格式后，再尝试转换为TXT格式失败。

```
$ openssl rsa -inform PEM -in Key0.pem -text -out Key0.txt
unable to load Private Key
140185959843488:error:0906D06C:PEM routines:PEM_read_bio:no start line:pem_lib.c:703:Expecting: ANY PRIVATE KEY
$ cat Key0.pem
MIIEowIBAAKCAQEA1IJ2tHYgAQ9/SbGPgc/pgAq/gfcp/HsOpJyQgOTBMWbD6CBz
BJh4FzxP+RuJflOm7ILXc3QOO+ccJIT/6P8yuRp4JgWnd8r5wvAwBCzYrRV8zz6Y
tgbBO7ORtd/lPtHzdLXj52/aAbrRu4L8qu3C8acOrM6EjY6nKUdtbYRhm2VssSE5
ApU3pPKW6/QYXrUGypj8E8pujtYbtQIir4OXpMzJ2+AYeZOvjqSTuDSvet2As3qj
BdpBTXWfNC44FHAolcWI6U8Q/L6QKO2H8P11IZAA8aHZva2vudcxVwKz2QiOR1yV
ey4iXk2BhbOJQxC0XT3cc8k7Pbr+BHCDjR7i8wIDAQABAoIBAQCHlsJUfDYJVzD4
/SC6S8UJHFJ6gxA39vAt2XNduhcGBTKkLegVG48sDCBeqdI9VvRfXVBIatkWIWxU
ZMO/jux3LEtSvzLN/SUE2ylX0KFjNh2PQbpAEelCxV0H9VYYke7LHa7PIQ+xINjm
0jmSeedzNgrn+VCb3VQMw3UvdlKsyYx6j2AKx4qmML2T6qhwn/racKqTArH/9I2h
y47cxZYYACWwMD4R4NVj/UVy1yc4JU0HrtgyIo9fZL2CpGx/ZxQ0fKBGa5pI3xmn
TZZzbTUy3SGORijr1R5dYe48ZnxYc7n4G7/E9aiytrvDuny3b4crPu2UAyqsDfBK
j8ercULpAoGBAPqeKEC9J+hMGy4U1Ssu5ZqaNXxvLUEfT/ge+s/iVdh/dCtYEeqh
iR8MFJ7cqGUZt/ecR9remF/xGdXob0YssfaZiBEYu8mgr5mR4/xhF15fJHTmuyla
K3xsjOpMYTcF5KGQdwNnIXfodgL58xbel0ksx70qS/OOH60XF30Oe5KFAoGBANkS
y79dRokQDVqMDIPNswfxA7kFteL6wgXXnVgTqTCDZm7L3TnTBxwj5ZETxUm0RuA/
FdY46L54eiWcOpHcdMlKyf4Re9H855/25bUQf28e7LLRciuGUCZxNRKQ6r3IIERi
q0/9q5Hdec81kWOL7i8O8qeyP3wC1yiXSynM0aUXAoGAW3i+WGKx3idpBDi2VTyY
sQT34KLzcYFsPrOP97A0hQB/9hH++BRdZ+eQ3yrKi5wHeWihEVGNa/cj5t8fPg2y
Jr+C2jqcz8rGTNbiz4rgbKFtPP258i3nEVLNW/bkxKByAkYoKiXKIWnHKO7xurcj
oKGnhXOapRqKlTKIcCyJDcECgYAUGGRaQ9VKzPyffEWQUhOX0Z0JnNi4uYQKrGo5
hCBuiEuMSD0jpECNP1l6M71Y1GKXUd/ApCYPs/GC19KoPCNnmw/WAGJZDzOWIHIl
b/CMJe29pBwQoW98D5DdNiM1DHjIO+YmEpK2fy1OnGPoNkUHgDfAhITSAyVN8auY
pAhoYwKBgAMHL7a52J2oI1gM5lKA+odLXIIScm4TC3CCqkcVajrY3XbCqVz+oRFK
gzZoGIYOpBaYD/zy8vdL5Ds4Tg0ueo4yTyqnmSG34ydNabTnVyyj6z0W1Q/nhnJ8
KiYJx4ZGR1/xLWfk0XDQmKEwwU2jDUN/++nm5XXVkUI6tHKOvhf4
```

对比这里的key0.pem可最初生成的内容，唯一的差别就是这里缺少"`-----BEGIN PUBLIC KEY-----`"和"`-----END PUBLIC KEY-----`"标记

### 2.4 TXT转PEM格式

我不知道如何用`openssl`命令进行转换，谁知道的告诉我啊~~~

但是，我相信看过TXT内容的都应该知道如何进行转换，因为TXT文件最后的"`-----BEGIN PUBLIC KEY-----`"和"`-----END PUBLIC KEY-----`"部分就是PEM内容。
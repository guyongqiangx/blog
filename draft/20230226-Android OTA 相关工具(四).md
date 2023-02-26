# 20230226-Android OTA 相关工具(四)  查看 payload 文件信息

> 本文为洛奇看世界(guyongqiangx)原创，转载请注明出处。
>
> 文章链接：https://blog.csdn.net/guyongqiangx/article/details/129228856

一直以来，很多人都表达过很想去研究一下 Android OTA 的 payload 文件，看看里面到底有什么，想对其进行一番研究操作，但又觉得 payload 文件很复杂，最终望而却步。



在很久很久的以前上古时代，确切说是 Android 7.1 刚引进 A/B 系统的时候，基本没有什么用于分析 A/B 系统和 payload 的工具，我根据 update_metadata.proto 文件画过一张 payload.bin 的文件结构图，如下(可以点击图片看大图)：

![payload.bin 文件结构图](https://img-blog.csdn.net/20180921185230638)

图 1. Android 7.1 的 payload.bin 文件结构图



从 Anroid 7.1 到如今的 Android 13 系统，update_metadata.proto 文件几经变化，但大体结构仍然不变。

从 Android 10(Q) 的动态分区开始，update_engine 的代码中新增了一个名为 [payload_info.py](http://aospxref.com/android-10.0.0_r47/xref/system/update_engine/scripts/payload_info.py) 的脚本，专门用于解析 payload.bin 文件并显示相关信息。

有了这个工具，我觉得你应该不需要再对 payload.bin 文件内容发愁了。



> 更多关于 Android OTA 升级相关文章的列表和内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303) 
>
> 如果您已经订阅了收费专栏，请务必加我微信，拉你进相应专栏的答疑群。



> 本文基于 Android 11(R) 上的 payload_info.py 工具介绍其用法。

## 1. payload_info.py 的使用

### 1. 环境

payload_info.py 脚本位于 `system/update_engine/scripts` 目录下，payload_info.py 的脚本内容很简单，就是通过 payload 的 proto 结构数据查看 payload.bin 文件的信息。

payload_info.py 脚本的功能依赖于这个目录下的一些其它脚本，所以最简单的办法是直接在这个目录下进行操作，或者把脚本目录 export 到环境变量 PATH 中即可。

```bash
export PATH=system/update_engine/scripts:$PATH
```



虽然如此，但我通常还是建议你像我下面这样使用:

```bash
# 执行 build/envsetup.sh 设置代码编译相关的环境
$ source build/envsetup.sh

# 选择你感兴趣的编译配置，我这里直接用数字 46 指定，你也可以使用名称指定，如 'lunch aosp_arm64-eng'
$ lunch 46

# 把 payload_info.py 变量加入到 PATH 环境变量中
$ export PATH=system/update_engine/scripts:$PATH
```



设置好环境以后，就可以使用 payload_info.py 工具了。



### 2. 帮助信息

```bash
$ payload_info.py --help
usage: payload_info.py [-h] [--list_ops] [--stats] [--signatures] payload_file

Show information about an update payload.

positional arguments:
  payload_file  The update payload file.

optional arguments:
  -h, --help    show this help message and exit
  --list_ops    List the install operations and their extents.
  --stats       Show information about overall input/output.
  --signatures  Show signatures stored in the payload.
```



从这里可以看到，payload_info.py 支持的选项比较直观和简单，十分便于使用。

## 2. 查看 payload 文件信息

在这里，我查看一个 out/update 目录下差分包的 payload.bin 文件:

```bash
$ tree out/update
out/update
├── care_map.pb
├── META-INF
│   └── com
│       └── android
│           ├── metadata
│           └── otacert
├── payload.bin
└── payload_properties.txt

3 directories, 5 files
```



### 1. 不带选项查看

```bash
$ payload_info.py out/update/payload.bin 
Payload version:             2
Manifest length:             53885
Number of partitions:        6
  Number of "boot" ops:      67
  Number of "system" ops:    790
  Number of "vendor" ops:    42
  Number of "dtbo" ops:      4
  Number of "vbmeta" ops:    1
  Number of "vendor_boot" ops: 23
  Timestamp for boot:        
  Timestamp for system:      
  Timestamp for vendor:      
  Timestamp for dtbo:        
  Timestamp for vbmeta:      
  Timestamp for vendor_boot: 
  COW Size for boot:         0
  COW Size for system:       0
  COW Size for vendor:       0
  COW Size for dtbo:         0
  COW Size for vbmeta:       0
  COW Size for vendor_boot:  0
Block size:                  4096
Minor version:               7
```



从这里可以看到，这个 payload.bin 中一共操作了 6 个分区，分别是 boot, system, vendor, dtbo, vbmeta 和 vendor_boot。每个分区又有自己的 install operations。

### 2. 使用 stats 选项查看

```bash
$ payload_info.py --stats out/update/payload.bin 
Payload version:             2
Manifest length:             53885
Number of partitions:        6
  Number of "boot" ops:      67
  Number of "system" ops:    790
  Number of "vendor" ops:    42
  Number of "dtbo" ops:      4
  Number of "vbmeta" ops:    1
  Number of "vendor_boot" ops: 23
  Timestamp for boot:        
  Timestamp for system:      
  Timestamp for vendor:      
  Timestamp for dtbo:        
  Timestamp for vbmeta:      
  Timestamp for vendor_boot: 
  COW Size for boot:         0
  COW Size for system:       0
  COW Size for vendor:       0
  COW Size for dtbo:         0
  COW Size for vbmeta:       0
  COW Size for vendor_boot:  0
Block size:                  4096
Minor version:               7
Blocks read:                 1059987
Blocks written:              354408
Seeks when writing:          100
```

使用 stats 选项和不带选项输出的结果差不多，但会多出以下 IO 操作相关的部分:

```bash
Blocks read:                 1059987
Blocks written:              354408
Seeks when writing:          100
```



### 3. 使用 signagures 选项

顾名思义，signatures 选项就是用来查看 signature 信息的:

```bash
$ payload_info.py --signatures out/update/payload.bin 
Payload version:             2
Manifest length:             53885
Number of partitions:        6
  Number of "boot" ops:      67
  Number of "system" ops:    790
  Number of "vendor" ops:    42
  Number of "dtbo" ops:      4
  Number of "vbmeta" ops:    1
  Number of "vendor_boot" ops: 23
  Timestamp for boot:        
  Timestamp for system:      
  Timestamp for vendor:      
  Timestamp for dtbo:        
  Timestamp for vbmeta:      
  Timestamp for vendor_boot: 
  COW Size for boot:         0
  COW Size for system:       0
  COW Size for vendor:       0
  COW Size for dtbo:         0
  COW Size for vbmeta:       0
  COW Size for vendor_boot:  0
Block size:                  4096
Minor version:               7
Metadata signatures blob:    file_offset=53909 (267 bytes)
Metadata signatures: (1 entries)
  version=None, hex_data: (256 bytes)
    1a 53 e6 68 fb 26 26 bb c4 58 2f 1c fc a8 59 2d | .S.h.&&..X/...Y-
    e9 e8 2a a5 f4 29 94 92 9d b8 0a 85 03 0f 90 35 | ..*..).........5
    1f d7 a6 0f ba fc 9b ce f7 e4 d6 70 9b f8 b6 76 | ...........p...v
    19 2c a8 6f bf f8 cc c9 48 51 4b 67 91 03 73 91 | .,.o....HQKg..s.
    c4 cf 58 df 84 02 d6 d4 c4 6f 38 b7 70 ad ea 81 | ..X......o8.p...
    e3 a5 36 1d f1 b7 49 2f b0 18 56 ba 5b 96 ee d5 | ..6...I/..V.[...
    9f 30 1b 41 d7 36 9f b7 f3 d2 9d c5 57 c3 a8 93 | .0.A.6......W...
    ca 3d ab 77 84 3b 4a 39 c5 05 c1 37 0a 99 6b 16 | .=.w.;J9...7..k.
    db 5a 6e df a1 3a c1 6e 12 c4 47 76 88 19 28 6f | .Zn..:.n..Gv..(o
    55 79 28 8f 86 ab 5e 5d 38 b6 14 a2 2d 80 93 e9 | Uy(...^]8...-...
    07 11 50 f6 54 be a8 80 0c 14 40 36 15 37 85 e1 | ..P.T.....@6.7..
    d8 74 4e ac 03 7b 43 66 3a c1 0b bc 07 7b 63 03 | .tN..{Cf:....{c.
    bb e9 5d 2a 49 57 c5 3d 81 97 a2 83 87 01 0b 8c | ..]*IW.=........
    bc 5c a2 b3 26 a1 8a 7d 42 25 14 7a 76 c6 01 54 | .\..&..}B%.zv..T
    12 a5 0e f3 60 9e 3d 1c d8 fa c2 7c bc a8 f2 01 | ....`.=....|....
    ee c0 3b 5a 3b ac a4 c6 89 09 c6 78 a0 9d 00 34 | ..;Z;......x...4
Payload signatures blob:     blob_offset=9939442 (267 bytes)
Payload signatures: (1 entries)
  version=None, hex_data: (256 bytes)
    82 48 48 29 0d 04 9f 64 41 0e e2 bb da ad 14 eb | .HH)...dA.......
    a2 43 fd 7b ff c5 bd 58 b7 c8 af 02 b7 48 eb 30 | .C.{...X.....H.0
    8a 56 c7 6f fb 31 2d 77 e1 37 bc c4 b5 c6 8b a9 | .V.o.1-w.7......
    0e 79 73 8e 64 a9 10 63 8f c0 93 dd 2d da 0d 74 | .ys.d..c....-..t
    d6 28 1c da d2 4d 8e 29 5b f7 08 9d 56 80 0b 7b | .(...M.)[...V..{
    c8 ea 4e 8a 76 d9 ae 0d d3 1c 7d a7 8f d4 48 04 | ..N.v.....}...H.
    f4 d0 e0 b7 37 d1 0a 1e 92 d0 14 bb 34 4a c5 e4 | ....7.......4J..
    8b bf 8e 9d 1e a1 df 59 75 0a 77 10 0f bf 59 e5 | .......Yu.w...Y.
    05 33 b6 48 65 03 ed 9f 73 62 34 34 ca 8f 2d 21 | .3.He...sb44..-!
    cd d6 31 2f 22 93 69 9e fa 70 a1 9d 5b cf eb a3 | ..1/".i..p..[...
    f9 b7 ca c1 67 45 52 c2 1a 64 ad 22 32 46 0a 56 | ....gER..d."2F.V
    83 56 87 12 dc 71 55 08 0e 2b ec 92 ad 65 99 6e | .V...qU..+...e.n
    bf d9 e0 ad dc 45 48 3a 08 91 b6 ed 44 c6 f6 dc | .....EH:....D...
    c6 56 47 b7 d0 90 a6 63 c7 87 c8 51 2e 6c 79 16 | .VG....c...Q.ly.
    c4 11 36 ff 93 da f3 00 2c bc 0c 7a cc d1 53 d4 | ..6.....,..z..S.
    e6 d5 05 16 7b 23 ba 67 0c c5 40 6a ed 63 6c ff | ....{#.g..@j.cl.
```



从上面的输出可以看到 payload.bin 文件中 metadata 数据以及整个 payload 文件的 signagrue 签名内容信息。



### 4. 使用 list_ops 选项查看

使用 `list_ops` 选项可以查看 payload.bin 中包含的所有的 install operation 以及相关的 extent 信息

```bash
$ payload_info.py --list_ops out/update/payload.bin
Payload version:             2
Manifest length:             53885
Number of partitions:        6
  Number of "boot" ops:      67
  Number of "system" ops:    790
  Number of "vendor" ops:    42
  Number of "dtbo" ops:      4
  Number of "vbmeta" ops:    1
  Number of "vendor_boot" ops: 23
  Timestamp for boot:        
  Timestamp for system:      
  Timestamp for vendor:      
  Timestamp for dtbo:        
  Timestamp for vbmeta:      
  Timestamp for vendor_boot: 
  COW Size for boot:         0
  COW Size for system:       0
  COW Size for vendor:       0
  COW Size for dtbo:         0
  COW Size for vbmeta:       0
  COW Size for vendor_boot:  0
Block size:                  4096
Minor version:               7

boot install operations:
  0: SOURCE_COPY
    Source: 1 extent (512 blocks)
      (0,512)
    Destination: 1 extent (512 blocks)
      (0,512)
  ...
  65: ZERO
    Destination: 1 extent (281 blocks)
      (18150,281)
  66: SOURCE_COPY
    Source: 1 extent (1 block)
      (18431,1)
    Destination: 1 extent (1 block)
      (18431,1)
system install operations:
  0: BROTLI_BSDIFF
    Data offset: 170
    Data length: 1447872
    Source: 16 extents (512 blocks)
      (0,2) (3,1) (28,2) (32768,4) (65536,2) (65551,8) (85061,1) (98304,25)
      (131072,23) (163840,25) (196608,23) (229376,25) (262144,23) (294912,15)
      (302569,1) (303478,332)
    Destination: 14 extents (512 blocks)
      (0,2) (32768,2) (65551,8) (98304,2) (98308,21) (131074,21) (163840,2)
      (163844,21) (196610,21) (229376,2) (229380,21) (262146,21) (294912,15)
      (305874,353)
  1: SOURCE_COPY
    Source: 3 extents (23 blocks)
      (2,1) (2,1) (4,21)
    Destination: 1 extent (23 blocks)
      (2,23)
  2: BROTLI_BSDIFF
    Data offset: 1448042
    Data length: 81
    Source: 1 extent (1 block)
      (25,1)
    Destination: 1 extent (1 block)
      (25,1)
  ...
  788: ZERO
    Destination: 1 extent (75 blocks)
      (308293,75)
  789: REPLACE_BZ
    Data offset: 9938147
    Data length: 74
    Destination: 1 extent (1 block)
      (308368,1)
vendor install operations:
  0: SOURCE_COPY
    Source: 6 extents (512 blocks)
      (0,15) (6,1) (16,33) (48,1) (48,1) (51,461)
    Destination: 1 extent (512 blocks)
      (0,512)
  ...
  41: SOURCE_COPY
    Source: 1 extent (1 block)
      (19654,1)
    Destination: 1 extent (1 block)
      (19654,1)
dtbo install operations:
  0: SOURCE_COPY
    Source: 1 extent (1 block)
      (0,1)
    Destination: 1 extent (1 block)
      (0,1)
  1: BROTLI_BSDIFF
    Data offset: 9938221
    Data length: 182
    Source: 2 extents (3 blocks)
      (0,2) (255,1)
    Destination: 1 extent (1 block)
      (1,1)
  2: ZERO
    Destination: 1 extent (253 blocks)
      (2,253)
  3: SOURCE_COPY
    Source: 1 extent (1 block)
      (255,1)
    Destination: 1 extent (1 block)
      (255,1)
vbmeta install operations:
  0: BROTLI_BSDIFF
    Data offset: 9938403
    Data length: 868
    Source: 1 extent (1 block)
      (0,1)
    Destination: 1 extent (1 block)
      (0,1)
vendor_boot install operations:
  0: SOURCE_COPY
    Source: 1 extent (512 blocks)
      (0,512)
    Destination: 1 extent (512 blocks)
      (0,512)
  ...
  21: ZERO
    Destination: 1 extent (432 blocks)
      (9807,432)
  22: SOURCE_COPY
    Source: 1 extent (1 block)
      (10239,1)
    Destination: 1 extent (1 block)
      (10239,1)
```



具体的详细操作，以及相应的 extents 都一目了然。

也可以对 list_ops 的输出进一步操作，比如对各种操作进行分类统计。



## 3. 其它

到目前为止，我写过 Android OTA 升级相关的话题包括：

- 基础入门：《Android A/B 系统》系列
- 核心模块：《Android Update Engine 分析》 系列
- 动态分区：《Android 动态分区》 系列
- 虚拟 A/B：《Android 虚拟 A/B 分区》系列
- 升级工具：《Android OTA 相关工具》系列

更多这些关于 Android OTA 升级相关文章的内容，请参考[《Android OTA 升级系列专栏文章导读》](https://blog.csdn.net/guyongqiangx/article/details/129019303)。

如果您已经订阅了动态分区和虚拟分区付费专栏，请务必加我微信，备注订阅账号，拉您进“动态分区 & 虚拟分区专栏 VIP 答疑群”。我会在方便的时候，回答大家关于 A/B 系统、动态分区、虚拟分区、各种 OTA 升级和签名的问题。

除此之外，我有一个 Android OTA 升级讨论群，里面现在有 400+ 朋友，主要讨论手机，车机，电视，机顶盒，平板等各种设备的 OTA 升级话题，如果您从事 OTA 升级工作，欢迎加群一起交流，请在加我微信时注明“Android OTA 讨论组”。此群仅限 Android OTA 开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。

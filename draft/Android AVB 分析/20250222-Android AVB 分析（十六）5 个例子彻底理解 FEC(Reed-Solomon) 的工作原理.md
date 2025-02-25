# 20250222-Android AVB 分析（十六）5 个例子彻底理解 FEC(Reed-Solomon) 的工作原理

网上介绍 FEC 工作原理的文章很多，大多数都是从理论的角度对 FEC 或者 RS(里德所罗门)编码的数学原理介绍，并没有太多关于 FEC 实战介绍的文章。所以即使看了 FEC 的数学原理，但对 FEC 到底是如何工作的还是不清楚，包括我自己也是这样。

> 关于 FEC 是如何工作的，一直是我 Android OTA 讨论群中的未解话题，大家基本上都不清楚 Android 上面的 FEC 是如何工作的，为什么在 OTA 升级的最后阶段，FEC 的编码计算会消耗大量的 IO 资源，并持续很长时间。

接下来的几篇，我会从一个程序员的角度，演示基于里德所罗门编码的 FEC 到底是如何工作的。

## 1. 什么是 FEC？

### 1.1 FEC 的原理

FEC 是 **Forward Error Correction** 的简称，字面意思就是"前面的错误纠正"，简称**前向纠错**。

FEC是一种在数据传输过程中，通过在发送端添加冗余信息，使得接收端能够在不请求重传的情况下自动检测和纠正错误的技术。它的核心特点是“前向”，即错误的纠正是在接收端直接完成的，不需要发送端的进一步参与。

FEC主要用于数据传输，特别是那些重传代价高昂或不可行的场景，例如卫星通信、无线通信、流媒体传输等。在这些场景中，数据一旦发送出去，就很难或不可能请求重传，因此FEC能够有效提高数据传输的可靠性和效率。

实际上除了数据传输之外，有些数据存储也使用 FEC 进行纠错，例如 DVD 光盘，以及我们这几篇要讨论的重点：Android 镜像。



为了能让你能更好理解纠错的过程，下面是一个 FEC 前向纠错的简单例子。



### 1.2 一个 FEC 前向纠错的简单例子

下面是一个演示 FEC 前向纠错的例子：

例如，你的设备需要传输 1, 2, 3, 4, 5 这 5 个数字。为了达到纠错的目的，通过某种编码计算，添加 2 个字节的冗余信息，0x01 和 0x55，最后得到 7 个字节的数据: 

`0x01, 0x02, 0x03, 0x04, 0x05, 0x01, 0x55`。

设备发送数据时，先传输 0x01，然后传输 0x02，接着传输 0x03, 一直到发送完这 7 个数字。

但在传输过程中发生了干扰，第 3 个字节从 0x03 变成了 0x07，这样接收端接收到的数据变成了：

`0x01, 0x02, 0x07, 0x04, 0x05, 0x01, 0x55`

接收端在接收到这 7 个数字后，通过前面 5 个字节的数据，以及后面 2 个字节的冗余数据，通过计算将第 3 个字节的错误从 0x07 纠正回 0x03, 这个过程就叫做前向纠错。就是将前面传输错误的数据给纠正过来了。

这个过程是如何实现的呢？



### 1.3 FEC 前向纠错算法

这里的**前向纠错（FEC）** 示例，使用 **异或校验** 和 **线性方程** 实现单字节错误的检测与纠正。当传输数据 `[1, 2, 3, 4, 5]` 时，添加 **2 字节冗余信息** `0x01, 0x55`，具体步骤如下：

#### **0. 原始数据**

原始数据 `d1, d2, d3, d4, d5` 为: `0x01, 0x02, 0x03, 0x04, 0x05`。

------

#### **1. 发送端：生成冗余信息**

基于原始数据 `d1, d2, d3, d4, d5` 生成冗余信息 `r1, r2`，最终得到数据：

`d1, d2, d3, d4, d5, r1, r2`



##### **步骤 1：计算异或校验值（第 1 个冗余字节）**

将所有数据按位异或（XOR），生成一个校验值 `r1`：

即: `r1 = d1 ^ d2 ^ d3 ^ d4 ^ d5`

```python
r1 = 1 ^ 2 ^ 3 ^ 4 ^ 5 = 1
```

最终 `r1 = 1`。

##### **步骤 2：计算线性方程值（第 2 个冗余字节）**

为每个数据分配权重（如位置序号 `1, 2, 3, 4, 5`），计算加权和：

即: `r2 = 1 * d1 + 2 * d2 + 3 * d3 + 4 * d4 + 5 * d5`

```python
r2 = (1 * 1) + (2 * 2) + (3 * 3) + (4 * 4) + (5 * 5) = 55  
```

最终 `r2 = 55`。

##### **发送数据包**

发送原始数据 + 冗余信息：
`[1, 2, 3, 4, 5, 1, 55]`

------

#### **2. 接收端：检测与纠正错误**

假设传输中第 3 个数据（`3`）被篡改为 `7`，接收数据为：
`[1, 2, 7, 4, 5, 1, 55]`

##### **步骤 1：验证异或校验值**

重新计算接收数据的异或值：

```python
r1_received = 1 ^ 2 ^ 7 ^ 4 ^ 5 = 5
```

发现 `r1_received = 5`，与接收的冗余值 `1` 不符，说明存在错误。

##### **步骤 2：利用线性方程定位错误**

重新计算接收数据的加权和：

```python
r2_received = (1 * 1) + (2 * 2) + (7 * 3) + (4 * 4) + (5 * 5) = 67  
```

与接收的冗余值 `55` 的差值为 `67 - 55 = 12`。

##### **步骤 3：定位错误位置并纠正**

- **错误值（e）**：由异或差值可知，正确异或值应为 `1`，实际为 `5`，因此 `e = 1 ^ 5 = 4`。

- **错误位置（i）**：由线性方程差值 `12` 和错误值 `4`，计算位置：

  ```python
  i = 12 / 4 = 3  
  ```

  表示第 3 个数据出错。

- **纠正错误**：

  ```python
  错误数据 = 7  
  正确数据 = 7 ^ e = 7 ^ 4 = 3  
  ```

**修复后的数据**

`[1, 2, 3, 4, 5, 1, 55]`（错误已纠正）。



#### 3. 算法总结

总结一下，这个 FEC 纠错的算法步骤如下：

1. 原始数据：`d1, d2, d3, d4, d5`
2. 生成冗余字节 `r1 = d1 + d2 + d3 + d4 + d5`
3. 生成冗余字节 `r2 = 1*d1 + 2*d2 + 3*d3 + 4*d4 + 5*d5`
4. 发送数据加冗余：`d1, d2, d3, d4, d5, r1, r2`
5. 接收端计算接收数据的` r1'`和 `r2'`，并与接收到的 `r1` 和 `r2` 比较，得到差值 `s1` 和 `s2`
6. 如果 `s1`和`s2` 不为零，假设有一个错误，解方程找到错误位置`i`和错误值`e`：`e = s1，i = s2 / s1`
7. 纠正第`i`个数据：`d_i = d_i' - e`



这只是一个简单的 FEC 演示，通过添加 2 个字节的冗余来纠正 1 个字节的错误。局限在于：

1. 只能纠正 1 个字节的错误；
2. 只能纠正数据部分传输的错误，如果冗余信息传输错了则无法纠正。

实际的 FEC 算法更复杂，可以纠正更多字节的错误，即使冗余信息传输错误也可以得到纠正。

> 思考题：
>
> 1. 基于这里的 FEC 纠错算法，对于原始数据 `5, 6, 7, 8, 9`，其冗余数据是多少？
> 2. 如果接收到数据 `[5, 4, 8, 2, 1, 1, 35]`，你能恢复错误的那个字节吗？

## 2. 什么是里德所罗门编码(RS)？

### 2.1 里德所罗门编码

里德-所罗门编码（Reed-Solomon Coding），简称 RS 编码，是众多 FEC 编码算法中的一种。

里德-所罗门编码（Reed-Solomon Coding）是一种非二进制纠错码，由 Irving S. Reed 和 Gustave Solomon 在 1960 年提出。它属于 BCH 码的一个子类，广泛应用于数据传输和存储系统中，用于检测和纠正错误。里德-所罗门编码特别适用于纠正突发错误，即连续多个比特同时出错的情况。

> BCH 码是一种纠错编码，属于循环码的一种，由Bose、Ray-Chaudhuri和Hocquenghem三位学者提出，所以简称 BCH 码。它主要用于检测和纠正数据传输或存储中的错误。BCH 码的关键特性之一是在码设计过程中，可以对码能够纠正的符号错误数量进行精确控制。
>
> BCH 码是二进制循环码，而 RS 码是非二进制码，所以后者通常处理符号错误，而 BCH 更专注于比特错误。



里德-所罗门（Reed-Solomon）编码通常用 `RS(n, k) `来表示，其中：

- n：码字的总长度，即包含数据和冗余信息的符号总数。
- k：原始数据的长度，即未添加冗余信息前的数据符号数。

`RS(n, k) ` 编码可以纠正最多 `t=(n-k)/2` 个符号错误。这意味着，如果在传输或存储过程中，编码中的任何 t  个符号发生错误，RS 解码器都可以完全恢复原始数据。

例如，RS(255, 223) 编码可以纠正最多 16 个符号错误，因为 `t=(255-223)/2=16`。



关于 RS 编码，最常见的是下面这个示意图：

![img](./images-20250222-Android AVB 分析（十六）5 个例子彻底理解 FEC(Reed-Solomon) 的工作原理/image004(1).jpg)

这里提到的几个参数：m, n, k, t 你都清楚其意义吗？



#### **什么是符号(symbol)？**

在 RS 编码中，让初学者最难理解的术语就是 symbol(符号)，symbol 到底是什么？

前面提到，BCH 编码专注于比特错误，而 RS 编码专注于符号错误。这里的符号(symbol)是对多个比特(bit)的另外一种说法。

简单来说，1 个 symbol 可以是 1 bit 数据，也可以是 2 bit 或更多个 bit 的数据，1 symbol 可以是 1 byte 数据，也可以是 2 bytes 或者多个 bytes 数据。1 个 symbol 到底代表多少个 bit，是在具体的算法中指定的。



下面是我让 AI 整理的一些不同符号(symbol) 大小的应用场景(对错待核实):

![image-20250223002012831](./images-20250222-Android AVB 分析（十六）5 个例子彻底理解 FEC(Reed-Solomon) 的工作原理/image-20250223002012831.png)

**选择符号大小的关键因素**

1. **纠错需求**：符号越大，单符号可纠正的突发错误越长。
2. **数据长度**：符号大小需与数据块长度匹配（例如 GF(2⁸) 最大码长 255 符号）。
3. **计算资源**：符号越大，伽罗华域运算复杂度越高。
4. **行业标准**：如 DVB、CCSDS 等强制规定符号大小。

通过合理选择符号大小，RS 编码能够在效率、复杂度和纠错能力之间取得平衡，成为数字通信和存储系统的核心纠错技术。



在现实应用中，我们最常见的就是 `m=8`，即符号大小为 8bit，每个符号(symbol)代表 1 个字节。

因此，对于符号大小为 `m=8` (每个符号表示 1 byte)的情况下，RS(255, 223) 编码表示：

可以纠正最多 16 个字节错误，因为 `t=(255-223)/2=16`。



#### RS 编码的主要参数

一个完整的里德-所罗门（Reed-Solomon）编码可以通过以下参数来描述：

**RS(n, k, t, m, d)**

- **n**：编码长度，即一个编码块中包含的符号总数。
- **k**：信息符号数，即原始数据中包含的符号数。
- **t**：纠错能力，即编码能够纠正的最大符号错误数，计算公式为 `t=(n-k)/2`。
- **m**：符号大小，即每个符号的比特数，通常在有限域 `GF(2^m)` 中。
- **d**：最小距离，即任意两个有效码字之间的最小汉明距离，计算公式为 `d=n-k+1`。

在大多数的默认情况下 `m=8`，即 1 个 byte 代表 1 个符号。

另外，纠错能力 t 和 d 都可以通过 n, k 计算出来。

所以，**RS(n, k, t, m, d)** 通常简化记作 **RS(n, k)**，这就是为什么我们看到 RS(255, 223) 这种表示的原因。

对于 RS(255, 223) 这样的编码算法，包含了以下信息：

1. 默认符号大小 `m=8,` 因此 1 byte 表示 1 个符号。
2. `n=255`，每个编码块的总长度为 255 个符号，也就是 255 字节。
3. `k=223`,  编码块中原始数据占 223 个符号，也就是 223 字节。
4. `t=(n-k)/2=(255-223)/2=16`，因此对于一个 255 字节的编码块，可以最多纠正 16 个符号(字节)的错误。
5. `d=n-k+1=255-223+1=33`，对于最小汉明距离，表示数据容错能力的上限。d 越大，越不容易被错误破坏数据。

说人话就是，RS(255, 223) 表示对 223 字节进行编码，添加 32 字节的冗余信息形成 255 字节的编码块，可以纠正整个编码块中多达 (255-223)/2=16 个字节的错误。

实际上，在提供了具体错误位置的情况下，对于 RS(255, 223) 的可以纠正最多达 255-223=32 个字节的错误。但现实的数据传输中，根本不可能预先知道哪些位置发生了错误，所以也就没法提供错误的位置信息，最多也就只能纠正 (255-223)/2=16 个字节的错误。

> 如果你遇到杠精说 RS(255, 223) 最多可以纠正 32 个字节，那也没错。

解释到了这里，是时候回去再看下前面本节一开始那个 RS 编码的示意图了。能理解了吗？



### 2.2 几种常见的 RS 编码

下面是我让 Kimi 补充的几种常见的 RS 编码，大家可以根据上一节中关于 RS 纠错的参数自行计算下这些编码的纠错能力。

#### 1. RS(255, 223)

- **深空通信**：在深空探测任务中，如“旅行者号”（Voyager）和“伽利略号”（Galileo）等，RS(255, 223)编码被广泛应用于数据传输。由于深空通信距离遥远，信号传输过程中容易受到宇宙射线、太阳风等干扰，导致数据出错。RS(255, 223)编码强大的纠错能力能够有效纠正这些错误，确保从深空探测器传回地球的数据完整性和准确性，使科学家能够获取到宝贵的宇宙信息。
- **卫星通信**：在卫星通信领域，RS(255, 223)编码用于提高数据传输的可靠性。卫星与地面站之间的通信链路可能会受到大气层干扰、太阳活动等因素的影响，导致信号衰减和数据错误。采用RS(255, 223)编码可以在不增加过多冗余信息的情况下，纠正传输过程中出现的多个符号错误，从而保证卫星通信的稳定性和数据的完整性，对于卫星电视广播、卫星通信链路等有着重要的意义。
- **存储系统**：在一些对数据可靠性要求较高的存储系统中，如某些类型的硬盘存储，RS(255, 223)编码也发挥着重要作用。它可以纠正存储介质在读写过程中可能出现的突发错误，提高数据存储的可靠性，减少因硬件故障或介质老化导致的数据丢失风险，保障存储数据的安全性和完整性。

- **特点**：该编码在GF(2^8)上定义，具有很强的纠错能力，能够纠正最多16个符号错误。这意味着它可以纠正相对较长的错误序列，特别适合高噪声环境，如深空通信和卫星通信等场景，能够有效应对突发错误和随机错误，确保数据传输的可靠性。同时，RS(255, 223)编码在纠错过程中，能够以符号为单位进行纠正，这使得它在处理突发错误时具有优势，因为突发错误往往会导致连续多个比特出错，而该编码可以将这些错误作为一个整体进行纠正，提高了纠错效率。

#### 2. RS(255, 239)

- **数据存储**：在一些硬盘存储系统中，RS(255, 239)编码被用于提高数据存储的可靠性。硬盘存储介质在长时间使用过程中可能会出现物理损伤或读写错误，RS(255, 239)编码能够在一定程度上纠正这些错误，减少数据丢失的风险。虽然其纠错能力稍弱于RS(255, 223)，但对于一些对纠错能力要求不是特别高，但对数据传输效率要求较高的存储场景来说，是一个较为合适的选择。
- **无线通信系统**：在某些无线通信场景中，RS(255, 239)编码可用于数据传输。无线通信环境中的干扰因素较多，如多径效应、信号衰落等，这些因素会导致数据传输过程中出现错误。RS(255, 239)编码能够在保证较高传输效率的同时，提供一定的错误纠正能力，从而提高无线通信的可靠性和稳定性，适用于对实时性和传输效率要求较高的无线通信业务。

- **特点**：与RS(255, 223)相比，RS(255, 239)的纠错能力稍弱，能够纠正的符号错误数量较少。然而，它在编码效率方面具有一定优势，能够以较少的冗余信息实现错误纠正，从而提高数据传输的效率。这使得它在一些对传输效率要求较高的场景中更具吸引力，尤其是在数据量较大且需要快速传输的情况下，能够在保证一定纠错能力的前提下，减少冗余信息的开销，提高数据传输的效率和速度。

#### 3. RS(204, 188)

- **DVB-S（数字视频广播-卫星）系统**：在DVB-S系统中，RS(204, 188)编码是其重要的组成部分。卫星电视信号在传输过程中会受到多种因素的干扰，如大气层的散射、太阳活动等，导致信号衰减和数据错误。RS(204, 188)编码能够有效纠正这些错误，确保卫星电视信号的稳定传输和高质量接收。通过在接收端对信号进行解码和纠错处理，可以减少因传输错误导致的图像和声音的失真，提高观众的观看体验。
- **其他卫星通信场景**：除了DVB-S系统，RS(204, 188)编码也适用于其他卫星通信场景，如卫星数据传输、卫星通信链路等。在这些场景中，该编码能够提高数据传输的可靠性，降低错误率，确保卫星通信系统的正常运行，对于保障卫星通信业务的稳定性和数据的完整性具有重要作用。

- **特点**：RS(204, 188)编码适用于卫星通信环境，其纠错能力能够满足卫星通信中常见的错误类型和错误率要求。它能够在接收端直接纠正传输过程中的错误，而无需发送端的进一步参与，从而减少了因错误导致的重传请求，提高了卫星通信的效率和可靠性。这种编码方式在卫星通信领域得到了广泛应用，成为保障卫星通信质量的重要技术手段之一。



生活中除了上面这些例子, DVB 光盘中也大量使用 RS 编码来纠错，我们这里 AVB 分析中讨论的安卓系统上使用的是 RS(255, 253) 编码。

## 3. 基于 RS 编码的 4 个实验

有了前面几节的理论基础，我们开始本文的重点，基于程序员的视角，通过一些 Python 代码来理解 RS 编码。

> 本文实现需要安装 Python 的 reedsolo 库，参考：https://pypi.org/project/reedsolo/
>
> 另外，为了格式化打印数据，我还引用了 construct 库的 hexdump 和 hexundump 函数，因此还需要安装 construct 库。
>
> ```bash
> pip install reedsolo
> pip install construct 
> ```

### 1. RS(255, 223) 编码实验

源码：

```python
from reedsolo import RSCodec
from construct.lib.hex import hexdump, hexundump

if __name__ == "__main__":
    print("RS(255, 223) Encoding Demo:")
    data = [x for x in range(223)]
    print("Original Data:")
    print(hexdump(data, linesize=16))

    rs = RSCodec(nsize=255, nsym=32)

    res = rs.encode(data)
    print("Encoded Data:")
    print(hexdump(res, linesize=16))

    print("Done!")
```



输出：

```
RS(255, 223) Encoding Demo:
Original Data:
hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE      ...............
""")

Encoded Data:
hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE 41   ...............A
00E0   84 11 83 B1 1F DB 53 74 21 93 96 96 CD A7 0E 1D   ......St!.......
00F0   B5 C8 66 84 AF 22 25 64 B8 9C C6 06 9F 17 2E      ..f.."%d.......
""")

Done!
```



我们在这里构建了一个 0x00~0xDE 的 223 个字节的数据，通过 RS(255, 223) 编码，输出了一个 255 字节的数据块。(见 Original Data 数据)



在输出的数据块中，新增了 0xDF~0xFE 的 32 个字节，这部分就是通过 RS 编码新增的冗余信息。(见 Encoded Data 数据)



### 2. RS(255, 253) 编码实验

源码：

```python
from reedsolo import RSCodec
from construct.lib.hex import hexdump, hexundump

if __name__ == "__main__":
    print("RS(255, 253) Encoding Demo:")
    data = [x for x in range(253)]
    print("Original Data:")
    print(hexdump(data, linesize=16))

    rs = RSCodec(nsize=255, nsym=2)

    res = rs.encode(data)
    print("Encoded Data:")
    print(hexdump(res, linesize=16))

    print("Done!")
```



输出：

```bash
RS(255, 253) Encoding Demo:
Original Data:
hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC            .............
""")

Encoded Data:
hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC 3E C2      .............>.
""")

Done!
```



我们在这里构建了一个 0x00~0xFC 的 253 个字节的数据，通过 RS(255, 253) 编码，输出了一个 255 字节的数据块。(见 Original Data 数据)



在输出的数据块中，新增了0xFD 和 0xFE 位置的 2 个字节(0x3E, 0xC2)，这两字节就是通过 RS 编码新增的冗余信息。(见 Encoded Data 数据)



在 Android 镜像中就是基于 RS(255, 253)，给每 253 字节添加 2 个字节的冗余信息进行保存。



### 3. RS(255, 253) 纠错 1 字节成功



源码：

```
from reedsolo import RSCodec
from construct.lib.hex import hexdump, hexundump

if __name__ == "__main__":
    print("RS(255, 253) Encoding and Correction Demo:")
    data = [x for x in range(253)]
    print("Original Data:")
    print(hexdump(data, linesize=16))

    rs = RSCodec(nsize=255, nsym=2)

    encoded_data = rs.encode(data)
    print("Encoded Data:")
    print(hexdump(encoded_data, linesize=16))

    encoded_data[0] = 0xFF
    print("Incorrect Data:")
    print(hexdump(encoded_data, linesize=16))

    decoded_data, decoded_msgecc, errata_pos = rs.decode(encoded_data)
    print("Correct data:")
    print(hexdump(decoded_data, linesize=16))
    print(f"ECC message: {hexdump(decoded_msgecc, linesize=16)}")
    print(f"Error position: {list(errata_pos)}")

    print("Done!")
```



输出：

```bash
RS(255, 253) Encoding and Correction Demo:
...

Incorrect Data:
hexundump("""
0000   FF 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC 3E C2      .............>.
""")

Correct data:
hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC            .............
""")

ECC message: hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC 3E C2      .............>.
""")

Error position: [0]
Done!
```



在这个例子中，

我们在这里构建了一个 0x00~0xFC 的 253 个字节的数据，通过 RS(255, 253) 编码，输出了一个 255 字节的数据块。(见 Original Data 数据)



在输出的数据块中，新增了0xFD 和 0xFE 位置的 2 个字节(0x3E, 0xC2)，这两字节就是通过 RS 编码新增的冗余信息。(见 Encoded Data 数据)



随后，我们基于编码后的数据，将第 1 个字节的数据从原来的 0x00 修改为 0xFF。(见 Incorrect Data 数据)



然后，通过解码，还原出了正确的 253 字节数据。(见 Correct data 数据)。

同时，我们还获得了纠错后带有冗余码的 255 字节数据。(见 ECC message 数据)

以及错误数据的位置：Error position: [0]



### 4. RS(255, 253) 纠错 2 字节失败



源码：

```python
from reedsolo import RSCodec
from construct.lib.hex import hexdump, hexundump

if __name__ == "__main__":
    print("RS(255, 253) Encoding and Correction Demo:")
    data = [x for x in range(253)]
    print("Original Data:")
    print(hexdump(data, linesize=16))

    rs = RSCodec(nsize=255, nsym=2)

    encoded_data = rs.encode(data)
    print("Encoded Data:")
    print(hexdump(encoded_data, linesize=16))

    encoded_data[0] = 0xFF
    encoded_data[1] = 0xFF
    print("Incorrect Data:")
    print(hexdump(encoded_data, linesize=16))

    decoded_data, decoded_msgecc, errata_pos = rs.decode(encoded_data)
    print("Correct data:")
    print(hexdump(decoded_data, linesize=16))
    print(f"ECC message: {hexdump(decoded_msgecc, linesize=16)}")
    print(f"Error position: {list(errata_pos)}")

    print("Done!")
```



输出：

```bash
RS(255, 253) Encoding and Correction Demo:
...

Incorrect Data:
hexundump("""
0000   FF FF 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC 3E C2      .............>.
""")

Correct data:
hexundump("""
0000   FF FF 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F9 F9 FA FB FC            .............
""")

ECC message: hexundump("""
0000   FF FF 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F9 F9 FA FB FC 3E C2      .............>.
""")

Error position: [248]
Done!
```



在这个例子中，

我们在这里构建了一个 0x00~0xFC 的 253 个字节的数据，通过 RS(255, 253) 编码，输出了一个 255 字节的数据块。(见 Original Data 数据)



在输出的数据块中，新增了0xFD 和 0xFE 位置的 2 个字节(0x3E, 0xC2)，这两字节就是通过 RS 编码新增的冗余信息。(见 Encoded Data 数据)



随后，我们基于编码后的数据，将第 1 个字节的数据从原来的 0x00 修改为 0xFF。(见 Incorrect Data 数据)



然后，通过解码，还原出了正确的 253 字节数据。(见 Correct data 数据)。

同时，我们还获得了纠错后带有冗余码的 255 字节数据。(见 ECC message 数据)

以及错误数据的位置：Error position: [0]



### 5. RS(255, 253) 纠错 2 字节成功



源码：

```python
from reedsolo import RSCodec
from construct.lib.hex import hexdump, hexundump

if __name__ == "__main__":
    print("RS(255, 253) Encoding and Correction Demo:")
    data = [x for x in range(253)]
    print("Original Data:")
    print(hexdump(data, linesize=16))

    rs = RSCodec(nsize=255, nsym=2)

    encoded_data = rs.encode(data)
    print("Encoded Data:")
    print(hexdump(encoded_data, linesize=16))

    encoded_data[0] = 0xFF
    encoded_data[1] = 0xFF
    print("Incorrect Data:")
    print(hexdump(encoded_data, linesize=16))

    decoded_data, decoded_msgecc, errata_pos = rs.decode(encoded_data, erase_pos=[0, 1])
    print("Correct data:")
    print(hexdump(decoded_data, linesize=16))
    print(f"ECC message: {hexdump(decoded_msgecc, linesize=16)}")
    print(f"Error position: {list(errata_pos)}")

    print("Done!")

```



输出：

```bash
RS(255, 253) Encoding and Correction Demo:
...

Incorrect Data:
hexundump("""
0000   FF FF 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC 3E C2      .............>.
""")

Correct data:
hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC            .............
""")

ECC message: hexundump("""
0000   00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F   ................
0010   10 11 12 13 14 15 16 17 18 19 1A 1B 1C 1D 1E 1F   ................
0020   20 21 22 23 24 25 26 27 28 29 2A 2B 2C 2D 2E 2F    !"#$%&'()*+,-./
0030   30 31 32 33 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F   0123456789:;<=>?
0040   40 41 42 43 44 45 46 47 48 49 4A 4B 4C 4D 4E 4F   @ABCDEFGHIJKLMNO
0050   50 51 52 53 54 55 56 57 58 59 5A 5B 5C 5D 5E 5F   PQRSTUVWXYZ[\]^_
0060   60 61 62 63 64 65 66 67 68 69 6A 6B 6C 6D 6E 6F   `abcdefghijklmno
0070   70 71 72 73 74 75 76 77 78 79 7A 7B 7C 7D 7E 7F   pqrstuvwxyz{|}~
0080   80 81 82 83 84 85 86 87 88 89 8A 8B 8C 8D 8E 8F   ................
0090   90 91 92 93 94 95 96 97 98 99 9A 9B 9C 9D 9E 9F   ................
00A0   A0 A1 A2 A3 A4 A5 A6 A7 A8 A9 AA AB AC AD AE AF   ................
00B0   B0 B1 B2 B3 B4 B5 B6 B7 B8 B9 BA BB BC BD BE BF   ................
00C0   C0 C1 C2 C3 C4 C5 C6 C7 C8 C9 CA CB CC CD CE CF   ................
00D0   D0 D1 D2 D3 D4 D5 D6 D7 D8 D9 DA DB DC DD DE DF   ................
00E0   E0 E1 E2 E3 E4 E5 E6 E7 E8 E9 EA EB EC ED EE EF   ................
00F0   F0 F1 F2 F3 F4 F5 F6 F7 F8 F9 FA FB FC 3E C2      .............>.
""")

Error position: [0, 1]
Done!
```



## 4. 其它

我创建了一个 Android AVB 讨论群，主要讨论 Android 设备的 AVB 验证问题。

我还有几个 Android OTA 升级讨论群，主要讨论 Android 设备的 OTA 升级话题。

欢迎您加群和我们一起交流，请在加我微信时注明“Android AVB 交流”或“Android OTA 交流”。

仅限 Android 相关的开发者参与~

> 公众号“洛奇看世界”后台回复“wx”获取个人微信。




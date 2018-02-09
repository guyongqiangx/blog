Smartcard测试中，基本上都包含有对等待时间WT(waiting time)的极限测试，在客户支持中，也常常遇到WT不能通过测试的问题，大部分情况是由于卡通信中WT没有正确设置的缘故。

本来想将所有的关于WT的东西都列出来，包括GT, WT, CWT, BWT, BGT等，懒散了一下，这里只说T0协议下WT的计算。

本文推理和计算中涉及到ISO-7816标准和一些数学公式，会让人没有那么赖心看下去，如果你只关心结论，请跳转到：
- 第2.3节，看关于等待时间WT的一些结论
- 第3节，查看T0卡通信时解析ATR并计算工作等待时间WT的实例

这里所有关于时间的定义都来自标准ISO/IEC 7816-3:2006(E)

> ISO/IEC 7816-3:2006(E)
>
>   Identification cards — Integrated circuit cards — Part 3:
>   Cards with contacts — Electrical interface and transmission protocols

## 1. 等待时间WT的定义
第`7.2 Character frame`中定义了GT和WT

![GT and WT definition](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/wt-definition.png?raw=true)

这里指出：
1. 两个连续字符之间最小的上升沿间隔叫做"guart time"，记为GT。
2. 两个连续字符之间最大的上升沿间隔叫做"waiting time"，记为WT。

T0协议时关于WT，有两种：
1. 初始等待时间(initial waiting time,)， 即复位应答ATR中的waiting time。
2. 工作等待时间(work waiting time)，即卡通信时的waiting time。

下面来看看标准7816-3中关于这两个waiting time的规定。

## 2. T0卡复位和正常通信时的WT

## 2.1 复位时的WT

复位时发送ATR使用的WT又叫做初始等待时间(initial waiting time)

第`8.1 Characters and coding conventions`节指定了`initial waiting time`的值：

![WT in ATR](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/wt-in-atr.png?raw=true)

这里指出：
1. 复位传输ATR时，传输传输参数使用默认的`Fd = 372, Dd = 1`
2. 传输ATR时，`GT = 12 etu, WT = 9600 etu`

## 2.2 正常通信时的WT

正常通信时等待时间WT有叫做工作等待时间(work waiting time)

第`10.2 Character level` (page 28)节指定了T0协议的`work waiting time`的计算方式：

![WT in T0](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/wt-in-t0.png?raw=true)

这里指出：

```math
WT = WI \times 960 \times \frac{Fi}{f}
```

其中：
1. WI参数从TC2的bit1~8解析得到，TC2的值`0x00`留作将来之用，如果TC2不存在，则WI默认为10
2. Fi和f参数可以从TA1解析拿到，bit5-8得到Fi和f，bit1-4得到Di，默认为`Fi=372, f=5`和`Di=1`，如下：
![Fi, f and Di](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/f-d-factor-with-ta1.png?raw=true)

第`7.1 Elementary time unit`中定义了etu:

![etu definition](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/etu-definition.png?raw=true)

所以这里：
```math
\frac{Fi}{f} = Di \times 1etu

WT = WI \times 960 \times \frac{Fi}{f} = WI \times 960 \times Di \times 1etu
```

如果TC2不存在(WI=0)，TA1不存在(`Fi=371, f=5, Di=1`)有：
```math
WT = 10 \times 960 \times 1 \times 1etu = 9600etu
```

所以，T0协议工作时的WT和ATR的WT是一样的，都是9600etu。

## 2.3 WT结论

1. ATR传输的`WT = 9600 etu`;
2. T0卡工作时`WT = WI x Di x 960etu`，默认情况下`WI=10, Di=1`，此时`WT = 9600etu`，跟ATR传输时一样。

## 3. 实例分析

某CA的T0卡发送的原始ATR为：
```
3F 77 18 00 00 C2 EB 41 02 6C 90 00
```

对ATR解析后的数据如下：
- | -
---|---
TS = 0x3F | Inverse Convention
T0 = 0x77 | Y(1): b0111, K: 7 (historical bytes)
TA(1) = 0x18 | Fi=372, Di=12, 31 cycles/ETU (129032 bits/s at 4.00 MHz, 161290 bits/s for fMax=5 MHz)
TB(1) = 0x00 | VPP is not electrically connected
TC(1) = 0x00 | Extra guard time: 0
----	|
Historical bytes | C2 EB 41 02 6C 90 00
Category indicator byte: 0xC2 | (proprietary format) ".A.l.."

这里存在TA1(`Fi=372, f=5, Di=12`)，但不存在TC2(`WI=10`)，因此WT：
```math
WT = WI \times Di \times 960etu = 10 \times 12 \times 960etu = 115200 etu
```

所以在驱动中，需要将卡工作时的WT设置为115200etu，而不是默认的9600etu。

## 4. ATR解析的福利

最后送上一个福利。

你可能不了解7816-3标准，也不清楚ATR如何解析，没有关系，一个名为“Smart card ATR parsing”的网站为你解析ATR，省了多少烦恼，我第一次发现的时候开心得不行。

好了，地址在：[Smart card ATR parsing: https://smartcard-atr.appspot.com/](https://smartcard-atr.appspot.com/)

赶快去体验吧！

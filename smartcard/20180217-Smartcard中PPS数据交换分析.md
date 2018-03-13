## 1. 什么是PPS？

PPS，全称为`Protocol and Parameters Selection`，直译为协议和参数选择，是设备同Smartcard协商通信协议和传输参数的一种机制。

Smartcard会在复位应答ATR(`Answer To Reset`)中表明支持的协议和参数。设备端可以使用默认的协议，或者通过PPS数据交换选择其它协议。更多的情况是，设备端通过PPS协商使用新的传输参数，如波特率因子，但并不更改传输协议。

本文根据7816-3规范，说明什么时候进行PPS交换？如何进行PPS交换？由于涉及到标准的引用，内容难免枯燥繁琐，如果只希望了解PPS交换的时机和流程，请转到本文第4节(`4. PPS数据交换总结`)，查看结论。如果想看PPS交换的实例，请转到5节(`5. PPS交换实例分析`)。

这里主要的定义和引用都来自标准ISO/IEC 7816-3:2006(E)。

> ISO/IEC 7816-3:2006(E)
>
>   Identification cards — Integrated circuit cards — Part 3:
>   Cards with contacts — Electrical interface and transmission protocols

## 2. 何时进行PPS交换？

### 2.1 PPS数据交换的场景

第`"6.3.1 Selecton of transmission parameters and protocol"`节详细描述了PPS操作的场景。即什么时候进行PPS交换？

![PPS Exchange Scenario](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/pps%20exchange%20scenario.png?raw=true)

文档中的解释如下：

![PPS Exchange Scenario Details](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/pps%20exchange%20scenario%20details.png?raw=true)

复位ATR后操作场景如下：

- 如果ATR中TA2存在，说明卡端处于指定模式(card in specific mode)，则设备端使用TA2指定的协议和参数进行通信
- 如果ATR中TA2不存在， 说明卡端处于协商模式(card in negotiable mode)，此时通信继续使用ATR传输使用的参数
  - 如果卡端收到的第一个字节是`FF`，则设备端和卡端开始PPS交换，交换完成后双方使用协商的参数通信
  - 如果卡端收到的第一个字节不是`FF`，则按照TD1中指定的第一传输协议通信

显然，这里TA2是关键，那么ATR中的TA2是如何规定的呢？

### 2.2 ATR中关于TA2的定义

第`8.3 Global interface bytes`节对TA2做了详尽的定义

![TA2 Definition of ATR](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/ta2%20definition.png?raw=true)

ATR中TA2定义的要点如下：
- bit 8 表明是否支持在协调模式和指定模式之间切换
  - 0, 支持模式切换
  - 1, 不支持模式切换
- bit 7~6 预留给将来使用，默认为0
- bit 5 指定传输使用的参数F和D
  - 0, 使用TA1中指定的Fi和Di参数
  - 1, 使用隐含参数，即默认参数（非ATR中接口字符定义的值）
- bit 4~1, 指定传输使用的协议T

简而言之，TA2指定了传输使用的协议T和参数F和D，同时TA2也表明是否支持模式切换。


## 3. 如何进行PPS交换？

### 3.1 PPS交换的动作
第`9.1 PPS exchange`节定义了PPS交换的动作:

![PPS Exchange Operation](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/pps%20exchange%20operation.png?raw=true)

翻译过来如下：

- 设备端向卡端发起PPS交换请求
- 如果卡端收到错误的PPS请求，不做响应
- 如果卡端收到正确的PPS请求，如果支持，则需要发送PPS响应；否则，发生WT超时。
- 对于`overrun of WT`, `erroneous PPS response`和`unsuccessfull PPS exchange`三种情况，设备端需要进行deactivation操作。

### 3.2 PPS数据的格式

PPS数据交换分为PPS请求和PPS响应，第`9.2 PPS request and response`定义了PPS请求和响应的细节。

![PPS Request and Response](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/pps%20exchange%20request%20and%20response.png?raw=true)

总体说来，PPS请求和响应的格式一样，1字节的initial byte(PPSS)，紧跟1字节的format byte (PPS0), 3个可选的参数字节 optinal parameter bytes (PPS1, PPS2和PPS3)，最后1字节的check byte (PCK)。

详细的格式信息如下：

![PPS Exchange Structure Format](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/pps%20exchange%20structure%20format%20details.png?raw=true)

> 这里PPS数据的最后一个字节check byte (PCK)可以通过对前面PPSS, PPS0~3的各个字节异或得到。
>
> 规范上对此的描述是，将PPS命令字节数据(包括PPSS, PPS0~3, PCK)进行异或，其结果为0。这应该是为了方便进行数据校验的结果。换句话说，如果PPS数据异或结果不为0，那说明PPS命令是非法的。

### 3.3 PPS响应的细节

PPS响应的数据细节同PPS请求的细节一样，但设置上需要遵从以下规则：

![PPS Exchange Response](https://github.com/guyongqiangx/blog/blob/dev/smartcard/images/pps%20exchange%20response%20details.png?raw=true)

这里提到：

- 响应PPS的bit 1~4同请求PPS的bit 1~4一样
- 响应PPS的bit 5同请求PPS的bit 5一样或置0
- 响应PPS的bit 6同请求PPS的bit 6一样或置0
- 响应PPS的bit 7同请求PPS的bit 7一样或置0

> 不要问我这里为什么没有提到bit 8，哈哈，因为bit 8是保留为，默认为0

啰嗦一次，实际上，绝大部分时候，响应PPS同请求PPS是一样的。

## 4. PPS数据交换总结

什么时候进行PPS交换？

Smartcard复位后的第一件事是发送ATR，设备端接收并解析ATR。ATR的TA2字段存在与否表明了Smartcard的两种模式：
- TA2存在
  
  Smartcard为指定协议模式(`card in specific mode`)，此时采用ATR中指定的协议和参数进行通信

- TA2不存在

  Smartcard为协商模式(`card in negotiable mode`)，此时设备端根据具体情况决定进行PPS数据交换，还是发送工作命令

只有当Smartcard处于协商模式下时，设备才有必要根据具体情况决定进行PPS交换还是直接发送命令工作

- PPS数据交换

  如果需要协商采用新的协议或调整参数，则设备发送PPS请求(0xFF开头)到Smartcard，卡端解析PPS后应用新的参数，并作PPS响应。设备端接收到卡端的PPS响应，至此，一轮PPS数据交换才算完成。完成后，二者开始正常的交互操作。

- 正常工作

  如果不需要更改协议或调整参数，则设备直接发送操作命令(非0xFF开头)到Smartcard，开始二者的交互操作。

> 通常情况下，PPS数据交换是设备端接收到ATR后，发送的第一个命令(0xFF开头)。理论上，也是可以在工作一段时间后再发送PPS更改传输协议和参数，但我没有见过这种情况。
>
> 个人猜测如果Smartcard以某协议工作一段时间后，需要更改协议，可能是先复位，在设备接收到ATR后通过发起PPS请求更改。

PPS数据交换分为PPS请求和PPS响应，二者的数据格式一样，不仅如此，绝大多数情况下，二者的内容也一样。设备端发送了什么命令，卡端原样返回该命令。

## 5. PPS交换实例分析

### 5.1 Irdeto某T1卡

#### ATR

设备接收到Irdeto某T1卡的ATR如下：
```
3B B0 36 00 81 31 FE 5D 95
```

从ATR中提取到的Fi=744, Di=32，但该ATR中不包含TA2字段，复位后卡处于协商模式。

#### PPS Request

设备端接收到ATR后发起PPS请求：
```
FF 10 18 F7
```

PPS请求的内容解析如下：
```
Initial Byte: FF
 Format Byte: 10
                bit 1~4: 0, T=0
                bit 5~7: 1, bit 5=1, PPS1 presented
        PPS1: 18
                TA1=18, Fi=372, f(max.)=5, Di=12
         PCK: F7
                FF xor 10 xor 18 = F7
```

> 这里的PCK可以使用计算器对前面PPSS, PPS0, PPS1逐个异或操作得到。

显然，这里ATR接收到的Fi=744, Di=32。设备发起PPS请求，将Fi和Di分别修改为Fi=372, Di=12。

#### PPS Response

Smartcard返回的PPS响应如下：
```
FF 10 18 F7
```

设置成功，卡端返回跟PPS请求一样的数据。

### 5.2 Conax某T0卡

#### ATR
设备接收到Conax某T0卡的ATR如下：
```
3B 34 94 00 30 42 30 30
```

从ATR中提取到的Fi=512, Di=8，但该ATR中不包含TA2字段，复位后卡处于协商模式。

#### PPS Request

设备端接收到ATR后发起PPS请求：
```
FF 10 94 7B
```

PPS请求的内容解析如下：
```
Initial Byte: FF
 Format Byte: 10
                bit 1~4: 0, T=0
                bit 5~7: 1, bit 5=1, PPS1 presented
        PPS1: 94
                TA1=94, Fi=512, f(max.)=5, Di=8
         PCK: 7B
                FF xor 10 xor 94 = 7B
```

显然，这里ATR接收到的Fi=512, Di=8。设备发起PPS请求，将Fi和Di分别修改为Fi=512, Di=8。

所以这里虽然发起了PPS交换，但交换前后的参数都是一样的，多此一举啊~~~~

> 后来查看代码发现，处理流程上，设备接收到ATR后，直接发起PPS请求，将ATR解析得到的TA1设置为PPS请求的第3个字节PPS1。所以也就不难理解为什么PPS交换前后参数一样了。

#### PPS Response

Smartcard返回的PPS响应如下：

```
FF 10 94 7B
```

设置成功，卡端返回跟PPS请求一样的数据

## 6. 福利

最后送上一个福利。

Smartcard操作中，ATR解析至关重要，但你可能不了解7816-3标准，也不清楚ATR如何解析，那怎么办啊？

没有关系，一个名为“Smart card ATR parsing”的网站为你解析ATR，省了多少烦恼，我第一次发现的时候开心得不行。

好了，地址在：[\[Smart card ATR parsing\]: https://smartcard-atr.appspot.com/](https://smartcard-atr.appspot.com/)

赶快去体验吧！
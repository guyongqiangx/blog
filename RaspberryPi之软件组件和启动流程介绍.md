出于NDA的原因，树莓派RaspberryPi公开的芯片资料较少，就我对Broadcom其它产品线芯片的了解，以及网上对BCM283x系列的芯片介绍来看，树莓派使用的283x系列芯片大致构成如下（仅猜测，非正式文档）：
![BCM283x CPU function block diagram](http://img.blog.csdn.net/20160915171614768)

主要部件包括：
- 广为人知的ARMv7（主CPU，即Application Processor或AP）
- 博通独有的VideoCore IV（图像处理单元，即GPU）
- 只读ROM
- 一次性写入的OTP
- 小块的SDRAM
- 控制核心secure core
- 集成的其它部件，如各种外设的controller等

其上电之初的整个过程完全由secure core控制。

http://elinux.org/RPi_Software 有提到启动所需要的各个组成构件，主要有：
- First stage bootloader，出厂前固化在283x芯片内部rom上，芯片厂商写入，不可更改
- Second stage bootloader，即boot目录下的bootcode.bin，由树莓派基金会定制；
- GPU firmware，即boot目录下的start.elf，由树莓派基金会定制；
- User code，用户代码，可由用户自主定义，默认即boot目录下的kernel.img，也可通过config.txt设置为其它程序，如u-boot.bin

那这些部件都由谁来执行，如何启动的呢？

简而言之：
1. reset后secure core执行rom内的程序
    reset后secure core检查OTP并初始化相应的启动设备，让GPU执行bootcode.bin。网上有些文章介绍通过更改OTP使树莓派从USB启动，也就是这个道理。
2. GPU启动执行bootcode.bin
    bootcode.bin相当于GPU的bootloader，会对内存等进行初始化并加载start.elf
3. GPU加载执行start.elf来负责图像输出工作，让CPU执行kernel.img或u-boot.bin
    start.elf读取config.txt来设置图像输出格式，初始化CPU的clock和串口等设备，准备kernel.img并触发CPU的reset
4. CPU启动执行kernel.img或u-boot.bin，进入应用程序

由于内置的rom code和bootcode.bin以及start.elf都不公开，CPU执行的user code由GPU来加载，所以不清楚执行user code之前的事情也不影响对树莓派的使用。

网上也有人讨论说secure core是内置在GPU里面的，目前没有任何公开的资料说明secure core到底位于哪里，但这并不妨碍我们对树莓派启动过程的理解。




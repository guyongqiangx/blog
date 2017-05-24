##bootloader使用SLRAM设备向Kernel传递块数据
[TOC]
###bootloader向Kernel传递参数的主要途径

####1. 通过命令行参数传递
Bootloader将需要传递的参数作为kernel启动的命令行参数，如：x=param，内核启动后再解析参数x；
此种方式需要在kernel中添加代码解析x=param参数；

####2.	通过外部设备传递参数
Bootloader将需要传递的参数写入外部存储设备中，如EEPROM/flash/emmc/hd/usb，内核启动后再从外部设备中读取这些数据；
此种方式需要bootloader驱动支持flash/emmc或者hd/usb读写，另外频繁读写flash会影响flash寿命； 

####3.	通过内存传递参数
Bootloader将需要传递的参数写入内存指定区域，内核启动后再从内存的约定区域读取数据；
此种方式需要确保两个问题：
1)	 确保写入的内存区域在kernel启动后读取这些数据之前不会被修改，很容易出现这部分内存被kernel管理起来而没有权限读写数据；
2)	 确保kernel启动后kernel读写参数的内存和bootloader操作的区域不是同一块内存区域，因为Bootloader和kernel对内存区域的地址映射不一样；
此种方式比较复杂，需要地址转换，病防止内存中的数据不被篡改；

####4.	通过寄存器传递参数
Bootloader将需要传递的参数写入芯片的某些内核启动过程中不会被修改该的寄存器，内核启动后再从这些约定的寄存器中读取数据；此种方式操作简单，不需要额外的驱动，单由于寄存器跟芯片相关，不同厂商的寄存器不一样，跟平台的相关性较大；

####5.	其它方式传递参数
1) 通过device tree传递参数，内核启动后需要单独的代码来解析参数；
（某些平台的命令行cmdline就通过device tree传递）
2) 通过ATAGS传递参数，内核启动后需要单独的代码来解析参数；
（某些平台的命令行cmdline就通过ATAGS传递，逐渐被device tree代替）
3)	将待传递参数设置为bootloader的环境变量，内核启动过程中返回bootloader读取环境变量；
（仅限于某些实现kernel读取bootloader环境变量功能的平台）

如果还有其他方式，欢迎补充。

以上方式中：
- 命令行方式适合传递少量数据；
- 外部设备方式可以传递各种大小数据，但可能会影响外部设备寿命；
- 内存方式传递数据操作比较复杂，数据也容易被篡改；
- 寄存器方式受限于未使用的寄存器数量，也只适合传递少量数据，且具有平台相关性；

###使用SLRAM传递参数的实例
本文主要根据内核中现有代码和基础设施，通过SLRAM驱动从bootloader向内核传递参数。
如下是基于Broadcom机顶盒7584平台的操作示例：

####1. 运行menuconfig进行内核设置
编译时运行menuconfig命令进行内核设置
![运行menuconfig进行设置](http://img.blog.csdn.net/20160813205034872)

####2. 查找SLRAM
在menuconfig界面输入“/”后弹出配置查找对话框
![查找SLRAM](http://img.blog.csdn.net/20160813205247488)

####3. SLRAM查找结果
在查找对话框中输入SLRAM后会显示搜索到的信息
![SLRAM查找结果](http://img.blog.csdn.net/20160813205346598)
搜索结果显示SLRAM驱动的开关MTD_SLRAM位于driver/mtd/devices/Kconfig中，且依赖于MTD=y选项

####4.	打开SLRAM驱动
进入Device Drivers下的Memory Technology Device (MTD) support 子菜单打开SLRAM驱动
![这里写图片描述](http://img.blog.csdn.net/20160813213521777)
设置“Uncached system RAM”项为星号，将相应驱动编译进内核

###SLRAM设备传递参数测试
设置完成后编译成带文件系统的内核文件vmlinuz-initrd-7584a0进行测试。
以下是测试步骤：
####1.	设置IP
机顶盒启动后运行ifconfig配置IP地址：

```
CFE> ifconfig -auto eth0
Sending DHCP discover...
Ethernet link is up: 100 Mbps Full-Duplex
Device eth0:  hwaddr 00-66-6E-70-0D-A2, ipaddr 192.168.6.92, mask 255.255.255.0
        gateway 192.168.6.1, nameserver 192.168.138.20, domain she.rocky.com
*** command status = 0
CFE>

```

####2.	检查原始数据
用CFE的dump命令检查下0x84000000地址处的数据，默认全为0xFF：

```
CFE> d -b 0x84000000 64
84000000  FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF  ................
84000010  FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF  ................
84000020  FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF  ................
84000030  FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF  ................
84000040  FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF  ................
84000050  FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF  ................
84000060  FF FF FF FF                                      ....            
*** command status = 0
CFE>

```

####3.	加载测试数据到指定内存区域
用CFE的load命令向0x84000000地址处写入测试数据， 写入的测试数据大小为465568字节：

```
CFE> load -raw -addr=0x84000000 -max=524288 -tftp 192.168.6.95:test.bin
Loader:raw Filesys:tftp Dev:eth0 File:192.168.6.95:cfe.bin Options:(null)
Loading: . 0 bytes read
Failed.
Could not load test.bin: Error
Trying again with '-nz' option
Loading: ........... 465568 bytes read
Entry address is 0x84000000
*** command status = 0
CFE>

```

####4.	检查加载的测试数据
用CFE的dump命令检查下0x84000000地址处的数据， 确保是刚才加载的数据：

```
CFE> d -b 0x84000000 64
84000000  0A 00 00 10 00 00 00 00 5A 00 04 24 40 B0 09 3C  ........Z..$@..<
84000010  64 43 29 35 00 00 24 AD 93 0A 11 04 00 00 00 00  dC)5..$.........
84000020  00 54 04 3C 46 1B 00 10 00 00 00 00 40 B0 08 3C  .T.<F.......@..<
84000030  84 8E 08 35 00 00 09 8D 40 B0 0A 3C F0 83 4A 35  ...5....@..<..J5
84000040  00 00 49 AD 40 B0 08 3C 90 8E 08 35 00 00 09 8D  ..I.@..<...5....
84000050  40 B0 0A 3C F4 83 4A 35 00 00 49 AD 5F 0A 11 04  @..<..J5..I._...
84000060  00 00 00 00                                      ....            
*** command status = 0
CFE>

```

####5.	启动内核，传递SLRAM内存地址参数
启动kernel，将刚才0x84000000开始大小为512K的参数通过命令行传递：

```
CFE> boot -z -elf 192.168.6.95:vmlinuz-initrd-7584a0 'slram=cfe_slram,64M,+512K'
Loader:elf Filesys:tftp Dev:eth0 File:192.168.6.95:ygu/7584a0/vmlinuz-initrd-7584a0 Options:slram=cfe_slram,64M,+512K
Loading: 0x80001000/11961344 0x80b69400/110224 Entry address is 0x8045f3d0
Closing network eth0
Starting program at 0x8045f3d0

```

对应的内核传递参数为：'slram=cfe_slram,64M,+512K'，表示从64MB偏移量开始即（0x84000000地址处）开始的512K区域定义成名称为cfe_slram的mtd分区；

####6.	检查SLRAM设备
内核启动后检查mtd分区信息：

```
# cat /proc/mtd
dev:    size   erasesize  name
mtd0: 00080000 00004000 "cfe_slram"
mtd1: 1f300000 00020000 "rootfs"
mtd2: 20000000 00020000 "entire_device"
mtd3: 00500000 00020000 "kernel"
#

```
内核已经根据步骤5中传入的参数建立名为了cfe_slram的内存mtd设备；

####7.	读取SLRAM设备数据
用hexdump工具检查cfe_slram设备上的数据：

```
# hexdump -C -n 64 /dev/mtd0
00000000  0a 00 00 10 00 00 00 00  5a 00 04 24 40 b0 09 3c  |........Z..$@..<|
00000010  64 43 29 35 00 00 24 ad  93 0a 11 04 00 00 00 00  |dC)5..$.........|
00000020  00 54 04 3c 46 1b 00 10  00 00 00 00 40 b0 08 3c  |.T.<F.......@..<|
00000030  84 8e 08 35 00 00 09 8d  40 b0 0a 3c f0 83 4a 35  |...5....@..<..J5|
00000040
#


```

只需要对/dev/mtd0上的数据进行读取就可以拿到bootloader传递过来的数据；

###其它
- SLRAM驱动比较简单，位于drivers/mtd/devices/slram.c中：
- 对于虚拟为mtd的SLRAM设备，其大小在驱动中被定义为SLRAM_BLK_SZ的整数倍，宏SLRAM_BLK_SZ默认定义的大小为16K，所以最小的SLRAM设备为16KB，如果需要传递的数据较小，可以通过SLRAM_BLK_SZ宏进行调整。
- SLRAM的命令行参数格式为：slram=name,start,end/offset
- 如下是通过命令行参数保留两个内存区域作为slram设备：slram=rootfs_slram,76M,+24M,loader_slram,61M,+10M


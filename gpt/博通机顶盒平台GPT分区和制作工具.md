# `GPT`分区和制作工具

## 0. 前言

本文基于Broadcom机顶盒平台，介绍`GPT`分区的特点，并重点描述了如何通过开源的`sgdisk`工具和博通Android包自带的`makegpt`工具在博通机顶盒平台上进行`GPT`分区设置。

内容较长，以下为直通车：

- 只想了解`GPT`的特点，请参考__1.2 `GPT`设备的特点__
- 只想通过`sgdisk`进行分区划分，请参考__2.2 `sgdisk`分区实例__
- 只想通过`makegpt`生成`GPT`数据，请参考__3.2 `makegpt`分区实例__

## 1. GPT介绍
### 1.1 GPT介绍

本文略过`GPT`的各种细节，详细资料可以参考以下页面：

- Wiki页面： [GPT(GUID Partition Table)](https://en.wikipedia.org/wiki/GUID_Partition_Table) 
- [GPT 分区详解](http://www.jinbuguo.com/storage/gpt.html)

### 1.2 GPT设备的特点

总体上GPT分区的布局如下：

![GPT 布局](https://upload.wikimedia.org/wikipedia/commons/0/07/GUID_Partition_Table_Scheme.svg)

归结起来，GPT设备有以下特点：

1. 设备由若干的逻辑块`LBA (Logic Block Addressing)`组成，单个`LBA`大小为512字节
2. `LBA 0`用于兼容传统的`MBR`，也称作"`Protective MBR`"
3. 设备有两个`GPT`镜像数据，每个占用33个`LBA`：
   - `LBA 1`开始的`Primary GPT`
      + `LBA 1`存放`Primary GPT Header`
      + `LBA 2 - LBA 33`，总计32块用于存放分区信息
   - `LBA - 1`结束的`Secondary GPT`
      + `LBA-33 - LBA-2`，总计32块用于存放分区信息
      + `LBA-1`存放`Secondary GPT Header`
4. 数据存放到设备中间的`LBA 34 - LBA-34`区域

### 1.3 `GPT Header`的格式
`GPT Header`占用一个完整的`LBA`，以`Primary GPT Header`为例，在`LBA 1`中的格式如下：

| Offset | Length | Contents |
|-:|-:|:-|
|0 (0x00) | 8 bytes | Signature ("EFI PART", `45h 46h 49h 20h 50h 41h 52h 54h` on little-endian machines) |
|8 (0x08) | 4 bytes | Revision (for GPT version 1.0, the value is 00h 00h 01h 00h) |
|12 (0x0C)| 4 bytes | Header size in little endian (in bytes, usually 5Ch 00h 00h 00h or 92 bytes) |
|16 (0x10) | 4 bytes | CRC32 of header (offset +0 up to header size), with this field zeroed during calculation |
|20 (0x14) | 4 bytes | Reserved; must be zero |
|24 (0x18) | 8 bytes | Current LBA (location of this header copy) |
|32 (0x20) | 8 bytes | Backup LBA (location of the other header copy) |
|40 (0x28) | 8 bytes | First usable LBA for partitions (primary partition table last LBA + 1) |
|48 (0x30) | 8 bytes | Last usable LBA (secondary partition table first LBA - 1) |
|56 (0x38) | 16 bytes | Disk GUID (also referred as UUID on UNIXes) |
|72 (0x48) | 8 bytes | Starting LBA of array of partition entries (always 2 in primary copy) |
|80 (0x50) | 4 bytes | Number of partition entries in array |
|84 (0x54) | 4 bytes | Size of a single partition entry (usually 80h or 128) |
|88 (0x58) | 4 bytes | CRC32 of partition array |
|92 (0x5C) | * | Reserved; must be zeroes for the rest of the block |

> 以下是一个实际的`Primary GPT Header`例子：
>
> ![GPT Header Example](https://github.com/guyongqiangx/blog/blob/dev/gpt/primary-gpt-header-comments.jpg?raw=true)
>
> 这里从第二个`LBA`即`LBA 1`开始，其偏移地址为`0x200`，每个字段解释如下：
> 
> 1. `0x200-0x207`， `GPT`头签名， `"45 46 49 20 50 41 52 54"(ASCII: "EFI PART")`
> 2. `0x208-0x20B`， 版本号， `00 00 01 00`，表示`1.0`版
> 3. `0x20C-0x20F`， `GPT`头大小， `5C 00 00 00` ，(小端)表示0x5C (92)字节
> 4. `0x210-0x203`， `GPT`头`CRC`校验和(计算时把这个字段本身看做零值)，``
> 5. `0x214-0x217`， 预留，`00 00 00 00`
> 6. `0x218-0x21F`， 当前`GPT`头的起始扇区号，`01 00 00 00 00 00 00 00`，即`LBA 1`
> 7. `0x220-0x227`， 备份`GPT`头的起始扇区号，`FF FF E8 00 00 00 00 00`
> 8. `0x228-0x22F`，分区起始扇区号，`06 00 00 00 00 00 00 00`，即`LBA 6`，通常会从`LBA 34`开始
> 9. `0x230-0x237`，分区结束扇区号，`FA FF E8 00 00 00 00 00`
> 10. `0x238-0x247`，设备`GUID`，`33 C4 B9 43 06 A1 BF 68 AF F4 89 04 16 FC 87 D7`
> 11. `0x248-0x24F`，分区表起始扇区号，`02 00 00 00 00 00 00 00`，即`LBA 2`
> 12. `0x250-0x253`，分区表总项数，`0D 00 00 00`，即13项，通常为128项
> 13. `0x254-0x257`，单个分区表占用字节数，`80 00 00 00`，即128字节
> 14. `0x248-0x25B`，分区表`CRC`校验和，`D4 6A D8 FB`
> 15. `0x25C-0x39F`，预留，填充全0
> 
> 从上面的第12，13项看，一个`LBA`可以存放4个分区项，13个分区项总共占用4个`LBA`，再加上`LBA 0`和用于存放`GPT Header`的`LBA 1`，因此这里设备开始处整个`GPT`占用6个`LBA`，即`LBA 0 - LBA 5`，所以第8项指出分区的起始扇区号为`LBA 6`
> 
> 从主`GPT`反推备份`GPT`，显然备份`GPT`只占用尾部的5个`LBA`(1个`LBA`存放`GPT`头，4个`LBA`存放13个分区项)，而并非预期的33个。


### 1.4 `Partition Entry`的格式
在`GPT Header`中定义了`Partition Entry`的数目`(0x50)`和大小`(0x54)`，单个`Partition Entry`的大小通常为128字节，所以一个`LBA`可以存放4项。

`GUID partition entry format`

| Offset | Length | Contents |
|-:|-:|:-|
| 0 (0x00) | 16 bytes | Partition type GUID |
| 16 (0x10) | 16 bytes | Unique partition GUID |
| 32 (0x20) | 8 bytes | First LBA (little endian) |
| 40 (0x28) | 8 bytes | Last LBA (inclusive, usually odd) |
| 48 (0x30) | 8 bytes | Attribute flags (e.g. bit 60 denotes read-only) |
| 56 (0x38) | 72 bytes | Partition name (36 UTF-16LE code units) |

对于分区属性，`Microsoft`定义的基本分区属性有：

`Basic data partition attributes`

| Bit | Value | Content |
|-|-|:-|
| 60 | 0x0001000000000000 | Read-only |
| 61 | 0x0002000000000000 | Shadow copy (of another partition) |
| 62 | 0x0004000000000000 | Hidden |
| 63 | 0x0008000000000000 | No drive letter (i.e. do not automount) |

以上`Partition Entry`的描述中，比较直观的有：

- `offset 0x20`, 起始`LBA`
- `offset 0x28`, 结束`LBA`
- `offset 0x30`, 分区属性
- `offset 0x38`, 分区名称

这几个属性在工具`sgdisk`和`makegpt`的参数中都有体现。

> 以下是一个`Partition Entry`的例子：
> ![`Partition Entry Exmaple`](https://github.com/guyongqiangx/blog/blob/dev/gpt/gpt-entries-comments.jpg?raw=true)
>
> 这里从第三个`LBA`即`LBA 2`开始，其偏移地址为`0x400`，每个字段解释如下：
> 
> 1. `0x400-0x40F`，分区类型`GUID`， `"A2 A0 D0 EB E5 B9 33 44 87 C0 68 B6 B7 26 99 C7"`，转换为`GUID`为`EBD0A0A2-B9E5-4433-87C0-68B6B72699C7`，相应的分区类型为“基本数据分区”
> 2. `0x410-0x41F`，分区的`GUID`， `1F 29 CA 94 2B 2A FE DE 0D 52 7D 9C 5C 91 55 8A`
> 3. `0x420-0x427`，分区起始扇区号，`22 00 00 00 00 00 00 00`，表示从第0x22个`LBA`即`LBA 34`开始
> 4. `0x428-0x42F`，分区结束扇区号，`22 00 00 00 00 00 00 00`，表示分区在第0x22个`LBA`结束，即该分区只占用了1个`LBA`
> 5. `0x430-0x437`，分区属性，`00 00 00 00 00 00 00 00`
> 6. `0x438-0x47F`，分区名称，这里为`"macadr"`
> 
> 从上图可见，在`LBA 2`上（区域`0x400-0x5FF`），共存放了4个分区项，分区类型都是“基本数据分区”，其名称分别为`"macadr"，"nvram"，"bsu"和"misc"`

## 2. `sgdisk`工具
`sgdisk`是`Linux`上用于创建`GPT`分区的工具，官方网站[`GPT fdisk Tutorial`](http://www.rodsbooks.com/gdisk/)

### 2.1 `sgdisk`的参数
`sgdisk`的参数非常多，可以在命令行运行`sgdisk --help`获得详细信息。
也可以参考`sgdisk`的帮助页面：[`sgdisk` man page](http://www.rodsbooks.com/gdisk/sgdisk.html)，该页面对每一个选项都有详细的描述。

简单讲，`sgdisk`的使用如下：
```
sgdisk [ options ] device`
```

如：`sgdisk -p /dev/mmcblk0`，显示`eMMC`设备`/dev/mmcblk0`上的分区信息。

#### 2.1.1 `sgdisk`常用的选项

- `-c, --change-name=partnum:name`，设置分区`partnum`的名字
- `-d, --delete=partnum`，删除指定编号`partnum`的分区
- `-E, --end-of-largest`，显示设备最大的可用`sector`值，由于`GPT`在设备顶端还有一个镜像数据，所以该值为`Secondary GPT `的下边界，即`LBA - 34`
- `-n, --new=partnum:start:end`，创建指定编号为`partnum`的分区，且该分区的起始`LBA`分别为`start`和`end`
- `-p, --print`，摘要显示`GPT`分区信息，包括设备和分区的信息
- `-o, --clear`，清除设备的分区数据

#### 2.1.2 `sgdisk`的一些其它选项

- `-a, --set-alignment=value`，设置分区对齐的方式，以`sector`为单位，默认为2048（2048 x 512 = 1MB)，即1MB边界对齐
- `-A, --attributes=list|[partnum:show|or|nand|xor|=|set|clear|toggle|get[:bitnum|hexbitmask]]`，设置分区`partnum`的属性
- `-b, --backup=file`，备份分区数据到文件`file`
- `-i, --info=partnum`，显示指定分区`partnum`的详细信息
- `-l, --load-backup=file`，从文件`file`加载分区数据
- `-v, --verify`，校验`GPT`数据，该命令可以检查发现较多问题，如`CRC`不正确，`Primary GPT`和`Secondary GPT`不匹配等。

### 2.2 `sgdisk`的实例
以下是在一个4G的`eMMC`上创建分区的例子：

#### 2.2.1 待分区数据

| 分区号 | 起始LBA号 | 结束LBA号 | 分区大小 | 名称 |
|-:|-:|:-|-:|-|
| 1 | 34 | 545 | 256.0 KiB | macadr |
| 2 | 546 | 1057 | 256.0 KiB | nvram |
| 3 | 1058 | 1569 | 256.0 KiB | bsu |
| 4 | 1570 | 3617 | 1024.0 KiB | misc |
| 5 | 3618 | 665 | 1024.0 KiB | hwcfg |
| 6 | 5666 | 71201 | 32.0 MiB | boot |
| 7 | 71202 | 136737 | 32.0 MiB | recovery |
| 8 | 136738 | 2233889 | 1024.0 MiB | cache |
| 9 | 2233890 | 4331041 | 1024.0 MiB | system |
| 10 | 4331042 | 6428193 | 1024.0 MiB | userdata |
| 11 | 6428914 | 7733214 | 636.9 MiB | storage |

#### 2.2.2 分区命令

	sgdisk -o /dev/mmcblk0
	sgdisk -a 1 -n 1:34:545 -c 1:"macadr" /dev/mmcblk0
	sgdisk -a 1 -n 2:546:1057 -c 2:"nvram" /dev/mmcblk0
	sgdisk -a 1 -n 3:1058:1569 -c 3:"bsu" /dev/mmcblk0
	sgdisk -a 1 -n 4:1570:3617 -c 4:"misc" /dev/mmcblk0
	sgdisk -a 1 -n 5:3618:5665 -c 5:"hwcfg" /dev/mmcblk0
	sgdisk -a 1 -n 6:5666:71201 -c 6:"boot" /dev/mmcblk0
	sgdisk -a 1 -n 7:71202:136737 -c 7:"recovery" /dev/mmcblk0
	sgdisk -a 1 -n 8:136738:2233889 -c 8:"cache" /dev/mmcblk0
	sgdisk -a 1 -n 9:2233890:4331041 -c 9:"system" /dev/mmcblk0
	sgdisk -a 1 -n 10:4331042:6428193 -c 10:"userdata" /dev/mmcblk0
	sgdisk -n 11:6428914:`sgdisk -E /dev/mmcblk0` -c 11:"storage" /dev/mmcblk0

以上命令中，

- 先用`sgdisk -o /dev/mmcblk0`选项清空设备上的分区数据，
- 然后再用`sgdisk -n -c`选项逐个划分了编号为1-11的分区，
- 其中最后一个分区的结束位置通过命令`sgdisk -E /dev/mmcblk0`来取得。

#### 2.2.3 显示分区
执行完成后，用`sgdisk -p`命令查看刚才划分的分区：

	# sgdisk -p /dev/mmcblk0
	Disk /dev/mmcblk0: 7733248 sectors, 3.7 GiB
	Logical sector size: 512 bytes
	Disk identifier (GUID): 782D35FD-F9E9-45F1-85FF-AD5E25034F86
	Partition table holds up to 128 entries
	First usable sector is 34, last usable sector is 7733214
	Partitions will be aligned on 2-sector boundaries
	Total free space is 720 sectors (360.0 KiB)
	
	Number  Start (sector)    End (sector)  Size       Code  Name
	   1              34             545   256.0 KiB   8300  macadr
	   2             546            1057   256.0 KiB   8300  nvram
	   3            1058            1569   256.0 KiB   8300  bsu
	   4            1570            3617   1024.0 KiB  8300  misc
	   5            3618            5665   1024.0 KiB  8300  hwcfg
	   6            5666           71201   32.0 MiB    8300  boot
	   7           71202          136737   32.0 MiB    8300  recovery
	   8          136738         2233889   1024.0 MiB  8300  cache
	   9         2233890         4331041   1024.0 MiB  8300  system
	  10         4331042         6428193   1024.0 MiB  8300  userdata
	  11         6428914         7733214   636.9 MiB   8300  storage

使用`sgdisk`进行划分时，需要提供`start`:`end`参数，对于每个分区都需要进行计算才能得到这个参数，分区数量多的情况下还容易出错，操作起来不太方便。

### 2.3 `sgdisk`的其它实例

- 打印分区信息

	`# sgdisk -p /dev/mmcblk0`

- 清除分区信息

	`# sgdisk -o /dev/mmcblk0`

- 设置分区属性

    将partition 9设置为只读（属性 bit 60置1）：

	`# sgdisk -A 9:set:60 /dev/mmcblk0`

- 备份`GPT`数据

	将GPT数据备份到文件gpt.bin：

	`# sgdisk -b gpt.bin /dev/mmcblk0`

- 加载`GPT`数据

	从文件gpt.bin恢复GPT数据：
	`# sgdisk -l gpt.bin /dev/mmcblk0`

- 校验`GPT`数据

	`# sgdisk -v /dev/mmcblk0`

## 3. `makegpt`工具

`sgdisk`进行划分需要精确计算每个分区的起始和结束位置，不太方便；另外，生产线上运行`sgdisk`命令创建分区会影响流水线效率，如果能预先制作好`GPT`数据，生产时直接写入设备的相应位置就更好了。

博通机顶盒平台的Android系统提供了一个`makegpt`工具，该工具通过读取一个比较直观的配置文件来生成`GPT`数据，然后只需要将生成的`gpt.bin`写到`eMMC`设备的起始位置即可，解决了`sgdisk`运行不方便的问题。

以`Android 7.1`的`release`包为例，工具`makegpt`相关的文件有：

- `makegpt`源码：`vendor\broadcom\bcm_platform\tools\makegpt`
- `GPT`分区的配置数据：`device\broadcom\common\gpts\default.conf`
- 编译后生成的`makegpt`工具：`out\host\linux-x86\bin\makegpt`
- 编译后生成的`gpt.bin`数据：`out\target\product\bcm{board}\gpt.bin`

### 3.1 `makegpt`的参数

在`Android`根目录下执行`makegpt --help`得到的用法如下：

	$ out/host/linux-x86/bin/makegpt -help 
	Usage: makegpt [options] partitionName,startaddr,size,attr [...]...
	where options may be one of:
	  -b base_address     base address of partition table (mandatory)
	  -s total_disk_size  total disk size in bytes (mandatory)
	  -a                  generate alternate GPT table instead
	  -o  outputfile      output file (mandatory)
	  -v  level           turns on verbose mode. 0=off, 1=normal, 2=debug, 3=noisy
	  -h                  prints this help
	
	  startaddr can be '-' to guess based on previous startaddr+size.
	  size can be '-' to guess based on next startaddr.
	  startaddr and size can be a hex value or a value with suffix K, M, or G.
	
	Example: makegpt -a -b 0x60000 -o gpt_alt.bin -s 0x1e0000000 -- image1,0x10000,0x10000,0 image2,-,64k,0 image3,0x30000,0x30000,0 image4,0x90000,-,0

从上面的`help`信息可见，`makegpt`的使用方式为：
```
makegpt [options] partitionName,startaddr,size,attr [...]...
```

其中，对每个分区的设置如下：

- `partitionName`，指定分区名字
- `startaddr`，指定分区起始地址，如果为“-”，则基于上一分区的起始地址和大小进行计算，即 `previous startaddr + size`
- `size`，指定分区的大小，如果为“-”，则基于下一分区的起始地址进行计算
- `attr`，指定分区的属性，例如`Android`的`system`分区指定属性`0x0001000000000000`（bit 48置1）

### 3.2 `GPT`分区配置文件

这里的`GPT`分区配置文件`default.conf`默认的内容为：

	-s 7818182656 -b 0 -v 3
	macadr,17K,512,0
	nvram,-,64K,0
	bsu,-,256K,0
	misc,1M,1M,0
	hwcfg,-,1M,0
	boot,-,32M,0
	recovery,-,32M,0
	cache,-,256M,0x0001000000000000
	splash,-,12M,0
	metadata,-,12M,0
	tee,-,8M,0
	system,-,1224M,0x0001000000000000
	userdata,-,-,0x0001000000000000

根据`3.1`节对`makegpt`参数的分析，这里主要指定了以下参数：

- `-s total_disk_size`，指定设备的大小（按字节`Byte`计算），为`7818182656`字节
- `-b base_address`，指定分区起始位置，为`0`，从偏移为`0`的地址开始
- `-o  outputfile`，指定生成的`gpt`数据，没有设置，因为已经在调用`makegpt`的命令行中指定
- `-v  level`，`makegpt`执行时输出log的level开关（`0=off, 1=normal, 2=debug, 3=noisy`），这里设置为3，会显示较多的log信息
- `partitionName,startaddr,size,attr`，指定分区参数，这里指定了13个分区：
    1. `macadr,17K,512,0`，从`17K`（第34个`LBA`）开始，大小为512B，属性为0；
    2. `nvram,-,64K,0`，从`macadr`分区结束地址（即`17K+512`)开始，大小为64KB，属性为0；
    3. `bsu,-,256K,0`，从`nvram`分区结束地址开始，大小为256KB，属性为0；
    4. `misc,1M,1M,0`，从绝对地址1MB处开始，大小为1MB，属性为0；
    5. `hwcfg,-,1M,0`，从`misc`分区结束地址开始，大小为1MB，属性为0；
    6. `boot,-,32M,0`，从`hwcfg`分区结束地址开始，大小为32MB，属性为0；
    7. `recovery,-,32M,0`，从`boot`分区结束地址开始，大小为32MB，属性为0；
    8. `cache,-,256M,0x0001000000000000`，从`recovery`分区结束地址开始，大小为256MB，指定属性为`0x0001000000000000`
    9. `splash,-,12M,0`，从`cache`分区结束地址开始，大小为12MB，属性为0；
    10. `metadata,-,12M,0`，从`splash`分区结束地址开始，大小为12MB，属性为0；
    11. `tee,-,8M,0`，从`metadata`分区结束地址开始，大小为8MB，属性为0；
    12. `system,-,1224M,0x0001000000000000`，从`tee`分区结束地址开始，大小为1224MB，指定属性为`0x0001000000000000`
    13. `userdata,-,-,0x0001000000000000`，从`system`分区结束地址开始，包含剩余空间，指定属性为`0x0001000000000000`


> 注意：
>
> 1. __预留了`LBA 0 - LBA 33`用于存放`GPT`数据，所以第一个分区`macadr`从`LBA 34`（即17K）开始__
> 2. __分区划分中，由于`bsu`和`misc`不连续，分区之间会有未使用空间构成的空白区域__

在编译`Android`时，调用`makegpt`生成`gpt.bin`的命令为：

```
out/host/linux-x86/bin/makegpt -o out/target/product/bcm7252ssffdr4/gpt.bin `paste -sd " " device/broadcom/common/gpts/default.conf`
```

这里通过命令`paste -sd " " device/broadcom/common/gpts/default.conf`，将文件`default.conf`输出到命令行作为`makegpt`的调用参数，因此`makegpt`执行的完整命令如下：

	$ out/host/linux-x86/bin/makegpt \
		-o out/target/product/bcm7252ssffdr4/gpt.bin \
		-s 7818182656 \
		-b 0 \
		-v 3 \
		macadr,17K,512,0 \
		nvram,-,64K,0 \
		bsu,-,256K,0 \
		misc,1M,1M,0 \
		hwcfg,-,1M,0 \
		boot,-,32M,0 \
		recovery,-,32M,0 \
		cache,-,256M,0x0001000000000000 \
		splash,-,12M,0 \
		metadata,-,12M,0 \
		tee,-,8M,0 \
		system,-,1224M,0x0001000000000000 \
		userdata,-,-,0x0001000000000000

## 4. 操作eMMC的`boot`分区

eMMC默认出厂时用户可见的分区有4个：

1. `BOOT Area Partition 1`
2. `BOOT Area Partition 2`
3. `User Data Area`
4. `RPMB (Replay Protected Memory Block)`

通常`boot1`分区用于存放启动代码，`boot2`分区用于存放备份代码或配置数据，更多的厂家将`boot2`分区闲置浪费了，因此可以将`boot2`分区利用起来。

`boot`分区默认是`raw`格式，可以在`boot2`分区上写入`GPT`数据创建`GPT`分区。

以下通过`GPT`工具将`boot2`分区设置为`GPT`设备。

### 4.1 用`makegpt`设置`boot2`分区

- `boot2`分区划分

	分区配置文件`boot.conf`:

		-s 4194304 -b 0 -v 3
		data1,17K,512,0
		data2,-,64K,0
		data3,-,256K,0
		data4,-,-,0

- 生成`Primary GPT`

	```$ makegpt -o gpt-primary.bin `paste -sd " " boot.conf````

- 生成`Secondary GPT`

	```$ makegpt -a -o gpt-secondary.bin `paste -sd " " boot.conf````


	将上面生成的`gpt-primary.bin`和`gpt-secondary.bin`分别写入`boot2`分区的`LBA 0`和`LBA - 34`（对于4MB的`boot2`分区，总共有8192个`LBA`, `LBA - 34`对应为`LBA 8158`）即可。


- `BOLT`命令行向`boot2`分区写入`GPT`数据

    - 写入`Primary GPT`:

		`BOLT> flash 192.168.1.100:gpt-primary.bin flash2`

    - 写入`Secondary GPT`到`LBA 8158` (偏移地址：`0x3FBC00`）:

		`BOLT> flash -offset=0x3FBC00 192.168.1.100:gpt-secondary.bin flash2`

		写入后启动提示说备份`GPT`无效，打开`gpt-secondary.bin`发现只占用了2个`LBA`，所以将数据重新写到`LBA - 2`的位置，即`LBA 8190`(偏移地址：`0x3FFC00`)，系统启动正常，写入命令如下：
	
		`BOLT> flash -offset=0x3FFC00 192.168.1.100:gpt-secondary.bin flash2`

## 5. 总结

- `sgdisk`可以在命令行通过命令或脚本任意创建、修改和删除分区，比较灵活；
- `makegpt`根据传入的配置，直接生成所需的`GPT`数据，比较方便，但不灵活；
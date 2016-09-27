#u-boot-2016.09 make编译过程分析（二）

##综述
`u-boot`自`v2014.10`版本开始引入`KBuild`系统，同更改前的编译系统相比，由于`Kbuild`系统的原因，其`Makefile`变得更加复杂。

u-boot的编译跟kernel编译一样，分两步执行：

+ 第一步：配置，执行`make xxx_defconfig`进行各项配置，生成`.config`文件
+ 第二部：编译，执行`make`进行编译，生成可执行的二进制文件u-boot.bin或u-boot.elf

**Makefile的核心是依赖和命令。对于每个目标，首先会检查依赖，如果依赖存在，则执行命令更新目标；如果依赖不存在，则会以依赖为目标，先生成依赖，待依赖生成后，再执行命令生成目标。**

+ 博客《[u-boot-2016.09 make配置过程分析](http://blog.csdn.net/guyongqiangx/article/details/52558087 "u-boot-2016.09 make配置过程分析")》详尽解释了第一步的操作，在这一步中，u-boot执行配置命令`make xxx_defconfig`时先搜集所有默认的`Kconfig`配置，然后再用命令行指定的`xxx_defconfig`配置进行更新并输出到根目录的`.config`文件中。

+ 配置完成后执行make命令生成二进制文件的过程，由于涉及的依赖和命令很多，也将make编译过程分析分为两部分，目标依赖和命令执行。
    + 博客《[u-boot-2016.09 make编译过程分析（一）](http://blog.csdn.net/guyongqiangx/article/details/52565493 "u-boot-2016.09 make编译过程分析（一）")》中描述了`make`过程中的依赖关系
    + 本篇主要分析`make`过程中的通过命令生成各个目标的依赖，从而一步一步更新目标，直至更新并生成顶层目标`u-boot.bin`。

##第二部分、执行命令更新目标
将上面的依赖关系并到一起，就得到了一个完整的`u-boot`目标依赖图：
![完整的目标依赖关系](http://img.blog.csdn.net/20160917232812279)
（完整的关系图较大，可以将图片拖到浏览器的其他窗口看大图）

这些依赖有两类：

+ 依赖本身通过执行命令生成，但不存在进一步的依赖；
+ 依赖自身还有进一步的依赖，在生成了进一步依赖的基础上，执行命令生成依赖；

###1. 命令直接生成的依赖
####1.1 `scripts/kconfig/conf`生成的依赖
+ `.config`
+ `include/generated/autoconf.h`
+ `include/config/auto.conf.cmd`
+ `include/config/tristate.conf`
+ `include/config/auto.conf`

####1.2 
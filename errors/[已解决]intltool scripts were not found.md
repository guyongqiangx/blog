##1. 错误描述
`Ubuntu 14.04` 64位系统编译软件时报告错误：
```
configure: error: The intltool scripts were not found. Please install intltool.
```

详细错误信息：
```
checking for intltool-update... no
checking for intltool-merge... no
checking for intltool-extract... no
configure: error: The intltool scripts were not found. Please install intltool.
make[1]: *** [avahi-0.6.30/.marker_prep1] Error 1
```

##2. 解决办法

从错误信息看，这个错误是由于没有安装`intltool`引起的。

可以通过命令行安装`intltool`解决：
```shell
sudo apt-get install intltool
```

##1. 错误描述
新搭建的`build server`，编译软件时报错：
```
error: possibly undefined macro: AC_PROG_LIBTOOL
```

详细的错误信息如下：
```
[20160926_16:03:11] make[8]: Entering directory `/opt/zyu/CM_develop_d31_clone_zyu/erouter/rg_apps/userspace/public/libs/openssl/crypto/md5'
[20160926_16:03:11] configure.ac:22: error: possibly undefined macro: AC_PROG_LIBTOOL
[20160926_16:03:11]       If this token and others are legitimate, please use m4_pattern_allow.
[20160926_16:03:11]       See the Autoconf documentation.
[20160926_16:03:11] autoreconf: /usr/bin/autoconf failed with exit status: 1
[20160926_16:03:11] make[8]: Leaving directory `/opt/zyu/CM_develop_d31_clone_zyu/erouter/rg_apps/userspace/public/libs/openssl/crypto/md5'
[20160926_16:03:11] making depend in crypto/sha...
[20160926_16:03:11] make[8]: Entering directory `/opt/zyu/CM_develop_d31_clone_zyu/erouter/rg_apps/userspace/public/libs/openssl/crypto/sha'
[20160926_16:03:11] configure: WARNING: you should use --build, --host, --target
[20160926_16:03:11] configure: WARNING: you should use --build, --host, --target
[20160926_16:03:11] configure: WARNING: unrecognized options: --disable-static
[20160926_16:03:11] configure: error: cannot find install-sh, install.sh, or shtool in "." "./.." "./../.."
[20160926_16:03:12] make[5]: *** [sqlite3] Error 1
[20160926_16:03:12] make[5]: *** Waiting for unfinished jobs....

```

##2. 解决办法
检查第一个错误信息：
```
[20160926_16:03:11] configure.ac:22: error: possibly undefined macro: AC_PROG_LIBTOOL
```
从错误信息看，是在处理`configure.ac`文件时出错了，认为`AC_PROG_LIBTOOL`是未定义的宏，使得执行`autoconf`失败，安装`libtool`包得以解决：
```
sudo apt-get install libtool
```
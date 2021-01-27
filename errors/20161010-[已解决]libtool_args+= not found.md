##1. 错误描述
编译软件时报告错误：
```
eval: libtool_args+=: not found
```

详细的错误信息如下：
```shell
...
/opt/ygu/android-l/kernel/private/bcm-97xxx/rootfs/lib/popt/libtool: 1: eval: libtool_args+=: not found
/opt/ygu/android-l/kernel/private/bcm-97xxx/rootfs/lib/popt/libtool: 1: eval: compile_command+=: not found
/opt/ygu/android-l/kernel/private/bcm-97xxx/rootfs/lib/popt/libtool: 1: eval: finalize_command+=: not found
...
```

##2. 解决办法
`Ubuntu`系统默认`shell`为`dash`，需要切换到`bash`。
运行命令：
```shell
sudo dpkg-reconfigure dash
```

在弹出的对话框中选择`No`，系统会将默认`shell`设置为`bash`：
```shell
ygu@stb-lab-04:~$ sudo dpkg-reconfigure dash
[sudo] password for ygu: 
Removing 'diversion of /bin/sh to /bin/sh.distrib by dash'
Adding 'diversion of /bin/sh to /bin/sh.distrib by bash'
Removing 'diversion of /usr/share/man/man1/sh.1.gz to /usr/share/man/man1/sh.distrib.1.gz by dash'
Adding 'diversion of /usr/share/man/man1/sh.1.gz to /usr/share/man/man1/sh.distrib.1.gz by bash'
ygu@stb-lab-04:~$  
```
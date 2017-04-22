# 基于Ubuntu搭建NIS Slave服务

## 1. 背景

### 1.1 一大段废话
由于公司某些业务变更的原因，将服务器从原来的IT部分转到了BU，并且没有了支持，所有事情都得自力更生。

迁移过来的多台服务器中有两台NIS服务器，系统是`Sun OS 5.10`（即`Solaris 10`），好吧，我是`Solaris`小白，也不打算再花时间去学习这个东东，但又担心哪天系统挂了或坏了就悲剧了。

所以决定在现有的`Ubuntu`上先做一个`NIS Slave`吧，即使系统被挂了或者被IT拿走了，还能用这个`Slave`顶一顶。

由于`NIS`服务主要是一些查询，本身对服务器性能要求不高，手上的台式老机`DELL T3400`用来做`Slave`也是绰绰有余的啦。好吧，我比较懒，不想重装为`CentOS`或者`Ubuntu Server`了，够用就好啦。

### 1.2 搭建环境

整个环境简述如下：

1. 原有两台`NIS`服务器，系统为`Solaris 10`
  - NIS Master， nis1.she.guyongqiangx.com
  - NIS Slave，nis2.she.guyongqiangx.com
2. 新增一台`NIS`服务器，系统为`Ubuntu 12.04.5 LTS`
  - 备份 NIS Slave，nis3.she.guyongqiangx.com

整个操作分为两大部分：

1. NIS Master上新增Slave服务器nis3
2. 在nis3上将服务器设置为NIS Slave

## 2. NIS Master上新增Slave nis3

在网上找到一个基于`Solaris 11.2`新增`NIS Slave`的说明：

[How to Add a New Slave Server](https://docs.oracle.com/cd/E36784_01/html/E36831/anis2-proc-51.html)

> 这篇文章是基于`Solaris 11.2`的，奇怪的是我之前曾经按照这里面的步骤在`Solaris 10`上运行的时候失败了，但是这次当我再次验证这个步骤的时候却又是成功的，如果有遇到同样问题的请告诉我。

以下是我的操作记录：

1. 进入`/var/yp`目录

	```
	# cd /var/yp
	# ls -lh
	total 12124
	lrwxrwxrwx   1 root     root          14 Jan 14  2009 Makefile -> ./etc/Makefile
	drwxr-xr-x   5 root     root         512 Jan 14  2009 OLD
	-rw-r--r--   1 root     root         194 Sep 18  2008 aliases
	drwxr-xr-x   3 root     bin          512 Oct  1  2016 binding
	-rw-------   1 root     root        5.9M May 12  2011 core
	lrwxrwxrwx   1 root     root          21 Jun 27  2009 etc -> /tools/admin/site/etc
	-rw-r--r--   1 root     bin          226 Jan 22  2005 nicknames
	drwxr-xr-x   2 root     root        2.0K Apr 19 15:35 she
	drwxr-xr-x   2 root     root        1.0K Apr 19 15:35 timestamps
	-r-x------   1 root     bin          870 Jan 22  2005 updaters
	```

2. 执行`makedbm`对`ypservers`数据文件进行反编译

	```
	# which makedbm
	/usr/sbin/makedbm
	# makedbm -u she/ypservers > temp-file
	# cat temp-file
	nis2.she.guyongqiangx.com 
	nis1.she.guyongqiangx.com 
	YP_LAST_MODIFIED 1241053445
	YP_MASTER_NAME nis1.she.guyongqiangx.com
	```

3. 编辑`temp-file`，添加`nis3`

	```
	# cat temp-file
	nis3.she.guyongqiangx.com
	nis2.she.guyongqiangx.com 
	nis1.she.guyongqiangx.com 
	YP_LAST_MODIFIED 1492590247
	YP_MASTER_NAME nis1.she.guyongqiangx.com
	```

4. 编译`temp-file`重新生成数据库文件

	```
	# makedbm temp-file ypservers
	```

5. 在`nis2`上验证`ypservers`的内容



## 3. nis3上设置为NIS Slave服务

### 3.1 修改IP

根据`nis3`的环境修改`IP`和路由等设置，修改后如下：

	ygu@stbszx-adm-1:~$ cat /etc/network/interfaces 
	auto lo
	iface lo inet loopback
	
	auto eth0
	iface eth0 inet static
	    address 10.148.7.35
	    netmask 255.255.254.0
	    gateway 10.148.6.1
	    dns-nameservers 192.19.189.30 192.19.189.10
	    dns-search she.guyongqiangx.com guyongqiangx.com she.guyongqiangx.net guyongqiangx.net

### 3.2 修改hostname

原有hostname为`stbszx-adm-1`，修改为`nis3`，如下：

	ygu@stbszx-adm-1:~$ cat /etc/hostname 
	nis3

### 3.3 修改hosts

修改hosts文件，添加对本机nis3以及nis1和nis2的hostname和IP映射：

	ygu@stbszx-adm-1:~$ cat /etc/hosts
	127.0.0.1       localhost
	10.148.7.35     nis3 nis3.she.guyongqiangx.com nis3.she.guyongqiangx.net
	
	# The following lines are desirable for IPv6 capable hosts
	::1     ip6-localhost ip6-loopback
	fe00::0 ip6-localnet
	ff00::0 ip6-mcastprefix
	ff02::1 ip6-allnodes
	ff02::2 ip6-allrouters
	
	# 2017-04-22 adminbse ygu - NIS servers
	10.148.138.17   nis2.she.guyongqiangx.com
	10.148.138.16   nis1.she.guyongqiangx.com

### 3.4 重启并检查设置

由于主机名等设置需要重启才能生效，所以在安装NIS组件前重启电脑

	ygu@stbszx-adm-1:~$ sudo shutdown -r now
	
	Broadcast message from ygu@stbszx-adm-1
	        (/dev/pts/1) at 15:55 ...
	
	The system is going down for reboot NOW!

检查 3.1-3.3的所有设置是否生效：

	ygu@nis3:~$ hostname
	nis3
	ygu@nis3:~$ ifconfig eth0
	eth0      Link encap:Ethernet  HWaddr 00:10:18:55:8c:b0  
	          inet addr:10.148.7.35  Bcast:10.148.7.255  Mask:255.255.254.0
	          inet6 addr: fe80::210:18ff:fe55:8cb0/64 Scope:Link
	          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
	          RX packets:720 errors:0 dropped:0 overruns:0 frame:0
	          TX packets:260 errors:0 dropped:0 overruns:0 carrier:0
	          collisions:0 txqueuelen:1000 
	          RX bytes:91702 (91.7 KB)  TX bytes:38110 (38.1 KB)
	          Interrupt:16 
	
### 3.5 安装NIS组件

`nis`服务基于`rpcbind`提供服务，所以需要同时安装`rpcbind`和`nis`组件，

	ygu@nis3:~$ sudo apt-get install rpcbind nis

安装nis时会弹出设置NIS domain的对话框，这里填写为`she`：
![set nis domainname](https://github.com/guyongqiangx/blog/blob/dev/nis/images/config-nis-domain.png?raw=true)

这个对话框实际上是创建文件`/etc/defaultdomain`，并写入内容`she`，如下：

	ygu@nis3:~$ cat /etc/defaultdomain 
	she

### 3.6 配置NIS

####3.6.1 配置

	ygu@nis3:~$ sudo /usr/lib/yp/ypinit -s nis1.she.guyongqiangx.com
	We will need a few minutes to copy the data from nis1.she.guyongqiangx.com.
	Transferring auto_tools...
	Transferring auto_projects...
	Transferring auto_home...
	Transferring auto_master...
	Transferring netmasks.byaddr...
	Transferring netgroup.byhost...
	Transferring netgroup.byuser...
	Transferring netgroup...
	Transferring services.byservicename...
	Transferring services.byname...
	Transferring passwd.adjunct.byname...
	Transferring ethers.byaddr...
	Transferring ethers.byname...
	Transferring hosts.byaddr...
	Transferring hosts.byname...
	Transferring group.bygid...
	Transferring group.byname...
	Transferring passwd.byuid...
	Transferring ypservers...
	Transferring passwd.byname...
	
	nis3's NIS data base has been set up.
	If there were warnings, please figure out what went wrong, and fix it.
	
	At this point, make sure that /etc/passwd and /etc/group have
	been edited so that when the NIS is activated, the data bases you
	have just created will be used, instead of the /etc ASCII files.

#### 3.6.2 验证ypservers设置

	ygu@nis3:/var/yp$ find /usr -type f -name makedbm
	/usr/lib/yp/makedbm
	ygu@nis3:/var/yp$ sudo /usr/lib/yp/makedbm -u she/ypservers 
	nis2.she.guyongqiangx.com
	nis1.she.guyongqiangx.com
	YP_LAST_MODIFIED        1492590247
	YP_MASTER_NAME  nis1.she.guyongqiangx.com
	nis3.she.guyongqiangx.com   nis3.she.guyongqiangx.com

  显然，这里`she/ypservers`文件里面已经包含了`nis1`，`nis2`和`nis3`了。

#### 3.6.3 修改`/etc/default/nis`

主要修改包括：

- 设置为`NIS Slave Server`

    `NISSERVER=false` 修改为 `NISSERVER=slave`

- 关闭当前作为`NIS`客户端（如果本机既作为`Slave Sever`，又作为`Client`则不要停需要改）

    `NISCLIENT=true` 修改为 `NISCLIENT=false`

- 设置`NIS Master`

    `NISMASTER=` 修改为 `NISMASTER=nis1.she.guyongqiangx.com`

修改后的内容如下：

	ygu@nis3:~$ cat /etc/default/nis 
	#
	# /etc/defaults/nis     Configuration settings for the NIS daemons.
	#
	
	# Are we a NIS server and if so what kind (values: false, slave, master)?
	NISSERVER=slave
	
	# Are we a NIS client?
	NISCLIENT=false
	
	# Location of the master NIS password file (for yppasswdd).
	# If you change this make sure it matches with /var/yp/Makefile.
	YPPWDDIR=/etc
	
	# Do we allow the user to use ypchsh and/or ypchfn ? The YPCHANGEOK
	# fields are passed with -e to yppasswdd, see it's manpage.
	# Possible values: "chsh", "chfn", "chsh,chfn"
	YPCHANGEOK=chsh
	
	# NIS master server.  If this is configured on a slave server then ypinit
	# will be run each time NIS is started.
	NISMASTER=nis1.she.guyongqiangx.com
	
	# Additional options to be given to ypserv when it is started.
	YPSERVARGS=
	
	# Additional options to be given to ypbind when it is started.  
	YPBINDARGS=-no-dbus
	
	# Additional options to be given to yppasswdd when it is started.  Note
	# that if -p is set then the YPPWDDIR above should be empty.
	YPPASSWDDARGS=
	
	# Additional options to be given to ypxfrd when it is started. 
	YPXFRDARGS=

如果不修改`/etc/defaults/nis`，则启动`ypserv`会失败，查询`rpc`服务也找不到`ypserv`信息，如下：

	ygu@nis3:/var/yp$ sudo service ypserv start
	ypserv stop/waiting
	ygu@nis3:/var/yp$ rpcinfo -p nis3.she.guyongqiangx.com
	   program vers proto   port  service
	    100000    4   tcp    111  portmapper
	    100000    3   tcp    111  portmapper
	    100000    2   tcp    111  portmapper
	    100000    4   udp    111  portmapper
	    100000    3   udp    111  portmapper
	    100000    2   udp    111  portmapper
	    100007    2   udp    612  ypbind
	    100007    1   udp    612  ypbind
	    100007    2   tcp    613  ypbind
	    100007    1   tcp    613  ypbind

### 3.7 启动`ypserv`服务

重新启动`ypserv`并查询其`rpc`服务：

	ygu@nis3:/var/yp$ sudo service ypserv restart
	stop: Unknown instance: 
	ypserv start/running, process 4817
	ygu@nis3:/var/yp$ rpcinfo -p nis3
	   program vers proto   port  service
	    100000    4   tcp    111  portmapper
	    100000    3   tcp    111  portmapper
	    100000    2   tcp    111  portmapper
	    100000    4   udp    111  portmapper
	    100000    3   udp    111  portmapper
	    100000    2   udp    111  portmapper
	    100007    2   udp    612  ypbind
	    100007    1   udp    612  ypbind
	    100007    2   tcp    613  ypbind
	    100007    1   tcp    613  ypbind
	    100004    2   udp    753  ypserv
	    100004    1   udp    753  ypserv
	    100004    2   tcp    754  ypserv
	    100004    1   tcp    754  ypserv
	ygu@nis3:/var/yp$ sudo service ypserv restart
	ypserv stop/waiting
	ypserv start/running, process 4859

由于第一次启动误用了`restart`指令，所以会提示`stop: Unknow instance`，正常启动后再使用`restart`就不会有这个提示了。

## 4.登录验证

在另外一台CentOS终端上配置并使用`nis3`提供的`nis`服务

1. 命令行运行`setup`命令，弹出对话框

    ![运行setup命令](https://github.com/guyongqiangx/blog/blob/dev/nis/images/nis3-client-setup.png?raw=true)

2. 选择“`Authentication Information`”设置验证方式，弹出对话框中选择“`Use NIS`”

    ![设置NIS验证](https://github.com/guyongqiangx/blog/blob/dev/nis/images/nis3-client-select-nis.png?raw=true)

3. 在`NIS Settings`对话框中设置`Domain`为`she`，`Server`为`nis3.she.guyongqiangx.com`，如下：

    ![设置NIS domain和server](https://github.com/guyongqiangx/blog/blob/dev/nis/images/nis3-client-nis-setting.png?raw=true)

  设置完成后点击OK，返回命令行。

运行`yptest`可以看到各项测试结果，说明`nis3`已经可以正常工作了。
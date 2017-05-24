##1. 安装`Ubuntu 14.04`系统
`Android`系统编译推荐使用基于`Ubuntu`的64位系统。`Ubuntu 12.04`比较老了，`Ubuntu 16.04`又太新，这里选择`Ubuntu 14.04`的64位桌面版本。

下载地址：[`http://releases.ubuntu.com/14.04/`](http://releases.ubuntu.com/14.04/)

##2. 安装`ssh`
安装完系统的第一件事情就是安装`ssh`，这样就可以远程登录操作了。

+ 安装`openssh`

`sudo apt-get install openssh-server`

+ 检查`ssh`服务

`sudo ps -e | grep ssh`

+ 修改配置

执行`sudo vim /etc/ssh/sshd_config`命令修改默认配置：

`PermitRootLogin without-password --> PermitRootLogin yes`

**实际上这项是针对root用户登录，如果不需要root用录，可以忽略此步骤**

+ 重启`ssh`服务

`sudo service ssh restart`

##3. 安装`Java`
编译`Android`需要安装`Java`，不同版本的`Android`需要不同版本的`Java`，在编译不同版本的`Android`时需要在这些版本之间切换。具体各版本对`Java`环境的要求如下：

+ `KitKat`及以下需要`Java6`
+ `Lollipop`和`Marshmallow`需要`Java7`
+ `AOSP`的`master`分支，以及`Nougat`需要`Java8`

通过`PPA(Personal Package Archives)`源进行安装，比较方便：

+ 安装`java6`

```shell
sudo add-apt-repository ppa:webupd8team/java
sudo apt-get update
sudo apt-get install oracle-java6-installer
```

同样的方法可以通过命令安装基于oracle的java7, java8和java9：

```
sudo apt-get install oracle-java{6,7,8,9}-installer
```

+ 安装`java7`和`java8`

> `Ubuntu 14.04`默认包含了`java7`的安装源，直接执行安装命令即可：`sudo apt-get install openjdk-7-jdk`


```shell
sudo add-apt-repository ppa:openjdk-r/ppa
sudo apt-get update
sudo apt-get install openjdk-7-jdk
sudo apt-get install openjdk-8-jdk
```

+ `Java`各个版本之间的切换：

```shell
sudo update-alternatives --config java
sudo update-alternatives --config javac
sudo update-alternatives --config javadoc
```

以下是`java`从`java-7-openjdk`切换到`java-6-oracle`的例子：

```shell
$ sudo update-alternatives --config java
There are 3 choices for the alternative java (providing /usr/bin/java).

  Selection    Path                                            Priority   Status
------------------------------------------------------------
* 0            /usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java   1071      auto mode
  1            /usr/lib/jvm/java-6-oracle/jre/bin/java          1         manual mode
  2            /usr/lib/jvm/java-7-openjdk-amd64/jre/bin/java   1071      manual mode
  3            /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java   1069      manual mode

Press enter to keep the current choice[*], or type selection number: 1
update-alternatives: using /usr/lib/jvm/java-6-oracle/jre/bin/java to provide /usr/bin/java (java) in manual mode
$ 
```

##4. 安装`android`编译工具链
以下是仅针对`Ubuntu 14.04`的安装命令，其它版本如`Ubuntu 12.04`需要安装的软件跟这个命令中的不一样：
```shell
sudo apt-get install bison g++-multilib git gperf libxml2-utils make zlib1g-dev:i386 zip
```

+ `g++-multilib`安装错误
安装中会出现错误：
```
ygu@stb-lab-04:~$ sudo apt-get install bison g++-multilib git gperf libxml2-utils make zlib1g-dev:i386 zip
[sudo] password for ygu: 
Reading package lists... Done
Building dependency tree       
Reading state information... Done
make is already the newest version.
make set to manually installed.
zip is already the newest version.
zip set to manually installed.
Some packages could not be installed. This may mean that you have
requested an impossible situation or if you are using the unstable
distribution that some required packages have not yet been created
or been moved out of Incoming.
The following information may help to resolve the situation:

The following packages have unmet dependencies:
 g++-multilib : Depends: gcc-multilib (>= 4:4.8.2-1ubuntu6) but it is not going to be installed
                Depends: g++ (>= 4:4.8.2-1ubuntu6) but it is not going to be installed
                Depends: g++-4.8-multilib (>= 4.8.2-5~) but it is not going to be installed
E: Unable to correct problems, you have held broken packages.
```
根据提示`g++-multilib`依赖于`gcc-multilib`，`g++`或`g++-4.8-multilib`，先安装其中一个：

```
sudo apt-get install gcc-multilib g++
```

再次执行安装命令即可。

+ 其它安装包
除了以上的安装包外，部分机器因为编译其它软件可能还需要额外的安装包，例如：
```
sudo apt-get install flex zlib1g-dev:amd64
```

+ 更新后的安装列表
根据以上操作，修改为安装以下软件列表：
```shell
sudo apt-get install bison g++ g++-multilib git gperf libxml2-utils make zlib1g-dev:i386 zip
```


##5. 安装`samba`

+ 安装`samba`服务端
```shell
sudo apt-get install samba samba-common
```
+ 编辑`samba.conf`
```
sudo vim /etc/samba/smb.conf 
```
新增`/opt`目录作为共享目录，并需要登录才能访问：
```
[opt]
   comment = opt
   path = /opt
   writeable = yes
   browseable = yes
#  valid users = %S
   guest ok = no
```

+ 添加`samba`用户

将现有用户`ygu`添加作为`samba`用户，如果想新增一个用户，需要现在`Ubuntu`系统中添加该用户后再用`smbpasswd -a`添加。
```shell
ygu@stb-lab-04:~$ sudo smbpasswd -a ygu
New SMB password:
Retype new SMB password:
Added user ygu.
```

+ 重启`samba`服务
```shell 
ygu@stb-lab-04:~$ sudo service nmbd restart
nmbd stop/waiting
nmbd start/running, process 20361
ygu@stb-lab-04:~$ sudo service smbd restart
smbd stop/waiting
smbd start/running, process 20340
```

>**为什么需要同时重启`nmbd`和`smbd`两项服务？**
>
>`Samba`服务器包括两个后台应用程序: `smbd`和`nmbd`。<br>
> + `smbd`是`Samba`的核心, 主要负责建立`Samba`服务器与`Samba`客户机之间的对话, 验证用户身份并提供对文件和打印系统的访问; <br>
> + `nmbd`主要负责对外发布`Samba`服务器可以提供的`NetBIOS`名称和浏览服务,使`Windows`用户可以在“网上邻居”中浏览`Samba`服务器中共享的资源。

##6. 安装`tftp`
+ 安装`tftp`服务端
```shell
sudo apt-get install xinetd tftpd tftp
```
+ 配置`tftp`服务
执行`sudo vim /etc/xinetd.d/tftp`命令按如下内容编辑`/etc/xinetd.d/tftp`文件：
```
service tftp
{
protocol = udp
port = 69
socket_type = dgram
wait = yes
user = nobody
server = /usr/sbin/in.tftpd
server_args = /tftpboot
disable = no
}
```
+ 创建`tftp`目录并设置权限
```shell
sudo mkdir /tftpboot
sudo chmod -R 777 /tftpboot
sudo chown -R nobody /tftpboot
```
+ 重启`xinetd`服务
```shell
sudo service xinetd restart
```
##7. 安装`NFS`服务

+ 安装`NFS`服务端
```shell
sudo apt-get install nfs-kernel-server
```
+ 创建`NFS`服务目录
```
mkdir -p /opt/nfs
```
+ 编辑`/etc/exports`
```
/opt/nfs *(rw,sync,no_root_squash,no_subtree_check)
```
+ 启动`NFS server`
```
sudo service nfs-kernel-server restart
```
+ 检查`NFS`目录
```
ygu@stb-lab-04:/opt$ sudo showmount -e
Export list for stb-lab-04:
/opt/nfs *
```
##8. 启动进入命令行界面
对于`build server`，默认并不需要图形界面，所以选择开机直接进入命令行界面。

以下是修改配置文件使开机进入命令行的一种简便方法。

+ 编辑`grub`文件

执行`sudo vim /etc/default/grub`命令
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
```
修改为：
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash text"
```
保存并退出

+ 执行`update-grub`
```shell
sudo update-grub
```
`update-grub`操作会更新`/boot/grub/grub.cfg`文件，重启后就会使用这个修改后的配置直接进入命令行。

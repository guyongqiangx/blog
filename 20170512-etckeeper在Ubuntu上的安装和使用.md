# etckeeper在Ubuntu上的安装和使用

Linux系统上安装软件最痛苦的事情莫过于配置过程，这其中etc文件的各种修改、各种备份、各种还原，有时候真是想死啊~~

好吧，etckeeper就是用来解救etc修改和备份的~~

本质上，etckeeper是基于版本系统进行管理的，但为什么不直接使用版本系统（如git）进行备份管理呢？

实际上也可以直接用版本系统来管理/etc文件夹的，但是etckeeper在版本管理系统基础上针对/etc的使用场景进行了改进。

主要有以下几点（版本系统以git为例）：

1. etckeeper和git都可以进行文件系统的版本管理，但是etckeeper还保存了文件的元数据，如mode和group信息等
2. git和mercurial不能跟踪空文件夹，但是/etc下存在部分重要的空文件夹需要跟踪管理
3. etckeeper在安装和升级软件包前后可以自动提交/etc文件夹改动的内容
4. etckeeper可以每天进行备份提交

以下是etckeeper在Ubuntu 14.04.5上的安装和使用介绍。

## 1. etckeeper的安装

### 1.1 安装git

最常见的是etckeeper内部使用git进行版本管理，所以需要先安装git

	ygu@ubuntu:~$ sudo apt-get install git-core 

### 1.2 安装etckeepr

	ygu@ubuntu:~$ sudo apt-get install etckeeper 
	Reading package lists... Done
	Building dependency tree       
	Reading state information... Done
	The following NEW packages will be installed:
	  etckeeper
	0 upgraded, 1 newly installed, 0 to remove and 248 not upgraded.
	Need to get 26.7 kB of archives.
	After this operation, 216 kB of additional disk space will be used.
	Get:1 http://mirrors.aliyun.com/ubuntu/ trusty/main etckeeper all 1.9ubuntu2 [26.7 kB]
	Fetched 26.7 kB in 0s (58.6 kB/s)
	Preconfiguring packages ...
	Selecting previously unselected package etckeeper.
	(Reading database ... 178087 files and directories currently installed.)
	Preparing to unpack .../etckeeper_1.9ubuntu2_all.deb ...
	Unpacking etckeeper (1.9ubuntu2) ...
	Processing triggers for man-db (2.6.7.1-1ubuntu1) ...
	Setting up etckeeper (1.9ubuntu2) ...
	etckeeper init not ran as bzr is not installed

etckeepr安装消息的最后一步提示说，由于`bzr`没有安装，所以没有运行`etckeeper init`进行初始化。

## 2. etckeeper的配置

### 2.1 配置文件路径

默认情况下，配置文件etckeeper.conf位于/etc/etckeeper文件夹内：

	ygu@ubuntu:~$ cd /etc/etckeeper   
	ygu@ubuntu:/etc/etckeeper$ ls -lh
	total 44K
	drwxr-xr-x 2 root root 4.0K May 12 14:44 commit.d
	-rw-r--r-- 1 root root 1.2K Feb 23  2014 etckeeper.conf
	drwxr-xr-x 2 root root 4.0K May 12 14:44 init.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 list-installed.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 post-install.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 pre-commit.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 pre-install.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 unclean.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 uninit.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 update-ignore.d
	drwxr-xr-x 2 root root 4.0K May 12 14:44 vcs.d

### 2.2 配置文件内容

安装好etckeeper后默认的配置内容如下：

	ygu@ubuntu:/etc/etckeeper$ cat etckeeper.conf 
	# The VCS to use.
	#VCS="hg"
	#VCS="git"
	VCS="bzr"
	#VCS="darcs"
	
	# Options passed to git commit when run by etckeeper.
	GIT_COMMIT_OPTIONS=""
	
	# Options passed to hg commit when run by etckeeper.
	HG_COMMIT_OPTIONS=""
	
	# Options passed to bzr commit when run by etckeeper.
	BZR_COMMIT_OPTIONS=""
	
	# Options passed to darcs record when run by etckeeper.
	DARCS_COMMIT_OPTIONS="-a"
	
	# Uncomment to avoid etckeeper committing existing changes
	# to /etc automatically once per day.
	#AVOID_DAILY_AUTOCOMMITS=1
	
	# Uncomment the following to avoid special file warning
	# (the option is enabled automatically by cronjob regardless).
	#AVOID_SPECIAL_FILE_WARNING=1
	
	# Uncomment to avoid etckeeper committing existing changes to 
	# /etc before installation. It will cancel the installation,
	# so you can commit the changes by hand.
	#AVOID_COMMIT_BEFORE_INSTALL=1
	
	# The high-level package manager that's being used.
	# (apt, pacman-g2, yum, zypper etc)
	HIGHLEVEL_PACKAGE_MANAGER=apt
	
	# The low-level package manager that's being used.
	# (dpkg, rpm, pacman, pacman-g2, etc)
	LOWLEVEL_PACKAGE_MANAGER=dpkg
	
	# To push each commit to a remote, put the name of the remote here.
	# (eg, "origin" for git).
	PUSH_REMOTE=""

根据需要对etckeepr.conf进行修改，常见的改动有两项（包括用git进行管理和取消每天自动提交）：

1. 使用git进行版本管理

	将

		#VCS="git"
		VCS="bzr"
	
	修改为：
	
		VCS="git"
		#VCS="bzr"

2. 根据需要决定是否每天进行备份提交

	如果不进行每天备份提交，将

		#AVOID_DAILY_AUTOCOMMITS=1

	修改为：

		AVOID_DAILY_AUTOCOMMITS=1

	etckeeper的设置选项意思很浅显，也带有很清楚的注释，其它选项可以根据实际需要进行修改。

## 3. etckeeper的使用

### 3.1 初始化

配置完etckeeper后的第一件事就是初始化。

	ygu@ubuntu:/etc/etckeeper$ sudo etckeeper init
	Initialized empty Git repository in /etc/.git/

如果不希望使用原来保存的历史，可以通过`etckeeper uninit`命令销毁历史记录。
	ygu@ubuntu:/etc$ sudo etckeeper uninit
	** Warning: This will DESTROY all recorded history for /etc,
	** including the git repository.
	
	Are you sure you want to do this? [yN] y
	Proceeding..

如果安装etckeeper时已经使用bzr版本管理进行过初始化，则配置git管理时需要先`etckeeper uninit`再进行`etckeeper init`操作。

### 3.2 提交修改

初始化完后，进行提交。

	ygu@ubuntu:/etc$ sudo etckeeper commit "initial commit"

每次对/etc改动后也使用`etckeeper commit`来提交。

`etckeeper`安装配置好后，日常维护只需要会这一个`etckeeper commit`操作就够了，简单不？

### 3.3 版本和分支管理

etckeeper没有提供单独的取消修改和分支创建切换的命令，这些操作都是通过git来进行，例如创建和切换分支，撤销和回溯版本等。

但是通过git更新文件后需要运行`etckeeper init`来更新文件属性。

例如，使用git切换到backup分支：

	ygu@ubuntu:/etc$ sudo git checkout backup
	ygu@ubuntu:/etc$ sudo etckeeper init

### 3.4 远程备份

/etc文件夹的内容，可以通过git推送到远程仓库实现备份，具体步骤如下：

	# ssh登录guyongqiangx在目录/opt/etc-backup下创建远程库
	# ssh 登录
	ygu@ubuntu:/etc$ ssh ygu@guyongqiangx
	ygu@guyongqiangx:~$ mkdir -p /opt/etc-backup
	ygu@guyongqiangx:~$ cd /opt/etc-backup/
	ygu@guyongqiangx:/opt/etc-backup$ chmod 700 .
	# 创建版本库
	ygu@guyongqiangx:/opt/etc-backup$ git init --bare
	Initialized empty Git repository in /opt/etc-backup/

	#
	# 以上操作也可以通过一条ssh命令来完成：
	# ssh ygu@guyongqiangx 'mkdir -p /opt/etc-backup; cd /opt/etc-backup; chmod 700 .; git init --bare'
	#

	# 本地注册guyongqiangx服务器的远程库
	# 注册远程库
	ygu@ubuntu:/etc$ sudo git remote add backup ssh://ygu@guyongqiangx/opt/etc-backup
	# 显示远程库信息
	ygu@ubuntu:/etc$ sudo git remote -v
	backup  ssh://ygu@guyongqiangx/opt/etc-backup (fetch)
	backup  ssh://ygu@guyongqiangx/opt/etc-backup (push)

	# 将/etc内容推送到guyongqiangx的远程库
	# 推送到远程库
	ygu@ubuntu:/etc$ sudo git push backup --all
	# 输入远程服务器登录密码
	ygu@guyongqiangx's password: 
	Counting objects: 2488, done.
	Delta compression using up to 2 threads.
	Compressing objects: 100% (1912/1912), done.
	Writing objects: 100% (2488/2488), 1.73 MiB | 1.13 MiB/s, done.
	Total 2488 (delta 341), reused 0 (delta 0)
	To ssh://ygu@guyongqiangx/opt/etc-backup
	 * [new branch]      master -> master

如果etckeeper有将数据备份到远程，最重要是要确保数据安全，例如，上面步骤中命令`chmod 700 .`将远程库的目录设置为只读。

> !!!
> 将远程目录设置为700模式远远不够，因为备份的/etc目录下包含shadow文件，一旦远程备份目录被读取，所有/etc下的重要数据都泄露了。

## 4. 废话太多，简单总结

以上内容比较多，最常见的操作有以下四个：

	# 安装
	$ apt-get install git-core etckeeper
	
	# 修改配置文件，VCS="git"，AVOID_DAILY_AUTOCOMMITS=1
	$ vi /etc/etckeeper/etckeeper.conf
	
	# 初始化并第1次提交
	$ etckeeper init
	$ etckeeper commit "initial commit"
	
	# 修改文件/etc/xxx并提交
	$ vi /etc/xxx
	$ etckeeper commit "commit message"

好吧，日常维护就只有`etckeeper commit`一条指令。
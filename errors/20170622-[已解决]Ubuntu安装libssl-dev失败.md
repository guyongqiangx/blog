最近打算用Python3写一个签名验证工具，安装`pyOpenSSL`时需要用到本机的`libssl-dev`库，进一步在Ubuntu上尝试安装库时出错，如下：
```
ygu@guyongqiangx:~$ sudo apt-get install libssl-dev
Reading package lists... Done
Building dependency tree       
Reading state information... Done
Some packages could not be installed. This may mean that you have
requested an impossible situation or if you are using the unstable
distribution that some required packages have not yet been created
or been moved out of Incoming.
The following information may help to resolve the situation:

The following packages have unmet dependencies:
 libssl-dev : Depends: libssl1.0.0 (= 1.0.1f-1ubuntu2) but 1.0.1f-1ubuntu2.19 is to be installed
              Recommends: libssl-doc but it is not going to be installed
E: Unable to correct problems, you have held broken packages.
```

度娘搜索提示说建议使用aptitude进行安装

```
ygu@guyongqiangx:~$ sudo apt-get install aptitude
Reading package lists... Done
Building dependency tree       
Reading state information... Done
aptitude is already the newest version.
0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
```
发现我原来已经安装过aptitude了

使用aptitude再次安装libssl-dev，并选择降级的版本。
```
ygu@guyongqiangx:~$ sudo aptitude install libssl-dev
The following NEW packages will be installed:
  libssl-dev{b} libssl-doc{a} 
0 packages upgraded, 2 newly installed, 0 to remove and 0 not upgraded.
Need to get 2,031 kB of archives. After unpacking 7,801 kB will be used.
The following packages have unmet dependencies:
 libssl-dev : Depends: libssl1.0.0 (= 1.0.1f-1ubuntu2) but 1.0.1f-1ubuntu2.19 is installed.
The following actions will resolve these dependencies:

     Keep the following packages at their current version:
1)     libssl-dev [Not Installed]                         


# 这里提示时，一定要选n，选Y跟apt-get install操作一样
Accept this solution? [Y/n/q/?] n
The following actions will resolve these dependencies:

     Downgrade the following packages:                                   
1)     libssl1.0.0 [1.0.1f-1ubuntu2.19 (now) -> 1.0.1f-1ubuntu2 (trusty)]


# 接受这里的降级处理，成功安装
Accept this solution? [Y/n/q/?] y
The following packages will be DOWNGRADED:
  libssl1.0.0 
The following NEW packages will be installed:
  libssl-dev libssl-doc{a} 
0 packages upgraded, 2 newly installed, 1 downgraded, 0 to remove and 0 not upgraded.
Need to get 2,857 kB of archives. After unpacking 7,784 kB will be used.
Do you want to continue? [Y/n/?] y
Get: 1 http://mirrors.aliyun.com/ubuntu/ trusty/main libssl1.0.0 amd64 1.0.1f-1ubuntu2 [825 kB]                     
Get: 2 http://mirrors.aliyun.com/ubuntu/ trusty/main libssl-doc all 1.0.1f-1ubuntu2 [965 kB]                        
Get: 3 http://mirrors.aliyun.com/ubuntu/ trusty/main libssl-dev amd64 1.0.1f-1ubuntu2 [1,066 kB]                    
Fetched 2,857 kB in 50s (57.1 kB/s)                                                                                 
Preconfiguring packages ...
dpkg: warning: downgrading libssl1.0.0:amd64 from 1.0.1f-1ubuntu2.19 to 1.0.1f-1ubuntu2
(Reading database ... 234481 files and directories currently installed.)
Preparing to unpack .../libssl1.0.0_1.0.1f-1ubuntu2_amd64.deb ...
Unpacking libssl1.0.0:amd64 (1.0.1f-1ubuntu2) over (1.0.1f-1ubuntu2.19) ...
Selecting previously unselected package libssl-dev:amd64.
Preparing to unpack .../libssl-dev_1.0.1f-1ubuntu2_amd64.deb ...
Unpacking libssl-dev:amd64 (1.0.1f-1ubuntu2) ...
Selecting previously unselected package libssl-doc.
Preparing to unpack .../libssl-doc_1.0.1f-1ubuntu2_all.deb ...
Unpacking libssl-doc (1.0.1f-1ubuntu2) ...
Processing triggers for man-db (2.6.7.1-1ubuntu1) ...
Setting up libssl1.0.0:amd64 (1.0.1f-1ubuntu2) ...
Setting up libssl-dev:amd64 (1.0.1f-1ubuntu2) ...
Setting up libssl-doc (1.0.1f-1ubuntu2) ...
Processing triggers for libc-bin (2.19-0ubuntu6.9) ...
```

安装成功。

简单总结：
- `apt-get`安装时会默认选择预设的依赖版本。
- `aptitude`安装时会提示是否选择默认设定的依赖版本，如果选`n`，会对库进行依赖降级，从而安装期望的版本。
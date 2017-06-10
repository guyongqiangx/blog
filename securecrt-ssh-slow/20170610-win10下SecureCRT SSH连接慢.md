最近公司IT推送了win10，系统升级，SecureCRT通过SSH登录服务器突然变得很慢，差不多要30s的样子，那感觉，没法忍受啊~

为了定位问题，网上建议打开`ssh`的调试信息。在排除网络异常的情况下，大多数连接慢跟`GSSAPI`认证有关。

如果只希望了解解决方案，请转到第5节。

## 1. 打开`ssh`调试信息

### 1.1 `linux`系统命令行

在linux命令行下可以通过给`ssh`添加`-v`选项打开调试信息：
```
ygu@stbszx-bld-5:~$ ssh -v ygu@stbszx-bld-6
```

### 1.2 `windows`系统`SecureCRT`工具

`SecureCRT`选中"`File --> Trace Options`"打开调试信息，如下：
!["File --> Trace Options"打开调试信息](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/1-trace-options.png?raw=true)

## 2. 检查`SSH`连接慢

连接时发现两次进行`SSAPI`连接时很慢，需要等待，见红色方框部分：
!["SSPI时需要等待"](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/0-ssh2-slow-log.png?raw=true)

对比原来win7下正常的情形，红色方框部分几乎是不需要等待的。

## 3. 取消勾选`GSSAPI`验证无用

网上大多数修改方式是在`Options --> Session Options`中取消勾选`GSSAPI`来禁用`GSSAPI`选项，如下：
![取消勾选`GSSAPI`选项](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/2-ssh2-settings.png?raw=true)

我测试发现竟然没用。

网上有一篇文章也提到取消勾选“`GSSAPI`”没有用：[<<记一次使用SecureCRT连接局域网巨慢的问题>>](http://www.cnblogs.com/mxw09/p/3607453.html)

## 4. 修改`GSSAPI Properites`设置为`GSSAPI`

最后发现通过修改`GSSAPI`选项可以解决这个问题。

默认情况下，`GSSAPI`的`Method`设置为“`Auto-Detect`”，如下：

!["Auto-Detect"](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/3-ssh2-gssapi-properties-default.png?raw=true)

`Method`选项有“`Auto-Detect`”，“`GSSAPI`”和“`MS Kerberos`”：

!["GSSAPI"的所有"Method"](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/4-ssh2-gssapi-properties-all.png?raw=true)

将`Method`从`Auto-Detect`修改为`GSSAPI`，测试连接正常：

!["GSSAPI"](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/5-ssh2-gssapi-properties-gssapi.png?raw=true)

以下是连接连接正常的log：
!["SSH 连接正常"](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/0-ssh2-fast-log.png?raw=true)

显然，正常连接时不再有`SSPI`请求的延时了（见上图蓝色方框部分）。

我也尝试将`Method`修改为`MS Kerberos`，其现象跟`Auto-Detect`一样，个人猜想`SecureCRT`采用`Auto-Detect`时默认先用`MS Kerberos`进行验证导致需要等待。对于`GSSAPI`的验证方式我并不清楚，求大神科普下~~

## 5. 总结

`SecureCRT`将`GSSAPI Method`从默认的`Auto-Detect`修改为`GSSAPI`得到解决，位置如下：
```
Options 
  --> Session Options
    --> SSH2
      --> Authentication
        --> GSSAPI
          --> Properties
            --> Method
```

![`GSSAPI Properties`的`Method`修改为`GSSAPI`](https://github.com/guyongqiangx/blog/blob/dev/securecrt-ssh-slow/images/5-ssh2-gssapi-properties-gssapi.png?raw=true)
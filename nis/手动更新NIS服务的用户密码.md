# 手动更新NIS服务的用户密码

## 1. 密码存放格式

公司NIS服务器基于`Sun OS 5.10`，即`Solaris 10`，没有开放`yppasswd`服务，由于某些原因只能手动在NIS文件里面手动修改密码，检查`yp`的文件后发现密码存放在`passwd.adjunct`文件中。

### 1.1 密码存放实例

以下是用户`ygu`的记录：

	ygu:$1$T7q3OPy9$zfSTOGqcM.s0.fE1dIOoO/:::::

在`Ubuntu 14.04`上，其`shadow`文件的格式是这样的：

	root@ubuntu:~# cat /etc/shadow | grep root
	root:$6$2vZ14Nil$p96FaJofTH.X5YfWqExlEAyLcKGN3xiBnYnrvtk1eoZ44IFbTLRBBHTCMxgQYNp2Z/52E9yNzdtd7Yw9Q47Hh0:17225:0:99999:7:::

### 1.2 密码存放格式

#### 1.2.1 `shadow`记录格式

NIS的密码格式和Ubuntu的格式是一样的，以Linux的`/etc/shadow`文件为例，这个文件的每行是一个单独的记录，每个记录由9个字段组成，使用分号“:”进行分隔，上面的`root`密码的每个字段意义如下：

![`root`密码格式](https://github.com/guyongqiangx/blog/blob/dev/nis/images/shadow%20file%20format.jpg?raw=true)

1. login name

    登录名，这里为：`root`

2. encrypted password

    密码密文，如果为空，则对应用户没有口令，登录时不需要口令；如果含有不属于集合{./0-9A-Za-z}中的字符，则对应的用户不能登录。

    这里为`$6$2vZ14Nil$p96FaJofTH.X5YfW......47Hh0`。
    
    加密后的密码也有固定格式，后面会描述。

3. date of last password change

    上次密码修改日期，通常是从1970年1月1日起的天数，这里为`17225`。

4. minimum password age

    密码最短保留天数，用户两次更改密码的最小时间间隔，为空或0表示没有限制，这里为`0`。

5. maximum password age

    密码最长保留天数，用户必须在这个时间间隔内修改密码，到期后原来密码仍然有效，只是会被提示修改密码，为空表示没有限制，这里为`99999`。

6. password warning period

    密码到期前的提示天数, 为0表示密码到期前不提示，这里为`7`。

7. password inactivity period

    密码过期后的宽限天数，为空表示不执行宽限功能，这里为空。

8. account expiration date

    账号过期时间，通常是从1970年1月1日起的天数，账号过期不同于密码过期，账号过期意味着账号不能再登录；密码过期意味着用户不能用当前密码登录，通过其它方式修改密码后仍然可以登录，为空表示账号永不过期，这里为空。

9. reserved field, this field is reserved for future use

    保留字段，供将来使用，这里为空。

#### 1.2.2 密文字段格式

对于第2个字段（encrypted password），并非全部都是密文，而是由3个子字段构成，即：

$<u>id</u>$<u>salt</u>$<u>encrypted</u>

图示如下：

![](https://github.com/guyongqiangx/blog/blob/dev/nis/images/password%20and%20data%20encryption.jpg?raw=true)

1. id

    id表示密文加密的方式，有多种：1表示采用MD5，5表示采用SHA-256，6表示采用SHA-512，这里为6。

2. salt

    密码生成的随机参数，通过将`salt`和`passwd`合并到一起进行计算得到HASH密文，防止攻击，这里为`2vZ14Nil`。

3. encrypted

    通过处理后得到的密文，这里为‘`p96FaJofTH.X5YfWqExlEAyLcKGN3xiBnYnrvtk1eoZ44IFbTLRBBHTCMxgQYNp2Z/52E9yNzdtd7Yw9Q47Hh0`’。

详细描述可以参考[`Ubuntu Manuals`](http://manpages.ubuntu.com/manpages/zesty/man3/crypt.3.html)，现将其`NOTES`一节摘录如下：

	NOTES
	   Glibc notes
	       The glibc2 version of  this  function  supports  additional  encryption
	       algorithms.
	
	       If  salt  is  a  character  string  starting with the characters "$id$"
	       followed by a string terminated by "$":
	
	              $id$salt$encrypted
	
	       then instead of using the DES machine,  id  identifies  the  encryption
	       method  used  and  this  then  determines  how the rest of the password
	       string is interpreted.  The following values of id are supported:
	
	              ID  | Method
	              ─────────────────────────────────────────────────────────
	              1   | MD5
	              2a  | Blowfish (not in mainline glibc; added in some
	                  | Linux distributions)
	              5   | SHA-256 (since glibc 2.7)
	              6   | SHA-512 (since glibc 2.7)
	
	       So   $5$salt$encrypted   is   an   SHA-256   encoded    password    and
	       $6$salt$encrypted is an SHA-512 encoded one.
	
	       "salt" stands for the up to 16 characters following "$id$" in the salt.
	       The encrypted part of  the  password  string  is  the  actual  computed
	       password.  The size of this string is fixed:
	
	       MD5     | 22 characters
	       SHA-256 | 43 characters
	       SHA-512 | 86 characters
	
	       The  characters  in  "salt"  and  "encrypted"  are  drawn  from the set
	       [a-zA-Z0-9./].  In the MD5 and SHA implementations the  entire  key  is
	       significant (instead of only the first 8 bytes in DES).

### 2. 重新生成密码

通过以上介绍，有如下结论：

1. `Ubuntu 14.04`的密码存储id为6，采用SHA-512方式
2. `NIS`服务器的密码存储id为1，采用MD5方式

以下来进行实际操作。


下面通过`openssl`工具来生成密码：

> `openssl`的用法如下：
>
> 	ygu@ubuntu:~$ openssl passwd -h
	Usage: passwd [options] [passwords]
	where options are
	-crypt             standard Unix password algorithm (default)
	-1                 MD5-based password algorithm
	-apr1              MD5-based password algorithm, Apache variant
	-salt string       use provided salt
	-in file           read passwords from file
	-stdin             read passwords from stdin
	-noverify          never verify when reading password from terminal
	-quiet             no warnings
	-table             format output as table
	-reverse           switch table columns

假定这里选择参数`2MQdYmSo`作为`salt`随机数：

	ygu@ubuntu:~$ openssl passwd -1 -salt 2MQdYmSo
	Password:
	$1$2MQdYmSo$n5oqmyyEoHkP5/3PLnfZL0

用这里最后生成的字符`$1$2MQdYmSo$n5oqmyyEoHkP5/3PLnfZL0`串替换文件`passwd.adjunct`中记录的相应字段即可。

> 由于这里只更新了`encrypted password`字段，所以账户的一些其他信息，如`date of last password change`不会得到更新。

### 3. 参考链接

参考链接：

- [How are passwords stored in Linux](http://www.slashroot.in/how-are-passwords-stored-linux-understanding-hashing-shadow-utils)
- [Ubuntu Manpage: shadow - shadowed password file](http://manpages.ubuntu.com/manpages/zesty/man5/shadow.5.html)
- [Ubuntu Manpage: crypt, crypt_r - password and data encryption](http://manpages.ubuntu.com/manpages/zesty/man3/crypt.3.html)
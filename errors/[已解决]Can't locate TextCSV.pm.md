##1. 错误描述
编译软件时报告错误：
```
Can't locate Text/CSV.pm
```

详细错误信息：
```
Can't locate Text/CSV.pm in @INC 
(you may need to install the Text::CSV module) 
(@INC contains: 
/etc/perl /usr/local/lib/perl/5.18.2 
/usr/local/share/perl/5.18.2 
/usr/lib/perl5 
/usr/share/perl5 
/usr/lib/perl/5.18 
/usr/share/perl/5.18 
/usr/local/lib/site_perl .) at 
./LatticeFrameworkDataModelTool.pl line 104.
BEGIN failed--compilation aborted at ./LatticeFrameworkDataModelTool.pl line 104.
```

##2. 解决办法

从错误信息看，这个错误是由`perl`没有安装`Text::CSV`模块引起的。

可以通过命令行安装`Text::CSV`模块引起的。
```shell
sudo apt-get install libtext-csv-perl
```
或
```shell
perl -MCPAN -e'install Text::CSV'
```
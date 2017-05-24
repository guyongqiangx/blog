#神奇的'`asdf;`'错误

##1. 问题的由来
编译代码时，有时候会根据宏设置进行条件编译，例如`u-boot`的代码`common\board_r.c`中：
```c
static int run_main_loop(void)
{
#ifdef CONFIG_SANDBOX
    sandbox_main_loop_init();
#endif
    /* main_loop() can return to retry autoboot, if so just run it again */
    for (;;)
        main_loop();
    return 0;
}
```

代码会根据宏`CONFIG_SANDBOX`是否定义来决定是否编译对`sandbox_main_loop_init()`函数的调用。

如果不清楚宏的意义和设置，但又想知道宏包含的代码是否参与编译，比较省事的办法是在宏包含的代码片段内添加一个非法语句。因为插入了非法语句，如果需要编译，那肯定会出现编译错误。

>我以前就喜欢用`asdf;`（**为了让这个非法语句看起来像一个正常语句，在语句末尾特意添加了分号`;`**）。

**谁想，这里面其实有个坑。**

##2. `asdf;`实验
###2.1 例子
下面以`Hello World`为例说明。

+ `Hello World`例子
`hello.c`：
```c
#include <stdio.h>

int main(int argc, char *argv[])
{
        printf("hello world!\n");

        return 0;
}
```
编译`hello.c`，一切正常：
```shell
ygu@stb-lab-04:/opt/ygu/example$ gcc -o hello hello.c
ygu@stb-lab-04:/opt/ygu/example$ ls -al
total 28
drwxrwxr-x 2 ygu ygu 4096 Oct 10 17:50 .
drwxr-xr-x 6 ygu ygu 4096 Oct 10 17:44 ..
-rwxrwxr-x 1 ygu ygu 8519 Oct 10 17:45 hello
-rw-rw-r-- 1 ygu ygu   96 Oct 10 17:44 hello.c
```
+ 函数内的`asdf;`

在`main`函数内添加非法语句`asdf;`，`hello1.c`：
```c
#include <stdio.h>

int main(int argc, char *argv[])
{
        asdf;

        printf("hello world!\n");

        return 0;
}
```
无法通过编译，跟预期的一样：
```shell
ygu@stb-lab-04:/opt/ygu/example$ gcc -o hello1 hello1.c 
hello1.c: In function 'main':
hello1.c:5:2: error: 'asdf' undeclared (first use in this function)
  asdf;
  ^
hello1.c:5:2: note: each undeclared identifier is reported only once for each function it appears in
ygu@stb-lab-04:/opt/ygu/example$ ls -al
total 28
drwxrwxr-x 2 ygu ygu 4096 Oct 10 17:50 .
drwxr-xr-x 6 ygu ygu 4096 Oct 10 17:44 ..
-rwxrwxr-x 1 ygu ygu 8519 Oct 10 17:45 hello
-rw-rw-r-- 1 ygu ygu   96 Oct 10 17:44 hello.c
-rw-rw-r-- 1 ygu ygu  104 Oct 10 17:50 hello1.c
```
+ 函数外的`asdf;`

如果将这个`asdf;`添加到函数外，会怎样呢？

在`main`函数外添加非法语句`asdf;`，`hello2.c`：
```c
#include <stdio.h>

asdf;

int main(int argc, char *argv[])
{
        printf("hello world!\n");

        return 0;
}
```

居然能通过编译，好意外：
```shell
ygu@stb-lab-04:/opt/ygu/example$ gcc -o hello2 hello2.c
hello2.c:3:1: warning: data definition has no type or storage class [enabled by default]
 asdf;
 ^
ygu@stb-lab-04:/opt/ygu/example$ ls -lh
total 36K
-rwxrwxr-x 1 ygu ygu 8.4K Oct 10 17:45 hello
-rw-rw-r-- 1 ygu ygu   96 Oct 10 17:44 hello.c
-rw-rw-r-- 1 ygu ygu  104 Oct 10 17:50 hello1.c
-rwxrwxr-x 1 ygu ygu 8.4K Oct 10 18:02 hello2
-rw-rw-r-- 1 ygu ygu  103 Oct 10 17:59 hello2.c
```

###2.2 实验结论

**为什么`asdf;`添加在不同的地方，结果不一样呢？**

+ 函数内的`asdf;`

不能通过编译，报错：
```
hello1.c: In function 'main':
hello1.c:5:2: error: 'asdf' undeclared (first use in this function)
  asdf;
  ^
hello1.c:5:2: note: each undeclared identifier is reported only once for each function it appears in
```

从错误信息看，编译器认为这里的`asdf`是未声明的标识符（`undeclared identifier`）。

+ 函数外的`asdf;`

可以通过编译，但有一个警告信息：
```
hello2.c:3:1: warning: data definition has no type or storage class [enabled by default]
 asdf;
 ^
```

编译器认为`asdf;`是一个数据定义语句，其定义了数据`asdf`，但是没有指定数据的类型或类别。

根据默认的行为，`asdf`的数据类型会被认为是整形`int`。
因此，这里相当于是定义了一个未被使用的`int`型变量`asdf`，也就不难理解为什么可以通过编译了。

> 为了验证`asdf`被默认认为是`int`而不是其它，可以尝试在代码里面对`asdf`赋值一个指针：
>
> `char c = 'a'; asdf = &c;`
> 
> 编译会输出警告信息：
> 
> `warning: assignment makes integer from pointer without a cast [enabled by default]`
> 
> `warning`提示这里尝试将`pointer`赋值给`integer`而没有强制类型转换


##3. 结论
尽量不要使用带分号'`;`'的语句（如：'`asdf;`'）来检查代码是否被宏条件语句编译。

如果要用非法语句来检查，也不要加分号'`;`'

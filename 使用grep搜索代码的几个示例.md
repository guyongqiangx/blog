# 使用grep搜索代码的几个示例

作为基于windows系统工作的攻城狮，每天必须用`sourceinsight`，这工具确实好用，关键词和语法着色，上下文联想，代码自动补全，但是也经常发现有些不太方便的地方。例如：操作前需要先建立工程，这也没什么，但是如果只想临时在某个代码包里查找符号变量什么的，也得需要先创建工程；对于代码量很大的项目，如Android，工程的创建和解析都很麻烦；还有就是对二进制搜索支持不好，对搜索的匹配也很有限。

好吧，刚发现`sourceinsight`还支持正则表达式搜索，这个功能什么时候出现的？

搜索代码，或者是查找关键词，除了`sourceinsight`，那就应该是`grep`了。
可是度娘一下"`grep`"看看你能收到什么？大多数都是"grep命令详解”，“grep命令和参数的用法”，要不就是“grep和正则表达式”，然后点进去就是给你罗列一大堆“grep”的选项，要不就是罗列一大堆正则表达式语法，是罗列，罗列啊~我TM不想知道“grep”的一大堆选项，要你说，运行“man grep”详细到十万八千里去了，我也不想去研究正则表达式的各种语法，我只想知道如何解决我我遇到的实际问题。

好吧，搜索了半天，也还是解决不了问题，最好老老实实“man grep”去找答案吧。

下面，从码农读代码的角度，总结下我最常用的`grep`方式，也欢迎大家交流下`grep`的一些高级用法。

> 读代码时的查找通常比较简单，就是想知道某些符号在哪个文件定义或在哪些地方被引用，都是一些明确的符号，很少需要模糊查找，所以用到复杂正则表达式的机会很少。

免不了啰嗦一下，“grep”的常用的几个选项：

- `-r`，递归查找

- `-n`，搜索结果显示行号
  
- `-i`，忽略大小写
  
- `-v`，反向匹配
  
- `-w`，匹配整个单词

- `-E`，匹配扩展的正则表达式

这里以`u-boot-2016.09`代码为例，进行`memcpy`查找操作。

## 1. 递归查找并显示行号

这个是最基本的查找了。

```
$ grep -rn memcpy
```
在当前目录查找可以使用：

- 不指定目录："`grep -rn memcpy`"
- 用"`.`"指定当前目录："`grep -rn memcpy .`"
 
其实这两者查找结果一样，但在输出格式上是有区别的，具体留给你去比较好了。

## 2. 查找不区分大小写

```
$ grep -rni memcpy
```

选项"`-i`"或略大小写，这样除了匹配“`memcpy`”外，还可以匹配一些宏定义如"`MEMCPY`"和"`Memcpy`"等，如：
```
...
include/malloc.h:351:#define HAVE_MEMCPY
include/malloc.h:353:#ifndef USE_MEMCPY
include/malloc.h:354:#ifdef HAVE_MEMCPY
include/malloc.h:355:#define USE_MEMCPY 1
include/malloc.h:357:#define USE_MEMCPY 0
include/malloc.h:361:#if (__STD_C || defined(HAVE_MEMCPY))
include/malloc.h:365:void* memcpy(void*, const void*, size_t);
...
board/freescale/t102xrdb/spl.c:63:	/* Memcpy existing GD at CONFIG_SPL_GD_ADDR */
board/freescale/t102xrdb/spl.c:64:	memcpy((void *)CONFIG_SPL_GD_ADDR, (void *)gd, sizeof(gd_t));
board/freescale/t208xqds/spl.c:68:	/* Memcpy existing GD at CONFIG_SPL_GD_ADDR */
...
```

## 3. 排除指定文件的搜索结果

搜索结果的第一列会显示搜索结果位于哪个文件中，所以可以通过对搜索结果第一列的过滤来排除指定文件。

例如：编译时生成的`*.o.cmd`文件中带了很多包含`memcpy.h`的行，如：
```
out/rpi_3_32b/drivers/input/.input.o.cmd:295:    $(wildcard include/config/use/arch/memcpy.h)
```

可以在搜索结果中用反向匹配"`-v`"排除`*.o.cmd`文件的匹配：
```
$ grep -rn memcpy | grep -v .o.cmd
```

如果想排除多个生成文件中的匹配，包括"`*.o.cmd`，`*.s.cmd`，`*.o`，`*.map`"等，有两种方式：

- 使用多个`-v`依次对上一次的结果进行反向匹配：
```
$ grep -rn memcpy | grep -v .o.cmd | grep -v .s.cmd | grep -v .o | grep -v .map
```
- 使用`-Ev`一次进行多个反向匹配搜索：
```
$ grep -rn memcpy | grep -Ev '\.o\.cmd|\.s\.cmd|\.o|\.map'
```

> 由于这里使用了正则表达式"`-E`"，所以需要用"`\`"将"`.`"字符进行转义

另外，也可以使用"`--exclude=GLOB`"来指定排除某些格式的文件，如不在“`*.cmd`”，“`*.o`”和“`*.map`”中搜索：
```
$ grep -rn --exclude=*.cmd --exclude=*.o --exclude=*.map memcpy
```

> 跟“`--exclude=GLOB`”类似的用法有“`--include=GLOB`”，从指定的文件中搜索，如只在“`*.cmd`”，“`*.o`”和“`*.map`”中搜索：
> ```
> $ grep -rn --include=*.cmd --include=*.o --include=*.map memcpy
> ```
> “`--include=GLOB`”在不确定某些函数是否被编译时特别有用。
> 例如，不确定函数`rpi_is_serial_active`是否有被编译，那就查找“*.o”文件是否存在这个函数符号：
> ```
> $ grep -rn --include=*.o rpi_is_serial_active
> Binary file out/rpi_3_32b/board/raspberrypi/rpi/built-in.o matches
> Binary file out/rpi_3_32b/board/raspberrypi/rpi/rpi.o matches
> ```
> 显然，从结果看，这个函数是参与了编译的，否则搜索结果为空。
> 
> 如果想知道函数`rpi_is_serial_active`最后有没有被链接使用，查询生成的`u-boot*`文件就知道了：
> ```
> $ grep -rn --include=u-boot* rpi_is_serial_active
> Binary file out/rpi_3_32b/u-boot matches
> ```
> 可见`u-boot`文件中找到了这个函数符号。

## 4. 不在某些指定的目录查找`memcpy`

如果指定了`u-boot`编译的输出目录，例如输出到`out`，则可以直接忽略对`out`目录的搜索，如：
```
$ grep -rn --exclude-dir=out memcpy
```

> 忽略多个目录（“out”和“doc”）：
> ```
> $ grep -rn --exclude-dir=out --exclude-dir=doc memcpy
> ```

## 5. 查找精确匹配结果

通常的“`memcpy`”查找结果中会有一些这样的匹配：“`MCD_memcpy`”，“`zmemcpy`”，“`memcpyl`”，“`memcpy_16`”等，如果只想精确匹配整个单词，则使用`-w`选项：
```
$ grep -rnw memcpy .
```

## 6. 查找作为单词分界的结果

“作为单次分界“这个表述不太准确，例如，希望“`memcpy`”的查找中，只匹配“`MCD_memcpy`”，“`memcpy_16`”，而不用匹配“`zmemcpy`”，“`memcpyl`”这样的结果，也就是`memcpy`以一个完整单词的形式出现。

一般这种查询就需要结合正则表达式了，用正则表达式去匹配单词边界，例如：

```
$ grep -rn -E "(\b|_)memcpy(\b|_)"
```

> 关于正则表达式“`(\b|_)memcpy(\b|_)`”
> 
> - "`\b`"匹配单词边界
> - "`_`"匹配单个下滑下
> 
> 所以上面的表达式可以匹配：`memcpy`，`memcpy_xxx`，`xxx_memcpy`和`xxx_memcpy_xxx`等模式。（可能匹配的还有函数`memcpy_`，`_memcpy`和`_memcpy_`）

## 7. 查看查找结果的上下文

想在结果中查看匹配内容的前后几行信息，例如想看宏定义“`MEMCPY`”匹配的前三行和后两行：
```
$ grep -rn -B 3 -A 2 MEMCPY
```
> 选项`B/A`：
> `-B` 指定显示匹配前（Before）的行数
> `-A` 指定显示匹配后（After）的行数

## 8. grep和find配合进行查找

find针是对文件级别的粗粒度查找，而grep则对文件内容的细粒度搜索。
所以grep跟find命令配合，用grep在find的结果中进行搜索，能发挥更大的作用，也更方便。

例如，我想查找所有`makefile`类文件中对`CFLAGS`的设置。
`makefile`类常见文件包括`makefile`，`*.mk`，`*.inc`等，而且文件名还可能是大写的。

可以通过find命令先找出`makefile`类文件，然后再从结果中搜索`CFLAGS`：

```
$ find . -iname Makefile -o -iname *.inc -o -iname *.mk | xargs grep -rn CFLAGS
```
> 这里由于涉及到find命令，所以整个查找看起来有点复杂了，也可以只用`grep`的`--include=GLOB`选项来实现：
> 
> ```
> $ grep -rn --include=Makefile --include=*.inc --include=*.mk CFLAGS .
> ```
> 
> 比较上面的两个搜索结果，是一样的，但是有一点要注意：
> 
> - `grep`命令的`--include=GLOB`模式下，文件名是区分大小写的，而且没有方式指定忽略文件名大小写
> 
> 刚好这里搜索的`Makefile`只有首字母大写的形式，而不存在小写的`makefile`，所以这里碰巧是结果一致而已，否则需要指定更多的`--include=GLOB`参数。

以上是我的一些`grep`用法，欢迎交流，共同提高读代码的效率。
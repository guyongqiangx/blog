# 20230107-使用 lldb 调试 update engine

>  本文参考了以下文章：
>
> - [《Ubuntu环境Camera相关的gdb/lldb调试》](https://liyangzmx.github.io/gdbclient.html)
>
> - [《使用调试程序》](https://source.android.google.cn/docs/core/tests/debug/gdb?hl=zh-cn)

据我观察，工程师有两种，一种是 printf 工程师，一种是使用调试器的工程师。

- printf 只需要在怀疑的地方加个打印输出想要的信息，然后重新运行一遍程序查看结果，门槛特别低，基本上不需要特殊技能；

- 通过调试器可以在线调试，实时查看程序的各种状态，缺点是门槛高，需要记住各种操作命令。

必须得承认，尽管工作十多年了，一直都是一个 printf 工程师，有很多借口用 printf 的理由，比如主要基于驱动工作，没有好的调试环境，有些东西无法调试，有时候调试追踪也不能完全定位，诸如此类。背后还是因为 printf 没有学习门槛，十分方便。根本原因是骨子里偷懒，从没想过认真使用调试器，借助调试器的功能来提高效率，想在想起来，浪费了很多时间，这真是永远的痛。

所以，我建议你，有可能的话，尽量使用调试器。



```bash
$ adb connect 10.148.6.127
connected to 10.148.6.127:5555
$ adb root
$ adb devices
List of devices attached
10.148.6.127:5555       device

$ lldbclient.py --setup-forwarding vscode --lldb -n update_engine
Redirecting gdbserver output to /tmp/gdbclient.log

(lldb) command source -s 0 '/tmp/tmp34jqm1'
Executing commands in '/tmp/tmp34jqm1'.
(lldb) settings append target.exec-search-paths /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/ /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/hw /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/ssl/engines /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/drm /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/egl /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/soundfx /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/vendor/lib/ /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/vendor/lib/hw /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/vendor/lib/egl /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/apex/com.android.runtime/bin
(lldb) target create /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/bin/update_engine
Current executable set to '/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/bin/update_engine' (arm).
(lldb) target modules search-paths add / /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/
(lldb) gdb-remote 5039
(lldb) 
```



```bash
$ lldbclient.py --setup-forwarding vscode -n update_engine
Redirecting gdbserver output to /tmp/gdbclient.log

{
    "miDebuggerPath": "/local/public/users/ygu/android-r/src-vab/prebuilts/gdb/linux-x86/bin/gdb", 
    "program": "/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/bin/update_engine", 
    "setupCommands": [
        {
            "text": "-enable-pretty-printing", 
            "description": "Enable pretty-printing for gdb", 
            "ignoreFailures": true
        }, 
        {
            "text": "-environment-directory /local/public/users/ygu/android-r/src-vab", 
            "description": "gdb command: dir", 
            "ignoreFailures": false
        }, 
        {
            "text": "-gdb-set solib-search-path /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/hw:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/ssl/engines:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/drm:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/egl:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/system/lib/soundfx:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/vendor/lib/:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/vendor/lib/hw:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/vendor/lib/egl:/local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols/apex/com.android.runtime/bin", 
            "description": "gdb command: set solib-search-path", 
            "ignoreFailures": false
        }, 
        {
            "text": "-gdb-set solib-absolute-prefix /local/public/users/ygu/android-r/src-vab/out/target/product/inuvik/symbols", 
            "description": "gdb command: set solib-absolute-prefix", 
            "ignoreFailures": false
        }, 
        {
            "text": "-interpreter-exec console \"source /local/public/users/ygu/android-r/src-vab/development/scripts/gdb/dalvik.gdb\"", 
            "description": "gdb command: source art commands", 
            "ignoreFailures": false
        }
    ], 
    "name": "(gdbclient.py) Attach update_engine (port: 5039)", 
    "miDebuggerServerAddress": "localhost:5039", 
    "request": "launch", 
    "type": "cppdbg", 
    "cwd": "/local/public/users/ygu/android-r/src-vab", 
    "MIMode": "gdb"
}


Paste the above json into .vscode/launch.json and start the debugger as
normal. Press enter in this terminal once debugging is finished to shutdown
the gdbserver and close all the ports.

Press enter to shutdown gdbserver
```



```bash
update_engine_client \
--payload=http://10.148.7.100/public/users/ygu/update-bootctl/payload.bin \
--update \
--headers="\
	FILE_HASH=G/+9FvzNVr9ugcTDD7POS2Lw3h2OPCRa1Q4aiqW5YKc=
	FILE_SIZE=9993885
	METADATA_HASH=YkpoyE+L27IeSLe3XIpRvX6+dJXkC09tD95s7AFsZ68=
	METADATA_SIZE=53909
"
```


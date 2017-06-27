编译Android的第一步是执行`source build/envsetup.sh`设置编译相关的环境，里面到底都做了什么呢？我们来看一看。

`envsetup.sh`的代码较长，共有1632行，但其内容较简单，只做了两件事：
1. 函数定义
  
   定义可以在命令行直接调用的函数，方便编译和调试操作。一共定义了四种类型共75个可以在命令行调用的函数;
2. 生成编译配置列表

   脚本通过查找并执行{device, vendor, product}目录下的`vendorsetup.sh`文件，搜集所有可能的编译配置生成配置列表，供编译时选择；

接下来基于这两个主题对文件`envsetup.sh`进行详细分析。

## 1. 函数定义

文件95%以上的代码都是在定义各种各样的函数，并将这些函数导入到shell环境中，使其可以直接在命令行调用。
这些函数总共分为4类，包括：
- 辅助函数类
- 编译环境设置类
- 代码搜索类
- `adb`调试类

> 通过以下命令获得`envsetup.sh`中所定义的函数总数：
> ```
> ygu@guyongqiangx:src$ sed -n "/^[[:blank:]]*function /s/function \([a-z_]\w*\).*/\1/p" < build/envsetup.sh | wc -l
> 75
> ```
>

以下对所有定义的函数逐个进行分析。

### 1.1 辅助函数类
#### `hmm`

  `hmm`函数输出`envsetup.sh`的帮助说明，提示执行`. build/envsetup.sh`后有哪些可以调用的操作。以前看到别人提过`android`编译的特殊命令，包括`m`、`mm`和`mmm`，这3个命令的差别我每次都要去问度娘，好了，现在直接运行`hmm`，什么都知道了。

```
function hmm() {
cat <<EOF
Invoke ". build/envsetup.sh" from your shell to add the following functions to your environment:
- lunch:     lunch <product_name>-<build_variant>
- tapas:     tapas [<App1> <App2> ...] [arm|x86|mips|armv5|arm64|x86_64|mips64] [eng|userdebug|user]
- croot:     Changes directory to the top of the tree.
- m:         Makes from the top of the tree.
- mm:        Builds all of the modules in the current directory, but not their dependencies.
- mmm:       Builds all of the modules in the supplied directories, but not their dependencies.
             To limit the modules being built use the syntax: mmm dir/:target1,target2.
- mma:       Builds all of the modules in the current directory, and their dependencies.
- mmma:      Builds all of the modules in the supplied directories, and their dependencies.
- provision: Flash device with all required partitions. Options will be passed on to fastboot.
- cgrep:     Greps on all local C/C++ files.
- ggrep:     Greps on all local Gradle files.
- jgrep:     Greps on all local Java files.
- resgrep:   Greps on all local res/*.xml files.
- mangrep:   Greps on all local AndroidManifest.xml files.
- mgrep:     Greps on all local Makefiles files.
- sepgrep:   Greps on all local sepolicy files.
- sgrep:     Greps on all local source files.
- godir:     Go to the directory containing a file.

Environment options:
- SANITIZE_HOST: Set to 'true' to use ASAN for all host modules. Note that
                 ASAN_OPTIONS=detect_leaks=0 will be set by default until the
                 build is leak-check clean.

Look at the source to view more functions. The complete list is:
EOF
    # 查找编译环境根目录
    T=$(gettop)
    local A
    A=""
    # 读取build/envsetup.sh文件，并通过sed操作获取其中定义的函数，并进行排序输出，存放到变量$A中
    for i in `cat $T/build/envsetup.sh | sed -n "/^[[:blank:]]*function /s/function \([a-z_]*\).*/\1/p" | sort | uniq`; do
      A="$A $i"
    done
    echo $A
}
```
  直接在命令行调用`hmm`，先显示一堆`help`信息，随后列举本文件中所有定义的函数。
  
  >
  > 函数中命令"`sed -n "/^[[:blank:]]*function /s/function \([a-z_]*\).*/\1/p"`"用于生成函数列表。
  >
  > 但其操作有一个bug，用于匹配函数的正则表达式"`function \([a-z_]*\).*`"会漏掉函数"`is64bit`"。
  >
  > 将匹配模式从"`function \([a-z_]*\).*`"修改为"`function \([a-z_]\w*\).*`"可以匹配文件中的所有函数。

#### `gettop`
  `gettop`函数从指定的$TOP目录或当前目录开始查找build/core/envsetup.mk文件，并将能找到该文件的目录返回给调用函数作为操作的根目录，详细注释如下：

```
function gettop
{
    local TOPFILE=build/core/envsetup.mk
    # 如果编译环境已经设置了$TOP，就检查$TOP/build/core/envsetup.mk文件是否存在
    if [ -n "$TOP" -a -f "$TOP/$TOPFILE" ] ; then
        # The following circumlocution ensures we remove symlinks from TOP.
        # 转到$TOP目录，通过命令`/bin/pwd`将$TOP目录指向的真实路径存放到PWD中
        (cd $TOP; PWD= /bin/pwd)
    else
        # 如果当前路径下能够找到build/core/envsetup.mk文件，
        # 则将当前目录的真实路径存放到PWD中
        if [ -f $TOPFILE ] ; then
            # The following circumlocution (repeated below as well) ensures
            # that we record the true directory name and not one that is
            # faked up with symlink names.
            PWD= /bin/pwd
        else
            # 如果当前目录下无法找到build/core/envsetup.mk文件，
            # 则不断返回到外层目录查找，直到到达根目录/为止
            
            # 保存查找操作前的路径
            local HERE=$PWD
            T=
            while [ \( ! \( -f $TOPFILE \) \) -a \( $PWD != "/" \) ]; do
                # 转到外层目录
                \cd ..
                # 将当前路径保存到T中
                T=`PWD= /bin/pwd -P`
            done
            # 查找完后恢复操作前的路径
            \cd $HERE
            # 如果目录T包含build/core/envsetup.mk，说明是T是编译的根目录
            if [ -f "$T/$TOPFILE" ]; then
                # 输出$T中保存的路径作为gettop的返回值
                echo $T
            fi
        fi
    fi
}
```
#### `croot`
  `croot`命令切换到当前编译环境的根目录。
```
function croot()
{
    # 查找当前编译树的根目录
    T=$(gettop)
    if [ "$T" ]; then
        # 切换到编译环境的根目录
        \cd $(gettop)
    else
        echo "Couldn't locate the top of the tree.  Try setting TOP."
    fi
}
```
#### `cproj`
  `cproj`命令用于切换到当前模块的编译目录下（含有Android.mk）
```
function cproj()
{
    TOPFILE=build/core/envsetup.mk
    # 保存操作前的路径
    local HERE=$PWD
    T=
    # 当前目录下build/core/envsetup.mk不存在（即当前目录不是编译根目录），
    # 并且当前目录不是系统根目录
    while [ \( ! \( -f $TOPFILE \) \) -a \( $PWD != "/" \) ]; do
        T=$PWD
        # 当前$T目录下存在文件Android.mk
        if [ -f "$T/Android.mk" ]; then
            # 转到$T目录
            \cd $T
            return
        fi
        # 转到外层目录
        \cd ..
    done
    # 恢复操作前的路径
    \cd $HERE
    echo "can't find Android.mk"
}
```
#### `getprebuilt`
  `getprebuilt`返回`ANDROID_PREBUILTS`的路径
  
  命令行直接调用`getprebuilt`：
```
ygu@guyongqiangx:src$ getprebuilt
/android/src/prebuilt/linux-x86
```
实际上src目录下并不存在路径`prebuilt/linux-x86`

```
function getprebuilt
{
    # 通过函数get_abs_build_var返回ANDROID_PREBUILTS设置
    get_abs_build_var ANDROID_PREBUILTS
}
```
#### `setpaths`
  `setpaths`
```
function setpaths()
{
    # 如果找不到编译的根目录，则退出设置
    T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP."
        return
    fi

    ##################################################################
    #                                                                #
    #              Read me before you modify this code               #
    #                                                                #
    #   This function sets ANDROID_BUILD_PATHS to what it is adding  #
    #   to PATH, and the next time it is run, it removes that from   #
    #   PATH.  This is required so lunch can be run more than once   #
    #   and still have working paths.                                #
    #                                                                #
    ##################################################################

    # Note: on windows/cygwin, ANDROID_BUILD_PATHS will contain spaces
    # due to "C:\Program Files" being in the path.

    # 将$ANDROID_BUILD_PATHS和$ANDROID_PRE_BUILD_PATHS指定的路径添加到$PATH中，并export
    # out with the old
    if [ -n "$ANDROID_BUILD_PATHS" ] ; then
        export PATH=${PATH/$ANDROID_BUILD_PATHS/}
    fi
    if [ -n "$ANDROID_PRE_BUILD_PATHS" ] ; then
        export PATH=${PATH/$ANDROID_PRE_BUILD_PATHS/}
        # strip leading ':', if any
        # 说实话，我没搞懂这个是什么意思，求大神指点下
        export PATH=${PATH/:%/}
    fi

    # and in with the new
    # 设置ANDROID_PREBUILT和ANDROID_GCC_PREBUILTS相应的路径
    prebuiltdir=$(getprebuilt)
    gccprebuiltdir=$(get_abs_build_var ANDROID_GCC_PREBUILTS)

    # defined in core/config.mk
    # 设置TARGET_GCC_VERSION和2ND_TARGET_GCC_VERSION
    targetgccversion=$(get_build_var TARGET_GCC_VERSION)
    targetgccversion2=$(get_build_var 2ND_TARGET_GCC_VERSION)
    export TARGET_GCC_VERSION=$targetgccversion

    # The gcc toolchain does not exists for windows/cygwin. In this case, do not reference it.
    export ANDROID_TOOLCHAIN=
    export ANDROID_TOOLCHAIN_2ND_ARCH=
    # 根据get_build_var返回的TARGET_ARCH分别设置{x86, x86_64, arm, arm64，mips|mips64}体系结构对应的toolchaindir名称
    local ARCH=$(get_build_var TARGET_ARCH)
    case $ARCH in
        x86) toolchaindir=x86/x86_64-linux-android-$targetgccversion/bin
            ;;
        x86_64) toolchaindir=x86/x86_64-linux-android-$targetgccversion/bin
            ;;
        arm) toolchaindir=arm/arm-linux-androideabi-$targetgccversion/bin
            ;;
        arm64) toolchaindir=aarch64/aarch64-linux-android-$targetgccversion/bin;
               toolchaindir2=arm/arm-linux-androideabi-$targetgccversion2/bin
            ;;
        mips|mips64) toolchaindir=mips/mips64el-linux-android-$targetgccversion/bin
            ;;
        *)
            echo "Can't find toolchain for unknown architecture: $ARCH"
            toolchaindir=xxxxxxxxx
            ;;
    esac
    
    # 设置ANDROID_TOOLCHAIN和ANDROID_TOOLCHAIN_2ND_ARCH环境变量，用于指示toolchain路径
    if [ -d "$gccprebuiltdir/$toolchaindir" ]; then
        export ANDROID_TOOLCHAIN=$gccprebuiltdir/$toolchaindir
    fi

    if [ -d "$gccprebuiltdir/$toolchaindir2" ]; then
        export ANDROID_TOOLCHAIN_2ND_ARCH=$gccprebuiltdir/$toolchaindir2
    fi

    # 设置Android编译相关的路径变量ANDROID_BUILD_PATHS
    export ANDROID_DEV_SCRIPTS=$T/development/scripts:$T/prebuilts/devtools/tools:$T/external/selinux/prebuilts/bin
    export ANDROID_BUILD_PATHS=$(get_build_var ANDROID_BUILD_PATHS):$ANDROID_TOOLCHAIN:$ANDROID_TOOLCHAIN_2ND_ARCH:$ANDROID_DEV_SCRIPTS:

    # If prebuilts/android-emulator/<system>/ exists, prepend it to our PATH
    # to ensure that the corresponding 'emulator' binaries are used.
    # 基于不同的系统设置ANDROID_EMULATOR_PREBUILTS变量
    case $(uname -s) in
        Darwin)
            ANDROID_EMULATOR_PREBUILTS=$T/prebuilts/android-emulator/darwin-x86_64
            ;;
        Linux)
            ANDROID_EMULATOR_PREBUILTS=$T/prebuilts/android-emulator/linux-x86_64
            ;;
        *)
            ANDROID_EMULATOR_PREBUILTS=
            ;;
    esac
    # 如果ANDROID_EMULATOR_PREBUILTS变量指定的目录存在，则将其添加到Android编译相关的路径变量ANDROID_BUILD_PATHS中
    if [ -n "$ANDROID_EMULATOR_PREBUILTS" -a -d "$ANDROID_EMULATOR_PREBUILTS" ]; then
        ANDROID_BUILD_PATHS=$ANDROID_BUILD_PATHS$ANDROID_EMULATOR_PREBUILTS:
        export ANDROID_EMULATOR_PREBUILTS
    fi

    # 将Android编译相关的路径ANDROID_BUILD_PATHS添加到PATH中
    export PATH=$ANDROID_BUILD_PATHS$PATH
    # 将development/python-packages添加到python运行的查找路径中
    export PYTHONPATH=$T/development/python-packages:$PYTHONPATH

    unset ANDROID_JAVA_TOOLCHAIN
    unset ANDROID_PRE_BUILD_PATHS
    # 如果设置了$JAVA_HOME，则将其加入到PATH变量中
    if [ -n "$JAVA_HOME" ]; then
        export ANDROID_JAVA_TOOLCHAIN=$JAVA_HOME/bin
        export ANDROID_PRE_BUILD_PATHS=$ANDROID_JAVA_TOOLCHAIN:
        export PATH=$ANDROID_PRE_BUILD_PATHS$PATH
    fi

    # 设置ANDROID_PRODUCT_OUT和OUT环境变量
    unset ANDROID_PRODUCT_OUT
    export ANDROID_PRODUCT_OUT=$(get_abs_build_var PRODUCT_OUT)
    export OUT=$ANDROID_PRODUCT_OUT

    # 设置HOST_OUT环境变量
    unset ANDROID_HOST_OUT
    export ANDROID_HOST_OUT=$(get_abs_build_var HOST_OUT)

    # needed for building linux on MacOS
    # TODO: fix the path
    #export HOST_EXTRACFLAGS="-I "$T/system/kernel_headers/host_include
}
```
#### `set_java_home`
  `set_java_home`
```
# Force JAVA_HOME to point to java 1.7/1.8 if it isn't already set.
function set_java_home() {
    # Clear the existing JAVA_HOME value if we set it ourselves, so that
    # we can reset it later, depending on the version of java the build
    # system needs.
    #
    # If we don't do this, the JAVA_HOME value set by the first call to
    # build/envsetup.sh will persist forever.
    #
    # 如果已经设置$ANDROID_SET_JAVA_HOME变量，则清空JAVA_HOME
    if [ -n "$ANDROID_SET_JAVA_HOME" ]; then
      export JAVA_HOME=""
    fi

    # 如果JAVA_HOME没有设置
    if [ ! "$JAVA_HOME" ]; then
      # 如果已经设置了LEGACY_USE_JAVA7，说明强制指定使用JDK7
      if [ -n "$LEGACY_USE_JAVA7" ]; then
        echo Warning: Support for JDK 7 will be dropped. Switch to JDK 8.
        # 根据编译系统设置JDK7的JAVA_HOME
        case `uname -s` in
            Darwin) # Mac
                export JAVA_HOME=$(/usr/libexec/java_home -v 1.7)
                ;;
            *)
                # 默认设置为java-7-openjdk-amd64的路径
                export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64
                ;;
        esac
      # 如果没有设置LEGACY_USE_JAVA7，则使用JDK 8
      else
        # 根据系统设置JDK8的JAVA_HOME
        case `uname -s` in
            Darwin)
                export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
                ;;
            *)
                export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
                ;;
        esac
      fi

      # Keep track of the fact that we set JAVA_HOME ourselves, so that
      # we can change it on the next envsetup.sh, if required.
      #
      # 设置ANDROID_SET_JAVA_HOME作为已经设置了JAVA_HOME的标识
      export ANDROID_SET_JAVA_HOME=true
    fi
}
```
#### `printconfig`
  `printconfig`输出当前的编译配置，如：
```
ygu@guyongqiangx:src$ printconfig
============================================
PLATFORM_VERSION_CODENAME=REL
PLATFORM_VERSION=7.1.1
TARGET_PRODUCT=bcm7252ssffdr4
TARGET_BUILD_VARIANT=userdebug
TARGET_BUILD_TYPE=release
TARGET_BUILD_APPS=
TARGET_ARCH=arm
TARGET_ARCH_VARIANT=armv7-a-neon
TARGET_CPU_VARIANT=cortex-a15
TARGET_2ND_ARCH=
TARGET_2ND_ARCH_VARIANT=
TARGET_2ND_CPU_VARIANT=
HOST_ARCH=x86_64
HOST_2ND_ARCH=x86
HOST_OS=linux
HOST_OS_EXTRA=Linux-4.2.0-42-generic-x86_64-with-Ubuntu-14.04-trusty
HOST_CROSS_OS=windows
HOST_CROSS_ARCH=x86
HOST_CROSS_2ND_ARCH=x86_64
HOST_BUILD_TYPE=release
BUILD_ID=NMF27D
OUT_DIR=out
============================================
```

```
function printconfig()
{
    # 检查编译根目录
    T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
    # 调用get_build_var report_config来打印输出当前的编译配置
    get_build_var report_config
}
```

#### `getdriver`
  `getdriver`在定义了$WITH_STATIC_ANALYZER的情况下，返回用于代码分析工具的一些参数
  默认编译下$WITH_STATIC_ANALYZER没有定义，所以`getdriver`调用返回空

```
# Return driver for "make", if any (eg. static analyzer)
function getdriver()
{
    local T="$1"
    # 检查$WITH_STATIC_ANALYZER，如果设置为0，就将其内容清空
    test "$WITH_STATIC_ANALYZER" = "0" && unset WITH_STATIC_ANALYZER
    if [ -n "$WITH_STATIC_ANALYZER" ]; then
        # 好吧，将这一堆字符串返回，我也不知道干什么用，求大神指导下
        echo "\
$T/prebuilts/misc/linux-x86/analyzer/tools/scan-build/scan-build \
--use-analyzer $T/prebuilts/misc/linux-x86/analyzer/bin/analyzer \
--status-bugs \
--top=$T"
    fi
}
```
#### `gettargetarch`
  `gettargetarch`函数返回编译目标系统的CPU架构，如arm
```
function gettargetarch
{
    # 通过get_build_var TARGET_ARCH返回cpu arch
    get_build_var TARGET_ARCH
}
```
#### `godir`
  `godir`函数的用法为"Usage: godir <regex>"，在编译路径下搜索匹配<regex>模式的目录，然后跳转到此目录。
```
ygu@guyongqiangx:src$ godir fugu
   [1] ./device/asus/fugu
   [2] ./device/asus/fugu-kernel
   [3] ./device/asus/fugu/bluetooth
   [4] ./device/asus/fugu/dumpstate
   [5] ./device/asus/fugu/factory-images
   [6] ./device/asus/fugu/kernel-headers/drm
   [7] ./device/asus/fugu/kernel-headers/drm/ttm
   [8] ./device/asus/fugu/kernel-headers/linux
   [9] ./device/asus/fugu/kernel-headers/linux/sound
   ...
Select one:
```
  在上面的提示后输入1，命令行跳转到`./device/asus/fugu`目录下，实现了跟函数名一致的"go dir"的操作。

```
function godir () {
    # 如果godir的第一个参数$1为空，显示godir的用法
    if [[ -z "$1" ]]; then
        echo "Usage: godir <regex>"
        return
    fi
    # 变量T存放编译根目录路径
    T=$(gettop)
    # 根据是否设置$OUT_DIR，设置$FILELIST
    if [ ! "$OUT_DIR" = "" ]; then
        # 创建$OUT_DIR目录
        mkdir -p $OUT_DIR
        FILELIST=$OUT_DIR/filelist
    else
        FILELIST=$T/filelist
    fi
    # 如果$FILELIST文件不存在，则将find命令结果输出到filelist中
    if [[ ! -f $FILELIST ]]; then
        echo -n "Creating index..."
        # 
        # 使用find命令从编译的根目录下查找文件"-type f"（目录out和.repo除外），并将结果输出到$FILELIST文件中
        # out目录和.repo目录的排除选项分别为：
        # - "-wholename ./out -prune"
        # - "-wholename ./.repo -prune"
        # 关于find的"-wholename pattern"选项，其行为跟"-path pattern"基本一样，具体可以查看find的帮助信息
        # 因此filelist文件保存了除out和.repo目录外其余目录的完整文件名
        (\cd $T; find . -wholename ./out -prune -o -wholename ./.repo -prune -o -type f > $FILELIST)
        echo " Done"
        echo ""
    fi
    local lines
    # 根据传入godir的参数，在filelist中搜索，并用sed处理后将结果存放在lines中
    # 操作"sed -e 's/\/[^/]*$//'"仅保留完整文件名的路径部分
    lines=($(\grep "$1" $FILELIST | sed -e 's/\/[^/]*$//' | sort | uniq))
    # 检查lines中的结果，即filelist通过grep和sed操作后，是否还有匹配的目录
    if [[ ${#lines[@]} = 0 ]]; then
        echo "Not found"
        return
    fi
    local pathname
    local choice
    # 如果lines的结果多于1行，则对各行进行编号并输出
    if [[ ${#lines[@]} > 1 ]]; then
        while [[ -z "$pathname" ]]; do
            # 从1开始编号
            local index=1
            local line
            for line in ${lines[@]}; do
                # 对每行以类似以下的格式进行输出：
                # $ godir fugu
                #   [1] ./device/asus/fugu
                #   [2] ./device/asus/fugu-kernel
                #   [3] ./device/asus/fugu/bluetooth
                #   [4] ./device/asus/fugu/dumpstate
                # 
                printf "%6s %s\n" "[$index]" $line
                # 序号自增
                index=$(($index + 1))
            done
            echo
            # 提示输入序号
            echo -n "Select one: "
            unset choice
            # 读取输入序号
            read choice
            if [[ $choice -gt ${#lines[@]} || $choice -lt 1 ]]; then
                echo "Invalid choice"
                continue
            fi
            # 取得输入序号对应的目录
            pathname=${lines[$(($choice-1))]}
        done
    else
        # 如果符合匹配的路径只有一条，则直接将匹配的路径存放到pathname中
        pathname=${lines[0]}
    fi
    # 转到选择的目标路径
    \cd $T/$pathname
}
```
#### `pez`
  `pez`函数的参数"$@"是一条可执行命令，通过执行结果来决定打印FAILUE和SUCCESS的颜色，失败打印红色的FAILURE，成功打印绿色的SUCCESS
```
# Print colored exit condition
function pez {
    # 执行参数命令#@
    "$@"
    # 获取$@命令的返回值
    local retval=$?
    # 检查返回值是否为0
    if [ $retval -ne 0 ]
    then
        # 输出红色的FAILURE
        echo $'\E'"[0;31mFAILURE\e[00m"
    else
        # 输出绿色的SUCCESS
        echo $'\E'"[0;32mSUCCESS\e[00m"
    fi
    # 将$@命令的执行结果返回给外层调用
    return $retval
}
```
#### `findmakefile`
  `findmakefile`查找当前模块的Android.mk并输出文件的详细路径
  以下是在目录`cd device/asus/fugu/kernel-headers/linux/sound/`内执行`findmakefile`的例子：
```
ygu@guyongqiangx:src$ cd device/asus/fugu/kernel-headers/linux/sound/
ygu@guyongqiangx:src/device/asus/fugu/kernel-headers/linux/sound$ findmakefile
/android/src/device/asus/fugu/Android.mk
ygu@guyongqiangx:src/device/asus/fugu/kernel-headers/linux/sound$ 
```
  显然，会在当前目录下逐层往外查找Android.mk，找到后显示Android.mk的完整路径，显示完路径后仍然在当前目录下。
  
```
function findmakefile()
{
    TOPFILE=build/core/envsetup.mk
    local HERE=$PWD
    T=
    # 检查是否已经在编译的根目录或系统根目录了
    while [ \( ! \( -f $TOPFILE \) \) -a \( $PWD != "/" \) ]; do
        T=`PWD= /bin/pwd`
        # 如果目录下存在Android.mk
        if [ -f "$T/Android.mk" ]; then
            # 输出Android.mk的完整路径
            echo $T/Android.mk
            # 切换回当前执行findmakefile的目录
            \cd $HERE
            return
        fi
        # 转到上级目录
        \cd ..
    done
    # 切换回当前执行findmakefile的目录
    \cd $HERE
}
```
#### `settitle`
  `settitle`根据板子设置，更细PROMPT_COMMAND设置
  这里的PROMPT_COMMAND设置看起来好像没有什么用。
  因此设置PROMPT_COMMAND有什么目的，我完全没弄清楚，求指点。
  以下是关于`PROMPT_COMMAND`的两个链接：
  http://www.tldp.org/HOWTO/Bash-Prompt-HOWTO/x264.html
  
  https://unix.stackexchange.com/questions/27692/in-bash-why-is-prompt-command-set-to-something-invisible
```
function settitle()
{
    # 如果STAY_OFF_MY_LAWN为""，则根据arch, product, variant, apps更新环境的PROMPT_COMMAND
    if [ "$STAY_OFF_MY_LAWN" = "" ]; then
        local arch=$(gettargetarch)
        local product=$TARGET_PRODUCT
        local variant=$TARGET_BUILD_VARIANT
        local apps=$TARGET_BUILD_APPS
        if [ -z "$apps" ]; then
            export PROMPT_COMMAND="echo -ne \"\033]0;[${arch}-${product}-${variant}] ${USER}@${HOSTNAME}: ${PWD}\007\""
        else
            export PROMPT_COMMAND="echo -ne \"\033]0;[$arch $apps $variant] ${USER}@${HOSTNAME}: ${PWD}\007\""
        fi
    fi
}
```
#### `set_sequence_number`
  `set_sequence_number`将BUILD_ENV_SEQUENCE_NUMBER设置为10
  说实话，我也不知道这个BUILD_ENV_SEQUENCE_NUMBER是做什么用的
```
function set_sequence_number()
{
    export BUILD_ENV_SEQUENCE_NUMBER=10
}
```
#### `set_stuff_for_environment`
  `set_stuff_for_environment` 调用前面定义的一系列函数设置`title`, `java home`, `path`, `sequence number`, `android build top dir`等环境变量
```
function set_stuff_for_environment()
{
    # 设置PROMPT_COMMAND
    settitle
    # 设置JAVA_HOME
    set_java_home
    # 将Android编译相关的toolchain和tools路径导入到PATH变量
    setpaths
    # 设置 BUILD_ENV_SEQUENCE_NUMBER
    set_sequence_number

    # 设置ANDROID_BUILD_TOP为编译根目录路径
    export ANDROID_BUILD_TOP=$(gettop)
    # With this environment variable new GCC can apply colors to warnings/errors
    # 通过注释看起来是设置GCC工具在error, warning, note, caret, lucus, quote情形下的颜色
    export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
    # 看起来这个选项是给ASAN使用的，参考链接：http://www.freebuf.com/news/83811.html
    export ASAN_OPTIONS=detect_leaks=0
}
```
#### `addcompletions`
  `addcompletions`命令将sdk/bash_completion目录下所有的*.bash文件通过'.'操作导入到当前环境中来
```
function addcompletions()
{
    local T dir f

    # Keep us from trying to run in something that isn't bash.
    # 检测shell版本字符串BASH_VERSION长度为0时，返回
    if [ -z "${BASH_VERSION}" ]; then
        return
    fi

    # Keep us from trying to run in bash that's too old.
    # 检测bash主版本低于3时返回
    if [ ${BASH_VERSINFO[0]} -lt 3 ]; then
        return
    fi

    # 指定dir目录并检查是否存在
    dir="sdk/bash_completion"
    if [ -d ${dir} ]; then
        # 获取sdk/bash_completion下的*.bash文件列表，并将这些*.bash文件包含进来
        for f in `/bin/ls ${dir}/[a-z]*.bash 2> /dev/null`; do
            echo "including $f"
            # 对*.bash文件执行'.'操作
            . $f
        done
    fi
}
```
### 1.2 编译环境设置类
#### `build_build_var_cache`
  `build_build_var_cache`命令用于创建`var_cache_xxx='yyy'`和`abs_var_cache_xxx='yyy'`的键值对，用于存储环境变量。
  主要的键值对包括：
  - `var_cache_2ND_TARGET_GCC_VERSION`
  - `var_cache_ANDROID_BUILD_PATHS`
  - `var_cache_TARGET_ARCH`
  - `var_cache_TARGET_DEVICE`
  - `var_cache_TARGET_GCC_VERSION`
  - `var_cache_print`
  - `var_cache_report_config`
  - `abs_var_cache_ANDROID_GCC_PREBUILTS`
  - `abs_var_cache_ANDROID_PREBUILTS`
  - `abs_var_cache_HOST_OUT`
  - `abs_var_cache_PRODUCT_OUT`
  - `abs_var_cache_print`
  键值对分析：
  - `var_cache_print`和`abs_var_cache_print`是因为提取脚本分析错误的原因，误以为'print'也是`get_build_var`/`get_build_var`需要提取的参数
  - `var_cache_report_config`存放了编译配置完整的的report
  
```
# Get all the build variables needed by this script in a single call to the build system.
function build_build_var_cache()
{
    # 获取编译根目录
    T=$(gettop)
    # Grep out the variable names from the script.
    # 
    # 我读书少，不太了解awk的用法，看了以下操作，确实开了眼界，值得借鉴
    # 命令直接分析脚本提取参数，确保刚好是需要的参数，没有多一个，也没有少一个，哈哈
    #
    # 搜索envsetup.sh文件中所有调用get_build_var的地方，提取其调用参数，并存放到cached_vars中
    # 我尝试在命令行直接执行操作，其得到的结果如下：
    # ygu@guyongqiangx:src$ cat build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/get_build_var/) print $(i+1)}'
    # print
    # 
    # TARGET_DEVICE
    # TARGET_GCC_VERSION
    # 2ND_TARGET_GCC_VERSION
    # TARGET_ARCH
    # ANDROID_BUILD_PATHS
    # report_config
    # TARGET_ARCH
    # 这里分析代码时把设置cached_vars的这行也包含在里面了，所以可以看到结果的第一行中有 print
    #
    cached_vars=`cat $T/build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/get_build_var/) print $(i+1)}' | sort -u | tr '\n' ' '`
    
    # 搜索envsetup.sh文件中所有调用get_abs_build_var的地方，提取其调用参数，并存放到cached_abs_vars中
    # ygu@guyongqiangx:src$ cat build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/get_abs_build_var/) print $(i+1)}'
    # print
    # 
    # ANDROID_GCC_PREBUILTS
    # PRODUCT_OUT
    # HOST_OUT
    # ANDROID_PREBUILTS
    # 这里跟提取get_build_var的参数一样，也包含了print一行
    # 
    cached_abs_vars=`cat $T/build/envsetup.sh | tr '()' '  ' | awk '{for(i=1;i<=NF;i++) if($i~/get_abs_build_var/) print $(i+1)}' | sort -u | tr '\n' ' '`
    # Call the build system to dump the "<val>=<value>" pairs as a shell script.
    #
    # 通过 command make --no-print-directory -f build/core/config.mk 命令来操作cached_vars和cached_abs_vars相关变量
    # 后续打算对build/core/config.mk进行分析，看看到底发生了什么，这里暂且略过。
    #
    build_dicts_script=`\cd $T; CALLED_FROM_SETUP=true BUILD_SYSTEM=build/core \
                        command make --no-print-directory -f build/core/config.mk \
                        dump-many-vars \
                        DUMP_MANY_VARS="$cached_vars" \
                        DUMP_MANY_ABS_VARS="$cached_abs_vars" \
                        DUMP_VAR_PREFIX="var_cache_" \
                        DUMP_ABS_VAR_PREFIX="abs_var_cache_"`
    # 检查上一步的返回值，即上一行命令中make操作的执行结果                      
    local ret=$?
    if [ $ret -ne 0 ]
    then
        unset build_dicts_script
        return $ret
    fi
    # Excute the script to store the "<val>=<value>" pairs as shell variables.
    # 对$build_dicts_script内容进行求值处理，从注释看起来是建立一个"<val>=<value>"的键值对
    # 通过在eval操作前“echo $build_dicts_script”输出发现，其格式是这样的（为便于阅读，已经经过换行处理）：
    # ygu@guyongqiangx:src$ build_build_var_cache  
    # var_cache_2ND_TARGET_GCC_VERSION='' 
    # var_cache_ANDROID_BUILD_PATHS='/android/src/out/host/linux-x86/bin' 
    # var_cache_TARGET_ARCH='arm' 
    # var_cache_TARGET_DEVICE='bcm7252ssffdr4' 
    # var_cache_TARGET_GCC_VERSION='4.9' 
    # var_cache_print='' 
    # var_cache_report_config=` \
    #           echo '============================================'; \
    #           echo 'PLATFORM_VERSION_CODENAME=REL'; \
    #           echo 'PLATFORM_VERSION=7.1.1'; \
    #           echo 'TARGET_PRODUCT=bcm7252ssffdr4'; \
    #           echo 'TARGET_BUILD_VARIANT=userdebug'; \
    #           echo 'TARGET_BUILD_TYPE=release'; \
    #           echo 'TARGET_BUILD_APPS='; \
    #           echo 'TARGET_ARCH=arm'; \
    #           echo 'TARGET_ARCH_VARIANT=armv7-a-neon'; \
    #           echo 'TARGET_CPU_VARIANT=cortex-a15'; \
    #           echo 'TARGET_2ND_ARCH='; \
    #           echo 'TARGET_2ND_ARCH_VARIANT='; \
    #           echo 'TARGET_2ND_CPU_VARIANT='; \
    #           echo 'HOST_ARCH=x86_64'; \
    #           echo 'HOST_2ND_ARCH=x86'; \
    #           echo 'HOST_OS=linux'; \
    #           echo 'HOST_OS_EXTRA=Linux-4.2.0-42-generic-x86_64-with-Ubuntu-14.04-trusty'; \
    #           echo 'HOST_CROSS_OS=windows'; \
    #           echo 'HOST_CROSS_ARCH=x86'; \
    #           echo 'HOST_CROSS_2ND_ARCH=x86_64'; \
    #           echo 'HOST_BUILD_TYPE=release'; \
    #           echo 'BUILD_ID=NMF27D'; \
    #           echo 'OUT_DIR=out'; \
    #           echo '============================================';` 
    # abs_var_cache_ANDROID_GCC_PREBUILTS='/android/src/prebuilts/gcc/linux-x86' 
    # abs_var_cache_ANDROID_PREBUILTS='/android/src/prebuilt/linux-x86' 
    # abs_var_cache_HOST_OUT='/android/src/out/host/linux-x86' 
    # abs_var_cache_PRODUCT_OUT='/android/src/out/target/product/bcm7252ssffdr4' 
    # abs_var_cache_print=''
    #
    eval "$build_dicts_script"
    # 显然，执行eval求值的结果就是建立如下类型的两种键值对：
    # var_cache_xxx='yyy'
    # abs_var_cache_xxx='yyy'
    #
    # 保存eval的求值结果
    ret=$?
    unset build_dicts_script
    # 检查$build_dicts_scripts操作是否成功
    if [ $ret -ne 0 ]
    then
        return $ret
    fi
    # 设置CACHE_READY标志
    BUILD_VAR_CACHE_READY="true"
}
```
#### `destroy_build_var_cache`
  `destroy_build_var_cache`命令清空所有通过`build_build_var_cache`函数建立的环境变量。
```
# Delete the build var cache, so that we can still call into the build system
# to get build variables not listed in this script.
function destroy_build_var_cache()
{
    # 取消CACHE_READY标志
    unset BUILD_VAR_CACHE_READY
    # 根据cached_vars列表取消相应变量var_cache_xxx的设置
    for v in $cached_vars; do
      unset var_cache_$v
    done
    # 清空cached_vars列表
    unset cached_vars
    # 根据cached_abs_vars列表取消相应变量abs_var_cache_xxx的设置
    for v in $cached_abs_vars; do
      unset abs_var_cache_$v
    done
    # 清空cached_abs_vars列表
    unset cached_abs_vars
}
```
#### `get_abs_build_var`
  `get_abs_build_var`命令查找通过`build_build_var_cache`函数建立的键值对列表，输出其参数对应的键值
  如，`get_abs_build_var xxx`，则返回变量`abs_var_cache_xxx`的值。
  `get_abs_build_var`函数跟`get_build_var`函数操作一样，唯一不同的地方是前者获取`abs_var_cache_xxx`变量的值，后者获取`var_cache_xxx`变量的值。
```
# Get the value of a build variable as an absolute path.
function get_abs_build_var()
{
    # 如果$BUILD_VAR_CACHE_READY=true，直接返回前缀为abs_var_cache_的变量
    # 函数 getprebuilt中，调用get_abs_build_var ANDROID_PREBUILTS，直接返回$abs_var_cache_ANDROID_PREBUILTS
    if [ "$BUILD_VAR_CACHE_READY" = "true" ]
    then
        # 有意思，通过对echo输出的内容进行eval来设置
        eval echo \"\${abs_var_cache_$1}\"
    return
    fi

    # 查找编译根目录，如果没找到，则退出函数
    T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
    # 切换到编译的根目录，执行命令"make --no-print-directory -f build/core/config.mk dumpvar-abs-$1"
    # 函数 getprebuilt中，调用get_abs_build_var ANDROID_PREBUILTS，执行命令："make --no-print-directory -f build/core/config.mk dumpvar-abs-ANDROID_PREBUILTS"
    # 这里应该是通过make命令来重新生成`$abs_var_cache_ANDROID_PREBUILTS`变量
    (\cd $T; CALLED_FROM_SETUP=true BUILD_SYSTEM=build/core \
      command make --no-print-directory -f build/core/config.mk dumpvar-abs-$1)
}
```

#### `get_build_var`
  `get_build_var`命令超找通过`build_build_var_cache`函数建立的键值对列表，输出其参数对应的键值
  如，`get_build_var xxx`，则返回变量`var_cache_xxx`的值。
  `get_build_var`函数跟`get_abs_build_var`函数操作一样，唯一不同的地方是前者获取`var_cache_xxx`变量的值，后者获取`abs_var_cache_xxx`变量的值。
```
# Get the exact value of a build variable.
function get_build_var()
{
    # 如果$BUILD_VAR_CACHE_READY=true，直接返回前缀为var_cache_的变量
    if [ "$BUILD_VAR_CACHE_READY" = "true" ]
    then
        eval echo \"\${var_cache_$1}\"
    return
    fi

    # 查找编译根目录，如果没找到，则退出函数
    T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
    # 切换到编译的根目录，执行命令"make --no-print-directory -f build/core/config.mk dumpvar-$1"
    # 来重新生成`$var_cache_ANDROID_PREBUILTS`变量
    (\cd $T; CALLED_FROM_SETUP=true BUILD_SYSTEM=build/core \
      command make --no-print-directory -f build/core/config.mk dumpvar-$1)
}
```
#### `check_product`
  `check_product`检查TARGET_DEVICE设置是否有效
```
# check to see if the supplied product is one we can build
function check_product()
{
    # 查找编译根目录，如果没找到，则退出函数
    T=$(gettop)
    if [ ! "$T" ]; then
        echo "Couldn't locate the top of the tree.  Try setting TOP." >&2
        return
    fi
        # 将参数1设置到TARGET_PRODUCT，其余相关参数置空
        TARGET_PRODUCT=$1 \
        TARGET_BUILD_VARIANT= \
        TARGET_BUILD_TYPE= \
        TARGET_BUILD_APPS= \
        # 通过get_build_var获取var_cache_TARGET_DEVICE变量，并将标准输出的内容重定向到/dev/null
        get_build_var TARGET_DEVICE > /dev/null
    # hide successful answers, but allow the errors to show
    # 这里根据注释说，错误信息会显示，并且check_product的返回值是get_build_var函数的调用结果
}
```
#### `check_variant`
  `check_variant` 检查输入的选项是否`(user userdebug eng)`这三者之一，找到返回0，找不到返回1
```
VARIANT_CHOICES=(user userdebug eng)

# check to see if the supplied variant is valid
function check_variant()
{
    # 遍历数组VARIANT_CHOICES=(user userdebug eng)
    for v in ${VARIANT_CHOICES[@]}
    do
        # 如果匹配，返回0
        if [ "$v" = "$1" ]
        then
            return 0
        fi
    done
    # 没有找到，返回1
    return 1
}
```
#### `choosetype`
  `choosetype` 根据传入选项或读取用户输入设置编译版本是release还是debug版
```
function choosetype()
{
    # 显示提示信息
    echo "Build type choices are:"
    echo "     1. release"
    echo "     2. debug"
    echo

    # 设置默认选项为"1. release"
    local DEFAULT_NUM DEFAULT_VALUE
    DEFAULT_NUM=1
    DEFAULT_VALUE=release

    export TARGET_BUILD_TYPE=
    local ANSWER
    # 检查是否已经设置TARGET_BUILD_TYPE，设置后其值不为空
    while [ -z $TARGET_BUILD_TYPE ]
    do
        # 提示默认选项为"[1]"
        echo -n "Which would you like? ["$DEFAULT_NUM"] "
        # 如果choosetype不带参数，则读取参数到ANSWER
        if [ -z "$1" ] ; then
            read ANSWER
        else
            # choosetype带参数的情况下，直接将参数保存到ANSWER
            echo $1
            ANSWER=$1
        fi
        # 根据ANSWER，设置TARGET_BUILD_TYPE
        case $ANSWER in
        "")
            export TARGET_BUILD_TYPE=$DEFAULT_VALUE
            ;;
        1)
            export TARGET_BUILD_TYPE=release
            ;;
        release)
            export TARGET_BUILD_TYPE=release
            ;;
        2)
            export TARGET_BUILD_TYPE=debug
            ;;
        debug)
            export TARGET_BUILD_TYPE=debug
            ;;
        *)
            echo
            echo "I didn't understand your response.  Please try again."
            echo
            ;;
        esac
        # 如果choosetype带有参数，则退出while循环，不用再提示设置
        if [ -n "$1" ] ; then
            break
        fi
    done

    # 设置编译环境相关变量var_cache_xxx和abs_var_cache_xxx
    build_build_var_cache
    # 设置其他环境变量，如PROMPT_COMMAND，编译toolchain和tools相关的路径等
    set_stuff_for_environment
    # 清空环境变量，不懂为什么刚设置了这些变量，这里又要取消？
    destroy_build_var_cache
}
```
#### `chooseproduct`
  `chooseproduct` 根据预先设置的变量或读取用户输入设置TARGET_PRODUCT
```
#
# This function isn't really right:  It chooses a TARGET_PRODUCT
# based on the list of boards.  Usually, that gets you something
# that kinda works with a generic product, but really, you should
# pick a product by name.
#
# 注释里面提到一些trick，说需要通过name来选择product
#
function chooseproduct()
{
    # 检查TARGET_PRODUCT是否为空
    if [ "x$TARGET_PRODUCT" != x ] ; then
        # 已经设置TARGET_PRODUCT，则保存到default_value
        default_value=$TARGET_PRODUCT
    else
        # 没有设置TARGET_PRODUCT，则设置default_value为aosp_arm
        default_value=aosp_arm
    fi

    export TARGET_BUILD_APPS=
    export TARGET_PRODUCT=
    local ANSWER
    # 读取TARGET_PRODUCT设置
    while [ -z "$TARGET_PRODUCT" ]
    do
        # 如果chooseproduct有带参数，则将参数保存到ANSWER
        # 否则，在命令行读取用户输入数据，并保存到ANSWER
        echo -n "Which product would you like? [$default_value] "
        if [ -z "$1" ] ; then
            read ANSWER
        else
            echo $1
            ANSWER=$1
        fi

        # 如果 ANSWER 长度为0，即用户直接回车输入的情况
        if [ -z "$ANSWER" ] ; then
            export TARGET_PRODUCT=$default_value
        else
            # 调用check_product函数检查输入ANSWER
            if check_product $ANSWER
            then
                export TARGET_PRODUCT=$ANSWER
            else
                echo "** Not a valid product: $ANSWER"
            fi
        fi
        # 如果chooseproduct带了参数，则不再读取输入，跳出循环
        if [ -n "$1" ] ; then
            break
        fi
    done

    # 设置编译环境相关变量var_cache_xxx和abs_var_cache_xxx
    build_build_var_cache
    # 设置其他环境变量，如PROMPT_COMMAND，编译toolchain和tools相关的路径等
    set_stuff_for_environment
    # 清空环境变量，不懂为什么刚设置了这些变量，这里又要取消？
    destroy_build_var_cache
}
```
#### `choosevariant`
  `choosevariant` 读取用户输入设置`TARGET_BUILD_VARIANT`为`user`,`userdebug`或`eng`
```
function choosevariant()
{
    echo "Variant choices are:"
    local index=1
    local v
    # 从1开始，循环显示VARIANT_CHOICES数组的内容，效果如下：
    # $ choosevariant
    # Variant choices are:
    #      1. user
    #      2. userdebug
    #      3. eng
    # Which would you like? [eng]
    #
    for v in ${VARIANT_CHOICES[@]}
    do
        # The product name is the name of the directory containing
        # the makefile we found, above.
        echo "     $index. $v"
        index=$(($index+1))
    done

    local default_value=eng
    local ANSWER

    export TARGET_BUILD_VARIANT=
    # 交互读取TARGET_BUILD_VARIANT设置
    while [ -z "$TARGET_BUILD_VARIANT" ]
    do
        # 读取用户输入，默认为[eng]
        echo -n "Which would you like? [$default_value] "
        if [ -z "$1" ] ; then
            read ANSWER
        else
            # 如果choosevariant有带参数，则直接用保存参数
            echo $1
            ANSWER=$1
        fi

        # 如果 ANSWER 长度为0，即用户直接回车输入的情况
        if [ -z "$ANSWER" ] ; then
            export TARGET_BUILD_VARIANT=$default_value
        # 将ANSWER的数值转换为VARIANT_CHOICES数组中的字符串
        elif (echo -n $ANSWER | grep -q -e "^[0-9][0-9]*$") ; then
            if [ "$ANSWER" -le "${#VARIANT_CHOICES[@]}" ] ; then
                export TARGET_BUILD_VARIANT=${VARIANT_CHOICES[$(($ANSWER-1))]}
            fi
        else
            # 调用check_variant是否为有效值
            if check_variant $ANSWER
            then
                export TARGET_BUILD_VARIANT=$ANSWER
            else
                echo "** Not a valid variant: $ANSWER"
            fi
        fi
        # 如果choosevariant带了参数，则不再读取输入，跳出循环
        if [ -n "$1" ] ; then
            break
        fi
    done
}
```
#### `choosecombo`
  `choosecombo`根据传入的3个参数，分别设置type(release, debug), product和variant(user, userdebug, eng)参数
```
function choosecombo()
{
    # 使用参数1设置type (release, debug)
    choosetype $1

    # 使用参数2设置product
    echo
    echo
    chooseproduct $2

    # 使用参数3设置variant (user, userdebug, eng)
    echo
    echo
    choosevariant $3

    echo
    # 设置编译环境相关变量var_cache_xxx和abs_var_cache_xxx
    build_build_var_cache
    # 设置其他环境变量，如PROMPT_COMMAND，编译toolchain和tools相关的路径等
    set_stuff_for_environment
    # 显示当前选择的编译配置
    printconfig
    # 清空环境变量，不懂为什么刚设置了这些变量，这里又要取消？
    destroy_build_var_cache
}
```
#### `add_lunch_combo`
  `add_lunch_combo`将提供的编译选项参数添加到`LUNCH_MENU_CHOICES`列表中
```
function add_lunch_combo()
{
    local new_combo=$1
    local c
    for c in ${LUNCH_MENU_CHOICES[@]} ; do
        if [ "$new_combo" = "$c" ] ; then
            return
        fi
    done
    LUNCH_MENU_CHOICES=(${LUNCH_MENU_CHOICES[@]} $new_combo)
}
```
#### `print_lunch_menu`
  `print_lunch_menu`打印编译选项列表`LUNCH_MENU_CHOICES`的所有项
```
function print_lunch_menu()
{
    local uname=$(uname)
    echo
    echo "You're building on" $uname
    echo
    echo "Lunch menu... pick a combo:"

    local i=1
    local choice
    # 遍历数组LUNCH_MENU_CHOICES，以类似"1. aosp_arm-eng"的格式输出
    for choice in ${LUNCH_MENU_CHOICES[@]}
    do
        echo "     $i. $choice"
        i=$(($i+1))
    done

    echo
}
```
#### `lunch`
  `lunch`操作根据传入参数选项设置`TARGET_PRODUCT`, `TARGET_BUILD_VARIANT`和`TARGET_BUILD_TYPE`
```
function lunch()
{
    local answer

    # 获取lunch操作的参数
    if [ "$1" ] ; then
        answer=$1
    else
        # lunch操作不带参数，则先显示lunch menu，然后读取用户输入
        print_lunch_menu
        echo -n "Which would you like? [aosp_arm-eng] "
        read answer
    fi

    local selection=

    # lunch操作得到的结果为空（例如用户直接在lunch要求输入时回车的情况）
    # 则将选项默认为"aosp_arm-eng"
    if [ -z "$answer" ]
    then
        selection=aosp_arm-eng
    # lunch操作得到的输入是数字，则将数字转换为LUNCH_MENU_CHOICES中的字符串
    elif (echo -n $answer | grep -q -e "^[0-9][0-9]*$")
    then
        if [ $answer -le ${#LUNCH_MENU_CHOICES[@]} ]
        then
            selection=${LUNCH_MENU_CHOICES[$(($answer-1))]}
        fi
    # lunch操作得到的是字符串，直接将字符串保存到selection中      
    elif (echo -n $answer | grep -q -e "^[^\-][^\-]*-[^\-][^\-]*$")
    then
        selection=$answer
    fi

    # 检查selection的值是否正常
    # 例如选择了一个LUNCH_MENU_CHOICES中不存在的索引，则selection就为空
    if [ -z "$selection" ]
    then
        echo
        echo "Invalid lunch combo: $answer"
        return 1
    fi

    export TARGET_BUILD_APPS=

    #
    # 分离selection字符串，例如：aosp_fugu-userdebug
    #
    # 获取第一个'-'后的部分，这里即userdebug，保存到variant
    local variant=$(echo -n $selection | sed -e "s/^[^\-]*-//")
    # 检查variant是否合法，即是否选项(user, userdebug, eng)之一，如果不是，输出提示
    check_variant $variant
    if [ $? -ne 0 ]
    then
        echo
        echo "** Invalid variant: '$variant'"
        echo "** Must be one of ${VARIANT_CHOICES[@]}"
        variant=
    fi

    # 获取最后一个'-'前的部分，这里即aosp_fugu，保存到product
    local product=$(echo -n $selection | sed -e "s/-.*$//")
    
    # 设置TARGET_PRODUCT和TARGET_BUILD_VARIANT
    TARGET_PRODUCT=$product \
    TARGET_BUILD_VARIANT=$variant \
    # 根据前面的设置，更新编译环境相关变量
    build_build_var_cache
    if [ $? -ne 0 ]
    then
        echo
        echo "** Don't have a product spec for: '$product'"
        echo "** Do you have the right repo manifest?"
        product=
    fi

    # product或variant为空的情况下，退出函数
    if [ -z "$product" -o -z "$variant" ]
    then
        echo
        return 1
    fi

    # export 编译选项TARGET_PRODUCT, TARGET_BUILD_VARIANT和TARGET_BUILD_TYPE三元组
    export TARGET_PRODUCT=$product
    export TARGET_BUILD_VARIANT=$variant
    export TARGET_BUILD_TYPE=release

    echo

    # 设置其他环境变量，如PROMPT_COMMAND，编译toolchain和tools相关的路径等
    set_stuff_for_environment
    # 输出当前的设置选项
    printconfig
    # 清空环境变量，不懂为什么刚设置了这些变量，这里又要取消？
    destroy_build_var_cache
}
```
#### `_lunch`
  `_lunch`命令提供lunch命令的补全操作
```
# Tab completion for lunch.
function _lunch()
{
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # 生成补全结果
    COMPREPLY=( $(compgen -W "${LUNCH_MENU_CHOICES[*]}" -- ${cur}) )
    return 0
}
# 指定遇到lunch命令时，用_lunch函数的输出的内容进行补全
complete -F _lunch lunch
```
#### `m`
  可以在代码的任何一个目录里面执行`m`指令编译所有模块
  其实很简单，就是用make的`-C`选项指定到代码的根目录。
```
function m()
{
    # 获取代码的根目录
    local T=$(gettop)
    # 编译无关，可以忽略此选项
    local DRV=$(getdriver $T)
    if [ "$T" ]; then
        # 直接转到代码的根目录进行编译
        $DRV make -C $T -f build/core/main.mk $@
    else
        echo "Couldn't locate the top of the tree.  Try setting TOP."
        return 1
    fi
}
```
#### `mm`
  `mm`指令编译当前目录下的所有模块
```
function mm()
{
    # 获取代码根目录
    local T=$(gettop)
    local DRV=$(getdriver $T)
    # If we're sitting in the root of the build tree, just do a
    # normal make.
    # 如果在代码根目录下执行mm指令，转换为直接运行make指令
    if [ -f build/core/envsetup.mk -a -f Makefile ]; then
        $DRV make $@
    else
        # 超找当前目录对应模块的Android.mk文件
        # Find the closest Android.mk file.
        local M=$(findmakefile)
        local MODULES=
        local GET_INSTALL_PATH=
        local ARGS=
        # Remove the path to top as the makefilepath needs to be relative
        # 将查找到的Android.mk转换为针对代码根目录的相对路径
        local M=`echo $M|sed 's:'$T'/::'`
        # 好吧，没有找到代码的根目录
        if [ ! "$T" ]; then
            echo "Couldn't locate the top of the tree.  Try setting TOP."
            return 1
        # 好吧，竟然没有Android.mk文件
        elif [ ! "$M" ]; then
            echo "Couldn't locate a makefile from the current directory."
            return 1
        else
            # 逐个处理命令行参数
            for ARG in $@; do
                case $ARG in
                  GET-INSTALL-PATH) GET_INSTALL_PATH=$ARG;;
                esac
            done
            # 如果GET_INSTALL_PATH不为空，则
            if [ -n "$GET_INSTALL_PATH" ]; then
              MODULES=
              ARGS=GET-INSTALL-PATH
            # 编译所有模块
            else
              MODULES=all_modules
              ARGS=$@
            fi
            # 转到代码根目录开始编译指定的模块
            ONE_SHOT_MAKEFILE=$M $DRV make -C $T -f build/core/main.mk $MODULES $ARGS
        fi
    fi
}
```
#### `mmm`
  `mmm`手动指定目录和，其下面编译的模块，格式如下：
  `mmm dir1,dir2,dir3,dir4/,...:[module1],[module2],[module3],[module4] -options`
 
```
function mmm()
{
    # 获取代码根目录
    local T=$(gettop)
    local DRV=$(getdriver $T)
    # 在代码根目录存在的情况下，开始进行命令参数解析和编译
    if [ "$T" ]; then
        local MAKEFILE=
        local MODULES=
        local ARGS=
        local DIR TO_CHOP
        local GET_INSTALL_PATH=
        # 提取编译命令中的选项参数，即符号"-"后面接的参数
        local DASH_ARGS=$(echo "$@" | awk -v RS=" " -v ORS=" " '/^-.*$/')
        # 提取编译命令中目录和模块部分，即符号的"-"前的参数部分
        # 例如 "mmm dir1 dir2 dir3 dir4/:module1,module2,module3,module4"
        local DIRS=$(echo "$@" | awk -v RS=" " -v ORS=" " '/^[^-].*$/')
        for DIR in $DIRS ; do
            #
            # 编译命令类似 mmm dir1 dir2 dir3 dir4/:module1,module2,module3,module4
            #
            # 第一个sed命令获取$DIR中":"后面的module1~module4的部分
            # 第二个sed命令替换到各个目标间的','号，将其转换为一个包含编译目标的数组，即模块
            # 处理后变成 MODULES=module1 module2 module3 module4
            MODULES=`echo $DIR | sed -n -e 's/.*:\(.*$\)/\1/p' | sed 's/,/ /'`
            # 没有指定模块的话，默认为all_modules
            if [ "$MODULES" = "" ]; then
                MODULES=all_modules
            fi
            # 第一个sed命令提取$DIR的":"前的目录部分
            # 第二个sed命令忽略目录部分的"/"后缀
            # 处理后变成DIR=dir1 dir2 dir3 dir4
            DIR=`echo $DIR | sed -e 's/:.*//' -e 's:/$::'`
            # 如果处理后的文件夹得到的DIR下有Android.mk
            if [ -f $DIR/Android.mk ]; then
                # 计算代码根目录路径包含的字符数
                local TO_CHOP=`(\cd -P -- $T && pwd -P) | wc -c | tr -d ' '`
                # 代码根目录路径的字符数+1
                local TO_CHOP=`expr $TO_CHOP + 1`
                # 获取当前目录的绝对路径START
                local START=`PWD= /bin/pwd`
                # 获取当前目录相对于根目录的相对路径，并保存在MFILE中
                local MFILE=`echo $START | cut -c${TO_CHOP}-`
                # 构建Android.mk的相对路径
                if [ "$MFILE" = "" ] ; then
                    MFILE=$DIR/Android.mk
                else
                    MFILE=$MFILE/$DIR/Android.mk
                fi
                MAKEFILE="$MAKEFILE $MFILE"
            else
                # 如果处理后的文件夹下面没有Android.mk，说明其可能不是目录，而是某个命令，如showcommands
                case $DIR in
                  # 如果是showcommands, snode, dist或*=*的情况，将其作为真正编译命令的参数传递
                  showcommands | snod | dist | *=*) ARGS="$ARGS $DIR";;
                  GET-INSTALL-PATH) GET_INSTALL_PATH=$DIR;;
                  # 不是showcommands, snode, dist等的情况下，检查这个目录是否存在
                  *) if [ -d $DIR ]; then
                         # 目录存在，但Android.mk不存在，提示没有Android.mk文件
                         echo "No Android.mk in $DIR.";
                     else
                         echo "Couldn't locate the directory $DIR";
                     fi
                     return 1;;
                esac
            fi
        done
        # 将GET_INSTALL_PATH作为参数传入编译
        if [ -n "$GET_INSTALL_PATH" ]; then
          ARGS=$GET_INSTALL_PATH
          MODULES=
        fi
        # 将mmm命令“-”后的选项和模块参数以及其他参数传递给主makefile进行编译
        ONE_SHOT_MAKEFILE="$MAKEFILE" $DRV make -C $T -f build/core/main.mk $DASH_ARGS $MODULES $ARGS
    # 获取代码根目录是T返回空，说明没有找到代码根目录，有什么办法？那就显示错误信息并退出吧      
    else
        echo "Couldn't locate the top of the tree.  Try setting TOP."
        return 1
    fi
}
```
#### `mma`
  `mma` 相当于mm执行相应目录下的all_modules参数
```
function mma()
{
  # 获取代码根目录
  local T=$(gettop)
  local DRV=$(getdriver $T)
  # 如果在代码根目录下执行mm指令，转换为直接运行make指令
  if [ -f build/core/envsetup.mk -a -f Makefile ]; then
    $DRV make $@
  else
    # 取得的代码根目录路径为空，那就报错退出
    if [ ! "$T" ]; then
      echo "Couldn't locate the top of the tree.  Try setting TOP."
      return 1
    fi
    # 将当前目录转换为相对于根目录的相对路径
    local MY_PWD=`PWD= /bin/pwd|sed 's:'$T'/::'`
    # 基于路径设置MODULES-IN-PATH参数
    local MODULES_IN_PATHS=MODULES-IN-$MY_PWD
    # Convert "/" to "-".
    MODULES_IN_PATHS=${MODULES_IN_PATHS//\//-}
    # 编译所有模块
    $DRV make -C $T -f build/core/main.mk $@ $MODULES_IN_PATHS
  fi
}
```
#### `mmma`
  `mmma` 相当于mmm执行相应目录下的all_modules参数
```
function mmma()
{
  # 获取代码根目录
  local T=$(gettop)
  local DRV=$(getdriver $T)
  # 在代码根目录存在的情况下，开始进行命令参数解析和编译
  if [ "$T" ]; then
    # 提取编译命令中的选项参数，即符号"-"后面接的参数
    local DASH_ARGS=$(echo "$@" | awk -v RS=" " -v ORS=" " '/^-.*$/')
    # 提取编译命令中目录和模块部分，即符号的"-"前的参数部分
    # 例如 "mmm dir1 dir2 dir3 dir4/:module1,module2,module3,module4"
    local DIRS=$(echo "$@" | awk -v RS=" " -v ORS=" " '/^[^-].*$/')
    # 获取当前目录
    local MY_PWD=`PWD= /bin/pwd`
    # 将当前目录到代码根目录的相对路径保存到MY_PWD中
    if [ "$MY_PWD" = "$T" ]; then
      MY_PWD=
    else
      MY_PWD=`echo $MY_PWD|sed 's:'$T'/::'`
    fi
    local DIR=
    local MODULES_IN_PATHS=
    local ARGS=
    for DIR in $DIRS ; do
      # 检查DIR指定的参数是否为目录
      if [ -d $DIR ]; then
        # Remove the leading ./ and trailing / if any exists.
        DIR=${DIR#./}
        DIR=${DIR%/}
        # 生成DIR相对于代码根目录的完整相对路径
        if [ "$MY_PWD" != "" ]; then
          DIR=$MY_PWD/$DIR
        fi
        MODULES_IN_PATHS="$MODULES_IN_PATHS MODULES-IN-$DIR"
      else
        # 如果DIR对应的参数是showcommands, snod, dist等，将其转换为参数ARGS
        case $DIR in
          showcommands | snod | dist | *=*) ARGS="$ARGS $DIR";;
          *) echo "Couldn't find directory $DIR"; return 1;;
        esac
      fi
    done
    # Convert "/" to "-".
    MODULES_IN_PATHS=${MODULES_IN_PATHS//\//-}
    # 将mmm命令“-”后的选项和模块参数以及其他参数传递给主makefile进行编译
    $DRV make -C $T -f build/core/main.mk $DASH_ARGS $ARGS $MODULES_IN_PATHS
  else
    # 获取代码根目录是T返回空，说明没有找到代码根目录，有什么办法？那就显示错误信息并退出吧    
    echo "Couldn't locate the top of the tree.  Try setting TOP."
    return 1
  fi
}
```
#### `get_make_command`
  `get_make_command`将`make`命令转换为`command make`调用。
  执行`souce build/envsetup.sh`后环境中有两个`make`：
  
  - `envsetup.sh`脚本中定义的`make`
  - make系统的可执行文件`make`
  命令行运行`make`时，先执行`shell`环境中内置的`make`函数，然后`make`函数内部通过`command`命令调用可执行文件`make`

```
function get_make_command()
{
  echo command make
}
```
#### `make`
  `make`
```
function make()
{
    # 获取开始时间
    local start_time=$(date +"%s")
    # 
    # 命令行运行`make`时，先执行`shell`环境中内置的`make`函数（本函数），
    # 然后通过函数的`command`命令调用可执行文件`make`进行真正的make操作
    # 这里相当于是重新定义shell命令行的函数将命令`make`拦截了
    #
    # 将make xxx转换为命令command make xxx执行
    $(get_make_command) "$@"
    # 获取可执行文件make的返回值
    local ret=$?
    # 获取执行make命令完成的时间
    local end_time=$(date +"%s")
    # 计算时间差，并转换为HH:MM:SS的格式
    local tdiff=$(($end_time-$start_time))
    local hours=$(($tdiff / 3600 ))
    local mins=$((($tdiff % 3600) / 60))
    local secs=$(($tdiff % 60))
    # 设置各种字体颜色
    local ncolors=$(tput colors 2>/dev/null)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        color_failed=$'\E'"[0;31m"
        color_success=$'\E'"[0;32m"
        color_reset=$'\E'"[00m"
    else
        color_failed=""
        color_success=""
        color_reset=""
    fi
    echo
    # 显示编译成功信息
    if [ $ret -eq 0 ] ; then
        echo -n "${color_success}#### make completed successfully "
    
    # 显示编译失败信息
    else
        echo -n "${color_failed}#### make failed to build some targets "
    fi
    # 显示make操作执行的时间
    if [ $hours -gt 0 ] ; then
        printf "(%02g:%02g:%02g (hh:mm:ss))" $hours $mins $secs
    elif [ $mins -gt 0 ] ; then
        printf "(%02g:%02g (mm:ss))" $mins $secs
    elif [ $secs -gt 0 ] ; then
        printf "(%s seconds)" $secs
    fi
    echo " ####${color_reset}"
    echo
    return $ret
}
```
#### `tapas`
  `tapas` 以交互方式设置单个app编译的build环境变量，调用格式为：
  ```
  tapas [<App1> <App2> ...] [arm|x86|mips] [eng|userdebug|user]
  ```
  话说tapas长这样，其实做底层的我一次都没有用过这个命令。
  
```
# Configures the build to build unbundled apps.
# Run tapas with one or more app names (from LOCAL_PACKAGE_NAME)
function tapas()
{
    # 获取参数里的arch相关变量（arm|x86|mips|armv5|arm64|x86_64|mips64）
    local arch="$(echo $* | xargs -n 1 echo | \grep -E '^(arm|x86|mips|armv5|arm64|x86_64|mips64)$' | xargs)"
    # 获取参数里variant相关变量（user|userdebug|eng）
    local variant="$(echo $* | xargs -n 1 echo | \grep -E '^(user|userdebug|eng)$' | xargs)"
    # 获取参数里分辨率DPI（`Dot Per Inch`，每英寸像素数）相关的参数
    local density="$(echo $* | xargs -n 1 echo | \grep -E '^(ldpi|mdpi|tvdpi|hdpi|xhdpi|xxhdpi|xxxhdpi|alldpi)$' | xargs)"
    # 使用`grep -v`过滤参数中arch, variant，density相关参数，然后将剩余参数指定为apps
    local apps="$(echo $* | xargs -n 1 echo | \grep -E -v '^(user|userdebug|eng|arm|x86|mips|armv5|arm64|x86_64|mips64|ldpi|mdpi|tvdpi|hdpi|xhdpi|xxhdpi|xxxhdpi|alldpi)$' | xargs)"

    #
    # 检查命令行是否设置了多个arch, variant和density参数，显然这类相关参数变量只能有唯一值
    #
    
    # 检查是否设置了多个arch参数，显示错误消息
    if [ $(echo $arch | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple build archs supplied: $arch"
        return
    fi
    # 检查是否设置了多个variant参数，显示错误消息
    if [ $(echo $variant | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple build variants supplied: $variant"
        return
    fi
    # 检查是否设置了多个density参数，显示错误消息
    if [ $(echo $density | wc -w) -gt 1 ]; then
        echo "tapas: Error: Multiple densities supplied: $density"
        return
    fi

    # 根据arch设置针对相应平台的默认的product
    local product=aosp_arm
    case $arch in
      x86)    product=aosp_x86;;
      mips)   product=aosp_mips;;
      armv5)  product=generic_armv5;;
      arm64)  product=aosp_arm64;;
      x86_64) product=aosp_x86_64;;
      mips64)  product=aosp_mips64;;
    esac
    # 没有指定variant，则默认设置为eng
    if [ -z "$variant" ]; then
        variant=eng
    fi
    # 没有指定app，则默认为all
    if [ -z "$apps" ]; then
        apps=all
    fi
    # 没有指定density参数，则默认设置为alldpi
    if [ -z "$density" ]; then
        density=alldpi
    fi

    # 根据以上的各参数设置编译环境变量TARGET_PRODUCT, TARGET_BUILD_{VARIANT, DENSITY, TYPE, APPS}
    export TARGET_PRODUCT=$product
    export TARGET_BUILD_VARIANT=$variant
    export TARGET_BUILD_DENSITY=$density
    export TARGET_BUILD_TYPE=release
    export TARGET_BUILD_APPS=$apps

    # 设置编译环境相关变量var_cache_xxx和abs_var_cache_xxx
    build_build_var_cache
    # 设置其他环境变量，如PROMPT_COMMAND，编译toolchain和tools相关的路径等
    set_stuff_for_environment
    # 显示当前选择的编译配置
    printconfig
    # 清空环境变量，不懂为什么刚设置了这些变量，这里又要取消？
    destroy_build_var_cache
}
```
### 1.3 代码搜索类

代码搜索类函数定义了各种xxxgrep函数，并导入到当前环境中，使其可以直接在命令行调用。
这些函数先用find命令在除.repo/.git/out的目录外搜索相应后名称的目录或文件，然后基于搜索结果调用grep进行模式查找。

  - `sgrep`，基于(c|h|cc|cpp|S|java|xml|sh|mk|aidl|vts)文件查找
  - `ggrep`，基于(.gradle)的文件查找
  - `jgrep`，基于(.java)文件查找
  - `cgrep`，基于(c|cc|cpp|h|hpp)文件查找
  - `resgrep`，基于res目录下(xml)文件查找
  - `mangrep`，基于AndroidManifest.xml文件查找
  - `sepgrep`，基于sepolicy目录下查找
  - `rcgrep`，基于`*.rc*`文件查找
  - `mgrep`，基于(`Makefile|Makefile\..*|.*\.make|.*\.mak|.*\.mk`)的Makefile文件查找
  - `treegrep`，基于代码的文件(c|h|cpp|S|java|xml)进行查找

```
# 针对MAC和非MAC环境定义sgrep函数
case `uname -s` in
    Darwin)
        function sgrep()
        {
            # 排除 .repo, .git目录
            # 并对后缀(c|h|cc|cpp|S|java|xml|sh|mk|aidl|vts)的文件执行grep模式搜索
            find -E . -name .repo -prune -o -name .git -prune -o  -type f -iregex '.*\.(c|h|cc|cpp|S|java|xml|sh|mk|aidl|vts)' \
                -exec grep --color -n "$@" {} +
        }

        ;;
    *)
        function sgrep()
        {
            find . -name .repo -prune -o -name .git -prune -o  -type f -iregex '.*\.\(c\|h\|cc\|cpp\|S\|java\|xml\|sh\|mk\|aidl\|vts\)' \
                -exec grep --color -n "$@" {} +
        }
        ;;
esac

function ggrep()
{
    # 排除 .repo, .git, out目录
    # 并对后缀.gradle的文件执行grep模式搜索
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.gradle" \
        -exec grep --color -n "$@" {} +
}

function jgrep()
{
    # 排除 .repo, .git, out目录
    # 并对后缀为.java的文件执行grep模式搜索
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.java" \
        -exec grep --color -n "$@" {} +
}

function cgrep()
{
    # 排除 .repo, .git, out目录
    # 并对后缀为(.c|.cc|.cpp|.h|.hpp)的文件执行grep模式搜索
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) \
        -exec grep --color -n "$@" {} +
}

function resgrep()
{
    # 排除 .repo, .git, out目录
    # 并对名为res目录下的*.xml文件执行grep模式搜索
    for dir in `find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -name res -type d`; do
        find $dir -type f -name '*\.xml' -exec grep --color -n "$@" {} +
    done
}

function mangrep()
{
    # 排除 .repo, .git, out目录
    # 并对名为AndroidManifest.xml的文件执行grep模式搜索
    find . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o -type f -name 'AndroidManifest.xml' \
        -exec grep --color -n "$@" {} +
}

function sepgrep()
{
    # 排除 .repo, .git, out目录
    # 并对名为sepolicy目录中的文件执行grep模式搜索
    find . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o -name sepolicy -type d \
        -exec grep --color -n -r --exclude-dir=\.git "$@" {} +
}

function rcgrep()
{
    # 排除 .repo, .git, out目录
    # 并对名为*.rc*的文件执行grep模式搜索
    find . -name .repo -prune -o -name .git -prune -o -name out -prune -o -type f -name "*\.rc*" \
        -exec grep --color -n "$@" {} +
}

case `uname -s` in
    Darwin)
        function mgrep()
        {
            # 排除 .repo, .git, ./out目录
            # 并对Makefile，后缀为(.make|.mak|.mk)的文件或Makefile目录下的文件执行grep模式搜索
            find -E . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o -type f -iregex '.*/(Makefile|Makefile\..*|.*\.make|.*\.mak|.*\.mk)' \
                -exec grep --color -n "$@" {} +
        }

        function treegrep()
        {
            # 排除 .repo, .git目录
            # 并对后缀为(.c|.h|.cpp|.S|.java|.xml)的文件执行grep模式搜索
            find -E . -name .repo -prune -o -name .git -prune -o -type f -iregex '.*\.(c|h|cpp|S|java|xml)' \
                -exec grep --color -n -i "$@" {} +
        }

        ;;
    *)
        function mgrep()
        {
            find . -name .repo -prune -o -name .git -prune -o -path ./out -prune -o -regextype posix-egrep -iregex '(.*\/Makefile|.*\/Makefile\..*|.*\.make|.*\.mak|.*\.mk)' -type f \
                -exec grep --color -n "$@" {} +
        }

        function treegrep()
        {
            find . -name .repo -prune -o -name .git -prune -o -regextype posix-egrep -iregex '.*\.(c|h|cpp|S|java|xml)' -type f \
                -exec grep --color -n -i "$@" {} +
        }

        ;;
esac

```

### 1.4 `adb`调试类
#### `qpid`
  `qpid`

```
# simplified version of ps; output in the form
# <pid> <procname>
function qpid() {
    local prepend=''
    local append=''
    if [ "$1" = "--exact" ]; then
        prepend=' '
        append='$'
        shift
    elif [ "$1" = "--help" -o "$1" = "-h" ]; then
        echo "usage: qpid [[--exact] <process name|pid>"
        return 255
    fi

    local EXE="$1"
    if [ "$EXE" ] ; then
        qpid | \grep "$prepend$EXE$append"
    else
        adb shell ps \
            | tr -d '\r' \
            | sed -e 1d -e 's/^[^ ]* *\([0-9]*\).* \([^ ]*\)$/\1 \2/'
    fi
}
```
#### `pid`
  `pid`
```
function pid()
{
    local prepend=''
    local append=''
    if [ "$1" = "--exact" ]; then
        prepend=' '
        append='$'
        shift
    fi
    local EXE="$1"
    if [ "$EXE" ] ; then
        local PID=`adb shell ps \
            | tr -d '\r' \
            | \grep "$prepend$EXE$append" \
            | sed -e 's/^[^ ]* *\([0-9]*\).*$/\1/'`
        echo "$PID"
    else
        echo "usage: pid [--exact] <process name>"
        return 255
    fi
}
```
#### `coredump_setup`
#### `coredump_enable`
#### `core`
#### `systemstack`
#### `stacks`
#### `is64bit`
#### `tracedmdump`
#### `runhat`
#### `getbugreports`
#### `getsdcardpath`
#### `getscreenshotpath`
#### `getlastscreenshot`
#### `startviewserver`
#### `stopviewserver`
#### `isviewserverstarted`
#### `key_home`
#### `key_back`
#### `key_menu`
#### `smoketest`
#### `runtest`
#### `provision`
  `provision`
```
function provision()
{
    # 如果ANDROID_PRODUCT_OUT没有设置，则退出函数
    if [ ! "$ANDROID_PRODUCT_OUT" ]; then
        echo "Couldn't locate output files.  Try running 'lunch' first." >&2
        return 1
    fi
    # 如果$ANDROID_PRODUCT_OUT/provision-device文件不存在，则退出函数
    if [ ! -e "$ANDROID_PRODUCT_OUT/provision-device" ]; then
        echo "There is no provisioning script for the device." >&2
        return 1
    fi

    # Check if user really wants to do this.
    # 如果第一个参数是--no-confirmation，表明不需要交互执行脚本
    if [ "$1" = "--no-confirmation" ]; then
        shift 1
    else
        # 交互执行脚本，弹出确认信息
        echo "This action will reflash your device."
        echo ""
        echo "ALL DATA ON THE DEVICE WILL BE IRREVOCABLY ERASED."
        echo ""
        echo -n "Are you sure you want to do this (yes/no)? "
        read
        # 用户选择no，则退出程序
        if [[ "${REPLY}" != "yes" ]] ; then
            echo "Not taking any action. Exiting." >&2
            return 1
        fi
    fi
    # 开始执行provision-device脚本
    "$ANDROID_PRODUCT_OUT/provision-device" "$@"
}
```
## 2. 生成编译配置列表

`envsetup.sh`脚本中除去函数的定义外，剩下的就是自身的逻辑应用，为了方便起见，以下是删除函数定义后的脚本内容：

```
...
# 编译的可能选项后缀
VARIANT_CHOICES=(user userdebug eng)
...
# Clear this variable.  It will be built up again when the vendorsetup.sh
# files are included at the end of this file.
# 清空选项菜单
unset LUNCH_MENU_CHOICES
...
# add the default one here
# 添加默认的菜单编译选项，包括aosp_{arm, arm64, mips, mips64, x86, x86_64}-eng等选项
add_lunch_combo aosp_arm-eng
add_lunch_combo aosp_arm64-eng
add_lunch_combo aosp_mips-eng
add_lunch_combo aosp_mips64-eng
add_lunch_combo aosp_x86-eng
add_lunch_combo aosp_x86_64-eng
...
# 设置_lunch作为lunch命令的补全函数
complete -F _lunch lunch
...
# 检查当前执行的shell环境是否为bash，如果不是，输出警告信息
if [ "x$SHELL" != "x/bin/bash" ]; then
    case `ps -o command -p $$` in
        *bash*)
            ;;
        *)
            echo "WARNING: Only bash is supported, use of other shell would lead to erroneous results"
            ;;
    esac
fi

# Execute the contents of any vendorsetup.sh files we can find.
# 依次查找{device, vendor, product}目录下的vendorsetup.sh文件
for f in `test -d device && find -L device -maxdepth 4 -name 'vendorsetup.sh' 2> /dev/null | sort` \
         `test -d vendor && find -L vendor -maxdepth 4 -name 'vendorsetup.sh' 2> /dev/null | sort` \
         `test -d product && find -L product -maxdepth 4 -name 'vendorsetup.sh' 2> /dev/null | sort`
do
    # 对查找到的vendorsetup.sh文件执行"."操作，将其内容导入到当前环境中来
    # 一个约定俗成是vendorsetup.sh里面调用add_lunch_combo添加编译选项，例如：
    # 文件device\asus\fugu\vendorsetup.sh的内容为：
    #     add_lunch_combo full_fugu-userdebug
    #     add_lunch_combo aosp_fugu-userdebug
    echo "including $f"
    . $f
done
# 清除变量f
unset f

# 调用addcompletions函数设置基于sdk/bash_completion的补全功能
addcompletions
```

简单来说，`envsetup.sh`搜集各个vendor定义的编译选项，存放到lunch menu中，供下一步的`lunch`操作使用。

执行`lunch`操作是，`lunch`函数解析传入的编译选项，如`full_fugu-userdebug`，更新相应的Android编译环境变量。

## 后记

对这样的脚本文件进行逐行分析真是花费时间，前后用掉了几个下午，写出来的内容也啰嗦冗长，也是够佩服自己的耐心，差点就忍不住了。
好吧，就当是对envsetup.sh的75个函数进行完全解读，留作字典来查询了。

如果只想知道envsetup.sh的大概功能，浏览下主要关心的函数就够了，没有必要对每一行代码都细致入微的分析，这样效率太低。
`envsetup.sh`的主要内容包括：
- `m`/`mm`/`mmm`操作
- `lunch`操作的过程
- 各个自定义的脚本文件vendorsetup.sh是如何起作用的就够了

除此之外的其它函数，如各种搜索函数，`adb`调试函数等，可能永远都不会用到。
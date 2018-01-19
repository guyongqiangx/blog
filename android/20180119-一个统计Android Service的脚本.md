# 一个统计Android Service的脚本

最近在Android 8.0上做启动时间优化，需要统计生成的service，顺手写了个脚本抓取生成的root system vendor目录下*.rc文件内的service内容。

目前主要的功能是汇总所有的service到一个文件，这样就不用逐个打开文件找了。后续更新打算对各种service进行分类。

- 用法
    ```
    $ ./check-android-services.sh 
    usage: check-android-services.sh 'dir1 dir2 dir3' service-list-file
         $ check-android-services.sh 'root system vendor' service.list
    $ ./check-android-services.sh "root system vendor" service-list.txt
    ```

- 代码
    ```
    #!/bin/bash
    
    function usage () {
      echo "usage: `basename $0` 'dir1 dir2 dir3' service-list-file"
      echo "     $ `basename $0` 'root system vendor' service.list"
    }
    
    if [ $# -ne 2 ]; then
      usage
      exit 1
    fi
    
    DIRS=$1
    SERVICE_LIST=$2
    
    #echo "check android services in: $DIRS, and list in $SERVICE_LIST" 
    
    # check_service input_file out_putfile
    function check_service() {
      IFS_SAVE=$IFS
      IFS=''
      MODE=false
    
      DONE=false
    
      until $DONE
      do read -r LINE || DONE=true
      #while read -r LINE
      #do
        #echo "$LINE"
        # start with "service"
      	if echo $LINE | grep -E '^service' > /dev/null 2>&1; then
      	  if [ x$MODE = "xfalse" ]; then
      	    MODE=true
      	  else
      	    echo "" >> $2
      	  fi
      	  echo $LINE >> $2
      	elif [ x$LINE = "x" ]; then
      	  if [ x$MODE = "xtrue" ]; then
      	    MODE=false
      	    echo "" >> $2
      	  fi
      	# start with whitespace
      	elif echo $LINE | grep -E '^[ \t]' > /dev/null 2>&1; then
      	  if [ x$MODE = "xtrue" ]; then
      	    echo $LINE >> $2
      	  else
            continue
          fi
      	fi
      done < $1
      IFS=${IFS_SAVE}
    }
    
    if [ -e $SERVICE_LIST ]; then
      rm -f $SERVICE_LIST
    fi
    
    for dir in $DIRS
    do
      # get *.rc files list
      FILES=`find $dir -type f -iname "*.rc" 2>/dev/null | sort`
    
      for f in $FILES
      do
        echo $f
    
        # only check file contains "service"
        if grep -E '^service ' $f >/dev/null 2>&1; then
          # add file name
          echo "[$f]" >> $SERVICE_LIST
    
          # add service details
          #sed -n '/^service /,/^[^ ]/p' $f >> $SERVICE_LIST
          #echo "" >> $SERVICE_LIST
    
          check_service $f $SERVICE_LIST
        fi
      done
    done
    
    exit 0
    ```
- 脚本下载地址
  [check-android-services.sh](https://raw.githubusercontent.com/guyongqiangx/blog/dev/android/src/check-android-services.sh)
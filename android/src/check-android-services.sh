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
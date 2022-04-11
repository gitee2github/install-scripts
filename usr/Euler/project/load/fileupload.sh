#!/bin/bash
:<<!
* Copyright (c) Huawei Technologies Co., Ltd. 2013-2022. All rights reserved.
* install-scripts licensed under the Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*     http://license.coscl.org.cn/MulanPSL2
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
* PURPOSE.
* See the Mulan PSL v2 for more details.
* Create: 2022-02-28
* Description: the main log upload program
!

source $LOCAL_SCRIPT_PATH/util/CommonFunction

#os local path
FT_LOCALPATH=
FT_FILEPATH=
FT_SERVERURL=
FT_TRAN_PROTOCOL=
FT_SERVER_IP=
FT_SERVER_PORT=
FT_SERVER_SOURCE_PATH=
FT_USER_NAME=
FT_USER_PASSWORD=
# log file
FT_LOGFILE=

FT_MOUNT=`which mount`
FT_FPING=`which ping`
FT_TFTP=`which tftp`

function test_server_connection
{
  local serverIp=$1
  local try_time=10
  local n=1
  if [ -z "$serverIp" ]; then
    echo "serverIp is not exit" | tee -a $FT_LOGFILE
    return 1
  fi
  while [ 1 -eq 1 ]
  do
      $FT_FPING -c 1 $serverIp
      returnvalue=$?
      if [ $returnvalue -eq 0 ]; then
          return $returnvalue
      else
         if [ $n -eq $try_time ]; then
            echo "can not connect to server serverIp is ****" | tee -a $FT_LOGFILE
            return 1
         fi
         sleep 1
         ((n++))
      fi
  done
}
function FT_FileUploadByNfs
{
    local mountpoint="/opt/tmpnfs"

    if [ -z "$FT_SERVER_SOURCE_PATH" ];then
       echo "server source path is not exit." | tee -a $FT_LOGFILE
       return 1
    fi


    if [ -n "`mount | grep "$mountpoint"`" ];then
        echo " $mountpoint has already  be mounted " | tee -a $FT_LOGFILE
        return 1
    fi

    if [ -d $mountpoint ]; then
        rm -rf $mountpoint
    fi
    mkdir -p $mountpoint
    if [ $? -ne 0 ]; then
        g_LOG_Error "mkdir $mountpoint failed"
        return 1
    fi



    $FT_MOUNT -o rsize=8192,wsize=8192,soft,nolock,timeo=10,intr -t nfs $FT_SERVER_IP:$FT_SERVER_SOURCE_PATH $mountpoint | tee -a $FT_LOGFILE
    if [ ${PIPESTATUS[0]} -ne 0 ];then
        echo "NFS mount failed." | tee -a $FT_LOGFILE
        return 1
    fi

    if [ -d $FT_LOCALPATH ]; then
        cp -dpR $FT_LOCALPATH/* $mountpoint
        returnValue=$?
    elif [ -f $FT_LOCALPATH ]; then
        cp -dp $FT_LOCALPATH $mountpoint
        returnValue=$?
    else
        if [ -n "`mount | grep "$mountpoint"`" ];then
            umount $mountpoint
        fi
        echo "FT_LOCALPATH is not exist" | tee -a $FT_LOGFILE
        return 1
    fi
    if [ -n "`mount | grep "$mountpoint"`" ];then
        umount $mountpoint
    fi
    return $returnValue
}
function FT_FileUploadByCifs
{
    local mountpoint="/opt/tmpcifs"

    if [ -z "$FT_SERVER_SOURCE_PATH" ];then
        echo "server source path is not exit." | tee -a $FT_LOGFILE
        return 1
    fi

    if [ -n "`mount | grep "$mountpoint"`" ];then
        echo " $mountpoint has already  be mounted " | tee -a $FT_LOGFILE
        return 1
    fi
    if [ -d $mountpoint ]; then
        rm -rf $mountpoint
    fi
    mkdir -p $mountpoint
    if [ $? -ne 0 ]; then
        g_LOG_Error "mkdir $mountpoint failed"
        return 1
    fi

    if [ -z "$FT_USER_NAME" ];then
        echo "username is not exist." | tee -a $FT_LOGFILE
        return 1
    fi

    if [ -z "$FT_USER_PASSWORD" ];then
        echo "userpassword is not exist." | tee -a $FT_LOGFILE
        return 1
    fi

    $FT_MOUNT -t cifs -o user=$FT_USER_NAME,password=$FT_USER_PASSWORD "//$FT_SERVER_IP$FT_SERVER_SOURCE_PATH" $mountpoint | tee -a $FT_LOGFILE
    if [ ${PIPESTATUS[0]} -ne 0 ];then
        echo "CIFS mount failed." | tee -a $FT_LOGFILE
        return 1
    fi

    if [ -d $FT_LOCALPATH ]; then
        cp -dpR $FT_LOCALPATH/* $mountpoint
        returnValue=$?
    elif [ -f $FT_LOCALPATH ]; then
        cp -dp $FT_LOCALPATH $mountpoint
        returnValue=$?
    else
        if [ -n "`mount | grep "$mountpoint"`" ];then
            umount $mountpoint
        fi
        echo "FT_LOCALPATH is not exist"
        return 1
    fi
    if [ -n "`mount | grep "$mountpoint"`" ];then
      umount $mountpoint
    fi
    return $returnValue
}
function FT_FileUploadByTftp
{
    local FILENAME
    local FILEPATH
    if [ -d $FT_LOCALPATH ]; then
        cd $FT_LOCALPATH
        for line in $FT_LOCALPATH/*
        do
            if [ ! -f "$line" ]; then
                echo "$line is not a file." | tee -a $FT_LOGFILE
                return 1
            fi
            tftp $FT_SERVER_IP &>> $FT_LOGFILE <<EOF
            put ${line##*/}
            quit
EOF
            if cat  "$FT_LOGFILE" | grep "Error code" ;then
                echo "tftp upload failed[${line##*/}]." | tee -a $FT_LOGFILE
                return 1
            fi
        done
    elif [ -f $FT_LOCALPATH ]; then
        FILENAME=`basename "$FT_LOCALPATH"`
        FILEPATH=`dirname "$FT_LOCALPATH"`
        cd $FILEPATH
        tftp $FT_SERVER_IP &>> $FT_LOGFILE <<EOF
        put $FILENAME
        quit
EOF
        if cat  "$FT_LOGFILE" | grep "Error code" ;then
           echo "tftp upload failed[$FT_LOCALPATH]." | tee -a $FT_LOGFILE
           return 1
        fi
    else
       echo "$FT_LOCALPATH is not exist"
       return 1
    fi
    cd -
    return 0
}
function FT_FileUploadByFtp
{

   local url=""
   if [ -z "$FT_SERVER_SOURCE_PATH" ];then
      echo "server source path is not exit." | tee -a $FT_LOGFILE
      return 1
   fi
   if [ -z "$FT_USER_NAME" ];then
      echo "username is not exist." | tee -a $FT_LOGFILE
      return 1
   fi

   if [ -z "$FT_USER_PASSWORD" ];then
      echo "userpassword is not exist." | tee -a $FT_LOGFILE
      return 1
   fi

   if [ -z "$FT_SERVER_PORT" ];then
      url=$FT_SERVER_IP
   else
      url=$FT_SERVER_IP:$FT_SERVER_PORT
   fi

   if [ "x/" == "x$FT_SERVER_SOURCE_PATH" ];then
      url=$url/
   else
      url=$url/$FT_SERVER_SOURCE_PATH/
   fi

   url=ftp://$FT_USER_NAME:$FT_USER_PASSWORD@$url

   if [ -d $FT_LOCALPATH ]; then
       for line in $FT_LOCALPATH
       do
           if [ ! -f "$line" ]; then
               echo "$line is not a file." | tee -a $FT_LOGFILE
               return 1
           fi
           curl -T "$line" $url | tee -a $FT_LOGFILE
           returnValue=${PIPESTATUS[0]}
           if [  $returnValue -ne 0 ];then
               echo "ftp upload faied[${line##*/}]." | tee -a $FT_LOGFILE
               return $returnValue
           fi
       done
    elif [ -f $FT_LOCALPATH ]; then
        curl -T $FT_LOCALPATH  $url
        returnValue=${PIPESTATUS[0]}
        if [  $returnValue -ne 0 ];then
            echo "ftp upload faied[$FT_LOCALPATH]." | tee -a $FT_LOGFILE
            return $returnValue
        fi
    else
        echo "$FT_LOCALPATH is not exist" | tee -a $FT_LOGFILE
        return 1
    fi

    return $returnValue
}

function FT_ParseUrl
{
    local serverUrl
    local userName;
    local password;
    local tmpPath;
    local pattern="^[nN][Ff][sS]$|^[cC][iI][fF][sS]$|^[fF][tT][pP]$|^[tT][fF][tT][pP]$"
    local ipPattern="^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$"

    serverUrl=$1
    if [ -z "$1" ];then
        echo "serverurl is not exist." | tee -a $FT_LOGFILE
        return 1
    fi

    #FT_TRAN_PROTOCOL
    FT_TRAN_PROTOCOL=`echo $serverUrl | awk -F':' '{print $1}'`
    if ! echo $FT_TRAN_PROTOCOL | grep -q -E "$pattern"; then
        echo "The serverurl protcol must be nfs,cifs,ftp,tftp" | tee -a $FT_LOGFILE
        return 1
    fi

    #FT_SERVER_IP, protocol://IP[:port ]/softwarepath?u=u&p=pwd
    tmpPath=`echo ${serverUrl} | awk -F '://' '{print $2}' | awk -F'?' '{print $1}'`
    FT_SERVER_IP=`echo ${tmpPath} | awk -F'/' '{print $1}' | awk -F':' '{print $1}'`
    if ! echo "$FT_SERVER_IP" | grep -q "$ipPattern" ;then
        echo "ip address format is invild" | tee -a $FT_LOGFILE
        return 1
    fi

    #FT_SERVER_PORT
    FT_SERVER_PORT=`echo ${tmpPath} | awk -F'/' '{print $1}' | awk -F':' '{print $2}'`

    #FT_SERVER_SOURCE_PATH,softwarepath
    FT_SERVER_SOURCE_PATH=`echo ${tmpPath#*/}`
    FT_SERVER_SOURCE_PATH="`echo $FT_SERVER_SOURCE_PATH | sed "s/^[\/]\{0,\}//g" | sed "s/\/$//g"`"
    if [ -z "$FT_SERVER_SOURCE_PATH" ];then
        FT_SERVER_SOURCE_PATH="/"
    fi

    #FT_USER_NAME,FT_USER_PASSWORD
    TMP_PARAMS=`echo $serverUrl | awk -F "?" '{print $2}'`
    if [ -n "$TMP_PARAMS" ]; then
        tempPattern=`echo $TMP_PARAMS | awk -F "@" '{print $1}'`
        if echo "$tempPattern" | grep -q "^[u|U]=.*$"; then
            userName=`echo $tempPattern | awk -F "=" '{print $2}'`
        elif echo "$tempPattern" | grep -q "^[p|P]=.*$"; then
            password=`echo $tempPattern | awk -F "=" '{print $2}'`
        fi

        tempPattern=`echo $TMP_PARAMS | awk -F "@" '{print $2}'`
        if echo "$tempPattern" | grep -q "^[u|U]=.*$"; then
            userName=`echo $tempPattern | awk -F "=" '{print $2}'`
        elif echo "$tempPattern" | grep -q "^[p|P]=.*$"; then
            password=`echo $tempPattern | awk -F "=" '{print $2}'`
        fi

        FT_USER_NAME=$userName
        FT_USER_PASSWORD=$password
    fi

    return 0
}

function g_FT_FileUpload
{
    FT_LOCALPATH=$1
    FT_SERVERURL=$2
    FT_LOGFILE=$3

    if [ ! -f "$FT_LOGFILE" ];then
        echo "logfile is not exist"
        return 1
    fi

    if [ -z "$FT_LOCALPATH" ];then
        echo "localpath is not exist" | tee -a $FT_LOGFILE
        return 1
    fi
    FT_LOCALPATH="`echo $FT_LOCALPATH | sed "s/^[\/]\{0,\}/\//g" | sed "s/\/$//g"`"

    if [ -z "$FT_SERVERURL" ];then
        echo "serverurl is not exist" | tee -a $FT_LOGFILE
        return 1
    fi

    FT_ParseUrl $FT_SERVERURL
    if [ $? -ne 0 ];then
        echo "FT_ParseUrl failed!" | tee -a $FT_LOGFILE
        return 1
    fi

    if [ -z "$FT_TRAN_PROTOCOL" ];then
        echo "protocol is not exist." | tee -a $FT_LOGFILE
        return 1
    fi

    test_server_connection $FT_SERVER_IP
    if [ $? -ne 0 ];then
        echo "ping FT_SERVER_IP failed!" | tee -a $FT_LOGFILE
        return 1
    fi

    if echo $FT_TRAN_PROTOCOL | grep "^[nN][fF][sS]$"; then
        FT_FileUploadByNfs
        if [ $? -ne 0 ];then
            echo "FT_FileUploadByNfs failed!" | tee -a $FT_LOGFILE
            return 1
        fi
    elif echo $FT_TRAN_PROTOCOL | grep "^[cC][iI][fF][sS]$"; then
        FT_FileUploadByCifs
        if [ $? -ne 0 ];then
            echo "FT_FileUploadByCifs failed!" | tee -a $FT_LOGFILE
            return 1
        fi
    elif echo $FT_TRAN_PROTOCOL | grep "^[fF][tT][pP]$"; then
        FT_FileUploadByFtp
        if [ $? -ne 0 ];then
            echo "FT_FileUploadByFtp failed!" | tee -a $FT_LOGFILE
            return 1
        fi
    elif echo $FT_TRAN_PROTOCOL | grep "^[tT][fF][tT][pP]$"; then
        FT_FileUploadByTftp
        if [ $? -ne 0 ];then
            echo "FT_FileUploadByTftp failed!" | tee -a $FT_LOGFILE
            return 1
        fi
    else
        echo "Unsupported protocol:[$FT_TRAN_PROTOCOL]" | tee -a $FT_LOGFILE
        return 1
    fi

    return 0
}

#param $1 localPath, $2 serverurl, $3 logfile
g_FT_FileUpload $1 $2 $3
if [ $? -ne 0 ];then
    echo "upload files failed!" | tee -a $FT_LOGFILE
    exit 1
else
    echo "upload files success!" | tee -a $FT_LOGFILE
    exit 0
fi

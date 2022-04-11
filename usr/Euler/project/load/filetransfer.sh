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
* Description: load the installation file
!

FT_WGET=`which wget`
FT_MOUNT=`which mount`
FT_FPING=`which ping`
FT_TFTP=`which tftp`

#file transfer protocol cd, nfs, ftp
FT_TRAN_PROTOCOL=""
#file transfer server port
FT_SERVER_PORT=""
#pxe server ip
FT_SERVER_IP=""
#install media path on the file server
FT_SERVER_SOURCE_PATH=""
#local path
FT_LOCAL_PATH=""
#file server's user name
FT_USER_NAME=""
#file server's password
FT_USER_PASSWORD=""

#ft cdrom dev name
FT_SR_DEV=""

FT_FILE_LIST="filelist"

function mountDirectory()
{
    local mountoption
    local filesystype
    local bemountedpoint
    local mountpoint
    local retcode=0

    #mount cifs diretory
    if  [ $# -eq 4 ];then
        mountoption=$1
        filesystype=$2
        bemountedpoint=$3
        mountpoint=$4
    elif [ $# -eq 3 ]; then
        filesystype=$1
        bemountedpoint=$2
        mountpoint=$3
    else
        g_LOG_Error "lack of parameter,parameter must be ge 3"
        return 1
    fi

    mkdir -p $mountpoint

    if [ ! -d $mountpoint ]; then
        g_LOG_Error "error mount point is not a directory"
        return 1
    fi

    #replace the unnessary "/" from the mountpoint
    mountCheckPath="`echo $mountpoint | sed "s/[\/]\{2,\}/\//g" | sed "s/\/$//g"`"

    #check bemountedpoint or mountpoint is already mounted
    if [ -n "` cat /proc/mounts | grep " $mountCheckPath " | grep $bemountedpoint`" ];then
        g_LOG_Info "$mountCheckPath has been mounted"
        return 1
    fi

    g_LOG_Info "begin mount $bemountedpoint to $mountpoint"

    [ "x$mountoption" != "x" ] && mountoption="-o $mountoption"
    $FT_MOUNT $mountoption -t $filesystype $bemountedpoint $mountCheckPath >>tmp$$.log 2>&1
    retcode=$?
    g_LOG_Info "end mount $bemountedpoint to $mountpoint `cat tmp$$.log`"
    rm -rf tmp$$.log

    return $retcode
}
#########################################################################
function ft_mountNfsDir()
{
    local filesystype="nfs"
    local serverIp=$1
    local sourceDir=$2
    local targetDir=$3
    local mountoption
    if [ $# -lt 3 ];then
        g_LOG_Error "lack of parameter"
	return 1
    fi

    mountoption="rsize=8192,wsize=8192,soft,nolock,timeo=10,intr"
    sourceDir="`echo $sourceDir | sed "s/^[\/]\{0,\}/\//g" | sed "s/\/$//g"`"
    mountDirectory $mountoption $filesystype $serverIp:$sourceDir $targetDir
    return $?
}

######################################################################
function ft_mountCifsDir()
{
    local serverIp=$1
    local sourceDir=$2
    local targetDir=$3
    local username=$4
    local password=$5
    local filesysType="cifs"
    local mountoption
    if [ $# -lt 5 ];then
        g_LOG_Error "lack of parameter"
        return 1
    fi

    if [ -n "${username}" -a -n "${password}" ]; then
        mountoption="user=${username},password=${password}"
    fi

    sourceDir="`echo ${sourceDir} | sed "s/^[\/]\{0,\}/\//g" | sed "s/\/$//g"`"
    mountDirectory ${mountoption} ${filesysType} "//${serverIp$sourceDir}" ${targetDir}

    return $?
}
####################################################################
function checkDevSr()
{
    local sr_dev=$1
    local mountpoint=$2
    local filesysType="iso9660"
    local mountoption="loop"
    if [ -e ${sr_dev} ];then
        mountdir=${sr_dev}
        mountDirectory ${mountoption} ${filesysType} ${mountdir} ${mountpoint}
        if [ $? -eq 0 ];then
            return 0
        else
            if [ -n "`cat /proc/mounts | grep " ${mountpoint} " | grep " ${mountdir} "`" ]; then
                umount ${mountpoint} >>${OTHER_TTY} 2>&1
            fi
            return 1
        fi

        if [ -n "`cat /proc/mounts | grep " ${mountpoint} " | grep " ${mountdir} "`" ]; then
            umount ${mountpoint} >>${OTHER_TTY} 2>&1
        fi
    fi
    return 1
}

################################################################
function ft_mountCdromDir()
{
    local mountpoint=$1
    local count=1
    if [ $# -lt 1 ];then
        g_LOG_Error "lack of parameter"
        return 1
    fi
    if [ -n "${FT_SR_DEV}" ]; then
        checkDevSr ${FT_SR_DEV} ${mountpoint}
        [ $? -eq 0 ] && return 0
    fi

    while [ 1 -eq 1 ]
    do
        SR_SCSI_DEV_ALL=`ls /dev/sr[0-9]* 2>>${OTHER_TTY}`
        for FT_SR_DEV in ${SR_SCSI_DEV_ALL}
        do
            checkDevSr ${FT_SR_DEV} ${mountpoint}
            [ $? -eq 0 ] && return 0
        done
        sleep 1
        ((count++))
        if [ ${count} -gt 5 ]; then
            g_LOG_Error "cdrom not found"
            return 1
        fi
    done
}
##########################################################
function ft_downloadFile()
{
    local serverUrl
    local targetPath
    local fileType
    local returnVal
    if [ $# -lt 3 ]; then
        g_LOG_Error "lack of parmter"
        return 1
    fi

    serverUrl=$1
    targetPath=$2
    fileType=$3

    mkdir -p ${targetPath}
    if [ $? -ne 0 ]; then
        g_LOG_Error "mkdir ${targetPath} failed"
        return 1
    fi

    case ${fileType} in
    0)
       ${FT_WGET} -c ${serverUrl} --timeout=300 -P ${targetPath} >>tmp$$.txt 2>&1
       returnVal=$?
     ;;
    1)
       ${FT_WGET} -N -r -np ${serverUrl}\/ --timeout=300 -x -nH -P ${targetPath}\/>>tmp$$.txt 2>&1
       returnVal=$?
     ;;
    *)
       echo "fielType is worng" >>tmp$$.txt 2>&1
       returnVal=1;
     ;;
    esac

    if [ ${returnVal} -ne 0 ];then
       g_LOG_Error "`cat tmp$$.txt`"
    else
       g_LOG_Debug "`cat tmp$$.txt`"
    fi
    rm -rf tmp$$.txt
    return ${returnVal}
}
###########################################################
function tftp_download()
{
    local result=
    local filelist="filelist"
    local serverIp
    local serverPort
    local sourceFile
    local targetFile
    if [ $# -eq 3 ]; then
        serverIp=$1
        sourceFile=$2
        targetFile=$3
    else
        serverIp=$1
        serverPort=$2
        sourceFile=$3
        targetFile=$4
    fi
    local targetDir=`dirname ${targetFile}`
    local fileName=`basename ${targetFile}`

    mkdir -p ${targetDir}
    if [ $? -ne ${targetDir} ]; then
        g_LOG_Error "mkdir ${targetDir} failed"
        return 1
    fi

    if echo ${fileName} | grep -q ${FT_FILE_LIST} ;then
        #download filelist first
        result=`${FT_TFTP} ${serverIp} ${serverPort} -c get ${sourceFile}/${filelist} ${targetFile} 2>&1`
        if [ ! -z "${result}" ];then
            g_LOG_Error "${result}"
            g_LOG_Error "Download remote file [${FT_FILE_LIST}] failed, maybe it's not exist."
            return 1
        fi

        if [ ! -f ${targetFile} ];then
            g_LOG_Error "[${targetFile}] is not exist."
            return 1
        fi

        while read line
        do
            if [ -z "${line}" ]; then
                g_LOG_Notice "This line in ${targetFile} is empty"
                continue
            fi
            local basedir=`dirname ${line}`
            if [ ! -d ${targetDir}/${basedir} ];then
                mkdir -p ${targetDir}/${basedir}
                if [ $? -ne 0 ]; then
                    g_LOG_Error "mkdir ${targetDir}/${basedir} failed"
                    return 1
                fi
            fi
            echo "${line}" | grep "\/$" > /dev/null 2>&1
            if [ $? -ne 0 ];then
                result=`${FT_TFTP} ${serverIp} ${serverPort} -c get ${sourceFile}/${line} ${targetDir}/${line} 2>&1`
                if [ ! -z "${result}" ]; then
                    rm -rf ${targetDir}/${line} > /dev/null 2>&1
                    g_LOG_Warn "${result}"
                    g_LOG_Warn "Download remote file [${sourceFile}/${line}] failed, maybe it's not exist."
                fi
            fi
        done < ${targetFile}
    else
        result=`${FT_TFTP} ${serverIp} ${serverPort} -c get ${sourceFile} ${targetFile} 2>&1`
        if [ ! -z "${result}" ];then
            rm -rf ${targetFile} > /dev/null 2>&1
            g_LOG_Error "${result}"
            g_LOG_Error "Download remote file [${sourceFile}] failed, maybe it's not exist."
            return 1
        fi
    fi
    return 0
}

###########################################################
function parseUrl()
{
    local serverUrl=
    local userName=
    local password=
    local pattern="^[fF][iI][lL][eE]$|^[cC][dD]$|^[nN][fF][sS]$|^[fF][tT][pP]$|^[hH][tT][tT][pP]$|^[tT][fF][tT][pP]$"
    local ipPattern="^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$"
    local tmpPath=
    local TMP_PARAMS=

    if [ -z "$1" ]; then
        g_LOG_Error "lack of parmter"
        return 1
    fi
    serverUrl=$1
    FT_TRAN_PROTOCOL=`echo ${serverUrl} | awk -F ":" '{print $1}'`
    if ! echo ${FT_TRAN_PROTOCOL} | grep -q -E "${pattern}"; then
        g_LOG_Error "The serverurl protocol must be cd, nfs, ftp, http or tftp"
        return 1
    fi
    g_LOG_Debug "file transfer protocol is ${FT_TRAN_PROTOCOL}"
    tmpPath=`echo ${serverUrl} | awk -F "://" '{print $2}' | awk -F'?' '{print $1}'`
    if echo ${FT_TRAN_PROTOCOL} | grep -q "^[cC][dD]$"; then
        FT_SERVER_SOURCE_PATH=${tmpPath}
	g_LOG_Debug "file source path is ${FT_SERVER_SOURCE_PATH}"
    elif echo ${FT_TRAN_PROTOCOL} | grep -q "^[fF][iI][lL][eE]$"; then
        FT_SERVER_SOURCE_PATH=${tmpPath}
    else
        FT_SERVER_IP=`echo ${tmpPath} | awk -F'/' '{print $1}' | awk -F':' '{print $1}'`
        if ! echo "${FT_SERVER_IP}" | grep -q "${ipPattern}"; then
            g_LOG_Debug "ip address format is invild"
            return 1
        fi
        FT_SERVER_PORT=`echo ${tmpPath} | awk -F'/' '{print $1}' | awk -F':' '{print $2}'`
        FT_SERVER_SOURCE_PATH=`echo ${tmpPath#*/}`
        g_LOG_Debug "file server source path is ${FT_SERVER_SOURCE_PATH}"
        TMP_PARAMS=`echo ${serverUrl} | awk -F "?" '{print $2}'`
        if [ -n "${TMP_PARAMS}" ]; then
            tempPattern=`echo ${TMP_PARAMS} | awk -F "@" '{print $1}'`
            if echo "${tempPattern} | grep -q "^[u|U]=.*$"; then
                userName=`echo ${tempPattern} | awk -F "=" '{print $2}'`
            elif echo "${tempPattern} | grep -q "^[p|P]=.*$"; then
                password=`echo ${tempPattern} | awk -F "=" '{print $2}'`
            fi

            tempPattern=`echo ${TMP_PARAMS} | awk -F "@" '{print $2}'`
            if echo "${tempPattern} | grep -q "^[u|U]=.*$"; then
                userName=`echo ${tempPattern} | awk -F "=" '{print $2}'`
            elif echo "${tempPattern} | grep -q "^[p|P]=.*$"; then
                password=`echo ${tempPattern} | awk -F "=" '{print $2}'`
            fi

            FT_USER_NAME=${userName}
            FT_USER_PASSWORD=${password}
        fi
    fi

    return 0
}

###########################################################
function g_DownLoad_Files()
{
    if [ $# -lt 3 ];then
        g_LOG_Error "lack of parameter parameters must be 3"
        return 1
    fi

    local serverUrl=$1
    local targetPath=$2
    local fileType=$3
    local returnValue
    local ftpurl
    local httpurl
    local cur_trytimes=1


    parseUrl $serverUrl
    if [ $? -ne 0 ]; then
        g_LOG_Error "Parse url failed"
        return 1
    fi

    targetPath="`echo $targetPath | sed "s/[\/]\{2,\}/\//g" | sed "s/\/$//g"`"
    if [ -z $targetPath ]; then
        g_LOG_Error "Download target path is empty"
        return 1
    fi
    if echo $FT_TRAN_PROTOCOL | grep -q "^[cC][dD]$"; then
        ft_mountCdromDir $targetPath
        returnValue=$?
        g_LOG_Info "Mount cdrom to $targetPath, result is $returnValue"
    elif echo $FT_TRAN_PROTOCOL | grep -q "^[fF][iI][lL][eE]$"; then
        copyfiles $FT_SERVER_SOURCE_PATH $targetPath
        returnValue=$?
        g_LOG_Info "Copy files from $FT_SERVER_SOURCE_PATH to $targetPath, result is $returnValue"
    else
        test_server_connection $FT_SERVER_IP
        if [ $? -ne 0 ]; then
            g_LOG_Error "Connect server failed"
            return 1
        else
            if echo $FT_TRAN_PROTOCOL | grep -q  "^[nN][fF][sS]$"; then
                ft_mountNfsDir $FT_SERVER_IP $FT_SERVER_SOURCE_PATH $targetPath
                returnValue=$?
            elif echo $FT_TRAN_PROTOCOL | grep -q "^[cC][iI][fF][sS]$"; then
                ft_mountCifsDir $FT_SERVER_IP $FT_SERVER_SOURCE_PATH $targetPath $FT_USER_NAME $FT_USER_PASSWORD
                returnValue=$?
            elif echo $FT_TRAN_PROTOCOL | grep -q "^[fF][tT][pP]$"; then
                ftpurl=$(combineUrl "ftp")
                if [ -z "$ftpurl" ]; then
                    g_LOG_Error "ftp server url is not exist"
                    return 1
                fi
                if echo "$ftpurl" | grep -q "@"; then
                    g_LOG_Notice "use non-anonymous account access"
                else
                    g_LOG_Notice "use anonymous account access"
                fi
                while true;
                do
                    ft_downloadFile $ftpurl $targetPath $fileType
                    returnValue=$?
                    g_LOG_Debug "ftp donwload returnValue=$returnValue, cur_trytimes=$cur_trytimes"
                    if [ "$returnValue" -ne 0 ];then
                        g_LOG_Warn "Load OS failure, try again."
                        ((cur_trytimes++))
                        if [ "$cur_trytimes" -gt 3 ];then
                            g_LOG_Info "Try 3 times on load OS package failure."
                            break
                        fi
                        rm -rf ${targetPath}/* >>$OTHER_TTY 2>&1
                    else
                        break
                    fi
                done
            elif echo $FT_TRAN_PROTOCOL | grep -q "^[tT][fF][tT][pP]$"; then
                tftp_download $FT_SERVER_IP $FT_SERVER_PORT $FT_SERVER_SOURCE_PATH $targetPath/$FT_FILE_LIST
                returnValue=$?
                g_LOG_Info "tftp download returnValue=$returnValue"
           fi
        fi
    fi #end if
    return $returnValue
}
###########################################################
function combineUrl()
{
    local protocol=$1
    local serverUrl=""
    local sourceDir="`echo $FT_SERVER_SOURCE_PATH | sed "s/^[\/]\{0,\}/\//g" | sed "s/\/$//g"`"
    if [ -z "$protocol" ];then
        return 1
    else
        serverUrl="$protocol://"
        if [ -n "$FT_USER_NAME" -a -n "$FT_USER_PASSWORD" ];then
            serverUrl="$serverUrl$FT_USER_NAME:$FT_USER_PASSWORD@$FT_SERVER_IP"
        else
            serverUrl="$serverUrl$FT_SERVER_IP"
        fi
        if [ -n "$FT_SERVER_PORT" ];then
            serverUrl="$serverUrl:$FT_SERVER_PORT$sourceDir"
        else
            serverUrl="$serverUrl$sourceDir"
        fi

        echo "$serverUrl"
        return 0
    fi
}
###########################################################
function test_server_connection()
{
    local serverIp=$1
    local try_time=10
    local n=1
    if [ -z "${serverIp}" ]; then
       g_LOG_Error "server ip is null "
       return 1
    fi
    while [ 1 -eq 1 ]
    do
        ${FT_FPING} -c 1 ${serverIp}
        returnvalue=$?
        if [ ${returnvalue} -eq 0 ]; then
            return ${returnvalue}
        else
            if [ $n -eq ${try_time} ]; then
                g_LOG_Error "can not connect to server serverIp is ${serverIp}"
                return 1
            fi
            sleep 1
            ((n++))
        fi
    done
}
#################################################################
function copyfiles()
{
    if [ $# -lt 1 ];then
        g_LOG_Error "lack of parameter"
        return 1
    fi
    local sourceFile=$1
    local targetFile=$2
    local returnValue
    if [ -z "${targetFile}" ]; then
        targetFile="."
    fi

    if [ ! -e "${targetFile}" ]; then
        mkdir -p ${targetFile}
        if [ $? -ne 0 ]; then
            g_LOG_Error "mkdir ${targetFile} failed"
            return 1
        fi
    fi

    #if sourceFile is a dir
    if [ -d ${sourceFile} ]; then
	cp -dpR ${sourceFile}/* ${targetFile} >>tmp$$.log 2>&1
	returnValue=$?
    #if sourceFile is a file
    elif [ -f ${sourceFile} ]; then
	cp -dp ${sourceFile} ${targetFile} >>tmp$$.log 2>&1
        returnValue=$?
    else
	g_LOG_Error "${sourceFile} is not exist, please check CDROM or PXE Server."
	return 1
    fi
    g_LOG_Info "`cat tmp$$.log`"
    rm -rf tmp$$.log
    return ${returnValue}
}
#######################################################
function g_Upload_Files()
{
    local serverurl
    local protocol
    local localpath
    local fileType
    localpath=$1
    fileType=$2
    serverurl=$3
    parseUrl ${serverurl}
    if [ $? -ne 0 ]; then
        g_LOG_Error "parse url failed"
        return 1
    fi

    local tmpPath="/opt/tmpnfs"
    if echo ${FT_TRAN_PROTOCOL} | grep -q "^[fF][iI][lL][eE]$"; then
	copyfiles ${localpath} ${FT_SERVER_SOURCE_PATH}
    else
        test_server_connection ${FT_SERVER_IP}
	if [ $? -ne 0 ]; then
	    g_LOG_Error "Connect server failed"
	    return 1
	else
	    if echo ${FT_TRAN_PROTOCOL} | grep -q "^[nN][fF][sS]$"; then
		ft_mountNfsDir ${FT_SERVER_IP} ${FT_SERVER_SOURCE_PATH} ${tmpPath}
		copyfiles ${localpath} ${tmpPath}
		if [ -n "`mount | grep ${tmpPath}`" ];then
			umount ${tmpPath}
		fi
	    fi
	fi
    fi
}

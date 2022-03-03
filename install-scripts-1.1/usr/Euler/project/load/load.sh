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

source $LOCAL_SCRIPT_PATH/load/filetransfer.sh

LOCAL_CD_CFG_PATH="all"
MODPROBE="`which modprobe`"
MKFS_EXT3="`which mkfs.ext3`"
MOUNT="`which mount`"
######################################################
#function g_LOAD_CONFIG
#input none
#dataAccess $CFG_SERVER_URL $LOCAL_CONFIG_PATH
#           LOCAL_TEMPCFG_PATH
######################################################
function g_LOAD_CONFIG
{
    local returnValue
    g_LOG_Info "begin load config file"
    if [ -n "$CFG_SERVER_URL" -a -n "$LOCAL_CONFIG_PATH" ]; then
       g_DownLoad_Files $CFG_SERVER_URL $LOCAL_CONFIG_PATH 1
       returnValue=$?
    else
       g_LOG_Error "cfg_server_url or local config path is not exist"
       return 1
    fi
    if [ ${returnValue} -eq 0 ]; then
        local tran_protocol=`echo $CFG_SERVER_URL | awk -F ":" '{print $1}'`
        local config_url="file://$LOCAL_CONFIG_PATH"
        if ! echo $tran_protocol | grep -q -E "^[nN][fF][sS]$|^[cC][iI][fF][sS]$|^[tT][fF][tT][pP]$"; then
            if echo $tran_protocol | grep -q -E "^[fF][tT][pP]$|^[hH][tT][tT][pP]$"; then
                if [ "x$FT_SERVER_SOURCE_PATH" != "x" ]; then
                    config_url="$config_url/$FT_SERVER_SOURCE_PATH"
                else
                    config_url="$config_url/$LOCAL_CD_CFG_PATH"
                fi
            else
                config_url="$config_url/$LOCAL_CD_CFG_PATH"
            fi
        fi
        g_LOG_Debug "config_url is $config_url"
        g_DownLoad_Files $config_url $LOCAL_TEMP_PATH 1
        returnValue=$?
        if [ -n "`cat /proc/mounts | grep "$LOCAL_CONFIG_PATH"`" ];then
            umount $LOCAL_CONFIG_PATH >>$OTHER_TTY 2>&1
        fi
    else
        g_LOG_Error "download cfg file from server error"
    fi
    g_LOG_Info "end load config file"
    return ${returnValue}
}
######################################################
#function g_LOAD_Os
#description load os repo to targetdir
#dataAccess $REPO_SERVER_URL $LOCAL_SOURCE_PATH
######################################################
function g_Load_Os
{
    g_LOG_Info "Begin load OS tar package"
    local returnValue="0"
    local tmpdir="/media"

    if [ ! -d "${tmpdir}" ];then
        mkdir -p ${tmpdir}
        if [ $? -ne 0 ];then
            g_LOG_Error "mkdir ${tmpdir} failed"
            return 1
        fi
    fi

    if [ -n "${REPO_SERVER_URL}" -a -n "${LOCAL_SOURCE_PATH}" ];then
        INIT_RAMDISK
        if [ $? -ne 0 ];then
            g_LOG_Error "init load os storage error"
	    return 1
	fi
        local tran_protocol=`echo ${REPO_SERVER_URL} | awk -F ":" '{print $1}'`
    
	if echo ${tran_protocol} | grep -q -E "^[cC][dD]$|^[nN][fF][sS]$|^[cC][iI][fF][sS]$" ;then
            g_DownLoad_Files ${REPO_SERVER_URL} "${tmpdir}" 1
            if [ $? -eq 0 ]; then
                local localUrl="file://$tmpdir/repo"
                g_DownLoad_Files $localUrl $LOCAL_SOURCE_PATH/repo 1
                returnValue=$?
     	        umount $tmpdir >>$OTHER_TTY 2>&1
            else
     	        returnValue=1
   	    fi
        elif echo $tran_protocol | grep -q "^[bB][tT]$";then
            g_DownLoad_Files $REPO_SERVER_URL $LOCAL_SOURCE_PATH 0
            returnValue=$?
        else
            g_DownLoad_Files $REPO_SERVER_URL $LOCAL_SOURCE_PATH 1
            returnValue=$?
        fi

        if echo $tran_protocol | grep -q -E "^[fF][tT][pP]$|^[hH][tT][tT][pP]$"; then 
   	     if [ "x$FT_SERVER_SOURCE_PATH" != "x" ]; then
                 LOCAL_SOURCE_PATH="$LOCAL_SOURCE_PATH/$FT_SERVER_SOURCE_PATH/repo"
             else
		 LOCAL_SOURCE_PATH="$LOCAL_SOURCE_PATH/repo"
             fi
        else
           LOCAL_SOURCE_PATH="$LOCAL_SOURCE_PATH/repo"		
        fi
    else
	    returnValue=1
    fi
    g_LOG_Debug "local_source_path is:$LOCAL_SOURCE_PATH"
    g_LOG_Info "end load os tar package"
    return $returnValue
}
##########################################################
#description init a ramdisk and mount 2 $LOCAL_SOURCE_PATH
##########################################################
function INIT_RAMDISK()
{
    $MODPROBE brd rd_size=3072000 rd_nr=1 max_part=1 >>$OTHER_TTY 2>&1
    if [ -b /dev/ram0 ];then
        $MKFS_EXT3 /dev/ram0 >>$OTHER_TTY 2>&1
	mkdir -p $LOCAL_SOURCE_PATH
	if [ $? -ne 0 ]; then
	    g_LOG_Error "mkdir $LOCAL_SOURCE_PATH failed"
	    return 1
	fi
	
	$MOUNT -t ext3 /dev/ram0 $LOCAL_SOURCE_PATH >>$OTHER_TTY 2>&1
	if [ $? -ne 0 ]; then
	    g_LOG_Error "mount /dev/ram0 to $LOCAL_SOURCE_PATH error"
            return 1
	fi
    else
	g_LOG_Error "insmod brd failed,create ramdisk error"
	return 1
    fi
    return 0
}

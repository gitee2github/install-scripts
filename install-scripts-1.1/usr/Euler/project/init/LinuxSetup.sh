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
* Author: zhangqiumiao
* Create: 2022-02-28
* Description: the main installation program
!

#!/bin/bash

LOCAL_SCRIPT_PATH=/usr/Euler/project
LOCAL_LOG_PATH=/var/log

source ${LOCAL_SCRIPT_PATH}/util/GlobalVariables.sh
source ${LOCAL_SCRIPT_PATH}/util/CommonFunction

############ module scripts ############
INIT_SETUPOS_SCRIPT=${LOCAL_SCRIPT_PATH}/install/setupOS.sh

INIT_MODULES=${LOCAL_SCRIPT_PATH}/init/InitModules.sh

INIT_UPLOAD_SCRIPT=${LOCAL_SCRIPT_PATH}/load/fileupload.sh


######################### hook scripts path #########################
CUSTOM_INSTALL_HOOK_PATH=${LOCAL_HOOK_PATH}/custom_install_hook
ENV_CHECK_HOOK_PATH=${LOCAL_HOOK_PATH}/env_check_hook
SET_INSTALL_IP_HOOK_PATH=${LOCAL_HOOK_PATH}/set_install_ip_hook
BEFORE_PARTITION_HOOK_PATH=${LOCAL_HOOK_PATH}/before_partition_hook
DOWNLOAD_INSTALL_FILE_HOOK_PATH=${LOCAL_HOOK_PATH}/download_install_file_hook
BEFORE_SETUP_OS_HOOK_PATH=${LOCAL_HOOK_PATH}/before_setup_os_hook
INSTALL_SUCC_HOOK=${LOCAL_HOOK_PATH}/install_succ_hook
INSTALL_FAIL_HOOK=${LOCAL_HOOK_PATH}/install_fail_hook

############################################################
#    Description:    upload log to remote server
#    Parameter:      none
#    Return:         0-success, 1-failed
############################################################
function INIT_Upload_LOG()
{
    #check if log file does exist
    if [ ! -f "${LOG_FILE}" ]; then
        g_LOG_Warn "log file does not exist."
        return 1
    fi

    local filedate="`date +%Y%m%d%H%M%S`"
    local mac=`cat /sys/class/net/${NET_DEVICE}/address`
    mac=`echo ${mac} | sed 's/:/-/g'`
    local target_LogPath=${filedate}_${mac}_OSLOG
    local local_OS_LogPath=${LOCAL_DISK_PATH}/${LOCAL_LOG_PATH}/installOS/

    if [ `echo ${INSTALL_MEDIA} | egrep -i "^PXE$"` ]; then
        #create dir
        cd ${LOCAL_LOG_PATH}
        if [ -d "${target_LogPath}" ]; then
            rm -rf ${target_LogPath}
        fi
        mkdir -p ${target_LogPath}
        if [ $? -ne 0 ]; then
            g_LOG_Error "make dir ${target_LogPath} failed"
            return 1
        fi
        #recopy log file
        cp ${LOG_FILE} ${target_LogPath} >> ${OTHER_TTY} 2>&1
        if [ -f "${LOCAL_LOG_PATH}/dmesg.install" ]; then
            cp ${LOCAL_LOG_PATH}/dmesg.install ${target_LogPath} >> ${OTHER_TTY} 2>&1
        fi
        if [ -f "${OTHER_TTY}" ]; then
            cp ${OTHER_TTY} ${target_LogPath}
        fi

	#compress install log
	tar -zcf ${target_LogPath}.tar.gz ${target_LogPath} >> ${OTHER_TTY} 2>&1
	#upload
	${INIT_UPLOAD_SCRIPT} "${LOCAL_LOG_PATH}/${target_LogPath}.tar.gz" "${LOG_SERVER_URL}" ${LOG_FILE}
        if [ $? -ne 0 ]; then
            g_LOG_Warn "Upload log failed."
        fi
        rm -rf ${LOCAL_LOG_PATH}/${target_LogPath}*
    fi

    #copy LOG_FILE to disk
    if [ ! -d "${local_OS_LogPath}" ]; then
        mkdir -p ${local_OS_LogPath} >> ${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "make dir ${local_OS_LogPath} failed."
            return 1
        fi
    fi
    cp -ap ${LOG_FILE} ${local_OS_LogPath} >> ${OTHER_TTY} 2>&1
    if [ -f "${LOCAL_LOG_PATH}/dmesg.install" ]; then
        cp -ap ${LOCAL_LOG_PATH}/dmesg.install ${local_OS_LogPath} >> ${OTHER_TTY} 2>&1
    fi
    if [ -f "${OTHER_TTY}" ]; then
        cp -ap ${OTHER_TTY} ${local_OS_LogPath}
    fi
    g_LOG_Info "Copy log file to disk success"
    return 0
}

############################################################
#    Description:    capture signal(Ctrl+C, kill -9 ...)
#    Parameter:      none
#    Return:         0-success, 1-failed
############################################################
function INIT_Signal_Catcher()
{
    echo ""
}

############################################################
#    Description:    the entry of install
#    Parameter:      none
#    Return:         0-success, 1-failed
############################################################
function INIT_Setup_Main()
{
    #define local variable
    local tmp=
    local sysconfig_conf=`basename ${SYSCONFIG_CONF}`
    local cmdline=/proc/cmdline

    #initialize the drivers
    ${INIT_MODULES}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Initializing modules failed."
        return 1
    fi
    g_LOG_Notice "Initializing modules success."

    #Parse the isopackage.sdf file before initializing the environment
    SI_CMDTYPE="`INIT_Get_CmdLineParamValue 'cmdtype' ${ISOPACKAGE_CONF}`"
    g_LOG_Debug "SI_CMDTYPE is ${SI_CMDTYPE}"
    if [ -z "${SI_CMDTYPE}" ]; then
        g_LOG_Error "SI_CMDTYPE is null, please config in isopackage.sdf file."
        return 1
    fi

    #Wait for complete device initialization
    if [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
        g_LOG_Info "Waiting for device initialization."
        INIT_WaitDeviceInitial
        if [ $? -ne 0 ]; then
            g_LOG_Warn "Device initialization has some problems."
        fi
    fi
    #Parse install_mode field in cmdline to determine whether to install or start.
    #If it is start mode, skip the installation process.
    INSTALL_MODE="`INIT_Get_CmdLineParamValue 'install_mode' ${cmdline}`"
    if [ -z "${INSTALL_MODE}" -o "${INSTALL_MODE}" == "start" -o "${INSTALL_MODE}" == "install_product_only" ]; then
        g_LOG_Info "INSTALL_MODE=${INSTALL_MODE}, just booting system, do not install."
        g_LOG_Info "If you want to install, please set cmdline install_mode=install"
        exit 0
    fi

    #User defined system installation hook. Users can customize the installation process instead
    #of using the default one.
    tmp=`ls ${CUSTOM_INSTALL_HOOK_PATH}/S* 2>/dev/null | wc -l`
    if [ "${tmp}" != 0 ]; then
        g_LOG_Notice "Start custom install hook."
        INIT_Execute_Hook ${CUSTOM_INSTALL_HOOK_PATH}
        if [ $? -ne 0 ]; then
            g_LOG_Error "Execute custom install failed."
            g_LOG_Info "If you want to user default installation, remove hook shell in ${CUSTOM_INSTALL_HOOK_PATH}"
	    return 1
        fi
        g_LOG_Notice "Execute custom install hook success."
        return 0
    fi

    # wait for disk scan
    DISK_SCAN_TIMEOUT="`INIT_Get_CmdLineParamValue 'disk_scan_timeout' ${cmdline}`"
    g_LOG_Info "timeout set to ${DISK_SCAN_TIMEOUT}"
    DM_WaitScan ${DISK_SCAN_TIMEOUT}

    INIT_Execute_Hook ${ENV_CHECK_HOOK_PATH}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Execute custom check environment failed."
        return 1
    fi

    #Initial Environment
    g_LOG_Notice "Initializing environment..."
    INIT_Install_Env
    if [ $? -ne 0 ]; then
        g_LOG_Error "Initial environment failed."
        cat ${LOG_FILE} | grep -w "ERROR" | awk -F ': ' '{print $2}'
        return 1
    fi
    g_LOG_Notice "Initializing environment success."

    INIT_Execute_Hook ${BEFORE_PARTITION_HOOK_PATH} ${PARTITION_CONF}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Execute custom hook failed before partition."
        return 1
    fi

    g_LOG_Notice "Creating and formatting partitions..."
    g_DM_CreateAndFormatPartition ${FSTAB_FILE}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Create and format partitions failed."
        return 1
    fi
    g_LOG_Notice "Create and format partitions success."

    #mount partitions
    g_LOG_Notice "Mounting partitions..."
    g_DM_MountPartitionToTarget ${LOCAL_DISK_PATH} ${FSTAB_FILE}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Mount partitions failed."
        return 1
    fi
    g_LOG_Notice "Mount partitions success."

    g_LOG_Notice "Start download installation package..."
    sleep 1

    #Execute the customized download hook. Users can customize the download
    #operation and save the download data on ram0 created by the installer.
    #The path is ${LOCAL_SOURCE_PATH}.
    #When users want to customize the download, they need to download the
    #repo directory to ${LOCAL_SOURCE_PATH}. The repo directory must contain
    #OS.tar.gz and sha256 file.
    tmp=`ls ${DOWNLOAD_INSTALL_FILE_HOOK_PATH}/S* 2>/dev/null | wc -l`
    if [ "${tmp}" != 0 ]; then
        g_LOG_Notice "Start custom download hook."
        INIT_Execute_Hook ${DOWNLOAD_INSTALL_FILE_HOOK_PATH}
        if [ $? -ne 0 ]; then
            g_LOG_Error "Execute custom download failed."
            return 1
        fi
        g_LOG_Notice "Execute custom download success."
        g_LOG_Debug "ls ${LOCAL_SOURCE_PATH} `ls ${LOCAL_SOURCE_PATH}`"
    else
        #Execute the default download process
        g_LOG_Notice "Loading OS tar package..."

        #copy OS tar package
        g_Load_Os >> ${OTHER_TTY} 2>&1

        if [ $? -ne 0 ]; then
            g_LOG_Error "Load OS tar package failed."
            return 1
        fi
	g_LOG_Notice "Load OS tar package success."
    fi

    g_LOG_Notice "Download installation package success."

    #Execute the hook before decompressing the OS tar package, and users can
    #mount the user-defined partition.
    INIT_Execute_Hook ${BEFORE_SETUP_OS_HOOK_PATH} "LOCAL_UNCOMPRESS_PATH"
    if [ $? -ne 0 ]; then
        g_LOG_Error "Execute custom hook failed before setup OS."
        return 1
    fi

    #setup OS to disk
    g_LOG_Notice "Start setup OS..."
    ${INIT_SETUPOS_SCRIPT} ${ISOPACKAGE_CONF} ${INSTALL_MODE}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Setup OS failed."
        return 1
    fi

    return 0
}

#capture signal
trap "INIT_Signal_Catcher" INT TERM QUIT

#start setup OS
INIT_Setup_Main
ret=$?

if [ -f ${LOCAL_DISK_PATH}/root/.bash_history ]; then
    g_LOG_Notice "rm history file: ${LOCAL_DISK_PATH}/root/.bash_history"
    rm -rf ${LOCAL_DISK_PATH}/root/.bash_history
fi

#upload log
dmesg > ${LOCAL_LOG_PATH}/dmesg.install
chmod 640 ${LOCAL_LOG_PATH}/dmesg.install
g_LOG_Notice "Uploading log file."
INIT_Upload_LOG >/dev/null 2>&1
chmod 600 ${LOCAL_DISK_PATH}/var/log/installOS/*
chmod 700 ${LOCAL_DISK_PATH}/var/log/installOS

#change stage
if [ "${ret}" -ne 0 ]; then
    g_LOG_Error "Install OS failed."
    INIT_Execute_Hook ${INSTALL_FAIL_HOOK}
    exit 1
else
    g_LOG_Notice "Install OS success."
    INIT_Execute_Hook ${INSTALL_SUCC_HOOK}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Execute custom hook failed after install OS success."
        exit 1
    fi

    exit 0
fi

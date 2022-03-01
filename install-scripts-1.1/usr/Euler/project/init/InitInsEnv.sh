#!/bin/bash
# Description: Initial Environment


########### module variables ###########
INIT_INSTALL_IP=
INIT_INSTALL_GW=
INIT_INSTALL_NETMASK=
INIT_INSTALL_MAC=
# 1:current NET_DEVICE is appointed NIC in cmdline
INIT_NIC_ISAPPOINTED=1
INIT_UDEV_WAIT_TIMEOUT=180

###########################################################
#    Description:    print global variable when debug switch is on
#    Parameter:      none
#    Return:         0-success, 1-failed
###########################################################
function INIT_Print_Global()
{
    g_LOG_Debug "INSTALL_MODE=${INSTALL_MODE}"
    g_LOG_Debug "INSTALL_MEDIA=${INSTALL_MEDIA}"

    g_LOG_Debug "LOCAL_LOG_PATH=${LOCAL_LOG_PATH}"
    g_LOG_Debug "LOCAL_SOURCE_PATH=${LOCAL_SOURCE_PATH}"
    g_LOG_Debug "LOCAL_CONFIG_PATH=${LOCAL_CONFIG_PATH}"
    g_LOG_Debug "LOCAL_SCRIPT_PATH=${LOCAL_SCRIPT_PATH}"
    g_LOG_Debug "LOCAL_DISK_PATH=${LOCAL_DISK_PATH}"
    g_LOG_Debug "LOCAL_TEMPCFG_PATH=${LOCAL_TEMPCFG_PATH}"
    g_LOG_Debug "LOCAL_HOOK_PATH=${LOCAL_HOOK_PATH}"

    g_LOG_Debug "SERVER_SOURCE_TYPE=${SERVER_SOURCE_TYPE}"
    g_LOG_Debug "SERVER_SOURCE_PATH=${SERVER_SOURCE_PATH}"
    g_LOG_Debug "SERVER_LOG_TYPE=${SERVER_LOG_TYPE}"
    g_LOG_Debug "SERVER_LOG_PATH=${SERVER_LOG_PATH}"

    g_LOG_Debug "NET_DEVICE=${NET_DEVICE}"
    g_LOG_Debug "NODE_NAME=${NODE_NAME}"

    g_LOG_Debug "PARTITION_CONF=${PARTITION_CONF}"
    g_LOG_Debug "FSTAB_FILE=${FSTAB_FILE}"
    g_LOG_Debug "SYSCONFIG_CONF=${SYSCONFIG_CONF}"
}

###########################################################
#    Description:    initial install environment
#    Parameter:      none
#    Return:         0-success, 1-failed
###########################################################
function INIT_Install_Config()
{
    #Format conversion of partition config file, which is used for partition during installation
    g_DM_ResolvePartitionConfigFile ${PARTITION_CONF}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Generate partition detail config error."
        return 1
    fi
}

###########################################################
#    Description:    get a available net card to set ip
#    Parameter:      none
#    Return:         0-success, 1-failed
###########################################################
function INIT_Set_NetByAvlbCard()
{
    local netNames=
    local ret=1

    g_LOG_Info "Finding avaliable netdevice to set DHCP..."

    INIT_INSTALL_IP="DHCP"

    if [ "x${SI_CMDTYPE}" == "xsl-cmd" ]; then
        netNames="`ifconfig -a | grep 'HWaddr' | awk '{print $1}'`"
    elif [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
        netNames="`ifconfig -a | grep 'flags=' | awk -F ":" '{print $1}'`"
    else
        g_LOG_Error "SI_CMDTYPE is wrong, please check isopackage.sdf."
        return 1
    fi

    for netName in $(echo $netNames);
    do
        NET_DEVICE=${netName}
        INIT_Set_IP
        if [ $? -ne 0 ]; then
            g_LOG_Warn "Set [${NET_DEVICE}]'s ip failure."
            continue
        fi
        g_LOG_Info "Set [${NET_DEVICE}]'s ip success."
        #means set ip success
        ret=0
        break
    done
    g_LOG_Info "Get available netdevice success"

    return $ret
}

###############################################################
#    Description:    get net device name
#    Parameter:      none
#    Return:         0-success, 1-failed
###############################################################
function INIT_Get_NetDevice()
{
    local eth=
    local mac=
    local eths=
    local ret=

    mac=${INIT_INSTALL_MAC}
    if [ -z "${mac}" ]; then
        echo ""
        return 1
    fi

    if [ "x${SI_CMDTYPE}" == "xsl-cmd" ]; then
	    eth="`ifconfig -a | grep -i ${mac} | awk '{print $1}'`"
    elif [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
        eths="`ifconfig -a | grep 'flags=' | awk -F ":" '{print $1}' | sort`"
        for netname in $(echo $eths);
        do
            ret="`ifconfig ${netname} | grep -i ${mac}`"
            if [ ! -z "${ret}" ]; then
                eth=${netname}
                break
            fi
        done
    else
        g_LOG_Error "SI_CMDTYPE is wrong, please check isopackage.sdf."
        return 1
    fi

    if [ ! -z "${eth}" ]; then
        echo "${eth}"
        return 0
    fi

    echo ""

    return 1
}

#########################################################
#    Description:    check network
#    Parameter:      param1: server ip, which is used to ping
#    Return:         0-success. 1-failed
#########################################################
function INIT_Check_Net()
{
    local serverIP=$1
    local result
    local n
    local x

    n=1
    while true;
    do
        result="`ping -c 1 ${serverIP} 2>/dev/null`"
        if [ ! -z "`echo ${result} | grep "time="`" ]; then
            g_LOG_Notice "Connect to server OK."
            break
        fi

        g_LOG_Info "${result}"
        g_LOG_Info "ping server is unreachable. Try again..."
        ((x=15-n))
        echo -e "${x} \c "
        sleep 1
        ((n++))
        if [ "${n}" -gt 15 ]; then
            g_LOG_Error "Connect to server failed."
            return 1
        fi
    done

    return 0
}

##############################################################
#    Description:    check install net
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Check_InstallNet()
{
    g_LOG_Info "Checking [${NET_DEVICE}] connect to server..."
    #check if can connect to source server
    if [ "${SERVER_SOURCE_TYPE}" != "CD" ]; then
        INIT_Check_Net "${SERVER_SOURCE_IP}"
        if [ $? -ne 0 ]; then
            g_LOG_Warn "[${NET_DEVICE}] connect to source server [${SERVER_SOURCE_IP}] failed."
            return 1
        fi
    fi

    #check if can connect to log server
    if [ "${SERVER_LOG_TYPE}" != "file" ]; then
        INIT_Check_Net "${SERVER_LOG_IP}"
        if [ $? -ne 0 ]; then
            g_LOG_Warn "[${NET_DEVICE}] connect to log server [${SERVER_LOG_IP}] failed."
            return 0
        fi
    fi
    g_LOG_Info "Checking [${NET_DEVICE}]'s Net success."
    return 0
}

##############################################################
#    Description:    INIT_Get_DHCPIP
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Get_DHCPIP()
{
    local tDhclient="`which dhclient`"
    local cur_trytimes=1
    local flag=1
    local ret=
    local runningCount=

    while true;
    do
        if [ -f "${tDhclient}" ]; then
            g_LOG_Info "dhcp cmd tDhclient=${tDhclient}"
            runningCount=`ps -ef | grep "${tDhclient}" | grep -v "grep" | wc -l`
            if [ ${runningCount} -ne 0 ]; then
                g_LOG_Info "There is DHCP client process, killall at first"
                killall -w ${tDhclient} 2>/dev/null
            fi
	    ${tDhclient} --timeout 60 ${NET_DEVICE} -v >> ${OTHER_TTY} 2>&1
        else
            g_LOG_Error "no dhcp cmd for get dhcp ip."
            return 1
        fi

        sleep 1

        if [ "x${SI_CMDTYPE}" == "xsl-cmd" ]; then
            ret="`ifconfig ${NET_DEVICE} | grep "inet addr:"`"
        elif [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
            ret="`ifconfig ${NET_DEVICE} | grep "inet "`"
        else
            g_LOG_Error "SI_CMDTYPE is wrong, please check isopackage.sdf."
            return 1
        fi

        if [ -z "${ret}" ]; then
            if [ "${INIT_NIC_ISAPPOINTED}" == "0" ]; then
                break
            fi
        else
            flag=0
            break
        fi

        ((cur_trytimes++))
        if [ "${cur_trytimes}" -gt 3 ]; then
            g_LOG_Info "Try 3 times on dhclient ${NET_DEVICE} failure."
            break
        fi
    done

    if [ "${flag}" -ne 0 ]; then
        echo "dhclient ${NET_DEVICE} failure" >> ${OTHER_TTY} 2>&1
        g_LOG_Error "dhclient ${NET_DEVICE} failure"
        return 1
    fi

    return 0
}

##############################################################
#    Description:    set install IP
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Set_IP()
{
    g_LOG_Info "Setting [${NET_DEVICE}]'s IP..."
    echo "Setting [${NET_DEVICE}]'s IP..."
    #up net card
    ifconfig ${NET_DEVICE} up
    if [ $? -ne 0 ]; then
        g_LOG_Warn "ifconfig [${NET_DEVICE}] up failure"
        return 1
    fi
    sleep 2

    if [ `echo "${INIT_INSTALL_IP}" | egrep "^[Dd][Hh][Cc][Pp]$"` ]; then
        INIT_Get_DHCPIP
        if [ $? -ne 0 ]; then
            g_LOG_Warn "Dhclient [${NET_DEVICE}] failure"
            ifconfig ${NET_DEVICE} down >> ${OTHER_TTY} 2>&1
            return 1
        fi
    elif [ ! -z "${INIT_INSTALL_IP}" ] && [ ! -z "${INIT_INSTALL_NETMASK}" ]; then
	    #set IP
	    ifconfig ${NET_DEVICE} "${INIT_INSTALL_IP}" netmask "${INIT_INSTALL_NETMASK}" >> ${OTHER_TTY} 2>&1
	    if [ $? -ne 0 ]; then
		    g_LOG_Warn "Set [${NET_DEVICE}]'s ip ${INIT_INSTALL_IP} failure."
		    ifconfig ${NET_DEVICE} down >> ${OTHER_TTY} 2>&1
		    return 1
	    fi

        #add gw
        if [ ! -z "${INIT_INSTALL_GW}" ]; then
            route add default gw "${INIT_INSTALL_GW}" >> ${OTHER_TTY} 2>&1
        fi
    else
        g_LOG_Warn "Set [${NET_DEVICE}]'s ip failure, ip or netmask is null."
        return 1
    fi

    g_LOG_Info "Set [${NET_DEVICE}]'s IP success."
    echo "Set [${NET_DEVICE}]'s IP success."
    #check network
    echo "Checking [${NET_DEVICE}] connect to server..."
    INIT_Check_InstallNet
    if [ $? -ne 0 ]; then
        echo "Check [${NET_DEVICE}] connect to server failure."
        ifconfig ${NET_DEVICE} down >> ${OTHER_TTY} 2>&1
        return 1
    fi
    echo "Check [${NET_DEVICE}] connect to server success."
    return 0
}

##############################################################
#    Description:    set install net
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Set_InstallNet()
{
    local flag=1
    local tmpNetDevice=

    if [ -n "${NET_DEVICE}" ]; then
        #set install ip
        INIT_Set_IP
        flag=$?
        if [ "${flag}" -ne 0 ]; then
            g_LOG_Warn "Set [${NET_DEVICE}]'s ip failure."
        fi
    fi

    if [ "${flag}" -ne 0 ] && [ ! -z "${INIT_INSTALL_MAC}" ]; then
        #Get net device name
        g_LOG_Info "install mac is ${INIT_INSTALL_MAC}"
        tmpNetDevice=${NET_DEVICE}
        NET_DEVICE="`INIT_Get_NetDevice`"

        if [ $? -ne 0 ] || [ -z "${NET_DEVICE}" ] || [ "${NET_DEVICE}" == "${tmpNetDevice}" ]; then
            flag=1
            g_LOG_Warn "Get netdevice failure."
        else
            #set install IP
            INIT_Set_IP
            flag=$?
            if [ "${flag}" -ne 0 ]; then
                g_LOG_Warn "Set [${NET_DEVICE}]'s ip failure."
            fi
        fi
    fi

    if [ "${flag}" -ne 0 ]; then
        INIT_NIC_ISAPPOINTED=0
        INIT_Set_NetByAvlbCard
        return $?
    fi

    return 0
}

##############################################################
#    Description:    initial install environment
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Install_Network()
{
    #set install environment IP
    if [ ! `echo "${INSTALL_MEDIA}" | grep "[Cc][Dd]"` ]; then
        g_LOG_Notice "Starting set install IP..."
        INIT_Set_InstallNet
        if [ $? -ne 0 ]; then
            g_LOG_Error "Set install IP error."
            INIT_Print_Global
            return 1
        fi
        g_LOG_Notice "Set install IP success."
    fi
    return 0
}

##############################################################
#    Description:    check tools
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Check_Tools()
{
    #partition related
    local tSfdisk="`which sfdisk`"
    local tMkswap="`which mkswap`"
    local tMke2fs="`which mke2fs`"
    local tParted="`which parted`"
    local tMkdosfs="`which mkdosfs`"
    local tPartprobe="`which partprobe`"

    #file transport related
    local tWget="`which wget`"
    local tMount="`which mount`"
    local tPing="`which ping`"
    local tIfconfig="`which ifconfig`"

    if [ -z "${tSfdisk}" ]; then
        g_LOG_Error "Command sfdisk doesn't exist."
        return 1
    fi

    if [ -z "${tMkswap}" ];then
        g_LOG_Error "Command mkswap doesn't exist."
        return 1
    fi

    if [ -z "${tMke2fs}" ];then
        g_LOG_Error "Command mke2fs doesn't exist."
        return 1
    fi

    if [ -z "${tParted}" ]; then
        g_LOG_Error "Command parted doesn't exist."
        return 1
    fi

    if [ -z "${tMkdosfs}" ]; then
        g_LOG_Error "Command mkdosfs doesn't exist."
        return 1
    fi

    if [ -z "${tPartprobe}" ]; then
        g_LOG_Error "Command partprobe doesn't exist."
        return 1
    fi

    if [ -z "${tWget}" ]; then
        g_LOG_Error "Command wget doesn't exist."
        return 1
    fi

    if [ -z "${tMount}" ]; then
        g_LOG_Error "Command mount doesn't exist."
        return 1
    fi

    if [ -z "${tPing}" ]; then
        g_LOG_Error "Command ping doesn't exist."
        return 1
    fi

    if [ -z "${tIfconfig}" ]; then
        g_LOG_Error "Command ifconfig doesn't exist."
        return 1
    fi

    return 0
}

##############################################################
#    Description:    check install environment
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Check_InsEnv()
{
    #check global variables
    if [ ! `echo ${INSTALL_MEDIA} | egrep "^[Cc][Dd]$|^[Pp][Xx][Ee]$"` ]; then
        g_LOG_Error "install media is not valid."
        return 1
    fi

    if [ -z "${SERVER_LOG_TYPE}" ] || [ -z "${SERVER_LOG_IP}" ]; then
        g_LOG_Warn "log url is not valid format."
    fi

    #check install tools
    INIT_Check_Tools
    if [ $? -ne 0 ]; then
        g_LOG_Error "check tools error"
        return 1
    fi

    return 0
}

##############################################################
#    Description:    make install direction
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Make_InsDir()
{
    #make disk mount point
    if [ -d "${LOCAL_DISK_PATH}" ]; then
        rm -rf ${LOCAL_DISK_PATH}
    fi
    mkdir -p ${LOCAL_DISK_PATH}
    if [ $? -ne 0 ]; then
        g_LOG_Error "mkdir ${LOCAL_DISK_PATH} error."
        return 1
    fi

    #make OS tar package download dir
    if [ -d "${LOCAL_SOURCE_PATH}" ]; then
        rm -rf ${LOCAL_SOURCE_PATH}
    fi
    mkdir -p ${LOCAL_SOURCE_PATH}
    if [ $? -ne 0 ];then
        g_LOG_Error "mkdir ${LOCAL_SOURCE_PATH} error."
        return 1
    fi

    #make temp config file dir
    if [ -d "${LOCAL_TEMPCFG_PATH}" ]; then
        rm -rf ${LOCAL_TEMPCFG_PATH}
    fi
    mkdir -p ${LOCAL_TEMPCFG_PATH}
    if [ $? -ne 0 ];then
        g_LOG_Error "mkdir ${LOCAL_TEMPCFG_PATH} error."
        return 1
    fi

    return 0
}

##############################################################
#    Description:    parse cmdline(/proc/cmdline) and evaluate global variable
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Parse_Cmdline()
{
    local sourcePathParam
    local configPathParam
    local logPathParam
    local tmpPath
    local cmdline=/proc/cmdline

    #parse install media, "CD" or "PXE"
    INSTALL_MEDIA="`INIT_Get_CmdLineParamValue 'install_media' ${cmdline}`"

    #parse log file path
    logPathParam="`INIT_Get_CmdLineParamValue 'install_log' ${cmdline}`"
    if [ -z "${logPathParam}" ] || [ `echo ${logPathParam} | egrep "^[Cc][Dd]"` ]; then
        #if logPathParam is null, set default value
        SERVER_LOG_TYPE="file"
        SERVER_LOG_IP="localhost"
        SERVER_LOG_PATH="${LOCAL_TARGET_PATH}/var/log/installOS"
        LOG_SERVER_URL=${SERVER_LOG_TYPE}://${SERVER_LOG_PATH}
    else
        SERVER_LOG_TYPE="`echo ${logPathParam} | awk -F ':' '{print $1}'`"
        tmpPath="`echo ${logPathParam} | awk -F '://' '{print $2}' | awk -F'?' '{print $1}'`"
        SERVER_LOG_IP="`echo ${tmpPath} | awk -F '/' '{print $1}' | awk -F':' '{print $1}'`"
        SERVER_LOG_PATH=`echo ${tmpPath#*/}`
        LOG_SERVER_URL=${logPathParam}
    fi

    #parse install img path
    sourcePathParam="`INIT_Get_CmdLineParamValue 'install_repo' ${cmdline}`"
    if [ ! -z "${sourcePathParam}" ]; then
        if [ `echo ${sourcePathParam} | egrep "^[Cc][Dd]"` ]; then
            #if sourcePathParam is null, set default value
            SERVER_SOURCE_TYPE="CD"
            SERVER_SOURCE_IP="localhost"
            SERVER_SOURCE_PATH="euler/x86_64/ospkg"
            REPO_SERVER_URL=${SERVER_SOURCE_TYPE}://${SERVER_SOURCE_PATH}
        else
            SERVER_SOURCE_TYPE="`echo ${sourcePathParam} | awk -F ':' '{print $1}'`"
            tmpPath="`echo ${sourcePathParam} | awk -F '://' '{print $2}' | awk -F'?' '{print $1}'`"
            SERVER_SOURCE_IP="`echo ${tmpPath} | awk -F '/' '{print $1}' | awk -F':' '{print $1}'`"
            SERVER_SOURCE_PATH=`echo ${tmpPath#*/}`
            REPO_SERVER_URL=${sourcePathParam}
        fi
    fi

    #parse install net config
    local netcfg="`INIT_Get_CmdLineParamValue 'net_cfg' ${cmdline}`"
    if [ ! -z "${netcfg}" ]; then
        NET_DEVICE="`echo ${netcfg} | awk -F ',' '{print $1}'`"
        INIT_INSTALL_MAC="`echo ${netcfg} | awk -F ',' '{print $2}'`"
        INIT_INSTALL_IP="`echo ${netcfg} | awk -F ',' '{print $3}'`"
        INIT_INSTALL_NETMASK="`echo ${netcfg} | awk -F ',' '{print $4}'`"
        INIT_INSTALL_GW="`echo ${netcfg} | awk -F ',' '{print $5}'`"
    fi

    #parse partition alignment type, "cyl" or "min" or "opt"
    PARTITION_ALIGNMENT="`INIT_Get_CmdLineParamValue 'part_align' ${cmdline}`"
    if [ -z "$(echo ${PARTITION_ALIGNMENT} | grep -wE "cyl|cylinder|min|minimal|opt|optimal")" ]; then
        PARTITION_ALIGNMENT=""
    fi

    return 0
}

##############################################################
#    Description:    initial install environment
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_Install_Var()
{
    #parse cmdline
    g_LOG_Info "Start parsing cmdline..."
    INIT_Parse_Cmdline
    if [ $? -ne 0 ]; then
        g_LOG_Error "Parsing cmdline error."
        return 1
    fi

    #make install directory
    g_LOG_Info "Start making install directory..."
    INIT_Make_InsDir
    if [ $? -ne 0 ]; then
        g_LOG_Error "Making install directory error."
        return 1
    fi

    #check install environment
    g_LOG_Info "Start checking install environment..."
    INIT_Check_InsEnv
    if [ $? -ne 0 ]; then
        g_LOG_Error "Checking install environment error."
        return 1
    fi
}

function INIT_Install_Env()
{
    local num=

    INIT_Install_Var
    if [ $? -ne 0 ]; then
        g_LOG_Error "Initial variable error."
        INIT_Print_Global
        return 1
    fi

    #Set the pre installation network hook. The user can customize
    #the network configuration. In this case, the installation is
    #not required to cinfigure the network.
    num=`ls ${SET_INSTALL_IP_HOOK_PATH}/S* 2>/dev/null | wc -l`
    if [ "${num}" != 0 ]; then
        g_LOG_Notice "Start setting install network hook."
        INIT_Execute_Hook ${SET_INSTALL_IP_HOOK_PATH}
        if [ $? -ne 0 ]; then
            g_LOG_Error "Execute set install network failed."
            return 1
        fi
        g_LOG_Notice "Start set install network success."
    else
        if [ -z "${SERVER_SOURCE_TYPE}" ] || [ -z "${SERVER_SOURCE_IP}" ]; then
            g_LOG_Error "source url is null."
            return 1
        fi
        INIT_Install_Network
        if [ $? -ne 0 ]; then
            g_LOG_Error "Initial network error."
            INIT_Print_Global
            return 1
        fi
    fi

    #Check whether the boot mode is UEFI or legacy
    if [ -d /sys/firmware/efi ]; then
        g_LOG_Info "UEFI boot, set EFI_FLAG=1"
        EFI_FLAG=1
    fi

    INIT_Install_Config
    if [ $? -ne 0 ]; then
        g_LOG_Error "Generate config file error."
        INIT_Print_Global
        return 1
    fi

    INIT_Print_Global

    return 0
}

##############################################################
#    Description:    wait for complete device initialization
#    Parameter:      none
#    Return:         0-success, 1-failed
##############################################################
function INIT_WaitDeviceInitial()
{
    local install_product=
    install_product="`cat /proc/cmdline | grep -w "product=mbsc"`"

    systemctl status systemd-udevd.service >> ${OTHER_TTY} 2>&1
    if [ $? -ne 0 ]; then
        g_LOG_Info "Start udev service again."
	systemctl start systemd-udevd.service >> ${OTHER_TTY} 2>&1
	if [ $? -ne 0 ]; then
            if [ -z "${install_product}" ]; then
                g_LOG_Error "Start udev service failed."
                return 1
            else
                g_LOG_Info "install product is mbsc, don't need Systemctl Start udevd service"
            fi
        fi
    fi

    udevadm trigger --type=subsystems --action=add >> ${OTHER_TTY} 2>&1
    udevadm trigger --type=devices --action=add >> ${OTHER_TTY} 2>&1
    sleep 1
    udevadm settle --timeout=${INIT_UDEV_WAIT_TIMEOUT} >> ${OTHER_TTY} 2>&1

    return 0
}

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
* Description: the main installation program
!

# package list sdf file
SI_OS_PACKAGE_SDF="$1"

#install mode
SI_INSTALL_MODE="$2"

#kernel version
SI_VERSION=''
export SI_VERSION

#add local variable
LOCAL_SI_VERSION=''
export LOCAL_SI_VERSION

SI_OSTARNAME=''
export SI_OSTARNAME

#vmlinuz name
SI_VMLINUZ=''
export SI_VMLINUZ

#initrd name
SI_INITRD=''
export SI_INITRD

#System.map name
SI_SYSTEMMAP=''
export SI_SYSTEMMAP

#Euler version
MENU_VERSION=
export MENU_VERSION

#OS.tar.gz包解压次数
SI_UNCOMPRESS_TIME=1

#/etc/SI_FSTAB in OS
SI_FSTAB=/etc/fstab

#/etc/SI_FSTAB_BAK in OS
SI_FSTAB_BAK=/etc/fstab_bak

#/boot/grub in OS
SI_GRUB_PATH=/boot/grub

GRUB_DIR=/usr/lib/grub
GRUB2_DIR=/usr/lib/grub2
if [ ${EFI_FLAG} -eq 1 ]; then
    SI_GRUB2_PATH=/boot/efi/EFI/openEuler
else
    SI_GRUB2_PATH=/boot/grub2
fi
GRUB2_EFI=EFI/grub2

GRUB2_CMD="`which grub2-install`"

SI_PARTITION=''
#menu.lst中root值#
SI_PARTITION_MENU=''

#启动分区id
SI_PARTITION_ID=''
export SI_PARTITION_ID

SI_DISK_NAME=''

#启动盘/dev/sda
SI_DISK=''
export SI_DISK

#第一块硬盘的ID#
SI_FIRSTDISK_ID=''

source $LOCAL_SCRIPT_PATH/log/setuplog.sh
source $LOCAL_SCRIPT_PATH/util/CommonFunction
source $LOCAL_SCRIPT_PATH/disk/hwcompatible.sh
source $LOCAL_SCRIPT_PATH/disk/diskmgr.sh

BEFORE_MKINITRD_HOOK=${LOCAL_HOOK_PATH}/before_mkinitrd_hook
AFTER_SETUP_OS_HOOK=${LOCAL_HOOK_PATH}/after_setup_os_hook
BEFORE_INSALLGRUB_HOOK=${LOCAL_HOOK_PATH}/before_installgrub_hook

####################################################
#funcation:SetupOS_ParserSdf
#desc:parser sdf file
#input none
#output 1
#date 2013-09-17
####################################################
function SetupOS_ParserSdf()
{
    local euler_version=
    local os_version=

   #1.get os tar package
    if [ ! -f "$SI_OS_PACKAGE_SDF" ]; then
        g_LOG_Error "the $SI_OS_PACKAGE_SDF is not exist."
        return 1
    fi

    SI_OSTARNAME="`INIT_Get_CmdLineParamValue 'name' ${SI_OS_PACKAGE_SDF}`"
    SI_VERSION="`INIT_Get_CmdLineParamValue 'kernelversion' ${SI_OS_PACKAGE_SDF}`"
    LOCAL_SI_VERSION="`INIT_Get_CmdLineParamValue 'localversion' ${SI_OS_PACKAGE_SDF}`"
    SI_UNCOMPRESS_TIME="`INIT_Get_CmdLineParamValue 'uncompresstime' ${SI_OS_PACKAGE_SDF}`"

    euler_version="`INIT_Get_CmdLineParamValue 'eulerversion' ${SI_OS_PACKAGE_SDF}`"
    os_version="`INIT_Get_CmdLineParamValue 'os_version' ${SI_OS_PACKAGE_SDF}`"
    if [ ! -z "${euler_version}" ]; then
        MENU_VERSION=${euler_version}
    elif [ ! -z "${os_version}" ]; then
        MENU_VERSION=${os_version}
    else
        MENU_VERSION="openEuler"
    fi

    if [ -z "$LOCAL_SI_VERSION" ]; then
        LOCAL_SI_VERSION="-default"
        g_LOG_Info "localversion is set "-default"."
    else
        g_LOG_Info "localversion is $LOCAL_SI_VERSION."
    fi

    if [ -z "$SI_VERSION" ]; then
        g_LOG_Error "the kernelversion is null, please input the kernel version in $SI_OS_PACKAGE_SDF file."
        return 1
    else
        g_LOG_Info "kernelversion is $SI_VERSION."
    fi

    SI_VMLINUZ="vmlinuz-${SI_VERSION}${LOCAL_SI_VERSION}"
    SI_SYSTEMMAP="System.map-${SI_VERSION}${LOCAL_SI_VERSION}"

    if [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
        SI_INITRD="initramfs-${SI_VERSION}${LOCAL_SI_VERSION}.img"
    else
        SI_INITRD="initrd-${SI_VERSION}${LOCAL_SI_VERSION}"
    fi

    return 0
}

#########################################################
#   Description:    SetupOS_Decompr
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_Decompr()
{
    local boot_dir=./boot
    local initrd_file=initrd
    local linux_file=linux

    #check sdf file is null or not
    if [ -z "$SI_OSTARNAME" ]; then
        g_LOG_Error "the OS package name is $SI_OSTARNAME in the $SYSCONFIG_CONF file."
        return 1
    fi

    #check OS.tar.gz is correct or not
    if [ ! -f "$LOCAL_SOURCE_PATH/$SI_OSTARNAME" ]; then
        g_LOG_Error "$SI_OSTARNAME is not exist in $LOCAL_SOURCE_PATH."
        return 1
    else
        g_LOG_Info "checking $SI_OSTARNAME package sucess."
    fi

    #sha256sum check
    if [ ! -z "$LOCAL_SOURCE_PATH" -a ! -z "$SI_OSTARNAME" -a -f "$LOCAL_SOURCE_PATH/$SI_OSTARNAME.sha256" ]; then
        pushd $LOCAL_SOURCE_PATH >> $OTHER_TTY 2>&1
        sha256sum -c "$SI_OSTARNAME.sha256" >> $OTHER_TTY 2>&1
        if [ $? -eq 0 ]; then
            g_LOG_Info "sha256sum success."
            popd >> $OTHER_TTY 2>&1
        else
            g_LOG_Error "sha256sum failed."
            popd >> $OTHER_TTY 2>&1
            return 1
        fi
    else
        g_LOG_Error "the $LOCAL_SOURCE_PATH/$SI_OSTARNAME.sha256 file is null or not exist."
        return 1
    fi

    g_LOG_Info "Uncompressing OS package."
    g_LOG_Info "Uncompressing path is $LOCAL_UNCOMPRESS_PATH"
    if [ ! -d "$LOCAL_UNCOMPRESS_PATH" ]; then
        g_LOG_Error "Uncompressing path is $LOCAL_UNCOMPRESS_PATH not exist."
        return 1
    fi

    tar -xzf $LOCAL_SOURCE_PATH/$SI_OSTARNAME -C $LOCAL_UNCOMPRESS_PATH >> $OTHER_TTY 2>&1
    if [ $? -ne 0 ]; then
        g_LOG_Error "uncompressed the $LOCAL_SOURCE_PATH/$SI_OSTARNAME failed."
          return 1
    fi

    #initrd解压到硬盘上的场景。
    if [ "$SI_UNCOMPRESS_TIME" = 2 ]; then
        g_LOG_Info "Uncompress initrd to $LOCAL_UNCOMPRESS_PATH."

        pushd $LOCAL_UNCOMPRESS_PATH >> $OTHER_TTY 2>&1

        if [ ! -f ./${initrd_file} ] || [ ! -f ./${linux_file} ]; then
            g_LOG_Error "Can't find initrd or linux."
            popd >> $OTHER_TTY 2>&1
            return 1
        fi

        cat ${initrd_file} | gunzip | cpio -di
        if [ $? -ne 0 ]; then
            g_LOG_Error "Uncompress initrd failed"
            popd >> $OTHER_TTY 2>&1
            return 1
        fi

        if [ ! -d ${boot_dir} ]; then
            mkdir -p ${boot_dir}
            if [ $? -ne 0 ]; then
                g_LOG_Error "mkdir ${boot_dir} failed"
                return 1
            fi
        fi

        mv ${linux_file} ${boot_dir}/$SI_VMLINUZ >> $OTHER_TTY 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "move ${linux_file} to ${boot_dir}/$SI_VMLINUZ failed."
            popd >> $OTHER_TTY 2>&1
            return 1
        fi

        rm -rf ${initrd_file}
        if [ $? -ne 0 ]; then
            g_LOG_Error "rm ${initrd_file} failed."
            popd >> $OTHER_TTY 2>&1
            return 1
        fi

        #拷贝System.map，grub，vmlinuz，initrd到启动目录
        cp -a $LOCAL_CONFIG_PATH/System.map ${boot_dir}/$SI_SYSTEMMAP >> $OTHER_TTY 2>&1

        popd >> $OTHER_TTY 2>&1
    fi

    sync
    g_LOG_Notice "Uncompress success."

    return 0
}

#########################################################
#   Description:    SetupOS_CpFstab
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_CpFstab()
{

    #copy fstab to /etc
    if [ ! -f "$FSTAB_FILE" -o -z "$FSTAB_FILE" ]; then
        g_LOG_Error "the $FSTAB_FILE in ISO is not exist or null."
        return 1
    fi

    if [ -d "${LOCAL_DISK_PATH}/etc" ]; then
        #copy fstab from iso to disk
        cp -af $FSTAB_FILE ${LOCAL_DISK_PATH}${SI_FSTAB} >> $OTHER_TTY 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "copy $SI_FSTAB failed."
            return 1
        fi

        #modify fstab，add "proc，sysfs，debugfs，usbfs，devpts"
        echo "sysfs                /sys                 sysfs      noauto                0 0" >> ${LOCAL_DISK_PATH}${SI_FSTAB}
        echo "proc                 /proc                proc       defaults              0 0" >> ${LOCAL_DISK_PATH}${SI_FSTAB}
        echo "usbfs                /proc/bus/usb        usbfs      noauto                0 0" >> ${LOCAL_DISK_PATH}${SI_FSTAB}
        echo "devpts               /dev/pts             devpts     mode=0620,gid=5       0 0" >> ${LOCAL_DISK_PATH}${SI_FSTAB}

        g_LOG_Info "copy $FSTAB_FILE success."

    fi

    return 0
}

#########################################################
#   Description:    remountSysFs2Target
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function remountSysFs2Target()
{
    #Check if the dev directory is already mounted
    if [ -z "`mount | grep " $LOCAL_DISK_PATH/dev "`" ]; then
        if [ ! -d $LOCAL_DISK_PATH/dev ]; then
            mkdir $LOCAL_DISK_PATH/dev -p
            if [ $? -ne 0 ]; then
                g_LOG_Error "mkdir $LOCAL_DISK_PATH/dev failed"
                return 1
            fi
        fi
        mount --bind /dev $LOCAL_DISK_PATH/dev/
        if [ $? -ne 0 ]; then
            g_LOG_Error "Mount devtmpfs filesystem failed."
            return 1
        fi
    fi

    g_LOG_Info "Mount dev filesystem success."

    #Check if the proc directory is already mounted
    if [ -z "`mount | grep " $LOCAL_DISK_PATH/proc "`" ]; then
        if [ ! -d $LOCAL_DISK_PATH/proc ]; then
            mkdir $LOCAL_DISK_PATH/proc -p
            if [ $? -ne 0 ]; then
                g_LOG_Error "mkdir $LOCAL_DISK_PATH/proc failed"
                return 1
            fi
        fi
        mount --bind /proc $LOCAL_DISK_PATH/proc
        if [ $? -ne 0 ]; then
            g_LOG_Error "Mount proc filesystem failed."
            return 1
        fi
    fi

    g_LOG_Info "Mount proc filesystem success."

    #Check if the sys directory is already mounted
    if [ -z "`mount | grep " $LOCAL_DISK_PATH/sys "`" ]; then
        if [ ! -d $LOCAL_DISK_PATH/sys ]; then
            mkdir $LOCAL_DISK_PATH/sys -p
            if [ $? -ne 0 ]; then
                g_LOG_Error "mkdir $LOCAL_DISK_PATH/sys failed"
                return 1
            fi
        fi
        mount --bind /sys $LOCAL_DISK_PATH/sys
        if [ $? -ne 0 ]; then
            g_LOG_Error "Mount sysfs filesystem failed."
            return 1
        fi
    fi

    g_LOG_Info "Mount memory filesystem success."
    return 0
}

#########################################################
#   Description:    SetupOS_Initrd
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_Initrd()
{
    local mkinit_cmd=''
    local ret=0

    g_LOG_Notice "Creating initrd."

    chroot ${LOCAL_DISK_PATH} >> ${OTHER_TTY} 2>&1 <<EOF
    depmod -a "${SI_VERSION}${LOCAL_SI_VERSION}"
EOF
    if [ $? -ne 0 ]; then
        g_LOG_Error "depmod failed."
        return 1
    else
        g_LOG_Info "depmod success."
    fi

    g_LOG_Debug "SI_VERSION ${SI_VERSION}, SI_CMDTYPE ${SI_CMDTYPE}"
    if [ "x${SI_CMDTYPE}" == "xsl-cmd"  ]; then
        g_LOG_Info "mkinitrd with sl-cmd."
        mkinit_cmd="mkinitrd -k /boot/${SI_VMLINUZ} -i /boot/${SI_INITRD} -M /boot/${SI_SYSTEMMAP}"
    elif [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
        g_LOG_Info "mkinitrd with rh-cmd."
        mkinit_cmd="dracut -f /boot/${SI_INITRD} ${SI_VERSION}${LOCAL_SI_VERSION}"
    else
        g_LOG_Error "no mkinitrd cmd."
    fi

    chroot ${LOCAL_DISK_PATH} >> ${OTHER_TTY} 2>&1 <<EOF
        ${mkinit_cmd}
EOF
    ret=$?
    if [ ${ret} -ne 0 ]; then
        g_LOG_Notice "mkinitrd errno ${ret}"
    else
        g_LOG_Notice "mkinitrd success."
    fi

    if [ ! -f "${LOCAL_DISK_PATH}/boot/${SI_INITRD}" ]; then
        g_LOG_Error "Can not find ${LOCAL_DISK_PATH}/boot/${SI_INITRD} file, mkinitrd failed."
        return 1
    fi

    return 0
}

#########################################################
#   Author：
#   Description:获取硬盘设备的ID，某些光驱会被识别成sd设备，所以第一块硬盘不一定对应 hd0
#   Input:      硬盘名 (例：/dev/sdc)
#   Return:     硬盘ID （例：2）
#########################################################
function SetupOS_get_diskid()
{
    local harddisk_name=$1
    local harddisk_id=
    local machine_type=
    local command=

    #input check
    if [ -z "${harddisk_name}" ]; then
        g_LOG_Error "harddisk_name is null."
        return 1
    fi

    #get machine type
    machine_type="`DM_GetMachineType`"

    #get the id of disk
    case ${machine_type} in
    ${CON_MACHINE_TYPE_HP})
        harddisk_id="`echo ${harddisk_name} | awk -F "/" '{print substr($NF,length($NF),1)}'`"
        command="`printf "%d" "'${harddisk_id}"` - `printf "%d" "'0"`"
        harddisk_id="`expr $command`"
    ;;
    ${CON_MACHINE_TYPE_RED3})
        #red3.0设备不考虑存在其他盘命名成/dev/md设备的场景。所以第一块盘id，始终是0
        harddisk_id="`echo ${harddisk_name} | awk -F "/" '{print substr($NF,length($NF),1)}'`"
        command="`printf "%d" "'${harddisk_id}"` - `printf "%d" "'${harddisk_id}"`"
        harddisk_id="`expr $command`"
    ;;
    *)
        harddisk_id="`echo ${harddisk_name} | awk -F "/" '{print substr($NF,length($NF),1)}'`"
        command="`printf "%d" "'${harddisk_id}"` - `printf "%d" "'a"`"
        harddisk_id="`expr $command`"
    ;;
    esac

    echo "${harddisk_id}"

    return 0
}

#########################################################
#   Description:    get boot partion name
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_GetBootPartition()
{
    local var=
    local rootdisk_id=
    local command=

    #DM_GetGrubInfo返回的信息形式为grub_info="${disk_dev} hd${harddisk_id} ${partition_id}"
    #/dev/sdb hd1 0
    var=`DM_GetGrubInfo ${FSTAB_FILE}`
    if [ -z "$var" ]; then
        g_LOG_Error "function DM_GetGrubInfo return is null."
        return 1
    fi

    SI_PARTITION_ID=`echo $var | awk '{print $3}'`
    SI_DISK_NAME=`echo $var | awk '{print $2}'`
    SI_PARTITION="($SI_DISK_NAME,$SI_PARTITION_ID)"
    SI_DISK=`echo $var | awk '{print $1}'`

    #get first disk name
    FIRST_DISK="`DM_Get_FirstDiskName`"

    SI_FIRSTDISK_ID=`SetupOS_get_diskid "${FIRST_DISK}"`
    if [ $? -ne 0 ]; then
        g_LOG_Error "get the id of firstdisk:${FIRST_DISK} error."
        return 1
    fi
    g_LOG_Info "SI_PARTITION_ID=$SI_PARTITION_ID SI_DISK_NAME=$SI_DISK_NAME SI_PARTITION=$SI_PARTITION SI_DISK=$SI_DISK FIRST_DISK=$FIRST_DISK SI_FIRSTDISK_ID=$SI_FIRSTDISK_ID"
    if [ ${SI_FIRSTDISK_ID} -eq 0 ]; then
        SI_PARTITION_MENU="($SI_DISK_NAME,$SI_PARTITION_ID)"
    else
        rootdisk_id="`echo ${SI_DISK_NAME} | awk '{print substr($NF,length($NF),1)}'`"
        command="`printf "%d" "${rootdisk_id}"` - `printf "%d" "${SI_FIRSTDISK_ID}"`"
        rootdisk_id="`expr $command`"
        SI_PARTITION_MENU="(hd${rootdisk_id},$SI_PARTITION_ID)"
    fi

    if [ -z "$SI_DISK" ] || [ -z "$SI_DISK_NAME" ] || [ -z "$SI_PARTITION_ID" ]; then
        g_LOG_Error "disk=$SI_DISK,disk_name=$SI_DISK_NAME,partition_id=$SI_PARTITION_ID."
        return 1
    fi

    g_LOG_Info "SI_PARTITION_MENU=$SI_PARTITION_MENU"

    return 0
}

#########################################################
#   Description:    SetupOS_GrubInstall
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_GrubInstall()
{
    local error_code=
    local log_file="/opt/grub.log"
    g_LOG_Info "Installing Grub."

    # Verify env
    if [ ! -d "$LOCAL_DISK_PATH/$SI_GRUB_PATH" ]; then
        g_LOG_Error "Grub path dose not exist."
        return 1
    fi

    if [ ! -f "$LOCAL_DISK_PATH/$SI_GRUB_PATH/stage1" ]; then
        g_LOG_Error "stage1 does not exist in the target."
        return 1
    fi

    if [ ! -f "$LOCAL_DISK_PATH/$SI_GRUB_PATH/stage2" ]; then
        g_LOG_Error "stage2 does not exist in the target."
        return 1
    fi

    which grub >> $OTHER_TTY 2>&1
    if [ $? -ne 0 ]; then
        g_LOG_Error "grub command not found."
        return 1
    fi

    grub --batch --device-map=${LOCAL_DISK_PATH}/boot/grub/device.map > $log_file 2>&1  <<EOF
    root $SI_PARTITION
    setup (hd$SI_FIRSTDISK_ID)
    quit
EOF

    error_code=`cat $log_file | grep "Error"`

    if [ -z "$error_code" ]; then
        g_LOG_Notice "Install Grub success."
    else
        g_LOG_Info "`cat $log_file`"
        return 1
    fi

    return 0
}

#########################################################
#   Description:    SetupOS_Grub2Install
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_Grub2Install()
{
    g_LOG_Info "Installing Grub2."
    local boot_partition_id=
    local efi_mount_dir="/boot/efi"
    local arch="$(uname -m)"
    local log_file="/opt/grub2.log"
    local grub_editenv="`which grub2-editenv`"
    local slot_id=

    #boot_esp true means esp partition is /boot, this could happened in x86
    if [ "x${BOOT_ESP}" = "xtrue" ]; then
        efi_mount_dir="/boot"
    fi

    if [ ${EFI_FLAG} -eq 1 ]; then
        boot_devname=$(mount | grep "${efi_mount_dir} " | awk '{print $1}')
        boot_partition_id=${boot_devname:(-1)}
        g_LOG_Info "Install UEFI bootloader"
        if ! mount | grep efivarfs >/dev/null; then
            mount -t efivarfs efivarfs /sys/firmware/efi/efivars
        fi

        slot_id=`efibootmgr | grep -w "openEuler Linux" | awk -F "*" '{print $1}' | awk -F "Boot" '{print $2}'`
	if [ ! -z "${slot_id}" ]; then
            efibootmgr -b ${slot_id} -B
        fi

        #添加bios的uefi启动项，（-p 1表示第1个分区）
        #uefi模式下，启动分区id从1开始，（-1）仅支持分区1到分区9

        g_LOG_Debug "boot partition name is "${boot_devname}", boot partition id is "${boot_partition_id}""

        if [ "${arch}" = "aarch64" ]; then
            efibootmgr -q -c -d ${SI_DISK} -p ${boot_partition_id} -w -L 'openEuler Linux' -l '\EFI\openEuler\grubaa64.efi'
        else
            if [ "x${BOOT_ESP}" = "xtrue" ]; then
                efibootmgr -q -c -d ${SI_DISK} -p ${boot_partition_id} -w -L 'openEuler Linux' -l '\efi\EFI\openEuler\grubx64.efi'
            else
                efibootmgr -q -c -d ${SI_DISK} -p ${boot_partition_id} -w -L 'openEuler Linux' -l '\EFI\openEuler\grubx64.efi'
            fi
        fi
        if [ $? -ne 0 ]; then
            g_LOG_Error "efibootmgr for ${SI_DISK} failed."
            return 1
        fi
        g_LOG_Info "Execute efibootmgr success"

        if [ -f "${LOCAL_DISK_PATH}${grub_editenv}" ]; then
            chroot ${LOCAL_DISK_PATH} ${grub_editenv} create
            if [ $? -ne 0 ]; then
                g_LOG_Error "chroot ${LOCAL_DISK_PATH} ${grub_editenv} create failed."
            fi
        else
            g_LOG_Warn "Command grub2-editenv doesn't exist."
        fi
    else
        g_LOG_Info "Install BIOS bootloader"
        #BIOS grub2
        eval ${GRUB2_CMD} --boot-directory=${LOCAL_DISK_PATH}/boot ${SI_DISK} --debug --force > ${log_file} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "${GRUB2_CMD} --boot-directory=${LOCAL_DISK_PATH}/boot ${SI_DISK} --debug --force failed."
            return 1
        else
            g_LOG_Info "${GRUB2_CMD} --boot-directory=${LOCAL_DISK_PATH}/boot ${SI_DISK} --debug --force success."
        fi

    fi
}
#########################################################
#   Description:    setup grub.conf and devicemap file
#   Input           partion names,such as:(hd0,0),hd0,/dev/sda
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_DeviceMap_GrubConf()
{
    local partion_grub=$1
    local diskname_grub=$2
    local disk_os=$3

    if [ "${diskname_grub}" == "hd0" -o "${FIRST_DISK}" == "${disk_os}" ]; then
        echo "("${diskname_grub}") "${disk_os}"" > ${LOCAL_DISK_PATH}${SI_GRUB_PATH}/device.map
    elif [ ! -z "${FIRST_DISK}" ]; then
        echo "("${diskname_grub}") "${disk_os}"
        (hd${SI_FIRSTDISK_ID}) $FIRST_DISK" > ${LOCAL_DISK_PATH}${SI_GRUB_PATH}/device.map
    else
        g_LOG_Error "FIRST_DISK is null."
        return 1
    fi

    return 0
}

#########################################################
#   Description:    SetupOS_Modify_Menulst
#   Input           root,resume
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_Modify_Menulst()
{
    local value=''
    local name=''
    local option="$1"
    local grub_cfg="${LOCAL_DISK_PATH}/${SI_GRUB2_PATH}/grub.cfg"

    cat ${grub_cfg} | grep "${option}=" | grep -v "set root=" > ${LOCAL_CONFIG_PATH}/menu.lst_bak
    for var in $(cat ${LOCAL_CONFIG_PATH}/menu.lst_bak);
    do
        name=`echo "${var}" | awk -F '=' '{print $1}'`
        if [ "${name}" = "${option}" ]; then
            value=$(echo ${var#${option}=})
            break
        fi
    done

    echo ${value}

    rm -rf ${LOCAL_CONFIG_PATH}/menu.lst_bak >/dev/null 2>&1

    return 0
}


#########################################################
#   Description:    Setup_Grubpassword
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function Setup_Grubpassword()
{
    local crypt_grub_passwd=''
    local grub_default_file="${LOCAL_DISK_PATH}/etc/default/grub"
    local user_cfg="${LOCAL_DISK_PATH}${SI_GRUB2_PATH}/user.cfg"

    #set gurb root password
    if cat ${grub_default_file} | grep "^GRUB_PASSWORD" >/dev/null; then
        crypt_grub_passwd="$(cat ${grub_default_file} | grep "^GRUB_PASSWORD" | awk -F= '{print $2}' | grep "grub.pbkdf2.sha512" | sed "s/\"//g" | sed "s/'//g")"
    elif cat ${grub_default_file} | grep "^GRUB2_PASSWORD" >/dev/null; then
        crypt_grub_passwd="$(cat ${grub_default_file} | grep "^GRUB2_PASSWORD" | awk -F= '{print $2}' | grep "grub.pbkdf2.sha512" | sed "s/\"//g" | sed "s/'//g")"
    fi

    if [ -z "${crypt_grub_passwd}" ]; then
        g_LOG_Error "No valid grub password found. Please add a passwd in grub config file!"
        return 1
    else
        echo "GRUB2_PASSWORD=${crypt_grub_passwd}" >> ${user_cfg}
        chmod 600 ${user_cfg}
        if [ $? -ne 0 ]; then
	    g_LOG_Error "chmod user.cfg failed."
	    return 1
        fi
    fi

    return 0
}

#########################################################
#   Description:    SetupOS_GrubCfg
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_GrubCfg()
{
    local rootPartition=''
    local root_device=''
    local root_device_tmp=''
    local grub_cfg="${LOCAL_DISK_PATH}/${SI_GRUB2_PATH}/grub.cfg"
    local grub_uefi_firmware="${LOCAL_DISK_PATH}/etc/grub.d/30_uefi-firmware"

    local title_str=''

    g_LOG_Info "Installing grub.cfg, uncompresstime is ${SI_UNCOMPRESS_TIME}"

    #install initrd linux to disk
    #double boot entry is not supported
    if [ "${SI_UNCOMPRESS_TIME}" == 2 ]; then
        #modify uuid to by-id in grub.cfg
        rootPartition=`sed -n "/\s\/\s/p" ${LOCAL_DISK_PATH}${SI_FSTAB} | awk '{print $1}'`

        if [ -z "${rootPartition}" ]; then
            g_LOG_Error "root partition can not be found."
            return 1
        fi
        g_LOG_Info "the root partition is ${rootPartition}."

        if [ -f ${grub_uefi_firmware} ]; then
             chmod -x ${grub_uefi_firmware}
        fi

        Setup_Grubpassword
        if [ $? -ne 0 ]; then
            g_LOG_Error "set grub password failed."
            return 1
        fi

        chroot ${LOCAL_DISK_PATH} grub2-mkconfig -o ${SI_GRUB2_PATH}/grub.cfg
        if [ $? -ne 0 ]; then
            g_LOG_Error "chroot ${LOCAL_DISK_PATH} grub2-mkconfig -o ${SI_GRUB2_PATH}/grub.cfg failed."
            return 1
        else
            g_LOG_Info "chroot ${LOCAL_DISK_PATH} grub2-mkconfig -o ${SI_GRUB2_PATH}/grub.cfg success."
        fi
        chmod 600 ${grub_cfg}
        if [ $? -ne 0 ]; then
            g_LOG_Error "chmod grub.cfg failed."
            return 1
        fi
        chmod +x ${grub_uefi_firmware}

        root_device=`SetupOS_Modify_Menulst "root"`
        if [ -z "${root_device}" ]; then
            g_LOG_Warn "root_device in grub.cfg is null."
        fi

        root_device_tmp=`echo ${root_device} | sed 's#\/#\\\/#g'`
        rootPartition=`echo ${rootPartition} | sed 's#\/#\\\/#g'`
        g_LOG_Debug "old root_device is ${root_device}, old rootPartition is ${rootPartition}."

        sed -i "s/${root_device_tmp}/${rootPartition}/g" ${grub_cfg}

        #grub.cfg中的title
        title_str=$(cat ${grub_cfg} |grep "^menuentry" | awk -F "[']" '{print $2}')
        if [ -z "${title_str}" ]; then
            g_LOG_Warn "no title."
        fi

        sed -i "s/${title_str}/${MENU_VERSION}/g" ${grub_cfg}
    fi

    g_LOG_Notice "instsall OS grub.cfg success."

    return 0
}

#########################################################
#   Description:    SetupOS_Menulst
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_Menulst()
{
    local grub_root=''
    local grub_roots=''
    local grub_root_new=''

    local rootPartition=''
    local root_device=''
    local root_device_tmp=''

    local title_str=''

    g_LOG_Info "Modifying Menu.lst."

    if [ ! -f ${MENULST_CONF} ]; then
        g_LOG_Error "the ${MENULST_CONF} is not exist."
        return 1
    fi

    #修改menu.lst中的grub root
    grub_roots=`cat ${MENULST_CONF} |grep "root ("`
    if [ -z "${grub_roots}" ]; then
        g_LOG_Error "no grub root."
        return 1
    fi

    grub_root=`echo ${grub_roots} | awk -F ")" '{print $1}'`")"

    grub_root_new="root ${SI_PARTITION_MENU}"

    sed -i "s/${grub_root}/${grub_root_new}/g" ${MENULST_CONF} >> ${OTHER_TTY} 2>&1
    if [ $? -ne 0 ]; then
        g_LOG_Error "modify OS menu.lst grub root failed."
        return 1
    fi

    #initrd解压到硬盘上的场景，需要修改menu.lst中的root选项,title
    #注意，我们不支持双系统，所以menu.lst中只存在一个菜单项
    if [ "${SI_UNCOMPRESS_TIME}" == 2 ]; then
        #修改menu.lst中的root选项
        rootPartition=`sed -n "/\s\/\s/p" ${LOCAL_DISK_PATH}${SI_FSTAB} | awk '{print $1}'`

        if [ -z "${rootPartition}" ]; then
            g_LOG_Error "root partition can not be found."
            return 1
        fi

        g_LOG_Info "the root partition is ${rootPartition}."

        root_device=`SetupOS_Modify_Menulst "root"`
        if [ -z "${root_device}" ]; then
            g_LOG_Warn "root_device in menu.lst is null."
        fi

        root_device_tmp=`echo ${root_device} | sed 's#\/#\\\/#g'`
        rootPartition=`echo ${rootPartition} | sed 's#\/#\\\/#g'`
        g_LOG_Debug "old root_device is ${root_device}, old rootPartition is ${rootPartition}."

        sed -i "s/${root_device_tmp}/${rootPartition}/g" ${MENULST_CONF}

        #menu.lst中的title
        title_str=`cat ${MENULST_CONF} |grep "^title"`
        if [ -z "${title_str}" ]; then
            g_LOG_Warn "no title."
        fi

        sed -i "s/${title_str}/title ${MENU_VERSION}/g" ${MENULST_CONF}
    fi

    g_LOG_Notice "Modify OS menu.lst success."

    #存储的menu.lst是软连接，所以这里不拷贝，直接修好$LOCAL_CONFIG_PATH/menu.lst，然后在hook中做拷贝#
    #对于默认流程，还是执行拷贝#
    if [ -d "${LOCAL_DISK_PATH}${SI_GRUB_PATH}" ] && [ ! -L "${LOCAL_DISK_PATH}${SI_GRUB_PATH}" ]; then
        g_LOG_Info "copy ${MENULST_CONF} to ${LOCAL_DISK_PATH}${SI_GRUB_PATH}"
        chmod 600 ${MENULST_CONF} >> ${OTHER_TTY} 2>&1
        cp -af ${MENULST_CONF} ${LOCAL_DISK_PATH}${SI_GRUB_PATH} >> ${OTHER_TTY} 2>&1
    fi

    return 0
}

#########################################################
#   Description:    SetupOS_clean
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_clean()
{
    local download_dir=''

    g_LOG_Info "execute clean after setup os."

    #LOCAL_SOURCE_PATH=/mnt/disk/download/repo LOCAL_SOURCE_PATH is changed in load.sh
    download_dir=`dirname ${LOCAL_SOURCE_PATH}`
    g_LOG_Debug "download_dir is ${download_dir}"

    if [ -n "`cat /proc/mounts | grep " ${download_dir} "`" ]; then
        umount ${download_dir} >> ${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            umount -l ${download_dir} >> ${OTHER_TTY} 2>&1
            g_LOG_Warn "umount ${download_dir} failed,use umount -l again."
        else
            g_LOG_Info "umount ${download_dir} success."
        fi
    fi

    rm -rf ${download_dir} >> ${OTHER_TTY} 2>&1

    rm -rf ${LOCAL_DISK_PATH}/lost+found

    return 0
}

#########################################################
#   Description:    SetupOS_Install
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS_Install()
{
    SetupOS_ParserSdf
    if [ $? -ne 0 ]; then
        g_LOG_Error "parser sdf file error"
        return 1
    fi

    g_LOG_Info "Decompressing OS."
    SetupOS_Decompr

    if [ $? -ne 0 ]; then
        g_LOG_Error "Decompressing OS failed."
        return 1
    fi

    #对于initrd放在硬盘上的场景，不支持fstab挂载。对于initrd解压到硬盘上的，支持fstab挂载#
    g_LOG_Info "Copy fstab."
    SetupOS_CpFstab
    if [ $? -ne 0 ]; then
        g_LOG_Error "Setup fstab failed."
        return 1
    fi

    #对于initrd放在硬盘上的场景,mkinitrd
    if [ "${SI_UNCOMPRESS_TIME}" == 2 ]; then
        g_LOG_Info "Remount system fs."
        remountSysFs2Target
        if [ $? -ne 0 ]; then
            g_LOG_Error "mount memory filesystem failed."
            return 1
        fi

        INIT_Execute_Hook ${BEFORE_MKINITRD_HOOK} ${LOCAL_DISK_PATH}
        if [ $? -ne 0 ]; then
            g_LOG_Error "Execute before_mkinitrd_hook failed."
            return 1
        fi
        SetupOS_Initrd
        if [ $? -ne 0 ]; then
            g_LOG_Error "mkinitrd failed, please check environment."
            return 1
        fi

    fi

    # check boot partion is exist or not获取引导分区相关信息#
    g_LOG_Info "Get boot partition."
    SetupOS_GetBootPartition
    if [ $? -ne 0 ]; then
        g_LOG_Error "cannot find /boot folder."
        return 1
    else
        g_LOG_Info "the boot disk is ${SI_PARTITION}."
    fi

    #生成device.map#
    SetupOS_DeviceMap_GrubConf ${SI_PARTITION} ${SI_DISK_NAME} ${SI_DISK}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Setup device map failed."
        return 1
    fi

    INIT_Execute_Hook ${BEFORE_INSALLGRUB_HOOK} ${LOCAL_DISK_PATH}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Execute before_installgrub_hook failed."
        return 1
    fi

    if [ -f "${GRUB2_CMD}" ]; then
        #安装grub2#
        g_LOG_Info "${GRUB2_CMD} exist,install grub2 start."
        SetupOS_Grub2Install
        if [ $? -ne 0 ]; then
            g_LOG_Error "Install grub2 failed."
            return 1
        fi

        SetupOS_GrubCfg
        if [ $? -ne 0 ]; then
            g_LOG_Error "Modify grub.cfg failed."
            return 1
        fi
    else
        #安装grub#
        g_LOG_Info "leagcy boot,install grub start."
        SetupOS_GrubInstall
        if [ $? -ne 0 ]; then
            g_LOG_Error "Install grub failed."
            return 1
        fi
        SetupOS_Menulst
        if [ $? -ne 0 ]; then
            g_LOG_Error "Modify menu.lst failed."
            return 1
        fi
    fi

    #拷贝new.part到/etc目录中，用于下次安装进行分区比较
    if [ -f "${LOCAL_TEMPCFG_PATH}/new.part" ] && [ -d "${LOCAL_DISK_PATH}/etc" ]; then
        g_LOG_Info "copy ${LOCAL_TEMPCFG_PATH}/new.part to ${LOCAL_DISK_PATH}/etc"
        DM_CopyPartitionConf ${LOCAL_TEMPCFG_PATH}/new.part
        if [ $? -ne 0 ]; then
            g_LOG_Warn "move new.part file failed"
        fi
        cp ${LOCAL_TEMPCFG_PATH}/new.part ${LOCAL_DISK_PATH}/etc/ >> ${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Warn "copy new.part failed"
        fi
    fi

    #如果存在after_setup_os_hook，则执行hook#
    INIT_Execute_Hook ${AFTER_SETUP_OS_HOOK} ${LOCAL_SOURCE_PATH} ${LOCAL_CONFIG_PATH}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Execute after_setup_os_hook failed."
        return 1
    fi

    SetupOS_clean

    return 0
}

#########################################################
#   Description:    main function set 3 functions
#                    1、install 2、rescue 3、error
#   Input           none
#   Return:         0: SUCCESS
#                   1: Internal Error.
#########################################################
function SetupOS()
{
    local ret=

    case ${SI_INSTALL_MODE} in
        install)
            SetupOS_Install
            ret=$?
            sync
            return ${ret}
        ;;
        *)
            g_LOG_Error "Unsupported install mod:[${install_mode}]"
            return 1
        ;;
    esac
}


if [ ! -z "`cat /proc/mounts | grep " ${LOCAL_DISK_PATH} "`" ]; then
    SetupOS
    ret=$?
else
    g_LOG_Error "${LOCAL_DISK_PATH} is not mounted."
    ret=1
fi

exit ${ret}

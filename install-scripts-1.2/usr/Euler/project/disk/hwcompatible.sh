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
* Description: functions for compatibility
!

#machine type
CON_MACHINE_TYPE_GENERAL="general"
CON_MACHINE_TYPE_HP="hp"

#version for kernel and crash kernel
CON_KERNEL_TYPE_XEN="xen"
CON_KERNEL_TYPE_DEFAULT="default"
CON_LIB_MODULES_PATH=/lib/modules
CON_ADDON_DRIVER_PATH=/kernel/addondrivers

########################################################
#    Description: get machine type
#    Parameter:   none
#    Return:      machine type
########################################################
function DM_GetMachineType()
{
    local machine_type=

    #get machine type
    if [ ! -z "`ls -l /sys/block | grep "c0d"`" ]; then
        machine_type=${CON_MACHINE_TYPE_HP}
    else
        machine_type=${CON_MACHINE_TYPE_GENERAL}
    fi

    echo "${machine_type}"

    return 0
}

########################################################
#    Description: get partition name
#    Parameter:   param1: disk device name
#                 param2: partition count
#    Return:      partition name
########################################################
function DM_GetPartitionName()
{
    local disk_dev=$1
    local partition_count=$2
    local machine_type=

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    if [ -z "${partition_count}" ] \
        || [ -z "`echo ${partition_count} | grep -P "^[1-9]\d*"`" ]; then
        g_LOG_Error "Illegal partition number."
        return 1
    fi

    #get machine type
    machine_type="`DM_GetMachineType`"

    #get partition name
    case ${machine_type} in
    ${CON_MACHINE_TYPE_HP})
        echo "${disk_dev}p${partition_count}"
    ;;
    *)
        echo "${disk_dev}${partition_count}"
    ;;
    esac

    return 0
}

#########################################################
#    Description: get partition number
#    Parameter:   param1: disk device name
#                 param2: partition name
#    Return:      partition number
#########################################################
function DM_GetPartitionNumber()
{
    local disk_dev=$1
    local partition_name=$2
    local machine_type=

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    if [ -z "${partition_name}" ]; then
        g_LOG_Error "Can't find partition ${partition_name}."
        return 1
    fi

    #get machine type
    machine_type="`DM_GetMachineType`"

    #get partition name
    case ${machine_type} in
    ${CON_MACHINE_TYPE_HP})
        echo "${partition_name}" | sed "s ${disk_dev}p  "
    ;;
    *)
        echo "${partition_name}" | sed "s ${disk_dev}  "
    ;;
    esac

    return 0
}

#########################################################
#    Description: get partition id
#    Parameter:   param1: partition name
#    Return:      partition id
#########################################################
function DM_GetPartitionById()
{
    local partition_name=$1
    local partition_dev_name=
    local partition_by_id=
    local machine_type=
    local partition_by_id_tmp=

    #input check
    if [ -z "${partition_name}" ]; then
        g_LOG_Error "Can't find partition ${partition_name}."
        return 1
    fi

    #format partition name
    partition_dev_name="`echo ${partition_name} | awk -F "/" '{print $NF}'`"
    #get machine type
    machine_type="`DM_GetMachineType`"

    #get partition name
    partition_by_id="`ls -l /dev/disk/by-id 2>&1 | grep -w "${partition_dev_name}" | awk '{print $9}'`"
    case ${machine_type} in
    ${CON_MACHINE_TYPE_HP})
        partition_by_id="`echo "${partition_by_id}" | grep "^cciss"`"
    ;;
    *)
        partition_by_id_tmp=${partition_by_id}
        partition_by_id="`echo "${partition_by_id_tmp}" | grep "^scsi"`"
        if [ -z "${partition_by_id}" ]; then
            partition_by_id="`echo "${partition_by_id_tmp}" | grep "^ata"`"
        fi
    ;;
    esac

    if [ -z "${partition_by_id}" ]; then
        g_LOG_Warn "Can't find partition id of ${partition_name}, use partition name instead."
        echo "${partition_name}"
    else
        echo "/dev/disk/by-id/${partition_by_id}"
    fi

    return 0
}

#########################################################
#    Description: get partition uuid
#    Parameter:   param1: partition name
#    Return:      partition uuid
#########################################################
function DM_GetPartitionByUuid()
{
    local partition_name=$1
    local partition_dev_name=
    local partition_by_uuid=

    #input check
    if [ -z "${partition_name}" ] || [ ! -b "${partition_name}" ]; then
        g_LOG_Error "Can't find partition ${partition_name}."
        return 1
    fi

    #format partition name
    partition_dev_name="`echo ${partition_name} | awk -F "/" '{print $NF}'`"

    #get partition name
    partition_by_uuid="`ls -l /dev/disk/by-uuid 2>&1 | grep -w "${partition_dev_name}" | awk '{print $9}'`"

    if [ -z "${partition_by_uuid}" ]; then
        g_LOG_Warn "Can't find partition uuid of ${partition_name}, use partition name instead."
        echo "${partition_name}"
    else
        echo "/dev/disk/by-uuid/${partition_by_uuid}"
    fi

    return 0
}

############################################################
#    Description: get grub info
#    Parameter:   param1: boot info file
#    Return:      grub info(include device name, harddisk id and partition id)
############################################################
function DM_GetGrubInfo()
{
    local fstab_file=$1

    local machine_type=
    local partition_name=
    local partition_info=
    local partition_id=
    local partition_name_intm=
    local disk_dev=
    local harddisk_id=
    local command=
    local grub_info=

    local first_disk=
    local first_disk_id=

    #input check
    if [ -z "${fstab_file}" ] || [ ! -f "${fstab_file}" ]; then
        g_LOG_Error "Can't find fstab file."
        return 1
    fi

    #get machine type
    machine_type="`DM_GetMachineType`"

    # Search for /boot/efi in fstab file
    partition_name="`sed -n "/\s\/boot\/efi\s/p" ${fstab_file} | awk '{print $1}'`"

    if [ -z "${partition_name}" ]; then
        #Search for /boot partition
        partition_name="`sed -n "/\s\/boot\s/p" ${fstab_file} | awk '{print $1}'`"
    fi

    partition_info="`ls -l ${partition_name} 2>&1`"
    if [ $? -ne 0 ]; then
        g_LOG_Error "Partition ${partition_name} doesn't exist."
        return 1
    elif [ ! -z "`echo ${partition_info} | grep "^l"`" ]; then
        case ${DISK_FLAG} in
        UUID)
            partition_name_intm="`echo ${partition_info} | awk '{print $11}'`"
            partition_id=${partition_name_intm##*[a-zA-Z]}
        ;;
        *)
            partition_id="`echo ${partition_name} | awk -F'-part' '{print $2}'`"
        ;;
        esac
        case ${machine_type} in
        ${CON_MACHINE_TYPE_HP})
            disk_dev="`echo ${partition_info} | awk -F "/" '{print $NF}' | sed "s p${partition_id}$  "`"
            harddisk_id="`echo ${disk_dev} | awk '{print substr($NF,length($NF),1)}'`"
            command="`printf "%d" "'${harddisk_id}"` - `printf "%d" "'0"`"
            disk_dev="`hwinfo --disk --short | awk '{print $1}' | grep -w "${disk_dev}"`"
        ;;
        *)
            disk_dev="`echo ${partition_info} | awk -F "/" '{print $NF}' | sed "s ${partition_id}$  "`"
            harddisk_id="`echo ${disk_dev} | awk '{print substr($NF,length($NF),1)}'`"
            command="`printf "%d" "'${harddisk_id}"` - `printf "%d" "'a"`"
            disk_dev="`hwinfo --disk --short | awk '{print $1}' | grep -w "${disk_dev}"`"
        ;;
        esac

    elif [ ! -z "`echo ${partition_info} | grep "^b"`" ]; then
        partition_id="`echo ${partition_name} | awk -F "/" '{print $NF}' | grep -oP "\d+$"`"
        case ${machine_type} in
        ${CON_MACHINE_TYPE_HP})
            disk_dev="`echo ${partition_name} | sed "s p${partition_id}$  "`"
            harddisk_id="`echo ${disk_dev} | awk -F "/" '{print substr($NF,length($NF),1)}'`"
            command="`printf "%d" "'${harddisk_id}"` - `printf "%d" "'0"`"
        ;;
        *)
            disk_dev="`echo ${partition_name} | sed "s ${partition_id}$  "`"
            harddisk_id="`echo ${disk_dev} | awk -F "/" '{print substr($NF,length($NF),1)}'`"
            command="`printf "%d" "'${harddisk_id}"` - `printf "%d" "'a"`"
        ;;
        esac
    else
        g_LOG_Error "${partition_name} is neither a link nor a block file."
        return 1
    fi

    harddisk_id="`expr ${command}`"

    if [ 1 -eq ${EFI_FLAG} ]; then
        partition_id="gpt${partition_id}"
    else
        partition_id="$(($partition_id - 1))"
    fi

    grub_info="${disk_dev} hd${harddisk_id} ${partition_id}"

    echo "${grub_info}"

    return 0
}

###########################################################
#    Description: copy modules
#    Parameter:   param1: kernel type
#    Return:      0:normal 1:abnormal
###########################################################
function DM_CopyModules()
{
    local kernel_type=$1

    local kernel_file=/etc/sysconfig/kernel
    local tmp_os_driver_path=/opt/driver/os
    local tmp_crash_driver_path=/opt/driver/crash
    local tmp_driver_path=
    local old_ko_lst=
    local new_ko_lst=
    local ko_name=
    local ko_count=
    local duplicate_drivers=()
    local kernel_version=

    if [ "${kernel_type}" != "${CON_KERNEL_TYPE_XEN}" ] \
        && [ "${kernel_type}" != "${CON_KERNEL_TYPE_DEFAULT}" ]; then
        kernel_type=${CON_KERNEL_TYPE_XEN}
    fi

    if [ "${kernel_type}" == "${CON_KERNEL_TYPE_XEN}" ]; then
        tmp_driver_path=${tmp_os_driver_path}
    else
        tmp_driver_path=${tmp_crash_driver_path}
    fi

    if [ -d ${tmp_driver_path} ]; then
        ko_count=`find ${tmp_driver_path} -name "*.ko" | wc -l`
        if [ $((ko_count)) -gt 0 ]; then
            #get kernel version
            kernel_version="`ls -l ${LOCAL_DISK_PATH}/${CON_LIB_MODULES_PATH} 2>&1 \
                | grep "${kernel_type}$" | awk '{print $NF}'`"
            if [ -z "${kernel_version}" ]; then
                g_LOG_Error "Can't find ${kernel_type} kernel."
                return 1
            fi
            export kernel_version

            #if addon driver for xen kernel exists
            for ko_file in `find ${tmp_driver_path} -name "*.ko"`
            do
                ko_name="`basename ${ko_file}`"
                #check if there are duplicate drivers
                for dup_ko in `find ${LOCAL_DISK_PATH}/${CON_LIB_MODULES_PATH}/${kernel_version} -name "${ko_name}"`
                do
                    duplicate_drivers[${#duplicate_drivers[*]}]=${dup_ko}
                done
                #get new ko list which would be used to make initrd
                ko_name="`echo ${ko_name} | sed 's/\.ko$//'`"
                new_ko_lst="${new_ko_lst} ${ko_name}"
            done

            #delete duplicate drivers
            g_LOG_Info "Duplicate drivers for ${kernel_version}, delete old ones."
            for dup_ko in ${duplicate_drivers[*]}
            do
                rm -f ${dup_ko}
                g_LOG_Info "${dup_ko} was deleted."
            done

	    #copy new drivers to xen kernel
            mkdir -p ${LOCAL_DISK_PATH}/${CON_LIB_MODULES_PATH}/${kernel_version}/${CON_ADDON_DRIVER_PATH}
	    if [ $? -ne 0 ]; then
                g_LOG_Error "make dir ${LOCAL_DISK_PATH}/${CON_LIB_MODULES_PATH}/${kernel_version}/${CON_ADDON_DRIVER_PATH} failed."
                return 1
            fi
            cp -a ${tmp_driver_path}/* \
                ${LOCAL_DISK_PATH}/${CON_LIB_MODULES_PATH}/${kernel_version}/${CON_ADDON_DRIVER_PATH}

            #depmod
            chroot ${LOCAL_DISK_PATH} >>${OTHER_TTY} 2>&1 << EOF
            depmod -a ${kernel_version}
EOF
            if [ $? -ne 0 ]; then
                g_LOG_Error "depmod for ${kernel_version} failed."
                return 1
            else
                g_LOG_Info "depmod for ${kernel_version} success."
            fi

            #update /etc/sysconfig/kernel for building initrd
            if [ "${kernel_type}" == "${CON_KERNEL_TYPE_XEN}" ]; then
                if [ ! -f ${LOCAL_DISK_PATH}/${kernel_file} ]; then
                    g_LOG_Error "${kernel_file} not found."
                    return 1
                fi

                old_ko_lst="`cat ${LOCAL_DISK_PATH}/${kernel_file} \
                    | grep "^INITRD_MODULES=" | awk -F '"' '{print $2}'`"
                g_LOG_Info "Old ko value is: ${old_ko_lst}"

                #remove duplicate ko
                new_ko_lst="`echo "${old_ko_lst} ${new_ko_lst}" \
                    | awk '{for (i=1;i<=NF;i++) print $i}' | sort | uniq | tr "\n" " " \
                    | sed 's/^[[:blank:]]*//' | sed 's/[[:blank:]]*$//'`"
                g_LOG_Info "New ko value is: ${new_ko_lst}"

                #replace old ko list with new one
                sed -i "s/^INITRD_MODULES=.*$/INITRD_MODULES=\"${new_ko_lst}\"/g" \
                    ${LOCAL_DISK_PATH}/${kernel_file}
            fi
        fi
    fi

    return 0
}

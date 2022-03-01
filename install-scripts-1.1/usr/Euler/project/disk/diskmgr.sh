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
 * Description: Create partitions, Format partitions, Mount partitions
!

#!/bin/bash

#config file
DM_DEFAULT_PARTITION_CONF=${LOCAL_TEMPCFG_PATH}/default.part
DM_NEW_PARTITION_CONF=${LOCAL_TEMPCFG_PATH}/new.part

#script to create partitions
DM_PARTITION_SCRIPT=${LOCAL_TEMPCFG_PATH}/partition.sh
#script to format partitions
DM_FORMAT_SCRIPT=${LOCAL_TEMPCFG_PATH}/format.sh

#disk device list
DM_DEVICE_NAMES=

#partition type
CON_PARTITION_TYPE_PRIMARY="primary"
CON_PARTITION_TYPE_EXTENDED="extended"
CON_PARTITION_TYPE_LOGICAL="logical"

#a partition must have 10MB space at least
CON_MIN_PARTITION_SIZE_MB=10
#root partition need 1G space at least
CON_MIN_ROOT_SIZE_MB=$((1*1024))

#partition table type msdos
CON_PARTITION_TABLE_MSDOS="msdos"
#partition table type gpt
CON_PARTITION_TABLE_GPT="gpt"

#over this size should use gpt, else use mbr
CON_MBR_LIMIT_DISK_SIZE=$((2**32))

#default sector size is 512Bytes
CON_DEFAULT_SECTOR_SIZE=512

#4K sector size is 4096Bytes
CON_4K_SECTOR_SIZE=4096

#boot partition num
DM_BOOTABLE_PARTITION_NUM=0

#install disk
DM_INSTALL_DISK=

#default disk scan timeout
DM_DEFAULT_DISK_SCAN_TIMEOUT=15

#mark for default.part which transformed from partition.conf
CON_DEFAULT_CONFIG_MARK="#defaultpart"

#mount old partition to this path to test if installed using default partition config
CON_TEST_DEFAULT_INSTALL_PATH=/mnt/default_test

#operation tag
#means it's an old partition
CON_OP_TAG_OLD="o"
#means it's a new partition
CON_OP_TAG_NEW="n"


#default partition number for add, delete, modify operation
CON_DEFAULT_PARTITION_NUMBER=9999

#max time to create partition devices in /dev/
CON_PARTITION_DEVICE_TIMEOUT=20
##########################################################
#    Description: translate partition size in partition.conf
#    Parameter:   param1: partition size in partition.conf
#    Return:      partition size(unit MB)
##########################################################
function DM_TranslateSize()
{
    local size=$1
    local size_MB=
    local unit=

    #input check
    if [ -z "${size}" ]; then
        g_LOG_Error "Input null, unknown size"
        return 1
    fi

    #percentage is not supported
    echo ${size} | grep "%" > /dev/null
    if [ $? -eq 0 ]; then
        g_LOG_Error "Percentage is not supported"
        return 1
    fi

    #keyword MAX
    echo "${size}" | grep -i "^MAX$" > /dev/null
    if [ $? -eq 0 ]; then
        echo "MAX"
        return 0
    fi

    #check if size is valid
    echo "${size}" | grep -iP "^[1-9]\d*[MGT]$" > /dev/null
    if [ $? -ne 0 ]; then
        g_LOG_Error "Invalid size specified for partition size."
        return 1
    fi

    #get unit
    unit="`echo ${size} | sed 's/[0-9]//g'`"
    #get size number
    size="`echo ${size} | sed 's/[a-zA-Z]//g'`"

    #translate by unit
    case ${unit} in
    M)
        size_MB=${size}
    ;;
    G)
        size_MB=$((size*1024))
    ;;
    T)
        size_MB=$((size*1024*1024))
    ;;
    *)
        g_LOG_Error "Only support size unit:M(MegaByte) G(GigaByte) T(TeraByte)."
        return 1
    ;;
    esac

    #check partition size, must larger than 10MB
    if [ $((size_MB)) -lt $((CON_MIN_PARTITION_SIZE_MB)) ]; then
        g_LOG_Error "Invalid partition size, should be more than 10MB."
        return 1
    fi

    echo "${size_MB}"

    return 0
}

##########################################################
#    Description: use sfdisk to get disk info
#    Parameter:   param1: disk device
#    Return:      cylinders heads sectors sector_count sector_size
##########################################################
function DM_GetDiskCHSInfoWithSfdisk()
{
    local disk_dev=$1

    local sfdisk_info=
    local cylinders=
    local heads_per_cylinder=
    local sectors_per_head=
    local sector_count=
    local sector_size=

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    #use sfdisk to get disk info
    sfdisk_info="`sfdisk -g ${disk_dev} 2>>${OTHER_TTY} | grep "^${disk_dev}"`"
    cylinders="`echo ${sfdisk_info} | awk '{print $2}'`"
    heads_per_cylinder="`echo ${sfdisk_info} | awk '{print $4}'`"
    sectors_per_head="`echo ${sfdisk_info} | awk '{print $6}'`"

    #check output
    if [ -z "`echo ${cylinders} | grep -P "^\d+$"`" ] \
        || [ -z "`echo ${heads_per_cylinder} | grep -P "^\d+$"`" ] \
        || [ -z "`echo ${sectors_per_head} | grep -P "^\d+$"`" ]; then
        g_LOG_Error "Use sfdisk to get CHS(cylinder head sector) information of ${disk_dev} failed."
        return 1
    fi

    sector_size="`sfdisk -luS ${disk_dev} 2>>${OTHER_TTY} | grep "sectors of" | awk '{print $5}'`"
    if [ -z "`echo ${sector_size} | grep -P "^[1-9]\d*$"`" ]; then
        sector_size=${CON_DEFAULT_SECTOR_SIZE}
    fi

    if [ $((cylinders)) -eq 0 ]; then
        g_LOG_Error "Cylinder count of ${disk_dev} is zero."
    elif [ $((heads_per_cylinder)) -eq 0 ]; then
        g_LOG_Error "Head count per cylinder of ${disk_dev} is zero."
    elif [ $((sectors_per_head)) -eq 0 ]; then
        g_LOG_Error "Sector count per head of ${disk_dev} is zero."
    else
        #return chs info
        sector_count=$((cylinders * heads_per_cylinder * sectors_per_head))
        echo "${cylinders} ${heads_per_cylinder} ${sectors_per_head} ${sector_count} ${sector_size}"
        return 0
    fi

    return 1
}

##########################################################
#    Description: use parted to get disk info
#    Parameter:   param1: disk device
#    Return:      cylinders heads sectors sector_count sector_size
##########################################################
function DM_GetDiskCHSInfoWithParted()
{
    local disk_dev=$1
    local parted_info=
    local cylinders=
    local heads_per_cylinder=
    local sectors_per_head=
    local sector_count=
    local sector_size=

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    #use parted to get disk info
    parted_info="`parted ${disk_dev} -s unit chs p 2>>${OTHER_TTY} \
        | grep -i "cylinder,head,sector" | awk '{print $4}' | sed 's/\.$//'`"
    cylinders="`echo ${parted_info} | awk -F "," '{print $1}'`"
    heads_per_cylinder="`echo ${parted_info} | awk -F "," '{print $2}'`"
    sectors_per_head="`echo ${parted_info} | awk -F "," '{print $3}'`"

    #check output
    if [ -z "`echo ${cylinders} | grep -P "^\d+$"`" ] \
        || [ -z "`echo ${heads_per_cylinder} | grep -P "^\d+$"`" ] \
        || [ -z "`echo ${sectors_per_head} | grep -P "^\d+$"`" ]; then
        g_LOG_Error "Use parted to get CHS(cylinder head sector) information of ${disk_dev} failed."
        return 1
    fi

    sector_size=`parted ${disk_dev} -s p 2>&1 | grep -i "^sector size" \
        | awk -F "/" '{print $2}' | awk -F " " '{print $NF}' | sed 's/[a-zA-Z]//g'`
    if [ -z "`echo ${sector_size} | grep -P "^[1-9]\d*$"`" ]; then
        sector_size=${CON_DEFAULT_SECTOR_SIZE}
    fi

    if [ $((cylinders)) -eq 0 ]; then
        g_LOG_Error "Cylinder count of ${disk_dev} is zero."
    elif [ $((heads_per_cylinder)) -eq 0 ]; then
        g_LOG_Error "Head count per cylinder of ${disk_dev} is zero."
    elif [ $((sectors_per_head)) -eq 0 ]; then
        g_LOG_Error "Sector count per head of ${disk_dev} is zero."
    else
        #return chs info
        sector_count=$((cylinders * heads_per_cylinder * sectors_per_head))
        echo "${cylinders} ${heads_per_cylinder} ${sectors_per_head} ${sector_count} ${sector_size}"
        return 0
    fi

    return 1
}

###########################################################
#    Description: get cylinder size
#    Parameter:   param1: disk device
#    Return:      cylinder size
###########################################################
function DM_GetCylinderSize()
{
    local disk_dev=$1
    local cylinder_size=
    local chs_info=
    local heads=
    local sectors=
    local sector_size=

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    chs_info="`DM_GetDiskCHSInfoWithParted ${disk_dev}`"
    if [ $? -ne 0 ]; then
        return 1
    fi
    heads=`echo ${chs_info} | awk '{print $2}'`
    sectors=`echo ${chs_info} | awk '{print $3}'`
    sector_size=`echo ${chs_info} | awk '{print $5}'`

    cylinder_size=$((heads*sectors*sector_size))
    echo "${cylinder_size}"

    return 0
}

###########################################################
#    Description: use parted to get disk size
#    Parameter:   param1: disk device
#    Return:      disk size
###########################################################
function DM_GetDiskSize()
{
    local disk_dev=$1
    local disk_size=
    local sector_count=
    local sector_size=

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    #get disk size(unit MB)
    chs_info="`DM_GetDiskCHSInfoWithParted ${disk_dev}`"
    if [ $? -ne 0 ]; then
        return 1
    fi
    sector_count=`echo ${chs_info} | awk '{print $4}'`
    sector_size=`echo ${chs_info} | awk '{print $5}'`

    disk_size=$((sector_count*sector_size/1024/1024))
    if [ $((disk_size)) -eq 0 ]; then
        g_LOG_Error "Disk size of ${disk_dev} is zero."
        return 1
    fi

    echo "${disk_size}"

    return 0
}

##########################################################
#    Description: format partition.conf,generate default.part
#    Parameter:   param1: partition config file
#    Return:      0-success, 1-failed
##########################################################
function DM_FormatPartitionConf()
{
    local partition_config_file=$1
    local temp_config_file=/opt/partition_config_`date '+%s'`
    local temp_detail_file=/opt/partition_detail_`date '+%s'`

    local partition_name=
    local start_pos="-"
    local end_pos="-"
    local partition_size=
    local partition_type=
    local partition_filesystem=
    local mount_point=
    local is_format="NO"
    local tag=${CON_OP_TAG_NEW}
    local arch="$(uname -m)"

    local hd_disk_num=0
    local partition_count=0

    local efi_partition=
    local chs_info=
    local sector_count=
    local sector_size=

    #init default partition config file
    rm -rf ${DM_DEFAULT_PARTITION_CONF}
    mkdir -p `dirname ${DM_DEFAULT_PARTITION_CONF}`
    if [ $? -ne 0 ]; then
        g_LOG_Error "make dir `dirname ${DM_DEFAULT_PARTITION_CONF}` failed"
        return 1
    fi
    echo "${CON_DEFAULT_CONFIG_MARK}" > ${DM_DEFAULT_PARTITION_CONF}
    rm -rf ${temp_config_file}
    rm -rf ${temp_detail_file}

    #During UEFI boot, an ESP is required, otherwise the installation fails
    if [ 1 -eq ${EFI_FLAG} ]; then
        efi_partition=`cat ${partition_config_file} | grep -w " /boot/efi "`
        if [ -z "${efi_partition}" ]; then
            if [ "x${arch}" == "xaarch64" ]; then
                g_LOG_Error "UEFI boot, there must be a /boot/efi partition as ESP for boot."
                return 1
            else
                BOOT_ESP="true"
            fi
        else
            BOOT_ESP="false"
        fi
    fi

    for disk_dev in ${DM_DEVICE_NAMES}
    do
        chs_info="`DM_GetDiskCHSInfoWithParted ${disk_dev}`"
        if [ $? -ne 0 ]; then
            g_LOG_Warn "Get disk ${disk_dev} CHS info failed"
            return 1
        fi
        sector_count=`echo ${chs_info} | awk '{print $4}'`
        sector_size=`echo ${chs_info} | awk '{print $5}'`

        #check if device is a harddisk
        disk_name="`echo ${disk_dev} | awk -F "/" '{print $NF}'`"
        if [ -z "`cat /proc/partitions | grep ${disk_name}`" ]; then
            g_LOG_Warn "Device ${disk_name} is not a disk."
            continue
        fi

        #filter comment and blank lines
        cat "${partition_config_file}" | sed 's/^[[:blank:]]*#.*$//g' | sed /^[[:blank:]]*$/d | \
            grep -w "hd${hd_disk_num} " > ${temp_config_file}
        hd_disk_num=$((hd_disk_num+1))
        g_LOG_Info "disk num ${hd_disk_num}(${disk_dev}) partition parse..."
        partition_count=0
        while read LINE
        do
            if [ -z "${LINE}" ]; then
                continue
            fi

            partition_count=$((partition_count+1))
            partition_name="`DM_GetPartitionName ${disk_dev} ${partition_count}`"
            if [ $? -ne 0 ] || [ -z "${partition_name}" ]; then
                g_LOG_Error "Failed to get partition name."
                return 1
            fi

            g_LOG_Info "Install disk DM_INSTALL_DISK=${disk_dev}."
            DM_INSTALL_DISK=${disk_dev}

            if [ "${sector_size}" -eq "${CON_4K_SECTOR_SIZE}" ]; then
                #During UEFI boot, an ESP is required, otherwise the installation fails
                if [ 1 -ne ${EFI_FLAG} ]; then
                    g_LOG_Error "4K sector disk, you must choice UEFI boot."
                    return 1
                fi
            fi

            mount_point="`echo "${LINE}" | awk '{print $2}'`"
            partition_size="`echo "${LINE}" | awk '{print $3}' | tr [a-z] [A-Z]`"
            partition_type="`echo "${LINE}" | awk '{print $4}' | tr [A-Z] [a-z]`"
            partition_filesystem="`echo "${LINE}" | awk '{print $5}' | tr [A-Z] [a-z]`"
            is_format="`echo "${LINE}" | awk '{print $6}' | tr [a-z] [A-Z]`"
            if [ -z "${is_format}" ]; then
                is_format="NO"
                g_LOG_Info "Disk format not set, default is NO"
            fi

	    #By default, only / , /boot and /boot/efi partitions are formatted
	    if [ "${mount_point}" == "/boot" ] || [ "${mount_point}" == "/" ] || [ "${mount_point}" == "/boot/efi" ]; then
                is_format="YES"
                g_LOG_Info "root and boot partition default to format"
            fi

            #During UEFI boot, the file system format of boot partition is FAT16.
            #It will be reported that FAT32 is not supported through grub2-probe detection
            if [ "${mount_point}" == "/boot/efi" ] && [ 1 -eq ${EFI_FLAG} ]; then
                g_LOG_Info "UEFI boot, modify /boot/efi partition filesystem to fat16."
                partition_filesystem="fat16"
            fi

	    #UEFI x86, if no /boot/efi, choose /boot as ESP partition
            if [ "${mount_point}" == "/boot" ] && [ "x${BOOT_ESP}" == "xtrue" ]; then
                g_LOG_Info "UEFI boot, modify /boot partition filesystem to fat16."
                partition_filesystem="fat16"
            fi

            g_LOG_Info "partition conf: mount_point=${mount_point} partition_size=${partition_size} partition_type=${partition_type} partition_filesystem=${partition_filesystem} is_format=${is_format}"
	    #extended partition doesn't need size, filesystem, mount point
            if [ "${partition_type}" == "${CON_PARTITION_TYPE_EXTENDED}" ]; then
                partition_size="-"
                partition_filesystem="-"
                mount_point="-"
                g_LOG_Info "Type is Extended partition"
                if [ $((sector_count)) -gt $((CON_MBR_LIMIT_DISK_SIZE)) ] || [ 1 -eq ${EFI_FLAG} ]; then
                    partition_count=$((partition_count-1))
                    g_LOG_Notice "sector count ${sector_count} is too large or EFI boot, continue"
                    continue
                fi
            else
                partition_size="`DM_TranslateSize ${partition_size}`"
                if [ $? -ne 0 ]; then
                    g_LOG_Error "DM_TranslateSize failed"
                    return 1
                elif [ -z "`echo ${partition_size} | grep -iw "max"`" ]; then
                    partition_size="${partition_size}M"
                fi
            fi
            g_LOG_Info "partition size ${partition_size}"
            #write to config file
            printf "%s %s %s %s %s %s %s %s %s\n" \
                ${partition_name} ${start_pos} ${end_pos} ${partition_size} \
                ${partition_type} ${partition_filesystem} ${mount_point} \
                ${is_format} ${tag} >> ${temp_detail_file}

        done < ${temp_config_file}
    done

    #move tempory config file to default.part
    rm -f ${temp_config_file}
    if [ -f ${temp_detail_file} ]; then
        cat ${temp_detail_file} >> ${DM_DEFAULT_PARTITION_CONF}
        rm -f ${temp_detail_file}
    fi

    return 0
}

##########################################################
#    Description: init disk's partition table
#    Parameter:   param1: disk device
#    Return:      0-success, 1-failed
##########################################################
function DM_InitPartitionTable()
{
    local disk_dev=$1
    local chs_info=
    local sector_count=
    local sector_size=

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    chs_info="`DM_GetDiskCHSInfoWithSfdisk ${disk_dev}`"
    if [ $? -ne 0 ]; then
        g_LOG_Error "DM_GetDiskCHSInfoWithSfdisk ${disk_dev} failed"
        return 1
    fi
    sector_count=`echo ${chs_info} | awk '{print $4}'`

    if [ 1 -eq ${EFI_FLAG} ]; then
        #In UEFI mode, GPT is required
        parted ${disk_dev} -s mklabel ${CON_PARTITION_TABLE_GPT} >> ${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "Init partition table of ${disk_dev} to gpt failed."
            return 1
        fi
    elif [ $((sector_count)) -le $((CON_MBR_LIMIT_DISK_SIZE)) ]; then
        #if sector count less than 2^32 then use msdos partition table
        parted ${disk_dev} -s mklabel ${CON_PARTITION_TABLE_MSDOS} >> ${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "Init partition table of ${disk_dev} to msdos failed."
            return 1
        fi
    else
        #if sector count more than 2^32 then use gpt partition table
        parted ${disk_dev} -s mklabel ${CON_PARTITION_TABLE_GPT} >> ${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "Init partition table of ${disk_dev} to gpt failed."
            return 1
        fi
    fi

    return 0
}

##########################################################
#    Description: copy new.part file in order to compare
#                 partition conf
#    Parameter:   param1: new.part file
#    Return:      0-success, 1-failed
##########################################################
function DM_CopyPartitionConf()
{
    local part_file=$1
    #temp_part_file is part info from old new.part
    #temp_target_file is new partition info for new.part
    local temp_part_file=/opt/temp_part_`date '+%s'`
    local temp_target_file=/opt/temp_target_`date '+%s'`

    rm -rf ${temp_part_file}
    rm -rf ${temp_target_file}

    cat "${part_file}" | sed 's/^[[:blank:]]*#.*$//g' \
        | sed /^[[:blank:]]*$/d | awk '{print $1,$4,$5,$7}' > ${temp_part_file}

    while read line
    do
        partition_name="`echo ${line} | awk '{print $1}'`"
	partition_size="`echo ${line} | awk '{print $2}'`"

	partition_info="`lsblk -n ${partition_name} 2>>${OTHER_TTY}`"
	if [ -z "${partition_info}" ]; then
            g_LOG_Warn "partition not found when copy the partition conf"
	    return 1
        fi
        partition_size="`echo ${partition_info} | awk '{print $4}'`"
	echo "${line}" | awk '{print $1,"'${partition_size}'",$3,$4}' >> ${temp_target_file}

    done < ${temp_part_file}

    mv ${temp_target_file} ${part_file}
    if [ $? -ne 0 ]; then
        g_LOG_Warn "mv temp_target_file to new.part failed"
        return 1
    fi

    rm -rf ${temp_part_file}
    rm -rf ${temp_target_file}

    return 0
}

#########################################################
#    Description: check current disk partition that has
#                 been modified
#    Parameter:   param1: old new.part file
#    Return:      0-success, 1-failed
#########################################################
function DM_IsDiskPartitionChanged()
{
    local old_part_file=$1
    local install_disk=${DM_INSTALL_DISK}
    local partition_name=
    local partition_size=
    local partition_type=
    local partition_num=

    local current_partition_info=
    local current_partition_size=
    local current_partition_num=

    if [ -z "${install_disk}" ]; then
        g_LOG_Info "current install disk is not found"
        echo "false"
        return 1
    fi

    #partition_num:/etc/new.part, static conf for pre install
    #current_partition_num: current partition num in disk
    #partition_conf_num:current partition num in conf
    partition_num="`cat ${old_part_file} | wc -l`"
    current_partition_num="`parted -s ${install_disk} print 2>>/dev/null | grep -E \"^ +[0-9]+ |^[0-9]+ \" | wc -l`"
    partition_conf_num="`cat ${PARTITION_CONF} | wc -l`"

    if [ -n "`cat ${PARTITION_CONF} | grep extended`" ] && [ ${EFI_FLAG} -eq 1 ]; then
        partition_conf_num=$(($partition_conf_num-1))
    fi

    g_LOG_Debug "partition_num:${partition_num}, current_partition_num:${current_partition_num}, partition_conf_num:${partition_conf_num}"

    if [ "x${partition_num}" != "x${current_partition_num}" ] || [ "x${partition_conf_num}" != "x${current_partition_num}" ]; then
        g_LOG_Info "disk partition num had been changed, not use old new.part"
        echo "false"
        return 0
    fi

    while read line
    do
        if [ -z "${line}" ]; then
            continue
        fi

        partition_name="`echo ${line} | awk '{print $1}'`"
	partition_size="`echo ${line} | awk '{print $2}'`"
	partition_type="`echo ${line} | awk '{print $3}'`"

	current_partition_info="`lsblk -n ${partition_name} 2>>${OTHER_TTY}`"
	if [ -z "${current_partition_info}" ]; then
            g_LOG_Info "disk partition had been modified, not use old new.part"
            echo "false"
            return 0
        else
            if [ "${partition_type}" == "${CON_PARTITION_TYPE_EXTENDED}" ]; then
                if [ 1 -ne ${EFI_FLAG} ]; then
                    #if disk is gpt, we don't have extended partition
		    #if disk is msdos, we have extended partition
		    g_LOG_Info "extended partition don't need to compare size"
		    continue
                else
                    echo "false"
                    return 1
                fi
            fi
            if [ -z "`echo ${partition_size} | grep -iw 'max'`" ]; then
                current_partition_size="`echo ${current_partition_info} | awk '{print $4}'`"
                g_LOG_Notice "current_partition_size:${current_partition_size}"
                g_LOG_Notice "partition_size:${partition_size}"

	        if [ "x${current_partition_size}" != "x${partition_size}" ]; then
                    g_LOG_Info "current disk partition and old new.part are difference"
                    echo "false"
                    return 0
	        else
                    continue
                fi
            fi
        fi
    done < ${old_part_file}

    echo "true"
    return 0
}

##########################################################
#    Description: Confirm old partitions, decide if need
#                 to create and format all partitions
#    Parameter:   none
#    Return:      0-success, 1-failed
##########################################################
function DM_ConfirmOldPartitions()
{
    local temp_new_part_file=/opt/new_part_`date '+%s'`
    local temp_old_part_file=/opt/old_part_`date '+%s'`
    local default_mark_file=${CON_TEST_DEFAULT_INSTALL_PATH}/etc/new.part
    local default_partition_conf=${CON_TEST_DEFAULT_INSTALL_PATH}/usr/Euler/conf/partition.conf

    local root_index=0
    local partition_info=
    local partition_name=
    local partition_filesystem=
    local default_flg="true"
    local tLsblk="`which lsblk`"

    mkdir -p ${CON_TEST_DEFAULT_INSTALL_PATH}
    if [ $? -ne 0 ]; then
        g_LOG_Error "make dir ${CON_TEST_DEFAULT_INSTALL_PATH} failed"
        return 1
    fi
    rm -rf ${temp_new_part_file}
    rm -rf ${temp_old_part_file}

    #get partition name, size, type, filesystem, mount point
    cat "${DM_NEW_PARTITION_CONF}" | sed 's/^[[:blank:]]*#.*$//g' \
        | sed /^[[:blank:]]*$/d | awk '{print $1,$4,$5,$7}' > ${temp_new_part_file}

    #get root partition index
    root_index=`cat ${temp_new_part_file} | awk '{print $NF}' | grep -n "^/$" \
        | awk -F ":" '{print $1}'`

    #check if root partition exsits
    local install_product=
    install_product="`cat /proc/cmdline | grep -w "product=mbsc"`"
    if [ -z "${install_product}" ]; then
        if [ -z "${root_index}" ] || [ $((root_index)) -lt 1 ]; then
            g_LOG_Error "Default partition config file doesn't contain root partition."
            return 1
        fi
    else
        g_LOG_Info "install product is mbsc, don't need root partition."
    fi

    #get partition name and file system
    partition_info="`cat ${DM_NEW_PARTITION_CONF} | sed 's/^[[:blank:]]*#.*$//g' \
        | sed /^[[:blank:]]*$/d | sed -n "${root_index}p"`"
    partition_name="`echo ${partition_info} | awk '{print $1}'`"
    partition_filesystem="`echo ${partition_info} | awk '{print $6}'`"

    g_LOG_Debug "root index is : ${root_index}, root partition info is: ${partition_info}"

    #try to mount old partition
    mount -t ${partition_filesystem} ${partition_name} \
        ${CON_TEST_DEFAULT_INSTALL_PATH} > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        #mount failed, not use default config
       g_LOG_Info "mount failed, not use default config"
        default_flg="false"
    elif [ ! -f ${default_mark_file} ]; then
        #new.part doesn't exist, not use default config
        g_LOG_Info "new.part doesn't exist, not use default config"
        default_flg="false"
    elif [ -z "${tLsblk}" ]; then
        #current product don't contain lsblk command
        g_LOG_Info "current product don't contain lsblk command, not use default config."
        default_flg="false"
    else
        #compare old new.part and current new.part
        g_LOG_Info "compare old new.part and current new.part"

        cat ${default_mark_file} | sed 's/^[[:blank:]]*#.*$//g' \
            | sed /^[[:blank:]]*$/d | awk '{print $1,$2,$3,$4}' > ${temp_old_part_file}

        #compare current disk partition and old new.part
        #if old new.part and current disk partition conf are difference
        #it shows that current disk partition had been modified, we use current new.part
        #if old new.part and current disk partition conf are same
        #we user old new.part
        default_flg="`DM_IsDiskPartitionChanged ${temp_old_part_file}`"
        if [ $? -ne 0 ]; then
            g_LOG_Info "gpt partition don't have extended partition"
            default_flg="false"
	fi

        if [ "${default_flg}" = "true" ]; then
            diff ${PARTITION_CONF} ${default_partition_conf} > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                g_LOG_Info "current partition.conf and disk partition.conf is diff"
                default_flg="false"
            fi
        fi
    fi

    #installed using default config
    echo "${CON_DEFAULT_CONFIG_MARK}" >${temp_new_part_file}
    if [ "${default_flg}" = "true" ]; then
        g_LOG_Info "Installed using default config ${DM_NEW_PARTITION_CONF}."
        cat ${DM_NEW_PARTITION_CONF} | sed 's/^[[:blank:]]*#.*$//g' \
            | sed /^[[:blank:]]*$/d | awk '{print $1,"0","0",$4,$5,$6,$7,$8,"o"}' \
            >> ${temp_new_part_file}
        mv ${temp_new_part_file} ${DM_NEW_PARTITION_CONF}
    fi

    g_LOG_Debug "`cat ${DM_NEW_PARTITION_CONF}`"

    rm -f ${temp_new_part_file}
    rm -f ${temp_old_part_file}

    #umount old partition
    if mount | grep ${CON_TEST_DEFAULT_INSTALL_PATH} >/dev/null 2>&1; then
        umount -v ${CON_TEST_DEFAULT_INSTALL_PATH} >> ${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
                g_LOG_Error "Can't umount old partition."
                return 1
    	fi
    fi
    rm -rf ${CON_TEST_DEFAULT_INSTALL_PATH}

    return 0
}

###############################################################
#    Description: verify default.part
#    Parameter:   param1: disk device
#    Return:      0-success, 1-failed
###############################################################
function DM_VerifyPartitionConfAfter()
{
    local disk_dev=$1

    local partition_size=
    local partition_type=
    local total_size=0

    local small_root_flag=1
    local mount_point=
    local root_partition_size=-1

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    if [ -z "`cat ${DM_DEFAULT_PARTITION_CONF} | sed 's/^[[:blank:]]*#.*$//g' | sed /^[[:blank:]]*$/d`" ]; then
        g_LOG_Error "Generate default.part failed! Please check partition config."
        return 1
    fi

    #get disk size(unit MB)
    disk_size="`DM_GetDiskSize ${disk_dev}`"
    if [ $? -ne 0 ]; then
	    return 1
    fi

    while read LINE
    do
        if [ -z "${LINE}" ]; then
            continue
        fi

        partition_size="`echo ${LINE} | awk '{print $4}' | sed 's/M$//'`"
        partition_type="`echo ${LINE} | awk '{print $5}'`"
        mount_point="`echo ${LINE} | awk '{print $7}'`"

        if [ "${partition_type}" = "${CON_PARTITION_TYPE_EXTENDED}" ]; then
            continue
        fi

        if [ "${mount_point}" = "/" ]; then
            root_partition_size=${partition_size}
        fi

        if [ ! -z "`echo ${partition_size} | grep -i "MAX"`" ]; then
            continue
        fi

        total_size=$((total_size + partition_size))
    done < ${DM_DEFAULT_PARTITION_CONF}

    #check if total size larger than real disk size
    if [ $((total_size)) -gt $((disk_size)) ]; then
        g_LOG_Error "Disk space ${disk_size} is not enough for your partition config ${total_size}."
        return 1
    fi

    #check if root partition size larger than 1G
    if [ ! -z "`echo ${root_partition_size} | grep -i "MAX"`" ]; then
        if [ $((disk_size - total_size)) -lt $((CON_MIN_ROOT_SIZE_MB)) ]; then
            small_root_flag=0
        fi
    elif [ $((root_partition_size)) -ne -1 ] \
        && [ $((root_partition_size)) -lt $((CON_MIN_ROOT_SIZE_MB)) ]; then
        small_root_flag=0
    fi

    if [ ${small_root_flag} -eq 0 ]; then
        g_LOG_Error "Insufficient space allocated for the root partition. At least 1GB is required."
        return 1
    fi

    return 0
}

##############################################################
#    Description: generate format script
#    Parameter:   param1: partition name
#                 param2: partition filesystem
#    Return:      0-success, 1-failed
##############################################################
function DM_GenFormatScript()
{
    local partition_name=$1
    local partition_filesystem=$2

    if [ -z "${partition_name}" ]; then
        g_LOG_Error "Input null, unknown partition name."
        return 1
    fi

    if [ -z "${partition_filesystem}" ]; then
        g_LOG_Error "Input null, unknown filesystem."
        return 1
    fi

    if [ ! -f "${DM_FORMAT_SCRIPT}" ]; then
        g_LOG_Error "Script for formatting partition lost."
        return 1
    fi

    g_LOG_Info "generate format script for partition_name=${partition_name}, partition_filesystem=${partition_filesystem}"

    case ${partition_filesystem} in
    ext2)
        echo "mke2fs -F ${partition_name}" >> ${DM_FORMAT_SCRIPT}
        echo "tune2fs -c -1 ${partition_name}" >> ${DM_FORMAT_SCRIPT}
    ;;
    ext3)
        echo "mke2fs -F -j ${partition_name}" >> ${DM_FORMAT_SCRIPT}
        echo "tune2fs -c -1 ${partition_name}" >> ${DM_FORMAT_SCRIPT}
    ;;
    ext4)
        echo "mke2fs -F -t ext4 ${partition_name}" >> ${DM_FORMAT_SCRIPT}
        echo "tune2fs -c -1 ${partition_name}" >> ${DM_FORMAT_SCRIPT}
    ;;
    fat32)
        echo "mkdosfs -F 32 ${partition_name}" >> ${DM_FORMAT_SCRIPT}
    ;;
    fat16)
        echo "mkdosfs -F 16 ${partition_name}" >> ${DM_FORMAT_SCRIPT}
    ;;
    swap)
        echo "mkswap ${partition_name}" >> ${DM_FORMAT_SCRIPT}
    ;;
    *)
    ;;
    esac

    return 0
}

############################################################
#    Description: remove lvm partitions
#    Parameter:   param1: disk device
#    Return:      0-success, 1-failed
############################################################
function DM_RemoveLVMPartition()
{
    local install_disk=$1
    local tmp_lvmlist=/opt/tmp_lvmlist_`date '+%s'`
    local tmp_vglist=/opt/tmp_vglist_`date '+%s'`
    local tmp_pvlist=/opt/tmp_pvlist_`date '+%s'`

    rm -rf ${tmp_lvmlist}
    rm -rf ${tmp_vglist}
    rm -rf ${tmp_pvlist}

    #remove lv
    lvscan 2>/dev/null | awk -F "'" '{print $2}' > ${tmp_lvmlist}
    while read item1
    do
        if [ -z "${item1}" ]; then
            continue
        fi

        g_LOG_Debug "starting remove lvm_disk ${item1}"
        lvremove -f ${item1} >>${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Warn "lvremove -f ${item1} failed"
        fi
        sleep 1
    done < ${tmp_lvmlist}

    #remove vg
    vgscan 2>/dev/null | grep lvm | awk -F '"' '{print $2}' > ${tmp_vglist}
    while read item2
    do
        if [ -z "${item2}" ]; then
            continue
        fi

        g_LOG_Debug "starting remove vg_disk ${item2}"
        vgremove -f ${item2} >>${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Warn "vgremove -f ${item2} failed"
        fi
        sleep 1
    done < ${tmp_vglist}

    pvscan 2>/dev/null | grep lvm | awk -F ' ' '{print $2}' > ${tmp_pvlist}
    while read item3
    do
        if [ -z "${item3}" ]; then
             continue
        fi

        g_LOG_Debug "starting remove pv_disk ${item3}"
        pvremove -ff -y ${item3} >>${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Warn "pvremove -ff -y ${item3} failed"
        fi
        sleep 1
    done < ${tmp_pvlist}

    return 0
}

##########################################################
#    Description: generate partition and format script
#    Parameter:   param1: disk device
#                 param2: file contains new partition settings
#                 param3: file contains old partition info
#    Return:      0-success, 1-failed
##########################################################
function DM_GenPartitionScript()
{
    local disk_dev=$1
    local new_detail_file=$2
    local err_msg=/opt/err_msg_`date '+%s'`

    local chs_info=
    local sector_count=
    local sector_size=
    local physical_sector_size=
    local cylinder_size=
    local disk_cyl=
    local allocated_cyl=0
    local end_cyl=
    local new_part_num=${CON_DEFAULT_PARTITION_NUMBER}
    local min_redo_part_num=
    local partition_table=
    local command=

    local partition_name=
    local start_pos=
    local end_pos=
    local partition_size=
    local partition_type=
    local partition_filesystem=
    local mount_point=
    local is_format=
    local tag=
    local partition_num=
    local partition_cyl=
    local boot_partition_num=0
    local root_partition_num=0

    #input check
    if [ -z "${disk_dev}" ] || [ ! -b "${disk_dev}" ]; then
        g_LOG_Error "Can't find disk ${disk_dev}."
        return 1
    fi

    if [ -z "${new_detail_file}" ] || [ ! -f "${new_detail_file}" ]; then
        g_LOG_Error "Can't find new partition config file."
        return 1
    fi

    #get min partition num of new partitions
    partition_name="`cat ${new_detail_file} | awk '{print $1,$9}' \
            | grep -w "${CON_OP_TAG_NEW}" | head -n 1 | awk '{print $1}'`"
    if [ ! -z "${partition_name}" ]; then
        new_part_num="`DM_GetPartitionNumber ${disk_dev} ${partition_name}`"
        if [ $? -ne 0 ] || [ -z "`echo ${new_part_num} | grep -P "^\d+$"`" ]; then
            g_LOG_Error "Unrecognized partition name \"${partition_name}\"."
            return 1
        fi
    fi

    #get min partition num of new_part_num
    min_redo_part_num=${new_part_num}
    g_LOG_Debug "new_part_num=${new_part_num}, min_redo_part_num=${min_redo_part_num}"

    #try to get disk info using parted
    parted ${disk_dev} -s unit cyl p >${err_msg} 2>&1
    if [ $? -ne 0 ]; then
        cat ${err_msg} | grep -i "${CON_UNKNOWN_DISK_LABEL}" > /dev/null
        if [ $? -eq 0 ] || [ $((min_redo_part_num)) -eq 1 ]; then
            #if partition table is not inited, do init it
            #if all new partitions, do init partition table
            g_LOG_Info "Init partition table on ${disk_dev}."
            DM_InitPartitionTable ${disk_dev}
            if [ $? -ne 0 ]; then
                g_LOG_Warn "Init partition table of ${disk_dev} failed."
                return 0
            else
                g_LOG_Info "Init partition table of ${disk_dev} successful."
            fi
        else
            #get disk size failed due to other reasons
            g_LOG_Warn "Read partition information of ${disk_dev} failed."
            cat ${err_msg} >>${OTHER_TTY}
            return 0
        fi
    fi

    if [ $((min_redo_part_num)) -ne $((CON_DEFAULT_PARTITION_NUMBER)) ]; then
        DM_InitPartitionTable ${disk_dev}
    fi

    chs_info="`DM_GetDiskCHSInfoWithParted ${disk_dev}`"
    if [ $? -ne 0 ]; then
        return 1
    fi
    sector_count=`echo ${chs_info} | awk '{print $4}'`
    disk_cyl=`echo ${chs_info} | awk '{print $1}'`
    sector_size=`echo ${chs_info} | awk '{print $5}'`
    physical_sector_size=`parted ${disk_dev} -s p 2>&1 | grep -i "^sector size" \
        | awk -F "/" '{print $NF}' | sed 's/[a-zA-Z]//g'`
    if [ -z "`echo ${physical_sector_size} | grep -P "^[1-9]\d*$"`" ]; then
        physical_sector_size=${CON_DEFAULT_SECTOR_SIZE}
    fi

    #get cylinder size
    cylinder_size="`DM_GetCylinderSize ${disk_dev}`"
    if [ $? -ne 0 ]; then
        g_LOG_Error "Failed to get cylinder size of ${disk_dev}."
        return 1
    fi

    g_LOG_Debug "chs_info=${chs_info}, sector_count=${sector_count}, disk_cyl=${disk_cyl}, cylinder_size=${cylinder_size}"
    #generate create and format script for new partitions
    g_LOG_Info "generate create and format script for new partitions."
    g_LOG_Debug "new_detail_file content is `cat ${new_detail_file}`"
    while read LINE
    do
        if [ -z "${LINE}" ]; then
            continue
        fi

        partition_name="`echo ${LINE} | awk '{print $1}'`"
        start_pos="`echo ${LINE} | awk '{print $2}'`"
        end_pos="`echo ${LINE} | awk '{print $3}'`"
        partition_size="`echo ${LINE} | awk '{print $4}' | sed 's/M$//'`"
        partition_type="`echo ${LINE} | awk '{print $5}'`"
        partition_filesystem="`echo ${LINE} | awk '{print $6}'`"
        mount_point="`echo ${LINE} | awk '{print $7}'`"
        is_format="`echo ${LINE} | awk '{print $8}'`"
        tag="`echo ${LINE} | awk '{print $9}'`"

        #get partition number
        partition_num=`DM_GetPartitionNumber ${disk_dev} ${partition_name}`
        if [ $? -ne 0 ] || [ -z "`echo ${partition_num} | grep -P "^\d+$"`" ]; then
            g_LOG_Error "Unrecognized partition name \"${partition_name}\"."
            return 1
        fi

        #get boot partition number
        if [ "${mount_point}" = "/boot/efi" ]; then
            boot_partition_num=${partition_num}
        elif [ "${mount_point}" = "/boot" ] && ! grep "/boot/efi" ${PARTITION_CONF} >/dev/null ; then
            root_partition_num=${partition_num}
        fi

        if [ $((partition_num)) -lt $((min_redo_part_num)) ]; then
            if [ "${partition_type}" != "${CON_PARTITION_TYPE_EXTENDED}" ]; then
                if [ -z "`echo ${is_format} | grep -iw "no"`" ]; then
                    g_LOG_Info "$((partition_num)) -lt $((min_redo_part_num)) is_format is yes, execute DM_GenFormatScript"
                    DM_GenFormatScript ${partition_name} ${partition_filesystem}
                    if [ $? -ne 0 ]; then
                        g_LOG_Error "Generate script for formatting partition failed."
                        return 1
                    fi
                fi
                allocated_cyl=$((end_pos+1))
            fi
        else
            #use all left size to create extended partition
            if [ "${partition_type}" = "${CON_PARTITION_TYPE_EXTENDED}" ]; then
                if [ 1 -ne ${EFI_FLAG} ] && [ $((sector_count)) -le $((CON_MBR_LIMIT_DISK_SIZE)) ]; then
                    if [ -z "${PARTITION_ALIGNMENT}" ]; then
                        printf "parted %s -s mkpart %s %s %s\n" \
                            ${disk_dev} ${CON_PARTITION_TYPE_EXTENDED} \
                            "${allocated_cyl}cyl" "$((disk_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                    else
                        printf "parted %s -s -a %s mkpart %s %s %s\n" \
                            ${disk_dev} ${PARTITION_ALIGNMENT} ${CON_PARTITION_TYPE_EXTENDED} \
                            "${allocated_cyl}cyl" "$((disk_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                    fi
                fi
                continue
            fi

            DM_GenFormatScript ${partition_name} ${partition_filesystem}
            if [ $? -ne 0 ]; then
                g_LOG_Error "Generate script for formatting partition failed."
                return 1
            fi

            #get boot partition number
            if [ "${mount_point}" = "/boot/efi" ]; then
                boot_partition_num=${partition_num}
            elif [ "${mount_point}" = "/boot" ] && ! grep "/boot/efi" $PARTITION_CONF >/dev/null ; then
                root_partition_num=${partition_num}
            fi

            #generate partition script
            g_LOG_Info "generate partition script for: ${LINE}"
            if [ ! -z "`echo ${partition_size} | grep -i "max"`" ]; then
                if [ -z "${PARTITION_ALIGNMENT}" ]; then
                    printf "parted %s -s mkpart %s %s %s\n" \
                        ${disk_dev} ${partition_type} \
                        "${allocated_cyl}cyl" "$((disk_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                else
                    printf "parted %s -s -a %s mkpart %s %s %s\n" \
                        ${disk_dev} ${PARTITION_ALIGNMENT} ${partition_type} \
                        "${allocated_cyl}cyl" "$((disk_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                fi
                break
            else
                partition_cyl=$((partition_size*1024*1024/cylinder_size))

                if [ $((allocated_cyl + partition_cyl)) -gt $((disk_cyl)) ]; then
                    g_LOG_Debug "allocated_cyl=${allocated_cyl}, partition_cyl=${partition_cyl}, disk_cyl=${disk_cyl}"
                    if [ -z "${PARTITION_ALIGNMENT}" ]; then
                        printf "parted %s -s mkpart %s %s %s\n" \
                            ${disk_dev} ${partition_type} \
                            "${allocated_cyl}cyl" "$((disk_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                    else
                        printf "parted %s -s -a %s mkpart %s %s %s\n" \
                            ${disk_dev} ${PARTITION_ALIGNMENT} ${partition_type} \
                            "${allocated_cyl}cyl" "$((disk_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                    fi

                    break
                else
                    end_cyl=$((allocated_cyl + partition_cyl))
                    g_LOG_Debug "allocated_cyl=${allocated_cyl}, partition_cyl=${partition_cyl}, end_cyl=${end_cyl}"

                    if [ -z "${PARTITION_ALIGNMENT}" ]; then
                        printf "parted %s -s mkpart %s %s %s\n" \
                            ${disk_dev} ${partition_type} \
                            "${allocated_cyl}cyl" "$((end_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                    else
                        printf "parted %s -s -a %s mkpart %s %s %s\n" \
                            ${disk_dev} ${PARTITION_ALIGNMENT} ${partition_type} \
                            "${allocated_cyl}cyl" "$((end_cyl))cyl" >> ${DM_PARTITION_SCRIPT}
                    fi

                    allocated_cyl=${end_cyl}
                fi
            fi
        fi

    done < ${new_detail_file}

    #set boot flag
    g_LOG_Info "set boot flag"
    if [ $((boot_partition_num)) -gt 0 ]; then
        g_LOG_Info "set boot flag, boot_partition_num=${boot_partition_num}"
        printf "parted %s -s set %d boot on\n" \
            ${disk_dev} ${boot_partition_num} >> ${DM_PARTITION_SCRIPT}
    elif [ $((root_partition_num)) -gt 0 ]; then
        g_LOG_Info "set boot flag, root_partition_num=${root_partition_num}"
        printf "parted %s -s set %d boot on\n" \
            ${disk_dev} ${root_partition_num} >> ${DM_PARTITION_SCRIPT}
    fi

    return 0
}

###########################################################
#    Description: execute partition script
#    Parameter:   none
#    Return:      0-success, 1-failed
###########################################################
function DM_CreatePartition()
{
    local partition_script=$1

    if [ ! -f ${partition_script} ]; then
        g_LOG_Error "Script for creating partition lost."
        return 1
    fi

    #read partition script and execute
    while read LINE
    do
        if [ -z "${LINE}" ]; then
            continue
        fi

        g_LOG_Debug "${LINE}"
        eval "${LINE}" >>${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "Execute command \"${LINE}\" failed."
            return 1
        fi
    done < ${partition_script}

    return 0
}

############################################################
#    Description: execute format script
#    Parameter:   none
#    Return:      0-success, 1-failed
############################################################
function DM_FormatPartition()
{
    local format_script=$1

    if [ ! -f ${format_script} ]; then
        g_LOG_Error "Script for formatting partition lost."
        return 1
    fi

    #read format script and execute
    while read LINE
    do
        if [ -z "${LINE}" ]; then
            continue
        fi

        g_LOG_Debug "${LINE}"
        eval "${LINE}" >>${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "Execute command \"${LINE}\" failed."
            return 1
        fi
    done < ${format_script}

    return 0
}

############################################################
#    Description: generate fstab
#    Parameter:   param1: name of fstab file
#    Return:      0-success, 1-failed
############################################################
function DM_GetFstabFile()
{
    local fstab_file=$1
    local temp_detail_file=/opt/temp_detail_`date '+%s'`
    local temp_fstab_file=/opt/temp_fstab_`date '+%s'`
    local partition_name=
    local partition_by_id=
    local partition_type=
    local partition_filesystem=
    local mount_point=
    local actual_filesystem=
    local partition_check_type=0
    local diskflag=
    local diskflag_array=()
    local cmdline=/proc/cmdline

    #input check
    if [ -z "${fstab_file}" ]; then
        g_LOG_Error "Input null, can't locate fstab."
        return 1
    fi

    #check new.part
    if [ ! -f ${DM_DEFAULT_PARTITION_CONF} ]; then
        g_LOG_Error "New partition config file not found."
        return 1
    fi

    if [ -z "`cat ${DM_DEFAULT_PARTITION_CONF}`" ]; then
        g_LOG_Error "No any new partition config information."
        return 1
    fi

    #get disk flag from cmdline
    diskflag="`INIT_Get_CmdLineParamValue 'install_diskflag' ${cmdline}`"
    case ${diskflag} in
    id|uuid|devname)
        diskflag_array=($diskflag)
    ;;
    *)
        diskflag_array=(id uuid devname)
    ;;
    esac
    g_LOG_Info "install disk flag is ${diskflag_array[*]}"

    rm -rf ${fstab_file}
    mkdir -p `dirname ${fstab_file}`
    if [ $? -ne 0 ]; then
        g_LOG_Error "make dir `dirname ${fstab_file}` failed."
        return 1
    fi
    :>${fstab_file}

    rm -rf ${temp_detail_file}
    rm -rf ${temp_fstab_file}

    #filter comment and blank lines
    cat ${DM_DEFAULT_PARTITION_CONF} | sed 's/^[[:blank:]]*#.*$//g' | sed /^[[:blank:]]*$/d \
        > ${temp_detail_file}

    while read LINE
    do
        if [ -z "${LINE}" ]; then
            continue
        fi

        partition_type="`echo ${LINE} | awk '{print $5}'`"
        if [ "${partition_type}" == "${CON_PARTITION_TYPE_EXTENDED}" ]; then
            continue
        fi

	mount_point="`echo ${LINE} | awk '{print $7}'`"

        case ${mount_point} in
        -)
            continue
        ;;
        \/)
            partition_check_type=1
        ;;
        *)
            partition_check_type=2
        ;;
        esac

	#check filesystem
	partition_name="`echo ${LINE} | awk '{print $1}'`"
	partition_filesystem="`echo ${LINE} | awk '{print $6}' | tr [A-Z] [a-z]`"
        if [ "${partition_filesystem}" == "fat32" ] || [ "${partition_filesystem}" == "fat16" ]; then
            partition_filesystem="vfat"
        fi

        for data in ${diskflag_array[*]}
        do
            case ${data} in
            uuid)
                partition_by_id="`DM_GetPartitionByUuid ${partition_name}`"
                DISK_FLAG="UUID"
            ;;
            id)
                partition_by_id="`DM_GetPartitionById ${partition_name}`"
                DISK_FLAG="ID"
            ;;
            *)
                partition_by_id="${partition_name}"
                DISK_FLAG="DEVNAME"
            ;;
            esac
            if [ -n "${partition_by_id}" ]; then
                break
            fi
        done
        if [ -z "${partition_by_id}" ]; then
            g_LOG_Error "Failed to get partition name by ${diskflag_array[*]}."
            return 1
        fi

        #generate fstab file
        case ${partition_filesystem} in
        swap)
            printf "%s    %s    %s    %s %d %d\n" \
            ${partition_by_id} swap ${partition_filesystem} \
            pri=42 0 0 >> ${temp_fstab_file}
        ;;
        ext2|ext3|ext4|vfat)
            if [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
                printf "%s    %s    %s    %s %d %d\n" \
                ${partition_by_id} ${mount_point} ${partition_filesystem} \
                defaults 0 0 >> ${temp_fstab_file}
            else
                printf "%s    %s    %s    %s %d %d\n" \
                ${partition_by_id} ${mount_point} ${partition_filesystem} \
                defaults 1 ${partition_check_type} >> ${temp_fstab_file}
            fi
        ;;
        *)
            if [ "${partition_filesystem}" != "-" ]; then
                g_LOG_Warn "Unknown filesystem, can't mount \"${mount_point}\""
            fi
            continue
        ;;
        esac

    done < ${temp_detail_file}

    #Check if do while is OK
    if [ $? -ne 0 ]; then
        return 1
    fi

    rm -f ${temp_detail_file}
    if [ -f ${temp_fstab_file} ] && [ ! -z "`cat ${temp_fstab_file}`" ]; then
        cat ${temp_fstab_file} | sort -b -k 2,2 > ${fstab_file}
        rm -f ${temp_fstab_file}
    else
        g_LOG_Error "fstab is null"
        return 1
    fi

    return 0
}

##############################################################
#    Description: Generate default.part
#    Parameter:   param1: partition config file
#    Return:      0-success, 1-failed
##############################################################
function g_DM_ResolvePartitionConfigFile()
{
    local partition_config_file=$1
    local install_disk=

    #input check
    if [ -z "${partition_config_file}" ] || [ ! -f "${partition_config_file}" ]; then
        g_LOG_Error "Can't find partition.conf."
        return 1
    fi

    #get disk device list
    DM_DEVICE_NAMES="`DM_GetDiskList`"
    if [ $? -ne 0 ]; then
        g_LOG_Error "get disk list failed.DM_DEVICE_NAMES=\"${DM_DEVICE_NAMES}\"."
        return 1
    fi

    #format partition.conf to default.part
    g_LOG_Info "Format partition.conf."
    DM_FormatPartitionConf "${partition_config_file}"
    if [ $? -ne 0 ]; then
        g_LOG_Error "Failed to format ${partition_config_file}."
        return 1
    fi
    g_LOG_Info "Formatting partition.conf end."

    #verify default.part
    g_LOG_Info "verify new partition setting."
    install_disk=${DM_INSTALL_DISK}
    DM_VerifyPartitionConfAfter ${install_disk}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Illegal new partition setting."
        return 1
    fi

    return 0
}

#############################################################
#    Description: create and format partitions
#    Parameter:   param1: fstab
#    Return:      0-success, 1-failed
#############################################################
function g_DM_CreateAndFormatPartition()
{
    local fstab_file=$1
    local install_disk=${DM_INSTALL_DISK}
    local default_config_file=${DM_DEFAULT_PARTITION_CONF}
    local disk_name=
    local formatParam=
    local cmdline="/proc/cmdline"
    local new_detail_file=/opt/new_detail_`date '+%s'`

    #input check
    if [ -z "${fstab_file}" ]; then
        g_LOG_Error "Input null, can't locate fstab."
        return 1
    fi

    #check new.part
    if [ ! -f ${DM_NEW_PARTITION_CONF} ]; then
        #when use cd to install, should have new.part
        #if new.part doesn't exist, there must have an accident, use default.part as new
        if [ ! -z "`echo ${INSTALL_MEDIA} | grep -iw "cd"`" ]; then
            g_LOG_Info "New partition config file not found. choose default config."
        fi

        if [ ! -f ${DM_DEFAULT_PARTITION_CONF} ]; then
            g_LOG_Error "Default partition config file doesn't exist."
            return 1
        fi

        if [ -z "`cat ${DM_DEFAULT_PARTITION_CONF}`" ]; then
            g_LOG_Error "Default partition config is null."
            return 1
        fi

        mkdir -p `dirname ${DM_NEW_PARTITION_CONF}`
        if [ $? -ne 0 ]; then
            g_LOG_Error "make dir `dirname ${DM_NEW_PARTITION_CONF}` failed"
            return 1
        fi
        cp ${DM_DEFAULT_PARTITION_CONF} ${DM_NEW_PARTITION_CONF}

    elif [ -z "`cat ${DM_NEW_PARTITION_CONF}`" ]; then
        g_LOG_Error "No any new partition config information."
        return 1
    fi

    #check if device is a harddisk
    disk_name="`echo ${install_disk} | awk -F "/" '{print $NF}'`"
    if [ -z "`cat /proc/partitions | grep ${disk_name}`" ]; then
        g_LOG_Error "Device ${install_disk} is not a disk."
        return 1
    fi

    #parse forcedformat
    formatParam="`INIT_Get_CmdLineParamValue 'forcedformat' ${cmdline}`"
    if [ `echo ${formatParam} | egrep "^[Yy][Ee][Ss]"` ]; then
        g_LOG_Info "create and format all partitions"
    else
        g_LOG_Info "Confirm old partitions, decide if need to create and format all partitions"
        DM_ConfirmOldPartitions
        if [ $? -ne 0 ]; then
            g_LOG_Error "Execute DM_ConfirmOldPartitions failed."
            return 1
        fi
    fi

    rm -rf ${new_detail_file}

    #init partition and format script
    rm -rf ${DM_PARTITION_SCRIPT}
    rm -rf ${DM_FORMAT_SCRIPT}
    mkdir -p `dirname ${DM_PARTITION_SCRIPT}`
    if [ $? -ne 0 ]; then
        g_LOG_Error "make dir `dirname ${DM_PARTITION_SCRIPT}` failed"
        return 1
    fi
    mkdir -p `dirname ${DM_FORMAT_SCRIPT}`
    if [ $? -ne 0 ]; then
        g_LOG_Error "make dir `dirname ${DM_FORMAT_SCRIPT}` failed"
        return 1
    fi
    touch ${DM_PARTITION_SCRIPT}
    if [ $? -ne 0 ]; then
        g_LOG_Error "touch file ${DM_PARTITION_SCRIPT} failed"
        return 1
    fi
    touch ${DM_FORMAT_SCRIPT}
    if [ $? -ne 0 ]; then
        g_LOG_Error "touch file ${DM_FORMAT_SCRIPT} failed"
        return 1
    fi

    #check if device is a harddisk
    disk_name="`echo ${install_disk} | awk -F "/" '{print $NF}'`"
    if [ -z "`cat /proc/partitions | grep ${disk_name}`" ]; then
        g_LOG_Error "Device ${install_disk} is not a disk."
        return 1
    fi

    g_LOG_Info "Remove LVM partitions."
    DM_RemoveLVMPartition ${install_disk}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Remove LVM partitions failed."
        return 1
    fi

    g_LOG_Info "Attempts to remove all device definitions."
    dmsetup remove_all -f >>${OTHER_TTY} 2>&1

    #get new partition setting for this disk
    cat ${DM_NEW_PARTITION_CONF} | grep "${install_disk}" > ${new_detail_file}
    g_LOG_Info "DM_NEW_PARTITION_CONF=${DM_NEW_PARTITION_CONF}:`cat ${DM_NEW_PARTITION_CONF}`"

    #generate partition and format script
    g_LOG_Info "Start to generate partition and format script."
    DM_GenPartitionScript ${install_disk} ${new_detail_file}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Failed to generate partition and format script."
        return 1
    fi

    g_LOG_Info "Finished to generate partition and format script."

    #execute partition script
    g_LOG_Notice "Creating partitions."
    DM_CreatePartition ${DM_PARTITION_SCRIPT}
    if [ $? -ne 0 ]; then
        return 1
    fi
    g_LOG_Notice "Finished to create partitions."

    #prepare for formatting
    if [ "x${SI_CMDTYPE}" == "xsl-cmd" ]; then
        g_LOG_Info "partprobe ${install_disk}."
        partprobe ${install_disk} >>${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "Inform kernel of ${install_disk}'s partition table changes failed."
            return 1
        fi
        sleep 3
    elif [ "x${SI_CMDTYPE}" == "xrh-cmd" ]; then
        #wait until partition devices in /dev/ created
        udevadm trigger --subsystem-match=block --action=add >>${OTHER_TTY} 2>&1
        sleep 1
        udevadm settle --timeout=${CON_PARTITION_DEVICE_TIMEOUT} >>${OTHER_TTY} 2>&1
    else
        g_LOG_Error "SI_CMDTYPE is wrong, please check isopackage.sdf."
        return 1
    fi
    
    #execute partition script
    g_LOG_Notice "Formatting partition."
    DM_FormatPartition ${DM_FORMAT_SCRIPT}
    if [ $? -ne 0 ]; then
        return 1
    fi
    g_LOG_Notice "Finished to format partitions."

    #wait until partition devices in /dev/ created
    udevadm trigger --subsystem-match=block --action=add >>${OTHER_TTY} 2>&1
    sleep 1
    udevadm settle --timeout=${CON_PARTITION_DEVICE_TIMEOUT} >>${OTHER_TTY} 2>&1

    #generate fstab from new.part
    g_LOG_Info "Generate fstab file."
    DM_GetFstabFile "${fstab_file}"
    if [ $? -ne 0 ]; then
        g_LOG_Error "Failed to generate fstab file."
        return 1
    fi
    g_LOG_Info "Finished to generate fstab file."

    return 0
}

###########################################################
#    Description: mount partitions defined fstab to target path
#    Parameter:   param1: target path
#                 param2: fstab
#    Return:      0-success, 1-failed
###########################################################
function g_DM_MountPartitionToTarget()
{
    local target_path=$1
    local fstab_file=$2
    
    local disk_name=
    local mount_path=
    local modified_mount_path=
    local fstype=
    local cur_trytimes=

    #input check
    if [ -z "${target_path}" ]; then
        g_LOG_Error "There isn't any target path."
        return 1
    fi

    if [ -z "${fstab_file}" ] || [ ! -f ${fstab_file} ]; then
        g_LOG_Error "Can't find fstab file."
        return 1
    fi

    #wait until partition devices in /dev/ created
    udevadm trigger --subsystem-match=block --action=add >>${OTHER_TTY} 2>&1
    sleep 1
    udevadm settle --timeout=${CON_PARTITION_DEVICE_TIMEOUT} >>${OTHER_TTY} 2>&1

    #at first, create target path
    mkdir -p ${target_path}
    if [ $? -ne 0 ]; then
        g_LOG_Error "make dir ${target_path} failed"
        return 1
    fi

    while read LINE
    do
        #filter comment and blank lines
        LINE="`echo ${LINE} | sed 's/^[[:blank:]]*#.*$//g' | sed /^[[:blank:]]*$/d`"
        if [ -z "${LINE}" ]; then
            continue
        fi

        disk_name="`echo ${LINE} | awk '{print $1}'`"
        mount_path="${target_path}/`echo ${LINE} | awk '{print $2}'`"
        modified_mount_path="`echo ${mount_path} | sed "s/[\/]\{2,\}/\//g" | \
            sed "s/\/$//g"`"
        fstype="`echo ${LINE} | awk '{print $3}'`"
        cur_trytimes=1

        if [ -z "${fstype}" ]; then
            g_LOG_Error "File system is empty."
            return 1
        fi

        #do not mount swap
        if [ "`echo ${fstype} | tr A-Z a-z`" == "swap" ]; then
            continue
        fi

        #create path before mounting
        mkdir -p "${modified_mount_path}" >>${OTHER_TTY} 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Error "Failed to create path ${modified_mount_path} before mounting."
            return 1
        fi

        #Check if the directory is already mounted
        if [ ! -z "`mount | grep "${disk_name}" | grep "${modified_mount_path}"`" ]; then
            continue
        fi

        while true;
        do
            #mount to target path
            g_LOG_Debug "mount -t ${fstype} ${disk_name} ${modified_mount_path}"
            mount -t "${fstype}" "${disk_name}" "${modified_mount_path}" >>${OTHER_TTY} 2>&1
            if [ $? -eq 0 ]; then
                break
            fi
            g_LOG_Warn "Mount partition to ${modified_mount_path} failed, try again."
            ((cur_trytimes++))
            if [ "${cur_trytimes}" -gt 3 ]; then
                g_LOG_Error "Mount partition to ${modified_mount_path} failed."
                return 1
            fi
            sleep 2
        done
    done < ${fstab_file}

    return 0
}

#########################################################
#    Description: wait for disk scan
#    Parameter:   none
#    Return:      0 if find disk
#########################################################
function DM_WaitScan()
{
    local timeout=
    local interval=3
    local disk_list=

    # check if $1 is number
    [[ "$1" =~ ^[0-9]+$ ]] && timeout="$1"
    [ -z "${timeout}" ] && timeout="${DM_DEFAULT_DISK_SCAN_TIMEOUT}"
    [ "${timeout}" -lt "${interval}" ] && timeout="${interval}"

    while [ "${timeout}" -gt 0 ]; do
        sleep ${interval}
        disk_list="`DM_GetDiskList`"
        [ $? -eq 0 ] && break
        g_LOG_Info "all disks list is \"${disk_list}\"."
        ((timeout-=interval))
    done

    if [ "${timeout}" -gt 0 ]; then
        g_LOG_Info "all disks list is \"${disk_list}\"."
        return 0
    else
        g_LOG_Error "can not find any disk!"
        return 1
    fi
}

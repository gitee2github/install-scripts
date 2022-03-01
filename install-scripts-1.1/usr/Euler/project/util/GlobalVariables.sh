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
* Description: Global Variables
!

#!/bin/bash

############## Global Variables ##############
#install mode, it is may be install or start
INSTALL_MODE=
#install media, it is may be cd or pxe
INSTALL_MEDIA=

#### Local Path ####
#used to store OS.tar.gz
LOCAL_SOURCE_PATH=/mnt/disk/download
#used to mount disk
LOCAL_DISK_PATH=/mnt/disk
#The OS decompression path is only used in the hook to deal with
#the modification of the path
LOCAL_UNCOMPRESS_PATH=${LOCAL_DISK_PATH}
#used to store temp files
LOCAL_PROJECT_PATH=/usr/Euler
#boot profile directory
LOCAL_CONFIG_PATH=${LOCAL_PROJECT_PATH}/conf
#directory of temporary configuration files during boot
LOCAL_TEMPCFG_PATH=${LOCAL_CONFIG_PATH}/tmp
#boot installation directory
LOCAL_SCRIPT_PATH=${LOCAL_PROJECT_PATH}/project
#boot hook directory
LOCAL_HOOK_PATH=${LOCAL_PROJECT_PATH}/hook

#### Server path ####
#the protocol of downloading OS.tar.gz
SERVER_SOURCE_TYPE=
#the remote source(OS.tar.gz) server's IP
SERVER_SOURCE_IP=
#the remote source(OS.tar.gz) server's path
SERVER_SOURCE_PATH=
#the protocol of uploading logs
SERVER_LOG_TYPE=
#the remote log server's IP
SERVER_LOG_IP=
#the remote log server's path
SERVER_LOG_PATH=

#### Host config ####
#net device name, for example eth0
NET_DEVICE=
#set host name
NODE_NAME=

#### Config Files ####
#OS.tar.gz package information
ISOPACKAGE_CONF=${LOCAL_CONFIG_PATH}/isopackage.sdf
#config partitions, include "device name", "mount point", "partition size"...
PARTITION_CONF=${LOCAL_CONFIG_PATH}/partition.conf
#menu.lst file
MENULST_CONF=${LOCAL_CONFIG_PATH}/menu.lst
#system config file
SYSCONFIG_CONF=${LOCAL_CONFIG_PATH}/UVP.conf
#config all deivce which needed to mount
FSTAB_FILE=${LOCAL_TEMPCFG_PATH}/fstab
#config log level, it is may be 0,1,2,3,4,5,6,7
LOG_LEVEL=

#Transport file related
REPO_SERVER_URL=
LOG_SERVER_URL=
CFG_SERVER_URL=

#used to display error message in setup
OTHER_TTY=/var/log/othertty.output
#the first disk name, for example /dev/sda
FIRST_DISK=
#boot mode, 0-legacy, 1-UEFI
EFI_FLAG=0

#means esp partition
BOOT_ESP="false"

PARTITION_ALIGNMENT=

SI_CMDTYPE=
UDEV_WAIT_TIMEOUT=30

#Disk mount flag, can be UUID, ID or DEVNAME
DISK_FLAG=
########## export global variables ##########
export INSTALL_MODE
export INSTALL_MEDIA
export LOCAL_SCRIPT_PATH
export LOCAL_HOOK_PATH

export LOCAL_LOG_PATH
export LOCAL_SOURCE_PATH
export LOCAL_CONFIG_PATH
export LOCAL_DISK_PATH
export LOCAL_UNCOMPRESS_PATH
export LOCAL_TEMPCFG_PATH
export LOCAL_ADDONSCRIPT_PATH

export SERVER_SOURCE_TYPE
export SERVER_SOURCE_IP
export SERVER_SOURCE_PATH
export SERVER_LOG_TYPE
export SERVER_LOG_IP
export SERVER_LOG_PATH

export NET_DEVICE

export PARTITION_CONF
export MENULST_CONF
export FSTAB_FILE
export SYSCONFIG_CONF
export LOG_FILE
export LOG_LEVEL

export REPO_SERVER_URL
export LOG_SERVER_URL
export CFG_SERVER_URL

export OTHER_TTY
export FIRST_DISK
export LC_ALL=C
export EFI_FLAG

export BOOT_ESP

export PARTITION_ALIGNMENT
export SI_CMDTYPE

export UDEV_WAIT_TIMEOUT

export DISK_FLAG
########## include modules ##########
source ${LOCAL_SCRIPT_PATH}/log/setuplog.sh
source ${LOCAL_SCRIPT_PATH}/load/load.sh
source ${LOCAL_SCRIPT_PATH}/init/InitInsEnv.sh
source ${LOCAL_SCRIPT_PATH}/disk/hwcompatible.sh
source ${LOCAL_SCRIPT_PATH}/disk/diskmgr.sh

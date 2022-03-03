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
* Description: Initial Modules
!

source ${LOCAL_SCRIPT_PATH}/log/setuplog.sh
source ${LOCAL_SCRIPT_PATH}/util/CommonFunction

INSMOD_DRV_HOOK=${LOCAL_HOOK_PATH}/insmod_drv_hook

SPECIAL_MODULES=${INSMOD_DRV_HOOK}/os_special_drv_insmod.sh

NVRAM=os_rnvramdev

##################################################################
# Description:    StartExeShell
# Parameter:      none
# Return:         0-success, 1-failed
##################################################################
function StartExeShell()
{
    local os_exeshell=`which os_exeshell`

    g_LOG_Info "Start ${os_exeshell} &"

    OS_IS_CPU_ALLOW_BIND_CPU0
    if [ $? -eq 1 ]; then
        taskset -c 0 ${os_exeshell} &
    else
        ${os_exeshell} &
    fi

    return 0
}

##################################################################
# Description:    load OS modules
# Parameter:      none
# Return:         0-success, 1-failed
##################################################################
function InitSysModules()
{
    local temp_module=
    local sys_modules=${LOCAL_CONFIG_PATH}/modules

    g_LOG_Info "Loading the kernel modules:"
    cat ${sys_modules} | sed -e '/^[ \t]*$/d' |
    while read module
    do
        temp_module=`echo "${module}" | awk -F' ' '{print $1}'`
        modinfo ${temp_module} >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            g_LOG_Warn "module ${temp_module} is not exist."
            continue
        fi

	modprobe ${module}
        if [ $? -ne 0 ]; then
            g_LOG_Warn "Loading module: ${module} fail."
            continue
        fi

        if [ "${temp_module}" == "${NVRAM}" ]; then
            g_LOG_Info "module is ${NVRAM}, start exe shell"
            StartExeShell
        fi

        g_LOG_Info "Loading module: ${module} end."
    done

    return 0
}

function ModulesInit()
{
    if [ -f "${SPECIAL_MODULES}" ]; then
        sh ${SPECIAL_MODULES}
    fi

    InitSysModules

    INIT_Execute_Hook ${INSMOD_DRV_HOOK}
    if [ $? -ne 0 ]; then
        g_LOG_Error "Execute insert custom modules failed."
        return 1
    fi
    return 0
}

ModulesInit "$@"

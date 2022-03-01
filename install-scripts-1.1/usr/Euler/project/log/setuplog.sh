#!/bin/bash
# Description: This script contains the miniOS log
#              interfaces and generic utility functions.

#templogFile
LOG_FILE="/var/log/setup.log"
export LOG_FILE

#const value of different loglevel
CON_EMERG="0"
CON_ALERT="1"
CON_CRIT="2"
CON_ERROR="3"
CON_WARN="4"
CON_NOTICE="5"
CON_INFO="6"
CON_DEBUG="7"

#set default log level
DEFAULT_LEVEL="6"
LOG_LEVEL=${DEFAULT_LEVEL}

CURRENT_TTY=`tty`
if [ $? -ne 0 ];then
    CURRENT_TTY="/dev/console"
fi
function g_LOG_Init()
{
    local logdir="`dirname ${LOG_FILE}`"
    local loglevel=`cat /proc/cmdline | awk -F 'log_level=' '{print $2}' | awk '{print $1}'`

    local isDel=1
    if [ ! -z "$1" ]
    then
        isDel=$1
    fi

    if [ "$isDel" = "0" ]
    then
        if [ -f "${LOG_FILE}" ]
        then
            rm -rf ${LOG_FILE}
        fi

        #set logdir
        if [ ! -d "${logdir}" ]
        then
            mkdir -p ${logdir}
            if [ $? -ne 0 ]; then
                echo "Error: mkdir ${logdir} failed"
                return 1
            fi
        fi
        touch ${LOG_FILE}
        if [ $? -ne 0 ]; then
            echo "Error: touch ${LOG_FILE} failed"
            return 1
        fi
    fi

    #set loglevel
    if [ -z "${loglevel}" ]
    then
        LOG_LEVEL=${DEFAULT_LEVEL}
    elif [ ! `echo ${loglevel} | grep '^[0-7]$'` ]
    then
        echo "Warning: input invalid ! the loglevel will be set to default!" >> ${LOG_FILE}
        LOG_LEVEL=${DEFAULT_LEVEL}
    else
        LOG_LEVEL=${loglevel}
    fi

    echo "current log level is ${LOG_LEVEL}." >> ${LOG_FILE}
    chmod 600 ${LOG_FILE}
    return 0
}
function LOG_WriteLog()
{
    local progname=`basename ${BASH_SOURCE[2]}`
    local severity=$1
    local line_no=$2
    shift 2
    local logmsg=$@

    logmsg="`echo $logmsg | sed -r 's/([0-9]{1,3}\.){3}[0-9]{1,3}/\*\*\*\*/g'`"
    #存储os的安装日志，保持与启动日志一致，移植hima os的日志处理方式
    which OS_echo 1>/dev/null 2>/dev/null
    if [ $? == 0 ]
    then
        if [ $severity -le 3 ];then
            echo "$logmsg" > /dev/stderr
        fi

        echo "$logmsg" > /dev/kmsg

        return 0
    fi

    if [ ${severity} -le ${LOG_LEVEL} ]
    then
        case ${severity} in
            0)  #Emerg log
                echo -n "[ EMERG ] - " >> ${LOG_FILE}
                ;;
            1)  #Alert log
                echo -n "[ ALERT ] - " >> ${LOG_FILE}
                ;;
            2)  #crit log
                echo -n "[ CRIT ] - " >> ${LOG_FILE}
                ;;
            3)  # Error log
                echo -n "[ ERROR ] - " >> ${LOG_FILE}
                ;;
            4)  # Warning log
                echo -n "[ WARN ] - " >> ${LOG_FILE}
                ;;
            5)  #Notice log
                echo -n "[ NOTICE ] - " >> ${LOG_FILE}
                ;;
            6)  # Information log
                echo -n "[ INFO ] - " >> ${LOG_FILE}
                ;;
            7)  # Debug log
                echo -n "[ DEBUG ] - " >> ${LOG_FILE}
                ;;
            *)  # Any other logs
                echo -n "[       ] - " >> ${LOG_FILE}
                ;;
        esac

    echo "`date "+%b %d %Y %H:%M:%S"`" ${progname} "[line_no=${line_no}]:" \
    "${logmsg}" | tee -a ${LOG_FILE} > ${CURRENT_TTY}

    fi

        return 0
}
function g_LOG_Emerg()
{
    LOG_WriteLog $CON_EMERG $BASH_LINENO "$@"
        return 0
}
function g_LOG_Alert()
{
    LOG_WriteLog $CON_ALERT $BASH_LINENO "$@"
        return 0
}
function g_LOG_Crit()
{
    LOG_WriteLog $CON_CRIT $BASH_LINENO "$@"
        return 0
}
function g_LOG_Error()
{
    LOG_WriteLog $CON_ERROR $BASH_LINENO "$@"
        return 0
}
function g_LOG_Warn()
{
    LOG_WriteLog $CON_WARN $BASH_LINENO "$@"
        return 0
}
function g_LOG_Notice()
{
    LOG_WriteLog $CON_NOTICE $BASH_LINENO "$@"
        return 0
}
function g_LOG_Info()
{
    LOG_WriteLog $CON_INFO $BASH_LINENO "$@"
        return 0
}
function g_LOG_Debug()
{
    LOG_WriteLog $CON_DEBUG $BASH_LINENO "$@"
        return 0
}

g_LOG_Init "$@"

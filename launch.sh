#!/bin/bash
#
# Copyright (c) 2015 Wan Li. All Rights Reserved
#
# Author: Wan Li
# Date: 2015/12/01
# Brief:
#   Process launcher
# Arguments:
#   -c check proc file and env file
#   -h help
#   -f [procfile] specify procfile to load
#   -e [env_file] specify env file to load, 
#                 if not set, process will try to load .env on startup
# Returns:
#   succ:0
#   fail:1

# switches
# set -x
set -e
set -u
set -o pipefail 

# enviroment variables
PORT=8080

# variables
env_file=''
proc_file=''
arg_c=0
arg_h=0
cmd_array=()
color_array=($(
    for i in {1..7}; do 
        echo $(( 30+i ))
    done
))

# functions

# Usage
function usage() {
    printf "%s\n" 'Usage: launch [-c] [-f procfile|Procfile] [-e envfile|.env]'
    exit 0
}

#######################################
# Brief:
#   Validate procfile
# Arguments:
#   procfile
# Returns:
#   0 if succeeded
#   -1 otherwise
#######################################
function validate_procfile() {
    local target_file=$1
    local ret=0
    local tmp=''
    if [[ ! -e "${target_file}" ]]; then
        return -1
    fi 
    while read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        IFS=":" read -ra arr <<< "${line}"
        if [[ 2 -ne "${#arr[@]}" ]]; then
            echo "syntax error: ${line}" 
            ret=-1
            continue
        fi
        tmp=$(< <(eval "${arr[0]}=''" 2>&1))
        if [[ -n "${tmp}" ]]; then
            echo 'error: '"${tmp}"
            ret=-1
        fi
    done < "${target_file}"
    return "${ret}"
}

#######################################
# Brief:
#   Run procfile
# Globals:
#   color_array, cmd_array
# Arguments:
#   procfile
# Returns:
#   0 if succeeded
#   -1 otherwise
#######################################
function run_procfile() {
    local file=$1
    local proc_name=''
    local proc_cmd=''
    local line_out=''
    local color_idx=0
    local grep_arr=''
    local exec_cmd=''
    if [[ ! -e "${file}" ]]; then
        echo 'no Procfile found.'
        return -1
    fi
    
    while read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        IFS=":" read -ra arr <<< "${line}"
        if [[ 2 -gt "${#arr[@]}" ]]; then
            continue
        fi
        if [[ 2 -lt "${#arr[@]}" ]]; then
            IFS=":" read -r arr[0] arr[1] <<< "${line}"
        fi
        proc_name="${arr[0]}"
        proc_cmd="${arr[1]}"
        grep_arr=($(< <(echo "${proc_cmd}" | grep -Eo '\$[A-Za-z0-9]+')))
        grep_arr=${grep_arr:-""}
        for var in "${grep_arr[@]}"; do
            if [[ -n "${var}" ]]; then
                eval "${var#\$}"'=${'"${var#\$}"':-""}'
            fi
        done
        {
            exec_cmd=$(eval "echo \"${proc_cmd}\"")
            while read -r tty_line || [[ -n "${tty_line}" ]]; do
                line_out=$(printf '%s %s | %s' \
                    "$(date +%H:%M:%S)" "${proc_name}" "${tty_line}")
                printf '\e[%s;1m%s\e[m\n' \
                    "${color_array[${color_idx}]}" \
                    "${line_out}"
            done < <(exec $(printf "%s " "${exec_cmd[@]}") 2>/dev/null)
        } &
        exec_cmd=$(eval "echo \"${proc_cmd}\"")
        if [[ ${#cmd_array[@]} -gt 0 ]]; then
            cmd_array=("${cmd_array[@]}" "${exec_cmd}")
        else
            cmd_array=("${exec_cmd}")
        fi
        line_out=$(printf "%s %s |%s started with pid %s" \
            "$(date +%H:%M:%S)" "${proc_name}" "${exec_cmd}" "$!")
        printf '\e[%s;1m%s\e[m\n' \
            "${color_array[${color_idx}]}" \
            "${line_out}"
        grep_port=$(< <(echo "${proc_cmd}" | grep -Eo '\$PORT'))
        if [[ 'PORT' == "${grep_port#\$}" ]]; then
            PORT=$(( ${PORT} + 1 ))
        fi
        color_idx=$(( ${color_idx}+1 % ${#color_array[@]} ))
    done < "${file}"
}

#######################################
# Brief:
#   Terminate subprocesses
# Globals:
#   cmd_array
# Returns:
#   0 if succeeded
#   -1 otherwise
#######################################
function terminate_process() {
    for cmd in "${cmd_array[@]}"; do
        seg_array=( $(< <(ps aux | grep "${cmd}")) )
        kill "${seg_array[1]}" 2>/dev/null
    done
    echo "$(jobs -p)" | xargs kill
}

#######################################
# Brief:
#   Validate env_file
# Arguments:
#   env_file
# Returns:
#   0 if succeeded
#   -1 otherwise
#######################################
function validate_envfile() {
    local target_file=$1
    local ret=0
    local tmp=''
    if [[ ! -e "${target_file}" ]]; then
        return -1
    fi 
    while read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        tmp=$(< <(eval "${line}" 2>&1))
        if [[ -n "${tmp}" ]]; then
            echo "found error: ${tmp} line: ${line}"
            ret=-1
        fi
    done < "${target_file}"
    return "${ret}"
}

#######################################
# Brief:
#   Load env_file
# Arguments:
#   env_file
# Returns:
#   0 if succeeded
#   -1 otherwise
#######################################
function load_envfile() {
    local target_file=$1
    local ret=0
    local tmp=''
    if [[ -z "${target_file}" && -e '.env' ]]; then
        target_file='.env'
    fi
    if [[ ! -e "${target_file}" ]]; then
        #echo 'run without env_file'
        return 0
    fi
    while read -r line || [[ -n "${line}" ]]; do
        line="${line%%#*}"
        eval "${line}"
    done < "${target_file}"
    return "${ret}"
}

#######################################
# Brief:
#   Validate procfile and env_file
# Globals:
#   proc_file env_file
# Arguments:
#   None
# Returns:
#   0 if succeeded
#   -1 otherwise
#######################################
function verify() {
    local valid=0
    validate_procfile "${proc_file}"
    valid=$?
    if [[ "${valid}" -ne 0 ]]; then
        echo 'failed to verify Procfile'
        exit "${valid}"
    fi
    
    if [[ -e "${env_file}" ]]; then
        validate_envfile "${env_file}"
        valid=$?
        if [[ "${valid}" -ne 0 ]]; then
            echo 'failed to verify Envfile'
            exit "${valid}"
        fi
    fi
}

# Main
function main() {
    while getopts 'chf:e:' opt; do
        case "${opt}" in
            c) arg_c=1 ;;
            h) arg_h=1 ;;
            f) proc_file=$OPTARG ;;
            e) env_file=$OPTARG ;;
            *) usage ;;
        esac
    done
    if [[ 1 -eq "${arg_h}" ]]; then
        usage
        exit 0
    fi
    # check if -c option is set
    if [[ 1 -eq "${arg_c}" ]]; then
        # check if Procfile is specified, if not then print usage
        if [[ -z "${proc_file}" ]]; then
            echo "Procfile not exits"
            usage
            exit -1
        fi
        env_file=${env_file:-".env"}
        # verify both Procfile and env_file
        verify
        exit 0
    fi
    env_file=${env_file:-".env"}
    load_envfile "${env_file}"
    proc_file=${proc_file:-"Procfile"}
    run_procfile "${proc_file}"
    wait
}

# Trap
trap 'terminate_process 2>&1' SIGINT SIGTERM EXIT

# Start
main "$@"

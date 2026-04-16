#!/bin/bash

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
VERBOSE=false
DEBUG=false
LOG_FILE=""
ENABLE_LOG_FILE=false

# Charts directory
CHARTS_REPO_DIR="/srv/kubernetes-charts"
CHARTS_DIR="${CHARTS_REPO_DIR}/charts"

# Initialize log file
function init_log_file() {
    local release="$1"
    if [[ "${ENABLE_LOG_FILE}" == "true" ]]; then
        if [[ -z "${LOG_FILE}" ]]; then
            # Auto-generate log file name with release name
            LOG_FILE="/tmp/k8s-update-replicas-${release}-$(date +%Y%m%d-%H%M%S).log"
        fi

        # 检查日志文件是否已存在（由入口脚本创建）
        local is_new_log=false
        if [[ ! -f "${LOG_FILE}" ]]; then
            is_new_log=true
            # Create log file
            touch "${LOG_FILE}" 2>/dev/null || {
                echo -e "${RED}[ERROR]${NC} 无法创建日志文件: ${LOG_FILE}"
                exit 1
            }
        fi

        # 只在新日志文件时显示提示（避免重复提示）
        if [[ "${is_new_log}" == "true" ]]; then
            echo -e "${GREEN}[INFO]${NC} 日志将保存到: ${LOG_FILE}"
        fi

        # 追加更新脚本的日志头部
        echo "" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "副本数更新脚本执行日志" >> "${LOG_FILE}"
        echo "Release: ${release}" >> "${LOG_FILE}"
        echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "" >> "${LOG_FILE}"
    fi
}

# Log output function (output to both terminal and file)
function write_log() {
    local message="$1"

    # 终端输出
    echo -e "${message}"

    # 文件输出（去除颜色代码）
    if [[ "${ENABLE_LOG_FILE}" == "true" ]] && [[ -n "${LOG_FILE}" ]]; then
        local clean_message
        clean_message=$(echo -e "${message}" | sed 's/\x1b\[[0-9;]*m//g')
        echo "${clean_message}" >> "${LOG_FILE}"
    fi
}

# Logging functions
function get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

function log_info() {
    write_log "${GREEN}[INFO]  ${NC}[$(get_timestamp)] $1"
}

function log_warn() {
    write_log "${YELLOW}[WARN]  ${NC}[$(get_timestamp)] $1"
}

function log_error() {
    write_log "${RED}[ERROR] ${NC}[$(get_timestamp)] $1"
}

function log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        write_log "${CYAN}[DEBUG] ${NC}[$(get_timestamp)] $1"
    fi
}

function log_step() {
    write_log ""
    write_log "${BLUE}===================================================${NC}"
    write_log "${BLUE}[STEP]  ${NC}[$(get_timestamp)] $1"
    write_log "${BLUE}===================================================${NC}"
}

function log_cmd() {
    if [[ "${VERBOSE}" == "true" ]] || [[ "${DEBUG}" == "true" ]]; then
        write_log "${CYAN}[CMD]   ${NC}[$(get_timestamp)] $1"
    fi
}

function error_exit() {
    log_error "$1"
    log_error "副本数更新失败，请检查上述错误信息"
    if [[ "${ENABLE_LOG_FILE}" == "true" ]] && [[ -n "${LOG_FILE}" ]]; then
        echo "" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
        echo "状态: 失败" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        log_error "详细日志已保存到: ${LOG_FILE}"
    fi
    exit 1
}

# Print help information
function print_help() {
    cat << EOF
Usage: $0 <release> [OPTIONS]

Description:
  Update replica count for Kubernetes deployments using helm upgrade --set.

Arguments:
  <release>                   Helm release name (required)

Options:
  --replicas <count>          Number of replicas (required)
  -n, --namespace <ns>        Kubernetes namespace (required)
  -k, --kind <kind>           Resource kind: Deployment or StatefulSet (required)

  -v, --verbose               Enable verbose output
  -d, --debug                 Enable debug mode
  -l, --log                   Enable log file (auto-generated name)
  --log-file <path>           Specify log file path
  -h, --help                  Show this help message

Examples:
  # Update ingress-nginx replicas
  $0 ingress-nginx --replicas 3 -n ingress-nginx -k Deployment

Special Component Handling:
  ingress-nginx    → Uses controller.replicaCount path

EOF
}

# Build helm upgrade command for replica update
function build_replica_helm_command() {
    local release="$1"
    local namespace="$2"
    local replicas="$3"
    local kind="$4"

    log_debug "构建副本数更新 helm upgrade 命令..."
    log_debug "  Release: ${release}"
    log_debug "  命名空间: ${namespace}"
    log_debug "  副本数: ${replicas}"
    log_debug "  资源类型: ${kind}"

    # Build base command
    local cmd="helm upgrade ${release} ${CHARTS_DIR}/${release} -n ${namespace}"

    # Add replica count - special handling for different components
    if [[ "${release}" == "ingress-nginx" ]]; then
        # ingress-nginx uses controller.replicaCount
        cmd="${cmd} --set controller.replicaCount=${replicas}"
        log_debug "使用路径: controller.replicaCount"
    elif [[ "${release}" == "velero" ]]; then
        # velero uses deployment.replicas
        cmd="${cmd} --set deployment.replicas=${replicas}"
        log_debug "使用路径: deployment.replicas"
    else
        # Standard components use replicaCount
        cmd="${cmd} --set replicaCount=${replicas}"
        log_debug "使用路径: replicaCount"
    fi

    # Add reuse-values to keep other configurations
    cmd="${cmd} --reuse-values"

    log_debug "构建的命令: ${cmd}"
    echo "${cmd}"
}

# Execute helm upgrade
function execute_helm_upgrade() {
    local cmd="$1"

    log_info "执行 helm upgrade..."
    log_cmd "${cmd}"

    if eval "${cmd}"; then
        log_info "✓ Helm 升级成功完成"
        return 0
    else
        log_error "Helm 升级失败"
        return 1
    fi
}

# Main update function
function update_replicas() {
    local release="$1"
    local namespace="$2"
    local replicas="$3"
    local kind="$4"

    # Initialize log file
    init_log_file "${release}"

    log_info "=========================================="
    log_info "Kubernetes 副本数更新脚本"
    log_info "Release: ${release}"
    [[ "${VERBOSE}" == "true" ]] && log_info "详细模式: 已启用"
    [[ "${DEBUG}" == "true" ]] && log_info "调试模式: 已启用"
    log_info "=========================================="

    log_step "开始副本数更新流程"

    # Display configuration
    log_info "配置信息:"
    log_info "  Release:   ${release}"
    log_info "  命名空间:  ${namespace}"
    log_info "  资源类型:  ${kind}"
    log_info "  副本数量:  ${replicas}"

    # Validate replicas is a positive integer
    if ! [[ "${replicas}" =~ ^[1-9][0-9]*$ ]]; then
        error_exit "副本数必须是正整数: ${replicas}"
    fi

    if [[ "${release}" == "ingress-nginx" ]]; then
        if [[ ${replicas} -gt 3 ]]; then
            error_exit "ingress-nginx 副本数不能超过 3 个 (当前请求: ${replicas})"
        fi
        log_info "✓ ingress-nginx 副本数验证通过 (最大限制: 3)"
    fi

    # Check if chart exists
    if [[ ! -d "${CHARTS_DIR}/${release}" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/${release}"
    fi

    # Build and execute helm upgrade command
    log_step "执行 Helm 升级"
    local helm_cmd=$(build_replica_helm_command "${release}" "${namespace}" "${replicas}" "${kind}")

    if ! execute_helm_upgrade "${helm_cmd}"; then
        error_exit "Helm 升级失败"
    fi

    log_step "✓ 副本数更新成功"
    log_info "Release: ${release}"
    log_info "新副本数: ${replicas}"
    log_info "资源类型: ${kind}"

    # Log file end marker
    if [[ "${ENABLE_LOG_FILE}" == "true" ]] && [[ -n "${LOG_FILE}" ]]; then
        echo "" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
        echo "状态: 成功" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        log_info "日志已保存到: ${LOG_FILE}"
    fi
}

# Main function
function main() {
    # If no arguments, show help
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi

    # Parse arguments
    local RELEASE=""
    local NAMESPACE=""
    local REPLICAS=""
    local KIND=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--debug)
                DEBUG=true
                VERBOSE=true
                shift
                ;;
            -l|--log)
                ENABLE_LOG_FILE=true
                shift
                ;;
            --log-file)
                ENABLE_LOG_FILE=true
                LOG_FILE="$2"
                shift 2
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -k|--kind)
                KIND="$2"
                shift 2
                ;;
            --replicas)
                REPLICAS="$2"
                shift 2
                ;;
            *)
                # First positional argument is release name
                if [[ -z "${RELEASE}" ]] && [[ ! "$1" =~ ^- ]]; then
                    RELEASE="$1"
                    shift
                else
                    error_exit "Unknown option: $1"
                fi
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "${RELEASE}" ]]; then
        error_exit "Release 名称是必需的 (第一个参数)"
    fi

    if [[ -z "${REPLICAS}" ]]; then
        error_exit "副本数是必需的 (--replicas)"
    fi

    if [[ -z "${NAMESPACE}" ]]; then
        error_exit "命名空间是必需的 (-n/--namespace)"
    fi

    if [[ -z "${KIND}" ]]; then
        error_exit "资源类型是必需的 (-k/--kind). 有效值: Deployment, StatefulSet"
    fi

    # Validate kind value
    if [[ ! "${KIND}" =~ ^(Deployment|StatefulSet)$ ]]; then
        error_exit "无效的资源类型: ${KIND}. 有效值: Deployment, StatefulSet"
    fi

    # Execute update
    update_replicas "${RELEASE}" "${NAMESPACE}" "${REPLICAS}" "${KIND}"
}

# Run main function
main "$@"

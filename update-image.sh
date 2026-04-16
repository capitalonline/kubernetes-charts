#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 仓库配置
CHARTS_REPO_DIR="/srv/kubernetes-charts"

# 日志配置
LOG_FILE=""
ENABLE_LOG_FILE=false

# 日志输出函数（同时输出到终端和文件）
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

# 日志函数
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

function log_step() {
    write_log ""
    write_log "${BLUE}===================================================${NC}"
    write_log "${BLUE}[STEP]  ${NC}[$(get_timestamp)] $1"
    write_log "${BLUE}===================================================${NC}"
}

function error_exit() {
    log_error "$1"
    exit 1
}

# 打印帮助信息
function print_help() {
    cat << EOF
使用方法: $0 [选项] <release> [命令选项]

说明:
  本脚本是镜像更新系统的入口脚本，负责：
  1. 同步代码仓库（git pull）
  2. 调用真正的更新脚本 scripts/update-container-image.sh
  
  这样设计的好处：
  - 即使 update.sh 本地文件较旧，也能拉取最新的更新脚本
  - 确保每次更新都使用最新版本的更新逻辑

全局选项:
  -l, --log                           保存日志到 /tmp 目录（自动生成文件名）
  -h, --help                          显示帮助信息

命令:
  <release>                           Helm release 名称（必需）

命令选项:
  -c, --container <name>              容器名称（必需）
  -i, --image <image>                 新镜像（必需）
  -n, --namespace <ns>                命名空间（必需）
  -k, --kind <kind>                   资源类型：Deployment, StatefulSet, DaemonSet（必需）
  -v, --verbose                       详细输出
  -d, --debug                         调试模式

示例:
  # 更新 cronhpa-controller 镜像（Deployment）
  $0 cronhpa-controller -c cronhpa-controller \\
    -i registry-cds.yun-paas.com/cds-eks/kubernetes-cronhpa-controller:v1.1.0 \\
    -n kube-system -k Deployment

  # 更新 Prometheus Node Exporter（DaemonSet）
  $0 prometheus -c node-exporter \\
    -i registry.io/node-exporter:v1.7.0 \\
    -n monitoring -k DaemonSet

  # 更新 Grafana（StatefulSet）
  $0 grafana -c grafana \\
    -i registry.io/grafana:10.0.0 \\
    -n monitoring -k StatefulSet

  # 查看详细帮助信息
  $0 --help

注意:
  - 代码会被同步到 ${CHARTS_REPO_DIR}
  - 真正的更新脚本位于 ${CHARTS_REPO_DIR}/scripts/update-container-image.sh
  - 所有命令选项会透传给更新脚本

EOF
}

# 同步代码仓库
function sync_charts_repo() {
    log_step "同步 Charts 代码仓库"
    
    local max_retries=10
    local retry_count=0
    
    # 如果仓库目录已存在，执行 pull 更新
    if [[ -d "${CHARTS_REPO_DIR}/.git" ]]; then
        log_info "执行 git pull 更新代码..."
        
        while [[ ${retry_count} -lt ${max_retries} ]]; do
            retry_count=$((retry_count + 1))
            
            if cd "${CHARTS_REPO_DIR}" && git pull 2>/dev/null; then
                cd - > /dev/null 2>&1
                log_info "✓ 代码更新成功"
                log_step "✓ 代码仓库同步完成"
                return 0
            fi
            
            cd - > /dev/null 2>&1
            if [[ ${retry_count} -lt ${max_retries} ]]; then
                log_warn "git pull 失败，1秒后重试... (${retry_count}/${max_retries})"
                sleep 1
            fi
        done
        
        error_exit "git pull 失败，已重试 ${max_retries} 次"
    else
        # 仓库不存在，报错退出
        error_exit "仓库目录不存在: ${CHARTS_REPO_DIR}"
    fi
}

# 主函数
function main() {
    # 如果没有参数，显示帮助
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi
    
    # 收集所有参数，用于传递给真正的更新脚本
    local all_args=()
    local has_command=false
    local release_name=""
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--log)
                ENABLE_LOG_FILE=true
                # 不要将 -l 参数传递给子脚本
                shift
                ;;
            -h|--help)
                # 如果只是请求帮助，先同步代码，然后调用更新脚本的帮助
                sync_charts_repo
                exec "${CHARTS_REPO_DIR}/scripts/update-container-image.sh" --help
                ;;
            *)
                # 其他参数收集起来传递给更新脚本
                has_command=true
                # 捕获第一个非选项参数作为 release 名称（用于日志文件名）
                if [[ -z "${release_name}" ]] && [[ ! "$1" =~ ^- ]]; then
                    release_name="$1"
                fi
                all_args+=("$1")
                shift
                ;;
        esac
    done
    
    # 检查是否有命令
    if [[ "${has_command}" == "false" ]]; then
        log_error "未指定更新命令"
        echo ""
        print_help
        exit 1
    fi
    
    log_info "=========================================="
    log_info "Kubernetes 镜像更新入口"
    log_info "仓库目录: ${CHARTS_REPO_DIR}"
    log_info "=========================================="
    
    # 生成日志文件名（如果启用了日志）
    if [[ "${ENABLE_LOG_FILE}" == "true" ]]; then
        # 如果没有 release 名称，使用默认名称
        local log_component="${release_name:-update}"
        LOG_FILE="/tmp/k8s-update-image-${log_component}-$(date +%Y%m%d-%H%M%S).log"
    fi
    
    # 初始化日志文件
    if [[ "${ENABLE_LOG_FILE}" == "true" ]]; then
        # 创建日志文件
        touch "${LOG_FILE}" 2>/dev/null || {
            log_error "无法创建日志文件: ${LOG_FILE}"
            exit 1
        }
        
        # 写入日志头部
        echo "======================================" >> "${LOG_FILE}"
        echo "Kubernetes 镜像更新日志" >> "${LOG_FILE}"
        echo "Release: ${release_name:-unknown}" >> "${LOG_FILE}"
        echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "" >> "${LOG_FILE}"
        
        log_info "日志将保存到: ${LOG_FILE}"
    fi
    
    # 同步代码仓库
    sync_charts_repo
    
    # 调用真正的更新脚本
    log_step "调用镜像更新脚本"
    log_info "执行: ${CHARTS_REPO_DIR}/scripts/update-container-image.sh ${all_args[*]}"
    
    # 如果启用了日志，传递日志文件路径给更新脚本
    if [[ "${ENABLE_LOG_FILE}" == "true" ]]; then
        exec "${CHARTS_REPO_DIR}/scripts/update-container-image.sh" --log-file "${LOG_FILE}" "${all_args[@]}"
    else
        exec "${CHARTS_REPO_DIR}/scripts/update-container-image.sh" "${all_args[@]}"
    fi
}

# 执行主函数
main "$@"


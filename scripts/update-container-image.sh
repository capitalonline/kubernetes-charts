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
            LOG_FILE="/tmp/k8s-update-image-${release}-$(date +%Y%m%d-%H%M%S).log"
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
        echo "镜像更新脚本执行日志" >> "${LOG_FILE}"
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
    log_error "镜像更新失败，请检查上述错误信息"
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
  Update container image version in Helm charts using helm upgrade --set.

Arguments:
  <release>                   Helm release name (required)

Options:
  -c, --container <name>      Container name (required)
  -i, --image <image>         New image (format: [registry/]repository:tag) (required)
  -n, --namespace <ns>        Kubernetes namespace (required)
  -k, --kind <kind>           Resource kind: Deployment, StatefulSet, or DaemonSet (required)
  
  -v, --verbose               Enable verbose output
  -d, --debug                 Enable debug mode
  -l, --log                   Enable log file (auto-generated name)
  --log-file <path>           Specify log file path
  -h, --help                  Show this help message

Examples:
  # Update cronhpa-controller image (Deployment)
  $0 cronhpa-controller -c cronhpa-controller \\
    -i harbor-dev.yun-paas.com/dev/kubernetes-cronhpa-controller:v1.1.0 \\
    -n kube-system -k Deployment

  # Update prometheus node-exporter (DaemonSet)
  $0 prometheus -c node-exporter \\
    -i registry.io/node-exporter:v1.7.0 \\
    -n monitoring -k DaemonSet

  # Update grafana (StatefulSet) with logging enabled
  $0 grafana -c grafana \\
    -i registry.io/grafana:10.0.0 \\
    -n monitoring -k StatefulSet -l

Component to Container Mapping:
  prometheus          → prometheus, node-exporter, kube-state-metrics, 
                        blackbox-exporter, prometheus-operator, config-reloader,
                        kube-rbac-proxy, module-configmap-reloader
  alertmanager        → alertmanager, config-reloader
  grafana             → grafana
  loki                → loki, promtail-container, event-exporter
  dcgm-exporter       → dcgm-exporter, kube-rbac-proxy
  prometheus-adapter  → prometheus-adapter
  cronhpa-controller  → cronhpa-controller
  vpc-cni             → cni-daemon, cni-manager, vpc-cni-webhook, install-cni
  csi-nfs            → csi-provisioner, csi-resizer, csi-snapshotter,
                      livenessprobe, node-driver-registrar, nfs
  cloud-controller-manager  → cds-cloud-controller-manager
  velero              → velero, velero-plugin-for-aws, node-agent

EOF
}

# Parse image string
function parse_image() {
    local image="$1"
    local registry=""
    local repository=""
    local tag=""
    
    # Extract tag
    if [[ "${image}" == *":"* ]]; then
        tag="${image##*:}"
        image="${image%:*}"
    else
        error_exit "镜像必须包含标签 (格式: repository:tag 或 registry/repository:tag)"
    fi
    
    # Extract registry and repository
    if [[ "${image}" == *"/"* ]]; then
        # Count slashes to determine if registry is present
        local slash_count=$(echo "${image}" | tr -cd '/' | wc -c | tr -d ' ')
        if [[ ${slash_count} -ge 2 ]] || [[ "${image}" == *"."* ]]; then
            # Has registry (contains . or multiple /)
            registry="${image%%/*}"
            repository="${image#*/}"
        else
            # No registry, just repository with namespace
            repository="${image}"
        fi
    else
        repository="${image}"
    fi
    
    echo "${registry}|${repository}|${tag}"
}

# Build helm upgrade command
function build_helm_command() {
    local release="$1"
    local namespace="$2"
    local container="$3"
    local image_registry="$4"
    local image_repository="$5"
    local image_tag="$6"
    
    log_debug "构建 helm upgrade 命令..."
    log_debug "  Release: ${release}"
    log_debug "  命名空间: ${namespace}"
    log_debug "  容器: ${container}"
    log_debug "  仓库地址: ${image_registry}"
    log_debug "  镜像名: ${image_repository}"
    log_debug "  标签: ${image_tag}"
    
    # Build values path for container
    local values_path="container.${container}.image"
    
    # Build base command
    local cmd="helm upgrade ${release} ${CHARTS_DIR}/${release} -n ${namespace}"
    
    # Special handling for cloud-controller-manager
    # This chart uses image.repository and image.tag directly (not container.<name>.image)
    if [[ "${release}" == "cloud-controller-manager" ]]; then
        # Add image configuration
        if [[ -n "${image_registry}" ]]; then
            local full_repo="${image_registry}/${image_repository}"
            cmd="${cmd} --set image.repository=${full_repo}"
        else
            cmd="${cmd} --set image.repository=${image_repository}"
        fi
        
        cmd="${cmd} --set image.tag=${image_tag}"
    elif [[ "${release}" == "ingress-nginx" ]]; then
            cmd="${cmd} --set controller.image.registry=${image_registry}"
            cmd="${cmd} --set controller.image.image=${image_repository}"
            cmd="${cmd} --set controller.image.tag=${image_tag}"
    elif [[ "${release}" == "kubeprober" ]]; then
           cmd="${cmd} --set probeAgent.image.repository=${image_registry}/${image_repository}"
           cmd="${cmd} --set probeAgent.image.tag=${image_tag}"
    else
        # Standard path for other charts
        # Add image configuration
        if [[ -n "${image_registry}" ]]; then
            local full_repo="${image_registry}/${image_repository}"
            cmd="${cmd} --set ${values_path}.repository=${full_repo}"
        else
            cmd="${cmd} --set ${values_path}.repository=${image_repository}"
        fi
        
        cmd="${cmd} --set ${values_path}.tag=${image_tag}"
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
function update_image() {
    local release="$1"
    local namespace="$2"
    local container="$3"
    local image="$4"
    local kind="$5"
    
    # Initialize log file
    init_log_file "${release}"
    
    log_info "=========================================="
    log_info "Kubernetes 镜像更新脚本"
    log_info "Release: ${release}"
    [[ "${VERBOSE}" == "true" ]] && log_info "详细模式: 已启用"
    [[ "${DEBUG}" == "true" ]] && log_info "调试模式: 已启用"
    log_info "=========================================="
    
    log_step "开始镜像更新流程"
    
    # Display configuration
    log_info "配置信息:"
    log_info "  Release:   ${release}"
    log_info "  命名空间:  ${namespace}"
    log_info "  资源类型:  ${kind}"
    log_info "  容器名称:  ${container}"
    log_info "  镜像地址:  ${image}"
    
    # Parse image
    local parsed=$(parse_image "${image}")
    IFS='|' read -r image_registry image_repository image_tag <<< "${parsed}"
    
    log_info "解析镜像组件:"
    [[ -n "${image_registry}" ]] && log_info "  仓库地址:  ${image_registry}"
    log_info "  镜像名称:  ${image_repository}"
    log_info "  标签版本:  ${image_tag}"
    
    # Build full image string for verification
    local full_image="${image_repository}:${image_tag}"
    if [[ -n "${image_registry}" ]]; then
        full_image="${image_registry}/${full_image}"
    fi
    
    # Check if chart exists
    if [[ ! -d "${CHARTS_DIR}/${release}" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/${release}"
    fi
    
    # Build and execute helm upgrade command
    log_step "执行 Helm 升级"
    local helm_cmd=$(build_helm_command "${release}" "${namespace}" "${container}" \
        "${image_registry}" "${image_repository}" "${image_tag}")
    
    if ! execute_helm_upgrade "${helm_cmd}"; then
        error_exit "Helm 升级失败"
    fi
    
    log_step "✓ 镜像更新成功"
    log_info "Release: ${release}"
    log_info "容器名称: ${container}"
    log_info "新镜像: ${full_image}"
    
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
    local CONTAINER=""
    local IMAGE=""
    local KIND=""
    
    # Parse global options first
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
            -c|--container)
                CONTAINER="$2"
                shift 2
                ;;
            -i|--image)
                IMAGE="$2"
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
    
    if [[ -z "${CONTAINER}" ]]; then
        error_exit "容器名称是必需的 (-c/--container)"
    fi
    
    if [[ -z "${IMAGE}" ]]; then
        error_exit "镜像地址是必需的 (-i/--image)"
    fi
    
    if [[ -z "${NAMESPACE}" ]]; then
        error_exit "命名空间是必需的 (-n/--namespace)"
    fi
    
    if [[ -z "${KIND}" ]]; then
        error_exit "资源类型是必需的 (-k/--kind). 有效值: Deployment, StatefulSet, DaemonSet"
    fi
    
    # Validate kind value
    if [[ ! "${KIND}" =~ ^(Deployment|StatefulSet|DaemonSet)$ ]]; then
        error_exit "无效的资源类型: ${KIND}. 有效值: Deployment, StatefulSet, DaemonSet"
    fi
    
    # Execute update
    update_image "${RELEASE}" "${NAMESPACE}" "${CONTAINER}" "${IMAGE}" "${KIND}"
}

# Run main function
main "$@"

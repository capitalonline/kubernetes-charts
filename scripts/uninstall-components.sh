#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认配置
NAMESPACE="monitoring"
VERBOSE=false
DEBUG=false
LOG_FILE=""
ENABLE_LOG_FILE=false

# 初始化日志文件
function init_log_file() {
    local component="$1"
    if [[ "${ENABLE_LOG_FILE}" == "true" ]]; then
        if [[ -z "${LOG_FILE}" ]]; then
            # 自动生成日志文件名，包含组件名称
            LOG_FILE="/tmp/k8s-uninstall-${component}-$(date +%Y%m%d-%H%M%S).log"
        fi
        
        # 检查日志文件是否已存在（由入口脚本创建）
        local is_new_log=false
        if [[ ! -f "${LOG_FILE}" ]]; then
            is_new_log=true
            # 创建日志文件
            touch "${LOG_FILE}" 2>/dev/null || {
                echo -e "${RED}[ERROR]${NC} 无法创建日志文件: ${LOG_FILE}"
                exit 1
            }
        fi
        
        # 只在新日志文件时显示提示（避免重复提示）
        if [[ "${is_new_log}" == "true" ]]; then
            echo -e "${GREEN}[INFO]${NC} 日志将保存到: ${LOG_FILE}"
        fi
        
        # 追加卸载脚本的日志头部
        echo "" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "卸载脚本执行日志" >> "${LOG_FILE}"
        echo "组件: ${component}" >> "${LOG_FILE}"
        echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "" >> "${LOG_FILE}"
    fi
}

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

# 错误处理
function error_exit() {
    log_error "$1"
    log_error "卸载失败，请检查上述错误信息"
    if [[ "${ENABLE_LOG_FILE}" == "true" ]] && [[ -n "${LOG_FILE}" ]]; then
        log_error "详细日志已保存到: ${LOG_FILE}"
    fi
    exit 1
}

# 打印帮助信息
function print_help() {
    cat << EOF
使用方法: $0 <命令> [选项]

命令:
  prometheus                          卸载 Prometheus（包含内置的 Exporters）
  alertmanager                        卸载 Alertmanager
  grafana                             卸载 Grafana
  loki                                卸载 Loki
  dcgm-exporter                       卸载 DCGM Exporter
  prometheus-adapter                  卸载 Prometheus Adapter
  alertmanager-webhook-adapter        卸载 Alertmanager Webhook Adapter
  cronhpa-controller                  卸载 CronHPA Controller
  vpc-cni                             卸载 VPC CNI 网络插件
  csi-nfs                             卸载 CSI NFS 驱动
  p2p-accelerator                     卸载 P2P Accelerator 镜像加速
  csi-disk                            卸载 CSI Disk 存储插件
  csi-oss                             卸载 CSI OSS 对象存储插件
  kubeprober                          卸载 KubeProber 集群诊断工具
  node-agent                          卸载 Node Agent 绑核组件
  cloud-controller-manager                      卸载云控制器
  ingress-nginx                       卸载 ingress-nginx 控制器
  velero                              卸载 Velero 备份与恢复组件

全局选项:
  -v, --verbose                       显示详细信息（包括执行的命令）
  -d, --debug                         调试模式（显示更详细的调试信息）
  -l, --log                           保存日志到 /tmp 目录（自动生成文件名）
  --log-file FILE                     保存日志到指定文件
  --delete-secrets                    同时删除 secrets
  -h, --help                          显示帮助信息

示例:
  # 卸载单个组件
  $0 prometheus

  # 卸载组件并删除 secrets
  $0 prometheus --delete-secrets

  # 启用详细模式
  $0 -v prometheus

  # 启用调试模式并保存日志
  $0 -d -l prometheus

  # 保存日志到指定文件
  $0 --log-file /var/log/uninstall.log prometheus

EOF
}

# 卸载组件
function uninstall_component() {
    local component=$1
    
    log_debug "检查组件 ${component} 是否已安装..."
    log_debug "执行: helm status ${component} -n ${NAMESPACE}"
    
    if helm status ${component} -n ${NAMESPACE} &> /dev/null; then
        log_info "卸载 ${component}..."
        log_cmd "helm uninstall ${component} -n ${NAMESPACE}"
        if helm uninstall ${component} -n ${NAMESPACE}; then
            log_info "✓ ${component} 卸载完成"
        else
            log_error "${component} 卸载失败"
            return 1
        fi
    else
        log_warn "${component} 未安装，跳过"
    fi
}

# 删除 secrets
function delete_secrets() {
    log_step "删除 Secrets"
    
    log_debug "检查 etcd-certs secret..."
    if kubectl -n ${NAMESPACE} get secret etcd-certs &> /dev/null; then
        log_cmd "kubectl -n ${NAMESPACE} delete secret etcd-certs"
        kubectl -n ${NAMESPACE} delete secret etcd-certs
        log_info "✓ 已删除 etcd-certs secret"
    else
        log_warn "etcd-certs secret 不存在，跳过"
    fi
    
    log_debug "检查 monitoring-certs secret..."
    if kubectl -n ${NAMESPACE} get secret monitoring-certs &> /dev/null; then
        log_cmd "kubectl -n ${NAMESPACE} delete secret monitoring-certs"
        kubectl -n ${NAMESPACE} delete secret monitoring-certs
        log_info "✓ 已删除 monitoring-certs secret"
    else
        log_warn "monitoring-certs secret 不存在，跳过"
    fi
}

# 删除 PVC 和 PV
function delete_pvc() {
    local component="$1"
    local namespace="$2"
    
    log_step "删除 PVC 和 PV"
    
    case ${component} in
        prometheus)
            log_debug "检查 Prometheus PVC..."
            local pvc_name="prometheus-k8s-db-prometheus-k8s-0"
            if kubectl -n ${namespace} get pvc ${pvc_name} &> /dev/null; then
                log_info "删除 PVC: ${pvc_name}"
                log_cmd "kubectl -n ${namespace} delete pvc ${pvc_name}"
                kubectl -n ${namespace} delete pvc ${pvc_name}
                log_info "✓ 已删除 PVC: ${pvc_name}"
            else
                log_debug "Prometheus PVC 不存在，跳过"
            fi
            ;;
        grafana)
            log_debug "检查 Grafana PVC..."
            local pvc_name="grafana-pvc-grafana-0"
            if kubectl -n ${namespace} get pvc ${pvc_name} &> /dev/null; then
                log_info "删除 PVC: ${pvc_name}"
                log_cmd "kubectl -n ${namespace} delete pvc ${pvc_name}"
                kubectl -n ${namespace} delete pvc ${pvc_name}
                log_info "✓ 已删除 PVC: ${pvc_name}"
            else
                log_debug "Grafana PVC 不存在，跳过"
            fi
            ;;
        loki)
            log_debug "检查 Loki PVC..."
            local pvc_name="loki-pvc-loki-0"
            if kubectl -n ${namespace} get pvc ${pvc_name} &> /dev/null; then
                log_info "删除 PVC: ${pvc_name}"
                log_cmd "kubectl -n ${namespace} delete pvc ${pvc_name}"
                kubectl -n ${namespace} delete pvc ${pvc_name}
                log_info "✓ 已删除 PVC: ${pvc_name}"
            else
                log_debug "Loki PVC 不存在，跳过"
            fi
            ;;
        *)
            log_debug "${component} 不使用 PVC/PV，跳过"
            ;;
    esac
}

# 主函数
function main() {
    local delete_sec=false
    
    # 如果没有参数，显示帮助
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --delete-secrets)
                delete_sec=true
                shift
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            cronhpa-controller|vpc-cni|p2p-accelerator|csi-disk|csi-oss|csi-nfs|node-agent|cloud-controller-manager|ingress-nginx|kubeprober|velero)
                local component="$1"
                shift
                
                # 保存用户输入的所有参数
                local user_args="$*"
                
                # 初始化日志文件
                init_log_file "${component}"
                
                log_info "=========================================="
                log_info "Kubernetes 组件卸载脚本"
                log_info "命令: ${component}"
                [[ "${VERBOSE}" == "true" ]] && log_info "详细模式: 已启用"
                [[ "${DEBUG}" == "true" ]] && log_info "调试模式: 已启用"
                log_info "=========================================="
                
                # 打印用户输入的所有参数
                if [[ -n "${user_args}" ]]; then
                    log_info "用户输入参数: ${user_args}"
                else
                    log_info "用户输入参数: (无)"
                fi
                
                # 确定目标命名空间
                local target_ns="kube-system"
                if [[ "${component}" == "ingress-nginx" ]]; then
                    target_ns="ingress-nginx"
                elif [[ "${component}" == "kubeprober" ]]; then
                    target_ns="kubeprober"
                elif [[ "${component}" == "velero" ]]; then
                    target_ns="velero"
                fi

                log_step "开始卸载 ${component}"
                
                log_debug "检查组件 ${component} (${target_ns})..."
                if helm status ${component} -n ${target_ns} &> /dev/null; then
                    log_info "卸载 ${component} (${target_ns})..."
                    log_cmd "helm uninstall ${component} -n ${target_ns}"
                    if helm uninstall ${component} -n ${target_ns}; then
                        log_info "✓ ${component} 卸载完成"
                    else
                        error_exit "${component} 卸载失败"
                    fi
                else
                    log_warn "${component} 未安装在 ${target_ns} 命名空间"
                fi
                
                # 如果是 kubeprober，提示 CRDs 保留信息
                if [[ "${component}" == "kubeprober" ]]; then
                    log_info ""
                    log_info "KubeProber CRDs 仍然保留在集群中"
                    log_info "如需删除 CRDs，请手动执行："
                    log_info "  kubectl delete -f charts/kubeprober/crds/"
                    log_info ""
                    log_warn "注意：删除 CRDs 会同时删除所有相关的自定义资源（Probes、ProbeStatuses、Alerts）"
                fi

                # 如果是 velero，提示 CRDs 保留信息
                if [[ "${component}" == "velero" ]]; then
                    log_info ""
                    log_info "Velero CRDs 仍然保留在集群中"
                    log_info "如需删除 CRDs，请手动执行："
                    log_info "  kubectl delete crd -l app.kubernetes.io/name=velero"
                    log_info ""
                    log_warn "注意：删除 CRDs 会同时删除所有备份记录（Backup、Restore、Schedule 等资源）"
                fi

                log_step "✓ 卸载操作完成"
                
                # 日志文件结束标记
                if [[ "${ENABLE_LOG_FILE}" == "true" ]] && [[ -n "${LOG_FILE}" ]]; then
                    echo "" >> "${LOG_FILE}"
                    echo "======================================" >> "${LOG_FILE}"
                    echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
                    echo "状态: 成功" >> "${LOG_FILE}"
                    echo "======================================" >> "${LOG_FILE}"
                    log_info "日志已保存到: ${LOG_FILE}"
                fi
                
                exit 0
                ;;
            prometheus|alertmanager|grafana|loki|dcgm-exporter|prometheus-adapter|alertmanager-webhook-adapter)
                local component="$1"
                shift
                
                # 保存用户输入的所有参数
                local user_args="$*"
                
                # 初始化日志文件
                init_log_file "${component}"
                
                log_info "=========================================="
                log_info "Kubernetes 组件卸载脚本"
                log_info "命令: ${component}"
                [[ "${VERBOSE}" == "true" ]] && log_info "详细模式: 已启用"
                [[ "${DEBUG}" == "true" ]] && log_info "调试模式: 已启用"
                log_info "=========================================="
                
                # 打印用户输入的所有参数
                if [[ -n "${user_args}" ]]; then
                    log_info "用户输入参数: ${user_args}"
                else
                    log_info "用户输入参数: (无)"
                fi
                
                # monitoring 命名空间的组件使用固定命名空间
                NAMESPACE="monitoring"
                
                # 检查命名空间是否存在
                if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
                    error_exit "命名空间 ${NAMESPACE} 不存在"
                fi
                
                log_step "开始卸载 ${component}"
                
                uninstall_component "${component}"
                
                # 如果指定了 --delete-secrets，删除 secrets
                if [[ ${delete_sec} == true ]]; then
                    delete_secrets
                fi
                
                # 自动删除 PVC（如果组件使用了 PVC）
                delete_pvc "${component}" "${NAMESPACE}"
                
                log_step "✓ 卸载操作完成"
                
                # 日志文件结束标记
                if [[ "${ENABLE_LOG_FILE}" == "true" ]] && [[ -n "${LOG_FILE}" ]]; then
                    echo "" >> "${LOG_FILE}"
                    echo "======================================" >> "${LOG_FILE}"
                    echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
                    echo "状态: 成功" >> "${LOG_FILE}"
                    echo "======================================" >> "${LOG_FILE}"
                    log_info "日志已保存到: ${LOG_FILE}"
                fi
                
                exit 0
                ;;
            *)
                log_error "未知命令: $1"
                echo ""
                print_help
                exit 1
                ;;
        esac
    done
}

# 执行主函数
main "$@"

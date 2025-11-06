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

# Charts 目录配置
# 注意：此脚本由入口脚本 install.sh 调用，代码同步在入口脚本中完成
CHARTS_REPO_DIR="/srv/kubernetes-charts"
CHARTS_DIR="${CHARTS_REPO_DIR}/charts"

# 初始化日志文件
function init_log_file() {
    local component="$1"
    if [[ "${ENABLE_LOG_FILE}" == "true" ]]; then
        if [[ -z "${LOG_FILE}" ]]; then
            # 自动生成日志文件名，包含组件名称
            LOG_FILE="/tmp/k8s-monitoring-install-${component}-$(date +%Y%m%d-%H%M%S).log"
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
        
        # 追加安装脚本的日志头部
        echo "" >> "${LOG_FILE}"
        echo "======================================" >> "${LOG_FILE}"
        echo "安装脚本执行日志" >> "${LOG_FILE}"
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
    log_error "安装失败，请检查上述错误信息"
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
  prometheus [选项]                   安装 Prometheus（会自动初始化）
  alertmanager [选项]                 安装 Alertmanager
  grafana [选项]                      安装 Grafana
  loki [选项]                         安装 Loki
  dcgm-exporter                       安装 DCGM Exporter
  prometheus-adapter                  安装 Prometheus Adapter
  alertmanager-webhook-adapter        安装 Alertmanager Webhook Adapter
  cronhpa-controller                  安装 CronHPA Controller
  vpc-cni [选项]                      安装 VPC CNI 网络插件
  all                                 安装所有组件（使用默认参数）

全局选项:
  -n, --namespace NAME                命名空间 (默认: monitoring)
  -v, --verbose                       显示详细信息（包括执行的命令）
  -d, --debug                         调试模式（显示更详细的调试信息）
  -l, --log                           保存日志到 /tmp 目录（自动生成文件名）
  --log-file FILE                     保存日志到指定文件
  -h, --help                          显示帮助信息

示例:
  # 安装 Prometheus（使用默认参数，会自动初始化）
  $0 prometheus

  # 安装 Prometheus（自定义参数，ETCD 端点自动检测）
  $0 prometheus --retention 7d --storage-size 50Gi \\
    --ingress prometheus.example.com,prometheus-internal.example.com \\
    --htpasswd admin:admin

  # 安装 Grafana
  $0 grafana --storage-size 100Gi --ingress grafana.example.com

  # 在自定义命名空间安装
  $0 -n mon prometheus

  # 安装所有组件
  $0 all

  # 启用详细模式
  $0 -v prometheus

  # 启用调试模式（包含详细输出和调试信息）
  $0 -d prometheus --retention 7d

  # 保存日志到 /tmp 目录
  $0 -l prometheus

  # 保存日志到指定文件
  $0 --log-file /var/log/prometheus-install.log prometheus

组件特定选项:

  prometheus:
    --retention TIME              数据保留时间 (默认: 1d)
    --storage-class CLASS         存储类 (默认: default-local-sc)
    --storage-size SIZE           存储大小 (默认: 10Gi)
    --ingress HOST1,HOST2         Ingress 主机名
    --htpasswd USER:PASS          HTTP 基本认证 (格式: username:password 或 username:$apr1$hash...)
    
    注意: ETCD 端点会自动从集群检测（kubectl get pod -n kube-system -l component=etcd）

  alertmanager:
    --ingress HOST1,HOST2         Ingress 主机名
    --htpasswd USER:PASS          HTTP 基本认证 (格式: username:password 或 username:$apr1$hash...)
    --enable-rules                启用 Prometheus Rules (默认禁用，包含 8 个预定义告警规则)

  grafana:
    --storage-class CLASS         存储类 (默认: default-local-sc)
    --storage-size SIZE           存储大小 (默认: 50Gi)
    --ingress HOST1,HOST2         Ingress 主机名

  loki:
    --retention TIME              日志数据保留期限 (默认: 30d)
    --max-query-length TIME       单次查询最大时间范围 (默认: 30d)
    --storage-class CLASS         存储类 (默认: default-local-sc)
    --storage-size SIZE           存储大小 (默认: 50Gi)

EOF
}

# 初始化逻辑函数（内部函数，供其他函数调用）
function do_init() {
    log_step "开始初始化监控组件环境"
    log_info "目标命名空间: ${NAMESPACE}"
    
    # 创建命名空间
    log_info "检查命名空间是否存在..."
    log_debug "执行: kubectl get namespace ${NAMESPACE}"
    if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
        log_info "命名空间 ${NAMESPACE} 不存在，开始创建..."
        log_cmd "kubectl create namespace ${NAMESPACE}"
        if kubectl create namespace ${NAMESPACE}; then
            log_info "✓ 命名空间 ${NAMESPACE} 创建成功"
        else
            error_exit "创建命名空间 ${NAMESPACE} 失败"
        fi
    else
        log_warn "命名空间 ${NAMESPACE} 已存在，跳过创建"
    fi
    
    # 创建 etcd-certs secret
    log_info "检查 etcd-certs secret..."
    log_debug "执行: kubectl -n ${NAMESPACE} get secret etcd-certs"
    if kubectl -n ${NAMESPACE} get secret etcd-certs &> /dev/null; then
        log_warn "Secret etcd-certs 已存在，跳过创建"
    else
        log_info "检查 ETCD 证书文件..."
        log_debug "证书路径: /etc/kubernetes/pki/etcd/"
        if [[ -f /etc/kubernetes/pki/etcd/healthcheck-client.crt ]] && \
           [[ -f /etc/kubernetes/pki/etcd/healthcheck-client.key ]] && \
           [[ -f /etc/kubernetes/pki/etcd/ca.crt ]]; then
            log_info "ETCD 证书文件存在，创建 secret..."
            log_cmd "kubectl -n ${NAMESPACE} create secret generic etcd-certs --from-file=..."
            if kubectl -n ${NAMESPACE} create secret generic etcd-certs \
              --from-file=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
              --from-file=/etc/kubernetes/pki/etcd/healthcheck-client.key \
              --from-file=/etc/kubernetes/pki/etcd/ca.crt; then
                log_info "✓ etcd-certs secret 创建成功"
            else
                error_exit "创建 etcd-certs secret 失败"
            fi
        else
            log_error "ETCD 证书文件不存在"
            log_error "请确保以下文件存在:"
            log_error "  - /etc/kubernetes/pki/etcd/healthcheck-client.crt"
            log_error "  - /etc/kubernetes/pki/etcd/healthcheck-client.key"
            log_error "  - /etc/kubernetes/pki/etcd/ca.crt"
            error_exit "无法创建 etcd-certs secret，ETCD 证书文件缺失"
        fi
    fi
    
    # 创建 monitoring-certs secret
    log_info "检查 monitoring-certs secret..."
    log_debug "执行: kubectl -n ${NAMESPACE} get secret monitoring-certs"
    if kubectl -n ${NAMESPACE} get secret monitoring-certs &> /dev/null; then
        log_warn "Secret monitoring-certs 已存在，跳过创建"
    else
        log_info "检查 TLS 证书文件..."
        log_debug "证书路径: /tmp/yun-paas.key, /tmp/yun-paas.crt"
        if [[ -f /tmp/yun-paas.key ]] && [[ -f /tmp/yun-paas.crt ]]; then
            log_info "TLS 证书文件存在，创建 secret..."
            log_cmd "kubectl -n ${NAMESPACE} create secret tls monitoring-certs --key ... --cert ..."
            if kubectl -n ${NAMESPACE} create secret tls monitoring-certs \
              --key /tmp/yun-paas.key --cert /tmp/yun-paas.crt; then
                log_info "✓ monitoring-certs secret 创建成功"
            else
                error_exit "创建 monitoring-certs secret 失败"
            fi
        else
            log_error "TLS 证书文件不存在"
            log_error "请确保以下文件存在:"
            log_error "  - /tmp/yun-paas.key"
            log_error "  - /tmp/yun-paas.crt"
            error_exit "无法创建 monitoring-certs secret，TLS 证书文件缺失"
        fi
    fi
    
    log_step "✓ 初始化完成"
}


# 安装 Prometheus
function cmd_prometheus() {
    # 先执行初始化
    do_init
    
    log_step "开始安装 Prometheus"
    
    local retention="1d"
    local storage_class="default-local-sc"
    local storage_size="10Gi"
    local ingress_hosts=""
    local htpasswd=""
    
    # 解析参数
    log_debug "解析安装参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --retention)
                retention="$2"
                log_debug "设置 retention=${retention}"
                shift 2
                ;;
            --storage-class)
                storage_class="$2"
                log_debug "设置 storage-class=${storage_class}"
                shift 2
                ;;
            --storage-size)
                storage_size="$2"
                log_debug "设置 storage-size=${storage_size}"
                shift 2
                ;;
            --ingress)
                ingress_hosts="$2"
                log_debug "设置 ingress=${ingress_hosts}"
                shift 2
                ;;
            --htpasswd)
                htpasswd="$2"
                log_debug "设置 htpasswd=${htpasswd}"
                shift 2
                ;;
            *)
                error_exit "未知选项: $1"
                ;;
        esac
    done
    
    # 自动检测 ETCD 端点
    log_info "自动检测 ETCD 端点..."
    log_debug "执行: kubectl get pod -n kube-system -l component=etcd -o wide"
    
    # 获取 ETCD Pod 的 IP 和 NODE
    local etcd_list=()
    while IFS= read -r line; do
        if [[ -z "${line}" ]]; then
            continue
        fi
        
        # 解析 Pod 信息（格式：POD_NAME NODE）
        local pod_name=$(echo "${line}" | awk '{print $1}')
        local node_name=$(echo "${line}" | awk '{print $7}')
        local pod_ip=$(echo "${line}" | awk '{print $6}')
        
        if [[ -n "${pod_ip}" ]] && [[ -n "${node_name}" ]] && [[ "${pod_ip}" != "<none>" ]]; then
            etcd_list+=("${pod_ip}:${node_name}")
            log_debug "检测到 ETCD Pod: ${pod_name} -> ${pod_ip}:${node_name}"
        fi
    done < <(kubectl get pod -n kube-system -l component=etcd -o wide --no-headers 2>/dev/null)
    
    # 检查是否检测到 ETCD 端点
    if [[ ${#etcd_list[@]} -eq 0 ]]; then
        error_exit "未检测到任何 ETCD Pod，请检查集群状态（kubectl get pod -n kube-system -l component=etcd）"
    fi
    
    # 拼接为逗号分隔的字符串
    local etcd_endpoints=$(IFS=,; echo "${etcd_list[*]}")
    log_info "✓ 自动检测到 ${#etcd_list[@]} 个 ETCD 端点"
    log_debug "ETCD 端点字符串: ${etcd_endpoints}"
    
    # 显示配置信息
    log_info "Prometheus 安装配置:"
    log_info "  命名空间: ${NAMESPACE}"
    log_info "  数据保留: ${retention}"
    log_info "  存储类: ${storage_class}"
    log_info "  存储大小: ${storage_size}"
    if [[ -n "${ingress_hosts}" ]]; then
        log_info "  Ingress: ${ingress_hosts}"
    fi
    if [[ -n "${htpasswd}" ]]; then
        log_info "  认证: 已启用"
    fi
    
    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/prometheus"
    if [[ ! -d "${CHARTS_DIR}/prometheus" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/prometheus"
    fi
    
    # 构建 helm 命令
    log_info "构建 Helm 安装命令..."
    local helm_args=(
        "install" "prometheus" "${CHARTS_DIR}/prometheus"
        "-n" "${NAMESPACE}" "--create-namespace"
        "--set" "prometheus.retention=${retention}"
        "--set" "prometheus.storage.storageClassName=${storage_class}"
        "--set" "prometheus.storage.size=${storage_size}"
    )
    
    # 添加 ingress hosts
    if [[ -n "${ingress_hosts}" ]]; then
        log_debug "添加 Ingress 配置..."
        IFS=',' read -ra HOSTS <<< "${ingress_hosts}"
        for i in "${!HOSTS[@]}"; do
            log_debug "  ingress.hosts[$i]=${HOSTS[$i]}"
            helm_args+=("--set" "ingress.hosts[$i]=${HOSTS[$i]}")
        done
    fi
    
    # 添加 etcd endpoints
    if [[ -n "${etcd_endpoints}" ]]; then
        log_debug "添加 ETCD 端点配置..."
        IFS=',' read -ra ENDPOINTS <<< "${etcd_endpoints}"
        for i in "${!ENDPOINTS[@]}"; do
            IFS=':' read -r ip nodename <<< "${ENDPOINTS[$i]}"
            log_debug "  etcd.endpoints[$i].ip=${ip}"
            log_debug "  etcd.endpoints[$i].nodeName=${nodename}"
            helm_args+=("--set" "etcd.endpoints[$i].ip=${ip}")
            helm_args+=("--set" "etcd.endpoints[$i].nodeName=${nodename}")
        done
    fi
    
    # 添加 htpasswd 认证
    if [[ -n "${htpasswd}" ]]; then
        log_debug "添加 HTTP 基本认证配置..."
        helm_args+=("--set" "prometheus.auth.enabled=true")
        helm_args+=("--set" "prometheus.auth.htpasswd=${htpasswd}")
    fi
    
    # 显示完整的 helm 命令
    log_cmd "helm ${helm_args[*]}"
    
    # 执行安装
    log_info "开始执行 Helm 安装..."
    if helm "${helm_args[@]}"; then
        log_step "✓ Prometheus 安装成功"
    else
        error_exit "Prometheus 安装失败，请检查 Helm 输出"
    fi
}

# 安装 Alertmanager
function cmd_alertmanager() {
    log_step "开始安装 Alertmanager"
    
    local ingress_hosts=""
    local htpasswd=""
    local enable_rules=false
    
    # 解析参数
    log_debug "解析安装参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ingress)
                ingress_hosts="$2"
                log_debug "设置 ingress=${ingress_hosts}"
                shift 2
                ;;
            --htpasswd)
                htpasswd="$2"
                log_debug "设置 htpasswd=${htpasswd}"
                shift 2
                ;;
            --enable-rules)
                enable_rules=true
                log_debug "设置 enable-rules=true"
                shift
                ;;
            *)
                error_exit "未知选项: $1"
                ;;
        esac
    done
    
    # 显示配置信息
    log_info "Alertmanager 安装配置:"
    log_info "  命名空间: ${NAMESPACE}"
    [[ -n "${ingress_hosts}" ]] && log_info "  Ingress: ${ingress_hosts}"
    [[ -n "${htpasswd}" ]] && log_info "  认证: 已启用"
    [[ "${enable_rules}" == "true" ]] && log_info "  PrometheusRules: 已启用（8 个预定义规则）"
    
    # 构建 helm 命令
    log_info "构建 Helm 安装命令..."
    local helm_args=(
        "install" "alertmanager" "${CHARTS_DIR}/alertmanager"
        "-n" "${NAMESPACE}" "--create-namespace"
    )
    
    # 添加 ingress hosts
    if [[ -n "${ingress_hosts}" ]]; then
        log_debug "添加 Ingress 配置..."
        IFS=',' read -ra HOSTS <<< "${ingress_hosts}"
        for i in "${!HOSTS[@]}"; do
            log_debug "  ingress.hosts[$i]=${HOSTS[$i]}"
            helm_args+=("--set" "ingress.hosts[$i]=${HOSTS[$i]}")
        done
    fi
    
    # 添加 htpasswd 认证
    if [[ -n "${htpasswd}" ]]; then
        log_debug "添加 HTTP 基本认证配置..."
        helm_args+=("--set" "alertmanager.auth.enabled=true")
        helm_args+=("--set" "alertmanager.auth.htpasswd=${htpasswd}")
    fi
    
    # 启用 Prometheus Rules
    if [[ "${enable_rules}" == "true" ]]; then
        log_debug "启用 Prometheus Rules..."
        helm_args+=("--set" "prometheusRules.enabled=true")
    fi
    
    log_cmd "helm ${helm_args[*]}"
    log_info "开始执行 Helm 安装..."
    if helm "${helm_args[@]}"; then
        log_step "✓ Alertmanager 安装成功"
    else
        error_exit "Alertmanager 安装失败"
    fi
}

# 安装 Grafana
function cmd_grafana() {
    log_step "开始安装 Grafana"
    
    local storage_class="default-local-sc"
    local storage_size="50Gi"
    local ingress_hosts=""
    
    # 解析参数
    log_debug "解析安装参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --storage-class)
                storage_class="$2"
                log_debug "设置 storage-class=${storage_class}"
                shift 2
                ;;
            --storage-size)
                storage_size="$2"
                log_debug "设置 storage-size=${storage_size}"
                shift 2
                ;;
            --ingress)
                ingress_hosts="$2"
                log_debug "设置 ingress=${ingress_hosts}"
                shift 2
                ;;
            *)
                error_exit "未知选项: $1"
                ;;
        esac
    done
    
    # 显示配置信息
    log_info "Grafana 安装配置:"
    log_info "  命名空间: ${NAMESPACE}"
    log_info "  存储类: ${storage_class}"
    log_info "  存储大小: ${storage_size}"
    [[ -n "${ingress_hosts}" ]] && log_info "  Ingress: ${ingress_hosts}"
    
    # 构建 helm 命令
    log_info "构建 Helm 安装命令..."
    local helm_args=(
        "install" "grafana" "${CHARTS_DIR}/grafana"
        "-n" "${NAMESPACE}" "--create-namespace"
        "--set" "grafana.storage.storageClassName=${storage_class}"
        "--set" "grafana.storage.size=${storage_size}"
    )
    
    # 添加 ingress hosts
    if [[ -n "${ingress_hosts}" ]]; then
        log_debug "添加 Ingress 配置..."
        IFS=',' read -ra HOSTS <<< "${ingress_hosts}"
        for i in "${!HOSTS[@]}"; do
            log_debug "  ingress.hosts[$i]=${HOSTS[$i]}"
            helm_args+=("--set" "ingress.hosts[$i]=${HOSTS[$i]}")
        done
    fi
    
    log_cmd "helm ${helm_args[*]}"
    log_info "开始执行 Helm 安装..."
    if helm "${helm_args[@]}"; then
        log_step "✓ Grafana 安装成功"
    else
        error_exit "Grafana 安装失败"
    fi
}

# 安装 Loki
function cmd_loki() {
    log_step "开始安装 Loki"
    
    local retention="30d"
    local max_query_length="30d"
    local storage_class="default-local-sc"
    local storage_size="50Gi"
    
    # 解析参数
    log_debug "解析安装参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --retention)
                retention="$2"
                log_debug "设置 retention=${retention}"
                shift 2
                ;;
            --max-query-length)
                max_query_length="$2"
                log_debug "设置 max-query-length=${max_query_length}"
                shift 2
                ;;
            --storage-class)
                storage_class="$2"
                log_debug "设置 storage-class=${storage_class}"
                shift 2
                ;;
            --storage-size)
                storage_size="$2"
                log_debug "设置 storage-size=${storage_size}"
                shift 2
                ;;
            *)
                error_exit "未知选项: $1"
                ;;
        esac
    done
    
    # 显示配置信息
    log_info "Loki 安装配置:"
    log_info "  命名空间: ${NAMESPACE}"
    log_info "  数据保留期: ${retention}"
    log_info "  最大查询时长: ${max_query_length}"
    log_info "  存储类: ${storage_class}"
    log_info "  存储大小: ${storage_size}"
    
    log_cmd "helm install loki ${CHARTS_DIR}/loki -n ${NAMESPACE} --create-namespace --set ..."
    log_info "开始执行 Helm 安装..."
    if helm install loki ${CHARTS_DIR}/loki \
      -n ${NAMESPACE} --create-namespace \
      --set loki.retention=${retention} \
      --set loki.maxQueryLength=${max_query_length} \
      --set loki.storage.storageClassName=${storage_class} \
      --set loki.storage.size=${storage_size}; then
        log_step "✓ Loki 安装成功"
    else
        error_exit "Loki 安装失败"
    fi
}


# 安装 DCGM Exporter
function cmd_dcgm_exporter() {
    log_step "开始安装 DCGM Exporter"
    log_info "命名空间: ${NAMESPACE}"
    log_cmd "helm install dcgm-exporter ${CHARTS_DIR}/dcgm-exporter -n ${NAMESPACE}"
    log_info "开始执行 Helm 安装..."
    if helm install dcgm-exporter ${CHARTS_DIR}/dcgm-exporter \
      -n ${NAMESPACE} --create-namespace; then
        log_step "✓ DCGM Exporter 安装成功"
    else
        error_exit "DCGM Exporter 安装失败"
    fi
}

# 安装 Prometheus Adapter
function cmd_prometheus_adapter() {
    log_step "开始安装 Prometheus Adapter"
    log_info "命名空间: ${NAMESPACE}"
    log_cmd "helm install prometheus-adapter ${CHARTS_DIR}/prometheus-adapter -n ${NAMESPACE}"
    log_info "开始执行 Helm 安装..."
    if helm install prometheus-adapter ${CHARTS_DIR}/prometheus-adapter \
      -n ${NAMESPACE} --create-namespace; then
        log_step "✓ Prometheus Adapter 安装成功"
    else
        error_exit "Prometheus Adapter 安装失败"
    fi
}

# 安装 Alertmanager Webhook Adapter
function cmd_alertmanager_webhook_adapter() {
    log_step "开始安装 Alertmanager Webhook Adapter"
    log_info "命名空间: ${NAMESPACE}"
    log_cmd "helm install alertmanager-webhook-adapter ${CHARTS_DIR}/alertmanager-webhook-adapter -n ${NAMESPACE}"
    log_info "开始执行 Helm 安装..."
    if helm install alertmanager-webhook-adapter ${CHARTS_DIR}/alertmanager-webhook-adapter \
      -n ${NAMESPACE} --create-namespace; then
        log_step "✓ Alertmanager Webhook Adapter 安装成功"
    else
        error_exit "Alertmanager Webhook Adapter 安装失败"
    fi
}

# 安装 CronHPA Controller
function cmd_cronhpa_controller() {
    log_step "开始安装 CronHPA Controller"
    log_info "命名空间: kube-system"
    log_cmd "helm install cronhpa-controller ${CHARTS_DIR}/cronhpa-controller -n kube-system"
    log_info "开始执行 Helm 安装..."
    if helm install cronhpa-controller ${CHARTS_DIR}/cronhpa-controller \
      -n kube-system --create-namespace; then
        log_step "✓ CronHPA Controller 安装成功"
    else
        error_exit "CronHPA Controller 安装失败"
    fi
}

# 安装 VPC CNI
function cmd_vpc_cni() {
    log_step "开始安装 VPC CNI"
    log_info "命名空间: kube-system"
    log_cmd "helm install vpc-cni ${CHARTS_DIR}/vpc-cni -n kube-system --create-namespace"
    log_info "开始执行 Helm 安装..."
    if helm install vpc-cni ${CHARTS_DIR}/vpc-cni \
      -n kube-system --create-namespace; then
        log_step "✓ VPC CNI 安装成功"
    else
        error_exit "VPC CNI 安装失败"
    fi
}

# 安装 P2P Accelerator
function cmd_p2p_accelerator() {
    log_step "开始安装 P2P Accelerator"
    log_info "命名空间: kube-system"
    log_cmd "helm install p2p-accelerator ${CHARTS_DIR}/p2p-accelerator -n kube-system --create-namespace"
    log_info "开始执行 Helm 安装..."
    if helm install p2p-accelerator ${CHARTS_DIR}/p2p-accelerator \
      -n kube-system --create-namespace; then
        log_step "✓ P2P Accelerator 安装成功"
        echo ""
        log_info "验证安装："
        log_info "  kubectl -n kube-system get pods -l app.kubernetes.io/app-component=p2p-accelerator"
        log_info "  kubectl -n kube-system get svc | grep p2p-accelerator"
        log_info ""
        log_info "健康检查："
        log_info "  curl http://localhost:30020/healthz"
        log_info ""
        log_info "查看 Metrics："
        log_info "  curl http://localhost:30020/metrics"
    else
        error_exit "P2P Accelerator 安装失败"
    fi
}

# 安装所有组件
function cmd_all() {
    log_info "安装所有组件（使用默认参数）..."
    
    cmd_prometheus \
      --retention 1d \
      --storage-size 10Gi \
      --ingress prometheus.example.com,prometheus-internal.example.com
    
    cmd_alertmanager \
      --ingress alertmanager.example.com,alertmanager-internal.example.com
    
    cmd_grafana \
      --storage-size 50Gi \
      --ingress grafana.example.com,grafana-internal.example.com
    
    cmd_loki --storage-size 50Gi
    cmd_dcgm_exporter
    cmd_prometheus_adapter
    cmd_alertmanager_webhook_adapter
    cmd_cronhpa_controller
    
    log_info "所有组件安装完成"
    log_info "注意: Node Exporter、Kube State Metrics 和 Blackbox Exporter 已随 Prometheus 自动安装"
}

# 主函数
function main() {
    # 如果没有参数，显示帮助
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi
    
    # 解析全局选项
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
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
            -h|--help)
                print_help
                exit 0
                ;;
            prometheus|alertmanager|grafana|loki|dcgm-exporter|prometheus-adapter|alertmanager-webhook-adapter|cronhpa-controller|vpc-cni|p2p-accelerator|all)
                local cmd="$1"
                shift
                
                # 保存用户输入的所有参数（在 shift 之前）
                local user_args="$*"
                
                # 初始化日志文件
                init_log_file "${cmd}"
                
                log_info "=========================================="
                log_info "Kubernetes 组件安装脚本"
                log_info "命令: ${cmd}"
                log_info "命名空间: ${NAMESPACE}"
                [[ "${VERBOSE}" == "true" ]] && log_info "详细模式: 已启用"
                [[ "${DEBUG}" == "true" ]] && log_info "调试模式: 已启用"
                log_info "=========================================="
                
                # 打印用户输入的所有参数
                if [[ -n "${user_args}" ]]; then
                    log_info "用户输入参数: ${user_args}"
                else
                    log_info "用户输入参数: (无)"
                fi
                
                log_info "Charts 目录: ${CHARTS_DIR}"
                
                # 验证 charts 目录是否存在
                if [[ ! -d "${CHARTS_DIR}" ]]; then
                    error_exit "Charts 目录不存在: ${CHARTS_DIR}，请确保已通过入口脚本 install.sh 执行代码同步"
                fi
                
                # 执行对应的命令
                case ${cmd} in
                    prometheus)
                        cmd_prometheus "$@"
                        ;;
                    alertmanager)
                        cmd_alertmanager "$@"
                        ;;
                    grafana)
                        cmd_grafana "$@"
                        ;;
                    loki)
                        cmd_loki "$@"
                        ;;
                    dcgm-exporter)
                        cmd_dcgm_exporter "$@"
                        ;;
                    prometheus-adapter)
                        cmd_prometheus_adapter "$@"
                        ;;
                    alertmanager-webhook-adapter)
                        cmd_alertmanager_webhook_adapter "$@"
                        ;;
                    cronhpa-controller)
                        cmd_cronhpa_controller "$@"
                        ;;
                    vpc-cni)
                        cmd_vpc_cni "$@"
                        ;;
                    p2p-accelerator)
                        cmd_p2p_accelerator "$@"
                        ;;
                    all)
                        cmd_all "$@"
                        ;;
                esac
                
                echo ""
                log_info "=========================================="
                log_info "安装完成！"
                log_info "=========================================="
                
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

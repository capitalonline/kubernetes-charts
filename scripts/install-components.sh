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
            LOG_FILE="/tmp/k8s-install-${component}-$(date +%Y%m%d-%H%M%S).log"
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
  loki-add-ingress [选项]             为已安装的 Loki 补充安装 Ingress
  loki-update-promtail-config [选项]  更新 Loki 的 promtail-config 配置并滚动重启 DaemonSet
  dcgm-exporter                       安装 DCGM Exporter
  prometheus-adapter                  安装 Prometheus Adapter
  alertmanager-webhook-adapter        安装 Alertmanager Webhook Adapter
  cronhpa-controller                  安装 CronHPA Controller
  vpc-cni [选项]                      安装 VPC CNI 网络插件
  p2p-accelerator [选项]              安装 P2P Accelerator
  csi-nfs                      安装 CSI NFS 驱动
  csi-disk [选项]                     安装 CSI Disk 存储插件
  csi-oss                             安装 CSI OSS 对象存储插件
  kubeprober                          安装 KubeProber 集群诊断工具
  node-agent  [选项]                   安装 Node Agent 绑核组件
  ingress-nginx                       安装 ingress-nginx 插件
  velero [选项]                        安装 Velero 备份与恢复组件
  all                                 安装所有组件（使用默认参数）

全局选项:
  -n, --namespace NAME                命名空间 (默认: monitoring)
  -v, --verbose                       显示详细信息（包括执行的命令）
  -d, --debug                         调试模式（显示更详细的调试信息）
  -l, --log                           保存日志到 /tmp 目录（自动生成文件名）
  --log-file FILE                     保存日志到指定文件
  --components COMP1,COMP2,...        批量安装指定组件（逗号分隔）
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

  # 安装 P2P Accelerator（自定义镜像仓库）
  $0 p2p-accelerator --mirrored-registries https://registry1.com,https://registry2.com

  # 安装 CSI NFS 驱动
  $0 csi-nfs

  # 安装 CSI Disk 存储插件（使用默认参数）
  $0 csi-disk

  # 安装 CSI Disk 存储插件（自定义网关配置）
  $0 csi-disk --gateway-host gateway.gic.test --gateway-ip 192.168.0.100

  # 安装 CSI OSS 对象存储插件
  $0 csi-oss

  # 安装 Cloud Controller Manager (云控制器组件)
  $0 cloud-controller-manager

  # 安装 Node Agent (绑核组件)
  $0 node-agent

  # 批量安装多个组件
  $0 --components csi-oss,csi-nfs,csi-disk,node-agent

  # 批量安装多个组件（带调试日志）
  $0 -d -l --components csi-oss,csi-nfs,csi-disk

组件特定选项:

  prometheus:
    --retention TIME              数据保留时间 (默认: 1d)
    --storage-class CLASS         存储类 (默认: default-local-sc)
    --storage-size SIZE           存储大小 (默认: 10Gi)
    --ingress HOST1,HOST2         Ingress 主机名
    --ingress-flow HOSTNAME       统一监控流量Ingress主机名（可选）
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
    --ingress HOST                [可选] Ingress 主机名（HTTP，不含 TLS），为空则不创建 Ingress

  loki-add-ingress:
    --ingress HOST                [必传] Ingress 主机名，为已安装的 Loki 补充创建 Ingress

  loki-update-promtail-config:
    （无参数）重新 apply promtail-config ConfigMap 并滚动重启 promtail-daemonset

  p2p-accelerator:
    --mirrored-registries URL1,URL2  [必传] 镜像仓库地址列表 (逗号分隔，例如: https://registry1.com,https://registry2.com)

  csi-disk:
    --gateway-host HOSTNAME       [可选] 网关主机名 (默认: gateway.gic.test)
    --gateway-ip IP               [可选] 网关 IP 地址 (默认: 192.168.0.100)

  velero:
    --s3-url URL                  [可选] S3/MinIO 服务地址（不传则部署无存储配置的 Velero）
    --bucket NAME                 [可选] 备份存储桶名称 (默认: velero)
    --access-key KEY              [可选] S3 Access Key（与 --s3-url 同时提供）
    --secret-key KEY              [可选] S3 Secret Key（与 --s3-url 同时提供）
    --region NAME                 [可选] S3 区域名称 (默认: minio)
    --enable-node-agent           [可选] 启用 node-agent DaemonSet（用于 PVC 文件系统备份）

    注意: --s3-url、--access-key、--secret-key 需同时提供或全部不提供

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
    local ingress_flow=""
    
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
              --ingress-flow)
                ingress_flow="$2"
                log_debug "设置 ingress-flow=${ingress_flow}"
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
    while IFS=$'\t' read -r pod_name pod_ip node_name; do
        if [[ -z "${pod_name}" ]]; then
            continue
        fi
        if [[ -n "${pod_ip}" ]] && [[ -n "${node_name}" ]] && [[ "${pod_ip}" != "<none>" ]]; then
            etcd_list+=("${pod_ip}:${node_name}")
            log_debug "检测到 ETCD Pod: ${pod_name} -> ${pod_ip}:${node_name}"
        fi
    done < <(kubectl get pod -n kube-system -l component=etcd \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\t"}{.spec.nodeName}{"\n"}{end}' 2>/dev/null)
    
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

    # 添加 ingress flow（新增部分）
    if [[ -n "${ingress_flow}" ]]; then
        log_debug "添加 Flow Ingress 配置..."
        helm_args+=("--set" "flowIngress.enabled=true")
        helm_args+=("--set" "flowIngress.host=${ingress_flow}")
    else
        helm_args+=("--set" "flowIngress.enabled=false")
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
    local ingress_host=""
    
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
            --ingress)
                ingress_host="$2"
                log_debug "设置 ingress-host=${ingress_host}"
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
    [[ -n "${ingress_host}" ]] && log_info "  Ingress Host: ${ingress_host}"
    
    # 构建 helm 命令
    log_info "构建 Helm 安装命令..."
    local helm_args=(
        "install" "loki" "${CHARTS_DIR}/loki"
        "-n" "${NAMESPACE}" "--create-namespace"
        "--set" "loki.retention=${retention}"
        "--set" "loki.maxQueryLength=${max_query_length}"
        "--set" "loki.storage.storageClassName=${storage_class}"
        "--set" "loki.storage.size=${storage_size}"
    )
    
    # 添加 ingress 配置
    if [[ -n "${ingress_host}" ]]; then
        log_debug "添加 Ingress 配置..."
        helm_args+=("--set" "ingress.enabled=true")
        helm_args+=("--set" "ingress.host=${ingress_host}")
    fi
    
    log_cmd "helm ${helm_args[*]}"
    log_info "开始执行 Helm 安装..."
    if helm "${helm_args[@]}"; then
        log_step "✓ Loki 安装成功"
    else
        error_exit "Loki 安装失败"
    fi
}

# 为已安装的 Loki 补充安装 Ingress
function cmd_loki_add_ingress() {
    log_step "开始为 Loki 补充安装 Ingress"
    
    local ingress_host=""
    
    # 解析参数
    log_debug "解析参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ingress)
                ingress_host="$2"
                log_debug "设置 ingress-host=${ingress_host}"
                shift 2
                ;;
            *)
                error_exit "未知选项: $1"
                ;;
        esac
    done
    
    if [[ -z "${ingress_host}" ]]; then
        error_exit "必须通过 --ingress 指定 Ingress Host 主机名"
    fi
    
    # 检查 Loki 是否已安装
    log_info "检查 Loki 是否已安装..."
    if ! helm status loki -n ${NAMESPACE} &> /dev/null; then
        error_exit "Loki 未安装，请先安装 Loki（./install.sh loki）"
    fi
    
    log_info "Loki Ingress 配置:"
    log_info "  命名空间: ${NAMESPACE}"
    log_info "  Ingress Host: ${ingress_host}"
    
    log_cmd "helm upgrade loki ${CHARTS_DIR}/loki -n ${NAMESPACE} --reuse-values --set ingress.enabled=true --set ingress.host=${ingress_host}"
    log_info "开始执行 Helm Upgrade..."
    if helm upgrade loki ${CHARTS_DIR}/loki \
      -n ${NAMESPACE} \
      --reuse-values \
      --set ingress.enabled=true \
      --set "ingress.host=${ingress_host}"; then
        log_step "✓ Loki Ingress 安装成功"
        log_info "Ingress Host: ${ingress_host}"
    else
        error_exit "Loki Ingress 安装失败"
    fi
}

# 更新 Loki promtail-config 配置并滚动重启 DaemonSet
function cmd_loki_update_promtail_config() {
    log_step "开始更新 Loki promtail-config 配置"

    # 检查 promtail-daemonset 是否存在
    log_info "检查 promtail-daemonset 是否存在..."
    if ! kubectl -n ${NAMESPACE} get daemonset promtail-daemonset &> /dev/null; then
        error_exit "promtail-daemonset 不存在，请确认 Loki 已正常部署"
    fi

    # apply promtail-config ConfigMap
    local config_file="${CHARTS_DIR}/loki/templates/promtail/promtail-config.yaml"
    log_cmd "kubectl apply -f ${config_file}"
    log_info "开始 apply promtail-config ConfigMap..."
    if kubectl apply -f "${config_file}"; then
        log_info "✓ promtail-config ConfigMap apply 成功"
    else
        error_exit "promtail-config ConfigMap apply 失败"
    fi

    # 滚动重启 DaemonSet
    log_cmd "kubectl -n ${NAMESPACE} rollout restart daemonset promtail-daemonset"
    log_info "开始滚动重启 promtail-daemonset..."
    if kubectl -n ${NAMESPACE} rollout restart daemonset promtail-daemonset; then
        log_step "✓ promtail-config 更新并重启完成"
    else
        error_exit "promtail-daemonset 滚动重启失败"
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
    
    local mirrored_registries=""
    
    # 解析参数
    log_debug "解析安装参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mirrored-registries)
                mirrored_registries="$2"
                log_debug "参数: mirrored-registries = ${mirrored_registries}"
                shift 2
                ;;
            *)
                log_warn "未知参数: $1"
                shift
                ;;
        esac
    done
    
    # 校验必传参数
    if [[ -z "${mirrored_registries}" ]]; then
        log_error "缺少必传参数: --mirrored-registries"
        log_error ""
        log_error "使用方法："
        log_error "  $0 p2p-accelerator --mirrored-registries URL1,URL2"
        log_error ""
        log_error "示例："
        log_error "  $0 p2p-accelerator --mirrored-registries https://aj941n.yun-paas.com"
        log_error "  $0 p2p-accelerator --mirrored-registries https://registry1.com,https://registry2.com"
        error_exit "参数校验失败"
    fi
    
    # 显示配置信息
    log_info "P2P Accelerator 安装配置:"
    log_info "  命名空间: kube-system"
    log_info "  镜像仓库: ${mirrored_registries}"
    
    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/p2p-accelerator"
    if [[ ! -d "${CHARTS_DIR}/p2p-accelerator" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/p2p-accelerator"
    fi
    
    # 构建 helm 命令
    log_info "构建 Helm 安装命令..."
    local helm_args=(
        "install" "p2p-accelerator" "${CHARTS_DIR}/p2p-accelerator"
        "-n" "kube-system" "--create-namespace"
    )
    
    # 添加 mirrored registries
    log_debug "添加镜像仓库配置..."
    IFS=',' read -ra REGISTRIES <<< "${mirrored_registries}"
    for i in "${!REGISTRIES[@]}"; do
        log_debug "  mirroredRegistries[$i]=${REGISTRIES[$i]}"
        helm_args+=("--set" "mirroredRegistries[$i]=${REGISTRIES[$i]}")
    done
    
    # 显示完整的 helm 命令
    log_cmd "helm ${helm_args[*]}"
    
    # 执行安装
    log_info "开始执行 Helm 安装..."
    if helm "${helm_args[@]}"; then
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
        error_exit "P2P Accelerator 安装失败，请检查 Helm 输出"
    fi
}

# 安装 CSI NFS 驱动
function cmd_csi_nfs() {
    log_step "开始安装 CSI NFS 驱动"
    log_info "  命名空间: kube-system"

    log_cmd "helm install csi-nfs ${CHARTS_DIR}/csi-nfs -n kube-system --create-namespace"
    log_info "开始执行 Helm 安装..."
    if helm install csi-nfs ${CHARTS_DIR}/csi-nfs \
      -n kube-system --create-namespace; then
        log_step "✓ CSI NFS 驱动安装成功"
    else
        error_exit "CSI NFS 驱动安装失败，请检查 Helm 输出"
    fi
}

# 安装 CSI Disk
function cmd_csi_disk() {
    log_step "开始安装 CSI Disk"
    
    local gateway_host=""
    local gateway_ip=""
    local has_gateway_config=false
    
    # 解析参数
    log_debug "解析安装参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --gateway-host)
                gateway_host="$2"
                has_gateway_config=true
                log_debug "参数: gateway-host = ${gateway_host}"
                shift 2
                ;;
            --gateway-ip)
                gateway_ip="$2"
                has_gateway_config=true
                log_debug "参数: gateway-ip = ${gateway_ip}"
                shift 2
                ;;
            *)
                log_warn "未知参数: $1"
                shift
                ;;
        esac
    done
    
    # 显示配置信息
    log_info "CSI Disk 安装配置:"
    log_info "  命名空间: kube-system"
    if [[ "${has_gateway_config}" == true ]]; then
        log_info "  网关主机名: ${gateway_host}"
        log_info "  网关 IP: ${gateway_ip}"
    else
        log_info "  网关配置: 未配置 (使用 values.yaml 默认值)"
    fi
    log_info "  CSI Disk 是云盘存储的 CSI 驱动"

    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/csi-disk"
    if [[ ! -d "${CHARTS_DIR}/csi-disk" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/csi-disk"
    fi

    # 构建 helm 命令
    log_info "构建 Helm 安装命令..."
    local helm_args=(
        "install" "csi-disk" "${CHARTS_DIR}/csi-disk"
        "-n" "kube-system" "--create-namespace"
    )
    
    # 如果用户配置了网关参数，则添加到 helm 命令中
    if [[ "${has_gateway_config}" == true ]]; then
        if [[ -n "${gateway_host}" ]]; then
            helm_args+=("--set" "hostAliases[0].hostnames[0]=${gateway_host}")
        fi
        if [[ -n "${gateway_ip}" ]]; then
            helm_args+=("--set" "hostAliases[0].ip=${gateway_ip}")
        fi
    else
        # 如果没有配置，则清空 hostAliases（不使用 values.yaml 的默认值）
        helm_args+=("--set" "hostAliases=null")
    fi
    
    # 显示完整的 helm 命令
    log_cmd "helm ${helm_args[*]}"

    # 执行安装
    log_info "开始执行 Helm 安装..."
    if helm "${helm_args[@]}"; then
        log_step "✓ CSI Disk 安装成功"
        echo ""
        log_info "验证安装："
        log_info "  kubectl -n kube-system get pods -l app.kubernetes.io/app-component=csi-disk"
        log_info "  kubectl -n kube-system get csidriver eks-disk.csi.cds.net"
        log_info ""
        log_info "Controller 组件："
        log_info "  kubectl -n kube-system get deployment eks-disk-csi-cds-controller"
        log_info ""
        log_info "Node 组件（DaemonSet）："
        log_info "  kubectl -n kube-system get daemonset eks-disk-csi-cds-node"
    else
        error_exit "CSI Disk 安装失败，请检查 Helm 输出"
    fi
}

# 安装 CSI OSS
function cmd_csi_oss() {
    log_step "开始安装 CSI OSS"
    log_info "命名空间: kube-system"
    log_info "CSI OSS 是对象存储的 CSI 驱动"

    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/csi-oss"
    if [[ ! -d "${CHARTS_DIR}/csi-oss" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/csi-oss"
    fi

    # 执行安装
    log_cmd "helm install csi-oss ${CHARTS_DIR}/csi-oss -n kube-system --create-namespace"
    log_info "开始执行 Helm 安装..."

    if helm install csi-oss ${CHARTS_DIR}/csi-oss \
      -n kube-system --create-namespace; then
        log_step "✓ CSI OSS 安装成功"
        echo ""
        log_info "验证安装："
        log_info "  kubectl -n kube-system get pods -l app.kubernetes.io/app-component=csi-oss"
        log_info "  kubectl -n kube-system get csidriver oss.csi.cds.net"
        log_info ""
        log_info "Node 组件（DaemonSet）："
        log_info "  kubectl -n kube-system get daemonset oss-csi-cds-node"
        log_info ""
        log_info "注意："
        log_info "  CSI OSS 只在 node.kubernetes.io/host-type=ecs 或 bms 的节点运行"
    else
        error_exit "CSI OSS 安装失败，请检查 Helm 输出"
    fi
}

# 安装 KubeProber
function cmd_kubeprober() {
    log_step "开始安装 KubeProber"
    log_info "命名空间: kubeprober"
    log_info "KubeProber 是 Kubernetes 集群诊断工具"

    local alert_token=""
    local env=""
    local customer_id=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --alert_token)
                alert_token="$2"; shift 2;;
            --env)
                env="$2"; shift 2;;
            --customer_id)
                customer_id="$2"; shift 2;;
            *)
                shift;;
        esac
    done

    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/kubeprober"
    if [[ ! -d "${CHARTS_DIR}/kubeprober" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/kubeprober"
    fi

    # 先安装 CRDs
    log_info "安装 KubeProber CRDs..."
    log_cmd "kubectl apply -f ${CHARTS_DIR}/kubeprober/crds/"
    if kubectl apply -f "${CHARTS_DIR}/kubeprober/crds/"; then
        log_info "✓ CRDs 安装成功"
    else
        log_warn "CRDs 安装失败或已存在，继续安装..."
    fi

    # 执行安装
    local helm_cmd="helm install kubeprober ${CHARTS_DIR}/kubeprober \
        -n kubeprober --create-namespace \
        --set alertToken=\"${alert_token}\" \
        --set env=\"${env}\" \
        --set customerId=\"${customer_id}\""

    log_cmd "${helm_cmd}"
    log_info "执行 Helm 命令: ${helm_cmd}"
    log_info "开始执行 Helm 安装..."

    if eval "${helm_cmd}"; then
        log_step "✓ KubeProber 安装成功"
        echo ""
        log_info "验证安装："
        log_info "  kubectl -n kube-system get pods -l app.kubernetes.io/name=kubeprober"
        log_info "  kubectl -n kube-system get svc probeagent"
        log_info ""
        log_info "组件说明："
        log_info "  - probe-agent: 探测代理（Deployment）"
        log_info "  - nsenter: 主机诊断工具（DaemonSet）"
        log_info ""
        log_info "访问探测状态 API："
        log_info "  kubectl -n kube-system port-forward svc/probeagent 8082:8082"
        log_info "  curl http://localhost:8082"
        log_info ""
        log_info "查看 Metrics："
        log_info "  kubectl -n kube-system port-forward svc/probeagent 8000:8000"
        log_info "  curl http://localhost:8000/metrics"
    else
        error_exit "KubeProber 安装失败，请检查 Helm 输出"
    fi
}

# 安装 Cloud Controller Manager
function cmd_cloud_controller_manager() {
    log_step "开始安装 Cloud Controller Manager"
    log_info "命名空间: kube-system"
    log_info "Cloud Controller Manager 用于与云提供商集成"

    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/cloud-controller-manager"
    if [[ ! -d "${CHARTS_DIR}/cloud-controller-manager" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/cloud-controller-manager"
    fi

    # 执行安装
    log_cmd "helm install cloud-controller-manager ${CHARTS_DIR}/cloud-controller-manager -n kube-system --create-namespace"
    log_info "开始执行 Helm 安装..."

    if helm install cloud-controller-manager ${CHARTS_DIR}/cloud-controller-manager \
      -n kube-system --create-namespace; then
        log_step "✓ Cloud Controller Manager 安装成功"
        echo ""
        log_info "验证安装："
        log_info "  kubectl -n kube-system get pods -l app.kubernetes.io/app-component=cloud-controller-manager"
        log_info "  kubectl -n kube-system get deployment eks-cloud-controller-manager"
        log_info ""
        log_info "注意："
        log_info "  需要提前配置必要的 Secret 和 ConfigMap (eks-secrets, cds-properties)"
    else
        error_exit "Cloud Controller Manager 安装失败，请检查 Helm 输出"
    fi
}

function cmd_node_agent() {
    log_step "开始安装 Node Agent (绑核组件)"
    log_info "命名空间: kube-system"
    log_info "Node Agent 是用于 CPU 绑定和 kubelet 配置的节点代理组件"

    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/node-agent"
    if [[ ! -d "${CHARTS_DIR}/node-agent" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/node-agent"
    fi

    # 执行安装
    log_cmd "helm install node-agent ${CHARTS_DIR}/node-agent -n kube-system --create-namespace"
    log_info "开始执行 Helm 安装..."

    if helm install node-agent ${CHARTS_DIR}/node-agent \
      -n kube-system --create-namespace; then
        log_step "✓ Node Agent 安装成功"
        echo ""
        log_info "验证安装："
        log_info "  kubectl -n kube-system get pods -l app=node-agent"
        log_info "  kubectl -n kube-system get daemonset node-agent"
        log_info ""
        log_info "注意："
        log_info "  Node Agent 以 DaemonSet 形式运行在所有工作节点上"
        log_info "  用于监听节点 Annotation 并自动配置 CPU 管理策略"
    else
        error_exit "Node Agent 安装失败，请检查 Helm 输出"
    fi
}

function cmd_velero() {
    log_step "开始安装 Velero"

    local namespace="velero"
    local s3_url=""
    local bucket="velero"
    local access_key=""
    local secret_key=""
    local region="minio"
    local enable_node_agent=false

    # 解析参数
    log_debug "解析安装参数..."
    while [[ $# -gt 0 ]]; do
        case $1 in
            --s3-url)
                s3_url="$2"
                log_debug "参数: s3-url = ${s3_url}"
                shift 2
                ;;
            --bucket)
                bucket="$2"
                log_debug "参数: bucket = ${bucket}"
                shift 2
                ;;
            --access-key)
                access_key="$2"
                log_debug "参数: access-key = ${access_key}"
                shift 2
                ;;
            --secret-key)
                secret_key="$2"
                log_debug "参数: secret-key = ***"
                shift 2
                ;;
            --region)
                region="$2"
                log_debug "参数: region = ${region}"
                shift 2
                ;;
            --enable-node-agent)
                enable_node_agent=true
                log_debug "参数: enable-node-agent = true"
                shift
                ;;
            *)
                log_warn "未知参数: $1"
                shift
                ;;
        esac
    done

    # 判断是否配置了存储（三个参数需同时提供）
    local has_storage=false
    if [[ -n "${s3_url}" ]] && [[ -n "${access_key}" ]] && [[ -n "${secret_key}" ]]; then
        has_storage=true
    elif [[ -n "${s3_url}" ]] || [[ -n "${access_key}" ]] || [[ -n "${secret_key}" ]]; then
        error_exit "--s3-url、--access-key、--secret-key 三个参数需同时提供，或全部不提供（不配置存储）"
    fi

    # 显示配置信息
    log_info "Velero 安装配置:"
    log_info "  命名空间: ${namespace}"
    if [[ "${has_storage}" == "true" ]]; then
        log_info "  S3 地址: ${s3_url}"
        log_info "  存储桶: ${bucket}"
        log_info "  S3 区域: ${region}"
    else
        log_info "  存储配置: 未配置（后续可在集群中手动创建 BackupStorageLocation）"
    fi
    log_info "  Node Agent: ${enable_node_agent}"

    # 检查 chart 是否存在
    log_debug "检查 chart 目录: ${CHARTS_DIR}/velero"
    if [[ ! -d "${CHARTS_DIR}/velero" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/velero"
    fi

    # 独立 apply CRD（Helm 3 的 crds/ 目录只在首次 install 时安装，upgrade 时不更新）
    log_info "应用 Velero CRDs..."
    if [[ -f "${CHARTS_DIR}/velero/crds/velero-crds.yaml" ]]; then
        log_cmd "kubectl apply -f ${CHARTS_DIR}/velero/crds/velero-crds.yaml"
        if kubectl apply -f "${CHARTS_DIR}/velero/crds/velero-crds.yaml" --server-side --force-conflicts; then
            log_info "✓ Velero CRDs 应用成功"
        else
            log_warn "CRDs 应用失败，尝试使用常规方式..."
            if kubectl apply -f "${CHARTS_DIR}/velero/crds/velero-crds.yaml"; then
                log_info "✓ Velero CRDs 应用成功（常规方式）"
            else
                error_exit "Velero CRDs 应用失败"
            fi
        fi
    else
        error_exit "CRD 文件不存在: ${CHARTS_DIR}/velero/crds/velero-crds.yaml"
    fi

    # 构建 helm 命令
    log_info "构建 Helm 安装命令..."
    local helm_args=(
        "upgrade" "--install" "velero" "${CHARTS_DIR}/velero"
        "-n" "${namespace}" "--create-namespace"
        "--skip-crds"
    )

    if [[ "${has_storage}" == "true" ]]; then
        # 写入临时凭据配置文件（避免 --set 处理多行字符串的问题）
        local tmp_values
        tmp_values=$(mktemp /tmp/velero-values-XXXXXX.yaml)
        cat > "${tmp_values}" << HEREDOC
credentials:
  useSecret: true
  secretContents:
    cloud: |
      [default]
      aws_access_key_id = ${access_key}
      aws_secret_access_key = ${secret_key}
HEREDOC
        log_debug "临时凭据文件: ${tmp_values}"

        helm_args+=(
            "-f" "${tmp_values}"
            "--set" "backupStorageLocation.enabled=true"
            "--set" "backupStorageLocation.config.s3Url=${s3_url}"
            "--set" "backupStorageLocation.bucket=${bucket}"
            "--set" "backupStorageLocation.config.region=${region}"
            "--set" "volumeSnapshotLocation.enabled=true"
        )
    fi

    if [[ "${enable_node_agent}" == "true" ]]; then
        helm_args+=("--set" "nodeAgent.enabled=true")
    fi

    log_cmd "helm ${helm_args[*]}"

    # 执行安装
    log_info "开始执行 Helm 安装..."
    if helm "${helm_args[@]}"; then
        [[ "${has_storage}" == "true" ]] && rm -f "${tmp_values}"
        log_step "✓ Velero 安装成功"
        echo ""
        log_info "验证安装："
        log_info "  kubectl -n ${namespace} get pods"
        if [[ "${has_storage}" == "true" ]]; then
            log_info "  kubectl -n ${namespace} get backupstoragelocation"
            log_info ""
            log_info "查看备份存储位置连接状态："
            log_info "  kubectl -n ${namespace} get bsl"
            log_info ""
            log_info "创建一次性备份示例："
            log_info "  velero backup create my-backup --include-namespaces default -n ${namespace}"
        else
            log_info ""
            log_warn "存储未配置，备份功能暂不可用"
            log_info "后续配置存储请手动创建 BackupStorageLocation："
            log_info "  kubectl apply -f <your-bsl.yaml> -n ${namespace}"
        fi
        log_info ""
        if [[ "${enable_node_agent}" == "true" ]]; then
            log_info "Node Agent（文件系统备份）已启用："
            log_info "  kubectl -n ${namespace} get daemonset node-agent"
        fi
    else
        [[ "${has_storage}" == "true" ]] && rm -f "${tmp_values}"
        error_exit "Velero 安装失败，请检查 Helm 输出"
    fi
}

function cmd_ingress_nginx() {
    log_step "开始安装 ingress-nginx"

    local release_name="ingress-nginx"
    local namespace="ingress-nginx"
    local service_type="NodePort"
    local external_traffic_policy="Cluster"
    local replicas=1

    local algorithm=""
    local slb_id=""
    local eip=""
    local vip=""
    local protocol=""
    local types=""
    local spec=""
    local network=""
    local node_pool_id=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
            case $1 in
                --service-type)
                    service_type="$2"; shift 2;;
                --external_traffic_policy)
                    external_traffic_policy="$2"; shift 2;;
                --algorithm)
                    algorithm="$2"; shift 2;;
                --slb-id)
                    slb_id="$2"; shift 2;;
                --eip)
                    eip="$2"; shift 2;;
                --vip)
                    vip="$2"; shift 2;;
                --protocol)
                    protocol="$2"; shift 2;;
                --types)
                    types="$2"; shift 2;;
                --spec)
                    spec="$2"; shift 2;;
                --network)
                    network="$2"; shift 2;;
                --node_pool_id)
                    node_pool_id="$2"; shift 2;;
                --replicas)
                    replicas="$2"; shift 2;;
                *)
                    shift;;
            esac
        done

    log_info "命名空间: ${namespace}"
    log_info "Service 类型: ${service_type}"
    log_info "externalTrafficPolicy: ${external_traffic_policy}"
    log_info "Ingress 控制器用于集群流量入口"

    # 检查 chart
    log_debug "检查 chart 目录: ${CHARTS_DIR}/ingress-nginx"
    if [[ ! -d "${CHARTS_DIR}/ingress-nginx" ]]; then
        error_exit "Chart 目录不存在: ${CHARTS_DIR}/ingress-nginx"
    fi

    if [[ "${service_type}" == "NodePort" ]]; then
        external_traffic_policy="Cluster"
        log_info "NodePort 模式强制 externalTrafficPolicy=Cluster"
    fi

    if [[ ${replicas} -gt 3 ]]; then
        replicas=3
        log_info "ingress-nginx 副本数不能超过 3 个 (当前请求: ${replicas}), 设置replicas=3"
    fi

    if [[ "${service_type}" == "LoadBalancer" ]]; then
            if [[ -z "${slb_id}" ]]; then
                error_exit "LoadBalancer 模式必须提供 --slb-id"
            fi
    fi

    # 打印命令
    local helm_cmd="helm install ingress-nginx ${CHARTS_DIR}/ingress-nginx \
          -n ingress-nginx \
          --create-namespace \
          --set controller.service.type=${service_type} \
          --set controller.replicaCount=${replicas} \
          --set controller.service.externalTrafficPolicy=${external_traffic_policy}"

    if [[ -n "${node_pool_id}" ]]; then
        helm_cmd+=" \
          --set controller.nodeSelector.\"node\.kubernetes\.io/node-pool-id\"=\"${node_pool_id}\""
        log_info "设置节点池 ID: ${node_pool_id}"
    fi

    if [[ "${service_type}" == "LoadBalancer" ]]; then
        if [[ -z "${slb_id}" ]]; then
            error_exit "LoadBalancer 模式必须提供 --slb-id"
        fi
        helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-select-slb-id\"=\"${slb_id}\""

        [[ -n "${protocol}" ]] && helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-load-balancer-protocol\"=\"${protocol}\""

        [[ -n "${types}" ]] && helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-load-balancer-types\"=\"${types}\""

        [[ -n "${spec}" ]] && helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-load-balancer-specification\"=\"${spec}\""

        [[ -n "${network}" ]] && helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-load-balancer-network\"=\"${network}\""

        [[ -n "${algorithm}" ]] && helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-load-balancer-algorithm\"=\"${algorithm}\""

        [[ -n "${eip}" ]] && helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-select-slb-eip-addr\"=\"${eip}\""

        [[ -n "${vip}" ]] && helm_cmd+=" \
          --set-string controller.service.annotations.\"service\.beta\.kubernetes\.io/cds-select-slb-vip-addr\"=\"${vip}\""

    fi
    log_cmd "${helm_cmd}"

    log_info "开始执行 Helm 安装..."

    if eval "${helm_cmd}"; then

            log_step "✓ ingress-nginx 安装成功"
            echo ""

            log_info "验证安装："
            log_info "  kubectl -n ingress-nginx get pods"
            log_info "  kubectl -n ingress-nginx get svc"
            log_info ""
            log_info "查看 Service："
            log_info "  kubectl -n ingress-nginx get svc ingress-nginx-controller"
            log_info ""

            if [[ "${service_type}" == "LoadBalancer" ]]; then
                log_info "等待云负载均衡分配外网 IP..."
            fi

        else
            error_exit "ingress-nginx 安装失败，请检查 Helm 输出"
        fi
}


# 调用组件安装函数（统一入口）
function install_component() {
    local component="$1"
    shift  # 移除第一个参数，剩余参数传递给具体的安装函数
    
    # 将组件名称中的横线转换为下划线，构造函数名
    local func_name="cmd_${component//-/_}"
    
    # 检查函数是否存在
    if declare -f "${func_name}" > /dev/null; then
        "${func_name}" "$@"
        return $?
    else
        log_error "未知组件: ${component}"
        return 1
    fi
}

# 批量安装指定组件
function cmd_components() {
    local components_list="$1"
    
    if [[ -z "${components_list}" ]]; then
        error_exit "组件列表不能为空，请使用 --components 参数指定组件列表"
    fi
    
    log_step "开始批量安装组件"
    log_info "组件列表: ${components_list}"
    
    # 将逗号分隔的字符串转换为数组
    IFS=',' read -ra COMPONENTS <<< "${components_list}"
    
    local total=${#COMPONENTS[@]}
    local success_count=0
    local failed_count=0
    local failed_components=()
    
    log_info "共需安装 ${total} 个组件"
    echo ""
    
    # 遍历安装每个组件
    for i in "${!COMPONENTS[@]}"; do
        local component="${COMPONENTS[$i]}"
        # 去除前后空格
        component=$(echo "${component}" | xargs)
        
        local current=$((i + 1))
        log_step "安装组件 [${current}/${total}]: ${component}"
        
        # 调用统一的组件安装函数
        if install_component "${component}"; then
            success_count=$((success_count + 1))
            log_info "✓ ${component} 安装成功"
        else
            failed_count=$((failed_count + 1))
            failed_components+=("${component}")
            log_error "✗ ${component} 安装失败"
        fi
        
        echo ""
    done
    
    # 显示安装汇总
    log_step "批量安装完成"
    log_info "总计: ${total} 个组件"
    log_info "成功: ${success_count} 个"
    log_info "失败: ${failed_count} 个"
    
    if [[ ${failed_count} -gt 0 ]]; then
        log_error "失败的组件列表:"
        for failed_comp in "${failed_components[@]}"; do
            log_error "  - ${failed_comp}"
        done
        error_exit "批量安装未完全成功，请检查失败的组件"
    else
        log_info "✓ 所有组件安装成功！"
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
    cmd_csi_nfs
    cmd_csi_disk ""
    cmd_csi_oss
    cmd_cloud_controller_manager
    cmd_node_agent

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
            --components)
                local components_list="$2"
                shift 2
                
                # 初始化日志文件
                init_log_file "components"
                
                log_info "=========================================="
                log_info "Kubernetes 组件批量安装脚本"
                log_info "命令: 批量安装"
                log_info "命名空间: ${NAMESPACE}"
                [[ "${VERBOSE}" == "true" ]] && log_info "详细模式: 已启用"
                [[ "${DEBUG}" == "true" ]] && log_info "调试模式: 已启用"
                log_info "=========================================="
                log_info "组件列表: ${components_list}"
                log_info "Charts 目录: ${CHARTS_DIR}"
                
                # 验证 charts 目录是否存在
                if [[ ! -d "${CHARTS_DIR}" ]]; then
                    error_exit "Charts 目录不存在: ${CHARTS_DIR}，请确保已通过入口脚本 install.sh 执行代码同步"
                fi
                
                # 执行批量安装
                cmd_components "${components_list}"
                
                echo ""
                log_info "=========================================="
                log_info "批量安装完成！"
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
            -h|--help)
                print_help
                exit 0
                ;;
            prometheus|alertmanager|grafana|loki|loki-add-ingress|loki-update-promtail-config|dcgm-exporter|prometheus-adapter|alertmanager-webhook-adapter|cronhpa-controller|vpc-cni|p2p-accelerator|csi-disk|csi-oss|csi-nfs|cloud-controller-manager|node-agent|ingress-nginx|kubeprober|velero|all)
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
                
                # 执行对应的命令（使用统一的组件安装函数）
                install_component "${cmd}" "$@"
                
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

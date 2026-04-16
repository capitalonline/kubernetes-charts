# Kubernetes 监控组件安装脚本

一套简单易用的脚本工具，用于快速部署、管理和监控 Kubernetes 集群的完整监控解决方案。

## 📦 组件列表

### 核心监控组件

| 组件 | 说明 | 版本 | 安装方式 |
|------|------|------|---------|
| **Prometheus** | 监控和告警工具包 | v2.46.0 | 一体化 Chart，包含 3 个内置 Exporters |
| **Alertmanager** | 告警管理器 | v0.26.0 | 独立安装 |
| **Grafana** | 指标可视化和仪表板 | 10.3.1 | 独立安装 |
| **Loki** | 日志聚合系统 | - | 独立安装 |

### 内置在 Prometheus 中的组件

以下组件已集成在 Prometheus chart 中，安装 Prometheus 时会自动部署：

| 组件 | 说明 | 版本 |
|------|------|------|
| **Node Exporter** | 节点指标导出器 | v1.6.1 |
| **Kube State Metrics** | K8s 集群状态指标 | v2.9.2 |
| **Blackbox Exporter** | 黑盒监控探针 | v0.24.0 |

### 独立组件

| 组件 | 说明 | 版本 |
|------|------|------|
| **DCGM Exporter** | NVIDIA GPU 指标导出器 | - |
| **Prometheus Adapter** | K8s 自定义指标 API（HPA 支持） | v0.11.1 |
| **Alertmanager Webhook Adapter** | Alertmanager Webhook 适配器 | v1.1.7 |
| **CronHPA Controller** | 定时 HPA 控制器（安装到 kube-system） | v1.0.0 |
| **VPC CNI** | 容器网络接口插件（安装到 kube-system） | v3.0.0 |
| **P2P Accelerator** | 镜像加速（安装到 kube-system） | v0.4.0 |
| **CSI Disk** | 云盘存储 CSI 驱动（安装到 kube-system） | v1.0.1-eks |
| **CSI NFS** | NFS 存储 CSI 驱动（安装到 kube-system） | - |
| **CSI OSS** | 对象存储 CSI 驱动（安装到 kube-system） | - |
| **KubeProber** | Kubernetes 集群诊断工具（安装到 kube-system） | v1.0.0 |

## 🚀 快速开始

### 脚本架构

本项目采用**双脚本架构**设计，确保安装时始终使用最新版本的安装逻辑：

```
install.sh                          # 轻量级入口脚本（本地执行）
    ├─ 同步代码仓库 (git pull)
    └─ 调用 scripts/install-components.sh（从仓库同步的最新版本）
        └─ 执行实际的安装逻辑
```

**设计优势：**
- ✅ **自动更新**：即使本地 `install.sh` 较旧，也能拉取最新的安装脚本
- ✅ **持续改进**：安装逻辑的改进会在下次运行时自动生效
- ✅ **版本一致**：确保所有用户使用相同版本的安装逻辑

**前提条件：**
- ⚠️ 需要预先克隆仓库到 `/srv/kubernetes-charts`
- ⚠️ 如果仓库不存在，脚本会报错退出

### 代码同步

**前提条件：首次使用需要手动克隆仓库**

```bash
# 克隆代码仓库到 /srv 目录
sudo git clone https://gitee.com/capitalonline2025/kubernetes-charts.git /srv/kubernetes-charts
```

**自动同步：**

后续使用时，所有入口脚本（install.sh、uninstall.sh、update-image.sh）会自动执行 `git pull` 同步最新代码：

```bash
# 自动 git pull 更新代码后执行安装
./install.sh prometheus
```

**同步逻辑：**
- ✅ 如果 `/srv/kubernetes-charts/.git` 存在 → 执行 `git pull` 更新（失败时重试 10 次，每次间隔 1 秒）
- ❌ 如果仓库不存在 → 报错退出（需要先手动克隆）
- ✅ 自动使用同步后的 charts：`/srv/kubernetes-charts/charts`

### 一键部署完整监控栈

```bash
# 安装所有组件（自动同步代码 + 初始化 + 调试模式 + 保存日志）
./install.sh -d -l all
```

这会安装：
- ✅ Prometheus（包含 Node Exporter、Kube State Metrics、Blackbox Exporter）
- ✅ Alertmanager
- ✅ Grafana
- ✅ Loki
- ✅ DCGM Exporter
- ✅ Prometheus Adapter
- ✅ Alertmanager Webhook Adapter
- ✅ CronHPA Controller
- ✅ VPC CNI
- ✅ P2P Accelerator
- ✅ CSI Disk

### 安装单个组件

#### 安装 Prometheus

```bash
# 自定义参数安装（ETCD 端点自动检测）
./install.sh -d -l prometheus \
  --retention 7d \
  --storage-size 50Gi \
  --storage-class default-local-sc \
  --ingress prometheus.example.com,prometheus-internal.example.com \
  --htpasswd admin:admin
```

#### 安装 Grafana

```bash
./install.sh -d -l grafana \
  --storage-size 100Gi \
  --storage-class default-local-sc \
  --ingress grafana.example.com,grafana-internal.example.com
```

#### 安装 Alertmanager

```bash
./install.sh -d -l alertmanager \
  --ingress alertmanager.example.com,alertmanager-internal.example.com \
  --htpasswd admin:admin
```

#### 安装 Loki

```bash
# 基础安装（不含 Ingress）
./install.sh -d -l loki \
  --retention 30d \
  --max-query-length 30d \
  --storage-size 200Gi \
  --storage-class default-local-sc

# 安装并同时配置 Ingress（HTTP，无 TLS）
./install.sh -d -l loki \
  --retention 30d \
  --storage-size 200Gi \
  --storage-class default-local-sc \
  --ingress loki.example.com
```

#### 为已安装的 Loki 补充安装 Ingress

```bash
# 对之前未配置 Ingress 的 Loki 补充安装
./install.sh -d -l loki-add-ingress \
  --ingress loki.example.com
```

#### 更新 Loki promtail-config 配置并滚动重启

修改 `charts/loki/templates/promtail/promtail-config.yaml` 后执行：

```bash
./install.sh -d -l loki-update-promtail-config
```

执行流程：re-apply `promtail-config.yaml` → 滚动重启 `promtail-daemonset` 所有 Pod

#### 安装其他组件

```bash
# DCGM Exporter（GPU 监控）
./install.sh -d -l dcgm-exporter

# Prometheus Adapter（自定义指标 API）
./install.sh -d -l prometheus-adapter

# Alertmanager Webhook Adapter
./install.sh -d -l alertmanager-webhook-adapter

# CronHPA Controller（定时 HPA 控制器）
./install.sh -d -l cronhpa-controller

# VPC CNI（容器网络插件）
./install.sh -d -l vpc-cni

# P2P Accelerator（镜像加速）
./install.sh -d -l p2p-accelerator \
  --mirrored-registries https://aj941n.yun-paas.com

# CSI Disk（云盘存储）
./install.sh -d -l csi-disk

# KubeProber（集群诊断工具）
./install.sh -d -l kubeprober
```

#### 批量安装多个组件

使用 `--components` 参数可以一次性安装多个组件（逗号分隔）：

```bash
# 批量安装所有 CSI 存储驱动
./install.sh --components csi-oss,csi-nfs,csi-disk

# 批量安装监控组件（带调试日志）
./install.sh -d -l --components prometheus,grafana,alertmanager

# 批量安装基础设施组件
./install.sh --components vpc-cni,p2p-accelerator,cronhpa-controller
```

> **注意**：批量安装时所有组件使用默认参数，如需自定义参数请单独安装

## 🛠️ 脚本工具

本项目提供 4 个主要脚本工具：

| 脚本 | 功能 | 说明 | 日志功能 |
|------|------|------|---------|
| `install.sh` | 安装组件 | 部署新的监控组件到集群 | ✅ 支持 `-l` 参数 |
| `upgrade.sh` | 升级组件 | 更新已安装组件的配置或版本 | - |
| `update-image.sh` | 更新镜像 | 更新容器镜像版本（不改变其他配置） | ✅ 支持 `-l` 参数 |
| `uninstall.sh` | 卸载组件 | 从集群中移除监控组件 | ✅ 支持 `-l` 参数 |

### install.sh - 安装监控组件

**语法：**
```bash
./install.sh [全局选项] <组件名> [组件参数]
```

**可用组件：**
- `prometheus` - 安装 Prometheus（包含 Node Exporter、Kube State Metrics、Blackbox Exporter）
- `alertmanager` - 安装 Alertmanager
- `grafana` - 安装 Grafana
- `loki` - 安装 Loki
- `loki-add-ingress` - 为已安装的 Loki 补充安装 Ingress
- `dcgm-exporter` - 安装 DCGM Exporter
- `prometheus-adapter` - 安装 Prometheus Adapter
- `alertmanager-webhook-adapter` - 安装 Alertmanager Webhook Adapter
- `cronhpa-controller` - 安装 CronHPA Controller
- `vpc-cni` - 安装 VPC CNI 网络插件
- `p2p-accelerator` - 安装 P2P Accelerator 镜像加速
- `csi-disk` - 安装 CSI Disk 云盘存储驱动
- `cloud-controller-manager` - 安装 Cloud Controller Manager 云控制器管理器
- `all` - 安装所有组件

**全局选项：**
- `-n, --namespace NAME` - 指定命名空间（默认：monitoring）
- `-v, --verbose` - 显示详细信息（包括执行的命令）
- `-d, --debug` - 调试模式（显示更详细的调试信息）
- `-l, --log` - 保存日志到 `/tmp` 目录（自动生成文件名，包含组件名和时间戳）
- `--components COMP1,COMP2,...` - 批量安装指定组件（逗号分隔）
- `-h, --help` - 显示帮助信息

**Prometheus 参数：**
- `--retention TIME` - 数据保留时间（默认：1d）
- `--storage-class CLASS` - 存储类（默认：default-local-sc）
- `--storage-size SIZE` - 存储大小（默认：10Gi）
- `--ingress HOST1,HOST2` - Ingress 主机名（逗号分隔）
- `--htpasswd USER:PASS` - HTTP 基本认证（格式：username:password 或 username:$apr1$hash...）

> **注意**：ETCD 监控端点会自动从集群检测（`kubectl get pod -n kube-system -l component=etcd`）

**Grafana 参数：**
- `--storage-class CLASS` - 存储类（默认：default-local-sc）
- `--storage-size SIZE` - 存储大小（默认：50Gi）
- `--ingress HOST1,HOST2` - Ingress 主机名（逗号分隔）

**Alertmanager 参数：**
- `--ingress HOST1,HOST2` - Ingress 主机名（逗号分隔）
- `--htpasswd USER:PASS` - HTTP 基本认证（格式：username:password 或 username:$apr1$hash...）
- `--enable-rules` - 启用 Prometheus Rules（默认禁用，包含 8 个预定义告警规则）

**Loki 参数：**
- `--storage-class CLASS` - 存储类（默认：default-local-sc）
- `--storage-size SIZE` - 存储大小（默认：50Gi）
- `--retention TIME` - 日志数据保留期（默认：30d）
- `--max-query-length TIME` - 单次查询最大时间范围（默认：30d）
- `--ingress HOST` - [可选] Ingress 主机名（HTTP，无 TLS），为空则不创建 Ingress

**loki-add-ingress 参数：**
- `--ingress HOST` - [必传] Ingress 主机名，为已安装的 Loki 补充安装 Ingress

**loki-update-promtail-config：**
- 无参数，修改 `charts/loki/templates/promtail/promtail-config.yaml` 后执行即可

**P2P Accelerator 参数：**
- `--mirrored-registries URL1,URL2` - [必传] 镜像仓库地址列表（逗号分隔，如：https://registry1.com,https://registry2.com）

> **注意**：
> - `cronhpa-controller`、`vpc-cni`、`p2p-accelerator` 和 `csi-disk` 固定安装到 `kube-system` 命名空间，不受 `-n` 参数影响
> - `vpc-cni` 使用 values.yaml 中的默认配置（Underlay 网络、IPv4、3 副本）
> - `p2p-accelerator` 以 DaemonSet 方式在每个节点运行
> - `csi-disk` 提供云盘存储的 CSI 驱动支持

### upgrade.sh - 升级监控组件

**示例：**
```bash
# 升级 Prometheus（保留现有配置）
./upgrade.sh prometheus

# 升级 Prometheus（修改参数）
./upgrade.sh -d -l prometheus --retention 30d --storage-size 100Gi

# 升级所有已安装的组件
./upgrade.sh all
```

### uninstall.sh - 卸载监控组件

**支持的参数：**
- `-v, --verbose` - 显示详细信息（包括执行的命令）
- `-d, --debug` - 调试模式（显示更详细的调试信息）
- `-l, --log` - 保存日志到 /tmp 目录（自动生成文件名，包含组件名、时间戳和代码行号）
- `--delete-secrets` - 同时删除 secrets（etcd-certs、monitoring-certs）

**特性：**
- ✅ 支持重复卸载（幂等性）
- ✅ 自动使用正确的命名空间（monitoring 或 kube-system）
- ✅ **自动删除 PVC 和 PV**（卸载 Prometheus/Grafana/Loki 时会自动清理持久化存储）
- ✅ 卸载失败时报错退出

> **⚠️ 重要提示**：
> - 卸载 **Prometheus**、**Grafana**、**Loki** 时会**自动删除 PVC 和 PV**，所有持久化数据将被永久删除
> - PVC 和 PV 会被自动清理，无需额外参数
> - 如需保留数据，请在卸载前备份 PVC 内容

**示例：**
```bash
# 卸载单个组件
./uninstall.sh prometheus

# 卸载组件并删除 secrets
./uninstall.sh prometheus --delete-secrets

# 详细模式卸载
./uninstall.sh -v prometheus

# 调试模式并保存日志
./uninstall.sh -d -l prometheus --delete-secrets

# 保存日志到指定文件
./uninstall.sh --log-file /var/log/uninstall.log prometheus

# 卸载 kube-system 命名空间的组件
./uninstall.sh cronhpa-controller
./uninstall.sh vpc-cni
./uninstall.sh p2p-accelerator
./uninstall.sh csi-disk

# 批量卸载（可以安全地重复执行）
for component in prometheus alertmanager grafana loki; do
  ./uninstall.sh -v ${component}
done
```

### update-image.sh - 更新容器镜像

用于更新已部署组件的容器镜像版本，支持 Deployment、StatefulSet 和 DaemonSet 类型的资源。

**必需参数：**
- `<release>` - Helm release 名称
- `-c, --container <name>` - 容器名称
- `-i, --image <image>` - 新镜像（格式：`[registry/]repository:tag`）
- `-n, --namespace <ns>` - 命名空间
- `-k, --kind <kind>` - 资源类型（Deployment、StatefulSet 或 DaemonSet）

**全局选项：**
- `-l, --log` - 保存日志到 /tmp 目录（自动生成文件名，包含 release 名称、时间戳和代码行号）
- `-h, --help` - 显示帮助信息

**命令选项：**
- `-v, --verbose` - 详细输出
- `-d, --debug` - 调试模式

**示例：**
```bash
# 更新 cronhpa-controller 镜像（Deployment）
./update-image.sh cronhpa-controller \
  -c cronhpa-controller \
  -i harbor-dev.yun-paas.com/dev/kubernetes-cronhpa-controller:v1.1.0 \
  -n kube-system \
  -k Deployment

# 更新 Prometheus Node Exporter（DaemonSet）
./update-image.sh prometheus \
  -c node-exporter \
  -i registry.io/node-exporter:v1.7.0 \
  -n monitoring \
  -k DaemonSet

# 更新 Grafana（StatefulSet）
./update-image.sh grafana \
  -c grafana \
  -i registry.io/grafana:10.0.0 \
  -n monitoring \
  -k StatefulSet

# 启用调试日志
./update-image.sh prometheus \
  -c prometheus \
  -i registry.io/prometheus:v2.47.0 \
  -n monitoring \
  -k StatefulSet \
  -d -l
```

**工作原理：**
1. 使用 `helm upgrade --set` 更新镜像配置
2. Kubernetes 自动触发滚动更新

**注意事项：**
- 镜像格式必须包含 tag（不支持 `latest` 隐式标签）
- 更新会触发 Pod 滚动重启
- 建议在更新前备份重要数据
- 更新后可使用 `kubectl rollout status` 手动检查滚动更新状态

### status.sh - 查看组件状态

**示例：**
```bash
# 查看所有组件状态
./status.sh

# 查看指定组件状态
./status.sh --component prometheus

# 显示详细信息
./status.sh --detail
```

## 📖 完整示例

### 场景 1：生产环境完整部署

```bash
# 1. 安装 Prometheus（包含 3 个内置 Exporters，自动检测 ETCD）
./install.sh -d -l prometheus \
  --retention 15d \
  --storage-size 100Gi \
  --storage-class fast-ssd \
  --ingress prometheus.example.com,prometheus-internal.example.com \
  --htpasswd admin:SecurePassword

# 2. 安装 Alertmanager
./install.sh -d -l alertmanager \
  --ingress alertmanager.example.com,alertmanager-internal.example.com \
  --htpasswd admin:SecurePassword

# 3. 安装 Grafana
./install.sh -d -l grafana \
  --storage-size 100Gi \
  --storage-class fast-ssd \
  --ingress grafana.example.com,grafana-internal.example.com

# 4. 安装 Loki（含 Ingress）
./install.sh -d -l loki \
  --storage-size 200Gi \
  --storage-class fast-ssd \
  --ingress loki.example.com

# 5. 安装其他组件
./install.sh -d -l dcgm-exporter                     # GPU 监控（如有 NVIDIA GPU）
./install.sh -d -l prometheus-adapter                # 自定义指标 API（HPA 支持）
./install.sh -d -l alertmanager-webhook-adapter      # Webhook 适配器
./install.sh -d -l cronhpa-controller                # 定时 HPA 控制器
./install.sh -d -l vpc-cni                           # VPC CNI 网络插件
./install.sh -d -l p2p-accelerator \
  --mirrored-registries https://aj941n.yun-paas.com # P2P 镜像加速

# 6. 验证部署
kubectl -n monitoring get pods                       # 大部分组件
kubectl -n kube-system get pods -l app=cronhpa-controller  # CronHPA Controller
kubectl -n kube-system get pods -l app.kubernetes.io/name=vpc-cni  # VPC CNI
kubectl -n kube-system get pods -l app.kubernetes.io/app-component=p2p-accelerator  # P2P Accelerator
kubectl -n monitoring get svc
kubectl -n monitoring get pvc
```

### 场景 2：开发/测试环境快速部署

```bash
# 一键安装所有组件
./install.sh -d -l all

# 或者批量安装指定组件
./install.sh -d -l --components prometheus,grafana,loki,csi-disk

# 查看状态
./status.sh
```

### 场景 3：升级存储配置

```bash
# 升级 Prometheus 存储空间
./upgrade.sh -d -l prometheus --storage-size 200Gi

# 升级 Grafana 存储空间
./upgrade.sh -d -l grafana --storage-size 200Gi
```

### 场景 4：更新容器镜像

```bash
# 更新单个组件的镜像
./update-image.sh cronhpa-controller \
  -c cronhpa-controller \
  -i harbor-dev.yun-paas.com/dev/kubernetes-cronhpa-controller:v1.1.0 \
  -n kube-system \
  -k Deployment

# 更新 Prometheus 组件的镜像（StatefulSet）
./update-image.sh prometheus \
  -c prometheus \
  -i registry.io/prometheus:v2.47.0 \
  -n monitoring \
  -k StatefulSet

# 更新 Node Exporter 镜像（DaemonSet）
./update-image.sh prometheus \
  -c node-exporter \
  -i registry.io/node-exporter:v1.7.0 \
  -n monitoring \
  -k DaemonSet
```

### 场景 5：批量部署存储解决方案

```bash
# 批量安装所有 CSI 存储驱动
./install.sh -d -l --components csi-nfs,csi-disk,csi-oss

# 验证安装
kubectl -n kube-system get pods | grep csi
kubectl get csidriver

# 查看日志
cat /tmp/k8s-install-components-*.log
```

### 场景 6：卸载组件

```bash
# 卸载单个组件（支持重复执行）
./uninstall.sh -v prometheus

# 卸载组件并删除 secrets
./uninstall.sh -v prometheus --delete-secrets

# 卸载 kube-system 命名空间的组件
./uninstall.sh -v cronhpa-controller
./uninstall.sh -v vpc-cni
./uninstall.sh -v p2p-accelerator
./uninstall.sh -v csi-disk
./uninstall.sh -v kubeprober
```

## 🔍 验证安装

### 检查所有 Pod

```bash
kubectl -n monitoring get pods -o wide
```

### 使用标签查询特定组件的 Pod

```bash
# 查询 Prometheus 组件的所有 Pod（包括 prometheus、node-exporter、kube-state-metrics 等）
kubectl -n monitoring get pods -l app.kubernetes.io/app-component=prometheus

# 查询 Grafana 组件的 Pod
kubectl -n monitoring get pods -l app.kubernetes.io/app-component=grafana

# 查询 Alertmanager 组件的 Pod
kubectl -n monitoring get pods -l app.kubernetes.io/app-component=alertmanager

# 查询 Loki 组件的 Pod
kubectl -n monitoring get pods -l app.kubernetes.io/app-component=loki

# 查询 CronHPA Controller（在 kube-system 命名空间）
kubectl -n kube-system get pods -l app.kubernetes.io/app-component=cronhpa-controller

# 查询 VPC CNI（在 kube-system 命名空间）
kubectl -n kube-system get pods -l app.kubernetes.io/app-component=vpc-cni

# 查询 P2P Accelerator（在 kube-system 命名空间）
kubectl -n kube-system get pods -l app.kubernetes.io/app-component=p2p-accelerator

# 查询 CSI Disk（在 kube-system 命名空间）
kubectl -n kube-system get pods -l app.kubernetes.io/app-component=csi-disk
```

### 检查 Service

```bash
kubectl -n monitoring get svc
```

### 检查 Ingress

```bash
kubectl -n monitoring get ingress
```

### 检查持久化存储

```bash
kubectl -n monitoring get pvc
```

## 🌐 访问服务

### 通过 Ingress 访问（推荐）

根据配置的 Ingress 主机名访问：

- **Prometheus**: `https://prometheus.example.com`
  - 默认账号/密码：`admin/admin`（可通过 `--htpasswd` 自定义）
  
- **Grafana**: `https://grafana.example.com`
  - 默认账号/密码：`admin/admin`
  
- **Alertmanager**: `https://alertmanager.example.com`
  - 默认账号/密码：`admin/admin`（可通过 `--htpasswd` 自定义）

- **Loki**: `http://loki.example.com`（HTTP，无 TLS）
  - 可直接作为 Grafana 数据源地址

### 通过 Port Forward 访问

```bash
# Prometheus
kubectl -n monitoring port-forward svc/prometheus-k8s 9090:9090

# Grafana
kubectl -n monitoring port-forward svc/grafana 3000:3000

# Alertmanager
kubectl -n monitoring port-forward svc/alertmanager-main 9093:9093
```

## 📊 日志功能

所有主要脚本（install.sh、uninstall.sh、update-image.sh）都支持统一的日志记录功能，便于问题追踪和调试。

### 基本用法

```bash
# 安装时记录日志
./install.sh -l prometheus --retention 30d

# 卸载时记录日志
./uninstall.sh -l prometheus

# 更新镜像时记录日志
./update-image.sh -l prometheus -c prometheus \
  -i registry.io/prometheus:v2.50.0 \
  -n monitoring -k StatefulSet
```

### 日志文件特性

**自动生成路径：**
- 所有日志统一保存到 `/tmp` 目录
- 文件名自动包含：操作类型、组件名、时间戳
- 示例文件名：
  - `/tmp/k8s-monitoring-install-prometheus-20241105-120530.log`
  - `/tmp/k8s-monitoring-uninstall-grafana-20241105-143022.log`
  - `/tmp/k8s-update-image-prometheus-20241105-165545.log`

**统一日志输出：**
- 入口脚本和核心脚本写入同一个日志文件
- 完整记录从代码同步到操作完成的全过程

### 日志管理

```bash
# 查看所有日志文件
ls -lh /tmp/k8s-monitoring-*.log
ls -lh /tmp/k8s-update-image-*.log

# 查看特定日志
cat /tmp/k8s-monitoring-install-prometheus-20241105-120530.log

# 搜索错误信息
grep ERROR /tmp/k8s-monitoring-*.log

# 清理 7 天前的旧日志
find /tmp -name "k8s-monitoring-*.log" -mtime +7 -delete
find /tmp -name "k8s-update-image-*.log" -mtime +7 -delete

# 备份重要日志
mkdir -p /var/log/k8s-monitoring
mv /tmp/k8s-monitoring-*.log /var/log/k8s-monitoring/
```

### 日志级别

```bash
# 标准模式（只显示关键信息）
./install.sh prometheus

# 详细模式（显示所有命令）
./install.sh -v prometheus

# 调试模式（显示所有调试信息 + 详细输出）
./install.sh -d prometheus

# 调试模式 + 保存日志
./install.sh -d -l prometheus
```

### 注意事项

- ⚠️ `/tmp` 目录在系统重启后可能被清空，重要日志请及时备份
- ⚠️ 日志文件包含完整的操作记录，可能包含敏感信息（如镜像地址、配置参数）
- ⚠️ 定期清理旧日志，避免占用过多磁盘空间
- ✅ 生产环境建议始终使用 `-l` 参数记录日志，便于问题追踪

## 🔐 安全配置

### 生成 htpasswd 密码

```bash
# 方法 1：使用 htpasswd 工具
htpasswd -nb admin yourpassword

# 方法 2：使用 Docker
docker run --rm httpd:alpine htpasswd -nb admin yourpassword
```

### 配置认证

```bash
# Prometheus 认证
./install.sh prometheus --htpasswd 'admin:$apr1$xyz...'

# Alertmanager 认证
./install.sh alertmanager --htpasswd 'admin:$apr1$xyz...'
```

## 📁 目录结构

```
kubernetes-charts/
├── install.sh                          # 安装脚本
├── uninstall.sh                        # 卸载脚本
├── upgrade.sh                          # 升级脚本
├── update-image.sh                     # 镜像更新脚本
├── status.sh                           # 状态查看脚本
├── README.md                           # 本文件
├── QUICKSTART.md                       # 快速开始指南
└── charts/                             # Helm Charts
    ├── prometheus/                     # Prometheus 一体化 Chart
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   ├── crds/                       # Prometheus Operator CRDs
    │   └── templates/                  # Kubernetes 资源模板
    │       ├── node-exporter/          # 内置：Node Exporter 模板
    │       ├── kube-state-metrics/     # 内置：Kube State Metrics 模板
    │       ├── blackbox-exporter/      # 内置：Blackbox Exporter 模板
    │       ├── prometheus-*.yaml       # Prometheus 资源
    │       └── prometheusOperator-*.yaml
    ├── alertmanager/                   # Alertmanager Chart
    ├── grafana/                        # Grafana Chart
    ├── loki/                           # Loki Chart
    ├── dcgm-exporter/                  # DCGM Exporter Chart
    ├── prometheus-adapter/             # Prometheus Adapter Chart
    └── alertmanager-webhook-adapter/   # Webhook Adapter Chart
```

## 🔧 高级配置

### 自定义命名空间

大部分组件默认安装到 `monitoring` 命名空间，可通过 `-n` 参数自定义：

```bash
./install.sh -n custom-monitoring prometheus
./install.sh -n custom-monitoring grafana
```

**特殊说明：**
- `cronhpa-controller`、`vpc-cni`、`p2p-accelerator` 和 `csi-disk` 固定安装到 `kube-system` 命名空间
- Node Exporter、Kube State Metrics、Blackbox Exporter 随 Prometheus 一起安装

### ETCD 监控配置

ETCD 监控端点会**自动检测**，无需手动指定。脚本会通过以下命令自动发现 ETCD 端点：

```bash
kubectl get pod -n kube-system -l component=etcd -o wide
```

**前提条件：**
需要准备 ETCD 证书文件（脚本会自动检测并创建 Secret）：
- `/etc/kubernetes/pki/etcd/healthcheck-client.crt`
- `/etc/kubernetes/pki/etcd/healthcheck-client.key`
- `/etc/kubernetes/pki/etcd/ca.crt`

**注意：**
- ETCD 必须以 Pod 形式运行，并有 `component=etcd` 标签
- kubectl 需有访问 `kube-system` 命名空间的权限

## 🐛 故障排查

### 查看日志

```bash
# 查看 Prometheus 日志
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus -c prometheus

# 查看 Node Exporter 日志
kubectl -n monitoring logs -l app.kubernetes.io/name=node-exporter

# 查看 Kube State Metrics 日志
kubectl -n monitoring logs -l app.kubernetes.io/name=kube-state-metrics

# 查看 Grafana 日志
kubectl -n monitoring logs -l app.kubernetes.io/name=grafana
```

### 检查资源状态

```bash
# 查看 PVC 状态
kubectl -n monitoring get pvc

# 查看 StatefulSet
kubectl -n monitoring get sts

# 查看 DaemonSet
kubectl -n monitoring get ds

# 查看事件
kubectl -n monitoring get events --sort-by='.lastTimestamp'
```

### 常见问题

#### 1. Prometheus Pod 一直 Pending

检查 PVC 是否成功绑定：
```bash
kubectl -n monitoring describe pvc prometheus-prometheus-db-prometheus-prometheus-0
```

确保 StorageClass 存在：
```bash
kubectl get storageclass
```

#### 2. Node Exporter Pod 无法调度

Node Exporter 是 DaemonSet，会在每个节点上运行。检查节点标签和污点：
```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

#### 3. ETCD 监控不工作

```bash
# 手动验证自动检测命令
kubectl get pod -n kube-system -l component=etcd -o wide
```

```bash
# 检查 etcd-certs secret
kubectl -n monitoring get secret etcd-certs

# 检查 ETCD 端点配置
kubectl -n monitoring get endpoints prometheus-etcd
```

#### 4. Ingress 无法访问

```bash
kubectl -n monitoring describe ingress prometheus
```

#### 5. Prometheus Adapter APIService 不可用

```bash
# 查看 APIService
kubectl get apiservice | grep metrics

# 检查 prometheus-adapter 服务
kubectl -n monitoring get svc prometheus-adapter
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus-adapter
```

### 调试 Helm Release

```bash
# 查看 release 信息
helm status prometheus -n monitoring

# 查看实际渲染的资源
helm get manifest prometheus -n monitoring

# 查看配置值
helm get values prometheus -n monitoring

# 查看历史版本
helm history prometheus -n monitoring

# 回滚到上一个版本
helm rollback prometheus -n monitoring
```

## ⚠️ 注意事项

1. **首次安装 Prometheus**：需要先安装 CRDs
   ```bash
   kubectl apply --server-side -f charts/prometheus/crds/
   ```

2. **存储类**：确保集群中存在指定的 StorageClass（默认：`default-local-sc`）

3. **ETCD 证书**：如果要监控 ETCD，确保证书文件存在于 `/etc/kubernetes/pki/etcd/`
   - ETCD 端点会自动检测，无需手动指定

4. **TLS 证书**：如果要使用 HTTPS Ingress，确保证书文件存在于 `/tmp/yun-paas.key` 和 `/tmp/yun-paas.crt`

5. **命名空间**：
   - 大部分组件默认安装到 `monitoring` 命名空间
   - `cronhpa-controller`、`vpc-cni`、`p2p-accelerator` 和 `csi-disk` 固定安装到 `kube-system` 命名空间

6. **资源规划**：
   - Prometheus：根据监控目标数量和保留时间规划存储（建议至少 50Gi）
   - Grafana：一般 10-50Gi 足够
   - Loki：根据日志量规划（建议至少 100Gi）

7. **Prometheus Adapter**：
   - 注册 `custom.metrics.k8s.io` 和 `external.metrics.k8s.io` APIService
   - 不与 metrics-server 的 `metrics.k8s.io` 冲突
   - 支持 HPA 自定义指标扩缩容

8. **VPC CNI**：
   - 提供容器网络接口（CNI）功能
   - 固定安装到 `kube-system` 命名空间
   - Helm 会自动部署所需的 CRDs
   - 卸载时 CRDs 会被保留（避免数据丢失）
   - 使用 values.yaml 中的默认配置

9. **备份**：升级前建议备份重要数据：
   ```bash
   kubectl -n monitoring get pvc
   # 备份 PVC 对应的数据
   ```

10. **PVC/PV 自动清理**：
   - 卸载 **Prometheus**、**Grafana**、**Loki** 时会**自动删除 PVC 和 PV**
   - 所有持久化数据（监控数据、Dashboard、日志）将被永久删除
   - 如需保留数据，请在卸载前手动备份 PVC 内容或底层存储卷数据

11. **密码安全**：生产环境请使用强密码，不要使用 `admin:admin`

## 🎯 最佳实践

1. **使用调试模式和日志**：生产部署时建议使用 `-d -l` 保存完整日志
   ```bash
   ./install.sh -d -l prometheus --retention 30d --storage-size 200Gi
   ```

2. **分步部署**：建议按顺序安装
   ```
   Prometheus → Alertmanager → Grafana → Loki → 其他组件
   ```

3. **资源隔离**：使用节点选择器和污点容忍
   - 监控组件部署在专用节点
   - 避免影响业务应用

4. **监控监控系统**：配置 Prometheus 自监控和告警规则

5. **定期备份**：
   - 定期备份 Prometheus 数据
   - 导出重要的 Grafana Dashboard
   - 备份 Alertmanager 配置

## 📁 项目结构

```
kubernetes-charts/
├── install.sh                         # 安装入口脚本（轻量级，只负责代码同步）
├── uninstall.sh                       # 卸载入口脚本（轻量级，只负责代码同步）
├── upgrade.sh                         # 升级入口脚本（轻量级，只负责代码同步）
├── update-image.sh                    # 镜像更新入口脚本（轻量级，只负责代码同步）
├── scripts/
│   ├── install-components.sh          # 真正的安装逻辑（从仓库同步）
│   ├── uninstall-components.sh        # 真正的卸载逻辑（从仓库同步）
│   ├── upgrade-components.sh          # 真正的升级逻辑（从仓库同步）
│   └── update-container-image.sh      # 真正的镜像更新逻辑（从仓库同步）
├── charts/                            # Helm Charts 目录
│   ├── prometheus/                    # 包含 Node Exporter、Kube State Metrics、Blackbox Exporter
│   ├── alertmanager/
│   ├── grafana/
│   ├── loki/
│   ├── dcgm-exporter/
│   ├── prometheus-adapter/
│   ├── alertmanager-webhook-adapter/
│   ├── cronhpa-controller/
│   ├── vpc-cni/
│   └── p2p-accelerator/
└── README.md

安装时代码同步到：/srv/kubernetes-charts/
```

**脚本说明：**
- `install.sh`：安装入口脚本，负责代码同步（git pull）并调用 `scripts/install-components.sh`
- `uninstall.sh`：卸载入口脚本，负责代码同步（git pull）并调用 `scripts/uninstall-components.sh`
- `upgrade.sh`：升级入口脚本，负责代码同步（git pull）并调用 `scripts/upgrade-components.sh`
- `update-image.sh`：镜像更新入口脚本，负责代码同步（git pull）并调用 `scripts/update-container-image.sh`
- `scripts/install-components.sh`：实际的安装逻辑，包含所有组件安装函数
- `scripts/uninstall-components.sh`：实际的卸载逻辑，支持单个或批量卸载组件
- `scripts/upgrade-components.sh`：实际的升级逻辑，用于更新已安装的组件
- `scripts/update-container-image.sh`：实际的镜像更新逻辑，使用 helm upgrade --set 更新容器镜像

**代码同步说明：**
- 所有入口脚本在执行前会自动执行 `git pull` 更新代码（重试 10 次）
- 需要预先将仓库克隆到 `/srv/kubernetes-charts`
- 如果仓库不存在，脚本会报错退出

## 📚 扩展阅读

- 各组件详细配置请查看 `charts/<组件名>/values.yaml`
- Prometheus Operator 详细说明请查看 `charts/prometheus/README.md`
- 快速开始指南请查看 [QUICKSTART.md](QUICKSTART.md)

## 📄 许可证

请查看 [LICENSE](LICENSE) 文件了解详情。

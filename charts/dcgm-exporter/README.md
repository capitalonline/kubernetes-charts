# DCGM Exporter Helm Chart

这是一个用于在 Kubernetes 集群中部署 NVIDIA DCGM Exporter 的 Helm Chart，用于监控 NVIDIA GPU 指标。

## 概述

此 Chart 包含以下组件：
- DCGM Exporter DaemonSet - 在有 GPU 的节点上收集 GPU 指标
- ServiceMonitor - Prometheus 监控集成
- ClusterRole 和 ClusterRoleBinding - RBAC 权限配置
- Service - 服务暴露
- ServiceAccount - 服务账号

## 特性

- **DaemonSet 部署**：在集群的 GPU 节点上运行 DCGM Exporter
- **GPU 指标收集**：收集 GPU 使用率、温度、内存、功耗等指标
- **自动发现**：通过 ServiceMonitor 自动被 Prometheus 发现和抓取
- **安全配置**：使用 kube-rbac-proxy 提供安全的指标访问

## 前置条件

- Kubernetes 1.19+
- Helm 3.0+
- 集群中有 NVIDIA GPU 节点
- 已安装 NVIDIA GPU Operator 或 Device Plugin
- Prometheus Operator（用于 ServiceMonitor）

## 快速开始

### 安装

使用默认配置安装：

```bash
helm install dcgm-exporter ./charts/dcgm-exporter -n monitoring --create-namespace
```

自定义镜像版本：

```bash
helm install dcgm-exporter ./charts/dcgm-exporter -n monitoring --create-namespace \
  --set dcgmExporter.image.tag=3.3.9-3.6.0-ubuntu22.04
```

### 卸载

```bash
helm uninstall dcgm-exporter -n monitoring
```

## 配置参数

### DCGM Exporter 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `dcgmExporter.image.repository` | DCGM Exporter 镜像仓库 | `capitalonline/dcgm-exporter` |
| `dcgmExporter.image.tag` | DCGM Exporter 镜像标签 | `3.3.8-3.6.0-ubuntu22.04-v3` |
| `dcgmExporter.rbacProxy.image.repository` | Kube RBAC Proxy 镜像仓库 | `capitalonline/kube-rbac-proxy` |
| `dcgmExporter.rbacProxy.image.tag` | Kube RBAC Proxy 镜像标签 | `v0.14.2` |

## 自定义安装

### 修改镜像版本

```bash
helm install dcgm-exporter ./charts/dcgm-exporter -n monitoring \
  --set dcgmExporter.image.tag=3.3.9-3.6.0-ubuntu22.04
```

### 使用自定义镜像仓库

```bash
helm install dcgm-exporter ./charts/dcgm-exporter -n monitoring \
  --set dcgmExporter.image.repository=my-registry.com/dcgm-exporter \
  --set dcgmExporter.image.tag=3.3.8-3.6.0-ubuntu22.04-v3
```

### 使用配置文件

创建 `my-values.yaml`：

```yaml
dcgmExporter:
  image:
    repository: my-registry.com/dcgm-exporter
    tag: 3.3.9-3.6.0-ubuntu22.04
  rbacProxy:
    image:
      repository: my-registry.com/kube-rbac-proxy
      tag: v0.15.0
```

安装：

```bash
helm install dcgm-exporter ./charts/dcgm-exporter -n monitoring -f my-values.yaml
```

## 部署信息

### 镜像

- DCGM Exporter: `capitalonline/dcgm-exporter:3.3.8-3.6.0-ubuntu22.04-v3`
- Kube RBAC Proxy: `capitalonline/kube-rbac-proxy:v0.14.2`

### 收集的 GPU 指标

DCGM Exporter 收集以下类型的 GPU 指标：

- **GPU 使用率**：SM（流式多处理器）使用率
- **内存使用**：已用内存、总内存
- **温度**：GPU 温度
- **功耗**：GPU 功耗（瓦特）
- **时钟频率**：GPU 和内存时钟频率
- **PCIe 吞吐量**：PCIe 发送/接收速率
- **ECC 错误**：单比特和双比特 ECC 错误
- **XID 错误**：GPU 错误代码

### 资源配置

**DCGM Exporter 容器：**
- Requests: CPU 100m, Memory 200Mi
- Limits: CPU 250m, Memory 1024Mi

**Kube RBAC Proxy 容器：**
- Requests: CPU 10m, Memory 20Mi
- Limits: CPU 20m, Memory 40Mi

## 验证安装

### 检查 Pod 状态

```bash
kubectl get pods -n monitoring -l app=nvidia-gpu-exporter
```

应该看到在每个 GPU 节点上都有一个 dcgm-exporter Pod 在运行。

### 查看日志

```bash
kubectl logs -n monitoring -l app=nvidia-gpu-exporter -c dcgm-exporter
```

### 检查 ServiceMonitor

```bash
kubectl get servicemonitor -n monitoring nvidia-gpu-exporter
```

### 测试指标端点

```bash
# 通过 port-forward 访问指标
kubectl port-forward -n monitoring daemonset/nvidia-gpu-exporter 9401:9401

# 在另一个终端中测试
curl -k https://localhost:9401/metrics
```

## 在 Prometheus 中查看

安装后，DCGM Exporter 的指标会自动被 Prometheus 抓取。可以在 Prometheus UI 中查询：

```promql
# 查看所有 GPU 的使用率
DCGM_FI_DEV_GPU_UTIL

# 查看 GPU 内存使用
DCGM_FI_DEV_FB_USED

# 查看 GPU 温度
DCGM_FI_DEV_GPU_TEMP

# 查看 GPU 功耗
DCGM_FI_DEV_POWER_USAGE
```

## 常见查询示例

### GPU 使用率

```promql
DCGM_FI_DEV_GPU_UTIL{gpu="0"}
```

### GPU 内存使用率

```promql
100 * (DCGM_FI_DEV_FB_USED / DCGM_FI_DEV_FB_FREE)
```

### GPU 温度

```promql
DCGM_FI_DEV_GPU_TEMP
```

### GPU 功耗

```promql
DCGM_FI_DEV_POWER_USAGE
```

### 按节点聚合 GPU 使用率

```promql
avg by (kubernetes_node) (DCGM_FI_DEV_GPU_UTIL)
```

## 升级

升级已安装的 DCGM Exporter：

```bash
helm upgrade dcgm-exporter ./charts/dcgm-exporter -n monitoring
```

## 故障排查

### Pod 未在 GPU 节点上运行

检查节点是否有 GPU 资源：

```bash
kubectl describe node <node-name> | grep -i gpu
```

### 指标未被 Prometheus 抓取

1. 检查 ServiceMonitor 是否正确创建：
```bash
kubectl get servicemonitor -n monitoring nvidia-gpu-exporter -o yaml
```

2. 查看 Prometheus targets：
   - 访问 Prometheus UI
   - 进入 Status → Targets
   - 查找 nvidia-gpu-exporter 相关的 targets

### Pod 启动失败

查看 Pod 事件和日志：

```bash
kubectl describe pod -n monitoring -l app=nvidia-gpu-exporter
kubectl logs -n monitoring -l app=nvidia-gpu-exporter --all-containers
```

### 权限问题

DCGM Exporter 需要特权访问 GPU 设备，确保：
- Pod 以 privileged 模式运行
- 挂载了 `/var/lib/kubelet/pod-resources` 路径
- ServiceAccount 具有正确的 RBAC 权限

### GPU 不可见

如果 DCGM Exporter 看不到 GPU：

1. 检查 NVIDIA Device Plugin 是否运行：
```bash
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
```

2. 检查节点标签：
```bash
kubectl get nodes -l nvidia.com/gpu.present=true
```

## 与 Grafana 集成

DCGM Exporter 的指标可以在 Grafana 中可视化。推荐使用以下 Dashboard：

- **NVIDIA DCGM Exporter Dashboard**：Dashboard ID 12239
- **NVIDIA GPU Metrics**：自定义 Dashboard

如果安装了本项目的 Grafana Chart，已包含预配置的 NVIDIA GPU 监控 Dashboard（`cm-grafana-NVIDIA.yaml`）。

## 卸载和清理

完全删除 DCGM Exporter：

```bash
# 卸载 Chart
helm uninstall dcgm-exporter -n monitoring
```

DCGM Exporter 不使用持久化存储，卸载后所有资源会被完全清除。

## 技术说明

### DaemonSet 调度

DCGM Exporter 使用 DaemonSet 并通过节点亲和性或节点选择器确保只在 GPU 节点上运行。

### 安全上下文

- **privileged**: true（需要访问 GPU 设备）
- **runAsNonRoot**: false
- **runAsUser**: 0（root 用户）

### 挂载路径

- `/var/lib/kubelet/pod-resources` - 用于获取 Pod GPU 资源分配信息
- `/var/run/nvidia-exporter` - NVIDIA 运行时数据

### Kube RBAC Proxy

使用 kube-rbac-proxy 在 DCGM Exporter 前提供身份验证层，增强安全性。

## 支持的 GPU

DCGM Exporter 支持以下 NVIDIA GPU 架构：
- Pascal (P100, P40, etc.)
- Volta (V100)
- Turing (T4, RTX series)
- Ampere (A100, A30, A10, etc.)
- Hopper (H100)

## 环境变量

DCGM Exporter 使用以下环境变量：
- `DCGM_EXPORTER_LISTEN`: 监听地址（默认 `:9400`）
- `DCGM_EXPORTER_KUBERNETES`: 启用 Kubernetes 模式（`true`）

## 更多信息

- [DCGM Exporter GitHub](https://github.com/NVIDIA/dcgm-exporter)
- [NVIDIA DCGM 文档](https://docs.nvidia.com/datacenter/dcgm/latest/)
- [Prometheus 官方文档](https://prometheus.io/docs/)


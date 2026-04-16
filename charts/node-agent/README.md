# Node Config Agent (绑核组件)

## 组件介绍

Node Config Agent 是一个 Kubernetes DaemonSet 组件，用于自动化配置节点的 CPU 管理策略和 kubelet 资源预留。

## 核心功能

- **CPU 绑定管理**: 监听节点 Annotation `cds-node/cpu-manager-policy` 并自动配置 CPU 管理策略
- **资源预留**: 为系统预留 2C 2G 资源，确保系统稳定性
- **自动部署**: 以 DaemonSet 形式在所有工作节点上运行
- **安全隔离**: 自动排除控制平面节点，仅在工作节点部署

## 部署方式

### 使用 Helm 安装

```bash
# 安装组件
./install.sh node-agent

# 或者批量安装
./install.sh --components node-agent,csi-oss,prometheus
```

### 验证安装

```bash
# 检查 Pod 状态
kubectl -n kube-system get pods -l app=node-agent

# 检查 DaemonSet
kubectl -n kube-system get daemonset node-agent

# 查看详细信息
kubectl -n kube-system describe daemonset node-agent
```

## 配置说明

该组件采用**硬编码配置**设计原则，所有参数均已固化，不允许用户自定义：

### 固定配置项

- **镜像**: `registry-cds.yun-paas.com/cds-eks/node-agent:v1.3`
- **资源预留**: CPU 2 核，内存 2Gi
- **目标 Annotation**: `cds-node/cpu-manager-policy`
- **部署节点**: 仅工作节点（自动排除控制平面节点）
- **权限模式**: 特权模式（privileged: true）
- **Host PID**: 启用（hostPID: true）

### 镜像更新支持

为了支持项目统一的镜像更新脚本，本组件遵循 `container.<container-name>.image` 配置规范：

```yaml
container:
  agent:
    image:
      repository: registry-cds.yun-paas.com/cds-eks/node-agent
      tag: v1.3
      pullPolicy: Always
```

使用镜像更新脚本：
```bash
./update-image.sh node-agent -c agent \\
  -i registry-cds.yun-paas.com/cds-eks/node-agent:v1.4 \\
  -n kube-system -k DaemonSet
```

### 宿主机路径映射

- `/etc/default/kubelet` → 容器内 `/host/etc/default/kubelet`
- `/var/lib/kubelet/cpu_manager_state` → 容器内 `/host/var/lib/kubelet/cpu_manager_state`

## 安全注意事项

⚠️ **重要提醒**：
- 组件运行在特权模式下，具有修改宿主机文件系统的权限
- 仅建议在受信任的环境中部署
- 生产环境使用前请充分测试

## 故障排除

### 常见问题

1. **Pod 无法启动**
   ```bash
   kubectl -n kube-system logs -l app=node-agent
   ```

2. **节点配置未生效**
   - 检查节点是否包含正确的 Annotation
   - 验证 kubelet 配置文件权限

3. **权限相关错误**
   - 确认集群 RBAC 配置正确
   - 验证 ServiceAccount 权限

### 日志查看

```bash
# 实时查看日志
kubectl -n kube-system logs -f -l app=node-agent

# 查看历史日志
kubectl -n kube-system logs -p -l app=node-agent
```

## 组件架构

```
Node Agent (DaemonSet)
├── ServiceAccount: node-agent
├── ClusterRole: node-agent (nodes get/list/watch)
├── ClusterRoleBinding: node-agent
└── Pod Template:
    ├── Host PID: Enabled
    ├── Privileged: True
    ├── Node Affinity: Exclude control-plane/master nodes
    └── Volume Mounts: Host filesystem access
```

## 版本信息

- **Chart 版本**: 1.0.0
- **应用版本**: 1.3
- **兼容性**: Kubernetes 1.16+

## 维护说明

如需更新组件，请联系系统管理员或参考项目维护文档。
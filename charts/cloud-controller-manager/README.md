# Cloud Controller Manager Helm Chart

This chart deploys Cloud Controller Manager on a Kubernetes cluster using the Helm package manager.

## Prerequisites

- Kubernetes 1.16+
- Helm 3+

## Configuration

The following table lists the configurable parameters of the cloud-controller-manager chart and their default values.

| Parameter                     | Description                                      | Default                                    |
|-------------------------------|--------------------------------------------------|--------------------------------------------|
| `image.repository`            | Image repository                                 | `registry-cds.yun-paas.com/cds-eks/eks-cloud-controller-manager` |
| `image.tag`                   | Image tag                                        | `v1.0.8`                                   |
| `image.pullPolicy`            | Image pull policy                                | `Always`                                   |
| `serviceAccount.create`       | Specifies whether a service account should be created | `true`                              |
| `serviceAccount.name`         | Name of the service account to create            | `cloud-controller-manager`                 |
| `rbac.create`                 | Specifies whether RBAC resources should be created | `true`                                  |
| `resources.requests.cpu`      | CPU resource requests                            | `100m`                                     |
| `resources.requests.memory`   | Memory resource requests                         | `100Mi`                                    |
| `env.CDS_ACCESS_KEY_ID`       | Access key ID for cloud provider                 | `""`                                       |
| `env.CDS_ACCESS_KEY_SECRET`   | Access key secret for cloud provider             | `""`                                       |
| `env.CDS_CLUSTER_ID`          | Cluster ID for cloud provider                    | `""`                                       |
| `env.CDS_OVERSEA`             | Oversea flag for cloud provider                  | `""`                                       |
| `env.CDS_API_SCHEMA`          | API schema for cloud provider                    | `""`                                       |
| `env.CDS_API_HOST`            | API host for cloud provider                      | `""`                                       |
| `env.CDS_LB_API_HOST`         | Load balancer API host for cloud provider        | `""`                                       |
| `env.CDS_VPC_ID`              | VPC ID for cloud provider                        | `""`                                       |

## Installation

To install the chart:

```bash
# Add the chart repository
helm repo add my-charts .

# Install the chart
helm install cloud-controller-manager charts/cloud-controller-manager -n kube-system --create-namespace
```

## Uninstallation

To uninstall/delete the chart:

```bash
helm uninstall cloud-controller-manager -n kube-system
```

## Values

By default, the chart uses values from `values.yaml`. You can customize the installation by providing your own values file:

```bash
helm install cloud-controller-manager charts/cloud-controller-manager -f my-values.yaml -n kube-system --create-namespace
```

## Notes

- The chart installs resources in the `kube-system` namespace
- Requires a Secret named `eks-secrets` containing access keys
- Requires a ConfigMap named `cds-properties` containing cluster configuration
- The cloud controller manager pods will be scheduled on control plane nodes
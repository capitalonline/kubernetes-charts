#!/bin/bash
# Sync GPU Operator v26.3.0 images to registry-cds.yun-paas.com/cds-eks
# Usage: bash sync-images.sh

set -euo pipefail

TARGET_REGISTRY="registry-cds.yun-paas.com/cds-eks"

IMAGES=(
  # gpu-operator (validator, operator, nodeStatusExporter)
  "nvcr.io/nvidia/gpu-operator:v26.3.0"
  # driver
  "nvcr.io/nvidia/driver:580.126.20"
  # driver manager
  "nvcr.io/nvidia/cloud-native/k8s-driver-manager:v0.10.0"
  # container toolkit
  "nvcr.io/nvidia/k8s/container-toolkit:v1.19.0"
  # device plugin & gfd
  "nvcr.io/nvidia/k8s-device-plugin:v0.19.0"
  # dcgm
  "nvcr.io/nvidia/cloud-native/dcgm:4.5.2-1-ubuntu22.04"
  # dcgm-exporter
  "nvcr.io/nvidia/k8s/dcgm-exporter:4.5.1-4.8.0-distroless"
  # mig-manager
  "nvcr.io/nvidia/cloud-native/k8s-mig-manager:v0.14.0"
  # gds (nvidia-fs)
  "nvcr.io/nvidia/cloud-native/nvidia-fs:2.27.3"
  # gdrcopy
  "nvcr.io/nvidia/cloud-native/gdrdrv:v2.5.1"
  # vgpu-device-manager
  "nvcr.io/nvidia/cloud-native/vgpu-device-manager:v0.4.2"
  # sandbox device plugin (kubevirt)
  "nvcr.io/nvidia/kubevirt-gpu-device-plugin:v1.5.0"
  # sandbox device plugin (kata)
  "nvcr.io/nvidia/cloud-native/nvidia-sandbox-device-plugin:v0.0.2"
  # cc-manager
  "nvcr.io/nvidia/cloud-native/k8s-cc-manager:v0.3.0"
  # node-feature-discovery
  "registry.k8s.io/nfd/node-feature-discovery:v0.18.3"
)

for src in "${IMAGES[@]}"; do
  # Replace source registry with target registry
  if [[ "$src" == nvcr.io/* ]]; then
    dst="${TARGET_REGISTRY}/${src#nvcr.io/}"
  elif [[ "$src" == registry.k8s.io/* ]]; then
    dst="${TARGET_REGISTRY}/${src#registry.k8s.io/}"
  else
    echo "SKIP: unknown registry in $src"
    continue
  fi

  echo "========================================"
  echo "SRC: $src"
  echo "DST: $dst"
  echo "========================================"

  docker pull "$src"
  docker tag "$src" "$dst"
  docker push "$dst"

  echo ""
done

echo "All images synced to ${TARGET_REGISTRY}."

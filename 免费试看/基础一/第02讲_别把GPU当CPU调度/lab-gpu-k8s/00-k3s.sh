#!/usr/bin/env bash
# 在 2 卡 GPU 机（Ubuntu 22.04，驱动已装）上起单节点 k3s
set -euo pipefail

nvidia-smi -L || { echo "先确认驱动可用：nvidia-smi 要能列出卡"; exit 1; }

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
mkdir -p ~/.kube && cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

kubectl wait --for=condition=Ready nodes --all --timeout=180s
echo "== 验证：节点 Ready；此时还没有 nvidia.com/gpu（还没装 Device Plugin）=="
kubectl get nodes
kubectl describe node | grep -c 'nvidia.com/gpu' || true

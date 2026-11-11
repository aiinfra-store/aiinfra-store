#!/usr/bin/env bash
# GPU Operator：一次装好 容器工具包 + Device Plugin + GFD 标签 + dcgm-exporter
# 驱动已在宿主机装好，所以 driver.enabled=false；k3s 的 containerd 路径要显式告诉 toolkit
set -euo pipefail
cd "$(dirname "$0")"

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null
helm repo update nvidia >/dev/null
helm upgrade --install gpu-operator nvidia/gpu-operator -n gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set toolkit.env[0].name=CONTAINERD_CONFIG \
  --set toolkit.env[0].value=/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl \
  --set toolkit.env[1].name=CONTAINERD_SOCKET \
  --set toolkit.env[1].value=/run/k3s/containerd/containerd.sock \
  --set toolkit.env[2].name=CONTAINERD_SET_AS_DEFAULT \
  --set-string toolkit.env[2].value=true \
  --wait --timeout 15m

echo "== 等 device plugin 上报资源 =="
until kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}' | grep -q '[1-9]'; do sleep 5; done

echo
echo "== 验证 1：operator 各组件 Running / Completed =="
kubectl get pods -n gpu-operator
echo
echo "== 验证 2：账本上出现 nvidia.com/gpu，数量 = 物理卡数 =="
kubectl describe node | grep -E '^\s+nvidia.com/gpu'
nvidia-smi -L | wc -l
echo
echo "== 验证 3：GFD 自动打的标签（型号 / 显存 / 卡数）=="
kubectl get node -o json | grep -oE '"nvidia.com/gpu\.(product|memory|count)": "[^"]+"'
echo
echo "== 验证 4：真起一个 CUDA Pod，日志应出现 Test PASSED =="
kubectl apply -f manifests/vectoradd.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/cuda-vectoradd --timeout=300s
kubectl logs cuda-vectoradd | tail -2

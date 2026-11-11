#!/usr/bin/env bash
# 建 3 节点 kind 集群，并给两个 worker 各「挂」2 张假 GPU（只是账本上的扩展资源）
set -euo pipefail
cd "$(dirname "$0")"

kind create cluster --config kind-config.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=180s

for n in gang-lab-worker gang-lab-worker2; do
  kubectl patch node "$n" --subresource=status --type=json \
    -p='[{"op":"add","path":"/status/capacity/nvidia.com~1gpu","value":"2"}]'
done

echo "等待 kubelet 把 capacity 同步到 allocatable ..."
until [ "$(kubectl get node gang-lab-worker2 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')" = "2" ]; do sleep 2; done

echo
echo "== 验证：每个 worker 应显示 nvidia.com/gpu: 2 =="
kubectl get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'

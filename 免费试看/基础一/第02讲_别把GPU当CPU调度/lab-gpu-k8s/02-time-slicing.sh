#!/usr/bin/env bash
# 虚拟化鸿沟：开 time-slicing → 账本 ×4 → 把槽位填满（每张物理卡挤 4 个 Pod）→ 全 Running，但各自只有 ~1/4 速度
set -euo pipefail
cd "$(dirname "$0")"

PHYS=$(nvidia-smi -L | wc -l)

echo "== 基线：只起 1 个 Pod，记下 matmul/s =="
kubectl apply -f manifests/share-pods.yaml
kubectl scale deploy/share --replicas=1
kubectl rollout status deploy/share --timeout=900s   # 首次拉 pytorch 镜像较慢
sleep 20
kubectl logs deploy/share --tail=2

echo
echo "== 开 time-slicing（replicas: 4）=="
kubectl apply -f manifests/time-slicing.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
until [ "$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable.nvidia\.com/gpu}')" = "$((PHYS * 4))" ]; do sleep 5; done

echo "== 验证 1：账本从 ${PHYS} 变成 $((PHYS * 4))，标签带 replicas / SHARED =="
kubectl describe node | grep -E '^\s+nvidia.com/gpu'
kubectl get node -o json | grep -oE '"nvidia.com/gpu\.(replicas|product)": "[^"]+"'

echo
echo "== 验证 2：起 $((PHYS * 4)) 个 Pod 把槽位填满 → 每张物理卡上正好挤 4 个，全部 Running =="
kubectl scale deploy/share --replicas=$((PHYS * 4))
kubectl rollout status deploy/share --timeout=300s
kubectl get pods -l app=share -o wide

sleep 30
echo
echo "== 验证 3：宿主机 nvidia-smi 按 gpu_uuid 数，每张卡上 4 个进程 =="
nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv
echo
echo "== 验证 4：每个 Pod 的 matmul/s ≈ 基线的 1/4 —— kubectl 里看不出来 =="
for p in $(kubectl get pods -l app=share -o name); do kubectl logs "$p" --tail=1; done

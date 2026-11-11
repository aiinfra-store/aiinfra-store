#!/usr/bin/env bash
# 可观测鸿沟：让 dcgm-exporter 吐出 PROF 指标 → 制造利用率虚高 → 看 Util 高、TENSOR_ACTIVE 低
set -euo pipefail
cd "$(dirname "$0")"

kubectl delete deploy share --ignore-not-found >/dev/null

kubectl -n gpu-operator create configmap metrics-config \
  --from-file=dcgm-metrics.csv=manifests/dcgm-metrics.csv --dry-run=client -o yaml | kubectl apply -f -
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge -p '{
  "spec":{"dcgmExporter":{
    "config":{"name":"metrics-config"},
    "env":[{"name":"DCGM_EXPORTER_COLLECTORS","value":"/etc/dcgm-exporter/dcgm-metrics.csv"}]}}}'
sleep 10
kubectl -n gpu-operator rollout status ds/nvidia-dcgm-exporter --timeout=300s

kubectl -n gpu-operator port-forward svc/nvidia-dcgm-exporter 9400:9400 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null' EXIT
sleep 3

scrape() { curl -s localhost:9400/metrics | grep -E '^DCGM_FI_(DEV_GPU_UTIL|DEV_POWER_USAGE|PROF_SM_ACTIVE|PROF_PIPE_TENSOR_ACTIVE)\{' | sed -E 's/\{.*gpu="([0-9]+)".*\} / gpu\1 /'; }

echo "== 验证 1：exporter 在吐指标（空闲时）=="
scrape
echo "（PROF 指标一行都没有 → 这张卡不支持 DCP 指标，或 csv 没生效：kubectl -n gpu-operator logs ds/nvidia-dcgm-exporter）"

echo
echo "== 验证 2：宿主机制造利用率虚高，40 秒后再抓 =="
FAKE=scripts/fake_busy.py
torchrun --standalone --nproc_per_node=2 "$FAKE" > /tmp/fake_busy.log 2>&1 &
FB=$!
sleep 40
scrape
kill $FB 2>/dev/null || true
tail -2 /tmp/fake_busy.log
echo
echo "读法：GPU1 的 GPU_UTIL 接近 100，但 PIPE_TENSOR_ACTIVE ≈ 0、功耗偏低 → 利用率虚高"

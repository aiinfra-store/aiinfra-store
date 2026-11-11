#!/usr/bin/env bash
# 清掉默认调度器那组 Pod，换 Volcano 成组调度，再验证「释放后整组接上」
set -euo pipefail
cd "$(dirname "$0")"

kubectl delete pod a-w0 a-w1 b-w0 b-w1 --ignore-not-found --now >/dev/null
kubectl apply -f 03-gang-jobs.yaml
sleep 20

echo "== 验证 1：一个任务 Running 2/2，另一个整组 Pending（不占卡）=="
kubectl get vcjob
kubectl get podgroup
kubectl get pods -o wide
echo
echo "== 验证 2：Pending 的原因是「组没凑齐」，不是半启动 =="
kubectl describe pod gang-b-worker-0 | grep -A1 FailedScheduling || true
echo
echo "== 验证 3：删掉 gang-a，gang-b 应整组起来 =="
kubectl delete vcjob gang-a
sleep 20
kubectl get vcjob
kubectl get pods -o wide

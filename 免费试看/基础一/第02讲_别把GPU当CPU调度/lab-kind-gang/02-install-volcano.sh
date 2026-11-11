#!/usr/bin/env bash
# 装 Volcano，并验证组件 + CRD 都在
set -euo pipefail

helm repo add volcano-sh https://volcano-sh.github.io/helm-charts >/dev/null
helm repo update volcano-sh >/dev/null
helm upgrade --install volcano volcano-sh/volcano --version 1.16.0 -n volcano-system --create-namespace --wait --timeout 10m

echo
echo "== 验证 1：三个组件 Running（admission / controllers / scheduler）=="
kubectl get pods -n volcano-system
echo
echo "== 验证 2：PodGroup / Job CRD 已注册 =="
kubectl get crd | grep -E 'podgroups|jobs.batch.volcano'
echo
echo "== 验证 3：默认队列存在 =="
kubectl get queue

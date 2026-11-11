#!/usr/bin/env bash
# 面试第二层：K8s 只记整数。把 worker 的账本改成「2 张卡 × 4 份」= 8，看 8 个 Pod 全 Running
# （等价于 time-slicing replicas: 4 的效果，物理卡并没有变多）
set -euo pipefail

kubectl delete vcjob --all --ignore-not-found >/dev/null
kubectl delete pod -l 'job in (a,b)' --now >/dev/null
kubectl delete pod -l app=share --now >/dev/null
kubectl wait --for=delete pod -l volcano.sh/job-name --timeout=120s >/dev/null 2>&1 || true
kubectl wait --for=delete pod -l app=share --timeout=120s >/dev/null 2>&1 || true
kubectl patch node gang-lab-worker --subresource=status --type=json \
  -p='[{"op":"replace","path":"/status/capacity/nvidia.com~1gpu","value":"8"}]'
until [ "$(kubectl get node gang-lab-worker -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')" = "8" ]; do sleep 2; done

for i in $(seq 0 7); do
  kubectl run "share-$i" --image=busybox:1.36 --restart=Never --labels=app=share \
    --overrides='{"spec":{"nodeName":"gang-lab-worker","terminationGracePeriodSeconds":1,"containers":[{"name":"c","image":"busybox:1.36","command":["sleep","3600"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}' >/dev/null
done
sleep 10

echo "== 验证：账本 8，8 个 Pod 全 Running —— kubectl 看不出它们在抢 2 张卡 =="
kubectl describe node gang-lab-worker | grep -E 'nvidia.com/gpu'
kubectl get pods -o wide -l app=share

# 复位账本，免得影响后面重做调度实验
kubectl delete pod -l app=share --now >/dev/null
kubectl patch node gang-lab-worker --subresource=status --type=json \
  -p='[{"op":"replace","path":"/status/capacity/nvidia.com~1gpu","value":"2"}]' >/dev/null

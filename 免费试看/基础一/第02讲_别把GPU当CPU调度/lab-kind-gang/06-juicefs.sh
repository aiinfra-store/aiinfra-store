#!/usr/bin/env bash
# 存储鸿沟：装 JuiceFS CSI → PVC 挂 /models → 新节点冷读 vs 命中缓存 → warmup
set -euo pipefail
cd "$(dirname "$0")"

kubectl delete pod --all --now >/dev/null 2>&1 || true
kubectl apply -f storage/backend.yaml
kubectl -n storage rollout status deploy/redis --timeout=300s

helm repo add juicefs https://juicedata.github.io/charts/ >/dev/null
helm repo update juicefs >/dev/null
# GitHub 下载偶尔 EOF，重试 3 次
for i in 1 2 3; do
  helm upgrade --install juicefs-csi-driver juicefs/juicefs-csi-driver --version 0.33.2 -n kube-system --wait --timeout 10m && break
  sleep 5
done

echo "== 验证 1：CSI controller / node 都 Running =="
kubectl get pods -n kube-system | grep juicefs-csi

kubectl apply -f storage/juicefs-pvc.yaml
kubectl wait --for=condition=Ready pod/trainer-0 --timeout=600s
echo
echo "== 验证 2：PVC Bound，Pod 里 /models 是 JuiceFS =="
kubectl get pvc juicefs-llm-weights
kubectl exec trainer-0 -- df -h /models

echo
echo "== 写一份 300MB 假权重（trainer-0 在 worker 上）=="
# 先删旧文件再写：实验后端 Redis 只有 1GB，反复覆盖写同一个文件，旧分片会一直挂在文件上把它撑满
kubectl exec trainer-0 -- rm -f /models/model-00001.safetensors
kubectl exec trainer-0 -- dd if=/dev/urandom of=/models/model-00001.safetensors bs=1M count=300 2>&1 | tail -1

trainer1() {
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata: { name: trainer-1 }
spec:
  nodeName: gang-lab-worker2
  terminationGracePeriodSeconds: 1
  containers:
  - name: trainer
    image: busybox:1.36
    command: ["sleep", "3600"]
    volumeMounts: [{ name: w, mountPath: /models }]
  volumes:
  - name: w
    persistentVolumeClaim: { claimName: juicefs-llm-weights }
EOF
  kubectl wait --for=condition=Ready pod/trainer-1 --timeout=300s >/dev/null
}

echo
echo "== 验证 3：worker2 第一次读（冷，要回源）=="
trainer1
kubectl exec trainer-1 -- sh -c 'time cat /models/model-00001.safetensors > /dev/null' 2>&1 | grep real

echo
echo "== 验证 4：重建 trainer-1 再读（命中节点本地缓存 /var/jfsCache）=="
kubectl delete pod trainer-1 --now >/dev/null
kubectl wait --for=delete pod/trainer-1 --timeout=120s >/dev/null || true
trainer1
kubectl exec trainer-1 -- sh -c 'time cat /models/model-00001.safetensors > /dev/null' 2>&1 | grep real

echo
echo "== 验证 5：warmup —— 生产上在训练 Pod 启动前对新节点执行 =="
# 只挑 worker2 上正在运行的 mount pod（旧的 mount pod 可能是 Completed，进不去）
MP=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=juicefs-mount \
  --field-selector spec.nodeName=gang-lab-worker2,status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
# mount pod 名是 juicefs-<节点>-pvc-<…>-<后缀>，它自己的挂载目录是 /jfs/pvc-<…>-<后缀>（/jfs 下可能残留旧目录，不能用 ls）
DIR="pvc-${MP##*-pvc-}"
kubectl -n kube-system exec "$MP" -- juicefs warmup "/jfs/$DIR/" 2>&1 | tail -1
kubectl -n kube-system exec "$MP" -- du -sh /var/jfsCache

#!/usr/bin/env bash
# 默认调度器：两个训练任务 A、B，各需 2 个 Worker × 2 卡；集群一共只有 4 张卡
# 交错提交（A-W0、B-W0、A-W1、B-W1），复现「各拿一半、互相等」
set -euo pipefail
cd "$(dirname "$0")"

kubectl create configmap worker-script --from-file=worker.sh --dry-run=client -o yaml | kubectl apply -f -

svc() {
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: job-$1 }
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector: { job: "$1" }
EOF
}

pod() { # job rank peer
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $1-w$2
  labels: { job: "$1" }
spec:
  hostname: $1-w$2
  subdomain: job-$1
  restartPolicy: Never
  terminationGracePeriodSeconds: 1
  containers:
  - name: trainer
    image: busybox:1.36
    command: ["sh", "/script/worker.sh"]
    env:
    - { name: PEER, value: "$1-w$3.job-$1.default.svc.cluster.local" }
    resources:
      limits: { nvidia.com/gpu: "2" }
    volumeMounts: [{ name: s, mountPath: /script }]
  volumes: [{ name: s, configMap: { name: worker-script } }]
EOF
}

svc a; svc b
pod a 0 1; pod b 0 1
sleep 3
pod a 1 0; pod b 1 0

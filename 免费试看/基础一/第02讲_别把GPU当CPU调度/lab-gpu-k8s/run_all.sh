#!/usr/bin/env bash
# 2 卡 GPU 机一键：k3s → GPU Operator → time-slicing → DCGM 利用率虚高 → NCCL 路径
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out
for s in 00-k3s 01-gpu-operator 02-time-slicing 03-dcgm 04-nccl-path; do
  echo; echo "########## $s ##########"
  ./"$s".sh 2>&1 | tee "out/$s.log"
done
tar czf "lab-gpu-k8s-out-$(hostname)-$(date +%m%d%H%M).tgz" out
echo "完成。日志在 out/ 目录，按 README 把数字写进作业。"

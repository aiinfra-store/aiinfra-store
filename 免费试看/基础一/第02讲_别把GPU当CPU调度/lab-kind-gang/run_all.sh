#!/usr/bin/env bash
# 笔记本一键跑完：调度死锁 → Volcano 修复 → 资源账本 → JuiceFS 存储
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out

step() { local name=$1; shift; echo; echo "########## $name ##########"; "$@" 2>&1 | grep -v 'WARNING: Kubernetes configuration' | tee "out/$name.log"; }

step 00-up ./00-up.sh
step 01-default-deadlock bash -c './01-default-deadlock.sh && sleep 40 && kubectl get pods -o wide && kubectl logs a-w0 | tail -2 && kubectl describe pod a-w1 | grep FailedScheduling'
step 02-install-volcano ./02-install-volcano.sh
step 03-gang ./03-gang.sh
step 05-ledger ./05-ledger.sh
step 06-juicefs ./06-juicefs.sh

echo
echo "全部完成，日志在 out/。清理：./99-down.sh"

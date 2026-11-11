#!/usr/bin/env bash
# 网络鸿沟（单机可做的部分）：同一个 AllReduce，强制换路径，看日志关键字和带宽
#   default  → 卡间直连（P2P / NVLink）或共享内存
#   socket   → 关掉 P2P 和共享内存，NCCL 只能走 NET/Socket（= 跨机没配好 RDMA 时的样子）
# 双机 RDMA 的验收见 README「网络 · 双机验收清单」
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p out

run() {
  local mode=$1; shift
  env "$@" LAB_MODE="$mode" NCCL_DEBUG=INFO \
    torchrun --standalone --nproc_per_node=2 scripts/allreduce_bw.py > "out/nccl-$mode.log" 2>&1
  echo "---- $mode ----"
  grep -E 'NCCL INFO (Channel 00/0|NET/|Using network)' "out/nccl-$mode.log" | head -4
  grep -E '^\[' "out/nccl-$mode.log"
}

run default
run socket NCCL_P2P_DISABLE=1 NCCL_SHM_DISABLE=1 NCCL_SOCKET_IFNAME=lo

echo
echo "读法：default 的 Channel 行是 via P2P/IPC 或 SHM；socket 出现 NET/Socket，busbw 掉一个量级"

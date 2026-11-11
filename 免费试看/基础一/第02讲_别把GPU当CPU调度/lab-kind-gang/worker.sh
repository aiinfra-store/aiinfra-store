# 模拟 NCCL 建组：rank0 一直等到 rank1 能被解析才开始「训练」
# 由 ConfigMap 挂进容器；PEER 由环境变量传入
i=0
until nslookup "$PEER" >/dev/null 2>&1; do
  i=$((i+1))
  echo "[$(hostname)] NCCL rendezvous: waiting for $PEER ... ${i}0s (GPU 已占住，没有在算)"
  sleep 10
done
echo "[$(hostname)] all ranks joined, training started"
while true; do echo "[$(hostname)] step ok"; sleep 10; done

# lab-gpu-k8s · 真机实验：在一台 2 卡 GPU 机上，把第二讲的虚拟化 / 可观测 / 网络路径搭一遍

> 特训课第一期眼下 GPU 暂时没有资源，讲义里先讲原理、步骤和判断标准；真机实战后面找时间补上，到时可以照着讲义第十一部分复现。

环境：1 台 **2 卡** GPU 机（Ubuntu 22.04，驱动已装，`nvidia-smi` 可用，宿主机有 Python + PyTorch，需要整机或虚拟机，普通容器实例装不了 k3s）。全程约 1 小时。

> DCGM 的 PROF 指标（`SM_ACTIVE` / `PIPE_TENSOR_ACTIVE`）只有数据中心卡支持（如 V100 / A10 / L20 / A100 / H100），消费卡（如 3090 / 4090）读不到。

```bash
chmod +x *.sh && ./run_all.sh        # 或按编号逐个跑
```

| 脚本 | 搭什么 | 验证什么（看到这个才算成） |
|---|---|---|
| `00-k3s.sh` | 单节点 k3s | 节点 Ready；此时还没有 `nvidia.com/gpu` |
| `01-gpu-operator.sh` | GPU Operator（toolkit + Device Plugin + GFD + dcgm-exporter） | 账本出现 `nvidia.com/gpu: 2`；GFD 标签有型号/显存；vectoradd 日志 `Test PASSED` |
| `02-time-slicing.sh` | time-slicing `replicas: 4` | 账本 2 → 8；标签 `nvidia.com/gpu.replicas=4`；副本调到 8 个把槽位填满（每张卡 4 个），全 Running，各自 matmul/s ≈ 基线 1/4 |
| `03-dcgm.sh` | dcgm-exporter 自定义指标（含 PROF） | 利用率虚高时 GPU1：`GPU_UTIL≈100`、`PIPE_TENSOR_ACTIVE≈0` |
| `04-nccl-path.sh` | 同一 AllReduce 强制换路径 | default 日志 `via P2P/...`；socket 日志 `NET/Socket`，busbw 掉一个量级 |

> 脚本按官方文档编写，不同版本的环境可能略有差异；第一次跑请留意 `01` 的 k3s containerd 路径（GPU Operator 版本不同可能是 `config.toml` 或 `config.toml.tmpl`）。

## 邻居对照实验（讲义第十一部分实验 B：3A / 3B，不需要 K8s）

```bash
# 3A 同卡邻居：先测 baseline，再让 noisy 和 victim 挤在 GPU0 上
python3 scripts/neighbor_demo.py --mode baseline --kind d2d
CUDA_VISIBLE_DEVICES=0 python3 scripts/neighbor_demo.py --mode noisy  --kind d2d --seconds 5 &
CUDA_VISIBLE_DEVICES=0 python3 scripts/neighbor_demo.py --mode victim --kind d2d

# 3B 跨卡邻居：GPU0 测主机→显卡拷贝，GPU1 同时也在拷
python3 scripts/neighbor_demo.py --mode baseline --kind h2d
CUDA_VISIBLE_DEVICES=1 python3 scripts/neighbor_demo.py --mode noisy  --kind h2d --seconds 5 &
CUDA_VISIBLE_DEVICES=0 python3 scripts/neighbor_demo.py --mode victim --kind h2d
```

判断标准：3A 的 victim 带宽预期接近 baseline 的一半；3B 掉多少取决于 `nvidia-smi topo -m` 里两张卡的关系，PIX / PXB 掉得最多，NODE / SYS 可能只掉一点。

## 网络 · 双机验收清单（需 2 台带 IB/RoCE 网卡的机器）

| # | 命令 | 合格标准 |
|---|---|---|
| 1 | `ibv_devices` / `ibstat` | 能列出 `mlx5_*`，`State: Active`，`Rate` 与网卡标称一致 |
| 2 | A: `ib_write_bw -d mlx5_0` · B: `ib_write_bw -d mlx5_0 <A的IP>` | 带宽接近网卡标称（如 200Gb/s ≈ 23 GB/s） |
| 3 | `lsmod \| grep nvidia_peermem` | 有输出 → GPUDirect RDMA 内核模块已加载 |
| 4 | `kubectl describe node \| grep rdma/` | 出现 `rdma/rdma_shared_device_a`（装了 RDMA 设备插件 / Network Operator） |
| 5 | 训练 Pod 日志 `grep NET/` | `NET/IB : Using [0]mlx5_0`，Channel 行 `via NET/IB/0/GDRDMA` |
| 6 | nccl-tests `all_reduce_perf -b 1G -e 1G -g 8`（跨两机） | busbw 接近网卡总带宽；出现 `NET/Socket` 即不合格 |

## 作业里要填的数字

从 `out/` 的日志里找到这几组数字，写进作业（对应讲义第十一部分）：实验 F 里 P2P 与 Socket 两种路径的 busbw、实验 D 里 time-slicing 前后的 matmul/s、实验 B 里 3A / 3B 的带宽对比、实验 E 里 DCGM 抓到利用率虚高时的三个读数。

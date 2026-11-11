"""2 卡 AllReduce 带宽：配合 NCCL 环境变量，看「走哪条路」和「快多少」。"""
import os
import time

import torch
import torch.distributed as dist

dist.init_process_group("nccl")
rank = dist.get_rank()
world = dist.get_world_size()
torch.cuda.set_device(rank)

x = torch.ones(256 * 1024 * 1024 // 4, device="cuda")  # 256 MiB
for _ in range(3):
    dist.all_reduce(x)
torch.cuda.synchronize()

iters = 10
t = time.time()
for _ in range(iters):
    dist.all_reduce(x)
torch.cuda.synchronize()
dt = (time.time() - t) / iters

# NCCL busbw 口径：2*(n-1)/n * size / time
busbw = 2 * (world - 1) / world * x.numel() * 4 / dt / 1e9
if rank == 0:
    mode = os.environ.get("LAB_MODE", "default")
    print(f"[{mode}] allreduce 256MiB  time={dt*1000:.1f}ms  busbw={busbw:.1f} GB/s", flush=True)
dist.destroy_process_group()

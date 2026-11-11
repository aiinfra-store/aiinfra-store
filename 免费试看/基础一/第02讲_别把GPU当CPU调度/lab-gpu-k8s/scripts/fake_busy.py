import os, time, torch
import torch.distributed as dist

rank = int(os.environ["LOCAL_RANK"])
torch.cuda.set_device(rank)
dist.init_process_group("nccl")

x = torch.randn(4096, 4096, device="cuda")
step = 0
t0 = time.time()
# ~45s is enough for screen recording
deadline = t0 + float(os.environ.get("FAKE_BUSY_SECONDS", "45"))

while time.time() < deadline:
    if rank == 0:
        time.sleep(0.4)
    dist.all_reduce(x)
    step += 1
    if rank == 0 and step % 10 == 0:
        elapsed = time.time() - t0
        print(
            f"steps={step}  elapsed={elapsed:.1f}s  steps/s={step/elapsed:.2f}",
            flush=True,
        )

if rank == 0:
    elapsed = time.time() - t0
    print(
        f"DONE steps={step}  elapsed={elapsed:.1f}s  steps/s={step/max(elapsed,1e-6):.2f}",
        flush=True,
    )

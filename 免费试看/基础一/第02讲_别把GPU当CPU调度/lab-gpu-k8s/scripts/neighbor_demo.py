import argparse, time, torch

# kind=d2d: copy inside one GPU's memory  -> contends for that GPU's memory bandwidth / SMs
# kind=h2d: pinned host -> GPU copy       -> contends for PCIe uplink / host memory


def make_buffers(kind, mib):
    n = mib * 1024 * 1024 // 4
    dst = torch.empty(n, device="cuda", dtype=torch.float32)
    if kind == "h2d":
        src = torch.empty(n, dtype=torch.float32, pin_memory=True)
    else:
        src = torch.empty_like(dst)
    return src, dst


def bandwidth_gbps(kind, seconds):
    src, dst = make_buffers(kind, 256)
    for _ in range(5):
        dst.copy_(src, non_blocking=True)
    torch.cuda.synchronize()
    n = 0
    t0 = time.time()
    while time.time() - t0 < seconds:
        dst.copy_(src, non_blocking=True)
        torch.cuda.synchronize()
        n += 1
    dt = time.time() - t0
    bytes_moved = n * src.numel() * 4
    return bytes_moved / dt / 1e9, n, dt


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["baseline", "victim", "noisy"], required=True)
    p.add_argument("--kind", choices=["d2d", "h2d"], default="d2d")
    p.add_argument("--gpu", type=int, default=0)
    p.add_argument("--seconds", type=float, default=3.0)
    args = p.parse_args()
    torch.cuda.set_device(args.gpu)

    if args.mode == "noisy":
        print(f"[noisy] kind={args.kind} GPU{args.gpu} hammering copies", flush=True)
        src, dst = make_buffers(args.kind, 512)
        t0 = time.time()
        while time.time() - t0 < max(args.seconds + 2.0, 6.0):
            dst.copy_(src, non_blocking=True)
        torch.cuda.synchronize()
        print("[noisy] DONE", flush=True)
        return

    gbps, n, dt = bandwidth_gbps(args.kind, args.seconds)
    print(
        f"[{args.mode}] kind={args.kind} GPU{args.gpu}  copy_bw={gbps:.2f} GB/s  iters={n}  time={dt:.2f}s",
        flush=True,
    )


if __name__ == "__main__":
    main()

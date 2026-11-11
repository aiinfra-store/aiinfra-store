# lab-kind-gang · 笔记本 kind 模拟：调度死锁 → Volcano → 资源账本 → JuiceFS

配套讲义：`第02讲_别把GPU当CPU调度.md`（实验一到实验四）。

环境：macOS / Linux，Docker（Docker Desktop 或 Colima，给 4 核 6G、磁盘余量 ≥ 10G）+ `kind` + `kubectl` + `helm`。不需要 GPU。

开始前先按讲义实验一的第一到第三步准备好 Docker、调高 inotify 上限、装好工具。inotify 不调的话，JuiceFS 的 CSI 插件会报 `too many open files` 并反复重启。

## 两种用法

**一键跑完**：

```bash
chmod +x *.sh
./run_all.sh                        # 约 20~30 分钟（首次拉镜像最慢），日志在 out/
./99-down.sh                        # 清理：删除 gang-lab 集群
```

**照着讲义一步步做**：讲义里每一步要创建的文件，这里都已经按同样的目录放好（`manifests/`、`storage/`），可以直接用，也可以自己照着讲义重新敲一遍再对照。

## 脚本

| 脚本 | 搭什么 | 看到这个才算成（本机实测输出） |
|---|---|---|
| `00-up.sh` | kind 3 节点；给 2 个 worker 账本写 `nvidia.com/gpu: 2` | `gang-lab-worker 2` / `gang-lab-worker2 2` |
| `01-default-deadlock.sh` | 默认调度，交错提交 A-W0 B-W0 A-W1 B-W1（各 2 卡） | `a-w0 Running` `a-w1 Pending` `b-w0 Running` `b-w1 Pending`；事件 `2 Insufficient nvidia.com/gpu`；a-w0 日志 `waiting for a-w1` |
| `02-install-volcano.sh` | helm 装 Volcano | admission / controllers / scheduler Running；`podgroups.scheduling.volcano.sh` CRD；`default` 队列 |
| `03-gang.sh` | 两个 `minAvailable: 2` 的 Volcano Job | `gang-a Running 2` `gang-b Pending`；PodGroup `Inqueue`；事件 `pod group is not ready, 2 Pending, 2 minAvailable`；删 gang-a 后 `gang-b Running 2` |
| `05-ledger.sh` | 把账本 2 改成 8（≈ time-slicing replicas: 4） | 8 个各要 1 卡的 Pod 全 Running |
| `06-juicefs.sh` | Redis 后端 + JuiceFS CSI + PVC + 训练 Pod | PVC `Bound`；`df` 显示 `JuiceFS:llm-weights`；跨节点冷读 0.7~3s → 命中缓存 0.2~0.5s（多次实测）；`warmup cache: 1 files (300 MiB bytes)` |

`out/` 里是本机实测的完整日志，可以拿来和自己的输出对照。

## 文件

```text
kind-config.yaml            # 实验一：三节点集群配置
manifests/
├── gpu-2.json              # 实验一：给节点登记 2 张假 GPU 的补丁
├── kind-demo.yaml          # 1 个控制面 + 1 个 worker 的小集群配置，可单独练习建集群、删集群
├── deadlock/               # 实验二：默认调度复现死锁（训练脚本、headless Service、4 个 Worker Pod）
├── gang/                   # 实验二：Volcano 成组调度（gang-a、gang-b）
└── ledger/                 # 实验四：账本改成 8、复位成 2、8 副本 Deployment
storage/
├── backend.yaml            # 实验三：Redis 后端
├── juicefs-pvc.yaml        # 实验三：Secret + StorageClass + PVC + trainer-0
└── trainer-1.yaml          # 实验三：另一个节点上的训练 Pod
worker.sh                   # 01-default-deadlock.sh 用的训练脚本（和 manifests/deadlock/0-train-script.yaml 内容相同）
03-gang-jobs.yaml           # 03-gang.sh 用的两个 Volcano Job（和 manifests/gang/ 作用相同，只是打印的日志文字略有不同）
```

## 说明

- 「假 GPU」只是节点账本上的扩展资源：调度器只认这个数字，所以调度行为和真卡完全一致；容器里当然没有卡。
- `worker.sh` 用 DNS 解析模拟 NCCL 建组：同组的另一个 Worker 没起来（没有 IP），rank0 就一直等。
- JuiceFS 实验里 Redis 一身二用（db1 元数据、db2 数据），上限 1 GB。重做存储实验时先删旧文件再写，脚本里已经这样做了；反复覆盖写同一个文件会把 Redis 撑满。生产换 S3/OSS 只改 `storage/juicefs-pvc.yaml` 里 Secret 的 `storage` / `bucket`，再加 `access-key` / `secret-key`。
- 常见坑：Docker 磁盘满会表现为 `ImagePullBackOff ... no space left on device`，先 `docker builder prune`；GitHub 下载 helm chart 偶发 `EOF` 或 `context deadline exceeded`，重试即可（`06-juicefs.sh` 已自动重试）。
- 更多问题见讲义附录 B。

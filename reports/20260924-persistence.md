# 2026-09-24 Pennyroyal 持久缓存验证

## 已证明的核心结果

在本机 WSL2 / RTX PRO 6000 96GB、300W / 64GB RAM 上，固定 v2.5.1 镜像加两处本地隔离修复，12GiB HiCache + buffered NIXL 能恢复被 GPU 淘汰的200K prefix，也能跨正常server restart恢复。FR-Spec、online FP8均关闭。当前还在追加正确性与更长context测试，本报告后续章节持续更新。

| 项目 | Primitive 已有基线 | Pennyroyal 修复后250K配置 |
|---|---:|---:|
| 冷200K TTFT |20.87s|首次25.21s；后续不同200K 20.73–21.12s|
| 冷prefill（server forward） |9.68K tok/s|首次8.12K；后续9.73–9.93K tok/s|
| 热200K TTFT |0.916s|0.941s；重复0.737–0.815s|
| 首次热prefix复用 |195200/200304（97.45%）|199936/200304（99.82%）|
| ABCDA最后A |0复用，21.07s|200256/200304（99.98%），4.202s|
| restart后首次A |0复用，20.88s|200256/200304，4.136s|
| restore来源 |无持久缓存|storage_nixl；GPU/host命中计数为0|
| 128-token decode样本 |约111–134tok/s|本轮约118–156tok/s，非全负载保证|
| PLE |26.82GiB NVFP4量化常驻|47.68GiB FP8磁盘表，NVMe按需读取|
| 容器内存 |既有部署约35GiB|28GiB硬上限；anon约5.5+shmem约12.76GiB，其余文件页缓存|
| GPU显存 |既有基线约92GB|修复轮资源采样详见resources.jsonl，约84–86千MiB|
| swap |禁用|容器memory.swap.max=0，采样current=0|
| 运维复杂度 |现有成熟部署|两处本地源码overlay、NIXL磁盘目录、namespace与磁盘预算管理|

冷请求仍要约21秒；第一次使用还存在额外开销。磁盘恢复相比Primitive冷重算节省约16.7–16.9秒（约80% TTFT），相对GPU热命中仍慢数秒。decode未证明稳定超过150tok/s，迁移价值来自持久恢复而非decode。

## 测试口径与证据

- 输入沿用Primitive原始200K prompt；B/C/D改变最前端以破坏前缀命中。A+suffix为200304tokens，输出固定128tokens，temperature0.6/seed42，thinking关闭。
- `fixed-A-after-BCD.json`：200256 storage cached / prefetched / load_back tokens；server tail prefill0.291s；host→GPU load-back 0.090s、2950459424bytes。
- `fixed-A-after-restart.json`：同样200256 storage tokens；tail prefill0.471s；load-back0.159s。该计时不包括全部磁盘查询/预取/排队，不可将0.159s声称为完整恢复耗时；用户可见TTFT为4.136s。
- restart在停止后执行sync及Linux drop_caches=1；前后namespace一致。请求期间cgroup块设备读取增加2924007424bytes（约2.72GiB），说明实际从持久文件读取，并非仅保留GPU或Linux页缓存。
- 正常stop/restart通过不等于断电一致性、Windows重启、磁盘故障已验证。
- 数据：`../results/fixed-*.json`、同名前后Prometheus快照、`../../logs/resources.jsonl`、`fixed-before-restart.log`及`fixed-restart-full.log`。
- 不同runtime、主权重量化、PLE模式并不完全相同，此表评估实用结果，不能单独归因为GPU、WSL或某个kernel。

## 失败配置和必要修复

1. 默认cudaHostRegister在真实Mamba transfer kernel下触发CUDA非法访问。torch-pinned本地overlay通过20轮真实kernel预检。不是CUDA IPC invalid-resource-handle问题。
2. 4GiB HiCache不足以可靠恢复本测试的混合状态；ABCDA缓存0。
3. 12GiB O_DIRECT还创建约14.07GiB Mamba双向bounce区，Windows低内存保护停机。不是OOM，也不应靠swap掩盖。
4. 12GiB buffered消除该中转区，但原版NIXL存在性检查漏算两个sibling状态，预取线程退出，HTTP仍healthy。`hicache_nixl.py`本地overlay按完整component names计数，与实际读写描述符保持一致；没有绕过缺失状态检查。

原始失败结果保留为A-*和12g-*，修复后结果为fixed-*。本机成功是“固定上游+本地修复”的证据，不能声称原版镜像在WSL上直接开箱通过。差异见references/*.patch。

## 内容正确性

独立200K prompt首/中/尾包含随机标记。修复后冷/热回答正确；E/F/G淘汰后storage恢复200064/200111tokens，三处回答仍完全正确。正常停止、释放文件页缓存并重启后，storage恢复200064/200111tokens，三个随机标记仍完全正确；完整回答耗时3.588s（非TTFT）。对应fixed-quality-restart.json。该测试检验跨位置内容恢复，不是全面中文coding能力评测。

## 缓存空间与内存补充

按同一目录`du -sb`差值，fixed新namespace首个200K cold后新增约3.735GiB；完成四个不同200K session A/B/C/D后新增约15.056GiB。GPU被淘汰不会立刻删除这些磁盘文件。该数字包含KV和必要混合状态文件，受生成长度、状态快照与后续写入影响，不是固定每token磁盘公式。后续速度矩阵产生更多独立prefix，因此总目录大小远高于4session结果。

修复轮250K GPU资源采样约84942–86270MiB；固定28GiB cgroup上限包含可回收文件页缓存，空闲一段时间实测降到约19.26GiB。不能把28GiB当成全部不可回收匿名内存。PLE47.68GiB文件不是整表RAM常驻；按需读入的PLE页和NIXL页共享文件缓存预算，无法从本次cgroup汇总中精确拆分独立PLE驻留RAM，因此该项标记为未单独测量。

所有容器swap采样0；WSL全局约78MiB既有swap不是本容器新增swap。memory.events的max为内存上限回收事件，不等于OOM；本轮oom/oom_kill均0。停止时的CancelledError日志与主动shutdown一致，不能与运行中的prefetch线程异常混淆。

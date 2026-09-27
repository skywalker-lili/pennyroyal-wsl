# 验证发现（未完成最终判断）

## 4GiB主机缓存

冷200K实测TTFT20.60–20.80s，server prefill约9.91–10.10K tok/s，decode约135–157tok/s。热请求199936/200304cached，TTFT1.30s。
ABCDA末次A却为0cache、TTFT20.67s。日志明确报告缺失Mamba状态文件，hybrid prefetch在3456-token边界被丢弃。不能把这个配置称作已解决eviction。

源码UnifiedRadixCache中，host内存分配失败会尝试evict_host，仍失败则截短预取；Mamba是all-or-nothing状态，缺边界文件就必须丢弃。小host池208256tokens与GPU池300032tokens缺少恢复周转空间是待验证原因。

## 12GiB主机缓存首次尝试

O_DIRECT下，Mamba stride不满足页对齐，NIXL回退到bounce buffers。固定STORAGE_BATCH_SIZE=128，为每个方向预留128份大Mamba状态，中转区约14GiB且不计入--hicache-size显示值。启动时Windows可用物理内存低于6GiB，保护脚本停止了服务；未发生OOM，不应通过增加分页文件掩盖此问题。

## 当前候选

保持12GiB HiCache，采用已存在的NIXL use_direct_io=false选项，以普通文件IO允许Mamba zero-copy路径，避免巨型bounce区。独立4MiB WRITE和新进程READ验证通过，整模型验证待完成。PLE依旧是独立的NVMe FP8 reader，未改为RAM或改变量化。

Buffered prefix文件可能命中Linux页缓存；必须将NIXL storage来源计数和真实块设备读取量区分。重启实验在服务停止后释放文件页缓存，以验证实际持久文件恢复。它不是断电/文件系统损坏测试。

这不需要修改NIXL batch常量；唯一runtime源码overlay仍是WSL torch-pinned host allocator。FR-Spec和online FP8保持关闭。

## 12GiB buffered：真实线程故障（已完成的失败实验）

200K cold TTFT 25.27s（首次），后续不同200K冷请求20.77–20.97s，prefill9.80–9.90K tok/s。warm199936/200304缓存，TTFT0.952s。ABCDA最后A缓存0、TTFT21.875s；restart后缓存0、TTFT21.737s。不能声称持久化有效。

确切错误为 `ValueError: Pool mamba exposed 4 component names for multiplier 2`，发生在NIXL batch_exists_v2，导致prefetch_thread_func退出。HTTP仍然healthy，因此仅健康检查不足。写入/读取使用4个组件，但存在性检查的旧计数仅算temporal+conv，漏掉slot_sibling_specs。本地第二个独立overlay修复计数，让存在性查询与真实读写描述符一致；仍保持完整性检查，未跳过缺失组件。补丁后的整模型复测进行中。

200K三位置随机标记在重启前冷/热和重启后均准确，但重启后是冷重算，不能将此归为cache恢复正确性证据。原始质量结果 quality-before.json / quality-after.json 保留。

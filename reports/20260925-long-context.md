# 262K / 384K / 490K容量探索

这是独立524288 context、YaRN factor2候选，KV总池524288、12GiB HiCache、28GiB容器RAM上限、nativeNEXTN3、FR关闭。**默认恢复250K原生配置。** 不能把本表与250K标准速度矩阵混作同一配置。

| 输入tokens | cold TTFT | server prefill tok/s | cold decode tok/s | warm cached | warm TTFT |
|---:|---:|---:|---:|---:|---:|
|262005|33.43s|8010|135.7|261952|1.863s|
|383987|50.46s|7784|130.3|383936|1.494s|
|约490000|未完成|不报告整体速度|未测得|未完成|未测得|

前两档各一次cold/warm，固定128输出，只证明容量和即时GPU reuse；未验证其ABCDA/restart或复杂内容正确性。不能把200K持久恢复结果外推到384K。

490K第一次触发90s读超时；重试使用新随机前缀、150s socket及240s进程界限，随后因为显存/主机内存压力停止该候选。采样GPU97372MiB已用、仅67MiB空闲，Windows可用约6.24–6.27GiB，后段prefill下降至约988–991tok/s。cgroup swap0、oom/oom_kill0；未造成WSL崩溃。不能仅凭显存接近满载认定已证实WDDM paging，未采集相应直接证据。

490K不合格，不建议默认启用524K配置。将来若确需490K，可独立评估更小prefill chunk与更多显存余量；本轮不通过延长等待或提高内存上限掩盖容量压力，也不调整精度追求通过。

证据：logs/long-90s-timeout.json、long-sequence.json、long-context-pressure.log、resources.jsonl；benchmarks/results/long-262000-*、long-384000-*。失败容器保留flash-next-pennyroyal-524k-pressure。没有490K完整成功结果，也没有其重启恢复证明。

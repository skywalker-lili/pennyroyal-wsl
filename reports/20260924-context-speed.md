# 与Primitive标准对齐的32K/64K/128K/248K速度测试

完成12/12正式请求和1次1024token预热。运行的是已验证250000 context配置，未切换长context/YaRN。每档3轮串行、512输出、temperature0.6、top_p0.95、seed42+trial、thinking关闭、ignore_eos=true。prompt生成函数逐字沿用Primitive：开头唯一UUID、Neutral filler text重复、末尾HTTP streaming教程要求；服务端tokenize后逼近相同档位。所有轮cache命中0，单请求计数隔离通过，没有OOM。

| 输入档位 | Primitive TTFT s | Penny TTFT s | Primitive prefill tok/s | Penny prefill tok/s | Primitive decode tok/s | Penny decode tok/s（范围） |
|---|---:|---:|---:|---:|---:|---:|
|32,768|2.723|3.053|12204|11471|115.4|128.2（124.7–131.9）|
|65,536|5.699|6.029|11685|11345|125.0|125.3（125.1–130.9）|
|131,072|11.963|12.547|11086|10831|115.8|118.4（81.8–120.6）|
|248,000|27.882|26.255|8987|9739|114.2|119.6（79.1–133.0）|

均为每档三轮中位数；三次样本量有限，不作为显著性结论。128K一轮decode为81.8tok/s、248K一轮为79.1tok/s，应保留该波动，不能宣称稳定超过120或150tok/s。本轮未隔离波动根因，可能需后续结合MTP接受率、磁盘写回和系统调度调查；不凭此猜定原因。

计时沿用Primitive标准：TTFT为提交到首个非空文字；客户端decode=(completion_tokens−1)/(elapsed−TTFT)；prefill tok/s为实际input/server prefill阶段秒数。SGLang使用per_stage_req_latency(prefill_forward)，vLLM用request_prefill_time，两框架内部计时边界可能不完全相同，跨框架以TTFT更直观。SGLang未找到对应独立decode阶段指标，server_decode保持null，不能捏造；客户端decode已完整测量。

该四档使用中性重复填充，与200K prefix-cache测试的coding prompt不同；不能混为同一速度样本。512输出对齐原速度矩阵，128输出只用于原缓存复用实验。具体算法由Primitive benchmark-context-speed.py复制后仅适配端口、tokenize路由和metrics，无读取其认证密钥。

原始结果：[20260924T201237Z-context-speed.json](../results/20260924T201237Z-context-speed.json)；同名前后metrics全保留。脚本：../scripts/benchmark-context-speed.py。原Primitive基线：primitive-ai/benchmarks/reports/20260923-context-speed.md；该表是历史实测，未在本轮重启Primitive重新跑。

缓存命中/ABCDA/restart完整对照另见[持久缓存报告](20260924-persistence.md)。

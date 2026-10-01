# Pennyroyal on Windows WSL2

This is a patch for running [Pennyroyal](https://github.com/jpezzulli/sglang-rtxpro6000) Flash-Next inside Windows WSL2. It is not an installer, and it is not a fork of the model. Weights, the container image, and the upstream runtime stay in the original project. This tree adds the WSL-specific overlays and the Windows start/stop scripts that were needed to keep that runtime alive on WSL.

It was run against one pinned image, not against upstream `latest` and not against a floating version tag:

`ghcr.io/jpezzulli/sglang-rtxpro6000@sha256:76258532b1c01f7583fbe951f90b80903db931030291db9db4e5a68b28567866`

Upstream documents that release as `pennyroyal-v2.5.1` and the tag `ghcr.io/jpezzulli/sglang-rtxpro6000:v2.5.1`. Pull the digest above. Do not assume the tag still points at this digest.

The WSL run that these files describe used a 250,000-token context and a 12 GiB host cache. That is a smaller profile than upstream's 524,288-token / 32 GiB HiCache recipe. Speed numbers and the machine they were measured on are in [Measured on one machine](#measured-on-one-machine). A 490,000-token prompt failed on that machine. That does not say the upstream long-context recipe is wrong on bare metal.

No path in this repository is a machine path. The checkout can live on any drive. Weights and caches cannot.

## What you need

- Windows with WSL2, and an NVIDIA driver that can hand the GPU to WSL. See the [CUDA on WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/index.html).
- One GPU in the RTX PRO 6000 96 GB class. The image is built for SM120.
- Docker Engine and the NVIDIA Container Toolkit inside the WSL distro, not merely Docker Desktop on Windows. `docker info` must succeed as root in that distro before the model will start.
- Disk on the WSL filesystem (ext4), not on `/mnt/c` or `/mnt/d`. The checkpoint is about 126 GiB. The prepared PLE overlay is about 48 GiB more. Cache and NIXL need more free space on that same filesystem.

## 1. Download the weights

Weights are not in this repository. Download the checkpoint Pennyroyal v2.5.1 documents, at the revision it pins.

Model card: <https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4>

Upstream instructions: [BUILD.md — Reference and measured checkpoints](https://github.com/jpezzulli/sglang-rtxpro6000/blob/pennyroyal-v2.5.1/BUILD.md#reference-and-measured-checkpoints)

Run this inside WSL. Replace the destination with a directory on the distro's own disk:

```bash
hf download RadixArk/Qwen3.8-Flash-Next-NVFP4 \
  --revision 7b719225242aacd3dbd3f9407468c2ee9a9d2594 \
  --local-dir /path/to/RadixArk-Qwen3.8-Flash-Next-NVFP4
```

`/path/to/...` is a placeholder. Do not download onto `/mnt/c` or `/mnt/d`. A Windows drive mounted into WSL is the wrong disk for these files.

The 27B checkpoint in that same upstream section is not used by this patch.

## 2. Prepare the NVMe PLE overlay

This patch runs Flash-Next with the PLE table on disk, which is what kept the WSL memory budget workable. The image already contains the reader. You still have to build the overlay from the checkpoint you just downloaded.

Upstream write-up: [NVME-PLE.md](https://github.com/jpezzulli/sglang-rtxpro6000/blob/pennyroyal-v2.5.1/NVME-PLE.md)

The container guide's prepare command is the one to follow if you use Compose: [Optional settings](https://github.com/jpezzulli/sglang-rtxpro6000/blob/pennyroyal-v2.5.1/docker/pennyroyal/README.md). The same entrypoint, without Compose, is:

```bash
docker pull ghcr.io/jpezzulli/sglang-rtxpro6000@sha256:76258532b1c01f7583fbe951f90b80903db931030291db9db4e5a68b28567866

docker run --rm \
  -v /path/to/parent:/models \
  ghcr.io/jpezzulli/sglang-rtxpro6000@sha256:76258532b1c01f7583fbe951f90b80903db931030291db9db4e5a68b28567866 \
  exec .venv/bin/python scripts/pennyroyal/prepare_ple_nvme.py \
  --source /models/RadixArk-Qwen3.8-Flash-Next-NVFP4 \
  --output /models/flash-next-ple
```

`/path/to/parent` is the ext4 directory that contains the checkpoint. The output must be a new directory. Leave the source checkpoint unchanged. If `exec` is refused, use the Compose form in the container guide, then continue with the paths you actually got.

## 3. Tell the scripts where those directories are

From the checkout root:

```powershell
copy paths.example.jsonc paths.jsonc
```

Edit `paths.jsonc`. Set:

- `wsl_distro` — the name from `wsl -l -q`
- `model_source` — the checkpoint directory from step 1
- `model_prepared` — the overlay from step 2
- `data_dir` — a writable ext4 directory for cache and NIXL
- `host_port`, `container_name`, `dockerd_task` — change them if the defaults collide with something you already run

`paths.jsonc` is gitignored. Do not commit it. The scripts refuse to start while a value still contains `/path/to`, and they refuse Linux paths under `/mnt/`.

The checkout itself is located from the script file. Moving this folder to another drive does not require an edit, except that a registered dockerd task still points at the old folder until you run the install script again.

## 4. Register dockerd, then start

WSL has no systemd. If `dockerd` is a child of a terminal, closing that terminal kills the engine and the model with it. The task in `windows/` starts it with no window and waits, so the engine outlives the terminal.

Skip this if `docker info` already works in the distro. Do not register a second dockerd beside one that is already running.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install-dockerd-task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\start-service.ps1 -Action check
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\start-service.ps1
```

`start` returns when the container exists. It does not mean the model has finished loading. Cold start on the machine these files came from was about 7–8 minutes, and the image's own health check allows 20. Then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\start-service.ps1 -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\start-service.ps1 -Action smoke
```

`smoke` calls `http://127.0.0.1:<host_port>/v1/chat/completions`. The served name is `qwen3.8-flash-next-pennyroyal`. The port is whatever you set in `paths.jsonc`. The process listens on loopback only. It has no API key. Do not publish it on `0.0.0.0` unless you add your own authentication.

A hand-typed `docker run`, for when you are already inside WSL and do not want the PowerShell shortcut, is in `windows/manual.md`. Use the shortcut unless you are debugging the command itself.

The other profile is not the daily one:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\start-service.ps1 -Config configs\context-350k.jsonc
```

That launcher asks for a 350,000-token context. It was not boot-tested as its own server. Switching profile or editing `paths.jsonc` does not change a container that already exists. Stop it, `docker rm` it, then start again.

## 5. Stop

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\stop-service.ps1
```

This stops the model container and drops the WSL page cache. It does not stop dockerd, and it does not shut WSL down. Other containers can keep using the engine.

## What the patch changes

- `overlays/common.py` — WSL's default pinned allocator broke the Mamba kernel. This file is the torch-pinned allocator that was mounted over the image copy.
- `overlays/hicache_nixl.py` — NIXL component-count fix, mounted over the image copy. Also reads `l3_cleaner_max_gib` and optional `l3_cleaner_target_gib` (defaults to half of max when omitted) from the toml and strips them before the NIXL plugin sees the dict. Those cap the sum of NIXL cache files in GiB, not the whole disk. A container restart is required.
- `overlays/serve-flash-next.sh` — the 250,000-token launcher used for the run above. HiCache is 12 GiB, not upstream's 32 GiB.
- `overlays/nixl-preflight.toml` — buffered POSIX IO. O_DIRECT was the slower path on this setup.
- `windows/run-dockerd-hidden.vbs` — dockerd owned by Task Scheduler, no console window.

The `.patch` files are the functional diff against the image. They do not include the short notice header added to the copies in this tree. Mount the `.py` and `.sh` files, not the patches. Image-internal paths such as `/opt/pennyroyal/...` are properties of that digest. They are not your disk layout. `overlays/README.md` lists them.

## Layout

- `windows/` — start, stop, the hidden dockerd task, and the hand-typed command
- `configs/` — runtime profiles. No disk paths
- `overlays/` — files mounted into the pinned image
- `paths.example.jsonc` — copy to `paths.jsonc` and fill in
- `reports/` — notes from one WSL machine. Not setup instructions

## Measured on one machine

These numbers are from one Windows WSL2 host. They are not a claim about bare-metal Pennyroyal, and they are not a significance test. Three rounds per tier is a small sample.

Hardware, as reported on that host:

- Windows 11 Pro, WSL2, Ubuntu 26.04
- AMD Ryzen 7 9700X, 8 cores / 16 threads
- 61.6 GiB physical memory, as Windows reported it
- NVIDIA RTX PRO 6000 Blackwell Max-Q Workstation Edition
- `nvidia-smi` inside WSL: 97887 MiB, driver 596.72

No hostname, account, or disk path belongs in this section.

### 250K profile

This is the server the speed table ran against. It is `configs/default.jsonc` plus `overlays/serve-flash-next.sh`. Editing the JSON without the matching shell line does not change the server.

- Image: `ghcr.io/jpezzulli/sglang-rtxpro6000@sha256:76258532b1c01f7583fbe951f90b80903db931030291db9db4e5a68b28567866`
- Entrypoint profile: `next-plain`. FR-Spec off. Online FP8 off.
- Context: 250000, native RoPE, empty model overrides. The checkpoint's original max position is 262144, so this profile does not use YaRN.
- Scheduler: `MAX_TOTAL_TOKENS` 300032, `max_running_requests` 4, `max_mamba_cache_size` 24
- Container: 28 GiB cgroup cap, `memory.swap.max=0`, `--shm-size` 4g
- GPU: `--mem-fraction-static` 0.94, tensor parallel 1, page size 64, chunked prefill 4096
- Weights: ModelOpt NVFP4 (`modelopt_fp4`), compute bfloat16, KV `fp8_e4m3`
- Mamba: SSM and conv bfloat16, track interval 64, radix strategy `extra_buffer`, `gdn-mtp-cache-mode` none
- Linear attention: FlashInfer for decode and prefill
- HiCache: 12 GiB, host mode `cache`, `write_through`, kernel IO, `page_first`, NIXL backend, prefetch `timeout`
- NIXL: buffered POSIX. `use_direct_io` false. O_DIRECT was the slower path on this host.
- PLE: NVMe FP8 table, not the RAM-backed table
- Allocator: the torch-pinned overlay in `overlays/common.py`. `SGLANG_HICACHE_TORCH_PINNED_ALLOC=1`
- Build jobs inside the container: 2
- Served name: `qwen3.8-flash-next-pennyroyal`

Protocol for the table: one 1024-token warmup, then 12 formal requests. Each of 32K, 64K, 128K, and 248K ran 3 serial rounds, 512 output tokens, temperature 0.6, top_p 0.95, seed 42 plus the trial index, thinking off, `ignore_eos`. Cache hits were 0. TTFT is submit to the first non-empty text. Decode is client-side `(completion_tokens - 1) / (elapsed - TTFT)`. Prefill tok/s uses the server's prefill-forward stage. Values are medians.

| Input tokens | TTFT s | Prefill tok/s | Decode tok/s (range) |
|---:|---:|---:|---:|
| 32,768 | 3.053 | 11471 | 128.2 (124.7–131.9) |
| 65,536 | 6.029 | 11345 | 125.3 (125.1–130.9) |
| 131,072 | 12.547 | 10831 | 118.4 (81.8–120.6) |
| 248,000 | 26.255 | 9739 | 119.6 (79.1–133.0) |

One 128K round decoded at 81.8 tok/s, and one 248K round at 79.1. Do not read the medians as a stable rate above 120.

An older Primitive run on this same host, not re-run for this patch, had decode medians of 115.4 / 125.0 / 115.8 / 114.2 tok/s at those four lengths. That is a historical baseline, not a paired comparison.

The lab note is `reports/20260924-context-speed.md`. Raw result files are not in this repository.

### 524K profile

Not the default. A separate server was booted at context-length 524288, YaRN factor 2.0, the same 12 GiB HiCache and 28 GiB container cap. It started, and a 384K-token prompt completed a short smoke request (128 output tokens, one cold pass and one warm cache hit). A 490K prompt did not finish. That is not a daily configuration, and it is not evidence that upstream's long-context recipe fails on bare metal.

## License

The overlay files are modified files from the Pennyroyal image named above. Upstream is Apache-2.0. See `LICENSE` and `NOTICE`. Model weights are under their own license on the model card. This repository does not grant that license.

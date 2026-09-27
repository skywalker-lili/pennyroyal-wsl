# Hand-typed start and stop

Prefer the shortcuts. They read `paths.jsonc` and refuse a Windows-drive model path.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\start-service.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\stop-service.ps1
```

From inside the distro, `powershell.exe` can call those same files. The checkout path is wherever you put this folder:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File /mnt/c/path/to/this/checkout/windows/start-service.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File /mnt/c/path/to/this/checkout/windows/stop-service.ps1
```

`/mnt/c/path/to/this/checkout` is a placeholder for the checkout. The model directories are not under `/mnt`.

## docker run, if you are not using the shortcut

Fill the four paths. They are the same values as `paths.jsonc`. The image digest is not a path. Do not replace it with a floating tag.

`REPO` is this checkout as a Linux path (`wslpath -a` on the Windows path of the folder that contains `windows/`). Overlay files may live on `/mnt/<drive>`. The three data paths must not.

```bash
DISTRO=Ubuntu
MODEL_SOURCE=/path/to/RadixArk-Qwen3.8-Flash-Next-NVFP4
MODEL_PREPARED=/path/to/flash-next-ple
DATA_DIR=/path/to/pennyroyal-data
HOST_PORT=30021
CONTAINER=flash-next-pennyroyal
REPO=/path/to/this/checkout
IMAGE=ghcr.io/jpezzulli/sglang-rtxpro6000@sha256:76258532b1c01f7583fbe951f90b80903db931030291db9db4e5a68b28567866

sudo sysctl -w vm.drop_caches=3
sudo sysctl -w vm.compact_memory=1
mkdir -p "$DATA_DIR/cache" "$DATA_DIR/nixl"

sudo docker run -d \
  --name "$CONTAINER" \
  --gpus all \
  --user 0 \
  --memory 28g \
  --shm-size 4g \
  --security-opt seccomp=unconfined \
  -p "127.0.0.1:${HOST_PORT}:8001" \
  -v "$MODEL_SOURCE:/models/source:ro" \
  -v "$MODEL_PREPARED:/models/prepared:ro" \
  -v "$DATA_DIR/cache:/cache:rw" \
  -v "$DATA_DIR/nixl:/nixl:rw" \
  -v "$REPO/overlays/nixl-preflight.toml:/config/nixl.toml:ro" \
  -v "$REPO/overlays/hicache_nixl.py:/opt/pennyroyal/python/sglang/srt/mem_cache/storage/nixl/hicache_nixl.py:ro" \
  -v "$REPO/overlays/common.py:/opt/pennyroyal/python/sglang/srt/mem_cache/pool_host/common.py:ro" \
  -v "$REPO/overlays/serve-flash-next.sh:/opt/pennyroyal/configs/pennyroyal/serve-flash-next.sh:ro" \
  -e TARGET_MODEL=/models/source \
  -e PENNY_PLE_BACKEND=nvme \
  -e PENNY_PLE_NVME_MODEL=/models/prepared \
  -e CACHE_BASE=/cache \
  -e NIXL_STORAGE_BASE=/nixl \
  -e SGLANG_HICACHE_TORCH_PINNED_ALLOC=1 \
  -e SGLANG_SM120_ONLINE_MXFP8=false \
  -e NIXL_CONFIG=/config/nixl.toml \
  -e MAX_TOTAL_TOKENS=300032 \
  -e MAX_RUNNING_REQUESTS=4 \
  -e MAX_MAMBA_CACHE_SIZE=24 \
  -e PENNY_BUILD_JOBS=2 \
  -e CUDA_HOME=/usr/local/cuda-13.3 \
  "$IMAGE" \
  next-plain
```

Then turn container swap off. Replace `$CONTAINER` if you changed the name:

```bash
sudo python3 - <<'PY'
from pathlib import Path
import subprocess
name = "flash-next-pennyroyal"
pid = subprocess.check_output(["docker", "inspect", "-f", "{{.State.Pid}}", name], text=True).strip()
cgroup = Path(f"/proc/{pid}/cgroup").read_text().strip().split("::")[-1]
path = Path("/sys/fs/cgroup" + cgroup) / "memory.swap.max"
path.write_text("0")
assert path.read_text().strip() == "0"
print(path)
PY
```

`docker run -d` returns before the model is loaded. `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$HOST_PORT/health` is ready at `200`. If the container name already exists, do not run again. `sudo docker start "$CONTAINER"`, then the swap command.

## Stop

```bash
sudo docker stop -t 60 "$CONTAINER"
sudo sysctl -w vm.drop_caches=3
sudo sysctl -w vm.compact_memory=1
```

Do not `wsl --shutdown`. Do not kill dockerd. Those are shared with anything else using the engine.

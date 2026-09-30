# Overlay mount targets

These paths are inside the pinned image. They are not your disk. `windows/start-service.ps1` mounts the files in this directory onto them. Do not rewrite them to a Windows path.

- `common.py` -> `/opt/pennyroyal/python/sglang/srt/mem_cache/pool_host/common.py`
- `hicache_nixl.py` -> `/opt/pennyroyal/python/sglang/srt/mem_cache/storage/nixl/hicache_nixl.py`
- `serve-flash-next.sh` or `serve-flash-next-350k.sh` -> `/opt/pennyroyal/configs/pennyroyal/serve-flash-next.sh`
- `nixl-preflight.toml` -> `/config/nixl.toml`. `l3_cleaner_max_gib` and `l3_cleaner_target_gib` are read by the mounted `hicache_nixl.py`, then removed so the NIXL plugin does not see them. They are not upstream cleaner arguments.

The launcher is mounted over the image's `serve-flash-next.sh` even when the file you selected is `serve-flash-next-350k.sh`. The image entrypoint calls that name. The shell then finds `chat-template.sh`, `request-capacity.sh`, and `ple-backend.sh` beside it, in the image, so those files are not copied here.

`serve-flash-next-350k.sh` was not boot-tested as its own server.

Your checkpoint, prepared PLE overlay, cache, and NIXL directory come from `paths.jsonc` and are mounted at `/models/source`, `/models/prepared`, `/cache`, and `/nixl`.

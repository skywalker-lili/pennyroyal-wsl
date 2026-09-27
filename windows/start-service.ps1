# Start the WSL Pennyroyal container.
# The checkout is the parent of this script's directory. Disk paths come from paths.jsonc.
param(
  [ValidateSet('start', 'status', 'smoke', 'check')]
  [string]$Action = 'start',
  [string]$Config = ''
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

function Read-Jsonc([string]$Path) {
  $text = Get-Content -Raw -LiteralPath $Path
  $text = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
  $text = [regex]::Replace($text, '(?m)//.*$', '')
  return ($text | ConvertFrom-Json)
}

function Assert-NoQuote([string]$Value, [string]$Name) {
  if ($Value.Contains("'")) { throw "$Name cannot contain a single quote" }
}

function ConvertTo-WslPath([string]$Distro, [string]$WindowsPath) {
  Assert-NoQuote $WindowsPath 'checkout path'
  $escaped = $WindowsPath.Replace("'", "'\''")
  $out = & wsl.exe -d $Distro -u root -- bash -lc "wslpath -a '$escaped'"
  if ($LASTEXITCODE -ne 0) { throw "wslpath failed for $WindowsPath" }
  return (($out | Out-String).Trim())
}

function Invoke-WslBash([string]$Distro, [string]$Script) {
  $normalized = $Script -replace "`r`n", "`n" -replace "`r", "`n"
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($normalized))
  & wsl.exe -d $Distro -u root -- bash -lc "echo $b64 | base64 -d | bash"
  if ($LASTEXITCODE -ne 0) { throw "WSL command failed ($LASTEXITCODE)" }
}

$pathsFile = Join-Path $RepoRoot 'paths.jsonc'
if (-not (Test-Path -LiteralPath $pathsFile)) {
  throw "Copy paths.example.jsonc to paths.jsonc and edit it. Missing: $pathsFile"
}
$paths = Read-Jsonc $pathsFile
foreach ($name in @('wsl_distro', 'model_source', 'model_prepared', 'data_dir', 'container_name', 'dockerd_task')) {
  $value = [string]$paths.$name
  if ([string]::IsNullOrWhiteSpace($value)) { throw "paths.jsonc is missing $name" }
  if ($value -match '/path/to') { throw "paths.jsonc still has a placeholder in $name" }
  Assert-NoQuote $value $name
}
foreach ($name in @('model_source', 'model_prepared', 'data_dir')) {
  $value = [string]$paths.$name
  if ($value -notmatch '^/') { throw "$name must be an absolute path inside the WSL distro" }
  if ($value -match '^/mnt/') { throw "$name must be on the distro filesystem, not $value" }
}
if (-not $paths.host_port) { throw 'paths.jsonc is missing host_port' }

$distro = [string]$paths.wsl_distro
$configPath = if ($Config) {
  if ([System.IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $RepoRoot $Config }
} else {
  Join-Path $RepoRoot 'configs\default.jsonc'
}
if (-not (Test-Path -LiteralPath $configPath)) { throw "Config not found: $configPath" }
$cfg = Read-Jsonc $configPath
$launcher = Join-Path $RepoRoot "overlays\$($cfg.launcher)"
if (-not (Test-Path -LiteralPath $launcher)) { throw "Launcher not found: $launcher" }
$launcherText = Get-Content -Raw -LiteralPath $launcher
if ($launcherText -notmatch "CONTEXT_LENGTH=$($cfg.context)(\D|$)") {
  throw "configs context $($cfg.context) does not match CONTEXT_LENGTH in $($cfg.launcher)"
}
if ($launcherText -notmatch [regex]::Escape([string]$cfg.served_model_name)) {
  throw "served_model_name is not in $($cfg.launcher)"
}

$wslRepo = ConvertTo-WslPath $distro $RepoRoot
Write-Output "checkout: $wslRepo"
Write-Output "distro: $distro"
Write-Output "config: $configPath"
Write-Output "image: $($cfg.image)"
if ($Action -eq 'check') {
  Write-Output 'check: paths accepted, nothing started'
  exit 0
}

function Get-HealthCode {
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri "http://127.0.0.1:$($paths.host_port)/health"
    return [int]$resp.StatusCode
  } catch {
    return 0
  }
}

if ($Action -eq 'status') {
  Write-Output "health: $(Get-HealthCode)"
  & wsl.exe -d $distro -u root -- docker ps -a --filter "name=$($paths.container_name)" --format '{{.Names}} {{.Status}}'
  & wsl.exe -d $distro -u root -- nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader
  exit 0
}

if ($Action -eq 'smoke') {
  $code = Get-HealthCode
  if ($code -ne 200) { throw "health returned $code, not 200" }
  $body = @{
    model = [string]$cfg.served_model_name
    messages = @(@{ role = 'user'; content = 'Reply with the single word pong.' })
    max_tokens = 16
    temperature = 0
  } | ConvertTo-Json -Depth 5
  $chat = Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Method Post `
    -Uri "http://127.0.0.1:$($paths.host_port)/v1/chat/completions" `
    -ContentType 'application/json' -Body $body
  Write-Output $chat.Content
  exit 0
}

$os = Get-CimInstance Win32_OperatingSystem
$freeBytes = [int64]$os.FreePhysicalMemory * 1KB
if ($freeBytes -lt 6GB) {
  throw "Windows available RAM is below 6GiB ($([math]::Round($freeBytes / 1GB, 1)) GiB). Drop caches and retry. Do not add swap."
}

$dockerUp = $false
& wsl.exe -d $distro -u root -- docker info *> $null
if ($LASTEXITCODE -eq 0) { $dockerUp = $true }
if (-not $dockerUp) {
  & schtasks.exe /Run /TN $paths.dockerd_task
  if ($LASTEXITCODE -ne 0) {
    throw "docker is down and scheduled task '$($paths.dockerd_task)' did not start. Run windows\install-dockerd-task.ps1 once, or start the engine you already have."
  }
  $ready = $false
  foreach ($i in 1..30) {
    Start-Sleep -Seconds 1
    & wsl.exe -d $distro -u root -- docker info *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
  }
  if (-not $ready) { throw 'dockerd task was started but docker info is still failing' }
}

$container = [string]$paths.container_name
$exists = (& wsl.exe -d $distro -u root -- docker container inspect -f '{{.Name}}' $container 2>$null | Out-String).Trim()
$reuse = -not [string]::IsNullOrWhiteSpace($exists)

$swap = @"
python3 - <<'PY'
from pathlib import Path
import subprocess
name = "$container"
pid = subprocess.check_output(["docker", "inspect", "-f", "{{.State.Pid}}", name], text=True).strip()
cgroup = Path(f"/proc/{pid}/cgroup").read_text().strip().split("::")[-1]
path = Path("/sys/fs/cgroup" + cgroup) / "memory.swap.max"
path.write_text("0")
assert path.read_text().strip() == "0", path.read_text()
print(path)
PY
"@

$prelude = @"
set -euo pipefail
sysctl -w vm.drop_caches=3
sysctl -w vm.compact_memory=1
"@

if ($reuse) {
  Write-Output "reusing $container. Path and config edits are not applied to an existing container. stop, docker rm $container, then start again."
  Invoke-WslBash $distro @"
$prelude
docker start '$container'
$swap
"@
} else {
  $image = [string]$cfg.image
  Assert-NoQuote $image 'image'
  Assert-NoQuote $wslRepo 'wsl checkout'
  $memory = "$($cfg.memory_gib)g"
  $bash = @"
$prelude
mkdir -p '$($paths.data_dir)/cache' '$($paths.data_dir)/nixl'
docker run -d \
  --name '$container' \
  --gpus all \
  --user 0 \
  --memory $memory \
  --shm-size 4g \
  --security-opt seccomp=unconfined \
  -p 127.0.0.1:$($paths.host_port):8001 \
  -v '$($paths.model_source):/models/source:ro' \
  -v '$($paths.model_prepared):/models/prepared:ro' \
  -v '$($paths.data_dir)/cache:/cache:rw' \
  -v '$($paths.data_dir)/nixl:/nixl:rw' \
  -v '$wslRepo/overlays/nixl-preflight.toml:/config/nixl.toml:ro' \
  -v '$wslRepo/overlays/hicache_nixl.py:/opt/pennyroyal/python/sglang/srt/mem_cache/storage/nixl/hicache_nixl.py:ro' \
  -v '$wslRepo/overlays/common.py:/opt/pennyroyal/python/sglang/srt/mem_cache/pool_host/common.py:ro' \
  -v '$wslRepo/overlays/$($cfg.launcher):/opt/pennyroyal/configs/pennyroyal/serve-flash-next.sh:ro' \
  -e TARGET_MODEL=/models/source \
  -e PENNY_PLE_BACKEND=nvme \
  -e PENNY_PLE_NVME_MODEL=/models/prepared \
  -e CACHE_BASE=/cache \
  -e NIXL_STORAGE_BASE=/nixl \
  -e SGLANG_HICACHE_TORCH_PINNED_ALLOC=1 \
  -e SGLANG_SM120_ONLINE_MXFP8=false \
  -e NIXL_CONFIG=/config/nixl.toml \
  -e MAX_TOTAL_TOKENS=$($cfg.max_total_tokens) \
  -e MAX_RUNNING_REQUESTS=$($cfg.max_running_requests) \
  -e MAX_MAMBA_CACHE_SIZE=$($cfg.max_mamba_cache_size) \
  -e PENNY_BUILD_JOBS=$($cfg.penny_build_jobs) \
  -e CUDA_HOME=/usr/local/cuda-13.3 \
  $image \
  next-plain
$swap
"@
  Invoke-WslBash $distro $bash
}

Write-Output "container started. The model is not ready yet. Cold start is several minutes. Poll: http://127.0.0.1:$($paths.host_port)/health"

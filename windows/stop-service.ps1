# Stop the model container only. Does not stop dockerd and does not shut WSL down.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$pathsFile = Join-Path $RepoRoot 'paths.jsonc'
if (-not (Test-Path -LiteralPath $pathsFile)) {
  throw "Missing paths.jsonc. Nothing to stop was recorded there."
}
$text = Get-Content -Raw -LiteralPath $pathsFile
$text = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
$text = [regex]::Replace($text, '(?m)//.*$', '')
$paths = $text | ConvertFrom-Json
$distro = [string]$paths.wsl_distro
$container = [string]$paths.container_name
if ($container.Contains("'")) { throw 'container_name cannot contain a single quote' }

& wsl.exe -d $distro -u root -- docker info *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Output 'docker is not running. The model container is already gone. dockerd was not started.'
} else {
  & wsl.exe -d $distro -u root -- docker stop -t 60 $container
  if ($LASTEXITCODE -ne 0) {
    Write-Output "docker stop returned $LASTEXITCODE. If the container was already stopped, that is fine."
  }
}

& wsl.exe -d $distro -u root -- sysctl -w vm.drop_caches=3
& wsl.exe -d $distro -u root -- sysctl -w vm.compact_memory=1
Write-Output 'stopped the model container only. dockerd and WSL were left running.'

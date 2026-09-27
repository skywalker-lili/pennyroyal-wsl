# Register the hidden dockerd task. Does not start the model.
# Skip this if docker info already works. One dockerd per distro.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$pathsFile = Join-Path $RepoRoot 'paths.jsonc'
if (-not (Test-Path -LiteralPath $pathsFile)) {
  throw "Copy paths.example.jsonc to paths.jsonc and set wsl_distro and dockerd_task first."
}
$text = Get-Content -Raw -LiteralPath $pathsFile
$text = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
$text = [regex]::Replace($text, '(?m)//.*$', '')
$paths = $text | ConvertFrom-Json
$task = [string]$paths.dockerd_task
$vbs = Join-Path $PSScriptRoot 'run-dockerd-hidden.vbs'
if (-not (Test-Path -LiteralPath $vbs)) { throw "Missing $vbs" }
$tr = "wscript.exe //B //Nologo `"$vbs`""
if ($tr.Length -gt 261) {
  throw "Scheduled task command is $($tr.Length) characters. Move the checkout to a shorter path. The limit is 261."
}
& schtasks.exe /Create /F /TN $task /SC ONCE /ST 00:00 /RL LIMITED /TR $tr
if ($LASTEXITCODE -ne 0) { throw "schtasks /Create failed ($LASTEXITCODE). Run this once from a shell that is allowed to register a task." }
Write-Output "registered $task. It was not started. start-service.ps1 runs it only when docker info fails."
Write-Output "If you move this folder, run this script again."

# Keep dockerd alive without a visible console.
# The scheduled task runs this file and waits. wsl.exe is started with
# CREATE_NO_WINDOW so closing the caller's terminal does not own the process.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$pathsFile = Join-Path $RepoRoot 'paths.jsonc'
if (-not (Test-Path -LiteralPath $pathsFile)) { throw "Missing paths.jsonc" }
$text = Get-Content -Raw -LiteralPath $pathsFile
$text = [regex]::Replace($text, '(?s)/\*.*?\*/', '')
$text = [regex]::Replace($text, '(?m)//.*$', '')
$paths = $text | ConvertFrom-Json
$distro = [string]$paths.wsl_distro
$sh = Join-Path $PSScriptRoot 'run-dockerd.sh'
$escaped = $sh.Replace("'", "'\''")
$wslSh = (& wsl.exe -d $distro -u root -- bash -lc "wslpath -a '$escaped'").Trim()
if (-not $wslSh) { throw "wslpath failed for $sh" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $env:SystemRoot 'System32\wsl.exe'
$psi.Arguments = "-d $distro -u root -- bash $wslSh"
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$process = [Diagnostics.Process]::Start($psi)
if (-not $process) { throw 'Failed to start hidden wsl.exe for dockerd' }
$process.WaitForExit()
exit $process.ExitCode

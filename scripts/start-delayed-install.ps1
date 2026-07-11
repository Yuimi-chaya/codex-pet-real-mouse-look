[CmdletBinding()]
param(
  [ValidateRange(60, 3600)][int]$DelaySeconds = 180,
  [string]$OutputRoot = (Join-Path $env:USERPROFILE 'Downloads\codex-pet-real-mouse-look'),
  [switch]$ConfirmedByUser
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmedByUser) {
  throw 'Delayed installation requires explicit user confirmation. Re-run with -ConfirmedByUser only after explaining package replacement and rollback risk.'
}
$patch = Join-Path $PSScriptRoot 'patch-codex-pet-real-mouse-look-msix.ps1'
$taskId = [guid]::NewGuid().ToString('N')
$cancel = Join-Path $OutputRoot ("CANCEL-DELAYED-INSTALL-$taskId")
$runner = Join-Path $env:TEMP ('codex-pet-look-delayed-' + [guid]::NewGuid().ToString('N') + '.ps1')
$body = @"
`$ErrorActionPreference = 'Stop'
Start-Sleep -Seconds $DelaySeconds
if (Test-Path -LiteralPath '$($cancel.Replace("'", "''"))') { exit 2 }
`$deadline = (Get-Date).AddMinutes(10)
do {
  if (Test-Path -LiteralPath '$($cancel.Replace("'", "''"))') { exit 2 }
  `$codex = @(Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue)
  if (`$codex.Count -eq 0) { break }
  Start-Sleep -Seconds 2
} while ((Get-Date) -lt `$deadline)
if (`$codex.Count -ne 0) { throw 'Codex did not exit within 10 minutes; installation cancelled.' }
if (Test-Path -LiteralPath '$($cancel.Replace("'", "''"))') { exit 2 }
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$($patch.Replace("'", "''"))' -OutputRoot '$($OutputRoot.Replace("'", "''"))' -Install -NoLaunch -InstallPrerequisites
exit `$LASTEXITCODE
"@
[System.IO.File]::WriteAllText($runner, $body, (New-Object System.Text.UTF8Encoding($false)))
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $runner + '"')) -WindowStyle Hidden
Write-Host "[codex-pet-look-delay] scheduled after $DelaySeconds seconds"
Write-Host "[codex-pet-look-delay] cancel before execution by creating: $cancel"

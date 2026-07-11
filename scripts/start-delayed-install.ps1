[CmdletBinding()]
param(
  [ValidateRange(60, 3600)][int]$DelaySeconds = 60,
  [string]$OutputRoot = (Join-Path $env:USERPROFILE 'Downloads\codex-pet-real-mouse-look'),
  [switch]$ConfirmedByUser,
  [switch]$AutoCloseCodexAcknowledged,
  [switch]$GenerateOnly
)

$ErrorActionPreference = 'Stop'
if (-not $GenerateOnly -and -not $ConfirmedByUser) {
  throw 'Delayed installation requires explicit user confirmation. Re-run with -ConfirmedByUser only after explaining package replacement and rollback risk.'
}
if (-not $GenerateOnly -and -not $AutoCloseCodexAcknowledged) {
  throw 'The user must explicitly acknowledge that Codex/ChatGPT will close automatically. Re-run with -AutoCloseCodexAcknowledged only after that acknowledgement.'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot -ErrorAction Stop).Path
$patch = Join-Path $PSScriptRoot 'patch-codex-pet-real-mouse-look-msix.ps1'
$rollback = Join-Path $PSScriptRoot 'rollback-codex-pet-msix.ps1'
$taskId = [guid]::NewGuid().ToString('N')
$cancel = Join-Path $OutputRoot ("CANCEL-DELAYED-INSTALL-$taskId")
$runOutputRoot = Join-Path $OutputRoot ("delayed-$taskId")
$runner = if ($GenerateOnly) {
  Join-Path $OutputRoot 'codex-pet-look-delayed.generated.ps1'
} else {
  Join-Path $env:TEMP ('codex-pet-look-delayed-' + [guid]::NewGuid().ToString('N') + '.ps1')
}
$body = @"
`$ErrorActionPreference = 'Stop'
`$host.UI.RawUI.WindowTitle = 'Codex pet patch - do not close this window'
try {
  Write-Host '[codex-pet-look-delay] Codex will close and patching will start after $DelaySeconds seconds.'
  Write-Host '[codex-pet-look-delay] Do not close this command window.'
  Start-Sleep -Seconds $DelaySeconds
  if (Test-Path -LiteralPath '$($cancel.Replace("'", "''"))') { exit 2 }
  `$codex = @(Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue)
  foreach (`$process in `$codex) {
    try { [void]`$process.CloseMainWindow() } catch { }
  }
  `$closeDeadline = (Get-Date).AddSeconds(15)
  do {
    if (Test-Path -LiteralPath '$($cancel.Replace("'", "''"))') { exit 2 }
    Start-Sleep -Seconds 1
    `$codex = @(Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue)
  } while (`$codex.Count -gt 0 -and (Get-Date) -lt `$closeDeadline)
  if (`$codex.Count -gt 0) {
    Write-Host '[codex-pet-look-delay] ending remaining Codex/ChatGPT processes after the graceful-close window'
    `$codex | Stop-Process -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
  }
  if (@(Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Codex or ChatGPT is still running after the automatic close attempt.'
  }
  if (Test-Path -LiteralPath '$($cancel.Replace("'", "''"))') { exit 2 }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File '$($patch.Replace("'", "''"))' -OutputRoot '$($runOutputRoot.Replace("'", "''"))' -Install -NoLaunch -InstallPrerequisites
  if (`$LASTEXITCODE -ne 0) { throw "Patch process exited with code `$LASTEXITCODE." }
  Write-Host '[codex-pet-look-delay] patch completed. Start Codex from the Start menu after closing this window.' -ForegroundColor Green
  [void](Read-Host 'Press Enter to close this command window')
  exit 0
} catch {
  Write-Host "[codex-pet-look-delay] FAILED: `$(`$_.Exception.Message)" -ForegroundColor Red
  `$backups = @(Get-ChildItem -LiteralPath '$($runOutputRoot.Replace("'", "''"))' -Recurse -Filter '*_original-backup.msix' -File -ErrorAction SilentlyContinue)
  if (`$backups.Count -eq 1) {
    `$backup = `$backups[0]
    `$rollbackCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + '$($rollback.Replace("'", "''"))' + '" -BackupMsix "' + `$backup.FullName + '" -Install -Confirm'
    Write-Host '[codex-pet-look-delay] Rollback command for this run:' -ForegroundColor Yellow
    Write-Host `$rollbackCommand -ForegroundColor Yellow
  } elseif (`$backups.Count -eq 0) {
    Write-Host '[codex-pet-look-delay] No original-backup MSIX was created for this run. Do not use an unrelated backup; inspect the error before retrying.' -ForegroundColor Yellow
  } else {
    Write-Host '[codex-pet-look-delay] Multiple backups were found in this run-specific directory. No rollback command will be guessed; inspect the files first.' -ForegroundColor Yellow
  }
  [void](Read-Host 'Keep this window open until you record the error and rollback command. Press Enter to close')
  exit 1
}
"@
[System.IO.File]::WriteAllText($runner, $body, (New-Object System.Text.UTF8Encoding($false)))
if ($GenerateOnly) {
  Write-Host "[codex-pet-look-delay] generated runner without scheduling: $runner"
  exit 0
}
Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $runner + '"')) -WindowStyle Normal
Write-Host "[codex-pet-look-delay] scheduled after $DelaySeconds seconds"
Write-Host "[codex-pet-look-delay] cancel before execution by creating: $cancel"
Write-Host '[codex-pet-look-delay] Codex/ChatGPT will close automatically. Do not close the command window that opens.'

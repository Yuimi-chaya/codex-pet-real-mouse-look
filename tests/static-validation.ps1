[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wrapper = Join-Path $root 'scripts\patch-codex-pet-real-mouse-look-msix.ps1'
$base = Join-Path $root 'scripts\lib\msix-repack-base.ps1'
$rollback = Join-Path $root 'scripts\rollback-codex-pet-msix.ps1'
$delayed = Join-Path $root 'scripts\start-delayed-install.ps1'

$required = @{
  $wrapper = @(
    'h=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400&&!u',
    '[switch]$GenerateOnly',
    "'-PatchHookPath', `$petPatchHook"
  )
  $base = @(
    '_original-backup.msix',
    '[Parameter(Mandatory = $true)][string]$PatchHookPath',
    "Cert:\CurrentUser\My"
  )
  $rollback = @(
    '$identity.Name -ne ''OpenAI.Codex''',
    '-PreserveApplicationData'
  )
  $delayed = @(
    'CANCEL-DELAYED-INSTALL-$taskId',
    '[int]$DelaySeconds = 60',
    '[switch]$AutoCloseCodexAcknowledged',
    '[switch]$GenerateOnly',
    'CloseMainWindow()',
    'Stop-Process -Force',
    'delayed-$taskId',
    '$backups.Count -eq 1',
    'Rollback command for this run:',
    '-WindowStyle Normal'
  )
}

foreach ($path in $required.Keys) {
  $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  foreach ($marker in $required[$path]) {
    if (-not $text.Contains($marker)) {
      throw "Required marker missing from ${path}: $marker"
    }
  }
}

$forbiddenPatterns = @(
  ('C:\Users\' + 'a1234'),
  ('.codex\skills\' + 'codex-windows-fast-patch'),
  ('Remove-AppxPackage -Package $existing.PackageFullName ' + '-ErrorAction Stop'),
  ('Cert:\Local' + 'Machine')
)

foreach ($path in @($base, $rollback)) {
  $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  if ($text.Contains('Stop-Process -Force')) {
    throw "Only the explicitly confirmed delayed self-install may force-close Codex: $path"
  }
}

$codexPlusPlusName = 'Codex' + '++'
Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object {
    $_.FullName -notlike '*\.git\*' -and
    $_.FullName -notlike '*\.audit-output*\*'
  } |
  ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -ne $text -and $text.Contains($codexPlusPlusName)) {
      throw "Unrelated project reference found in standalone repository: $($_.FullName)"
    }
  }

$baseText = Get-Content -LiteralPath $base -Raw -Encoding UTF8
foreach ($unrelated in @('Fast Mode', 'Browser Use', 'Computer Use', 'LocalPluginMarketplace', 'openai-curated-local')) {
  if ($baseText.Contains($unrelated)) {
    throw "Unrelated Codex patch behavior found in minimal MSIX base: $unrelated"
  }
}

Get-ChildItem -LiteralPath $root -Recurse -File |
  Where-Object { $_.FullName -notlike '*\.git\*' -and $_.FullName -notlike '*\.audit-output\*' } |
  ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    foreach ($pattern in $forbiddenPatterns) {
      if ($null -ne $text -and $text.Contains($pattern)) {
        throw "Forbidden publication marker found in $($_.FullName): $pattern"
      }
    }
  }

Write-Host '[static-validation] OK'

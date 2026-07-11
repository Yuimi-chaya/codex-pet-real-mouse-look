[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory = $true)][string]$BackupMsix,
  [switch]$Install
)

$ErrorActionPreference = 'Stop'
$resolved = (Resolve-Path -LiteralPath $BackupMsix -ErrorAction Stop).Path
if ([System.IO.Path]::GetExtension($resolved) -ne '.msix') {
  throw "Backup must be an .msix file: $resolved"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolved)
try {
  $manifestEntry = $archive.GetEntry('AppxManifest.xml')
  if (-not $manifestEntry) {
    throw "Backup does not contain AppxManifest.xml: $resolved"
  }
  $reader = New-Object System.IO.StreamReader($manifestEntry.Open(), [System.Text.Encoding]::UTF8, $true)
  try {
    [xml]$manifest = $reader.ReadToEnd()
  } finally {
    $reader.Dispose()
  }
} finally {
  $archive.Dispose()
}
$identity = $manifest.Package.Identity
if (-not $identity -or $identity.Name -ne 'OpenAI.Codex') {
  throw "Backup is not an OpenAI.Codex MSIX: $resolved"
}

Write-Host "[codex-pet-look-rollback] backup: $resolved"
Write-Host "[codex-pet-look-rollback] package: $($identity.Name) $($identity.Version) $($identity.ProcessorArchitecture)"
if (-not $Install) {
  Write-Host '[codex-pet-look-rollback] dry run only; re-run with -Install after the user confirms rollback.'
  exit 0
}
if (-not $PSCmdlet.ShouldProcess('OpenAI.Codex', 'replace current package with rollback MSIX')) {
  exit 0
}
$existing = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1
$running = @(Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
  throw 'Codex or ChatGPT is still running. Close it normally before rollback; the script will not force-close it.'
}
if ($existing) {
  Remove-AppxPackage -Package $existing.PackageFullName -PreserveApplicationData -ErrorAction Stop
}
try {
  Add-AppxPackage -Path $resolved -ErrorAction Stop
} catch {
  Write-Error "Rollback package installation failed after removing the current package. User data was preserved. Re-run Add-AppxPackage -Path `"$resolved`" after resolving the reported AppX error. Original error: $($_.Exception.Message)"
  throw
}
$installed = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | Select-Object -First 1
Write-Host "[codex-pet-look-rollback] installed: $($installed.PackageFullName)"

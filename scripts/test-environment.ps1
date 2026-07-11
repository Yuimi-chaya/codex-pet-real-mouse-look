[CmdletBinding()]
param(
  [string[]]$AuditedAppVersions = @('26.707.3748.0'),
  [string]$OutputRoot = (Join-Path $env:USERPROFILE 'Downloads\codex-pet-real-mouse-look')
)

$ErrorActionPreference = 'Stop'

function Get-CodexPackage {
  try {
    return Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop |
      Sort-Object Version -Descending |
      Select-Object -First 1
  } catch {
    if ($PSVersionTable.PSEdition -eq 'Core') {
      $json = & powershell.exe -NoProfile -Command "Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1 PackageFullName,PackageFamilyName,InstallLocation,@{n='Version';e={`$_.Version.ToString()}} | ConvertTo-Json -Compress"
      if ($LASTEXITCODE -eq 0 -and $json) {
        return $json | ConvertFrom-Json
      }
    }
    return $null
  }
}

$package = Get-CodexPackage
$petsRoot = Join-Path $env:USERPROFILE '.codex\pets'
$pets = @()
if (Test-Path -LiteralPath $petsRoot -PathType Container) {
  foreach ($manifest in Get-ChildItem -LiteralPath $petsRoot -Recurse -File -Filter 'pet.json' -ErrorAction SilentlyContinue) {
    try {
      $pet = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
      $pets += [pscustomobject]@{
        id = [string]$pet.id
        version = if ($pet.spriteVersionNumber) { [int]$pet.spriteVersionNumber } else { 1 }
        manifest = $manifest.FullName
        spritesheetExists = Test-Path -LiteralPath (Join-Path $manifest.DirectoryName ([string]$pet.spritesheetPath)) -PathType Leaf
      }
    } catch {
      $pets += [pscustomobject]@{ id = $manifest.Directory.Name; version = 0; manifest = $manifest.FullName; spritesheetExists = $false }
    }
  }
}

$driveRoot = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($OutputRoot))
$drive = Get-PSDrive -Name $driveRoot.Substring(0, 1) -ErrorAction SilentlyContinue
$commands = @{}
foreach ($name in @('node', 'npm', 'npx', 'makeappx.exe', 'signtool.exe')) {
  $commands[$name] = [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

$version = if ($package) { [string]$package.Version } else { '' }
$result = [ordered]@{
  status = if ($package -and @($pets | Where-Object { $_.version -eq 2 -and $_.spritesheetExists }).Count -gt 0) { 'ready' } else { 'blocked' }
  windows = [Environment]::OSVersion.VersionString
  powershell = $PSVersionTable.PSVersion.ToString()
  powershellEdition = $PSVersionTable.PSEdition
  codexInstalled = [bool]$package
  codexVersion = $version
  codexVersionAudited = $version -in $AuditedAppVersions
  codexLatestStatus = 'unknown-offline-check-store-or-official-source'
  codexInstallLocation = if ($package) { [string]$package.InstallLocation } else { '' }
  outputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
  outputDriveFreeGiB = if ($drive) { [math]::Round($drive.Free / 1GB, 2) } else { $null }
  commands = $commands
  pets = $pets
  v2PetCount = @($pets | Where-Object { $_.version -eq 2 -and $_.spritesheetExists }).Count
  warnings = @(
    if (-not $package) { 'Codex App is not installed for the current Windows user.' }
    if ($version -and $version -notin $AuditedAppVersions) { "Codex App $version is not in the audited compatibility matrix." }
    if (@($pets | Where-Object { $_.version -eq 2 -and $_.spritesheetExists }).Count -eq 0) { 'No usable v2 pet was found. Look directions require spriteVersionNumber: 2.' }
    if ($drive -and $drive.Free -lt 12GB) { 'The output drive has less than 12 GiB free. Repacking may fail.' }
  )
}

$result | ConvertTo-Json -Depth 8

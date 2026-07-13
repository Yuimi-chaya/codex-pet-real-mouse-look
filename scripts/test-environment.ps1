[CmdletBinding()]
param(
  [string[]]$HumanTestedAppVersions = @('26.707.3748.0'),
  [string]$OutputRoot = (Join-Path $env:USERPROFILE 'Downloads\codex-pet-real-mouse-look'),
  [switch]$SkipStoreCheck
)

$ErrorActionPreference = 'Stop'

function Get-CodexPackage {
  try {
    return Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop |
      Sort-Object Version -Descending |
      Select-Object -First 1
  } catch {
    if ($PSVersionTable.PSEdition -eq 'Core') {
      $windowsPowerShell = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($windowsPowerShell) {
        $json = & $windowsPowerShell.Source -NoProfile -Command "Get-AppxPackage -Name 'OpenAI.Codex' | Sort-Object Version -Descending | Select-Object -First 1 PackageFullName,PackageFamilyName,InstallLocation,@{n='Version';e={`$_.Version.ToString()}} | ConvertTo-Json -Compress"
        if ($LASTEXITCODE -eq 0 -and $json) {
          return $json | ConvertFrom-Json
        }
      }
    }
    return $null
  }
}

function Get-CodexStoreUpdateStatus {
  param([string]$InstalledVersion)

  if ($SkipStoreCheck) {
    return [pscustomobject]@{ status = 'unknown'; candidateVersion = ''; method = 'skipped'; detail = 'Store check was skipped.' }
  }

  $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $winget -or [string]::IsNullOrWhiteSpace($InstalledVersion)) {
    return [pscustomobject]@{ status = 'unknown'; candidateVersion = ''; method = 'winget'; detail = 'winget or installed version is unavailable.' }
  }

  try {
    $output = @(& $winget.Source list --id 'OpenAI.Codex' --exact --source 'msstore' --upgrade-available --accept-source-agreements --disable-interactivity 2>&1)
    $versions = @(
      [regex]::Matches(($output -join "`n"), '(?<!\d)(\d+\.\d+\.\d+\.\d+)(?!\d)') |
        ForEach-Object { [version]$_.Groups[1].Value } |
        Sort-Object -Descending -Unique
    )
    $installed = [version]$InstalledVersion
    $newer = @($versions | Where-Object { $_ -gt $installed } | Select-Object -First 1)
    if ($newer.Count -eq 1) {
      return [pscustomobject]@{
        status = 'update-available'
        candidateVersion = $newer[0].ToString()
        method = 'winget'
        detail = 'winget reported a higher version for the exact package id.'
      }
    }
    return [pscustomobject]@{
      status = 'unknown'
      candidateVersion = ''
      method = 'winget'
      detail = 'No authoritative higher-version result was available. Store rollout, account, region, source cache, or package registration may differ.'
    }
  } catch {
    return [pscustomobject]@{ status = 'unknown'; candidateVersion = ''; method = 'winget'; detail = $_.Exception.Message }
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
$latest = Get-CodexStoreUpdateStatus -InstalledVersion $version
$result = [ordered]@{
  status = if ($package -and @($pets | Where-Object { $_.version -eq 2 -and $_.spritesheetExists }).Count -gt 0) { 'ready' } else { 'blocked' }
  windows = [Environment]::OSVersion.VersionString
  powershell = $PSVersionTable.PSVersion.ToString()
  powershellEdition = $PSVersionTable.PSEdition
  codexInstalled = [bool]$package
  codexVersion = $version
  codexVersionHumanTested = $version -in $HumanTestedAppVersions
  codexCompatibilityStatus = if ($version -in $HumanTestedAppVersions) { 'human-tested-requires-dry-run' } else { 'strict-dry-run-required' }
  codexLatestStatus = $latest.status
  codexLatestCandidateVersion = $latest.candidateVersion
  codexLatestCheckMethod = $latest.method
  codexLatestCheckDetail = $latest.detail
  codexInstallLocation = if ($package) { [string]$package.InstallLocation } else { '' }
  outputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
  outputDriveFreeGiB = if ($drive) { [math]::Round($drive.Free / 1GB, 2) } else { $null }
  commands = $commands
  pets = $pets
  v2PetCount = @($pets | Where-Object { $_.version -eq 2 -and $_.spritesheetExists }).Count
  warnings = @(
    if (-not $package) { 'Codex App is not installed for the current Windows user.' }
    if ($version -and $version -notin $HumanTestedAppVersions) { "Codex App $version is not human-tested; strict DryRun ASAR target validation is required." }
    if ($latest.status -eq 'update-available') { "A newer Codex App version may be available: $($latest.candidateVersion). Update before patching." }
    if ($latest.status -eq 'unknown') { 'The external checker cannot prove Store latest status; do not report this App as up to date.' }
    if (@($pets | Where-Object { $_.version -eq 2 -and $_.spritesheetExists }).Count -eq 0) { 'No usable v2 pet was found. Look directions require spriteVersionNumber: 2.' }
    if ($drive -and $drive.Free -lt 12GB) { 'The output drive has less than 12 GiB free. Repacking may fail.' }
  )
}

$result | ConvertTo-Json -Depth 8

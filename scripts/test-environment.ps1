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

function Get-PetSpritesheetInfo {
  param(
    [Parameter(Mandatory = $true)][string]$ManifestDirectory,
    [string]$SpritesheetPath
  )

  if ([string]::IsNullOrWhiteSpace($SpritesheetPath)) {
    return [pscustomobject]@{ path = ''; exists = $false; format = 'missing'; supported = $false }
  }
  $path = [System.IO.Path]::GetFullPath((Join-Path $ManifestDirectory $SpritesheetPath))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ path = $path; exists = $false; format = 'missing'; supported = $false }
  }

  $fileLength = (Get-Item -LiteralPath $path).Length
  $header = New-Object byte[] 30
  $stream = [System.IO.File]::OpenRead($path)
  try {
    $read = $stream.Read($header, 0, $header.Length)
  } finally {
    $stream.Dispose()
  }
  $isPng = $fileLength -ge 33 -and $read -ge 24 -and
    $header[0] -eq 0x89 -and $header[1] -eq 0x50 -and $header[2] -eq 0x4e -and $header[3] -eq 0x47 -and
    $header[4] -eq 0x0d -and $header[5] -eq 0x0a -and $header[6] -eq 0x1a -and $header[7] -eq 0x0a -and
    $header[8] -eq 0 -and $header[9] -eq 0 -and $header[10] -eq 0 -and $header[11] -eq 13 -and
    [System.Text.Encoding]::ASCII.GetString($header, 12, 4) -eq 'IHDR' -and
    ($header[16] -ne 0 -or $header[17] -ne 0 -or $header[18] -ne 0 -or $header[19] -ne 0) -and
    ($header[20] -ne 0 -or $header[21] -ne 0 -or $header[22] -ne 0 -or $header[23] -ne 0)
  $riffSize = if ($read -ge 8) { [System.BitConverter]::ToUInt32($header, 4) } else { 0 }
  $webpChunkSize = if ($read -ge 20) { [System.BitConverter]::ToUInt32($header, 16) } else { 0 }
  $webpChunkType = if ($read -ge 16) { [System.Text.Encoding]::ASCII.GetString($header, 12, 4) } else { '' }
  $isWebp = $fileLength -ge 20 -and $read -ge 20 -and
    [System.Text.Encoding]::ASCII.GetString($header, 0, 4) -eq 'RIFF' -and
    [System.Text.Encoding]::ASCII.GetString($header, 8, 4) -eq 'WEBP' -and
    $riffSize -ge 12 -and ([uint64]$riffSize + 8) -le [uint64]$fileLength -and
    $webpChunkType -in @('VP8 ', 'VP8L', 'VP8X') -and
    ([uint64]$webpChunkSize + 20) -le ([uint64]$riffSize + 8)
  $format = if ($isPng) { 'png' } elseif ($isWebp) { 'webp' } else { 'unsupported' }
  return [pscustomobject]@{ path = $path; exists = $true; format = $format; supported = $format -in @('png', 'webp') }
}

$package = Get-CodexPackage
$petsRoot = Join-Path $env:USERPROFILE '.codex\pets'
$pets = @()
if (Test-Path -LiteralPath $petsRoot -PathType Container) {
  foreach ($manifest in Get-ChildItem -LiteralPath $petsRoot -Recurse -File -Filter 'pet.json' -ErrorAction SilentlyContinue) {
    try {
      $pet = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
      $spritesheet = Get-PetSpritesheetInfo -ManifestDirectory $manifest.DirectoryName -SpritesheetPath ([string]$pet.spritesheetPath)
      $pets += [pscustomobject]@{
        id = [string]$pet.id
        version = if ($pet.spriteVersionNumber) { [int]$pet.spriteVersionNumber } else { 1 }
        manifest = $manifest.FullName
        spritesheetPath = $spritesheet.path
        spritesheetExists = $spritesheet.exists
        spritesheetFormat = $spritesheet.format
        spritesheetFormatSupported = $spritesheet.supported
        usableV2 = [int]$pet.spriteVersionNumber -eq 2 -and $spritesheet.supported
      }
    } catch {
      $pets += [pscustomobject]@{ id = $manifest.Directory.Name; version = 0; manifest = $manifest.FullName; spritesheetPath = ''; spritesheetExists = $false; spritesheetFormat = 'invalid-manifest'; spritesheetFormatSupported = $false; usableV2 = $false }
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
  status = if ($package -and @($pets | Where-Object { $_.usableV2 }).Count -gt 0) { 'ready' } else { 'blocked' }
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
  v2PetCount = @($pets | Where-Object { $_.usableV2 }).Count
  warnings = @(
    if (-not $package) { 'Codex App is not installed for the current Windows user.' }
    if ($version -and $version -notin $HumanTestedAppVersions) { "Codex App $version is not human-tested; strict DryRun ASAR target validation is required." }
    if ($latest.status -eq 'update-available') { "A newer Codex App version may be available: $($latest.candidateVersion). Update before patching." }
    if ($latest.status -eq 'unknown') { 'The external checker cannot prove Store latest status; do not report this App as up to date.' }
    if (@($pets | Where-Object { $_.version -eq 2 -and $_.spritesheetExists -and -not $_.spritesheetFormatSupported }).Count -gt 0) { 'A v2 pet spritesheet exists but is not a recognized PNG or WebP file.' }
    if (@($pets | Where-Object { $_.usableV2 }).Count -eq 0) { 'No usable v2 pet was found. Look directions require spriteVersionNumber: 2 and a valid PNG or WebP spritesheet.' }
    if ($drive -and $drive.Free -lt 12GB) { 'The output drive has less than 12 GiB free. Repacking may fail.' }
  )
}

$result | ConvertTo-Json -Depth 8

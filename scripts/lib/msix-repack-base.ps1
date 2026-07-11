[CmdletBinding()]
param(
  [string]$AppPath,
  [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\codex-pet-real-mouse-look'),
  [Parameter(Mandatory = $true)][string]$PatchHookPath,
  [switch]$InstallPrerequisites,
  [switch]$Install,
  [switch]$Launch,
  [switch]$NoLaunch,
  [switch]$ForceRebuild,
  [switch]$KeepWorkDir,
  [switch]$CleanupAfter,
  [switch]$CleanupWindowsSdkAfterInstall,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$LogPrefix = '[codex-pet-msix]'
$OutputRootWasExplicit = $PSBoundParameters.ContainsKey('OutputRoot')
$WindowsSdkBuildToolsPackageId = 'microsoft.windows.sdk.buildtools'
$WindowsSdkBuildToolsVersion = '10.0.26100.7705'
$WindowsSdkInstallTimeoutSeconds = 300
$script:InstalledWindowsSdkViaNuGet = $false
$script:InstalledWindowsSdkViaWinget = $false

function Write-Log {
  param([string]$Message)
  Write-Host "$LogPrefix $Message"
}

function Fail {
  param([string]$Message)
  throw "$LogPrefix error: $Message"
}

function Normalize-AppPath {
  param([string]$Candidate)
  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    return $null
  }
  $resolved = Resolve-Path -LiteralPath $Candidate -ErrorAction SilentlyContinue
  if ($resolved) {
    $Candidate = $resolved.ProviderPath
  }
  if ((Split-Path -Leaf $Candidate) -ne 'app') {
    $nested = Join-Path $Candidate 'app'
    if (Test-Path -LiteralPath $nested -PathType Container) {
      $Candidate = $nested
    }
  }
  return $Candidate
}

function Test-CodexAppPath {
  param([string]$Candidate)
  $app = Normalize-AppPath $Candidate
  return ($app -and
    (Test-Path -LiteralPath $app -PathType Container) -and
    (Test-Path -LiteralPath (Join-Path $app 'Codex.exe') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $app 'resources\app.asar') -PathType Leaf))
}

function Find-CodexAppPath {
  if ($AppPath) {
    $manual = Normalize-AppPath $AppPath
    if (-not (Test-CodexAppPath $manual)) {
      Fail "-AppPath is not a Codex app directory: $AppPath"
    }
    return $manual
  }

  $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1
  if ($package -and $package.InstallLocation) {
    $candidate = Join-Path $package.InstallLocation 'app'
    if (Test-CodexAppPath $candidate) {
      return (Normalize-AppPath $candidate)
    }
  }

  Fail 'could not find the Windows Store/MSIX Codex app. Pass -AppPath explicitly.'
}

function Resolve-OutputRoot {
  param(
    [Parameter(Mandatory = $true)][string]$Candidate,
    [bool]$WasExplicit
  )
  if ([string]::IsNullOrWhiteSpace($Candidate)) {
    Fail 'OutputRoot is empty'
  }

  $fullPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Candidate))
  $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue
  if ($item -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
    if ($WasExplicit) {
      Fail "OutputRoot must not be a reparse point: $fullPath"
    }
    $fullPath = Join-Path ([System.IO.Path]::GetTempPath()) 'codex-pet-msix-repack'
    Write-Log "warning: default OutputRoot is a reparse point; using $fullPath"
  }

  New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
  return (Resolve-Path -LiteralPath $fullPath -ErrorAction Stop).ProviderPath
}

function Get-PackageRoot {
  param([string]$App)
  return (Split-Path -Parent $App)
}

function Get-PackageShortId {
  param([string]$PackageRoot)
  $name = Split-Path -Leaf $PackageRoot
  if ($name -match '^(OpenAI\.Codex_[^_]+)_') {
    return $matches[1]
  }
  return $name
}

function Find-WindowsSdkTool {
  param([string]$ToolName)
  $roots = @(
    (Join-Path $env:TEMP 'codex-windows-sdk-buildtools'),
    (Join-Path $env:USERPROFILE ".nuget\packages\$WindowsSdkBuildToolsPackageId"),
    (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'),
    (Join-Path $env:ProgramFiles 'Windows Kits\10\bin')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  foreach ($root in $roots) {
    $hit = Get-ChildItem -LiteralPath $root -Recurse -File -Filter $ToolName -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\' } |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($hit) {
      return $hit.FullName
    }
  }
  return $null
}

function Remove-DirectoryRobust {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$RequiredRoot,
    [switch]$BestEffort
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
  $root = (Resolve-Path -LiteralPath $RequiredRoot -ErrorAction Stop).ProviderPath.TrimEnd('\')
  if ($resolved.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or
      -not $resolved.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Fail "refusing to remove a path outside the work root: $resolved"
  }
  try {
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
  } catch {
    if ($BestEffort) {
      Write-Log "warning: could not remove ${resolved}: $($_.Exception.Message)"
      return
    }
    Fail "could not remove ${resolved}: $($_.Exception.Message)"
  }
}

function Install-WindowsSdkBuildToolsViaNuGet {
  if ((Find-WindowsSdkTool 'makeappx.exe') -and (Find-WindowsSdkTool 'signtool.exe')) {
    return
  }
  $cacheRoot = Join-Path $env:TEMP 'codex-windows-sdk-buildtools'
  $packageRoot = Join-Path $cacheRoot $WindowsSdkBuildToolsVersion
  $packageId = $WindowsSdkBuildToolsPackageId.ToLowerInvariant()
  $nupkg = Join-Path $cacheRoot "$packageId.$WindowsSdkBuildToolsVersion.nupkg"
  $zip = Join-Path $cacheRoot "$packageId.$WindowsSdkBuildToolsVersion.zip"
  $url = "https://api.nuget.org/v3-flatcontainer/$packageId/$WindowsSdkBuildToolsVersion/$packageId.$WindowsSdkBuildToolsVersion.nupkg"

  New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
  if (Test-Path -LiteralPath $packageRoot) {
    Remove-DirectoryRobust -Path $packageRoot -RequiredRoot $cacheRoot
  }
  Write-Log "downloading Windows SDK BuildTools from NuGet: $WindowsSdkBuildToolsVersion"
  $oldProgress = $ProgressPreference
  try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing -TimeoutSec 120
  } finally {
    $ProgressPreference = $oldProgress
  }
  Copy-Item -LiteralPath $nupkg -Destination $zip -Force
  Expand-Archive -LiteralPath $zip -DestinationPath $packageRoot -Force
  Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

  if (-not ((Find-WindowsSdkTool 'makeappx.exe') -and (Find-WindowsSdkTool 'signtool.exe'))) {
    Fail "NuGet Windows SDK BuildTools did not provide required x64 MSIX tools: $packageRoot"
  }
  $script:InstalledWindowsSdkViaNuGet = $true
}

function Invoke-ProcessWithTimeout {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [int]$TimeoutSeconds,
    [string]$Description
  )
  Write-Log "$Description (timeout ${TimeoutSeconds}s)"
  $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    try { $process.Kill() } catch {}
    Fail "$Description timed out after ${TimeoutSeconds}s"
  }
  if ($process.ExitCode -ne 0) {
    Fail "$Description failed with exit code $($process.ExitCode)"
  }
}

function Install-WindowsSdkPrerequisites {
  try {
    Install-WindowsSdkBuildToolsViaNuGet
    return
  } catch {
    Write-Log "warning: NuGet Windows SDK BuildTools install failed: $($_.Exception.Message)"
  }

  $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $winget) {
    Fail 'makeappx.exe and signtool.exe are unavailable. Install Windows SDK manually, or rerun with -InstallPrerequisites when winget is available.'
  }
  Invoke-ProcessWithTimeout -FilePath $winget.Source -ArgumentList @(
    'install', '--id', 'Microsoft.WindowsSDK.10.0.26100', '-e', '--source', 'winget',
    '--accept-source-agreements', '--accept-package-agreements'
  ) -TimeoutSeconds $WindowsSdkInstallTimeoutSeconds -Description 'winget Windows SDK install'
  $script:InstalledWindowsSdkViaWinget = $true
}

function Require-WindowsSdkTool {
  param([string]$ToolName)
  $tool = Find-WindowsSdkTool $ToolName
  if (-not $tool -and $InstallPrerequisites) {
    Install-WindowsSdkPrerequisites
    $tool = Find-WindowsSdkTool $ToolName
  }
  if (-not $tool) {
    Fail "$ToolName not found. Re-run with -InstallPrerequisites or install the Windows SDK for this build."
  }
  return [string]$tool
}

function Copy-FileDataOnly {
  param([string]$Source, [string]$Destination)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  $input = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
  try {
    $output = [System.IO.File]::Open($Destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $input.CopyTo($output) } finally { $output.Dispose() }
  } finally {
    $input.Dispose()
  }
}

function Copy-DirectoryDataOnly {
  param([string]$Source, [string]$Destination)
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    $target = Join-Path $Destination $item.Name
    if ($item.PSIsContainer -and (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0)) {
      Copy-DirectoryDataOnly -Source $item.FullName -Destination $target
    } elseif ($item.PSIsContainer) {
      Fail "package layout contains an unsupported reparse directory: $($item.FullName)"
    } else {
      Copy-FileDataOnly -Source $item.FullName -Destination $target
    }
  }
}

function Copy-PackageLayout {
  param([string]$SourcePackageRoot, [string]$WorkPackageRoot, [string]$WorkRoot)
  if (Test-Path -LiteralPath $WorkPackageRoot) {
    if (-not $ForceRebuild) {
      if ($Install) {
        Fail "a previous work package exists at $WorkPackageRoot. Re-run with -ForceRebuild so original-backup.msix is created from a fresh package copy."
      }
      Write-Log "using existing work package layout: $WorkPackageRoot"
      return
    }
    Remove-DirectoryRobust -Path $WorkPackageRoot -RequiredRoot $WorkRoot
  }

  New-Item -ItemType Directory -Force -Path $WorkPackageRoot | Out-Null
  Write-Log "copying package layout to: $WorkPackageRoot"
  & robocopy.exe $SourcePackageRoot $WorkPackageRoot /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -gt 7) {
    Write-Log "warning: robocopy failed with exit code $LASTEXITCODE; retrying with data-only copy"
    Remove-DirectoryRobust -Path $WorkPackageRoot -RequiredRoot $WorkRoot
    New-Item -ItemType Directory -Force -Path $WorkPackageRoot | Out-Null
    Copy-DirectoryDataOnly -Source $SourcePackageRoot -Destination $WorkPackageRoot
  }
  if (-not (Test-Path -LiteralPath (Join-Path $WorkPackageRoot 'app\resources\app.asar') -PathType Leaf)) {
    Fail "package copy did not produce app.asar: $WorkPackageRoot"
  }
}

function Remove-OldPackageArtifacts {
  param([string]$WorkPackageRoot)
  foreach ($relative in @('AppxSignature.p7x', 'AppxBlockMap.xml', 'AppxMetadata\CodeIntegrity.cat')) {
    $path = Join-Path $WorkPackageRoot $relative
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Force
    }
  }
}

function Invoke-NpxAsar {
  param([string]$Action, [string]$Source, [string]$Target)
  $npx = Get-Command 'npx' -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $npx) {
    Fail 'npx was not found. Install Node.js for this build before running the patch.'
  }
  & $npx.Source --yes asar $Action $Source $Target
  if ($LASTEXITCODE -ne 0) {
    Fail "npx asar $Action failed with exit code $LASTEXITCODE"
  }
}

function Invoke-PatchAppAsar {
  param([string]$WorkAppPath, [string]$SourceAppPath, [string]$WorkDir)
  Fail 'no pet ASAR patch hook was loaded'
}

function Resolve-PatchHookPath {
  param([string]$Path)
  $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
  if (-not $resolved -or -not (Test-Path -LiteralPath $resolved.ProviderPath -PathType Leaf)) {
    Fail "PatchHookPath was not found: $Path"
  }
  return $resolved.ProviderPath
}

function Convert-BytesToHex {
  param([byte[]]$Bytes)
  return (($Bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-AsarHeaderSha256 {
  param([string]$AsarPath)
  $stream = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
  try {
    $pickleHeader = New-Object byte[] 16
    if ($stream.Read($pickleHeader, 0, 16) -ne 16) { Fail 'could not read the ASAR pickle header' }
    $headerSize = [BitConverter]::ToUInt32($pickleHeader, 12)
    if ($headerSize -le 0 -or $headerSize -gt ($stream.Length - 16)) { Fail "invalid ASAR JSON header size: $headerSize" }
    $headerBytes = New-Object byte[] $headerSize
    if ($stream.Read($headerBytes, 0, [int]$headerSize) -ne [int]$headerSize) { Fail 'could not read the ASAR JSON header' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (Convert-BytesToHex $sha.ComputeHash($headerBytes)) } finally { $sha.Dispose() }
  } finally {
    $stream.Dispose()
  }
}

function Update-CodexExeAsarIntegrity {
  param([string]$ExePath, [string]$AsarHash)
  $bytes = [System.IO.File]::ReadAllBytes($ExePath)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  $match = [regex]::Match($text, '\[\{"file":"resources\\\\app\.asar","alg":"SHA256","value":"([0-9a-fA-F]{64})"\}\]')
  if (-not $match.Success) {
    if ($text.Contains('app.asar')) { Fail 'could not find Electron ASAR integrity JSON inside Codex.exe' }
    Write-Log 'Codex.exe ASAR integrity JSON is not present; skipping executable integrity update'
    return
  }
  $oldHash = $match.Groups[1].Value
  if ($oldHash -eq $AsarHash) { return }
  $oldBytes = [System.Text.Encoding]::ASCII.GetBytes($oldHash)
  $newBytes = [System.Text.Encoding]::ASCII.GetBytes($AsarHash)
  $position = -1
  for ($i = 0; $i -le $bytes.Length - $oldBytes.Length; $i++) {
    $matched = $true
    for ($j = 0; $j -lt $oldBytes.Length; $j++) {
      if ($bytes[$i + $j] -ne $oldBytes[$j]) { $matched = $false; break }
    }
    if ($matched) { $position = $i; break }
  }
  if ($position -lt 0) { Fail 'could not locate the ASAR integrity hash bytes in Codex.exe' }
  [Array]::Copy($newBytes, 0, $bytes, $position, $newBytes.Length)
  [System.IO.File]::WriteAllBytes($ExePath, $bytes)
  Write-Log "updated Codex.exe ASAR integrity: $oldHash -> $AsarHash"
}

function Get-ManifestPublisher {
  param([string]$WorkPackageRoot)
  [xml]$manifest = Get-Content -Raw -LiteralPath (Join-Path $WorkPackageRoot 'AppxManifest.xml')
  return $manifest.Package.Identity.Publisher
}

function Get-OrCreateSigningCertificate {
  param([string]$Publisher)
  $cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $Publisher } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1
  if ($cert) { return $cert }
  Write-Log "creating CurrentUser signing certificate: $Publisher"
  return New-SelfSignedCertificate -Type CodeSigningCert -Subject $Publisher -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5)
}

function Trust-SigningCertificate {
  param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
  $tempCert = Join-Path $env:TEMP ('codex-pet-msix-' + $Cert.Thumbprint + '.cer')
  try {
    Export-Certificate -Cert $Cert -FilePath $tempCert -Force | Out-Null
    Import-Certificate -FilePath $tempCert -CertStoreLocation 'Cert:\CurrentUser\Root' | Out-Null
    Import-Certificate -FilePath $tempCert -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' | Out-Null
  } finally {
    Remove-Item -LiteralPath $tempCert -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-MakeAppxPack {
  param([string]$MakeAppx, [string]$WorkPackageRoot, [string]$MsixPath)
  if (Test-Path -LiteralPath $MsixPath) { Remove-Item -LiteralPath $MsixPath -Force }
  Write-Log "packing MSIX: $MsixPath"
  & $MakeAppx pack /d $WorkPackageRoot /p $MsixPath /o
  if ($LASTEXITCODE -ne 0) { Fail "makeappx pack failed with exit code $LASTEXITCODE" }
}

function Invoke-SignPackage {
  param([string]$SignTool, [string]$MsixPath, [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
  & $SignTool sign /fd SHA256 /sha1 $Cert.Thumbprint $MsixPath
  if ($LASTEXITCODE -ne 0) { Fail "signtool sign failed with exit code $LASTEXITCODE" }
}

function Assert-CodexIsClosedForInstall {
  $running = @(Get-Process -Name 'Codex', 'ChatGPT' -ErrorAction SilentlyContinue)
  if ($running.Count -gt 0) {
    $names = @($running | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
    Fail "installation stopped because Codex or ChatGPT is still running: $names. Close them normally, then rerun with -Install."
  }
}

function Install-PatchedPackage {
  param(
    [string]$MsixPath,
    [string]$BackupMsixPath
  )
  Assert-CodexIsClosedForInstall
  $existing = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($existing) {
    Write-Log "removing existing package while preserving application data: $($existing.PackageFullName)"
    Remove-AppxPackage -Package $existing.PackageFullName -PreserveApplicationData -ErrorAction Stop
  }
  Write-Log "installing patched MSIX: $MsixPath"
  try {
    Add-AppxPackage -Path $MsixPath -ErrorAction Stop
  } catch {
    $patchedError = $_
    Write-Log "patched package installation failed; attempting the signed original backup: $BackupMsixPath"
    try {
      Add-AppxPackage -Path $BackupMsixPath -ErrorAction Stop
    } catch {
      Fail "patched package and automatic backup restore both failed. User data was preserved. Restore manually with Add-AppxPackage -Path `"$BackupMsixPath`". Patched error: $($patchedError.Exception.Message). Backup error: $($_.Exception.Message)"
    }
    Fail "patched package installation failed, but the original backup was restored successfully: $($patchedError.Exception.Message)"
  }
  $installed = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | Select-Object -First 1
  if ($Launch -and -not $NoLaunch) {
    Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($installed.PackageFamilyName)!App"
  }
}

function Cleanup-WindowsSdk {
  if ($script:InstalledWindowsSdkViaNuGet) {
    $root = Join-Path $env:TEMP 'codex-windows-sdk-buildtools'
    if (Test-Path -LiteralPath $root) {
      Remove-DirectoryRobust -Path $root -RequiredRoot $env:TEMP -BestEffort
    }
  }
  if ($script:InstalledWindowsSdkViaWinget) {
    Write-Log 'Windows SDK was installed through winget and is retained for user-managed cleanup'
  }
}

$OutputRoot = Resolve-OutputRoot -Candidate $OutputRoot -WasExplicit $OutputRootWasExplicit
$resolvedPatchHook = Resolve-PatchHookPath $PatchHookPath
$script:PetAsarPatchHookLoaded = $false
. $resolvedPatchHook
if (-not $script:PetAsarPatchHookLoaded) {
  Fail "PatchHookPath must set PetAsarPatchHookLoaded and define Invoke-PatchAppAsar: $resolvedPatchHook"
}
Write-Log "loaded pet ASAR patch hook: $resolvedPatchHook"
$sourceApp = Find-CodexAppPath
$sourcePackageRoot = Get-PackageRoot $sourceApp
$packageShortId = Get-PackageShortId $sourcePackageRoot
$workRoot = Join-Path $OutputRoot $packageShortId
$workPackageRoot = Join-Path $workRoot 'package'
$workApp = Join-Path $workPackageRoot 'app'
$artifactsDir = Join-Path $workRoot 'artifacts'
$tempWork = Join-Path $workRoot ('work-' + [guid]::NewGuid().ToString('N'))
$backupMsixPath = Join-Path $artifactsDir ($packageShortId + '_original-backup.msix')
$patchedMsixPath = Join-Path $artifactsDir ($packageShortId + '_patched.msix')

Write-Log "source app: $sourceApp"
Write-Log "output root: $workRoot"
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null
New-Item -ItemType Directory -Force -Path $tempWork | Out-Null

try {
  Copy-PackageLayout -SourcePackageRoot $sourcePackageRoot -WorkPackageRoot $workPackageRoot -WorkRoot $workRoot
  Remove-OldPackageArtifacts $workPackageRoot

  $makeappx = $null
  $signtool = $null
  $cert = $null
  if (-not $DryRun) {
    $makeappx = Require-WindowsSdkTool 'makeappx.exe'
    $signtool = Require-WindowsSdkTool 'signtool.exe'
    $cert = Get-OrCreateSigningCertificate (Get-ManifestPublisher $workPackageRoot)
    Trust-SigningCertificate $cert
    if ($Install) {
      Write-Log "creating signed original backup before patching: $backupMsixPath"
      Invoke-MakeAppxPack $makeappx $workPackageRoot $backupMsixPath
      Invoke-SignPackage $signtool $backupMsixPath $cert
    }
  }

  $patched = Invoke-PatchAppAsar -WorkAppPath $workApp -SourceAppPath $sourceApp -WorkDir $tempWork
  if (-not $DryRun) {
    $asarHash = Get-AsarHeaderSha256 (Join-Path $workApp 'resources\app.asar')
    Write-Log "app.asar header sha256: $asarHash"
    Update-CodexExeAsarIntegrity -ExePath (Join-Path $workApp 'Codex.exe') -AsarHash $asarHash
    Invoke-MakeAppxPack $makeappx $workPackageRoot $patchedMsixPath
    Invoke-SignPackage $signtool $patchedMsixPath $cert
    Write-Log "patched MSIX: $patchedMsixPath"
    if ($Install) { Install-PatchedPackage -MsixPath $patchedMsixPath -BackupMsixPath $backupMsixPath }
  } else {
    Write-Log 'dry-run completed; no MSIX was signed or installed'
  }

  if ($CleanupWindowsSdkAfterInstall) { Cleanup-WindowsSdk }
  if ($CleanupAfter -and (Test-Path -LiteralPath $workPackageRoot)) {
    Remove-DirectoryRobust -Path $workPackageRoot -RequiredRoot $workRoot -BestEffort
    Write-Log "cleanup retained signed artifacts for rollback: $artifactsDir"
  }
  Write-Log 'done'
} finally {
  if ($KeepWorkDir) {
    Write-Log "keeping workdir: $tempWork"
  } elseif (Test-Path -LiteralPath $tempWork) {
    Remove-DirectoryRobust -Path $tempWork -RequiredRoot $workRoot -BestEffort
  }
}

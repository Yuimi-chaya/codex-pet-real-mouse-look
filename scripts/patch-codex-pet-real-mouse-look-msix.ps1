[CmdletBinding()]
param(
  [string]$AppPath,
  [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\codex-pet-real-mouse-look'),
  [string[]]$HumanTestedAppVersions = @('26.707.3748.0'),
  [switch]$SkipV2PetCheck,
  [switch]$InstallPrerequisites,
  [switch]$Install,
  [switch]$Launch,
  [switch]$NoLaunch,
  [switch]$ForceRebuild,
  [switch]$KeepWorkDir,
  [switch]$CleanupAfter,
  [switch]$CleanupWindowsSdkAfterInstall,
  [switch]$GenerateOnly,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$LogPrefix = '[codex-pet-look-patch]'

function Write-Log {
  param([string]$Message)
  Write-Host "$LogPrefix $Message"
}

function Fail {
  param([string]$Message)
  throw "$LogPrefix error: $Message"
}

function Write-Utf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-PetSpritesheetInfo {
  param(
    [Parameter(Mandatory = $true)][string]$ManifestDirectory,
    [string]$SpritesheetPath
  )

  if ([string]::IsNullOrWhiteSpace($SpritesheetPath)) {
    return [pscustomobject]@{ Path = ''; Exists = $false; Format = 'missing'; Supported = $false }
  }
  $path = [System.IO.Path]::GetFullPath((Join-Path $ManifestDirectory $SpritesheetPath))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{ Path = $path; Exists = $false; Format = 'missing'; Supported = $false }
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
  return [pscustomobject]@{ Path = $path; Exists = $true; Format = $format; Supported = $format -in @('png', 'webp') }
}

$basePatchScript = Join-Path $PSScriptRoot 'lib\msix-repack-base.ps1'
if (-not (Test-Path -LiteralPath $basePatchScript -PathType Leaf)) {
  Fail "base MSIX patch script not found: $basePatchScript"
}

$package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
  Sort-Object Version -Descending |
  Select-Object -First 1
if ($null -eq $package) {
  Fail 'OpenAI Codex App is not installed for the current Windows user'
}
$installedVersion = $package.Version.ToString()
if ($installedVersion -in $HumanTestedAppVersions) {
  Write-Log "Codex App version $installedVersion is human-tested; strict ASAR target validation is still required"
} else {
  Write-Log "Codex App version $installedVersion is not human-tested; proceeding only to strict ASAR target validation"
}

if (-not $SkipV2PetCheck) {
  $petsRoot = Join-Path $env:USERPROFILE '.codex\pets'
  $v2Pets = @()
  if (Test-Path -LiteralPath $petsRoot -PathType Container) {
    foreach ($manifest in Get-ChildItem -LiteralPath $petsRoot -Recurse -File -Filter 'pet.json' -ErrorAction SilentlyContinue) {
      try {
        $pet = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
        $spritesheet = Get-PetSpritesheetInfo -ManifestDirectory $manifest.DirectoryName -SpritesheetPath ([string]$pet.spritesheetPath)
        if ($pet.spriteVersionNumber -eq 2 -and $spritesheet.Supported) {
          $v2Pets += [pscustomobject]@{ Id = $pet.id; Manifest = $manifest.FullName; Spritesheet = $spritesheet.Path; Format = $spritesheet.Format }
        } elseif ($pet.spriteVersionNumber -eq 2) {
          Write-Log "warning: v2 pet has no recognized PNG or WebP spritesheet: $($manifest.FullName)"
        }
      } catch {
        Write-Log "warning: could not parse pet manifest: $($manifest.FullName)"
      }
    }
  }
  if ($v2Pets.Count -eq 0) {
    Fail 'No usable Codex v2 pet was found. Real-mouse look requires pet.json with spriteVersionNumber: 2 and a valid PNG or WebP spritesheet with look-direction rows.'
  }
  Write-Log "v2 pets: $(@($v2Pets | ForEach-Object { "$($_.Id) [$($_.Format)]" }) -join ', ')"
}

$generatedRoot = Join-Path $OutputRoot 'pet-look-wrapper'
New-Item -ItemType Directory -Force -Path $generatedRoot | Out-Null
$generatedPatchScript = Join-Path $generatedRoot 'patch_codex_pet_real_mouse_look_windows_msix.generated.ps1'
$petPatchHook = Join-Path $generatedRoot 'patch_codex_pet_real_mouse_look_asar_hook.ps1'
$baseContent = Get-Content -Raw -LiteralPath $basePatchScript

$petPatchFunction = @'
$script:PetAsarPatchHookLoaded = $true

function Invoke-PatchAppAsar {
  param(
    [string]$WorkAppPath,
    [string]$SourceAppPath,
    [string]$WorkDir
  )
  $asarPath = Join-Path $WorkAppPath 'resources\app.asar'
  $extractDir = Join-Path $WorkDir 'asar-extracted'
  $newAsarPath = Join-Path $WorkDir 'app.asar'

  if (Test-Path -LiteralPath $extractDir) {
    Remove-DirectoryRobust -Path $extractDir -RequiredRoot $WorkDir
  }
  if (Test-Path -LiteralPath $newAsarPath) {
    Remove-Item -LiteralPath $newAsarPath -Force
  }

  Write-Log 'extracting app.asar'
  Invoke-NpxAsar 'extract' $asarPath $extractDir

  $viteBuildDir = Join-Path $extractDir '.vite\build'
  if (-not (Test-Path -LiteralPath $viteBuildDir -PathType Container)) {
    Fail "vite build directory not found in extracted asar: $viteBuildDir"
  }

  $mainFiles = @(Get-ChildItem -LiteralPath $viteBuildDir -Filter 'main-*.js' -File -ErrorAction SilentlyContinue)
  if ($mainFiles.Count -eq 0) {
    Fail "main bundle not found under: $viteBuildDir"
  }

  $constructorTargetPattern = [regex]::new('this\.nativePositionController=new (?<controller>[A-Za-z_$][A-Za-z0-9_$]*)\(\{getCurrentWindow:\(\)=>this\.window,retryEnabled:this\.nativeCompositionSupported,setPosition:e=>this\.compositionHost\.setOverlayWindowPosition\(e\),shouldCancelWindowMoveResync:\(\)=>this\.layoutMode===`native`&&this\.isOverlayWindowPointerDragActive\(\)\}\),(?<subscription>[A-Za-z_$][A-Za-z0-9_$]*)\(e=>\{this\.setComputerUseCursorLocation\(e\)\}\)\}', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
  $classStartPattern = [regex]::new('class(?: [A-Za-z_$][A-Za-z0-9_$]*)?\{', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
  $screenCallPattern = [regex]::new('[A-Za-z_$][A-Za-z0-9_$]*\.screen\.getCursorScreenPoint\(\)', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
  $cursorFallbackPattern = [regex]::new('refreshCursorAtCurrentMousePosition\(e\)\{if\(e\.isDestroyed\(\)\)return!1;if\(this\.computerUseCursorPoint!=null\)return this\.sendCursorPointToAvatarOverlay\(e,this\.computerUseCursorPoint,!0\);let t=[^;]{1,400}\?\?(?<electron>[A-Za-z_$][A-Za-z0-9_$]*)\.screen\.getCursorScreenPoint\(\)', [System.Text.RegularExpressions.RegexOptions]::CultureInvariant)
  $constructorOldPatch = 'this.nativePositionController=new c5({getCurrentWindow:()=>this.window,retryEnabled:this.nativeCompositionSupported,setPosition:e=>this.compositionHost.setOverlayWindowPosition(e),shouldCancelWindowMoveResync:()=>this.layoutMode===`native`&&this.isOverlayWindowPointerDragActive()}),io(e=>{this.setComputerUseCursorLocation(e)}),this.realMouseLookTimer=setInterval(()=>{let e=this.window;e==null||e.isDestroyed()||!this.rendererReady||this.dragState!=null||this.computerUseCursorPoint!=null||this.sendComputerUseCursorLocationToRenderer(e)},100)}'
  $constructorPreviousPatch = 'this.nativePositionController=new c5({getCurrentWindow:()=>this.window,retryEnabled:this.nativeCompositionSupported,setPosition:e=>this.compositionHost.setOverlayWindowPosition(e),shouldCancelWindowMoveResync:()=>this.layoutMode===`native`&&this.isOverlayWindowPointerDragActive()}),io(e=>{this.setComputerUseCursorLocation(e)}),this.realMouseLookLastPoint=null,this.realMouseLookLastMoveMs=0,this.realMouseLookActive=!1,this.realMouseLookTimer=setInterval(()=>{let e=this.window;if(e==null||e.isDestroyed()||!this.rendererReady||this.dragState!=null||this.computerUseCursorPoint!=null)return;let t=c.screen.getCursorScreenPoint(),n=e.getContentBounds(),r=this.layout?.mascot??{left:0,top:0,width:n.width,height:n.height},i=n.x+r.left+r.width/2,a=n.y+r.top+r.height/2,o=Math.hypot(t.x-i,t.y-a),s=this.realMouseLookLastPoint,l=s==null?1/0:Math.hypot(t.x-s.x,t.y-s.y);l>=2&&(this.realMouseLookLastPoint={x:t.x,y:t.y},this.realMouseLookLastMoveMs=Date.now());let u=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400;u?(this.realMouseLookActive=!0,this.sendComputerUseCursorLocationToRenderer(e,t)):this.realMouseLookActive&&(this.realMouseLookActive=!1,this.sendComputerUseCursorLocationToRenderer(e,null))},100)}'
  $constructorPatch = 'this.nativePositionController=new c5({getCurrentWindow:()=>this.window,retryEnabled:this.nativeCompositionSupported,setPosition:e=>this.compositionHost.setOverlayWindowPosition(e),shouldCancelWindowMoveResync:()=>this.layoutMode===`native`&&this.isOverlayWindowPointerDragActive()}),io(e=>{this.setComputerUseCursorLocation(e)}),this.realMouseLookLastPoint=null,this.realMouseLookLastMoveMs=0,this.realMouseLookActive=!1,this.realMouseLookTimer=setInterval(()=>{let e=this.window;if(e==null||e.isDestroyed()||!this.rendererReady||this.dragState!=null||this.computerUseCursorPoint!=null)return;let t=c.screen.getCursorScreenPoint(),n=e.getContentBounds(),r=this.layout?.mascot??{left:0,top:0,width:n.width,height:n.height},i=n.x+r.left+r.width/2,a=n.y+r.top+r.height/2,o=Math.hypot(t.x-i,t.y-a),s=this.realMouseLookLastPoint,l=s==null?1/0:Math.hypot(t.x-s.x,t.y-s.y);l>=2&&(this.realMouseLookLastPoint={x:t.x,y:t.y},this.realMouseLookLastMoveMs=Date.now());let u=t.x>=n.x+r.left&&t.x<=n.x+r.left+r.width&&t.y>=n.y+r.top&&t.y<=n.y+r.top+r.height,h=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400&&!u;h?(this.realMouseLookActive=!0,this.sendComputerUseCursorLocationToRenderer(e,t)):this.realMouseLookActive&&(this.realMouseLookActive=!1,this.sendComputerUseCursorLocationToRenderer(e,null))},100)}'
  $constructorPatchSuffix = $constructorPatch.Substring($constructorPatch.IndexOf(',this.realMouseLookLastPoint=null', [System.StringComparison]::Ordinal))
  $senderTarget = 'sendComputerUseCursorLocationToRenderer(e){if(e.isDestroyed()||!this.rendererReady)return;let t=e.getContentBounds();this.windowManager.sendMessageToWebContents(e.webContents,{type:`avatar-overlay-computer-use-cursor-changed`,point:this.computerUseCursorPoint==null?null:{x:this.computerUseCursorPoint.x-t.x,y:this.computerUseCursorPoint.y-t.y}})}'
  $senderOldPatch = 'sendComputerUseCursorLocationToRenderer(e){if(e.isDestroyed()||!this.rendererReady)return;let t=e.getContentBounds(),n=this.computerUseCursorPoint??c.screen.getCursorScreenPoint();this.windowManager.sendMessageToWebContents(e.webContents,{type:`avatar-overlay-computer-use-cursor-changed`,point:n==null?null:{x:n.x-t.x,y:n.y-t.y}})}'
  $senderPatch = 'sendComputerUseCursorLocationToRenderer(e,t=this.computerUseCursorPoint){if(e.isDestroyed()||!this.rendererReady)return;let n=e.getContentBounds(),r=t;this.windowManager.sendMessageToWebContents(e.webContents,{type:`avatar-overlay-computer-use-cursor-changed`,point:r==null?null:{x:r.x-n.x,y:r.y-n.y}})}'

  $patchedFile = $null
  foreach ($file in $mainFiles) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $text = [System.IO.File]::ReadAllText($file.FullName, $utf8NoBom)
    if ($text.Contains('realMouseLookLastMoveMs') -and $text.Contains('h=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400&&!u')) {
      $normalizedExistingText = $screenCallPattern.Replace($text, 'c.screen.getCursorScreenPoint()')
      $existingConstructorCount = ($normalizedExistingText.Split(@($constructorPatchSuffix), [System.StringSplitOptions]::None).Length - 1)
      $existingSenderCount = ($text.Split(@($senderPatch), [System.StringSplitOptions]::None).Length - 1)
      if ($existingConstructorCount -ne 1 -or $existingSenderCount -ne 1) {
        Fail "existing pet patch target mismatch in $($file.FullName): constructor=$existingConstructorCount sender=$existingSenderCount"
      }
      $existingConstructorIndex = $normalizedExistingText.IndexOf($constructorPatchSuffix, [System.StringComparison]::Ordinal)
      $existingSenderIndex = $text.IndexOf($senderPatch, [System.StringComparison]::Ordinal)
      $existingConstructorClasses = $classStartPattern.Matches($text.Substring(0, $existingConstructorIndex + 1))
      $existingSenderClasses = $classStartPattern.Matches($text.Substring(0, $existingSenderIndex + 1))
      if ($existingConstructorClasses.Count -eq 0 -or $existingSenderClasses.Count -eq 0 -or
          $existingConstructorClasses[$existingConstructorClasses.Count - 1].Index -ne $existingSenderClasses[$existingSenderClasses.Count - 1].Index) {
        Fail "existing pet patch constructor and sender are not in the same class in $($file.FullName)"
      }
      $patchedFile = $file.FullName
      Write-Log "pet real mouse look patch already present: $patchedFile"
      break
    }

    $constructorSource = $null
    $constructorReplacement = $null
    $senderSource = $senderTarget
    $constructorMatches = $constructorTargetPattern.Matches($text)
    $constructorCount = $constructorMatches.Count
    $senderCount = ($text.Split(@($senderSource), [System.StringSplitOptions]::None).Length - 1)
    if ($constructorCount -eq 1 -and $senderCount -eq 1) {
      $constructorSource = $constructorMatches[0].Value
    } elseif ($constructorCount -eq 0 -and $senderCount -eq 0) {
      $constructorSource = $constructorOldPatch
      $constructorReplacement = $constructorPatch
      $senderSource = $senderOldPatch
      $constructorCount = ($text.Split(@($constructorSource), [System.StringSplitOptions]::None).Length - 1)
      $senderCount = ($text.Split(@($senderSource), [System.StringSplitOptions]::None).Length - 1)
    }
    if ($constructorCount -eq 0 -and $senderCount -eq 0) {
      $constructorSource = $constructorPreviousPatch
      $constructorReplacement = $constructorPatch
      $senderSource = $senderPatch
      $constructorCount = ($text.Split(@($constructorSource), [System.StringSplitOptions]::None).Length - 1)
      $senderCount = ($text.Split(@($senderSource), [System.StringSplitOptions]::None).Length - 1)
    }
    if ($constructorCount -eq 0 -and $senderCount -eq 0) {
      continue
    }
    if ($constructorCount -ne 1 -or $senderCount -ne 1) {
      Fail "pet look patch target count mismatch in $($file.FullName): constructor=$constructorCount sender=$senderCount"
    }
    if ([string]::IsNullOrEmpty($constructorSource)) {
      Fail "pet look patch target classification failed in $($file.FullName)"
    }

    $constructorIndex = $text.IndexOf($constructorSource, [System.StringComparison]::Ordinal)
    $senderIndex = $text.IndexOf($senderSource, [System.StringComparison]::Ordinal)
    $constructorClasses = $classStartPattern.Matches($text.Substring(0, $constructorIndex + 1))
    $senderClasses = $classStartPattern.Matches($text.Substring(0, $senderIndex + 1))
    if ($constructorIndex -lt 0 -or $senderIndex -le $constructorIndex -or $constructorClasses.Count -eq 0 -or $senderClasses.Count -eq 0) {
      Fail "pet look patch event-flow ordering mismatch in $($file.FullName)"
    }
    $constructorClassIndex = $constructorClasses[$constructorClasses.Count - 1].Index
    $senderClassIndex = $senderClasses[$senderClasses.Count - 1].Index
    if ($constructorClassIndex -ne $senderClassIndex) {
      Fail "pet look constructor and sender are not in the same class in $($file.FullName)"
    }

    if ([string]::IsNullOrEmpty($constructorReplacement)) {
      $cursorFallbackMatches = $cursorFallbackPattern.Matches($text)
      if ($cursorFallbackMatches.Count -ne 1) {
        Fail "pet look Electron cursor fallback mismatch in $($file.FullName): matches=$($cursorFallbackMatches.Count)"
      }
      $screenAlias = $cursorFallbackMatches[0].Groups['electron'].Value
      $dynamicSuffix = $constructorPatchSuffix.Replace('c.screen.getCursorScreenPoint()', "$screenAlias.screen.getCursorScreenPoint()")
      $constructorReplacement = $constructorSource.Substring(0, $constructorSource.Length - 1) + $dynamicSuffix
    }

    $text = $text.Replace($constructorSource, $constructorReplacement).Replace($senderSource, $senderPatch)
    [System.IO.File]::WriteAllText($file.FullName, $text, $utf8NoBom)
    $patchedFile = $file.FullName
    Write-Log "pet real mouse look patch result: patched $patchedFile"
    break
  }

  if ($null -eq $patchedFile) {
    Fail 'pet look patch target not found in main bundle'
  }

  $verify = [System.IO.File]::ReadAllText($patchedFile, (New-Object System.Text.UTF8Encoding($false)))
  $normalizedVerify = $screenCallPattern.Replace($verify, 'c.screen.getCursorScreenPoint()')
  $verifiedConstructorCount = ($normalizedVerify.Split(@($constructorPatchSuffix), [System.StringSplitOptions]::None).Length - 1)
  $verifiedSenderCount = ($verify.Split(@($senderPatch), [System.StringSplitOptions]::None).Length - 1)
  if ($verifiedConstructorCount -ne 1 -or $verifiedSenderCount -ne 1) {
    Fail "pet look patch verification failed after write: constructor=$verifiedConstructorCount sender=$verifiedSenderCount"
  }

  Write-Log 'repacking app.asar'
  Invoke-NpxAsar 'pack' $extractDir $newAsarPath
  Copy-Item -LiteralPath $newAsarPath -Destination $asarPath -Force
  return $true
}
'@

Write-Utf8NoBom -Path $petPatchHook -Content $petPatchFunction
Write-Utf8NoBom -Path $generatedPatchScript -Content $baseContent
Write-Log "generated pet ASAR hook: $petPatchHook"
Write-Log "generated MSIX repack script: $generatedPatchScript"

if ($GenerateOnly) {
  Write-Log 'generate-only requested; package copy, patch, signing, and installation were not started'
  return
}

$patchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $generatedPatchScript, '-OutputRoot', $OutputRoot, '-PatchHookPath', $petPatchHook)
if (-not [string]::IsNullOrWhiteSpace($AppPath)) {
  $patchArgs += @('-AppPath', $AppPath)
}
if ($InstallPrerequisites) { $patchArgs += '-InstallPrerequisites' }
if ($Install) { $patchArgs += '-Install' }
if ($Launch) { $patchArgs += '-Launch' }
if ($NoLaunch) { $patchArgs += '-NoLaunch' }
if ($ForceRebuild) { $patchArgs += '-ForceRebuild' }
if ($KeepWorkDir) { $patchArgs += '-KeepWorkDir' }
if ($CleanupAfter) { $patchArgs += '-CleanupAfter' }
if ($CleanupWindowsSdkAfterInstall) { $patchArgs += '-CleanupWindowsSdkAfterInstall' }
if ($DryRun) { $patchArgs += '-DryRun' }

Write-Log "running targeted patch script"
& powershell @patchArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if ($Install -and $Launch -and -not $NoLaunch) {
  Write-Log 'launching Codex via AppUserModelID'
  Start-Process -FilePath 'explorer.exe' -ArgumentList 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App'
}

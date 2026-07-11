[CmdletBinding()]
param(
  [string]$AppPath,
  [string]$OutputRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\codex-pet-real-mouse-look'),
  [string[]]$SupportedAppVersions = @('26.707.3748.0'),
  [switch]$AllowVersionMismatch,
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
if (-not $AllowVersionMismatch -and $installedVersion -notin $SupportedAppVersions) {
  Fail "Codex App version $installedVersion has not been audited. Supported: $($SupportedAppVersions -join ', '). Update this repository's compatibility matrix before using -AllowVersionMismatch."
}

if (-not $SkipV2PetCheck) {
  $petsRoot = Join-Path $env:USERPROFILE '.codex\pets'
  $v2Pets = @()
  if (Test-Path -LiteralPath $petsRoot -PathType Container) {
    foreach ($manifest in Get-ChildItem -LiteralPath $petsRoot -Recurse -File -Filter 'pet.json' -ErrorAction SilentlyContinue) {
      try {
        $pet = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json
        if ($pet.spriteVersionNumber -eq 2) {
          $v2Pets += [pscustomobject]@{ Id = $pet.id; Manifest = $manifest.FullName }
        }
      } catch {
        Write-Log "warning: could not parse pet manifest: $($manifest.FullName)"
      }
    }
  }
  if ($v2Pets.Count -eq 0) {
    Fail 'No Codex v2 pet was found. Real-mouse look requires pet.json with spriteVersionNumber: 2 and look-direction rows.'
  }
  Write-Log "v2 pets: $($v2Pets.Id -join ', ')"
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

  $constructorTarget = 'this.nativePositionController=new c5({getCurrentWindow:()=>this.window,retryEnabled:this.nativeCompositionSupported,setPosition:e=>this.compositionHost.setOverlayWindowPosition(e),shouldCancelWindowMoveResync:()=>this.layoutMode===`native`&&this.isOverlayWindowPointerDragActive()}),io(e=>{this.setComputerUseCursorLocation(e)})}'
  $constructorOldPatch = 'this.nativePositionController=new c5({getCurrentWindow:()=>this.window,retryEnabled:this.nativeCompositionSupported,setPosition:e=>this.compositionHost.setOverlayWindowPosition(e),shouldCancelWindowMoveResync:()=>this.layoutMode===`native`&&this.isOverlayWindowPointerDragActive()}),io(e=>{this.setComputerUseCursorLocation(e)}),this.realMouseLookTimer=setInterval(()=>{let e=this.window;e==null||e.isDestroyed()||!this.rendererReady||this.dragState!=null||this.computerUseCursorPoint!=null||this.sendComputerUseCursorLocationToRenderer(e)},100)}'
  $constructorPreviousPatch = 'this.nativePositionController=new c5({getCurrentWindow:()=>this.window,retryEnabled:this.nativeCompositionSupported,setPosition:e=>this.compositionHost.setOverlayWindowPosition(e),shouldCancelWindowMoveResync:()=>this.layoutMode===`native`&&this.isOverlayWindowPointerDragActive()}),io(e=>{this.setComputerUseCursorLocation(e)}),this.realMouseLookLastPoint=null,this.realMouseLookLastMoveMs=0,this.realMouseLookActive=!1,this.realMouseLookTimer=setInterval(()=>{let e=this.window;if(e==null||e.isDestroyed()||!this.rendererReady||this.dragState!=null||this.computerUseCursorPoint!=null)return;let t=c.screen.getCursorScreenPoint(),n=e.getContentBounds(),r=this.layout?.mascot??{left:0,top:0,width:n.width,height:n.height},i=n.x+r.left+r.width/2,a=n.y+r.top+r.height/2,o=Math.hypot(t.x-i,t.y-a),s=this.realMouseLookLastPoint,l=s==null?1/0:Math.hypot(t.x-s.x,t.y-s.y);l>=2&&(this.realMouseLookLastPoint={x:t.x,y:t.y},this.realMouseLookLastMoveMs=Date.now());let u=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400;u?(this.realMouseLookActive=!0,this.sendComputerUseCursorLocationToRenderer(e,t)):this.realMouseLookActive&&(this.realMouseLookActive=!1,this.sendComputerUseCursorLocationToRenderer(e,null))},100)}'
  $constructorPatch = 'this.nativePositionController=new c5({getCurrentWindow:()=>this.window,retryEnabled:this.nativeCompositionSupported,setPosition:e=>this.compositionHost.setOverlayWindowPosition(e),shouldCancelWindowMoveResync:()=>this.layoutMode===`native`&&this.isOverlayWindowPointerDragActive()}),io(e=>{this.setComputerUseCursorLocation(e)}),this.realMouseLookLastPoint=null,this.realMouseLookLastMoveMs=0,this.realMouseLookActive=!1,this.realMouseLookTimer=setInterval(()=>{let e=this.window;if(e==null||e.isDestroyed()||!this.rendererReady||this.dragState!=null||this.computerUseCursorPoint!=null)return;let t=c.screen.getCursorScreenPoint(),n=e.getContentBounds(),r=this.layout?.mascot??{left:0,top:0,width:n.width,height:n.height},i=n.x+r.left+r.width/2,a=n.y+r.top+r.height/2,o=Math.hypot(t.x-i,t.y-a),s=this.realMouseLookLastPoint,l=s==null?1/0:Math.hypot(t.x-s.x,t.y-s.y);l>=2&&(this.realMouseLookLastPoint={x:t.x,y:t.y},this.realMouseLookLastMoveMs=Date.now());let u=t.x>=n.x+r.left&&t.x<=n.x+r.left+r.width&&t.y>=n.y+r.top&&t.y<=n.y+r.top+r.height,h=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400&&!u;h?(this.realMouseLookActive=!0,this.sendComputerUseCursorLocationToRenderer(e,t)):this.realMouseLookActive&&(this.realMouseLookActive=!1,this.sendComputerUseCursorLocationToRenderer(e,null))},100)}'
  $senderTarget = 'sendComputerUseCursorLocationToRenderer(e){if(e.isDestroyed()||!this.rendererReady)return;let t=e.getContentBounds();this.windowManager.sendMessageToWebContents(e.webContents,{type:`avatar-overlay-computer-use-cursor-changed`,point:this.computerUseCursorPoint==null?null:{x:this.computerUseCursorPoint.x-t.x,y:this.computerUseCursorPoint.y-t.y}})}'
  $senderOldPatch = 'sendComputerUseCursorLocationToRenderer(e){if(e.isDestroyed()||!this.rendererReady)return;let t=e.getContentBounds(),n=this.computerUseCursorPoint??c.screen.getCursorScreenPoint();this.windowManager.sendMessageToWebContents(e.webContents,{type:`avatar-overlay-computer-use-cursor-changed`,point:n==null?null:{x:n.x-t.x,y:n.y-t.y}})}'
  $senderPatch = 'sendComputerUseCursorLocationToRenderer(e,t=this.computerUseCursorPoint){if(e.isDestroyed()||!this.rendererReady)return;let n=e.getContentBounds(),r=t;this.windowManager.sendMessageToWebContents(e.webContents,{type:`avatar-overlay-computer-use-cursor-changed`,point:r==null?null:{x:r.x-n.x,y:r.y-n.y}})}'

  $patchedFile = $null
  foreach ($file in $mainFiles) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $text = [System.IO.File]::ReadAllText($file.FullName, $utf8NoBom)
    if ($text.Contains('realMouseLookLastMoveMs') -and $text.Contains('h=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400&&!u')) {
      $existingConstructorCount = ($text.Split(@($constructorPatch), [System.StringSplitOptions]::None).Length - 1)
      $existingSenderCount = ($text.Split(@($senderPatch), [System.StringSplitOptions]::None).Length - 1)
      if ($existingConstructorCount -ne 1 -or $existingSenderCount -ne 1) {
        Fail "existing pet patch target mismatch in $($file.FullName): constructor=$existingConstructorCount sender=$existingSenderCount"
      }
      $patchedFile = $file.FullName
      Write-Log "pet real mouse look patch already present: $patchedFile"
      break
    }

    $constructorSource = $constructorTarget
    $senderSource = $senderTarget
    $constructorCount = ($text.Split(@($constructorSource), [System.StringSplitOptions]::None).Length - 1)
    $senderCount = ($text.Split(@($senderSource), [System.StringSplitOptions]::None).Length - 1)
    if ($constructorCount -eq 0 -and $senderCount -eq 0) {
      $constructorSource = $constructorOldPatch
      $senderSource = $senderOldPatch
      $constructorCount = ($text.Split(@($constructorSource), [System.StringSplitOptions]::None).Length - 1)
      $senderCount = ($text.Split(@($senderSource), [System.StringSplitOptions]::None).Length - 1)
    }
    if ($constructorCount -eq 0 -and $senderCount -eq 0) {
      $constructorSource = $constructorPreviousPatch
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

    $text = $text.Replace($constructorSource, $constructorPatch).Replace($senderSource, $senderPatch)
    [System.IO.File]::WriteAllText($file.FullName, $text, $utf8NoBom)
    $patchedFile = $file.FullName
    Write-Log "pet real mouse look patch result: patched $patchedFile"
    break
  }

  if ($null -eq $patchedFile) {
    Fail 'pet look patch target not found in main bundle'
  }

  $verify = [System.IO.File]::ReadAllText($patchedFile, (New-Object System.Text.UTF8Encoding($false)))
  if (-not ($verify.Contains('realMouseLookLastMoveMs') -and $verify.Contains('h=o<=480&&Date.now()-this.realMouseLookLastMoveMs<=1400&&!u'))) {
    Fail 'pet look patch verification failed after write'
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

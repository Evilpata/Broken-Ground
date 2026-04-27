# ============================================================
#  Broken Ground - Local Multiplayer Patch Script
#  Tüm yamalar bu script ile otomatik uygulanır.
#  Run as: Right-click → "Run with PowerShell"
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  BROKEN GROUND - LOCAL MULTIPLAYER PATCH   " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Find game directory ────────────────────────────────────────────────
$steamPaths = @(
    "D:\SteamLibrary\steamapps\common\Broken Ground",
    "C:\Program Files (x86)\Steam\steamapps\common\Broken Ground",
    "C:\Program Files\Steam\steamapps\common\Broken Ground",
    "E:\SteamLibrary\steamapps\common\Broken Ground",
    "F:\SteamLibrary\steamapps\common\Broken Ground"
)

$gameDir = $null
foreach ($p in $steamPaths) {
    if (Test-Path (Join-Path $p "BrokenGround.exe")) {
        $gameDir = $p
        break
    }
}

if (-not $gameDir) {
    Write-Host "Oyun klasörü bulunamadı! Lütfen yolu girin:" -ForegroundColor Yellow
    Write-Host "(örn: D:\SteamLibrary\steamapps\common\Broken Ground)" -ForegroundColor Gray
    $gameDir = Read-Host "Oyun yolu"
}

if (-not (Test-Path (Join-Path $gameDir "BrokenGround.exe"))) {
    Write-Host "HATA: BrokenGround.exe bulunamadı: $gameDir" -ForegroundColor Red
    Read-Host "Çıkmak için Enter'a basın"
    exit 1
}

$managedDir = Join-Path $gameDir "BrokenGround_Data\Managed"
$dllPath    = Join-Path $managedDir "Assembly-CSharp.dll"
$backupPath = Join-Path $managedDir "Assembly-CSharp.dll.backup"

Write-Host "Oyun klasörü: $gameDir" -ForegroundColor Green

# ── 2. Backup ─────────────────────────────────────────────────────────────
if (-not (Test-Path $backupPath)) {
    Copy-Item $dllPath $backupPath
    Write-Host "Yedek oluşturuldu: Assembly-CSharp.dll.backup" -ForegroundColor Green
} else {
    Write-Host "Yedek zaten mevcut, orijinal korunuyor." -ForegroundColor Gray
    # Always patch from the ORIGINAL backup
    Copy-Item $backupPath $dllPath -Force
    Write-Host "Orijinal DLL yüklendi (temiz patch yapılacak)" -ForegroundColor Gray
}

# ── 3. Download Mono.Cecil ─────────────────────────────────────────────────
$cecilDir  = Join-Path $env:TEMP "mono_cecil_bg"
$cecilPath = Join-Path $cecilDir "Mono.Cecil.dll"

if (-not (Test-Path $cecilPath)) {
    Write-Host "Mono.Cecil indiriliyor..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $cecilDir | Out-Null
    $nupkg = Join-Path $env:TEMP "mono.cecil.nupkg"
    Invoke-WebRequest "https://www.nuget.org/api/v2/package/Mono.Cecil/0.11.5" -OutFile $nupkg
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($nupkg)
    $entry = $zip.Entries | Where-Object { $_.FullName -eq "lib/net40/Mono.Cecil.dll" }
    $stream = $entry.Open()
    $fs = [System.IO.File]::Create($cecilPath)
    $stream.CopyTo($fs)
    $fs.Close(); $stream.Close(); $zip.Dispose()
    Remove-Item $nupkg
    Write-Host "Mono.Cecil indirildi." -ForegroundColor Green
}

Add-Type -Path $cecilPath

# ── 4. Load DLL ───────────────────────────────────────────────────────────
$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($managedDir)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$rp.ReadSymbols = $false
$module = [Mono.Cecil.ModuleDefinition]::ReadModule($dllPath, $rp)

Write-Host "DLL yüklendi: $([System.IO.Path]::GetFileName($dllPath))" -ForegroundColor Green

# ── Helper: make method return true ───────────────────────────────────────
function PatchReturnTrue($method) {
    $method.Body.Instructions.Clear()
    $method.Body.Variables.Clear()
    $method.Body.ExceptionHandlers.Clear()
    $p = $method.Body.GetILProcessor()
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ret))
}

# ── Helper: make method return void (nop) ─────────────────────────────────
function PatchReturnVoid($method) {
    $method.Body.Instructions.Clear()
    $method.Body.Variables.Clear()
    $method.Body.ExceptionHandlers.Clear()
    $p = $method.Body.GetILProcessor()
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ret))
}

# ── Helper: env var import ─────────────────────────────────────────────────
$getEnvRef      = $module.ImportReference([System.Environment].GetMethod("GetEnvironmentVariable",[Type[]]@([string])))
$strEqRef       = $module.ImportReference([string].GetMethod("op_Equality",[Type[]]@([string],[string])))
$isNullEmptyRef = $module.ImportReference([string].GetMethod("IsNullOrEmpty",[Type[]]@([string])))

# ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Yamalar uygulanıyor..." -ForegroundColor Cyan

# ── Types ──────────────────────────────────────────────────────────────────
$loginType   = $module.Types | Where-Object { $_.Name -eq "Login" }
$scType      = $module.Types | Where-Object { $_.Name -eq "SteamConnect" }
$gmType      = $module.Types | Where-Object { $_.Name -eq "GameManager" }
$slType      = $module.Types | Where-Object { $_.Name -eq "SaveLoad" }
$pdType      = $module.Types | Where-Object { $_.Name -eq "PlayerData" }
$unlType     = $module.Types | Where-Object { $_.Name -eq "Unlockable" }
$pfType      = $module.Types | Where-Object { $_.Name -eq "ProfanityFilter" }
$loadingType = $module.Types | Where-Object { $_.Name -eq "Loading" }
$fjType      = $module.Types | Where-Object { $_.Name -eq "FindGame" }
$jgType      = $module.Types | Where-Object { $_.Name -eq "JoinGame" }
$srType      = $module.Types | Where-Object { $_.Name -eq "ServiceRoom" }
$tnetType    = $module.Types | Where-Object { $_.Name -eq "TNetConnectionHandler" }
$tnsType     = $module.Types | Where-Object { $_.FullName -eq "TNet.TNServerInstance" }
$tnmType     = $module.Types | Where-Object { $_.FullName -eq "TNet.TNManager" }
$evtType     = $module.Types | Where-Object { $_.Name -eq "EventManager" }

# ── Fields ─────────────────────────────────────────────────────────────────
$gmSessionFld   = $gmType.Fields | Where-Object { $_.Name -eq "sessionTicket" }
$gmOfflineFld   = $gmType.Fields | Where-Object { $_.Name -eq "offlineMode" }
$gmPlayerFld    = $gmType.Fields | Where-Object { $_.Name -eq "loggedInPlayerData" }
$gmMatchFld     = $gmType.Fields | Where-Object { $_.Name -eq "matchmakeTicket" }
$loggingInFld   = $loginType.Fields | Where-Object { $_.Name -eq "loggingIn" }
$hasPro         = $pdType.Fields | Where-Object { $_.Name -eq "hasPro" }
$displayNameFld = $pdType.Fields | Where-Object { $_.Name -eq "_displayName" }

# ── Methods ────────────────────────────────────────────────────────────────
$loadUserData    = $slType.Methods    | Where-Object { $_.Name -eq "LoadUserData" }
$pdCtorMth       = $pdType.Methods    | Where-Object { $_.Name -eq ".ctor" -and $_.Parameters.Count -eq 0 }
$initUnlocksMth  = $pdType.Methods    | Where-Object { $_.Name -eq "InitialiseUnlocks" }
$gotoMenuLoginMth= $loginType.Methods | Where-Object { $_.Name -eq "GotoMenu" }
$gotoMenuScMth   = $scType.Methods    | Where-Object { $_.Name -eq "GotoMenu" }
$lpfab2p         = $loginType.Methods | Where-Object { $_.Name -eq "LoginPlayFab" -and $_.Parameters.Count -eq 2 }
$attemptAuth     = $scType.Methods    | Where-Object { $_.Name -eq "AttemptAuth" }
$cwsMth          = $scType.Methods    | Where-Object { $_.Name -eq "ConnectWithSteam" }
$showMth         = $loadingType.Methods | Where-Object { $_.Name -eq "Show" -and $_.Parameters.Count -eq 2 }
$hideMth         = $loadingType.Methods | Where-Object { $_.Name -eq "Hide" }
$startMth        = $loginType.Methods | Where-Object { $_.Name -eq "Start" }
$cleanMth        = $pfType.Methods    | Where-Object { $_.Name -eq "Clean" -and $_.Parameters.Count -eq 1 }
$checkPlayerData = ($module.Types | Where-Object { $_.Name -eq "Common" }).Methods | Where-Object { $_.Name -eq "CheckPlayerData" }
$regPlayerData   = ($module.Types | Where-Object { $_.Name -eq "Players" }).Methods | Where-Object { $_.Name -eq "RegisterPlayerData" }

# Helper for env-var bypass body (used in multiple methods)
function ApplyEnvBypassBody($method, $gotoMenuRef) {
    $method.Body.Instructions.Clear()
    $method.Body.Variables.Clear()
    $method.Body.ExceptionHandlers.Clear()
    $method.Body.InitLocals = $true
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.ImportReference($pdType))))

    $p = $method.Body.GetILProcessor()
    $stloc0 = $p.Create([Mono.Cecil.Cil.OpCodes]::Stloc_0)
    $stloc1 = $p.Create([Mono.Cecil.Cil.OpCodes]::Stloc_1)
    $ldarg0g= $p.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
    $retIns = $p.Create([Mono.Cecil.Cil.OpCodes]::Ret)

    # ip = GetEnv("BG_IP") ?? ""
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_IP"))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $stloc0))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))
    $p.Append($stloc0)
    # mode = GetEnv("BG_MODE") ?? "host"
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_MODE"))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $stloc1))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "host"))
    $p.Append($stloc1)
    # SaveLoad.LoadUserData(); pd = new PlayerData()
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($loadUserData)))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Newobj, $module.ImportReference($pdCtorMth)))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Stloc_2))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_2))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $module.ImportReference($gmPlayerFld)))
    # sessionTicket = ip
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $module.ImportReference($gmSessionFld)))
    # pd.InitialiseUnlocks()
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_2))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($initUnlocksMth)))
    # if (mode == "single") offlineMode = true
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_1))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "single"))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Call, $strEqRef))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $ldarg0g))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $module.ImportReference($gmOfflineFld)))
    # this.GotoMenu()
    $p.Append($ldarg0g)
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Call, $gotoMenuRef))
    $p.Append($retIns)
}

# === PATCH 1: ServiceRoom.ConnectToServiceRoom → nop ===
PatchReturnVoid ($srType.Methods | Where-Object { $_.Name -eq "ConnectToServiceRoom" })
Write-Host "  [1] ServiceRoom.ConnectToServiceRoom → nop" -ForegroundColor Green

# === PATCH 2: FindGame.CheckIfServerIsShutDown → onSuccess() ===
$fj_check = $fjType.Methods | Where-Object { $_.Name -eq "CheckIfServerIsShutDown" }
$fj_check.Body.Instructions.Clear(); $fj_check.Body.Variables.Clear(); $fj_check.Body.ExceptionHandlers.Clear()
$p2 = $fj_check.Body.GetILProcessor()
$p2.Append($p2.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$invokeRef = $module.ImportReference(([System.Action]).GetMethod("Invoke"))
$p2.Append($p2.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $invokeRef))
$p2.Append($p2.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host "  [2] FindGame.CheckIfServerIsShutDown → onSuccess()" -ForegroundColor Green

# === PATCH 3: JoinGame.CheckIfServerIsShutDown → onSuccess() ===
$jg_check = $jgType.Methods | Where-Object { $_.Name -eq "CheckIfServerIsShutDown" }
$jg_check.Body.Instructions.Clear(); $jg_check.Body.Variables.Clear(); $jg_check.Body.ExceptionHandlers.Clear()
$p3 = $jg_check.Body.GetILProcessor()
$p3.Append($p3.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$p3.Append($p3.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $invokeRef))
$p3.Append($p3.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host "  [3] JoinGame.CheckIfServerIsShutDown → onSuccess()" -ForegroundColor Green

# === PATCH 4: Login.LoginPlayFab(string,string) → env-var bypass ===
ApplyEnvBypassBody $lpfab2p $module.ImportReference($gotoMenuLoginMth)
Write-Host "  [4] Login.LoginPlayFab(s,s) → env-var bypass" -ForegroundColor Green

# === PATCH 5: Login.Start() → auto-login if BG_MODE set ===
$sp5 = $startMth.Body.GetILProcessor()
$firstOrig = $startMth.Body.Instructions[0]
$i1 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,  "BG_MODE")
$i2 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Call,   $getEnvRef)
$i3 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Call,   $isNullEmptyRef)
$i4 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $firstOrig)
$i5 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
$i6 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,  "")
$i7 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,  "")
$i8 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Call,   $module.ImportReference($lpfab2p))
$i9 = $sp5.Create([Mono.Cecil.Cil.OpCodes]::Ret)
foreach ($ins in @($i1,$i2,$i3,$i4,$i5,$i6,$i7,$i8,$i9)) { $sp5.InsertBefore($firstOrig,$ins) }
Write-Host "  [5] Login.Start() → auto-login on BG_MODE env var" -ForegroundColor Green

# === PATCH 6: SteamConnect.AttemptAuth() → env-var bypass ===
ApplyEnvBypassBody $attemptAuth $module.ImportReference($gotoMenuScMth)
Write-Host "  [6] SteamConnect.AttemptAuth() → env-var bypass" -ForegroundColor Green

# === PATCH 7: SteamConnect.ConnectWithSteam() → skip SteamManager check ===
$cwsMth.Body.Instructions.Clear(); $cwsMth.Body.Variables.Clear(); $cwsMth.Body.ExceptionHandlers.Clear()
$p7 = $cwsMth.Body.GetILProcessor()
$p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Connecting..."))
$p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
$p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($showMth)))
$p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($attemptAuth)))
$p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host "  [7] SteamConnect.ConnectWithSteam() → skip Steam check" -ForegroundColor Green

# === PATCH 8: Unlockable.IsUnlocked() → always true ===
PatchReturnTrue ($unlType.Methods | Where-Object { $_.Name -eq "IsUnlocked" })
Write-Host "  [8] Unlockable.IsUnlocked() → always true" -ForegroundColor Green

# === PATCH 9: PlayerData.IsItemOwned() → always true ===
PatchReturnTrue ($pdType.Methods | Where-Object { $_.Name -eq "IsItemOwned" })
Write-Host "  [9] PlayerData.IsItemOwned() → always true" -ForegroundColor Green

# === PATCH 10: PlayerData.OwnsAnyWeaponPack() → always true ===
PatchReturnTrue ($pdType.Methods | Where-Object { $_.Name -eq "OwnsAnyWeaponPack" })
Write-Host "  [10] PlayerData.OwnsAnyWeaponPack() → always true" -ForegroundColor Green

# === PATCH 11: PlayerData.InitialiseUnlocks() → set hasPro=true + displayName ===
$initM = $pdType.Methods | Where-Object { $_.Name -eq "InitialiseUnlocks" }
$ilpI  = $initM.Body.GetILProcessor()
$firstI = $initM.Body.Instructions[0]

$storeNameIns = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $module.ImportReference($displayNameFld))
$storeProIns  = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $module.ImportReference($hasPro))

# Prepend: this._displayName = GetEnv("BG_NAME") ?? "Player1"
$n = @(
    $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0),
    $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_NAME"),
    $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef),
    $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Dup),
    $storeNameIns,
    $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Pop),
    $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Player1")
)
$brNotNull = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $storeNameIns)
$n[3] = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Dup)

$a0 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
$a1 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_NAME")
$a2 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef)
$a3 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Dup)
$a4 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $storeNameIns)
$a5 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Pop)
$a6 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Player1")

# hasPro = true
$b0 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
$b1 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1)

foreach ($ins in @($a0,$a1,$a2,$a3,$a4,$a5,$a6,$storeNameIns,$b0,$b1,$storeProIns)) {
    $ilpI.InsertBefore($firstI, $ins)
}
Write-Host "  [11] PlayerData.InitialiseUnlocks() → hasPro=true + displayName from env" -ForegroundColor Green

# === PATCH 12: PlayerData.get_displayName() → fallback to BG_NAME ===
$getDispM = $pdType.Methods | Where-Object { $_.Name -eq "get_displayName" }
$getDispM.Body.Instructions.Clear(); $getDispM.Body.Variables.Clear(); $getDispM.Body.ExceptionHandlers.Clear()
$getDispM.Body.InitLocals = $true
$getDispM.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))
$cleanRef  = $module.ImportReference($cleanMth)
$gp = $getDispM.Body.GetILProcessor()
$tail_ldloc = $gp.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0)
$stloc0d    = $gp.Create([Mono.Cecil.Cil.OpCodes]::Stloc_0)
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $module.ImportReference($displayNameFld)))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Stloc_0))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Call, $isNullEmptyRef))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $tail_ldloc))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_NAME"))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $stloc0d))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Player1"))
$gp.Append($stloc0d)
$gp.Append($tail_ldloc)
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Call, $cleanRef))
$gp.Append($gp.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host "  [12] PlayerData.get_displayName() → fallback to BG_NAME env var" -ForegroundColor Green

# ── 5. Write patched DLL ───────────────────────────────────────────────────
$tempPath = $dllPath + ".patching"
$wp = New-Object Mono.Cecil.WriterParameters
$module.Write($tempPath, $wp)
$module.Dispose()
Copy-Item $tempPath $dllPath -Force
Remove-Item $tempPath

# ── 6. Copy launcher ───────────────────────────────────────────────────────
$launcherSrc = Join-Path $PSScriptRoot "BrokenGroundLauncher.exe"
$launcherDst = Join-Path $gameDir "BrokenGroundLauncher.exe"
if (Test-Path $launcherSrc) {
    Copy-Item $launcherSrc $launcherDst -Force
    Write-Host "  [+] BrokenGroundLauncher.exe kopyalandı" -ForegroundColor Green
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  PATCH TAMAMLANDI!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Oyunu BrokenGroundLauncher.exe ile başlat!" -ForegroundColor Yellow
Write-Host "  - İsim gir"
Write-Host "  - HOST GAME: sen sunucu kurarsın"
Write-Host "  - JOIN GAME: arkadaşın IP'sini gir ve bağlan"
Write-Host ""
Write-Host "ZeroTier ile internet üzerinden de oynanabilir!" -ForegroundColor Cyan
Write-Host ""
Read-Host "Çıkmak için Enter'a basın"

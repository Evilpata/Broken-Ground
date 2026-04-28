# ============================================================
#  Broken Ground - Local Multiplayer Patch Script v2
#  Tüm yamalar + Goldberg Steam Emulator otomatik kurulur.
#  Run as: Right-click -> "Run with PowerShell"
#  Or: patch.ps1 -GameDir "C:\path\to\Broken Ground"
# ============================================================

param(
    [string]$GameDir = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  BROKEN GROUND - LOCAL MULTIPLAYER PATCH   " -ForegroundColor Cyan
Write-Host "         v2  (Goldberg Steam + DLL Patch)   " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Find game directory ────────────────────────────────────────────────

# If launched from BrokenGroundGame.exe, GameDir is passed directly
$gameDir = $GameDir.Trim('"').Trim("'")

if (-not $gameDir) {
    # 1) Script'in yanında mı? (patch.ps1 oyun klasörüne koyulduysa)
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ($scriptDir -and (Test-Path (Join-Path $scriptDir "BrokenGround.exe") -ErrorAction SilentlyContinue)) {
        $gameDir = $scriptDir
    }
}

if (-not $gameDir) {
    # 2) Tüm sürücülerdeki yaygın yolları tara
    $existingDrives = (Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)

    $relPaths = @(
        "SteamLibrary\steamapps\common\Broken Ground",
        "Steam\steamapps\common\Broken Ground",
        "Program Files (x86)\Steam\steamapps\common\Broken Ground",
        "Program Files\Steam\steamapps\common\Broken Ground",
        "Games\Broken Ground",
        "Broken Ground"
    )

    foreach ($drive in $existingDrives) {
        foreach ($rel in $relPaths) {
            $candidate = Join-Path $drive $rel
            if (Test-Path (Join-Path $candidate "BrokenGround.exe") -ErrorAction SilentlyContinue) {
                $gameDir = $candidate; break
            }
        }
        if ($gameDir) { break }
    }
}

if (-not $gameDir) {
    # 3) Tüm kullanıcı profillerindeki Desktop / OneDrive\Desktop yollarını tara
    $usersRoot = "C:\Users"
    if (Test-Path $usersRoot) {
        $userDirs = Get-ChildItem $usersRoot -Directory -ErrorAction SilentlyContinue
        $desktopRels = @(
            "Desktop\Broken Ground",
            "OneDrive\Desktop\Broken Ground",
            "Desktop\BrokenGround",
            "OneDrive\Desktop\BrokenGround"
        )
        foreach ($u in $userDirs) {
            foreach ($rel in $desktopRels) {
                $candidate = Join-Path $u.FullName $rel
                if (Test-Path (Join-Path $candidate "BrokenGround.exe") -ErrorAction SilentlyContinue) {
                    $gameDir = $candidate; break
                }
            }
            if ($gameDir) { break }
        }
    }
}

if (-not $gameDir) {
    # Last resort: ask user (only works when run manually, not from EXE)
    Write-Host ""
    Write-Host "Oyun klasoru otomatik bulunamadi!" -ForegroundColor Yellow
    Write-Host "Oyunun kurulu oldugu klasoru tam yoluyla girin." -ForegroundColor Gray
    Write-Host "(ornek: C:\Program Files (x86)\Steam\steamapps\common\Broken Ground)" -ForegroundColor Gray
    Write-Host ""
    try {
        $gameDir = Read-Host "Oyun klasoru"
        $gameDir = $gameDir.Trim('"').Trim("'")
    } catch {
        Write-Host "HATA: Otomatik modda calistirildi, oyun klasoru bulunamadi." -ForegroundColor Red
        Write-Host "BrokenGroundGame.exe oyun klasorunde mi? Kontrol edin." -ForegroundColor Yellow
        exit 1
    }
}

if (-not (Test-Path (Join-Path $gameDir "BrokenGround.exe"))) {
    Write-Host ""
    Write-Host "HATA: BrokenGround.exe bulunamadi: $gameDir" -ForegroundColor Red
    Write-Host "Dogru klasoru girdiginizden emin olun." -ForegroundColor Red
    Read-Host "Cikmak icin Enter'a basin"
    exit 1
}

$managedDir = Join-Path $gameDir "BrokenGround_Data\Managed"
$dllPath    = Join-Path $managedDir "Assembly-CSharp.dll"
$backupPath = Join-Path $managedDir "Assembly-CSharp.dll.backup"

Write-Host "Oyun klasoru: $gameDir" -ForegroundColor Green

# ── 2. Backup DLL ─────────────────────────────────────────────────────────
if (-not (Test-Path $backupPath)) {
    Copy-Item $dllPath $backupPath
    Write-Host "Yedek olusturuldu: Assembly-CSharp.dll.backup" -ForegroundColor Green
} else {
    Write-Host "Yedekten temiz DLL yukleniyor..." -ForegroundColor Gray
    Copy-Item $backupPath $dllPath -Force
}

# ── 3. Download Mono.Cecil ─────────────────────────────────────────────────
$cecilDir  = Join-Path $env:TEMP "mono_cecil_bg"
$cecilPath = Join-Path $cecilDir "Mono.Cecil.dll"

if (-not (Test-Path $cecilPath)) {
    Write-Host "Mono.Cecil indiriliyor (NuGet)..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $cecilDir | Out-Null
    try {
        $nupkg = Join-Path $env:TEMP "mono.cecil.nupkg"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest "https://www.nuget.org/api/v2/package/Mono.Cecil/0.11.5" -OutFile $nupkg -UseBasicParsing
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($nupkg)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq "lib/net40/Mono.Cecil.dll" }
        if (-not $entry) { throw "lib/net40/Mono.Cecil.dll NuGet paketinde bulunamadi" }
        $stream = $entry.Open()
        $fs = [System.IO.File]::Create($cecilPath)
        $stream.CopyTo($fs)
        $fs.Close(); $stream.Close(); $zip.Dispose()
        Remove-Item $nupkg -ErrorAction SilentlyContinue
        Write-Host "Mono.Cecil indirildi." -ForegroundColor Green
    } catch {
        Write-Host "HATA: Mono.Cecil indirilemedi: $_" -ForegroundColor Red
        Write-Host "Internet baglantinizi kontrol edin." -ForegroundColor Yellow
        Read-Host "Cikmak icin Enter'a basin"
        exit 1
    }
}

Add-Type -Path $cecilPath

# ── 4. Load DLL ───────────────────────────────────────────────────────────
Write-Host "DLL yukleniyor..." -ForegroundColor Gray
$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory($managedDir)
$rp = New-Object Mono.Cecil.ReaderParameters
$rp.AssemblyResolver = $resolver
$rp.ReadSymbols = $false
$module = [Mono.Cecil.ModuleDefinition]::ReadModule($dllPath, $rp)
Write-Host "DLL yuklendi." -ForegroundColor Green

# ── Helpers ───────────────────────────────────────────────────────────────
function PatchReturnTrue($method) {
    $method.Body.Instructions.Clear()
    $method.Body.Variables.Clear()
    $method.Body.ExceptionHandlers.Clear()
    $p = $method.Body.GetILProcessor()
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ret))
}

function PatchReturnVoid($method) {
    $method.Body.Instructions.Clear()
    $method.Body.Variables.Clear()
    $method.Body.ExceptionHandlers.Clear()
    $p = $method.Body.GetILProcessor()
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ret))
}

$getEnvRef      = $module.ImportReference([System.Environment].GetMethod("GetEnvironmentVariable",[Type[]]@([string])))
$strEqRef       = $module.ImportReference([string].GetMethod("op_Equality",[Type[]]@([string],[string])))
$isNullEmptyRef = $module.ImportReference([string].GetMethod("IsNullOrEmpty",[Type[]]@([string])))

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

# ── Fields ─────────────────────────────────────────────────────────────────
$gmSessionFld   = $gmType.Fields  | Where-Object { $_.Name -eq "sessionTicket" }
$gmOfflineFld   = $gmType.Fields  | Where-Object { $_.Name -eq "offlineMode" }
$gmPlayerFld    = $gmType.Fields  | Where-Object { $_.Name -eq "loggedInPlayerData" }
$hasPro         = $pdType.Fields  | Where-Object { $_.Name -eq "hasPro" }
$displayNameFld = $pdType.Fields  | Where-Object { $_.Name -eq "_displayName" }

# ── Methods ────────────────────────────────────────────────────────────────
$loadUserData     = $slType.Methods    | Where-Object { $_.Name -eq "LoadUserData" }
$pdCtorMth        = $pdType.Methods    | Where-Object { $_.Name -eq ".ctor" -and $_.Parameters.Count -eq 0 }
$initUnlocksMth   = $pdType.Methods    | Where-Object { $_.Name -eq "InitialiseUnlocks" }
$gotoMenuLoginMth = $loginType.Methods | Where-Object { $_.Name -eq "GotoMenu" }
$gotoMenuScMth    = $scType.Methods    | Where-Object { $_.Name -eq "GotoMenu" }
$lpfab2p          = $loginType.Methods | Where-Object { $_.Name -eq "LoginPlayFab" -and $_.Parameters.Count -eq 2 }
$attemptAuth      = $scType.Methods    | Where-Object { $_.Name -eq "AttemptAuth" }
$cwsMth           = $scType.Methods    | Where-Object { $_.Name -eq "ConnectWithSteam" }
$showMth          = $loadingType.Methods | Where-Object { $_.Name -eq "Show" -and $_.Parameters.Count -eq 2 }
$startMth         = $loginType.Methods | Where-Object { $_.Name -eq "Start" }
$cleanMth         = $pfType.Methods    | Where-Object { $_.Name -eq "Clean" -and $_.Parameters.Count -eq 1 }

# ── Env-var bypass body (Login + SteamConnect) ────────────────────────────
function ApplyEnvBypassBody($method, $gotoMenuRef) {
    $method.Body.Instructions.Clear()
    $method.Body.Variables.Clear()
    $method.Body.ExceptionHandlers.Clear()
    $method.Body.InitLocals = $true
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))  # 0 = ip
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))  # 1 = mode
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.ImportReference($pdType)))) # 2 = pd

    $p = $method.Body.GetILProcessor()
    $stloc0  = $p.Create([Mono.Cecil.Cil.OpCodes]::Stloc_0)
    $stloc1  = $p.Create([Mono.Cecil.Cil.OpCodes]::Stloc_1)
    $ldarg0  = $p.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
    $retIns  = $p.Create([Mono.Cecil.Cil.OpCodes]::Ret)

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

    # GameManager.loggedInPlayerData = pd
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_2))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $module.ImportReference($gmPlayerFld)))

    # GameManager.sessionTicket = ip
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $module.ImportReference($gmSessionFld)))

    # pd.InitialiseUnlocks()
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_2))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($initUnlocksMth)))

    # if (mode == "single") offlineMode = true
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_1))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "single"))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Call, $strEqRef))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Brfalse, $ldarg0))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $module.ImportReference($gmOfflineFld)))

    # this.GotoMenu()
    $p.Append($ldarg0)
    $p.Append($p.Create([Mono.Cecil.Cil.OpCodes]::Call, $gotoMenuRef))
    $p.Append($retIns)
}

# ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Yamalar uygulanıyor..." -ForegroundColor Cyan

# === PATCH 1: ServiceRoom.ConnectToServiceRoom → nop ===
try {
    PatchReturnVoid ($srType.Methods | Where-Object { $_.Name -eq "ConnectToServiceRoom" })
    Write-Host "  [1] ServiceRoom.ConnectToServiceRoom -> nop" -ForegroundColor Green
} catch { Write-Host "  [1] ATLANDI: $_" -ForegroundColor Yellow }

# === PATCH 2: FindGame.CheckIfServerIsShutDown → onSuccess() ===
# FIX: detect static vs instance to pick correct arg index
try {
    $fj_check = $fjType.Methods | Where-Object { $_.Name -eq "CheckIfServerIsShutDown" }
    $fj_check.Body.Instructions.Clear(); $fj_check.Body.Variables.Clear(); $fj_check.Body.ExceptionHandlers.Clear()
    $p2 = $fj_check.Body.GetILProcessor()
    $invokeRef = $module.ImportReference(([System.Action]).GetMethod("Invoke"))
    # Static: Ldarg_0 = first param (action). Instance: Ldarg_0 = this, Ldarg_1 = action
    $actionOpc2 = if ($fj_check.IsStatic) { [Mono.Cecil.Cil.OpCodes]::Ldarg_0 } else { [Mono.Cecil.Cil.OpCodes]::Ldarg_1 }
    $p2.Append($p2.Create($actionOpc2))
    $p2.Append($p2.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $invokeRef))
    $p2.Append($p2.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    Write-Host "  [2] FindGame.CheckIfServerIsShutDown -> onSuccess() ($( if ($fj_check.IsStatic) {'static'} else {'instance'}))" -ForegroundColor Green
} catch { Write-Host "  [2] ATLANDI: $_" -ForegroundColor Yellow }

# === PATCH 3: JoinGame.CheckIfServerIsShutDown → onSuccess() ===
# FIX: param is UnityEngine.Events.UnityAction, NOT System.Action — use correct Invoke ref
try {
    $jg_check = $jgType.Methods | Where-Object { $_.Name -eq "CheckIfServerIsShutDown" }
    $jg_check.Body.Instructions.Clear(); $jg_check.Body.Variables.Clear(); $jg_check.Body.ExceptionHandlers.Clear()
    $p3 = $jg_check.Body.GetILProcessor()
    $actionOpc3 = if ($jg_check.IsStatic) { [Mono.Cecil.Cil.OpCodes]::Ldarg_0 } else { [Mono.Cecil.Cil.OpCodes]::Ldarg_1 }
    # Build correct Invoke ref for the actual parameter type (UnityAction or Action)
    $jgParamTypeRef = $module.ImportReference($jg_check.Parameters[0].ParameterType)
    $jgInvokeRef    = New-Object Mono.Cecil.MethodReference("Invoke", $module.TypeSystem.Void, $jgParamTypeRef)
    $jgInvokeRef.HasThis = $true
    $p3.Append($p3.Create($actionOpc3))
    $p3.Append($p3.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $jgInvokeRef))
    $p3.Append($p3.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    Write-Host "  [3] JoinGame.CheckIfServerIsShutDown -> onSuccess() ($( if ($jg_check.IsStatic) {'static'} else {'instance'})) [UnityAction fix]" -ForegroundColor Green
} catch { Write-Host "  [3] ATLANDI: $_" -ForegroundColor Yellow }

# === PATCH 4: Login.LoginPlayFab(string,string) → env-var bypass ===
try {
    ApplyEnvBypassBody $lpfab2p $module.ImportReference($gotoMenuLoginMth)
    Write-Host "  [4] Login.LoginPlayFab(s,s) -> env-var bypass" -ForegroundColor Green
} catch { Write-Host "  [4] HATA: $_" -ForegroundColor Red }

# === PATCH 5: Login.Start() → auto-login if BG_MODE set ===
try {
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
    Write-Host "  [5] Login.Start() -> auto-login on BG_MODE env var" -ForegroundColor Green
} catch { Write-Host "  [5] HATA: $_" -ForegroundColor Red }

# === PATCH 6: SteamConnect.AttemptAuth() → env-var bypass ===
try {
    ApplyEnvBypassBody $attemptAuth $module.ImportReference($gotoMenuScMth)
    Write-Host "  [6] SteamConnect.AttemptAuth() -> env-var bypass" -ForegroundColor Green
} catch { Write-Host "  [6] HATA: $_" -ForegroundColor Red }

# === PATCH 7: SteamConnect.ConnectWithSteam() → skip SteamManager check ===
try {
    $cwsMth.Body.Instructions.Clear(); $cwsMth.Body.Variables.Clear(); $cwsMth.Body.ExceptionHandlers.Clear()
    $p7 = $cwsMth.Body.GetILProcessor()
    $p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Connecting..."))
    $p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
    $p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($showMth)))
    $p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($attemptAuth)))
    $p7.Append($p7.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    Write-Host "  [7] SteamConnect.ConnectWithSteam() -> skip Steam check" -ForegroundColor Green
} catch { Write-Host "  [7] HATA: $_" -ForegroundColor Red }

# === PATCH 8: Unlockable.IsUnlocked() → always true ===
try {
    PatchReturnTrue ($unlType.Methods | Where-Object { $_.Name -eq "IsUnlocked" })
    Write-Host "  [8] Unlockable.IsUnlocked() -> always true (tum silah/map/bomba acik)" -ForegroundColor Green
} catch { Write-Host "  [8] HATA: $_" -ForegroundColor Red }

# === PATCH 9: PlayerData.IsItemOwned() → always true ===
try {
    PatchReturnTrue ($pdType.Methods | Where-Object { $_.Name -eq "IsItemOwned" })
    Write-Host "  [9] PlayerData.IsItemOwned() -> always true" -ForegroundColor Green
} catch { Write-Host "  [9] HATA: $_" -ForegroundColor Red }

# === PATCH 10: PlayerData.OwnsAnyWeaponPack() → always true ===
try {
    PatchReturnTrue ($pdType.Methods | Where-Object { $_.Name -eq "OwnsAnyWeaponPack" })
    Write-Host "  [10] PlayerData.OwnsAnyWeaponPack() -> always true" -ForegroundColor Green
} catch { Write-Host "  [10] HATA: $_" -ForegroundColor Red }

# === PATCH 11: PlayerData.InitialiseUnlocks() → prepend hasPro=true + displayName ===
try {
    $initM  = $pdType.Methods | Where-Object { $_.Name -eq "InitialiseUnlocks" }
    $ilpI   = $initM.Body.GetILProcessor()
    $firstI = $initM.Body.Instructions[0]

    $storeNameIns = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $module.ImportReference($displayNameFld))
    $storeProIns  = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Stfld, $module.ImportReference($hasPro))

    # this._displayName = GetEnv("BG_NAME") ?? "Player1"
    $a0 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
    $a1 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_NAME")
    $a2 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef)
    $a3 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Dup)
    $a4 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $storeNameIns)
    $a5 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Pop)
    $a6 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Player1")
    # this.hasPro = true
    $b0 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
    $b1 = $ilpI.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1)

    foreach ($ins in @($a0,$a1,$a2,$a3,$a4,$a5,$a6,$storeNameIns,$b0,$b1,$storeProIns)) {
        $ilpI.InsertBefore($firstI, $ins)
    }
    Write-Host "  [11] PlayerData.InitialiseUnlocks() -> hasPro=true + displayName from env" -ForegroundColor Green
} catch { Write-Host "  [11] HATA: $_" -ForegroundColor Red }

# === PATCH 12: PlayerData.get_displayName() → fallback to BG_NAME ===
try {
    $getDispM = $pdType.Methods | Where-Object { $_.Name -eq "get_displayName" }
    $getDispM.Body.Instructions.Clear(); $getDispM.Body.Variables.Clear(); $getDispM.Body.ExceptionHandlers.Clear()
    $getDispM.Body.InitLocals = $true
    $getDispM.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))
    $cleanRef   = $module.ImportReference($cleanMth)
    $gp         = $getDispM.Body.GetILProcessor()
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
    Write-Host "  [12] PlayerData.get_displayName() -> fallback to BG_NAME env var" -ForegroundColor Green
} catch { Write-Host "  [12] HATA: $_" -ForegroundColor Red }

# Helper: TNet host connect via JoinGame.Connect (properly fires OnConnected callback)
function ApplyTNetConnect($method, $isAlwaysHost) {
    $tnsType_h  = $module.Types | Where-Object { $_.FullName -eq "TNet.TNServerInstance" }
    $jgType_h   = $module.Types | Where-Object { $_.Name -eq "JoinGame" }
    $showMth_h  = $loadingType.Methods | Where-Object { $_.Name -eq "Show" -and $_.Parameters.Count -eq 2 }

    # TNServerInstance.Start(int tcpPort, bool lanBroadcast) — PUBLIC STATIC, accessible!
    $tnsStart2Mth_h = $tnsType_h.Methods | Where-Object {
        $_.Name -eq "Start" -and $_.Parameters.Count -eq 2 -and
        $_.Parameters[0].ParameterType.Name -eq "Int32" -and
        $_.Parameters[1].ParameterType.Name -eq "Boolean"
    }
    # JoinGame.Connect(string lobbyID, string ip, int port, string ticket, bool asHost)
    $jgConnMth_h = $jgType_h.Methods | Where-Object { $_.Name -eq "Connect" -and $_.Parameters.Count -eq 5 }

    $method.Body.Instructions.Clear()
    $method.Body.Variables.Clear()
    $method.Body.ExceptionHandlers.Clear()
    $method.Body.InitLocals = $true
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))  # 0=mode
    $method.Body.Variables.Add((New-Object Mono.Cecil.Cil.VariableDefinition($module.TypeSystem.String)))  # 1=ip

    $ph = $method.Body.GetILProcessor()

    # Create target instructions first (forward refs)
    $ih_stloc0   = $ph.Create([Mono.Cecil.Cil.OpCodes]::Stloc_0)
    $ih_stloc1   = $ph.Create([Mono.Cecil.Cil.OpCodes]::Stloc_1)
    # Join branch label: ldstr "" (lobbyID arg to JoinGame.Connect)
    $ih_joinLbl  = $ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "")

    # mode = GetEnv("BG_MODE") ?? "host"
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_MODE"))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $ih_stloc0))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "host"))
    $ph.Append($ih_stloc0)

    # ip = GetEnv("BG_IP") ?? ""
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "BG_IP"))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $getEnvRef))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Dup))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $ih_stloc1))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Pop))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))
    $ph.Append($ih_stloc1)

    # Loading.Show("Connecting...", null)
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Connecting..."))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
    $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($showMth_h)))

    if ($isAlwaysHost) {
        # Always host: Start TNet server first, then connect as host
        # TNServerInstance.Start(5127, false) — returns bool, pop it
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 5127))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))   # lanBroadcast=false
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($tnsStart2Mth_h)))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Pop))         # discard bool return
        # JoinGame.Connect("", "127.0.0.1", 5127, "", true)
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))      # lobbyID
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "127.0.0.1"))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 5127))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))      # ticket
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))       # asHost=true
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($jgConnMth_h)))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    } else {
        # Dynamic mode (Quick Play): check BG_MODE env var
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "join"))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $strEqRef))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $ih_joinLbl))

        # HOST path: Start TNet server, then connect as host
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 5127))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($tnsStart2Mth_h)))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Pop))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "127.0.0.1"))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 5127))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($jgConnMth_h)))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ret))

        # JOIN path: connect to host's IP
        $ph.Append($ih_joinLbl)
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_1))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 5127))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($jgConnMth_h)))
        $ph.Append($ph.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    }
}

# === PATCH 13: FindGame.QuickPlayAttempt() → TNet JoinGame.Connect bypass (OnConnected fires) ===
try {
    $fjType2 = $module.Types | Where-Object { $_.Name -eq "FindGame" }
    $qpaMth  = $fjType2.Methods | Where-Object { $_.Name -eq "QuickPlayAttempt" }
    ApplyTNetConnect $qpaMth $false
    Write-Host "  [13] FindGame.QuickPlayAttempt() -> JoinGame.Connect (host/join, OnConnected fires)" -ForegroundColor Green
} catch { Write-Host "  [13] HATA: $_" -ForegroundColor Red }

# === PATCH 16: CreateMultiplayer.ContinueLaunch() → bypass PlayFab.StartGame, use TNet host ===
try {
    $cmType  = $module.Types | Where-Object { $_.Name -eq "CreateMultiplayer" }
    $clMth   = $cmType.Methods | Where-Object { $_.Name -eq "ContinueLaunch" }
    $tnsType_cm = $module.Types | Where-Object { $_.FullName -eq "TNet.TNServerInstance" }
    $jgType_cm  = $module.Types | Where-Object { $_.Name -eq "JoinGame" }
    $showMth_cm = $loadingType.Methods | Where-Object { $_.Name -eq "Show" -and $_.Parameters.Count -eq 2 }
    $tnsGetInst_cm = $tnsType_cm.Methods | Where-Object { $_.Name -eq "get_instance" }
    $tnsStart_cm   = $tnsType_cm.Methods | Where-Object { $_.Name -eq "Start" -and $_.Parameters.Count -eq 3 -and $_.Parameters[0].ParameterType.Name -eq "Int32" }
    $jgConn_cm     = $jgType_cm.Methods  | Where-Object { $_.Name -eq "Connect" -and $_.Parameters.Count -eq 5 }

    $pCL = $clMth.Body.GetILProcessor()

    # Find index of "newobj PlayFab.ClientModels.StartGameRequest" — cut from here
    $cutIdx = -1
    for ($ci = 0; $ci -lt $clMth.Body.Instructions.Count; $ci++) {
        $ins = $clMth.Body.Instructions[$ci]
        if ($ins.OpCode.Code -eq [Mono.Cecil.Cil.Code]::Newobj -and
            $ins.Operand.ToString() -match "StartGameRequest") {
            $cutIdx = $ci; break
        }
    }
    if ($cutIdx -lt 0) { throw "StartGameRequest newobj bulunamadi" }

    # Remove from cutIdx to end (preserve game-settings setup before that point)
    while ($clMth.Body.Instructions.Count -gt $cutIdx) {
        $pCL.Remove($clMth.Body.Instructions[$cutIdx])
    }

    # Append: Loading.Show + TNServerInstance.Start(5127,false) + JoinGame.Connect as host
    $tnsType_cm    = $module.Types | Where-Object { $_.FullName -eq "TNet.TNServerInstance" }
    $tnsStart2_cm  = $tnsType_cm.Methods | Where-Object {
        $_.Name -eq "Start" -and $_.Parameters.Count -eq 2 -and
        $_.Parameters[0].ParameterType.Name -eq "Int32" -and
        $_.Parameters[1].ParameterType.Name -eq "Boolean"
    }
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Connecting..."))
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($showMth_cm)))
    # Start TNet server on port 5127
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 5127))
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))      # lanBroadcast=false
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($tnsStart2_cm)))
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Pop))            # discard bool
    # Connect as host to local server
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))      # lobbyID
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "127.0.0.1"))
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 5127))
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, ""))      # ticket
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))       # asHost=true
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($jgConn_cm)))
    $pCL.Append($pCL.Create([Mono.Cecil.Cil.OpCodes]::Ret))

    Write-Host "  [16] CreateMultiplayer.ContinueLaunch() -> TNet host (CREATE butonu artik calisir)" -ForegroundColor Green
} catch { Write-Host "  [16] HATA: $_" -ForegroundColor Red }

# === PATCH 17: CreateMultiplayer.QuickPlayAttempt() → always host (Start server + connect) ===
try {
    $cmType2  = $module.Types | Where-Object { $_.Name -eq "CreateMultiplayer" }
    $cmQpaMth = $cmType2.Methods | Where-Object { $_.Name -eq "QuickPlayAttempt" }
    ApplyTNetConnect $cmQpaMth $true
    Write-Host "  [17] CreateMultiplayer.QuickPlayAttempt() -> TNet Start + JoinGame.Connect host" -ForegroundColor Green
} catch { Write-Host "  [17] HATA: $_" -ForegroundColor Red }

# === PATCH 14: GameManager.HasAuthority() → offlineMode || TNServerInstance.isActive ===
# Analiz: orijinal NetworkServer.active kullanıyor (Unity UNET),
# TNet'te bu her zaman false döner. TNServerInstance.isActive ile değiştir.
try {
    $gmType2    = $module.Types | Where-Object { $_.Name -eq "GameManager" }
    $tnsType3   = $module.Types | Where-Object { $_.FullName -eq "TNet.TNServerInstance" }
    $hasMth2    = $gmType2.Methods | Where-Object { $_.Name -eq "HasAuthority" }
    $tnsIsActProp = $tnsType3.Methods | Where-Object { $_.Name -eq "get_isActive" }
    $gmOffFld2  = $gmType2.Fields | Where-Object { $_.Name -eq "offlineMode" }

    $hasMth2.Body.Instructions.Clear()
    $hasMth2.Body.Variables.Clear()
    $hasMth2.Body.ExceptionHandlers.Clear()
    $p14 = $hasMth2.Body.GetILProcessor()

    $trueIns = $p14.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1)
    # if (offlineMode) return true
    $p14.Append($p14.Create([Mono.Cecil.Cil.OpCodes]::Ldsfld, $module.ImportReference($gmOffFld2)))
    $p14.Append($p14.Create([Mono.Cecil.Cil.OpCodes]::Brtrue, $trueIns))
    # return TNServerInstance.isActive
    $p14.Append($p14.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($tnsIsActProp)))
    $p14.Append($p14.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    $p14.Append($trueIns)
    $p14.Append($p14.Create([Mono.Cecil.Cil.OpCodes]::Ret))

    Write-Host "  [14] GameManager.HasAuthority() -> offlineMode || TNServerInstance.isActive" -ForegroundColor Green
} catch { Write-Host "  [14] HATA: $_" -ForegroundColor Red }

# === PATCH 15: TNetConnectionHandler.SendAuth() + SendMatchmakerAuth() → NOP ===
# Analiz: bu metodlar sunucuya PlayFab ticket gönderiyorlar (paket 129/130).
# Local TNet sunucusu bu paketleri işlemez/beklemez, auth yeterli.
# sessionTicket = IP adresi olduğu için paket gönderilir ama sunucu doğrulamaz.
# Güvenli taraf: NOP yaparak gereksiz network trafiğini önleyelim.
try {
    $tncType3   = $module.Types | Where-Object { $_.Name -eq "TNetConnectionHandler" }
    $sendAuthM  = $tncType3.Methods | Where-Object { $_.Name -eq "SendAuth" }
    $sendMaM    = $tncType3.Methods | Where-Object { $_.Name -eq "SendMatchmakerAuth" }
    PatchReturnVoid $sendAuthM
    PatchReturnVoid $sendMaM
    Write-Host "  [15] TNetConnectionHandler.SendAuth() + SendMatchmakerAuth() -> NOP" -ForegroundColor Green
} catch { Write-Host "  [15] HATA: $_" -ForegroundColor Red }

# === PATCH 19: UserData.ReadUserDataIntoPlayerData → NOP ===
# We pass null dictionaries (no PlayFab data), so the method would crash on ContainsKey(null).
# NOP it — outfit defaults to whatever PlayerData ctor sets.
try {
    $udType19  = $module.Types | Where-Object { $_.Name -eq "UserData" }
    $readUD19  = $udType19.Methods | Where-Object { $_.Name -eq "ReadUserDataIntoPlayerData" }
    PatchReturnVoid $readUD19
    Write-Host "  [19] UserData.ReadUserDataIntoPlayerData -> NOP (null dict guvenli)" -ForegroundColor Green
} catch { Write-Host "  [19] HATA: $_" -ForegroundColor Red }

# === PATCH 20: UserData.LoadUserData → direkt Common.OnGotPlayerData cagir (PlayFab bypass) ===
# PlayFab sunucusu kapali, callback hic donemez => oyuncu lobi kartı hic acilmaz.
# Cozum: LoadUserData dogrudan OnGotPlayerData'yi cagirsin (null data ile).
# Common.OnGotPlayerData(int playerID, string displayName, dict, dict, list)
try {
    $udType20      = $module.Types | Where-Object { $_.Name -eq "UserData" }
    $loadUD20      = $udType20.Methods | Where-Object { $_.Name -eq "LoadUserData" -and $_.Parameters.Count -eq 3 }
    $commonType20  = $module.Types | Where-Object { $_.Name -eq "Common" }
    $onGotPD20     = $commonType20.Methods | Where-Object { $_.Name -eq "OnGotPlayerData" }

    $loadUD20.Body.Instructions.Clear()
    $loadUD20.Body.Variables.Clear()
    $loadUD20.Body.ExceptionHandlers.Clear()
    $p20 = $loadUD20.Body.GetILProcessor()
    # Common.OnGotPlayerData(playerID, playFabId, null, null, null)
    $p20.Append($p20.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))   # playerID (int)
    $p20.Append($p20.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))   # playFabId (string = displayName)
    $p20.Append($p20.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))    # userData dict
    $p20.Append($p20.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))    # readOnlyData dict
    $p20.Append($p20.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))    # statistics list
    $p20.Append($p20.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($onGotPD20)))
    $p20.Append($p20.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    Write-Host "  [20] UserData.LoadUserData -> Common.OnGotPlayerData direkt (PlayFab bypass)" -ForegroundColor Green
} catch { Write-Host "  [20] HATA: $_" -ForegroundColor Red }

# === PATCH 18: JoinGame.OnConnected() → Loading.Hide() + lokal oyuncuyu lobiye kaydet ===
# OnConnected never calls Loading.Hide(), spinner stays forever.
# Also: server never sends NewPlayer packet for local player → lobby slots stay empty.
# Fix: register local player immediately when we connect.
try {
    $jgType18      = $module.Types | Where-Object { $_.Name -eq "JoinGame" }
    $onConnM18     = $jgType18.Methods | Where-Object { $_.Name -eq "OnConnected" }
    $hideMth18     = ($module.Types | Where-Object { $_.Name -eq "Loading" }).Methods | Where-Object { $_.Name -eq "Hide" -and $_.Parameters.Count -eq 0 }
    $commonType18  = $module.Types | Where-Object { $_.Name -eq "Common" }
    $createPD18    = $commonType18.Methods | Where-Object { $_.Name -eq "CreatePlayerData" }
    $udType18      = $module.Types | Where-Object { $_.Name -eq "UserData" }
    $loadUD18      = $udType18.Methods | Where-Object { $_.Name -eq "LoadUserData" -and $_.Parameters.Count -eq 3 }
    $gmType18      = $module.Types | Where-Object { $_.Name -eq "GameManager" }
    $gmPlayerFld18 = $gmType18.Fields | Where-Object { $_.Name -eq "loggedInPlayerData" }
    $pdType18      = $module.Types | Where-Object { $_.Name -eq "PlayerData" }
    $getDispMth18  = $pdType18.Methods | Where-Object { $_.Name -eq "get_displayName" }
    $tnsType18     = $module.Types | Where-Object { $_.FullName -eq "TNet.TNServerInstance" }
    # Use TNet.TNManager.get_playerID() (static)
    $tnMgrType18   = $module.Types | Where-Object { $_.FullName -eq "TNet.TNManager" }
    $getPIDMth18   = $tnMgrType18.Methods | Where-Object { $_.Name -eq "get_playerID" }

    $il18 = $onConnM18.Body.GetILProcessor()
    $first18 = $onConnM18.Body.Instructions[0]

    # Build instructions to prepend (in reverse order since InsertBefore shifts)
    # Order: Loading.Hide() → CreatePlayerData(id, name) → pop → LoadUserData(id, name, null)
    $ins_ret = $il18.Create([Mono.Cecil.Cil.OpCodes]::Nop)  # placeholder, not actually inserted

    # 1. Loading.Hide()
    $i_hide = $il18.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($hideMth18))

    # 2. Common.CreatePlayerData(TNManager.playerID, loggedInPlayerData.displayName)
    $i_getid1  = $il18.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($getPIDMth18))
    $i_getpd1  = $il18.Create([Mono.Cecil.Cil.OpCodes]::Ldsfld, $module.ImportReference($gmPlayerFld18))
    $i_getdn1  = $il18.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($getDispMth18))
    $i_create  = $il18.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($createPD18))
    $i_pop     = $il18.Create([Mono.Cecil.Cil.OpCodes]::Pop)  # discard returned PlayerData

    # 3. UserData.LoadUserData(TNManager.playerID, displayName, null) → calls OnGotPlayerData directly
    $i_getid2  = $il18.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($getPIDMth18))
    $i_getpd2  = $il18.Create([Mono.Cecil.Cil.OpCodes]::Ldsfld, $module.ImportReference($gmPlayerFld18))
    $i_getdn2  = $il18.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $module.ImportReference($getDispMth18))
    $i_null    = $il18.Create([Mono.Cecil.Cil.OpCodes]::Ldnull)  # callback = null
    $i_load    = $il18.Create([Mono.Cecil.Cil.OpCodes]::Call, $module.ImportReference($loadUD18))

    foreach ($ins in @($i_hide, $i_getid1, $i_getpd1, $i_getdn1, $i_create, $i_pop,
                        $i_getid2, $i_getpd2, $i_getdn2, $i_null, $i_load)) {
        $il18.InsertBefore($first18, $ins)
    }
    Write-Host "  [18] JoinGame.OnConnected() -> Hide spinner + kaydet lokal oyuncu (lobi kartı gorunur)" -ForegroundColor Green
} catch { Write-Host "  [18] HATA: $_" -ForegroundColor Red }

# ── 5. Write patched DLL ───────────────────────────────────────────────────
Write-Host ""
Write-Host "Yamali DLL yaziliyor..." -ForegroundColor Gray
$tempPath = $dllPath + ".patching"
$wp = New-Object Mono.Cecil.WriterParameters
$module.Write($tempPath, $wp)
$module.Dispose()
Copy-Item $tempPath $dllPath -Force
Remove-Item $tempPath
Write-Host "DLL basariyla yazildi." -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ── 6. GOLDBERG STEAM EMULATOR (CreamAPI / Spacewar alternatifi) ──────────
# ════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "Steam API bypass (Goldberg Emulator) yukleniyor..." -ForegroundColor Cyan
Write-Host "  Steam'e gerek kalmayacak!" -ForegroundColor Gray

$steamApiPath   = Join-Path $gameDir "steam_api64.dll"
$steamApiBak    = Join-Path $gameDir "steam_api64_original.dll"
$steamSettingsDir = Join-Path $gameDir "steam_settings"

$goldbergOk = $false

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ "User-Agent" = "BrokenGroundPatch/2.0" }

    # GitHub API: latest release of gbe_fork
    Write-Host "  GitHub'dan Goldberg son surumu aliniyor..." -ForegroundColor Gray
    $release = Invoke-RestMethod "https://api.github.com/repos/Detanup01/gbe_fork/releases/latest" -Headers $headers
    $asset   = $release.assets | Where-Object { $_.name -eq "emu-win-release.7z" } | Select-Object -First 1

    if (-not $asset) { throw "emu-win-release.7z bulunamadi" }

    $tmpDir    = Join-Path $env:TEMP "goldberg_bg_$([System.IO.Path]::GetRandomFileName())"
    $archive7z = Join-Path $tmpDir "emu-win-release.7z"
    $7zrPath   = Join-Path $tmpDir "7zr.exe"

    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    # Windows Defender exclusion (Goldberg DLL often flagged as PUP)
    try {
        Add-MpPreference -ExclusionPath $tmpDir -ErrorAction Stop
        Write-Host "  Windows Defender istisna eklendi (gecici)" -ForegroundColor Gray
        $defExcluded = $true
    } catch { $defExcluded = $false }

    # Download 7zr.exe (standalone 7-zip, ~500 KB)
    Write-Host "  7zr.exe indiriliyor..." -ForegroundColor Gray
    Invoke-WebRequest "https://www.7-zip.org/a/7zr.exe" -OutFile $7zrPath -UseBasicParsing -Headers $headers

    # Download Goldberg archive
    Write-Host "  Goldberg emulator indiriliyor ($([math]::Round($asset.size/1MB,1)) MB)..." -ForegroundColor Yellow
    Invoke-WebRequest $asset.browser_download_url -OutFile $archive7z -UseBasicParsing -Headers $headers

    if (-not (Test-Path $archive7z) -or (Get-Item $archive7z).Length -lt 100000) {
        throw "Arsiv indirilemedi veya Windows Defender tarafindan silindi"
    }

    # Extract
    Write-Host "  Arsiv aciliyor..." -ForegroundColor Gray
    & $7zrPath x $archive7z "-o$tmpDir" -y | Out-Null

    # Find steam_api64.dll
    $candidates = @(
        (Join-Path $tmpDir "release\steam_api64.dll"),
        (Join-Path $tmpDir "win64\steam_api64.dll"),
        (Join-Path $tmpDir "x64\steam_api64.dll")
    )
    $goldbergDll = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $goldbergDll) {
        $found = Get-ChildItem $tmpDir -Recurse -Filter "steam_api64.dll" |
                 Where-Object { $_.Length -gt 150000 } | Select-Object -First 1
        if ($found) { $goldbergDll = $found.FullName }
    }

    if (-not $goldbergDll) { throw "steam_api64.dll arsivde bulunamadi" }

    # Backup + Install
    if (-not (Test-Path $steamApiBak)) {
        Copy-Item $steamApiPath $steamApiBak
        Write-Host "  Orijinal steam_api64.dll yedeklendi." -ForegroundColor Gray
    }
    Copy-Item $goldbergDll $steamApiPath -Force
    Write-Host "  [G] steam_api64.dll -> Goldberg Emulator kuruldu!" -ForegroundColor Green

    # 32-bit as well
    $goldbergDll32 = $goldbergDll -replace "64\.dll$", ".dll"
    if (Test-Path $goldbergDll32) {
        $steamApi32Bak = Join-Path $gameDir "steam_api_original.dll"
        if (-not (Test-Path $steamApi32Bak)) {
            Copy-Item (Join-Path $gameDir "steam_api.dll") $steamApi32Bak -ErrorAction SilentlyContinue
        }
        Copy-Item $goldbergDll32 (Join-Path $gameDir "steam_api.dll") -Force -ErrorAction SilentlyContinue
    }

    # Cleanup
    if ($defExcluded) { Remove-MpPreference -ExclusionPath $tmpDir -ErrorAction SilentlyContinue }
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    $goldbergOk = $true

} catch {
    Write-Host "  Goldberg kurulamadi: $_" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [!] ELLE KURULUM (Steam'siz oynamak icin):" -ForegroundColor Cyan
    Write-Host "  1) Windows Defender -> Virus & threat protection"
    Write-Host "     -> Real-time protection KAPAT (gecici)"
    Write-Host "  2) Bu patch.ps1'i tekrar calistir"
    Write-Host "  3) Defender'i tekrar AC"
    Write-Host ""
    Write-Host "  VEYA C# patch yeterlidir (Steam arka planda acik olsun)" -ForegroundColor Gray
}

# ── 7. steam_settings klasörü oluştur ─────────────────────────────────────
Write-Host ""
Write-Host "steam_settings yapilandiriliyor..." -ForegroundColor Gray

New-Item -ItemType Directory -Force -Path $steamSettingsDir | Out-Null

# steam_appid.txt
$appIdPath = Join-Path $gameDir "steam_appid.txt"
$existingId = if (Test-Path $appIdPath) { (Get-Content $appIdPath -Raw).Trim() } else { "708420" }
if (-not (Test-Path $appIdPath)) { "708420" | Out-File $appIdPath -NoNewline -Encoding ascii }

# Default account_name.txt (launcher overwrites at runtime)
$accountNamePath = Join-Path $steamSettingsDir "account_name.txt"
if (-not (Test-Path $accountNamePath)) {
    "Player1" | Out-File $accountNamePath -NoNewline -Encoding ascii
}

# user_steam_id.txt — stable fake Steam ID
$steamIdPath = Join-Path $steamSettingsDir "user_steam_id.txt"
if (-not (Test-Path $steamIdPath)) {
    "76561198012345678" | Out-File $steamIdPath -NoNewline -Encoding ascii
}

# configs.main.ini — AppID + LAN settings
$configMain = Join-Path $steamSettingsDir "configs.main.ini"
@"
[main::connectivity]
disable_networking=0
disable_overlay=1

[main::general]
appid=$existingId
"@ | Out-File $configMain -Encoding ascii

# Disable overlay (can cause issues)
$configUser = Join-Path $steamSettingsDir "configs.user.ini"
@"
[user::general]
account_name=Player1
"@ | Out-File $configUser -Encoding ascii

Write-Host "  [S] steam_settings/ olusturuldu (AppID: $existingId)" -ForegroundColor Green

# ── 8. Compile new Launcher (with Goldberg steam_settings support) ─────────
Write-Host ""
Write-Host "Launcher derleniyor..." -ForegroundColor Cyan

$launcherSrc = @'
using System;
using System.Windows.Forms;
using System.Diagnostics;
using System.IO;
using System.Drawing;

public class BgLauncher : Form {
    private TextBox tbName, tbIP;
    private Label lblIP;
    private Button btnSingle, btnHost, btnJoin, btnConnect;
    private string gameDir;
    private bool joinVisible = false;

    public BgLauncher() {
        gameDir = Path.GetDirectoryName(Application.ExecutablePath);

        Text = "Broken Ground Launcher";
        ClientSize = new Size(370, 240);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(18, 18, 28);
        Font = new Font("Segoe UI", 9f);

        var title = new Label {
            Text = "BROKEN GROUND — LOCAL MULTIPLAYER",
            ForeColor = Color.FromArgb(80, 180, 255),
            Location = new Point(10, 8),
            Size = new Size(350, 18),
            TextAlign = System.Drawing.ContentAlignment.MiddleCenter,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold)
        };

        var lblName = new Label {
            Text = "Karakter Ismi:", ForeColor = Color.LightGray,
            Location = new Point(15, 34), Size = new Size(100, 18)
        };
        tbName = new TextBox {
            Location = new Point(15, 52), Size = new Size(340, 24),
            BackColor = Color.FromArgb(38, 38, 58), ForeColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle, Text = "Player1"
        };

        btnSingle = MakeBtn("SINGLE PLAYER", new Point(15, 90), new Size(160, 38), Color.FromArgb(25, 90, 25));
        btnHost   = MakeBtn("HOST GAME",     new Point(195, 90), new Size(160, 38), Color.FromArgb(25, 55, 110));
        btnJoin   = MakeBtn("JOIN GAME  v",  new Point(15, 138), new Size(340, 38), Color.FromArgb(90, 35, 35));

        lblIP = new Label {
            Text = "Host IP Adresi (LAN / ZeroTier):", ForeColor = Color.LightGray,
            Location = new Point(15, 186), Size = new Size(240, 18), Visible = false
        };
        tbIP = new TextBox {
            Location = new Point(15, 204), Size = new Size(230, 24),
            BackColor = Color.FromArgb(38, 38, 58), ForeColor = Color.White,
            BorderStyle = BorderStyle.FixedSingle, Text = "", Visible = false
        };
        btnConnect = MakeBtn("CONNECT", new Point(258, 202), new Size(97, 28),
                             Color.FromArgb(100, 55, 15));
        btnConnect.Visible = false;

        btnSingle.Click += (s, e) => Launch("single", "");
        btnHost.Click   += (s, e) => Launch("host", "");
        btnJoin.Click   += (s, e) => ToggleJoin();
        btnConnect.Click += (s, e) => {
            string ip = tbIP.Text.Trim();
            if (string.IsNullOrEmpty(ip)) { MessageBox.Show("IP adresi girin!", "Hata"); return; }
            Launch("join", ip);
        };

        Controls.AddRange(new Control[] {
            title, lblName, tbName, btnSingle, btnHost, btnJoin,
            lblIP, tbIP, btnConnect
        });
    }

    void ToggleJoin() {
        joinVisible = !joinVisible;
        lblIP.Visible = tbIP.Visible = btnConnect.Visible = joinVisible;
        ClientSize = new Size(370, joinVisible ? 244 : 240);
        btnJoin.Text = joinVisible ? "JOIN GAME  ^" : "JOIN GAME  v";
    }

    Button MakeBtn(string text, Point loc, Size sz, Color bg) {
        var btn = new Button {
            Text = text, Location = loc, Size = sz,
            BackColor = bg, ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Segoe UI", 9f, FontStyle.Bold)
        };
        btn.FlatAppearance.BorderColor = Color.FromArgb(60, 60, 80);
        return btn;
    }

    void WriteGoldbergSettings(string name) {
        try {
            string dir = Path.Combine(gameDir, "steam_settings");
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "account_name.txt"), name);
            long steamId = 76561198000000000L + (Math.Abs(name.GetHashCode()) % 999998 + 1);
            File.WriteAllText(Path.Combine(dir, "user_steam_id.txt"), steamId.ToString());
            string cfgUser = Path.Combine(dir, "configs.user.ini");
            File.WriteAllText(cfgUser, "[user::general]\r\naccount_name=" + name + "\r\n");
        } catch { }
    }

    void Launch(string mode, string ip) {
        string name = tbName.Text.Trim();
        if (string.IsNullOrEmpty(name)) name = "Player1";
        if (name.Length > 32) name = name.Substring(0, 32);

        WriteGoldbergSettings(name);

        try {
            File.WriteAllText(Path.Combine(gameDir, "launcher_config.ini"),
                string.Format("name={0}\nmode={1}\nip={2}\n", name, mode, ip));
        } catch { }

        var psi = new ProcessStartInfo {
            FileName = Path.Combine(gameDir, "BrokenGround.exe"),
            WorkingDirectory = gameDir,
            UseShellExecute = false
        };
        psi.EnvironmentVariables["BG_NAME"] = name;
        psi.EnvironmentVariables["BG_MODE"] = mode;
        psi.EnvironmentVariables["BG_IP"]   = ip;

        try {
            Process.Start(psi);
            Application.Exit();
        } catch (Exception ex) {
            MessageBox.Show("Oyun baslatılamadi:\n" + ex.Message, "Hata",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    [STAThread]
    static void Main() {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new BgLauncher());
    }
}
'@

$launcherOut = Join-Path $PSScriptRoot "BrokenGroundLauncher.exe"
$launcherDst = Join-Path $gameDir "BrokenGroundLauncher.exe"

try {
    Add-Type -TypeDefinition $launcherSrc `
             -OutputAssembly $launcherOut `
             -OutputType WindowsApplication `
             -ReferencedAssemblies "System.Windows.Forms","System.Drawing" `
             -ErrorAction Stop
    Write-Host "  [L] Launcher derlendi: BrokenGroundLauncher.exe" -ForegroundColor Green
} catch {
    Write-Host "  Launcher derlenemedi: $_" -ForegroundColor Yellow
    Write-Host "  Mevcut launcher kullaniliyor." -ForegroundColor Gray
    # Fallback: use existing exe if present
    if (-not (Test-Path $launcherOut)) {
        $launcherOut = $null
    }
}

# ── 9. Copy launcher to game dir ───────────────────────────────────────────
# FIX: Copy-Item hatasını önle — kaynak ve hedef aynı klasörde olabilir
if ($launcherOut -and (Test-Path $launcherOut)) {
    $srcFull = [System.IO.Path]::GetFullPath($launcherOut)
    $dstFull = [System.IO.Path]::GetFullPath($launcherDst)
    if ($srcFull -ne $dstFull) {
        Copy-Item $launcherOut $launcherDst -Force
        Write-Host "  [L] BrokenGroundLauncher.exe oyun klasorune kopyalandi" -ForegroundColor Green
    } else {
        Write-Host "  [L] BrokenGroundLauncher.exe zaten oyun klasoründe (kopyalama atlandı)" -ForegroundColor Gray
    }
} elseif (Test-Path (Join-Path $PSScriptRoot "BrokenGroundLauncher.exe")) {
    $srcFull2 = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "BrokenGroundLauncher.exe"))
    $dstFull2 = [System.IO.Path]::GetFullPath($launcherDst)
    if ($srcFull2 -ne $dstFull2) {
        Copy-Item (Join-Path $PSScriptRoot "BrokenGroundLauncher.exe") $launcherDst -Force
        Write-Host "  [L] BrokenGroundLauncher.exe kopyalandi (mevcut)" -ForegroundColor Green
    } else {
        Write-Host "  [L] BrokenGroundLauncher.exe zaten yerinde (kopyalama atlandı)" -ForegroundColor Gray
    }
}

# ── 10. Firewall rules (optional) ─────────────────────────────────────────
Write-Host ""
Write-Host "Firewall kurallari kontrol ediliyor..." -ForegroundColor Gray
try {
    $existingTcp = netsh advfirewall firewall show rule name="BrokenGround TCP" 2>&1
    if ($existingTcp -match "No rules match") {
        netsh advfirewall firewall add rule name="BrokenGround TCP" dir=in action=allow protocol=TCP localport=5127 | Out-Null
        Write-Host "  [F] Firewall TCP 5127 kurali eklendi" -ForegroundColor Green
    } else {
        Write-Host "  [F] Firewall TCP 5127 zaten mevcut" -ForegroundColor Gray
    }
    $existingUdp = netsh advfirewall firewall show rule name="BrokenGround UDP" 2>&1
    if ($existingUdp -match "No rules match") {
        netsh advfirewall firewall add rule name="BrokenGround UDP" dir=in action=allow protocol=UDP localport=50000 | Out-Null
        Write-Host "  [F] Firewall UDP 50000 kurali eklendi" -ForegroundColor Green
    } else {
        Write-Host "  [F] Firewall UDP 50000 zaten mevcut" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Firewall: Yonetici yetkisi gerekebilir, atlanıyor..." -ForegroundColor Yellow
}

# ════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  PATCH TAMAMLANDI!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  DLL Patch  : Assembly-CSharp.dll (PlayFab/Steam bypass)" -ForegroundColor White
if ($goldbergOk) {
    Write-Host "  Steam API  : Goldberg Emulator kuruldu (Steam gerekmez!)" -ForegroundColor Green
} else {
    Write-Host "  Steam API  : C# patch uygulandı (Steam acık olsun)" -ForegroundColor Yellow
}
Write-Host "  Launcher   : BrokenGroundLauncher.exe" -ForegroundColor White
Write-Host "  Klasor     : $gameDir" -ForegroundColor White
Write-Host ""
Write-Host "NASIL OYNANIR:" -ForegroundColor Cyan
Write-Host "  1) BrokenGroundLauncher.exe'yi ac"
Write-Host "  2) Karakter ismini gir"
Write-Host "  3) SINGLE PLAYER / HOST GAME / JOIN GAME'i sec"
Write-Host "  4) Host isen: Multiplayer -> Quick Play"
Write-Host "  5) Join isen: Host'un IP'sini gir -> CONNECT"
Write-Host ""
Write-Host "ZeroTier ile internet uzerinden de oynanabilir!" -ForegroundColor Cyan
Write-Host "(zerotier.com'dan ucretsiz indir)" -ForegroundColor Gray
Write-Host ""
Read-Host "Cikmak icin Enter'a basin"

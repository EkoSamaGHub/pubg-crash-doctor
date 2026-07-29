#requires -Version 5.1
<#
    PUBG Crash Doctor  -  read-only diagnostic scanner
    ---------------------------------------------------
    Gathers the same evidence a manual investigation would (PUBG logs, Windows
    crash/power events, RAM speed, GPU driver, pagefile, disk health), analyses
    the pattern, and writes a local report that index.html renders in your browser.

    IT CHANGES NOTHING ON YOUR SYSTEM. Every command below only READS.
    No settings are touched, no files deleted, nothing is uploaded anywhere.

    Usage:
        Right-click  ->  Run with PowerShell        (or double-click Run-Diagnostic.bat)
        or:  powershell -ExecutionPolicy Bypass -File diagnose.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoBrowser,
    [string]$OutDir
)

$ErrorActionPreference = 'SilentlyContinue'
$TOOL_VERSION = '1.1'
if (-not $OutDir) { $OutDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path } }

function Line($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Clean($s) { if ($null -eq $s) { return '' } ($s -replace '[\x00-\x1F]', ' ').Trim() }

Clear-Host
Line "  PUBG Crash Doctor  v$TOOL_VERSION" 'White'
Line "  Read-only scan - nothing on your PC will be changed." 'DarkGray'

# --------------------------------------------------------------------------
# SYSTEM
# --------------------------------------------------------------------------
Head 'System'
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$cs   = Get-CimInstance Win32_ComputerSystem
$os   = Get-CimInstance Win32_OperatingSystem
$gpuW = Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -or $_.DriverVersion } | Select-Object -First 1

$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
Line ("  CPU:    {0}" -f (Clean $cpu.Name))
Line ("  RAM:    {0} GB" -f $ramGB)
Line ("  GPU:    {0}  (driver {1})" -f (Clean $gpuW.Name), $gpuW.DriverVersion)
Line ("  OS:     {0}  {1}" -f (Clean $os.Caption), $os.Version)

# GPU VRAM + vendor (nvidia-smi is the only reliable VRAM source on >4GB cards)
$vramMB = $null; $nvDriver = $null
$smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
if ($smi) {
    $q = & $smi --query-gpu=memory.total,driver_version --format=csv,noheader,nounits 2>$null
    if ($q) { $p = ($q -split ',').Trim(); $vramMB = [int]$p[0]; $nvDriver = $p[1] }
}
$vendor = if ($gpuW.Name -match 'NVIDIA|GeForce|RTX|GTX') { 'NVIDIA' }
          elseif ($gpuW.Name -match 'AMD|Radeon|RX ') { 'AMD' }
          elseif ($gpuW.Name -match 'Intel|Arc|UHD|Iris') { 'Intel' } else { 'Unknown' }
if ($vramMB) { Line ("  VRAM:   {0} MB ({1:N1} GB)" -f $vramMB, ($vramMB/1024)) }

# Driver date
$drvDate = $null
try { if ($gpuW.DriverDate) { $drvDate = ([Management.ManagementDateTimeConverter]::ToDateTime($gpuW.DriverDate)).ToString('yyyy-MM-dd') } } catch {}

# --------------------------------------------------------------------------
# MEMORY  (XMP / EXPO state)
# --------------------------------------------------------------------------
Head 'Memory (RAM overclock / XMP state)'
$sticks = Get-CimInstance Win32_PhysicalMemory
$ratedMax = ($sticks | Measure-Object Speed -Maximum).Maximum
$curMax   = ($sticks | Measure-Object ConfiguredClockSpeed -Maximum).Maximum
$xmpState = 'Unknown'
if ($ratedMax -and $curMax) {
    if ($curMax -lt $ratedMax) { $xmpState = 'OFF / reduced' }   # running below the sticks' rated speed
    elseif ($curMax -ge $ratedMax -and $ratedMax -gt 2400) { $xmpState = 'ON' }
    else { $xmpState = 'Stock' }
}
Line ("  Sticks:          {0}" -f ($sticks | Measure-Object).Count)
Line ("  Rated speed:     {0} MT/s" -f $ratedMax)
Line ("  Running at:      {0} MT/s" -f $curMax)
Line ("  Memory OC (XMP): {0}" -f $xmpState) $(if ($xmpState -eq 'ON') { 'Yellow' } else { 'Gray' })

# --------------------------------------------------------------------------
# PAGEFILE
# --------------------------------------------------------------------------
Head 'Pagefile'
$pf = Get-CimInstance Win32_PageFileUsage | Select-Object -First 1
$pfAuto = [bool]$cs.AutomaticManagedPagefile
$pfMB = if ($pf) { [int]$pf.AllocatedBaseSize } else { 0 }
$pfBad = (-not $pfAuto) -and ($pfMB -lt 2048)
Line ("  Allocated:       {0} MB" -f $pfMB)
Line ("  System-managed:  {0}" -f $pfAuto) $(if ($pfBad) { 'Red' } else { 'Gray' })
if ($pfBad) { Line "  ^ Small/disabled pagefile can itself cause 'out of video memory'." 'Yellow' }

# --------------------------------------------------------------------------
# DISK HEALTH
# --------------------------------------------------------------------------
$disks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus
$diskBad = @($disks | Where-Object { $_.HealthStatus -and $_.HealthStatus -ne 'Healthy' }).Count -gt 0

# --------------------------------------------------------------------------
# PUBG LOGS
# --------------------------------------------------------------------------
Head 'PUBG logs'
$logDir   = Join-Path $env:LOCALAPPDATA 'TslGame\Saved\Logs'
$crashDir = Join-Path $env:LOCALAPPDATA 'TslGame\Saved\Crashes'
$logFiles = @(Get-ChildItem "$logDir\*.log" -ErrorAction SilentlyContinue)
$pubgInstalled = Test-Path $logDir

function ScanLogs($pattern) {
    $hits = @()
    foreach ($f in $logFiles) {
        $m = Select-String -Path $f.FullName -Pattern $pattern -ErrorAction SilentlyContinue
        if ($m) { $hits += $m }
    }
    $hits
}
$oom      = ScanLogs 'E_OUTOFMEMORY|Out of video memory'
$gpuCrash = ScanLogs 'LogGPUCrash'
$rhang    = ScanLogs 'GameThread timed out waiting for RenderThread|RenderThread'
$fatal    = ScanLogs 'LowLevelFatalError'

$lastOom = if ($oom) { Clean ($oom[-1].Line.Substring(0, [Math]::Min(180, $oom[-1].Line.Length))) } else { '' }
Line ("  Log files scanned:          {0}" -f $logFiles.Count)
Line ("  'Out of video memory' hits: {0}" -f @($oom).Count)      $(if (@($oom).Count) { 'Yellow' } else { 'Gray' })
Line ("  GPU-crash hits:             {0}" -f @($gpuCrash).Count) $(if (@($gpuCrash).Count) { 'Yellow' } else { 'Gray' })
Line ("  Render-thread hang hits:    {0}" -f @($rhang).Count)

# Crash dumps
$crashes = @(Get-ChildItem $crashDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
$lastCrash = if ($crashes) { $crashes[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm') } else { '' }
$lastCrashErr = ''
if ($crashes) {
    $xmlF = Join-Path $crashes[0].FullName 'CrashContext.runtime-xml'
    if (Test-Path $xmlF) {
        try { $rp = ([xml](Get-Content $xmlF -Raw)).FGenericCrashContext.RuntimeProperties
              $lastCrashErr = Clean $rp.ErrorMessage } catch {}
    }
}
Line ("  Crash reports on disk:      {0}  (latest {1})" -f $crashes.Count, $lastCrash)

# --------------------------------------------------------------------------
# ANTI-CHEAT / LAUNCH BLOCK  ("Interrupted by external program", PUBG Shield)
# This is a DIFFERENT failure class from instability crashes: the game is being
# blocked from starting, not crashing mid-game.
# --------------------------------------------------------------------------
Head 'Anti-cheat (PUBG Shield / BattlEye)'

# Find the game install (pubg_fail.log lives next to TslGame.exe)
$failLog = $null
$steamRoots = @()
try {
    $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if ($sp) { $steamRoots += $sp.Replace('/', '\') }
} catch {}
$steamRoots += @("$env:ProgramFiles(x86)\Steam", "$env:ProgramFiles\Steam", 'C:\Steam')
# also read library folders so non-C: installs are found
foreach ($r in @($steamRoots | Select-Object -Unique)) {
    $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($m in ([regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"'))) {
            $steamRoots += $m.Groups[1].Value.Replace('\\', '\')
        }
    }
}
foreach ($r in @($steamRoots | Select-Object -Unique)) {
    $c = Join-Path $r 'steamapps\common\PUBG\TslGame\Binaries\Win64\pubg_fail.log'
    if (Test-Path $c) { $failLog = $c; break }
}

$acCode = ''; $acDiag = ''; $acWhen = ''; $acInjected = @(); $acPresent = $false
if ($failLog) {
    $acPresent = $true
    $acWhen = (Get-Item $failLog).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
    try {
        $rawAc = Get-Content $failLog -Raw -Encoding Unicode   # the file is UTF-16LE JSON
        if ($rawAc -notmatch '^\s*\{') { $rawAc = Get-Content $failLog -Raw }
        $acj = $rawAc | ConvertFrom-Json
        $acCode = "$($acj.code)/$($acj.code2)"
        $acDiag = (@($acj.diagnostic) -join ' ')
        # third-party DLLs loaded INTO the game = the usual culprits.
        # Exclude Windows' own DLLs and anything shipped inside the PUBG install
        # (e.g. onnxruntime.dll is PUBG's own runtime, not an injection).
        $gameRoot = Split-Path (Split-Path (Split-Path $failLog -Parent) -Parent) -Parent
        $acInjected = @($acj.modules |
            ForEach-Object { ($_ -split ':', 2)[-1] } |
            Where-Object {
                $_ -and $_ -notmatch '\\WINDOWS\\|\\System32\\|\\SysWOW64\\' `
                    -and $_ -notmatch 'TslGame\.exe$' `
                    -and ($_ -notlike "*$([regex]::Escape($gameRoot))*") `
                    -and $_ -notmatch '\\PUBG\\|\\steamapps\\|steamclient|GameOverlay|BattlEye'
            } |
            ForEach-Object { Split-Path $_ -Leaf } | Sort-Object -Unique)
    } catch {}
    Line ("  pubg_fail.log found ({0})" -f $acWhen) 'Yellow'
    if ($acCode) { Line ("  Code: {0}   Diagnostic: {1}" -f $acCode, $acDiag) }
    if ($acInjected.Count) { Line ("  Non-Windows modules in the game: {0}" -f (($acInjected | Select-Object -First 8) -join ', ')) }
} else {
    Line '  No pubg_fail.log - no anti-cheat launch block recorded.'
}

# Software known to trip PUBG Shield / BattlEye (overlays, macro/RGB suites, injectors)
$conflictMap = @(
    @{ rx='RTSS|RivaTuner';              name='RivaTuner Statistics Server (RTSS)' }
    @{ rx='MSIAfterburner|Afterburner';  name='MSI Afterburner (overlay)' }
    @{ rx='Overwolf';                    name='Overwolf' }
    @{ rx='obs64|obs32|obs-';            name='OBS (game capture hook)' }
    @{ rx='Fraps|Bandicam|Dxtory';       name='Screen recorder (Fraps/Bandicam/Dxtory)' }
    @{ rx='ArmouryCrate|ArmourySw|ROGLive'; name='ASUS Armoury Crate / ROG Live Service' }
    @{ rx='iCUE|CorsairService';         name='Corsair iCUE' }
    @{ rx='LightingService|LedKeeper';   name='RGB lighting service' }
    @{ rx='Razer|Synapse';               name='Razer Synapse' }
    @{ rx='SteelSeries|GG Engine';       name='SteelSeries GG' }
    @{ rx='Logi.*Options|LGHUB|lghub';   name='Logitech G HUB / Options' }
    @{ rx='Wallpaper64|wallpaper32';     name='Wallpaper Engine' }
    @{ rx='Rainmeter';                   name='Rainmeter' }
    @{ rx='Nahimic|SteelSeriesSonar';    name='Nahimic / Sonar audio overlay' }
    @{ rx='CheatEngine|xenos|Extreme Injector'; name='Memory injector (WILL be blocked)' }
    @{ rx='MacroRecorder|AutoHotkey';    name='Macro tool (AutoHotkey etc.)' }
    @{ rx='DS4Windows|x360ce';           name='Controller remapper (DS4Windows/x360ce)' }
    @{ rx='MSI Center|DragonCenter|GamingHub'; name='MSI Center / Dragon Center' }
)
$running = Get-Process | Select-Object -ExpandProperty Name -Unique
$conflicts = @()
foreach ($c in $conflictMap) { if ($running -match $c.rx) { $conflicts += $c.name } }
$conflicts = @($conflicts | Sort-Object -Unique)
Line ("  Overlay/RGB/macro software running: {0}" -f $(if ($conflicts.Count) { $conflicts -join ', ' } else { 'none detected' })) `
     $(if ($conflicts.Count) { 'Yellow' } else { 'Gray' })

# Hypervisor / virtualization  (PUBG's [MHV] diagnostic + common BattlEye conflict)
$hyperPresent = [bool](Get-CimInstance Win32_ComputerSystem).HypervisorPresent
$vbsRunning = $false; $hvciOn = $false
try {
    $dgi = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
    $vbsRunning = ($dgi.VirtualizationBasedSecurityStatus -eq 2)
    $hvciOn = (@($dgi.SecurityServicesRunning) -contains 2)
} catch {}
Line ("  Hypervisor running:     {0}" -f $hyperPresent) $(if ($hyperPresent) { 'Yellow' } else { 'Gray' })
Line ("  Memory Integrity (HVCI): {0}" -f $hvciOn)       $(if ($hvciOn) { 'Yellow' } else { 'Gray' })

# --------------------------------------------------------------------------
# WINDOWS EVENT LOG
# --------------------------------------------------------------------------
Head 'Windows event log (last 30 days)'
$since = (Get-Date).AddDays(-30)

# Kernel-Power 41 (unexpected shutdown) + bugcheck breakdown
$kp = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=41; StartTime=$since} -ErrorAction SilentlyContinue)
$kp0 = 0; $kpBsod = 0; $kpTimes = @()
foreach ($e in $kp) {
    try {
        $x = [xml]$e.ToXml(); $d = @{}
        $x.Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
        if ([int64]$d.BugcheckCode -eq 0) { $kp0++ } else { $kpBsod++ }
    } catch { $kp0++ }
    $kpTimes += $e.TimeCreated.ToString('yyyy-MM-dd HH:mm')
}
$whea = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=$since} -ErrorAction SilentlyContinue).Count
$tdr  = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=4101; StartTime=$since} -ErrorAction SilentlyContinue).Count

# Rough "system-wide instability" signal: distinct non-PUBG apps that left crash dumps recently
$wer = @(Get-ChildItem "$env:LOCALAPPDATA\CrashDumps\*.dmp" -ErrorAction SilentlyContinue |
         Where-Object { $_.LastWriteTime -gt $since -and $_.Name -notmatch 'Tsl|PUBG' } |
         ForEach-Object { ($_.Name -split '\.')[0] } | Sort-Object -Unique)

Line ("  Kernel-Power 41 (total):    {0}" -f $kp.Count)         $(if ($kp.Count) { 'Yellow' } else { 'Gray' })
Line ("     - no bluescreen (code 0): {0}" -f $kp0)             $(if ($kp0) { 'Yellow' } else { 'Gray' })
Line ("     - with bluescreen:        {0}" -f $kpBsod)
Line ("  WHEA hardware errors:       {0}" -f $whea)             $(if ($whea) { 'Red' } else { 'Gray' })
Line ("  GPU driver timeouts (TDR):  {0}" -f $tdr)              $(if ($tdr) { 'Yellow' } else { 'Gray' })
Line ("  Other apps that crashed:    {0}" -f $wer.Count)

# --------------------------------------------------------------------------
# ANALYSIS
# --------------------------------------------------------------------------
$findings = New-Object System.Collections.ArrayList
function Add-Finding($sev, $title, $detail) { [void]$findings.Add([ordered]@{ severity=$sev; title=$title; detail=$detail }) }

if ($whea -gt 0) {
    Add-Finding 'critical' 'Real hardware errors are being logged (WHEA)' `
        "Windows recorded $whea hardware-level error(s). This is the strongest possible signal that a physical component (RAM, CPU, or the PCIe/GPU link) is faulting. Prioritise the RAM test and check temperatures/PSU."
}
if ($kp0 -gt 0) {
    Add-Finding 'high' 'Your whole PC shut down without a bluescreen' `
        "$kp0 unexpected shutdown(s) with bugcheck code 0 - the machine froze or lost power with no BSOD. That pattern points at power delivery (PSU) or unstable memory, not a clean software fault."
}
if ($kpBsod -gt 0) {
    Add-Finding 'high' 'Bluescreen(s) recorded' `
        "$kpBsod shutdown(s) came with a bugcheck code - an actual BSOD. Note the STOP code next time it happens; it names the faulting driver/component."
}
if (@($wer).Count -ge 2) {
    Add-Finding 'high' 'Unrelated programs are also crashing' `
        ("Recent crash dumps from non-game apps: {0}. When several unrelated programs fail, the cause is usually corrupted memory (unstable RAM/XMP), not any one app." -f (($wer | Select-Object -First 6) -join ', '))
}
if (@($oom).Count -gt 0) {
    $vtxt = if ($vramMB) { " You have $([math]::Round($vramMB/1024,0)) GB of VRAM" } else { '' }
    Add-Finding 'high' "'Out of video memory' errors found in the logs" `
        ("$(@($oom).Count) occurrence(s).$vtxt - if you play at 1080p/1440p you are almost certainly NOT truly out of VRAM. Treat this as instability or a starved pagefile, not a capacity problem.")
}
if (@($rhang).Count -gt 0 -or $tdr -gt 0) {
    Add-Finding 'medium' 'The GPU hung under load' `
        'The render thread stalled / the display driver timed out (TDR). This is a GPU, driver, or GPU-overclock issue - or a PSU that sags when the card spikes.'
}
if ($xmpState -eq 'ON') {
    Add-Finding 'medium' 'Memory overclock (XMP/EXPO) is enabled' `
        "Your RAM is running at its rated $ratedMax MT/s via XMP/EXPO. An unstable memory profile is the single most common hidden cause of PUBG's phantom crashes. Testing with it OFF is the highest-value free experiment."
}
if ($pfBad) {
    Add-Finding 'medium' 'Pagefile is disabled or very small' `
        "Unreal needs system-memory headroom to back GPU resources. A tiny/disabled pagefile causes 'out of video memory' even with VRAM free. Set it to System-managed."
}
$drvVerShown = if ($nvDriver) { "v$nvDriver" } elseif ($gpuW.DriverVersion) { "v$($gpuW.DriverVersion)" } else { '' }
if ($drvVerShown -or $drvDate) {
    Add-Finding 'info' 'GPU driver reference' `
        ("Current driver: $drvVerShown$(if($drvDate){" (dated $drvDate)"}). If your crashes began around when this installed, roll back to the previous version - newer is not always more stable, and a clean reinstall clears corruption.")
}
if ($diskBad) {
    Add-Finding 'high' 'A disk reports non-healthy status' `
        'One of your drives is not reporting Healthy. Failing storage can corrupt game files and cause crashes; back up and check with the maker''s tool.'
}
# ---- anti-cheat / launch-block findings (different failure class) ----
if ($acPresent) {
    Add-Finding 'high' 'PUBG anti-cheat blocked the game from launching' `
        ("PUBG Shield wrote pubg_fail.log on $acWhen$(if($acCode){" (code $acCode$(if($acDiag){", diagnostic $acDiag"}))"}). This is an 'Interrupted by external program' block, NOT an instability crash - the game was stopped at startup because something on the PC looked like it was hooking into it. Reinstalling rarely helps; removing the conflicting software does.")
}
if ($acInjected.Count -gt 0) {
    Add-Finding 'high' 'Third-party code was loaded inside the game process' `
        ("Non-Windows modules present: {0}. Anything here that is not part of PUBG is a prime suspect - close or uninstall it and retry." -f (($acInjected | Select-Object -First 8) -join ', '))
}
if ($conflicts.Count -gt 0) {
    Add-Finding $(if ($acPresent) { 'high' } else { 'medium' }) 'Software running that commonly trips anti-cheat' `
        ("Detected: {0}. Overlays, RGB/macro suites and capture tools inject into games and are the usual cause of 'Application is interrupted by external software'. Fully exit them (tray icons too) before launching." -f ($conflicts -join ', '))
}
if ($acPresent -and $acDiag -match 'MHV') {
    Add-Finding 'high' 'Anti-cheat flagged a hypervisor ([MHV])' `
        ("PUBG's diagnostic tag was $acDiag and this PC has hypervisor running=$hyperPresent, Memory Integrity=$hvciOn. Virtualization layers (Hyper-V, WSL2/Docker, Windows Sandbox, Core Isolation, some VPN/AV sandboxes) can trigger this block. Try turning off Memory Integrity and/or the Hyper-V/Virtual Machine Platform features, reboot, and retry.")
} elseif ($acPresent -and ($hyperPresent -or $hvciOn)) {
    Add-Finding 'medium' 'Virtualization features are active' `
        "Hypervisor running=$hyperPresent, Memory Integrity=$hvciOn. These sometimes conflict with kernel anti-cheat. Worth disabling temporarily as a test if the launch block persists."
}

if ($findings.Count -eq 0) {
    Add-Finding 'info' 'No strong crash signature found' `
        'This scan did not find recorded crash evidence. If PUBG is still crashing, play a session then run this again so it can catch fresh logs, and enable HWiNFO logging for temperatures/voltages.'
}

# Which failure class(es) is this PC showing?
$hasInstability = ($whea -gt 0 -or $kp0 -gt 0 -or $kpBsod -gt 0 -or @($oom).Count -gt 0 -or @($gpuCrash).Count -gt 0 -or @($rhang).Count -gt 0 -or $tdr -gt 0 -or @($wer).Count -ge 2)
$errorClass = if ($acPresent -and $hasInstability) { 'both' }
              elseif ($acPresent) { 'anticheat' }
              elseif ($hasInstability) { 'instability' }
              else { 'none' }

# Headline verdict
$verdict = 'No clear crash pattern detected yet'
if ($whea -gt 0) { $verdict = 'Hardware errors logged - test your RAM and check power/temps first' }
elseif ($kp0 -gt 0 -or @($wer).Count -ge 2) { $verdict = 'Signs of memory/power instability - the XMP-off test is your top priority' }
elseif (@($oom).Count -gt 0 -or @($gpuCrash).Count -gt 0) { $verdict = 'Graphics allocation failures - check pagefile, driver, and overclocks' }
elseif (@($rhang).Count -gt 0 -or $tdr -gt 0) { $verdict = 'GPU hangs under load - driver / overclock / PSU' }
if ($errorClass -eq 'anticheat') {
    $verdict = 'Anti-cheat is blocking launch - close overlay/RGB software (this is not a hardware fault)'
} elseif ($errorClass -eq 'both') {
    $verdict = "$verdict  +  anti-cheat also blocked a launch (two separate problems)"
}

# Fix list for the anti-cheat / launch-block class
$acFixes = @(
    [ordered]@{ step=1; title='Fully exit every overlay, RGB and macro app'; body='Not just close the window - quit from the system tray: RTSS/Afterburner, Overwolf, OBS, Razer Synapse, iCUE, Armoury Crate, G HUB, SteelSeries, Wallpaper Engine, Rainmeter, Nahimic. Relaunch PUBG after each removal to find the culprit.'; relevant=($conflicts.Count -gt 0) }
    [ordered]@{ step=2; title='Turn off in-game overlays'; body='Steam (Settings > In Game), Discord (User Settings > Game Overlay), NVIDIA App/GeForce Experience, Xbox Game Bar, and any browser/hardware overlay.'; relevant=$acPresent }
    [ordered]@{ step=3; title='Remove anything that injects into games'; body='Cheat/injection tools, trainers, unofficial mods or FPS "boosters" will be blocked outright - uninstall them. Some AV "game modes" and sandboxes also hook games.'; relevant=($acInjected.Count -gt 0) }
    [ordered]@{ step=4; title='Test with virtualization off (the [MHV] case)'; body='Turn OFF Core Isolation > Memory Integrity (Windows Security > Device Security), reboot and retry. If it persists and you use Hyper-V/WSL2/Docker/Windows Sandbox, disable those Windows features (or run "bcdedit /set hypervisorlaunchtype off", reboot) as a TEST - re-enable them afterwards if they are not the cause.'; relevant=($acDiag -match 'MHV' -or $hyperPresent -or $hvciOn) }
    [ordered]@{ step=5; title='Repair the anti-cheat / game files'; body='Steam > PUBG > Properties > Installed Files > Verify integrity. Then reinstall BattlEye: run BattlEye\\Install_BattlEye.bat in the game Binaries folder, or reinstall from Steam.'; relevant=$acPresent }
    [ordered]@{ step=6; title='Repair Windows itself'; body='In an admin terminal: "sfc /scannow", then "DISM /Online /Cleanup-Image /RestoreHealth". Corrupted system files can make anti-cheat fail its integrity checks.'; relevant=$acPresent }
    [ordered]@{ step=7; title='Boot clean to identify the conflict'; body='Run msconfig > Services > Hide all Microsoft services > Disable all, reboot, and launch PUBG. If it works, re-enable services in halves until the culprit appears.'; relevant=$acPresent }
)

# Ordered recommendations (mirrors the guide). 'relevant' highlights ones the data supports.
$rec = @(
    [ordered]@{ step=0; title='Set the pagefile to System-managed'; body='Settings > System > About > Advanced system settings > Performance > Advanced > Virtual memory. Fixes many false "out of video memory" errors. Never disable it.'; relevant=[bool]$pfBad }
    [ordered]@{ step=1; title='Roll back / clean-reinstall the GPU driver'; body='If crashes started after a driver update, roll back to the previous version (Device Manager, or DDU in Safe Mode). Turn off automatic driver updates.'; relevant=($tdr -gt 0 -or @($gpuCrash).Count -gt 0) }
    [ordered]@{ step=2; title='Turn off ALL overclocks (including the factory GPU OC)'; body='Close Afterburner; also pull core -100 MHz to test the factory OC. Many "stable" OCs fail in PUBG specifically.'; relevant=(@($rhang).Count -gt 0 -or $tdr -gt 0) }
    [ordered]@{ step=3; title='Disable XMP / EXPO / DOCP and test'; body='Reboot to BIOS, set the memory profile to Disabled/Auto, play. If crashes stop, your RAM overclock was unstable - then run MemTest86 or run at a lower speed / relaxed timings.'; relevant=($xmpState -eq 'ON' -or $kp0 -gt 0 -or @($wer).Count -ge 2 -or $whea -gt 0) }
    [ordered]@{ step=4; title='Verify game files on Steam'; body='PUBG > Properties > Installed Files > Verify integrity of game files.'; relevant=$false }
    [ordered]@{ step=5; title='Cap your framerate'; body='An uncapped FPS (esp. in menus) spikes GPU power draw and can trip a marginal PSU/GPU. Cap at your monitor refresh.'; relevant=$false }
    [ordered]@{ step=6; title='Watch hidden temps/voltages with HWiNFO64'; body='Log GPU Memory-Junction temp (GDDR6 can hit 100C+ while the core looks cool) and the +12V rail (sag under load = PSU).'; relevant=(@($rhang).Count -gt 0 -or $tdr -gt 0 -or $kp0 -gt 0) }
    [ordered]@{ step=7; title='If the whole PC still power-cycles: hardware'; body='Reseat GPU + RAM, use two separate PCIe cables (no daisy-chain), suspect an old/cheap PSU, and test on the CPU''s integrated graphics to isolate the card.'; relevant=($kp0 -gt 0 -or $whea -gt 0) }
)

# --------------------------------------------------------------------------
# BUILD REPORT
# --------------------------------------------------------------------------
$report = [ordered]@{
    tool         = 'PUBG Crash Doctor'
    version      = $TOOL_VERSION
    generatedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    pubgInstalled = [bool]$pubgInstalled
    errorClass   = $errorClass
    verdict      = $verdict
    system = [ordered]@{
        cpu = Clean $cpu.Name; cores = [int]$cpu.NumberOfCores
        ramGB = $ramGB; gpu = Clean $gpuW.Name; gpuVendor = $vendor
        driver = $(if ($nvDriver) { $nvDriver } else { $gpuW.DriverVersion }); driverDate = $drvDate
        vramMB = $vramMB; os = Clean $os.Caption
    }
    memory = [ordered]@{ sticks=@($sticks).Count; ratedMax=$ratedMax; currentMax=$curMax; xmp=$xmpState }
    pagefile = [ordered]@{ allocatedMB=$pfMB; systemManaged=$pfAuto; flagged=[bool]$pfBad }
    disksHealthy = (-not $diskBad)
    evidence = [ordered]@{
        logFiles       = $logFiles.Count
        outOfVideoMem  = @($oom).Count
        gpuCrash       = @($gpuCrash).Count
        renderHang     = @($rhang).Count
        fatalError     = @($fatal).Count
        lastOomLine    = $lastOom
        crashReports   = $crashes.Count
        lastCrash      = $lastCrash
        lastCrashError = $lastCrashErr
        kernelPower41  = $kp.Count
        kp41NoBsod     = $kp0
        kp41Bsod       = $kpBsod
        kp41Times      = @($kpTimes | Select-Object -First 8)
        wheaErrors     = $whea
        gpuTimeouts    = $tdr
        otherAppCrashes= @($wer | Select-Object -First 8)
    }
    anticheat = [ordered]@{
        blocked        = [bool]$acPresent
        logPath        = $failLog
        lastBlock      = $acWhen
        code           = $acCode
        diagnostic     = $acDiag
        injectedModules= @($acInjected | Select-Object -First 10)
        conflictingApps= @($conflicts)
        hypervisor     = [bool]$hyperPresent
        memoryIntegrity= [bool]$hvciOn
    }
    findings = @($findings)
    recommendations = @($rec)
    anticheatFixes = @($acFixes)
}

$json = $report | ConvertTo-Json -Depth 8
$jsPath = Join-Path $OutDir 'report-data.js'
Set-Content -Path $jsPath -Value "window.PUBG_REPORT = $json;" -Encoding UTF8

Head 'Verdict'
Line ("  $verdict") 'White'
Line ("`n  Report written: $jsPath" ) 'DarkGray'

$indexPath = Join-Path $OutDir 'index.html'
if ((-not $NoBrowser) -and (Test-Path $indexPath)) {
    Line "  Opening dashboard in your browser..." 'DarkGray'
    Start-Process $indexPath
} else {
    Line "  Open index.html in your browser to see the full dashboard." 'DarkGray'
}
Line ""

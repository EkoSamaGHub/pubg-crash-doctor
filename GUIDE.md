# PUBG keeps crashing / "Out of video memory"? Read this before you buy anything.

*A diagnostic guide for PUBG (and other Unreal Engine games) that crash to desktop, throw "Out of video memory trying to allocate a rendering resource," freeze, or randomly power off the whole PC.*

If you're here, you've probably already tried the usual advice — lower settings, update drivers, verify files — and it didn't help. That's because most guides treat the symptom, not the cause. This one teaches you to **read the actual evidence on your machine** and fix the real problem.

---

## The single most important thing to understand

> **The error "Out of video memory trying to allocate a rendering resource. Make sure your video card has the minimum required memory, try lowering the resolution…" is usually NOT about running out of video memory.**

If you have an 8 GB+ card and you're playing at 1080p or 1440p, you are *not* actually filling your VRAM. You can prove it in 30 seconds:

- Open **Task Manager → Performance → GPU**, watch **Dedicated GPU memory** while you play.
- When it crashes, was memory anywhere near the limit? On a 12 GB card at 1080p you'll typically be using 4–9 GB. Nowhere close.

So why the error? Because that message is what Unreal shows whenever a graphics allocation **fails** — and an allocation can fail for reasons that have nothing to do with capacity: an unstable memory overclock corrupting data, a shaky GPU overclock, a starved Windows pagefile, a flaky driver, or a GPU/PSU that hangs under load. **The error text points you at the one thing that's usually innocent (VRAM) and away from the real culprits.**

Once you stop trusting the error message, you can actually diagnose it.

---

## First: which problem do you actually have?

There are **two completely different failure classes**, and they need opposite fixes. Check which one matches you before reading further:

| You see… | Class | Read |
|---|---|---|
| "Out of video memory", crash-to-desktop **mid-game**, freezes, PC powers off | **Instability** | The rest of this guide |
| **"Interrupted by external program"** / "Application is interrupted by external software", PUBG Shield Reporter, `pubg_fail.log`, codes like `00000252/0021` or `[MHV]` — usually **at launch** | **Anti-cheat block** | The section right below |

Getting this wrong wastes days — people replace RAM over an anti-cheat conflict, or reinstall Windows over unstable memory.

---

## Class B — "Interrupted by external program" (PUBG Shield / BattlEye)

This means **PUBG's anti-cheat stopped the game from starting** because something on your PC looked like it was hooking into the game. Your hardware is almost certainly fine, and **"please reinstall the program" is bad advice** — reinstalling rarely fixes it.

The dialog names a log at `…\PUBG\TslGame\Binaries\Win64\pubg_fail.log`. That file is JSON (UTF-16) and contains the real clues: an error `code`, a `diagnostic` tag, and the full list of **modules loaded inside the game**.

**Fix it in this order:**

1. **Fully exit every overlay, RGB and macro app** — and I mean *quit from the system tray*, not just close the window. The usual offenders: **RivaTuner/RTSS, MSI Afterburner, Overwolf, OBS, Razer Synapse, Corsair iCUE, ASUS Armoury Crate, Logitech G HUB, SteelSeries GG, Wallpaper Engine, Rainmeter, Nahimic**. Relaunch after removing each one to find the culprit.
2. **Turn off in-game overlays** — Steam (Settings → In Game), Discord (Game Overlay), NVIDIA App / GeForce Experience, Xbox Game Bar.
3. **Uninstall anything that injects into games** — trainers, unofficial mods, "FPS boosters", cheat tools. These are blocked by design. Some antivirus "game modes" and sandboxes hook games too.
4. **If your log shows `[MHV]` — suspect virtualization.** This tag appears alongside hypervisor-based features. Turn **off Core Isolation → Memory Integrity** (Windows Security → Device Security), reboot, retry. If it persists and you run **Hyper-V, WSL2, Docker Desktop, Windows Sandbox, or a VM platform**, disable those Windows features as a *test* (`bcdedit /set hypervisorlaunchtype off`, reboot — reverse with `…/set hypervisorlaunchtype auto` if it wasn't the cause).
5. **Repair game + anti-cheat** — Steam → Verify integrity, then reinstall BattlEye (`BattlEye\Install_BattlEye.bat` in the game's Binaries folder).
6. **Repair Windows** — `sfc /scannow`, then `DISM /Online /Cleanup-Image /RestoreHealth`. Corrupt system files make anti-cheat fail its integrity checks.
7. **Clean boot to isolate it** — `msconfig` → Services → *Hide all Microsoft services* → Disable all → reboot → launch. If it works, re-enable in halves until the conflict reappears.

> **Note on `[MHV]`:** Krafton doesn't publish what its diagnostic tags mean. The hypervisor link is a strong, widely-reported correlation — not an official definition. Treat step 4 as a high-value *test*, not a guarantee.

Official Krafton note on this error: [support.pubg.com](https://support.pubg.com/hc/en-us/articles/360044878374-When-I-start-the-game-I-see-a-Xenuine-error-message-that-says-Application-is-interrupted-by-external-software)

---

## Class A — crashes & instability

## Step 1 — Read the evidence (don't guess)

Your PC already recorded what happened. Three places to look:

### A) PUBG's own logs
Paste this into the address bar of File Explorer:
```
%LOCALAPPDATA%\TslGame\Saved\Logs
```
Open the most recent `TslGame.log` (and the `-backup-` ones) and search for:
- `LogGPUCrash` — the graphics driver crashed
- `E_OUTOFMEMORY` — the phantom video-memory error
- `RenderThread` / `GameThread timed out waiting for RenderThread` — **the GPU hung** (froze for 30+ seconds)

Crash dumps live next door in `…\TslGame\Saved\Crashes`.

### B) Windows Event Viewer — the most useful source
Press `Win+R`, type `eventvwr`, go to **Windows Logs → System**. Look for events around your crash times:

| What you see | What it means |
|---|---|
| **Kernel-Power, Event ID 41** | The PC died without a clean shutdown (freeze or power loss). |
| **Event ID 41 with `BugCheckCode 0`** | No bluescreen happened — raw freeze or power cut. Points at **power or memory**, not a clean software fault. |
| **Event ID 41 with a non-zero BugCheckCode** | There WAS a bluescreen — look the code up, it names the culprit. |
| **WHEA-Logger** (any) | Genuine **hardware** error (CPU/RAM/PCIe). Rare but the strongest possible clue. |
| **Event ID 4101 / "nvlddmkm"** | "Display driver stopped responding and has recovered" (a TDR) = **GPU hang**. |

### C) Match the pattern to the cause
This is the whole diagnosis in one table:

| Symptom pattern | Most likely class |
|---|---|
| Only the game closes, you're back at a normal desktop, `LogGPUCrash` in the log | GPU driver or **GPU/overclock** instability |
| Whole PC freezes or reboots, **no** bluescreen, **no** WHEA event | **Power supply or system RAM** instability |
| Bluescreen with a bugcheck code | Look up that specific code |
| **Other, unrelated apps also crash randomly** (browser, Discord, background tools) | **Memory corruption** — almost always RAM/XMP |
| "Out of video memory" but VRAM was nowhere near full | Instability or **pagefile** — not capacity |

That last row about unrelated apps crashing is a huge tell. Software doesn't fail in three different ways at once. Corrupted memory does.

---

## Step 2 — The fixes, cheapest and most-likely first

Do these **in order** and test after each. Don't skip ahead to buying parts.

### Fix 0 — Set a proper Windows pagefile *(free, fixes a surprising number of "out of video memory" cases)*
Unreal needs system-memory "commit" headroom to back its GPU resources. If your pagefile is disabled or tiny, allocations fail with a video-memory error even though VRAM is fine.
- **Settings → System → About → Advanced system settings → Performance → Settings → Advanced → Virtual memory → Change.**
- Set it to **System managed**, all drives, and reboot. (If you must set it manually, 1.5×–2× your RAM.)
- **Never** run with the pagefile disabled, no matter what an "optimization" guide told you.

### Fix 1 — GPU driver: clean reinstall, or roll BACK
- **If the crashes started right after a driver update, roll back** — the newest driver is not always the most stable. Device Manager → your GPU → Properties → Driver → **Roll Back Driver**, or grab the previous version from NVIDIA/AMD and do a **clean install** (or use [DDU](https://www.wagnardsoft.com/display-driver-uninstaller-ddu-) in Safe Mode first).
- Then **turn off automatic driver updates** so it doesn't silently reinstall the bad one.
- Rolling back is also the *test*: if crashes continue on a known-good older driver, the driver was innocent — move on.

### Fix 2 — Stop ALL overclocking, including your card's *factory* OC
- Close MSI Afterburner / any OC tool. But also: most "OC edition" cards ship with a factory overclock that is stable in most games and **not** stable in PUBG specifically.
- In Afterburner, pull **Core Clock −100 MHz** (and Memory −100) and test. If that fixes it, your GPU overclock — even the factory one — was the problem. You can then dial in a mild stable undervolt/underclock.

### Fix 3 — Test your RAM at stock speed: **disable XMP** *(the big underrated one)*
This is the fix that gets missed the most, and it produces *exactly* the phantom "out of video memory" + random-power-off + unrelated-apps-crashing pattern.
- Reboot into BIOS (usually `Del` or `F2` at boot).
- Find **XMP** (Intel) / **EXPO** (AMD Ryzen) / **DOCP** or **AMP** (ASUS/Gigabyte naming) and set it to **Disabled / Auto**.
- Your RAM now runs at the JEDEC default (e.g. 2400 instead of 3200). Save, exit, and play.

**If the crashes stop, your memory overclock was unstable.** That's your answer. You don't have to live at the slow speed forever — once confirmed, you can:
- Run **MemTest86** (free, boots from a USB stick) to find whether one specific stick is faulty — replace it and you get full speed back permanently; **or**
- Re-enable XMP but at a **lower speed** (try 3000 instead of 3200), or with **slightly relaxed timings**, or a small **DRAM voltage** bump (e.g. +0.05 V). Test each for stability.

> Expect to lose ~10–20% FPS with XMP off. That's normal and temporary — PUBG is very sensitive to memory speed. It's a diagnostic cost, not damage.

### Fix 4 — Verify game files
Steam → Library → **PUBG → Properties → Installed Files → Verify integrity of game files.** Rules out corruption cheaply.

### Fix 5 — Cap your framerate
An uncapped framerate (especially in menus/lobbies) makes the GPU spike to maximum transient power draw, which can trip an unstable PSU or a marginal GPU. Set an in-game or driver-level FPS cap at your monitor's refresh rate.

### Fix 6 — Watch the *hidden* temps and voltages with HWiNFO64
[HWiNFO64](https://www.hwinfo.com) (free) shows sensors that Task Manager and the error message can't:
- **GPU Memory Junction Temperature** — GDDR6 can hit 95–105 °C and throttle/error while the *core* still reads a cool 55 °C. A dying or dusty card shows here first.
- **GPU Hot Spot** — same idea.
- **+12V rail** — if this sags under load (e.g. dips toward 11.4 V or below when the action starts), suspect the **power supply**.

Start HWiNFO in "Sensors only" mode, hit the **logging** button to record to a CSV, play until it crashes, then read the last rows to see what the hardware was doing at the moment of death.

### Fix 7 — If the whole PC still power-cycles: hardware
- **Reseat** the GPU and RAM sticks. Try one RAM stick at a time.
- Check the **PSU cables**: the GPU should be fed by **two separate PCIe cables**, not one cable with a daisy-chained "pigtail" second connector.
- Suspect the **PSU** if it's old, cheap, or underpowered for your card — a tired PSU produces every symptom above, including GPU hangs.
- **Isolate the GPU for free:** if your CPU has integrated graphics, plug your monitor into the *motherboard's* video output and run on the iGPU for a day. If the crashing stops, the graphics card (or its power delivery) is guilty.

---

## A real example (so this isn't abstract)

- **Rig:** RTX 3060 12 GB, i7-11700K, 2×16 GB DDR4 running XMP at 3200, playing at 1080p.
- **Symptoms:** "Out of video memory" every few minutes; sometimes the whole PC powered off with no bluescreen; even Game Bar and other background apps left crash dumps.
- **What the logs showed:** `LogGPUCrash: E_OUTOFMEMORY` with ~10 GB of VRAM free, one crash where the GPU hung waiting on the render thread for 30 s, six `Kernel-Power 41` events with BugCheckCode 0 (no bluescreens), and **zero** WHEA/TDR events.
- **The tell:** phantom VRAM errors + no bluescreens + *unrelated* apps crashing = memory corruption, not a game bug and not a real VRAM shortage.
- **The fix:** rolling the driver back didn't help (ruled it out). **Disabling XMP did** — the game then ran **83 minutes straight and exited cleanly**, where before it died in 1–7 minutes. Next step is MemTest86 to decide between a bad stick vs. just running the RAM a notch slower.

The point isn't "XMP is always the answer." The point is that **the method** — read the logs, match the pattern, eliminate in order — found the real cause, which the on-screen error was actively pointing away from.

---

## Appendix — copy-paste diagnostics (Windows PowerShell)

All read-only; they just report what already happened. Right-click Start → **Terminal** and paste.

**Find crash signatures in PUBG's logs:**
```powershell
Get-ChildItem "$env:LOCALAPPDATA\TslGame\Saved\Logs\*.log" |
  Select-String -Pattern 'LogGPUCrash|E_OUTOFMEMORY|RenderThread|LowLevelFatalError' |
  Select-Object -Last 20
```

**List unexpected shutdowns / freezes (Kernel-Power 41) and see if a bluescreen was involved:**
```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; Id=41} -MaxEvents 10 | ForEach-Object {
  $x=[xml]$_.ToXml(); $d=@{}; $x.Event.EventData.Data | ForEach-Object { $d[$_.Name]=$_.'#text' }
  [pscustomobject]@{ Time=$_.TimeCreated; BugCheck=$d.BugcheckCode }
}
```
`BugCheck = 0` means no bluescreen (suspect power/RAM); non-zero means look the code up.

**Check for real hardware errors (WHEA) in the last 30 days:**
```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=(Get-Date).AddDays(-30)} -ErrorAction SilentlyContinue |
  Select-Object TimeCreated, Id, LevelDisplayName
```
No output = good (no logged hardware faults).

**See your RAM's actual running speed (to confirm XMP is on/off):**
```powershell
Get-CimInstance Win32_PhysicalMemory | Select-Object PartNumber, Speed, ConfiguredClockSpeed
```

**See your GPU driver version and date:**
```powershell
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate
```

---

## TL;DR checklist

1. ✅ Don't trust the "video memory" text — confirm in Task Manager that VRAM isn't actually full.
2. ✅ Read Event Viewer: **41 / BugCheck 0** = power/RAM; **WHEA** = hardware; **4101/nvlddmkm** = GPU hang.
3. ✅ Set pagefile to **System managed**.
4. ✅ **Roll back** the GPU driver if crashes started after an update; disable auto-updates.
5. ✅ Turn off overclocks — including the **factory** GPU OC (test −100 MHz core).
6. ✅ **Disable XMP/EXPO/DOCP** and test. If fixed → MemTest86, or run RAM slower / relaxed.
7. ✅ Verify files, cap FPS, watch **GPU memory-junction temp** and **+12V** in HWiNFO64.
8. ✅ Still power-cycling? Reseat parts, check PSU cables, test on the iGPU, suspect the PSU.

Work top to bottom, test after each step, and you'll usually find it well before you spend a cent.

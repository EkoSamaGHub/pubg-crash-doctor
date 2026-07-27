# 🎮🩺 PUBG Crash Doctor

**A tiny, read-only tool that tells you *why* PUBG keeps crashing — and what to fix, cheapest first.**

If PUBG crashes to desktop, throws **“Out of video memory trying to allocate a rendering resource”**, freezes, or hard-powers-off your whole PC — and the usual "lower settings / verify files" advice hasn't helped — this reads the evidence your machine already recorded and points you at the real cause.

> **The key insight:** that "out of video memory" error is usually **lying**. On an 8 GB+ card at 1080p/1440p you are *not* actually out of VRAM. The real cause is normally an unstable **RAM/XMP** profile, a shaky **overclock**, a starved **pagefile**, a bad **driver**, or a tired **PSU**. This tool finds which one.

---

## What it does

`diagnose.ps1` runs a **read-only** scan and builds a local report that `index.html` renders in your browser:

- **PUBG logs** — `LogGPUCrash`, `E_OUTOFMEMORY`, render-thread hangs, fatal errors
- **Windows Event Viewer** — Kernel-Power **41** (with/without bluescreen), **WHEA** hardware faults, GPU driver **TDRs**
- **Memory** — XMP/EXPO state, actual vs rated speed
- **System** — pagefile config, GPU driver + date, VRAM, disk health
- Cross-checks whether **other, unrelated apps** are also crashing (a classic sign of bad RAM)

Then it prints a **verdict**, a ranked list of **likely causes**, and an **ordered fix list** with the steps your specific scan points to highlighted.

## What it does **not** do

- ❌ It changes **nothing** on your system — every command only *reads*.
- ❌ It uploads **nothing**. The report (`report-data.js`) stays on your disk. You choose whether to share it.
- ❌ It is not official PUBG/KRAFTON software. It's a community troubleshooting aid.

Inspect `diagnose.ps1` yourself before running — it's short and commented.

---

## How to run (Windows 10/11)

1. **Download** — green **`Code ▾` → Download ZIP**, then unzip anywhere. *(or `git clone` this repo)*
2. **Run** — double-click **`Run-Diagnostic.bat`**, or right-click **`diagnose.ps1`** → **Run with PowerShell**.
3. **Read** — your browser opens `index.html` with your results.

Command-line equivalent:

```powershell
powershell -ExecutionPolicy Bypass -File diagnose.ps1
```

No install, no dependencies. Works best on NVIDIA (uses `nvidia-smi` for exact VRAM) but runs on any GPU.

---

## The fixes it recommends (in order)

Cheapest & most-likely first — do them one at a time and test after each:

0. **Set the pagefile to System-managed** — fixes many false "out of video memory" errors.
1. **Roll back / clean-reinstall the GPU driver** — newer isn't always more stable; disable auto-updates.
2. **Turn off ALL overclocks**, including your card's *factory* OC (test core −100 MHz).
3. **Disable XMP / EXPO / DOCP** and test — the single most underrated fix. If crashes stop, your RAM overclock was unstable.
4. **Verify game files** on Steam.
5. **Cap your framerate** — uncapped FPS spikes power draw and can trip a marginal PSU/GPU.
6. **Watch hidden temps/voltages** with [HWiNFO64](https://www.hwinfo.com) — GPU **memory-junction** temp and the **+12V rail**.
7. **Still power-cycling? Hardware** — reseat GPU + RAM, use two separate PCIe cables, suspect an old PSU, test on the CPU's integrated graphics to isolate the card.

A longer written walkthrough of the method (reading logs, matching the crash pattern to a cause) is in [`GUIDE.md`](GUIDE.md).

---

## Sharing your result when asking for help

Click **“Copy summary for a forum post”** in the dashboard — it copies a clean, paste-ready summary (specs + evidence + top findings) with no personal file paths. Great for r/PUBATTLEGROUNDS, the Steam forums, or a Discord.

## Privacy

The scan reads system info (CPU/GPU/RAM model, driver version), PUBG log contents, and Windows crash/power event timestamps, and writes them to `report-data.js` **on your machine only**. `report-data.js` is git-ignored so you can't accidentally commit your own data.

## Contributing

Issues and PRs welcome — especially AMD/Intel telemetry, more crash signatures, and translations.

## License

MIT — see [`LICENSE`](LICENSE). No warranty; hardware/BIOS changes are at your own risk.

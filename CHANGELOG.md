# Changelog

## 0.2.0 - 2026-10-24
**Windows 10 support; project renamed to WinDebloat Tool.**

- Target OS detection: image build from DISM (10240–21999 = Windows 10, 22000+ = Windows 11); the GUI
  guesses from the file name, then from the install.wim/esd XML header of the mounted ISO (Windows 8+),
  or from the downloaded version. Manual override: *Target OS* box / `-TargetOs Auto|Win10|Win11`.
- Separate Windows 10 profile in `config/DebloatConfig.psd1` (`Win10Apps`, `Win10Tweaks`): removes
  3D Builder/Viewer, Print 3D, Mixed Reality Portal, People, Skype, Mobile Plans, Wallet, Messaging,
  Weather, News, Get Help, Tips, Office hub, OneNote, Solitaire, Xbox apps, Your Phone, Feedback Hub,
  Cortana (+ newer Store apps if present); optional: Groove, Movies & TV, Maps, Paint 3D, Mail, Camera,
  Alarms, Voice Recorder, Sticky Notes. Tweaks: consumer features, CDM silent installs/suggestions,
  Cortana/web search, telemetry minimum, News and Interests, Meet Now, Copilot, optional OneDrive setup removal.
- New tweak action `DeleteValue` (registry value removal).
- autounattend.xml: the BypassNRO command is removed automatically for Windows 10 images.
- Microsoft download: Windows 10 22H2 (x64 and x86) next to Windows 11 x64/arm64; architecture-aware
  SHA256 lookup (the Windows 10 page lists 32-bit and 64-bit hashes).
- Fix: a successful Microsoft API response without an `Errors` field was treated as an error
  (`@($null).Count` is 1 in PowerShell).
- Rename: main script `WinDebloatTool.ps1`; `Win11DebloatTool.ps1` kept as a forwarding wrapper;
  `run.bat` prefers the new script and falls back to the old one; work folder/log names `WinDebloat_*`.
- Tests: OS detection, WIM header parser (synthetic Windows 10 WIM, optional real WIM), Windows 10
  profile and tweaks, per-OS autounattend, mocked Windows 10 download flow.

## 0.1.0 - 2026-10-24
First public version.

- WinForms GUI (works on Windows PowerShell 2.0+): pick a local ISO **or** download the official ISO
  straight from Microsoft (release / architecture / language lists come from Microsoft), progress bar,
  SHA256 check against the hash table Microsoft publishes, browser fallback.
- Checkbox list of apps to remove (defaults = reference build), registry tweaks, autounattend.xml,
  edition choice (All / Home+Pro / custom indexes), component cleanup, dry run.
- Background runspace for all long work; Cancel stops after the current step; log pane + log file.
- Console mode (`-NoGui`), `-WhatIf`/`-DryRun`, `-Check` system report.
- Servicing via `dism.exe` (ADK > system > the ISO's own DISM), `reg.exe` offline hives,
  `oscdimg.exe` BIOS+UEFI ISO, SHA256 of the result.
- Windows 7 SP1 / 8.x support paths: 7-Zip ISO extraction, ISO DISM fallback, manual
  app deprovisioning, TLS 1.2 detection (experimental, see README).
- oscdimg acquisition: official ADK installer (Deployment Tools only, signature checked) or winget.

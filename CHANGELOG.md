# Changelog

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

# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.0 — 2026-10-26

### Added
- **App and tweak lists in JSON** (`data/apps.json`, `data/tweaks.json`): names and descriptions in all four
  UI languages, `level` (safe / aggressive / unsafe), `default`, `os`, build range, registry operations with
  undo information. The GUI builds its checklists from them and shows the description as a tooltip. Entries
  with mistakes are skipped with a warning. A small built-in JSON reader keeps PowerShell 2.0 working
  (ConvertFrom-Json → JavaScriptSerializer → own parser). The 1.0 defaults are unchanged (checked by a test).
- New optional tweaks (off by default): minimum telemetry, advertising ID, tailored experiences, web search,
  Recall, Widgets, Reserved Storage, OneDrive setup, and a Windows 11 setup-check bypass (`LabConfig`) that is
  also written into `boot.wim`. Tweaks can now use the `SYSTEM` and `DEFAULT` hives.
- **Generated autounattend.xml** (new *Unattended setup* tab and console parameters): local administrator
  account with an optional password (plain text, with a warning), BypassNRO, skip the TPM / Secure Boot /
  RAM checks, region and keyboard, skip the privacy questions, and a first-logon script that removes the
  selected apps again if Setup brought them back. Windows 10 and 11, amd64 and arm64. No disk configuration.
  Without options the file is identical to the 1.0 template.
- **Offline updates** (new *Updates* tab, `-UpdatesPath`): integrates `.msu` / `.cab` files from a folder in
  the order SSU → LCU → .NET; optional `boot.wim` (SSU + LCU) and WinRE (SSU + Safe OS) servicing and
  `StartComponentCleanup /ResetBase` (with a warning). A package that fails or does not apply is logged and
  skipped. Nothing is downloaded.
- **Presets**: built-in *An toàn / Safe* and *Gọn tối đa / Aggressive*, save and load your own `.json`
  (never with a password); `-Preset` on the console.
- **Simple mode**: at start the tool asks *Simple* or *Advanced* (*Remember my choice* stores it in
  `settings.psd1`; switch links in both windows; `-Mode Simple|Advanced`). The Simple window has Windows 11/10,
  ISO language (follows the UI language; Vietnamese falls back to English International because Microsoft
  has no Vietnamese ISO) and an output folder with a free-space check. One **START** button installs oscdimg
  if needed, downloads the newest official ISO from Microsoft (SHA256 checked; mirror offer if Microsoft
  refuses), keeps Home + Pro and applies the Safe preset, with progress, step text, log, Cancel and
  *Open folder*. Console: `-Simple` (with `-OutputFolder`, `-IsoLanguage`, `-IsoPath`, `-DryRun`).
- **Automatic oscdimg**: the official ADK installer is checked for a Microsoft signature (where
  `Get-AuthenticodeSignature` exists), exit codes 0 / 3010 are accepted, missing administrator rights and no
  internet give clear messages; Windows 7 SP1 / 8.x hosts try the official ADK for Windows 10, version 1607
  (best effort), otherwise a "copy oscdimg into tools" message.
- New button icons (`sliders`, `package`, `rocket`); new tests for the JSON reader, data files, answer file, presets,
  update ordering / failure handling and a mocked pipeline with updates, WinRE, `boot.wim` and a preset.

### Changed
- The options area is now a tab control (Options / Unattended setup / Updates) with a preset row below the
  lists; pages scroll instead of clipping text at large fonts.
- `boot.wim` is serviced on a copy outside the ISO tree; on any failure the original is kept.
- *Home + Pro* is chosen by edition ID `Core` / `Professional` (edition IDs from the WIM XML when DISM
  prints translated labels; localized names as a fallback), so N / Single Language editions are never kept.
- README: "About the author" section; the watermark shows a tooltip about the author (4 languages).
- License and README copyright line: "Copyright (c) 2026 TaiNT13@PNC STG & WinDebloat Tool contributors".

### Credits
- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) (MIT) and
  [farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows) (MIT): reference
  for the new privacy tweaks and the preset idea.
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) (MIT): app list and ratings (as in 1.0).
- [ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder): ideas only (it has no license; no
  code was copied).

## 1.0.0 — 2026-10-26
Initial release.

### Added
- Builds a debloated, bootable (BIOS + UEFI) installation ISO from an official Windows 10 or Windows 11 ISO,
  using only Microsoft tools (DISM, reg.exe, oscdimg).
- Graphical interface (WinForms) with a resizable layout, plus a console mode (`-NoGui`) and a dry run
  (`-DryRun` / `-WhatIf`).
- Detects the target OS and release from the image build (Windows 11 21H2 – 26H2, Windows 10 1507 – 22H2),
  with a build-aware app and tweak profile; it can also be chosen by hand.
- Built-in download of official ISOs from Microsoft for every release, language and architecture
  Microsoft still serves. Uses aria2 multi-connection downloads (bundled) with resume, falls back to the
  built-in downloader, and checks the SHA256 when Microsoft publishes it.
- Optional mirror fallback for original Microsoft files listed on massgrave.dev. It is only offered when
  Microsoft cannot deliver, needs confirmation, and a mandatory SHA256 check deletes any file that does not
  match.
- App removal with safe defaults, optional extras and opt-in *unsafe* packages; core components (Store,
  Windows Security, Edge, WebView2, runtimes, codecs, App Installer) are protected.
- Offline Registry tweaks: consumer features, Copilot, Widgets feed, Teams/Chat auto-install, new-user
  suggestions, OOBE auto-install tasks; on Windows 10 also Cortana and web search, minimum telemetry,
  News and Interests, Meet Now and optional OneDrive setup.
- Edition selection: all, Home + Pro, or index list.
- Optional `autounattend.xml` for a local account without the Microsoft account screens (BypassNRO on
  Windows 11).
- Image options: LZX (`install.wim`) or ESD (`install.esd`) compression, optional WinSxS component cleanup,
  and an optional split of a > 4 GB `install.wim` into `install*.swm` for FAT32 USB sticks.
- Every kept edition is exported into a fresh image. Temporary files are kept out of the ISO tree, and the
  log records sizes for each step with a warning when the output ISO is much larger than the source.
- Safe work folder handling: leftovers of an earlier run are detected and cleaned (offline hives unloaded,
  mounted images discarded), folders with foreign files are never deleted, and the work folder is cleaned
  after a finished, failed or cancelled run.
- **Install oscdimg** button that installs only the Windows ADK Deployment Tools (signature checked, or via
  winget), and a **System check** report.
- Interface in Vietnamese, English, Simplified Chinese and Khmer; dialogs and status show the selected
  language, and the log file is bilingual (English / Vietnamese).
- App icon and button icons that scale with the display DPI.
- Runs on Windows 7 SP1 to Windows 11 with Windows PowerShell 2.0 or newer.

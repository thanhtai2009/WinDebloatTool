# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.2.1 — 2026-11-02

### Added
- Simple mode: build from a local ISO file as an alternative to downloading from Microsoft.
- Local ISOs are validated before use; the detected Windows version is shown and selected.

### Changed
- Simple window: larger minimum size to fit the ISO source option.

## 1.2.0 — 2026-11-01

### Added
- Newest ISO check in both windows: finds the latest Windows 10 / 11 release on Microsoft's download pages.
- Simple mode always builds from the newest release, with the built-in list as offline fallback.
- Automatic background update of the app and tweak lists, verified by SHA256 (can be turned off).

### Changed
- New app and button icon set.

## 1.1.0 — 2026-10-26

### Added
- Simple mode: one-click build (download, Home + Pro, Safe preset) with progress and cancel.
- Mode chooser at startup, with an option to remember the choice.
- Presets: built-in Safe and Aggressive, plus saving and loading custom presets.
- Unattended setup tab: generates `autounattend.xml` (local account, hardware-check bypass, region, privacy).
- Updates tab: integrates offline `.msu` / `.cab` updates into the image, boot image and WinRE.
- New optional privacy tweaks (telemetry, advertising ID, web search, Recall, Widgets and more).
- Optional Windows 11 hardware-requirement bypass, also applied to Windows Setup.
- App and tweak descriptions as tooltips in all four languages.
- Automatic oscdimg installation with signature check and clear error messages.

### Changed
- App and tweak lists moved to editable data files.
- Options are now organized in tabs and scroll at large font sizes.
- Home + Pro selection now works on all languages and never keeps N or Single Language editions.
- The boot image is modified on a copy; the original is kept if anything fails.
- Updated copyright notice.

### Credits
- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) and
  [farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows) (MIT): privacy tweaks
  and presets.
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) (MIT): app list and ratings.
- [ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder): ideas only, no code copied.

## 1.0.0 — 2026-10-26
Initial release.

### Added
- Builds a debloated, bootable (BIOS + UEFI) ISO from an official Windows 10 or 11 ISO using Microsoft tools only.
- Graphical interface, console mode and dry run.
- Automatic detection of the Windows version and release in the image.
- Official ISO download from Microsoft with fast resumable downloads and SHA256 verification.
- Optional verified mirror when Microsoft cannot deliver.
- App removal with safe defaults; core components are protected.
- Offline registry tweaks for ads, suggestions, Copilot, Widgets, Teams and more.
- Edition selection: all, Home + Pro, or custom.
- Optional unattended setup with a local account.
- Image options: compression, component cleanup, split for FAT32 USB drives.
- Safe work-folder handling and automatic cleanup after every run.
- One-click oscdimg installation and a system check report.
- Interface in Vietnamese, English, Simplified Chinese and Khmer.
- Runs on Windows 7 SP1 to Windows 11 with PowerShell 2.0 or newer.

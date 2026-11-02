<p align="center">
  <img src="assets/icon-256.png" alt="WinDebloat Tool" width="128">
</p>

<h1 align="center">WinDebloat Tool</h1>

<p align="center">
  Build a clean Windows 10 / 11 installation ISO from the official Microsoft ISO.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/PowerShell-2.0%2B-5391FE.svg?logo=powershell&logoColor=white" alt="PowerShell 2.0+">
  <img src="https://img.shields.io/badge/Windows-7%20%E2%80%93%2011-0078D6.svg" alt="Windows 7 – 11">
</p>

<p align="center">
  English · <a href="README_VI.md">Tiếng Việt</a>
</p>

---

## Overview
WinDebloat Tool removes preinstalled apps and turns off ads, suggestions and automatic app installs inside
the Windows installation image, so every PC set up from the resulting ISO starts clean. It can download the
official ISO directly from Microsoft or work with an ISO already on the PC. **Simple** mode builds a
ready-to-use ISO with one click; **Advanced** mode gives full control over apps, tweaks, editions and setup
options. The interface is available in Vietnamese, English, Simplified Chinese and Khmer, and the tool runs
on Windows 7 SP1 or later with PowerShell 2.0 or newer.

## Highlights
- Official ISO download from Microsoft, verified by SHA256, or use of an existing local ISO.
- Removal of preinstalled apps with safe defaults; core components such as Store and Windows Security are protected.
- Offline Registry tweaks for ads, suggestions, Copilot, Widgets, telemetry and more.
- Choice of editions (for example Home + Pro), optional unattended setup with a local account, and offline updates.
- Bootable BIOS + UEFI ISO with a SHA256 file and a detailed log.
- Built-in and custom presets; app and tweak lists in [`data/`](data) are easy to review and edit.

## Quick start
1. Download `WinDebloatTool_v1.2.0.zip` from [Releases](https://github.com/thanhtai2009/WinDebloatTool/releases/latest).
2. Right-click the zip → **Properties** → tick **Unblock**, then extract it.
3. Double-click **`run.bat`** and accept the administrator prompt.
4. Choose **Simple** for a one-click build, or **Advanced** for full control, then press **START**.
5. Write the finished ISO to a USB drive with Rufus or Ventoy, or use it in a virtual machine.

A build usually takes 30–90 minutes. See [CHANGELOG.md](CHANGELOG.md) for what is new in each version.

## Requirements
- Windows 7 SP1 or newer (Windows 10 / 11 recommended), PowerShell 2.0 or newer.
- Administrator rights (`run.bat` requests them).
- About 25 GB of free disk space.
- Internet access only when downloading an ISO or installing oscdimg (installed automatically from the
  official Windows ADK when missing).
- Windows 7 additionally needs 7-Zip and `oscdimg.exe` in `tools\`; downloads require TLS 1.2 support.

## Safety
- Only Microsoft tools are used to modify the image (DISM, reg.exe, oscdimg); the bundled aria2 is used for downloads only.
- The source ISO is never modified; the tool writes a new ISO and cleans up its work folder.
- Downloads are checked against Microsoft's SHA256; files that do not match are deleted.
- Changes apply to installations made from the new ISO. Removed apps can be reinstalled from the Microsoft Store.

## Credits
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) (MIT): app list and safety ratings.
- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) and
  [farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows) (MIT): privacy tweaks and presets.
- [ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder): ideas only; no code was taken.
- [pbatard/Fido](https://github.com/pbatard/Fido) (GPL-3.0): documentation of the Microsoft download flow; no code was taken.
- [aria2](https://aria2.github.io/) (GPL-2.0-or-later): bundled unmodified in `tools/aria2/`
  (see [`NOTICE.txt`](tools/aria2/NOTICE.txt) and [`COPYING`](tools/aria2/COPYING)).
- [massgrave.dev](https://massgrave.dev/genuine-installation-media): list of original Microsoft files for the optional mirror.
- Icons were drawn for this project in a style inspired by Material 3 Expressive; they are not the Windows logo.

Windows, DISM and the Windows ADK are Microsoft products. Nothing from Microsoft is redistributed here.

## License
[MIT](LICENSE) Copyright (c) 2026 TaiNT13@PNC STG & WinDebloat Tool contributors. aria2 in `tools/aria2/` keeps its own license (GPL-2.0).

---

<p align="center"><sub>Designed by TaiNT13@PNC STG</sub></p>

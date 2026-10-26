<p align="center">
  <img src="assets/icon-256.png" alt="WinDebloat Tool" width="128">
</p>

<h1 align="center">WinDebloat Tool</h1>

<p align="center">
  Turn an official Windows 10 or Windows 11 ISO into a clean, debloated installation ISO.
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

WinDebloat Tool removes preinstalled apps and turns off ads, suggestions and auto-installs **inside the
installation image**, so every PC you set up from the ISO starts clean. It runs on Windows, has a GUI and a
console mode, and only uses Microsoft tools (DISM, reg.exe, oscdimg). The one bundled third-party program is
aria2, used for fast ISO downloads.

## Contents
- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Using the GUI](#using-the-gui)
- [Console mode](#console-mode)
- [Supported Windows versions](#supported-windows-versions)
- [What gets changed](#what-gets-changed)
- [Download sources](#download-sources)
- [Languages](#languages)
- [FAQ and troubleshooting](#faq-and-troubleshooting)
- [Safety notes](#safety-notes)
- [Credits](#credits)
- [License](#license)

## Features
- **Windows 10 and Windows 11:** the target OS and release are detected from the image build, and the
  matching app and tweak profile is chosen. You can also pick it by hand.
- **Built-in ISO download from Microsoft:** every Windows 11 (21H2 – 26H2) and Windows 10 (1507 – 22H2)
  release Microsoft still serves, in every language and architecture offered. Downloads use aria2 with
  16 connections and can be resumed. The SHA256 is checked when Microsoft publishes one.
- **App removal:** a checklist of provisioned apps (Clipchamp, Teams, Outlook (new), Copilot, Xbox, News,
  Weather, Solitaire, Phone Link and more). Safe defaults, optional extras, and risky packages marked
  *unsafe* and left unchecked.
- **Registry tweaks applied offline:** consumer features, Copilot, the Widgets feed, Teams/Chat
  auto-install, new-user suggestions and the OOBE auto-install tasks are turned off. On Windows 10 it also
  turns off Cortana and web search, sets telemetry to the minimum and hides News and Interests.
- **Edition choice:** keep all editions, only Home and Pro, or a list of index numbers.
- **autounattend.xml (optional):** lets you create a local account and skips the Microsoft account
  screens. Disk, edition and region stay interactive.
- **Size options:** normal LZX compression (`install.wim`) or ESD compression (`install.esd`, the smallest
  ISO). An `install.wim` over 4 GB can be split for FAT32 USB sticks. Optional WinSxS component cleanup.
- **Bootable result:** a BIOS + UEFI ISO built with oscdimg, plus its SHA256 file. The **Install oscdimg**
  button installs only the Deployment Tools of the official Windows ADK.
- **Safe work folder handling:** temporary files never end up in the ISO. The work folder is always cleaned
  up after a finished, failed or cancelled run. A leftover from an earlier run is detected and cleaned, and
  a folder with someone else's files is never deleted.
- **Clear logs:** every step is written to a log file, with image and ISO sizes and a warning if the output
  is much larger than the source.
- **Interface in 4 languages:** Vietnamese, English, Simplified Chinese and Khmer.

## Requirements
| | |
|---|---|
| Operating system | Windows 7 SP1 or newer (Windows 10 / 11 recommended) |
| PowerShell | 2.0 or newer (included with Windows) |
| Rights | Administrator (`run.bat` asks for it automatically) |
| oscdimg | From the Windows ADK *Deployment Tools*. Click **Install oscdimg** in the app, or copy `oscdimg.exe` into `tools\` |
| Free space | About 25 GB on the drive of the output folder (the work folder is created there) |
| Internet | Only for downloading an ISO; building from a local ISO works offline |

## Quick start
1. Download `WinDebloatTool_v1.0.0.zip` and extract it to a folder.
2. Unblock the files once: right-click the zip → **Properties** → tick **Unblock** *before* extracting.
   Or, after extracting, run in PowerShell 3.0 or newer:
   `Get-ChildItem -Recurse 'C:\path\to\WinDebloatTool' | Unblock-File`
3. Double-click **`run.bat`** and accept the administrator prompt. You can also run
   `WinDebloatTool.ps1` from an elevated PowerShell.
4. Choose a source ISO, check the apps and options, then click **START**.
5. Write the finished ISO to a USB stick with **Rufus** or **Ventoy**, or use it in a virtual machine.

A build takes about 20–60 minutes. The output folder then contains the ISO, `<name>.iso.sha256`, a
`WinDebloat_<time>.log` file and `kept_indexN.txt`, the list of apps left in each edition.

## Using the GUI
**1. Source ISO**
- **Local ISO file:** click *Browse...* and pick an ISO you already have.
- **Download the official ISO from Microsoft:** choose the version and architecture, click *Load languages*,
  pick a language, then *Download*. The ISO is saved to the folder you choose, and its path is filled in.
- **Target OS:** *Auto (detect)* reads the build from the image and shows it, for example
  *Windows 11 24H2 (26100)*. You can force Windows 10 or Windows 11.

**2. Apps to remove**: the list matches the detected release. *Defaults*, *All* and *None* change the
selection quickly. Apps that are not in the image are skipped and logged.

**3. Options**
- **Editions:** *All*, *Home + Pro*, or *Index:* with numbers such as `1,6`. *List the editions in the ISO*
  shows the numbers.
- **Registry tweaks:** check the tweaks you want (see [What gets changed](#what-gets-changed)).
- **autounattend.xml:** local account, skips the Microsoft account screens (BypassNRO on Windows 11 only).
- **Component cleanup (slow):** runs `DISM /Cleanup-Image /StartComponentCleanup` on every edition.
- **ESD compression:** writes `install.esd`, the smallest ISO, but the build takes much longer.
- **Dry run:** shows what would be done without changing anything.

**4. Output ISO**: the file to create. If you leave it empty, `<source>_debloated.iso` is created next to
the source.

Bottom row: **System check** reports Windows, PowerShell, .NET, TLS 1.2, DISM, oscdimg and free space.
**Install oscdimg** installs the ADK Deployment Tools. **START** and **Cancel** control the build, and
*Open the log folder* opens the logs.

## Console mode
```bat
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_lite.iso -Edition HomePro
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_small.iso -Compression Recovery
run.bat -NoGui -IsoPath D:\Win10_22H2_English_x64v1.iso -OutputIso D:\Win10_lite.iso -TargetOs Win10
run.bat -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf     # dry run
run.bat -Check                                                 # system check only
```

| Parameter | Description |
|---|---|
| `-IsoPath <file>` | Source ISO (giving it starts console mode) |
| `-OutputIso <file>` | ISO to create |
| `-NoGui` | Console mode |
| `-Edition All\|HomePro\|Custom` | Editions to keep (default `All`) |
| `-Indexes 1,6` | Index numbers for `-Edition Custom` |
| `-TargetOs Auto\|Win10\|Win11` | Profile to use (default `Auto`, detected from the image) |
| `-NoAutounattend` | Do not add `autounattend.xml` |
| `-ComponentCleanup` | Run WinSxS component cleanup on every edition |
| `-Compression Max\|Recovery` | `Max` = LZX `install.wim` (default); `Recovery` = `install.esd`, smallest, slower |
| `-SplitWimMB <MB>` | Split an `install.wim` over 4 GB into `install*.swm` parts, e.g. `3800` for FAT32 USB |
| `-WorkDir <folder>` | Work folder (default `<output folder>\WinDebloat_work`) |
| `-KeepWorkDir` | Keep the work folder after the build |
| `-MinFreeGB <n>` | Minimum free space required (default `25`) |
| `-OscdimgPath <file>` | Path to `oscdimg.exe` if it is not found automatically |
| `-DryRun` / `-WhatIf` | Show the plan, change nothing |
| `-Check` | System check only |

`Win11DebloatTool.ps1` is an alias of `WinDebloatTool.ps1` with the same parameters.

## Supported Windows versions
**Images (what you can debloat)**

| Windows | Releases (build) |
|---|---|
| Windows 11 | 21H2 (22000), 22H2 (22621), 23H2 (22631), 24H2 (26100), 25H2 (26200), 26H2 (26300) – x64 and ARM64 |
| Windows 10 | 1507 (10240) to 22H2 (19045) – x64 and x86 |

Build 22000 and newer uses the Windows 11 profile; builds 10240–21999 use the Windows 10 profile.
Entries in the config can be limited to a build range, so each release only shows the apps it contains.

**Host (the PC that runs the tool)**

| Host | Notes |
|---|---|
| Windows 10 / 11 | Recommended. System or ADK DISM, ISO mounting built in, oscdimg installs from the app. |
| Windows 8 / 8.1 | Uses the DISM inside the ISO. Copy `oscdimg.exe` into `tools\` (the current ADK does not install). |
| Windows 7 SP1 | Needs 7-Zip (to open the ISO) and `oscdimg.exe` in `tools\`. Downloads need TLS 1.2 (KB3140245, .NET 4.5.2+; WMF 5.1 recommended). |

## What gets changed
**Windows 11 – removed by default:** Clipchamp, Teams (new), Outlook (new), News, Bing Search, Weather,
Xbox app, Xbox Game Bar, Solitaire, Microsoft 365 hub, Power Automate, To Do, Dev Home, Feedback Hub,
Phone Link, Cross Device, Quick Assist, Copilot, Microsoft Family, Tips. On older builds it also removes
Cortana, Maps, People, the Copilot provider and Teams (consumer).
**Optional:** Widgets, Media Player, Movies & TV, Camera, Clock, Sound Recorder, Sticky Notes,
Mail & Calendar.

**Windows 10 – removed by default:** 3D Builder, 3D Viewer, Print 3D, Mixed Reality Portal, People, Skype,
Mobile Plans, Wallet, Messaging, Weather, News, Tips, Office hub, OneNote for Windows 10, Solitaire, Xbox
Console Companion, Xbox Game Bar / Overlay, Your Phone, Feedback Hub, Cortana. If present, it also removes
Clipchamp, Teams, To Do, Power Automate, Outlook (new), Copilot and Microsoft Family.
**Optional:** Groove Music, Movies & TV, Maps, Paint 3D, Mail & Calendar, Camera, Alarms & Clock,
Voice Recorder, Sticky Notes.

**Always kept:** Microsoft Store, Windows Security, Edge, WebView2, Calculator, Photos, Notepad, Terminal,
Snipping Tool, Paint, media codecs, runtimes (VCLibs, .NET Native, UI.Xaml, Windows App Runtime) and
App Installer (winget).

**Registry tweaks – Windows 11**

| Tweak | Keys |
|---|---|
| Consumer features off | `Policies\Microsoft\Windows\CloudContent` DisableWindowsConsumerFeatures, DisableConsumerAccountStateContent, DisableCloudOptimizedContent = 1 |
| Copilot off | `Policies\Microsoft\Windows\WindowsCopilot` TurnOffWindowsCopilot = 1 (machine and default user) |
| Widgets news feed off | `Policies\Microsoft\Windows\Windows Feeds` EnableFeeds = 0 |
| Teams/Chat auto-install off | `CurrentVersion\Communications` ConfigureChatAutoInstall = 0 |
| BypassNRO | `CurrentVersion\OOBE` BypassNRO = 1 |
| New-user suggestions off | default user `ContentDeliveryManager` values = 0, Start_IrisRecommendations = 0 |
| Chat button off | default user `Explorer\Advanced` TaskbarMn = 0 |
| OOBE install tasks removed | `WindowsUpdate\Orchestrator\UScheduler_Oobe\{OutlookUpdate, DevHomeUpdate, CrossDeviceUpdate}` |

**Registry tweaks – Windows 10**

| Tweak | Keys |
|---|---|
| Consumer features off | `Policies\Microsoft\Windows\CloudContent` DisableWindowsConsumerFeatures, DisableSoftLanding, DisableCloudOptimizedContent = 1 |
| New-user suggestions off | default user `ContentDeliveryManager` (SilentInstalledAppsEnabled, PreInstalledAppsEnabled, SubscribedContent-*) = 0 |
| Cortana and web search off | `Policies\Microsoft\Windows\Windows Search` AllowCortana = 0, DisableWebSearch = 1, ConnectedSearchUseWeb = 0; default user BingSearchEnabled = 0, CortanaConsent = 0 |
| Telemetry minimum | `Policies\Microsoft\Windows\DataCollection` AllowTelemetry = 0 (Home/Pro: *Required*), DoNotShowFeedbackNotifications = 1 |
| News and Interests off | `Policies\Microsoft\Windows\Windows Feeds` EnableFeeds = 0 |
| Meet Now / People off | `Policies\Explorer` HideSCAMeetNow = 1, PeopleBand = 0 |
| Copilot off | as on Windows 11 |
| OOBE install tasks removed | `UScheduler_Oobe\{OutlookUpdate, DevHomeUpdate}` if present |
| OneDrive setup off (optional) | removes default user `Run\OneDriveSetup` |

**autounattend.xml** (added to the ISO root, optional): accepts the license and hides the Microsoft account
pages so you can create a local account. On Windows 11 it also sets BypassNRO during setup. The setup
language and architecture are set to match the image.

All lists live in [`config/DebloatConfig.psd1`](config/DebloatConfig.psd1) (`Apps` / `Tweaks` for
Windows 11, `Win10Apps` / `Win10Tweaks` for Windows 10, `Protected` for both). Wildcards are allowed.

**How a build works:** mount or extract the ISO → copy it to the work folder → for each kept edition:
`DISM /Mount-Image` → remove apps → load the offline Registry hives and apply tweaks → optional component
cleanup → `/Unmount-Image /Commit` → export every kept edition into a new `install.wim` / `install.esd`
→ add `autounattend.xml` → `oscdimg` (BIOS + UEFI) → SHA256.

## Download sources
1. **Microsoft (always first).** The tool uses the same download service as Microsoft's website. Links are
   valid for about 24 hours. It uses aria2 when the *Use aria2* box is ticked, and falls back to the
   built-in downloader automatically.
2. **Mirror (opt-in, only when Microsoft cannot deliver).** If the download is refused, the release is
   withdrawn or the link fails, the tool can offer a copy of the original Microsoft file from the list on
   [massgrave.dev](https://massgrave.dev/genuine-installation-media). A dialog names the file, the host
   (not a Microsoft server) and the expected SHA256, and nothing happens unless you click *Yes*. The file is
   accepted only if its **SHA256 matches the original Microsoft file**; otherwise it is deleted. Mirrors are
   listed in the `Mirrors` section of `config/DebloatConfig.psd1`, and an entry without a valid SHA256 is
   never offered.

## Languages
The interface comes in **Tiếng Việt** (default), **English**, **简体中文** and **ភាសាខ្មែរ**. Switch it
with the box at the bottom right; the choice is remembered. Texts are in `lang/*.psd1`, and corrections
are welcome (keep the `{0}` placeholders). The log file is written in English and Vietnamese.

## FAQ and troubleshooting
**The output ISO is larger than I expected.**
Each edition you keep stores its own changed files, so keeping *All* editions (around 10 on current media)
makes the image grow. Keep only the editions you need (for example *Home + Pro*) and/or tick **ESD
compression**. The log shows `SIZE ...` lines for each step and lists the largest files if the ISO ends up
more than 500 MB larger than the source.

**A work folder from an earlier run is still there.**
It is detected and cleaned automatically: offline hives are unloaded, mounted images are discarded and the
folder is deleted. If the folder contains files that were not created by the tool, nothing is deleted. The
GUI offers a new folder (for example `D:\WinDebloat_work_2`), and the console picks one by itself.

**The download is refused (error 715-123130 or "Sentinel").**
Microsoft blocks automated downloads for some IP addresses, regions and VPNs. Turn off the VPN, try another
DNS (1.1.1.1 or 8.8.8.8) or network, or click *Open the Microsoft page* and download in the browser. Then
choose the file with *Browse...*. The tool can also offer a verified mirror (see
[Download sources](#download-sources)). If *Load languages* fails with "vlscppe.microsoft.com could not be
resolved", an ad blocker, hosts file or DNS filter is blocking Microsoft's download hosts.

**oscdimg.exe is missing.**
Click **Install oscdimg**: it installs only the Deployment Tools of the official Windows ADK (signature
checked, or via winget). Or download the ADK from
<https://learn.microsoft.com/windows-hardware/get-started/adk-install>, or copy `oscdimg.exe` into
`tools\`, or pass `-OscdimgPath`.

**The USB stick does not boot or copying fails.**
`install.wim` is usually larger than 4 GB. Use Rufus or Ventoy, or build with `-SplitWimMB 3800` (or ESD
compression) for a plain FAT32 copy.

**Where are the logs?**
In the GUI, click *Open the log folder* (`logs\` in the tool folder). Each build also writes
`WinDebloat_<time>.log` next to the output ISO. Please attach these files when you report a problem.

## Safety notes
- Removal happens **inside the image** and is permanent for installations made from that ISO. Removed apps
  can be reinstalled from the Microsoft Store.
- Packages that other features depend on (Xbox TCUI, Xbox Identity Provider, Xbox Speech-to-text, Get Help)
  are marked **unsafe** and are never removed by default. Removing the Xbox components breaks Xbox / Game
  Pass sign-in and Game Bar.
- Core components (Store, Windows Security, Edge, WebView2, runtimes, codecs, App Installer) are protected
  and cannot be removed through the lists.
- Windows 11 hardware checks (TPM 2.0, Secure Boot, CPU) are **not** bypassed.
- Feature updates may bring some apps back; the policies reduce this but cannot prevent it completely.
- The tool never runs anything it downloads. Your source ISO is never modified.

## Credits
- **[Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)** (MIT): its app list and safe /
  optional / unsafe ratings were the main reference for the removal lists.
- **[pbatard/Fido](https://github.com/pbatard/Fido)** (GPL-3.0): documented the Microsoft ISO download flow;
  this project implements it independently and contains no Fido code.
- **[aria2](https://aria2.github.io/)** (GPL-2.0-or-later): bundled unmodified in `tools/aria2/` and run as
  a separate program. See [`tools/aria2/NOTICE.txt`](tools/aria2/NOTICE.txt) for its source, hashes and
  license ([`COPYING`](tools/aria2/COPYING)).
- **[massgrave.dev](https://massgrave.dev/genuine-installation-media)**: the list of original Microsoft
  files used for the optional mirror fallback.
- The app and button icons were drawn for this project (SVG sources in `assets/`). The icon is not the
  Microsoft Windows logo.

Windows, DISM and the Windows ADK are Microsoft products. Nothing from Microsoft is redistributed here.

## License
[MIT](LICENSE) © 2026 WinDebloat Tool contributors. aria2 in `tools/aria2/` keeps its own license (GPL-2.0).

---

<p align="center"><sub>Designed by TaiNT13@PNC STG</sub></p>

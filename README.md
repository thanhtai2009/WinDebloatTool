# WinDebloat Tool (Windows 10 / 11)

Turn an **official Windows 10 or Windows 11 ISO** into a **debloated ISO** – on Windows, with a GUI, using
Microsoft tools (DISM, reg.exe, oscdimg from the Windows ADK). The only third-party program is the bundled
**aria2** (GPLv2, unmodified) used for faster multi-connection ISO downloads – see *Third-party*.

> Vietnamese guide: [README_VI.md](README_VI.md)
>
> Formerly *Win11 Debloat Tool*. Since 0.2.0 the main script is `WinDebloatTool.ps1`;
> `Win11DebloatTool.ps1` remains as a wrapper and `run.bat` accepts the same parameters as before.

> **Status: early.** 0.3.3 adds the bottom watermark; 0.3.2 fixed the first real-Windows report (a crash on an empty path field).
> The code was written and statically checked on Linux
> (PowerShell 7 parser, PSScriptAnalyzer, a custom PowerShell 2.0 compatibility scan, offline unit
> tests with mocked dism/reg). The same removals and tweaks were applied to a real
> Windows 11 ISO on Linux (wimlib + hivex); that ISO booted into Windows Setup in a QEMU VM
> (UEFI + Secure Boot), but a full installation was not tested. This Windows
> tool reproduces that process with Microsoft tools. **The Windows 10 profile has not been applied to a
> real Windows 10 image at all yet** (only unit-tested). The GUI has had one real run (Windows 11, PowerShell 5.1); please keep reporting problems.

## Quick start
1. Download/extract the zip, double-click **`run.bat`** (accept the UAC prompt).
2. **Source**: *Browse…* to an ISO you already have, **or** choose a release (every Windows 11 21H2…26H2
   and Windows 10 1507…22H2 build Microsoft still serves) / arch → *Languages* → language → *Download*
   (straight from Microsoft, with aria2 16 connections if enabled, SHA256 checked).
   **Target OS** is detected automatically (see below); you can force Windows 10 / Windows 11.
3. Choose apps, tweaks, editions (All / Home+Pro / index list) and the output path.
4. **START**. Takes 20–60 min and needs about **25 GB** free. The output folder gets
   `*.iso`, `*.iso.sha256`, a log file and `kept_indexN.txt` (apps left in each edition).
5. Write the ISO to USB with **Rufus** or **Ventoy** (install.wim is > 4 GB; plain FAT32 copying fails).

*Download* only asks for a folder (last used one, else `%USERPROFILE%\Downloads`); it does not need the
output field. If the output field is empty, START uses `<source>_debloated.iso` next to the source.
Empty or wrong paths give a short message instead of an error. **Install oscdimg** installs only the
*Deployment Tools* of the official Windows ADK (`adksetup.exe /features OptionId.DeploymentTools /quiet`,
signature checked, or winget); manual download:
<https://learn.microsoft.com/windows-hardware/get-started/adk-install>. START checks for oscdimg too.

### Interface language
Vietnamese (default), English, 简体中文 and ភាសាខ្មែរ – the box next to *Open the log folder* switches at once
and the choice is saved in `settings.psd1` (tool folder, else `%APPDATA%\WinDebloatTool`). Texts live in
`lang\*.psd1` (UTF-8 with BOM, one key per line). Fonts: Segoe UI; Chinese uses Microsoft YaHei UI →
Microsoft YaHei; Khmer uses Leelawadee UI (Windows 8+) → Khmer UI (Windows 7) → DaunPenh. The log
window shows English (plus Vietnamese when the UI is Vietnamese); the log file keeps both.
**The Chinese and Khmer texts are machine-assisted** – corrections by native speakers are very welcome
(edit `lang\zh-CN.psd1` / `lang\km.psd1`, keep the `{0}` placeholders; `tests/Test-Offline.ps1` checks
that every key and placeholder is present).

Console mode:
```
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_lite.iso -Edition HomePro
run.bat -NoGui -IsoPath D:\Win10_22H2_English_x64v1.iso -OutputIso D:\Win10_lite.iso
run.bat -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf      # dry run
run.bat -Check                                                  # system report
```
Parameters: `-TargetOs Auto|Win10|Win11`, `-Edition All|HomePro|Custom -Indexes 1,6`, `-NoAutounattend`, `-ComponentCleanup`,
`-DryRun`/`-WhatIf`, `-WorkDir`, `-KeepWorkDir`, `-MinFreeGB`, `-OscdimgPath`.

## Downloading from Microsoft
- **Releases:** the picker lists every release Microsoft's download API serves (edition IDs as used by
  [Fido](https://github.com/pbatard/Fido)). Checked live on 2026-10-25: all of them returned a language
  list and a link – Windows 11 26H2, 25H2 (+v2), 24H2 (x64 + ARM64); 23H2 (+v2), 22H2 v1 + v2, 21H2 (+v1)
  (x64); Windows 10 22H2 (+v1), 21H2, 21H1, 20H2 (+v2), 2004, 1909, 1903 (+v2), 1809 (+v2), 1803, 1709,
  1703, 1607, 1511, 1507 (x64 + x86). The original Windows 11 22H2 ISO (edition 2360, build 22621.382) is
  marked "no longer offered": Microsoft still returns a link but its CDN answers HTTP 400.
  `SentinelReject` is often random and is retried with a new session; error 715-123130 (Type 9: IP, region
  or VPN blocked) is not retried. If Microsoft withdraws one, *Languages* marks it
  "no longer offered – use a local ISO". Microsoft publishes SHA256 values only for the current releases;
  for older ones the hash is logged for manual comparison.
- **aria2** (`tools\aria2\x64|x86\aria2c.exe`, bundled; also `tools\aria2c.exe`, next to the script, or PATH):
  `-x16 -s16 -k1M`, `--continue`, certificate check on, retries; options in the `Download` section of
  `config\DebloatConfig.psd1`. Checkbox *Use aria2 (multi-connection)*; speed and connections show in the
  status line; *Cancel* kills aria2c (the `.aria2` file stays, so *Download* again resumes).
  On any aria2 error (e.g. HTTP 403) the tool logs a warning and falls back to the built-in single-connection
  downloader (HttpWebRequest, `.partial` resume).
- **Windows 7:** aria2 1.37 uses Windows' own TLS (schannel). Without TLS 1.2 updates (KB3140245) it fails and
  the tool falls back automatically (not tested on Windows 7).

## Mirror fallback (not Microsoft, opt-in)
Microsoft is always tried first. Only when Microsoft cannot deliver (release withdrawn, *Sentinel* /
715-123130 block, CDN or download error) does the error message offer: **Yes = try a copy of the original
Microsoft file listed on [massgrave.dev](https://massgrave.dev/genuine-installation-media)**, No = open the
Microsoft page, Cancel = close.
- A second dialog names the exact file, the download host and the expected SHA256, and says plainly that
  the host is **not a Microsoft server**. Nothing happens without *Yes*. The host is written to the log.
- File hosts (buzzheavier.com, zerofs.link) only serve a download page, so the tool opens it in the
  browser. After downloading, choose the file in the dialog that opens.
- **SHA256 check is mandatory.** The file is accepted only if its SHA256 equals the hash of the original
  Microsoft (MSDN) file. On a mismatch it is **deleted** and the tool reports both hashes. The tool never
  runs anything it downloads; the ISO is only read by DISM in the normal build.
- Included (English US only; 10 entries in `Mirrors` in `config\DebloatConfig.psd1`): Windows 11 26H2
  consumer / business x64, Windows 10 22H2 (Oct 2025) consumer / business x64 + x86, Windows 11
  Enterprise LTSC 2024 and IoT Enterprise LTSC 2024 x64, Windows 10 Enterprise LTSC 2021 x64 + x86.
  massgrave.dev's link pages publish no hashes, so each SHA256 was taken from two independent hash lists
  (msnews.ru, and ntriver.org / macrohard0.github.io) that agree (2026-10-25). The 26H2 consumer hash also
  equals the value Microsoft publishes. Files with no confirmed hash were left out.
- To add one: copy an entry and set `FileName`, `Url`, `Sha256` (the original Microsoft hash), `Os`,
  `Arch`, `Release` and `Kind`. Entries without a valid 64-character SHA256 are never offered.

## Windows 10 or Windows 11? (target OS detection)
The engine reads the build of each image with DISM: **10240–21999 = Windows 10** (22H2 is 19045),
**22000+ = Windows 11**, and picks the matching profile from `config\DebloatConfig.psd1`.
The GUI shows the guess immediately (file name, then the WIM header read from the mounted ISO on
Windows 8+, or the version you downloaded) and fills the app/tweak lists for that OS. On Windows 7
(no ISO mounting) it uses the file name; if that says nothing, the engine still detects the OS from
the image and uses that profile's defaults. The *Target OS* box (`-TargetOs`) overrides detection;
a mismatch is logged as a warning.

**Version-aware profile:** the build also selects the release (10240=1507 … 19045=22H2; 22000=21H2,
22621=22H2, 22631=23H2, 26100=24H2, 26200=25H2, 26300+=26H2). Entries in `DebloatConfig.psd1` may carry
`MinBuild` / `MaxBuild`; the GUI shows e.g. *Windows 11 24H2 (26100)* and only the entries for that build
(e.g. no Cortana on 24H2, no Clipchamp/Outlook on 21H2). Listed apps that are not in the image are skipped
and logged.

## What it changes – Windows 11
**Removed (provisioned apps, default):** Clipchamp, Teams (new), Outlook (new), News, Bing Search,
Weather, Xbox app, Game Bar,
Solitaire, Microsoft 365 hub, Power Automate, To Do, Dev Home, Feedback Hub,
Phone Link, Cross Device, Quick Assist, Copilot, Family; on older builds also Cortana, Maps, People,
Tips, Copilot provider, old Teams. Optional (unchecked): Widgets, Media Player, Movies & TV, Camera,
Clock, Sound Recorder, Sticky Notes, Mail & Calendar, and – marked *unsafe*, because games, Store
dialogs, game sign-in or troubleshooters depend on them – Xbox TCUI, Xbox Identity Provider,
Xbox Speech-to-text overlay, Get Help (removed by default up to 0.3.0).

**Always kept:** Store, Defender/Security, Edge, WebView2, Calculator, Photos, Notepad, Terminal,
Snipping Tool, Paint, codecs, runtimes, App Installer (winget). Everything removed can be reinstalled
from the Store.

**Registry (offline, inside the image):**
| Tweak | Keys |
|---|---|
| Consumer features off | `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent` DisableWindowsConsumerFeatures / DisableConsumerAccountStateContent / DisableCloudOptimizedContent = 1 |
| Copilot off | `...\Policies\Microsoft\Windows\WindowsCopilot` TurnOffWindowsCopilot = 1 (machine + default user) |
| Widgets news off | `...\Policies\Microsoft\Windows\Windows Feeds` EnableFeeds = 0 |
| Teams/Chat auto-install off | `...\CurrentVersion\Communications` ConfigureChatAutoInstall = 0 |
| BypassNRO | `...\CurrentVersion\OOBE` BypassNRO = 1 |
| New-user suggestions off | default user `ContentDeliveryManager` (18 values) = 0, Start_IrisRecommendations = 0 |
| Chat taskbar button off | default user `Explorer\Advanced` TaskbarMn = 0 |
| OOBE install tasks removed | `WindowsUpdate\Orchestrator\UScheduler_Oobe\{OutlookUpdate,DevHomeUpdate,CrossDeviceUpdate}` |

**autounattend.xml** (ISO root): accepts the EULA, hides the Microsoft-account screens so you can
create a **local account**, sets BypassNRO again during setup. Disk, edition, product key, region
and account name stay interactive. The tool rewrites the setup UI language and architecture to match
the ISO.

## What it changes – Windows 10 (22H2)
**Removed (default):** 3D Builder, 3D Viewer, Print 3D, Mixed Reality Portal, People, Skype, Mobile Plans
(OneConnect), Wallet, Messaging, Weather, News, Tips (Getstarted), Office hub, OneNote (Store
app), Solitaire, Xbox app / Game Bar (Xbox TCUI / Identity Provider / Speech-to-text and Get Help are
listed as *unsafe*, unchecked),
Your Phone, Feedback Hub, **Cortana**, and – if present in newer refreshes – Clipchamp, Teams,
To Do, Power Automate, Outlook (new), Copilot, Family.
Optional (unchecked): Groove Music, Movies & TV, Maps, Paint 3D, Mail & Calendar, Camera, Alarms & Clock,
Voice Recorder, Sticky Notes.

**Always kept:** Store (+ purchase app), Defender/Security, Edge, Calculator, Photos, Snip & Sketch,
Notepad/Terminal if present, classic Paint, image/video codecs (HEIF, WebP, VP9, …), VCLibs/.NET Native/UI.Xaml
runtimes, App Installer. Everything removed can be reinstalled from the Store.

**Registry:**
| Tweak | Keys |
|---|---|
| Consumer features off | `Policies\Microsoft\Windows\CloudContent` DisableWindowsConsumerFeatures / DisableSoftLanding / DisableCloudOptimizedContent = 1 |
| New-user suggestions / silent app installs off | default user `ContentDeliveryManager` (SilentInstalledAppsEnabled, PreInstalledAppsEnabled, SubscribedContent-*, …) = 0 |
| Cortana & web search off | `Policies\Microsoft\Windows\Windows Search` AllowCortana = 0, DisableWebSearch = 1, ConnectedSearchUseWeb = 0; default user BingSearchEnabled = 0, CortanaConsent = 0, DisableSearchBoxSuggestions = 1 |
| Telemetry minimum | `Policies\Microsoft\Windows\DataCollection` AllowTelemetry = 0, DoNotShowFeedbackNotifications = 1; AdvertisingInfo DisabledByGroupPolicy = 1. *Home/Pro treat 0 as "Required (Basic)"; only Enterprise/Education honour "Security".* |
| News and Interests off | `Policies\Microsoft\Windows\Windows Feeds` EnableFeeds = 0; default user `Feeds` ShellFeedsTaskbarViewMode = 2 |
| Meet Now off | `Policies\Explorer` HideSCAMeetNow = 1 (machine + default user); People band off |
| Copilot off | as Windows 11 (only matters on late 22H2 builds) |
| OOBE install tasks removed | `UScheduler_Oobe\{OutlookUpdate,DevHomeUpdate}` if present |
| OneDrive setup off (optional, unchecked) | deletes default user `Run\OneDriveSetup`, so new accounts do not get OneDrive installed |

No TPM/Secure Boot changes (not needed for Windows 10). **autounattend.xml** is the same file, but the
tool removes the Windows 11-only BypassNRO command for Windows 10 images (Windows 10 Setup already offers
"Offline account" / "Limited experience" without a network).

Edit `config\DebloatConfig.psd1` to change app/tweak lists (wildcards allowed): `Apps` / `Tweaks` are
the Windows 11 profile, `Win10Apps` / `Win10Tweaks` the Windows 10 profile; `Protected` applies to both.

## Caveats
- **TPM 2.0 / Secure Boot / CPU checks are NOT bypassed** (Windows 11). Unsupported PCs still get blocked.
- Windows 10 support from Microsoft ended on 2025-10-14 (security updates only via ESU). The ISO is still offered.
- Removing the Xbox components breaks **Xbox / Game Pass sign-in** and Game Bar until you reinstall
  them from the Store.
- Copilot/Outlook/Teams may come back with feature updates; the policies reduce but do not
  guarantee that.
- Microsoft may block the in-app download (VPN, region, too many requests – message 715-123130).
  Use *Open Microsoft page*, download in the browser, then *Browse*.
- Download links expire after ~24 h.
- Use a local NTFS drive for the work folder (not a network share).

## Troubleshooting
- **Log file:** the GUI writes `logs\WinDebloat_gui_<date>_<time>.log` in the tool folder (or `%TEMP%`
  if the folder is not writable); the link *Open the log folder* in the window opens it. A build also writes
  `WinDebloat_<time>.log` next to the output ISO. Send these files when reporting a problem.
- **"Languages" fails / "remote name could not be resolved: vlscppe.microsoft.com"**: your DNS, ad
  blocker, hosts file or ISP blocks Microsoft's download-protection hosts `vlscppe.microsoft.com` and
  `ov-df.microsoft.com`. Since 0.2.1 the list still loads; if the download link is then rejected
  (*Sentinel* / 715-123130), switch DNS to 1.1.1.1 or 8.8.8.8 (or unblock the two hosts), turn off
  VPN, or use *Open Microsoft page* and download in the browser.
- If nothing loads at all, the version list still shows Windows 11 / Windows 10; *Download* then opens
  the official page.

## Requirements & Windows version support
| Host | Status |
|---|---|
| Windows 10 / 11 | **Primary target.** System DISM or ADK DISM; Mount-DiskImage; oscdimg via ADK (the tool offers to install *Deployment Tools* only, from Microsoft, signature checked; or winget). |
| Windows 8 / 8.1 | Experimental. ISO mounting works; Windows 8.x DISM cannot service Windows 11, so the ISO's own `sources\dism.exe` is used (no Appx provider → apps removed with the registry/folder method used by the reference build). The current ADK does not install → copy `oscdimg.exe` into `tools\`. |
| Windows 7 SP1 | Experimental, least tested. PowerShell 2.0 is supported by the code. Needs **7-Zip** (no ISO mounting in Win7), `oscdimg.exe` copied into `tools\` (the last ADK that installs on Win7 is the 8.1 ADK, which Microsoft no longer offers), and the ISO's DISM, which may not work with Win7's WIM mount driver. For downloading: TLS 1.2 support (KB3140245 + .NET 4.5.2+, or KB3154518 for .NET 3.5.1; WMF 5.1 recommended). Honest recommendation: **do the build on a Windows 10/11 PC**. |

The startup **System check** (button or `-Check`) reports Windows/PowerShell/.NET versions, TLS 1.2,
DISM versions, oscdimg, ISO access method and free space, with what to do in English and Vietnamese.

## How it works
1. Check admin, free space, oscdimg, DISM.
2. Mount the ISO (Win8+) or extract it with 7-Zip (Win7); copy it to a work folder.
3. `install.esd` → `install.wim` (`dism /Export-Image /Compress:max`) if needed.
4. For each selected edition: `dism /Mount-Image` → `/Remove-ProvisionedAppxPackage` →
   `reg load` SOFTWARE + Default\NTUSER.DAT → tweaks → `reg unload` → optional
   `/Cleanup-Image /StartComponentCleanup` → `/Unmount-Image /Commit`.
5. `dism /Export-Image /Compress:max` of the kept editions (recompress, drops unselected ones).
6. Add autounattend.xml, `oscdimg -m -o -u2 -udfver102 -bootdata:2#p0,e,b<etfsboot.com>#pEF,e,b<efisys.bin>`.
7. SHA256 of the result.
`try/finally` always unloads the hives, discards a mounted image on errors, and unmounts the ISO.

## Development
```
pwsh -File tests/Test-Parse.ps1       # parser check of every file + config + XML
pwsh -File tests/Test-PS2Compat.ps1   # PowerShell 2.0 compatibility scan
pwsh -File tests/Test-Offline.ps1     # unit tests with mocked dism/reg/web
                                      # (set W11D_REAL_WIM=path\install.wim to also parse a real WIM header)
pwsh -c "Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
```
Layout: `run.bat` (elevating launcher) · `WinDebloatTool.ps1` (entry, CLI; `Win11DebloatTool.ps1` =
compatibility wrapper) · `lib/Core.ps1`
(engine) · `lib/MsDownload.ps1` (Microsoft download) · `lib/Gui.ps1` (WinForms) ·
`config/DebloatConfig.psd1` (lists, download options, mirror list) · `lang/*.psd1` (UI texts) ·
`autounattend.xml`.

## Third-party
- Our code is MIT. `tools\aria2\` contains **aria2 1.37.0** Windows builds (`aria2c.exe`), **GPLv2**,
  distributed unmodified as a separate program that the tool runs as an external process (mere aggregation).
  License, README, AUTHORS, NEWS and `NOTICE.txt` (original URL, SHA256 of zip and exe, link to the
  corresponding source) are in that folder. To update, replace the exe with a newer official build.

## License
MIT (see LICENSE). The Microsoft download flow was documented by the community, notably
[Fido](https://github.com/pbatard/Fido) (GPL-3.0); this project contains an independent
implementation and **no Fido code**, so it stays MIT. Windows, DISM and the ADK are Microsoft
products; nothing of Microsoft is redistributed here.

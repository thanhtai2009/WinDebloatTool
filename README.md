# Win11 Debloat Tool

Turn an **official Windows 11 ISO** into a **debloated ISO** – on Windows, with a GUI, using only
Microsoft tools (DISM, reg.exe, oscdimg from the Windows ADK). No third-party downloads.

> Vietnamese guide: [README_VI.md](README_VI.md)

> **Status: not yet tested on real Windows.** The code was written and statically checked on Linux
> (PowerShell 7 parser, PSScriptAnalyzer, a custom PowerShell 2.0 compatibility scan, offline unit
> tests with mocked dism/reg). The same removals and tweaks were applied to a real
> Windows 11 ISO on Linux (wimlib + hivex); that ISO booted into Windows Setup in a QEMU VM
(UEFI + Secure Boot), but a full installation was not tested. This Windows
> tool reproduces that process with Microsoft tools. Please report problems from a first real run.

## Quick start
1. Download/extract the zip, double-click **`run.bat`** (accept the UAC prompt).
2. **Source**: *Browse…* to an ISO you already have, **or** *Load list* → choose version /
   arch / language → *Download* (straight from Microsoft, SHA256 checked).
3. Choose apps, tweaks, editions (All / Home+Pro / index list) and the output path.
4. **START**. Takes 20–60 min and needs about **25 GB** free. The output folder gets
   `*.iso`, `*.iso.sha256`, a log file and `kept_indexN.txt` (apps left in each edition).
5. Write the ISO to USB with **Rufus** or **Ventoy** (install.wim is > 4 GB; plain FAT32 copying fails).

Console mode:
```
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_lite.iso -Edition HomePro
run.bat -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf      # dry run
run.bat -Check                                                  # system report
```
Parameters: `-Edition All|HomePro|Custom -Indexes 1,6`, `-NoAutounattend`, `-ComponentCleanup`,
`-DryRun`/`-WhatIf`, `-WorkDir`, `-KeepWorkDir`, `-MinFreeGB`, `-OscdimgPath`.

## What it changes
**Removed (provisioned apps, default):** Clipchamp, Teams (new), Outlook (new), News, Bing Search,
Weather, Xbox app, Game Bar, Xbox TCUI, Xbox Identity Provider, Xbox Speech-to-text overlay,
Solitaire, Get Help, Microsoft 365 hub, Power Automate, To Do, Dev Home, Feedback Hub,
Phone Link, Cross Device, Quick Assist, Copilot, Family; on older builds also Cortana, Maps, People,
Tips, Copilot provider, old Teams. Optional (unchecked): Widgets, Media Player, Movies & TV, Camera,
Clock, Sound Recorder, Sticky Notes, Mail & Calendar.

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

Edit `config\DebloatConfig.psd1` to change app/tweak lists (wildcards allowed).

## Caveats
- **TPM 2.0 / Secure Boot / CPU checks are NOT bypassed.** Unsupported PCs still get blocked.
- Removing the Xbox components breaks **Xbox / Game Pass sign-in** and Game Bar until you reinstall
  them from the Store.
- Copilot/Outlook/Teams may come back with feature updates; the policies reduce but do not
  guarantee that.
- Microsoft may block the in-app download (VPN, region, too many requests – message 715-123130).
  Use *Open Microsoft page*, download in the browser, then *Browse*.
- Download links expire after ~24 h.
- Use a local NTFS drive for the work folder (not a network share).

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
pwsh -c "Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
```
Layout: `run.bat` (elevating launcher) · `Win11DebloatTool.ps1` (entry, CLI) · `lib/Core.ps1`
(engine) · `lib/MsDownload.ps1` (Microsoft download) · `lib/Gui.ps1` (WinForms) ·
`config/DebloatConfig.psd1` · `autounattend.xml`.

## License
MIT (see LICENSE). The Microsoft download flow was documented by the community, notably
[Fido](https://github.com/pbatard/Fido) (GPL-3.0); this project contains an independent
implementation and **no Fido code**, so it stays MIT. Windows, DISM and the ADK are Microsoft
products; nothing of Microsoft is redistributed here.

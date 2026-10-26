# Changelog

## 0.3.3 - 2026-10-26
**Watermark.**

- The main window shows *Designed by TaiNT13@PNC STG* at the very bottom (small gray text, right-aligned,
  docked to the bottom edge so it stays visible when the window is resized). Same text in every interface
  language (not translated). The log box ends just above it, so nothing overlaps; its height follows the
  UI font (any DPI / language font) and the colour is the Windows *GrayText* system colour (works with
  any colour scheme / high contrast). Window minimum height +24 px.
- Tests: watermark text, docked bottom, not in the language files.

## 0.3.2 - 2026-10-25
**Fix for the first real-Windows report, interface language selector, optional mirror fallback.**

- **Bug (Windows 11, PowerShell 5.1):** "Cannot bind argument to parameter 'LiteralPath' because it is an
  empty string". *List editions in the ISO* passed the empty source field to `Test-Path -LiteralPath`
  (Windows PowerShell refuses an empty string there). Every path from a text box now goes through
  `Test-W11PathText` (empty / blank / invalid → friendly message, never an exception). Same fix for
  *Save as…*, *System check*, START, the suggested output name and `Get-W11FreeGB`.
- *Download* never depends on the output field: the folder dialog starts in the last used folder, else
  `%USERPROFILE%\Downloads`, else `<tool>\downloads`; the choice is remembered. START fills an empty output
  field with `<source>_debloated.iso` next to the source and checks the output folder (exists, not the
  source file) before it starts.
- **Install oscdimg** button: official Windows ADK *Deployment Tools* only (`adksetup.exe /features
  OptionId.DeploymentTools /quiet`, signature checked, or winget); the ADK link is in the messages and the
  system check. START still checks for oscdimg first.
- **Interface language:** Vietnamese (default), English, Simplified Chinese, Khmer. The old
  "English / Việt" labels are gone. Texts are in `lang\*.psd1` (UTF-8 BOM), switch live, remembered in
  `settings.psd1`. Each language gets a font that can show it (YaHei UI / YaHei; Leelawadee UI / Khmer UI /
  DaunPenh). The log window shows English unless the UI is Vietnamese; the log file is unchanged.
  zh/km are machine-assisted, fixes welcome.
- **Mirror fallback** (opt-in, only after Microsoft fails): 10 English (US) originals listed on
  massgrave.dev (Win11 26H2, Win10 22H2, LTSC 2024 / 2021) in `Mirrors` in the config, each with file name
  and SHA256 confirmed by two independent hash lists. Clear "NOT a Microsoft server" confirmation, host
  logged, the download page opens in the browser, the chosen file is SHA256-checked (mandatory) and deleted
  on mismatch. Nothing downloaded is ever run.
- aria2 status line no longer mixes languages (`x16` connections).
- Tests: empty-path repro and guards, output-path checks, download-folder default, language files (same
  keys in all four, placeholders, BOM, every key used by the GUI, every tweak), fonts, settings round trip,
  mirror list / selection / SHA256 accept + delete-on-mismatch, log language.

## 0.3.1 - 2026-10-25
**Cross-check against the teammate research (MS edition IDs, appx names by build).**

- Edition 2360 (Windows 11 22H2 original, 22621.382) marked "no longer offered – use a local ISO": the API
  still returns a link but the CDN answers HTTP 400 (probe on 2 sessions, 2026-10-25).
- Error 715-123130 (Type 9, IP / region / VPN block) is no longer retried (SKU list and link);
  SentinelReject (Type 8) is still retried with a new session.
- Xbox TCUI, Xbox Identity Provider, Xbox Speech-to-text and Get Help are now opt-in (Win10 + Win11),
  labelled *unsafe* (Win11Debloat rates them unsafe: Store/game dialogs, Xbox sign-in, accessibility,
  troubleshooters).
- Build ranges (Win11): Maps, People, Mail & Calendar, Movies & TV up to 23H2 (22631), since a clean
  24H2 install no longer has them; Dev Home 23H2–24H2 only.
- Tests for all of the above, plus package-name checks (Clipchamp.Clipchamp, MicrosoftTeams vs MSTeams,
  Microsoft.Copilot, Microsoft.Paint protected).

## 0.3.0 - 2026-10-25
**Multi-connection downloads (aria2), every Windows release, version-aware debloat profile.**

- Before: one HTTPS connection (HttpWebRequest, 1 MB buffer, `.partial` resume, SHA256 check).
- aria2 1.37.0 bundled (`tools\aria2\x64|x86\aria2c.exe`, GPLv2, unmodified, NOTICE with hashes + source
  link). Detection: `tools\aria2c.exe`, next to the script, bundled x64/x86, PATH. `-x16 -s16 -k1M`,
  `--continue`, certificate check, retries, options in `DebloatConfig.psd1` (`Download`). Progress, speed
  and connections in the GUI status line; *Cancel* kills aria2c; aria2 failure (e.g. 403) → warning +
  automatic fallback to the built-in downloader (keeps a sequential partial file for resume);
  SHA256 still verified. GUI checkbox *Use aria2 (multi-connection) / Dùng aria2 (tải đa luồng)*.
- Release picker: Windows 11 21H2…26H2 (x64, ARM64 for 24H2+) and Windows 10 1507…22H2 (x64/x86),
  29 releases. *Languages* loads one release at a time; withdrawn releases are marked "no longer offered –
  use a local ISO". Sentinel rejections are retried with a fresh session.
- Version-aware profile: build → release name (`Windows 11 24H2 (26100)`), optional `MinBuild`/`MaxBuild`
  per app/tweak (49 entries annotated); the GUI shows only entries for the detected build; the engine skips
  and logs out-of-range tweaks and apps missing from the image.
- System check reports aria2 (with the Windows 7 TLS note).
- Tests: aria2 detection order, arguments + quoting, progress parsing, success / 403 fallback / cancel /
  partial resume with a mocked process, real aria2c against a local Range server, release catalog,
  language loading (ok / withdrawn / Sentinel), link retry, build mapping and profile filtering.

## 0.2.1 - 2026-10-24
**Fix: "Load list" showed nothing.**

- Root cause: the session registration call to `vlscppe.microsoft.com` was fatal. On PCs where DNS,
  an ad blocker, a hosts file or the ISP blocks that host ("The remote name could not be resolved:
  'vlscppe.microsoft.com'"), every product failed and no list appeared.
  Both registration steps (vlscppe + ov-df) are now best effort with a 10 s timeout; the tool continues
  to www.microsoft.com anyway. Verified live: the language list needs no registration, the download
  link needs only the ov-df step.
- When Microsoft rejects a link (`SentinelReject`, 715-123130) the message says which host was
  unreachable and suggests DNS 1.1.1.1 / 8.8.8.8, turning off VPN, or the browser fallback (EN + VI).
- The version/architecture list (Windows 11 x64/arm64, Windows 10 x64/x86) is always shown, even
  offline; for entries Microsoft did not return, *Download* opens the official page.
- Status line while loading, per-product progress, errors from the list are shown in a message box.
- GUI robustness: every event handler and job callback is wrapped (errors no longer vanish into the
  hidden console); a click while another task runs is queued instead of silently ignored; the startup
  system check and ISO detection run in the background without locking the buttons.
- GUI session log file: `logs\WinDebloat_gui_<date>_<time>.log` in the tool folder (or `%TEMP%` if the
  folder is read-only), with error details; *Open log folder* link in the window.
- Web requests use HttpWebRequest with timeouts (30 s; WebClient had none) and name the failing host.
- Non-JSON answers (proxy / captive portal pages) give a clear error.
- Release labels: x64 and ARM64 Windows 11 now share one label ("Windows 11 26H2 (Build 26300.9457)").
- Tests: user's exact DNS failure, vlscppe + ov-df blocked, fully offline, partial failure, HTML answer,
  real Microsoft responses (captured 2026-10-24), background runspace job + log file.

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

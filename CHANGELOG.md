# Changelog

## 0.3.8 - 2026-10-26
**Fix: START stopped with "Work dir is not empty and was not created by this tool: D:\WinDebloat_work"** (real
Windows 11 report, folder left by an earlier run of 0.3.5/0.3.6).

- Cause: the old cleanup deleted the work folder with one `Remove-Item -Recurse`. The ownership marker
  `.w11debloat-work` sorts first and was deleted, then files in use (e.g. a still-mounted image) stopped the
  delete, so the next run found a folder without marker and refused it.
- A work folder is now "ours" with the marker, or when it holds only what this tool creates (`iso\` with ISO
  files, `mount\` with a Windows image, `scratch\`, `install.work.wim` / `install.new.*`, logs). Such a leftover
  is cleaned first, every step logged: unload our offline hives (`HKLM\W11D_SOFTWARE`, `HKLM\W11D_DEFAULT`),
  `dism /Unmount-Image /MountDir:<dir> /Discard` for every image DISM lists below the folder (and for a
  non-empty mount folder it does not list), `dism /Cleanup-Mountpoints`, then delete with retries (clear
  attributes, then takeown + icacls for Administrators). The marker is written first and deleted last.
- A folder with other files is never deleted. GUI: a dialog (4 languages) offers a new folder such as
  `D:\WinDebloat_work_2`, or cancel. Console: the next free name is used and logged (`-WorkDirConflict Fail`
  stops instead).
- The work folder is cleaned in `finally` after a finished, failed or cancelled run (mounted image discarded
  first); `-KeepWorkDir` keeps it.
- GUI shows one language: engine messages are bilingual `English / Tiếng Việt` (the log keeps both); dialogs,
  the failure message and the status line now show the Vietnamese part for `vi` and the English part for the
  other languages. Several engine messages now carry their details (numbers, paths) in both parts.
- Tests: leftover of an older version accepted and cleaned, mounted leftover unmounted before the new mount,
  foreign folder kept (console picks `_2`/`_3`, `Fail` stops before any DISM call), cleanup after failure and
  cancel, `-KeepWorkDir`, one-language texts for every bilingual engine message.

## 0.3.7 - 2026-10-26
**Output ISO much larger than the source (report: +10 GB with "All" editions).**

- Findings: the mount folder, the work WIM and the ISO tree were already separate folders under the work dir,
  and the kept editions were already exported with `/Compress:max` into a fresh `install.wim`. What grows is
  the image itself: every serviced edition gets its own changed files after `/Unmount-Image /Commit`, and the
  export can only store a file once when it is byte-identical in all editions. With "All" (about 10 editions on
  the 26300 media, `install.wim` 8.2 GB in a 9.0 GB ISO) this adds up quickly, more so with component cleanup.
  0.3.6 also had no size log and no check, so the cause was not visible.
- The new image is always a NEW file next to the tree (`<work>\install.new.wim` / `.esd`). Every kept edition
  is exported into it, then it replaces every `install.*` (wim/esd/swm) in `sources\`.
- New option **ESD compression** (GUI checkbox; console `-Compression Recovery`): `/Compress:recovery` gives
  `install.esd`, the smallest ISO (Windows Setup reads it), but it is much slower. Default stays `Max` (LZX).
- `install.wim` bigger than 4 GB: WARN (fine for the ISO or an NTFS USB); console `-SplitWimMB 3800` splits it
  into `install.swm`, `install2.swm`, ... for FAT32 USB sticks (`dism /Split-Image`).
- Mount, scratch (`<work>\scratch`, passed to export / component cleanup) and temporary images are checked to be
  outside the ISO tree (and the output ISO too) at start, before export and before oscdimg.
- Before oscdimg, leftovers are removed from the tree: extra `install*` images, `*.tmp`, `*.partial`, `~*`.
- Log: `SIZE ...` lines for the source ISO and image, the work WIM after each commit (+growth), the new image
  after each export (+growth), the ISO tree and the output ISO. WARN when the new image is more than 500 MB
  larger than the source image (advice: fewer editions or ESD), and when the output ISO is more than 500 MB
  larger than the source ISO, with the 10 largest files of the ISO tree.
- ISO label made only of padding falls back to `WIN11_DEBLOAT`.
- Tests: path inside/outside checks, the work layout, export / split command lines, and a mocked full pipeline
  (Max, Recovery, split) on real folders: only the new image ends up in the tree, no DISM path inside the tree,
  size lines and warnings present.

## 0.3.6 - 2026-10-26
**App icon and button icons.**

- **App icon** (`assets/WinDebloatTool.ico`, 16 20 24 32 40 48 64 128 256 px; SVG sources `assets/icon.svg`
  and a simplified `assets/icon-small.svg` used for 16-32 px; `icon-256.png` / `icon-512.png` for the README):
  tilted, rounded, gradient window panes with a broom sweeping across them and a few sparkles. Our own
  drawing, not the Microsoft logo. Set on the main window and the mirror picker. Entries up to 128 px are
  32-bit BMP so the .NET 2.0 `Icon` class (Windows 7 / PowerShell 2.0) can read them.
- **Button icons** (`assets/icons/<name>_<16|20|24|32>.png`, SVG sources in `assets/icons/svg/`), one
  consistent Fluent-like set drawn for this project: Chọn... (folder), Lưu thành... (save), Lấy ngôn ngữ
  (refresh), Tải về (download), Mặc định / Chọn hết / Bỏ hết (reset / checked / empty box), Xem các phiên bản
  (eye), Kiểm tra máy (shield), Cài oscdimg (wrench), BẮT ĐẦU (broom), Huỷ (stop), plus a globe before
  "Mở trang Microsoft" and a folder before "Mở thư mục nhật ký" (clickable). Icon before the text; size
  by DPI (100 % 16 px, 125 % 20, 150 % 24, 200 % 32). The layout adds the icon width to every measured
  button, so no text is cut in any language. Disabled buttons draw the icon greyed (WinForms).
- Icons are optional: a missing or unreadable file means no icon, never an error. Images are copied in
  memory, the PNG files are not kept locked.
- `assets/build_assets.py` (cairosvg + ImageMagick) rebuilds every PNG / ICO from the SVGs.
- README: icon, *Credits* (icons, Raphire/Win11Debloat app list and ratings reference, pbatard/Fido download
  flow).
- Tests: ICO sizes / BMP entries, every mapped icon in 4 sizes, icons missing -> no error, icon size by DPI,
  layout with 16 px icons in all 4 languages.

## 0.3.5 - 2026-10-26
**Fix: START failed at once when the output ISO is on the root of a drive.**

- **Bug (real Windows 11, PowerShell 5.1):** output `D:\Windows11_..._debloated.iso` -> "The path is not of
  a legal form" (`System.ArgumentException`). `Invoke-Win11Debloat` ran `New-Item -ItemType Directory -Force`
  on the output folder, which is `D:\` here; Windows PowerShell's file system provider cannot do that on a
  drive root (it builds a `DirectoryInfo` from an empty parent path). The folder already existed - nothing
  needed creating.
- New `New-W11Directory`: does nothing when the folder exists, never touches a drive / share root, creates
  missing folders with `[IO.Directory]::CreateDirectory`; used for the output, work, mount, 7-Zip extraction,
  settings, download and log folders (no `New-Item -ItemType Directory` left).
- New path rules for everything the user types or pastes (`ConvertTo-W11CleanPath`, `Resolve-W11FullPath`,
  `Get-W11ParentDir`): spaces, `"..."`, `'...'`, typographic quotes, zero-width / BOM / bidi characters and
  non-breaking spaces removed; `/` -> `\`; `D:` -> `D:\`; `D:x.iso` -> `D:\x.iso`; relative paths resolved
  against the PowerShell folder (not the process folder, which is System32 when elevated); `.` / `..`,
  repeated and trailing `\` collapse; UNC `\\server\share\...` supported. Invalid characters, reserved names
  (CON, NUL, COM1...), `\\?\` paths and `..` above the root are refused with a clear message.
- Work folder: next to the output ISO (`D:\WinDebloat_work` for a drive-root output), `%TEMP%` when the output
  is on a network share; a drive root is refused as work folder (it is deleted after the run). Free space is
  now also checked on the output drive when it differs from the work drive (>= 8 GB). A missing / not ready
  drive gives a clear message instead of a .NET error.
- Output check before START, in all four languages: drive or share missing, a folder instead of a file name
  (with an example name), invalid characters. The cleaned, absolute paths are written back into the boxes.
- `ConvertTo-W11Arg` keeps the backslash of a drive root (`"D:\\"`), so tools never get the drive-relative `D:`.
- Tests: the exact report (source and output on `D:\`) runs through path preparation (output folder `D:\`, work
  folder `D:\WinDebloat_work`); 28 path cases (quotes, invisible characters, spaces, relative, drive root, UNC,
  trailing `\`, invalid); messages; no `New-Item -ItemType Directory` left.

## 0.3.4 - 2026-10-26
**Resizable layout, no clipped text, Vietnamese app notes.**

- **Bug (real Windows 11, maximized):** sections 1-4 and the button row kept their design width; only the log
  box stretched. Every control is now placed by `Set-W11Layout` on each resize and after a language switch:
  sections 1 and 4, the ISO path boxes, the release / language combos and the progress bar stretch to the
  right edge; sections 2 and 3 share the width 58/42 and grow in height together with the app / tweak lists;
  the log box takes the rest; the watermark stays at the bottom right. Positions scale with the DPI the
  process sees (PowerShell 7 is DPI aware, Windows PowerShell 5.1 is scaled by Windows).
- **Bug: clipped text.** Widths of labels, buttons, radio buttons and check boxes come from the text in the
  current language and font (`TextRenderer.MeasureText`), so nothing is cut in vi / en / zh-CN / km. The
  autounattend check box and the "always kept" hint wrap onto as many lines as they need; the language combo
  is always wide enough for "(bấm Lấy ngôn ngữ)"; status, detected-OS and aria2 labels end with "…" instead
  of being cut. The app and tweak lists get a horizontal scroll bar sized to their longest entry.
- **No mixed Vietnamese / English in the app list:** the notes in brackets are translated part by part
  (*không an toàn: đăng nhập game*, *trợ năng, khó cài lại*, *công cụ khắc phục sự cố*, *giao diện
  Store/game*, *bản mới*, *tuỳ chọn; Paint cổ điển vẫn giữ*), also for zh-CN / km; product names and package
  Ids stay as they are. Vietnamese tweak names without English leftovers (consumer features, policy,
  telemetry; Khmer too), and the Vietnamese tweak names in the log file.
- Tests: layout geometry with mock controls for 4 languages x 3 window sizes (minimum, 1264x921, maximized
  1920 wide): no overlaps, nothing outside its section or under the watermark, sections reach the right
  edge, 58/42 split, one-line texts fit; app notes fully translated.

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

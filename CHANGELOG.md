# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

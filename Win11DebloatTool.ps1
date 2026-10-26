<#
    Alias of WinDebloatTool.ps1: same parameters, forwards everything to it.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$IsoPath,
    [string]$OutputIso,
    [string]$WorkDir,
    [ValidateSet('All', 'HomePro', 'Custom')][string]$Edition = 'All',
    [ValidateSet('Auto', 'Win10', 'Win11')][string]$TargetOs = 'Auto',
    [int[]]$Indexes,
    [switch]$NoAutounattend,
    [switch]$ComponentCleanup,
    [ValidateSet('Max', 'Recovery')][string]$Compression = 'Max',
    [int]$SplitWimMB = 0,
    [switch]$DryRun,
    [switch]$NoGui,
    [switch]$Check,
    [switch]$KeepWorkDir,
    [int]$MinFreeGB = 25,
    [string]$OscdimgPath,
    [string]$Preset,                # safe | aggressive | path of a preset .json (explicit parameters win)
    [string]$UpdatesPath,           # folder with .msu / .cab updates (SSU, LCU, .NET, Safe OS)
    [switch]$UpdateBootWim,
    [switch]$UpdateWinRE,
    [switch]$ResetBase,
    [string]$LocalUser,             # answer file: create this local administrator account
    [string]$LocalPassword,         # plain text; without it the password is asked (empty = no password)
    [switch]$NoBypassNro,
    [switch]$BypassChecks,          # Windows 11: skip TPM / Secure Boot / RAM checks in setup
    [switch]$SkipPrivacy,
    [switch]$FirstLogonCleanup,
    [string]$Locale,                # e.g. vi-VN
    [string]$Keyboard,              # e.g. 0409:00000409 or en-US
    [string]$AutounattendPath,      # your own answer file instead of the generated one
    [ValidateSet('Simple', 'Advanced')][string]$Mode,     # GUI: open this mode (skips the chooser)
    [switch]$Simple,                # Simple mode in the console: newest official ISO -> Home + Pro -> safe preset -> ISO
    [string]$OutputFolder,          # Simple mode: where the ISO is downloaded and the new ISO is saved
    [string]$IsoLanguage = 'auto'   # Simple mode: Microsoft language name (English International, English, ...) or auto
)
$target = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'WinDebloatTool.ps1'
if ($WhatIfPreference) { $PSBoundParameters['DryRun'] = [switch]$true; [void]$PSBoundParameters.Remove('WhatIf') }
$global:LASTEXITCODE = 0
try { & $target @PSBoundParameters } catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
exit $LASTEXITCODE

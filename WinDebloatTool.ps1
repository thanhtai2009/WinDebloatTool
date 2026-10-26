<#
.SYNOPSIS
    WinDebloat Tool - turn an official Windows 10 or Windows 11 ISO into a debloated ISO.
    Công cụ tạo ISO Windows 10 / 11 gọn nhẹ từ ISO gốc của Microsoft.

.DESCRIPTION
    Without parameters a GUI opens (download official ISO or pick a local one, choose apps/tweaks,
    progress + log). With -NoGui (or -IsoPath) it runs in the console.
    The target OS (and with it the debloat profile) is detected from the image build
    (>= 22000 = Windows 11, 10240-21999 = Windows 10); -TargetOs overrides it.
    Runs on Windows 7 SP1 .. 11 with Windows PowerShell 2.0+ (see README for Windows 7 limits).
    Launch through run.bat, which elevates to Administrator.

.EXAMPLE
    .\WinDebloatTool.ps1
.EXAMPLE
    .\WinDebloatTool.ps1 -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_lite.iso -Edition HomePro
.EXAMPLE
    .\WinDebloatTool.ps1 -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf
.EXAMPLE
    .\WinDebloatTool.ps1 -NoGui -IsoPath D:\Win10_22H2_English_x64v1.iso -OutputIso D:\Win10_lite.iso -TargetOs Win10
.EXAMPLE
    .\WinDebloatTool.ps1 -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_small.iso -Compression Recovery
    (install.esd, smallest ISO, slower; -SplitWimMB 3800 splits a >4 GB install.wim into install*.swm for FAT32 USB)
.EXAMPLE
    .\WinDebloatTool.ps1 -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_min.iso -Preset aggressive
    (built-in presets: safe, aggressive; or a .json saved from the GUI)
.EXAMPLE
    .\WinDebloatTool.ps1 -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_upd.iso -UpdatesPath D:\Updates -UpdateWinRE
.EXAMPLE
    .\WinDebloatTool.ps1 -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_auto.iso -LocalUser Tai -SkipPrivacy -Locale vi-VN -FirstLogonCleanup
.EXAMPLE
    .\WinDebloatTool.ps1 -Check
.EXAMPLE
    .\WinDebloatTool.ps1 -Mode Simple
    (opens the GUI directly in Simple mode; -Mode Advanced = the full window)
.EXAMPLE
    .\WinDebloatTool.ps1 -Simple -OutputFolder D:\ISO -TargetOs Win11 -IsoLanguage 'English International'
    (console: newest official ISO from Microsoft, Home + Pro, safe preset, oscdimg installed if missing; add -DryRun to only show the plan,
     -IsoPath to use an ISO you already have)
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

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'lib\Core.ps1')
. (Join-Path $here 'lib\MsDownload.ps1')
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { $null = $_ }
if ($WhatIfPreference) { $DryRun = [switch]$true; $WhatIfPreference = $false }

if ($Check) {
    $wp = $env:TEMP
    if ($OutputIso) { $o = Resolve-W11FullPath $OutputIso; if ($o) { $d = Get-W11ParentDir $o; if ($d -and -not $d.StartsWith('\\')) { $wp = $d } } }
    $null = Get-W11Capabilities -WorkPath $wp -MinFreeGB $MinFreeGB
    return
}

if ($Mode -eq 'Simple' -and $NoGui) { $Simple = [switch]$true }
if (-not $NoGui -and -not $IsoPath -and -not $Simple) {
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        Write-W11Log -Level WARN -En 'GUI needs -STA. Start through run.bat.' -Vi 'Giao diện cần -STA, hãy chạy bằng run.bat.'
    }
    . (Join-Path $here 'lib\Gui.ps1')
    Show-W11Gui -Mode $Mode
    return
}

# ------------------------- Simple mode, console -------------------------
if ($Simple) {
    $os = 'Win11'; if ($TargetOs -eq 'Win10') { $os = 'Win10' }
    $dir = $OutputFolder
    if (-not $dir) { $dir = Get-W11SimpleDefaultFolder }
    $dir = Resolve-W11FullPath (ConvertTo-W11CleanPath $dir)
    if (-not $dir) { Write-Host "ERROR / LỖI: invalid output folder / thư mục không hợp lệ: $OutputFolder" -ForegroundColor Red; exit 2 }
    $free = -1; try { $free = Get-W11FreeGB -Path $dir } catch { Write-Host "ERROR / LỖI: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
    $iso = ''; if ($IsoPath) { $iso = Resolve-W11FullPath $IsoPath }
    $plan = Get-W11SimplePlan -Os $os -UiLang 'vi' -LangChoice $IsoLanguage -OutputFolder $dir -FreeGB $free -IsoPath $iso
    if ($PSBoundParameters.ContainsKey('MinFreeGB')) { $plan.BuildMinFreeGB = $MinFreeGB }
    elseif ($plan.LowSpace -and -not $DryRun) {
        Write-Host ("ERROR / LỖI: only {0} GB free on {1}, about {2} GB are needed. Add -MinFreeGB 0 to continue anyway / Chỉ còn {0} GB trống, cần khoảng {2} GB (thêm -MinFreeGB 0 để vẫn chạy)" -f $free, $dir, $plan.MinFreeGB) -ForegroundColor Red
        exit 2
    }
    Write-Host ("Simple mode / Chế độ Đơn giản: {0} {1} | ISO language: {2} | Home + Pro | preset safe | {3}" -f $os, $plan.Arch, ($plan.LangPrefs -join ' > '), $dir)
    try {
        $r = Invoke-W11SimpleBuild -Plan $plan -IsoPath $iso -DryRun:$DryRun -DownloadOptions (Get-MsAria2Options -Config (Get-W11Config))
        Write-Progress -Activity 'WinDebloat Tool' -Completed
        if ($r.DownloadFailed) {
            Write-Host "ERROR / LỖI: download from Microsoft failed / tải từ Microsoft thất bại: $($r.Error)" -ForegroundColor Red
            foreach ($m in @(Get-MsMirrorCandidates -Config (Get-W11Config) -Os $plan.Os -Arch $plan.Arch -ReleaseName '')) { Write-Host "  mirror (not Microsoft, check SHA256 $($m.Sha256)): $($m.FileName) - $($m.Page)" }
            Write-Host '  Download the ISO yourself, then run again with -IsoPath <file> / Tự tải ISO rồi chạy lại với -IsoPath <file>'
            exit 3
        }
        if ($r.Build -and $r.Build.Sha256) { Write-Host ''; Write-Host "ISO   : $($r.Build.OutputIso)" -ForegroundColor Green; Write-Host "SHA256: $($r.Build.Sha256)" -ForegroundColor Green }
        if ($r.Build -and $r.Build.LogPath) { Write-Host "Log   : $($r.Build.LogPath)" }
        exit 0
    } catch {
        Write-Host ''
        Write-Host "ERROR / LỖI: $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }
}

# ------------------------- console mode -------------------------
$null = Get-W11Capabilities -WorkPath $env:TEMP -MinFreeGB $MinFreeGB
if (-not $IsoPath) {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Filter = 'Windows ISO (*.iso)|*.iso'
    $d.Title = 'Select the official Windows 10/11 ISO / Chọn ISO Windows 10/11 gốc'
    if ($d.ShowDialog() -ne 'OK') { Write-W11Log -Level WARN -En 'No ISO selected.' -Vi 'Chưa chọn ISO.'; exit 1 }
    $IsoPath = $d.FileName
}
if (-not $OutputIso) {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object Windows.Forms.SaveFileDialog
    $d.Filter = 'ISO (*.iso)|*.iso'
    $o = Resolve-W11FullPath $IsoPath; if ($o) { $d.InitialDirectory = Get-W11ParentDir $o }
    $d.FileName = [IO.Path]::GetFileNameWithoutExtension($IsoPath) + '_debloated.iso'
    if ($d.ShowDialog() -ne 'OK') { Write-W11Log -Level WARN -En 'No output selected.' -Vi 'Chưa chọn nơi lưu.'; exit 1 }
    $OutputIso = $d.FileName
}

if (-not $DryRun -and -not (Find-W11Oscdimg -Hint $OscdimgPath)) {
    if ((Get-W11AdkSetupPlan).Legacy -and (Get-W11AdkSetupPlan).Supported) {
        Write-Host ''
        Write-Host 'oscdimg.exe (Windows ADK) is required. On Windows 7/8.x only the older official ADK (Windows 10, version 1607) installs / Cần oscdimg.exe; trên Win7/8 chỉ cài được ADK cũ (bản 1607):'
        Write-Host '  [1] Try it (Deployment Tools only) / Thử cài (chỉ Deployment Tools)'
        Write-Host "  [Q] Quit and copy oscdimg.exe into $(Join-Path $here 'tools') / Thoát rồi tự chép oscdimg.exe vào thư mục tools"
        $c = Read-Host 'Choice / Lựa chọn'
        if ($c -eq '1') { $OscdimgPath = Install-W11Oscdimg -Method AdkSetup } else { exit 1 }
    } elseif ((Get-W11OsBuild) -ge 10240) {
        Write-Host ''
        Write-Host 'oscdimg.exe (Windows ADK) is required / Cần oscdimg.exe (Windows ADK):'
        Write-Host '  [1] Download official ADK installer, install only Deployment Tools / Tải bộ cài ADK chính thức, chỉ cài Deployment Tools'
        Write-Host '  [2] Install via winget (Microsoft.WindowsADK) / Cài qua winget'
        Write-Host '  [Q] Quit / Thoát'
        $c = Read-Host 'Choice / Lựa chọn'
        if ($c -eq '1') { $OscdimgPath = Install-W11Oscdimg -Method AdkSetup }
        elseif ($c -eq '2') { $OscdimgPath = Install-W11Oscdimg -Method Winget }
        else { exit 1 }
    } else {
        Write-W11Log -Level ERROR -En "oscdimg.exe not found. Copy it from a Windows 10/11 PC's ADK into $(Join-Path $here 'tools')" -Vi 'Không có oscdimg.exe, hãy chép từ máy Win10/11 có ADK vào thư mục tools'
        exit 1
    }
}

$params = @{
    IsoPath = $IsoPath; OutputIso = $OutputIso; EditionMode = $Edition; TargetOs = $TargetOs
    Autounattend = (-not $NoAutounattend); ComponentCleanup = [bool]$ComponentCleanup; DryRun = [bool]$DryRun
    MinFreeGB = $MinFreeGB; KeepWorkDir = [bool]$KeepWorkDir; Compression = $Compression; SplitWimMB = $SplitWimMB
}
if ($WorkDir) { $params.WorkDir = $WorkDir }
if ($Indexes) { $params.Indexes = $Indexes }
if ($OscdimgPath) { $params.OscdimgPath = $OscdimgPath }
if ($AutounattendPath) { $params.AutounattendPath = $AutounattendPath }
$bp = $PSBoundParameters
if ($Preset) {
    $params.Preset = $Preset
    # options not given on the command line come from the preset
    if (-not $bp.ContainsKey('Edition')) { [void]$params.Remove('EditionMode') }
    if (-not $bp.ContainsKey('Compression')) { [void]$params.Remove('Compression') }
    if (-not $bp.ContainsKey('ComponentCleanup')) { [void]$params.Remove('ComponentCleanup') }
    if (-not $bp.ContainsKey('NoAutounattend')) { [void]$params.Remove('Autounattend') }
}
if ($UpdatesPath) { $params.UpdatesPath = $UpdatesPath }
if ($bp.ContainsKey('UpdateBootWim')) { $params.UpdateBootWim = [bool]$UpdateBootWim }
if ($bp.ContainsKey('UpdateWinRE')) { $params.UpdateWinRE = [bool]$UpdateWinRE }
if ($bp.ContainsKey('ResetBase')) { $params.ResetBase = [bool]$ResetBase }
$uKeys = @('LocalUser', 'LocalPassword', 'NoBypassNro', 'BypassChecks', 'SkipPrivacy', 'FirstLogonCleanup', 'Locale', 'Keyboard')
if (@($uKeys | Where-Object { $bp.ContainsKey($_) }).Count -gt 0) {
    $uo = Get-W11UnattendDefaults
    if ($Preset) { $uo = Get-W11PresetUnattend (Read-W11Preset -Path (Resolve-W11PresetRef $Preset)) }
    if ($LocalUser) {
        if (-not (Test-W11LocalAccountName $LocalUser)) { Write-Host "ERROR / LỖI: invalid account name / tên tài khoản không hợp lệ: $LocalUser" -ForegroundColor Red; exit 2 }
        $uo.LocalAccount = $true; $uo.UserName = $LocalUser
        if ($bp.ContainsKey('LocalPassword')) { $uo.Password = $LocalPassword }
        else {
            $sec = Read-Host -AsSecureString "Password for $LocalUser (empty = none, stored as plain text in autounattend.xml) / Mật khẩu (để trống = không đặt)"
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            try { $uo.Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }
    if ($bp.ContainsKey('NoBypassNro')) { $uo.BypassNro = -not $NoBypassNro }
    if ($bp.ContainsKey('BypassChecks')) { $uo.BypassChecks = [bool]$BypassChecks }
    if ($bp.ContainsKey('SkipPrivacy')) { $uo.SkipPrivacy = [bool]$SkipPrivacy }
    if ($bp.ContainsKey('FirstLogonCleanup')) { $uo.FirstLogonCleanup = [bool]$FirstLogonCleanup }
    if ($Locale) { $uo.Locale = $Locale }
    if ($Keyboard) { $uo.Keyboard = $Keyboard }
    $params.UnattendOptions = $uo
}
try {
    $r = Invoke-Win11Debloat @params
    Write-Progress -Activity 'WinDebloat Tool' -Completed
    if ($r.TargetOs) { Write-Host "Target: $(Get-W11OsLabel $r.TargetOs)" }
    if ($r.Sha256) { Write-Host ''; Write-Host "ISO   : $($r.OutputIso)" -ForegroundColor Green; Write-Host "SHA256: $($r.Sha256)" -ForegroundColor Green }
    Write-Host "Log   : $($r.LogPath)"
    exit 0
} catch {
    Write-Host ''
    Write-Host "ERROR / LỖI: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

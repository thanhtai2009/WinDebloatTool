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
    .\WinDebloatTool.ps1 -Check
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
    [switch]$DryRun,
    [switch]$NoGui,
    [switch]$Check,
    [switch]$KeepWorkDir,
    [int]$MinFreeGB = 25,
    [string]$OscdimgPath
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

if (-not $NoGui -and -not $IsoPath) {
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        Write-W11Log -Level WARN -En 'GUI needs -STA. Start through run.bat.' -Vi 'Giao diện cần -STA, hãy chạy bằng run.bat.'
    }
    . (Join-Path $here 'lib\Gui.ps1')
    Show-W11Gui
    return
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
    if ((Get-W11OsBuild) -ge 10240) {
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
    MinFreeGB = $MinFreeGB; KeepWorkDir = [bool]$KeepWorkDir
}
if ($WorkDir) { $params.WorkDir = $WorkDir }
if ($Indexes) { $params.Indexes = $Indexes }
if ($OscdimgPath) { $params.OscdimgPath = $OscdimgPath }
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

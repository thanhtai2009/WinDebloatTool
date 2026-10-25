<#
    WinDebloat Tool - Windows Forms GUI (PowerShell 2.0+ / .NET 3.5+ compatible).
    Long work runs in a background runspace; a timer pumps log lines and progress into the UI.
    SPDX-License-Identifier: MIT
#>

function New-W11Ctl {
    param([string]$Type, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H)
    $c = New-Object ("System.Windows.Forms.$Type")
    if ($Text) { $c.Text = $Text }
    $c.Location = New-Object Drawing.Point $X, $Y
    $c.Size = New-Object Drawing.Size $W, $H
    return $c
}

function Set-W11Busy {
    param([bool]$Busy)
    foreach ($c in $script:BusyControls) { $c.Enabled = -not $Busy }
    $script:ui.btnCancel.Enabled = $Busy
    if ($Busy) { $script:ui.form.Cursor = [Windows.Forms.Cursors]::AppStarting } else { $script:ui.form.Cursor = [Windows.Forms.Cursors]::Default }
}

function Get-W11JobText {
    <# Script text for a background runspace: Core + MsDownload (+ optional prelude, used by the tests),
       then $Script inside try/catch. Errors land in $sync.Error and, with details, in the log file. #>
    param([string]$Script, [string]$Root, [string]$Prelude = '')
    $core = [IO.File]::ReadAllText((Join-Path (Join-Path $Root 'lib') 'Core.ps1'))
    $dl = [IO.File]::ReadAllText((Join-Path (Join-Path $Root 'lib') 'MsDownload.ps1'))
    return $core + "`r`n" + $dl + "`r`n" + $Prelude + "`r`n" + @'
$script:W11Root = $W11RootPath
$script:W11D.Sync = $sync
if ($W11LogPath) { $script:W11D.LogPath = $W11LogPath }
$ErrorActionPreference = 'Stop'
try {
'@ + "`r`n" + $Script + "`r`n" + @'
} catch {
    $sync.Error = $_.Exception.Message
    Write-W11Log -Level ERROR -En $_.Exception.Message
    $detail = $_.Exception.ToString()
    if ($_.ScriptStackTrace) { $detail += "`r`n" + $_.ScriptStackTrace }
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) { $detail += "`r`n" + $_.InvocationInfo.PositionMessage }
    if ($script:W11D.LogPath) { try { Add-Content -LiteralPath $script:W11D.LogPath -Value ('    ' + $detail) -Encoding UTF8 } catch { $null = $_ } }
}
'@
}

function Start-W11Job {
    <# Runs $Script (text) in a background runspace. Core + MsDownload are injected as text so the
       runspace does not depend on the execution policy. $sync and $JobArgs are available.
       -Background: does not lock the UI (startup check, OS detection) and is skipped if busy.
       A user action while another job runs is queued and starts right after it (never dropped silently). #>
    param([string]$Script, [hashtable]$JobArgs = @{}, [scriptblock]$OnDone, [switch]$Background, [string]$Name = 'task')
    if ($script:Job) {
        if ($Background) { return $false }
        $script:PendingJob = @{ Script = $Script; JobArgs = $JobArgs; OnDone = $OnDone; Name = $Name }
        Write-W11Log -En "'$Name' will start when the running '$($script:Job.Name)' finishes..." -Vi "'$Name' sẽ chạy ngay sau khi '$($script:Job.Name)' xong..."
        $script:ui.lblStatus.Text = "Waiting for $($script:Job.Name)... / Đang chờ tác vụ trước..."
        return $false
    }
    $script:Sync.Cancel = $false; $script:Sync.Error = $null; $script:Sync.Result = $null
    $script:Sync.Percent = 0; $script:Sync.Status = ''
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $script:Sync)
    $rs.SessionStateProxy.SetVariable('JobArgs', $JobArgs)
    $rs.SessionStateProxy.SetVariable('W11RootPath', $script:W11Root)
    $rs.SessionStateProxy.SetVariable('W11LogPath', $script:W11D.LogPath)
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript((Get-W11JobText -Script $Script -Root $script:W11Root))
    $script:Job = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); OnDone = $OnDone; Name = $Name; Background = [bool]$Background }
    if (-not $Background) { Set-W11Busy $true }
    return $true
}

function Invoke-W11Tick {
    try {
        $q = $script:Sync.LogQueue
        $sb = New-Object Text.StringBuilder
        while ($q.Count -gt 0) { [void]$sb.Append([string]$q.Dequeue()); [void]$sb.Append("`r`n") }
        if ($sb.Length -gt 0) { $script:ui.tbLog.AppendText($sb.ToString()) }
        if ($script:Job -and -not $script:Job.Background) {
            $p = [int]$script:Sync.Percent
            if ($p -lt 0) { $p = 0 }; if ($p -gt 100) { $p = 100 }
            $script:ui.pb.Value = $p
            if ($script:Sync.Status) { $script:ui.lblStatus.Text = [string]$script:Sync.Status }
        }
        if ($script:Job -and $script:Job.Handle.IsCompleted) {
            $j = $script:Job
            $script:Job = $null
            try { [void]$j.PS.EndInvoke($j.Handle) } catch { if (-not $script:Sync.Error) { $script:Sync.Error = $_.Exception.Message } }
            try {
                foreach ($er in @($j.PS.Streams.Error)) { if ($er) { Write-W11Log -Level WARN -En "[$($j.Name)] $er" } }
            } catch { $null = $_ }
            try { $j.PS.Dispose(); $j.RS.Close() } catch { $null = $_ }
            Invoke-W11Tick
            if (-not $j.Background) { Set-W11Busy $false }
            if ($j.OnDone) {
                try { & $j.OnDone }
                catch { Show-W11Error -Context $j.Name -ErrorRecord $_ }
            }
            if (-not $script:Job -and $script:PendingJob) {
                $pj = $script:PendingJob; $script:PendingJob = $null
                [void](Start-W11Job -Script $pj.Script -JobArgs $pj.JobArgs -OnDone $pj.OnDone -Name $pj.Name)
            }
        }
    } catch {
        if (-not $script:TickFailed) { $script:TickFailed = $true; Show-W11Error -Context 'UI timer' -ErrorRecord $_ }
    }
}

function Get-W11GuiLogPath {
    # GUI session log: <tool folder>\logs\WinDebloat_gui_<time>.log, or %TEMP% if the tool folder is read-only.
    $name = 'WinDebloat_gui_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log'
    foreach ($dir in @((Join-Path $script:W11Root 'logs'), $env:TEMP)) {
        if (-not $dir) { continue }
        try {
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop }
            $p = Join-Path $dir $name
            [IO.File]::WriteAllText($p, '')
            return $p
        } catch { $null = $_ }
    }
    return $null
}

function Show-W11Error {
    # Any failure in a click handler / job callback ends here: log (with details) + message box. Never silent.
    param([string]$Context, $ErrorRecord, [string]$Message)
    $msg = $Message
    if ($ErrorRecord) {
        $msg = $ErrorRecord.Exception.Message
        $detail = $ErrorRecord.Exception.ToString()
        if ($ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.PositionMessage) { $detail += "`r`n" + $ErrorRecord.InvocationInfo.PositionMessage }
        if ($ErrorRecord.ScriptStackTrace) { $detail += "`r`n" + $ErrorRecord.ScriptStackTrace }
        try { Write-W11Log -Level ERROR -En "[$Context] $msg" } catch { $null = $_ }
        if ($script:W11D.LogPath) { try { Add-Content -LiteralPath $script:W11D.LogPath -Value ('    ' + $detail) -Encoding UTF8 } catch { $null = $_ } }
    }
    try {
        if ($script:ui -and $script:ui.lblStatus) { $script:ui.lblStatus.Text = "Error / Lỗi: $msg" }
        if ($script:ui -and $script:ui.btnCancel -and -not $script:Job) { Set-W11Busy $false }
    } catch { $null = $_ }
    $logTxt = ''
    if ($script:W11D.LogPath) { $logTxt = "`n`nLog / Nhật ký:`n$($script:W11D.LogPath)" }
    try {
        [void][Windows.Forms.MessageBox]::Show($script:ui.form, "Unexpected error in '$Context':`n$msg`n`nLỗi không mong muốn ở '$Context'. Hãy gửi file log cho người hỗ trợ.$logTxt", 'WinDebloat Tool', 'OK', 'Error')
    } catch { $null = $_ }
}

function Invoke-W11Handler {
    # Event handlers are stored in $script:H and run through here, so an exception can never vanish
    # (PowerShell only prints errors from WinForms event scriptblocks to the hidden console window).
    param([string]$Name)
    try { & $script:H[$Name] }
    catch { Show-W11Error -Context $Name -ErrorRecord $_ }
}

function Show-W11Msg {
    param([string]$Text, [string]$Icon = 'Information', [string]$Buttons = 'OK')
    return [Windows.Forms.MessageBox]::Show($script:ui.form, $Text, 'WinDebloat Tool', $Buttons, $Icon)
}

function Get-W11ReleaseItemText($e) {
    if ($e.Available -eq $false) { return "$($e.Release)  [not offered / không còn]" }
    return $e.Release
}

function Update-W11DownloadLists {
    param([string]$Level)
    $cat = @($script:Catalog)
    if ($cat.Count -eq 0) { return }
    $ui = $script:ui
    if ($Level -eq 'release') {
        $keep = Get-W11SelectedRelease
        $script:ReleaseItems = @()
        $ui.cbRelease.Items.Clear()
        foreach ($r in @($cat | ForEach-Object { $_.Release } | Select-Object -Unique)) {
            $first = @($cat | Where-Object { $_.Release -eq $r })[0]
            $script:ReleaseItems += $r
            [void]$ui.cbRelease.Items.Add((Get-W11ReleaseItemText $first))
        }
        if ($ui.cbRelease.Items.Count -gt 0) {
            $idx = 0
            for ($i = 0; $i -lt $script:ReleaseItems.Count; $i++) { if ($script:ReleaseItems[$i] -eq $keep) { $idx = $i } }
            if ($ui.cbRelease.SelectedIndex -eq $idx) { Update-W11DownloadLists 'arch' } else { $ui.cbRelease.SelectedIndex = $idx }   # triggers 'arch'
        }
        return
    }
    if ($Level -eq 'arch') {
        $keep = [string]$ui.cbArch.SelectedItem
        $ui.cbArch.Items.Clear()
        $rel = Get-W11SelectedRelease
        foreach ($a in @($cat | Where-Object { $_.Release -eq $rel } | ForEach-Object { $_.Arch } | Select-Object -Unique)) { [void]$ui.cbArch.Items.Add($a) }
        if ($ui.cbArch.Items.Count -gt 0) {
            $idx = $ui.cbArch.Items.IndexOf($keep)
            if ($idx -lt 0) { $idx = $ui.cbArch.Items.IndexOf(((Get-W11HostArch) -replace 'amd64', 'x64')) }
            if ($idx -lt 0) { $idx = 0 }
            if ($ui.cbArch.SelectedIndex -eq $idx) { Update-W11DownloadLists 'lang' } else { $ui.cbArch.SelectedIndex = $idx }   # triggers 'lang'
        }
        return
    }
    if ($Level -eq 'lang') {
        $ui.cbLang.Items.Clear()
        $e = Get-W11SelectedEntry
        if (-not $e) { return }
        if ($e.Available -eq $false) {
            [void]$ui.cbLang.Items.Add('(not offered - use a local ISO / không còn, dùng ISO có sẵn)')
            $ui.cbLang.SelectedIndex = 0
            return
        }
        if ($e.Static -or @($e.Skus).Count -eq 0) {
            [void]$ui.cbLang.Items.Add('(press Load languages / bấm Lấy ngôn ngữ)')
            $ui.cbLang.SelectedIndex = 0
            return
        }
        $def = -1; $i = 0
        foreach ($s in $e.Skus) {
            [void]$ui.cbLang.Items.Add($s.LocalizedLanguage)
            if ($def -lt 0 -and $s.Language -eq 'English') { $def = $i }
            $i++
        }
        if ($def -lt 0) { $def = 0 }
        if ($ui.cbLang.Items.Count -gt 0) { $ui.cbLang.SelectedIndex = $def }
    }
}

function Get-W11SelectedRelease {
    $i = $script:ui.cbRelease.SelectedIndex
    if ($i -lt 0 -or $i -ge @($script:ReleaseItems).Count) { return $null }
    return $script:ReleaseItems[$i]
}

function Show-W11NotOffered($e) {
    $name = ''; if ($e) { $name = $e.Release }
    $ans = Show-W11Msg ("Microsoft no longer offers $name for download. Use a local ISO (Browse...) instead.`n`nMicrosoft không còn cung cấp bản này. Hãy dùng file ISO có sẵn trên máy (bấm Chọn...).`n`nOpen the Microsoft page? / Mở trang Microsoft?") 'Information' 'YesNo'
    if ([string]$ans -eq 'Yes') { & $script:H['lnkMs.LinkClicked'] }
}

function Get-W11SelectedEntry {
    $rel = Get-W11SelectedRelease
    $arch = [string]$script:ui.cbArch.SelectedItem
    return (@($script:Catalog | Where-Object { $_.Release -eq $rel -and $_.Arch -eq $arch }) | Select-Object -First 1)
}

function Get-W11SuggestedOutput {
    param([string]$Iso)
    $dir = Split-Path -Parent $Iso
    $name = [IO.Path]::GetFileNameWithoutExtension($Iso) + '_debloated.iso'
    return (Join-Path $dir $name)
}

function Get-W11EffectiveOs {
    # Combo: 0 = Auto (detected, else Windows 11 list as placeholder), 1 = Windows 11, 2 = Windows 10
    $i = $script:ui.cbOs.SelectedIndex
    if ($i -eq 1) { return 'Win11' }
    if ($i -eq 2) { return 'Win10' }
    if ($script:DetectedOs) { return $script:DetectedOs }
    return 'Win11'
}

function Set-W11ProfileLists {
    # (Re)fills the app and tweak lists for the effective target OS and, when known, the image build
    # (entries outside their MinBuild/MaxBuild are hidden).
    param([switch]$Force)
    $os = Get-W11EffectiveOs
    $build = 0; if ($script:DetectedOs -and $script:DetectedOs -eq $os) { $build = [int]$script:DetectedBuild }
    $key = "$os/$build"
    if (-not $Force -and $script:ShownOs -eq $key) { return }
    $script:ShownOs = $key
    $prof = Get-W11Profile -Config $script:Cfg -Os $os -Build $build
    $script:ProfileApps = @($prof.Apps)
    $ui = $script:ui
    $ui.clbApps.Items.Clear(); $script:AppIds = @()
    foreach ($a in $prof.Apps) {
        $i = $ui.clbApps.Items.Add(('{0}   [{1}]' -f $a.Name, $a.Id))
        $ui.clbApps.SetItemChecked($i, [bool]$a.Default)
        $script:AppIds += $a.Id
    }
    $ui.clbTweaks.Items.Clear(); $script:TweakIds = @()
    foreach ($t in $prof.Tweaks) {
        $i = $ui.clbTweaks.Items.Add(('{0} / {1}' -f $t.Name, $t.NameVi))
        $ui.clbTweaks.SetItemChecked($i, [bool]$t.Default)
        $script:TweakIds += $t.Id
    }
    $title = Get-W11OsLabel $os
    if ($build -gt 0) { $title = Get-W11ReleaseLabel -Build $build -Os $os }
    $ui.grpApps.Text = ('2. Apps to remove / App sẽ gỡ  -  {0}' -f $title)
    $hidden = @($prof.SkippedApps).Count + @($prof.SkippedTweaks).Count
    if ($build -gt 0 -and $hidden -gt 0) { Write-W11Log -En "$hidden list entries do not apply to $title and are hidden" -Vi "$hidden mục không áp dụng cho bản này nên được ẩn" }
}

function Set-W11Detected {
    param([string]$Os, [string]$Source, [int]$Build = 0)
    $script:DetectedOs = $Os
    $script:DetectedBuild = $Build
    $txt = 'Detected / Nhận diện: '
    if ($Os) {
        $txt += (Get-W11ReleaseLabel -Build $Build -Os $Os)
        $txt += " [$Source]"
    } else { $txt += 'unknown - choose manually / chưa rõ, hãy chọn tay' }
    $script:ui.lblOs.Text = $txt
    Set-W11ProfileLists
}

function Start-W11Detect {
    # quick guess from the file name, then (Win8+) read the WIM header inside the ISO in the background
    param([string]$Iso)
    $g = Get-W11OsFromName $Iso
    $gb = 0; if ([IO.Path]::GetFileName($Iso) -match '(?<!\d)(1\d{4}|2\d{4})(?!\d)') { $gb = [int]$Matches[1]; if ((Resolve-W11OsFromBuild $gb) -ne $g) { $gb = 0 } }
    Set-W11Detected -Os $g -Source 'filename' -Build $gb
    if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) { return }
    [void](Start-W11Job -Background -Name 'OS detection' -Script '$sync.Result = Get-W11IsoOsInfo -IsoPath $JobArgs.Iso' -JobArgs @{ Iso = $Iso } -OnDone {
        $r = $script:Sync.Result
        if ($r -and $r.Os) {
            Set-W11Detected -Os $r.Os -Source $r.Source -Build $r.Build
            Write-W11Log -Level OK -En "Target OS detected: $(Get-W11ReleaseLabel -Build $r.Build -Os $r.Os) (from $($r.Source))" -Vi 'Đã nhận diện hệ điều hành'
        }
    })
}

function Show-W11Gui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    try { [Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { $null = $_ }
    $script:H = @{}
    $script:PendingJob = $null; $script:TickFailed = $false
    $script:W11D.LogPath = Get-W11GuiLogPath

    $script:Sync = [hashtable]::Synchronized(@{
            LogQueue = [Collections.Queue]::Synchronized((New-Object Collections.Queue))
            Percent = 0; Status = ''; Cancel = $false; Result = $null; Error = $null
        })
    $script:W11D.Sync = $script:Sync
    $script:Job = $null
    $script:Catalog = @(Get-MsReleaseCatalog)
    $script:ReleaseItems = @()
    $cfg = Get-W11Config
    $script:Cfg = $cfg

    $ui = @{}
    $script:ui = $ui
    $f = New-Object Windows.Forms.Form
    $f.Text = "WinDebloat Tool $($script:W11D.Version) - tạo ISO Windows 10 / 11 gọn nhẹ"
    $f.ClientSize = New-Object Drawing.Size 980, 816
    $f.StartPosition = 'CenterScreen'
    $f.Font = New-Object Drawing.Font 'Segoe UI', 9
    $f.MinimumSize = New-Object Drawing.Size 1000, 856
    $ui.form = $f

    # ---------- 1. source ----------
    $g1 = New-W11Ctl GroupBox '1. Source ISO / Nguồn ISO' 10 8 960 166
    $ui.rbLocal = New-W11Ctl RadioButton 'Local ISO file / File ISO có sẵn trên máy' 12 20 400 22
    $ui.rbLocal.Checked = $true
    $lo = New-W11Ctl Label 'Target OS / Hệ điều hành:' 418 23 150 20
    $ui.cbOs = New-W11Ctl ComboBox '' 570 19 170 23
    $ui.cbOs.DropDownStyle = 'DropDownList'
    [void]$ui.cbOs.Items.Add('Auto (detect) / Tự nhận')
    [void]$ui.cbOs.Items.Add('Windows 11')
    [void]$ui.cbOs.Items.Add('Windows 10')
    $ui.lblOs = New-W11Ctl Label 'Detected / Nhận diện: -' 746 23 210 20
    $ui.lblOs.ForeColor = [Drawing.Color]::DimGray
    $ui.tbIso = New-W11Ctl TextBox '' 32 44 790 23
    $ui.btnIso = New-W11Ctl Button 'Browse... / Chọn...' 830 42 118 26
    $ui.rbDl = New-W11Ctl RadioButton 'Download official ISO from Microsoft / Tải ISO gốc từ Microsoft' 12 74 520 22
    $lr = New-W11Ctl Label 'Version / Bản:' 32 107 86 20
    $ui.cbRelease = New-W11Ctl ComboBox '' 120 104 330 23   # every Windows 11 + Windows 10 release Microsoft serves
    $ui.cbRelease.DropDownWidth = 420; $ui.cbRelease.MaxDropDownItems = 20
    $la = New-W11Ctl Label 'Arch:' 456 107 36 20
    $ui.cbArch = New-W11Ctl ComboBox '' 494 104 64 23
    $ll = New-W11Ctl Label 'Lang:' 564 107 38 20
    $ui.cbLang = New-W11Ctl ComboBox '' 604 104 150 23
    $ui.cbLang.DropDownWidth = 220
    foreach ($cb in @($ui.cbRelease, $ui.cbArch, $ui.cbLang)) { $cb.DropDownStyle = 'DropDownList' }
    $ui.btnFetch = New-W11Ctl Button 'Languages / Lấy ngôn ngữ' 760 102 150 27
    $ui.btnDownload = New-W11Ctl Button 'Download / Tải' 834 134 114 27
    $ui.chkAria2 = New-W11Ctl CheckBox 'Use aria2 (multi-connection) / Dùng aria2 (tải đa luồng)' 32 136 360 22
    $ui.lblAria2 = New-W11Ctl Label '' 396 139 432 20
    $ui.lblAria2.ForeColor = [Drawing.Color]::DimGray
    $script:Aria2Exe = $null
    try { $script:Aria2Exe = Find-MsAria2 } catch { $script:Aria2Exe = $null }
    if ($script:Aria2Exe) {
        $useA = $true; if ($cfg.Download -and $cfg.Download.ContainsKey('UseAria2')) { $useA = [bool]$cfg.Download.UseAria2 }
        $ui.chkAria2.Checked = $useA
        $ui.lblAria2.Text = 'aria2: ' + $script:Aria2Exe
    } else {
        $ui.chkAria2.Checked = $false; $ui.chkAria2.Enabled = $false
        $ui.lblAria2.Text = 'aria2c.exe not found - single connection / Không thấy aria2c.exe, tải một luồng'
    }
    $ui.lnkMs = New-W11Ctl LinkLabel 'Open Microsoft page / Mở trang Microsoft' 560 76 390 20
    $ui.lnkMs.TextAlign = 'MiddleRight'
    $g1.Controls.AddRange(@($lo, $ui.cbOs, $ui.lblOs, $ui.rbLocal, $ui.tbIso, $ui.btnIso, $ui.rbDl, $ui.btnFetch, $lr, $ui.cbRelease, $la, $ui.cbArch, $ll, $ui.cbLang, $ui.btnDownload, $ui.lnkMs, $ui.chkAria2, $ui.lblAria2))

    # ---------- 2. apps ----------
    $g2 = New-W11Ctl GroupBox '2. Apps to remove / App sẽ gỡ' 10 180 560 330
    $ui.grpApps = $g2
    $ui.clbApps = New-W11Ctl CheckedListBox '' 12 22 536 266
    $ui.clbApps.CheckOnClick = $true
    $script:AppIds = @()
    $ui.btnAppDef = New-W11Ctl Button 'Defaults / Mặc định' 12 294 140 27
    $ui.btnAppAll = New-W11Ctl Button 'All / Tất cả' 158 294 110 27
    $ui.btnAppNone = New-W11Ctl Button 'None / Bỏ hết' 274 294 110 27
    $note = New-W11Ctl Label 'Store, Defender, Edge, Calculator, Photos... always kept' 390 299 165 30
    $note.ForeColor = [Drawing.Color]::DimGray
    $note.Font = New-Object Drawing.Font 'Segoe UI', 7
    $g2.Controls.AddRange(@($ui.clbApps, $ui.btnAppDef, $ui.btnAppAll, $ui.btnAppNone, $note))

    # ---------- 3. options ----------
    $g3 = New-W11Ctl GroupBox '3. Options / Tuỳ chọn' 580 180 390 330
    $le = New-W11Ctl Label 'Editions / Phiên bản:' 12 22 140 20
    $ui.rbEdAll = New-W11Ctl RadioButton 'All / Tất cả' 12 42 100 22
    $ui.rbEdHP = New-W11Ctl RadioButton 'Home + Pro' 116 42 100 22
    $ui.rbEdCustom = New-W11Ctl RadioButton 'Index:' 220 42 62 22
    $ui.rbEdAll.Checked = $true
    $ui.tbIdx = New-W11Ctl TextBox '' 284 42 94 23
    $ui.btnEd = New-W11Ctl Button 'List editions in ISO / Xem phiên bản' 12 66 366 25
    $lt = New-W11Ctl Label 'Registry tweaks / Tinh chỉnh registry:' 12 96 300 18
    $ui.clbTweaks = New-W11Ctl CheckedListBox '' 12 115 366 128
    $ui.clbTweaks.CheckOnClick = $true
    $script:TweakIds = @()
    $ui.chkUnattend = New-W11Ctl CheckBox 'autounattend.xml: local account, skip MS-account screens (BypassNRO only for Win11) / tài khoản local' 12 246 370 34
    $ui.chkUnattend.Checked = $true
    $ui.chkCleanup = New-W11Ctl CheckBox 'Component cleanup (slow) / Dọn WinSxS (chậm)' 12 280 370 22
    $ui.chkDry = New-W11Ctl CheckBox 'Dry run (change nothing) / Chạy thử (không đổi gì)' 12 302 370 22
    $g3.Controls.AddRange(@($le, $ui.rbEdAll, $ui.rbEdHP, $ui.rbEdCustom, $ui.tbIdx, $ui.btnEd, $lt, $ui.clbTweaks, $ui.chkUnattend, $ui.chkCleanup, $ui.chkDry))

    # ---------- 4. output ----------
    $g4 = New-W11Ctl GroupBox '4. Output ISO / ISO đầu ra' 10 516 960 56
    $ui.tbOut = New-W11Ctl TextBox '' 12 22 810 23
    $ui.btnOut = New-W11Ctl Button 'Save as... / Lưu...' 830 20 118 26
    $g4.Controls.AddRange(@($ui.tbOut, $ui.btnOut))

    # ---------- actions / progress / log ----------
    $ui.btnCheck = New-W11Ctl Button 'System check / Kiểm tra máy' 10 580 180 32
    $ui.btnStart = New-W11Ctl Button 'START / BẮT ĐẦU' 196 580 150 32
    $ui.btnStart.Font = New-Object Drawing.Font 'Segoe UI', 9, ([Drawing.FontStyle]::Bold)
    $ui.btnCancel = New-W11Ctl Button 'Cancel / Huỷ' 352 580 110 32
    $ui.btnCancel.Enabled = $false
    $ui.pb = New-W11Ctl ProgressBar '' 470 584 500 24
    $ui.pb.Minimum = 0; $ui.pb.Maximum = 100
    $ui.lblStatus = New-W11Ctl Label 'Ready / Sẵn sàng' 10 618 760 20
    $ui.lnkLog = New-W11Ctl LinkLabel 'Open log folder / Mở thư mục log' 776 618 194 20
    $ui.lnkLog.TextAlign = 'MiddleRight'
    $ui.tbLog = New-W11Ctl TextBox '' 10 640 960 166
    $ui.tbLog.Multiline = $true; $ui.tbLog.ScrollBars = 'Both'; $ui.tbLog.ReadOnly = $true; $ui.tbLog.WordWrap = $false
    $ui.tbLog.MaxLength = 2147483647
    $ui.tbLog.Font = New-Object Drawing.Font 'Consolas', 8.5
    $ui.tbLog.Anchor = 'Top, Bottom, Left, Right'
    $f.Controls.AddRange(@($g1, $g2, $g3, $g4, $ui.btnCheck, $ui.btnStart, $ui.btnCancel, $ui.pb, $ui.lblStatus, $ui.lnkLog, $ui.tbLog))

    $script:DetectedOs = $null; $script:DetectedBuild = 0; $script:ShownOs = $null; $script:LastDlEntry = $null; $script:AutoDownload = $false
    $ui.cbOs.SelectedIndex = 0
    Set-W11ProfileLists -Force
    $script:H['cbOs.SelectedIndexChanged'] = { Set-W11ProfileLists }
    $ui.cbOs.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbOs.SelectedIndexChanged' })
    $script:H['lnkLog.LinkClicked'] = {
        $lp = $script:W11D.LogPath
        if ($lp -and (Test-Path -LiteralPath $lp)) { Start-Process 'explorer.exe' -ArgumentList ('/select,"' + $lp + '"') }
        else { Show-W11Msg 'No log file yet / Chưa có file log' | Out-Null }
    }
    $ui.lnkLog.Add_LinkClicked({ Invoke-W11Handler 'lnkLog.LinkClicked' })

    $script:BusyControls = @($ui.cbOs, $ui.btnIso, $ui.btnFetch, $ui.btnDownload, $ui.cbRelease, $ui.cbArch, $ui.chkAria2, $ui.btnEd, $ui.btnCheck, $ui.btnStart, $ui.btnOut, $ui.clbApps, $ui.clbTweaks)

    # ---------- events ----------
    $script:H['btnIso.Click'] = {
            $d = New-Object Windows.Forms.OpenFileDialog
            $d.Filter = 'Windows ISO (*.iso)|*.iso|All files (*.*)|*.*'
            $d.Title = 'Select the official Windows 10/11 ISO / Chọn file ISO Windows 10/11 gốc'
            if ($d.ShowDialog($script:ui.form) -eq 'OK') {
                $script:ui.tbIso.Text = $d.FileName
                $script:ui.rbLocal.Checked = $true
                if (-not $script:ui.tbOut.Text) { $script:ui.tbOut.Text = Get-W11SuggestedOutput $d.FileName }
                Start-W11Detect $d.FileName
            }
        }
    $ui.btnIso.Add_Click({ Invoke-W11Handler 'btnIso.Click' })
    $script:H['btnOut.Click'] = {
            $d = New-Object Windows.Forms.SaveFileDialog
            $d.Filter = 'ISO (*.iso)|*.iso'
            $d.FileName = 'Win11_debloated.iso'
            if ($script:ui.tbOut.Text) { $d.InitialDirectory = Split-Path -Parent $script:ui.tbOut.Text; $d.FileName = Split-Path -Leaf $script:ui.tbOut.Text }
            if ($d.ShowDialog($script:ui.form) -eq 'OK') { $script:ui.tbOut.Text = $d.FileName }
        }
    $ui.btnOut.Add_Click({ Invoke-W11Handler 'btnOut.Click' })
    $script:H['btnAppDef.Click'] = { for ($i = 0; $i -lt $script:ui.clbApps.Items.Count; $i++) { $script:ui.clbApps.SetItemChecked($i, [bool]$script:ProfileApps[$i].Default) } }
    $ui.btnAppDef.Add_Click({ Invoke-W11Handler 'btnAppDef.Click' })
    $script:H['btnAppAll.Click'] = { for ($i = 0; $i -lt $script:ui.clbApps.Items.Count; $i++) { $script:ui.clbApps.SetItemChecked($i, $true) } }
    $ui.btnAppAll.Add_Click({ Invoke-W11Handler 'btnAppAll.Click' })
    $script:H['btnAppNone.Click'] = { for ($i = 0; $i -lt $script:ui.clbApps.Items.Count; $i++) { $script:ui.clbApps.SetItemChecked($i, $false) } }
    $ui.btnAppNone.Add_Click({ Invoke-W11Handler 'btnAppNone.Click' })
    $script:H['tbIdx.TextChanged'] = { if ($script:ui.tbIdx.Text) { $script:ui.rbEdCustom.Checked = $true } }
    $ui.tbIdx.Add_TextChanged({ Invoke-W11Handler 'tbIdx.TextChanged' })

    $script:H['lnkMs.LinkClicked'] = {
            $e = Get-W11SelectedEntry
            if ($e) { $url = $e.PageUrl }
            elseif ((Get-W11EffectiveOs) -eq 'Win10') { $url = $script:MsDl.Pages['Win10'] }
            else { $url = $script:MsDl.Pages['Win11'] }
            Start-Process $url
            Write-W11Log -En 'Opened the official Microsoft page. After the download finishes, choose the ISO with Browse.' -Vi 'Đã mở trang Microsoft. Tải xong hãy bấm "Chọn..." để chọn file ISO.'
        }
    $ui.lnkMs.Add_LinkClicked({ Invoke-W11Handler 'lnkMs.LinkClicked' })

    $script:H['btnFetch.Click'] = {
            # languages (and SHA256 table) of the selected release only - one quick API call
            $e = Get-W11SelectedEntry
            if (-not $e) { return }
            $script:ui.rbDl.Checked = $true
            if ($e.Available -eq $false) { Show-W11NotOffered $e; return }
            $script:ui.lblStatus.Text = "Loading languages for $($e.Release)... / Đang lấy danh sách ngôn ngữ..."
            [void](Start-W11Job -Name 'Load languages' -Script '$sync.Result = Update-MsEntryLanguages -Entry $JobArgs.Entry' -JobArgs @{ Entry = $e } -OnDone {
                    $r = $script:Sync.Result
                    if (-not $r) { $script:ui.lblStatus.Text = 'Could not load languages - see the log / Không lấy được ngôn ngữ - xem log'; return }
                    Set-MsEntryLanguages -Catalog $script:Catalog -Result $r
                    Update-W11DownloadLists 'release'
                    if ($r.Ok) {
                        $script:ui.lblStatus.Text = "$(@($r.Skus).Count) languages loaded / Đã lấy $(@($r.Skus).Count) ngôn ngữ"
                        if (@($r.Hashes.Keys).Count -eq 0) { Write-W11Log -Level WARN -En 'Microsoft does not publish SHA256 values for this older release; the ISO hash will be logged so you can compare it yourself.' -Vi 'Microsoft không công bố SHA256 cho bản cũ này; mã SHA256 của ISO sẽ được ghi vào log để anh tự đối chiếu.' }
                        if ($script:AutoDownload) { $script:AutoDownload = $false; & $script:H['btnDownload.Click'] }
                        return
                    }
                    $script:AutoDownload = $false
                    if ($r.NotOffered) { Show-W11NotOffered (Get-W11SelectedEntry); return }
                    $script:ui.lblStatus.Text = 'Could not load languages - see the log / Không lấy được ngôn ngữ - xem log'
                    $logTxt = ''; if ($script:W11D.LogPath) { $logTxt = "`n`nLog / Nhật ký: $($script:W11D.LogPath)" }
                    $ans = Show-W11Msg ("Microsoft did not return the language list:`n$($r.Error)`n`nIf the error mentions vlscppe.microsoft.com or ov-df.microsoft.com, your DNS / ad blocker / hosts file blocks them: switch DNS to 1.1.1.1 or 8.8.8.8 and try again. Microsoft also rejects requests for a while after many tries in a row; waiting a few minutes usually helps.`n`nKhông lấy được danh sách ngôn ngữ. Nếu lỗi nhắc tới vlscppe.microsoft.com hoặc ov-df.microsoft.com thì DNS / trình chặn quảng cáo / file hosts đang chặn hai tên miền này: hãy đổi DNS sang 1.1.1.1 hoặc 8.8.8.8 rồi thử lại. Microsoft cũng tạm từ chối khi bị hỏi nhiều lần liên tiếp, đợi vài phút là được.`n`nOpen the Microsoft page now? / Mở trang Microsoft ngay?$logTxt") 'Warning' 'YesNo'
                    if ([string]$ans -eq 'Yes') { & $script:H['lnkMs.LinkClicked'] }
                })
        }
    $ui.btnFetch.Add_Click({ Invoke-W11Handler 'btnFetch.Click' })
    $script:H['cbRelease.SelectedIndexChanged'] = { Update-W11DownloadLists 'arch' }
    $ui.cbRelease.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbRelease.SelectedIndexChanged' })
    $script:H['cbArch.SelectedIndexChanged'] = { Update-W11DownloadLists 'lang' }
    $ui.cbArch.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbArch.SelectedIndexChanged' })

    $script:H['btnDownload.Click'] = {
            $e = Get-W11SelectedEntry
            if (-not $e) { return }
            if ($e.Available -eq $false) { Show-W11NotOffered $e; return }
            if ($e.Static -or @($e.Skus).Count -eq 0) {
                # languages not loaded yet: load them, then come back here
                $script:AutoDownload = $true
                & $script:H['btnFetch.Click']
                return
            }
            if ($script:ui.cbLang.SelectedIndex -lt 0) { Show-W11Msg 'Choose a language / Hãy chọn ngôn ngữ' 'Warning' | Out-Null; return }
            $sku = $e.Skus[$script:ui.cbLang.SelectedIndex]
            $d = New-Object Windows.Forms.FolderBrowserDialog
            $d.Description = 'Folder to save the ISO (~8 GB) / Thư mục lưu ISO (~8 GB)'
            if ($d.ShowDialog($script:ui.form) -ne 'OK') { return }
            try { $free = Get-W11FreeGB -Path $d.SelectedPath } catch { $free = 999 }
            if ($free -lt 9) { Show-W11Msg "Only $free GB free there / Chỉ còn $free GB trống" 'Warning' | Out-Null; return }
            $script:ui.rbDl.Checked = $true
            $script:LastDlEntry = $e
            $script:ui.lblStatus.Text = 'Requesting the download link... / Đang lấy link tải...'
            $opts = Get-MsAria2Options -Config $script:Cfg -Override @{ UseAria2 = [bool]($script:ui.chkAria2.Enabled -and $script:ui.chkAria2.Checked) }
            [void](Start-W11Job -Name 'Download' -Script '$sync.Result = Invoke-MsIsoDownload -Entry $JobArgs.Entry -Sku $JobArgs.Sku -Folder $JobArgs.Folder -Options $JobArgs.Options -Sync $sync' -JobArgs @{ Entry = $e; Sku = $sku; Folder = $d.SelectedPath; Options = $opts } -OnDone {
                if ($script:Sync.Error) {
                    $script:ui.lblStatus.Text = 'Download failed - see the log / Tải thất bại - xem log'
                    $ans = Show-W11Msg ("Download failed / Tải thất bại:`n$($script:Sync.Error)`n`nOpen the Microsoft page to download in the browser? / Mở trang Microsoft để tải bằng trình duyệt?") 'Error' 'YesNo'
                    if ([string]$ans -eq 'Yes') { & $script:H['lnkMs.LinkClicked'] }
                    return
                }
                $iso = [string]$script:Sync.Result
                $script:ui.tbIso.Text = $iso
                $script:ui.rbLocal.Checked = $true
                if (-not $script:ui.tbOut.Text) { $script:ui.tbOut.Text = Get-W11SuggestedOutput $iso }
                if ($script:LastDlEntry) { Set-W11Detected -Os $script:LastDlEntry.Os -Source 'download' -Build $script:LastDlEntry.Build; Start-W11Detect $iso }
                $script:ui.lblStatus.Text = 'Download complete / Tải xong'
            })
        }
    $ui.btnDownload.Add_Click({ Invoke-W11Handler 'btnDownload.Click' })

    $script:H['btnEd.Click'] = {
            if (-not (Test-Path -LiteralPath $script:ui.tbIso.Text)) { Show-W11Msg 'Choose an ISO first / Hãy chọn ISO trước' 'Warning' | Out-Null; return }
            [void](Start-W11Job -Name 'List editions' -Script '$sync.Result = @(Get-W11IsoEditions -IsoPath $JobArgs.Iso)' -JobArgs @{ Iso = $script:ui.tbIso.Text } -OnDone { $script:ui.lblStatus.Text = 'Editions listed in the log / Danh sách phiên bản ở khung log' })
        }
    $ui.btnEd.Add_Click({ Invoke-W11Handler 'btnEd.Click' })

    $script:H['btnCheck.Click'] = {
            $wp = $env:TEMP
            if ($script:ui.tbOut.Text) { $wp = Split-Path -Parent $script:ui.tbOut.Text }
            [void](Start-W11Job -Name 'System check' -Script '$null = Get-W11Capabilities -WorkPath $JobArgs.Work' -JobArgs @{ Work = $wp } -OnDone { $script:ui.lblStatus.Text = 'System check done (see log) / Đã kiểm tra máy (xem log)' })
        }
    $ui.btnCheck.Add_Click({ Invoke-W11Handler 'btnCheck.Click' })

    $script:H['btnCancel.Click'] = {
            $script:Sync.Cancel = $true
            Write-W11Log -Level WARN -En 'Cancel requested - downloads stop at once; ISO builds stop after the current step (DISM steps cannot be interrupted).' -Vi 'Đã yêu cầu huỷ - việc tải dừng ngay, còn tạo ISO sẽ dừng sau bước hiện tại.'
        }
    $ui.btnCancel.Add_Click({ Invoke-W11Handler 'btnCancel.Click' })

    $script:StartRun = {
        $ui = $script:ui
        $iso = $ui.tbIso.Text.Trim('"', ' ')
        $out = $ui.tbOut.Text.Trim('"', ' ')
        if (-not $iso -or -not (Test-Path -LiteralPath $iso)) { Show-W11Msg 'Choose a valid source ISO / Hãy chọn file ISO nguồn hợp lệ' 'Warning' | Out-Null; return }
        if (-not $out) { $out = Get-W11SuggestedOutput $iso; $ui.tbOut.Text = $out }
        $mode = 'All'; $idx = @()
        if ($ui.rbEdHP.Checked) { $mode = 'HomePro' }
        if ($ui.rbEdCustom.Checked) {
            $mode = 'Custom'
            foreach ($p in ($ui.tbIdx.Text -split '[,; ]+')) { if ($p -match '^\d+$') { $idx += [int]$p } }
            if ($idx.Count -eq 0) { Show-W11Msg 'Enter index numbers, e.g. 1,6 / Nhập số index, ví dụ 1,6' 'Warning' | Out-Null; return }
        }
        $apps = @(); foreach ($i in $ui.clbApps.CheckedIndices) { $apps += $script:AppIds[$i] }
        $tw = @(); foreach ($i in $ui.clbTweaks.CheckedIndices) { $tw += $script:TweakIds[$i] }
        $targetOs = Get-W11EffectiveOs
        $osNote = Get-W11OsLabel $targetOs
        $useDefaults = ($ui.cbOs.SelectedIndex -eq 0 -and -not $script:DetectedOs)
        if ($useDefaults) { $targetOs = 'Auto'; $osNote = 'Auto: detected from the image at start, default lists of that OS / tự nhận khi chạy, dùng danh sách mặc định' }
        $dry = $ui.chkDry.Checked
        if (-not $dry -and -not (Find-W11Oscdimg)) {
            if ((Get-W11OsBuild) -ge 10240) {
                $ans = Show-W11Msg ("oscdimg.exe (Windows ADK) is required to build the ISO.`nYes = download the official ADK installer from Microsoft and install only 'Deployment Tools'`nNo = install via winget (Microsoft.WindowsADK)`nCancel = stop`n`nCần oscdimg.exe (Windows ADK) để tạo ISO.`nYes = tải bộ cài ADK chính thức và chỉ cài 'Deployment Tools'`nNo = cài qua winget`nCancel = dừng") 'Question' 'YesNoCancel'
                if ([string]$ans -eq 'Cancel') { return }
                $m = 'AdkSetup'; if ([string]$ans -eq 'No') { $m = 'Winget' }
                [void](Start-W11Job -Name 'Install ADK' -Script '$null = Install-W11Oscdimg -Method $JobArgs.Method' -JobArgs @{ Method = $m } -OnDone {
                        if ($script:Sync.Error) { Show-W11Msg ("ADK install failed / Cài ADK lỗi:`n$($script:Sync.Error)") 'Error' | Out-Null } else { & $script:StartRun }
                    })
                return
            }
            Show-W11Msg ("oscdimg.exe not found. The current Windows ADK cannot be installed on Windows 7/8.x.`nCopy oscdimg.exe from a Windows 10/11 PC with ADK (Deployment Tools\amd64\Oscdimg) into:`n$(Join-Path $script:W11Root 'tools')`n`nKhông có oscdimg.exe. ADK mới không cài được trên Win7/8. Hãy chép oscdimg.exe từ máy Win10/11 có ADK vào thư mục tools.") 'Warning' | Out-Null
            return
        }
        $summary = "Source: $iso`nOutput: $out`nTarget OS: $osNote`nEditions: $mode $($idx -join ',')`nApps: $($apps.Count)  Tweaks: $($tw.Count)`nautounattend: $($ui.chkUnattend.Checked)  Cleanup: $($ui.chkCleanup.Checked)  Dry run: $dry`n`nNeeds ~25 GB free and 20-60 minutes. Continue? / Cần ~25 GB trống, 20-60 phút. Tiếp tục?"
        if ([string](Show-W11Msg $summary 'Question' 'YesNo') -ne 'Yes') { return }
        $ui.tbLog.Clear()
        $jobArgs = @{
            IsoPath = $iso; OutputIso = $out; EditionMode = $mode; Indexes = $idx; TargetOs = $targetOs
            Autounattend = $ui.chkUnattend.Checked; ComponentCleanup = $ui.chkCleanup.Checked; DryRun = $dry
        }
        if (-not $useDefaults) { $jobArgs.RemoveApps = $apps; $jobArgs.Tweaks = $tw }
        [void](Start-W11Job -Name 'Build ISO' -Script '$sync.Result = Invoke-Win11Debloat @JobArgs -Sync $sync' -JobArgs $jobArgs -OnDone {
            $r = $script:Sync.Result
            if ($script:Sync.Error) {
                Show-W11Msg ("FAILED / THẤT BẠI:`n$($script:Sync.Error)`n`nSee the log file next to the output ISO. / Xem file log cạnh ISO đầu ra.") 'Error' | Out-Null
            } elseif ($r -and $r.DryRun) {
                Show-W11Msg 'Dry run finished - see the log. / Chạy thử xong - xem log.' | Out-Null
            } elseif ($r) {
                Show-W11Msg ("Done! / Xong!`n$($r.OutputIso)`nSHA256: $($r.Sha256)`n`nWrite it to USB with Rufus or Ventoy. / Ghi ra USB bằng Rufus hoặc Ventoy.") | Out-Null
            }
        })
    }
    $script:H['btnStart.Click'] = { & $script:StartRun }
    $ui.btnStart.Add_Click({ Invoke-W11Handler 'btnStart.Click' })

    $f.Add_FormClosing({
            param($s, $e)
            if ($script:Job) {
                Show-W11Msg 'A job is still running. Press Cancel and wait for it to stop first. / Đang chạy, hãy bấm Huỷ và chờ dừng hẳn.' 'Warning' | Out-Null
                $e.Cancel = $true
            }
        })

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 300
    $timer.Add_Tick({ Invoke-W11Tick })
    $timer.Start()

    $script:H['form.Shown'] = {
        Update-W11DownloadLists 'release'   # full release list; languages are loaded per release on demand
        Write-W11Log -En 'Welcome. 1) pick or download a Windows 10/11 ISO  2) check target OS, apps, options  3) START.' -Vi 'Xin chào. 1) chọn hoặc tải ISO Windows 10/11  2) kiểm tra hệ điều hành, app, tuỳ chọn  3) BẮT ĐẦU.'
        if ($script:W11D.LogPath) { Write-W11Log -En "Log file: $($script:W11D.LogPath)" -Vi 'File nhật ký (gửi file này khi cần hỗ trợ)' }
        Write-W11Log -En ("WinDebloat Tool $($script:W11D.Version) | Host: Windows build $(Get-W11OsBuild), PowerShell $($PSVersionTable.PSVersion), CLR $($PSVersionTable.CLRVersion)")
        [void](Start-W11Job -Background -Name 'System check' -Script '$null = Get-W11Capabilities -WorkPath $JobArgs.Work' -JobArgs @{ Work = $env:TEMP })
    }
    $f.Add_Shown({ Invoke-W11Handler 'form.Shown' })
    [void]$f.ShowDialog()
    $timer.Stop()
}

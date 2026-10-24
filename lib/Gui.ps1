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

function Update-W11DownloadLists {
    param([string]$Level)
    $cat = @($script:Catalog)
    if ($cat.Count -eq 0) { return }
    $ui = $script:ui
    if ($Level -eq 'release') {
        $ui.cbRelease.Items.Clear()
        foreach ($r in @($cat | ForEach-Object { $_.Release } | Select-Object -Unique)) { [void]$ui.cbRelease.Items.Add($r) }
        if ($ui.cbRelease.Items.Count -gt 0) { $ui.cbRelease.SelectedIndex = 0 }   # triggers 'arch'
        return
    }
    if ($Level -eq 'arch') {
        $ui.cbArch.Items.Clear()
        $rel = [string]$ui.cbRelease.SelectedItem
        foreach ($a in @($cat | Where-Object { $_.Release -eq $rel } | ForEach-Object { $_.Arch } | Select-Object -Unique)) { [void]$ui.cbArch.Items.Add($a) }
        if ($ui.cbArch.Items.Count -gt 0) {
            $idx = $ui.cbArch.Items.IndexOf(((Get-W11HostArch) -replace 'amd64', 'x64'))
            if ($idx -lt 0) { $idx = 0 }
            $ui.cbArch.SelectedIndex = $idx                                         # triggers 'lang'
        }
        return
    }
    if ($Level -eq 'lang') {
        $ui.cbLang.Items.Clear()
        $e = Get-W11SelectedEntry
        if (-not $e) { return }
        if ($e.Static -or @($e.Skus).Count -eq 0) {
            [void]$ui.cbLang.Items.Add('(Load list first / bấm Lấy danh sách)')
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

function Get-W11SelectedEntry {
    $rel = [string]$script:ui.cbRelease.SelectedItem
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
    # (Re)fills the app and tweak lists for the effective target OS; keeps nothing from the other profile.
    param([switch]$Force)
    $os = Get-W11EffectiveOs
    if (-not $Force -and $script:ShownOs -eq $os) { return }
    $script:ShownOs = $os
    $prof = Get-W11Profile -Config $script:Cfg -Os $os
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
    $ui.grpApps.Text = ('2. Apps to remove / App sẽ gỡ  -  {0}' -f (Get-W11OsLabel $os))
}

function Set-W11Detected {
    param([string]$Os, [string]$Source, [int]$Build = 0)
    $script:DetectedOs = $Os
    $txt = 'Detected / Nhận diện: '
    if ($Os) {
        $txt += (Get-W11OsLabel $Os)
        if ($Build -gt 0) { $txt += " (build $Build)" }
        $txt += " [$Source]"
    } else { $txt += 'unknown - choose manually / chưa rõ, hãy chọn tay' }
    $script:ui.lblOs.Text = $txt
    Set-W11ProfileLists
}

function Start-W11Detect {
    # quick guess from the file name, then (Win8+) read the WIM header inside the ISO in the background
    param([string]$Iso)
    $g = Get-W11OsFromName $Iso
    Set-W11Detected -Os $g -Source 'filename'
    if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) { return }
    [void](Start-W11Job -Background -Name 'OS detection' -Script '$sync.Result = Get-W11IsoOsInfo -IsoPath $JobArgs.Iso' -JobArgs @{ Iso = $Iso } -OnDone {
        $r = $script:Sync.Result
        if ($r -and $r.Os) {
            Set-W11Detected -Os $r.Os -Source $r.Source -Build $r.Build
            Write-W11Log -Level OK -En "Target OS detected: $(Get-W11OsLabel $r.Os) (build $($r.Build), from $($r.Source))" -Vi 'Đã nhận diện hệ điều hành'
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
    $script:Catalog = @(Get-MsStaticCatalog)
    $cfg = Get-W11Config
    $script:Cfg = $cfg

    $ui = @{}
    $script:ui = $ui
    $f = New-Object Windows.Forms.Form
    $f.Text = "WinDebloat Tool $($script:W11D.Version) - tạo ISO Windows 10 / 11 gọn nhẹ"
    $f.ClientSize = New-Object Drawing.Size 980, 790
    $f.StartPosition = 'CenterScreen'
    $f.Font = New-Object Drawing.Font 'Segoe UI', 9
    $f.MinimumSize = New-Object Drawing.Size 1000, 830
    $ui.form = $f

    # ---------- 1. source ----------
    $g1 = New-W11Ctl GroupBox '1. Source ISO / Nguồn ISO' 10 8 960 140
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
    $ui.btnFetch = New-W11Ctl Button 'Load list / Lấy danh sách' 32 102 150 27
    $lr = New-W11Ctl Label 'Version:' 190 107 52 20
    $ui.cbRelease = New-W11Ctl ComboBox '' 244 104 250 23   # Windows 11 + Windows 10 releases
    $la = New-W11Ctl Label 'Arch:' 500 107 36 20
    $ui.cbArch = New-W11Ctl ComboBox '' 538 104 70 23
    $ll = New-W11Ctl Label 'Language:' 614 107 62 20
    $ui.cbLang = New-W11Ctl ComboBox '' 678 104 150 23
    foreach ($cb in @($ui.cbRelease, $ui.cbArch, $ui.cbLang)) { $cb.DropDownStyle = 'DropDownList' }
    $ui.btnDownload = New-W11Ctl Button 'Download / Tải' 834 102 114 27
    $ui.lnkMs = New-W11Ctl LinkLabel 'Open Microsoft page / Mở trang Microsoft' 560 76 390 20
    $ui.lnkMs.TextAlign = 'MiddleRight'
    $g1.Controls.AddRange(@($lo, $ui.cbOs, $ui.lblOs, $ui.rbLocal, $ui.tbIso, $ui.btnIso, $ui.rbDl, $ui.btnFetch, $lr, $ui.cbRelease, $la, $ui.cbArch, $ll, $ui.cbLang, $ui.btnDownload, $ui.lnkMs))

    # ---------- 2. apps ----------
    $g2 = New-W11Ctl GroupBox '2. Apps to remove / App sẽ gỡ' 10 154 560 330
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
    $g3 = New-W11Ctl GroupBox '3. Options / Tuỳ chọn' 580 154 390 330
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
    $g4 = New-W11Ctl GroupBox '4. Output ISO / ISO đầu ra' 10 490 960 56
    $ui.tbOut = New-W11Ctl TextBox '' 12 22 810 23
    $ui.btnOut = New-W11Ctl Button 'Save as... / Lưu...' 830 20 118 26
    $g4.Controls.AddRange(@($ui.tbOut, $ui.btnOut))

    # ---------- actions / progress / log ----------
    $ui.btnCheck = New-W11Ctl Button 'System check / Kiểm tra máy' 10 554 180 32
    $ui.btnStart = New-W11Ctl Button 'START / BẮT ĐẦU' 196 554 150 32
    $ui.btnStart.Font = New-Object Drawing.Font 'Segoe UI', 9, ([Drawing.FontStyle]::Bold)
    $ui.btnCancel = New-W11Ctl Button 'Cancel / Huỷ' 352 554 110 32
    $ui.btnCancel.Enabled = $false
    $ui.pb = New-W11Ctl ProgressBar '' 470 558 500 24
    $ui.pb.Minimum = 0; $ui.pb.Maximum = 100
    $ui.lblStatus = New-W11Ctl Label 'Ready / Sẵn sàng' 10 592 760 20
    $ui.lnkLog = New-W11Ctl LinkLabel 'Open log folder / Mở thư mục log' 776 592 194 20
    $ui.lnkLog.TextAlign = 'MiddleRight'
    $ui.tbLog = New-W11Ctl TextBox '' 10 614 960 166
    $ui.tbLog.Multiline = $true; $ui.tbLog.ScrollBars = 'Both'; $ui.tbLog.ReadOnly = $true; $ui.tbLog.WordWrap = $false
    $ui.tbLog.MaxLength = 2147483647
    $ui.tbLog.Font = New-Object Drawing.Font 'Consolas', 8.5
    $ui.tbLog.Anchor = 'Top, Bottom, Left, Right'
    $f.Controls.AddRange(@($g1, $g2, $g3, $g4, $ui.btnCheck, $ui.btnStart, $ui.btnCancel, $ui.pb, $ui.lblStatus, $ui.lnkLog, $ui.tbLog))

    $script:DetectedOs = $null; $script:ShownOs = $null; $script:LastDlEntry = $null
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

    $script:BusyControls = @($ui.cbOs, $ui.btnIso, $ui.btnFetch, $ui.btnDownload, $ui.btnEd, $ui.btnCheck, $ui.btnStart, $ui.btnOut, $ui.clbApps, $ui.clbTweaks)

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
            $script:ui.rbDl.Checked = $true
            $script:ui.lblStatus.Text = 'Loading the list from Microsoft (up to ~1 min)... / Đang lấy danh sách từ Microsoft (tối đa khoảng 1 phút)...'
            Write-W11Log -Level STEP -En 'Asking Microsoft for available Windows 11 / Windows 10 releases and languages...' -Vi 'Đang hỏi Microsoft danh sách Windows 11 / 10 và ngôn ngữ...'
            [void](Start-W11Job -Name 'Load list' -Script '$sync.Result = Get-MsCatalogForGui' -OnDone {
                    $r = $script:Sync.Result
                    $entries = @(); $live = 0; $err = $script:Sync.Error
                    if ($r) { $entries = @($r.Entries); $live = [int]$r.Live; if ($r.Error) { $err = $r.Error } }
                    if ($entries.Count -eq 0) { $entries = @(Get-MsStaticCatalog) }
                    $script:Catalog = $entries
                    Update-W11DownloadLists 'release'
                    $offer = (@($entries | Where-Object { -not $_.Static } | ForEach-Object { "$($_.Release) [$($_.Arch)]" }) -join ', ')
                    if ($live -gt 0) {
                        Write-W11Log -Level OK -En "Microsoft offers: $offer" -Vi 'Microsoft đang cung cấp các bản trên'
                        $script:ui.lblStatus.Text = "List loaded: $live entries / Đã lấy danh sách: $live mục"
                        $miss = @($entries | Where-Object { $_.Static })
                        if ($miss.Count -gt 0) { Write-W11Log -Level WARN -En ('Not available right now (official page only): ' + (($miss | ForEach-Object { "$($_.Release) [$($_.Arch)]" }) -join ', ')) -Vi 'Một số bản chưa lấy được, chỉ mở được trang Microsoft' }
                    } else {
                        $script:ui.lblStatus.Text = 'Could not load the list - see the log / Không lấy được danh sách - xem log'
                        $logTxt = ''; if ($script:W11D.LogPath) { $logTxt = "`n`nLog / Nhật ký: $($script:W11D.LogPath)" }
                        $ans = Show-W11Msg ("Microsoft did not return the list:`n$err`n`nIf the error mentions vlscppe.microsoft.com or ov-df.microsoft.com, those hosts are blocked by your DNS / ad blocker / hosts file: switch DNS to 1.1.1.1 or 8.8.8.8 and try again.`nYou can still choose the version below and press Download to open the official Microsoft page.`n`nKhông lấy được danh sách từ Microsoft. Nếu lỗi nhắc tới vlscppe.microsoft.com hoặc ov-df.microsoft.com thì DNS / trình chặn quảng cáo / file hosts đang chặn hai tên miền này: hãy đổi DNS sang 1.1.1.1 hoặc 8.8.8.8 rồi thử lại.`nAnh vẫn có thể chọn phiên bản bên dưới và bấm Tải để mở trang tải chính thức của Microsoft.`n`nOpen the Microsoft page now? / Mở trang Microsoft ngay?$logTxt") 'Warning' 'YesNo'
                        if ([string]$ans -eq 'Yes') { & $script:H['lnkMs.LinkClicked'] }
                    }
                })
        }
    $ui.btnFetch.Add_Click({ Invoke-W11Handler 'btnFetch.Click' })
    $script:H['cbRelease.SelectedIndexChanged'] = { Update-W11DownloadLists 'arch' }
    $ui.cbRelease.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbRelease.SelectedIndexChanged' })
    $script:H['cbArch.SelectedIndexChanged'] = { Update-W11DownloadLists 'lang' }
    $ui.cbArch.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbArch.SelectedIndexChanged' })

    $script:H['btnDownload.Click'] = {
            $e = Get-W11SelectedEntry
            if ($e -and ($e.Static -or @($e.Skus).Count -eq 0)) {
                $ans = Show-W11Msg ("The language list for $($e.Release) [$($e.Arch)] has not been loaded from Microsoft.`nYes = open the official Microsoft download page in the browser`nNo = try 'Load list' again`n`nChưa lấy được danh sách ngôn ngữ cho bản này.`nYes = mở trang tải chính thức của Microsoft`nNo = thử lại 'Lấy danh sách'") 'Question' 'YesNoCancel'
                if ([string]$ans -eq 'Yes') { & $script:H['lnkMs.LinkClicked'] } elseif ([string]$ans -eq 'No') { & $script:H['btnFetch.Click'] }
                return
            }
            if (-not $e -or $script:ui.cbLang.SelectedIndex -lt 0) { Show-W11Msg 'Click "Load list" first / Hãy bấm "Lấy danh sách" trước' 'Warning' | Out-Null; return }
            $sku = $e.Skus[$script:ui.cbLang.SelectedIndex]
            $d = New-Object Windows.Forms.FolderBrowserDialog
            $d.Description = 'Folder to save the ISO (~8 GB) / Thư mục lưu ISO (~8 GB)'
            if ($d.ShowDialog($script:ui.form) -ne 'OK') { return }
            try { $free = Get-W11FreeGB -Path $d.SelectedPath } catch { $free = 999 }
            if ($free -lt 9) { Show-W11Msg "Only $free GB free there / Chỉ còn $free GB trống" 'Warning' | Out-Null; return }
            $script:ui.rbDl.Checked = $true
            $script:LastDlEntry = $e
            $script:ui.lblStatus.Text = 'Requesting the download link... / Đang lấy link tải...'
            [void](Start-W11Job -Name 'Download' -Script '$sync.Result = Invoke-MsIsoDownload -Entry $JobArgs.Entry -Sku $JobArgs.Sku -Folder $JobArgs.Folder -Sync $sync' -JobArgs @{ Entry = $e; Sku = $sku; Folder = $d.SelectedPath } -OnDone {
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
                if ($script:LastDlEntry) { Set-W11Detected -Os $script:LastDlEntry.Os -Source 'download' }
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
            Write-W11Log -Level WARN -En 'Cancel requested - stopping after the current step (DISM steps cannot be interrupted).' -Vi 'Đã yêu cầu huỷ - sẽ dừng sau bước hiện tại.'
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
        Update-W11DownloadLists 'release'   # static version/arch list until 'Load list' succeeds
        Write-W11Log -En 'Welcome. 1) pick or download a Windows 10/11 ISO  2) check target OS, apps, options  3) START.' -Vi 'Xin chào. 1) chọn hoặc tải ISO Windows 10/11  2) kiểm tra hệ điều hành, app, tuỳ chọn  3) BẮT ĐẦU.'
        if ($script:W11D.LogPath) { Write-W11Log -En "Log file: $($script:W11D.LogPath)" -Vi 'File nhật ký (gửi file này khi cần hỗ trợ)' }
        Write-W11Log -En ("WinDebloat Tool $($script:W11D.Version) | Host: Windows build $(Get-W11OsBuild), PowerShell $($PSVersionTable.PSVersion), CLR $($PSVersionTable.CLRVersion)")
        [void](Start-W11Job -Background -Name 'System check' -Script '$null = Get-W11Capabilities -WorkPath $JobArgs.Work' -JobArgs @{ Work = $env:TEMP })
    }
    $f.Add_Shown({ Invoke-W11Handler 'form.Shown' })
    [void]$f.ShowDialog()
    $timer.Stop()
}

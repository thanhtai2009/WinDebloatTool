<#
    WinDebloat Tool - Windows Forms GUI (PowerShell 2.0+ / .NET 3.5+ compatible).
    Long work runs in a background runspace; a timer pumps log lines and progress into the UI.
    SPDX-License-Identifier: MIT
#>

# watermark at the bottom of the main window: same text in every language (never translated)
$script:W11Watermark = 'Designed by TaiNT13@PNC STG'

function Get-W11TextWidth {
    # width in pixels of one line of text in a font (.NET 2.0 TextRenderer)
    param([string]$Text, $Font)
    if (-not $Text) { return 0 }
    return [Windows.Forms.TextRenderer]::MeasureText($Text, $Font).Width
}

function Get-W11TextHeight {
    # height in pixels of word-wrapped text in a given width
    param([string]$Text, $Font, [int]$Width)
    if ($Width -lt 20) { $Width = 20 }
    $flags = [Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::TextBoxControl
    $sz = New-Object Drawing.Size $Width, 10000
    return [Windows.Forms.TextRenderer]::MeasureText([string]$Text, $Font, $sz, $flags).Height
}

function Set-W11ListExtent {
    # horizontal scroll range of a checked list = its widest item (+ check box), so long entries are never cut
    param($List)
    $max = 0
    foreach ($it in $List.Items) { $w = Get-W11TextWidth ([string]$it) $List.Font; if ($w -gt $max) { $max = $w } }
    $List.HorizontalExtent = $max + [int](28 * $script:LayoutScale)
}

function Set-W11Layout {
    # Places every control from the current client size (PS 2.0 / .NET 2.0: no TableLayoutPanel tricks needed):
    # sections 1 and 4, path boxes, progress bar and log stretch horizontally; sections 2 and 3 share the width
    # (58/42) and, with the log, grow vertically; widths of labels / buttons / check boxes come from the text in
    # the current language and font, so nothing is clipped. Sizes scale with the DPI the process sees.
    $ui = $script:ui
    if (-not $ui -or -not $ui.form -or -not $ui.tbLog) { return }
    $f = $ui.form
    $cw = $f.ClientSize.Width; $ch = $f.ClientSize.Height
    if ($cw -lt 300 -or $ch -lt 300) { return }   # minimized
    if (-not $script:LayoutScale) {
        $s = 1.0
        try { $g = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $s = [double]$g.DpiX / 96.0; $g.Dispose() } catch { $s = 1.0 }
        if ($s -lt 1) { $s = 1.0 }
        $script:LayoutScale = $s
    }
    $s = [double]$script:LayoutScale
    $px = { param([double]$v) [int][Math]::Round($v * $s) }
    $tw = { param($c) (Get-W11TextWidth $c.Text $c.Font) }
    $M = & $px 10; $gap = & $px 8; $in = & $px 12; $bh = & $px 27
    $gt = [Math]::Max((& $px 20), $f.Font.Height + (& $px 5))   # first row inside a group box, below its title
    $rowH = [Math]::Max((& $px 23), $f.Font.Height + (& $px 8))
    $btnW = { param($c, [int]$min) [Math]::Max((& $px $min), (& $tw $c) + (& $px 24)) }
    $chkW = { param($c) (& $tw $c) + (& $px 24) }
    $lblW = { param($c) (& $tw $c) + (& $px 4) }

    $f.SuspendLayout()
    try {
        $gw = $cw - 2 * $M
        # ---------- 1. source ----------
        $g1 = $ui.grpSource
        $y1 = $gt; $y2 = $y1 + $rowH + (& $px 2); $y3 = $y2 + $rowH + (& $px 6); $y4 = $y3 + $rowH + (& $px 6); $y5 = $y4 + $rowH + (& $px 6)
        $g1H = $y5 + $rowH + (& $px 10)
        $g1.SetBounds($M, (& $px 8), $gw, $g1H)
        $r = $gw - $in
        $ui.rbLocal.SetBounds($in, $y1, (& $chkW $ui.rbLocal), $rowH)
        $x = $ui.rbLocal.Right + (& $px 16)
        $w = & $lblW $ui.lblTargetOs
        $ui.lblTargetOs.SetBounds($x, $y1 + (& $px 3), $w, $rowH - (& $px 3))
        $x += $w + (& $px 4)
        $ui.cbOs.SetBounds($x, $y1, (& $px 170), $rowH)
        $x = $ui.cbOs.Right + $gap
        $ui.lblOs.SetBounds($x, $y1 + (& $px 3), [Math]::Max(50, $r - $x), $rowH - (& $px 3))
        $w = & $btnW $ui.btnIso 118
        $ui.btnIso.SetBounds($r - $w, $y2 - (& $px 2), $w, $bh)
        $ui.tbIso.SetBounds((& $px 32), $y2, $ui.btnIso.Left - $gap - (& $px 32), $rowH)
        $ui.rbDl.SetBounds($in, $y3, (& $chkW $ui.rbDl), $rowH)
        $w = & $lblW $ui.lnkMs
        $ui.lnkMs.SetBounds($r - $w, $y3 + (& $px 2), $w, $rowH - (& $px 2))
        $wf = & $btnW $ui.btnFetch 120
        $ui.btnFetch.SetBounds($r - $wf, $y4 - (& $px 2), $wf, $bh)
        $wl1 = & $lblW $ui.lblVersion; $wl2 = & $lblW $ui.lblArch; $wl3 = & $lblW $ui.lblLang; $wArch = & $px 70
        $avail = $ui.btnFetch.Left - $gap - (& $px 32) - $wl1 - $wl2 - $wl3 - $wArch - 3 * (& $px 4) - 2 * $gap
        $minLang = (Get-W11TextWidth (T 'lang.pressLoad') $ui.cbLang.Font) + (& $px 30)
        $wLang = [Math]::Max($minLang, [int]($avail * 0.4)); $wRel = [Math]::Max((& $px 160), $avail - $wLang)
        $x = & $px 32
        $ui.lblVersion.SetBounds($x, $y4 + (& $px 3), $wl1, $rowH - (& $px 3)); $x += $wl1 + (& $px 4)
        $ui.cbRelease.SetBounds($x, $y4, $wRel, $rowH); $x += $wRel + $gap
        $ui.lblArch.SetBounds($x, $y4 + (& $px 3), $wl2, $rowH - (& $px 3)); $x += $wl2 + (& $px 4)
        $ui.cbArch.SetBounds($x, $y4, $wArch, $rowH); $x += $wArch + $gap
        $ui.lblLang.SetBounds($x, $y4 + (& $px 3), $wl3, $rowH - (& $px 3)); $x += $wl3 + (& $px 4)
        $ui.cbLang.SetBounds($x, $y4, [Math]::Max((& $px 80), $ui.btnFetch.Left - $gap - $x), $rowH)
        $ui.cbLang.DropDownWidth = [Math]::Max($ui.cbLang.Width, (& $px 240))
        $ui.cbRelease.DropDownWidth = [Math]::Max($ui.cbRelease.Width, (& $px 420))
        $w = & $btnW $ui.btnDownload 114
        $ui.btnDownload.SetBounds($r - $w, $y5 - (& $px 2), $w, $bh)
        $ui.chkAria2.SetBounds((& $px 32), $y5, (& $chkW $ui.chkAria2), $rowH)
        $x = $ui.chkAria2.Right + $gap
        $ui.lblAria2.SetBounds($x, $y5 + (& $px 3), [Math]::Max(50, $ui.btnDownload.Left - $gap - $x), $rowH - (& $px 3))

        # ---------- vertical split: middle (2 + 3) and log share what is left ----------
        $wm = $ui.lblWatermark
        $wm.Height = $wm.Font.Height + (& $px 6)
        $bigH = & $px 32
        $g4H = $gt + $rowH + (& $px 11)
        $statusH = [Math]::Max((& $px 24), $rowH + (& $px 2))
        $yMid = $g1.Bottom + (& $px 6)
        $fixed = $yMid + (& $px 6) + $g4H + $gap + $bigH + (& $px 6) + $statusH + (& $px 4) + $gap + $wm.Height
        $minMid = & $px 330; $minLog = & $px 110
        $extra = $ch - $fixed - $minMid - $minLog
        $midH = $minMid; if ($extra -gt 0) { $midH += [int]($extra * 0.55) }

        # ---------- 2. apps ----------
        $g2w = [int](($gw - $M) * 0.58); $g3w = $gw - $M - $g2w
        $g2 = $ui.grpApps
        $g2.SetBounds($M, $yMid, $g2w, $midH)
        $ui.btnAppDef.SetBounds($in, 0, (& $btnW $ui.btnAppDef 90), $bh)
        $ui.btnAppAll.SetBounds($ui.btnAppDef.Right + (& $px 6), 0, (& $btnW $ui.btnAppAll 90), $bh)
        $ui.btnAppNone.SetBounds($ui.btnAppAll.Right + (& $px 6), 0, (& $btnW $ui.btnAppNone 90), $bh)
        $nx = $ui.btnAppNone.Right + $gap
        $nw = $g2w - $in - $nx
        if ($nw -ge (& $px 140)) {
            $nh = [Math]::Max($bh, (Get-W11TextHeight $ui.note.Text $ui.note.Font $nw) + (& $px 2))
            $rowTop = $midH - (& $px 8) - $nh
            $ui.note.SetBounds($nx, $rowTop, $nw, $nh)
            $btnTop = $rowTop + [int](($nh - $bh) / 2)
            $listBottom = $rowTop - (& $px 6)
        } else {
            # narrow: hint on its own line(s) under the buttons
            $nw = $g2w - 2 * $in
            $nh = (Get-W11TextHeight $ui.note.Text $ui.note.Font $nw) + (& $px 2)
            $ui.note.SetBounds($in, $midH - (& $px 8) - $nh, $nw, $nh)
            $btnTop = $ui.note.Top - (& $px 4) - $bh
            $listBottom = $btnTop - (& $px 6)
        }
        foreach ($b in @($ui.btnAppDef, $ui.btnAppAll, $ui.btnAppNone)) { $b.Top = $btnTop }
        $ui.clbApps.SetBounds($in, $gt + (& $px 2), $g2w - 2 * $in, [Math]::Max((& $px 60), $listBottom - $gt - (& $px 2)))

        # ---------- 3. options ----------
        $g3 = $ui.grpOptions
        $g3.SetBounds($g2.Right + $M, $yMid, $g3w, $midH)
        $iw = $g3w - 2 * $in
        $ui.lblEditions.SetBounds($in, $gt, $iw, $rowH - (& $px 3))
        $ye = $ui.lblEditions.Bottom
        $x = $in
        foreach ($rb in @($ui.rbEdAll, $ui.rbEdHP, $ui.rbEdCustom)) { $w = & $chkW $rb; $rb.SetBounds($x, $ye, $w, $rowH); $x += $w + (& $px 4) }
        $ui.tbIdx.SetBounds($x, $ye, [Math]::Max((& $px 50), $g3w - $in - $x), $rowH)
        $ui.btnEd.SetBounds($in, $ye + $rowH + (& $px 2), $iw, $bh)
        $ui.lblTweaks.SetBounds($in, $ui.btnEd.Bottom + (& $px 5), $iw, $rowH - (& $px 4))
        $chkH = { param($c) [Math]::Max($rowH - (& $px 1), (Get-W11TextHeight $c.Text $c.Font ($iw - (& $px 24))) + (& $px 6)) }
        $hDry = & $chkH $ui.chkDry; $hCl = & $chkH $ui.chkCleanup; $hUn = & $chkH $ui.chkUnattend
        $ui.chkDry.SetBounds($in, $midH - (& $px 6) - $hDry, $iw, $hDry)
        $ui.chkCleanup.SetBounds($in, $ui.chkDry.Top - $hCl, $iw, $hCl)
        $ui.chkUnattend.SetBounds($in, $ui.chkCleanup.Top - $hUn, $iw, $hUn)
        $ty = $ui.lblTweaks.Bottom + (& $px 1)
        $ui.clbTweaks.SetBounds($in, $ty, $iw, [Math]::Max((& $px 50), $ui.chkUnattend.Top - (& $px 4) - $ty))

        # ---------- 4. output ----------
        $g4 = $ui.grpOutput
        $g4.SetBounds($M, $g2.Bottom + (& $px 6), $gw, $g4H)
        $w = & $btnW $ui.btnOut 118
        $ui.btnOut.SetBounds($r - $w, $gt - (& $px 2), $w, $bh)
        $ui.tbOut.SetBounds($in, $gt, $ui.btnOut.Left - $gap - $in, $rowH)

        # ---------- actions / progress / status / log ----------
        $yb = $g4.Bottom + $gap
        $x = $M
        foreach ($p in @(@($ui.btnCheck, 130), @($ui.btnOsc, 120), @($ui.btnStart, 150), @($ui.btnCancel, 100))) {
            $w = & $btnW $p[0] $p[1]; $p[0].SetBounds($x, $yb, $w, $bigH); $x += $w + (& $px 6)
        }
        $x += & $px 2
        $ui.pb.SetBounds($x, $yb + (& $px 4), [Math]::Max((& $px 80), $cw - $M - $x), $bigH - (& $px 8))
        $ys = $yb + $bigH + (& $px 6)
        $w = & $lblW $ui.lnkLog
        $ui.lnkLog.SetBounds($cw - $M - $w, $ys + (& $px 3), $w, $statusH - (& $px 3))
        $ui.cbUiLang.SetBounds($ui.lnkLog.Left - (& $px 10) - (& $px 150), $ys, (& $px 150), $rowH)
        $ui.lblStatus.SetBounds($M, $ys + (& $px 3), [Math]::Max(50, $ui.cbUiLang.Left - (& $px 10) - $M), $statusH - (& $px 3))
        $yl = $ys + $statusH + (& $px 4)
        $ui.tbLog.SetBounds($M, $yl, $gw, [Math]::Max((& $px 60), $ch - $wm.Height - (& $px 6) - $yl))
    } finally {
        $f.ResumeLayout($true)
    }
}

function Invoke-W11Layout {
    # Resize handler: a layout error is reported once, not on every resize step
    try { Set-W11Layout }
    catch { if (-not $script:LayoutFailed) { $script:LayoutFailed = $true; Show-W11Error -Context 'layout' -ErrorRecord $_ } }
}

function New-W11Ctl {
    # Text '@key' = localized string; the key stays in .Tag so Set-W11UiTexts can switch the language live
    param([string]$Type, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H)
    $c = New-Object ("System.Windows.Forms.$Type")
    if ($Text -and $Text.StartsWith('@')) { $c.Tag = $Text; $c.Text = T $Text.Substring(1) }
    elseif ($Text) { $c.Text = $Text }
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
        $script:ui.lblStatus.Text = T 'status.waiting' $script:Job.Name
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

#region ---------- languages, settings, fonts ----------
$script:W11Langs = @(
    @{ Code = 'vi'; Name = 'Tiếng Việt' }
    @{ Code = 'en'; Name = 'English' }
    @{ Code = 'zh-CN'; Name = '简体中文' }
    @{ Code = 'km'; Name = 'ភាសាខ្មែរ' }
)
$script:AdkUrl = 'https://learn.microsoft.com/windows-hardware/get-started/adk-install'

function Import-W11Lang {
    # lang\<code>.psd1 (UTF-8 BOM, data only) -> hashtable; empty table when missing/broken
    param([string]$Code)
    $dir = Join-Path $script:W11Root 'lang'
    if (-not $Code -or -not (Test-W11PathText (Join-Path $dir "$Code.psd1") -Leaf)) { return @{} }
    try {
        $t = $null
        Import-LocalizedData -BaseDirectory $dir -FileName $Code -BindingVariable t -UICulture 'en-US' -ErrorAction Stop
        if ($t -is [hashtable]) { return $t }
    } catch { $null = $_ }
    return @{}
}

function Set-W11Language {
    param([string]$Code)
    if (-not (@($script:W11Langs | ForEach-Object { $_.Code }) -contains $Code)) { $Code = 'vi' }
    $script:UiLang = $Code
    $script:LEn = Import-W11Lang 'en'
    if ($Code -eq 'en') { $script:L = $script:LEn } else { $script:L = Import-W11Lang $Code }
    if ($script:Sync) { $script:Sync.UiLang = $Code }
    if ($script:W11D -and $script:W11D.Sync) { $script:W11D.Sync.UiLang = $Code }
}

function T {
    # T 'key' [arg0 arg1 ...] -> text in the chosen language (fallback English, then the key itself)
    param([string]$Key)
    $s = $null
    if ($script:L -and $script:L.ContainsKey($Key)) { $s = [string]$script:L[$Key] }
    if (-not $s -and $script:LEn -and $script:LEn.ContainsKey($Key)) { $s = [string]$script:LEn[$Key] }
    if (-not $s) { $s = $Key }
    $s = $s.Replace('\n', "`n")
    if ($args.Count -gt 0) { try { $s = $s -f $args } catch { $s = $s + ' ' + ($args -join ' ') } }
    return $s
}

function Get-W11FontFor {
    # first installed font that can show the language (Khmer / Chinese need special fonts)
    param([string]$Code, [string[]]$Installed)
    switch ($Code) {
        'zh-CN' { $c = @('Microsoft YaHei UI', 'Microsoft YaHei', 'SimSun', 'Segoe UI') }
        'km' { $c = @('Leelawadee UI', 'Khmer UI', 'DaunPenh', 'Khmer OS System', 'Segoe UI') }
        default { $c = @('Segoe UI', 'Tahoma', 'Microsoft Sans Serif') }
    }
    foreach ($n in $c) { if (@($Installed) -contains $n) { return $n } }
    return $c[$c.Count - 1]
}

function Get-W11InstalledFonts {
    try { return @((New-Object Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }) } catch { return @() }
}

function Get-W11SettingsPath {
    # <tool>\settings.psd1 when the tool folder is writable, else %APPDATA%\WinDebloatTool\settings.psd1
    param([switch]$ForWrite)
    $p1 = Join-Path $script:W11Root 'settings.psd1'
    $p2 = $null; if ($env:APPDATA) { $p2 = Join-Path (Join-Path $env:APPDATA 'WinDebloatTool') 'settings.psd1' }
    if (-not $ForWrite) {
        if (Test-W11PathText $p1 -Leaf) { return $p1 }
        if ($p2 -and (Test-W11PathText $p2 -Leaf)) { return $p2 }
        return $null
    }
    try { $probe = Join-Path $script:W11Root ('.w11w' + [guid]::NewGuid().ToString('N')); [IO.File]::WriteAllText($probe, ''); Remove-Item -LiteralPath $probe -Force; return $p1 } catch { $null = $_ }
    return $p2
}

function Read-W11Settings {
    $p = Get-W11SettingsPath
    if (-not $p) { return @{} }
    try {
        $t = $null
        Import-LocalizedData -BaseDirectory (Split-Path -Parent $p) -FileName 'settings' -BindingVariable t -UICulture 'en-US' -ErrorAction Stop
        if ($t -is [hashtable]) { return $t }
    } catch { $null = $_ }
    return @{}
}

function Save-W11Settings {
    param([hashtable]$Settings)
    $p = Get-W11SettingsPath -ForWrite
    if (-not $p) { return $null }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("# WinDebloat Tool settings (written by the tool)`r`n@{`r`n")
    foreach ($k in @($Settings.Keys | Sort-Object)) {
        if ($k -notmatch '^[A-Za-z][A-Za-z0-9]*$') { continue }
        [void]$sb.Append(("    {0} = '{1}'`r`n" -f $k, ([string]$Settings[$k]).Replace("'", "''")))
    }
    [void]$sb.Append("}`r`n")
    try {
        $d = Split-Path -Parent $p
        if (-not (Test-W11PathText $d -Container)) { New-W11Directory $d }
        [IO.File]::WriteAllText($p, $sb.ToString(), (New-Object Text.UTF8Encoding $true))
        return $p
    } catch { return $null }
}

function Get-W11DownloadFolder {
    # last used folder -> %USERPROFILE%\Downloads -> <tool>\downloads (created)
    param([hashtable]$Settings)
    if ($Settings -and $Settings.DownloadFolder -and (Test-W11PathText ([string]$Settings.DownloadFolder) -Container)) { return [string]$Settings.DownloadFolder }
    if ($env:USERPROFILE) { $d = Join-Path $env:USERPROFILE 'Downloads'; if (Test-W11PathText $d -Container) { return $d } }
    $d = Join-Path $script:W11Root 'downloads'
    try { if (-not (Test-W11PathText $d -Container)) { New-W11Directory $d } } catch { $null = $_ }
    return $d
}
#endregion

function Get-W11GuiLogPath {
    # GUI session log: <tool folder>\logs\WinDebloat_gui_<time>.log, or %TEMP% if the tool folder is read-only.
    $name = 'WinDebloat_gui_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log'
    foreach ($dir in @((Join-Path $script:W11Root 'logs'), $env:TEMP)) {
        if (-not $dir) { continue }
        try {
            New-W11Directory $dir
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
        if ($script:ui -and $script:ui.lblStatus) { $script:ui.lblStatus.Text = T 'status.error' $msg }
        if ($script:ui -and $script:ui.btnCancel -and -not $script:Job) { Set-W11Busy $false }
    } catch { $null = $_ }
    $logTxt = ''
    if ($script:W11D.LogPath) { $logTxt = "`n`n" + (T 'msg.logFile' $script:W11D.LogPath) }
    try {
        [void][Windows.Forms.MessageBox]::Show($script:ui.form, (T 'msg.error' $Context $msg) + $logTxt, 'WinDebloat Tool', 'OK', 'Error')
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
    if ($e.Available -eq $false) { return (T 'item.notOffered' $e.Release) }
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
        $keep = $ui.cbLang.SelectedIndex
        $ui.cbLang.Items.Clear()
        $e = Get-W11SelectedEntry
        if (-not $e) { return }
        if ($e.Available -eq $false) {
            [void]$ui.cbLang.Items.Add((T 'lang.notOffered'))
            $ui.cbLang.SelectedIndex = 0
            return
        }
        if ($e.Static -or @($e.Skus).Count -eq 0) {
            [void]$ui.cbLang.Items.Add((T 'lang.pressLoad'))
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
        if ($script:KeepLangIndex -and $keep -ge 0 -and $keep -lt $ui.cbLang.Items.Count) { $def = $keep }
        if ($ui.cbLang.Items.Count -gt 0) { $ui.cbLang.SelectedIndex = $def }
    }
}

function Get-W11SelectedRelease {
    $i = $script:ui.cbRelease.SelectedIndex
    if ($i -lt 0 -or $i -ge @($script:ReleaseItems).Count) { return $null }
    return $script:ReleaseItems[$i]
}

function Get-W11SelectedEntry {
    $rel = Get-W11SelectedRelease
    $arch = [string]$script:ui.cbArch.SelectedItem
    return (@($script:Catalog | Where-Object { $_.Release -eq $rel -and $_.Arch -eq $arch }) | Select-Object -First 1)
}

#region ---------- Microsoft failure -> optional mirror fallback ----------
function Get-W11MirrorChoices {
    # mirror entries that fit the selected (failed) Microsoft download: same OS + architecture
    param($Entry)
    $os = Get-W11EffectiveOs; $arch = ((Get-W11HostArch) -replace 'amd64', 'x64'); $rel = ''
    if ($Entry) { $os = $Entry.Os; $arch = $Entry.Arch; $rel = $Entry.Name }
    return @(Get-MsMirrorCandidates -Config $script:Cfg -Os $os -Arch $arch -ReleaseName $rel)
}

function Show-W11MsFailure {
    # Microsoft could not deliver (withdrawn release, Sentinel / Type 9 block, CDN error).
    # Mirror fallback is offered only here, only on request, and only for entries with a known SHA256.
    param($Entry, [string]$Text, [string]$Icon = 'Warning')
    $logTxt = ''; if ($script:W11D.LogPath) { $logTxt = "`n`n" + (T 'msg.logFile' $script:W11D.LogPath) }
    $choices = @(Get-W11MirrorChoices $Entry)
    if ($choices.Count -gt 0) {
        $ans = [string](Show-W11Msg ($Text + "`n`n" + (T 'q.tryMirror') + $logTxt) $Icon 'YesNoCancel')
        if ($ans -eq 'Yes') { Invoke-W11MirrorOffer $choices }
        elseif ($ans -eq 'No') { & $script:H['lnkMs.LinkClicked'] }
        return
    }
    $ans = [string](Show-W11Msg ($Text + "`n`n" + (T 'q.openMs') + $logTxt) $Icon 'YesNo')
    if ($ans -eq 'Yes') { & $script:H['lnkMs.LinkClicked'] }
}

function Show-W11NotOffered($e) {
    $name = ''; if ($e) { $name = $e.Release }
    Show-W11MsFailure -Entry $e -Text (T 'msg.notOffered' $name) -Icon 'Information'
}

function Select-W11Mirror {
    # small picker when several mirror entries fit; returns the chosen entry or $null
    param([object[]]$Choices)
    if (@($Choices).Count -eq 1) { return $Choices[0] }
    $d = New-Object Windows.Forms.Form
    $d.Text = 'WinDebloat Tool'; $d.ClientSize = New-Object Drawing.Size 640, 250
    $d.StartPosition = 'CenterParent'; $d.FormBorderStyle = 'FixedDialog'; $d.MinimizeBox = $false; $d.MaximizeBox = $false
    $d.Font = $script:ui.form.Font
    $lb = New-W11Ctl Label (T 'dlg.mirrorPick') 12 10 616 40
    $list = New-W11Ctl ListBox '' 12 52 616 150
    foreach ($m in $Choices) { [void]$list.Items.Add(('{0}   ({1})' -f $m.FileName, (Get-MsUrlHost $m.Url))) }
    $list.SelectedIndex = 0
    $ok = New-W11Ctl Button (T 'btn.ok') 432 212 94 28; $ok.DialogResult = 'OK'
    $no = New-W11Ctl Button (T 'btn.cancel') 534 212 94 28; $no.DialogResult = 'Cancel'
    $d.AcceptButton = $ok; $d.CancelButton = $no
    $d.Controls.AddRange(@($lb, $list, $ok, $no))
    $r = $d.ShowDialog($script:ui.form)
    $i = $list.SelectedIndex
    $d.Dispose()
    if ([string]$r -ne 'OK' -or $i -lt 0) { return $null }
    return $Choices[$i]
}

function Invoke-W11MirrorOffer {
    param([object[]]$Choices)
    $m = Select-W11Mirror $Choices
    if (-not $m) { return }
    $hostName = Get-MsUrlHost $m.Url
    $ans = [string](Show-W11Msg (T 'msg.mirrorOffer' $m.FileName $hostName $m.Sha256) 'Warning' 'YesNo')
    if ($ans -ne 'Yes') { Write-W11Log -En 'Mirror fallback declined.' -Vi 'Đã từ chối dùng mirror.'; return }
    Write-W11Log -Level WARN -En "Mirror fallback chosen by the user: $($m.FileName) from host $hostName (NOT a Microsoft server; listed on $($m.Page)). The file will be accepted only if its SHA256 is $($m.Sha256)." -Vi "Đã chọn tải từ mirror $hostName (không phải máy chủ Microsoft); chỉ chấp nhận khi SHA256 khớp."
    Start-Process $m.Url
    $d = New-Object Windows.Forms.OpenFileDialog
    $d.Filter = T 'dlg.isoFilter'
    $d.Title = T 'dlg.pickMirror' $m.FileName
    $d.FileName = $m.FileName
    $dir = Get-W11DownloadFolder $script:Settings
    if (Test-W11PathText $dir -Container) { $d.InitialDirectory = $dir }
    if ($d.ShowDialog($script:ui.form) -ne 'OK') { return }
    Start-W11MirrorVerify -Path $d.FileName -Mirror $m
}

function Start-W11MirrorVerify {
    param([string]$Path, $Mirror)
    $script:ui.lblStatus.Text = T 'status.verifying'
    [void](Start-W11Job -Name 'Verify mirror ISO' -Script '$sync.Result = Test-MsMirrorFile -Path $JobArgs.Path -Mirror $JobArgs.Mirror' -JobArgs @{ Path = $Path; Mirror = $Mirror } -OnDone {
            $r = $script:Sync.Result
            if ($r -and $r.Ok) {
                $script:ui.tbIso.Text = $r.Path
                $script:ui.rbLocal.Checked = $true
                if (-not $script:ui.tbOut.Text.Trim()) { $script:ui.tbOut.Text = Get-W11SuggestedOutput $r.Path }
                Start-W11Detect $r.Path
                $script:ui.lblStatus.Text = T 'status.ready'
                Show-W11Msg (T 'msg.mirrorOk' $r.Path) | Out-Null
                return
            }
            $script:ui.lblStatus.Text = T 'status.dlFailed'
            if ($r -and $r.Deleted) { Show-W11Msg (T 'msg.mirrorBad' $r.Path $r.Hash $r.Expected) 'Error' | Out-Null; return }
            $why = $script:Sync.Error; if ($r -and $r.Error) { $why = $r.Error }
            $pth = ''; if ($r) { $pth = $r.Path }
            Show-W11Msg (T 'msg.mirrorBadKept' $pth $why) 'Error' | Out-Null
        })
}
#endregion

function Get-W11SuggestedOutput {
    # <source>_debloated.iso next to the source; '' when there is no usable source path (never throws)
    param([string]$Iso)
    $full = Resolve-W11FullPath $Iso
    if (-not $full -or (Test-W11IsPathRoot $full)) { return '' }
    $leaf = Get-W11PathLeaf $full
    $name = $leaf; $dot = $leaf.LastIndexOf('.'); if ($dot -gt 0) { $name = $leaf.Substring(0, $dot) }
    if (-not $name) { return '' }
    return (Join-W11Path (Get-W11ParentDir $full) ($name + '_debloated.iso'))
}

function Test-W11OutputPath {
    # $null when the output ISO path is usable, otherwise the message to show
    param([string]$Out, [string]$Iso)
    # (same path rules as Invoke-Win11Debloat: quotes / spaces / invisible characters removed, Windows rules)
    $c = ConvertTo-W11CleanPath $Out
    if (-not $c) { return (T 'msg.outInvalid' '') }
    $full = Resolve-W11FullPath $c
    if (-not $full -or (Test-W11IsPathRoot $full)) { return (T 'msg.outInvalid' $c) }
    if (Test-W11PathText $full -Container) {
        $n = Get-W11SuggestedOutput $Iso; if ($n) { $n = Get-W11PathLeaf $n } else { $n = 'Windows_debloated.iso' }
        return (T 'msg.outIsFolder' $full (Join-W11Path $full $n))
    }
    $dir = Get-W11ParentDir $full
    if (-not (Test-W11PathText $dir -Container)) {
        if (Test-W11IsPathRoot $dir) { return (T 'msg.outDriveMissing' $dir) }
        return (T 'msg.outDirMissing' $dir)
    }
    if ($Iso) { $fi = Resolve-W11FullPath $Iso; if ($fi -and $fi -eq $full) { return (T 'msg.outSameAsIso') } }
    return $null
}

function Get-W11EffectiveOs {
    # Combo: 0 = Auto (detected, else Windows 11 list as placeholder), 1 = Windows 11, 2 = Windows 10
    $i = $script:ui.cbOs.SelectedIndex
    if ($i -eq 1) { return 'Win11' }
    if ($i -eq 2) { return 'Win10' }
    if ($script:DetectedOs) { return $script:DetectedOs }
    return 'Win11'
}

$script:W11AppNotes = @{
    'older builds' = 'app.older'; 'optional' = 'app.optional'; 'if present' = 'app.ifPresent'; 'new' = 'app.new'
    'Store/games UI' = 'app.noteStoreUi'; 'game sign-in' = 'app.noteGameSignIn'
    'accessibility, hard to reinstall' = 'app.noteSpeech'; 'troubleshooters' = 'app.noteGetHelp'
    'classic Paint stays' = 'app.notePaint'
}

function Get-W11AppText($a) {
    # app list entry: product names and package Ids stay as they are, the note in the trailing brackets
    # ("optional", "unsafe: game sign-in", "optional; classic Paint stays" ...) is translated part by part
    $n = [string]$a.Name
    if ($n -match '^(.*\S)\s*\(([^()]+)\)$') {
        $base = $matches[1]; $parts = @()
        foreach ($p in ($matches[2] -split ';\s*')) {
            $pre = ''
            if ($p -match '^unsafe:\s*(.+)$') { $pre = (T 'app.unsafe') + ': '; $p = $matches[1] }
            if ($script:W11AppNotes.ContainsKey($p)) { $p = T $script:W11AppNotes[$p] }
            $parts += ($pre + $p)
        }
        $n = '{0} ({1})' -f $base, ($parts -join '; ')
    }
    return ('{0}   [{1}]' -f $n, $a.Id)
}

function Get-W11TweakText($t) {
    $k = 'tweak.' + $t.Id
    if (($script:L -and $script:L.ContainsKey($k)) -or ($script:LEn -and $script:LEn.ContainsKey($k))) { return (T $k) }
    return [string]$t.Name
}

function Set-W11ProfileLists {
    # (Re)fills the app and tweak lists for the effective target OS and, when known, the image build
    # (entries outside their MinBuild/MaxBuild are hidden). -KeepChecks keeps the user's ticks (language switch).
    param([switch]$Force, [switch]$KeepChecks)
    $os = Get-W11EffectiveOs
    $build = 0; if ($script:DetectedOs -and $script:DetectedOs -eq $os) { $build = [int]$script:DetectedBuild }
    $key = "$os/$build"
    if (-not $Force -and $script:ShownOs -eq $key) { return }
    $ui = $script:ui
    $keepA = $null; $keepT = $null
    if ($KeepChecks -and $script:ShownOs -eq $key) {
        $keepA = @(); foreach ($i in $ui.clbApps.CheckedIndices) { $keepA += $script:AppIds[$i] }
        $keepT = @(); foreach ($i in $ui.clbTweaks.CheckedIndices) { $keepT += $script:TweakIds[$i] }
    }
    $script:ShownOs = $key
    $prof = Get-W11Profile -Config $script:Cfg -Os $os -Build $build
    $script:ProfileApps = @($prof.Apps)
    $ui.clbApps.Items.Clear(); $script:AppIds = @()
    foreach ($a in $prof.Apps) {
        $i = $ui.clbApps.Items.Add((Get-W11AppText $a))
        $on = [bool]$a.Default; if ($null -ne $keepA) { $on = ($keepA -contains $a.Id) }
        $ui.clbApps.SetItemChecked($i, $on)
        $script:AppIds += $a.Id
    }
    $ui.clbTweaks.Items.Clear(); $script:TweakIds = @()
    foreach ($t in $prof.Tweaks) {
        $i = $ui.clbTweaks.Items.Add((Get-W11TweakText $t))
        $on = [bool]$t.Default; if ($null -ne $keepT) { $on = ($keepT -contains $t.Id) }
        $ui.clbTweaks.SetItemChecked($i, $on)
        $script:TweakIds += $t.Id
    }
    Set-W11ListExtent $ui.clbApps
    Set-W11ListExtent $ui.clbTweaks
    $title = Get-W11OsLabel $os
    if ($build -gt 0) { $title = Get-W11ReleaseLabel -Build $build -Os $os }
    $ui.grpApps.Text = T 'grp.apps' $title
    $hidden = @($prof.SkippedApps).Count + @($prof.SkippedTweaks).Count
    if (-not $KeepChecks -and $build -gt 0 -and $hidden -gt 0) { Write-W11Log -En "$hidden list entries do not apply to $title and are hidden" -Vi "$hidden mục không áp dụng cho bản này nên được ẩn" }
}

function Update-W11DetectedLabel {
    $src = [string]$script:DetectedSource
    if ($src -eq 'filename') { $src = T 'src.filename' } elseif ($src -eq 'download') { $src = T 'src.download' }
    if (-not $script:DetectedSource -and -not $script:DetectedOs) { $script:ui.lblOs.Text = T 'lbl.detectedNone'; return }
    if ($script:DetectedOs) { $script:ui.lblOs.Text = T 'lbl.detected' (Get-W11ReleaseLabel -Build $script:DetectedBuild -Os $script:DetectedOs) $src }
    else { $script:ui.lblOs.Text = T 'lbl.detectedUnknown' }
}

function Set-W11Detected {
    param([string]$Os, [string]$Source, [int]$Build = 0)
    $script:DetectedOs = $Os
    $script:DetectedBuild = $Build
    $script:DetectedSource = $Source
    Update-W11DetectedLabel
    Set-W11ProfileLists
}

function Start-W11Detect {
    # quick guess from the file name, then (Win8+) read the WIM header inside the ISO in the background
    param([string]$Iso)
    if (-not (Test-W11PathText $Iso -Leaf)) { return }
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

function Set-W11UiTexts {
    # applies the chosen language to every control (live switch) + a font that can show it
    $ui = $script:ui
    $fam = Get-W11FontFor -Code $script:UiLang -Installed $script:InstalledFonts
    $ui.form.Font = New-Object Drawing.Font $fam, 9
    $ui.btnStart.Font = New-Object Drawing.Font $fam, 9, ([Drawing.FontStyle]::Bold)
    $ui.note.Font = New-Object Drawing.Font $fam, 7.5
    if ($ui.lblWatermark) {
        $ui.lblWatermark.Font = New-Object Drawing.Font $fam, 7.5
        $ui.lblWatermark.Text = $script:W11Watermark
    }
    $ui.form.Text = T 'app.title' $script:W11D.Version
    $stack = New-Object Collections.Stack
    $stack.Push($ui.form)
    while ($stack.Count -gt 0) {
        $c = $stack.Pop()
        if ($c.Tag -is [string] -and ([string]$c.Tag).StartsWith('@')) { $c.Text = T ([string]$c.Tag).Substring(1) }
        foreach ($ch in $c.Controls) { $stack.Push($ch) }
    }
    $i = $ui.cbOs.SelectedIndex
    $ui.cbOs.Items[0] = T 'os.auto'
    $ui.cbOs.SelectedIndex = $i
    if ($script:Aria2Exe) { $ui.lblAria2.Text = 'aria2: ' + $script:Aria2Exe } else { $ui.lblAria2.Text = T 'lbl.aria2Missing' }
    if ($ui.tip) { $ui.tip.SetToolTip($ui.cbUiLang, (T 'tip.uiLang')) }
    Update-W11DetectedLabel
    $script:KeepLangIndex = $true
    try { if ($ui.cbRelease.Items.Count -gt 0) { Update-W11DownloadLists 'release' } } finally { $script:KeepLangIndex = $false }
    Set-W11ProfileLists -Force -KeepChecks
    if (-not $script:Job) { $ui.lblStatus.Text = T 'status.ready' }
    Invoke-W11Layout
}

function Invoke-W11OscInstall {
    # official Microsoft source only: adksetup.exe /features OptionId.DeploymentTools, or winget Microsoft.WindowsADK
    param([switch]$ThenStart)
    if ((Get-W11OsBuild) -lt 10240) { Show-W11Msg (T 'msg.oscWin7' (Join-Path $script:W11Root 'tools')) 'Warning' | Out-Null; return }
    $ans = [string](Show-W11Msg (T 'msg.oscPrompt' $script:AdkUrl) 'Question' 'YesNoCancel')
    if ($ans -eq 'Cancel') { return }
    $m = 'AdkSetup'; if ($ans -eq 'No') { $m = 'Winget' }
    $script:AfterOsc = [bool]$ThenStart
    $script:ui.lblStatus.Text = T 'status.oscInstalling'
    [void](Start-W11Job -Name 'Install ADK' -Script '$null = Install-W11Oscdimg -Method $JobArgs.Method' -JobArgs @{ Method = $m } -OnDone {
            if ($script:Sync.Error) { $script:ui.lblStatus.Text = T 'status.error' $script:Sync.Error; Show-W11Msg (T 'msg.oscFailed' $script:Sync.Error $script:AdkUrl) 'Error' | Out-Null; return }
            $script:ui.lblStatus.Text = T 'status.ready'
            $p = Find-W11Oscdimg
            if ($p -and $script:AfterOsc) { Write-W11Log -Level OK -En "oscdimg ready: $p" -Vi 'Đã có oscdimg'; & $script:StartRun; return }
            if ($p) { Show-W11Msg (T 'msg.oscReady' $p) | Out-Null } else { Show-W11Msg (T 'msg.oscFailed' 'oscdimg.exe not found after the install' $script:AdkUrl) 'Error' | Out-Null }
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
            Percent = 0; Status = ''; Cancel = $false; Result = $null; Error = $null; UiLang = 'vi'
        })
    $script:W11D.Sync = $script:Sync
    $script:Job = $null
    $script:Settings = Read-W11Settings
    Set-W11Language ([string]$script:Settings.Language)
    $script:InstalledFonts = Get-W11InstalledFonts
    $script:Catalog = @(Get-MsReleaseCatalog)
    $script:ReleaseItems = @()
    $cfg = Get-W11Config
    $script:Cfg = $cfg

    $ui = @{}
    $script:ui = $ui
    $f = New-Object Windows.Forms.Form
    $f.ClientSize = New-Object Drawing.Size 980, 840
    $f.StartPosition = 'CenterScreen'
    $f.Font = New-Object Drawing.Font 'Segoe UI', 9
    $f.MinimumSize = New-Object Drawing.Size 1000, 880
    $ui.form = $f
    $ui.tip = New-Object Windows.Forms.ToolTip

    # ---------- 1. source ----------
    $g1 = New-W11Ctl GroupBox '@grp.source' 10 8 960 166
    $ui.grpSource = $g1
    $ui.rbLocal = New-W11Ctl RadioButton '@rb.local' 12 20 400 22
    $ui.rbLocal.Checked = $true
    $lo = New-W11Ctl Label '@lbl.targetOs' 418 23 150 20
    $ui.cbOs = New-W11Ctl ComboBox '' 570 19 170 23
    $ui.cbOs.DropDownStyle = 'DropDownList'
    [void]$ui.cbOs.Items.Add((T 'os.auto'))
    [void]$ui.cbOs.Items.Add('Windows 11')
    [void]$ui.cbOs.Items.Add('Windows 10')
    $ui.lblTargetOs = $lo
    $ui.lblOs = New-W11Ctl Label '' 746 23 210 20
    $ui.lblOs.AutoEllipsis = $true
    $ui.lblOs.ForeColor = [Drawing.Color]::DimGray
    $ui.tbIso = New-W11Ctl TextBox '' 32 44 790 23
    $ui.btnIso = New-W11Ctl Button '@btn.browse' 830 42 118 26
    $ui.rbDl = New-W11Ctl RadioButton '@rb.download' 12 74 520 22
    $lr = New-W11Ctl Label '@lbl.version' 32 107 80 20
    $ui.cbRelease = New-W11Ctl ComboBox '' 114 104 320 23   # every Windows 11 + Windows 10 release Microsoft serves
    $ui.cbRelease.DropDownWidth = 420; $ui.cbRelease.MaxDropDownItems = 20
    $ui.lblVersion = $lr
    $la = New-W11Ctl Label '@lbl.arch' 440 107 84 20
    $ui.lblArch = $la
    $ui.cbArch = New-W11Ctl ComboBox '' 526 104 64 23
    $ll = New-W11Ctl Label '@lbl.lang' 596 107 64 20
    $ui.lblLang = $ll
    $ui.cbLang = New-W11Ctl ComboBox '' 662 104 120 23
    $ui.cbLang.DropDownWidth = 240
    foreach ($cb in @($ui.cbRelease, $ui.cbArch, $ui.cbLang)) { $cb.DropDownStyle = 'DropDownList' }
    $ui.btnFetch = New-W11Ctl Button '@btn.languages' 788 102 160 27
    $ui.btnDownload = New-W11Ctl Button '@btn.download' 834 134 114 27
    $ui.chkAria2 = New-W11Ctl CheckBox '@chk.aria2' 32 136 360 22
    $ui.lblAria2 = New-W11Ctl Label '' 396 139 432 20
    $ui.lblAria2.ForeColor = [Drawing.Color]::DimGray
    $ui.lblAria2.AutoEllipsis = $true
    $script:Aria2Exe = $null
    try { $script:Aria2Exe = Find-MsAria2 } catch { $script:Aria2Exe = $null }
    if ($script:Aria2Exe) {
        $useA = $true; if ($cfg.Download -and $cfg.Download.ContainsKey('UseAria2')) { $useA = [bool]$cfg.Download.UseAria2 }
        $ui.chkAria2.Checked = $useA
    } else { $ui.chkAria2.Checked = $false; $ui.chkAria2.Enabled = $false }
    $ui.lnkMs = New-W11Ctl LinkLabel '@lnk.ms' 560 76 390 20
    $ui.lnkMs.TextAlign = 'MiddleRight'
    $g1.Controls.AddRange(@($lo, $ui.cbOs, $ui.lblOs, $ui.rbLocal, $ui.tbIso, $ui.btnIso, $ui.rbDl, $ui.btnFetch, $lr, $ui.cbRelease, $la, $ui.cbArch, $ll, $ui.cbLang, $ui.btnDownload, $ui.lnkMs, $ui.chkAria2, $ui.lblAria2))

    # ---------- 2. apps ----------
    $g2 = New-W11Ctl GroupBox '' 10 180 560 330
    $ui.grpApps = $g2
    $ui.clbApps = New-W11Ctl CheckedListBox '' 12 22 536 266
    $ui.clbApps.CheckOnClick = $true
    $ui.clbApps.HorizontalScrollbar = $true
    $ui.clbApps.IntegralHeight = $false
    $script:AppIds = @()
    $ui.btnAppDef = New-W11Ctl Button '@btn.appDef' 12 294 120 27
    $ui.btnAppAll = New-W11Ctl Button '@btn.appAll' 138 294 100 27
    $ui.btnAppNone = New-W11Ctl Button '@btn.appNone' 244 294 100 27
    $ui.note = New-W11Ctl Label '@lbl.keptNote' 350 294 205 34
    $ui.note.ForeColor = [Drawing.Color]::DimGray
    $g2.Controls.AddRange(@($ui.clbApps, $ui.btnAppDef, $ui.btnAppAll, $ui.btnAppNone, $ui.note))

    # ---------- 3. options ----------
    $g3 = New-W11Ctl GroupBox '@grp.options' 580 180 390 330
    $ui.grpOptions = $g3
    $le = New-W11Ctl Label '@lbl.editions' 12 22 300 20
    $ui.lblEditions = $le
    $ui.rbEdAll = New-W11Ctl RadioButton '@rb.edAll' 12 42 100 22
    $ui.rbEdHP = New-W11Ctl RadioButton 'Home + Pro' 116 42 100 22
    $ui.rbEdCustom = New-W11Ctl RadioButton '@rb.edIdx' 218 42 92 22
    $ui.rbEdAll.Checked = $true
    $ui.tbIdx = New-W11Ctl TextBox '' 312 42 66 23
    $ui.btnEd = New-W11Ctl Button '@btn.listEditions' 12 66 366 25
    $lt = New-W11Ctl Label '@lbl.tweaks' 12 96 300 18
    $ui.lblTweaks = $lt
    $ui.clbTweaks = New-W11Ctl CheckedListBox '' 12 115 366 128
    $ui.clbTweaks.CheckOnClick = $true
    $ui.clbTweaks.HorizontalScrollbar = $true
    $ui.clbTweaks.IntegralHeight = $false
    $script:TweakIds = @()
    $ui.chkUnattend = New-W11Ctl CheckBox '@chk.unattend' 12 246 370 34
    $ui.chkUnattend.Checked = $true
    $ui.chkCleanup = New-W11Ctl CheckBox '@chk.cleanup' 12 280 370 22
    $ui.chkDry = New-W11Ctl CheckBox '@chk.dry' 12 302 370 22
    $g3.Controls.AddRange(@($le, $ui.rbEdAll, $ui.rbEdHP, $ui.rbEdCustom, $ui.tbIdx, $ui.btnEd, $lt, $ui.clbTweaks, $ui.chkUnattend, $ui.chkCleanup, $ui.chkDry))

    # ---------- 4. output ----------
    $g4 = New-W11Ctl GroupBox '@grp.output' 10 516 960 56
    $ui.grpOutput = $g4
    $ui.tbOut = New-W11Ctl TextBox '' 12 22 810 23
    $ui.btnOut = New-W11Ctl Button '@btn.saveAs' 830 20 118 26
    $g4.Controls.AddRange(@($ui.tbOut, $ui.btnOut))

    # ---------- actions / progress / log ----------
    $ui.btnCheck = New-W11Ctl Button '@btn.check' 10 580 150 32
    $ui.btnOsc = New-W11Ctl Button '@btn.osc' 166 580 130 32
    $ui.btnStart = New-W11Ctl Button '@btn.start' 302 580 150 32
    $ui.btnCancel = New-W11Ctl Button '@btn.cancel' 458 580 100 32
    $ui.btnCancel.Enabled = $false
    $ui.pb = New-W11Ctl ProgressBar '' 566 584 404 24
    $ui.pb.Minimum = 0; $ui.pb.Maximum = 100
    $ui.lblStatus = New-W11Ctl Label '@status.ready' 10 618 560 20
    $ui.lblStatus.AutoEllipsis = $true
    $ui.cbUiLang = New-W11Ctl ComboBox '' 580 615 150 23
    $ui.cbUiLang.DropDownStyle = 'DropDownList'
    foreach ($lg in $script:W11Langs) { [void]$ui.cbUiLang.Items.Add($lg.Name) }
    $ui.lnkLog = New-W11Ctl LinkLabel '@lnk.log' 740 618 230 20
    $ui.lnkLog.TextAlign = 'MiddleRight'
    $ui.tbLog = New-W11Ctl TextBox '' 10 642 960 164
    $ui.tbLog.Multiline = $true; $ui.tbLog.ScrollBars = 'Both'; $ui.tbLog.ReadOnly = $true; $ui.tbLog.WordWrap = $false
    $ui.tbLog.MaxLength = 2147483647
    $ui.tbLog.Font = New-Object Drawing.Font 'Consolas', 8.5
    # every control is placed by Set-W11Layout (on resize and after a language switch)
    # watermark: docked to the bottom edge (stays there on resize), below the log box, system gray text
    # (follows the Windows colour scheme / high contrast), no '@' key = not translated
    $ui.lblWatermark = New-Object Windows.Forms.Label
    $ui.lblWatermark.Name = 'lblWatermark'
    $ui.lblWatermark.AutoSize = $false
    $ui.lblWatermark.UseMnemonic = $false
    $ui.lblWatermark.Dock = 'Bottom'
    $ui.lblWatermark.TextAlign = 'MiddleRight'
    $ui.lblWatermark.Padding = New-Object Windows.Forms.Padding 0, 0, 12, 2
    $ui.lblWatermark.ForeColor = [Drawing.SystemColors]::GrayText
    $ui.lblWatermark.BackColor = [Drawing.Color]::Transparent
    $ui.lblWatermark.Font = New-Object Drawing.Font 'Segoe UI', 7.5
    $ui.lblWatermark.Text = $script:W11Watermark
    $ui.lblWatermark.Height = $ui.lblWatermark.Font.Height + 6
    $f.Controls.AddRange(@($g1, $g2, $g3, $g4, $ui.btnCheck, $ui.btnOsc, $ui.btnStart, $ui.btnCancel, $ui.pb, $ui.lblStatus, $ui.cbUiLang, $ui.lnkLog, $ui.tbLog, $ui.lblWatermark))

    $script:DetectedOs = $null; $script:DetectedBuild = 0; $script:DetectedSource = $null; $script:ShownOs = $null; $script:LastDlEntry = $null; $script:AutoDownload = $false
    $ui.cbOs.SelectedIndex = 0
    for ($i = 0; $i -lt $script:W11Langs.Count; $i++) { if ($script:W11Langs[$i].Code -eq $script:UiLang) { $ui.cbUiLang.SelectedIndex = $i } }
    Set-W11ProfileLists -Force
    Set-W11UiTexts
    $f.Add_Resize({ Invoke-W11Layout })
    $script:H['cbOs.SelectedIndexChanged'] = { Set-W11ProfileLists }
    $ui.cbOs.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbOs.SelectedIndexChanged' })
    $script:H['cbUiLang.SelectedIndexChanged'] = {
        $i = $script:ui.cbUiLang.SelectedIndex
        if ($i -lt 0) { return }
        $code = $script:W11Langs[$i].Code
        if ($code -eq $script:UiLang) { return }
        Set-W11Language $code
        Set-W11UiTexts
        $script:Settings.Language = $code
        $null = Save-W11Settings $script:Settings
    }
    $ui.cbUiLang.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbUiLang.SelectedIndexChanged' })
    $script:H['lnkLog.LinkClicked'] = {
        $lp = $script:W11D.LogPath
        if (Test-W11PathText $lp -Leaf) { Start-Process 'explorer.exe' -ArgumentList ('/select,"' + $lp + '"') }
        else { Show-W11Msg (T 'msg.noLog') | Out-Null }
    }
    $ui.lnkLog.Add_LinkClicked({ Invoke-W11Handler 'lnkLog.LinkClicked' })

    $script:BusyControls = @($ui.cbOs, $ui.btnIso, $ui.btnFetch, $ui.btnDownload, $ui.cbRelease, $ui.cbArch, $ui.chkAria2, $ui.btnEd, $ui.btnCheck, $ui.btnOsc, $ui.btnStart, $ui.btnOut, $ui.clbApps, $ui.clbTweaks)

    # ---------- events ----------
    $script:H['btnIso.Click'] = {
            $d = New-Object Windows.Forms.OpenFileDialog
            $d.Filter = T 'dlg.isoFilter'
            $d.Title = T 'dlg.isoTitle'
            $cur = $script:ui.tbIso.Text.Trim().Trim('"')
            if (Test-W11PathText $cur -Leaf) { $d.InitialDirectory = Split-Path -Parent $cur }
            if ($d.ShowDialog($script:ui.form) -eq 'OK') {
                $script:ui.tbIso.Text = $d.FileName
                $script:ui.rbLocal.Checked = $true
                if (-not $script:ui.tbOut.Text.Trim()) { $script:ui.tbOut.Text = Get-W11SuggestedOutput $d.FileName }
                Start-W11Detect $d.FileName
            }
        }
    $ui.btnIso.Add_Click({ Invoke-W11Handler 'btnIso.Click' })
    $script:H['btnOut.Click'] = {
            $d = New-Object Windows.Forms.SaveFileDialog
            $d.Filter = 'ISO (*.iso)|*.iso'
            $cur = $script:ui.tbOut.Text.Trim().Trim('"')
            if (-not $cur) { $cur = Get-W11SuggestedOutput $script:ui.tbIso.Text }
            $d.FileName = 'Windows_debloated.iso'
            if ($cur) {
                try {
                    $leaf = [IO.Path]::GetFileName($cur); if ($leaf) { $d.FileName = $leaf }
                    $dir = [IO.Path]::GetDirectoryName($cur); if (Test-W11PathText $dir -Container) { $d.InitialDirectory = $dir }
                } catch { $null = $_ }
            }
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
            $script:ui.lblStatus.Text = T 'status.loadingLangs' $e.Release
            [void](Start-W11Job -Name 'Load languages' -Script '$sync.Result = Update-MsEntryLanguages -Entry $JobArgs.Entry' -JobArgs @{ Entry = $e } -OnDone {
                    $r = $script:Sync.Result
                    if (-not $r) { $script:ui.lblStatus.Text = T 'status.langsFailed'; return }
                    Set-MsEntryLanguages -Catalog $script:Catalog -Result $r
                    Update-W11DownloadLists 'release'
                    if ($r.Ok) {
                        $script:ui.lblStatus.Text = T 'status.langsLoaded' (@($r.Skus).Count)
                        if (@($r.Hashes.Keys).Count -eq 0) { Write-W11Log -Level WARN -En 'Microsoft does not publish SHA256 values for this older release; the ISO hash will be logged so you can compare it yourself.' -Vi 'Microsoft không công bố SHA256 cho bản cũ này; mã SHA256 của ISO sẽ được ghi vào nhật ký để bạn tự đối chiếu.' }
                        if ($script:AutoDownload) { $script:AutoDownload = $false; & $script:H['btnDownload.Click'] }
                        return
                    }
                    $script:AutoDownload = $false
                    if ($r.NotOffered) { Show-W11NotOffered (Get-W11SelectedEntry); return }
                    $script:ui.lblStatus.Text = T 'status.langsFailed'
                    Show-W11MsFailure -Entry (Get-W11SelectedEntry) -Text (T 'msg.langsFailed' $r.Error) -Icon 'Warning'
                })
        }
    $ui.btnFetch.Add_Click({ Invoke-W11Handler 'btnFetch.Click' })
    $script:H['cbRelease.SelectedIndexChanged'] = { Update-W11DownloadLists 'arch' }
    $ui.cbRelease.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbRelease.SelectedIndexChanged' })
    $script:H['cbArch.SelectedIndexChanged'] = { Update-W11DownloadLists 'lang' }
    $ui.cbArch.Add_SelectedIndexChanged({ Invoke-W11Handler 'cbArch.SelectedIndexChanged' })

    $script:H['btnDownload.Click'] = {
            # needs only a download folder (never the Output ISO field)
            $e = Get-W11SelectedEntry
            if (-not $e) { return }
            if ($e.Available -eq $false) { Show-W11NotOffered $e; return }
            if ($e.Static -or @($e.Skus).Count -eq 0) {
                # languages not loaded yet: load them, then come back here
                $script:AutoDownload = $true
                & $script:H['btnFetch.Click']
                return
            }
            if ($script:ui.cbLang.SelectedIndex -lt 0) { Show-W11Msg (T 'msg.chooseLang') 'Warning' | Out-Null; return }
            $sku = $e.Skus[$script:ui.cbLang.SelectedIndex]
            $d = New-Object Windows.Forms.FolderBrowserDialog
            $d.Description = T 'dlg.dlFolder'
            $d.SelectedPath = Get-W11DownloadFolder $script:Settings
            if ($d.ShowDialog($script:ui.form) -ne 'OK') { return }
            $folder = [string]$d.SelectedPath
            if (-not (Test-W11PathText $folder -Container)) { Show-W11Msg (T 'msg.badFolder' $folder) 'Warning' | Out-Null; return }
            try { $free = Get-W11FreeGB -Path $folder } catch { $free = 999 }
            if ($free -lt 9) { Show-W11Msg (T 'msg.lowSpace' $free) 'Warning' | Out-Null; return }
            $script:Settings.DownloadFolder = $folder
            $null = Save-W11Settings $script:Settings
            $script:ui.rbDl.Checked = $true
            $script:LastDlEntry = $e
            $script:ui.lblStatus.Text = T 'status.requestLink'
            $opts = Get-MsAria2Options -Config $script:Cfg -Override @{ UseAria2 = [bool]($script:ui.chkAria2.Enabled -and $script:ui.chkAria2.Checked) }
            [void](Start-W11Job -Name 'Download' -Script '$sync.Result = Invoke-MsIsoDownload -Entry $JobArgs.Entry -Sku $JobArgs.Sku -Folder $JobArgs.Folder -Options $JobArgs.Options -Sync $sync' -JobArgs @{ Entry = $e; Sku = $sku; Folder = $folder; Options = $opts } -OnDone {
                if ($script:Sync.Error) {
                    $script:ui.lblStatus.Text = T 'status.dlFailed'
                    Show-W11MsFailure -Entry $script:LastDlEntry -Text (T 'msg.dlFailed' $script:Sync.Error) -Icon 'Error'
                    return
                }
                $iso = [string]$script:Sync.Result
                $script:ui.tbIso.Text = $iso
                $script:ui.rbLocal.Checked = $true
                if (-not $script:ui.tbOut.Text.Trim()) { $script:ui.tbOut.Text = Get-W11SuggestedOutput $iso }
                if ($script:LastDlEntry) { Set-W11Detected -Os $script:LastDlEntry.Os -Source 'download' -Build $script:LastDlEntry.Build; Start-W11Detect $iso }
                $script:ui.lblStatus.Text = T 'status.dlDone'
            })
        }
    $ui.btnDownload.Add_Click({ Invoke-W11Handler 'btnDownload.Click' })

    $script:H['btnEd.Click'] = {
            $iso = $script:ui.tbIso.Text.Trim().Trim('"')
            if (-not $iso) { Show-W11Msg (T 'msg.chooseIsoFirst') 'Warning' | Out-Null; return }
            if (-not (Test-W11PathText $iso -Leaf)) { Show-W11Msg (T 'msg.isoNotFound' $iso) 'Warning' | Out-Null; return }
            [void](Start-W11Job -Name 'List editions' -Script '$sync.Result = @(Get-W11IsoEditions -IsoPath $JobArgs.Iso)' -JobArgs @{ Iso = $iso } -OnDone { if (-not $script:Sync.Error) { $script:ui.lblStatus.Text = T 'status.editionsListed' } })
        }
    $ui.btnEd.Add_Click({ Invoke-W11Handler 'btnEd.Click' })

    $script:H['btnCheck.Click'] = {
            $wp = $env:TEMP
            $out = Resolve-W11FullPath $script:ui.tbOut.Text
            if ($out) { $dir = Get-W11ParentDir $out; if ($dir -and -not $dir.StartsWith('\\') -and (Test-W11PathText $dir -Container)) { $wp = $dir } }
            [void](Start-W11Job -Name 'System check' -Script '$null = Get-W11Capabilities -WorkPath $JobArgs.Work' -JobArgs @{ Work = $wp } -OnDone { $script:ui.lblStatus.Text = T 'status.checkDone' })
        }
    $ui.btnCheck.Add_Click({ Invoke-W11Handler 'btnCheck.Click' })

    $script:H['btnOsc.Click'] = {
            $p = Find-W11Oscdimg
            if ($p) { Show-W11Msg (T 'msg.oscReady' $p) | Out-Null; return }
            Invoke-W11OscInstall
        }
    $ui.btnOsc.Add_Click({ Invoke-W11Handler 'btnOsc.Click' })

    $script:H['btnCancel.Click'] = {
            $script:Sync.Cancel = $true
            Write-W11Log -Level WARN -En 'Cancel requested - downloads stop at once; ISO builds stop after the current step (DISM steps cannot be interrupted).' -Vi 'Đã yêu cầu huỷ - việc tải dừng ngay, còn tạo ISO sẽ dừng sau bước hiện tại.'
        }
    $ui.btnCancel.Add_Click({ Invoke-W11Handler 'btnCancel.Click' })

    $script:StartRun = {
        $ui = $script:ui
        $iso = ConvertTo-W11CleanPath $ui.tbIso.Text
        $out = ConvertTo-W11CleanPath $ui.tbOut.Text
        if (-not $iso) { Show-W11Msg (T 'msg.chooseIsoFirst') 'Warning' | Out-Null; return }
        $isoFull = Resolve-W11FullPath $iso
        if (-not $isoFull -or -not (Test-W11PathText $isoFull -Leaf)) { Show-W11Msg (T 'msg.isoNotFound' $iso) 'Warning' | Out-Null; return }
        $iso = $isoFull; $ui.tbIso.Text = $iso
        if (-not $out) { $out = Get-W11SuggestedOutput $iso; $ui.tbOut.Text = $out }
        $bad = Test-W11OutputPath -Out $out -Iso $iso
        if ($bad) { Show-W11Msg $bad 'Warning' | Out-Null; return }
        $out = Resolve-W11FullPath $out; $ui.tbOut.Text = $out
        $mode = 'All'; $idx = @()
        if ($ui.rbEdHP.Checked) { $mode = 'HomePro' }
        if ($ui.rbEdCustom.Checked) {
            $mode = 'Custom'
            foreach ($p in ($ui.tbIdx.Text -split '[,; ]+')) { if ($p -match '^\d+$') { $idx += [int]$p } }
            if ($idx.Count -eq 0) { Show-W11Msg (T 'msg.idxNeeded') 'Warning' | Out-Null; return }
        }
        $apps = @(); foreach ($i in $ui.clbApps.CheckedIndices) { $apps += $script:AppIds[$i] }
        $tw = @(); foreach ($i in $ui.clbTweaks.CheckedIndices) { $tw += $script:TweakIds[$i] }
        $targetOs = Get-W11EffectiveOs
        $osNote = Get-W11OsLabel $targetOs
        $useDefaults = ($ui.cbOs.SelectedIndex -eq 0 -and -not $script:DetectedOs)
        if ($useDefaults) { $targetOs = 'Auto'; $osNote = T 'os.autoNote' }
        $dry = $ui.chkDry.Checked
        if (-not $dry -and -not (Find-W11Oscdimg)) { Invoke-W11OscInstall -ThenStart; return }
        $yn = @{ $true = (T 'w.yes'); $false = (T 'w.no') }
        $summary = T 'msg.summary' $iso $out $osNote ("$mode $($idx -join ',')".Trim()) $apps.Count $tw.Count $yn[[bool]$ui.chkUnattend.Checked] $yn[[bool]$ui.chkCleanup.Checked] $yn[[bool]$dry]
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
                Show-W11Msg (T 'msg.failed' $script:Sync.Error) 'Error' | Out-Null
            } elseif ($r -and $r.DryRun) {
                Show-W11Msg (T 'msg.dryDone') | Out-Null
            } elseif ($r) {
                Show-W11Msg (T 'msg.done' $r.OutputIso $r.Sha256) | Out-Null
            }
        })
    }
    $script:H['btnStart.Click'] = { & $script:StartRun }
    $ui.btnStart.Add_Click({ Invoke-W11Handler 'btnStart.Click' })

    $f.Add_FormClosing({
            param($s, $e)
            if ($script:Job) {
                Show-W11Msg (T 'msg.jobRunning') 'Warning' | Out-Null
                $e.Cancel = $true
            }
        })

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 300
    $timer.Add_Tick({ Invoke-W11Tick })
    $timer.Start()

    $script:H['form.Shown'] = {
        Update-W11DownloadLists 'release'   # full release list; languages are loaded per release on demand
        Write-W11Log -En 'Welcome. 1) pick or download a Windows 10/11 ISO  2) check target OS, apps, options  3) START.' -Vi 'Xin chào. 1) chọn hoặc tải ISO Windows 10/11  2) kiểm tra hệ điều hành, ứng dụng, tuỳ chọn  3) BẮT ĐẦU.'
        if ($script:W11D.LogPath) { Write-W11Log -En "Log file: $($script:W11D.LogPath)" -Vi 'File nhật ký (gửi file này khi cần hỗ trợ)' }
        Write-W11Log -En ("WinDebloat Tool $($script:W11D.Version) | Host: Windows build $(Get-W11OsBuild), PowerShell $($PSVersionTable.PSVersion), CLR $($PSVersionTable.CLRVersion) | UI language: $($script:UiLang)")
        [void](Start-W11Job -Background -Name 'System check' -Script '$null = Get-W11Capabilities -WorkPath $JobArgs.Work' -JobArgs @{ Work = $env:TEMP })
    }
    $f.Add_Shown({ Invoke-W11Handler 'form.Shown' })
    [void]$f.ShowDialog()
    $timer.Stop()
}

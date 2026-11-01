# Newest-ISO check tests: version on the official page, live newest entries, merge into the release list,
# time limit / offline fallback, GUI selection (Advanced), Simple build, task time limit. Microsoft is mocked.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\MsDownload.ps1')
. (Join-Path $root 'lib\Gui.ps1')
$script:W11Root = $root
$script:fail = 0; $script:pass = 0
function Assert($cond, $msg) { if ($cond) { $script:pass++; Write-Host "PASS $msg" -ForegroundColor Green } else { $script:fail++; Write-Host "FAIL $msg" -ForegroundColor Red } }

function Initialize-MsDl { }
function ConvertFrom-MsJson { param([string]$Json) return ($Json | ConvertFrom-Json -AsHashtable) }
$script:MsDl.RetryDelaySec = 0
$origTimeout = $script:MsDl.TimeoutMs; $origRetry = $script:MsDl.RetryDelaySec
$script:net = @{ Pages = @{}; Skus = @{}; Fail = @(); Delay = 0 }
function Invoke-MsDlRequest {
    param([string]$Uri, [string]$Referer, [int]$TimeoutMs)
    if ($script:net.Delay) { Start-Sleep -Milliseconds $script:net.Delay }
    $h = ([Uri]$Uri).Host
    if ($h -eq 'vlscppe.microsoft.com') { return '' }
    if ($Uri -like '*mdt.js*') { return 'x?w=AB12&y rticks="+123' }
    if ($h -eq 'ov-df.microsoft.com') { return '' }
    foreach ($k in $script:net.Fail) { if ($Uri -like "*$k*") { throw "${h}: Timeout - The operation has timed out" } }
    if ($Uri -like '*getskuinformationbyproductedition*') {
        $null = $Uri -match 'productEditionId=(\d+)'
        if ($script:net.Skus.ContainsKey($Matches[1])) { return $script:net.Skus[$Matches[1]] }
        return '{"ValidationContainer":{"Errors":[]},"Skus":[]}'
    }
    foreach ($k in $script:net.Pages.Keys) { if ($Uri -like "*/$k") { return $script:net.Pages[$k] } }
    throw "unexpected request $Uri"
}
function New-Page([string]$Id, [string]$Option, [string]$Current, [string]$Extra = '') {
    return "<html><p>Windows 10, version 2004 notes</p><p>$Extra</p><p>&nbsp;&nbsp;(Current release: $Current)</p><select><option value="""">Select</option><option value=""$Id"">$Option</option></select><table><tr><td>English 64-bit</td><td>$('A' * 64)</td></tr></table></html>"
}
function New-Skus([string]$Display) {
    $l = @()
    $i = 1
    foreach ($n in @('English', 'German', 'Vietnamese')) { $l += ('{{"Id":"{0}","Language":"{1}","LocalizedLanguage":"{1}","ProductDisplayName":"{2}"}}' -f (27000 + $i), $n, $Display); $i++ }
    return ('{"ValidationContainer":{"Errors":[]},"Skus":[' + ($l -join ',') + ']}')
}
function Set-Net27H2 {
    $script:net = @{ Pages = @{}; Skus = @{}; Fail = @(); Delay = 0 }
    $script:net.Pages['windows11'] = New-Page '3900' 'Windows 11 (multi-edition ISO for x64 devices)' 'Windows 11 2027 Update l Version 27H2'
    $script:net.Pages['windows11arm64'] = New-Page '3901' 'Windows 11 (multi-edition ISO for Arm64)' 'Windows 11 2027 Update l Version 27H2'
    $script:net.Pages['windows10ISO'] = (New-Page '2618' 'Windows 10 (multi-edition ISO)' '' 'Windows 10 2023 Update | Version 22H2') -replace '\(Current release: \)', ''
    $script:net.Skus['3900'] = New-Skus 'Windows 11 Client - Build 26400.1000'
    $script:net.Skus['3901'] = New-Skus 'Windows 11 Client - Build 26400.1000'
    $script:net.Skus['2618'] = New-Skus 'Windows 10 22H2 v1'
}

# --- version on the official page ---
Set-Net27H2
$pi = Get-MsDlPageInfo -Url 'https://www.microsoft.com/en-us/software-download/windows11' -Fallback '3813'
$p10 = Get-MsDlPageInfo -Url 'https://www.microsoft.com/en-us/software-download/windows10ISO' -Fallback '2618'
Assert ($pi.Version -eq '27H2' -and $pi.PageRead -and @($pi.Editions)[0].Id -eq '3900' -and $pi.Hashes.Count -eq 1) 'page: "Current release ... Version 27H2" wins over other "version" text; edition id and SHA256 table read'
Assert ($p10.Version -eq '22H2') 'page: Windows 10 "2023 Update | Version 22H2" line'
$script:net.Fail = @('windows11')
$pf = Get-MsDlPageInfo -Url 'https://www.microsoft.com/en-us/software-download/windows11' -Fallback '3813'
Assert (-not $pf.PageRead -and $pf.Version -eq '' -and @($pf.Editions)[0].Id -eq '3813') 'page unreachable: fallback edition id, no version'
$fxPage = Get-MsDlPageInfo -Url 'https://x' -Fallback '3813'
Assert ($null -ne $fxPage) 'page info never throws'

# --- newest entries ---
Set-Net27H2
$lr = Get-MsLatestCatalog
$x64 = @($lr.Entries | Where-Object { $_.Os -eq 'Win11' -and $_.Arch -eq 'x64' })[0]
$w10 = @($lr.Entries | Where-Object { $_.Os -eq 'Win10' })
Assert (@($lr.Entries).Count -eq 4 -and @($lr.Errors).Count -eq 0 -and -not $lr.TimedOut) 'newest: one entry per OS / architecture (Win11 x64, arm64, Win10 x64, x86)'
Assert ($x64.EditionId -eq '3900' -and $x64.Release -eq 'Windows 11 27H2 (Build 26400.1000)' -and $x64.Build -eq 26400 -and $x64.Latest -and -not $x64.Static -and $x64.Available -and @($x64.Skus).Count -eq 3 -and $x64.Hashes.Count -eq 1 -and $x64.SessionId) 'newest: Win11 x64 = new edition 3900, version from the page, build from Microsoft, languages + SHA256 ready'
Assert ($w10.Count -eq 2 -and $w10[0].EditionId -eq '2618' -and $w10[0].Release -eq 'Windows 10 22H2' -and (@($w10 | ForEach-Object { $_.Arch }) -join ',') -eq 'x64,x86') 'newest: Windows 10 x64 + x86 share edition 2618 (no build in the answer -> version only)'
Assert ($script:MsDl.TimeoutMs -eq $origTimeout -and $script:MsDl.RetryDelaySec -eq $origRetry) 'newest: request time limits restored afterwards'

# --- merge into the release list ---
$base = @(Get-MsReleaseCatalog)
$cat = @(Merge-MsLatestCatalog -Catalog $base -Latest $lr.Entries)
$old = @($cat | Where-Object { $_.EditionId -eq '3813' })[0]
$w10m = @($cat | Where-Object { $_.Os -eq 'Win10' -and $_.EditionId -eq '2618' })
$firstW10 = 0; for ($i = 0; $i -lt $cat.Count; $i++) { if ($cat[$i].Os -eq 'Win10') { $firstW10 = $i; break } }
Assert ($cat.Count -eq $base.Count + 2 -and $cat[0].EditionId -eq '3900' -and $cat[1].EditionId -eq '3901' -and $cat[2].EditionId -eq '3813') 'merge: unknown editions 3900 / 3901 added at the top of the Windows 11 list'
Assert (-not $old.Latest -and $old.Static -and @($cat | Where-Object { $_.Latest }).Count -eq 4) 'merge: only the 4 newest entries carry the newest mark'
Assert ($w10m.Count -eq 2 -and $w10m[0].Latest -and @($w10m[0].Skus).Count -eq 3 -and $w10m[0].Release -eq 'Windows 10 22H2 v1 (Build 19045.2965, 2023-05)' -and -not $w10m[0].Static -and $firstW10 -gt 2 -and @($cat[0..($firstW10 - 1)] | Where-Object { $_.Os -ne 'Win11' }).Count -eq 0) 'merge: known edition 2618 gets the languages and keeps its name; Windows 11 entries stay before Windows 10'
# --- choosing the newest ---
Assert ((Select-MsLatestEntry -Catalog $cat -Os 'Win11' -Arch 'arm64').EditionId -eq '3901' -and (Select-MsLatestEntry -Catalog $cat -Os 'Win10' -Arch 'x86').Arch -eq 'x86' -and (Select-MsLatestEntry -Catalog $cat -Os 'Win11' -Arch 'x86').EditionId -eq '3900' -and $null -eq (Select-MsLatestEntry -Catalog @(Get-MsReleaseCatalog) -Os 'Win11' -Arch 'x64')) 'select: newest for OS + architecture, else the first newest of that OS, $null without a check'

$catX = @(Merge-MsLatestCatalog -Catalog @(Get-MsReleaseCatalog) -Latest $lr.Entries)
$cat2 = @(Merge-MsLatestCatalog -Catalog $catX -Latest @())
Assert ($cat2.Count -eq $catX.Count -and @($cat2 | Where-Object { $_.Latest }).Count -eq 0) 'merge with nothing: list unchanged, newest marks cleared'

# same edition, new build -> renamed; same build -> name kept
Set-Net27H2
$script:net.Pages['windows11'] = New-Page '3813' 'Windows 11 (multi-edition ISO for x64 devices)' 'Windows 11 2026 Update l Version 26H2'
$script:net.Skus['3813'] = New-Skus 'Windows 11 Client - Build 26300.9999'
$lr2 = Get-MsLatestCatalog -Os @('Win11')
$cat3 = @(Merge-MsLatestCatalog -Catalog @(Get-MsReleaseCatalog) -Latest $lr2.Entries)
$e3 = @($cat3 | Where-Object { $_.EditionId -eq '3813' })[0]
Assert ($cat3.Count -eq @(Get-MsReleaseCatalog).Count + 1 -and $e3.Release -eq 'Windows 11 26H2 (Build 26300.9999)' -and $e3.BuildFull -eq '26300.9999' -and $e3.Latest) 'merge: same edition with a newer build is renamed to the new build'
$script:net.Skus['3813'] = New-Skus 'Windows 11 Client - Build 26300.9457'
$cat4 = @(Merge-MsLatestCatalog -Catalog @(Get-MsReleaseCatalog) -Latest (Get-MsLatestCatalog -Os @('Win11')).Entries)
Assert ((@($cat4 | Where-Object { $_.EditionId -eq '3813' })[0]).Release -eq 'Windows 11 26H2 (Build 26300.9457, 2026-09)') 'merge: same build keeps the built-in name (with its date)'

# --- partial / offline / time limit ---
Set-Net27H2
$script:net.Fail = @('windows11arm64')
$lp = Get-MsLatestCatalog
Assert (@($lp.Entries).Count -eq 3 -and @($lp.Errors).Count -eq 1 -and $lp.Errors[0] -match 'arm64' -and -not $lp.TimedOut) 'one page fails: the others are still returned, the failure is reported'
$script:net.Fail = @('software-download')
$lo = $null; $thrown = $false
try { $lo = Get-MsLatestCatalog } catch { $thrown = $true }
Assert (-not $thrown -and @($lo.Entries).Count -eq 0 -and @($lo.Errors).Count -eq 3) 'offline: no entries, 3 errors, never throws'
Set-Net27H2
$script:net.Delay = 400
$sw = [Diagnostics.Stopwatch]::StartNew()
$lt = Get-MsLatestCatalog -TimeoutSec 3
$sw.Stop()
Assert ($lt.TimedOut -and @($lt.Entries).Count -ge 1 -and @($lt.Entries).Count -lt 4 -and (@($lt.Errors) -join ' ') -match 'time limit' -and $sw.ElapsedMilliseconds -lt 8000 -and $script:MsDl.TimeoutMs -eq $origTimeout) "time limit: remaining pages skipped, limits restored ($($sw.ElapsedMilliseconds) ms)"
$script:net.Delay = 0

# --- Simple build uses the newest release ---
$fnNames = @('Find-W11Oscdimg', 'Install-W11Oscdimg', 'Get-MsLatestCatalog', 'Update-MsEntryLanguages', 'Set-MsEntryLanguages', 'Invoke-MsIsoDownload', 'Invoke-Win11Debloat', 'New-W11Directory')
$saveFn = @{}; foreach ($n in $fnNames) { $saveFn[$n] = (Get-Item "function:$n").ScriptBlock }
$script:sim = @{ Calls = @(); Latest = @() }
function Find-W11Oscdimg { param([string]$Hint) return 'C:\ADK\oscdimg.exe' }
function Install-W11Oscdimg { param($Method) return 'C:\ADK\oscdimg.exe' }
function Get-MsLatestCatalog { param([string[]]$Os, [int]$TimeoutSec) $script:sim.Calls += "latest:$($Os -join ',')"; return (New-Object PSObject -Property @{ Entries = $script:sim.Latest; Errors = @('offline'); TimedOut = $false }) }
function Update-MsEntryLanguages { param($Entry) return (New-W11Obj @{ Ok = $true; EditionId = $Entry.EditionId; Skus = @((New-Object PSObject -Property @{ Id = '1'; Language = 'English'; LocalizedLanguage = 'English' })); Hashes = @{}; NotOffered = $false }) }
function Set-MsEntryLanguages { param($Catalog, $Result) }
function Invoke-MsIsoDownload { param($Entry, $Sku, $Folder, $Sync, $Options) $script:sim.Calls += "download:$($Entry.EditionId)"; return (Join-W11Path $Folder 'x.iso') }
function Invoke-Win11Debloat { $script:sim.Calls += 'build'; return (New-W11Obj @{ OutputIso = 'C:\o\x_debloated.iso'; Sha256 = 'AB'; DryRun = $false }) }
function New-W11Directory { param($Path) }
$pl = Get-W11SimplePlan -Os Win11 -UiLang en -OutputFolder 'C:\o' -HostArch amd64 -HostBuild 22631 -FreeGB 40
$r1 = Invoke-W11SimpleBuild -Plan $pl -Catalog @(Merge-MsLatestCatalog -Catalog @(Get-MsReleaseCatalog) -Latest $lr.Entries)
Assert ((@($script:sim.Calls) -join '>') -eq 'download:3900>build' -and $r1.Entry.EditionId -eq '3900') 'Simple: list from the newest-ISO button -> downloads the newest (3900), no second check'
$script:sim = @{ Calls = @(); Latest = @($lr.Entries) }
$r2 = Invoke-W11SimpleBuild -Plan $pl
Assert ((@($script:sim.Calls) -join '>') -eq 'latest:Win11>download:3900>build') 'Simple: without the button START checks the newest itself'
$script:sim = @{ Calls = @(); Latest = @() }
$r3 = Invoke-W11SimpleBuild -Plan $pl
Assert ((@($script:sim.Calls) -join '>') -eq 'latest:Win11>download:3813>build' -and -not $r3.DownloadFailed) 'Simple: check fails -> built-in newest (3813), no error'
$script:sim = @{ Calls = @(); Latest = @($lr.Entries) }
$r4 = Invoke-W11SimpleBuild -Plan $pl -DryRun
Assert (@($script:sim.Calls).Count -eq 0 -and $r4.Entry.EditionId -eq '3813') 'Simple dry run: no network check'
foreach ($n in $fnNames) { Set-Item "function:$n" $saveFn[$n] }

# --- Advanced window: newest entry selected after the check ---
Add-Type -TypeDefinition @'
using System; using System.Collections;
public class W11LatestCombo {
    public ArrayList Items = new ArrayList();
    int _i = -1;
    public event EventHandler SelectedIndexChanged;
    public int SelectedIndex { get { return _i; } set { _i = value; if (SelectedIndexChanged != null) SelectedIndexChanged(this, EventArgs.Empty); } }
    public object SelectedItem { get { return (_i >= 0 && _i < Items.Count) ? Items[_i] : null; } }
}
public class W11LatestLabel { public string Text = ""; }
'@
Set-W11Language 'en'
function New-TestUi {
    $u = @{ cbRelease = (New-Object W11LatestCombo); cbArch = (New-Object W11LatestCombo); cbLang = (New-Object W11LatestCombo); cbOs = (New-Object W11LatestCombo); lblStatus = (New-Object W11LatestLabel) }
    $u.cbRelease.add_SelectedIndexChanged({ Update-W11DownloadLists 'arch' })
    $u.cbArch.add_SelectedIndexChanged({ Update-W11DownloadLists 'lang' })
    foreach ($t in @('auto', 'Windows 11', 'Windows 10')) { [void]$u.cbOs.Items.Add($t) }
    return $u
}
$script:ui = New-TestUi; $script:ui.cbOs.SelectedIndex = 0; $script:DetectedOs = $null
$script:Catalog = @(Get-MsReleaseCatalog); $script:ReleaseItems = @()
Update-W11DownloadLists 'release'
$script:ui.cbArch.SelectedIndex = $script:ui.cbArch.Items.IndexOf('x64')
$script:LatestBox = @{ Result = $lr }
Complete-W11LatestCheck
$u = $script:ui
Assert ([string]$u.cbRelease.Items[$u.cbRelease.SelectedIndex] -eq 'Windows 11 27H2 (Build 26400.1000)  [newest]' -and [string]$u.cbArch.SelectedItem -eq 'x64' -and $u.cbLang.Items.Count -eq 3 -and [string]$u.cbLang.SelectedItem -eq 'English') 'Advanced: newest Windows 11 selected, marked [newest], languages ready for Download'
Assert ($u.lblStatus.Text -eq 'Newest: Windows 11 27H2 (Build 26400.1000)' -and $null -eq $script:LatestBox) 'Advanced: status shows the newest release'
$script:ui = New-TestUi; $script:ui.cbOs.SelectedIndex = 0
$script:Catalog = @(Get-MsReleaseCatalog); Update-W11DownloadLists 'release'
for ($i = 0; $i -lt $script:ReleaseItems.Count; $i++) { if ($script:ReleaseItems[$i] -like 'Windows 10 21H2*') { $script:ui.cbRelease.SelectedIndex = $i; break } }
$script:ui.cbArch.SelectedIndex = $script:ui.cbArch.Items.IndexOf('x86')
$script:LatestBox = @{ Result = $lr }
Complete-W11LatestCheck
Assert ((Get-W11SelectedEntry).Os -eq 'Win10' -and (Get-W11SelectedEntry).Arch -eq 'x86' -and (Get-W11SelectedEntry).Latest -and [string]$script:ui.cbArch.SelectedItem -eq 'x86') 'Advanced: an older Windows 10 x86 shown -> newest Windows 10 x86 selected'
$script:ui = New-TestUi; $script:ui.cbOs.SelectedIndex = 2
$script:Catalog = @(Get-MsReleaseCatalog); Update-W11DownloadLists 'release'
$script:ui.cbArch.SelectedIndex = $script:ui.cbArch.Items.IndexOf('x64')
$script:LatestBox = @{ Result = $lr }
Complete-W11LatestCheck
Assert ((Get-W11SelectedEntry).Os -eq 'Win10' -and (Get-W11SelectedEntry).Latest) 'Advanced: target OS set to Windows 10 -> newest Windows 10 selected even when Windows 11 was shown'
$script:ui = New-TestUi; $script:ui.cbOs.SelectedIndex = 1
$script:Catalog = @(Get-MsReleaseCatalog); $n0 = $script:Catalog.Count; Update-W11DownloadLists 'release'
$keep = Get-W11SelectedRelease
$script:LatestBox = @{ Result = $lo }
Complete-W11LatestCheck
Assert ($script:Catalog.Count -eq $n0 -and (Get-W11SelectedRelease) -eq $keep -and $script:ui.lblStatus.Text -eq (T 'status.latestFailed')) 'Advanced: check failed -> list and selection unchanged, status says so'
$script:Sync = [hashtable]::Synchronized(@{ LogQueue = [Collections.Queue]::Synchronized((New-Object Collections.Queue)); Error = 'no answer within the time limit' })
$script:LatestBox = @{ Result = $null }
$why = Get-W11LatestResult
Assert (@($why.Entries).Count -eq 0 -and $why.Why -match 'time limit') 'Advanced: stopped check -> fallback with the reason'

# --- task time limit in the UI timer ---
$script:Sync = [hashtable]::Synchronized(@{ LogQueue = [Collections.Queue]::Synchronized((New-Object Collections.Queue)); Cancel = $false; Error = $null; Result = $null; Percent = 0; Status = '' })
$script:ui = @{ tbLog = (New-Object Text.StringBuilder) | Add-Member -MemberType ScriptMethod -Name AppendText -Value { param($t) [void]$this.Append($t) } -PassThru; lblStatus = (New-Object W11LatestLabel) }
$script:Job = $null; $script:PendingJob = $null; $script:RulesJob = $null; $script:RulesReload = $false; $script:TickFailed = $false
$script:done = $null
$sw = [Diagnostics.Stopwatch]::StartNew()
$started = Start-W11Job -Background -Name 'Hang' -TimeoutMs 1500 -Script 'Start-Sleep -Seconds 60' -OnDone { $script:done = @{ Error = $script:Sync.Error; Ms = $sw.ElapsedMilliseconds } }
while (-not $script:done -and $sw.ElapsedMilliseconds -lt 30000) { Invoke-W11Tick; Start-Sleep -Milliseconds 100 }
Assert ($started -and $script:done -and $script:done.Error -eq 'no answer within the time limit' -and $script:done.Ms -lt 10000 -and $null -eq $script:Job -and -not $script:TickFailed) "task time limit: a hanging task is stopped and its OnDone runs ($($script:done.Ms) ms)"
$script:done = $null
$sw = [Diagnostics.Stopwatch]::StartNew()
$null = Start-W11Job -Background -Name 'Quick' -TimeoutMs 60000 -Script '$sync.Result = 42' -OnDone { $script:done = @{ Error = $script:Sync.Error; Result = $script:Sync.Result } }
while (-not $script:done -and $sw.ElapsedMilliseconds -lt 60000) { Invoke-W11Tick; Start-Sleep -Milliseconds 100 }
Assert ($script:done -and -not $script:done.Error -and $script:done.Result -eq 42) 'task time limit: a task that finishes in time is not touched'

# --- wiring ---
$gs = [IO.File]::ReadAllText((Join-Path $root 'lib\Gui.ps1'))
Assert ($gs -match "btnLatest = New-W11Ctl Button '@btn\.latest'" -and $gs -match "btnSLatest = New-W11Ctl Button '@simple\.latest'" -and $gs -match "btnLatest = 'sparkle'" -and $gs -match "btnSLatest = 'sparkle'") 'GUI: newest-ISO button in the Advanced and Simple windows, with icon'
Assert ($gs -match 'BusyControls = @\([^)]*\$ui\.btnLatest' -and $gs -match 'BusyControls = @\([^)]*\$ui\.btnSLatest' -and $gs -match "-TimeoutMs \(\(\`$script:W11LatestTimeoutSec \+ 15\) \* 1000\)") 'GUI: buttons disabled while a task runs; the check has a hard time limit'
$miss = @()
foreach ($l in @('en', 'vi', 'zh-CN', 'km')) { $t = Import-W11Lang $l; foreach ($k in @('btn.latest', 'item.latest', 'status.checkingLatest', 'status.latestDone', 'status.latestPartial', 'status.latestFailed', 'simple.latest', 'simple.latestFound', 'tip.latest', 'tip.simpleLatest')) { if (-not $t[$k]) { $miss += "$l/$k" } } }
Assert ($miss.Count -eq 0) "translations: newest-ISO texts in 4 languages ($($miss -join ','))"

Write-Host ''
Write-Host "Passed: $script:pass  Failed: $script:fail"
if ($script:fail -gt 0) { exit 1 }

# Simple mode local ISO tests: file check, image check, source choice in the Simple window, START with a
# local ISO (no download, no online check), texts in 4 languages. Runs without Windows (controls are mocked).
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\MsDownload.ps1')
. (Join-Path $root 'lib\Gui.ps1')
$script:W11Root = $root
$script:fail = 0; $script:pass = 0
function Assert($cond, $msg) { if ($cond) { $script:pass++; Write-Host "PASS $msg" -ForegroundColor Green } else { $script:fail++; Write-Host "FAIL $msg" -ForegroundColor Red } }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('w11-local-iso-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
function New-FakeIso([string]$Name, [string]$Id = 'CD001', [int]$Sector = 16, [int]$Bytes = 40960, [string]$Label = 'CCCOMA_X64FRE_EN-US_DV9') {
    $p = Join-Path $tmp $Name
    $b = New-Object byte[] $Bytes
    $o = $Sector * 2048
    if ($Id -and $o + 72 -le $Bytes) {
        $b[$o] = 1
        [Text.Encoding]::ASCII.GetBytes($Id).CopyTo($b, $o + 1)
        [Text.Encoding]::ASCII.GetBytes($Label.PadRight(32)).CopyTo($b, $o + 40)
    }
    [IO.File]::WriteAllBytes($p, $b)
    return $p
}

# --- file check ---
$minSave = $script:W11IsoMinBytes
$script:W11IsoMinBytes = 32KB
$ok = New-FakeIso 'Win11_24H2_English_x64.iso'
$udf = New-FakeIso 'udf.ISO' -Id 'NSR02' -Sector 17
$r = Test-W11IsoFile -Path $ok
Assert ($r.Ok -and $r.Reason -eq '' -and $r.Size -eq 40960 -and $r.Path -eq $ok -and $r.Label -eq 'CCCOMA_X64FRE_EN-US_DV9') 'file check: ISO 9660 descriptor -> accepted, full path, size and label'
Assert ((Test-W11IsoFile -Path $udf).Ok) 'file check: UDF descriptor (sector 17, upper-case .ISO) -> accepted'
Assert ((Test-W11IsoFile -Path ('"' + $ok + '"')).Ok) 'file check: quoted path (pasted from Explorer) accepted'
Assert ((Test-W11IsoFile -Path (Join-Path $tmp 'nope.iso')).Reason -eq 'missing' -and (Test-W11IsoFile -Path '').Reason -eq 'missing' -and (Test-W11IsoFile -Path $tmp).Reason -eq 'missing') 'file check: missing file, empty path, folder -> missing'
$txt = Join-Path $tmp 'notes.txt'; [IO.File]::WriteAllText($txt, 'x')
Assert ((Test-W11IsoFile -Path $txt).Reason -eq 'notIso') 'file check: other extension -> notIso'
Assert ((Test-W11IsoFile -Path (New-FakeIso 'zero.iso' -Id '')).Reason -eq 'notIso' -and (Test-W11IsoFile -Path (New-FakeIso 'short.iso' -Bytes 4096)).Reason -eq 'notIso') 'file check: renamed file without a volume descriptor / shorter than sector 16 -> notIso'
$script:W11IsoMinBytes = 1MB
Assert ((Test-W11IsoFile -Path $ok).Reason -eq 'tooSmall') 'file check: below the minimum size -> tooSmall'
$script:W11IsoMinBytes = $minSave
Assert ($script:W11IsoMinBytes -eq 1GB) 'file check: minimum size is 1 GB'
$script:W11IsoMinBytes = 32KB

# --- image check (Get-W11IsoOsInfo.HasImage) ---
$fnNames = @('Open-W11Iso', 'Close-W11Iso', 'Get-W11WimXmlInfo')
$saveFn = @{}; foreach ($n in $fnNames) { $saveFn[$n] = (Get-Item "function:$n").ScriptBlock }
$hadMount = [bool](Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)
if (-not $hadMount) { function global:Mount-DiskImage { } }
$isoRoot = Join-Path $tmp 'mnt'; New-Item -ItemType Directory -Path (Join-Path $isoRoot 'sources') -Force | Out-Null
function Open-W11Iso { param($IsoPath) return (New-W11Obj @{ Root = $isoRoot }) }
function Close-W11Iso { param($Iso, $IsoPath) }
function Get-W11WimXmlInfo { param($Path) return @((New-W11Obj @{ Name = 'Windows 11 Pro'; Build = 26100 })) }
$i1 = Get-W11IsoOsInfo -IsoPath (Join-Path $tmp 'linux.iso')
Assert ($i1.HasImage -eq $false -and -not $i1.Os) 'image check: ISO without sources\install.wim / .esd -> HasImage = false'
[IO.File]::WriteAllText((Join-Path $isoRoot (Join-Path 'sources' 'install.esd')), 'x')
$i2 = Get-W11IsoOsInfo -IsoPath (Join-Path $tmp 'renamed.iso')
Assert ($i2.HasImage -eq $true -and $i2.Os -eq 'Win11' -and $i2.Build -eq 26100 -and $i2.Source -eq 'image') 'image check: install.esd -> HasImage = true, Windows 11 26100 from the image'
function Open-W11Iso { param($IsoPath) throw 'mount failed' }
$i3 = Get-W11IsoOsInfo -IsoPath $ok
Assert ($null -eq $i3.HasImage -and $i3.Os -eq 'Win11' -and $i3.Source -eq 'filename') 'image check: mount failed -> not refused (HasImage = null), file-name guess'
foreach ($n in $fnNames) { Set-Item "function:$n" $saveFn[$n] }

# --- Simple window: source choice ---
Set-W11Language 'en'
function New-Ctl([hashtable]$P = @{}) { $h = @{ Text = ''; Enabled = $true; Visible = $true; Checked = $false; SelectedIndex = 0 }; foreach ($k in $P.Keys) { $h[$k] = $P[$k] }; return (New-Object PSObject -Property $h) }
$tipLog = @{}
$tip = New-Object PSObject | Add-Member -MemberType ScriptMethod -Name SetToolTip -Value { param($c, $t) $tipLog['last'] = $t } -PassThru
$script:ui = @{ rbSDl = (New-Ctl @{ Checked = $true }); rbSLocal = (New-Ctl); btnSIso = (New-Ctl); lblSIso = (New-Ctl); cbSLang = (New-Ctl); btnSLatest = (New-Ctl); lblSLatest = (New-Ctl); cbSOs = (New-Ctl); lblStatus = (New-Ctl); tip = $tip }
$script:Job = $null; $script:SimpleLocal = $null
$script:msgs = @()
function Show-W11Msg { param($Text, $Icon, $Buttons) $script:msgs += [string]$Text; return 'OK' }
$jobs = @()
function Start-W11Job { param([switch]$Background, $Name, $Script, $JobArgs, $OnDone, [int]$TimeoutMs) $script:lastJob = @{ Name = $Name; Script = $Script; Args = $JobArgs; Background = [bool]$Background }; return $true }

Update-W11SimpleSource
$u = $script:ui
Assert ($u.lblSIso.Text -eq (T 'simple.isoNone') -and $u.cbSLang.Enabled -and $u.btnSLatest.Enabled -and $u.lblSLatest.Visible) 'Simple: download chosen -> language and newest check available, "no ISO chosen" shown'
$bad = New-FakeIso 'bad.iso' -Id ''
Assert (-not (Set-W11SimpleLocalIso $bad) -and $null -eq $script:SimpleLocal -and -not $u.rbSLocal.Checked -and $script:msgs.Count -eq 1 -and $script:msgs[0] -like "*$bad*" -and $script:msgs[0] -like ('*' + (T 'iso.notIso') + '*')) 'Simple: not an ISO -> refused with the reason, nothing selected'
$script:lastJob = $null
$w10 = New-FakeIso 'Win10_22H2_English_x64.iso'
Assert ((Set-W11SimpleLocalIso $w10) -and $u.rbSLocal.Checked -and $script:SimpleLocal.Path -eq $w10 -and $script:SimpleLocal.Os -eq 'Win10' -and $u.cbSOs.SelectedIndex -eq 1) 'Simple: Windows 10 ISO chosen -> local source on, Windows 10 selected from the file name'
Assert (-not $u.cbSLang.Enabled -and -not $u.btnSLatest.Enabled -and -not $u.lblSLatest.Visible -and $tipLog['last'] -eq $w10) 'Simple: local source -> ISO language and newest check disabled, full path in the tooltip'
Assert ($script:lastJob -and $script:lastJob.Background -and $script:lastJob.Args.Iso -eq $w10 -and $script:lastJob.Script -match 'Get-W11IsoOsInfo' -and $script:SimpleLocal.Detecting -and $u.lblSIso.Text -eq (T 'simple.isoInfo' 'Win10_22H2_English_x64.iso' (Format-W11Size 40960) (T 'simple.isoChecking'))) 'Simple: image read in the background (window stays usable), info says "checking"'
Complete-W11SimpleDetect -Result (New-W11Obj @{ Os = 'Win11'; Build = 26100; Source = 'image'; HasImage = $true })
Assert (-not $script:SimpleLocal.Detecting -and $script:SimpleLocal.Os -eq 'Win11' -and $script:SimpleLocal.Build -eq 26100 -and $u.cbSOs.SelectedIndex -eq 0 -and $u.lblSIso.Text -like ('*' + (Get-W11ReleaseLabel -Build 26100 -Os 'Win11') + '*')) 'Simple: image says Windows 11 26100 -> overrides the file name, Windows 11 selected, shown next to the file'
$script:msgs = @()
Complete-W11SimpleDetect -Result (New-W11Obj @{ Os = $null; Build = 0; Source = 'unknown'; HasImage = $false })
Assert ($null -eq $script:SimpleLocal -and $script:msgs.Count -eq 1 -and $script:msgs[0] -like ('*' + (T 'iso.noImage') + '*') -and $u.lblSIso.Text -eq (T 'simple.isoNone')) 'Simple: ISO without a Windows image -> refused after the check, choice cleared'
$noName = New-FakeIso 'data.iso'
$null = Set-W11SimpleLocalIso $noName
Complete-W11SimpleDetect -Result (New-W11Obj @{ Os = $null; Build = 0; Source = 'unknown'; HasImage = $null })
Assert ($script:SimpleLocal -and -not $script:SimpleLocal.Os -and $u.lblSIso.Text -like ('*' + (T 'simple.isoUnknown') + '*')) 'Simple: version unknown (Windows 7 host / mount failed) -> kept, user picks Windows'
$u.rbSLocal.Checked = $false; $u.rbSDl.Checked = $true
Update-W11SimpleSource
Assert ($u.cbSLang.Enabled -and $u.btnSLatest.Enabled -and $script:SimpleLocal) 'Simple: back to download -> language and newest check on again, chosen file remembered for this session'
$script:Job = @{ Background = $false }; $u.rbSLocal.Checked = $true
Update-W11SimpleSource
Assert (-not $u.cbSLang.Enabled -and -not $u.btnSLatest.Enabled) 'Simple: while a task runs the source-dependent controls stay disabled'
$script:Job = $null
if (-not $hadMount) { Remove-Item function:global:Mount-DiskImage }
Assert ((Get-W11SimpleIsoText $null) -eq (T 'simple.isoNone') -and (Get-W11SimpleIsoText @{ Path = 'C:\i\a.iso'; Size = 5GB; Os = 'Win11'; Build = 0; Detecting = $false }) -eq ('a.iso  ({0}, {1})' -f (Format-W11Size 5GB), (Get-W11ReleaseLabel -Build 0 -Os 'Win11'))) 'Simple: info text = file name (size, Windows)'

# --- START with a local ISO ---
$fnNames = @('Find-W11Oscdimg', 'Install-W11Oscdimg', 'Get-MsLatestCatalog', 'Update-MsEntryLanguages', 'Invoke-MsIsoDownload', 'Invoke-Win11Debloat', 'New-W11Directory')
$saveFn = @{}; foreach ($n in $fnNames) { $saveFn[$n] = (Get-Item "function:$n").ScriptBlock }
$script:sim = @{ Calls = @(); Args = $null }
function Find-W11Oscdimg { param([string]$Hint) return 'C:\ADK\oscdimg.exe' }
function Install-W11Oscdimg { param($Method) return 'C:\ADK\oscdimg.exe' }
function Get-MsLatestCatalog { $script:sim.Calls += 'latest'; return (New-W11Obj @{ Entries = @(); Errors = @(); TimedOut = $false }) }
function Update-MsEntryLanguages { $script:sim.Calls += 'languages' }
function Invoke-MsIsoDownload { $script:sim.Calls += 'download'; return 'C:\d\x.iso' }
function Invoke-Win11Debloat { $script:sim.Calls += 'build'; $script:sim.Args = $args; $script:sim.Iso = $IsoPath; return (New-W11Obj @{ OutputIso = 'C:\o\x_debloated.iso' }) }
function New-W11Directory { param($Path) }
$pl = Get-W11SimplePlan -Os Win10 -UiLang vi -OutputFolder 'C:\o' -IsoPath 'D:\iso\Win10_22H2_Vietnamese_x64.iso' -HostArch amd64 -HostBuild 22631 -FreeGB 40
Assert ($pl.IsoPath -eq 'D:\iso\Win10_22H2_Vietnamese_x64.iso' -and @($pl.Steps) -notcontains 'download') 'START local: plan carries the ISO and has no download step'
$rb = Invoke-W11SimpleBuild -Plan $pl
Assert ((@($script:sim.Calls) -join '>') -eq 'build' -and $rb.IsoPath -eq 'D:\iso\Win10_22H2_Vietnamese_x64.iso' -and $rb.Stage -eq 'done' -and -not $rb.DownloadFailed -and $null -eq $rb.Entry) 'START local: no newest check, no language request, no download - straight to the build'
$script:sim = @{ Calls = @() }
$rd = Invoke-W11SimpleBuild -Plan $pl -DryRun
Assert ((@($script:sim.Calls) -join '>') -eq 'build' -and $rd.Stage -eq 'done') 'START local dry run: no network, build preview with the chosen ISO'
foreach ($n in $fnNames) { Set-Item "function:$n" $saveFn[$n] }
$script:W11IsoMinBytes = $minSave

# --- wiring ---
$gs = [IO.File]::ReadAllText((Join-Path $root 'lib\Gui.ps1'))
Assert ($gs -match "rbSDl = New-W11Ctl RadioButton '@simple\.srcDownload'" -and $gs -match "rbSLocal = New-W11Ctl RadioButton '@simple\.srcLocal'" -and $gs -match "btnSIso = New-W11Ctl Button '@btn\.browse'" -and $gs -match "btnSIso = 'folder-open'") 'GUI: Simple window has Download / local ISO choice and a Browse... button with icon'
Assert ($gs -match "Filter = T 'dlg\.isoFilter'" -and $gs -match "H\['btnSIso\.Click'\]" -and $gs -match "btnSIso\.Add_Click") 'GUI: Browse... opens a file dialog filtered to *.iso'
Assert ($gs -match "Get-W11SimplePlan[^\r\n]*-IsoPath \`$iso" -and $gs -match "msg\.simpleConfirmLocal" -and $gs -match 'SimpleHasDownload = \(-not \$Mirror -and -not \$Plan\.IsoPath\)') 'GUI: START passes the local ISO to the plan, confirms without a download, no download progress'
Assert ($gs -match 'BusyControls = @\(\$ui\.rbSDl, \$ui\.rbSLocal, \$ui\.btnSIso') 'GUI: source choice disabled while a task runs'

# --- translations ---
$keys = @('simple.source', 'simple.srcDownload', 'simple.srcLocal', 'simple.isoNone', 'simple.isoInfo', 'simple.isoChecking', 'simple.isoUnknown',
    'msg.simpleNoIso', 'msg.simpleIsoBad', 'msg.simpleConfirmLocal', 'iso.missing', 'iso.notIso', 'iso.tooSmall', 'iso.unreadable', 'iso.noImage')
$miss = @()
foreach ($l in @('en', 'vi', 'zh-CN', 'km')) {
    $t = Import-W11Lang $l
    foreach ($k in $keys) { if (-not $t[$k]) { $miss += "$l/$k" } }
    if ($t['msg.simpleConfirmLocal'] -notmatch '\{0\}' -or $t['msg.simpleConfirmLocal'] -notmatch '\{2\}' -or $t['simple.isoInfo'] -notmatch '\{2\}') { $miss += "$l/format" }
}
Assert ($miss.Count -eq 0) "translations: local ISO texts in 4 languages ($($miss -join ','))"
Assert ((Import-W11Lang 'vi')['simple.srcLocal'] -eq 'Chọn file ISO có sẵn') 'translations: Vietnamese wording'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host "Passed: $script:pass  Failed: $script:fail"
if ($script:fail -gt 0) { exit 1 }

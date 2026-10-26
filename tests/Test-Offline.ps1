# Offline unit tests for parsing / planning logic. External tools (dism, reg, web) are mocked,
# so this runs on pwsh anywhere (also Linux). It does NOT prove behaviour on real Windows.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$fx = Join-Path $root 'tests\fixtures'
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\MsDownload.ps1')
$script:fail = 0
function Assert($cond, $msg) { if ($cond) { Write-Host "PASS $msg" -ForegroundColor Green } else { Write-Host "FAIL $msg" -ForegroundColor Red; $script:fail++ } }
function Lines($f) { $l = New-Object Collections.ArrayList; foreach ($x in [IO.File]::ReadAllLines((Join-Path $fx $f))) { if ($x.Trim()) { [void]$l.Add($x.Trim()) } }; return , $l }

# --- dism output parsing (mock Invoke-W11Dism) ---
function Invoke-W11Dism { param([string]$Arguments, [switch]$Quiet, $ProgressBase, $ProgressSpan, $ProgressText, [switch]$NoThrow)
    if ($Arguments -match '/Get-ImageInfo .*/Index:(\d+)') { $f = 'dism_info_2.txt' }
    elseif ($Arguments -match '/Get-ImageInfo') { $f = 'dism_info_all.txt' }
    elseif ($Arguments -match '/Get-ProvisionedAppxPackages') { $f = 'dism_appx.txt' }
    else { $script:dismCalls += $Arguments; return (New-W11Obj @{ ExitCode = 0; Lines = (New-Object Collections.ArrayList) }) }
    return (New-W11Obj @{ ExitCode = 0; Lines = (Lines $f) })
}
$script:dismCalls = @()
$info = @(Get-W11ImageInfo -ImageFile 'X:\install.wim')
Assert ($info.Count -eq 2) 'Get-W11ImageInfo finds 2 indexes'
Assert ($info[1].EditionId -eq 'Professional' -and $info[1].DefaultLanguage -eq 'en-US' -and $info[1].Architecture -eq 'x64') 'edition/lang/arch parsed'
$apps = @(Get-W11ProvisionedApps -MountDir 'X:\m')
Assert ($apps.Count -eq 3 -and $apps[0].PackageName -like 'Clipchamp.Clipchamp_*') 'provisioned appx parsed'

$cfg = Get-W11Config
Assert ($info[1].Build -eq 26300) 'build parsed from dism Version line'
$p11 = Get-W11Profile -Config $cfg -Os Win11
$def = @($p11.Apps | Where-Object { $_.Default } | ForEach-Object { $_.Id })
# 0.3.1: four packages of the reference build are rated "unsafe" by Win11Debloat (Apps.json, checked 2026-10-25):
# listed but opt-in, so a default build keeps Store/game sign-in/troubleshooters working
$unsafe = @('Microsoft.GetHelp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay')
foreach ($fam in (Get-Content (Join-Path $root 'tests\fixtures\reference_families.txt'))) {
    if (-not $fam) { continue }
    if ($unsafe -contains $fam) { Assert (($def -notcontains $fam) -and @($p11.Apps | Where-Object { $_.Id -eq $fam -and $_.Name -match 'unsafe' }).Count -eq 1) "unsafe reference removal is listed but opt-in: $fam" }
    else { Assert ($def -contains $fam) "reference removal kept in defaults: $fam" }
}
$d10 = @((Get-W11Profile -Config $cfg -Os Win10).Apps | Where-Object { $_.Default } | ForEach-Object { $_.Id })
Assert (@($unsafe | Where-Object { $d10 -contains $_ }).Count -eq 0) 'Win10: unsafe packages not removed by default'
Assert (-not (Test-W11Like 'Microsoft.WindowsStore' $def)) 'Store not in removal list'
Assert (Test-W11Like 'Microsoft.WindowsStore' $cfg.Protected) 'Store protected'
Assert (Test-W11Like 'Microsoft.VCLibs.140.00.UWPDesktop' $cfg.Protected) 'VCLibs protected (wildcard)'

$script:W11D.Dism = 'mock'; $script:W11D.DismCanAppx = $true
$script:dismCalls = @()
Remove-W11AppsDism -MountDir 'X:\m' -Patterns $def -Protected $cfg.Protected
Assert ($script:dismCalls.Count -eq 2) 'DISM remove called for Clipchamp + XboxGamingOverlay only'
Assert (-not ($script:dismCalls | Where-Object { $_ -match 'WindowsStore' })) 'Store never removed'

# --- tweaks (mock reg) ---
$script:regCalls = @()
function Invoke-W11Reg { param([string]$Arguments) $script:regCalls += $Arguments; if ($Arguments -like 'query*') { return 0 }; return 0 }
Invoke-W11Tweaks -TweakDefs @($p11.Tweaks)
$adds = @($script:regCalls | Where-Object { $_ -like 'add *' })
$dels = @($script:regCalls | Where-Object { $_ -like 'delete *' })
Assert ($adds.Count -eq 28) "28 registry values written (got $($adds.Count))"
Assert ($dels.Count -eq 3) 'UScheduler_Oobe Outlook/DevHome/CrossDevice deleted'
Assert (@($adds | Where-Object { $_ -match 'W11D_SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE" /v "BypassNRO" /t REG_DWORD /d 1' }).Count -eq 1) 'BypassNRO=1 command'
Assert (@($adds | Where-Object { $_ -match 'W11D_DEFAULT\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced" /v "TaskbarMn"' }).Count -eq 1) 'TaskbarMn in default user hive'

# --- MS page parsing / hash matching ---
function Invoke-MsDlRequest { param([string]$Uri, [string]$Referer) return [IO.File]::ReadAllText((Join-Path $fx 'mspage.html')) }
$pi = Get-MsDlPageInfo -Url 'https://x' -Fallback '3813'
Assert (@($pi.Editions).Count -eq 1 -and $pi.Editions[0].Id -eq '3813') 'edition 3813 parsed from page'
Assert ($pi.Hashes.Count -eq 4) 'hash table parsed'
Assert ((Find-MsPublishedHash $pi.Hashes 'English' 'English (United States)') -eq 'BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650') 'English hash matched (= hash of the ISO used for the reference build)'
Assert ((Find-MsPublishedHash $pi.Hashes 'English International' 'English International') -like '7E3F*') 'English International hash matched'
Assert ((Find-MsPublishedHash $pi.Hashes 'Chinese (Simplified)' 'Chinese Simplified') -like '1111*') 'Chinese (Simplified) normalised'
Assert ((Get-MsIsoFileName 'https://software.download.prss.microsoft.com/dbazure/Win11_25H2_English_x64.iso?t=1&P1=2') -eq 'Win11_25H2_English_x64.iso') 'ISO file name from URL'

# --- misc ---
$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, 'abc')
Assert ((Get-W11Sha256 $tmp) -eq 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') 'SHA256 (SHA256Managed) correct'
$ua = [IO.Path]::GetTempFileName()
Write-W11Autounattend -Template (Join-Path $root 'autounattend.xml') -Destination $ua -Language 'de-DE' -Arch 'arm64'
$x = [IO.File]::ReadAllText($ua)
Assert ($x -match '<UILanguage>de-DE</UILanguage>' -and $x -notmatch 'processorArchitecture="amd64"' -and $x -match 'BypassNRO') 'autounattend language/arch rewrite'
[xml]$null = $x
Remove-Item $tmp, $ua
Assert ((Get-W11ArchName 'arm64') -eq 'arm64' -and (Get-W11ArchName 'x64') -eq 'amd64') 'arch mapping'

# ================= Windows 10 support =================
# --- OS detection from build / file name ---
Assert ((Resolve-W11OsFromBuild 19045) -eq 'Win10' -and (Resolve-W11OsFromBuild 19041) -eq 'Win10' -and (Resolve-W11OsFromBuild 10240) -eq 'Win10') 'builds 10240/19041/19045 -> Win10'
Assert ((Resolve-W11OsFromBuild 22000) -eq 'Win11' -and (Resolve-W11OsFromBuild 26300) -eq 'Win11') 'builds 22000/26300 -> Win11'
Assert ($null -eq (Resolve-W11OsFromBuild 9600) -and $null -eq (Resolve-W11OsFromBuild 0)) 'build 9600/0 -> unknown'
Assert ((Get-W11OsFromName 'D:\iso\Win10_22H2_English_x64v1.iso') -eq 'Win10') 'name Win10_22H2_English_x64v1.iso'
Assert ((Get-W11OsFromName 'Win11_25H2_English_x64.iso') -eq 'Win11') 'name Win11_25H2_English_x64.iso'
Assert ((Get-W11OsFromName 'Windows11_Client_x64_en-us_26300_9457.iso') -eq 'Win11') 'name Windows11_Client_..._26300'
Assert ((Get-W11OsFromName '19045.2965.230505-1139.22h2_release_CLIENT_x64FRE_en-us.iso') -eq 'Win10') 'name with build 19045'
Assert ($null -eq (Get-W11OsFromName 'my_backup.iso')) 'unknown name -> $null'

# --- WIM header XML reader (synthetic Windows 10 WIM) ---
function New-FakeWim($path, $xml) {
    $x = [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes($xml)
    $hdr = New-Object byte[] 208
    [Text.Encoding]::ASCII.GetBytes("MSWIM`0`0`0").CopyTo($hdr, 0)
    $sz = [BitConverter]::GetBytes([long]$x.Length); for ($i = 0; $i -lt 7; $i++) { $hdr[72 + $i] = $sz[$i] }
    $hdr[79] = 2
    [BitConverter]::GetBytes([long]4096).CopyTo($hdr, 80)
    $fs = [IO.File]::Create($path)
    $fs.Write($hdr, 0, 208); $fs.Write((New-Object byte[] (4096 - 208)), 0, 4096 - 208); $fs.Write($x, 0, $x.Length); $fs.Close()
}
$fw = [IO.Path]::GetTempFileName()
New-FakeWim $fw '<WIM><TOTALBYTES>1</TOTALBYTES><IMAGE INDEX="1"><NAME>Windows 10 Home</NAME><WINDOWS><ARCH>9</ARCH><EDITIONID>Core</EDITIONID><LANGUAGES><LANGUAGE>vi-VN</LANGUAGE><DEFAULT>vi-VN</DEFAULT></LANGUAGES><VERSION><MAJOR>10</MAJOR><MINOR>0</MINOR><BUILD>19045</BUILD></VERSION></WINDOWS></IMAGE><IMAGE INDEX="6"><NAME>Windows 10 Pro</NAME><WINDOWS><ARCH>0</ARCH><EDITIONID>Professional</EDITIONID><VERSION><BUILD>19045</BUILD></VERSION></WINDOWS></IMAGE></WIM>'
$wx = @(Get-W11WimXmlInfo -Path $fw)
Assert ($wx.Count -eq 2 -and $wx[0].Build -eq 19045 -and $wx[0].EditionId -eq 'Core' -and $wx[0].DefaultLanguage -eq 'vi-VN') 'WIM XML: build/edition/language'
Assert ($wx[1].Index -eq 6 -and $wx[1].Architecture -eq 'x86' -and $wx[0].Architecture -eq 'x64') 'WIM XML: index + arch mapping'
Assert ((Resolve-W11OsFromBuild $wx[0].Build) -eq 'Win10') 'synthetic Win10 WIM -> Win10'
[IO.File]::WriteAllBytes($fw, [Text.Encoding]::ASCII.GetBytes('not a wim at all' * 20))
$threw = $false; try { $null = Get-W11WimXmlInfo -Path $fw } catch { $threw = $true }
Assert $threw 'non-WIM file rejected'
Remove-Item $fw
if ($env:W11D_REAL_WIM -and (Test-Path -LiteralPath $env:W11D_REAL_WIM)) {
    $rw = @(Get-W11WimXmlInfo -Path $env:W11D_REAL_WIM)
    Write-Host ("     real WIM: " + (($rw | ForEach-Object { "$($_.Index):$($_.Name)/$($_.EditionId)/$($_.Build)/$($_.Architecture)/$($_.DefaultLanguage)" }) -join '; '))
    Assert ($rw.Count -ge 1 -and (Resolve-W11OsFromBuild $rw[0].Build)) "real WIM header parsed ($env:W11D_REAL_WIM)"
    $rl = Get-W11ReleaseLabel -Build $rw[0].Build
    Assert ($rl -match '^Windows 1[01] \S+ \(\d{5}\)$') "real WIM -> release label: $rl"
}

# --- Windows 10 profile ---
$p10 = Get-W11Profile -Config $cfg -Os Win10
$d10 = @($p10.Apps | Where-Object { $_.Default } | ForEach-Object { $_.Id })
$o10 = @($p10.Apps | Where-Object { -not $_.Default } | ForEach-Object { $_.Id })
foreach ($id in @('Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.MixedReality.Portal', 'Microsoft.People', 'Microsoft.SkypeApp', 'Microsoft.OneConnect', 'Microsoft.Wallet', 'Microsoft.Messaging', 'Microsoft.BingWeather', 'Microsoft.BingNews', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.YourPhone', 'Microsoft.WindowsFeedbackHub', 'Microsoft.549981C3F5F10', 'Clipchamp.Clipchamp', 'MicrosoftTeams')) {
    Assert ($d10 -contains $id) "Win10 default removal: $id"
}
foreach ($id in @('Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.WindowsMaps', 'Microsoft.MSPaint')) { Assert ($o10 -contains $id) "Win10 optional (unticked): $id" }
foreach ($id in @('Microsoft.WindowsStore', 'Microsoft.Windows.Photos', 'Microsoft.WindowsCalculator', 'Microsoft.WindowsNotepad', 'Microsoft.WindowsTerminal', 'Microsoft.ScreenSketch', 'Microsoft.StorePurchaseApp', 'Microsoft.VCLibs.140.00', 'Microsoft.UI.Xaml.2.4', 'Microsoft.NET.Native.Framework.2.2', 'Microsoft.DesktopAppInstaller', 'Microsoft.HEIFImageExtension', 'Microsoft.WebpImageExtension', 'Microsoft.VP9VideoExtensions', 'Microsoft.SecHealthUI')) {
    Assert ((-not (Test-W11Like $id $d10)) -and (Test-W11Like $id $p10.Protected)) "Win10 keeps + protects: $id"
}
Assert (@($p10.Apps | ForEach-Object { $_.Id } | Where-Object { Test-W11Like $_ $p10.Protected }).Count -eq 0) 'no Win10 app entry is also protected'
Assert (@($p11.Apps | ForEach-Object { $_.Id } | Where-Object { Test-W11Like $_ $p11.Protected }).Count -eq 0) 'no Win11 app entry is also protected'
$t10 = @($p10.Tweaks | ForEach-Object { $_.Id })
Assert ($t10 -notcontains 'BypassNRO' -and $t10 -notcontains 'TeamsChatAutoInstallOff') 'Win10 profile has no Win11-only tweaks'
Assert (@($p10.Tweaks | Where-Object { $_.Id -eq 'OneDriveSetupOff' })[0].Default -eq $false) 'OneDrive removal optional (unticked)'
$script:regCalls = @()
Invoke-W11Tweaks -TweakDefs @($p10.Tweaks)
$adds = @($script:regCalls | Where-Object { $_ -like 'add *' })
Assert (@($adds | Where-Object { $_ -match 'DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0' }).Count -eq 1) 'Win10 AllowTelemetry=0'
Assert (@($adds | Where-Object { $_ -match 'Windows Search" /v "DisableWebSearch" /t REG_DWORD /d 1' }).Count -eq 1) 'Win10 web search off'
Assert (@($adds | Where-Object { $_ -match 'W11D_SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer" /v "HideSCAMeetNow"' }).Count -eq 1) 'Win10 Meet Now hidden'
Assert (@($adds | Where-Object { $_ -match 'W11D_DEFAULT\\Software\\Microsoft\\Windows\\CurrentVersion\\Feeds" /v "ShellFeedsTaskbarViewMode" /t REG_DWORD /d 2' }).Count -eq 1) 'Win10 News and Interests hidden'
Assert (@($script:regCalls | Where-Object { $_ -match '^delete .*CurrentVersion\\Run" /v "OneDriveSetup" /f' }).Count -eq 1) 'OneDriveSetup Run value deleted (DeleteValue)'
Assert (@($adds | Where-Object { $_ -match 'BypassNRO' }).Count -eq 0) 'Win10: no BypassNRO in registry'

# --- autounattend per OS ---
$ua = [IO.Path]::GetTempFileName()
Write-W11Autounattend -Template (Join-Path $root 'autounattend.xml') -Destination $ua -Language 'en-US' -Arch 'x86' -Os 'Win10'
$x10 = [IO.File]::ReadAllText($ua); $d = New-Object Xml.XmlDocument; $d.LoadXml($x10)
$cmds = @($d.GetElementsByTagName('RunSynchronousCommand'))
$paths10 = @($d.GetElementsByTagName('Path') | ForEach-Object { $_.InnerText })
Assert ((@($paths10 | Where-Object { $_ -match 'BypassNRO' }).Count -eq 0) -and $cmds.Count -eq 1 -and [string]$cmds[0].Order -eq '1' -and $x10 -match 'DisableWindowsConsumerFeatures') 'Win10 autounattend: BypassNRO removed, order renumbered'
Assert ($x10 -match 'processorArchitecture="x86"' -and $x10 -match 'HideOnlineAccountScreens') 'Win10 autounattend: x86 + local account'
Write-W11Autounattend -Template (Join-Path $root 'autounattend.xml') -Destination $ua -Language 'en-US' -Arch 'amd64' -Os 'Win11'
$d.LoadXml([IO.File]::ReadAllText($ua))
Assert (@($d.GetElementsByTagName('Path') | Where-Object { $_.InnerText -match 'BypassNRO' }).Count -eq 1 -and @($d.GetElementsByTagName('RunSynchronousCommand')).Count -eq 2) 'Win11 autounattend keeps BypassNRO'
Remove-Item $ua

# --- Microsoft download flow with Windows 10 (endpoints mocked) ---
# pwsh-only stand-in for JavaScriptSerializer (the test suite runs on PowerShell 7; the tool itself does not use this)
function ConvertFrom-MsJson {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '')]
    param([string]$Json)
    return ($Json | ConvertFrom-Json -AsHashtable)
}
function New-MsDlSession { return 'sess-' + [guid]::NewGuid().ToString().Substring(0, 8) }
function Initialize-MsDl { }
function Invoke-MsDlRequest {
    param([string]$Uri, [string]$Referer)
    $f = $null
    if ($Uri -like '*software-download/windows10ISO') { $f = 'win10page.html' }
    elseif ($Uri -like '*software-download/windows11') { $f = 'mspage.html' }
    elseif ($Uri -like '*software-download/windows11arm64') { throw 'simulated: arm64 page unreachable' }
    elseif ($Uri -like '*getskuinformationbyproductedition*productEditionId=2618*') { $f = 'sku_win10.json' }
    elseif ($Uri -like '*getskuinformationbyproductedition*') { $f = 'sku_win11.json' }
    elseif ($Uri -like '*GetProductDownloadLinksBySku*') { $f = 'links_win10.json' }
    if (-not $f) { throw "unexpected URL $Uri" }
    return [IO.File]::ReadAllText((Join-Path $fx $f))
}
$cat = @(Get-MsWinCatalog)
$w10 = @($cat | Where-Object { $_.Os -eq 'Win10' })
$w11 = @($cat | Where-Object { $_.Os -eq 'Win11' })
Assert ($w10.Count -eq 2 -and (@($w10 | ForEach-Object { $_.Arch }) -join ',') -eq 'x64,x86') 'catalog: Windows 10 offers x64 + x86'
Assert ($w10[0].EditionId -eq '2618' -and $w10[0].Release -eq 'Windows 10 22H2 v1' -and $w10[0].SessionId -eq $w10[1].SessionId) 'catalog: Win10 edition 2618, release label, shared session'
Assert ($w11.Count -ge 2 -and $w11[0].Release -eq 'Windows 11 26H2 (Build 26300.9457)') 'catalog: Windows 11 still listed (arm64 page fell back to id 3816)'
Assert ((@($w11 | Where-Object { $_.Arch -eq 'arm64' })[0].EditionId) -eq '3816') 'arm64 fallback edition id'
$x86 = @($w10 | Where-Object { $_.Arch -eq 'x86' })[0]
$x64 = @($w10 | Where-Object { $_.Arch -eq 'x64' })[0]
Assert ((Get-MsIsoDownloadLink -Entry $x86 -SkuId '19002') -like '*x32v1.iso*') 'Win10 x86 link picked by DownloadType 0'
Assert ((Get-MsIsoDownloadLink -Entry $x64 -SkuId '19002') -like '*x64v1.iso*') 'Win10 x64 link picked by DownloadType 1'
Assert ((Find-MsPublishedHash $x64.Hashes 'English' 'English (United States)' 'x64') -like '*0064') 'Win10 hash: 64-bit row for x64'
Assert ((Find-MsPublishedHash $x86.Hashes 'English' 'English (United States)' 'x86') -like '*0032') 'Win10 hash: 32-bit row for x86'
Assert ((Find-MsPublishedHash @{ 'English  64-bit' = 'ARM' } 'English' 'English' 'arm64') -eq 'ARM') 'arm64 page label with double space'
Assert ((Get-MsReleaseLabel -Display 'Windows 10 Client - Build 19045.2965' -OsName 'Windows 10') -eq 'Windows 10 22H2 (Build 19045.2965)') 'release label from Win10 build'

# ================= 0.2.1: "Load list shows nothing" (vlscppe.microsoft.com not resolvable) =================
# Reload the real download module (the tests above replaced New-MsDlSession), keep only a network mock.
. (Join-Path $root 'lib\MsDownload.ps1')
function ConvertFrom-MsJson {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseCompatibleCommands', '')]
    param([string]$Json)
    $t = $Json.Trim(); if (-not $t.StartsWith('{')) { throw "Microsoft answered with something that is not JSON: $t" }
    return ($t | ConvertFrom-Json -AsHashtable)
}
function Initialize-MsDl { }
$script:W11D.Sync = $null
$script:logLines = New-Object Collections.ArrayList
function Write-W11Log { param([string]$En, [string]$Vi, [string]$Level = 'INFO') [void]$script:logLines.Add("[$Level] $En | $Vi") }
function Set-W11Progress { param($Percent, $Status) }
$script:MsDl.RetryDelaySec = 0
$script:Net = @{}      # host -> 'dns' (simulated resolve failure) ; key 'sku' -> fixture override ; 'links' -> fixture
$script:netLog = New-Object Collections.ArrayList
function Invoke-MsDlRequest {
    param([string]$Uri, [string]$Referer, [int]$TimeoutMs)
    $h = ([Uri]$Uri).Host
    [void]$script:netLog.Add($Uri)
    if ($script:Net[$h] -eq 'dns') { throw "${h}: NameResolutionFailure - The remote name could not be resolved: '$h'" }
    if ($h -eq 'vlscppe.microsoft.com') { return '' }
    if ($Uri -like 'https://ov-df.microsoft.com/mdt.js*') { return 'var a="https://ov-df.microsoft.com/?w=8DF31DFD0A&x=1";rticks="+1792854152655;' }
    if ($h -eq 'ov-df.microsoft.com') { return '' }
    if ($Uri -like '*software-download/windows10ISO') { return [IO.File]::ReadAllText((Join-Path $fx 'win10page.html')) }
    if ($Uri -like '*software-download/windows11arm64') { return '<select><option value="3816">Windows 11 (multi-edition ISO for Arm64 devices)</option></select>' }
    if ($Uri -like '*software-download/windows11') { return [IO.File]::ReadAllText((Join-Path $fx 'mspage.html')) }
    if ($Uri -like '*getskuinformationbyproductedition*') {
        if ($Uri -match 'productEditionId=(\d+)') { $ed = $Matches[1] }
        if ($script:Net['sku' + $ed]) { return $script:Net['sku' + $ed] }
        return [IO.File]::ReadAllText((Join-Path $fx "live_sku_$ed.json"))
    }
    if ($Uri -like '*GetProductDownloadLinksBySku*') { return [IO.File]::ReadAllText((Join-Path $fx $script:Net['links'])) }
    throw "unexpected URL $Uri"
}

# 1) exactly the user's failure: vlscppe.microsoft.com cannot be resolved
$script:Net = @{ 'vlscppe.microsoft.com' = 'dns'; links = 'links_win10.json' }
$script:logLines.Clear()
$cg = Get-MsCatalogForGui
$liveE = @($cg.Entries | Where-Object { -not $_.Static })
Assert ($cg.Live -eq 4 -and $liveE.Count -eq 4 -and -not $cg.Error) 'vlscppe DNS failure: list still loads (4 live entries, no error)'
Assert ((@($liveE | ForEach-Object { "$($_.Os)/$($_.Arch)" }) -join ',') -eq 'Win11/x64,Win11/arm64,Win10/x64,Win10/x86') 'vlscppe DNS failure: Win11 x64/arm64 + Win10 x64/x86'
Assert (@($liveE | Where-Object { $_.SessionState.Tags -eq $false -and $_.SessionState.OvDf -eq $true }).Count -eq 4) 'session state recorded (Tags failed, ov-df ok)'
Assert (@($script:logLines | Where-Object { $_ -like '`[WARN`] Session step 1 (vlscppe.microsoft.com) failed*could not be resolved*' }).Count -ge 1) 'vlscppe failure logged as WARN with the reason'
Assert (@($script:netLog | Where-Object { $_ -like '*getskuinformationbyproductedition*' }).Count -eq 3) 'SKU endpoint still called for 3813, 3816, 2618'
$w11 = @($liveE | Where-Object { $_.Os -eq 'Win11' })
Assert ($w11[0].Release -eq 'Windows 11 26H2 (Build 26300.9457)' -and $w11[1].Release -eq $w11[0].Release) 'real Microsoft SKU answers: x64 + ARM labels unified (26H2 Build 26300.9457)'
Assert ((@($liveE | Where-Object { $_.Os -eq 'Win10' })[0].Release) -eq 'Windows 10 22H2 v1') 'real Win10 display "22H2_v1" -> "Windows 10 22H2 v1"'
Assert ((@($w11[0].Skus | ForEach-Object { $_.Language }) -join ',') -eq 'Arabic,English') 'languages parsed from real answer'
$x86 = @($liveE | Where-Object { $_.Arch -eq 'x86' })[0]
Assert ((Get-MsIsoDownloadLink -Entry $x86 -SkuId '16067') -like '*x32v1.iso*') 'download link still works when only vlscppe is blocked'

# 2) vlscppe AND ov-df blocked: list loads, the link request is rejected with a clear explanation
$script:Net = @{ 'vlscppe.microsoft.com' = 'dns'; 'ov-df.microsoft.com' = 'dns'; links = 'live_sentinel.json' }
$cg = Get-MsCatalogForGui
Assert ($cg.Live -eq 4) 'vlscppe + ov-df blocked: list still loads'
$e1 = @($cg.Entries | Where-Object { $_.Arch -eq 'x64' -and $_.Os -eq 'Win11' })[0]
$msg = ''; try { $null = Get-MsIsoDownloadLink -Entry $e1 -SkuId '27160' } catch { $msg = $_.Exception.Message }
Assert ($msg -match 'Sentinel' -and $msg -match 'vlscppe\.microsoft\.com' -and $msg -match '1\.1\.1\.1' -and $msg -match 'đổi DNS') 'SentinelReject explains blocked hosts + DNS fix (EN + VI)'

# 3) SentinelReject with healthy session -> generic VPN/region hint
$script:Net = @{ links = 'live_sentinel.json' }   # hosts reachable, link still rejected (VPN / rate limit)
$e1.SessionState = @{ Tags = $true; OvDf = $true; Note = '' }
$script:netLog.Clear()
$msg = ''; try { $null = Get-MsIsoDownloadLink -Entry $e1 -SkuId '27160' } catch { $msg = $_.Exception.Message }
Assert ($msg -match 'VPN' -and $msg -notmatch 'cannot reach') 'SentinelReject with working session -> VPN/region hint'
Assert (@($script:netLog | Where-Object { $_ -like '*GetProductDownloadLinksBySku*' }).Count -eq 3 -and @($script:netLog | Where-Object { $_ -like '*getskuinformation*' }).Count -eq 2) 'Sentinel on link: 2 retries, each with a fresh session + SKU list'

# 4) www.microsoft.com unreachable: never throws, static list (4 choices) + error text
$script:Net = @{ 'vlscppe.microsoft.com' = 'dns'; 'ov-df.microsoft.com' = 'dns'; 'www.microsoft.com' = 'dns' }
$threw = $false; try { $cg = Get-MsCatalogForGui } catch { $threw = $true }
Assert (-not $threw -and $cg.Live -eq 0 -and @($cg.Entries).Count -eq 4 -and @($cg.Entries | Where-Object { $_.Static }).Count -eq 4) 'offline: static Win11 x64/arm64 + Win10 x64/x86 choices'
Assert ($cg.Error -match 'www\.microsoft\.com' -and $cg.Error -match 'could not be resolved') 'offline: error names the host and reason'
Assert (@($cg.Entries | Where-Object { -not $_.PageUrl }).Count -eq 0) 'static entries carry the official page URL (browser fallback)'

# 5) partial failure: arm64 SKU list refused -> arm64 shown as static, others live
$script:Net = @{ sku3816 = '{"ValidationContainer":{"Errors":[]},"Errors":[{"Key":"ErrorSettings.SentinelReject","Value":"Sentinel marked this request as rejected.","Type":8}]}' }
$cg = Get-MsCatalogForGui
$arm = @($cg.Entries | Where-Object { $_.Arch -eq 'arm64' })
Assert ($cg.Live -eq 3 -and $arm.Count -eq 1 -and $arm[0].Static) 'partial: arm64 falls back to the static entry'

# 6) blocked page instead of JSON (proxy / captive portal)
$script:Net = @{ sku3813 = '<html>Access denied</html>'; sku3816 = '<html>x</html>'; sku2618 = '<html>x</html>' }
$cg = Get-MsCatalogForGui
Assert ($cg.Live -eq 0 -and $cg.Error -match 'not JSON') 'HTML instead of JSON -> clear error, static list'

# ================= 0.3.0: release catalog, per-release languages =================
$rc = @(Get-MsReleaseCatalog)
Assert (@($rc | Where-Object { $_.Os -eq 'Win11' }).Count -eq 15 -and @($rc | Where-Object { $_.Os -eq 'Win10' }).Count -eq 36) 'release catalog: 15 Win11 entries (4 releases x64+arm64, 7 x64 only) + 36 Win10 (18 x64+x86)'
Assert (@($rc | Where-Object { $_.Static -and @($_.Skus).Count -eq 0 }).Count -eq $rc.Count -and @($rc | Where-Object { -not $_.Available }).Count -eq 1) 'release catalog: languages not loaded yet; one release not offered'
$e2360 = @($rc | Where-Object { $_.EditionId -eq '2360' })[0]
Assert ($e2360.Available -eq $false -and $e2360.Note -match 'use a local ISO' -and $e2360.Note -match 'HTTP 400' -and $e2360.ReleaseName -eq '22H2') '2360 (Win11 22H2 original, CDN HTTP 400) marked "no longer offered - use a local ISO"'
Assert (@($rc | Where-Object { $_.EditionId -eq '2370' -or $_.EditionId -eq '2616' -or $_.EditionId -eq '3813' } | Where-Object { $_.Available }).Count -eq 3) 'other 22H2 builds + 26H2 stay downloadable'
$r242 = @($rc | Where-Object { $_.ReleaseName -eq '24H2' -and $_.Arch -eq 'arm64' })[0]
Assert ($r242.EditionId -eq '3131' -and $r242.Build -eq 26100 -and $r242.PageUrl -like '*windows11arm64' -and $r242.DownloadType -eq 2) 'release catalog: 24H2 arm64 = edition 3131, build 26100, ARM page'
Assert ((@($rc | Where-Object { $_.Os -eq 'Win10' -and $_.ReleaseName -eq '1507' })[0]).Release -eq 'Windows 10 1507 (Build 10240.16384, 2015-07)') 'release catalog: label with build + date'
$script:Net = @{}
$e13 = @($rc | Where-Object { $_.EditionId -eq '3813' -and $_.Arch -eq 'x64' })[0]
$ur = Update-MsEntryLanguages -Entry $e13
Assert ($ur.Ok -and @($ur.Skus).Count -eq 2 -and $ur.Hashes.Count -eq 4) 'languages for 26H2: SKUs + published hashes (edition listed on the page)'
$script:Net = @{ sku2860 = [IO.File]::ReadAllText((Join-Path $fx 'live_sku_3813.json')) }
$e23 = @($rc | Where-Object { $_.EditionId -eq '2860' })[0]
$ur = Update-MsEntryLanguages -Entry $e23
Assert ($ur.Ok -and $ur.Hashes.Count -eq 0) 'older release (23H2 2860): languages ok, no hash table borrowed from the current release'
Set-MsEntryLanguages -Catalog $rc -Result $ur
Assert (-not $e23.Static -and @($e23.Skus).Count -eq 2 -and $e23.SessionId) 'Set-MsEntryLanguages fills the entry'
$script:Net = @{ sku2377 = [IO.File]::ReadAllText((Join-Path $fx 'live_sku_2618.json')) }
$e22 = @($rc | Where-Object { $_.EditionId -eq '2377' -and $_.Arch -eq 'x64' })[0]
Set-MsEntryLanguages -Catalog $rc -Result (Update-MsEntryLanguages -Entry $e22)
Assert (@($rc | Where-Object { $_.EditionId -eq '2377' -and -not $_.Static }).Count -eq 2) 'Win10: x64 + x86 share one edition, both filled'
$script:Net = @{ sku79 = '{"Skus":[],"Errors":[]}' }
$e07 = @($rc | Where-Object { $_.EditionId -eq '79' -and $_.Arch -eq 'x64' })[0]
$ur = Update-MsEntryLanguages -Entry $e07
Set-MsEntryLanguages -Catalog $rc -Result $ur
Assert ($ur.NotOffered -and -not $ur.Ok -and @($rc | Where-Object { $_.EditionId -eq '79' -and -not $_.Available }).Count -eq 2 -and $e07.Note -match 'use a local ISO' -and $e07.Note -match 'ISO có sẵn') 'withdrawn edition -> marked "no longer offers - use a local ISO" (x64 + x86)'
$script:Net = @{ sku1060 = [IO.File]::ReadAllText((Join-Path $fx 'live_sentinel.json')) }
$script:netLog.Clear()
$e18 = @($rc | Where-Object { $_.EditionId -eq '1060' -and $_.Arch -eq 'x64' })[0]
$threw = $false; try { $ur = Update-MsEntryLanguages -Entry $e18 } catch { $threw = $true }
Set-MsEntryLanguages -Catalog $rc -Result $ur
Assert (-not $threw -and -not $ur.Ok -and -not $ur.NotOffered -and $e18.Available -and $ur.Error -match 'Sentinel') 'Sentinel on languages: no throw, not marked withdrawn, error kept'
Assert (@($script:netLog | Where-Object { $_ -like '*getskuinformation*' }).Count -eq 6) 'Sentinel on languages: 2 rounds x 3 tries, fresh session per round'
# link: Sentinel once, then OK on the retry
$script:linkCalls = 0
$script:Net = @{ links = 'links_win10.json'; sku2377 = [IO.File]::ReadAllText((Join-Path $fx 'live_sku_2618.json')) }
$origReq = ${function:Invoke-MsDlRequest}
function Invoke-MsDlRequest {
    param([string]$Uri, [string]$Referer, [int]$TimeoutMs)
    if ($Uri -like '*GetProductDownloadLinksBySku*') { $script:linkCalls++; if ($script:linkCalls -eq 1) { return [IO.File]::ReadAllText((Join-Path $fx 'live_sentinel.json')) } }
    return (& $origReq -Uri $Uri -Referer $Referer -TimeoutMs $TimeoutMs)
}
$e10 = @($rc | Where-Object { $_.EditionId -eq '2377' -and $_.Arch -eq 'x86' })[0]
$lk = $null; try { $lk = Get-MsIsoDownloadLink -Entry $e10 -SkuId '16067' } catch { $lk = $_.Exception.Message }
Assert ($lk -like '*x32v1.iso*' -and $script:linkCalls -eq 2) 'link: Sentinel once -> new session -> link (x86 picked)'
# Type 9 (715-123130, IP / region / VPN block): no retry loop, clear message
$script:linkCalls = 0
function Invoke-MsDlRequest {
    param([string]$Uri, [string]$Referer, [int]$TimeoutMs)
    if ($Uri -like '*GetProductDownloadLinksBySku*') { $script:linkCalls++; return '{"Errors":[{"Key":"ErrorSettings.ErrorCode","Value":"715-123130","Type":9}]}' }
    return (& $origReq -Uri $Uri -Referer $Referer -TimeoutMs $TimeoutMs)
}
$m9 = ''; try { $null = Get-MsIsoDownloadLink -Entry $e10 -SkuId '16067' } catch { $m9 = $_.Exception.Message }
Assert ($script:linkCalls -eq 1 -and $m9 -match '715-123130' -and $m9 -match 'VPN') 'Type 9 on link: stops after one try with the VPN/region hint'
Set-Item function:Invoke-MsDlRequest $origReq
$script:Net = @{ sku2084 = '{"Errors":[{"Key":"ErrorSettings.ErrorCode","Value":"715-123130","Type":9}]}' }
$script:netLog.Clear()
$ur9 = Update-MsEntryLanguages -Entry (@($rc | Where-Object { $_.EditionId -eq '2084' })[0])
Assert (-not $ur9.Ok -and -not $ur9.NotOffered -and $ur9.Error -match '715-123130' -and @($script:netLog | Where-Object { $_ -like '*getskuinformation*' }).Count -eq 3) 'Type 9 on languages: one round only, not marked withdrawn'

# ================= 0.3.0: build -> release, version-aware profile =================
$pairs = @{ 10240 = '1507'; 10586 = '1511'; 14393 = '1607'; 15063 = '1703'; 16299 = '1709'; 17134 = '1803'; 17763 = '1809'; 18362 = '1903'; 18363 = '1909'; 19041 = '2004'; 19042 = '20H2'; 19043 = '21H1'; 19044 = '21H2'; 19045 = '22H2'; 22000 = '21H2'; 22621 = '22H2'; 22631 = '23H2'; 26100 = '24H2'; 26200 = '25H2'; 26300 = '26H2' }
$bad = @(); foreach ($b in $pairs.Keys) { if ((Get-W11ReleaseName $b) -ne $pairs[$b]) { $bad += "$b=$(Get-W11ReleaseName $b)" } }
Assert ($bad.Count -eq 0) "build -> release name for all 20 known builds $($bad -join ' ')"
Assert ((Get-W11ReleaseName 26400) -eq '26H2+' -and (Get-W11ReleaseName 19046) -eq '22H2+' -and $null -eq (Get-W11ReleaseName 9600) -and $null -eq (Get-W11ReleaseName 0)) 'unknown newer build -> "26H2+", Win8.1 / 0 -> none'
Assert ((Get-W11ReleaseLabel -Build 26100 -Os Win11) -eq 'Windows 11 24H2 (26100)' -and (Get-W11ReleaseLabel -Build 19045) -eq 'Windows 10 22H2 (19045)') 'release label "Windows 11 24H2 (26100)"'
Assert ((Test-W11ForBuild @{ MinBuild = 22621 } 22000) -eq $false -and (Test-W11ForBuild @{ MinBuild = 22621 } 22621) -and (Test-W11ForBuild @{ MaxBuild = 22631 } 26100) -eq $false -and (Test-W11ForBuild @{ MinBuild = 22621 } 0) -and (Test-W11ForBuild @{ Id = 'x' } 26100)) 'Test-W11ForBuild: Min/Max inclusive, unknown build = all'
$pa = Get-W11Profile -Config $cfg -Os Win11 -Build 22000
$ids = @($pa.Apps | ForEach-Object { $_.Id }); $tids = @($pa.Tweaks | ForEach-Object { $_.Id })
Assert (($ids -notcontains 'Clipchamp.Clipchamp') -and ($ids -notcontains 'Microsoft.OutlookForWindows') -and ($ids -notcontains 'Microsoft.Copilot') -and ($ids -contains 'Microsoft.549981C3F5F10') -and ($ids -contains 'Microsoft.People')) 'Win11 21H2 profile: no Clipchamp/Outlook/Copilot, has Cortana/People'
Assert (($tids -contains 'BypassNRO') -and ($tids -contains 'ChatTaskbarOff') -and ($tids -notcontains 'CopilotOff') -and @($pa.SkippedApps).Count -gt 0) 'Win11 21H2 tweaks: BypassNRO + Chat on, Copilot off-tweak hidden'
$pb = Get-W11Profile -Config $cfg -Os Win11 -Build 26100
$ids = @($pb.Apps | ForEach-Object { $_.Id }); $tids = @($pb.Tweaks | ForEach-Object { $_.Id })
Assert (($ids -notcontains 'Microsoft.549981C3F5F10') -and ($ids -contains 'Microsoft.Copilot') -and ($ids -contains 'Microsoft.OutlookForWindows') -and ($ids -contains 'Microsoft.Windows.DevHome') -and ($tids -notcontains 'ChatTaskbarOff') -and ($tids -contains 'CopilotOff')) 'Win11 24H2 profile: Copilot/Outlook/Dev Home, no Cortana, no Chat tweak'
Assert (@($pb.Apps | Where-Object { @('Microsoft.WindowsMaps', 'Microsoft.People', 'microsoft.windowscommunicationsapps', 'Microsoft.ZuneVideo') -contains $_.Id }).Count -eq 0) 'Win11 24H2 clean install: no Maps / People / Mail & Calendar / Movies & TV (Thurrott 24H2)'
$p23 = @((Get-W11Profile -Config $cfg -Os Win11 -Build 22631).Apps | ForEach-Object { $_.Id })
Assert (($p23 -contains 'Microsoft.WindowsMaps') -and ($p23 -contains 'Microsoft.People') -and ($p23 -contains 'Microsoft.ZuneVideo') -and ($p23 -contains 'MicrosoftTeams') -and ($p23 -contains 'MSTeams')) 'Win11 23H2: Maps / People / Movies & TV still listed; old (MicrosoftTeams) + new (MSTeams) Teams'
$p25 = @((Get-W11Profile -Config $cfg -Os Win11 -Build 26200).Apps | ForEach-Object { $_.Id })
Assert (($p25 -notcontains 'Microsoft.Windows.DevHome') -and ($p25 -notcontains 'MicrosoftTeams') -and ($p25 -contains 'MSTeams') -and ($p25 -contains 'Clipchamp.Clipchamp') -and ($p25 -contains 'Microsoft.Copilot')) 'Win11 25H2: Dev Home + old Teams gone; MSTeams, Clipchamp.Clipchamp, Microsoft.Copilot listed'
Assert (@($cfg.Apps + $cfg.Win10Apps | Where-Object { $_.Id -eq 'Microsoft.Clipchamp' -or $_.Id -eq 'Microsoft.Paint' }).Count -eq 0 -and (Test-W11Like 'Microsoft.Paint' $cfg.Protected)) 'package names: no Microsoft.Clipchamp; Microsoft.Paint (new Paint) protected, only Microsoft.MSPaint (Paint 3D) listed'
$pc = Get-W11Profile -Config $cfg -Os Win11 -Build 26200
Assert (@($pc.Apps | Where-Object { $_.Id -eq 'Microsoft.WindowsMaps' -or $_.Id -eq 'Microsoft.Windows.Ai.Copilot.Provider' }).Count -eq 0) 'Win11 25H2: Maps + old Copilot provider hidden'
$pd = Get-W11Profile -Config $cfg -Os Win10 -Build 15063
$ids = @($pd.Apps | ForEach-Object { $_.Id }); $tids = @($pd.Tweaks | ForEach-Object { $_.Id })
Assert (($ids -notcontains 'Microsoft.549981C3F5F10') -and ($ids -notcontains 'Microsoft.GamingApp') -and ($ids -contains 'Microsoft.3DBuilder') -and ($ids -contains 'Microsoft.Messaging') -and ($tids -notcontains 'NewsInterestsOff') -and ($tids -notcontains 'MeetNowOff')) 'Win10 1703 profile: no Cortana app/GamingApp/News/MeetNow, has 3D Builder/Messaging'
$pe = Get-W11Profile -Config $cfg -Os Win10
Assert (@($pe.Apps).Count -eq @($cfg.Win10Apps).Count -and @($pe.SkippedApps).Count -eq 0) 'unknown build: full list (nothing hidden)'
$script:logLines.Clear()
$ab = @(Write-W11AbsentPatterns -Patterns @('Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.People') -Names @('Microsoft.BingNews', 'Microsoft.WindowsStore'))
Assert ($ab.Count -eq 2 -and @($script:logLines | Where-Object { $_ -like '*not in this image (skipped): Clipchamp.Clipchamp, Microsoft.People*' }).Count -eq 1) 'packages missing from the image are skipped + logged'

# ================= 0.3.0: aria2 =================
$tr = Join-Path ([IO.Path]::GetTempPath()) ('w11a2_' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path (Join-Path $tr 'tools/aria2/x64'), (Join-Path $tr 'tools/aria2/x86') -Force
$saveRoot = $script:W11Root; $script:W11Root = $tr
$x86 = Join-Path (Join-Path (Join-Path $tr 'tools') 'aria2') 'x86'; $x64 = Join-Path (Join-Path (Join-Path $tr 'tools') 'aria2') 'x64'
Set-Content -LiteralPath (Join-Path $x86 'aria2c.exe') -Value 'x'
$origIs64 = ${function:Get-MsOsIs64}
function Get-MsOsIs64 { return $script:fake64 }
$script:fake64 = $true
Assert ((Find-MsAria2) -eq (Join-Path $x86 'aria2c.exe')) 'aria2 detect: only bundled x86 -> x86 (also fine on 64-bit)'
Set-Content -LiteralPath (Join-Path $x64 'aria2c.exe') -Value 'x'
Assert ((Find-MsAria2) -eq (Join-Path $x64 'aria2c.exe')) 'aria2 detect: 64-bit Windows -> bundled x64'
$script:fake64 = $false
Assert ((Find-MsAria2) -eq (Join-Path $x86 'aria2c.exe')) 'aria2 detect: 32-bit Windows -> bundled x86'
Set-Content -LiteralPath (Join-Path (Join-Path $tr 'tools') 'aria2c.exe') -Value 'x'
Assert ((Find-MsAria2) -eq (Join-Path (Join-Path $tr 'tools') 'aria2c.exe')) 'aria2 detect: tools\aria2c.exe overrides the bundled build'
$hint = Join-Path $tr 'my aria2c.exe'; Set-Content -LiteralPath $hint -Value 'x'
Assert ((Find-MsAria2 -Hint $hint) -eq $hint) 'aria2 detect: explicit path (Aria2Path) first'
Remove-Item -LiteralPath (Join-Path $tr 'tools') -Recurse -Force
$onPath = Get-Command aria2c.exe, aria2c -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($onPath) { Assert ((Find-MsAria2) -eq $onPath.Definition) 'aria2 detect: falls back to PATH' } else { Assert ($null -eq (Find-MsAria2)) 'aria2 detect: none -> $null' }
Set-Item function:Get-MsOsIs64 $origIs64
$script:W11Root = $saveRoot

$ao = Get-MsAria2Options -Config $cfg
Assert ($ao.UseAria2 -and $ao.Aria2Connections -eq 16 -and $ao.Aria2Split -eq 16 -and $ao.Aria2MinSplitSize -eq '1M' -and $ao.Aria2FileAllocation -eq 'none') 'aria2 options from DebloatConfig.psd1 (-x16 -s16 -k1M, allocation none)'
$ao2 = Get-MsAria2Options -Config $cfg -Override @{ Aria2Connections = 64; Aria2Split = 0; Aria2FileAllocation = 'bogus'; Aria2MinSplitSize = 'huge' }
Assert ($ao2.Aria2Connections -eq 16 -and $ao2.Aria2Split -eq 1 -and $ao2.Aria2FileAllocation -eq 'none' -and $ao2.Aria2MinSplitSize -eq '1M') 'aria2 options clamped / validated'
$al = @(Get-MsAria2Arguments -Uri 'https://dl.example/Win11.iso?t=1&P1=2' -Destination (Join-Path $tr 'Win11.iso') -Options (Get-MsAria2Options -Override @{ Aria2FileAllocation = 'falloc' }) -LogFile 'x.log' -ParentPid 4242)
foreach ($want in @('--max-connection-per-server=16', '--split=16', '--min-split-size=1M', '--continue=true', '--file-allocation=falloc', '--check-certificate=true', '--max-tries=5', '--retry-wait=5', '--summary-interval=1', '--human-readable=false', '--stop-with-process=4242', '--out=Win11.iso', '--log=x.log', '--auto-file-renaming=false')) {
    Assert ($al -contains $want) "aria2 argument $want"
}
Assert ($al[-1] -eq 'https://dl.example/Win11.iso?t=1&P1=2' -and @($al | Where-Object { $_ -like '--check-certificate=false*' }).Count -eq 0) 'aria2: URI last, certificates always checked'
Assert ((ConvertTo-MsCmdArg 'plain') -eq 'plain' -and (ConvertTo-MsCmdArg 'C:\My Dir\') -eq '"C:\My Dir\\"' -and (ConvertTo-MsCmdArg 'a"b') -eq '"a\"b"' -and (ConvertTo-MsCmdArg 'https://x/a.iso?t=1&P1=2') -eq '"https://x/a.iso?t=1&P1=2"' -and (ConvertTo-MsCmdArg '') -eq '""') 'command-line quoting (spaces, quotes, &, trailing backslash)'

$pl = ConvertFrom-MsAria2Line '[#847d8f 52428800B/6140975104B(0%) CN:16 DL:85983232B ETA:1m10s]'
Assert ($pl.Done -eq 52428800 -and $pl.Total -eq 6140975104 -and [math]::Round($pl.Percent, 2) -eq 0.85 -and $pl.Connections -eq 16 -and $pl.Speed -eq 85983232 -and $pl.Eta -eq '1m10s') 'aria2 progress line parsed (raw bytes)'
$pl = ConvertFrom-MsAria2Line ' *** [#2089b0 2.5GiB/5.7GiB(43%) CN:12 DL:82MiB ETA:39s]'
Assert ($pl.Total -eq [long](5.7 * 1GB) -and $pl.Speed -eq 82MB -and $pl.Connections -eq 12) 'aria2 progress line parsed (human-readable sizes)'
$pl = ConvertFrom-MsAria2Line '[#2089b0 0B/0B CN:1 DL:0B]'
Assert ($pl -and $pl.Total -eq 0 -and $pl.Percent -eq 0) 'aria2 progress before the size is known'
Assert ($null -eq (ConvertFrom-MsAria2Line '') -and $null -eq (ConvertFrom-MsAria2Line '*** Download Progress Summary as of Sat Oct 24 ***') -and $null -eq (ConvertFrom-MsAria2Line 'FILE: /x/Win11.iso') -and $null -eq (ConvertFrom-MsAria2Line '2b3c4d|OK  |  300MiB/s|/x/Win11.iso')) 'non-progress aria2 lines ignored'
$st = Format-MsAria2Status (ConvertFrom-MsAria2Line '[#847d8f 3221225472B/6442450944B(50%) CN:16 DL:104857600B ETA:30s]')
Assert ($st -match '3[.,]00 / 6[.,]00 GB' -and $st -match '100[.,]0 MB/s' -and $st -match ' x16 ' -and $st -match 'ETA 30s') "status line shows size, speed, connections: $st"

# mocked aria2 process -> success / failure -> fallback / cancel
function New-FakeAria2([string[]]$Out, [int]$Code, [bool]$Running = $false) {
    $o = New-Object PSObject -Property @{ StandardOutput = (New-Object IO.StringReader (($Out -join "`n") + "`n")); HasExited = (-not $Running); ExitCode = $Code; Killed = $false }
    $o | Add-Member -MemberType ScriptMethod -Name Kill -Value { $this.Killed = $true; $this.HasExited = $true; $script:a2Killed = $true }
    $o | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) return $true }
    return $o
}
$script:a2Plan = $null; $script:a2Calls = @(); $script:saveCalls = @(); $script:linkN = 0; $script:a2Killed = $false
function Start-MsAria2Process { param([string]$Exe, [string]$Arguments)
    $script:a2Calls += $Arguments
    $script:a2SawDest = Test-Path -LiteralPath $script:a2Dest
    if ($script:a2Plan.Code -eq 0) { Set-Content -LiteralPath $script:a2Dest -Value 'iso' }
    if ($script:a2Plan.Code -ne 0 -and $script:a2Plan.Control) { Set-Content -LiteralPath "$($script:a2Dest).aria2" -Value 'ctl' }
    return (New-FakeAria2 $script:a2Plan.Out $script:a2Plan.Code ([bool]$script:a2Plan.Running))
}
function Save-MsFile { param([string]$Uri, [string]$Destination, $Sync) $script:saveCalls += @{ Uri = $Uri; HadPartial = (Test-Path -LiteralPath "$Destination.partial") }; Set-Content -LiteralPath $Destination -Value 'iso'; return $Destination }
$origLink = ${function:Get-MsIsoDownloadLink}
function Get-MsIsoDownloadLink { param($Entry, $SkuId) $script:linkN++; return "https://dl.example/Win10_22H2_English_x64.iso?t=$($script:linkN)" }
$origSha = ${function:Get-W11Sha256}
function Get-W11Sha256 { param([string]$Path) return 'ABCDEF' }
$null = New-Item -ItemType Directory -Path $tr -Force
$fakeExe = Join-Path $tr 'aria2c.exe'; Set-Content -LiteralPath $fakeExe -Value 'x'
$script:a2Dest = Join-Path $tr 'Win10_22H2_English_x64.iso'
$dlEntry = New-Object PSObject -Property @{ Release = 'Windows 10 22H2'; Arch = 'x64'; Hashes = @{ 'English x64' = 'ABCDEF' }; EditionId = '2618'; DownloadType = 1 }
$dlSku = New-Object PSObject -Property @{ Id = '1'; Language = 'English'; LocalizedLanguage = 'English' }
$dlOpt = @{ UseAria2 = $true; Aria2Path = $fakeExe }
$prog = @('[#1 0B/0B CN:1 DL:0B]', '[#1 1073741824B/4294967296B(25%) CN:16 DL:52428800B ETA:1m]', '[#1 2147483648B/4294967296B(50%) CN:16 DL:104857600B ETA:20s]')

# success
$script:a2Plan = @{ Out = ($prog + @('', 'Download Results:', 'abc|OK  |  300MiB/s|x')); Code = 0 }
$sy = @{ Percent = 0; Status = ''; Cancel = $false }; $script:saveCalls = @(); $script:linkN = 0; $script:logLines.Clear()
$res = Invoke-MsIsoDownload -Entry $dlEntry -Sku $dlSku -Folder $tr -Sync $sy -Options $dlOpt
Assert ($res -eq $script:a2Dest -and $script:saveCalls.Count -eq 0 -and $sy.Percent -eq 50) 'aria2 success: progress reaches the GUI, no fallback'
Assert (@($script:logLines | Where-Object { $_ -like '*SHA256 matches*' }).Count -eq 1) 'aria2 success: SHA256 still verified'
Assert (($script:a2Calls[-1] -match '\?<signed>') -eq $false -and @($script:logLines | Where-Object { $_ -like '*aria2: *?<signed>*' -and $_ -notlike '*.iso?t=1*' }).Count -eq 1) 'aria2 command logged with the signed query hidden'
$sy2 = @{ Percent = 0; Status = ''; Cancel = $false }
$null = Invoke-MsAria2Download -Exe $fakeExe -Uri 'https://dl.example/a.iso' -Destination $script:a2Dest -Options $dlOpt -Sync $sy2
Assert ($sy2.Status -like 'aria2: 2*/ 4*GB (50*%)*100*MB/s*x16*ETA 20s') "speed + connections in the status line: $($sy2.Status)"
Remove-Item -LiteralPath $script:a2Dest -Force

# failure (403 -> exit 22) -> fallback to the built-in downloader with a fresh link
$script:a2Plan = @{ Out = @('10/24 12:00:00 [ERROR] CUID#7 - Download aborted. URI=https://dl.example/x', 'errorCode=22 The response status is not successful. status=403'); Code = 22; Control = $true }
$sy = @{ Percent = 0; Status = ''; Cancel = $false }; $script:saveCalls = @(); $script:linkN = 0; $script:logLines.Clear()
$res = Invoke-MsIsoDownload -Entry $dlEntry -Sku $dlSku -Folder $tr -Sync $sy -Options $dlOpt
Assert ($res -eq $script:a2Dest -and $script:saveCalls.Count -eq 1 -and $script:saveCalls[0].Uri -like '*t=2') 'aria2 exit 22 (HTTP 403) -> built-in downloader with a fresh link'
Assert (@($script:logLines | Where-Object { $_ -like '`[WARN`]*exit code 22*built-in downloader*' }).Count -eq 1 -and -not (Test-Path -LiteralPath "$($script:a2Dest).aria2")) 'fallback logged as WARN; aria2 control file removed'
Assert (@($script:logLines | Where-Object { $_ -like '*SHA256 matches*' }).Count -eq 1) 'fallback: SHA256 still verified'
Remove-Item -LiteralPath $script:a2Dest -Force

# earlier .partial: aria2 continues it; aria2 fails before writing a control file -> .partial kept for the fallback resume
Set-Content -LiteralPath "$($script:a2Dest).partial" -Value 'half'
$script:a2Plan = @{ Out = @(); Code = 6; Control = $false }
$script:saveCalls = @(); $script:logLines.Clear()
$res = Invoke-MsIsoDownload -Entry $dlEntry -Sku $dlSku -Folder $tr -Sync @{ Percent = 0; Status = ''; Cancel = $false } -Options $dlOpt
Assert ($script:a2SawDest -and $script:saveCalls.Count -eq 1 -and $script:saveCalls[0].HadPartial) '.partial handed to aria2, and back to the built-in resume when aria2 fails'
Remove-Item -LiteralPath $script:a2Dest -Force

# cancel: aria2 killed, no fallback, OperationCanceledException
$script:a2Plan = @{ Out = $prog; Code = 7; Running = $true; Control = $true }
$sy = @{ Percent = 0; Status = ''; Cancel = $true }; $script:saveCalls = @(); $script:a2Killed = $false
$ex = $null; try { $null = Invoke-MsIsoDownload -Entry $dlEntry -Sku $dlSku -Folder $tr -Sync $sy -Options $dlOpt } catch { $ex = $_.Exception }
Assert ($ex -is [System.OperationCanceledException] -and $script:a2Killed -and $script:saveCalls.Count -eq 0 -and (Test-Path -LiteralPath "$($script:a2Dest).aria2")) 'Cancel kills aria2c, no fallback, control file kept for resume'
Remove-Item -LiteralPath "$($script:a2Dest).aria2" -Force -ErrorAction SilentlyContinue

# aria2 off / missing -> built-in downloader directly
$script:a2Calls = @(); $script:saveCalls = @()
$res = Invoke-MsIsoDownload -Entry $dlEntry -Sku $dlSku -Folder $tr -Sync @{ Percent = 0; Status = ''; Cancel = $false } -Options @{ UseAria2 = $false }
Assert ($script:a2Calls.Count -eq 0 -and $script:saveCalls.Count -eq 1) 'checkbox off -> built-in downloader only'
Remove-Item -LiteralPath $script:a2Dest -Force

Remove-Item function:Start-MsAria2Process, function:Save-MsFile
Set-Item function:Get-W11Sha256 $origSha
. (Join-Path $root 'lib\MsDownload.ps1')   # restore the real download functions (keeps the mocked network)
$script:MsDl.RetryDelaySec = 0
Set-Item function:Get-MsIsoDownloadLink $origLink

# optional: real aria2c against a local Range server (Linux CI box / Windows with aria2 + python)
$realA2 = Get-Command aria2c, aria2c.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$py = Get-Command python3, python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($realA2 -and $py -and $env:W11D_ARIA2_IT -ne '0') {
    $sd = Join-Path $tr 'srv'; $null = New-Item -ItemType Directory -Path $sd -Force
    $data = New-Object byte[] (24MB); (New-Object Random 7).NextBytes($data); [IO.File]::WriteAllBytes((Join-Path $sd 'test.iso'), $data)
    $want = (Get-W11Sha256 -Path (Join-Path $sd 'test.iso'))
    function Start-RangeServer([int]$Port, [string]$Mode) {
        $psi = New-Object Diagnostics.ProcessStartInfo $py.Definition, ('"{0}" "{1}" {2} 0 {3}' -f (Join-Path $root 'tests/tools/range_server.py'), $sd, $Port, $Mode)
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi); Start-Sleep -Milliseconds 700; return $p
    }
    $port = 18000 + (Get-Random -Maximum 900)
    $srv = Start-RangeServer $port 'ok'
    $dst = Join-Path $tr 'it/test.iso'; $null = New-Item -ItemType Directory -Path (Split-Path $dst) -Force
    $sy = @{ Percent = 0; Status = ''; Cancel = $false }
    $ok = $null; try { $ok = Invoke-MsAria2Download -Exe $realA2.Definition -Uri "http://127.0.0.1:$port/test.iso?t=1" -Destination $dst -Options (Get-MsAria2Options) -Sync $sy } catch { $ok = $_.Exception.Message }
    Assert ($ok -eq $dst -and (Get-W11Sha256 -Path $dst) -eq $want) "real aria2c: 16-connection download, file identical ($ok)"
    $srv.Kill(); $srv.WaitForExit()
    $srv = Start-RangeServer $port '403'
    $code = $null; try { $null = Invoke-MsAria2Download -Exe $realA2.Definition -Uri "http://127.0.0.1:$port/test.iso" -Destination (Join-Path $tr 'it/b.iso') -Options (Get-MsAria2Options -Override @{ Aria2MaxTries = 1 }) -Sync @{ Cancel = $false } } catch { $code = $_.Exception.Data['Aria2ExitCode']; $m403 = $_.Exception.Message }
    Assert ($code -eq 22 -and $m403 -match 'exit code 22') "real aria2c: HTTP 403 -> exit code 22 ($m403)"
    $srv.Kill(); $srv.WaitForExit()
} else { Write-Host 'SKIP real aria2c integration test (aria2c or python not found)' }
Remove-Item -LiteralPath $tr -Recurse -Force -ErrorAction SilentlyContinue

# 7) GUI background job path: job text runs in a runspace, results + log lines cross back, errors are logged with details
. (Join-Path $root 'lib\Gui.ps1')
$prelude = @'
function ConvertFrom-MsJson { param([string]$Json) return ($Json | ConvertFrom-Json -AsHashtable) }
function Initialize-MsDl { }
$script:MsDl.RetryDelaySec = 0
function Invoke-MsDlRequest {
    param([string]$Uri, [string]$Referer, [int]$TimeoutMs)
    $h = ([Uri]$Uri).Host
    if ($h -eq 'vlscppe.microsoft.com') { throw "The remote name could not be resolved: '$h'" }
    if ($Uri -like '*mdt.js*') { return 'x?w=AB12&y rticks="+123' }
    if ($h -eq 'ov-df.microsoft.com') { return '' }
    if ($Uri -like '*getskuinformationbyproductedition*') { $null = $Uri -match 'productEditionId=(\d+)'; return [IO.File]::ReadAllText((Join-Path $JobArgs.Fx "live_sku_$($Matches[1]).json")) }
    return '<html></html>'
}
'@
function Invoke-TestJob([string]$Script, [string]$LogPath) {
    $sync = [hashtable]::Synchronized(@{ LogQueue = [Collections.Queue]::Synchronized((New-Object Collections.Queue)); Error = $null; Result = $null; Percent = 0; Status = '' })
    $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
    $rs.SessionStateProxy.SetVariable('sync', $sync); $rs.SessionStateProxy.SetVariable('JobArgs', @{ Fx = $fx })
    $rs.SessionStateProxy.SetVariable('W11RootPath', $root); $rs.SessionStateProxy.SetVariable('W11LogPath', $LogPath)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript((Get-W11JobText -Script $Script -Root $root -Prelude $prelude))
    [void]$ps.Invoke(); $ps.Dispose(); $rs.Close()
    return $sync
}
$lp = [IO.Path]::GetTempFileName()
$js = Invoke-TestJob '$sync.Result = Get-MsCatalogForGui' $lp
$logTxt = [IO.File]::ReadAllText($lp)
Assert (-not $js.Error -and $js.Result.Live -eq 4 -and @($js.Result.Entries).Count -eq 4) 'runspace: Load list job returns 4 live entries despite vlscppe failure'
Assert ($js.LogQueue.Count -gt 3 -and $logTxt -match 'vlscppe\.microsoft\.com' -and $logTxt -match 'Querying Microsoft') 'runspace: progress + warnings reach the GUI queue and the log file'
Assert ($js.Status -like 'Microsoft list done*') 'runspace: status text updated for the status label'
$js = Invoke-TestJob '$sync.Result = Update-MsEntryLanguages -Entry (@(Get-MsReleaseCatalog) | Where-Object { $_.EditionId -eq ''3816'' })[0]' $lp
Assert (-not $js.Error -and $js.Result.Ok -and @($js.Result.Skus).Count -ge 1 -and $js.Result.EditionId -eq '3816') 'runspace: "Languages" job for one release (GUI button path)'
$js = Invoke-TestJob 'throw "boom from job"' $lp
$logTxt = [IO.File]::ReadAllText($lp)
Assert ($js.Error -eq 'boom from job' -and $logTxt -match '\[ERROR\] boom from job' -and $logTxt -match 'RuntimeException') 'runspace: job exception -> $sync.Error + details in log'
Remove-Item $lp

# 8) v0.3.2: empty paths (real-Windows crash), i18n files, settings, fonts, mirror fallback
$script:W11Root = $root
# Windows PowerShell 2.0-5.1 refuse '' for -LiteralPath (the v0.3.1 crash); PowerShell 7 only does so for Get-Item
$crash = $null
try { if ($PSVersionTable.PSVersion.Major -le 5) { $null = Test-Path -LiteralPath '' } else { $null = Get-Item -LiteralPath '' } } catch { $crash = $_.Exception.Message }
Assert ($crash -match 'empty string') "repro: empty -LiteralPath throws ($crash)"
$tp = Join-Path ([IO.Path]::GetTempPath()) ('w11p_' + [guid]::NewGuid().ToString('N')); $null = New-Item -ItemType Directory -Path $tp -Force
$tf = Join-Path $tp 'Win11_26H2.iso'; [IO.File]::WriteAllText($tf, 'iso-bytes')
$noThrow = $true; $r = @()
try { $r = @((Test-W11PathText ''), (Test-W11PathText '   '), (Test-W11PathText $null), (Test-W11PathText '""'), (Test-W11PathText "bad`0path"), (Test-W11PathText '' -Leaf), (Test-W11PathText '' -Container)) } catch { $noThrow = $false }
Assert ($noThrow -and @($r | Where-Object { $_ }).Count -eq 0) 'Test-W11PathText: empty / blank / quoted-empty / invalid -> $false, never throws'
Assert ((Test-W11PathText $tf -Leaf) -and (Test-W11PathText ('"' + $tf + '" ') -Leaf) -and -not (Test-W11PathText $tf -Container) -and (Test-W11PathText $tp -Container) -and -not (Test-W11PathText (Join-Path $tp 'nope.iso') -Leaf)) 'Test-W11PathText: file / folder / quotes / missing'
Assert ((Get-W11SuggestedOutput '') -eq '' -and (Get-W11SuggestedOutput '   ') -eq '' -and (Get-W11SuggestedOutput $null) -eq '') 'Get-W11SuggestedOutput: empty source -> "" (no Split-Path exception)'
Assert ((Get-W11SuggestedOutput $tf) -eq (Join-Path $tp 'Win11_26H2_debloated.iso')) 'Get-W11SuggestedOutput: <source>_debloated.iso next to the source'
$gfe = $null; try { $null = Get-W11FreeGB -Path ' ' } catch { $gfe = $_.Exception.Message }
Assert ($gfe -match 'No folder') "Get-W11FreeGB: friendly message for an empty folder ($gfe)"
$guiSrc = [IO.File]::ReadAllText((Join-Path $root 'lib/Gui.ps1'))
$rawLit = @([regex]::Matches($guiSrc, '-LiteralPath \$script:ui\.\w+\.Text|Split-Path[^\r\n]*\$script:ui\.\w+\.Text'))
Assert ($rawLit.Count -eq 0) "GUI never passes a raw text box value to -LiteralPath / Split-Path ($($rawLit.Count) found)"

# languages
$langDir = Join-Path $root 'lang'
$codes = @('vi', 'en', 'zh-CN', 'km')
$tabs = @{}
foreach ($c in $codes) {
    $fp = Join-Path $langDir "$c.psd1"
    $b = [IO.File]::ReadAllBytes($fp)
    Assert ($b.Length -gt 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) "lang/$c.psd1 is UTF-8 with BOM"
    $t = $null; Import-LocalizedData -BaseDirectory $langDir -FileName $c -BindingVariable t -UICulture 'en-US'
    $tabs[$c] = $t
}
$enKeys = @($tabs['en'].Keys | Sort-Object)
foreach ($c in $codes) {
    $k = @($tabs[$c].Keys | Sort-Object)
    $missing = @($enKeys | Where-Object { $k -notcontains $_ }); $extra = @($k | Where-Object { $enKeys -notcontains $_ })
    Assert ($missing.Count -eq 0 -and $extra.Count -eq 0) "lang/${c}: same $($enKeys.Count) keys as en (missing: $($missing -join ',') extra: $($extra -join ','))"
    $bad = @(); $empty = @()
    foreach ($key in $enKeys) {
        $v = [string]$tabs[$c][$key]
        if (-not $v.Trim()) { $empty += $key }
        $pe = (@([regex]::Matches([string]$tabs['en'][$key], '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)) -join ','
        $pc = (@([regex]::Matches($v, '\{\d+\}') | ForEach-Object { $_.Value } | Sort-Object -Unique)) -join ','
        $stray = ($v -replace '\{\d+\}', '') -match '[{}]'
        if ($pe -ne $pc -or $stray) { $bad += $key }
    }
    Assert ($bad.Count -eq 0 -and $empty.Count -eq 0) "lang/${c}: placeholders match English, no stray braces, no empty text (bad: $($bad -join ',') empty: $($empty -join ','))"
}
$used = @([regex]::Matches($guiSrc, "(?:\bT '|'@)([a-z][A-Za-z0-9]*\.[A-Za-z0-9.]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$undef = @($used | Where-Object { $enKeys -notcontains $_ })
Assert ($used.Count -gt 60 -and $undef.Count -eq 0) "every key used in Gui.ps1 ($($used.Count)) exists in the language files (undefined: $($undef -join ','))"
$wmLit = "'Designed by TaiNT13@PNC STG'"
$langAll = (@($codes | ForEach-Object { [IO.File]::ReadAllText((Join-Path $langDir "$_.psd1")) }) -join "`n")
Assert ($guiSrc.Contains('$script:W11Watermark = ' + $wmLit) -and $guiSrc -match "lblWatermark\.Dock = 'Bottom'" -and $guiSrc -match 'lblWatermark\.Text = \$script:W11Watermark' -and -not $langAll.Contains('TaiNT13')) 'watermark: exact text, docked bottom, same in every language (not in lang files)'
$cfgT = Get-W11Config
$tIds = @(@($cfgT.Tweaks) + @($cfgT.Win10Tweaks) | ForEach-Object { $_.Id } | Sort-Object -Unique)
$noTw = @($tIds | Where-Object { $enKeys -notcontains "tweak.$_" })
Assert ($tIds.Count -ge 10 -and $noTw.Count -eq 0) "every tweak Id has a translated name (missing: $($noTw -join ','))"
$vnBad = @($enKeys | Where-Object { [string]$tabs['vi'][$_] -match ' / ' -and [string]$tabs['en'][$_] -notmatch ' / ' })
Assert ($vnBad.Count -eq 0) "no leftover 'English / Việt' pairs in vi.psd1 ($($vnBad -join ','))"

Set-W11Language 'km'
Assert ($script:UiLang -eq 'km' -and (T 'btn.start') -eq [string]$tabs['km']['btn.start']) 'T: Khmer text'
Assert ((T 'msg.lowSpace' 5) -match '\b5\b' -and (T 'msg.done' 'X.iso' 'AB') -match "X\.iso`nSHA256: AB") 'T: placeholders + \n line breaks'
$script:L.Remove('btn.cancel')
Assert ((T 'btn.cancel') -eq 'Cancel' -and (T 'no.such.key') -eq 'no.such.key') 'T: missing key -> English -> key itself'
Set-W11Language 'xx'
Assert ($script:UiLang -eq 'vi' -and (T 'btn.start') -eq 'BẮT ĐẦU') 'unknown language code -> Vietnamese (default)'
Set-W11Language 'zh-CN'
Assert ((T 'btn.start') -eq '开始' -and (Get-W11TweakText @{ Id = 'CopilotOff'; Name = 'x' }) -match 'Copilot' -and (Get-W11TweakText @{ Id = 'NoSuchTweak'; Name = 'Fallback' }) -eq 'Fallback') 'Chinese texts + tweak name falls back to config'
Set-W11Language 'en'
Assert ((Get-W11AppText @{ Id = 'X.Y'; Name = 'Clipchamp (optional)' }) -eq 'Clipchamp (optional)   [X.Y]') 'app text: English stays as in config'
Set-W11Language 'vi'
Assert ((Get-W11AppText @{ Id = 'X.Y'; Name = 'Xbox (unsafe: game sign-in)' }) -eq 'Xbox (không an toàn: đăng nhập game)   [X.Y]') 'app text: note in brackets translated'
Assert ((Get-W11AppText @{ Id = 'P'; Name = 'Paint 3D (optional; classic Paint stays)' }) -eq 'Paint 3D (tuỳ chọn; Paint cổ điển vẫn giữ)   [P]' -and (Get-W11AppText @{ Id = 'T'; Name = 'Microsoft Teams (new)' }) -eq 'Microsoft Teams (bản mới)   [T]' -and (Get-W11AppText @{ Id = 'O'; Name = 'Microsoft 365 (Office) hub' }) -eq 'Microsoft 365 (Office) hub   [O]' -and (Get-W11AppText @{ Id = 'M'; Name = 'Mobile Plans (OneConnect)' }) -eq 'Mobile Plans (OneConnect)   [M]') 'app text: multi-part notes, (new), product names in brackets untouched'
$cfgA = Get-W11Config
$mixed = @()
foreach ($a in @(@($cfgA.Apps) + @($cfgA.Win10Apps))) { $tx = Get-W11AppText $a; $nt = ''; if ($tx -match '\(([^()]+)\)   \[') { $nt = $matches[1] }; if ($nt -match 'unsafe|optional|older|present|reinstall|sign-in|troubleshoot|games UI|classic|^new$') { $mixed += $tx } }
Assert ($mixed.Count -eq 0) "app list (vi): every note translated, no English left ($($mixed -join ' | '))"

# 9) v0.3.4: resizable layout (mock controls: geometry only, real WinForms needs Windows)
Add-Type -TypeDefinition @'
using System.Collections;
public class W11MockFont { public int Height = 16; }
public class W11MockImg { public int Width = 16; }
public class W11MockCtl {
    public W11MockImg Image;
    public string Name = ""; public string Text = ""; public W11MockFont Font = new W11MockFont();
    public int Left, Top, Width = 10, Height = 10; public int DropDownWidth, HorizontalExtent;
    public ArrayList Items = new ArrayList(); public W11MockCtl Parent;
    public int Right { get { return Left + Width; } } public int Bottom { get { return Top + Height; } }
    public void SetBounds(int x, int y, int w, int h) { Left = x; Top = y; Width = w; Height = h; }
}
public class W11MockSize { public int Width, Height; }
public class W11MockForm { public W11MockSize ClientSize = new W11MockSize(); public W11MockFont Font = new W11MockFont(); public void SuspendLayout() { } public void ResumeLayout(bool b) { } }
'@
function Get-W11TextWidth { param([string]$Text, $Font) if (-not $Text) { return 0 }; return 7 * $Text.Length }
function Get-W11TextHeight { param([string]$Text, $Font, [int]$Width) $l = [Math]::Max(1, [Math]::Ceiling((7.0 * ([string]$Text).Length) / [Math]::Max(20, $Width))); return [int](16 * $l) }
$gSrcKeys = @{
    picMs = ''; picLog = ''; grpSource = 'grp.source'; rbLocal = 'rb.local'; lblTargetOs = 'lbl.targetOs'; cbOs = 'os.auto'; lblOs = 'lbl.detectedNone'; tbIso = ''; btnIso = 'btn.browse'
    rbDl = 'rb.download'; lnkMs = 'lnk.ms'; btnFetch = 'btn.languages'; lblVersion = 'lbl.version'; cbRelease = ''; lblArch = 'lbl.arch'; cbArch = ''; lblLang = 'lbl.lang'; cbLang = 'lang.pressLoad'
    btnDownload = 'btn.download'; chkAria2 = 'chk.aria2'; lblAria2 = 'lbl.aria2Missing'
    grpApps = 'grp.apps'; clbApps = ''; btnAppDef = 'btn.appDef'; btnAppAll = 'btn.appAll'; btnAppNone = 'btn.appNone'; note = 'lbl.keptNote'
    grpOptions = 'grp.options'; lblEditions = 'lbl.editions'; rbEdAll = 'rb.edAll'; rbEdHP = ''; rbEdCustom = 'rb.edIdx'; tbIdx = ''; btnEd = 'btn.listEditions'; lblTweaks = 'lbl.tweaks'
    clbTweaks = ''; chkUnattend = 'chk.unattend'; chkCleanup = 'chk.cleanup'; chkEsd = 'chk.esd'; chkDry = 'chk.dry'
    grpOutput = 'grp.output'; tbOut = ''; btnOut = 'btn.saveAs'
    btnCheck = 'btn.check'; btnOsc = 'btn.osc'; btnStart = 'btn.start'; btnCancel = 'btn.cancel'; pb = ''; lblStatus = 'status.ready'; cbUiLang = ''; lnkLog = 'lnk.log'; tbLog = ''; lblWatermark = ''
}
$inner = @{
    grpSource = @('picMs', 'rbLocal', 'lblTargetOs', 'cbOs', 'lblOs', 'tbIso', 'btnIso', 'rbDl', 'lnkMs', 'btnFetch', 'lblVersion', 'cbRelease', 'lblArch', 'cbArch', 'lblLang', 'cbLang', 'btnDownload', 'chkAria2', 'lblAria2')
    grpApps = @('clbApps', 'btnAppDef', 'btnAppAll', 'btnAppNone', 'note')
    grpOptions = @('lblEditions', 'rbEdAll', 'rbEdHP', 'rbEdCustom', 'tbIdx', 'btnEd', 'lblTweaks', 'clbTweaks', 'chkUnattend', 'chkCleanup', 'chkEsd', 'chkDry')
    grpOutput = @('tbOut', 'btnOut')
}
$top = @('grpSource', 'grpApps', 'grpOptions', 'grpOutput', 'btnCheck', 'btnOsc', 'btnStart', 'btnCancel', 'pb', 'lblStatus', 'cbUiLang', 'picLog', 'lnkLog', 'tbLog')
$oneLine = @('rbLocal', 'lblTargetOs', 'btnIso', 'rbDl', 'lnkMs', 'btnFetch', 'lblVersion', 'lblArch', 'lblLang', 'cbLang', 'btnDownload', 'chkAria2', 'btnAppDef', 'btnAppAll', 'btnAppNone', 'rbEdAll', 'rbEdCustom', 'btnEd', 'btnOut', 'btnCheck', 'btnOsc', 'btnStart', 'btnCancel', 'lnkLog')
$saveUi = $script:ui; $layBad = @()
foreach ($c in $codes) {
    Set-W11Language $c
    foreach ($sz in @(@(984, 841), @(1904, 1001), @(1264, 921))) {
        $mf = New-Object W11MockForm; $mf.ClientSize.Width = $sz[0]; $mf.ClientSize.Height = $sz[1]
        $mu = @{ form = $mf }
        foreach ($k in $gSrcKeys.Keys) { $o = New-Object W11MockCtl; $o.Name = $k; if ($gSrcKeys[$k]) { $o.Text = T $gSrcKeys[$k] '' }; $mu[$k] = $o }
        foreach ($k in $script:W11ButtonIcons.Keys) { $mu[$k].Image = New-Object W11MockImg }   # 16 px icons
        $mu.rbEdHP.Text = 'Home + Pro'; $mu.lblWatermark.Text = $script:W11Watermark; $mu.lblWatermark.Font.Height = 13
        if ($c -eq 'km') { $mf.Font.Height = 22; foreach ($k in $gSrcKeys.Keys) { $mu[$k].Font.Height = 22 } }   # taller Khmer font
        $script:ui = $mu; $script:LayoutScale = 1.0
        Set-W11Layout
        $mu.lblWatermark.Top = $sz[1] - $mu.lblWatermark.Height
        $tag = "$c $($sz[0])x$($sz[1])"
        foreach ($k in $oneLine) { $need = Get-W11TextWidth $mu[$k].Text $null; if ($mu[$k].Image) { $need += 22 }; if ($need -gt $mu[$k].Width) { $layBad += "$tag ${k}: text wider than control" } }
        $sets = @(, $top) + @($inner.Keys | ForEach-Object { , $inner[$_] })
        foreach ($set in $sets) {
            for ($i = 0; $i -lt $set.Count; $i++) {
                $a = $mu[$set[$i]]
                if ($a.Width -le 0 -or $a.Height -le 0) { $layBad += "$tag $($a.Name): empty" }
                for ($j = $i + 1; $j -lt $set.Count; $j++) {
                    $b = $mu[$set[$j]]
                    if ($a.Left -lt $b.Right -and $b.Left -lt $a.Right -and $a.Top -lt $b.Bottom -and $b.Top -lt $a.Bottom) { $layBad += "$tag overlap $($a.Name) / $($b.Name)" }
                }
            }
        }
        foreach ($g in $inner.Keys) { foreach ($k in $inner[$g]) { $o = $mu[$k]; if ($o.Left -lt 0 -or $o.Top -lt 14 -or $o.Right -gt $mu[$g].Width -or $o.Bottom -gt $mu[$g].Height) { $layBad += "$tag $k outside $g" } } }
        foreach ($k in $top) { $o = $mu[$k]; if ($o.Left -lt 0 -or $o.Right -gt $sz[0] -or $o.Bottom -gt $mu.lblWatermark.Top) { $layBad += "$tag $k outside the window / under the watermark" } }
        if ($mu.grpSource.Right -ne $sz[0] - 10 -or $mu.grpOptions.Right -ne $sz[0] - 10 -or $mu.grpOutput.Right -ne $sz[0] - 10 -or $mu.tbLog.Right -ne $sz[0] - 10 -or $mu.pb.Right -ne $sz[0] - 10) { $layBad += "$tag sections / progress / log do not reach the right edge" }
        if ([Math]::Abs($mu.grpApps.Width / [double]($mu.grpApps.Width + $mu.grpOptions.Width) - 0.58) -gt 0.01) { $layBad += "$tag 2/3 width split" }
    }
}
$script:ui = $saveUi
Assert ($layBad.Count -eq 0) "layout: 4 languages x 3 window sizes - everything fits, stretches to the right edge, no overlaps, nothing under the watermark ($(@($layBad | Select-Object -First 6) -join '; '))"
Assert ($guiSrc -match 'HorizontalScrollbar = \$true' -and $guiSrc -match 'Add_Resize\(\{ Invoke-W11Layout \}\)' -and $guiSrc -notmatch "tbLog\.Anchor") 'layout: resize handler, horizontal scroll bars on the lists'
Set-W11Language 'vi'

Assert ((Get-W11FontFor 'km' @('Segoe UI', 'Leelawadee UI', 'Khmer UI')) -eq 'Leelawadee UI' -and (Get-W11FontFor 'km' @('Segoe UI', 'Khmer UI')) -eq 'Khmer UI' -and (Get-W11FontFor 'km' @('Segoe UI', 'DaunPenh')) -eq 'DaunPenh') 'font: Khmer -> Leelawadee UI (Win8+) / Khmer UI (Win7) / DaunPenh'
Assert ((Get-W11FontFor 'zh-CN' @('Microsoft YaHei UI', 'Microsoft YaHei')) -eq 'Microsoft YaHei UI' -and (Get-W11FontFor 'zh-CN' @('Microsoft YaHei')) -eq 'Microsoft YaHei' -and (Get-W11FontFor 'vi' @()) -eq 'Microsoft Sans Serif' -and (Get-W11FontFor 'en' @('Segoe UI')) -eq 'Segoe UI') 'font: Chinese YaHei UI -> YaHei, fallbacks'

# settings round trip + download folder default (does not need Output ISO)
$script:W11Root = $tp
$sp = Save-W11Settings @{ Language = 'km'; DownloadFolder = "$tp\it's here"; 'bad key' = 'x' }
$sb = [IO.File]::ReadAllBytes($sp)
$st2 = Read-W11Settings
Assert ($sp -eq (Join-Path $tp 'settings.psd1') -and $sb[0] -eq 0xEF -and $st2.Language -eq 'km' -and $st2.DownloadFolder -eq "$tp\it's here" -and -not $st2.ContainsKey('bad key')) 'settings.psd1: saved (UTF-8 BOM) and read back, quotes kept'
[IO.File]::WriteAllText($sp, 'this is { not valid')
Assert ((Read-W11Settings).Count -eq 0) 'broken settings.psd1 -> defaults, no error'
$oldUp = $env:USERPROFILE
$env:USERPROFILE = $tp; $null = New-Item -ItemType Directory -Path (Join-Path $tp 'Downloads') -Force
Assert ((Get-W11DownloadFolder @{ DownloadFolder = $tp }) -eq $tp -and (Get-W11DownloadFolder @{ DownloadFolder = (Join-Path $tp 'gone') }) -eq (Join-Path $tp 'Downloads') -and (Get-W11DownloadFolder @{}) -eq (Join-Path $tp 'Downloads') -and (Get-W11DownloadFolder $null) -eq (Join-Path $tp 'Downloads')) 'download folder: last used -> %USERPROFILE%\Downloads'
$env:USERPROFILE = Join-Path $tp 'nouser'
Assert ((Get-W11DownloadFolder @{}) -eq (Join-Path $tp 'downloads') -and (Test-Path -LiteralPath (Join-Path $tp 'downloads'))) 'download folder: falls back to <tool>\downloads (created)'
$env:USERPROFILE = $oldUp
$script:W11Root = $root
Assert ($null -eq (Test-W11OutputPath -Out (Join-Path $tp 'out.iso') -Iso $tf)) 'output path check: valid path accepted'
Assert ((Test-W11OutputPath -Out '' -Iso $tf) -and (Test-W11OutputPath -Out $tf -Iso $tf) -eq (T 'msg.outSameAsIso') -and (Test-W11OutputPath -Out (Join-Path $tp 'nodir/out.iso') -Iso $tf) -match 'nodir') 'output path check: empty / same as source / missing folder -> friendly message'

# mirror fallback
$mir = @($cfgT.Mirrors)
$badM = @($mir | Where-Object { [string]$_.Sha256 -notmatch '^[0-9A-F]{64}$' -or [string]$_.FileName -notmatch '^[a-z]{2}-[a-z]{2}_windows_1[01]_.+\.iso$' -or [string]$_.Url -notmatch '^https://' -or (Get-MsUrlHost $_.Url) -match 'microsoft\.com$' -or [string]$_.Page -notmatch '^https://massgrave\.dev/' -or @('Win10', 'Win11') -notcontains $_.Os })
Assert ($mir.Count -ge 8 -and $badM.Count -eq 0 -and @($mir | Where-Object { $_.Kind -eq 'ltsc' }).Count -ge 3) "config Mirrors: $($mir.Count) entries, each with file name, https page, massgrave source and a 64-hex SHA256"
$uniq = @($mir | ForEach-Object { $_.Sha256 } | Sort-Object -Unique)
Assert ($uniq.Count -eq $mir.Count) 'config Mirrors: no duplicate hashes'
$c11 = @(Get-MsMirrorCandidates -Config $cfgT -Os 'Win11' -Arch 'x64' -ReleaseName '26H2')
Assert ($c11.Count -ge 3 -and $c11[0].FileName -like '*consumer*26h2_x64*' -and $c11[0].Sha256 -eq 'BD4307DF32BC8AF33B39CCECB1174AEB345386630F89A2B86C7A4E36B55EA650') 'mirror candidates: Win11 26H2 x64 consumer first (hash = Microsoft published value)'
Assert (@(Get-MsMirrorCandidates -Config $cfgT -Os 'Win11' -Arch 'arm64').Count -eq 0 -and @(Get-MsMirrorCandidates -Config $cfgT -Os 'Win10' -Arch 'x86').Count -eq 3) 'mirror candidates: by OS + arch (no arm64 entries)'
$fakeCfg = @{ Mirrors = @(@{ Os = 'Win10'; Arch = 'x64'; Kind = 'consumer'; FileName = 'a.iso'; Sha256 = ''; Url = 'https://h/x' }, @{ Os = 'Win10'; Arch = 'x64'; Kind = 'consumer'; FileName = 'b.iso'; Sha256 = ('A' * 64); Url = 'https://h/y' }) }
Assert (@(Get-MsMirrorCandidates -Config $fakeCfg -Os 'Win10' -Arch 'x64').Count -eq 1) 'mirror entries without a SHA256 are never offered'
Assert (@(Get-MsMirrorCandidates -Config @{} -Os 'Win10' -Arch 'x64').Count -eq 0) 'no Mirrors section -> no fallback'
$good = Get-W11Sha256 -Path $tf
$vr = Test-MsMirrorFile -Path $tf -Mirror @{ FileName = 'Win11_26H2.iso'; Sha256 = $good.ToLower(); Url = 'https://buzzheavier.com/x' }
Assert ($vr.Ok -and -not $vr.Deleted -and (Test-Path -LiteralPath $tf)) 'mirror file with the expected SHA256 is accepted and kept'
$vr = Test-MsMirrorFile -Path $tf -Mirror @{ FileName = 'Win11_26H2.iso'; Sha256 = ('0' * 64); Url = 'https://buzzheavier.com/x' }
Assert (-not $vr.Ok -and $vr.Deleted -and -not (Test-Path -LiteralPath $tf) -and $vr.Hash -eq $good.ToUpper()) 'mirror file with a wrong SHA256 is deleted and reported'
[IO.File]::WriteAllText($tf, 'iso-bytes')
$vr = Test-MsMirrorFile -Path $tf -Mirror @{ FileName = 'x.iso'; Sha256 = 'nohash'; Url = 'https://h/x' }
Assert (-not $vr.Ok -and $vr.Error -match 'no valid SHA256' -and (Test-Path -LiteralPath $tf)) 'mirror entry without a valid SHA256 is refused (file untouched)'
$vr = Test-MsMirrorFile -Path (Join-Path $tp 'missing.iso') -Mirror @{ Sha256 = ('0' * 64) }
Assert (-not $vr.Ok -and $vr.Error -match 'not found') 'mirror check: missing file reported'
$msSrc = [IO.File]::ReadAllText((Join-Path $root 'lib/MsDownload.ps1'))
$mStart = $msSrc.IndexOf('#region ---------- mirror fallback'); $mEnd = $msSrc.IndexOf('#endregion', $mStart)
$mBody = $msSrc.Substring($mStart, $mEnd - $mStart)
Assert ($mBody -notmatch 'Start-Process|Invoke-Item|Invoke-Expression|& \$|\.Start\(') 'mirror code never runs a downloaded file'

# log box: UI language other than Vietnamese -> English only (file keeps both)
$lp2 = [IO.Path]::GetTempFileName()
$js = Invoke-TestJob '$sync.UiLang = "km"; Write-W11Log -En "Hello" -Vi "Xin chao"' $lp2
$q = @($js.LogQueue.ToArray()) -join "`n"
Assert ($q -match '\] Hello$' -and $q -notmatch 'Xin chao' -and [IO.File]::ReadAllText($lp2) -match 'Hello \| Xin chao') 'log: GUI shows English for zh/km/en, log file keeps English | Vietnamese'
Remove-Item $lp2

# 10) v0.3.5: user paths (real-Windows bug: output 'D:\x.iso' -> New-Item -Force 'D:\' -> "The path is not of a legal form")
$zw = [string][char]0x200B; $nb = [string][char]0x00A0; $lq = [string][char]0x201C; $rq = [string][char]0x201D
$pcases = @(
    @(' "D:\Windows11_Client_x64_en-us_26300_9457_debloated.iso" ', '', 'D:\Windows11_Client_x64_en-us_26300_9457_debloated.iso'),
    @(($zw + 'D:\x.iso' + $nb), '', 'D:\x.iso'),
    @(($lq + 'D:\My ISOs\x.iso' + $rq), '', 'D:\My ISOs\x.iso'),
    @("'D:\x.iso'", '', 'D:\x.iso'),
    @('d:/a//b/./c/../x.iso', '', 'D:\a\b\x.iso'),
    @('D:', '', 'D:\'), @('D:\', '', 'D:\'), @('D:x.iso', '', 'D:\x.iso'), @('D:\out\', '', 'D:\out'),
    @('D:\a.\b \x.iso', '', 'D:\a\b\x.iso'),
    @('\\srv\share\iso\x.iso', '', '\\srv\share\iso\x.iso'), @('//srv/share/x.iso', '', '\\srv\share\x.iso'),
    @('x.iso', 'C:\Users\u\Downloads', 'C:\Users\u\Downloads\x.iso'), @('..\x.iso', 'C:\a\b', 'C:\a\x.iso'), @('\x.iso', 'E:\a', 'E:\x.iso'),
    @('\\srv', '', $null), @('\\srv\', '', $null), @('D:\..\x.iso', '', $null), @('D:\a<b.iso', '', $null), @('D:\a:b.iso', '', $null), @('D:\a?.iso', '', $null),
    @('D:\CON.iso', '', $null), @('D:\x\nul', '', $null), @('\\?\D:\x.iso', '', $null), @('', '', $null), @('   ', '', $null), @('""', '', $null), @("D:\a`tb.iso", '', 'D:\ab.iso')
)
$pbad = @()
foreach ($pc in $pcases) {
    $got = Resolve-W11FullPath $pc[0] $pc[1]
    if ($got -ne $pc[2]) { $pbad += "[$($pc[0])] -> [$got] (expected [$($pc[2])])" }
}
Assert ($pbad.Count -eq 0) "Resolve-W11FullPath: quotes / invisible chars / spaces / relative / drive root / UNC / trailing \ / invalid ($($pbad -join '; '))"
Assert ((Get-W11ParentDir 'D:\Windows11_Client_x64_en-us_26300_9457_debloated.iso') -eq 'D:\' -and (Get-W11ParentDir 'D:\a\x.iso') -eq 'D:\a' -and (Get-W11ParentDir '\\srv\sh\x.iso') -eq '\\srv\sh\' -and (Get-W11ParentDir '\\srv\sh\a\x.iso') -eq '\\srv\sh\a' -and $null -eq (Get-W11ParentDir 'D:\') -and $null -eq (Get-W11ParentDir '\\srv\sh\')) 'Get-W11ParentDir: drive root output -> D:\ (not "D:" or empty), UNC, roots have no parent'
Assert ((Test-W11IsPathRoot 'D:\') -and (Test-W11IsPathRoot '\\srv\sh\') -and -not (Test-W11IsPathRoot 'D:\a')) 'Test-W11IsPathRoot'
Assert ((Get-W11DefaultWorkDir 'D:\') -eq 'D:\WinDebloat_work' -and (Get-W11DefaultWorkDir 'D:\ISO') -eq 'D:\ISO\WinDebloat_work' -and (Get-W11DefaultWorkDir '\\srv\sh\') -like '*WinDebloat_work' -and (Get-W11DefaultWorkDir '\\srv\sh\') -notlike '\\srv*') 'work dir: next to the output (also on a drive root), %TEMP% for a network output'
Assert ((ConvertTo-W11Arg 'D:\') -eq '"D:\\"' -and (ConvertTo-W11Arg 'D:\a\') -eq '"D:\a"' -and (ConvertTo-W11Arg 'D:\a b') -eq '"D:\a b"') 'ConvertTo-W11Arg: drive root keeps its backslash ("D:\\" = D:\), no trailing \ before the quote'
Assert ((Get-W11SuggestedOutput 'D:\Windows11_Client_x64_en-us_26300_9457.iso') -eq 'D:\Windows11_Client_x64_en-us_26300_9457_debloated.iso' -and (Get-W11SuggestedOutput ' "\\srv\sh\w.iso" ') -eq '\\srv\sh\w_debloated.iso') 'suggested output on a drive root / UNC'
Set-W11Language 'vi'
Assert ((Test-W11OutputPath -Out 'Q:\x.iso' -Iso '') -eq (T 'msg.outDriveMissing' 'Q:\') -and (Test-W11OutputPath -Out 'D:\' -Iso '') -eq (T 'msg.outInvalid' 'D:\') -and (Test-W11OutputPath -Out 'D:\a|b.iso' -Iso '') -eq (T 'msg.outInvalid' 'D:\a|b.iso')) 'output check: missing drive / drive root / invalid characters -> Vietnamese message'
Assert ((Test-W11OutputPath -Out $tp -Iso $tf) -eq (T 'msg.outIsFolder' $tp (Join-Path $tp 'Win11_26H2_debloated.iso'))) 'output check: a folder -> "add a file name" with an example'
foreach ($c in $codes) { Set-W11Language $c; Assert ((T 'msg.outIsFolder' 'A' 'B') -match 'A' -and (T 'msg.outIsFolder' 'A' 'B') -match 'B' -and (T 'msg.outDriveMissing' 'Q:\') -match 'Q:') "lang/${c}: path messages" }
Set-W11Language 'vi'
# New-W11Directory: existing folder / root -> nothing created, missing -> created, never New-Item
$nd = Join-Path $tp 'a/b c/d'
New-W11Directory $nd; New-W11Directory $nd; New-W11Directory '/'
Assert (Test-Path -LiteralPath $nd -PathType Container) 'New-W11Directory: nested folder with spaces created, existing folder and root are no-ops'
$nde = $null; try { New-W11Directory 'Q:\' } catch { $nde = $_.Exception.Message }
Assert ($nde -match 'Không thấy ổ đĩa') "New-W11Directory: missing drive root -> clear message ($nde)"
$coreSrc = [IO.File]::ReadAllText((Join-Path $root 'lib/Core.ps1')) + [IO.File]::ReadAllText((Join-Path $root 'lib/Gui.ps1')) + [IO.File]::ReadAllText((Join-Path $root 'lib/MsDownload.ps1'))
Assert (@([regex]::Matches($coreSrc, '(?m)^[^#\r\n]*New-Item -ItemType Directory')).Count -eq 0) 'no New-Item -ItemType Directory left in the tool (drive-root bug class)'
# the exact report: Invoke-Win11Debloat with source and output on the root of D: gets past path preparation
$origAdmin = ${function:Test-W11Admin}; $origNewDir = ${function:New-W11Directory}; $origLog = ${function:Write-W11Log}
$script:madeDirs = @(); $script:runLog = @()
function Write-W11Log { param([string]$Level = 'INFO', [string]$En, [string]$Vi) $script:runLog += $En }
function Test-W11Admin { throw 'SENTINEL-after-path-setup' }
function New-W11Directory { param([string]$Path) $script:madeDirs += $Path }
$lpD = [IO.Path]::GetTempFileName(); $errD = $null
try { $null = Invoke-Win11Debloat -IsoPath 'D:\Windows11_Client_x64_en-us_26300_9457.iso' -OutputIso ' "D:\Windows11_Client_x64_en-us_26300_9457_debloated.iso" ' -EditionMode All -Autounattend $true -LogPath $lpD } catch { $errD = $_.Exception.Message }
Set-Item function:Test-W11Admin $origAdmin; Set-Item function:New-W11Directory $origNewDir; Set-Item function:Write-W11Log $origLog
$logD = $script:runLog -join "`n"; Remove-Item $lpD
Assert ($errD -eq 'SENTINEL-after-path-setup' -and $script:madeDirs.Count -eq 1 -and $script:madeDirs[0] -eq 'D:\' -and $logD -match 'Output ISO: D:\\Windows11_Client_x64_en-us_26300_9457_debloated\.iso' -and $logD -match 'Work dir  : D:\\WinDebloat_work') "repro D:\ output: paths prepared (out dir 'D:\', work 'D:\WinDebloat_work'), no exception ($errD; dirs: $($script:madeDirs -join ','))"
$errD = $null; try { $null = Invoke-Win11Debloat -IsoPath 'D:\w.iso' -OutputIso 'D:\a|b.iso' -LogPath ([IO.Path]::GetTempFileName()) } catch { $errD = $_.Exception.Message }
Assert ($errD -match 'không hợp lệ') "Invoke-Win11Debloat: invalid output path -> clear message ($errD)"
$errD = $null; try { $null = Invoke-Win11Debloat -IsoPath 'D:\w.iso' -OutputIso 'D:\o.iso' -WorkDir 'D:\' -LogPath ([IO.Path]::GetTempFileName()) } catch { $errD = $_.Exception.Message }
Assert ($errD -match 'gốc ổ đĩa') "Invoke-Win11Debloat: drive root as work dir refused (it is deleted afterwards) ($errD)"

# 11) v0.3.6: app icon + button icons (files, optional loading)
$assets = Join-Path $root 'assets'
$icoB = [IO.File]::ReadAllBytes((Join-Path $assets 'WinDebloatTool.ico'))
$icoN = [BitConverter]::ToUInt16($icoB, 4); $icoSizes = @(); $icoBmp = $true
for ($i = 0; $i -lt $icoN; $i++) {
    $w = [int]$icoB[6 + 16 * $i]; if ($w -eq 0) { $w = 256 }; $icoSizes += $w
    $off = [BitConverter]::ToUInt32($icoB, 6 + 16 * $i + 12)
    $isPng = ($icoB[$off] -eq 0x89 -and $icoB[$off + 1] -eq 0x50)
    if ($w -le 128 -and $isPng) { $icoBmp = $false }
}
Assert ((($icoSizes | Sort-Object) -join ',') -eq '16,20,24,32,40,48,64,128,256' -and $icoBmp) "app icon: 9 sizes 16..256, BMP entries up to 128 px (.NET 2.0 Icon class) ($($icoSizes -join ','))"
Assert ((Test-Path -LiteralPath (Join-Path $assets 'icon.svg')) -and (Test-Path -LiteralPath (Join-Path $assets 'icon-small.svg')) -and (Test-Path -LiteralPath (Join-Path $assets 'icon-256.png')) -and (Test-Path -LiteralPath (Join-Path $assets 'icon-512.png'))) 'app icon: SVG sources + 256/512 PNG'
$missIc = @()
foreach ($n in ($script:W11ButtonIcons.Values | Sort-Object -Unique)) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $assets 'icons/svg') "$n.svg"))) { $missIc += "$n.svg" }
    foreach ($z in @(16, 20, 24, 32)) {
        $fp = Join-Path (Join-Path $assets 'icons') ('{0}_{1}.png' -f $n, $z)
        if (-not (Test-Path -LiteralPath $fp)) { $missIc += "${n}_$z" } else { $pb = [IO.File]::ReadAllBytes($fp); if ([BitConverter]::ToInt32(@($pb[19], $pb[18], $pb[17], $pb[16]), 0) -ne $z) { $missIc += "${n}_$z(size)" } }
    }
}
Assert ($missIc.Count -eq 0 -and $script:W11ButtonIcons.Count -ge 14) "button icons: every mapped icon has its SVG and 16/20/24/32 PNG ($($missIc -join ','))"
$saveRoot = $script:W11Root; $script:W11Root = $tp; $script:AppIconTried = $false; $icErr = $null
try { $a1 = Get-W11AppIcon; $a2 = Get-W11IconImage 'folder-open'; $a3 = Get-W11AssetPath @('icons', 'nope.png') } catch { $icErr = $_.Exception.Message }
$script:W11Root = $saveRoot; $script:AppIconTried = $false
Assert (-not $icErr -and $null -eq $a1 -and $null -eq $a2 -and $null -eq $a3) "icons missing (assets folder deleted) -> no icon, no error ($icErr)"
$script:LayoutScale = 1.0; $z1 = Get-W11IconSize; $script:LayoutScale = 1.5; $z2 = Get-W11IconSize; $script:LayoutScale = 2.0; $z3 = Get-W11IconSize; $script:LayoutScale = 1.25; $z4 = Get-W11IconSize; $script:LayoutScale = $null
Assert ($z1 -eq 16 -and $z4 -eq 20 -and $z2 -eq 24 -and $z3 -eq 32) "icon size by DPI: 100% 16, 125% 20, 150% 24, 200% 32 ($z1 $z4 $z2 $z3)"
Assert ($guiSrc -match "TextImageRelation = 'ImageBeforeText'" -and $guiSrc -match 'Set-W11FormIcon \$f' -and $guiSrc -match 'Set-W11FormIcon \$d') 'icons: image before text on buttons; icon on the main window and the mirror dialog'

# 12) v0.3.7: ISO much bigger than the source (user report: +10 GB) -> layout, export command lines, size log, sanity warning
Assert ((Test-W11PathInside 'D:\W\iso\sources' 'D:\W\iso') -and (Test-W11PathInside 'd:\w\ISO' 'D:\W\iso\') -and -not (Test-W11PathInside 'D:\W\iso2' 'D:\W\iso') -and -not (Test-W11PathInside 'D:\W\mount' 'D:\W\iso') -and (Test-W11PathInside '/t/w/iso/a' '/t/w/iso')) 'Test-W11PathInside: same/child yes, sibling or prefix-only no'
$ly = Get-W11WorkLayout -WorkDir 'D:\WinDebloat_work'
Assert ($ly.Tree -eq 'D:\WinDebloat_work\iso' -and $ly.Mount -eq 'D:\WinDebloat_work\mount' -and $ly.Scratch -eq 'D:\WinDebloat_work\scratch' -and $ly.WorkWim -eq 'D:\WinDebloat_work\install.work.wim' -and $ly.NewImage -eq 'D:\WinDebloat_work\install.new.wim') 'work layout: tree, mount, scratch, work WIM and new image are siblings under the work dir'
$le = $null; try { Assert-W11WorkLayout -Layout $ly -OutputIso 'D:\Windows11_debloated.iso' } catch { $le = $_.Exception.Message }
Assert (-not $le) "default layout passes the check ($le)"
Assert ((Get-W11WorkLayout -WorkDir 'D:\W' -Compression Recovery).NewImage -eq 'D:\W\install.new.esd') 'Recovery compression -> new image is install.new.esd'
$badLy = New-W11Obj @{ Tree = 'D:\W\iso'; Mount = 'D:\W\iso\mount'; Scratch = 'D:\W\scratch'; WorkWim = 'D:\W\iso\sources\install.work.wim'; NewImage = 'D:\W\n.wim' }
$le = $null; try { Assert-W11WorkLayout -Layout $badLy } catch { $le = $_.Exception.Message }
Assert ($le -match 'Mount=D:\\W\\iso\\mount' -and $le -match 'WorkWim=') "mount dir / work WIM inside the ISO tree -> refused ($le)"
$le = $null; try { Assert-W11WorkLayout -Layout $ly -OutputIso 'D:\WinDebloat_work\iso\out.iso' } catch { $le = $_.Exception.Message }
Assert ($le -match 'OutputIso') 'output ISO inside the ISO tree -> refused'
$ea = Get-W11ExportArgs -Source 'D:\W\install.work.wim' -Index 6 -Destination 'D:\W\install.new.wim' -ScratchDir 'D:\W\scratch'
Assert ($ea -eq '/Export-Image /SourceImageFile:"D:\W\install.work.wim" /SourceIndex:6 /DestinationImageFile:"D:\W\install.new.wim" /Compress:max /ScratchDir:"D:\W\scratch"') "export command line (max): $ea"
$ea = Get-W11ExportArgs -Source 'E:\sources\install.esd' -Index 1 -Destination 'D:\My W\install.new.esd' -Compression Recovery -CheckIntegrity
Assert ($ea -eq '/Export-Image /SourceImageFile:"E:\sources\install.esd" /SourceIndex:1 /DestinationImageFile:"D:\My W\install.new.esd" /Compress:recovery /CheckIntegrity') "export command line (recovery): $ea"
$sa = Get-W11SplitArgs -ImageFile 'D:\W\install.new.wim' -SwmFile 'D:\W\iso\sources\install.swm'
Assert ($sa -eq '/Split-Image /ImageFile:"D:\W\install.new.wim" /SWMFile:"D:\W\iso\sources\install.swm" /FileSize:3800 /CheckIntegrity') "split command line: $sa"

# full pipeline with mocked dism/robocopy/oscdimg on real temp folders
$pr = Join-Path $tp 'p12'; $srcRoot = Join-Path $pr 'isoroot'
foreach ($d in @('sources', 'boot', 'efi/microsoft/boot')) { $null = [IO.Directory]::CreateDirectory((Join-Path $srcRoot $d)) }
[IO.File]::WriteAllBytes((Join-Path $srcRoot 'sources/install.wim'), (New-Object byte[] 5000))
[IO.File]::WriteAllBytes((Join-Path $srcRoot 'sources/boot.wim'), (New-Object byte[] 300))
[IO.File]::WriteAllBytes((Join-Path $srcRoot 'boot/etfsboot.com'), (New-Object byte[] 10))
[IO.File]::WriteAllBytes((Join-Path $srcRoot 'efi/microsoft/boot/efisys.bin'), (New-Object byte[] 10))
[IO.File]::WriteAllBytes((Join-Path $srcRoot 'setup.exe'), (New-Object byte[] 20))
$srcIso = Join-Path $pr 'Windows11_src.iso'; [IO.File]::WriteAllBytes($srcIso, (New-Object byte[] 4096))
$saved = @{}
foreach ($fn in @('Write-W11Log', 'Test-W11Admin', 'Get-W11FreeGB', 'Find-W11Oscdimg', 'Clear-W11StaleMount', 'Dismount-W11Hives', 'Mount-W11Hives', 'Open-W11Iso', 'Close-W11Iso', 'Select-W11Dism', 'Get-W11ImageInfo', 'Remove-W11AppsDism', 'Invoke-W11Tweaks', 'Invoke-W11Process', 'Invoke-W11Dism', 'Get-W11Sha256')) { $saved[$fn] = (Get-Item "function:$fn").ScriptBlock }
function Write-W11Log { param([string]$Level = 'INFO', [string]$En, [string]$Vi) [void]$script:pLog.Add("[$Level] $En") }
function Test-W11Admin { return $true }
function Get-W11FreeGB { param([string]$Path) return 100 }
function Find-W11Oscdimg { param([string]$Hint) return 'oscdimg.exe' }
function Clear-W11StaleMount { param([string]$MountDir) }
function Dismount-W11Hives { }
function Mount-W11Hives { param([string]$MountDir) }
function Open-W11Iso { param([string]$IsoPath, [string]$ExtractTo) return (New-W11Obj @{ Root = $script:pSrcRoot + '/'; Label = 'CCCOMA'; Mode = 'Mounted' }) }
function Close-W11Iso { param($Iso, [string]$IsoPath) }
function Select-W11Dism { param([string]$IsoSourcesDir) $script:W11D.Dism = 'dism.exe'; $script:W11D.DismCanAppx = $true; return (New-W11Obj @{ Path = 'dism.exe'; Kind = 'Host'; Version = '10.0.26100' }) }
function Get-W11ImageInfo { param([string]$ImageFile) return @(1, 2, 3 | ForEach-Object { New-W11Obj @{ Index = $_; Name = "Windows 11 E$_"; EditionId = @('Core', 'Professional', 'Education')[$_ - 1]; DefaultLanguage = 'en-US'; Architecture = 'x64'; Build = 26300 } }) }
function Remove-W11AppsDism { param($MountDir, $Patterns, $Protected, $OutOfRange, $KeptListPath, [switch]$DryRun) }
function Invoke-W11Tweaks { param([object[]]$TweakDefs, [switch]$DryRun) }
function Get-W11Sha256 { param([string]$Path) return 'AB' }
function Invoke-W11Process { param([string]$FilePath, [string]$Arguments, [switch]$Quiet, [switch]$MergeStdErr, $ProgressBase, $ProgressSpan, $ProgressText)
    [void]$script:pCalls.Add("$FilePath $Arguments")
    if ($FilePath -like '*robocopy*') {
        # faulty copy on purpose: also brings the original install.wim and a temp file into the tree
        $dst = Join-Path $script:pWork 'iso'
        Copy-Item -LiteralPath $script:pSrcRoot -Destination $dst -Recurse   # robocopy creates the target folder
        [IO.File]::WriteAllBytes((Join-Path $dst 'sources/junk.tmp'), (New-Object byte[] 7))
    }
    if ($FilePath -eq 'oscdimg.exe') { $fs = [IO.File]::Create($script:pOut); $fs.SetLength($script:pIsoLen); $fs.Close() }
    return (New-W11Obj @{ ExitCode = 0; Lines = (New-Object Collections.ArrayList) })
}
function Invoke-W11Dism { param([string]$Arguments, [switch]$Quiet, $ProgressBase, $ProgressSpan, $ProgressText, [switch]$NoThrow)
    [void]$script:pCalls.Add("dism $Arguments")
    if ($Arguments -match '/DestinationImageFile:"([^"]+)"') { $fs = [IO.File]::Open($Matches[1], 'OpenOrCreate'); $fs.SetLength($fs.Length + $script:pExportLen); $fs.Close() }
    if ($Arguments -match '/Unmount-Image .*/Commit') { $fs = [IO.File]::Open((Join-Path $script:pWork 'install.work.wim'), 'Open'); $fs.SetLength($fs.Length + 100); $fs.Close() }
    if ($Arguments -match '/SWMFile:"([^"]+)"') { $b = $Matches[1]; [IO.File]::WriteAllBytes($b, (New-Object byte[] 3)); [IO.File]::WriteAllBytes(($b -replace 'install\.swm$', 'install2.swm'), (New-Object byte[] 3)) }
    return (New-W11Obj @{ ExitCode = 0; Lines = (New-Object Collections.ArrayList) })
}
$script:pSrcRoot = $srcRoot
$saveWindir = $env:windir; if (-not $env:windir) { $env:windir = '/windows' }   # robocopy/attrib paths (mocked)
$runs = @(
    @{ Name = 'max'; Compression = 'Max'; Split = 0; Export = 1000; IsoLen = 600MB },
    @{ Name = 'recovery'; Compression = 'Recovery'; Split = 0; Export = 500; IsoLen = 2000 },
    @{ Name = 'split'; Compression = 'Max'; Split = 3800; Export = 1500MB; IsoLen = 2000 }
)
$pRes = @{}
foreach ($r in $runs) {
    $script:pWork = Join-Path $pr ('work_' + $r.Name); $script:pOut = Join-Path $pr ('out/' + $r.Name + '.iso')
    $script:pExportLen = $r.Export; $script:pIsoLen = $r.IsoLen
    $script:pLog = New-Object Collections.ArrayList; $script:pCalls = New-Object Collections.ArrayList
    $e12 = $null
    try { $null = Invoke-Win11Debloat -IsoPath $srcIso -OutputIso $script:pOut -WorkDir $script:pWork -EditionMode All -Autounattend $false -Compression $r.Compression -SplitWimMB $r.Split -KeepWorkDir $true -LogPath (Join-Path $pr "$($r.Name).log") } catch { $e12 = $_.Exception.Message + ' @ ' + $_.InvocationInfo.PositionMessage }
    $pRes[$r.Name] = New-W11Obj @{ Err = $e12; Log = ($script:pLog -join "`n"); Calls = @($script:pCalls); Work = $script:pWork
        Sources = @(Get-ChildItem -LiteralPath (Join-Path $script:pWork 'iso/sources') -Force | ForEach-Object { $_.Name } | Sort-Object) }
}
foreach ($fn in $saved.Keys) { Set-Item "function:$fn" $saved[$fn] }
$env:windir = $saveWindir
$m = $pRes['max']; $tree12 = Join-Path $m.Work 'iso'
Assert (-not $m.Err) "pipeline (mocked, Max): runs to the end ($($m.Err))"
$exp = @($m.Calls | Where-Object { $_ -like 'dism /Export-Image*' })
$expOk = @($exp | Where-Object { $_ -match '/Compress:max' -and $_ -match [regex]::Escape('/DestinationImageFile:"' + (Join-Path $m.Work 'install.new.wim') + '"') -and $_ -match [regex]::Escape('/SourceImageFile:"' + (Join-Path $m.Work 'install.work.wim') + '"') })
Assert ($exp.Count -eq 3 -and $expOk.Count -eq 3 -and $exp[2] -match '/SourceIndex:3 ') "pipeline: every kept edition exported with /Compress:max from the work WIM into a NEW image outside the tree ($($exp -join ' || '))"
$mnt = @($m.Calls | Where-Object { $_ -like 'dism /Mount-Image*' })
Assert ($mnt.Count -eq 3 -and @($mnt | Where-Object { $_ -match [regex]::Escape('/MountDir:"' + (Join-Path $m.Work 'mount') + '"') }).Count -eq 3) 'pipeline: images mounted in <work>\mount, next to the ISO tree'
$inTree = @($m.Calls | Where-Object { $_ -like 'dism *' -and ($_ -match ('/(MountDir|DestinationImageFile|ScratchDir):"' + [regex]::Escape($tree12))) })
Assert ($inTree.Count -eq 0) "pipeline: no DISM mount/scratch/destination path inside the ISO tree ($($inTree -join ' || '))"
Assert (($m.Sources -join ',') -eq 'boot.wim,install.wim') "pipeline: old install.wim and junk.tmp replaced/removed before oscdimg, tree sources = $($m.Sources -join ',')"
Assert ((Get-Item -LiteralPath (Join-Path $tree12 'sources/install.wim')).Length -eq 3000) 'pipeline: tree install.wim is the newly exported image'
$osc = @($m.Calls | Where-Object { $_ -like 'oscdimg.exe *' })
Assert ($osc.Count -eq 1 -and $osc[0] -match '-m -o -u2 -udfver102' -and $osc[0] -match [regex]::Escape('"' + $tree12 + '"')) "pipeline: oscdimg packs only the ISO tree ($osc)"
Assert ($m.Log -match 'SIZE source ISO: .*\(4096 bytes\); source install\.wim: .*\(5000 bytes\)' -and $m.Log -match 'SIZE work WIM after commit' -and $m.Log -match 'SIZE new image: ' -and $m.Log -match 'SIZE source image: .* -> new image: .*\(3 editions, Max\)' -and $m.Log -match 'SIZE ISO tree: ' -and $m.Log -match 'SIZE output ISO: .*\(629145600 bytes\), source ISO: .*\(4096 bytes\)') 'pipeline: size log lines (source ISO/image, work WIM per commit, new image per export, tree, output ISO)'
Assert ($m.Log -match '\[WARN\] Output ISO is .* larger than the source ISO' -and $m.Log -match 'install\.wim' -and $m.Log -match 'boot\.wim') 'pipeline: output ISO > source + 500 MB -> WARN with the largest files of the ISO tree'
Assert ($m.Log -match 'Removed temp file from the ISO tree: .*junk\.tmp' -and $m.Log -match 'Removing old install\.wim') 'pipeline: leftovers are logged when removed'
$rv = $pRes['recovery']
$expR = @($rv.Calls | Where-Object { $_ -like 'dism /Export-Image*' -and $_ -match '/Compress:recovery' -and $_ -match 'install\.new\.esd"' })
Assert (-not $rv.Err -and $expR.Count -eq 3 -and ($rv.Sources -join ',') -eq 'boot.wim,install.esd' -and $rv.Log -notmatch '\[WARN\] Output ISO') "pipeline (Recovery): install.esd only, /Compress:recovery, no size warning ($($rv.Err); $($rv.Sources -join ','))"
$sp = $pRes['split']
Assert (-not $sp.Err -and ($sp.Sources -join ',') -eq 'boot.wim,install.swm,install2.swm' -and @($sp.Calls | Where-Object { $_ -like 'dism /Split-Image*/FileSize:3800*' }).Count -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $sp.Work 'install.new.wim'))) "pipeline (split): >4 GB install.wim -> install.swm + install2.swm in the tree ($($sp.Err); $($sp.Sources -join ','))"
Assert ($sp.Log -match '\[WARN\] The new image is .* larger than the source one') 'pipeline: new image much bigger than the source image -> WARN with the advice (fewer editions / ESD)'
Remove-Item -LiteralPath $tp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Failures: $script:fail"
exit $script:fail

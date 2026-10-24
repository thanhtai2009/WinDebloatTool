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
foreach ($fam in (Get-Content (Join-Path $root 'tests\fixtures\reference_families.txt'))) { if ($fam) { Assert ($def -contains $fam) "reference removal kept in defaults: $fam" } }
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
}

# --- Windows 10 profile ---
$p10 = Get-W11Profile -Config $cfg -Os Win10
$d10 = @($p10.Apps | Where-Object { $_.Default } | ForEach-Object { $_.Id })
$o10 = @($p10.Apps | Where-Object { -not $_.Default } | ForEach-Object { $_.Id })
foreach ($id in @('Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.MixedReality.Portal', 'Microsoft.People', 'Microsoft.SkypeApp', 'Microsoft.OneConnect', 'Microsoft.Wallet', 'Microsoft.Messaging', 'Microsoft.BingWeather', 'Microsoft.BingNews', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.YourPhone', 'Microsoft.WindowsFeedbackHub', 'Microsoft.549981C3F5F10', 'Clipchamp.Clipchamp', 'MicrosoftTeams')) {
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
$e1.SessionState = @{ Tags = $true; OvDf = $true; Note = '' }
$msg = ''; try { $null = Get-MsIsoDownloadLink -Entry $e1 -SkuId '27160' } catch { $msg = $_.Exception.Message }
Assert ($msg -match 'VPN' -and $msg -notmatch 'cannot reach') 'SentinelReject with working session -> VPN/region hint'

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
$js = Invoke-TestJob 'throw "boom from job"' $lp
$logTxt = [IO.File]::ReadAllText($lp)
Assert ($js.Error -eq 'boom from job' -and $logTxt -match '\[ERROR\] boom from job' -and $logTxt -match 'RuntimeException') 'runspace: job exception -> $sync.Error + details in log'
Remove-Item $lp

Write-Host "Failures: $script:fail"
exit $script:fail

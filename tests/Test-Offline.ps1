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
$def = @($cfg.Apps | Where-Object { $_.Default } | ForEach-Object { $_.Id })
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
Invoke-W11Tweaks -TweakDefs @($cfg.Tweaks)
$adds = @($script:regCalls | Where-Object { $_ -like 'add *' })
$dels = @($script:regCalls | Where-Object { $_ -like 'delete *' })
Assert ($adds.Count -eq 28) "28 registry values written (got $($adds.Count))"
Assert ($dels.Count -eq 3) 'UScheduler_Oobe Outlook/DevHome/CrossDevice deleted'
Assert (@($adds | Where-Object { $_ -match 'W11D_SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\OOBE" /v "BypassNRO" /t REG_DWORD /d 1' }).Count -eq 1) 'BypassNRO=1 command'
Assert (@($adds | Where-Object { $_ -match 'W11D_DEFAULT\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced" /v "TaskbarMn"' }).Count -eq 1) 'TaskbarMn in default user hive'

# --- MS page parsing / hash matching ---
function Invoke-MsDlRequest { param([string]$Uri, [string]$Referer) return [IO.File]::ReadAllText((Join-Path $fx 'mspage.html')) }
$pi = Get-MsDlPageInfo -Url 'https://x' -Arch 'x64'
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

Write-Host "Failures: $script:fail"
exit $script:fail

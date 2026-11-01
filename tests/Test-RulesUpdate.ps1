# Rules auto-update tests: download, SHA256 / format / policy checks, atomic install with backup, timeout,
# offline, disabled setting, GUI background check. Uses a local HTTP server (tests/tools/rules_server.py).
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'lib\Core.ps1')
. (Join-Path $root 'lib\Gui.ps1')
$script:fail = 0; $script:pass = 0
function Assert($cond, $msg) { if ($cond) { $script:pass++; Write-Host "PASS $msg" -ForegroundColor Green } else { $script:fail++; Write-Host "FAIL $msg" -ForegroundColor Red } }

# isolated tool folder (bundled rules = a copy of data\) and download store
$work = Join-Path ([IO.Path]::GetTempPath()) ('w11rules_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$tool = Join-Path $work 'tool'
foreach ($d in @('lib', 'config', 'data', 'lang')) { Copy-Item -LiteralPath (Join-Path $root $d) -Destination (Join-Path $tool $d) -Recurse }
$script:W11Root = $tool
$store = Join-Path $work 'store'
$script:W11D.RulesStore = $store
$srv = Join-Path $work 'srv'; $null = New-Item -ItemType Directory -Path $srv -Force
$hits = Join-Path $work 'hits.log'
$dataFiles = (@(Get-ChildItem -LiteralPath (Join-Path $tool 'data') -Recurse | ForEach-Object { $_.Name }) -join ',')
$bundledApps = Read-W11JsonFile (Join-Path $root 'data\apps.json')
$bundledTweaks = Read-W11JsonFile (Join-Path $root 'data\tweaks.json')

function Set-Mode([string]$m) { [IO.File]::WriteAllText((Join-Path $srv '.mode'), $m) }
function Get-Bytes([string]$t) { return , ([Text.Encoding]::UTF8.GetBytes($t.Replace("`r`n", "`n"))) }
function Publish {
    # serves a rule set: -Apps / -Tweaks (objects or raw text), manifest with correct hashes unless overridden
    param([string]$Version, $Apps = $bundledApps, $Tweaks = $bundledTweaks, [string]$AppsText, [string]$TweaksText, [hashtable]$Hash = @{}, [string]$MinTool = '1.1.0', [string]$ManifestText)
    if (-not $AppsText) { $AppsText = ConvertTo-W11Json $Apps }
    if (-not $TweaksText) { $TweaksText = ConvertTo-W11Json $Tweaks }
    $ab = Get-Bytes $AppsText; $tb = Get-Bytes $TweaksText
    [IO.File]::WriteAllBytes((Join-Path $srv 'apps.json'), $ab); [IO.File]::WriteAllBytes((Join-Path $srv 'tweaks.json'), $tb)
    $ha = Get-W11RulesHash $ab; if ($Hash.apps) { $ha = $Hash.apps }
    $ht = Get-W11RulesHash $tb; if ($Hash.tweaks) { $ht = $Hash.tweaks }
    if (-not $ManifestText) {
        $ManifestText = ConvertTo-W11Json (New-W11Ordered 'schema' 1 'version' $Version 'minToolVersion' $MinTool 'files' @((New-W11Ordered 'name' 'apps.json' 'sha256' $ha), (New-W11Ordered 'name' 'tweaks.json' 'sha256' $ht)))
    }
    [IO.File]::WriteAllBytes((Join-Path $srv 'rules-manifest.json'), (Get-Bytes $ManifestText))
}
function Copy-Data($d) { return (ConvertFrom-W11Json (ConvertTo-W11Json $d)) }
function Get-RuleDirs { if (-not (Test-Path -LiteralPath $store)) { return @() }; return @(Get-ChildItem -LiteralPath $store | Where-Object { $_.PSIsContainer } | ForEach-Object { $_.Name }) }
function New-TestApp([string]$p) { return (New-W11Ordered 'pattern' $p 'os' 'both' 'default' $false 'level' 'safe' 'name' @{ vi = $p; en = $p; 'zh-CN' = $p; km = $p }) }
function With-Tweak($op, [string]$kind = 'set') {
    $t = Copy-Data $bundledTweaks
    $x = Copy-Data $t['tweaks'][0]; $x['id'] = 'PolicyProbe'; $x['set'] = @(); $x[$kind] = @($op)
    $t['tweaks'] = @($t['tweaks']) + @($x)
    return $t
}

# --- pure helpers ---
Assert (Test-W11RulesUrl $script:W11D.RulesBaseUrl) 'default rules URL: HTTPS raw.githubusercontent.com, project repository'
Assert (-not (Test-W11RulesUrl ($script:W11D.RulesBaseUrl -replace '^https:', 'http:'))) 'plain HTTP GitHub URL refused'
Assert (-not (Test-W11RulesUrl ($script:W11D.RulesBaseUrl -replace '\.com/[^/]+/', '.com/someone-else/'))) 'other GitHub owner refused'
Assert (-not (Test-W11RulesUrl ($script:W11D.RulesBaseUrl -replace 'raw\.githubusercontent\.com', 'example.com'))) 'other host refused'
Assert (-not (Test-W11RulesUrl 'http://127.0.0.1:8080/')) 'local test URL refused without -AllowTestUrl'
$lf = [Text.Encoding]::UTF8.GetBytes("{`n  `"a`": 1`n}`n")
$crlf = [Text.Encoding]::UTF8.GetBytes("{`r`n  `"a`": 1`r`n}`r`n")
$bom = [byte[]](@(0xEF, 0xBB, 0xBF) + @($crlf))
Assert ((Get-W11RulesHash $lf) -eq (Get-W11RulesHash $crlf) -and (Get-W11RulesHash $lf) -eq (Get-W11RulesHash $bom)) 'rules hash: LF, CRLF and BOM+CRLF give the same SHA256'
$sha = New-Object Security.Cryptography.SHA256Managed
Assert ((Get-W11RulesHash $lf) -eq ([BitConverter]::ToString($sha.ComputeHash($lf)) -replace '-', '')) 'rules hash of an LF file = plain SHA256 (what raw.githubusercontent.com serves)'
Assert (@(Test-W11RulesContent $bundledApps $bundledTweaks).Count -eq 0) 'bundled rules pass the download checks (format + policy)'
Assert ((Test-W11RulesDir (Join-Path $root 'data')) -eq (New-Object Version '2026.11.1.1')) 'bundled data\rules-manifest.json matches apps.json / tweaks.json'
$ar = Get-W11ActiveRules
Assert ($ar.Source -eq 'bundled' -and [string]$ar.Version -eq '2026.11.1.1') "no download yet: bundled rules active ($($ar.Source) $($ar.Version))"
$r = Update-W11Rules -BaseUrl 'https://example.com/rules/'
Assert ($r.Status -eq 'Rejected' -and $r.ElapsedMs -lt 1000) "foreign URL: rejected without a request ($($r.Status))"

# --- offline (connection refused) ---
$l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0; $l.Start(); $deadPort = $l.LocalEndpoint.Port; $l.Stop()
$r = Update-W11Rules -BaseUrl "http://127.0.0.1:$deadPort/" -AllowTestUrl
Assert ($r.Status -eq 'Offline' -and $r.ElapsedMs -lt 10000) "offline: status Offline in $($r.ElapsedMs) ms ($($r.Error))"
Assert ((Get-W11ActiveRules).Source -eq 'bundled' -and (Get-RuleDirs).Count -eq 0) 'offline: local rules unchanged, nothing written'
$cfg = Get-W11Config
Assert ($cfg.RulesSource -eq 'bundled' -and @($cfg.Apps).Count -gt 0) 'offline: Get-W11Config still loads the bundled rules'

$py = Get-Command python3, python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $py) {
    Write-Host 'SKIP network tests (python not found)'
} else {
    $psi = New-Object Diagnostics.ProcessStartInfo $py.Definition, ('"{0}" "{1}" "{2}"' -f (Join-Path $root 'tests/tools/rules_server.py'), $srv, $hits)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $port = [int]$proc.StandardOutput.ReadLine()
    $url = "http://127.0.0.1:$port/"
    try {
        # --- success ---
        Set-Mode 'ok'
        $a2 = Copy-Data $bundledApps; $a2['apps'] = @($a2['apps']) + @(New-TestApp 'Contoso.RulesTestOne')
        $a2['protected'] = @(@($a2['protected']) | Where-Object { $_ -ne 'Microsoft.WindowsStore' })
        Publish -Version '2026.12.1.1' -Apps $a2
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        Assert ($r.Status -eq 'Updated' -and $r.Version -eq '2026.12.1.1') "success: Updated to $($r.Version) ($($r.Status) $($r.Error))"
        $first = $r.Dir
        Assert ((Get-W11RulesPointer $store 'current.txt') -eq $first -and (Test-W11RulesDir $first)) 'success: current.txt points to the verified folder'
        $cfg = Get-W11Config
        Assert ($cfg.RulesSource -eq 'downloaded' -and $cfg.RulesVersion -eq '2026.12.1.1' -and @($cfg.Apps | Where-Object { $_.Id -eq 'Contoso.RulesTestOne' }).Count -eq 1) 'success: Get-W11Config uses the downloaded rules'
        Assert (@($cfg.Protected) -contains 'Microsoft.WindowsStore') 'success: bundled protected apps stay protected even if the download drops them'
        Assert (@(Get-RuleDirs | Where-Object { $_ -like 'tmp-*' }).Count -eq 0) 'success: no temporary folder left'
        Assert ((@(Get-ChildItem -LiteralPath (Join-Path $tool 'data') -Recurse | ForEach-Object { $_.Name }) -join ',') -eq $dataFiles) 'success: bundled data\ folder untouched'

        # --- same version again: nothing downloaded beyond the manifest ---
        [IO.File]::WriteAllText($hits, '')
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        $h = @([IO.File]::ReadAllLines($hits))
        Assert ($r.Status -eq 'UpToDate' -and $h.Count -eq 1 -and $h[0] -eq '/rules-manifest.json') "up to date: only the manifest is fetched ($($r.Status), $($h.Count) request(s))"

        # --- second and third update: previous copy kept as backup, older ones pruned ---
        $a3 = Copy-Data $a2; $a3['apps'] = @($a3['apps']) + @(New-TestApp 'Contoso.RulesTestTwo')
        Publish -Version '2026.12.2.1' -Apps $a3
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        $second = $r.Dir
        Assert ($r.Status -eq 'Updated' -and (Get-W11RulesPointer $store 'previous.txt') -eq $first -and (Test-Path -LiteralPath $first)) 'backup: previous.txt keeps the folder of the rules before'
        $pinned = $second
        $a4 = Copy-Data $a3; $a4['apps'] = @($a4['apps']) + @(New-TestApp 'Contoso.RulesTestThree')
        Publish -Version '2026.12.3.1' -Apps $a4
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        $third = $r.Dir
        Assert ($r.Status -eq 'Updated' -and (Get-W11RulesPointer $store 'previous.txt') -eq $second -and -not (Test-Path -LiteralPath $first) -and @(Get-RuleDirs).Count -eq 2) 'backup: only current + previous are kept'
        # a run started before the update keeps its rule set (the GUI passes the folder of its rules)
        $pc = Get-W11Config -DataDir $pinned
        Assert (@($pc.Apps | Where-Object { $_.Id -eq 'Contoso.RulesTestTwo' }).Count -eq 1 -and @($pc.Apps | Where-Object { $_.Id -eq 'Contoso.RulesTestThree' }).Count -eq 0) 'no mid-run swap: the pinned rule set of a running build is still readable and unchanged'
        Assert ((Get-W11Config).RulesVersion -eq '2026.12.3.1') 'next run: the new rules are active'
        Assert ($pc.RulesSource -eq 'downloaded' -and @($pc.Protected) -contains 'Microsoft.WindowsStore') 'pinned download: same checks and bundled protected apps as the active rules'

        # --- bad hash ---
        $before = @(Get-RuleDirs) -join ','
        $a5 = Copy-Data $a4; $a5['apps'] = @($a5['apps']) + @(New-TestApp 'Contoso.Evil')
        Publish -Version '2027.1.1.1' -Apps $a5 -Hash @{ apps = ('0' * 64) }
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        Assert ($r.Status -eq 'Rejected' -and $r.Error -match 'SHA256') "bad hash: rejected ($($r.Error))"
        Assert ((@(Get-RuleDirs) -join ',') -eq $before -and (Get-W11ActiveRules).Dir -eq $third) 'bad hash: nothing written, current rules kept'
        # the right hash, but of other content (file changed after the manifest was made)
        Publish -Version '2027.1.1.1' -Apps $a5 -Hash @{ apps = (Get-W11RulesHash (Get-Bytes (ConvertTo-W11Json $a4))) }
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        Assert ($r.Status -eq 'Rejected' -and (Get-W11ActiveRules).Dir -eq $third) 'bad hash: manifest of an older file -> rejected'

        # --- malformed rules ---
        $cases = @(
            @{ Name = 'tweaks.json is not JSON'; TweaksText = '{ "schema": 1, "tweaks": [ { "id": "X", ' }
            @{ Name = 'apps.json without apps'; AppsText = '{ "schema": 1, "apps": [] }' }
            @{ Name = 'unknown schema'; AppsText = (ConvertTo-W11Json (& { $x = Copy-Data $a4; $x['schema'] = 2; $x })) }
            @{ Name = 'tweak with an invalid hive'; Tweaks = (With-Tweak @{ hive = 'HKCU'; key = 'Software\Contoso'; name = 'A'; type = 'REG_DWORD'; value = '1'; undo = @{ action = 'delete' } }) }
            @{ Name = 'policy: autostart Run key'; Tweaks = (With-Tweak @{ hive = 'SOFTWARE'; key = 'Microsoft\Windows\CurrentVersion\Run'; name = 'Evil'; type = 'REG_SZ'; value = 'C:\evil.exe'; undo = @{ action = 'delete' } }) }
            @{ Name = 'policy: debugger (Image File Execution Options)'; Tweaks = (With-Tweak @{ hive = 'SOFTWARE'; key = 'Microsoft\Windows NT\CurrentVersion\Image File Execution Options\sethc.exe'; name = 'Debugger'; type = 'REG_SZ'; value = 'cmd.exe'; undo = @{ action = 'delete' } }) }
            @{ Name = 'policy: Winlogon shell'; Tweaks = (With-Tweak @{ hive = 'SOFTWARE'; key = 'Microsoft\Windows NT\CurrentVersion\Winlogon'; name = 'Userinit'; type = 'REG_SZ'; value = 'x'; undo = @{ action = 'delete' } }) }
            @{ Name = 'policy: service ImagePath'; Tweaks = (With-Tweak @{ hive = 'SYSTEM'; key = 'ControlSet001\Services\Evil'; name = 'ImagePath'; type = 'REG_EXPAND_SZ'; value = 'x'; undo = @{ action = 'delete' } }) }
            @{ Name = 'policy: COM class (Classes\CLSID)'; Tweaks = (With-Tweak @{ hive = 'SOFTWARE'; key = 'Classes\CLSID\{0}\InprocServer32'; name = 'ThreadingModel'; type = 'REG_SZ'; value = 'Both'; undo = @{ action = 'delete' } }) }
            @{ Name = 'policy: quote in a value (reg.exe argument)'; Tweaks = (With-Tweak @{ hive = 'SOFTWARE'; key = 'Policies\Contoso'; name = 'A'; type = 'REG_SZ'; value = 'a" /f "b'; undo = @{ action = 'delete' } }) }
            @{ Name = 'policy: deleting a top-level key'; Tweaks = (With-Tweak @{ hive = 'SOFTWARE'; key = 'Microsoft'; undo = @{ action = 'none' } } 'deleteKey') }
            @{ Name = 'manifest without tweaks.json'; ManifestText = (ConvertTo-W11Json (New-W11Ordered 'schema' 1 'version' '2027.1.1.1' 'files' @((New-W11Ordered 'name' 'apps.json' 'sha256' ('A' * 64))))) }
            @{ Name = 'manifest lists another file'; ManifestText = (ConvertTo-W11Json (New-W11Ordered 'schema' 1 'version' '2027.1.1.1' 'files' @((New-W11Ordered 'name' '..\lib\Core.ps1' 'sha256' ('A' * 64)), (New-W11Ordered 'name' 'apps.json' 'sha256' ('A' * 64)), (New-W11Ordered 'name' 'tweaks.json' 'sha256' ('A' * 64))))) }
            @{ Name = 'manifest is not JSON'; ManifestText = '<html>rate limited</html>' }
            @{ Name = 'manifest with a bad version'; ManifestText = (ConvertTo-W11Json (New-W11Ordered 'schema' 1 'version' 'latest' 'files' @())) }
        )
        foreach ($c in $cases) {
            $pa = @{ Version = '2027.1.1.1'; Apps = $a4 }
            foreach ($k in @('AppsText', 'TweaksText', 'Tweaks', 'ManifestText')) { if ($c.ContainsKey($k)) { $pa[$k] = $c[$k] } }
            Publish @pa
            $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
            Assert ($r.Status -eq 'Rejected' -and (Get-W11ActiveRules).Dir -eq $third -and (@(Get-RuleDirs) -join ',') -eq $before) "malformed ($($c.Name)): rejected, current rules kept ($($r.Status): $($r.Error))"
        }
        # rules for a newer tool are not applied
        Publish -Version '2027.1.1.1' -Apps $a4 -MinTool '9.0'
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        Assert ($r.Status -eq 'UpToDate' -and (Get-W11ActiveRules).Dir -eq $third) 'minToolVersion above this tool: not applied'
        # HTTP error
        Set-Mode '404'
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        Assert ($r.Status -eq 'Failed' -and (Get-W11ActiveRules).Dir -eq $third) "HTTP 404: current rules kept ($($r.Status))"

        # --- a damaged download on disk falls back to the backup, then to the bundled rules ---
        $ap3 = Join-Path $third 'apps.json'
        $orig3 = [IO.File]::ReadAllBytes($ap3)
        [IO.File]::WriteAllText($ap3, '{ "schema": 1, "apps": [] }')
        Assert ((Get-W11ActiveRules).Dir -eq $second -and (Get-W11Config).RulesVersion -eq '2026.12.2.1') 'damaged current rules: the previous copy is used'
        $ap2 = Join-Path $second 'apps.json'; $orig2 = [IO.File]::ReadAllBytes($ap2)
        [IO.File]::WriteAllText($ap2, 'x')
        Assert ((Get-W11Config).RulesSource -eq 'bundled') 'damaged current and previous rules: bundled rules are used'
        [IO.File]::WriteAllBytes($ap3, $orig3); [IO.File]::WriteAllBytes($ap2, $orig2)

        # --- timeout: the server accepts but never answers ---
        Set-Mode 'hang'
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl
        Assert ($r.Status -eq 'Timeout' -and $r.ElapsedMs -ge 9000 -and $r.ElapsedMs -le 11500) "timeout: gives up after the 10 s limit ($($r.ElapsedMs) ms, $($r.Status))"
        Assert ((Get-W11ActiveRules).Dir -eq $third) 'timeout: current rules kept'
        # slow body: the limit covers the whole check, not each read
        Set-Mode 'trickle'
        Publish -Version '2027.2.1.1' -Apps $a4
        $r = Update-W11Rules -BaseUrl $url -AllowTestUrl -TimeoutMs 3000
        Assert ($r.Status -eq 'Timeout' -and $r.ElapsedMs -le 4500 -and (Get-W11ActiveRules).Dir -eq $third) "timeout: a trickling download stops at the limit ($($r.ElapsedMs) ms)"

        # --- disabled setting ---
        Set-Mode 'ok'
        Assert ((Get-W11RulesAutoUpdate @{}) -and (Get-W11RulesAutoUpdate @{ RulesAutoUpdate = '1' }) -and -not (Get-W11RulesAutoUpdate @{ RulesAutoUpdate = '0' })) 'setting: on by default, RulesAutoUpdate = 0 turns it off'
        $st = @{ RulesAutoUpdate = '0'; Language = 'vi' }
        $sp = Save-W11Settings $st
        Assert ($sp -and (Read-W11Settings).RulesAutoUpdate -eq '0') 'setting: saved to and read from settings.psd1'
        [IO.File]::WriteAllText($hits, '')
        $script:RulesJob = $null
        $started = Start-W11RulesUpdate -Settings (Read-W11Settings) -BaseUrl $url -AllowTestUrl
        Start-Sleep -Milliseconds 500
        Assert (-not $started -and -not $script:RulesJob -and ([IO.File]::ReadAllText($hits)).Length -eq 0) 'disabled: no background check, no request'
        Remove-Item -LiteralPath $sp -Force

        # --- GUI background check: returns at once, finishes in the background ---
        Publish -Version '2027.3.1.1' -Apps $a4
        $script:Cfg = Get-W11Config; $script:Job = $null; $script:ui = $null
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $started = Start-W11RulesUpdate -Settings @{} -BaseUrl $url -AllowTestUrl
        $tStart = $sw.ElapsedMilliseconds
        Assert ($started -and $script:RulesJob -and $tStart -lt 3000) "GUI: check starts in the background and returns in $tStart ms"
        while ($script:RulesJob -and $sw.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 100; Invoke-W11RulesTick }
        Assert ($script:RulesResult.Status -eq 'Updated' -and $script:RulesReload) "GUI: background check installed 2027.3.1.1 ($($script:RulesResult.Status) $($script:RulesResult.Error))"
        $script:Job = @{ Background = $false }
        Update-W11RulesReload
        Assert ($script:Cfg.RulesVersion -eq '2026.12.3.1' -and $script:RulesReload) 'GUI: while a build runs, its rules are not swapped'
        $script:Job = $null
        Update-W11RulesReload
        Assert ($script:Cfg.RulesVersion -eq '2027.3.1.1' -and -not $script:RulesReload) 'GUI: after the build the new rules are loaded for the next run'
        # hanging server: the UI is never blocked and the check is dropped at the limit
        Set-Mode 'hang'
        Publish -Version '2027.4.1.1' -Apps $a4
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $started = Start-W11RulesUpdate -Settings @{} -BaseUrl $url -AllowTestUrl
        $tStart = $sw.ElapsedMilliseconds
        $maxTick = 0
        while ($script:RulesJob -and $sw.ElapsedMilliseconds -lt 20000) { $t0 = $sw.ElapsedMilliseconds; Invoke-W11RulesTick; $maxTick = [Math]::Max($maxTick, $sw.ElapsedMilliseconds - $t0); Start-Sleep -Milliseconds 100 }
        $tEnd = $sw.ElapsedMilliseconds
        Assert ($started -and $tStart -lt 3000 -and $maxTick -lt 500) "GUI timeout: start $tStart ms, longest timer tick $maxTick ms (UI stays responsive)"
        Assert ($script:RulesResult.Status -eq 'Timeout' -and $tEnd -le 12000 -and (Get-W11Config).RulesVersion -eq '2027.3.1.1') "GUI timeout: dropped after $tEnd ms, current rules kept ($($script:RulesResult.Status))"
    } finally {
        try { $proc.Kill() } catch { $null = $_ }
    }
}
# a check blocked inside .NET (e.g. DNS) is stopped by the UI timer shortly after the limit
$rs = [runspacefactory]::CreateRunspace(); $rs.Open()
$ps = [powershell]::Create(); $ps.Runspace = $rs; [void]$ps.AddScript('Start-Sleep -Seconds 30')
$script:RulesJob = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); Clock = [Diagnostics.Stopwatch]::StartNew(); TimeoutMs = 1000 }
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($script:RulesJob -and $sw.ElapsedMilliseconds -lt 10000) { Start-Sleep -Milliseconds 100; Invoke-W11RulesTick }
Assert (-not $script:RulesJob -and $script:RulesResult.Status -eq 'Timeout' -and $sw.ElapsedMilliseconds -lt 3000) "GUI: a blocked check is dropped at limit + 1 s ($($sw.ElapsedMilliseconds) ms)"
# the PowerShell 2.0 JSON path (built-in parser) accepts the bundled rules too
$pa = ConvertFrom-W11Json ([IO.File]::ReadAllText((Join-Path $root 'data\apps.json'))) -Engine Parser
$pt = ConvertFrom-W11Json ([IO.File]::ReadAllText((Join-Path $root 'data\tweaks.json'))) -Engine Parser
$pm = ConvertFrom-W11Json ([IO.File]::ReadAllText((Join-Path $root 'data\rules-manifest.json'))) -Engine Parser
Assert (@(Test-W11RulesContent $pa $pt).Count -eq 0 -and @(Test-W11RulesManifest $pm).Count -eq 0) 'PS 2.0 JSON parser: bundled rules and manifest pass the checks'
# console entry point and GUI wiring
$ep = [IO.File]::ReadAllText((Join-Path $root 'WinDebloatTool.ps1'))
Assert ($ep -match '\[switch\]\$UpdateRules' -and $ep -match 'Update-W11Rules') 'console: -UpdateRules checks now'
$gs = [IO.File]::ReadAllText((Join-Path $root 'lib\Gui.ps1'))
Assert ($gs -match 'Start-W11RulesUpdate -Settings \$script:Settings' -and $gs -match 'RulesDir = \[string\]\$script:Cfg\.RulesDir') 'GUI: check at launch, builds get the rule set shown in the window'
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Passed: $script:pass  Failed: $script:fail"
exit $script:fail

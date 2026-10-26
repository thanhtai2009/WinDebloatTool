<#
    WinDebloat Tool (Windows 10 / 11) - core engine (no GUI).
    Compatible with Windows PowerShell 2.0+ (Windows 7 SP1) up to 5.1 / 7.x.
    All image servicing goes through dism.exe (ADK, system or the ISO's own copy),
    registry through reg.exe, ISO creation through oscdimg.exe (Windows ADK).
    SPDX-License-Identifier: MIT
#>

# When dot-sourced from a file we know our location; when injected as text into a background
# runspace (GUI), the caller sets $script:W11Root afterwards.
if ($MyInvocation.MyCommand.Path) {
    $script:W11LibDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $script:W11Root = Split-Path -Parent $script:W11LibDir
}
$script:W11D = @{
    Version      = '1.1.0'
    LogPath      = $null
    Sync         = $null
    HiveSoftware = 'HKLM\W11D_SOFTWARE'
    HiveDefault  = 'HKLM\W11D_DEFAULT'      # Users\Default\NTUSER.DAT (template for new users)
    HiveSystem   = 'HKLM\W11D_SYSTEM'       # Windows\System32\config\SYSTEM (loaded only when a tweak needs it)
    HiveDefProf  = 'HKLM\W11D_DEFPROFILE'   # Windows\System32\config\DEFAULT (.DEFAULT profile, same)
    AdkSetupUrl  = 'https://go.microsoft.com/fwlink/?linkid=2289980'   # official current ADK online installer (10.1.26100.9457, Sep 2026)
    AdkVersion   = '10.1.26100.9457'
    # Windows 7 SP1 / 8.x hosts: the current ADK does not install there; the ADK for Windows 10, version 1607
    # (republished May 2025, official link from learn.microsoft.com "Other ADK downloads") is tried instead.
    AdkLegacyUrl = 'https://go.microsoft.com/fwlink/p/?LinkId=526740'
    AdkLegacyVersion = '10.1.14393 (ADK for Windows 10, version 1607)'
    Dism         = $null    # selected dism.exe
    DismCanAppx  = $false   # $false -> manual (registry + folder) app removal
}

function New-W11Obj { param([hashtable]$Property) return New-Object PSObject -Property $Property }

#region ---------- logging / progress ----------
function Write-W11Log {
    param(
        [Parameter(Mandatory = $true)][string]$En,
        [string]$Vi,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK', 'STEP', 'DRY')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    if ($Vi) { $text = "$En | $Vi" } else { $text = $En }
    $line = "[$ts] [$Level] $text"
    if ($script:W11D.LogPath) {
        try { Add-Content -LiteralPath $script:W11D.LogPath -Value $line -Encoding UTF8 } catch { $null = $_ }
    }
    $s = $script:W11D.Sync
    if ($s) {
        if ($Vi -and $s.UiLang -and $s.UiLang -ne 'vi') { $line = "[$ts] [$Level] $En" }
        $s.LogQueue.Enqueue($line)
    } else {
        $color = 'Gray'
        switch ($Level) { 'WARN' { $color = 'Yellow' } 'ERROR' { $color = 'Red' } 'OK' { $color = 'Green' } 'STEP' { $color = 'Cyan' } 'DRY' { $color = 'Magenta' } }
        Write-Host $line -ForegroundColor $color
    }
}

function Set-W11Progress {
    param([double]$Percent, [string]$Status)
    $s = $script:W11D.Sync
    if ($Percent -gt 100) { $Percent = 100 }
    if ($s) {
        if ($Percent -ge 0) { $s.Percent = $Percent }
        if ($Status) { $s.Status = $Status }
    } elseif ($Status -and $Percent -ge 0) {
        Write-Progress -Activity 'WinDebloat Tool' -Status $Status -PercentComplete ([int]$Percent)
    }
}

function Assert-W11NotCancelled {
    $s = $script:W11D.Sync
    if ($s -and $s.Cancel) { throw (New-Object System.OperationCanceledException 'Cancelled by user / Người dùng đã huỷ') }
}
#endregion

#region ---------- generic helpers ----------
function Test-W11Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal $id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-W11Config {
    <# Settings from config\DebloatConfig.psd1 (download / mirrors) + the app and tweak lists from data\apps.json and
       data\tweaks.json. The lists keep the shape the engine always used: Apps / Tweaks (Windows 11),
       Win10Apps / Win10Tweaks, Protected. Without the JSON files the lists of the .psd1 (if any) are used. #>
    param([string]$Path, [string]$DataDir)
    if (-not $Path) { $Path = Join-Path $script:W11Root 'config\DebloatConfig.psd1' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Config not found: $Path" }
    # Import-LocalizedData parses .psd1 in restricted (data-only) language and exists since PS 2.0
    Import-LocalizedData -BaseDirectory (Split-Path -Parent $Path) -FileName ([IO.Path]::GetFileNameWithoutExtension($Path)) -BindingVariable w11cfg
    if (-not $DataDir) { $DataDir = Join-Path $script:W11Root 'data' }
    $w11cfg.DataSource = 'psd1'
    $ap = Join-Path $DataDir 'apps.json'
    $tp = Join-Path $DataDir 'tweaks.json'
    if (Test-Path -LiteralPath $ap) {
        $a = Import-W11AppData -Path $ap
        $w11cfg.Apps = $a.Win11; $w11cfg.Win10Apps = $a.Win10; $w11cfg.Protected = $a.Protected
        $w11cfg.DataSource = 'json'
    }
    if (Test-Path -LiteralPath $tp) {
        $t = Import-W11TweakData -Path $tp
        $w11cfg.Tweaks = $t.Win11; $w11cfg.Win10Tweaks = $t.Win10
        $w11cfg.DataSource = 'json'
    }
    foreach ($k in @('Apps', 'Win10Apps', 'Tweaks', 'Win10Tweaks', 'Protected')) { if (-not $w11cfg.ContainsKey($k)) { $w11cfg[$k] = @() } }
    return $w11cfg
}

#region ---------- JSON (Windows PowerShell 2.0 has no ConvertFrom-Json) ----------
function ConvertTo-W11Plain {
    # ConvertFrom-Json (PSCustomObject) / JavaScriptSerializer (Dictionary, object[]) output -> hashtables, object[] and plain values
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [bool]) { return $Value }
    if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
        $d = [double]$Value
        if ($d -eq [Math]::Floor($d) -and [Math]::Abs($d) -lt 2147483648) { return [int]$d }
        return $d
    }
    if ($Value -is [long]) { if ([Math]::Abs($Value) -lt 2147483648) { return [int]$Value }; return $Value }
    if ($Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $h = @{}
        foreach ($k in @($Value.Keys)) { $h[[string]$k] = ConvertTo-W11Plain $Value[$k] }
        return $h
    }
    if ($Value.PSObject -and @($Value.PSObject.TypeNames) -contains 'System.Management.Automation.PSCustomObject') {
        $h = @{}
        foreach ($p in @($Value.PSObject.Properties)) { $h[[string]$p.Name] = ConvertTo-W11Plain $p.Value }
        return $h
    }
    if ($Value -is [Collections.IEnumerable]) {
        $l = New-Object Collections.ArrayList
        foreach ($x in $Value) { [void]$l.Add((ConvertTo-W11Plain $x)) }
        return , ($l.ToArray())
    }
    return [string]$Value
}

function ConvertFrom-W11JsonString {
    # JSON string token (with the quotes) -> text
    param([string]$Token)
    $s = $Token.Substring(1, $Token.Length - 2)
    if ($s.IndexOf('\') -lt 0) { return $s }
    $sb = New-Object Text.StringBuilder
    $i = 0
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -ne '\') { [void]$sb.Append($c); $i++; continue }
        $e = $s[$i + 1]
        switch -casesensitive ([string]$e) {
            'n' { [void]$sb.Append("`n") }
            'r' { [void]$sb.Append("`r") }
            't' { [void]$sb.Append("`t") }
            'b' { [void]$sb.Append([char]8) }
            'f' { [void]$sb.Append([char]12) }
            'u' { [void]$sb.Append([char][Convert]::ToInt32($s.Substring($i + 2, 4), 16)); $i += 4 }
            default { [void]$sb.Append($e) }   # \" \\ \/
        }
        $i += 2
    }
    return $sb.ToString()
}

function ConvertFrom-W11JsonText {
    <# Small JSON parser (RFC 8259) for hosts that have neither ConvertFrom-Json (PS 3+) nor
       JavaScriptSerializer (System.Web.Extensions). Objects -> hashtable, arrays -> object[]. #>
    param([string]$Json)
    if ($null -eq $Json) { throw 'JSON: empty text' }
    $rx = New-Object Text.RegularExpressions.Regex '\G\s*(?:("(?:[^"\\\u0000-\u001F]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*")|(-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)|(true|false|null)|([{}\[\]:,]))'
    $pos = 0; $len = $Json.Length
    $stack = New-Object Collections.ArrayList
    $result = $null; $haveResult = $false; $expect = 'value'   # value | key | colon | comma-or-end
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $rxEnd = New-Object Text.RegularExpressions.Regex '\G\s*\z'
    while ($true) {
        if ($pos -ge $len -or $rxEnd.Match($Json, $pos).Success) { break }
        $m = $rx.Match($Json, $pos)
        if (-not $m.Success) { throw "JSON: unexpected character at position $pos" }
        $pos = $m.Index + $m.Length
        $isValue = $false; $val = $null
        if ($m.Groups[1].Success) {
            $str = ConvertFrom-W11JsonString $m.Groups[1].Value
            if ($expect -eq 'key' -or $expect -eq 'key-or-end') { $stack[$stack.Count - 1].Key = $str; $expect = 'colon'; continue }
            $isValue = $true; $val = $str
        } elseif ($m.Groups[2].Success) {
            $t = $m.Groups[2].Value
            if ($t -match '^-?\d+$' -and [Math]::Abs([double]::Parse($t, $inv)) -lt 2147483648) { $val = [int]::Parse($t, $inv) } else { $val = [double]::Parse($t, $inv) }
            $isValue = $true
        } elseif ($m.Groups[3].Success) {
            switch ($m.Groups[3].Value) { 'true' { $val = $true } 'false' { $val = $false } default { $val = $null } }
            $isValue = $true
        } else {
            $p = $m.Groups[4].Value
            if ($p -eq '{' -or $p -eq '[') {
                if ($expect -ne 'value' -and $expect -ne 'value-or-end') { throw "JSON: unexpected '$p' at position $($m.Index)" }
                if ($p -eq '{') { [void]$stack.Add(@{ C = @{}; Obj = $true; Key = $null }); $expect = 'key-or-end' }
                else { [void]$stack.Add(@{ C = (New-Object Collections.ArrayList); Obj = $false; Key = $null }); $expect = 'value-or-end' }
                continue
            }
            if ($p -eq ':') { if ($expect -ne 'colon') { throw "JSON: unexpected ':' at position $($m.Index)" }; $expect = 'value'; continue }
            if ($p -eq ',') {
                if ($expect -ne 'comma-or-end' -or $stack.Count -eq 0) { throw "JSON: unexpected ',' at position $($m.Index)" }
                if ($stack[$stack.Count - 1].Obj) { $expect = 'key' } else { $expect = 'value' }
                continue
            }
            # '}' or ']'
            if ($stack.Count -eq 0) { throw "JSON: unexpected '$p' at position $($m.Index)" }
            $top = $stack[$stack.Count - 1]
            if (($p -eq '}') -ne $top.Obj) { throw "JSON: mismatched '$p' at position $($m.Index)" }
            if ($expect -ne 'comma-or-end' -and $expect -ne 'key-or-end' -and $expect -ne 'value-or-end') { throw "JSON: unexpected '$p' at position $($m.Index)" }
            $stack.RemoveAt($stack.Count - 1)
            if ($top.Obj) { $val = $top.C } else { $val = $top.C.ToArray() }
            $isValue = $true
            $expect = 'value'   # the closed container is a value of its parent
        }
        if ($isValue) {
            if ($expect -eq 'key-or-end' -or $expect -eq 'key' -or $expect -eq 'colon' -or $expect -eq 'comma-or-end') { throw "JSON: unexpected value at position $($m.Index)" }
            if ($stack.Count -eq 0) {
                if ($haveResult) { throw "JSON: extra data at position $($m.Index)" }
                $result = $val; $haveResult = $true; $expect = 'end'
            } else {
                $top = $stack[$stack.Count - 1]
                if ($top.Obj) { $top.C[$top.Key] = $val } else { [void]$top.C.Add($val) }
                $expect = 'comma-or-end'
            }
        }
    }
    if ($stack.Count -gt 0 -or -not $haveResult) { throw 'JSON: unexpected end of text' }
    if ($result -is [Array]) { return , $result }
    return $result
}

function ConvertFrom-W11Json {
    <# JSON text -> hashtables / object[]. ConvertFrom-Json when the host has it (PowerShell 3+), else
       JavaScriptSerializer (.NET 3.5 SP1 / 4.x, System.Web.Extensions), else the built-in parser. #>
    param([string]$Json, [ValidateSet('Auto', 'Native', 'Serializer', 'Parser')][string]$Engine = 'Auto')
    if ($null -eq $Json -or -not $Json.Trim()) { throw 'JSON: empty text' }
    if (($Engine -eq 'Auto' -or $Engine -eq 'Native') -and (Get-Command ConvertFrom-Json -ErrorAction SilentlyContinue)) {
        $o = ConvertFrom-Json -InputObject $Json
        return , (ConvertTo-W11Plain $o)
    }
    if ($Engine -eq 'Auto' -or $Engine -eq 'Serializer') {
        if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
            try { Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop } catch { try { [void][Reflection.Assembly]::LoadWithPartialName('System.Web.Extensions') } catch { $null = $_ } }
        }
        if ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type]) {
            $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
            $ser.MaxJsonLength = 67108864
            return , (ConvertTo-W11Plain ($ser.DeserializeObject($Json)))
        }
        if ($Engine -eq 'Serializer') { throw 'JavaScriptSerializer (System.Web.Extensions) is not available' }
    }
    return , (ConvertFrom-W11JsonText $Json)
}

function Read-W11JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    try { return , (ConvertFrom-W11Json $text) }
    catch { throw "Invalid JSON in $Path ($($_.Exception.Message)) / File JSON bị lỗi: $Path" }
}

function ConvertTo-W11JsonString {
    param([string]$Text)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($c in $Text.ToCharArray()) {
        $n = [int]$c
        if ($c -eq '"') { [void]$sb.Append('\"') }
        elseif ($c -eq '\') { [void]$sb.Append('\\') }
        elseif ($n -eq 10) { [void]$sb.Append('\n') }
        elseif ($n -eq 13) { [void]$sb.Append('\r') }
        elseif ($n -eq 9) { [void]$sb.Append('\t') }
        elseif ($n -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $n)) }
        else { [void]$sb.Append($c) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-W11Json {
    <# Value -> indented JSON text (PS 2.0 has no ConvertTo-Json). Hashtable keys are sorted, an
       OrderedDictionary keeps its order. Arrays of plain values stay on one line. #>
    param($Value, [int]$Indent = 0)
    $pad = '  ' * $Indent
    $inv = [Globalization.CultureInfo]::InvariantCulture
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' }; return 'false' }
    if ($Value -is [string] -or $Value -is [char]) { return (ConvertTo-W11JsonString ([string]$Value)) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [short] -or $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64]) { return ([IFormattable]$Value).ToString($null, $inv) }
    if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) { return ([double]$Value).ToString('R', $inv) }
    if ($Value -is [Collections.IDictionary]) {
        $keys = @($Value.Keys)
        if ($Value -is [hashtable]) { $keys = @($keys | Sort-Object) }
        if ($keys.Count -eq 0) { return '{}' }
        $parts = @()
        foreach ($k in $keys) { $parts += ($pad + '  ' + (ConvertTo-W11JsonString ([string]$k)) + ': ' + (ConvertTo-W11Json $Value[$k] ($Indent + 1))) }
        return ("{`r`n" + ($parts -join ",`r`n") + "`r`n" + $pad + '}')
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = @(); $simple = $true
        foreach ($x in $Value) { $items += , $x; if ($x -is [Collections.IDictionary] -or ($x -is [Collections.IEnumerable] -and -not ($x -is [string]))) { $simple = $false } }
        if ($items.Count -eq 0) { return '[]' }
        if ($simple) { return ('[' + ((@($items | ForEach-Object { ConvertTo-W11Json $_ })) -join ', ') + ']') }
        $parts = @()
        foreach ($x in $items) { $parts += ($pad + '  ' + (ConvertTo-W11Json $x ($Indent + 1))) }
        return ("[`r`n" + ($parts -join ",`r`n") + "`r`n" + $pad + ']')
    }
    return (ConvertTo-W11JsonString ([string]$Value))
}

function New-W11Ordered {
    # OrderedDictionary from name/value pairs (PS 2.0 has no [ordered])
    $d = New-Object Collections.Specialized.OrderedDictionary
    for ($i = 0; $i + 1 -lt $args.Count; $i += 2) { $d[[string]$args[$i]] = $args[$i + 1] }
    return , $d
}
#endregion

#region ---------- data files: data\apps.json, data\tweaks.json ----------
$script:W11UiLangs = @('vi', 'en', 'zh-CN', 'km')
$script:W11Hives = @('SOFTWARE', 'SYSTEM', 'DEFAULT', 'NTUSER')
$script:W11RegTypes = @('REG_DWORD', 'REG_QWORD', 'REG_SZ', 'REG_EXPAND_SZ', 'REG_MULTI_SZ', 'REG_BINARY')

function Get-W11LangText {
    # text table { vi, en, zh-CN, km } -> text in $Lang, else English, else the first non-empty one
    param($Table, [string]$Lang = 'en')
    if ($null -eq $Table) { return '' }
    if ($Table -is [string]) { return $Table }
    if ($Table -is [Collections.IDictionary]) {
        if ($Lang -and $Table.Contains($Lang) -and $Table[$Lang]) { return [string]$Table[$Lang] }
        if ($Table.Contains('en') -and $Table['en']) { return [string]$Table['en'] }
        foreach ($k in @($Table.Keys)) { if ($Table[$k]) { return [string]$Table[$k] } }
    }
    return ''
}

function Get-W11JsonVal {
    # safe lookup in a parsed JSON object (missing key -> $Default)
    param($Object, [string]$Key, $Default = $null)
    if ($null -ne $Object -and $Object -is [Collections.IDictionary] -and $Object.Contains($Key) -and $null -ne $Object[$Key]) { return $Object[$Key] }
    return $Default
}

function Get-W11EntryOsList {
    # 'win10' | 'win11' | 'both' -> Win10 / Win11 profile names
    param([string]$Os)
    switch ($Os) { 'win10' { return @('Win10') } 'win11' { return @('Win11') } 'both' { return @('Win10', 'Win11') } }
    return @()
}

function Test-W11LangTable {
    param($Table)
    if (-not ($Table -is [Collections.IDictionary])) { return $false }
    foreach ($l in $script:W11UiLangs) { if (-not $Table.Contains($l) -or -not ([string]$Table[$l]).Trim()) { return $false } }
    return $true
}

function Test-W11AppData {
    <# Problems (texts) in a parsed apps.json; empty = valid. #>
    param($Data)
    $bad = @()
    if (-not ($Data -is [Collections.IDictionary])) { return @('apps.json: not a JSON object') }
    $apps = @(Get-W11JsonVal $Data 'apps' @())
    if ($apps.Count -eq 0) { $bad += 'apps.json: no apps' }
    $seen = @{}
    $n = 0
    foreach ($a in $apps) {
        $n++
        $p = [string](Get-W11JsonVal $a 'pattern' '')
        $tag = "apps.json #$n ($p)"
        if (-not $p -or $p -notmatch '^[A-Za-z0-9.*_-]+$') { $bad += "${tag}: pattern missing or has characters other than A-Z 0-9 . * _ -" }
        $os = [string](Get-W11JsonVal $a 'os' '')
        if (@('win10', 'win11', 'both') -notcontains $os) { $bad += "${tag}: os must be win10, win11 or both" }
        if (@('safe', 'aggressive', 'unsafe') -notcontains [string](Get-W11JsonVal $a 'level' '')) { $bad += "${tag}: level must be safe, aggressive or unsafe" }
        if (-not ((Get-W11JsonVal $a 'default') -is [bool])) { $bad += "${tag}: default must be true or false" }
        if (-not (Test-W11LangTable (Get-W11JsonVal $a 'name'))) { $bad += "${tag}: name needs vi, en, zh-CN and km" }
        foreach ($o in (Get-W11EntryOsList $os)) { $k = "$o|$p"; if ($seen.ContainsKey($k)) { $bad += "${tag}: listed twice for $o" }; $seen[$k] = 1 }
    }
    foreach ($x in @(Get-W11JsonVal $Data 'protected' @())) { if (-not ([string]$x)) { $bad += 'apps.json: empty protected pattern' } }
    return $bad
}

function Test-W11RegOp {
    param($Op, [string]$Kind, [string]$Tag)
    $bad = @()
    if ($script:W11Hives -notcontains [string](Get-W11JsonVal $Op 'hive' '')) { $bad += "${Tag}: hive must be SOFTWARE, SYSTEM, DEFAULT or NTUSER" }
    $k = [string](Get-W11JsonVal $Op 'key' '')
    if (-not $k -or $k.StartsWith('\') -or $k -match '^HK') { $bad += "${Tag}: key missing (relative to the hive, without HKLM\...)" }
    if ($Kind -ne 'deleteKey' -and -not [string](Get-W11JsonVal $Op 'name' '')) { $bad += "${Tag}: value name missing" }
    if ($Kind -eq 'set') {
        if ($script:W11RegTypes -notcontains [string](Get-W11JsonVal $Op 'type' '')) { $bad += "${Tag}: type must be one of $($script:W11RegTypes -join ', ')" }
        if ($null -eq (Get-W11JsonVal $Op 'value')) { $bad += "${Tag}: value missing" }
    }
    $u = Get-W11JsonVal $Op 'undo'
    if (-not ($u -is [Collections.IDictionary]) -or @('delete', 'set', 'none') -notcontains [string](Get-W11JsonVal $u 'action' '')) { $bad += "${Tag}: undo.action must be delete, set or none" }
    return $bad
}

function Test-W11TweakData {
    <# Problems (texts) in a parsed tweaks.json; empty = valid. #>
    param($Data)
    $bad = @()
    if (-not ($Data -is [Collections.IDictionary])) { return @('tweaks.json: not a JSON object') }
    $list = @(Get-W11JsonVal $Data 'tweaks' @())
    if ($list.Count -eq 0) { $bad += 'tweaks.json: no tweaks' }
    $seen = @{}
    $n = 0
    foreach ($t in $list) {
        $n++
        $id = [string](Get-W11JsonVal $t 'id' '')
        $tag = "tweaks.json #$n ($id)"
        if ($id -notmatch '^[A-Za-z][A-Za-z0-9]*$') { $bad += "${tag}: id must be letters and digits" }
        $os = [string](Get-W11JsonVal $t 'os' '')
        if (@('win10', 'win11', 'both') -notcontains $os) { $bad += "${tag}: os must be win10, win11 or both" }
        if (@('safe', 'aggressive') -notcontains [string](Get-W11JsonVal $t 'level' '')) { $bad += "${tag}: level must be safe or aggressive" }
        if (-not ([string](Get-W11JsonVal $t 'category' ''))) { $bad += "${tag}: category missing" }
        if (-not ((Get-W11JsonVal $t 'default') -is [bool])) { $bad += "${tag}: default must be true or false" }
        if (-not ((Get-W11JsonVal $t 'bootWim' $false) -is [bool])) { $bad += "${tag}: bootWim must be true or false" }
        if (-not (Test-W11LangTable (Get-W11JsonVal $t 'name'))) { $bad += "${tag}: name needs vi, en, zh-CN and km" }
        if (-not (Test-W11LangTable (Get-W11JsonVal $t 'description'))) { $bad += "${tag}: description needs vi, en, zh-CN and km" }
        $ops = 0
        foreach ($kind in @('set', 'deleteKey', 'deleteValue')) {
            $i = 0
            foreach ($op in @(Get-W11JsonVal $t $kind @())) { $i++; $ops++; $bad += @(Test-W11RegOp $op $kind "$tag $kind #$i") }
        }
        if ($ops -eq 0) { $bad += "${tag}: no registry operation (set / deleteKey / deleteValue)" }
        $boot = @(Get-W11JsonVal $t 'bootSet' @())
        if ((Get-W11JsonVal $t 'bootWim' $false) -eq $true) {
            if ($boot.Count -eq 0) { $bad += "${tag}: bootWim is true but bootSet is empty" }
            $i = 0
            foreach ($op in $boot) {
                $i++; $bad += @(Test-W11RegOp $op 'set' "$tag bootSet #$i")
                if (@('SYSTEM', 'SOFTWARE') -notcontains [string](Get-W11JsonVal $op 'hive' '')) { $bad += "$tag bootSet #${i}: boot.wim only has the SYSTEM and SOFTWARE hives" }
            }
        } elseif ($boot.Count -gt 0) { $bad += "${tag}: bootSet given but bootWim is false" }
        foreach ($o in (Get-W11EntryOsList $os)) { $k = "$o|$id"; if ($seen.ContainsKey($k)) { $bad += "${tag}: id used twice for $o" }; $seen[$k] = 1 }
    }
    return $bad
}

function ConvertTo-W11RegOp {
    # JSON registry operation -> engine form (Hive / Key / Value = value name / Type / Data)
    param($Op)
    $h = @{ Hive = [string]$Op['hive']; Key = [string]$Op['key'] }
    if ($Op.Contains('name')) { $h.Value = [string]$Op['name'] }
    if ($Op.Contains('type')) { $h.Type = [string]$Op['type'] }
    if ($Op.Contains('value')) { $h.Data = [string]$Op['value'] }
    if ($Op.Contains('undo')) { $h.Undo = $Op['undo'] }
    return $h
}

function Import-W11AppData {
    <# data\apps.json -> @{ Win11 = entries; Win10 = entries; Protected = patterns }. Entry: Id (= pattern), Name (English),
       Names (per language), Default, Level, Os, MinBuild, MaxBuild. Invalid entries are skipped and logged. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $d = Read-W11JsonFile $Path
    $bad = @(Test-W11AppData $d)
    foreach ($b in $bad) { Write-W11Log -Level WARN -En "  $b" -Vi 'mục này trong danh sách ứng dụng bị lỗi' }
    $out = @{ Win11 = @(); Win10 = @(); Protected = @(@(Get-W11JsonVal $d 'protected' @()) | ForEach-Object { [string]$_ }) }
    foreach ($a in @(Get-W11JsonVal $d 'apps' @())) {
        $p = [string](Get-W11JsonVal $a 'pattern' '')
        if (-not $p -or $p -notmatch '^[A-Za-z0-9.*_-]+$' -or -not (Test-W11LangTable (Get-W11JsonVal $a 'name'))) { continue }
        $e = @{ Id = $p; Names = $a['name']; Name = (Get-W11LangText $a['name'] 'en'); Default = ((Get-W11JsonVal $a 'default' $false) -eq $true)
            Level = [string](Get-W11JsonVal $a 'level' 'aggressive'); Os = [string]$a['os'] }
        if (Get-W11JsonVal $a 'minBuild') { $e.MinBuild = [int]$a['minBuild'] }
        if (Get-W11JsonVal $a 'maxBuild') { $e.MaxBuild = [int]$a['maxBuild'] }
        foreach ($o in (Get-W11EntryOsList $e.Os)) { $out[$o] += $e }
    }
    return $out
}

function Import-W11TweakData {
    <# data\tweaks.json -> @{ Win11 = entries; Win10 = entries } in the engine form: Id, Name / NameVi (log text),
       Names, Descriptions, Category, Level, Default, BootWim, MinBuild, MaxBuild, Set / Delete / DeleteValue / BootSet. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $d = Read-W11JsonFile $Path
    $bad = @(Test-W11TweakData $d)
    foreach ($b in $bad) { Write-W11Log -Level WARN -En "  $b" -Vi 'mục này trong danh sách tinh chỉnh bị lỗi' }
    $badIdx = @{}
    foreach ($b in $bad) { if ($b -match '^tweaks\.json #(\d+) ') { $badIdx[[int]$matches[1]] = 1 } }
    $out = @{ Win11 = @(); Win10 = @() }
    $n = 0
    foreach ($t in @(Get-W11JsonVal $d 'tweaks' @())) {
        $n++
        if ($badIdx.ContainsKey($n)) { continue }
        $e = @{ Id = [string]$t['id']; Names = $t['name']; Descriptions = $t['description']
            Name = (Get-W11LangText $t['description'] 'en'); NameVi = (Get-W11LangText $t['description'] 'vi')
            Category = [string]$t['category']; Level = [string]$t['level']; Default = ($t['default'] -eq $true)
            BootWim = ((Get-W11JsonVal $t 'bootWim' $false) -eq $true); Os = [string]$t['os'] }
        if (Get-W11JsonVal $t 'minBuild') { $e.MinBuild = [int]$t['minBuild'] }
        if (Get-W11JsonVal $t 'maxBuild') { $e.MaxBuild = [int]$t['maxBuild'] }
        $ops = @(@(Get-W11JsonVal $t 'set' @()) | ForEach-Object { ConvertTo-W11RegOp $_ }); if ($ops.Count) { $e.Set = $ops }
        $ops = @(@(Get-W11JsonVal $t 'deleteKey' @()) | ForEach-Object { ConvertTo-W11RegOp $_ }); if ($ops.Count) { $e.Delete = $ops }
        $ops = @(@(Get-W11JsonVal $t 'deleteValue' @()) | ForEach-Object { ConvertTo-W11RegOp $_ }); if ($ops.Count) { $e.DeleteValue = $ops }
        $ops = @(@(Get-W11JsonVal $t 'bootSet' @()) | ForEach-Object { ConvertTo-W11RegOp $_ }); if ($ops.Count) { $e.BootSet = $ops }
        foreach ($o in (Get-W11EntryOsList $e.Os)) { $out[$o] += $e }
    }
    return $out
}
#endregion

function Get-W11FreeGB {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not $Path -or -not $Path.Trim()) { throw 'No folder given / Chưa chọn thư mục' }
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
    if ($root -like '\\*') { throw "Network paths are not supported for the work folder / Không hỗ trợ thư mục mạng: $Path" }
    $d = New-Object IO.DriveInfo $root
    if (-not $d.IsReady) { throw "Drive not found or not ready / Không thấy ổ đĩa hoặc ổ chưa sẵn sàng: $root" }
    return [Math]::Round($d.AvailableFreeSpace / 1GB, 1)
}

function ConvertTo-W11Arg {
    # quoted argument; no trailing '\' (it would escape the closing quote), except a drive root: "D:\\" = D:\
    param([string]$s)
    $t = $s.TrimEnd('\')
    if ($t -match '^[A-Za-z]:$') { return '"' + $t + '\\"' }
    return '"' + $t + '"'
}

function Invoke-W11Process {
    <# Runs a console program (stdout captured, \r progress lines parsed for %), returns ExitCode + Lines. #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = '',
        [switch]$Quiet,
        [double]$ProgressBase = -1,
        [double]$ProgressSpan = 0,
        [string]$ProgressText = '',
        [switch]$MergeStdErr     # run through cmd.exe "2>&1" so tools that log to stderr (oscdimg, 7-Zip) are captured
    )
    $psi = New-Object Diagnostics.ProcessStartInfo
    if ($MergeStdErr) {
        $psi.FileName = Join-Path $env:windir 'System32\cmd.exe'
        $psi.Arguments = '/S /C ""' + $FilePath + '" ' + $Arguments + ' 2>&1"'
    } else {
        $psi.FileName = $FilePath
        $psi.Arguments = $Arguments
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $lines = New-Object Collections.ArrayList
    $cur = New-Object Text.StringBuilder
    $buf = New-Object char[] 4096
    $reader = $p.StandardOutput
    $flush = {
        $l = $cur.ToString().Trim()
        $cur.Length = 0
        if ($l) {
            $m = [regex]::Match($l, '(\d{1,3}(?:[.,]\d+)?)\s?%')
            if ($m.Success -and $ProgressBase -ge 0) {
                $pct = [double]($m.Groups[1].Value -replace ',', '.')
                Set-W11Progress ($ProgressBase + $ProgressSpan * $pct / 100) $ProgressText
            }
            if ($l -notmatch '^\[[=\s]*\d' -and $l -notmatch '^\d{1,3}% complete') {
                [void]$lines.Add($l)
                if (-not $Quiet) { Write-W11Log -En "    $l" }
            }
        }
    }
    while (($n = $reader.Read($buf, 0, $buf.Length)) -gt 0) {
        for ($i = 0; $i -lt $n; $i++) {
            $c = $buf[$i]
            if ($c -eq [char]13 -or $c -eq [char]10 -or $c -eq [char]8) { . $flush } else { [void]$cur.Append($c) }
        }
    }
    . $flush
    $p.WaitForExit()
    return (New-W11Obj @{ ExitCode = $p.ExitCode; Lines = $lines })
}

function Invoke-W11Reg {
    param([Parameter(Mandatory = $true)][string]$Arguments)
    return (Invoke-W11Process -FilePath (Join-Path $env:windir 'System32\reg.exe') -Arguments $Arguments -Quiet).ExitCode
}

function Test-W11Like {
    param([string]$Name, [string[]]$Patterns)
    foreach ($p in $Patterns) { if ($Name -like $p) { return $true } }
    return $false
}

#region ---------- user paths (Windows rules, pure string logic so it behaves the same everywhere) ----------
function ConvertTo-W11CleanPath {
    <# User-typed / pasted path -> plain text: surrounding whitespace and quotes ("..." '...' and the
       typographic ones) and invisible characters (zero-width, BOM, bidi marks from copy/paste) removed,
       non-breaking spaces become spaces. '' when nothing is left. #>
    param([string]$Path)
    if ($null -eq $Path) { return '' }
    $s = [regex]::Replace($Path, '[\u200B-\u200F\u202A-\u202E\u2060-\u2064\uFEFF\u0000-\u001F]', '')
    $s = $s.Replace([string][char]0x00A0, ' ')
    $q = [char[]]@([char]0x22, [char]0x27, [char]0x201C, [char]0x201D, [char]0x201E, [char]0x2018, [char]0x2019, [char]0x00AB, [char]0x00BB)
    $prev = $null
    while ($prev -ne $s) { $prev = $s; $s = $s.Trim().Trim($q) }
    return $s
}

function Get-W11PathRoot {
    # 'D:\' for 'D:\a\b', '\\server\share\' for UNC; $null when the (normalized) path has no root
    param([string]$Path)
    if ($Path -match '^([A-Za-z]:\\)') { return $matches[1].ToUpper() }
    if ($Path -match '^(\\\\[^\\]+\\[^\\]+\\?)') { $r = $matches[1]; if (-not $r.EndsWith('\')) { $r += '\' }; return $r }
    return $null
}

function Resolve-W11FullPath {
    <# Cleaned, absolute Windows path, or $null when it is not a usable path. Works the way Windows does, but
       without [IO.Path]::GetFullPath, whose base folder is the process folder (System32 when elevated):
       relative paths are resolved against -BaseDir (default: the current PowerShell folder);
       'D:' -> 'D:\', 'D:x.iso' -> 'D:\x.iso', '\x.iso' -> root of the base drive; '/' -> '\'; repeated '\',
       '.' and '..' collapse; trailing dots/spaces of each part are dropped (as Windows does); a trailing
       '\' is removed except on a root. Invalid: characters <>:"|?* (':' only after the drive), reserved device
       names (CON, NUL, COM1...), '\\?\' / '\\.\' device paths, '..' above the root, a bare '\\server'. #>
    param([string]$Path, [string]$BaseDir)
    $p = ConvertTo-W11CleanPath $Path
    if (-not $p) { return $null }
    if ($env:OS -ne 'Windows_NT' -and $p.StartsWith('/') -and -not $p.StartsWith('//')) { try { return [IO.Path]::GetFullPath($p) } catch { return $null } }   # test host (Linux) only
    $p = $p.Replace('/', '\')
    if ($p.StartsWith('\\?\') -or $p.StartsWith('\\.\')) { return $null }
    $unc = $p.StartsWith('\\')
    if ($p -match '^[A-Za-z]:$') { $p += '\' }
    elseif ($p -match '^([A-Za-z]:)([^\\].*)$') { $p = $matches[1] + '\' + $matches[2] }
    if (-not $unc -and $p -notmatch '^[A-Za-z]:\\') {
        if (-not $BaseDir) { try { $BaseDir = (Get-Location -PSProvider FileSystem).ProviderPath } catch { $BaseDir = $null } }
        $b = $null; if ($BaseDir) { $b = Resolve-W11FullPath $BaseDir 'C:\' }
        if (-not $b) { return $null }
        if ($p.StartsWith('\')) { $p = (Get-W11PathRoot $b) + $p.TrimStart('\') } else { $p = $b.TrimEnd('\') + '\' + $p }
        $unc = $p.StartsWith('\\')
    }
    if ($unc) {
        $parts = @($p.Substring(2).Split('\') | Where-Object { $_ -ne '' })
        if ($parts.Count -lt 2) { return $null }
        $root = '\\' + $parts[0] + '\' + $parts[1] + '\'
        $rest = @(); if ($parts.Count -gt 2) { $rest = $parts[2..($parts.Count - 1)] }
        foreach ($x in @($parts[0], $parts[1])) { if ($x.IndexOfAny([char[]]'<>:"|?*') -ge 0 -or $x -eq '.' -or $x -eq '..') { return $null } }
    } else {
        $root = $p.Substring(0, 3).ToUpper()
        $rest = @($p.Substring(3).Split('\'))
    }
    $out = New-Object Collections.ArrayList
    foreach ($seg in $rest) {
        if ($seg -eq '' -or $seg -eq '.') { continue }
        if ($seg -eq '..') { if ($out.Count -eq 0) { return $null }; $out.RemoveAt($out.Count - 1); continue }
        $seg = $seg.TrimEnd([char[]]@('.', ' '))
        if (-not $seg) { continue }
        if ($seg.IndexOfAny([char[]]'<>:"|?*') -ge 0) { return $null }
        if ($seg -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$') { return $null }
        [void]$out.Add($seg)
    }
    $full = $root + ([string[]]$out.ToArray() -join '\')
    if ($env:OS -eq 'Windows_NT') { try { $null = [IO.Path]::GetFullPath($full) } catch { return $null } }
    return $full
}

function Get-W11ParentDir {
    # folder of a normalized full path: 'D:\x.iso' -> 'D:\', 'D:\a\x.iso' -> 'D:\a', '\\srv\sh\x.iso' -> '\\srv\sh\';
    # $null for a root (it has no parent)
    param([string]$FullPath)
    $root = Get-W11PathRoot $FullPath
    if (-not $root -and $FullPath -and $FullPath.StartsWith('/') -and -not $FullPath.StartsWith('//')) { return [IO.Path]::GetDirectoryName($FullPath) }   # test host (Linux) only
    if (-not $root) { return $null }
    $t = $FullPath.TrimEnd('\')
    if ($t.Length -le $root.TrimEnd('\').Length) { return $null }
    $i = $t.LastIndexOf('\')
    if ($i -lt $root.Length) { return $root }
    return $t.Substring(0, $i)
}

function Test-W11IsPathRoot {
    param([string]$FullPath)
    if ($FullPath -eq '/') { return $true }
    $root = Get-W11PathRoot $FullPath
    return [bool]($root -and $FullPath.TrimEnd('\') -eq $root.TrimEnd('\'))
}

function Get-W11PathLeaf {
    # last part of a path ('D:\a\x.iso' -> 'x.iso'), '\' and '/' both count
    param([string]$Path)
    if (-not $Path) { return '' }
    $t = $Path.TrimEnd([char[]]@('\', '/'))
    $i = $t.LastIndexOfAny([char[]]@('\', '/'))
    return $t.Substring($i + 1)
}

function Join-W11Path {
    # folder + name without Join-Path (no provider / drive lookups); keeps the separator style of the folder
    param([string]$Dir, [string]$Name)
    if (-not $Dir) { return $Name }
    $sep = '\'; if ($Dir.StartsWith('/')) { $sep = '/' }
    return ($Dir.TrimEnd([char[]]@('\', '/')) + $sep + $Name)
}

function New-W11Directory {
    <# Creates a folder (and its parents) when it is missing. Never calls New-Item on a drive root: Windows
       PowerShell 5.1 New-Item (Directory, -Force) on "D:\" throws "The path is not of a legal form". #>
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not $Path) { throw 'No folder given / Chưa có thư mục' }
    if (Test-Path -LiteralPath $Path -PathType Container) { return }
    if (Test-W11IsPathRoot $Path) { throw "Drive or network share not found: $Path / Không thấy ổ đĩa hoặc thư mục mạng: $Path" }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { throw "A file with this name already exists, a folder is needed: $Path / Đã có một file trùng tên, cần một thư mục: $Path" }
    $null = [IO.Directory]::CreateDirectory($Path)
}

function Get-W11DefaultWorkDir {
    # work folder next to the output ISO (same drive = no copy across drives); %TEMP% for a network output
    param([string]$OutDir)
    if ($OutDir -and -not $OutDir.StartsWith('\\')) { return ($OutDir.TrimEnd('\') + '\WinDebloat_work') }
    $t = Resolve-W11FullPath $env:TEMP
    if (-not $t) { $t = [IO.Path]::GetTempPath() }
    return ($t.TrimEnd('\') + '\WinDebloat_work')
}
#endregion

function Test-W11PathText {
    <# Safe path check for user-typed / empty values: $false (never an exception) for empty, whitespace,
       invalid characters or a missing item. -Leaf = file, -Container = folder. #>
    param([string]$Path, [switch]$Leaf, [switch]$Container)
    if (-not $Path -or -not $Path.Trim()) { return $false }
    $Path = $Path.Trim().Trim('"')
    if (-not $Path -or $Path.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return $false }
    try {
        if ($Leaf) { return (Test-Path -LiteralPath $Path -PathType Leaf) }
        if ($Container) { return (Test-Path -LiteralPath $Path -PathType Container) }
        return (Test-Path -LiteralPath $Path)
    } catch { return $false }
}

function Get-W11Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = New-Object Security.Cryptography.SHA256Managed
    $fs = [IO.File]::OpenRead($Path)
    try { $h = $sha.ComputeHash($fs) } finally { $fs.Close() }
    return ([BitConverter]::ToString($h) -replace '-', '')
}

function Get-W11IsoLabel {
    # Reads the ISO9660 primary volume descriptor (sector 16, bytes 40..71).
    param([Parameter(Mandatory = $true)][string]$IsoPath)
    try {
        $fs = [IO.File]::OpenRead($IsoPath)
        try {
            $buf = New-Object byte[] 2048
            [void]$fs.Seek(16 * 2048, [IO.SeekOrigin]::Begin)
            [void]$fs.Read($buf, 0, 2048)
            return [Text.Encoding]::ASCII.GetString($buf, 40, 32).Trim()
        } finally { $fs.Close() }
    } catch { return '' }
}
#endregion

#region ---------- environment / capabilities ----------
function Get-W11OsBuild { return [Environment]::OSVersion.Version.Build }

function Get-W11NetFx4Release {
    try {
        $k = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Stop
        return [int]$k.Release
    } catch { return 0 }
}

function Get-W11NetFx4Name([int]$Release) {
    if ($Release -ge 533320) { return '4.8.1' }
    if ($Release -ge 528040) { return '4.8' }
    if ($Release -ge 461808) { return '4.7.2' }
    if ($Release -ge 460798) { return '4.7' }
    if ($Release -ge 394802) { return '4.6.2' }
    if ($Release -ge 393295) { return '4.6' }
    if ($Release -ge 379893) { return '4.5.2' }
    if ($Release -ge 378389) { return '4.5' }
    if ($Release -gt 0) { return '4.x' }
    return 'none'
}

function Enable-W11Tls12 {
    # 3072 = Tls12. Returns $false when the running .NET cannot do TLS 1.2.
    try {
        $cur = [int][Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], ($cur -bor 3072))
        return (([int][Net.ServicePointManager]::SecurityProtocol -band 3072) -eq 3072)
    } catch { return $false }
}

function Find-W11SevenZip {
    $c = @()
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)) { if ($pf) { $c += (Join-Path $pf '7-Zip\7z.exe') } }
    $c += (Join-Path $script:W11Root 'tools\7z.exe')
    foreach ($x in $c) { if (Test-Path -LiteralPath $x) { return $x } }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Definition }
    return $null
}

function Get-W11KitRoots {
    $roots = @()
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $pf) { continue }
        foreach ($v in @('10', '8.1', '8.0')) { $roots += (Join-Path $pf "Windows Kits\$v\Assessment and Deployment Kit\Deployment Tools") }
    }
    return $roots
}

function Get-W11HostArch {
    $a = $env:PROCESSOR_ARCHITEW6432; if (-not $a) { $a = $env:PROCESSOR_ARCHITECTURE }
    switch ($a) { 'ARM64' { return 'arm64' } 'x86' { return 'x86' } default { return 'amd64' } }
}

function Get-W11OscdimgCandidates {
    <# Where oscdimg.exe is looked for, best first: the given path, <tool>\tools, <tool>\tools\Oscdimg, then every
       ADK "Deployment Tools\<arch>\Oscdimg" (host architecture first, then amd64, x86). No file access. #>
    param([string]$Hint, [string]$Arch = (Get-W11HostArch), [string[]]$KitRoots = (Get-W11KitRoots), [string]$ToolRoot = $script:W11Root)
    $c = @()
    if ($Hint) { $c += $Hint }
    if ($ToolRoot) { $t = Join-W11Path $ToolRoot 'tools'; $c += (Join-W11Path $t 'oscdimg.exe'); $c += (Join-W11Path (Join-W11Path $t 'Oscdimg') 'oscdimg.exe') }
    $archs = @($Arch); foreach ($a in @('amd64', 'x86')) { if ($archs -notcontains $a) { $archs += $a } }
    foreach ($k in @($KitRoots)) { if (-not $k) { continue }; foreach ($a in $archs) { $c += (Join-W11Path (Join-W11Path (Join-W11Path $k $a) 'Oscdimg') 'oscdimg.exe') } }
    return $c
}

function Find-W11Oscdimg {
    param([string]$Hint)
    foreach ($x in @(Get-W11OscdimgCandidates -Hint $Hint)) { if ($x -and (Test-Path -LiteralPath $x)) { return $x } }
    $cmd = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Definition }
    return $null
}

function Get-W11DismCandidates {
    <# All dism.exe we can use, best first. Major >= 10 is required for Windows 11 images. #>
    param([string]$IsoSourcesDir)
    $arch = Get-W11HostArch
    $list = @()
    $add = {
        param($path, $kind)
        if ($path -and (Test-Path -LiteralPath $path)) {
            $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($path)
            $script:__c += (New-W11Obj @{ Path = $path; Kind = $kind; Major = $vi.FileMajorPart; Build = $vi.FileBuildPart; Version = ('{0}.{1}.{2}' -f $vi.FileMajorPart, $vi.FileMinorPart, $vi.FileBuildPart) })
        }
    }
    $script:__c = @()
    foreach ($k in Get-W11KitRoots) { foreach ($a in @($arch, 'amd64', 'x86')) { & $add (Join-Path $k "$a\DISM\dism.exe") 'ADK' } }
    $sysnative = Join-Path $env:windir 'Sysnative\dism.exe'
    if (Test-Path -LiteralPath $sysnative) { & $add $sysnative 'System' } else { & $add (Join-Path $env:windir 'System32\dism.exe') 'System' }
    if ($IsoSourcesDir) { & $add (Join-Path $IsoSourcesDir 'dism.exe') 'ISO' }
    $list = @($script:__c | Sort-Object -Property @{ Expression = { if ($_.Kind -eq 'ADK') { 0 } elseif ($_.Kind -eq 'System') { 1 } else { 2 } } }, @{ Expression = { $_.Build }; Descending = $true })
    return $list
}

function Select-W11Dism {
    param([string]$IsoSourcesDir)
    $c = @(Get-W11DismCandidates -IsoSourcesDir $IsoSourcesDir)
    $good = @($c | Where-Object { $_.Major -ge 10 -and $_.Kind -ne 'ISO' })
    if ($good.Count -gt 0) {
        $script:W11D.Dism = $good[0].Path; $script:W11D.DismCanAppx = $true
        return $good[0]
    }
    $iso = @($c | Where-Object { $_.Kind -eq 'ISO' })
    if ($iso.Count -gt 0) {
        $script:W11D.Dism = $iso[0].Path
        $script:W11D.DismCanAppx = (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $iso[0].Path) 'appxprovider.dll'))
        Write-W11Log -Level WARN -En "No Windows 10/11 DISM on this PC - using the ISO's own DISM (EXPERIMENTAL): $($iso[0].Path)" -Vi 'Máy không có DISM bản Win10/11 - dùng DISM có sẵn trong ISO (THỬ NGHIỆM)'
        return $iso[0]
    }
    throw 'No usable DISM (need Windows 10/11 DISM or ADK) / Không có DISM phù hợp (cần DISM Win10/11 hoặc ADK)'
}

function Get-W11Capabilities {
    <# Startup capability check. Returns objects (Item, Value, Ok, Hint) and logs them. #>
    param([string]$WorkPath, [int]$MinFreeGB = 25)
    $r = @()
    $os = $null; try { $os = Get-WmiObject Win32_OperatingSystem -ErrorAction Stop } catch { $null = $_ }
    $build = Get-W11OsBuild
    $osName = [Environment]::OSVersion.VersionString
    if ($os) { $osName = "$($os.Caption) (build $($os.BuildNumber), $($os.OSArchitecture))" }
    $r += (New-W11Obj @{ Item = 'Windows'; Value = $osName; Ok = ($build -ge 7601); Hint = 'Windows 7 SP1 or newer required / Cần Windows 7 SP1 trở lên' })

    $psv = $PSVersionTable.PSVersion
    $r += (New-W11Obj @{ Item = 'PowerShell'; Value = "$psv (CLR $($PSVersionTable.CLRVersion))"; Ok = $true
            Hint = $(if ($psv.Major -lt 3) { 'Works on PS 2.0, but WMF 5.1 (KB3191566, needs .NET 4.5.2+) is recommended / Chạy được trên PS 2.0 nhưng nên cài WMF 5.1' } else { '' }) })

    $rel = Get-W11NetFx4Release
    $r += (New-W11Obj @{ Item = '.NET Framework 4'; Value = (Get-W11NetFx4Name $rel); Ok = $true
            Hint = $(if ($rel -lt 379893) { '.NET 4.5.2+ recommended (TLS 1.2 + WMF 5.1) / Nên cài .NET 4.5.2 trở lên' } else { '' }) })

    $tls = Enable-W11Tls12
    $r += (New-W11Obj @{ Item = 'TLS 1.2'; Value = $(if ($tls) { 'available' } else { 'NOT available' }); Ok = $tls
            Hint = $(if (-not $tls) { 'Downloads will fail. Win7: install KB3140245 + .NET 4.5.2+ (or KB3154518 for .NET 3.5.1) and WMF 5.1 / Tải về sẽ lỗi: Win7 cần KB3140245 + .NET 4.5.2+ (hoặc KB3154518) và WMF 5.1' } else { '' }) })

    $adm = Test-W11Admin
    $r += (New-W11Obj @{ Item = 'Administrator'; Value = "$adm"; Ok = $adm; Hint = $(if (-not $adm) { 'Run run.bat (it self-elevates) / Hãy chạy run.bat (tự xin quyền admin)' } else { '' }) })

    $mdi = [bool](Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)
    $sz = Find-W11SevenZip
    $isoOk = $mdi -or [bool]$sz
    $isoVal = 'Mount-DiskImage'; if (-not $mdi) { if ($sz) { $isoVal = "7-Zip: $sz" } else { $isoVal = 'none' } }
    $r += (New-W11Obj @{ Item = 'ISO access'; Value = $isoVal; Ok = $isoOk
            Hint = $(if (-not $isoOk) { 'Windows 7 cannot mount ISO: install 7-Zip (7-zip.org) / Win7 không mount được ISO: hãy cài 7-Zip' } else { '' }) })

    $dc = @(Get-W11DismCandidates)
    $dgood = @($dc | Where-Object { $_.Major -ge 10 })
    $dv = ($dc | ForEach-Object { "$($_.Kind) $($_.Version)" }) -join '; '
    if (-not $dv) { $dv = 'none' }
    $r += (New-W11Obj @{ Item = 'DISM'; Value = $dv; Ok = ($dgood.Count -gt 0)
            Hint = $(if ($dgood.Count -eq 0) { 'Windows 7/8.x DISM cannot service Windows 11. The ISO''s own DISM will be tried (experimental, apps removed via registry method). Best: run this tool on Windows 10/11 / DISM của Win7/8 không xử lý được Win11; sẽ thử DISM trong ISO (thử nghiệm). Tốt nhất chạy trên Win10/11' } else { '' }) })

    $osc = Find-W11Oscdimg
    $oscHint = ''
    if (-not $osc) {
        if ($build -ge 10240) { $oscHint = 'Missing: press "Install oscdimg" (or START) to install the official "ADK Deployment Tools" from Microsoft, or get them from https://learn.microsoft.com/windows-hardware/get-started/adk-install / Thiếu: bấm "Cài oscdimg" (hoặc BẮT ĐẦU) để cài ADK Deployment Tools chính thức của Microsoft' }
        else { $oscHint = 'Missing: current ADK does not install on Win7/8.x. Copy oscdimg.exe from a Win10/11 PC (ADK\Deployment Tools\amd64\Oscdimg) into the tools\ folder / Thiếu: ADK mới không cài được trên Win7/8; hãy chép oscdimg.exe từ máy Win10/11 có ADK vào thư mục tools\' }
    }
    $oscVal = 'not found'; if ($osc) { $oscVal = $osc }
    $r += (New-W11Obj @{ Item = 'oscdimg'; Value = $oscVal; Ok = [bool]$osc; Hint = $oscHint })

    if (Get-Command Find-MsAria2 -ErrorAction SilentlyContinue) {
        $a2 = $null; try { $a2 = Find-MsAria2 } catch { $a2 = $null }
        $a2Val = 'not found - downloads use one connection / không có, tải một luồng'; $a2Hint = ''
        if ($a2) { $a2Val = $a2 }
        if ($a2 -and $build -lt 9200) { $a2Hint = 'Windows 7: aria2 uses the system TLS (schannel); without TLS 1.2 updates (KB3140245) it fails and the tool falls back to the single-connection download / Win7: aria2 dùng TLS của hệ thống; thiếu bản cập nhật TLS 1.2 (KB3140245) thì tool tự chuyển sang tải một luồng' }
        $r += (New-W11Obj @{ Item = 'aria2'; Value = $a2Val; Ok = $true; Hint = $a2Hint })
    }

    if ($WorkPath) {
        try {
            $free = Get-W11FreeGB -Path $WorkPath
            $r += (New-W11Obj @{ Item = 'Free space'; Value = "$free GB @ $([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($WorkPath)))"; Ok = ($free -ge $MinFreeGB); Hint = $(if ($free -lt $MinFreeGB) { "Need >= $MinFreeGB GB / Cần trống ít nhất $MinFreeGB GB" } else { '' }) })
        } catch { $r += (New-W11Obj @{ Item = 'Free space'; Value = $_.Exception.Message; Ok = $false; Hint = '' }) }
    }

    Write-W11Log -Level STEP -En '===== System check =====' -Vi '===== Kiểm tra hệ thống ====='
    foreach ($x in $r) {
        if ($x.Ok) { $lvl = 'OK' } else { $lvl = 'WARN' }
        Write-W11Log -Level $lvl -En ('{0,-16}: {1}' -f $x.Item, $x.Value)
        if ($x.Hint) { Write-W11Log -Level $lvl -En "    -> $($x.Hint)" }
    }
    return $r
}

function Get-W11AdkSetupPlan {
    <# Which official ADK installer to use on this host and how to call it (no network):
       Windows 10/11 -> current ADK; Windows 7 SP1 / 8.x -> ADK for Windows 10 1607 (best effort); older -> not supported.
       Only the "Deployment Tools" feature is installed (oscdimg.exe + DISM). #>
    param([int]$HostBuild = (Get-W11OsBuild), [string]$InstallPath)
    $a = '/quiet /norestart /ceip off /features OptionId.DeploymentTools'
    if ($InstallPath) { $a += (' /installpath {0}' -f (ConvertTo-W11Arg $InstallPath)) }
    $legacy = ($HostBuild -lt 10240)
    $url = $script:W11D.AdkSetupUrl; $ver = $script:W11D.AdkVersion
    if ($legacy) { $url = $script:W11D.AdkLegacyUrl; $ver = $script:W11D.AdkLegacyVersion }
    return (New-W11Obj @{ Url = $url; Version = $ver; Arguments = $a; Legacy = $legacy; Supported = ($HostBuild -ge 7601)
            SuccessCodes = @(0, 3010); FileName = 'adksetup.exe' })
}

function Test-W11MicrosoftSignature {
    # Authenticode check of a downloaded installer: valid and signed by Microsoft Corporation.
    # Returns @{ Ok; Status; Signer; Checked } - Checked = $false when Get-AuthenticodeSignature is not available.
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) { return (New-W11Obj @{ Ok = $true; Status = 'NotChecked'; Signer = ''; Checked = $false }) }
    $sig = Get-AuthenticodeSignature -FilePath $Path
    $subj = ''; if ($sig.SignerCertificate) { $subj = [string]$sig.SignerCertificate.Subject }
    $ok = ([string]$sig.Status -eq 'Valid' -and $subj -match 'O=Microsoft Corporation')
    return (New-W11Obj @{ Ok = $ok; Status = [string]$sig.Status; Signer = $subj; Checked = $true })
}

function Install-W11Oscdimg {
    <# Installs ONLY "Deployment Tools" of the official Windows ADK (contains oscdimg.exe + DISM), downloaded from
       Microsoft (go.microsoft.com) and checked to be signed by Microsoft. Windows 10/11: current ADK; Windows 7 SP1 /
       8.x: ADK for Windows 10 1607 (best effort - if it fails, copy oscdimg.exe into tools\). Needs administrator
       rights and internet. Returns the path of oscdimg.exe. #>
    param([ValidateSet('AdkSetup', 'Winget')][string]$Method = 'AdkSetup')
    $already = Find-W11Oscdimg
    if ($already) { Write-W11Log -Level OK -En "oscdimg already available: $already" -Vi 'Đã có oscdimg'; return $already }
    $plan = Get-W11AdkSetupPlan
    $toolsDir = Join-Path $script:W11Root 'tools'
    if (-not $plan.Supported) { throw "This Windows version cannot install the Windows ADK. Copy oscdimg.exe into $toolsDir / Phiên bản Windows này không cài được Windows ADK, hãy chép oscdimg.exe vào $toolsDir" }
    if (-not (Test-W11Admin)) { throw 'Installing the Windows ADK needs administrator rights: start the tool with run.bat (it asks for them) / Cài Windows ADK cần quyền quản trị: hãy mở công cụ bằng run.bat (tự xin quyền)' }
    if ($Method -eq 'Winget') {
        if ($plan.Legacy) { throw 'winget is not available on this Windows version / Windows này không có winget' }
        $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $wg) { throw 'winget not found / Không tìm thấy winget' }
        Write-W11Log -Level STEP -En 'Installing Windows ADK Deployment Tools via winget...' -Vi 'Đang cài ADK Deployment Tools bằng winget...'
        $res = Invoke-W11Process -FilePath $wg.Definition -Arguments ('install --id Microsoft.WindowsADK -e --accept-package-agreements --accept-source-agreements --override "{0}"' -f $plan.Arguments)
        Write-W11Log -En "winget exit code: $($res.ExitCode)"
    } else {
        if (-not (Enable-W11Tls12)) { throw 'TLS 1.2 is not available, so Microsoft cannot be reached (Windows 7: install KB3140245 and .NET 4.5.2+) / Không có TLS 1.2 nên không kết nối được Microsoft (Win7: cài KB3140245 và .NET 4.5.2+)' }
        $tmp = $env:TEMP; if (-not $tmp) { $tmp = $script:W11Root }
        $exe = Join-Path $tmp $plan.FileName
        if ($plan.Legacy) { Write-W11Log -Level WARN -En "Windows 7/8.x host: trying $($plan.Version). If it does not install, copy oscdimg.exe into $toolsDir" -Vi "Máy Win7/8: thử $($plan.Version); nếu không cài được, hãy chép oscdimg.exe vào $toolsDir" }
        Write-W11Log -Level STEP -En "Downloading the official ADK installer $($plan.Version): $($plan.Url)" -Vi 'Đang tải bộ cài ADK chính thức của Microsoft...'
        $wc = New-Object Net.WebClient
        try { $wc.DownloadFile($plan.Url, $exe) }
        catch { throw "Could not download the ADK installer (no internet, proxy or firewall?): $($_.Exception.Message) / Không tải được bộ cài ADK (mất mạng, proxy hoặc tường lửa?)" }
        finally { $wc.Dispose() }
        $sig = Test-W11MicrosoftSignature -Path $exe
        if (-not $sig.Ok) {
            Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
            throw "adksetup.exe signature check failed ($($sig.Status) $($sig.Signer)) / Chữ ký số của adksetup.exe không hợp lệ ($($sig.Status))"
        }
        if ($sig.Checked) { Write-W11Log -Level OK -En "Signature OK ($($sig.Signer))." -Vi 'Chữ ký số hợp lệ (Microsoft Corporation).' }
        else { Write-W11Log -Level WARN -En 'Get-AuthenticodeSignature is not available - signature not checked (downloaded over HTTPS from go.microsoft.com).' -Vi 'Không kiểm tra được chữ ký số trên máy này (đã tải qua HTTPS từ go.microsoft.com).' }
        Write-W11Log -Level STEP -En "Installing Deployment Tools only (several minutes): adksetup.exe $($plan.Arguments)" -Vi 'Đang cài Deployment Tools (mất vài phút)...'
        $p = Start-Process -FilePath $exe -ArgumentList $plan.Arguments -Wait -PassThru
        Write-W11Log -En "adksetup exit code: $($p.ExitCode)"
        if ($plan.SuccessCodes -notcontains [int]$p.ExitCode) {
            $why = "adksetup.exe failed (exit code $($p.ExitCode)). Log: %TEMP%\adk\*.log"
            if ($plan.Legacy) { $why += ". Copy oscdimg.exe from a Windows 10/11 PC (ADK\Deployment Tools\amd64\Oscdimg) into $toolsDir" }
            throw "$why / Cài ADK lỗi (mã $($p.ExitCode))"
        }
    }
    $found = Find-W11Oscdimg
    if (-not $found) { throw "oscdimg.exe still not found after the ADK install. Copy it into $toolsDir / Vẫn không thấy oscdimg.exe sau khi cài ADK, hãy chép vào $toolsDir" }
    Write-W11Log -Level OK -En "oscdimg: $found" -Vi 'Đã có oscdimg'
    return $found
}
#endregion

#region ---------- ISO access ----------
function Open-W11Iso {
    <# Win8+: Mount-DiskImage (read-only). Win7: extract with 7-Zip into $ExtractTo.
       Returns Root, Label, Mode ('Mounted'|'Extracted'). #>
    param([Parameter(Mandatory = $true)][string]$IsoPath, [string]$ExtractTo)
    $label = Get-W11IsoLabel -IsoPath $IsoPath
    if (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue) {
        $img = Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -Access ReadOnly -PassThru
        $letter = $null
        for ($i = 0; $i -lt 20 -and -not $letter; $i++) {
            $vol = $img | Get-Volume -ErrorAction SilentlyContinue
            if ($vol -and $vol.DriveLetter) { $letter = $vol.DriveLetter } else { Start-Sleep -Milliseconds 500 }
        }
        if (-not $letter) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue; throw 'ISO mounted but has no drive letter / ISO không có ký tự ổ' }
        return (New-W11Obj @{ Root = "$($letter):\"; Label = $label; Mode = 'Mounted' })
    }
    $sz = Find-W11SevenZip
    if (-not $sz) { throw 'Cannot open ISO: Mount-DiskImage needs Windows 8+, or install 7-Zip / Không mở được ISO: cần Win8+ hoặc cài 7-Zip' }
    if (-not $ExtractTo) { throw 'Extraction target required' }
    New-W11Directory $ExtractTo
    Write-W11Log -Level STEP -En "Extracting ISO with 7-Zip (no Mount-DiskImage on this Windows)..." -Vi 'Đang giải nén ISO bằng 7-Zip...'
    $res = Invoke-W11Process -FilePath $sz -Arguments ('x -y -o{0} {1}' -f (ConvertTo-W11Arg $ExtractTo), (ConvertTo-W11Arg $IsoPath)) -Quiet -MergeStdErr -ProgressBase 5 -ProgressSpan 10 -ProgressText 'Extracting ISO / Giải nén ISO'
    if ($res.ExitCode -ne 0) { throw "7-Zip failed (exit $($res.ExitCode))" }
    return (New-W11Obj @{ Root = $ExtractTo; Label = $label; Mode = 'Extracted' })
}

function Close-W11Iso {
    param($Iso, [string]$IsoPath)
    if ($Iso -and $Iso.Mode -eq 'Mounted') { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
}
#endregion

#region ---------- DISM wrappers ----------
function Invoke-W11Dism {
    param([Parameter(Mandatory = $true)][string]$Arguments, [switch]$Quiet, [double]$ProgressBase = -1, [double]$ProgressSpan = 0, [string]$ProgressText = '', [switch]$NoThrow)
    if (-not $script:W11D.Dism) { throw 'DISM not selected' }
    $res = Invoke-W11Process -FilePath $script:W11D.Dism -Arguments ("/English $Arguments") -Quiet:$Quiet -ProgressBase $ProgressBase -ProgressSpan $ProgressSpan -ProgressText $ProgressText
    if (-not $NoThrow -and $res.ExitCode -ne 0 -and $res.ExitCode -ne 3010) {
        if ($Quiet) { foreach ($l in ($res.Lines | Select-Object -Last 8)) { Write-W11Log -Level ERROR -En "    $l" } }
        throw ('DISM failed (exit {0}): {1}' -f $res.ExitCode, $Arguments)
    }
    return $res
}

function Get-W11ImageInfo {
    param([Parameter(Mandatory = $true)][string]$ImageFile)
    $res = Invoke-W11Dism ('/Get-ImageInfo /ImageFile:{0}' -f (ConvertTo-W11Arg $ImageFile)) -Quiet
    $idx = @($res.Lines | ForEach-Object { if ($_ -match '^Index\s*:\s*(\d+)') { [int]$Matches[1] } })
    $out = @()
    foreach ($i in $idx) {
        $d = Invoke-W11Dism ('/Get-ImageInfo /ImageFile:{0} /Index:{1}' -f (ConvertTo-W11Arg $ImageFile), $i) -Quiet
        $o = @{ Index = $i; Name = ''; EditionId = ''; Architecture = 'x64'; Languages = @(); DefaultLanguage = 'en-US'; Build = 0 }
        $inLang = $false
        foreach ($l in $d.Lines) {
            if ($l -match '^Name\s*:\s*(.+)$') { $o.Name = $Matches[1].Trim(); $inLang = $false; continue }
            if ($l -match '^Edition\s*:\s*(.+)$') { $o.EditionId = $Matches[1].Trim(); $inLang = $false; continue }
            if ($l -match '^Architecture\s*:\s*(.+)$') { $o.Architecture = $Matches[1].Trim(); $inLang = $false; continue }
            if ($l -match '^Version\s*:\s*\d+\.\d+\.(\d+)') { $o.Build = [int]$Matches[1]; $inLang = $false; continue }
            if ($l -match '^Languages\s*:') { $inLang = $true; continue }
            if ($inLang -and $l -match '^([a-z]{2,3}-[A-Za-z-]+)(\s*\(Default\))?') {
                $o.Languages += $Matches[1]
                if ($Matches[2]) { $o.DefaultLanguage = $Matches[1] }
                continue
            }
            if ($l -match '^\S+\s*:') { $inLang = $false }
        }
        $out += (New-W11Obj $o)
    }
    return $out
}
#endregion

#region ---------- target OS detection / profiles ----------
function Resolve-W11OsFromBuild {
    # 22000+ = Windows 11, 10240..21999 = Windows 10 (19041-19045 = 2004..22H2)
    param([int]$Build)
    if ($Build -ge 22000) { return 'Win11' }
    if ($Build -ge 10240) { return 'Win10' }
    return $null
}

function Get-W11OsFromName {
    # Best-effort guess from a file name such as Win10_22H2_English_x64v1.iso / Win11_25H2_English_x64.iso
    param([string]$Name)
    if (-not $Name) { return $null }
    $n = [IO.Path]::GetFileName($Name)
    if ($n -match '(?i)win(dows)?[ _.-]?11') { return 'Win11' }
    if ($n -match '(?i)win(dows)?[ _.-]?10') { return 'Win10' }
    if ($n -match '(?<!\d)1904[1-5](?!\d)') { return 'Win10' }
    if ($n -match '(?<!\d)2[2-9]\d{3}(?!\d)') { return 'Win11' }
    return $null
}

function Get-W11WimXmlInfo {
    <# Reads the XML metadata straight from a WIM/ESD header (no DISM needed, works on PS 2.0).
       Header: "MSWIM\0\0\0" ... rhXmlData at byte 72 (7-byte size + flags, 8-byte offset). XML is UTF-16LE. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $fs = [IO.File]::OpenRead($Path)
    try {
        $hdr = New-Object byte[] 208
        if ($fs.Read($hdr, 0, 208) -ne 208) { throw 'file too small' }
        if ([Text.Encoding]::ASCII.GetString($hdr, 0, 5) -ne 'MSWIM') { throw "not a WIM/ESD file: $Path" }
        $size = [long]0
        for ($i = 6; $i -ge 0; $i--) { $size = $size * 256 + $hdr[72 + $i] }
        $off = [BitConverter]::ToInt64($hdr, 80)
        if ($size -le 0 -or $size -gt 64MB -or $off -le 0) { throw 'invalid XML resource in WIM header' }
        $buf = New-Object byte[] $size
        [void]$fs.Seek($off, [IO.SeekOrigin]::Begin)
        $got = 0
        while ($got -lt $size) { $n = $fs.Read($buf, $got, $size - $got); if ($n -le 0) { break }; $got += $n }
    } finally { $fs.Close() }
    $text = [Text.Encoding]::Unicode.GetString($buf).TrimStart([char]0xFEFF).TrimEnd([char]0)
    $x = New-Object Xml.XmlDocument
    $x.LoadXml($text)
    $out = @()
    foreach ($img in @($x.SelectNodes('/WIM/IMAGE'))) {
        $w = $img.SelectSingleNode('WINDOWS')
        $build = 0; $ed = ''; $arch = 'x64'; $lang = ''
        if ($w) {
            $b = $w.SelectSingleNode('VERSION/BUILD'); if ($b) { $build = [int]$b.InnerText }
            $e = $w.SelectSingleNode('EDITIONID'); if ($e) { $ed = $e.InnerText }
            $a = $w.SelectSingleNode('ARCH'); if ($a) { switch ($a.InnerText) { '0' { $arch = 'x86' } '12' { $arch = 'arm64' } default { $arch = 'x64' } } }
            $l = $w.SelectSingleNode('LANGUAGES/DEFAULT'); if ($l) { $lang = $l.InnerText }
        }
        $nm = $img.SelectSingleNode('NAME'); $name = ''; if ($nm) { $name = $nm.InnerText }
        $out += (New-W11Obj @{ Index = [int]$img.GetAttribute('INDEX'); Name = $name; EditionId = $ed; Build = $build; Architecture = $arch; DefaultLanguage = $lang })
    }
    return $out
}

function Get-W11IsoOsInfo {
    <# Detects Windows 10 vs 11 for an ISO. Win8+ hosts: mount + read install.wim/esd XML (fast).
       Otherwise (Win7) falls back to the file name. Returns Os, Build, Source, Editions. #>
    param([Parameter(Mandatory = $true)][string]$IsoPath)
    $guess = Get-W11OsFromName $IsoPath
    if (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue) {
        $iso = $null
        try {
            $iso = Open-W11Iso -IsoPath $IsoPath
            foreach ($f in @('install.wim', 'install.esd')) {
                $p = Join-Path $iso.Root "sources\$f"
                if (Test-Path -LiteralPath $p) {
                    $eds = @(Get-W11WimXmlInfo -Path $p)
                    $build = 0; foreach ($e in $eds) { if ($e.Build -gt $build) { $build = $e.Build } }
                    $os = Resolve-W11OsFromBuild $build
                    if ($os) { return (New-W11Obj @{ Os = $os; Build = $build; Source = 'image'; Editions = $eds }) }
                }
            }
        } catch {
            Write-W11Log -Level WARN -En "Could not read the image inside the ISO: $($_.Exception.Message)" -Vi 'Không đọc được image trong ISO'
        } finally { if ($iso) { Close-W11Iso -Iso $iso -IsoPath $IsoPath } }
    }
    if ($guess) { return (New-W11Obj @{ Os = $guess; Build = 0; Source = 'filename'; Editions = @() }) }
    return (New-W11Obj @{ Os = $null; Build = 0; Source = 'unknown'; Editions = @() })
}

# Feature-update builds (major build -> release name). Windows 10 20H2..22H2 share the 19041 code base
# but their ISOs report their own build (19042..19045).
$script:W11Builds = @(
    @(10240, '1507'), @(10586, '1511'), @(14393, '1607'), @(15063, '1703'), @(16299, '1709'), @(17134, '1803'),
    @(17763, '1809'), @(18362, '1903'), @(18363, '1909'), @(19041, '2004'), @(19042, '20H2'), @(19043, '21H1'),
    @(19044, '21H2'), @(19045, '22H2'),
    @(22000, '21H2'), @(22621, '22H2'), @(22631, '23H2'), @(26100, '24H2'), @(26200, '25H2'), @(26300, '26H2')
)

function Get-W11ReleaseName {
    <# 19045 -> '22H2', 26100 -> '24H2'. Unlisted builds get the nearest older release + '+'
       (e.g. an Insider 26400 -> '26H2+'); $null below 10240. #>
    param([int]$Build)
    if ($Build -lt 10240) { return $null }
    $os = Resolve-W11OsFromBuild $Build
    $best = $null
    foreach ($b in $script:W11Builds) {
        if ((Resolve-W11OsFromBuild $b[0]) -ne $os) { continue }
        if ($b[0] -eq $Build) { return $b[1] }
        if ($b[0] -lt $Build) { $best = $b[1] }
    }
    if ($best) { return "$best+" }
    return $null
}

function Get-W11OsLabel([string]$Os) {
    if ($Os -eq 'Win10') { return 'Windows 10' }
    if ($Os -eq 'Win11') { return 'Windows 11' }
    return 'unknown'
}

function Get-W11ReleaseLabel {
    # 26100 -> 'Windows 11 24H2 (26100)'; 0 -> 'unknown'
    param([int]$Build, [string]$Os)
    if (-not $Os) { $Os = Resolve-W11OsFromBuild $Build }
    $l = Get-W11OsLabel $Os
    $r = Get-W11ReleaseName $Build
    if ($r) { return "$l $r ($Build)" }
    if ($Build -gt 0) { return "$l (build $Build)" }
    return $l
}

function Test-W11ForBuild {
    # Entry applies to the image build? Optional MinBuild / MaxBuild in the config entry; Build 0 = unknown -> yes
    param($Entry, [int]$Build)
    if ($Build -le 0) { return $true }
    if ($Entry.MinBuild -and $Build -lt [int]$Entry.MinBuild) { return $false }
    if ($Entry.MaxBuild -and $Build -gt [int]$Entry.MaxBuild) { return $false }
    return $true
}

function Get-W11Profile {
    <# App/tweak lists for the target OS. Config keys: Apps/Tweaks (Windows 11), Win10Apps/Win10Tweaks.
       With -Build, entries whose MinBuild/MaxBuild exclude that build are left out (SkippedApps/SkippedTweaks). #>
    param([Parameter(Mandatory = $true)]$Config, [ValidateSet('Win10', 'Win11')][string]$Os = 'Win11', [int]$Build = 0)
    if ($Os -eq 'Win10') { $apps = $Config.Win10Apps; $tweaks = $Config.Win10Tweaks }
    else { $apps = $Config.Apps; $tweaks = $Config.Tweaks }
    $ka = @(); $sa = @(); $kt = @(); $st = @()
    foreach ($a in @($apps)) { if ($null -eq $a) { continue }; if (Test-W11ForBuild $a $Build) { $ka += $a } else { $sa += $a } }
    foreach ($t in @($tweaks)) { if ($null -eq $t) { continue }; if (Test-W11ForBuild $t $Build) { $kt += $t } else { $st += $t } }
    return (New-W11Obj @{ Os = $Os; Build = $Build; Release = (Get-W11ReleaseLabel -Build $Build -Os $Os)
            Apps = $ka; Tweaks = $kt; SkippedApps = $sa; SkippedTweaks = $st; Protected = @($Config.Protected) })
}
function Get-W11ProvisionedApps {
    param([Parameter(Mandatory = $true)][string]$MountDir)
    $res = Invoke-W11Dism ('/Image:{0} /Get-ProvisionedAppxPackages' -f (ConvertTo-W11Arg $MountDir)) -Quiet
    $out = @(); $dn = $null
    foreach ($l in $res.Lines) {
        if ($l -match '^DisplayName\s*:\s*(.+)$') { $dn = $Matches[1].Trim() }
        elseif ($l -match '^PackageName\s*:\s*(.+)$' -and $dn) { $out += (New-W11Obj @{ DisplayName = $dn; PackageName = $Matches[1].Trim() }); $dn = $null }
    }
    return $out
}

function Clear-W11StaleMount {
    param([string]$MountDir)
    $res = Invoke-W11Dism '/Get-MountedImageInfo' -Quiet -NoThrow
    $full = [IO.Path]::GetFullPath($MountDir).TrimEnd('\')
    foreach ($l in $res.Lines) {
        if ($l -match '^Mount Dir\s*:\s*(.+)$' -and $Matches[1].Trim().TrimEnd('\') -eq $full) {
            Write-W11Log -Level WARN -En "Discarding stale mount at $full" -Vi 'Huỷ image còn mount từ lần trước'
            $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Discard' -f (ConvertTo-W11Arg $full)) -Quiet -NoThrow
        }
    }
    $null = Invoke-W11Dism '/Cleanup-Mountpoints' -Quiet -NoThrow
}
#endregion

#region ---------- registry / apps ----------
function Get-W11TweakHives {
    # Hives (SOFTWARE / SYSTEM / DEFAULT / NTUSER) touched by these tweaks; -Boot = the bootSet operations
    param([object[]]$TweakDefs, [switch]$Boot)
    $seen = @{}
    foreach ($t in @($TweakDefs)) {
        if ($null -eq $t) { continue }
        if ($Boot) { $kinds = @('BootSet') } else { $kinds = @('Set', 'Delete', 'DeleteValue') }
        foreach ($k in $kinds) { if ($t.ContainsKey($k)) { foreach ($op in @($t[$k])) { $seen[(Get-W11HiveName $op.Hive)] = 1 } } }
    }
    return @($seen.Keys | Sort-Object)
}

function Get-W11HiveName([string]$Hive) {
    # DEFAULTUSER was the 1.0 name of the default user's NTUSER.DAT
    if ($Hive -eq 'DEFAULTUSER') { return 'NTUSER' }
    return $Hive.ToUpperInvariant()
}

function Get-W11HiveFiles {
    # hive name -> @{ Mount = HKLM\W11D_...; File = path inside the mounted image }
    param([Parameter(Mandatory = $true)][string]$MountDir)
    return @{
        SOFTWARE = @{ Mount = $script:W11D.HiveSoftware; File = (Join-Path $MountDir 'Windows\System32\config\SOFTWARE') }
        NTUSER   = @{ Mount = $script:W11D.HiveDefault; File = (Join-Path $MountDir 'Users\Default\NTUSER.DAT') }
        SYSTEM   = @{ Mount = $script:W11D.HiveSystem; File = (Join-Path $MountDir 'Windows\System32\config\SYSTEM') }
        DEFAULT  = @{ Mount = $script:W11D.HiveDefProf; File = (Join-Path $MountDir 'Windows\System32\config\DEFAULT') }
    }
}

function Mount-W11Hives {
    <# Loads the offline hives. SOFTWARE and the default user's NTUSER.DAT are always loaded (app removal
       and most tweaks need them); SYSTEM / DEFAULT only when listed in -Hives. -BootImage = boot.wim
       (WinPE has no user profile: only SOFTWARE / SYSTEM). #>
    param([Parameter(Mandatory = $true)][string]$MountDir, [string[]]$Hives, [switch]$BootImage)
    $files = Get-W11HiveFiles -MountDir $MountDir
    if ($BootImage) { $want = @() } else { $want = @('SOFTWARE', 'NTUSER') }
    foreach ($h in @($Hives)) { if ($h -and $want -notcontains $h) { $want += $h } }
    foreach ($h in $want) {
        if (-not $files.ContainsKey($h)) { continue }
        if ($BootImage -and $h -eq 'NTUSER') { continue }
        $f = $files[$h]
        if ((Invoke-W11Reg ('load {0} {1}' -f $f.Mount, (ConvertTo-W11Arg $f.File))) -ne 0) { Dismount-W11Hives; throw "reg load failed: $($f.File)" }
    }
}

function Dismount-W11Hives {
    foreach ($h in @($script:W11D.HiveSoftware, $script:W11D.HiveDefault, $script:W11D.HiveSystem, $script:W11D.HiveDefProf)) {
        if ((Invoke-W11Reg "query $h") -ne 0) { continue }   # not loaded
        $ok = $false
        for ($i = 0; $i -lt 10 -and -not $ok; $i++) {
            [GC]::Collect(); [GC]::WaitForPendingFinalizers()
            $ok = ((Invoke-W11Reg "unload $h") -eq 0)
            if (-not $ok) { Start-Sleep -Seconds 1 }
        }
        if (-not $ok) { Write-W11Log -Level WARN -En "Could not unload $h - run 'reg unload $h' manually" -Vi "Không unload được $h, hãy chạy 'reg unload $h'" }
    }
}

function ConvertTo-W11RegData([string]$Data) {
    # reg.exe /d argument: plain numbers / words as-is (1.0 behaviour), quoted when empty or containing spaces
    if ($Data -match '^[A-Za-z0-9_.:-]+$') { return $Data }
    return (ConvertTo-W11Arg $Data)
}

function Invoke-W11Tweaks {
    <# Applies tweak entries to the loaded hives. -Boot applies the BootSet operations (boot.wim setup image)
       instead of Set / DeleteValue / Delete. #>
    param([object[]]$TweakDefs, [switch]$DryRun, [switch]$Boot)
    $map = @{ SOFTWARE = $script:W11D.HiveSoftware; NTUSER = $script:W11D.HiveDefault; SYSTEM = $script:W11D.HiveSystem; DEFAULT = $script:W11D.HiveDefProf }
    foreach ($t in $TweakDefs) {
        if ($Boot -and -not $t.ContainsKey('BootSet')) { continue }
        Write-W11Log -En "  Tweak: $($t.Name)" -Vi $t.NameVi
        if ($Boot) { $sets = @($t.BootSet) } elseif ($t.ContainsKey('Set')) { $sets = @($t.Set) } else { $sets = @() }
        foreach ($v in $sets) {
            $hv = Get-W11HiveName $v.Hive
            $key = '{0}\{1}' -f $map[$hv], $v.Key
            if ($DryRun) { Write-W11Log -Level DRY -En "    would set $hv\$($v.Key)\$($v.Value) = $($v.Data)"; continue }
            $code = Invoke-W11Reg ('add {0} /v {1} /t {2} /d {3} /f' -f (ConvertTo-W11Arg $key), (ConvertTo-W11Arg $v.Value), $v.Type, (ConvertTo-W11RegData $v.Data))
            if ($code -ne 0) { Write-W11Log -Level WARN -En "    FAILED to set $($v.Key)\$($v.Value) (exit $code)" -Vi 'Không ghi được (có thể do quyền của key)' }
            else { Write-W11Log -En "    set $($v.Key)\$($v.Value) = $($v.Data)" }
        }
        if ($Boot) { continue }
        if ($t.ContainsKey('DeleteValue')) {
            foreach ($d in $t.DeleteValue) {
                $hv = Get-W11HiveName $d.Hive
                $key = '{0}\{1}' -f $map[$hv], $d.Key
                if ($DryRun) { Write-W11Log -Level DRY -En "    would delete value (if present) $hv\$($d.Key)\$($d.Value)"; continue }
                if ((Invoke-W11Reg ('query {0} /v {1}' -f (ConvertTo-W11Arg $key), (ConvertTo-W11Arg $d.Value))) -ne 0) { Write-W11Log -En "    (not present) $($d.Key)\$($d.Value)"; continue }
                $code = Invoke-W11Reg ('delete {0} /v {1} /f' -f (ConvertTo-W11Arg $key), (ConvertTo-W11Arg $d.Value))
                if ($code -ne 0) { Write-W11Log -Level WARN -En "    FAILED to delete value $($d.Key)\$($d.Value) (exit $code)" -Vi 'Không xoá được giá trị' }
                else { Write-W11Log -En "    deleted value $($d.Key)\$($d.Value)" }
            }
        }
        if ($t.ContainsKey('Delete')) {
            foreach ($d in $t.Delete) {
                $hv = Get-W11HiveName $d.Hive
                $key = '{0}\{1}' -f $map[$hv], $d.Key
                if ($DryRun) { Write-W11Log -Level DRY -En "    would delete (if present) $hv\$($d.Key)"; continue }
                if ((Invoke-W11Reg ('query {0}' -f (ConvertTo-W11Arg $key))) -ne 0) { Write-W11Log -En "    (not present) $($d.Key)"; continue }
                $code = Invoke-W11Reg ('delete {0} /f' -f (ConvertTo-W11Arg $key))
                if ($code -ne 0) { Write-W11Log -Level WARN -En "    FAILED to delete $($d.Key) (exit $code)" -Vi 'Không xoá được key' }
                else { Write-W11Log -En "    deleted $($d.Key)" }
            }
        }
    }
}

function Write-W11AbsentPatterns {
    # Apps on the list that this image simply does not contain: nothing to do, just say so
    param([string[]]$Patterns, [string[]]$Names)
    $absent = @()
    foreach ($pt in @($Patterns)) {
        if (-not $pt) { continue }
        $hit = $false
        foreach ($n in @($Names)) { if (Test-W11Like $n @($pt)) { $hit = $true; break } }
        if (-not $hit) { $absent += $pt }
    }
    if ($absent.Count -gt 0) { Write-W11Log -En ('  not in this image (skipped): ' + ($absent -join ', ')) -Vi 'không có trong bản này (bỏ qua)' }
    return $absent
}

function Write-W11OutOfRange {
    # Default apps hidden by MinBuild/MaxBuild that ARE in the image: kept, but tell the user (config may need widening)
    param([string[]]$OutOfRange, [string[]]$Patterns, [string[]]$Names)
    foreach ($pt in @($OutOfRange)) {
        if (-not $pt -or (Test-W11Like $pt @($Patterns))) { continue }
        foreach ($n in @($Names)) {
            if (Test-W11Like $n @($pt)) { Write-W11Log -Level WARN -En "  $n is in this image but outside its minBuild/maxBuild range in data\apps.json - kept" -Vi 'app này có trong bản này nhưng nằm ngoài khoảng build trong cấu hình - được giữ lại'; break }
        }
    }
}

function Remove-W11AppsDism {
    param([string]$MountDir, [string[]]$Patterns, [string[]]$Protected, [switch]$DryRun, [string]$KeptListPath, [string[]]$OutOfRange)
    $prov = @(Get-W11ProvisionedApps -MountDir $MountDir)
    Write-W11OutOfRange -OutOfRange $OutOfRange -Patterns $Patterns -Names @($prov | ForEach-Object { $_.DisplayName })
    $removed = 0
    foreach ($p in $prov) {
        if (-not (Test-W11Like $p.DisplayName $Patterns)) { continue }
        if (Test-W11Like $p.DisplayName $Protected) { Write-W11Log -Level WARN -En "  skip protected: $($p.DisplayName)" -Vi 'bỏ qua app được bảo vệ'; continue }
        if ($DryRun) { Write-W11Log -Level DRY -En "  would remove $($p.PackageName)" -Vi 'sẽ gỡ'; $removed++; continue }
        Assert-W11NotCancelled
        $r = Invoke-W11Dism ('/Image:{0} /Remove-ProvisionedAppxPackage /PackageName:{1}' -f (ConvertTo-W11Arg $MountDir), $p.PackageName) -Quiet -NoThrow
        if ($r.ExitCode -eq 0) { Write-W11Log -En "  removed $($p.PackageName)" -Vi 'đã gỡ'; $removed++ }
        else { Write-W11Log -Level WARN -En "  failed to remove $($p.PackageName) (exit $($r.ExitCode))" -Vi 'gỡ thất bại' }
    }
    $null = Write-W11AbsentPatterns -Patterns $Patterns -Names @($prov | ForEach-Object { $_.DisplayName })
    if ($DryRun) { $kept = @($prov | Where-Object { -not (Test-W11Like $_.DisplayName $Patterns) -or (Test-W11Like $_.DisplayName $Protected) } | ForEach-Object { $_.DisplayName } | Sort-Object -Unique) }
    else { $kept = @(Get-W11ProvisionedApps -MountDir $MountDir | ForEach-Object { $_.DisplayName } | Sort-Object -Unique) }
    if ($KeptListPath) { $kept | Set-Content -LiteralPath $KeptListPath -Encoding UTF8 }
    Write-W11Log -Level OK -En "  $removed package(s) removed, $($kept.Count) kept" -Vi "đã gỡ $removed gói, giữ lại $($kept.Count)"
}

function Remove-W11AppsManual {
    <# Fallback when DISM has no Appx provider (e.g. ISO's DISM on Windows 7): drop AppxAllUserStore\Applications entries, add Deprovisioned
       markers and delete the package folders. Requires the SOFTWARE hive to be loaded. #>
    param([string]$MountDir, [string[]]$Patterns, [string[]]$Protected, [switch]$DryRun, [string]$KeptListPath)
    $base = "$($script:W11D.HiveSoftware)\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore"
    $res = Invoke-W11Process -FilePath (Join-Path $env:windir 'System32\reg.exe') -Arguments ('query {0}' -f (ConvertTo-W11Arg "$base\Applications")) -Quiet
    $names = @($res.Lines | Where-Object { $_ -like 'HKEY_*' } | ForEach-Object { Split-Path -Leaf $_ } | Where-Object { $_ -ne 'Applications' })
    $wa = Join-Path $MountDir 'Program Files\WindowsApps'
    $removed = 0; $kept = @()
    foreach ($n in $names) {
        $fam = $n.Split('_')[0]; $pub = $n.Split('_')[-1]
        if (-not (Test-W11Like $fam $Patterns) -or (Test-W11Like $fam $Protected)) { $kept += $fam; continue }
        if ($DryRun) { Write-W11Log -Level DRY -En "  would deprovision $n"; $removed++; continue }
        Assert-W11NotCancelled
        $null = Invoke-W11Reg ('delete {0} /f' -f (ConvertTo-W11Arg "$base\Applications\$n"))
        $null = Invoke-W11Reg ('add {0} /f' -f (ConvertTo-W11Arg "$base\Deprovisioned\$($fam)_$pub"))
        foreach ($dir in @(Get-ChildItem -LiteralPath $wa -Force -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer -and $_.Name -like "$($fam)_*" })) {
            $null = Invoke-W11Process -FilePath (Join-Path $env:windir 'System32\icacls.exe') -Arguments ('{0} /setowner *S-1-5-32-544 /T /C /Q' -f (ConvertTo-W11Arg $dir.FullName)) -Quiet
            $null = Invoke-W11Process -FilePath (Join-Path $env:windir 'System32\icacls.exe') -Arguments ('{0} /grant *S-1-5-32-544:F /T /C /Q' -f (ConvertTo-W11Arg $dir.FullName)) -Quiet
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-W11Log -En "  deprovisioned $n (manual)" -Vi 'đã gỡ (thủ công)'
        $removed++
    }
    $null = Write-W11AbsentPatterns -Patterns $Patterns -Names @($names | ForEach-Object { $_.Split('_')[0] })
    $kept = @($kept | Sort-Object -Unique)
    if ($KeptListPath) { $kept | Set-Content -LiteralPath $KeptListPath -Encoding UTF8 }
    Write-W11Log -Level OK -En "  $removed package(s) removed (manual mode), $($kept.Count) kept" -Vi "đã gỡ $removed gói (chế độ thủ công)"
}

function Get-W11ArchName([string]$Arch) {
    switch -regex ($Arch) { 'arm64' { return 'arm64' } '^x86$' { return 'x86' } default { return 'amd64' } }
}

function Write-W11Autounattend {
    param([string]$Template, [string]$Destination, [string]$Language = 'en-US', [string]$Arch = 'amd64', [string]$Os = 'Win11')
    $xml = [IO.File]::ReadAllText($Template)
    $xml = $xml -replace 'processorArchitecture="[a-z0-9]+"', ('processorArchitecture="{0}"' -f $Arch)
    # Setup UI language must exist on the media -> use the image's default language
    $xml = $xml -replace '<UILanguage>[^<]+</UILanguage>', ('<UILanguage>{0}</UILanguage>' -f $Language)
    if ($Os -eq 'Win10') {
        # Windows 10 already offers "Offline account / Limited experience"; BypassNRO is a Windows 11 thing.
        $doc = New-Object Xml.XmlDocument
        $doc.PreserveWhitespace = $true
        $doc.LoadXml($xml)
        foreach ($c in @($doc.GetElementsByTagName('RunSynchronousCommand'))) {
            if ($c.InnerXml -match 'BypassNRO') { [void]$c.ParentNode.RemoveChild($c) }
        }
        $n = 1
        foreach ($c in @($doc.GetElementsByTagName('RunSynchronousCommand'))) {
            foreach ($o in @($c.GetElementsByTagName('Order'))) { $o.InnerText = [string]$n }
            $n++
        }
        $xml = $doc.OuterXml
    }
    [IO.File]::WriteAllText($Destination, $xml, (New-Object Text.UTF8Encoding $false))
}

function Get-W11IsoEditions {
    # Lists editions inside an ISO. Needs Mount-DiskImage (Win8+); on Win7 returns $null.
    param([Parameter(Mandatory = $true)][string]$IsoPath)
    if (-not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) {
        Write-W11Log -Level WARN -En 'Listing editions needs Windows 8+ (Mount-DiskImage). On Windows 7 use "All" or "Home+Pro".' -Vi 'Xem phiên bản cần Win8+; trên Win7 hãy chọn "Tất cả" hoặc "Home+Pro".'
        return $null
    }
    $iso = Open-W11Iso -IsoPath $IsoPath
    try {
        $src = $null
        foreach ($f in @('install.wim', 'install.esd')) { $p = Join-Path $iso.Root "sources\$f"; if (Test-Path -LiteralPath $p) { $src = $p; break } }
        if (-not $src) { throw 'sources\install.wim/esd not found' }
        $null = Select-W11Dism -IsoSourcesDir (Join-Path $iso.Root 'sources')
        $eds = @(Get-W11ImageInfo -ImageFile $src)
        foreach ($e in $eds) { Write-W11Log -En ('  [{0}] {1}  ({2}, {3}, {4}, build {5} = {6})' -f $e.Index, $e.Name, $e.EditionId, $e.Architecture, $e.DefaultLanguage, $e.Build, (Get-W11OsLabel (Resolve-W11OsFromBuild $e.Build))) }
        return $eds
    } finally { Close-W11Iso -Iso $iso -IsoPath $IsoPath }
}
#endregion

#region ---------- offline updates (.msu / .cab from a local folder) ----------
<# Kinds: SSU (servicing stack), LCU (cumulative update, also checkpoint updates and the combined SSU+LCU .msu of
   Windows 11 / newer Windows 10), NetFx (.NET Framework cumulative update), SafeOS (WinRE "Safe OS" dynamic update).
   The kind comes from the sub-folder (ssu, lcu, netfx / dotnet / ndp, safeos / winre) or from the file name
   (ssu-*, *ndp*, *netfx*, *dotnet*, *safeos*); anything else is treated as LCU. On Windows the .msu content is
   listed (expand.exe -D) to recognise a combined SSU+LCU package or a stand-alone SSU. #>
$script:W11UpdateKinds = @('SSU', 'SafeOS', 'LCU', 'NetFx')

function Get-W11KbNumber {
    param([string]$Name)
    $m = [regex]::Match([string]$Name, '(?i)kb(\d{6,8})')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}

function Get-W11UpdateKind {
    <# -RelativePath: path below the updates folder (sub-folder names count). -Contents: file names inside the .msu
       (optional). Returns @{ Kind; Combined } #>
    param([Parameter(Mandatory = $true)][string]$RelativePath, [string[]]$Contents)
    $rel = ($RelativePath -replace '/', '\').ToLowerInvariant()
    $leaf = Split-Path -Leaf $rel
    $dirs = @(); $parts = $rel.Split('\'); if ($parts.Count -gt 1) { $dirs = $parts[0..($parts.Count - 2)] }
    $kind = $null
    foreach ($d in $dirs) {
        if ($d -match '^(ssu|servicing[\s_-]*stack)') { $kind = 'SSU' }
        elseif ($d -match '^(safe[\s_-]*os|winre|re)$') { $kind = 'SafeOS' }
        elseif ($d -match '^(netfx|dotnet|\.net|ndp|net)') { $kind = 'NetFx' }
        elseif ($d -match '^(lcu|cu|cumulative)') { $kind = 'LCU' }
    }
    if (-not $kind) {
        if ($leaf -match '(^|[^a-z])ssu([^a-z]|$)') { $kind = 'SSU' }
        elseif ($leaf -match 'safe[\s_-]*os|winre') { $kind = 'SafeOS' }
        elseif ($leaf -match 'ndp\d|netfx|dotnet|[^a-z]net4') { $kind = 'NetFx' }
    }
    $combined = $false
    $cabs = @(@($Contents) | Where-Object { $_ -and ([string]$_).ToLowerInvariant().EndsWith('.cab') -and ([string]$_) -notmatch '(?i)^wsusscan\.cab$' })
    if ($cabs.Count -gt 0) {
        $ssuCabs = @($cabs | Where-Object { ([string]$_) -match '(?i)^ssu-' })
        if ($ssuCabs.Count -gt 0 -and $ssuCabs.Count -lt $cabs.Count) { $combined = $true; if (-not $kind -or $kind -eq 'SSU') { $kind = 'LCU' } }
        elseif ($ssuCabs.Count -gt 0 -and $ssuCabs.Count -eq $cabs.Count -and -not $kind) { $kind = 'SSU' }
    }
    if (-not $kind) { $kind = 'LCU' }
    return @{ Kind = $kind; Combined = $combined }
}

function Get-W11MsuContents {
    # file names inside an .msu (expand.exe -D); empty when expand.exe is not there (not Windows) or fails
    param([Parameter(Mandatory = $true)][string]$Path)
    $exe = Join-Path ([string]$env:windir) 'System32\expand.exe'
    if (-not $env:windir -or -not (Test-Path -LiteralPath $exe)) { return @() }
    try {
        $r = Invoke-W11Process -FilePath $exe -Arguments ('-D {0}' -f (ConvertTo-W11Arg $Path)) -Quiet
        $out = @()
        foreach ($l in @($r.Lines)) { if ([string]$l -match ':\s*([^:\\]+\.(cab|xml|txt|psf|wim))\s*$') { $out += $Matches[1].Trim() } }
        return $out
    } catch { return @() }
}

function Get-W11UpdateOrder {
    # DISM order: SSU first, then the WinRE Safe OS update, the cumulative update(s) (oldest KB first: checkpoint
    # updates before the latest one) and the .NET update last
    param([object[]]$Packages)
    $out = @()
    foreach ($k in $script:W11UpdateKinds) {
        $out += @(@($Packages) | Where-Object { $_ -and $_.Kind -eq $k } | Sort-Object @{ Expression = { $_.Kb } }, @{ Expression = { $_.Name } })
    }
    return $out
}

function Get-W11UpdatePackages {
    <# All .msu / .cab files below -Path (sub-folders too), with Kind / Kb / Combined, in install order.
       -NoInspect skips listing the .msu content. #>
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$NoInspect)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Updates folder not found / Không thấy thư mục bản cập nhật: $Path" }
    $root = ((Resolve-Path -LiteralPath $Path).ProviderPath -replace '/', '\').TrimEnd('\')
    $pk = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })) {
        $ext = $f.Extension.ToLowerInvariant()
        if ($ext -ne '.msu' -and $ext -ne '.cab') { continue }
        $full = ($f.FullName -replace '/', '\')
        $rel = $full; if ($full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { $rel = $full.Substring($root.Length + 1) }
        $contents = @()
        if ($ext -eq '.msu' -and -not $NoInspect) { $contents = @(Get-W11MsuContents -Path $f.FullName) }
        $k = Get-W11UpdateKind -RelativePath $rel -Contents $contents
        $pk += (New-W11Obj @{ Path = $f.FullName; Name = $f.Name; RelativePath = $rel; Kind = $k.Kind; Combined = $k.Combined
                Kb = (Get-W11KbNumber $f.Name); Size = [int64]$f.Length })
    }
    return @(Get-W11UpdateOrder $pk)
}

function Select-W11UpdatesFor {
    # which packages go into which image: Install = SSU, LCU, NetFx; Boot (boot.wim) = SSU, LCU; WinRE = SSU, SafeOS
    param([object[]]$Packages, [ValidateSet('Install', 'Boot', 'WinRE')][string]$Target)
    switch ($Target) {
        'Install' { $k = @('SSU', 'LCU', 'NetFx') }
        'Boot' { $k = @('SSU', 'LCU') }
        default { $k = @('SSU', 'SafeOS') }
    }
    return @(@($Packages) | Where-Object { $_ -and $k -contains $_.Kind })
}

function Add-W11UpdatePackages {
    <# dism /Add-Package for each package (already in order) into a mounted image. A failing package is logged and
       skipped (0x800f081e = not applicable to this image). Returns @{ Added; Skipped; Failed }. #>
    param([Parameter(Mandatory = $true)][string]$MountDir, [object[]]$Packages, [string]$ScratchDir, [string]$Tag = '', [switch]$DryRun,
        [double]$ProgressBase = -1, [double]$ProgressSpan = 0)
    $res = @{ Added = 0; Skipped = 0; Failed = 0 }
    $list = @($Packages | Where-Object { $_ })
    $n = 0
    foreach ($p in $list) {
        $n++
        $what = "$Tag $($p.Kind) $($p.Name)".Trim()
        if ($p.Combined) { $what += ' (SSU+LCU)' }
        if ($DryRun) { Write-W11Log -Level DRY -En "    would add package $what" -Vi 'sẽ tích hợp gói cập nhật'; $res.Added++; continue }
        Assert-W11NotCancelled
        Write-W11Log -En "    adding $what ..." -Vi "    đang tích hợp $($p.Name)..."
        $a = '/Image:{0} /Add-Package /PackagePath:{1}' -f (ConvertTo-W11Arg $MountDir), (ConvertTo-W11Arg $p.Path)
        if ($ScratchDir) { $a += ' /ScratchDir:' + (ConvertTo-W11Arg $ScratchDir) }
        $pb = -1; if ($ProgressBase -ge 0 -and $list.Count -gt 0) { $pb = $ProgressBase + $ProgressSpan * ($n - 1) / $list.Count }
        $r = Invoke-W11Dism $a -Quiet -NoThrow -ProgressBase $pb -ProgressSpan ($ProgressSpan / [Math]::Max(1, $list.Count)) -ProgressText "Update $($p.Name)"
        $code = [int]$r.ExitCode
        if ($code -eq 0 -or $code -eq 3010) { Write-W11Log -Level OK -En "    added $($p.Name)" -Vi 'đã tích hợp'; $res.Added++ }
        elseif ($code -eq -2146498530) { Write-W11Log -En "    $($p.Name) does not apply to this image (0x800f081e) - skipped" -Vi 'gói này không dùng cho image này - bỏ qua'; $res.Skipped++ }
        else {
            foreach ($l in @($r.Lines | Select-Object -Last 4)) { Write-W11Log -Level WARN -En "      $l" }
            Write-W11Log -Level WARN -En ('    FAILED to add {0} (exit 0x{1:x8}) - continuing with the next package' -f $p.Name, $code) -Vi 'tích hợp lỗi, chuyển sang gói tiếp theo'
            $res.Failed++
        }
    }
    return $res
}

function Invoke-W11ComponentCleanup {
    param([Parameter(Mandatory = $true)][string]$MountDir, [string]$ScratchDir, [switch]$ResetBase, [string]$Tag = '', [double]$ProgressBase = -1, [double]$ProgressSpan = 0)
    $a = '/Image:{0}' -f (ConvertTo-W11Arg $MountDir)
    if ($ScratchDir) { $a += ' /ScratchDir:' + (ConvertTo-W11Arg $ScratchDir) }
    $a += ' /Cleanup-Image /StartComponentCleanup'
    if ($ResetBase) { $a += ' /ResetBase'; Write-W11Log -En '  /Cleanup-Image /StartComponentCleanup /ResetBase (slow; updates can no longer be uninstalled)...' -Vi '  Dọn component store kèm /ResetBase (chậm, không gỡ được bản cập nhật về sau)...' }
    else { Write-W11Log -En '  /Cleanup-Image /StartComponentCleanup (slow)...' -Vi '  Dọn component store (chậm)...' }
    $r = Invoke-W11Dism $a -Quiet -NoThrow -ProgressBase $ProgressBase -ProgressSpan $ProgressSpan -ProgressText (("$Tag Component cleanup").Trim())
    if ($r.ExitCode -ne 0) { Write-W11Log -Level WARN -En "  Component cleanup failed (exit $($r.ExitCode)), continuing" -Vi '  Dọn component lỗi, bỏ qua' }
}

function Update-W11WinRE {
    <# Services Windows\System32\Recovery\Winre.wim of the mounted install image: SSU + Safe OS update (+ cleanup),
       re-exported so it does not grow. The serviced copy is cached by the SHA256 of the original, so editions that
       share the same Winre.wim are serviced once. #>
    param([Parameter(Mandatory = $true)][string]$MountDir, [Parameter(Mandatory = $true)]$Layout, [object[]]$Packages, [hashtable]$Cache,
        [switch]$Cleanup, [switch]$DryRun)
    $re = Join-W11Path $MountDir 'Windows\System32\Recovery\Winre.wim'
    $pk = @(Select-W11UpdatesFor $Packages 'WinRE')
    if ($pk.Count -eq 0) { Write-W11Log -En '  WinRE: no SSU / Safe OS package - skipped' -Vi '  WinRE: không có gói SSU / Safe OS - bỏ qua'; return }
    if (-not (Test-Path -LiteralPath $re)) { Write-W11Log -Level WARN -En '  WinRE: Windows\System32\Recovery\Winre.wim not found - skipped' -Vi '  WinRE: không thấy Winre.wim - bỏ qua'; return }
    if ($DryRun) { $null = Add-W11UpdatePackages -MountDir $Layout.MountRe -Packages $pk -Tag 'WinRE' -DryRun; return }
    $hash = Get-W11Sha256 -Path $re
    if ($Cache -and $Cache.ContainsKey($hash) -and (Test-Path -LiteralPath $Cache[$hash])) {
        Write-W11Log -En '  WinRE: same Winre.wim as an earlier edition - reusing the serviced copy' -Vi '  WinRE: giống bản trước - dùng lại bản đã cập nhật'
        $item = Get-Item -LiteralPath $re -Force; $item.Attributes = 'Normal'
        Copy-Item -LiteralPath $Cache[$hash] -Destination $re -Force
        return
    }
    Write-W11Log -Level STEP -En '  WinRE: servicing Winre.wim (SSU + Safe OS)...' -Vi '  WinRE: đang cập nhật Winre.wim (SSU + Safe OS)...'
    New-W11Directory $Layout.MountRe
    foreach ($f in @($Layout.WinReWork, $Layout.WinReDone)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    Copy-Item -LiteralPath $re -Destination $Layout.WinReWork -Force
    (Get-Item -LiteralPath $Layout.WinReWork -Force).Attributes = 'Normal'
    $mounted = $false
    try {
        $null = Invoke-W11Dism ('/Mount-Image /ImageFile:{0} /Index:1 /MountDir:{1}' -f (ConvertTo-W11Arg $Layout.WinReWork), (ConvertTo-W11Arg $Layout.MountRe)) -Quiet
        $mounted = $true
        $r = Add-W11UpdatePackages -MountDir $Layout.MountRe -Packages $pk -ScratchDir $Layout.Scratch -Tag 'WinRE'
        if ($Cleanup -and $r.Added -gt 0) { Invoke-W11ComponentCleanup -MountDir $Layout.MountRe -ScratchDir $Layout.Scratch -ResetBase -Tag 'WinRE' }
        if ($r.Added -eq 0) {
            $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Discard' -f (ConvertTo-W11Arg $Layout.MountRe)) -Quiet -NoThrow
            $mounted = $false
            Write-W11Log -Level WARN -En '  WinRE: nothing was added - Winre.wim left unchanged' -Vi '  WinRE: không tích hợp được gói nào - giữ nguyên Winre.wim'
            return
        }
        $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Commit' -f (ConvertTo-W11Arg $Layout.MountRe)) -Quiet
        $mounted = $false
        $null = Invoke-W11Dism (Get-W11ExportArgs -Source $Layout.WinReWork -Index 1 -Destination $Layout.WinReDone -Compression Max -ScratchDir $Layout.Scratch) -Quiet
        $item = Get-Item -LiteralPath $re -Force; $attr = $item.Attributes; $item.Attributes = 'Normal'
        Copy-Item -LiteralPath $Layout.WinReDone -Destination $re -Force
        try { (Get-Item -LiteralPath $re -Force).Attributes = $attr } catch { $null = $_ }
        if ($Cache) {
            $keep = Join-W11Path $Layout.WinReCacheDir ('re_' + $Cache.Count + '.wim')
            New-W11Directory $Layout.WinReCacheDir
            Copy-Item -LiteralPath $Layout.WinReDone -Destination $keep -Force
            $Cache[$hash] = $keep
        }
        Write-W11Log -Level OK -En ('  WinRE updated ({0})' -f (Format-W11Size (Get-W11FileLength $re))) -Vi '  Đã cập nhật WinRE'
    } catch {
        Write-W11Log -Level WARN -En "  WinRE update failed, Winre.wim left unchanged: $($_.Exception.Message)" -Vi '  Cập nhật WinRE lỗi, giữ nguyên Winre.wim'
    } finally {
        if ($mounted) { $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Discard' -f (ConvertTo-W11Arg $Layout.MountRe)) -Quiet -NoThrow }
        foreach ($f in @($Layout.WinReWork, $Layout.WinReDone)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
    }
}

function Update-W11BootWim {
    <# sources\boot.wim of the ISO tree: index 2 (Windows Setup) gets the bootSet tweaks (e.g. LabConfig), every
       index gets SSU + LCU when -Packages is given. Re-exported into a new boot.wim (the file does not grow).
       Failures are logged and the original boot.wim is kept. #>
    param([Parameter(Mandatory = $true)][string]$Tree, [Parameter(Mandatory = $true)]$Layout, [object[]]$Packages, [object[]]$BootTweaks, [switch]$DryRun)
    $boot = Join-W11Path $Tree 'sources\boot.wim'
    $pk = @(Select-W11UpdatesFor $Packages 'Boot')
    $tw = @(@($BootTweaks) | Where-Object { $_ -and $_.ContainsKey('BootSet') })
    if ($pk.Count -eq 0 -and $tw.Count -eq 0) { return }
    Write-W11Log -Level STEP -En ('Servicing boot.wim ({0} update package(s), {1} setup tweak(s))...' -f $pk.Count, $tw.Count) -Vi 'Đang xử lý boot.wim...'
    if ($DryRun) {
        $null = Add-W11UpdatePackages -MountDir $Layout.MountBoot -Packages $pk -Tag 'boot.wim' -DryRun
        if ($tw.Count) { Invoke-W11Tweaks -TweakDefs $tw -Boot -DryRun }
        return
    }
    if (-not (Test-Path -LiteralPath $boot)) { Write-W11Log -Level WARN -En 'sources\boot.wim not found - boot image not changed' -Vi 'Không thấy sources\boot.wim - bỏ qua boot image'; return }
    # serviced on a copy next to the tree: on any failure the tree keeps the original boot.wim
    $work = $Layout.BootWork
    foreach ($f in @($work, $Layout.BootNew)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    Copy-Item -LiteralPath $boot -Destination $work -Force
    (Get-Item -LiteralPath $work -Force).Attributes = 'Normal'
    $infos = @(Get-W11ImageInfo -ImageFile $work)
    $mounted = $false; $changed = $false
    New-W11Directory $Layout.MountBoot
    try {
        foreach ($e in $infos) {
            $isSetup = ([int]$e.Index -eq 2 -or $infos.Count -eq 1)
            if ($pk.Count -eq 0 -and -not $isSetup) { continue }
            Assert-W11NotCancelled
            Write-W11Log -En "  boot.wim [$($e.Index)] $($e.Name)" -Vi '  boot.wim'
            $null = Invoke-W11Dism ('/Mount-Image /ImageFile:{0} /Index:{1} /MountDir:{2}' -f (ConvertTo-W11Arg $work), $e.Index, (ConvertTo-W11Arg $Layout.MountBoot)) -Quiet
            $mounted = $true
            $r = @{ Added = 0 }
            if ($pk.Count) { $r = Add-W11UpdatePackages -MountDir $Layout.MountBoot -Packages $pk -ScratchDir $Layout.Scratch -Tag "boot.wim[$($e.Index)]" }
            $tweaked = $false
            if ($isSetup -and $tw.Count) {
                Mount-W11Hives -MountDir $Layout.MountBoot -Hives @(Get-W11TweakHives $tw -Boot) -BootImage
                try { Invoke-W11Tweaks -TweakDefs $tw -Boot; $tweaked = $true } finally { Dismount-W11Hives }
            }
            if ($r.Added -gt 0 -or $tweaked) {
                if ($r.Added -gt 0) { Invoke-W11ComponentCleanup -MountDir $Layout.MountBoot -ScratchDir $Layout.Scratch -ResetBase -Tag 'boot.wim' }
                $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Commit' -f (ConvertTo-W11Arg $Layout.MountBoot)) -Quiet
                $changed = $true
            } else { $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Discard' -f (ConvertTo-W11Arg $Layout.MountBoot)) -Quiet -NoThrow }
            $mounted = $false
        }
        if ($changed) {
            foreach ($e in $infos) { $null = Invoke-W11Dism (Get-W11ExportArgs -Source $work -Index $e.Index -Destination $Layout.BootNew -Compression Max -ScratchDir $Layout.Scratch) -Quiet }
            (Get-Item -LiteralPath $boot -Force).Attributes = 'Normal'
            Remove-Item -LiteralPath $boot -Force
            Move-Item -LiteralPath $Layout.BootNew -Destination $boot
            Write-W11Log -Level OK -En ('  boot.wim updated ({0})' -f (Format-W11Size (Get-W11FileLength $boot))) -Vi '  Đã cập nhật boot.wim'
        }
    } catch {
        if ($mounted) { $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Discard' -f (ConvertTo-W11Arg $Layout.MountBoot)) -Quiet -NoThrow; $mounted = $false }
        if ($_.Exception -is [System.OperationCanceledException]) { throw }
        Write-W11Log -Level WARN -En "  boot.wim servicing failed, keeping the original: $($_.Exception.Message)" -Vi '  Xử lý boot.wim lỗi, giữ nguyên bản gốc'
    } finally {
        foreach ($f in @($work, $Layout.BootNew)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
    }
}
#endregion

#region ---------- answer file (autounattend.xml) ----------
<# Generated answer file. Never contains DiskConfiguration: disk / partition selection always stays interactive,
   nothing is wiped automatically. Options (hashtable, all optional):
     LocalAccount (bool), UserName, Password (plain text, may be empty), BypassNro (default $true, Windows 11),
     BypassChecks (TPM / Secure Boot / RAM / CPU / storage, Windows 11), SkipPrivacy, FirstLogonCleanup
     (+ FirstLogonApps = app patterns removed again at first logon), Locale (e.g. vi-VN), Keyboard (e.g. 0409:00000409
     or en-US). Without options the result matches the 1.0 template. #>
$script:W11ReservedUsers = @('administrator', 'admin', 'guest', 'defaultaccount', 'wdagutilityaccount', 'system', 'user', 'users', 'none',
    'everyone', 'localsystem', 'networkservice', 'localservice', 'administrators', 'defaultuser0', 'defaultuser100000')
$script:W11FirstLogonScript = 'W11D-FirstLogon.ps1'

function Get-W11UnattendDefaults {
    return @{ LocalAccount = $false; UserName = ''; Password = ''; BypassNro = $true; BypassChecks = $false; SkipPrivacy = $false
        FirstLogonCleanup = $false; FirstLogonApps = @(); Locale = ''; Keyboard = '' }
}

function Test-W11LocalAccountName {
    # Windows local user name rules: 1-20 characters, none of " / \ [ ] : ; | = , + * ? < > @ %, not only dots / spaces, not a built-in name
    param([string]$Name)
    if (-not $Name) { return $false }
    if ($Name.Length -gt 20) { return $false }
    if ($Name -match '["/\\\[\]:;|=,+*?<>@%]') { return $false }
    if ($Name -match '[\x00-\x1F]') { return $false }
    if ($Name.Trim(' .'.ToCharArray()).Length -eq 0) { return $false }
    if ($Name -ne $Name.Trim()) { return $false }
    if ($script:W11ReservedUsers -contains $Name.ToLowerInvariant()) { return $false }
    return $true
}

function Test-W11LocaleName([string]$Name) { return ($Name -match '^[a-z]{2,3}(-[A-Za-z]{2,4})?(-[A-Za-z0-9]{2,8})?$') }
function Test-W11KeyboardName([string]$Name) { return ($Name -match '^[0-9A-Fa-f]{4}:[0-9A-Fa-f{}-]{8,40}$' -or (Test-W11LocaleName $Name)) }

function ConvertTo-W11XmlText([string]$Text) {
    return [Security.SecurityElement]::Escape([string]$Text)
}

function Get-W11SafePatterns {
    # app patterns usable inside the first-logon script: letters, digits . _ - * only
    param([string[]]$Patterns)
    return @(@($Patterns) | Where-Object { $_ -and ([string]$_) -match '^[A-Za-z0-9.*_-]+$' } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
}

function New-W11FirstLogonScript {
    <# PowerShell script run once at the first logon: removes apps (from the selected list) that Windows
       re-installed during setup or OOBE, for every user and from the provisioned list. Protected patterns are kept. #>
    param([string[]]$Patterns, [string[]]$Protected)
    $pt = @(Get-W11SafePatterns $Patterns)
    $pr = @(Get-W11SafePatterns $Protected)
    $q = { param($a) if ($a.Count -eq 0) { return '@()' }; return '@(' + ((@($a) | ForEach-Object { "'" + $_ + "'" }) -join ', ') + ')' }
    $lines = @(
        '# WinDebloat Tool - first logon clean-up (generated). Removes apps that came back during setup.',
        '# Runs once from autounattend.xml (FirstLogonCommands); log: %WINDIR%\Setup\Scripts\W11D-FirstLogon.log',
        "`$patterns = $(& $q $pt)",
        "`$protected = $(& $q $pr)",
        '$log = Join-Path $env:WINDIR ''Setup\Scripts\W11D-FirstLogon.log''',
        'function Out-Log([string]$t) { try { Add-Content -LiteralPath $log -Value (''['' + (Get-Date -Format ''yyyy-MM-dd HH:mm:ss'') + ''] '' + $t) } catch { } }',
        'function Test-Match([string]$n, $list) { foreach ($p in $list) { if ($n -like $p) { return $true } }; return $false }',
        'Out-Log ''first logon clean-up started''',
        'try {',
        '    foreach ($p in @(Get-AppxProvisionedPackage -Online)) {',
        '        if ((Test-Match $p.DisplayName $patterns) -and -not (Test-Match $p.DisplayName $protected)) {',
        '            try { $null = Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop; Out-Log (''deprovisioned '' + $p.PackageName) } catch { Out-Log (''failed '' + $p.PackageName + '': '' + $_.Exception.Message) }',
        '        }',
        '    }',
        '} catch { Out-Log (''provisioned list: '' + $_.Exception.Message) }',
        'try { $all = @(Get-AppxPackage -AllUsers -ErrorAction Stop) } catch { $all = @(Get-AppxPackage) }',
        'foreach ($p in $all) {',
        '    if ((Test-Match $p.Name $patterns) -and -not (Test-Match $p.Name $protected) -and -not $p.NonRemovable) {',
        '        try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; Out-Log (''removed '' + $p.PackageFullName) }',
        '        catch { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; Out-Log (''removed (current user) '' + $p.PackageFullName) } catch { Out-Log (''failed '' + $p.PackageFullName + '': '' + $_.Exception.Message) } }',
        '    }',
        '}',
        'Out-Log ''first logon clean-up finished'''
    )
    return (($lines -join "`r`n") + "`r`n")
}

function New-W11UnattendXml {
    param([hashtable]$Options, [ValidateSet('Win10', 'Win11')][string]$Os = 'Win11', [string]$Arch = 'amd64', [string]$Language = 'en-US')
    $o = Get-W11UnattendDefaults
    if ($Options) { foreach ($k in @($Options.Keys)) { $o[$k] = $Options[$k] } }
    $Arch = Get-W11ArchName $Arch
    if (-not (Test-W11LocaleName $Language)) { $Language = 'en-US' }
    if ($o.LocalAccount -and -not (Test-W11LocalAccountName ([string]$o.UserName))) { throw "Invalid local account name / Tên tài khoản không hợp lệ: '$($o.UserName)'" }
    if ($o.Locale -and -not (Test-W11LocaleName ([string]$o.Locale))) { throw "Invalid region / Vùng không hợp lệ: '$($o.Locale)'" }
    if ($o.Keyboard -and -not (Test-W11KeyboardName ([string]$o.Keyboard))) { throw "Invalid keyboard / Bàn phím không hợp lệ: '$($o.Keyboard)'" }
    $isW11 = ($Os -eq 'Win11')
    $c = 'processorArchitecture="{0}" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"' -f $Arch
    $x = New-Object Text.StringBuilder
    $w = { param([string]$s) [void]$x.Append($s + "`r`n") }
    $notes = @()
    if ($o.LocalAccount) { $notes += "- Creates the local administrator account '$([string]$o.UserName -replace '--', '- -')' (password stored in this file as plain text)." }
    else { $notes += '- Local account name/password stay INTERACTIVE.' }
    if ($o.Locale -or $o.Keyboard) { $notes += '- Region / keyboard preset.' } else { $notes += '- Region and keyboard stay INTERACTIVE.' }
    if ($o.SkipPrivacy) { $notes += '- Privacy questions skipped (Microsoft recommended answers turned off where possible).' } else { $notes += '- Privacy questions stay INTERACTIVE.' }
    if ($isW11 -and $o.BypassChecks) { $notes += '- TPM / Secure Boot / RAM / CPU / storage checks are BYPASSED (LabConfig).' } else { $notes += '- TPM / Secure Boot / RAM / CPU requirement checks are NOT bypassed.' }
    if ($o.FirstLogonCleanup) { $notes += '- First logon: removes apps that came back (sources\$OEM$ script).' }
    & $w '<?xml version="1.0" encoding="utf-8"?>'
    & $w '<!-- WinDebloat Tool answer file (Windows 10 / 11), generated.'
    & $w '     - Disk/partition selection and edition stay INTERACTIVE (no disk is wiped automatically). EULA auto-accepted.'
    foreach ($n in $notes) { & $w ('     ' + $n) }
    & $w '-->'
    & $w '<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">'
    # ---- windowsPE ----
    & $w '  <settings pass="windowsPE">'
    & $w "    <component name=`"Microsoft-Windows-International-Core-WinPE`" $c>"
    & $w '      <SetupUILanguage>'
    & $w "        <UILanguage>$Language</UILanguage>"
    & $w '      </SetupUILanguage>'
    & $w '      <InputLocale>0409:00000409</InputLocale>'
    & $w '      <SystemLocale>en-US</SystemLocale>'
    & $w "      <UILanguage>$Language</UILanguage>"
    & $w '      <UserLocale>en-US</UserLocale>'
    & $w '    </component>'
    & $w "    <component name=`"Microsoft-Windows-Setup`" $c>"
    if ($isW11 -and $o.BypassChecks) {
        & $w '      <RunSynchronous>'
        $i = 0
        foreach ($v in @('BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassCPUCheck', 'BypassStorageCheck')) {
            $i++
            & $w '        <RunSynchronousCommand wcm:action="add">'
            & $w "          <Order>$i</Order>"
            & $w "          <Path>reg.exe add &quot;HKLM\SYSTEM\Setup\LabConfig&quot; /v $v /t REG_DWORD /d 1 /f</Path>"
            & $w '        </RunSynchronousCommand>'
        }
        & $w '      </RunSynchronous>'
    }
    & $w '      <UserData>'
    & $w '        <AcceptEula>true</AcceptEula>'
    & $w '      </UserData>'
    & $w '    </component>'
    & $w '  </settings>'
    # ---- specialize ----
    $cmds = @()
    if ($isW11 -and $o.BypassNro) { $cmds += 'reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f' }
    $cmds += 'reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f'
    if ($o.SkipPrivacy) { $cmds += 'reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE" /v DisablePrivacyExperience /t REG_DWORD /d 1 /f' }
    & $w '  <settings pass="specialize">'
    & $w "    <component name=`"Microsoft-Windows-Deployment`" $c>"
    & $w '      <RunSynchronous>'
    $i = 0
    foreach ($cmd in $cmds) {
        $i++
        & $w '        <RunSynchronousCommand wcm:action="add">'
        & $w "          <Order>$i</Order>"
        & $w ('          <Path>{0}</Path>' -f ($cmd -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'))
        & $w '        </RunSynchronousCommand>'
    }
    & $w '      </RunSynchronous>'
    & $w '    </component>'
    & $w '  </settings>'
    # ---- oobeSystem ----
    & $w '  <settings pass="oobeSystem">'
    if ($o.Locale -or $o.Keyboard) {
        $loc = [string]$o.Locale; if (-not $loc) { $loc = $Language }
        $kb = [string]$o.Keyboard; if (-not $kb) { $kb = $loc }
        & $w "    <component name=`"Microsoft-Windows-International-Core`" $c>"
        & $w "      <InputLocale>$(ConvertTo-W11XmlText $kb)</InputLocale>"
        & $w "      <SystemLocale>$(ConvertTo-W11XmlText $loc)</SystemLocale>"
        & $w "      <UILanguage>$Language</UILanguage>"
        & $w "      <UserLocale>$(ConvertTo-W11XmlText $loc)</UserLocale>"
        & $w '    </component>'
    }
    & $w "    <component name=`"Microsoft-Windows-Shell-Setup`" $c>"
    if ($o.FirstLogonCleanup) {
        & $w '      <FirstLogonCommands>'
        & $w '        <SynchronousCommand wcm:action="add">'
        & $w '          <Order>1</Order>'
        & $w ('          <CommandLine>cmd.exe /c powershell.exe -NoProfile -ExecutionPolicy Bypass -File &quot;%WINDIR%\Setup\Scripts\{0}&quot;</CommandLine>' -f $script:W11FirstLogonScript)
        & $w '          <Description>WinDebloat Tool: remove apps that came back</Description>'
        & $w '        </SynchronousCommand>'
        & $w '      </FirstLogonCommands>'
    }
    & $w '      <OOBE>'
    & $w '        <HideEULAPage>true</HideEULAPage>'
    if ($o.LocalAccount) { & $w '        <HideLocalAccountScreen>true</HideLocalAccountScreen>' }
    & $w '        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>'
    & $w '        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>'
    if ($o.SkipPrivacy) { & $w '        <ProtectYourPC>3</ProtectYourPC>' }
    & $w '      </OOBE>'
    if ($o.LocalAccount) {
        $u = ConvertTo-W11XmlText ([string]$o.UserName)
        & $w '      <UserAccounts>'
        & $w '        <LocalAccounts>'
        & $w '          <LocalAccount wcm:action="add">'
        & $w "            <Name>$u</Name>"
        & $w "            <DisplayName>$u</DisplayName>"
        & $w '            <Group>Administrators</Group>'
        & $w '            <Password>'
        & $w "              <Value>$(ConvertTo-W11XmlText ([string]$o.Password))</Value>"
        & $w '              <PlainText>true</PlainText>'
        & $w '            </Password>'
        & $w '          </LocalAccount>'
        & $w '        </LocalAccounts>'
        & $w '      </UserAccounts>'
    }
    & $w '    </component>'
    & $w '  </settings>'
    & $w '</unattend>'
    return $x.ToString()
}

function Write-W11UnattendFiles {
    <# Writes autounattend.xml to the ISO tree root and, with FirstLogonCleanup, the first-logon script to
       sources\$OEM$\$$\Setup\Scripts (Windows Setup copies it to %WINDIR%\Setup\Scripts). The password is never logged. #>
    param([Parameter(Mandatory = $true)][string]$Tree, [hashtable]$Options, [string]$Os = 'Win11', [string]$Arch = 'amd64', [string]$Language = 'en-US',
        [string[]]$Protected)
    $xml = New-W11UnattendXml -Options $Options -Os $Os -Arch $Arch -Language $Language
    $doc = New-Object Xml.XmlDocument
    $doc.LoadXml($xml)   # well-formed check before it goes on the ISO
    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText((Join-W11Path $Tree 'autounattend.xml'), $xml, $utf8)
    $o = Get-W11UnattendDefaults; if ($Options) { foreach ($k in @($Options.Keys)) { $o[$k] = $Options[$k] } }
    $desc = @()
    if ($o.LocalAccount) { $desc += "local account '$($o.UserName)'"; if ([string]$o.Password) { $desc += 'password set (plain text in autounattend.xml)' } else { $desc += 'no password' } }
    if ($Os -eq 'Win11' -and $o.BypassNro) { $desc += 'BypassNRO' }
    if ($Os -eq 'Win11' -and $o.BypassChecks) { $desc += 'TPM/Secure Boot/RAM check bypass' }
    if ($o.SkipPrivacy) { $desc += 'skip privacy' }
    if ($o.Locale -or $o.Keyboard) { $desc += "region $($o.Locale) keyboard $($o.Keyboard)" }
    if ($o.FirstLogonCleanup) {
        $dir = Join-W11Path $Tree 'sources\$OEM$\$$\Setup\Scripts'
        New-W11Directory $dir
        $ps = New-W11FirstLogonScript -Patterns @($o.FirstLogonApps) -Protected $Protected
        [IO.File]::WriteAllText((Join-W11Path $dir $script:W11FirstLogonScript), $ps, (New-Object Text.UTF8Encoding $true))
        $desc += ('first-logon clean-up ({0} app patterns)' -f @(Get-W11SafePatterns @($o.FirstLogonApps)).Count)
    }
    if ($desc.Count) { Write-W11Log -En ('  autounattend.xml: ' + ($desc -join ', ')) -Vi '  autounattend.xml đã tạo' }
    if ($o.LocalAccount -and [string]$o.Password) { Write-W11Log -Level WARN -En '  The account password is stored as PLAIN TEXT in autounattend.xml on the ISO - do not share this ISO.' -Vi '  Mật khẩu tài khoản nằm dạng chữ thường trong autounattend.xml trên ISO - đừng chia sẻ ISO này.' }
}
#endregion

#region ---------- presets (data\presets\*.json, user .json files) ----------
<# Preset schema (version 1):
   { "schema": "windebloat-preset/1", "name": {vi,en,...}, "description": {...},
     "editions": { "mode": "All|HomePro|Custom", "indexes": [] },
     "apps":   { "select": "defaults|level|list|all|none", "level": "safe|aggressive", "ids": [], "exclude": [] },
     "tweaks": { "select": ..., "level": ..., "ids": [] },
     "unattend": { "enabled": true, "localAccount": false, "userName": "", "bypassNro": true, "bypassChecks": false,
                   "skipPrivacy": false, "firstLogonCleanup": false, "locale": "", "keyboard": "" },
     "updates": { "enabled": false, "folder": "", "bootWim": false, "winre": false, "resetBase": false },
     "image": { "compression": "Max|Recovery", "componentCleanup": false } }
   A password is never written to a preset. "list" uses ids; the other modes are resolved for the image's OS. #>
$script:W11PresetSchema = 'windebloat-preset/1'
$script:W11PresetLevels = @{ safe = 1; aggressive = 2; unsafe = 3 }

function Get-W11PresetDir { return (Join-Path $script:W11Root 'data\presets') }

function Get-W11BuiltinPresets {
    # built-in presets: @{ Id; Path; Data } sorted by file name (safe.json first)
    $dir = Get-W11PresetDir
    $out = @()
    if (-not (Test-Path -LiteralPath $dir)) { return $out }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.json' | Sort-Object @{ Expression = { $_.Name -ne 'safe.json' } }, Name)) {
        try { $d = Read-W11Preset -Path $f.FullName; $out += (New-W11Obj @{ Id = [IO.Path]::GetFileNameWithoutExtension($f.Name); Path = $f.FullName; Data = $d }) }
        catch { Write-W11Log -Level WARN -En "Preset $($f.Name) skipped: $($_.Exception.Message)" -Vi 'bỏ qua mẫu cấu hình lỗi' }
    }
    return $out
}

function Test-W11Preset {
    # problems in a parsed preset (empty = valid)
    param($Data)
    $bad = @()
    if (-not ($Data -is [Collections.IDictionary])) { return @('not a JSON object') }
    if ([string](Get-W11JsonVal $Data 'schema' '') -ne $script:W11PresetSchema) { $bad += "schema must be '$($script:W11PresetSchema)'" }
    $ed = Get-W11JsonVal $Data 'editions'
    if ($ed -and @('All', 'HomePro', 'Custom') -notcontains [string](Get-W11JsonVal $ed 'mode' 'All')) { $bad += 'editions.mode must be All, HomePro or Custom' }
    foreach ($s in @('apps', 'tweaks')) {
        $x = Get-W11JsonVal $Data $s
        if ($null -eq $x) { continue }
        if (@('defaults', 'level', 'list', 'all', 'none') -notcontains [string](Get-W11JsonVal $x 'select' 'defaults')) { $bad += "$s.select must be defaults, level, list, all or none" }
        if ([string](Get-W11JsonVal $x 'select' '') -eq 'level' -and -not $script:W11PresetLevels.ContainsKey([string](Get-W11JsonVal $x 'level' ''))) { $bad += "$s.level must be safe or aggressive" }
    }
    $im = Get-W11JsonVal $Data 'image'
    if ($im -and @('Max', 'Recovery') -notcontains [string](Get-W11JsonVal $im 'compression' 'Max')) { $bad += 'image.compression must be Max or Recovery' }
    $un = Get-W11JsonVal $Data 'unattend'
    if ($un) {
        if ((Get-W11JsonVal $un 'password')) { $bad += 'unattend.password is not allowed in a preset' }
        $u = [string](Get-W11JsonVal $un 'userName' '')
        if ($u -and -not (Test-W11LocalAccountName $u)) { $bad += "unattend.userName '$u' is not a valid account name" }
    }
    return $bad
}

function Read-W11Preset {
    param([Parameter(Mandatory = $true)][string]$Path)
    $d = Read-W11JsonFile $Path
    $bad = @(Test-W11Preset $d)
    if ($bad.Count) { throw ("Invalid preset / Mẫu cấu hình không hợp lệ ({0}): {1}" -f (Split-Path -Leaf $Path), ($bad -join '; ')) }
    $un = Get-W11JsonVal $d 'unattend'
    if ($un -and $un.Contains('password')) { $un.Remove('password') }
    return $d
}

function Resolve-W11PresetItems {
    <# apps / tweaks section of a preset -> selected ids among $Items (profile entries with Id / Default / Level).
       Unknown ids in a list are ignored (they may belong to the other OS). #>
    param($Section, [object[]]$Items)
    $sel = [string](Get-W11JsonVal $Section 'select' 'defaults')
    $ex = @(@(Get-W11JsonVal $Section 'exclude' @()) | ForEach-Object { [string]$_ })
    if ($ex.Count) { $Items = @(@($Items) | Where-Object { $_ -and $ex -notcontains $_.Id }) }
    switch ($sel) {
        'none' { return @() }
        'all' { return @(@($Items) | Where-Object { $_ -and $_.Level -ne 'unsafe' } | ForEach-Object { $_.Id }) }
        'level' {
            $max = $script:W11PresetLevels[[string](Get-W11JsonVal $Section 'level' 'safe')]
            if (-not $max) { $max = 1 }
            return @(@($Items) | Where-Object { $_ -and ($_.Default -or ($script:W11PresetLevels.ContainsKey([string]$_.Level) -and $script:W11PresetLevels[[string]$_.Level] -le $max)) } | ForEach-Object { $_.Id })
        }
        'list' {
            $ids = @(@(Get-W11JsonVal $Section 'ids' @()) | ForEach-Object { [string]$_ })
            return @(@($Items) | Where-Object { $_ -and $ids -contains $_.Id } | ForEach-Object { $_.Id })
        }
        default { return @(@($Items) | Where-Object { $_ -and $_.Default } | ForEach-Object { $_.Id }) }
    }
}

function New-W11Preset {
    <# Builds a preset (OrderedDictionary, ready for ConvertTo-W11Json) from the current choices. -Unattend is the
       answer-file option hashtable; its Password is dropped. #>
    param([string]$Name = 'Custom', [string]$EditionMode = 'All', [int[]]$Indexes, [string[]]$Apps, [string[]]$Tweaks,
        [bool]$UnattendEnabled = $true, [hashtable]$Unattend, [hashtable]$Updates, [string]$Compression = 'Max', [bool]$ComponentCleanup = $false)
    $u = Get-W11UnattendDefaults; if ($Unattend) { foreach ($k in @($Unattend.Keys)) { $u[$k] = $Unattend[$k] } }
    $up = @{ Enabled = $false; Folder = ''; BootWim = $false; WinRE = $false; ResetBase = $false }
    if ($Updates) { foreach ($k in @($Updates.Keys)) { $up[$k] = $Updates[$k] } }
    $idx = @(); foreach ($i in @($Indexes)) { if ($i) { $idx += [int]$i } }
    return (New-W11Ordered 'schema' $script:W11PresetSchema `
            'name' (New-W11Ordered 'vi' $Name 'en' $Name 'zh-CN' $Name 'km' $Name) `
            'editions' (New-W11Ordered 'mode' $EditionMode 'indexes' $idx) `
            'apps' (New-W11Ordered 'select' 'list' 'ids' @(@($Apps) | Where-Object { $_ })) `
            'tweaks' (New-W11Ordered 'select' 'list' 'ids' @(@($Tweaks) | Where-Object { $_ })) `
            'unattend' (New-W11Ordered 'enabled' ([bool]$UnattendEnabled) 'localAccount' ([bool]$u.LocalAccount) 'userName' ([string]$u.UserName) `
                'bypassNro' ([bool]$u.BypassNro) 'bypassChecks' ([bool]$u.BypassChecks) 'skipPrivacy' ([bool]$u.SkipPrivacy) `
                'firstLogonCleanup' ([bool]$u.FirstLogonCleanup) 'locale' ([string]$u.Locale) 'keyboard' ([string]$u.Keyboard)) `
            'updates' (New-W11Ordered 'enabled' ([bool]$up.Enabled) 'folder' ([string]$up.Folder) 'bootWim' ([bool]$up.BootWim) 'winre' ([bool]$up.WinRE) 'resetBase' ([bool]$up.ResetBase)) `
            'image' (New-W11Ordered 'compression' $Compression 'componentCleanup' ([bool]$ComponentCleanup)))
}

function Save-W11Preset {
    param([Parameter(Mandatory = $true)]$Preset, [Parameter(Mandatory = $true)][string]$Path)
    $un = $Preset['unattend']
    if ($un -and $un.Contains('password')) { $un.Remove('password') }
    [IO.File]::WriteAllText($Path, (ConvertTo-W11Json $Preset) + "`r`n", (New-Object Text.UTF8Encoding $false))
}

function Get-W11PresetUnattend {
    # preset unattend section -> answer-file option hashtable (no password)
    param($Preset)
    $o = Get-W11UnattendDefaults
    $un = Get-W11JsonVal $Preset 'unattend'
    if (-not $un) { return $o }
    $o.LocalAccount = ((Get-W11JsonVal $un 'localAccount' $false) -eq $true)
    $o.UserName = [string](Get-W11JsonVal $un 'userName' '')
    $o.BypassNro = ((Get-W11JsonVal $un 'bypassNro' $true) -eq $true)
    $o.BypassChecks = ((Get-W11JsonVal $un 'bypassChecks' $false) -eq $true)
    $o.SkipPrivacy = ((Get-W11JsonVal $un 'skipPrivacy' $false) -eq $true)
    $o.FirstLogonCleanup = ((Get-W11JsonVal $un 'firstLogonCleanup' $false) -eq $true)
    $o.Locale = [string](Get-W11JsonVal $un 'locale' '')
    $o.Keyboard = [string](Get-W11JsonVal $un 'keyboard' '')
    return $o
}

function Resolve-W11PresetRef {
    # preset name (built-in file name without .json, e.g. safe / aggressive) or a path -> full path
    param([Parameter(Mandatory = $true)][string]$Preset)
    if (Test-Path -LiteralPath $Preset -PathType Leaf) { return (Resolve-Path -LiteralPath $Preset).ProviderPath }
    $p = Join-Path (Get-W11PresetDir) ($Preset.ToLowerInvariant() + '.json')
    if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    throw "Preset not found / Không thấy mẫu cấu hình: $Preset"
}
#endregion

#region ---------- Simple mode (one-screen flow: download -> Home + Pro -> defaults -> ISO) ----------
# Edition names used when an image has no edition id (Home / Pro in some languages of the official media)
$script:W11HomeNames = @('Home', 'Famille', 'Hogar', 'Domácnost', 'Familiale', 'Домашняя', '家庭版', '家用版', 'ホーム', '홈')
$script:W11ProNames = @('Pro', 'Professional', 'Professionnel', 'Профессиональная', '专业版', '專業版', 'プロ')
# never kept by Home + Pro: N (no media apps), single language, China, education, workstations, enterprise
$script:W11NotHomeProRx = '(?i)(\bN\b|single\s*language|unilingue|un\s+solo\s+idioma|einzelsprache|одного\s+языка|单语言|單一語言|中文版|country\s*specific|china|中国|ducation|ducación|bildung|для\s+образовательных|образовательн|教育|workstation|stations\s+de\s+travail|estaciones\s+de\s+trabajo|для\s+рабочих|工作站|enterprise|entreprise|企业|企業|\bS\b|\bSE\b|team|IoT)'

function Merge-W11EditionIds {
    # fills a missing EditionId / Name of DISM image info from the WIM XML (same index)
    param([object[]]$Images, [object[]]$XmlInfo)
    $byIdx = @{}; foreach ($x in @($XmlInfo)) { if ($x) { $byIdx[[int]$x.Index] = $x } }
    foreach ($i in @($Images)) {
        if (-not $i) { continue }
        $x = $byIdx[[int]$i.Index]
        if (-not $x) { continue }
        if (-not $i.EditionId -and $x.EditionId) { $i.EditionId = $x.EditionId }
        if (-not $i.Name -and $x.Name) { $i.Name = $x.Name }
    }
    return $Images
}

function Get-W11EditionKind {
    <# 'Home', 'Pro' or $null for one image. The edition id decides (Core / Professional exactly: CoreN,
       ProfessionalN, CoreSingleLanguage, CoreCountrySpecific, ProfessionalEducation... are not standard Home / Pro).
       Without an edition id the (possibly translated) name is used. #>
    param($Image)
    $id = [string]$Image.EditionId
    if ($id) {
        if ($id -eq 'Core') { return 'Home' }
        if ($id -eq 'Professional') { return 'Pro' }
        return $null
    }
    $n = [string]$Image.Name
    if (-not $n -or $n -match $script:W11NotHomeProRx) { return $null }
    foreach ($w in $script:W11HomeNames) { if ($n -match ('(?i)(^|[\s(])' + [regex]::Escape($w) + '($|[\s)])') -or ($w -match '[^\x00-\x7F]' -and $n.Contains($w))) { return 'Home' } }
    foreach ($w in $script:W11ProNames) { if ($n -match ('(?i)(^|[\s(])' + [regex]::Escape($w) + '($|[\s)])') -or ($w -match '[^\x00-\x7F]' -and $n.Contains($w))) { return 'Pro' } }
    return $null
}

function Select-W11HomeProImages {
    # the standard Home and Pro images of an install.wim/esd (first of each), in index order
    param([object[]]$Images)
    $hm = $null; $pro = $null
    foreach ($i in @($Images | Where-Object { $_ } | Sort-Object Index)) {
        $k = Get-W11EditionKind $i
        if ($k -eq 'Home' -and -not $hm) { $hm = $i }
        elseif ($k -eq 'Pro' -and -not $pro) { $pro = $i }
    }
    return @(@($hm, $pro) | Where-Object { $_ } | Sort-Object Index)
}

# ISO languages offered in Simple mode (Microsoft's language names). 'auto' follows the UI language.
$script:W11IsoLanguages = @('auto', 'English International', 'English', 'Chinese Simplified', 'Chinese Traditional', 'Thai', 'Japanese', 'Korean', 'French', 'German', 'Spanish')

function Get-W11IsoLanguagePrefs {
    <# Ordered Microsoft language names to try. auto: vi -> Vietnamese (if Microsoft offers it) then English
       International; zh-CN -> Chinese Simplified; en -> English (United States); km -> English International.
       English International and English are always the last fallbacks. #>
    param([string]$UiLang = 'vi', [string]$Choice = 'auto')
    $l = @()
    if ($Choice -and $Choice -ne 'auto') { $l += $Choice }
    else {
        switch ($UiLang) {
            'vi' { $l += 'Vietnamese'; $l += 'English International' }
            'zh-CN' { $l += 'Chinese Simplified' }
            'en' { $l += 'English' }
            default { $l += 'English International' }
        }
    }
    foreach ($x in @('English International', 'English')) { if ($l -notcontains $x) { $l += $x } }
    return $l
}

function Select-W11IsoSku {
    # first SKU whose Language matches the preference list (case-insensitive); $null when none
    param([object[]]$Skus, [string[]]$Prefs)
    foreach ($p in @($Prefs)) {
        foreach ($s in @($Skus)) { if ($s -and ([string]$s.Language) -ieq $p) { return $s } }
    }
    return $null
}

function Get-W11SimpleArch {
    # ISO architecture for this PC: Windows 11 x64 / arm64; Windows 10 x64 (x86 on a 32-bit Windows)
    param([string]$Os = 'Win11', [string]$HostArch = (Get-W11HostArch))
    if ($Os -eq 'Win11') { if ($HostArch -eq 'arm64') { return 'arm64' }; return 'x64' }
    if ($HostArch -eq 'x86') { return 'x86' }
    return 'x64'
}

function Get-W11SimpleEntry {
    # newest release Microsoft still serves for the OS / architecture (catalog is newest first)
    param([object[]]$Catalog, [string]$Os = 'Win11', [string]$Arch = 'x64')
    foreach ($e in @($Catalog)) { if ($e -and $e.Os -eq $Os -and $e.Arch -eq $Arch -and $e.Available) { return $e } }
    return $null
}

function Get-W11SimpleDefaultFolder {
    # Desktop\WinDebloat -> <tool>\output
    param([string]$Desktop = ([Environment]::GetFolderPath('Desktop')), [string]$ToolRoot = $script:W11Root)
    if ($Desktop -and (Test-W11PathText $Desktop -Container)) { return (Join-Path $Desktop 'WinDebloat') }
    return (Join-Path $ToolRoot 'output')
}

$script:W11SimpleMinFreeGB = 15   # ISO download (~6 GB) + work copy; below this Simple mode warns
$script:W11SimpleBuildMinFreeGB = 10   # checked by the engine once the ISO is on disk (work copy + new ISO); 0 = user accepted low space

function Get-W11SimplePlan {
    <# Everything Simple mode will do, decided up front (pure; the GUI shows it, the tests check it):
       newest official ISO for Os + host architecture, language preference, Home + Pro, the Safe preset
       (= default apps, tweaks, answer file, compression), work folder and output inside OutputFolder. #>
    param([ValidateSet('Win10', 'Win11')][string]$Os = 'Win11', [string]$UiLang = 'vi', [string]$LangChoice = 'auto',
        [Parameter(Mandatory = $true)][string]$OutputFolder, [string]$HostArch = (Get-W11HostArch), [int]$HostBuild = (Get-W11OsBuild),
        [double]$FreeGB = -1, [string]$IsoPath)
    $dir = $OutputFolder.TrimEnd('\', '/')
    $steps = @('check', 'oscdimg')
    if (-not $IsoPath) { $steps += 'download' }
    $steps += 'build'
    return (New-W11Obj @{
            Os = $Os; Arch = (Get-W11SimpleArch -Os $Os -HostArch $HostArch); LangPrefs = @(Get-W11IsoLanguagePrefs -UiLang $UiLang -Choice $LangChoice)
            LangChoice = $LangChoice; OutputFolder = $dir; DownloadFolder = $dir; WorkDir = (Join-W11Path $dir 'WinDebloat_work')
            EditionMode = 'HomePro'; Preset = 'safe'; IsoPath = $IsoPath; Steps = $steps; Adk = (Get-W11AdkSetupPlan -HostBuild $HostBuild)
            MinFreeGB = $script:W11SimpleMinFreeGB; BuildMinFreeGB = $script:W11SimpleBuildMinFreeGB; FreeGB = $FreeGB; LowSpace = ($FreeGB -ge 0 -and $FreeGB -lt $script:W11SimpleMinFreeGB)
        })
}

function Set-W11SimpleStep {
    param([string]$Step)
    $s = $script:W11D.Sync
    if ($s) { $s.Step = $Step }
    Write-W11Log -Level STEP -En "[Simple] step: $Step" -Vi "[Đơn giản] bước: $Step"
}

function Invoke-W11SimpleBuild {
    <# Runs a Simple-mode plan: oscdimg (installs the ADK Deployment Tools if needed), download of the newest
       official ISO from Microsoft (aria2 when available, SHA256 checked against Microsoft's table), then the build
       with Home + Pro and the Safe preset. A Microsoft download failure does not throw: the result has
       DownloadFailed = $true so the caller can offer the verified mirror and call again with -IsoPath.
       Returns @{ Stage; IsoPath; Build; DownloadFailed; Error; Entry; Sku; DryRun }. #>
    param([Parameter(Mandatory = $true)]$Plan, [string]$IsoPath, [hashtable]$Sync, [switch]$DryRun, [double]$MinFreeGB = -1, [hashtable]$DownloadOptions = @{})
    if ($Sync) { $script:W11D.Sync = $Sync }
    if ($MinFreeGB -lt 0 -and $null -ne $Plan.BuildMinFreeGB) { $MinFreeGB = [double]$Plan.BuildMinFreeGB }
    $res = @{ Stage = 'check'; IsoPath = $IsoPath; Build = $null; DownloadFailed = $false; Error = $null; Entry = $null; Sku = $null; DryRun = [bool]$DryRun }
    if (-not $IsoPath) { $IsoPath = $Plan.IsoPath; $res.IsoPath = $IsoPath }
    Set-W11SimpleStep 'check'
    Write-W11Log -En ("Simple mode: {0} {1}, ISO language {2}, Home + Pro, preset {3}, output folder {4}" -f $Plan.Os, $Plan.Arch, ($Plan.LangPrefs -join ' > '), $Plan.Preset, $Plan.OutputFolder) -Vi 'Chế độ Đơn giản: tải ISO mới nhất, giữ Home + Pro, gỡ ứng dụng và tinh chỉnh theo mặc định'
    if (-not $DryRun) { New-W11Directory $Plan.OutputFolder }
    # ---- oscdimg ----
    $res.Stage = 'oscdimg'; Set-W11SimpleStep 'oscdimg'
    $osc = Find-W11Oscdimg
    if ($osc) { Write-W11Log -Level OK -En "oscdimg: $osc" -Vi 'Đã có oscdimg' }
    elseif ($DryRun) { Write-W11Log -Level DRY -En ("would install the Windows ADK Deployment Tools: {0} {1} ({2})" -f $Plan.Adk.FileName, $Plan.Adk.Arguments, $Plan.Adk.Url) -Vi 'sẽ tự cài ADK Deployment Tools' }
    else { $osc = Install-W11Oscdimg -Method AdkSetup }
    Assert-W11NotCancelled
    # ---- download ----
    if (-not $IsoPath) {
        $res.Stage = 'download'; Set-W11SimpleStep 'download'
        try {
            $entry = Get-W11SimpleEntry -Catalog @(Get-MsReleaseCatalog -Os @($Plan.Os)) -Os $Plan.Os -Arch $Plan.Arch
            if (-not $entry) { throw "No $($Plan.Os) $($Plan.Arch) release is offered by Microsoft" }
            $res.Entry = $entry
            if ($DryRun) {
                Write-W11Log -Level DRY -En ("would download {0} [{1}] from Microsoft (language: {2}) into {3}, then check its SHA256" -f $entry.Release, $entry.Arch, ($Plan.LangPrefs -join ' > '), $Plan.DownloadFolder) -Vi 'sẽ tải ISO mới nhất từ Microsoft'
            } else {
                $lr = Update-MsEntryLanguages -Entry $entry
                if (-not $lr.Ok) { throw $lr.Error }
                Set-MsEntryLanguages -Catalog @($entry) -Result $lr
                $sku = Select-W11IsoSku -Skus $lr.Skus -Prefs $Plan.LangPrefs
                if (-not $sku) { throw "Microsoft offers none of these languages: $($Plan.LangPrefs -join ', ')" }
                if ($sku.Language -ne $Plan.LangPrefs[0]) { Write-W11Log -Level WARN -En "Microsoft does not offer '$($Plan.LangPrefs[0])' for this release - using '$($sku.Language)'" -Vi "Microsoft không có ISO '$($Plan.LangPrefs[0])', dùng '$($sku.Language)'" }
                $res.Sku = $sku
                $IsoPath = Invoke-MsIsoDownload -Entry $entry -Sku $sku -Folder $Plan.DownloadFolder -Sync $Sync -Options $DownloadOptions
                $res.IsoPath = $IsoPath
            }
        } catch [System.OperationCanceledException] {
            throw
        } catch {
            if ($Sync -and $Sync.Cancel) { throw (New-Object System.OperationCanceledException 'Cancelled by user / Người dùng đã huỷ') }
            $res.DownloadFailed = $true; $res.Error = $_.Exception.Message
            Write-W11Log -Level ERROR -En "Download from Microsoft failed: $($res.Error)" -Vi 'Tải ISO từ Microsoft thất bại'
            return (New-W11Obj $res)
        }
    }
    Assert-W11NotCancelled
    # ---- build ----
    $res.Stage = 'build'; Set-W11SimpleStep 'build'
    $leaf = 'Windows'; if ($IsoPath) { $leaf = [IO.Path]::GetFileNameWithoutExtension((Get-W11PathLeaf $IsoPath)) }
    if (-not $IsoPath -and $DryRun) { Write-W11Log -Level DRY -En ("would build {0} with Home + Pro and preset {1} (oscdimg, BIOS + UEFI)" -f (Join-W11Path $Plan.OutputFolder 'Windows_debloated.iso'), $Plan.Preset) -Vi 'sẽ tạo ISO gọn nhẹ'; return (New-W11Obj $res) }
    $a = @{ IsoPath = $IsoPath; OutputIso = (Join-W11Path $Plan.OutputFolder ($leaf + '_debloated.iso')); WorkDir = $Plan.WorkDir
        EditionMode = $Plan.EditionMode; TargetOs = $Plan.Os; Preset = $Plan.Preset; DryRun = [bool]$DryRun; WorkDirConflict = 'NewFolder' }
    if ($MinFreeGB -ge 0) { $a.MinFreeGB = [int]$MinFreeGB }
    if ($osc) { $a.OscdimgPath = $osc }
    if ($Sync) { $a.Sync = $Sync }
    $res.Build = Invoke-Win11Debloat @a
    $res.Stage = 'done'; Set-W11SimpleStep 'done'
    return (New-W11Obj $res)
}
#endregion

#region ---------- image export / size checks ----------
function Test-W11PathInside {
    # $true when $Path is $Parent itself or anything below it (case-insensitive, '\' and '/' are the same)
    param([string]$Path, [string]$Parent)
    if (-not $Path -or -not $Parent) { return $false }
    $a = ($Path -replace '/', '\').TrimEnd('\') + '\'
    $b = ($Parent -replace '/', '\').TrimEnd('\') + '\'
    return $a.StartsWith($b, [StringComparison]::OrdinalIgnoreCase)
}

function Get-W11WorkLayout {
    # every temporary path lives directly under the work dir, next to (never inside) the ISO tree
    param([Parameter(Mandatory = $true)][string]$WorkDir, [ValidateSet('Max', 'Recovery')][string]$Compression = 'Max')
    $ext = 'wim'; if ($Compression -eq 'Recovery') { $ext = 'esd' }
    return (New-W11Obj @{
        Tree = (Join-W11Path $WorkDir 'iso'); Mount = (Join-W11Path $WorkDir 'mount'); Scratch = (Join-W11Path $WorkDir 'scratch')
        WorkWim = (Join-W11Path $WorkDir 'install.work.wim'); NewImage = (Join-W11Path $WorkDir ('install.new.' + $ext))
        Marker = (Join-W11Path $WorkDir '.w11debloat-work'); Ext = $ext
        MountBoot = (Join-W11Path $WorkDir 'mountboot'); BootWork = (Join-W11Path $WorkDir 'boot.work.wim'); BootNew = (Join-W11Path $WorkDir 'boot.new.wim')
        MountRe = (Join-W11Path $WorkDir 'mountre'); WinReWork = (Join-W11Path $WorkDir 'winre.work.wim'); WinReDone = (Join-W11Path $WorkDir 'winre.new.wim')
        WinReCacheDir = (Join-W11Path $WorkDir 'winrecache')
    })
}

function Assert-W11WorkLayout {
    # throws if a mount/scratch/temp image path would end up inside the folder that becomes the ISO (or the other way round)
    param([Parameter(Mandatory = $true)]$Layout, [string]$OutputIso)
    $t = $Layout.Tree
    $bad = @()
    foreach ($n in @('Mount', 'Scratch', 'WorkWim', 'NewImage', 'MountBoot', 'BootWork', 'BootNew', 'MountRe', 'WinReWork', 'WinReDone', 'WinReCacheDir')) {
        $p = $Layout.$n
        if ((Test-W11PathInside $p $t) -or (Test-W11PathInside $t $p)) { $bad += "$n=$p" }
    }
    if ($OutputIso -and (Test-W11PathInside $OutputIso $t)) { $bad += "OutputIso=$OutputIso" }
    if ((Test-W11PathInside $t $Layout.Mount)) { $bad += "Tree=$t" }
    if ($bad.Count -gt 0) { throw ('Unsafe work folder layout (temporary files inside the ISO tree) / Thư mục tạm nằm trong cây ISO: ' + ($bad -join '; ')) }
}

function Get-W11ExportArgs {
    # DISM command line that copies one edition into a NEW image file (dedupe by file hash, full recompression)
    param([Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][int]$Index, [Parameter(Mandatory = $true)][string]$Destination,
        [ValidateSet('Max', 'Recovery')][string]$Compression = 'Max', [string]$ScratchDir, [switch]$CheckIntegrity)
    $a = '/Export-Image /SourceImageFile:{0} /SourceIndex:{1} /DestinationImageFile:{2} /Compress:{3}' -f (ConvertTo-W11Arg $Source), $Index, (ConvertTo-W11Arg $Destination), $Compression.ToLower()
    if ($CheckIntegrity) { $a += ' /CheckIntegrity' }
    if ($ScratchDir) { $a += ' /ScratchDir:' + (ConvertTo-W11Arg $ScratchDir) }
    return $a
}

function Get-W11SplitArgs {
    # install.wim > 4 GB does not fit on a FAT32 USB stick -> install.swm, install2.swm, ...
    param([Parameter(Mandatory = $true)][string]$ImageFile, [Parameter(Mandatory = $true)][string]$SwmFile, [int]$SizeMB = 3800)
    return ('/Split-Image /ImageFile:{0} /SWMFile:{1} /FileSize:{2} /CheckIntegrity' -f (ConvertTo-W11Arg $ImageFile), (ConvertTo-W11Arg $SwmFile), $SizeMB)
}

function Get-W11FileLength {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) { return [int64](Get-Item -LiteralPath $Path -Force).Length }
    return [int64]0
}

function Format-W11Size {
    param([int64]$Bytes)
    return ('{0:N2} GB' -f ($Bytes / 1GB))
}

function Get-W11TreeFiles {
    param([Parameter(Mandatory = $true)][string]$Dir)
    return @(Get-ChildItem -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer })
}

function Get-W11LargestFiles {
    param([Parameter(Mandatory = $true)][string]$Dir, [int]$Top = 10)
    return @(Get-W11TreeFiles $Dir | Sort-Object Length -Descending | Select-Object -First $Top)
}

function Write-W11LargestFiles {
    param([Parameter(Mandatory = $true)][string]$Dir, [int]$Top = 10)
    $root = ($Dir -replace '/', '\').TrimEnd('\')
    foreach ($f in (Get-W11LargestFiles $Dir $Top)) {
        $rel = ($f.FullName -replace '/', '\')
        if ($rel.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($root.Length).TrimStart('\') }
        Write-W11Log -En ('    {0,10}  {1}' -f (Format-W11Size $f.Length), $rel)
    }
}

function Clear-W11TreeTemp {
    # removes leftovers that must never be packed into the ISO: extra install images, DISM/robocopy temp files
    param([Parameter(Mandatory = $true)][string]$Tree, [string]$KeepImage)
    $removed = @()
    $src = Join-W11Path $Tree 'sources'
    foreach ($f in (Get-W11TreeFiles $Tree)) {
        $n = $f.Name.ToLower()
        $isImg = (($f.DirectoryName -replace '/', '\').TrimEnd('\') -eq ($src -replace '/', '\').TrimEnd('\')) -and ($n -like 'install*.wim' -or $n -like 'install*.esd' -or $n -like 'install*.swm')
        $isTmp = ($n -like '*.tmp' -or $n -like '*.partial' -or $n -like '~*' -or $n -eq 'install.work.wim' -or $n -like 'install.new.*' -or $n -like 'kept_index*.txt')
        $keepIt = ($KeepImage -and ($f.FullName -replace '/', '\') -eq ($KeepImage -replace '/', '\'))
        if ($isImg -and $KeepImage -like '*.swm' -and $n -like 'install*.swm') { $keepIt = $true }   # install.swm, install2.swm, ...
        if (($isImg -or $isTmp) -and -not $keepIt) { Remove-Item -LiteralPath $f.FullName -Force; $removed += $f.FullName }
    }
    return $removed
}
#endregion

#region ---------- work folder ownership / cleanup ----------
$script:W11WorkFiles = @('.w11debloat-work', 'install.work.wim', 'install.new.wim', 'install.new.esd', 'install.wim', 'install.esd',
    'boot.work.wim', 'boot.new.wim', 'winre.work.wim', 'winre.new.wim')
$script:W11IsoRootNames = @('boot', 'efi', 'sources', 'support', 'setup.exe', 'autorun.inf', 'bootmgr', 'bootmgr.efi', 'autounattend.xml', '[boot]')
$script:W11ImageRootNames = @('windows', 'program files', 'program files (x86)', 'programdata', 'users', 'perflogs', 'recovery', '$recycle.bin', '$windows.~bt', '$windows.~ws', 'system volume information', 'documents and settings', 'config.msi', 'msocache', 'inetpub', 'program files (arm)')
# boot.wim (Windows Setup) and WinRE images also have sources\ and setup.exe at their root
$script:W11BootRootNames = @('windows', 'program files', 'program files (x86)', 'programdata', 'users', 'sources', 'setup.exe', 'recovery', 'program files (arm)', '$recycle.bin', 'system volume information')

function Get-W11LocalText {
    <# Engine texts are bilingual 'English / Tiếng Việt' (the log keeps both). The GUI shows one language:
       Vietnamese part for 'vi', English part for every other UI language. Works line by line; a line is split at
       the first ' / ' with no Vietnamese letter before it and a Vietnamese letter after it. #>
    param([string]$Text, [string]$Lang = 'vi')
    if (-not $Text) { return $Text }
    $vn = '[àáảãạăắằẳẵặâấầẩẫậđèéẻẽẹêếềểễệìíỉĩịòóỏõọôốồổỗộơớờởỡợùúủũụưứừửữựỳýỷỹỵÀÁẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬĐÈÉẺẼẸÊẾỀỂỄỆÌÍỈĨỊÒÓỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢÙÚỦŨỤƯỨỪỬỮỰỲÝỶỸỴ]'
    $out = @()
    foreach ($line in ($Text -split "`n")) {
        $res = $line; $from = 0
        while ($true) {
            $i = $line.IndexOf(' / ', $from)
            if ($i -lt 0) { break }
            $left = $line.Substring(0, $i); $right = $line.Substring($i + 3)
            if ($left -notmatch $vn -and $right -match $vn) {
                if ($Lang -eq 'vi') { $res = $right } else { $res = $left }
                break
            }
            $from = $i + 3
        }
        $out += $res
    }
    return ($out -join "`n")
}

function Test-W11KnownWorkItem {
    # one top-level entry of a work folder: does it look like something this tool (any version) creates?
    param([Parameter(Mandatory = $true)]$Item)
    $n = $Item.Name.ToLower()
    if ($Item.PSIsContainer) {
        if ($n -eq 'scratch') { return $true }
        $names = $null
        if ($n -eq 'iso') { $names = $script:W11IsoRootNames }
        elseif ($n -eq 'mount') { $names = $script:W11ImageRootNames }
        elseif ($n -eq 'mountboot' -or $n -eq 'mountre') { $names = $script:W11BootRootNames }
        elseif ($n -eq 'winrecache') {
            foreach ($c in @(Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue)) { if ($c.PSIsContainer -or $c.Name -notlike '*.wim') { return $false } }
            return $true
        }
        else { return $false }
        foreach ($c in @(Get-ChildItem -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue)) {
            if ($names -notcontains $c.Name.ToLower()) { return $false }
        }
        return $true
    }
    if ($script:W11WorkFiles -contains $n) { return $true }
    return ($n -like '*.log' -or $n -like '*.tmp' -or $n -like 'kept_index*.txt' -or $n -like 'install*.swm')
}

function Get-W11WorkDirState {
    # Missing | Empty | Ours (marker, or only things this tool creates: leftover of an earlier run) | Foreign
    param([Parameter(Mandatory = $true)][string]$WorkDir)
    if (-not (Test-Path -LiteralPath $WorkDir)) { return 'Missing' }
    if (Test-Path -LiteralPath $WorkDir -PathType Leaf) { return 'Foreign' }
    $items = @(Get-ChildItem -LiteralPath $WorkDir -Force -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) { return 'Empty' }
    if (Test-Path -LiteralPath (Join-W11Path $WorkDir '.w11debloat-work')) { return 'Ours' }
    foreach ($i in $items) { if (-not (Test-W11KnownWorkItem $i)) { return 'Foreign' } }
    return 'Ours'
}

function Get-W11UniqueWorkDir {
    # D:\WinDebloat_work -> D:\WinDebloat_work_2, _3, ... (first one that is missing, empty or ours)
    param([Parameter(Mandatory = $true)][string]$WorkDir)
    $b = $WorkDir.TrimEnd([char[]]@('\', '/'))
    for ($n = 2; $n -lt 100; $n++) {
        $c = '{0}_{1}' -f $b, $n
        if ((Get-W11WorkDirState $c) -ne 'Foreign') { return $c }
    }
    throw "No free work folder name next to $WorkDir / Không tìm được tên thư mục tạm trống cạnh $WorkDir"
}

function Get-W11MountedImages {
    # mount folders DISM knows about (also ones left by an earlier run or another version)
    $res = Invoke-W11Dism '/Get-MountedImageInfo' -Quiet -NoThrow
    $m = @()
    foreach ($l in @($res.Lines)) { if ([string]$l -match '^\s*Mount Dir\s*:\s*(.+?)\s*$') { $m += $Matches[1] } }
    return $m
}

function Remove-W11WorkTree {
    # deletes the work folder; the ownership marker goes LAST, so a half-deleted folder is still recognised
    param([Parameter(Mandatory = $true)][string]$WorkDir, [int]$Retries = 4, [int]$DelaySec = 2)
    $marker = Join-W11Path $WorkDir '.w11debloat-work'
    for ($a = 1; $a -le $Retries; $a++) {
        if (-not (Test-Path -LiteralPath $WorkDir)) { return $true }
        try {
            foreach ($c in @(Get-ChildItem -LiteralPath $WorkDir -Force)) {
                if ($c.Name -ne '.w11debloat-work') { Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction Stop }
            }
            if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker -Force -ErrorAction Stop }
            Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction Stop
            Write-W11Log -En "  Work folder deleted: $WorkDir" -Vi '  Đã xoá thư mục tạm'
            return $true
        } catch {
            Write-W11Log -Level WARN -En "  Delete attempt $a/$Retries failed: $($_.Exception.Message)" -Vi "  Xoá lần $a/$Retries chưa được"
            $sys = Join-Path ([string]$env:windir) 'System32'
            Write-W11Log -En '  Clearing read-only/system/hidden attributes...' -Vi '  Bỏ thuộc tính chỉ đọc/hệ thống/ẩn...'
            $null = Invoke-W11Process -FilePath (Join-Path $sys 'attrib.exe') -Arguments ('-R -S -H {0} /S /D' -f (ConvertTo-W11Arg (Join-W11Path $WorkDir '*'))) -Quiet
            if ($a -ge 2) {
                Write-W11Log -En '  Taking ownership (takeown) and granting Administrators full control (icacls)...' -Vi '  Lấy quyền sở hữu (takeown) và cấp toàn quyền cho Administrators (icacls)...'
                $null = Invoke-W11Process -FilePath (Join-Path $sys 'takeown.exe') -Arguments ('/F {0} /R /A /D Y' -f (ConvertTo-W11Arg $WorkDir)) -Quiet
                $null = Invoke-W11Process -FilePath (Join-Path $sys 'icacls.exe') -Arguments ('{0} /grant *S-1-5-32-544:(OI)(CI)F /T /C /Q' -f (ConvertTo-W11Arg $WorkDir)) -Quiet
            }
            if ($DelaySec -gt 0) { Start-Sleep -Seconds $DelaySec }
        }
    }
    return (-not (Test-Path -LiteralPath $WorkDir))
}

function Clear-W11WorkDir {
    <# Cleans a work folder of this tool (current run or a leftover of any version):
       1. unload our offline hives  2. discard every image DISM has mounted below the folder (+ a non-empty mount
       folder DISM does not list), then /Cleanup-Mountpoints  3. delete with retries (attributes, ownership). #>
    param([Parameter(Mandatory = $true)][string]$WorkDir, [string]$MountDir, [switch]$Quiet)
    if (-not $MountDir) { $MountDir = Join-W11Path $WorkDir 'mount' }
    if (-not $Quiet) { Write-W11Log -Level STEP -En "Cleaning work folder $WorkDir..." -Vi "Đang dọn thư mục tạm $WorkDir..." }
    Write-W11Log -En '  Unloading offline registry hives (if loaded)...' -Vi '  Gỡ các hive registry offline (nếu còn)...'
    Dismount-W11Hives
    $dismOk = $true
    if (-not $script:W11D.Dism) { try { $null = Select-W11Dism } catch { $dismOk = $false; Write-W11Log -Level WARN -En "  No DISM, cannot check mounted images: $($_.Exception.Message)" -Vi '  Không có DISM, không kiểm tra được image đang mount' } }
    if ($dismOk) {
        $dirs = @()
        foreach ($m in @(Get-W11MountedImages)) { if (Test-W11PathInside $m $WorkDir) { $dirs += $m } }
        foreach ($md in @((Join-W11Path $WorkDir 'mountre'), (Join-W11Path $WorkDir 'mountboot'), $MountDir)) {
            if ((Test-Path -LiteralPath $md -PathType Container) -and @(Get-ChildItem -LiteralPath $md -Force -ErrorAction SilentlyContinue).Count -gt 0) {
                $known = $false; foreach ($d in $dirs) { if ((Test-W11PathInside $d $md) -and (Test-W11PathInside $md $d)) { $known = $true } }
                if (-not $known) { $dirs += $md }
            }
        }
        foreach ($d in $dirs) {
            Write-W11Log -Level WARN -En "  Image still mounted at $d - discarding (dism /Unmount-Image /Discard)..." -Vi "  Image còn mount ở $d - đang huỷ mount..."
            $r = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Discard' -f (ConvertTo-W11Arg $d)) -Quiet -NoThrow
            Write-W11Log -En "  unmount exit code $($r.ExitCode)"
        }
        Write-W11Log -En '  dism /Cleanup-Mountpoints...' -Vi '  Dọn điểm mount hỏng...'
        $r = Invoke-W11Dism '/Cleanup-Mountpoints' -Quiet -NoThrow
        Write-W11Log -En "  cleanup-mountpoints exit code $($r.ExitCode)"
    }
    if (-not (Remove-W11WorkTree -WorkDir $WorkDir)) {
        throw "Could not delete the work folder $WorkDir (files in use? close Explorer windows / antivirus scan, or restart Windows and try again) / Không xoá được thư mục tạm $WorkDir (file đang được dùng? hãy đóng cửa sổ Explorer, chờ diệt virus quét xong hoặc khởi động lại máy rồi thử lại)"
    }
}
#endregion

#region ---------- main ----------
function Invoke-Win11Debloat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$IsoPath,
        [Parameter(Mandatory = $true)][string]$OutputIso,
        [string]$WorkDir,
        [ValidateSet('All', 'HomePro', 'Custom')][string]$EditionMode = 'All',
        [ValidateSet('Auto', 'Win10', 'Win11')][string]$TargetOs = 'Auto',   # Auto = from image build
        [int[]]$Indexes,
        [string[]]$RemoveApps,          # $null = config defaults
        [string[]]$Tweaks,              # $null = config defaults
        [bool]$Autounattend = $true,
        [string]$AutounattendPath,
        [bool]$ComponentCleanup = $false,
        [ValidateSet('Max', 'Recovery')][string]$Compression = 'Max',   # Max = LZX install.wim, Recovery = LZMS install.esd (smallest, slow)
        [int]$SplitWimMB = 0,           # > 0: split an install.wim bigger than 4 GB into install*.swm (FAT32 USB)
        [bool]$DryRun = $false,
        [int]$MinFreeGB = 25,
        [string]$OscdimgPath,
        [string]$ConfigPath,
        [string]$LogPath,
        [bool]$KeepWorkDir = $false,
        [ValidateSet('NewFolder', 'Fail')][string]$WorkDirConflict = 'NewFolder',   # work folder with foreign files: use <dir>_2 or stop
        [hashtable]$UnattendOptions,    # generated answer file options (see New-W11UnattendXml); ignored with -AutounattendPath
        [string]$UpdatesPath,           # folder with .msu / .cab updates to integrate (SSU, LCU, .NET, Safe OS)
        [bool]$UpdateBootWim = $false,  # also add SSU + LCU to boot.wim
        [bool]$UpdateWinRE = $false,    # also add SSU + Safe OS update to WinRE (Winre.wim inside each edition)
        [bool]$ResetBase = $false,      # /StartComponentCleanup /ResetBase after updating (smaller, updates can no longer be removed)
        [string]$Preset,                # preset name (safe, aggressive) or .json path; explicit parameters win
        [hashtable]$Sync
    )
    $ErrorActionPreference = 'Stop'
    if ($Sync) { $script:W11D.Sync = $Sync }
    # ---- preset: fills every option that was not given explicitly ----
    $presetData = $null
    if ($Preset) {
        $presetFile = Resolve-W11PresetRef $Preset
        $presetData = Read-W11Preset -Path $presetFile
        $bp = $PSBoundParameters
        $ed = Get-W11JsonVal $presetData 'editions'
        if ($ed -and -not $bp.ContainsKey('EditionMode')) { $EditionMode = [string](Get-W11JsonVal $ed 'mode' 'All') }
        if ($ed -and -not $bp.ContainsKey('Indexes') -and @(Get-W11JsonVal $ed 'indexes' @()).Count) { $Indexes = @(@(Get-W11JsonVal $ed 'indexes' @()) | ForEach-Object { [int]$_ }) }
        $im = Get-W11JsonVal $presetData 'image'
        if ($im -and -not $bp.ContainsKey('Compression')) { $Compression = [string](Get-W11JsonVal $im 'compression' 'Max') }
        if ($im -and -not $bp.ContainsKey('ComponentCleanup')) { $ComponentCleanup = ((Get-W11JsonVal $im 'componentCleanup' $false) -eq $true) }
        $un = Get-W11JsonVal $presetData 'unattend'
        if ($un -and -not $bp.ContainsKey('Autounattend')) { $Autounattend = ((Get-W11JsonVal $un 'enabled' $true) -eq $true) }
        if ($un -and -not $bp.ContainsKey('UnattendOptions')) { $UnattendOptions = Get-W11PresetUnattend $presetData }
        $upd = Get-W11JsonVal $presetData 'updates'
        if ($upd -and (Get-W11JsonVal $upd 'enabled' $false) -eq $true) {
            if (-not $bp.ContainsKey('UpdatesPath') -and [string](Get-W11JsonVal $upd 'folder' '')) { $UpdatesPath = [string](Get-W11JsonVal $upd 'folder' '') }
            if (-not $bp.ContainsKey('UpdateBootWim')) { $UpdateBootWim = ((Get-W11JsonVal $upd 'bootWim' $false) -eq $true) }
            if (-not $bp.ContainsKey('UpdateWinRE')) { $UpdateWinRE = ((Get-W11JsonVal $upd 'winre' $false) -eq $true) }
            if (-not $bp.ContainsKey('ResetBase')) { $ResetBase = ((Get-W11JsonVal $upd 'resetBase' $false) -eq $true) }
        }
    }
    $customUnattend = [bool]$AutounattendPath
    $uo = Get-W11UnattendDefaults
    if ($UnattendOptions) { foreach ($k in @($UnattendOptions.Keys)) { $uo[$k] = $UnattendOptions[$k] } }
    if ($Autounattend -and -not $customUnattend -and $uo.LocalAccount -and -not (Test-W11LocalAccountName ([string]$uo.UserName))) {
        throw "Invalid local account name / Tên tài khoản không hợp lệ: '$($uo.UserName)'"
    }
    if ($UpdatesPath) {
        $p = Resolve-W11FullPath $UpdatesPath
        if (-not $p -or -not (Test-Path -LiteralPath $p -PathType Container)) { throw "Updates folder not found / Không thấy thư mục bản cập nhật: '$UpdatesPath'" }
        $UpdatesPath = $p
    }
    # every path is cleaned (quotes, spaces, invisible characters) and made absolute with Windows rules;
    # the output folder is only created when missing and never through New-Item on a drive root
    # (New-Item -Force 'D:\' fails with "The path is not of a legal form" on Windows PowerShell 5.1)
    $p = Resolve-W11FullPath $IsoPath
    if (-not $p) { throw "Invalid source ISO path / Đường dẫn ISO nguồn không hợp lệ: '$IsoPath'" }
    $IsoPath = $p
    $p = Resolve-W11FullPath $OutputIso
    if (-not $p -or (Test-W11IsPathRoot $p)) { throw "Invalid output ISO path / Đường dẫn ISO đầu ra không hợp lệ: '$OutputIso'" }
    if (Test-Path -LiteralPath $p -PathType Container) { throw "The output ISO path is a folder, add a file name (e.g. Windows_debloated.iso) / Đường dẫn ISO đầu ra là một thư mục, hãy thêm tên file: '$p'" }
    $OutputIso = $p
    $outDir = Get-W11ParentDir $OutputIso
    if (-not $WorkDir) { $WorkDir = Get-W11DefaultWorkDir $outDir }
    $p = Resolve-W11FullPath $WorkDir
    if (-not $p -or (Test-W11IsPathRoot $p)) { throw "Invalid work folder (a drive root is not allowed, it gets deleted afterwards) / Thư mục tạm không hợp lệ (không dùng gốc ổ đĩa): '$WorkDir'" }
    $WorkDir = $p.TrimEnd('\')
    # a folder with files this tool did not create is never deleted: use the next free name (console) or stop (GUI asked already)
    $wdNote = $null
    $wdState = Get-W11WorkDirState $WorkDir
    if ($wdState -eq 'Foreign') {
        if ($WorkDirConflict -eq 'Fail') { throw "The work folder $WorkDir contains files that were not created by this tool; nothing was deleted. Choose another work folder / Thư mục tạm $WorkDir chứa file không do công cụ tạo ra, không xoá gì cả. Hãy chọn thư mục tạm khác" }
        $alt = Get-W11UniqueWorkDir $WorkDir
        $wdNote = "$WorkDir -> $alt"
        $WorkDir = $alt; $wdState = Get-W11WorkDirState $WorkDir
    }
    New-W11Directory $outDir
    if (-not $LogPath) { $LogPath = Join-W11Path $outDir ('WinDebloat_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss')) }
    $script:W11D.LogPath = $LogPath

    $cfg = Get-W11Config -Path $ConfigPath
    $userApps = $RemoveApps; $userTweaks = $Tweaks
    # provisional profile (final one is chosen once the image build is known)
    $os = $TargetOs
    if ($os -eq 'Auto') { $os = Get-W11OsFromName $IsoPath; if (-not $os) { $os = 'Win11' } }
    $planFor = {
        param($o, [int]$b = 0)
        $script:__prof = Get-W11Profile -Config $cfg -Os $o -Build $b
        $a = $userApps
        if ($null -eq $a -and $presetData) { $a = @(Resolve-W11PresetItems (Get-W11JsonVal $presetData 'apps') @($script:__prof.Apps)) }
        if ($null -eq $a) { $a = @($script:__prof.Apps | Where-Object { $_.Default } | ForEach-Object { $_.Id }) }
        $t = $userTweaks
        if ($null -eq $t -and $presetData) { $t = @(Resolve-W11PresetItems (Get-W11JsonVal $presetData 'tweaks') @($script:__prof.Tweaks)) }
        if ($null -eq $t) { $t = @($script:__prof.Tweaks | Where-Object { $_.Default } | ForEach-Object { $_.Id }) }
        # an explicitly chosen tweak that does not apply to this build is skipped (and logged)
        $script:__skippedTweaks = @($script:__prof.SkippedTweaks | Where-Object { $t -contains $_.Id } | ForEach-Object { $_.Id })
        $t = @($t | Where-Object { $script:__skippedTweaks -notcontains $_ })
        $script:__apps = @($a); $script:__tweakIds = @($t)
        $script:__tweakDefs = @($script:__prof.Tweaks | Where-Object { $t -contains $_.Id })
    }
    & $planFor $os
    $RemoveApps = $script:__apps; $Tweaks = $script:__tweakIds; $tweakDefs = $script:__tweakDefs

    # mount, scratch and temporary images are siblings of the ISO tree, never inside it (checked below)
    $lay = Get-W11WorkLayout -WorkDir $WorkDir -Compression $Compression
    Assert-W11WorkLayout -Layout $lay -OutputIso $OutputIso
    $mountDir = $lay.Mount; $tree = $lay.Tree; $workWim = $lay.WorkWim; $marker = $lay.Marker
    $scratch = $lay.Scratch; $newImage = $lay.NewImage
    $srcIsoLen = Get-W11FileLength $IsoPath
    $iso = $null; $imageMounted = $false; $success = $false; $workDirOwned = $false
    $result = New-W11Obj @{ OutputIso = $OutputIso; Sha256 = $null; LogPath = $LogPath; DryRun = $DryRun; TargetOs = $null; Build = 0; Release = $null }

    Write-W11Log -Level STEP -En "===== WinDebloat Tool $($script:W11D.Version) (Windows 10/11) =====" -Vi '===== Công cụ debloat Windows 10/11 ====='
    Write-W11Log -En "Source ISO: $IsoPath" -Vi 'ISO nguồn'
    Write-W11Log -En "Output ISO: $OutputIso" -Vi 'ISO đầu ra'
    Write-W11Log -En "Work dir  : $WorkDir" -Vi 'Thư mục tạm'
    Write-W11Log -En "Log file  : $LogPath" -Vi 'File log'
    if ($wdNote) { Write-W11Log -Level WARN -En "Work folder has files of something else (not deleted), using a new one: $wdNote" -Vi "Thư mục tạm chứa file khác (không xoá), dùng thư mục mới: $wdNote" }
    Write-W11Log -En "Work dir state: $wdState" -Vi 'Trạng thái thư mục tạm'
    Write-W11Log -En ("Layout    : tree=$tree mount=$mountDir scratch=$scratch image=$newImage")
    Write-W11Log -En ("Compression: {0} (install.{1})" -f $Compression, $lay.Ext) -Vi ('Kiểu nén: ' + $Compression)
    if ($presetData) { Write-W11Log -En "Preset: $(Get-W11LangText (Get-W11JsonVal $presetData 'name') 'en') ($presetFile)" -Vi ('Mẫu cấu hình: ' + (Get-W11LangText (Get-W11JsonVal $presetData 'name') 'vi')) }
    Write-W11Log -En "Data: apps/tweaks from $($cfg.DataSource)"
    if ($DryRun) { Write-W11Log -Level DRY -En 'DRY RUN: nothing will be modified.' -Vi 'CHẠY THỬ: không thay đổi gì.' }

    try {
        Set-W11Progress 1 'Checking prerequisites / Kiểm tra điều kiện'
        if (-not (Test-W11Admin)) { throw 'Administrator rights required / Cần quyền Administrator' }
        if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found / Không thấy ISO: $IsoPath" }
        if ($OutputIso -eq $IsoPath) { throw 'Output ISO must differ from source ISO / ISO đầu ra phải khác ISO nguồn' }
        if ($Autounattend -and $customUnattend -and -not (Test-Path -LiteralPath $AutounattendPath)) { throw "autounattend.xml not found: $AutounattendPath" }
        $updates = @()
        if ($UpdatesPath) {
            Write-W11Log -Level STEP -En "Update packages in $UpdatesPath :" -Vi 'Các gói cập nhật sẽ tích hợp:'
            $updates = @(Get-W11UpdatePackages -Path $UpdatesPath)
            foreach ($u in $updates) { $cmb = ''; if ($u.Combined) { $cmb = ' (SSU+LCU)' }; Write-W11Log -En ('  {0,-6} {1}{2}  {3}' -f $u.Kind, $u.RelativePath, $cmb, (Format-W11Size $u.Size)) }
            if ($updates.Count -eq 0) { Write-W11Log -Level WARN -En '  no .msu / .cab file found - nothing to integrate' -Vi '  không có file .msu / .cab nào - bỏ qua bước cập nhật' }
            if ($ResetBase) { Write-W11Log -Level WARN -En 'ResetBase: integrated updates can no longer be uninstalled from the installed Windows.' -Vi 'ResetBase: các bản cập nhật đã tích hợp sẽ không gỡ được trên Windows sau khi cài.' }
        }
        $installUpdates = @(Select-W11UpdatesFor $updates 'Install')
        $bootUpdates = @(); if ($UpdateBootWim) { $bootUpdates = @(Select-W11UpdatesFor $updates 'Boot') }
        $doWinRe = ($UpdateWinRE -and @(Select-W11UpdatesFor $updates 'WinRE').Count -gt 0)
        $winReCache = @{}

        $free = Get-W11FreeGB -Path $WorkDir
        Write-W11Log -En "Free space on work drive: $free GB (need >= $MinFreeGB GB)" -Vi "Dung lượng trống: $free GB (cần >= $MinFreeGB GB)"
        if ($free -lt $MinFreeGB -and -not $DryRun) { throw "Not enough free space ($free GB < $MinFreeGB GB) / Không đủ dung lượng trống ($free GB < $MinFreeGB GB)" }
        $outRoot = Get-W11PathRoot $OutputIso
        if ($outRoot -and -not $outRoot.StartsWith('\\') -and $outRoot -ne (Get-W11PathRoot $WorkDir)) {
            $ofree = Get-W11FreeGB -Path $outDir
            Write-W11Log -En "Free space on output drive: $ofree GB" -Vi "Dung lượng trống ổ đầu ra: $ofree GB"
            if ($ofree -lt 8 -and -not $DryRun) { throw "Not enough free space for the output ISO ($ofree GB < 8 GB) / Không đủ chỗ cho ISO đầu ra ($ofree GB < 8 GB)" }
        }

        $oscdimg = Find-W11Oscdimg -Hint $OscdimgPath
        if ($oscdimg) { Write-W11Log -En "oscdimg: $oscdimg" }
        elseif ($DryRun) { Write-W11Log -Level WARN -En 'oscdimg.exe not found (needed for a real run).' -Vi 'Chưa có oscdimg.exe (cần khi chạy thật).' }
        else { throw 'oscdimg.exe not found - install the Windows ADK Deployment Tools (https://learn.microsoft.com/windows-hardware/get-started/adk-install) or copy oscdimg.exe into tools\ / Chưa có oscdimg.exe: hãy cài Windows ADK Deployment Tools (https://learn.microsoft.com/windows-hardware/get-started/adk-install) hoặc chép oscdimg.exe vào thư mục tools\' }

        if ($DryRun -and -not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) {
            Write-W11Log -Level DRY -En 'Windows 7: dry run cannot look inside the ISO without extracting it (7-Zip). Plan only.' -Vi 'Win7: chạy thử không xem được bên trong ISO, chỉ in kế hoạch.'
            Write-W11Log -En ('Apps to remove: ' + ($RemoveApps -join ', '))
            Invoke-W11Tweaks -TweakDefs $tweakDefs -DryRun
            if ($installUpdates.Count) { $null = Add-W11UpdatePackages -MountDir $mountDir -Packages $installUpdates -Tag 'install.wim' -DryRun }
            return $result
        }

        # ---- prepare work dir ----
        if ((Get-W11WorkDirState $WorkDir) -eq 'Ours') {
            $how = 'marker'; if (-not (Test-Path -LiteralPath $marker)) { $how = 'no marker, only files this tool creates' }
            Write-W11Log -Level WARN -En "Leftover work folder of an earlier run ($how): cleaning it" -Vi 'Thư mục tạm còn sót từ lần chạy trước: đang dọn'
            Clear-W11WorkDir -WorkDir $WorkDir -MountDir $mountDir -Quiet
        }
        New-W11Directory $WorkDir
        Set-Content -LiteralPath $marker -Value 'w11debloat'   # written first, deleted last
        $workDirOwned = $true
        New-W11Directory $mountDir
        New-W11Directory $scratch

        # ---- open ISO ----
        Set-W11Progress 3 'Opening ISO / Đang mở ISO'
        Write-W11Log -Level STEP -En 'Opening source ISO...' -Vi 'Đang mở ISO nguồn...'
        $iso = Open-W11Iso -IsoPath $IsoPath -ExtractTo $tree
        Write-W11Log -En "ISO root: $($iso.Root)  label: $($iso.Label)  mode: $($iso.Mode)"
        $srcImage = $null
        foreach ($f in @('install.wim', 'install.esd')) { $p = Join-Path $iso.Root "sources\$f"; if (Test-Path -LiteralPath $p) { $srcImage = $p; break } }
        if (-not $srcImage) { throw 'sources\install.wim or install.esd not found - not a Windows install ISO? / Không thấy install.wim/esd' }
        $isEsd = ($srcImage -like '*.esd')
        $srcImgLen = Get-W11FileLength $srcImage
        Write-W11Log -En ('SIZE source ISO: {0} ({1} bytes); source {2}: {3} ({4} bytes)' -f (Format-W11Size $srcIsoLen), $srcIsoLen, (Get-W11PathLeaf $srcImage), (Format-W11Size $srcImgLen), $srcImgLen) -Vi 'Dung lượng nguồn'

        $d = Select-W11Dism -IsoSourcesDir (Join-Path $iso.Root 'sources')
        Write-W11Log -En "DISM: $($d.Path) ($($d.Kind) $($d.Version)), appx provider: $($script:W11D.DismCanAppx)"
        if (-not $script:W11D.DismCanAppx) { Write-W11Log -Level WARN -En 'Apps will be removed with the manual registry/folder method.' -Vi 'App sẽ được gỡ bằng phương pháp registry/thư mục thủ công.' }

        $all = @(Get-W11ImageInfo -ImageFile $srcImage)
        foreach ($e in $all) { Write-W11Log -En ('  [{0}] {1} ({2})' -f $e.Index, $e.Name, $e.EditionId) }
        if ($EditionMode -eq 'HomePro') {
            if (@($all | Where-Object { -not $_.EditionId }).Count -gt 0) {
                # DISM output on a non-English host may use translated labels: take the edition ids from the WIM XML
                try { $all = @(Merge-W11EditionIds -Images $all -XmlInfo @(Get-W11WimXmlInfo -Path $srcImage)) } catch { Write-W11Log -Level WARN -En "Could not read edition ids from the image XML: $($_.Exception.Message)" }
            }
            $selected = @(Select-W11HomeProImages -Images $all)
        }
        elseif ($EditionMode -eq 'Custom') { $selected = @($all | Where-Object { $Indexes -contains $_.Index }) }
        else { $selected = $all }
        if ($selected.Count -eq 0) { throw 'No edition selected / Không có phiên bản nào được chọn' }
        Write-W11Log -Level OK -En ('Editions to keep: ' + (($selected | ForEach-Object { "$($_.Index):$($_.Name)" }) -join ', ')) -Vi 'Phiên bản giữ lại'
        $lang = $selected[0].DefaultLanguage
        $archName = Get-W11ArchName $selected[0].Architecture
        $build = [int]$selected[0].Build
        $detected = Resolve-W11OsFromBuild $build
        if ($detected) { Write-W11Log -Level OK -En "Image build $build = $(Get-W11ReleaseLabel -Build $build)" -Vi "Bản build $build = $(Get-W11ReleaseLabel -Build $build)" }
        else { Write-W11Log -Level WARN -En "Could not read the image build; using profile $(Get-W11OsLabel $os)" -Vi 'Không đọc được build, dùng hồ sơ đã chọn' }
        if ($TargetOs -eq 'Auto') {
            if ($detected) { $os = $detected }
        } elseif ($detected -and $detected -ne $TargetOs) {
            Write-W11Log -Level WARN -En "You chose $(Get-W11OsLabel $TargetOs) but the image is $(Get-W11OsLabel $detected). Continuing with your choice." -Vi "Đã chọn $(Get-W11OsLabel $TargetOs) nhưng image là $(Get-W11OsLabel $detected). Vẫn làm theo lựa chọn thủ công."
        }
        # final plan for this OS and build (MinBuild/MaxBuild filters)
        $planBuild = 0; if ($detected -eq $os) { $planBuild = $build }
        & $planFor $os $planBuild
        $RemoveApps = $script:__apps; $Tweaks = $script:__tweakIds; $tweakDefs = $script:__tweakDefs
        foreach ($sk in @($script:__skippedTweaks)) { Write-W11Log -Level WARN -En "Tweak '$sk' does not apply to build $planBuild - skipped" -Vi "Tinh chỉnh '$sk' không áp dụng cho bản này - bỏ qua" }
        $cfgProtected = $script:__prof.Protected
        $outOfRange = @($script:__prof.SkippedApps | Where-Object { $_.Default } | ForEach-Object { $_.Id })
        $result.TargetOs = $os
        $result.Build = $build
        $result.Release = Get-W11ReleaseLabel -Build $planBuild -Os $os
        Write-W11Log -Level OK -En "Debloat profile: $($result.Release)" -Vi "Hồ sơ debloat: $($result.Release)"
        Write-W11Log -En "Language: $lang, architecture: $archName"
        Write-W11Log -En ('Apps to remove: ' + ($RemoveApps -join ', ')) -Vi 'App sẽ gỡ'
        Write-W11Log -En ('Tweaks: ' + ($Tweaks -join ', ')) -Vi 'Tinh chỉnh registry'

        if ($DryRun) {
            if (-not $isEsd) {
                Write-W11Log -Level DRY -En "Inspecting index $($selected[0].Index) read-only..." -Vi 'Đang xem thử image (chỉ đọc)...'
                try {
                    $null = Invoke-W11Dism ('/Mount-Image /ImageFile:{0} /Index:{1} /MountDir:{2} /ReadOnly' -f (ConvertTo-W11Arg $srcImage), $selected[0].Index, (ConvertTo-W11Arg $mountDir)) -Quiet
                    $imageMounted = $true
                    if ($script:W11D.DismCanAppx) { Remove-W11AppsDism -MountDir $mountDir -Patterns $RemoveApps -Protected $cfgProtected -OutOfRange $outOfRange -DryRun }
                    else { Write-W11Log -Level DRY -En 'Manual app removal mode; listing skipped.' }
                } catch { Write-W11Log -Level WARN -En "Read-only inspection failed: $($_.Exception.Message)" -Vi 'Không xem thử được' }
            } else {
                Write-W11Log -Level DRY -En 'install.esd will be converted to WIM first.' -Vi 'install.esd sẽ được chuyển sang WIM trước.'
            }
            Invoke-W11Tweaks -TweakDefs $tweakDefs -DryRun
            if ($installUpdates.Count) { $null = Add-W11UpdatePackages -MountDir $mountDir -Packages $installUpdates -Tag 'install.wim' -DryRun }
            if ($doWinRe) { Update-W11WinRE -MountDir $mountDir -Layout $lay -Packages $updates -DryRun }
            Update-W11BootWim -Tree $tree -Layout $lay -Packages $bootUpdates -BootTweaks @($tweakDefs | Where-Object { $_.BootWim }) -DryRun
            if ($ComponentCleanup -or $ResetBase) { Write-W11Log -Level DRY -En "Would run /StartComponentCleanup$(if ($ResetBase) { ' /ResetBase' })" -Vi 'Sẽ dọn component store' }
            if ($Autounattend) {
                Write-W11Log -Level DRY -En "Would add autounattend.xml (UILanguage=$lang, arch=$archName, $(Get-W11OsLabel $os))" -Vi 'Sẽ thêm autounattend.xml'
                if (-not $customUnattend) { $null = New-W11UnattendXml -Options $uo -Os $os -Arch $archName -Language $lang }
            }
            Write-W11Log -Level DRY -En "Would build $OutputIso with oscdimg (BIOS+UEFI)." -Vi 'Sẽ tạo ISO bằng oscdimg.'
            Write-W11Log -Level OK -En 'Dry run finished.' -Vi 'Chạy thử xong.'
            $success = $true
            return $result
        }

        # ---- ISO tree ----
        Assert-W11NotCancelled
        if ($iso.Mode -eq 'Mounted') {
            Set-W11Progress 5 'Copying ISO files / Đang chép file ISO'
            Write-W11Log -Level STEP -En 'Copying ISO contents (except install.wim/esd)...' -Vi 'Đang chép nội dung ISO...'
            $rc = (Invoke-W11Process -FilePath (Join-Path $env:windir 'System32\robocopy.exe') -Arguments ('{0} {1} /E /XF install.wim install.esd /R:1 /W:1 /NP /NFL /NDL /NJH /NJS' -f (ConvertTo-W11Arg ($iso.Root + '.')), (ConvertTo-W11Arg $tree)) -Quiet).ExitCode
            if ($rc -ge 8) { throw "robocopy failed (exit $rc)" }
        }
        $null = Invoke-W11Process -FilePath (Join-Path $env:windir 'System32\attrib.exe') -Arguments ('-R {0} /S /D' -f (ConvertTo-W11Arg "$tree\*")) -Quiet
        # from now on use the DISM copy inside the work tree if we were using the ISO's DISM
        if ($d.Kind -eq 'ISO') { $script:W11D.Dism = Join-W11Path $tree 'sources\dism.exe' }

        # ---- working WIM ----
        $targets = @()
        if ($isEsd) {
            $n = 0
            foreach ($e in $selected) {
                $n++
                Assert-W11NotCancelled
                Write-W11Log -Level STEP -En "Converting ESD index $($e.Index) to WIM (slow)..." -Vi 'Đang chuyển ESD sang WIM (chậm)...'
                $null = Invoke-W11Dism (Get-W11ExportArgs -Source $srcImage -Index $e.Index -Destination $workWim -Compression Max -ScratchDir $scratch -CheckIntegrity) -Quiet -ProgressBase (8 + 12 * ($n - 1) / $selected.Count) -ProgressSpan (12 / $selected.Count) -ProgressText "ESD -> WIM: $($e.Name)"
                $targets += (New-W11Obj @{ WorkIndex = $n; Name = $e.Name })
            }
            if ($iso.Mode -eq 'Extracted') { Remove-Item -LiteralPath $srcImage -Force }
        } else {
            Set-W11Progress 10 'Preparing install.wim / Chuẩn bị install.wim'
            if ($iso.Mode -eq 'Extracted') { Move-Item -LiteralPath $srcImage -Destination $workWim }
            else { Write-W11Log -Level STEP -En 'Copying install.wim...' -Vi 'Đang chép install.wim...'; Copy-Item -LiteralPath $srcImage -Destination $workWim }
            (Get-Item -LiteralPath $workWim).IsReadOnly = $false
            $targets = @($selected | ForEach-Object { New-W11Obj @{ WorkIndex = $_.Index; Name = $_.Name } })
        }
        Close-W11Iso -Iso $iso -IsoPath $IsoPath; $iso = $null
        $workLen = Get-W11FileLength $workWim
        Write-W11Log -En ('SIZE work WIM before servicing: {0}' -f (Format-W11Size $workLen))

        # ---- service each edition ----
        $i = 0
        foreach ($t in $targets) {
            $i++
            $base = 20 + 55 * ($i - 1) / $targets.Count
            $span = 55 / $targets.Count
            $tag = "[$i/$($targets.Count)]"
            Assert-W11NotCancelled
            Write-W11Log -Level STEP -En "$tag Mounting $($t.Name) (index $($t.WorkIndex))..." -Vi "Đang mount $($t.Name)..."
            $null = Invoke-W11Dism ('/Mount-Image /ImageFile:{0} /Index:{1} /MountDir:{2}' -f (ConvertTo-W11Arg $workWim), $t.WorkIndex, (ConvertTo-W11Arg $mountDir)) -Quiet -ProgressBase $base -ProgressSpan ($span * 0.2) -ProgressText "$tag Mount"
            $imageMounted = $true
            $kept = Join-W11Path $outDir ('kept_index{0}.txt' -f $t.WorkIndex)
            if ($installUpdates.Count) {
                Write-W11Log -En "  Integrating $($installUpdates.Count) update package(s)..." -Vi "  Đang tích hợp $($installUpdates.Count) gói cập nhật..."
                $ur = Add-W11UpdatePackages -MountDir $mountDir -Packages $installUpdates -ScratchDir $scratch -Tag $tag -ProgressBase ($base + $span * 0.2) -ProgressSpan ($span * 0.3)
                Write-W11Log -Level OK -En "  updates: $($ur.Added) added, $($ur.Skipped) not applicable, $($ur.Failed) failed" -Vi "  cập nhật: $($ur.Added) đã thêm, $($ur.Skipped) không áp dụng, $($ur.Failed) lỗi"
            }
            if ($doWinRe) { Update-W11WinRE -MountDir $mountDir -Layout $lay -Packages $updates -Cache $winReCache -Cleanup:($ComponentCleanup -or $ResetBase) }
            Set-W11Progress ($base + $span * 0.5) "$tag Removing apps / Gỡ app"
            $hives = @(Get-W11TweakHives $tweakDefs)
            if ($script:W11D.DismCanAppx) {
                Remove-W11AppsDism -MountDir $mountDir -Patterns $RemoveApps -Protected $cfgProtected -OutOfRange $outOfRange -KeptListPath $kept
                Mount-W11Hives -MountDir $mountDir -Hives $hives
                try { Invoke-W11Tweaks -TweakDefs $tweakDefs } finally { Dismount-W11Hives }
            } else {
                Mount-W11Hives -MountDir $mountDir -Hives $hives
                try {
                    Remove-W11AppsManual -MountDir $mountDir -Patterns $RemoveApps -Protected $cfgProtected -KeptListPath $kept
                    Invoke-W11Tweaks -TweakDefs $tweakDefs
                } finally { Dismount-W11Hives }
            }
            Assert-W11NotCancelled
            if ($ComponentCleanup -or $ResetBase) {
                Invoke-W11ComponentCleanup -MountDir $mountDir -ScratchDir $scratch -ResetBase:$ResetBase -Tag $tag -ProgressBase ($base + $span * 0.6) -ProgressSpan ($span * 0.2)
            }
            Write-W11Log -En '  Committing image...' -Vi '  Đang lưu image...'
            $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Commit' -f (ConvertTo-W11Arg $mountDir)) -Quiet -ProgressBase ($base + $span * 0.8) -ProgressSpan ($span * 0.2) -ProgressText "$tag Commit"
            $imageMounted = $false
            $l = Get-W11FileLength $workWim
            Write-W11Log -En ('  SIZE work WIM after commit: {0} (+{1})' -f (Format-W11Size $l), (Format-W11Size ($l - $workLen)))
            $workLen = $l
        }

        # ---- export / recompress ----
        # Always a NEW image file next to the tree: every kept edition is exported into it (files shared by
        # editions are stored once, everything is recompressed, the space left by /Commit is dropped), then it
        # replaces every install.* in the tree.
        Assert-W11WorkLayout -Layout $lay -OutputIso $OutputIso
        if (Test-Path -LiteralPath $newImage) { Remove-Item -LiteralPath $newImage -Force }
        $i = 0; $newLen = [int64]0
        foreach ($t in $targets) {
            $i++
            Assert-W11NotCancelled
            Write-W11Log -Level STEP -En "Exporting/recompressing $($t.Name) ($Compression)..." -Vi "Đang nén lại $($t.Name)..."
            $null = Invoke-W11Dism (Get-W11ExportArgs -Source $workWim -Index $t.WorkIndex -Destination $newImage -Compression $Compression -ScratchDir $scratch) -Quiet -ProgressBase (75 + 12 * ($i - 1) / $targets.Count) -ProgressSpan (12 / $targets.Count) -ProgressText "Export $($t.Name)"
            $l = Get-W11FileLength $newImage
            Write-W11Log -En ('  SIZE new image: {0} (+{1})' -f (Format-W11Size $l), (Format-W11Size ($l - $newLen)))
            $newLen = $l
        }
        Remove-Item -LiteralPath $workWim -Force
        $srcDir = Join-W11Path $tree 'sources'
        foreach ($f in @(Get-ChildItem -LiteralPath $srcDir -Force | Where-Object { -not $_.PSIsContainer -and $_.Name -match '^install.*\.(wim|esd|swm)$' })) {
            Write-W11Log -En "  Removing old $($f.Name) from the ISO tree" -Vi "  Xoá $($f.Name) cũ khỏi cây ISO"
            Remove-Item -LiteralPath $f.FullName -Force
        }
        $finalImage = Join-W11Path $srcDir ('install.' + $lay.Ext)
        if ($SplitWimMB -gt 0 -and $lay.Ext -eq 'wim' -and $newLen -ge 4GB) {
            Write-W11Log -Level STEP -En "install.wim is over 4 GB: splitting into install*.swm ($SplitWimMB MB parts) for FAT32 USB..." -Vi 'install.wim lớn hơn 4 GB: đang chia thành install*.swm cho USB FAT32...'
            $finalImage = Join-W11Path $srcDir 'install.swm'
            $null = Invoke-W11Dism (Get-W11SplitArgs -ImageFile $newImage -SwmFile $finalImage -SizeMB $SplitWimMB) -Quiet
            Remove-Item -LiteralPath $newImage -Force
        } else {
            Move-Item -LiteralPath $newImage -Destination $finalImage
            if ($lay.Ext -eq 'wim' -and $newLen -ge 4GB) { Write-W11Log -Level WARN -En 'install.wim is over 4 GB: fine for the ISO / Rufus (NTFS), but a FAT32 USB needs the split option.' -Vi 'install.wim lớn hơn 4 GB: dùng ISO/Rufus (NTFS) vẫn được, USB FAT32 thì cần chia file.' }
        }
        Write-W11Log -En ('SIZE source image: {0} -> new image: {1} ({2} editions, {3})' -f (Format-W11Size $srcImgLen), (Format-W11Size $newLen), $targets.Count, $Compression) -Vi 'Dung lượng image'
        if ($newLen -gt $srcImgLen + 500MB) {
            Write-W11Log -Level WARN -En ('The new image is {0} larger than the source one. Each serviced edition stores its own changed files; keep fewer editions (Home + Pro) or use ESD compression.' -f (Format-W11Size ($newLen - $srcImgLen))) -Vi 'Image mới lớn hơn image gốc: mỗi phiên bản đã sửa lưu riêng phần thay đổi; hãy giữ ít phiên bản hơn (Home + Pro) hoặc chọn nén ESD.'
        }

        # ---- boot.wim: setup tweaks (LabConfig) and SSU + LCU ----
        Update-W11BootWim -Tree $tree -Layout $lay -Packages $bootUpdates -BootTweaks @($tweakDefs | Where-Object { $_.BootWim })

        # ---- autounattend ----
        if ($Autounattend) {
            Write-W11Log -Level STEP -En 'Adding autounattend.xml to ISO root...' -Vi 'Thêm autounattend.xml vào gốc ISO...'
            if ($customUnattend) { Write-W11Autounattend -Template $AutounattendPath -Destination (Join-W11Path $tree 'autounattend.xml') -Language $lang -Arch $archName -Os $os }
            else {
                $opt = @{}; foreach ($k in @($uo.Keys)) { $opt[$k] = $uo[$k] }
                $opt.FirstLogonApps = @($RemoveApps)
                Write-W11UnattendFiles -Tree $tree -Options $opt -Os $os -Arch $archName -Language $lang -Protected $cfgProtected
            }
        }

        # ---- build ISO ----
        Assert-W11NotCancelled
        Write-W11Log -Level STEP -En 'Building bootable ISO with oscdimg...' -Vi 'Đang tạo ISO khởi động bằng oscdimg...'
        if (Test-Path -LiteralPath $OutputIso) { Remove-Item -LiteralPath $OutputIso -Force }
        Assert-W11WorkLayout -Layout $lay -OutputIso $OutputIso
        foreach ($r in @(Clear-W11TreeTemp -Tree $tree -KeepImage $finalImage)) { Write-W11Log -En "  Removed temp file from the ISO tree: $r" -Vi '  Đã xoá file tạm khỏi cây ISO' }
        $treeLen = [int64]0; foreach ($f in (Get-W11TreeFiles $tree)) { $treeLen += $f.Length }
        Write-W11Log -En ('SIZE ISO tree: {0}' -f (Format-W11Size $treeLen)) -Vi 'Dung lượng cây ISO'
        $etfs = Join-W11Path $tree 'boot\etfsboot.com'
        $efisys = Join-W11Path $tree 'efi\microsoft\boot\efisys.bin'
        if (-not (Test-Path -LiteralPath $efisys)) { throw "UEFI boot file missing: $efisys" }
        $label = ((Get-W11IsoLabel -IsoPath $IsoPath) -replace '[^A-Za-z0-9_]', '_').Trim('_')
        if (-not $label) { $label = 'WIN11_DEBLOAT' }
        if ($label.Length -gt 32) { $label = $label.Substring(0, 32) }
        if (Test-Path -LiteralPath $etfs) {
            $boot = '-bootdata:2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfs, $efisys
        } else {
            Write-W11Log -Level WARN -En 'No etfsboot.com (ARM64 media?) - building UEFI-only ISO.' -Vi 'Không có etfsboot.com - chỉ tạo ISO UEFI.'
            $boot = '-bootdata:1#pEF,e,b"{0}"' -f $efisys
        }
        $argLine = '-m -o -u2 -udfver102 -l{0} {1} {2} {3}' -f $label, $boot, (ConvertTo-W11Arg $tree), (ConvertTo-W11Arg $OutputIso)
        Write-W11Log -En "oscdimg $argLine"
        $res = Invoke-W11Process -FilePath $oscdimg -Arguments $argLine -Quiet -MergeStdErr -ProgressBase 88 -ProgressSpan 8 -ProgressText 'Building ISO / Đang tạo ISO'
        foreach ($l in ($res.Lines | Select-Object -Last 10)) { Write-W11Log -En "    $l" }
        if ($res.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $OutputIso)) { throw "oscdimg failed (exit $($res.ExitCode))" }

        # ---- hash ----
        Set-W11Progress 96 'SHA256...'
        Write-W11Log -Level STEP -En 'Computing SHA256...' -Vi 'Đang tính SHA256...'
        $hash = Get-W11Sha256 -Path $OutputIso
        ('{0} *{1}' -f $hash.ToLower(), (Split-Path -Leaf $OutputIso)) | Set-Content -LiteralPath "$OutputIso.sha256" -Encoding ASCII
        $result.Sha256 = $hash
        $outLen = Get-W11FileLength $OutputIso
        Write-W11Log -En ('SIZE output ISO: {0} ({1} bytes), source ISO: {2} ({3} bytes)' -f (Format-W11Size $outLen), $outLen, (Format-W11Size $srcIsoLen), $srcIsoLen) -Vi 'Dung lượng ISO'
        if ($outLen -gt $srcIsoLen + 500MB) {
            Write-W11Log -Level WARN -En ('Output ISO is {0} larger than the source ISO. Largest files in the ISO tree:' -f (Format-W11Size ($outLen - $srcIsoLen))) -Vi 'ISO đầu ra lớn hơn ISO nguồn quá 500 MB. Các file lớn nhất trong cây ISO:'
            Write-W11LargestFiles -Dir $tree -Top 10
        }
        Write-W11Log -Level OK -En ('DONE: {0} ({1:N2} GB)' -f $OutputIso, ($outLen / 1GB)) -Vi 'HOÀN TẤT'
        Write-W11Log -Level OK -En "SHA256: $hash"
        Set-W11Progress 100 'Done / Xong'
        $success = $true
        return $result
    } catch [System.OperationCanceledException] {
        Write-W11Log -Level WARN -En 'Cancelled. Cleaning up...' -Vi 'Đã huỷ. Đang dọn dẹp...'
        throw
    } catch {
        Write-W11Log -Level ERROR -En "FAILED: $($_.Exception.Message)" -Vi 'THẤT BẠI'
        throw
    } finally {
        Dismount-W11Hives
        if ($imageMounted) {
            Write-W11Log -En 'Discarding mounted image...' -Vi 'Huỷ image đang mount...'
            $r = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Discard' -f (ConvertTo-W11Arg $mountDir)) -Quiet -NoThrow
            if ($r.ExitCode -ne 0) { Write-W11Log -Level WARN -En 'Unmount failed - run: dism /Cleanup-Mountpoints' -Vi 'Không unmount được, hãy chạy dism /Cleanup-Mountpoints' }
        }
        Close-W11Iso -Iso $iso -IsoPath $IsoPath
        # finished, failed or cancelled: the work folder is always cleaned (unless -KeepWorkDir)
        if ($workDirOwned -and -not $KeepWorkDir) {
            if (-not $success) { Write-W11Log -Level WARN -En 'Run did not finish: cleaning up the work folder (mounted image discarded, nothing kept)' -Vi 'Chưa chạy xong: đang dọn thư mục tạm (huỷ image đang mount, không giữ lại gì)' }
            try { Clear-W11WorkDir -WorkDir $WorkDir -MountDir $mountDir -Quiet }
            catch { Write-W11Log -Level WARN -En "Work folder not fully deleted, delete it by hand: $($_.Exception.Message)" -Vi "Chưa xoá hết thư mục tạm, hãy xoá bằng tay: $WorkDir" }
        } elseif ($workDirOwned) { Write-W11Log -En "Work folder kept (-KeepWorkDir): $WorkDir" -Vi 'Giữ lại thư mục tạm' }
    }
}
#endregion

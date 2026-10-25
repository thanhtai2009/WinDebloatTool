<#
    WinDebloat Tool - official Windows 10 / 11 ISO download from microsoft.com (PowerShell 2.0+ compatible).
    Talks only to Microsoft endpoints, doing what https://www.microsoft.com/software-download/windows11
    (and /windows11arm64, /windows10ISO) does in a browser:
      1. whitelist a random session id (vlscppe.microsoft.com/tags + ov-df.microsoft.com)
      2. software-download-connector/api/getskuinformationbyproductedition  -> languages (SKUs)
      3. software-download-connector/api/GetProductDownloadLinksBySku         -> signed ISO URL (~24 h)
    The flow is documented by the community (e.g. pbatard/Fido, GPLv3); this is an independent
    implementation and contains no Fido code.
    The ISO itself is downloaded with aria2c.exe (separate GPLv2 program, bundled unmodified in
    tools\aria2, started as a process) when available, else with the built-in single-stream downloader.
    SPDX-License-Identifier: MIT
#>

$script:MsDl = @{
    OrgId      = 'y6jn8c31'
    ProfileId  = '606624d44113'
    InstanceId = '560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175'
    Locale     = 'en-US'
    UserAgent  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0'
    # One entry per official download page. Fallback = product edition id used if the page cannot be parsed
    # (verified 2026-10-24: windows11 -> 3813, windows11arm64 -> 3816, windows10ISO -> 2618).
    # DownloadType in Microsoft's answer: 0 = x86 (32-bit), 1 = x64, 2 = arm64.
    Products   = @(
        @{ Os = 'Win11'; Archs = @('x64');        Page = 'https://www.microsoft.com/en-us/software-download/windows11';      Fallback = '3813' }
        @{ Os = 'Win11'; Archs = @('arm64');      Page = 'https://www.microsoft.com/en-us/software-download/windows11arm64'; Fallback = '3816' }
        @{ Os = 'Win10'; Archs = @('x64', 'x86'); Page = 'https://www.microsoft.com/en-us/software-download/windows10ISO';   Fallback = '2618' }
    )
    Pages      = @{
        Win11 = 'https://www.microsoft.com/en-us/software-download/windows11'
        Win11arm64 = 'https://www.microsoft.com/en-us/software-download/windows11arm64'
        Win10 = 'https://www.microsoft.com/en-us/software-download/windows10ISO'
        x64   = 'https://www.microsoft.com/en-us/software-download/windows11'
        arm64 = 'https://www.microsoft.com/en-us/software-download/windows11arm64'
    }
    DownloadTypes = @{ x86 = 0; x64 = 1; arm64 = 2 }
    # Every release Microsoft's download API serves (edition ids from pbatard/Fido history).
    # Verified 2026-10-25: these returned languages AND a download link (Sentinel rejects were intermittent
    # and passed on retry). Offered = $false marks a release "local ISO only": 2360 (22H2 original) gets a
    # link but its ISO answers HTTP 400 at the CDN (teammate probe, 2 sessions, 2026-10-25).
    Catalog = @(
        @{ Os = 'Win11'; Name = '26H2';    Build = '26300.9457';  Date = '2026-09'; Ids = @{ x64 = '3813'; arm64 = '3816' }; Offered = $true }
        @{ Os = 'Win11'; Name = '25H2 v2'; Build = '26200.8037';  Date = '2026-03'; Ids = @{ x64 = '3321'; arm64 = '3324' }; Offered = $true }
        @{ Os = 'Win11'; Name = '25H2';    Build = '26200.6584';  Date = '2025-10'; Ids = @{ x64 = '3262'; arm64 = '3265' }; Offered = $true }
        @{ Os = 'Win11'; Name = '24H2';    Build = '26100.1742';  Date = '2024-10'; Ids = @{ x64 = '3113'; arm64 = '3131' }; Offered = $true }
        @{ Os = 'Win11'; Name = '23H2 v2'; Build = '22631.2861';  Date = '2023-12'; Ids = @{ x64 = '2935' }; Offered = $true }
        @{ Os = 'Win11'; Name = '23H2';    Build = '22631.2428';  Date = '2023-10'; Ids = @{ x64 = '2860' }; Offered = $true }
        @{ Os = 'Win11'; Name = '22H2 v2'; Build = '22621.1702';  Date = '2023-05'; Ids = @{ x64 = '2616' }; Offered = $true }
        @{ Os = 'Win11'; Name = '22H2 v1'; Build = '22621.525';   Date = '2022-10'; Ids = @{ x64 = '2370' }; Offered = $true }
        @{ Os = 'Win11'; Name = '22H2';    Build = '22621.382';   Date = '2022-09'; Ids = @{ x64 = '2360' }; Offered = $false; Why = 'CDN answers HTTP 400 for this ISO (2026-10-25) / máy chủ tải trả lỗi HTTP 400' }
        @{ Os = 'Win11'; Name = '21H2 v1'; Build = '22000.318';   Date = '2021-11'; Ids = @{ x64 = '2093' }; Offered = $true }
        @{ Os = 'Win11'; Name = '21H2';    Build = '22000.194';   Date = '2021-10'; Ids = @{ x64 = '2069' }; Offered = $true }
        @{ Os = 'Win10'; Name = '22H2 v1'; Build = '19045.2965';  Date = '2023-05'; Ids = @{ x64 = '2618'; x86 = '2618' }; Offered = $true }
        @{ Os = 'Win10'; Name = '22H2';    Build = '19045.2006';  Date = '2022-10'; Ids = @{ x64 = '2377'; x86 = '2377' }; Offered = $true }
        @{ Os = 'Win10'; Name = '21H2';    Build = '19044.1288';  Date = '2021-11'; Ids = @{ x64 = '2084'; x86 = '2084' }; Offered = $true }
        @{ Os = 'Win10'; Name = '21H1';    Build = '19043.985';   Date = '2021-05'; Ids = @{ x64 = '2033'; x86 = '2033' }; Offered = $true }
        @{ Os = 'Win10'; Name = '20H2 v2'; Build = '19042.631';   Date = '2020-12'; Ids = @{ x64 = '1882'; x86 = '1882' }; Offered = $true }
        @{ Os = 'Win10'; Name = '20H2';    Build = '19042.508';   Date = '2020-10'; Ids = @{ x64 = '1807'; x86 = '1807' }; Offered = $true }
        @{ Os = 'Win10'; Name = '2004';    Build = '19041.264';   Date = '2020-05'; Ids = @{ x64 = '1626'; x86 = '1626' }; Offered = $true }
        @{ Os = 'Win10'; Name = '1909';    Build = '18363.418';   Date = '2019-11'; Ids = @{ x64 = '1429'; x86 = '1429' }; Offered = $true }
        @{ Os = 'Win10'; Name = '1903 v2'; Build = '18362.356';   Date = '2019-09'; Ids = @{ x64 = '1384'; x86 = '1384' }; Offered = $true }
        @{ Os = 'Win10'; Name = '1903';    Build = '18362.30';    Date = '2019-05'; Ids = @{ x64 = '1214'; x86 = '1214' }; Offered = $true }
        @{ Os = 'Win10'; Name = '1809 v2'; Build = '17763.379';   Date = '2019-03'; Ids = @{ x64 = '1203'; x86 = '1203' }; Offered = $true }
        @{ Os = 'Win10'; Name = '1809';    Build = '17763.107';   Date = '2018-10'; Ids = @{ x64 = '1060'; x86 = '1060' }; Offered = $true }
        @{ Os = 'Win10'; Name = '1803';    Build = '17134.1';     Date = '2018-04'; Ids = @{ x64 = '651';  x86 = '651' };  Offered = $true }
        @{ Os = 'Win10'; Name = '1709';    Build = '16299.15';    Date = '2017-09'; Ids = @{ x64 = '484';  x86 = '484' };  Offered = $true }
        @{ Os = 'Win10'; Name = '1703';    Build = '15063.0';     Date = '2017-03'; Ids = @{ x64 = '361';  x86 = '361' };  Offered = $true }
        @{ Os = 'Win10'; Name = '1607';    Build = '14393.0';     Date = '2016-07'; Ids = @{ x64 = '244';  x86 = '244' };  Offered = $true }
        @{ Os = 'Win10'; Name = '1511';    Build = '10586.164';   Date = '2016-04'; Ids = @{ x64 = '178';  x86 = '178' };  Offered = $true }
        @{ Os = 'Win10'; Name = '1507';    Build = '10240.16384'; Date = '2015-07'; Ids = @{ x64 = '79';   x86 = '79' };   Offered = $true }
    )
    Releases = @{ '19044' = '21H2'; '19045' = '22H2'; '22000' = '21H2'; '22621' = '22H2'; '22631' = '23H2'; '26100' = '24H2'; '26200' = '25H2'; '26300' = '26H2' }
    RetryDelaySec = 2          # between SKU-list attempts (Microsoft sometimes needs a second try)
    SessionTimeoutMs = 10000   # vlscppe / ov-df: best effort, keep short
    SessionState = @{}         # session id -> @{ Tags = $bool; OvDf = $bool; Note = text }
    TimeoutMs = 30000   # per request; a blocked host (hosts file / DNS filter / firewall) must fail fast, not hang the list
    # Shown before / without the live list (version + architecture only; languages need Microsoft's answer)
    Static = @(
        @{ Os = 'Win11'; Arch = 'x64';   EditionId = '3813'; Release = 'Windows 11 (latest)';  Page = 'https://www.microsoft.com/en-us/software-download/windows11' }
        @{ Os = 'Win11'; Arch = 'arm64'; EditionId = '3816'; Release = 'Windows 11 (latest)';  Page = 'https://www.microsoft.com/en-us/software-download/windows11arm64' }
        @{ Os = 'Win10'; Arch = 'x64';   EditionId = '2618'; Release = 'Windows 10 22H2';      Page = 'https://www.microsoft.com/en-us/software-download/windows10ISO' }
        @{ Os = 'Win10'; Arch = 'x86';   EditionId = '2618'; Release = 'Windows 10 22H2';      Page = 'https://www.microsoft.com/en-us/software-download/windows10ISO' }
    )
}

function Initialize-MsDl {
    if (-not (Enable-W11Tls12)) {
        throw 'TLS 1.2 is not available in this .NET/PowerShell. Win7: install KB3140245, .NET 4.5.2+ (or KB3154518) and WMF 5.1 / Chưa có TLS 1.2, Win7 cần KB3140245 + .NET 4.5.2+ và WMF 5.1'
    }
    if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
        try { Add-Type -AssemblyName System.Web.Extensions } catch { [void][Reflection.Assembly]::LoadWithPartialName('System.Web.Extensions') }
    }
    if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
        throw 'JSON support (System.Web.Extensions, .NET 3.5 SP1+) is missing / Thiếu System.Web.Extensions (.NET 3.5 SP1 trở lên)'
    }
}

function ConvertFrom-MsJson {
    # JavaScriptSerializer works on .NET 3.5 (PS 2.0) and 4.x; returns Dictionary / object[]
    param([string]$Json)
    $t = ''; if ($Json) { $t = $Json.Trim() }
    if (-not $t.StartsWith('{') -and -not $t.StartsWith('[')) {
        $snip = $t; if ($snip.Length -gt 160) { $snip = $snip.Substring(0, 160) + '...' }
        throw "Microsoft answered with something that is not JSON (blocked page / proxy / captive portal?): $snip / Microsoft trả về dữ liệu lạ (bị chặn, proxy?)"
    }
    $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = 67108864
    return $ser.DeserializeObject($t)
}

function Get-MsVal {
    # Safe key lookup on JavaScriptSerializer dictionaries (missing key -> $null)
    param($Object, [string]$Key)
    if ($null -ne $Object -and $Object -is [Collections.IDictionary] -and $Object.ContainsKey($Key)) { return $Object[$Key] }
    return $null
}

function Get-MsCount {
    # Element count of a JSON value; $null (missing key) counts as 0. (@($null).Count is 1.)
    param($Value)
    if ($null -eq $Value) { return 0 }
    return @($Value).Count
}

function Invoke-MsDlRequest {
    # HttpWebRequest instead of WebClient: WebClient has no timeout (default 100 s per request, so a
    # blocked host made "Load list" look dead for minutes). Errors name the host so the log is useful.
    param([Parameter(Mandatory = $true)][string]$Uri, [string]$Referer, [int]$TimeoutMs = 0)
    if ($TimeoutMs -le 0) { $TimeoutMs = $script:MsDl.TimeoutMs }
    $req = [Net.HttpWebRequest][Net.WebRequest]::Create($Uri)
    $req.UserAgent = $script:MsDl.UserAgent
    $req.Accept = '*/*'
    $req.Headers.Add('Accept-Language', 'en-US,en;q=0.9')
    if ($Referer) { $req.Referer = $Referer }
    $req.Timeout = $TimeoutMs; $req.ReadWriteTimeout = $TimeoutMs
    $req.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $resp = $null
    try {
        try { $resp = $req.GetResponse() }
        catch [Net.WebException] {
            $we = $_.Exception
            $code = ''; if ($we.Response) { $code = " HTTP $([int]$we.Response.StatusCode)" }
            throw "$($req.RequestUri.Host): $($we.Status)$code - $($we.Message)"
        }
        $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        try { return $sr.ReadToEnd() } finally { $sr.Close() }
    } finally { if ($resp) { $resp.Close() } }
}

function Get-MsUnixMs {
    $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
    return [long]([DateTime]::UtcNow - $epoch).TotalMilliseconds
}

function New-MsDlSession {
    <# Registers a random session id the way the official page does. Both steps are BEST EFFORT:
       verified live 2026-10-24: the language list (getskuinformationbyproductedition) works without any
       registration; the download link needs the ov-df step (vlscppe alone -> "SentinelReject").
       Hosts files / DNS filters / ad blockers often block these hosts ("remote name could not be resolved"),
       so a failure here is logged and remembered, never fatal. #>
    $sid = [guid]::NewGuid().ToString()
    $st = @{ Tags = $false; OvDf = $false; Note = '' }
    $to = $script:MsDl.SessionTimeoutMs
    try {
        $null = Invoke-MsDlRequest -Uri ('https://vlscppe.microsoft.com/tags?org_id={0}&session_id={1}' -f $script:MsDl.OrgId, $sid) -TimeoutMs $to
        $st.Tags = $true
    } catch {
        $st.Note += "vlscppe.microsoft.com: $($_.Exception.Message.TrimEnd('.')). "
        Write-W11Log -Level WARN -En "Session step 1 (vlscppe.microsoft.com) failed, continuing: $($_.Exception.Message)" -Vi 'Không kết nối được vlscppe.microsoft.com (thường do DNS / chặn quảng cáo / file hosts). Vẫn tiếp tục.'
    }
    try {
        $js = Invoke-MsDlRequest -Uri ('https://ov-df.microsoft.com/mdt.js?instanceId={0}&PageId=si&session_id={1}' -f $script:MsDl.InstanceId, $sid) -TimeoutMs $to
        $w = $null; $rticks = $null
        if ($js -match '[?&]w=([A-F0-9]+)') { $w = $Matches[1] }
        if ($js -match 'rticks\=\"\+?(\d+)') { $rticks = $Matches[1] }
        if (-not ($w -and $rticks)) { throw 'mdt.js answer not understood (w/rticks missing)' }
        $null = Invoke-MsDlRequest -Uri ('https://ov-df.microsoft.com/?session_id={0}&CustomerId={1}&PageId=si&w={2}&mdt={3}&rticks={4}' -f $sid, $script:MsDl.InstanceId, $w, (Get-MsUnixMs), $rticks) -TimeoutMs $to
        $st.OvDf = $true
    } catch {
        $st.Note += "ov-df.microsoft.com: $($_.Exception.Message.TrimEnd('.')). "
        Write-W11Log -Level WARN -En "Session step 2 (ov-df.microsoft.com) failed, continuing: $($_.Exception.Message)" -Vi 'Không kết nối được ov-df.microsoft.com. Danh sách vẫn lấy được, nhưng Microsoft có thể từ chối link tải.'
    }
    $script:MsDl.SessionState[$sid] = $st
    return $sid
}

function Get-MsSessionState([string]$SessionId) {
    if ($SessionId -and $script:MsDl.SessionState.ContainsKey($SessionId)) { return $script:MsDl.SessionState[$SessionId] }
    return $null
}

function Get-MsBlockedHint {
    <# Explanation shown when Microsoft rejects a request (715-123130 / SentinelReject). $State = session state. #>
    param($State)
    $en = 'Microsoft rejected the request. Usual causes: VPN/proxy, region, too many attempts'
    $vi = 'Microsoft từ chối yêu cầu. Nguyên nhân thường gặp: đang bật VPN/proxy, vùng bị hạn chế, thử quá nhiều lần'
    if ($State -and (-not $State.OvDf -or -not $State.Tags)) {
        $en = 'Microsoft rejected the request because this PC cannot reach vlscppe.microsoft.com / ov-df.microsoft.com (blocked by DNS, ad blocker, hosts file or the ISP). ' + $State.Note
        $vi = 'Microsoft từ chối vì máy không truy cập được vlscppe.microsoft.com / ov-df.microsoft.com (bị chặn bởi DNS, trình chặn quảng cáo, file hosts hoặc nhà mạng)'
    }
    return ($en + "`nFix: use DNS 1.1.1.1 or 8.8.8.8 (or unblock those two hosts), turn off VPN, wait a while and retry - or use 'Open Microsoft page' and download in the browser." +
        "`n`n" + $vi + ".`nCách xử lý: đổi DNS sang 1.1.1.1 hoặc 8.8.8.8 (hoặc bỏ chặn hai tên miền trên), tắt VPN, đợi một lúc rồi thử lại; hoặc bấm 'Mở trang Microsoft' để tải bằng trình duyệt.")
}

function Get-MsDlPageInfo {
    # Edition ids + published SHA256 table from the official page.
    param([string]$Url, [string]$Fallback, [string]$Label = 'Windows')
    $editions = @(); $hashes = @{}
    try {
        $html = Invoke-MsDlRequest -Uri $Url
        foreach ($m in [regex]::Matches($html, '<option value="(\d{3,6})"[^>]*>([^<]+)</option>')) {
            $editions += (New-Object PSObject -Property @{ Id = $m.Groups[1].Value; Name = $m.Groups[2].Value.Trim() })
        }
        foreach ($m in [regex]::Matches($html, '<td>([^<]{2,60})</td>\s*<td>([0-9A-Fa-f]{64})</td>')) {
            $hashes[$m.Groups[1].Value.Trim()] = $m.Groups[2].Value.ToUpper()
        }
    } catch { Write-W11Log -Level WARN -En "Could not read $Url ($($_.Exception.Message)); using known edition id $Fallback" -Vi 'Không đọc được trang Microsoft, dùng mã phiên bản có sẵn' }
    if ($editions.Count -eq 0 -and $Fallback) { $editions = @(New-Object PSObject -Property @{ Id = $Fallback; Name = $Label }) }
    return (New-Object PSObject -Property @{ Editions = $editions; Hashes = $hashes })
}

function Get-MsSkuList {
    <# Languages (SKUs) of one product edition, with a fresh session. Retries (Microsoft sometimes answers
       empty / Sentinel on the first try). Returns Skus (Id, Language, LocalizedLanguage), Display, SessionId, SessionState. #>
    param([Parameter(Mandatory = $true)][string]$EditionId, [string]$Referer)
    $lastMsg = 'no SKUs returned'
    for ($round = 0; $round -lt 2; $round++) {
        $sid = New-MsDlSession   # one session per edition: Microsoft only honours the last SKU list of a session
        $u = 'https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile={0}&productEditionId={1}&SKU=undefined&friendlyFileName=undefined&Locale={2}&sessionID={3}' -f $script:MsDl.ProfileId, $EditionId, $script:MsDl.Locale, $sid
        $resp = $null
        for ($try = 0; $try -lt 3; $try++) {
            $resp = ConvertFrom-MsJson (Invoke-MsDlRequest -Uri $u -Referer $Referer)
            if ((Get-MsCount (Get-MsVal $resp 'Skus')) -gt 0) { break }
            if ($try -lt 2 -and $script:MsDl.RetryDelaySec -gt 0) { Start-Sleep -Seconds $script:MsDl.RetryDelaySec }
        }
        $skuList = @(); if ((Get-MsCount (Get-MsVal $resp 'Skus')) -gt 0) { $skuList = @(Get-MsVal $resp 'Skus') }
        if ($skuList.Count -gt 0) {
            $skus = @()
            foreach ($sk in $skuList) { $skus += (New-Object PSObject -Property @{ Id = [string](Get-MsVal $sk 'Id'); Language = [string](Get-MsVal $sk 'Language'); LocalizedLanguage = [string](Get-MsVal $sk 'LocalizedLanguage') }) }
            return (New-Object PSObject -Property @{ Skus = $skus; Display = [string](Get-MsVal $skuList[0] 'ProductDisplayName'); SessionId = $sid; SessionState = (Get-MsSessionState $sid) })
        }
        $errs = @(); if ((Get-MsCount (Get-MsVal $resp 'Errors')) -gt 0) { $errs = @(Get-MsVal $resp 'Errors') }
        $sentinel = $false
        if ($errs.Count -gt 0) {
            $lastMsg = [string](Get-MsVal $errs[0] 'Value')
            $etype = [string](Get-MsVal $errs[0] 'Type')
            $blocked = ($etype -eq '9' -or $lastMsg -match '715-123130')
            $sentinel = (-not $blocked -and ($etype -eq '8' -or $lastMsg -match '[Ss]entinel'))
            if ($sentinel -or $blocked) { $lastMsg = "$lastMsg`n" + (Get-MsBlockedHint (Get-MsSessionState $sid)) }
        }
        if (-not $sentinel) { break }   # "no languages" or an IP/region block (Type 9) will not change on retry
        if ($script:MsDl.RetryDelaySec -gt 0) { Start-Sleep -Seconds ($script:MsDl.RetryDelaySec * 2) }
    }
    throw "Microsoft refused the language list ($lastMsg)"
}

function Get-MsReleaseCatalog {
    <# Every known release x architecture as entries (no network). Languages are filled in later
       (Update-MsEntryLanguages / Set-MsEntryLanguages). Available = $false: Microsoft no longer serves it. #>
    param([string[]]$Os = @('Win11', 'Win10'))
    $out = @()
    foreach ($r in $script:MsDl.Catalog) {
        if ($Os -notcontains $r.Os) { continue }
        $osName = 'Windows 11'; if ($r.Os -eq 'Win10') { $osName = 'Windows 10' }
        $label = "$osName $($r.Name) (Build $($r.Build), $($r.Date))"
        foreach ($a in @('x64', 'arm64', 'x86')) {
            if (-not $r.Ids.ContainsKey($a)) { continue }
            $pg = $script:MsDl.Pages[$r.Os]; if ($a -eq 'arm64') { $pg = $script:MsDl.Pages['Win11arm64'] }
            $out += (New-Object PSObject -Property @{
                    Os = $r.Os; Arch = $a; DownloadType = $script:MsDl.DownloadTypes[$a]; EditionId = $r.Ids[$a]; EditionName = $label
                    Release = $label; ReleaseName = $r.Name; Build = [int]($r.Build.Split('.')[0]); BuildFull = $r.Build
                    SessionId = $null; SessionState = $null; PageUrl = $pg; Hashes = @{}; Skus = @(); Static = $true
                    Available = [bool]$r.Offered; Note = $(if ($r.Offered) { '' } else { "Microsoft no longer offers this - use a local ISO / Microsoft không còn cung cấp bản này, hãy dùng file ISO có sẵn ($($r.Why))" })
                })
        }
    }
    return $out
}

function Update-MsEntryLanguages {
    <# Language list for $Entry's edition plus the published SHA256 table when the official page still
       lists that edition. Never throws. Result: EditionId, Ok, Skus, SessionId, SessionState, Hashes, Display, Error, NotOffered. #>
    param([Parameter(Mandatory = $true)]$Entry)
    $res = New-Object PSObject -Property @{ EditionId = $Entry.EditionId; Ok = $false; Skus = @(); SessionId = $null; SessionState = $null; Hashes = @{}; Display = ''; Error = $null; NotOffered = $false }
    Set-W11Progress -Percent 10 -Status "Microsoft: $($Entry.Release) [$($Entry.Arch)]..."
    Write-W11Log -En "Asking Microsoft for the languages of $($Entry.Release) [$($Entry.Arch)] (edition $($Entry.EditionId))" -Vi 'Đang hỏi Microsoft danh sách ngôn ngữ'
    try {
        Initialize-MsDl
        $info = Get-MsDlPageInfo -Url $Entry.PageUrl -Label $Entry.Release
        if (@($info.Editions | Where-Object { $_.Id -eq $Entry.EditionId }).Count -gt 0) { $res.Hashes = $info.Hashes }
        $sk = Get-MsSkuList -EditionId $Entry.EditionId -Referer $Entry.PageUrl
        $res.Skus = $sk.Skus; $res.SessionId = $sk.SessionId; $res.SessionState = $sk.SessionState; $res.Display = $sk.Display; $res.Ok = $true
        $h = 'no SHA256 table for this release on the page (older release; the hash is logged for manual comparison)'
        if ($res.Hashes.Count -gt 0) { $h = "$($res.Hashes.Count) published SHA256 values" }
        Write-W11Log -Level OK -En "$($Entry.Release): $(@($res.Skus).Count) languages, $h" -Vi "Đã lấy $(@($res.Skus).Count) ngôn ngữ"
    } catch {
        $res.Error = $_.Exception.Message
        # a withdrawn edition answers without languages and without a Sentinel error
        if ($res.Error -match 'no SKUs returned' -or $res.Error -match '(?i)\binvalid\b|not (be )?found') { $res.NotOffered = $true }
        Write-W11Log -Level WARN -En "$($Entry.Release) [$($Entry.Arch)]: $($res.Error)" -Vi 'Không lấy được danh sách ngôn ngữ'
    }
    Set-W11Progress -Percent 100 -Status ''
    return $res
}

function Set-MsEntryLanguages {
    # Applies an Update-MsEntryLanguages result to every catalog entry of that edition (Win10 x64/x86 share one)
    param([object[]]$Catalog, $Result)
    foreach ($e in @($Catalog)) {
        if ($e.EditionId -ne $Result.EditionId) { continue }
        if ($Result.Ok) {
            $e.Skus = $Result.Skus; $e.SessionId = $Result.SessionId; $e.SessionState = $Result.SessionState
            $e.Hashes = $Result.Hashes; $e.Static = $false; $e.Available = $true; $e.Note = ''
        } elseif ($Result.NotOffered) {
            $e.Available = $false; $e.Note = 'Microsoft no longer offers this - use a local ISO / Microsoft không còn cung cấp bản này, hãy dùng file ISO có sẵn'
        } else { $e.Note = $Result.Error }
    }
}

function Get-MsWinCatalog {
    <# One entry per (OS, edition, architecture) Microsoft currently offers:
       Os, Arch, DownloadType, EditionId, EditionName, Release, SessionId, PageUrl, Hashes, Skus (Id, Language, LocalizedLanguage) #>
    param([string[]]$Os = @('Win11', 'Win10'))
    Initialize-MsDl
    $out = @(); $errors = @()
    $prods = @($script:MsDl.Products | Where-Object { $Os -contains $_.Os })
    $n = 0
    foreach ($prod in $prods) {
        $n++
        $osName = 'Windows 11'; if ($prod.Os -eq 'Win10') { $osName = 'Windows 10' }
        $what = "$osName $($prod.Archs -join '/')"
        Set-W11Progress -Percent ([int](100 * ($n - 1) / $prods.Count)) -Status "Microsoft: $what ($n/$($prods.Count))..."
        Write-W11Log -En "Querying Microsoft: $what ($($prod.Page))" -Vi "Đang hỏi Microsoft: $what"
        $info = Get-MsDlPageInfo -Url $prod.Page -Fallback $prod.Fallback -Label $osName
        foreach ($ed in $info.Editions) {
            try {
                $sk = Get-MsSkuList -EditionId $ed.Id -Referer $prod.Page
                $sid = $sk.SessionId
                $skus = @($sk.Skus)
                $release = Get-MsReleaseLabel -Display $sk.Display -OsName $osName
                Write-W11Log -Level OK -En "$what`: $release, $($skus.Count) languages" -Vi "$what`: $($skus.Count) ngôn ngữ"
                foreach ($a in $prod.Archs) {
                    $out += (New-Object PSObject -Property @{
                            Os = $prod.Os; Arch = $a; DownloadType = $script:MsDl.DownloadTypes[$a]
                            EditionId = $ed.Id; EditionName = $ed.Name; Release = $release; SessionId = $sid
                            PageUrl = $prod.Page; Hashes = $info.Hashes; Skus = $skus; Static = $false
                            SessionState = (Get-MsSessionState $sid)
                        })
                }
            } catch {
                $errors += "$what (edition $($ed.Id)): $($_.Exception.Message)"
                Write-W11Log -Level WARN -En "$what (edition $($ed.Id)) failed: $($_.Exception.Message)" -Vi "Không lấy được $what"
            }
        }
    }
    Set-W11Progress -Percent 100 -Status 'Microsoft list done / Đã xong danh sách'
    if ($out.Count -eq 0) { throw ('Could not get the list from Microsoft: ' + ($errors -join ' ; ')) }
    return $out
}

function Get-MsStaticCatalog {
    # Version/architecture choices known without the network. Skus empty -> GUI offers the official page.
    $out = @()
    foreach ($s in $script:MsDl.Static) {
        $out += (New-Object PSObject -Property @{
                Os = $s.Os; Arch = $s.Arch; DownloadType = $script:MsDl.DownloadTypes[$s.Arch]; EditionId = $s.EditionId
                EditionName = $s.Release; Release = $s.Release; SessionId = $null; PageUrl = $s.Page; Hashes = @{}; Skus = @(); Static = $true
            })
    }
    return $out
}

function Get-MsCatalogForGui {
    <# Never throws. Live entries from Microsoft plus static entries for every OS/arch Microsoft did not
       return, so the version list is never empty. Returns Entries, Live (count), Error (text or $null). #>
    param([string[]]$Os = @('Win11', 'Win10'))
    $live = @(); $err = $null
    try { $live = @(Get-MsWinCatalog -Os $Os) }
    catch {
        $err = $_.Exception.Message
        Write-W11Log -Level ERROR -En "Microsoft list failed: $err" -Vi 'Không lấy được danh sách từ Microsoft'
    }
    $all = @() + $live
    foreach ($s in @(Get-MsStaticCatalog)) {
        if ($Os -notcontains $s.Os) { continue }
        $have = @($live | Where-Object { $_.Os -eq $s.Os -and $_.Arch -eq $s.Arch })
        if ($have.Count -eq 0) { $all += $s }
    }
    return (New-Object PSObject -Property @{ Entries = $all; Live = $live.Count; Error = $err })
}

function Get-MsWin11Catalog { return (Get-MsWinCatalog -Os @('Win11')) }   # backwards compatibility

function Get-MsReleaseLabel {
    # "Windows 11 Client - Build 26300.9457" -> "Windows 11 26H2 (Build 26300.9457)"; "Windows 10 22H2 v1" stays readable
    param([string]$Display, [string]$OsName)
    if ($Display -match '(?:Build )?\b(\d{5})(\.\d+)?\b') {
        $rel = $script:MsDl.Releases[$Matches[1]]
        if ($rel) { return "$OsName $rel (Build $($Matches[1])$($Matches[2]))" }
        return "$OsName (Build $($Matches[1])$($Matches[2]))"
    }
    if ($Display) {
        $d = ($Display.Trim() -replace '_', ' ')
        if ($d -notmatch '(?i)windows\s*1[01]') { $d = "$OsName $d" }
        return $d
    }
    return $OsName
}

function Get-MsIsoDownloadLink {
    <# Signed ISO URL for one language. On a Sentinel / 715-123130 rejection (often intermittent rate
       limiting) it retries up to twice with a fresh session (new SKU list + link), then explains. #>
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)][string]$SkuId)
    Initialize-MsDl
    $sid = $Entry.SessionId; $state = $Entry.SessionState
    $lastErr = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        if ($attempt -gt 0) {
            if (-not $Entry.EditionId) { break }
            if ($script:MsDl.RetryDelaySec -gt 0) { Start-Sleep -Seconds ($script:MsDl.RetryDelaySec * 2) }
            Write-W11Log -Level WARN -En "Microsoft rejected the link request - retrying with a new session ($attempt/2)" -Vi 'Microsoft từ chối, đang thử lại với phiên mới'
            $sk = Get-MsSkuList -EditionId $Entry.EditionId -Referer $Entry.PageUrl
            $sid = $sk.SessionId; $state = $sk.SessionState
            if (@($sk.Skus | Where-Object { $_.Id -eq $SkuId }).Count -eq 0) { break }   # SKU ids are fixed per edition + language
        }
        $u = 'https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile={0}&productEditionId=undefined&SKU={1}&friendlyFileName=undefined&Locale={2}&sessionID={3}' -f $script:MsDl.ProfileId, $SkuId, $script:MsDl.Locale, $sid
        $resp = ConvertFrom-MsJson (Invoke-MsDlRequest -Uri $u -Referer $Entry.PageUrl)
        $errs = @(); if ((Get-MsCount (Get-MsVal $resp 'Errors')) -gt 0) { $errs = @(Get-MsVal $resp 'Errors') }
        if ($errs.Count -gt 0) {
            $e = $errs[0]
            $etype = [string](Get-MsVal $e 'Type'); $eval = [string](Get-MsVal $e 'Value')
            if (@('8', '9') -contains $etype -or $eval -match '715-123130|[Ss]entinel') {
                if (-not $state) { $state = Get-MsSessionState $sid }
                $lastErr = "Microsoft: $eval (session $sid)`n" + (Get-MsBlockedHint $state)
                if ($etype -eq '9' -or $eval -match '715-123130') { break }   # IP / region / VPN block: a new session does not help
                continue                                                      # SentinelReject is often random: new session
            }
            throw ('Microsoft refused the download link: ' + $eval)
        }
        $want = [int]$Entry.DownloadType
        $uri = $null
        $opts = @(); if ((Get-MsCount (Get-MsVal $resp 'ProductDownloadOptions')) -gt 0) { $opts = @(Get-MsVal $resp 'ProductDownloadOptions') }
        foreach ($o in $opts) { if ([int](Get-MsVal $o 'DownloadType') -eq $want) { $uri = [string](Get-MsVal $o 'Uri'); break } }
        if (-not $uri -and $opts.Count -gt 0) { $uri = [string](Get-MsVal $opts[0] 'Uri') }
        if (-not $uri) { throw 'No ISO link in Microsoft response' }
        return $uri
    }
    if ($lastErr) { throw $lastErr }
    throw 'Microsoft refused the download link'
}

function Find-MsPublishedHash {
    # Labels look like "English 64-bit", "English  64-bit" (arm64 page) or "Arabic 32-bit" (Windows 10 page).
    param([hashtable]$Hashes, [string]$Language, [string]$LocalizedLanguage, [string]$Arch = 'x64')
    if (-not $Hashes -or $Hashes.Count -eq 0) { return $null }
    $targets = @()
    foreach ($x in @($Language, $LocalizedLanguage)) { if ($x) { $targets += (($x -replace '[()]', '' -replace '\s+', ' ').Trim().ToLower()) } }
    foreach ($k in $Hashes.Keys) {
        $kind = 'any'
        if ($k -match '(?i)32-bit|x86') { $kind = 'x86' } elseif ($k -match '(?i)64-bit|arm64|x64') { $kind = '64' }
        if ($Arch -eq 'x86' -and $kind -eq '64') { continue }
        if ($Arch -ne 'x86' -and $kind -eq 'x86') { continue }
        $label = (($k -replace '(?i)\s*(64-bit|32-bit|arm64|x64|x86)\s*$', '') -replace '[()]', '' -replace '\s+', ' ').Trim().ToLower()
        if ($targets -contains $label) { return $Hashes[$k] }
    }
    return $null
}

function Save-MsFile {
    <# Streams a URL to disk with progress, resume (.partial) and cancel support. #>
    param([Parameter(Mandatory = $true)][string]$Uri, [Parameter(Mandatory = $true)][string]$Destination, [hashtable]$Sync)
    Initialize-MsDl
    $partial = "$Destination.partial"
    $have = [long]0
    if (Test-Path -LiteralPath $partial) { $have = (Get-Item -LiteralPath $partial).Length }
    $req = [Net.WebRequest]::Create($Uri)
    $req.UserAgent = $script:MsDl.UserAgent
    $req.Timeout = 60000; $req.ReadWriteTimeout = 120000
    if ($have -gt 0) {
        try { $req.AddRange([long]$have) }                       # .NET 4+
        catch { try { $req.AddRange([int]$have) } catch { $have = [long]0 } }   # .NET 2/3.5 (< 2 GB only)
    }
    $resp = $req.GetResponse()
    try {
        $append = ($have -gt 0 -and [int]$resp.StatusCode -eq 206)
        if (-not $append) { $have = [long]0 }
        $total = $have + $resp.ContentLength
        if ($append) { $mode = [IO.FileMode]::Append } else { $mode = [IO.FileMode]::Create }
        $fs = New-Object IO.FileStream $partial, $mode, ([IO.FileAccess]::Write)
        $stream = $resp.GetResponseStream()
        try {
            $buf = New-Object byte[] 1048576
            $sw = [Diagnostics.Stopwatch]::StartNew(); $lastBytes = $have; $lastT = [long]0
            while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
                $fs.Write($buf, 0, $n); $have += $n
                if ($Sync -and $Sync.Cancel) { throw (New-Object System.OperationCanceledException 'Download cancelled / Đã huỷ tải') }
                if ($sw.ElapsedMilliseconds - $lastT -ge 500) {
                    $dt = ($sw.ElapsedMilliseconds - $lastT) / 1000.0
                    $speed = ($have - $lastBytes) / [Math]::Max(0.001, $dt)
                    $lastBytes = $have; $lastT = $sw.ElapsedMilliseconds
                    $pct = 0; if ($total -gt 0) { $pct = 100.0 * $have / $total }
                    $st = '{0:N2} / {1:N2} GB  ({2:N1}%)  {3:N1} MB/s' -f ($have / 1GB), ($total / 1GB), $pct, ($speed / 1MB)
                    if ($Sync) { $Sync.Percent = $pct; $Sync.Status = $st } else { Write-Progress -Activity 'Downloading ISO / Đang tải ISO' -Status $st -PercentComplete ([int]$pct) }
                }
            }
        } finally { $fs.Close(); $stream.Close() }
    } finally { $resp.Close() }
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force }
    Move-Item -LiteralPath $partial -Destination $Destination
    return $Destination
}

#region ---------- aria2 (multi-connection download) ----------
$script:MsAria2Defaults = @{
    UseAria2 = $true; Aria2Connections = 16; Aria2Split = 16; Aria2MinSplitSize = '1M'; Aria2FileAllocation = 'none'
    Aria2MaxTries = 5; Aria2RetryWait = 5; Aria2Timeout = 60
}
$script:MsAria2ExitText = @{
    1 = 'unknown error / lỗi không xác định'; 2 = 'timeout / hết thời gian chờ'; 3 = 'file not found (404) / không tìm thấy file'
    5 = 'too slow / tốc độ quá chậm'; 6 = 'network problem / lỗi mạng'; 7 = 'unfinished downloads / chưa tải xong'
    8 = 'server does not support resume / máy chủ không hỗ trợ tải tiếp'; 9 = 'not enough disk space / không đủ dung lượng ổ đĩa'
    13 = 'file already exists / file đã tồn tại'; 16 = 'could not create file / không tạo được file'; 17 = 'I/O error / lỗi đọc ghi'
    19 = 'name resolution failed (DNS) / lỗi phân giải tên miền'; 22 = 'bad HTTP response, e.g. 403 / link hết hạn hoặc bị từ chối (vd. 403)'
    23 = 'too many redirects / chuyển hướng quá nhiều'; 24 = 'HTTP authorization failed / bị từ chối truy cập'; 28 = 'bad option / tham số sai'
}

function Get-MsOsIs64 {
    if ([IntPtr]::Size -eq 8) { return $true }
    if ($env:PROCESSOR_ARCHITEW6432) { return $true }
    return ($env:PROCESSOR_ARCHITECTURE -match '64')
}

function Find-MsAria2 {
    <# aria2c.exe search order: explicit hint, tools\aria2c.exe (user override / newer build), next to the
       script, the bundled tools\aria2\<x64|x86>\aria2c.exe for this Windows, then PATH. #>
    param([string]$Hint)
    $root = $script:W11Root
    $c = @()
    if ($Hint) { $c += $Hint }
    if ($root) {
        $c += (Join-Path (Join-Path $root 'tools') 'aria2c.exe')
        $c += (Join-Path $root 'aria2c.exe')
        $bundled = Join-Path (Join-Path $root 'tools') 'aria2'
        $useX64 = Get-MsOsIs64
        # Windows 10 on ARM cannot run x64 programs (Windows 11 on ARM can); it runs x86 ones
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $useX64 = ([Environment]::OSVersion.Version.Build -ge 22000) }
        if ($useX64) { $c += (Join-Path (Join-Path $bundled 'x64') 'aria2c.exe') }
        $c += (Join-Path (Join-Path $bundled 'x86') 'aria2c.exe')
    }
    foreach ($x in $c) { if ($x -and (Test-Path -LiteralPath $x -PathType Leaf)) { return $x } }
    foreach ($n in @('aria2c.exe', 'aria2c')) {
        $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Definition }
    }
    return $null
}

function Get-MsAria2Options {
    # Defaults merged with the Download section of DebloatConfig.psd1 (and/or an explicit hashtable)
    param($Config, [hashtable]$Override)
    $o = @{}
    foreach ($k in $script:MsAria2Defaults.Keys) { $o[$k] = $script:MsAria2Defaults[$k] }
    if ($Config -and $Config.Download) { foreach ($k in $Config.Download.Keys) { $o[$k] = $Config.Download[$k] } }
    if ($Override) { foreach ($k in $Override.Keys) { $o[$k] = $Override[$k] } }
    foreach ($k in @('Aria2Connections', 'Aria2Split')) { $v = [int]$o[$k]; if ($v -lt 1) { $v = 1 }; if ($v -gt 16) { $v = 16 }; $o[$k] = $v }
    if (@('none', 'prealloc', 'falloc', 'trunc') -notcontains [string]$o.Aria2FileAllocation) { $o.Aria2FileAllocation = 'none' }
    if ([string]$o.Aria2MinSplitSize -notmatch '^\d+[KM]?$') { $o.Aria2MinSplitSize = '1M' }
    return $o
}

function ConvertTo-MsCmdArg([string]$a) {
    # Quote one argument for the Windows command line (MSVCRT rules: double trailing backslashes)
    if ($a -notmatch '[\s"&|<>^]' -and $a.Length -gt 0) { return $a }
    $t = $a -replace '(\\*)"', '$1$1\"'
    $t = $t -replace '(\\+)$', '$1$1'
    return '"' + $t + '"'
}

function Get-MsAria2Arguments {
    <# Argument list for one ISO download. Sizes are printed raw (--human-readable=false) for parsing. #>
    param([Parameter(Mandatory = $true)][string]$Uri, [Parameter(Mandatory = $true)][string]$Destination,
        [hashtable]$Options, [string]$LogFile, [int]$ParentPid = 0)
    $o = Get-MsAria2Options -Override $Options
    $dir = Split-Path -Parent $Destination
    $name = Split-Path -Leaf $Destination
    $a = @(
        "--dir=$dir", "--out=$name",
        "--max-connection-per-server=$($o.Aria2Connections)", "--split=$($o.Aria2Split)", "--min-split-size=$($o.Aria2MinSplitSize)",
        '--continue=true', '--always-resume=true', '--auto-file-renaming=false', '--allow-overwrite=false',
        "--file-allocation=$($o.Aria2FileAllocation)", '--check-certificate=true',
        "--max-tries=$([int]$o.Aria2MaxTries)", "--retry-wait=$([int]$o.Aria2RetryWait)", "--timeout=$([int]$o.Aria2Timeout)", '--connect-timeout=30',
        '--summary-interval=1', '--console-log-level=warn', '--human-readable=false', '--enable-color=false', '--show-console-readout=true',
        '--remote-time=false', '--enable-rpc=false', '--follow-torrent=false', '--follow-metalink=false',
        "--user-agent=$($script:MsDl.UserAgent)"
    )
    if ($LogFile) { $a += "--log=$LogFile"; $a += '--log-level=notice' }
    if ($ParentPid -gt 0) { $a += "--stop-with-process=$ParentPid" }   # aria2 stops if the tool is killed
    $a += $Uri
    return $a
}

function ConvertFrom-MsAria2Size([string]$v) {
    if ($v -notmatch '^([\d.]+)([KMGT]i)?B$') { return $null }
    $n = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
    switch ($Matches[2]) { 'Ki' { $n *= 1KB } 'Mi' { $n *= 1MB } 'Gi' { $n *= 1GB } 'Ti' { $n *= 1TB } }
    return [long]$n
}

function ConvertFrom-MsAria2Line {
    <# Parses a console readout line, e.g. "[#847d8f 52428800B/6140975104B(0%) CN:16 DL:85983232B ETA:1m10s]"
       (also the human-readable form "52MiB/5.7GiB"). Returns $null for any other line. #>
    param([string]$Line)
    $m = [regex]::Match($Line, '\[#\w+\s+(?<done>[\d.]+(?:[KMGT]i)?B)/(?<total>[\d.]+(?:[KMGT]i)?B)(?:\((?<pct>\d+)%\))?(?:\s+CN:(?<cn>\d+))?(?:\s+SD:\d+)?(?:\s+DL:(?<dl>[\d.]+(?:[KMGT]i)?B))?(?:\s+UL:\S+)?(?:\s+ETA:(?<eta>\w+))?\]')
    if (-not $m.Success) { return $null }
    $done = ConvertFrom-MsAria2Size $m.Groups['done'].Value
    $total = ConvertFrom-MsAria2Size $m.Groups['total'].Value
    $pct = 0.0
    if ($total -gt 0) { $pct = 100.0 * $done / $total } elseif ($m.Groups['pct'].Success) { $pct = [double]$m.Groups['pct'].Value }
    $speed = [long]0; if ($m.Groups['dl'].Success) { $speed = ConvertFrom-MsAria2Size $m.Groups['dl'].Value }
    $cn = 0; if ($m.Groups['cn'].Success) { $cn = [int]$m.Groups['cn'].Value }
    $eta = ''; if ($m.Groups['eta'].Success) { $eta = $m.Groups['eta'].Value }
    return (New-Object PSObject -Property @{ Done = $done; Total = $total; Percent = $pct; Connections = $cn; Speed = $speed; Eta = $eta })
}

function Format-MsAria2Status($p) {
    $s = 'aria2: {0:N2} / {1:N2} GB ({2:N1}%)  {3:N1} MB/s  x{4}' -f ($p.Done / 1GB), ($p.Total / 1GB), $p.Percent, ($p.Speed / 1MB), $p.Connections
    if ($p.Eta) { $s += "  ETA $($p.Eta)" }
    return $s
}

function Start-MsAria2Process {
    # Separate function so the tests can replace the process with a fake one.
    param([string]$Exe, [string]$Arguments)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $false   # aria2 writes its console output to stdout; details go to --log
    $psi.WorkingDirectory = Split-Path -Parent $Exe
    return [Diagnostics.Process]::Start($psi)
}

function Invoke-MsAria2Download {
    <# Runs aria2c and feeds its progress to $Sync (GUI) or Write-Progress. Cancel kills aria2 (the
       .aria2 control file stays, so the next start resumes). Throws on failure with exit code meaning. #>
    param([Parameter(Mandatory = $true)][string]$Exe, [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination, [hashtable]$Options, [hashtable]$Sync)
    $log = "$Destination.aria2.log"
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }
    $argList = Get-MsAria2Arguments -Uri $Uri -Destination $Destination -Options $Options -LogFile $log -ParentPid $PID
    $argText = ($argList | ForEach-Object { ConvertTo-MsCmdArg $_ }) -join ' '
    $shown = $argText -replace '\?[^"\s]*', '?<signed>'
    Write-W11Log -En "aria2: $Exe $shown"
    $p = Start-MsAria2Process -Exe $Exe -Arguments $argText
    $cancelled = $false; $last = $null
    try {
        while ($true) {
            $line = $p.StandardOutput.ReadLine()
            if ($null -eq $line) { break }
            $pr = ConvertFrom-MsAria2Line $line
            if ($pr) {
                $last = $pr
                $st = Format-MsAria2Status $pr
                if ($Sync) { $Sync.Percent = $pr.Percent; $Sync.Status = $st }
                else { Write-Progress -Activity 'Downloading ISO (aria2) / Đang tải ISO' -Status $st -PercentComplete ([int]$pr.Percent) }
            } elseif ($line -match '(?i)\b(error|errorCode|exception)\b') {
                Write-W11Log -Level WARN -En "aria2: $($line.Trim())"
            }
            if ($Sync -and $Sync.Cancel) { $cancelled = $true; break }
        }
    } finally {
        # normal end: stdout closed, give aria2 time to write its results and exit; kill only on cancel / error / hang
        if (-not $cancelled) { try { [void]$p.WaitForExit(30000) } catch { $null = $_ } }
        if (-not $p.HasExited) {
            try { $p.Kill() } catch { $null = $_ }
        }
        try { [void]$p.WaitForExit(15000) } catch { $null = $_ }
    }
    if ($cancelled) { throw (New-Object System.OperationCanceledException 'Download cancelled - aria2 stopped; start the download again to resume / Đã huỷ tải; bấm Tải lại để tải tiếp') }
    $code = [int]$p.ExitCode
    if ($code -ne 0) {
        $why = $script:MsAria2ExitText[$code]; if (-not $why) { $why = 'see aria2 log / xem log aria2' }
        $tail = ''
        if (Test-Path -LiteralPath $log) {
            $errLines = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ -match '\[(ERROR|WARN)\]' } | Select-Object -Last 3)
            if ($errLines.Count -gt 0) { $tail = ' | ' + ($errLines -join ' | ') }
        }
        $ex = New-Object System.Exception ("aria2 failed (exit code $code): $why$tail")
        $ex.Data['Aria2ExitCode'] = $code
        throw $ex
    }
    if ($last) { Write-W11Log -Level OK -En ('aria2 finished: {0:N2} GB' -f ($last.Total / 1GB)) -Vi 'aria2 đã tải xong' }
    return $Destination
}

function Clear-MsAria2Files([string]$Destination) {
    # aria2 writes segments out of order; such a file cannot be resumed by the single-stream downloader
    foreach ($f in @($Destination, "$Destination.aria2")) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
}
#endregion

#region ---------- mirror fallback (massgrave.dev list, opt-in, SHA256 mandatory) ----------
function Get-MsMirrorCandidates {
    <# Mirror entries from DebloatConfig.psd1 (Mirrors) for an OS/arch, best first: same release name,
       then consumer, then business, then LTSC. Entries without a valid SHA256 are never returned. #>
    param($Config, [string]$Os, [string]$Arch, [string]$ReleaseName)
    $out = @()
    foreach ($m in @($Config.Mirrors)) {
        if (-not $m -or [string]$m.Sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or [string]$m.FileName -notmatch '\.iso$') { continue }
        if ($Os -and $m.Os -ne $Os) { continue }
        if ($Arch -and $m.Arch -ne $Arch) { continue }
        $rank = 3
        if ($m.Kind -eq 'consumer') { $rank = 1 } elseif ($m.Kind -eq 'business') { $rank = 2 }
        if ($ReleaseName -and $m.Release -and $ReleaseName -like "$($m.Release)*") { $rank = 0 }
        $out += (New-Object PSObject -Property @{ Rank = $rank; Mirror = $m })
    }
    return @($out | Sort-Object Rank | ForEach-Object { $_.Mirror })
}

function Get-MsUrlHost([string]$Url) {
    try { return ([Uri]$Url).Host } catch { return '' }
}

function Test-MsMirrorFile {
    <# Mandatory check of a file downloaded from a mirror: SHA256 must equal the entry's value (the hash of
       the original Microsoft MSDN file). On mismatch the file is deleted. Nothing is ever executed. #>
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)]$Mirror)
    $res = New-Object PSObject -Property @{ Ok = $false; Hash = ''; Expected = ([string]$Mirror.Sha256).ToUpper(); Deleted = $false; Path = $Path; Error = $null }
    if (-not (Test-W11PathText $Path -Leaf)) { $res.Error = "File not found: $Path"; return $res }
    if ($res.Expected -notmatch '^[0-9A-F]{64}$') { $res.Error = 'Mirror entry has no valid SHA256 - refusing to use it'; return $res }
    Write-W11Log -Level STEP -En "Verifying SHA256 of $Path (mirror $($Mirror.FileName), host $(Get-MsUrlHost $Mirror.Url))" -Vi 'Đang kiểm tra SHA256 của file tải từ mirror'
    $res.Hash = (Get-W11Sha256 -Path $Path).ToUpper()
    if ($res.Hash -eq $res.Expected) {
        $res.Ok = $true
        Write-W11Log -Level OK -En "SHA256 matches the original Microsoft file $($Mirror.FileName): $($res.Hash)" -Vi 'SHA256 khớp với file gốc của Microsoft'
        return $res
    }
    Write-W11Log -Level ERROR -En "SHA256 MISMATCH for $Path : got $($res.Hash), expected $($res.Expected) - deleting the file" -Vi 'SHA256 KHÔNG KHỚP - xoá file'
    try { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop; $res.Deleted = $true } catch { $res.Error = $_.Exception.Message }
    return $res
}
#endregion

function Get-MsIsoFileName([string]$Uri) {
    $m = [regex]::Match($Uri, '/([^/?]+\.iso)(\?|$)')
    if ($m.Success) { return $m.Groups[1].Value }
    return 'Win11_official.iso'
}

function Invoke-MsIsoDownload {
    <# Full download: link -> aria2 (multi-connection) or built-in stream -> SHA256 check against
       Microsoft's published table. aria2 failure (not cancel) falls back to the built-in downloader. #>
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)]$Sku, [Parameter(Mandatory = $true)][string]$Folder,
        [hashtable]$Sync, [hashtable]$Options)
    $opt = Get-MsAria2Options -Override $Options
    Write-W11Log -Level STEP -En "Requesting download link: $($Entry.Release) $($Sku.Language) $($Entry.Arch)" -Vi 'Đang lấy link tải từ Microsoft...'
    $uri = Get-MsIsoDownloadLink -Entry $Entry -SkuId $Sku.Id
    $dest = Join-Path $Folder (Get-MsIsoFileName $uri)
    $aria = $null
    if ($opt.UseAria2) {
        $aria = Find-MsAria2 -Hint ([string]$opt.Aria2Path)
        if (-not $aria) { Write-W11Log -Level WARN -En 'aria2c.exe not found - using the built-in downloader (single connection)' -Vi 'Không tìm thấy aria2c.exe, dùng bộ tải có sẵn (1 luồng)' }
    }
    $done = $false
    if ($aria) {
        # a file started by the built-in downloader is sequential, so aria2 can continue it
        if ((Test-Path -LiteralPath "$dest.partial") -and -not (Test-Path -LiteralPath $dest) -and -not (Test-Path -LiteralPath "$dest.aria2")) {
            Move-Item -LiteralPath "$dest.partial" -Destination $dest
            Write-W11Log -En 'Continuing the earlier partial download with aria2' -Vi 'Tải tiếp phần đã tải dở bằng aria2'
        }
        Write-W11Log -En "Downloading with aria2 ($($opt.Aria2Connections) connections) to $dest" -Vi "Đang tải bằng aria2 ($($opt.Aria2Connections) luồng)"
        try {
            $null = Invoke-MsAria2Download -Exe $aria -Uri $uri -Destination $dest -Options $opt -Sync $Sync
            $done = $true
        } catch [System.OperationCanceledException] {
            throw
        } catch {
            Write-W11Log -Level WARN -En "$($_.Exception.Message) - switching to the built-in downloader" -Vi 'aria2 lỗi, chuyển sang bộ tải có sẵn (1 luồng)'
            if ($Sync -and $Sync.Cancel) { throw (New-Object System.OperationCanceledException 'Download cancelled / Đã huỷ tải') }
            if ((Test-Path -LiteralPath $dest) -and -not (Test-Path -LiteralPath "$dest.aria2") -and -not (Test-Path -LiteralPath "$dest.partial")) {
                # no control file = sequential data from the start (e.g. the moved .partial): keep it for resume
                Move-Item -LiteralPath $dest -Destination "$dest.partial"
            } else { Clear-MsAria2Files $dest }   # multi-segment file without a usable control file cannot be resumed
            try { $uri = Get-MsIsoDownloadLink -Entry $Entry -SkuId $Sku.Id } catch { Write-W11Log -Level WARN -En "Could not get a fresh link, reusing the first one: $($_.Exception.Message)" }
        }
    }
    if (-not $done) {
        Write-W11Log -En "Downloading to $dest" -Vi 'Đang tải về'
        $null = Save-MsFile -Uri $uri -Destination $dest -Sync $Sync
    }
    Write-W11Log -Level STEP -En 'Verifying SHA256...' -Vi 'Đang kiểm tra SHA256...'
    if ($Sync) { $Sync.Status = 'SHA256...' }
    $hash = Get-W11Sha256 -Path $dest
    $expected = Find-MsPublishedHash -Hashes $Entry.Hashes -Language $Sku.Language -LocalizedLanguage $Sku.LocalizedLanguage -Arch $Entry.Arch
    if ($expected) {
        if ($expected -eq $hash) { Write-W11Log -Level OK -En "SHA256 matches Microsoft's published hash: $hash" -Vi 'SHA256 khớp với Microsoft' }
        else { throw "SHA256 MISMATCH! got $hash, Microsoft published $expected. Delete the file and retry / SHA256 KHÔNG KHỚP, hãy xoá file và tải lại" }
    } else {
        Write-W11Log -Level WARN -En "No published hash found for this language; SHA256 = $hash (compare manually on the Microsoft page)" -Vi 'Không tìm thấy hash công bố cho ngôn ngữ này, hãy so thủ công'
    }
    return $dest
}

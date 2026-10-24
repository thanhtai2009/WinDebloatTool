<#
    WinDebloat Tool - official Windows 10 / 11 ISO download from microsoft.com (PowerShell 2.0+ compatible).
    Talks only to Microsoft endpoints, doing what https://www.microsoft.com/software-download/windows11
    (and /windows11arm64, /windows10ISO) does in a browser:
      1. whitelist a random session id (vlscppe.microsoft.com/tags + ov-df.microsoft.com)
      2. software-download-connector/api/getskuinformationbyproductedition  -> languages (SKUs)
      3. software-download-connector/api/GetProductDownloadLinksBySku         -> signed ISO URL (~24 h)
    The flow is documented by the community (e.g. pbatard/Fido, GPLv3); this is an independent
    implementation and contains no Fido code.
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
                $sid = New-MsDlSession   # one session per edition: Microsoft only honours the last SKU list of a session
                $u = 'https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile={0}&productEditionId={1}&SKU=undefined&friendlyFileName=undefined&Locale={2}&sessionID={3}' -f $script:MsDl.ProfileId, $ed.Id, $script:MsDl.Locale, $sid
                $resp = $null
                for ($try = 0; $try -lt 3; $try++) {
                    $resp = ConvertFrom-MsJson (Invoke-MsDlRequest -Uri $u -Referer $prod.Page)
                    if ((Get-MsCount (Get-MsVal $resp 'Skus')) -gt 0) { break }
                    if ($try -lt 2 -and $script:MsDl.RetryDelaySec -gt 0) { Start-Sleep -Seconds $script:MsDl.RetryDelaySec }
                }
                $skuList = @(); if ((Get-MsCount (Get-MsVal $resp 'Skus')) -gt 0) { $skuList = @(Get-MsVal $resp 'Skus') }
                if ($skuList.Count -eq 0) {
                    $msg = 'no SKUs returned'
                    $errs = @(); if ((Get-MsCount (Get-MsVal $resp 'Errors')) -gt 0) { $errs = @(Get-MsVal $resp 'Errors') }
                    if ($errs.Count -gt 0) {
                        $msg = [string](Get-MsVal $errs[0] 'Value')
                        if (@('8', '9') -contains [string](Get-MsVal $errs[0] 'Type') -or $msg -match '715-123130|[Ss]entinel') { $msg = "$msg`n" + (Get-MsBlockedHint (Get-MsSessionState $sid)) }
                    }
                    throw "Microsoft refused the language list ($msg)"
                }
                $display = [string](Get-MsVal $skuList[0] 'ProductDisplayName')
                $release = Get-MsReleaseLabel -Display $display -OsName $osName
                $skus = @()
                Write-W11Log -Level OK -En "$what`: $release, $($skuList.Count) languages" -Vi "$what`: $($skuList.Count) ngôn ngữ"
                foreach ($sk in $skuList) { $skus += (New-Object PSObject -Property @{ Id = [string](Get-MsVal $sk 'Id'); Language = [string](Get-MsVal $sk 'Language'); LocalizedLanguage = [string](Get-MsVal $sk 'LocalizedLanguage') }) }
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
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)][string]$SkuId)
    Initialize-MsDl
    $u = 'https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile={0}&productEditionId=undefined&SKU={1}&friendlyFileName=undefined&Locale={2}&sessionID={3}' -f $script:MsDl.ProfileId, $SkuId, $script:MsDl.Locale, $Entry.SessionId
    $resp = ConvertFrom-MsJson (Invoke-MsDlRequest -Uri $u -Referer $Entry.PageUrl)
    $errs = @(); if ((Get-MsCount (Get-MsVal $resp 'Errors')) -gt 0) { $errs = @(Get-MsVal $resp 'Errors') }
    if ($errs.Count -gt 0) {
        $e = $errs[0]
        $etype = [string](Get-MsVal $e 'Type'); $eval = [string](Get-MsVal $e 'Value')
        if (@('8', '9') -contains $etype -or $eval -match '715-123130|[Ss]entinel') {
            $state = $Entry.SessionState; if (-not $state) { $state = Get-MsSessionState $Entry.SessionId }
            throw ("Microsoft: $eval (session $($Entry.SessionId))`n" + (Get-MsBlockedHint $state))
        }
        throw ('Microsoft refused the download link: ' + (Get-MsVal $e 'Value'))
    }
    $want = [int]$Entry.DownloadType
    $uri = $null
    $opts = @(); if ((Get-MsCount (Get-MsVal $resp 'ProductDownloadOptions')) -gt 0) { $opts = @(Get-MsVal $resp 'ProductDownloadOptions') }
    foreach ($o in $opts) { if ([int](Get-MsVal $o 'DownloadType') -eq $want) { $uri = [string](Get-MsVal $o 'Uri'); break } }
    if (-not $uri -and $opts.Count -gt 0) { $uri = [string](Get-MsVal $opts[0] 'Uri') }
    if (-not $uri) { throw 'No ISO link in Microsoft response' }
    return $uri
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

function Get-MsIsoFileName([string]$Uri) {
    $m = [regex]::Match($Uri, '/([^/?]+\.iso)(\?|$)')
    if ($m.Success) { return $m.Groups[1].Value }
    return 'Win11_official.iso'
}

function Invoke-MsIsoDownload {
    <# Full download: link -> stream -> SHA256 check against Microsoft's published table. #>
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)]$Sku, [Parameter(Mandatory = $true)][string]$Folder, [hashtable]$Sync)
    Write-W11Log -Level STEP -En "Requesting download link: $($Entry.Release) $($Sku.Language) $($Entry.Arch)" -Vi 'Đang lấy link tải từ Microsoft...'
    $uri = Get-MsIsoDownloadLink -Entry $Entry -SkuId $Sku.Id
    $dest = Join-Path $Folder (Get-MsIsoFileName $uri)
    Write-W11Log -En "Downloading to $dest" -Vi 'Đang tải về'
    $null = Save-MsFile -Uri $uri -Destination $dest -Sync $Sync
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

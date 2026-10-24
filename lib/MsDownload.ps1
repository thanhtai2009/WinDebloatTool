<#
    Win11 Debloat Tool - official ISO download from microsoft.com (PowerShell 2.0+ compatible).
    Talks only to Microsoft endpoints, doing what https://www.microsoft.com/software-download/windows11
    does in a browser:
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
    ArchOrder  = @('x64', 'arm64')
    Pages      = @{
        x64   = 'https://www.microsoft.com/en-us/software-download/windows11'
        arm64 = 'https://www.microsoft.com/en-us/software-download/windows11arm64'
    }
    FallbackEditions = @{ x64 = '3813'; arm64 = '3816' }   # used only if the page cannot be parsed
    Releases = @{ '22000' = '21H2'; '22621' = '22H2'; '22631' = '23H2'; '26100' = '24H2'; '26200' = '25H2'; '26300' = '26H2' }
}

function Initialize-MsDl {
    if (-not (Enable-W11Tls12)) {
        throw 'TLS 1.2 is not available in this .NET/PowerShell. Win7: install KB3140245, .NET 4.5.2+ (or KB3154518) and WMF 5.1 / Chưa có TLS 1.2, Win7 cần KB3140245 + .NET 4.5.2+ và WMF 5.1'
    }
    try { Add-Type -AssemblyName System.Web.Extensions } catch { [void][Reflection.Assembly]::LoadWithPartialName('System.Web.Extensions') }
}

function ConvertFrom-MsJson {
    # JavaScriptSerializer works on .NET 3.5 (PS 2.0) and 4.x; returns Dictionary / object[]
    param([string]$Json)
    $ser = New-Object Web.Script.Serialization.JavaScriptSerializer
    $ser.MaxJsonLength = 67108864
    return $ser.DeserializeObject($Json)
}

function Get-MsVal {
    # Safe key lookup on JavaScriptSerializer dictionaries (missing key -> $null)
    param($Object, [string]$Key)
    if ($null -ne $Object -and $Object -is [Collections.IDictionary] -and $Object.ContainsKey($Key)) { return $Object[$Key] }
    return $null
}

function Invoke-MsDlRequest {
    param([Parameter(Mandatory = $true)][string]$Uri, [string]$Referer)
    $wc = New-Object Net.WebClient
    try {
        $wc.Encoding = [Text.Encoding]::UTF8
        $wc.Headers.Add('User-Agent', $script:MsDl.UserAgent)
        $wc.Headers.Add('Accept-Language', 'en-US,en;q=0.9')
        if ($Referer) { $wc.Headers.Add('Referer', $Referer) }
        return $wc.DownloadString($Uri)
    } finally { $wc.Dispose() }
}

function Get-MsUnixMs {
    $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
    return [long]([DateTime]::UtcNow - $epoch).TotalMilliseconds
}

function New-MsDlSession {
    $sid = [guid]::NewGuid().ToString()
    $null = Invoke-MsDlRequest -Uri ('https://vlscppe.microsoft.com/tags?org_id={0}&session_id={1}' -f $script:MsDl.OrgId, $sid)
    try {
        $js = Invoke-MsDlRequest -Uri ('https://ov-df.microsoft.com/mdt.js?instanceId={0}&PageId=si&session_id={1}' -f $script:MsDl.InstanceId, $sid)
        $w = $null; $rticks = $null
        if ($js -match '[?&]w=([A-F0-9]+)') { $w = $Matches[1] }
        if ($js -match 'rticks\=\"\+?(\d+)') { $rticks = $Matches[1] }
        if ($w -and $rticks) {
            $null = Invoke-MsDlRequest -Uri ('https://ov-df.microsoft.com/?session_id={0}&CustomerId={1}&PageId=si&w={2}&mdt={3}&rticks={4}' -f $sid, $script:MsDl.InstanceId, $w, (Get-MsUnixMs), $rticks)
        }
    } catch { $null = $_ }   # best effort; the SKU call tells us whether it worked
    return $sid
}

function Get-MsDlPageInfo {
    # Edition ids + published SHA256 table from the official page.
    param([string]$Url, [string]$Arch)
    $editions = @(); $hashes = @{}
    try {
        $html = Invoke-MsDlRequest -Uri $Url
        foreach ($m in [regex]::Matches($html, '<option value="(\d{3,6})"[^>]*>([^<]+)</option>')) {
            $editions += (New-Object PSObject -Property @{ Id = $m.Groups[1].Value; Name = $m.Groups[2].Value.Trim() })
        }
        foreach ($m in [regex]::Matches($html, '<td>([^<]{2,60})</td>\s*<td>([0-9A-Fa-f]{64})</td>')) {
            $hashes[$m.Groups[1].Value.Trim()] = $m.Groups[2].Value.ToUpper()
        }
    } catch { $null = $_ }
    if ($editions.Count -eq 0) { $editions = @(New-Object PSObject -Property @{ Id = $script:MsDl.FallbackEditions[$Arch]; Name = "Windows 11 ($Arch)" }) }
    return (New-Object PSObject -Property @{ Editions = $editions; Hashes = $hashes })
}

function Get-MsWin11Catalog {
    <# One entry per (architecture, edition) Microsoft currently offers:
       Arch, EditionId, EditionName, Release, SessionId, PageUrl, Hashes, Skus (Id, Language, LocalizedLanguage) #>
    param([string[]]$Arch = @('x64', 'arm64'))
    Initialize-MsDl
    $out = @(); $errors = @()
    foreach ($a in $script:MsDl.ArchOrder) {
        if ($Arch -notcontains $a) { continue }
        $page = $script:MsDl.Pages[$a]
        $info = Get-MsDlPageInfo -Url $page -Arch $a
        foreach ($ed in $info.Editions) {
            try {
                $sid = New-MsDlSession   # one session per edition: Microsoft only honours the last SKU list of a session
                $u = 'https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile={0}&productEditionId={1}&SKU=undefined&friendlyFileName=undefined&Locale={2}&sessionID={3}' -f $script:MsDl.ProfileId, $ed.Id, $script:MsDl.Locale, $sid
                $resp = $null
                for ($try = 0; $try -lt 3; $try++) {
                    $resp = ConvertFrom-MsJson (Invoke-MsDlRequest -Uri $u -Referer $page)
                    if (@(Get-MsVal $resp 'Skus').Count -gt 0) { break }
                    Start-Sleep -Seconds 2
                }
                $skuList = @(Get-MsVal $resp 'Skus')
                if ($skuList.Count -eq 0) {
                    $msg = 'no SKUs returned'
                    $errs = @(Get-MsVal $resp 'Errors')
                    if ($errs.Count -gt 0) { $msg = Get-MsVal $errs[0] 'Value' }
                    throw "Microsoft refused the language list ($msg)"
                }
                $display = [string](Get-MsVal $skuList[0] 'ProductDisplayName')
                $release = $display
                if ($display -match 'Build (\d{5})(\.\d+)?') {
                    $rel = $script:MsDl.Releases[$Matches[1]]
                    if ($rel) { $release = "Windows 11 $rel (Build $($Matches[1])$($Matches[2]))" } else { $release = "Windows 11 (Build $($Matches[1])$($Matches[2]))" }
                }
                $skus = @()
                foreach ($s in $skuList) { $skus += (New-Object PSObject -Property @{ Id = [string](Get-MsVal $s 'Id'); Language = [string](Get-MsVal $s 'Language'); LocalizedLanguage = [string](Get-MsVal $s 'LocalizedLanguage') }) }
                $out += (New-Object PSObject -Property @{
                        Arch = $a; EditionId = $ed.Id; EditionName = $ed.Name; Release = $release; SessionId = $sid
                        PageUrl = $page; Hashes = $info.Hashes; Skus = $skus
                    })
            } catch { $errors += "$a/$($ed.Id): $($_.Exception.Message)" }
        }
    }
    if ($out.Count -eq 0) { throw ('Could not get the list from Microsoft: ' + ($errors -join ' ; ')) }
    foreach ($e in $errors) { Write-W11Log -Level WARN -En $e }
    return $out
}

function Get-MsIsoDownloadLink {
    param([Parameter(Mandatory = $true)]$Entry, [Parameter(Mandatory = $true)][string]$SkuId)
    Initialize-MsDl
    $u = 'https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile={0}&productEditionId=undefined&SKU={1}&friendlyFileName=undefined&Locale={2}&sessionID={3}' -f $script:MsDl.ProfileId, $SkuId, $script:MsDl.Locale, $Entry.SessionId
    $resp = ConvertFrom-MsJson (Invoke-MsDlRequest -Uri $u -Referer $Entry.PageUrl)
    $errs = @(Get-MsVal $resp 'Errors')
    if ($errs.Count -gt 0) {
        $e = $errs[0]
        if ([int](Get-MsVal $e 'Type') -eq 9) { throw "Microsoft blocked this request (message 715-123130: too many requests, VPN or region). Session $($Entry.SessionId). Use 'Open Microsoft page'. / Microsoft chặn yêu cầu, hãy dùng nút mở trang Microsoft." }
        throw ('Microsoft refused the download link: ' + (Get-MsVal $e 'Value'))
    }
    $want = 1; if ($Entry.Arch -eq 'arm64') { $want = 2 }
    $uri = $null
    $opts = @(Get-MsVal $resp 'ProductDownloadOptions')
    foreach ($o in $opts) { if ([int](Get-MsVal $o 'DownloadType') -eq $want) { $uri = [string](Get-MsVal $o 'Uri'); break } }
    if (-not $uri -and $opts.Count -gt 0) { $uri = [string](Get-MsVal $opts[0] 'Uri') }
    if (-not $uri) { throw 'No ISO link in Microsoft response' }
    return $uri
}

function Find-MsPublishedHash {
    param([hashtable]$Hashes, [string]$Language, [string]$LocalizedLanguage)
    if (-not $Hashes -or $Hashes.Count -eq 0) { return $null }
    $targets = @()
    foreach ($x in @($Language, $LocalizedLanguage)) { if ($x) { $targets += (($x -replace '[()]', '' -replace '\s+', ' ').Trim().ToLower()) } }
    foreach ($k in $Hashes.Keys) {
        $label = (($k -replace '(?i)\s*(64-bit|32-bit|arm64|x64)\s*$', '') -replace '[()]', '' -replace '\s+', ' ').Trim().ToLower()
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
    $expected = Find-MsPublishedHash -Hashes $Entry.Hashes -Language $Sku.Language -LocalizedLanguage $Sku.LocalizedLanguage
    if ($expected) {
        if ($expected -eq $hash) { Write-W11Log -Level OK -En "SHA256 matches Microsoft's published hash: $hash" -Vi 'SHA256 khớp với Microsoft' }
        else { throw "SHA256 MISMATCH! got $hash, Microsoft published $expected. Delete the file and retry / SHA256 KHÔNG KHỚP, hãy xoá file và tải lại" }
    } else {
        Write-W11Log -Level WARN -En "No published hash found for this language; SHA256 = $hash (compare manually on the Microsoft page)" -Vi 'Không tìm thấy hash công bố cho ngôn ngữ này, hãy so thủ công'
    }
    return $dest
}

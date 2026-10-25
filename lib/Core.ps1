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
    Version      = '0.3.0'
    LogPath      = $null
    Sync         = $null
    HiveSoftware = 'HKLM\W11D_SOFTWARE'
    HiveDefault  = 'HKLM\W11D_DEFAULT'
    AdkSetupUrl  = 'https://go.microsoft.com/fwlink/?linkid=2289980'   # official current ADK online installer
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
    param([string]$Path)
    if (-not $Path) { $Path = Join-Path $script:W11Root 'config\DebloatConfig.psd1' }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Config not found: $Path" }
    # Import-LocalizedData parses .psd1 in restricted (data-only) language and exists since PS 2.0
    Import-LocalizedData -BaseDirectory (Split-Path -Parent $Path) -FileName ([IO.Path]::GetFileNameWithoutExtension($Path)) -BindingVariable w11cfg
    return $w11cfg
}

function Get-W11FreeGB {
    param([Parameter(Mandatory = $true)][string]$Path)
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
    if ($root -like '\\*') { throw "Network paths are not supported for the work folder / Không hỗ trợ thư mục mạng: $Path" }
    $d = New-Object IO.DriveInfo $root
    return [Math]::Round($d.AvailableFreeSpace / 1GB, 1)
}

function ConvertTo-W11Arg { param([string]$s) return '"' + $s.TrimEnd('\') + '"' }

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

function Find-W11Oscdimg {
    param([string]$Hint)
    $arch = Get-W11HostArch
    $c = @()
    if ($Hint) { $c += $Hint }
    $c += (Join-Path $script:W11Root 'tools\oscdimg.exe')
    $c += (Join-Path $script:W11Root 'tools\Oscdimg\oscdimg.exe')
    foreach ($k in Get-W11KitRoots) {
        foreach ($a in @($arch, 'amd64', 'x86')) { $c += (Join-Path $k "$a\Oscdimg\oscdimg.exe") }
    }
    foreach ($x in $c) { if ($x -and (Test-Path -LiteralPath $x)) { return $x } }
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
        if ($build -ge 10240) { $oscHint = 'Missing: the tool can install "ADK Deployment Tools" from Microsoft for you / Thiếu: tool sẽ đề nghị cài ADK Deployment Tools từ Microsoft' }
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

function Install-W11Oscdimg {
    <# Installs ONLY "Deployment Tools" of the official Windows ADK (contains oscdimg.exe + DISM).
       Windows 10/11 hosts only (the current ADK does not install on 7/8.x). #>
    param([ValidateSet('AdkSetup', 'Winget')][string]$Method = 'AdkSetup')
    if ((Get-W11OsBuild) -lt 10240) { throw 'The current Windows ADK only installs on Windows 10/11. Copy oscdimg.exe into tools\ manually / ADK mới chỉ cài được trên Win10/11' }
    $feature = '/quiet /norestart /ceip off /features OptionId.DeploymentTools'
    if ($Method -eq 'Winget') {
        $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $wg) { throw 'winget not found / Không tìm thấy winget' }
        Write-W11Log -Level STEP -En 'Installing Windows ADK Deployment Tools via winget...' -Vi 'Đang cài ADK Deployment Tools bằng winget...'
        $res = Invoke-W11Process -FilePath $wg.Definition -Arguments ('install --id Microsoft.WindowsADK -e --accept-package-agreements --accept-source-agreements --override "{0}"' -f $feature)
        Write-W11Log -En "winget exit code: $($res.ExitCode)"
    } else {
        if (-not (Enable-W11Tls12)) { throw 'TLS 1.2 not available / Không có TLS 1.2' }
        $exe = Join-Path $env:TEMP 'adksetup.exe'
        Write-W11Log -Level STEP -En "Downloading official ADK installer: $($script:W11D.AdkSetupUrl)" -Vi 'Đang tải bộ cài ADK chính thức...'
        $wc = New-Object Net.WebClient
        try { $wc.DownloadFile($script:W11D.AdkSetupUrl, $exe) } finally { $wc.Dispose() }
        $sig = Get-AuthenticodeSignature -FilePath $exe
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
            throw "adksetup.exe signature check failed ($($sig.Status)) / Chữ ký số không hợp lệ"
        }
        Write-W11Log -Level OK -En 'Signature OK (Microsoft Corporation). Installing Deployment Tools only (several minutes)...' -Vi 'Chữ ký hợp lệ. Đang cài Deployment Tools (vài phút)...'
        $p = Start-Process -FilePath $exe -ArgumentList $feature -Wait -PassThru
        Write-W11Log -En "adksetup exit code: $($p.ExitCode)"
    }
    $found = Find-W11Oscdimg
    if (-not $found) { throw 'oscdimg.exe still not found after ADK install / Vẫn không tìm thấy oscdimg.exe' }
    Write-W11Log -Level OK -En "oscdimg: $found"
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
    $null = New-Item -ItemType Directory -Force -Path $ExtractTo
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
function Mount-W11Hives {
    param([Parameter(Mandatory = $true)][string]$MountDir)
    $sw = Join-Path $MountDir 'Windows\System32\config\SOFTWARE'
    $du = Join-Path $MountDir 'Users\Default\NTUSER.DAT'
    if ((Invoke-W11Reg ('load {0} {1}' -f $script:W11D.HiveSoftware, (ConvertTo-W11Arg $sw))) -ne 0) { throw "reg load failed: $sw" }
    if ((Invoke-W11Reg ('load {0} {1}' -f $script:W11D.HiveDefault, (ConvertTo-W11Arg $du))) -ne 0) { Dismount-W11Hives; throw "reg load failed: $du" }
}

function Dismount-W11Hives {
    foreach ($h in @($script:W11D.HiveSoftware, $script:W11D.HiveDefault)) {
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

function Invoke-W11Tweaks {
    param([object[]]$TweakDefs, [switch]$DryRun)
    $map = @{ SOFTWARE = $script:W11D.HiveSoftware; DEFAULTUSER = $script:W11D.HiveDefault }
    foreach ($t in $TweakDefs) {
        Write-W11Log -En "  Tweak: $($t.Name)" -Vi $t.NameVi
        if ($t.ContainsKey('Set')) {
            foreach ($v in $t.Set) {
                $key = '{0}\{1}' -f $map[$v.Hive], $v.Key
                if ($DryRun) { Write-W11Log -Level DRY -En "    would set $($v.Hive)\$($v.Key)\$($v.Value) = $($v.Data)"; continue }
                $code = Invoke-W11Reg ('add {0} /v {1} /t {2} /d {3} /f' -f (ConvertTo-W11Arg $key), (ConvertTo-W11Arg $v.Value), $v.Type, $v.Data)
                if ($code -ne 0) { Write-W11Log -Level WARN -En "    FAILED to set $($v.Key)\$($v.Value) (exit $code)" -Vi 'Không ghi được (có thể do quyền của key)' }
                else { Write-W11Log -En "    set $($v.Key)\$($v.Value) = $($v.Data)" }
            }
        }
        if ($t.ContainsKey('DeleteValue')) {
            foreach ($d in $t.DeleteValue) {
                $key = '{0}\{1}' -f $map[$d.Hive], $d.Key
                if ($DryRun) { Write-W11Log -Level DRY -En "    would delete value (if present) $($d.Hive)\$($d.Key)\$($d.Value)"; continue }
                if ((Invoke-W11Reg ('query {0} /v {1}' -f (ConvertTo-W11Arg $key), (ConvertTo-W11Arg $d.Value))) -ne 0) { Write-W11Log -En "    (not present) $($d.Key)\$($d.Value)"; continue }
                $code = Invoke-W11Reg ('delete {0} /v {1} /f' -f (ConvertTo-W11Arg $key), (ConvertTo-W11Arg $d.Value))
                if ($code -ne 0) { Write-W11Log -Level WARN -En "    FAILED to delete value $($d.Key)\$($d.Value) (exit $code)" -Vi 'Không xoá được giá trị' }
                else { Write-W11Log -En "    deleted value $($d.Key)\$($d.Value)" }
            }
        }
        if ($t.ContainsKey('Delete')) {
            foreach ($d in $t.Delete) {
                $key = '{0}\{1}' -f $map[$d.Hive], $d.Key
                if ($DryRun) { Write-W11Log -Level DRY -En "    would delete (if present) $($d.Hive)\$($d.Key)"; continue }
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
            if (Test-W11Like $n @($pt)) { Write-W11Log -Level WARN -En "  $n is in this image but outside its MinBuild/MaxBuild range in DebloatConfig.psd1 - kept" -Vi 'app này có trong bản này nhưng nằm ngoài khoảng build trong cấu hình - được giữ lại'; break }
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
    <# Fallback when DISM has no Appx provider (e.g. ISO's DISM on Windows 7): same method as the
       reference Linux build - drop AppxAllUserStore\Applications entries, add Deprovisioned
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
        [bool]$DryRun = $false,
        [int]$MinFreeGB = 25,
        [string]$OscdimgPath,
        [string]$ConfigPath,
        [string]$LogPath,
        [bool]$KeepWorkDir = $false,
        [hashtable]$Sync
    )
    $ErrorActionPreference = 'Stop'
    if ($Sync) { $script:W11D.Sync = $Sync }
    $OutputIso = [IO.Path]::GetFullPath($OutputIso)
    $IsoPath = [IO.Path]::GetFullPath($IsoPath)
    $outDir = Split-Path -Parent $OutputIso
    if (-not $WorkDir) { $WorkDir = Join-Path $outDir 'WinDebloat_work' }
    $WorkDir = [IO.Path]::GetFullPath($WorkDir).TrimEnd('\')
    $null = New-Item -ItemType Directory -Force -Path $outDir
    if (-not $LogPath) { $LogPath = Join-Path $outDir ('WinDebloat_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss')) }
    $script:W11D.LogPath = $LogPath
    if (-not $AutounattendPath) { $AutounattendPath = Join-Path $script:W11Root 'autounattend.xml' }

    $cfg = Get-W11Config -Path $ConfigPath
    $userApps = $RemoveApps; $userTweaks = $Tweaks
    # provisional profile (final one is chosen once the image build is known)
    $os = $TargetOs
    if ($os -eq 'Auto') { $os = Get-W11OsFromName $IsoPath; if (-not $os) { $os = 'Win11' } }
    $planFor = {
        param($o, [int]$b = 0)
        $script:__prof = Get-W11Profile -Config $cfg -Os $o -Build $b
        $a = $userApps; if ($null -eq $a) { $a = @($script:__prof.Apps | Where-Object { $_.Default } | ForEach-Object { $_.Id }) }
        $t = $userTweaks; if ($null -eq $t) { $t = @($script:__prof.Tweaks | Where-Object { $_.Default } | ForEach-Object { $_.Id }) }
        # an explicitly chosen tweak that does not apply to this build is skipped (and logged)
        $script:__skippedTweaks = @($script:__prof.SkippedTweaks | Where-Object { $t -contains $_.Id } | ForEach-Object { $_.Id })
        $t = @($t | Where-Object { $script:__skippedTweaks -notcontains $_ })
        $script:__apps = @($a); $script:__tweakIds = @($t)
        $script:__tweakDefs = @($script:__prof.Tweaks | Where-Object { $t -contains $_.Id })
    }
    & $planFor $os
    $RemoveApps = $script:__apps; $Tweaks = $script:__tweakIds; $tweakDefs = $script:__tweakDefs

    $mountDir = Join-Path $WorkDir 'mount'
    $tree = Join-Path $WorkDir 'iso'
    $workWim = Join-Path $WorkDir 'install.work.wim'
    $marker = Join-Path $WorkDir '.w11debloat-work'
    $iso = $null; $imageMounted = $false; $success = $false
    $result = New-W11Obj @{ OutputIso = $OutputIso; Sha256 = $null; LogPath = $LogPath; DryRun = $DryRun; TargetOs = $null; Build = 0; Release = $null }

    Write-W11Log -Level STEP -En "===== WinDebloat Tool $($script:W11D.Version) (Windows 10/11) =====" -Vi '===== Công cụ debloat Windows 10/11 ====='
    Write-W11Log -En "Source ISO: $IsoPath" -Vi 'ISO nguồn'
    Write-W11Log -En "Output ISO: $OutputIso" -Vi 'ISO đầu ra'
    Write-W11Log -En "Work dir  : $WorkDir" -Vi 'Thư mục tạm'
    Write-W11Log -En "Log file  : $LogPath" -Vi 'File log'
    if ($DryRun) { Write-W11Log -Level DRY -En 'DRY RUN: nothing will be modified.' -Vi 'CHẠY THỬ: không thay đổi gì.' }

    try {
        Set-W11Progress 1 'Checking prerequisites / Kiểm tra điều kiện'
        if (-not (Test-W11Admin)) { throw 'Administrator rights required / Cần quyền Administrator' }
        if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found / Không thấy ISO: $IsoPath" }
        if ($OutputIso -eq $IsoPath) { throw 'Output ISO must differ from source ISO / ISO đầu ra phải khác ISO nguồn' }
        if ($Autounattend -and -not (Test-Path -LiteralPath $AutounattendPath)) { throw "autounattend.xml not found: $AutounattendPath" }

        $free = Get-W11FreeGB -Path $WorkDir
        Write-W11Log -En "Free space on work drive: $free GB (need >= $MinFreeGB GB)" -Vi "Dung lượng trống: $free GB (cần >= $MinFreeGB GB)"
        if ($free -lt $MinFreeGB -and -not $DryRun) { throw "Not enough free space / Không đủ dung lượng trống ($free GB < $MinFreeGB GB)" }

        $oscdimg = Find-W11Oscdimg -Hint $OscdimgPath
        if ($oscdimg) { Write-W11Log -En "oscdimg: $oscdimg" }
        elseif ($DryRun) { Write-W11Log -Level WARN -En 'oscdimg.exe not found (needed for a real run).' -Vi 'Chưa có oscdimg.exe (cần khi chạy thật).' }
        else { throw 'oscdimg.exe not found - install ADK Deployment Tools or copy oscdimg.exe into tools\ / Chưa có oscdimg.exe' }

        if ((Test-Path -LiteralPath $WorkDir) -and -not (Test-Path -LiteralPath $marker)) {
            if (@(Get-ChildItem -LiteralPath $WorkDir -Force).Count -gt 0) { throw "Work dir is not empty and was not created by this tool: $WorkDir / Thư mục tạm đang chứa dữ liệu khác" }
        }
        if ($DryRun -and -not (Get-Command Mount-DiskImage -ErrorAction SilentlyContinue)) {
            Write-W11Log -Level DRY -En 'Windows 7: dry run cannot look inside the ISO without extracting it (7-Zip). Plan only.' -Vi 'Win7: chạy thử không xem được bên trong ISO, chỉ in kế hoạch.'
            Write-W11Log -En ('Apps to remove: ' + ($RemoveApps -join ', '))
            Invoke-W11Tweaks -TweakDefs $tweakDefs -DryRun
            return $result
        }

        # ---- prepare work dir ----
        if (Test-Path -LiteralPath $WorkDir) {
            if (-not $DryRun) {
                Write-W11Log -En 'Cleaning previous work dir...' -Vi 'Dọn thư mục tạm cũ...'
                try { $null = Select-W11Dism; Clear-W11StaleMount -MountDir $mountDir } catch { $null = $_ }
                Dismount-W11Hives
                Remove-Item -LiteralPath $WorkDir -Recurse -Force
            }
        }
        $null = New-Item -ItemType Directory -Force -Path $WorkDir
        $null = New-Item -ItemType Directory -Force -Path $mountDir
        Set-Content -LiteralPath $marker -Value 'w11debloat'

        # ---- open ISO ----
        Set-W11Progress 3 'Opening ISO / Đang mở ISO'
        Write-W11Log -Level STEP -En 'Opening source ISO...' -Vi 'Đang mở ISO nguồn...'
        $iso = Open-W11Iso -IsoPath $IsoPath -ExtractTo $tree
        Write-W11Log -En "ISO root: $($iso.Root)  label: $($iso.Label)  mode: $($iso.Mode)"
        $srcImage = $null
        foreach ($f in @('install.wim', 'install.esd')) { $p = Join-Path $iso.Root "sources\$f"; if (Test-Path -LiteralPath $p) { $srcImage = $p; break } }
        if (-not $srcImage) { throw 'sources\install.wim or install.esd not found - not a Windows install ISO? / Không thấy install.wim/esd' }
        $isEsd = ($srcImage -like '*.esd')

        $d = Select-W11Dism -IsoSourcesDir (Join-Path $iso.Root 'sources')
        Write-W11Log -En "DISM: $($d.Path) ($($d.Kind) $($d.Version)), appx provider: $($script:W11D.DismCanAppx)"
        if (-not $script:W11D.DismCanAppx) { Write-W11Log -Level WARN -En 'Apps will be removed with the manual registry/folder method.' -Vi 'App sẽ được gỡ bằng phương pháp registry/thư mục thủ công.' }

        $all = @(Get-W11ImageInfo -ImageFile $srcImage)
        foreach ($e in $all) { Write-W11Log -En ('  [{0}] {1} ({2})' -f $e.Index, $e.Name, $e.EditionId) }
        if ($EditionMode -eq 'HomePro') { $selected = @($all | Where-Object { $_.EditionId -eq 'Core' -or $_.EditionId -eq 'Professional' }) }
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
            if ($Autounattend) { Write-W11Log -Level DRY -En "Would add autounattend.xml (UILanguage=$lang, arch=$archName, $(Get-W11OsLabel $os))" -Vi 'Sẽ thêm autounattend.xml' }
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
        if ($d.Kind -eq 'ISO') { $script:W11D.Dism = Join-Path $tree 'sources\dism.exe' }

        # ---- working WIM ----
        $targets = @()
        if ($isEsd) {
            $n = 0
            foreach ($e in $selected) {
                $n++
                Assert-W11NotCancelled
                Write-W11Log -Level STEP -En "Converting ESD index $($e.Index) to WIM (slow)..." -Vi 'Đang chuyển ESD sang WIM (chậm)...'
                $null = Invoke-W11Dism ('/Export-Image /SourceImageFile:{0} /SourceIndex:{1} /DestinationImageFile:{2} /Compress:max /CheckIntegrity' -f (ConvertTo-W11Arg $srcImage), $e.Index, (ConvertTo-W11Arg $workWim)) -Quiet -ProgressBase (8 + 12 * ($n - 1) / $selected.Count) -ProgressSpan (12 / $selected.Count) -ProgressText "ESD -> WIM: $($e.Name)"
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
            $kept = Join-Path $outDir ('kept_index{0}.txt' -f $t.WorkIndex)
            Set-W11Progress ($base + $span * 0.2) "$tag Removing apps / Gỡ app"
            if ($script:W11D.DismCanAppx) {
                Remove-W11AppsDism -MountDir $mountDir -Patterns $RemoveApps -Protected $cfgProtected -OutOfRange $outOfRange -KeptListPath $kept
                Mount-W11Hives -MountDir $mountDir
                try { Invoke-W11Tweaks -TweakDefs $tweakDefs } finally { Dismount-W11Hives }
            } else {
                Mount-W11Hives -MountDir $mountDir
                try {
                    Remove-W11AppsManual -MountDir $mountDir -Patterns $RemoveApps -Protected $cfgProtected -KeptListPath $kept
                    Invoke-W11Tweaks -TweakDefs $tweakDefs
                } finally { Dismount-W11Hives }
            }
            Assert-W11NotCancelled
            if ($ComponentCleanup) {
                Write-W11Log -En '  /Cleanup-Image /StartComponentCleanup (slow)...' -Vi '  Dọn component store (chậm)...'
                $r = Invoke-W11Dism ('/Image:{0} /Cleanup-Image /StartComponentCleanup' -f (ConvertTo-W11Arg $mountDir)) -Quiet -NoThrow -ProgressBase ($base + $span * 0.5) -ProgressSpan ($span * 0.3) -ProgressText "$tag Component cleanup"
                if ($r.ExitCode -ne 0) { Write-W11Log -Level WARN -En "  Component cleanup failed (exit $($r.ExitCode)), continuing" -Vi '  Dọn component lỗi, bỏ qua' }
            }
            Write-W11Log -En '  Committing image...' -Vi '  Đang lưu image...'
            $null = Invoke-W11Dism ('/Unmount-Image /MountDir:{0} /Commit' -f (ConvertTo-W11Arg $mountDir)) -Quiet -ProgressBase ($base + $span * 0.8) -ProgressSpan ($span * 0.2) -ProgressText "$tag Commit"
            $imageMounted = $false
        }

        # ---- export / recompress ----
        $finalWim = Join-Path $tree 'sources\install.wim'
        if (Test-Path -LiteralPath $finalWim) { Remove-Item -LiteralPath $finalWim -Force }
        $i = 0
        foreach ($t in $targets) {
            $i++
            Assert-W11NotCancelled
            Write-W11Log -Level STEP -En "Exporting/recompressing $($t.Name)..." -Vi "Đang nén lại $($t.Name)..."
            $null = Invoke-W11Dism ('/Export-Image /SourceImageFile:{0} /SourceIndex:{1} /DestinationImageFile:{2} /Compress:max' -f (ConvertTo-W11Arg $workWim), $t.WorkIndex, (ConvertTo-W11Arg $finalWim)) -Quiet -ProgressBase (75 + 12 * ($i - 1) / $targets.Count) -ProgressSpan (12 / $targets.Count) -ProgressText "Export $($t.Name)"
        }
        Remove-Item -LiteralPath $workWim -Force
        Write-W11Log -En ('install.wim: {0:N2} GB' -f ((Get-Item -LiteralPath $finalWim).Length / 1GB))

        # ---- autounattend ----
        if ($Autounattend) {
            Write-W11Log -Level STEP -En 'Adding autounattend.xml to ISO root...' -Vi 'Thêm autounattend.xml vào gốc ISO...'
            Write-W11Autounattend -Template $AutounattendPath -Destination (Join-Path $tree 'autounattend.xml') -Language $lang -Arch $archName -Os $os
        }

        # ---- build ISO ----
        Assert-W11NotCancelled
        Write-W11Log -Level STEP -En 'Building bootable ISO with oscdimg...' -Vi 'Đang tạo ISO khởi động bằng oscdimg...'
        if (Test-Path -LiteralPath $OutputIso) { Remove-Item -LiteralPath $OutputIso -Force }
        $etfs = Join-Path $tree 'boot\etfsboot.com'
        $efisys = Join-Path $tree 'efi\microsoft\boot\efisys.bin'
        if (-not (Test-Path -LiteralPath $efisys)) { throw "UEFI boot file missing: $efisys" }
        $label = (Get-W11IsoLabel -IsoPath $IsoPath) -replace '[^A-Za-z0-9_]', '_'
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
        Write-W11Log -Level OK -En ('DONE: {0} ({1:N2} GB)' -f $OutputIso, ((Get-Item -LiteralPath $OutputIso).Length / 1GB)) -Vi 'HOÀN TẤT'
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
        if ((Test-Path -LiteralPath $marker) -and ($DryRun -or ($success -and -not $KeepWorkDir))) {
            Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
#endregion

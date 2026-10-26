# Parse-checks every .ps1/.psd1 in the repo and loads the config. Runs on pwsh (Linux/Windows) or Windows PowerShell.
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$fail = 0
Get-ChildItem -Path $root -Recurse -Include *.ps1, *.psd1 | ForEach-Object {
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errs)
    if ($errs.Count) { $fail++; foreach ($e in $errs) { Write-Host ("FAIL {0}:{1} {2}" -f $_.Name, $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Red } }
    else { Write-Host "OK   $($_.FullName.Substring($root.Length + 1))" -ForegroundColor Green }
}
# config must load through the same PS2-compatible loader the tool uses
. (Join-Path $root 'lib\Core.ps1')
$cfg = Get-W11Config -Path (Join-Path $root 'config\DebloatConfig.psd1')
Write-Host ("Config: Win11 {0} apps ({1} default) {2} tweaks; Win10 {3} apps ({4} default) {5} tweaks; {6} protected" -f @($cfg.Apps).Count, @($cfg.Apps | Where-Object { $_.Default }).Count, @($cfg.Tweaks).Count, @($cfg.Win10Apps).Count, @($cfg.Win10Apps | Where-Object { $_.Default }).Count, @($cfg.Win10Tweaks).Count, @($cfg.Protected).Count)
# data\*.json and data\presets\*.json must parse with the built-in parser (PowerShell 2.0 path) and validate
foreach ($jf in @(Get-ChildItem -LiteralPath (Join-Path $root 'data') -Recurse -Filter '*.json')) {
    $msg = $null
    try {
        $d = ConvertFrom-W11Json ([IO.File]::ReadAllText($jf.FullName)) -Engine Parser
        $bad = @()
        if ($jf.Name -eq 'apps.json') { $bad = @(Test-W11AppData $d) } elseif ($jf.Name -eq 'tweaks.json') { $bad = @(Test-W11TweakData $d) } else { $bad = @(Test-W11Preset $d) }
        if ($bad.Count) { $msg = $bad -join '; ' }
    } catch { $msg = $_.Exception.Message }
    if ($msg) { $fail++; Write-Host "FAIL $($jf.Name): $msg" -ForegroundColor Red } else { Write-Host "OK   data: $($jf.Name)" -ForegroundColor Green }
}
[xml]$x = Get-Content -LiteralPath (Join-Path $root 'autounattend.xml') -Encoding UTF8
Write-Host "autounattend.xml: well-formed XML ($($x.unattend.settings.Count) passes)"
exit $fail

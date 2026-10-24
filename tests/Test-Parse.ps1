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
Write-Host ("Config: {0} apps ({1} default), {2} protected, {3} tweaks" -f @($cfg.Apps).Count, @($cfg.Apps | Where-Object { $_.Default }).Count, @($cfg.Protected).Count, @($cfg.Tweaks).Count)
[xml]$x = Get-Content -LiteralPath (Join-Path $root 'autounattend.xml') -Encoding UTF8
Write-Host "autounattend.xml: well-formed XML ($($x.unattend.settings.Count) passes)"
exit $fail

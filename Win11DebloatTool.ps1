<#
    Alias of WinDebloatTool.ps1: same parameters, forwards everything to it.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$IsoPath,
    [string]$OutputIso,
    [string]$WorkDir,
    [ValidateSet('All', 'HomePro', 'Custom')][string]$Edition = 'All',
    [ValidateSet('Auto', 'Win10', 'Win11')][string]$TargetOs = 'Auto',
    [int[]]$Indexes,
    [switch]$NoAutounattend,
    [switch]$ComponentCleanup,
    [ValidateSet('Max', 'Recovery')][string]$Compression = 'Max',
    [int]$SplitWimMB = 0,
    [switch]$DryRun,
    [switch]$NoGui,
    [switch]$Check,
    [switch]$KeepWorkDir,
    [int]$MinFreeGB = 25,
    [string]$OscdimgPath
)
$target = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'WinDebloatTool.ps1'
if ($WhatIfPreference) { $PSBoundParameters['DryRun'] = [switch]$true; [void]$PSBoundParameters.Remove('WhatIf') }
$global:LASTEXITCODE = 0
try { & $target @PSBoundParameters } catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
exit $LASTEXITCODE

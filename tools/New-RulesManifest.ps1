<#
.SYNOPSIS
    Writes data\rules-manifest.json for the current data\apps.json and data\tweaks.json (maintainers).
.DESCRIPTION
    Run after every change of the rule files, then commit the three files together. Clients download the
    manifest from the main branch on GitHub and accept the rule files only when their SHA256 matches.
.EXAMPLE
    .\tools\New-RulesManifest.ps1 -Version 2026.11.2.1
#>
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$MinToolVersion = '1.1.0'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $root 'lib\Core.ps1')
if (-not (ConvertTo-W11Version $Version)) { throw "Version must look like 2026.11.1.1: $Version" }
$data = Join-Path $root 'data'
$files = @()
$parsed = @{}
foreach ($n in $script:W11RulesFiles) {
    $b = [IO.File]::ReadAllBytes((Join-Path $data $n))
    $parsed[$n] = ConvertFrom-W11RulesBytes $b
    $files += , (New-W11Ordered 'name' $n 'sha256' (Get-W11RulesHash $b))
}
$bad = @(Test-W11RulesContent $parsed['apps.json'] $parsed['tweaks.json'])
if ($bad.Count) { throw ('Rule files are not valid for publishing: ' + ($bad -join '; ')) }
$m = New-W11Ordered 'schema' 1 'version' $Version 'minToolVersion' $MinToolVersion 'files' $files
$out = Join-Path $data $script:W11RulesManifestName
[IO.File]::WriteAllText($out, (ConvertTo-W11Json $m) + "`r`n", (New-Object Text.UTF8Encoding $false))
Write-Host "Written $out"

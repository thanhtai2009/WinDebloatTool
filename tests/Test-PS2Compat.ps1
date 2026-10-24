# Static PowerShell 2.0 compatibility scan (PSScriptAnalyzer cannot target 2.0).
# Flags syntax/cmdlets that do not exist in Windows PowerShell 2.0 (Windows 7 SP1 in-box).
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
# Win8+ cmdlets are allowed only where guarded by Get-Command checks (Open-W11Iso / Close-W11Iso / Get-W11IsoEditions)
$guarded = @{ 'Mount-DiskImage' = 1; 'Dismount-DiskImage' = 1; 'Get-Volume' = 1 }
$ps3Cmdlets = @('Invoke-WebRequest', 'Invoke-RestMethod', 'ConvertFrom-Json', 'ConvertTo-Json', 'Get-FileHash', 'Import-PowerShellDataFile',
    'Expand-Archive', 'Compress-Archive', 'Get-CimInstance', 'New-TemporaryFile', 'Unblock-File', 'Get-WindowsImage', 'Mount-WindowsImage',
    'Dismount-WindowsImage', 'Export-WindowsImage', 'Get-AppxProvisionedPackage', 'Remove-AppxProvisionedPackage', 'Repair-WindowsImage',
    'Start-BitsTransfer', 'Get-Disk', 'Get-Partition', 'Mount-DiskImage', 'Dismount-DiskImage', 'Get-Volume', 'Get-AuthenticodeSignature_')
$ps3Params = @('Raw', 'NoNewline', 'File', 'Directory', 'Depth')
$issues = 0
function Report($file, $ast, $msg) { $script:issues++; Write-Host ("PS2 {0}:{1}  {2}  -> {3}" -f $file, $ast.Extent.StartLineNumber, $msg, $ast.Extent.Text.Split("`n")[0].Trim()) -ForegroundColor Yellow }
Get-ChildItem -Path $root -Recurse -Include *.ps1 | Where-Object { $_.FullName -notlike '*tests*' } | ForEach-Object {
    $file = $_.FullName.Substring($root.Length + 1)
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$t, [ref]$e)
    $all = $ast.FindAll({ $true }, $true)
    foreach ($n in $all) {
        $type = $n.GetType().Name
        switch ($type) {
            'NamedAttributeArgumentAst' { if ($n.ExpressionOmitted) { Report $file $n "attribute argument without value (PS3+): use $($n.ArgumentName) = `$true" } }
            'InvokeMemberExpressionAst' {
                $m = $n.Member.Extent.Text
                if ($n.Static -and $m -eq 'new') { Report $file $n '::new() is PS5+' }
                if (-not $n.Static -and ($m -eq 'Where' -or $m -eq 'ForEach')) { Report $file $n '.Where()/.ForEach() are PS4+' }
            }
            'TypeExpressionAst' { if ($n.TypeName.Name -match '^(pscustomobject|ordered)$') { Report $file $n "[$($n.TypeName.Name)] is PS3+" } }
            'ConvertExpressionAst' { if ($n.Type.TypeName.Name -match '^(pscustomobject|ordered)$') { Report $file $n "[$($n.Type.TypeName.Name)] is PS3+" } }
            'TypeDefinitionAst' { Report $file $n 'class/enum is PS5+' }
            'UsingExpressionAst' { Report $file $n '$using: is PS3+' }
            'BinaryExpressionAst' { if ("$($n.Operator)" -match '^(Iin|Cin|In|Inotin|Cnotin|NotIn|Shl|Shr)$') { Report $file $n "-$($n.Operator) operator is PS3+" } }
            'VariableExpressionAst' { if ($n.VariablePath.UserPath -match '^(PSScriptRoot|PSItem|PSCommandPath)$') { Report $file $n "`$$($n.VariablePath.UserPath) is not available in PS2 scripts" } }
            'CommandAst' {
                $name = $n.GetCommandName()
                if ($name -and ($ps3Cmdlets -contains $name)) {
                    $fn = $n.Parent; while ($fn -and $fn.GetType().Name -ne 'FunctionDefinitionAst') { $fn = $fn.Parent }
                    $fname = ''; if ($fn) { $fname = $fn.Name }
                    if (-not ($guarded.ContainsKey($name) -and @('Open-W11Iso', 'Close-W11Iso', 'Get-W11IsoEditions') -contains $fname)) { Report $file $n "$name is not in PS2/Win7" }
                }
                foreach ($el in $n.CommandElements) {
                    if ($el.GetType().Name -eq 'CommandParameterAst' -and ($ps3Params -contains $el.ParameterName) -and $name -match '^(Get-Content|Set-Content|Out-File|Get-ChildItem|ConvertTo-Json)$') { Report $file $el "-$($el.ParameterName) on $name is PS3+" }
                }
                if (($name -eq 'Where-Object' -or $name -eq 'ForEach-Object' -or $name -eq '?' -or $name -eq '%') -and -not ($n.CommandElements | Where-Object { $_.GetType().Name -eq 'ScriptBlockExpressionAst' })) { Report $file $n 'simplified Where/ForEach syntax is PS3+' }
            }
        }
    }
    Write-Host "scanned $file"
}
Write-Host "PS2 compatibility issues: $issues"
exit $issues

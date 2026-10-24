@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                 # console tool: colored bilingual output is intended
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        'PSAvoidUsingPositionalParameters',
        'PSUseBOMForUnicodeEncodedFile',
        'PSAvoidUsingWMICmdlet',                 # Get-WmiObject on purpose: CIM cmdlets do not exist in PowerShell 2.0
        'PSReviewUnusedParameter'                # false positives: parameters used inside dot-sourced helper scriptblocks / event args
    )
    Rules = @{
        PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('3.0', '5.1', '7.0') }
        PSUseCompatibleCmdlets = @{ Compatibility = @('desktop-3.0-windows') }
        PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @('win-8_x64_6.2.9200.0_3.0_x64_4.0.30319.42000_framework') }
    }
}

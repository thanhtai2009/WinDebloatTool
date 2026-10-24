# Win11 Debloat Tool - configuration / cấu hình
# Edit this file to change what is removed. / Sửa file này để đổi danh sách gỡ bỏ.
#  Apps    : Id is matched against the provisioned package DisplayName (wildcards * allowed).
#            Default = $true -> pre-checked in the GUI and used by the CLI.
#  Protected: never removed, even if listed above (Store, Defender UI, runtimes...).
#  Tweaks  : registry values written to the OFFLINE image. Hive SOFTWARE = HKLM\SOFTWARE,
#            DEFAULTUSER = C:\Users\Default\NTUSER.DAT (applies to every new user).
@{
    Apps = @(
        # ---- default removals (same list as the reference build) ----
        @{ Id = 'Clipchamp.Clipchamp';                    Name = 'Clipchamp video editor';          Default = $true }
        @{ Id = 'MSTeams';                                Name = 'Microsoft Teams (new)';           Default = $true }
        @{ Id = 'Microsoft.OutlookForWindows';            Name = 'Outlook (new)';                   Default = $true }
        @{ Id = 'Microsoft.BingNews';                     Name = 'Microsoft News';                  Default = $true }
        @{ Id = 'Microsoft.BingSearch';                   Name = 'Bing Search';                     Default = $true }
        @{ Id = 'Microsoft.BingWeather';                  Name = 'Weather';                         Default = $true }
        @{ Id = 'Microsoft.GamingApp';                    Name = 'Xbox app';                        Default = $true }
        @{ Id = 'Microsoft.XboxGamingOverlay';            Name = 'Xbox Game Bar';                   Default = $true }
        @{ Id = 'Microsoft.Xbox.TCUI';                    Name = 'Xbox TCUI';                       Default = $true }
        @{ Id = 'Microsoft.XboxIdentityProvider';         Name = 'Xbox Identity Provider';          Default = $true }
        @{ Id = 'Microsoft.XboxSpeechToTextOverlay';      Name = 'Xbox Speech-to-text overlay';     Default = $true }
        @{ Id = 'Microsoft.MicrosoftSolitaireCollection'; Name = 'Solitaire Collection';            Default = $true }
        @{ Id = 'Microsoft.GetHelp';                      Name = 'Get Help';                        Default = $true }
        @{ Id = 'Microsoft.MicrosoftOfficeHub';           Name = 'Microsoft 365 (Office) hub';      Default = $true }
        @{ Id = 'Microsoft.PowerAutomateDesktop';         Name = 'Power Automate';                  Default = $true }
        @{ Id = 'Microsoft.Todos';                        Name = 'Microsoft To Do';                 Default = $true }
        @{ Id = 'Microsoft.Windows.DevHome';              Name = 'Dev Home';                        Default = $true }
        @{ Id = 'Microsoft.WindowsFeedbackHub';           Name = 'Feedback Hub';                    Default = $true }
        @{ Id = 'Microsoft.YourPhone';                    Name = 'Phone Link';                      Default = $true }
        @{ Id = 'MicrosoftWindows.CrossDevice';           Name = 'Cross Device experience';         Default = $true }
        @{ Id = 'MicrosoftCorporationII.QuickAssist';     Name = 'Quick Assist';                    Default = $true }
        @{ Id = 'Microsoft.Copilot';                      Name = 'Copilot';                         Default = $true }
        @{ Id = 'MicrosoftCorporationII.MicrosoftFamily'; Name = 'Microsoft Family';                Default = $true }
        # ---- removed only if present (older builds) ----
        @{ Id = 'Microsoft.549981C3F5F10';                Name = 'Cortana (older builds)';          Default = $true }
        @{ Id = 'Microsoft.WindowsMaps';                  Name = 'Maps (older builds)';             Default = $true }
        @{ Id = 'Microsoft.People';                       Name = 'People (older builds)';           Default = $true }
        @{ Id = 'Microsoft.Getstarted';                   Name = 'Tips / Get Started';              Default = $true }
        @{ Id = 'Microsoft.Windows.Ai.Copilot.Provider';  Name = 'Copilot provider (older builds)'; Default = $true }
        @{ Id = 'MicrosoftTeams';                         Name = 'Teams consumer (older builds)';   Default = $true }
        # ---- optional, NOT removed by default ----
        @{ Id = 'MicrosoftWindows.Client.WebExperience';  Name = 'Widgets board (optional)';        Default = $false }
        @{ Id = 'Microsoft.ZuneMusic';                    Name = 'Media Player (optional)';         Default = $false }
        @{ Id = 'Microsoft.ZuneVideo';                    Name = 'Movies & TV (optional)';          Default = $false }
        @{ Id = 'Microsoft.WindowsCamera';                Name = 'Camera (optional)';               Default = $false }
        @{ Id = 'Microsoft.WindowsAlarms';                Name = 'Clock / Alarms (optional)';       Default = $false }
        @{ Id = 'Microsoft.WindowsSoundRecorder';         Name = 'Sound Recorder (optional)';       Default = $false }
        @{ Id = 'Microsoft.MicrosoftStickyNotes';         Name = 'Sticky Notes (optional)';         Default = $false }
        @{ Id = 'microsoft.windowscommunicationsapps';    Name = 'Mail & Calendar (older builds)';  Default = $false }
    )

    # Never removed / Không bao giờ gỡ
    Protected = @(
        'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',
        'Microsoft.SecHealthUI', 'Microsoft.MicrosoftEdge*', 'Microsoft.WebView2*', 'Microsoft.VCLibs*',
        'Microsoft.UI.Xaml*', 'Microsoft.NET.Native*', 'Microsoft.WindowsAppRuntime*',
        'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad',
        'Microsoft.WindowsTerminal', 'Microsoft.ScreenSketch', 'Microsoft.Paint',
        'Microsoft.*VideoExtension*', 'Microsoft.*ImageExtension*', 'Microsoft.WebMediaExtensions',
        'Microsoft.ApplicationCompatibilityEnhancements'
    )

    Tweaks = @(
        @{
            Id = 'ConsumerFeatures'; Default = $true
            Name = 'Disable consumer features / suggested apps'; NameVi = 'Tắt cài app gợi ý (consumer features)'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\CloudContent'; Value = 'DisableWindowsConsumerFeatures'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\CloudContent'; Value = 'DisableConsumerAccountStateContent'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\CloudContent'; Value = 'DisableCloudOptimizedContent'; Type = 'REG_DWORD'; Data = '1' }
            )
        }
        @{
            Id = 'CopilotOff'; Default = $true
            Name = 'Turn off Windows Copilot (policy)'; NameVi = 'Tắt Copilot (policy)'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\WindowsCopilot'; Value = 'TurnOffWindowsCopilot'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Policies\Microsoft\Windows\WindowsCopilot'; Value = 'TurnOffWindowsCopilot'; Type = 'REG_DWORD'; Data = '1' }
            )
        }
        @{
            Id = 'WidgetsFeedOff'; Default = $true
            Name = 'Turn off Widgets news feed'; NameVi = 'Tắt tin tức Widgets'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\Windows Feeds'; Value = 'EnableFeeds'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'TeamsChatAutoInstallOff'; Default = $true
            Name = 'Stop Teams/Chat auto-install'; NameVi = 'Chặn tự cài Teams/Chat'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\Windows\CurrentVersion\Communications'; Value = 'ConfigureChatAutoInstall'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'BypassNRO'; Default = $true
            Name = 'BypassNRO=1 (allow setup without internet / local account)'; NameVi = 'BypassNRO=1 (cài không cần mạng, tài khoản local)'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\Windows\CurrentVersion\OOBE'; Value = 'BypassNRO'; Type = 'REG_DWORD'; Data = '1' }
            )
        }
        @{
            Id = 'NewUserSuggestionsOff'; Default = $true
            Name = 'New users: no suggestions / silent app installs / Start recommendations'; NameVi = 'User mới: tắt gợi ý, tự cài app, gợi ý Start'
            Set = @(
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'ContentDeliveryAllowed'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'FeatureManagementEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'OemPreInstalledAppsEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'PreInstalledAppsEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'PreInstalledAppsEverEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SilentInstalledAppsEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SoftLandingEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SystemPaneSuggestionsEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContentEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-310093Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-338387Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-338388Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-338389Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-338393Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-353694Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-353696Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'SubscribedContent-353698Enabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'RotatingLockScreenOverlayEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Value = 'Start_IrisRecommendations'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'ChatTaskbarOff'; Default = $true
            Name = 'Hide Chat button on taskbar (new users)'; NameVi = 'Ẩn nút Chat trên taskbar (user mới)'
            Set = @(
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Value = 'TaskbarMn'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'RemoveOobeSetupTasks'; Default = $true
            Name = 'Remove OOBE auto-install tasks (Outlook, Dev Home, Cross Device)'; NameVi = 'Xoá tác vụ tự cài Outlook/DevHome/CrossDevice khi setup'
            Delete = @(
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' }
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' }
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\CrossDeviceUpdate' }
            )
        }
    )
}

# Win11 Debloat Tool - configuration / cấu hình
# Edit this file to change what is removed. / Sửa file này để đổi danh sách gỡ bỏ.
#  Profiles: Apps/Tweaks = Windows 11 profile, Win10Apps/Win10Tweaks = Windows 10 profile.
#  Optional MinBuild / MaxBuild per entry: shown and applied only for images in that build range
#  (e.g. 19045 = Windows 10 22H2, 22621 = Windows 11 22H2, 26100 = 24H2). Apps that an image does not
#  contain are skipped anyway and listed in the log.
#            The profile is picked from the image build (>= 22000 = Win11) or chosen in the GUI.
#  Apps    : Id is matched against the provisioned package DisplayName (wildcards * allowed).
#            Default = $true -> pre-checked in the GUI and used by the CLI.
#  Protected: never removed, even if listed above (Store, Defender UI, runtimes...).
#  Tweaks  : registry values written to the OFFLINE image. Hive SOFTWARE = HKLM\SOFTWARE,
#            DEFAULTUSER = C:\Users\Default\NTUSER.DAT (applies to every new user).
@{
    Apps = @(
        # ---- default removals (same list as the reference build) ----
        @{ Id = 'Clipchamp.Clipchamp';                    Name = 'Clipchamp video editor';          Default = $true; MinBuild = 22621 }
        @{ Id = 'MSTeams';                                Name = 'Microsoft Teams (new)';           Default = $true; MinBuild = 22631 }
        @{ Id = 'Microsoft.OutlookForWindows';            Name = 'Outlook (new)';                   Default = $true; MinBuild = 26100 }
        @{ Id = 'Microsoft.BingNews';                     Name = 'Microsoft News';                  Default = $true }
        @{ Id = 'Microsoft.BingSearch';                   Name = 'Bing Search';                     Default = $true; MinBuild = 26100 }
        @{ Id = 'Microsoft.BingWeather';                  Name = 'Weather';                         Default = $true }
        @{ Id = 'Microsoft.GamingApp';                    Name = 'Xbox app';                        Default = $true }
        @{ Id = 'Microsoft.XboxGamingOverlay';            Name = 'Xbox Game Bar';                   Default = $true }
        @{ Id = 'Microsoft.Xbox.TCUI';                    Name = 'Xbox TCUI (unsafe: Store/games UI)'; Default = $false }
        @{ Id = 'Microsoft.XboxIdentityProvider';         Name = 'Xbox Identity Provider (unsafe: game sign-in)'; Default = $false }
        @{ Id = 'Microsoft.XboxSpeechToTextOverlay';      Name = 'Xbox Speech-to-text (unsafe: accessibility, hard to reinstall)'; Default = $false }
        @{ Id = 'Microsoft.MicrosoftSolitaireCollection'; Name = 'Solitaire Collection';            Default = $true }
        @{ Id = 'Microsoft.GetHelp';                      Name = 'Get Help (unsafe: troubleshooters)'; Default = $false }
        @{ Id = 'Microsoft.MicrosoftOfficeHub';           Name = 'Microsoft 365 (Office) hub';      Default = $true }
        @{ Id = 'Microsoft.PowerAutomateDesktop';         Name = 'Power Automate';                  Default = $true }
        @{ Id = 'Microsoft.Todos';                        Name = 'Microsoft To Do';                 Default = $true }
        @{ Id = 'Microsoft.Windows.DevHome';              Name = 'Dev Home';                        Default = $true; MinBuild = 22631; MaxBuild = 26100 }
        @{ Id = 'Microsoft.WindowsFeedbackHub';           Name = 'Feedback Hub';                    Default = $true }
        @{ Id = 'Microsoft.YourPhone';                    Name = 'Phone Link';                      Default = $true }
        @{ Id = 'MicrosoftWindows.CrossDevice';           Name = 'Cross Device experience';         Default = $true; MinBuild = 26100 }
        @{ Id = 'MicrosoftCorporationII.QuickAssist';     Name = 'Quick Assist';                    Default = $true; MinBuild = 22621 }
        @{ Id = 'Microsoft.Copilot';                      Name = 'Copilot';                         Default = $true; MinBuild = 26100 }
        @{ Id = 'MicrosoftCorporationII.MicrosoftFamily'; Name = 'Microsoft Family';                Default = $true; MinBuild = 22621 }
        # ---- removed only if present (older builds) ----
        @{ Id = 'Microsoft.549981C3F5F10';                Name = 'Cortana (older builds)';          Default = $true; MaxBuild = 22631 }
        @{ Id = 'Microsoft.WindowsMaps';                  Name = 'Maps (older builds)';             Default = $true; MaxBuild = 22631 }
        @{ Id = 'Microsoft.People';                       Name = 'People (older builds)';           Default = $true; MaxBuild = 22631 }
        @{ Id = 'Microsoft.Getstarted';                   Name = 'Tips / Get Started';              Default = $true }
        @{ Id = 'Microsoft.Windows.Ai.Copilot.Provider';  Name = 'Copilot provider (older builds)'; Default = $true; MinBuild = 22631; MaxBuild = 26100 }
        @{ Id = 'MicrosoftTeams';                         Name = 'Teams consumer (older builds)';   Default = $true; MaxBuild = 22631 }
        # ---- optional, NOT removed by default ----
        @{ Id = 'MicrosoftWindows.Client.WebExperience';  Name = 'Widgets board (optional)';        Default = $false }
        @{ Id = 'Microsoft.ZuneMusic';                    Name = 'Media Player (optional)';         Default = $false }
        @{ Id = 'Microsoft.ZuneVideo';                    Name = 'Movies & TV (optional)';          Default = $false; MaxBuild = 22631 }
        @{ Id = 'Microsoft.WindowsCamera';                Name = 'Camera (optional)';               Default = $false }
        @{ Id = 'Microsoft.WindowsAlarms';                Name = 'Clock / Alarms (optional)';       Default = $false }
        @{ Id = 'Microsoft.WindowsSoundRecorder';         Name = 'Sound Recorder (optional)';       Default = $false }
        @{ Id = 'Microsoft.MicrosoftStickyNotes';         Name = 'Sticky Notes (optional)';         Default = $false }
        @{ Id = 'microsoft.windowscommunicationsapps';    Name = 'Mail & Calendar (older builds)';  Default = $false; MaxBuild = 22631 }
    )

    # Never removed / Không bao giờ gỡ
    Protected = @(
        'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller',
        'Microsoft.SecHealthUI', 'Microsoft.MicrosoftEdge*', 'Microsoft.WebView2*', 'Microsoft.VCLibs*',
        'Microsoft.UI.Xaml*', 'Microsoft.NET.Native*', 'Microsoft.WindowsAppRuntime*',
        'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad',
        'Microsoft.WindowsTerminal', 'Microsoft.ScreenSketch', 'Microsoft.Paint',
        'Microsoft.*VideoExtension*', 'Microsoft.*ImageExtension*', 'Microsoft.WebMediaExtensions',
        'Microsoft.ApplicationCompatibilityEnhancements', 'Microsoft.Services.Store.Engagement', 'Microsoft.Advertising.Xaml'
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
            Id = 'CopilotOff'; Default = $true; MinBuild = 22621
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
            Id = 'TeamsChatAutoInstallOff'; Default = $true; MaxBuild = 22631
            Name = 'Stop Teams/Chat auto-install'; NameVi = 'Chặn tự cài Teams/Chat'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\Windows\CurrentVersion\Communications'; Value = 'ConfigureChatAutoInstall'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'BypassNRO'; Default = $true; MinBuild = 22000
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
            Id = 'ChatTaskbarOff'; Default = $true; MaxBuild = 22631
            Name = 'Hide Chat button on taskbar (new users)'; NameVi = 'Ẩn nút Chat trên taskbar (user mới)'
            Set = @(
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Value = 'TaskbarMn'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'RemoveOobeSetupTasks'; Default = $true; MinBuild = 22621
            Name = 'Remove OOBE auto-install tasks (Outlook, Dev Home, Cross Device)'; NameVi = 'Xoá tác vụ tự cài Outlook/DevHome/CrossDevice khi setup'
            Delete = @(
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' }
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' }
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\CrossDeviceUpdate' }
            )
        }
    )

    # ======================= Windows 10 profile =======================
    Win10Apps = @(
        # ---- default removals ----
        @{ Id = 'Microsoft.3DBuilder';                    Name = '3D Builder (older builds)';       Default = $true; MaxBuild = 16299 }
        @{ Id = 'Microsoft.Microsoft3DViewer';            Name = '3D Viewer';                       Default = $true; MinBuild = 15063 }
        @{ Id = 'Microsoft.Print3D';                      Name = 'Print 3D (older builds)';         Default = $true; MinBuild = 16299 }
        @{ Id = 'Microsoft.MixedReality.Portal';          Name = 'Mixed Reality Portal';            Default = $true; MinBuild = 15063 }
        @{ Id = 'Microsoft.People';                       Name = 'People';                          Default = $true }
        @{ Id = 'Microsoft.SkypeApp';                     Name = 'Skype';                           Default = $true }
        @{ Id = 'Microsoft.OneConnect';                   Name = 'Mobile Plans (OneConnect)';       Default = $true; MinBuild = 14393 }
        @{ Id = 'Microsoft.Wallet';                       Name = 'Wallet';                          Default = $true; MinBuild = 14393 }
        @{ Id = 'Microsoft.Messaging';                    Name = 'Messaging (older builds)';        Default = $true; MinBuild = 10586; MaxBuild = 18363 }
        @{ Id = 'Microsoft.BingWeather';                  Name = 'Weather';                         Default = $true }
        @{ Id = 'Microsoft.BingNews';                     Name = 'News';                            Default = $true }
        @{ Id = 'Microsoft.GetHelp';                      Name = 'Get Help (unsafe: troubleshooters)'; Default = $false; MinBuild = 16299 }
        @{ Id = 'Microsoft.Getstarted';                   Name = 'Tips / Get Started';              Default = $true }
        @{ Id = 'Microsoft.MicrosoftOfficeHub';           Name = 'Office hub';                      Default = $true }
        @{ Id = 'Microsoft.Office.OneNote';               Name = 'OneNote for Windows 10';          Default = $true }
        @{ Id = 'Microsoft.MicrosoftSolitaireCollection'; Name = 'Solitaire Collection';            Default = $true }
        @{ Id = 'Microsoft.XboxApp';                      Name = 'Xbox Console Companion';          Default = $true }
        @{ Id = 'Microsoft.GamingApp';                    Name = 'Xbox app (if present)';           Default = $true; MinBuild = 19041 }
        @{ Id = 'Microsoft.XboxGameOverlay';              Name = 'Xbox Game Overlay';               Default = $true; MinBuild = 15063 }
        @{ Id = 'Microsoft.XboxGamingOverlay';            Name = 'Xbox Game Bar';                   Default = $true; MinBuild = 17134 }
        @{ Id = 'Microsoft.Xbox.TCUI';                    Name = 'Xbox TCUI (unsafe: Store/games UI)'; Default = $false; MinBuild = 15063 }
        @{ Id = 'Microsoft.XboxIdentityProvider';         Name = 'Xbox Identity Provider (unsafe: game sign-in)'; Default = $false }
        @{ Id = 'Microsoft.XboxSpeechToTextOverlay';      Name = 'Xbox Speech-to-text (unsafe: accessibility, hard to reinstall)'; Default = $false; MinBuild = 17134 }
        @{ Id = 'Microsoft.YourPhone';                    Name = 'Your Phone / Phone Link';         Default = $true; MinBuild = 17763 }
        @{ Id = 'Microsoft.WindowsFeedbackHub';           Name = 'Feedback Hub';                    Default = $true; MinBuild = 14393 }
        @{ Id = 'Microsoft.549981C3F5F10';                Name = 'Cortana';                         Default = $true; MinBuild = 19041 }
        @{ Id = 'Clipchamp.Clipchamp';                    Name = 'Clipchamp (if present)';          Default = $true; MinBuild = 19041 }
        @{ Id = 'MicrosoftTeams';                         Name = 'Teams (if present)';              Default = $true; MinBuild = 19041 }
        @{ Id = 'MSTeams';                                Name = 'Teams new (if present)';          Default = $true; MinBuild = 19041 }
        @{ Id = 'Microsoft.Todos';                        Name = 'To Do (if present)';              Default = $true; MinBuild = 19041 }
        @{ Id = 'Microsoft.PowerAutomateDesktop';         Name = 'Power Automate (if present)';     Default = $true; MinBuild = 19041 }
        @{ Id = 'Microsoft.OutlookForWindows';            Name = 'Outlook new (if present)';        Default = $true; MinBuild = 19041 }
        @{ Id = 'Microsoft.Copilot';                      Name = 'Copilot (if present)';            Default = $true; MinBuild = 19041 }
        @{ Id = 'MicrosoftCorporationII.MicrosoftFamily'; Name = 'Microsoft Family (if present)';   Default = $true; MinBuild = 19041 }
        # ---- optional, NOT removed by default ----
        @{ Id = 'Microsoft.ZuneMusic';                    Name = 'Groove Music (optional)';         Default = $false }
        @{ Id = 'Microsoft.ZuneVideo';                    Name = 'Movies & TV (optional)';          Default = $false }
        @{ Id = 'Microsoft.WindowsMaps';                  Name = 'Maps (optional)';                 Default = $false }
        @{ Id = 'Microsoft.MSPaint';                      Name = 'Paint 3D (optional; classic Paint stays)'; Default = $false; MinBuild = 15063 }
        @{ Id = 'microsoft.windowscommunicationsapps';    Name = 'Mail & Calendar (optional)';      Default = $false }
        @{ Id = 'Microsoft.WindowsCamera';                Name = 'Camera (optional)';               Default = $false }
        @{ Id = 'Microsoft.WindowsAlarms';                Name = 'Alarms & Clock (optional)';       Default = $false }
        @{ Id = 'Microsoft.WindowsSoundRecorder';         Name = 'Voice Recorder (optional)';       Default = $false }
        @{ Id = 'Microsoft.MicrosoftStickyNotes';         Name = 'Sticky Notes (optional)';         Default = $false }
    )

    Win10Tweaks = @(
        @{
            Id = 'ConsumerFeatures'; Default = $true
            Name = 'Disable consumer features / suggested apps'; NameVi = 'Tắt cài app gợi ý (consumer features)'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\CloudContent'; Value = 'DisableWindowsConsumerFeatures'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\CloudContent'; Value = 'DisableSoftLanding'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\CloudContent'; Value = 'DisableCloudOptimizedContent'; Type = 'REG_DWORD'; Data = '1' }
            )
        }
        @{
            Id = 'NewUserSuggestionsOff'; Default = $true
            Name = 'New users: no silent app installs / suggestions / lock-screen ads'; NameVi = 'User mới: tắt tự cài app, gợi ý, quảng cáo màn hình khoá'
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
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'RotatingLockScreenEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Value = 'RotatingLockScreenOverlayEnabled'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'CortanaWebSearchOff'; Default = $true
            Name = 'Cortana and web/Bing results in Start search off'; NameVi = 'Tắt Cortana và kết quả web/Bing khi tìm trong Start'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\Windows Search'; Value = 'AllowCortana'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\Windows Search'; Value = 'DisableWebSearch'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\Windows Search'; Value = 'ConnectedSearchUseWeb'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Search'; Value = 'BingSearchEnabled'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Search'; Value = 'CortanaConsent'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Policies\Microsoft\Windows\Explorer'; Value = 'DisableSearchBoxSuggestions'; Type = 'REG_DWORD'; Data = '1' }
            )
        }
        @{
            Id = 'TelemetryMinimum'; Default = $true
            Name = 'Telemetry to minimum allowed by the edition (Home/Pro = Required, Ent/Edu = Security)'; NameVi = 'Telemetry mức thấp nhất mà phiên bản cho phép'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\DataCollection'; Value = 'AllowTelemetry'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\DataCollection'; Value = 'DoNotShowFeedbackNotifications'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\AdvertisingInfo'; Value = 'DisabledByGroupPolicy'; Type = 'REG_DWORD'; Data = '1' }
            )
        }
        @{
            Id = 'NewsInterestsOff'; Default = $true; MinBuild = 18362
            Name = 'News and Interests (taskbar weather/news) off'; NameVi = 'Tắt Tin tức và sở thích trên taskbar'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\Windows Feeds'; Value = 'EnableFeeds'; Type = 'REG_DWORD'; Data = '0' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Feeds'; Value = 'ShellFeedsTaskbarViewMode'; Type = 'REG_DWORD'; Data = '2' }
            )
        }
        @{
            Id = 'MeetNowOff'; Default = $true; MinBuild = 17763
            Name = 'Hide Meet Now and People on the taskbar'; NameVi = 'Ẩn Meet Now và People trên taskbar'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\Windows\CurrentVersion\Policies\Explorer'; Value = 'HideSCAMeetNow'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Value = 'HideSCAMeetNow'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People'; Value = 'PeopleBand'; Type = 'REG_DWORD'; Data = '0' }
            )
        }
        @{
            Id = 'CopilotOff'; Default = $true; MinBuild = 19045
            Name = 'Turn off Windows Copilot (policy, if it arrives via updates)'; NameVi = 'Tắt Copilot (policy, nếu được cài qua update)'
            Set = @(
                @{ Hive = 'SOFTWARE'; Key = 'Policies\Microsoft\Windows\WindowsCopilot'; Value = 'TurnOffWindowsCopilot'; Type = 'REG_DWORD'; Data = '1' }
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Policies\Microsoft\Windows\WindowsCopilot'; Value = 'TurnOffWindowsCopilot'; Type = 'REG_DWORD'; Data = '1' }
            )
        }
        @{
            Id = 'RemoveOobeSetupTasks'; Default = $true; MinBuild = 19045
            Name = 'Remove OOBE auto-install tasks (Outlook, Dev Home) if present'; NameVi = 'Xoá tác vụ tự cài Outlook/DevHome khi setup (nếu có)'
            Delete = @(
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' }
                @{ Hive = 'SOFTWARE'; Key = 'Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' }
            )
        }
        @{
            Id = 'OneDriveSetupOff'; Default = $false
            Name = 'Do not auto-install OneDrive for new users (optional)'; NameVi = 'Không tự cài OneDrive cho user mới (tuỳ chọn)'
            DeleteValue = @(
                @{ Hive = 'DEFAULTUSER'; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Value = 'OneDriveSetup' }
            )
        }
    )

    # ---------- ISO download from Microsoft ----------
    # aria2 (tools\aria2\<arch>\aria2c.exe, bundled; or tools\aria2c.exe / next to the script / PATH)
    # downloads with several connections. If it is missing or fails, the built-in single-stream
    # downloader (with resume) is used automatically.
    Download = @{
        UseAria2          = $true
        Aria2Connections  = 16       # --max-connection-per-server (1-16)
        Aria2Split        = 16       # --split
        Aria2MinSplitSize = '1M'     # --min-split-size
        Aria2FileAllocation = 'none' # none | prealloc | falloc | trunc
        Aria2MaxTries     = 5        # --max-tries
        Aria2RetryWait    = 5        # --retry-wait (seconds)
        Aria2Timeout      = 60       # --timeout (seconds)
    }
}

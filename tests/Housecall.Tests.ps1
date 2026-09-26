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

    It 'never uses a reserved key as an area letter' {
        foreach ($reserved in @('?', '0', 'L', 'Q')) {
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

Describe 'Findings' {
    It 'has a finding and an advice sentence, in both languages, for every finding id in the code' {
        $code = Get-Content (Join-Path $root 'src\checks\network.ps1') | Where-Object { $_ -match 'Set-HcFinding' }
        # The id right after "Set-HcFinding $r", or inside "{ 'id' }" when it is chosen by an if.
        $ids = @($code | ForEach-Object { [regex]::Matches($_, "(?:Set-HcFinding \`$r |\{ )'(\w+)'") | ForEach-Object { $_.Groups[1].Value } }) | Sort-Object -Unique
        $ids.Count | Should BeGreaterThan 10
        foreach ($lang in @('en', 'nl')) {
            foreach ($id in $ids) {
                $script:Strings[$lang]["finding.$id"] | Should Not BeNullOrEmpty
                $script:Strings[$lang]["advice.$id"] | Should Not BeNullOrEmpty
            }
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
                 @(Get-Item (Join-Path $root 'dev.ps1'), (Join-Path $root 'build.ps1'))
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

    Mock Get-HcNetworkFacts { New-FakeFacts }
    Mock Get-HcConnectionQuality { [pscustomobject]@{ Sent = 10; Lost = 0; AverageMs = 4 } }
    Mock Get-HcWifiDrops { 2 }
    Mock Get-HcSiteFacts { [pscustomobject]@{ Host = 'nu.nl'; HostsEntry = $null; Address = '1.2.3.4'; TcpMs = 12; HttpStatus = 200 } }

    It 'walks the menu in English without errors and ends on Q' {
        { Start-Housecall -Lang en -Answers @('A', '1', '', '0', 'F2', '', '?', '', 'zz', 'Q') } | Should Not Throw
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
}

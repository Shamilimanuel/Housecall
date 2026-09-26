<#
    Area A: Internet & Wi-Fi.

      A1  no internet at all          Test-HcInternet
      A2  Wi-Fi slow or drops         Test-HcInternet, then Test-HcConnectionQuality
      A3  one website will not load   Test-HcInternet, then Test-HcSite
      A4  email                       not built yet

    The chain in Test-HcInternet follows the path a packet takes: adapter,
    connection, address, router, internet, names (DNS), the web. The first
    link that fails is the finding; the links after it are skipped, because
    they cannot work without it.

    Everything is read with objects (Get-NetAdapter, Get-NetIPConfiguration),
    never by reading the text of ipconfig, because Windows translates that
    text. The one exception is netsh for the Wi-Fi name and signal, where
    only the untranslated parts are matched: "SSID" and a number with "%".
#>

$script:WeakSignal = 40      # % and below counts as weak
$script:TestHost = 'www.msftconnecttest.com'   # what Windows itself uses to test the internet

# ------------------------------------------------------------------- facts --

function Get-HcWifiInfo {
    $info = [pscustomobject]@{ Ssid = $null; Signal = $null }
    try {
        $text = & netsh.exe wlan show interfaces 2>$null
        foreach ($line in $text) {
            if ($line -match '^\s*SSID\s*:\s*(.+?)\s*$') { $info.Ssid = $Matches[1] }
            elseif ($line -match ':\s*(\d{1,3})\s*%\s*$') { $info.Signal = [int]$Matches[1] }
        }
    } catch { }
    $info
}

# The proxy Windows programs are told to use, or $null. Adware likes setting
# one, including an automatic-configuration script (AutoConfigURL).
function Get-HcProxy {
    try {
        $s = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($s.ProxyEnable -eq 1 -and $s.ProxyServer) { return [string]$s.ProxyServer }
        if ($s.AutoConfigURL) { return [string]$s.AutoConfigURL }
    } catch { }
    $null
}

function Test-HcDns {
    param([string]$Name = $script:TestHost)
    try {
        $answer = Resolve-DnsName -Name $Name -Type A -DnsOnly -QuickTimeout -ErrorAction Stop
        return @($answer | Where-Object { $_.IPAddress }).Count -gt 0
    } catch {
        return $false
    }
}

# 'ok', 'intercepted' (something else answered: a login page, a proxy) or
# 'failed'. Plain http on purpose: a Wi-Fi login page can only catch that.
function Get-HcWebTest {
    $saved = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $page = Invoke-WebRequest -Uri "http://$script:TestHost/connecttest.txt" -UseBasicParsing `
            -TimeoutSec 6 -MaximumRedirection 0 -ErrorAction Stop
        if ($page.Content -match 'Microsoft Connect Test') { return 'ok' }
        return 'intercepted'
    } catch {
        # A redirect (to a login page) also lands here, as an error.
        $response = $_.Exception.Response
        if ($null -ne $response) { return 'intercepted' }
        return 'failed'
    } finally {
        $ProgressPreference = $saved
    }
}

<#
    Reads everything A1 needs, in the order of the chain, and stops reading
    once a link is missing: there is no point waiting for a router that has
    no address to answer. Fields left $null were not checked.
#>
function Get-HcNetworkFacts {
    $f = [pscustomobject]@{
        Adapters = @(); Active = $null; Ssid = $null; Signal = $null
        IPv4 = $null; Dhcp = $null; Gateway = $null; DnsServers = @()
        Proxy = $null; GatewayMs = $null; InternetMs = $null; DnsOk = $null; Web = $null
    }

    $f.Adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -notmatch 'Bluetooth' } |
        ForEach-Object {
            [pscustomobject]@{
                Name    = $_.Name
                Status  = [string]$_.Status
                IsWifi  = ([string]$_.PhysicalMediaType -match '802\.11') -or ($_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN')
                IfIndex = $_.ifIndex
            }
        })
    $f.Proxy = Get-HcProxy

    $up = @($f.Adapters | Where-Object { $_.Status -eq 'Up' })
    if ($up.Count -eq 0) { return $f }

    # The adapter in use is the one with a router; otherwise the first one up.
    $chosen = $null
    foreach ($a in $up) {
        $config = Get-NetIPConfiguration -InterfaceIndex $a.IfIndex -ErrorAction SilentlyContinue
        if ($null -eq $chosen -or ($config.IPv4DefaultGateway -and -not $chosen.Config.IPv4DefaultGateway)) {
            $chosen = [pscustomobject]@{ Adapter = $a; Config = $config }
        }
    }
    $f.Active = $chosen.Adapter
    $config = $chosen.Config
    if ($config) {
        $f.IPv4 = @($config.IPv4Address | ForEach-Object { $_.IPAddress }) | Select-Object -First 1
        $f.Gateway = @($config.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) | Select-Object -First 1
        $f.DnsServers = @($config.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
    }
    $ipInterface = Get-NetIPInterface -InterfaceIndex $f.Active.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipInterface) { $f.Dhcp = ([string]$ipInterface.Dhcp -eq 'Enabled') }

    if ($f.Active.IsWifi) {
        $wifi = Get-HcWifiInfo
        $f.Ssid = $wifi.Ssid
        $f.Signal = $wifi.Signal
    }

    if (-not $f.IPv4 -or $f.IPv4 -like '169.254.*' -or -not $f.Gateway) { return $f }

    $f.GatewayMs = Get-HcPingMs $f.Gateway
    if ($f.GatewayMs -lt 0) { $f.GatewayMs = Get-HcPingMs $f.Gateway }   # one retry
    $f.InternetMs = Get-HcInternetMs
    if ($f.InternetMs -lt 0) { return $f }

    $f.DnsOk = Test-HcDns
    if ($f.DnsOk) { $f.Web = Get-HcWebTest }
    $f
}

# ------------------------------------------------------------------ verdict --

# A1. Walks the chain; see the top of this file.
function Test-HcInternet {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $f = $Facts

    # Adapter
    if (@($f.Adapters).Count -eq 0) {
        Add-HcLine $r problem (T 'net.noAdapter')
        Set-HcFinding $r 'noAdapter'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    if ($null -eq $f.Active) {
        $wifi = @($f.Adapters | Where-Object { $_.IsWifi }) | Select-Object -First 1
        $cable = @($f.Adapters | Where-Object { -not $_.IsWifi }) | Select-Object -First 1
        if ($wifi -and $wifi.Status -eq 'Disabled') {
            Add-HcLine $r problem (T 'net.wifiDisabled' $wifi.Name)
            Set-HcFinding $r 'wifiDisabled'
        } elseif ($wifi) {
            Add-HcLine $r problem (T 'net.wifiNotConnected')
            Set-HcFinding $r 'wifiNotConnected'
        } elseif ($cable.Status -eq 'Disabled') {
            Add-HcLine $r problem (T 'net.adapterOff' $cable.Name)
            Set-HcFinding $r 'adapterOff'
        } else {
            Add-HcLine $r problem (T 'net.cableUnplugged' $cable.Name)
            Set-HcFinding $r 'cableUnplugged'
        }
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'net.adapterUp' $f.Active.Name)

    # Connection
    $weak = $false
    if ($f.Active.IsWifi) {
        if ($f.Ssid -and $null -ne $f.Signal) {
            Add-HcLine $r ok (T 'net.wifiConnected' $f.Ssid $f.Signal)
            if ($f.Signal -le $script:WeakSignal) {
                Add-HcLine $r warn (T 'net.weakSignal' $f.Signal)
                $weak = $true
            }
        } else {
            Add-HcLine $r ok (T 'net.wifiConnectedNoSignal')
        }
    } else {
        Add-HcLine $r ok (T 'net.cableConnected')
    }
    if ($f.Proxy) { Add-HcLine $r warn (T 'net.proxy' $f.Proxy) }

    # Address
    if (-not $f.IPv4 -or $f.IPv4 -like '169.254.*') {
        $shown = if ($f.IPv4) { $f.IPv4 } else { T 'net.none' }
        Add-HcLine $r problem (T 'net.noAddress' $shown)
        Set-HcFinding $r 'noAddress'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    if ($f.Dhcp -eq $false) {
        Add-HcLine $r warn (T 'net.addressStatic' $f.IPv4)
    } else {
        Add-HcLine $r ok (T 'net.address' $f.IPv4)
    }

    # Router
    if (-not $f.Gateway) {
        Add-HcLine $r problem (T 'net.noGateway')
        Set-HcFinding $r 'noGateway'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    $internetOk = ($null -ne $f.InternetMs -and $f.InternetMs -ge 0)
    if ($f.GatewayMs -ge 0) {
        Add-HcLine $r ok (T 'net.gatewayOk' $f.Gateway $f.GatewayMs)
    } elseif ($internetOk) {
        # Some routers ignore pings. The internet getting through proves it works.
        Add-HcLine $r ok (T 'net.gatewayNoPing' $f.Gateway)
    } else {
        Add-HcLine $r problem (T 'net.gatewayDown' $f.Gateway)
        Set-HcFinding $r 'gatewayDown'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }

    # Internet
    if (-not $internetOk) {
        Add-HcLine $r problem (T 'net.internetDown')
        Set-HcFinding $r 'internetDown'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'net.internetOk' $f.InternetMs)

    # Names
    if ($f.DnsOk -eq $false) {
        $servers = if (@($f.DnsServers).Count) { @($f.DnsServers) -join ', ' } else { T 'net.none' }
        Add-HcLine $r problem (T 'net.dnsDown' $servers)
        Set-HcFinding $r 'dnsDown'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'net.dnsOk')

    # The web
    switch ($f.Web) {
        'ok'          { Add-HcLine $r ok (T 'net.webOk') }
        'intercepted' { Add-HcLine $r problem (T 'net.webIntercepted'); Set-HcFinding $r $(if ($f.Proxy) { 'proxy' } else { 'webIntercepted' }) }
        'failed'      { Add-HcLine $r problem (T 'net.webFailed'); Set-HcFinding $r $(if ($f.Proxy) { 'proxy' } else { 'webIntercepted' }) }
    }

    # Nothing broken: the smaller things, then all good.
    if ($f.Proxy) { Set-HcFinding $r 'proxy' }
    if ($weak) { Set-HcFinding $r 'weakSignal' }
    Set-HcFinding $r 'allGood'
    $r
}

# The findings after which the internet itself works, so A2 and A3 can go on.
$script:InternetWorks = @('allGood', 'weakSignal', 'proxy')

function Get-HcConnectionQuality {
    param([string]$Gateway, [int]$Count = 10)
    $times = @()
    $lost = 0
    for ($i = 0; $i -lt $Count; $i++) {
        $ms = Get-HcPingMs $Gateway 1000
        if ($ms -ge 0) { $times += $ms } else { $lost++ }
    }
    $average = if ($times.Count) { [int]($times | Measure-Object -Average).Average } else { -1 }
    [pscustomobject]@{ Sent = $Count; Lost = $lost; AverageMs = $average }
}

# Wi-Fi disconnects in the past 7 days (WLAN-AutoConfig event 8003), or $null
# when there is no Wi-Fi log to read. Sleep and shutdown count too, which is
# why the bar for calling it a problem is high.
function Get-HcWifiDrops {
    try {
        $filter = @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8003; StartTime = (Get-Date).AddDays(-7) }
        return @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop).Count
    } catch {
        if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { return 0 }
        return $null
    }
}

# A2. Only goes further than A1 when the internet works at all.
function Test-HcConnectionQuality {
    param([pscustomobject]$Facts, [pscustomobject]$Quality, $Drops)
    $r = Test-HcInternet $Facts
    if ($script:InternetWorks -notcontains $r.FindingId) { return $r }

    $base = $r.FindingId
    $r.FindingId = $null
    $lossPct = 0
    if ($Quality) {
        if ($Quality.Lost -eq 0) {
            Add-HcLine $r ok (T 'net.lossOk' $Quality.Sent $Quality.AverageMs)
        } else {
            $lossPct = [int](100 * $Quality.Lost / $Quality.Sent)
            $status = if ($lossPct -ge 10) { 'problem' } else { 'warn' }
            Add-HcLine $r $status (T 'net.loss' $Quality.Lost $Quality.Sent)
        }
    }
    if ($Facts.Active.IsWifi -and $null -ne $Drops) {
        $status = if ($Drops -ge 50) { 'problem' } else { 'ok' }
        Add-HcLine $r $status (T 'net.drops' $Drops)
    }

    if ($base -eq 'weakSignal') { Set-HcFinding $r 'weakSignal' }
    if ($lossPct -ge 10) { Set-HcFinding $r 'unstable' @($lossPct) }
    if ($Facts.Active.IsWifi -and $Drops -ge 50) { Set-HcFinding $r 'dropsMany' @($Drops) }
    if ($base -eq 'proxy') { Set-HcFinding $r 'proxy' }
    Set-HcFinding $r 'connHealthy'
    $r
}

# ------------------------------------------------------------- one website --

# "https://www.Marktplaats.nl/abc" -> "www.marktplaats.nl"; $null when it is
# not a web address at all.
function ConvertTo-HcHostName {
    param([string]$Text)
    $h = "$Text".Trim().ToLowerInvariant()
    $h = $h -replace '^[a-z][a-z0-9+.-]*://', ''
    $h = $h -replace '[/?#].*$', ''
    $h = $h -replace ':\d+$', ''
    if ($h -match '^([a-z0-9-]+\.)+[a-z]{2,}$') { return $h }
    $null
}

# A line in the hosts file that sends this site (or its www. twin) somewhere,
# as the address it is sent to, or $null.
function Get-HcHostsEntry {
    param([string]$HostName, [string]$Path = (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'))
    $names = @($HostName, ($HostName -replace '^www\.', ''), ('www.' + ($HostName -replace '^www\.', '')))
    try {
        foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            $clean = ($line -replace '#.*$', '').Trim()
            if (-not $clean) { continue }
            $parts = $clean -split '\s+'
            if ($parts.Count -lt 2) { continue }
            foreach ($name in $parts[1..($parts.Count - 1)]) {
                if ($names -contains $name.ToLowerInvariant()) { return $parts[0] }
            }
        }
    } catch { }
    $null
}

function Get-HcSiteFacts {
    param([string]$HostName)
    $s = [pscustomobject]@{ Host = $HostName; HostsEntry = $null; Address = $null; TcpMs = $null; HttpStatus = $null }
    $s.HostsEntry = Get-HcHostsEntry $HostName

    try {
        $s.Address = @([System.Net.Dns]::GetHostAddresses($HostName) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.IPAddressToString }) |
            Select-Object -First 1
    } catch { }
    if (-not $s.Address) { return $s }

    $s.TcpMs = Get-HcTcpMs $s.Address 443 3000
    if ($s.TcpMs -lt 0) { return $s }

    # Older Windows 10 builds still offer TLS 1.0 first; most sites refuse it.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $saved = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $page = Invoke-WebRequest -Uri "https://$HostName/" -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
        $s.HttpStatus = [int]$page.StatusCode
    } catch {
        $response = $_.Exception.Response
        $s.HttpStatus = if ($null -ne $response) { [int]$response.StatusCode } else { 0 }
    } finally {
        $ProgressPreference = $saved
    }
    $s
}

# A3, after A1 said the internet works. 4xx still means the site is alive
# (403 is often just bot protection); only 5xx and silence count against it.
function Test-HcSite {
    param([pscustomobject]$Site)
    $r = New-HcReport
    $h = $Site.Host
    Add-HcLine $r ok (T 'net.internetWorks')

    if ($Site.HostsEntry) {
        Add-HcLine $r problem (T 'site.hosts' $h $Site.HostsEntry)
        Set-HcFinding $r 'siteHosts'
    } else {
        Add-HcLine $r ok (T 'site.hostsOk' $h)
    }

    if (-not $Site.Address) {
        Add-HcLine $r problem (T 'site.dnsFail' $h)
        Set-HcFinding $r 'siteNotFound' @($h)
        return $r
    }
    Add-HcLine $r ok (T 'site.dnsOk' $h $Site.Address)

    if ($Site.TcpMs -lt 0) {
        Add-HcLine $r problem (T 'site.tcpFail' $h)
        Set-HcFinding $r 'siteBlocked'
        return $r
    }
    Add-HcLine $r ok (T 'site.tcpOk' $h $Site.TcpMs)

    if ($Site.HttpStatus -ge 500) {
        Add-HcLine $r problem (T 'site.httpError' $h $Site.HttpStatus)
        Set-HcFinding $r 'siteError' @($Site.HttpStatus)
    } elseif ($Site.HttpStatus -ge 200) {
        Add-HcLine $r ok (T 'site.httpOk' $h $Site.HttpStatus)
    } else {
        Add-HcLine $r problem (T 'site.httpNone' $h)
        Set-HcFinding $r 'siteBlocked'
    }
    Set-HcFinding $r 'siteOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcA1 {
    Write-Dim (T 'run.checking')
    Write-Host ''
    Write-HcReport (Test-HcInternet (Get-HcNetworkFacts))
}

function Invoke-HcA2 {
    Write-Dim (T 'run.checking')
    Write-Host ''
    $facts = Get-HcNetworkFacts
    $quality = $null
    $drops = $null
    if ($facts.GatewayMs -ge 0) { $quality = Get-HcConnectionQuality $facts.Gateway }
    if ($facts.Active.IsWifi) { $drops = Get-HcWifiDrops }
    Write-HcReport (Test-HcConnectionQuality $facts $quality $drops)
}

function Invoke-HcA3 {
    $hostName = $null
    while (-not $hostName) {
        $typed = Read-HcLine (T 'site.ask')
        if (-not "$typed".Trim() -or "$typed".Trim().ToUpperInvariant() -eq 'Q') { return }
        $hostName = ConvertTo-HcHostName $typed
        if (-not $hostName) { Write-Warn2 (T 'site.invalid' $typed) }
    }
    Write-Host ''
    Write-Dim (T 'run.checking')
    Write-Host ''

    $base = Test-HcInternet (Get-HcNetworkFacts)
    if ($script:InternetWorks -notcontains $base.FindingId) {
        # The internet itself is down: that is the answer, not the site.
        Write-HcReport $base
        return
    }
    Write-HcReport (Test-HcSite (Get-HcSiteFacts $hostName))
}

$script:ProblemHandlers['A1'] = 'Invoke-HcA1'
$script:ProblemHandlers['A2'] = 'Invoke-HcA2'
$script:ProblemHandlers['A3'] = 'Invoke-HcA3'

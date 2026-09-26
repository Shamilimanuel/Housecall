<#
    What Housecall needs to know about the PC before it shows the menu.
    Everything here is read-only and quick: the whole thing should finish in
    well under two seconds, even offline.
#>

function Test-HcAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# Milliseconds to open a TCP connection, or -1 when it does not get through
# within the timeout (unreachable, refused, firewall).
function Get-HcTcpMs {
    param([string]$Address, [int]$Port, [int]$TimeoutMs = 1500)
    $client = New-Object System.Net.Sockets.TcpClient
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        $attempt = $client.BeginConnect($Address, $Port, $null, $null)
        if ($attempt.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) {
            return [int][math]::Max(1, $clock.ElapsedMilliseconds)
        }
    } catch {
    } finally {
        $client.Close()
    }
    -1
}

# Milliseconds for one ping, or -1 for no reply.
function Get-HcPingMs {
    param([string]$Address, [int]$TimeoutMs = 1000)
    $ping = New-Object System.Net.NetworkInformation.Ping
    try {
        $reply = $ping.Send($Address, $TimeoutMs)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            return [int][math]::Max(1, $reply.RoundtripTime)
        }
    } catch {
    } finally {
        $ping.Dispose()
    }
    -1
}

# Milliseconds to reach the internet, or -1. Uses IP addresses, not names, so
# a broken DNS still counts as online -- telling those apart is A1's job.
function Get-HcInternetMs {
    foreach ($target in @(@('1.1.1.1', 443), @('8.8.8.8', 53))) {
        $ms = Get-HcTcpMs $target[0] $target[1]
        if ($ms -ge 0) { return $ms }
    }
    -1
}

function Test-HcOnline { (Get-HcInternetMs) -ge 0 }

<#
    Online is measured at the start, but a visit often fixes the internet
    (A1). Before anything that needs the relay, and after a fix, an offline
    PC is measured again, so the invoice and history still work once the
    internet is back. Costs up to 3 seconds, and only while offline.
#>
<#
    A copy on a USB stick does not update itself. When it runs from a file
    and the PC is online, it compares its build with version.txt on GitHub
    and returns a warning when they differ; $null when all is well, or when
    it cannot tell (offline, no answer, the dev version).
#>
function Get-HcOutdatedWarning {
    param([pscustomobject]$Environment)
    if (-not $script:HcFromFile -or "$script:HcBuild" -notmatch '^[0-9a-f]{12}$' -or -not $Environment.Online) { return $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $latest = "$((Invoke-WebRequest -Uri 'https://github.com/Shamilimanuel/Housecall/raw/main/version.txt' -UseBasicParsing -TimeoutSec 5).Content)".Trim()
    } catch { return $null }
    if ($latest -notmatch '^[0-9a-f]{12}$' -or $latest -eq $script:HcBuild) { return $null }
    T 'env.outdated'
}

function Update-HcOnline {
    param([pscustomobject]$Environment)
    if (-not $Environment.Online) { $Environment.Online = Test-HcOnline }
}

# "Windows 11 Home" rather than "Microsoft Windows 11 Home".
function Get-HcOsName {
    try {
        $caption = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).Caption
        return ($caption -replace '^Microsoft\s+', '').Trim()
    } catch {
        return 'Windows'
    }
}

function Get-HcEnvironment {
    [pscustomobject]@{
        IsWindows = ($env:OS -eq 'Windows_NT')
        PSVersion = $PSVersionTable.PSVersion
        Os        = Get-HcOsName
        IsAdmin   = Test-HcAdmin
        Online    = Test-HcOnline
    }
}

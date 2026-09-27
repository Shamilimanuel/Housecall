<#
    Area E: Windows & updates.

      E1  update stuck or failing      update service, last real update, failures,
                                       paused, restart pending, disk space, Windows 10
      E2  error message on the screen  activation, the clock, restart pending, recent crashes
      E3  will not shut down / restart restart pending (updates), fast startup, time since restart

    The update history comes from Windows Update's own COM object; titles
    are translated by Windows, so nothing here matches on them except the
    two KB numbers of Defender's daily definitions, which are left out: they
    install every day and would hide a Windows Update that is stuck.
#>

$script:DefenderKbs = 'KB2267602|KB4052623'
$script:StaleDays = 45
$script:UpdateSpaceGB = 10
$script:ClockToleranceSec = 300

# ------------------------------------------------------------------- facts --

function Test-HcRebootPending {
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
}

function Get-HcUpdateHistory {
    $h = [pscustomobject]@{ LastSuccess = $null; Failures = @(); Known = $false }
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $count = $searcher.GetTotalHistoryCount()
        $entries = @($searcher.QueryHistory(0, [Math]::Min($count, 100)) | Where-Object { $_.Operation -eq 1 -and $_.Title -notmatch $script:DefenderKbs })
        $h.Known = $true
        $h.LastSuccess = ($entries | Where-Object { $_.ResultCode -eq 2 } | Sort-Object Date -Descending | Select-Object -First 1).Date
        if ($h.LastSuccess) { $h.LastSuccess = $h.LastSuccess.ToLocalTime() }
        $since = (Get-Date).AddDays(-30)
        $h.Failures = @($entries | Where-Object { $_.ResultCode -in @(4, 5) -and $_.Date -gt $since } |
            Group-Object Title | ForEach-Object { $_.Group[0] } | Sort-Object Date -Descending | Select-Object -First 3 |
            ForEach-Object { [pscustomobject]@{ Title = ($_.Title -replace '\s+\(.*$', ''); Code = ('0x{0:X8}' -f $_.HResult) } })
    } catch { }
    $h
}

function Get-HcUpdateFacts {
    $pause = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue).PauseUpdatesExpiryTime
    $pausedUntil = $null
    if ($pause) { try { $pausedUntil = [datetime]::Parse($pause, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime() } catch { } }
    $service = Get-Service wuauserv -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Now             = Get-Date
        ServiceDisabled = ($service -and [string]$service.StartType -eq 'Disabled')
        History         = Get-HcUpdateHistory
        RebootPending   = Test-HcRebootPending
        PausedUntil     = $pausedUntil
        Windows10       = ([Environment]::OSVersion.Version.Build -lt 22000)
        Disk            = Get-HcSystemDisk
    }
}

# Seconds this PC's clock is off from internet time (the Date header of the
# page Windows itself uses to test the internet), or $null when offline.
function Get-HcClockOffset {
    try {
        $r = Invoke-WebRequest -Uri "http://$script:TestHost/connecttest.txt" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        $server = [datetime]::Parse($r.Headers['Date'], [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
        return [int]([datetime]::UtcNow - $server).TotalSeconds
    } catch {
        return $null
    }
}

# The time zone a client in these countries should have. Only compared by
# offset and summer time, so a zone with the same clock (Berlin for a Dutch
# client) is not called wrong. Countries not listed are not judged.
$script:CountryTimeZone = @{
    NL = 'W. Europe Standard Time'; DE = 'W. Europe Standard Time'; LU = 'W. Europe Standard Time'
    BE = 'Romance Standard Time'; FR = 'Romance Standard Time'; ES = 'Romance Standard Time'
    GB = 'GMT Standard Time'; IE = 'GMT Standard Time'
    SR = 'SA Eastern Standard Time'; AW = 'SA Western Standard Time'; CW = 'SA Western Standard Time'; BQ = 'SA Western Standard Time'
}

# The expected zone when the current one runs a different clock; $null when
# it is fine or the country is not known.
function Get-HcExpectedTimeZone {
    param([string]$Country, [string]$CurrentId)
    $expectedId = $script:CountryTimeZone[$Country]
    if (-not $expectedId -or -not $CurrentId) { return $null }
    try {
        $expected = [TimeZoneInfo]::FindSystemTimeZoneById($expectedId)
        $current = [TimeZoneInfo]::FindSystemTimeZoneById($CurrentId)
    } catch { return $null }
    if ($expected.BaseUtcOffset -eq $current.BaseUtcOffset -and $expected.SupportsDaylightSavingTime -eq $current.SupportsDaylightSavingTime) { return $null }
    $expected
}

function Get-HcErrorFacts {
    $activated = $null
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Stop | Select-Object -First 1
        if ($lic) { $activated = ($lic.LicenseStatus -eq 1) }
    } catch { }
    $crashes = @()
    try {
        $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = (Get-Date).AddDays(-3) } -ErrorAction Stop |
            Group-Object { (Split-Path -Leaf ([string]$_.Properties[0].Value)) -replace '\.exe$', '' } | Where-Object { $_.Name -notmatch $script:WindowsHelpers } |
            Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } })
    } catch { }
    [pscustomobject]@{
        Activated     = $activated
        ClockOffset   = Get-HcClockOffset
        TimeZone      = (Get-TimeZone -ErrorAction SilentlyContinue)
        Country       = (Get-ItemProperty 'HKCU:\Control Panel\International\Geo' -ErrorAction SilentlyContinue).Name
        AutoTimeOff   = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -ErrorAction SilentlyContinue).Type -eq 'NoSync')
        RebootPending = Test-HcRebootPending
        Crashes       = $crashes
    }
}

function Get-HcShutdownFacts {
    $os = Get-CimInstance Win32_OperatingSystem
    [pscustomobject]@{
        RebootPending = Test-HcRebootPending
        FastStartup   = ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -ErrorAction SilentlyContinue).HiberbootEnabled -eq 1)
        UptimeDays    = [int]((Get-Date) - $os.LastBootUpTime).TotalDays
    }
}

# ------------------------------------------------------------------ verdict --

# E1.
function Test-HcUpdates {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.Windows10) {
        Add-HcLine $r problem (T 'upd.windows10')
        $found['windows10'] = @()
    }
    if ($Facts.ServiceDisabled) {
        Add-HcLine $r problem (T 'upd.serviceDisabled')
        Add-HcAction $r 'enableUpdateService'
        $found['updateServiceDisabled'] = @()
    } else {
        Add-HcLine $r ok (T 'upd.serviceOk')
    }
    if ($Facts.PausedUntil -and $Facts.PausedUntil -gt $Facts.Now) {
        Add-HcLine $r warn (T 'upd.paused' (Format-HcDate $Facts.PausedUntil))
        Add-HcAction $r 'resumeUpdates'
        $found['updatesPaused'] = @(Format-HcDate $Facts.PausedUntil)
    }

    $h = $Facts.History
    if ($h.Known) {
        if ($h.LastSuccess) {
            $days = [int]($Facts.Now - $h.LastSuccess).TotalDays
            if ($days -gt $script:StaleDays) {
                Add-HcLine $r problem (T 'upd.lastOld' (Format-HcDate $h.LastSuccess) $days)
                $found['updatesStale'] = @($days)
            } else {
                Add-HcLine $r ok (T 'upd.last' (Format-HcDate $h.LastSuccess))
            }
        } else {
            Add-HcLine $r problem (T 'upd.never')
            $found['updatesStale'] = @('?')
        }
        foreach ($f in @($h.Failures)) { Add-HcLine $r problem (T 'upd.failed' $f.Title $f.Code) }
        if (@($h.Failures).Count) { $found['updateFailures'] = @(@($h.Failures)[0].Code) }
    } else {
        Add-HcLine $r skipped (T 'upd.historyUnknown')
    }
    if ($found['updateFailures'] -or $found['updatesStale']) { Add-HcAction $r 'resetUpdates' }

    if ($Facts.RebootPending) {
        Add-HcLine $r warn (T 'upd.rebootPending')
        $found['rebootPending'] = @()
    }
    if ($Facts.Disk.FreeGB -lt $script:UpdateSpaceGB) {
        Add-HcLine $r problem (T 'upd.noSpace' $Facts.Disk.Drive $Facts.Disk.FreeGB)
        $found['updateSpace'] = @($Facts.Disk.FreeGB)
    }

    Select-HcFinding $r $found @('updateServiceDisabled', 'windows10', 'updateSpace', 'updatesPaused', 'rebootPending', 'updateFailures', 'updatesStale') 'updatesOk'
    $r
}

# E2.
function Test-HcErrors {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.Activated -eq $false) {
        Add-HcLine $r problem (T 'err.notActivated')
        $found['notActivated'] = @()
    } elseif ($Facts.Activated) {
        Add-HcLine $r ok (T 'err.activated')
    }
    if ($null -eq $Facts.ClockOffset) {
        Add-HcLine $r skipped (T 'err.clockUnknown')
    } elseif ([Math]::Abs($Facts.ClockOffset) -gt $script:ClockToleranceSec) {
        Add-HcLine $r problem (T 'err.clockWrong' ([int]([Math]::Abs($Facts.ClockOffset) / 60)))
        Add-HcAction $r 'syncClock'
        $found['clockWrong'] = @([int]([Math]::Abs($Facts.ClockOffset) / 60))
    } else {
        Add-HcLine $r ok (T 'err.clockOk')
    }
    # The clock check above compares universal time, so a wrong time zone
    # passes it while the clock on screen is hours off.
    if ($Facts.PSObject.Properties['TimeZone'] -and $Facts.TimeZone) {
        $expected = Get-HcExpectedTimeZone $Facts.Country $Facts.TimeZone.Id
        if ($expected) {
            Add-HcLine $r problem (T 'err.timeZoneWrong' $Facts.TimeZone.DisplayName $expected.DisplayName)
            Add-HcAction $r 'setTimeZone' @{ Label = $expected.DisplayName; Id = $expected.Id; Previous = $Facts.TimeZone.Id }
            $found['wrongTimeZone'] = @($Facts.TimeZone.DisplayName, $expected.DisplayName)
        } else {
            Add-HcLine $r ok (T 'err.timeZone' $Facts.TimeZone.DisplayName)
        }
    }
    if ($Facts.PSObject.Properties['AutoTimeOff'] -and $Facts.AutoTimeOff) {
        Add-HcLine $r warn (T 'err.autoTimeOff')
        $found['autoTimeOff'] = @()
    }
    if ($Facts.RebootPending) {
        Add-HcLine $r warn (T 'upd.rebootPending')
        $found['rebootPending'] = @()
    }
    $crashes = @($Facts.Crashes)
    if ($crashes.Count) {
        foreach ($c in $crashes) { Add-HcLine $r warn (T 'err.crash' $c.Name $c.Count) }
        $found['recentCrash'] = @($crashes[0].Name)
    } else {
        Add-HcLine $r ok (T 'err.noCrash')
    }
    Add-HcAction $r 'repairWindows'
    Select-HcFinding $r $found @('clockWrong', 'wrongTimeZone', 'notActivated', 'rebootPending', 'recentCrash', 'autoTimeOff') 'errorsOk'
    $r
}

# E3.
function Test-HcShutdown {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    if ($Facts.RebootPending) {
        Add-HcLine $r warn (T 'upd.rebootPending')
        $found['rebootPending'] = @()
    } else {
        Add-HcLine $r ok (T 'sd.noPending')
    }
    if ($Facts.FastStartup) {
        Add-HcLine $r warn (T 'sd.fastStartup')
        Add-HcAction $r 'disableFastStartup'
        $found['fastStartup'] = @()
    }
    if ($Facts.UptimeDays -ge $script:UptimeDays) {
        Add-HcLine $r warn (T 'perf.uptimeLong' $Facts.UptimeDays)
        $found['longUptime'] = @($Facts.UptimeDays)
    } else {
        Add-HcLine $r ok (T 'perf.uptime' $Facts.UptimeDays)
    }
    Select-HcFinding $r $found @('rebootPending', 'fastStartup', 'longUptime') 'shutdownOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcE1 { { Test-HcUpdates (Get-HcUpdateFacts) } }
function Invoke-HcE2 { { Test-HcErrors (Get-HcErrorFacts) } }
function Invoke-HcE3 { { Test-HcShutdown (Get-HcShutdownFacts) } }

$script:ProblemHandlers['E1'] = 'Invoke-HcE1'
$script:ProblemHandlers['E2'] = 'Invoke-HcE2'
$script:ProblemHandlers['E3'] = 'Invoke-HcE3'

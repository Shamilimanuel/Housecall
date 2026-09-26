<#
    Area F: Safety & scams.

      F1  a pop-up says I have a virus         notifications, antivirus, proxy, hosts file
      F2  someone called and got into my PC    remote-access programs, scheduled tasks, antivirus, notifications
      F3  full security check                  all of the above

    The scam this is built around: a caller (or a fake virus pop-up with a
    phone number) talks the client into installing AnyDesk, TeamViewer or
    similar, then takes over the PC and the bank account. So F2 looks for
    remote-access programs installed, downloaded, running or merely used
    before, and dates each one: "installed two days ago" is what matters.

    Everything is read-only and works without admin. Nothing is ever removed
    here -- plenty of families use these tools on purpose. Housecall reports
    and asks; removal (Phase 2) always needs the client's yes.
#>

$script:RecentDays = 30

# Remote-access programs. Pattern matches the installed name and service
# names; Processes are process names without .exe; Traces are folders a tool
# leaves behind even after it is removed or was only run once.
$script:RemoteToolList = @(
    @{ Name = 'AnyDesk';               Pattern = 'AnyDesk';                      Processes = @('AnyDesk');                          Traces = @('%APPDATA%\AnyDesk', '%ProgramData%\AnyDesk') }
    @{ Name = 'TeamViewer';            Pattern = 'TeamViewer';                   Processes = @('TeamViewer', 'TeamViewer_Service', 'tv_w32', 'tv_x64'); Traces = @('%APPDATA%\TeamViewer') }
    @{ Name = 'UltraViewer';           Pattern = 'UltraViewer';                  Processes = @('UltraViewer_Desktop', 'UltraViewer_Service'); Traces = @() }
    @{ Name = 'RustDesk';              Pattern = 'RustDesk';                     Processes = @('rustdesk');                         Traces = @('%APPDATA%\RustDesk') }
    @{ Name = 'HopToDesk';             Pattern = 'HopToDesk';                    Processes = @('HopToDesk');                        Traces = @('%APPDATA%\HopToDesk') }
    @{ Name = 'Supremo';               Pattern = '^Supremo';                     Processes = @('Supremo', 'SupremoService', 'SupremoHelper'); Traces = @() }
    @{ Name = 'ScreenConnect';         Pattern = 'ScreenConnect';                Processes = @('ScreenConnect.ClientService', 'ScreenConnect.WindowsClient'); Traces = @() }
    @{ Name = 'LogMeIn / GoTo';        Pattern = 'LogMeIn(?! Hamachi)|GoTo Resolve|GoToAssist'; Processes = @('LogMeIn', 'LMIGuardianSvc', 'GoToAssist'); Traces = @() }
    @{ Name = 'Splashtop';             Pattern = 'Splashtop';                    Processes = @('SRService', 'SRManager', 'strwinclt');  Traces = @() }
    @{ Name = 'AeroAdmin';             Pattern = 'AeroAdmin';                    Processes = @('AeroAdmin');                        Traces = @() }
    @{ Name = 'Ammyy Admin';           Pattern = 'Ammyy';                        Processes = @('AA_v3', 'Ammyy');                   Traces = @() }
    @{ Name = 'RemotePC';              Pattern = 'RemotePC';                     Processes = @('RemotePCService', 'RemotePCDesktop'); Traces = @() }
    @{ Name = 'Zoho Assist';           Pattern = 'Zoho Assist';                  Processes = @('ZA_Connect', 'ZohoURS');            Traces = @() }
    @{ Name = 'Chrome Remote Desktop'; Pattern = 'Chrome Remote Desktop';        Processes = @('remoting_host');                    Traces = @() }
    @{ Name = 'DWService';             Pattern = 'DWAgent|DWService';            Processes = @('dwagent', 'dwagsvc');               Traces = @() }
    @{ Name = 'VNC';                   Pattern = 'VNC';                          Processes = @('winvnc', 'tvnserver', 'vncserver'); Traces = @() }
    @{ Name = 'Getscreen.me';          Pattern = 'Getscreen';                    Processes = @('getscreen');                        Traces = @() }
    @{ Name = 'ISL Light';             Pattern = 'ISL Light|ISL AlwaysOn';       Processes = @('ISLLight', 'ISLAlwaysOnMonitor');   Traces = @() }
    @{ Name = 'Remote Utilities';      Pattern = 'Remote Utilities';             Processes = @('rutserv', 'rfusclient');            Traces = @() }
    @{ Name = 'Atera';                 Pattern = 'AteraAgent|Atera Networks';    Processes = @('AteraAgent');                       Traces = @() }
    # Built into Windows: nothing to find installed, but running means a session is on.
    @{ Name = 'Quick Assist';          Pattern = $null;                          Processes = @('QuickAssist');                      Traces = @() }
)

# Browsers built on Chrome keep site permissions in a Preferences file per
# profile. Firefox keeps them in a database this cannot read yet.
$script:BrowserRoots = @(
    @{ Name = 'Chrome';   Path = '%LOCALAPPDATA%\Google\Chrome\User Data' }
    @{ Name = 'Edge';     Path = '%LOCALAPPDATA%\Microsoft\Edge\User Data' }
    @{ Name = 'Brave';    Path = '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data' }
    @{ Name = 'Opera';    Path = '%APPDATA%\Opera Software\Opera Stable' }
    @{ Name = 'Opera GX'; Path = '%APPDATA%\Opera Software\Opera GX Stable' }
)

# Sites that people really do allow to send notifications. They are listed
# as fine; everything else is flagged, because that is where fake virus
# warnings come from. Matched on the host name, subdomains included.
$script:KnownNotificationSites = @(
    'mail.google.com', 'calendar.google.com', 'meet.google.com', 'chat.google.com', 'youtube.com'
    'web.whatsapp.com', 'web.telegram.org', 'messenger.com', 'facebook.com', 'instagram.com'
    'outlook.live.com', 'outlook.office.com', 'outlook.office365.com', 'teams.microsoft.com', 'teams.live.com'
    'discord.com', 'x.com', 'linkedin.com', 'marktplaats.nl', 'nu.nl', 'nos.nl'
    'localhost', '127.0.0.1'
)

function Test-HcKnownSite {
    param([string]$Site)
    $h = ($Site -replace '^[a-z]+://', '' -replace '[:/].*$', '').ToLowerInvariant()
    foreach ($known in $script:KnownNotificationSites) {
        if ($h -eq $known -or $h.EndsWith('.' + $known)) { return $true }
    }
    $false
}

# Which finding wins when several are found: the most urgent first.
$script:SecurityPriority = @(
    'remoteActive', 'remoteRecent', 'defenderOff', 'suspiciousTask', 'notifySites',
    'proxy', 'hostsRedirect', 'avOld', 'threatsFound', 'remoteOld', 'unknownTask'
)

# ------------------------------------------------------------------- facts --

function ConvertFrom-HcInstallDate {
    param([string]$Text)
    $d = [datetime]::MinValue
    if ($Text -and [datetime]::TryParseExact($Text.Trim(), 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { return $d }
    $null
}

function Get-HcDownloadFolders {
    $folders = @()
    try { $folders += (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path } catch { }
    $folders += Join-Path $env:USERPROFILE 'Downloads'
    $folders += [Environment]::GetFolderPath('Desktop')
    @($folders | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)
}

function Get-HcRemoteTools {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installed = @(Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
    $processes = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName })
    $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Where-Object { $_.StartMode -eq 'Auto' } | ForEach-Object { "$($_.Name) $($_.DisplayName) $($_.PathName)" })
    $runKeys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    $runValues = @(foreach ($k in $runKeys) {
        $item = Get-ItemProperty $k -ErrorAction SilentlyContinue
        if ($item) { $item.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "$($_.Name) $($_.Value)" } }
    })
    $downloads = @(foreach ($folder in Get-HcDownloadFolders) {
        Get-ChildItem -LiteralPath $folder -File -Filter *.exe -ErrorAction SilentlyContinue
    })

    foreach ($tool in $script:RemoteToolList) {
        $found = [pscustomobject]@{
            Name = $tool.Name; Installed = $false; InstallDate = $null; Running = $false
            AutoStart = $false; Downloaded = $null; LastUsed = $null
        }
        $p = $tool.Pattern
        if ($p) {
            $entry = $installed | Where-Object { $_.DisplayName -match $p } | Select-Object -First 1
            if ($entry) {
                $found.Installed = $true
                $found.InstallDate = ConvertFrom-HcInstallDate $entry.InstallDate
            }
            $found.AutoStart = [bool](@($services + $runValues) -match $p)
            $file = $downloads | Where-Object { $_.Name -match $p } | Sort-Object CreationTime -Descending | Select-Object -First 1
            if ($file) { $found.Downloaded = $file.CreationTime }
        }
        $found.Running = [bool]($processes | Where-Object { $tool.Processes -contains $_ })
        foreach ($trace in $tool.Traces) {
            $folder = [Environment]::ExpandEnvironmentVariables($trace)
            if (Test-Path -LiteralPath $folder) {
                $when = (Get-Item -LiteralPath $folder).LastWriteTime
                if ($null -eq $found.LastUsed -or $when -gt $found.LastUsed) { $found.LastUsed = $when }
            }
        }
        if ($found.Installed -or $found.Running -or $found.AutoStart -or $found.Downloaded -or $found.LastUsed) { $found }
    }
}

# Sites allowed to send notifications, from every Chrome-family profile.
# Preferences can be large, so this uses the .NET JSON reader with the size
# limit lifted instead of ConvertFrom-Json, which fails on big files in 5.1.
function Get-HcNotificationSites {
    try { Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop } catch { return @() }
    $json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $json.MaxJsonLength = [int]::MaxValue

    foreach ($browser in $script:BrowserRoots) {
        $root = [Environment]::ExpandEnvironmentVariables($browser.Path)
        if (-not (Test-Path -LiteralPath $root)) { continue }
        # Opera keeps Preferences in the root; the others in one folder per profile.
        $files = @(Get-Item -LiteralPath (Join-Path $root 'Preferences') -ErrorAction SilentlyContinue) +
                 @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                    ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'Preferences') -ErrorAction SilentlyContinue })
        foreach ($file in $files) {
            try {
                $prefs = $json.DeserializeObject([IO.File]::ReadAllText($file.FullName))
                $sites = $prefs['profile']['content_settings']['exceptions']['notifications']
            } catch { continue }
            if ($null -eq $sites) { continue }
            foreach ($key in $sites.Keys) {
                if ($sites[$key]['setting'] -ne 1) { continue }
                $since = $null
                try {
                    # Microseconds since 1601, the same epoch as a Windows file time.
                    $since = [DateTime]::FromFileTimeUtc([int64]$sites[$key]['last_modified'] * 10).ToLocalTime()
                } catch { }
                [pscustomobject]@{ Browser = $browser.Name; Site = ($key -split ',')[0] -replace ':443$', ''; Since = $since }
            }
        }
    }
}

# The antivirus Windows Security reports, and for Defender its update age and
# recent detections. productState's middle byte is 0x10 or 0x11 when on; the
# last byte is 0x00 when up to date.
function Get-HcAntivirus {
    $av = [pscustomobject]@{ Known = $false; Name = $null; Enabled = $false; Outdated = $false; DaysOld = $null; Threats = $null }
    try {
        $products = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)
        $av.Known = $true
        foreach ($p in $products) {
            $hex = '{0:X6}' -f [int]$p.productState
            if ($hex.Substring(2, 2) -in @('10', '11')) {
                $av.Enabled = $true
                $av.Name = $p.displayName
                $av.Outdated = ($hex.Substring(4, 2) -ne '00')
                break
            }
        }
        if (-not $av.Name -and $products.Count) { $av.Name = $products[0].displayName }
    } catch { }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if ($av.Name -match 'Defender' -or -not $av.Known) {
            $av.Known = $true
            if (-not $av.Name) { $av.Name = 'Microsoft Defender' }
            $av.Enabled = [bool]($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled)
            if ($mp.AntivirusSignatureLastUpdated) {
                $av.DaysOld = [int]((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
                $av.Outdated = ($av.DaysOld -gt 7)
            }
        }
        $av.Threats = @(Get-MpThreatDetection -ErrorAction Stop |
            Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-$script:RecentDays) }).Count
    } catch { }
    $av
}

<#
    Scheduled tasks outside Windows' own folder whose command looks like
    malware. Two levels:
      strong  a script host with an encoded, hidden or downloading command,
              or a program run from Temp, Public or Downloads
      weak    a script host running a script file from the user's folders --
              legitimate tools do this too, so it is only "check this"
#>
$script:ScriptHosts = 'powershell|pwsh|mshta|wscript|cscript|cmd|rundll32|regsvr32'

function Get-HcTaskLevel {
    param([string]$Execute, [string]$Arguments)
    $exe = [IO.Path]::GetFileNameWithoutExtension(($Execute -replace '"', ''))
    $isHost = $exe -match "^($script:ScriptHosts)$"
    if ($isHost -and $Arguments -match '-e(nc|ncodedcommand)?\s|FromBase64|https?://|-w(indowstyle)?\s+hid|DownloadString|Invoke-WebRequest|iwr |\biex\b') { return 'strong' }
    if ($Execute -match '\\(Temp|Users\\Public|Downloads)\\') { return 'strong' }
    if ($isHost -and $Arguments -match '\\(AppData|ProgramData|Users)\\') { return 'weak' }
    $null
}

function Get-HcSuspiciousTasks {
    foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' })) {
        foreach ($action in @($task.Actions | Where-Object { $_.Execute })) {
            $level = Get-HcTaskLevel $action.Execute $action.Arguments
            if ($level) {
                $command = ("$($action.Execute) $($action.Arguments)").Trim()
                if ($command.Length -gt 70) { $command = $command.Substring(0, 67) + '...' }
                [pscustomobject]@{ Name = $task.TaskName; Command = $command; Level = $level }
                break
            }
        }
    }
}

# Hosts-file lines that send a name somewhere, other than the usual localhost.
function Get-HcHostsRedirects {
    param([string]$Path = (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'))
    try {
        foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            $clean = ($line -replace '#.*$', '').Trim()
            if (-not $clean) { continue }
            $parts = $clean -split '\s+'
            if ($parts.Count -lt 2) { continue }
            foreach ($name in $parts[1..($parts.Count - 1)]) {
                if ($name -notmatch '^(localhost|localhost\.localdomain|broadcasthost)$') { "$name -> $($parts[0])" }
            }
        }
    } catch { }
}

# Reads only the parts asked for: F1 does not need to wait for the task list.
function Get-HcSecurityFacts {
    param([string[]]$Parts)
    $f = [pscustomobject]@{
        Now = Get-Date; RemoteTools = $null; Tasks = $null; Antivirus = $null
        Notifications = $null; Proxy = $null; Hosts = $null
    }
    if ($Parts -contains 'remote')        { $f.RemoteTools = @(Get-HcRemoteTools) }
    if ($Parts -contains 'tasks')         { $f.Tasks = @(Get-HcSuspiciousTasks) }
    if ($Parts -contains 'antivirus')     { $f.Antivirus = Get-HcAntivirus }
    if ($Parts -contains 'notifications') { $f.Notifications = @(Get-HcNotificationSites) }
    if ($Parts -contains 'proxy')         { $f.Proxy = Get-HcProxy }
    if ($Parts -contains 'hosts')         { $f.Hosts = @(Get-HcHostsRedirects) }
    $f
}

# ------------------------------------------------------------------ verdict --

function Format-HcDate {
    param([datetime]$Date)
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }
    $Date.ToString('d MMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture))
}

<#
    One verdict for F1, F2 and F3: $Parts says which sections to show, in
    that order. Every section adds its lines and names what it found; the
    finding is then the most urgent one by $script:SecurityPriority, or
    $CleanId when nothing was found.
#>
function Test-HcSecurity {
    param([pscustomobject]$Facts, [string[]]$Parts, [string]$CleanId)
    $r = New-HcReport
    $found = @{}
    $recent = $Facts.Now.AddDays(-$script:RecentDays)

    foreach ($part in $Parts) {
        switch ($part) {
            'remote' {
                $tools = @($Facts.RemoteTools)
                if ($tools.Count -eq 0) { Add-HcLine $r ok (T 'sec.noRemote'); break }
                foreach ($t in $tools) {
                    $bits = @()
                    if ($t.Installed) {
                        $bits += $(if ($t.InstallDate) { T 'sec.installed' (Format-HcDate $t.InstallDate) } else { T 'sec.installedUnknown' })
                    }
                    if ($t.Downloaded) { $bits += T 'sec.downloaded' (Format-HcDate $t.Downloaded) }
                    if ($t.Running) { $bits += T 'sec.running' }
                    if ($t.AutoStart) { $bits += T 'sec.autoStart' }
                    if ($t.LastUsed -and -not $t.Running) { $bits += T 'sec.lastUsed' (Format-HcDate $t.LastUsed) }

                    $newest = @($t.InstallDate, $t.Downloaded, $t.LastUsed) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
                    $isRecent = ($newest -and $newest -gt $recent)
                    $status = if ($t.Running -or $isRecent) { 'problem' } else { 'warn' }
                    Add-HcLine $r $status ('{0}: {1}' -f $t.Name, ($bits -join ', '))

                    if ($t.Running -and -not $found['remoteActive']) { $found['remoteActive'] = @($t.Name) }
                    elseif ($isRecent -and -not $found['remoteRecent']) { $found['remoteRecent'] = @($t.Name, (Format-HcDate $newest)) }
                    elseif (-not $found['remoteOld']) { $found['remoteOld'] = @($t.Name) }
                }
            }
            'tasks' {
                $tasks = @($Facts.Tasks)
                if ($tasks.Count -eq 0) { Add-HcLine $r ok (T 'sec.noTasks'); break }
                foreach ($t in $tasks) {
                    $status = if ($t.Level -eq 'strong') { 'problem' } else { 'warn' }
                    Add-HcLine $r $status (T 'sec.task' $t.Name $t.Command)
                    $id = if ($t.Level -eq 'strong') { 'suspiciousTask' } else { 'unknownTask' }
                    if (-not $found[$id]) { $found[$id] = @($t.Name) }
                }
            }
            'antivirus' {
                $av = $Facts.Antivirus
                if ($null -eq $av -or -not $av.Known) { Add-HcLine $r skipped (T 'sec.avUnknown'); break }
                if (-not $av.Enabled) {
                    Add-HcLine $r problem (T 'sec.avOff')
                    $found['defenderOff'] = @()
                } elseif ($av.Outdated) {
                    $text = if ($av.DaysOld) { T 'sec.avOld' $av.Name $av.DaysOld } else { T 'sec.avOutdated' $av.Name }
                    Add-HcLine $r warn $text
                    $found['avOld'] = @()
                } else {
                    Add-HcLine $r ok (T 'sec.avOk' $av.Name)
                }
                if ($av.Threats -gt 0) {
                    Add-HcLine $r warn (T 'sec.threats' $av.Threats)
                    $found['threatsFound'] = @($av.Threats)
                }
            }
            'notifications' {
                $sites = @($Facts.Notifications)
                $known = @($sites | Where-Object { Test-HcKnownSite $_.Site })
                $unknown = @($sites | Where-Object { -not (Test-HcKnownSite $_.Site) })
                if ($known.Count) {
                    $names = @($known | ForEach-Object { $_.Site -replace '^[a-z]+://', '' } | Sort-Object -Unique) -join ', '
                    Add-HcLine $r ok (T 'sec.notifyKnown' $names)
                }
                if ($unknown.Count -eq 0) {
                    if (-not $known.Count) { Add-HcLine $r ok (T 'sec.notifyNone') }
                    break
                }
                foreach ($s in $unknown) {
                    $text = if ($s.Since) { T 'sec.notifySite' $s.Site $s.Browser (Format-HcDate $s.Since) } else { T 'sec.notifySiteNoDate' $s.Site $s.Browser }
                    Add-HcLine $r warn $text
                }
                $found['notifySites'] = @($unknown.Count)
            }
            'proxy' {
                if ($Facts.Proxy) {
                    Add-HcLine $r warn (T 'net.proxy' $Facts.Proxy)
                    $found['proxy'] = @()
                } else {
                    Add-HcLine $r ok (T 'sec.noProxy')
                }
            }
            'hosts' {
                $lines = @($Facts.Hosts)
                if ($lines.Count -eq 0) { Add-HcLine $r ok (T 'sec.hostsOk'); break }
                $shown = ($lines | Select-Object -First 3) -join ', '
                if ($lines.Count -gt 3) { $shown += ', ...' }
                Add-HcLine $r warn (T 'sec.hostsRedirect' $lines.Count $shown)
                $found['hostsRedirect'] = @()
            }
        }
    }

    foreach ($id in $script:SecurityPriority) {
        if ($found.ContainsKey($id)) { Set-HcFinding $r $id $found[$id]; break }
    }
    Set-HcFinding $r $CleanId
    $r
}

# ---------------------------------------------------------------- handlers --

$script:SecurityChecks = @{
    F1 = @{ Parts = @('notifications', 'antivirus', 'proxy', 'hosts');                  Clean = 'cleanPopup' }
    F2 = @{ Parts = @('remote', 'tasks', 'antivirus', 'notifications');                 Clean = 'cleanCall' }
    F3 = @{ Parts = @('remote', 'tasks', 'antivirus', 'notifications', 'proxy', 'hosts'); Clean = 'cleanAll' }
}

function Invoke-HcSecurityCheck {
    param([string]$Code)
    $plan = $script:SecurityChecks[$Code]
    Write-Dim (T 'run.checking')
    Write-Host ''
    Write-HcReport (Test-HcSecurity (Get-HcSecurityFacts $plan.Parts) $plan.Parts $plan.Clean)
}

function Invoke-HcF1 { Invoke-HcSecurityCheck 'F1' }
function Invoke-HcF2 { Invoke-HcSecurityCheck 'F2' }
function Invoke-HcF3 { Invoke-HcSecurityCheck 'F3' }

$script:ProblemHandlers['F1'] = 'Invoke-HcF1'
$script:ProblemHandlers['F2'] = 'Invoke-HcF2'
$script:ProblemHandlers['F3'] = 'Invoke-HcF3'

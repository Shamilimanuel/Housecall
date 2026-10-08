<#
    Phase 7, batch 3 (6 Oct 2026), and B7 (same day, from a real PC).

      B7  the screen goes black, games crash
                                  graphics driver resets (TDR) in 30 days,
                                  the driver's age, screens with different
                                  refresh rates, moving wallpapers and
                                  overlays, fatal hardware errors (WHEA)

      D5  the PC switches off or restarts by itself
                                  the System log of 30 days: unexpected
                                  power-offs (Kernel-Power 41), blue screens,
                                  and restarts started by Windows Update
                                  (User32 1074) against the active hours
      D6  the PC gets hot or noisy
                                  what uses the processor now, the busiest
                                  programs, a performance power plan on a
                                  laptop; the rest is dust and air: steps
      E6  installing a program does not work
                                  S mode, "apps from the Store only", Smart
                                  App Control, free space, the Windows
                                  Installer service, an account without
                                  administrator rights, a waiting restart
      F5  the browser is hijacked
                                  per Chrome-family browser and profile: the
                                  search engine, the start pages, extensions
                                  not from the store, and policies that say
                                  "managed by your organisation"

    Read-only; Housecall does not edit a browser's settings file (decided
    26 Sep: an open browser overwrites it, a broken one can reset the
    profile), so the fixes open the browser's own reset and extension pages.
#>

# ------------------------------------------------- D5: off or restarting --

$script:UpdateProcesses = 'TrustedInstaller|MoUsoCoreWorker|usoclient|wuauclt|UpdateOrchestrator|svchost'

function Get-HcRestartFacts {
    $since = (Get-Date).AddDays(-30)
    $read = { param($filter) try { @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop) } catch { @() } }
    $off = & $read @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since }
    $blue = & $read @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since }
    $planned = & $read @{ LogName = 'System'; ProviderName = 'User32'; Id = 1074; StartTime = $since }
    $byUpdate = @($planned | Where-Object { "$($_.Properties[0].Value)" -match $script:UpdateProcesses })
    $ux = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Off            = $off.Count
        LastOff        = $(if ($off.Count) { ($off | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated })
        BlueScreens    = $blue.Count
        UpdateRestarts = $byUpdate.Count
        OtherRestarts  = $planned.Count - $byUpdate.Count
        ActiveStart    = $(if ($null -ne $ux.ActiveHoursStart) { [int]$ux.ActiveHoursStart })
        ActiveEnd      = $(if ($null -ne $ux.ActiveHoursEnd) { [int]$ux.ActiveHoursEnd })
    }
}

function Test-HcRestarts {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $culture = [Globalization.CultureInfo]::GetCultureInfo($(if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }))
    if ($Facts.Off) {
        Add-HcLine $r problem (T 'rst.off' $Facts.Off $Facts.LastOff.ToString('d MMM HH:mm', $culture))
        $found['unexpectedOff'] = @($Facts.Off)
    } else { Add-HcLine $r ok (T 'rst.offNone') }
    if ($Facts.BlueScreens) {
        Add-HcLine $r problem (T 'rst.blue' $Facts.BlueScreens)
        $found['blueScreenRestarts'] = @($Facts.BlueScreens)
    } else { Add-HcLine $r ok (T 'rst.blueNone') }
    $hours = if ($null -ne $Facts.ActiveStart -and $null -ne $Facts.ActiveEnd) { T 'rst.hours' $Facts.ActiveStart $Facts.ActiveEnd } else { '' }
    if ($Facts.UpdateRestarts) {
        Add-HcLine $r warn ((T 'rst.update' $Facts.UpdateRestarts) + $hours)
        Add-HcAction $r 'openActiveHours'
        $found['updateRestarts'] = @($Facts.UpdateRestarts)
    } else { Add-HcLine $r ok ((T 'rst.updateNone') + $hours) }
    if ($Facts.OtherRestarts) { Add-HcLine $r ok (T 'rst.other' $Facts.OtherRestarts) }
    Select-HcFinding $r $found @('unexpectedOff', 'blueScreenRestarts', 'updateRestarts') 'restartsOk'
    $r
}

# ---------------------------------------------------- D6: hot or noisy --

$script:HotCpuPercent = 60

function Get-HcHeatFacts {
    $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $plan = $null
    try { if ("$(& powercfg.exe /getactivescheme)" -match '\(([^)]+)\)\s*$') { $plan = $Matches[1] } } catch { }
    $schemeGuid = $null
    try { if ("$(& powercfg.exe /getactivescheme)" -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $schemeGuid = $Matches[1] } } catch { }
    [pscustomobject]@{
        Laptop = [bool]@($chassis | Where-Object { $_ -in $script:LaptopChassis }).Count
        Cpu    = [int](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue).PercentProcessorTime
        Busy   = @(Get-HcBusyProcesses)
        Plan   = $plan
        # High performance and Ultimate performance: Windows' own scheme ids.
        PerformancePlan = ($schemeGuid -in @('8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'e9a42b02-d5df-448d-aa00-03f14749eb61') -or "$plan" -match 'performance|prestaties')
    }
}

function Test-HcHeat {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $top = @($Facts.Busy | Where-Object { $_.Name -notmatch $script:SystemProcess }) | Select-Object -First 3
    if ($Facts.Cpu -ge $script:HotCpuPercent) {
        $who = if ($top) { $top[0].Name } else { '?' }
        Add-HcLine $r problem (T 'heat.cpu' $Facts.Cpu)
        $found['hotBusy'] = @($Facts.Cpu, $who)
    } else {
        Add-HcLine $r ok (T 'heat.cpuOk' $Facts.Cpu)
    }
    foreach ($p in $top) { if ($p.Cpu -ge 5) { Add-HcLine $r ok (T 'heat.process' $p.Name $p.Cpu) } }
    $hog = @($top | Where-Object { $_.Cpu -ge 30 }) | Select-Object -First 1
    if ($hog) { Add-HcAction $r 'closeProcess' @{ Label = $hog.Name; Name = $hog.Name } }
    if ($Facts.Plan) {
        if ($Facts.Laptop -and $Facts.PerformancePlan) {
            Add-HcLine $r warn (T 'heat.planFast' $Facts.Plan)
            Add-HcAction $r 'openPowerSettings'
            $found['hotPlan'] = @($Facts.Plan)
        } else {
            Add-HcLine $r ok (T 'heat.plan' $Facts.Plan)
        }
    }
    Select-HcFinding $r $found @('hotBusy', 'hotPlan') 'hotDust'
    $r
}

# ------------------------------------------- E6: installing does not work --

$script:InstallFreeGB = 5

function Get-HcInstallFacts {
    $ci = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction SilentlyContinue
    $aic = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -ErrorAction SilentlyContinue).AicEnabled
    $msi = Get-Service -Name msiserver -ErrorAction SilentlyContinue
    # whoami, because .NET leaves out Administrators while it is "for deny
    # only" (an administrator without an administrator window).
    $groups = "$(& whoami.exe /groups /fo csv /nh 2>$null)"
    if (-not $groups) { $groups = (@([Security.Principal.WindowsIdentity]::GetCurrent().Groups | ForEach-Object { "`"$($_.Value)`"" }) -join ',') }
    [pscustomobject]@{
        SMode         = ($ci.SkuPolicyRequired -eq 1)
        SmartApp      = $(if ($null -ne $ci.VerifiedAndReputablePolicyState) { [int]$ci.VerifiedAndReputablePolicyState })
        AppSource     = "$aic"
        FreeGB        = $(if ($d = Get-HcSystemDisk) { $d.FreeGB })
        InstallerOff  = ($msi -and "$($msi.StartType)" -eq 'Disabled')
        AdminAccount  = ($groups -match '"S-1-5-32-544"')
        RebootPending = ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
    }
}

function Test-HcInstall {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    if ($Facts.SMode) { Add-HcLine $r problem (T 'ins.sMode'); $found['installSMode'] = @() }
    switch -Regex ($Facts.AppSource) {
        '^StoreOnly$'                  { Add-HcLine $r problem (T 'ins.storeOnly'); Add-HcAction $r 'openAppSource'; $found['installStoreOnly'] = @() }
        '^(Recommendations|PreferStore)$' { Add-HcLine $r warn (T 'ins.storeWarn'); Add-HcAction $r 'openAppSource' }
        default                        { if (-not $Facts.SMode) { Add-HcLine $r ok (T 'ins.anywhere') } }
    }
    if ($Facts.SmartApp -eq 1) { Add-HcLine $r warn (T 'ins.smartApp'); $found['installSmartApp'] = @() }
    elseif ($Facts.SmartApp -eq 2) { Add-HcLine $r ok (T 'ins.smartAppEval') }
    if ($null -ne $Facts.FreeGB) {
        if ($Facts.FreeGB -lt $script:InstallFreeGB) { Add-HcLine $r problem (T 'ins.space' $Facts.FreeGB); $found['installNoSpace'] = @($Facts.FreeGB) }
        else { Add-HcLine $r ok (T 'ins.spaceOk' $Facts.FreeGB) }
    }
    if ($Facts.InstallerOff) { Add-HcLine $r problem (T 'ins.msiOff'); Add-HcAction $r 'enableInstaller'; $found['installMsiOff'] = @() }
    if ($Facts.AdminAccount) { Add-HcLine $r ok (T 'ins.admin') }
    else { Add-HcLine $r warn (T 'ins.notAdmin'); $found['installNotAdmin'] = @() }
    if ($Facts.RebootPending) { Add-HcLine $r warn (T 'ins.reboot'); $found['installReboot'] = @() }
    Select-HcFinding $r $found @('installSMode', 'installStoreOnly', 'installNoSpace', 'installMsiOff', 'installReboot', 'installNotAdmin', 'installSmartApp') 'installOk'
    $r
}

# -------------------------------------------------- F5: browser hijacked --

# Search engines people choose themselves; anything else as the default
# search is how a hijacker earns its money.
$script:KnownSearchHosts = '(^|\.)(google\.[a-z.]+|bing\.com|duckduckgo\.com|ecosia\.org|startpage\.com|qwant\.com|search\.brave\.com|yahoo\.com|msn\.com)$'
$script:BrowserPolicyKeys = @{
    'Chrome' = 'SOFTWARE\Policies\Google\Chrome'
    'Edge'   = 'SOFTWARE\Policies\Microsoft\Edge'
    'Brave'  = 'SOFTWARE\Policies\BraveSoftware\Brave'
}

# Pure: the host of a URL, without "www." (the browsers' own templates,
# "{google:baseURL}" and "{bing:baseURL}", are Google and Bing).
function Get-HcUrlHost {
    param([string]$Url)
    if (-not $Url) { return $null }
    if ($Url -match '^\{(google|bing):') { return "$($Matches[1]).com" }
    if ($Url -match '^[a-z][a-z0-9+.-]*://([^/:?#]+)') { return ($Matches[1].ToLowerInvariant() -replace '^www\.', '') }
    $null
}

# Pure: a search host a person would not pick, or a "yhs" partner search
# (the classic Yahoo redirect used by hijackers).
function Test-HcHijackUrl {
    param([string]$Url)
    $h = Get-HcUrlHost $Url
    if (-not $h) { return $false }
    if ($Url -match '[?&/](yhs|hsimp|hspart)[=/-]') { return $true }
    $h -notmatch $script:KnownSearchHosts
}

# Where the stores' extensions update from; Edge's store does not set from_webstore.
$script:ExtensionStores = '^https://(clients2\.google\.com|edge\.microsoft\.com|extension-updates\.opera\.com)/'

# Policies that steer the search engine, start page or extensions; other
# rules (privacy tools switch off Copilot, shopping, ...) are no hijack.
$script:HijackPolicyNames = '^(DefaultSearchProvider|Homepage|RestoreOnStartup|NewTabPageLocation|ExtensionInstallForcelist|ExtensionSettings)'

# An extension's name, from its manifest or, for "__MSG_name__", its own
# translations; the id when neither says.
function Get-HcExtensionName {
    param($Manifest, [string]$Dir, [string]$Id)
    $name = $null; try { $name = "$($Manifest['name'])" } catch { }
    if ($name -match '^__MSG_(.+)__$' -and $Dir) {
        $key = $Matches[1]
        $locale = 'en'; try { if ($Manifest['default_locale']) { $locale = "$($Manifest['default_locale'])" } } catch { }
        $file = Join-Path $Dir "_locales\$locale\messages.json"
        $name = $null
        if (Test-Path -LiteralPath $file) {
            try {
                $messages = (New-Object System.Web.Script.Serialization.JavaScriptSerializer).DeserializeObject([IO.File]::ReadAllText($file))
                foreach ($k in $messages.Keys) { if ($k -eq $key) { $name = "$($messages[$k]['message'])" } }
            } catch { }
        }
    }
    if ($name -and $name -notmatch '^__MSG_') { $name } else { $Id }
}

function Get-HcBrowserState {
    try { Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop } catch { return @() }
    $json = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $json.MaxJsonLength = [int]::MaxValue
    $read = { param($path) if (Test-Path -LiteralPath $path) { try { $json.DeserializeObject([IO.File]::ReadAllText($path)) } catch { $null } } }
    foreach ($browser in $script:BrowserRoots) {
        $root = [Environment]::ExpandEnvironmentVariables($browser.Path)
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $profiles = @(Get-Item -LiteralPath $root) + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
        foreach ($p in $profiles) {
            $prefs = & $read (Join-Path $p.FullName 'Preferences')
            if ($null -eq $prefs) { continue }
            $secure = & $read (Join-Path $p.FullName 'Secure Preferences')
            $search = $null; $start = @(); $exts = @()
            try { $search = $prefs['default_search_provider_data']['template_url_data']['url'] } catch { }
            try { if ($prefs['session']['restore_on_startup'] -eq 4) { $start = @($prefs['session']['startup_urls']) } } catch { }
            try { if ($prefs['homepage'] -and -not $prefs['homepage_is_newtabpage']) { $start += $prefs['homepage'] } } catch { }
            foreach ($source in @($secure, $prefs)) {
                try { $settings = $source['extensions']['settings'] } catch { $settings = $null }
                if ($null -eq $settings) { continue }
                foreach ($id in $settings.Keys) {
                    $e = $settings[$id]
                    # Without a location it is what is left of a removed extension.
                    if (-not $e.ContainsKey('location')) { continue }
                    $loc = 0; try { $loc = [int]$e['location'] } catch { }
                    if ($loc -in @(5, 10)) { continue }   # Windows' and the browser's own parts
                    if (@($exts | Where-Object { $_.Id -eq $id }).Count) { continue }
                    $manifest = $null; try { $manifest = $e['manifest'] } catch { }
                    $dir = $null; try { $dir = "$($e['path'])" } catch { }
                    if ($dir -and -not [IO.Path]::IsPathRooted($dir)) { $dir = Join-Path (Join-Path $p.FullName 'Extensions') $dir }
                    if (-not $manifest -and $dir) { $manifest = & $read (Join-Path $dir 'manifest.json') }
                    $store = $false; try { $store = [bool]$e['from_webstore'] } catch { }
                    if (-not $store -and $manifest) { try { $store = ("$($manifest['update_url'])" -match $script:ExtensionStores) } catch { } }
                    $exts += [pscustomobject]@{ Id = $id; Name = (Get-HcExtensionName $manifest $dir $id); FromStore = $store }
                }
            }
            [pscustomobject]@{ Browser = $browser.Name; Profile = $p.Name; Search = $search; Start = @($start | Where-Object { $_ }); Extensions = $exts }
        }
    }
}

function Get-HcHijackFacts {
    $policies = foreach ($b in $script:BrowserPolicyKeys.Keys) {
        $names = @()
        foreach ($hive in @('HKLM:', 'HKCU:')) {
            $key = Get-Item -LiteralPath "$hive\$($script:BrowserPolicyKeys[$b])" -ErrorAction SilentlyContinue
            if ($key) { $names += @($key.Property) + @(Get-ChildItem -LiteralPath $key.PSPath -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) }
        }
        if ($names.Count) { [pscustomobject]@{ Browser = $b; Names = @($names | Select-Object -Unique) } }
    }
    [pscustomobject]@{ Browsers = @(Get-HcBrowserState); Policies = @($policies) }
}

function Test-HcHijack {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    foreach ($pol in @($Facts.Policies)) {
        $steering = @(@($pol.Names) | Where-Object { $_ -match $script:HijackPolicyNames })
        if ($steering.Count) {
            Add-HcLine $r problem (T 'hij.policy' $pol.Browser ($steering -join ', '))
            if (-not $found['browserPolicy']) { $found['browserPolicy'] = @($pol.Browser) }
        } else {
            Add-HcLine $r ok (T 'hij.policyOther' $pol.Browser @($pol.Names).Count)
        }
    }
    $buttons = @{}
    foreach ($s in @($Facts.Browsers)) {
        $who = if ($s.Profile -in @('Default', 'User Data') -or $s.Profile -like '*Stable') { $s.Browser } else { "$($s.Browser) ($($s.Profile))" }
        if ($s.Search -and (Test-HcHijackUrl $s.Search)) {
            Add-HcLine $r problem (T 'hij.search' $who (Get-HcUrlHost $s.Search))
            if (-not $found['browserSearchHijack']) { $found['browserSearchHijack'] = @($who, (Get-HcUrlHost $s.Search)) }
            $buttons[$s.Browser] = $true
        } else {
            Add-HcLine $r ok (T 'hij.searchOk' $who $(if ($s.Search) { Get-HcUrlHost $s.Search } else { T 'hij.default' }))
        }
        foreach ($u in @($s.Start)) {
            $h = Get-HcUrlHost $u
            if ($h -and $h -match 'search' -and (Test-HcHijackUrl $u)) {
                Add-HcLine $r problem (T 'hij.start' $who $h)
                if (-not $found['browserStartHijack']) { $found['browserStartHijack'] = @($who, $h) }
                $buttons[$s.Browser] = $true
            } elseif ($h) {
                Add-HcLine $r ok (T 'hij.startOk' $who $h)
            }
        }
        $outside = @($s.Extensions | Where-Object { -not $_.FromStore })
        if ($outside.Count) {
            Add-HcLine $r warn (T 'hij.extOutside' $who (@($outside | Select-Object -First 4 | ForEach-Object { $_.Name }) -join ', '))
            if (-not $found['browserExtOutside']) { $found['browserExtOutside'] = @($who) }
            Add-HcAction $r 'openBrowserExtensions' @{ Label = $s.Browser; Browser = $s.Browser }
        } elseif (@($s.Extensions).Count) {
            Add-HcLine $r ok (T 'hij.extOk' $who @($s.Extensions).Count)
        }
    }
    foreach ($b in $buttons.Keys) { Add-HcAction $r 'openBrowserReset' @{ Label = $b; Browser = $b } }
    if (-not @($Facts.Browsers).Count) { Add-HcLine $r skipped (T 'hij.none') }
    Select-HcFinding $r $found @('browserPolicy', 'browserSearchHijack', 'browserStartHijack', 'browserExtOutside') 'browserOk'
    $r
}

# ------------------------------------ B7: black screen, games that crash --

# Added 6 Oct after a real PC: about every day a black screen and a
# crashed game when the mouse went to the second screen. The log showed the
# graphics driver timing out and restarting (a "TDR"). AMD writes no
# Display 4101 for it, only a LiveKernelEvent with a WATCHDOG dump; Windows
# re-reports the queued ones (about 50 events each time), so one dump, to
# the minute, is one incident.
$script:GpuResetCodes = '^(117|141|1b8)$'
$script:GpuDriverOldDays = 180
$script:GpuDriverSites = @{
    'AMD'    = 'https://www.amd.com/en/support/download/drivers.html'
    'NVIDIA' = 'https://www.nvidia.com/en-us/drivers/'
    'Intel'  = 'https://www.intel.com/content/www/us/en/support/detect.html'
}
$script:GpuBackgroundTools = @{ 'wallpaper32' = 'Wallpaper Engine'; 'wallpaper64' = 'Wallpaper Engine'; 'MSIAfterburner' = 'MSI Afterburner'; 'RTSS' = 'RivaTuner'; 'Lively' = 'Lively Wallpaper' }

# Pure: the incidents (one [datetime] per minute) from LiveKernelEvent
# reports (@{ Code; Files; Time; Report }) and Display 4101 times. A report
# that Windows lists again keeps its id; its time is the dump's, or else
# the first time it was listed.
function ConvertFrom-HcGpuReports {
    param([object[]]$Reports, [datetime[]]$DisplayResets = @())
    $byReport = @{}
    foreach ($rep in @($Reports)) {
        if ("$($rep.Code)" -notmatch $script:GpuResetCodes) { continue }
        $key = if ($rep.Report) { "$($rep.Report)" } else { $rep.Time.ToString('yyyyMMddHHmm') }
        if ("$($rep.Files)" -match 'WATCHDOG-(\d{8}-\d{4})') {
            $byReport[$key] = @{ Time = [datetime]::ParseExact($Matches[1], 'yyyyMMdd-HHmm', [Globalization.CultureInfo]::InvariantCulture); Dump = $true }
        } elseif (-not $byReport[$key] -or (-not $byReport[$key].Dump -and $rep.Time -lt $byReport[$key].Time)) {
            $byReport[$key] = @{ Time = $rep.Time; Dump = $false }
        }
    }
    $seen = @{}
    foreach ($t in @(@($byReport.Values | ForEach-Object { $_.Time }) + @($DisplayResets))) {
        if ($t) { $seen[$t.ToString('yyyyMMddHHmm')] = $t.Date.AddHours($t.Hour).AddMinutes($t.Minute) }
    }
    @($seen.Values | Sort-Object)
}

# Pure: AMD, NVIDIA or Intel from a graphics card's name ($null otherwise).
function Get-HcGpuVendor {
    param([string]$Name)
    if ($Name -match 'AMD|Radeon') { 'AMD' } elseif ($Name -match 'NVIDIA|GeForce|Quadro|RTX|GTX') { 'NVIDIA' } elseif ($Name -match 'Intel') { 'Intel' } else { $null }
}

function Initialize-HcDisplayMode {
    if ('Housecall.DisplayMode' -as [type]) { return }
    Add-Type -Namespace Housecall -Name DisplayMode -MemberDefinition @"
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields;
    public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
}
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);
public static int GetHz(string device) {
    DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    return EnumDisplaySettings(device, -1, ref d) ? d.dmDisplayFrequency : 0;
}
"@
}

function Get-HcGpuFacts {
    $since = (Get-Date).AddDays(-30)
    $reports = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Windows Error Reporting'; Id = 1001; StartTime = $since } -ErrorAction SilentlyContinue |
        Where-Object { "$($_.Properties[2].Value)" -eq 'LiveKernelEvent' } |
        ForEach-Object { [pscustomobject]@{ Code = "$($_.Properties[5].Value)"; Files = "$($_.Properties[15].Value)"; Time = $_.TimeCreated; Report = "$($_.Properties[19].Value)" } })
    $display = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 4101; StartTime = $since } -ErrorAction SilentlyContinue | ForEach-Object { $_.TimeCreated })
    $whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; Level = 1, 2; StartTime = $since } -ErrorAction SilentlyContinue)
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; DriverDate = $_.DriverDate; Vendor = (Get-HcGpuVendor $_.Name) }
    })
    $screens = @()
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Initialize-HcDisplayMode
        $screens = @([Windows.Forms.Screen]::AllScreens | ForEach-Object { [pscustomobject]@{ Device = $_.DeviceName; Hz = [Housecall.DisplayMode]::GetHz($_.DeviceName) } })
    } catch { }
    $running = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $script:GpuBackgroundTools[$_.Name] } | Where-Object { $_ } | Select-Object -Unique)
    [pscustomobject]@{
        Now            = Get-Date
        Resets         = @(ConvertFrom-HcGpuReports $reports $display | Where-Object { $_ -ge $since })
        HardwareErrors = $whea.Count
        Gpus           = $gpus
        Screens        = $screens
        Background     = $running
    }
}

function Test-HcGpu {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $culture = [Globalization.CultureInfo]::GetCultureInfo($(if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }))
    $resets = @($Facts.Resets)
    $old = $null
    foreach ($g in @($Facts.Gpus)) {
        if ($g.Name -match 'Basic Display|Basisbeeldscherm') {
            Add-HcLine $r problem (T 'gpu.basic' $g.Name)
            $found['gpuNoDriver'] = @()
            continue
        }
        $date = if ($g.DriverDate) { ([datetime]$g.DriverDate).ToString('d MMM yyyy', $culture) } else { '?' }
        if ($g.DriverDate -and ($Facts.Now - [datetime]$g.DriverDate).Days -gt $script:GpuDriverOldDays) {
            Add-HcLine $r warn (T 'gpu.driverOld' $g.Name $date)
            if (-not $old) { $old = $g }
        } else {
            Add-HcLine $r ok (T 'gpu.driver' $g.Name $date)
        }
    }
    if ($resets.Count) {
        Add-HcLine $r problem (T 'gpu.resets' $resets.Count $resets[-1].ToString('d MMM HH:mm', $culture))
        $found[$(if ($old) { 'gpuDriverOld' } else { 'gpuResets' })] = @($resets.Count)
    } else {
        Add-HcLine $r ok (T 'gpu.resetsNone')
    }
    $hz = @(@($Facts.Screens) | Where-Object { $_.Hz -gt 1 } | ForEach-Object { $_.Hz })
    if ($hz.Count -gt 1) {
        $list = ($hz | ForEach-Object { "$_ Hz" }) -join ', '
        if (@($hz | Select-Object -Unique).Count -gt 1) {
            Add-HcLine $r $(if ($resets.Count) { 'warn' } else { 'ok' }) (T 'gpu.hzMixed' $list)
            if ($resets.Count) { Add-HcAction $r 'openAdvancedDisplay' }
        } else {
            Add-HcLine $r ok (T 'gpu.hz' $list)
        }
    }
    if (@($Facts.Background).Count) {
        Add-HcLine $r $(if ($resets.Count) { 'warn' } else { 'ok' }) (T 'gpu.background' (@($Facts.Background) -join ', '))
    }
    if ($Facts.HardwareErrors) {
        Add-HcLine $r problem (T 'gpu.whea' $Facts.HardwareErrors)
        $found['gpuHardware'] = @($Facts.HardwareErrors)
    }
    if ($resets.Count -or $found['gpuNoDriver']) {
        foreach ($v in @(@($Facts.Gpus) | ForEach-Object { $_.Vendor } | Where-Object { $_ } | Select-Object -Unique)) {
            Add-HcAction $r 'openGpuDriverSite' @{ Label = $v; Vendor = $v }
        }
        Add-HcAction $r 'openGraphicsSettings'
    }
    Select-HcFinding $r $found @('gpuNoDriver', 'gpuDriverOld', 'gpuResets', 'gpuHardware') 'gpuOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcB7 { { Test-HcGpu (Get-HcGpuFacts) } }
function Invoke-HcD5 { { Test-HcRestarts (Get-HcRestartFacts) } }
function Invoke-HcD6 { { Test-HcHeat (Get-HcHeatFacts) } }
function Invoke-HcE6 { { Test-HcInstall (Get-HcInstallFacts) } }
function Invoke-HcF5 { { Test-HcHijack (Get-HcHijackFacts) } }

$script:ProblemHandlers['B7'] = 'Invoke-HcB7'
$script:ProblemHandlers['D5'] = 'Invoke-HcD5'
$script:ProblemHandlers['D6'] = 'Invoke-HcD6'
$script:ProblemHandlers['E6'] = 'Invoke-HcE6'
$script:ProblemHandlers['F5'] = 'Invoke-HcF5'

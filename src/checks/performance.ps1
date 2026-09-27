<#
    Area D: Slow or freezing.

      D1  the whole computer is slow    disk space, memory, CPU now, time since restart,
                                        system disk type, RAM size, startup programs
      D2  takes ages to start           startup programs, system disk type, disk space
      D3  a program freezes or crashes  crashes and hangs this week, blue screens,
                                        unexpected shutdowns, memory
      D4  the disk is full              free space, Temp, Recycle Bin, Downloads

    CPU comes from Win32_PerfFormattedData classes, not Get-Counter, whose
    counter names Windows translates. Startup programs are switched on and
    off the way Task Manager does it: a StartupApproved value, first byte
    02 = on, 03 = off, so it can be undone.
#>

$script:DiskFullPercent  = 5      # free % of the system disk at or below: full
$script:DiskLowPercent   = 15     # ... at or below: getting full
$script:MemoryFullPercent = 90
$script:CpuBusyPercent   = 80
$script:UptimeDays       = 7
$script:ManyStartup      = 8

# Programs that start with Windows and should keep doing so: security,
# sound and touchpad drivers, OneDrive (photo backup).
$script:KeepAtStartup = 'SecurityHealth|Defender|Realtek|RtkAud|Nahimic|Waves|Dolby|Synaptics|ELAN|igfx|Intel|AMD|NVIDIA|Bluetooth|OneDrive|Housecall|Reveille|Courier'

# Windows' own background processes: their crashes are Windows' business,
# and "update or reinstall it" would be nonsense advice.
$script:WindowsHelpers = '^(dllhost|svchost|backgroundTaskHost|RuntimeBroker|taskhostw|WerFault|SearchProtocolHost|SearchHost|SearchIndexer|conhost|sihost|ctfmon|smartscreen)$'

# Processes never offered for closing.
$script:SystemProcess = '^(System|Idle|svchost|csrss|wininit|services|lsass|smss|dwm|explorer|MsMpEng|Registry|Memory Compression|audiodg|winlogon|fontdrvhost|Secure System|powershell|conhost)$'

# ------------------------------------------------------------------- facts --

function Get-HcSystemDisk {
    $drive = $env:SystemDrive
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
    $media = $null
    try {
        $media = [string](Get-Partition -DriveLetter $drive.TrimEnd(':') -ErrorAction Stop | Get-Disk -ErrorAction Stop | Get-PhysicalDisk -ErrorAction Stop | Select-Object -First 1).MediaType
    } catch { }
    [pscustomobject]@{
        Drive  = $drive
        FreeGB = [math]::Round($d.FreeSpace / 1GB, 1)
        SizeGB = [math]::Round($d.Size / 1GB, 1)
        FreePercent = if ($d.Size) { [int](100 * $d.FreeSpace / $d.Size) } else { 100 }
        Media  = $media     # SSD, HDD or Unspecified
    }
}

<#
    Startup programs from the Run keys and Startup folders, each with the
    StartupApproved value Task Manager uses to switch it on or off.
#>
function Get-HcStartupItems {
    $approvedRoot = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $sources = @(
        @{ Hive = 'HKCU'; Kind = 'Run';           Key = 'Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKLM'; Kind = 'Run';           Key = 'Software\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKLM'; Kind = 'Run32';         Key = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' }
        @{ Hive = 'HKCU'; Kind = 'StartupFolder'; Folder = [Environment]::GetFolderPath('Startup') }
        @{ Hive = 'HKLM'; Kind = 'StartupFolder'; Folder = [Environment]::GetFolderPath('CommonStartup') }
    )
    foreach ($s in $sources) {
        $names = @()
        if ($s.Key) {
            $item = Get-Item "$($s.Hive):\$($s.Key)" -ErrorAction SilentlyContinue
            if ($item) { $names = @($item.Property) }
        } elseif ($s.Folder -and (Test-Path -LiteralPath $s.Folder)) {
            $names = @(Get-ChildItem -LiteralPath $s.Folder -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object { $_.Name })
        }
        $approved = "$($s.Hive):\$approvedRoot\$($s.Kind)"
        $values = Get-ItemProperty $approved -ErrorAction SilentlyContinue
        foreach ($n in $names) {
            $bytes = if ($values) { $values.$n } else { $null }
            [pscustomobject]@{
                Name     = ($n -replace '\.lnk$', '')
                Value    = $n
                Machine  = ($s.Hive -eq 'HKLM')
                Approved = $approved
                Enabled  = -not ($bytes -and $bytes.Count -gt 0 -and ($bytes[0] -band 1))
            }
        }
    }
}

function Get-HcBusyProcesses {
    $cores = [Math]::Max(1, [Environment]::ProcessorCount)
    @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin @('_Total', 'Idle') } |
        Sort-Object PercentProcessorTime -Descending | Select-Object -First 5 | ForEach-Object {
            [pscustomobject]@{
                Name = ($_.Name -replace '#\d+$', '')
                Cpu  = [int]($_.PercentProcessorTime / $cores)
                MemoryMB = [int]($_.WorkingSetPrivate / 1MB)
            }
        })
}

function Get-HcPerformanceFacts {
    param([switch]$Crashes, [switch]$Sizes)
    $os = Get-CimInstance Win32_OperatingSystem
    $f = [pscustomobject]@{
        Disk        = Get-HcSystemDisk
        RamGB       = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        MemoryUsed  = [int](100 - 100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize)
        Cpu         = [int](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue).PercentProcessorTime
        Busy        = @(Get-HcBusyProcesses)
        UptimeDays  = [int]((Get-Date) - $os.LastBootUpTime).TotalDays
        Startup     = @(Get-HcStartupItems)
        CrashApps   = @()
        Shutdowns   = 0
        BlueScreens = 0
        Sizes       = $null
    }
    if ($Crashes) {
        $since = (Get-Date).AddDays(-7)
        try {
            $f.CrashApps = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = $since } -ErrorAction Stop |
                Group-Object { (Split-Path -Leaf ([string]$_.Properties[0].Value)) -replace '\.exe$', '' } | Where-Object { $_.Name -notmatch $script:WindowsHelpers } |
                Sort-Object Count -Descending | Select-Object -First 5 |
                ForEach-Object { [pscustomobject]@{ Name = $_.Name; Count = $_.Count } })
        } catch { }
        $month = (Get-Date).AddDays(-30)
        try { $f.Shutdowns = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $month } -ErrorAction Stop).Count } catch { }
        try { $f.BlueScreens = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $month } -ErrorAction Stop).Count } catch { }
    }
    if ($Sizes) {
        $size = { param($path) if ($path -and (Test-Path -LiteralPath $path)) { [math]::Round(((Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1GB, 1) } else { 0 } }
        $binGB = 0
        try {
            $bytes = 0
            foreach ($i in (New-Object -ComObject Shell.Application).Namespace(10).Items()) { $bytes += $i.Size }
            $binGB = [math]::Round($bytes / 1GB, 1)
        } catch { }
        $downloads = $null
        try { $downloads = (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path } catch { }
        $f.Sizes = [pscustomobject]@{ TempGB = & $size $env:TEMP; BinGB = $binGB; DownloadsGB = & $size $downloads }
    }
    $f
}

# ------------------------------------------------------------------ verdict --

# Lines for the startup programs, and a switch-off offer for each one that
# may go. Returns how many are on.
function Add-HcStartupLines {
    param([pscustomobject]$Report, [object[]]$Items)
    $on = @($Items | Where-Object { $_.Enabled })
    $names = @($on | ForEach-Object { $_.Name }) -join ', '
    if ($on.Count -gt $script:ManyStartup) {
        Add-HcLine $Report warn (T 'perf.startupMany' $on.Count $names)
    } else {
        Add-HcLine $Report ok (T 'perf.startup' $on.Count)
    }
    foreach ($i in @($on | Where-Object { $_.Name -notmatch $script:KeepAtStartup }) | Select-Object -First 6) {
        $fix = if ($i.Machine) { 'disableStartupMachine' } else { 'disableStartup' }
        Add-HcAction $Report $fix @{ Label = $i.Name; Approved = $i.Approved; Value = $i.Value }
    }
    $on.Count
}

function Add-HcDiskLine {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Disk)
    if ($Disk.FreePercent -le $script:DiskFullPercent) {
        Add-HcLine $Report problem (T 'perf.diskFull' $Disk.Drive $Disk.FreeGB $Disk.FreePercent)
        $Found['diskFull'] = @($Disk.Drive, $Disk.FreeGB)
    } elseif ($Disk.FreePercent -le $script:DiskLowPercent) {
        Add-HcLine $Report warn (T 'perf.diskLow' $Disk.Drive $Disk.FreeGB $Disk.FreePercent)
        $Found['diskLow'] = @($Disk.Drive, $Disk.FreeGB)
    } else {
        Add-HcLine $Report ok (T 'perf.diskOk' $Disk.Drive $Disk.FreeGB $Disk.FreePercent)
    }
    if ($Disk.Media -eq 'HDD') {
        Add-HcLine $Report warn (T 'perf.hdd' $Disk.Drive)
        $Found['hddSystem'] = @()
    }
}

function Add-HcMemoryLines {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Facts)
    if ($Facts.MemoryUsed -ge $script:MemoryFullPercent) {
        Add-HcLine $Report problem (T 'perf.memoryFull' $Facts.MemoryUsed $Facts.RamGB)
        $Found['memoryFull'] = @($Facts.MemoryUsed)
    } else {
        Add-HcLine $Report ok (T 'perf.memory' $Facts.MemoryUsed $Facts.RamGB)
    }
    if ($Facts.RamGB -le 4.1) {
        Add-HcLine $Report warn (T 'perf.lowRam' $Facts.RamGB)
        $Found['lowRam'] = @($Facts.RamGB)
    }
}

# D1.
function Test-HcSlow {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    Add-HcDiskLine $r $found $Facts.Disk
    Add-HcMemoryLines $r $found $Facts

    $top = @($Facts.Busy) | Select-Object -First 1
    if ($Facts.Cpu -ge $script:CpuBusyPercent) {
        $who = if ($top) { $top.Name } else { '?' }
        Add-HcLine $r problem (T 'perf.cpuBusy' $Facts.Cpu $who)
        $found['cpuBusy'] = @($Facts.Cpu, $who)
    } else {
        Add-HcLine $r ok (T 'perf.cpu' $Facts.Cpu)
    }
    # A program hogging the processor or memory may be closed (unsaved work goes).
    $hog = @($Facts.Busy | Where-Object { $_.Name -notmatch $script:SystemProcess -and ($_.Cpu -ge 50 -or ($Facts.MemoryUsed -ge $script:MemoryFullPercent -and $_.MemoryMB -ge 1500)) }) | Select-Object -First 1
    if ($hog) { Add-HcAction $r 'closeProcess' @{ Label = $hog.Name; Name = $hog.Name } }

    if ($Facts.UptimeDays -ge $script:UptimeDays) {
        Add-HcLine $r warn (T 'perf.uptimeLong' $Facts.UptimeDays)
        $found['longUptime'] = @($Facts.UptimeDays)
    } else {
        Add-HcLine $r ok (T 'perf.uptime' $Facts.UptimeDays)
    }
    if ((Add-HcStartupLines $r $Facts.Startup) -gt $script:ManyStartup) { $found['manyStartup'] = @(@($Facts.Startup | Where-Object { $_.Enabled }).Count) }

    Select-HcFinding $r $found @('diskFull', 'memoryFull', 'cpuBusy', 'longUptime', 'hddSystem', 'lowRam', 'manyStartup', 'diskLow') 'slowOk'
    $r
}

# D2.
function Test-HcSlowStart {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    if ((Add-HcStartupLines $r $Facts.Startup) -gt $script:ManyStartup) { $found['manyStartup'] = @(@($Facts.Startup | Where-Object { $_.Enabled }).Count) }
    Add-HcDiskLine $r $found $Facts.Disk
    Add-HcMemoryLines $r $found $Facts
    Select-HcFinding $r $found @('diskFull', 'hddSystem', 'manyStartup', 'lowRam', 'diskLow') 'startOk'
    $r
}

# D3.
function Test-HcCrashes {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $apps = @($Facts.CrashApps)
    if ($apps.Count) {
        foreach ($a in $apps) { Add-HcLine $r $(if ($a.Count -ge 3) { 'problem' } else { 'warn' }) (T 'perf.crashApp' $a.Name $a.Count) }
        $worst = $apps[0]
        if ($worst.Count -ge 3) { $found['crashes'] = @($worst.Name, $worst.Count) } else { $found['someCrashes'] = @($worst.Name) }
    } else {
        Add-HcLine $r ok (T 'perf.noCrashes')
    }
    if ($Facts.BlueScreens -gt 0) {
        Add-HcLine $r problem (T 'perf.blueScreens' $Facts.BlueScreens)
        $found['blueScreens'] = @($Facts.BlueScreens)
    }
    if ($Facts.Shutdowns -gt 0) {
        Add-HcLine $r warn (T 'perf.shutdowns' $Facts.Shutdowns)
        $found['shutdowns'] = @($Facts.Shutdowns)
    }
    Add-HcMemoryLines $r $found $Facts
    Add-HcDiskLine $r $found $Facts.Disk
    Select-HcFinding $r $found @('blueScreens', 'crashes', 'memoryFull', 'diskFull', 'shutdowns', 'someCrashes', 'lowRam') 'crashOk'
    $r
}

# D4.
function Test-HcDiskSpace {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    Add-HcDiskLine $r $found $Facts.Disk
    $s = $Facts.Sizes
    if ($s) {
        Add-HcLine $r ok (T 'perf.sizes' $s.TempGB $s.BinGB $s.DownloadsGB)
        if ($s.TempGB -ge 0.5) { Add-HcAction $r 'emptyTemp' @{ Label = $s.TempGB } }
        if ($s.BinGB -ge 0.1) { Add-HcAction $r 'emptyRecycleBin' @{ Label = $s.BinGB } }
    }
    # D4 is where the space gets freed, so its findings point below, not to D4.
    Select-HcFinding $r $found @('diskFull', 'diskLow') 'diskOk'
    switch ($r.FindingId) {
        'diskFull' { $r.FindingId = 'spaceFull' }
        'diskLow'  { $r.FindingId = 'spaceLow' }
        'diskOk'   { $r.FindingArgs = @($Facts.Disk.Drive, $Facts.Disk.FreeGB) }
    }
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcD1 { { Test-HcSlow (Get-HcPerformanceFacts) } }
function Invoke-HcD2 { { Test-HcSlowStart (Get-HcPerformanceFacts) } }
function Invoke-HcD3 { { Test-HcCrashes (Get-HcPerformanceFacts -Crashes) } }
function Invoke-HcD4 { { Test-HcDiskSpace (Get-HcPerformanceFacts -Sizes) } }

$script:ProblemHandlers['D1'] = 'Invoke-HcD1'
$script:ProblemHandlers['D2'] = 'Invoke-HcD2'
$script:ProblemHandlers['D3'] = 'Invoke-HcD3'
$script:ProblemHandlers['D4'] = 'Invoke-HcD4'

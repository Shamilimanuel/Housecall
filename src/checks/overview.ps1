<#
    Pc-overzicht (phase 6, step 3): what this PC is, and whether an upgrade
    makes sense. Read-only, like every check.

    Get-HcOverviewFacts reads the PC; everything after it is pure, so each
    rule can be tested: the PC's name, how old its processor is, whether
    Windows still gets updates, and the advice. The advice is where the
    "building PCs" half of the business shows: an SSD instead of a hard
    disk, more memory, Windows 11 -- or honestly, time for a newer PC.

    The PC's age comes from its processor, not the BIOS date: a BIOS update
    moves that date to this year (Shamil's own PC says 2026 for a 2020
    Ryzen), and Windows' install date only says when it was last reset.
#>

# When Windows stops getting updates, for Home and Pro (Microsoft's
# lifecycle pages). Enterprise and Education get longer and are not judged.
$script:WindowsSupportEnd = @{
    '11-21H2' = '2023-10-10'; '11-22H2' = '2024-10-08'; '11-23H2' = '2025-11-11'
    '11-24H2' = '2026-10-13'; '11-25H2' = '2027-10-12'
}
$script:Windows10End = '2025-10-14'
# Extended Security Updates for home users, one extra year of Windows 10.
$script:Windows10EsuEnd = '2026-10-13'
# How far ahead a coming end of updates is worth mentioning.
$script:SupportSoonDays = 60

# The first year a processor was sold, per generation or series.
$script:IntelYear = @{ 2 = 2011; 3 = 2012; 4 = 2013; 5 = 2015; 6 = 2015; 7 = 2017; 8 = 2017; 9 = 2018; 10 = 2019; 11 = 2020; 12 = 2021; 13 = 2022; 14 = 2023 }
$script:RyzenYear = @{ 1 = 2017; 2 = 2018; 3 = 2019; 4 = 2020; 5 = 2020; 6 = 2022; 7 = 2022; 8 = 2024; 9 = 2024 }

$script:PlaceholderName = '^\s*(System Product Name|System manufacturer|To be filled.*|Default string|O\.?E\.?M\.?|Not Applicable|None|x\.x|)\s*$'

# ------------------------------------------------------------ pure parts --

# "Dell Inc." -> "Dell", "Hewlett-Packard" -> "HP", "ASUSTeK COMPUTER INC." -> "ASUS".
function Get-HcMakerName {
    param([string]$Maker)
    $m = "$Maker".Trim()
    switch -Regex ($m) {
        '^(HP|Hewlett)'  { return 'HP' }
        '^ASUS'          { return 'ASUS' }
        '^LENOVO'        { return 'Lenovo' }
        '^Micro-Star|^MSI' { return 'MSI' }
        '^Acer'          { return 'Acer' }
        '^Dell'          { return 'Dell' }
        '^Microsoft'     { return 'Microsoft' }
        '^Gigabyte'      { return 'Gigabyte' }
    }
    ($m -replace '(?i)[,\s]+(inc\.?|corporation|corp\.?|co\.,? ?ltd\.?|ltd\.?|gmbh)$', '').Trim()
}

<#
    What to call this PC: "HP Pavilion 15", "Lenovo ThinkPad T480" (Lenovo
    keeps the readable name in the product version), or for a self-built
    PC, which says "System Product Name", its motherboard.
#>
function Get-HcPcName {
    param([string]$Maker, [string]$Model, [string]$Version, [string]$BoardMaker, [string]$Board)
    $brand = Get-HcMakerName $Maker
    if ($brand -eq 'Lenovo' -and $Version -notmatch $script:PlaceholderName -and $Version -notmatch '^Lenovo$') {
        return ($brand + ' ' + ($Version -replace '^(?i)lenovo\s+', '')).Trim()
    }
    if ($Model -notmatch $script:PlaceholderName) {
        if ($Model -match ('^(?i)' + [regex]::Escape($brand))) { return $Model.Trim() }
        return ($brand + ' ' + $Model).Trim()
    }
    if ($Board -notmatch $script:PlaceholderName) {
        return T 'pc.selfBuilt' ((Get-HcMakerName $BoardMaker) + ' ' + $Board).Trim()
    }
    T 'pc.unknownModel'
}

# The year a processor came out, from its name; $null when unknown.
function Get-HcCpuYear {
    param([string]$Name)
    $n = "$Name"
    if ($n -match 'Core\(?T?M?\)?\s+Ultra\s+\d\s+(\d)\d\d') { return $(if ($Matches[1] -eq '1') { 2023 } else { 2024 }) }
    if ($n -match 'Core\(?T?M?\)?\s+i\d-(\d{4,5})([A-Z]\d?)?') {
        $digits = $Matches[1]
        $suffix = "$($Matches[2])"
        $gen = if ($digits.Length -eq 5) { [int]$digits.Substring(0, 2) }
               elseif ($digits -match '^1[0-4]' -and $suffix -match '^G') { [int]$digits.Substring(0, 2) }
               else { [int]$digits.Substring(0, 1) }
        return $script:IntelYear[$gen]
    }
    if ($n -match 'Ryzen\s+AI') { return 2024 }
    if ($n -match 'Ryzen\s+(\d|Threadripper)\s+(PRO\s+)?(\d)\d{3}') { return $script:RyzenYear[[int]$Matches[3]] }
    if ($n -match '\b[NJ]\d{3}\b') { return 2023 }
    if ($n -match '\b[NJ][45]\d{3}\b') { return 2018 }
    if ($n -match '\b[NJ][23]\d{3}\b') { return 2015 }
    $null
}

# Whether Windows 11 supports this processor: $true, $false, or $null when
# the name does not say (then the E1 check and Microsoft's tool decide).
function Test-HcCpuWin11 {
    param([string]$Name)
    $n = "$Name"
    if ($n -match 'Core\(?T?M?\)?\s+Ultra') { return $true }
    if ($n -match 'Ryzen\s+AI') { return $true }
    if ($n -match 'Ryzen\s+(\d|Threadripper)\s+(PRO\s+)?(\d)\d{3}') { return ([int]$Matches[3] -ge 2) }
    $year = Get-HcCpuYear $n
    if ($n -match 'Core\(?T?M?\)?\s+i\d-' -and $year) { return ($year -ge 2017 -and $n -notmatch '\bi\d-7\d{3}') }
    $null
}

<#
    Whether this Windows still gets updates: its version, the date that
    stops, and ok / soon (within $SupportSoonDays) / ended. $null for an
    edition that is not judged.
#>
function Get-HcWindowsSupport {
    param([int]$Build, [string]$DisplayVersion, [string]$Edition, [datetime]$Today = (Get-Date))
    $major = if ($Build -ge 22000) { 11 } else { 10 }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    if ($major -eq 10) {
        $end = [datetime]::Parse($script:Windows10End, $invariant)
        $esu = [datetime]::Parse($script:Windows10EsuEnd, $invariant)
        return [pscustomobject]@{ Major = 10; Version = $DisplayVersion; End = $end; Esu = $esu; Status = 'ended' }
    }
    if ($Edition -match 'Enterprise|Education|IoT|Server') { return $null }
    $date = $script:WindowsSupportEnd["11-$DisplayVersion"]
    if (-not $date) { return $null }
    $end = [datetime]::Parse($date, $invariant)
    $status = if ($Today -ge $end) { 'ended' } elseif (($end - $Today).TotalDays -le $script:SupportSoonDays) { 'soon' } else { 'ok' }
    [pscustomobject]@{ Major = 11; Version = $DisplayVersion; End = $end; Esu = $null; Status = $status }
}

# SSD or HDD, from what Windows reports, falling back on the bus and the
# spin speed (older drivers report "Unspecified").
function Get-HcDiskKind {
    param([string]$MediaType, [string]$BusType, $SpindleSpeed)
    if ($MediaType -eq 'SSD' -or $BusType -eq 'NVMe') { return 'SSD' }
    if ($MediaType -eq 'HDD' -or ($SpindleSpeed -and [uint32]$SpindleSpeed -gt 0 -and [uint32]$SpindleSpeed -lt [uint32]::MaxValue)) { return 'HDD' }
    'unknown'
}

# "2 TB" or "512 GB", the way disks are sold (decimal).
function Format-HcSize {
    param([double]$GB)
    $sep = if ($script:Lang -eq 'nl') { ',' } else { '.' }
    if ($GB -ge 1000) { return ('{0:0.#} TB' -f ([Math]::Round($GB / 1000 * 2) / 2)).Replace('.', $sep) }
    '{0:0} GB' -f $GB
}

<#
    The advice, most important first. Each has an Id (adv.<id> in the
    strings, with .short for the note), its Args, a Level (problem, upgrade,
    warn, info or ok) and the problem Code that goes deeper, if any.
#>
function Get-HcOverviewAdvice {
    param([pscustomobject]$Facts, [datetime]$Today = (Get-Date))
    $list = New-Object System.Collections.ArrayList
    $add = { param($id, $level, $code, [object[]]$params = @())
        [void]$list.Add([pscustomobject]@{ Id = $id; Level = $level; Code = $code; Args = $params }) }
    $date = { param($d) Format-HcLongDate $d }

    foreach ($d in @($Facts.Disks | Where-Object { $_.Health -and $_.Health -ne 'Healthy' })) {
        & $add 'diskHealth' 'problem' $null @($d.Name)
    }
    $system = @($Facts.Disks | Where-Object { $_.Number -eq $Facts.SystemDisk }) | Select-Object -First 1
    if ($system -and $system.Kind -eq 'HDD') { & $add 'ssd' 'upgrade' $null @() }
    if ($Facts.SystemSizeGB -gt 0) {
        $used = 1 - ($Facts.SystemFreeGB / $Facts.SystemSizeGB)
        if ($used -ge 0.9 -or $Facts.SystemFreeGB -lt 10) { & $add 'diskFull' 'warn' 'D4' @([Math]::Round($Facts.SystemFreeGB)) }
    }
    if ($Facts.RamGB -and $Facts.RamGB -lt 7.5) {
        # 4 GB goes to 8, which is enough for everyday use; 6 GB goes to 16.
        $target = if ($Facts.RamGB -le 4.5) { 8 } else { 16 }
        $id = if ($Facts.Laptop) { 'ramLaptop' } else { 'ram' }
        & $add $id 'upgrade' $null @([Math]::Round($Facts.RamGB), $target)
    }

    $support = Get-HcWindowsSupport $Facts.Build $Facts.DisplayVersion $Facts.Edition $Today
    if ($support -and $support.Major -eq 10) {
        $cpuOk = Test-HcCpuWin11 $Facts.Cpu
        if ($cpuOk -eq $false) {
            $id = if ($Today -lt $support.Esu) { 'win10Stuck' } else { 'win10StuckEnded' }
            & $add $id 'problem' 'E1' @((& $date $support.Esu))
        } else {
            & $add 'win11Free' 'upgrade' 'E1' @((& $date $support.Esu))
        }
    } elseif ($support -and $support.Status -ne 'ok') {
        $id = if ($support.Status -eq 'soon') { 'winVersionSoon' } else { 'winVersionEnded' }
        & $add $id 'warn' 'E1' @($support.Version, (& $date $support.End))
    }

    if ($Facts.BatteryHealth) {
        if ($Facts.BatteryHealth -lt 50) { & $add 'batteryReplace' 'upgrade' 'C4' @($Facts.BatteryHealth) }
        elseif ($Facts.BatteryHealth -lt 70) { & $add 'batteryAging' 'info' 'C4' @($Facts.BatteryHealth) }
    }

    $year = Get-HcCpuYear $Facts.Cpu
    if ($year -and ($Today.Year - $year) -ge 8) { & $add 'oldPc' 'info' $null @($year, ($Today.Year - $year)) }

    if ($list.Count -eq 0) { & $add 'allGood' 'ok' $null @() }
    $list
}

# ------------------------------------------------------------ reading --

function Get-HcOverviewFacts {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $product = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $current = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)

    $modules = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $slots = (@(Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue) | Measure-Object MemoryDevices -Sum).Sum
    $ramType = switch (@($modules | ForEach-Object { [int]$_.SMBIOSMemoryType }) | Select-Object -First 1) {
        20 { 'DDR' } 21 { 'DDR2' } 24 { 'DDR3' } 26 { 'DDR4' } 29 { 'LPDDR3' } 30 { 'LPDDR4' } 34 { 'DDR5' } 35 { 'LPDDR5' } default { $null }
    }

    $systemDisk = $null
    try { $systemDisk = [int](Get-Partition -DriveLetter $env:SystemDrive.Substring(0, 1) -ErrorAction Stop | Get-Disk -ErrorAction Stop).Number } catch { }
    $disks = @()
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.BusType -notin @('USB', 'SD', 'MMC', 'File Backed Virtual') } | ForEach-Object {
            [pscustomobject]@{
                Number = [int]$_.DeviceId; Name = "$($_.FriendlyName)".Trim(); Bus = "$($_.BusType)"
                Kind = Get-HcDiskKind "$($_.MediaType)" "$($_.BusType)" $_.SpindleSpeed
                # Decimal, as disks are sold: a "2 TB" disk is 1863 GB to Windows.
                SizeGB = [Math]::Round($_.Size / 1e9); Health = "$($_.HealthStatus)"
            }
        } | Sort-Object Number)
    } catch { }
    $volume = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue

    $batteryHealth = $null
    $battery = $null
    try { $battery = Get-HcBatteryFacts } catch { }
    if ($battery -and $battery.HasBattery) { $batteryHealth = Get-HcBatteryHealth $battery.DesignMWh $battery.FullMWh }

    [pscustomobject]@{
        Name           = Get-HcPcName "$($cs.Manufacturer)" "$($cs.Model)" "$($product.Version)" "$($board.Manufacturer)" "$($board.Product)"
        Laptop         = [bool]@($chassis | Where-Object { $_ -in $script:LaptopChassis }).Count
        Cpu            = "$($cpu.Name)".Trim() -replace '\s+', ' '
        Cores          = [int]$cpu.NumberOfCores
        Gpus           = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)".Trim() } | Where-Object { $_ -and $_ -notmatch 'Basic Display|Remote Display|Virtual' })
        RamGB          = [Math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        RamType        = $ramType
        SlotsUsed      = $modules.Count
        SlotsTotal     = [int]$slots
        Os             = ("$($os.Caption)" -replace '^Microsoft\s+', '').Trim()
        Edition        = "$($current.EditionID)"
        DisplayVersion = $(if ($current.DisplayVersion) { "$($current.DisplayVersion)" } else { "$($current.ReleaseId)" })
        Build          = [int]$os.BuildNumber
        Disks          = $disks
        SystemDisk     = $systemDisk
        SystemSizeGB   = $(if ($volume) { [Math]::Round($volume.Size / 1GB, 1) } else { 0 })
        SystemFreeGB   = $(if ($volume) { [Math]::Round($volume.FreeSpace / 1GB, 1) } else { 0 })
        HasBattery     = [bool]($battery -and $battery.HasBattery)
        BatteryHealth  = $batteryHealth
    }
}

<#
    Area C: Printer & devices.

      C1  printer will not print        print service, printers, default printer, queue
      C2  mouse, keyboard or USB stick  devices with errors, keyboard and mouse, USB drives
      C3  Bluetooth                     adapter, Bluetooth service, paired devices

    Same shape as A and F: Get-...Facts reads the PC, Test-... decides, and
    the fixes it offers live in src\fixes.ps1. Everything here reads
    through CIM and PnP objects, which Windows does not translate.
#>

# Printers that only exist on the PC: PDF, XPS, OneNote, fax. Documents
# sent there never reach paper -- a common "my printer does nothing".
$script:VirtualPrinter = 'Print to PDF|XPS|OneNote|Fax|Send To'
$script:VirtualPort = '^(PORTPROMPT:|nul:|SHRFAX:|XPSPort:|FILE:)'

# How old a waiting print job must be before it counts as stuck.
$script:StuckMinutes = 10

# DetectedErrorState values Windows reports for a printer, and whether each
# stops printing (problem) or is only a warning.
$script:PrinterStates = @{ 3 = 'warn'; 4 = 'problem'; 5 = 'warn'; 6 = 'problem'; 7 = 'problem'; 8 = 'problem'; 10 = 'problem'; 11 = 'problem' }

# ------------------------------------------------------------------- facts --

function Get-HcPrinterFacts {
    $f = [pscustomobject]@{ Now = Get-Date; SpoolerRunning = $false; SpoolerDisabled = $false; Printers = @(); Jobs = @() }
    $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if ($spooler) {
        $f.SpoolerRunning = ($spooler.Status -eq 'Running')
        $f.SpoolerDisabled = ([string]$spooler.StartType -eq 'Disabled')
    }
    if (-not $f.SpoolerRunning) { return $f }

    $ports = @{}
    Get-CimInstance Win32_TCPIPPrinterPort -ErrorAction SilentlyContinue | ForEach-Object { $ports[$_.Name] = $_.HostAddress }

    $f.Printers = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | ForEach-Object {
        $virtual = ($_.Name -match $script:VirtualPrinter) -or ([string]$_.DriverName -match $script:VirtualPrinter) -or ([string]$_.PortName -match $script:VirtualPort)
        $hostAddress = $ports[[string]$_.PortName]
        $reachable = $null
        if ($hostAddress -and -not $virtual) {
            $reachable = (Get-HcPingMs $hostAddress) -ge 0
            if (-not $reachable) { $reachable = (Get-HcPingMs $hostAddress) -ge 0 }
        }
        [pscustomobject]@{
            Name = $_.Name; Default = [bool]$_.Default; Virtual = $virtual
            Offline = ([bool]$_.WorkOffline -or $_.PrinterStatus -eq 7 -or $_.DetectedErrorState -eq 9)
            State = [int]$_.DetectedErrorState; HostAddress = $hostAddress; Reachable = $reachable
        }
    })
    $f.Jobs = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{ Printer = ($_.Name -split ',')[0]; Document = $_.Document; Submitted = $_.TimeSubmitted; Status = [string]$_.JobStatus }
    })
    $f
}

# Devices Windows reports a problem for, from Device Manager's own list.
function Get-HcProblemDevices {
    param([string]$Class)
    $all = if ($Class) { Get-PnpDevice -Class $Class -PresentOnly -ErrorAction SilentlyContinue } else { Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue }
    @($all | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
        [pscustomobject]@{ Name = $_.FriendlyName; Class = $_.Class; Code = [int]$_.ConfigManagerErrorCode; InstanceId = $_.InstanceId }
    })
}

function Get-HcUsbDrives {
    foreach ($disk in @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceType -eq 'USB' })) {
        $letters = @(Get-CimAssociatedInstance -InputObject $disk -ResultClassName Win32_DiskPartition -ErrorAction SilentlyContinue |
            ForEach-Object { Get-CimAssociatedInstance -InputObject $_ -ResultClassName Win32_LogicalDisk -ErrorAction SilentlyContinue } |
            ForEach-Object { $_.DeviceID })
        [pscustomobject]@{ Name = ($disk.Model -replace '\s+USB Device$', ''); Letters = $letters }
    }
}

function Get-HcInputFacts {
    [pscustomobject]@{
        Problems  = @(Get-HcProblemDevices)
        Keyboards = @(Get-CimInstance Win32_Keyboard -ErrorAction SilentlyContinue).Count
        Pointers  = @(Get-CimInstance Win32_PointingDevice -ErrorAction SilentlyContinue).Count
        UsbDrives = @(Get-HcUsbDrives)
    }
}

<#
    Bluetooth devices in Device Manager come in three kinds, told apart by
    their instance id: the adapter (USB\ or PCI\), paired devices
    (BTHENUM\DEV_ or BTHLE\DEV_) and Windows' own helpers (everything else).
    A paired device is "present" while it is connected.
#>
function Get-HcBluetoothFacts {
    $devices = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)
    $service = Get-Service -Name bthserv -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Adapters = @($devices | Where-Object { $_.InstanceId -match '^(USB|PCI|ACPI)\\' -and $_.Present } | ForEach-Object {
            [pscustomobject]@{ Name = $_.FriendlyName; Code = [int]$_.ConfigManagerErrorCode; InstanceId = $_.InstanceId }
        })
        ServiceRunning = ($service -and $service.Status -eq 'Running')
        Paired = @($devices | Where-Object { $_.InstanceId -match '^BTH(ENUM|LE)\\DEV_' } | ForEach-Object {
            [pscustomobject]@{ Name = $_.FriendlyName; Connected = [bool]$_.Present }
        } | Sort-Object Name -Unique)
    }
}

# ------------------------------------------------------------------ verdict --

# "switched off", "no driver installed", ... for a Device Manager error code.
function Get-HcDeviceReason {
    param([int]$Code)
    if ($script:Strings['en'].ContainsKey("dev.code.$Code")) { return (T "dev.code.$Code") }
    T 'dev.codeOther' $Code
}

# Lines, a finding and a fix for one device with a problem. Shared by C2 and C3.
function Add-HcDeviceProblem {
    param([pscustomobject]$Report, [hashtable]$Found, [pscustomobject]$Device)
    Add-HcLine $Report problem (T 'dev.deviceProblem' $Device.Name (Get-HcDeviceReason $Device.Code))
    $target = @{ Label = $Device.Name; InstanceId = $Device.InstanceId }
    switch ($Device.Code) {
        22      { Add-HcAction $Report 'enableDevice' $target; if (-not $Found['deviceDisabled']) { $Found['deviceDisabled'] = @($Device.Name) } }
        28      { if (-not $Found['deviceNoDriver']) { $Found['deviceNoDriver'] = @($Device.Name) } }
        default { Add-HcAction $Report 'restartDevice' $target; if (-not $Found['deviceError']) { $Found['deviceError'] = @($Device.Name, (Get-HcDeviceReason $Device.Code)) } }
    }
}

function Select-HcFinding {
    param([pscustomobject]$Report, [hashtable]$Found, [string[]]$Priority, [string]$Clean)
    foreach ($id in $Priority) {
        if ($Found.ContainsKey($id)) { Set-HcFinding $Report $id $Found[$id]; break }
    }
    Set-HcFinding $Report $Clean
}

# C1.
function Test-HcPrinter {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if (-not $Facts.SpoolerRunning) {
        Add-HcLine $r problem (T 'dev.spoolerStopped')
        Add-HcAction $r 'startSpooler'
        Set-HcFinding $r 'spoolerStopped'
        Add-HcLine $r skipped (T 'net.skipped')
        return $r
    }
    Add-HcLine $r ok (T 'dev.spoolerOk')

    $real = @($Facts.Printers | Where-Object { -not $_.Virtual })
    if ($real.Count -eq 0) {
        $virtualNames = @($Facts.Printers | ForEach-Object { $_.Name })
        $shown = if ($virtualNames.Count) { $virtualNames -join ', ' } else { T 'net.none' }
        Add-HcLine $r problem (T 'dev.noPrinter' $shown)
        Set-HcFinding $r 'noPrinter'
        return $r
    }

    foreach ($p in $real) {
        if ($p.Reachable -eq $false) {
            Add-HcLine $r problem (T 'dev.printerUnreachable' $p.Name $p.HostAddress)
            if (-not $found['printerUnreachable']) { $found['printerUnreachable'] = @($p.Name) }
        } elseif ($p.Offline) {
            Add-HcLine $r problem (T 'dev.printerOffline' $p.Name)
            if (-not $found['printerOffline']) { $found['printerOffline'] = @($p.Name) }
        } elseif ($script:PrinterStates.ContainsKey($p.State)) {
            $what = T "dev.state.$($p.State)"
            Add-HcLine $r $script:PrinterStates[$p.State] (T 'dev.printerState' $p.Name $what)
            if ($script:PrinterStates[$p.State] -eq 'problem' -and -not $found['printerAttention']) { $found['printerAttention'] = @($p.Name, $what) }
        } elseif ($p.Default) {
            Add-HcLine $r ok (T 'dev.printerReadyDefault' $p.Name)
        } else {
            Add-HcLine $r ok (T 'dev.printerReady' $p.Name)
        }
    }

    # The default printer: a real one, or documents never reach paper.
    $default = @($Facts.Printers | Where-Object { $_.Default }) | Select-Object -First 1
    $best = @($real | Where-Object { -not $_.Offline -and $_.Reachable -ne $false }) + $real | Select-Object -First 1
    if ($null -eq $default) {
        Add-HcLine $r problem (T 'dev.noDefault')
        Add-HcAction $r 'setDefault' @{ Label = $best.Name; Name = $best.Name }
        $found['noDefault'] = @()
    } elseif ($default.Virtual) {
        Add-HcLine $r problem (T 'dev.defaultVirtual' $default.Name)
        Add-HcAction $r 'setDefault' @{ Label = $best.Name; Name = $best.Name; Previous = $default.Name }
        $found['defaultVirtual'] = @($default.Name)
    }

    # The queue: documents waiting longer than a few minutes block the rest.
    $stuck = @($Facts.Jobs | Where-Object { $_.Status -match 'Error|Fout' -or ($_.Submitted -and $_.Submitted -lt $Facts.Now.AddMinutes(-$script:StuckMinutes)) })
    if ($stuck.Count) {
        $oldest = ($stuck | Sort-Object Submitted | Select-Object -First 1).Submitted
        $when = if ($oldest) { $oldest.ToString('HH:mm') } else { '?' }
        Add-HcLine $r problem (T 'dev.jobsStuck' $stuck.Count $when)
        Add-HcAction $r 'clearJobs'
        Add-HcAction $r 'restartSpooler'
        $found['jobsStuck'] = @()
    } else {
        Add-HcLine $r ok (T 'dev.jobsOk')
    }

    Select-HcFinding $r $found @('printerUnreachable', 'printerOffline', 'printerAttention', 'jobsStuck', 'defaultVirtual', 'noDefault') 'printerReady'
    if ($r.FindingId -eq 'printerReady') {
        $target = if ($default -and -not $default.Virtual) { $default } else { $best }
        Add-HcAction $r 'printTestPage' @{ Label = $target.Name; Name = $target.Name }
    }
    $r
}

# C2.
function Test-HcInputDevices {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($Facts.Keyboards -gt 0) { Add-HcLine $r ok (T 'dev.keyboardOk') } else { Add-HcLine $r warn (T 'dev.noKeyboard') }
    if ($Facts.Pointers -gt 0) {
        Add-HcLine $r ok (T 'dev.pointerOk')
    } else {
        Add-HcLine $r problem (T 'dev.noPointer')
        $found['noPointer'] = @()
    }
    foreach ($d in @($Facts.UsbDrives)) {
        if (@($d.Letters).Count) {
            Add-HcLine $r ok (T 'dev.usbDrive' $d.Name (@($d.Letters) -join ', '))
        } else {
            Add-HcLine $r problem (T 'dev.usbNoLetter' $d.Name)
            if (-not $found['usbNoLetter']) { $found['usbNoLetter'] = @($d.Name) }
        }
    }
    $problems = @($Facts.Problems)
    if ($problems.Count -eq 0) {
        Add-HcLine $r ok (T 'dev.noDeviceErrors')
    } else {
        foreach ($d in $problems) { Add-HcDeviceProblem $r $found $d }
    }
    Select-HcFinding $r $found @('noPointer', 'deviceDisabled', 'deviceError', 'deviceNoDriver', 'usbNoLetter') 'devicesOk'
    $r
}

# C3.
function Test-HcBluetooth {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    $adapters = @($Facts.Adapters)
    if ($adapters.Count -eq 0) {
        Add-HcLine $r problem (T 'dev.btNoAdapter')
        Set-HcFinding $r 'btNoAdapter'
        return $r
    }
    foreach ($a in $adapters) {
        if ($a.Code -eq 0) { Add-HcLine $r ok (T 'dev.btAdapter' $a.Name) } else { Add-HcDeviceProblem $r $found $a }
    }
    if ($Facts.ServiceRunning) {
        Add-HcLine $r ok (T 'dev.btServiceOk')
    } else {
        Add-HcLine $r problem (T 'dev.btServiceStopped')
        Add-HcAction $r 'startBtService'
        $found['btServiceStopped'] = @()
    }
    $paired = @($Facts.Paired)
    if ($paired.Count) {
        $names = @($paired | ForEach-Object { if ($_.Connected) { T 'dev.btConnected' $_.Name } else { T 'dev.btNotConnected' $_.Name } }) -join ', '
        Add-HcLine $r ok (T 'dev.btPaired' $names)
    } else {
        Add-HcLine $r ok (T 'dev.btNonePaired')
    }
    Select-HcFinding $r $found @('deviceDisabled', 'btServiceStopped', 'deviceError', 'deviceNoDriver') 'btOk'
    $r
}

# ---------------------------------------------------------------- handlers --

# ------------------------------------------------------------ C4: battery --

# Laptop, notebook, sub-notebook, tablet, convertible, detachable.
$script:LaptopChassis = @(8, 9, 10, 14, 30, 31, 32)
# Win32_Battery.BatteryStatus values that mean mains power is connected.
$script:OnMains = @(2, 3, 6, 7, 8, 9, 11)
$script:BatteryCharging = @(6, 7, 8, 9)
# Below this share of its original capacity a battery is worn out.
$script:BatteryWornPercent = 50
$script:BatteryAgingPercent = 70

function Get-HcBatteryFacts {
    $battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) | Select-Object -First 1
    $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $design = $null; $full = $null; $online = $null; $charging = $null
    try { $design = [int64](Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity } catch { }
    try { $full = [int64](Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity } catch { }
    try {
        $st = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
        if ($st) { $online = [bool]$st.PowerOnline; $charging = [bool]$st.Charging }
    } catch { }
    $status = if ($battery) { [int]$battery.BatteryStatus } else { $null }
    $plan = $null
    try { if ("$(powercfg /getactivescheme)" -match '\(([^)]+)\)\s*$') { $plan = $Matches[1] } } catch { }
    [pscustomobject]@{
        HasBattery = [bool]$battery
        Laptop     = [bool]@($chassis | Where-Object { $_ -in $script:LaptopChassis }).Count
        Charge     = $(if ($battery) { [int]$battery.EstimatedChargeRemaining })
        # Windows reports 71582788 minutes when it cannot estimate (on mains).
        RunMinutes = $(if ($battery -and $battery.EstimatedRunTime -and $battery.EstimatedRunTime -lt 10000) { [int]$battery.EstimatedRunTime })
        PluggedIn  = $(if ($null -ne $online) { $online } elseif ($null -ne $status) { $status -in $script:OnMains } else { $null })
        Charging   = $(if ($null -ne $charging) { $charging } elseif ($null -ne $status) { $status -in $script:BatteryCharging } else { $null })
        DesignMWh  = $design
        FullMWh    = $full
        PowerPlan  = $plan
    }
}

# How much of its original capacity the battery still holds; $null when
# Windows does not say.
function Get-HcBatteryHealth {
    param($DesignMWh, $FullMWh)
    if (-not $DesignMWh -or -not $FullMWh -or $DesignMWh -le 0) { return $null }
    [int][Math]::Min(100, [Math]::Round(100 * $FullMWh / $DesignMWh))
}

function Test-HcBattery {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if (-not $Facts.HasBattery) {
        if ($Facts.Laptop) {
            Add-HcLine $r problem (T 'bat.missing')
            $found['batteryMissing'] = @()
        } else {
            Add-HcLine $r ok (T 'bat.none')
            $found['noBattery'] = @()
        }
    } else {
        $health = Get-HcBatteryHealth $Facts.DesignMWh $Facts.FullMWh
        if ($null -eq $health) {
            Add-HcLine $r skipped (T 'bat.healthUnknown')
        } elseif ($health -lt $script:BatteryWornPercent) {
            Add-HcLine $r problem (T 'bat.health' $health)
            $found['batteryWorn'] = @($health)
        } elseif ($health -lt $script:BatteryAgingPercent) {
            Add-HcLine $r warn (T 'bat.health' $health)
            $found['batteryAging'] = @($health)
        } else {
            Add-HcLine $r ok (T 'bat.health' $health)
        }

        if ($Facts.PluggedIn) {
            if ($Facts.Charging) {
                Add-HcLine $r ok (T 'bat.charging' $Facts.Charge)
            } elseif ($Facts.Charge -ge 95) {
                Add-HcLine $r ok (T 'bat.full' $Facts.Charge)
            } elseif ($Facts.Charge -ge 55 -and $Facts.Charge -le 85) {
                # Many laptops stop around 60 or 80% on purpose, to spare the battery.
                Add-HcLine $r warn (T 'bat.holding' $Facts.Charge)
                $found['chargeLimit'] = @($Facts.Charge)
            } else {
                Add-HcLine $r problem (T 'bat.notCharging' $Facts.Charge)
                $found['notCharging'] = @($Facts.Charge)
            }
        } elseif ($null -ne $Facts.RunMinutes) {
            Add-HcLine $r ok (T 'bat.onBatteryTime' $Facts.Charge $Facts.RunMinutes)
        } else {
            Add-HcLine $r ok (T 'bat.onBattery' $Facts.Charge)
        }
        Add-HcAction $r 'openBatterySettings'
    }
    if ($Facts.PowerPlan) { Add-HcLine $r ok (T 'bat.plan' $Facts.PowerPlan) }

    Select-HcFinding $r $found @('batteryMissing', 'notCharging', 'batteryWorn', 'batteryAging', 'chargeLimit', 'noBattery') 'batteryOk'
    $r
}

function Invoke-HcC1 { { Test-HcPrinter (Get-HcPrinterFacts) } }
function Invoke-HcC2 { { Test-HcInputDevices (Get-HcInputFacts) } }
function Invoke-HcC3 { { Test-HcBluetooth (Get-HcBluetoothFacts) } }
function Invoke-HcC4 { { Test-HcBattery (Get-HcBatteryFacts) } }

$script:ProblemHandlers['C1'] = 'Invoke-HcC1'
$script:ProblemHandlers['C2'] = 'Invoke-HcC2'
$script:ProblemHandlers['C3'] = 'Invoke-HcC3'
$script:ProblemHandlers['C4'] = 'Invoke-HcC4'

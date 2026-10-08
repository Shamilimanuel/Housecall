<#
    E4: Windows 10, can this PC move to Windows 11? (6 Oct 2026)

    Windows 10's extra security updates (ESU) stop on 13 October 2026; after
    that it gets none at all. Microsoft's own requirements, each read here
    without administrator rights:

      processor     on Microsoft's list (Test-HcCpuWin11, by its generation)
      64-bit        Windows itself is 64-bit
      memory        4 GB or more
      storage       64 GB or more, and room for the upgrade (30 GB free)
      UEFI          the start-up firmware; the Secure Boot key exists only
                    there (an old "Legacy BIOS" start needs converting)
      Secure Boot   must be possible; it does not have to be on
      TPM 2.0       the security chip, from Device Manager's own list; often
                    simply switched off in the BIOS (fTPM on AMD, PTT on Intel)

    When Windows Update has already judged the PC for Windows 11, its
    verdict (green / red and why) is shown too. Housecall never upgrades by
    itself and never gets around a requirement: the steps say how, with a
    backup first.
#>

$script:Win11MinRamGB = 4
$script:Win11MinDiskGB = 64
$script:Win11FreeGB = 30
$script:Win11DownloadUrl = 'https://www.microsoft.com/software-download/windows11'

function Get-HcWin11Facts {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue) | Select-Object -First 1
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue

    # UEFI: Windows keeps a Secure Boot state only on a UEFI PC.
    $sb = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
    $fw = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction SilentlyContinue).PEFirmwareType
    $uefi = if ($sb) { $true } elseif ($fw -eq 2) { $true } elseif ($fw -eq 1) { $false } else { $null }

    # The TPM as Device Manager lists it: "Trusted Platform Module 2.0".
    $tpmDevice = @(Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%Trusted Platform%'" -ErrorAction SilentlyContinue) | Select-Object -First 1
    $tpm = if (-not $tpmDevice) { 'none' }
           elseif ([int]$tpmDevice.ConfigManagerErrorCode -ne 0) { 'error' }
           elseif ("$($tpmDevice.Name)" -match '2\.0') { '2.0' }
           elseif ("$($tpmDevice.Name)" -match '1\.2') { '1.2' }
           else { 'unknown' }

    [pscustomobject]@{
        Build          = [int]"$($cv.CurrentBuild)"
        DisplayVersion = "$($cv.DisplayVersion)"
        Edition        = "$($cv.EditionID)"
        Cpu            = "$($cpu.Name)".Trim()
        Bits64         = ("$($os.OSArchitecture)" -match '64')
        RamGB          = $(if ($cs) { [Math]::Round($cs.TotalPhysicalMemory / 1GB, 1) })
        DiskGB         = $(if ($disk) { [Math]::Round($disk.Size / 1GB) })
        FreeGB         = $(if ($disk) { [Math]::Round($disk.FreeSpace / 1GB) })
        Uefi           = $uefi
        SecureBootOn   = ($sb -and $sb.UEFISecureBootEnabled -eq 1)
        Tpm            = $tpm
        Verdict        = Get-HcWin11Verdict
        Today          = (Get-Date)
    }
}

<#
    Windows Update's own judgement, when it has made one: the newest of its
    upgrade appraisals, "Green" or "Red" and the reasons (like "Tpm
    UefiSecureBoot"). $null when there is none.
#>
function Get-HcWin11Verdict {
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators'
    $keys = @(Get-ChildItem $base -ErrorAction SilentlyContinue | Sort-Object PSChildName -Descending)
    foreach ($k in $keys) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($p.UpgEx) { return [pscustomobject]@{ Release = $k.PSChildName; Result = "$($p.UpgEx)"; Reason = "$($p.RedReason)".Trim() } }
    }
    $null
}

# Pure: the report.
function Test-HcWin11 {
    param([pscustomobject]$Facts)
    $f = $Facts
    $r = New-HcReport
    $found = @{}
    $culture = if ($script:Lang -eq 'nl') { 'nl-NL' } else { 'en-GB' }

    if ($f.Build -ge 22000) {
        Add-HcLine $r ok (T 'w11.already' $f.DisplayVersion)
        Add-HcAction $r 'openWindowsUpdate'
        Set-HcFinding $r 'win11Already'
        return $r
    }

    # The deadline first: why this matters now.
    $esu = [datetime]::Parse($script:Windows10EsuEnd, [Globalization.CultureInfo]::InvariantCulture)
    $esuText = $esu.ToString('d MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo($culture))
    if ($f.Today -lt $esu) {
        Add-HcLine $r warn (T 'w11.esuSoon' $esuText ([int][Math]::Ceiling(($esu - $f.Today).TotalDays)))
    } else {
        Add-HcLine $r problem (T 'w11.esuEnded' $esuText)
    }

    # What cannot be fixed on the spot.
    $cpuOk = Test-HcCpuWin11 $f.Cpu
    if ($cpuOk -eq $true) { Add-HcLine $r ok (T 'w11.cpuOk' $f.Cpu) }
    elseif ($cpuOk -eq $false) { Add-HcLine $r problem (T 'w11.cpuNo' $f.Cpu); $found['win11NotPossible'] = @(T 'w11.why.cpu') }
    else { Add-HcLine $r skipped (T 'w11.cpuUnknown' $f.Cpu) }
    if (-not $f.Bits64) { Add-HcLine $r problem (T 'w11.bits32'); if (-not $found['win11NotPossible']) { $found['win11NotPossible'] = @(T 'w11.why.bits') } }
    if ($null -ne $f.RamGB) {
        if ($f.RamGB -lt $script:Win11MinRamGB - 0.3) { Add-HcLine $r problem (T 'w11.ramLow' $f.RamGB); if (-not $found['win11NotPossible']) { $found['win11NotPossible'] = @(T 'w11.why.ram') } }
        else { Add-HcLine $r ok (T 'w11.ramOk' ([Math]::Round($f.RamGB))) }
    }
    if ($null -ne $f.DiskGB) {
        if ($f.DiskGB -lt $script:Win11MinDiskGB - 4) { Add-HcLine $r problem (T 'w11.diskSmall' $f.DiskGB); if (-not $found['win11NotPossible']) { $found['win11NotPossible'] = @(T 'w11.why.disk') } }
        elseif ($f.FreeGB -lt $script:Win11FreeGB) { Add-HcLine $r warn (T 'w11.freeLow' $f.FreeGB $script:Win11FreeGB); $found['win11Space'] = @($f.FreeGB) }
        else { Add-HcLine $r ok (T 'w11.freeOk' $f.FreeGB) }
    }

    # What is often only a BIOS setting.
    switch ($f.Tpm) {
        '2.0'   { Add-HcLine $r ok (T 'w11.tpmOk') }
        '1.2'   { Add-HcLine $r problem (T 'w11.tpm12'); if (-not $found['win11NotPossible']) { $found['win11NotPossible'] = @(T 'w11.why.tpm') } }
        default { Add-HcLine $r problem (T 'w11.tpmNone'); $found['win11TpmOff'] = @() }
    }
    if ($f.Uefi -eq $true) {
        Add-HcLine $r ok $(if ($f.SecureBootOn) { T 'w11.uefiSbOn' } else { T 'w11.uefiSbOff' })
    } elseif ($f.Uefi -eq $false) {
        Add-HcLine $r problem (T 'w11.legacy')
        $found['win11Legacy'] = @()
    } else {
        Add-HcLine $r skipped (T 'w11.uefiUnknown')
    }

    # Windows Update's own verdict, when there is one.
    if ($f.Verdict) {
        if ($f.Verdict.Result -match 'Green') { Add-HcLine $r ok (T 'w11.msGreen') }
        elseif ($f.Verdict.Result -match 'Red') { Add-HcLine $r warn (T 'w11.msRed' $(if ($f.Verdict.Reason) { $f.Verdict.Reason } else { '?' })) }
    }

    if ($found['win11NotPossible']) {
        Add-HcAction $r 'openWin11Download'
    } else {
        Add-HcAction $r 'openWindowsUpdate'
        Add-HcAction $r 'openWin11Download'
    }
    Select-HcFinding $r $found @('win11NotPossible', 'win11TpmOff', 'win11Legacy', 'win11Space') 'win11Ready'
    $r
}

function Invoke-HcE4 { { Test-HcWin11 (Get-HcWin11Facts) } }

$script:ProblemHandlers['E4'] = 'Invoke-HcE4'

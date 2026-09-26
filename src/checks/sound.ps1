<#
    Area B: Sound, screen & video calls.

      B1  no sound                      sound service, sound hardware, outputs, mute, volume
      B2  microphone or camera          microphones, cameras, Windows privacy switches
      B3  screen too small, dark, wrong colour filter, high contrast, magnifier,
                                        brightness, orientation, scale

    Sound is read through Core Audio (src\checks\audio-interop.ps1); the
    privacy switches straight from the registry, where Settings keeps them.
#>

# Outputs that are a screen or a digital socket: fine when the screen has
# speakers and is on, silent otherwise -- the classic "sound went to the TV".
$script:ScreenOutput = '(AMD|NVIDIA|Intel).*(High Definition Audio|Display Audio)|HDMI|DisplayPort|Digital Output|S/PDIF|SPDIF'

# Where Settings keeps "may apps use the microphone / camera".
$script:ConsentStore = 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'

# Video-call apps from the Store, by the start of their key under ConsentStore.
# Desktop programs (Zoom, Teams classic, Skype desktop) share one switch: NonPackaged.
$script:CallApps = [ordered]@{
    '5319275A.WhatsAppDesktop' = 'WhatsApp'
    'MSTeams'                  = 'Microsoft Teams'
    'MicrosoftTeams'           = 'Microsoft Teams'
    'Microsoft.SkypeApp'       = 'Skype'
    'Microsoft.WindowsCamera'  = 'Camera'
    'FACEBOOK.317180B0BB486'   = 'Messenger'
    'Zoom'                     = 'Zoom'
}

# ------------------------------------------------------------------- facts --

function Get-HcSoundFacts {
    $running = { param($n) $s = Get-Service -Name $n -ErrorAction SilentlyContinue; $s -and $s.Status -eq 'Running' }
    [pscustomobject]@{
        ServiceRunning = (& $running 'Audiosrv') -and (& $running 'AudioEndpointBuilder')
        Problems       = @(Get-HcProblemDevices 'MEDIA')
        Outputs        = Get-HcAudioDevices 0
    }
}

# One privacy switch: the whole PC (HKLM), apps (HKCU), desktop programs
# (NonPackaged), or one app. Only switches set to Deny matter.
function Get-HcPrivacyBlocks {
    param([string]$Capability)
    $blocks = @()
    $value = { param($path) (Get-ItemProperty $path -ErrorAction SilentlyContinue).Value }
    $user = "HKCU:\$script:ConsentStore\$Capability"
    if ((& $value "HKLM:\$script:ConsentStore\$Capability") -eq 'Deny') {
        $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'all'; Name = $null; Key = "HKLM:\$script:ConsentStore\$Capability"; Machine = $true }
    }
    if ((& $value $user) -eq 'Deny') {
        $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'apps'; Name = $null; Key = $user; Machine = $false }
    }
    if ((& $value "$user\NonPackaged") -eq 'Deny') {
        $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'desktop'; Name = $null; Key = "$user\NonPackaged"; Machine = $false }
    }
    foreach ($key in @(Get-ChildItem $user -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'NonPackaged' })) {
        foreach ($prefix in $script:CallApps.Keys) {
            if ($key.PSChildName.StartsWith($prefix) -and (& $value $key.PSPath) -eq 'Deny') {
                $blocks += [pscustomobject]@{ Capability = $Capability; Who = 'app'; Name = $script:CallApps[$prefix]; Key = "$user\$($key.PSChildName)"; Machine = $false }
            }
        }
    }
    $blocks
}

function Get-HcCallFacts {
    $cameras = @(Get-PnpDevice -Class Camera, Image -PresentOnly -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Microphones = Get-HcAudioDevices 1
        Cameras     = @($cameras | Where-Object { $_.ConfigManagerErrorCode -eq 0 } | ForEach-Object { $_.FriendlyName })
        Problems    = @($cameras | Where-Object { $_.ConfigManagerErrorCode -ne 0 } | ForEach-Object {
            [pscustomobject]@{ Name = $_.FriendlyName; Class = $_.Class; Code = [int]$_.ConfigManagerErrorCode; InstanceId = $_.InstanceId } })
        Blocks      = @(Get-HcPrivacyBlocks 'microphone') + @(Get-HcPrivacyBlocks 'webcam')
    }
}

function Get-HcScreenFacts {
    $brightness = $null
    try { $brightness = [int](Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop | Select-Object -First 1).CurrentBrightness } catch { }
    $portrait = $false
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
        $portrait = $b.Height -gt $b.Width
    } catch { }
    $dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction SilentlyContinue).AppliedDPI
    $text = (Get-ItemProperty 'HKCU:\Software\Microsoft\Accessibility' -ErrorAction SilentlyContinue).TextScaleFactor
    $contrast = (Get-ItemProperty 'HKCU:\Control Panel\Accessibility\HighContrast' -ErrorAction SilentlyContinue).Flags
    [pscustomobject]@{
        Brightness   = $brightness
        ColorFilter  = ((Get-ItemProperty 'HKCU:\Software\Microsoft\ColorFiltering' -ErrorAction SilentlyContinue).Active -eq 1)
        HighContrast = ($contrast -and ([int]$contrast -band 1))
        Magnifier    = [bool](Get-Process -Name Magnify -ErrorAction SilentlyContinue)
        Portrait     = $portrait
        Scale        = $(if ($dpi) { [int]([int]$dpi * 100 / 96) } else { 100 })
        TextSize     = $(if ($text) { [int]$text } else { 100 })
    }
}

# ------------------------------------------------------------------ verdict --

# B1.
function Test-HcSound {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if (-not $Facts.ServiceRunning -or $null -eq $Facts.Outputs) {
        Add-HcLine $r problem (T 'snd.serviceStopped')
        Add-HcAction $r 'restartAudio'
        Set-HcFinding $r 'audioServiceStopped'
        return $r
    }
    Add-HcLine $r ok (T 'snd.serviceOk')
    foreach ($d in @($Facts.Problems)) { Add-HcDeviceProblem $r $found $d }

    $outputs = @($Facts.Outputs)
    if ($outputs.Count -eq 0) {
        Add-HcLine $r problem (T 'snd.noOutput')
        Select-HcFinding $r $found @('deviceDisabled', 'deviceError', 'deviceNoDriver') 'noOutput'
        return $r
    }

    $default = @($outputs | Where-Object { $_.IsDefault }) | Select-Object -First 1
    if (-not $default) { $default = $outputs[0] }
    Add-HcLine $r ok (T 'snd.default' $default.Name $default.Volume)
    if ($default.Muted) {
        Add-HcLine $r problem (T 'snd.muted' $default.Name)
        Add-HcAction $r 'unmute' @{ Label = $default.Name; Id = $default.Id }
        $found['muted'] = @($default.Name)
    }
    if ($default.Volume -ge 0 -and $default.Volume -le 5) {
        Add-HcLine $r problem (T 'snd.volumeLow' $default.Name $default.Volume)
        Add-HcAction $r 'setVolume' @{ Label = $default.Name; Id = $default.Id; Percent = 50; Previous = $default.Volume }
        $found['volumeLow'] = @($default.Name, $default.Volume)
    }
    $others = @($outputs | Where-Object { $_.Id -ne $default.Id })
    $speakers = @($others | Where-Object { $_.Name -notmatch $script:ScreenOutput })
    if ($default.Name -match $script:ScreenOutput -and $speakers.Count) {
        Add-HcLine $r warn (T 'snd.defaultScreen' $default.Name)
        $found['defaultScreen'] = @($default.Name)
    }
    if ($others.Count) { Add-HcLine $r ok (T 'snd.others' (@($others | ForEach-Object { $_.Name }) -join ', ')) }

    # Speakers and headphones first, then screens; the test sound last.
    foreach ($o in @($speakers) + @($others | Where-Object { $_.Name -match $script:ScreenOutput }) | Select-Object -First 5) {
        Add-HcAction $r 'setDefaultAudio' @{ Label = $o.Name; Id = $o.Id; PreviousId = $default.Id }
    }
    Add-HcAction $r 'testSound'

    Select-HcFinding $r $found @('deviceDisabled', 'deviceError', 'deviceNoDriver', 'muted', 'volumeLow', 'defaultScreen') 'soundOk'
    if ($r.FindingId -eq 'soundOk') { $r.FindingArgs = @($default.Name) }
    $r
}

# "WhatsApp", "Apps", ... for a privacy block, in the current language.
function Get-HcBlockWho {
    param([pscustomobject]$Block)
    if ($Block.Who -eq 'app') { return $Block.Name }
    T ('priv.' + $Block.Who)
}

# B2.
function Test-HcCalls {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    $mics = $Facts.Microphones
    if ($null -eq $mics -or @($mics).Count -eq 0) {
        Add-HcLine $r problem (T 'call.noMic')
        $found['noMic'] = @()
    } else {
        $mic = @(@($mics) | Where-Object { $_.IsDefault }) | Select-Object -First 1
        if (-not $mic) { $mic = @($mics)[0] }
        Add-HcLine $r ok (T 'call.mic' $mic.Name $mic.Volume)
        if ($mic.Muted) {
            Add-HcLine $r problem (T 'call.micMuted' $mic.Name)
            Add-HcAction $r 'unmute' @{ Label = $mic.Name; Id = $mic.Id }
            $found['micMuted'] = @($mic.Name)
        } elseif ($mic.Volume -ge 0 -and $mic.Volume -lt 10) {
            Add-HcLine $r problem (T 'call.micLow' $mic.Name $mic.Volume)
            Add-HcAction $r 'setVolume' @{ Label = $mic.Name; Id = $mic.Id; Percent = 80; Previous = $mic.Volume }
            $found['micLow'] = @($mic.Name)
        }
    }

    foreach ($c in @($Facts.Cameras)) { Add-HcLine $r ok (T 'call.camera' $c) }
    foreach ($d in @($Facts.Problems)) { Add-HcDeviceProblem $r $found $d }
    if (@($Facts.Cameras).Count -eq 0 -and @($Facts.Problems).Count -eq 0) {
        Add-HcLine $r warn (T 'call.noCamera')
        $found['noCamera'] = @()
    }

    foreach ($capability in @('microphone', 'webcam')) {
        $blocks = @($Facts.Blocks | Where-Object { $_.Capability -eq $capability })
        $what = T "priv.$capability"
        if ($blocks.Count -eq 0) { Add-HcLine $r ok (T 'call.privacyOk' $what); continue }
        foreach ($b in $blocks) {
            $who = Get-HcBlockWho $b
            Add-HcLine $r problem (T 'call.blocked' $who $what)
            $fix = if ($b.Machine) { 'allowAccessMachine' } else { 'allowAccess' }
            Add-HcAction $r $fix @{ Label = "$who, $what"; Key = $b.Key }
            if (-not $found['privacyBlocked']) { $found['privacyBlocked'] = @($who, $what) }
        }
    }

    Select-HcFinding $r $found @('privacyBlocked', 'micMuted', 'noMic', 'deviceDisabled', 'deviceError', 'deviceNoDriver', 'micLow', 'noCamera') 'callsOk'
    $r
}

# B3.
function Test-HcScreen {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}

    if ($null -ne $Facts.Brightness) {
        if ($Facts.Brightness -lt 30) {
            Add-HcLine $r problem (T 'scr.tooDark' $Facts.Brightness)
            Add-HcAction $r 'setBrightness' @{ Label = ''; Percent = 80; Previous = $Facts.Brightness }
            $found['tooDark'] = @($Facts.Brightness)
        } else {
            Add-HcLine $r ok (T 'scr.brightness' $Facts.Brightness)
        }
    }
    if ($Facts.ColorFilter) { Add-HcLine $r problem (T 'scr.colorFilter'); $found['colorFilter'] = @() }
    if ($Facts.HighContrast) { Add-HcLine $r problem (T 'scr.highContrast'); $found['highContrast'] = @() }
    if ($Facts.Magnifier) {
        Add-HcLine $r problem (T 'scr.magnifier')
        Add-HcAction $r 'closeMagnifier'
        $found['magnifier'] = @()
    }
    if (-not ($Facts.ColorFilter -or $Facts.HighContrast -or $Facts.Magnifier)) { Add-HcLine $r ok (T 'scr.normal') }
    if ($Facts.Portrait) { Add-HcLine $r warn (T 'scr.rotated'); $found['rotated'] = @() }
    Add-HcLine $r ok (T 'scr.scale' $Facts.Scale $Facts.TextSize)

    Select-HcFinding $r $found @('tooDark', 'colorFilter', 'highContrast', 'magnifier', 'rotated') 'screenOk'
    $r
}

# ---------------------------------------------------------------- handlers --

function Invoke-HcB1 { { Test-HcSound (Get-HcSoundFacts) } }
function Invoke-HcB2 { { Test-HcCalls (Get-HcCallFacts) } }
function Invoke-HcB3 { { Test-HcScreen (Get-HcScreenFacts) } }

$script:ProblemHandlers['B1'] = 'Invoke-HcB1'
$script:ProblemHandlers['B2'] = 'Invoke-HcB2'
$script:ProblemHandlers['B3'] = 'Invoke-HcB3'

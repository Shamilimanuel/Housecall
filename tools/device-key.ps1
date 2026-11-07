<#
    The device key for the tools in this folder (25 Oct): the same file and
    the same reading as Housecall itself (src\relay.ps1, Get-HcDeviceKey).
    Dot-sourced by overview.ps1, setup-invoice.ps1, setup-mail.ps1 and
    register-device.ps1, which run only on Shamil's own PCs. With the key, a
    code gives the full pass; without it the relay refuses the overview and
    the business details.
#>

$script:HcDeviceKeyPath = Join-Path $env:LOCALAPPDATA 'Housecall\device.key'

function Get-HcDeviceKey {
    if (-not (Test-Path -LiteralPath $script:HcDeviceKeyPath)) { return $null }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($script:HcDeviceKeyPath), $null, 'CurrentUser')
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        if ($text -match '^[A-Za-z0-9_-]{40,100}$') { return $text }
    } catch { }
    $null
}

# The unlock request: the code, and the device key when this PC has one.
function New-HcToolUnlock {
    param([string]$Code)
    $body = @{ action = 'unlock'; code = $Code }
    $key = Get-HcDeviceKey
    if ($key) { $body.device_key = $key }
    $body
}

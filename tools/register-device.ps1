<#
    Makes this PC one of your own devices (25 Oct). Run it once on each of
    your own PCs -- never on a client's PC:

        powershell -ExecutionPolicy Bypass -File tools\register-device.ps1

    It makes a random device key, locks it to your Windows account with
    Windows' own encryption (DPAPI) in %LOCALAPPDATA%\Housecall\device.key,
    and registers it at the relay with two codes from Google Authenticator,
    one after the other. Only the key's fingerprint (SHA-256) goes to the
    relay; the key itself only goes along when you unlock.

    With the key, a code gives the full pass: Alle klanten, the overview,
    your business details, Corrigeren for any client. Without it (a client's
    PC) a code gives a pass for that one PC only, so a client's PC with
    malware can never reach your other clients' data.

    Two codes, because a single code you type on a client's PC (where a
    keylogger could see it) must never be enough to add a device.

        -Remove   deletes this PC's key (the relay's list keeps the
                  fingerprint; it can no longer be used without the key)
#>
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'device-key.ps1')
$RelayUrl = 'https://btwbtxjawubtgeizcrir.supabase.co/functions/v1/housecall'

function Invoke-Relay {
    param([hashtable]$Body)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Body -Depth 10 -Compress))
    try {
        $r = Invoke-WebRequest -Uri $RelayUrl -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 60
        $reader = New-Object IO.StreamReader($r.RawContentStream, [Text.Encoding]::UTF8)
        return ($reader.ReadToEnd() | ConvertFrom-Json)
    } catch {
        $response = $_.Exception.Response
        if ($response) {
            $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
            return ($reader.ReadToEnd() | ConvertFrom-Json)
        }
        throw
    }
}

Write-Host ''
Write-Host '  Housecall: this PC as one of your own devices' -ForegroundColor Yellow
Write-Host ''

if ($Remove) {
    Remove-Item -LiteralPath $script:HcDeviceKeyPath -ErrorAction SilentlyContinue
    Write-Host "  Removed $script:HcDeviceKeyPath"
    return
}

$key = Get-HcDeviceKey
if (-not $key) {
    # 32 random bytes as text (base64url), locked to this Windows user.
    $raw = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($raw)
    $rng.Dispose()
    $key = [Convert]::ToBase64String($raw).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    Add-Type -AssemblyName System.Security
    New-Item -ItemType Directory -Path (Split-Path -Parent $script:HcDeviceKeyPath) -Force | Out-Null
    [IO.File]::WriteAllBytes($script:HcDeviceKeyPath, [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($key), $null, 'CurrentUser'))
    Write-Host "  A new device key is in $script:HcDeviceKeyPath (only your Windows account can read it)."
} else {
    Write-Host '  This PC already has a device key; it is registered again.'
}
$sha = [Security.Cryptography.SHA256]::Create()
$hash = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key)) | ForEach-Object { $_.ToString('x2') }) -join '')
$sha.Dispose()

Write-Host ''
Write-Host '  Two codes from Google Authenticator, one after the other.'
$code1 = ((Read-Host '  The code the app shows now') -replace '\s', '')
Write-Host '  Wait until the app shows a NEW code (every 30 seconds).'
$code2 = ((Read-Host '  The next code') -replace '\s', '')
$name = "$env:COMPUTERNAME".Trim()
$r = Invoke-Relay @{ action = 'device_register'; code1 = $code1; code2 = $code2; hash = $hash; name = $name }
if ($r.registered) {
    Write-Host ''
    Write-Host "  Done: $name is one of your own devices. Housecall and the tools on this PC now get the full pass." -ForegroundColor Green
} else {
    $why = switch ($r.error) {
        'wrong_code' { 'one of the codes was not right, or both were the same code. Run this again.' }
        'code_used'  { 'a code was already used. Wait for a new one and run this again.' }
        'locked'     { 'too many wrong codes: wait 15 minutes.' }
        'locked_day' { 'Housecall is locked for a day after too many wrong codes.' }
        default      { "the relay said: $($r.error)" }
    }
    Write-Host "  Not registered: $why" -ForegroundColor Red
}
Write-Host ''

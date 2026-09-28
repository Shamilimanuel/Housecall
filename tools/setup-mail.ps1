<#
    Connects your Outlook (shamilimanuel@outlook.com) so Housecall can mail
    a note, receipt or invoice to a client from it. Run it once on your own
    PC, and again if Housecall says the link has expired:

        powershell -ExecutionPolicy Bypass -File tools\setup-mail.ps1
        powershell -ExecutionPolicy Bypass -File tools\setup-mail.ps1 -Disconnect

    Microsoft no longer lets programs send mail with just a password
    (since March 2026). So Housecall gets its own small "app registration"
    at Microsoft, you sign in once, and the relay keeps the sign-in (a
    refresh token) in your Supabase. It never reaches a client's PC and it
    can only send mail, nothing else in your mailbox.
#>
param([switch]$Disconnect)

$ErrorActionPreference = 'Stop'
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
Write-Host '  Housecall: mail from your Outlook' -ForegroundColor Yellow
Write-Host ''

$code = (Read-Host '  Code from Google Authenticator').Trim()
$unlock = Invoke-Relay @{ action = 'unlock'; code = $code }
if (-not $unlock.token) { Write-Host "  That did not work: $($unlock.error)" -ForegroundColor Red; return }
$token = $unlock.token

$status = Invoke-Relay @{ action = 'mail_status'; token = $token }
if ($Disconnect) {
    $null = Invoke-Relay @{ action = 'mail_disconnect'; token = $token }
    Write-Host '  Disconnected. Housecall can no longer send mail from your Outlook.' -ForegroundColor Green
    Write-Host '  (To remove the app completely: account.live.com/consent/Manage, and the app registration.)'
    return
}
if ($status.connected) {
    Write-Host "  Already connected: $($status.email)" -ForegroundColor Green
    if ((Read-Host '  Connect again? (y/N)').Trim() -notmatch '^(y|j)') { return }
}

Write-Host ''
Write-Host '  Step 1, once: the app registration at Microsoft (about 5 minutes)' -ForegroundColor Cyan
Write-Host '   1. Open https://entra.microsoft.com and sign in with shamilimanuel@outlook.com.'
Write-Host '      (Asked to make a free Azure account first? That is Microsoft''s free sign-up.)'
Write-Host '   2. App registrations > New registration.'
Write-Host '        Name: Housecall mail'
Write-Host '        Supported account types: Personal Microsoft accounts only'
Write-Host '        Redirect URI: leave empty.  Then Register.'
Write-Host '   3. Authentication > Allow public client flows: Yes > Save.'
Write-Host '   4. API permissions > Add a permission > Microsoft Graph > Delegated > Mail.Send > Add.'
Write-Host '   5. Overview: copy the Application (client) ID.'
Write-Host ''
$clientId = ''
while ($clientId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
    $clientId = (Read-Host '  Application (client) ID').Trim()
}

$start = Invoke-Relay @{ action = 'mail_start'; token = $token; client_id = $clientId }
if (-not $start.device_code) { Write-Host "  Microsoft said no: $($start.detail)" -ForegroundColor Red; return }

Write-Host ''
Write-Host '  Step 2: sign in once' -ForegroundColor Cyan
Write-Host "   Go to $($start.verification_uri) (it opens by itself), type this code:"
Write-Host ''
Write-Host "        $($start.user_code)" -ForegroundColor Yellow
Write-Host ''
Write-Host '   Sign in with shamilimanuel@outlook.com and allow "Housecall mail" to send mail.'
try { Start-Process $start.verification_uri } catch { }

$deadline = (Get-Date).AddSeconds([int]$start.expires_in)
$interval = [Math]::Max(3, [int]$start.interval)
$done = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $interval
    $r = Invoke-Relay @{ action = 'mail_finish'; token = $token; client_id = $clientId; device_code = $start.device_code }
    if ($r.pending) { Write-Host '.' -NoNewline; continue }
    $done = $r
    break
}
Write-Host ''
if (-not $done -or -not $done.connected) {
    $why = if ($done) { $done.detail } else { 'the code expired' }
    Write-Host "  Not connected: $why. Run this script again." -ForegroundColor Red
    return
}
Write-Host "  Connected: $($done.email)" -ForegroundColor Green

if ((Read-Host '  Send a test mail to yourself? (Y/n)').Trim() -notmatch '^(n)') {
    $test = Invoke-Relay @{ action = 'mail_send'; token = $token; to = $done.email
        subject = 'Housecall test'; text = "This mail was sent by Housecall through your Outlook.`n`nIf you can read it, mailing notes and invoices to clients works." }
    if ($test.sent) { Write-Host "  Test mail sent to $($done.email). Check your inbox (and Sent Items)." -ForegroundColor Green }
    else { Write-Host "  The test mail failed: $($test.error) $($test.detail)" -ForegroundColor Red }
}

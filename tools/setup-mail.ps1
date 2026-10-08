<#
    Connects mail from your own domain so Housecall can mail a note,
    receipt or invoice to a client. Run it once on your own PC
    (housecall -Mail):

        powershell -ExecutionPolicy Bypass -File tools\setup-mail.ps1
        powershell -ExecutionPolicy Bypass -File tools\setup-mail.ps1 -Disconnect

    Changed 6 Oct 2026: first this connected Outlook through a Microsoft app
    registration, which was too much of a hurdle. Now the relay sends
    through Gmail with an app password (a separate password that can only
    be used for mail, and can be removed at Google at any time). The app
    password goes into Supabase as a secret, typed there by you; this script
    and Housecall never see it. Replies from clients go to the email address
    in your business details (your Outlook).

    Changed 8 Oct 2026: mail goes out through Resend, from an address on
    your own domain (verified at Resend). The relay still uses a Gmail when
    the GMAIL_ secrets are set and the Resend ones are not.
#>
param([switch]$Disconnect)

$ErrorActionPreference = 'Stop'
$RelayUrl = 'https://btwbtxjawubtgeizcrir.supabase.co/functions/v1/housecall'
$SecretsUrl = 'https://supabase.com/dashboard/project/btwbtxjawubtgeizcrir/functions/secrets'

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
Write-Host '  Housecall: mail from your own domain' -ForegroundColor Yellow
Write-Host ''

if ($Disconnect) {
    Write-Host '  To stop Housecall from mailing:'
    Write-Host "   1. Supabase, Edge Functions > Secrets: delete RESEND_API_KEY and MAIL_FROM."
    Write-Host '      ' $SecretsUrl
    Write-Host '   2. Resend: delete the API key "Housecall" at https://resend.com/api-keys'
    try { Start-Process $SecretsUrl } catch { }
    return
}

$health = Invoke-Relay @{ action = 'health' }
if (-not $health.resend) {
    Write-Host '  Once, about 5 minutes (your domain is already verified at Resend):' -ForegroundColor Cyan
    Write-Host '   1. Resend, API Keys > Create API Key:'
    Write-Host '        Name        Housecall'
    Write-Host '        Permission  Sending access'
    Write-Host '        Domain      your domain'
    Write-Host '      Copy the key (it starts with re_). Resend shows it only once.'
    Write-Host '        https://resend.com/api-keys'
    Write-Host '   2. In Supabase, Edge Functions > Secrets, add two secrets:'
    Write-Host '        RESEND_API_KEY  the key'
    Write-Host '        MAIL_FROM       the address clients see, e.g. info@ and your domain'
    Write-Host "        $SecretsUrl"
    Write-Host ''
    Write-Host '  The key goes only into Supabase: not here, not in a chat.' -ForegroundColor DarkGray
    Write-Host ''
    if ((Read-Host '  Open these pages now? (Y/n)').Trim() -notmatch '^n') {
        foreach ($url in 'https://resend.com/api-keys', $SecretsUrl) {
            try { Start-Process $url } catch { }
        }
    }
    for ($try = 1; -not $health.resend; $try++) {
        $null = Read-Host '  Press Enter when the two secrets are saved'
        $health = Invoke-Relay @{ action = 'health' }
        if (-not $health.resend) {
            Write-Host '  The relay does not see them yet: check both names, that the key starts with re_, and that MAIL_FROM is a whole address.' -ForegroundColor Red
            if ($try -ge 3) { Write-Host '  Run this script again when they are there.'; return }
        }
    }
}

$code = (Read-Host '  Code from Google Authenticator').Trim()
$unlock = Invoke-Relay @{ action = 'unlock'; code = $code }
if (-not $unlock.token) { Write-Host "  That did not work: $($unlock.error)" -ForegroundColor Red; return }
$token = $unlock.token

$status = Invoke-Relay @{ action = 'mail_status'; token = $token }
Write-Host "  Connected: mail goes out from $($status.email)" -ForegroundColor Green

$to = (Read-Host '  Send a test mail to (your own address)').Trim()
if (-not $to) { Write-Host '  No address: no test mail.'; return }
$test = Invoke-Relay @{ action = 'mail_send'; token = $token; to = $to
    subject = 'Housecall test'; text = "This mail was sent by Housecall from your own domain.`n`nIf you can read it, mailing notes and invoices to clients works. Answer it to see where replies arrive." }
if ($test.sent) {
    Write-Host "  Test mail sent to $to. Check the inbox (and the spam folder, the first time)." -ForegroundColor Green
} elseif ($test.error -eq 'mail_reconnect') {
    Write-Host '  Resend refused the key. Make a new one (Sending access) and replace RESEND_API_KEY in Supabase.' -ForegroundColor Red
} else {
    Write-Host "  The test mail failed: $($test.error) $($test.detail)" -ForegroundColor Red
}

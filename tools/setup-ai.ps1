<#
    One-time setup of the AI chat and visit memory, on Shamil's own PC.

        powershell -ExecutionPolicy Bypass -File tools\setup-ai.ps1

    1. Makes a new Google Authenticator secret, shows it as a QR code (in the
       browser, drawn locally) and as a key to type, and checks that the
       code on the phone matches.
    2. Puts the secret on the clipboard for the Supabase secret
       HOUSECALL_TOTP_SECRET, and clears the clipboard afterwards.
    3. Opens the pages to make an Anthropic API key (Supabase secret
       ANTHROPIC_API_KEY) and to set a monthly spending limit.
    4. Asks the relay whether everything is set.

    The secret is shown on this screen once and is never saved to a file,
    except for a few seconds in the QR page, which is deleted when you press
    Enter. Running it again makes a NEW secret: the old Authenticator entry
    then stops working (delete it from the app).

    -Check only asks the relay whether everything is set (no new secret).
    -FunctionsOnly loads the functions without running anything (for tests).
#>
param([switch]$Check, [switch]$FunctionsOnly)

$ErrorActionPreference = 'Stop'
$RelayUrl = 'https://btwbtxjawubtgeizcrir.supabase.co/functions/v1/housecall'
$SecretsPage = 'https://supabase.com/dashboard/project/btwbtxjawubtgeizcrir/functions/secrets'

function ConvertTo-Base32 {
    param([byte[]]$Bytes)
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $out = New-Object System.Text.StringBuilder
    $buffer = 0
    $bits = 0
    foreach ($b in $Bytes) {
        $buffer = (($buffer -shl 8) -bor $b) -band 0xFFFF
        $bits += 8
        while ($bits -ge 5) {
            [void]$out.Append($alphabet[($buffer -shr ($bits - 5)) -band 31])
            $bits -= 5
        }
    }
    if ($bits -gt 0) { [void]$out.Append($alphabet[($buffer -shl (5 - $bits)) -band 31]) }
    $out.ToString()
}

function ConvertFrom-Base32 {
    param([string]$Text)
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $bytes = New-Object System.Collections.Generic.List[byte]
    $buffer = 0
    $bits = 0
    foreach ($c in ($Text.ToUpperInvariant() -replace '[^A-Z2-7]', '').ToCharArray()) {
        $buffer = (($buffer -shl 5) -bor $alphabet.IndexOf($c)) -band 0xFFFF
        $bits += 5
        if ($bits -ge 8) {
            $bytes.Add([byte](($buffer -shr ($bits - 8)) -band 0xFF))
            $bits -= 8
        }
    }
    $bytes.ToArray()
}

# RFC 6238 (HMAC-SHA1, 30 s, 6 digits), the same as the relay and the app.
function Get-Totp {
    param([byte[]]$Key, [long]$Step)
    $counter = [BitConverter]::GetBytes($Step)
    if ([BitConverter]::IsLittleEndian) { [array]::Reverse($counter) }
    $hmac = New-Object System.Security.Cryptography.HMACSHA1 (, $Key)
    try { $mac = $hmac.ComputeHash($counter) } finally { $hmac.Dispose() }
    $o = $mac[19] -band 0x0F
    # [int] first: in PowerShell a [byte] shifted left stays a byte, so it would become 0.
    $n = (((([int]$mac[$o]) -band 0x7F) -shl 24) -bor ([int]$mac[$o + 1] -shl 16) -bor ([int]$mac[$o + 2] -shl 8) -bor [int]$mac[$o + 3]) % 1000000
    $n.ToString('000000')
}

function Get-TotpStep { [long][Math]::Floor(([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) / 30) }

function Invoke-Relay {
    param([string]$Json)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri $RelayUrl -Method Post -Body $Json -ContentType 'application/json' -TimeoutSec 60
}

function Show-Health {
    Write-Host '  Checking the relay...'
    $health = Invoke-Relay '{"action":"health"}'
    $mark = { param($ok) if ($ok) { 'OK' } else { 'MISSING' } }
    Write-Host ("     Authenticator secret: " + (& $mark $health.totp_secret))
    Write-Host ("     Anthropic key:        " + (& $mark $health.anthropic_key))
    Write-Host ("     Database:             " + (& $mark $health.database))
    Write-Host ''
    if ($health.totp_secret -and $health.anthropic_key -and $health.database) {
        Write-Host '  All set. In Housecall, press ? or H and type the code from the app.' -ForegroundColor Green
    } else {
        Write-Host '  Something is missing: check the secret names on the Supabase secrets page, then run:' -ForegroundColor Yellow
        Write-Host '     powershell -ExecutionPolicy Bypass -File tools\setup-ai.ps1 -Check' -ForegroundColor Yellow
    }
    Write-Host ''
}

if ($FunctionsOnly) { return }
if ($Check) { Write-Host ''; Show-Health; return }

function Pause-Step { param([string]$Text) [void](Read-Host "  $Text  (Enter)") }

Write-Host ''
Write-Host '  Housecall: setting up the AI chat and visit memory' -ForegroundColor Yellow
Write-Host ''

# ---- 1. The Authenticator secret
$random = New-Object byte[] 20
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($random)
$rng.Dispose()
$secret = ConvertTo-Base32 $random
$uri = "otpauth://totp/Housecall:Shamil?secret=$secret&issuer=Housecall&algorithm=SHA1&digits=6&period=30"

$qr = Join-Path $env:TEMP ('housecall-qr-' + [guid]::NewGuid().ToString('N') + '.html')
$html = @"
<!doctype html><meta charset="utf-8"><title>Housecall</title>
<body style="font-family:Segoe UI,sans-serif;text-align:center;padding:40px">
<h2>Scan this with Google Authenticator</h2><div id="qr" style="display:inline-block;padding:16px;background:#fff"></div>
<p>Or tap + &gt; "Enter a setup key": account <b>Housecall</b>, key <code>$secret</code>, time based.</p>
<p>Then go back to the PowerShell window.</p>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<script>new QRCode(document.getElementById("qr"), { text: "$uri", width: 256, height: 256 });</script>
</body>
"@
[IO.File]::WriteAllText($qr, $html)
Start-Process $qr
Write-Host '  1. In Google Authenticator: tap +, then "Scan a QR code" (the page in your browser),'
Write-Host '     or "Enter a setup key":'
Write-Host "        account  Housecall"
Write-Host "        key      $secret" -ForegroundColor Cyan
Write-Host '        type     Time based'
Pause-Step 'Added in the app?'
Remove-Item -LiteralPath $qr -Force -ErrorAction SilentlyContinue

$key = ConvertFrom-Base32 $secret
while ($true) {
    $typed = (Read-Host '  Type the 6-digit code the app shows now') -replace '\s', ''
    $step = Get-TotpStep
    if (@(($step - 1), $step, ($step + 1) | ForEach-Object { Get-Totp $key $_ }) -contains $typed) { break }
    Write-Host '  That does not match. Check the app entry and try the next code.' -ForegroundColor Yellow
}
Write-Host '  The code matches.' -ForegroundColor Green
Write-Host ''

# ---- 2. Into Supabase
Set-Clipboard -Value $secret
Start-Process $SecretsPage
Write-Host '  2. The Supabase secrets page is open, and the key is on your clipboard.'
Write-Host '     Add a secret:  name  HOUSECALL_TOTP_SECRET   value  Ctrl+V   and save.'
Pause-Step 'Saved?'
Set-Clipboard -Value ' '
Write-Host '     Clipboard cleared.' -ForegroundColor DarkGray
Write-Host ''

# ---- 3. The Anthropic key and a spending limit
Start-Process 'https://console.anthropic.com/settings/keys'
Write-Host '  3. The Anthropic console is open. Create a key called "Housecall" and copy it.'
Write-Host '     On the Supabase secrets page add:  name  ANTHROPIC_API_KEY   value  (the key)'
Write-Host '     The key is only shown once in the console: paste it straight into Supabase.'
Pause-Step 'Saved?'
Start-Process 'https://console.anthropic.com/settings/limits'
Write-Host '     Set a monthly spending limit (for example 20 dollars) on the page that just opened.'
Pause-Step 'Done?'
Write-Host ''

# ---- 4. Ask the relay
Write-Host '  4.'
Show-Health

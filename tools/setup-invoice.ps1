<#
    Your business details and prices for the invoice, stored in your own
    Supabase (never in the public script). Run it on your own PC, and again
    whenever something changes:

        powershell -ExecutionPolicy Bypass -File tools\setup-invoice.ps1

    It asks for your Google Authenticator code, then only what the invoice
    needs now: your name, email, phone, hourly rate and call-out fee. The
    business part (address, KvK, IBAN, BTW) comes after one question and is
    skipped by default -- until you are registered it is not needed, and
    fields left empty are simply not printed. Enter keeps the current value,
    a single dash (-) empties it.
#>

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

function Read-Field {
    param([string]$Label, $Current)
    $shown = if ($null -ne $Current -and "$Current" -ne '') { " [$Current]" } else { '' }
    $typed = (Read-Host "  $Label$shown").Trim()
    if ($typed -eq '') { return $Current }
    if ($typed -eq '-') { return $null }
    $typed
}

function Read-Money {
    param([string]$Label, $Current)
    while ($true) {
        $v = Read-Field $Label $Current
        if ($null -eq $v -or "$v" -eq '') { return $null }
        $t = ("$v" -replace ',', '.').Trim()
        $d = 0.0
        if ([double]::TryParse($t, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d) -and $d -ge 0) { return [Math]::Round($d, 2) }
        Write-Host '  Type an amount, for example 40 or 17,50.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '  Housecall: your details for the invoice' -ForegroundColor Yellow
Write-Host ''

$token = $null
while (-not $token) {
    $code = (Read-Host '  Code from Google Authenticator') -replace '\s', ''
    $r = Invoke-Relay @{ action = 'unlock'; code = $code }
    if ($r.token) { $token = $r.token }
    elseif ($r.error -eq 'code_used') { Write-Host '  That code was already used: wait for the next one.' -ForegroundColor Yellow }
    elseif ($r.error -eq 'locked') { Write-Host '  Too many wrong codes: wait 15 minutes.' -ForegroundColor Yellow; return }
    else { Write-Host '  That code is not right. Try the current one.' -ForegroundColor Yellow }
}

$now = (Invoke-Relay @{ action = 'settings_get'; token = $token }).settings
if (-not $now) { $now = [pscustomobject]@{} }
Write-Host ''
Write-Host '  Enter keeps what is between [ ], a dash (-) empties it.' -ForegroundColor DarkGray
Write-Host ''

$s = @{}
$name = $null
while (-not $name) { $name = Read-Field 'Your name (on top of the invoice)' $now.business_name }
$s.business_name = $name
$s.email         = Read-Field 'Email' $now.email
$s.phone         = Read-Field 'Phone (optional)' $now.phone
$s.hourly_rate   = Read-Money 'Hourly rate in euros' $now.hourly_rate
$s.callout_fee   = Read-Money 'Call-out fee in euros (0 = none)' $now.callout_fee

Write-Host ''
$business = (Read-Host '  Also fill in business details (address, KvK, IBAN, BTW)? Only needed once you are registered. (y/N)').Trim()
if ($business -match '^(y|yes|j|ja)$') {
    Write-Host ''
    $s.owner_name    = Read-Field 'Your own name, if the business has another name' $now.owner_name
    $s.address       = Read-Field 'Street and number' $now.address
    $s.postcode_city = Read-Field 'Postcode and city' $now.postcode_city
    $s.kvk           = Read-Field 'KvK number' $now.kvk
    $s.iban          = Read-Field 'IBAN (makes "bank transfer" a payment choice)' $now.iban
    $days = Read-Field 'Payment term for bank transfer, in days' $(if ($now.payment_days) { $now.payment_days } else { 14 })
    $s.payment_days  = [int]$(if ("$days" -match '^\d{1,2}$') { $days } else { 14 })
    Write-Host '  BTW: [1] KOR, no BTW (small business scheme)  [2] 21%, included in your prices  [3] not decided yet'
    $currentMode = if ($now.btw_mode) { $now.btw_mode } else { 'unset' }
    $pick = (Read-Host "  Choose [now: $currentMode]").Trim()
    $s.btw_mode = switch ($pick) { '1' { 'kor' } '2' { '21' } '3' { 'unset' } default { $currentMode } }
    if ($s.btw_mode -eq '21') { $s.btw_number = Read-Field 'BTW-id (NL...B01)' $now.btw_number }
}

$saved = Invoke-Relay @{ action = 'settings_save'; token = $token; settings = $s }
if ($saved.error) {
    Write-Host "  Not saved: $($saved.error) $($saved.field)" -ForegroundColor Red
    return
}
$x = $saved.settings
Write-Host ''
Write-Host '  Saved. The invoice will show:' -ForegroundColor Green
foreach ($line in @(
    (@($x.business_name, $x.owner_name) | Where-Object { $_ }) -join ', '
    (@($x.address, $x.postcode_city) | Where-Object { $_ }) -join ', '
    (@($(if ($x.kvk) { "KvK $($x.kvk)" }), $(if ($x.iban) { "IBAN $($x.iban)" })) | Where-Object { $_ }) -join '   '
    (@($x.email, $x.phone) | Where-Object { $_ }) -join '   '
)) { if ($line) { Write-Host "     $line" } }
Write-Host "     Rate $($x.hourly_rate) per hour, call-out fee $($x.callout_fee)"
if (-not $x.iban) { Write-Host '     Payment choices: card, cash, payment request (Tikkie or your bank's betaalverzoek); bank transfer appears once an IBAN is set' -ForegroundColor DarkGray }
Write-Host ''
Write-Host '  Filled in something that is not needed? Run this again and type a dash (-) to empty it.' -ForegroundColor DarkGray
Write-Host ''

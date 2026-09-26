<#
    The relay (a Supabase Edge Function, relay\housecall\index.ts) and what
    goes through it: unlocking with a Google Authenticator code, and visit
    memory. The AI chat (src\ai.ps1) uses the same unlock.

    One code unlocks the relay until Housecall closes (at most 4 hours,
    which the relay enforces). The token lives only in this PowerShell
    session and is never written to disk.

    Visit memory: each PC gets a scrambled id (SHA-256 of its BIOS serial
    and machine UUID), never a name. The relay keeps the visits in Shamil's
    Supabase; nothing is kept on the client's PC.
#>

$script:RelayUrl = 'https://btwbtxjawubtgeizcrir.supabase.co/functions/v1/housecall'
$script:HcToken = $null
$script:HcTokenExpires = [datetime]::MinValue
$script:HcKnownLabel = $null

# One POST to the relay. Returns Ok, Status, Data (the parsed JSON) and
# Error (the relay's error code, or 'unreachable').
function Invoke-HcRelay {
    param([hashtable]$Body)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    $json = ConvertTo-Json -InputObject $Body -Depth 30 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $saved = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $r = Invoke-WebRequest -Uri $script:RelayUrl -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' `
            -UseBasicParsing -TimeoutSec 150 -ErrorAction Stop
        $reader = New-Object IO.StreamReader($r.RawContentStream, [Text.Encoding]::UTF8)
        return [pscustomobject]@{ Ok = $true; Status = [int]$r.StatusCode; Data = ($reader.ReadToEnd() | ConvertFrom-Json); Error = $null }
    } catch {
        $response = $_.Exception.Response
        if ($null -eq $response) { return [pscustomobject]@{ Ok = $false; Status = 0; Data = $null; Error = 'unreachable' } }
        $status = [int]$response.StatusCode
        $code = 'unreachable'
        try {
            $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
            $parsed = $reader.ReadToEnd() | ConvertFrom-Json
            if ($parsed.error) { $code = [string]$parsed.error }
        } catch { }
        return [pscustomobject]@{ Ok = $false; Status = $status; Data = $null; Error = $code }
    } finally {
        $ProgressPreference = $saved
    }
}

# A relay error in plain words.
function Get-HcRelayMessage {
    param([string]$Code)
    switch ($Code) {
        'wrong_code'  { T 'relay.wrongCode' }
        'code_used'   { T 'relay.codeUsed' }
        'locked'      { T 'relay.locked' }
        'not_set_up'  { T 'relay.notSetUp' }
        'locked_out'  { T 'relay.expired' }
        'unreachable' { T 'relay.unreachable' }
        'ai_key'      { T 'relay.aiKey' }
        'ai_busy'     { T 'relay.aiBusy' }
        'no_settings' { T 'inv.noSettings' }
        default       { T 'relay.error' $Code }
    }
}

function Test-HcUnlocked {
    $script:HcToken -and $script:HcTokenExpires -gt (Get-Date).AddMinutes(1)
}

<#
    Asks for the Authenticator code, unless this session is already
    unlocked. Enter (or anything that is not a code) skips. Returns $true
    once unlocked. The first unlock also shows what is known about this PC.
#>
function Unlock-HcRelay {
    param([string]$PromptKey = 'relay.askCode')
    if (Test-HcUnlocked) { return $true }
    if ($script:HcToken) { Write-Dim (T 'relay.expired') }
    for ($try = 0; $try -lt 3; $try++) {
        $code = ("$(Read-HcLine (T $PromptKey))" -replace '\s', '')
        if ($code -notmatch '^\d{6}$') { return $false }
        $r = Invoke-HcRelay @{ action = 'unlock'; code = $code }
        if ($r.Ok) {
            $script:HcToken = $r.Data.token
            $script:HcTokenExpires = [datetime]::Parse($r.Data.expires, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime()
            Write-Ok (T 'relay.unlocked' $script:HcTokenExpires.ToString('HH:mm'))
            Show-HcKnownPc
            return $true
        }
        Write-Warn2 (Get-HcRelayMessage $r.Error)
        if ($r.Error -notin @('wrong_code', 'code_used')) { return $false }
    }
    $false
}

# ------------------------------------------------------------ visit memory --

# A scrambled, stable id for this PC. The BIOS serial and machine UUID
# survive a Windows reinstall; when both are placeholders (cheap boards say
# "To be filled by O.E.M."), Windows' own MachineGuid is added.
function Get-HcPcId {
    $serial = ''
    $uuid = ''
    try { $serial = [string](Get-CimInstance Win32_BIOS -ErrorAction Stop).SerialNumber } catch { }
    try { $uuid = [string](Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop).UUID } catch { }
    $parts = "housecall|$($serial.Trim())|$($uuid.Trim())"
    if ($serial -match '^\s*$|O\.?E\.?M|Default|System Serial|^0+$' -and $uuid -match '^[F0-]*$') {
        try { $parts += '|' + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction Stop).MachineGuid } catch { }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($parts)) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

# The visits of this PC as Ok, Visits and Error. Not a bare list: an empty
# list returned from a PowerShell function arrives as $null, which looked
# exactly like a failed request (found by Shamil on his first try, 26 Sep).
function Get-HcVisits {
    if (-not (Test-HcUnlocked)) { return [pscustomobject]@{ Ok = $false; Visits = @(); Error = 'locked_out' } }
    $r = Invoke-HcRelay @{ action = 'visit_get'; token = $script:HcToken; pc = (Get-HcPcId) }
    if (-not $r.Ok) { return [pscustomobject]@{ Ok = $false; Visits = @(); Error = $r.Error } }
    [pscustomobject]@{ Ok = $true; Visits = @($r.Data.visits | Where-Object { $_ }); Error = $null }
}

# "3 sep. 2026: C1, D2" -- what a stored visit was about.
function Format-HcVisitLine {
    param($Visit)
    $when = Format-HcDate ([datetime]::Parse([string]$Visit.visited_at, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime())
    $codes = @($Visit.problems | ForEach-Object { $_.code }) -join ', '
    if (-not $codes) { $codes = '-' }
    "$when ($codes)"
}

# One line after unlocking: "Known PC (mevr. de Vries): last visit 3 sep. 2026 (C1)".
function Show-HcKnownPc {
    $result = Get-HcVisits
    $visits = @($result.Visits)
    if (-not $result.Ok -or $visits.Count -eq 0) { return }
    $last = $visits[0]
    $label = @($visits | Where-Object { $_.label } | Select-Object -First 1).label
    $script:HcKnownLabel = $label
    $shown = if ($label) { " ($label)" } else { '' }
    Write-Step (T 'mem.known' $shown (Format-HcVisitLine $last))
}

# H on the menu: the visit history of this PC, with a number to delete one.
# Deleting a visit never deletes its invoice: invoices are kept 7 years.
function Show-HcHistory {
    param([pscustomobject]$Environment)
    Clear-HcScreen
    Write-Banner $Environment
    Write-Host ('  ' + (T 'mem.title')) -ForegroundColor Yellow
    Write-Host ''
    if (-not $Environment.Online) {
        Write-Warn2 (T 'ai.offline')
    } elseif (Unlock-HcRelay) {
        while ($true) {
            $result = Get-HcVisits
            $visits = @($result.Visits)
            if (-not $result.Ok) { Write-Warn2 (Get-HcRelayMessage $result.Error); break }
            if ($visits.Count -eq 0) { Write-Dim (T 'mem.none'); break }
            Write-Host ''
            for ($i = 0; $i -lt $visits.Count; $i++) {
                $v = $visits[$i]
                $label = if ($v.label) { "  [$($v.label)]" } else { '' }
                $invoiceNo = if ($v.invoice_number) { '  ' + (T 'mem.invoice' $v.invoice_number) } else { '' }
                Write-Option ([string]($i + 1)) ((Format-HcVisitLine $v) + $label + $invoiceNo)
                foreach ($p in @($v.problems)) { Write-Dim ('     ' + $p.code + '  ' + (T "problem.$($p.code)")) }
                foreach ($c in @($v.changes)) { Write-Dim ('     + ' + $c) }
            }
            Write-Host ''
            $pick = "$(Read-HcLine (T 'mem.deleteAsk'))".Trim()
            $n = 0
            if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $visits.Count) { return }
            $chosen = $visits[$n - 1]
            if (-not (Test-HcYes (Read-HcLine (T 'mem.deleteConfirm' (Format-HcVisitLine $chosen))))) {
                Write-Dim (T 'fix.cancelled')
                continue
            }
            $r = Invoke-HcRelay @{ action = 'visit_delete'; token = $script:HcToken; pc = (Get-HcPcId); id = [long]$chosen.id }
            if (-not $r.Ok) { Write-Warn2 (Get-HcRelayMessage $r.Error); continue }
            Write-Ok (T 'mem.deleted')
            if ($chosen.invoice_number) { Write-Dim (T 'mem.invoiceKept' $chosen.invoice_number) }
        }
    }
    Write-Host ''
    [void](Read-HcLine (T 'pressEnter'))
}

<#
    At the end of a visit (Q): offers to save it. Asks for the code when
    the session is not unlocked yet, and for an optional name or note, so
    Shamil can find it again for the invoice. Skipped in a dry run, offline,
    or when no problem was opened.
#>
function Save-HcVisitRecord {
    param([pscustomobject]$Environment, $Invoice)
    if ($script:HcVisit.Count -eq 0 -or $script:DryRun -or -not $Environment.Online -or $script:HcQuitSkipped) { return }
    Write-Host ''
    if (-not (Unlock-HcRelay 'mem.saveAsk')) { return }
    if ($Invoice) {
        # The invoice already names the client: no need to ask again.
        $label = [string]$Invoice.client_name
    } else {
        $current = if ($script:HcKnownLabel) { $script:HcKnownLabel } else { T 'mem.noLabel' }
        $typed = "$(Read-HcLine (T 'mem.labelAsk' $current))".Trim()
        $label = if ($typed -and $typed -ne 'Q') { $typed } else { $script:HcKnownLabel }
    }
    if ($label -and $label.Length -gt 80) { $label = $label.Substring(0, 80) }

    $r = Invoke-HcRelay @{
        action   = 'visit_save'
        token    = $script:HcToken
        pc       = (Get-HcPcId)
        label    = $label
        lang     = $script:Lang
        os       = $Environment.Os
        problems = @($script:HcVisit | Where-Object { $_.FindingId } | ForEach-Object { @{ code = $_.Code; finding = $_.FindingId } })
        changes  = @($script:HcChanges | ForEach-Object { $_.Label })
        invoice_number = $(if ($Invoice) { [string]$Invoice.number } else { $null })
    }
    if ($r.Ok) { Write-Ok (T 'mem.saved') } else { Write-Warn2 (T 'mem.notSaved' (Get-HcRelayMessage $r.Error)) }
}

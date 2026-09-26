<#
    A4: email will not send or arrive.

    Asks for the email address, but uses only the part after the @: that
    domain decides the mail servers. Then: does the domain receive mail at
    all, do its receiving (IMAP) and sending (SMTP) servers answer from this
    PC, and which mail program is installed -- including the old Windows
    Mail app, which Microsoft switched off at the end of 2024 and which many
    older clients still try to use.

    What cannot be checked from outside: the password, and whether the
    mailbox is full. The finding says so, and the steps go through them.
#>

# The providers clients in the Netherlands use most, with their servers.
# Webmail only where the address is certain.
$script:MailProviders = @(
    @{ Name = 'Ziggo';     Domains = 'ziggo.nl', 'home.nl', 'casema.nl', 'chello.nl', 'upcmail.nl', 'quicknet.nl'
       Imap = 'imap.ziggo.nl'; Smtp = 'smtp.ziggo.nl'; SmtpPort = 587; Web = $null }
    @{ Name = 'KPN';       Domains = 'kpnmail.nl', 'kpnplanet.nl', 'planet.nl', 'hetnet.nl', 'xs4all.nl', 'telfort.nl', 'telfortglasvezel.nl'
       Imap = 'imap.kpnmail.nl'; Smtp = 'smtp.kpnmail.nl'; SmtpPort = 587; Web = $null }
    @{ Name = 'Outlook.com'; Domains = 'outlook.com', 'outlook.nl', 'hotmail.com', 'hotmail.nl', 'live.com', 'live.nl', 'msn.com'
       Imap = 'outlook.office365.com'; Smtp = 'smtp-mail.outlook.com'; SmtpPort = 587; Web = 'https://outlook.live.com/mail/' }
    @{ Name = 'Gmail';     Domains = 'gmail.com', 'googlemail.com'
       Imap = 'imap.gmail.com'; Smtp = 'smtp.gmail.com'; SmtpPort = 587; Web = 'https://mail.google.com/' }
    @{ Name = 'iCloud';    Domains = 'icloud.com', 'me.com', 'mac.com'
       Imap = 'imap.mail.me.com'; Smtp = 'smtp.mail.me.com'; SmtpPort = 587; Web = 'https://www.icloud.com/mail' }
    @{ Name = 'Yahoo';     Domains = 'yahoo.com', 'yahoo.nl', 'ymail.com'
       Imap = 'imap.mail.yahoo.com'; Smtp = 'smtp.mail.yahoo.com'; SmtpPort = 465; Web = 'https://mail.yahoo.com/' }
)

# "naam@Ziggo.nl " -> "ziggo.nl"; also accepts just the domain.
function ConvertTo-HcMailDomain {
    param([string]$Text)
    $d = ("$Text".Trim().ToLowerInvariant() -split '@')[-1].Trim()
    if ($d -match '^([a-z0-9-]+\.)+[a-z]{2,}$') { return $d }
    $null
}

# How many letters must change to turn one word into the other (Levenshtein),
# kept to two rows so no two-dimensional array is needed.
function Get-HcEditDistance {
    param([string]$A, [string]$B)
    $previous = @(0..$B.Length)
    for ($i = 1; $i -le $A.Length; $i++) {
        $current = @($i) + @(0) * $B.Length
        for ($j = 1; $j -le $B.Length; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $delete = $previous[$j] + 1
            $insert = $current[$j - 1] + 1
            $replace = $previous[$j - 1] + $cost
            $current[$j] = [Math]::Min([Math]::Min($delete, $insert), $replace)
        }
        $previous = $current
    }
    $previous[$B.Length]
}

# A known provider domain one or two letters away: "zigo.nl" -> "ziggo.nl".
function Get-HcMailTypo {
    param([string]$Domain)
    foreach ($p in $script:MailProviders) {
        if ($p.Domains -contains $Domain) { return $null }
    }
    foreach ($p in $script:MailProviders) {
        foreach ($known in $p.Domains) {
            $limit = if ($known.Length -ge 8) { 2 } else { 1 }
            if ((Get-HcEditDistance $Domain $known) -le $limit) { return $known }
        }
    }
    $null
}

function Get-HcMailApps {
    $apps = @()
    $appPath = { param($exe) [bool](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction SilentlyContinue) }
    if (& $appPath 'OUTLOOK.EXE') { $apps += 'Outlook' }
    if (Get-AppxPackage -Name Microsoft.OutlookForWindows -ErrorAction SilentlyContinue) { $apps += 'Outlook (new)' }
    if (& $appPath 'thunderbird.exe') { $apps += 'Thunderbird' }
    [pscustomobject]@{
        Apps          = $apps
        RetiredMail   = [bool](Get-AppxPackage -Name microsoft.windowscommunicationsapps -ErrorAction SilentlyContinue)
    }
}

function Get-HcMailFacts {
    param([string]$Domain)
    $provider = $script:MailProviders | Where-Object { $_.Domains -contains $Domain } | Select-Object -First 1
    $mx = @()
    try { $mx = @(Resolve-DnsName $Domain -Type MX -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object { $_.NameExchange } | ForEach-Object { $_.NameExchange }) } catch { }
    $f = [pscustomobject]@{
        Domain = $Domain; Provider = $null; Web = $null; Typo = (Get-HcMailTypo $Domain)
        ReceivesMail = ($mx.Count -gt 0); ImapHost = $null; ImapMs = $null; SmtpHost = $null; SmtpMs = $null
        Apps = Get-HcMailApps
    }
    if ($provider) {
        $f.Provider = $provider.Name
        $f.Web = $provider.Web
        $f.ImapHost = $provider.Imap
        $f.SmtpHost = $provider.Smtp
        $f.ImapMs = Get-HcTcpMs $provider.Imap 993 3000
        $f.SmtpMs = Get-HcTcpMs $provider.Smtp $provider.SmtpPort 3000
    }
    $f
}

function Test-HcMail {
    param([pscustomobject]$Facts)
    $r = New-HcReport
    $found = @{}
    $d = $Facts.Domain
    Add-HcLine $r ok (T 'net.internetWorks')

    if ($Facts.Typo) {
        Add-HcLine $r warn (T 'mail.typo' $d $Facts.Typo)
        $found['mailTypo'] = @($d, $Facts.Typo)
    }
    if ($Facts.ReceivesMail) {
        Add-HcLine $r ok (T 'mail.receives' $d)
    } else {
        Add-HcLine $r problem (T 'mail.noMx' $d)
        $found['mailNoDomain'] = @($d)
    }

    if ($Facts.Provider) {
        foreach ($s in @(@('in', $Facts.ImapHost, $Facts.ImapMs), @('out', $Facts.SmtpHost, $Facts.SmtpMs))) {
            $what = T "mail.$($s[0])"
            if ($s[2] -ge 0) { Add-HcLine $r ok (T 'mail.serverOk' $what $s[1] $s[2]) }
            else {
                Add-HcLine $r problem (T 'mail.serverDown' $what $s[1])
                if (-not $found['mailServerDown']) { $found['mailServerDown'] = @($Facts.Provider) }
            }
        }
    } elseif ($Facts.ReceivesMail -and -not $Facts.Typo) {
        Add-HcLine $r skipped (T 'mail.unknownProvider' $d)
    }

    $apps = @($Facts.Apps.Apps)
    if ($apps.Count) { Add-HcLine $r ok (T 'mail.apps' ($apps -join ', ')) } else { Add-HcLine $r ok (T 'mail.noApps') }
    if ($Facts.Apps.RetiredMail) {
        Add-HcLine $r warn (T 'mail.retired')
        $found['mailAppRetired'] = @()
    }
    if ($Facts.Web) { Add-HcAction $r 'openWebmail' @{ Label = $Facts.Provider; Url = $Facts.Web } }

    Select-HcFinding $r $found @('mailTypo', 'mailNoDomain', 'mailServerDown', 'mailAppRetired') 'mailOk'
    if ($r.FindingId -eq 'mailOk') { $r.FindingArgs = @($(if ($Facts.Provider) { $Facts.Provider } else { $d })) }
    $r
}

function Invoke-HcA4 {
    $domain = $null
    while (-not $domain) {
        $typed = Read-HcLine (T 'mail.ask')
        if (-not "$typed".Trim() -or "$typed".Trim().ToUpperInvariant() -eq 'Q') { return }
        $domain = ConvertTo-HcMailDomain $typed
        if (-not $domain) { Write-Warn2 (T 'mail.invalid' $typed) }
    }
    Write-Host ''
    # A script variable, not a closure; see Invoke-HcA3.
    $script:HcMailDomain = $domain
    {
        $base = Test-HcInternet (Get-HcNetworkFacts)
        if ($script:InternetWorks -notcontains $base.FindingId) { return $base }
        Test-HcMail (Get-HcMailFacts $script:HcMailDomain)
    }
}

$script:ProblemHandlers['A4'] = 'Invoke-HcA4'

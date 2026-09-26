<#
    Console output: the four line styles (same as Reveille's setup.ps1), menu
    options, and the banner.
#>

function Write-Step  { param([string]$m) Write-Host "  $m" -ForegroundColor Cyan }
function Write-Ok    { param([string]$m) Write-Host "  $m" -ForegroundColor Green }
function Write-Warn2 { param([string]$m) Write-Host "  $m" -ForegroundColor Yellow }
function Write-Dim   { param([string]$m) Write-Host "  $m" -ForegroundColor DarkGray }

# One menu line: the key in yellow, then the label.  [A] Internet & Wi-Fi
function Write-Option {
    param([string]$Key, [string]$Label)
    Write-Host '  [' -NoNewline -ForegroundColor DarkGray
    Write-Host $Key -NoNewline -ForegroundColor Yellow
    Write-Host '] ' -NoNewline -ForegroundColor DarkGray
    Write-Host $Label
}

# Several short options on one line, for the footer: [0] Back  [L] English  [Q] Quit
function Write-OptionRow {
    param([object[]]$Options)
    Write-Host '  ' -NoNewline
    foreach ($o in $Options) {
        Write-Host '[' -NoNewline -ForegroundColor DarkGray
        Write-Host $o[0] -NoNewline -ForegroundColor Yellow
        Write-Host '] ' -NoNewline -ForegroundColor DarkGray
        Write-Host ($o[1] + '    ') -NoNewline -ForegroundColor Gray
    }
    Write-Host ''
}

# Clearing between screens keeps the menu readable at the client's desk. A
# scripted run (the tests) keeps everything, so the output can be read back.
function Clear-HcScreen {
    if ($null -eq $script:HcInputQueue) {
        try { Clear-Host } catch { }
    }
}

# Every read goes through here, so tests can feed answers from a queue. When
# the queue runs dry, or there is no console to read from, the answer is Q:
# a scripted run ends instead of hanging.
$script:HcInputQueue = $null

function Read-HcLine {
    param([string]$Prompt)
    if ($null -ne $script:HcInputQueue) {
        if ($script:HcInputQueue.Count -eq 0) { return 'Q' }
        $line = [string]$script:HcInputQueue.Dequeue()
        Write-Host "  $Prompt> $line" -ForegroundColor DarkGray
        return $line
    }
    try {
        $line = Read-Host "  $Prompt"
    } catch {
        # Nobody at a console (a non-interactive run): remember it, so the
        # note is printed instead of waiting for a click that never comes.
        $script:NoConsole = $true
        return 'Q'
    }
    if ($null -eq $line) { return '' }
    $line
}

<#
    The banner.

    Drawn from a bitmap the way Reveille draws its own, so this file stays
    plain ASCII: the block and rule characters are built from [char] codes and
    render correctly however the script is fetched.
#>

$script:Glyphs = @{
    'H' = @('#...#', '#...#', '#####', '#...#', '#...#')
    'O' = @('.###.', '#...#', '#...#', '#...#', '.###.')
    'U' = @('#...#', '#...#', '#...#', '#...#', '.###.')
    'S' = @('.####', '#....', '.###.', '....#', '####.')
    'E' = @('#####', '#....', '####.', '#....', '#####')
    'C' = @('.####', '#....', '#....', '#....', '.####')
    'A' = @('.###.', '#...#', '#####', '#...#', '#...#')
    'L' = @('#....', '#....', '#....', '#....', '#####')
}

function Write-Banner {
    param([pscustomobject]$Environment)

    $block = [string][char]0x2588      # full block
    $rule = [string][char]0x2500       # horizontal rule
    $word = 'HOUSECALL'

    # Warm yellow at the top falling to orange: a porch light. HOUSE and CALL
    # share the gradient; the H keeps the bright end so it reads as the mark.
    $gradient = @('Yellow', 'Yellow', 'DarkYellow', 'DarkYellow', 'DarkRed')

    Write-Host ''
    for ($row = 0; $row -lt 5; $row++) {
        Write-Host '  ' -NoNewline
        for ($i = 0; $i -lt $word.Length; $i++) {
            $line = $script:Glyphs[[string]$word[$i]][$row]
            $text = ($line -replace '#', $block) -replace '\.', ' '
            $colour = if ($i -eq 0) { 'White' } else { $gradient[$row] }
            Write-Host "$text " -ForegroundColor $colour -NoNewline
        }
        Write-Host ''
    }

    Write-Host ''
    Write-Host ('  ' + ($rule * 53)) -ForegroundColor DarkGray
    Write-Host ('   ' + (T 'tagline')) -ForegroundColor Gray
    if ($Environment) { Write-HcStatus $Environment }
    Write-Host ('  ' + ($rule * 53)) -ForegroundColor DarkGray
    Write-Dim (T 'promise')
    Write-Host ''
}

# One line under the banner: what this PC is and what Housecall may do on it.
#   Windows 11 Home  .  PowerShell 5.1  .  not admin  .  online
function Write-HcStatus {
    param([pscustomobject]$Environment)
    $dot = '  ' + [char]0x00B7 + '  '
    $parts = @(
        $Environment.Os
        ('PowerShell ' + $Environment.PSVersion.Major + '.' + $Environment.PSVersion.Minor)
        $(if ($Environment.IsAdmin) { T 'status.admin' } else { T 'status.notAdmin' })
        $(if ($Environment.Online) { T 'status.online' } else { T 'status.offline' })
    )
    Write-Host ('   ' + ($parts -join $dot)) -ForegroundColor DarkGray
    if ($script:DryRun) {
        Write-Host ('   ' + (T 'status.dryRun')) -ForegroundColor Magenta
    }
}

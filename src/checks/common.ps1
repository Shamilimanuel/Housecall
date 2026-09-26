<#
    The shape every check shares, for all areas A to F.

    A problem is handled in three steps, kept apart on purpose:

      1. Get-...Facts   reads the PC. Read-only, and the only step that
                        touches Windows, so tests replace it with fake facts.
      2. Test-...       turns facts into a report. Pure: no output, no
                        reading the PC, so every scenario can be tested.
      3. Write-HcReport prints the report.

    A report is a list of result lines plus one finding: the id of the most
    important thing found (finding.<id> and advice.<id> in strings.ps1).
    Phase 2 maps finding ids to fixes.
#>

# Problem code -> the function that handles it. Each area's file registers
# its own; a code with no handler shows the "not built yet" screen.
$script:ProblemHandlers = @{}

# One line of a report. Status is ok, problem, warn or skipped; Text is
# already in the current language.
function New-HcResult {
    param([string]$Status, [string]$Text)
    [pscustomobject]@{ Status = $Status; Text = $Text }
}

function New-HcReport {
    [pscustomobject]@{
        Results     = New-Object System.Collections.ArrayList
        FindingId   = $null
        FindingArgs = @()
    }
}

# Adds a line to the report. Written as a function so the Test- functions
# stay readable: Add-HcLine $r ok (T 'net.dnsOk')
function Add-HcLine {
    param([pscustomobject]$Report, [string]$Status, [string]$Text)
    [void]$Report.Results.Add((New-HcResult $Status $Text))
}

# Sets the finding, unless one is already set: the first real problem in the
# chain is the cause, and whatever follows from it is not.
function Set-HcFinding {
    param([pscustomobject]$Report, [string]$Id, [object[]]$Arguments = @())
    if ($null -eq $Report.FindingId) {
        $Report.FindingId = $Id
        $Report.FindingArgs = $Arguments
    }
}

$script:ResultStyle = @{
    ok      = @('[ OK ]', 'Green')
    problem = @('[ !! ]', 'Red')
    warn    = @('[ !  ]', 'Yellow')
    skipped = @('[ -- ]', 'DarkGray')
}

function Write-HcReport {
    param([pscustomobject]$Report)
    foreach ($line in $Report.Results) {
        $style = $script:ResultStyle[$line.Status]
        Write-Host ('  ' + $style[0] + ' ') -NoNewline -ForegroundColor $style[1]
        $colour = if ($line.Status -eq 'skipped') { 'DarkGray' } else { 'Gray' }
        Write-Host $line.Text -ForegroundColor $colour
    }
    if ($Report.FindingId) {
        $findingArgs = @('finding.' + $Report.FindingId) + @($Report.FindingArgs)
        Write-Host ''
        Write-HcLabelled (T 'run.found') (T @findingArgs) 'Yellow'
        Write-Host ''
        Write-HcLabelled (T 'run.advice') (T ('advice.' + $Report.FindingId)) 'Cyan'
    }
}

# "Found: text" with the text word-wrapped under itself, so a long sentence
# does not run back to the left edge of the window.
function Write-HcLabelled {
    param([string]$Label, [string]$Text, [string]$LabelColour)
    $width = 100
    try {
        $w = $Host.UI.RawUI.WindowSize.Width
        if ($w -gt 40) { $width = [math]::Min($w - 2, 100) }
    } catch { }

    $indent = ' ' * (2 + $Label.Length + 1)
    $lines = New-Object System.Collections.Generic.List[string]
    $current = ''
    foreach ($word in ($Text -split ' ')) {
        if ($current -and ($indent.Length + $current.Length + 1 + $word.Length) -gt $width) {
            $lines.Add($current)
            $current = $word
        } elseif ($current) {
            $current += ' ' + $word
        } else {
            $current = $word
        }
    }
    if ($current) { $lines.Add($current) }

    Write-Host ('  ' + $Label + ' ') -NoNewline -ForegroundColor $LabelColour
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq 0) { Write-Host $lines[$i] } else { Write-Host ($indent + $lines[$i]) }
    }
}

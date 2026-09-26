<#
    Housecall -- finds and fixes computer problems at a client's desk.

        irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex

    Pick a letter for the area and a number for the problem (A1 = no
    internet), or ? to describe it in your own words. Housecall checks that
    part of the PC read-only, and changes nothing without a yes.

    Options (these need the longer form, because `iex` cannot take arguments):

        $s = 'github.com/Shamilimanuel/Housecall/raw/main/setup.ps1'
        & ([scriptblock]::Create((irm $s))) -DryRun      # check, never fix
        & ([scriptblock]::Create((irm $s))) -Lang nl     # force Dutch or English

    setup.ps1 is built by build.ps1 from dev.ps1 and the files in src\.
    Edit those, never setup.ps1 by hand: the next build overwrites it.
#>

[CmdletBinding()]
param(
    # Diagnose only. Every fix is skipped, so it is safe to try on any PC.
    [switch]$DryRun,
    # Language for everything on screen: nl or en. Defaults to the Windows
    # language. No [ValidateSet] on purpose: under `irm | iex` this block runs
    # as plain variable declarations, and the empty default would fail it.
    [string]$Lang,
    # Open this problem straight away, e.g. A1. Used when Housecall restarts
    # itself as administrator, so it carries on where it was.
    [string]$Start,
    # Leave the AI chat (?) out of the menu, e.g. when the client does not
    # want anything sent over the internet.
    [switch]$NoAI
)

$ErrorActionPreference = 'Stop'

<#
    All of Housecall's code is kept as text in $HcSource and run from there.
    That way it can hand itself to a new administrator window (see
    Start-HcElevated in src\fixes.ps1) even when it came in through
    `irm | iex` and there is no file on disk, and even with no internet.
#>
# >>> sources (build.ps1 replaces this block with the files' text)
$HcSource = @(
    'strings.ps1'
    'ui.ps1'
    'environment.ps1'
    'menu.ps1'
    'checks\common.ps1'
    'checks\network.ps1'
    'checks\email.ps1'
    'checks\security.ps1'
    'checks\devices.ps1'
    'checks\audio-interop.ps1'
    'checks\sound.ps1'
    'checks\performance.ps1'
    'checks\updates.ps1'
    'fixes.ps1'
    'note.ps1'
    'relay.ps1'
    'invoice.ps1'
    'ai.ps1'
) | ForEach-Object { [IO.File]::ReadAllText((Join-Path (Join-Path $PSScriptRoot 'src') $_)) }
$HcSource = $HcSource -join "`r`n"
# <<< sources

. ([scriptblock]::Create($HcSource))
$script:HcSource = $HcSource
Start-Housecall -DryRun:$DryRun -Lang $Lang -Start $Start -NoAI:$NoAI

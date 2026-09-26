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
    [string]$Lang
)

$ErrorActionPreference = 'Stop'

# >>> sources (build.ps1 replaces this block with the files themselves)
$src = Join-Path $PSScriptRoot 'src'
. (Join-Path $src 'strings.ps1')
. (Join-Path $src 'ui.ps1')
. (Join-Path $src 'environment.ps1')
. (Join-Path $src 'menu.ps1')
. (Join-Path $src 'checks\common.ps1')
. (Join-Path $src 'checks\network.ps1')
. (Join-Path $src 'checks\security.ps1')
. (Join-Path $src 'fixes.ps1')
# <<< sources

Start-Housecall -DryRun:$DryRun -Lang $Lang

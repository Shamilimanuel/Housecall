<#
    Bundles dev.ps1 and everything it loads from src\ into one file,
    setup.ps1 -- the file the one-liner fetches, since `irm | iex` can only
    fetch one file:

        irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex

    Run it before every commit that touches src\: setup.ps1 is what clients
    get, and it only changes when this script rebuilds it.

        powershell -ExecutionPolicy Bypass -File build.ps1

    The block between the ">>> sources" and "<<< sources" markers in
    dev.ps1 is replaced by the contents of each dot-sourced file, in the
    same order. The result is checked before it is written: it must be plain
    ASCII and parse without errors.
#>

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$entry = Join-Path $root 'dev.ps1'
$out = Join-Path $root 'setup.ps1'

$lines = Get-Content -LiteralPath $entry
$start = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -match '^# >>> sources' })
$end = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -match '^# <<< sources' })
if ($start -lt 0 -or $end -lt $start) {
    throw 'dev.ps1 has no ">>> sources" / "<<< sources" block.'
}

$bundle = New-Object System.Collections.Generic.List[string]
$lines[0..($start - 1)] | ForEach-Object { $bundle.Add($_) }

foreach ($line in $lines[($start + 1)..($end - 1)]) {
    if ($line -match "^\. \(Join-Path \`$src '([^']+)'\)") {
        $name = $Matches[1]
        $bundle.Add('')
        $bundle.Add("# ==================================================== src\$name ==")
        Get-Content -LiteralPath (Join-Path $root "src\$name") | ForEach-Object { $bundle.Add($_) }
    }
}

$bundle.Add('')
$lines[($end + 1)..($lines.Count - 1)] | ForEach-Object { $bundle.Add($_) }
$text = ($bundle -join "`r`n") + "`r`n"

if ($text -match '[^\x00-\x7F]') {
    throw 'The bundle contains non-ASCII characters. PowerShell 5.1 would misread them; use [char] codes instead.'
}
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    throw ('The bundle does not parse: ' + ($errors | ForEach-Object { $_.Message }) -join '; ')
}

[System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.ASCIIEncoding))
Write-Host "  Built $out ($([math]::Round($text.Length / 1KB, 1)) KB)" -ForegroundColor Green

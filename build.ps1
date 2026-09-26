<#
    Bundles dev.ps1 and everything it loads from src\ into one file,
    setup.ps1 -- the file the one-liner fetches, since `irm | iex` can only
    fetch one file:

        irm github.com/Shamilimanuel/Housecall/raw/main/setup.ps1 | iex

    Run it before every commit that touches src\: setup.ps1 is what clients
    get, and it only changes when this script rebuilds it.

        powershell -ExecutionPolicy Bypass -File build.ps1

    The block between the ">>> sources" and "<<< sources" markers in
    dev.ps1 is replaced by one single-quoted here-string holding the text of
    every file it lists, in the same order: $HcSource = @' ... '@. dev.ps1
    then runs that text. The result is checked before it is written: plain
    ASCII, no line that would end the here-string early, and it must parse.
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

# The fingerprint: the first 12 hex digits of the SHA-256 of every source
# file, so it changes exactly when the code does.
$sha = [Security.Cryptography.SHA256]::Create()
$texts = foreach ($l in $lines[($start + 1)..($end - 1)]) {
    if ($l -match "^\s+'([^']+\.ps1)'\s*$") { [IO.File]::ReadAllText((Join-Path (Join-Path $root 'src') $Matches[1])) }
}
# Without carriage returns, so Git's line-ending conversion does not change it.
$all = ((@($lines) + @($texts)) -join "`n") -replace "`r", ''
$build = (($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($all)) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 12)

$bundle = New-Object System.Collections.Generic.List[string]
$marker = "`$HcBuild = 'dev'"
if (@($lines[0..($start - 1)] | Where-Object { $_ -eq $marker }).Count -ne 1) { throw "dev.ps1 needs exactly one line: $marker" }
$lines[0..($start - 1)] | ForEach-Object { if ($_ -eq $marker) { $bundle.Add("`$HcBuild = '$build'") } else { $bundle.Add($_) } }

$bundle.Add("`$HcSource = @'")
foreach ($line in $lines[($start + 1)..($end - 1)]) {
    if ($line -match "^\s+'([^']+\.ps1)'\s*$") {
        $name = $Matches[1]
        $bundle.Add('')
        $bundle.Add("# ==================================================== src\$name ==")
        foreach ($code in (Get-Content -LiteralPath (Join-Path $root "src\$name"))) {
            if ($code -match "^'@") { throw "src\$name has a line starting with '@, which would end the here-string." }
            $bundle.Add($code)
        }
    }
}
$bundle.Add("'@")

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
[System.IO.File]::WriteAllText((Join-Path $root 'version.txt'), $build + "`n", (New-Object System.Text.ASCIIEncoding))
Write-Host "  Built $out ($([math]::Round($text.Length / 1KB, 1)) KB), build $build" -ForegroundColor Green

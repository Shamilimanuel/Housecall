<#
    Finds which part of Housecall an antivirus blocks.

    Found on 2 Oct 2026: on Shamil's laptop McAfee stopped the one-liner with
    "This script contains malicious content and has been blocked by your
    antivirus software" (ScriptContainedMaliciousContent, line 1 char 1).
    Windows hands every script that PowerShell is about to run to the
    antivirus (AMSI); McAfee judged Housecall as a whole, so this narrows it
    down: the whole script, then each source file, then each function or
    statement inside a file that is blocked.

    Run it on the PC where the one-liner is blocked, with the antivirus ON:

        irm github.com/Shamilimanuel/Housecall/raw/main/tools/amsi-test.ps1 | iex

    Every piece is handed to PowerShell wrapped in a function that is never
    called, so the antivirus scans it but none of it runs. Nothing on the PC
    changes. At the end the report is shown and put on the clipboard, to
    paste back into the chat.
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$HcRaw = 'https://github.com/Shamilimanuel/Housecall/raw/main'

function Get-HcRawText {
    param([string]$Path)
    $content = (Invoke-WebRequest -Uri "$HcRaw/$Path" -UseBasicParsing -TimeoutSec 30).Content
    if ($content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($content) }
    "$content"
}

# blocked / clean / error. The text goes into a function body: a param
# block is allowed there, and the function is never called.
function Test-HcScan {
    param([string]$Text)
    try {
        Invoke-Expression ("function Test-HcScanProbe {`r`n" + $Text + "`r`n}")
        'clean'
    } catch {
        if ("$($_.FullyQualifiedErrorId) $($_.Exception.Message)" -match 'ScriptContainedMaliciousContent|malicious content') { return 'blocked' }
        'error'
    }
}

# Each top-level statement of a file (a function, a list, an assignment),
# with its first line and a short name, read by PowerShell's own parser.
function Get-HcStatements {
    param([string]$Text)
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    foreach ($s in $ast.EndBlock.Statements) {
        $name = if ($s -is [Management.Automation.Language.FunctionDefinitionAst]) { 'function ' + $s.Name } else { (($s.Extent.Text -split "`r?`n")[0]).Trim() }
        if ($name.Length -gt 70) { $name = $name.Substring(0, 70) + '...' }
        [pscustomobject]@{ Line = $s.Extent.StartLineNumber; Name = $name; Text = $s.Extent.Text }
    }
}

$report = New-Object System.Collections.Generic.List[string]
$say = { param($line) Write-Host $line; $report.Add($line) }

Write-Host ''
Write-Host '  Housecall antivirus test: reading only, nothing runs and nothing changes.' -ForegroundColor Cyan
Write-Host ''
$av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object { $_.displayName }) -join ', '
& $say "Antivirus: $(if ($av) { $av } else { 'unknown' })"
& $say "PowerShell $($PSVersionTable.PSVersion), Windows $([Environment]::OSVersion.Version)"

# 0. Control: Microsoft's harmless AMSI test string, which every antivirus
#    that scans PowerShell blocks on purpose. Not blocked = the scanner is off,
#    and nothing below means anything. (Split in two so this file itself is
#    not blocked.)
$control = Test-HcScan ("'AMSI Test Sample: " + '7e72c3ce-861b-4339-8740-0ac1484c1386' + "'")
& $say "Control (Microsoft's test string): $control$(if ($control -ne 'blocked') { ': the antivirus is NOT scanning PowerShell right now' } else { ', so the scanner is active' })"

# 1. The whole one-liner, as GitHub serves it.
$setup = Get-HcRawText 'setup.ps1'
$build = if ($setup -match "\`$HcBuild = '([0-9a-f]+)'") { $Matches[1] } else { '?' }
$whole = Test-HcScan $setup
& $say "Whole setup.ps1 (build $build): $whole"
if ($whole -ne 'blocked') {
    & $say 'The whole script is NOT blocked right now. Is the antivirus real-time scan switched on? Switch it on and run this test again.'
}

# 2. The start file and each source file on its own.
$dev = Get-HcRawText 'dev.ps1'
$names = @(($dev -split "`r?`n") | Where-Object { $_ -match "^\s+'([^']+\.ps1)'\s*$" } | ForEach-Object { $Matches[1] })
$files = [ordered]@{ 'dev.ps1' = $dev }
foreach ($n in $names) { $files["src\$n"] = Get-HcRawText ('src/' + ($n -replace '\\', '/')) }

$blockedFiles = @()
foreach ($f in $files.Keys) {
    $result = Test-HcScan $files[$f]
    if ($result -ne 'clean') { & $say "  $f : $result" }
    if ($result -eq 'blocked') { $blockedFiles += $f }
}
if (-not $blockedFiles.Count) { & $say '  No single file is blocked on its own.' }

# 3. Inside each blocked file: each function and statement on its own.
foreach ($f in $blockedFiles) {
    & $say "Inside $f :"
    $hits = 0
    foreach ($s in @(Get-HcStatements $files[$f])) {
        if ((Test-HcScan $s.Text) -eq 'blocked') { & $say "  BLOCKED line $($s.Line): $($s.Name)"; $hits++ }
    }
    if (-not $hits) { & $say '  No single part is blocked: it is the file as a whole.' }
}

# 4. Only the whole is blocked: add the files one by one until it tips.
if ($whole -eq 'blocked' -and -not $blockedFiles.Count) {
    $sum = ''
    foreach ($f in $files.Keys) {
        $sum += "`r`n" + $files[$f]
        if ((Test-HcScan $sum) -eq 'blocked') { & $say "Blocked once the files up to $f are together."; break }
    }
}

Write-Host ''
try { ($report -join "`r`n") | Set-Clipboard; Write-Host '  The report is on the clipboard: paste it into the chat.' -ForegroundColor Green } catch { Write-Host '  Copy the lines above into the chat.' -ForegroundColor Yellow }
Write-Host ''

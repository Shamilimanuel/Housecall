<#
    Makes "housecall" a command on your own PC: type it in PowerShell, in
    cmd or in Win+R and Housecall starts. Run once per PC (not on a
    client's PC; there the one-liner or the USB stick is the way):

        powershell -ExecutionPolicy Bypass -File tools\install-command.ps1

    It writes housecall.cmd to %LOCALAPPDATA%\Microsoft\WindowsApps, a
    folder Windows already puts on the PATH. Nothing else changes: no
    profile, no execution policy. -Remove takes it away again.

        housecall              the latest version from GitHub, as clients get it
        housecall -Console     the text menu
        housecall -Dev         from this source folder, to try changes first
        housecall -Mail        connect your Outlook for mailing (tools\setup-mail.ps1)
#>
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$target = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\housecall.cmd'

if ($Remove) {
    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
    Write-Host "  Removed $target"
    return
}

$dev = Join-Path (Split-Path -Parent $PSScriptRoot) 'dev.ps1'
$mail = Join-Path $PSScriptRoot 'setup-mail.ps1'
$lines = @(
    '@echo off'
    'rem Housecall. Made by tools\install-command.ps1; run it again to update, or with -Remove.'
    'if /i "%~1"=="-Mail" ('
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$mail`" %2"
    '    goto :eof'
    ')'
    'if /i "%~1"=="-Dev" ('
    "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dev`" %2 %3 %4 %5 %6"
    '    goto :eof'
    ')'
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; & ([scriptblock]::Create((irm ''https://github.com/Shamilimanuel/Housecall/raw/main/setup.ps1''))) %*"'
)
[IO.File]::WriteAllText($target, (($lines -join "`r`n") + "`r`n"), (New-Object Text.ASCIIEncoding))
Write-Host "  Made $target"
Write-Host '  Type housecall in a new PowerShell window (or housecall -Dev for this folder).'

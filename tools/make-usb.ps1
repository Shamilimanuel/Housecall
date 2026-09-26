<#
    Puts Housecall on a USB stick, for PCs without internet (the one-liner
    needs internet to download Housecall). Run it on your own PC, and again
    whenever Housecall shows "deze kopie is verouderd":

        powershell -ExecutionPolicy Bypass -File tools\make-usb.ps1

    It asks which USB stick to use (or pass -Drive E:), then writes a
    Housecall folder on it:

        Housecall\setup.ps1      the same file the one-liner downloads
        Housecall\Housecall.cmd  double-click this at the client's PC

    Right-click Housecall.cmd > Als administrator uitvoeren when a fix will
    need admin rights; otherwise Housecall offers to restart as admin.
#>
param([string]$Drive)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$setup = Join-Path $root 'setup.ps1'

# The copy must be the newest build: rebuild first, so the USB matches src\.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'build.ps1')
if ($LASTEXITCODE -ne 0) { throw 'build.ps1 failed: the USB stick was not touched.' }

if (-not $Drive) {
    $sticks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2')
    if ($sticks.Count -eq 0) {
        Write-Host '  No USB stick found. Plug one in and run this again.' -ForegroundColor Yellow
        return
    }
    Write-Host ''
    for ($i = 0; $i -lt $sticks.Count; $i++) {
        $s = $sticks[$i]
        $free = if ($s.FreeSpace) { '{0:N1} GB free' -f ($s.FreeSpace / 1GB) } else { '' }
        Write-Host ("  [{0}] {1} {2}  {3}" -f ($i + 1), $s.DeviceID, $s.VolumeName, $free)
    }
    $pick = if ($sticks.Count -eq 1) { '1' } else { (Read-Host '  Which one').Trim() }
    if ($pick -notmatch '^\d+$' -or [int]$pick -lt 1 -or [int]$pick -gt $sticks.Count) { Write-Host '  Nothing chosen.'; return }
    $Drive = $sticks[[int]$pick - 1].DeviceID
}
$Drive = $Drive.TrimEnd('\')
if (-not (Test-Path "$Drive\")) { throw "Drive $Drive not found." }

$folder = Join-Path "$Drive\" 'Housecall'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
Copy-Item -LiteralPath $setup -Destination (Join-Path $folder 'setup.ps1') -Force

# %~dp0 is the folder the .cmd is in, whatever letter the stick gets on the client's PC.
$cmd = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0setup.ps1`" %*`r`n"
[IO.File]::WriteAllText((Join-Path $folder 'Housecall.cmd'), $cmd, (New-Object Text.ASCIIEncoding))

$build = (Get-Content (Join-Path $root 'version.txt') -TotalCount 1).Trim()
Write-Host ''
Write-Host "  Housecall is on $Drive\Housecall (build $build)." -ForegroundColor Green
Write-Host '  At the client: open the stick, double-click Housecall.cmd.' -ForegroundColor Gray
Write-Host '  Push your latest changes to GitHub too, or the stick will say it is out of date.' -ForegroundColor DarkGray
Write-Host ''

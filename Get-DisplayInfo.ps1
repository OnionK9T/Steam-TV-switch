<#
  Get-DisplayInfo.ps1 — print everything Toggle-SteamTV.ps1 needs to know.

  Run this first. Look at the DisplayConfig tables:
    - the active target is the screen you are looking at right now
    - the other one is the screen you want to switch to
    - note each one's tech= (5 = HDMI, 10 = DisplayPort) and id=
#>
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'lib\DispInfo.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'lib\DisplayConfig.cs')

Write-Host ''
Write-Host '=== desktop screens (System.Windows.Forms) ===' -ForegroundColor Cyan
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
    [pscustomobject]@{
        Device     = $_.DeviceName
        Primary    = $_.Primary
        Resolution = "$($_.Bounds.Width)x$($_.Bounds.Height)"
        Position   = "$($_.Bounds.X),$($_.Bounds.Y)"
    }
} | Format-Table -AutoSize

Write-Host '=== DisplayConfig targets (all, active or not) ===' -ForegroundColor Cyan
Write-Host '  index|friendly name|tech|target id|state'
Write-Host '  tech: 1=VGA 4=DVI 5=HDMI 10=DisplayPort(external) 11=DisplayPort(embedded)'
[DispConfig]::ListAllTargets()

Write-Host '=== DisplayConfig targets (currently active) ===' -ForegroundColor Cyan
[DispConfig]::ListTargets()

<#
.SYNOPSIS
  Poll two keys and fire Toggle-SteamTV.ps1 (TV / desktop) when they go down.

.DESCRIPTION
  This exists for controllers whose extra buttons can only be mapped to a
  physical keyboard key. The vendor software captures real scan codes, so a
  key injected by software (keybd_event) is invisible to it — you must map to
  a key that physically exists on your keyboard.

  Unlike AutoHotkey-style hotkeys, this does NOT block the key: its normal
  function still works, the script only watches the key state.

.PARAMETER VkTv
  Virtual-key code that should switch to the TV. 0x2D = Insert.

.PARAMETER VkPc
  Virtual-key code that should switch back to the monitor. 0x21 = Page Up.

.PARAMETER DebounceMs
  Ignore repeat presses within this window.

.EXAMPLE
  .\Watch-Keys.ps1 -VkTv 0x2D -VkPc 0x21
#>
param(
    [int]$VkTv = 0x2D,
    [int]$VkPc = 0x21,
    [string]$Script = (Join-Path $PSScriptRoot 'Toggle-SteamTV.ps1'),
    [int]$DebounceMs = 900,
    [switch]$NoLog
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class KeyState {
  [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
}
'@

$settingsPath = Join-Path $PSScriptRoot 'settings.psd1'
if (Test-Path $settingsPath) {
    try {
        $cfg = Import-PowerShellDataFile -Path $settingsPath
        if (-not $PSBoundParameters.ContainsKey('VkTv') -and $cfg.ContainsKey('VkTv')) { $VkTv = [int]$cfg.VkTv }
        if (-not $PSBoundParameters.ContainsKey('VkPc') -and $cfg.ContainsKey('VkPc')) { $VkPc = [int]$cfg.VkPc }
    } catch { }
}

$log = Join-Path $PSScriptRoot 'key-hit.log'
$lastTv = [Environment]::TickCount - 100000
$lastPc = [Environment]::TickCount - 100000

function Invoke-Toggle([string]$switchArg, [string]$tag) {
    if (-not $NoLog) {
        Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss.fff'), $tag)
    }
    Start-Process powershell -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $Script + '"'), $switchArg
    ) -WindowStyle Hidden
}

Write-Host ("watching VK=0x{0:X2} (TV) and VK=0x{1:X2} (PC) ..." -f $VkTv, $VkPc) -ForegroundColor Cyan

while ($true) {
    $now = [Environment]::TickCount

    $s = [KeyState]::GetAsyncKeyState($VkTv)
    if ((($s -band 0x8000) -ne 0) -and (($now - $lastTv) -gt $DebounceMs)) {
        $lastTv = $now
        Invoke-Toggle '-ForceTv' 'key -> ForceTv'
    }

    $s = [KeyState]::GetAsyncKeyState($VkPc)
    if ((($s -band 0x8000) -ne 0) -and (($now - $lastPc) -gt $DebounceMs)) {
        $lastPc = $now
        Invoke-Toggle '-ForcePc' 'key -> ForcePc'
    }

    Start-Sleep -Milliseconds 40
}

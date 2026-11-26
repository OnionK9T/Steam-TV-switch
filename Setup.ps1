<#
.SYNOPSIS
  Interactive setup. Detects your displays and audio devices, then writes
  settings.psd1 next to this script.

.DESCRIPTION
  Run this once. Everything else (toggle-tv.bat / toggle-pc.bat / watch-keys.bat)
  reads settings.psd1 automatically.

  -Yes  非交互:按输出技术自动选(第一块 HDMI 当电视,第一块 DisplayPort 当显示器),
         音频留空。适合先跑通再回头调。
#>
[CmdletBinding()]
param(
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'lib\DispInfo.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'lib\DisplayConfig.cs')

$techName = @{ 1 = 'VGA'; 4 = 'DVI'; 5 = 'HDMI'; 10 = 'DisplayPort'; 11 = 'eDP' }

function Get-Targets {
    $out = @()
    foreach ($line in ([DispConfig]::ListAllTargets() -split "`r?`n")) {
        if ($line -match '^\d+\|(.*)\|tech=(\d+)\|id=(\d+)\|(active|inactive)$') {
            $out += [pscustomobject]@{
                Name  = $matches[1]
                Tech  = [int]$matches[2]
                Id    = [uint32]$matches[3]
                State = $matches[4]
            }
        }
    }
    return $out
}

function Show-Targets($targets) {
    $i = 0
    foreach ($t in $targets) {
        $i++
        $tech = if ($techName.ContainsKey($t.Tech)) { $techName[$t.Tech] } else { "tech=$($t.Tech)" }
        Write-Host ("{0,3}. {1,-28} {2,-12} id={3,-8} {4}" -f $i, $t.Name, $tech, $t.Id, $t.State)
    }
}

function Ask-Index([string]$prompt, [int]$max, [int]$fallback) {
    while ($true) {
        $raw = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace($raw)) { return $fallback }
        $n = 0
        if ([int]::TryParse($raw.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $max) { return $n }
        Write-Host ("  请输入 1..{0}" -f $max) -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '=== displays ===' -ForegroundColor Cyan
$targets = @(Get-Targets)
if ($targets.Count -eq 0) { throw 'No display targets found.' }
Show-Targets $targets
Write-Host ''

$tv = $null
$pc = $null

if ($Yes) {
    $tv = $targets | Where-Object { $_.Tech -eq 5 } | Select-Object -First 1
    $pc = $targets | Where-Object { $_.Tech -eq 10 } | Select-Object -First 1
    if (-not $tv -or -not $pc) { throw 'Auto mode needs one HDMI and one DisplayPort output.' }
}
else {
    $tvIdx = Ask-Index '哪一个是电视?输编号' $targets.Count 0
    if ($tvIdx -eq 0) { throw '需要选一个电视编号。' }
    $tv = $targets[$tvIdx - 1]

    $rest = @($targets | Where-Object { $_.Id -ne $tv.Id })
    Write-Host ''
    Write-Host '=== remaining ===' -ForegroundColor Cyan
    Show-Targets $rest
    $pcIdx = Ask-Index '哪一个是电脑显示器?输编号' $rest.Count 1
    $pc = $rest[$pcIdx - 1]
}

Write-Host ''
Write-Host ("电视: {0} (id={1})" -f $tv.Name, $tv.Id) -ForegroundColor Green
Write-Host ("显示器: {0} (id={1})" -f $pc.Name, $pc.Id) -ForegroundColor Green
Write-Host ''

Write-Host '=== audio outputs ===' -ForegroundColor Cyan
$audioLines = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'AudioSwitch.ps1') -List 2>&1 | Out-String
$audioLines -split "`r?`n" | Where-Object { $_ -match '^\s*\d+\.\s' } | ForEach-Object { Write-Host $_ }

$audio = @()
foreach ($line in ($audioLines -split "`r?`n")) {
    if ($line -match '^\s*\d+\.\s+(.+)$') { $audio += $matches[1].Trim() }
}

$tvAudio = ''
$pcAudio = ''

if (-not $Yes -and $audio.Count -gt 0) {
    Write-Host ''
    $n = Ask-Index '电视用哪个音频?输编号(直接回车=不切音频)' $audio.Count 0
    if ($n -gt 0) { $tvAudio = $audio[$n - 1] }
    $m = Ask-Index '桌面音箱是哪个?输编号(直接回车=不切音频)' $audio.Count 0
    if ($m -gt 0) { $pcAudio = $audio[$m - 1] }
}

$settings = @"
@{
    TvTargetId = $($tv.Id)
    PcTargetId = $($pc.Id)
    TvAudio    = '$($tvAudio -replace "'", "''")'
    PcAudio    = '$($pcAudio -replace "'", "''")'
    VkTv       = 0x2D
    VkPc       = 0x21
}
"@

$settingsPath = Join-Path $PSScriptRoot 'settings.psd1'
[System.IO.File]::WriteAllText($settingsPath, $settings, (New-Object System.Text.UTF8Encoding($true)))

Write-Host ''
Write-Host ("已写入 {0}" -f $settingsPath) -ForegroundColor Green
Write-Host ''
Write-Host '下一步:' -ForegroundColor Cyan
Write-Host '  Toggle-SteamTV.ps1 -ForceTv    切到电视并开大屏'
Write-Host '  Toggle-SteamTV.ps1 -ForcePc    切回显示器'
Write-Host '  Watch-Keys.ps1                 监听两个按键'

<#
.SYNOPSIS
  Move Steam Big Picture onto a TV (or back to the desktop monitor), leaving
  exactly one display active.

.DESCRIPTION
  Steam Big Picture always opens on the *primary* display and offers no
  per-monitor choice. The only reliable way to get it onto a TV is to make the
  TV the only active output for the moment, launch it, and later switch back.

  This script does that in three steps:
    1. DisplaySwitch /extend  - bring both outputs up so the target has a valid
                                mode path (SetDisplayConfig returns 87 without it)
    2. SetDisplayConfig       - keep only the chosen target (the other output is
                                actually powered down, not merely moved)
    3. switch default audio + launch steam://open/bigpicture

.PARAMETER ForceTv
  Always go to the TV, regardless of the current state.

.PARAMETER ForcePc
  Always go back to the monitor, regardless of the current state.

.PARAMETER TvTargetId
  DisplayConfig target id (the "id=" column from Get-DisplayInfo.ps1) of the TV.
  When omitted, the script auto-detects the single target whose output
  technology matches -TvTech.

.PARAMETER PcTargetId
  Same, for the desktop monitor.

.PARAMETER TvTech
  Output technology used for TV auto-detection. 5 = HDMI (default).

.PARAMETER PcTech
  Output technology used for monitor auto-detection. 10 = DisplayPort (default).

.PARAMETER TvAudio
  Substring of the TV's audio endpoint name, e.g. "TV HDMI Output".
  Leave empty to skip audio switching.

.PARAMETER PcAudio
  Substring of the desktop speaker endpoint name. Leave empty to skip.

.PARAMETER WaitSeconds
  Settle time after the display change before launching Big Picture.

.PARAMETER NoAudio
  Never touch audio at all.

.EXAMPLE
  .\Toggle-SteamTV.ps1 -ForceTv -TvAudio "TV HDMI Output" -PcAudio "Speakers"

.EXAMPLE
  .\Toggle-SteamTV.ps1 -ForcePc
#>
[CmdletBinding()]
param(
    [switch]$ForceTv,
    [switch]$ForcePc,
    [uint32]$TvTargetId = 0,
    [uint32]$PcTargetId = 0,
    [int]$TvTech = 5,
    [int]$PcTech = 10,
    [string]$TvAudio = '',
    [string]$PcAudio = '',
    [int]$WaitSeconds = 3,
    [switch]$NoAudio,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'lib\DispInfo.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'lib\DisplayConfig.cs')

function Get-AllTargets {
    $out = @()
    foreach ($line in ([DispConfig]::ListAllTargets() -split "`r?`n")) {
        if ($line -match '^\d+\|(.*)\|tech=(\d+)\|id=(\d+)\|(active|inactive)$') {
            $out += [pscustomobject]@{
                Name = $matches[1]
                Tech = [int]$matches[2]
                Id   = [uint32]$matches[3]
                State = $matches[4]
            }
        }
    }
    return $out
}

function Get-ActiveIds {
    $ids = @()
    foreach ($line in ([DispConfig]::ListTargets() -split "`r?`n")) {
        if ($line -match 'id=(\d+)') { $ids += [uint32]$matches[1] }
    }
    return $ids
}

function Resolve-Target {
    param([uint32]$Explicit, [int]$Tech, [string]$Label, [string]$ParamName)
    if ($Explicit -ne 0) { return $Explicit }
    $all = Get-AllTargets
    if ($all.Count -eq 0) { throw 'No display targets reported by the driver.' }
    $cand = @($all | Where-Object { $_.Tech -eq $Tech })
    if ($cand.Count -eq 1) {
        Write-Host ("  auto: {0} -> {1} (id={2})" -f $Label, $cand[0].Name, $cand[0].Id) -ForegroundColor DarkGray
        return $cand[0].Id
    }
    if ($cand.Count -eq 0) {
        throw ("No {0} target with tech={1}. Run Get-DisplayInfo.ps1, then pass -{2} <id>." -f $Label, $Tech, $ParamName)
    }
    $list = ($cand | ForEach-Object { "{0} [id={1}]" -f $_.Name, $_.Id }) -join ', '
    throw ("Multiple {0} candidates (tech={1}): {2}. Pass -{3} <id>." -f $Label, $Tech, $list, $ParamName)
}

function Set-Audio([string]$name) {
    if (-not $name) { return }
    $script = Join-Path $PSScriptRoot 'AudioSwitch.ps1'
    if (-not (Test-Path $script)) {
        Write-Host '  AudioSwitch.ps1 not found, skipping audio.' -ForegroundColor DarkYellow
        return
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Set $name | Out-Host
}

$ds = Join-Path $env:SystemRoot 'System32\DisplaySwitch.exe'

$tvId = Resolve-Target -Explicit $TvTargetId -Tech $TvTech -Label 'TV' -ParamName 'TvTargetId'
$pcId = Resolve-Target -Explicit $PcTargetId -Tech $PcTech -Label 'monitor' -ParamName 'PcTargetId'
if ($tvId -eq $pcId) { throw 'TV and monitor resolved to the same target. Pass explicit ids.' }

$active = Get-ActiveIds
$onTv = ($active.Count -eq 1 -and $active[0] -eq $tvId)
if ($ForceTv) { $onTv = $false }
if ($ForcePc) { $onTv = $true }

$audioEnabled = -not $NoAudio

if ($DryRun) {
    Write-Host ("dry run: tv={0} pc={1} onTv={2} audio={3}" -f $tvId, $pcId, $onTv, $audioEnabled) -ForegroundColor Yellow
    exit 0
}

if (-not $onTv) {
    Write-Host '[1/3] leaving only the TV active ...' -ForegroundColor Cyan
    & $ds /extend
    Start-Sleep -Seconds 2
    $r = [DispConfig]::OnlyTargetById($tvId)
    Write-Host ('      ' + $r)
    if ($r -ne 'set=0') {
        Write-Host 'TV did not come up (powered off, wrong input, or no cable). Aborted.' -ForegroundColor Yellow
        exit 1
    }
    Start-Sleep -Seconds $WaitSeconds

    Write-Host '[2/3] switching audio to the TV ...' -ForegroundColor Cyan
    if ($audioEnabled) { Set-Audio $TvAudio } else { Write-Host '      skipped (-NoAudio)' -ForegroundColor DarkGray }

    Write-Host '[3/3] opening Steam Big Picture ...' -ForegroundColor Cyan
    Start-Process 'steam://open/bigpicture'

    Write-Host 'Done. Run again (or -ForcePc) to go back.' -ForegroundColor Green
}
else {
    Write-Host '[1/3] restoring extend, then keeping only the monitor ...' -ForegroundColor Cyan
    & $ds /extend
    Start-Sleep -Seconds 2
    Write-Host ('      ' + [DispConfig]::OnlyTargetById($pcId))
    Start-Sleep -Seconds $WaitSeconds

    Write-Host '[2/3] switching audio back ...' -ForegroundColor Cyan
    if ($audioEnabled) { Set-Audio $PcAudio } else { Write-Host '      skipped (-NoAudio)' -ForegroundColor DarkGray }

    Write-Host '[3/3] back on the desktop monitor.' -ForegroundColor Green
}

<#
.SYNOPSIS
    DCS Pre-Flight Launcher (engine). Reads apps.json, launches your companion
    apps in order, runs each app's post-launch actions (clicks / keys / popup
    dismissals), applies AutoTune, then launches DCS World MT.

.DESCRIPTION
    Config lives in apps.json next to this script - edit it with the visual
    manager (DCS-Preflight-Manager.ps1), not by hand. Missing apps are warned
    about and skipped, never fatal.

.PARAMETER NoDCS      Set up companions only; do not launch DCS.
.PARAMETER NoTune     Skip the AutoTune graphics step.
.PARAMETER TuneMode   Performance | Balanced | Quality (overrides config).
#>
[CmdletBinding()]
param(
    [switch]$NoDCS,
    [switch]$NoTune,
    [ValidateSet('Performance','Balanced','Quality')]
    [string]$TuneMode
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'Native.ps1')
. (Join-Path $root 'Common.ps1')
Add-Type -AssemblyName System.Windows.Forms

# ---- load config ----------------------------------------------------------
$cfgPath = Get-PfConfigPath $root
if (-not (Test-Path -LiteralPath $cfgPath)) {
    Write-Host ''
    Write-Host 'First run - scanning for installed DCS companion apps...' -ForegroundColor Cyan
    [void](Initialize-PfConfig $cfgPath $root)
    Write-Host "Created $cfgPath" -ForegroundColor Green
    Write-Host 'Open the Manager to review the list before flying.' -ForegroundColor Yellow
}
$cfg      = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
$settings = $cfg.settings
if (-not $TuneMode) { $TuneMode = $settings.autotune.mode }
if (-not $TuneMode) { $TuneMode = 'Balanced' }

# ---- console helpers ------------------------------------------------------
function Write-Step($n, $msg) { Write-Host ("[{0}] {1}" -f $n, $msg) -ForegroundColor Cyan }
function Write-Ok($msg)       { Write-Host ("      OK   {0}" -f $msg) -ForegroundColor Green }
function Write-Skip($msg)     { Write-Host ("      --   {0}" -f $msg) -ForegroundColor DarkGray }
function Write-Warn2($msg)    { Write-Host ("      !!   {0}" -f $msg) -ForegroundColor Yellow }

function Test-Running($proc) {
    if (-not $proc) { return $false }
    return [bool](Get-Process -Name $proc -ErrorAction SilentlyContinue)
}

# ---- window / action helpers ---------------------------------------------
function Wait-ForWindow($substr, $timeoutSec) {
    if (-not $substr) { return [IntPtr]::Zero }
    $ticks = [math]::Max(1, [int]$timeoutSec) * 2
    for ($i = 0; $i -lt $ticks; $i++) {
        $h = [PfNative]::FindWindow($substr)
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 500
    }
    return [IntPtr]::Zero
}

function Invoke-PopupSweep {
    if (-not $settings.popupRules) { return }
    foreach ($r in $settings.popupRules) {
        if (-not $r.enabled) { continue }
        $h = [PfNative]::FindWindow($r.titleMatch)
        if ($h -ne [IntPtr]::Zero) {
            [PfNative]::SetForegroundWindow($h) | Out-Null
            Start-Sleep -Milliseconds 250
            [System.Windows.Forms.SendKeys]::SendWait($r.keys)
            Write-Ok "dismissed popup '$($r.titleMatch)'"
        }
    }
}

function Invoke-Action($act) {
    switch ($act.type) {
        'wait' {
            Start-Sleep -Seconds ([int]$act.seconds)
        }
        'click' {
            if ($act.ifWindow) {
                $h = Wait-ForWindow $act.ifWindow $act.timeout
                if ($h -eq [IntPtr]::Zero) { Write-Skip "window '$($act.ifWindow)' not present - skip click"; return }
                [PfNative]::SetForegroundWindow($h) | Out-Null
                Start-Sleep -Milliseconds 350
            }
            [PfNative]::ClickAt([int]$act.x, [int]$act.y)
            $lbl = if ($act.label) { $act.label } else { "$($act.x),$($act.y)" }
            Write-Ok "clicked [$lbl]"
        }
        'sendkeys' {
            if ($act.ifWindow) {
                $h = Wait-ForWindow $act.ifWindow $act.timeout
                if ($h -eq [IntPtr]::Zero) { Write-Skip "window '$($act.ifWindow)' not present - skip keys"; return }
                [PfNative]::SetForegroundWindow($h) | Out-Null
                Start-Sleep -Milliseconds 350
            }
            [System.Windows.Forms.SendKeys]::SendWait($act.keys)
            Write-Ok "sent keys '$($act.keys)'"
        }
        default { Write-Warn2 "unknown action type '$($act.type)'" }
    }
}

# ---- launch one app -------------------------------------------------------
function Start-App($app) {
    $name = $app.name
    if (-not $app.enabled) { Write-Skip "$name (disabled)"; return }

    $alreadyRunning = Test-Running $app.proc
    if ($alreadyRunning) {
        Write-Ok "$name already running"
    }
    elseif (-not (Test-Path -LiteralPath $app.path)) {
        Write-Warn2 "$name not found, skipping: $($app.path)"
        return
    }
    else {
        try {
            Start-Process -FilePath $app.path -WorkingDirectory (Split-Path -Parent $app.path) -ErrorAction Stop | Out-Null
            Write-Ok "launched $name"
        } catch {
            Write-Warn2 "failed to launch $name : $($_.Exception.Message)"
            return
        }
        if ($app.waitForUp -and $app.proc) {
            for ($i = 0; $i -lt 15; $i++) {
                if (Test-Running $app.proc) { Write-Ok "$name is up"; break }
                Start-Sleep -Seconds 1
            }
        }
        if ([int]$app.delayAfter -gt 0) { Start-Sleep -Seconds ([int]$app.delayAfter) }
    }

    # post-launch actions run whether or not it was already running
    if ($app.actions) {
        foreach ($act in $app.actions) {
            try { Invoke-Action $act } catch { Write-Warn2 "action failed: $($_.Exception.Message)" }
        }
    }
    Invoke-PopupSweep
}

function Invoke-AutoTune {
    $at = $settings.autotune
    if ($NoTune -or -not $at.enabled) { Write-Skip 'AutoTune skipped'; return }
    if (-not (Test-Path -LiteralPath $at.script)) { Write-Warn2 "AutoTune script not found: $($at.script)"; return }
    if (Test-Running 'DCS')                        { Write-Warn2 'DCS already running - AutoTune cannot write options.lua, skipping'; return }
    try {
        Write-Host ''
        & $at.script -Mode $TuneMode
        Write-Ok "AutoTune applied ($TuneMode profile)"
    } catch {
        Write-Warn2 "AutoTune failed (continuing): $($_.Exception.Message)"
    }
}

function Start-DCS {
    if ($NoDCS -or -not $settings.launchDcs) { Write-Skip 'DCS launch skipped'; return $false }
    if (Test-Running 'DCS')                  { Write-Ok 'DCS already running'; return $true }
    $exe = $settings.dcsExe
    if (-not (Test-Path -LiteralPath $exe))  { Write-Warn2 "DCS not found: $exe"; return $false }

    $cd = [int]$settings.dcsCountdown
    if ($cd -lt 1) { $cd = 1 }
    Write-Host ''
    Write-Host ("  Launching DCS World MT in {0}s - press any key to CANCEL..." -f $cd) -ForegroundColor Magenta
    for ($i = $cd; $i -gt 0; $i--) {
        Write-Host ("  {0}..." -f $i) -NoNewline -ForegroundColor Magenta
        for ($t = 0; $t -lt 10; $t++) {
            if ([Console]::KeyAvailable) {
                [Console]::ReadKey($true) | Out-Null
                Write-Host ''
                Write-Warn2 'DCS launch cancelled. Companion apps are still running.'
                return $false
            }
            Start-Sleep -Milliseconds 100
        }
        Write-Host ''
        Invoke-PopupSweep
    }
    Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
    Write-Ok 'DCS World MT launching'
    return $true
}

# ---- run ------------------------------------------------------------------
Write-Host ''
Write-Host '============================================================' -ForegroundColor White
Write-Host '              DCS PRE-FLIGHT LAUNCHER' -ForegroundColor White
Write-Host '============================================================' -ForegroundColor White

$step = 1
foreach ($app in $cfg.apps) {
    Write-Step $step $app.name
    Start-App $app
    $step++
}

Write-Step $step "DCS-AutoTune ($TuneMode)"
Invoke-AutoTune
$step++

Write-Step $step 'DCS World MT'
$launched = Start-DCS

Write-Host ''
Write-Host '------------------------------------------------------------' -ForegroundColor White
Write-Host '  Pre-flight complete. Fly safe.' -ForegroundColor Green
Write-Host '------------------------------------------------------------' -ForegroundColor White

if (-not $launched) { Write-Host ''; Read-Host 'Press Enter to close' }

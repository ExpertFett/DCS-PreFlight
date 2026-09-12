# Common.ps1 - config location + installed-app detection for DCS Pre-Flight.
# Shared by the engine and the manager. Dot-source after Native.ps1.

# ---------------------------------------------------------------- config path
function Test-PfWritable($dir) {
    try {
        if (-not (Test-Path -LiteralPath $dir)) { return $false }
        $t = Join-Path $dir ('.pfw_' + [System.IO.Path]::GetRandomFileName())
        [System.IO.File]::WriteAllText($t, 'x')
        Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}

# Portable mode: config sits next to the scripts (zip / per-user install).
# Installed read-only (e.g. Program Files): fall back to %LOCALAPPDATA%.
function Get-PfConfigPath($scriptRoot) {
    $local = Join-Path $scriptRoot 'apps.json'
    if (Test-PfWritable $scriptRoot) { return $local }
    $dir = Join-Path $env:LOCALAPPDATA 'DCS-Preflight'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dst = Join-Path $dir 'apps.json'
    if ((-not (Test-Path -LiteralPath $dst)) -and (Test-Path -LiteralPath $local)) {
        Copy-Item -LiteralPath $local -Destination $dst -Force
    }
    return $dst
}

# ---------------------------------------------------------------- detection
function Get-PfStartMenuIndex {
    $sh  = New-Object -ComObject WScript.Shell
    $idx = @{}
    $menus = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
               "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")
    foreach ($sm in $menus) {
        if (-not (Test-Path -LiteralPath $sm)) { continue }
        $lnks = Get-ChildItem -LiteralPath $sm -Recurse -Filter *.lnk -ErrorAction SilentlyContinue
        foreach ($f in $lnks) {
            try {
                $t = $sh.CreateShortcut($f.FullName).TargetPath
                if ($t -and $t.ToLower().EndsWith('.exe') -and (Test-Path -LiteralPath $t)) {
                    if (-not $idx.ContainsKey($f.BaseName)) { $idx[$f.BaseName] = $t }
                }
            } catch { }
        }
    }
    return $idx
}

# Known DCS companion apps. Detection order = default launch order.
function Get-PfCatalog {
    $pf   = ${env:ProgramFiles}
    $pf86 = ${env:ProgramFiles(x86)}
    $lad  = $env:LOCALAPPDATA
    $usr  = $env:USERPROFILE
    return @(
        @{ name='Stream Deck';              proc='StreamDeck';                lnk='^Stream Deck$';            paths=@("$pf\Elgato\StreamDeck\StreamDeck.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='SimHaptic';                proc='SimHaptic';                 lnk='^SimHaptic$';             paths=@("$usr\Saved Games\SimHaptic\SimHaptic.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='HF8 (Interhaptics)';       proc='HapticService';             lnk='Interhaptics|HF8';        paths=@("$pf86\Interhaptics\HapticService\HapticService.exe","$pf\Interhaptics\HapticService\HapticService.exe"); delayAfter=3; waitForUp=$false; enabled=$true }
        @{ name='SimShaker for Aviators';   proc='SimShaker';                 lnk='SimShaker';               paths=@("$pf86\SimShaker for Aviators\SimShaker.exe","$pf\SimShaker for Aviators\SimShaker.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='DCRealistic';              proc='DCRealistic';               lnk='^DCRealistic$';           paths=@("$usr\Saved Games\DCRealistic\DCRealistic.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='TrackIR';                  proc='TrackIR5';                  lnk='TrackIR';                 paths=@("$pf86\NaturalPoint\TrackIR5\TrackIR5.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='opentrack';                proc='opentrack';                 lnk='opentrack';               paths=@("$pf\opentrack\opentrack.exe"); delayAfter=0; waitForUp=$false; enabled=$false }
        @{ name='SimAppPro (Winwing)';      proc='SimAppPro';                 lnk='^SimAppPro$';             paths=@("$lad\Programs\SimAppPro\SimAppPro.exe"); delayAfter=2; waitForUp=$false; enabled=$true }
        @{ name='VoiceAttack';              proc='VoiceAttack';               lnk='VoiceAttack';             paths=@("$pf\VoiceAttack\VoiceAttack.exe","$pf86\VoiceAttack\VoiceAttack.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='Virtual Desktop Streamer'; proc='VirtualDesktop.Streamer';   lnk='Virtual Desktop Streamer';paths=@("$pf\Virtual Desktop Streamer\VirtualDesktop.Streamer.exe"); delayAfter=0; waitForUp=$true;  enabled=$true }
        @{ name='SteamVR';                  proc='vrmonitor';                 lnk='^SteamVR$';               paths=@("$pf86\Steam\steamapps\common\SteamVR\bin\win64\vrmonitor.exe"); delayAfter=0; waitForUp=$false; enabled=$false }
        @{ name='DCS-SRS Client';           proc='SR-ClientRadio';            lnk='DCS-SRS Client|SimpleRadio'; paths=@("$pf\DCS-SimpleRadio-Standalone\Client\SR-ClientRadio.exe","$pf86\DCS-SimpleRadio-Standalone\Client\SR-ClientRadio.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='LotAtc Client';            proc='LotAtcClient';              lnk='LotAtc Client';           paths=@(); delayAfter=0; waitForUp=$false; enabled=$false }
        @{ name='OpenKneeboard';            proc='OpenKneeboardApp';          lnk='^OpenKneeboard$';         paths=@("$pf\OpenKneeboard\bin\OpenKneeboardApp.exe"); delayAfter=0; waitForUp=$false; enabled=$true }
        @{ name='Tacview';                  proc='Tacview';                   lnk='^Tacview';                paths=@("$pf\Tacview\Tacview.exe","$pf86\Tacview\Tacview.exe"); delayAfter=0; waitForUp=$false; enabled=$false }
        @{ name='OBS Studio';               proc='obs64';                     lnk='OBS Studio';              paths=@("$pf\obs-studio\bin\64bit\obs64.exe"); delayAfter=0; waitForUp=$false; enabled=$false }
        @{ name='Discord';                  proc='Discord';                   lnk='zzz-no-lnk-match';        paths=@("$lad\Discord\app-*\Discord.exe"); delayAfter=0; waitForUp=$false; enabled=$false }
        @{ name='YouTube Music';            proc='youtube-music-desktop-app'; lnk='YouTube Music';           paths=@("$lad\youtube_music_desktop_app\youtube-music-desktop-app.exe"); delayAfter=3; waitForUp=$false; enabled=$false }
    )
}

function Resolve-PfCatalogItem($item, $smIndex) {
    foreach ($p in $item.paths) {
        if (-not $p) { continue }
        # Wildcard paths (versioned folders, e.g. Discord's app-1.2.3) - newest wins.
        if ($p.Contains('*')) {
            $hit = Get-ChildItem -Path $p -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
            continue
        }
        if (Test-Path -LiteralPath $p) { return $p }
    }
    foreach ($k in $smIndex.Keys) {
        if ($k -match $item.lnk) { return $smIndex[$k] }
    }
    return $null
}

# Returns app entries (config shape) for everything actually installed.
function Find-PfApps {
    $sm  = Get-PfStartMenuIndex
    $out = New-Object System.Collections.ArrayList
    foreach ($c in (Get-PfCatalog)) {
        $path = Resolve-PfCatalogItem $c $sm
        if (-not $path) { continue }
        [void]$out.Add(@{
            name = $c.name; path = $path; proc = $c.proc
            enabled = $c.enabled; waitForUp = $c.waitForUp; delayAfter = $c.delayAfter
            actions = @()
        })
    }
    return $out
}

function Find-PfDcsExe {
    $cands = New-Object System.Collections.ArrayList
    foreach ($key in @('HKCU:\Software\Eagle Dynamics\DCS World',
                       'HKCU:\Software\Eagle Dynamics\DCS World OpenBeta')) {
        try {
            $v = (Get-ItemProperty -Path $key -ErrorAction Stop).Path
            if ($v) { [void]$cands.Add($v) }
        } catch { }
    }
    foreach ($d in @("${env:ProgramFiles}\Eagle Dynamics\DCS World",
                     "${env:ProgramFiles}\Eagle Dynamics\DCS World OpenBeta",
                     "${env:ProgramFiles(x86)}\Steam\steamapps\common\DCSWorld",
                     "C:\Games\DCS World", "D:\Eagle Dynamics\DCS World", "D:\Games\DCS World")) {
        [void]$cands.Add($d)
    }
    foreach ($d in $cands) {
        foreach ($b in @('bin-mt\DCS.exe', 'bin\DCS.exe')) {
            $p = Join-Path $d $b
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return ''
}

function Find-PfAutoTune($scriptRoot) {
    foreach ($p in @((Join-Path $scriptRoot 'Tune-DCS.ps1'),
                     (Join-Path (Split-Path -Parent $scriptRoot) 'DCS-AutoTune\Tune-DCS.ps1'),
                     "$env:USERPROFILE\Saved Games\Claude Dump\DCS-AutoTune\Tune-DCS.ps1")) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

function Find-PfModAudit($scriptRoot) {
    foreach ($p in @((Join-Path $scriptRoot 'Check-DcsUpdate.ps1'),
                     (Join-Path (Split-Path -Parent $scriptRoot) 'DCS-ModAudit\Check-DcsUpdate.ps1'),
                     "$env:USERPROFILE\Saved Games\Claude Dump\DCS-ModAudit\Check-DcsUpdate.ps1")) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

# Build a fresh config for this machine and write it to $cfgPath.
function Initialize-PfConfig($cfgPath, $scriptRoot) {
    $apps  = Find-PfApps
    $dcs   = Find-PfDcsExe
    $tune  = Find-PfAutoTune $scriptRoot
    $audit = Find-PfModAudit $scriptRoot
    $cfg = @{
        settings = @{
            launchDcs     = [bool]$dcs
            dcsExe        = $dcs
            dcsCountdown  = 6
            autotune      = @{ enabled = [bool]$tune; script = $tune; mode = 'Balanced' }
            modAuditCheck = @{ enabled = [bool]$audit; script = $audit; quiet = $true }
            popupRules    = @(
                @{ titleMatch = 'Update Available'; keys = '{ESC}'; enabled = $false }
                @{ titleMatch = 'New version';      keys = '{ESC}'; enabled = $false }
            )
        }
        apps = $apps
    }
    $json = $cfg | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($cfgPath, $json)
    return $cfg
}

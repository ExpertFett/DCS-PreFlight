<#
  DCS Pre-Flight Manager - visual editor for apps.json.
  - Add / remove / reorder / enable companion apps (no file editing).
  - Detect installed DCS companion apps automatically.
  - Record post-launch clicks with a live mouse tracker (press F9 to capture).
  - Configure AutoTune, DCS launch, countdown, and auto-dismiss popup rules.
  - Launch the whole pre-flight from one button.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) [void][System.Windows.Forms.MessageBox]::Show($e.Exception.Message, 'DCS Pre-Flight Manager - error', 'OK', 'Error') })

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'Native.ps1')
. (Join-Path $root 'Common.ps1')

$script:enginePath = Join-Path $root 'DCS-Preflight.ps1'
$script:cfgPath    = Get-PfConfigPath $root
$script:curIdx     = -1
$script:refreshing = $false

# ---------------------------------------------------------------- load config
function ConvertTo-PfApp($a) {
    $acts = New-Object System.Collections.ArrayList
    if ($a.actions) {
        foreach ($ac in $a.actions) {
            $h = @{ type = [string]$ac.type }
            switch ($ac.type) {
                'wait'     { $h.seconds  = [int]$ac.seconds }
                'click'    { $h.x = [int]$ac.x; $h.y = [int]$ac.y; $h.label = [string]$ac.label; $h.ifWindow = [string]$ac.ifWindow; $h.timeout = [int]$ac.timeout }
                'sendkeys' { $h.keys = [string]$ac.keys; $h.ifWindow = [string]$ac.ifWindow; $h.timeout = [int]$ac.timeout }
            }
            [void]$acts.Add($h)
        }
    }
    return @{
        name = [string]$a.name; path = [string]$a.path; proc = [string]$a.proc
        enabled = [bool]$a.enabled; waitForUp = [bool]$a.waitForUp; delayAfter = [int]$a.delayAfter
        actions = $acts
    }
}

function Load-Config {
    if (-not (Test-Path -LiteralPath $script:cfgPath)) {
        [void][System.Windows.Forms.MessageBox]::Show("No config found - scanning for installed DCS companion apps.", 'First run', 'OK', 'Information')
        [void](Initialize-PfConfig $script:cfgPath $root)
    }
    $raw = Get-Content -LiteralPath $script:cfgPath -Raw | ConvertFrom-Json
    $cfg = @{
        settings = @{
            launchDcs    = [bool]$raw.settings.launchDcs
            dcsExe       = [string]$raw.settings.dcsExe
            dcsCountdown = [int]$raw.settings.dcsCountdown
            autotune     = @{
                enabled = [bool]$raw.settings.autotune.enabled
                script  = [string]$raw.settings.autotune.script
                mode    = [string]$raw.settings.autotune.mode
            }
            modAuditCheck = @{
                enabled = [bool]$raw.settings.modAuditCheck.enabled
                script  = [string]$raw.settings.modAuditCheck.script
                quiet   = if ($null -ne $raw.settings.modAuditCheck.quiet) { [bool]$raw.settings.modAuditCheck.quiet } else { $true }
            }
            popupRules = New-Object System.Collections.ArrayList
        }
        apps = New-Object System.Collections.ArrayList
    }
    foreach ($r in $raw.settings.popupRules) {
        [void]$cfg.settings.popupRules.Add(@{ titleMatch = [string]$r.titleMatch; keys = [string]$r.keys; enabled = [bool]$r.enabled })
    }
    foreach ($a in $raw.apps) { [void]$cfg.apps.Add((ConvertTo-PfApp $a)) }
    return $cfg
}

try { $script:cfg = Load-Config }
catch {
    [void][System.Windows.Forms.MessageBox]::Show("Could not load config:`n$($_.Exception.Message)", 'DCS Pre-Flight Manager', 'OK', 'Error')
    return
}

# ---------------------------------------------------------------- helpers
function Show-Input($prompt, $title, $default) {
    return [Microsoft.VisualBasic.Interaction]::InputBox($prompt, $title, $default)
}

function Format-Action($act) {
    switch ($act.type) {
        'wait'     { return "Wait $($act.seconds)s" }
        'click'    { $c = "Click [$($act.label)]"; if ($act.ifWindow) { $c += " IF win~'$($act.ifWindow)'" }; return $c }
        'sendkeys' { $c = "Keys '$($act.keys)'";   if ($act.ifWindow) { $c += " IF win~'$($act.ifWindow)'" }; return $c }
        default    { return "($($act.type))" }
    }
}

# ---------------------------------------------------------------- the recorder
function Invoke-Recorder {
    $ov = New-Object System.Windows.Forms.Form
    $ov.FormBorderStyle = 'FixedToolWindow'
    $ov.Text = 'Recording'
    $ov.TopMost = $true
    $ov.StartPosition = 'Manual'
    $ov.Location = New-Object System.Drawing.Point(20, 20)
    $ov.Size = New-Object System.Drawing.Size(430, 135)
    $ov.ShowInTaskbar = $false
    $ov.BackColor = [System.Drawing.Color]::Black

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.ForeColor = [System.Drawing.Color]::Lime
    $lbl.Font = New-Object System.Drawing.Font('Consolas', 11)
    $lbl.Dock = 'Fill'
    $lbl.TextAlign = 'MiddleLeft'
    $ov.Controls.Add($lbl)

    $script:recResult = $null
    $tm = New-Object System.Windows.Forms.Timer
    $tm.Interval = 50
    $tm.Add_Tick({
        $p = [System.Windows.Forms.Cursor]::Position
        $t = [PfNative]::WindowTitleAtCursor()
        $lbl.Text = "  X = $($p.X)    Y = $($p.Y)`n  Window: $t`n`n  Hover the target, press F9 to CAPTURE`n  (press Esc to cancel)"
        if (((([PfNative]::GetAsyncKeyState(0x78)) -band 0x8000)) -ne 0) {
            $tm.Stop(); $script:recResult = @{ x = $p.X; y = $p.Y; title = $t }; $ov.Close()
        }
        elseif (((([PfNative]::GetAsyncKeyState(0x1B)) -band 0x8000)) -ne 0) {
            $tm.Stop(); $script:recResult = $null; $ov.Close()
        }
    })
    $ov.Add_Shown({ $tm.Start() })
    $ov.Add_FormClosed({ $tm.Stop(); $tm.Dispose() })
    [void]$ov.ShowDialog()
    return $script:recResult
}

# ---------------------------------------------------------------- build form
$f = New-Object System.Windows.Forms.Form
$f.Text = 'DCS Pre-Flight Manager'
$f.Size = New-Object System.Drawing.Size(950, 740)
$f.StartPosition = 'CenterScreen'
$f.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'DCS PRE-FLIGHT MANAGER'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(12, 8)
$title.AutoSize = $true
$f.Controls.Add($title)

# ---- app list (left) ----
$lblApps = New-Object System.Windows.Forms.Label
$lblApps.Text = 'Programs - tick the box to launch. Order = launch order.'
$lblApps.Location = New-Object System.Drawing.Point(12, 40)
$lblApps.AutoSize = $true
$f.Controls.Add($lblApps)

$lstApps = New-Object System.Windows.Forms.ListView
$lstApps.Location = New-Object System.Drawing.Point(12, 62)
$lstApps.Size = New-Object System.Drawing.Size(250, 330)
$lstApps.View = 'Details'
$lstApps.CheckBoxes = $true
$lstApps.FullRowSelect = $true
$lstApps.MultiSelect = $false
$lstApps.HideSelection = $false
$lstApps.HeaderStyle = 'None'
[void]$lstApps.Columns.Add('Program', 228)
$f.Controls.Add($lstApps)

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add'; $btnAdd.Location = New-Object System.Drawing.Point(12, 398); $btnAdd.Size = New-Object System.Drawing.Size(60, 28)
$f.Controls.Add($btnAdd)
$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = 'Remove'; $btnRemove.Location = New-Object System.Drawing.Point(76, 398); $btnRemove.Size = New-Object System.Drawing.Size(66, 28)
$f.Controls.Add($btnRemove)
$btnUp = New-Object System.Windows.Forms.Button
$btnUp.Text = 'Up'; $btnUp.Location = New-Object System.Drawing.Point(150, 398); $btnUp.Size = New-Object System.Drawing.Size(50, 28)
$f.Controls.Add($btnUp)
$btnDown = New-Object System.Windows.Forms.Button
$btnDown.Text = 'Down'; $btnDown.Location = New-Object System.Drawing.Point(204, 398); $btnDown.Size = New-Object System.Drawing.Size(58, 28)
$f.Controls.Add($btnDown)

$btnDetect = New-Object System.Windows.Forms.Button
$btnDetect.Text = 'Detect Installed Programs'; $btnDetect.Location = New-Object System.Drawing.Point(12, 430); $btnDetect.Size = New-Object System.Drawing.Size(250, 28)
$f.Controls.Add($btnDetect)

$lblLegend = New-Object System.Windows.Forms.Label
$lblLegend.Text = 'Grey = program file not found on this PC'
$lblLegend.Location = New-Object System.Drawing.Point(12, 464)
$lblLegend.AutoSize = $true
$lblLegend.ForeColor = [System.Drawing.Color]::Gray
$f.Controls.Add($lblLegend)

# ---- selected app (right) ----
$grpApp = New-Object System.Windows.Forms.GroupBox
$grpApp.Text = 'Selected program'
$grpApp.Location = New-Object System.Drawing.Point(278, 40)
$grpApp.Size = New-Object System.Drawing.Size(648, 392)
$f.Controls.Add($grpApp)

$lblN = New-Object System.Windows.Forms.Label; $lblN.Text = 'Name'; $lblN.Location = New-Object System.Drawing.Point(15, 28); $lblN.AutoSize = $true; $grpApp.Controls.Add($lblN)
$txtName = New-Object System.Windows.Forms.TextBox; $txtName.Location = New-Object System.Drawing.Point(110, 25); $txtName.Size = New-Object System.Drawing.Size(380, 23); $grpApp.Controls.Add($txtName)

$lblP = New-Object System.Windows.Forms.Label; $lblP.Text = 'Program (.exe)'; $lblP.Location = New-Object System.Drawing.Point(15, 60); $lblP.AutoSize = $true; $grpApp.Controls.Add($lblP)
$txtPath = New-Object System.Windows.Forms.TextBox; $txtPath.Location = New-Object System.Drawing.Point(110, 57); $txtPath.Size = New-Object System.Drawing.Size(420, 23); $grpApp.Controls.Add($txtPath)
$btnBrowse = New-Object System.Windows.Forms.Button; $btnBrowse.Text = 'Browse'; $btnBrowse.Location = New-Object System.Drawing.Point(538, 56); $btnBrowse.Size = New-Object System.Drawing.Size(90, 25); $grpApp.Controls.Add($btnBrowse)

$lblPr = New-Object System.Windows.Forms.Label; $lblPr.Text = 'Process name'; $lblPr.Location = New-Object System.Drawing.Point(15, 92); $lblPr.AutoSize = $true; $grpApp.Controls.Add($lblPr)
$txtProc = New-Object System.Windows.Forms.TextBox; $txtProc.Location = New-Object System.Drawing.Point(110, 89); $txtProc.Size = New-Object System.Drawing.Size(200, 23); $grpApp.Controls.Add($txtProc)
$lblPrH = New-Object System.Windows.Forms.Label; $lblPrH.Text = '(used to skip if already running)'; $lblPrH.Location = New-Object System.Drawing.Point(320, 92); $lblPrH.AutoSize = $true; $lblPrH.ForeColor = [System.Drawing.Color]::Gray; $grpApp.Controls.Add($lblPrH)

$chkWait = New-Object System.Windows.Forms.CheckBox; $chkWait.Text = 'Wait until it is running before continuing'; $chkWait.Location = New-Object System.Drawing.Point(110, 118); $chkWait.AutoSize = $true; $grpApp.Controls.Add($chkWait)

$lblD = New-Object System.Windows.Forms.Label; $lblD.Text = 'Delay after (sec)'; $lblD.Location = New-Object System.Drawing.Point(15, 148); $lblD.AutoSize = $true; $grpApp.Controls.Add($lblD)
$numDelay = New-Object System.Windows.Forms.NumericUpDown; $numDelay.Location = New-Object System.Drawing.Point(110, 145); $numDelay.Size = New-Object System.Drawing.Size(60, 23); $numDelay.Minimum = 0; $numDelay.Maximum = 600; $grpApp.Controls.Add($numDelay)

$lblA = New-Object System.Windows.Forms.Label; $lblA.Text = 'Post-launch actions (run top to bottom after the app starts):'; $lblA.Location = New-Object System.Drawing.Point(15, 182); $lblA.AutoSize = $true; $grpApp.Controls.Add($lblA)
$lstActions = New-Object System.Windows.Forms.ListBox; $lstActions.Location = New-Object System.Drawing.Point(15, 205); $lstActions.Size = New-Object System.Drawing.Size(470, 165); $grpApp.Controls.Add($lstActions)

$btnRec = New-Object System.Windows.Forms.Button; $btnRec.Text = 'Record Click (F9)'; $btnRec.Location = New-Object System.Drawing.Point(498, 205); $btnRec.Size = New-Object System.Drawing.Size(135, 32); $btnRec.BackColor = [System.Drawing.Color]::FromArgb(220, 235, 220); $grpApp.Controls.Add($btnRec)
$btnKeys = New-Object System.Windows.Forms.Button; $btnKeys.Text = 'Add Key Press'; $btnKeys.Location = New-Object System.Drawing.Point(498, 243); $btnKeys.Size = New-Object System.Drawing.Size(135, 28); $grpApp.Controls.Add($btnKeys)
$btnWait = New-Object System.Windows.Forms.Button; $btnWait.Text = 'Add Wait'; $btnWait.Location = New-Object System.Drawing.Point(498, 277); $btnWait.Size = New-Object System.Drawing.Size(135, 28); $grpApp.Controls.Add($btnWait)
$btnDelAct = New-Object System.Windows.Forms.Button; $btnDelAct.Text = 'Remove Action'; $btnDelAct.Location = New-Object System.Drawing.Point(498, 311); $btnDelAct.Size = New-Object System.Drawing.Size(135, 28); $grpApp.Controls.Add($btnDelAct)

# ---- settings ----
$grpSet = New-Object System.Windows.Forms.GroupBox
$grpSet.Text = 'Pre-flight settings'
$grpSet.Location = New-Object System.Drawing.Point(278, 440)
$grpSet.Size = New-Object System.Drawing.Size(648, 185)
$f.Controls.Add($grpSet)

$chkDcs = New-Object System.Windows.Forms.CheckBox; $chkDcs.Text = 'Launch DCS at the end'; $chkDcs.Location = New-Object System.Drawing.Point(15, 25); $chkDcs.AutoSize = $true; $grpSet.Controls.Add($chkDcs)
$txtDcs = New-Object System.Windows.Forms.TextBox; $txtDcs.Location = New-Object System.Drawing.Point(190, 22); $txtDcs.Size = New-Object System.Drawing.Size(345, 23); $grpSet.Controls.Add($txtDcs)
$btnDcsBrowse = New-Object System.Windows.Forms.Button; $btnDcsBrowse.Text = 'Browse'; $btnDcsBrowse.Location = New-Object System.Drawing.Point(542, 21); $btnDcsBrowse.Size = New-Object System.Drawing.Size(88, 25); $grpSet.Controls.Add($btnDcsBrowse)

$chkTune = New-Object System.Windows.Forms.CheckBox; $chkTune.Text = 'Run AutoTune graphics profile'; $chkTune.Location = New-Object System.Drawing.Point(15, 55); $chkTune.AutoSize = $true; $grpSet.Controls.Add($chkTune)
$lblMode = New-Object System.Windows.Forms.Label; $lblMode.Text = 'Mode'; $lblMode.Location = New-Object System.Drawing.Point(280, 56); $lblMode.AutoSize = $true; $grpSet.Controls.Add($lblMode)
$cmbMode = New-Object System.Windows.Forms.ComboBox; $cmbMode.DropDownStyle = 'DropDownList'; $cmbMode.Location = New-Object System.Drawing.Point(325, 53); $cmbMode.Size = New-Object System.Drawing.Size(130, 23); [void]$cmbMode.Items.AddRange(@('Performance','Balanced','Quality')); $grpSet.Controls.Add($cmbMode)

$lblCd = New-Object System.Windows.Forms.Label; $lblCd.Text = 'DCS launch countdown (sec)'; $lblCd.Location = New-Object System.Drawing.Point(15, 87); $lblCd.AutoSize = $true; $grpSet.Controls.Add($lblCd)
$numCd = New-Object System.Windows.Forms.NumericUpDown; $numCd.Location = New-Object System.Drawing.Point(200, 84); $numCd.Size = New-Object System.Drawing.Size(60, 23); $numCd.Minimum = 1; $numCd.Maximum = 60; $grpSet.Controls.Add($numCd)

$lblPop = New-Object System.Windows.Forms.Label; $lblPop.Text = "Auto-dismiss popups - one per line:  title text | keys      (start a line with # to disable)"; $lblPop.Location = New-Object System.Drawing.Point(15, 115); $lblPop.AutoSize = $true; $grpSet.Controls.Add($lblPop)
$txtPop = New-Object System.Windows.Forms.TextBox; $txtPop.Multiline = $true; $txtPop.ScrollBars = 'Vertical'; $txtPop.Location = New-Object System.Drawing.Point(15, 135); $txtPop.Size = New-Object System.Drawing.Size(615, 42); $grpSet.Controls.Add($txtPop)

# ---- bottom buttons ----
$btnLaunch = New-Object System.Windows.Forms.Button; $btnLaunch.Text = 'LAUNCH PRE-FLIGHT'; $btnLaunch.Location = New-Object System.Drawing.Point(12, 640); $btnLaunch.Size = New-Object System.Drawing.Size(250, 42); $btnLaunch.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $btnLaunch.BackColor = [System.Drawing.Color]::FromArgb(200, 225, 255); $f.Controls.Add($btnLaunch)
$btnSave = New-Object System.Windows.Forms.Button; $btnSave.Text = 'Save'; $btnSave.Location = New-Object System.Drawing.Point(640, 644); $btnSave.Size = New-Object System.Drawing.Size(130, 34); $f.Controls.Add($btnSave)
$btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = 'Close'; $btnClose.Location = New-Object System.Drawing.Point(796, 644); $btnClose.Size = New-Object System.Drawing.Size(130, 34); $f.Controls.Add($btnClose)
$lblStatus = New-Object System.Windows.Forms.Label; $lblStatus.Text = ''; $lblStatus.Location = New-Object System.Drawing.Point(278, 652); $lblStatus.AutoSize = $true; $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen; $f.Controls.Add($lblStatus)

# ---------------------------------------------------------------- view logic
function Get-SelIdx {
    if ($lstApps.SelectedIndices.Count -gt 0) { return $lstApps.SelectedIndices[0] }
    return -1
}

function Refresh-Actions {
    $lstActions.Items.Clear()
    if ($script:curIdx -lt 0 -or $script:curIdx -ge $script:cfg.apps.Count) { return }
    foreach ($act in $script:cfg.apps[$script:curIdx].actions) { [void]$lstActions.Items.Add((Format-Action $act)) }
}

function Load-Details($i) {
    $script:refreshing = $true
    if ($i -lt 0 -or $i -ge $script:cfg.apps.Count) {
        $grpApp.Enabled = $false
        $txtName.Text = ''; $txtPath.Text = ''; $txtProc.Text = ''; $chkWait.Checked = $false; $numDelay.Value = 0; $lstActions.Items.Clear()
        $script:refreshing = $false
        return
    }
    $grpApp.Enabled = $true
    $a = $script:cfg.apps[$i]
    $txtName.Text = [string]$a.name; $txtPath.Text = [string]$a.path; $txtProc.Text = [string]$a.proc
    $chkWait.Checked = [bool]$a.waitForUp
    $d = [int]$a.delayAfter; if ($d -lt 0) { $d = 0 }; if ($d -gt $numDelay.Maximum) { $d = $numDelay.Maximum }; $numDelay.Value = $d
    Refresh-Actions
    $script:refreshing = $false
}

function Save-Details($i) {
    if ($i -lt 0 -or $i -ge $script:cfg.apps.Count) { return }
    $a = $script:cfg.apps[$i]
    $a.name = $txtName.Text; $a.path = $txtPath.Text; $a.proc = $txtProc.Text
    $a.waitForUp = $chkWait.Checked; $a.delayAfter = [int]$numDelay.Value
}

function Update-ItemStyle($i) {
    if ($i -lt 0 -or $i -ge $lstApps.Items.Count) { return }
    $p = [string]$script:cfg.apps[$i].path
    if ($p -and (Test-Path -LiteralPath $p)) { $lstApps.Items[$i].ForeColor = [System.Drawing.Color]::Black }
    else { $lstApps.Items[$i].ForeColor = [System.Drawing.Color]::Gray }
}

function Refresh-AppList {
    $script:refreshing = $true
    $lstApps.BeginUpdate()
    $lstApps.Items.Clear()
    for ($i = 0; $i -lt $script:cfg.apps.Count; $i++) {
        $it = New-Object System.Windows.Forms.ListViewItem([string]$script:cfg.apps[$i].name)
        $it.Checked = [bool]$script:cfg.apps[$i].enabled
        [void]$lstApps.Items.Add($it)
        Update-ItemStyle $i
    }
    $lstApps.EndUpdate()
    $script:refreshing = $false
}

function Select-App($i) {
    if ($i -lt 0 -or $i -ge $lstApps.Items.Count) { $script:curIdx = -1; Load-Details -1; return }
    $lstApps.Items[$i].Selected = $true
    $lstApps.Items[$i].EnsureVisible()
    $script:curIdx = $i
    Load-Details $i
}

function Save-AllAndWrite {
    if ($script:curIdx -ge 0) { Save-Details $script:curIdx }
    for ($i = 0; $i -lt $script:cfg.apps.Count -and $i -lt $lstApps.Items.Count; $i++) {
        $script:cfg.apps[$i].enabled = $lstApps.Items[$i].Checked
    }
    $s = $script:cfg.settings
    $s.launchDcs = $chkDcs.Checked
    $s.dcsExe = $txtDcs.Text
    $s.autotune.enabled = $chkTune.Checked
    if ($cmbMode.SelectedItem) { $s.autotune.mode = [string]$cmbMode.SelectedItem }
    $s.dcsCountdown = [int]$numCd.Value
    $rules = New-Object System.Collections.ArrayList
    foreach ($line in $txtPop.Lines) {
        $ln = $line.Trim(); if (-not $ln) { continue }
        $en = $true
        if ($ln.StartsWith('#')) { $en = $false; $ln = $ln.TrimStart('#').Trim() }
        $parts = $ln -split '\|', 2
        if ($parts.Count -eq 2) { [void]$rules.Add(@{ titleMatch = $parts[0].Trim(); keys = $parts[1].Trim(); enabled = $en }) }
    }
    $s.popupRules = $rules
    $json = $script:cfg | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($script:cfgPath, $json)
}

# ---------------------------------------------------------------- events
# Only the checkbox toggles enable/disable; clicking the name just selects.
$lstApps.Add_ItemChecked({
    param($s, $e)
    if ($script:refreshing) { return }
    $script:cfg.apps[$e.Item.Index].enabled = $e.Item.Checked
})

$lstApps.Add_SelectedIndexChanged({
    if ($script:refreshing) { return }
    $i = Get-SelIdx
    if ($i -lt 0) { return }          # ignore the transient deselect
    if ($i -eq $script:curIdx) { return }
    if ($script:curIdx -ge 0 -and $script:curIdx -lt $script:cfg.apps.Count) { Save-Details $script:curIdx }
    $script:curIdx = $i
    Load-Details $i
})

# Live-sync the name into the list as you type.
$txtName.Add_TextChanged({
    if ($script:refreshing) { return }
    $i = $script:curIdx
    if ($i -lt 0 -or $i -ge $script:cfg.apps.Count -or $i -ge $lstApps.Items.Count) { return }
    $script:cfg.apps[$i].name = $txtName.Text
    $lstApps.Items[$i].Text = $txtName.Text
})

# Re-colour the row when the path changes (found vs not found).
$txtPath.Add_TextChanged({
    if ($script:refreshing) { return }
    $i = $script:curIdx
    if ($i -lt 0 -or $i -ge $script:cfg.apps.Count) { return }
    $script:cfg.apps[$i].path = $txtPath.Text
    Update-ItemStyle $i
})

$btnAdd.Add_Click({
    if ($script:curIdx -ge 0) { Save-Details $script:curIdx }
    $new = @{ name = 'New Program'; path = ''; proc = ''; enabled = $true; waitForUp = $false; delayAfter = 0; actions = (New-Object System.Collections.ArrayList) }
    [void]$script:cfg.apps.Add($new)
    $script:curIdx = -1
    Refresh-AppList
    Select-App ($script:cfg.apps.Count - 1)
    $txtName.Focus(); $txtName.SelectAll()
})

$btnRemove.Add_Click({
    $i = Get-SelIdx; if ($i -lt 0) { return }
    $nm = $script:cfg.apps[$i].name
    if ([System.Windows.Forms.MessageBox]::Show("Remove '$nm' from the list?", 'Remove', 'YesNo', 'Question') -ne 'Yes') { return }
    $script:cfg.apps.RemoveAt($i); $script:curIdx = -1; Refresh-AppList
    if ($lstApps.Items.Count -gt 0) { Select-App ([Math]::Min($i, $lstApps.Items.Count - 1)) } else { Load-Details -1 }
})

$btnUp.Add_Click({
    $i = Get-SelIdx; if ($i -le 0) { return }
    Save-Details $i
    $t = $script:cfg.apps[$i]; $script:cfg.apps[$i] = $script:cfg.apps[$i - 1]; $script:cfg.apps[$i - 1] = $t
    $script:curIdx = -1; Refresh-AppList; Select-App ($i - 1)
})

$btnDown.Add_Click({
    $i = Get-SelIdx; if ($i -lt 0 -or $i -ge $script:cfg.apps.Count - 1) { return }
    Save-Details $i
    $t = $script:cfg.apps[$i]; $script:cfg.apps[$i] = $script:cfg.apps[$i + 1]; $script:cfg.apps[$i + 1] = $t
    $script:curIdx = -1; Refresh-AppList; Select-App ($i + 1)
})

$btnDetect.Add_Click({
    $f.Cursor = 'WaitCursor'
    try {
        $found = Find-PfApps
        $added = 0
        foreach ($n in $found) {
            $dupe = $false
            foreach ($e in $script:cfg.apps) {
                if ($e.path -and ($e.path.ToLower() -eq ([string]$n.path).ToLower())) { $dupe = $true; break }
            }
            if ($dupe) { continue }
            [void]$script:cfg.apps.Add((ConvertTo-PfApp $n)); $added++
        }
        $script:curIdx = -1
        Refresh-AppList
        if ($lstApps.Items.Count -gt 0) { Select-App 0 }
        $lblStatus.Text = "Detected $($found.Count) installed - added $added new."
    } finally { $f.Cursor = 'Default' }
})

$btnBrowse.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'Programs (*.exe)|*.exe|All files (*.*)|*.*'
    if ($ofd.ShowDialog() -eq 'OK') {
        $txtPath.Text = $ofd.FileName
        if (-not $txtProc.Text) { $txtProc.Text = [System.IO.Path]::GetFileNameWithoutExtension($ofd.FileName) }
        if ($txtName.Text -eq 'New Program' -or -not $txtName.Text) { $txtName.Text = [System.IO.Path]::GetFileNameWithoutExtension($ofd.FileName) }
    }
})

$btnDcsBrowse.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'DCS.exe|DCS.exe|Programs (*.exe)|*.exe'
    if ($ofd.ShowDialog() -eq 'OK') { $txtDcs.Text = $ofd.FileName }
})

$btnRec.Add_Click({
    if ($script:curIdx -lt 0) { [void][System.Windows.Forms.MessageBox]::Show('Select a program first.'); return }
    $f.WindowState = 'Minimized'
    Start-Sleep -Milliseconds 350
    $r = Invoke-Recorder
    $f.WindowState = 'Normal'; $f.Activate()
    if (-not $r) { $lblStatus.Text = 'Record cancelled.'; return }
    $def = 'click'
    if ($r.title) { if ($r.title.Length -gt 40) { $def = $r.title.Substring(0, 40) } else { $def = $r.title } }
    $label = Show-Input 'Name this click (shows in the launch log):' 'Record Click' $def
    if (-not $label) { $label = $def }
    $res = [System.Windows.Forms.MessageBox]::Show("Only click when a specific window/popup is open?`n`nCaptured window:`n$($r.title)`n`nYes = only if that window is open (good for update popups)`nNo = always click here", 'Conditional click?', 'YesNo', 'Question')
    $ifw = ''; $to = 0
    if ($res -eq 'Yes') { $ifw = Show-Input 'Window title must CONTAIN:' 'Condition' $r.title; if ($ifw) { $to = 15 } }
    $act = @{ type = 'click'; x = [int]$r.x; y = [int]$r.y; label = $label; ifWindow = $ifw; timeout = $to }
    [void]$script:cfg.apps[$script:curIdx].actions.Add($act); Refresh-Actions
    $lblStatus.Text = "Captured click at $($r.x),$($r.y) - remember to Save."
})

$btnKeys.Add_Click({
    if ($script:curIdx -lt 0) { [void][System.Windows.Forms.MessageBox]::Show('Select a program first.'); return }
    $keys = Show-Input "Keys to send (SendKeys syntax). Examples:  {ENTER}   {ESC}   ^s   %{F4}" 'Add Key Press' '{ENTER}'
    if (-not $keys) { return }
    $ifw = Show-Input 'Optional - only send if a window title contains this (blank = always):' 'Condition' ''
    $to = 0; if ($ifw) { $to = 15 }
    $act = @{ type = 'sendkeys'; keys = $keys; ifWindow = $ifw; timeout = $to }
    [void]$script:cfg.apps[$script:curIdx].actions.Add($act); Refresh-Actions
})

$btnWait.Add_Click({
    if ($script:curIdx -lt 0) { [void][System.Windows.Forms.MessageBox]::Show('Select a program first.'); return }
    $s = Show-Input 'Seconds to wait before the next action:' 'Add Wait' '2'
    $sec = 0; [void][int]::TryParse($s, [ref]$sec); if ($sec -le 0) { return }
    $act = @{ type = 'wait'; seconds = $sec }
    [void]$script:cfg.apps[$script:curIdx].actions.Add($act); Refresh-Actions
})

$btnDelAct.Add_Click({
    if ($script:curIdx -lt 0) { return }
    $i = $lstActions.SelectedIndex; if ($i -lt 0) { return }
    $script:cfg.apps[$script:curIdx].actions.RemoveAt($i); Refresh-Actions
})

$btnSave.Add_Click({
    try { Save-AllAndWrite; $lblStatus.Text = 'Saved.' }
    catch { [void][System.Windows.Forms.MessageBox]::Show("Save failed:`n$($_.Exception.Message)") }
})

$btnLaunch.Add_Click({
    try {
        Save-AllAndWrite
        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$script:enginePath`""
        $lblStatus.Text = 'Pre-flight launching in a new window...'
    } catch { [void][System.Windows.Forms.MessageBox]::Show("Launch failed:`n$($_.Exception.Message)") }
})

$btnClose.Add_Click({ $f.Close() })

# ---------------------------------------------------------------- init view
$chkDcs.Checked  = [bool]$script:cfg.settings.launchDcs
$txtDcs.Text     = [string]$script:cfg.settings.dcsExe
$chkTune.Checked = [bool]$script:cfg.settings.autotune.enabled
$m = [string]$script:cfg.settings.autotune.mode; if (-not $m) { $m = 'Balanced' }
$cmbMode.SelectedItem = $m; if ($cmbMode.SelectedIndex -lt 0) { $cmbMode.SelectedIndex = 1 }
$cd = [int]$script:cfg.settings.dcsCountdown; if ($cd -lt 1) { $cd = 6 }; if ($cd -gt 60) { $cd = 60 }; $numCd.Value = $cd
$popLines = @()
foreach ($r in $script:cfg.settings.popupRules) {
    $prefix = ''; if (-not $r.enabled) { $prefix = '# ' }
    $popLines += ("{0}{1} | {2}" -f $prefix, $r.titleMatch, $r.keys)
}
$txtPop.Text = ($popLines -join "`r`n")

Refresh-AppList
if ($lstApps.Items.Count -gt 0) { Select-App 0 } else { Load-Details -1 }

[void]$f.ShowDialog()

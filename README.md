# DCS Pre-Flight Launcher

One click starts every program you use with DCS, sets them up, and then launches DCS.

No more opening SRS, then the kneeboard, then your HOTAS software, then the VR
streamer, clicking through each one, and finally starting the sim.

---

## What it does

1. Launches each of your companion programs **in order**, skipping any that are
   already running.
2. Runs any **post-launch clicks** you recorded (some apps need a click or two,
   and update popups love to get in the way).
3. Optionally applies a **DCS graphics profile** (via DCS-AutoTune, if you have it).
4. Launches **DCS** last, after a countdown you can cancel.

Anything it cannot find is skipped with a warning - it never hard-fails.

---

## Install

**Installer:** run `DCS-Preflight-Setup.exe` and follow the prompts.

**Portable:** unzip anywhere (a folder you can write to, e.g. Documents or your
Saved Games folder - not Program Files) and run `DCS-Preflight-Manager.bat`.

Requires Windows 10/11. Uses the built-in Windows PowerShell - nothing else to install.

On first run it **scans your PC** for known DCS companion apps (SRS, OpenKneeboard,
SimAppPro, Virtual Desktop, TrackIR, VoiceAttack, LotAtc, Tacview, Stream Deck,
SimShaker, Interhaptics/HF8, opentrack, and more) and builds your list automatically.
It also finds your DCS install on its own.

---

## Two ways to run it

| Shortcut | What it does |
|---|---|
| **DCS Pre-Flight Manager** | The control panel - edit your list, record clicks, then hit **LAUNCH PRE-FLIGHT** |
| **DCS Pre-Flight** | Straight launch, no window to click through. Use this day to day. |

---

## The Manager

### Programs list
- **Tick the box** to include a program in the launch. Clicking the *name* just
  selects it - only the checkbox turns it on or off.
- **Up / Down** sets the launch order.
- **Add** to browse to any `.exe`, **Remove** to drop one.
- **Detect Installed Programs** re-scans your PC and adds anything new it finds.
- A **grey** row means that program file no longer exists on this PC.

### Selected program
- **Name** - whatever you want to call it.
- **Program (.exe)** - the file to launch (**Browse** to pick it).
- **Process name** - used to skip launching if it is already running.
  Usually the exe name without `.exe`.
- **Wait until it is running** - hold the sequence until this app is up.
  Good for the VR streamer, which should be running before DCS starts.
- **Delay after** - pause a few seconds before the next program (for apps
  that need a moment to settle, like HOTAS software pushing LEDs).

### Post-launch actions
Some programs need a click after they open. Record it once:

1. Select the program.
2. Click **Record Click (F9)**. The Manager minimises and a small green tracker
   shows live **X / Y** and the **window under your cursor**.
3. Hover the button you would normally click and press **F9**. (Esc cancels.)
4. Give it a name, then choose whether it should be **conditional**:
   - **Yes** - only click when a window with that title is open. Use this for
     **update popups**, so it does nothing on days there is no update.
   - **No** - always click that spot.

You can also **Add Key Press** (e.g. `{ENTER}`, `{ESC}`) and **Add Wait**.
Actions run top to bottom.

> Record clicks with the app where it will actually be at launch - positions are
> absolute screen coordinates. If a window opens somewhere else next time, either
> re-record or make the click conditional on the window title.

### Pre-flight settings
- **Launch DCS at the end** + the path to `DCS.exe` (auto-detected; **Browse** to change).
- **Run AutoTune graphics profile** - only if you have DCS-AutoTune. Leave it off otherwise.
- **DCS launch countdown** - seconds you get to cancel before DCS starts.
- **Auto-dismiss popups** - one rule per line, `window title | keys`, for example:
  ```
  Update Available | {ESC}
  New version | {ESC}
  ```
  Start a line with `#` to disable it. These are checked between every step.

**Changes are saved when you press Save, or automatically when you press LAUNCH PRE-FLIGHT.**

---

## Command line

```
DCS-Preflight.ps1 -NoDCS                 # set up companions only
DCS-Preflight.ps1 -NoTune                # skip the graphics profile step
DCS-Preflight.ps1 -TuneMode Quality      # Performance | Balanced | Quality
```

---

## Where settings live

`apps.json`, next to the scripts. If you installed to a read-only location it
lives in `%LOCALAPPDATA%\DCS-Preflight\apps.json` instead. It is plain JSON -
back it up, or hand-edit it if you prefer.

---

## Troubleshooting

**A program did not start** - check the path in the Manager (grey row = file not
found). Apps that moved after a reinstall need re-pointing with **Browse**.

**It launched something that was already open** - set the **Process name** field.
Open Task Manager > Details to see the real process name.

**A recorded click missed** - the window opened in a different spot. Re-record it,
or make it conditional on the window title so it waits for the right window.

**DCS did not launch** - confirm the `DCS.exe` path in Pre-flight settings. The
tool prefers the multi-threaded `bin-mt\DCS.exe`.

**AutoTune warns that DCS is running** - DCS rewrites its options when it exits,
so the graphics profile can only be applied while DCS is closed. Close it and rerun.

---

## Notes

- Nothing is modified in your DCS install. The tool only launches programs and,
  if you enable AutoTune, writes the DCS options file that AutoTune manages.
- Clicks are replayed as real mouse input, so leave the machine alone for the few
  seconds the sequence runs.

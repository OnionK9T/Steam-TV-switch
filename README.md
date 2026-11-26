# Steam TV Switch

**One button: PC → TV, Steam Big Picture launches on the TV, audio follows. Another button: everything back.**

If your gaming PC is chained to a desk monitor but you actually play on the couch, this removes the last piece of friction — the part where you sit down, realize Big Picture opened on the wrong screen, and go back to the desk to fix display settings.

```
        ┌───────────────┐   DisplayPort   ┌───────────────┐
        │    Monitor    │◄───────────────►│      TV       │   HDMI
        │    (desk)     │                 │   (couch)     │
        └───────────────┘                 └───────────────┘
                 ▲                                ▲
                 └──────────── PC ────────────────┘
```

## Does this match your setup?

You will get value out of this if **all** of these are true:

- One PC, two displays: a monitor at the desk and a TV on HDMI.
- You want Steam Big Picture to open **on the TV**, not on the monitor.
- You want TV audio to become the default output automatically.
- You have a controller with a spare back button (or are fine pressing a keyboard key).
- You do not mind that only one screen is lit while you play.

If Steam Big Picture already opens on the right screen, you do not need this.

## What one press does

| Press | Display | Audio | Steam |
|---|---|---|---|
| **→ TV** | Monitor off, TV becomes the only screen | Switches to TV output | `steam://open/bigpicture` |
| **→ PC** | TV off, monitor becomes the only screen | Switches back to speakers | — |

Nothing is left in a half state: if the TV is off or unplugged, the script refuses to switch and says so, instead of leaving you with a black screen.

## Setup — about five minutes, once

### 1. Get the files

```powershell
git clone https://github.com/OnionK9T/Steam-TV-switch.git
cd Steam-TV-switch
```

No admin rights, no installer, no external tools. Everything is Windows built-ins plus two small C# interop files.

### 2. Run the configurator

Double-click **`setup.bat`**, or:

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup.ps1
```

It prints your display outputs and asks three questions:

```
=== displays ===
  1. SOME MONITOR                  DisplayPort  id=1234     active
  2. SOME TV                       HDMI         id=5678     inactive

哪一个是电视?输编号: 2
哪一个是电脑显示器?输编号: 1
电视用哪个音频?输编号: 2
桌面音箱是哪个?输编号: 5
```

It writes `settings.psd1` next to the script. That file holds your display IDs and audio device names, and it is git-ignored — it never leaves your machine.

### 3. Test it

```powershell
.\Toggle-SteamTV.ps1 -ForceTv
```

The monitor goes dark, the TV lights up, Steam Big Picture appears on it, audio moves to the TV. Then:

```powershell
.\Toggle-SteamTV.ps1 -ForcePc
```

Back to normal. If both work, the hard part is done.

You can also just double-click `toggle-tv.bat` / `toggle-pc.bat`.

### 4. Bind it to a controller button

The script listens to a **keyboard key**, so map your controller's back button to one. On a Flydigi Vader 4 Pro, for example, the Flydigi Space Station maps `M3 → Insert` and `M4 → PgUp` (it captures physical key presses, so only real keyboard keys work — injected keys are ignored).

Then run the listener once:

```powershell
.\Watch-Keys.ps1
```

It polls both keys every 40 ms with a 900 ms debounce and calls the toggle with `-ForceTv` or `-ForcePc`. It does **not** swallow the keys — their normal function stays intact.

Prefer double-clicking? Run `watch-keys.bat`.

### 5. Start it with Windows (optional)

Press `Win+R`, type `shell:startup`, and drop a shortcut to `watch-keys.bat` in there.

## Turning off Xbox Game Bar

If a controller's Guide/Home button also summons Xbox Game Bar, disable it once:

**Settings → Gaming → Xbox Game Bar → turn off "Open Xbox Game Bar using this button on a controller"**

Or by registry:

```powershell
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name UseNexusForGameBarEnabled -Value 0 -Type DWord
```

Also check Steam → Settings → Controller → turn off "Guide button focuses Steam", otherwise you get two overlapping triggers.

## If something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `电视没点亮` / "TV did not light up" | TV is off, asleep, or on another HDMI input | Turn the TV on and select the right input |
| Both screens stay on | `SetDisplayConfig` returned 87 | Re-run `Setup.ps1`; the display IDs changed after a cable swap |
| Big Picture opens on the monitor | TV and monitor IDs are swapped in `settings.psd1` | Re-run `Setup.ps1` |
| Audio does not move | TV audio device is gone (TV off, or HDMI audio disabled) | Turn the TV on first; check Sound settings |
| Script prints its own source code or fails to parse | File saved without a UTF-8 BOM | Re-save as "UTF-8 with BOM" (PowerShell 5.1 quirk) |
| Nothing happens on button press | Listener not running, or key not mapped | Run `watch-keys.bat`; check `key-hit.log` |

Diagnostics:

```powershell
.\Get-DisplayInfo.ps1     # current topology and output IDs
.\AudioSwitch.ps1 -List   # audio endpoints
.\Toggle-SteamTV.ps1 -DryRun   # show what it would do, change nothing
```

## How it works (the short version)

Steam Big Picture follows the **primary display** — there is no "open on display 2" option. So the only way to land it on the TV is to make the TV the primary display for the duration.

The naive approach is `DisplaySwitch.exe /external`. It does not mean "the HDMI one"; it means "the second display in enumeration order". If the TV happens to sort first, `/external` picks the monitor and the direction is reversed.

The reliable sequence is:

1. `DisplaySwitch.exe /extend` — light up the target so it has a valid mode path.
2. `SetDisplayConfig` — keep only the target output, drop the other.
3. Switch the default audio endpoint via `IPolicyConfig`.
4. Launch `steam://open/bigpicture`.

Step 1 is not optional: `SetDisplayConfig` returns `87` (`ERROR_INVALID_PARAMETER`) when the target has no active path. That is also why there is a brief flash of both screens during a switch — it is a structural cost of this approach, not a bug.

## Requirements

- Windows 10 or 11
- One HDMI and one DisplayPort output (other combinations work; set `-TvTech` / `-PcTech` accordingly)
- PowerShell 5.1 (built in)
- Steam
- Optional: a controller with a remappable button, and its vendor software

## Files

| File | Purpose |
|---|---|
| `Setup.ps1` / `setup.bat` | Detect displays, write `settings.psd1` |
| `Toggle-SteamTV.ps1` | The actual switch (`-ForceTv`, `-ForcePc`, `-DryRun`) |
| `Watch-Keys.ps1` / `watch-keys.bat` | Poll two keys, call the toggle |
| `AudioSwitch.ps1` | List / set the default audio endpoint |
| `Get-DisplayInfo.ps1` | Print current topology |
| `lib/DisplayConfig.cs` | `QueryDisplayConfig` / `SetDisplayConfig` interop |
| `lib/DispInfo.cs` | `EnumDisplayDevices` / `EnumDisplaySettings` interop |
| `toggle-tv.bat` / `toggle-pc.bat` | Double-click wrappers |

## Credits

Built with **DSH (DeepSeek Harness)** and **DeepSeek 4.1 Flash**. The architecture, the Win32 interop wrappers, and every trap along the way — error `87`, the UTF-8 BOM parsing bug, the misleading meaning of `DisplaySwitch /external` — were worked out in a single assisted session.

## License

MIT

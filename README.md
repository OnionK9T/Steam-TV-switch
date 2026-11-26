# steam-tv

One button to put **Steam Big Picture** on your TV, one button to come back —
with only one display powered at a time.

```
        press TV key                     press PC key
desktop ──────────► TV only + audio on TV ──────────► desktop only + audio back
        (Big Picture opens on the TV)
```

## The problem

Steam Big Picture always opens on the **primary display**, and Steam has no
setting for "open Big Picture on monitor 2". The only reliable way to get it
onto a TV is to make the TV the only active output, launch Big Picture, then
switch back when you are done.

Windows' built-in `DisplaySwitch.exe /external` looks like it solves this, but
"external" means *the second display in enumeration order*, not *the HDMI one*.
On a machine where the TV happens to be enumerated first,
`/external` picks the **other** output — the monitor — the exact opposite of what you want.

This repo does it properly, using `QueryDisplayConfig` / `SetDisplayConfig`
and the target id of each output.

## How it works

```
controller back button
        │  (mapped to a physical keyboard key by vendor software)
        ▼
  Watch-Keys.ps1          polls GetAsyncKeyState, 40 ms, debounced
        │
        ▼
  Toggle-SteamTV.ps1
        ├─ DisplaySwitch /extend   ← gives the target a valid mode path
        ├─ SetDisplayConfig        ← keeps only the chosen target; the other
        │                            output is really powered down
        ├─ AudioSwitch.ps1         ← moves the default audio endpoint
        └─ steam://open/bigpicture
```

Why `/extend` first: `SetDisplayConfig` returns **87 (ERROR_INVALID_PARAMETER)**
when you ask it to keep a target that currently has no active mode path. Lighting
both outputs for a moment gives the driver a path to work with. The visible cost
is a brief moment of two screens, then one.

Why not `ChangeDisplaySettingsEx` with a NULL `DEVMODE`: it does **not** disable
a display. It only resets that display's position back to its default, which
leaves the output on.

## Requirements

- Windows 10 / 11
- PowerShell 5.1 (built in) — no extra modules, no third-party executables
- Steam installed (Big Picture is opened through the `steam://` protocol)
- Two outputs: one for the desktop, one for the TV

## Quick start

**1. Inspect your displays**

```powershell
powershell -ExecutionPolicy Bypass -File .\Get-DisplayInfo.ps1
```

Look at the last two tables. You want, for each output, its `tech=` and `id=`:

```
0|SOME TV|tech=5|id=1234|inactive
1|SOME MONITOR|tech=10|id=5678|active
```

`tech` is the output technology (`5` = HDMI, `10` = DisplayPort, `4` = DVI,
`1` = VGA). If your TV and monitor use different technologies, the script
auto-detects them and you can skip the ids entirely.

**2. Test the switch**

```powershell
powershell -ExecutionPolicy Bypass -File .\Toggle-SteamTV.ps1 -ForceTv
powershell -ExecutionPolicy Bypass -File .\Toggle-SteamTV.ps1 -ForcePc
```

If auto-detection is ambiguous (two HDMI outputs, for example), pass the ids:

```powershell
.\Toggle-SteamTV.ps1 -ForceTv -TvTargetId 1234 -PcTargetId 5678
```

**3. Find your audio endpoint names**

```powershell
powershell -ExecutionPolicy Bypass -File .\AudioSwitch.ps1 -List
```

Pick the substring that identifies the TV output and the desktop speakers.

**4. Put it together**

```powershell
.\Toggle-SteamTV.ps1 -ForceTv -TvTargetId 1234 -PcTargetId 5678 `
    -TvAudio "TV HDMI Output" -PcAudio "Speakers"
```

**5. Bind your buttons**

Any of these works:

- Point the vendor software's macro / launch-program action at `toggle-tv.bat`
  and `toggle-pc.bat` (no extra process, cleanest).
- If the vendor software can only map buttons to keyboard keys, map one button
  to `Insert` and another to `Page Up`, then run `watch-keys.bat` (optionally at
  login). You can change the keys:

  ```powershell
  .\Watch-Keys.ps1 -VkTv 0x2D -VkPc 0x21
  ```

  `0x2D` = Insert, `0x21` = Page Up, `0x2E` = Delete, `0x22` = Page Down.
  Full list: [Virtual-Key Codes](https://learn.microsoft.com/windows/win32/inputdev/virtual-key-codes).

## Auto-start

Put a shortcut to `watch-keys.bat` (or to `toggle-tv.bat` if you use the
launch-program route) in:

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
```

`watch-keys.bat` runs a `powershell` window; to keep it invisible, start it with
a shortcut whose *Run* setting is **Minimized**, or run it through Task Scheduler
with "Run whether user is logged on or not" disabled and "Hidden" checked.

## Turning off Xbox Game Bar

If pressing the controller's Guide/Home button also opens Xbox Game Bar:

`Settings → Gaming → Xbox Game Bar → turn off "Open Xbox Game Bar using this button on a controller"`

Registry equivalent:

```
HKCU\Software\Microsoft\GameBar
    UseNexusForGameBarEnabled = 0   (DWORD)
```

Also check Steam: `Settings → Controller → Guide button focuses Steam` should be
**off**, otherwise both the Game Bar and Steam react to the same press.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `set=87` | Target is not active. The script already calls `DisplaySwitch /extend` first — if you still get 87, the TV is off, on the wrong input, or unplugged. |
| Switch happens, but Big Picture opens on the monitor | Wrong target id. Re-run `Get-DisplayInfo.ps1`; ids can change when you move cables or ports. |
| Nothing happens when pressing the controller button | Vendor software did not capture the key. Check that the mapped key is a **physical** key on your keyboard — software-injected keys have no scan code and are invisible to it. |
| A key press also types/deletes text | The watcher does not block keys. If the mapped key is one you use, pick a less-used one, or use the launch-program route instead. |
| Audio did not follow | Endpoint name mismatch. Run `AudioSwitch.ps1 -List` and use a substring of the exact name. The TV endpoint also disappears from the list when the TV is off. |
| Screen flashes two displays before settling | Expected: `/extend` has to light the target before it can be isolated. |
| Desktop icons move around | Windows re-lays out the desktop when the topology changes. Not avoidable through these APIs. |

## Known limitations

- The dual-then-single switch always flashes the second output briefly.
- DisplayConfig target ids are stable per connector, not across cable/port moves.
- The audio endpoint of a TV only exists while the TV is actually linked; that is
  why the switch is ordered "display first, audio second".
- Physical keys used for mapping keep their normal function (the watcher only
  reads state), but they will also trigger the switch.

## Credits

Built with **DSH (DeepSeek Harness)** and **DeepSeek 4.1 Flash**. The architecture,
the Win32 interop wrappers, and every trap along the way — error `87`, the UTF-8
BOM parsing bug, the misleading meaning of `DisplaySwitch /external` — were worked
out in a single assisted session.

## License

MIT — see [LICENSE](LICENSE).

中文说明见 [README.zh-CN.md](README.zh-CN.md)。

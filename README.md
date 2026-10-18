# DBFR-Script · CHAMBER / Saiyan Control

A separate Lua/Luau edition of the DBFR Chamber training helper, built for a Roblox
script executor. The interface uses an orange and gold Dragon Ball theme, seven
Dragon Balls, a blue HTC countdown, a training dashboard, calibration, settings,
and an activity log. All application, build, and test source is Lua.

**Status:** implemented and tested offline with Roblox API doubles. This has not
been run inside the DBFR game or your executor. Image-only prompts need calibration
unless their names already identify their button. The game-specific bindings and
live input acceptance still need an initial in-game check.

## Run

1. **Sign into GitHub**, open **[`dist/chamber.lua`](dist/chamber.lua)**, and use
   **Copy raw file** to copy its complete contents. Paste the actual Lua code into
   your executor and execute it. This works with a private repository. The single
   file contains the whole app; no downloaded UI library or Python is needed.
2. Open **Calibration**. Start, Respawn, Reconnect, and the bottom-right timer are
   found by visible text when possible. Bind unidentified controls as described below.
3. Press **POWER UP** or **F6**. The window collapses to a small badge, leaving the
   game controls clear. Clicking the badge pauses automation and opens the panel.

| Control | Action |
| --- | --- |
| F6 | Run / pause |
| F7 | Unload and release held inputs |
| Right Shift | Show / hide; opening the panel pauses training |
| Header dash | Collapse to the badge |
| Header × | Unload |

Start with the game at its training hub. Automation starts paused on each fresh
execution. Re-executing the script unloads the previous instance first.

**Private repository:** GitHub currently marks `Zitely/DBFR-Script` as private.
Your executor does not inherit your browser's GitHub sign-in, so the HTTP launcher
receives `404: Not Found`. Use the direct-copy instructions above. An authenticated
cloud workspace downloading the file successfully does not prove an executor can
download it. The full bundle starts without HTTP or `loadstring`.

The optional [`loader.lua`](loader.lua) requires a publicly readable repository URL.
If the repository is deliberately made public later, it downloads the bundle from
[`Zitely/DBFR-Script`](https://github.com/Zitely/DBFR-Script) and caches a copy for
optional teleport reload. Paste its **complete contents** into your executor to
get separate download, compilation, and startup errors. The short launcher below
also checks the functions that the previous one-line launcher called blindly:

```lua
local compile = loadstring
assert(type(compile) == "function",
    "loadstring is unavailable. Paste the complete dist/chamber.lua file instead.")
local ok, source = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/Zitely/DBFR-Script/main/loader.lua")
end)
assert(ok, "Loader download failed: " .. tostring(source))
assert(type(source) == "string" and not source:match("^%s*404"),
    "GitHub returned 404. Sign into GitHub and copy the complete dist/chamber.lua file instead.")
local run, reason = compile(source, "Chamber launcher")
assert(type(run) == "function", "Loader compilation failed: " .. tostring(reason))
run()
```

The loader requires a publicly readable raw URL and executor HTTP support. If
either is unavailable, paste the complete `dist/chamber.lua` file instead.

### `Expected identifier ... got '404'`

The downloaded text was a GitHub error response, not the Lua script. A private
repository returns 404 to requests without GitHub authentication; missing files
and incorrect URLs can also return it. Sign into GitHub and copy the complete
[`dist/chamber.lua`](dist/chamber.lua) source directly into the executor. The
updated loader recognizes 404 and HTML responses before attempting compilation.

### `:1: attempt to call a nil value`

The old one-line launcher could produce this if `loadstring` was missing, or if
compilation returned no function. The line number alone does not identify which
call failed. Use the checked launcher above or paste the full bundle directly;
the full bundle needs neither HTTP nor `loadstring` to start. If it still fails,
share the full error and executor name. Ordinary Roblox LocalScripts do not
provide the executor capabilities this application uses.

## Calibration

Click **BIND**, then hover the matching **game** control. After three seconds the
app captures the UI object under the cursor and reopens its panel. It does not
click the game during calibration. Use RESET to return a binding to automatic
detection. Settings and bindings save to `DBFR_Lua/settings.json` in the executor's
workspace when its file functions are available.

- Bind the **left mouse, right mouse, Q, and E prompts** if their icons use unnamed
  images. A binding matches the image and sprite rectangle, or the exact label
  text, across new copies of that prompt. Choose the actual icon or label.
- Bind **both hit rings** for continuous training presence between notes.
- Bind the **lines menu**, its **Respawn entry**, and the **confirmation button**
  separately. Open each menu yourself while paused to expose its control.
- Bind the **HTC timer** to its numeric `H:MM:SS` text label. Bind challenge numbers
  to their numeric labels if automatic lane detection misses them.
- Start and Reconnect support explicit bindings if their labels differ.

Controls resolve again when the game recreates its UI. Ambiguous paths with
identically named siblings are rejected. Prompt images use signatures rather
than paths because individual notes are frequently destroyed and recreated.

The automatic layout uses the original 1280×720 reference, scaled to Roblox's
viewport. Both rhythm lanes and the bottom-right timer retain that layout.
This in-client edition follows the Roblox window; it has no desktop monitor
selection. Non-16:9 layouts and significantly different game HUDs need additional
layout adaptation. Binding targets changes their hit position but does not move
the automatic lane search regions.

## Automation

- **Rhythm:** measures moving GUI prompts, predicts their arrival at a hit ring,
  and sends left/right mouse or Q/E input. Default offset: −40 ms; hold: 38 ms.
  Stationary icons and single observations do not trigger presses.
- **25-press challenge:** remembers the nearest identified prompt, locks that
  button, and pulses until the numeric counter reaches zero on three observations
  or disappears on four. `10` and `20` are not zero. Defaults are 20 ms held and
  20 ms released, with a cap of 125 attempts. Roblox's frame scheduling and the
  executor affect the actual rate; an attempt does not prove the game counted it.
- **Recovery:** pauses after two seconds without training UI, becomes eligible
  after eight seconds, then clicks **lines menu → Respawn → confirmation**. It
  waits at least eight seconds, requires a living character and three ready
  samples, and sends a fresh Start before accepting training again. A Start button
  that remains visible during respawn cannot skip the wait.
- **HTC timer:** verifies two plausible readings, extrapolates between reads, and
  enters AFK at 35 minutes remaining by default. Set the threshold to 0 to disable
  that behavior. A missing timer remains unknown; there is no guessed session
  duration. Once verified, the countdown survives a normal respawn.
- **Reconnect:** checks throughout active training, startup, recovery, and AFK,
  every two seconds. Two observations confirm the button. It approaches smoothly,
  hovers, and clicks, with three attempts and a nine-second cooldown measured
  after each click. After the hub returns, it waits seven seconds and starts
  training again. Retry counts reset for future disconnects. A real Reconnect
  attempt clears the old HTC reading; the new hub reading survives training startup.
- **Pause / preview:** F6 pauses all automatic actions. Preview mode detects UI
  without dispatching input. Errors stop automation and appear in Activity.

The timing, recovery, reconnect, and AFK values are editable in Settings. Settings
changes pause automation so an in-flight action cannot silently switch behavior.
There is no anti-idle input: reaching the AFK threshold intentionally stops input
and waits for the game to display Reconnect.

## Executor compatibility and reconnect limits

The adapter uses executor mouse/key functions when present and otherwise tries
`VirtualInputManager`. Access restrictions stop the action with a visible error;
the app does not treat sending an event as proof of success. Reconnect scanning
needs access to its GUI, usually in CoreGui. An access failure is logged.

Disconnecting may destroy the entire Lua session. No running script can keep
clicking after its executor has stopped it. Optional **Reload after teleport**
uses the executor's `queue_on_teleport` capability and a cached copy of the bundle.
It depends on that executor reattaching; a disconnect/rejoin may not emit the
same queue event as a normal teleport. Automatic re-execution cannot be verified
offline and is not available in every executor.

To enable reload without a public loader, place the bundle at
`DBFR_Lua/chamber.lua` in the executor workspace. Enable the setting, then press
POWER UP. The queued startup checks the saved run/reload settings, so pausing or
unloading cancels automatic resume. Without queue/file support, load the script
again after reconnecting. Each new instance continues using the saved bindings.

This project reads exposed GUI objects. It does not include a screenshot/OCR
engine for text drawn entirely inside images, nor does it invent game remote
names. If the timer or countdown uses image glyphs rather than numeric text,
that game-specific adapter still needs implementing from a GUI sample.

## Development

The original Python repository is a separate project. This checkout contains:

| File | Purpose |
| --- | --- |
| `src/Engine.lua` | Training, recovery, AFK, and reconnect state machine |
| `src/Rhythm.lua` | Note motion, input timing, and spam lifecycle |
| `src/Bindings.lua` | Visible GUI discovery and saved calibration |
| `src/Input.lua` | Smooth movement and cancellable input with release handling |
| `src/UI.lua` | Native Roblox Dragon Ball dashboard |
| `src/Main.lua` | Lifecycle, settings, hotkeys, and optional teleport reload |
| `src/Timer.lua`, `src/Config.lua` | Countdown verification and validated defaults |
| `dist/chamber.lua` | Self-contained executor bundle |

From the repository root, with Lua 5.1+ or LuaJIT installed:

```sh
lua tools/build.lua
lua tests/run.lua
```

The tests cover repeated reconnects, timer retention through more than three
minutes of subsequent training, post-respawn Start gating, early and sustained
spam, exact counter completion, button movement/cancellation/release, calibration,
GUI visibility, dashboard actions, and unloading duplicate instances. The tests
use deterministic Roblox doubles; they do not render Roblox or verify executor
permissions or in-game timing.

The source uses the Lua 5.1-compatible subset of Luau. The shipped app uses Roblox
services and therefore runs in Roblox, not in the desktop Lua interpreter used
for the offline tests.

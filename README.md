# DBFR-Script · Saiyan Hub

A Lua/Luau Chamber training helper for a Roblox script executor, with a compact
orange and gold Dragon Ball themed hub. **Version 1.5.1 includes manual HTC entry
with a cooldown-fee option in Travel.** Movement, Combat, Visuals, QOL, and Travel
tabs sit alongside the existing Chamber toggle. Right Shift
shows or hides the hub; the top-right controls minimize or exit. Detection is
automatic. It now reads DBFR's live note lanes, linked double notes, and mash
counters using the game controller and Minigame module supplied by the user.

## Run

1. Paste this into your executor and run it:

   ```lua
   loadstring(game:HttpGet("https://raw.githubusercontent.com/Zitely/DBFR-Script/main/http_loader.lua"))()
   ```

   It downloads the current Chamber build from `main` every time you execute it.
2. At the game's training hub, click **CHAMBER AUTO TRAIN** to turn automation on.
   Click the same button again to stop. Drag the header to move the panel.

| Window control | Action |
| --- | --- |
| Right Shift | Hide the hub or bring it back expanded; ignored while typing in a text box |
| Top-right − / + | Minimize to the header / restore the feature rows |
| Top-right × | Stop automation, release inputs, and completely unload the hub |

Hiding or minimizing keeps Chamber running if it is on. Use its feature toggle
to pause, or × to exit. Execute the full script again to reopen after exiting.

The panel displays its version, current action, and bottom-right HTC timer. Fresh execution
starts with Chamber off. Running the script again unloads its previous instance,
releases held inputs, and disconnects the old loop before creating the new panel.
Turning Chamber on during an existing minigame adopts it after three observations
of the game's active training state. It moves the pointer away from the hub before
sending inputs. Recovery waits for a fresh Start after respawn and uses the game's
health, cooldown, resting, and exact death-screen state instead of treating a
visible Start as ready. When Chamber is turned on in the HTC, it checks the
player's `Difficulty` attribute and selects **Nightmare** through the game's
`DifficultySet` remote only when Nightmare is not already selected. It rechecks
after a respawn.

## Optional hub tools

All additional toggles start **off**, including Anti-AFK. Slider preferences are
saved locally when executor storage is available; feature toggles are not resumed
automatically. Adjust FOV to apply an override; **Restore Game FOV** removes it.

| Tab | Tools |
| --- | --- |
| Movement | Speed boost and walk speed, infinite jump, noclip, Saiyan flight and flight speed |
| Combat | Fast punch, Ki blasts, block/parry, face nearest living player, transformation, one-second Ki recharge |
| Visuals | Player ESP, NPC ESP, fullbright, clear sky/fog removal, FOV and FOV restoration |
| QOL | Auto Meditate, Ki charge, Dragon Ball radar with distance and notifications, data save every 30 seconds, Anti-AFK, reduced screen shake |
| Travel | Manual HTC entry/cooldown fee, Earth spawn, West City, Satan City, Ginger Town, Nam's Village, Mr. Popo, Kame House, Gravity Chamber, training dummies |

Flight uses WASD, E/Space to ascend, and Q to descend. These are movement inputs;
the added features have no keyboard toggle shortcuts. Flight stops moving while
typing. Travel uses live NPC positions where available, with the uploaded script's
coordinates as fallbacks. It moves the character only when clicked.

**The uploaded Auto HTC, overnight/quick-cycle engine, and automatic re-entry
loop are not imported.** The
original Chamber Start, solver, health reset, readiness checks, and 30-minute /
20-minute overnight cycle remain in use. Movement, combat, charging, manual
meditation, camera overrides, and Anti-AFK pause while Chamber runs. Manual travel
and recharge also require Chamber and Auto Meditate to be off. Nonconflicting
visuals and data saving can remain enabled.

**Travel → Enter HTC · bypass costs 60,000 Zeni** is a manual action:

- Reads the game's `TimeCheck:InvokeServer(2)`. With zero cooldown, it requests a
  teleport to HTC (`4178935231`) without paying a re-entry fee.
- With an active cooldown and at least 60,000 Zeni in `Data.Moneys`, it requests
  `NPCStuff:FireServer("GravityChamberReEnterFee")`, then `GetQuest:FireServer(70)`,
  waits 0.2 seconds, and requests the teleport. This spends in-game currency;
  it does not remove the fee or guarantee the server will accept re-entry.
- Missing controls, an unreadable cooldown, or insufficient funds stop the action
  with a reason. The button does nothing if already inside HTC.
- Only one request can run at a time. Repeated clicks while teleporting wait ten
  seconds; a reported teleport failure allows another manual attempt. Once a fee
  is requested, retries in the same hub instance do not request it again, even
  if the first call failed. Reloading the script creates a new instance.
- Closing the hub, starting Chamber/Auto Meditate, or losing the current living
  character cancels remaining work before teleport is sent. A payment already
  requested cannot be undone by cancellation.
- When the executor supports a teleport queue, the public hub loader is queued
  once. It opens with Chamber off; it does not start a new training/overnight loop.
  Otherwise, run your usual loader after joining. No retries happen automatically.

The upload's **Auto Meditate** equips owned weights and solves a manually started
minigame; it does not initiate meditation. Here it uses the existing DBFR lane
reader and rhythm solver, requests an already-owned weight if its tool is missing,
and equips the strongest available tool. It never starts training, selects
difficulty, resets the character, or operates an HTC timer. It pauses conflicting
combat/movement tools while enabled.

Remote-based tools use the names and arguments from the uploaded script. Missing
or incompatible remotes display an **Unavailable** reason beneath the control.
Sending a request cannot guarantee the server accepts it: Recharge Ki does not
promise an instant maximum, and block/parry uses the game's blocking operation.
Reduce Screen Shake preserves Roblox's normal camera update and removes later
render-step offsets; it does not suppress every possible camera effect or alter
scripted cameras/cutscenes.

Switching off or exiting restores properties still owned by the effect and removes
only this hub's highlights, flight movers, and connections. Player ESP refreshes
once per second and follows respawns. NPC/radar discovery is limited to named
world folders, processes at most 64 work items per update, and caps each marker
set at 128. New balls notify once per object while radar is enabled. No world-wide
scan runs every frame. Live Roblox/executor compatibility remains to be tested.

`loader.lua` and `dist/chamber.lua` are identical, self-contained programs. Their
first line is:

```lua
-- CHAMBER FULL SCRIPT - no download needed.
```

They need no HTTP request, `loadstring`, Python, or downloaded UI library to start.
[`http_loader.lua`](http_loader.lua) is the public one-line updater above. It
downloads `dist/chamber.lua`, validates the response before compiling it, and
caches the complete bundle in the executor workspace when file APIs are available.

If you see `Chamber download failed`, `404`, or an error from the old one-line
launcher, replace that launcher with the complete `loader.lua` above. For an error
from the complete file, retain the full error text and executor name.

## Performance

The previous version inspected every GUI object every frame, including while
paused, and repeatedly rebuilt its object list. This version:

- Does no discovery or automation work with all tools off. Chamber disconnects
  its GUI observers when turned off; Auto Meditate can independently use the same
  scanner while enabled. Optional tools share the single heartbeat scheduler.
- Builds an index incrementally, then follows GUI addition, removal, text, image,
  name, and attribute events. Newly appearing prompts take priority over the
  initial inventory of existing UI.
- Budgets discovery to at most 96 work items per tick, with a 0.8 ms soft time
  budget checked between items. A single Roblox API call can exceed that budget.
- Samples cached prompt positions at up to 60 Hz; checks cached controls about
  every 150 ms and refreshes status text every 400 ms. It skips unchanged UI values.
- Observes direct children of the two known note lanes separately, so live notes
  do not wait behind an inventory discovery backlog. Each lane's children are read
  once when it is attached or replaced; subsequent additions/removals use events.

In an offline fixture containing 3,000 unrelated labels, 120 paused frames went
from over 5 million GUI type checks to zero. During 120 active frames after
initial discovery, the new scanner made 1,201 type checks and 120 candidate reads,
with no full-tree enumeration. These are mock operation counts, not measured
Roblox FPS. **Live performance and executor input acceptance still need an
in-game check.**

## Automatic detection

For the supplied DBFR HUD, training state comes from `Main.Active` and
`Main.Frame.Visible`. Start is `Main["Button Thing"].Start.TextButton`; it waits for
health above 2, `Main.UICoolDown` false, and
`Characters.Interactions.Resting` false. These values are read, never rewritten.

The supplied `PlayerScripts.RespawnLocal` script creates
`PlayerGui.RespawnUI.RespawnCanvas` whenever the Humanoid dies. Chamber checks the
live Humanoid every 50 ms and, when health is above zero and at or below 2, sets
health to zero and calls `BreakJoints()`. Once the game clones that canvas,
Chamber stops further recovery input and waits
for it to disappear and for the new character to have `AttackCheck` before
collecting three fresh, start-ready samples.

Only direct children of `Main.Frame.Attack` and `Block` are live notes. Their names
identify MouseButton1/MouseButton2 or Q/E; `NC` means consumed. The reader uses
`Position.X.Scale`, so note timing does not depend on screen resolution. Double
notes reference their partner through `Obj.Value`. A top-level `mash` note names
its input in the `Key` attribute and uses `CounterA` or `CounterB`; nested visual
copies and the templates under `Frame.Keys` are ignored.

Reconnect and HTC timer use visible text and layout. The native menu route remains
available as a fallback for a disappeared training UI. Older HUDs retain the generic
label/name/attribute and learned-image fallback.
There is no binding page or calibration step.

### Capture an unrecognized minigame

If the status says `Chamber prompts were not recognized automatically`, use the
optional **[`dist/capture_minigame.lua`](dist/capture_minigame.lua)** to collect the
actual game UI details. This is a separate read-only diagnostic, not the autoplay
program. Copy the entire file while signed into GitHub and run it in the executor.

1. Turn Chamber **OFF** and execute the capture script.
2. During its **30-second recording**, manually press Start and play a round.
   Also open the lines menu and Respawn dialog to expose their controls.
3. When the console says `[Chamber Capture] Done`, share
   **`DBFR_Lua/minigame_capture.json`** from your executor's workspace. If clipboard
   access is available, the same report is copied there. Without file or clipboard
   support, the report prints in the console and is available as
   `getgenv().__DBFR_CAPTURE_RESULT`.

The report records incoming `ReplicatedStorage.Minigame.OnClientEvent` arguments,
their times, and GUI paths, labels, image assets, attributes, and positions under
the `Main`, `MainFrame`, `Menu`, and `Timer` roots shown in Dark Dex. It does not
send inputs, fire remotes, replay signals, or hook game methods. Discovery is
spread across frames; collection is capped and any truncation is recorded.
All listeners disconnect when recording ends or the capture is rerun. If needed,
`getgenv().__DBFR_CAPTURE.stop()` ends recording early and exports the report.

The supplied Minigame module establishes that each incoming pair is `{type, gap}`:
1 = attack, 2 = block, 3 = linked double, 4 = attack mash, 5 = block mash. Thus
`{2, 0.3}` schedules a block-lane note with a 0.3-second gap. Actual keys are chosen
randomly on the client, and harder difficulties add more notes. Autoplay therefore
reads the spawned GUI notes; it does not replay events or send fabricated results.

The scanner cannot infer Q/E/left/right from an opaque image with no identifying
metadata or known signature. Such a HUD needs a game-specific compatibility
update; removing calibration does not give the script image recognition. It
also cannot read timer or counter digits drawn entirely inside images. Unknown
prompts are not assigned arbitrary inputs.

The fallback layout and timer/menu detection use the original 1280×720 reference
scaled to the viewport. Non-16:9 layouts or changed menus may need adaptation;
the known note lanes use their own normalized positions. The Lua version follows
the Roblox window and has no desktop monitor selection.

## Automation

- **Rhythm:** presses the rightmost live note in each lane inside the game's
  normalized hit window (above 0.8, below 1.2). The default target is 0.96 with a
  38 ms hold; legacy timing adjustments are bounded to stay inside that window.
  Linked doubles send both captured keys together, within the game's 0.2-second
  second-input deadline. Older HUDs retain motion prediction. These are game
  inputs, not keyboard shortcuts for the hub.
- **25-press challenge:** starts on the first visible counter using the mash note's
  actual key, and continues tracking that note beyond the normal hit window until
  the counter reaches zero on three observations or disappears on four. Defaults
  are 20 ms held and 20 ms released, with a cap of 125 attempts. Frame scheduling
  and the executor affect the actual rate; sending a press does not prove the
  game counted it. Consecutive mash notes are distinguished by object identity.
- **Recovery:** checks health every 50 ms, including during training, and directly
  resets a living character at health at or below 2. Once the game produces its source-confirmed RespawnUI canvas,
  it waits for that canvas to go away, then requires three ready samples with
  health above 2, cleared cooldown, and no resting before it sends a fresh Start.
- **Nightmare and weights:** before every Start, Chamber verifies Nightmare is
  selected, then equips the strongest available **Heavy**, **Medium**, or **Light
  Weights** tool. It does not start the round if Nightmare cannot be selected.
- **HTC timer:** verifies two plausible readings and extrapolates between reads.
  At **30 minutes remaining** by default, it stops all input for **20 minutes**.
  Unknown timers are not given a guessed duration. A verified countdown survives
  normal respawn.
- **Overnight reconnect:** after that AFK interval, it resumes looking for the
  Reconnect button, confirms two observations, approaches smoothly, hovers, and
  clicks. It allows three attempts with a nine-second cooldown after
  each click, waits seven seconds after the hub returns, and starts again. Retry
  counts reset for later disconnects. Reconnecting clears the old session timer.
- **Off:** cancels pending actions, releases inputs, and stops discovery. Errors
  stop Chamber and display a reason below its toggle. Additional details appear
  in the executor console.

Defaults live in `src/Config.lua`; previous configuration remains readable from
`DBFR_Lua/settings.json` when executor file functions are available. There is no
settings page. AFK intentionally stops input for the full configured interval
before it acts on Reconnect.

## Executor compatibility

Input uses executor mouse/key functions when available, otherwise
`VirtualInputManager`. Restricted access can prevent those actions. Reconnect
detection needs access to its GUI, usually in CoreGui. Ordinary Roblox
LocalScripts do not provide all executor capabilities used by this application.

A disconnect can destroy the Lua session. To reload automatically when supported,
place the full bundle at `DBFR_Lua/chamber.lua` in the executor workspace and set
`config.resumeAfterTeleport` to `true` in `DBFR_Lua/settings.json` before executing
the script. Turning Chamber on then registers the executor's teleport queue.
Pausing or unloading cancels the saved resume request. Queue, file, compiler,
and executor reattachment support are required; a disconnect/rejoin may not
trigger the same queue event as a normal teleport. Otherwise, execute the full
script again after rejoining.

## Development

All application, build, and test source is Lua. The original Python application
is a separate repository.

| File | Purpose |
| --- | --- |
| `src/Engine.lua` | Training, recovery, AFK, and reconnect state machine |
| `src/Rhythm.lua` | Note motion, input timing, and spam lifecycle |
| `src/GuiIndex.lua` | Bounded discovery and GUI event subscriptions |
| `src/Bindings.lua` | Automatic recognition and cached candidate sampling |
| `src/GameState.lua`, `src/GameNotes.lua` | Exact DBFR state gates and live note/counter reader |
| `src/Input.lua` | Smooth movement, cancellation, and input release |
| `src/UI.lua` | Dragon Ball tabs, scrolling controls, and independent Chamber status |
| `src/FeatureCatalog.lua`, `src/Features.lua` | Optional feature controls, scheduling, remote actions, and conflict handling |
| `src/HTCEntry.lua` | Manual HTC cooldown/fee request, cancellable entry, and optional hub reload |
| `src/HubEffects.lua`, `src/EffectScope.lua` | Movement/visual effects with reversible property and connection ownership |
| `src/WorldMarkers.lua` | Bounded NPC/radar discovery and owned marker cleanup |
| `src/Main.lua` | Chamber lifecycle, saved configuration, optional teleport reload |
| `src/Capture.lua`, `dist/capture_minigame.lua` | Optional read-only diagnostic and its standalone bundle |
| `src/Timer.lua`, `src/Config.lua` | Countdown verification and validated defaults |
| `loader.lua`, `dist/chamber.lua` | Identical generated executor bundles |
| `http_loader.lua` | Optional downloader for publicly readable repositories |

From the repository root, with Lua 5.1+ or LuaJIT:

```sh
lua tools/build.lua
lua tests/run.lua
```

For a future feature, `ui:addFeature(id, title, onToggle)` adds its own button and
status labels. Keep the feature's state, input handling, and cleanup independent
of Chamber; adding a row does not start another scanning loop. Chamber currently
registers one row in `Main.lua`. No keyboard binding is needed.

The offline suite covers exact note names and normalized timing across
difficulty speeds, linked doubles, 25 accepted mash inputs at 30/60 Hz, lane
replacement, source-confirmed RespawnUI handling, recovery order, post-respawn Start gating, repeated
reconnects, timer retention, sustained spam, cancellation and release, automatic
recognition, event-driven discovery, pause/unload cleanup, and large GUI fixtures.
Hub tests cover remote cadences, yielding block cancellation, feature conflicts,
restoration on character/camera replacement, marker discovery, notifications,
manual travel, shared meditation solving, and Anti-AFK suspension during overnight idle.
Manual HTC tests cover free entry, fee ordering, insufficient funds, invalid cooldowns,
duplicate requests, failed teleport retries, cancellation, and reload without automation.
It uses deterministic Roblox API doubles and does not render Roblox or validate
live executor permissions. The source uses the Lua 5.1-compatible subset of Luau;
the shipped application runs inside Roblox.

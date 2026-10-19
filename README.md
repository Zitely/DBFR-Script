# DBFR-Script · Saiyan Hub

A Lua/Luau Chamber training helper for a Roblox script executor, with a compact
orange and gold Dragon Ball themed hub. **Version 1.2.2 has one Chamber toggle,
a Right Shift visibility shortcut, and top-right minimize and exit buttons.**
The hub supports additional feature rows as the project grows. Detection is
automatic. It now reads DBFR's live note lanes, linked double notes, and mash
counters using the game controller and Minigame module supplied by the user.

## Run

1. Sign into GitHub, open **[`loader.lua`](loader.lua)**, and choose **Copy raw file**.
2. Replace the **entire contents** of your executor tab with that code and execute it.
3. At the game's training hub, click **CHAMBER AUTO TRAIN** to turn automation on.
   Click the same button again to stop. Drag the header to move the panel.

| Window control | Action |
| --- | --- |
| Right Shift | Hide the hub or bring it back expanded; ignored while typing in a text box |
| Top-right − / + | Minimize to the header / restore the feature rows |
| Top-right × | Stop automation, release inputs, and completely unload the hub |

Hiding or minimizing keeps Chamber running if it is on. Use its feature toggle
to pause, or × to exit. Execute the full script again to reopen after exiting.

The panel displays the current action and bottom-right HTC timer. Fresh execution
starts with Chamber off. Running the script again unloads its previous instance,
releases held inputs, and disconnects the old loop before creating the new panel.
Turning Chamber on during an existing minigame adopts it after three observations
of the game's active training state. It moves the pointer away from the hub before
sending inputs. Recovery waits for a fresh Start after respawn and uses the game's
health, cooldown, resting, and exact death-screen state instead of treating a
visible Start as ready.

`loader.lua` and `dist/chamber.lua` are identical, self-contained programs. Their
first line is:

```lua
-- CHAMBER FULL SCRIPT - no download needed.
```

They need no HTTP request, `loadstring`, Python, or downloaded UI library to start.
The repository is private: an executor cannot use your browser's GitHub sign-in.
The optional [`http_loader.lua`](http_loader.lua) is for publicly readable
repositories only; it cannot download this private repository unauthenticated.

If you see `Chamber download failed`, `404`, or an error from the old one-line
launcher, replace that launcher with the complete `loader.lua` above. For an error
from the complete file, retain the full error text and executor name.

## Performance

The previous version inspected every GUI object every frame, including while
paused, and repeatedly rebuilt its object list. This version:

- Does no discovery or automation work while Chamber is off, and disconnects its
  GUI observers when turned off.
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
`PlayerGui.RespawnUI.RespawnCanvas` whenever the Humanoid dies. Chamber requests
the manual lines menu → Respawn route as soon as the training health gate is hit.
Once the game clones that canvas, Chamber stops further recovery clicks and waits
for it to disappear before collecting three fresh, start-ready samples. The game
removes it only after the new character has its `AttackCheck`.

Only direct children of `Main.Frame.Attack` and `Block` are live notes. Their names
identify MouseButton1/MouseButton2 or Q/E; `NC` means consumed. The reader uses
`Position.X.Scale`, so note timing does not depend on screen resolution. Double
notes reference their partner through `Obj.Value`. A top-level `mash` note names
its input in the `Key` attribute and uses `CounterA` or `CounterB`; nested visual
copies and the templates under `Frame.Keys` are ignored.

The lines menu still uses its name or reference layout; Respawn, confirmation,
Reconnect, and HTC timer use visible text and layout. Exact recovery-menu paths
have not yet been supplied, so menu recognition still needs an in-game check.
Older HUDs retain the generic label/name/attribute and learned-image fallback.
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
- **Recovery:** notices health at or below 2 while training is inactive on the
  next state check (about 100 ms) and immediately starts **lines menu → Respawn →
  confirmation**. Once the game produces its source-confirmed RespawnUI canvas,
  it waits for that canvas to go away, then requires three ready samples with
  health above 2, cleared cooldown, and no resting before it sends a fresh Start.
  Missing menu controls pause with a specific status.
- **HTC timer:** verifies two plausible readings and extrapolates between reads.
  At 35 minutes remaining by default, it enters AFK. Unknown timers are not given
  a guessed duration. A verified countdown survives normal respawn.
- **Reconnect:** watches throughout active training, recovery, startup, and AFK.
  It checks every two seconds, confirms two observations, approaches smoothly,
  hovers, and clicks. It allows three attempts with a nine-second cooldown after
  each click, waits seven seconds after the hub returns, and starts again. Retry
  counts reset for later disconnects. Reconnecting clears the old session timer.
- **Off:** cancels pending actions, releases inputs, and stops discovery. Errors
  stop Chamber and display a reason below its toggle. Additional details appear
  in the executor console.

Defaults live in `src/Config.lua`; previous configuration remains readable from
`DBFR_Lua/settings.json` when executor file functions are available. There is no
settings page. AFK intentionally stops input until Reconnect appears.

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
| `src/UI.lua` | Compact Dragon Ball hub and independent feature rows |
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

The 90-test offline suite covers exact note names and normalized timing across
difficulty speeds, linked doubles, 25 accepted mash inputs at 30/60 Hz, lane
replacement, source-confirmed RespawnUI handling, recovery order, post-respawn Start gating, repeated
reconnects, timer retention, sustained spam, cancellation and release, automatic
recognition, event-driven discovery, pause/unload cleanup, and large GUI fixtures.
It uses deterministic Roblox API doubles and does not render Roblox or validate
live executor permissions. The source uses the Lua 5.1-compatible subset of Luau;
the shipped application runs inside Roblox.

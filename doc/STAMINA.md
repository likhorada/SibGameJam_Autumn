# Sprint, stamina and fatigue

## Behaviour

- Hold Shift while moving forward (including forward diagonals) to sprint.
  Backward and sideways movement remains walking. Speeds stay 2.5 / 4.3 m/s.
- A full reserve lasts **3 seconds** of actual grounded sprint movement. Consumption
  is linear; standing with Shift held, pushing a wall and using the PC do not drain it.
- Exhaustion disables sprint and returns to walk speed through existing braking.
  Recovery starts after **0.5 seconds**: full recovery takes **4 seconds at rest/on PC**,
  **6 seconds while walking**, excluding the delay.
- At **35%** recovery sprint unlocks. Holding forward + Shift automatically resumes it,
  giving roughly a one-second burst before the next exhaustion. This cycling is intentional.
- Stopping voluntarily before exhaustion permits immediate use of the remaining reserve.
- Seating/standing, focus loss and mouse release do not reset stamina. A new player
  instance starts full. `PlayerStamina.reset()` is available for a future session restart.

## Bar

`HUD/StaminaBar` is anchored strictly bottom-centre, 160×3 logical pixels, 26 pixels
above the bottom at the 1280×720 design size. Muted translucent track/fill; no numbers,
colour flashes or arcade decorations. It fades in when stamina is spent, stays while
recovering and fades out at full. Hidden with the HUD while seated.

Only presentation is deceptive: `display = 1 - (1 - real)^2`. At real 50% the target
fill is 75%; at real 20% it is 36%. The beginning appears generous and the end drains
faster. Fill and visibility use exponential smoothing; gameplay never reads the bar.

## Fatigue screen effect

- A mild warning starts below **20%**. At exhaustion fatigue increases smoothly.
- After exhaustion a separate fatigue latch persists beyond the sprint-unlock threshold.
  It falls to zero at **45%** recovery. Onset is smoothed; recovery follows the gradual
  stamina envelope without a smoothing tail beyond that clear threshold.
  Resuming sprint at 35% still leaves mild fatigue, as requested.
- The final walking camera's change in orientation determines a bounded directional
  shutter offset. This includes large immediate mouse flicks and smoothed look.
- The Compatibility canvas shader uses six screen samples: directional blur and a weak
  offset copy. **This is a ghosting approximation of the current image, not stored previous
  frames, depth-based motion vectors or a static Gaussian blur.**
- At rest the directional offset decays and the shader draw is hidden, even if stamina
  is empty. At full reserve, behind the PC, on mouse release, focus loss and during camera
  handoff it is hidden too. No extra 3D render target or GPU→CPU readback is used in gameplay.
- The effect is the first HUD child, before the bar, crosshair and text. These remain
  sharp; the desktop and CCTV are not processed. Entering the PC invalidates orientation
  history so returning or resizing cannot smear between unrelated views.
- No extra bob, vignette, breathing, heartbeat or audio added.

## Inspector tuning

**`scenes/player/player.tscn` → Player:** existing `walk_speed`, `sprint_speed`, acceleration
and braking. The camera now receives actual sprint state, rather than raw Shift input,
so exhaustion, sideways movement and walls do not keep sprint FOV/bob active.

**Player → Stamina** (`scripts/player/stamina.gd`):

| Property | Default |
| --- | --- |
| `sprint_seconds` | 3 |
| `recovery_delay` | 0.5 |
| `rest_recovery_seconds` | 4 |
| `walking_recovery_seconds` | 6 |
| `restart_ratio` | 0.35 |
| `warning_ratio` | 0.2 |
| `clear_fatigue_ratio` | 0.45 |
| `warning_strength` | 0.22 |

**`scenes/ui/hud.tscn` → HUD** (`scripts/ui/player_hud.gd`):

| Property | Default / meaning |
| --- | --- |
| `visual_curve_power` | 2; 1 gives an honest bar |
| `bar_response` / `bar_fade_response` | 12 / 8; fill and opacity smoothing |
| `fatigue_strength` | 1; **0 fully disables smear without changing stamina** |
| `fatigue_response` | 5; fatigue onset/fade response |
| `smear_response` | 20; directional offset response |
| `shutter_seconds` | 0.035; simulated exposure |
| `max_smear_pixels` | 18 design-size pixels for the main shutter offset |
| `ghost_weight` | 0.12; offset-copy weight; copy lies at 1.7× shutter offset |

Bar dimensions, bottom margin and colours are ordinary child Control/ColorRect
properties in the HUD scene. Existing `CameraMotion.effect_strength` still controls bob,
roll and FOV independently; it does not disable the new fatigue shader.

## Tests and manual acceptance

```powershell
godot --headless --editor --path . --import
godot --headless --path . --script res://tests/stamina_smoke.gd
godot --path . --script res://tests/stamina_smoke.gd
```

Headless checks model timing, linear drain, recovery delay, thresholds, warning/latch,
30/60/144 update-step consistency, deceptive curve, layout and recovery while seated.
Native additionally checks actual input/movement, direction restrictions, wall pushing,
automatic restart, speed/FOV after exhaustion, bar smoothing, and rendered shader pixels
against a static contrast chart. Opaque crosshair pixels must remain unchanged.
Stationary-camera clearing and the strength-zero comfort switch are also checked.
Optional native screenshots: `-- --capture-dir=C:/existing/folder`.

**Manual comfort check:** open `tests/stamina_fixture.tscn` and press F6. It uses the real
game/player/HUD in a long, simple test space, so there is room for the full three-second
run. Hold W+Shift, exhaust, turn the camera, stop turning, and wait for recovery. Compare
against `HUD.fatigue_strength = 0` if the smear feels too disorienting. The fixture is
excluded from normal release exports by `tests/*`.

For a dedicated Web fixture export, use a **temporary project copy**: change only that
copy's `run/main_scene` to `res://tests/stamina_fixture.tscn` and remove `tests/*` from
its Web preset's exclusion filter, then export to `build/stamina-web/index.html`.
Run `node tools/stamina_web_check.mjs` from that copy (Windows, Node 22+, Chrome).
`STAMINA_WEB_ROOT` may override the export directory and `CHROME` the executable.
This harness asserts live fixture telemetry while driving real browser keys/mouse;
test-only JavaScript telemetry is absent from the normal game export. Screenshots are
saved under `%LOCALAPPDATA%/Temp/opencode/stamina_web_*.png` and still need visual review.

## Verified locally (Godot 4.6.2 Compatibility)

- Import and stamina smoke in headless/native mode — PASS. Native screenshots show
  the subtle centred bar, directional smear on a contrast chart and a sharp crosshair.
- Existing prototype/10 PC cycles, camera motion, headless desktop and CCTV smoke — PASS.
- Clean copy from Git index, without unrelated local scene/theme/notepad/model changes:
  import, headless/native stamina tests, production Web and Windows exports — PASS.
- Windows EXE from clean copy: headless startup for ten frames, empty stderr. Interactive
  testing of that standalone EXE was not performed.
- Production Web from clean copy in ordinary Chrome/local HTTP: existing CCTV interaction
  harness completed without console errors; viewed camera screenshot remains unaffected.
- Dedicated Web fixture from that copy, with only temporary main-scene/export-filter
  changes: actual W+Shift drain, deceptive bar, exhaustion, mouse-driven smear, clear
  stationary camera, recovery, held-Shift restart, PC transitions and 640×360 — PASS.
  Live telemetry recorded roughly 0.51 real vs 0.79 smoothed displayed stamina, a bounded
  16.9-pixel moving-camera offset at exhaustion, and shader hidden again at rest.
  Reviewed screenshots of bar, moving/stationary image, PC and resized view; no console errors.

Firefox, low-end hardware performance and extended human comfort acceptance are not
verified. Frame-step tests are numerical consistency checks, not GPU benchmarks. The
Web harness uses its own temporary Chrome profile with background throttling disabled;
this is a testing setting, not a required browser/game configuration. Feel/intensity
still needs player acceptance; start by reducing `fatigue_strength` if uncomfortable.

# Visual effects

## Presentation

- Apartment: one shared-world `SubViewport`, 256×144 at the project's 16:9
  design aspect, nearest upscale. Source gameplay cameras are not moved or
  replaced; a render-only camera follows walking, transitions, fusebox and hiding.
  Root 3D rendering is disabled to avoid rendering the apartment twice, restored
  on scene teardown. The apartment viewport stops updating behind the desktop.
- CCTV: existing single active 480×270 viewport, unchanged render budget.
- HUD and desktop text remain at the normal design resolution.
- CRT: faint scanlines and a moving brightness band, only while seated at the PC.
  Multiplicative overlay; no screen texture copy, noise or curvature.
  Scanlines use physical-pixel coordinates (one dark row per three rows), avoiding
  the former 360-cycle cosine cancelling at pixel centers on a 720-row screen.
- Anxiety: same directional smear/ghosting as stamina, stronger on camera turns,
  with mild persistent double contours even at rest. Stamina and anxiety share
  one world-screen shader pass. CCTV samples only its own image, never UI text.
- Anxiety grows with proximity to neighbor, police and the active corridor
  entity, including through walls. Starts at 7 m, reaches full strength at 1.5 m.
  Corridor apparition and neighbor entry also trigger short scare pulses.
  Recovery takes up to 2.5 seconds. No stamina/gameplay values are changed.
- Dev menu and run-end screens suppress effects. No new player settings.

## Tuning

Select `Main/VisualEffects` in `scenes/main.tscn`:
`render_height`, `crt_strength`, `anxiety_strength`, `danger_radius`,
`full_danger_radius`, `recovery_seconds`. A strength of zero disables that effect.
Future scripted scares can call `game.visual_effects.trigger_scare(strength)`.
The existing `HUD` fatigue parameters still control the directional smear.

Implementation: `scripts/visual_effects.gd`, `scripts/ui/player_hud.gd`,
`scripts/ui/desktop/cctv_app.gd`, `assets/shaders/terminal_crt.gdshader`,
`assets/shaders/cctv_feed.gdshader`. Wiring: `scripts/main.gd`, `scenes/main.tscn`,
`scripts/threats/corridor_entity.gd`, `scripts/threats/psych_neighbor.gd`.

## Verified — 2026-10-31, Godot 4.6.2 Compatibility

- Editor import: no script errors.
- Native `tests/visual_effects_smoke.gd`: PASS, including real rendered-pixel
  changes at rest, 256×144 apartment and 480×270 CCTV, scare recovery, proximity falloff, PC render
  gating, CCTV-only anxiety, hiding camera and root-render restoration.
- Native `tests/stamina_smoke.gd` and `tests/prototype_smoke.gd`: PASS, including
  stamina shader pixel checks and 10 computer enter/exit cycles.
- Headless visual-effects, neighbor, police, outage and threat-lifecycle smoke
  tests: PASS. Police/outage tests also print resource-in-use warnings at exit;
  those teardown warnings have not been investigated in this task.
- Dedicated Web test export opened in Chrome/WebGL 2: PASS via
  `tools/visual_effects_web_check.mjs`. Checked stationary scare/recovery,
  CRT and CCTV anxiety, stopped apartment rendering behind the PC, return camera,
  1280×720, 640×360 and letterboxed 1000×720. No browser errors.
- Firefox, weak-hardware performance and subjective playtest tuning not verified.

Native reproduction:

```powershell
godot --path . --script res://tests/visual_effects_smoke.gd
```

Optional `-- --capture-dir=C:/existing/folder` saves comparison screenshots.
For Web, use a **separate test copy** of the project: main scene
`tests/visual_effects_fixture.tscn`, remove `tests/*` from the Web exclusion filter,
import and export to `build/effects-web/index.html`, then run:

```powershell
node tools/visual_effects_web_check.mjs
```

Do not ship the fixture: it exposes test-only JavaScript commands/telemetry.
Production export exclusions remain unchanged.

## CRT rendering fix — 2026-11-01

- `assets/shaders/terminal_crt.gdshader`: physical-pixel scanlines, stronger
  contrast (subsequently increased to 16% at default strength), wider/stronger
  moving band. No new effects.
- `tests/visual_effects_smoke.gd`: diagnostic red overlay proves the layer draws
  over the desktop; CRT-on/off screenshot comparison checks actual scanline contrast.
- `tests/crt_smoke.gd`: isolated rendered-pixel test, PASS on native Compatibility
  at 1280×720 and 640×360. Checks scanlines, moving band and zero-strength bypass.
- `tests/visual_effects_fixture.gd`, `tools/visual_effects_web_check.mjs`: test-only
  CRT toggles and screenshot pixel comparison; Chrome/WebGL PASS, measured 13.1%
  scanline contrast. Web used the existing separate test copy with the updated
  shader/fixture, not the concurrently changing threat gameplay scripts.
- Current full native visual-effects smoke: CRT checks PASS; one unrelated
  proximity assertion fails (`Enemy distance controls anxiety, without visibility
  gating`) after changes to enemy awareness. Threat logic was not modified here.
- Run isolated test: `godot --path . --script res://tests/crt_smoke.gd`.

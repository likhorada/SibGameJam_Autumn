# CCTV GuyRig — 2026-11-01

- Updated from GitHub `main` to `9dca784` (fast-forward).
- `scenes/cctv/guy_actor.tscn` instances `assets/models/GuyRig.glb`.
  Office, observation shop, street target/pedestrians and the shared test mannequin
  use it; the latter also updates the legacy shop/yard feeds and menu backgrounds.
- `scripts/cctv/guy_actor.gd` applies the GLB's one-frame `Action` pose once,
  then pauses the AnimationPlayer. The current GLB contains no separate sitting,
  typing or walking clips. Motion still follows the existing scripted routes;
  the visual turns toward horizontal movement, without changing route positions.
- Per-instance shirt materials preserve the ochre target clue and blue/purple
  pedestrians. Imported textures/materials remain shared and unmodified.
- Removed the office's old placeholder-arm bobbing, which referenced deleted meshes.

## Checks (Godot 4.6.2, Compatibility)

- `tests/guy_actor_smoke.gd`: headless and native PASS; checks all five locations,
  actor counts, applied bone pose, paused player and shirt colors.
- `tests/shift_smoke.gd`: headless/native assertions PASS; native office, checkout
  and street screenshots inspected. One native run crashed in engine shutdown
  after printing PASS; a headless run reported resources still in use at exit.
- `tests/cctv_smoke.gd`: final native run PASS, no errors. Earlier headless run
  crashed in engine shutdown after PASS. Small-motion look-at errors found during
  that run were fixed by normalizing the facing direction.
- Web release exported and opened in Chrome using `tools/cctv_web_check.mjs`.
  GuyRig renders with the authored pose and ochre shirt (screenshot inspected).
  The existing browser harness did **not** pass: it catches an invalid UID warning
  from `scenes/atmosphere/room_camera_feed.tscn` / `room_camera_event.gd`. Its old
  shop/yard capture labels currently capture the observation office instead,
  so this is only browser startup/office rendering evidence, not full route coverage.

Unrelated concurrent menu credits, icons and main-scene edits were left alone.

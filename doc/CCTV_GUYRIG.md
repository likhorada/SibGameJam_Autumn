# CCTV humanoid animation — 2026-11-01

## Runtime

- `scenes/cctv/guy_actor.tscn` / `scripts/cctv/guy_actor.gd`: one actor controller,
  with Inspector-selectable **GuyRig / DecoyGreen / DecoyRed / DecoyYellow** models.
  Street pedestrians use the actual three decoy GLBs with their original materials.
  Viktor uses the original GuyRig materials: white shirt and blue tie, matching the briefing.
- `assets/animations/cctv_humanoid.res`: seven shared skeletal clips: `idle`, `walk`,
  `work`, `stand`, `carry_idle`, `carry_walk`, `reach` (shared library).
  Walking tempo follows measured horizontal speed; turns and clip changes blend.
  Pedestrians have different animation phase offsets.
- Office: seated at the authored chair/laptop, small typing movements. Starting
  the alarm route rolls the chair back and plays `stand`; the first 1.5 seconds
  keep the actor at the desk, then he walks via the aisle to the actual door.
  Total office route: 18.5 seconds. The notebook code stays visible.
- Shop (`locations/shop.tscn`, also used by the menu): turn toward wine/gin/vodka,
  reach the actual shelf, attach the item to `DEF-hand.R`, carry with
  a separate upper-body pose, then reach/release onto the checkout counter.
  After payment he collects the bottle again, leaves carrying it, and keeps that
  same item when the shift changes to the street (no duplicate or lost purchase).
  Handoffs occur 0.45 seconds into the reach, not at the start of the gesture.
  The wrapper follows wrist position but stays upright (top-level transform), so
  late AnimationPlayer/BoneAttachment updates cannot rotate the bottle sideways.
  Base-origin wrappers retain the GLB scale and sit on a real shelf ledge/KSO tray.
- Yard and menu mannequins inherit the same walking controller.
  There are no new viewports, runtime IK solvers, external services or Blender dependency.

## Authoring / rebuild

The current GLBs contain one-frame `Action`, not walking/sitting animation clips.
`GuyRig.blend` contains the full Rigify rig but no saved actions/pose assets.
New clips are therefore baked through the model's existing IK controls, not claimed
to be pre-existing exported animations. Original `.blend` and character GLBs are untouched.

1. `blender -b assets/models/GuyRig.blend --python tools/bake_cctv_animations.py`
2. `godot --headless --path . --script res://tools/bake_cctv_animations.gd`

Intermediate untextured GLBs go into `%LOCALAPPDATA%/Temp/opencode/cctv-animation-bake`.
The Godot bake retains deform bones **and their ancestors** (including Rigify ORG
bones); removing those ancestors disconnects hips/shoulders. Constant rest tracks
are included to prevent poses leaking across transitions. Each clip has 204 tracks
for 68 relevant bones, not the full 260-bone control rig.

## Verified: Godot 4.6.2 Compatibility

- `tests/guy_actor_smoke.gd`: headless/native PASS. Checks actual model resources,
  all three decoys, seated body height, stand/walk/idle transitions, moving feet,
  chair hold in the route, hand attachment, carry cycle and counter release.
- `tests/cctv_smoke.gd`: final native run PASS, no errors.
- `tests/shift_smoke.gd`: native/headless assertions PASS. Headless still reports
  ObjectDB/resources in use at shutdown. One intermediate native run crashed in
  engine shutdown after PASS (also observed before this animation work).
- `tests/cctv_animation_visual.gd`: live native office departure, pickup/carry,
  checkout and street run completed; key screenshots inspected under
  `%LOCALAPPDATA%/Temp/opencode/cctv_anim_*.png`.
- Dedicated **release Web export in Chrome: PASS**, using
  `tests/cctv_animation_fixture.tscn` and `tools/cctv_animation_web_check.mjs`.
  Checks getting up, rising head height, pickup/carry/release, distinct decoy GLBs
  and animated feet. Office/work/stand/carry screenshots inspected.
  The existing unrelated invalid UID warning in `room_camera_feed.tscn` remains;
  the harness logs warnings but fails on actual runtime errors.

For the Web fixture, copy the project (including current imports) to a temporary
directory whose name contains `cctv-animation-web`; run
`tools/prepare_cctv_animation_web.gd` **in that copy only**, export its Web preset
to `index.html`, then `node tools/cctv_animation_web_check.mjs <export-directory>`.
Production main-scene/export settings are not changed. Tests/tools remain excluded
from production exports. This is animation acceptance, not a full survival/quiz Web playthrough.

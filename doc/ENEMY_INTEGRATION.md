# Enemy branch integration — 2026-10-31

## Checkpoints and scope

- `58888bc`: all pre-existing local enemy, power, audio, translation and test changes saved before integration.
- `3ddf16b`: merged `origin/main` at `18ec621` into `feat/enemies`. No textual conflicts; main contributed Cigarettes, Cubicle and Vodka models.
- Imported those models with Godot 4.6.2 standard; committed their import settings and extracted textures so other machines do not depend on this checkout's cache.
- No gameplay redesign or renderer/engine changes.

## Regression coverage

Godot 4.6.2 standard, Windows, Compatibility renderer:

- All 15 existing `tests/*_smoke.gd` scripts passed with a real desktop window: ambience, camera motion, CCTV, chat, desktop, flashlight, menu, neighbor, outage, police, power, prototype, shift, stamina and threat scheduler.
- The neighbor check initially reported two ambient WAV/playback resources at process shutdown despite passing its assertions. Verbose diagnostics isolated the final run's stopped audio voices. The check now allows 0.2 seconds for AudioServer's mixing thread to release them before quitting. Verbose checks, three consecutive headless reruns and a final real-window rerun passed without resource/leak warnings. No runtime audio change was necessary.
- `tests/threat_lifecycle_smoke.gd`: 12 run creations/teardowns cycling all three threats, both live teardown and death overlays. Checks scene weak references, baseline node/orphan counts, reservation cleanup and stopped footsteps. Passed headless and with a real window with no shutdown warnings after allowing the audio thread to finish; also passed three consecutive headless reruns.
- Editor import passed both in this checkout and in a fresh archive of the integration commit, without relying on its existing `.godot` cache.
- Release Web and Windows Desktop exports passed without reported errors/warnings. Source menu and exported Windows EXE also passed headless 60-frame startup checks.
- Production Web build opened in normal Chrome: menu/settings interaction, fullscreen, RU language persistence, 640x360 resizing, game launch and gameplay pointer lock passed. Small settings and persisted-language screenshots reviewed.
- Dedicated Web outage fixture in normal Chrome passed RU/EN: held F7, forced outage, ejection from PC, flashlight input, corridor encounter, provoked pursuit and contact death. The fixture was exported from a fresh integration archive, not an old build.
- Dedicated Web police fixture passed RU/EN: F7 trigger, PC exit, E to hide/leave, constrained mouse look, blocked walking while hidden, safe departure and death on premature exit.
- Dedicated Web neighbor fixture passed: pointer capture, real E input, F7 trigger, closing the door to survive, double-clicking the virtual TXT and death with the door left open.

## Limits

- Desktop smoke tests use synthetic input; not a substitute for human playtesting or judging audio/visual quality.
- No Firefox, weak-hardware performance or long-duration memory profiling was performed. Node/orphan checks and clean shutdown diagnostics are bounded regression checks, not proof that every possible leak is absent.
- Browser fixtures expose test-only controls; production presets continue to exclude `tests/*` and `tools/*`.
- Logs and screenshots are local artifacts under `%LOCALAPPDATA%/Temp/opencode/merge-*` and the existing browser-check screenshot paths; not shipped in Git.

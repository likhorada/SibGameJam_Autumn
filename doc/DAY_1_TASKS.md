# Day 1 — agent-ready backlog

**Milestone:** by the end of Day 1, someone who has never opened the project can launch it, play one 2–3 minute scripted shift, answer 3 questions, see a result and restart. Browser proof preferred over polish.

## Current status — 2026-10-30

| Task | Status | Evidence / remaining work |
| --- | --- | --- |
| D1-01 | Prototype ready | Godot 4.6.2 Compatibility, editable apartment blockout, walking/sprint, desktop and clean-copy smoke tests pass. |
| D1-02 | Core interaction ready | Smooth full-screen PC enter/exit, 10 desktop cycles, Chrome input/resize checks pass. Browser focus-loss and later audio startup still need acceptance. |
| D1-03 | Partial | CCTV app: four cameras in two editable test locations, color/BW, microphone flags, delayed pan/zoom, one active render target. No clue timeline or real feed audio yet. See `doc/CCTV.md`. |
| D1-04 | Partial | Freeform Notepad preserves notes within the run; no quiz, scoring or full session restart yet. See `doc/DESKTOP_UI.md`. |
| D1-05 | Not started | Fusebox is decorative, not an implemented threat. |
| D1-06 | Partial | Web and Windows exports work; Chrome prototype tested. CI workflow added; Pages requires owner setup. Full game-loop acceptance depends on D1-03..05. |

See `doc/PROTOTYPE_TESTS.md` for actual checks and limitations. The user approved the
local blockout for publication; this does **not** mean the Day 1 milestone is complete.

## P0 — Must be done in order

### D1-01 — Create Godot repository + launchable scene
**Owner:** Integration / agent A. **Dependency:** none.
- Set up Godot 4.x project (team pins version), Compatibility renderer, 1280×720 design size, basic input actions, main scene.
- Scene launches into a basic first-person apartment with a desk/computer, using primitive meshes and one or two cheap lights.
- Add `.gitignore`, `README.md` run instructions, and export target notes.
**Accept:** F6/F5 works, no parser errors, camera can look around, the computer is visually identifiable. Native/headless launch checked if tool available.

### D1-02 — Computer focus / exit interaction
**Owner:** Gameplay / agent B. **Dependency:** D1-01 scene interface agreed.
- Interaction key focuses terminal, shows mouse cursor and terminal UI; Escape leaves terminal and restores looking around.
- Make web focus/mouse lock behavior graceful; include on-screen hint.
**Accept:** 10 consecutive enter/exit cycles without stuck mouse or broken input. Can view room while away from terminal.

### D1-03 — Fictional CCTV viewer + minimal timeline
**Owner:** Surveillance / agent C. **Dependency:** terminal UI contract.
- Two target feeds with distinct fixed mock frames/cheap scenes; optional third feed for audio text.
- Data-driven 90-second scripted sequence with 3 observable facts. Feeds switched by clickable buttons; clock/status shown.
- Implement audio-only clue as text initially; actual VO can wait. Active feed only; no always-live multi-camera rendering.
**Accept:** Switching feeds reveals genuinely different info; events display at correct times and advance independently of chosen feed; no Internet needed.

### D1-04 — Notes + quiz + scoring
**Owner:** UI / agent D. **Dependency:** event IDs / answer schema agreed with D1-03.
- Minimal notes panel (freeform text, local run memory only).
- At timeline end, show 3 multiple-choice questions, score count and restart.
- Hand-authored questions with stable answer IDs, not NLP or string matching.
**Accept:** Correct answers give 3/3; incorrect answers lower score; notes remain accessible while observing; restart resets the session.

### D1-05 — One home threat prototype
**Owner:** Threats / agent E. **Dependency:** D1-02.
- Add home CCTV tab or look-around cue; trigger a warning (door knock/static/shadow) during subject event window.
- Player can acknowledge/check threat by looking away from terminal or checking home feed; short grace period.
- One simple state machine: `IDLE -> WARNING -> RESOLVED` or `GAME_OVER` if ignored. No enemy AI.
**Accept:** Player must choose between watching target and handling warning; threat is understandable, repeatable and can cause failure; restart works.

### D1-06 — Integration + first Web export
**Owner:** Integration / agent A. **Dependency:** D1-01..05 MVP in main.
- Integrate all scene changes, check no shared-node conflicts, fix parse warnings/errors.
- Add Web export preset, install matching templates locally, export to `build/web/index.html` (ignored by git).
- Serve through local HTTP server and play in Chromium/Firefox. Verify input, text rendering, audio unlock, video/CCTV UI, quiz, game over and restart; inspect browser console.
**Accept:** Desktop run passes full flow. Web exported and run successfully **or** blocker documented exactly (missing templates/tools/unsupported feature), with no false "tested" claim.

## P1 — Only after all P0 is playable
- 2nd threat personality (neighbor) using same state machine.
- Simple PSX filter optional toggle, no advanced shader dependencies.
- CRT static, 2D distortion overlays at low resolution.
- 2–3 original low-poly props + coherent rusty material palette.
- Test quality mode / lower feed size if performance is bad.
- More believable clue variations: side-angle/no sound vs overhead/audio-only.

## P2 — Definitely not Day 1
- Full city and NPC navigation, multiple paths or days, real-time facial/voice analysis.
- Real camera APIs, internet browsing, networking, advanced AI.
- Three fully implemented pursuers, elaborate combat, full narrative cinematics.
- Heavy volumetric effects, dozens of active render targets.

## Suggested integration checkpoints
1. **Checkpoint A:** empty 3D room + desktop interaction works.
2. **Checkpoint B:** two feeds, 3 facts and timer work.
3. **Checkpoint C:** quiz and reset work without threat.
4. **Checkpoint D:** one threat creates attention conflict.
5. **Checkpoint E:** exported browser build completes full run.

## Data contract proposal (edit together before parallel work)
```json
{
  "duration_sec": 100,
  "events": [
    {"at_sec": 10, "feed_id": "street", "clue_id": "jacket", "display": "Subject wears a red jacket."},
    {"at_sec": 30, "feed_id": "checkout_audio", "clue_id": "purchase", "display": "Cashier: One bag of rice."},
    {"at_sec": 65, "feed_id": "office", "clue_id": "boss", "display": "Boss: I'm Marina."}
  ],
  "questions": [
    {"id": "q_purchase", "prompt": "What did the subject buy?", "options": ["rice", "pasta", "buckwheat"], "answer_index": 0},
    {"id": "q_boss", "prompt": "What was the boss's name?", "options": ["Alex", "Marina", "Dina"], "answer_index": 1},
    {"id": "q_jacket", "prompt": "What color was the jacket?", "options": ["red", "black", "blue"], "answer_index": 0}
  ]
}
```
Timeline is fictional and presentation is provisional. `clue_id` ties observations to quiz facts. Do not treat this format as an engine parser until implemented and validated.

## Prompt to hand to a coding agent
> Read AGENTS.md, GAME_CONCEPT.md and DAY_1_TASKS.md. Implement task D1-XX only. Preserve Compatibility renderer and web export constraints. Use placeholders and keep main scene launchable. Do not introduce scope beyond task. When finished report changed files, run/tests actually performed, acceptance criteria results, remaining blockers and how to reproduce. Do not claim Web-tested unless you exported and opened the browser build.

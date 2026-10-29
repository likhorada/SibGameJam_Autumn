# AGENTS.md — FOOD CHAIN (working title)

## Project
Short first-person surveillance horror game for a game jam. The player is a stalker watching a **fictional, scripted** person's day through CCTV: where they go, what they buy, what they say, and whom they meet. The player takes notes and answers a multiple-choice quiz at the end. Meanwhile, police, hostile neighbors, and hired killers threaten the player's own apartment; the player must balance observing the target with checking their surroundings and surviving. Tone: paranoid, grimy, darkly funny. Visual style: low-poly PSX/PS2, industrial rust, analog CCTV.

Keep this core loop intact. See `doc/GAME_CONCEPT.md` for details; current priorities live in `doc/DAY_1_TASKS.md`, **not in this file**. All surveillance footage and people are fictional; do not use real camera feeds or personal data.

## Technical constraints
- **Godot 4.6 standard + GDScript**, with the **Compatibility** renderer. Ship to desktop **and Web**; test browser exports early and regularly. Coordinate any engine version changes with the team.
- The player can walk around the apartment, sit at the computer to enter a full-screen PC interface, and leave it to resume walking (Welcome to the Game reference).
- Optimize for weak hardware: simple geometry, modest textures and lighting, cheap effects, limited active rendering. Avoid many simultaneously live 3D CCTV `SubViewport`s; use scripted/cached feeds or render the active feed only.
- Avoid features that undermine Web portability (C#/.NET, native-only plugins, required external services, blocking I/O). Favor simple event-driven logic and data-driven scripted timelines.
- Make mouse capture/release, UI input, window resizing, and browser audio startup reliable.

## Working rules
- Keep the project launchable; make small, focused changes and don't rewrite unrelated systems.
- Prefer a playable, tested solution over abstractions, speculative features, or visual polish.
- Keep observation events, questions, and answers separate from presentation code where practical.
- Never claim something works unless tested. Report changed files, what you verified (desktop/Web), and remaining issues.
- If requirements are unclear, follow the current task and `GAME_CONCEPT.md`; ask before changing the game's core design.

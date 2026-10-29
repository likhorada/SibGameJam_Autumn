# FOOD CHAIN — concept lock (working title)

## One-liner
You're a stalker watching a stranger's ordinary day through fictional online street/shop CCTV, taking notes for a final quiz — but while you're hunting, police, furious neighbors and a killer may come for you. Everyone is somebody else's prey.

## Design pillars
1. **Observation is work.** Watch the subject's day carefully: what they bought, ate, who they met, their boss's name, etc.
2. **Information is fragmented.** The same event appears at different angles; some feeds have sound and others don't; choosing the right feed matters.
3. **Attention is scarce.** Watching the subject competes with checking the player's room, apartment security cameras, doors and unsettling noises.
4. **Consequences are tangible.** Missing a detail hurts the end-of-day quiz; ignoring a danger may end the run.
5. **Predator is prey.** The player is morally monstrous, yet vulnerable to their own pursuers. Unsettling, occasionally absurd tone.

## Explicitly agreed mechanics
- First-person, 3D apartment and seated computer interaction.
- Multiple *fictional* target CCTV feeds; target's day progresses through scripted events.
- Feed angle and audio availability change what details can be learned.
- Player keeps notes while watching.
- End-of-day multiple-choice quiz tests details actually observable during play.
- Separate home/safety CCTV feeds and physical look-around check.
- Police, violent neighbors and hired killer are planned threat *types*. Day 1 can implement one generic threat state as placeholder; don't claim three are done.
- PSX/PS2 visual direction; decayed, dirty, rusty, oppressive Silent Hill 3-like environments; creepy retro desktop/WTTG paranoia.
- Low-end PC and Web export are hard constraints.

## Minute-to-minute loop
Observe subject -> switch camera/view or audio source -> gather fact -> jot note -> hear/see warning at home -> decide whether to check surroundings/home CCTV -> return to observation (potentially missing a fact) -> repeat -> quiz -> result/failure.

## Day 1 sample sequence (PLACEHOLDER DATA; not canon lore)
- 00:10 CAM_STREET: subject approaches shop. Visible: jacket color.
- 00:25 CAM_STORE_WIDE: subject chooses between rice and pasta. Wide view is ambiguous.
- 00:35 CAM_CHECKOUT_AUDIO: checkout dialogue makes final purchase obvious.
- 00:40 HOME: warning sound / door disturbance. Player must look away and acknowledge a check.
- 01:00 CAM_OFFICE: subject meets boss; label or dialogue establishes the boss's first name.
- 01:20 DAY END: 3 questions (purchase, boss, jacket); result screen and restart.

This is a *prototype timeline*. Final dialogue and exact events can change. Keep questions honest: every answer must be discoverable, and a missed event must not silently hard-lock the game.

## Information design rules
- For each test fact define: question, 3 answer options, correct answer ID, observation window, feed(s) which reveal it, and optional sound cue.
- Different cameras should show complementary evidence, not random obscurity.
- Target feed and home feed must be clearly distinguished in UI to avoid confusion.
- Events continue while the player handles danger, but early prototype should provide a forgiving observation window and clear signaling.
- Avoid recording actual player data or fetching real public cameras. In-game surveillance is fictional.

## What we are NOT changing right now
- No alternative core premise; no replacing the final quiz with an anomaly system.
- No expanding to a city simulation, multiple target NPCs, complicated narrative branches or real-time internet cameras.
- Do not invent extra systems (stress meters, currencies, hacking, etc.) unless the team explicitly approves.

## Art direction
- Cramped dingy apartment; CRT/computer UI; grainy, low-resolution CCTV; gritty rust, brown-green shadow and murky red accents.
- Low-poly geometry and deliberately rough texture work rather than expensive modern lighting.
- Sound carries tension: hum, distant footsteps, rattling door, static, clipped CCTV audio.
- Art/camera effects must be cheap and optional; legibility of quiz clues always wins over visual noise.
- main references: silent hill 3 and 4, welcome to the game, bodycam
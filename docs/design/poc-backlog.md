# Cast: post-POC backlog

Things to do *after* the POC loop works: walk and climb the terrain, fight, and say a
spell. The backlog follows the game's two pillars:
- **Exploration:** discovering a procedural hex world with verticality.
- **Combat through spoken spells.**

Each pillar gets its own sections, followed by the work that cuts across both. Within each
section, items are in priority order.

**P0** = do next, because the pillar can't be judged without it. **P1** = needed before
anyone outside the team plays. **P2** = later.

---

# Pillar 1: Exploration

## 1. Making the terrain worth exploring (see exploration.md)

- **P0** Add fog of war with a reveal radius that grows with height. Without it,
  vantage points and secrets mean nothing.
- **P0** Tag a guaranteed "crown" (vantage cell) per region in `DungeonGen`.
- **P0** Make height easy to read: lighter tile tops, darker sides, and a subtle rim per
  level.
- **P1** Generator rules:
  - one-way drops, each with a validated way back up;
  - loop shortcuts;
  - secrets placed visible from at least one crown and reachable by `find_path` with
    climbing allowed.
- **P1** Secrets: ledge caches, hidden stairs behind breakable walls, and pit undercrofts.
- **P1** Make climbing a decision:
  - no attacks while climbing, and +25% ranged damage taken;
  - +15% damage from 2 or more levels above;
  - a warning the first time a player hovers a 3-level edge ("You can't climb back up
    here").
- **P1** Risk and reward side areas: elite rooms, and brute gauntlets on brute-proof
  plateaus.
- **P1** Room templates with deliberate height puzzles: a climb-only ledge, a stair choke
  point, and a brute-proof plateau.
- **P2** Collapse rooms (floor sinks after the loot is taken), bridge-out islands, and
  split-route rooms with two levers.
- **P2** Shrines on crowns and in secrets, where new spells are learned. This ties
  progression to exploration.

## 2. Co-op exploration

- **P1** A ping key that drops a world marker, and a minimap with teammates and the crowns
  they've climbed.
- **P1** Shared fog reveal, so a scout's climb helps the whole team.
- **P2** A soft leash: beyond about 2 rooms apart, the far player's spell cooldowns run
  slower.
- **P2** Light non-combat voice uses: unison shrine doors, shout-to-scout (it reveals the
  room's walls and wakes enemies), silent rooms, and "mark" by voice.

---

# Pillar 2: Combat through spoken spells

## 3. Voice pipeline and recognition

- **P0** Per-utterance logging to a CSV in `user://`: heard text, partials, match type,
  M/F/C, power, tier, and onset → event and end → event latency.
- **P0** An F2 "that was wrong" key, plus opt-in mic recording so matcher rules can be
  replayed offline (the replay tool from Hero-Reader's speech evaluation).
- **P0** Dedupe the same spell from the same player within 1.5 s (Zipformer double fires
  are 7–10%).
- **P0** Rule 1, "spoken, not mentioned" (a short utterance or a "cast" prefix), plus the
  hair-trigger whitelist for corn.
- **P0** Measure the chatter false-cast rate: 10 minutes of think-aloud play, and a second
  person talking in the room.
- **P1** Check whether the sherpa-onnx result exposes per-token probabilities and
  timestamps. If it does, wire up C (clarity) and F (fluency); otherwise keep C = 1.
- **P1** Sweep hotword score 1.5 / 2 / 3 against the *chatter false-cast rate*, not just
  hits.
- **P1** Confusables checker: spell words within one sound of each other, or of the 500
  most common chat words, are flagged at loadout time.
- **P1** Calibration scene: say each word 3 times, measure the noise floor, set the
  personal level gate, and suggest alternate words.
- **P2** Speaker embeddings (sherpa-onnx speaker ID) for shared rooms and couch co-op.
- **P2** Echo cancellation against in-game voice playback.
- **P2** A/B test Parakeet + VAD (tighter p90 latency) against the Zipformer (better hit
  rate) on Cast's spell vocabulary.

## 4. Casting feel and latency hiding

- **P0** Start the "gathering" pose and rune ring on `voice_activity(true)`, within
  50 ms.
- **P0** Floating heard-word display on every result: gold for Perfect, white for Clean,
  sputtering for Shaky, a smoke puff for Fizzle, and a grey "?" for a Miss.
- **P1** Commit the spell-specific wind-up on an exact partial match, and cancel cheaply
  if the final result disagrees.
- **P1** Every spell gets a 0.3–0.5 s release with the hit frame at the end.
- **P1** Keyboard parity: a 0.5 s channel and fixed 0.8 power, with an accessibility
  toggle for 1.0 and no channel.
- **P2** A/B test quick-draw (fire on an exact partial) for `quick`-tagged spells.

## 5. Combat tuning

- **P0** Set the brute slam and any other telegraph a player should answer with a spell to
  at least 1.5 s.
- **P0** Long spell cooldowns (6–30 s) with big effects, while ordinary attacks carry
  moment-to-moment combat.
- **P1** Perfect riders for the four POC spells: a burn patch, an overheal shield, an
  armor pulse, and a corn kernel scatter.
- **P1** Funny Fizzles (smoke puffs now, the chicken backfire later).
- **P2** Height-aware spells: falling objects (corn, meteor, anvil) hit harder downhill,
  tempest pushes enemies off ledges, quake raises or lowers a hex, and cheese rolls
  downhill.

## 6. Monsters

- **P1** Voice-interaction enemies, cheapest first:
  1. The Listener (only reads `voice_activity`).
  2. Hush Moth.
  3. Word Thief.
  4. Echo.
- **P1** Terrain-aware AI: archers seek high ground, swarmers flow around climbable steps,
  and the brute takes the long way round via stairs.
- **P2** Ledge Lurker (ambushes from height), Loudmouth (driven by mic level), and the
  Hush Warden boss.

## 7. AI allies (until networking exists)

- **P0** Text-bubble cast barks ("Fox: HEAL!") so the voice fiction is visible.
- **P1** Voice-commanded allies ("Fox, heal me", "Bear, over here"), which tests targeting
  without networking.
- **P1** Allies answer the "Brace!" call and response, and follow the player up climbs and
  stairs.
- **P2** Allies chorus with the player to test unison timing.

---

# Cross-cutting

## 8. HUD and UX

- **P0** A voice debug panel on F1: level meter, last partial, last final result, and the
  power breakdown.
- **P1** Spell slots that show their spoken word in large type, with cooldowns.
- **P1** A tutorial room that covers climbing, stairs, one-way drops, and saying each spell
  with Perfect vs Shaky shown side by side.
- **P1** First-run screen: recommend headphones, pick a push-to-talk mode, and set the
  fluency toggle.
- **P2** A post-run report: secrets found, crowns climbed, best spell, fumbles, and the
  corn count.

## 9. Networking and co-op (after the POC proves fun solo)

- **P1** Host-authoritative casts: the client sends `(spell, power, onset_time, level)`,
  and the host resolves dedupe, crosstalk and unison.
- **P1** Clock sync for comparing onset times across machines.
- **P1** In-game Steam voice, so we have the playback reference for echo handling.
- **P2** Split words and chorus casts. Couch mode with separate spell sets on a shared mic.

## 10. Accessibility

- **P1** Rebindable spell words chosen from pre-vetted alternates, a friendly-matching
  option, and a fluency-scoring toggle.
- **P1** Optional climb assist (auto-path over 2-level steps) for players who find the
  traversal fiddly.
- **P2** Free-text custom words, and models and word lists per language.

## 11. Art direction

- **P1** A setting-neutral prototype art pass (see game-pitch.md):
  - grey stone floors with light tops and dark sides;
  - team-color rims on heroes;
  - spells as the only saturated colors.
- **P2** Pick the setting after the first playtest. Warcry is the frontrunner.

## 12. Playtest protocol

- **P0** A 30-minute script:
  - 5 minutes of tutorial;
  - 20 minutes of play with keys 1/2 available;
  - a survey rating "fun to explore", "felt like magic", "felt laggy", frustration, and
    voice fatigue, each on a 1–7 scale.
- **P0** Combat go/no-go thresholds (voice-mechanic.md §7):
  - at least 90% of intended casts recognized;
  - at most 1 accidental cast per 10 minutes;
  - **at least 60% of casts by voice when keys are available**.
- **P0** Exploration metrics:
  - share of optional areas and secrets found;
  - crowns climbed per floor;
  - time spent off the main path;
  - whether players volunteer "what's up there?"
- **P1** At least 5 testers, including one non-native speaker and one noisy setup (a
  laptop mic, no headphones).

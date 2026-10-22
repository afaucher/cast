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
- **P2** Opt-in mic recording, so matcher rules can be replayed offline (the replay tool
  from Hero-Reader's speech evaluation). Only if passive logs aren't enough.
- **P0** Dedupe the same spell from the same player within 1.5 s (Zipformer double fires
  are 7–10%).
- **P0** The three strictness modes (strict, loose by default, chaos), the customizable
  trigger word (default "cast"), and the hair-trigger list for loose mode (corn,
  including sound-alikes such as "corner").
- **P0** Accidental-cast handling:
  - label a cast as accidental when strict mode would have rejected it. This is a
    heuristic built from the trigger's position, the pause before it, whether a trigger
    was said, the match kind and the word count;
  - show an "ACCIDENTAL: <name>" callout;
  - the label grants no mechanical advantage, because a cooldown discount is exploitable
    by phrasing casts casually;
  - data is passive only: the label and its signals go to `user://voice_log.csv`, with no
    player effort;
  - accidental friendly fire can't down anyone.
- **P0** Read accidental casts per minute in each mode straight from the log, and ask
  "funny or annoying?" after the session.
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
- **P2** Height-aware spells: falling objects (meteor, anvil) hit harder downhill,
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

## 8. Results and scoring (see north-star.md)

- **P1** A per-contract score and 1–3 stars:
  - the objective is the base score;
  - time vs par gives a bonus or a deduction;
  - deductions for damage taken, friendly fire and accidental casts;
  - a bonus for secrets found.
- **P1** The generator computes **par** from the critical-path length and the enemy
  budget, so the star thresholds stay fair across seeds.
- **P1** Track friendly fire and accidental casts per player (needed for both scoring and
  the end screen).
- **P1** Downs cost time to revive but never fail a contract by themselves. Make sure no
  single accident can wipe the team.
- **P2** An end-screen highlights reel: "Most accidental casts", "Friendly fire dealt",
  "Fastest revive" and "Best unison".
- **P2** Tune the thresholds from playtests. Target: a coordinated team gets 2 stars every
  time, and a well-oiled one gets 3.

## 9. HUD and UX

- **P0** A voice debug panel on F1: level meter, last partial, last final result, and the
  power breakdown.
- **P1** Spell slots that show their spoken word in large type, with cooldowns.
- **P1** Aim-snap feedback. When the aim snaps onto a teammate (within ~1.3 units),
  outline them in your team color. Make the reticle warn (red) when the spell you're
  winding up would hurt the teammate you're aiming at.
- **P1** A tutorial room that covers climbing, stairs, one-way drops, and saying each spell
  with Perfect vs Shaky shown side by side.
- **P1** First-run screen: recommend headphones, pick a push-to-talk mode, and set the
  fluency toggle.
- **P2** A post-run report: secrets found, crowns climbed, best spell, fumbles, and the
  corn count. Merge it into the results screen in §8.
- **PARKED** The floating combat words (user, 2026-10-22: "park the 13 words"). BOOM!, LAVA! and *bonk* are already
  gone. Still on screen, to review later: SLAM!, THUD!, AAAH!, POP! (corn and the goblin's rocket), FIRE!, FIZZLE, DUD,
  DAMP, COFFEE!, crash..., DENTIST!, BAWK!, *pfft*. Numbers and money stay.

## 10. Networking and co-op (after the POC proves fun solo)

The architecture and lag plan are in [`networking.md`](networking.md): each machine owns its own
hero, the host owns monsters, and cross-owner hits and shoves travel as messages.

- **P0** The day-one infrastructure from `networking.md`: Steam peer settings, packed snapshots,
  clock sync, the interpolation buffer, a two-way lossy link in tests, and telemetry.
- **P1** Casts: the caster sends `(spell, power, target, onset_tick)`, and the host resolves
  dedupe, crosstalk and unison.
- **P1** Clock sync for comparing onset times across machines.
- **P1** In-game Steam voice, so we have the playback reference for echo handling.
- **P2** Split words and chorus casts. Couch mode with separate spell sets on a shared mic.

## 11. Accessibility

- **P1** Rebindable spell words chosen from pre-vetted alternates, a friendly-matching
  option, and a fluency-scoring toggle.
- **P1** Optional climb assist (auto-path over 2-level steps) for players who find the
  traversal fiddly.
- **P2** Free-text custom words, and models and word lists per language.

## 12. Art direction (target look in north-star.md §5)

- **P1** A hex-edge emissive floor shader. It's the cheapest high-impact change, and it
  makes height steps readable.
- **P1** The lighting split: a warm key light and warm ambient, spells as cool cyan and
  violet emissive, and `WorldEnvironment` glow.
- **P1** Team-color rims on heroes. Spells stay the only cool, saturated colors.
- **P2** Toon ramp shading (2–3 bands) with outlines: inverted-hull on actors and a
  screen-space edge pass for the level.
- **P2** Warm luxury-interior materials (wood, marble, brass, concrete) to replace the grey
  prototype palette.
- **P2** Stylized silhouettes: grinning imps, a scrappy contractor crew with improvised
  gear, and a popcorn-burst FX for corn's explosion.
- **P2** Lock the setting after the first playtest. The concept art points to Contract
  Sorcery; Warcry is the alternative.

## 13. Playtest protocol

- **P0** A 30-minute script:
  - 5 minutes of tutorial;
  - 20 minutes of play with keys 1/2 available;
  - a survey rating "fun to explore", "felt like magic", "felt laggy", frustration, and
    voice fatigue, each on a 1–7 scale.
- **P0** Combat go/no-go thresholds (voice-mechanic.md §7):
  - at least 90% of intended casts recognized;
  - in loose mode, about 1 true accident every 2–4 minutes, with laughs outnumbering
    groans at least 3:1 and no run-ending accidents;
  - at most 1 phantom cast per 10 minutes;
  - **at least 60% of casts by voice when keys are available**.
- **P0** Exploration metrics:
  - share of optional areas and secrets found;
  - crowns climbed per floor;
  - time spent off the main path;
  - whether players volunteer "what's up there?"
- **P1** At least 5 testers, including one non-native speaker and one noisy setup (a
  laptop mic, no headphones).

## 14. Heroes and characters (see characters.md)

- **P1** A `HeroDef` data resource with per-hero stats (HP, speed, radius, climb factor,
  shove weight), melee and secondary parameters, color and rig. `HeroFactory` spawns by
  hero id.
- **P1** Shove physics on the hex grid:
  - `Actor.knockback` plus a forced-movement tick that skips AI and input;
  - `HexMap.shove_check` (a rise of 2+ stops the shove with a wall slam; any drop is
    allowed);
  - a gravity fall state with fall damage beyond 3 levels;
  - void ring-out for monsters and fish-out for heroes;
  - monster stagger;
  - a leash fix so shoved monsters don't reset and heal.

  A teammate-caused shove or fall never downs anyone.
- **P1** Rebar's Bowl: a piercing, terrain-riding boulder that shoves both teams (0 damage
  to allies). The reticle turns hazard-yellow when its path crosses a teammate.
- **P1** Gasket's Spin: a tap for a 360° spin, a hold for a whirl of up to 2.5 s, then
  dizziness. Plus the Hammer smash.
- **P1** Wick's arrows (tap, plus a hold-to-draw piercing shot) and shooting while
  climbing. Sir Rattles' shield (hold to block projectiles in a front arc, tap to bash and
  interrupt).
- **P1** Movement quirks:
  - Heavy: no +2 climbs, unshovable;
  - Stout: half shove, slow climb;
  - Light: fast climb, 3-hex shove;
  - Hollow: 6-level drops, falls apart on landing.

  AI-ally pathing must respect each one.
- **P1** `HeroRig`: rigid-part puppets with named animations (`play(&"melee")`), plus a
  shared toon-ramp and inverted-hull outline material. A placeholder art pass on Sir
  Rattles first, then the other three heroes, in code-built primitives.
- **P1** Generator: a no-climb way back (stairs) from every one-way drop, so the brute and
  Rebar are never stranded.
- **P2** A one-day KayKit comparison spike: a pack model next to a primitive hero at the
  default zoom.
- **P2** Gasket's wall-breaker (cracked secret walls glint and break in one swing) and
  Rebar's Leg-up (allies use a still Rebar as a step).
- **P2** Spell "signature twists" per hero. Loadouts stay open, and corn never gets a twist.
- **P2** Vertical-slice models: rigid-part low-poly in Blender, toon-shaded, on one
  proportion template. AI images for concept sheets only.
- **P2** The stretch hero Gulp (frog, tongue pull) and end-screen stats such as "Teammates
  bowled".

## 15. Spell slots and components

- **P1** Four slots, held spell (keys 1-4; E is Use and never casts, spells are cast by voice or the typed console). The held spell recharges 15% faster (a passive boost) and is shown as its component held in the hero's hand. See `spells-and-components.md`.
- **P1** Material components: monster drop tables, walk-over pickups, charges, swapping.
- **P1** Spell **teeth**: affliction, 1-2 s growth, pop with splash and shove, heal cleanses. See `spells.md`.
- **P1** Rename the heroes: Pebble -> **Rebar**, Dagna -> **Gasket**, Larkin -> **Wick**. Done: labels, game.gd, docs, model classes and files. Voice clips ("gasket", "rebar", "wick", plus "Gasket heal me" etc.) assert that the names never cast a spell.
- **P1** Contracts: objectives with pay (employees $10 each, disinfect a room $10k, hellgates $3k each), property-damage deductions, end-of-job invoice. See `contracts.md`.
- Restock spell components at the van (floor 1 only); later.
- **P2** Villain-lair site type (torture chamber, throne room, lab, moat, barracks). See `environment.md`.

## 15b. Downed heroes and revives

- **Decided (user, 2026-10-20): "Option A is fine for now."** The contract ends ("crew incapacitated") when every
  human-played hero is down; AI seats do not keep it alive (solo: you down = crew down). Before, a solo player who went
  down watched the last AI ally until it died, and the AI cannot take the elevator.
- **P2** A real revive mechanic ("We can consider C when we define a revive mechanic"): the nearest ally walks to a
  downed hero and channels a revive (~3 s, exposed), the hero gets up with some HP, the revive is billed like today's
  end-of-job revival. Needs a networked revive (the reviver's machine requests, the host decides) and an AI rule for what
  allies do while a human is down.
  Open first (user, 2026-10-20: "we would immediately have to answer how many revives you get and what happens when
  you run out"): a revive budget (per floor, per contract, or priced per use on the invoice) and the rule once it is spent
  (back to Option A: you stay down; or a costlier revive).

## 16. Gags and one-offs

- **P3** A half-man, half-shark **employee** (user, 2026-10-20: "a half man half shark employee. It would be a good gag").
  A rescuable staff member (suit and tie up top, shark below, or the other way round) who follows the crew like any
  employee; candidates for the joke: he wades the sewer and moat channels happily, the shark lines up with his "family"
  in a lair, his rescue line on the headset. Fits the supervillain lair (a failed experiment on the payroll). Not
  designed; pick it up once the sharks and the sewer have settled.

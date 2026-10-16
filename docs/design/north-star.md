# Cast: north star

*From the user's concept art: a scrappy crew in a warm-lit luxury interior, with a glowing
hex floor, popcorn explosions and grinning imps. This page is the tie-breaker for design
decisions. The two pillars still apply: **exploration** of a procedural hex world, and
**combat through spoken spells**.*

## 1. Pillar statement: "Overcooked with magic"

**Cast is chaotic co-op where the chaos comes from the people.**
- Crosstalk.
- Accidental casts.
- Friendly-fire corn.
- Pointing at the wrong teammate.

Yet **a well-oiled team consistently does pretty well.**

- **Forgiving floor.** A messy, laughing group still finishes contracts. Misses are free,
  accidents are cheap, and nothing that one person does ends a run.
- **High coordination ceiling.** A practiced team clears faster, takes less damage, never
  hits each other, and *sounds* like a team doing it. Skill shows up as consistency, not as
  the occasional lucky win.

## 2. Fun chaos vs unfun chaos

| Fun chaos (keep it) | Unfun chaos (design it out) |
|---|---|
| **Player-caused:** a teammate's careless sentence casts armor too early | **Random:** a dice roll, or a spell the recognizer invented that nobody said |
| **Readable:** an "ACCIDENTAL: Fox" callout, the spell's color, a visible aim reticle | **Unreadable:** "why did I just take damage?" |
| **Recoverable:** it costs time, HP or score | **Run-ending:** one slip wipes the team |
| **Attributable:** everyone knows who to laugh at | **Anonymous:** nobody learns anything |
| **Avoidable with skill:** better call-outs, a stricter mode, aiming carefully | **Unavoidable:** no amount of teamwork prevents it |

Phantom casts (the recognizer making up a word) and long recognition delays are *unfun*
chaos. Engineering keeps those down, while design turns up the player-caused kind.

## 3. What teamwork mastery looks like

- **Call-outs.** "Brute on the left, I'll armor," "Stairs behind the pool," "Don't say
  corner." Voice chat is both the comms channel *and* the input, so good comms is good
  play.
- **Role splits.** One player tanks and taunts, one supports, one deals damage, one
  scouts the high ground. Small spell loadouts (2–4 slots) force complementary picks.
- **Aimed support spells** (already implemented).
  - Every spell lands **where the caster aims**: the same spot the ranged weapon hits.
  - The aim **snaps onto a teammate within ~1.3 units.** Healing or armoring a friend
    means *pointing at them*.
  - Saying the wrong spell while pointing at a friend, such as corn, **hurts them.**
  - Mastery is the hand–voice combination: aim at the right person, then say the right
    word.
- **Timing.**
  - Armor called *before* the brute's slam lands, not after.
  - Heals staggered rather than stacked.
  - Unison casts that land within 400 ms of each other.
- **Voice discipline.** The team picks its own chaos level: strict mode or a rarer trigger
  word ("pickle", "invoke") for a focused run, and loose mode for a fun night. Knowing
  *when* to go quiet in silent rooms and during boss silence windows is a skill too.

## 4. Results model (per contract)

Like Overcooked: every contract ends with a score and **1–3 stars** against thresholds
that a good team hits *consistently*.

| Measure | Effect on score |
|---|---|
| Objective complete | Base score. Failing the objective is the only way to get 0 stars |
| Time vs **par** | A bonus, or a small deduction |
| Damage taken (whole team) | A deduction |
| **Friendly fire** (spells hitting teammates) | A deduction, with an itemized line on the end screen |
| **Accidental casts** | A small deduction each; in loose and chaos modes, mostly a stat to laugh at |
| Downs and revives | A time cost (reviving takes seconds), never a failure in itself |
| Secrets and side areas found | A bonus, which ties scoring to exploration |
| Property damage (contract-sorcery fiction) | A deduction, capped |

**Rules:**
- **Par is computed by the generator** from the critical-path length and the enemy budget.
  Procedural maps then have fair thresholds, and a good team's star count doesn't swing
  with the seed.
- **Thresholds:** 1 star means you finished. 2 stars means you worked together, the
  target a decent team hits every time. 3 stars means a well-oiled crew.
- **Chaos costs score, never the run.** Accidents make you *slower and hurt*; they never
  wipe the team.
- **The end screen tells the story.** Show the stars plus a highlights reel: "Most
  accidental casts: Fox (4)", "Friendly fire dealt: Bear, 312", "Fastest revive", "Best
  unison". The groan becomes a laugh after the fact.

## 5. Art direction from the concept art

The art **fits the contract-sorcery bunker pitch** (`pitch-contract-sorcery.md`): a
luxury modern interior invaded by demons, and a scrappy crew doing the job. Costume
and prop details in the image that suggest a different theme are ignored; only the mood,
lighting and chaos carry over.

- **Illustrated comic look:** bold outlines, flat toon shading in 2–3 bands, chunky
  readable shapes, and expressive silhouettes.
- **Warm vs cool:**
  - The interior is warm: amber practical lamps, wood, marble and brass.
  - The magic is cool: cyan and violet glows with bloom.
  - Spells pop because they're the only cool light in a warm room.
- **A glowing hex floor:** emissive lines along the hex edges. It's gorgeous, and it also
  makes the grid and the **height changes** readable, since the glow breaks at each level
  step.
- **Popcorn bursts:** corn's explosion is a puffy white-and-yellow burst, the signature
  comedy FX.
- **Imps:** small, grinning, red-orange demons that read instantly as the swarmer and
  grunt archetypes.
- **The crew:** scrappy contractors with improvised gear (taped-together wands, hard hats,
  mismatched armor, tool belts). Each has one team color.

**How to get there from the prototype:**
1. A toon ramp shader on actors and props, plus an outline pass: inverted-hull outlines on
   characters, and a screen-space edge pass for the level.
2. The lighting split: a warm key light and warm ambient, with spells as cool emissive and
   `WorldEnvironment` glow enabled.
3. The hex-edge emissive floor shader. This is the cheapest high-impact change and it
   improves height readability straight away.
4. Swap the grey prototype palette for warm interior materials. Keep the rule that spells
   are the only cool, saturated colors.
5. Stylized silhouettes for heroes and imps before any texture detail.

## 6. Decision filter

Ask of every new feature, spell, enemy or system:

- [ ] Does the chaos come from **players**, not dice?
- [ ] Can the team tell **what happened and who caused it** within a second?
- [ ] Can a coordinated team **reliably play around it**?
- [ ] Does it give the team **something to say to each other**?
- [ ] Is the worst case **recoverable**, so it costs score rather than ending the run?
- [ ] Is it **funny when it goes wrong**?
- [ ] Does it serve **exploration** or **spoken-spell combat**?
- [ ] Does it respect the recognizer's reality? Misses must be free, and it has to work
      within a ~0.3–0.6 s recognition delay.

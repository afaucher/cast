# Spell roster

Status: 2026-10-17. Every spell lands where the caster aims (the same point the ranged attack goes),
and the aim snaps onto a teammate near the cursor. **[decided]** marks the user's calls;
**[proposal]** marks suggestions still waiting on the user.

| Spell | Say | Effect | Hits | State |
|---|---|---|---|---|
| Heal | cast heal | A burst heal at the aim point | heroes | in game |
| Fireball | cast fireball | A projectile that explodes at the aim point; anyone near the blast may catch fire (see Burning) | monsters (damage), **everyone** (fire) | in game |
| Armor | cast armor | A zone at the aim point where heroes take less damage | heroes | in game |
| Corn | cast corn | A corn bomb drops from the sky | **everyone** | in game |
| Tentacles | cast tentacles | Neon-purple tentacles burst from the floor in an oval lying across your aim, shove everything outward, then stay up 4–6 s swatting anyone inside back out | **everyone** (shoves), monsters (a little damage, every swat) | in game |
| Teeth | cast teeth | "Too many teeth" sprout out of everyone in the area, grow for 1–2 s, then explode | **everyone** | in game |
| Vines | cast vines | Thorny vines root everyone in the area for ~2 s: no walking, no shoving, attacks still work | **everyone** | in game |
| Damp | cast damp | A wide soggy area: fires go out, nobody can ignite for 15 s, puddles make shoves slide further | **everyone** | in game |
| Coffee | cast coffee | +60% move and attack speed for 6 s, twitchy, then a 2 s crash (−30%); a downed ally gets up as a gray, leaking zombie | **everyone** in a small radius | in game |
| Chicken | cast chicken | Four chickens scatter from the aim point for 12 s and peck everything for zero; a pecked monster chases its chicken | **everyone** (pecks for 0); monsters turn on them | in game |
| Revive | cast revive | Stands every downed ally in a small radius back up at half health; lifts a coffee zombie's curse | heroes (the downed, and zombies) | in game |

## Tentacles [in game; reshaped 2026-10-27]
**"Cast tentacles":** neon-purple tentacles burst from the floor at the aim point and shove **everyone** out, then stay up
swatting. Code: `scripts/spells/tentacles.gd` (the spell, a scheduled effect), `tentacles_fx.gd` (the look),
`defs/tentacles.gd` (the numbers). Tests: `tests/test_spell_tentacles.gd`, and in a crew `tests/test_net_m4_status.gd`.

Playtest feedback item 2 ("most useful in hallways to break up a rush. Maybe like a wall or a push from the player
outward"). Asked "How do we expect the player to use it? Defensively?" and offered a sideways tentacle wall pushing away
from the caster, the user said (2026-10-27): **"Let's just increase the duration and that swatting behavior. Let's
consider increasing the width of the area but not the depth. Again with strength."** and then "Build" on the spec below.

- **Shape [decided]:** an oval lying **sideways across the caster's line of aim** (caster -> target, flat; the caster's
  facing when it stands on the target). Its depth half-axis, along the aim, is the old radius: 2.2 + 0.8 × power (2.2 to
  3.0). Its width half-axis, across the aim, is the depth × (1.2 + 0.3 × power): about 2.7 at minimum power, 4.5 at full (2026-10-28, below).
  Aimed down a hall, the oval spans the hall wall to wall. A body counts when any of it is inside.
- **Burst (as before):** after the 0.25 s telegraph everyone inside is shoved directly away from the centre, 2.5 + 1.5 ×
  power (4.0 at full); monsters and breakables (mail) take 6 × power. A pavise's planks facing the centre block it; floor
  cracks over the oval (three Grime marks along its width); one burst of noise for the monsters.
- **Duration [decided]:** the tentacles stay up **4 s at minimum power to 6 s at full** (4 + 2 × power) after the burst,
  then retract over 0.8 s.
- **Swats [decided]:** every **0.6 s** while up (at the cast's moment + 0.25 + k × 0.6, on the shared clock: 6 swats at
  minimum power, 9 at full) everyone inside the oval, monsters **and** heroes and the caster, is swatted out of the oval's
  **nearest edge**: a shove of 1.5 + 0.5 × power (2.0 at full). Across this wide oval that is mostly along the aim: a body
  on the caster's side of the middle goes back toward the caster, one beyond it on away; near an end of the width it goes
  out of that end. Monsters and breakables take 6 × power at every swat. No noise per swat.
- **Unchanged:** cooldown 10 s, the word, Neon ichor, and the description on the spell's card.
- **Look:** a purple telegraph oval, then about 8 tentacles per radius-3 circle's worth of area (16 at full power, 6 to
  18) spread over the oval, each leaning toward its nearest edge; they whip out with the burst, wave while up, lash out on
  every swat (drawn back just before it) and sink away at the end. A faint neon rim marks the oval's edge the whole time and
  flares on each swat. Cosmetic only, on the same clock (`GameWorld.fx_rng` for the jitter).
- **Aim reticle:** while Tentacles is the held spell, the aim ring shows its full-power oval round the landing point, turned
  across the line of aim as the cast will lay it (`AimReticle`; the power is not known until it is spoken).
- **Co-op:** the aim travels in the cast event (`TentaclesSpell.cast_extra` -> NetCasts' `x`, the `aim` SPAWN var), so every
  machine lays the same oval from the same moment; each machine applies only the shoves and damage it resolves
  (`Combat.hits_in_radius` filtered to the oval: a hero's by its owner, the rest by the caster's machine).
- **Watch for (playtest):** a swat is long enough (over `Actor.WALL_SLAM_MIN_SHOVE`, 1.0) to **slam** a body pinned
  against a wall inside the oval: 8 damage and a stagger per swat, on top of the swat's 6 × power for a monster. A
  monster pinned for all nine swats of a full cast takes up to about 140 with the burst; a teammate pinned there can drop to 1 HP (a hero's
  shove never downs a hero). In the crew test a hero standing near a wall was swatted on all nine ticks.
  Decision (2026-10-27): offered "swats skip wall slams" and a new desc ("... then keep swatting anyone inside for a few
  seconds"), the user said "Leave both as is": swats keep slamming, and the desc stays as it was.
- **Floor only, narrower [decided] (2026-10-28):** after the gym, the user: "I think we scaled it up too much. It is MUCH
  bigger then hallways now and spawns tenticles in the walls. Maybe we can limit it to just the floor space?" and picked
  the width 1.2 to 1.5 × depth (about 2.7 to 4.5 half-width; it was 1.4 to 2.0, 12 across at full) and "Yes, visuals and
  hits". A spot counts only when it is floor (not wall, not void) and a line 0.9 above the floor reaches it from the centre
  without passing through a wall (`Tentacles.reaches`): tentacles grow only there, and only bodies standing there are
  shoved, swatted or hurt, so nothing reaches into the next room. The telegraph oval and rim are still drawn whole.

## Teeth [decided: core idea]
**"Cast teeth":** too many teeth sprout out of **anyone** in the area at the aim point, monsters and
heroes alike. They grow for **1–2 s**, then explode.

Details [proposal]:
- **Area:** radius 2.0 + 0.6 × power around the resolved aim point. Everyone inside at cast time is
  afflicted.
- **Growth:** 1–2 s. Stronger casts grow faster: 2.0 s at low power, 1.0 s at full power. That's
  also the counterplay window, and it reads clearly as a ticking bomb on each victim.
- **Pop:** the carrier takes 25 × power. Everyone within 1.5 of the carrier (any team) takes 10 ×
  power plus a mild shove outward (uses the shove system). Pops can chain into a satisfying mess in
  a packed room.
- **Co-op chaos:**
  - Teammates near an afflicted hero should scatter, which gives the "Overcooked" moment of everyone
    running away from Gasket.
  - Afflicted heroes may run toward monsters to share the pop.
  - Friendly fire never downs a hero; heroes end at 1 HP at worst, as with the other everyone-spells.
- **Synergy:** a **heal** cast on an afflicted ally pulls the teeth before they pop (the dentist).
- **Look:** clusters of oversized faceted white teeth (molars, fangs, a few gold fillings) push out
  of the body and swell, jittering faster as the pop nears. They burst into tumbling teeth and
  sparkles. It works on every model because the teeth attach to the actor, not the mesh.
- **Voice risk:** "teeth" is short (one syllable), and the recognizer may hear "tea", "tease",
  "these" or "teach". Measure it with text-to-speech clips like tentacles, and only add aliases that
  show up in testing. "Teeth" is rare in chatter. Under loose mode it needs the trigger, so
  accidents should be rare. Corn remains the only spell that fires on a bare mention.
- **Cooldown:** 12 s, the same tier as corn. A material-component source (an imp jaw?) is to be
  decided with the drop table in `spells-and-components.md`.

## Burning [in game, 2026-10-17]
A fireball blast can set anyone near it on fire. It is a status node (`scripts/spells/burning.gd`, `class_name
Burning`) attached as a child of the actor. Damp is built on it (see "Damp" below).

- **Ignite:** when a fireball explodes, every actor in the blast (monsters, heroes, employees: friendly fire
  included, since aiming at a teammate is the game) rolls to ignite. `IGNITE_CHANCE` is **35%** at the centre of
  a full-power fireball, falling to 60% of that at the rim (`EDGE_CHANCE_MULT`) and to 60% of that at minimum
  power (`LOW_POWER_MULT`). The roll uses `GameWorld.rng`, so a seeded run is repeatable.
- **Who can't burn:** hellgates, priced props and mail packages (inanimate), the dead and the downed, and
  anything fireproof or soaked (below). Rebar can burn even though he is immovable.
- **Burn:** 5 to 10 s (random), `TICK_DAMAGE` 1.5 every 0.5 s, so **15 to 30 HP** over a full burn. Armor and
  other damage modifiers apply. That never kills a full-HP hero (Wick, the frailest, has 85) but it finishes a
  swarmer (12) or an archer (25), and an employee (30) can burn to death. The blast already hurts employees
  more than that, so we accept it. A hero's fire never takes a hero below 1 HP, like the other
  everyone-spells. The damage is dealt through `Actor.apply_damage` with the caster as the source, so kill
  credit and ledger attribution work.
- **Refresh, not stack:** igniting a burning actor sets the end to the longer of what is left and the new
  duration (and adopts the new culprit). Damage never stacks.
- **No spread:** no contact spread, no aura. Only a fireball blast ignites.
- **Stops:** on burn-out, on death or downing, on extinguish. A heal does **not** put it out.
- **Look:** 8 faceted orange and yellow flames flicker around the body and lick up from the head, with a small
  warm light, embers on each tick and a scorch mark on the floor every 3 s (`Grime`, fades after 30 s). The
  flames are built once per fire from shared meshes and materials; the flicker only edits transforms. Look-dev
  scene: `scenes/burning_lab.tscn` (`--scene res://scenes/burning_lab.tscn --shot <png>`).

**API (used by Damp and other spells):**
```gdscript
Burning.ignite(actor, source, duration) -> Burning   # null if it cannot burn
Burning.is_burning(actor)  /  Burning.remaining(actor)
Burning.extinguish(actor) -> bool                    # put it out
Burning.extinguish_in_radius(pos, radius, team = -1) -> int
Burning.soak(actor, seconds)                         # extinguish AND no ignition until dry (the "damp" status)
Burning.set_fireproof(actor, on)                     # permanent: group "fireproof"
Burning.is_soaked(actor)  /  Burning.soaked_left(actor)   # damp, and for how long
```
Every live fire is in the group `burning`, and `Burning.ended(reason)` says why it stopped (`burnt_out`,
`extinguished`, `died`).

**How Damp uses it:** a Damp cast calls `Burning.extinguish_in_radius` over its area and `Burning.soak(actor,
seconds)` on everyone in it (through `Wet.douse`), so damp actors cannot ignite until they dry. A fireball blast on a
soaked actor shows "FIZZLE" and a puff of steam, and rolls no dice (the rng stream is unchanged). Tests:
`tests/test_burning.gd`, `tests/test_spell_damp.gd`.

## Vines [in game, 2026-10-17]
**"Cast vines":** thorny vines burst out of the floor at the aim point and **root everyone** in the area (heroes, the
caster if inside, monsters, employees) for about two seconds. Code: `scripts/spells/vines.gd` (the spell),
`vines_fx.gd` (the burst), `vine_wrap.gd` (the wrap on each rooted actor). Tests: `tests/test_spell_vines.gd`.

- **Area and time:** radius 2.4 + 0.6 × power (2.4 to 3.0), root 1.6 + 0.6 × power seconds (1.6 to 2.2), after a 0.3 s
  telegraph. Cooldown 10 s. No damage.
- **Root:** the `vines` modifier with `Actor.STAT_ROOT` (see "Speed modifiers" below). A rooted actor **cannot walk**
  (`Actor.move` does nothing and `effective_speed()` is 0) and **cannot be shoved**: `Actor.shove` returns at once, so
  tentacles, the bowl, the spin, a hero's or a monster's melee nudge, the brute's slam, a teeth pop's shove, a
  hellgate's shove and a shove into a priced prop all do nothing to it. The damage those attacks also deal still
  lands. It can still **attack and cast**, and it can turn.
- **Re-casting** refreshes the root (the same id never stacks). A slide already in progress is not cancelled.
- **Friendly fire:** vines root teammates (aim at a fleeing friend next to a teeth carrier) and do not hurt them.
- **Combos:** vines then **teeth**, and nobody escapes the pop (friends included); vines are the counter to your own
  shove spells; a hasted actor in vines is still rooted, and the haste is waiting when the roots let go.
- **Look:** a variant of the tentacles kit: 11 short green faceted vines, curled at the tips and studded with pale
  thorns, sprout across the area, sway while the roots hold and sink away after. Each rooted actor wears two thorny
  strands spiralling up its legs (`VineWrap`, which grows, sways and withers with the modifier).
- **Component:** a **seed pod** (a split green pod with pale seeds and a curled tendril). Drops from archers (8%).
  Spa planters are the planned environment source (no planters exist yet).
- **Voice:** "VINES" is heard for nearly every clip; see the measured results in `scripts/voice/incantation.gd`.

## Damp [in game, 2026-10-17]
**"Cast damp":** a wide area gets soggy. Code: `scripts/spells/damp.gd` (the spell and its puddle field), `wet.gd`
(the status look), `Burning` (above) and a `puddle` Grime mark. Tests: `tests/test_spell_damp.gd`.

- **Area:** radius 4.0 + 1.0 × power (4.0 to 5.0), wider than tentacles. Cooldown 10 s, 0.2 s telegraph. No damage.
- **Fire:** every fire in the area goes out (`Burning.extinguish_in_radius`), any team.
- **Soak:** everyone in the area is soaked for **15 s** (`Wet.douse` → `Burning.soak`): they **cannot ignite** until
  dry, so a **fireball blast on soaked actors fizzles**. A shorter second dose never cuts the damp short.
- **Wet floor:** most hex cells in the area (80%, and the middle ones always) become puddles for **24 s**, drying
  over the last 8 s. A shove that starts on a wet cell goes up to **+50% further** (`Damp.slide_mult`, which
  `Actor.shove` asks): tentacles, the bowl, the spin, melee and teeth all slide further on a puddle. The bonus fades
  as the puddles dry. Which cells are wet is a pure function of (centre, radius, cast stamp), so no list is sent.
- **Grime:** one `Grime.WET` decal per wet cell (a new `puddle` tile in the atlas). It fades by itself inside the 30 s
  player-mark rule, and the wet floor ends first, at 24 s.
- **Look:** a drizzle of droplets falls over the area inside a cyan ring. Soaked actors **drip** (a small particle
  emitter at the body) and leave **wet footprints** that fade over 3.5 s. Inanimate things (hellgates, priced props,
  mail packages) are soaked but do not drip.
- **Combos:** **+ fire** puts out a fireball's burn and soaks you against the next blast (it answers your team's own
  fire); **+ shoves** a wet floor slides everything further. Planned: wet footprints reveal ghosts, and server-room
  sparks electrify puddles.
- **Component:** a **soggy sponge**. Drops from grunts (6%); a leaky pipe is the planned environment source.
- **Voice:** "DAMP" is heard cleanly. "damn" is not an alias (see the voice notes in `incantation.gd`).

## Coffee [in game, 2026-10-17]
**"Cast coffee":** haste, then a crash. Code: `scripts/spells/coffee.gd`, and the speed system in `Actor`. Tests:
`tests/test_spell_coffee.gd`.

- **Area:** a **small** radius, 1.5 + 0.5 × power (1.5 to 2.0). Everyone in it is caffeinated: heroes, the caster if
  inside, **monsters** ("caffeinate the swarmers by accident") and employees. Cooldown 14 s. Immediate, no telegraph.
- **Haste:** **+60% move speed and +60% attack speed** for 4.5 + 1.5 × power seconds (**6 s** at full power). Attack
  speed divides every attack cooldown: a hero's melee, bolt, bowl, spin and arrow **and the bow's draw time** (Wick's
  draw gets faster), and a monster's strike cooldown. **Spell cooldowns are not sped up** (coffee is about the body,
  not the voice).
- **Twitchy:** the **local player** gets a slight **aim wobble** (up to 0.06 rad, about 3.4°, two slow sines of the game
  clock, so no random numbers) on melee, shots and voice casts. **AI allies, monsters and employees** take tiny random
  steps instead (about 0.22 units, every 0.35 to 0.8 s, rolled on `GameWorld.rng`, never while winding up an attack,
  rooted or helpless).
- **Crash:** then **−30% move and attack speed for 2 s**. Drinking again refreshes the haste to the longer time and
  cancels a crash (no stacking).
- **Combos:** **Wick's draw** (a faster draw, jittery aim); **vines** (rooted wins; the haste resumes after); a
  **goo slow** (the speeds multiply, 1.6 × 0.5 = 0.8).
- **Look:** steam wisps curl off the head while it lasts, "COFFEE!" and "crash..." float up, and a ring and a burst
  of beans mark the cast.
- **The coffee zombie [decided, user, 2026-10-27]:** "I think I want two different ways to revive. One coffee should bring
  you back but leave you grayscale. With minimum health. And a slow health leak. Basically you're a walking zombie. You
  could be healed. But if your health drops to zero again, you fall down again." and "So the combination would be coffee
  plus heal to get you back in the game." Then the numbers: a 75% cure, 10 HP, 1.5 HP/s.
  - A **downed** hero inside the radius stands up at **10 HP** (`CoffeeSpell.ZOMBIE_HP`) as a **zombie** (`Hero.zombie`):
    the model stays **grayscale** (the downed look, `LowPolyModel.set_gray`) but stands, walks, attacks and casts as
    normal, and it **leaks 1.5 HP a second** (`ZOMBIE_LEAK`; straight off the HP: a curse, not a hit, so armor does not
    slow it and nothing flashes).
  - **Heals work** as on anyone. Healed to **75% of max HP or more** (`ZOMBIE_CURE`) the curse lifts at once: the colour
    comes back and the leak stops. One full heal (35) takes a fresh zombie to about 45, so it is coffee **plus two heals**
    (or a Revive, below) to be whole again.
  - At **0 HP** a zombie goes down again as usual, and another coffee makes a new zombie.
  - The one it stood up gets **no haste and no crash** from that cup (the living drink first); live allies and monsters in
    the splash are caffeinated as ever. A zombie standing in a later coffee is a live ally and gets hasted.
  - Coffee's aim snaps onto a downed teammate's body too (`SNAPS_DOWNED`), and the aim ring hugs the body while coffee or
    Revive is the held spell. A body left on the floor above (hidden on arrival) is not there to stand up.
  - The approved description: "Everyone in a small radius gets +60% move and attack speed for six seconds, twitchy, then a
    crash. Monsters too. A downed ally gets up gray, leaking health, until healed past three quarters."
  - A zombie who takes the elevator arrives a zombie (the floor carry keeps the curse). The end-of-floor revival fee bills
    only whoever is down when the contract ends (contracts.md 9).
  - Networking: getting up is the verb `Actor.revive(hp, cursed)`, applied by the hero's OWNER (`Combat.revive_radius` asks
    `Net.resolves`, like a heal); the zombie flag is an `OWNER` var on the hero snapshot (the hp field's top bit,
    `NetCodec.HERO_FIELDS`), so every screen shows the gray from it and only the owner runs the leak. A puppet stands up when
    its owner's snapshot says it is no longer down (`Hero.net_stand_up`). A late joiner gets it in the heroes of the join
    snapshot, then from the stream. Tests: `tests/test_spell_revive.gd`, `tests/test_net_revive.gd`.
- **Component:** **coffee beans** (three roasted beans with their grooves). Drops from brutes (10%). The break room and
  a reward for protecting employees are the planned environment sources.
- **Voice:** one speaker's "cast coffee" is often written "COUGHING": that and "cough" are aliased, below the bare
  floor (see `incantation.gd`).

## Chicken [in game, 2026-10-18]
**"Cast chicken"** (decided by the user, 2026-10-18): "chickens run around and do zero damage attacks to everything,
distracting them." Code: `scripts/spells/chicken.gd` (the bird and its AI), `scripts/art/lowpoly/chicken_model.gd` (the
model), `scripts/fx/chicken_fx.gd` (the feathers), `ChickenSpell.cast` (`scripts/spells/defs/chicken.gd`). Tests: `tests/test_chicken.gd`,
`tests/test_net_chicken.gd`. Look-dev: `scenes/new_spells_lab.tscn --spell chicken` (`--closeup`, `--pickup`).

- **The flock [decided]:** one cast makes **4 chickens** that burst out of a feather cloud at the aim point, each its own
  way (0.6 s at 1.5x speed). Each lasts **12 s**, then puffs up for 0.35 s and **poofs into feathers**, if nothing killed it
  first. Power does not change the flock. Cooldown **14 s** (armor and coffee's tier: it is crowd control).
- **Running about:** speed 3.6 (a grunt walks 3.2, an imp 5.5). A chicken wanders erratically (a new heading every 0.25 to
  0.7 s, now and then a short stop) and drifts back toward where it was cast if it strays more than 5.5. Every 0.3 s it
  looks for something to peck: the **nearest monster within 4.5** first, else the **nearest anything within 2.5** (heroes,
  employees, priced props, mail, crates, gates; never another chicken). It runs at it wobbling, pulls its head back for
  0.22 s and pecks, then hops off (0.15 to 0.45 s, so a slow monster sometimes gets its swing in) and comes back for more,
  about one peck a second (0.9 s, x0.85 to 1.2; coffee speeds it up).
- **Pecks do zero [decided]:** a peck is a hit for nothing. It goes through its own verb, `Actor.peck(source)`, applied
  where hits resolve (`Combat.peck`, `Net.resolves_hit`). `apply_damage` ignores amounts of 0 on purpose and every
  `damaged` listener assumes real damage (a prop's bill and dent, a mail box breaking, an employee's panic, a monster's
  shout), so a zero hit through it would either do nothing or set all of those off; the smallest honest alternative is a
  verb of its own that touches none of them. Every screen shows a **"0"** (in the hit colour of the victim's side), a
  flash and a puff of feathers at the beak. No Ledger line, no break, no panic, no stagger, no shove.
- **A pecked monster turns on its chicken [decided]:** `Monster._on_pecked` makes the chicken its target over any hero for
  **4 s** (`Monster.TAUNT_TIME`), each peck restarting it, or until the chicken dies. Only the pecked monster turns: no shout,
  no pack alert. A second chicken's peck only keeps the chase going. When it is over the monster goes back to the nearest
  hero (or home). Its leash still holds.
- **Fragile [decided: one or two hits from anything]:** 20 HP, and every hit takes at least 10 (`Chicken.HIT_FLOOR`), so
  one or two hits kill it in a feather explosion ("BAWK!"). That covers a monster's swing (any monster's swing catches a
  chicken in its arc; a brute's slam, which is for heroes, still lands on the chicken it chases), an arrow, a fireball (its
  blast hits neutrals), corn, teeth, a fire (a burning chicken lasts two ticks), a wall slam, and **the crew's own swings,
  bolts and arrows** (`Chicken.WEAPONS_HIT`, true: swatting your own chicken while hitting the monster it pulled is
  player-caused chaos; set it false to have only the monsters' attacks hit chickens). Tentacles and the bowl shove
  chickens about (light: shove x1.6) without hurting them. A grunt that a chicken pecks turns on it within about 1.5 s
  and kills it about 3.5 s later (`tests/test_chicken.gd`).
- **Look:** a plump white hen, as big as an imp (a real one would be half that and unreadable at the game's zoom), with a
  big red comb and wattle, an orange beak and legs and a cocked tail. White and round with a red top, so a flock never
  reads as the purple, spiky imps. It trots with a bob, jerks its head from pose to pose, winds its head back and plunges
  it to peck, and beats its wings when it flaps off. Feathers are tumbling flat blades (white, cream, a few rust).
- **Component:** **Chicken feather** (a long white tail feather with a rust-red tip). Drops from **imps (4% each)**; imps
  come in packs. A mail package can hold one too.
- **Networking (the "owned actor" shape, host-owned like a monster):** the cast is an event that lands on every machine
  (`NetCasts.LEAD`); every screen shows the feather cloud, and **only the host spawns the flock** and runs it (rolls on
  `GameWorld.rng`). `NetWorld` announces each chicken as a runtime spawn (`world.spawn`, kind "chicken"), streams it as a
  monster-format entry (it is the first runtime actor, `NetWorldCodec.RUNTIME_ACTORS`: state, the peck's wind-up, the
  peck count) and its death as
  `world.die`. A client shows puppets that play the same pecks (the "0" on whatever its screen shows the chicken pecking),
  flaps and poof. A client's hit on a chicken is a request the host applies. Pecks change nothing a client owns (a hero
  shrugs), so nothing about them travels. A late joiner gets the chickens as runtime spawns plus the keyframe.
- **Voice:** "chicken" (and "chickens") is in the vocabulary; see the CHICKEN note in `scripts/voice/incantation.gd` for
  what the recognizer writes.
- **Sound (2026-10-25):** the user's five recorded clucks, the `chicken_cluck` pool (`Chicken.cluck`, cosmetic, every
  screen from the chicken it shows): one per chicken as the flock lands (staggered 0.05-0.45 s), one on each peck, and
  one now and then (every 2-5 s); the cue's two voices and 0.18 s gap cap a pecking flock (audio-plan.md "War cries").
  Not built: a squawk in `ChickenFx.feather_explosion` and a soft pop in `ChickenFx.poof`.

## Revive [in game, 2026-10-27]
**"Cast revive"** (decided by the user, 2026-10-27): "We should also have a dedicated revive spell which brings you back
about half health and it doesn't have this zombie curse effect. The revive spells should be a plant leaf or something."
Then: the spell is **Revive**, the word **"revive"**, the component an **Aloe leaf**. It is the clean way back; coffee's
zombie (above) is the cheap one. Code: `ReviveSpell` (`scripts/spells/defs/revive.gd`), the verb `Actor.revive`,
`Combat.revive_radius`, `GameWorld.downed_in_radius`, the look `ReviveFx` (`scripts/fx/revive_fx.gd`). Tests:
`tests/test_spell_revive.gd`, `tests/test_net_revive.gd` (two machines).

- **Effect:** every **downed** ally within **1.5 + 0.5 × power** (1.5 to 2.0, coffee's small radius: you point at the body)
  stands up at **50% of max HP** (`REVIVE_HP`), with **no zombie curse**. On a **coffee zombie** it lifts the curse (colour
  back, no leak) and brings the HP up to at least 50% (a zombie already above half keeps what it has). A standing hero who is
  not a zombie is untouched (it is not a heal). Monsters and staff never get up: only heroes lie downed.
- **Aim:** a support spell like heal (`FOLLOWS`): the aim snaps onto a teammate, a **downed** one included (`SNAPS_DOWNED`;
  the aim ring hugs the body while Revive is held).
- **Cooldown 12 s** [proposal]: heal's rate of HP back (heal 35 per 8 s, Revive 50 per 12 s, about 4 HP a second each), the
  corn and teeth tier, a little under coffee's 14 s, so the clean revive is not slower than the zombie one. The real budget
  is the Aloe leaves (charges).
- **The approved description:** "Stands a downed ally back up at half health. Point at them."
- **Look:** aloe-green leaf blades burst up and tumble down, pale motes rise and two hex rings lift off the floor at the
  radius (every cast, hit or miss). A hero who gets up (Revive or coffee) throws a puff of leaves (gray and coffee-brown for
  a zombie) and plays the hop's cue (`jump`: Revive has no sound of its own, no new audio); a zombie cured throws a green
  sparkle. No floating text.
- **Component:** the **Aloe leaf** (a fat, fleshy leaf curling to a point, pale teeth along both edges, pale flecks, the
  gel at the cut). Drops from the **Water Boy** (the enemy medic, floors 2-3) at 12% [proposal]; a mail package can hold
  one too.
- **Networking:** the shape is a status applied by the target's owner (like heal and coffee). The cast is an event that lands
  on every machine at the same moment; each machine stands up only the heroes it owns (`Net.resolves`: a player's own hero,
  the host's AI seats), so a client's Revive at the host's AI is applied on the host and a host's coffee at a client's
  hero on that client. The other screens see the hero stand from its owner's snapshot (`dead` false, the HP, the zombie
  flag). No new event, no request. Randomness: none.
- **AI allies** do not cast spells (`AllyBrain`: "Allies do not cast spells in the POC"), so they neither Revive nor coffee
  the downed; solo is unchanged (you down = crew down).
- **Voice:** "revive" (and "revives") is in the vocabulary. Measured with TTS (David + Zira, 2026-10-27): 12 of 12
  deliberate clips fire revive and nothing else (0.95 to 1.00), no other clip fires it, and "arrive", "relive", "reviews",
  "survive", "rival" and "revival" never cast; "revive me" / "I need a revive" cast in chaos only. Details: the REVIVE note
  in `scripts/voice/incantation.gd`; clips in `tools/make_voice_clips.ps1`.

### Speed modifiers (`Actor.set_modifier`)
One verb, four stats, built for coffee and ready for goo slows:
```gdscript
actor.set_modifier(id, mult, duration, stat = Actor.STAT_DAMAGE_TAKEN)   # same id refreshes, never stacks
actor.clear_modifier(id)
# stats: STAT_DAMAGE_TAKEN (armor 0.4), STAT_MOVE_SPEED, STAT_ATTACK_RATE, STAT_ROOT (presence = rooted)
actor.move_speed_mult()  /  actor.effective_speed()        # move_speed x modifiers, 0 while rooted
actor.attack_rate_mult()  /  actor.scaled_cooldown(base)   # base / rate
actor.is_rooted()  /  actor.modifier_left(id)
Combat.modify_radius(pos, radius, id, mult, duration, stat)   # an area applies it to everyone in range
```
- **Stacking:** the modifiers of one stat **multiply** (haste 1.6 × goo 0.5 = 0.8), so independent sources combine and
  none replaces another. The same id refreshes.
- **Clamps:** move speed 0.2 to 2.5, attack rate 0.25 to 3.0, so a pile of slows never freezes an actor and a pile of
  haste never rockets one. Standing still is what a **root** is for, and it overrides every speed.
- Old callers are unchanged: `set_modifier("armor", 0.5, 10.0)` is still damage taken. Movement code reads
  `effective_speed()` (never `move_speed`, which stays the base a kit or the AI sets) and attacks read
  `scaled_cooldown()`.

## Brainstorm: next spells [proposal, 2026-10-16]
These are user ideas, thought through but not built. (Vines, Damp and Coffee were built on 2026-10-17: see their sections above.) Unless noted, every spell lands at the aim point
and follows the area rule: area spells hit **everyone** inside, except heal and armor.

| Spell | Effect | Hits | Chaos / co-op angle | Voice risk |
|---|---|---|---|---|
| **Wind** | A directional gust from the caster toward the aim point: a cone that shoves everything along it 2–3 hexes, with a whoosh and dust streaks | everyone in the cone | Blow monsters off ledges and into pits, or a friend off the crate tower. It differs from tentacles (radial, from the floor) because it's aimed and linear. | medium: "when", "win", "wine" (a wine cellar exists) |
| **Blind** | A dark cloud. Anyone inside can't see for ~2–3 s. Monsters lose their target and swing at random; a hero gets a brief black-edged, pinhole screen effect. | everyone in the area | Blinding a teammate is the misplay. Blinding the brute mid-windup makes its slam go off in a random direction. | medium: "behind", "blond", "blend" |
| **Ghost** | **Single target:** the actor nearest the aim point (a teammate, yourself, or an ENEMY; it falls back to the caster) becomes nearly invisible for ~4 s. Its own attack breaks it early. | one actor | On a hero: monsters drop aggro, which makes it a rescue or escape tool, and the ghost passes through actors. **On an enemy it's simply dumb [decided]:** the monster is nearly invisible to your side (a faint shimmer, no HP bar or windup glow), keeps fighting normally, and AI allies lose it. There's no upside; it's the corn of single-target spells. | medium: "goes", "go", "host", "post" |

**Combos** (the ones for the built spells are in their sections above):
- **Damp + ghost:** wet footprints reveal ghosts, enemy-ghost misplays included.
- **Damp + server-room sparks:** electrified puddles become a hazard.
- **Wind + wet floor:** wind shoves slide further on puddles (it uses the same `Actor.shove` factor), and rooted actors ignore it like every shove.
- **Blind + brute:** its slam fires blind, maybe into its own swarmers.
- **Ghost + employees** (`contracts.md`): ghost an employee past a hellgate.

**Component ideas** (extending `spells-and-components.md`):

| Spell | Component | Source |
|---|---|---|
| Wind | feather or fan blade | archer |
| Blind | ink sac or bat wing | a new enemy |
| Ghost | ectoplasm | a future ghost enemy |

**Suggested build order** (Vines, Coffee and Damp are built):
1. **Wind** is almost free: an aimed cone on top of the existing shove system. It already slides further on Damp's puddles and ignores rooted actors.
2. **Ghost** needs visibility and aggro rules (monsters losing targets).
3. **Blind** shares that aggro work, plus a screen effect.

### Mercurio Retrogrado: "Everything Goes Wrong" [parked, 2026-10-17]
"cast mercurio retrogrado" is two Spanish words for an English-only speech model, so it should be near impossible to
say. The reward is overpowered. The user picked this idea (#3 of six) and parked it with the other spells.

**Single target:** whoever the aim ring is on. Enemies get a long, brutal bad week; a teammate (a misfire, or
aiming at yourself) gets a short, funny one that never takes control away.

| Effect | On an enemy (20 s) | On a player (8 s) |
|---|---|---|
| Attacks | half its swings and shots whiff; a whiffed swing can hit a neighbouring monster, a whiffed arrow veers into the pack | 1 in 4 attacks whiffs; a miss never hurts a teammate |
| Communication (Mercury's domain) | it "mishears" orders: walks the wrong way for a beat, loses its target | **voice casts come out wrong:** "cast heal" fires a random other slotted spell |
| Footing | trips every 3–4 s (0.6 s stun); its climbs fail (+2 steps become walls) | trips once or twice (a stagger, no stun, no damage) |
| Damage taken | +50% from everything | none |
| Shoves | pushed twice as far; a prop it gets knocked into bills "Act of Mercury: $0" | normal |
| Look | a swirling ☿℞ glyph overhead, outline flickering like a bad signal | the same glyph, and the HUD subtitle "Mercury is in retrograde" |

**Edge cases:**
- **Hellgate:** you can't curse the gate; for 20 s everything it spawns comes out stumbling and cursed for 5 s.
- **Swarmers:** the curse spreads to the target's swarm.
- **Employees:** a cursed one wanders off and waits somewhere wrong.
- **Heal:** halves the time left on a player and does nothing for enemies.
- **Bosses:** half duration.

**Open questions:**
1. Is the voice swap on cursed players in?
2. Enemy damage taken: +50%, or double?
3. Are the durations right?
4. Is "Act of Mercury" free property damage in?

**Build notes:**
- A status node like `Burning` (`scripts/spells/burning.gd`).
- Test the phrase with recorded clips: hard but learnable. Add sound-alikes such as "MERCURY RETRO GRADO".
- A ~90 s cooldown and a rare component (a quicksilver vial).

**Other ideas considered:**
1. Return to Sender: rewind the target into its gate.
2. Miscommunication: it fights for you, then pops.
4. Planetary Alignment: an orbit-and-slam nuke.
5. Exes Return: replay every hit it took, doubled.
6. Refund: delete it and get paid its bounty.

# Spell roster

Status: 2026-10-16. Every spell lands where the caster aims (the same point the ranged attack goes),
and the aim snaps onto a teammate near the cursor. **[decided]** marks the user's calls;
**[proposal]** marks suggestions still waiting on the user.

| Spell | Say | Effect | Hits | State |
|---|---|---|---|---|
| Heal | cast heal | A burst heal at the aim point | heroes | in game |
| Fireball | cast fireball | A projectile that explodes at the aim point; anyone near the blast may catch fire (see Burning) | monsters (damage), **everyone** (fire) | in game |
| Armor | cast armor | A zone at the aim point where heroes take less damage | heroes | in game |
| Corn | cast corn | A corn bomb drops from the sky | **everyone** | in game |
| Tentacles | cast tentacles | Neon-purple tentacles burst from the floor and shove everything outward | **everyone** (shove), monsters (a little damage) | in game |
| Teeth | cast teeth | "Too many teeth" sprout out of everyone in the area, grow for 1–2 s, then explode | **everyone** | in game |

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
Burning`) attached as a child of the actor, and it is the groundwork for Damp.

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

**API (for Damp and other spells):**
```gdscript
Burning.ignite(actor, source, duration) -> Burning   # null if it cannot burn
Burning.is_burning(actor)  /  Burning.remaining(actor)
Burning.extinguish(actor) -> bool                    # put it out
Burning.extinguish_in_radius(pos, radius, team = -1) -> int
Burning.soak(actor, seconds)                         # extinguish AND no ignition until dry (the "damp" status)
Burning.set_fireproof(actor, on)                     # permanent: group "fireproof"
```
Every live fire is in the group `burning`, and `Burning.ended(reason)` says why it stopped (`burnt_out`,
`extinguished`, `died`).

**How Damp is meant to use it:** a Damp cast calls `Burning.extinguish_in_radius` over its area and
`Burning.soak(actor, seconds)` on everyone in it, so damp actors cannot ignite until they dry (a damp actor in a
fireball blast just fizzles). Tests: `tests/test_burning.gd`.

## Brainstorm: next spells [proposal, 2026-10-16]
These are user ideas, thought through but not built. Unless noted, every spell lands at the aim point
and follows the area rule: area spells hit **everyone** inside, except heal and armor.

| Spell | Effect | Hits | Chaos / co-op angle | Voice risk |
|---|---|---|---|---|
| **Wind** | A directional gust from the caster toward the aim point: a cone that shoves everything along it 2–3 hexes, with a whoosh and dust streaks | everyone in the cone | Blow monsters off ledges and into pits, or a friend off the crate tower. It differs from tentacles (radial, from the floor) because it's aimed and linear. | medium: "when", "win", "wine" (a wine cellar exists) |
| **Blind** | A dark cloud. Anyone inside can't see for ~2–3 s. Monsters lose their target and swing at random; a hero gets a brief black-edged, pinhole screen effect. | everyone in the area | Blinding a teammate is the misplay. Blinding the brute mid-windup makes its slam go off in a random direction. | medium: "behind", "blond", "blend" |
| **Damp** | Everything in a wide area gets slightly moist: puddles, wet footprints, dripping models. It puts out fire. | everyone and everything | Mostly utility and comedy; the value is in the combos. | medium–high: "damn" (common chatter, but loose mode needs the trigger), "dump", "camp", "dam" |
| **Vines** | Vines burst up and root everyone in the area for ~2 s. Rooted actors can still attack, but can't move and **can't be shoved**. | everyone in the area | Root the brute so it can't reach you, or root a fleeing friend next to a teeth carrier. It's the counter to your own shove spells. | medium: "wines", "vibes", "fines", "binds" |
| **Ghost** | **Single target:** the actor nearest the aim point (a teammate, yourself, or an ENEMY; it falls back to the caster) becomes nearly invisible for ~4 s. Its own attack breaks it early. | one actor | On a hero: monsters drop aggro, which makes it a rescue or escape tool, and the ghost passes through actors. **On an enemy it's simply dumb [decided]:** the monster is nearly invisible to your side (a faint shimmer, no HP bar or windup glow), keeps fighting normally, and AI allies lose it. There's no upside; it's the corn of single-target spells. | medium: "goes", "go", "host", "post" |
| **Coffee** | Haste: +60% move and attack speed for ~6 s, but twitchy (aim jitter, tiny random steps). Then a crash: −30% speed for 2 s. | everyone in a **small** radius (monsters too) | Coffee the team before a rush, or caffeinate the swarmers by accident. The crash makes timing matter. | low–medium: "copy" (matters only if the "Brace!/Copy!" call-and-response is built), "coughing" |

**Combos:**
- **Damp:**
  - **+ fire:** puts out fireball blasts and burning patches, and soaks the next fireball (a fizzle). It answers your team's own fire.
  - **+ ghost:** wet footprints reveal ghosts, enemy-ghost misplays included.
  - **+ server-room sparks:** electrified puddles become a hazard.
  - **+ shoves (wind, tentacles, bowl):** a wet floor makes shoves slide further.
- **Vines:**
  - **+ teeth:** root a pack, then teeth them, and nobody escapes the pop (friends included).
  - **vs shoves:** rooted actors ignore wind, tentacles, the bowl and spin.
- **Blind + brute:** its slam fires blind, maybe into its own swarmers.
- **Coffee + Wick's draw:** a faster draw, but jittery aim.
- **Ghost + employees** (`contracts.md`): ghost an employee past a hellgate.

**Component ideas** (extending `spells-and-components.md`):

| Spell | Component | Source |
|---|---|---|
| Wind | feather or fan blade | archer |
| Blind | ink sac or bat wing | a new enemy |
| Damp | sponge or leaky pipe | environment pickup |
| Vines | seed pod | spa planters |
| Ghost | ectoplasm | a future ghost enemy |
| Coffee | beans | the break room, or a reward for protecting employees |

**Suggested build order:**
1. **Vines** introduces a new mechanic (root) that counters the shove system and combos with teeth.
   The art is a simple variant of the tentacles kit.
2. **Wind** is almost free: an aimed cone on top of the existing shove system.
3. **Coffee** needs a small speed-modifier system (useful later for goo slows).
4. **Ghost** needs visibility and aggro rules (monsters losing targets).
5. **Blind** shares that aggro work, plus a screen effect.
6. **Damp** last, because it depends on fire and environment features that don't exist yet.

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

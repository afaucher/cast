# Spell roster

Status: 2026-10-16. Every spell lands where the caster aims (the same point the ranged attack goes),
and the aim snaps onto a teammate near the cursor. **[decided]** marks the user's calls;
**[proposal]** marks suggestions still waiting on the user.

| Spell | Say | Effect | Hits | State |
|---|---|---|---|---|
| Heal | cast heal | A burst heal at the aim point | heroes | in game |
| Fireball | cast fireball | A projectile that explodes at the aim point | monsters | in game |
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

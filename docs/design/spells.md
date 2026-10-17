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
| Tentacles | cast tentacles | Neon-purple tentacles burst from the floor and shove everything outward | **everyone** (shove), monsters (a little damage) | being built |
| Teeth | cast teeth | "Too many teeth" sprout out of everyone in the area, grow for 1–2 s, then explode | **everyone** | designed |

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
    running away from Dagna.
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

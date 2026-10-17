# Spell slots, readied spells and material components

Status: design record, 2026-10-16. The user's decisions are marked **[decided]**. Proposals still
waiting for a yes are marked **[proposal]**.

## Slots [decided]
- Each player has **4 spell slots** (the POC has 2).
- Spells come from **material components** dropped by the monsters you kill along the way.
- Players **swap** spells in and out of their slots.

## Controls [decided, with a known awkwardness]
- **1–4** select a slot; that spell is now *readied*.
- **E** casts the readied spell at the aim point (the ground under the cursor, the same point the
  ranged attack uses). It's the keyboard path.
- **Voice** casts any slotted spell by name ("cast heal"), readied or not.
- The awkward part, raised by the user: if voice can cast anything, selecting a spell has no
  meaning of its own. The next section gives it some.

## The readied spell is "the one in your hand" [proposal]
Selecting answers the question "what do I want to prioritize right now?". Readying a spell earns three things:

1. **Instant feel, by hiding voice latency.** The game knows which spell you're likely to say, so
   when speech starts and the partial transcript is consistent with the readied spell's incantation
   (e.g. the trigger word is heard), the hero starts the cast wind-up at once. The cast resolves when
   recognition confirms it, and a mismatch turns into a cheap fizzle. Non-readied spells wait for the
   final recognition (about 0.5–0.8 s after you stop speaking). This is the biggest benefit.
2. **Aim preview.** The reticle shows the readied spell's real footprint: the corn blast circle, the
   tentacles shove ring, the armor zone, the fireball path. Teammates also see it, so the crew can
   read "Larkin is about to corn that spot".
3. **A modest boost:** +25% power, and a fumbled readied cast never fully fizzles. It drops to a
   floor of 0.5 power rather than failing.

Other details:
- **Saying a non-readied slotted spell** casts it normally, with no boost and the full wait. It does
  NOT change which spell is readied.
- **Keyboard E** casts the readied spell at a fixed 0.8 power, lower than a clean voice cast, so
  voice stays the better choice (`voice-mechanic.md`).
- **Teammate UI:** a small icon over each hero shows their readied spell. This is co-op
  communication for free, and fits "a well-oiled team" (`north-star.md`).

Alternatives considered:
- **Only the readied spell is voice-castable.** Rejected: it guts the voice fantasy and adds a
  key press to every cast.
- **Casting a non-readied spell costs an extra component** ("rummaging in the bag"). Possible
  later, if the material economy needs a sink.

## Material components [proposal]
- Each spell has a **component**. Picking one up when the spell isn't slotted offers it for a slot
  (swap screen or quick-swap). Picking one up when it is slotted adds **charges**.
- **Charges:** each cast spends one. At 0 charges, a cast fizzles with "out of reagents" (no
  cooldown spent). Prioritizing becomes real: spend the last fireball now, or hold it for the brute?
- **Drops by monster kind.** Kinds drop thematically, so routes and target choice matter:

  | Monster | Drops | For |
  |---|---|---|
  | grunt (skeleton) | bone dust | armor |
  | archer | fletching | fireball? (or a future "volley" spell) |
  | brute | ember horn | fireball |
  | swarmer (imp) | neon ichor | tentacles |
  | anywhere (rare) | moss | heal |
  | anywhere (rare) | corn | corn |

  These pairings are placeholders to tune. Exploration secrets and vantage points can hold rarer
  components (`exploration.md`).
- **Co-op:** components are **shared loot**. Whoever picks it up gets it, and handing one to a
  teammate is a later feature. Fighting over the corn is on-theme.
- **Swapping mid-fight:** allowed. A swap takes 0.5 s and the hero can't cast during it, a small
  cost that keeps loadouts meaningful.

## Open questions for the user
1. Charges per component pickup (1? 3?), and the per-spell cap.
2. Is a swap screen acceptable, or must swaps happen in-world (walk over a component = auto-slot
   into the readied slot)? The in-world version needs no menus, which suits the no-mid-play-keys
   preference.
3. Should the readied spell also be readable by AI allies (so they could cover you)?
4. How many distinct spells for the vertical slice: 6–8?

## Impact on the POC code (for whoever builds it)
- `Hero.spell_slots` grows to 4; add `readied_slot` and per-spell `charges`.
- `PlayerController`: keys 1–4 select, `E` casts the readied spell; key casting moves from 1/2 to E.
- `VoiceCaster`: emit an early "likely spell" hint from partials (the trigger is heard and the
  partial is a prefix of the readied incantation), so the game can start the wind-up early.
- `AimReticle`: draw the readied spell's footprint.
- `MonsterFactory`/`Monster`: drop table on death, and a pickup actor that auto-collects on walk-over.
- HUD: 4 cards, readied highlight, charges count, and an icon over each teammate's head.

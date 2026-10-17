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

## The readied spell: a passive boost, held in your hand [decided direction]
Selecting a slot is not an active mechanic. It's a **passive boost** to that one spell, shown by the
hero **holding its material component in hand** (a glowing ember for fireball, a cob for corn, a
coil of neon ichor for tentacles).

- **The boost [decided]:** while readied, the spell can be cast **15% more often**: its cooldown is
  divided by 1.15, about 13% shorter. It applies to casts by voice or with E. It's noticeable but
  not dominant: it nudges priorities rather than dictating them.
- **Choosing what to hold** is the "what do I want to prioritize right now?" decision. It's quiet
  and strategic, not a reflex.
- **Teammates can read it** from the component in your hand, which gives co-op awareness for free.
- **E** casts the readied (held) spell from the keyboard. Voice casts any slotted spell; casting a
  different one doesn't change what you're holding.

Ideas that were set aside, as too active or too much UI:
- the readied spell starting its wind-up early to hide voice latency;
- a footprint preview on the reticle;
- only the readied spell being voice-castable;
- extra component cost for casting a spell you aren't holding.

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
3. ~~What should the passive boost be?~~ Decided: 15% more frequent casts (a shorter cooldown).
4. How many distinct spells for the vertical slice: 6–8?

## Impact on the POC code (for whoever builds it)
- `Hero.spell_slots` grows to 4; add `readied_slot` and per-spell `charges`.
- `PlayerController`: keys 1–4 select, `E` casts the readied spell; key casting moves from 1/2 to E.
- `Hero.try_cast`: when the cast spell is the readied one, set its cooldown to `cooldown / 1.15`.
- Hero models: a hand attachment point that shows the held component (`LowPolyModel`).
- `MonsterFactory`/`Monster`: drop table on death, and a pickup actor that auto-collects on walk-over.
- HUD: 4 cards, readied highlight, charges count.

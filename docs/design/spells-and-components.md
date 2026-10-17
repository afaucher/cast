# Spell slots, readied spells and material components

Status: **implemented**, 2026-10-16. The user's decisions are marked **[decided]**; numbers marked
*(tunable)* live in one place (`scripts/spells/spell_components.gd` and `SpellBook.SPELLS`) and are
expected to move with playtesting. Nothing here is a proposal any more except the "Later" list at the end.

## Where the data lives
| What | File |
|---|---|
| Slot count, charges, cap, held boost, E power, pickup radii, **drop table** | `scripts/spells/spell_components.gd` (`SpellComponents`) |
| Per-spell component name, `available` flag, cooldowns | `scripts/spells/spell_book.gd` (`SpellBook.SPELLS`) |
| Pickup actor | `scripts/spells/component_pickup.gd` (`ComponentPickup`) |
| Faceted prop for each component (pickup and hand) | `scripts/spells/component_props.gd` (`ComponentProps`) |
| Slots, charges, held slot, swap | `scripts/heroes/hero.gd` |
| Keys 1-4 / E / F, the cast entry point | `scripts/heroes/player_controller.gd`, `scripts/app/input_setup.gd` |
| Cards, toasts, swap prompt | `scripts/ui/hud.gd` |
| Hand attachment | `LowPolyModel.hold_item()` (`scripts/art/lowpoly/`), `pebble_model.gd`, `dagna_model.gd`, `larkin_model.gd` |
| Drop hook | `Monster._on_death` -> `SpellComponents.drop_for` |

## Slots [decided, implemented]
- Each hero has **4 spell slots** (`SpellComponents.SLOT_COUNT`). The start-of-game picker still
  picks **2** spells; they go in slots 1-2 with **5 charges** each (`START_CHARGES`, *tunable*).
  Slots 3-4 start empty and fill from pickups.
- Slots fill in order and never have gaps; `Hero.spell_slots` is the list, `Hero.slot_spell(i)` is the
  safe lookup (`""` = empty).

## Controls [decided, implemented]
- **1-4** ready (hold) a slot. An empty slot says "Slot N is empty" and changes nothing.
- **E** (`cast_readied`) casts the held spell at the aim point at a fixed power of **0.8**
  (`READIED_POWER`).
- **Voice** casts *any* slotted spell, held or not, at the voice's own power, and **does not change
  which slot is held**.
- **F** (`swap_pickup`) swaps the pickup you are standing next to into the held slot (below).
- Keys 1-4 no longer cast. They used to be "cast slot 1/2 at full power"; E replaces that.

## The held spell: a passive boost, shown in your hand [decided, implemented]
- **The boost:** the held spell's cooldown is divided by **1.15** (`HELD_COOLDOWN_DIV`), about 13%
  shorter, for casts by voice or by E. It is read when the spell is cast, so switching the held slot
  mid-cooldown does not retroactively change a cooldown that is running. No other active mechanics.
- **In hand:** the hero visibly holds the held spell's component, in the hand that isn't busy.
  `LowPolyModel.hold_item(node)` parents a prop to a hand anchor (null empties the hand); each model
  picks the host part:
  - **Pebble:** his left glove (both fists punch alternately, the left is just the quieter).
  - **Dagna:** her bare left fist (the right has the wrench).
  - **Larkin:** the free right hand (the bow is in the left); the anchor follows that hand every frame.
  - The old capsule body (`--proto-heroes`, arena) gets a prop on its off side.
- **Teammates can read it** from the component in your hand.

## Material components [decided, implemented]
- Each spell has a **component** (a name, a prop and a colour). A cast spends **1 charge**. At **0
  charges the cast fizzles**: a puff, the toast "Out of <component>", **no cooldown spent**; voice and
  the HUD both show it (the voice log also says "fizzled: out of ..."). The spell stays slotted.
- **Cap: 9 charges** per spell (`MAX_CHARGES`).
- A pickup is worth **3 charges** (`PICKUP_CHARGES`, *tunable*).

| Spell | Component | Prop |
|---|---|---|
| Heal | Grave moss | green clump with pale spore buds |
| Fireball | Ember horn | curved charcoal horn, glowing orange tip |
| Armor | Hide plate | tilted blue plate in a leather rim |
| Corn | Corn kernel | one fat golden kernel on a husk leaf |
| Tentacles | Neon ichor | glowing purple flask |
| Teeth | Loose teeth | three white molars (gold filling) |

### Drops (data table `SpellComponents.DROPS` / `ANY_KIND`, *tunable*)
Every monster rolls each entry of its kind's list, then each entry of `ANY_KIND`, independently when
it dies.

| Monster | Drops | For | Chance |
|---|---|---|---|
| grunt (skeleton) | Loose teeth | teeth | 35% |
| archer | Grave moss | heal | 40% |
| brute | Ember horn **or** Hide plate, 50/50 | fireball / armor | 100% |
| swarmer (imp) | Neon ichor | tentacles | 15% **per imp** |
| any monster | Corn kernel | corn | 5%, in addition |

- **Teeth is not castable yet.** Its component, prop and drop entry are all in the data, but the
  spell is `available = false`: it is hidden from the picker, `Hero.slot_in` refuses it, `SpellBook.cast`
  refuses it, and **its drops are skipped** while unavailable (otherwise grunts would litter the floor
  with components nobody can use). Flip `available` to `true` in `SpellBook.SPELLS` when the teeth
  gameplay lands and everything switches on: the 35% grunt drops, the pickup, slotting. (`roll_drops(...,
  include_unavailable = true)` rolls the raw table, which the tests use.)
- Drops fan out around the corpse and snap onto real floor (a monster shoved into a pit drops nothing).

## Pickups, and the swap rule [decided, implemented]
`ComponentPickup` is a world prop: it bobs and turns, has a soft glow and a faint floor ring, and shows a
small floating label ("Ember horn x3") when a player is within 4 units.
- **Auto-collect:** a player hero within **0.8** (`COLLECT_RADIUS`) picks it up.
  - Spell **slotted**: `+3` charges, capped at 9. If the cap leaves some over, the rest of the pickup
    stays on the floor (a capped spell takes nothing).
  - Spell **not slotted**, an empty slot exists: it fills the first empty slot with the pickup's charges.
    Toast: "+3 Ember horn  (Fireball, slot 3)".
  - Otherwise toast: "+3 Ember horn" (HUD) and a card flash.
- **All four slots full, spell not slotted:** the pickup stays on the floor. Within **1.2** (`SWAP_RADIUS`)
  the HUD shows **"F: swap <Spell> into slot N (held)"**. **F** swaps it into the **held** slot: the new
  spell takes that slot with the pickup's charges and becomes the held spell (the new component is now in
  the hand), and the **old spell drops as a pickup** with its **remaining charges**, a little away from
  you so it doesn't instantly re-prompt. An old spell with 0 charges drops nothing. A swap is instant
  (no 0.5 s lock, see "Resolved").
- **Allies:** only the **player** collects (`Hero.is_player`, so each human in future co-op does too).
  AI allies don't cast spells yet, so their slots would only steal the player's loot. Revisit when allies
  cast: the plan is that they pick up what they walk over, but never route to it.
- **Co-op:** components are **shared loot**; whoever walks over it gets it. Handing one to a teammate is
  a later feature. Fighting over the corn is on-theme.

## HUD [implemented]
- **Four spell cards:** key 1-4, spell name, "say: CAST HEAL" (`SpellBook.incantation` + the current
  trigger word), the component name with a colour chip, a big charges count (`x5`; amber at 1, red `OUT` at
  0), the radial cooldown sweep (the held spell's sweep uses its shortened cooldown), a flash on cast or
  pickup. A **HELD** card has a bright gold frame and a HELD tag; an **empty** slot is a dim dashed outline
  with the key and "walk over a component to fill this slot".
- **Toasts:** "+3 Ember horn", "Out of Ember horn", "Slot 3 is empty". The swap prompt is a persistent line
  above the cards while a swap is on offer.
- **Debug panel GAME section:** one line per slot with the spell, charges, cooldown and the HELD marker.

## Resolved open questions
1. **Charges per pickup and the cap:** 3 per pickup, 9 cap, 5 to start (*tunable*).
2. **Swap screen or in-world?** In-world. Walk over it (auto-slot into an empty slot), or press **F** next to
   it to swap into the held slot when full. No menus, which suits the no-mid-play-keys preference.
3. ~~What should the passive boost be?~~ 15% more frequent casts (a shorter cooldown). Decided.
4. **Swap cost:** none. The 0.5 s no-cast swap lock from the old proposal was dropped: the swap is already
   a deliberate stop-and-press, and the old spell's charges are never lost, so a lock added only friction.

## Still open
- How many distinct spells for the vertical slice: 6-8? (Teeth is the sixth.)
- Exploration secrets and vantage points holding rarer components (`exploration.md`).
- Handing a component to a teammate; allies casting and collecting.
- Whether a dropped pickup should eventually despawn (today it waits forever).

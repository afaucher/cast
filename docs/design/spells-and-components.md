# Spell slots, held spells and material components

Status: **implemented**, 2026-10-16. The user's decisions are marked **[decided]**; numbers marked
*(tunable)* live in one place (`scripts/spells/spell_components.gd` and `SpellBook.SPELLS`) and are
expected to move with playtesting. Nothing here is a proposal any more except the "Later" list at the end.

## Where the data lives
| What | File |
|---|---|
| Slot count, charges, cap, held boost, pickup radii, **drop table** | `scripts/spells/spell_components.gd` (`SpellComponents`) |
| Per-spell component name, `available` flag, cooldowns | `scripts/spells/spell_book.gd` (`SpellBook.SPELLS`) |
| Pickup actor | `scripts/spells/component_pickup.gd` (`ComponentPickup`) |
| Faceted prop for each component (pickup and hand) | each spell's def (`scripts/spells/defs/<id>.gd`: `component_soup()`, `GLOW`), built by `ComponentProps.make` (`scripts/spells/component_props.gd`) |
| Slots, charges, held slot, swap | `scripts/heroes/hero.gd` |
| Keys 1-4 / E (use) / F, the cast entry point | `scripts/heroes/player_controller.gd`, `scripts/app/input_setup.gd` |
| Cards, toasts, swap prompt | `scripts/ui/hud.gd` |
| Hand attachment | `LowPolyModel.hold_item()` (`scripts/art/lowpoly/`), `rebar_model.gd`, `gasket_model.gd`, `wick_model.gd` |
| Drop hook | `Monster._on_death` -> `SpellComponents.drop_for` |

## The license requisition [implemented, 2026-10-17; as a requisition 2026-10-18]
`SpellPicker` is paperwork: FORM 15 "License requisition" at a contract start, FORM 15-S "Supplemental requisition" for a
player joining a job in progress (one component, two variants). The player requisitions 2 licenses for this job (later,
per-mission spending lives here; no prices or stock yet). Every spell from `SpellBook.ids()` is a **line item**
(`RequisitionLine`: a printed box, the license with its colour tag, its component and cooldown), with nothing hard-coded
per spell, so a new spell appears without a picker change. The list is at least 5 and at most 10 lines tall (10 since
Chicken, the tenth spell, so all ten show) and
**scrolls** past that (focus keeps the line in view). Beside it lies FORM 15-A, a separate **spec sheet** (`SpecSheet`)
for the focused line: what to say ("cast heal", with the player's trigger word), component, cooldown and what it does.
Both pages fit 1600 x 900 canvas units (1280 x 720) and the Steam Deck's 1600 x 1000, from ten spells to a hundred.
Up / Down and the D-pad move line to line, Enter or a click ticks (the red tick is the record), and with two ticked
Enter or a click on "Requested by" stamps the player's name and submits (`picked`). Esc voids. Test hook: set
`spell_ids` / `spell_meta` (`SpellPicker.fake_ids(24)`) before adding it to the tree; `tests/test_license_checkout.gd`
covers 10, 24 and 100 spells and both variants.

## Slots [decided, implemented]
- Each hero has **4 spell slots** (`SpellComponents.SLOT_COUNT`). The start-of-game picker still
  picks **2** spells; they go in slots 1-2 with **5 charges** each (`START_CHARGES`, *tunable*).
  Slots 3-4 start empty and fill from pickups.
- Slots fill in order and never have gaps; `Hero.spell_slots` is the list, `Hero.slot_spell(i)` is the
  safe lookup (`""` = empty).

## Controls [decided, implemented]
- **1-4** ready (hold) a slot. An empty slot says "Slot N is empty" and changes nothing.
- **E** (`use`) is the context key (freight elevator, employees). It never casts: E casting was removed
  (2026-10-17, user). Spells are cast by voice, or by the typed console (Enter), only.
- **Voice** casts *any* slotted spell, held or not, at the voice's own power, and **does not change
  which slot is held**.
- **F** (`swap_pickup`) swaps the pickup you are standing next to into the held slot (below).
- Keys 1-4 do not cast (they used to be "cast slot 1/2 at full power"), and neither does E (removed 2026-10-17, user).
  The held slot is purely the passive boost plus the component in the hero's hand.

## The held spell: a passive boost, shown in your hand [decided, implemented]
- **The boost:** the held spell's cooldown is divided by **1.15** (`HELD_COOLDOWN_DIV`), about 13%
  shorter, for casts by voice or the typed console. It is read when the spell is cast, so switching the held slot
  mid-cooldown does not retroactively change a cooldown that is running. No other active mechanics.
- **In hand:** the hero visibly holds the held spell's component, in the hand that isn't busy.
  `LowPolyModel.hold_item(node)` parents a prop to a hand anchor (null empties the hand); each model
  picks the host part:
  - **Rebar:** his left glove (both fists punch alternately, the left is just the quieter).
  - **Gasket:** her bare left fist (the right has the wrench).
  - **Wick:** the free right hand (the bow is in the left); the anchor follows that hand every frame.
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
| Vines | Seed pod | split green pod with pale seeds, a curled tendril and a thorn |
| Damp | Soggy sponge | yellow porous sponge with a dripping blue bead |
| Coffee | Coffee beans | three roasted beans with their grooves |
| Chicken | Chicken feather | a long white tail feather with a rust-red tip |

### Drops (data table `SpellComponents.DROPS` / `ANY_KIND`, *tunable*)
Every monster rolls each entry of its kind's list, then each entry of `ANY_KIND`, independently when
it dies.

| Monster | Drops | For | Chance |
|---|---|---|---|
| grunt (skeleton) | Loose teeth | teeth | 12% (was 35%) |
| archer | Grave moss | heal | 15% (was 40%) |
| brute | Ember horn **or** Hide plate, 50/50 | fireball / armor | 35% (was 100%) |
| swarmer (imp) | Neon ichor | tentacles | 3% **per imp** (was 15%) |
| grunt (skeleton) | Soggy sponge | damp | 6% |
| archer | Seed pod | vines | 8% |
| brute | Coffee beans | coffee | 10% |
| swarmer (imp) | Chicken feather | chicken | 4% **per imp** |
| any monster | Corn kernel | corn | 2%, in addition (was 5%) |

Drops are rare on purpose: not every creature drops every spell, and the floor should not fill up with
pickups. Two more tunables in `SpellComponents` keep it that way:
- **Floor cap** (`FLOOR_DROP_CAP` = 5): at most 5 monster-dropped pickups lying on the floor at a time
  (`SpellComponents.floor_pickups()` counts the live ones on the host). One taken or expired makes room for the next
  drop; mail's and a swapped-out spell's pickups do not count. Until 2026-10-24 it was 5 per floor in all, which left a
  crew with nothing to cast late in a floor; the user: "Lets change it to no more then 5 per-floor at a time". The dice
  are always rolled, so the rng stream is the same whatever the cap does.
- **Despawn** (`PICKUP_LIFETIME` = 60 s, `PICKUP_FADE` = 5 s): an uncollected pickup blinks for its last 5 s
  (faster for the last 2) and then vanishes. A spell you swapped out for another is the exception: it is
  dropped with lifetime 0 (never despawns), so no charges are ever lost to a swap.

- **Teeth is not castable yet.** Its component, prop and drop entry are all in the data, but the
  spell is `available = false`: it is hidden from the picker, `Hero.slot_in` refuses it, `SpellBook.cast`
  refuses it, and **its drops are skipped** while unavailable (otherwise grunts would litter the floor
  with components nobody can use). Flip `available` to `true` in `SpellBook.SPELLS` when the teeth
  gameplay lands and everything switches on: the 12% grunt drops, the pickup, slotting. (`roll_drops(...,
  include_unavailable = true)` rolls the raw table, which the tests use.)
- Drops fan out around the corpse and snap onto real floor (a monster shoved into a pit drops nothing).

Vines, damp and coffee (2026-10-17) take their drops from the monsters for now. Their designed environment sources do
not exist yet: seed pods from spa planters, a sponge or leaky pipe as an environment pickup, and coffee beans from the
break room or as a reward for protecting employees. A broken mail package can also hold any castable spell's component
(`MailPackage.roll_component` uses `SpellBook.ids()`, so all ten are possible). Chicken feathers (2026-10-18) come from imps.

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
- How many distinct spells for the vertical slice? There are ten now (vines, damp and coffee are the seventh to ninth,
  chicken the tenth);
  the license requisition (FORM 15) is a scrolling catalog that is meant to grow past 20.
- Exploration secrets and vantage points holding rarer components (`exploration.md`).
- Handing a component to a teammate; allies casting and collecting.
- ~~Whether a dropped pickup should eventually despawn~~ Yes: 60 s, blinking for the last 5 (see Drops).

# Environmental hazards

Status: explosive props are **built** (2026-10-19). This doc holds the rules every hazard follows and, below, what was
built. Background: `combat-variety-research.md` §5.3 ("an exploding prop that the crew sets off with fire on purpose is
the positive version" of the priced props).

## Rules for every hazard (agreed with the user, 2026-10-19)
Hazards make the room a tool.
- **They hurt both sides.** Luring monsters into one is the fun, and so is catching a teammate.
- **They give a clear warning,** like an attack's telegraph: a hiss, a spark, a glow.
- **The crew can set one off on purpose,** with a spell, a shove or an attack. That gives voice a "use the room" job
  ("fireball the gas tanks!").
- **They are the client's property, so they bill the invoice.** Every big play is also a money call.

## Explosive props (as built)

Code: `scripts/contracts/explosive_prop.gd` (`ExplosiveProp extends PricedProp`), `scripts/fx/fuse_fx.gd` (the warning),
`scripts/fx/blast_fx.gd` (the blast's look), the models in `scripts/art/lowpoly/props/prop_models.gd`, placement in
`SiteBuilder._plan_hazards`. Tests: `tests/test_explosive_props.gd`, `tests/test_net_explosives.gd` (two processes).

### The props
Each is a priced prop (`PricedProp.TABLE`, site `"hazard"`, so never one of a site's random priced props). The room
themes place them (`RoomThemeDefs` `"hazards"`).

| Kind | Name | Price | HP | Fuse | Blast radius | Damage (centre) | Shove (centre) | Rooms |
|---|---|---|---|---|---|---|---|---|
| `oil_drum` | Oil drum | $800 | 40 | 1.3 s | 3.0 | 45 | 2.6 | torture chamber (lamp oil), barracks (generator fuel), science |
| `gas_cylinders` | Gas cylinders | $1,800 | 35 | 1.0 s | 3.2 | 50 | 2.8 | lab, science, panic room (the air supply) |
| `propane_tank` | Propane tank | $1,200 | 45 | 1.2 s | 3.4 | 55 | 3.0 | spa (the sauna heater), indoor pool (the pool heater) |
| `battery_pack` | Server battery pack | $6,500 | 60 | 1.5 s | 2.8 | 40 | 2.4 | server room (the UPS), panic room (backup power) |

Damage and shove fall off linearly to 35% (`EDGE_MULT`) at the rim. For scale: Wick has 85 HP, a fireball does 40, a
brute's slam 25. A hero next to a drum loses about half their HP; one at the rim about a sixth. The cheap ones are
cheap on their own, but a blast breaks whatever priced props are in reach, so the real cost is the room.

### Setting one off
- **Fire.** A fireball's blast lights every explosive it reaches (`ExplosiveProp.fire_at`, from `SpellBook`'s fireball,
  beside `MonsterSenses.fire_at`). A burning actor (monster, hero or employee) that touches one lights it; the bill goes to
  whoever set the walker on fire (`Burning.culprit`), else the walker.
- **A hard hit.** One hit of `HARD_HIT` (15) or more lights it: Gasket's hammer (28), Rebar's fist (26), a drawn arrow
  (28), corn, a brute's slam (25, `Combat.slam` now also hits an explosive in its ring), another blast. **Any arrow or
  bolt** punctures it (`ExplosiveProp.shot_damage`: at least 15, so an archer's 8-damage arrow and Wick's tap arrow light
  it). Enough small dents to break it light it instead of breaking it.
- **A hard shove.** An actor slammed into it (the priced prop's contact check: 10 damage per unit of slide, so a slide of
  1.5+ units) or a shove on it of `HARD_SHOVE` (1.5) or more (tentacles, Gasket's spin, a blast).
- **Light taps don't.** Wick's bow bash (12), a melee nudge (0.7-1.0), a teeth splash: a free dent, like any prop.
- While the fuse burns, hits do nothing (the blast is coming).

### The warning (FuseFx)
A short fuse: 1.0-1.5 s by kind. It has:
- the `fuse` sound: a "pssht", then a quiet high sizzle;
- a jet of sparks from the valve or bung;
- a red glow that pulses faster and swells as the fuse burns down;
- the model shaking harder and harder;
- the blast's TRUE radius on the floor, drawn like the brute's slam ring: a red rim and a fill that grows to the rim by
  the moment it blows. A body whose edge is outside the rim is safe (`Combat.explode` counts the body's radius).

### The blast
At the fuse's end, on every machine:
- `Combat.explode(pos, radius, damage, -1, igniter, 0.35, shove, decider = the prop)` hits everyone: heroes, monsters,
  employees, other props, mail and chickens.
- `Burning.on_blast` at 0.7 power over three quarters of the radius gives everyone in it a fireball's chance to catch
  fire. A burning monster that runs into the next drum sets it off.
- It makes a loud noise for the monsters (`MonsterSenses.noise`, as loud as corn).
- The look (BlastFx) is the fireball's burst made bigger (the same `fireball` sound), a white-hot core, a shock ring out
  to the radius, the prop's shards, a smoke plume, a strong shake, "BOOM!", and a scorch mark (Grime, which fades like a
  fireball's).
- Then it breaks. Its rubble stays, with a scorch plate.

### Chains
When one blows, every other explosive in its reach lights first, on a short fuse of its own (`chain_delay`: 0.3 s + 0.08
s a unit, so 0.5 s at 2.5 units). A row of drums goes off as a sequence you can read, not as one flash.

### Billing
Breaking it bills its full price **once** (`PricedProp._on_death`, on the host) to whoever set it off (`igniter`). A chain
keeps the first igniter, so one player's fireball pays for the whole row. The blast's source is the igniter, so
everything it breaks (priced props, mail) and every employee it kills is blamed on them too (`Ledger.culprit_name` asks
`blamed()`). A monster that sets one off (an archer's arrow, a brute's slam) bills it to "demons".

### Damp (decided: a soaked explosive is a dud)
A soaked explosive (Damp, `Wet.douse`, a pool: `Burning.soak`) **will not light from anything** (fire, hits or shoves)
until it dries (Damp soaks for 15 s). A fireball on it fizzles. Smashed while wet, it breaks as a dud: billed, no blast.
A soak that lands on a **burning fuse** puts it out ("FIZZLE"), unless it lands in the fuse's last 0.3 s
(`DOUSE_LOCK`). So "damp the drums!" is the voice counter that makes a room safe, and "damp it!" can save a teammate
standing next to a lit fuse.

### Monsters
- Their attacks set explosives off: an archer's arrow punctures one, a brute's slam lights one in its ring, and so does a
  burning monster walking into one. A monster's sword swing still leaves priced props alone.
- They don't avoid explosives, and they don't seek them out either: an archer's idle target practice skips them
  (`Archer._practice_ok`).
- AI allies treat them as priced props: they avoid swinging at a target with one in the arc. They don't step out of a
  lit fuse's ring yet (a follow-up).

### Placement (`SiteBuilder._plan_hazards`)
- Explosives go in rooms whose theme lists some, never in the start room, and on the same wall cells and poses as a priced
  prop: wall-backed, flush to the face, with a clear lane in front. That keeps them out of the start, exit and elevator
  zones and away from the doors (cells near a corridor).
- Clearances: at least 4 cells from a hellgate, 3 from an employee's spot, 2 from a priced prop (still inside the blast:
  the money call), and 4 from another room's explosive.
- At most `MAX_HAZARDS` (3) a floor and one a room. In half the rooms (`HAZARD_PAIR_ODDS`) a second one stands 2.0-3.2
  units away, inside its blast, so they chain.
- It uses its own RNG (seeded from the floor seed) and borrows the theme context's poses with that RNG, so the priced
  props, notes and decor dice are unchanged. It is deterministic per seed. It tries a random sample of 14 wall cells a
  room (a pair's second one: the wall cells 1-2 hexes from the first), which costs about 4 ms a floor
  (`SiteBuilder.last_hazard_usec`). The plan's `hazards` and the spawned actors
  are in the floor checksum.

### Networking (a host-arbitrated object whose blast is a scheduled effect)
- **Who owns it:** the host, like every prop. A client's hit or shove on one is a request (`Net.route_hit`,
  `Net.route_shove`), and the amount already includes an arrow's puncture.
- **Who lights it:** the host decides. A client's fireball is a cast that also runs on the host, so the host lights the
  prop from its own run (`fire_at`); the client's hit request that follows finds the fuse already burning. A burning
  walker is seen on the host from the replicated fire.
- **The fuse:** `obj.fuse {id, s, e, by}` carries the start and end on the shared clock and the igniter. A douse sends
  `obj.out {id}`. A douse only counts before the last 0.3 s, so it reaches every screen before the blast would.
- **The blast:** every machine runs it at `e` on its own clock. Each machine applies only what it resolves: the decider is
  the prop, so the host handles monsters, props and employees, and each hero's own machine handles its hero. A client's
  hero is hit once, by its own machine. The chain's fuses are new `obj.fuse` events from the host's blast.
- **The break and the bill:** `obj.break` and the host's Ledger, as for any prop. A client's Ledger is a mirror.
- **Declarations:** `ExplosiveProp.net_fields()`. Its OWNER vars (`fuse_start`, `fuse_end`, `_igniter`, `blown`) are
  carried by `obj.fuse` and the scheduled blast (`NetEvents.WORLD_CARRIES`).
- **Late join:** the snapshot carries every burning fuse (`fuses`, replayed as `obj.fuse`). A blown prop is a gone id
  (shown broken).
- `test_net_explosives` (host and one client, `off` and `coast`) checks all of this. The client's fireball lights the
  host's drum, the chain lights the cylinders, and both machines see each fuse end within about 2 ms on the shared clock
  and each blast within a frame. The client's hero takes exactly one hit of the expected damage, on its own machine. Each
  bill line exists exactly once on the host, and the client's invoice matches the host's line for line.

### Dev flags (screenshots, tests)
- `--hazard-near oil_drum,gas_cylinders` builds explosives near seat 1's hero before the barrier, on every machine.
- `--to-hazard kind[:n]` with `--focus dev` stands the crew beside the floor's n-th explosive of that kind and puts the
  camera on it.
- `--hazard-demo fuse|chain|invoice [--demo-after s]`:
  - `fuse` lights the first one after s seconds.
  - `chain` does the same with two frozen grunts beside each.
  - `invoice` does the same, then cashes out after the last blast.

### Open questions (the user may want to change)
- The cap of 3 a floor. With 4 of 6 lair themes and 4 of 7 bunker themes holding explosives, most floors get 2-3.
- Damp blocks every way of setting one off, not just fire.
- Arrows always puncture, so an archer's 8-damage arrow sets one off.
- The blast sets people on fire (0.7 of a fireball's chance).
- Prices: the battery pack costs $6,500 on its own.

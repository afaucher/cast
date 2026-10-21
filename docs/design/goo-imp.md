# Goo imp (sewer pest)

**Status: [built] (2026-10-20), sewer only; see "7. As built" at the end.** The user asked (2026-10-20) "Show me just the
goo imp", picked Gloop in bile goo (section 6), then said to build it. It is a real monster kind (`goo_imp`) that only the
sewer deals: the sewer slice's layout 2 stages a pack of three (`.\run.ps1 --sewer 2 --spells damp,fireball --no-mic`), and
`MonsterFactory.compose_sewer` / `spawn_sewer_pack` are the hook for the sewer rooms on generated floors. Sections 1-6 are
the look-dev record as it was.

- Blockouts: `scripts/art/lowpoly/monsters/goo_imp_blockouts.gd` (`GooImpBlockouts.build(kind, goo_colour)`, a
  `MonsterModel` with `pose_preview("rest" | "windup" | "swing")`).
- Lab: `scenes/goo_imp_lab.tscn` (`scripts/art/lowpoly/monsters/goo_imp_lab.gd`, on `LabBase`). It builds a small sewer
  with the slice's own pieces (`SewerLayouts.Builder`, `HexMapView`, `DungeonLook`, `SewerView` in the brick look) and
  renders every shot below at the game camera (CameraRig: yaw 45, pitch -56, ortho 24, 1920x1080).

## 1. The concept

- **A ranged pest in small packs** (three or four), imp-sized, a cousin of the swarmer imp. Where the swarmer rushes, the
  goo imp **hangs back on dry walkways** (a ledge or the far deck across a channel) and **lobs goo balls on an arc**.
- **The telegraph:** a dark shadow and a goo-coloured ring on the floor where the ball will land, there from the throw
  until the splat (`throw.png`). The ball is big and glowing so it reads in the air.
- **A hit:** small damage and a short slow.
- **A miss:** a **goo patch** (about 5 s) that slows anyone crossing it, crew and monsters alike.
- **Goo is flammable:** a fireball on a patch turns it into a **fire patch**, which can catch the imps' own pack
  (`fire.png`). **Damp** washes patches away.
- Fiction: the sewer's own wildlife. The site's monsters took the fixtures and the staff upstairs; down here they took the
  drains.

## 2. The look

**The family** (all three): the swarmer's body plan and size (pot belly, big glowing yellow eyes, a toothy grin, clawed
hands and feet, a tail), so the eye files it as "an imp", but a sewer animal:
- pale **axolotl pink** skin with darker warts (the sewer is olive, brown and dark green: pink is its complement);
- **three red gill frills** each side where the swarmer has bat ears;
- webbed feet, a finned paddle tail;
- **goo drooling from the grin.**

Every goo face glows (the monsters' emissive faces, `MonsterMaterial`); the body is matte. The goo is the beacon, like the
Water Boy's water. Built at `MODEL_SCALE` 0.95 (the swarmer is 0.88): about 1.0 tall.

| | **A. Goo Sac** (`sac`) | **B. Gloop** (`drip`) | **C. Slinger** (`ladle`) |
|---|---|---|---|
| One line | a glowing goo bladder grown on its back | the imp dripping with its own goo | a mop bucket of goo and a long soup ladle |
| Body | the family imp, a veined, strapped bladder (0.6 across) on its back with a spout on top; a ball in its right hand, pinched off the spout | the family imp under a goo cap that runs down its head, drips off its chin, elbows and belly, a puddle at its feet; the ball wells up in both hands | the family imp, a small yellow mop bucket of goo on its left arm, a long steel ladle on its right shoulder, the bowl full |
| Silhouette | a round hump behind the head | no prop: a lumpy, glowing figure | a long diagonal stick with a bright dot at the end |
| Throw tell | the right arm goes back over the head (the ball hides behind the head) | the right hand takes the ball back over the head | the ladle swings back and down behind it, then over: the biggest motion of the three |
| At the game camera | a pink speck with a chartreuse hump | the brightest of the three: a chartreuse imp | pink speck, yellow bucket, the ladle's line and bowl |

## 3. Read tests

Renders in `docs/design/goo_imp/` (the bile goo unless noted). Only `sheet.png`, `close.png`, Gloop's crops
(`drip_alone_crop*`, `sewer_drip_crop*`), `lineup_crop`, `throw_crop`, `fire_crop` and `goo_colours_crop` are committed
(the full set was about 22 MB); re-render the rest with section 4.

| File | What |
|---|---|
| `sheet.png` | **the comparison sheet**: the close-ups (rest, windup), the three alone crops in colour and grey, the lineup in colour and grey, the three packs and their greys, then the throw, the fire and the goo colours |
| `<kind>_alone.png`, `_alone_crop.png`, `_alone_crop_gray.png` | each variant alone on the cistern's deck, three-quarters, at the game camera; the crop is 240x135 at x3, nearest (game pixels stay pixels), and its greyscale silhouette |
| `close.png`, `close_throw.png` | low angle (yaw 160, pitch -18, ortho 4.6): the swarmer imp and the three, at rest and winding up the throw |
| `lineup.png`, `_gray.png`, `_crop.png` | Wick, the swarmer imp, a grunt and the three in a row at the game camera, named |
| `sewer_<kind>.png`, `_gray`, `_crop`, `_crop_gray` | a pack of three on the far ledge of a 6.0 sewer main (one winding up, one throwing, one at rest), Rebar and Gasket wading the channel, Wick on the near ledge |
| `throw.png`, `_crop.png` | the throw mocked in the cistern: a ball mid-arc with its droplets, its landing marker by Wick, a fresh patch (a miss), Gasket stuck in a patch (goo over his boots, strands to the floor), a ball that fell in the water as a floating slick |
| `fire.png`, `_crop.png` | Wick's fireball has lit a patch under the pack: the patch charred and burning with `Burning`'s flames, the imp in it on fire, one backing off, one still throwing, an unlit patch beside them |
| `goo_colours.png`, `_gray.png`, `_crop.png` | the Goo Sac, a ball and a patch in each goo colour: bile, pink, tar |

(`_crop` files are a 960x540 window around the action at x2, nearest, unless noted.)

**What they show:**
- **Cousin of the swarmer, not a copy.** Same size and stance; colour separates them at once (violet vs pink with
  chartreuse goo). In grey the gills vs the bat ears are too small to tell apart at the game camera: the read there is
  colour, then the carry.
- **Scale.** All three are swarmer-sized: the smallest things on screen next to a grunt or a hero (`lineup.png`). In a
  pack on a ledge they are specks with a glowing spot, which is right for a pest, and the goo is what finds them.
- **Grey.** All three are pale, lighter than the floor and the swarmer, about the grunt's bone value. Gloop is the
  brightest; the Slinger is the only one with a shape of its own (the stick); the Sac reads as a round lump.
- **Goo Sac:** the hump says "goo creature", and the goo has a source. But the throw tell is small: the arm goes back
  behind the head and the ball disappears.
- **Gloop:** the strongest colour read in a pack, the whole head glows. A pack of three is a bright smear; it also looks
  "charged", which can be mistaken for a buffed or healed monster. No prop, so nothing says "thrower".
- **Slinger:** the clearest *thrower*: the ladle is a lever anyone reads, and its swing is the biggest tell. The yellow
  bucket is mop-bucket yellow, near Corn's yellow but matte, and small.
- **The throw** (`throw.png`): the landing marker (shadow plus ring) is the most important read and it works at the game
  camera; the ball and its droplets read as "something lobbed". The patch reads as a lumpy glowing splat, nothing like a
  heal ring. A hero stuck in one reads by the goo on his boots.
- **Fire on goo** (`fire.png`): the clearest contrast of all: orange flames on a charred black bed against chartreuse
  patches. The imp on fire is mostly hidden in the flames; a real burning imp would carry `Burning`'s own flames.
- **Level design:** in a 6.0 main the near ledge is hidden by the near wall (as `sewer-concept.md` warns), so a patch
  thrown there is out of sight. That is why the throw and fire mocks are in the cistern: the imps belong on a far deck
  or ledge, throwing at a crew in the channel or on open decks.

### Goo colour (`goo_colours.png`)

| Goo | Reads in the sewer | Problem |
|---|---|---|
| **bile** (0.80, 1.0, 0.16), the enemy chartreuse | well on the dark decks, and on the green water too (it glows brighter than the water's olive) | it is the Water Boy's water and its pulse: a patch could be taken for a heal zone (the shape differs: a lumpy splat vs rings) |
| **pink** (1.0, 0.30, 0.72) | the most distinct from the sewer and from every spell (Tentacles is violet, Chicken red) | it melts into the imp's pink skin: the pink-goo imp is one pink blob. Pink goo would need another skin (an olive grey, say) |
| **tar** (1.0, 0.62, 0.10), amber grease | reads, and says "flammable" | next to Corn's yellow and Fireball's orange; a burning tar patch is harder to tell from an unlit one |

**Recommendation:** **bile goo** on the pink imp. It reads, it keeps the enemy colour family, and the fire contrast is the
strongest. If sharing chartreuse with the healer's water is a problem, pink goo with a re-skinned imp is the alternative.

### Ranking

1. **Slinger (C).** The best thrower read (the ladle and its swing), a silhouette of its own, and the mop bucket is a joke
   that fits the sewer. Risk: the thinnest goo read of the three (a bowl and a bucket).
2. **Goo Sac (A).** The best "goo creature" read; the hump is the silhouette. Risk: a small throw tell.
3. **Gloop (B).** The brightest, but a pack is a glowing smear and it looks buffed rather than ranged.

A mix is possible: the Slinger's ladle on the Goo Sac's body (the sac as its ammunition) would have both reads.

## 4. Re-render

```
godot --path . --resolution 1920x1080 -- --scene res://scenes/goo_imp_lab.tscn --shot <absolute dir> [--view <name>] [--goo bile|pink|tar]
```

`<dir>` gets every file above (about 15 s). `--view <name>` renders one view only (`sac_alone`, `close`, `lineup`,
`sewer_ladle`, `throw`, `fire`, `goo_colours`, ...). `--goo` recolours every view but `goo_colours`. Godot is
`..\Hero-Reader\third_party\godot\Godot_v4.7-stable_win64_console.exe` (`$env:CAST_GODOT`).

## 5. If it is built (not designed yet)

Not part of this look-dev; for the next step. A host-owned monster like the other monsters; the throw a wind-up event with a
scheduled landing (the cast pattern: the marker shows on every machine, each owner resolves the hit on its own hero); the
patch a timed area every machine places from that event (a scheduled effect, like Damp's puddles), its slow applied by
each actor's owner; the fire patch the same patch's state change from a fireball's blast. It needs the networking
checklist (`networking.md`) before any code.

## 6. Open questions for the user

1. ~~**Which variant?**~~ **Decided (user, 2026-10-20): "Gloop is the best for the sewer."** Gloop (`drip`) is the look.
   The doc's own worry stands as a note for the build: a Gloop pack can read as glowing/buffed rather than ranged, so the
   throw's telegraph (the wind-up and the landing marker) has to carry "thrower".
2. ~~**The goo colour**~~ **Decided (user, 2026-10-20): "Keep bile goo."** The Water Boy shares the chartreuse; the
   patch's lumpy splat (vs his rings) has to keep them apart.
**Decided (user, 2026-10-20), questions 3-8:**

| Question | The user | What it means |
|---|---|---|
| 3. The skin | "as shown is fine" | Pale axolotl pink with red gills. |
| 4. The patch | "as shown is fine until I play it" | About 0.8 radius, 5 s, slows monsters too; revisit after a playtest. |
| 5. A ball in the water | "splash and gone" | No floating slick: a splash, and the ball is gone. |
| 6. Fire on a patch | "no fire spread for now, just hurts" | A lit patch burns and **hurts** whoever stands in it; it does **not** set them `Burning`. (Its burn time is the build's call; propose ~3 s.) |
| 7. Damp on a patch | "just have damp replace it" | Damp removes the goo patch; Damp's own wet floor is what's left. |
| 8. Pack size and HP | "3-4 per pack, same toughness" | Packs of **3-4**, the swarmer imp's HP. |

## 7. As built (2026-10-20)

### What it is
- **The monster:** `scripts/monsters/goo_imp.gd` (`GooImp extends Monster`, MonsterDefs kind `goo_imp`). **Look:** Gloop in
  bile goo, pale axolotl pink with red gills (`GooImpModel`, `scripts/art/lowpoly/monsters/goo_imp_model.gd`, built on the
  look-dev's `DripImp`; about 2000 triangles, ui height 1.04). The look-dev's inner class `GooImp` is now `ImpBody` (the
  game's class took the name).
- **The thrower read** (section 3's worry: a Gloop pack can read "buffed"): the tell is the monsters' wind-up (0.7 s), during
  which the right hand takes the ball back over the head and the **ball swells to twice its size** (the thrown ball's size);
  the body's goo hardly flares (`glow_flare` 0.15); right after the throw its **hands are empty** and a new ball wells up over
  0.45 s. In the air the ball is big and glowing with a trail of droplets, and the **landing marker** (a dark shadow that grows
  and darkens as the ball comes down, inside a bile ring the size of a patch) is on the floor from the throw to the splat.
- **Where it lives:** MonsterDefs rows have a new `habitat` field (`"sewer"`) and a `sewer_pack` field (`{min 3, max 4,
  weight 1}`). A habitat kind has no `pack` and no `gate`, so `MonsterFactory.compose` (every normal floor's packs) and the
  hellgates never deal it; `test_monster_defs` holds that (floor packs never roll one even with a 50x bias), and
  `test_golden_floor` is unchanged. **The hook for the sewer generator:** `MonsterFactory.compose_sewer(rng, kind = "")` (one
  sewer pack's kinds: 3-4 goo imps) and `MonsterFactory.spawn_sewer_pack(cells, rng, kind = "", count = -1)` (spawns it as a
  clump on the DRY cells of a room: full floor, not stairs, not water), each on the caller's own dice.
- **Staged:** the sewer slice's layout 2 (`SewerLayouts._junction`) has three on N's (the aquarium overflow's) dry east deck
  over the channel, facing the flooded hall and the west deck.
- **Drops** (a design call): per imp, damp 5 %, fireball 4 % (its two counters).

### The numbers
| | | |
|---|---|---|
| HP | 12 | the swarmer's ("same toughness") |
| Speed | 3.6 | (swarmer 5.5); shove_mult 1.5, radius 0.26 |
| Aggro | 10 | |
| Throw band | 5-9 from its target, with a line of sight | closer than 2.6 it backs off (never into water; cornered, it throws anyway) |
| Tell | 0.7 s | the monsters' wind-up (a shove, a stagger or a daze calls it off) |
| Cooldown | 2.6 s x 0.6-1.55 (1.6-4.0 s) | the first throw of a fight waits 0.2-2.0 s: a pack's balls come one by one. Widened from x0.8-1.25 and 0.2-1.4 after the first playtest (user, 2026-10-21: "can we jitter their throws a bit?", the timing) |
| Aim | where the target stands, up to 0.6 off | no lead: the marker is fair |
| Flight | 0.85-1.15 s | 0.85 + 0.03 per unit thrown; the arc tops out 1.4 + 0.12 per unit above the higher end |
| Hit | 5 damage + the goo slow (x0.5 walking speed) for 1.5 s | anyone whose feet are within 0.55 (+ their radius) of the landing point, 1.0 up or down |
| Patch | radius 0.8, 5 s (shrinks away over the last 0.6 s) | x0.5 walking speed on it: heroes, monsters, employees and chickens alike (not a shark, nobody in the air) |
| Fire on a patch | burns 3 s, 4 damage every 0.5 s (24 over the burn) to whoever stands in it | never sets anyone `Burning` (no fire spread); a hero's fire never takes a hero below 1 HP (as `Burning`); burnt off, it leaves a scorch |
| Damp on a patch | removes it (a lit one too) | Damp's own wet floor is what is left |
| Water | a splash and gone | no slick |

It hangs back on DRY ground: while it fights (and idles and searches) `GooImp.move` refuses any step from dry floor into
water, so a pack on a deck waits at the edge of a channel and throws from there; walking home it may wade, and an imp shoved
into the water walks out to the nearest dry floor first.

### Network shapes (networking.md)
- **The imp:** a host-owned monster (Monster's shape) with no OWNER var of its own; its tell is `world.windup`. A puppet's
  `net_strike` throws nothing (the host's ball is on its way). Late join: a monster's keyframe.
- **The ball: a scheduled effect the host announces.** `GooImp._strike` (host) throws a `GooBall` and calls
  `Net.announce(ball)`: `NetObjects.adopt` gives it a runtime id and sends `obj.new {id, k "goo_ball", r [imp, from, to,
  start (shared clock), flight, damage]}`; every client builds the same ball (`GooBall.net_copy`) and flies it on its own clock
  for the same shared moment. At the splat **each machine resolves the hit on what it resolves** (`Combat.resolves`: its own
  heroes; the hit's slow is a modifier its owner applies and NetStatus shows). Params SPAWN; flight, marker, splash LOCAL.
  Late join: skipped (it lands within about a second).
- **The patch: a host-arbitrated world object made during play.** Only the ball's OWNER (the host) decides a patch, from where
  it has the heroes (a ball nobody stood under, on dry floor), and announces it the same way (`obj.new {k "goo_patch"}`). The
  host decides its two changes, **lit** (`GooPatch.fire_at`, called from the fireball's blast, which runs on every machine,
  acts only on patches this machine owns) and **washed** (`GooPatch.wash_at`, from Damp's burst, the same), and tells everyone
  `obj.goo {id, st, t, by}` (`net_link` / `net_event`). Every machine then runs the patch on its own clock: the slow is LOCAL
  (like pool water: `Actor.effective_speed` asks `GooPatch.speed_mult`, from the patches every screen has; nothing travels);
  the burn's ticks are applied to the actors each machine resolves (`Net.resolves`: a hero's player, the host for the rest);
  the drying and the burn-out are scheduled. OWNER vars `lit_at`, `lit_by`, `washed` (carrier: `obj.goo`). Late join: every
  live patch with its state, rebuilt as obj.new would (`late_join_state`, section `new`).
- **The new net piece: RUNTIME OBJECTS** (`NetObjects.RUNTIME_OBJECTS`, `Net.announce`, `obj.new`). A host-arbitrated object
  the host makes during play (not seed-built) implements the net-object contract plus `net_spawn_row(objects)` and a static
  `net_copy(row, objects)`; NetObjects numbers it (`NetRegistry` runtime ids), links it, sends `obj.new`, builds the clients'
  copies and the late joiner's (`new` rows). Nothing in `scripts/net/` names the classes but the kind table. `test_net_contract`
  section 8 holds each runtime object to it (its two methods, NET_SCRIPTS, REPLICATED); no allowlist was widened.
- **Who disagrees, and how much:** the host decides a patch from its ~100 ms old view of a client's hero. A client that dodged
  at the last moment on its own screen takes no hit and sees no patch (the host saw it under the ball); one that walked in at
  the last moment takes the hit on its own machine and a patch appears under it about half a round trip later. Near misses, as
  option A intends. A fireball's blast point can differ between machines only when it hits an actor in flight; the host's
  blast is the one that lights.
- Cosmetic: the goo on a hero's boots (`GooBoots`, `scripts/fx/goo_boots.gd`), the marker, droplets, splashes and flames; every
  screen draws them from what it shows. No sound cues were added (the monsters' attacks have none yet).

### How to play it
- `.\run.ps1 --sewer 2 --spells damp,fireball --no-mic`: the junction; the pack is in N (the aquarium overflow), up the north
  hall from the drain junction, on the east deck across the channel. Fight it from N's west deck to see patches (a ball into
  the channel only splashes); fireball a patch under the pack; Damp a patch away.
- Any floor, for a quick look: `.\run.ps1 --seed 7 --contract 1 --spells fireball,damp --spawn-near goo_imp,3 --no-mic`; for
  screenshots add `--idle-monsters --monster-demo goo` (the allies hold, the imps wake on the player and throw).
- Online: no normal floor deals it (the sewer slice is solo); the net test spawns them on a shared floor.

### Tests
- `test_monster_goo_imp` (solo): the tell, the throw, a hit (5 and the slow, no patch), a miss's patch slowing a hero and a
  monster and drying up after 5 s, a ball into water, the real fireball lighting a patch (it hurts, sets nobody Burning, burns
  out after 3 s), the real Damp washing one away (its wet floor stays), dry ground across a channel, a pack's throws spread
  out, and the rows a client and a late joiner build from.
- `test_net_goo_imp` (two processes, `off` and `coast`): the throw and the victim-decided hit, the host's patch on the client
  slowing the client's hero, the client's fireball lighting it on the host (blamed on the client, the same lit moment on both,
  the burn applied to the client's hero by the client), the client's Damp washing one away; the OWNER-write guard quiet.
- `test_monster_models` (the model; the goo imp may glow on up to 45 % of its faces, the user's pick, where every other model
  keeps to 25 %), `test_monster_defs` (habitat, sewer packs), `test_net_contract` (sections 1, 4, 7, 8), `test_zfight` (the
  model, `goo/patch`, `goo/patch_burnt`, `goo/ball`, `goo/boots`; the look-dev head's teeth were sunk into the grin to stop a
  z-fight).

### What's left
- Wire `compose_sewer` / `spawn_sewer_pack` into the generated sewer rooms (the sewer-generator merge).
- Playtest the numbers (the user: "as shown is fine until I play it"): the patch's size and life, the 0.5 slow, and the throw
  rate of a pack of four.
- A throw and a splat sound (Sfx cues and the mic-leak probe, audio-plan.md).
- Only a fireball lights a patch: an explosive prop's blast or a burning actor walking in does not.

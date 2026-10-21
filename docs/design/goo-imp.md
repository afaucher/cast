# Goo imp (sewer pest)

**Status: [proposal], look-dev only.** The user asked (2026-10-20): "Show me just the goo imp". Nothing here is in the
game: no Monster kind, no `MonsterDefs` row, no `net_fields()`, not in `MonsterModels` or `ZFightModels`. The three
blockouts and the lab exist only to pick a look.

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

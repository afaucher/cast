# Enemy healer: options

**The user's direction (2026-10-19):** "For the medic, imps are far too small. It won't read well. Lets think of some
alternatives." This page replaces the look of the Imp Medic (`combat-proposals.md` §3) and offers other mechanics with
it. Everything here is **[proposal]**. Nothing is in the game: the four blockouts and the lab are look-dev only.

- Blockouts: `scripts/art/lowpoly/monsters/healer_blockouts.gd` (`HealerBlockouts.build(kind)`, in `ZFightModels` as
  `healer/<kind>`). Not in `MonsterModels`, not a `Monster` kind, no `net_fields()`.
- Lab: `scenes/healer_lab.tscn` (`healer_lab.gd`). It renders every read test below:
  `godot --path . --resolution 1920x1080 -- --scene res://scenes/healer_lab.tscn --shot <dir>` (round 2: add `--set v2`).

**Status (the user, 2026-10-20):** "I like the water cooler idea. It is placed too high. But the monster doesn't look like
a healer in any way. Their body looks very heavy compared to the other monsters, closer to the brute than anything.
Alternatives?" and, on the eyeball, "looks great but doesn't read as a healer ... Useful model for the future tho with a
different enemy type." So: **the Water Cooler's prop and its area pulse stay**; its carrier is redesigned in **§7
(round 2)**; the Night Nurse is **parked as a future enemy, not a healer** (§3 B). §3-§6 are round 1, kept as the record.

## 1. What has to be true

- **It reads at the game camera** (CameraRig: yaw 45, pitch -56, ortho size 24, 1920x1080) at least as well as a grunt.
- **It is the priority target** in a pack: the eye should find it before the brute.
- **Colour rules:** spells own the cool, saturated colours. Every healer's glow (eyes, fluid, lens, charge) is the
  **enemy chartreuse** `BILE = (0.80, 1.0, 0.16)`: yellower and paler than Vines `(0.45, 0.78, 0.22)`, nowhere near
  Heal's mint `(0.35, 0.95, 0.5)`. No red cross: it is a protected emblem. The caps and badges are plain.
- **Fiction:** a deadpan corporate exorcism. The monsters have taken over the client's staff and fixtures (the grunt
  is the bunker's old security detail, the brute the owner's bouncer in suit trousers). A healer is the site's
  occupational health, facilities or HR, gone to hell.

## 2. How big the old medic was

Every model alone at the game camera, no floor, no bloom (`measure.txt`). Pixels covered at 1920x1080:

| Model | Pixels | | Model | Pixels |
|---|---|---|---|---|
| Imp (swarmer) | **686** | | Wick | 2,306 |
| Goblin scout | 1,570 | | Gasket | 3,728 |
| Archer | 1,946 | | Rebar | 7,826 |
| Grunt | **1,953** | | Company Nurse (iv_nurse) | 1,977 |
| Brute | **6,129** | | Night Nurse (eye) | 3,560 |
| Water Cooler (cooler) | 6,092 | | Orderly | 5,835 |

The Imp Medic was the imp's body plus a coat and a jar: about 700-900 pixels, **a third of a grunt and a ninth of a
brute**. In a pack it sits behind a brute that is eight times its size. The user is right: it cannot be the thing the
eye finds first. Every option below is grunt-sized or bigger.

## 3. The concepts

Sizes are against the grunt (2.2 tall, 0.75 wide) and the brute (2.7 tall, 2.1 across the fists).

### A. Water Cooler (area pulse) [blockout]
*"Hydration is mandatory."* The site's facilities demon, with the office water cooler strapped to its back.

- **Silhouette:** a squat, broad demon (burnt-orange skin, the charcoal company polo, a lanyard) under a white cooler
  cabinet. The upside-down 5-gallon jug glows chartreuse at **3.1 m**, the highest point in any pack. Brute footprint
  (6,092 px), grunt width. The jug sits above the brute's horns, so the brute never hides it.
- **Mechanic:** every 5 s it plants and pours. A 0.8 s **tell** (the jug bubbles and flares, it hunches and grips its
  straps), then a **pulse**: rings run out to **r 5** and every monster inside gets **+15** (imps included; never
  itself). HP 60, speed 2.4. It hangs back at the pack's centre, 7-10 from the nearest hero.
- **Counters:** kill it (a big job: 60 HP) or **move it**. Tentacles or the bowl pull it out of its pack, a shove during
  the tell cancels the pour, a daze cancels it. Vines does nothing useful (it pours standing still), which gives the
  spells different jobs. Because it pulls its pack into a clump, **teeth, corn and fireball are at their best** next
  to it: "it's clumping them, teeth on the cooler!"
- **Networking:** a host-owned monster. The pour is one reliable event `world.pulse {id, t}` (`NetEvents.WORLD_CARRIES`);
  every machine draws the rings from it. The host applies the heals: it owns every monster, so the loop over
  `actors_in_radius` asks `Net.resolves(a)` (networking rule 3) and only the host's lands. Late joiner: nothing (a pulse
  is instantaneous; `NetEvents.LATE_JOIN`).

### B. Night Nurse (multi-tether, floating) [blockout] **[parked: a future enemy, not a healer]**
*"Occupational health is watching."* The hellgate's own monitor: a floating eyeball in a paper nurse's cap.

> **Parked (2026-10-20).** The user liked the model but it does not read as a healer: the nurse does not come across on a
> floating eye. The blockout stays in the lab (`HealerBlockouts.build("eye")`, `healer/eye` in ZFightModels) for a
> different enemy. Ideas for it, without the cap: a **watcher / alarm** (it spots the crew and calls the room's monsters,
> the goblin's "!" without the fireworks), a **laser sentry** (it hovers out of melee and sweeps a beam, the vines
> pull-down still the answer), or a **hellgate scout** (it drifts ahead of a gate's wave and marks where it lands).

- **Silhouette:** an orb 1.4 across floating at 2.45, the cap on top (3.5), five fleshy tendrils with glowing tips
  hanging to 1.0, a shadow disc on the floor. 1.8 grunts (3,560 px). It floats over the crowd, so nothing stands in
  front of it, and the shadow tells you where it is.
- **Mechanic:** tethers **up to three** monsters within 6 at once, **+5 HP/s each**, for up to 4 s, then 2 s rest.
  **Tell:** the iris flares and the tendrils spread toward the patients. HP 40, drifts at 2.8 behind the pack.
- **Counters:** it hovers **above melee** [question 3]: arrows, spells and thrown things only. **Vines or tentacles pull
  it to the floor** for 3 s, where Gasket and Rebar can hit it. A hero walking through a tether snaps it. "Vines the
  eye!" then the hammer is the call-out this enemy exists for.
- **Networking:** host-owned. `tethers` (up to three ids) is `OWNER`, carried by a reliable `world.tether {id, ids}` on
  each change; every machine draws the lines. The heal ticks are the host's (`Net.resolves`). Grounded is a status set
  through `set_modifier` by the eye's owner (the host); a client's vines on it is already a request. Late joiner: the
  keyframe carries `tethers`.

### C. Orderly (revive) [blockout]
*"No one clocks out early."* A brute-sized orderly in hospital whites, pushing a gurney with a car battery and jumper
cables.

- **Silhouette:** 2.6 tall, the brute's mass (5,835 px), and a **gurney 1.9 long on legs** out in front: the only
  rectangle on the floor. Purple-grey skin, whites, a chartreuse badge and eyes, the battery's charge strip and clamps
  glowing.
- **Mechanic:** when a non-imp monster dies within 8, its body **lingers 6 s** instead of fading. The orderly wheels to it,
  clamps the cables (1 s tell: sparks, the battery flares), a 2 s **jolt** ("CLEAR!"), and the monster **stands up at
  50% HP**. HP 90, speed 2.2. Any hit of 10 or more, a shove or a daze breaks the jolt.
- **Counters:** kill the orderly (big); **stand on the body** (a hero within 0.6 blocks the clamps); **cremate it**:
  a fireball, corn or teeth on a body removes it ("no body, no claim"); or kill fast enough that it is always walking.
- **Networking:** the heaviest. A lingering body becomes a host-arbitrated world object (`Session.objects`, like a
  crate): a client's fireball on it is a request (`Net.request`). The revive is the host spawning the same kind at 50%
  HP through `world.spawn` and the body going to the gone ids. Late joiner: bodies in the keyframe, gone ids as usual.
  It also needs bodies to linger (today they fade over `DEATH_TIME`).

### D. Company Nurse (single beam, the original mechanic) [blockout]
*"Fit to return to work."* A tall, gangly ghoul in maroon scrubs, a bouffant cap and a mask, pushing a wheeled IV stand.

- **Silhouette:** 2.3 to the cap, the pole to 3.0 with a glowing bag. **Grunt-sized in pixels (1,977) but thin**: a
  pale stick with a small glowing bag on top.
- **Mechanic:** §3 of `combat-proposals.md` as it stands, with the beam as an **IV line**: it picks the most hurt
  monster in 7, a 0.5 s tell (it straightens and lifts the line), then a 2.5 s drip of **+12 HP/s** (30). HP 30, speed
  3.6, 4.2 fleeing. The line breaks on any hit, a shove, a root, a daze, a hero stepping through it, or the patient
  shoved out of range. Shoving the nurse **knocks the stand over** (1.5 s to right it).
- **Counters:** arrows, corn, fireball, the hammer kill it in one or two; vines roots it; the chicken's pecks break it;
  Rebar body-blocks the line.
- **Networking:** as `combat-proposals.md` §3.6 (`world.beam`).

### E. Wellness Coach (healing zones) [concept only]
*"Breathe in. The invoice breathes out."* A guru-client cultist in a long robe carrying a tall reed diffuser.

- **Silhouette:** a tall cone of robe (2.4) with a vase of sticks held up and a chartreuse plume. Risk: the hooded archer
  is already a robe; the diffuser and the plume have to do the work.
- **Mechanic:** places up to two **diffusers** (small breakable objects) that breathe a 3-radius mist: monsters inside
  regain **6 HP/s**. **Fireball or corn ignites the mist**: a flash fire that hurts the monsters in it (20). Smash the
  diffusers (one hit) or burn them.
- **Networking:** the diffusers are host-arbitrated world objects; the ignition is a scheduled effect.
- **Why not built:** the zone is a floor decal, and decals read worse than a body; the guru client is one archetype of
  five. A good "floor 3 of a guru site" variant of A.

### F. HR Rep (buff, not heal) [concept only]
*"Your performance is being reviewed."* A skeleton in a grey suit with a clipboard, wheeling a flip chart ("Q3 TARGETS").

- **Mechanic:** every 6 s a "motivational talk": three monsters within 6 are **Motivated** for 5 s (+30% speed and
  damage, a chartreuse lanyard glows on them). A status (`set_modifier`) the target's owner (the host) applies.
- **Why not built:** bone white next to the grunt and the pavise (the reason §3.7 already gave), and a buff is harder
  to read than a heal: the players see faster monsters, not a cause. Funniest fiction of the six.

## 4. Read tests

Renders (1920x1080, the game camera unless noted), in the session scratchpad `medic\`:

| File | What |
|---|---|
| `<kind>_pack.png`, `_pack_crop.png` | the pack: two grunts, an archer, three imps, a brute and the healer at the back, the crew on the left |
| `<kind>_pack_gray.png`, `_pack_crop_gray.png` | the same in greyscale: the silhouette and value test |
| `<kind>_heal.png`, `_heal_crop.png` | the heal effect mocked: pulse, IV line, tethers, jump-start |
| `<kind>_close.png` | low angle: a grunt, the healer, a brute and Wick |
| `lineup.png`, `lineup_gray.png` | everyone in a row, named |
| `sheet.png` | the comparison sheet: the lineup (colour over grey), the four packs, their greys, the four heals |
| `measure.txt` | the pixel table in §2 |

(`_crop` files are a 960x540 window around the fight at 2x, nearest: game pixels stay pixels.)

**What they show:**
- **Water Cooler:** the clearest read. The jug is the brightest and highest thing on the screen in colour **and** in
  grey, above the brute. Its pulse is the clearest effect of the four: every player can see who is inside the ring.
  From above the cabinet reads as a white column with a lamp on it; the water cooler only reads as a water cooler in the
  close view. That is fine: the beacon is the job, the joke is for the close-ups and the HUD name.
- **Night Nurse:** reads well and floats clear of the crowd; the shadow disc places it. Three tethers converge on it, so
  the effect points at the healer. From above it is mostly **white** (sclera and cap), the grunts' value in grey: the
  round shape and the iris glow separate it, not the value. A darker lid or a tinted sclera would help.
- **Orderly:** brute-sized and unmistakable: nothing else is a rectangle on legs, and the whites are the brightest
  large mass in grey. The jump-start mock reads, but the body on the floor is small and the cables are thin: the
  "CLEAR!" column of light does the work.
- **Company Nurse:** the weakest read. Grunt pixels, but spread over a thin figure and a thinner pole; in grey it is a
  pale stick among pale skeletons. Its **IV line is the best single-target effect**: a bright line from the patient
  straight back to the healer.
- **Colour:** in every heal mock the chartreuse reads yellow-green, never mint; nothing is confused with the Heal
  spell. The Vines green is the nearest spell colour; keep the healer's glow pale and yellow. The patient tint
  (additive chartreuse) turns the dark-red brute olive at 0.38; 0.24 (the renders) is enough.
- Not tested: the themed floors (carpet, marble, the pool deck) and a real fight's motion. The lab uses the plain room
  of `monster_lab`.

## 5. Ranking and recommendation (round 1; superseded by §7.3)

1. **Water Cooler (A).** Best read (brute-sized, the beacon on top), the cleanest fiction (every site has one), the
   simplest networking (one event per pour, heals on the host), and it changes how a fight plays: it clumps its pack,
   so the team's area spells matter, and moving it is as good as killing it. Risk: 60 HP of "kill it first" behind a
   brute can feel tanky; tune the pulse (15 every 5 s) before the HP.
2. **Night Nurse (B).** The best teamwork call-out ("vines the eye!") and a job for Wick and the casters. Risk: a
   melee-proof enemy is a new rule (and the AI allies must learn it); the white read needs a darker lid.
3. **Orderly (C).** The funniest, and the biggest. Risk: the most work (lingering bodies, a revive path, cremation), and
   reviving makes fights longer, which the research warns about for one-hit imps (here it never revives imps).
4. **Company Nurse (D).** Keep its IV line if you want a single-target beam on another body; the body itself is too thin.

**Recommendation:** build **A, the Water Cooler**, as the enemy healer for floors 2-3, under §3.5's spawning rules
(never alone, one on floor 2, two on floor 3, paired with a brute or the pavise). Keep **B** as the floor-3 or hellgate
variant once the pull-down rule is settled. E is a guru-site reskin of A if you want one.

## 6. Questions for the user

1. **Which one?** The Water Cooler (recommended), the Night Nurse, the Orderly, or the Company Nurse on a better body?
2. **Area or single target?** The cooler heals everything in r 5, imps included. Fine, or should it skip imps like
   the old medic?
3. **The Night Nurse above melee:** acceptable as a rule (vines or tentacles pull it down), or should melee reach it?
4. **Revive at all?** The Orderly needs bodies to linger for 6 s and a "cremate the body" interaction.
5. **HUD names:** "Water Cooler", "Night Nurse", "Orderly", "Company Nurse"? The client could also bill them
   ("Facilities", "Occupational Health").
6. **The beacon:** should the healer's glow be on all the time (always findable), or dim and flare only while healing
   (a tell, but harder to find)? The renders keep it on.

## 7. Round 2: who carries the Water Cooler

**The brief (2026-10-20):** keep the cooler and the area pulse (§3 A), but lower the cooler (carried at chest or
shoulder height, or set down and tended, never towering) and give it a carrier that reads as a healer or caretaker at a
glance, with a support weight: grunt to archer, lean or soft, never brute-like. The water must still be the brightest
thing in the pack.

Blockouts: `scripts/art/lowpoly/monsters/cooler_carriers.gd` (`CoolerCarriers.build(kind)`, in ZFightModels as
`carrier/<kind>`), lab only like round 1. **The glow is on the water only** (the jug, the pour, a filled cup); the eyes are
the monsters' usual small ember (the acolyte's are closed); the kit box is plain. The pulse is unchanged: a 0.8 s tell, then
rings to r 5 and +15 to every monster inside (§3 A's numbers and networking).

### 7.1 The four carriers

| | **Office Temp** (`temp`) | **Wellness Acolyte** (`acolyte`) | **Water Boy** (`waterboy`) | **Night Janitor** (`janitor`) |
|---|---|---|---|---|
| One line | *"I was told to keep everyone hydrated."* A skeleton intern on placement from the agency | *"Drink. Release. Return to work."* The guru client's staff | *"Water break!"* The sideline medic of the bunker's five-a-side | *"Somebody has to refill it."* The night shift, tending the cooler |
| Body | the grunt's skeleton in a long, soft dusty-rose cardigan, shirt collar, round glasses, an orange lanyard and ID card, a pencil | a soft bell of mid-value linen robe, a terracotta sash, wooden beads, bald with small horns, eyes closed, a small smile | a goblin in a white team polo, an orange ball cap, a whistle on a cord, a towel over the shoulder, shorts and tall socks | a hunched grey ghoul in a drab coverall and flat cap, a rag in the back pocket |
| The cooler | the jug **hugged to its chest** in both arms (1.2-1.8) | the jug **cradled in front** like a vessel, pouring into a paper cup in the other hand (1.1-1.6) | the whole **counter-top cooler on a hand truck** it wheels in front: cabinet, jug (top 1.5), a cup tube, a plain first aid box | the cooler **set down on a cart** beside its mop bucket (jug top 1.4), a sleeve of cups and a filled one; one hand on the tap, the mop in the other |
| Healer cues | carrying with care, the lanyard, "harmless office" | the pour, the cup, the closed eyes, the calm | towel, whistle, first aid box, the cup tube: a sports medic | the cups, the tap; otherwise a cleaner |
| Tell (0.8 s) | it tips the jug forward to pour | it tips the jug into the cup | it raises the whistle | it fills a cup at the tap |
| Height | 2.2 | 1.85 | 1.7 to the cap | 1.9, hunched |
| Pixels (game camera) | **1,568** (0.8 grunt) | **1,710** (0.9 grunt) | **2,483** (1.3 grunts, the truck included) | **2,744** (1.4 grunts, the cart included) |

For weight: imp 686, archer 1,946, grunt 1,953, brute 6,129, and round 1's porter 6,092. All four carriers are grunt to
archer weight in the body; the Water Boy and the Janitor are bigger on screen only because of their wheeled props, which are
low and boxy, not a mass. None is brute-like.

### 7.2 Read tests

Renders (1920x1080, the game camera unless noted) in the session scratchpad `medic\v2\`:

| File | What |
|---|---|
| `<kind>_alone.png`, `_alone_crop.png` | the carrier alone, three-quarters (crop x3, nearest) |
| `<kind>_pack.png`, `_pack_crop.png` | the round 1 pack (two grunts, an archer, three imps, a brute) with the carrier at the back, the crew on the left |
| `<kind>_pack_gray.png`, `_pack_crop_gray.png` | the same in greyscale |
| `<kind>_heal.png`, `_heal_crop.png` | the pulse mocked: the rings, the splash (the acolyte's pour into its cup), +15 over every patient |
| `<kind>_close.png` | low angle, **ortho size 9**: a grunt, an archer, the carrier, a brute and Wick |
| `weight.png` | low angle, ortho 9: grunt, archer, the four carriers, brute |
| `weight_game.png`, `_gray.png` | the same row at the game camera, named, with the imp and round 1's cooler |
| `sheet.png` | the comparison sheet: weight, weight_game in colour over grey, the four packs, their greys, the four pulses |
| `measure.txt` | the pixel table above |

**What they show:**
- **The water is the brightest saturated thing in every pack**, and now low: at chest or waist height it sits among the
  pack instead of over it. It no longer clears the brute's horns, so behind a brute it can be partly hidden from some
  angles; the pulse rings still give it away the moment it pours.
- **In greyscale the jug is not the brightest value**: the bone grunts are as bright. Round 1's jug was alone at the top
  of the frame; low down it competes. The read is colour plus bloom, not value. If that matters (colour-blind players),
  raise the jug's glow gain or give it a soft halo; a value-only read would need a darker carrier and darker neighbours.
- **Water Boy:** the clearest healer read of the four. The white polo, orange cap and towel say "team staff", and the
  cooler on the hand truck is the only one that reads as a water cooler at the game camera (cabinet and jug together). The
  goblin body is light; the truck gives it presence without bulk. Risk: it is a goblin next to the goblin scout; the
  white polo and the truck separate them, and the scout's rockets do not appear here.
- **Wellness Acolyte:** the kindest gesture and the softest, lightest shape. The pour into the cup is lovely in the
  close-up but small at the game camera: what reads there is a pale robe with a glowing jug in front. The linen robe is
  deliberately mid-value so the water wins; a saffron robe (tried first) out-shone the jug.
- **Office Temp:** the hug reads at once (a figure clutching a glowing jug) and is funny, but the body is the thinnest
  (0.8 grunt) and the skull is grunt bone: in grey it is "a small skeleton with a lamp".
- **Night Janitor:** the cart and the set-down cooler read well, and "set down and tended" works, but the carrier reads
  as a cleaner, not a healer. Also the biggest footprint.

### 7.3 Ranking and recommendation

1. **Water Boy** (recommended). Reads as a caretaker at a glance (towel, whistle, first aid box, cups), the cooler reads as
   a water cooler, the water is the bright thing at waist height, and the body is goblin-light. The fiction lands too:
   the monsters take a water break mid-fight, and the hand truck explains why it is slow (2.4) and why a shove (tentacles,
   the bowl) is such a good answer: it tips the truck. "Kill the water boy!" is a good call-out.
2. **Wellness Acolyte.** The best gesture and the guru client's own; the pour is the healer cue, but it is small at the
   game camera. A strong choice for guru sites, or as the Water Boy's reskin there.
3. **Office Temp.** Funniest, clear hug, but too slight and too bone-white next to the grunts.
4. **Night Janitor.** "Set down and tended" reads, the healer does not.

### 7.4 Questions for the user

1. **Water Boy?** Or the Acolyte, or the Water Boy everywhere with the Acolyte on guru sites?
2. **A goblin?** The Water Boy is a goblin like the scout. Keep it, or make it an imp-sized-up "intern" of another kind?
3. **The greyscale read:** is colour plus bloom enough for the healer, or should the jug get a halo so it also wins on
   value?
4. **Does the hand truck tip over on a shove** (the cooler rolls away and the pulse stops until it is picked up)? A fun
   counter, but a new host-arbitrated object.

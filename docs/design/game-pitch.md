# Cast: setting pitches

> **New:** the user's twist on Short Order Sorcery is developed as a full pitch in
> [`pitch-contract-sorcery.md`](pitch-contract-sorcery.md). In it, gig-economy sorcerers
> take dangerous contracts in billionaires' survival bunkers. It is now a co-frontrunner
> with Warcry.

**Cast is an exploration game that uses spoken spells for combat.** It stands on two
pillars:
1. **Exploration:** discovering a procedural hex world with real verticality. You step up,
   climb slowly, and use stairs, ledges, pits, vantage points and hidden areas. See
   `exploration.md`.
2. **Combat through spoken spells:** ordinary attacks plus spells you shout out loud. See
   `voice-mechanic.md`.

Each pitch below has to give a reason to explore *and* a reason that shouted words have
power.

Four directions for the world around those pillars. All four share the same constraints:
- **Camera:** an orthographic isometric camera looking at hex tiles with height levels.
- **Team:** small, so the art has to work as flat-shaded low-poly or something close to it,
  with silhouettes that stay readable at about 40 px tall.
- **Voice:** the fiction has to answer one question: *why does shouting a word do
  something here?*

What reads well in isometric view:
- strong value contrast between floor, walls and actors;
- one saturated accent color per team or spell;
- tops of tiles lighter than their sides, so height levels are obvious at a glance;
- big ground decals for telegraphs, such as the brute's slam ring.

Every pitch below is built around those four rules.

---

## 1. Warcry

**Hook:** *A sworn warband descends into a god's barrow, and the old gods answer whoever
shouts loudest.*

- **Tone:** The straightest Diablo fit. It is gritty, torchlit and heavy, with the warband's
  banter and the occasional absurd answer from a minor god as relief.
- **Why explore:** The barrow-lands are a sprawl of mounds, sunken halls and collapsed
  cairns.
  - Grave-goods lie on ledges and in sealed side-tombs.
  - Each god's shrine sits somewhere high or hidden, and finding one teaches a new
    war cry.
  - The best views come from climbing a mound's crown, where you can spot the next shrine
    or a hidden stair.
- **Why words have power:** Each warrior is oath-bound to a pantheon of old gods. A spell is
  a **war cry that calls on a god by its word**: "Fire!" calls the forge-god, "Heal!" the
  hearth-mother.
  - The gods are proud and impatient. A clean, confident cry gets their full attention.
  - A stammered one gets a distracted, half-hearted answer, which is the fumble.
  - Warbands that cry out *together* are heard best, which explains unison spells.
- **Visual style:** Dark burial mounds and cairns.
  - **Tiles:** hex tiles are stacked turf and fieldstone, and height levels are mound
    terraces. Climbable 2-level steps are rough drystone walls, and stairs are cut stone
    steps.
  - **Lighting:** the floors are dark peat and grey stone, lit by torches and by spell
    light. Warm torch pools against cold blue shadow keep heights easy to read.
  - **Characters:** heavy shoulders and big shield silhouettes, each tinted with a team
    color.
  - **Monsters:** barrow-dead, cave beasts and cultists. Their silhouettes are simple and
    cheap, and they read against the stone.
  - **Spell FX:** each god has one color and one rune that flashes on the ground when its
    cry lands.
- **Corn:** The harvest god is minor, bored and *always* listening. Anyone who says "corn"
  in any context gets an offering back: a burning, cart-sized corn sheaf hurled from the
  sky. The warband treats it as an omen and the dungeon treats it as artillery.
- **Voice hooks the setting gives for free:**
  - War chants for unison casts.
  - "Taboo" barrows, where speaking wakes the dead (silence rooms).
  - Enemy shamans who curse or steal a warrior's god-word.
  - Learning new gods' words as the progression.

## 2. Stonesong

**Hook:** *Dwarven choir-miners sing the mountain open, and the mountain sings back.*

- **Tone:** Earnest, warm, mythic, and a little melancholy. The vibe is Deep Rock meets
  a Welsh male voice choir.
- **Why words have power:** The mountain is alive and hard of hearing. Stone obeys a
  clearly spoken command. Chanting together is louder to the mountain, so unison spells
  are the core fantasy rather than a bonus.
- **Why explore:** The mountain is a vertical maze of basalt shafts. Climbing *is* the
  dwarven craft. The deepest veins and lost forges sit below sheer drops reached only by
  stairs, and the old choir-halls sit above them.
- **Visual style:** Basalt columns, a perfect match for hex tiles with heights. Think of
  the Giant's Causeway as a whole dungeon.
  - **Lighting:** dark slate tiles with lighter tops, plus warm lantern pools and cool
    crystal light. This two-tone scheme makes height easy to read.
  - **Characters:** chunky, short and wide, which suits a high camera.
  - **Spell FX:** sung runes that glow up through the cracks between columns.
- **Corn:** The mountain mishears. A dwarf says "scorn" or "corn" and a granite corncob
  the size of a cart falls from the ceiling. Dwarven scholars insist that the mountain is
  joking.
- **Risk:** It's the most beautiful option and the least funny one, which makes it the
  hardest home for the joke spells.

## 3. Short Order Sorcery

**Hook:** *A diner at the bottom of the dungeon, where every spell is an order shouted at
a kitchen god.*

- **Tone:** Slapstick and loud, with Overcooked energy. Shouting is the point.
- **Why words have power:** The Kitchen Below fills any order called clearly. It's
  "ORDER UP: fireball!" A mumbled order gets you the wrong dish, or a sad one.
- **Why explore:** You forage the dungeon's pantry-caverns for rare ingredients, which
  unlock new orders. It's the weakest exploration motive of the four, because it pulls
  toward a level-based arena structure.
- **Visual style:**
  - **Tiles:** checkerboard and tile-grout hex floors; counters and fridges are walls;
    heights are stacked crates and shelving.
  - **Look:** a bright toy-like palette with chunky props.
  - **Monsters:** angry produce and kitchen pests.
- **Corn:** Corn is on the menu, of course. A crop-duster drops a buttered cob that lands
  on a sizzling plate and explodes. Popcorn is the upgrade.
- **Risk:** The joke has a short shelf life, and "grim dungeon crawl" turns into "party
  game." It also encourages shouting, which leads to voice fatigue and annoyed housemates
  (see voice-mechanic.md).

## 4. Dead Air

**Hook:** *1950s radio operators descend into a buried signal bunker where anything said
on the right frequency comes true.*

- **Tone:** Eerie and retro, like *Control* meets *The Twilight Zone*, broken up by deadpan
  radio banter.
- **Why words have power:** The bunker broadcasts on a frequency reality listens to.
  - You "key the mic" to cast, so **push-to-talk is part of the fiction**.
  - Teammates go by callsigns ("Fox, heal"), so **targeting by voice is part of the
    fiction** too.
  - Static and interference explain fumbles.
- **Why explore:** You map the bunker.
  - Antenna masts on high platforms act as vantage points that reveal the map around
    them.
  - Sealed sub-levels sit down long stairwells.
  - Signal strength hints at hidden rooms.

  It's a strong exploration loop, but a claustrophobic one.
- **Visual style:**
  - **Palette:** phosphor green and amber on near-black, with flat shading, a scanline
    post-process, and hard rim lights.
  - **Tiles:** concrete hex plates with stencil numbers.
  - **Monsters:** silhouettes and "signal ghosts" that glitch.
  - **Cost:** very cheap to produce and very readable, but monotone. It needs one accent
    color per spell to avoid becoming mush.
- **Corn:** "Operation Cornflake." Saying the codeword calls in an airdrop of a single
  enormous ear of corn, delivered by a B-17 you only hear.

---

## Comparison

| | Warcry | Stonesong | Short Order | Dead Air |
|---|---|---|---|---|
| Fit to the brief (Diablo-style co-op dungeon fight) | **Excellent** | Good | Weak (party game) | OK (more horror than action) |
| Exploration motive (vertical, procedural) | **Excellent** (mounds, shrines, sealed tombs) | **Excellent** (shafts, climbing) | Weak (ingredients) | Good (mapping, masts) |
| Voice fiction strength | **Excellent** (cries to gods, war chants) | Very good (unison) | Good (orders) | Excellent (radio, push-to-talk, callsigns) |
| Corn and joke spells fit | Good (a bored harvest god) | Weak | **Excellent** | Good |
| Hex and height fit | Good (mound terraces, cairns) | **Excellent** (basalt) | OK | OK |
| Isometric readability | Good (torch vs shadow) | Good | **Excellent** | Good (monotone risk) |
| Small-team art cost | Low–medium | Medium | Medium | **Lowest** |
| Voice-mechanic enemies | **Built in** (shamans, taboo barrows) | Some | Few | Some (jamming, interference) |
| Longevity | High | High | Low | Medium |

## Recommendation: keep the setting open, with **Warcry** as the frontrunner

**Don't lock the setting until the POC playtest answers one question: do the joke spells
land?**
- **If corn is the moment everyone remembers:** the tone has to make room for comedy.
  Warcry, with its bored harvest god, does that, and Short Order is the fallback if the
  game turns out to be a party game.
- **If the serious spells carry the fun:** Warcry or Stonesong.

**Why Warcry leads:**
- It serves both pillars.
  - **Exploration:** high shrines, sealed side-tombs and mound crowns as vantage points give
    a natural reason to climb and search.
  - **Combat:** shouted war cries.
- It is the closest match to the brief: warriors shouting spells in a dungeon fight.
- Shouting a war cry is the most natural fiction for "say the spell out loud." No one
  needs it explained.
- Unison chants, taboo silence rooms and god-word progression come straight from the
  fiction.
- The dark-stone look is cheap and reads well at isometric scale.

**Steal from the others whatever the final pick:**
- **From Stonesong:** basalt-column levels as a deep biome, and choir-style unison chants.
- **From Dead Air:** callsigns for voice targeting ("heal Fox").
- **From Short Order:** the shamelessness about corn.

### Setting-neutral prototype art rule (use now)

- **Floors:** mid-grey stone. Tile tops are one step lighter than their sides, and each
  height level gets a slightly darker rim.
- **Walls:** dark, cool grey.
- **Heroes:** one team color each, worn as a bright rim or cloak.
- **Spells:** the only saturated colors on screen. Fire is red-orange, heal green, armor
  blue, and corn yellow.
- **Telegraphs:** big ground decals in a single warning color.
- **Feedback:** every cast flashes the word the game heard above the caster. It's the
  clearest feedback the voice system can give, and it fits any setting.

This rule costs nothing and survives whichever setting wins.

# Cast: setting pitches

> **North star:** [`north-star.md`](north-star.md). "Overcooked with magic": chaotic co-op
> where a well-oiled team consistently does well.

> **Full pitch available:** **Contract Sorcery** is developed in
> [`pitch-contract-sorcery.md`](pitch-contract-sorcery.md). Gig sorcerers are sent on
> dangerous contracts: clearing demons out of billionaires' survival bunkers and
> retrieving treasure. It's summarized as pitch #3 below and is a co-frontrunner with
> Warcry.

**Cast is an exploration game that uses spoken spells for combat.** It stands on two
pillars:
1. **Exploration:** discovering a procedural hex world with real verticality. You step up,
   climb slowly, and use stairs, ledges, pits, vantage points and hidden areas. See
   `exploration.md`.
2. **Combat through spoken spells:** ordinary attacks plus spells you shout out loud. See
   `voice-mechanic.md`.

Each pitch has to give a reason to explore *and* a reason why shouted words have power.

Four directions for the world around those pillars. All four share the same constraints:
- **Camera:** an orthographic isometric camera looking at hex tiles with height levels.
- **Team:** small, so the art has to work as flat-shaded low-poly or something close to it,
  with silhouettes that stay readable at about 40 px tall.

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

- **Tone:** The straightest Diablo fit: gritty, torchlit and heavy, with the warband's
  banter as relief.
- **Why explore:** The barrow-lands are a sprawl of mounds, sunken halls and collapsed
  cairns.
  - Grave-goods lie on ledges and in sealed side-tombs.
  - Each god's shrine sits somewhere high or hidden, and finding one teaches a new
    war cry.
  - Mound crowns are the vantage points that reveal the next shrine or a hidden stair.
- **Why words have power:** Each warrior is oath-bound to a pantheon of old gods. A spell
  is a **war cry that calls on a god by its word**: "Fire!" for the forge-god, "Heal!" for
  the hearth-mother.
  - The gods are proud. A clean, confident cry gets their full attention, while a
    stammered one gets a half-hearted answer. That's the fumble.
  - Warbands that cry out *together* are heard best, which explains unison spells.
- **Visual style:** Dark burial mounds and cairns.
  - **Tiles:** hex tiles are stacked turf and fieldstone, and height levels are mound
    terraces. Climbable 2-level steps are drystone walls, and stairs are cut stone.
  - **Lighting:** dark peat and grey stone floors, lit by torches and spell light. Warm
    torch pools against cold blue shadow keep heights readable.
  - **Characters:** heavy shoulders and big shield silhouettes, each with a team color.
  - **Monsters:** barrow-dead, cave beasts and cultists. Their silhouettes are simple and
    cheap, and they read against the stone.
  - **Spell FX:** each god has one color and one rune that flashes on the ground when its
    cry lands.
- **Voice hooks the setting gives for free:**
  - War chants for unison casts.
  - Taboo barrows where speaking wakes the dead (silence rooms).
  - Shamans who curse or steal a warrior's god-word.
  - Learning new gods' words as the progression.

## 2. Stonesong

**Hook:** *Dwarven choir-miners sing the mountain open, and the mountain sings back.*

- **Tone:** Earnest, warm, mythic, and a little melancholy. The vibe is Deep Rock meets
  a Welsh male voice choir.
- **Why explore:** The mountain is a vertical maze of basalt shafts. Climbing *is* the
  dwarven craft. Lost forges sit below sheer drops reached only by stairs, and the old
  choir-halls sit above them.
- **Why words have power:** The mountain is alive and hard of hearing. Stone obeys a
  clearly spoken command. Chanting together is louder to the mountain, so unison spells
  are the core fantasy rather than a bonus.
- **Visual style:** Basalt columns, a perfect match for hex tiles with heights. Think of
  the Giant's Causeway as a whole dungeon.
  - **Lighting:** dark slate tiles with lighter tops, plus warm lantern pools and cool
    crystal light.
  - **Characters:** chunky, short and wide, which suits a high camera.
  - **Spell FX:** sung runes that glow up through the cracks between columns.
- **Risk:** It's the most beautiful option and the most solemn one. Comic fumbles and the
  joke spells may clash with the tone.

## 3. Contract Sorcery (full pitch: `pitch-contract-sorcery.md`)

**Hook:** *Gig sorcerers take dangerous jobs in rich people's survival bunkers: clearing
out demons, recovering treasure, and billing for every hour.*

- **Tone:** Workplace comedy over real danger, satirizing prepper billionaires and the gig
  economy.
- **Why explore:** Each contract type sends you through the bunker for a different reason.
  - A vault you can see before you can reach it.
  - Safes behind art.
  - An escort who can't climb, so you have to find the stairs.
  - Inspections that pay for map coverage.
- **Why words have power:** Licensed sorcery. The crew's dispatch rig listens on an open
  channel and turns a clean spoken call into a spell. A garbled call gets a garbled job.
- **Visual style:**
  - **Tiles:** marble floors and brutalist concrete walls; hydroponics terraces for
    steps, an infinity pool for the pit, and helipad stairs.
  - **Telegraphs:** contractor hazard-stripe tape marks every one.
- **Risk:** The satire can wear thin, and the business loop (damages and audits) mustn't
  make players timid.

## 4. Dead Air

**Hook:** *1950s radio operators descend into a buried signal bunker where anything said
on the right frequency comes true.*

- **Tone:** Eerie and retro, like *Control* meets *The Twilight Zone*, broken up by deadpan
  radio banter.
- **Why explore:** You map the bunker.
  - Antenna masts on high platforms act as vantage points that reveal the map around
    them.
  - Sealed sub-levels sit down long stairwells.
  - Signal strength hints at hidden rooms.

  It's a strong exploration loop, but a claustrophobic one.
- **Why words have power:** The bunker broadcasts on a frequency reality listens to.
  - You "key the mic" to cast, so **push-to-talk is part of the fiction**.
  - Teammates go by callsigns ("Fox, heal"), so **targeting by voice is part of the
    fiction** too.
  - Static explains fumbles.
- **Visual style:**
  - **Palette:** phosphor green and amber on near-black, with flat shading, a scanline
    post-process and hard rim lights.
  - **Tiles:** concrete hex plates with stencil numbers.
  - **Monsters:** silhouettes and glitching "signal ghosts."
  - **Cost:** very cheap, but monotone. It needs one accent color per spell.

---

## Comparison

| | Warcry | Stonesong | Contract Sorcery | Dead Air |
|---|---|---|---|---|
| Fit to the brief (Diablo-style co-op dungeon fight) | **Excellent** | Good | Good (lighter tone) | OK (more horror than action) |
| Exploration motive (vertical, procedural) | **Excellent** (mounds, shrines, tombs) | **Excellent** (shafts, climbing) | **Excellent** (a different reason per contract) | Good (mapping, masts) |
| Voice fiction strength | **Excellent** (war cries, chants) | Very good (unison) | Good (dispatch calls) | Excellent (radio, push-to-talk, callsigns) |
| Hex and height fit | Good (mound terraces) | **Excellent** (basalt) | Very good (bunker levels, pools, climbing walls) | OK |
| Isometric readability | Good (torch vs shadow) | Good | **Excellent** (clean interiors, hazard tape) | Good (monotone risk) |
| Small-team art cost | Low–medium | Medium | Medium (modular interiors) | **Lowest** |
| Voice-mechanic enemies | **Built in** (shamans, taboo barrows) | Some | **Built in** (rogue house AI, sleeping client) | Some (jamming) |
| Meta loop built in | Shrines and gods | Weak | **Strong** (contracts, reputation, payouts) | Medium |

## Recommendation: keep the setting open; prototype Warcry and Contract Sorcery

The two frontrunners answer the same question two ways: **is Cast grim or funny?**
- **Warcry** is the closest match to the brief (warriors shouting in a dungeon fight), and
  a war cry is the most natural fiction for "say the spell out loud."
- **Contract Sorcery** has the strongest structure: every contract type is a different
  reason to explore, and the run/meta loop comes with the fiction.

Both serve both pillars. Let the first playtest decide the tone: if comic fumbles and the
joke spells are what testers talk about afterwards, go with Contract Sorcery. If the big
serious spells carry it, go with Warcry.

**Steal from the others whatever the final pick:**
- **From Stonesong:** basalt-column levels as a deep biome, and choir-style unison chants.
- **From Dead Air:** callsigns for voice targeting ("heal Fox").

### Setting-neutral prototype art rule (use now)

- **Floors:** mid-grey stone. Tile tops are one step lighter than their sides, and each
  height level gets a slightly darker rim.
- **Walls:** dark, cool grey.
- **Heroes:** one team color each, worn as a bright rim or cloak.
- **Spells:** the only saturated colors on screen. Fire is red-orange, heal green, armor
  blue, and corn yellow.
- **Telegraphs:** big ground decals in a single warning color. Hazard-stripe works in any
  setting.
- **Feedback:** every cast flashes the word the game heard above the caster.

This rule costs nothing and survives whichever setting wins.

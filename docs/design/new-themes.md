# New level themes: discussion notes

Status: **[discussion]**, 2026-10-23. Nothing is built.

## The premise (the user's "5th", 2026-10-23)

"Demons & their gate are drawn to their environment. The client's behaviour just set the stage for which demons you get."
The client's folly (today's incident lines) is the bait; hell sends what the stage attracts. Each environment gets its own
demon roster, themed variants of the existing kinds mixed with what is already there (the goo imp, the imp gunner riding
a beast like the laser shark's), plus shared foot soldiers. Local wildlife (the gator, sharks) stays the client's
billed property, not hell's.

## Garden: an indoor grow room (PARKED, 2026-10-23)

The user: "Lets park that thought and then pivot to ghosts."

What the user wants (2026-10-23):
- Themed enemy types for the zone, mixing what is there: plants that turn into enemies when gooed; an imp riding a plant
  that squirts, like the laser shark's gunner.
- No portable greenhouses as props: "We're inside so whatever's growing there is supported by infrastructure like
  ceiling lights" (grow-light rigs, planter beds built into the floor, irrigation, misters, trellises).
- Vines works better in grow areas, and gets more effective everywhere: "Maybe it grows little flowers that pop open and
  release a small amount of gas that confuses or dazes enemies. And in the greenhouse area it does more. So it's a
  two-layer effect for slowing down pursuers." (Today Vines roots everyone in 2.4-3.0 for 1.6-2.2 s.)
- On scope: "I don't know if it's a wing or a room. I think the question is what are the interesting gameplay
  opportunities. What about the room is more than visually different."

Mechanics discussed (the user's reactions):
1. Foliage as soft cover (blocks sight, slows, burns into open floor).
2. Grow lights feed plant enemies; break a rig to darken and stall them.
3. Goo spreads the infestation; Damp washes beds back to sleep. The user: "I like 3 but not sure how to tell that story
   well to the player. Lets hold off."
4. Pollen beds as weapons: shoved into or fireballed, a bed bursts into a daze cloud. The user: "4 seems like it might
   work well with the existing."
5. Dry beds spread fire; ceiling misters douse (and soak you).
6. Vines thrives in planted areas (wider roots, bigger blooms, nearby beds join in).

Open: who the blooms' gas hits (enemies only or everyone, as the roots do); daze (exists) or confuse (new status); which
client owns the grow room.

## Ghost house: haunted contracts

Status: **[discussion]**, 2026-10-28; the mission decided 2026-10-31. Nothing but look tests is built. Decisions are marked with the date and the user's words; the rest is
proposal.

The user (2026-10-28): "I'm thinking about our ghost theme again. I think it actually makes more sense than plants. But
let's think about it from a mission point of view. Because it's not really compatible with the hellgate necessarily. What
if it's a different mission objective - like closing a book or hunting the necromancers? Haunted mansion, crypt, etc. we
can have zombies, ghosts, ectoplasm type things. The ghosts could haunt things like suits of armour or skeletons. We could
mix and match existing themes based on the specific locations. Like a haunted Mansion could have a sewer section. Or a
church or historical mansion could have a crypt."

### The mission [decided, 2026-10-31]
A second **pest family** with its own **source**, in the same contract frame (floors, employees, property damage, invoice).
The user (2026-10-31): "the plan was acolytes on floor one and two, and the grimoire on the last [floor]."
- Floors 1-2: **necromancer acolytes** raising the dead (mobile host monsters that flee and raise bodies; paid per kill).
- The origin (last) floor: **the grimoire**, pulsing out the dead until it is slammed shut or burned (a host-arbitrated
  world object like a hellgate: HP, phases, a pay line). A physical object, never text to read (Cast is not a reading game).
- **One pest family per contract.** The user: "We shouldn't be mixing hellgates and these," and "one pest family per
  contract for now." A haunted contract has no demons or hellgates; a hellgate contract has no ghosts, zombies or acolytes.
- **The haunting is tied to the site.** The user: "Haunting is tied to the site." Haunted mansions and churches get
  haunted contracts; the client does not make a site haunted.

### Sites: a room pool plus sections [proposal]
Sewer clusters and lava caves already mix sections into a floor; a site type becomes a room pool plus a section pool.
- Haunted mansion: library, portrait gallery, ballroom, dining hall, the existing wine cellar; sections: crypt, sewer.
  A conservatory room could carry the parked garden's pollen beds.
- Church / historic estate: nave; section: crypt. (The vestry was dropped and the bell tower removed after their look
  tests: `church-rooms.md`.)
- A villain lair could roll a crypt too.

### Ghosts [decided, 2026-10-28]
- **No spell is required to beat them.** The user: "Generally we want the player to be able to take on any monster without
  a specific spell." Anyone can hit a ghost directly.
- **They keep away unless they hold a body.** The user: "Maybe players can hit ghosts directly but generally they won't get
  near you unless they are holding a body. So killing the body makes them run, but they get hurt in the process." A ghost
  possesses a host (a suit of armour, a skeleton); breaking the host hurts the ghost and sends it fleeing to the next one.
- **Hard to see:** "a soft outline on whatever they possess." **A visual test comes first** ("Lets make sure to do a visual
  test on this"): the outline on a possessed host, and a free ghost, judged on screen before the look is built in. The
  test is built (look-dev only, 2026-10-28): `ghost-look.md`. It has a skeleton, a suit of armour and a wisp in the gym
  and in a look lab, with three choices: outline / rim / shimmer, faint / soft / strong, and pale blue / ecto green.
- **Tentacles pass through ghosts:** physical only, they smash or shove the hosts (the user picked "They pass through
  ghosts"). Swatting a wisp away from its hosts was dropped ("Skip this mechanic at least").
- **The Ghost spell's old "make an enemy lose its target" use is skipped for now** ("Skip this one for now as well").
- **Ghost form (cast Ghost on yourself) makes ghosts easier, not possible:** the user, asked whether it is the only way to
  kill a wisp: "Easier." It is a **whole-body transform** for now (translucent, moving as today's hero; "For now").
  Proposal: in ghost form you see free ghosts clearly and they do not flee from you.
- **Ghost form passes through regular enemies, so it is for fighting ghosts** [decided, 2026-10-31]. The user: "ghost form
  makes it so that you can pass through regular enemies, because you can walk through them[.] So it's for fighting
  ghosts[.]" **Regular enemies still hit a ghost-form hero** (2026-10-31): "A hero in ghost form can be hit by regular
  enemies. You can pass through them but if you wind up in their attack[,] you get hit." Passing through is movement only,
  not safety. Still open: whether a ghost-form hero can hit regular enemies, and its duration and cooldown.
- **Evicting a ghost without breaking its host: wanted, deferred** [2026-10-31]. The user: "We will have to add a way to
  evict ghosts without breaking them. I just haven't thought of one yet. Let's defer."
- **Breaking a possessed antique bills the crew; bones do not** [decided, 2026-10-31]. The user: "Breaking a possessed
  antique[:] it [bills] the crew. But bones don't count." A suit of armour (or any priced antique) goes on the invoice as
  property damage when it breaks, possessed or not; a possessed skeleton is free to smash.
- **Later (a big build):** "I like the idea of ghost mode after you normally die though. That is a huge extra build so
  later." A downed hero would roam as a ghost.

### Zombies and acolytes [decided, 2026-10-29]
- **Zombies stay down unless an acolyte raises them.** The user: "I was assuming that they would be wandering around and if
  they get knocked down the acolyte can bring them back." A downed zombie never gets up by itself; only an acolyte raises
  it, which makes acolytes the ones to hunt first. Asked whether a zombie ever rises on its own, and whether a burnt body
  can be raised: "Let's go with that for now" (no, and no: burning a body makes sure it stays down, useful but never
  required). This replaces the earlier proposal that zombies get back up unless burned.
- **Acolytes travel the map in a procession with monsters**, raising the bodies they come across. The user: "I think
  [acolytes] should actually be traveling around the map as a procession with monsters. So they would come across bodies
  and raise them." Open: what the procession is made of and how it moves (a route, a leader), and whether it is a
  networking shape of its own (a host-owned group of host monsters, like a pack). Built 2026-10-31 with calls to revisit
  (haunted-build-plan.md, "H4 as built"): a leader acolyte, four zombies and a rear acolyte on a loop of 2-3 rooms, a host-owned
  group (route and file PRIVATE) of host monsters, no new networking shape.
- **Coffee raises a downed zombie too.** The user: "the other situations would be when the player uses a heal or coffee.
  Where they get caught in the blast and brought back." Today Coffee touches any team (the haste on everyone in the
  splash, and a downed hero stands up as a coffee zombie), while Heal and Revive touch only the caster's team. Decided:
  "Let's do coffee only for now but revisit heal in a bit before we finish." So a downed zombie in a Coffee splash gets
  back up (spilling coffee near the bodies is a mistake you can make); Heal stays allies-only. **To revisit before the
  milestone ends:** whether Heal raises zombies too. This needs a downed zombie to be a body on the floor (it is not
  gone: an acolyte or a cup can stand it up), unlike today's monsters, which die.
- The look test (look-dev only): `necro-look.md`. The zombie is the thin mourner; a zombie's "about to rise" pose is now
  what an acolyte's raising shows.

### Other enemies [proposal]
- **Ectoplasm:** the infestation layer, like goo: it slicks or slows the floor, and Damp washes it away.
- **More enemy types are needed, later** (2026-10-31). The user: "We will need to think of additional enemy types to
  [flesh] out the levels. We only have skeletons and armor so far." Then: "Let's build it as is." The first build uses
  today's roster (zombies, acolytes, wisps, possessed skeletons and armour, the grimoire); new types come after. Worked
  out in parallel; the user's starting ideas: "ectoplasm monsters or maybe larger than average rats." The look test
  (2026-10-31): `crypt-pests-look.md`, crypt rats (a fast swarm) and an ecto blob that leaves a slick (area denial), three
  variants each. The user picked the sewer brute and the mass of faces, and both are in the game since H3b
  (haunted-build-plan.md, "H3b as built").

### Networking shapes [proposal]
- The grimoire: a host-arbitrated world object (the hellgate's shape). Acolytes, ghosts, hosts and zombies: host monsters.
- A possessed antique is a host monster from spawn, dormant and priced like a prop, with a possessed state (a prop
  turning into a monster fits no shape yet).
- Ghost visibility (soft outline, ghost form seeing them) is cosmetic per machine; who a ghost avoids is host-side.
- The crypt section goes in the floor checksum, like the sewers.

### Open
Answered 2026-10-31: the source (acolytes on floors 1-2, the grimoire on the last), the haunting tied to the site, and one
pest family per contract (The mission); ghost form passes through regular enemies, and a broken possessed antique bills
the crew but bones do not (Ghosts). Still open:
1. Ghost form: can a ghost-form hero hit regular enemies (they can hit it, decided), and its duration and cooldown.
2. Evicting a ghost without breaking its host (wanted, deferred).

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

Status: **[discussion]**, 2026-10-28. Nothing is built. Decisions are marked with the date and the user's words; the rest is
proposal.

The user (2026-10-28): "I'm thinking about our ghost theme again. I think it actually makes more sense than plants. But
let's think about it from a mission point of view. Because it's not really compatible with the hellgate necessarily. What
if it's a different mission objective - like closing a book or hunting the necromancers? Haunted mansion, crypt, etc. we
can have zombies, ghosts, ectoplasm type things. The ghosts could haunt things like suits of armour or skeletons. We could
mix and match existing themes based on the specific locations. Like a haunted Mansion could have a sewer section. Or a
church or historical mansion could have a crypt."

### The mission [proposal]
A second **pest family** with its own **source**, in the same contract frame (floors, employees, property damage, invoice):
- Floors 1-2: **necromancer acolytes** raising the dead (mobile host monsters that flee and raise bodies; paid per kill).
- The origin floor: **the grimoire**, pulsing out the dead until it is slammed shut or burned (a host-arbitrated world
  object like a hellgate: HP, phases, a pay line). A physical object, never text to read (Cast is not a reading game).

### Sites: a room pool plus sections [proposal]
Sewer clusters and lava caves already mix sections into a floor; a site type becomes a room pool plus a section pool.
- Haunted mansion: library, portrait gallery, ballroom, dining hall, the existing wine cellar; sections: crypt, sewer.
  A conservatory room could carry the parked garden's pollen beds.
- Church / historic estate: nave, vestry, bell tower; section: crypt.
- A villain lair could roll a crypt too.

### Ghosts [decided, 2026-10-28]
- **No spell is required to beat them.** The user: "Generally we want the player to be able to take on any monster without
  a specific spell." Anyone can hit a ghost directly.
- **They keep away unless they hold a body.** The user: "Maybe players can hit ghosts directly but generally they won't get
  near you unless they are holding a body. So killing the body makes them run, but they get hurt in the process." A ghost
  possesses a host (a suit of armour, a skeleton); breaking the host hurts the ghost and sends it fleeing to the next one.
- **Hard to see:** "a soft outline on whatever they possess." **A visual test comes first** ("Lets make sure to do a visual
  test on this"): the outline on a possessed host, and a free ghost, judged on screen before the look is built in.
- **Tentacles pass through ghosts:** physical only, they smash or shove the hosts (the user picked "They pass through
  ghosts"). Swatting a wisp away from its hosts was dropped ("Skip this mechanic at least").
- **The Ghost spell's old "make an enemy lose its target" use is skipped for now** ("Skip this one for now as well").
- **Ghost form (cast Ghost on yourself) makes ghosts easier, not possible:** the user, asked whether it is the only way to
  kill a wisp: "Easier." It is a **whole-body transform** for now (translucent, moving as today's hero; "For now").
  Proposal: in ghost form you see free ghosts clearly and they do not flee from you.
- **Later (a big build):** "I like the idea of ghost mode after you normally die though. That is a huge extra build so
  later." A downed hero would roam as a ghost.

### Other enemies [proposal]
- **Zombies:** slow and tough, and they get back up unless burned (Fireball's job).
- **Ectoplasm:** the infestation layer, like goo: it slicks or slows the floor, and Damp washes it away.

### Networking shapes [proposal]
- The grimoire: a host-arbitrated world object (the hellgate's shape). Acolytes, ghosts, hosts and zombies: host monsters.
- A possessed antique is a host monster from spawn, dormant and priced like a prop, with a possessed state (a prop
  turning into a monster fits no shape yet).
- Ghost visibility (soft outline, ghost form seeing them) is cosmetic per machine; who a ghost avoids is host-side.
- The crypt section goes in the floor checksum, like the sewers.

### Open
1. Source: acolytes on floors 1-2 plus the grimoire at the origin, or one of them?
2. Is a haunting tied to the site (mansions, churches) or the client (a haunted lair)?
3. Possessed antiques: does breaking one bill the crew, and is there a way to evict a ghost without breaking it?
4. One pest family per contract (no demons and ghosts together) for now?
5. What ghost form does exactly beyond "easier" (see the proposal above), and its duration and cooldown.

# Combat variety: research and options

Status: research only, 2026-10-19. Nothing here is built or decided. It answers two questions from the user, "what
enemy movement patterns and mechanics do games like this use?" and "what player moves and movement abilities?", and a
third raised the same day: **"the rock guy just goes in and tanks everybody easily. He's always the first to get hits
and almost always the kills."** Every idea is judged against `north-star.md` (player-caused chaos, readable,
recoverable, something to say to each other), the recognizer's latency and the four networking shapes in
`networking.md`. **[proposal]** marks every suggestion; the user decides.

---

## 1. Where Cast's combat is today

### 1.1 What the numbers say
From the logged playtest (the coordinator's count) and from all of `user://combat_log.csv` (238 first hits over 17
seeds, 2026-10-18):

| Fact | Number | Source |
|---|---|---|
| First hits by Rebar (AI ally) in the playtest | 83 of 136; Wick (player) 47, Gasket 6 | playtest log |
| First hits by Rebar, whole log | 130 of 238; Wick 77, Gasket 31 | `combat_log.csv` |
| Mean distance at first hit | Rebar 2.1, Gasket 1.8 (melee), Wick 5.1 | `combat_log.csv` |
| Share of first hits on imps | 172 of 238 (72%); grunts 42, archers 21, brutes 3 | `combat_log.csv` |
| Time from a monster's first hit to its death (median) | imp **0.0 s**, archer **0.0 s**, grunt 0.8 s, brute 2.6 s | `combat_log.csv` |
| Monsters fighting at once (peak per fight) | mostly 4-7 when a fight is a real fight; those last ~7 s (median) | `combat_log.csv` |
| Most-cast spells | teeth and heal | playtest |

### 1.2 Diagnosis
- **Most monsters die to the first hit.** Imps have 12 HP; every hero primary does 12-28. With imps at 72% of the
  fights, "first hit" and "kill" are the same event, so whoever arrives first gets the kills. Fights are a race to
  touch things, not a set of problems.
- **Every monster asks the same question:** "walk up and hit me". Grunt, imp and brute all chase the nearest hero and
  swing; the archer kites. There is nothing to prioritise (no healer, summoner, shield or bomb), nothing that forces the
  crew to split or regroup, and no attack that needs a teammate to answer.
- **The player has no defensive verb.** No dodge, block or parry in a fight. (When this was written there was no revive
  either: a downed hero lay there until corporate revived the crew at the end of the floor. Since 2026-10-27 there is one,
  by voice: coffee stands a downed ally up as a gray, leaking zombie and the Revive spell at half health; spells.md.)
  Defence is walking away or a voice spell, and a voice spell can't answer a 0.3-0.9 s wind-up (section 3.1).
- **Voice is a damage button.** Teeth and heal were the most cast. Teeth is "big damage on a clump", heal is the
  only recovery. Spells that change the shape of a fight (vines, damp, tentacles, chicken) have few targets that
  care: a fight of one-hit imps doesn't need control.
- **Height is mostly a sniping perch.** Brutes can't climb +2 and archers like high ground, but no monster uses height
  against the crew, and shoves off ledges and into walls/pits (`actor.gd:352-363`, which already deal damage) are
  rarely set up on purpose.

### 1.3 Why Rebar carries (from the code)
**His kit is the strongest at what fights currently test.**

| | Wick | Gasket | Rebar |
|---|---|---|---|
| HP | 85 | 120 | **160** |
| Shove taken | x1.3 (light) | x0.6 | **x0 (immovable)** |
| Primary | 12 dmg / 0.4 s, reach 1.3, 90° | 28 / 0.65 s, reach 1.5, 90° | **26 / 0.8 s, reach 1.8, 120°** |
| Secondary | arrow: 12 tap, 28 drawn (0.7 s draw, walk at 50%) | spin: 16, reach 1.9, 1.4 s cd, shoves teammates | **bowl: 6 dmg + 3.5 shove, 2 s cd, 9 range, passes through a whole line** |
| Climb | +2 at 0.6x | +2 at 0.25x | +1 only |

Everyone walks 4.5 (`hero_kit.gd:12`). Rebar's fist has the longest reach and widest arc, so one punch kills every
imp in a 120° cone, and his bowl tags a whole clump from 9 away every 2 s. He can't be shoved, so nothing ever moves
him off the front.

**The AI ally leads instead of following** (`scripts/heroes/ally_brain.gd`):
- `_pick_target()` takes the **nearest monster to the ally** among all monsters within `ENGAGE_RANGE` 9 of the leader.
  It has **no line-of-sight check, no awareness check** (idle, unaware monsters count) and **no wait** for the player to
  engage. It runs every physics frame, so the AI's "reaction time" is zero.
- Both AI seats are melee (`HeroFactory.make_ally(h, leader, false, ...)`: `prefers_ranged` is false), so both charge.
  Rebar's formation slot (2.6 hexes, `AI_SEATS`) is the closer of the two.
- `_try_secondary()` bowls first whenever a target is 3-9 away with LOS: the AI opens most fights from range before
  the player has aimed.
- The AI never casts, dodges or reads a wind-up; with 160 HP and an immovable body it doesn't need to.

**And monsters reward the one in front** (`monster.gd:722-805`): `_nearest_hero()` picks the nearest hero and the
1 s retarget only switches to a hero at least 2 units closer. So the hero who walks in first collects every monster.
No monster flanks (Option 5 of `monster-awareness.md` is held back), shoots past the front line, breaks armour, or
pins someone so a teammate must help. **Face-tanking is never wrong.** A swarm biting Rebar for 4 per 0.9 s each dies
to his next punch.

**So:** a tank with the best damage, an AI that engages first at zero reaction time, and monsters that only fight
whoever is closest. Each one alone would be fine; together they make Rebar the protagonist.

---

## 2. Enemy movement patterns and mechanics

### 2.1 Movement archetypes
Fit: how well it suits Cast (voice latency, isometric hex levels, 1-3 players plus AI, networking shape). Every monster
is a host-owned actor; strikes on a hero are a wind-up event each victim resolves (`world.windup`).

| Archetype | What it is | Done well in | Why it creates decisions | Fit for Cast |
|---|---|---|---|---|
| **Charger** | Winds up, then rushes in a line it can't steer | Doom's demons "push" the player ([Thompson](https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-)) | Sidestep or eat it; a charge into a wall or ledge is a payoff | **High.** The line is a floor decal (readable), the dodge is a key, and a skeleton charge is Option 5 already. Wind-up event, victim decides |
| **Flanker** | Paths to the side or back of its target instead of straight in | Imp flanking is Cast's own Option 5; "battle circle" spacing ([Tuts+](https://code.tutsplus.com/battle-circle-ai-let-your-player-feel-like-theyre-fighting-lots-of-enemies--gamedev-13535t)) | Stops a single tank holding a line; the backline must look around | **High.** The cheapest anti-face-tank tool. Host AI only |
| **Kiter** | Keeps a band of distance, retreats when approached | Cast's archer; Doom's ranged demons keep their distance in the open ([Thompson](https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-)) | Someone has to chase or root it | Already in. Make it pick the **least-protected** hero, not the nearest |
| **Burrower / ambusher** | Hides (underground, in a prop) and pops up near the crew | Gungeon's chest mimics breathe as a tell ([wiki](https://enterthegungeon.wiki.gg/wiki/Mimic)) | Rewards scouting and call-outs ("that crate is breathing") | **Medium.** A mimic prop fits the luxury interior and the exploration pillar. Host-arbitrated object that becomes a monster |
| **Leaper** | Jumps a gap or level to land on a target | Hades gives each enemy its own way over magma: hopping, floating, dashing ([Kotaku](https://kotaku.com/hades-level-design-is-less-random-than-it-seems-1845254545)) | Height stops being a safe perch; the landing spot is a decal | **High.** Imps hopping +2 ledges answers sniping from high ground. Wind-up event with a landing ring |
| **Teleporter** | Blinks when hurt or to reposition | Helldivers 1 Illuminate teleport when damaged ([wiki](https://helldivers.wiki.gg/wiki/Illuminate)) | Breaks focus fire; players note it can frustrate | **Low.** Hard to read at isometric zoom; feels random, not player-caused |
| **Orbiter / circler** | Circles the target and darts in | Cast's imp already circles while its bite recharges | Gives a window to hit it | In. Fine as is |
| **Swarmer** | Many weak bodies | Cast's imps; Helldivers' bugs and bots "overwhelm with numbers" ([wiki](https://helldivers.wiki.gg/wiki/Illuminate)) | Area spells shine | In. The problem is that it is 72% of the fights |
| **Turret** | Doesn't move; area denial | Diablo III Arcane Enchanted's spinning beams ([maxroll](https://maxroll.gg/d3/resources/elite-affixes)) | Forces movement through a space | **Medium.** A hellgate could fire; a "lamp" turret fits the decor |
| **Summoner** | Makes or raises more enemies | Diablo II's Fallen Shaman raises dead Fallen, so you kill it first ([diablowiki](https://diablo2.diablowiki.net/Fallen)) | A priority target; "kill the shaman!" is a call-out | **High.** An imp shaman in each clump makes the clump a puzzle. Host spawns (`world.spawn`) |
| **Shielder / bodyguard** | Blocks hits from the front, or protects another | Helldivers 1 Obelisk projects an energy wall ([wiki](https://helldivers.wiki.gg/wiki/Illuminate)) | Must be flanked, turned or shoved | **High.** A shield skeleton punishes a lone tank in front. Facing is already streamed |
| **Healer / buffer** | Heals or buffs allies | Risk of Rain 2's Malachite elites heal nearby elites (fan guides, [rogueranker](https://rogueranker.com/artifact-of-honor-ror2/)) | Priority target | **Medium.** Overlaps the summoner; pick one |
| **Exploder / suicider** | Runs in and blows up after a fuse | L4D's Boomer was built to break "shoot everything that moves" ([Shacknews, GDC](https://www.shacknews.com/article/57892/left-4-dead-at-gdc)) | Kill it far away, or shove it back | **High.** A fused imp is funny, readable (a lit fuse) and pays off shoves and props. Wind-up event |
| **Splitter** | Splits into smaller copies on death | Common in roguelikes (no source checked) | Rewards area damage | **Low.** More one-hit imps is the current problem |
| **Grabber / pinner** | Holds a hero until a teammate frees them | L4D Hunter and Smoker pin a survivor; a teammate's shove frees them ([L4D wiki](https://left4dead.fandom.com/wiki/Melee)) | The strongest co-op enemy there is: it needs a teammate | **High** for co-op, **medium** for networking: the pin is on the victim's machine, the rescue is a hit on a host monster. Must have an AI-ally answer for solo |
| **Alarm / scout** | Calls reinforcements | Cast's goblin; Helldivers' patrols raise alarms ([wiki](https://helldivers.wiki.gg/wiki/Illuminate)) | Kill it first or quietly | In (goblin scout) |

### 2.2 Telegraphs and attack tokens
- **A telegraph is the question the enemy asks.** Mike Stout frames enemies by the questions they pose ("can you
  avoid my damage?"), and says the player must know damage is coming before it lands
  ([Stout](https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing)). Sound, a flash and a charge-up
  effect are the usual parts. Cast has the visual half (the grunt's orange pulse, the brute's filling red ring); sound
  is waiting on the Sfx system.
- **Keep one cue for one meaning:** the same colour for "unavoidable" or "stand clear" everywhere. Cast's red floor ring
  (brute, origin gate) is a good start; make it the rule for any "leave this area".
- **Attack tokens.** In Doom (2016) each attack type has a limited pool of tokens; a demon takes one to attack and gives
  it back. Difficulty sets the pool size, and an on-screen demon can steal a token from an off-screen one
  ([Thompson](https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-)). The same article says demons
  that can't attack keep moving instead of standing still. "Kung fu circle" and "battle circle" versions reserve slots
  around the player and let one or two attack at a time
  ([Tuts+](https://code.tutsplus.com/battle-circle-ai-let-your-player-feel-like-theyre-fighting-lots-of-enemies--gamedev-13535t));
  one developer warns it can look like a school-yard fight with ten circling and two fighting
  ([gamedev.net](https://www.gamedev.net/forums/topic/701048-tactical-circle-system/)).
  **For Cast:** tokens **per hero** fix two things at once. Fewer monsters swing at one hero (fair), and a monster
  without a token goes to the hero who has spare tokens, which spreads the fight across the crew (anti-face-tank).
  Host-only (`PRIVATE`), no network cost.
- **Fairness tricks from Doom:** demons don't start new attacks during a glory kill, and accuracy drops as the player
  moves faster ([Thompson](https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-)). Cast's equivalent:
  no new wind-ups on a hero who is mid-cast (the voice is the player's "busy" moment).

### 2.3 Group composition (fodder, elites, specialists)
- **Enemies as chess pieces.** Doom Eternal's Hugo Martin describes the demons as chess pieces that move the player
  around, and the team placed them to stop players picking a fight apart from a safe corner
  ([Shacknews](https://www.shacknews.com/article/116635/hell-razer-the-making-of-doom-eternal?page=4)). The useful idea
  for Cast: **each pack has one piece that changes what the crew must do** (a shaman to kill first, a shield to flank,
  a fuse imp to shove away) and fodder around it.
- **Pack recipe [proposal]:** fodder (imps, skeletons) plus **one specialist** per pack, plus at most one elite or brute
  per room. Today a pack is one kind; mixing kinds is the cheapest variety there is, since the kinds exist.
- **Scouts and heavies.** Helldivers 1's Illuminate scouts spot players and heavier units teleport in; patrols are weak
  but raise alarms ([wiki](https://helldivers.wiki.gg/wiki/Illuminate)). Cast's goblin already does this.

### 2.4 Elite modifiers (affixes)
- **Diablo III:** an elite pack has 1 to 4 affixes as the game goes on, and some pairings are banned (Wormhole never with
  Vortex or Jailer). The dangerous pairs are crowd control (Waller, Jailer, Vortex) plus area damage (Arcane Enchanted,
  Molten, Frozen) ([maxroll](https://maxroll.gg/d3/resources/elite-affixes)).
- **Risk of Rain 2:** elites carry an element: Blazing leaves fire, Overloading turns HP into shield, Glacial freezes,
  Malachite heals other elites (fan guides disagree on details; [rogueranker](https://rogueranker.com/artifact-of-honor-ror2/)).
- **Hades:** "Armored" enemies have a yellow bar that must break first, and they ignore stagger and knockback until it
  does ([Prima](https://primagames.com/gaming/how-to-break-enemy-armor-in-hades-2)).
- **For Cast [proposal]:** affixes that **talk to existing spells**, so a spell becomes the answer: *Soggy* (can't burn:
  use something else), *Caffeinated* (fast, then crashes), *Armored* (immune to shoves until the plate breaks: shoves
  and vines stop working, fireball breaks plate), *Rooted* (vine-wrapped, immovable). One affix per elite, shown on the
  model (drips, steam, a plate). A `SPAWN` field on the monster; host AI.

### 2.5 Enemies that react to the crew
- **Armour phases.** Hades' armour turns "how do I kill it" into "how do I break it"
  ([Prima](https://primagames.com/gaming/how-to-break-enemy-armor-in-hades-2)). In Cast, a brute's plate that only
  breaks to a fireball, a wall slam or a teeth pop gives voice a job that a fist can't do.
- **Interrupt windows.** A channel of 2-3 s (a shaman's raise, the goblin's fuse) is the right length for a voice answer
  (vines, damp, a shove). Cast already does this with the goblin: soak him and the fuse is a dud.
- **Weapon-specific reactions.** Doom's imps stop when hit by the assault rifle
  ([Thompson](https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-)). Cast's equivalent: each kind
  reacts to one spell in a visible way (a chicken already pulls a monster; corn could scatter imps).
- **Counter-spells.** Not recommended now: a monster that cancels a player's spell makes a voice miss feel like the
  machine's fault (`voice-mechanic.md`: "misses are free").

### 2.6 Difficulty: crowd size vs behaviour
- Doom scales the **token pool**, not the crowd ([Thompson](https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-)).
  Diablo III scales **affix count** ([maxroll](https://maxroll.gg/d3/resources/elite-affixes)). L4D's Director places
  enemies from player skill, health and time since the last attack
  ([Booth, AIIDE 2009](https://www.readkong.com/page/the-ai-systems-of-left-4-dead-michael-booth-valve-9664541)).
- Cast's hellgates scale burst size and cap with depth and difficulty (`hellgate.gd`). **[proposal]** Scale **behaviour
  first**: tokens per hero (1 → 2 → 3), specialist share per pack, affixes per elite. More imps only makes area spells
  stronger and Rebar richer.

---

## 3. Player combat moves and movement abilities

### 3.1 Keys for reflexes, voice for tactics
- **Cast's timings.** A spoken spell lands ~0.15 s after the voice stops (`voice-mechanic.md`), and online casts land
  `NetCasts.LEAD` (~0.2 s) later on every machine. "Cast armor" takes ~0.5 s to say. **From the decision to the effect
  is ~0.85 s**, plus human reaction.
- **What that means for telegraphs:**

  | Tier | Wind-up | Answer | Cast today |
  |---|---|---|---|
  | Reflex | 0.3-0.9 s | movement or a **key** (dodge, block) | imp bite 0.3, grunt 0.35, brute 0.9 |
  | Tactical | 1.5-3 s | **voice** (vines, damp, armor, a shove spell) | goblin light + fuse 3.0 s, teeth growth 1-2 s |

  The brute's 0.9 s slam is on the edge: armor said the instant the ring appears lands about as the slam does. The
  north star's "armor called before the slam lands" works only if someone calls it early.
- **What voice games learned:**
  - There Came an Echo made concessions for voice: automatic cover, preset move points and a delay between order and
    action; fights were paced so players could see where units could go
    ([TechRaptor](https://techraptor.net/content/came-echo-review-dont-yell)). It also let players alias every command
    ([PlayStation Blog](https://blog.playstation.com/2014/04/10/there-came-an-echo-voice-controlled-strategy-on-ps4/)).
  - EndWar used voice for orders to units ("unit, attack", "retreat", "regroup"), with full non-voice controls as a
    fallback; its developers say voice was a building block of the whole design
    ([bit-tech](https://bit-tech.net/reviews/gaming/xbox/tom-clancy-s-end-war-interview/1/),
    [Shacknews](https://www.shacknews.com/article/47087/tom-clancys-endwar-first-look)).
  - Mage Arena: saying spell names is the whole game, and mispronunciations cause funny accidents
    ([Wikipedia](https://en.wikipedia.org/wiki/Mage_Arena)). In Verbis Virtus cast spells by reciting incantations
    (PocketSphinx) ([Wikipedia](https://en.wikipedia.org/wiki/In_Verbis_Virtus)).
  - Research: players praise voice for focus and naturalness and complain about accuracy, social awkwardness and
    inefficiency ([Carter et al., CHI PLAY 2015](https://dl.acm.org/doi/pdf/10.1145/2793107.2793144)); recognition
    errors add a layer of challenge that frustrates, and game context can improve recognition
    ([CHI 2024](https://dl.acm.org/doi/10.1145/3613904.3642426)).
  - **Lesson:** every voice game that worked put voice on **choices** (which spell, which unit, which order) and kept
    timing-critical motion on the hands or automated. Cast should do the same: dodge, block and revive on keys; what
    to cast, where and on whom by voice.

### 3.2 Catalogue
| Move | Done well in | Why it creates decisions | Key or voice | Fit for Cast |
|---|---|---|---|---|
| **Dodge roll / dash with i-frames** | Gungeon: invulnerable for the first half of a ~0.7 s roll ([wiki](https://enterthegungeon.wiki.gg/wiki/Dodge_Roll_(Move))); Hades' dash is the main way to avoid attacks ([PC Gamer](https://www.pcgamer.com/hades-guide-tips-and-tricks)) | Commit vs wait; reposition | **Key** | **High.** Owner authority makes it lag-free: the victim decides hits on its own hero, so an i-frame on my screen is real. Owned actor, `OWNER` state |
| **Dash charges / chaining** | Hyper Light Drifter: chained dashes on a rhythm, no block (player reports, [Steam](https://steamcommunity.com/app/257850/discussions/0/365163686057644206)) | Skill expression | Key | **Low.** Mastery for one player; Cast's ceiling is the team |
| **Dash attack / barge** | Hades' dash-strike (common knowledge, not checked in a source) | Gap close with damage | Key | **Medium.** Gasket's shoulder barge as her dash (a shove) |
| **Blink / teleport** | Wizard of Legend's dash arcana ([wiki](https://wizardoflegend.fandom.com/wiki/Searing_Rush)) | Escape | Key or voice | **Low** as a key (hex climbing gets messy); **medium** as a spell ("cast swap": trade places with a teammate) |
| **Leap / climb jump** | — | Reach high ground fast | Key | **Medium.** Wick's fast climb already does this |
| **Self-knockback / recoil** | — | Movement from attacks | — | **Low** |
| **Sprint** | — | Travel | Key | **Low.** Coffee is the sprint |
| **Block / brace** | Tunic: the shield blocks most attacks for stamina; the parry reflects projectiles but players find it hard to time ([Ludo](https://www.ludo.guide/guide/tunic/game-systems-and-mechanics/combat-system/blocking-and-dodging), [Steam](https://steamcommunity.com/app/553420/discussions/0/4778901811095664619)) | Hold ground vs move | Key | **High for Rebar only:** a brace instead of a dash ("I'm the wall": monsters near him strike him, he takes less) makes the tank a choice, not a stat |
| **Parry / reflect** | Tunic, above | Timing reward | Key | **Low.** Tight windows are bad with 0.2 s puppets and the swarmer's 0.3 s wind-up |
| **Charge / hold attack** | Wick's draw already; Hades II's Omega moves: hold to charge, costs Magick, leaves you exposed ([maxroll](https://maxroll.gg/hades-2/guides/hades-2-beginners-guide)) | Risk vs reward | Key | In (Wick). Gasket's spin and Rebar's bowl could charge too |
| **Combo strings / cancels** | Gauntlet (2014) wizard: two-button element combos borrowed from Magicka ([Outer Haven](https://www.theouterhaven.net/2014/10/review-gauntlet-2014)) | Execution depth | Key | **Low.** Cast's combos should be between players |
| **Backstab / flank bonus** | Cast's goblin has none on purpose | Positioning | — | **Medium** for a shield skeleton (frontal block = flank bonus by another name) |
| **Height advantage** | — | Hold the high ground | — | **Medium.** A ranged bonus from +2 helps Wick and helps exploration; the danger is more sniping. Pair it with leaping imps |
| **Revive** | Children of Morta: hold a button by the body for several seconds, exposed while you do ([LadiesGamers](https://ladiesgamers.com/children-of-morta-co-op-review-pc/)); Ravenswatch's revive altars ([analogstick](https://www.analogstickgaming.com/news/2024/11/14/unity-makes-strength-in-ravenswatch)) | Risk a teammate to save one | **Key** (hold E) | **High.** Cast has no in-fight revive. A request to the downed hero's owner |
| **Meter / ultimate** | Wizard of Legend's signature charges from hits ([wiki](https://wizardoflegend.fandom.com/wiki/Searing_Rush)); Ravenswatch heroes got a second ultimate ([analogstick](https://www.analogstickgaming.com/news/2024/11/14/unity-makes-strength-in-ravenswatch)) | Saves a big moment | Voice | **Medium.** Cast's charges and components are already a resource loop; a meter adds a second one |
| **Unison / chorus cast** | Cast's own design (`voice-mechanic.md` §4, not built) | The team says it together | **Voice** | **High.** The most Cast thing on this list |

---

## 4. Hero roles and the AI ally's place

### 4.1 How other games keep AI companions from carrying
| Game | What the companion does | What Cast can take |
|---|---|---|
| **The Last of Us** (Ellie) | Stays close; enemies can't see her so she never ruins stealth; helps in visible small ways (a thrown bottle, a health pack); her shooting was deliberately limited: low fire rate, hesitant animation ([Kill Screen](https://www.killscreen.com/how-ellies-pathfinding-made-you-love-her/); [GDC 2014](https://gdcvault.com/play/1020364/Ellie-Buddy-AI-in-The)) | A companion should **help the player play**, not play for them. Lower its damage on purpose |
| **Deep Rock Galactic** (Bosco, solo drone) | Attacks hostiles on its own, but the player **marks** a target with the laser pointer to direct it, and commands its rockets ([wiki](https://deeprockgalactic.wiki.gg/wiki/Laser_Pointer)) | The player picks what the AI focuses. In Cast, the aim reticle already snaps: "Rebar, there" |
| **Dragon's Dogma** (pawns) | Inclinations steer behaviour: Challenger goes for ranged foes, Guardian sticks to the Arisen, Medicant heals; they drift with how you play (fan wiki, [Fextralife](https://dragonsdogma.wiki.fextralife.com/Inclinations)) | Give each AI seat a **role**, not just a kit: Rebar guards the leader, Gasket goes for what's hitting the backline |
| **FFXII / Dragon Age** | Gambits and tactics: player-written if/then rules (community descriptions, [Guild Wars wiki](https://wiki-en.guildwars.com/wiki/Feedback:User/Erasculio/If_and_Then_clauses_for_AI)) | Too much UI for Cast. A two-state stance ("hold" / "go") is the voice-sized version |
| **Left 4 Dead** | Bots are "competent human player proxies" ([Booth](https://www.readkong.com/page/the-ai-systems-of-left-4-dead-michael-booth-valve-9664541)); the Director paces the threat, not the bots | Bots replace an absent player; they don't lead |
| **Vermintide 2** | Bots are widely called weak on high difficulty: they need babysitting ([review summary](https://vaporlens.app/app/552500/warhammer_vermintide_2)) | The other failure: too weak is also bad. Aim for "useful, never first" |
| **Hades** (Thanatos) | A rival, not a helper: he races you for kills; tie or win for a reward ([Prima](https://primagames.com/gaming/hades-guide-thanatos-encounter)) | If the AI is going to take kills, make it a contest the player can see and win |
| **Magicka, Helldivers, Divinity: Original Sin 2** | No AI teammates (as far as I found): co-op is humans only; Magicka's friendly fire is always on and reviving is cheap ([Co-Optimus](https://www.co-optimus.com/Interview/613/magicka-is-co-op-spell-casting-meets-monty-python-humor.html)) | When every teammate is human, chaos is attributable. An AI seat should be the **least** chaotic member |

**The pattern:** companions that work **follow, support, and leave the decisive act to the player**. Ellie's damage was
limited on purpose; Bosco waits for a mark; pawns have a role. Cast's AI does the opposite: it picks the nearest
target, engages first and has the best damage.

### 4.2 Making tank, bruiser and support distinct and interdependent
- **Classic MMO tanks hold enemies with threat or taunts.** Designers trying to drop the "trinity" point out that roles
  can be positional instead: a tank that blocks a path, and enemies that pick targets from who is in reach
  ([Game Developer, "It's not a trinity"](https://www.gamedeveloper.com/design/it-s-not-a-trinity-it-s-a-duality)).
- **A tank should take hits for others, not kill for them.** Ravenswatch's own example of a team: Beowulf takes hits at
  the front with his shield while others fire ultimates from mid-range
  ([analogstick](https://www.analogstickgaming.com/news/2024/11/14/unity-makes-strength-in-ravenswatch)). Children of
  Morta's John holds the front while Linda shoots from behind
  ([LadiesGamers](https://ladiesgamers.com/children-of-morta-co-op-review-pc/)).
- **Trade-offs make roles.** Today Rebar has the most HP, the most reach, the widest arc and is immovable. A role
  needs a weakness: a tank that is **slow to kill** (low damage, wide shove) and **slow to move** (Rebar already can't
  climb +2); a bruiser that kills but must be protected (Gasket); a ranged support who sets up and finishes (Wick).
- **Interdependence:** the tank **makes the opening** (shoves, braces, holds a door, holds aggro), the others **cash
  it in**. Concretely: Rebar's bowl lines monsters up or knocks them into a wall; Wick's drawn arrow pierces the line;
  Gasket's spin finishes a clump Rebar has gathered.

### 4.3 Enemies that make a lone tank a bad idea
- **Flankers** go around him to the backline (2.1). **Attack tokens per hero** send monsters without a token to the
  other heroes (2.2).
- **Ranged that skips the front.** Archers target the hero farthest from a melee monster, or the one who just cast.
- **Shield skeletons** block from the front: Rebar's fist hits the shield and someone must come around.
- **Pinners** (2.1): a grabbed hero needs a teammate; a tank alone has nobody to free him.
- **Armour-break and exposure.** L4D's Smoker was added because a tight, SWAT-like team "handled everything"
  ([Shacknews](https://www.shacknews.com/article/57892/left-4-dead-at-gdc)): an enemy built to pull one out of formation
  is the standard answer to a dominant formation.

---

## 5. Combination and co-op mechanics

### 5.1 Spell interactions
What Cast already has, and the next ones worth building. Magicka's elements: wet targets take double damage and
lightning punishes a wet caster; steam wets and removes fire
([LP Archive](https://lparchive.org/Magicka/Tutorial%203)). Divinity: Original Sin's surfaces: rain makes water,
lightning electrifies it and stuns everyone standing in it; fire on oil burns; fire on water makes steam
([Fextralife](https://divinityoriginalsin.wiki.fextralife.com/Environmental+Effects)).

| Combo | State | Setup → payoff |
|---|---|---|
| Damp + fireball | in game | soak a friend so your own fire fizzles on them |
| Damp + any shove | in game | puddles slide +50%, into walls and off ledges |
| Vines + teeth | in game | root them, nobody escapes the pop |
| Heal + teeth | in game | the dentist |
| Chicken + anything | in game | pulls one monster's attention off a hero for 4 s |
| Coffee on monsters | in game | the accident; then the 2 s crash is a window |
| **Fireball + corn on the floor** [proposal] | — | corn kernels left on the floor pop when fire reaches them (popcorn chain). Funny, readable, player-caused |
| **Damp + something electric** [proposal] | planned in `spells.md` (server-room sparks) | an electrified puddle stuns monsters and heroes standing in it: Divinity's best combo, and damp already has the puddle field |
| **Tentacles / bowl + pit, wall, ledge** [proposal] | mechanics exist (`actor.gd:352`) | make the payoff loud: a wall slam stagger, a fall, a pit kill shown with a big hit number |
| **Armored elite + fireball / slam** [proposal] | — | the plate breaks only to a blast or a wall slam: a reason to combine a shove and a fire |

### 5.2 Setups and payoffs between players
- **Gather → burst:** Rebar's bowl or tentacles bunch monsters; teeth or corn lands on the bunch. Already possible;
  pack AI that spreads out (flankers, tokens) makes the gathering a real job.
- **Mark → focus [proposal]:** Wick's drawn arrow marks what it hits for 4 s; spells and the AI ally prefer the mark.
  It turns the player's aim into the crew's target, which is the Bosco lesson.
- **Hold → revive:** one hero braces or armors over a downed friend while another holds E.
- **Unison:** two players say the same spell within 400 ms for a bigger cast (`voice-mechanic.md` §4). The single best
  "something to say to each other" mechanic in the design, not built yet.

### 5.3 The environment
- **Props:** shoves into priced props already stop the slide and bill the crew. An exploding prop (a gas line, a
  champagne tower) that the crew sets off with fire on purpose is the positive version.
- **Pools and wet floors:** damp's puddles; the spa and pool rooms (`pool-options.md`) are natural electrified-puddle
  rooms.
- **Height:** brutes can't climb +2, Rebar can't either. Monsters that can (leaping imps) and can't (brutes) make
  levels a tactical map, as Hades did with magma ([Kotaku](https://kotaku.com/hades-level-design-is-less-random-than-it-seems-1845254545)).
- **Doors:** a door shut on a pack is a chokepoint for a tank; a door a brute breaks through is a surprise. Doors are
  host-arbitrated objects already.
- **Fire and wet:** burning, soaked and puddles exist; the gap is a floor surface that fire spreads on (goo, oil from a
  broken lamp). Contracts already mention goo burned off by fireball.

---

## 6. Recommendations

Ranked by variety added for the cost, highest first. Size: S (a day or less), M (a few days), L (a week+). Shape is
the networking shape from `networking.md`.

### A. The AI ally and roles (the user's priority)
These are **options**; A1 is the cheapest quick fix, A2 and A3 the designed fixes. They combine.

**1. A1. AI ally restraint: follow and support, don't lead.** *[quick fix]* The AI only engages a monster that is
already fighting the crew (hit a hero, was hit by a player, or is in CHASE/ATTACK on a hero), after a short delay
(0.6-1.0 s), and prefers **the monster attacking its leader** over the nearest one; it needs line of sight; its bowl is
for peeling monsters off a hero, not opening. Optionally the AI deals less damage (x0.6), as Ellie's shooting was
limited.
- Builds on: `AllyBrain._pick_target`, `_try_secondary`.
- Size: **S** (about 40-80 lines plus a test).
- Shape: none. The AI runs on the host, all `PRIVATE`.
- Open question: should the AI hold back only until the player engages, or always fight second (never open a fight)?

**2. A2. Rebar as a tank, not a killer.** *[designed fix]* Lower his fist to about 14-16 damage with a bigger shove
(he moves monsters, others kill them), keep the HP and immovability, and give him a **brace** key: while held he walks
slowly, takes less damage, and monsters within ~3 prefer him (a taunt by position). For the AI Rebar, brace when a
wind-up targets the leader.
- Builds on: `HeroKit.DATA`, `set_modifier` (STAT_DAMAGE_TAKEN), `Monster._nearest_hero` (a weight for bracing heroes).
- Size: **S** for the numbers, **M** with the brace.
- Shape: owned actor (the brace flag is an `OWNER` field of `Hero` with a carrier in `NetCodec.HERO_FIELDS`); monsters
  read it on the host.
- Open question: is it OK that a player who picks Rebar kills less, or should each hero have a way to get kills?

**3. A3. Orders for the AI by voice: "Rebar, hold" / "Rebar, go".** *[designed fix]* Two stances: hold (stay in
formation, only defend the leader) and go (engage what the leader aims at, like Bosco's laser mark). It puts the AI
under the player's call-outs, which is the north star's "something to say".
- Builds on: the incantation vocabulary, the aim reticle, `AllyBrain`.
- Size: **M** (recognizer words and aliases need measuring like a spell).
- Shape: a client's order to a host-run AI is a request (`Net.request`); solo is local.
- Open question: are hero names safe in the vocabulary next to spells ("Gasket" vs "cast it")? Should orders need the
  trigger word?

### B. New enemy behaviours
**4. Attack tokens per hero, and spreading out.** Each hero has N melee tokens (1-3 by difficulty); a monster without
one circles or goes for the hero with a spare token; ranged monsters pick the hero no monster is on. Fairer fights,
and the tank can't soak the room.
- Builds on: `Monster._validate_target`, `_nearest_hero`, the swarmer's circling.
- Size: **S-M**.
- Shape: host AI, `PRIVATE`; nothing new on the wire.
- Open question: should difficulty scale token count (Doom's lever) instead of hellgate burst size?

**5. Imp roles in every clump: the fuse imp and the shaman.** A fuse imp lights up (a sputtering fuse, ~1.2 s) and
runs at a hero, then pops (damage and a shove, hurts props). A shaman imp hangs back and raises dead imps with a 2.5 s
channel that vines, damp or any hit interrupts. "Kill the shaman" and "shove the fuse" are call-outs.
- Builds on: `swarmer.gd`, `world.windup`, `world.spawn`, the goblin's interruptible light.
- Size: **M**.
- Shape: host-owned actors; the pop is a wind-up event each victim resolves.
- Open question: should a raised imp be worth no components (Diablo II's raised Fallen drop nothing)?

**6. The shield skeleton.** It blocks hits from its front arc (a clank, a "0"), so it must be flanked, turned (a chicken
peck, a taunt) or shoved; a wall slam or a teeth pop knocks the shield away. It punishes a lone tank in front.
- Builds on: `grunt.gd`, facing (already streamed), `Combat.melee_arc`.
- Size: **M**.
- Shape: host-owned actor; the attacker's machine asks the facing when it resolves its hit (`Combat.resolves`).
- Open question: do spells pass the shield (area from above) or only melee and arrows get blocked?

**7. Leaping imps and the charging skeleton (Option 5, promoted).** Imps hop +1/+2 ledges with a landing ring; a
skeleton hit from out of reach charges in a straight line it can't steer (into walls and off ledges).
- Builds on: `monster-awareness.md` Option 5, the shove/ledge rules, the hex levels.
- Size: **M**.
- Shape: host-owned actors; the landing and the charge are wind-up events.
- Open question: is sniping from high ground something to keep as a reward, or to answer?

**8. One elite affix per room.** Soggy, Caffeinated, Armored or Burning, shown on the model, each answered by a spell.
- Builds on: `Burning`, `Wet`, `set_modifier`, coffee.
- Size: **M**.
- Shape: a `SPAWN` field on the monster plus host AI; the effects are statuses the owner resolves.
- Open question: should affixes come with better component drops (a reason to seek elites)?

### C. New player moves
**9. A dodge on a key, different per hero.** Wick rolls (~2.5 units, i-frames ~0.15 s, 1.2 s cooldown), Gasket barges
(a short dash that shoves), Rebar braces (A2). AI allies use it on wind-ups aimed at them.
- Builds on: `PlayerController`, `Actor.shove`'s slide, the victim-decides rule.
- Size: **M**.
- Shape: owned actor. Lag-free by construction: the victim already decides its own hits.
- Open question: which key (Space or Shift)? Can you dodge up a +1 step or across a ledge?

**10. Revive in the fight.** Hold E by a downed teammate for ~3 s to stand them up at a share of HP; the reviver is
exposed (Children of Morta). Heal on a downed friend could speed it up.
- **Built differently (user, 2026-10-27): by voice, not on E.** "I think I want two different ways to revive. One coffee
  should bring you back but leave you grayscale. With minimum health. And a slow health leak." and "We should also have a
  dedicated revive spell which brings you back about half health and it doesn't have this zombie curse effect." Coffee on
  a body makes a zombie (10 HP, leaking 1.5 HP/s, cured by heals past 75%), the Revive spell (an Aloe leaf) stands them
  up at half health; spells.md has both. The hold-E revive below is not built; the fallback stays: corporate bills
  whoever is down at the end (contracts.md 9).
- Builds on: `use` (E), the downed state, `Ledger` (revive stats for the end screen).
- Size: **S-M**.
- Shape: a request to the downed hero's owner, which stands it up; an AI ally revives on the host.
- Open question: keep "corporate revives at the end of the floor" as the fallback, or charge for it?

### D. Interactions
**11. Make shoves into walls, ledges and pits a visible payoff.** The rules exist (`actor.gd:352-363`: wall slam 8 and
a stagger, fall damage, pits kill monsters). Add a big hit number, a "SLAM!", a stagger long enough to follow up, and
the Armored affix breaking on a slam. Rebar's bowl and tentacles then have a job beyond damage.
- Builds on: `Actor.shove`, the bowl, tentacles, damp's slide.
- Size: **S**.
- Shape: unchanged (scheduled effects; hits through `Combat`); the text is cosmetic.
- Open question: should a slam stagger long enough (~1 s) to be worth a call-out?

**12. Unison casts.** Build `voice-mechanic.md` §4: two players saying the same spell within 400 ms get one bigger
cast. With an AI seat, the AI could join a "chorus" the player starts.
- Builds on: `NetCasts`, voice onset timestamps on the synced clock.
- Size: **M**.
- Shape: scheduled effect; onsets are compared on `host_time()`.
- Open question: should the AI ally ever join a chorus, or is unison for humans only?

**Cheapest set for the next playtest [proposal]:** 1 (AI restraint), 4 (tokens), 11 (slam payoff) and the numbers
half of 2: all S, all host-side, no protocol changes.

---

## 7. Sources
| Link | What it contributed |
|---|---|
| [Tommy Thompson, "Cyber-Demons: the AI of DOOM (2016)", Game Developer](https://www.gamedeveloper.com/design/cyber-demons-the-ai-of-doom-2016-) | Attack tokens per attack type, token stealing, difficulty = pool size, no cover, fairness rules |
| [Shacknews, "Hell Razer: the making of Doom Eternal" p.4](https://www.shacknews.com/article/116635/hell-razer-the-making-of-doom-eternal?page=4) | Hugo Martin's enemies as chess pieces; stopping corner camping |
| [Mike Stout, "Enemy Attacks and Telegraphing", Game Developer](https://www.gamedeveloper.com/design/enemy-attacks-and-telegraphing) | Enemies as questions; a telegraph must warn before damage |
| [Tuts+, "Battle Circle AI"](https://code.tutsplus.com/battle-circle-ai-let-your-player-feel-like-theyre-fighting-lots-of-enemies--gamedev-13535t) | Limiting simultaneous attackers |
| [gamedev.net, "Tactical circle system"](https://www.gamedev.net/forums/topic/701048-tactical-circle-system/) | Kung fu circle slots, and its "school fight" pitfall |
| [Kotaku, Hades level design](https://kotaku.com/hades-level-design-is-less-random-than-it-seems-1845254545) | Each Hades enemy has its own way across magma |
| [Prima, breaking armour in Hades II](https://primagames.com/gaming/how-to-break-enemy-armor-in-hades-2) | Armoured enemies: yellow bar, immune to stagger until broken |
| [PC Gamer, Hades tips](https://www.pcgamer.com/hades-guide-tips-and-tricks) | Dash as the main defence |
| [Maxroll, Hades II beginner's guide](https://maxroll.gg/hades-2/guides/hades-2-beginners-guide) | Omega moves: hold to charge, Magick cost, exposure |
| [Prima, Thanatos encounter](https://primagames.com/gaming/hades-guide-thanatos-encounter) | An AI rival that races for kills, with a reward to beat |
| [Maxroll, Diablo III elite affixes](https://maxroll.gg/d3/resources/elite-affixes) | Affix count scaling, banned pairs, dangerous combinations |
| [Rogueranker, RoR2 Artifact of Honor](https://rogueranker.com/artifact-of-honor-ror2/) | Elite types (fan source, details disputed) |
| [Diablo wiki, Fallen](https://diablo2.diablowiki.net/Fallen) | Shamans raise Fallen; kill the shaman first |
| [Helldivers wiki, Illuminate](https://helldivers.wiki.gg/wiki/Illuminate) | Scouts and alarms, shields, teleport-on-damage, faction roles |
| [Gungeon wiki, Dodge Roll](https://enterthegungeon.wiki.gg/wiki/Dodge_Roll_(Move)) | Roll length and i-frame window |
| [Gungeon wiki, Mimic](https://enterthegungeon.wiki.gg/wiki/Mimic) | Ambusher with a breathing tell |
| [Steam, Hyper Light Drifter chain dash](https://steamcommunity.com/app/257850/discussions/0/365163686057644206) | Chained-dash rhythm (player reports) |
| [Ludo.guide, Tunic blocking](https://www.ludo.guide/guide/tunic/game-systems-and-mechanics/combat-system/blocking-and-dodging) | Block costs stamina |
| [Steam, Tunic parry](https://steamcommunity.com/app/553420/discussions/0/4778901811095664619) | Parry reflects projectiles; hard to time (player view) |
| [Outer Haven, Gauntlet (2014) review](https://www.theouterhaven.net/2014/10/review-gauntlet-2014) | Wizard's Magicka-style button combos |
| [Wizard of Legend wiki, Searing Rush](https://wizardoflegend.fandom.com/wiki/Searing_Rush) | Dash arcana, signature charge |
| [Shacknews, Left 4 Dead at GDC](https://www.shacknews.com/article/57892/left-4-dead-at-gdc) | Smoker added to disrupt disciplined teams; Boomer against shooting everything |
| [L4D wiki, Melee](https://left4dead.fandom.com/wiki/Melee) | A teammate's shove frees a pinned survivor |
| [Booth, "The AI Systems of Left 4 Dead"](https://www.readkong.com/page/the-ai-systems-of-left-4-dead-michael-booth-valve-9664541) | Bots as competent player proxies; the Director's pacing |
| [Kill Screen, Ellie's pathfinding](https://www.killscreen.com/how-ellies-pathfinding-made-you-love-her/) | Ellie stays close, never blows stealth, limited shooting |
| [GDC Vault, Ellie: Buddy AI in The Last of Us](https://gdcvault.com/play/1020364/Ellie-Buddy-AI-in-The) | The talk behind it (Max Dyckhoff, 2014) |
| [DRG wiki, Laser Pointer](https://deeprockgalactic.wiki.gg/wiki/Laser_Pointer) | Bosco attacks what the player marks |
| [Fextralife, Dragon's Dogma inclinations](https://dragonsdogma.wiki.fextralife.com/Inclinations) | Pawn roles (Challenger, Guardian, Medicant) |
| [Guild Wars wiki, if/then AI](https://wiki-en.guildwars.com/wiki/Feedback:User/Erasculio/If_and_Then_clauses_for_AI) | FFXII gambits and Dragon Age tactics as a pattern |
| [Vaporlens, Vermintide 2 reviews](https://vaporlens.app/app/552500/warhammer_vermintide_2) | Bots too weak is also a failure |
| [Game Developer, "It's not a trinity, it's a duality"](https://www.gamedeveloper.com/design/it-s-not-a-trinity-it-s-a-duality) | Roles without threat tables |
| [Analog Stick, Ravenswatch](https://www.analogstickgaming.com/news/2024/11/14/unity-makes-strength-in-ravenswatch) | Tank-front team example, second ultimates, synergies |
| [LadiesGamers, Children of Morta co-op](https://ladiesgamers.com/children-of-morta-co-op-review-pc/) | Hold-to-revive while exposed; front and back roles; tether |
| [Co-Optimus, Magicka interview](https://www.co-optimus.com/Interview/613/magicka-is-co-op-spell-casting-meets-monty-python-humor.html) | Free element combos, friendly fire always on, cheap revive |
| [LP Archive, Magicka tutorial 3](https://lparchive.org/Magicka/Tutorial%203) | Wet doubles damage, steam wets and removes fire |
| [Fextralife, Divinity: Original Sin environmental effects](https://divinityoriginalsin.wiki.fextralife.com/Environmental+Effects) | Water + lightning stuns, oil + fire, fire + water = steam |
| [TechRaptor, There Came an Echo review](https://techraptor.net/content/came-echo-review-dont-yell) | Concessions voice forced: automatic cover, preset points, order delay |
| [PlayStation Blog, There Came an Echo](https://blog.playstation.com/2014/04/10/there-came-an-echo-voice-controlled-strategy-on-ps4/) | Command aliasing |
| [bit-tech, EndWar interview](https://bit-tech.net/reviews/gaming/xbox/tom-clancy-s-end-war-interview/1/) | Voice as a building block of the design |
| [Shacknews, EndWar first look](https://www.shacknews.com/article/47087/tom-clancys-endwar-first-look) | Voice orders to units, non-voice fallback |
| [Wikipedia, Mage Arena](https://en.wikipedia.org/wiki/Mage_Arena) | Speaking spell names as the whole game |
| [Wikipedia, In Verbis Virtus](https://en.wikipedia.org/wiki/In_Verbis_Virtus) | Incantations by microphone (PocketSphinx) |
| [Carter et al., CHI PLAY 2015](https://dl.acm.org/doi/pdf/10.1145/2793107.2793144) | Why players like and dislike voice in games |
| [CHI 2024, context-aware recognition](https://dl.acm.org/doi/10.1145/3613904.3642426) | Recognition errors as extra challenge; context helps |
| Cast code and logs | `ally_brain.gd`, `hero_kit.gd`, `hero.gd`, `monster.gd`, `actor.gd`, `game.gd`, `user://combat_log.csv` |

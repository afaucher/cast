# Cast: content ideas

Spells, enemies, roles and progression, written to be setting-neutral, since the setting
is still open (see game-pitch.md). Spells are mainly for combat, the second pillar.
Several spells and enemies are built around the terrain heights so they also feed the
first pillar, exploration (see exploration.md).

## How to judge whether a spell word is safe for speech recognition

- **Good:** two or more syllables, a distinctive stressed vowel, rare in casual speech,
  and no common words within one sound of it ("meteor", "bulwark", "tangle").
- **Risky:** one syllable, a common onset swap ("zap" next to "sap", "tap", "cap"), a
  homophone of a common word ("heal" / "he'll"), or a word that's constantly said in
  gaming chatter ("just", "go", "wait").
- **Chatter-prone on purpose:** the hair-trigger spells (voice-mechanic.md, Rule 2).
- **Never put two risky look-alikes in one player's loadout.** For example, don't give one
  player both "frost" and "fireball" unless calibration shows they separate cleanly.

The four POC words, rated:

| Word | Rating | Notes |
|---|---|---|
| heal | Risky | Homophone "he'll"; sound-alikes "heel", "hill", "deal". Rule 1 (spoken, not mentioned) carries it |
| fireball | Good | |
| armor | Good | |
| corn | Risky | "Corner" matches (one extra sound); "core", "horn" and "born" are near. That makes it perfect for a hair-trigger joke |

---

## Spells (22)

| # | Word | Effect | Rating | Notes |
|---|---|---|---|---|
| 1 | **meteor** | A big delayed AoE at the cursor after 1.5 s | Good | A 3-syllable showpiece; the ideal "big" modifier target |
| 2 | **bulwark** | A hex-line wall of spectral shields for 4 s; blocks projectiles | Good | Almost never said in chat |
| 3 | **tangle** | Thorn vines root enemies on 3 hexes | Good | |
| 4 | **frost** | A cone that slows, and freezes on Perfect | OK | Avoid "freeze", which sits near "fries" and "please" |
| 5 | **lightning** | A chain that jumps 3 targets and prefers enemies on *higher* tiles | Good | "Zap" is the risky alternative |
| 6 | **vanish** | Blink to the cursor, up to 4 hexes, ignoring height | Good | "Blink" is OK but sits near "think" and "drink" |
| 7 | **mirror** | Spawns a decoy that taunts enemies | Good | |
| 8 | **vampire** | Drains life from the nearest enemy over 3 s | Good | "Leech" is risky: "each", "reach" |
| 9 | **tempest** | Pushes everything 2 hexes away and can knock enemies off ledges | Good | "Gust" is **very risky**, since it's one sound from "just" |
| 10 | **golem** | Summons a paper golem tank for 10 s | Good | |
| 11 | **sunburst** | A blinding flash that interrupts telegraphs | Good | "Flare" is risky: "there", "air" |
| 12 | **wake up** | Revives a downed ally (target by voice: "wake up Fox") | OK | Chatter-prone, and an accidental revive is a happy accident |
| 13 | **over here** | Taunt; hair-trigger | Chatter | Saying it in chat *should* taunt |
| 14 | **hurry** | Team haste for 3 s; hair-trigger | Chatter | "Hurry up!" in chat speeds everyone up, which is on-theme |
| 15 | **bubble** | A bubble shield on the target ally that absorbs one hit | Good | |
| 16 | **quake** | Raises or lowers the cursor hex by 1 level, which makes new climb paths or traps the brute | OK | Interacts with the terrain heights. Good for the split word "earth + quake" |
| *Joke* | | | | |
| 17 | **corn** (POC) | A corn bomb from the sky; hair-trigger, aimed at the speaker when merely mentioned | Risky | The legend itself |
| 18 | **cheese** | A giant cheese wheel that **rolls downhill along the hex heights**, flattening everything | OK | "Cheese" vs "these" and "keys"; uses the terrain system for comedy |
| 19 | **duck** | Everyone dodges *and* a rubber duck drops (it squeaks and taunts); hair-trigger | Chatter | Yelling "duck!" as a warning works both ways |
| 20 | **banana** | A peel on a hex; enemies slip and slide 2 hexes, off ledges if possible | Good | Hero-Reader's Zipformer once invented "BANANA" from chatter at a high hotword score. Watch it |
| 21 | **anvil** | A cartoon anvil falls after a beat on the cursor; massive single-target damage | Good | |
| 22 | **chicken** | Polymorphs one enemy into a chicken for 4 s. On a Fizzle, *you* become the chicken | OK | Fumble-as-joke done right: failure is funny, not just weak |

**Corn upgrades:**
- **Popcorn:** the split word "pop + corn" makes 6 small popping explosions.
- **Cornfield:** "corn + field" makes a carpet-bomb line.
- **Unicorn:** a late-game legendary in which a corn-horned unicorn charges in a line. It's
  should be safe from the corn trigger, since it isn't one sound from "corn" and doesn't
  start with "corn's" first sound. Verify that streaming partials never emit a bare
  "corn" mid-word.
- **Corn from above:** corn deals bonus damage to targets standing lower than the impact
  point. Players who reach high ground learn to rain corn down on a pit.

**Modifier words** (progression unlocks, see voice-mechanic.md):
- Good: **big**, **twin**, **quick**.
- Risky: "long" vs "wrong".
- Safe alternative: **lasting**.

---

## Enemies (10)

Six interact with the voice mechanic. Four exercise the terrain and combat.

| Enemy | Behavior | Voice interaction | Counterplay |
|---|---|---|---|
| **Hush Moth** | A flying caster that drifts to the densest hero group | Its dust cloud (2 hex radius) **mutes** casting inside it; the heard-word display comes out as "…" | Melee or ranged it down, or step out of the cloud. Keyboard casts work in the cloud at half power, so it isn't a hard lockout |
| **Echo** | A fragile mimic that stays at range | **Repeats your last spell word 2 s later, for the enemies**: your heal heals them, your fireball hits you | Kill it in the window, or cast a harmless word ("corn") to overwrite its echo |
| **Word Thief** (magpie) | Fast, grabs and flees | On hit, **steals one spell word**: that slot is greyed out and the Thief casts it badly (Shaky) | Chase and kill it to get the word back. A natural chase for the climb and stair terrain |
| **Loudmouth** | A tank that grows | **Grows stronger with team mic volume**: louder means more armor and size | Whisper. Teaches the volume signal; play it in short rooms only, to avoid annoying people |
| **The Listener** | A blind brute | Moves toward **whoever is speaking**, using voice activity | Talk to pull it, and stay quiet to lose it. Talking becomes a kiting tool |
| **Chorister Wraiths** | Packs of 3 | Immune except to **chorus or unison casts** (voice-mechanic.md §4) | Teaches unison. Needs networking or voice-commanded AI allies |
| **Grunt / Archer / Brute / Swarmer** | POC set | | |
| **Ledge Lurker** | A wall-crawler that ignores the climb rules and ambushes from height 3+ | | Tempest or quake knocks it off |
| **Hexwright** | A support caster that raises nearby enemies' damage reduction | | A priority target; tests target-by-voice ("fireball" plus aiming) |
| **Shieldbearer** | Blocks frontal ranged attacks and projectiles | | Flank over height, or use AoE spells that come from above (meteor, corn, anvil) |

**Boss idea: The Hush Warden.** An armored sentinel on a tiered arena.
- **Silence windows:** it periodically raises its hand, starting a 3 s silence window. Any
  player who speaks during it takes damage.
- **Sound-alike curses:** between windows it hurls curses with sound-alike names on
  screen ("HORN", "SCORN"). Saying your spell word *clearly* (Perfect) reflects them,
  while a sound-alike match backfires.
- **Arena:** the arena's height tiers shift during the fight, so where to stand is an
  exploration puzzle under pressure.
- It's a fight about controlled speech: precise, timed, and quiet on cue.

---

## Co-op roles

Roles are defined mostly by *what kind of speaking they do*.

| Role | Voice style | Kit | Plays like |
|---|---|---|---|
| **Warden** (tank) | Short barks, hair-trigger shouts | over here, bulwark, armor; heavy melee | Talks the most; accidental taunts are part of the job |
| **Cantor** (support) | Long incantations, unison leader | heal, bubble, wake up, armor; target by callsign | Calls the "Brace!" call-and-response; rewards fluent speakers |
| **Evoker** (damage) | Modifiers and power words | fireball, meteor, lightning, frost; "big" and "twin" | The power curve of multi-word incantations |
| **Cornjurer** (chaos) | Joke spells | corn, cheese, banana, anvil, chicken, duck | The comedy role. Fumbles backfire funnily, not fatally |
| **Hushed** (stealth) | Speaks rarely | vanish, tangle, mirror; Vow of Quiet makes their casts Perfect; strong ranged attack | The quiet player's role. Also a comfortable choice for anyone who'd rather not talk much |

Each class should have **one split-word half** that pairs with another class:
- Evoker "fire" + Cantor "storm".
- Cornjurer "pop" + anyone's "corn".
- Warden "earth" + Evoker "quake".

---

## Progression: new spells are found by exploring

- **Spells are found, not bought.** New spell words are found at **shrines** hidden in the
  world, which ties progression to exploration.
  - Shrines sit on vantage crowns, behind secret stairs, and at the bottom of one-way
    pits.
  - You learn a spell by speaking it once at the shrine. This doubles as a calibration
    sample for that word.
  - Elites can also drop shrine-keys.
- **Known spells persist** between runs.
- **Limited slots.** You equip 2 spells at the start (as in the POC), growing to 4.
  - This keeps each player's active vocabulary small, which helps the recognizer.
  - It also forces the team to pick complementary loadouts.
- **Grammar unlocks.** Progression adds *kinds* of words, not only spells:
  1. Nouns: base spells.
  2. Modifiers: big, twin, quick.
  3. Targets: callsigns.
  4. Split-word halves.
- **Mastery.** Every Perfect cast of a word adds mastery. At thresholds, the word gains its
  Perfect rider permanently, or a shorter cooldown. This rewards practice without punishing
  people the recognizer understands less well, because Clean casts still count half.
- **Rival words:** a stretch idea. Elite enemies "know" one of your words and resist it,
  which pushes players to vary their loadouts.

# Audio plan

Status: **proposal**, 2026-10-18. Nothing here is built in the game yet. The prototype synth and the mic-leak probe in
`tools/sfx_proto/` exist and ran (results below). **No sound files have been downloaded**: every third-party sound below
is a candidate the user has to approve first (the download list is at the end).

The user's ask (2026-10-18): basic audio. Find out whether good open-license sounds exist or whether we can make them
procedurally, track every source for attribution, and pick the top 10 sounds that make the game more fun and read
better ("a sound when cast is activated", "spells pffting").

## Where the project is today
- **No game audio at all.** No `AudioStreamPlayer` in `scripts/`, no `.wav`/`.ogg` assets, no bus layout file
  (`default_bus_layout.tres`). The only output control is the Master bus volume from Settings (FORM 3,
  `GameSettings.apply_volume`).
- **The mic is read directly** (`AudioServer.get_input_frames`, `VoiceCaster._pump_mic`), continuously, through
  `SpeechGate`. The recognizer listens all the time, so **anything the speakers play can reach it**.
- **Audio hooks already exist** in code: `ElevatorArrival.doors_opened` ("audio hook: the ding"),
  `VanArrival.honked` ("audio hook: play the horn here"), `Monster.windup_begun/windup_dropped`, `Brute.slammed`,
  the `Hellgate` signals (`activated`, `burst_telegraphed`, `burst_spawned`, `shove_telegraphed`, `shove_burst`,
  `closed`), `Hero.spell_cast/spell_empty/component_collected/melee_swung/bolt_fired`, `Actor.damaged/healed/died`,
  `Projectile.impacted`, `PricedProp.broken`, `MailPackage.broken`, `Ledger.line_added`, `VoiceCaster.spell_spoken/
  spell_fizzled/voice_activity/cast_detail` (with `accidental`).
- **Missing hook:** nothing fires when the trigger word alone is heard. `Incantation` tracks it as `_pending`
  (`is_pending()`); the plan adds one signal for it (step 4 below).

## 1. The top 10

Ranked by how much each adds to fun and readability. "UI" = non-positional, plays only on the machine that needs it.
"3D" = an `AudioStreamPlayer3D` at the world position, heard by every player near it. Lengths are targets.

| # | Sound | The moment | Why it matters | Length / character | Where |
|---|---|---|---|---|---|
| 1 | **Cast heard** | The recognizer hears the trigger word ("cast", or the player's own) and arms a cast | The player learns the mic is listening and the trigger got through. If the spell then fails, they know it was the spell word. In loose mode it is also the "uh-oh, you just armed it mid-sentence" warning, which is comedy | 0.15-0.2 s. Two rising glass pips, all energy above ~1.7 kHz, quiet. **Procedural** (`cast_armed_a`) | UI, **own machine only** (Voice-feedback bus) |
| 2 | **Spell fired**, one per spell family, with a power sweetener | `spell_spoken` becomes a cast (`Hero.spell_cast(id, power)`) | The payoff of speaking. Each family needs its own signature so the team hears *which* spell went off without looking: fire roar, heal shimmer, corn pops, armor clank, vine creak, tentacle squelch, damp splash, coffee pour, teeth chomp. **Perfect** adds a bright "ting" on top; **Shaky** plays the same sound with a sputter (pitch wobble, choppy gain) | 0.3-0.8 s. A cast "whoosh" layer at the caster, then the spell's own impact at the target | 3D at caster and at the landing point |
| 3 | **Fizzle "pfft"** and **out of component** | A cast scores below 0.5 (`spell_fizzled`) or the slot has 0 charges (`spell_empty`) | The user's "spells pffting". A fizzle that makes a comic puff turns a failure into a laugh, and it tells the player the cast was heard but botched. Out-of-component gets a different "empty jar" tok so it isn't confused with a bad word | 0.3-0.45 s. Air puff whose top falls away plus a small deflating squeak; out-of-component is shorter with a hollow knock. **Procedural** | 3D at the caster (quiet), so teammates hear it too |
| 4 | **Monster tells** | Brute wind-up (`windup_begun`, 0.9 s) then slam (`slammed`); archer draw (`windup_begun`); goblin scout fuse (its 1.5 s wind-up, `monster-awareness.md` Option 4) | Readability: off-screen or in a crowd, the sound is what lets the team dodge or call "armor!" in time. The goblin fuse is the kill window ("vines the goblin!"), so it must be unmistakable | Brute: a rising stone scrape/groan 0.9 s plus a heavy thud with a short low rumble. Archer: wooden creak 0.6 s. Fuse: a sputtering hiss that loops for the wind-up. **Recorded** (CC0), fuse could be procedural | 3D, slightly boosted attenuation so off-screen tells still carry |
| 5 | **Hits and hurt** | Your hero takes damage (`damaged` on your own hero), melee and bolt hits on monsters, `Projectile.impacted`, a hero going down | "Why did I just take damage?" is the unfun chaos `north-star.md` designs out. A distinct "ouch" thump for *your* hero (UI, non-positional) and generic impacts in the world. Friendly fire gets the same hurt sound plus the caster's spell, so it is attributable | Impacts 0.1-0.3 s, punchy, many variants with pitch jitter. **Recorded** (Kenney Impact Sounds, CC0) | Own hurt: UI. Others: 3D |
| 6 | **Accidental cast sting** | `cast_detail.accidental` is true (the "ACCIDENTAL: Fox" callout) | Pure comedy, and it makes the blame audible: everyone hears who did it. It plays *with* the spell, not instead of it | 0.6-0.75 s. A falling slide whistle and a woodblock "bonk". No voice, no trombone "wah" (too vowel-like for the mic; see Mic safety). **Procedural** (`accidental_sting`) | UI on every machine (once casts sync in M4; local until then) |
| 7 | **Pickup** | `Hero.component_collected` (and a softer tick per charge added) | Constant small rewards make the loop feel good; also tells a teammate "I grabbed the corn" | 0.1-0.15 s. A round upward "bloop", pitch rising with charges | 3D at the pickup, quiet |
| 8 | **Paper forms** | Signing (`SignLine` stamp), VOID (`FormVoid`), ticking a box (grease pencil), moving focus / typed values appearing (typewriter), a form sliding in | The UI theme is paperwork; the sounds sell it. A stamp thunk on every signature and VOID is the most satisfying button in the game | Stamp 0.2 s (thump + rubber click + paper slap), typewriter key 0.08 s, pencil scratch 0.15 s, paper rustle 0.3 s, typewriter bell for "form complete". Mixed: recorded CC0 stamp and typewriter, procedural fallback | UI bus |
| 9 | **Money** | `Ledger.line_added`: an "earn" line (cha-ching), a "damage" line (crunch plus a falling register "clunk"), the invoice totals | Property damage is attributable chaos ("Bear broke the vase: -$400"). A sound on the damage ticker makes it land, and the invoice reads like a till | Cha-ching 0.8 s (drawer clicks then a bell, **no voice**); damage clunk 0.3 s | In world: 3D at the broken prop. Invoice: UI |
| 10 | **World beats** | Hellgate wakes / telegraphs a burst / spawns / shoves / closes; elevator ding and doors (`ElevatorArrival.doors_opened`); van horn and door; goblin fireworks launch and bang | Big state changes the whole crew should notice: "the gate is about to spit", "the elevator is here", "the goblin got us". The burst and shove telegraphs are readability like #4 | Hellgate: low rumble loop while open, a rising whoosh for each telegraph, a slam on close. Ding: one bell 1.4 s (procedural works). Fireworks: whistle 1 s plus a bang and crackle. **Mostly recorded** | 3D (the fireworks carry floor-wide, like their alert radius) |

Below the line (later): footsteps, music, ambience beds per room theme, employee chatter (never real words; see Mic
safety), monster idle noises (the "?" suspicious beat in `monster-awareness.md` could use a small sting).

### Spell families (for #2)
| Spell | Cast layer (caster) | Landing layer (target) | Source |
|---|---|---|---|
| fireball | short whoosh | roar + crackle, then an explosion thump | CC0 (qubodup "Fire Spell" / "Fire Magic"), or procedural `spell_fireball` |
| heal | soft whoosh | rising bell arpeggio + shimmer | CC0 ("Heal - Rpg") or procedural `spell_heal` |
| corn | whoosh | a burst of 6-12 randomized single kernel pops (one sample, pitch and timing jitter) | CC0 single pop (michaelperfect) |
| armor | whoosh | metal plate clank + a short shield hum | Kenney Impact Sounds (plate/metal) + procedural hum |
| vines | whoosh | wood creak + leaf rustle | Kenney RPG Audio (creak) / search pending |
| tentacles | whoosh | wet squelch | search pending (Freesound CC0 "squelch") |
| damp | whoosh | splash + drips | search pending (Freesound CC0 "splash") |
| coffee | whoosh | pour + sizzle (no "ahh" voice) | search pending |
| teeth | whoosh | chomp (when `TeethFx.popped`) | search pending |

## 2. Sourcing

### Sources and their licences
| Source | Licence | Attribution | Commercial game | Notes |
|---|---|---|---|---|
| **Kenney** (kenney.nl) | **CC0** (stated on each pack page) | Not required; "Kenney.nl" credit appreciated | Yes | Best first stop. Impact Sounds (130 files), Interface Sounds (100), RPG Audio (50), Casino Audio (50), UI Audio, Digital Audio, Sci-fi Sounds. **Avoid the two Voiceover packs**: spoken words are a recognizer hazard |
| **Freesound** (freesound.org) | Per sound: **CC0**, **CC-BY** (3.0/4.0) or **CC-BY-NC**. Old Sampling+ remnants exist | CC0: none. CC-BY: title, author, link, licence, per sound (Freesound FAQ) | CC0 and CC-BY yes; **CC-BY-NC no** | Filter by licence on every search. Downloads need a free account (the user's). Every candidate below was checked on its own page |
| **OpenGameArt** (opengameart.org) | Per asset: CC0, CC-BY, CC-BY-SA, OGA-BY, GPL... | Depends | CC0/CC-BY yes; **CC-BY-SA and GPL: avoid** (share-alike on modified sounds; GPL is murky for assets) | Good CC0 packs exist (below). The "Spell Sounds Starter Pack" is CC-BY-SA/GPL: skip |
| **Sonniss GDC Game Audio Bundle** (sonniss.com) | Sonniss royalty-free licence v2.0 (27 Aug 2026) | **Not required** | Yes, unlimited projects | Can't redistribute the sounds *as sounds* (no sound packs; "re-designed and manipulated sounds remain licensed material"), and **no AI training**. Shipping them inside a game is fine. The 2026 bundle is ~7.5 GB: too big to browse casually, but the best quality for impacts, fire and monsters |
| **Pixabay** sound effects | Pixabay Content License | Not required | Yes | No standalone redistribution. Licence is not CC0 (except old content), and the summary page says nothing specific about games: usable, but second choice after CC0 |
| **Mixkit** | Mixkit Sound Effects Free License | Not required (per their FAQ, as reported by secondary sources) | Reported yes | **Unclear**: the licence text itself was not readable from here. Verify before use. Low priority |
| **ZapSplat** | Standard (free) licence | **Required** on the free tier ("Sound effects obtained from https://www.zapsplat.com"); Gold removes it | Yes | No redistribution as standalone files. **Licence page blocked (403) from here; terms from secondary sources only: flag as unclear**. Free tier is MP3-only |
| **BBC Sound Effects** (RemArc) | RemArc licence | - | **No**: personal, educational and research use only; commercial needs a paid licence (Pro Sound Effects) | **Do not use** |
| **sfxr / Bfxr / jsfxr / ChipTone** | Tools. sfxr's *code* is MIT; output ownership isn't stated for sfxr, Bfxr, jsfxr or ChipTone | - | Probably yes, but **unclear** | jfxr (an sfxr-style browser tool) states "any sound you create with jfxr is entirely yours". The 8-bit look also doesn't fit Cast's comic-foley style. Our own GDScript synth sidesteps the question: we own what it makes |

### Candidates per top-10 sound
All Freesound and OpenGameArt rows were verified on their own pages (2026-10-18). Sizes are of the original upload.

| # | Candidate | URL | Licence | Notes |
|---|---|---|---|---|
| 1 | Procedural `cast_armed_a` (ours) | `tools/sfx_proto/sfx_synth.gd` | ours | Passed the mic-leak probe (see Mic safety). No download needed |
| 2 fire | "Fire Spell" / qubodup | https://freesound.org/people/qubodup/sounds/442871/ | CC0 | 0.43 s, 82 KB |
| 2 fire | "Fire Magic" / qubodup | https://freesound.org/people/qubodup/sounds/442872/ | CC0 | 0.87 s, 164 KB |
| 2 fire | "JM_FX_Fireball 02.wav" / Julien_Matthey | https://freesound.org/people/Julien_Matthey/sounds/346917/ | CC0 | 1.8 s, 508 KB |
| 2 heal | "Heal - Rpg" / colorsCrimsonTears | https://freesound.org/people/colorsCrimsonTears/sounds/562292/ | CC0 | 1.23 s, 462 KB |
| 2 heal | "Cliche Magic Spell Sound" / qubodup | https://freesound.org/people/qubodup/sounds/817466/ | CC0 | 2.2 s, music box |
| 2 corn | "Pop Corn POP (single)" / michaelperfect | https://freesound.org/people/michaelperfect/sounds/792666/ | CC0 | 0.33 s, 68 KB: randomize copies into a burst |
| 2 corn | "popcorn popping.WAV" / goose278 | https://freesound.org/people/goose278/sounds/198381/ | CC0 | 2:35, 26 MB: raw material, only if the single pop is too thin |
| 2 armor etc. | Kenney "Impact Sounds" | https://kenney.nl/assets/impact-sounds | CC0 | 130 files (metal, wood, plates, punches) |
| 3 | Procedural `fizzle_pfft`, `out_of_component` (ours) | `tools/sfx_proto/sfx_synth.gd` | ours | Optional recorded layer: "Balloon Expels Air" / Terry93D, https://freesound.org/people/Terry93D/sounds/329946/ (CC0, 8.2 s) |
| 3 | "Fizzle" / michorvath | https://freesound.org/people/michorvath/sounds/388247/ | CC0 | 3.7 s; alternative |
| 4 brute | "Dinosaur falls to the ground" / Breviceps | https://freesound.org/people/Breviceps/sounds/457531/ | CC0 | 5.8 s, two heavy impacts |
| 4 brute | "Wooden Floor Body Slams" / Project_Trident | https://freesound.org/people/Project_Trident/sounds/128103/ | CC0 | 42.8 s, many slams to cut |
| 4 archer | "Bow Drawn" / Paveroux | https://freesound.org/people/Paveroux/sounds/490556/ | CC0 | 2.6 s, OGG, 46 KB |
| 4 archer | "Bow_draw_fast02.wav" / SonoFxAudio | https://freesound.org/people/SonoFxAudio/sounds/649337/ | **CC-BY 4.0** | 0.75 s, the right length for a 0.6 s draw. Needs credit |
| 4 goblin | "fuse_burning_48khz.wav" / elonen | https://freesound.org/people/elonen/sounds/45650/ | CC0 | 8.1 s, loopable section. Procedural `fuse_hiss` is the fallback |
| 5 | Kenney "Impact Sounds" | https://kenney.nl/assets/impact-sounds | CC0 | Hits, punches, thuds |
| 5 | Kenney "RPG Audio" | https://kenney.nl/assets/rpg-audio | CC0 | 50 files: weapon swings, footsteps, creaks |
| 6 | Procedural `accidental_sting` (ours) | `tools/sfx_proto/sfx_synth.gd` | ours | Recorded alternatives ("wah wah" trombone / horn) are 4-5 s and vowel-like: rejected for mic safety |
| 7 | Procedural `pickup_bloop` (ours) | `tools/sfx_proto/sfx_synth.gd` | ours | Or "Item or Material Pickup Pop 1 of 3" / el_boss, https://freesound.org/people/el_boss/sounds/665183/ (CC0, 0.07 s). Avoid "pickup_item_pop_effect" (a mouth pop) |
| 8 stamp | "Stamp" / kermite607 | https://freesound.org/people/kermite607/sounds/362622/ | CC0 | 0.64 s, 120 KB (takes 362623, 362624 too: rotate them) |
| 8 stamp | "Office stamp" / whammy | https://freesound.org/people/whammy/sounds/514486/ | CC0 | 4.5 s, several takes |
| 8 typewriter | "Typewriter - single key - type 1.wav" / yottasounds | https://freesound.org/people/yottasounds/sounds/380138/ | CC0 | 0.28 s, 210 KB |
| 8 typewriter | "Foley_Object_Typewriter_Keys_&_Return_Mono_NTG4.wav" / Nox_Sound | https://freesound.org/people/Nox_Sound/sounds/550340/ | CC0 | 8.7 s: six keys and a carriage return to slice |
| 8 bell | "Typewriter Ding.wav" / NHumphrey | https://freesound.org/people/NHumphrey/sounds/204466/ | CC0 | 1.5 s, end-of-line bell ("form complete") |
| 8 clicks | Kenney "Interface Sounds" | https://kenney.nl/assets/interface-sounds | CC0 | 100 clicks/confirms for focus moves |
| 9 | "Cash Register Purchase" / Zott820 | https://freesound.org/people/Zott820/sounds/209578/ | CC0 | 2.75 s, designed cha-ching (trim to ~0.9 s) |
| 9 | "Cash Register Fake.wav" / CapsLok | https://freesound.org/people/CapsLok/sounds/184438/ | CC0 | 2.2 s. Procedural `cha_ching` is the fallback |
| 9 | Kenney "Casino Audio" | https://kenney.nl/assets/casino-audio | CC0 | Chips and coins for the invoice tally |
| 10 hellgate | "Black Portal - Dark Dimension Rift" / LilMati | https://freesound.org/people/LilMati/sounds/657653/ | CC0 | 3.1 s, opening |
| 10 hellgate | "Demonic Portal" / LilMati | https://freesound.org/people/LilMati/sounds/506710/ | CC0 | 40 s: the open loop |
| 10 hellgate | "Gates of Hell (Gate Slam 1)" / magnuswaker | https://freesound.org/people/magnuswaker/sounds/528264/ | CC0 | 4.9 s: close |
| 10 elevator | Procedural `elevator_ding` (ours) | `tools/sfx_proto/sfx_synth.gd` | ours | Recorded: "Elevator Ding" / collierhs_colinlib, https://freesound.org/people/collierhs_colinlib/sounds/588718/ (CC0, 0.67 s, 58 KB) |
| 10 elevator | "elevator door and ding" / jamie7001 | https://freesound.org/people/jamie7001/sounds/476800/ | CC0 | 15.4 s: ding, doors open, doors close |
| 10 fireworks | "Whistle and Explosion Single_Firework" / Rudmer_Rotteveel | https://freesound.org/people/Rudmer_Rotteveel/sounds/336008/ | CC0 | 2.4 s, whistle then pop |
| 10 fireworks | "25 CC0 bang / firework SFX" / rubberduck | https://opengameart.org/content/25-cc0-bang-firework-sfx | CC0 | zip, 1.4 MB |
| general | "80 CC0 RPG SFX" / rubberduck | https://opengameart.org/content/80-cc0-rpg-sfx | CC0 | zip, 1.8 MB: spells, items, coins, creatures |
| general | "RPG Sound Pack" / artisticdude | https://opengameart.org/content/rpg-sound-pack | CC0 | zip, 12.5 MB, 95 WAVs (author asks for credit + OGA link) |

**Rejected:** the human breath in "thud impact wrestling ring..." (kyles), mouth pops, the trombone/horn "wah wah" stings,
Kenney's Voiceover packs, and anything with a voice: all are speech-like for the recognizer (see Mic safety).

### Attribution table (ready to become `CREDITS.md`)
Only rows the user approves get downloaded; the file name is what the sound becomes under `assets/audio/` (original
names are kept in the table). CC0 needs no credit, but we credit everyone anyway and keep the trail.

| Cue / file to use | Title (original file) | Author | Source | Licence | URL |
|---|---|---|---|---|---|
| `spell/fire_cast.wav` | Fire Spell | qubodup | Freesound | CC0 1.0 | https://freesound.org/people/qubodup/sounds/442871/ |
| `spell/fire_land.wav` | Fire Magic | qubodup | Freesound | CC0 1.0 | https://freesound.org/people/qubodup/sounds/442872/ |
| `spell/heal_land.wav` | Heal - Rpg | colorsCrimsonTears | Freesound | CC0 1.0 | https://freesound.org/people/colorsCrimsonTears/sounds/562292/ |
| `spell/corn_pop.wav` | Pop Corn POP (single) | michaelperfect | Freesound | CC0 1.0 | https://freesound.org/people/michaelperfect/sounds/792666/ |
| `monster/brute_slam.wav` | Dinosaur falls to the ground | Breviceps | Freesound | CC0 1.0 | https://freesound.org/people/Breviceps/sounds/457531/ |
| `monster/archer_draw.wav` | Bow Drawn | Paveroux | Freesound | CC0 1.0 | https://freesound.org/people/Paveroux/sounds/490556/ |
| `monster/archer_draw_fast.wav` (alt) | Bow_draw_fast02.wav | SonoFxAudio | Freesound | **CC BY 4.0** | https://freesound.org/people/SonoFxAudio/sounds/649337/ |
| `monster/goblin_fuse.wav` | fuse_burning_48khz.wav | elonen | Freesound | CC0 1.0 | https://freesound.org/people/elonen/sounds/45650/ |
| `world/firework.wav` | Whistle and Explosion Single_Firework | Rudmer_Rotteveel | Freesound | CC0 1.0 | https://freesound.org/people/Rudmer_Rotteveel/sounds/336008/ |
| `world/hellgate_open.wav` | Black Portal - Dark Dimension Rift | LilMati | Freesound | CC0 1.0 | https://freesound.org/people/LilMati/sounds/657653/ |
| `world/hellgate_loop.wav` | Demonic Portal | LilMati | Freesound | CC0 1.0 | https://freesound.org/people/LilMati/sounds/506710/ |
| `world/hellgate_close.wav` | Gates of Hell (Gate Slam 1) | magnuswaker | Freesound | CC0 1.0 | https://freesound.org/people/magnuswaker/sounds/528264/ |
| `world/elevator_doors.wav` | elevator door and ding | jamie7001 | Freesound | CC0 1.0 | https://freesound.org/people/jamie7001/sounds/476800/ |
| `ui/stamp_1..3.wav` | Stamp (362622, 362623, 362624) | kermite607 | Freesound | CC0 1.0 | https://freesound.org/people/kermite607/sounds/362622/ |
| `ui/type_key.wav` | Typewriter - single key - type 1.wav | yottasounds | Freesound | CC0 1.0 | https://freesound.org/people/yottasounds/sounds/380138/ |
| `ui/type_bell.wav` | Typewriter Ding.wav | NHumphrey | Freesound | CC0 1.0 | https://freesound.org/people/NHumphrey/sounds/204466/ |
| `ui/cha_ching.wav` | Cash Register Purchase | Zott820 (remix of CapsLok's "Cash Register Fake") | Freesound | CC0 1.0 | https://freesound.org/people/Zott820/sounds/209578/ |
| `impact/*.ogg` | Impact Sounds (pack) | Kenney | kenney.nl | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `foley/*.ogg` | RPG Audio (pack) | Kenney | kenney.nl | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| `ui/click_*.ogg` | Interface Sounds (pack) | Kenney | kenney.nl | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| (procedural) `cast_armed`, `fizzle`, `out_of_component`, `accidental`, `pickup`, `elevator_ding`, `fuse_hiss` fallback | - | Cast (made in-house with `SfxSynth`) | this repo | ours | `tools/sfx_proto/sfx_synth.gd` |

The only row that legally *requires* attribution is the CC-BY bow draw ("Bow_draw_fast02.wav" by SonoFxAudio,
https://freesound.org/people/SonoFxAudio/sounds/649337/, licensed under CC BY 4.0). Prefer the CC0 "Bow Drawn" and the
credits file stays courtesy-only.

**Flags:** ZapSplat (attribution required, terms unread: 403), Mixkit (licence text unread), sfxr-family output
(ownership unstated), Pixabay (not CC0, no game-specific wording) are all **unclear**; BBC RemArc is **non-commercial**;
any Freesound CC-BY-NC sound is **unusable**; Sonniss is fine to ship but **not** to redistribute as a pack (so a
public repo must not contain Sonniss files in raw form) and not for AI training.

## 3. Procedural option

### What Godot gives us
- **Offline or at boot:** fill a `PackedFloat32Array`, convert to 16-bit PCM in an `AudioStreamWAV` (`data`, `format`,
  `mix_rate`) and play it like any file, or `save_to_wav()` it to disk. Cheap: the 14 prototype cues build in well
  under a second.
- **Live:** `AudioStreamGenerator` + `AudioStreamGeneratorPlayback.push_frame` for sounds driven by parameters every
  frame (a fuse whose sputter follows the remaining wind-up, a hellgate hum that follows its phase). More CPU and more
  code; not needed for the top 10.
- The building blocks are small: sine and glide oscillators, struck-bell partials (inharmonic ratios with per-partial
  decay), white noise through a state-variable filter (low/band/high-pass with a swept cutoff), sparse crackle, and
  attack/decay envelopes. That is the whole prototype (`tools/sfx_proto/sfx_synth.gd`, ~250 lines).

### The prototype (built, 2026-10-18)
`tools/sfx_proto/make_sfx.gd` writes 14 cues as 44.1 kHz 16-bit mono WAVs:
```
Godot_v4.7-stable_win64_console.exe --path . --headless --script res://tools/sfx_proto/make_sfx.gd -- <out_dir> [cue ...]
```
Cues: `cast_armed_a`, `cast_armed_b`, `spell_whoosh`, `spell_fireball`, `spell_heal`, `fizzle_pfft`,
`out_of_component`, `accidental_sting`, `elevator_ding`, `stamp_thunk`, `typewriter_clack`, `cha_ching`,
`pickup_bloop`, `fuse_hiss`. Each recipe seeds its own `RandomNumberGenerator`, so every run makes identical files and
no global randomness is used. Nothing in the game loads these files.

**Round 2 (the user's listen, 2026-10-18)**: `make_sfx.gd -- <out_dir> v2` writes the revisions next to the originals:
| Feedback | New cues |
|---|---|
| cast heard "too twinkly, should be a magical charge-up" | `cast_armed_v2` (noise swell 0.5 -> 5 kHz + a high tone pair with a speeding flutter + a small top-out shimmer), `cast_armed_v2b` ("zhzhzh" capacitor pulses speeding up), and after the probe `cast_armed_v3` (sub swell 70 -> 210 Hz + "air" above 5 kHz, nothing in the speech band) and `cast_armed_v3b` (v2's shape moved above 4.5 kHz, a low swell underneath) |
| fizzle "more broken, unsuccessful" | `fizzle_pfft_v2` (a charge that stalls, spitting bursts with growing gaps, a falling spark, a dull thud), `fizzle_pfft_v2b` (an electrical short: a buzz cutting in and out with sparks, then a dying puff and thud) |
| fireball "too brassy, a cymbal not a fire" | `spell_fireball_v2` (a suck of air into a low-passed WHOOMPH with a sub thump, a flickering low roar, low-passed crackle), `spell_fireball_v2b` (bigger boom, longer burning tail). Energy above 3 kHz fell from 23% to 2-3% |
| stamp "not weighty enough" | `stamp_thunk_v2` (short click, 120 -> 48 Hz thud, low impact body, desk resonances, a small ink slap), `stamp_thunk_v2b` (lower and woodier, a hollow handle knock). Energy below 200 Hz rose from 41% to 59-68% |
| elevator "do 2 dings" | `elevator_ding_v2` (rising major third, C6 then E6), `elevator_ding_v2b` (the falling "ding-dong", E6 then C6, warmer) |
| accidental sting (not understood) | the original stays; `accidental_sting_v2` is a record scratch + bonk alternative, **rejected by the probe** (heard as "OH WHAT", and it broke 2 of 3 casts in C) |

### Which of the top 10 suit procedural
| Sound | Procedural? | Why |
|---|---|---|
| 1 cast heard | **Yes, best** | A tuned, short, high, mic-safe tone is exactly what synthesis does well, and we control its spectrum |
| 2 spell fired | **Partly** | The cast whoosh and heal shimmer synthesize well; fire roar is passable; corn pops, splashes, squelches, chomps and metal clanks sound much better recorded |
| 3 fizzle / out of component | **Yes** | Filtered-noise puff plus a deflating glide is the classic synth fizzle |
| 4 monster tells | **No** (fuse: maybe) | Stone scrape, bow creak and body slams need real recordings. The fuse hiss synthesizes acceptably |
| 5 hits / hurt | **No** | Impacts need recorded transients and body; Kenney's CC0 pack covers them |
| 6 accidental sting | **Yes** | Slide whistle + woodblock is easy and stays short |
| 7 pickup | **Yes** | A bloop is a sine glide |
| 8 forms | **Partly** | A stamp thump and a typewriter click are convincing enough as placeholders; a real stamp and typewriter sound richer and sell the paper theme better |
| 9 money | **Partly** | The register bell synthesizes well; the drawer mechanics sound better recorded |
| 10 world beats | **Ding: yes. The rest: no** | Portal rumbles, door motors and fireworks crackle want recordings |

## 4. Mic safety (measured)

The recognizer listens continuously and players may use speakers. `tools/sfx_proto/mic_leak_probe.gd` feeds each
prototype cue into the real recognizer (`VoiceCaster` with the real model, `SpeechGate` on and off), mixed digitally as
if it leaked from speakers into the mic. The TTS voice clips peak at about -0.5 dBFS; the cue leak was set to a peak of
0.5 alone and 0.4 under speech, i.e. **a very loud leak** (only ~8 dB under the voice's peak). Results (2026-10-18):

- **A. Each cue alone, 3 plays: no cue caused a cast** (gate on or off).
  - **No words at all:** `cast_armed_a`, `elevator_ding`, `stamp_thunk`, `cha_ching` (struck bells, thumps and short
    chimes).
  - **Filler words, no casts:** pitch glides and swept noise read as vowels: `spell_heal` "AH", `accidental_sting`
    "OH"/"POOH"/"FOOL", `pickup_bloop` "WHO"/"POOH", `fizzle_pfft` "HM"/"WHEW", `spell_whoosh` "WISH", `spell_fireball`
    "WHY", `fuse_hiss` "SH", `cast_armed_b` "HE", `typewriter_clack` (gate on) "EAT"/"D".
- **B. The "cast heard" chime overlapping the spell word** (both chimes, at 0.15 and 0.4 peak, starting 0.25 or 0.4 s
  into the voice), 5 spells x 2 voices: **every cast still recognized (80/80, and 10/10 clean)**. The cue the player
  hears most often doesn't hurt the cast it announces.
- **C. "cast <spell>" said over a teammate's loudest speech-like cues** starting with the voice, 3 spells x 6 cues:
  **15/18 cast; 3 missed** (`spell_whoosh` over "cast fireball" heard as "SK FIREBALL"; `spell_heal` over "cast corn" as
  "SCORD"; `pickup_bloop` over "cast corn" as "GASCORN"). Masking the *trigger word* is the real risk, not phantom
  casts.
- Caveats: a digital mix with no room, speaker or mic coloration; TTS voices; one recognizer model. It shows the
  direction, not the real-world rate.

**Round 2 (the charge-up and other revisions, `mic_leak_probe.gd -- v2`; B now starts the cue 0.15 or 0.3 s into the
voice, i.e. while "cast" or the spell word's onset is still being said):**
- **A:** no revised cue casts alone. The charge-ups read as "SH"/"HUSH"/"HUMPH", the record scratch as "OH WHAT"; the
  fireballs, stamps and dings produce nothing or one stray word.
- **B, the charge-up over the spell word (5 spells x 2 voices x 2 levels x 2 offsets = 40 each):**

  | Cue | Misses | At the realistic leak (0.15) | Pattern |
  |---|---|---|---|
  | `cast_armed_a` (round 1, twinkly) | 0 / 80 | 0 | - |
  | `cast_armed_v2` | 4 / 40 | 1 | "heal" heard as "meal", "yale", "field"; "corn" once |
  | `cast_armed_v2b` | 3 / 40 | 1 | "heal" as "yale", "veal" |
  | `cast_armed_v3` (speech band empty) | **1 / 40** | **0** | only loud and early |
  | `cast_armed_v3b` (above 4.5 kHz) | 2 / 40 | **0** | only loud and early |

  A broadband 1-4 kHz noise swell masks the soft "h" of "heal" (the fricative band), so the charge-up has to leave the
  speech band empty: **use `cast_armed_v3` or `v3b`**, not v2/v2b. Their misses were all at the loud (0.4) leak with
  the swell starting 0.15 s into the voice; starting at 0.3 s (closer to when the trigger is actually armed) they had
  none (v2 none, v2b one).
- **C, said over a teammate's loud revised cue:** 23/27 cast. Misses: `accidental_sting_v2` 2 (rejected),
  `elevator_ding_v2` 1, `fizzle_pfft_v2b` 1 ("CASCORD"); the fireballs and stamps never broke a cast.

### Rules that follow
1. **No voices in any sound effect.** No spoken words, no grunts or "ahh"s, no mouth pops, no Voiceover packs, no
   trombone "wah". Monsters stay non-vocal (scrapes, creaks, thuds) or get heavily processed and short.
2. **Frequent cues are struck, not sung:** bells, clicks, thumps and short noise bursts. Keep sustained pitch glides and
   formant-like noise sweeps (100 Hz-3 kHz) short and rare.
3. **The "cast heard" cue leaves the speech band (~300 Hz-4.5 kHz) nearly empty**: a charge-up built from a sub swell
   and "air" above 5 kHz (`cast_armed_v3`, after the user found the round-1 chime too twinkly), quiet, ~0.4 s. It plays
   the instant the trigger is armed, not delayed: B shows that is safe at a realistic leak.
4. **Duck the game while the local player speaks.** On `VoiceCaster.voice_activity(true)` tween the SFX and Music buses
   down ~8 dB (attack 30 ms, release 250 ms after `false`); UI and Voice-feedback stay. The gate's look-ahead means the
   first ~100 ms of the trigger word is not ducked, which is the C-case risk, so ducking reduces it, not removes it.
5. **Headphones are recommended** (already in `voice-mechanic.md` §3) and the first-run voice setup says so. Add an
   **"Audio out: Headphones / Speakers"** choice on FORM 3. Speakers mode: deeper ducking (-15 dB), SFX volume capped,
   and the long speech-like loops (hellgate hum) quieter.
6. **Later, an output-aware gate:** while the Master bus peak (`AudioServer.get_bus_peak_volume_left_db`) is high,
   `SpeechGate` raises its threshold for that moment, so loud game sound isn't treated as voice. True echo
   cancellation (the game's own output as the reference signal) is the proper fix and also covers Steam voice chat; it
   needs a native AEC (e.g. WebRTC's) and is out of scope here.
7. **Keep the probe.** Every new cue goes through `mic_leak_probe.gd` (or a test made from it) before it ships: no cue
   may produce a cast alone, and the armed chime may never break one.

## 5. Recommendation

**Mix:** procedural for the voice feedback and simple UI/tonal cues (cast heard, fizzle, out of component, accidental,
pickup, elevator ding; placeholder stamp/typewriter/cha-ching), **CC0 recordings** for everything physical (impacts,
monster tells, fire, corn pops, forms foley, hellgate, fireworks): Kenney first, then hand-picked CC0 Freesound sounds.
Avoid anything needing attribution unless it's clearly better; skip ZapSplat, BBC, Mixkit and sfxr-family output.
Sonniss GDC is the upgrade path for impacts and monsters later (shippable in the game, but it must not sit raw in a
public repo).

### Bus layout (`default_bus_layout.tres`)
```
Master
├─ Music            (empty for now; ducked while speaking)
├─ SFX              (ducked while speaking)
│  ├─ World         3D players: spells, monsters, hellgates, impacts, pickups
│  └─ Stings        non-positional game stings: accidental, your own hurt, money
├─ UI               paper forms: stamp, typewriter, pencil, paper, clicks (not ducked)
└─ VoiceFeedback    cast heard, your own fizzle (not ducked; its own volume so a player can mute the chime)
```
A Limiter on Master, and a gentle Compressor on SFX so corn spam can't clip. (Steam voice chat, when it lands, gets its
own `VoiceChat` bus.)

### Settings (FORM 3)
Keep Master; add **Music**, **Effects** (SFX), **Paperwork** (UI), **Spell feedback** (VoiceFeedback), the same 10-box
`BoxScale` each, and **Audio out: Headphones / Speakers** (default Speakers until the voice setup asks). Saved by
`GameSettings` like the master volume.

### Implementation steps
1. **Bus layout** file as above; `GameSettings.apply` sets every bus by name.
2. **`Sfx` autoload** (`scripts/fx/sfx.gd`, cosmetic): a cue table `name -> {streams[], bus, volume_db, pitch_jitter,
   max_voices, min_gap, positional, unit_size/max_distance}`. API: `Sfx.play(cue)`, `Sfx.play_at(cue, pos)`,
   `Sfx.attach(cue, node) -> handle` for loops (hellgate hum, fuse) and `Sfx.stop(handle)`. Pools: ~24
   `AudioStreamPlayer3D` and ~8 `AudioStreamPlayer`; per-cue voice limit (corn pops 8, impacts 6) and steal the oldest.
   Variation (pitch/volume jitter, picking a take) uses `GameWorld.fx_rng`, never `GameWorld.rng` (AGENTS.md rule 4).
   Headless (tests, the dedicated net test processes) it does nothing.
3. **`SfxSynth`** moves from `tools/sfx_proto/` to `scripts/fx/sfx_synth.gd`; the kept recipes are baked once at boot
   into `AudioStreamWAV`s (milliseconds), so no generated files are committed.
4. **The one new hook:** `VoiceCaster.trigger_heard` (or `armed`), emitted when `Incantation` starts a pending trigger.
   Everything else listens to signals that already exist (see "Where the project is today").
5. **Wiring is listen-only**, from `Game` / the HUD / each form, never inside gameplay logic: `spell_spoken` +
   `cast_detail` (power tier, accidental) -> #2/#6, `spell_fizzled` / `spell_empty` -> #3, `windup_begun` / `slammed`
   -> #4, `damaged` / `died` / `Projectile.impacted` -> #5, `component_collected` -> #7, `SignLine` / `FormVoid` /
   ticks / `FormTheme.typed` reveals -> #8, `Ledger.line_added` -> #9, hellgate / elevator / van / fireworks signals ->
   #10.
6. **Networking: sounds are cosmetic.** Every machine plays its own from events it already receives; no RPC ever carries
   a sound (and none may: no network code outside `scripts/net/`). Clients get monster wind-ups from the telegraph
   byte (check that the copy emits `windup_begun`; if not, `Sfx` watches the telegraph value), hellgate and elevator
   events from M3, ledger lines from the Ledger mirror, and other players' casts from M4 (`NetCasts.cast_applied`). The
   cast-heard chime and your own fizzle are local only (they are about *your* mic). Until M4, the accidental sting and
   other players' spell sounds play only on the caster's machine.
7. **Tests:** `test_sfx.gd` (every cue resolves to a stream on an existing bus; `Sfx` is silent headless; no use of
   `GameWorld.rng`), and the mic-leak probe as an optional voice test that skips without the model, like
   `test_voice_noise.gd`: no cue casts alone; the armed chime never breaks a clean cast.
8. **Assets and credits:** approved downloads go to `assets/audio/<group>/` with the attribution table above as
   `CREDITS.md` (and a credits line on the main menu's back page or an info form). Whether CC0 third-party files are
   committed or kept untracked like the speech models is the user's call (open question below).

## Open questions for the user
1. **Approve downloads?** Which of the list below (all CC0 except one optional CC-BY). Freesound needs the user's own
   login to download.
2. **Commit third-party audio to git** (CC0 allows it), or keep it untracked like `models/` and copy it in at build?
3. **The cast-heard chime: on by default?** It plays on every armed trigger, including mid-sentence ones in loose
   mode (that is part of the joke). It gets its own volume so players can turn it off.
4. **Should teammates hear your cast-heard chime** (softly, at your hero)? Proposed: no, only the spell itself.
5. **Music:** in scope now, or later? (A bus is reserved.)
6. **Speakers vs headphones:** ask in the first-run voice setup, or just recommend headphones and default to Speakers
   mode?

## Files to download if approved
Sizes are the original uploads as listed on each page (Kenney pages don't list a size).

| # | File | Source URL | Licence | Size |
|---|---|---|---|---|
| 1 | kenney_impact-sounds.zip (130 sounds) | https://kenney.nl/assets/impact-sounds | CC0 | not listed (a few MB) |
| 2 | kenney_rpg-audio.zip (50 sounds) | https://kenney.nl/assets/rpg-audio | CC0 | not listed |
| 3 | kenney_interface-sounds.zip (100 sounds) | https://kenney.nl/assets/interface-sounds | CC0 | ~835 KB (OpenGameArt mirror) |
| 4 | Fire Spell (442871) | https://freesound.org/people/qubodup/sounds/442871/ | CC0 | 82 KB |
| 5 | Fire Magic (442872) | https://freesound.org/people/qubodup/sounds/442872/ | CC0 | 164 KB |
| 6 | Heal - Rpg (562292) | https://freesound.org/people/colorsCrimsonTears/sounds/562292/ | CC0 | 462 KB |
| 7 | Pop Corn POP (single) (792666) | https://freesound.org/people/michaelperfect/sounds/792666/ | CC0 | 68 KB |
| 8 | Dinosaur falls to the ground (457531) | https://freesound.org/people/Breviceps/sounds/457531/ | CC0 | 1.1 MB |
| 9 | Bow Drawn (490556) | https://freesound.org/people/Paveroux/sounds/490556/ | CC0 | 46 KB |
| 10 | fuse_burning_48khz.wav (45650) | https://freesound.org/people/elonen/sounds/45650/ | CC0 | 760 KB |
| 11 | Whistle and Explosion Single_Firework (336008) | https://freesound.org/people/Rudmer_Rotteveel/sounds/336008/ | CC0 | 412 KB |
| 12 | Black Portal - Dark Dimension Rift (657653) | https://freesound.org/people/LilMati/sounds/657653/ | CC0 | 527 KB |
| 13 | Demonic Portal (506710) | https://freesound.org/people/LilMati/sounds/506710/ | CC0 | 6.7 MB |
| 14 | Gates of Hell (Gate Slam 1) (528264) | https://freesound.org/people/magnuswaker/sounds/528264/ | CC0 | 2.7 MB |
| 15 | elevator door and ding (476800) | https://freesound.org/people/jamie7001/sounds/476800/ | CC0 | 2.6 MB |
| 16 | Stamp (362622, 362623, 362624) | https://freesound.org/people/kermite607/sounds/362622/ | CC0 | ~110-120 KB each |
| 17 | Typewriter - single key - type 1.wav (380138) | https://freesound.org/people/yottasounds/sounds/380138/ | CC0 | 210 KB |
| 18 | Typewriter Ding.wav (204466) | https://freesound.org/people/NHumphrey/sounds/204466/ | CC0 | 389 KB |
| 19 | Cash Register Purchase (209578) | https://freesound.org/people/Zott820/sounds/209578/ | CC0 | 475 KB |
| opt | Bow_draw_fast02.wav (649337) | https://freesound.org/people/SonoFxAudio/sounds/649337/ | **CC BY 4.0** | 129 KB |
| opt | 25 CC0 bang / firework SFX | https://opengameart.org/content/25-cc0-bang-firework-sfx | CC0 | 1.4 MB |
| opt | 80 CC0 RPG SFX | https://opengameart.org/content/80-cc0-rpg-sfx | CC0 | 1.8 MB |

Total for rows 1-19: roughly 20 MB plus the three Kenney zips. Still to find (CC0 searches pending): tentacle squelch,
damp splash, coffee pour, teeth chomp, armor plate clank (likely inside Kenney Impact Sounds).

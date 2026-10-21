# Sound credits

The game's sound cues (`<cue>.wav` here) are rendered by `tools/render_sfx.ps1` (`tools/sfx_proto/render_game_sfx.gd`)
from the prototype recipes in `tools/sfx_proto/sfx_round3.gd` and `sfx_synth.gd`. The WAVs are generated and not in
git. The recordings they are cut from live in `assets/audio/third_party/` (untracked; `SOURCES.md` there lists every
file). Every third-party source is CC0 1.0, so no credit is required, but we give it anyway. "Synth" means the sound
is generated in GDScript by Cast's own code, so we own it.

| Cue (file) | Recipe | Made from | Author | Licence | URL |
|---|---|---|---|---|---|
| `cast_heard` | `cast_armed_v4a2` | `knifeSlice2.ogg` from the RPG Audio pack, reversed, cut to its last 0.25 s, speech band notched out | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| `fizzle` | `fizzle_pfft_v4` | synth (a short circuit, then a dying high sizzle) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `fireball` | `spell_fireball_v4b` | "Fire Magic" (442872), pitched down 2 semitones | qubodup (Freesound) | CC0 1.0 | https://freesound.org/people/qubodup/sounds/442872/ |
| | | `impactPunch_heavy_001.ogg` from the Impact Sounds pack (the thump under the attack) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `stamp` | `stamp_thunk_v4` | "Stamp", take 3 (362624), first hit only | kermite607 (Freesound) | CC0 1.0 | https://freesound.org/people/kermite607/sounds/362624/ |
| | | `impactPlank_medium_000.ogg` from the Impact Sounds pack (low-passed desk thud) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `paper` | `paper_flip` | `bookFlip3.ogg` from the RPG Audio pack, as recorded (silence trimmed, levelled) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/rpg-audio |
| `elevator_ding` | `elevator_ding_v4b` | synth (a two-tone lobby chime, A5 then F5) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `fuse` | `fuse_hiss_v6` | synth (a "pssht" as it lights, then a quiet high sizzle that dies away) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `firework` | `firework_v1` | "Whistle and Explosion Single_Firework" (336008), its start cut so the bang lands on the burst | Rudmer_Rotteveel (Freesound) | CC0 1.0 | `tools/sfx_proto/sfx_round3.gd` |

**Sewers and lava (2026-10-21).** All built in `tools/sfx_proto/sfx_round3.gd` ("sewers and lava"). The water (splashes,
slosh, droplets), the hisses, the hum and the bubbling are synth; the recordings below are layered in.

| Cue (file) | Recipe | Made from | Author | Licence | URL |
|---|---|---|---|---|---|
| `gator_hiss` | `gator_hiss_v3` | synth (a "khh", a faint high breath, a low throat rattle) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `gator_snap` | `gator_snap_v1` | `impactWood_light_000.ogg`, `impactSoft_medium_000.ogg` (Impact Sounds) and `metalLatch.ogg`'s first 50 ms (RPG Audio), with synth droplets | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds, https://kenney.nl/assets/rpg-audio |
| `gator_splash` | `gator_splash_v2` | synth splash on `impactSoft_heavy_000.ogg` (Impact Sounds, low-passed) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `gator_thrash` | `gator_thrash_v4` | a synth splash, then `impactSoft_medium_000/002.ogg` tail slaps (Impact Sounds, low-passed) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `goo_throw` | `goo_throw_v2` | synth (a wet "shlup" and an airy whoosh) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `goo_splat` | `goo_splat_v1` | synth squelch on `impactSoft_heavy_000.ogg` (Impact Sounds, low-passed) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `goo_splash` | `goo_splash_v1` | synth (a small splash) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `goo_ignite` | `goo_ignite_v1` | "Fire Spell" (442871), pitched down 6 semitones and low-passed | qubodup (Freesound) | CC0 1.0 | https://freesound.org/people/qubodup/sounds/442871/ |
| | | `impactSoft_heavy_000.ogg` (Impact Sounds, the thump under it) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `goo_wash` | `goo_wash_v1` | synth (a high fizz) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `wire_spark` | `wire_spark_v1` | `glitch_001.ogg`, `glitch_003.ogg` (Interface Sounds, high-passed) and `impactMetal_light_000.ogg` (Impact Sounds), with synth snaps and sizzle | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/interface-sounds, https://kenney.nl/assets/impact-sounds |
| `wire_shock` | `wire_shock_v1` | synth (a crack, crackle, a low thoom) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `wire_fizzle` | `wire_fizzle_v2` | synth (the hum cutting out) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `wade_step` | `wade_step_v1` | synth (a soft slosh and droplets) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `lava_bubble` | `lava_bubble_v1` | synth (low rumble and thick bubbles, all under 600 Hz) | Cast | ours | `tools/sfx_proto/sfx_round3.gd` |
| `lava_crust` | `lava_crust_v2` | synth steam on `impactSoft_heavy_000.ogg` (Impact Sounds, low-passed) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `lava_crack` | `lava_crack_v1` | `impactMining_000/002/004.ogg` (Impact Sounds, their first hits), with synth grit and groan | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| `lava_sizzle` | `lava_sizzle_v1` | synth sizzle on `impactSoft_heavy_000.ogg` (Impact Sounds, low-passed) | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/impact-sounds |

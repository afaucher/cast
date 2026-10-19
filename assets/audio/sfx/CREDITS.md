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

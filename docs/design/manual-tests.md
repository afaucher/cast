# Manual tests to track

What the user asked to track by hand (2026-10-22: "For the manual tests, let's track 11 & 16. The rest we can check
casually during play."). Tick an item when it has been played and found right; note what was wrong otherwise.

## 11. Wading footsteps (47b71df)

User, 2026-10-21: "The footstep squash sound in the water is too loud. And should probably play for all characters, not
just the player." Now `wade_step` plays at -24 dB (was -14) for every wader.

- [ ] Wading sounds quieter, not tiring over a long channel.
- [ ] Monsters and staff splash too when they wade; a pack crossing doesn't get noisy.
- [ ] Spells still cast cleanly while wading (the cue passed the mic-leak probe; check it in a real room).

Try: `.\run.ps1 --seed 5 --floor 2 --spells damp,fireball --to-sewer foot`

## 16. Movement package A "grounded" (69fc867)

Blind A/B, 2026-10-22: "Grounded is better. Not there yet." Then `grounded_anim` (lean, squash, strike-first melee, hit
areas matched to the weapons), decided 2026-10-23: "For movement profile - the new one is better." It is now the game's
default; the F6 / F7 keys are gone and the test gym's panel has the profile and the smoothing as "Experiments".

- [x] Blind A/B grounded vs today: grounded better.
- [ ] Judder smoothing on your own monitor (the gym's Smoothing picker, or `--physics-interp on`): does it help? What
  refresh rate is it? (Always-on was considered and parked, 2026-10-23.)
- [ ] Footsteps on each floor material in the lab: audible, not annoying, never trigger a cast.
- [ ] Steps (hop), +2 climbs (mantle), drops (gravity, landing) feel right.
- [ ] Stop slide: is 0.07 s / 0.12 u right, or should it be longer?
- [ ] In a crew, every window uses the host's profile.
- [x] Blind A/B `grounded` vs `grounded_anim`, as Gasket (2026-10-22): "Gasket feels MUCH better" — the aimed smash
  beats the old swing arc. Fixes in progress: the arm clipping into the body on the smash, a bigger hammer impact.
- [x] `grounded` vs `grounded_anim`, decided (2026-10-23): "the new one is better". `grounded_anim` is the default.
- [ ] Wick and Rebar in `grounded_anim`.

Try: `.\run.ps1 --move-lab` (the default, grounded_anim; `--move-feel today|grounded` for another), or `.\run.ps1 --gym`
and its Experiments pickers; crew: `.\run.ps1 -Crew 2 --net-wait 2 --move-lab --move-feel grounded`

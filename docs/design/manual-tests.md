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

Blind A/B, 2026-10-22: "Grounded is better. Not there yet." Next layer in progress: `grounded_anim` (lean, squash,
strike-first melee, hit areas matched to the weapons).

- [x] Blind A/B grounded vs today: grounded better.
- [ ] F7 (judder smoothing) on your own monitor: does it help? What refresh rate is it?
- [ ] Footsteps on each floor material in the lab: audible, not annoying, never trigger a cast.
- [ ] Steps (hop), +2 climbs (mantle), drops (gravity, landing) feel right.
- [ ] Stop slide: is 0.07 s / 0.12 u right, or should it be longer?
- [ ] In a crew, every window uses the host's profile.
- [ ] Next: blind A/B `grounded` vs `grounded_anim` once it lands.

Try: `.\run.ps1 --move-lab --move-feel shuffle` (F6 switch, F7 smoothing); crew: `.\run.ps1 -Crew 2 --net-wait 2 --move-lab --move-feel grounded`

# Playtest feedback log

Raw feedback from playtests, recorded as given, before deciding how to react. Each entry gets a decision line once one
is made (link the commit or doc that acted on it).

## 2026-10-24: release 2026-10-23.133405

The user: "Playtest feedback - just record then we can decide how to react".

1. **Climbable pillars you can't get down from.** "Players can climb pillars which they cannot then jump down. Lets bring
   these into alignment and have a debug key to unstick."
   - Decision (2026-10-24): "For pillars, can we just allow the player to jump from any height they can climb?" A player's
     hero now walks off any drop (`Hero._max_drop`, `HexMap.movement_check`'s `max_drop`); AI allies and monsters keep the
     3-level limit their paths are built for. No unstick key needed for this. Still open: how the user climbed "like 5
     levels" (the climb rule is +2 at a time; walking past a lone +5 pillar at 432 angles never got on top, so it is
     something next to it: a ledge, a platform or a terrace step, or the mantle).
2. **Tentacles for crowd control.** "Tentacles - most useful in hallways to break up a rush. Maybe like a wall or a push
   from the player outward for better crowd control."
   - Decision: pending.
3. **Offensive spell drops when the players are out.** "Increase offensive spell drop rates when the players are out."
   - Decision: pending.
4. **Swarms flocking down hallways.** "We need to figure out how to break up swarms of enemies a bit flocking down
   hallways. It makes it very repetitive. Especially at the origin gate with high spawn rates."
   - Building (2026-10-24): batch 1 of 2 (the user: "Sounds good" to path jitter, size jitter and speed spread first, then
     the walk and war cries). Each monster gets its own sideways lane off its path's cell centres (+/- 0.3, a new one every
     2-4 s; none at the goal, in a 1-cell hall, a door or a climb), a fixed pace of +/- 8% (not the goblin) and a look scale
     of +/- 7% from its net id (`Monster`, "Crowd variety"). The gym's Experiments switch each on / off (all on in the game);
     "Hallway x12" and "Hallway mix" send a pack down the arena-lobby hall (`GymDev.hall_pack`). `test_monster_crowd`.
   - Tuned (2026-10-24): "More path jitter, and lets see if we can unsync their footsteps/walk animation as well", then on
     +/- 0.3: "Do the wider jitter. The current is better then none but not quite enough". The lane is now +/- 0.6
     (`Monster.LANE_MAX`; half of it where the full width does not fit). Walk unsync: each monster's bob and model stride
     start at their own point of the cycle and run at +/- 10%, from its net id (`Monster.gait_for`), so a pack spawned
     together no longer strides in step.
   - Decision (2026-10-24): keep all four, always on. "0.6 looks good"; "They all look good. Lets make those the defaults";
     "Clean up the flags" (the gym switches and Monster's on/off statics are gone; the hallway pack buttons stay). Still
     open from this item: the war cries and a more active walk (batch 2), and the origin gate's spawn rate.
   - Building batch 2 (2026-10-24): the user, "Lets do 3 - crowd batch 2". A more active walk: on each kind's stride, a
     walking monster sways and shifts its weight, leans into its speed, swings its arms or weapon against its legs and bobs
     its head, in character (the skeleton a jaunty rattle-march, the brute a heavy lumber, the imp a low bouncy scurry, the
     archer a stalk with the bow up, the pavise a braced shuffle, the goblin, goo imp and Water Boy lighter versions;
     `MonsterModel.gait_k`), on its own unsynced clock; wind-ups and strikes are untouched. War cries: a pack's first sight
     of the crew makes ONE member yell (the lowest net id among the pack's sightings; one per 12 units per 6 s), and a
     charging monster yells now and then (a 6% roll every 1.5 s on the shared clock; 10 s cooldown each, 4 s per area), with
     a ~0.5 s arms-up pose; every machine yells from the monster state it sees (no event; `Monster`, "War cries"). Sounds:
     three candidates each for the skeleton, the brute and the imp, one shared cry (audio-plan.md "War cries", the
     listening sheet); A plays until picked. The gym's Experiments: "Monster walk" old / new and "War cries" off / A / B /
     C; the panel's "War cry" button makes the nearest monster of each kind yell. `test_monster_walk`,
     `test_monster_war_cry`, `test_net_monster_step2`.
   - Batch 2 in the gym (2026-10-24): "I don't like the audio. I will record one. But lets have the arms move foward
     instead of spin backwards. That looks weird." None of the A/B/C candidates is kept: the user records a cry (A plays
     as a placeholder until then). The cry pose now raises the arms up in front (the skeleton, brute, imp and goo imp
     swung them up behind; the archer's bow and fist rise in front too); `test_monster_walk` checks no arm swings behind.
   - Decision: pending (the walk; the cry's sound waits for the user's recording).
5. **Spells without the wake word.** "Can we do spells without the wake word?"
   - Today: the voice setup screen's "chaos" strictness already casts any spell word anywhere, no trigger
     (`Incantation`, "chaos"); the playtest ran "loose", the default. Chaos also casts on chatter ("brush your teeth",
     "I need coffee"), flagged accidental in the voice log.
   - Decision: pending.

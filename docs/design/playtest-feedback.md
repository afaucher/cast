# Playtest feedback log

Raw feedback from playtests, recorded as given, before deciding how to react. Each entry gets a decision line once one
is made (link the commit or doc that acted on it).

## 2026-10-24: release 2026-10-23.133405

The user: "Playtest feedback - just record then we can decide how to react".

1. **Climbable pillars you can't get down from.** "Players can climb pillars which they cannot then jump down. Lets bring
   these into alignment and have a debug key to unstick."
   - Decision: pending.
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
   - Decision: pending.
5. **Spells without the wake word.** "Can we do spells without the wake word?"
   - Today: the voice setup screen's "chaos" strictness already casts any spell word anywhere, no trigger
     (`Incantation`, "chaos"); the playtest ran "loose", the default. Chaos also casts on chatter ("brush your teeth",
     "I need coffee"), flagged accidental in the voice log.
   - Decision: pending.

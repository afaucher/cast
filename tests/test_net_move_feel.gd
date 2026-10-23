extends NetGameTest
## The movement feel in a crew (docs/design/movement-research.md "As built", MoveFeel): two processes, `off` and `coast`.
## On the movement lab (`--move-lab`: every window builds the same course, the barrier agrees). The host plays `grounded`,
## the client's own flag says `today`:
##   - the host's profile goes out with the job, so the client plays `grounded` too, and a pick of its own (the gym's
##     picker, MoveFeel.pick) does nothing in a crew;
##   - both walk (NetBot): each puppet stays within M2's tolerance of where the hero really was (the envelope, the hops and
##     the falls are the owner's motion and stream like any walk: nothing new on the wire, the snapshots keep their size);
##   - each screen strides the other's puppet from the shown motion (Gait), counts its footsteps, and never runs the walk
##     (HeroMotion) on it.

const PEERS := 2
const SEED := 21
const WALK := 7.0
const TOL := 0.35
const MAX_STEP := 0.6


func run_host() -> void:
	MoveFeel.reset()
	MoveFeel.set_mode(MoveFeel.GROUNDED)
	if not await enter_floor(SEED, 1, {"move_lab": true}):
		MoveFeel.reset()
		return
	if not await wait_sync():
		MoveFeel.reset()
		return
	for p in client_peers():
		command(p, "walk")
	var mine := await _walk()
	check(await wait_reports("walk", 1, 40.0), "the client reports its walk")
	var theirs: Dictionary = reported(client_peers()[0], "walk")
	eq(str(theirs["feel"]), "grounded", "the client plays the host's profile")
	check(not bool(theirs["pick"]), "the client's own pick does nothing in a crew")
	for d: Dictionary in [mine, theirs]:
		var other: Dictionary = theirs if d == mine else mine
		var e := series_error(other["ring"] as PackedFloat64Array, (d["seen"] as Dictionary)[int(other["seat"])] as PackedFloat64Array)
		print("[feel net] seat %d sees the other: %d frames, max err %.3f, max step beyond walking %.3f; puppet gait %s, steps %d, motion %s" % [
			int(d["seat"]), int(e["n"]), float(e["max_err"]), float(e["max_excess"]), str(d["puppet_gait"]), int(d["puppet_steps"]),
			str(d["puppet_motion"])])
		check(int(e["n"]) > 200, "seat %d watched the other walk" % int(d["seat"]))
		check(float(e["max_err"]) <= TOL, "seat %d: the puppet stays within %.2f of the truth (%.3f)" % [int(d["seat"]), TOL, float(e["max_err"])])
		check(float(e["max_excess"]) <= MAX_STEP, "seat %d: no snap beyond walking (%.3f)" % [int(d["seat"]), float(e["max_excess"])])
		check(bool(d["puppet_gait"]), "seat %d strides the puppet from its shown motion" % int(d["seat"]))
		check(int(d["puppet_steps"]) > 4, "seat %d hears the puppet's footsteps (%d)" % [int(d["seat"]), int(d["puppet_steps"])])
		eq(int(d["puppet_motion"]), 0, "seat %d never runs the walk on a puppet" % int(d["seat"]))
		check(int(d["own_steps"]) > 4, "seat %d's own hero strides too (%d steps)" % [int(d["seat"]), int(d["own_steps"])])
		check(int(d["out_max"]) <= 40, "snapshots keep their size (%d B)" % int(d["out_max"]))
	for p in client_peers():
		command(p, "end")
	check(await wait_done(1, 30.0), "the client is done")
	MoveFeel.reset()


func run_client() -> void:
	MoveFeel.reset()
	MoveFeel.set_mode(MoveFeel.TODAY)   # (its own flag: today)
	if not await enter_floor(SEED, 1, {"move_lab": true}):
		return
	if not await wait_sync():
		return
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"walk":
				report("walk", await _walk())
			_:
				running = false
	MoveFeel.reset()


func _walk() -> Dictionary:
	record(true)
	start_bot()
	await sleep(WALK)
	record(false)
	var puppet: Hero = null
	var other_seat := 2 if my_seat() == 1 else 1
	puppet = hero_at(other_seat)
	var own := my_hero()
	return {"seat": my_seat(), "ring": ring, "seen": seen, "feel": MoveFeel.active(), "pick": MoveFeel.pick(MoveFeel.TODAY),
		"puppet_gait": puppet != null and puppet._gait.gait != null, "puppet_steps": puppet._gait.steps if puppet != null else 0,
		"puppet_motion": (puppet._motion.hops + puppet._motion.landings + puppet._motion.mantles) if puppet != null else -1,
		"own_steps": own._gait.steps, "out_max": int(Session.snap.stats["out_max"])}

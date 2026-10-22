extends NetGameTest
## `grounded_anim` in a crew (MoveFeel, HeroFeel; docs/design/animation-research.md "As built"): two processes, `off` and
## `coast`, on the movement lab. The host plays grounded_anim, the client's own flag says today:
##   - the client plays the host's profile (it rides the job), so both screens agree on the lean, the strike and the hit areas;
##   - each screen leans the other's puppet from its shown motion (HeroFeel on a puppet) with nothing new on the wire (the
##     snapshots keep their size);
##   - each hero swings twice; the other screen replays both swings strike-first on its puppet (the `act` event it already had).

const PEERS := 2
const SEED := 21
const WALK := 5.0


func run_host() -> void:
	MoveFeel.reset()
	MoveFeel.set_mode(MoveFeel.GROUNDED_ANIM)
	if not await enter_floor(SEED, 1, {"move_lab": true}):
		MoveFeel.reset()
		return
	if not await wait_sync():
		MoveFeel.reset()
		return
	for p in client_peers():
		command(p, "walk")
	var mine := await _walk()
	check(await wait_reports("walk", 1, 40.0), "the client reports")
	var theirs: Dictionary = reported(client_peers()[0], "walk")
	eq(str(theirs["feel"]), "grounded_anim", "the client plays the host's profile")
	for d: Dictionary in [mine, theirs]:
		print("[anim net] seat %d: puppet layer %s, puppet lean up to %.1f deg, puppet strikes %d, own strikes %d, snapshot max %d B" % [
			int(d["seat"]), str(d["puppet_body"]), float(d["puppet_lean"]), int(d["puppet_strikes"]), int(d["own_strikes"]), int(d["out_max"])])
		check(bool(d["puppet_body"]), "seat %d: the puppet gets the body layer" % int(d["seat"]))
		check(float(d["puppet_lean"]) > 3.0, "seat %d leans the puppet from its shown motion (%.1f deg)" % [int(d["seat"]), float(d["puppet_lean"])])
		eq(int(d["own_strikes"]), 2, "seat %d's own hero struck twice" % int(d["seat"]))
		eq(int(d["puppet_strikes"]), 2, "seat %d replays both of the other's swings strike-first" % int(d["seat"]))
		check(int(d["out_max"]) <= 40, "snapshots keep their size (%d B)" % int(d["out_max"]))
	for p in client_peers():
		command(p, "end")
	check(await wait_done(1, 30.0), "the client is done")
	MoveFeel.reset()


func run_client() -> void:
	MoveFeel.reset()   # (its own flag: today)
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
	start_bot()
	var other_seat := 2 if my_seat() == 1 else 1
	var lean := 0.0
	var t_end := Time.get_ticks_msec() + int(WALK * 1000.0)
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var p := hero_at(other_seat)
		if p != null:
			lean = maxf(lean, p._feel.lean.length())
	bot.stop()
	var own := my_hero()
	own.melee(own.facing)
	await sleep(1.0)
	own.melee(own.facing)
	await sleep(2.0)
	var puppet := hero_at(other_seat)
	return {"seat": my_seat(), "feel": MoveFeel.active(), "puppet_body": puppet != null and puppet._feel.active(),
		"puppet_lean": rad_to_deg(lean), "puppet_strikes": puppet._feel.strikes if puppet != null else -1,
		"own_strikes": own._feel.strikes, "out_max": int(Session.snap.stats["out_max"])}

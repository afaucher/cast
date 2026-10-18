extends NetGameTest
## M2 "done when" (networking-build-plan.md), three processes, `off` and `coast`: hero sync. Each machine owns its own
## seat's hero and streams it at 30 Hz; the others show it as a puppet about 100 ms behind. Everyone walks (a NetBot on the
## real PlayerController), everyone sees everyone.
##
## - roles: each machine simulates exactly its own hero (one PlayerController), every other hero is a puppet with the
##   player's roster name over it, and nobody runs an AI (all three seats are players);
## - WALK: for 9 s all three walk a scripted loop at once. Each viewer records what its puppets showed and at which shared
##   time (`render_time`); the owner records where the hero REALLY was every frame. Every pair (host sees c1, c2 sees the
##   host, c2 sees c1 through the host's forward...) stays within 0.35 units of the truth at the time shown, with no frame
##   step over 0.6, under `off` and under `coast` (45 +- 15 ms, jitter reorders, 1.5% loss);
## - the budget: a client sends 24 bytes x 30 Hz, well under 3 KB/s; the host's snapshot with two heroes is 40 bytes;
## - the wire: under `coast` packets were really lost (gaps) and reordered ones refused, and the walk still held;
## - EVENTS: a teleport shows as ONE jump, with no position on the way across, from the host and through the forward;
##   hp, the held spell and death arrive on every screen and agree with the owner.

const PEERS := 3
const SEED := 21
const WALK := 9.0
const TOL := 0.35
const MAX_STEP := 0.6
const BUDGET := 3000.0
const EVENTS_SECONDS := 4.6


func run_host() -> void:
	if not await enter_floor(SEED):
		return
	if not await wait_sync():
		return
	check(await wait_reports("roles", 2, 30.0), "both clients are streaming")
	var all_roles := {1: roles()}
	for p in peers_with("roles"):
		all_roles[int(reported(p, "roles")["seat"])] = reported(p, "roles")
	_judge_roles(all_roles)

	# 1. Everyone walks.
	for p in client_peers():
		command(p, "walk")
	var mine := await do_walk()
	check(await wait_reports("walk", 2, 40.0), "both clients report their walk")
	var walks := {1: mine}
	for p in peers_with("walk"):
		walks[int(reported(p, "walk")["seat"])] = reported(p, "walk")
	_judge_walk(walks)

	# 2. A teleport, damage, a held spell and a death.
	for p in client_peers():
		command(p, "events")
	var mine_events := await do_events()
	check(await wait_reports("events", 2, 40.0), "both clients report the events")
	var events := {1: mine_events}
	for p in peers_with("events"):
		events[int(reported(p, "events")["seat"])] = reported(p, "events")
	_judge_events(events)
	for p in client_peers():
		command(p, "end")
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	if not await enter_floor(SEED):
		return
	if not await wait_sync():
		return
	report("roles", roles())
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"walk":
				report("walk", await do_walk())
			"events":
				report("events", await do_events())
			_:
				running = false


# --- Roles ---------------------------------------------------------------------------------------------------

## What this machine thinks each seat is: puppet or its own, who it controls, how the nameplates read.
func roles() -> Dictionary:
	var heroes := game.get("heroes_by_seat") as Dictionary
	var out := {"seat": my_seat(), "puppets": Session.snap.puppet_seats(), "live": Session.snap.live_seats(), "labels": {}, "flags": {}}
	var controllers := 0
	var brains := 0
	for seat: int in heroes:
		var h: Hero = heroes[seat]
		controllers += 1 if h.get_node_or_null("PlayerController") != null else 0
		brains += 1 if h.get_node_or_null("AllyBrain") != null else 0
		(out["labels"] as Dictionary)[seat] = h._name_label.text if h._name_label != null else ""
		(out["flags"] as Dictionary)[seat] = {"puppet": Net.is_puppet(h), "copy": Net.is_copy(h), "owns": Net.owns(h), "physics": h.is_physics_processing()}
	out["controllers"] = controllers
	out["brains"] = brains
	return out


func _judge_roles(all: Dictionary) -> void:
	var names := {1: "host", 2: "c1", 3: "c2"}
	for viewer: int in all:
		var r: Dictionary = all[viewer]
		var others: Array = [1, 2, 3]
		others.erase(viewer)
		eq(str(r["puppets"]), str(others), "seat %d shows the other two as puppets" % viewer)
		eq(str(r["live"]), str([viewer]), "seat %d simulates only its own hero" % viewer)
		eq(int(r["controllers"]), 1, "seat %d controls exactly one hero" % viewer)
		eq(int(r["brains"]), 0, "seat %d runs no AI (all three seats are players)" % viewer)
		for seat: int in others:
			eq(str((r["labels"] as Dictionary)[seat]), names[seat], "seat %d reads %s over seat %d's hero" % [viewer, names[seat], seat])
			var f: Dictionary = (r["flags"] as Dictionary)[seat]
			check(bool(f["puppet"]) and bool(f["copy"]) and not bool(f["owns"]) and not bool(f["physics"]), "seat %d: seat %d's hero is a puppet, not simulated" % [viewer, seat])
		var own: Dictionary = (r["flags"] as Dictionary)[viewer]
		check(bool(own["owns"]) and not bool(own["puppet"]) and not bool(own["copy"]), "seat %d owns its own hero" % viewer)


# --- The walk ----------------------------------------------------------------------------------------------

func do_walk() -> Dictionary:
	record(true)
	start_bot()
	await sleep(WALK)
	record(false)
	var delays := {}
	for seat in Session.snap.puppet_seats():
		delays[seat] = Session.snap.delay_of(seat)
	return {"seat": my_seat(), "ring": ring, "seen": seen, "wire": snap_wire(), "stats": Session.snap.stats.duplicate(),
		"delays": delays, "reached": bot.reached}


func _judge_walk(all: Dictionary) -> void:
	var rings := {}
	for seat: int in all:
		rings[seat] = (all[seat] as Dictionary)["ring"]
	var gaps := 0
	var stale := 0
	for viewer: int in all:
		var d: Dictionary = all[viewer]
		check(int(d["reached"]) >= 8, "seat %d's bot walked its loop (%d waypoints)" % [viewer, int(d["reached"])])
		for seat: int in (d["seen"] as Dictionary):
			var e := series_error(rings[seat] as PackedFloat64Array, (d["seen"] as Dictionary)[seat] as PackedFloat64Array)
			var delay := float((d["delays"] as Dictionary)[seat])
			print("[M2] seat %d sees seat %d: %d frames, max err %.3f (mean %.3f), max step %.3f (beyond walking %.3f), delay %.3f" % [
				viewer, seat, int(e["n"]), float(e["max_err"]), float(e["mean_err"]), float(e["max_step"]), float(e["max_excess"]), delay])
			check(int(e["n"]) > 300, "seat %d watched seat %d walk (%d frames)" % [viewer, seat, int(e["n"])])
			check(float(e["max_err"]) <= TOL, "seat %d: seat %d's puppet stays within %.2f of where the hero really was (%.3f)" % [viewer, seat, TOL, float(e["max_err"])])
			check(float(e["max_excess"]) <= MAX_STEP, "seat %d: seat %d's puppet never snaps %.1f beyond what walking covers in a frame (%.3f)" % [viewer, seat, MAX_STEP, float(e["max_excess"])])
			check(delay >= NetInterp.DELAY - 0.001 and delay <= NetInterp.DELAY_MAX, "seat %d: seat %d's delay is sane (%.3f)" % [viewer, seat, delay])
			if link == "off":
				check(delay < 0.16, "seat %d: on a clean link seat %d is shown about 100 ms behind (%.3f)" % [viewer, seat, delay])
		var w: Array = d["wire"]
		gaps += int(w[2])
		stale += int(w[1])
		var st: Dictionary = d["stats"]
		print("[M2] seat %d: snapshots out %d (%.0f B/s, biggest %d B), in %d (%.0f B/s); wire accepted %d stale %d gaps %d" % [
			viewer, int(st["out_packets"]), float(d["stats"]["out_bytes"]) / WALK, int(st["out_max"]), int(st["in_packets"]),
			float(st["in_bytes"]) / WALK, int(w[0]), int(w[1]), int(w[2])])
		check(int(st["in_packets"]) > 200, "seat %d received a steady stream (%d snapshots)" % [viewer, int(st["in_packets"])])
		check(int(st["in_foreign"]) == 0, "seat %d got no state for a hero it should not be told about" % viewer)
		var rate := float(st["out_bytes"]) / WALK
		if viewer == 1:
			check(int(st["out_max"]) == 40, "the host's snapshot to a client (two heroes) is 40 bytes (%d)" % int(st["out_max"]))
			check(rate / 2.0 < BUDGET, "the host sends %.0f B/s to each client, under the 3 KB/s budget" % (rate / 2.0))
		else:
			check(int(st["out_max"]) == 24, "a client's snapshot (one hero) is 24 bytes (%d)" % int(st["out_max"]))
			check(rate < BUDGET, "a client sends %.0f B/s, under the 3 KB/s budget" % rate)
	if link == "off":
		eq(gaps, 0, "a clean link loses no snapshot")
	else:
		check(gaps >= 1, "over `coast` snapshots were really lost (%d gaps, %d refused as stale) and the walk held anyway" % [gaps, stale])


# --- Events ------------------------------------------------------------------------------------------------

## c1 (index 1) stops, teleports, takes damage and readies its second spell; c2 takes damage and then dies; the host takes a
## little damage. Everyone watches the others. Returns what this machine did and what it saw.
func do_events() -> Dictionary:
	var out := {"seat": my_seat()}
	record(true)
	bot.stop()
	var hero := my_hero()
	var t0 := wall()
	match index:
		1:
			await sleep(1.2)
			out["a"] = hero.global_position
			var far := bot.route[0]
			for p in bot.route:
				if p.distance_to(hero.global_position) > far.distance_to(hero.global_position):
					far = p
			out["b"] = far
			out["t_tp"] = Session.host_time()
			bot.teleport(far)
			await sleep(0.4)
			hero.apply_damage(20.0)
			hero.select_slot(1)
		2:
			await sleep(1.5)
			hero.apply_damage(30.0)
			await sleep(1.0)
			hero.apply_damage(9999.0)
		_:
			await sleep(2.0)
			hero.apply_damage(10.0)
	await until(func() -> bool: return wall() - t0 >= EVENTS_SECONDS, 20.0)
	record(false)
	out["own"] = {"hp": hero.hp, "dead": hero.dead, "held": hero.held_slot}
	var view := {}
	for seat in Session.snap.puppet_seats():
		var h := hero_at(seat)
		view[seat] = {"hp": h.hp, "dead": h.dead, "held": h.held_slot}
	out["view"] = view
	out["seen"] = seen
	return out


func _judge_events(all: Dictionary) -> void:
	# The teleport: c1 is seat 2.
	var c1: Dictionary = all[2]
	var a: Vector3 = c1["a"]
	var b: Vector3 = c1["b"]
	var t_tp := float(c1["t_tp"])
	var span := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	check(span > 6.0, "c1 teleported %.1f units" % span)
	for viewer: int in [1, 3]:
		var series: PackedFloat64Array = (all[viewer]["seen"] as Dictionary)[2]
		var stray := 0
		var jumps := 0
		var biggest := 0.0
		var prev := Vector2.INF
		var frames := 0
		for i in floori(float(series.size()) / 5.0):
			var now := series[i * 5 + 4]
			if now < t_tp - 0.5 or now > t_tp + 2.0:
				continue
			frames += 1
			var q := Vector2(series[i * 5 + 1], series[i * 5 + 3])
			if q.distance_to(Vector2(a.x, a.z)) > 0.6 and q.distance_to(Vector2(b.x, b.z)) > 0.6:
				stray += 1
			if prev != Vector2.INF:
				var step := q.distance_to(prev)
				biggest = maxf(biggest, step)
				if step > 3.0:
					jumps += 1
			prev = q
		print("[M2] seat %d watching the teleport: %d frames, %d jump(s) (%.1f units), %d frames away from both ends" % [viewer, frames, jumps, biggest, stray])
		check(frames > 100, "seat %d watched the teleport (%d frames)" % [viewer, frames])
		eq(jumps, 1, "seat %d saw ONE jump" % viewer)
		check(biggest > span - 1.0, "... of the whole distance (%.1f of %.1f)" % [biggest, span])
		eq(stray, 0, "seat %d never saw the hero anywhere between the two ends" % viewer)
	# HP, the held spell, death: every screen agrees with the owner.
	for owner: int in all:
		var own: Dictionary = (all[owner] as Dictionary)["own"]
		for viewer: int in all:
			if viewer == owner:
				continue
			var v: Dictionary = ((all[viewer] as Dictionary)["view"] as Dictionary)[owner]
			near(float(v["hp"]), float(own["hp"]), 0.1, "seat %d sees seat %d's hp" % [viewer, owner])
			eq(bool(v["dead"]), bool(own["dead"]), "seat %d sees whether seat %d is down" % [viewer, owner])
			eq(int(v["held"]), int(own["held"]), "seat %d sees seat %d's held spell" % [viewer, owner])
	near(float((all[2]["own"] as Dictionary)["hp"]), 85.0 - 20.0, 0.1, "c1 really took 20")
	eq(int((all[2]["own"] as Dictionary)["held"]), 1, "c1 really readied slot 2")
	check(bool((all[3]["own"] as Dictionary)["dead"]), "c2 really went down")
	near(float((all[1]["own"] as Dictionary)["hp"]), 85.0 - 10.0, 0.1, "the host really took 10")

extends NetGameTest
## M7, the swarmer wind-up MEASUREMENT (networking.md open risk; the plan's M7 notes hold the numbers and the options). Three
## players stand by the van with six swarmers sent at them (--spawn-near swarmer,6), `off` and `coast`. Nothing here picks a
## design: it measures, and the checks only make sure there was something to measure.
##
## Phase 1, STANDING STILL (10 s): every swarmer wind-up aimed at a hero, per machine:
##   - how long the wind-up is VISIBLE on the victim's own screen before the strike is decided there: on the host, from the
##     monster entering its wind-up to the strike (Swarmer.WINDUP, 0.3 s since 2026-10-18); on a client, from the first frame its puppet SHOWS
##     the wind-up (the snapshot's ATTACK state, at the render delay) to the frame this client resolves the strike (render
##     time >= start + length - NetWorld.STRIKE_EARLY);
##   - when the world.windup event arrived on the client, against the wind-up's start (one way + polling), i.e. how early a
##     telegraph drawn from the EVENT could start;
##   - hits taken from swarmers per wind-up aimed at the hero.
## Phase 2, A PERFECT REFLEX (10 s): each machine's bot steps away from a swarmer the frame ITS screen first shows that swarmer
##   winding up at its hero (0 ms reaction, a human needs 200+): the share of those strikes that still hit, host vs clients.
## Every owner tops its own hero's HP up (no one dies), and every hero hit lands in the hits sheet (by kind "swarmer"). The
## host splits the swarmers two per hero (they keep their first pick otherwise). Hits counted are on THIS machine's hero
## from any swarmer strike that reached it (a strike at a teammate can catch it in the arc).

const PEERS := 3
const SEED := 13
const PHASE := 10.0
const DODGE_TIME := 0.3

var _attack_start: Dictionary = {}    ## monster id -> host_time its ATTACK began on this screen (or on the host, for real)
var _windup_arrival: Dictionary = {}  ## client: monster id -> [arrival host_time, s, length, victim]
var _seen_resolved := 0
var _dodging_until := 0.0
var _dodge := false
var _measuring := false
## This machine's samples: visible (s) per wind-up aimed at my hero, arrival lead (s), hit flags.
var visible: Array[float] = []
var arrival: Array[float] = []
var strikes_at_me := 0
var hits := 0
var dodged_attempts := 0


func run_host() -> void:
	if not await enter_floor(SEED, 1, {"spawn_near": "swarmer,6"}):
		return
	if not await wait_sync():
		return
	_watch_host()
	check(await wait_reports("ready", 2, 30.0), "both clients are on the floor")
	var results := {}
	for phase in ["still", "reflex"]:
		_reset(phase == "reflex")
		for p in client_peers():
			command(p, "phase", {"dodge": phase == "reflex"})
		var end := Session.host_time() + PHASE
		while Session.host_time() < end:
			_share_targets()
			await sleep(0.5)
		_measuring = false
		for p in client_peers():
			command(p, "report", {"phase": phase})
		check(await wait_reports(phase, 2, 20.0), "both clients report %s" % phase)
		results[phase] = {"host": _summary()}
		for p in client_peers():
			results[phase][_name_of(p)] = reported(p, phase)
		_print_phase(phase, results[phase])
	var still: Dictionary = results["still"]
	check(int((still["host"] as Dictionary)["at_me"]) + int((still["c1"] as Dictionary)["at_me"]) + int((still["c2"] as Dictionary)["at_me"]) >= 6,
		"the swarmers wound up at the crew (something to measure)")
	for who in ["c1", "c2"]:
		var r: Dictionary = still[who]
		if int(r["at_me"]) > 0:
			check(float(r["vis_mean"]) > 0.0, "%s saw the wind-ups on its screen before they were decided there (mean %.0f ms)" % [who, float(r["vis_mean"]) * 1000.0])
	for p in client_peers():
		command(p, "end")
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	if not await enter_floor(SEED, 1, {"spawn_near": "swarmer,6"}):
		return
	if not await wait_sync():
		return
	Session.event_received.connect(_on_world_event)
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"phase":
				_reset(bool(cmd["dodge"]))
			"report":
				_measuring = false
				report(str(cmd["phase"]), _summary())
			_:
				running = false


func _reset(dodge: bool) -> void:
	visible.clear()
	arrival.clear()
	strikes_at_me = 0
	hits = 0
	dodged_attempts = 0
	_dodge = dodge
	_measuring = true
	_seen_resolved = Session.world.resolved.size() if Session.world != null else 0


func _summary() -> Dictionary:
	var vis_mean := 0.0
	for v in visible:
		vis_mean += v
	vis_mean = vis_mean / float(visible.size()) if not visible.is_empty() else 0.0
	var arr_mean := 0.0
	for v in arrival:
		arr_mean += v
	arr_mean = arr_mean / float(arrival.size()) if not arrival.is_empty() else 0.0
	var zero := visible.filter(func(v: float) -> bool: return v <= 0.0).size()
	return {"at_me": strikes_at_me, "hits": hits, "vis_mean": vis_mean, "vis_min": visible.min() if not visible.is_empty() else 0.0,
		"vis_max": visible.max() if not visible.is_empty() else 0.0, "vis_zero": zero, "arr_mean": arr_mean,
		"arr_max": arrival.max() if not arrival.is_empty() else 0.0, "dodges": dodged_attempts,
		"delay": Session.world.delay() if not Session.hosting else 0.0}


# --- The host: its own hero's wind-ups are real time --------------------------------------------------------------

func _watch_host() -> void:
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m == null or m.kind != "swarmer":
			continue
		m.windup_begun.connect(func(_l: float) -> void:
			if _measuring and m.target == my_hero():
				_attack_start[id] = Session.host_time())
		m.windup_dropped.connect(func() -> void: _attack_start.erase(id))   # (called off: not a strike)
	my_hero().damaged.connect(func(amount: float, src: Node) -> void:
		if _measuring and amount > 0.0 and src is Monster and (src as Monster).kind == "swarmer" and (src as Monster).target == my_hero():
			hits += 1)   # (a strike aimed at me, as a client counts it)


## Host: the six swarmers split two per hero (left alone they keep whoever they picked first: the measurement needs the
## host's hero in it too). A swarmer mid wind-up keeps its target.
func _share_targets() -> void:
	var i := 0
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m == null or m.dead or m.kind != "swarmer":
			continue
		var h := hero_at(1 + i % 3)
		i += 1
		if h != null and m.state != Monster.State.ATTACK and m.target != h:
			m.target = h


# --- A client: what its screen shows ---------------------------------------------------------------------------------

func _on_world_event(_from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if kind != "world.windup" or not _measuring:
		return
	if int(data.get("v", 0)) != NetFloor.id_of(my_hero()):
		return
	var m := NetRegistry.node(int(data.get("id", 0))) as Monster
	if m == null or m.kind != "swarmer":
		return
	_windup_arrival[int(data["id"])] = [Session.host_time(), float(data["s"]), float(data["l"])]
	arrival.append(Session.host_time() - float(data["s"]))


func _process(delta: float) -> void:
	super._process(delta)
	if game == null or not _measuring or my_hero() == null:
		return
	var me := my_hero()
	var now := Session.host_time()
	# Wind-ups as this screen shows them.
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m == null or m.dead or m.kind != "swarmer":
			continue
		var attacking := m.state == Monster.State.ATTACK
		if Session.hosting and not attacking and _attack_start.has(id):
			# The host's own wind-up at its hero ended in a strike (a called-off one was erased): visible all along.
			strikes_at_me += 1
			visible.append(now - float(_attack_start[id]))
			_attack_start.erase(id)
		if not Session.hosting:
			if attacking and not _attack_start.has(id):
				_attack_start[id] = now
			elif not attacking and _attack_start.has(id) and now - float(_attack_start[id]) > 0.5:
				_attack_start.erase(id)
		var aimed := m.target == me if Session.hosting else (Session.world._windups.has(id) and int((Session.world._windups[id] as Array)[1]) == NetFloor.id_of(me))
		if _dodge and attacking and aimed and now >= _dodging_until:
			_step_away(m)
	if now >= _dodging_until:
		(game.get("controller") as PlayerController).move_override = Vector3.INF
	# A client: the strikes this screen resolved on its own hero.
	if not Session.hosting:
		var res: Array = Session.world.resolved
		while _seen_resolved < res.size():
			var r: Array = res[_seen_resolved]
			_seen_resolved += 1
			if int(r[1]) != NetFloor.id_of(me):
				continue
			var m := NetRegistry.node(int(r[0])) as Monster
			if m == null or m.kind != "swarmer":
				continue
			strikes_at_me += 1
			if float(r[3]) > 0.0:
				hits += 1
			var t0 := float(_attack_start.get(int(r[0]), -1.0))
			visible.append(float(r[2]) - t0 if t0 > 0.0 and float(r[2]) - t0 < 0.6 else 0.0)
	# Nobody dies: each owner tops up its own hero.
	if me.hp < me.max_hp * 0.6 and not me.dead:
		me.hp = me.max_hp


func _step_away(m: Monster) -> void:
	var away := my_hero().global_position - m.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.RIGHT
	(game.get("controller") as PlayerController).move_override = away.normalized()
	_dodging_until = Session.host_time() + DODGE_TIME
	dodged_attempts += 1


func _name_of(peer: int) -> String:
	return str((Session.roster.get(peer, {}) as Dictionary).get("name", peer))


func _print_phase(phase: String, res: Dictionary) -> void:
	for who: String in res:
		var r: Dictionary = res[who]
		print("[M7 swarmers] %s %s %s: %d wind-ups at me, %d hits (%.0f%%), visible on my screen mean %.0f ms (min %.0f, max %.0f, %d never shown), event arrived %.0f ms after the start (max %.0f), render delay %.0f ms, %d dodges" % [
			link, phase, who, int(r["at_me"]), int(r["hits"]), 100.0 * float(r["hits"]) / maxf(float(r["at_me"]), 1.0),
			float(r["vis_mean"]) * 1000.0, float(r["vis_min"]) * 1000.0, float(r["vis_max"]) * 1000.0, int(r["vis_zero"]),
			float(r["arr_mean"]) * 1000.0, float(r["arr_max"]) * 1000.0, float(r["delay"]) * 1000.0, int(r["dodges"])])

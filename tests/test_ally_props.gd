extends TestCase
## AI allies and the client's property (user, 2026-10-18: "double check our AI teammates won't go wild"). The crew's
## swings, arrows, bolts and boulders hit priced props, so the AI allies (Rebar: fist + bowl, Gasket: hammer + spin) are
## careful (AllyBrain.prop_care). On real contract floors a stand-in leader (invulnerable, never attacking) walks the
## rooms one by one, waiting in each until its fight is over; the two AI allies follow and fight. Every floor is run
## twice, careless and careful, and the test reports per floor: props the allies damaged and broke, dollars billed to
## them, kills and the time spent. Careful allies break (nearly) nothing and keep about the same kill rate.

const FLOORS := [["prepper", 3, 1], ["supervillain", 7, 2], ["guru", 11, 1], ["founder", 21, 3], ["prepper", 42, 2]]
const FLOOR_TIME := 150.0          ## game seconds per floor
const ROOM_WAIT := 20.0            ## at most this long in a room waiting for its fight to end

var root: Node3D
var _stats := {}


func _init() -> void:
	timeout_sec = 4000.0


func setup() -> void:
	var totals := {false: {}, true: {}}
	for care in [false, true]:
		for k in ["damaged", "dmg", "broken", "billed", "kills", "time", "held"]:
			totals[care][k] = 0.0
	for f: Array in FLOORS:
		for care in [false, true]:
			AllyBrain.prop_care = care
			var r: Dictionary = await _run_floor(f[0], f[1], f[2])
			print("ally props %-12s seed %3d floor %d %s: props hit %d (%.0f HP), broken %d, billed $%d, kills %d in %.0f s, attacks held %d" % [
				f[0], f[1], f[2], "careful " if care else "careless", int(r["damaged"]), float(r["dmg"]), int(r["broken"]), int(r["billed"]),
				int(r["kills"]), float(r["time"]), int(r["held"])])
			for k: String in r:
				totals[care][k] = float(totals[care][k]) + float(r[k])
	AllyBrain.prop_care = true
	var n := float(FLOORS.size())
	for care in [false, true]:
		var t: Dictionary = totals[care]
		print("ally props %s, per floor: props hit %.1f, broken %.2f, billed $%.0f, kills %.1f (%.2f a minute), held %.1f" % [
			"CAREFUL " if care else "CARELESS", t["damaged"] / n, t["broken"] / n, t["billed"] / n, t["kills"] / n,
			t["kills"] / maxf(t["time"], 1.0) * 60.0, t["held"] / n])
	var careful: Dictionary = totals[true]
	var careless: Dictionary = totals[false]
	check(careful["broken"] / n <= 0.4, "careful AI allies break at most a prop every few floors (%.2f a floor)" % (careful["broken"] / n))
	check(careful["billed"] <= careless["billed"], "careful allies bill no more than careless ones ($%d vs $%d)" % [int(careful["billed"]), int(careless["billed"])])
	var rate_care: float = careful["kills"] / maxf(careful["time"], 1.0)
	var rate_wild: float = careless["kills"] / maxf(careless["time"], 1.0)
	check(rate_care >= rate_wild * 0.8, "careful allies keep about their kill rate (%.2f vs %.2f a minute)" % [rate_care * 60.0, rate_wild * 60.0])
	finish()


func _run_floor(arch: String, s: int, f: int) -> Dictionary:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	var run := ContractRun.make(arch, s, 0.5)
	var map := DungeonGen.for_run(run, f)
	GameWorld.begin(map, root, run.floor_seed(f))
	Ledger.begin_contract(1000000)
	MonsterSenses.restless_override = 0.0
	var site := SiteBuilder.build(map, run, f)
	var start := site.plan.start
	var spots := Hex.range_cells(start, 2).filter(func(c: Vector2i) -> bool: return c != start and map.is_walkable_cell(c))
	var leader := HeroFactory.spawn_hero(start, "Wick", Color.WHITE, "sword", null, "wick")
	var rebar := HeroFactory.spawn_hero(spots[0], "Rebar", Color.WHITE, "sword", null, "rebar")
	var gasket := HeroFactory.spawn_hero(spots[mini(1, spots.size() - 1)], "Gasket", Color.WHITE, "sword", null, "gasket")
	var brains: Array = []
	for pair in [[rebar, 2.4, 2.6], [gasket, 3.9, 3.3]]:
		brains.append(HeroFactory.make_ally(pair[0], leader, false, pair[1], pair[2]))
	for h in [leader, rebar, gasket]:
		h.set_modifier("test_ward", 0.0, 99999.0)   # (nobody goes down: the fights go on)
	var allies := [rebar, gasket]
	var out := {"damaged": 0, "dmg": 0.0, "broken": 0, "billed": 0, "kills": 0, "time": 0.0, "held": 0}
	var hit_props := {}
	for pr in site.props:
		pr.damaged.connect(func(amount: float, src: Node) -> void:
			if allies.has(src):
				hit_props[pr.get_instance_id()] = true
				out["dmg"] = float(out["dmg"]) + amount)
		pr.broken.connect(func(_p: PricedProp, culprit: Node) -> void:
			if allies.has(culprit):
				out["broken"] = int(out["broken"]) + 1)
	var last_hit := {}
	for m in get_tree().get_nodes_in_group("monsters"):
		_watch(m, allies, last_hit, out)
	var on_spawn := func(a: Actor) -> void:
		if a is Monster:
			_watch(a, allies, last_hit, out)
	GameWorld.actor_spawned.connect(on_spawn)
	# The leader's tour: every room, nearest first, waiting in each until nothing near it is fighting.
	var rooms: Array = site.plan.rooms.keys()
	rooms.sort()
	var t0 := GameWorld.time
	var here := start
	var left := rooms.duplicate()
	while not left.is_empty() and GameWorld.time - t0 < FLOOR_TIME:
		left.sort_custom(func(a: String, b: String) -> bool: return Hex.distance(here, site.plan.centers[a]) < Hex.distance(here, site.plan.centers[b]))
		var tag: String = left.pop_front()
		var goal: Vector2i = site.plan.centers[tag]
		if not map.is_walkable_cell(goal):
			continue
		var path := map.find_path(leader.current_cell(), goal, leader.can_climb, 3000)
		var i := 1
		while i < path.size() and GameWorld.time - t0 < FLOOR_TIME:
			var wp := Hex.to_world(path[i])
			var to := wp - leader.global_position
			to.y = 0.0
			if to.length() < 0.35:
				i += 1
				continue
			leader.move(to.normalized(), get_physics_process_delta_time())
			await get_tree().physics_frame
		here = goal
		var wait_t := GameWorld.time
		while GameWorld.time - wait_t < ROOM_WAIT and GameWorld.time - t0 < FLOOR_TIME and _fighting_near(leader):
			await get_tree().physics_frame
	out["time"] = GameWorld.time - t0
	out["damaged"] = hit_props.size()
	for line in Ledger.lines:
		if str(line.get("kind", "")) == "damage" and (str(line.get("who", "")) == "Rebar" or str(line.get("who", "")) == "Gasket"):
			out["billed"] = int(out["billed"]) + int(line.get("amount", 0))
	for b in brains:
		out["held"] = int(out["held"]) + int(b.held_for_props)
	GameWorld.actor_spawned.disconnect(on_spawn)
	return out


func _watch(m: Node, allies: Array, last_hit: Dictionary, out: Dictionary) -> void:
	var id := m.get_instance_id()
	m.damaged.connect(func(_amount: float, src: Node) -> void: last_hit[id] = src)
	m.died.connect(func() -> void:
		if allies.has(last_hit.get(id)):
			out["kills"] = int(out["kills"]) + 1)


func _fighting_near(leader: Hero) -> bool:
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if m is Monster and (m as Monster).is_aggro() and GameWorld.flat_distance(m.global_position, leader.global_position) < 14.0:
			return true
	return false

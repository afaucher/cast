extends TestCase
## The AI restraint baseline measured (combat-variety-research.md 1.3 and A1, combat-proposals.md 1.0 "As built"). On real
## contract floors a stand-in player (Wick: a bot that walks the rooms and opens fights on what it sees, bow from range,
## dagger up close) leads the two AI allies (Rebar, Gasket). Every floor runs twice, the old eager AI and the restraint
## baseline, and the test reports who hit each monster first, who killed it, how long a monster lived after the crew's first
## hit, and the floor's pace. Nobody can go down (a ward), so every floor runs its full time.
## The goal (user, 2026-10-19): the player gets the first hits and the AI supports.

const FLOORS := [["prepper", 3, 1], ["supervillain", 7, 2], ["guru", 11, 1], ["founder", 21, 3], ["prepper", 42, 2], ["guru", 5, 2]]
const FLOOR_TIME := 110.0          ## game seconds per floor
const ROOM_WAIT := 20.0            ## at most this long in a room while something there is fighting
const SIGHT := 8.0                 ## the stand-in player opens on a monster it sees this close
const SHOOT_FROM := 6.5            ## ... shooting from here, closing to here first

var root: Node3D
## Monster instance id -> its state at the start of this physics frame (this node runs before the world under it), so a
## first hit can tell whether it OPENED a fight (the monster was in none: idle, suspicious, searching, walking home) or
## joined one (chasing, attacking, or on ALERT after its pack heard a fight).
var _state_at: Dictionary = {}


func _init() -> void:
	timeout_sec = 3000.0


func _physics_process(_delta: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	for n in get_tree().get_nodes_in_group("monsters"):
		_state_at[n.get_instance_id()] = n.state


func setup() -> void:
	var totals := {}
	for mode in ["eager", "restraint"]:
		totals[mode] = {"first_player": 0, "first_ai": 0, "open_player": 0, "open_ai": 0, "kill_player": 0, "kill_ai": 0,
			"time": 0.0, "lives": []}
	for f: Array in FLOORS:
		for mode in ["eager", "restraint"]:
			AllyBrain.restraint = mode == "restraint"
			var r: Dictionary = await _run_floor(f[0], f[1], f[2])
			print("restraint %-12s seed %3d floor %d %-9s: first hits player %d / AI %d; fights opened player %d / AI %d; kills player %d / AI %d; median life after first hit %.2f s; %.0f s" % [
				f[0], f[1], f[2], mode, r["first_player"], r["first_ai"], r["open_player"], r["open_ai"], r["kill_player"], r["kill_ai"],
				_median(r["lives"]), r["time"]])
			var t: Dictionary = totals[mode]
			for k: String in r:
				if k == "lives":
					(t["lives"] as Array).append_array(r["lives"])
				else:
					t[k] = t[k] + r[k]
	AllyBrain.restraint = true
	for mode in ["eager", "restraint"]:
		var t: Dictionary = totals[mode]
		var firsts: int = t["first_player"] + t["first_ai"]
		var kills: int = t["kill_player"] + t["kill_ai"]
		print("RESTRAINT %-9s (%d floors): first hits player %d / AI %d (player %.0f%%); fights opened player %d / AI %d; kills player %d / AI %d (player %.0f%%); %d kills, %.1f a minute; median life after the first hit %.2f s" % [
			mode, FLOORS.size(), t["first_player"], t["first_ai"], 100.0 * t["first_player"] / maxf(firsts, 1.0), t["open_player"], t["open_ai"], t["kill_player"],
			t["kill_ai"], 100.0 * t["kill_player"] / maxf(kills, 1.0), kills, kills / maxf(t["time"], 1.0) * 60.0, _median(t["lives"])])
	var e: Dictionary = totals["eager"]
	var r2: Dictionary = totals["restraint"]
	var share_e := float(e["first_player"]) / maxf(e["first_player"] + e["first_ai"], 1.0)
	var share_r := float(r2["first_player"]) / maxf(r2["first_player"] + r2["first_ai"], 1.0)
	check(share_r > share_e, "restraint: the player's share of first hits goes up (%.0f%% -> %.0f%%)" % [share_e * 100.0, share_r * 100.0])
	check(share_r >= 0.6, "restraint: the player gets most first hits (%.0f%%)" % (share_r * 100.0))
	check(int(r2["first_ai"]) < int(e["first_ai"]), "restraint: the AI hits first less often (%d -> %d)" % [e["first_ai"], r2["first_ai"]])
	eq(int(r2["open_ai"]), 0, "restraint: the AI never opens a fight (a first hit on a monster in no fight)")
	check(int(r2["kill_ai"]) > 0, "restraint: the AI still fights (%d kills)" % r2["kill_ai"])
	finish()


static func _median(a: Array) -> float:
	if a.is_empty():
		return -1.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


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
	var player := HeroFactory.spawn_hero(start, "Wick", Color.WHITE, "sword", null, "wick")
	var rebar := HeroFactory.spawn_hero(spots[0], "Rebar", Color.WHITE, "sword", null, "rebar")
	var gasket := HeroFactory.spawn_hero(spots[mini(1, spots.size() - 1)], "Gasket", Color.WHITE, "sword", null, "gasket")
	for pair in [[rebar, 2.4, 2.6], [gasket, 3.9, 3.3]]:
		HeroFactory.make_ally(pair[0], player, false, pair[1], pair[2])
	for h in [player, rebar, gasket]:
		h.set_modifier("test_ward", 0.0, 99999.0)
	var allies := [rebar, gasket]
	var out := {"first_player": 0, "first_ai": 0, "open_player": 0, "open_ai": 0, "kill_player": 0, "kill_ai": 0,
		"time": 0.0, "lives": []}
	var seen := {}
	for m in get_tree().get_nodes_in_group("monsters"):
		_watch(m, player, allies, out, seen)
	var on_spawn := func(a: Actor) -> void:
		if a is Monster:
			_watch(a, player, allies, out, seen)
	GameWorld.actor_spawned.connect(on_spawn)
	var rooms: Array = site.plan.rooms.keys()
	rooms.sort()
	var t0 := GameWorld.time
	var here := start
	var left := rooms.duplicate()
	var dt := get_physics_process_delta_time()
	while not left.is_empty() and GameWorld.time - t0 < FLOOR_TIME:
		left.sort_custom(func(a: String, b: String) -> bool: return Hex.distance(here, site.plan.centers[a]) < Hex.distance(here, site.plan.centers[b]))
		var tag: String = left.pop_front()
		var goal: Vector2i = site.plan.centers[tag]
		if not map.is_walkable_cell(goal):
			continue
		var path := map.find_path(player.current_cell(), goal, player.can_climb, 3000)
		var i := 1
		while i < path.size() and GameWorld.time - t0 < FLOOR_TIME:
			if _player_fights(player, dt):
				await get_tree().physics_frame
				continue
			var wp := Hex.to_world(path[i])
			var to := wp - player.global_position
			to.y = 0.0
			if to.length() < 0.35:
				i += 1
				continue
			player.move(to.normalized(), dt)
			await get_tree().physics_frame
		here = goal
		var wait_t := GameWorld.time
		while GameWorld.time - wait_t < ROOM_WAIT and GameWorld.time - t0 < FLOOR_TIME and _fighting_near(player):
			_player_fights(player, dt)
			await get_tree().physics_frame
	out["time"] = GameWorld.time - t0
	GameWorld.actor_spawned.disconnect(on_spawn)
	return out


## The stand-in player: the nearest monster it can see within SIGHT gets an arrow from SHOOT_FROM (closing in first), or
## the dagger when it is in reach. True while it is fighting (it does not walk on).
func _player_fights(player: Hero, dt: float) -> bool:
	var best: Actor = null
	var best_d := SIGHT
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if not (m is Monster):
			continue
		var d := GameWorld.flat_distance(m.global_position, player.global_position)
		if d <= best_d and GameWorld.map.line_of_sight(Combat.chest(player), Combat.chest(m)):
			best_d = d
			best = m
	if best == null:
		return false
	var to := best.global_position - player.global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.01 else player.facing
	player.face_point(best.global_position)
	if best_d <= player.melee_reach - 0.1:
		player.melee(dir)
	elif best_d <= SHOOT_FROM:
		player.shoot(dir)
	else:
		player.move(dir, dt)
	return true


func _watch(m: Node, player: Hero, allies: Array, out: Dictionary, seen: Dictionary) -> void:
	var id := m.get_instance_id()
	if seen.has(id):
		return
	seen[id] = {"first": null, "first_t": -1.0, "last": null}
	m.damaged.connect(func(_amount: float, src: Node) -> void:
		var rec: Dictionary = seen[id]
		var crew := src == player or allies.has(src)
		if rec["first"] == null and crew:
			rec["first"] = src
			rec["first_t"] = GameWorld.time
			var was: int = _state_at.get(id, Monster.State.IDLE)
			var opened := not (was == Monster.State.CHASE or was == Monster.State.ATTACK or was == Monster.State.ALERT)
			var who := "player" if src == player else "ai"
			out["first_" + who] = int(out["first_" + who]) + 1
			if opened:
				out["open_" + who] = int(out["open_" + who]) + 1
		if crew:
			rec["last"] = src)
	m.died.connect(func() -> void:
		var rec: Dictionary = seen[id]
		var last: Variant = rec["last"]
		if last == null:
			return   # (not the crew's kill: a fall, a brawl)
		if last == player:
			out["kill_player"] = int(out["kill_player"]) + 1
		elif allies.has(last):
			out["kill_ai"] = int(out["kill_ai"]) + 1
		(out["lives"] as Array).append(GameWorld.time - float(rec["first_t"])))


func _fighting_near(leader: Hero) -> bool:
	for m in GameWorld.team_actors(GameWorld.TEAM_MONSTERS):
		if m is Monster and (m as Monster).is_aggro() and GameWorld.flat_distance(m.global_position, leader.global_position) < 14.0:
			return true
	return false

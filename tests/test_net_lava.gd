extends NetGameTest
## Lava caves online (docs/design/lava-playtest.md, "As built"), three processes, `off` and `coast`. Every process forces a
## cave (LavaSite.force, as `--lava-floor` in every window does) on floor 2 of the board-SEED job; the host and c1 play it, c2
## joins later.
## - THE FLOOR: the checksums (map with the cave's record, plan, contract, spawn) match on all three, the same cave record,
##   and every machine has made its lava void (LavaField.activate);
## - A SHOVE INTO LAVA: c1's hero shoved off the rock into the lava is pulled back by c1's own machine (onto rock, 15 damage,
##   burning); the host applies none of it and shows c1's hero where c1 has it;
## - THE CRUST, TERRAIN ON A SCHEDULE: c1's damp at an isle's shore crusts the lava on both machines at the same shared moment,
##   the same cells, and a path crosses it onto the isle;
## - THE MELT: c1's hero standing on the crust when it melts is pulled back by c1's machine (15, burning); a host-owned monster
##   on it sinks and dies once, by the host, and c1 shows it dead;
## - THE LATE JOINER: c2 joins while the host keeps a crust up (damp after damp on one spot): c2 has the same crust cells;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 4
const CONTRACT := 1
const FLOOR := 2
const PATTERN := "causeway"
const JOINER_SPELLS := ["tentacles", "teeth"]
const SPELLS := "damp,fireball"


func setup() -> void:
	LavaSite.force = true
	LavaSite.force_pattern = PATTERN
	super()


func run_host() -> void:
	net_timeout = 200.0
	follow_reloads = true
	clear_flag("join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	make_game({"spells": SPELLS, "seed": SEED, "contract": CONTRACT, "net_wait": 2, "floor": FLOOR})
	if not check(await wait_floor(45.0), "floor %d starts" % FLOOR) or not await wait_sync():
		return
	(game.get("opts") as Dictionary).erase("net_wait")
	eq(flow().desyncs, [], "every machine built the same cave floor (no desync at the barrier)")
	var map := game.get("map") as HexMap
	var mine := _describe()
	if not check(not map.cave.is_empty(), "the floor has a lava cave (%s)" % str(map.cave.get("pattern", "-"))):
		return
	check(bool(mine["void"]), "the host's lava is void")
	if check(await wait_reports("floor", 1, 30.0), "c1 reports its floor"):
		var r: Dictionary = reported(c1(), "floor")
		for part in ["all", "map", "plan", "run", "spawn"]:
			eq(str(r[part]), str(mine[part]), "c1: the %s checksum matches the host's" % part)
		eq(str(r["cave"]), str(mine["cave"]), "c1: the same cave record")
		check(bool(r["void"]), "c1's lava is void")
	# Everything the host runs holds still (the isles' archers would shoot); the AI hero too.
	var frozen: Array[Monster] = []
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate or n is Employee:
			n.set_physics_process(false)
			if n is Monster and not (n as Monster).dead and str((n as Monster).kind) != "archer":
				frozen.append(n as Monster)
	var ai := hero_at(3)
	if ai.get_node_or_null("AllyBrain") != null:
		ai.get_node("AllyBrain").set_physics_process(false)
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	var isle: Dictionary = (map.cave["isles"] as Array)[0]
	var shore: Vector2i = isle["shore"]
	place_hero(my_hero(), _rock_near(map, shore, 4))
	place_hero(ai, _rock_near(map, shore, 5))

	# A shove into the lava: c1's machine pulls its hero back.
	var edge := _edge(map)
	command(c1(), "shove", {"from": edge[0], "dir": edge[1]})
	if check(await wait_reports("shove", 1, 15.0), "c1 reports its shove"):
		var r: Dictionary = reported(c1(), "shove")
		print("[lava] c1 shove: %s" % str(r))
		check(bool(r["rock"]), "c1's hero is pulled back onto rock by its own machine")
		near(float(r["lost"]), Actor.LAVA_DAMAGE, 3.1, "... with the lava's 15 (and a burn tick or two)")
		check(bool(r["burning"]), "... and burning")
		await sleep(0.6)
		check(_flat(hero_at(2).global_position, r["pos"]) < 0.8, "the host shows c1's hero where c1 has it")
		near(hero_at(2).hp, float(r["hp"]), 3.1, "... with c1's HP (the host applied none of it)")

	# The crust: c1's damp at the shore, on the shared clock on both machines.
	var t_cast := Session.host_time()
	command(c1(), "damp", {"at": shore})
	if not check(await until(func() -> bool: return _field() != null and not _field()._cell_end.is_empty(), 8.0), "c1's damp crusts the host's lava"):
		return
	var host_born := _shared_born()
	var host_cells := _crust_cells()
	check(not map.find_path(shore, isle["center"], false, 20000).is_empty(), "a path crosses the crust onto the isle")
	if check(await wait_reports("damp", 1, 15.0), "c1 reports its crust"):
		var r: Dictionary = reported(c1(), "damp")
		near(float(r["born"]), host_born, 0.1, "the crust forms at the same shared moment on c1 (host %.3f, c1 %.3f)" % [host_born, float(r["born"])])
		eq(r["cells"], host_cells, "c1 has the same crust cells (%d)" % host_cells.size())
	# The melt: c1's hero and a host monster on the crust.
	var spots := _crust_spots(map, host_cells)
	if not check(spots.size() >= 2, "two crust cells to stand on (%d)" % spots.size()):
		return
	command(c1(), "stand", {"at": spots[0]})
	var mon: Monster = frozen[0] if not frozen.is_empty() else null
	var deaths := [0]
	if check(mon != null, "a host-owned monster to put on the crust"):
		mon.died.connect(func() -> void: deaths[0] += 1)
		mon.global_position = Hex.to_world(spots[1], float(map.get_cell(spots[1]).level))
		mon.reset_physics_interpolation()
	check(await wait_reports("melt", 1, LavaField.CRUST_LIFE + 10.0), "c1 reports the melt")
	if mon != null:
		check(await until(func() -> bool: return mon.dead or not is_instance_valid(mon), 4.0), "the host's monster on the crust sank")
		await sleep(0.8)
		eq(deaths[0], 1, "... and died once")
	var mr: Dictionary = reported(c1(), "melt")
	print("[lava] c1 melt: %s" % str(mr))
	check(bool(mr["was_crust"]), "c1's hero stood on c1's crust")
	check(bool(mr["rock"]), "the melt put c1's hero back on rock, by c1's machine")
	near(float(mr["lost"]), Actor.LAVA_DAMAGE, 3.1, "... with the lava's 15")
	check(bool(mr["burning"]) != bool(mr["soaked"]), "... and burning, unless its own damp soaked it (soaked: %s)" % str(mr["soaked"]))
	check(bool(mr["mon_dead"]), "c1 shows the host's monster dead")
	check(_field()._cell_end.is_empty(), "the host's crust melted")
	eq(int(mr["crust_left"]), 0, "... and c1's")

	# The late joiner, mid-crust: the host keeps a crust up at one spot until c2 is in.
	raise_flag("join")
	var spot := Hex.to_world(shore, float(map.get_cell(shore).level))
	var keep := [true]
	_keep_crust(spot, keep)
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 30.0), "c2 joins the crew on the job"):
		keep[0] = false
		return
	var c2 := peer_named("c2")
	if not check(await wait_reports("checkout", 1, 30.0), "c2 opened its license checkout"):
		keep[0] = false
		return
	command(c2, "sign", {"spells": JOINER_SPELLS})
	var arrived := await wait_reports("arrived", 1, 40.0)
	keep[0] = false
	if check(arrived, "c2 arrived"):
		await sleep(0.3)
		var cells := _crust_cells()
		check(not cells.is_empty(), "the host has a crust as c2 arrives")
		command(c2, "crust")
		if check(await wait_reports("crust", 1, 10.0), "c2 reports its crust"):
			var jr: Dictionary = reported(c2, "crust")
			eq(jr["cells"], cells, "c2 has the host's crust cells (%d)" % cells.size())
			check(bool(jr["void"]), "c2's lava is void")
	command(c2, "end")
	command(c1(), "end")
	check(await wait_reports("end", 2, 10.0), "the clients are done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in [c1(), c2]:
		if reported(p, "end") != null:
			eq(int((reported(p, "end") as Dictionary)["guard"]), 0, "... nor on peer %d" % p)


func run_client() -> void:
	net_timeout = 200.0
	follow_reloads = true
	if index == 2:
		await _late_joiner()
		return
	if not check(await connect_client() == "", "joined"):
		return
	make_game({"spells": SPELLS, "floor": FLOOR})
	if not check(await wait_floor(45.0), "the floor starts here") or not await wait_sync():
		return
	report("floor", _describe())
	var map := game.get("map") as HexMap
	var running := true
	while running:
		var cmd := await wait_command(120.0)
		match str(cmd.get("cmd", "")):
			"shove":
				place_hero(my_hero(), cmd["from"])
				await sleep(0.3)
				var hp := my_hero().hp
				my_hero().shove(cmd["dir"], 3.0, null)
				await until(func() -> bool: return not my_hero().is_shoved(), 4.0)
				await sleep(0.2)
				var c := my_hero().current_cell()
				report("shove", {"rock": map.is_walkable_cell(c) and not map.is_lava(c), "lost": hp - my_hero().hp,
					"burning": Burning.is_burning(my_hero()), "pos": my_hero().global_position, "hp": my_hero().hp})
			"damp":
				Burning.extinguish(my_hero())
				var at: Vector2i = cmd["at"]
				place_hero(my_hero(), _rock_near(map, at, 2))
				await sleep(0.2)
				var ctl := game.get("controller") as PlayerController
				my_hero()._ready_at.clear()
				ctl.aim_override = Hex.to_world(at, float(map.get_cell(at).level))
				check(ctl.cast_spell("damp", 1.0), "c1 casts damp")
				ctl.aim_override = Vector3.INF
				await until(func() -> bool: return _field() != null and not _field()._cell_end.is_empty(), 8.0)
				report("damp", {"born": _shared_born(), "cells": _crust_cells()})
			"stand":
				Burning.extinguish(my_hero())
				var at: Vector2i = cmd["at"]
				place_hero(my_hero(), at)
				var was := map.is_crust(at)
				var hp := my_hero().hp
				await until(func() -> bool: return _field()._cell_end.is_empty(), LavaField.CRUST_LIFE + 2.0)
				var soaked := Burning.is_soaked(my_hero())
				await until(func() -> bool: return not my_hero().is_shoved(), 4.0)
				await sleep(1.0)
				var c := my_hero().current_cell()
				var mon_dead := true
				for id in NetRegistry.ids():
					var m := NetRegistry.node(id) as Monster
					if m != null and m.is_inside_tree() and not m.dead and map.lava.has(m.current_cell()):
						mon_dead = false
				report("melt", {"soaked": soaked, "was_crust": was, "rock": map.is_walkable_cell(c) and not map.is_crust(c), "lost": hp - my_hero().hp,
					"burning": Burning.is_burning(my_hero()), "mon_dead": mon_dead, "crust_left": _field()._cell_end.size()})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


## c2: join the crew on the job, mid-crust, and report the crust it has.
func _late_joiner() -> void:
	var since := Time.get_unix_time_from_system()
	if not check(await wait_flag("join", since, 150.0), "the host raised the join flag"):
		return
	if not check(await connect_client() == "", "joined the crew on the job"):
		return
	make_game({})
	if not check(await until(func() -> bool: return picker() != null, 30.0), "c2's license checkout opened"):
		return
	report("checkout", true)
	var sign_cmd := await wait_command(30.0)
	if not check(str(sign_cmd.get("cmd", "")) == "sign", "the host says sign"):
		return
	check(await sign_license(sign_cmd["spells"] as Array), "c2 signs")
	if not check(await until(func() -> bool: return Session.join.arrived, 40.0), "c2 arrived on the crew's floor"):
		return
	await wait_floor(10.0)
	report("arrived", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"crust":
				report("crust", {"cells": _crust_cells(), "void": bool(_describe()["void"])})
			"end":
				report("end", {"guard": Net.guard_hits.size()})
				running = false
			_:
				running = false


func c1() -> int:
	return peer_named("c1")


func _field() -> LavaField:
	return LavaField.of_world()


## This machine's floor: its checksum, the cave record's hash, and whether its lava is void.
func _describe() -> Dictionary:
	var map := game.get("map") as HexMap
	var sums: Dictionary = flow().local_sums
	var lava: Array = map.cave.get("lava", [])
	var void_now := not lava.is_empty() and _field() != null and _field().active
	for c: Vector2i in lava.slice(0, 40):
		void_now = void_now and (not map.has_cell(c) or map.is_crust(c))   # (a crust may lie over some of it)
	return {"all": sums["all"], "map": sums["map"], "plan": sums["plan"], "run": sums["run"], "spawn": sums["spawn"],
		"cave": NetFloor.canon(map.cave).sha256_text(), "void": void_now}


## The crust's start (its first live source) on the shared clock.
func _shared_born() -> float:
	var f := _field()
	if f == null or f.crusts.is_empty():
		return -1.0
	return Session.host_time() - (GameWorld.time - float(f.crusts[0]["born"]))


func _crust_cells() -> Array:
	var out: Array = []
	if _field() == null:
		return out
	for c: Vector2i in _field()._cell_end:
		out.append(c)
	out.sort_custom(HexMap._cell_less)
	return out


## Crust cells beside the rock (a body put there stands on the crust), nearest the rock first.
static func _crust_spots(map: HexMap, cells: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in cells:
		for nn in Hex.neighbors(c):
			if map.is_walkable_cell(nn) and not map.is_crust(nn):
				out.append(c)
				break
	return out


## A walkable rock cell of the cave within `reach` of c, nearest first.
static func _rock_near(map: HexMap, c: Vector2i, reach: int) -> Vector2i:
	for d in range(0, reach + 1):
		for n in Hex.ring(c, d):
			if map.is_walkable_cell(n) and not map.is_crust(n) and not map.is_lava(n):
				return n
	return c


## A rock cell of a bridge with lava beside it, and the direction off it into the lava: [cell, dir].
static func _edge(map: HexMap) -> Array:
	for br: Dictionary in map.cave["bridges"]:
		if int(br["w"]) < 2:
			continue
		var rows: Array = br["rows"]
		var row: Array = rows[rows.size() / 2]
		for c: Vector2i in row:
			for d in 6:
				var n: Vector2i = c + Hex.DIRS[d]
				var n2: Vector2i = n + Hex.DIRS[d]
				if map.is_lava(n) and map.is_lava(n2) and map.is_walkable_cell(c):
					return [c, Hex.dir_vector(d)]
	return [map.cave["rock"][0], Vector3.RIGHT]


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Host: damp after damp at `spot` (every few seconds, before the last crust melts) while keep[0] is true.
func _keep_crust(spot: Vector3, keep: Array) -> void:
	var ctl := game.get("controller") as PlayerController
	while keep[0] and is_inside_tree():
		Burning.extinguish(my_hero())
		my_hero()._ready_at.clear()
		my_hero()._charges["damp"] = 9
		ctl.aim_override = spot
		ctl.cast_spell("damp", 1.0)
		ctl.aim_override = Vector3.INF
		await sleep(LavaField.CRUST_LIFE - 3.0)

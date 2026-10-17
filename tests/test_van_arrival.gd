extends TestCase
## The crew's work van (docs/design/environment.md, "Van arrival"):
##  - it is planned on every floor of several seeds and archetypes, deterministically, on flat floor of the start room;
##  - it overlaps no wall, prop, decor, package, gate, employee or note, leaves the corridors and the start cell open and
##    strands no walkable cell; its cells are blocked (monsters are not placed there);
##  - the crew's spots are walkable cells beside it, outside its blockers;
##  - in the game the arrival plays (crew hidden, control off), finishes in about 2.5 s, enables control, leaves the heroes
##    on walkable ground next to the van, and the van stays solid (blockers push heroes out) and unpriced;
##  - --no-van-intro parks it at once, skip() jumps to the end, tests default to no intro;
##  - the model is within its triangle budget and its door and lights respond.

const GAME := preload("res://scripts/app/game.gd")
const SEEDS: Array[int] = [1, 2, 3, 7, 42]
const MAX_TRIS := 12000

var _floors := 0
var _worst_dist := 0.0


func setup() -> void:
	timeout_sec = 180.0
	_check_plans()
	_check_model()
	await _check_arrival_in_game()
	await _check_skip_and_defaults()
	finish()


# --- planning -----------------------------------------------------------------------------------------------------------

func _check_plans() -> void:
	for id in ClientArchetype.IDS:
		for s in SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var catalog := ContractParts.prop_catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.generate(run.floor_seed(f))
				var plan := SiteBuilder.plan(map, run, f, catalog)
				_floors += 1
				_check_floor(map, plan, "%s seed %d floor %d" % [id, s, f])
	var run2 := ContractRun.make("guru", 3, 0.5)
	var map2 := DungeonGen.generate(run2.floor_seed(2))
	var cat2 := ContractParts.prop_catalog(run2.site_type)
	var a := SiteBuilder.plan(map2, run2, 2, cat2)
	var b := SiteBuilder.plan(map2, run2, 2, cat2)
	check(a.van == b.van and not a.van.is_empty(), "the van is deterministic per floor")
	print("van: planned on %d floors, farthest from the start cell %.1f units" % [_floors, _worst_dist])


func _check_floor(map: HexMap, p: SitePlan, tag: String) -> void:
	var van := p.van
	if not check(not van.is_empty(), tag + ": a van is planned"):
		return
	var pos: Vector2 = van["pos"]
	var yaw: float = van["yaw"]
	var w: float = van["w"]
	var d: float = van["d"]
	var base: int = int(p.base_levels[p.start_room])
	var corr := SiteBuilder._corridor_distance(map, 3)
	_worst_dist = maxf(_worst_dist, pos.distance_to(ThemeGeo.world(p.start)))
	check(str(van["room"]) == p.start_room, tag + ": it parks in the start room")
	# flat start-room floor under the whole body
	var bad := 0
	for pt in ThemeGeo.foot_points(pos, yaw, w, d):
		var cell := map.get_cell(ThemeGeo.cell_of(pt))
		if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != base or not (cell.tag == p.start_room or cell.tag == "start"):
			bad += 1
		if int(corr.get(ThemeGeo.cell_of(pt), 99)) < 1:     # never on a corridor cell (2+ cells clear except in a cramped room)
			bad += 1
	eq(bad, 0, tag + ": the body stands on flat start-room floor, clear of the corridors")
	# the cells it blocks
	var cells: Array = van["cells"]
	check(not cells.is_empty(), tag + ": it blocks cells")
	check(not cells.has(p.start), tag + ": the start cell stays open")
	for c: Vector2i in cells:
		check(p.blocked.has(c), tag + ": van cell %s is in plan.blocked" % str(c))
		check(map.get_cell(c) == null or map.get_cell(c).tag != "corridor", tag + ": no van cell is a corridor cell")
	# parking strands nothing
	var blocked := {}
	for c: Vector2i in cells:
		blocked[c] = true
	var before := VanPlan._reach(map, p.start, {})
	var after := VanPlan._reach(map, p.start, blocked)
	var stranded := 0
	for c: Vector2i in before:
		if not blocked.has(c) and not after.has(c):
			stranded += 1
	eq(stranded, 0, tag + ": the van strands no walkable cell")
	# overlaps
	for pr in p.props:
		var foot: Vector2 = pr["foot"]
		check(not ThemeGeo.overlap(pos, yaw, w, d, pr["pos"], float(pr["yaw"]), foot.x, foot.y, 0.0), tag + ": not on a priced prop")
	for dc in p.decor:
		if String(dc["place"]) == "ring":
			continue
		check(not ThemeGeo.overlap(pos, yaw, w, d, dc["pos"], float(dc["yaw"]), float(dc["w"]), float(dc["d"]), 0.0), tag + ": not on decor (%s)" % str(dc["kind"]))
	for pk in p.packages:
		var dims := PackageModels.size_of(str((pk["sizes"] as Array)[0]))
		check(not ThemeGeo.overlap(pos, yaw, w, d, pk["pos"], float(pk["yaw"]), dims.x, dims.z, 0.0), tag + ": not on a mail package")
	for g in p.gates:
		check(not ThemeGeo.overlap(pos, yaw, w, d, ThemeGeo.world(g["cell"]), 0.0, 3.0, 3.0, 0.0), tag + ": not on a hellgate")
	for e in p.employees:
		check(not ThemeGeo.overlap(pos, yaw, w, d, ThemeGeo.world(e["cell"]), 0.0, 1.0, 1.0, 0.0), tag + ": not on an employee")
	for nt in p.notes:
		check(not VanPlan.near(van, ThemeGeo.world(nt["cell"]), 0.9, 1.1, 0.0), tag + ": not on a clue note")
	# the crew's spots: floor cells, beside the van, outside its blockers
	var spots: Array = van["crew"]
	eq(spots.size(), 3, tag + ": three crew spots")
	var pts: Array = van["block_points"]
	var rad: float = van["block_radius"]
	for sp: Vector2 in spots:
		var cell := map.get_cell(ThemeGeo.cell_of(sp))
		check(cell != null and cell.type == HexMap.Tile.FLOOR and cell.level == base, tag + ": a crew spot is on flat floor")
		check(sp.distance_to(pos) < 4.2, tag + ": a crew spot is next to the van")
		for bp: Vector2 in pts:
			check(sp.distance_to(bp) >= rad + 0.4, tag + ": a crew spot is outside the blockers")
	# the door faces the crew line
	var n: Vector2 = van["door_normal"]
	for sp: Vector2 in spots:
		check((sp - pos).dot(n) > 1.0, tag + ": the crew stands on the door side")


# --- the model ----------------------------------------------------------------------------------------------------------

func _check_model() -> void:
	var van := VanModel.new()
	for part in ["Body", "Door", "Lamps", "InnerGlow", "Wheels"]:
		check(van.parts.has(part), "the van has a %s" % part)
	check(van.triangle_count() > 500 and van.triangle_count() < MAX_TRIS, "the van is within its triangle budget (%d)" % van.triangle_count())
	var closed := van.door.position
	van.set_door_open(1.0)
	check(van.door.position.z < closed.z - 1.0, "the sliding door slides toward the rear when opened")
	van.set_door_open(0.0)
	near(van.door.position.z, closed.z, 0.001, "and closes again")
	van.set_lights(1.0)
	check(float(van._lamp_mat.get_shader_parameter("glow_gain")) > 1.0, "the headlights glow when switched on")
	van.set_lights(0.0)
	near(float(van._lamp_mat.get_shader_parameter("glow_gain")), 0.0, 0.001, "and go dark")
	van.set_bounce(-0.1)
	near(van.chassis.position.y, -0.1, 0.0001, "the chassis rides on the suspension")
	var found_text := false
	for l in van.find_children("*", "Label3D", true, false):
		if (l as Label3D).text.contains("BUDGET SORCERY") or (l as Label3D).text.contains("SORCERY"):
			found_text = true
	check(found_text, "the van carries the company name")
	van.free()
	var circle := VanCircle.new(2.9)
	circle.settle()
	check(circle.floor_mesh.visible and not circle.column_mesh.visible, "the settled circle is just the chalk figure")
	circle.free()


# --- in the game --------------------------------------------------------------------------------------------------------

func _make_game(extra: Dictionary) -> Node3D:
	var g: Node3D = load("res://scripts/app/game.gd").new()
	var o := {"no_mic": true, "spells": "heal,corn", "contract": 1, "seed": 5}
	o.merge(extra, true)
	g.set("opts", o)
	GAME.reset_flow()
	return g


func _drop(g: Node3D) -> void:
	g.queue_free()
	await frames(3)
	GAME.reset_flow()


func _check_arrival_in_game() -> void:
	var g := _make_game({"van_intro": true})
	add_child(g)
	await frames(3)
	var arrival: VanArrival = g.get("_arrival")
	var player: Hero = g.get("player")
	var controller: PlayerController = g.get("controller")
	if not check(arrival != null, "the game plans and spawns the van"):
		await _drop(g)
		return
	check(arrival.is_running(), "the arrival is playing")
	check(not controller.enabled, "control waits while the van arrives")
	check(not player.visible, "the crew is inside the van at first")
	var finished_count := [0]
	arrival.finished.connect(func() -> void: finished_count[0] += 1)
	var landed := [false]
	arrival.landed.connect(func() -> void: landed[0] = true)
	var honked := [false]
	arrival.honked.connect(func() -> void: honked[0] = true)
	var site: SiteBuilder.Site = g.get("_site")
	var as_node: Node = arrival
	check(site.props.size() > 0 and not (as_node is Actor), "the van is not a priced prop (it is not an Actor and not in the site's props)")
	# the timeline
	await frames(int(VanArrival.T_POP * 60.0) - 6)
	check(not arrival.van.visible, "the van has not popped in yet")
	await frames(14)
	check(arrival.van.visible, "the van pops in at 0.8 s")
	await frames(int((VanArrival.T_LAND - VanArrival.T_POP) * 60.0))
	check(landed[0], "it lands on its suspension")
	await frames(int((VanArrival.T_DOOR1 - VanArrival.T_LAND) * 60.0) + 4)
	check(honked[0], "the horn hook fired")
	check(arrival.van.door_open_amount() > 0.95, "the side door slid open")
	check(not controller.enabled, "control is still off while the crew steps out")
	var guard := 0
	while not arrival.is_done() and guard < 260:
		guard += 1
		await frames(1)
	check(arrival.is_done() and not arrival.is_running(), "the arrival is over after about 2.5 s (t = %.2f)" % arrival.time)
	check(arrival.time < VanArrival.DURATION + 0.4, "and it finished on time")
	eq(finished_count[0], 1, "finished is emitted exactly once")
	check(controller.enabled, "control is back when the heroes are out")
	_check_crew_out(g, arrival)
	await frames(int((VanArrival.SETTLE_END - VanArrival.DURATION) * 60.0) + 6)
	check(arrival.settled, "the circle has settled into chalk")
	check(not arrival.circle.column_mesh.visible and not arrival.circle.shock_mesh.visible, "the column of light and the shock ring are gone")
	# the van is solid and unpriced
	var map: HexMap = g.get("map")
	var plan: SitePlan = site.plan
	eq(arrival.blockers.size(), (plan.van["block_points"] as Array).size(), "one blocker per blocker circle")
	var damages := Ledger.damages()
	for b in arrival.blockers:
		eq(b.apply_damage(500.0, player), 0.0, "the van takes no damage")
		check(b.is_inside_tree() and b.team == GameWorld.TEAM_NEUTRAL, "its blockers are neutral actors")
	eq(Ledger.damages(), damages, "no property damage")
	var pts: Array = plan.van["block_points"]
	var rad: float = plan.van["block_radius"]
	# walk Wick straight at the van's middle: the blockers push him out
	var centre: Vector2 = plan.van["pos"]
	var aim := Vector3(centre.x, 0.0, centre.y)
	player.global_position = Vector3(centre.x, 0.0, centre.y) + Vector3((plan.van["door_normal"] as Vector2).x, 0.0, (plan.van["door_normal"] as Vector2).y) * 2.6
	player.snap_to_ground()
	controller.enabled = false
	for i in 80:
		player.move((aim - player.global_position).normalized(), 1.0 / 60.0)
		await frames(1)
	var closest := 99.0
	for bp: Vector2 in pts:
		closest = minf(closest, Vector2(player.global_position.x, player.global_position.z).distance_to(bp))
	check(closest >= rad + player.radius - 0.2, "a hero cannot walk into the van (closest %.2f)" % closest)
	# nothing is placed on it: no monster on a van cell
	for m in site.monsters:
		check(not (plan.van["cells"] as Array).has(m.current_cell()), "no monster stands on the van")
	check(map != null, "map is there")
	await _drop(g)


func _check_crew_out(g: Node3D, arrival: VanArrival) -> void:
	var map: HexMap = g.get("map")
	var plan: SitePlan = (g.get("_site") as SiteBuilder.Site).plan
	var heroes: Array[Hero] = g.call("_heroes")
	var pts: Array = plan.van["block_points"]
	var rad: float = plan.van["block_radius"]
	var van_pos: Vector2 = plan.van["pos"]
	for h in heroes:
		check(h.visible, "%s stepped out" % h.display_name)
		var cell := map.get_cell(h.current_cell())
		check(cell != null and cell.type == HexMap.Tile.FLOOR, "%s stands on a walkable cell" % h.display_name)
		var p2 := Vector2(h.global_position.x, h.global_position.z)
		check(p2.distance_to(van_pos) < 4.2, "%s stands next to the van" % h.display_name)
		for bp: Vector2 in pts:
			check(p2.distance_to(bp) >= rad + h.radius - 0.1, "%s is outside the van's blockers" % h.display_name)
	var spots: Array = plan.van["crew"]
	for i in mini(heroes.size(), spots.size()):
		var expect: Vector2 = spots[0 if i == 0 else (2 if heroes[i].display_name == "Rebar" else 1)]
		var got := Vector2(heroes[i].global_position.x, heroes[i].global_position.z)
		var tol := 0.3 if heroes[i].display_name == "Wick" else 1.3     # the allies start walking to their formation slots at once
		check(got.distance_to(expect) < tol, "%s ended at the crew spot beside the door" % heroes[i].display_name)


func _check_skip_and_defaults() -> void:
	# --no-van-intro: parked at once, crew out, control on
	var g := _make_game({"no_van_intro": true})
	add_child(g)
	await frames(3)
	var arrival: VanArrival = g.get("_arrival")
	check(arrival != null and arrival.is_done() and not arrival.is_running(), "--no-van-intro parks the van at once")
	check(arrival != null and arrival.van.visible and arrival.van.door_open_amount() > 0.95, "the parked van stands there with its door open")
	check((g.get("controller") as PlayerController).enabled, "control is on at once")
	check((g.get("player") as Hero).visible, "the crew is out")
	_check_crew_out(g, arrival)
	await _drop(g)
	# tests default to no intro too
	g = _make_game({})
	add_child(g)
	await frames(3)
	arrival = g.get("_arrival")
	check(arrival != null and arrival.is_done(), "a test run skips the intro by default")
	await _drop(g)
	# skip() mid-arrival
	g = _make_game({"van_intro": true})
	add_child(g)
	await frames(30)
	arrival = g.get("_arrival")
	var controller: PlayerController = g.get("controller")
	check(arrival.is_running() and not controller.enabled, "mid-arrival: playing, no control")
	var fin := [0]
	arrival.finished.connect(func() -> void: fin[0] += 1)
	arrival.skip()
	await frames(2)
	check(arrival.is_done() and controller.enabled, "skip() ends the arrival and hands control back")
	eq(fin[0], 1, "skip emits finished once")
	arrival.skip()
	eq(fin[0], 1, "a second skip() does nothing")
	check(arrival.van.visible and arrival.settled, "the van is parked and the circle chalk after a skip")
	_check_crew_out(g, arrival)
	# a key press skips it too
	await _drop(g)
	g = _make_game({"van_intro": true})
	add_child(g)
	await frames(20)
	arrival = g.get("_arrival")
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.pressed = true
	g.call("_unhandled_input", ev)
	await frames(2)
	check(arrival.is_done() and (g.get("controller") as PlayerController).enabled, "any key press skips the arrival (never trap the player)")
	await _drop(g)

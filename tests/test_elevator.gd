extends TestCase
## The elevator built into the game (docs/design/elevator-options.md, "Built"; ElevatorGeo, ElevatorArrival):
##  - every job picks one of four styles (look service | fancy x placement wall | free) from its contract seed, the same on
##    every machine, and all four occur; every floor of a job uses the job's style (a wall job's floor with no wall slot
##    falls back to the free car of the same look, and says so);
##  - the elevator is reachable from the floor's start and its arrival room, its spots stand clear, and nothing else is
##    planned or spawned on it;
##  - collision follows the geometry: the notch's back wall and jambs, the free car's glass sides / railings; the doorway is
##    open;
##  - in the game, for all four styles: floor 1 has the elevator shut with the crew at the van; on floor 2 the crew arrives in
##    the car's front row, the doors open and it walks out (control comes back), E works at the door and in the car.

const R := 0.4
const DT := 1.0 / 60.0
const GAME := preload("res://scripts/app/game.gd")

var root: Node3D


func setup() -> void:
	timeout_sec = 280.0
	var seeds := _style_seeds()
	_check_style_pick()
	_check_generation(seeds)
	_check_collision(seeds)
	await _check_game(seeds)
	finish()


# --- the style pick ------------------------------------------------------------------------------------------------

## A contract seed (run_for_seed, the --seed of the dev flags) for each style whose floors 1-2 got that style without a
## fallback: "service_wall", "fancy_wall", "service_free", "fancy_free".
func _style_seeds() -> Dictionary:
	var out := {}
	for s in range(1, 200):
		var run := ContractBoard.run_for_seed(s)
		var key := "%s_%s" % [run.elevator_look, run.elevator_place]
		if out.has(key):
			continue
		var ok := true
		for f in [1, 2]:
			var m := DungeonGen.for_run(run, f)
			if bool(m.elevator.get("fallback", true)) or str(m.elevator.get("place", "")) != run.elevator_place:
				ok = false
		if ok:
			out[key] = s
		if out.size() == 4:
			break
	print("elevator: style seeds %s" % str(out))
	return out


func _check_style_pick() -> void:
	var counts := {}
	for s in range(1, 401):
		var a := ContractRun.make("prepper", s, 0.5)
		var b := ContractRun.make("supervillain", s, 0.9)
		eq([a.elevator_look, a.elevator_place], [b.elevator_look, b.elevator_place], "seed %d: the style depends on the contract seed only" % s)
		var key := "%s_%s" % [a.elevator_look, a.elevator_place]
		counts[key] = int(counts.get(key, 0)) + 1
	print("elevator: styles over 400 seeds %s" % str(counts))
	eq(counts.size(), 4, "all four styles occur")
	for key: String in counts:
		check(int(counts[key]) >= 60, "%s is common enough (%d of 400)" % [key, int(counts[key])])
	# the run's other rolls do not move: the style has its own generator
	var r1 := ContractRun.make("prepper", 77, 0.5)
	var r2 := ContractRun.make("prepper", 77, 0.5)
	eq(r1.elevator_place + r1.elevator_look, r2.elevator_place + r2.elevator_look, "the same seed, the same style")


# --- generation ----------------------------------------------------------------------------------------------------

func _check_generation(seeds: Dictionary) -> void:
	eq(seeds.size(), 4, "a seed with each style (no fallback) exists")
	var floors := 0
	var gen_ms := 0.0
	var walls := 0
	var fallbacks := 0
	var frees := 0
	for s in range(1, 41):
		var run := ContractBoard.run_for_seed(s)
		var catalog := PricedProp.catalog(run.site_type)
		for f in range(1, ContractRun.FLOOR_COUNT + 1):
			var tag := "seed %d floor %d (%s %s)" % [s, f, run.elevator_look, run.elevator_place]
			var t0 := Time.get_ticks_usec()
			var m := DungeonGen.for_run(run, f)
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			floors += 1
			gen_ms += ms
			var e := m.elevator
			if not check(not e.is_empty(), tag + ": the floor has an elevator"):
				continue
			var place := str(e["place"])
			if run.elevator_place == ElevatorGeo.PLACE_WALL:
				if place == ElevatorGeo.PLACE_WALL:
					walls += 1
				else:
					fallbacks += 1
					check(bool(e["fallback"]), tag + ": a wall job's free car is a marked fallback")
			else:
				frees += 1
				eq(place, ElevatorGeo.PLACE_FREE, tag + ": a free job gets the free car")
				check(not bool(e["fallback"]), tag + ": (not a fallback)")
			var p := SiteBuilder.plan(m, run, f, catalog)
			eq(str(p.elevator.get("look", "")), run.elevator_look, tag + ": the plan carries the job's look")
			eq(p.exit, e["landing"], tag + ": the exit cell is the elevator's landing")
			_check_floor(m, p, tag)
			check(ms < 1000.0, tag + ": generated in %.0f ms" % ms)
	print("elevator: %d floors: %d wall, %d wall->free fallbacks, %d free; generation avg %.0f ms" % [floors, walls, fallbacks, frees, gen_ms / maxi(1, floors)])
	check(gen_ms / maxi(1, floors) < 250.0, "generating a floor stays quick (avg %.0f ms)" % (gen_ms / maxi(1, floors)))
	check(walls > 0 and frees > 0, "both placements were generated")
	check(fallbacks * 3 <= walls, "a wall job falls back to the free car rarely (%d of %d)" % [fallbacks, walls + fallbacks])
	# determinism (every machine builds the same elevator) and the same style on every floor of a job
	for key: String in seeds:
		var run := ContractBoard.run_for_seed(int(seeds[key]))
		for f in range(1, ContractRun.FLOOR_COUNT + 1):
			var a := DungeonGen.for_run(run, f)
			var b := DungeonGen.for_run(run, f)
			eq(NetFloor.map_text_of(a), NetFloor.map_text_of(b), "%s floor %d: the same map, elevator and solids every time" % [key, f])
			if not bool(a.elevator["fallback"]):
				eq(str(a.elevator["place"]), run.elevator_place, "%s floor %d: the job's placement" % [key, f])


## One floor: reachable, the spots clear, nothing planned on the elevator.
func _check_floor(m: HexMap, p: SitePlan, tag: String) -> void:
	var e := p.elevator
	var landing: Vector2i = e["landing"]
	check(m.is_walkable_cell(landing), tag + ": the landing is full floor")
	check(not m.find_path(p.start, landing, false).is_empty(), tag + ": the elevator is reachable from the start without climbing")
	# the arrival: from the landing the crew reaches the rest of its room (and the start)
	check(not m.find_path(landing, p.start, false).is_empty(), tag + ": the start is reachable from the elevator")
	var room_cells: Array = p.rooms[p.exit_room]
	var far := landing
	for c: Vector2i in room_cells:
		if m.is_walkable_cell(c) and m.get_cell(c).level == int(e["level"]) and Hex.distance(c, landing) > Hex.distance(far, landing):
			far = c
	check(not m.find_path(landing, far, false).is_empty(), tag + ": the arrival room opens out from the landing")
	if p.floor_number > SiteBuilder.VAN_FLOOR:
		eq(SiteBuilder.arrival_room(p), p.exit_room, tag + ": the crew arrives in the elevator's room")
	var place := str(e["place"])
	if place == ElevatorGeo.PLACE_WALL:
		for c: Vector2i in (e["cells"] as Array):
			check(m.is_half(c), tag + ": a car cell %s is cut by the car's back wall" % str(c))
		var ms: Array = e["mouth"]
		check(m.is_walkable_cell(ms[1]) and m.is_walkable_cell(ms[2]), tag + ": the doorway is full floor")
		# camera-facing: 15 or 45 degrees off the iso camera
		var off := rad_to_deg((e["out"] as Vector2).angle_to(ThemeGeo.CAMERA_DIR))
		check(absf(off) <= 45.5, tag + ": the doors face the camera (%.0f deg off)" % off)
		# nothing walkable behind or beside the car
		for c: Vector2i in (e["cells"] as Array):
			for x in Hex.range_cells(c, 2):
				var cell := m.get_cell(x)
				if cell != null and cell.type != HexMap.Tile.WALL:
					check(cell.tag == "exit" or cell.tag == p.exit_room, tag + ": only the elevator's room within 2 of the car (%s is %s)" % [str(x), cell.tag])
	else:
		for c: Vector2i in (e["cells"] as Array):
			check(not m.is_walkable_cell(c) and m.no_stand.has(c), tag + ": the car's cell %s is no standing spot" % str(c))
			check(m.get_cell(c).tag == p.exit_room, tag + ": the car's cell %s belongs to its room" % str(c))
		for c in Hex.ring((e["cells"] as Array)[0], 2):
			check(m.is_walkable_cell(c), tag + ": the walk round the car is open at %s" % str(c))
	for q: Vector2 in (e["inside"] as Array):
		check(ElevatorGeo.inside(e, q), tag + ": an arrival spot is in the car")
		check(not m.blocks_point(Vector3(q.x, 0.0, q.y), R), tag + ": an arrival spot is clear")
	for q: Vector2 in (e["steps"] as Array):
		check(not m.blocks_point(Vector3(q.x, 0.0, q.y), R), tag + ": a step-out spot is clear")
		var sc := m.get_cell(ThemeGeo.cell_of(q))
		check(sc != null and sc.level == int(e["level"]), tag + ": a step-out spot is on the elevator's floor")
	for q: Vector2 in (e["via"] as Array):
		check(not m.blocks_point(Vector3(q.x, 0.0, q.y), R - 0.05), tag + ": the doorway is clear")
	# nothing planned on it
	var keep := {}
	for c in ElevatorGeo.keep_cells(e):
		keep[c] = true
		check(p.blocked.has(c), tag + ": monsters are kept off %s" % str(c))
	for list: Array in [p.gates, p.employees, p.notes, p.props, p.packages]:
		for it: Dictionary in list:
			check(not keep.has(it["cell"]), tag + ": nothing stands on the elevator (%s)" % str(it["cell"]))
	var body := _body(e)
	for dc in p.decor:
		check(not ThemeGeo.overlap(dc["pos"], float(dc["yaw"]), float(dc["w"]), float(dc["d"]), body[0], body[1], body[2], body[3]),
			tag + ": decor %s keeps off the elevator" % dc["kind"])
	for pr in p.props:
		var foot: Vector2 = pr["foot"]
		check(not ThemeGeo.overlap(pr["pos"], float(pr["yaw"]), foot.x, foot.y, body[0], body[1], body[2], body[3]), tag + ": a priced prop keeps off the elevator")
	if not p.van.is_empty():
		check(not ThemeGeo.overlap(p.van["pos"], float(p.van["yaw"]), float(p.van["w"]), float(p.van["d"]), body[0], body[1], body[2], body[3]), tag + ": the van keeps off it")


## The elevator's footprint as (pos, yaw, w, d).
func _body(e: Dictionary) -> Array:
	if str(e["place"]) == ElevatorGeo.PLACE_WALL:
		return [ElevatorGeo.to_world(e, Vector2(0.0, -0.7)), float(e["yaw"]), 2.0 * ElevatorGeo.JAMB_OUT, 1.8]
	return [e["pos"], float(e["yaw"]), 2.0 * ElevatorGeo.SHAFT_R, 2.0 * ElevatorGeo.SHAFT_R]


# --- collision -----------------------------------------------------------------------------------------------------

func _world(m: HexMap) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(m, root, 3)


func _actor(pos: Vector3) -> Actor:
	var a := Actor.new()
	a.team = GameWorld.TEAM_HEROES
	a.radius = R
	GameWorld.spawn(a, pos)
	a.snap_to_ground()
	return a


## Walk an actor at local `from` in direction `dir` (local) for `n` frames; returns its final local position.
func _walk(m: HexMap, e: Dictionary, from: Vector2, dir: Vector2, n: int = 150) -> Vector2:
	var w := ElevatorGeo.to_world(e, from)
	var a := _actor(Vector3(w.x, float(e["level"]) * Hex.LEVEL_HEIGHT, w.y))
	var d := ElevatorGeo.to_world(e, from + dir) - w
	for i in n:
		a.move(Vector3(d.x, 0.0, d.y).normalized(), DT)
		check(not m.blocks_point(a.global_position, R - 0.01), "the body never overlaps a wall or a solid")
	var out := ElevatorGeo.to_local(e, Vector2(a.global_position.x, a.global_position.z))
	a.free()
	return out


func _check_collision(seeds: Dictionary) -> void:
	for key: String in ["service_wall", "fancy_free"]:
		if not seeds.has(key):
			continue
		var run := ContractBoard.run_for_seed(int(seeds[key]))
		var m := DungeonGen.for_run(run, 1)
		var e := m.elevator
		_world(m)
		if str(e["place"]) == ElevatorGeo.PLACE_WALL:
			var back := _walk(m, e, Vector2(0.0, -0.6), Vector2(0.0, -1.0))
			near(back.y, -ElevatorGeo.CAR_DEPTH + R, 0.03, "wall: the car's back wall stops a body walking in")
			var side := _walk(m, e, Vector2(0.0, -0.75), Vector2(1.0, 0.0))
			near(side.x, ElevatorGeo.JAMB_IN - R, 0.03, "wall: the jamb stops a body walking along the car")
			var side2 := _walk(m, e, Vector2(0.0, -0.75), Vector2(-1.0, 0.0))
			near(side2.x, -ElevatorGeo.JAMB_IN + R, 0.03, "wall: the other jamb too")
			# from the room, aimed at the sliver beside the car: the jamb holds the body off it
			var sliver := _walk(m, e, Vector2(2.3, 1.6), Vector2(0.0, -1.0))
			check(sliver.y >= ElevatorGeo.JAMB_FRONT + R - 0.03, "wall: the sliver beside the car is blocked (stopped at z %.2f)" % sliver.y)
			# and the doorway is open: in from the landing, all the way to the back
			var walk_in := _walk(m, e, Vector2(0.0, 1.5), Vector2(0.0, -1.0), 120)
			check(walk_in.y < -0.9 and ElevatorGeo.inside(e, ElevatorGeo.to_world(e, walk_in)), "wall: the crew walks in through the doorway (z %.2f)" % walk_in.y)
		else:
			# into a glass side from outside (the back, the left), out through one from inside: stopped at the side
			for ang: float in [180.0, 240.0, 120.0]:
				var dir := Vector2(sin(deg_to_rad(ang)), cos(deg_to_rad(ang)))
				var outside := _walk(m, e, dir * 3.2, -dir)
				check(outside.dot(dir) >= ElevatorGeo.SHAFT_APOTHEM + ElevatorGeo.FACE_HALF_T + R - 0.03,
					"free: a side stops a body from outside (%.0f deg: %.2f)" % [ang, outside.dot(dir)])
				var inner := _walk(m, e, Vector2.ZERO, dir)
				check(inner.dot(dir) <= ElevatorGeo.SHAFT_APOTHEM - ElevatorGeo.FACE_HALF_T - R + 0.03,
					"free: a side stops a body from inside (%.0f deg: %.2f)" % [ang, inner.dot(dir)])
			var walk_out := _walk(m, e, Vector2(0.0, 0.3), Vector2(0.0, 1.0), 120)
			check(walk_out.y > 2.5, "free: the door side is open: out onto the landing (z %.2f)" % walk_out.y)
			var walk_in := _walk(m, e, Vector2(0.0, 3.0), Vector2(0.0, -1.0), 120)
			check(ElevatorGeo.inside(e, ElevatorGeo.to_world(e, walk_in)), "free: and back in (z %.2f)" % walk_in.y)
			# pathing goes round the car, never through it
			var c0: Vector2i = (e["cells"] as Array)[0]
			var behind := c0 - ((e["landing"] as Vector2i) - c0)
			var path := m.find_path(e["landing"], behind, false)
			check(not path.is_empty(), "free: a path leads round the car")
			for c in path:
				check(not (e["cells"] as Array).has(c), "free: the path keeps off the car's cells")
	if root != null:
		root.free()
		root = null


# --- in the game ---------------------------------------------------------------------------------------------------

func _check_game(seeds: Dictionary) -> void:
	for key: String in ["service_wall", "fancy_wall", "service_free", "fancy_free"]:
		if not seeds.has(key):
			continue
		await _check_floor1(key, int(seeds[key]))
		await _check_arrival(key, int(seeds[key]))


func _make_game(extra: Dictionary) -> Node3D:
	var g: Node3D = GAME.new()
	var o := {"no_mic": true, "spells": "heal,corn"}
	o.merge(extra, true)
	g.set("opts", o)
	GAME.reset_flow()
	add_child(g)
	return g


func _drop(g: Node3D) -> void:
	g.queue_free()
	await frames(3)
	GAME.reset_flow()


func _check_floor1(key: String, s: int) -> void:
	var g := _make_game({"seed": s})
	await frames(6)
	var lift: ElevatorArrival = g.get("_lift")
	var tag := "%s (seed %d) floor 1" % [key, s]
	if not check(lift != null, tag + ": the elevator is built"):
		await _drop(g)
		return
	var site: SiteBuilder.Site = g.get("_site")
	eq(str(lift.plan["look"]) + "_" + str(lift.plan["place"]), key, tag + ": in the job's style")
	check(lift.is_done() and lift.crew.is_empty(), tag + ": nobody arrives by elevator on floor 1")
	near(lift.door_open_amount(), 0.0, 0.001, tag + ": its doors are shut")
	check(bool(g.call("_has_van")), tag + ": the crew is at the van")
	var player: Hero = g.get("player")
	check(Hex.distance(player.current_cell(), site.plan.exit) > 4, tag + ": far from the elevator")
	# the crew walks up: the doors open; E at the door opens the menu
	var e: Dictionary = site.plan.elevator
	var door: Vector2 = e["door"]
	var out: Vector2 = e["out"]
	var spot := door + out * 0.9
	player.global_position = Vector3(spot.x, float(e["level"]) * Hex.LEVEL_HEIGHT, spot.y)
	await frames(50)
	check(lift.door_open_amount() > 0.99, tag + ": the doors open for a hero at them")
	check(bool(g.call("_player_at_elevator")), tag + ": E targets the elevator at its door")
	var t: Object = g.call("use_target")
	check(t != null and t.kind == "elevator", tag + ": the use target is the elevator")
	# the crew walks off (back to the van): they shut again
	var away := Hex.to_world(site.plan.start, float(GameWorld.map.get_cell(site.plan.start).level))
	for h: Hero in g.call("_heroes"):
		h.global_position = away
	await frames(150)
	near(lift.door_open_amount(), 0.0, 0.001, tag + ": they shut again once the crew has gone")
	await _drop(g)


func _check_arrival(key: String, s: int) -> void:
	var g := _make_game({"seed": s, "floor": 2, "van_intro": true})
	await frames(2)
	var tag := "%s (seed %d) floor 2" % [key, s]
	var lift: ElevatorArrival = g.get("_lift")
	if not check(lift != null and lift.is_running(), tag + ": the crew arrives by elevator"):
		await _drop(g)
		return
	var e := lift.plan
	var heroes: Array[Hero] = g.call("_heroes")
	var controller: PlayerController = g.get("controller")
	check(not controller.enabled, tag + ": no control while the crew steps out")
	check(g.get("_arrival") == null, tag + ": no van")
	for h in heroes:
		check(ElevatorGeo.inside(e, Vector2(h.global_position.x, h.global_position.z)), tag + ": %s starts in the car" % h.display_name)
	# the front row: three spots across the car, nobody at the back
	near(lift.door_open_amount(), 0.0, 0.05, tag + ": the doors start shut")
	await frames(40)
	check(lift.door_open_amount() > 0.3, tag + ": the doors open")
	await frames(110)
	check(lift.is_done() and controller.enabled, tag + ": the crew is out and in control after ~2 s")
	var player: Hero = g.get("player")
	eq(player.current_cell(), e["landing"], tag + ": Wick on the landing")
	for h in heroes:
		check(not ElevatorGeo.inside(e, Vector2(h.global_position.x, h.global_position.z)), tag + ": %s stepped out" % h.display_name)
		check(not GameWorld.map.blocks_point(h.global_position, h.radius - 0.02), tag + ": %s stands clear" % h.display_name)
	eq(_prompt(g), "E Elevator", tag + ": E Elevator at the landing")
	check(lift.door_open_amount() > 0.99, tag + ": the doors stay open while the crew is there")
	# E in the car opens the menu
	var inside: Vector2 = (e["inside"] as Array)[0]
	player.global_position = Vector3(inside.x, player.global_position.y, inside.y)
	await frames(4)
	check(bool(g.call("_player_at_elevator")), tag + ": E works in the car")
	controller.press_use()
	await frames(2)
	var menu: ElevatorMenu = g.get("_menu")
	if check(menu != null, tag + ": E opens the elevator menu"):
		check(menu.can_descend(), tag + ": floor 2 can go down")
		menu.stay.emit()
		await frames(3)
	await _drop(g)
	# skippable: a key press jumps to the end
	var g2 := _make_game({"seed": s, "floor": 3, "van_intro": true})
	await frames(4)
	var lift2: ElevatorArrival = g2.get("_lift")
	if check(lift2 != null and lift2.is_running(), tag + ": floor 3 arrives by elevator too"):
		var ev := InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.pressed = true
		g2.call("_unhandled_input", ev)
		await frames(2)
		check(lift2.is_done() and (g2.get("controller") as PlayerController).enabled, tag + ": any key skips the arrival")
		eq((g2.get("player") as Hero).current_cell(), lift2.plan["landing"], tag + ": and the crew is out")
	await _drop(g2)


func _prompt(g: Node) -> String:
	var p: UsePrompt = g.get("_use_prompt")
	return "" if p == null or not p.wanted else "%s %s" % [p.key, p.verb]

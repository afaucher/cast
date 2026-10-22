extends MonsterTestBase
## Lava caves in the generator (docs/design/lava-playtest.md, "As built: caves on real floors"; LavaSite, CaveGen, LavaPlanner):
##   - PLACEMENT over contract seeds 1-SEEDS, floors 1-3: a cave only on a supervillain's floors 2-3, or on floor 2 of any other
##     client but the founder WITH a hellgate in it (its far chamber: "next to hellgates"); never the founder's;
##   - every cave, natural or forced (--lava-floor, LavaSite.force) over FORCED seeds:
##       2-3 chambers at one level, never the start or the elevator's room; every chamber reached from the start without
##       climbing on the TWO-WIDE bridges alone (the one-wide spans taken out); every row of a two-wide bridge two wide and its
##       bridgehead rows three wide; the lava four levels or more under all the rock beside it; no office door on its doorways;
##       its archers on its isles; the look hellfire exactly when a hellgate stands in it;
##       every ISLE: no walk reaches it, and a min-power damp at its shore makes a crust (LavaField's own rule, on the activated
##       map) that a climb-free path crosses onto it;
##   - all four patterns (causeway, fork, ring, gauntlet) come out of the forced runs;
##   - a shared run builds the same cave (the record in the map checksum); a floor whose cave did not fit is byte for byte the
##     floor without the option;
##   - timing: the cave pass and a cave floor's generation stay within test_dungeon_gen's budget (a failed cave attempt is built
##     again without it, so its worst case is two attempts).

const SEEDS := 60
const FORCED := 24
const PASS_BUDGET_MS := 150.0     ## (about 70 ms measured on an idle machine; 100+ while other test runs load it)
const FLOOR_BUDGET_MS := 600.0     ## test_dungeon_gen's 300 ms a floor, twice: the cave attempt and, if it fails, the plain one

var _probe: Node = null
var _worst_gen := 0.0
var _worst_tag := ""
var _worst_pass := 0.0
var _patterns := {}
var _isles := 0


func setup() -> void:
	timeout_sec = 900.0
	Monster.use_proto_visuals = true
	_probe = Node.new()
	var caves := 0
	var villain := 0
	var gate := 0
	var eligible := 0
	var natural: Array[String] = []
	for s in range(1, SEEDS + 1):
		var run := ContractBoard.run_for_seed(s)
		for f in range(1, 4):
			var t0 := Time.get_ticks_usec()
			var map := DungeonGen.for_run(run, f)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var rolled := LavaSite.seed_for(run, f, false) != 0 and SewerCluster.seed_for(run, f, false) == 0   # (a cluster floor keeps its cluster)
			if rolled:
				eligible += 1
			if map.cave.is_empty():
				if rolled:
					_check_unchanged(run, f, map)
				continue
			caves += 1
			var tag := "seed %d floor %d (%s)" % [s, f, run.archetype_id]
			if ms > _worst_gen:
				_worst_gen = ms
				_worst_tag = tag
			check(rolled, "%s: a cave only where the floor rolled one" % tag)
			check(run.archetype_id != "founder", "%s: never the founder's" % tag)
			var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			if run.archetype_id == LavaSite.VILLAIN:
				villain += 1
				check(f >= 2, "%s: a villain's cave on floors 2-3" % tag)
			else:
				gate += 1
				check(f == 2, "%s: a hellgate cave on floor 2" % tag)
				check(_gate_in(plan, map.cave["rooms"]), "%s: a hellgate in the cave (%s)" % [tag, str(plan.gates.map(func(g: Dictionary) -> String: return str(g["room"])))])
				check(_gate_in(plan, [map.cave["far"]]), "%s: ... in its far chamber" % tag)
			if natural.size() < 10:
				natural.append("%d/%d %s %s %s" % [s, f, run.archetype_id, map.cave["pattern"], map.cave.get("look", "")])
			_check_cave(run, f, map, plan, tag)
			_check_shared(run, f, tag)
			if caves == 1:
				_check_drawing(map, tag)
	print("[lava gen] %d caves on %d rolled floors of %d seeds (%d villain, %d hellgate); natural: %s" % [caves, eligible, SEEDS, villain, gate, str(natural)])
	check(caves >= 3, "some floors get a cave naturally (%d)" % caves)
	check(villain >= 1 and gate >= 1, "both kinds come out (%d villain, %d hellgate)" % [villain, gate])
	_check_forced()
	print("[lava gen] patterns %s, %d isles; worst cave floor %.0f ms (%s), worst cave pass %.1f ms" % [str(_patterns), _isles, _worst_gen, _worst_tag, _worst_pass])
	for p in LavaSite.PATTERNS:
		check(int(_patterns.get(p, 0)) >= 1, "the %s pattern comes out (%d)" % [p, int(_patterns.get(p, 0))])
	check(_worst_pass < PASS_BUDGET_MS, "the cave pass is cheap (worst %.1f ms)" % _worst_pass)
	check(_worst_gen < FLOOR_BUDGET_MS, "a cave floor generates in time (worst %.0f ms)" % _worst_gen)
	Monster.use_proto_visuals = false
	_probe.free()
	finish()


## The lava as drawn (LavaLook.dress_cave, and the damp's crust): every pattern shader hashes its lattice points from their
## integers. A sine hash (fract(sin(dot(p, k)) * 43758.5)) of a point tens of metres from the origin turns one rounding step
## of its argument into another value, so the same feature point came out in two places either side of a lattice line and
## the lava's plates were cut along it (user playtest 2026-10-21: "texture creases in the lava"). The shaders can't run
## headless; this reads their code.
func _check_drawing(map: HexMap, tag: String) -> void:
	var holder := Node3D.new()
	var look := LavaLook.dress_cave(holder, map, LavaPlanner.look_row(map))
	var mats: Array[ShaderMaterial] = [LavaLook.crust_material()]
	for n in look.find_children("*", "GeometryInstance3D", true, false):
		if (n as GeometryInstance3D).material_override is ShaderMaterial:
			mats.append((n as GeometryInstance3D).material_override as ShaderMaterial)
	check(mats.size() >= 2, "%s: the lava is drawn with its pattern shader (%d shaders)" % [tag, mats.size()])
	var sine := RegEx.create_from_string("fract\\s*\\(\\s*sin\\s*\\(")
	for m in mats:
		var code := m.shader.code
		var name := code.get_slice("\n", 2).strip_edges()
		check(sine.search(code) == null, "%s: no sine hash in the lava's patterns (%s)" % [tag, name])
		check(not code.contains("h22") or code.contains("uvec2"), "%s: its h22 is an integer hash (%s)" % [tag, name])
	holder.free()


func _gate_in(plan: SitePlan, rooms: Array) -> bool:
	for g in plan.gates:
		if rooms.has(str(g["room"])):
			return true
	return false


## --lava-floor: a cave on floor 2 (and 3) of most seeds, whatever the site.
func _check_forced() -> void:
	LavaSite.force = true
	var got := 0
	for s in range(1, FORCED + 1):
		var run := ContractBoard.run_for_seed(s)
		for f in [2, 3]:
			var t0 := Time.get_ticks_usec()
			var map := DungeonGen.for_run(run, f)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if map.cave.is_empty():
				continue
			got += 1
			var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			var tag := "forced seed %d floor %d" % [s, f]
			if f == 2:
				check(_gate_in(plan, [map.cave["far"]]), "%s: a forced cave on a floor of small gates holds one" % tag)
			_check_cave(run, f, map, plan, tag)
	LavaSite.force = false
	check(got >= FORCED, "--lava-floor forces a cave on most floors (%d of %d)" % [got, FORCED * 2])


## The cave's rules on one planned floor (see the header).
func _check_cave(run: ContractRun, f: int, map: HexMap, plan: SitePlan, tag: String) -> void:
	var rec: Dictionary = map.cave
	_patterns[rec["pattern"]] = int(_patterns.get(rec["pattern"], 0)) + 1
	_worst_pass = maxf(_worst_pass, CaveGen.last_usec / 1000.0)
	var rooms: Array = rec["rooms"]
	var lv := int(rec["level"])
	check(rooms.size() >= LavaSite.MIN_ROOMS and rooms.size() <= LavaSite.MAX_ROOMS, "%s: 2-3 chambers (%d)" % [tag, rooms.size()])
	check(not rooms.has(plan.start_room) and not rooms.has(plan.exit_room), "%s: never the start or the elevator's room" % tag)
	for t: String in rooms:
		eq(int(plan.base_levels.get(t, -99)), lv, "%s: %s stands at the cave's level" % [tag, t])
		eq(plan.theme_of(t), LavaPlanner.THEME, "%s: %s is a lava room" % [tag, t])
	eq(str(rec["look"]), "hellfire" if _gate_in(plan, rooms) else "magma", "%s: the look follows the gate" % tag)
	# the lava under every rock beside it
	var low := true
	for c: Vector2i in (rec["lava"] as Array):
		var cell := map.get_cell(c)
		low = low and cell != null and cell.level == lv - CaveGen.BED_DROP
		for nn in Hex.neighbors(c):
			var n := map.get_cell(nn)
			if n != null and not map.lava.has(nn) and n.type != HexMap.Tile.WALL:
				low = low and n.level - cell.level >= 4
	check(low, "%s: the lava lies four levels or more under every rock beside it" % tag)
	# two wide, three at the heads
	var span_cells := {}
	for br: Dictionary in rec["bridges"]:
		var rows: Array = br["rows"]
		if int(br["w"]) == 1:
			for row: Array in rows:
				for c: Vector2i in row:
					span_cells[c] = true
			continue
		var thin := 0
		for row: Array in rows:
			var ok := 0
			for c: Vector2i in row:
				ok += 1 if map.has_cell(c) and map.get_cell(c).wall_mask == 0 else 0
			if ok < 2:
				thin += 1
		eq(thin, 0, "%s: every row of the %s-%s bridge is two wide" % [tag, br["a"], br["b"]])
		var heads: Array = br["heads"]
		check(heads.size() >= 4, "%s: the %s-%s bridge has its bridgehead rows (%d)" % [tag, br["a"], br["b"], heads.size()])
		for h: int in heads:
			check((rows[h] as Array).size() >= 3, "%s: bridgehead row %d of %s-%s is three wide" % [tag, h, br["a"], br["b"]])
	# every chamber from the start on the two-wide bridges, without climbing
	var wide := HexMap.new()
	for c: Vector2i in map.cells:
		if span_cells.has(c) and not str(map.cells[c].tag).begins_with("room:"):
			continue
		var src: HexMap.Cell = map.cells[c]
		var cell := wide.set_cell(c, src.level, src.type)
		cell.wall_mask = src.wall_mask
		cell.wall_top = src.wall_top
		cell.stair_dir = src.stair_dir
		cell.stair_rise = src.stair_rise
	for ch: Dictionary in rec["chambers"]:
		check(not wide.find_path(plan.start, ch["center"], false, 20000).is_empty(), "%s: %s is reached on the two-wide bridges, no climbing" % [tag, ch["room"]])
	# no door on its doorways
	for d in plan.doors:
		check(not rooms.has(str(d["room"])), "%s: no office door on the cave's doorway %d" % [tag, int(d["id"])])
	# isles: none walked to, every one crust-reachable (LavaField's own rule)
	var isles: Array = rec["isles"]
	check(not isles.is_empty(), "%s: an archer isle" % tag)
	_isles += isles.size()
	for isle: Dictionary in isles:
		var cc: Vector2i = isle["center"]
		check(map.find_path(plan.start, cc, true, 20000).is_empty(), "%s: no walk reaches the isle at %s" % [tag, cc])
	for a: Vector2i in (rec.get("archers", []) as Array):
		check(map.get_cell(a) != null and map.get_cell(a).tag == "isle", "%s: archer at %s on an isle" % [tag, a])
	_check_crust_reach(map, tag)


## On the activated map: a min-power damp's crust at each isle's shore lets a climb-free walk onto the isle.
func _check_crust_reach(src: HexMap, tag: String) -> void:
	var rec: Dictionary = src.cave
	for isle: Dictionary in rec["isles"]:
		var map := _clone(src)
		var f := LavaField.new()
		_probe.add_child(f)
		f.setup(map)
		f.activate()
		var shore: Vector2i = isle["shore"]
		f.add_source(Hex.to_world(shore, float(map.get_cell(shore).level)), CaveGen.crust_reach(), 0.0)
		f._update(0.1)
		var path := map.find_path(shore, isle["center"], false, 20000)
		check(not path.is_empty(), "%s: a damp at the shore %s crusts a way onto the isle at %s (%d crust cells)" % [tag, shore, isle["center"], f._cell_end.size()])
		f.free()


func _clone(src: HexMap) -> HexMap:
	var m := HexMap.new()
	for c: Vector2i in src.cells:
		var s: HexMap.Cell = src.cells[c]
		var cell := m.set_cell(c, s.level, s.type)
		cell.tag = s.tag
		cell.wall_mask = s.wall_mask
		cell.wall_top = s.wall_top
		cell.stair_dir = s.stair_dir
		cell.stair_rise = s.stair_rise
	m.midpoint_walls = src.midpoint_walls
	m.lava = src.lava.duplicate()
	m.cave = src.cave
	return m


func _check_shared(run: ContractRun, f: int, tag: String) -> void:
	var shared := DungeonGen.for_run(run, f, true)
	var solo := DungeonGen.for_run(run, f)
	eq(NetFloor.map_text_of(shared), NetFloor.map_text_of(solo), "%s: a shared run's floor is the solo floor" % tag)
	check(NetFloor.map_text_of(shared).contains("\ncave="), "%s: the cave's record is in the map checksum" % tag)


## A floor that rolled a cave that did not fit is the floor without the option (its sewer cluster, if it rolled one).
func _check_unchanged(run: ContractRun, f: int, map: HexMap) -> void:
	var params := {"elevator": run.elevator_place}
	var sewer := SewerCluster.seed_for(run, f, false)
	if sewer != 0:
		params["sewer"] = sewer
	var ref := DungeonGen.generate(run.floor_seed(f), params)
	eq(NetFloor.map_text_of(map), NetFloor.map_text_of(ref), "seed %d floor %d: without its cave the floor is unchanged" % [run.seed, f])

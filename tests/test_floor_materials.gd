extends TestCase
## Floor and wall materials per room theme (FloorMaterials, docs/design/environment.md "Materials"):
##  - every room theme maps to a floor material, every material has a table entry and a shader pattern;
##  - SiteBuilder.plan() writes Cell.mat_id for EVERY cell of a generated floor: room cells from their theme, corridors
##    from the site type, walls from the room (luxury themes) or the site;
##  - the same seed gives the same materials, and writing them is cheap;
##  - HexMapView turns them into one draw call per surface as before (the material shader on the floor tops and wall
##    faces) and stays on the classic shader when nothing was assigned (menu garage, labs).

const SEEDS: Array[int] = [1, 2, 7, 42]

var _floors := 0
var _cells := 0
var _assign_ms := 0.0
var _worst_assign_ms := 0.0
var _seen: Dictionary = {}   ## floor id -> true, over every generated floor


func setup() -> void:
	timeout_sec = 120.0
	_check_tables()
	for id in ClientArchetype.IDS:
		for s in SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var catalog := PricedProp.catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.generate(run.floor_seed(f))
				var plan := SiteBuilder.plan(map, run, f, catalog)
				_check_floor(map, run, f, plan)
				_check_deterministic(map, run, f, catalog)
	_check_perf()
	await _check_view()
	print("floor materials: %d floors, %d cells; %d distinct floor materials seen; assign %.2f ms avg, %.2f ms worst" % [
			_floors, _cells, _seen.size(), _assign_ms / float(maxi(_floors, 1)), _worst_assign_ms])
	finish()


# --- tables -------------------------------------------------------------------------------------------------------------

func _check_tables() -> void:
	check(RoomThemeDefs.THEMES.size() >= 13, "the room theme table is there")
	for theme: String in RoomThemeDefs.THEMES:
		check(RoomThemeDefs.theme(theme).has("floor_mat"), "theme %s has a floor material" % theme)
		var fid := FloorMaterials.floor_for_theme(theme)
		check(fid > 0 and fid < FloorMaterials.FLOORS.size(), "theme %s: floor id %d is a real material (not the classic slate)" % [theme, fid])
		var wid := FloorMaterials.wall_for_theme(theme, str((RoomThemeDefs.THEMES[theme] as Dictionary)["site"]).replace("any", "bunker"))
		check(wid > 0 and wid < FloorMaterials.WALLS.size(), "theme %s: wall id %d is a real material" % [theme, wid])
	eq(FloorMaterials.floor_for_theme(""), FloorMaterials.F_SLATE, "no theme: the classic slate")
	eq(FloorMaterials.floor_for_theme("no_such_theme"), FloorMaterials.F_SLATE, "an unknown theme: the classic slate")
	eq(FloorMaterials.wall_for_theme("home_cinema", "bunker"), FloorMaterials.W_PANELLING, "the cinema is panelled")
	eq(FloorMaterials.wall_for_theme("wine_cellar", "bunker"), FloorMaterials.W_PANELLING, "the wine cellar is panelled")
	eq(FloorMaterials.wall_for_theme("throne_room", "lair"), FloorMaterials.W_MARBLE, "the throne room is marble")
	eq(FloorMaterials.wall_for_theme("gym", "bunker"), FloorMaterials.W_CONCRETE, "a bunker room without its own walls is poured concrete")
	eq(FloorMaterials.wall_for_theme("barracks", "lair"), FloorMaterials.W_STONE, "a lair room without its own walls is rough stone")
	check(FloorMaterials.corridor_floor("bunker") != FloorMaterials.corridor_floor("lair"), "bunker and lair corridors differ")
	for site: String in ["bunker", "lair"]:
		check(FloorMaterials.floor_for_theme("service_entrance") != FloorMaterials.corridor_floor(site), "%s: the service entrance is not the corridor look" % site)
	# the packing round-trips
	for fid in FloorMaterials.FLOORS.size():
		for wid in FloorMaterials.WALLS.size():
			var m := FloorMaterials.pack(fid, wid)
			check(FloorMaterials.floor_of(m) == fid and FloorMaterials.wall_of(m) == wid, "pack(%d, %d) round-trips" % [fid, wid])
	# the shader tables: a pattern for every material, colours in range
	var t := FloorMaterials.table_arrays()
	var base: PackedVector4Array = t["base"]
	var alt: PackedVector4Array = t["alt"]
	eq(base.size(), FloorMaterials.TABLE_SIZE, "the shader table has its fixed size")
	eq(alt.size(), FloorMaterials.TABLE_SIZE, "the alt table has its fixed size")
	for fid in range(1, FloorMaterials.FLOORS.size()):
		check(int(base[fid].w) > 0, "floor material %d (%s) has a pattern" % [fid, FloorMaterials.floor_name(fid)])
		check(alt[fid].w > 0.0, "floor material %d has a pattern scale" % fid)
		check(FloorMaterials.seam_gain(fid) > 0.0, "floor material %d keeps some seam glow" % fid)
	for wid in range(1, FloorMaterials.WALLS.size()):
		check(int(base[FloorMaterials.WALL_OFFSET + wid].w) >= 20, "wall material %d (%s) has a wall pattern" % [wid, FloorMaterials.wall_name(wid)])
	check(FloorMaterials.seam_gain(FloorMaterials.F_CARPET) < FloorMaterials.seam_gain(FloorMaterials.F_TILE), "carpet dims the seams, tile keeps them")
	check(FloorMaterials.seam_gain(FloorMaterials.F_DIAMOND) >= 0.99, "diamond plate keeps the seams bright")
	check(FloorMaterials.FLOORS[0]["pat"] == FloorMaterials.Pat.NONE, "id 0 is the classic slate (the texture path)")


# --- generated floors ---------------------------------------------------------------------------------------------------

func _check_floor(map: HexMap, run: ContractRun, f: int, plan: SitePlan) -> void:
	var tag := "%s s%d f%d" % [run.archetype_id, run.seed, f]
	_floors += 1
	_assign_ms += float(FloorMaterials.last_usec) / 1000.0
	_worst_assign_ms = maxf(_worst_assign_ms, float(FloorMaterials.last_usec) / 1000.0)
	var corr_floor := FloorMaterials.corridor_floor(run.site_type)
	var site_wall := FloorMaterials.corridor_wall(run.site_type)
	var unset := 0
	var bad_room := 0
	var bad_corr := 0
	var bad_wall := 0
	var corridors := 0
	# A planned door re-floors the cells around its doorway (DoorFloors option "c"): the tread-plate threshold on the door
	# line, the room's floor on the room side, the corridor's on the hall side, whichever tag the cell has.
	var at_door := {}
	for rec: Dictionary in plan.doors:
		var mid: Vector3 = rec["center"]
		for c2 in Hex.range_cells(rec["cell"], DoorFloors.REACH) + Hex.range_cells(Hex.from_world(mid), DoorFloors.REACH):
			at_door[c2] = rec
	var thresholds := 0
	var bad_door := 0
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		_cells += 1
		var fid := FloorMaterials.floor_of(cell.mat_id)
		var wid := FloorMaterials.wall_of(cell.mat_id)
		if cell.type == HexMap.Tile.WALL:
			if wid != site_wall:
				bad_wall += 1
			continue
		if fid == 0 or wid == 0:
			unset += 1    # mat_id is written for every walkable (and every cut) cell
			continue
		_seen[fid] = true
		if at_door.has(c):
			var rec: Dictionary = at_door[c]
			var own := corr_floor if cell.tag == "corridor" else FloorMaterials.floor_for_theme(String(plan.room_themes.get(cell.tag, "")))
			if fid == DoorFloors.THRESHOLD:
				thresholds += 1
			elif fid != own and fid != corr_floor and fid != FloorMaterials.floor_for_theme(String(plan.room_themes.get(str(rec["room"]), ""))):
				bad_door += 1
			if cell.tag == "corridor":
				corridors += 1
			continue
		if cell.tag == "corridor":
			corridors += 1
			if fid != corr_floor or wid != site_wall:
				bad_corr += 1
		elif plan.rooms.has(cell.tag):
			var theme := String(plan.room_themes.get(cell.tag, ""))
			if fid != FloorMaterials.floor_for_theme(theme) or wid != FloorMaterials.wall_for_theme(theme, run.site_type):
				bad_room += 1
	check(unset == 0, "%s: %d floor cells have no material" % [tag, unset])
	check(bad_room == 0, "%s: %d room cells do not carry their theme's material" % [tag, bad_room])
	check(bad_corr == 0, "%s: %d corridor cells are not the site's corridor material" % [tag, bad_corr])
	check(bad_wall == 0, "%s: %d wall cells are not the site's wall" % [tag, bad_wall])
	check(bad_door == 0, "%s: %d cells at a door are neither the threshold nor a floor of its room or hall" % [tag, bad_door])
	check(plan.doors.is_empty() or thresholds >= plan.doors.size(), "%s: every door has its tread-plate threshold (%d cells, %d doors)" % [tag, thresholds, plan.doors.size()])
	check(corridors > 0, "%s: the floor has corridors to check" % tag)
	# the start and exit cells take their room's material; stairs and every walkable cell have one
	for key: String in ["start", "exit"]:
		for c in map.cells_with_tag(key):
			var room := plan.start_room if key == "start" else plan.exit_room
			var theme := String(plan.room_themes.get(room, ""))
			eq(FloorMaterials.floor_of(map.cells[c].mat_id), FloorMaterials.floor_for_theme(theme), "%s: the %s cell has its room's floor" % [tag, key])
	for tg: String in plan.rooms:
		check(plan.room_themes.has(tg), "%s: %s has a theme to take a material from" % [tag, tg])


func _check_deterministic(map: HexMap, run: ContractRun, f: int, catalog: Array[String]) -> void:
	var again := DungeonGen.generate(run.floor_seed(f))
	SiteBuilder.plan(again, run, f, catalog)
	var same := map.cells.size() == again.cells.size()
	if same:
		for c: Vector2i in map.cells:
			if not again.cells.has(c) or again.cells[c].mat_id != map.cells[c].mat_id:
				same = false
				break
	check(same, "%s s%d f%d: the same seed gives the same materials" % [run.archetype_id, run.seed, f])
	# planning twice on the same map is stable too (the game plans once, tests plan again)
	SiteBuilder.plan(map, run, f, catalog)
	var stable := true
	for c: Vector2i in map.cells:
		if again.cells[c].mat_id != map.cells[c].mat_id:
			stable = false
			break
	check(stable, "%s s%d f%d: planning a map again keeps its materials" % [run.archetype_id, run.seed, f])


func _check_perf() -> void:
	var avg := _assign_ms / float(maxi(_floors, 1))
	check(avg < 10.0, "writing the materials is a cheap pass: %.2f ms on average" % avg)
	# a map nobody assigned stays the classic slate
	var plain := DungeonGen.generate(5)
	for c: Vector2i in plain.cells:
		if plain.cells[c].mat_id != 0:
			check(false, "a generated map has no materials until it is planned")
			break


# --- the view -------------------------------------------------------------------------------------------------------------

func _check_view() -> void:
	var run := ContractRun.make(ClientArchetype.IDS[0], 42, 0.4)
	var map := DungeonGen.generate(run.floor_seed(1))
	SiteBuilder.plan(map, run, 1, PricedProp.catalog(run.site_type))
	var view := HexMapView.new()
	add_child(view)
	view.build(map)
	await get_tree().process_frame
	var mesh: ArrayMesh = view.mesh_instance.mesh
	var mat_shader := 0
	var max_mat := 0.0
	for s in mesh.get_surface_count():
		var sm := mesh.surface_get_material(s) as ShaderMaterial
		check(sm != null, "surface %d has a shader material" % s)
		if sm != null and sm.shader.code.contains("m_base"):
			mat_shader += 1
			var arr := mesh.surface_get_arrays(s)
			for uv: Vector2 in (arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array):
				max_mat = maxf(max_mat, uv.y)
	check(mat_shader >= 2, "the floor tops and the wall faces use the material shader (%d surfaces)" % mat_shader)
	check(max_mat >= 1.0, "the vertices carry their material ids (largest %.0f)" % max_mat)
	# the same map without materials: classic shader, the same number of surfaces (one draw call each). (The same planned
	# terrain, its materials cleared: planning also carves the pool rooms' pools, which are terrain, not materials.)
	var classic_map := DungeonGen.generate(run.floor_seed(1))
	SiteBuilder.plan(classic_map, run, 1, PricedProp.catalog(run.site_type))
	for c: Vector2i in classic_map.cells:
		classic_map.cells[c].mat_id = 0
	var classic := HexMapView.new()
	add_child(classic)
	classic.build(classic_map)
	var classic_mesh: ArrayMesh = classic.mesh_instance.mesh
	for s in classic_mesh.get_surface_count():
		check(not (classic_mesh.surface_get_material(s) as ShaderMaterial).shader.code.contains("m_base"), "an unassigned map keeps the classic terrain shader")
	eq(int(view.stats["surfaces"]), int(classic.stats["surfaces"]), "materials add no draw calls")
	eq(int(view.stats["triangles"]), int(classic.stats["triangles"]), "materials add no triangles")
	view.queue_free()
	classic.queue_free()

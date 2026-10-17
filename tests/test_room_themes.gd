extends TestCase
## Room themes + logical set dressing (docs/design/environment.md, "Decisions (2026-10-17)"):
##  - every room of every floor gets a theme from the site's pool; the start room is the service entrance; the
##    origin room (floor 3) gets the theme the story names (mapping table); deterministic per seed;
##  - orientation: every wall-backed prop (priced AND decor) faces away from its nearest wall, corner props face
##    the room centre, centrepieces face the door, vignette seats face their table / screen / rack / desk / pool
##    within 15 degrees, clear lane in front of facing props, jitter at most 10 degrees;
##  - nothing on doors, corridors, the start, the exit, gates; stands on flat floor; room stays connected;
##  - the priced-prop cap is still 6; decor stays inside the per-room budget and out of the central fighting area;
##  - each theme's vignette places (in a synthetic room), placement is fast, the spawned nodes match the plan.

const SEEDS: Array[int] = [1, 2, 3, 7, 42]
const GATE_KINDS: Array[String] = ["summoning_circle", "candle", "moat_water", "shark_fin"]   ## drawn around a hellgate on purpose
const MAX_YAW_JITTER := 10.0
const SIGNATURE := {
	"wine_cellar": "tasting", "home_cinema": "cinema", "spa": "circle", "gym": "bench_rack", "server_room": "racks",
	"panic_room": "desk", "pool": "pool", "torture_chamber": "cage", "throne_room": "carpet", "lab": "shelf",
	"barracks": "bunks", "moat": "moat",
}

var _plans := 0
var _worst_wall_dot := 1.0
var _worst_seat_angle := 0.0
var _worst_corner_angle := 0.0
var _ops_ok: Dictionary = {}
var _ops_n: Dictionary = {}
var _theme_ms := 0.0
var _plan_ms := 0.0
var _worst_plan_ms := 0.0


func setup() -> void:
	timeout_sec = 120.0
	_check_tables()
	_check_priced_table()
	for id in ClientArchetype.IDS:
		for s in SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var catalog := ContractParts.prop_catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.generate(run.floor_seed(f))
				var plan := SiteBuilder.plan(map, run, f, catalog)
				_plans += 1
				_theme_ms += float(SiteBuilder.last_theme_usec) / 1000.0
				_plan_ms += float(SiteBuilder.last_plan_usec) / 1000.0
				_worst_plan_ms = maxf(_worst_plan_ms, float(SiteBuilder.last_plan_usec) / 1000.0)
				_check_floor(map, run, f, plan, catalog)
	_check_determinism()
	_check_fallback_map()
	_check_vignettes_place()
	_check_vignette_structure()
	_check_perf()
	_check_op_rates()
	await _check_spawn()
	await _check_models_and_anim()
	print("themes: %d floors; worst wall dot %.2f, worst seat angle %.1f deg, worst corner angle %.1f deg; plan %.1f ms (themes %.1f ms) avg, %.1f ms worst" % [
			_plans, _worst_wall_dot, _worst_seat_angle, _worst_corner_angle, _plan_ms / float(_plans), _theme_ms / float(_plans), _worst_plan_ms])
	finish()


# --- tables -------------------------------------------------------------------------------------------------------------

func _check_tables() -> void:
	var bunker := RoomThemeDefs.pool("bunker")
	var lair := RoomThemeDefs.pool("lair")
	eq(bunker.size(), 7, "bunker pool: wine cellar, home cinema, spa, gym, server room, panic room, pool")
	eq(lair.size(), 5, "lair pool: torture chamber, throne room, lab, barracks, moat")
	for id: String in bunker + lair + [RoomThemeDefs.SERVICE]:
		var def := RoomThemeDefs.theme(id)
		check(not def.is_empty(), "theme %s is defined" % id)
		if def.is_empty():
			continue
		check(String(def["name"]) != "", "%s has a name" % id)
		var light: Dictionary = def["light"]
		check(light.has("color") and float(light["energy"]) > 0.0, "%s has an accent light" % id)
		var site: String = def["site"]
		for k: String in (def["priced"] as Array):
			check(PricedProp.is_kind(k), "%s prefers a real priced prop (%s)" % [id, k])
			if site != "any":
				eq(String((PricedProp.TABLE[k] as Dictionary)["site"]), site, "%s: %s belongs to the %s site" % [id, k, site])
		for op: Dictionary in (def["recipe"] as Array):
			check(String(op["op"]) != "", "%s recipe op has a name" % id)
	# every decor kind has a rule and a model; every rule is a known one
	var places := ["wall", "corner", "center", "floor", "group", "ring"]
	var orients := ["away_from_wall", "face_center", "face_entrance", "face_start", "face_target", "parallel", "free"]
	for kind: String in RoomThemeDefs.DECOR:
		var m := RoomThemeDefs.decor(kind)
		check(places.has(String(m["place"])), "%s has a placement rule" % kind)
		check(orients.has(String(m["orient"])), "%s has an orientation rule" % kind)
		check(float(m["w"]) > 0.0 and float(m["d"]) > 0.0 and float(m["weight"]) > 0.0, "%s has a footprint and a weight" % kind)
		var node := DecorModels.build(kind, {"radius": 2.0, "length": 4.0, "text": "OM", "color": Color.RED})
		var body := node.get_node_or_null("Body") as MeshInstance3D
		check(body != null and body.mesh != null and body.mesh.get_surface_count() > 0, "%s builds a mesh" % kind)
		node.free()
	# the story origins: every origin a client can roll names a theme of that client's site
	for aid in ClientArchetype.IDS:
		var d := ClientArchetype.get_data(aid)
		var site_type: String = d["site"]
		for ev: Dictionary in (d["events"] as Array):
			var origin: String = ev["origin"]
			check(RoomThemeDefs.ORIGIN_THEMES.has(origin), "origin '%s' is in the mapping table" % origin)
			var t := RoomThemeDefs.origin_theme(site_type, origin)
			check(RoomThemeDefs.pool(site_type).has(t), "origin '%s' -> %s is in the %s pool" % [origin, t, site_type])
			eq(t, String(RoomThemeDefs.ORIGIN_THEMES.get(origin, "")), "origin '%s' maps through the table" % origin)
	eq(RoomThemeDefs.origin_theme("bunker", "yoga studio"), "spa", "yoga studio -> spa")
	eq(RoomThemeDefs.origin_theme("lair", "vat room"), "lab", "vat room -> lab")
	eq(RoomThemeDefs.origin_theme("bunker", "the wine room"), "wine_cellar", "an unlisted origin falls back to a keyword")
	check(RoomThemeDefs.pool("lair").has(RoomThemeDefs.origin_theme("lair", "nonsense")), "an unknown origin still names a pool theme")


func _check_priced_table() -> void:
	for k: String in PricedProp.TABLE:
		var pl := PricedProp.placement(k)
		check(["wall", "corner"].has(String(pl["place"])), "%s: priced props stand against a wall or in a corner" % k)
		check(["away_from_wall", "face_center", "face_entrance"].has(String(pl["orient"])), "%s has an orientation rule" % k)
		var foot: Vector2 = pl["foot"]
		check(foot.x > 0.3 and foot.y > 0.3, "%s has a footprint" % k)
	check(PricedProp.catalog("bunker").size() <= 10 and PricedProp.catalog("lair").size() <= 10, "catalogs stay at most 10")
	check(PricedProp.is_kind("treadmill") and PropModels.height("treadmill") > 1.0, "the gym's priced treadmill exists")


# --- one floor ------------------------------------------------------------------------------------------------------------

func _check_floor(map: HexMap, run: ContractRun, f: int, plan: SitePlan, catalog: Array[String]) -> void:
	var tag := "%s/%d floor %d" % [run.archetype_id, run.seed, f]
	var pool := RoomThemeDefs.pool(run.site_type)
	# --- every room has a theme
	eq(plan.room_themes.size(), plan.rooms.size(), "%s: a theme for every room" % tag)
	for rt: String in plan.rooms:
		var th := plan.theme_of(rt)
		check(th != "", "%s: %s has a theme" % [tag, rt])
		if rt == plan.start_room:
			eq(th, RoomThemeDefs.SERVICE, "%s: the start room is the service entrance" % tag)
		else:
			check(pool.has(th), "%s: %s theme %s is in the %s pool" % [tag, rt, th, run.site_type])
	# --- the origin room gets the story's theme
	if f == int(run.story["origin_floor"]) and plan.origin_room != "":
		eq(plan.theme_of(plan.origin_room), RoomThemeDefs.origin_theme(run.site_type, str(run.story["origin"])),
				"%s: the origin room (%s) gets the story's theme (%s)" % [tag, plan.origin_room, run.story["origin"]])
		check(plan.rooms_with_theme(plan.theme_of(plan.origin_room)).has(plan.origin_room), "%s: rooms_with_theme finds the origin room" % tag)
	# --- priced props: still at most 6, themed, standing back to the wall
	check(plan.props.size() <= 6 and SiteBuilder.MAX_PROPS == 6, "%s: at most 6 priced props (%d)" % [tag, plan.props.size()])
	for pr in plan.props:
		var kind: String = pr["kind"]
		var preferred := RoomThemes.priced_kinds(plan.theme_of(str(pr["room"])), catalog)
		if not preferred.is_empty():
			check(preferred.has(kind), "%s: %s in a %s room is one of its props" % [tag, kind, plan.theme_of(str(pr["room"]))])
		check(pr.has("pos") and pr.has("yaw") and pr.has("place") and pr.has("orient"), "%s: priced prop %s carries pos/yaw/rule" % [tag, kind])
	var placements: Array[Dictionary] = []
	for pr in plan.props:
		var e: Dictionary = pr.duplicate()
		e["priced"] = true
		e["lane"] = true
		e["w"] = (pr["foot"] as Vector2).x
		e["d"] = (pr["foot"] as Vector2).y
		placements.append(e)
	for dc in plan.decor:
		placements.append(dc)
	_check_placements(map, plan, tag, placements)
	_check_density(map, plan, tag)
	check(plan.lights.size() <= plan.rooms.size(), "%s: at most one accent light per room" % tag)
	var light_rooms := {}
	for l in plan.lights:
		check(not light_rooms.has(l["room"]), "%s: one light in %s" % [tag, l["room"]])
		light_rooms[l["room"]] = true
	for rt: String in plan.rooms:
		check(plan.entrances.has(rt), "%s: %s has an entrance" % [tag, rt])
	for r in plan.decor_report:
		if bool(r["skipped"]):
			continue
		var key := "%s/%s" % [r["theme"], r["op"]]
		_ops_n[key] = int(_ops_n.get(key, 0)) + 1
		if bool(r["ok"]):
			_ops_ok[key] = int(_ops_ok.get(key, 0)) + 1


## Orientation, flat floor, clear of doors / corridors / start / exit / gates / employees, a clear lane.
func _check_placements(map: HexMap, plan: SitePlan, tag: String, placements: Array[Dictionary]) -> void:
	var corridors: Array[Vector2i] = []
	for c: Vector2i in map.cells:
		if map.cells[c].tag == "corridor":
			corridors.append(c)
	for e in placements:
		var kind: String = e["kind"]
		var pos: Vector2 = e["pos"]
		var yaw: float = e["yaw"]
		var f := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
		var cell := Hex.from_world(Vector3(pos.x, 0.0, pos.y))
		var label := "%s: %s at %s" % [tag, kind, cell]
		# on flat floor of its own room
		var cc: HexMap.Cell = map.get_cell(cell)
		check(cc != null and cc.type == HexMap.Tile.FLOOR, "%s stands on floor" % label)
		check(cc != null and cc.level == int(plan.base_levels.get(str(e["room"]), -1)), "%s stands on the room's flat level" % label)
		check(plan.room_of_cell(cell) == str(e["room"]), "%s is in its room" % label)
		# never on a door, corridor, the start or the exit
		check(Hex.distance(cell, plan.start) > SiteBuilder.START_CLEAR, "%s keeps off the start" % label)
		check(Hex.distance(cell, plan.exit) > SiteBuilder.EXIT_CLEAR, "%s keeps off the exit" % label)
		var near := 99
		for cor in corridors:
			near = mini(near, Hex.distance(cell, cor))
		check(near > SiteBuilder.CORRIDOR_CLEAR, "%s keeps off the doors and corridors (%d)" % [label, near])
		for g in plan.gates:
			if not GATE_KINDS.has(kind):
				check(Hex.distance(cell, g["cell"]) > 3, "%s keeps clear of the hellgate" % label)
		for em in plan.employees:
			var ew := Hex.to_world(em["cell"])
			check(Vector2(ew.x - pos.x, ew.z - pos.y).length() > 0.7, "%s keeps off an employee" % label)
		# orientation
		var place := String(e["place"])
		match place:
			"wall":
				var m := _wall_face(map, pos)
				check(m != Vector2.ZERO, "%s (wall rule) has a wall next to it" % label)
				if m != Vector2.ZERO:
					var dot := f.dot(m)
					_worst_wall_dot = minf(_worst_wall_dot, dot)
					check(dot >= ThemeCtx.MIN_ALIGN - 0.01, "%s is back to the wall, facing into the room (facing . wall-face-normal = %.2f)" % [label, dot])
					check(dot > 0.0, "%s does not face its nearest wall" % label)
			"corner":
				var to_center := ThemeGeo.world(plan.centers[str(e["room"])]) - pos
				var ang := rad_to_deg(absf(f.angle_to(to_center)))
				_worst_corner_angle = maxf(_worst_corner_angle, ang)
				check(ang <= MAX_YAW_JITTER + 2.0, "%s (corner) faces the room centre (%.1f deg off)" % [label, ang])
			"center":
				if String(e["orient"]) == "face_entrance":
					var to_door: Vector2 = (plan.entrances[str(e["room"])] as Vector2) - pos
					var ang2 := rad_to_deg(absf(f.angle_to(to_door)))
					check(ang2 <= MAX_YAW_JITTER + 2.0, "%s (centrepiece) faces the door (%.1f deg off)" % [label, ang2])
		if bool(e.get("lane", false)):
			_check_lane(map, plan, label, e, placements)
		if e.has("target"):
			var target: Vector2 = e["target"]
			var ang3 := rad_to_deg(absf(f.angle_to(target - pos)))
			_worst_seat_angle = maxf(_worst_seat_angle, ang3)
			check(ang3 <= 15.0, "%s faces what it belongs to (%.1f deg off)" % [label, ang3])
		if String(e["orient"]) == "face_start":
			var to_start := Vector2(Hex.to_world(plan.start).x, Hex.to_world(plan.start).z) - pos
			check(rad_to_deg(absf(f.angle_to(to_start))) <= 15.0, "%s faces the start" % label)
	# vignette groups: members share a group id, chairs / seats have a target
	var groups: Dictionary = {}
	for dc in plan.decor:
		if int(dc["group"]) >= 0:
			if not groups.has(dc["group"]):
				groups[dc["group"]] = [] as Array[Dictionary]
			(groups[dc["group"]] as Array[Dictionary]).append(dc)
	for gid in groups:
		var members: Array[Dictionary] = groups[gid]
		var room_of_group := str(members[0]["room"])
		for mem in members:
			eq(str(mem["room"]), room_of_group, "%s: a vignette stays in one room" % tag)
			if String(mem["role"]) == "seat":
				check(mem.has("target"), "%s: every seat has something it faces" % tag)
		var screen_n := 0
		var seat_n := 0
		var table_n := 0
		for mem in members:
			match String(mem["role"]):
				"screen": screen_n += 1
				"seat": seat_n += 1
				"table": table_n += 1
		if screen_n > 0:
			eq(screen_n, 1, "%s: one screen per cinema" % tag)
			check(seat_n >= 3, "%s: the cinema has %d seats" % [tag, seat_n])
		if table_n > 0:
			check(seat_n >= 3, "%s: a table has chairs (%d)" % [tag, seat_n])


## The unit normal of the face of the wall cell nearest to p (pointing from the wall toward p), computed
## straight from the hex geometry.
func _wall_face(map: HexMap, p: Vector2) -> Vector2:
	var c0 := Hex.from_world(Vector3(p.x, 0.0, p.y))
	var best := INF
	var best_n := Vector2.ZERO
	for c in Hex.range_cells(c0, 2):
		var cell: HexMap.Cell = map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.WALL:
			continue
		var w := Hex.to_world(c)
		var rel := p - Vector2(w.x, w.z)
		var m := -INF
		var mn := Vector2.ZERO
		for d in 6:
			var nv := Hex.dir_vector(d)
			var n2 := Vector2(nv.x, nv.z)
			var proj := rel.dot(n2)
			if proj > m:
				m = proj
				mn = n2
		var dist := m - Hex.INNER
		if dist < best:
			best = dist
			best_n = mn
	return best_n


## A facing wall / corner / centre piece keeps a clear hex in front: walkable flat floor, nothing in it.
func _check_lane(map: HexMap, plan: SitePlan, label: String, e: Dictionary, all: Array[Dictionary]) -> void:
	var pos: Vector2 = e["pos"]
	var yaw: float = e["yaw"]
	var d: float = e["d"]
	var f := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
	var lane := pos + f * (d * 0.5 + 0.95)
	var lc := Hex.from_world(Vector3(lane.x, 0.0, lane.y))
	var cell: HexMap.Cell = map.get_cell(lc)
	check(cell != null and cell.type == HexMap.Tile.FLOOR and cell.level == int(plan.base_levels.get(str(e["room"]), -1)), "%s has flat floor in front of it" % label)
	for o in all:
		if o == e or not (bool(o.get("blocks", false)) or bool(o.get("priced", false))):
			continue
		if int(e.get("group", -1)) >= 0 and int(o.get("group", -2)) == int(e["group"]):
			continue
		var op: Vector2 = o["pos"]
		var ow: float = o["w"]
		var od: float = o["d"]
		# nothing solid inside the lane circle (radius 0.45 around its centre): compare to the other piece's circle
		var r_o := minf(ow, od) * 0.5
		check(op.distance_to(lane) > 0.45 + r_o * 0.55, "%s keeps a clear lane in front (%s at %.2f)" % [label, o["kind"], op.distance_to(lane)])


## Decor stays inside the budget, blockers inside theirs, the middle of the room stays free, and the room stays connected.
func _check_density(map: HexMap, plan: SitePlan, tag: String) -> void:
	var per_room: Dictionary = {}
	for dc in plan.decor:
		var rt: String = dc["room"]
		if not per_room.has(rt):
			per_room[rt] = {"weight": 0.0, "free_weight": 0.0, "blockers": 0.0, "n": 0}
		var d: Dictionary = per_room[rt]
		var w: float = RoomThemeDefs.decor(str(dc["kind"]))["weight"]
		d["weight"] = float(d["weight"]) + w
		if not (String(dc["role"]) in ["candle", "fin", "moat", "carpet", "monitor"]):
			d["free_weight"] = float(d["free_weight"]) + w
		if bool(dc["blocks"]):
			d["blockers"] = float(d["blockers"]) + (0.5 if String(dc["kind"]) == "barrel" else 1.0)
		d["n"] = int(d["n"]) + 1
		# the central fighting area stays clear of blocking pieces (a centrepiece table is the one exception)
		if bool(dc["blocks"]) and String(dc["role"]) != "table":
			var cw := ThemeGeo.world(plan.centers[rt])
			check((dc["pos"] as Vector2).distance_to(cw) >= ThemeCtx.CENTER_CLEAR - 0.01, "%s: %s keeps out of the middle of %s" % [tag, dc["kind"], rt])
	for rt: String in per_room:
		var cells := (plan.rooms[rt] as Array).size()
		var budget := clampf(floorf(float(cells) / ThemeCtx.CELLS_PER_DECOR), ThemeCtx.MIN_BUDGET, ThemeCtx.MAX_BUDGET)
		var d2: Dictionary = per_room[rt]
		check(float(d2["free_weight"]) <= budget + 0.001, "%s: %s decor weight %.1f within the budget %.0f" % [tag, rt, d2["free_weight"], budget])
		check(float(d2["weight"]) <= budget + 3.0, "%s: %s decor weight %.1f stays near the budget %.0f" % [tag, rt, d2["weight"], budget])
		var block_budget := clampi(cells / ThemeCtx.CELLS_PER_BLOCKER, 2, ThemeCtx.MAX_BLOCKERS)
		check(float(d2["blockers"]) <= float(block_budget) + 0.001, "%s: %s has %.1f blocking pieces, budget %d" % [tag, rt, d2["blockers"], block_budget])
		check(int(d2["n"]) <= 40, "%s: %s holds %d decor pieces" % [tag, rt, d2["n"]])
	# connectivity: with every blocking piece (decor and priced) solid, each room's floor is still one piece
	var solid: Dictionary = {}
	for dc in plan.decor:
		if bool(dc["blocks"]):
			for bp: Vector2 in (dc["block_points"] as Array):
				for c in Hex.range_cells(Hex.from_world(Vector3(bp.x, 0.0, bp.y)), 1):
					if _hex_dist(bp, c) < float(dc["block_radius"]) + 0.1:
						solid[c] = true
	for pr in plan.props:
		var pp: Vector2 = pr["pos"]
		for c in Hex.range_cells(Hex.from_world(Vector3(pp.x, 0.0, pp.y)), 1):
			if _hex_dist(pp, c) < float((PricedProp.TABLE[pr["kind"]] as Dictionary)["radius"]) + 0.1:
				solid[c] = true
	for rt: String in plan.rooms:
		var cells_in: Array[Vector2i] = plan.rooms[rt]
		var set := {}
		for c in cells_in:
			set[c] = true
		var start := Vector2i.ZERO
		var found := false
		for c in cells_in:
			if not solid.has(c) and map.cells[c].type == HexMap.Tile.FLOOR and map.is_walkable_cell(c):
				start = c
				found = true
				break
		if not found:
			continue
		var base_seen := _flood(map, set, start, {})
		var seen := _flood(map, set, start, solid)
		var expect := 0
		for c in base_seen:
			if not solid.has(c):
				expect += 1
		check(seen.size() >= expect - 2, "%s: %s stays connected around its props (%d of %d cells)" % [tag, rt, seen.size(), expect])


func _flood(map: HexMap, set: Dictionary, start: Vector2i, solid: Dictionary) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if seen.has(nb) or not set.has(nb) or solid.has(nb) or not map.is_walkable_cell(nb):
				continue   # (full cells: a cut cell's center is on the wall line, routes go through full floor)
			var a: HexMap.Cell = map.cells[c]
			var b: HexMap.Cell = map.cells[nb]
			if a.type != HexMap.Tile.FLOOR or b.type != HexMap.Tile.FLOOR or absi(a.level - b.level) > 1:
				continue
			seen[nb] = true
			queue.append(nb)
	return seen


func _hex_dist(p: Vector2, c: Vector2i) -> float:
	var w := Hex.to_world(c)
	var rel := p - Vector2(w.x, w.z)
	var m := -INF
	for d in 6:
		var nv := Hex.dir_vector(d)
		m = maxf(m, rel.dot(Vector2(nv.x, nv.z)))
	return m - Hex.INNER


# --- determinism ----------------------------------------------------------------------------------------------------------

func _dump(p: SitePlan) -> String:
	return str([p.room_themes, p.props, p.decor, p.lights, p.entrances])


func _check_determinism() -> void:
	for id in ["supervillain", "guru"]:
		var run := ContractRun.make(id, 31, 0.7)
		var catalog := ContractParts.prop_catalog(run.site_type)
		for f in range(1, 4):
			var a := SiteBuilder.plan(DungeonGen.generate(run.floor_seed(f)), run, f, catalog)
			var b := SiteBuilder.plan(DungeonGen.generate(run.floor_seed(f)), run, f, catalog)
			eq(_dump(a), _dump(b), "%s floor %d: themes and set dressing are deterministic" % [id, f])
		var other := ContractRun.make(id, 32, 0.7)
		var pa := SiteBuilder.plan(DungeonGen.generate(run.floor_seed(2)), run, 2, catalog)
		var pb := SiteBuilder.plan(DungeonGen.generate(other.floor_seed(2)), other, 2, catalog)
		check(_dump(pa) != _dump(pb), "%s: a different seed dresses differently" % id)
	# variety: over a few floors a site type uses more than one theme order
	var seen := {}
	for s in SEEDS:
		var run2 := ContractRun.make("prepper", s, 0.5)
		var p := SiteBuilder.plan(DungeonGen.generate(run2.floor_seed(1)), run2, 1, ContractParts.prop_catalog("bunker"))
		for th in p.room_themes.values():
			seen[th] = true
	check(seen.size() >= 6, "floors use a good spread of the bunker themes (%d)" % seen.size())


## The always-valid fallback map (one room, start and exit in it) still plans without trouble.
func _check_fallback_map() -> void:
	var run := ContractRun.make("prepper", 5, 0.5)
	var map := DungeonGen._fallback()
	var plan := SiteBuilder.plan(map, run, 1, ContractParts.prop_catalog("bunker"))
	eq(plan.room_themes.size(), plan.rooms.size(), "the fallback map's room has a theme")
	for rt: String in plan.rooms:
		check(plan.theme_of(rt) != "", "%s has a theme on the fallback map" % rt)
	# a plan with nothing in it (no rooms) does not crash either
	var empty_map := HexMap.new()
	empty_map.set_cell(Vector2i.ZERO, 0)
	var empty_plan := SiteBuilder.plan(empty_map, run, 1, ContractParts.prop_catalog("bunker"))
	eq(empty_plan.room_themes.size(), 0, "no rooms, no themes")


# --- each theme's vignette places (synthetic rooms) -----------------------------------------------------------------------

## A start room (radius 5) at the origin, a one-wide corridor east, and the themed room (radius `radius`) beyond it.
## Returns [HexMap, SitePlan, ThemeCtx].
func _synth(theme: String, radius: int = 8, gate: bool = false) -> Array:
	var m := HexMap.new()
	var a_c := Vector2i(0, 0)
	var b_c := Vector2i(radius + 13, 0)
	for c in Hex.range_cells(a_c, 5):
		m.set_cell(c, 0).tag = "room:0"
	for c in Hex.range_cells(b_c, radius):
		m.set_cell(c, 0).tag = "room:1"
	for q in range(6, b_c.x - radius):
		m.set_cell(Vector2i(q, 0), 0).tag = "corridor"
	var walls: Dictionary = {}
	for c: Vector2i in m.cells:
		for d in Hex.DIRS:
			if not m.has_cell(c + d):
				walls[c + d] = true
	for w: Vector2i in walls:
		m.set_cell(w, 3, HexMap.Tile.WALL)
	m.get_cell(a_c).tag = "start"
	m.get_cell(Vector2i(0, 3)).tag = "exit"
	var p := SitePlan.new()
	p.start = a_c
	p.exit = Vector2i(0, 3)
	SiteBuilder._index_rooms(m, p)
	p.room_themes = {"room:0": RoomThemeDefs.SERVICE, "room:1": theme}
	if gate:
		p.gates.append({"cell": b_c, "origin": true, "room": "room:1"})
	var avoid := {}
	for c in SiteBuilder._area(p.start, 3):
		avoid[c] = true
	for c in SiteBuilder._area(p.exit, 3):
		avoid[c] = true
	var ctx := ThemeCtx.make(m, p, avoid, SiteBuilder._corridor_zone(m), 12345)
	return [m, p, ctx]


func _check_vignettes_place() -> void:
	for theme: String in SIGNATURE:
		var r := _synth(theme)
		var plan: SitePlan = r[1]
		RoomThemes.plan_decor(r[2])
		var ok := {}
		for rep in plan.decor_report:
			if rep["room"] == "room:1":
				ok[String(rep["op"])] = bool(rep["ok"])
				check(bool(rep["ok"]) or bool(rep["skipped"]), "%s: recipe op '%s' places in a big room" % [theme, rep["op"]])
		check(bool(ok.get(String(SIGNATURE[theme]), false)), "%s: its vignette (%s) places" % [theme, SIGNATURE[theme]])
		var n_room := 0
		for dc in plan.decor:
			if dc["room"] == "room:1":
				n_room += 1
		check(n_room >= 2, "%s: the room is dressed (%d pieces)" % [theme, n_room])
		# the service entrance too
	var sv := _synth(RoomThemeDefs.SERVICE)
	var svp: SitePlan = sv[1]
	svp.room_themes["room:0"] = RoomThemeDefs.SERVICE
	svp.room_themes["room:1"] = RoomThemeDefs.SERVICE
	RoomThemes.plan_decor(sv[2])
	var kinds := {}
	for dc in svp.decor:
		kinds[dc["kind"]] = true
	check(kinds.has("hazard_tape") and kinds.has("wet_floor_sign"), "the service entrance has hazard tape and a WET FLOOR sign (%s)" % str(kinds.keys()))
	# the circle is drawn around a hellgate when there is one
	var g := _synth("spa", 8, true)
	RoomThemes.plan_decor(g[2])
	var gp: SitePlan = g[1]
	var circle_pos := Vector2.INF
	for dc in gp.decor:
		if dc["kind"] == "summoning_circle":
			circle_pos = dc["pos"]
	var gate_w := Hex.to_world(gp.gates[0]["cell"])
	check(circle_pos != Vector2.INF and circle_pos.distance_to(Vector2(gate_w.x, gate_w.z)) < 0.01, "the summoning circle is drawn around the hellgate")


## The vignettes are one unit with the relative transforms the design asks for.
func _check_vignette_structure() -> void:
	# cinema: a screen on a wall, 2-3 rows of recliners facing it, in rows
	var r := _synth("home_cinema")
	var plan: SitePlan = r[1]
	RoomThemes.plan_decor(r[2])
	var screen := {}
	var seats: Array[Dictionary] = []
	for dc in plan.decor:
		if dc["kind"] == "cinema_screen":
			screen = dc
		elif dc["kind"] == "recliner":
			seats.append(dc)
	check(not screen.is_empty() and screen["place"] == "wall", "the cinema screen is wall-backed")
	check(seats.size() >= 4 and seats.size() <= 9, "the cinema has 2-3 rows of recliners (%d)" % seats.size())
	var sf := Vector2(sin(deg_to_rad(float(screen["yaw"]))), cos(deg_to_rad(float(screen["yaw"]))))
	var rows := {}
	for s in seats:
		eq(int(s["group"]), int(screen["group"]), "recliners share the screen's group")
		var rel: Vector2 = (s["pos"] as Vector2) - (screen["pos"] as Vector2)
		check(rel.dot(sf) > 2.0, "every recliner sits in front of the screen")
		rows[roundi(rel.dot(sf))] = true
		var sy: float = s["yaw"]
		var seat_f := Vector2(sin(deg_to_rad(sy)), cos(deg_to_rad(sy)))
		var to_screen_c: Vector2 = (screen["pos"] as Vector2) - (s["pos"] as Vector2)
		check(rad_to_deg(absf(seat_f.angle_to(to_screen_c))) <= 15.0, "a recliner faces the screen (%.1f deg off)" % rad_to_deg(absf(seat_f.angle_to(to_screen_c))))
	check(rows.size() >= 2 and rows.size() <= 3, "the recliners form 2-3 rows (%d)" % rows.size())
	# table + chairs
	var tw := _synth("wine_cellar")
	RoomThemes.plan_decor(tw[2])
	var table := {}
	var chairs := 0
	var barrels := 0
	for dc in (tw[1] as SitePlan).decor:
		if dc["kind"] == "tasting_table":
			table = dc
		elif dc["kind"] == "chair":
			chairs += 1
			check(int(dc["group"]) == int(table.get("group", -5)) or table.is_empty(), "a chair belongs to the table's group")
		elif dc["kind"] == "barrel":
			barrels += 1
	check(not table.is_empty() and chairs >= 3, "a tasting table has chairs (%d)" % chairs)
	check(barrels >= 2, "barrels come in clusters (%d)" % barrels)
	# desk + chair + monitor
	var sr := _synth("server_room")
	RoomThemes.plan_decor(sr[2])
	var have := {}
	for dc in (sr[1] as SitePlan).decor:
		if int(dc["group"]) >= 0 and (dc["role"] in ["desk", "monitor", "seat"]):
			have[dc["role"]] = true
	check(have.has("desk") and have.has("monitor") and have.has("seat"), "a desk, its monitor and its chair are placed together")
	# bunk rows
	var bk := _synth("barracks")
	RoomThemes.plan_decor(bk[2])
	var bunks := 0
	for dc in (bk[1] as SitePlan).decor:
		if dc["kind"] == "bunk_bed":
			bunks += 1
			check(dc["place"] == "wall", "bunks are wall-backed")
	check(bunks >= 2, "bunk beds come in rows (%d)" % bunks)
	# weight bench + rack
	var gm := _synth("gym")
	RoomThemes.plan_decor(gm[2])
	var rack := {}
	var bench := {}
	for dc in (gm[1] as SitePlan).decor:
		if dc["kind"] == "dumbbell_rack" and dc["role"] == "rack":
			rack = dc
		elif dc["kind"] == "weight_bench":
			bench = dc
	check(not rack.is_empty() and not bench.is_empty(), "a weight bench stands in front of its rack")
	if not rack.is_empty() and not bench.is_empty():
		check((rack["pos"] as Vector2).distance_to(bench["pos"]) < 2.4, "the bench is right in front of the rack")
	# candles in a ring around the chalk circle
	var sp := _synth("spa")
	RoomThemes.plan_decor(sp[2])
	var circle := {}
	var candles: Array[Dictionary] = []
	for dc in (sp[1] as SitePlan).decor:
		if dc["kind"] == "summoning_circle":
			circle = dc
		elif dc["kind"] == "candle":
			candles.append(dc)
	check(not circle.is_empty() and candles.size() >= 5, "candles ring the chalk circle (%d)" % candles.size())
	if not circle.is_empty():
		var radius: float = (circle["params"] as Dictionary)["radius"]
		for cd in candles:
			var dist := (cd["pos"] as Vector2).distance_to(circle["pos"])
			check(absf(dist - (radius + 0.5)) < 0.15, "a candle sits on the ring around the circle (%.2f vs %.2f)" % [dist, radius + 0.5])
			eq(int(cd["group"]), int(circle["group"]), "candles share the circle's group")
	# the priced projector faces the screen's wall: place a cinema with a projector
	var pr_run := ContractRun.make("prepper", 11, 0.5)
	var seen_proj := 0
	for s in SEEDS:
		var run := ContractRun.make("prepper", s, 0.5)
		for f in range(1, 4):
			var plan2 := SiteBuilder.plan(DungeonGen.generate(run.floor_seed(f)), run, f, ContractParts.prop_catalog("bunker"))
			for rt: String in plan2.rooms_with_theme("home_cinema"):
				var proj := {}
				var scr := {}
				for pr in plan2.props:
					if pr["room"] == rt and pr["kind"] == "projector":
						proj = pr
				for dc in plan2.decor:
					if dc["room"] == rt and dc["kind"] == "cinema_screen":
						scr = dc
				if proj.is_empty() or scr.is_empty():
					continue
				seen_proj += 1
				var pf := Vector2(sin(deg_to_rad(float(proj["yaw"]))), cos(deg_to_rad(float(proj["yaw"]))))
				var to_screen: Vector2 = (scr["pos"] as Vector2) - (proj["pos"] as Vector2)
				check(rad_to_deg(absf(pf.angle_to(to_screen))) <= 80.0, "the projector faces the screen across the room (%.0f deg)" % rad_to_deg(absf(pf.angle_to(to_screen))))
	check(pr_run.site_type == "bunker", "bunker run")


# --- perf and op success --------------------------------------------------------------------------------------------------

func _check_perf() -> void:
	var avg := _plan_ms / float(_plans)
	check(avg < 150.0, "placing a floor is fast: %.1f ms on average (themes %.1f ms)" % [avg, _theme_ms / float(_plans)])
	check(_worst_plan_ms < 600.0, "the slowest floor plans in %.0f ms" % _worst_plan_ms)


## Every recipe op places in most rooms where it is tried (rooms can be too cramped, or the exit / a hellgate takes the middle).
func _check_op_rates() -> void:
	var worst := 1.0
	for key: String in _ops_n:
		var rate := float(_ops_ok.get(key, 0)) / float(_ops_n[key])
		check(rate >= 0.45, "%s places in %.0f%% of rooms" % [key, rate * 100.0])
		worst = minf(worst, rate)
		print("  op %-30s %3d / %3d  %.0f%%" % [key, int(_ops_ok.get(key, 0)), int(_ops_n[key]), rate * 100.0])
	print("themes: recipe ops place in %.0f%% of rooms at worst (%d op kinds)" % [worst * 100.0, _ops_n.size()])


# --- the spawned floor ----------------------------------------------------------------------------------------------------

func _check_spawn() -> void:
	var run := ContractRun.make("guru", 3, 0.5)
	var map := DungeonGen.generate(run.floor_seed(3))
	var world := Node3D.new()
	add_child(world)
	GameWorld.begin(map, world, 1)
	Ledger.begin_contract(1000000)
	var site := SiteBuilder.build(map, run, 3)
	var plan := site.plan
	var decor_nodes := 0
	var blockers := 0
	var lights := 0
	for n in site.decor:
		if n is DecorProp:
			decor_nodes += 1
			blockers += (n as DecorProp).blockers.size()
		elif n.name == "ThemeLights":
			lights = n.get_child_count()
	eq(decor_nodes, plan.decor.size(), "every decor placement is spawned")
	var want_blockers := 0
	for dc in plan.decor:
		if bool(dc["blocks"]):
			want_blockers += (dc["block_points"] as Array).size()
	eq(blockers, want_blockers, "blocking pieces carry their blocker circles")
	eq(lights, plan.lights.size(), "one accent light per themed room")
	check(lights <= plan.rooms.size() and lights <= 9, "at most one light per room (%d)" % lights)
	check(plan.lights.size() >= plan.rooms.size() - 1, "every room has an accent light")
	for l in plan.lights:
		check(not (l["color"] as Color).is_equal_approx(Color.BLACK) and float(l["energy"]) > 0.0 and float(l["range"]) > 0.0, "a light has colour, energy and range")
	# priced props stand where the plan says and face as planned
	eq(site.props.size(), plan.props.size(), "every priced prop is spawned")
	for i in site.props.size():
		var prop := site.props[i] as PricedProp
		var pr: Dictionary = plan.props[i]
		var pos: Vector2 = pr["pos"]
		check(Vector2(prop.global_position.x, prop.global_position.z).distance_to(pos) < 0.05, "%s stands at its planned spot" % prop.kind)
		var pf := prop.facing_vector()
		var want := Vector2(sin(deg_to_rad(float(pr["yaw"]))), cos(deg_to_rad(float(pr["yaw"]))))
		check(pf.distance_to(want) < 0.01, "%s faces its planned way" % prop.kind)
	# a blocker really pushes an actor out (the soft circle separation)
	var blocking: DecorProp = null
	for n in site.decor:
		if n is DecorProp and (n as DecorProp).blockers.size() > 0:
			blocking = n
			break
	if blocking != null:
		var b := blocking.blockers[0]
		var dummy := TrainingDummy.new()
		dummy.max_hp = 100.0
		GameWorld.spawn(dummy, b.global_position + Vector3(0.1, 0.0, 0.0))
		await get_tree().physics_frame
		dummy._separate()
		check(GameWorld.flat_distance(dummy.global_position, b.global_position) > 0.2, "a blocking decor piece pushes actors out of its way")
		eq(b.apply_damage(50.0, null), 0.0, "decor is never damaged")
		check(not b.dead and b.shove_mult == 0.0, "decor is immovable and unbreakable")
		dummy.queue_free()
	await get_tree().physics_frame
	GameWorld.end()
	world.queue_free()


func _check_models_and_anim() -> void:
	var holder := Node3D.new()
	add_child(holder)
	var sign_model := DecorModels.build("neon_sign", {"text": "EVIL", "color": Color(1, 0.2, 0.1), "dead": [3]})
	holder.add_child(sign_model)
	var letters := 0
	for ch in sign_model.get_children():
		if String(ch.name).begins_with("Letter"):
			letters += 1
	eq(letters, 4, "the sign has one mesh per letter")
	var screen_model := DecorModels.build("cinema_screen")
	holder.add_child(screen_model)
	var fin := DecorModels.build("shark_fin", {"center": Vector2(5, 5), "radius": 3.0, "gap_yaw": 0.0, "phase": 0.0, "speed": 0.6})
	holder.add_child(fin)
	var sc := screen_model.get_node_or_null("Screen") as MeshInstance3D
	check(sc != null, "the cinema screen has a picture")
	var tex0: Texture2D = ((sc.material_override as StandardMaterial3D).albedo_texture) if sc != null else null
	var changed := false
	for i in 40:
		await get_tree().process_frame
		if sc != null and (sc.material_override as StandardMaterial3D).albedo_texture != tex0:
			changed = true
	check(changed, "the screen flickers between frames")
	check(DecorScreen.frames().size() == DecorScreen.SNOW_FRAMES + 1, "the screen has snow frames and the demon frame")
	holder.queue_free()

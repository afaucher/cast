class_name SewerLayouts
extends RefCounted
## SEWER SLICE, phase 1 (docs/design/sewer-concept.md, "Phase 1 as built"): the round-2 lab layouts as whole floors for the
## dev flag `--sewer <N>` (GameDev, scripts/app/dev/sewer_dev.gd). NOT in the floor generator: DungeonGen and SiteBuilder
## never call it. The bridges of the lab are gone (user, 2026-10-20: "Omit the bridges for now"): a deck cut off by a
## channel is reached by wading.
##
##   1  L1 Reclamation run (bunker, concrete): intake -> narrow flooded hall -> settling cistern -> ledged wide hall -> pump room
##   2  L2 The Y junction (lair, brick): a drain junction, three flooded halls to the pump post, the aquarium overflow and a
##      storeroom
##   3  L3 = L1's layout in the toxic look (lair overflow), staged for a lair (L1's theme variant, user's build order)
##   4  L4 Storm-drain loop (bunker, concrete): four rooms in a ring, two ledged wide halls, two flooded narrow halls
##   5  L5 The sewer main (lair, brick): a grand cistern and an outfall gallery joined by a 6.0 main
##
## THE MAP (as the lab built it, plus water up to the walls): hex-blob rooms joined by halls cut the way DungeonGen cuts
## them (narrow 3.0, wide 4.5, a 6.0 main), midpoint walls. WET cells are sunk to the channel floor (CH_LEVEL, one level
## down, wading depth like the pools): a wet full cell is a basin cell (pool_mask all kites), a wet CUT cell keeps its wall
## part and its floor kites are pool floor (water up to the wall: HexMapView draws it, HexMap.water_at is true there), and a
## dry cell next to water gets pool kites toward it (PoolGeo's rule, wall kites left out), so every rim runs on a midpoint
## line. All the water of a layout is ONE connected body (test_sewer): every room's channel runs into its flooded halls.
## The body is a record in HexMap.pools ({"body": true, ...}: Wading slows and soaks in it as in any pool; PoolView skips it,
## SewerView draws it).
##
## THE ENTRY: every layout has a dry landing room (radius 4) with the freight elevator standing free in it (ElevatorGeo
## "free", its door toward the camera); a dry hall leads to the first sewer room. The crew arrives in the elevator (the
## flag starts the contract on floor 2: GameDev) and its landing is the exit.
##
## The layout record (build(n)): {id, name, blurb, look, site, map, rooms {tag: name}, flows [PackedVector2Array],
## landing (the landing room's centre), props / hazards [{kind, pos: Vector2, yaw}], decor [{kind, pos, yaw, params, y}],
## notes [{cell, format, header, text, yaw}], employee {cell, name, style}, monsters [{kind, at: Vector2, face: Vector2}],
## scout {route: [Vector2], looks: [Vector2, Vector2]} or {at} or {}, gator {at, face, spots: [Vector2]}, halls {id: cells},
## wet_halls [ids], decks [cells of each staged dry deck, for the reachability test]}. Deterministic (no random numbers).

const COUNT := 5
const CH_LEVEL := -1                                   ## the channel floor: one level down, like a pool floor
const WALL_LEVEL := 3
const LH := Hex.LEVEL_HEIGHT
const SURFACE_Y := CH_LEVEL * LH + HexMap.WATER_DEPTH  ## -0.14: the water surface (wading depth)
const LANDING_RADIUS := 4
const D := Hex.DIRS


## The cells of a layout as they are being laid out, then the map (the lab's builder, game-ready).
class Builder:
	extends RefCounted
	var cells := {}          ## Vector2i -> tag (rooms "room:N", halls "corridor"), before the map is made
	var wet := {}            ## Vector2i -> true: under water (sunk to the channel floor)
	var hall_cells := {}     ## hall id -> Array[Vector2i]
	var wet_halls: Array[String] = []
	var map: HexMap

	## A hex-blob room.
	func room(center: Vector2i, radius: int, tag: String) -> void:
		for c in Hex.range_cells(center, radius):
			if not cells.has(c):
				cells[c] = tag

	## A straight hall from door cell `a` n steps along DIRS[dir], cut the way DungeonGen cuts one: the route plus `lanes`
	## lanes toward DIRS[dir + 1] (0: narrow 3.0, 1: wide 4.5, 2: a 6.0 main) is its core, every core cell gets all six
	## neighbours. Returns the route (door to door).
	func hall(hall_id: String, a: Vector2i, dir: int, n: int, lanes: int) -> Array[Vector2i]:
		var before := cells.duplicate()
		var route: Array[Vector2i] = []
		for i in n + 1:
			route.append(a + D[dir] * i)
		var core: Array[Vector2i] = route.duplicate()
		for i in range(1, n):
			if not cells.has(route[i]):
				cells[route[i]] = "corridor"
			for k in range(1, lanes + 1):
				var lane: Vector2i = route[i] + D[(dir + 1) % 6] * k
				if cells.has(lane) and str(cells[lane]) != "corridor":
					continue
				cells[lane] = "corridor"
				core.append(lane)
		for k in core:
			for d in D:
				if not cells.has(k + d):
					cells[k + d] = "corridor"
		var mine: Array[Vector2i] = []
		for c: Vector2i in cells:
			if not before.has(c):
				mine.append(c)
		hall_cells[hall_id] = mine
		return route

	## The cells with walls round them, midpoint-cut: rooms flagstone, halls corridor stone, walls rough stone (SewerView
	## restyles them per look).
	func make_map() -> void:
		map = HexMap.new()
		var room_mat := FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
		var corr_mat := FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)
		var keys: Array = cells.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		for c: Vector2i in keys:
			var cell := map.set_cell(c, 0)
			cell.tag = str(cells[c])
			cell.mat_id = corr_mat if cell.tag == "corridor" else room_mat
		for c: Vector2i in keys:
			for nb in Hex.neighbors(c):
				if not cells.has(nb) and not map.has_cell(nb):
					map.set_cell(nb, WALL_LEVEL, HexMap.Tile.WALL).mat_id = room_mat
		map.cut_walls()

	func flood(list: Array) -> void:
		for c: Vector2i in list:
			if map.has_cell(c) and map.cells[c].type != HexMap.Tile.WALL and map.cells[c].wall_mask != HexMap.ALL_KITES:
				wet[c] = true

	func wet_line(a: Vector2i, b: Vector2i) -> void:
		flood(Hex.line(a, b))

	## A narrow hall under water wall to wall.
	func flood_hall(hall_id: String) -> void:
		wet_halls.append(hall_id)
		flood(hall_cells[hall_id])

	## A wide hall's channel: the route row and the near cut row (the far lane stays a dry ledge).
	func flood_wide(hall_id: String, route: Array[Vector2i], dir: int) -> void:
		wet_halls.append(hall_id)
		var list: Array[Vector2i] = []
		for i in range(1, route.size() - 1):
			var r: Vector2i = route[i]
			list.append(r)
			list.append(r + D[(dir + 5) % 6])
			list.append(r + D[(dir + 4) % 6])
		flood(list)

	## A 6.0 main's channel: the middle row only (lane 1); a dry ledge each side.
	func flood_main(hall_id: String, route: Array[Vector2i], dir: int) -> void:
		wet_halls.append(hall_id)
		var list: Array[Vector2i] = []
		for r in route:
			list.append(r + D[(dir + 1) % 6])
		flood(list)

	## Sink the wet cells and cut the rims (see the header): water up to the walls.
	func apply_water() -> void:
		for c: Vector2i in wet:
			var cell: HexMap.Cell = map.cells[c]
			cell.level = CH_LEVEL
			cell.pool_level = CH_LEVEL
			cell.pool_mask = HexMap.ALL_KITES & ~cell.wall_mask
		for c: Vector2i in map.cells:
			var cell: HexMap.Cell = map.cells[c]
			if cell.type == HexMap.Tile.WALL or wet.has(c):
				continue
			var m := 0
			for d in 6:
				if wet.has(c + D[d]):
					m |= (1 << d) | (1 << posmod(d - 1, 6))
			m &= ~cell.wall_mask
			if m != 0:
				cell.pool_mask = m
				cell.pool_level = CH_LEVEL

	## The landing room's free-standing elevator (door toward the camera) and the start / exit tags.
	func elevator(center: Vector2i, room_tag: String) -> void:
		var rec := ElevatorGeo.make_free(center, 5, 0, int(room_tag.trim_prefix("room:")))
		for poly in ElevatorGeo.solids(rec):
			map.add_solid(poly)
		for c: Vector2i in (rec["cells"] as Array):
			map.no_stand[c] = true
		map.elevator = rec
		var landing: Vector2i = rec["landing"]
		map.get_cell(landing).tag = "exit"
		map.get_cell(landing + D[1]).tag = "start"

	## The connected water as a HexMap.pools record (Wading reads it; PoolView skips it; SewerView draws it).
	func body_record(look: String) -> void:
		var basin: Array[Vector2i] = []
		var ring: Array[Vector2i] = []
		for c: Vector2i in map.cells:
			var cell: HexMap.Cell = map.cells[c]
			if wet.has(c):
				basin.append(c)
			elif cell.pool_mask != 0:
				ring.append(c)
		basin.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		map.pools.append({
			"room": "", "look": "sewer_" + look, "body": true, "shape": "sewer", "basin": basin, "ring": ring, "outline": [],
			"hole": [], "center": Vector2.ZERO, "axis": Vector2.RIGHT, "half_wid": 0.0, "deck_level": 0,
			"floor_level": CH_LEVEL, "surface_y": SURFACE_Y,
		})


# --- helpers -------------------------------------------------------------------------------------------------------

## World X/Z of a cell (plus a world offset).
static func w(c: Vector2i, off: Vector3 = Vector3.ZERO) -> Vector2:
	var p := Hex.to_world(c) + off
	return Vector2(p.x, p.z)


static func dv(d: int) -> Vector2:
	var v := Hex.dir_vector(posmod(d, 6))
	return Vector2(v.x, v.z)


## Yaw (degrees) that turns a model's front (+Z) onto the X/Z direction v.
static func yaw_to(v: Vector2) -> float:
	return rad_to_deg(atan2(v.x, v.y))


## A point on a hex-blob room's wall side between corners d and d + 1: `t` along the side from its middle, `inset` in
## from the wall line. Returns [pos (Vector2), yaw facing into the room].
static func wall_spot(c: Vector2i, radius: int, d: int, t: float, inset: float) -> Array:
	var n := (dv(d) + dv(d + 1)).normalized()
	var tan := (dv(d + 1) - dv(d)).normalized()
	var p := w(c) + n * (1.5 * float(radius) - inset) + tan * t
	return [p, yaw_to(-n)]


## The unit X/Z vector across a hall running along `dir`, toward its lanes (DIRS[dir + 1]'s side).
static func across(dir: int) -> Vector2:
	var ax := dv(dir)
	var v := Vector2(-ax.y, ax.x)
	return v if v.dot(dv(dir + 1)) > 0.0 else -v


static func _prop(L: Dictionary, kind: String, spot: Array) -> void:
	(L["props"] as Array).append({"kind": kind, "pos": spot[0], "yaw": spot[1]})


static func _hazard(L: Dictionary, kind: String, spot: Array) -> void:
	(L["hazards"] as Array).append({"kind": kind, "pos": spot[0], "yaw": spot[1]})

## A priced prop against a room's wall side (wall_spot's arguments), moved along the wall (or a little further in) until its
## whole footprint stands on dry floor at the deck's level: props never stand in the water or on a rim.
static func _prop_wall(L: Dictionary, kind: String, c: Vector2i, radius: int, d: int, t: float, inset: float) -> void:
	_prop(L, kind, _dry_wall_spot(L, kind, c, radius, d, t, inset))


static func _hazard_wall(L: Dictionary, kind: String, c: Vector2i, radius: int, d: int, t: float, inset: float) -> void:
	_hazard(L, kind, _dry_wall_spot(L, kind, c, radius, d, t, inset))


static func _dry_wall_spot(L: Dictionary, kind: String, c: Vector2i, radius: int, d: int, t: float, inset: float) -> Array:
	var m: HexMap = L["map"]
	var foot: Vector2 = PricedProp.placement(kind)["foot"]
	var gap := maxf(foot.x, foot.y) * 0.5 + 0.7
	for extra: float in [0.0, 0.35, 0.7]:
		for k in 25:
			var dt := float((k + 1) / 2) * 0.25 * (1.0 if k % 2 == 1 else -1.0)
			var s := wall_spot(c, radius, d, t + dt, inset + extra)
			if not _dry_foot(m, s[0], s[1], foot):
				continue
			var clear := true
			for e: Dictionary in L["props"] + L["hazards"]:
				clear = clear and (e["pos"] as Vector2).distance_to(s[0]) >= gap
			if clear:
				return s
	push_warning("SewerLayouts: no dry wall spot for %s at %s side %d" % [kind, c, d])
	return wall_spot(c, radius, d, t, inset)


## Is the footprint `foot` (lateral x forward) of a thing standing at pos facing yaw all dry floor at level 0?
static func _dry_foot(m: HexMap, pos: Vector2, yaw: float, foot: Vector2) -> bool:
	var f := Vector2(sin(deg_to_rad(yaw)), cos(deg_to_rad(yaw)))
	var l := Vector2(f.y, -f.x)
	for a: float in [-0.5, 0.0, 0.5]:
		for b2: float in [-0.5, 0.0, 0.5]:
			var p := pos + l * foot.x * a + f * foot.y * b2
			var p3 := Vector3(p.x, 0.0, p.y)
			if m.wall_at(p3) or m.water_at(p3) or is_nan(m.ground_height(p3)) or absf(m.ground_level(p3)) > 0.01:
				return false
	return true



## A decor piece: `y` is where the model's origin stands (NAN: on the ground under it).
static func _decor(L: Dictionary, kind: String, pos: Vector2, yaw: float, params: Dictionary = {}, y: float = NAN) -> void:
	(L["decor"] as Array).append({"kind": kind, "pos": pos, "yaw": yaw, "params": params, "y": y})


## A sluice gate across a doorway (decor: its posts on the jambs, the plate raised over the water).
static func _sluice(L: Dictionary, door_cell: Vector2i, dir: int, width: float = 3.0) -> void:
	var p := w(door_cell) + dv(dir) * Hex.INNER
	_decor(L, "sluice", p, yaw_to(dv(dir)), {"width": width, "open": 0.45}, 0.0)


## Iron bars across a culvert mouth (decor, standing on the channel floor).
static func _bars(L: Dictionary, c: Vector2i, dir: int, width: float = 2.8) -> void:
	_decor(L, "bars", w(c), yaw_to(dv(dir)), {"width": width, "height": 1.3}, CH_LEVEL * LH)


## An outfall pipe in the wall at `corner` (its border cell) pouring into the channel toward DIRS[into_dir].
static func _outfall(L: Dictionary, corner: Vector2i, into_dir: int, radius: float = 0.6, drop: float = 1.0) -> void:
	_decor(L, "outfall", w(corner) + dv(into_dir) * 0.1, yaw_to(dv(into_dir)), {"radius": radius, "drop": drop}, 0.0)


static func _grate(L: Dictionary, c: Vector2i, size: float, yaw: float = 0.0) -> void:
	_decor(L, "grate", w(c), yaw, {"size": size}, CH_LEVEL * LH + 0.01)


static func _mon(L: Dictionary, kind: String, at: Vector2, face: int) -> void:
	(L["monsters"] as Array).append({"kind": kind, "at": at, "face": dv(face)})


static func _note(L: Dictionary, cell: Vector2i, format: String, header: String, text: String, face: int) -> void:
	(L["notes"] as Array).append({"cell": cell, "format": format, "header": header, "text": text, "yaw": yaw_to(dv(face))})


static func _new_layout(id: int, layout_name: String, blurb: String, look: String, site: String) -> Dictionary:
	return {
		"id": id, "name": layout_name, "blurb": blurb, "look": look, "site": site, "rooms": {}, "flows": [],
		"props": [], "hazards": [], "decor": [], "notes": [], "monsters": [], "employee": {}, "scout": {}, "gator": {},
		"halls": {}, "wet_halls": [], "decks": [], "landing": Vector2i.ZERO, "view": Vector2.ZERO, "crew_at": Vector2i.ZERO,
	}


## The landing room (radius 4, the elevator in its middle) at `center`, and the dry hall `in` from `door` (a room's border
## cell) along DIRS[dir] to the landing room's border.
static func _landing(b: Builder, L: Dictionary, center: Vector2i, door: Vector2i, dir: int, tag: String) -> void:
	b.room(center, LANDING_RADIUS, tag)
	b.hall("in", door, dir, Hex.distance(door, center) - LANDING_RADIUS, 0)
	L["landing"] = center
	(L["rooms"] as Dictionary)[tag] = "landing (dry, the elevator)"


static func _flow(L: Dictionary, list: Array) -> void:
	var pl := PackedVector2Array()
	for c: Vector2i in list:
		pl.append(w(c))
	(L["flows"] as Array).append(pl)


static func _finish(b: Builder, L: Dictionary, landing_tag: String) -> void:
	b.apply_water()
	b.elevator(L["landing"], landing_tag)
	b.body_record(str(L["look"]))
	L["map"] = b.map
	L["halls"] = b.hall_cells
	L["wet_halls"] = b.wet_halls
	L["wet"] = b.wet


# --- the layouts ---------------------------------------------------------------------------------------------------

## Layout n (1-5) built: the map and everything staged on it (see the header).
static func build(n: int) -> Dictionary:
	match clampi(n, 1, COUNT):
		2: return _junction()
		3: return _reclaim(true)
		4: return _loop()
		5: return _main()
	return _reclaim(false)


static func layout_name(n: int) -> String:
	return ["L1 Reclamation run", "L2 The Y junction", "L3 Reclamation run (toxic)", "L4 Storm-drain loop", "L5 The sewer main"][clampi(n, 1, COUNT) - 1]


## L1 (and L3, its toxic lair variant): intake (A) -> narrow flooded hall -> settling cistern (B) -> ledged wide hall ->
## pump room (C). The outfall in A's back corner feeds a channel that bends through A, runs the hall, crosses B through its
## sump, runs the wide hall's channel and ends in C's drain sump at the pumps.
static func _reclaim(toxic: bool) -> Dictionary:
	var L := _new_layout(3 if toxic else 1, "Reclamation run" + (" (toxic)" if toxic else ""),
			"intake, a flooded hall, the settling cistern, a ledged hall, the pump room", "toxic" if toxic else "concrete",
			"lair" if toxic else "bunker")
	var b := Builder.new()
	var a0 := Vector2i(0, 0)
	var b0 := a0 + D[1] * 16
	var c0 := b0 + D[1] * 16
	var e0 := c0 + D[2] * 11
	b.room(a0, 5, "room:0")
	b.room(b0, 5, "room:1")
	b.room(c0, 5, "room:2")
	b.room(e0, 2, "room:4")
	L["rooms"] = {"room:0": "A: intake", "room:1": "B: settling cistern", "room:2": "C: pump room", "room:4": "way on (dry)"}
	_landing(b, L, a0 + D[4] * 13, a0 + D[4] * 5, 4, "room:3")
	var ab := b.hall("ab", a0 + D[1] * 5, 1, 6, 0)
	var bc := b.hall("bc", b0 + D[1] * 5, 1, 6, 1)
	b.hall("out", c0 + D[2] * 5, 2, 4, 0)
	b.make_map()
	b.wet_line(a0 + D[3] * 5, a0)
	b.wet_line(a0, a0 + D[1] * 5)
	b.flood_hall("ab")
	b.wet_line(b0 + D[4] * 5, b0 + D[1] * 5)
	b.flood(Hex.range_cells(b0, 2))
	b.flood_wide("bc", bc, 1)
	b.wet_line(c0 + D[4] * 5, c0 + D[1] * 2)
	b.flood(Hex.range_cells(c0 + D[1] * 3, 1))
	_flow(L, [a0 + D[3] * 5, a0, b0, c0, c0 + D[1] * 3])
	_finish(b, L, "room:3")
	# --- dressing (the lab's, the bridges gone)
	_outfall(L, a0 + D[3] * 5, 0)
	_decor(L, "pipe_bundle", wall_spot(a0, 5, 2, 0.5, 0.05)[0], wall_spot(a0, 5, 2, 0.5, 0.05)[1], {"length": 5.0})
	_sluice(L, a0 + D[1] * 5, 1)
	_sluice(L, b0 + D[4] * 5, 4)
	_decor(L, "wet_floor_sign", w(a0 + D[4] * 4 + D[5]), 30.0)
	_grate(L, b0, 1.4, 15.0)
	_decor(L, "pipe_bundle", wall_spot(b0, 5, 2, 0.0, 0.05)[0], wall_spot(b0, 5, 2, 0.0, 0.05)[1], {"length": 4.0})
	_decor(L, "crate_stack", w(b0 + D[5] * 3 + D[4]), 15.0)
	_prop_wall(L, "electrical_panel", c0, 5, 1, -0.8, 0.3)   # (first: the spot nearest the drain sump)
	_prop_wall(L, "sump_pump", c0, 5, 1, 1.0, 0.6)
	_prop_wall(L, "sump_pump", c0, 5, 1, 2.6, 0.6)
	_decor(L, "lab_console", wall_spot(c0, 5, 3, 0.5, 0.6)[0], wall_spot(c0, 5, 3, 0.5, 0.6)[1])
	_decor(L, "tool_cart", w(c0 + D[2] * 2 + D[1]), yaw_to(dv(4)))
	_hazard_wall(L, "oil_drum", c0, 5, 2, 2.6, 0.5)
	_grate(L, c0 + D[1] * 3, 1.6)
	# --- staging (round 2's list: no rats, no gas pocket)
	_note(L, a0 + D[4] * 3 + D[5], "sign", "NOTICE", "RECLAIMED WATER: DO NOT DRINK. It is reclaimed.", 1)
	_mon(L, "grunt", w(a0 + D[1] * 9), 4)                                    # one skeleton wading the narrow hall
	L["gator"] = {"at": w(b0, Vector3(0.3, 0, 0.2)), "face": dv(3), "spots": [w(b0 + D[5] * 3 + D[0]), w(bc[4])]}
	_mon(L, "grunt", w(b0 + D[2] * 3), 4)
	_mon(L, "grunt", w(b0 + D[3] * 3), 4)
	_mon(L, "grunt", w(b0 + D[5] * 3), 4)
	_mon(L, "archer", w(b0 + D[2] * 4), 4)                                    # the north deck, across the sump
	L["scout"] = _ledge_route(bc, 1, 1)
	_mon(L, "brute", w(c0 + D[3] * 2 + D[2]), 4)
	_mon(L, "archer", w(c0 + D[2] * 3 + D[3]), 4)
	_mon(L, "archer", w(c0 + D[3] * 3 + D[2]), 4)
	if toxic:
		L["employee"] = {"cell": c0 + D[2] * 3 + D[1], "name": "Keith (Henchman 10)", "style": "henchman"}
		_note(L, c0 + D[2] * 2, "complaint", "COMPLAINT", "Who keeps putting the gator in the aquarium? It is not an aquarium gator.", 4)
	else:
		L["employee"] = {"cell": c0 + D[2] * 3 + D[1], "name": "Stan (maintenance)", "style": "staff"}
		_note(L, c0 + D[2] * 2, "report", "PUMP LOG", "Pump 2: gator in the intake again. Pump 1: fine. Me: not fine.", 4)
	L["decks"] = [a0 + D[5] * 2, a0 + D[2] * 3, b0 + D[2] * 4, b0 + D[5] * 3, c0 + D[2] * 3, c0 + D[5] * 3, e0]
	L["view"] = (w(a0) + w(b0)) * 0.5 + Vector2(0.0, 1.0)
	L["crew_at"] = a0 + D[5] * 2
	return L


## L2: a drain junction (J) where three flooded narrow halls meet over a sump; each runs to a small room whose channel
## crosses it and leaves through a barred culvert (the pump post, the storeroom) or starts at the source (the aquarium
## overflow). The crew comes in dry, down a wide hall from the landing, onto J's south wedge.
static func _junction() -> Dictionary:
	var L := _new_layout(2, "The Y junction", "three flooded halls meet over a drain sump; three islands, no bridges", "brick", "lair")
	var b := Builder.new()
	var j0 := Vector2i(0, 0)
	var e := j0 + D[0] * 13
	var n := j0 + D[2] * 13
	var wr := j0 + D[4] * 13
	b.room(j0, 5, "room:0")
	b.room(e, 3, "room:1")
	b.room(n, 3, "room:2")
	b.room(wr, 3, "room:3")
	L["rooms"] = {"room:0": "J: drain junction", "room:1": "E: pump post", "room:2": "N: aquarium overflow", "room:3": "W: storeroom"}
	for d: int in [0, 2, 4]:
		b.hall("h%d" % d, j0 + D[d] * 5, d, 5, 0)
	_landing(b, L, j0 + D[5] * 12, j0 + D[5] * 5, 5, "room:4")
	b.make_map()
	b.flood(Hex.range_cells(j0, 1))
	for d: int in [0, 2, 4]:
		b.wet_line(j0, j0 + D[d] * 5)
		b.flood_hall("h%d" % d)
	b.wet_line(e - D[0] * 3, e + D[0] * 3)
	b.wet_line(n - D[2] * 3, n + D[2] * 3)
	b.wet_line(wr - D[4] * 3, wr + D[4] * 3)
	_flow(L, [n + D[2] * 3, j0])
	_flow(L, [e + D[0] * 3, j0])
	_flow(L, [wr + D[4] * 3, j0])
	_finish(b, L, "room:4")
	_grate(L, j0, 1.8, 30.0)
	for d: int in [0, 2, 4]:
		_sluice(L, j0 + D[d] * 5, d)
	_sluice(L, e - D[0] * 3, 3)
	_sluice(L, n - D[2] * 3, 5)
	_sluice(L, wr - D[4] * 3, 1)
	_decor(L, "pipe_bundle", wall_spot(j0, 5, 3, 0.0, 0.05)[0], wall_spot(j0, 5, 3, 0.0, 0.05)[1], {"length": 4.0})
	_decor(L, "pipe_bundle", wall_spot(j0, 5, 1, 0.0, 0.05)[0], wall_spot(j0, 5, 1, 0.0, 0.05)[1], {"length": 4.0})
	# E: the pump post
	_bars(L, e + D[0] * 3, 0)
	_prop_wall(L, "sump_pump", e, 3, 1, 0.0, 0.6)
	_prop_wall(L, "henchman_locker", e, 3, 2, 0.0, 0.45)
	_prop_wall(L, "electrical_panel", e, 3, 0, 0.6, 0.3)
	_decor(L, "barrel", w(e + D[5] * 2 + D[4]), 0.0)
	# N: the aquarium overflow (the source): the cracked tank pours into the channel's head
	_outfall(L, n + D[2] * 3, 5, 0.5, 1.2)
	_prop_wall(L, "shark_tank", n, 3, 1, 0.9, 0.7)
	_prop_wall(L, "shark_tank", n, 3, 2, -0.9, 0.7)
	_prop_wall(L, "specimen_vat", n, 3, 3, 0.0, 0.6)
	# W: the storeroom (drums, cylinders, crates)
	_bars(L, wr + D[4] * 3, 4)
	_hazard_wall(L, "oil_drum", wr, 3, 2, 0.6, 0.5)
	_hazard_wall(L, "oil_drum", wr, 3, 2, -0.6, 0.5)
	_hazard_wall(L, "gas_cylinders", wr, 3, 3, 0.4, 0.5)
	_decor(L, "crate_stack", w(wr + D[5] * 2), 10.0)
	_decor(L, "tool_cart", w(e + D[2] * 2 + D[3]), yaw_to(dv(5)))
	# staging
	L["gator"] = {"at": w(j0, Vector3(0.2, 0, 0.1)), "face": dv(4), "spots": [w(j0 + D[3] * 3 + D[4]), w(j0 + D[2] * 8)]}
	_mon(L, "grunt", w(j0 + D[1] * 3), 4)
	_mon(L, "grunt", w(j0 + D[1] * 2 + D[2]), 4)
	_mon(L, "grunt", w(j0 + D[1] * 3 + D[0]), 4)
	_mon(L, "grunt", w(j0 + D[0] * 4, Vector3(0.0, 0, 0.2)), 3)              # wading the east channel
	_mon(L, "archer", w(j0 + D[3] * 3 + D[2]), 5)                            # the NW wedge, across the sump
	_mon(L, "archer", w(e + D[1] * 2), 4)
	_mon(L, "archer", w(e + D[4] * 2), 1)
	_mon(L, "brute", w(wr + D[2] * 2), 1)
	L["employee"] = {"cell": e + D[2] * 2, "name": "Gary (Henchman 1)", "style": "henchman"}
	_note(L, e + D[5] * 2, "memo", "FEEDING ROTA", "Gator: Mon/Wed/Fri. Not Gary. Gary is not food. Gary, stop volunteering.", 2)
	_note(L, j0 + D[5] * 3 + D[4], "sign", "NOTICE", "DO NOT FEED THE GATOR", 1)
	_note(L, n + D[0] * 2, "complaint", "COMPLAINT", "Who keeps putting the gator in the aquarium?", 3)
	L["decks"] = [j0 + D[5] * 3, j0 + D[1] * 3, j0 + D[3] * 3 + D[2], e + D[1] * 2, e + D[5] * 2, n + D[0] * 2, n + D[3] * 2, wr + D[2] * 2, wr + D[5] * 2]
	L["view"] = w(j0) + Vector2(0.0, 1.5)
	L["crew_at"] = j0 + D[5] * 3
	return L


## L4: four rooms in a ring. Two ledged wide halls (the dry long way round) and two fully flooded narrow halls (the wet
## short way). The water comes in at the overflow chamber's outfall (P0) and runs both ways round to the grit chamber's
## drain (P2).
static func _loop() -> Dictionary:
	var L := _new_layout(4, "Storm-drain loop", "four rooms in a ring: two dry ledges the long way, two flooded halls the short way", "concrete", "bunker")
	var b := Builder.new()
	var p0 := Vector2i(0, 0)
	var p1 := p0 + D[1] * 14
	var p2 := p1 + D[2] * 12
	var p3 := p0 + D[2] * 12
	b.room(p0, 4, "room:0")
	b.room(p1, 4, "room:1")
	b.room(p2, 4, "room:2")
	b.room(p3, 4, "room:3")
	L["rooms"] = {"room:0": "P0: overflow chamber", "room:1": "P1: valve room", "room:2": "P2: grit chamber", "room:3": "P3: generator nook"}
	var h01 := b.hall("h01", p0 + D[1] * 4, 1, 6, 1)
	var h32 := b.hall("h32", p3 + D[1] * 4, 1, 6, 1)
	b.hall("h03", p0 + D[2] * 4, 2, 4, 0)
	var h12 := b.hall("h12", p1 + D[2] * 4, 2, 4, 0)
	_landing(b, L, p0 + D[4] * 11, p0 + D[4] * 4, 4, "room:4")
	b.make_map()
	b.wet_line(p0 + D[2] * 4, p0 + D[1] * 4)
	b.wet_line(p0 + D[2] * 3, p0 + D[1] * 3)
	b.flood_wide("h01", h01, 1)
	b.flood_wide("h32", h32, 1)
	b.flood_hall("h03")
	b.flood_hall("h12")
	b.wet_line(p1 + D[4] * 4, p1)
	b.wet_line(p1, p1 + D[2] * 4)
	b.wet_line(p2 + D[5] * 4, p2 + D[4] * 4)
	b.wet_line(p2 + D[5] * 3, p2 + D[4] * 3)
	b.wet_line(p3 + D[5] * 4, p3)
	b.wet_line(p3, p3 + D[1] * 4)
	_flow(L, [p0 + D[2] * 3 + D[0] * 1, p0 + D[1] * 3, p1, p1 + D[2] * 4, p2 + D[5] * 3, p2 + D[5] * 3 + D[3] * 1])
	_flow(L, [p0 + D[2] * 3 + D[0] * 1, p0 + D[2] * 3, p3 + D[5] * 4, p3, p3 + D[1] * 4, p2 + D[4] * 3, p2 + D[5] * 3 + D[3] * 2])
	_finish(b, L, "room:4")
	var of := wall_spot(p0, 4, 1, 0.0, 0.1)
	_decor(L, "outfall", of[0], of[1], {"radius": 0.6, "drop": 1.0}, 0.0)
	_decor(L, "wet_floor_sign", w(p0 + D[4] * 2 + D[5]), 20.0)
	_sluice(L, p0 + D[2] * 4, 2)
	_sluice(L, p3 + D[5] * 4, 5)
	_sluice(L, p1 + D[2] * 4, 2)
	_sluice(L, p2 + D[5] * 4, 5)
	# P1: the valve room (pipes, a pump, the panel, the tool cart)
	_decor(L, "pipe_bundle", wall_spot(p1, 4, 0, 0.0, 0.05)[0], wall_spot(p1, 4, 0, 0.0, 0.05)[1], {"length": 5.0})
	_prop_wall(L, "sump_pump", p1, 4, 5, 0.6, 0.6)
	_prop_wall(L, "electrical_panel", p1, 4, 4, -1.0, 0.3)
	_decor(L, "tool_cart", w(p1 + D[0] * 2 + D[5]), yaw_to(dv(3)))
	# P2: the grit chamber (the drain, crates of grit)
	_grate(L, p2 + D[5] * 3 + D[3] * 2, 1.6)
	_decor(L, "crate_stack", w(p2 + D[2] * 2 + D[1]), 25.0)
	_decor(L, "crate_stack", w(p2 + D[1] * 2 + D[0]), -15.0)
	# P3: the generator nook
	_hazard_wall(L, "propane_tank", p3, 4, 2, 0.6, 0.55)
	_hazard_wall(L, "oil_drum", p3, 4, 3, 0.0, 0.5)
	_decor(L, "rack_cab", wall_spot(p3, 4, 2, -1.2, 0.45)[0], wall_spot(p3, 4, 2, -1.2, 0.45)[1])
	# staging
	_note(L, p0 + D[4] * 2, "sign", "NOTICE", "LEVEL RISES WITHOUT WARNING", 1)
	L["scout"] = _ledge_route(h01, 1, 1)
	_mon(L, "grunt", w(p1 + D[3] * 2), 4)
	_mon(L, "grunt", w(p1 + D[3] * 2 + D[2]), 4)
	L["employee"] = {"cell": p1 + D[0] * 2, "name": "Stan (maintenance)", "style": "staff"}
	L["gator"] = {"at": w(h12[2], Vector3(0.2, 0, 0)), "face": dv(5),
			"spots": [w(p0 + D[2] * 3 + D[0] * 2), w(h32[3]), w(p1 + D[2] * 2 + D[3])]}
	_mon(L, "brute", w(p2 + D[1] * 2), 4)
	_mon(L, "archer", w(p3 + D[3] * 2 + D[2]), 0)
	_mon(L, "archer", w(p3 + D[3] * 2), 0)
	L["decks"] = [p0 + D[5] * 2, p0 + D[2] * 2 + D[3], p1 + D[0] * 2, p1 + D[3] * 2, p2 + D[1] * 2, p2 + D[2] * 2, p3 + D[3] * 2, p3 + D[5] * 2 + D[0]]
	L["view"] = (w(p0) + w(p2)) * 0.5 + Vector2(0.0, 1.0)
	L["crew_at"] = p0 + D[5] * 2
	return L


## L5: a grand cistern (A) and an outfall gallery (B) joined by a 6.0 main: a 3.0 channel with a dry ledge each side. The
## channel runs the length of A from an outfall on A's west wall, through a big sump, along the main, across B and out
## through a barred culvert.
static func _main() -> Dictionary:
	var L := _new_layout(5, "The sewer main", "a grand cistern and a 6.0 main: archers on the far ledge, the gator's lane between", "brick", "lair")
	var b := Builder.new()
	var a0 := Vector2i(0, 0)
	var b0 := a0 + D[1] * 24
	var e0 := b0 + D[2] * 10
	b.room(a0, 6, "room:0")
	b.room(b0, 5, "room:1")
	b.room(e0, 2, "room:3")
	L["rooms"] = {"room:0": "A: grand cistern", "room:1": "B: outfall gallery", "room:3": "way on (dry)"}
	var mn := b.hall("main", a0 + D[1] * 6, 1, 13, 2)
	_landing(b, L, a0 + D[5] * 12, a0 + D[5] * 6, 5, "room:2")
	b.hall("out", b0 + D[2] * 5, 2, 3, 0)
	b.make_map()
	b.wet_line(a0 + D[2] + D[4] * 6, a0 + D[2] + D[1] * 6)
	b.flood(Hex.range_cells(a0 + D[2] + D[4] * 2, 1))
	b.flood_main("main", mn, 1)
	b.wet_line(b0 + D[2] + D[4] * 6, b0 + D[2] + D[1] * 4)
	_flow(L, [a0 + D[2] + D[4] * 6, b0 + D[2] + D[1] * 4])
	_finish(b, L, "room:2")
	_outfall(L, a0 + D[2] + D[4] * 6, 1, 0.65, 1.0)
	_bars(L, b0 + D[2] + D[1] * 4, 1)
	_decor(L, "pipe_bundle", w(mn[10] + D[2] * 3) - across(1) * 0.05, yaw_to(-across(1)), {"length": 4.0})   # the main's far wall
	_prop_wall(L, "henchman_locker", a0, 6, 2, -1.0, 0.45)
	_prop_wall(L, "henchman_locker", a0, 6, 2, 0.0, 0.45)
	_prop_wall(L, "evil_portrait", a0, 6, 2, 2.0, 0.15)
	_prop_wall(L, "brazier", a0, 6, 3, 1.5, 0.8)
	_prop_wall(L, "electrical_panel", a0, 6, 3, -1.6, 0.3)
	_decor(L, "pipe_bundle", wall_spot(b0, 5, 1, 0.0, 0.05)[0], wall_spot(b0, 5, 1, 0.0, 0.05)[1], {"length": 5.0})
	_hazard_wall(L, "oil_drum", b0, 5, 1, 2.6, 0.5)
	_decor(L, "tool_cart", w(b0 + D[5] * 3 + D[4]), yaw_to(dv(2)))
	_grate(L, a0 + D[2] + D[4] * 2, 1.8, 10.0)
	_sluice(L, b0 + D[2] * 5, 2)
	# staging
	_mon(L, "grunt", w(a0 + D[2] * 3), 5)
	_mon(L, "grunt", w(a0 + D[2] * 3 + D[3]), 5)
	_mon(L, "grunt", w(a0 + D[3] * 3 + D[2]), 0)
	L["employee"] = {"cell": a0 + D[3] * 4 + D[2], "name": "Nigel (Henchman 4)", "style": "henchman"}
	_note(L, a0 + D[1] * 4 + D[0], "sign", "NOTICE", "GATOR CROSSING", 1)
	L["gator"] = {"at": w(mn[5] + D[2]), "face": dv(4), "spots": [w(a0 + D[2] + D[4] * 2), w(mn[11] + D[2])]}
	for i: int in [8, 10]:
		_mon(L, "archer", w(mn[i] + D[2] * 2) + across(1) * 0.75, 4)        # the far ledge
	_mon(L, "brute", w(b0 + D[5] * 2), 4)
	L["scout"] = {"at": w(b0 + D[2] * 3 + D[3]), "face": dv(4)}
	L["decks"] = [a0 + D[2] * 3, a0 + D[5] * 3, a0 + D[3] * 3, b0 + D[5] * 2, b0 + D[2] * 3, e0]
	L["view"] = w(mn[5]) + Vector2(0.0, 1.0)
	L["crew_at"] = a0 + D[1] * 4 + D[5]
	return L


## A goblin scout's walk along a wide hall's dry ledge (the lane row, its middle a little toward the far wall): route
## points from one doorway to the other, and a look into each room at the ends.
static func _ledge_route(route: Array[Vector2i], dir: int, lanes: int) -> Dictionary:
	var pts: Array = []
	var off := across(dir) * 0.45
	for i in range(1, route.size() - 1):
		pts.append(w(route[i] + D[(dir + 1) % 6] * lanes) + off)
	return {"route": pts, "looks": [-dv(dir), dv(dir)]}


## Every wet cell of a built layout reached from one of them through wet cells: the body's components (1 = one body).
static func components(wet: Dictionary) -> int:
	var seen := {}
	var n := 0
	for c: Vector2i in wet:
		if seen.has(c):
			continue
		n += 1
		var stack: Array[Vector2i] = [c]
		seen[c] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			for d in D:
				var nb: Vector2i = cur + d
				if wet.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
	return n


## A minimal site plan for the layout: the rooms, start and exit, the elevator, the priced props, the explosives, the decor,
## the notes and the employee (SiteBuilder.spawn puts them in the world); no gates, packs, mail, van or doors (the staged
## monsters, the scout and the gator come from SewerDev).
static func plan(L: Dictionary, floor_n: int, run: ContractRun) -> SitePlan:
	var m: HexMap = L["map"]
	var p := SitePlan.new()
	p.floor_number = floor_n
	p.start = m.cells_with_tag("start")[0]
	p.exit = m.cells_with_tag("exit")[0]
	SiteBuilder._index_rooms(m, p)
	p.elevator = m.elevator.duplicate(true)
	p.elevator["look"] = run.elevator_look if run != null else "service"
	p.dispatch = "This floor's the service level. Everything down here is wet."
	for tag: String in p.rooms:
		p.room_themes[tag] = "service_entrance" if tag == p.exit_room else "sewer"
	for e: Dictionary in L["props"]:
		var pos: Vector2 = e["pos"]
		p.props.append({"cell": ThemeGeo.cell_of(pos), "kind": e["kind"], "room": p.room_of_cell(ThemeGeo.cell_of(pos)), "pos": pos,
				"yaw": e["yaw"], "place": "wall", "orient": "away_from_wall", "foot": PricedProp.placement(str(e["kind"]))["foot"]})
	for e: Dictionary in L["hazards"]:
		var pos: Vector2 = e["pos"]
		p.hazards.append({"cell": ThemeGeo.cell_of(pos), "kind": e["kind"], "room": p.room_of_cell(ThemeGeo.cell_of(pos)), "pos": pos,
				"yaw": e["yaw"], "place": "wall", "orient": "away_from_wall", "foot": PricedProp.placement(str(e["kind"]))["foot"]})
	for e: Dictionary in L["decor"]:
		var pos: Vector2 = e["pos"]
		var kind := str(e["kind"])
		var ground := m.ground_height(Vector3(pos.x, 0.0, pos.y))
		var lift := 0.0 if is_nan(float(e["y"])) or is_nan(ground) else float(e["y"]) - ground
		var dm: Dictionary = RoomThemeDefs.decor(kind)
		p.decor.append({"kind": kind, "pos": pos, "yaw": float(e["yaw"]), "cell": ThemeGeo.cell_of(pos),
				"room": p.room_of_cell(ThemeGeo.cell_of(pos)), "place": str(dm.get("place", "wall")), "orient": str(dm.get("orient", "free")),
				"group": -1, "role": "", "blocks": bool(dm.get("blocks", false)), "w": float(dm.get("w", 1.0)), "d": float(dm.get("d", 1.0)),
				"lift": lift, "target": pos, "params": e["params"], "block_points": [pos], "block_radius": 0.45})
	for e: Dictionary in L["notes"]:
		var c: Vector2i = e["cell"]
		p.notes.append({"cell": c, "text": e["text"], "format": e["format"], "header": e["header"], "kind": "hint",
				"yaw": e["yaw"], "room": p.room_of_cell(c)})
	var emp: Dictionary = L["employee"]
	if not emp.is_empty():
		p.employees.append({"cell": emp["cell"], "name": emp["name"], "style": emp["style"], "room": p.room_of_cell(emp["cell"])})
	return p

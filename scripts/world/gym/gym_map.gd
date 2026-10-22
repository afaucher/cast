class_name GymMap
extends RefCounted
## THE TEST GYM's map and site plan (`--gym`, a solo dev mode: docs/design/test-gym.md). One fixed floor (no dice of its own
## but SEED) that holds every environment the generator can make, built from the same pieces the generator uses, so what is
## tried in the gym behaves as on a real floor. NOT in the floor generator: DungeonGen and SiteBuilder never call it, so the
## golden floors do not move. GymDev (scripts/app/dev/gym_dev.gd) swaps it in for the generated floor.
##
## THE ROOMS (hex-blob rooms joined by halls cut the way DungeonGen cuts them: SewerLayouts.Builder; base level LEVEL), round
## the ARENA in the middle:
##   room:1  arena       a big flat room (radius 9) with nothing in it: room for a crowd, the training dummies on its north side
##   room:0  lobby       west: the start and the free-standing freight elevator (the exit)
##   room:2  course      east: the movement lab's pieces in a row (MoveLab's: a slalom of pillars, a +1 step run, a top, a
##                       3-level drop, a +2 ledge to mantle, its 2-level drop) and then a MATERIAL WALK, one band of every floor
##                       material (FloorMaterials.FLOORS) so every footstep plays
##   room:3-8    offices     north-west: themed rooms (home cinema, wine cellar, server room, lab, throne room with the HELLGATE,
##                       torture chamber) on narrow halls with office doors (DoorPlanner, the square doors), the staff in the
##                       server room and a henchman in the lab
##   room:9,10   pool, moat  south-east: an indoor pool and a shark moat (PoolGeo carves them from their themes), each with a
##                       regular shark
##   room:11-14  sewer       north-east: a dry room, the service stair down (a door in the service style) and a SEWER CLUSTER
##                       of three rooms (HexMap.sewer: SewerPlanner floods it: channels, sumps, wading water, the outfall and
##                       bars; a flooded narrow hall with its sluices, a ledged wide hall; HazardPlanner hangs the electrical
##                       panel (its live wire) and the pumps; GatorPlanner puts the gator in a sump: its territory)
##   room:15,16  lava cave   south-west: two rock chambers over a lava field (HexMap.cave, the generated record's shape), a
##                       two-wide bridge between them, an ISLE across a two-cell gap a damp's crust reaches, the rim round it
## Every room is one fog space (RoomFog reads the tags); the plan has props and explosives from the themes, the decor, mail
## stacks, the doors and their thresholds, the sharks and the gator, and no monster packs, notes, scouts or van.

const SEED := 4242
const LEVEL := 3                   ## the gym's floor level (the cave's rock too)
const SEWER_LEVEL := 1             ## the sewer cluster's floor (its water one level below)
const WALL_RISE := 4               ## a wall stands this many levels over the highest floor beside it
const RIM_FRONT := 3               ## the cave's rim over its rock: on the camera's side ...
const RIM_BACK := 6                ## ... and at the back
const BED_DROP := 5                ## the lava bed below the rock (CaveGen's)
const LAVA_DROP := 2               ## the lava's surface below the rock (CaveGen's)
const CAVE_RADIUS := 11
const CHAMBER_R := 3
const NECK_R := 3                  ## rock round the cave's doorway (the hall in ends on rock, not over lava)
const D := Hex.DIRS
const CAMERA := Vector3(0.7071, 0.0, 0.7071)

## [id, theme, radius] in tag order (room:N is the N-th row). The course (a rectangle) and the cave chambers are laid out
## by their own code; their radius is unused (course) or the chamber's.
const ROOMS := [
	["lobby", "service_entrance", 5],
	["arena", "service_entrance", 9],
	["course", "service_entrance", 0],
	["cinema", "home_cinema", 6],
	["cellar", "wine_cellar", 5],
	["server", "server_room", 5],
	["lab", "lab", 5],
	["throne", "throne_room", 6],
	["torture", "torture_chamber", 5],
	["pool", "pool", 6],
	["moat", "moat", 7],
	["barracks", "barracks", 5],
	["sewer_a", "sewer", 6],
	["sewer_b", "sewer", 5],
	["sewer_c", "sewer", 5],
	["cave_a", "lava", CHAMBER_R],
	["cave_b", "lava", CHAMBER_R],
]
## [from, to, dir, hall length (cells between the two border cells), lanes (0 narrow 3.0: a door; 1 wide 4.5: open)]. The
## `to` room's centre follows from `from`'s (along DIRS[dir]), except the course and the cave (their own layout).
const LINKS := [
	["arena", "lobby", 3, 8, 1],
	["arena", "course", 0, 6, 1],
	["arena", "cinema", 2, 6, 0],
	["cinema", "cellar", 3, 6, 0],
	["cinema", "server", 1, 6, 0],
	["cinema", "lab", 2, 6, 0],
	["cellar", "throne", 2, 6, 0],
	["cellar", "torture", 4, 6, 0],
	["arena", "pool", 5, 6, 1],
	["pool", "moat", 0, 6, 0],
	["arena", "barracks", 1, 6, 1],
	["barracks", "sewer_a", 1, 7, 0],   # the service stair, LEVEL down to SEWER_LEVEL
	["sewer_a", "sewer_b", 0, 6, 0],    # a narrow hall: flooded wall to wall, sluices at both ends
	["sewer_a", "sewer_c", 2, 6, 1],    # a wide hall: its channel and a dry ledge
	["arena", "cave_a", 4, 6, 0],
]
const SEWER_ROOMS: Array[String] = ["sewer_a", "sewer_b", "sewer_c"]
const BARE_ROOMS: Array[String] = ["arena", "course"]   ## nothing is planned in them (props, explosives, decor, mail)
const GATE_ROOM := "throne"
const STAFF := [["server", "staff", 0], ["lab", "henchman", 3]]   ## [room, style, the direction of its spot off the centre]

## The course, along +X from the arena's hall: [from x (world, from COURSE_X0), kind, level offset, floor material].
const COURSE_X0 := 25.0
const COURSE_HALF := 6.0           ## |z| of the course's floor
const COURSE := [
	[0.0, "pad", 0, FloorMaterials.F_CONCRETE],
	[6.0, "slalom", 0, FloorMaterials.F_CARPET],
	[18.0, "steps", 1, FloorMaterials.F_WOOD],     # +1, +2, +3 every 2 units
	[24.0, "top", 3, FloorMaterials.F_MARBLE],
	[28.0, "drop", 0, FloorMaterials.F_TILE],      # a 3-level drop off the top
	[34.0, "ledge", 2, FloorMaterials.F_FLAGSTONE],  # a +2 climb (the mantle) and a 2-level drop
	[40.0, "flat", 0, FloorMaterials.F_CONCRETE],
	[44.0, "materials", 0, -1],                    # one band of each floor material
]
const PILLARS: Array[Vector2] = [Vector2(8.0, -2.5), Vector2(11.5, 2.5), Vector2(15.0, -2.5)]   ## (x from COURSE_X0, z)
const BAND := 2.0                  ## the material walk: each band this wide (world X)

static var _layout: Dictionary = {}


## The rooms' tags, centres and radii, the halls' door cells and the course's extent, from the tables (pure, cached).
## {rooms: {id: {tag, theme, center, r}}, links: [{a, b, dir, n, lanes, door_a, door_b}], course_x1}
static func layout() -> Dictionary:
	if not _layout.is_empty():
		return _layout
	var rooms := {}
	for i in ROOMS.size():
		var row: Array = ROOMS[i]
		rooms[row[0]] = {"id": row[0], "tag": "room:%d" % i, "theme": row[1], "r": int(row[2]), "center": Vector2i.ZERO}
	(rooms["arena"] as Dictionary)["center"] = Vector2i.ZERO
	var links: Array = []
	for row: Array in LINKS:
		var a: Dictionary = rooms[row[0]]
		var b: Dictionary = rooms[row[1]]
		var dir := int(row[2])
		var n := int(row[3])
		var door_a: Vector2i = a["center"] + D[dir] * int(a["r"])
		var door_b: Vector2i = door_a + D[dir] * n
		if str(b["id"]) != "course":
			b["center"] = door_b + D[dir] * int(b["r"])   # (the cave's entry chamber too: it sits on the cave's rim)
		links.append({"a": a["id"], "b": b["id"], "dir": dir, "n": n, "lanes": int(row[4]), "door_a": door_a, "door_b": door_b})
	var cave_c: Vector2i = (rooms["cave_a"] as Dictionary)["center"] + D[4] * (CAVE_RADIUS - CHAMBER_R)
	(rooms["cave_b"] as Dictionary)["center"] = cave_c + D[4] * (CAVE_RADIUS - CHAMBER_R - 1)
	var x1 := COURSE_X0 + float(COURSE[COURSE.size() - 1][0]) + BAND * FloorMaterials.FLOORS.size()
	_layout = {"rooms": rooms, "links": links, "course_x1": x1, "cave_center": cave_c}
	return _layout


static func tag_of(id: String) -> String:
	return str((layout()["rooms"][id] as Dictionary)["tag"])


static func center_of(id: String) -> Vector2i:
	return (layout()["rooms"][id] as Dictionary)["center"]


## The id of a room tag ("" when it is none of the gym's rooms).
static func id_of(tag: String) -> String:
	for id: String in layout()["rooms"]:
		if str((layout()["rooms"][id] as Dictionary)["tag"]) == tag:
			return id
	return ""


## What the course is at world (x, z): [kind ("floor" / "wall"), level, floor material]; x from COURSE_X0.
static func course_feature(x: float, z: float) -> Array:
	var dx := x - COURSE_X0
	for p in PILLARS:
		if Vector2(dx, z).distance_to(p) < 1.1:
			return ["wall", LEVEL, FloorMaterials.F_CONCRETE]
	var seg: Array = COURSE[0]
	for row: Array in COURSE:
		if dx >= float(row[0]):
			seg = row
	var lv := LEVEL + int(seg[2])
	var mat := int(seg[3])
	match str(seg[1]):
		"steps":
			lv = LEVEL + 1 + clampi(int((dx - float(seg[0])) / 2.0), 0, 2)
		"materials":
			mat = clampi(int((dx - float(seg[0])) / BAND), 0, FloorMaterials.FLOORS.size() - 1)
	return ["floor", lv, mat]


## The gym as a HexMap (the plan's terrain changes, the pools and the sewer's water, are made by plan()).
static func build_map() -> HexMap:
	var L := layout()
	var rooms: Dictionary = L["rooms"]
	var b := SewerLayouts.Builder.new()
	var level := {}      ## cell -> level (missing: LEVEL)
	var cave := _cave(L, b, level)
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		if id == "course" or id.begins_with("cave_"):
			continue
		b.room(r["center"], int(r["r"]), str(r["tag"]))
		if (SEWER_ROOMS as Array).has(id):
			for c in Hex.range_cells(r["center"], int(r["r"])):
				level[c] = SEWER_LEVEL
	# the course: a rectangle of cells (its walls and levels from course_feature)
	var x1 := float(L["course_x1"])
	var course_tag := tag_of("course")
	var pillars: Array[Vector2i] = []
	var lo := Hex.from_world(Vector3(COURSE_X0, 0, -COURSE_HALF))
	var hi := Hex.from_world(Vector3(x1, 0, COURSE_HALF))
	for r in range(lo.y - 1, hi.y + 2):
		for q in range(lo.x - 6, hi.x + 6):
			var c := Vector2i(q, r)
			var w := Hex.to_world(c)
			if w.x < COURSE_X0 or w.x > x1 or absf(w.z) > COURSE_HALF:
				continue
			var f := course_feature(w.x, w.z)
			b.cells[c] = course_tag
			level[c] = int(f[1])
			if str(f[0]) == "wall":
				pillars.append(c)
	var halls := {}
	for lk: Dictionary in L["links"]:
		var id := "%s-%s" % [lk["a"], lk["b"]]
		var route := b.hall(id, lk["door_a"], int(lk["dir"]), int(lk["n"]), int(lk["lanes"]))
		halls[id] = {"route": route, "link": lk}
		if str(lk["b"]) == "sewer_a":
			_stair_levels(b.hall_cells[id], route, LEVEL, SEWER_LEVEL, level)
		elif (SEWER_ROOMS as Array).has(str(lk["a"])):
			for c: Vector2i in b.hall_cells[id]:
				level[c] = SEWER_LEVEL
	# the cave's doorway ends on rock: no lava next to anything that is not the cave's
	_neck(cave, b, level)
	var m := _make_map(b, level, pillars, cave)
	_elevator(m, center_of("lobby"), tag_of("lobby"))
	_cave_record(m, L, cave, b)
	_sewer_record(m, L, halls, b)
	return m


## The plan (SiteBuilder.plan's steps with the gym's choices: fixed themes, the gate and the staff where the table says, no
## packs, no notes, no van). Changes the map's terrain as a floor plan does (the sewer's water, the pools, the materials).
static func plan(m: HexMap, run: ContractRun, floor_n: int) -> SitePlan:
	var L := layout()
	var p := SitePlan.new()
	p.floor_number = floor_n
	p.start = m.cells_with_tag("start")[0]
	p.exit = m.cells_with_tag("exit")[0]
	p.dispatch = "Test gym."
	SiteBuilder._index_rooms(m, p)
	var avoid := {}
	for c in Hex.range_cells(p.start, SiteBuilder.START_CLEAR):
		avoid[c] = true
	for c in Hex.range_cells(p.exit, SiteBuilder.EXIT_CLEAR):
		avoid[c] = true
	p.elevator = m.elevator.duplicate(true)
	p.elevator["look"] = run.elevator_look
	for c in ElevatorGeo.keep_cells(p.elevator):
		avoid[c] = true
	var bare := {}
	for id in BARE_ROOMS:
		for c: Vector2i in (p.rooms.get(tag_of(id), []) as Array):
			avoid[c] = true
			bare[c] = true
	var near_corr := SiteBuilder._corridor_zone(m)
	SewerPlanner.plan(m, run, floor_n, p)
	var gate_cell := _free_near(m, center_of(GATE_ROOM))
	p.gates.append({"cell": gate_cell, "origin": false, "room": tag_of(GATE_ROOM)})
	for i in STAFF.size():
		var row: Array = STAFF[i]
		var c := _free_near(m, center_of(row[0]) + D[int(row[2])] * 2)
		var names: Array[String] = SiteBuilder.HENCHMAN_NAMES if str(row[1]) == "henchman" else SiteBuilder.STAFF_NAMES
		p.employees.append({"cell": c, "name": names[i % names.size()], "style": row[1], "room": tag_of(row[0])})
	for id: String in L["rooms"]:
		p.room_themes[tag_of(id)] = str((L["rooms"][id] as Dictionary)["theme"])
	SewerPlanner.theme(m, p)
	LavaPlanner.theme(m, p)
	PoolGeo.carve(m, p, avoid, near_corr, SEED * 613 + 1)
	var ctx := ThemeCtx.make(m, p, avoid, near_corr, SEED * 919 + 3)
	SiteBuilder._elevator_body(p, ctx)
	p.van = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 131 + 5
	var catalog: Array[String] = PricedProp.catalog("bunker")
	catalog.append_array(PricedProp.catalog("lair"))
	PropPlanner.plan(m, run, p, rng, avoid, near_corr, catalog, ctx)
	HazardPlanner.plan(m, run, floor_n, p, avoid, near_corr, ctx)
	HazardPlanner.plan_sewer(m, run, floor_n, p, avoid, near_corr, ctx)
	RoomThemes.plan_decor(ctx)
	SewerPlanner.dress(m, run, p)
	PackagePlanner.plan(m, run, floor_n, p, ctx)
	# the arena and the course stay bare
	for key in ["props", "hazards", "decor", "packages"]:
		var kept: Array[Dictionary] = []
		for e: Dictionary in (p.get(key) as Array[Dictionary]):
			if not bare.has(e.get("cell", HexMap.NO_CELL)):
				kept.append(e)
		p.set(key, kept)
	p.pack_budgets = {}
	SiteBuilder._block_cells(p)
	FloorMaterials.assign(m, p, run.site_type)
	SewerPlanner.materials(m, p)
	LavaPlanner.materials(m, p)
	_course_materials(m)
	DoorPlanner.plan(m, run, floor_n, p)
	# a regular shark in each pool (the pool and the moat: SharkPlanner's layout, every floor)
	for i in m.pools.size():
		var rec: Dictionary = m.pools[i]
		if bool(rec.get("body", false)):
			continue
		var hole: Array = rec.get("hole", [])
		var start: Vector2 = rec["center"]
		var heading: Vector2 = rec["axis"]
		if not hole.is_empty():
			var ol: Array = rec["outline"]
			var a: Vector2 = ((ol[0] as Vector2) + (hole[0] as Vector2)) * 0.5
			var c2: Vector2 = ((ol[1 % ol.size()] as Vector2) + (hole[1 % hole.size()] as Vector2)) * 0.5
			start = a.lerp(c2, 0.5)
			heading = (c2 - a).normalized()
		else:
			start -= heading * 0.6
		rec["shark"] = "regular"
		p.sharks.append({"pool": i, "variant": "regular", "start": start, "heading": heading})
	GatorPlanner.plan(m, run, floor_n, p)
	return p


# --- building ----------------------------------------------------------------------------------------------------------

## The cave's cells into the builder (chambers, bridge, isle, lava) and its parts: {center, rock: {cell: level}, kind:
## {cell: tag}, lava: {cell: true}, bridge: [cells], isle: {...}, door}.
static func _cave(L: Dictionary, b: SewerLayouts.Builder, level: Dictionary) -> Dictionary:
	var C: Vector2i = L["cave_center"]
	var a: Dictionary = L["rooms"]["cave_a"]
	var bb: Dictionary = L["rooms"]["cave_b"]
	var door: Vector2i = HexMap.NO_CELL
	for lk: Dictionary in L["links"]:
		if str(lk["b"]) == "cave_a":
			door = lk["door_b"]
	var rock := {}
	var kind := {}
	for ch: Dictionary in [a, bb]:
		for c in Hex.range_cells(ch["center"], int(ch["r"])):
			rock[c] = LEVEL
			kind[c] = str(ch["tag"])
	# the bridge: two wide, from chamber A's rock to chamber B's
	var from: Vector2i = a["center"] + D[4] * int(a["r"])
	var to: Vector2i = bb["center"] - D[4] * int(bb["r"])
	var bridge: Array[Vector2i] = []
	var rows: Array = []
	for c in Hex.line(from, to):
		var row: Array[Vector2i] = [c, c + D[5]]
		rows.append(row)
		for x in row:
			if not rock.has(x):
				rock[x] = LEVEL
				kind[x] = "corridor"
				bridge.append(x)
	var zone: Array[Vector2i] = []
	for c in Hex.range_cells(C, CAVE_RADIUS):
		zone.append(c)
	for c in Hex.range_cells(door, NECK_R):
		if Hex.distance(c, C) <= CAVE_RADIUS and not rock.has(c):
			rock[c] = LEVEL
			kind[c] = str(a["tag"])
	var lava := {}
	for c in zone:
		if not rock.has(c):
			lava[c] = true
	var isle := _isle(C, rock, kind, lava)
	for c: Vector2i in rock:
		b.cells[c] = kind[c]
		level[c] = int(rock[c])
	for c: Vector2i in lava:
		b.cells[c] = "lava"
		level[c] = LEVEL - BED_DROP
	return {"center": C, "rock": rock, "kind": kind, "lava": lava, "bridge": bridge, "rows": rows, "isle": isle, "door": door,
		"zone": zone}


## The isle (CaveGen's rule): seven cells, its middle a level up, two lava cells off the rock (one if two cannot be crusted),
## a ring of lava round it, a shore cell whose weakest damp crust makes a walk onto it; the camera's side first.
static func _isle(C: Vector2i, rock: Dictionary, kind: Dictionary, lava: Dictionary) -> Dictionary:
	for want_gap: int in [3, 2]:
		var cands: Array = []
		for c in Hex.range_cells(C, CAVE_RADIUS - 3):
			var ok := true
			var gap := 99
			for x in Hex.range_cells(c, 2):
				if not lava.has(x):
					ok = false
					break
			if not ok:
				continue
			for x in Hex.range_cells(c, 1):
				for r: Vector2i in rock:
					gap = mini(gap, Hex.distance(x, r))
			if gap != want_gap:
				continue
			cands.append([-(Hex.to_world(c) - Hex.to_world(C)).dot(CAMERA), c])
		cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and HexMap._cell_less(x[1], y[1])))
		for cand: Array in cands:
			var c: Vector2i = cand[1]
			var isle_set := {}
			for x in Hex.range_cells(c, 1):
				isle_set[x] = LEVEL + (1 if x == c else 0)
			var lava2 := lava.duplicate()
			for x: Vector2i in isle_set:
				lava2.erase(x)
			var present := func(x: Vector2i) -> bool: return rock.has(x) or lava2.has(x) or isle_set.has(x)
			var shores: Array[Vector2i] = []
			for r: Vector2i in rock:
				if Hex.distance(r, c) <= want_gap + 1 and str(kind[r]) != "isle":
					shores.append(r)
			shores.sort_custom(HexMap._cell_less)
			for s in shores:
				var crust := CaveGen.crust_cells(Hex.to_world(s), CaveGen.crust_reach(), lava2, present)
				if CaveGen.crust_path(rock, isle_set, crust, s, LEVEL - 1):
					for x: Vector2i in isle_set:
						lava.erase(x)
						rock[x] = isle_set[x]
						kind[x] = "isle"
					var cells: Array = isle_set.keys()
					cells.sort_custom(HexMap._cell_less)
					return {"center": c, "cells": cells, "shore": s, "level": LEVEL, "gap": want_gap - 1}
	push_warning("GymMap: no isle fits the cave")
	return {}


## No lava next to a cell that is not the cave's (the hall in): rock instead, the entry chamber's.
static func _neck(cave: Dictionary, b: SewerLayouts.Builder, level: Dictionary) -> void:
	var lava: Dictionary = cave["lava"]
	var rock: Dictionary = cave["rock"]
	var kind: Dictionary = cave["kind"]
	var a_tag := tag_of("cave_a")
	var keys: Array = lava.keys()
	keys.sort_custom(HexMap._cell_less)
	for c: Vector2i in keys:
		var foreign := false
		for nb in Hex.neighbors(c):
			if b.cells.has(nb) and not lava.has(nb) and not rock.has(nb):
				foreign = true
		if foreign:
			lava.erase(c)
			rock[c] = LEVEL
			kind[c] = a_tag
			b.cells[c] = a_tag
			level[c] = LEVEL


## The cells with walls round them, midpoint-cut: rooms flagstone, halls corridor stone, walls rough stone (the plan's
## FloorMaterials.assign restyles them), each wall WALL_RISE over the highest floor beside it, the cave's rim higher.
static func _make_map(b: SewerLayouts.Builder, level: Dictionary, pillars: Array[Vector2i], cave: Dictionary) -> HexMap:
	var m := HexMap.new()
	var room_mat := FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var corr_mat := FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)
	var keys: Array = b.cells.keys()
	keys.sort_custom(HexMap._cell_less)
	for c: Vector2i in keys:
		var cell := m.set_cell(c, int(level.get(c, LEVEL)))
		cell.tag = str(b.cells[c])
		cell.mat_id = corr_mat if cell.tag == "corridor" else room_mat
	var lava: Dictionary = cave["lava"]
	var mid := Vector3.ZERO
	for c: Vector2i in lava:
		mid += Hex.to_world(c)
	mid /= maxf(1.0, float(lava.size()))
	var walls := {}
	for c: Vector2i in keys:
		for nb in Hex.neighbors(c):
			if not b.cells.has(nb):
				walls[nb] = maxi(int(walls.get(nb, -100)), int(level.get(c, LEVEL)) + WALL_RISE)
	for c in pillars:
		walls[c] = LEVEL + WALL_RISE
	for c: Vector2i in walls:
		var lv: int = walls[c]
		for nb in Hex.neighbors(c):
			if lava.has(nb):
				var front := (Hex.to_world(c) - mid).dot(CAMERA) > 0.0
				lv = maxi(lv, LEVEL + (RIM_FRONT if front else RIM_BACK))
		m.set_cell(c, lv, HexMap.Tile.WALL).mat_id = room_mat
	m.cut_walls()
	return m


## A hall's levels down a stair: `hi` at the top door, `lo` at the foot, a step a third of the way along.
static func _stair_levels(cells: Array, route: Array[Vector2i], hi: int, lo: int, level: Dictionary) -> void:
	var a := Hex.to_world(route[0])
	var dv := Hex.to_world(route[route.size() - 1]) - a
	var len2 := dv.length_squared()
	for c: Vector2i in cells:
		var t := clampf((Hex.to_world(c) - a).dot(dv) / len2, 0.0, 1.0)
		level[c] = hi - clampi(int(t * float(hi - lo + 1)), 0, hi - lo)


## The free-standing elevator in the lobby (SewerLayouts' landing room: its door toward the camera) and the start / exit tags.
static func _elevator(m: HexMap, center: Vector2i, room_tag: String) -> void:
	var rec := ElevatorGeo.make_free(center, 5, LEVEL, int(room_tag.trim_prefix("room:")))
	for poly in ElevatorGeo.solids(rec):
		m.add_solid(poly)
	for c: Vector2i in (rec["cells"] as Array):
		m.no_stand[c] = true
	m.elevator = rec
	var landing: Vector2i = rec["landing"]
	m.get_cell(landing).tag = "exit"
	m.get_cell(landing + D[1]).tag = "start"


## HexMap.cave and HexMap.lava, in the generated record's shape (CaveGen.finish), so LavaPlanner, LavaField, LavaLook and
## the fog treat it as a generated cave.
static func _cave_record(m: HexMap, L: Dictionary, cave: Dictionary, b: SewerLayouts.Builder) -> void:
	var rock_list: Array[Vector2i] = []
	for c: Vector2i in cave["rock"]:
		rock_list.append(c)
	rock_list.sort_custom(HexMap._cell_less)
	var lava_list: Array[Vector2i] = []
	for c: Vector2i in cave["lava"]:
		lava_list.append(c)
		m.lava[c] = true
	lava_list.sort_custom(HexMap._cell_less)
	var neck: Array[Vector2i] = []
	for c in Hex.range_cells(cave["door"], 1):
		if (cave["rock"] as Dictionary).has(c):
			neck.append(c)
	var a_tag := tag_of("cave_a")
	var b_tag := tag_of("cave_b")
	var isles: Array = []
	if not (cave["isle"] as Dictionary).is_empty():
		isles.append(cave["isle"])
	m.cave = {
		"seed": SEED, "pattern": "gym", "level": LEVEL, "crust_level": LEVEL - 1, "bed": LEVEL - BED_DROP,
		"lava_y": float(LEVEL - LAVA_DROP) * Hex.LEVEL_HEIGHT, "rooms": [a_tag, b_tag],
		"chambers": [{"room": a_tag, "center": center_of("cave_a"), "r": CHAMBER_R}, {"room": b_tag, "center": center_of("cave_b"), "r": CHAMBER_R}],
		"entry": {"room": a_tag, "door": cave["door"], "from": tag_of("arena"), "neck": neck},
		"far": b_tag, "gate": false,
		"bridges": [{"a": a_tag, "b": b_tag, "rows": cave["rows"], "wide": true}],
		"isles": isles, "archers": [], "rock": rock_list, "lava": lava_list, "joins": [],
	}


## HexMap.sewer in DungeonGen's shape (its "sewer" option's record), so SewerPlanner floods the cluster as on a real floor.
static func _sewer_record(m: HexMap, L: Dictionary, halls: Dictionary, b: SewerLayouts.Builder) -> void:
	var tags: Array[String] = []
	for id in SEWER_ROOMS:
		tags.append(tag_of(id))
	var out: Array = []
	var stair := {}
	var doors: Array[Vector2i] = []
	for id: String in halls:
		var h: Dictionary = halls[id]
		var lk: Dictionary = h["link"]
		var ia := (SEWER_ROOMS as Array).has(str(lk["a"]))
		var ib := (SEWER_ROOMS as Array).has(str(lk["b"]))
		if not ia and not ib:
			continue
		doors.append(lk["door_a"])
		doors.append(lk["door_b"])
		var cells: Array[Vector2i] = []
		for c: Vector2i in b.hall_cells[id]:
			cells.append(c)
		cells.sort_custom(HexMap._cell_less)
		var route: Array[Vector2i] = h["route"]
		if ia and ib:
			var lanes: Array[Vector2i] = []
			var dir := int(lk["dir"])
			for i in range(1, route.size() - 1):
				for k in range(1, int(lk["lanes"]) + 1):
					lanes.append(route[i] + D[(dir + 1) % 6] * k)
			out.append({"a": tag_of(lk["a"]), "b": tag_of(lk["b"]), "door_a": lk["door_a"], "door_b": lk["door_b"],
					"route": route.duplicate(), "lanes": lanes, "cells": cells, "narrow": int(lk["lanes"]) == 0, "loop": false})
		else:
			stair = {"room": tag_of(lk["b"]), "from": tag_of(lk["a"]), "door": lk["door_b"], "door_up": lk["door_a"], "cells": cells,
					"narrow": int(lk["lanes"]) == 0}
	m.sewer = {"seed": SEED, "level": SEWER_LEVEL, "rooms": tags, "stair": stair, "halls": out, "all_doors": doors}


## The course's own floors over FloorMaterials' (its walk of materials) and concrete walls round it.
static func _course_materials(m: HexMap) -> void:
	var tag := tag_of("course")
	for c: Vector2i in m.cells:
		var cell: HexMap.Cell = m.cells[c]
		if cell.tag != tag or cell.type == HexMap.Tile.WALL:
			continue
		var w := Hex.to_world(c)
		cell.mat_id = FloorMaterials.pack(int(course_feature(w.x, w.z)[2]), FloorMaterials.W_CONCRETE)


## The nearest full floor cell to c (c itself when it is one).
static func _free_near(m: HexMap, c: Vector2i) -> Vector2i:
	for r in 5:
		for x in (Hex.ring(c, r) if r > 0 else [c] as Array[Vector2i]):
			if m.is_walkable_cell(x) and not m.no_stand.has(x) and m.get_cell(x).pool_mask == 0:
				return x
	return c


# --- the gym's places (the test, the panel's teleports, the docs) ----------------------------------------------------

## A walkable spot in each environment: {name: cell}. The test walks to every one of them from the start.
static func spots(m: HexMap) -> Dictionary:
	var out := {}
	for id: String in layout()["rooms"]:
		if id == "course":
			continue
		out[id] = _free_near(m, center_of(id))
	var x1 := float(layout()["course_x1"])
	out["course_pad"] = _free_near(m, Hex.from_world(Vector3(COURSE_X0 + 3.0, 0, 0)))
	out["course_top"] = _free_near(m, Hex.from_world(Vector3(COURSE_X0 + 26.0, 0, 0)))
	out["course_ledge"] = _free_near(m, Hex.from_world(Vector3(COURSE_X0 + 37.0, 0, 0)))
	out["course_end"] = _free_near(m, Hex.from_world(Vector3(x1 - 1.5, 0, 0)))
	var rec := m.sewer
	for s: Dictionary in (rec.get("sumps", []) as Array):
		out["sump_" + id_of(str(s["room"]))] = s["cell"]   # (in the water)
	if not m.cave.is_empty():
		var isles: Array = m.cave["isles"]
		if not isles.is_empty():
			out["isle_shore"] = (isles[0] as Dictionary)["shore"]
	return out

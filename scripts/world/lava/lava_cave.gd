class_name LavaCave
extends RefCounted
## LAVA CAVE PROTOTYPE (docs/design/lava-playtest.md; concept: docs/design/sewer-concept.md part 2). Hand-authored cave
## layouts built as a whole floor, for the dev flag `--lava-cave <1-5>` (game.gd) and the lava lab. NOT in the normal
## floor generator: DungeonGen and SiteBuilder never call it.
##
## A cave is a lava plane with raised hex ROCK on it:
##   - CHAMBERS ("room:N"): rough blobs of rock at a base level, a level up here and there, CRAGS (+2, +3) for cover and
##     vantage;
##   - BRIDGES ("corridor", so each is a fog hall and its ends are doorways): rough runs of rock two hexes wide (the user,
##     2026-10-20: "we need 2x wide paths just to avoid falling in"), or ONE hex wide as a risky shortcut;
##   - ISLES: rock with no path to it, holding the ranged monsters the crew must fight at range (the user: "isolated
##     islands no paths to place ranged enemies on"). An isle shares the fog space of the chamber it overlooks, so the
##     archers on it show when that chamber is in view;
##   - LAVA ("lava"): every other cell of the cave, at LAVA_BED, four levels or more below any rock, so nobody walks off
##     an edge. LavaField turns these cells into void once the floor runs (the void-pit rule: a shoved hero is pulled
##     back, a shoved monster falls in and dies) and adds the lava's burn;
##   - the RIM ("rim"): two rings of tall hex columns (6-9) round the back of the cave; on the camera's side the lava
##     simply runs on out of view (a wall there hid the near edge). The rim never touches rock (lava is always between).
## Deterministic: every layout builds the same map (its own seeded generator for the roughness).

const LAVA_BED := -5            ## lava cells sit here until LavaField makes them void
const CRUST_LEVEL := -1         ## damp crust: one level under the shore rock (a step down from rock at 0)
const LAVA_Y := -1.0            ## the lava surface (world units)
const COUNT := 5
const MARGIN := 2               ## lava cells round the rock (cells), before the rim

const D0 := Vector2i(1, 0)
const D1 := Vector2i(1, -1)
const D2 := Vector2i(0, -1)
const D3 := Vector2i(-1, 0)
const D4 := Vector2i(-1, 1)
const D5 := Vector2i(0, 1)


## The layout's data: name, blurb, chambers [[tag, centre, radius, base]], crags [[cell, level]], isles [[tag (the
## space it shares), centre, radius, base]], bridges [{pts (waypoints), w (1 | 2), steps (levels per row)}], start,
## exit, archers [cells], melee [[kind, cell]], and for the plan diagrams: damp [[from, to]] (where a crust opens a
## shortcut), shove [cells] (where a shove into the lava tempts), cover [cells], flow [lines of how a fight goes].
static func layout(id: int) -> Dictionary:
	match id:
		2: return _fork()
		3: return _ring()
		4: return _gauntlet()
		5: return _crag()
	return _causeway()


## 1. THE CAUSEWAY: two chambers and one long two-wide bridge. An archer isle off the bridge's near side covers it; a
## grunt pack holds the far bridgehead. A one-wide goat path on the far side is out of the archers' reach but has no room
## to fight on.
static func _causeway() -> Dictionary:
	return {
		"name": "The Causeway", "blurb": "one long bridge under an archer isle; a goat path round the back",
		"chambers": [["room:0", Vector2i(0, 0), 3, 0], ["room:1", Vector2i(13, -13), 3, 0]],
		"crags": [[Vector2i(-2, 0), 2], [Vector2i(-3, 2), 1], [Vector2i(13, -11), 2], [Vector2i(14, -16), 2]],
		"isles": [["room:0", Vector2i(6, -2), 1, 1]],
		"bridges": [
			{"pts": [Vector2i(4, -4), Vector2i(9, -9)], "w": 2, "steps": [0, 0, 1, 1, 0, 0]},
			{"pts": [Vector2i(0, -4), Vector2i(9, -13)], "w": 1, "steps": [0, 1, 1, 0, 1, 2, 2, 1, 0, 0]},
		],
		"start": Vector2i(-1, 1), "exit": Vector2i(15, -15),
		"archers": [Vector2i(6, -2), Vector2i(7, -2)],
		"melee": [["grunt", Vector2i(11, -11)], ["grunt", Vector2i(12, -12)], ["grunt", Vector2i(11, -12)]],
		"damp": [[Vector2i(6, -6), Vector2i(6, -3)], [Vector2i(4, -6), Vector2i(4, -8)]],
		"shove": [Vector2i(10, -10), Vector2i(8, -8)],
		"cover": [Vector2i(13, -11), Vector2i(-2, 0)],
		"flow": [
			"Entry A: the archers on the isle open up as soon as A is in view (about 7 from the bridge).",
			"Cross the causeway under fire, or shoot the isle first from A's crag; damp the 2-hex gap to rush it.",
			"The grunts meet you at the far bridgehead: two wide, room to fight, and both edges are kill zones.",
			"The goat path (1 wide, far side) is out of arrow range but a single shove ends the crossing.",
		],
	}


## 2. THE FORK: a bridge to a central island with a crag, then two ways on: a short one-wide span straight to the exit
## chamber, or a long two-wide loop round the near side. An archer isle between the two routes covers both.
static func _fork() -> Dictionary:
	return {
		"name": "The Fork", "blurb": "a hub island, then the short narrow span or the long wide loop; archers in between",
		"chambers": [["room:0", Vector2i(0, 0), 3, 0], ["room:1", Vector2i(10, -10), 2, 0], ["room:2", Vector2i(19, -19), 3, 0]],
		"crags": [[Vector2i(-2, 1), 2], [Vector2i(10, -11), 2], [Vector2i(9, -9), 1], [Vector2i(20, -21), 2]],
		"isles": [["room:1", Vector2i(15, -12), 1, 1]],
		"bridges": [
			{"pts": [Vector2i(4, -4), Vector2i(7, -7)], "w": 2, "steps": [0, 1, 1, 0]},
			{"pts": [Vector2i(13, -13), Vector2i(15, -15)], "w": 1, "steps": [0, 1, 0]},
			{"pts": [Vector2i(10, -7), Vector2i(14, -7), Vector2i(19, -12), Vector2i(19, -15)], "w": 2,
				"steps": [0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1]},
		],
		"start": Vector2i(-1, 1), "exit": Vector2i(21, -21),
		"archers": [Vector2i(15, -12), Vector2i(16, -13)],
		"melee": [["grunt", Vector2i(10, -9)], ["grunt", Vector2i(11, -10)], ["grunt", Vector2i(9, -10)], ["swarmer", Vector2i(19, -18)]],
		"damp": [[Vector2i(12, -10), Vector2i(14, -11)], [Vector2i(14, -14), Vector2i(15, -13)]],
		"shove": [Vector2i(8, -8), Vector2i(14, -14), Vector2i(16, -9)],
		"cover": [Vector2i(10, -11), Vector2i(9, -9)],
		"flow": [
			"Entry A, bridge to the hub B: the grunts on B come at you on the bridge (shove them off).",
			"B's crag is cover from the isle's archers and the vantage over both routes.",
			"Short way: the 1-wide span, 3 hexes, archers 4 away: fast, exposed, one shove from the lava.",
			"Long way: the 2-wide loop round the near side, longer under the isle but room to fight the imps at C.",
			"Damp from B's east edge crusts the 1-hex gap to the isle: melee can go and clear it.",
		],
	}


## 3. THE RING: three chambers round a lava lake with an archer isle in the middle, two-wide bridges A-B and B-C round the
## back and a one-wide span A-C straight across the front, under the isle. A brute holds the B-C bridge.
static func _ring() -> Dictionary:
	return {
		"name": "The Ring", "blurb": "three chambers round a lake, archers on the centre isle, a brute on the back bridge",
		"chambers": [["room:0", Vector2i(0, 0), 3, 0], ["room:1", Vector2i(4, -12), 3, 0], ["room:2", Vector2i(16, -16), 3, 0]],
		"crags": [[Vector2i(-2, 1), 2], [Vector2i(3, -13), 2], [Vector2i(5, -14), 1], [Vector2i(17, -18), 2]],
		"isles": [["room:0", Vector2i(7, -9), 1, 1]],
		"bridges": [
			{"pts": [Vector2i(0, -4), Vector2i(0, -6), Vector2i(2, -8)], "w": 2, "steps": [0, 1, 1, 0, 0]},
			{"pts": [Vector2i(8, -12), Vector2i(12, -12)], "w": 2, "steps": [0, 0, 1, 1, 0]},
			{"pts": [Vector2i(4, -3), Vector2i(13, -12)], "w": 1, "steps": [0, 1, 1, 0, 0, 1, 2, 1, 1, 0]},
		],
		"start": Vector2i(-1, 1), "exit": Vector2i(18, -18),
		"archers": [Vector2i(7, -9), Vector2i(8, -10)],
		"melee": [["grunt", Vector2i(4, -11)], ["grunt", Vector2i(5, -12)], ["grunt", Vector2i(3, -11)], ["brute", Vector2i(10, -12)]],
		"damp": [[Vector2i(7, -5), Vector2i(7, -8)], [Vector2i(2, -7), Vector2i(5, -8)]],
		"shove": [Vector2i(10, -12), Vector2i(1, -6), Vector2i(8, -7)],
		"cover": [Vector2i(3, -13), Vector2i(-2, 1)],
		"flow": [
			"Entry A: the isle's archers cover the front span and both bridges; nowhere is fully out of reach.",
			"Front: the 1-wide span A-C is the short way, straight under the isle: a sprint under fire.",
			"Back: bridge A-B into the grunts at B (crag cover), then the brute on the B-C bridge: shove it off before it shoves you.",
			"Damp from the span or from bridge A-B crusts the lake to the isle (2 hexes).",
		],
	}


## 4. THE GAUNTLET: one long two-wide bridge between two chambers with an archer isle on each side, and the pack charging
## down the bridge from the far end.
static func _gauntlet() -> Dictionary:
	return {
		"name": "The Gauntlet", "blurb": "a long wide bridge between two archer isles; the pack comes down it at you",
		"chambers": [["room:0", Vector2i(0, 0), 3, 0], ["room:1", Vector2i(16, -16), 3, 0]],
		"crags": [[Vector2i(-2, 1), 2], [Vector2i(1, -2), 1], [Vector2i(16, -18), 2], [Vector2i(14, -15), 1]],
		"isles": [["room:0", Vector2i(6, -2), 1, 1], ["room:1", Vector2i(10, -14), 1, 1]],
		"bridges": [
			{"pts": [Vector2i(4, -4), Vector2i(12, -12)], "w": 2, "steps": [0, 0, 1, 1, 0, -1, 0, 1, 0]},
		],
		"start": Vector2i(-1, 1), "exit": Vector2i(18, -18),
		"archers": [Vector2i(6, -2), Vector2i(10, -14), Vector2i(11, -15)],
		"melee": [["grunt", Vector2i(13, -13)], ["grunt", Vector2i(14, -14)], ["grunt", Vector2i(14, -13)], ["brute", Vector2i(15, -15)]],
		"damp": [[Vector2i(10, -11), Vector2i(10, -13)], [Vector2i(6, -6), Vector2i(6, -3)]],
		"shove": [Vector2i(8, -8), Vector2i(9, -9), Vector2i(10, -10)],
		"cover": [Vector2i(-2, 1), Vector2i(1, -2)],
		"flow": [
			"Entry A: the near isle shoots into A; clear it from A's crags (Wick's bow, fireball) before stepping out.",
			"Mid-bridge: the pack comes down the bridge two abreast; the middle third is where everyone gets shoved.",
			"The far isle covers the last third and the bridgehead; damp from the bridge reaches it (2 hexes).",
			"No way round: the fight is the bridge.",
		],
	}


## 5. THE CRAG: a short bridge into a big middle chamber with crag pillars for cover, then a two-wide ramp up to the exit
## shelf with a two-level climb in it, under an archer tower too high for any crust to reach.
static func _crag() -> Dictionary:
	return {
		"name": "The Crag", "blurb": "a pillared middle chamber, then a climb to the exit shelf under a sniper tower",
		"chambers": [["room:0", Vector2i(0, 0), 3, 0], ["room:1", Vector2i(10, -10), 3, 0], ["room:2", Vector2i(15, -21), 2, 3]],
		"crags": [[Vector2i(-2, 1), 2], [Vector2i(9, -9), 2], [Vector2i(11, -8), 2], [Vector2i(8, -11), 2], [Vector2i(16, -22), 4]],
		"isles": [["room:1", Vector2i(14, -16), 1, 2]],
		"bridges": [
			{"pts": [Vector2i(4, -4), Vector2i(6, -6)], "w": 2, "steps": [0, 1, 0]},
			{"pts": [Vector2i(11, -14), Vector2i(11, -16), Vector2i(13, -18)], "w": 2, "steps": [0, 1, 1, 3, 3]},
		],
		"start": Vector2i(-1, 1), "exit": Vector2i(16, -21),
		"archers": [Vector2i(14, -16), Vector2i(15, -17)],
		"melee": [["grunt", Vector2i(10, -10)], ["grunt", Vector2i(11, -11)], ["grunt", Vector2i(9, -11)], ["swarmer", Vector2i(15, -20)]],
		"damp": [[Vector2i(12, -13), Vector2i(13, -15)]], "climb": true,
		"shove": [Vector2i(11, -15), Vector2i(12, -17), Vector2i(7, -7)],
		"cover": [Vector2i(9, -9), Vector2i(11, -8), Vector2i(8, -11)],
		"flow": [
			"Entry A, short bridge into B: grunts among the pillars; the pillars block the tower's arrows.",
			"The ramp to C has a two-level climb (slow, no attacks) in the tower's sights: shoot the tower first.",
			"Damp crusts the gap to the tower's foot, but the tower is 3 up from the crust: a crust can't climb it.",
			"At the top the imps swarm the climb: fight at the top of the ramp, not on it.",
		],
	}


# --- building ---------------------------------------------------------------------------------------------------

## The bridge's rows: [[route cell, lane cell or NO], ...] along its waypoints (one-wide: no lanes).
static func bridge_rows(b: Dictionary) -> Array:
	var pts: Array = b["pts"]
	var rows: Array = []
	var seen := {}
	for i in pts.size() - 1:
		var line := Hex.line(pts[i], pts[i + 1])
		for j in line.size():
			var c: Vector2i = line[j]
			if seen.has(c):
				continue
			seen[c] = true
			var nxt: Vector2i = line[j + 1] if j + 1 < line.size() else (c + (c - line[j - 1]) if j > 0 else c + D1)
			var d := Hex.dir_to(c, nxt)
			if d < 0:
				d = 1
			var lane: Vector2i = c + Hex.DIRS[(d + 1) % 6] if int(b["w"]) >= 2 else HexMap.NO_CELL
			rows.append([c, lane])
	return rows


## Every rock cell of the layout: cell -> [tag, level]. Rough: a chamber or isle cell sits a level up now and then
## (never next to a dip), an edge cell a level down now and then; crags and bridges as given.
static func rock(id: int) -> Dictionary:
	var L := layout(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * id + 13
	var out := {}
	for ch: Array in L["chambers"] + L["isles"]:
		_blob(out, ch[1], int(ch[2]), str(ch[0]), int(ch[3]), rng)
	for cr: Array in L["crags"]:
		var c: Vector2i = cr[0]
		var tag := str(out[c][0]) if out.has(c) else "room:0"
		out[c] = [tag, int(cr[1])]
	for b: Dictionary in L["bridges"]:
		var steps: Array = b["steps"]
		var rows := bridge_rows(b)
		for i in rows.size():
			var lv := int(steps[i % steps.size()])
			for c: Vector2i in rows[i]:
				if c == HexMap.NO_CELL or (out.has(c) and str(out[c][0]) != "corridor"):
					continue
				out[c] = ["corridor", lv]
	return out


static func _blob(out: Dictionary, centre: Vector2i, radius: int, tag: String, base: int, rng: RandomNumberGenerator) -> void:
	var cells := Hex.range_cells(centre, radius)
	var up := {}
	for c in cells:
		if Hex.distance(c, centre) < radius and rng.randf() < 0.28:
			up[c] = true
	for c in cells:
		var lv := base + (1 if up.has(c) else 0)
		if not up.has(c) and Hex.distance(c, centre) == radius and radius > 1 and rng.randf() < 0.15:
			var near_up := false
			for n in Hex.neighbors(c):
				near_up = near_up or up.has(n)
			if not near_up:
				lv = base - 1
		out[c] = [tag, lv]


## The cave as a HexMap: rock, lava round it, the rim round that; the start and exit tags; floor / wall materials (rock:
## flagstone, bridges: corridor stone; the lava look restyles them, LavaLook).
static func build_map(id: int) -> HexMap:
	var L := layout(id)
	var rk := rock(id)
	var region := {}
	for c: Vector2i in rk:
		var reach := MARGIN + (1 if posmod(hash(c * 31 + Vector2i(id, 7)), 5) == 0 else 0)
		for n in Hex.range_cells(c, reach):
			region[n] = true
	# no lone lava cell poking into the rim (it would show as a glowing hole in the wall)
	var lone: Array[Vector2i] = []
	for c: Vector2i in region:
		if rk.has(c):
			continue
		var around := 0
		for n in Hex.neighbors(c):
			around += 1 if region.has(n) else 0
		if around < 3:
			lone.append(c)
	for c in lone:
		region.erase(c)
	var m := HexMap.new()
	var rock_mat := FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var bridge_mat := FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)
	for c: Vector2i in region:
		if rk.has(c):
			var cell := m.set_cell(c, int(rk[c][1]))
			cell.tag = str(rk[c][0])
			cell.mat_id = bridge_mat if cell.tag == "corridor" else rock_mat
		else:
			var lv := m.set_cell(c, LAVA_BED)
			lv.tag = "lava"
			lv.mat_id = rock_mat
	# the rim: two rings outside the cave, tall at the back; on the camera's side (+X+Z) the same rings are more lava
	var rock_list: Array[Vector2i] = []
	for c: Vector2i in rk:
		rock_list.append(c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 + id
	var rim_cells: Array[Vector2i] = []
	for c: Vector2i in region:
		for n in Hex.range_cells(c, 2):
			if not region.has(n) and not m.has_cell(n):
				rim_cells.append(n)
				m.set_cell(n, 0)
	rim_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for c in rim_cells:
		var p := Hex.to_world(c)
		var best := INF
		var nearest := Vector3.ZERO
		for r in rock_list:
			var d := Hex.to_world(r).distance_squared_to(p)
			if d < best:
				best = d
				nearest = Hex.to_world(r)
		var front := (p - nearest).dot(Vector3(0.707, 0, 0.707)) > 0.0
		var cell := m.get_cell(c)
		if front:
			# no wall on the camera's side: the lava runs on out of view (a wall there hid the near edge and read as floor)
			cell.level = LAVA_BED
			cell.tag = "lava"
			cell.mat_id = FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
			continue
		cell.level = rng.randi_range(6, 9)
		cell.tag = "rim"
		cell.mat_id = FloorMaterials.pack(FloorMaterials.F_CARPET, FloorMaterials.W_STONE)   # (dim seams: LavaLook makes it near black)
	m.get_cell(L["start"]).tag = "start"
	m.get_cell(L["exit"]).tag = "exit"
	return m


## The lava cells of a built map (before LavaField makes them void).
static func lava_cells(m: HexMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in m.cells:
		if m.cells[c].tag == "lava":
			out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


## A minimal site plan for the cave: the rooms, start and exit (no gates, employees, props, decor, notes, mail, packs, van
## or doors: the cave's monsters come from spawn_monsters).
static func plan(m: HexMap, floor_n: int) -> SitePlan:
	var p := SitePlan.new()
	p.floor_number = floor_n
	p.start = m.cells_with_tag("start")[0]
	p.exit = m.cells_with_tag("exit")[0]
	SiteBuilder._index_rooms(m, p)
	p.dispatch = "Lava cave (prototype)."
	return p


## The layout's monsters: archers on the isles, the melee pack on the path. Appended to the site's monsters (and its pest
## count, as the packs would).
static func spawn_monsters(id: int, site: SiteBuilder.Site) -> void:
	var L := layout(id)
	var list: Array = []
	for c: Vector2i in L["archers"]:
		list.append(["archer", c])
	list.append_array(L["melee"])
	for e: Array in list:
		var kind := str(e[0])
		var m := MonsterFactory.spawn(kind, e[1])
		if m == null:
			continue
		site.monsters.append(m)
		if site.pest == "everything" or kind == site.pest:
			site.pest_spawned += 1


## Checks a layout (tests and the lab): the exit is reached from the start on two-wide bridges alone (the one-wide spans
## removed; without climbing unless the layout has "climb": the Crag's ramp), every archer stands on rock no path reaches, and every two-wide bridge row has its
## lane. Returns {ok, problems: [...]}.
static func check(id: int) -> Dictionary:
	var L := layout(id)
	var problems: Array[String] = []
	var m := build_map(id)
	for c in lava_cells(m):
		m.cells.erase(c)
	var narrow := {}
	for b: Dictionary in L["bridges"]:
		if int(b["w"]) < 2:
			for row: Array in bridge_rows(b):
				narrow[row[0]] = true
	var wide_only := HexMap.new()
	for c: Vector2i in m.cells:
		if not narrow.has(c):
			var src: HexMap.Cell = m.cells[c]
			var cell := wide_only.set_cell(c, src.level)
			cell.tag = src.tag
	if wide_only.find_path(L["start"], L["exit"], bool(L.get("climb", false))).is_empty():
		problems.append("no path from the start to the exit on the wide bridges (%s)" % ("climbing allowed" if L.get("climb", false) else "no climbing"))
	if m.find_path(L["start"], L["exit"], true).is_empty():
		problems.append("no path from the start to the exit")
	for c: Vector2i in L["archers"]:
		if not m.has_cell(c):
			problems.append("archer %s is not on rock" % c)
		elif not m.find_path(L["start"], c, true).is_empty():
			problems.append("archer %s can be walked to" % c)
	for e: Array in L["melee"]:
		if not m.has_cell(e[1]) or m.find_path(L["start"], e[1], true).is_empty():
			problems.append("%s at %s is not on the path" % [e[0], e[1]])
	for b: Dictionary in L["bridges"]:
		if int(b["w"]) >= 2:
			for row: Array in bridge_rows(b):
				if not m.has_cell(row[1]):
					problems.append("bridge row %s has no lane" % row[0])
	return {"ok": problems.is_empty(), "problems": problems}

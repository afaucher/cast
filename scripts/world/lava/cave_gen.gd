class_name CaveGen
extends RefCounted
## THE CAVE PASS of DungeonGen (its "cave" option; LavaSite says which floors; docs/design/lava-playtest.md "As built: caves
## on real floors"). A WING of the room tree (a room and everything beyond it from the start: 2-3 rooms) becomes a lava cave
## on dice of its own (the Builder's `crng`, seeded from the cave's seed): the playtest's cave patterns 1-4 generalised to
## whatever rooms and links the floor has.
##
##   choose(b)     after the tree and its base levels: the wing, the pattern, the cave's level (its rooms all at the root's
##                 level, so the hall in from the rest of the floor is the one it always was)
##   carve(b)      after every link is cut: the rock, the bridges, the spans, the neck, the isles and the lava
##   raise_rim(b)  after the walls: the walls round the lava become the cave's rim (tall at the back)
##   finish(b)     after validation: the tags and the record (HexMap.cave, HexMap.lava)
##
## THE PARTS (one level L for the whole cave; the lava bed BED_DROP below, its surface LAVA_DROP below):
##   - CHAMBERS: each room's core (its cells within CHAMBER_MIN..CHAMBER_MAX of its centre, the room's extent less two) is a
##     rough rock blob: a level up here and there, a dip at the edge now and then, a CRAG (+2) in a big one. The middle (2
##     cells) and every bridge's landing (2 cells round it) stay flat at L: a hellgate fits in the middle, and a bridge's
##     mouth is level (the playtest's one-sided fog came from a bump at a mouth). The rest of the room is lava.
##   - BRIDGES: a link between two of the cave's rooms is its route (DungeonGen's A*, which keeps clear of every other room
##     and hall) carried on into both rooms to the rock: TWO WIDE (the route and its lane), widened to THREE on the last
##     HEAD_ROWS rows at each end (the user, 2026-10-20: "Two wide, 3 at the ends"), its levels a walk between L and L + 1,
##     flat at both ends. A one-wide SPAN (the risky shortcut) is a route alone, its walk between L and L + 2.
##   - the NECK: the hall in from the rest of the floor meets the root chamber at its old doorway; the rock runs from there to
##     the chamber three wide, at L, so that hall keeps its doorway and ends at the lava.
##   - ISLES: rock with no path to it (archers: LavaPlanner), one or two lava cells off the rock (ISLE_GAP_MIN..MAX), and a
##     damp crust from one SHORE cell always reaches it (the user, 2026-10-21: "Keep, crust can always reach": no towers). The
##     check is the crust itself (crust_cells, the min-power damp) and a walk over it without climbing (crust_path).
##   - LAVA: every other cell of the cave's rooms and links, the cells within MARGIN of the rock, and a ring round each isle,
##     at the lava bed. Lava keeps FOREIGN_CLEAR from every cell that is not the cave's (a wall of each side between), except
##     the cave's own room cells round the neck, where the hall in ends at the lava.
##   - the RIM: the walls round the lava, raised to L + RIM_FRONT on the camera's side and L + RIM_BACK_MIN..MAX at the back.
##
## THE PATTERNS (the playtest's caves 1-4; LavaSite.PATTERNS):
##   causeway  two chambers: the bridge, an archer isle off its near half, and a one-wide GOAT PATH (a second route) round
##             the other side; the two walkways are one fog space (the lava between them is tagged "corridor", the playtest's
##             fix 4);
##   gauntlet  two chambers: one long bridge with an isle off each end, on opposite sides;
##   fork      three chambers in a row: the bridge to the hub, then two ways on: the hub's own link to the far chamber as a
##             one-wide span (the short way) and a second route two wide (the long way), an isle between them;
##   ring      three chambers: their links two wide, a one-wide span across between the two that are not linked, an isle in
##             the middle of the lake.
## A fork or ring whose extra route finds no way falls back to the plain chain (every link a bridge, an isle off the longest);
## a causeway without its goat path to the gauntlet. Every chamber is always reached on two-wide bridges.
##
## ANY failure (no wing, a bridge that cannot reach its rock, no isle a crust can reach, validation) and DungeonGen builds the
## attempt without the option, so a floor without a cave is byte for byte the floor it always was.

const CHAMBER_MIN := 3
const CHAMBER_MAX := 5
const CENTER_FLAT := 2
const LANDING_FLAT := 2
const HEAD_ROWS := 2
const MARGIN := 2
const FOREIGN_CLEAR := 3        ## an extra lava cell (not one of the cave's own room / link cells) keeps this far from the rest
const BED_DROP := 5             ## the lava bed: four levels or more below every rock, so nothing walks off an edge
const LAVA_DROP := 2            ## the lava's surface (LavaLook), in levels below L
const RIM_FRONT := 3
const RIM_BACK_MIN := 5
const RIM_BACK_MAX := 8
const ISLE_GAP_MIN := 2
const ISLE_GAP_MAX := 3
const ISLE_SEARCH := 6
const ISLE_APART := 4
const CAMERA := Vector3(0.7071, 0.0, 0.7071)

static var last_usec := 0
static var last_fail := ""   ## why the last cave did not fit (tests, the probe)


static func _no(why: String) -> bool:
	last_fail = why
	return false


## The world reach of the weakest damp's crust (the min-power damp's radius times LavaField.CRUST_FRAC): what an isle is
## checked against, so a crust always reaches it.
static func crust_reach() -> float:
	return DampSpell.damp_radius(SpellBook.MIN_POWER) * LavaField.CRUST_FRAC


# --- choose -----------------------------------------------------------------------------------------------------------

## Pick the wing and the pattern (see the header) on the cave's dice and put the wing's rooms at one level. False: no wing fits.
static func choose(b: DungeonGen.Builder) -> bool:
	var n := b.rooms.size()
	var parent := _parents(b)
	var options: Array = []   # [root, order, pattern]
	for v in range(1, n):
		var wing: Array[int] = b._wing(v, parent)
		if wing.size() < LavaSite.MIN_ROOMS or wing.size() > LavaSite.MAX_ROOMS or n - wing.size() < 3:
			continue
		for opt: Array in _shapes(b, v, wing, parent):
			options.append(opt)
	if options.is_empty():
		return _no("choose:89")
	if LavaSite.force_pattern != "":
		var want := options.filter(func(o: Array) -> bool: return str(o[2]) == LavaSite.force_pattern)
		if not want.is_empty():
			options = want
	var pick: Array = options[b.crng.randi_range(0, options.size() - 1)]
	var root: int = pick[0]
	var level := b.rooms[root].level
	var order: Array[int] = pick[1]
	for r in order:
		b.cave[r] = true
		b.rooms[r].level = level
	b.cave_info = {"root": root, "parent": parent[root], "order": order, "pattern": str(pick[2]), "level": level}
	return true


static func _parents(b: DungeonGen.Builder) -> Array[int]:
	var parent: Array[int] = []
	for _i in b.rooms.size():
		parent.append(-1)
	var order: Array[int] = [0]
	var seen := {0: true}
	var qi := 0
	while qi < order.size():
		var c: int = order[qi]
		qi += 1
		for nb: int in b.tree_adj[c]:
			if not seen.has(nb):
				seen[nb] = true
				parent[nb] = c
				order.append(nb)
	return parent


## The patterns a wing can take: [root, chambers in order from the entry, pattern].
static func _shapes(b: DungeonGen.Builder, v: int, wing: Array[int], parent: Array[int]) -> Array:
	var out: Array = []
	if wing.size() == 2:
		var order: Array[int] = [v, wing[1]]
		out.append([v, order, "causeway"])
		out.append([v, order, "gauntlet"])
		return out
	var x: int = wing[1]
	var y: int = wing[2]
	if parent[y] == x or parent[x] == y:
		var mid := x if parent[y] == x else y
		var far := y if mid == x else x
		var chain: Array[int] = [v, mid, far]
		out.append([v, chain, "fork"])
		out.append([v, chain, "ring"])
	else:
		# a star: the root and two rooms off it; the farther one from the root is the far chamber
		var dx := Hex.distance(b.rooms[x].center, b.rooms[v].center)
		var dy := Hex.distance(b.rooms[y].center, b.rooms[v].center)
		var star: Array[int] = []
		star.assign([v, x, y] if dx < dy or (dx == dy and x < y) else [v, y, x])
		out.append([v, star, "ring"])
	return out


# --- carve ------------------------------------------------------------------------------------------------------------

## The cave's rock and lava (see the header). False: the cave does not fit (the attempt is built without it).
static func carve(b: DungeonGen.Builder) -> bool:
	var t0 := Time.get_ticks_usec()
	var ok := _carve(b)
	last_usec = Time.get_ticks_usec() - t0
	return ok


static func _carve(b: DungeonGen.Builder) -> bool:
	var info: Dictionary = b.cave_info
	var order: Array[int] = info["order"]
	var lv := int(info["level"])
	var pattern := str(info["pattern"])
	# The cave's own cells: its rooms' and the links between them (the hall in from the rest of the floor is not).
	var owned := {}
	for r in order:
		for c: Vector2i in b.rooms[r].cells:
			owned[c] = true
	var tree: Array = []   # the links between two of the cave's rooms
	var entry: DungeonGen.Link = null
	for l in b.links:
		var ia := b.cave.has(l.a)
		var ib := b.cave.has(l.b)
		if ia and ib:
			tree.append(l)
			for c in l.cells:
				owned[c] = true
		elif ia or ib:
			if entry != null:
				return _no("_carve:180")   # (only the tree link comes in: the loops into a cave are not cut)
			entry = l
	if entry == null:
		return _no("_carve:183")
	var rock := {}    # cell -> level
	var kind := {}    # cell -> "room:N" | "corridor" | "isle"
	var radius := {}  # room index -> its chamber radius
	for r in order:
		var room: DungeonGen.Room = b.rooms[r]
		var rr := clampi(room.extent - 2, CHAMBER_MIN, CHAMBER_MAX)
		radius[r] = rr
		var core := {}
		for c: Vector2i in room.cells:
			if Hex.distance(c, room.center) <= rr:
				core[c] = true
		for c: Vector2i in b._component(core, room.center):
			rock[c] = lv
			kind[c] = "room:%d" % r
	# The walkways: each link of the cave a bridge (or a one-wide span), plus the pattern's extra route.
	var ways: Array = []   # [a, b, route S, wide]
	for l: DungeonGen.Link in tree:
		ways.append([l.a, l.b, l.route.duplicate(), true])
	var extra := {}
	match pattern:
		"causeway":
			extra = _extra_route(b, order[0], order[1], owned)
			if extra.is_empty():
				pattern = "gauntlet"
			else:
				ways.append([order[0], order[1], extra["route"], false])
		"fork":
			extra = _extra_route(b, order[1], order[2], owned)
			if extra.is_empty():
				pattern = "chain"
			else:
				for w: Array in ways:
					if (w[0] == order[1] and w[1] == order[2]) or (w[0] == order[2] and w[1] == order[1]):
						w[3] = false   # the hub's own link is the short one-wide way; the second route is the wide loop
				ways.append([order[1], order[2], extra["route"], true])
		"ring":
			var pa := order[0]
			var pb := order[2]
			if b.tree_adj[order[0]].has(order[2]):   # (a star: the span runs between the two outer rooms)
				pa = order[1]
			extra = _extra_route(b, pa, pb, owned)
			if extra.is_empty():
				pattern = "chain"
			else:
				ways.append([pa, pb, extra["route"], false])
	var bridges: Array = []
	for w: Array in ways:
		var br := _walkway(b, int(w[0]), int(w[1]), w[2], bool(w[3]), rock, kind, owned, lv)
		if br.is_empty():
			return _no("_carve:233")
		bridges.append(br)
	# The neck: the hall in meets the root chamber at its doorway; the rock runs on to the chamber, three wide.
	var root: int = info["root"]
	var door: Vector2i = entry.door_b if entry.b == root else entry.door_a
	var neck := _neck(b, root, door, rock, kind, owned, lv)
	if neck.is_empty():
		return _no("_carve:240")
	# Landings stay flat (and so does each chamber's middle); the rest of each chamber gets rough.
	var flat := {}
	for br: Dictionary in bridges:
		var rows: Array = br["rows"]
		for row: Array in [rows[0], rows[rows.size() - 1]]:
			for c: Vector2i in row:
				for nn in Hex.range_cells(c, LANDING_FLAT):
					flat[nn] = true
	for c: Vector2i in neck:
		for nn in Hex.range_cells(c, LANDING_FLAT):
			flat[nn] = true
	for r in order:
		_roughen(b, r, int(radius[r]), rock, kind, flat, lv)
	# The lava: the cave's own cells that are not rock, and the cells round the rock that are free.
	var foreign := _foreign(b, owned, rock)
	var lava := {}
	for c: Vector2i in owned:
		if not rock.has(c):
			lava[c] = true
	for c: Vector2i in rock:
		for nn in Hex.range_cells(c, MARGIN):
			if not rock.has(nn) and not lava.has(nn) and _free(b, nn, owned, foreign):
				lava[nn] = true
	# The isles: the pattern's anchors, each a crust's reach from a shore.
	var isles: Array = []
	for anchor: Dictionary in _anchors(b, pattern, order, bridges, extra):
		var isle := _isle(b, anchor, rock, kind, lava, owned, foreign, isles, lv)
		if isle.is_empty():
			return _no("_carve:isle " + last_fail)
		isles.append(isle)
	if isles.is_empty():
		return _no("_carve:272")
	# Write the cells: rock at its levels, lava at the bed.
	for c: Vector2i in rock:
		b.map.set_cell(c, int(rock[c]))
	for c: Vector2i in lava:
		b.map.set_cell(c, lv - BED_DROP)
	# Parallel walkways between the same two chambers are one fog space (the playtest's fix 4): the lava on the short line
	# between their middles is tagged "corridor" (it stays lava).
	var joins: Array[Vector2i] = []
	if pattern == "causeway" or pattern == "fork":
		joins = _join(bridges, lava)
	b.cave_info.merge({"pattern": pattern, "rock": rock, "kind": kind, "lava": lava, "bridges": bridges, "isles": isles,
		"neck": neck, "door": door, "radius": radius, "joins": joins, "entry_from": entry.a if entry.b == root else entry.b}, true)
	return true


## A second route between rooms a and b (DungeonGen's A*: it keeps clear of every hall already cut), its cells the cave's.
## {route} or {} when there is none.
static func _extra_route(b: DungeonGen.Builder, a: int, c: int, owned: Dictionary) -> Dictionary:
	var S: Array[Vector2i] = b._route(b.rooms[a], b.rooms[c])
	if S.size() < 3:
		return {}
	for p in S:
		owned[p] = true
		for nn in Hex.neighbors(p):
			if not b.map.has_cell(nn) and not b.room_of.has(nn):
				owned[nn] = true   # (its ring is the cave's too: a lane, else lava)
		for nn in Hex.range_cells(p, 2):
			b.corr_buffer2[nn] = true
			if Hex.distance(nn, p) <= 1:
				b.corr_buffer[nn] = true
	return {"route": S}


## One walkway from chamber a to chamber b along route S (door_a .. door_b), carried on into both rooms to their rock:
## {a, b, w, rows: [[cells of row 0], ...], heads: [row indices three wide]} or {} when it cannot reach a chamber's rock.
static func _walkway(b: DungeonGen.Builder, a: int, c: int, S: Array, wide: bool, rock: Dictionary, kind: Dictionary,
		owned: Dictionary, lv: int) -> Dictionary:
	var tag_a := "room:%d" % a
	var tag_b := "room:%d" % c
	var ext_a: Variant = _extension(b, S[0], a, rock, kind, owned)
	var ext_b: Variant = _extension(b, S[S.size() - 1], c, rock, kind, owned)
	if ext_a == null or ext_b == null:
		return {}
	var full: Array[Vector2i] = []
	var ea: Array = ext_a
	for i in range(ea.size() - 1, -1, -1):
		full.append(ea[i])
	for p: Vector2i in S:
		if not full.has(p):
			full.append(p)
	for p: Vector2i in ext_b:
		if not full.has(p):
			full.append(p)
	# drop route cells that are already the chambers' rock (a door cell inside the core), keep it one run
	var run: Array[Vector2i] = []
	for p in full:
		if rock.has(p) and str(kind[p]).begins_with("room:"):
			continue
		run.append(p)
	if run.size() < 2:
		return {}
	for i in range(1, run.size()):
		if Hex.distance(run[i - 1], run[i]) != 1:
			return {}
	var n := run.size()
	var steps: Array[int] = []
	var cur := 0
	var top := 1 if wide else 2
	for i in n:
		if i < HEAD_ROWS or i >= n - HEAD_ROWS:
			cur = 0
			steps.append(0)
			continue
		if b.crng.randf() < (0.3 if wide else 0.35):
			cur = clampi(cur + (1 if b.crng.randf() < 0.5 else -1), 0, top)
		# come back down before the far end (a mouth is flat; one level a row)
		cur = mini(cur, n - HEAD_ROWS - i)
		steps.append(cur)
	var rows: Array = []
	var heads: Array[int] = []
	for i in n:
		var p := run[i]
		var d := Hex.dir_to(p, run[i + 1]) if i + 1 < n else Hex.dir_to(run[i - 1], p)
		var row: Array[Vector2i] = [p]
		_put_rock(p, lv + steps[i], "corridor", rock, kind)
		if wide:
			var lane: Vector2i = p + Hex.DIRS[(d + 1) % 6]
			if rock.has(lane) or _usable(b, lane, owned, rock, kind):   # (a chamber's own rock counts: it is rock)
				_put_rock(lane, lv + steps[i], "corridor", rock, kind)
				row.append(lane)
			if i < HEAD_ROWS or i >= n - HEAD_ROWS:
				var lane2: Vector2i = p + Hex.DIRS[(d + 5) % 6]
				if rock.has(lane2) or _usable(b, lane2, owned, rock, kind):
					_put_rock(lane2, lv, "corridor", rock, kind)
					row.append(lane2)
				heads.append(i)
		rows.append(row)
	return {"a": tag_a, "b": tag_b, "w": 2 if wide else 1, "rows": rows, "heads": heads}


static func _put_rock(c: Vector2i, level: int, k: String, rock: Dictionary, kind: Dictionary) -> void:
	if rock.has(c) and str(kind[c]).begins_with("room:"):
		return   # (a chamber's own rock stays the chamber's)
	rock[c] = level
	kind[c] = k


## May a walkway's lane go on c? The cave's own cell or free space, never another room's or hall's (nor the chamber's rock,
## which it simply meets).
static func _usable(b: DungeonGen.Builder, c: Vector2i, owned: Dictionary, rock: Dictionary, kind: Dictionary) -> bool:
	if rock.has(c):
		return str(kind[c]) == "corridor"
	if owned.has(c):
		return true
	return not b.map.has_cell(c) and not b.room_of.has(c)


## The cells from `door` (on room r's edge) on toward its centre until the chamber's rock: [] when the door is on the rock,
## null when the way leaves the cave's cells.
static func _extension(b: DungeonGen.Builder, door: Vector2i, r: int, rock: Dictionary, kind: Dictionary, owned: Dictionary) -> Variant:
	var tag := "room:%d" % r
	var out: Array[Vector2i] = []
	if rock.has(door) and str(kind[door]) == tag:
		return out
	for c in Hex.line(door, b.rooms[r].center).slice(1):
		if rock.has(c) and str(kind[c]) == tag:
			return out
		if not owned.has(c):
			return null
		out.append(c)
	return null


## The neck from the hall's doorway in room r to its chamber: the door and the cells on to the rock, three wide where the
## cells are the room's. Returns its cells ([] when it cannot reach the rock).
static func _neck(b: DungeonGen.Builder, r: int, door: Vector2i, rock: Dictionary, kind: Dictionary, owned: Dictionary, lv: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var tag := "room:%d" % r
	var ext: Variant = _extension(b, door, r, rock, kind, owned)
	if ext == null:
		return out
	var line: Array[Vector2i] = [door]
	for c: Vector2i in (ext as Array):
		line.append(c)
	var center: Vector2i = b.rooms[r].center
	for i in line.size():
		var c: Vector2i = line[i]
		var d := Hex.dir_to(c, line[i + 1]) if i + 1 < line.size() else Hex.dir_to(c, _toward(c, center))
		var cells: Array[Vector2i] = [c]
		if d >= 0:
			cells.append(c + Hex.DIRS[(d + 1) % 6])
			cells.append(c + Hex.DIRS[(d + 5) % 6])
		for x in cells:
			if x != c and (not owned.has(x) or not b.rooms[r].cells.has(x)):
				continue
			if rock.has(x) and str(kind[x]) != tag and str(kind[x]) != "corridor":
				continue
			rock[x] = lv
			kind[x] = tag
			out.append(x)
	return out


## The neighbour of c one step toward `to`.
static func _toward(c: Vector2i, to: Vector2i) -> Vector2i:
	var line := Hex.line(c, to)
	return line[1] if line.size() > 1 else c + Hex.DIRS[0]


## A chamber's roughness: a level up on about a quarter of its inner cells, a dip on some edge cells (never next to a
## bump), a crag (+2) in a chamber of radius 4 or more; never on `flat` (the landings) or the middle.
static func _roughen(b: DungeonGen.Builder, r: int, rr: int, rock: Dictionary, kind: Dictionary, flat: Dictionary, lv: int) -> void:
	var tag := "room:%d" % r
	var center: Vector2i = b.rooms[r].center
	var cells: Array[Vector2i] = []
	for c: Vector2i in rock:
		if str(kind[c]) == tag:
			cells.append(c)
	cells.sort_custom(HexMap._cell_less)
	var up := {}
	var edge := {}
	for c in cells:
		var inner := true
		for nn in Hex.neighbors(c):
			if not rock.has(nn):
				inner = false
		if not inner:
			edge[c] = true
		if flat.has(c) or Hex.distance(c, center) <= CENTER_FLAT:
			continue
		if inner and b.crng.randf() < 0.25:
			up[c] = true
	for c: Vector2i in up:
		rock[c] = lv + 1
	for c in cells:
		if not edge.has(c) or flat.has(c) or up.has(c) or Hex.distance(c, center) <= CENTER_FLAT:
			continue
		var near_up := false
		for nn in Hex.neighbors(c):
			near_up = near_up or up.has(nn)
		if not near_up and b.crng.randf() < 0.15:
			rock[c] = lv - 1
	if rr >= 4:
		var cands: Array[Vector2i] = []
		for c in cells:
			if Hex.distance(c, center) == rr - 1 and not flat.has(c) and not edge.has(c):
				cands.append(c)
		if not cands.is_empty():
			var crag: Vector2i = cands[b.crng.randi_range(0, cands.size() - 1)]
			rock[crag] = lv + 2
			for nn in Hex.neighbors(crag):
				if rock.has(nn) and str(kind[nn]) == tag and int(rock[nn]) < lv:
					rock[nn] = lv   # (no dip right under a crag: a three-level wall)


## Every present cell that is not the cave's (other rooms, other halls, the hall in): lava keeps its distance from them.
static func _foreign(b: DungeonGen.Builder, owned: Dictionary, rock: Dictionary) -> Dictionary:
	var out := {}
	for c: Vector2i in b.map.cells:
		if not owned.has(c) and not rock.has(c):
			out[c] = true
	for c: Vector2i in b.room_of:
		if not owned.has(c) and not rock.has(c):
			out[c] = true
	return out


## May c be extra lava (not one of the cave's own cells)? Empty, and FOREIGN_CLEAR from everything that is not the cave's.
static func _free(b: DungeonGen.Builder, c: Vector2i, owned: Dictionary, foreign: Dictionary) -> bool:
	if owned.has(c):
		return true
	if b.map.has_cell(c) or b.room_of.has(c) or b.pits.has(c) or Hex.distance(c, Vector2i.ZERO) > b.p_size + 18:
		return false
	for nn in Hex.range_cells(c, FOREIGN_CLEAR - 1):
		if foreign.has(nn):
			return false
	return true


## Where the pattern wants its isles: [{at: a cell, side: a cell the isle should be nearer (or NO_CELL)}].
static func _anchors(b: DungeonGen.Builder, pattern: String, order: Array[int], bridges: Array, extra: Dictionary) -> Array:
	var out: Array = []
	var first: Dictionary = bridges[0]
	match pattern:
		"causeway":
			# off the bridge's near half, on the side away from the goat path
			var rows: Array = first["rows"]
			var near: Vector2i = (rows[rows.size() / 3] as Array)[0]
			var goat: Array = (bridges[bridges.size() - 1] as Dictionary)["rows"]
			out.append({"at": near, "away": (goat[goat.size() / 2] as Array)[0]})
		"gauntlet":
			var rows: Array = first["rows"]
			var a: Vector2i = (rows[rows.size() / 4] as Array)[0]
			var c: Vector2i = (rows[rows.size() * 3 / 4] as Array)[0]
			out.append({"at": a})
			out.append({"at": c, "apart": true})
		"fork":
			# between the hub's two ways to the far chamber
			var m1: Vector2i = _mid(bridges[bridges.size() - 1])
			var m2 := Vector2i.ZERO
			for br: Dictionary in bridges:
				if int(br["w"]) == 1:
					m2 = _mid(br)
			out.append({"at": Hex.round_axial((m1.x + m2.x) * 0.5, (m1.y + m2.y) * 0.5)})
		"ring":
			var sx := 0.0
			var sy := 0.0
			for r in order:
				sx += b.rooms[r].center.x
				sy += b.rooms[r].center.y
			out.append({"at": Hex.round_axial(sx / order.size(), sy / order.size())})
		_:
			var longest: Dictionary = first
			for br: Dictionary in bridges:
				if (br["rows"] as Array).size() > (longest["rows"] as Array).size():
					longest = br
			out.append({"at": _mid(longest)})
	return out


static func _mid(br: Dictionary) -> Vector2i:
	var rows: Array = br["rows"]
	return (rows[rows.size() / 2] as Array)[0]


## One isle near anchor: {center, cells, shore, level} or {} when none fits. Its ring becomes lava.
static func _isle(b: DungeonGen.Builder, anchor: Dictionary, rock: Dictionary, kind: Dictionary, lava: Dictionary,
		owned: Dictionary, foreign: Dictionary, isles: Array, lv: int) -> Dictionary:
	var at: Vector2i = anchor["at"]
	var dist := _rock_distance(rock, at, ISLE_SEARCH + 3)
	var cands: Array = []
	for c in Hex.range_cells(at, ISLE_SEARCH + 3):
		var cells := Hex.range_cells(c, 1)
		var gap := 99
		var ok := true
		for x in cells:
			if rock.has(x) or not (lava.has(x) or _free(b, x, owned, foreign)):
				ok = false
				break
			gap = mini(gap, int(dist.get(x, 99)))
		if not ok or gap < ISLE_GAP_MIN or gap > ISLE_GAP_MAX:
			continue
		for x in Hex.ring(c, 2):
			if rock.has(x) or not (lava.has(x) or _free(b, x, owned, foreign)):
				ok = false
				break
		for other: Dictionary in isles:
			ok = ok and Hex.distance(c, other["center"]) >= ISLE_APART + 2
		if not ok:
			continue
		var score := float(Hex.distance(c, at)) + (0.0 if gap == ISLE_GAP_MAX else 1.5)
		if anchor.has("away"):
			score -= 0.6 * float(Hex.distance(c, anchor["away"]))
		if bool(anchor.get("apart", false)) and not isles.is_empty():
			score -= 0.5 * float(Hex.distance(c, (isles[0] as Dictionary)["center"]))
		cands.append([score, c])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and HexMap._cell_less(x[1], y[1])))
	last_fail = "isle: %d candidates" % cands.size()
	for cand: Array in cands.slice(0, 12):
		var c: Vector2i = cand[1]
		var cells := Hex.range_cells(c, 1)
		var isle_set := {}
		for x in cells:
			isle_set[x] = lv + (1 if x == c else 0)   # (its levels: the walk onto it judges the step)
		# the lava it would sit in (its ring added), and the crust that reaches it from a shore cell
		var lava2 := lava.duplicate()
		for x in Hex.range_cells(c, 2):
			if not isle_set.has(x):
				lava2[x] = true
		for x in cells:
			lava2.erase(x)
		var shore := _shore(b, rock, kind, lava2, isle_set, lv, owned)
		if shore == HexMap.NO_CELL:
			continue
		for x in Hex.ring(c, 2):
			lava[x] = true
		for x in cells:
			lava.erase(x)
			rock[x] = lv + (1 if x == c else 0)
			kind[x] = "isle"
		cells.sort_custom(HexMap._cell_less)
		return {"center": c, "cells": cells, "shore": shore, "level": lv}
	return {}


## Hex distance from the rock to every cell within `reach` of `at`.
static func _rock_distance(rock: Dictionary, at: Vector2i, reach: int) -> Dictionary:
	var out := {}
	var frontier: Array[Vector2i] = []
	for c: Vector2i in rock:
		if Hex.distance(c, at) <= reach + ISLE_GAP_MAX + 1:
			out[c] = 0
			frontier.append(c)
	for step in range(1, ISLE_GAP_MAX + 2):
		var next: Array[Vector2i] = []
		for c in frontier:
			for nn in Hex.neighbors(c):
				if not out.has(nn):
					out[nn] = step
					next.append(nn)
		frontier = next
	return out


## A walkable rock cell (a chamber's or a walkway's, never an isle's) whose min-power damp crust makes a climb-free walk onto
## the isle; NO_CELL when there is none.
static func _shore(b: DungeonGen.Builder, rock: Dictionary, kind: Dictionary, lava: Dictionary, isle: Dictionary, lv: int,
		owned: Dictionary) -> Vector2i:
	var shores: Array[Vector2i] = []
	var near_isle := {}
	for x: Vector2i in isle:
		for nn in Hex.range_cells(x, ISLE_GAP_MAX):
			near_isle[nn] = true
	for c: Vector2i in near_isle:
		if rock.has(c) and str(kind[c]) != "isle":
			shores.append(c)
	shores.sort_custom(HexMap._cell_less)
	var present := func(x: Vector2i) -> bool: return rock.has(x) or lava.has(x) or b.map.has_cell(x) or isle.has(x)
	for s in shores:
		var crust := crust_cells(Hex.to_world(s), crust_reach(), lava, present)
		if crust_path(rock, isle, crust, s, lv - 1):
			return s
	return HexMap.NO_CELL


## The lava cells a damp at `centre` crusts (within `reach`, world units), never a cell next to the cave's edge (a lava cell
## a rim wall cuts: `present` says which cells exist round it). Shared by LavaField (the rule) and the generator (its check).
static func crust_cells(centre: Vector3, reach: float, lava: Dictionary, present: Callable) -> Dictionary:
	var out := {}
	var c0 := Hex.from_world(centre)
	var r := int(ceil(reach / Hex.SQRT3)) + 1
	for c in Hex.range_cells(c0, r):
		if not lava.has(c):
			continue
		var w := Hex.to_world(c)
		if Vector2(w.x - centre.x, w.z - centre.z).length() > reach:
			continue
		var whole := true
		for nn in Hex.neighbors(c):
			whole = whole and bool(present.call(nn))
		if whole:
			out[c] = true
	return out


## A climb-free walk from `from` (rock) over rock and crust (at crust_level) onto an isle cell (`isle`: cell -> its level).
static func crust_path(rock: Dictionary, isle: Dictionary, crust: Dictionary, from: Vector2i, crust_level: int) -> bool:
	var level := func(c: Vector2i) -> int: return crust_level if crust.has(c) else int(isle.get(c, rock.get(c, -9999)))
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		if isle.has(c):
			return true
		for nn in Hex.neighbors(c):
			if seen.has(nn) or not (crust.has(nn) or rock.has(nn) or isle.has(nn)):
				continue
			if not crust.has(nn) and not isle.has(nn) and not crust.has(c):
				continue   # (the walk goes over the crust: rock to rock is not the question)
			var d: int = int(level.call(nn)) - int(level.call(c))
			if d > 1 or d < -3:
				continue
			seen[nn] = true
			queue.append(nn)
	return false


## Lava on the short line between the middles of the walkways that run between the same two chambers: "corridor" (fog).
static func _join(bridges: Array, lava: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in bridges.size():
		for j in range(i + 1, bridges.size()):
			var x: Dictionary = bridges[i]
			var y: Dictionary = bridges[j]
			var same: bool = (x["a"] == y["a"] and x["b"] == y["b"]) or (x["a"] == y["b"] and x["b"] == y["a"])
			if not same:
				continue
			var ca := _mid(x)
			var best: Vector2i = ((y["rows"] as Array)[0] as Array)[0]
			for row: Array in y["rows"]:
				if Hex.distance(ca, row[0]) < Hex.distance(ca, best):
					best = row[0]
			for c in Hex.line(ca, best):
				if lava.has(c) and not out.has(c):
					out.append(c)
	return out


# --- the rim --------------------------------------------------------------------------------------------------------------

## The walls round the lava are the cave's rim: L + RIM_FRONT on the camera's side, L + RIM_BACK_MIN..MAX at the back (never
## lower than they were). Before cut_walls, which reads their height.
static func raise_rim(b: DungeonGen.Builder) -> void:
	var info: Dictionary = b.cave_info
	var lava: Dictionary = info["lava"]
	var lv := int(info["level"])
	var sx := 0.0
	var sz := 0.0
	for c: Vector2i in lava:
		var w := Hex.to_world(c)
		sx += w.x
		sz += w.z
	var mid := Vector3(sx / maxf(1.0, lava.size()), 0.0, sz / maxf(1.0, lava.size()))
	var seen := {}
	var walls: Array[Vector2i] = []
	for c: Vector2i in lava:
		for nn in Hex.neighbors(c):
			var cell: HexMap.Cell = b.map.get_cell(nn)
			if cell != null and cell.type == HexMap.Tile.WALL and not seen.has(nn):
				seen[nn] = true
				walls.append(nn)
	walls.sort_custom(HexMap._cell_less)
	for w in walls:
		var front := (Hex.to_world(w) - mid).dot(CAMERA) > 0.0
		var h := lv + (RIM_FRONT if front else b.crng.randi_range(RIM_BACK_MIN, RIM_BACK_MAX))
		var cell: HexMap.Cell = b.map.get_cell(w)
		cell.level = maxi(cell.level, h)


# --- finish -----------------------------------------------------------------------------------------------------------

## After validation: every cave cell's tag (chambers their room, walkways "corridor", isles "isle", lava "lava" or the fog
## join's "corridor") and the record (HexMap.cave, HexMap.lava).
static func finish(b: DungeonGen.Builder) -> void:
	var info: Dictionary = b.cave_info
	var rock: Dictionary = info["rock"]
	var kind: Dictionary = info["kind"]
	var lava: Dictionary = info["lava"]
	var lv := int(info["level"])
	var joins: Array[Vector2i] = info["joins"]
	for c: Vector2i in rock:
		var cell: HexMap.Cell = b.map.get_cell(c)
		if cell != null:
			cell.tag = str(kind[c])
	for c: Vector2i in lava:
		var cell: HexMap.Cell = b.map.get_cell(c)
		if cell != null:
			cell.tag = "corridor" if joins.has(c) else "lava"
	var order: Array[int] = info["order"]
	var tags: Array[String] = []
	for r in order:
		tags.append("room:%d" % r)
	var rock_list: Array[Vector2i] = []
	for c: Vector2i in rock:
		rock_list.append(c)
	rock_list.sort_custom(HexMap._cell_less)
	var lava_list: Array[Vector2i] = []
	for c: Vector2i in lava:
		lava_list.append(c)
		b.map.lava[c] = true
	lava_list.sort_custom(HexMap._cell_less)
	var chambers: Array = []
	for r in order:
		chambers.append({"room": "room:%d" % r, "center": b.rooms[r].center, "r": int((info["radius"] as Dictionary)[r])})
	var bridges: Array = []
	for br: Dictionary in info["bridges"]:
		bridges.append(br.duplicate(true))
	var neck: Array[Vector2i] = info["neck"]
	b.map.cave = {
		"seed": b.p_cave, "pattern": str(info["pattern"]), "level": lv, "crust_level": lv - 1, "bed": lv - BED_DROP,
		"lava_y": float(lv - LAVA_DROP) * Hex.LEVEL_HEIGHT, "rooms": tags, "chambers": chambers,
		"entry": {"room": "room:%d" % int(info["root"]), "door": info["door"], "from": "room:%d" % int(info["entry_from"]), "neck": neck.duplicate()},
		"far": tags[tags.size() - 1], "gate": b.p_cave_gate, "bridges": bridges, "isles": (info["isles"] as Array).duplicate(true),
		"rock": rock_list, "lava": lava_list, "joins": joins.duplicate(),
	}

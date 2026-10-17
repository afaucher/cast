class_name GrimePlan
extends RefCounted
## Where the AMBIENT grime goes on one floor: pure data (no nodes), deterministic per (map, plan, seed).
##
##   var marks := GrimePlan.build(map, plan, floor_seed, themes)    # Array[GrimePlan.Mark]
##
## Rules:
##  - INFESTATION HEAT: 1 at a hellgate (floor 3: the origin gate), falling off over GATE_RADIUS (ORIGIN_RADIUS)
##    hexes; the origin room holds at least ORIGIN_ROOM_HEAT; every far cell has a trace (BASE_HEAT, growing
##    with the distance from the start). The start room is scaled by START_ROOM_MULT (almost clean), and
##    nothing at all lands within START_CLEAR hexes of the start cell or the exit cell.
##  - A cell gets heat * DENSITY marks (the fraction is a dice roll), at most CELL_CAP; the whole floor at
##    most AMBIENT_CAP (the coolest marks are dropped first). Walkable floor only: no stairs, walls, pits, and
##    no raised crates.
##  - KINDS follow the heat: scorch, scratches, cracked tops and purple ichor puddles near the gates; rubble
##    specks, papers/receipts, broken glass and candle wax further out.
##  - TRAILS: from each gate, up to TRAILS_PER_GATE ichor drag trails run along the nearest corridors, leading away.
##  - THEME marks (only for rooms the `themes` dictionary (room tag -> theme id) names; SitePlan.room_themes
##    when the dictionary is empty and the plan has one): wine splats (wine cellar), popcorn (cinema), chalk
##    smears (spa), oil stains (gym), blood-red rust (torture chamber), green spills (lab).
##  - Every mark has a random rotation, scale, variant and tint from the seeded RNG.

const AMBIENT_CAP := 380
const CELL_CAP := 3
const DENSITY := 2.2
const GATE_RADIUS := 9
const ORIGIN_RADIUS := 11
const ORIGIN_ROOM_HEAT := 0.6
const BASE_HEAT := 0.07
const START_ROOM_MULT := 0.04
const START_CLEAR := 2
const TRAILS_PER_GATE := 2
const TRAIL_EXTEND := 10
const TRAIL_SEARCH := 30
const THEME_CHANCE := 0.30
const REACH := 0.84               ## a mark's content stays within this many world units of its cell centre

## theme id (substring match) -> the atlas kind its marks use
const THEME_KINDS := {
	"wine": "wine", "cinema": "popcorn", "theat": "popcorn", "spa": "chalk", "yoga": "chalk",
	"gym": "oil", "torture": "rust", "lab": "spill",
}


## One decal.
class Mark extends RefCounted:
	var kind := ""
	var variant := 0
	var pos := Vector3.ZERO          ## world position, y = the hex top + a hair
	var rot := 0.0                   ## radians about Y; +X of the tile points along (cos rot, 0, -sin rot)
	var size := Vector2.ONE          ## quad edge lengths in world units (x along the tile's X axis)
	var alpha := 1.0
	var glow := 0.0
	var tint := Color.WHITE
	var cell := Vector2i.ZERO
	var heat := 0.0
	var source := "ambient"          ## "ambient" | "trail" | "theme"


## What the plan needs to know about a floor (from a SitePlan, or derived from the map's tags).
class Ctx extends RefCounted:
	var start := Vector2i.ZERO
	var exit := Vector2i.ZERO
	var start_room := ""
	var origin_room := ""
	var gates: Array[Vector2i] = []
	var gate_origin: Array[bool] = []
	var themes: Dictionary = {}
	var crates: Dictionary = {}


static func build(map: HexMap, plan: SitePlan, seed_value: int, themes: Dictionary = {}) -> Array[Mark]:
	var ctx := context(map, plan, themes)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 4241
	var out: Array[Mark] = []
	var per_cell: Dictionary = {}

	var cells: Array[Vector2i] = []
	for c: Vector2i in map.cells:
		if eligible(map, ctx, c):
			cells.append(c)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))

	var trails := _trails(map, ctx, rng, per_cell)
	var theme_marks := _theme_marks(map, ctx, cells, rng, per_cell)
	var heat_marks: Array[Mark] = []
	for c in cells:
		var h := heat_at(map, ctx, c)
		var want := h * DENSITY
		var n := int(want) + (1 if rng.randf() < want - floorf(want) else 0)
		n = mini(n, CELL_CAP - int(per_cell.get(c, 0)))
		for i in maxi(n, 0):
			var m := _make(map, rng, c, _pick_kind(rng, h, map.get_cell(c).tag == "corridor"), "ambient")
			m.heat = h
			heat_marks.append(m)
		per_cell[c] = int(per_cell.get(c, 0)) + maxi(n, 0)
	# Over the global cap: the coolest marks go first (a stable sort keeps this deterministic).
	var room_left := maxi(0, AMBIENT_CAP - trails.size() - theme_marks.size())
	if heat_marks.size() > room_left:
		var idx: Array[int] = []
		for i in heat_marks.size():
			idx.append(i)
		idx.sort_custom(func(a: int, b: int) -> bool:
			var ha: float = heat_marks[a].heat
			var hb: float = heat_marks[b].heat
			return ha > hb or (ha == hb and a < b))
		var kept: Array[int] = []
		for i in room_left:
			kept.append(idx[i])
		kept.sort()
		var keep: Array[Mark] = []
		for i in kept:
			keep.append(heat_marks[i])
		heat_marks = keep
	out.append_array(trails)
	out.append_array(theme_marks)
	out.append_array(heat_marks)
	return out


# ---------------------------------------------------------------------- context / heat

static func context(map: HexMap, plan: SitePlan, themes: Dictionary = {}) -> Ctx:
	var ctx := Ctx.new()
	if plan != null:
		ctx.start = plan.start
		ctx.exit = plan.exit
		ctx.start_room = plan.start_room
		ctx.origin_room = plan.origin_room
		for g in plan.gates:
			ctx.gates.append(g["cell"])
			ctx.gate_origin.append(bool(g["origin"]))
		if themes.is_empty():
			var t: Variant = plan.get("room_themes")   # added by the room-theme builder; absent on older plans
			if t is Dictionary:
				themes = t
	else:
		var starts := map.cells_with_tag("start")
		var exits := map.cells_with_tag("exit")
		ctx.start = starts[0] if not starts.is_empty() else Vector2i.ZERO
		ctx.exit = exits[0] if not exits.is_empty() else ctx.start
		ctx.start_room = _room_near(map, ctx.start)
	ctx.themes = themes
	ctx.crates = HexMapView._find_crates(map)
	return ctx


static func _room_near(map: HexMap, c: Vector2i) -> String:
	for r in range(1, 6):
		for n in Hex.ring(c, r):
			var cell: HexMap.Cell = map.get_cell(n)
			if cell != null and cell.tag.begins_with("room:"):
				return cell.tag
	return ""


## Plain floor a decal can lie on: not stairs / walls / bridges, not a raised crate, and outside the clear
## zones around the start and the exit.
static func eligible(map: HexMap, ctx: Ctx, c: Vector2i) -> bool:
	var cell: HexMap.Cell = map.get_cell(c)
	if cell == null or cell.type != HexMap.Tile.FLOOR or ctx.crates.has(c):
		return false
	if Hex.distance(c, ctx.start) <= START_CLEAR or Hex.distance(c, ctx.exit) <= START_CLEAR:
		return false
	if ctx.gates.has(c):
		return false
	return true


## 0..1 infestation heat of a cell (before DENSITY).
static func heat_at(map: HexMap, ctx: Ctx, c: Vector2i) -> float:
	var h := 0.0
	for i in ctx.gates.size():
		var r := ORIGIN_RADIUS if ctx.gate_origin[i] else GATE_RADIUS
		var d := Hex.distance(c, ctx.gates[i])
		if d < r:
			h = maxf(h, pow(1.0 - float(d) / r, 1.3))
	var tag: String = map.get_cell(c).tag
	if ctx.origin_room != "" and tag == ctx.origin_room:
		h = maxf(h, ORIGIN_ROOM_HEAT)
	h = maxf(h, BASE_HEAT * clampf(float(Hex.distance(c, ctx.start)) / 14.0, 0.0, 1.0))
	if ctx.start_room != "" and tag == ctx.start_room:
		h *= START_ROOM_MULT
	return clampf(h, 0.0, 1.0)


# ---------------------------------------------------------------------- marks

## Weighted kind choice. Low heat is wear (rubble, paper, glass, wax); high heat is the infestation.
static func _pick_kind(rng: RandomNumberGenerator, h: float, corridor: bool) -> String:
	var kinds: Array[String] = ["scorch", "scratch", "ichor", "crack", "rubble", "paper", "glass", "wax"]
	var w: Array[float] = [
		0.5 + 2.2 * h, 1.1 + 1.4 * h, 0.1 + 3.6 * h * h, 0.25 + 1.5 * h, 1.4,
		0.2 if corridor else 1.3 * (1.0 - h), 0.9 * (1.0 - h), 0.2 if corridor else 0.8 * (1.0 - h),
	]
	var total := 0.0
	for x in w:
		total += x
	var roll := rng.randf() * total
	for i in kinds.size():
		roll -= w[i]
		if roll <= 0.0:
			return kinds[i]
	return kinds[kinds.size() - 1]


## A mark of `kind` at a random spot of cell `c` (its content kept inside the tile top).
static func _make(map: HexMap, rng: RandomNumberGenerator, c: Vector2i, kind: String, source: String) -> Mark:
	var m := Mark.new()
	m.kind = kind
	m.source = source
	m.cell = c
	m.variant = rng.randi() % maxi(GrimeAtlas.variant_count(kind), 1)
	var s: float
	match kind:
		"crack": s = 1.7
		"scorch": s = rng.randf_range(1.1, 1.7)
		"scratch": s = rng.randf_range(1.0, 1.5)
		"ichor", "spill", "wine", "oil", "rust": s = rng.randf_range(0.85, 1.5)
		"popcorn", "chalk": s = rng.randf_range(1.0, 1.6)
		"rubble": s = rng.randf_range(0.9, 1.5)
		"paper": s = rng.randf_range(0.9, 1.4)
		"glass": s = rng.randf_range(0.8, 1.3)
		"wax": s = rng.randf_range(0.8, 1.3)
		_: s = rng.randf_range(0.9, 1.4)
	m.size = Vector2(s, s)
	var room := maxf(0.0, minf(0.42, REACH - GrimeAtlas.CONTENT * s))
	var off := Vector2(1.0, 0.0).rotated(rng.randf() * TAU) * sqrt(rng.randf()) * room
	var cell: HexMap.Cell = map.get_cell(c)
	var w := Hex.to_world(c, float(cell.level))
	m.pos = Vector3(w.x + off.x, w.y + Grime.LIFT, w.z + off.y)
	m.rot = rng.randf() * TAU
	m.alpha = Grime.style_alpha(kind) * rng.randf_range(0.82, 1.0)
	m.glow = Grime.style_glow(kind)
	var v := rng.randf_range(0.9, 1.08)
	m.tint = Color(v, v, v, 1.0)
	return m


## Theme id -> atlas kind ("" when the theme has no grime of its own).
static func theme_kind(theme_id: String) -> String:
	var id := theme_id.to_lower()
	for key: String in THEME_KINDS:
		if id.contains(key):
			return str(THEME_KINDS[key])
	return ""


static func _theme_marks(map: HexMap, ctx: Ctx, cells: Array[Vector2i], rng: RandomNumberGenerator, per_cell: Dictionary) -> Array[Mark]:
	var out: Array[Mark] = []
	if ctx.themes.is_empty():
		return out
	for c in cells:
		var tag: String = map.get_cell(c).tag
		if not ctx.themes.has(tag):
			continue
		var kind := theme_kind(str(ctx.themes[tag]))
		if kind == "":
			continue
		var chance := THEME_CHANCE * (0.35 if tag == ctx.start_room else 1.0)
		if rng.randf() >= chance or int(per_cell.get(c, 0)) >= CELL_CAP:
			continue
		var m := _make(map, rng, c, kind, "theme")
		m.heat = 0.5
		out.append(m)
		per_cell[c] = int(per_cell.get(c, 0)) + 1
	return out


# ---------------------------------------------------------------------- trails

## Ichor drag trails: from each gate along the nearest corridors, leading away.
static func _trails(map: HexMap, ctx: Ctx, rng: RandomNumberGenerator, per_cell: Dictionary) -> Array[Mark]:
	var out: Array[Mark] = []
	for gi in ctx.gates.size():
		var gc := ctx.gates[gi]
		var dist: Dictionary = {gc: 0}
		var parent: Dictionary = {}
		var queue: Array[Vector2i] = [gc]
		var head := 0
		while head < queue.size():
			var cur := queue[head]
			head += 1
			if int(dist[cur]) >= TRAIL_SEARCH:
				break
			for d in Hex.DIRS:
				var nb: Vector2i = cur + d
				if dist.has(nb) or not map.is_walkable_cell(nb) or map.cell_transition(cur, nb) == HexMap.Move.BLOCKED:
					continue
				dist[nb] = int(dist[cur]) + 1
				parent[nb] = cur
				queue.append(nb)
		var entries: Array[Vector2i] = []
		for c in queue:
			if map.get_cell(c).tag == "corridor":
				var far := true
				for e in entries:
					if Hex.distance(e, c) < 7:
						far = false
				if far:
					entries.append(c)
					if entries.size() >= TRAILS_PER_GATE:
						break
		for entry in entries:
			var tail := entry   # the corridor cell the trail runs out to: the farthest one through this entry
			for c in queue:
				var dc: int = dist[c]
				if dc <= int(dist[tail]) or dc > int(dist[entry]) + TRAIL_EXTEND or map.get_cell(c).tag != "corridor":
					continue
				var x := c
				var ok := true
				while x != entry:
					if not parent.has(x) or map.get_cell(x).tag != "corridor":
						ok = false
						break
					x = parent[x]
				if ok:
					tail = c
			var path: Array[Vector2i] = [tail]
			while path[0] != gc and parent.has(path[0]):
				path.push_front(parent[path[0]])
			_lay_trail(map, ctx, rng, path, per_cell, out)
	return out


static func _lay_trail(map: HexMap, ctx: Ctx, rng: RandomNumberGenerator, path: Array[Vector2i], per_cell: Dictionary, out: Array[Mark]) -> void:
	var n := path.size()
	for i in range(1, n):
		var c := path[i]
		if not eligible(map, ctx, c) or int(per_cell.get(c, 0)) >= CELL_CAP - 1:
			continue
		var t := 1.0 - 0.6 * float(i) / n
		if rng.randf() > 0.95 * t:
			continue
		var a := Hex.to_world(path[i - 1])
		var b := Hex.to_world(path[mini(i + 1, n - 1)])
		var dir := Vector2(b.x - a.x, b.z - a.z)
		if dir.length() < 0.01:
			dir = Vector2(1, 0)
		dir = dir.normalized()
		var side := Vector2(-dir.y, dir.x)
		var m := _make(map, rng, c, "drag", "trail")
		var cell: HexMap.Cell = map.get_cell(c)
		var w := Hex.to_world(c, float(cell.level))
		var o := dir * rng.randf_range(-0.2, 0.2) + side * rng.randf_range(-0.3, 0.3)
		m.pos = Vector3(w.x + o.x, w.y + Grime.LIFT, w.z + o.y)
		m.rot = atan2(-dir.y, dir.x) + rng.randf_range(-0.2, 0.2)
		m.size = Vector2(1.5, 0.62) * rng.randf_range(0.85, 1.15) * (0.7 + 0.3 * t)
		m.heat = t
		out.append(m)
		per_cell[c] = int(per_cell.get(c, 0)) + 1
		if i % 3 == 0:   # a puddle where it was dragged through
			var p := _make(map, rng, c, "ichor", "trail")
			p.size = Vector2.ONE * rng.randf_range(0.6, 0.95)
			var o2 := side * rng.randf_range(-0.35, 0.35)
			p.pos = Vector3(w.x + o2.x, w.y + Grime.LIFT, w.z + o2.y)
			p.heat = t
			out.append(p)
			per_cell[c] = int(per_cell.get(c, 0)) + 1

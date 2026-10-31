class_name HauntPlanner
extends RefCounted
## A haunted floor's ghosts and the hosts they possess (docs/design/haunted-build-plan.md, "H5 as built"): plan() puts the
## hosts against the rooms' walls (SitePlan.haunts) and says which ones a ghost is in when the floor starts; spawn() puts them
## on the floor, the last actors (after the processions: no earlier net id moves), the hosts first, then a Wisp inside each
## possessed one. Nothing on a hellgate contract's floors (their plan has no haunts: the checksum's plan part leaves `haunts`
## out at [], NetFloor.PLAN_DEFAULTS). SiteBuilder.plan / spawn call them.
##
## HOW MANY: WISPS per floor (the ghosts), and HOSTS_PER_WISP x that many hosts plus one (so every ghost has a dormant host to
## flee to when its first one breaks), fewer when the floor has fewer rooms to put them in. At most one host a room.
## WHERE (own dice, from the floor seed): every room but the start, arrival and exit rooms, a crypt's included; in each a cell
## against a wall (at least two wall sides, every open side the same room's: not in a doorway), clear of whatever is planned
## there (SitePlan.blocked), at least APART from another host; a wall side is a wall cell or a cell a midpoint wall cuts. It
## stands toward the wall's face (WALL_IN at most, WALL_GAP off the face: HexMap.nearest_wall), facing into the room.
## WHICH KIND: a suit of armour in the mansion's house rooms (ARMOUR_SHARE of them), else a skeleton (the church's rooms and
## every crypt room: bones).
## WHICH ARE POSSESSED: the first in the seeded order, then each time the one farthest from those already picked.

const WISPS: Array[int] = [2, 2, 3]  ## ghosts on floors 1, 2, 3
const HOSTS_PER_WISP := 2
const ARMOUR_SHARE := 0.65          ## a mansion house room's host is a suit of armour this often (else bones)
const APART := 4                    ## cells between two hosts at least
const WALL_IN := 0.75               ## it stands up to this far toward the wall from its cell's middle (still in the cell) ...
const WALL_GAP := 0.6               ## ... and no nearer the wall's face than this (its plinth, its back)
const WALL_REACH := 2.0             ## the wall face it backs onto is this close to its cell's middle at most


## How many ghosts a floor of this run has (0 on a hellgate contract).
static func wisps_on(run: ContractRun, floor_n: int) -> int:
	if run == null or run.family != ClientArchetype.FAMILY_DEAD or floor_n < 1:
		return 0
	return WISPS[mini(floor_n, WISPS.size()) - 1]


static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var want := wisps_on(run, floor_n)
	if want <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 7177 + floor_n * 53 + 29
	var skip := {p.start_room: true, p.exit_room: true, SiteBuilder.arrival_room(p): true}
	var crypt := {}
	for tag: Variant in (CryptPlanner.record(map).get("rooms", []) as Array):
		crypt[str(tag)] = true
	var tags: Array[String] = []
	for tag: String in SiteBuilder._room_tags(p):
		if not skip.has(tag):
			tags.append(tag)
	_shuffle(tags, rng)
	var hosts_max := want * HOSTS_PER_WISP + 1
	var out: Array[Dictionary] = []
	for tag in tags:
		if out.size() >= hosts_max:
			break
		var cells := _wall_cells(map, p, tag, out)
		if cells.is_empty():
			continue
		var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var kind := "bones"
		if run.site_type == "mansion" and not crypt.has(tag) and rng.randf() < ARMOUR_SHARE:
			kind = "armour"
		var w := Hex.to_world(c, float(level_of(map, c)))
		var face := map.nearest_wall(w, WALL_REACH)
		var n: Vector2 = face["normal"] if not face.is_empty() else _wall_normal(map, c)   # (into the room, off its wall)
		var back := clampf(float(face.get("dist", 0.0)) - WALL_GAP, 0.0, WALL_IN)
		var pos := Vector2(w.x, w.z) - n * back
		out.append({"kind": kind, "cell": c, "pos": pos, "dir": n, "room": tag, "ghost": false})
	if out.is_empty():
		return
	# the possessed ones: the first, then the farthest from those already picked
	var picked: Array[int] = [0]
	while picked.size() < mini(want, out.size()):
		var best := -1
		var best_d := -1
		for i in out.size():
			if picked.has(i):
				continue
			var d := 1 << 20
			for j in picked:
				d = mini(d, Hex.distance(out[i]["cell"], out[j]["cell"]))
			if d > best_d:
				best_d = d
				best = i
		picked.append(best)
	for i in picked:
		out[i]["ghost"] = true
	p.haunts.assign(out)


## The room's cells a host may stand on: full floor at the room's level, free, against a wall (two wall sides or more), not in
## a doorway (every open side is the same room's), APART from the hosts already planned.
static func _wall_cells(map: HexMap, p: SitePlan, tag: String, planned: Array[Dictionary]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var level := int(p.base_levels.get(tag, 0))
	for c: Vector2i in (p.rooms[tag] as Array):
		var cell := map.get_cell(c)
		if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != level or not map.is_walkable_cell(c):
			continue
		if p.blocked.has(c) or map.is_pool_cell(c) or map.no_stand.has(c):
			continue
		var walls := 0
		var ok := true
		for d in Hex.DIRS:
			var nb := map.get_cell(c + d)
			if nb == null or nb.type == HexMap.Tile.WALL or nb.wall_mask != 0:
				walls += 1
			elif nb.tag != tag or nb.level != level or p.blocked.has(c + d):
				ok = false
				break
		if not ok or walls < 2 or map.nearest_wall(Hex.to_world(c, float(level)), WALL_REACH).is_empty():
			continue
		for h in planned:
			if Hex.distance(h["cell"], c) < APART:
				ok = false
				break
		if ok:
			out.append(c)
	return out


static func level_of(map: HexMap, c: Vector2i) -> float:
	var lv := map.ground_level(Hex.to_world(c))
	return 0.0 if is_nan(lv) else lv


## The unit X/Z way out of the walls round `c` (into the room).
static func _wall_normal(map: HexMap, c: Vector2i) -> Vector2:
	var at := Hex.to_world(c)
	var sum := Vector2.ZERO
	for d in Hex.DIRS:
		var nb := map.get_cell(c + d)
		if nb == null or nb.type == HexMap.Tile.WALL or nb.wall_mask != 0:
			var w := Hex.to_world(c + d)
			sum += Vector2(at.x - w.x, at.z - w.z)
	return sum.normalized() if sum.length() > 0.001 else Vector2(0.0, 1.0)


static func _shuffle(a: Array[String], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


static func spawn(map: HexMap, p: SitePlan, site: SiteBuilder.Site) -> void:
	for rec in p.haunts:
		site.hosts.append(build_host(map, str(rec["kind"]), rec["pos"] as Vector2, rec["dir"] as Vector2))
	for i in p.haunts.size():
		if bool(p.haunts[i]["ghost"]) and site.hosts[i] != null:
			var w := build_wisp(site.hosts[i])
			if w != null:
				site.wisps.append(w)


## A host of `kind` standing at X/Z `pos` (its floor), facing `dir`, dormant. The game's floors and the gym.
static func build_host(map: HexMap, kind: String, pos: Vector2, dir: Vector2) -> HauntHost:
	var c := Hex.from_world(Vector3(pos.x, 0.0, pos.y))
	var h := MonsterFactory.spawn(kind, c) as HauntHost
	if h == null:
		return null
	var gy := map.ground_height(Vector3(pos.x, 0.0, pos.y)) if map != null else 0.0
	h.global_position = Vector3(pos.x, h.global_position.y if is_nan(gy) else gy, pos.y)
	h.set_spawn_facing(Vector3(dir.x, 0.0, dir.y))
	h.reset_physics_interpolation()
	return h


## A ghost inside `host`, possessed from the start (`instant`: no wake and no event, every machine builds the floor so; the
## gym's "(possessed)" buttons pass false: it wakes). The game's floors and the gym.
static func build_wisp(host: HauntHost, instant: bool = true) -> Wisp:
	var w := MonsterFactory.spawn("wisp", host.current_cell()) as Wisp
	if w == null:
		return null
	w.global_position = host.global_position
	w.possess(host, instant)
	return w

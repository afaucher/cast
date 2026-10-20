class_name PackagePlanner
extends RefCounted
## The mail packages of a floor (MailPackage, docs/design/environment.md): plan() places the stacks near the room doors
## (SitePlan.packages) on dice of their own, spawn() puts every box into the world. SiteBuilder.plan / spawn call them;
## moved out of SiteBuilder verbatim (refactor plan H8).


const PACKAGE_MIN := 4                  ## mail package spots a floor
const PACKAGE_MAX := 6
const PACKAGE_SPACING := 5              ## hex cells between two spots (relaxed on tight floors)
const PACKAGE_DOOR_MIN := 2             ## a spot is at least this many cells from any corridor cell (the doorway stays clear) ...
const PACKAGE_DOOR_MAX := 6             ## ... and at most this many (near a door)
const PACKAGE_STACK_ODDS := [0.58, 0.30]   ## chance of a single box / a stack of two (otherwise three)


## 4-6 stacks of taped-up mail near the room doors. Runs after the decor, so it sees every body already placed
## (gates, employees, notes, priced props, decor and the clear lanes in front of them), and draws from its own
## RNG, so adding or changing it never moves a prop, a piece of decor or a pack.
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan, ctx: ThemeCtx) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = run.floor_seed(floor_n) * 6151 + floor_n * 29 + 11
	var want := rng.randi_range(PACKAGE_MIN, PACKAGE_MAX)
	var door_d := SiteBuilder._corridor_distance(map, PACKAGE_DOOR_MAX)
	var tags: Array = ctx.rooms.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	# Candidates: wall-backed poses on open room floor, 2-6 cells from the nearest corridor cell.
	var cands: Array[Dictionary] = []
	for tag: String in tags:
		var room: ThemeCtx.RoomInfo = ctx.rooms[tag]
		for c in room.cells:
			var dd := int(door_d.get(c, -1))
			if dd < PACKAGE_DOOR_MIN or ctx.wall_dirs(c).is_empty() or not room.open.has(c):
				continue
			var kind := "small"
			if rng.randf() >= 0.3:
				kind = "medium" if rng.randf() < 0.65 else "long"
			var dims := PackageModels.size_of(kind)
			var pose := ctx.wall_pose(room, c, dims.x, dims.z, rng.randf_range(-12.0, 12.0))
			var score := absf(float(dd) - 3.0) + rng.randf() * 2.5
			if pose.is_empty() or not _package_fits(ctx, room, door_d, pose["pos"], pose["yaw"], dims.x, dims.z):
				continue
			cands.append({"room": tag, "kind": kind, "pose": pose, "score": score, "cell": c})
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) < float(b["score"])
		return SiteBuilder._cell_less(a["cell"], b["cell"]))
	var picked: Array[Dictionary] = []
	var per_room: Dictionary = {}
	var used: Dictionary = {}
	for pass_n in 3:
		# one per room, well apart; then two a room, a bit closer; then anything that fits (tight floors)
		var spacing := maxi(2, PACKAGE_SPACING - 2 * pass_n)
		var room_cap := 1 + pass_n
		for i in cands.size():
			var cd := cands[i]
			if picked.size() >= want:
				break
			if used.has(i) or int(per_room.get(cd["room"], 0)) >= room_cap:
				continue
			var ok := true
			for other in picked:
				if Hex.distance(other["cell"], cd["cell"]) < spacing:
					ok = false
					break
			if not ok:
				continue
			used[i] = true
			picked.append(cd)
			per_room[cd["room"]] = int(per_room.get(cd["room"], 0)) + 1
	for cd in picked:
		var pose: Dictionary = cd["pose"]
		var kind: String = cd["kind"]
		var dims := PackageModels.size_of(kind)
		var roll := rng.randf()
		var one := float(PACKAGE_STACK_ODDS[0])
		var stack := 1 if roll < one else (2 if roll < one + float(PACKAGE_STACK_ODDS[1]) else 3)
		var sizes: Array[String] = [kind]
		var twists: Array[float] = [0.0]
		var shifts: Array[Vector2] = [Vector2.ZERO]
		for i in range(1, stack):
			# a box on top is the same size or a small one: never wider than what it sits on
			sizes.append(kind if (kind == "small" or rng.randf() < 0.5) else "small")
			twists.append(rng.randf_range(-11.0, 11.0))
			shifts.append(Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.03)))
		var pos: Vector2 = pose["pos"]
		var yaw: float = pose["yaw"]
		var room: ThemeCtx.RoomInfo = ctx.rooms[cd["room"]]
		ctx.add_body(room, pos, yaw, dims.x, dims.z, -1, "package")
		p.packages.append({"cell": ThemeGeo.cell_of(pos), "pos": pos, "yaw": yaw, "stack": stack, "room": cd["room"],
				"seed": rng.randi() & 0x3FFFFFFF, "sizes": sizes, "twists": twists, "shifts": shifts})


## Does a box footprint stand on open room floor clear of everything already planned (bodies, lanes, the
## start / exit zones, hellgate zones, blocking decor) and out of the doorway (corridor distance >= PACKAGE_DOOR_MIN)?
static func _package_fits(ctx: ThemeCtx, room: ThemeCtx.RoomInfo, door_d: Dictionary, pos: Vector2, yaw: float, w: float, d: float) -> bool:
	for pt in ThemeGeo.foot_points(pos, yaw, w, d):
		var pc := ThemeGeo.cell_of(pt)
		if not room.open.has(pc) or ctx.avoid.has(pc) or ctx.gate_zone.has(pc) or ctx.solid.has(pc) or int(door_d.get(pc, 99)) < PACKAGE_DOOR_MIN:
			return false
		if ctx.map.blocks_point(Vector3(pt.x, 0.0, pt.y)):
			return false   # the wall side of a cut cell
	if not ctx.rect_clear(pos, yaw, w, d):
		return false
	for b in room.bodies:
		if ThemeGeo.overlap(pos, yaw, w, d, b.pos, b.yaw, b.w, b.d, 0.0):
			return false
	return true


## Every planned stack, in plan order (each box its own actor: a stack of 3 is three entries in site.packages).
static func spawn(p: SitePlan, site: SiteBuilder.Site) -> void:
	for pk in p.packages:
		site.packages.append_array(_spawn_package(pk))


## One stack of mail: each box is its own MailPackage, resting on the one below (same or smaller size, a little
## twisted and shifted so it looks stacked by hand).
static func _spawn_package(pk: Dictionary) -> Array[Actor]:
	var out: Array[Actor] = []
	var sizes: Array = pk["sizes"]
	var twists: Array = pk["twists"]
	var shifts: Array = pk["shifts"]
	var base_pos: Vector2 = pk["pos"]
	var base_yaw: float = pk["yaw"]
	var seed_base: int = pk["seed"]
	var below: MailPackage = null
	var lift := 0.0
	for i in int(pk["stack"]):
		var kind: String = sizes[i]
		var shift: Vector2 = shifts[i]
		var m := MailPackage.spawn(base_pos + shift, {"size": kind, "yaw": base_yaw + float(twists[i]), "lift": lift,
				"below": below, "stack": i, "seed": seed_base + i * 7919})
		if m == null:
			break
		out.append(m)
		lift += PackageModels.height_of(kind)
		below = m
	return out

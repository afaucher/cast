extends MonsterTestBase
## The lava cave prototype (docs/design/lava-playtest.md; LavaCave, LavaField; the dev flag --lava-cave):
##   - every layout: a climb-free way from the start to the exit on the two-wide bridges, archers on rock no path reaches,
##     every two-wide row with its lane, the same map every build;
##   - lava is void with a burn: a monster shoved off a bridge dies in it, a hero is pulled back onto the rock with 15
##     damage and burning;
##   - damp crusts the lava: walkable for LavaField.CRUST_LIFE, then it melts, and whoever stands on it gets the lava
##     rule (the hero back on the nearest rock, burned; the monster sinks).
## The playtest's fixes (2026-10-20):
##   - every span of every layout (one-wide too) is walkable end to end, steered exactly or with the eight WASD directions,
##     and from a start ON a shared edge or next to a shared vertex of two span cells (where a one-wide span meets lava on
##     both sides): never stuck, never standing over the lava ("I was between the hexes");
##   - an AI ally following the leader over a bridge, onto a crust and back never stands on the lava and keeps up;
##   - fog is symmetric between the spaces a crew walks: from every walkway cell the walkway beside it shows, both ways;
##     the two walkways of the causeway are one space; every doorway sits on its rock, not on the lava bed.


func setup() -> void:
	timeout_sec = 240.0
	_check_layouts()
	await _check_shoves()
	await _check_crust()
	_check_spans()
	await _check_ally_follow()
	_check_fog_symmetry()
	finish()


func _check_layouts() -> void:
	for id in range(1, LavaCave.COUNT + 1):
		var r := LavaCave.check(id)
		check(bool(r["ok"]), "layout %d (%s): %s" % [id, LavaCave.layout(id)["name"], ", ".join(r["problems"]) if not r["ok"] else "ok"])
		var a := LavaCave.build_map(id)
		var b := LavaCave.build_map(id)
		var same := a.cells.size() == b.cells.size()
		for c: Vector2i in a.cells:
			same = same and b.has_cell(c) and a.cells[c].level == b.cells[c].level and a.cells[c].tag == b.cells[c].tag
		check(same, "layout %d builds the same map every time" % id)
		check(not LavaCave.lava_cells(a).is_empty(), "layout %d has lava" % id)
		var p := LavaCave.plan(a, 1)
		check(p.rooms.size() >= 2 and p.start != p.exit, "layout %d: a plan with rooms (%d), a start and an exit" % [id, p.rooms.size()])


## The cave (layout 1) with its LavaField active: returns the field.
func _cave() -> LavaField:
	var m := LavaCave.build_map(1)
	new_world(m)
	var f := LavaField.new()
	world.add_child(f)
	f.setup(m)
	f.activate()
	return f


## A bridge cell of layout 1's causeway and the direction off its near side (into the lava).
func _bridge_edge() -> Array:
	var b: Dictionary = LavaCave.layout(1)["bridges"][0]
	var rows := LavaCave.bridge_rows(b)
	var c: Vector2i = rows[3][0]
	return [c, Hex.dir_vector(5)]


func _check_shoves() -> void:
	var f := _cave()
	check(f.active and not GameWorld.map.has_cell(LavaCave.lava_cells(LavaCave.build_map(1))[0]), "active: the lava cells are void")
	var e := _bridge_edge()
	var cell: Vector2i = e[0]
	var off: Vector3 = e[1]
	var grunt := MonsterFactory.spawn("grunt", cell)
	grunt.aggro_range = 0.0
	await frames(2)
	grunt.shove(off, 3.0, null)
	var gone := await wait_until(func() -> bool: return grunt.dead or not is_instance_valid(grunt), 240)
	check(gone, "a grunt shoved off the bridge falls into the lava and dies")
	var hero := add_hero(cell, float(GameWorld.map.get_cell(cell).level))
	await frames(2)
	var hp0 := hero.hp
	hero.shove(off, 3.0, null)
	var back := await wait_until(func() -> bool: return not hero.is_shoved(), 240)
	check(back, "the hero's shove ends")
	var under := Hex.from_world(hero.global_position)
	check(GameWorld.map.is_walkable_cell(under), "the hero is pulled back onto rock (%s)" % under)
	near(hp0 - hero.hp, 15.0, 1.6, "15 damage (the pull's 5 and the lava's 10; plus a burn tick at most): %.1f" % (hp0 - hero.hp))
	check(Burning.is_burning(hero), "and it burns")
	world.free()
	world = null


func _check_crust() -> void:
	var f := _cave()
	var e := _bridge_edge()
	var cell: Vector2i = e[0]
	var off: Vector3 = e[1]
	var at := Hex.to_world(cell, float(GameWorld.map.get_cell(cell).level))
	var d := Damp.new()
	d.power = 1.0
	GameWorld.spawn(d, at)
	await frames(30)
	check(f.crusts.size() == 1, "a damp at the bridge's edge crusts the lava (%d crusts)" % f.crusts.size())
	var crust_cell := Hex.from_world(at + off * Hex.SQRT3 * 2.0)
	check(GameWorld.map.is_walkable_cell(crust_cell), "the lava two cells off the bridge is crust: walkable")
	check(GameWorld.map.find_path(cell, crust_cell, false).size() > 0, "a path leads onto it")
	var hero := add_hero(crust_cell, float(LavaCave.CRUST_LEVEL))
	var mon := MonsterFactory.spawn("grunt", crust_cell + Hex.DIRS[1])
	mon.aggro_range = 0.0
	var hp0 := hero.hp
	var melted := await wait_until(func() -> bool: return f.crusts.is_empty(), int((LavaField.CRUST_LIFE + 1.0) * 60.0))
	check(melted, "the crust melts after about %.0f s" % LavaField.CRUST_LIFE)
	check(not GameWorld.map.has_cell(crust_cell), "its cells are lava again")
	await wait_until(func() -> bool: return not hero.is_shoved(), 240)
	check(GameWorld.map.is_walkable_cell(Hex.from_world(hero.global_position)), "the hero on the crust is put back on rock")
	check(hp0 - hero.hp >= 14.0, "with the lava's damage (%.1f)" % (hp0 - hero.hp))
	var sunk := await wait_until(func() -> bool: return mon.dead or not is_instance_valid(mon), 240)
	check(sunk, "the grunt on the crust sinks")
	world.free()
	world = null


# --- every span walkable, from edges and vertices too (playtest: "stuck in a seam") -------------------------------

## The eight directions WASD gives (screen-relative, the game camera's yaw).
func _eight() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			if x != 0 or y != 0:
				out.append(PlayerController.move_direction(Vector2(x, y).normalized(), null))
	return out


## Walk `h` through `points` (world): steered straight at the next point, or with the best of the eight WASD
## directions every frame (a player switching keys). {arrived, void_frames, frames}.
func _walk(m: HexMap, h: Hero, points: Array[Vector3], eight: bool) -> Dictionary:
	var dirs := _eight()
	var dt := 1.0 / 60.0
	var i := 0
	var count := 0
	var over := 0
	var reach := 0.45 if eight else 0.3
	while i < points.size() and count < 60 * 30:
		var d := points[i] - h.global_position
		d.y = 0.0
		if d.length() < reach:
			i += 1
			continue
		var dir := d.normalized()
		if eight:
			var best := dirs[0]
			for e in dirs:
				if e.dot(dir) > best.dot(dir):
					best = e
			dir = best
		h.move(dir, dt)
		count += 1
		if is_nan(m.ground_height(h.global_position)):
			over += 1
	return {"arrived": i >= points.size(), "void_frames": over, "frames": count}


## Walk `h` along a span the way a player does: for each straight leg (route rows legs[i]..legs[i+1]) HOLD the one WASD
## key closest to the leg's direction until the hero is past the leg's end; switch keys at a kink. From row `from_row`.
## {arrived, void_frames, frames}.
func _walk_held(m: HexMap, h: Hero, centres: Array[Vector3], legs: Array[int], from_row: int, rank: int = 0) -> Dictionary:
	var dirs := _eight()
	var dt := 1.0 / 60.0
	var count := 0
	var over := 0
	for li in legs.size() - 1:
		var a := centres[legs[li]]
		var b := centres[legs[li + 1]]
		if legs[li + 1] < from_row:
			continue
		var leg := Vector3(b.x - a.x, 0, b.z - a.z)
		var along := leg.normalized()
		# the key closest to the leg (rank 0) or the next closest (rank 1: the other key a player might hold)
		var ranked := dirs.duplicate()
		ranked.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.dot(along) > y.dot(along))
		var key: Vector3 = ranked[rank]
		var stall := 0
		var best := INF
		while count < 60 * 30:
			var to_end := Vector3(b.x - h.global_position.x, 0, b.z - h.global_position.z)
			var ahead := to_end.dot(along)
			if ahead < 0.3:
				break   # past this leg's end (held keys drift sideways a little: the leg's line is what counts)
			h.move(key, dt)
			count += 1
			if is_nan(m.ground_height(h.global_position)):
				over += 1
			if ahead < best - 0.01:
				best = ahead
				stall = 0
			else:
				stall += 1
			if stall > 90:
				return {"arrived": false, "void_frames": over, "frames": count, "stuck_at": h.global_position.snapped(Vector3.ONE * 0.01), "leg": li}
	return {"arrived": true, "void_frames": over, "frames": count}


func _check_spans() -> void:
	var walks := 0
	var bad: Array[String] = []
	for id in range(1, LavaCave.COUNT + 1):
		var m := LavaCave.build_map(id)
		for c in LavaCave.lava_cells(m):
			m.cells.erase(c)
		new_world(m)
		var L := LavaCave.layout(id)
		var h := HeroFactory.spawn_hero(L["start"], "Walker", Color.WHITE)
		for bi in (L["bridges"] as Array).size():
			var rows := LavaCave.bridge_rows(L["bridges"][bi])
			var route: Array[Vector2i] = []
			for row: Array in rows:
				route.append(row[0])
			var centres: Array[Vector3] = []
			for c in route:
				centres.append(Hex.to_world(c, float(m.cells[c].level)))
			# starts: the first cell's centre, then ON each shared edge of two span cells and next to both ends of it
			var starts: Array = [[centres[0], 1]]
			for k in route.size() - 1:
				var a: Vector2i = route[k]
				var b: Vector2i = route[k + 1]
				var d := Hex.dir_to(a, b)
				var ca := Hex.to_world(a)
				var mid := (ca + Hex.to_world(b)) * 0.5
				starts.append([mid, k + 1])
				for corner: Vector3 in [ca + Hex.kite_corner(posmod(d - 1, 6)), ca + Hex.kite_corner(d)]:
					var p := corner.lerp(mid, 0.08)
					if not is_nan(m.ground_height(p)):
						starts.append([p, k + 1])
			# the waypoints' rows along the route (a kinked span has several straight legs)
			var legs: Array[int] = []
			for wp: Vector2i in L["bridges"][bi]["pts"]:
				legs.append(maxi(0, route.find(wp)))
			for st: Array in starts:
				for mode: String in ["straight", "wasd", "held", "held2"]:
					var p: Vector3 = st[0]
					p.y = m.ground_height(p)
					h.global_position = p
					var r: Dictionary
					if mode.begins_with("held"):
						r = _walk_held(m, h, centres, legs, int(st[1]), 1 if mode == "held2" else 0)
					else:
						var pts: Array[Vector3] = []
						for j in range(int(st[1]), centres.size()):
							pts.append(centres[j])
						r = _walk(m, h, pts, mode == "wasd")
					walks += 1
					if not r["arrived"] or int(r["void_frames"]) > 0:
						bad.append("cave %d span %d from %s (%s): %s" % [id, bi, (st[0] as Vector3).snapped(Vector3.ONE * 0.01), mode, r])
	check(bad.is_empty(), "every span walks end to end in %d walks, never over the lava%s" % [walks, (": " + "; ".join(bad.slice(0, 6))) if not bad.is_empty() else ""])
	if world != null:
		world.free()
		world = null


# --- an AI ally follows over a bridge and a crust (playtest: "The AI walked on the lava and got stuck") ---------------

func _check_ally_follow() -> void:
	var f := _cave()
	var m := GameWorld.map
	var L := LavaCave.layout(1)
	var start: Vector2i = L["start"]
	var leader := HeroFactory.spawn_hero(start, "Lead", Color.WHITE)
	var ally := HeroFactory.spawn_hero(start + Hex.DIRS[3], "Ally", Color.WHITE)
	HeroFactory.make_ally(ally, leader, false, 150.0)
	var b0: Vector2i = L["chambers"][1][1]
	var pts: Array[Vector3] = [Hex.to_world(L["chambers"][0][1])]
	for row: Array in LavaCave.bridge_rows(L["bridges"][0]):
		pts.append(Hex.to_world(row[0], float(m.cells[row[0]].level)))
	pts.append(Hex.to_world(b0))
	var edge: Vector2i = b0 + Hex.DIRS[0] * 3
	pts.append(Hex.to_world(edge, float(m.cells[edge].level)))
	var state := {"over": 0, "max_gap": 0.0}
	var hp0 := ally.hp
	# out along the bridge to the far chamber's east edge
	await _lead(leader, ally, m, pts, state, 60 * 20)
	# a damp at the edge crusts the lava; the leader walks two cells onto the crust, waits, and comes back
	var d := Damp.new()
	d.power = 1.0
	GameWorld.spawn(d, Hex.to_world(edge, float(m.cells[edge].level)))
	await frames(30)
	var crusted := f.crusts.size() == 1
	var on_crust: Array[Vector3] = [Hex.to_world(edge + Hex.DIRS[0], float(LavaCave.CRUST_LEVEL)), Hex.to_world(edge + Hex.DIRS[0] * 2, float(LavaCave.CRUST_LEVEL))]
	await _lead(leader, ally, m, on_crust, state, 60 * 3)
	await _lead(leader, ally, m, [] as Array[Vector3], state, 60)
	var back: Array[Vector3] = [Hex.to_world(edge, float(m.cells[edge].level)), Hex.to_world(b0)]
	await _lead(leader, ally, m, back, state, 60 * 4)
	# the crust melts with the crew back on rock; the ally settles by the leader
	await _lead(leader, ally, m, [] as Array[Vector3], state, 60 * 9)
	check(crusted, "the damp crusted the lava by the far chamber")
	check(int(state["over"]) == 0, "the ally never stood over the lava (%d frames)" % int(state["over"]))
	check(ally.hp >= hp0 - 0.01 and not Burning.is_burning(ally), "the ally never fell in (hp %.0f / %.0f)" % [ally.hp, hp0])
	var gap := GameWorld.flat_distance(ally.global_position, leader.global_position)
	check(gap < 4.5, "the ally keeps up with the leader: %.1f apart at the end (at most %.1f on the way)" % [gap, float(state["max_gap"])])
	world.free()
	world = null
	# and single file over the one-wide goat path, with the wide bridge two hexes away the whole way
	_cave()
	m = GameWorld.map
	leader = HeroFactory.spawn_hero(start, "Lead", Color.WHITE)
	ally = HeroFactory.spawn_hero(start + Hex.DIRS[3], "Ally", Color.WHITE)
	HeroFactory.make_ally(ally, leader, false, 150.0)
	var goat: Array[Vector3] = [Hex.to_world(L["chambers"][0][1])]
	for row: Array in LavaCave.bridge_rows(L["bridges"][1]):
		goat.append(Hex.to_world(row[0], float(m.cells[row[0]].level)))
	goat.append(Hex.to_world(b0))
	state = {"over": 0, "max_gap": 0.0}
	hp0 = ally.hp
	await _lead(leader, ally, m, goat, state, 60 * 25)
	await _lead(leader, ally, m, [] as Array[Vector3], state, 60 * 6)
	check(int(state["over"]) == 0 and ally.hp >= hp0 - 0.01, "over the goat path the ally never stands over the lava (%d frames, hp %.0f / %.0f)" % [int(state["over"]), ally.hp, hp0])
	gap = GameWorld.flat_distance(ally.global_position, leader.global_position)
	check(gap < 4.5, "and keeps up: %.1f apart at the end" % gap)
	world.free()
	world = null


## Walk the leader through `points` (straight steering) for up to `max_frames` physics frames (the ally's brain runs),
## watching the ally: frames over the lava, its largest distance from the leader.
func _lead(leader: Hero, ally: Hero, m: HexMap, points: Array[Vector3], state: Dictionary, max_frames: int) -> void:
	var i := 0
	for fr in max_frames:
		if i < points.size():
			var d := points[i] - leader.global_position
			d.y = 0.0
			if d.length() < 0.35:
				i += 1
			else:
				leader.move(d.normalized(), 1.0 / 60.0)
		await get_tree().physics_frame
		if is_nan(m.ground_height(ally.global_position)):
			state["over"] = int(state["over"]) + 1
		state["max_gap"] = maxf(float(state["max_gap"]), GameWorld.flat_distance(ally.global_position, leader.global_position))
		if i >= points.size() and points.size() > 0:
			return


# --- fog is symmetric between the walkways (playtest: "only from one side") ------------------------------------------

func _check_fog_symmetry() -> void:
	for id in range(1, LavaCave.COUNT + 1):
		var m := LavaCave.build_map(id)
		var fog := RoomFog.build(m)
		var L := LavaCave.layout(id)
		# every doorway's middle stands on its rock (it sat on the lava bed, under the bridge: the one-sided sight lines)
		for dw in fog.doorways:
			var mid: Vector3 = dw["mid"]
			check(mid.y > float(LavaCave.LAVA_BED + 2) * Hex.LEVEL_HEIGHT, "cave %d doorway %d (%s / %s) on rock, not the lava bed: y %.2f" % [id, dw["id"], dw["room"], dw["hall"], mid.y])
		# the cells a hero can stand on: rock, not the archers' isles (no path reaches them)
		var isle := {}
		for il: Array in L["isles"]:
			for c in Hex.range_cells(il[1], int(il[2])):
				isle[c] = true
		var walk: Array[Vector2i] = []
		for c: Vector2i in m.cells:
			var tag: String = m.cells[c].tag
			if m.cells[c].level != LavaCave.LAVA_BED and not isle.has(c) and (tag == "corridor" or tag.begins_with("room:")):
				walk.append(c)
		var from := {}
		for c in walk:
			fog.seen.fill(0)
			fog.update([Hex.to_world(c, float(m.cells[c].level))])
			from[c] = fog.state.duplicate()
		# both ways: if a spot sees the space of a spot near it (4 hexes or less), that spot sees the first one's space
		var asym: Array[String] = []
		for a in walk:
			for b in walk:
				var sa := fog.space_of_cell(a)
				var sb := fog.space_of_cell(b)
				if sa == sb or Hex.distance(a, b) > 4:
					continue
				var ab: bool = (from[a] as PackedByteArray)[sb] == RoomFog.IN_VIEW
				var ba: bool = (from[b] as PackedByteArray)[sa] == RoomFog.IN_VIEW
				if ab != ba:
					asym.append("%s(%s)%s%s(%s)" % [a, fog.tags[sa], " sees " if ab else " seen by ", b, fog.tags[sb]])
		check(asym.is_empty(), "cave %d: walkway spots 4 hexes apart or less see each other's space both ways%s" % [id, (": " + ", ".join(asym.slice(0, 5))) if not asym.is_empty() else ""])
		for pair: Array in L.get("join", []):
			var ra: Vector2i = LavaCave.bridge_rows(L["bridges"][int(pair[0])])[1][0]
			var rb: Vector2i = LavaCave.bridge_rows(L["bridges"][int(pair[1])])[1][0]
			check(fog.space_of_cell(ra) == fog.space_of_cell(rb), "cave %d: walkways %d and %d side by side are one fog space" % [id, pair[0], pair[1]])

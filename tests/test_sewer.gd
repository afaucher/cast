extends MonsterTestBase
## The sewer slice, phase 1 (docs/design/sewer-concept.md, "Phase 1 as built"; SewerLayouts, Gator, LiveWire; the dev flag
## --sewer):
##   - LAYOUTS (1-5): the same map every build; the water is ONE connected body; every flooded hall's water joins two rooms'
##     channels; the water runs up to the walls (a wet cut cell's floor is water); every staged deck, prop, note, the
##     employee, the monsters' spots and the elevator's landing are reachable from the landing; the employee and the notes
##     stand on dry floor; the gator starts in its home region and can walk to each of its bask spots inside it; every
##     electrical panel has water to drop its cable into;
##   - THE GATOR: it watches (4.5) and leaves a body outside its territory alone; a body inside its territory (3.0) for 0.4 s
##     is nipped (10 and a shove away) after the 0.5 s wind-up, a monster too, one victim a nip; it relocates to another
##     bask spot, slowly and without leaving its region; a shove inside its region settles it where it lands, riled
##     (territory 4.5); shoved out of its region it walks home; with no way home it settles and never teleports; over a
##     long run it never stays stuck; corn in its water chums it (no nips); kill and bill once, to the killer; shoved into a
##     pit it dies and the shover is billed;
##   - THE LIVE WIRE: the panel bills $250 to whoever breaks it; the cable lands 0.6 s later and shocks everyone standing in
##     water within 5 cells of where it lands (12 x1.5 soaked = 18, a 0.6 s daze), then pulses 6 (x1.5) every 1.5 s for
##     6 s; a wader 7 cells away and a body on dry floor beside it are untouched; one use.

const L1 := 1


func _init() -> void:
	timeout_sec = 1200.0   # (game seconds: the gator checks run minutes of game time, a few seconds of wall time)


func setup() -> void:
	for n in range(1, SewerLayouts.COUNT + 1):
		_check_layout(n)
	print("sewer: layouts checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	await _check_watch_and_nip()
	print("sewer: watch and nip checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	await _check_relocation()
	print("sewer: relocation checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	await _check_shoves()
	print("sewer: shoves checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	await _check_stuck()
	print("sewer: stuck checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	await _check_long_run()
	print("sewer: long run checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	await _check_chum()
	await _check_bill()
	await _check_pit()
	print("sewer: chum, bill, pit checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	await _check_live_wire()
	print("sewer: live wire checked (game %.1f s, wall %d ms, frame %d)" % [GameWorld.time, Time.get_ticks_msec(), Engine.get_physics_frames()])
	if world != null:
		world.free()
		world = null
	finish()


# --- layouts -----------------------------------------------------------------------------------------------------------

func _check_layout(n: int) -> void:
	var L := SewerLayouts.build(n)
	var tag := "layout %d (%s)" % [n, L["name"]]
	var m: HexMap = L["map"]
	var again: HexMap = SewerLayouts.build(n)["map"]
	var same := m.cells.size() == again.cells.size()
	for c: Vector2i in m.cells:
		var a: HexMap.Cell = m.cells[c]
		var b: HexMap.Cell = again.get_cell(c)
		same = same and b != null and a.level == b.level and a.tag == b.tag and a.pool_mask == b.pool_mask and a.wall_mask == b.wall_mask
	check(same, "%s: the same map every build" % tag)
	# one body of water
	var wet: Dictionary = L["wet"]
	check(wet.size() > 30, "%s: it has water (%d wet cells)" % [tag, wet.size()])
	eq(SewerLayouts.components(wet), 1, "%s: all its water is one connected body" % tag)
	var body_recs := m.pools.filter(func(r: Dictionary) -> bool: return bool(r.get("body", false)))
	eq(body_recs.size(), 1, "%s: one body record in HexMap.pools (Wading reads it)" % tag)
	# every flooded hall joins two rooms' channels
	var halls: Dictionary = L["halls"]
	for hid: String in L["wet_halls"]:
		var hall := {}
		for c: Vector2i in (halls[hid] as Array):
			if wet.has(c):
				hall[c] = true
		check(hall.size() >= 3, "%s: hall %s is flooded" % [tag, hid])
		var rooms := {}
		for c: Vector2i in hall:
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				if wet.has(nb) and not hall.has(nb) and m.get_cell(nb).tag.begins_with("room:"):
					rooms[m.get_cell(nb).tag] = true
		check(rooms.size() >= 2, "%s: hall %s's water joins two rooms' channels (%s)" % [tag, hid, str(rooms.keys())])
	# water up to the walls: a wet cut cell's floor kites are water, its wall kites are wall
	var cut_wet := 0
	for c: Vector2i in wet:
		var cell: HexMap.Cell = m.cells[c]
		if cell.wall_mask == 0:
			continue
		cut_wet += 1
		for k in 6:
			var p := Hex.to_world(c) + (Hex.kite_corner(k) + Hex.edge_mid(k) + Hex.edge_mid((k + 1) % 6)) / 3.0 * 0.9
			if (cell.wall_mask >> k) & 1 == 1:
				check(m.wall_at(p) and not m.water_at(p), "%s: %s kite %d is wall" % [tag, c, k])
			else:
				check(m.water_at(p) and not m.wall_at(p), "%s: %s kite %d is water up to the wall" % [tag, c, k])
	check(cut_wet >= 2, "%s: the water reaches the walls (%d wet cut cells)" % [tag, cut_wet])
	# the elevator and what is reachable from its landing
	check(not m.elevator.is_empty(), "%s: the elevator stands on the landing deck" % tag)
	var landing: Vector2i = m.cells_with_tag("exit")[0]
	check(m.is_walkable_cell(landing) and m.get_cell(landing).pool_mask == 0, "%s: its landing is dry floor" % tag)
	var targets: Array = []
	for c: Vector2i in L["decks"]:
		targets.append(["deck", c])
	for e: Dictionary in L["monsters"]:
		targets.append(["monster " + str(e["kind"]), ThemeGeo.cell_of(e["at"])])
	for e: Dictionary in L["notes"]:
		targets.append(["note", e["cell"]])
		check(m.is_walkable_cell(e["cell"]) and not m.is_pool_cell(e["cell"]), "%s: the note at %s stands on dry floor" % [tag, e["cell"]])
	var emp: Dictionary = L["employee"]
	targets.append(["employee", emp["cell"]])
	check(m.is_walkable_cell(emp["cell"]) and not m.is_pool_cell(emp["cell"]), "%s: the employee stands on dry floor" % tag)
	for t: Array in targets:
		var c: Vector2i = t[1]
		var ok := m.has_cell(c) and m.get_cell(c).type != HexMap.Tile.WALL and not m.find_path(landing, c, false).is_empty()
		check(ok, "%s: the %s at %s is reachable from the landing" % [tag, t[0], c])
	for e: Dictionary in L["monsters"]:
		var at: Vector2 = e["at"]
		var p := Vector3(at.x, 0.0, at.y)
		check(not is_nan(m.ground_height(p)) and not m.wall_at(p), "%s: the %s at %s stands on floor" % [tag, e["kind"], at])
	for e: Dictionary in L["props"] + L["hazards"]:
		var pp: Vector2 = e["pos"]
		var p3 := Vector3(pp.x, 0.0, pp.y)
		check(not is_nan(m.ground_height(p3)) and not m.wall_at(p3) and not m.water_at(p3), "%s: the %s at %s stands on dry floor" % [tag, e["kind"], pp])
		if str(e["kind"]) == "electrical_panel":
			var face := Vector2(sin(deg_to_rad(float(e["yaw"]))), cos(deg_to_rad(float(e["yaw"]))))
			var drop := LiveWire.drop_point_for(m, pp, face)
			check(drop != Vector3.INF and m.water_at(drop), "%s: the panel at %s drops its cable into the water" % [tag, pp])
			if drop != Vector3.INF:
				check(GameWorld.flat_distance(drop, p3) < 4.5, "%s: ... within reach of the panel (%.1f)" % [tag, GameWorld.flat_distance(drop, p3)])
	# the gator's home region and its bask spots
	var gt: Dictionary = L["gator"]
	var region := Gator.region_of(m)
	var at0: Vector2 = gt["at"]
	check(region.has(Hex.from_world(Vector3(at0.x, 0.0, at0.y))), "%s: the gator starts in its home region" % tag)
	check(m.water_at(Vector3(at0.x, 0.0, at0.y)), "%s: ... in the water" % tag)
	for s: Vector2 in (gt["spots"] as Array):
		var sc := Hex.from_world(Vector3(s.x, 0.0, s.y))
		check(region.has(sc), "%s: bask spot %s is in its region" % [tag, sc])
		check(_region_reach(m, region, Hex.from_world(Vector3(at0.x, 0.0, at0.y)), sc), "%s: bask spot %s can be walked to inside the region" % [tag, sc])
	var dry_out := 0
	for c: Vector2i in m.cells:
		if m.is_walkable_cell(c) and not region.has(c):
			dry_out += 1
	check(dry_out > 20, "%s: dry floor outside the gator's region (%d cells): it does not own the floor" % [tag, dry_out])


func _region_reach(m: HexMap, region: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	var seen := {a: true}
	var q: Array[Vector2i] = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		if c == b:
			return true
		for d in Hex.DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or not region.has(n) or (n != b and not m.is_walkable_cell(n)):
				continue
			if n != b and m.cell_transition(c, n) != HexMap.Move.OK:
				continue
			seen[n] = true
			q.append(n)
	return false


# --- the gator --------------------------------------------------------------------------------------------------------

## Layout 1 in a fresh world, its gator (no monsters, no crew): [layout, gator].
func _gator_world() -> Array:
	var L := SewerLayouts.build(L1)
	new_world(L["map"])
	var gt: Dictionary = L["gator"]
	var spots: Array[Vector2] = []
	for s: Vector2 in (gt["spots"] as Array):
		spots.append(s)
	var g := Gator.spawn(gt["at"], gt["face"], Gator.region_of(L["map"]), spots, 1234)
	g._relocate_at = INF   # (no relocation unless a check asks for one)
	return [L, g]


## A walkable cell whose centre is `d` (+-0.45) from point p, preferring the gator's front; INF none.
func _cell_at(p: Vector3, d: float, fwd: Vector3 = Vector3.ZERO, dry: int = -1) -> Vector2i:
	var m := GameWorld.map
	var best := Vector2i(1 << 20, 0)
	var best_s := INF
	for c in Hex.range_cells(Hex.from_world(p), int(ceil(d / Hex.SQRT3)) + 2):
		if not m.is_walkable_cell(c):
			continue
		if dry == 1 and m.is_pool_cell(c) or dry == 0 and m.get_cell(c).pool_mask != HexMap.ALL_KITES:
			continue
		var w := Hex.to_world(c)
		var dd := GameWorld.flat_distance(w, p)
		if absf(dd - d) > 0.45:
			continue
		var s := absf(dd - d) - (fwd.dot((w - p).normalized()) if fwd != Vector3.ZERO else 0.0)
		if s < best_s:
			best_s = s
			best = c
	return best


func _stand(a: Actor, c: Vector2i) -> void:
	a.global_position = Hex.to_world(c)
	a.snap_to_ground()


func _check_watch_and_nip() -> void:
	var gw := _gator_world()
	var g: Gator = gw[1]
	await frames(2)
	eq(g.state, Gator.CALM, "the gator rests calm")
	eq(int(Gator.PRICES["regular"]), 6300, "a gator is billed $6,300")
	check(g.is_in_group("gators") and g.is_in_group(PricedProp.GROUP) and not g.is_in_group("monsters"), "it is property, not a monster")
	var fwd := Vector3(g.facing.x, 0.0, g.facing.z)
	# watch: a body at 4.0 from its head (outside the territory) is watched, never nipped
	var h := add_hero(Vector2i.ZERO)
	_stand(h, _cell_at(g.head(), 4.2, fwd))
	var watched := await wait_until(func() -> bool: return g.state == Gator.WATCH, 30)
	check(watched, "a body within 4.5 of its head: it watches (state %s)" % g.state_name())
	var hp0 := h.hp
	await frames(150)
	eq(g.nips, 0, "outside its territory nothing is nipped")
	near(h.hp, hp0, 0.01, "the watched body is unhurt")
	# nip: inside the territory for 0.4 s, the 0.5 s wind-up, then 10 and a shove away
	var c2 := _cell_at(g.head(), 1.9, fwd)
	_stand(h, c2)
	var t0 := GameWorld.time
	var wound := await wait_until(func() -> bool: return g.state == Gator.NIP, 60)
	check(wound, "inside its territory: the nip winds up")
	var tw := GameWorld.time - t0
	check(tw >= Gator.DWELL - 0.05 and tw <= Gator.DWELL + 0.2, "after %.2f s inside (the %.1f s dwell)" % [tw, Gator.DWELL])
	var bit := await wait_until(func() -> bool: return h.hp < hp0 - 0.5, 90)
	check(bit, "the nip lands")
	var tb := GameWorld.time - t0
	check(tb >= Gator.DWELL + Gator.NIP_WINDUP - 0.05, "after the %.1f s wind-up (%.2f s in all)" % [Gator.NIP_WINDUP, tb])
	near(hp0 - h.hp, Gator.NIP_DAMAGE, 0.5, "a nip is %d damage" % int(Gator.NIP_DAMAGE))
	var from := h.global_position
	var g_at := g.global_position
	await frames(30)
	var moved := h.global_position - from
	moved.y = 0.0
	var away := from - g_at
	away.y = 0.0
	check(moved.length() > 1.0 and moved.normalized().dot(away.normalized()) > 0.5, "and shoves the victim away from the gator (%.2f)" % moved.length())
	# monsters are nipped too, one victim a nip, and they don't turn on it
	_stand(h, _cell_at(g.head(), 7.0, -fwd))
	var gr := MonsterFactory.spawn("grunt", _cell_at(g.head(), 1.9, fwd))
	gr.aggro_range = 0.0
	var hp_g := gr.hp
	var hit := await wait_until(func() -> bool: return gr.hp < hp_g - 0.5, 150)
	check(hit, "a skeleton in its territory is nipped too")
	near(hp_g - gr.hp, Gator.NIP_DAMAGE, 0.5, "... for %d" % int(Gator.NIP_DAMAGE))
	check(gr.target != g, "and the skeleton does not turn on it")
	gr.free()
	var a1 := add_hero(Vector2i.ZERO)
	var a2 := add_hero(Vector2i.ZERO)
	var two := _cells_within(g.head(), 1.4, 2.6, 2)
	check(two.size() == 2, "two spots inside its territory")
	_stand(a1, two[0])
	_stand(a2, two[1])
	var hp1 := a1.hp
	var hp2 := a2.hp
	var nips0 := g.nips
	await wait_until(func() -> bool: return g.nips > nips0, 150)
	await frames(2)
	var hurt := int(a1.hp < hp1 - 0.5) + int(a2.hp < hp2 - 0.5)
	eq(hurt, 1, "one victim a nip (two bodies inside)")
	for a in [h, a1, a2]:
		a.free()


func _check_relocation() -> void:
	var gw := _gator_world()
	var g: Gator = gw[1]
	await frames(2)
	var rest0 := g.rest_spot()
	g._relocate_at = GameWorld.time
	var moving := await wait_until(func() -> bool: return g.state == Gator.MOVE, 10)
	check(moving, "time to relocate, nobody near: it moves off")
	var left_region := false
	var arrived := false
	for i in 60 * 45:
		if not g.in_region(Hex.from_world(g.global_position)):
			left_region = true
		if g.state != Gator.MOVE:
			arrived = true
			break
		await get_tree().physics_frame
	check(arrived, "it reaches another spot")
	check(not left_region, "and never leaves its region on the way")
	check(g.rest_spot().distance_to(rest0) > 1.0, "its spot moved (%s -> %s)" % [rest0, g.rest_spot()])
	# with somebody close it stays put
	var h := add_hero(Vector2i.ZERO)
	_stand(h, _cell_at(g.global_position, 5.0))
	g._relocate_at = GameWorld.time
	await frames(20)
	check(g.state != Gator.MOVE, "with someone within 6 it does not relocate")
	h.free()


func _check_shoves() -> void:
	var gw := _gator_world()
	var g: Gator = gw[1]
	var L: Dictionary = gw[0]
	await frames(2)
	var h := add_hero(Vector2i.ZERO)
	_stand(h, _cell_at(g.global_position, 9.0))
	# inside its region: it slides like any body and settles where it lands, riled
	var p0 := g.global_position
	g.shove(Vector3(g.facing.z, 0.0, -g.facing.x), 1.6, h)
	check(g.is_shoved(), "a shove moves the gator")
	var done := await wait_until(func() -> bool: return not g.is_shoved(), 60)
	check(done, "the shove ends")
	await frames(2)
	check(GameWorld.flat_distance(p0, g.global_position) > 0.8, "it slid (%.2f)" % GameWorld.flat_distance(p0, g.global_position))
	check(g.is_riled(), "a shove riles it")
	near(g.territory(), Gator.TERRITORY_RILED, 0.01, "riled, its territory is %.1f" % Gator.TERRITORY_RILED)
	check(g.rest_spot().distance_to(Vector2(g.global_position.x, g.global_position.z)) < 0.05, "inside its region it settles where it lands")
	check(g.state != Gator.MOVE, "and stays there")
	# out of its region (a dry room): it walks home
	var region := g.home_cells
	var out_c := Vector2i(1 << 20, 0)
	var e0: Vector2i = (L["decks"] as Array)[6]   # L1's dry way-on room, far from the water
	for c in Hex.range_cells(e0, 2):
		if GameWorld.map.is_walkable_cell(c) and not region.has(c):
			out_c = c
			break
	check(out_c.x < 1 << 19, "a dry cell outside its region")
	_stand(g, out_c)
	g.shove(Vector3.RIGHT, 0.3, h)
	await wait_until(func() -> bool: return not g.is_shoved(), 60)
	await frames(2)
	eq(g.state, Gator.MOVE, "shoved out of its region it walks home")
	var home := await wait_until(func() -> bool: return g.state != Gator.MOVE and g.in_region(Hex.from_world(g.global_position)), 60 * 60)
	check(home, "and gets back into its region (state %s)" % g.state_name())
	h.free()


func _check_stuck() -> void:
	# a dry plateau 5 levels up beside a pool: no way down for a gator (it can't climb or drop 5)
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 7):
		m.set_cell(c, 0).tag = "room:0"
	for c in Hex.range_cells(Vector2i(-3, 0), 1):
		var cell := m.get_cell(c)
		cell.level = -1
		cell.pool_level = -1
		cell.pool_mask = HexMap.ALL_KITES
	for c in Hex.range_cells(Vector2i(4, 0), 1):
		m.get_cell(c).level = 5
	new_world(m)
	var region := Gator.region_of(m)
	var spots: Array[Vector2] = [Vector2(Hex.to_world(Vector2i(-3, 0)).x, Hex.to_world(Vector2i(-3, 0)).z)]
	var g := Gator.spawn(spots[0], Vector2.RIGHT, region, spots, 7)
	g._relocate_at = INF
	await frames(2)
	var top := Hex.to_world(Vector2i(4, 0), 5.0)
	g.global_position = top
	g.shove(Vector3.RIGHT, 0.2, null)
	await wait_until(func() -> bool: return not g.is_shoved(), 60)
	await frames(2)
	check(g.state != Gator.MOVE, "no way home: it settles where it is (state %s)" % g.state_name())
	var p := g.global_position
	g._relocate_at = GameWorld.time
	await frames(240)
	check(GameWorld.flat_distance(p, g.global_position) < 0.6, "it tries again at the relocation, finds no way, and never teleports")
	check(g.state != Gator.MOVE, "... and is not stuck walking")


## A long run on layout 1: relocations every few seconds, a hero wandering through: it is never stuck in MOVE for long.
func _check_long_run() -> void:
	var gw := _gator_world()
	var g: Gator = gw[1]
	await frames(2)
	var move_t := 0.0
	var longest := 0.0
	var moves := 0
	var was_move := false
	for i in 60 * 60:
		if i % (60 * 5) == 0 and g.state == Gator.CALM:
			g._relocate_at = GameWorld.time
		if g.state == Gator.MOVE:
			move_t += 1.0 / 60.0
			longest = maxf(longest, move_t)
			if not was_move:
				moves += 1
			was_move = true
		else:
			move_t = 0.0
			was_move = false
		await get_tree().physics_frame
	check(moves >= 3, "it relocated again and again (%d moves in 60 s)" % moves)
	check(longest < 25.0, "it is never stuck walking (the longest move took %.1f s)" % longest)
	check(g.in_region(Hex.from_world(g.global_position)), "it ends in its region")


func _check_chum() -> void:
	var gw := _gator_world()
	var g: Gator = gw[1]
	await frames(2)
	var fwd := Vector3(g.facing.x, 0.0, g.facing.z)
	Gator.corn_at(g.global_position + fwd * 2.0)
	await frames(2)
	eq(g.state, Gator.CHUM, "corn in its water within 6: chum")
	var h := add_hero(Vector2i.ZERO)
	_stand(h, _cell_at(g.head(), 1.9, fwd))
	var hp0 := h.hp
	await frames(int(Gator.CHUM_T * 60.0) - 30)
	near(h.hp, hp0, 0.01, "no nips while it noses the kernels")
	var later := await wait_until(func() -> bool: return h.hp < hp0 - 0.5, 150)
	check(later, "after the chum it nips again")
	h.free()


func _check_bill() -> void:
	var gw := _gator_world()
	var g: Gator = gw[1]
	Ledger.begin_contract(1000000)
	var h := add_hero(Vector2i.ZERO)
	h.display_name = "Wick"
	_stand(h, _cell_at(g.global_position, 9.0))
	await frames(2)
	g.apply_damage(60.0, h)
	eq(Ledger.lines.size(), 0, "a hit that does not kill it is free")
	check(g.is_riled(), "and riles it")
	g.apply_damage(200.0, h)
	check(g.dead, "it can be killed (HP %d)" % int(Gator.HP))
	eq(Ledger.lines.size(), 1, "the kill bills once")
	if Ledger.lines.size() == 1:
		var line: Dictionary = Ledger.lines[0]
		eq(int(line["amount"]), 6300, "its full price")
		eq(str(line["label"]), "Gator", "worded like a prop")
		eq(str(line["who"]), "Wick", "billed to the killer")
	g.apply_damage(50.0, h)
	eq(Ledger.lines.size(), 1, "nothing more after the kill")
	h.free()


func _check_pit() -> void:
	# a pool beside a pit (missing cells): shoved in, it falls and dies; the shover pays
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 6):
		m.set_cell(c, 0).tag = "room:0"
	for c in Hex.range_cells(Vector2i(-1, 0), 1):
		var cell := m.get_cell(c)
		cell.level = -1
		cell.pool_level = -1
		cell.pool_mask = HexMap.ALL_KITES
	for c in Hex.range_cells(Vector2i(3, 0), 1):
		m.cells.erase(c)
	new_world(m)
	Ledger.begin_contract(1000000)
	var spots: Array[Vector2] = [Vector2(Hex.to_world(Vector2i(-1, 0)).x, Hex.to_world(Vector2i(-1, 0)).z)]
	var g := Gator.spawn(spots[0], Vector2.LEFT, Gator.region_of(m), spots, 9)
	g._relocate_at = INF
	var h := add_hero(Vector2i(-5, 0))
	h.display_name = "Rebar"
	await frames(2)
	g.global_position = Hex.to_world(Vector2i(1, 0))
	g.snap_to_ground()
	g.shove(Vector3.RIGHT, 4.0, h)
	var gone := await wait_until(func() -> bool: return not is_instance_valid(g) or g.dead, 240)
	check(gone, "shoved into a pit it falls and dies")
	eq(Ledger.lines.size(), 1, "the kill bills once")
	if Ledger.lines.size() == 1:
		eq(str(Ledger.lines[0]["who"]), "Rebar", "to whoever shoved it")
		eq(int(Ledger.lines[0]["amount"]), 6300, "its full price")
	h.free()


# --- the live wire ------------------------------------------------------------------------------------------------------

func _check_live_wire() -> void:
	var L := SewerLayouts.build(L1)
	var m: HexMap = L["map"]
	new_world(m)
	Ledger.begin_contract(1000000)
	var pe: Dictionary = {}
	for e: Dictionary in L["props"]:
		if str(e["kind"]) == "electrical_panel":
			pe = e
	check(not pe.is_empty(), "layout 1 has an electrical panel")
	var panel := PricedProp.spawn(ThemeGeo.cell_of(pe["pos"]), "electrical_panel", {"pos": pe["pos"], "yaw": pe["yaw"]})
	eq(panel.price, 250, "the panel is $250")
	var drop := LiveWire.drop_point_for(m, pe["pos"], panel.facing_vector())
	var w := LiveWire.attach(panel, drop)
	var dc := w.drop_cell
	# a wader 3 cells from the drop, one 7 cells away, a body on dry floor 2 cells away, a skeleton wading 2 cells away
	var near_c := _ring_cell(m, dc, [3, 4], 0)
	var far_c := _ring_cell(m, dc, [7, 8], 0)
	var dry_c := _ring_cell(m, dc, [2, 3, 4], 1)
	var sk_c := _ring_cell(m, dc, [1, 2], 0)
	for c: Vector2i in [near_c, far_c, dry_c, sk_c]:
		check(c.x < 1 << 19, "a test spot round the drop (%s)" % c)
	var wader := add_hero(near_c)
	var far := add_hero(far_c)
	var dry := add_hero(dry_c)
	var sk := MonsterFactory.spawn("grunt", sk_c)
	sk.aggro_range = 0.0
	var breaker := add_hero(m.cells_with_tag("exit")[0])
	breaker.display_name = "Wick"
	for a: Actor in [wader, far, dry, breaker]:
		a.snap_to_ground()
	await frames(10)
	check(m.water_at(wader.global_position) and m.water_at(far.global_position) and not m.water_at(dry.global_position), "the waders wade, the dry one is dry")
	check(Burning.is_soaked(wader), "a wader is soaked (Wading)")
	var hp := {wader: wader.hp, far: far.hp, dry: dry.hp, sk: sk.hp}
	panel.apply_damage(1.0, breaker)
	check(panel.dead, "any hit breaks the panel (HP 1)")
	eq(Ledger.lines.size(), 1, "the panel is billed")
	if Ledger.lines.size() >= 1:
		eq(str(Ledger.lines[0]["label"]), "Electrical panel", "as the electrical panel")
		eq(int(Ledger.lines[0]["amount"]), 250, "$250")
		eq(str(Ledger.lines[0]["who"]), "Wick", "to whoever broke it")
	await frames(int(LiveWire.DROP_T * 60.0) - 6)
	near(wader.hp, float(hp[wader]), 0.01, "nothing until the cable lands (0.6 s)")
	await frames(10)
	eq(w.shocks, 1, "the cable lands: the shock")
	near(float(hp[wader]) - wader.hp, LiveWire.SHOCK_DAMAGE * LiveWire.SOAKED_MULT, 0.01, "a soaked wader within 5 cells takes 18")
	check(wader.is_dazed(), "and is dazed")
	near(float(hp[sk]) - sk.hp, LiveWire.SHOCK_DAMAGE * LiveWire.SOAKED_MULT, 0.01, "both sides: the skeleton wading takes it too")
	sk.free()   # (shocked by Wick's wire, it would go for him and swing at the wader on the way)
	near(far.hp, float(hp[far]), 0.01, "a wader 7 cells from the drop is untouched (distance based, N = 5)")
	near(dry.hp, float(hp[dry]), 0.01, "dry floor beside it is safe")
	await frames(int((LiveWire.PULSE_FOR + 0.5) * 60.0))
	eq(w.shocks, 1 + int(LiveWire.PULSE_FOR / LiveWire.PULSE_EVERY), "then it pulses every 1.5 s for 6 s")
	near(float(hp[wader]) - wader.hp, (LiveWire.SHOCK_DAMAGE + LiveWire.PULSE_DAMAGE * 4.0) * LiveWire.SOAKED_MULT, 0.01, "18 and four pulses of 9")
	near(far.hp, float(hp[far]), 0.01, "the far wader is never touched")
	var after := wader.hp
	await frames(180)
	near(wader.hp, after, 0.01, "then the breaker trips: one use")
	eq(Ledger.lines.size(), 1, "the shock bills nothing more")


## A walkable cell at one of the distances `ds` from c: wet (kind 0: a basin cell) or dry (1: no pool kites). (1 << 20, 0)
## when none.
func _ring_cell(m: HexMap, c: Vector2i, ds: Array, kind: int) -> Vector2i:
	for d: int in ds:
		for r in Hex.ring(c, d):
			if not m.is_walkable_cell(r):
				continue
			var cell := m.get_cell(r)
			if kind == 0 and cell.pool_mask == HexMap.ALL_KITES or kind == 1 and cell.pool_mask == 0:
				return r
	return Vector2i(1 << 20, 0)


## Up to `n` walkable cells whose centres are `lo`..`hi` from p, nearest first.
func _cells_within(p: Vector3, lo: float, hi: float, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cands: Array[Vector2i] = []
	for c in Hex.range_cells(Hex.from_world(p), 3):
		var d := GameWorld.flat_distance(Hex.to_world(c), p)
		if GameWorld.map.is_walkable_cell(c) and d >= lo and d <= hi:
			cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return GameWorld.flat_distance(Hex.to_world(a), p) < GameWorld.flat_distance(Hex.to_world(b), p))
	for c in cands:
		if out.size() < n:
			out.append(c)
	return out

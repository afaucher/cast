extends MonsterTestBase
## Hallway LANDINGS and their SET PIECES (docs/design/hallways.md; DungeonGen's landings pass, PropPlanner.plan_set_pieces):
##   1. how many a hall gets (DungeonGen.landing_count): none up to LANDING_MIN_LEN, then one per LANDING_EVERY
##   2. on the golden floors (ten contract seeds x floors 1-3, built as the game builds them): a landing is only on a hall
##      long enough for one, never on the service stair, the chokepoint or a sewer cluster's / lava cave's halls; its
##      hexagon is flat floor at one level with no stairs near, tagged "corridor", its full cells full, its new cells clear of
##      every room; almost every long hall gets one and a floor gets a few; exactly one set piece per landing, a site
##      landmark, wholly on the landing's own new cells (the hall's width stays clear), off the wall side, facing into the
##      landing; nothing else (no explosive, decor, note, mail, gate, employee) on a landing
##   3. deterministic from the seed (the map text and the set pieces twice alike)
##   4. the switch off: no landings and no set pieces, and every room, prop, explosive, decor piece, note, mail spot, gate,
##      employee, the start, the exit and the elevator exactly as with it on; a crew's floor (for_run's `shared`) has them
##      whatever the switch says
##   5. spawned: the set pieces are ordinary PricedProps, the last actors (no earlier net id moves), in Site.props, standing
##      where planned; the floor checksum's map text names the landings

const SEEDS := 10
const FLOORS := 3


func setup() -> void:
	timeout_sec = 300.0
	Monster.use_proto_visuals = true
	var keep := DungeonGen.landings
	DungeonGen.landings = true
	_check_counts()
	_check_floors()
	_check_deterministic()
	_check_switch()
	_check_spawn()
	DungeonGen.landings = keep
	Monster.use_proto_visuals = false
	finish()


# --- 1 -------------------------------------------------------------------------------------------------------------

func _check_counts() -> void:
	eq(DungeonGen.landing_count(12.0), 0, "a short hall gets no landing")
	eq(DungeonGen.landing_count(DungeonGen.LANDING_MIN_LEN), 0, "nor one exactly LANDING_MIN_LEN long")
	eq(DungeonGen.landing_count(DungeonGen.LANDING_MIN_LEN + 0.5), 1, "a longer one gets one")
	eq(DungeonGen.landing_count(DungeonGen.LANDING_MIN_LEN + DungeonGen.LANDING_EVERY + 0.5), 2, "and one more every LANDING_EVERY")
	eq(DungeonGen.landing_count(88.0), 3, "the old 88-unit outlier would get three")


# --- 2 -------------------------------------------------------------------------------------------------------------

func _check_floors() -> void:
	var total := 0
	var pieces := 0
	var floors := 0
	var long_eligible := 0
	var long_with := 0
	var turns := 0
	for s in range(1, SEEDS + 1):
		var run := ContractBoard.run_for_seed(s)
		for f in range(1, FLOORS + 1):
			var map := DungeonGen.for_run(run, f)
			var halls: Array[Dictionary] = DungeonGen.last_halls.duplicate()
			var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			var tag := "seed %d floor %d" % [s, f]
			floors += 1
			total += map.landings.size()
			pieces += plan.set_pieces.size()
			for lr in map.landings:
				if bool(lr["turn"]):
					turns += 1
			for h in halls:
				var eligible := not bool(h["stair"]) and not bool(h["special"]) and not (bool(h["narrow"]) and not bool(h["loop"]) and not bool(h["shortcut"]))
				if eligible and DungeonGen.landing_count(float(h["path"])) > 0:
					long_eligible += 1
					if int(h["landings"]) > 0:
						long_with += 1
				if int(h["landings"]) > 0:
					check(eligible, "%s: hall %d-%d has landings only if it may (not the stair, the chokepoint, a cluster's or cave's)" % [tag, h["a"], h["b"]])
					check(int(h["landings"]) <= DungeonGen.landing_count(float(h["path"])), "%s: hall %d-%d (%.1f long) has no more landings than its length asks" % [tag, h["a"], h["b"], h["path"]])
			_check_landings(map, plan, halls, run, tag)
	print("[landings] %d floors: %d landings (%.2f a floor, %d at a turn), %d set pieces; long halls with one: %d of %d" % [floors, total,
			float(total) / floors, turns, pieces, long_with, long_eligible])
	var mean := float(total) / floors
	check(mean >= 2.5 and mean <= 5.5, "a floor gets a few landings (%.2f a floor)" % mean)
	# (not every one: a short-ish hall with a big climb has no room for a flat landing and its steps clear of both doors)
	check(long_with >= int(0.8 * long_eligible), "most long halls get a landing (%d of %d)" % [long_with, long_eligible])
	eq(pieces, total, "a set piece on every landing")


func _check_landings(map: HexMap, plan: SitePlan, halls: Array[Dictionary], run: ContractRun, tag: String) -> void:
	var kinds: Array = PropPlanner.LANDING_KINDS.get(run.site_type, [])
	var piece_of := {}
	for sp in plan.set_pieces:
		var li := int(sp["landing"])
		check(not piece_of.has(li), "%s: one set piece on landing %d" % [tag, li])
		piece_of[li] = sp
	var others := {}   # every cell something of the rooms' planners stands on
	for list: Array in [plan.hazards, plan.decor, plan.notes, plan.packages, plan.gates, plan.employees, plan.props]:
		for e: Dictionary in list:
			others[e["cell"]] = true
	for pr in plan.props:
		check(str(pr["room"]).begins_with("room:"), "%s: the rooms' priced props stay in rooms (%s)" % [tag, pr["cell"]])
	for li in map.landings.size():
		var lr: Dictionary = map.landings[li]
		var hub: Vector2i = lr["hub"]
		var lv := int(lr["level"])
		var lt := "%s landing %d at %s" % [tag, li, lr["center"]]
		check(Hex.distance(hub, lr["center"]) <= 1, "%s: its hexagon is round its centre or a neighbour" % lt)
		# its hall
		var row := {}
		for h in halls:
			if "room:%d" % int(h["a"]) == str(lr["hall"][0]) and "room:%d" % int(h["b"]) == str(lr["hall"][1]):
				row = h
		if check(not row.is_empty(), "%s: on a hall of the floor" % lt):
			check(float(row["path"]) > DungeonGen.LANDING_MIN_LEN, "%s: on a long hall (%.1f)" % [lt, row["path"]])
			check(not bool(row["stair"]) and not bool(row["special"]), "%s: not the service stair, nor a cluster's or a cave's hall" % lt)
			check(not (bool(row["narrow"]) and not bool(row["loop"]) and not bool(row["shortcut"])), "%s: not the chokepoint" % lt)
		# flat, one level, a corridor, full in the middle
		var flat := true
		var full := true
		for c in Hex.range_cells(hub, DungeonGen.LANDING_R + 1):
			var cell := map.get_cell(c)
			if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != lv or cell.tag != "corridor":
				flat = false
			elif Hex.distance(c, hub) <= DungeonGen.LANDING_R and not map.is_walkable_cell(c):
				full = false
		check(flat, "%s: its hexagon is flat hall floor at level %d" % [lt, lv])
		check(full, "%s: its middle is full floor" % lt)
		for c in Hex.range_cells(hub, DungeonGen.LANDING_R + 2):
			var cell := map.get_cell(c)
			check(cell == null or cell.type != HexMap.Tile.STAIRS, "%s: no stairs at its edge (%s)" % [lt, c])
		# its new cells keep clear of the rooms (the elevator's notch, cut into its room's wall after the halls, aside: it keeps
		# its own two cells from anything else)
		var added := {}
		var notch: Array = map.elevator.get("cells", []) if str(map.elevator.get("place", "")) == ElevatorGeo.PLACE_WALL else []
		for c: Vector2i in (lr["cells"] as Array):
			added[c] = true
			check(Hex.distance(c, hub) <= DungeonGen.LANDING_R + 1, "%s: its cells are its hexagon's" % lt)
			for y in Hex.range_cells(c, DungeonGen.LANDING_ROOM_CLEAR - 1):
				var yc := map.get_cell(y)
				if yc != null and (yc.tag.begins_with("room:") or yc.tag == "start" or yc.tag == "exit") and not notch.has(y):
					check(false, "%s: cell %s keeps %d from the rooms (room cell %s)" % [lt, c, DungeonGen.LANDING_ROOM_CLEAR, y])
					break
		check(not added.is_empty(), "%s: it widens the hall" % lt)
		# nothing of the rooms' planners on it
		for c in Hex.range_cells(hub, DungeonGen.LANDING_R + 1):
			check(not others.has(c), "%s: nothing but its set piece stands on it (%s)" % [lt, c])
		# its set piece
		if not check(piece_of.has(li), "%s: has a set piece" % lt):
			continue
		var sp: Dictionary = piece_of[li]
		check(kinds.has(str(sp["kind"])), "%s: the set piece is a %s landmark (%s)" % [lt, run.site_type, sp["kind"]])
		check(PricedProp.catalog(run.site_type).has(str(sp["kind"])) and not PricedProp.is_hazard(str(sp["kind"])), "%s: of the site's catalog, no explosive" % lt)
		eq(str(sp["room"]), "", "%s: a set piece is in no room" % lt)
		var pos: Vector2 = sp["pos"]
		var yaw := float(sp["yaw"])
		var foot: Vector2 = sp["foot"]
		var lane_clear := true
		var off_wall := true
		for fp in ThemeGeo.foot_points(pos, yaw, foot.x, foot.y):
			if not added.has(ThemeGeo.cell_of(fp)):
				lane_clear = false
			if map.wall_at(Vector3(fp.x, 0.0, fp.y)):
				off_wall = false
		check(lane_clear, "%s: the %s stands wholly on the landing's own cells (the hall's width stays clear)" % [lt, sp["kind"]])
		check(off_wall, "%s: the %s is off the wall side" % [lt, sp["kind"]])
		var into := ThemeGeo.world(hub) - pos
		check(ThemeGeo.facing(yaw).dot(into.normalized()) > 0.5, "%s: the %s faces into the landing" % [lt, sp["kind"]])
		check(into.length() >= 2.0, "%s: the %s stands at the back, not in the middle (%.2f from it)" % [lt, sp["kind"], into.length()])


# --- 3 -------------------------------------------------------------------------------------------------------------

func _check_deterministic() -> void:
	var run := ContractBoard.run_for_seed(3)
	var a := DungeonGen.for_run(run, 1)
	var pa := SiteBuilder.plan(a, run, 1, PricedProp.catalog(run.site_type))
	var b := DungeonGen.for_run(run, 1)
	var pb := SiteBuilder.plan(b, run, 1, PricedProp.catalog(run.site_type))
	check(not a.landings.is_empty(), "seed 3 floor 1 has landings")
	eq(NetFloor.map_text_of(a), NetFloor.map_text_of(b), "the same floor twice (landings and all)")
	eq(str(pa.set_pieces), str(pb.set_pieces), "the same set pieces twice")


# --- 4 -------------------------------------------------------------------------------------------------------------

func _check_switch() -> void:
	var compared := 0
	for s in range(1, SEEDS + 1):
		var run := ContractBoard.run_for_seed(s)
		for f in range(1, FLOORS + 1):
			DungeonGen.landings = true
			var on := DungeonGen.for_run(run, f)
			var pon := SiteBuilder.plan(on, run, f, PricedProp.catalog(run.site_type))
			DungeonGen.landings = false
			var off := DungeonGen.for_run(run, f)
			var poff := SiteBuilder.plan(off, run, f, PricedProp.catalog(run.site_type))
			var shared := DungeonGen.for_run(run, f, true)
			DungeonGen.landings = true
			var tag := "seed %d floor %d" % [s, f]
			check(off.landings.is_empty() and poff.set_pieces.is_empty(), "%s: the switch off: no landings, no set pieces" % tag)
			eq(shared.landings.size(), on.landings.size(), "%s: a crew's floor has its landings whatever the switch says" % tag)
			if on.landings.is_empty():
				continue
			compared += 1
			# every room cell as it was
			# (an office door's tread-plate threshold writes its cells' floor: a hall's terraces and stairs keep off its landings, so
			# a narrow hall's door may move; the room's own floor stays)
			var thresholds := {}
			for dr: Dictionary in pon.doors + poff.doors:
				if dr.has("cell"):
					for c in Hex.range_cells(dr["cell"], 2):
						thresholds[c] = true
			var differ := ""
			for c: Vector2i in off.cells:
				var oc: HexMap.Cell = off.cells[c]
				if not (oc.tag.begins_with("room:") or oc.tag == "start" or oc.tag == "exit"):
					continue
				var nc := on.get_cell(c)
				if nc == null or nc.tag != oc.tag or nc.level != oc.level or nc.type != oc.type or nc.wall_mask != oc.wall_mask \
						or (nc.mat_id != oc.mat_id and not thresholds.has(c)):
					differ = "%s: off %s/%d/%d/%d/%d, on %s" % [c, oc.tag, oc.level, oc.type, oc.wall_mask, oc.mat_id,
							"-" if nc == null else "%s/%d/%d/%d/%d" % [nc.tag, nc.level, nc.type, nc.wall_mask, nc.mat_id]]
			for c: Vector2i in on.cells:
				var nc2: HexMap.Cell = on.cells[c]
				if nc2.tag.begins_with("room:") and (off.get_cell(c) == null or off.get_cell(c).tag != nc2.tag):
					differ = "%s: on %s, off %s" % [c, nc2.tag, "-" if off.get_cell(c) == null else off.get_cell(c).tag]
			check(differ == "", "%s: every room cell is as without landings (%s)" % [tag, differ])
			# the new floor cells are the landings'
			var lands := {}
			for lr in on.landings:
				for c in Hex.range_cells(lr["hub"], DungeonGen.LANDING_R + 1):
					lands[c] = true
			var stray := 0
			for c: Vector2i in on.cells:
				if on.cells[c].type != HexMap.Tile.WALL and not off.cells.has(c) and not lands.has(c):
					stray += 1
			eq(stray, 0, "%s: every new floor cell is a landing's" % tag)
			eq(str(on.elevator), str(off.elevator), "%s: the elevator as it was" % tag)
			for fld in ["start", "exit", "rooms", "room_themes", "gates", "employees", "props", "hazards", "decor", "notes", "packages",
					"van", "pack_budgets"]:
				eq(str(pon.get(fld)), str(poff.get(fld)), "%s: the plan's %s as without landings" % [tag, fld])
	check(compared >= 20, "compared on and off on %d floors" % compared)


# --- 5 -------------------------------------------------------------------------------------------------------------

func _check_spawn() -> void:
	var run := ContractBoard.run_for_seed(3)
	var map := DungeonGen.for_run(run, 1)
	new_world(map)
	GameWorld.begin(map, world, run.floor_seed(1))
	var plan := SiteBuilder.plan(map, run, 1, PricedProp.catalog(run.site_type))
	var site := SiteBuilder.spawn(map, run, plan)
	NetFloor.assign_ids(world, {})
	var n := plan.set_pieces.size()
	check(n > 0, "the floor has set pieces to spawn")
	var actors := NetFloor.actors_under(world)
	check(actors.size() >= n, "every actor is there")
	for i in n:
		var sp: Dictionary = plan.set_pieces[i]
		var a := actors[actors.size() - n + i] as PricedProp
		if not check(a != null, "set piece %d is a priced prop, among the last actors" % i):
			continue
		eq(a.kind, str(sp["kind"]), "set piece %d: the planned kind" % i)
		check(not (a is ExplosiveProp), "set piece %d: no explosive" % i)
		var pos: Vector2 = sp["pos"]
		check(Vector2(a.global_position.x, a.global_position.z).distance_to(pos) < 0.05, "set piece %d stands where planned" % i)
		near(a.global_position.y, float(map.landings[int(sp["landing"])]["level"]) * Hex.LEVEL_HEIGHT, 0.05, "set piece %d stands on the landing's floor" % i)
		check(site.props.has(a), "set piece %d is in Site.props" % i)
		check(NetFloor.id_of(a) >= NetFloor.ID_BASE, "set piece %d has a net id" % i)
	check(NetFloor.map_text_of(map).contains("landings="), "the floor checksum's map text has the landings")
	world.free()
	world = null

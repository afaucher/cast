extends MonsterTestBase
## The sewer in the generator (docs/design/sewer-concept.md, "Phase 3 as built"): over many contract seeds and floors, every
## sewer cluster DungeonGen cuts and SewerPlanner floods holds the rules:
##   - 2-4 rooms, on floors 2-3 only, all at one base level, none of them the start or the elevator's room;
##   - one service stair down into it: a hall of STAIRS cells whose doorway in the cluster stays dry;
##   - its water is ONE connected body (one HexMap.pools record with "body"), every flooded hall joins two rooms' water, every
##     room's water stays under SewerPlanner.WATER_CAP of its floor;
##   - every doorway of the floor is reachable from the start (wading where it must);
##   - the gator starts in the water inside its home region, its bask spots are in the region; the panel drops its cable into
##     the water; flooded narrow doorways get a sluice, never an office door;
##   - a SHARED run gets the same cluster (SewerCluster.NETWORKED, sewer phase 2): the same map text, the record in it;
##   - a floor without a cluster is byte for byte the floor it always was (the NetFloor map and plan texts);
##   - the timing: generation and the sewer's planning stay cheap.
## It also prints the share of floors 2-3 with a cluster and the first seeds with one on floor 2 (for the doc and playtests).

const SEEDS := 40               ## contract seeds for floors 2-3
const FLOOR1_SEEDS := 8         ## ... and floor 1 (never a cluster)


var _probe: Node = null   ## an empty spawn root for the checksums
var packs := 0            ## clusters with a goo imp pack


func setup() -> void:
	timeout_sec = 600.0
	Monster.use_proto_visuals = true
	var clusters := 0
	var eligible := 0
	var natural: Array[int] = []
	var worst_gen := 0.0
	var worst_sewer := 0
	var panels := 0
	var sizes := {}
	var narrow := 0
	var loops := 0
	packs = 0
	_probe = Node.new()
	for s in range(1, SEEDS + 1):
		var run := ContractBoard.run_for_seed(s)
		for f in range(1 if s <= FLOOR1_SEEDS else 2, 4):
			var t0 := Time.get_ticks_usec()
			var map := DungeonGen.for_run(run, f)
			var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
			var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			if f >= 2:
				eligible += 1
			if map.sewer.is_empty():
				_check_unchanged(run, f, map, plan)
				continue
			clusters += 1
			for e in plan.props:
				if str(e["kind"]) == "electrical_panel":
					panels += 1
			sizes[(map.sewer["rooms"] as Array).size()] = int(sizes.get((map.sewer["rooms"] as Array).size(), 0)) + 1
			for h: Dictionary in map.sewer["halls"]:
				narrow += 1 if bool(h["narrow"]) else 0
				loops += 1 if bool(h["loop"]) else 0
			worst_gen = maxf(worst_gen, gen_ms)
			worst_sewer = maxi(worst_sewer, SewerPlanner.last_usec + GatorPlanner.last_usec)
			if f == 2 and natural.size() < 5:
				natural.append(s)
			_check_cluster(run, f, map, plan, "seed %d floor %d" % [s, f])
			if clusters <= 3:
				_check_spawned(run, f, "seed %d floor %d" % [s, f])
			_check_shared(run, f, "seed %d floor %d" % [s, f])
	print("[sewer gen] %d of %d floors 2-3 have a cluster (%.0f%%), %d with a panel; natural floor-2 seeds: %s; worst gen %.0f ms, worst sewer plan %.1f ms" % [
		clusters, eligible, 100.0 * clusters / maxf(1.0, eligible), panels, str(natural), worst_gen, worst_sewer / 1000.0])
	print("[sewer gen] cluster sizes %s; %d flooded narrow halls, %d loops inside a cluster; %d goo imp packs" % [str(sizes), narrow, loops, packs])
	check(packs * 4 >= clusters * 3, "most clusters have a goo imp pack (%d of %d)" % [packs, clusters])
	check(panels * 3 >= clusters * 2, "most clusters have an electrical panel (%d of %d)" % [panels, clusters])
	check(clusters >= eligible / 5, "some floors 2-3 get a cluster (%d of %d)" % [clusters, eligible])
	check(worst_gen < 400.0, "a sewer floor generates in time (worst %.0f ms)" % worst_gen)
	check(worst_sewer < 30000, "the sewer's planning stays cheap (worst %.1f ms)" % (worst_sewer / 1000.0))
	_check_force()
	Monster.use_proto_visuals = false
	_probe.free()
	finish()


## The cluster's rules on one planned floor.
func _check_cluster(run: ContractRun, f: int, map: HexMap, plan: SitePlan, tag: String) -> void:
	var rec: Dictionary = map.sewer
	check(f >= 2 and SewerCluster.SITES.has(run.site_type), "%s: a cluster only on floors 2-3 of a bunker or lair" % tag)
	var rooms: Array = rec["rooms"]
	check(rooms.size() >= SewerCluster.MIN_ROOMS and rooms.size() <= SewerCluster.MAX_ROOMS, "%s: 2-4 rooms (%d)" % [tag, rooms.size()])
	check(not rooms.has(plan.start_room) and not rooms.has(plan.exit_room), "%s: never the start or the elevator's room" % tag)
	var level := int(rec["level"])
	for t: String in rooms:
		eq(int(plan.base_levels[t]), level, "%s: %s stands at the cluster's level" % [tag, t])
		eq(plan.theme_of(t), SewerPlanner.THEME, "%s: %s is a sewer room" % [tag, t])
	# the service stair
	var st: Dictionary = rec["stair"]
	var door: Vector2i = st["door"]
	check(map.is_walkable_cell(door) and not map.is_pool_cell(door), "%s: the stair's doorway in the cluster is dry floor" % tag)
	var stairs := 0
	for c: Vector2i in (st["cells"] as Array):
		if map.get_cell(c).type == HexMap.Tile.STAIRS:
			stairs += 1
	check(stairs >= 1, "%s: the service stair has steps (%d STAIRS cells)" % [tag, stairs])
	var up := int(plan.base_levels[str(st["from"])])
	check(up - level >= SewerCluster.DROP_MIN, "%s: the stair goes down %d levels" % [tag, up - level])
	# one body
	var bodies := map.pools.filter(func(r: Dictionary) -> bool: return bool(r.get("body", false)))
	eq(bodies.size(), 1, "%s: one body record" % tag)
	if bodies.is_empty():
		return
	var body: Dictionary = bodies[0]
	var wet := {}
	for c: Vector2i in (body["basin"] as Array):
		wet[c] = true
	check(wet.size() >= 20, "%s: it has water (%d wet cells)" % [tag, wet.size()])
	eq(SewerLayouts.components(wet), 1, "%s: all its water is one connected body" % tag)
	# every flooded hall joins two rooms' water
	for h: Dictionary in rec["halls"]:
		var hall := {}
		for c: Vector2i in (h["cells"] as Array):
			if wet.has(c):
				hall[c] = true
		check(hall.size() >= 2, "%s: the hall %s-%s is flooded" % [tag, h["a"], h["b"]])
		var joined := {}
		for c: Vector2i in hall:
			for d in Hex.DIRS:
				var nb: Vector2i = c + d
				if wet.has(nb) and not hall.has(nb) and rooms.has(map.get_cell(nb).tag):
					joined[map.get_cell(nb).tag] = true
		check(joined.size() >= 2, "%s: the hall %s-%s's water joins both rooms' (%s)" % [tag, h["a"], h["b"], str(joined.keys())])
		if not bool(h["narrow"]):
			var ledge := 0
			for c: Vector2i in (h["lanes"] as Array):
				if map.is_walkable_cell(c) and not wet.has(c):
					ledge += 1
			check(ledge >= 1, "%s: the wide hall %s-%s keeps a dry ledge (%d cells)" % [tag, h["a"], h["b"], ledge])
	# the water cap, in kites
	for t: String in rooms:
		var kites := 0
		var water := 0
		for c: Vector2i in (plan.rooms[t] as Array):
			var cell: HexMap.Cell = map.cells[c]
			for k in 6:
				if (cell.wall_mask >> k) & 1 == 1:
					continue
				kites += 1
				if (cell.pool_mask >> k) & 1 == 1:
					water += 1
		var share := float(water) / maxf(1.0, kites)
		check(share <= SewerPlanner.WATER_CAP + 0.05, "%s: %s's water is %.0f%% of its floor" % [tag, t, share * 100.0])
		check(share > 0.05, "%s: %s has its channel (%.0f%%)" % [tag, t, share * 100.0])
	_check_water_drawing(map, body, rec, tag)
	# every doorway reachable from the start, wading where it must
	var start: Vector2i = plan.start
	var reach := _reach(map, start)
	for d: Vector2i in (rec["all_doors"] as Array):
		check(reach.has(d), "%s: the doorway %s is reachable from the start" % [tag, d])
	for t: String in rooms:
		check(reach.has(plan.centers[t]) or reach.has(Hex.from_world(Hex.to_world(plan.centers[t]))), "%s: %s is reachable" % [tag, t])
	# nothing planned stands in the water
	for e in plan.employees + plan.notes:
		check(not map.is_pool_cell(e["cell"]), "%s: the %s at %s is on dry floor" % [tag, "note" if e.has("format") else "employee", e["cell"]])
	for g in plan.gates:
		check(not map.is_pool_cell(g["cell"]), "%s: the gate at %s is on dry floor" % [tag, g["cell"]])
	for e in plan.props + plan.hazards:
		var pp: Vector2 = e["pos"]
		check(not map.water_at(Vector3(pp.x, 0.0, pp.y)), "%s: the %s at %s stands on dry floor" % [tag, e["kind"], pp])
		if str(e["kind"]) == "electrical_panel":
			var drop := LiveWire.drop_point_for(map, pp, ThemeGeo.facing(float(e["yaw"])))
			check(drop != Vector3.INF and map.water_at(drop), "%s: the panel drops its cable into the water" % tag)
	# the gators
	var gators: Array = rec.get("gators", [])
	check(gators.size() >= 1 and gators.size() <= 2, "%s: one or two gators (%d)" % [tag, gators.size()])
	var region := GatorPlanner.region_of(map)
	for g: Dictionary in gators:
		var at: Vector2 = g["at"]
		var ac := ThemeGeo.cell_of(at)
		check(region.has(ac) and map.water_at(Vector3(at.x, 0.0, at.y)), "%s: the gator starts in its water" % tag)
		for s: Vector2 in (g["spots"] as Array):
			check(region.has(ThemeGeo.cell_of(s)), "%s: bask spot %s is in its region" % [tag, s])
	for c: Vector2i in (st["cells"] as Array):
		check(not region.has(c) or Hex.distance(c, door) <= 1, "%s: the stair is not the gator's (%s)" % [tag, c])
	# the goo imp pack: a room's dry cells by the water, clear of the stair's foot
	var pack: Dictionary = rec.get("pack", {})
	if not pack.is_empty():
		packs += 1
		check(rooms.has(pack["room"]), "%s: the goo pack is in the cluster" % tag)
		for c: Vector2i in (pack["cells"] as Array):
			check(map.is_walkable_cell(c) and not map.is_pool_cell(c) and Hex.distance(c, door) > SewerPlanner.PACK_STAIR_CLEAR, "%s: the goo pack's cell %s is dry deck" % [tag, c])
	# doors: a flooded narrow doorway is a sluice, never an office door
	for dr in plan.doors:
		var any_wet := false
		for c: Vector2i in (dr["door_cells"] as Array):
			any_wet = any_wet or wet.has(c)
		check(not any_wet, "%s: no office door stands in the water (%s)" % [tag, dr["cell"]])
	var narrow := 0
	for h: Dictionary in rec["halls"]:
		if bool(h["narrow"]):
			narrow += 1
	var sluices := plan.decor.filter(func(d: Dictionary) -> bool: return str(d["kind"]) == "sluice").size()
	check(sluices >= narrow, "%s: the flooded narrow halls have sluices (%d for %d halls)" % [tag, sluices, narrow])


## Every cell reached from `start` over walkable moves (wading is a one-level step).
func _reach(map: HexMap, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var nb: Vector2i = c + d
			if seen.has(nb) or not map.is_walkable_cell(nb):
				continue
			if map.cell_transition(c, nb) == HexMap.Move.OK:
				seen[nb] = true
				queue.append(nb)
	return seen


## A floor without a cluster is the floor the generator always built: the same map and plan as DungeonGen without the option.
func _check_unchanged(run: ContractRun, f: int, map: HexMap, plan: SitePlan) -> void:
	var ref := DungeonGen.generate(run.floor_seed(f), {"elevator": run.elevator_place})
	var ref_plan := SiteBuilder.plan(ref, run, f, PricedProp.catalog(run.site_type))
	var a := NetFloor.checksum(map, plan, run, _probe)
	var b := NetFloor.checksum(ref, ref_plan, run, _probe)
	check(str(a["map"]) == str(b["map"]) and str(a["plan"]) == str(b["plan"]), "seed %d floor %d: without a cluster the floor is unchanged" % [run.seed, f])


## The same floor in a shared run (sewer phase 2): the same cluster, so every machine of a crew builds the solo floor of the
## seed; the cluster's record is in the checksum's map text.
func _check_shared(run: ContractRun, f: int, tag: String) -> void:
	var shared := DungeonGen.for_run(run, f, true)
	var solo := DungeonGen.for_run(run, f)
	check(not shared.sewer.is_empty(), "%s: a shared run gets the cluster too" % tag)
	eq(NetFloor.map_text_of(shared), NetFloor.map_text_of(solo), "%s: the shared run's floor is the solo floor" % tag)
	check(NetFloor.map_text_of(shared).contains("\nsewer="), "%s: the cluster's record is in the map checksum" % tag)


## Spawned: the gators are in the world after the sharks, with live wires on the panels and the water drawn.
func _check_spawned(run: ContractRun, f: int, tag: String) -> void:
	var map := DungeonGen.for_run(run, f)
	new_world(map)
	GameWorld.begin(map, world, run.floor_seed(f))
	var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
	var site := SiteBuilder.spawn(map, run, plan)
	check(site.gators.size() == (map.sewer["gators"] as Array).size() and not site.gators.is_empty(), "%s: the gators are spawned" % tag)
	check(site.sewer_view != null and site.sewer_view.water != null, "%s: the water is drawn" % tag)
	var panels := plan.props.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "electrical_panel").size()
	eq(site.wires.size(), panels, "%s: a live wire on every panel" % tag)
	var actors := NetFloor.actors_under(world)
	var last_shark := -1
	var first_gator := 1 << 20
	var last_gator := -1
	var first_goo := 1 << 20
	var goo := 0
	for i in actors.size():
		if actors[i] is Shark:
			last_shark = i
		if actors[i] is Gator:
			first_gator = mini(first_gator, i)
			last_gator = i
		if actors[i] is Monster and MonsterDefs.habitat(str((actors[i] as Monster).kind)) == "sewer":
			first_goo = mini(first_goo, i)
			goo += 1
			check(not map.water_at(actors[i].global_position), "%s: a goo imp stands on dry floor" % tag)
	check(first_gator > last_shark, "%s: the gators come after the sharks in net-id order" % tag)
	if not (map.sewer.get("pack", {}) as Dictionary).is_empty():
		check(goo >= 3 and first_goo > last_gator, "%s: the goo imp pack (%d) is spawned after the gators" % [tag, goo])
	for g: Gator in site.gators:
		check(g.in_region(g.current_cell()), "%s: the gator stands in its region" % tag)


## --sewer-floor: a forced cluster on most floors, any site, a shared run alike (every window of a crew has the flag).
## The body's water as SewerView draws it (the user's playtest, 2026-10-21, "What happened to this water"): the foam runs only
## along the water's own edge (the far side of every foam strip is dry floor or a wall, never more of the body's water: a
## shared kite edge both sides of which drew foam and a kerb, when two cells' corner keys split far from the origin), every
## kerb stands on a deck over the water, none under it, and every kerb face is wound to face its normal ("z fighting on the
## water edge": strips and corner fans wound either way, lit and dark, overlapping at the rim's corners).
func _check_water_drawing(map: HexMap, body: Dictionary, rec: Dictionary, tag: String) -> void:
	var only := {}
	for c: Vector2i in (body["basin"] as Array) + (body["ring"] as Array):
		only[c] = true
	var v := SewerView.new()
	v.flows = rec["flows"]
	var surface_y := float(body["surface_y"])
	v.build_water(map, only, surface_y, int(body["floor_level"]))
	check(v.water != null and v.foam != null, "%s: the water and its foam are drawn" % tag)
	if v.foam != null:
		var arr := (v.foam.mesh as ArrayMesh).surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var inside := 0
		var first := Vector3.INF
		for q in vs.size() / 6:
			var edge := Vector3.ZERO
			var inner := Vector3.ZERO
			for i in [0, 1, 2, 5]:   # (a quad's corners: _quad's triangles 0 1 2, 0 2 3)
				if cs[q * 6 + i].a > 0.5:
					edge += vs[q * 6 + i] * 0.5
				else:
					inner += vs[q * 6 + i] * 0.5
			var probe := edge + (edge - inner).normalized() * 0.08
			if map.water_at(probe) and only.has(Hex.from_world(probe)):
				inside += 1
				if first == Vector3.INF:
					first = probe
		eq(inside, 0, "%s: no foam strip runs through the water (first at %s)" % [tag, first])
	if v.kerb != null:
		# (its top faces only: a kerb's front face runs on down into the water, to the channel floor + 0.2)
		var ka := (v.kerb.mesh as ArrayMesh).surface_get_arrays(0)
		var kv: PackedVector3Array = ka[Mesh.ARRAY_VERTEX]
		var kn: PackedVector3Array = ka[Mesh.ARRAY_NORMAL]
		var low := 0
		for i in kv.size():
			if kn[i].y > 0.9 and kv[i].y < surface_y:
				low += 1
		eq(low, 0, "%s: no kerb top lies under the water" % tag)
		# every kerb face is wound front side out (Godot: (c - a) x (b - a) along its normal): a double-sided back face is
		# lit from below, and the strips and corner fans overlap flush at the rim's corners, so a mix of the two fought there
		var back := 0
		for t in kv.size() / 3:
			var a := kv[t * 3]
			var n := (kv[t * 3 + 2] - a).cross(kv[t * 3 + 1] - a)
			if n.length_squared() > 1e-10 and n.dot(kn[t * 3]) <= 0.0:
				back += 1
		eq(back, 0, "%s: every kerb face is wound to face its normal" % tag)
	v.free()


func _check_force() -> void:
	SewerCluster.force = true
	# the playtest's floor (board seed 7, offer 2, floor 2: a column of kite corners at X = -51.0955) draws its water clean
	var pr: ContractRun = ContractBoard.offers(7)[1]
	var pm := DungeonGen.for_run(pr, 2)
	SiteBuilder.plan(pm, pr, 2, PricedProp.catalog(pr.site_type))
	if check(not SewerPlanner.record(pm).is_empty(), "the playtest's floor (board 7, offer 2, floor 2) has its cluster"):
		_check_water_drawing(pm, pm.pools[int(pm.sewer["body"])], pm.sewer, "board 7 offer 2 floor 2")
	var got := 0
	for s in range(1, 13):
		var run := ContractBoard.run_for_seed(s)
		var map := DungeonGen.for_run(run, 2)
		if not map.sewer.is_empty():
			got += 1
		eq(DungeonGen.for_run(run, 2, true).sewer.is_empty(), map.sewer.is_empty(), "seed %d: forced, a shared run gets the same" % s)
	SewerCluster.force = false
	check(got >= 9, "--sewer-floor forces a cluster on most floors (%d of 12)" % got)

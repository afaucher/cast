extends MonsterTestBase
## The crypt in the generator (docs/design/haunted-build-plan.md, "H2 as built"): a haunted floor's section, cut by DungeonGen
## (its "crypt" option, CryptCluster) and themed and dressed by CryptPlanner with the look test's kit.
##   - it rolls only on haunted floors (the mansion's 2-3, the church's 1-3), never on a bunker or a lair;
##   - 2-4 rooms at one base level DROP_MIN+ levels under the room above, none the start or the elevator's room, one stair of
##     STAIRS cells down into them, every room reachable from the start;
##   - its rooms are crypt rooms of the site's set, lit and dark by turns from the stair's foot, in the set's materials; the
##     lit rooms hold a row of priced sarcophagi with the vigil's candles; bone walls stand on a wall; its doorways get arches
##     and open gates, never an office door; its packs are the contract's family (skeletons and zombies, H3);
##   - it is lit as the look test lit it: its stone and its pieces on HexMapView's UNDER_LAYER, which the key and fill
##     lights leave out, and no downlight over its rooms;
##   - `crypt=` is in the map checksum text, the same checksum on two builds; a shared run gets the same crypt;
##   - a haunted floor without a crypt is the floor it always was (the map and plan texts of the generator without the
##     option).
## It prints the share of eligible floors with a crypt and the first natural seeds (for the doc and playtests).

const SEEDS := 24                ## contract seeds per haunted client
const BUILDS := 3                ## crypt floors per client spawned and built twice

var _probe: Node = null


func setup() -> void:
	timeout_sec = 480.0
	Monster.use_proto_visuals = true
	_probe = Node.new()
	_check_tables()
	_check_hellgate_sites()
	for id: String in ClientArchetype.HAUNTED_IDS:
		var crypts := 0
		var eligible := 0
		var built := 0
		var natural: Array[String] = []
		var sizes := {}
		for s in range(1, SEEDS + 1):
			var run := ContractBoard.run_for_client(id, s)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var rolled := CryptCluster.seed_for(run, f) != 0
				if (CryptCluster.FLOORS[run.site_type] as Array).has(f):
					eligible += 1
				else:
					check(not rolled, "%s/%d floor %d: no crypt on this floor of a %s" % [id, s, f, run.site_type])
				eq(CryptCluster.seed_for(run, f, true), CryptCluster.seed_for(run, f), "%s/%d floor %d: a crew rolls the solo floor's crypt" % [id, s, f])
				if not rolled:
					continue
				var map := DungeonGen.for_run(run, f)
				if map.crypt.is_empty():
					if s <= 6:
						var plan0 := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
						_check_unchanged(run, f, map, plan0, "%s/%d floor %d" % [id, s, f])
					continue
				crypts += 1
				var n := (map.crypt["rooms"] as Array).size()
				sizes[n] = int(sizes.get(n, 0)) + 1
				if natural.size() < 4:
					natural.append("%d/%d" % [s, f])
				var tag := "%s/%d floor %d" % [id, s, f]
				var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
				_check_crypt(run, f, map, plan, tag)
				if built < BUILDS:
					built += 1
					_check_built(id, s, f, tag)
				if s <= 8:
					_check_shared(run, f, tag)
		print("[crypt gen] %s: %d of %d eligible floors have a crypt (%.0f%%); sizes %s; natural seed/floor %s" % [id, crypts, eligible,
			100.0 * crypts / maxf(1.0, eligible), str(sizes), str(natural)])
		check(crypts * 6 >= eligible, "%s: some floors get a crypt (%d of %d)" % [id, crypts, eligible])
		check(built >= 2, "%s: crypt floors built and spawned (%d)" % [id, built])
	_check_forced()
	Monster.use_proto_visuals = false
	_probe.free()
	finish()


func _check_tables() -> void:
	for site: String in ["mansion", "church"]:
		check(CryptCluster.RATE.has(site) and CryptCluster.FLOORS.has(site), "the %s rolls a crypt" % site)
	check(float(CryptCluster.RATE["church"]) > float(CryptCluster.RATE["mansion"]) and (CryptCluster.FLOORS["church"] as Array).size() > (CryptCluster.FLOORS["mansion"] as Array).size(),
			"the church leans on its crypt more than the mansion")
	eq(CryptCluster.set_for("mansion"), "vault", "a vault under the mansion")
	eq(CryptCluster.set_for("church"), "chapel", "a chapel under the church")
	for set_name: String in RoomThemeDefs.CRYPT:
		for t: String in RoomThemeDefs.CRYPT[set_name]:
			var def := RoomThemeDefs.theme(t)
			check(not def.is_empty() and str(def["crypt_set"]) == set_name, "%s is a %s room" % [t, set_name])
			check(str(def.get("note_word", "")) != "" and float((def["light"] as Dictionary)["energy"]) > 0.0, "%s: a note word and an accent light" % t)
			eq(int(def["floor_mat"]), int(CryptLook.look(set_name)["floor"]), "%s wears the set's floor" % t)
			for op: Dictionary in (def["recipe"] as Array):
				check(ThemeVignettes.OPS.has(str(op["op"])), "%s: recipe op %s has a vignette" % [t, op["op"]])
			for pool_site: String in RoomThemeDefs.POOLS:
				check(not RoomThemeDefs.pool(pool_site).has(t), "%s is never dealt from a pool (%s)" % [t, pool_site])
	for set_name: String in CryptProps.SETS:
		var kind := CryptPlanner.tomb_kind(set_name)
		check(PricedProp.is_kind(kind) and PricedProp.price_of(kind) > 0, "%s is priced" % kind)
		for site: String in ["bunker", "lair", "mansion", "church"]:
			check(not PricedProp.catalog(site).has(kind), "%s is in no site's catalog (%s)" % [kind, site])
	for kind: String in RoomThemeDefs.DECOR:
		if RoomThemeDefs.decor(kind).has("crypt"):
			for set_name: String in CryptProps.SETS:
				var m := DecorModels.build(kind, {"set": set_name, "variant": 11})
				check(m.get_node_or_null("Body") is MeshInstance3D, "decor %s (%s) builds the look test's model" % [kind, set_name])
				m.free()
	var lit := DecorModels.build("crypt_candles", {"set": "vault"})
	eq(lit.find_children("CandleLight", "OmniLight3D", true, false).size(), 1, "a crypt's candles carry their light")
	lit.free()


## The hellgate sites never roll a crypt.
func _check_hellgate_sites() -> void:
	for s in range(1, 41):
		var run := ContractBoard.run_for_seed(s)
		for f in range(1, ContractRun.FLOOR_COUNT + 1):
			eq(CryptCluster.seed_for(run, f), 0, "seed %d floor %d (%s): no crypt on a %s" % [s, f, run.archetype_id, run.site_type])


func _check_crypt(run: ContractRun, f: int, map: HexMap, plan: SitePlan, tag: String) -> void:
	var rec := map.crypt
	var rooms: Array = rec["rooms"]
	var level := int(rec["level"])
	check(rooms.size() >= CryptCluster.MIN_ROOMS and rooms.size() <= CryptCluster.MAX_ROOMS, "%s: 2-4 rooms (%d)" % [tag, rooms.size()])
	check(not rooms.has(plan.start_room) and not rooms.has(plan.exit_room), "%s: never the start or the elevator's room" % tag)
	for t: String in rooms:
		eq(int(plan.base_levels[t]), level, "%s: %s at the crypt's level" % [tag, t])
	# the stair: STAIRS cells, down far enough, from the room above
	var st: Dictionary = rec["stair"]
	var stairs := 0
	for c: Vector2i in (st["cells"] as Array):
		if map.get_cell(c).type == HexMap.Tile.STAIRS:
			stairs += 1
	check(stairs >= 2, "%s: the stair has its flights (%d stair cells)" % [tag, stairs])
	var up := int(plan.base_levels[str(st["from"])])
	check(up - level >= CryptCluster.DROP_MIN, "%s: the crypt is %d+ levels under the room above (%d)" % [tag, CryptCluster.DROP_MIN, up - level])
	var route: Array = st["route"]
	eq(route[0], st["door_up"], "%s: the stair's route starts at its head" % tag)
	eq(route[route.size() - 1], st["door"], "%s: ... and ends at its foot" % tag)
	for t: String in rooms:
		var path := map.find_path(plan.start, plan.centers[t])
		check(not path.is_empty() or plan.centers[t] == plan.start, "%s: %s is reachable from the start" % [tag, t])
	# themed by set, lit and dark
	var set_name := CryptCluster.set_for(run.site_type)
	eq(str(rec["set"]), set_name, "%s: the %s's set" % [tag, run.site_type])
	var themes: Array = RoomThemeDefs.CRYPT[set_name]
	for t: String in rooms:
		if t == plan.origin_room:
			continue
		var th := str(plan.room_themes[t])
		check(themes.has(th), "%s: %s is a crypt room (%s)" % [tag, t, th])
		eq(th, themes[0] if (rec["lit"] as Array).has(t) else themes[1], "%s: %s's look" % [tag, t])
		eq(FloorMaterials.floor_of(map.get_cell(plan.centers[t]).mat_id), int(CryptLook.look(set_name)["floor"]), "%s: %s in the set's floor" % [tag, t])
	check(not (rec["lit"] as Array).is_empty() or rooms.has(plan.origin_room), "%s: a lit room" % tag)
	# the sarcophagi: a row in the lit rooms, priced
	var kind := CryptPlanner.tomb_kind(set_name)
	var tombs := 0
	for pr in plan.props:
		if str(pr["kind"]) == kind:
			tombs += 1
			check((rec["lit"] as Array).has(str(pr["room"])), "%s: a sarcophagus in a lit room" % tag)
			var back := ThemeGeo.local_to_world(pr["pos"], float(pr["yaw"]), 0.0, -1.05)
			check(map.wall_at(Vector3(back.x, 0.0, back.y)) or not map.nearest_wall(Vector3(back.x, 0.0, back.y), 0.4).is_empty(), "%s: a sarcophagus's head is at a wall" % tag)
	check(tombs >= 1, "%s: sarcophagi (%d)" % [tag, tombs])
	# the decor: bone walls on a wall, the vigil's candles, the gates
	var by_kind := {}
	for dc in plan.decor:
		by_kind[str(dc["kind"])] = int(by_kind.get(str(dc["kind"]), 0)) + 1
		if str(dc["kind"]) == "ossuary":
			var bp := ThemeGeo.local_to_world(dc["pos"], float(dc["yaw"]), 0.0, -float(dc["d"]) * 0.5)
			var w := map.nearest_wall(Vector3(bp.x, 0.0, bp.y), 0.35)
			check(not w.is_empty(), "%s: a bone wall's back is on a wall face" % tag)
			for e in [-0.45, 0.45]:
				var ep := ThemeGeo.local_to_world(dc["pos"], float(dc["yaw"]), float(dc["w"]) * e, -float(dc["d"]) * 0.5)
				check(not map.nearest_wall(Vector3(ep.x, 0.0, ep.y), 0.35).is_empty(), "%s: ... along its whole width" % tag)
	check(int(by_kind.get("ossuary", 0)) >= 1, "%s: bone walls (%s)" % [tag, str(by_kind.get("ossuary", 0))])
	check(int(by_kind.get("crypt_candles", 0)) + int(by_kind.get("crypt_candelabra", 0)) >= 2, "%s: candles" % tag)
	var dws := Doorways.find(map, Doorways.spaces(map))
	var mine := CryptPlanner.doorways(map, dws)
	eq(int(by_kind.get("crypt_gate", 0)) + int(by_kind.get("crypt_arch", 0)), mine.size(), "%s: an arch or a gate in each crypt doorway" % tag)
	check(int(by_kind.get("crypt_gate", 0)) >= 1, "%s: a gate at the stair's foot" % tag)
	for dr in plan.doors:
		check(not mine.has(int(dr["id"])), "%s: no office door on a crypt doorway" % tag)
	if set_name == "chapel":
		check(int(by_kind.get("light_shaft", 0)) >= 1, "%s: the chapel's shafts from above" % tag)
	# the map text carries the record
	check(NetFloor.map_text_of(map).contains("\ncrypt="), "%s: crypt= in the map checksum" % tag)
	check(not NetFloor.map_text_of(map).contains("\nsewer=") and map.cave.is_empty(), "%s: no sewer cluster or lava cave beside it" % tag)


## Spawned (as the game builds a floor) and built twice: the same checksum, priced sarcophagi, only the dead family in the crypt.
func _check_built(id: String, s: int, f: int, tag: String) -> void:
	var a := _build(id, s, f)
	var map: HexMap = a["map"]
	var site: SiteBuilder.Site = a["site"]
	var rooms: Array = map.crypt["rooms"]
	var priced := 0
	for p: PricedProp in site.props:
		if p.kind.ends_with("_sarcophagus"):
			priced += 1
			check(p.price > 0 and p.site == "crypt", "%s: a sarcophagus is priced" % tag)
	check(priced >= 1, "%s: the sarcophagi spawn as priced props (%d)" % [tag, priced])
	var in_crypt := 0
	for m in site.monsters:
		var cell := map.get_cell(Hex.from_world(m.global_position))
		if cell != null and rooms.has(cell.tag):
			in_crypt += 1
			check(m.kind in ["grunt", "zombie"], "%s: the crypt's packs are the family's skeletons and zombies (%s)" % [tag, m.kind])
	var lights := 0
	var under_pieces := 0
	for d in site.decor:
		lights += d.find_children("CandleLight", "OmniLight3D", true, false).size()
		for g in d.find_children("*", "GeometryInstance3D", true, false):
			if (g as GeometryInstance3D).layers == HexMapView.UNDER_LAYER:
				under_pieces += 1
				break
	check(lights >= 2, "%s: candle lights in the crypt (%d)" % [tag, lights])
	check(under_pieces >= 3, "%s: the crypt's pieces are out of the key light (%d)" % [tag, under_pieces])
	# the terrain: the crypt's stone on the underground layer, which the key and fill lights leave out
	var view := HexMapView.new()
	world.add_child(view)
	view.build(map)
	check(view.under_instance != null and view.under_instance.layers == HexMapView.UNDER_LAYER, "%s: the crypt's stone is drawn underground" % tag)
	check(view.mesh_instance.layers & HexMapView.UNDER_LAYER == 0, "%s: the rest of the floor is not" % tag)
	var look := Node3D.new()
	world.add_child(look)
	DungeonLook.apply(look, map)
	for n in ["KeyLight", "FillLight"]:
		var l := look.get_node_or_null(n) as Light3D
		check(l != null and l.light_cull_mask & HexMapView.UNDER_LAYER == 0, "%s: the %s leaves the crypt out" % [tag, n])
	var crypt_rooms := {}
	for t: String in rooms:
		crypt_rooms[t] = true
	var downlit := 0
	for dl in look.get_node("Downlights").get_children():
		var c := map.get_cell(Hex.from_world((dl as Node3D).position))
		if c != null and crypt_rooms.has(c.tag):
			downlit += 1
	eq(downlit, 0, "%s: no downlight over the crypt" % tag)
	var b := _build(id, s, f)
	eq(str(a["sum"]["all"]), str(b["sum"]["all"]), "%s: the same checksum on two builds (%s)" % [tag, ", ".join(NetFloor.differing_parts(a["sum"], b["sum"]))])
	eq(int(a["ids"]), int(b["ids"]), "%s: the same net ids" % tag)
	print("[crypt gen] %s: %d sarcophagi, %d of the dead in the crypt, %d candle lights" % [tag, priced, in_crypt, lights])


func _build(id: String, s: int, f: int) -> Dictionary:
	var run := ContractBoard.run_for_client(id, s)
	var map := DungeonGen.for_run(run, f)
	new_world(map)
	GameWorld.begin(map, world, run.floor_seed(f))
	var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
	var site := SiteBuilder.spawn(map, run, plan)
	var ids := NetFloor.assign_ids(world, {})
	var sum := NetFloor.checksum(map, plan, run, world)
	return {"run": run, "map": map, "plan": plan, "site": site, "ids": ids, "sum": sum}


## A haunted floor that rolled a crypt but found no wing is the floor the generator always built.
func _check_unchanged(run: ContractRun, f: int, map: HexMap, plan: SitePlan, tag: String) -> void:
	var ref := DungeonGen.generate(run.floor_seed(f), {"elevator": run.elevator_place})
	var ref_plan := SiteBuilder.plan(ref, run, f, PricedProp.catalog(run.site_type))
	var a := NetFloor.checksum(map, plan, run, _probe)
	var b := NetFloor.checksum(ref, ref_plan, run, _probe)
	eq(str(a["map"]), str(b["map"]), "%s: no crypt, the map it always was" % tag)
	eq(str(a["plan"]), str(b["plan"]), "%s: no crypt, the plan it always was" % tag)
	for c: Vector2i in map.cells:
		if FloorMaterials.is_under(map.cells[c].mat_id):
			check(false, "%s: no crypt, nothing underground (%s)" % [tag, c])
			break


func _check_shared(run: ContractRun, f: int, tag: String) -> void:
	var shared := DungeonGen.for_run(run, f, true)
	check(not shared.crypt.is_empty(), "%s: a shared run gets the crypt too" % tag)


## --crypt-floor: a crypt wherever a wing fits, on a hellgate site a vault; off again, the floor as before.
func _check_forced() -> void:
	var run := ContractBoard.run_for_seed(5)
	var before := NetFloor.map_text_of(DungeonGen.for_run(run, 2))
	CryptCluster.force = true
	var forced := 0
	for f in range(1, ContractRun.FLOOR_COUNT + 1):
		var map := DungeonGen.for_run(run, f)
		if not map.crypt.is_empty():
			forced += 1
			var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			eq(str(map.crypt["set"]), "vault", "forced on a %s: a vault" % run.site_type)
			check(not plan.room_themes.is_empty(), "forced: planned")
	CryptCluster.force = false
	check(forced >= 1, "--crypt-floor forces a crypt (%d of 3 floors)" % forced)
	eq(NetFloor.map_text_of(DungeonGen.for_run(run, 2)), before, "without the flag the hellgate floor is as before")

extends MonsterTestBase
## Haunted contracts, step H1 (docs/design/haunted-build-plan.md): the two haunted clients (ClientArchetype.HAUNTED_IDS, the
## dead pest family, a mansion and a church), their contracts (no hellgates, no gate or origin objective, the pest per floor
## pays, skeletons only), the board dealing them on dice of its own (the hellgate offers dealt as before), and their floors
## built the way the game builds them: no gate, no section, only skeletons, rooms from the haunted pools dressed with the
## look test's props, priced antiques from the site's catalog, notes and dispatch lines that never name a gate, and the same
## NetFloor checksum on two builds (the crew's load barrier).

const SEEDS: Array[int] = [3, 11, 42]
const BUILD_SEEDS: Array[int] = [3, 11]

var _ops := {}   ## "theme.op" -> Vector2i(placed, tried), over every floor built (printed: how well the rooms dress)


func setup() -> void:
	timeout_sec = 240.0
	Monster.use_proto_visuals = true   # (the checks read kinds, positions and the checksum, never the meshes)
	_check_tables()
	_check_runs()
	_check_board()
	for id: String in ClientArchetype.HAUNTED_IDS:
		for s in BUILD_SEEDS:
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				_check_floor(id, s, f)
	Monster.use_proto_visuals = false
	var keys := _ops.keys()
	keys.sort()
	var parts: Array[String] = []
	for k: String in keys:
		parts.append("%s %d/%d" % [k, (_ops[k] as Vector2i).x, (_ops[k] as Vector2i).y])
	print("haunted recipe ops (placed/tried): ", ", ".join(parts))
	finish()


func _check_tables() -> void:
	eq(ClientArchetype.ALL_IDS, ClientArchetype.IDS + ClientArchetype.HAUNTED_IDS, "every client: the hellgate clients first, then the haunted")
	eq(ClientArchetype.IDS.size(), 5, "the hellgate clients are the five (their order seeds every hellgate contract)")
	var sites := {}
	for id: String in ClientArchetype.HAUNTED_IDS:
		var d := ClientArchetype.get_data(id)
		eq(ClientArchetype.family_of(id), ClientArchetype.FAMILY_DEAD, "%s is the dead family" % id)
		sites[str(d["site"])] = true
		for k: String in d["pests"]:
			check(ClientArchetype.family_kinds(ClientArchetype.FAMILY_DEAD).has(k), "%s's pest %s is of its family" % [id, k])
		eq(float(d["everything_chance"]), 0.0, "%s never rolls 'everything'" % id)
		check(NoteCopy.STORY.has(id) and (d["events"] as Array).size() >= 3, "%s has events and notes" % id)
		for key in ["good", "mid", "bad", "incap"]:
			check(str(d["footers"][key]) != "", "%s footer %s" % [id, key])
		check(ClientArchetype.ACCENTS.has(id), "%s has an accent" % id)
		for ev: Dictionary in (d["events"] as Array):
			var origin := str(ev["origin"])
			check(RoomThemeDefs.ORIGIN_THEMES.has(origin), "%s: origin '%s' is in the mapping table" % [id, origin])
			check(RoomThemeDefs.pool(str(d["site"])).has(RoomThemeDefs.origin_theme(str(d["site"]), origin)), "%s: origin '%s' names a room of its site" % [id, origin])
		for floor_n in range(1, 4):
			for ln: Dictionary in (NoteCopy.STORY[id][floor_n] as Array):
				check(not str(ln["t"]).to_lower().contains("gate"), "%s: no story note names a gate (%s)" % [id, ln["t"]])
	check(sites.has("mansion") and sites.has("church"), "a mansion client and a church client")
	for id: String in ClientArchetype.IDS:
		eq(ClientArchetype.family_of(id), ClientArchetype.FAMILY_GATE, "%s is the hellgate family" % id)
	for f in range(1, 4):
		for t: String in NoteCopy.DISPATCH_DEAD[f]:
			check(not t.to_lower().contains("gate"), "a haunted dispatch line names no gate (%s)" % t)
	# the rooms
	var mansion := RoomThemeDefs.pool("mansion")
	for t in ["library", "gallery", "ballroom", "dining_hall", "conservatory", "wine_cellar"]:
		check(mansion.has(t), "the mansion deals the %s" % t)
	check(RoomThemeDefs.pool("church").has("nave"), "the church deals the nave")
	for site in ["mansion", "church"]:
		var catalog := PricedProp.catalog(site)
		check(catalog.size() >= 5, "the %s has priced antiques (%d)" % [site, catalog.size()])
		for t: String in RoomThemeDefs.pool(site):
			check(not RoomThemes.priced_kinds(t, catalog).is_empty(), "%s: the %s's antiques are in the site's catalog" % [site, t])
		for k: String in (PropPlanner.LANDING_KINDS[site] as Array):
			check(catalog.has(k), "%s: the landing piece %s is in the catalog" % [site, k])
		check(FloorMaterials.SITE_WALL.has(site) and FloorMaterials.SITE_CORRIDOR.has(site), "%s has its hall materials" % site)
		check(not SewerCluster.SITES.has(site), "%s rolls no sewer cluster (H1)" % site)
	check(PricedProp.catalog("mansion").has("suit_of_armour"), "a suit of armour is billed")
	for kind: String in RoomThemeDefs.DECOR:
		if RoomThemeDefs.decor(kind).has("haunt"):
			var m := DecorModels.build(kind, {"variant": 7})
			check(m.get_node_or_null("Body") is MeshInstance3D, "decor %s builds the look test's model" % kind)
			m.free()


func _check_runs() -> void:
	for id: String in ClientArchetype.HAUNTED_IDS:
		for s in SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var tag := "%s/%d" % [id, s]
			eq(run.family, ClientArchetype.FAMILY_DEAD, "%s: the dead family" % tag)
			check(not run.has_gates(), "%s: no hellgates" % tag)
			eq(run.floor_gates, [0, 0, 0] as Array[int], "%s: no gate on any floor" % tag)
			eq(run.pest, "grunt", "%s: the pest is the family's skeleton" % tag)
			eq(run.family_kinds(), ["grunt"] as Array[String], "%s: packs of skeletons only" % tag)
			var value := 0
			var pests := 0
			for o in run.objectives:
				value += int(o["pay"])
				check(str(o["kind"]) == "pest", "%s: only pest objectives (%s)" % [tag, o["kind"]])
				pests += 1
			eq(pests, ContractRun.FLOOR_COUNT, "%s: a pest objective per floor" % tag)
			eq(value + run.total_employees() * ContractRun.EMPLOYEE_EXTRACTED, run.contract_value, "%s: the contract value" % tag)
			check(run.pest_pay > ContractRun.PEST_PAY * 0.8, "%s: the pest pays for the whole job (%d)" % [tag, run.pest_pay])
			for ln in run.card_lines():
				check(not str(ln["label"]).to_lower().contains("gate"), "%s: the card names no gate (%s)" % [tag, ln["label"]])
			var again := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			eq([again.client_name, again.story, again.floor_employees, again.contract_value], [run.client_name, run.story, run.floor_employees, run.contract_value],
					"%s: deterministic" % tag)
	var gate_run := ContractRun.make("prepper", 3, 0.5)
	check(gate_run.has_gates() and gate_run.family == ClientArchetype.FAMILY_GATE and gate_run.total_gates() > 0, "a hellgate client keeps its gates")
	eq(ContractBoard.run_for_client("heir", 9).site_type, "mansion", "the --client flag's contract")


## The board: some boards deal a haunted offer, never two; every other slot is exactly the offer the board always dealt.
func _check_board() -> void:
	var haunted := 0
	for b in range(1, 81):
		var offers := ContractBoard.offers(b)
		var old := _old_offers(b)
		var ids := {}
		var h := 0
		for i in offers.size():
			ids[offers[i].archetype_id] = true
			if ClientArchetype.HAUNTED_IDS.has(offers[i].archetype_id):
				h += 1
				eq(offers[i].seed, old[i][1], "board %d slot %d: a haunted offer keeps the slot's seed" % [b, i])
				continue
			eq([offers[i].archetype_id, offers[i].seed, offers[i].difficulty], old[i], "board %d slot %d: the hellgate offer as it always was" % [b, i])
		check(h <= 1, "board %d: at most one haunted offer" % b)
		eq(ids.size(), ContractBoard.OFFER_COUNT, "board %d: three different clients" % b)
		haunted += h
	check(haunted > 10 and haunted < 70, "some boards deal a haunted offer (%d of 80)" % haunted)


## ContractBoard.offers before H1: [archetype, seed, difficulty] per slot.
func _old_offers(board_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed * 40503 + 7
	var ids: Array[String] = ClientArchetype.IDS.duplicate()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := ids[i]
		ids[i] = ids[j]
		ids[j] = t
	var tiers: Array[float] = [rng.randf_range(0.1, 0.35), rng.randf_range(0.4, 0.65), rng.randf_range(0.7, 0.95)]
	for i in range(tiers.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tt := tiers[i]
		tiers[i] = tiers[j]
		tiers[j] = tt
	var out: Array = []
	var used := {}
	for i in ContractBoard.OFFER_COUNT:
		var s := ((board_seed * 31 + i * 7919 + 1) & 0x7fffffff) % 100000
		while used.has(s):
			s = (s + 1) % 100000
		used[s] = true
		out.append([ids[i], s, clampf(tiers[i], 0.0, 1.0)])
	return out


## One floor of a haunted contract, built as the game builds it (test_golden_floor's way), twice.
func _check_floor(id: String, s: int, f: int) -> void:
	var tag := "%s/%d floor %d" % [id, s, f]
	var a := _build(id, s, f)
	var run: ContractRun = a["run"]
	var map: HexMap = a["map"]
	var plan: SitePlan = a["plan"]
	var site: SiteBuilder.Site = a["site"]
	var site_type := run.site_type
	# no hellgate, no section
	check(plan.gates.is_empty() and site.gates.is_empty() and site.origin_gate == null and site.beasts.is_empty(), "%s: no hellgate" % tag)
	check(map.sewer.is_empty() and map.cave.is_empty(), "%s: no sewer cluster or lava cave" % tag)
	check(site.scouts.is_empty() and site.sharks.is_empty() and site.gators.is_empty(), "%s: no goblin scout, shark or gator" % tag)
	# only skeletons, and enough of them to exterminate
	check(site.monsters.size() > 0, "%s: monsters spawned (%d)" % [tag, site.monsters.size()])
	var kinds := {}
	for m in site.monsters:
		kinds[m.kind] = true
	eq(kinds.keys(), ["grunt"], "%s: skeletons only" % tag)
	check(site.pest_spawned >= PackPlanner.PEST_MIN, "%s: at least %d to exterminate (%d)" % [tag, PackPlanner.PEST_MIN, site.pest_spawned])
	# the rooms: the haunted pool, the service entrance; the origin room on the last floor
	var pool := RoomThemeDefs.pool(site_type)
	var themes := {}
	for rt: String in plan.room_themes:
		var t := str(plan.room_themes[rt])
		themes[t] = true
		check(t == RoomThemeDefs.SERVICE or pool.has(t), "%s: %s is a %s room" % [tag, t, site_type])
	if f == ContractRun.FLOOR_COUNT:
		check(plan.origin_room != "", "%s: the story's origin room" % tag)
		eq(str(plan.room_themes.get(plan.origin_room, "")), RoomThemeDefs.origin_theme(site_type, str(run.story["origin"])), "%s: the origin room is the story's room" % tag)
	for rep in plan.decor_report:
		if not bool(rep["skipped"]):
			var key := "%s.%s" % [rep["theme"], rep["op"]]
			_ops[key] = (_ops.get(key, Vector2i.ZERO) as Vector2i) + Vector2i(1 if bool(rep["ok"]) else 0, 1)
	var haunt_decor := 0
	for dc in plan.decor:
		if RoomThemeDefs.decor(str(dc["kind"])).has("haunt"):
			haunt_decor += 1
	check(haunt_decor >= 4, "%s: the rooms are dressed with the look test's props (%d pieces)" % [tag, haunt_decor])
	var catalog := PricedProp.catalog(site_type)
	for pr in plan.props + plan.set_pieces:
		check(catalog.has(str(pr["kind"])), "%s: %s is one of the site's antiques" % [tag, pr["kind"]])
	# employees, notes, the dispatch line
	check(plan.employees.size() >= 2, "%s: staff to extract" % tag)
	for e in plan.employees:
		check(SiteBuilder.STAFF_NAMES.has(str(e["name"])), "%s: the household's staff (%s)" % [tag, e["name"]])
	eq(plan.notes.size(), 2, "%s: a story note and a hint slip" % tag)
	for nt in plan.notes:
		check(not str(nt["text"]).to_lower().contains("gate") and str(nt["text"]).length() <= NoteCopy.MAX_LEN, "%s: a note fits and names no gate (%s)" % [tag, nt["text"]])
	check(plan.dispatch != "" and not plan.dispatch.to_lower().contains("gate"), "%s: a dispatch line without a gate (%s)" % [tag, plan.dispatch])
	# the materials: the house rooms' walnut & damask, the church's limestone halls
	for rt: String in plan.room_themes:
		var t := str(plan.room_themes[rt])
		if t == RoomThemeDefs.SERVICE:
			continue
		var c: Vector2i = plan.centers[rt]
		eq(FloorMaterials.floor_of(map.get_cell(c).mat_id), FloorMaterials.floor_for_theme(t), "%s: the %s's floor" % [tag, t])
	# the same floor twice: the crew's load barrier compares this checksum
	var b := _build(id, s, f)
	eq(str(a["sum"]["all"]), str(b["sum"]["all"]), "%s: the same checksum on two builds (%s)" % [tag, ", ".join(NetFloor.differing_parts(a["sum"], b["sum"]))])
	eq(int(a["ids"]), int(b["ids"]), "%s: the same net ids" % tag)
	# the family is in the run part (a hellgate contract leaves it out: NetFloor.RUN_DEFAULTS)
	run.family = ClientArchetype.FAMILY_GATE
	var as_gate := NetFloor.checksum(b["map"], b["plan"], run, world)
	run.family = ClientArchetype.FAMILY_DEAD
	check(str(as_gate["run"]) != str(b["sum"]["run"]), "%s: the family is in the checksum's run part" % tag)


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

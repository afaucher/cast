extends TestCase
## Contract generation: determinism, the three floors' contents (small gates on 1-2, the origin gate
## in the origin room on 3), employees far from the gates, props clear of start/exit/corridors,
## and that every client archetype generates a full contract.

const SEEDS: Array[int] = [1, 2, 3, 7, 42, 99, 1234]


func setup() -> void:
	_check_tables()
	_check_run_determinism()
	for id in ClientArchetype.IDS:
		for s in SEEDS:
			_check_contract(ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05))
	_check_plan_determinism()
	_check_every_archetype_generates()
	await _check_spawn_smoke()
	finish()


func _check_tables() -> void:
	eq(ClientArchetype.IDS.size(), 5, "five client archetypes")
	for id in ClientArchetype.IDS:
		var d := ClientArchetype.get_data(id)
		check(d["site"] == "bunker" or d["site"] == "lair", "%s has a site type" % id)
		for k: String in d["pests"]:
			check(k == "everything" or MonsterFactory.KINDS.has(k), "%s pest '%s' is a monster kind" % [id, k])
		check((d["events"] as Array).size() >= 3 and NoteCopy.STORY.has(id), "%s has events and notes" % id)
		for key in ["good", "mid", "bad", "incap"]:
			check(str(d["footers"][key]) != "", "%s footer %s" % [id, key])
	var sites := {}
	for id in ClientArchetype.IDS:
		sites[ClientArchetype.site_of(id)] = true
	check(sites.has("bunker") and sites.has("lair"), "both site types are used")


func _check_run_determinism() -> void:
	var a := ContractRun.make("guru", 77, 0.6)
	var b := ContractRun.make("guru", 77, 0.6)
	eq(a.client_name, b.client_name, "same name")
	eq(a.pest, b.pest, "same pest")
	eq(a.story, b.story, "same story")
	eq(a.contract_value, b.contract_value, "same value")
	eq(a.floor_employees, b.floor_employees, "same staff")
	# (The story used to carry the shuffled clue order, so two seeds almost always differed there; now compare the
	# whole roll, over a few seeds.)
	var differs := false
	for s in [78, 79, 80]:
		var c := ContractRun.make("guru", s, 0.6)
		if a.client_name != c.client_name or a.story != c.story or a.pest != c.pest or a.floor_employees != c.floor_employees 				or a.floor_gates != c.floor_gates or a.company != c.company:
			differs = true
	check(differs, "a different seed rolls a different contract")
	eq(a.floor_seed(1), a.seed, "floor 1 uses the contract seed")
	check(a.floor_seed(2) != a.floor_seed(3) and a.floor_seed(2) != a.seed, "each floor has its own dungeon seed")


func _check_contract(run: ContractRun) -> void:
	var tag := "%s/%d" % [run.archetype_id, run.seed]
	eq(run.objectives.is_empty(), false, "%s has objectives" % tag)
	var gates := 0
	var origin := 0
	var pest := 0
	var value := 0
	for o in run.objectives:
		value += int(o["pay"])
		match o["kind"]:
			"gate": gates += 1
			"origin": origin += 1
			"pest": pest += 1
	eq(gates, run.total_gates(), "%s gate objectives" % tag)
	eq(origin, 1, "%s one origin gate" % tag)
	eq(pest, ContractRun.FLOOR_COUNT, "%s pest objective per floor" % tag)
	eq(value + run.total_employees() * ContractRun.EMPLOYEE_EXTRACTED, run.contract_value, "%s contract value" % tag)
	var pest_sum := 0
	for v in run.pest_floor_pay:
		pest_sum += v
	eq(pest_sum, run.pest_pay, "%s pest pay splits exactly" % tag)
	check(run.floor_gates[0] >= 1 and run.floor_gates[1] >= 1 and run.floor_gates[2] == 0, "%s small gates on floors 1-2 only" % tag)

	var catalog := PricedProp.catalog(run.site_type)
	for f in range(1, ContractRun.FLOOR_COUNT + 1):
		var map := DungeonGen.generate(run.floor_seed(f))
		var plan := SiteBuilder.plan(map, run, f, catalog)
		var ftag := "%s floor %d" % [tag, f]
		check(plan.start_room != "" and plan.start_room != plan.exit_room, "%s: start and exit rooms differ" % ftag)
		# --- gates ---
		if f < ContractRun.FLOOR_COUNT:
			eq(plan.small_gate_count(), run.floor_gates[f - 1], "%s: small gates placed" % ftag)
			check(not plan.has_origin(), "%s: no origin gate before floor 3" % ftag)
		else:
			check(plan.has_origin(), "%s: the origin gate" % ftag)
			eq(plan.gates.size(), 1, "%s: floor 3 holds only the origin gate" % ftag)
			eq(plan.small_gate_count(), 0, "%s: no small gates on floor 3" % ftag)
			if not plan.gates.is_empty():
				var g: Dictionary = plan.gates[0]
				eq(str(g["room"]), plan.origin_room, "%s: the origin gate is in the origin room" % ftag)
				eq(plan.room_of_cell(g["cell"]), plan.origin_room, "%s: the origin gate cell lies in the origin room" % ftag)
				check(plan.origin_room != plan.start_room and plan.origin_room != plan.exit_room, "%s: origin room is not start/exit" % ftag)
		for g in plan.gates:
			var gc: Vector2i = g["cell"]
			var cell: HexMap.Cell = map.get_cell(gc)
			check(cell != null and cell.type == HexMap.Tile.FLOOR, "%s: gate stands on floor" % ftag)
			check(Hex.distance(gc, plan.start) >= SiteBuilder.START_CLEAR and Hex.distance(gc, plan.exit) >= SiteBuilder.EXIT_CLEAR, "%s: gate keeps clear of start/exit" % ftag)
		# --- employees: far from the gates ---
		eq(plan.employees.size(), run.floor_employees[f - 1], "%s: employees placed" % ftag)
		check(plan.employees.size() >= 2 and plan.employees.size() <= 4, "%s: 2-4 employees" % ftag)
		var half := maxi(1, int(ceil(plan.ranked_rooms.size() / 2.0)))
		for e in plan.employees:
			var rank := plan.ranked_rooms.find(str(e["room"]))
			check(rank >= 0 and rank < half, "%s: employee room %s is among the farthest half (rank %d of %d)" % [ftag, e["room"], rank, plan.ranked_rooms.size()])
			for gate_cell in plan.gate_cells():
				check(Hex.distance(gate_cell, e["cell"]) >= 4, "%s: employee at least 4 cells from a gate" % ftag)
			check(plan.room_of_cell(e["cell"]) != plan.start_room, "%s: employees are not in the start room" % ftag)
		# --- props never block start / exit / corridors ---
		for pr in plan.props:
			var c: Vector2i = pr["cell"]
			check(Hex.distance(c, plan.start) > SiteBuilder.START_CLEAR and Hex.distance(c, plan.exit) > SiteBuilder.EXIT_CLEAR, "%s: prop clear of start/exit" % ftag)
			for cc: Vector2i in map.cells:
				if map.cells[cc].tag == "corridor":
					if Hex.distance(c, cc) <= SiteBuilder.CORRIDOR_CLEAR:
						check(false, "%s: prop %s too close to a corridor" % [ftag, c])
						break
			check(map.get_cell(c).type == HexMap.Tile.FLOOR, "%s: prop on floor" % ftag)
			check(catalog.has(str(pr["kind"])), "%s: prop kind comes from the catalog" % ftag)
		check(plan.props.size() <= 6 and SiteBuilder.MAX_PROPS == 6, "%s: at most 6 props a floor (%d)" % [ftag, plan.props.size()])
		check(SiteBuilder.PROP_SPACING >= 4, "props keep at least 4 apart")
		for i in plan.props.size():
			var pc: Vector2i = plan.props[i]["cell"]
			var by_wall := false
			for d in Hex.DIRS:
				var nb: HexMap.Cell = map.get_cell(pc + d)
				if nb != null and nb.type == HexMap.Tile.WALL:
					by_wall = true
			check(by_wall, "%s: prop %s stands next to a wall" % [ftag, pc])
			check(map.get_cell(pc).tag.begins_with("room:"), "%s: prop %s is in a room, not a corridor" % [ftag, pc])
			for j in range(i + 1, plan.props.size()):
				check(Hex.distance(pc, plan.props[j]["cell"]) >= 4, "%s: props %s and %s are 4+ apart" % [ftag, pc, plan.props[j]["cell"]])
		# --- packs: about 30% lighter than the old budgets ---
		for rtag: String in plan.pack_budgets:
			var idx := int(rtag.trim_prefix("room:"))
			var old_max := 5 + idx + 3 * (f - 1) + int(roundf(run.difficulty * 3.0)) + 3
			check(int(plan.pack_budgets[rtag]) <= maxi(2, int(ceil(0.7 * old_max))), "%s: %s pack budget %d is 30%% under the old %d" % [ftag, rtag, plan.pack_budgets[rtag], old_max])
		check(plan.pack_budgets.size() >= 4, "%s: monster packs planned" % ftag)
		check(not plan.pack_budgets.has(plan.start_room), "%s: no pack in the start room" % ftag)


func _plan_dump(p: SitePlan) -> String:
	return str([p.gates, p.employees, p.props, p.notes, p.pack_budgets, p.ranked_rooms, p.origin_room])


func _check_plan_determinism() -> void:
	var run := ContractRun.make("supervillain", 31, 0.7)
	var catalog := PricedProp.catalog(run.site_type)
	for f in range(1, 4):
		var map := DungeonGen.generate(run.floor_seed(f))
		var a := SiteBuilder.plan(map, run, f, catalog)
		var b := SiteBuilder.plan(DungeonGen.generate(run.floor_seed(f)), run, f, catalog)
		eq(_plan_dump(a), _plan_dump(b), "plan for floor %d is deterministic" % f)
	var other := ContractRun.make("supervillain", 32, 0.7)
	var pa := SiteBuilder.plan(DungeonGen.generate(run.floor_seed(2)), run, 2, catalog)
	var pb := SiteBuilder.plan(DungeonGen.generate(other.floor_seed(2)), other, 2, catalog)
	check(_plan_dump(pa) != _plan_dump(pb), "a different contract gives a different site")


func _check_every_archetype_generates() -> void:
	var seen_sites := {}
	for id in ClientArchetype.IDS:
		var run := ContractRun.make(id, 5, 0.5)
		check(run.client_name != "" and run.company != "", "%s has a client name and company" % id)
		check(run.story.has("event") and run.story.has("origin"), "%s has a story" % id)
		check(run.contract_value > 0, "%s has a contract value" % id)
		seen_sites[run.site_type] = true
		var map := DungeonGen.generate(run.floor_seed(1))
		var plan := SiteBuilder.plan(map, run, 1, PricedProp.catalog(run.site_type))
		check(plan.gates.size() > 0 and plan.employees.size() > 0, "%s floor 1 has gates and employees" % id)
	eq(seen_sites.size(), 2, "both bunker and lair contracts exist")
	var pays := {}
	for id in ClientArchetype.IDS:
		pays[ContractRun.make(id, 5, 0.5).gate_pay] = true
	check(pays.size() >= 3, "the clients pay different rates")


## Spawn a real floor: the packs lean toward the pest and there is something to exterminate.
func _check_spawn_smoke() -> void:
	var run := ContractRun.make("prepper", 3, 0.5)
	run.pest = "swarmer"
	var map := DungeonGen.generate(run.floor_seed(1))
	var world := Node3D.new()
	add_child(world)
	GameWorld.begin(map, world, 1)
	var site := SiteBuilder.build(map, run, 1)
	check(site.monsters.size() > 0, "monsters spawned")
	check(site.pest_spawned >= PackPlanner.PEST_MIN, "at least %d pests on the floor (got %d)" % [PackPlanner.PEST_MIN, site.pest_spawned])
	var swarmers := 0
	for m in site.monsters:
		if m.kind == "swarmer":
			swarmers += 1
	check(swarmers * 3 >= site.monsters.size() / 2, "the swarmer pest is over-represented (%d of %d)" % [swarmers, site.monsters.size()])
	eq(site.notes.size(), 2, "two notes (a story note and a hint slip)")
	var start_room_monsters := 0
	for m in site.monsters:
		if site.plan.room_of_cell(Hex.from_world(m.global_position)) == site.plan.start_room:
			start_room_monsters += 1
	eq(start_room_monsters, 0, "no monsters in the start room")
	# Density cap: at most one monster per 6 walkable room cells, and non-swarmers are spread out.
	var per_room: Dictionary = {}
	for m in site.monsters:
		var rt := site.plan.room_of_cell(Hex.from_world(m.global_position))
		per_room[rt] = int(per_room.get(rt, 0)) + 1
	for rt: String in per_room:
		var cap := SiteBuilder.room_cap(map, site.plan.rooms[rt])
		check(int(per_room[rt]) <= cap, "%s holds %d monsters, cap %d (1 per %d cells)" % [rt, per_room[rt], cap, MonsterFactory.CELLS_PER_MONSTER])
	eq(MonsterFactory.CELLS_PER_MONSTER, 6, "one monster per 6 walkable room cells")
	var near_sum := 0.0
	var near_n := 0
	var solo: Array[Monster] = []
	for m in site.monsters:
		if m.kind != "swarmer":
			solo.append(m)
	for m in solo:
		var best := 99
		for o in solo:
			if o != m and site.plan.room_of_cell(Hex.from_world(o.global_position)) == site.plan.room_of_cell(Hex.from_world(m.global_position)):
				best = mini(best, Hex.distance(Hex.from_world(m.global_position), Hex.from_world(o.global_position)))
		if best < 99:
			near_sum += best
			near_n += 1
	check(near_n == 0 or near_sum / near_n >= 3.0, "packs are spread out: average nearest neighbour %.1f cells" % (near_sum / maxi(1, near_n)))
	await get_tree().physics_frame
	GameWorld.end()
	world.queue_free()

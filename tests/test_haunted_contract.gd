extends MonsterTestBase
## Haunted contracts, step H1 (docs/design/haunted-build-plan.md): the two haunted clients (ClientArchetype.HAUNTED_IDS, the
## dead pest family, a mansion and a church), their contracts (no hellgates, no gate or origin objective, the pest per floor
## pays, the pest skeletons or zombies: H3), the board dealing them on dice of its own (the hellgate offers dealt as before), and their floors
## built the way the game builds them: no gate, no sewer or lava section (a crypt may roll since H2: its rooms are crypt
## rooms, tests/test_crypt_gen.gd), only the dead family (skeletons and zombies since H3), rooms from the haunted pools dressed with the
## look test's props, priced antiques from the site's catalog, notes and dispatch lines that never name a gate, and the same
## NetFloor checksum on two builds (the crew's load barrier). H6: the last floor has its grimoire (in the story's room, where
## the origin gate would be; floors 1-2 none), and the invoice reads like a hellgate contract's (acolytes on floors 1-2, the
## grimoire on floor 3, the pest at the standard rate: no H1 bonus).

const SEEDS: Array[int] = [3, 11, 42]
const BUILD_SEEDS: Array[int] = [3, 11]

var _ops := {}   ## "theme.op" -> Vector2i(placed, tried), over every floor built (printed: how well the rooms dress)
var totals := {}  ## floor tag -> {kind: count}: the dead family's mix over every floor built (H3b: rats and blobs turn up)


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
	var seen := {}
	for t: String in totals:
		for k: String in (totals[t] as Dictionary):
			seen[k] = true
	check(seen.has("crypt_rat") and seen.has("ecto_blob"), "H3b: the haunted floors deal crypt rats and ecto blobs (%s)" % str(seen.keys()))
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
	var pests_seen := {}
	for id: String in ClientArchetype.HAUNTED_IDS:
		for s in SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var tag := "%s/%d" % [id, s]
			eq(run.family, ClientArchetype.FAMILY_DEAD, "%s: the dead family" % tag)
			check(not run.has_gates(), "%s: no hellgates" % tag)
			eq(run.floor_gates, [0, 0, 0] as Array[int], "%s: no gate on any floor" % tag)
			check(run.pest in ["grunt", "zombie"], "%s: the pest is one of the family's, skeletons or zombies (%s)" % [tag, run.pest])
			eq(run.family_kinds(), ["grunt", "zombie", "crypt_rat", "ecto_blob"] as Array[String], "%s: packs of the dead family: skeletons, zombies, crypt rats and ecto blobs (H3, H3b)" % tag)
			pests_seen[run.pest] = true
			var value := 0
			var pests := 0
			var acolytes := [0, 0, 0]
			var books := [0, 0, 0]
			for o in run.objectives:
				value += int(o["pay"])
				check(str(o["kind"]) in ["pest", "acolyte", "grimoire"], "%s: only pest, acolyte and grimoire objectives (%s)" % [tag, o["kind"]])
				if str(o["kind"]) == "pest":
					pests += 1
				elif str(o["kind"]) == "grimoire":
					books[int(o["floor"]) - 1] += 1
					eq(int(o["pay"]), run.grimoire_pay, "%s: the grimoire pays the grimoire rate" % tag)
				else:
					acolytes[int(o["floor"]) - 1] += 1
					eq(int(o["pay"]), run.acolyte_pay, "%s: an acolyte pays the acolyte rate" % tag)
			eq(pests, ContractRun.FLOOR_COUNT, "%s: a pest objective per floor" % tag)
			# H6: the grimoire on the last floor (where a hellgate contract's origin gate is), paid as the origin gate
			eq(books, [0, 0, 1], "%s: the grimoire objective on the last floor" % tag)
			check(run.has_grimoire() and run.grimoire_pay >= ContractRun.GRIMOIRE_PAY * 0.8, "%s: the grimoire pays (%d)" % [tag, run.grimoire_pay])
			check(run.card_lines().any(func(ln: Dictionary) -> bool: return str(ln["label"]) == "Shut the grimoire" and int(ln["pay"]) == run.grimoire_pay), "%s: the card lists the grimoire" % tag)
			# ... and the pest at the standard rate (H1's DEAD_PEST_BONUS is retired)
			eq(run.pest_pay, ClientArchetype.round_pay(ContractRun.PEST_PAY * float(ClientArchetype.get_data(id)["pay_scale"])), "%s: the pest at the standard rate" % tag)
			# H4: the acolytes of floors 1-2, two a procession (floor 2 two processions on a harder job), none on the last floor
			eq(acolytes, [2, 4 if run.difficulty >= ContractRun.PROCESSION_HARD else 2, 0], "%s: the acolyte objectives per floor" % tag)
			check(run.acolyte_pay >= ContractRun.ACOLYTE_PAY * 0.8, "%s: an acolyte pays (%d)" % [tag, run.acolyte_pay])
			check(run.card_lines().any(func(ln: Dictionary) -> bool: return str(ln["label"]).contains("acolyte")), "%s: the card lists the acolytes" % tag)
			eq(value + run.total_employees() * ContractRun.EMPLOYEE_EXTRACTED, run.contract_value, "%s: the contract value" % tag)
			check(run.pest_pay > ContractRun.PEST_PAY * 0.8, "%s: the pest pays for the whole job (%d)" % [tag, run.pest_pay])
			for ln in run.card_lines():
				check(not str(ln["label"]).to_lower().contains("gate"), "%s: the card names no gate (%s)" % [tag, ln["label"]])
			var again := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			eq([again.client_name, again.story, again.floor_employees, again.contract_value], [run.client_name, run.story, run.floor_employees, run.contract_value],
					"%s: deterministic" % tag)
	check(pests_seen.has("grunt") and pests_seen.has("zombie"), "haunted contracts name skeletons or zombies as the pest (%s)" % str(pests_seen.keys()))
	var gate_run := ContractRun.make("prepper", 3, 0.5)
	check(gate_run.has_gates() and gate_run.family == ClientArchetype.FAMILY_GATE and gate_run.total_gates() > 0, "a hellgate client keeps its gates")
	check(gate_run.total_acolytes() == 0 and gate_run.acolyte_pay == 0, "... and has no acolytes (H4)")
	check(not gate_run.has_grimoire() and gate_run.grimoire_pay == 0, "... nor a grimoire (H6)")
	check(not gate_run.objectives.any(func(o: Dictionary) -> bool: return str(o["kind"]) == "grimoire"), "... nor its objective")
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


## H3b: a floor's crypt rats stand in clumps of 5-6 (a pick), at most one clump a room's pack (fewer when the room's density
## cap cut it short).
func _rat_clumps(tag: String, site: SiteBuilder.Site) -> void:
	var rats: Array[Monster] = []
	for m in site.monsters:
		if m.kind == "crypt_rat":
			rats.append(m)
	var left := rats.duplicate()
	while not left.is_empty():
		var clump: Array[Monster] = [left.pop_back()]
		var grew := true
		while grew:
			grew = false
			for r in left.duplicate():
				for c in clump:
					if GameWorld.flat_distance(r.global_position, c.global_position) < 2.6:
						clump.append(r)
						left.erase(r)
						grew = true
						break
		check(clump.size() <= 6, "%s: a rat clump is at most 6 (%d)" % [tag, clump.size()])


## H5: the floor's ghosts in their hosts (HauntPlanner): the floor's ghosts, each in a possessed host from the start; a dormant
## host or more besides; armour only in the mansion's house rooms (the church's and the crypt's are bones); never in the start,
## arrival or exit room; against a wall, apart from each other.
func _haunts(tag: String, run: ContractRun, f: int, map: HexMap, plan: SitePlan, site: SiteBuilder.Site) -> void:
	var want := HauntPlanner.wisps_on(run, f)
	check(want > 0, "%s: a haunted floor has ghosts" % tag)
	eq(site.hosts.size(), plan.haunts.size(), "%s: every planned host spawned" % tag)
	check(plan.haunts.size() > want, "%s: more hosts than ghosts (%d for %d)" % [tag, plan.haunts.size(), want])
	eq(site.wisps.size(), mini(want, plan.haunts.size()), "%s: the floor's ghosts (%d)" % [tag, want])
	var crypt: Array = map.crypt.get("rooms", [])
	var possessed := 0
	for i in plan.haunts.size():
		var rec: Dictionary = plan.haunts[i]
		var h := site.hosts[i]
		eq(h.kind, str(rec["kind"]), "%s: host %d is its planned kind" % [tag, i])
		if str(rec["kind"]) == "armour":
			check(run.site_type == "mansion" and not crypt.has(str(rec["room"])), "%s: armour only in the mansion's house rooms" % tag)
		check(str(rec["room"]) != plan.start_room and str(rec["room"]) != plan.exit_room and str(rec["room"]) != SiteBuilder.arrival_room(plan), "%s: no host in the start, arrival or exit room" % tag)
		var walls := 0
		for d in Hex.DIRS:
			var nb := map.get_cell((rec["cell"] as Vector2i) + d)
			if nb == null or nb.type == HexMap.Tile.WALL or nb.wall_mask != 0:
				walls += 1
		var face := map.nearest_wall(h.global_position, 2.0)
		check(walls >= 2 and not face.is_empty() and float(face["dist"]) < 1.3, "%s: host %d against a wall (%s)" % [tag, i, str(face.get("dist", -1.0))])
		check(map.is_walkable_cell(h.current_cell()), "%s: host %d on a full floor cell" % [tag, i])
		for j in range(i + 1, plan.haunts.size()):
			check(Hex.distance(rec["cell"], plan.haunts[j]["cell"]) >= HauntPlanner.APART, "%s: hosts %d and %d apart" % [tag, i, j])
		if bool(rec["ghost"]):
			possessed += 1
			check(h.is_possessed() and h.ghost != null and (h.ghost as Wisp).host == h, "%s: host %d has its ghost in it" % [tag, i])
		else:
			check(h.is_dormant() and not h.is_in_group("monsters"), "%s: host %d is dormant" % [tag, i])
	eq(possessed, site.wisps.size(), "%s: one possessed host a ghost" % tag)
	for w in site.wisps:
		check(not w.visible and not w.is_in_group("actors"), "%s: a ghost in its host is hidden, out of every query" % tag)


## One floor of a haunted contract, built as the game builds it (test_golden_floor's way), twice.
func _check_floor(id: String, s: int, f: int) -> void:
	var tag := "%s/%d floor %d" % [id, s, f]
	var a := _build(id, s, f)
	var run: ContractRun = a["run"]
	var map: HexMap = a["map"]
	var plan: SitePlan = a["plan"]
	var site: SiteBuilder.Site = a["site"]
	var site_type := run.site_type
	# no hellgate, no sewer or lava section (a crypt may roll: H2, test_crypt_gen)
	check(plan.gates.is_empty() and site.gates.is_empty() and site.origin_gate == null and site.beasts.is_empty(), "%s: no hellgate" % tag)
	# H6: the grimoire on the last floor only, in the story's room, where the origin gate would stand (its cell kept clear)
	if f == ContractRun.FLOOR_COUNT:
		check(not plan.grimoire.is_empty() and site.grimoire != null and not site.grimoire.dead, "%s: the grimoire" % tag)
		if site.grimoire != null:
			eq(str(plan.grimoire["room"]), plan.origin_room, "%s: the grimoire in the story's room" % tag)
			eq(site.grimoire.current_cell(), plan.grimoire["cell"] as Vector2i, "%s: standing on its planned cell" % tag)
			check(not site.grimoire.is_active() and site.grimoire.book != null and site.grimoire.book.state == "dormant", "%s: the grimoire dormant at the start" % tag)
			check(plan.blocked.has(plan.grimoire["cell"]) and plan.gate_cells().has(plan.grimoire["cell"]), "%s: its cell kept clear (no monster or prop placed on it)" % tag)
			for m in site.monsters:
				check(Hex.distance(m.current_cell(), plan.grimoire["cell"]) > 2, "%s: no pack monster on the altar (%s)" % [tag, m.kind])
	else:
		check(plan.grimoire.is_empty() and site.grimoire == null, "%s: no grimoire before the last floor" % tag)
	check(map.sewer.is_empty() and map.cave.is_empty(), "%s: no sewer cluster or lava cave" % tag)
	check(site.scouts.is_empty() and site.sharks.is_empty() and site.gators.is_empty(), "%s: no goblin scout, shark or gator" % tag)
	# only the dead family (skeletons and zombies, H3; crypt rats and ecto blobs, H3b), and enough of the pest to exterminate
	check(site.monsters.size() > 0, "%s: monsters spawned (%d)" % [tag, site.monsters.size()])
	var kinds := {}
	for m in site.monsters:
		kinds[m.kind] = int(kinds.get(m.kind, 0)) + 1
	for k: String in kinds:
		check(k in ["grunt", "zombie", "crypt_rat", "ecto_blob"], "%s: the dead family only (%s)" % [tag, k])
	# (H3: a zombie costs 3 to a skeleton's 2, so a mixed floor holds fewer than H1's skeleton-only one: measured 12-17 on
	# floors 1-2 and 26-35 on floor 3 here, against 17-21 and 34-42 with skeletons only. H3b: a rat pick is 5-6 rats for 6
	# points at weight 1, so a floor with rats holds more, lighter bodies: measured 12-22 on floors 1-2 and 30-40 on floor 3)
	# (H4: the processions' zombies are in `monsters` and their acolytes beside it, `acolytes`: the total holds both)
	# (H6: the grimoire's cell is kept clear as the origin gate's, which moves floor 3's pack draws: parish 11 floor 3 holds 41)
	check(site.monsters.size() + site.acolytes.size() <= 42, "%s: a sane total (%d and %d acolytes: %s)" % [tag, site.monsters.size(), site.acolytes.size(), str(kinds)])
	# H4: the floor's processions, each an acolyte, its four zombies and a rear acolyte, on a route of 2-3 rooms
	eq(plan.processions.size(), run.floor_processions[f - 1], "%s: the contract's processions" % tag)
	eq(site.processions.size(), plan.processions.size(), "%s: each spawned" % tag)
	eq(site.acolytes.size(), run.acolytes_on(f), "%s: two acolytes a procession" % tag)
	for pr in site.processions:
		eq(pr.acolytes.size(), Procession.ACOLYTES, "%s: a leader and a rear acolyte" % tag)
		eq(pr.zombies.size(), Procession.FILE, "%s: its file of zombies" % tag)
		check(pr.route.size() >= 2 and pr.route.size() <= ProcessionPlanner.ROUTE_ROOMS, "%s: a route of rooms (%s)" % [tag, ", ".join(pr.rooms)])
		check(not pr.rooms.has(plan.start_room) and not pr.rooms.has(plan.exit_room) and not pr.rooms.has(SiteBuilder.arrival_room(plan)), "%s: never through the start, arrival or exit room" % tag)
		check(pr.acolytes[0].is_in_group("monsters") and pr.acolytes[0] is Acolyte, "%s: its acolytes are monsters" % tag)
		var lead := pr.acolytes[0].global_position
		for i in pr.zombies.size():
			var want: Vector3 = pr.trail.point(pr.trail.head_arc() - Procession.GAP * float(i + 1))["pos"]
			check(GameWorld.flat_distance(pr.zombies[i].global_position, want) < 0.05, "%s: zombie %d stands in file behind the leader" % [tag, i])
		var back: Vector3 = pr.trail.point(pr.trail.head_arc() - Procession.GAP * float(Procession.FILE + 1))["pos"]
		check(GameWorld.flat_distance(pr.acolytes[1].global_position, back) < 0.05 and lead.distance_to(back) > Procession.GAP, "%s: the rear acolyte at the back" % tag)
	_haunts(tag, run, f, map, plan, site)
	_rat_clumps(tag, site)
	print("  %s: %d monsters %s, %d acolytes in %d processions, pest %s" % [tag, site.monsters.size(), str(kinds), site.acolytes.size(), site.processions.size(), run.pest])
	totals[tag] = kinds
	check(site.pest_spawned >= PackPlanner.PEST_MIN, "%s: at least %d to exterminate (%d)" % [tag, PackPlanner.PEST_MIN, site.pest_spawned])
	# the rooms: the haunted pool, the service entrance; the origin room on the last floor
	var pool := RoomThemeDefs.pool(site_type)
	var crypt_rooms: Array = map.crypt.get("rooms", [])   # (a crypt, H2: its rooms are crypt rooms, test_crypt_gen's)
	var crypt_themes: Array = RoomThemeDefs.CRYPT[CryptCluster.set_for(site_type)]
	var themes := {}
	for rt: String in plan.room_themes:
		var t := str(plan.room_themes[rt])
		themes[t] = true
		if crypt_rooms.has(rt):
			check(crypt_themes.has(t), "%s: %s in the crypt is a crypt room" % [tag, t])
			continue
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
		if str(pr["kind"]) == CryptPlanner.tomb_kind(CryptCluster.set_for(site_type)) and crypt_rooms.has(str(pr["room"])):
			continue   # (the crypt's sarcophagi: H2)
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

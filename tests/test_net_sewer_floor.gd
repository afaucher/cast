extends NetGameTest
## Sewer phase 2 (docs/design/sewer-concept.md, "Phase 2 as built"), three processes, `off` and `coast`: a crew's floor gets
## the sewer cluster a solo run of that seed gets (SewerCluster.NETWORKED), and every machine builds the same one.
## Floor 2 of the seed-7 job (offer 2) has a four-room cluster: two gators, an electrical panel with its live wire and a goo
## imp pack.
## - the floor: the checksums (map with the sewer record, plan, contract, the spawn table with each gator's spawn data) match
##   on all three; every machine has the cluster, the same rooms, the same gators (where they start, their home region, bask
##   spots and seed), the same live wires (where each cable lands) and the same goo imp pack;
## - the gators and the goo imps are the host's: puppets on the clients, the gators standing where the host has them after a
##   short watch;
## - the cluster's props are the host's too: c1 smashes a sump pump (a request) and the host bills it once ($3,500 to c1's
##   hero); the cluster's oil drum, when the floor has one, c1 sets off (a request: the host lights it, every machine runs the
##   blast) and the host bills it once; every machine shows them broken and every Ledger is the host's line for line;
## - nothing tripped the OWNER-write guard on any machine.

const PEERS := 3
const SEED := 7
const CONTRACT := 1
const FLOOR := 2
const WATCH := 2.5


func run_host() -> void:
	if not await enter_floor(SEED, CONTRACT, {"floor": FLOOR}):
		return
	await wait_sync()
	var mine := await describe()
	check(not (mine["rooms"] as Array).is_empty(), "the host's floor %d has a sewer cluster (%s)" % [FLOOR, str(mine["rooms"])])
	eq((mine["gators"] as Array).size(), 2, "... with two gators (a cluster of four rooms)")
	check(int(mine["wires"].size()) >= 1, "... and a live wire on its panel")
	check(int(mine["goo"]) >= 3, "... and a goo imp pack (%d)" % int(mine["goo"]))
	check(bool(mine["host_runs"]), "the host runs its gators")
	eq(flow().desyncs, [], "the host saw no desync")
	check(await wait_reports("floor", 2, 30.0), "both clients report their floor")
	for p in peers_with("floor"):
		var r: Dictionary = reported(p, "floor")
		for part in ["all", "map", "plan", "run", "spawn"]:
			eq(str(r[part]), str(mine[part]), "peer %d: the %s checksum matches the host's" % [p, part])
		eq(str(r["sewer"]), str(mine["sewer"]), "peer %d: the same sewer record" % p)
		eq(r["rooms"], mine["rooms"], "peer %d: the same cluster rooms" % p)
		eq(r["spawn_data"], mine["spawn_data"], "peer %d: the same gators (spawn data)" % p)
		eq(r["wires"], mine["wires"], "peer %d: the same live wires" % p)
		eq(int(r["goo"]), int(mine["goo"]), "peer %d: the same goo imp pack" % p)
		check(bool(r["puppets"]), "peer %d shows the host's gators as puppets" % p)
		eq(int(r["goo_puppets"]), int(mine["goo"]), "peer %d shows the goo imp pack as puppets" % p)
		var gh: Array = mine["gators"]
		var gc: Array = r["gators"]
		var off := 0
		for i in mini(gh.size(), gc.size()):
			if Vector2((gh[i] as Vector3).x, (gh[i] as Vector3).z).distance_to(Vector2((gc[i] as Vector3).x, (gc[i] as Vector3).z)) > 0.6:
				off += 1
		eq(off, 0, "peer %d: after %.1f s every gator stands where the host has it" % [p, WATCH])
		eq(int(r["guard"]), 0, "peer %d: the OWNER-write guard never fired" % p)
	# The cluster's props: a sump pump and (if there is one) the oil drum, set off by c1.
	var site: SiteBuilder.Site = game.get("_site")
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	var c1 := peer_named("c1")
	var smashed: Array[PricedProp] = []
	for kind in ["sump_pump", "oil_drum"]:
		var prop: PricedProp = null
		for pp in site.props + site.hazards:
			if pp is PricedProp and (pp as PricedProp).kind == kind and not (pp as PricedProp).dead and _in_cluster(pp as PricedProp):
				prop = pp
				break
		if prop == null:
			check(kind == "oil_drum", "the cluster has a %s" % kind)
			continue
		var lines_before := Ledger.lines.size()
		command(c1, "smash", {"id": NetFloor.id_of(prop)})
		check(await until(func() -> bool: return prop.dead, 6.0), "c1's hit broke the %s on the host" % kind)
		await sleep(0.4)
		var bills := 0
		for line: Dictionary in Ledger.lines.slice(lines_before):
			if str(line["label"]) == prop.display_name:
				bills += 1
				eq(int(line["amount"]), prop.price, "the %s bills its price" % kind)
				eq(str(line["who"]), hero_at(2).display_name, "... to c1's hero")
		eq(bills, 1, "the %s is billed once" % kind)
		smashed.append(prop)
	var ids: Array = smashed.map(func(pp: PricedProp) -> int: return NetFloor.id_of(pp))
	print("[sewer] c1 smashed: %s; Ledger %s" % [str(smashed.map(func(pp: PricedProp) -> String: return pp.kind)), ledger_text()])
	for p in client_peers():
		command(p, "after", {"ids": ids})
	check(await wait_reports("after", 2, 15.0), "both clients report the props")
	for p in peers_with("after"):
		var ar: Dictionary = reported(p, "after")
		check(bool(ar["broken"]), "peer %d shows them broken" % p)
		eq(str(ar["ledger"]), ledger_text(), "peer %d's Ledger is the host's, line for line" % p)
		eq(int(ar["guard"]), 0, "peer %d: the OWNER-write guard never fired" % p)
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	for p in client_peers():
		command(p, "end")
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	if not await enter_floor(SEED, CONTRACT, {"floor": FLOOR}):
		return
	await wait_sync()
	var r := await describe()
	r["guard"] = Net.guard_hits.size()
	var site: SiteBuilder.Site = game.get("_site")
	var goo_puppets := 0
	for a in NetFloor.actors_under(GameWorld.root):
		if a is Monster and MonsterDefs.habitat(str((a as Monster).kind)) == "sewer" and Net.is_puppet(a):
			goo_puppets += 1
	r["goo_puppets"] = goo_puppets
	report("floor", r)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"smash":
				var prop := NetRegistry.node(int(cmd["id"])) as PricedProp
				if prop != null:
					prop.apply_damage(999.0, my_hero())   # (a copy: obj.req hit; the host breaks it, or lights the drum)
			"after":
				var broken := true
				for id: int in cmd["ids"]:
					var prop := NetRegistry.node(id) as PricedProp
					await until(func() -> bool: return prop == null or prop.dead, 6.0)
					broken = broken and (prop == null or prop.dead)
				await sleep(0.4)
				report("after", {"broken": broken, "ledger": ledger_text(), "guard": Net.guard_hits.size()})
			_:
				running = false


## This machine's floor after WATCH seconds: its checksum, the cluster, the gators, the wires, the goo pack.
func describe() -> Dictionary:
	await sleep(WATCH)
	var site: SiteBuilder.Site = game.get("_site")
	var map := game.get("map") as HexMap
	var sums: Dictionary = flow().local_sums
	var gators: Array = []
	var spawn_data: Array = []
	var puppets := true
	var host_runs := true
	for g: Gator in site.gators:
		gators.append(g.global_position)
		spawn_data.append(g.net_spawn_text())
		puppets = puppets and Net.is_puppet(g)
		host_runs = host_runs and Net.simulates(g) and g.is_physics_processing()
	var wires: Array = []
	for w: LiveWire in site.wires:
		wires.append([w.drop_cell, NetFloor.id_of(w.panel)])
	var goo := 0
	for a in NetFloor.actors_under(GameWorld.root):
		if a is Monster and MonsterDefs.habitat(str((a as Monster).kind)) == "sewer":
			goo += 1
	return {"all": sums["all"], "map": sums["map"], "plan": sums["plan"], "run": sums["run"], "spawn": sums["spawn"],
		"sewer": NetFloor.canon(map.sewer).sha256_text(), "rooms": (map.sewer.get("rooms", []) as Array).duplicate(),
		"gators": gators, "spawn_data": spawn_data, "wires": wires, "goo": goo,
		"puppets": puppets and not gators.is_empty(), "host_runs": host_runs and not gators.is_empty()}


## A prop by the cluster's water (within 4 cells of it): the sewer's own, not the floor's.
func _in_cluster(p: PricedProp) -> bool:
	var map := game.get("map") as HexMap
	for n in Hex.range_cells(p.current_cell(), 4):
		if map.is_pool_cell(n) and map.water_at(Hex.to_world(n, float(map.get_cell(n).level))):
			return true
	return false

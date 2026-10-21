extends MonsterTestBase
## Dispatch's sewer calls (SewerCalls, NoteCopy.SEWER_CALLS; docs/design/sewer-concept.md, "Polish as built") on a generated
## sewer cluster (contract seed 5, floor 2: the prepper's bunker, a panel and two pumps):
##   - nothing is called while the crew is up top and no gator is near;
##   - a hero in a room of the cluster: "You're on the service level...", once (walking out and back does not repeat it);
##   - this machine's hero within SewerCalls.SIGHT of a gator: "That's the client's gator...", once;
##   - a gator killed: "Gator's down...", once;
##   - a panel broken with a hero wading in reach: when the cable lands and shocks, "That was the panel...", once;
##   - with a banner, a call waits while the banner holds another line, then shows; a call that waited past STALE is dropped;
##   - a floor with no cluster, gator or wire gets no SewerCalls at all.

const SEED := 5
const FLOOR := 2


func setup() -> void:
	timeout_sec = 120.0
	Monster.use_proto_visuals = true
	var run := ContractBoard.run_for_seed(SEED)
	var map := DungeonGen.for_run(run, FLOOR)
	check(not map.sewer.is_empty(), "seed %d floor %d has a sewer cluster" % [SEED, FLOOR])
	if map.sewer.is_empty():
		finish()
		return
	new_world(map)
	Ledger.begin_contract(1000000)
	var plan := SiteBuilder.plan(map, run, FLOOR, PricedProp.catalog(run.site_type))
	var site := SiteBuilder.spawn(map, run, plan)
	check(not site.gators.is_empty() and not site.wires.is_empty(), "it has a gator and a live wire")
	var hero := add_hero(plan.start, float(map.get_cell(plan.start).level))
	hero.snap_to_ground()
	hero.set_modifier("test_ward", 0.0, 999.0)
	var crew: Array = [hero]
	var calls := SewerCalls.new()
	calls.setup(map, site.wires, func() -> Array: return crew, func() -> Actor: return hero, null, null)
	add_child(calls)
	calls.set_process(false)   # (ticked by hand)
	# up top
	calls.tick()
	eq(calls.shown.size(), 0, "nothing is called while the crew is up top")
	# down the stair
	var st: Dictionary = map.sewer["stair"]
	var foot := _dry_cell_near(map, st["door"], str(st["room"]), 2)
	_stand(hero, foot)
	await frames(2)
	calls.tick()
	eq(calls.shown, [NoteCopy.SEWER_DOWN] as Array[String], "a hero in the cluster: the service level call")
	_stand(hero, plan.start)
	calls.tick()
	_stand(hero, foot)
	calls.tick()
	eq(calls.shown.count(NoteCopy.SEWER_DOWN), 1, "once a floor")
	# the gator
	var g: Gator = site.gators[0]
	_stand(hero, _dry_cell_near(map, g.current_cell(), "", 6))
	await frames(2)
	calls.tick()
	check(calls.shown.has(NoteCopy.GATOR_SEEN), "a gator within sight: the gator call")
	g.apply_damage(9999.0, hero)
	check(g.dead, "the gator is killed")
	calls.tick()
	check(calls.shown.has(NoteCopy.GATOR_BILLED), "a gator killed: the billed call")
	for other: Gator in site.gators:
		if not other.dead:
			other.apply_damage(9999.0, hero)
	calls.tick()
	eq(calls.shown.count(NoteCopy.GATOR_BILLED), 1, "once a floor, however many gators die")
	eq(calls.shown.count(NoteCopy.GATOR_SEEN), 1, "and the sighting once")
	# the live wire, a hero wading in its reach
	var w: LiveWire = site.wires[0]
	var wet := _wet_cell_near(map, w.drop_cell, 3)
	check(wet.x < 1 << 19, "a wading spot by the cable's drop")
	_stand(hero, wet)
	await frames(4)
	check(map.water_at(hero.global_position), "the hero wades")
	w.panel.apply_damage(5.0, hero)
	check(w.panel.dead, "the panel breaks")
	var shocked := await wait_until(func() -> bool: return w.shocks >= 1, 90)
	check(shocked, "the cable lands and shocks")
	calls.tick()
	check(calls.shown.has(NoteCopy.WIRE_SHOCK) and not calls.shown.has(NoteCopy.WIRE_LIVE), "a hero shocked: the shock call (%s)" % str(calls.shown))
	calls.tick()
	eq(calls.shown.count(NoteCopy.WIRE_SHOCK), 1, "once")
	calls.free()
	_check_banner_queue(map, site)
	_check_none()
	Monster.use_proto_visuals = false
	world.free()
	world = null
	finish()


## A call waits for the banner to be free, and is dropped past STALE.
func _check_banner_queue(map: HexMap, site: SiteBuilder.Site) -> void:
	var banner := DispatchBanner.new()
	add_child(banner)
	var calls := SewerCalls.new()
	calls.setup(map, [], func() -> Array: return [], func() -> Actor: return null, null, banner)
	add_child(calls)
	calls.set_process(false)
	banner.show_line("The floor's own line.", 7.0)
	calls.call_line(NoteCopy.SEWER_DOWN)
	calls.tick()
	eq(calls.shown.size(), 0, "a call waits while the banner holds another line")
	eq(banner.line, "The floor's own line.", "the banner keeps its line")
	banner.hold = 0.0
	calls.tick()
	eq(calls.shown, [NoteCopy.SEWER_DOWN] as Array[String], "then it shows")
	eq(banner.line, NoteCopy.SEWER_DOWN, "on the banner")
	banner.hold = 5.0
	calls.call_line(NoteCopy.GATOR_SEEN)
	calls._queue[0][1] = GameWorld.time - SewerCalls.STALE - 1.0
	banner.hold = 0.0
	calls.tick()
	check(not calls.shown.has(NoteCopy.GATOR_SEEN), "a call that waited past STALE is dropped")
	calls.free()
	banner.free()


func _check_none() -> void:
	var m := flat_map(6)
	new_world(m)
	var calls := SewerCalls.attach(self, m, [], func() -> Array: return [], func() -> Actor: return null, null, null)
	check(calls == null, "a floor with no cluster, gator or wire gets no sewer calls")


func _stand(a: Actor, c: Vector2i) -> void:
	a.global_position = Hex.to_world(c, float(GameWorld.map.get_cell(c).level))
	a.snap_to_ground()


## A dry walkable floor cell within r of c (in room `tag`, or any).
func _dry_cell_near(map: HexMap, c: Vector2i, tag: String, r: int) -> Vector2i:
	for d in range(0, r + 1):
		var ring := [c] if d == 0 else Hex.ring(c, d)
		for n: Vector2i in ring:
			var cell: HexMap.Cell = map.get_cell(n)
			if cell == null or cell.type != HexMap.Tile.FLOOR or not map.is_walkable_cell(n) or map.is_pool_cell(n):
				continue
			if tag != "" and cell.tag != tag:
				continue
			if d >= 2 or tag != "":
				return n
	return Vector2i(1 << 20, 0)


## A walkable water cell within r of c.
func _wet_cell_near(map: HexMap, c: Vector2i, r: int) -> Vector2i:
	for d in range(0, r + 1):
		var ring := [c] if d == 0 else Hex.ring(c, d)
		for n: Vector2i in ring:
			if map.is_walkable_cell(n) and map.is_pool_cell(n) and map.water_at(Hex.to_world(n, float(map.get_cell(n).level))):
				return n
	return Vector2i(1 << 20, 0)

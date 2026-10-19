extends NetGameTest
## Monster awareness step 2 online (two processes, `off` and `coast`):
## - THE GOBLIN'S ALARM: the host's scout spots the host's hero; the client sees his phases ("!", the light, the fuse,
##   hiding: world.scout) in order, the volley (a FireworksFx built from world.fireworks) and the monsters the host's
##   alarm woke walking in on ALERT (their streamed state);
## - AN ARCHER'S PRACTICE SHOT: the host's archer shoots a priced prop; the client plays the arrow (the puppet's visual),
##   the prop's dent arrives once (8 HP, from the host: obj.hurt), the client sends no hit request of its own (the visual
##   never decides a hit on a host-owned prop) and its own hero is untouched.

const PEERS := 2
const SEED := 21

var _phases: Array = []
var _volleys := 0
var _arrows := 0
var _scout: Node = null


func run_host() -> void:
	if not await enter_floor(SEED, 1, {"spawn_near": "archer,1", "idle_monsters": true}):
		return
	my_hero().set_modifier("test_ward", 0.0, 999.0)
	hero_at(3).set_modifier("test_ward", 0.0, 999.0)
	if not await wait_sync():
		return
	var brain := hero_at(3).get_node_or_null("AllyBrain")
	if brain != null:
		brain.set_physics_process(false)
	check(await wait_reports("ready", 1, 30.0), "the client is on the floor")
	var c1: int = client_peers()[0]
	var site: SiteBuilder.Site = game.get("_site")

	# 1. The goblin's alarm.
	if check(not site.scouts.is_empty(), "the floor has a goblin scout"):
		var g = site.scouts[0]
		var pack := _resting_far_monster(25.0)
		if check(pack != null, "a resting pack far from the crew"):
			g.global_position = _walkable_near(pack.global_position, 2)
			g.set_spawn_facing(Vector3.FORWARD)
			await sleep(0.5)
			var before := _states()
			command(c1, "goblin", {"id": NetFloor.id_of(g)})
			await sleep(0.4)
			g.aggro(my_hero())
			await until(func() -> bool: return int(g.volleys) > 0 or g.dead, 8.0)
			eq(int(g.volleys), 1, "the scout's volley went up on the host")
			await sleep(0.3)
			var woken: Array = []
			var after := _states()
			for id: int in after:
				if int(after[id]) == Monster.State.ALERT and int(before.get(id, -1)) != Monster.State.ALERT:
					woken.append(id)
			check(woken.size() >= 1, "the alarm woke monsters on the host (%d)" % woken.size())
			command(c1, "woken", {"ids": woken})
			check(await wait_reports("goblin", 1, 20.0), "the client reports the goblin")
			var r: Dictionary = reported(c1, "goblin")
			var seen: Array = r["phases"]
			print("[step2] the client saw the scout's phases %s, %d volley(s), %d of %d woken monsters on ALERT" % [str(seen), int(r["volleys"]), int(r["alert"]), woken.size()])
			var P: Dictionary = g.Phase
			var order := [P["TELL"], P["LIGHT"], P["FUSE"], P["HIDE"]]
			var at := -1
			var in_order := true
			for p: int in order:
				var i := seen.find(p)
				if i <= at:
					in_order = false
				at = i
			check(in_order, "the client saw \"!\", the light, the fuse and the hiding in order (%s)" % str(seen))
			eq(int(r["volleys"]), 1, "the client drew the volley once")
			eq(int(r["alert"]), woken.size(), "every monster the host's alarm woke walks in on ALERT on the client")

	# 2. An archer's practice shot.
	var dev: Array = game.get("_dev_monsters")
	var archer = dev[0] if not dev.is_empty() else null
	var pick := _prop_and_spot(site)
	if check(archer != null and not pick.is_empty(), "an archer and a prop to practise on"):
		var prop: PricedProp = pick[0]
		archer.global_position = pick[1]
		archer.face_point(prop.global_position)
		await sleep(0.6)
		var hp0 := prop.hp
		command(c1, "practice", {"archer": NetFloor.id_of(archer), "prop": NetFloor.id_of(prop)})
		await sleep(0.4)
		var shot = archer.practice_shot(prop)
		check(shot != null, "the host's archer looses a practice arrow")
		await sleep(1.5)
		near(prop.hp, hp0 - 8.0, 0.01, "the host's prop took the arrow once (8)")
		check(await wait_reports("practice", 1, 20.0), "the client reports the practice shot")
		var pr: Dictionary = reported(c1, "practice")
		print("[step2] practice on the client: %d arrow(s) shown, prop %.1f -> %.1f (%d dents), %d hit requests sent, own hero %.1f -> %.1f" % [
			int(pr["arrows"]), float(pr["hp0"]), float(pr["hp1"]), int(pr["dents"]), int(pr["requests"]), float(pr["me0"]), float(pr["me1"])])
		check(int(pr["arrows"]) >= 1, "the client played the arrow")
		near(float(pr["hp1"]), prop.hp, 0.05, "the client's prop shows the host's dent")
		eq(int(pr["dents"]), 1, "... exactly one dent (no double hit)")
		eq(int(pr["requests"]), 0, "the client's visual arrow sent no hit request")
		near(float(pr["me1"]), float(pr["me0"]), 0.001, "and its own hero was not hit")
	command(c1, "end")
	check(await wait_done(1, 30.0), "the client is done")


func run_client() -> void:
	if not await enter_floor(SEED, 1, {"spawn_near": "archer,1", "idle_monsters": true}):
		return
	if not await wait_sync():
		return
	await until(func() -> bool: return Session.world.active, 10.0)
	report("ready", {})
	GameWorld.root.child_entered_tree.connect(_on_child)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"goblin":
				_scout = NetRegistry.node(int(cmd["id"]))
				_phases = []
				_volleys = 0
			"woken":
				var woken: Array = cmd["ids"]
				await sleep(0.6)   # (the host's ALERT reaches this screen with the stream)
				var alert := 0
				for id: Variant in woken:
					var m := NetRegistry.node(int(id)) as Monster
					if m != null and not m.dead and (m.state == Monster.State.ALERT or m.state == Monster.State.SEARCH or m.state == Monster.State.CHASE):
						alert += 1
				await sleep(1.0)   # (the hiding phase)
				report("goblin", {"phases": _phases, "volleys": _volleys, "alert": alert})
				_scout = null
			"practice":
				var prop := NetRegistry.node(int(cmd["prop"])) as PricedProp
				var me := my_hero()
				var hp0 := prop.hp if prop != null else -1.0
				var me0 := me.hp
				var req0 := int(Session.objects.stats.get("hits_out", 0))
				_arrows = 0
				var dents := 0
				var last := hp0
				var t1 := wall()
				while wall() - t1 < 3.0:
					await get_tree().process_frame
					if prop != null and absf(prop.hp - last) > 0.01:
						dents += 1
						last = prop.hp
				report("practice", {"arrows": _arrows, "hp0": hp0, "hp1": prop.hp if prop != null else -1.0, "dents": dents,
					"requests": int(Session.objects.stats.get("hits_out", 0)) - req0, "me0": me0, "me1": me.hp})
			_:
				running = false


func _process(delta: float) -> void:
	super._process(delta)
	if _scout != null and is_instance_valid(_scout):
		var p := int(_scout.get("scout_phase"))
		if _phases.is_empty() or int(_phases.back()) != p:
			_phases.append(p)


func _on_child(n: Node) -> void:
	if n is FireworksFx:
		_volleys += 1
	elif n is Projectile:
		_arrows += 1


## Every monster's state now (host): id -> state.
func _states() -> Dictionary:
	var out := {}
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m != null and not m.dead and m.kind != "goblin":
			out[id] = m.state
	return out


## A resting pack monster at least `far` from every hero, with another monster near it (host).
func _resting_far_monster(far: float) -> Monster:
	var best: Monster = null
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if m == null or m.dead or m.kind == "goblin" or m.state != Monster.State.IDLE or m.is_frozen():
			continue
		var ok := true
		for seat in [1, 2, 3]:
			var h := hero_at(seat)
			if h != null and GameWorld.flat_distance(h.global_position, m.global_position) < far:
				ok = false
		if ok:
			best = m
			break
	return best


func _walkable_near(p: Vector3, ring: int) -> Vector3:
	var map: HexMap = game.get("map")
	var here := Hex.from_world(p)
	for r in range(ring, ring + 3):
		for c in Hex.ring(here, r):
			if map.is_walkable_cell(c):
				return Hex.to_world(c, float(map.get_cell(c).level))
	return p


## A priced prop and a walkable spot 4-7 units in front of it with a clear flat shot, away from the crew (host).
func _prop_and_spot(site: SiteBuilder.Site) -> Array:
	var map: HexMap = game.get("map")
	for pr in site.props:
		var prop := pr as PricedProp
		if prop == null or prop.dead or prop.hp <= 10.0:
			continue
		var near_crew := false
		for seat in [1, 2, 3]:
			var h := hero_at(seat)
			if h != null and GameWorld.flat_distance(h.global_position, prop.global_position) < 10.0:
				near_crew = true
		if near_crew:
			continue
		for c in Hex.range_cells(Hex.from_world(prop.global_position), 4):
			var d := Hex.distance(c, Hex.from_world(prop.global_position))
			if d < 3 or not map.is_walkable_cell(c):
				continue
			var at := Hex.to_world(c, float(map.get_cell(c).level))
			if absf(at.y - prop.global_position.y) > 0.4:
				continue
			var from := at + Vector3.UP * 0.9
			var to := Vector3(prop.global_position.x, from.y, prop.global_position.z)
			var stop := to - (to - from).normalized() * prop.radius
			if map.line_of_sight(from, stop, 0.08):
				return [prop, at]
	return []

extends NetGameTest
## Voice orders across machines (docs/design/combat-proposals.md 1.0, "As built"), two processes, `off` and `coast`. An order
## is heard on the speaker's machine (here typed into its VoiceCaster, the console's path) and is a request to the host,
## which runs the AI seats and the employees (NetOrders: ord.req, then ord.ok to everyone).
##
## The host plays Gasket and the client Wick (the character select), so the AI seat (3) is Rebar (CrewSeats).
## - The client says "Rebar go": the host's AI Rebar walks to where the client aimed and holds there; the client sees
##   Rebar's bark and its own waypoint.
## - The client says "Rebar follow": the host's Rebar follows the CLIENT's hero (not seat 1's).
## - The client says "Hench attack" beside the henchmen (a lair floor): they fight (FIGHT on the host, the state streams to
##   the client) and punch a monster.
## - The host says "Wick go": the client (a person playing Wick) is shown a marker naming the host; nothing is ordered.
## - The party HUD's order chip (ord.st): the client sees the host's AI Rebar go FOLLOW -> GO -> HOLD -> FOLLOW, and on
##   "Rebar attack" ATTACK -> FOLLOW once the fight is over, in that order (Hero.order_state on the client's copy).
## - Nothing tripped the OWNER-write guard on either machine.

const PEERS := 2
const SEED := 1          ## board seed 1, offer 0: a supervillain lair with three henchmen on floor 1
const OFFER := 0


func _init() -> void:
	net_timeout = 120.0


func run_host() -> void:
	Session.character_id = "gasket"   # (the host picked Gasket; the client is Wick: the AI seat is Rebar)
	if Session.roster.has(1):
		Session.roster[1]["character"] = "gasket"
	if not await enter_floor(SEED, OFFER):
		return
	if not await wait_sync():
		return
	_freeze_world()
	check(await wait_reports("ready", 1, 30.0), "the client is on the floor")
	var c1 := client_peers()[0]
	var rebar := hero_at(3)
	var brain := rebar.get_node_or_null("AllyBrain") as AllyBrain if rebar != null else null
	if not check(brain != null and rebar.display_name == "Rebar", "seat 3 is the AI's Rebar (%s)" % (rebar.display_name if rebar != null else "none")):
		return
	eq(my_hero().display_name, "Gasket", "the host plays Gasket")
	eq(hero_at(2).display_name, "Wick", "the client plays Wick")
	command(c1, "chip", {"key": "chip0", "want": "follow"})
	check(await wait_reports("chip0", 1, 10.0), "the client reports Rebar's chip")
	eq(str(reported(c1, "chip0")), "follow", "the client shows the host's AI Rebar on FOLLOW (ord.st)")

	# 1. "Rebar go" from the client.
	var spot := _open_spot(rebar.global_position, 5.0)
	command(c1, "say", {"text": "Rebar go", "at": spot})
	check(await until(func() -> bool: return brain.order == "go", 5.0), "the host's Rebar takes the client's go")
	check(await until(func() -> bool: return GameWorld.flat_distance(rebar.global_position, brain.order_point) <= AllyBrain.GO_ARRIVED + 0.15, 8.0),
		"and walks to the spot (%.2f away)" % GameWorld.flat_distance(rebar.global_position, brain.order_point))
	check(GameWorld.flat_distance(brain.order_point, spot) < 1.5, "the spot is where the client aimed")
	await sleep(1.5)
	check(GameWorld.flat_distance(rebar.global_position, brain.order_point) <= AllyBrain.GO_ARRIVED + 0.3, "it holds there")
	check(await wait_reports("said1", 1, 10.0), "the client reports")
	var s1: Dictionary = reported(c1, "said1")
	check(bool(s1["bark"]), "the client sees Rebar's bark")
	check(bool(s1["waypoint"]), "the client (the speaker) sees its waypoint")
	command(c1, "chip", {"key": "chip1", "want": "hold"})
	check(await wait_reports("chip1", 1, 10.0), "the client reports Rebar's chip")
	eq(str(reported(c1, "chip1")), "hold", "the client shows Rebar holding the spot")

	# 2. "Rebar follow" from the client: Rebar follows the client's hero (not seat 1's).
	command(c1, "say", {"text": "Rebar follow", "at": Vector3.INF})
	check(await until(func() -> bool: return brain.order == "" and brain.leader == hero_at(2), 5.0), "follow: the client's hero is Rebar's leader")
	check(await until(func() -> bool: return GameWorld.flat_distance(rebar.global_position, hero_at(2).global_position) < AllyBrain.FORMATION_HEX_MAX * AllyBrain.HEX_STEP + 1.5, 8.0),
		"and Rebar follows the client (%.1f away)" % GameWorld.flat_distance(rebar.global_position, hero_at(2).global_position))

	# 3. "Hench attack" from the client, beside the henchmen; a monster stands by them.
	var hench := _henchmen()
	if check(hench.size() >= 2, "the lair floor has henchmen (%d)" % hench.size()):
		var h0 := hench[0]
		var m := _nearest_monster(h0.global_position)
		var hits := [0.0]
		var m_at := Vector3.INF
		if m != null:
			# Just outside the henchman's PANIC_RANGE: the nearest monster, and no panic. Any closer and the henchman runs from
			# it while the client's order is on the wire (most of a second on a coast link), then fights whatever monster is
			# nearest where it stopped (FIGHT takes the nearest), not this one.
			m.global_position = _open_spot(h0.global_position, Employee.PANIC_RANGE + 0.75)
			m_at = m.global_position
			m.damaged.connect(func(a: float, src: Node) -> void:
				if src is Employee:
					hits[0] += a)
		# The client stands on the henchman's far side: between the two, its hero would be in the henchman's way.
		command(c1, "goto", {"at": _open_spot(h0.global_position, 3.0, m_at)})
		check(await wait_reports("there", 1, 10.0), "the client walked over")
		check(h0.state != Employee.State.PANIC, "the henchman did not panic at the monster (%s)" % h0.state_name())
		command(c1, "say", {"text": "Hench attack", "at": Vector3.INF})
		check(await until(func() -> bool: return h0.state == Employee.State.FIGHT, 5.0), "the henchmen fight on the client's order (%s)" % h0.state_name())
		eq(Session.orders.applied.back()["refused"], 0, "henchmen do not refuse")
		check(await until(func() -> bool: return hits[0] >= Employee.HENCH_PUNCH, 8.0), "a henchman punches the monster (%.0f)" % hits[0])
		command(c1, "look", {"id": NetFloor.id_of(h0)})
		check(await wait_reports("look", 1, 10.0), "the client looked")
		eq(int(reported(c1, "look")), Employee.State.FIGHT, "the client shows the henchman fighting (the state streams)")

	# 4. "Wick go" from the host: the client (a person playing Wick) gets a marker naming the host, nothing else.
	var at := _open_spot(hero_at(2).global_position, 4.0)
	var controller := game.get("controller") as PlayerController
	controller.aim_override = at
	(game.get("voice") as VoiceCaster).inject_text("Wick go")
	controller.aim_override = Vector3.INF
	var last: Dictionary = Session.orders.applied.back()
	eq(last["w"], "wick", "the host's order was heard")
	eq(last["marks"], [2], "it names the client's Wick only (not the speaker's own)")
	command(c1, "marker")
	check(await wait_reports("marker", 1, 10.0), "the client reports")
	eq(str(reported(c1, "marker")), "host: go here", "the client is shown a marker naming the host")

	# 5. "Rebar attack" from the client: ATTACK on the host's Rebar, then FOLLOW once nothing near is fighting; the client's
	# copy shows each state in turn.
	command(c1, "say", {"text": "Rebar attack", "at": Vector3.INF})
	check(await until(func() -> bool: return brain.order == "attack", 5.0), "the host's Rebar takes the attack")
	check(await until(func() -> bool: return brain.order == "", 30.0), "and goes back to following once the fight is over")
	command(c1, "chip", {"key": "chip2", "want": "follow"})
	check(await wait_reports("chip2", 1, 10.0), "the client reports Rebar's chip")
	eq(str(reported(c1, "chip2")), "follow", "the client shows Rebar back on FOLLOW")
	command(c1, "chips")
	check(await wait_reports("chips", 1, 10.0), "the client reports every chip it showed")
	var seen: Array = reported(c1, "chips")
	var want := ["follow", "go", "hold", "follow", "attack", "follow"]
	var k := 0
	for st: Variant in seen:
		if k < want.size() and str(st) == want[k]:
			k += 1
	eq(k, want.size(), "the client's chips ran FOLLOW, GO, HOLD, FOLLOW, ATTACK, FOLLOW in order (%s)" % str(seen))
	check(int(Session.orders.stats["states"]) >= 5, "the host sent the changes as ord.st (%d)" % int(Session.orders.stats["states"]))

	command(c1, "end")
	check(await wait_reports("end", 1, 10.0), "the client is done")
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host")
	eq(int(reported(c1, "end")), 0, "... nor on the client")
	print("[orders] host: %s; applied %s" % [str(Session.orders.stats), str(Session.orders.applied)])


func run_client() -> void:
	if not await enter_floor(SEED, OFFER):
		return
	if not await wait_sync():
		return
	report("ready", true)
	var chips: Array = []   # every order state the client's copy of Rebar showed, in order
	get_tree().physics_frame.connect(func() -> void:
		var r := hero_at(3)
		if r != null and (chips.is_empty() or str(chips.back()) != r.order_state):
			chips.append(r.order_state))
	var n := 0
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"say":
				var shown := int(Session.orders.stats["shown"])
				var at: Vector3 = cmd.get("at", Vector3.INF)
				var controller := game.get("controller") as PlayerController
				controller.aim_override = at if at != Vector3.INF else my_hero().global_position + my_hero().facing * 3.0
				(game.get("voice") as VoiceCaster).inject_text(str(cmd["text"]))
				controller.aim_override = Vector3.INF
				await until(func() -> bool: return int(Session.orders.stats["shown"]) > int(shown), 6.0)
				n += 1
				if n == 1:
					var g := hero_at(3)
					report("said1", {"bark": g != null and g.get_node_or_null(OrderFx.BARK_NAME) != null,
						"waypoint": GameWorld.root.get_node_or_null("OrderWaypoint") != null})
			"goto":
				var map := game.get("map") as HexMap
				place_hero(my_hero(), Hex.from_world(cmd["at"]))
				await sleep(0.4)
				report("there", map != null)
			"look":
				var e := NetRegistry.node(int(cmd["id"])) as Employee
				await until(func() -> bool: return e != null and e.state == Employee.State.FIGHT, 4.0)
				report("look", e.state if e != null else -1)
			"marker":
				await until(func() -> bool: return not get_tree().get_nodes_in_group(OrderFx.Marker.GROUP).is_empty(), 6.0)
				var ms := get_tree().get_nodes_in_group(OrderFx.Marker.GROUP)
				report("marker", str(ms[0].call("text")) if not ms.is_empty() else "")
			"chip":
				var want := str(cmd.get("want", ""))
				await until(func() -> bool: return hero_at(3) != null and hero_at(3).order_state == want, 8.0)
				report(str(cmd["key"]), hero_at(3).order_state if hero_at(3) != null else "")
			"chips":
				report("chips", chips.duplicate())
			"end":
				report("end", Net.guard_hits.size())
				running = false
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

## Host: the floor's monsters and hellgates stand still (nothing should hurt anyone; the henchmen punch a still monster).
func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)


func _henchmen() -> Array[Employee]:
	var out: Array[Employee] = []
	for e in Employee.alive():
		if e.style == "henchman":
			out.append(e)
	return out


func _nearest_monster(p: Vector3) -> Monster:
	var best: Monster = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("monsters"):
		var m := n as Monster
		if m != null and not m.dead and GameWorld.flat_distance(m.global_position, p) < best_d:
			best_d = GameWorld.flat_distance(m.global_position, p)
			best = m
	return best


## Walkable floor about `dist` from `p` (the first of eight directions that has it), level with it. With `away`, only a
## direction that does not head toward `away`.
func _open_spot(p: Vector3, dist: float, away: Vector3 = Vector3.INF) -> Vector3:
	var map := game.get("map") as HexMap
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		if away != Vector3.INF and Vector3(q.x - p.x, 0.0, q.z - p.z).dot(Vector3(away.x - p.x, 0.0, away.z - p.z)) > 0.0:
			continue
		if map.is_walkable_cell(Hex.from_world(q)) and not map.blocks_point(q, 0.6) and absf(map.ground_height(q) - p.y) < 0.6:
			return Vector3(q.x, map.ground_height(q), q.z)
	return p

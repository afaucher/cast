extends NetGameTest
## M4 "done when" (networking-build-plan.md: test_net_m4_hits), three processes, `off` and `coast`: combat across owners.
##
## - ATTACKER DECIDES: client A (c1, seat 2) swings at and shoots one of the host's monsters on its own screen: each hit
##   reaches the host exactly ONCE (the monster loses exactly the swing's and the arrow's damage there), and the other
##   client shows the host's HP;
## - VICTIM DECIDES: a brute next to A winds up and slams. The strike is resolved on A's machine (its NetWorld resolved it
##   from the wind-up event and A lost exactly one slam's damage), never by the host. Then a second slam: A walks out of
##   the ring on its own screen while the host still SHOWS A inside it at its own strike: A is not hit;
## - AGREEMENT: about 24 s of scripted fighting (every machine's hero swings, shoots and casts corn, fireball and heal at
##   the monsters the host keeps sending at the crew; A breaks a priced prop with corn). Then the fighting stops and
##   every machine agrees on every hero's HP and downed state (the owner's figure), which monsters are alive and their
##   HP, and the Ledger (the damage bill) line for line; every hit a client sent arrived at the host once;
## - GUARD (M4c): nothing tripped the OWNER-write guard during all of that, and a deliberate write to a copy's HP (a
##   negative test, with the guard's capture seam on) does trip it.

const PEERS := 3
const SEED := 13
const FIGHT := 24.0
const SLAM_RADIUS := 2.0    ## the brute's (brute.gd has no class name)
const SLAM_DAMAGE := 25.0
const DODGE_LEAD := 0.12    ## A starts walking out of the second slam this long before its strike

var fighting := false
var _next_act := 0.0
var _next_cast := 0.0


func run_host() -> void:
	net_timeout = 85.0
	if not await enter_floor(SEED, 1, {"give": "fireball:9"}):
		return
	if not await wait_sync():
		return
	_freeze_world(true)
	check(await wait_reports("ready", 2, 30.0), "both clients are streaming")
	var a := _peer_named("c1")
	var b := _peer_named("c2")
	var base := my_hero().global_position
	var a_spot := _open_spot(base, 7.0)
	command(a, "stand", {"at": a_spot})
	check(await wait_reports("stood", 1, 20.0), "A stands in the open")
	await sleep(0.5)

	# 1. The attacker decides: A hits a frozen grunt twice (a swing, then an arrow), each reaches the host once.
	var grunt := _spawn_near(hero_at(2).global_position, "grunt", 1.2)
	if not check(grunt != null, "the host spawned a grunt beside A"):
		return
	grunt.set_physics_process(false)
	var gid := NetFloor.id_of(grunt)
	await sleep(0.6)
	var hp0 := grunt.hp
	var hits0 := int(Session.objects.stats["hits_in"])
	command(a, "melee", {"id": gid})
	check(await until(func() -> bool: return grunt.hp < hp0 - 0.01, 4.0), "A's swing reached the host's grunt")
	await sleep(0.5)
	near(hp0 - grunt.hp, hero_at(2).melee_damage, 0.01, "it lost exactly one swing (%.0f): the hit arrived once" % hero_at(2).melee_damage)
	eq(int(Session.objects.stats["hits_in"]) - hits0, 1, "the host applied one hit request")
	var hp1 := grunt.hp
	command(a, "shoot", {"id": gid})
	check(await until(func() -> bool: return grunt.hp < hp1 - 0.01 or grunt.dead, 4.0), "A's arrow reached the host's grunt")
	await sleep(0.5)
	near(hp1 - grunt.hp, hero_at(2).arrow_tap_damage, 0.01, "it lost exactly one arrow (%.0f)" % hero_at(2).arrow_tap_damage)
	command(b, "monster_hp", {"id": gid})
	check(await wait_reports("monster_hp", 1, 10.0), "B reports the grunt")
	near(float(reported(b, "monster_hp")), grunt.hp, 0.15, "B shows the grunt's HP as the host has it")
	grunt.apply_damage(9999.0, my_hero())

	# 2. The victim decides: a brute beside A slams it (resolved on A), then slams again while A walks out of it.
	var brute := _spawn_near(hero_at(2).global_position, "brute", 1.2)
	if not check(brute != null, "the host spawned a brute beside A"):
		return
	var bid := NetFloor.id_of(brute)
	var slams: Array = []
	brute.connect("slammed", func(pos: Vector3) -> void:
		slams.append({"t": Session.host_time(), "a_dist": GameWorld.flat_distance(hero_at(2).global_position, pos)}))
	await sleep(0.4)
	command(a, "brace", {"id": bid})
	brute.aggro(hero_at(2))
	check(await until(func() -> bool: return slams.size() >= 1, 6.0), "the brute slammed on the host")
	check(await wait_reports("brace", 1, 15.0), "A reports the slam")
	var r1: Dictionary = reported(a, "brace")
	print("[M4] slam 1: the host showed A %.2f from the brute; A resolved it itself (%d strike(s) resolved on A, A lost %.1f)" % [float(slams[0]["a_dist"]), int(r1["resolved"]), float(r1["lost"])])
	check(float(slams[0]["a_dist"]) <= SLAM_RADIUS + 0.1, "A stood in the ring on the host's screen")
	eq(int(r1["resolved"]), 1, "A's machine resolved the brute's strike from the wind-up event")
	check(float(r1["lost"]) > 10.0 and float(r1["lost"]) <= SLAM_DAMAGE + 0.01, "A lost one slam's damage (%.1f, at most %.0f)" % [float(r1["lost"]), SLAM_DAMAGE])
	near(float(r1["lost"]), float(r1["strike_damage"]), 0.01, "... all of it in the strike A resolved (the host applied nothing)")
	await sleep(0.4)
	near(hero_at(2).hp, float(r1["hp"]), 0.15, "the host shows A's HP as A has it")
	# The second slam: the brute starts again right away; A walks out of the ring during the wind-up on its own screen.
	brute.set("_next_attack_time", 0.0)
	command(a, "dodge", {"id": bid})
	check(await until(func() -> bool: return slams.size() >= 2, 8.0), "the brute slammed again")
	check(await wait_reports("dodge", 1, 15.0), "A reports the second slam")
	var r2: Dictionary = reported(a, "dodge")
	print("[M4] slam 2: the host showed A %.2f from the brute at its strike; A was %.2f away on its own screen when it resolved it, lost %.1f" % [float(slams[1]["a_dist"]), float(r2["dist"]), float(r2["lost"])])
	check(float(slams[1]["a_dist"]) <= SLAM_RADIUS + 0.1, "the host still SHOWED A inside the ring at its strike (%.2f)" % float(slams[1]["a_dist"]))
	check(float(r2["dist"]) > SLAM_RADIUS + 0.1, "A was out of it on its own screen (%.2f)" % float(r2["dist"]))
	near(float(r2["lost"]), 0.0, 0.01, "A was not hit: it dodged on its own screen")
	brute.apply_damage(9999.0, my_hero())
	await sleep(0.5)

	# 3. A breaks a priced prop with corn: billed once, on every Ledger.
	var prop := _cheapest_prop()
	if check(prop != null, "the floor has a priced prop"):
		command(a, "smash", {"id": NetFloor.id_of(prop), "at": _open_spot(prop.global_position, 4.5)})
		check(await until(func() -> bool: return prop.dead, 10.0), "A's corn broke the %s on the host" % prop.display_name)
		check(await wait_reports("smash", 1, 15.0), "A reports the smash")
		await sleep(0.5)
		eq(_damage_lines(prop.display_name), 1, "the host billed the %s once" % prop.display_name)

	# 4. The fight.
	command(a, "fight")
	command(b, "fight")
	_freeze_world(false)
	fighting = true
	var t0 := wall()
	var spawned := 0
	while wall() - t0 < FIGHT:
		await sleep(0.5)
		if spawned < 18 and _alive_near(my_hero().global_position, 10.0) < 7:
			var who := hero_at(1 + spawned % 3)
			_spawn_near(who.global_position, ["grunt", "grunt", "archer", "swarmer", "brute"][spawned % 5], 4.0)
			spawned += 1
	fighting = false
	_freeze_world(true)
	for peer in [a, b]:
		command(peer, "stop")
	check(await wait_reports("stopped", 2, 15.0), "both clients stopped fighting")
	await sleep(1.5)

	# 5. Agreement.
	for peer in [a, b]:
		command(peer, "views")
	check(await wait_reports("views", 2, 20.0), "both clients report what they show")
	var views := {1: _views()}
	for peer in [a, b]:
		views[int(Session.roster[peer]["seat"])] = reported(peer, "views")
	var host_v: Dictionary = views[1]
	var downed := 0
	for seat in [1, 2, 3]:
		var own: Dictionary = (views[seat] as Dictionary)["heroes"][seat]
		downed += 1 if bool(own["dead"]) else 0
		for viewer: int in views:
			if viewer == seat:
				continue
			var seen: Dictionary = (views[viewer] as Dictionary)["heroes"][seat]
			check(absf(float(seen["hp"]) - float(own["hp"])) <= 0.15 and bool(seen["dead"]) == bool(own["dead"]),
				"seat %d shows seat %d's hero as its owner has it (hp %.1f vs %.1f, downed %s vs %s)" % [viewer, seat, float(seen["hp"]), float(own["hp"]), seen["dead"], own["dead"]])
	var host_mon: Dictionary = host_v["monsters"]
	for viewer in [2, 3]:
		var mon: Dictionary = (views[viewer] as Dictionary)["monsters"]
		var ids_h := host_mon.keys()
		var ids_v := mon.keys()
		ids_h.sort()
		ids_v.sort()
		eq(str(ids_v), str(ids_h), "seat %d shows the same living monsters as the host (%d)" % [viewer, ids_h.size()])
		var worst := 0.0
		for id: Variant in host_mon:
			if mon.has(id):
				worst = maxf(worst, absf(float(mon[id]) - float(host_mon[id])))
		check(worst <= 0.15, "... with the host's HP (worst %.2f)" % worst)
		eq(str((views[viewer] as Dictionary)["ledger"]), str(host_v["ledger"]), "seat %d's Ledger is the host's, line for line" % viewer)
	var sent := 0
	for peer in [a, b]:
		sent += int(reported(peer, "views")["hits_out"])
	var st := Session.objects.stats
	print("[M4] fight: %d monsters sent in, %d heroes downed; clients sent %d hit requests, the host applied %d (%.0f damage); %d shoves; deaths %d; casts applied on the host %d; strikes resolved on the clients %d / %d" % [
		spawned, downed, sent, int(st["hits_in"]), float(st["hit_damage_in"]), int(st["shoves_in"]), int(Session.world.stats["deaths"]),
		int(Session.casts.stats["applied"]), int(reported(a, "views")["strikes"]), int(reported(b, "views")["strikes"])])
	eq(int(st["hit_reqs"]), sent, "every hit request a client sent arrived at the host once")
	check(sent > 20, "the clients really fought (%d hits sent)" % sent)
	var snap := Session.snap.stats
	var span := maxf(Session.host_time() - float(snap["since"]), 0.001)
	print("[M4] bandwidth per client: heroes %.0f B/s + world %.0f B/s down over %.1f s; casts out %d, acts in %d, statuses out %d, wind-ups %d" % [
		float(snap["out_bytes"]) / span / 2.0, float(snap["world_out_bytes"]) / span / 2.0, span, int(Session.casts.stats["casts_out"]),
		int(Session.casts.stats["acts_in"]), int(Session.status.stats["out"]), int(Session.world.stats["windups"])])

	# 6. The guard.
	eq(Net.guard_hits.size(), 0, "the OWNER-write guard never fired on the host during the fight (%s)" % str(Net.guard_hits))
	for peer in [a, b]:
		eq(int(reported(peer, "views")["guard"]), 0, "... nor on seat %d" % int(Session.roster[peer]["seat"]))
	Net.guard_capture = true
	var puppet := hero_at(2)
	var was := puppet.hp
	puppet.hp = was - 1.0   # a non-owner writing an OWNER field: what the guard is for
	eq(Net.guard_hits.size(), 1, "a write to a client's hero's HP on the host trips the guard")
	Net.apply_begin()
	puppet.hp = was          # (the net layer applying the owner's state may)
	Net.apply_end()
	eq(Net.guard_hits.size(), 1, "... and the net layer's own write does not")
	Net.guard_capture = false
	Net.guard_hits.clear()
	command(b, "guard")
	check(await wait_reports("guard", 1, 10.0), "B ran the negative test")
	eq(int(reported(b, "guard")), 1, "a write to a host monster's HP on a client trips the guard there too")
	for peer in [a, b]:
		command(peer, "end")
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	net_timeout = 85.0
	if not await enter_floor(SEED, 1, {"give": "fireball:9"}):
		return
	if not await wait_sync():
		return
	report("ready", true)
	var c := game.get("controller") as PlayerController
	var running := true
	while running:
		var cmd := await wait_command(70.0)
		match str(cmd.get("cmd", "")):
			"stand":
				_stand(cmd["at"])
				await sleep(0.3)
				report("stood", true)
			"melee", "shoot":
				var m := await _wait_node(int(cmd["id"]))
				if m == null:
					continue
				await sleep(0.2)
				var to := m.global_position - my_hero().global_position
				my_hero()._ready_at.clear()
				if str(cmd["cmd"]) == "melee":
					check(my_hero().melee(to), "A swung")
				else:
					check(my_hero().fire_arrow(to, false), "A shot")
			"monster_hp":
				await sleep(0.4)
				var m := NetRegistry.node(int(cmd["id"])) as Actor
				report("monster_hp", m.hp if m != null else -1.0)
			"brace":
				var hp := my_hero().hp
				var n := Session.world.resolved.size()
				await until(func() -> bool: return Session.world.resolved.size() > n, 6.0)
				await sleep(0.3)
				var e: Array = Session.world.resolved.back() if Session.world.resolved.size() > n else [0, 0, 0.0, 0.0]
				report("brace", {"resolved": Session.world.resolved.size() - n, "lost": hp - my_hero().hp, "strike_damage": float(e[3]), "hp": my_hero().hp})
			"dodge":
				var id := int(cmd["id"])
				var hp := my_hero().hp
				var n := Session.world.resolved.size()
				await until(func() -> bool: return Session.world.pending_strike(id) > 0.0, 6.0)
				var strike := Session.world.pending_strike(id)
				await until(func() -> bool: return Session.host_time() >= strike - DODGE_LEAD, 3.0)
				var m := NetRegistry.node(id) as Actor
				var away := my_hero().global_position - m.global_position
				away.y = 0.0
				c.move_override = away.normalized() if away.length() > 0.05 else Vector3.RIGHT
				await until(func() -> bool: return Session.world.resolved.size() > n, 4.0)
				c.move_override = Vector3.INF
				var d := GameWorld.flat_distance(my_hero().global_position, m.global_position) if is_instance_valid(m) else -1.0
				await sleep(0.3)
				report("dodge", {"lost": hp - my_hero().hp, "dist": d})
			"smash":
				var prop := await _wait_node(int(cmd["id"]))
				_stand(cmd["at"])
				await sleep(0.4)
				for i in 3:
					if prop == null or prop.dead:
						break
					my_hero()._ready_at.clear()
					my_hero().set_charges("corn", 5)
					c.aim_override = prop.global_position
					c.cast_spell("corn", 1.0)
					c.aim_override = Vector3.INF
					await until(func() -> bool: return prop.dead, NetCasts.LEAD + CornStrike.DELAY + 0.8)
				report("smash", prop == null or prop.dead)
			"fight":
				fighting = true
			"stop":
				fighting = false
				c.move_override = Vector3.INF
				await sleep(0.3)
				report("stopped", true)
			"views":
				var v := _views()
				v["hits_out"] = int(Session.objects.stats["hits_out"])
				v["guard"] = Net.guard_hits.size()
				v["strikes"] = int(Session.world.stats["strikes"])
				report("views", v)
			"guard":
				Net.guard_capture = true
				var before := Net.guard_hits.size()
				var mon: Monster = null
				for id in Session.world.shown_ids():
					var n := NetRegistry.node(id)
					if n is Monster and not (n as Monster).dead:
						mon = n
						break
				if mon == null:
					var g := NetRegistry.hero(1)
					g.hp = g.hp   # (no monster left: the host's hero will do; an equal write is not a change)
					g.hp = g.hp + 0.5
				else:
					mon.hp = mon.hp - 1.0   # a client writing the host's monster's HP: the guard fires
				report("guard", Net.guard_hits.size() - before)
				Net.guard_capture = false
			_:
				running = false


# --- The fight (every machine drives its own hero) ---------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if not fighting or game == null:
		return
	var h := my_hero()
	if h == null or h.dead:
		return
	var now := Session.host_time()
	if now < _next_act:
		return
	_next_act = now + 0.25
	var foe := GameWorld.nearest_actor(h.global_position, GameWorld.TEAM_MONSTERS, 11.0)
	var c := game.get("controller") as PlayerController
	if h.hp < 40.0 and h.charges_of("heal") > 0 and h.cooldown_left("heal") <= 0.0:
		c.aim_override = h.global_position
		c.cast_spell("heal", 1.0)
		c.aim_override = Vector3.INF
		return
	if foe == null:
		c.move_override = Vector3.INF
		return
	var to := foe.global_position - h.global_position
	to.y = 0.0
	var d := to.length()
	if now >= _next_cast and d > 1.5:
		_next_cast = now + 2.5
		var spell := "corn" if d > 4.0 and _no_hero_near(foe.global_position, 3.5) else "fireball"
		h.set_charges(spell, maxi(h.charges_of(spell), 2))
		c.aim_override = foe.global_position
		c.cast_spell(spell, 1.0)
		c.aim_override = Vector3.INF
		return
	if d <= h.melee_reach * 0.9:
		c.move_override = Vector3.INF
		h.melee(to)
	elif d < 8.0:
		c.move_override = Vector3.INF
		h.fire_arrow(to, false)
	else:
		c.move_override = to.normalized()


func _no_hero_near(p: Vector3, r: float) -> bool:
	for seat in [1, 2, 3]:
		var x := hero_at(seat)
		if x != null and not x.dead and GameWorld.flat_distance(x.global_position, p) < r:
			return false
	return true


# --- Helpers ---------------------------------------------------------------------------------------------------

## What this machine shows: every hero's HP and downed state, every living monster's HP, the Ledger.
func _views() -> Dictionary:
	var heroes := {}
	for seat in [1, 2, 3]:
		var x := hero_at(seat)
		heroes[seat] = {"hp": x.hp, "dead": x.dead}
	var mon := {}
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster and not (n as Monster).dead:
			mon[id] = (n as Monster).hp
	return {"heroes": heroes, "monsters": mon, "ledger": _ledger_text()}


## Host: the monsters and gates hold still (or act again).
func _freeze_world(on: bool) -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if (n is Monster or n is Hellgate) and not (n as Actor).dead:
			n.set_physics_process(not on)


func _alive_near(p: Vector3, r: float) -> int:
	return GameWorld.actors_in_radius(p, r, GameWorld.TEAM_MONSTERS).size()


## Host: spawn a monster `dist` from `p` on open floor (it gets a runtime id and every client builds it).
func _spawn_near(p: Vector3, kind: String, dist: float) -> Monster:
	var spot := _open_spot(p, dist)
	if spot == p:
		return null
	var m := MonsterFactory.spawn(kind, Hex.from_world(spot))
	if m != null:
		m.global_position = Vector3(spot.x, m.global_position.y, spot.z)
	return m


func _cheapest_prop() -> PricedProp:
	var site: SiteBuilder.Site = game.get("_site")
	var best: PricedProp = null
	for p in site.props:
		if is_instance_valid(p) and not p.dead and (best == null or p.hp < best.hp):
			best = p
	return best


func _wait_node(id: int) -> Actor:
	await until(func() -> bool: return NetRegistry.node(id) != null, 5.0)
	return NetRegistry.node(id) as Actor


func _stand(at: Vector3) -> void:
	my_hero().global_position = at
	my_hero().snap_to_ground()


func _peer_named(n: String) -> int:
	for p: int in Session.roster:
		if str(Session.roster[p]["name"]) == n:
			return p
	return 0


## Open floor about `dist` from `p` (of sixteen directions, the first with nothing standing near it).
func _open_spot(p: Vector3, dist: float) -> Vector3:
	var map := game.get("map") as HexMap
	for k in 16:
		var a := TAU * float(k) / 16.0
		var q := p + Vector3(cos(a), 0.0, sin(a)) * dist
		if not map.is_walkable_cell(Hex.from_world(q)) or map.blocks_point(q, 0.6) or absf(map.ground_height(q) - p.y) > 0.6:
			continue
		var clear := true
		for x in GameWorld.actors_in_radius(q, 1.0):
			if not (x is Hero):
				clear = false
		if clear:
			return Vector3(q.x, map.ground_height(q), q.z)
	return p


static func _damage_lines(label: String) -> int:
	var n := 0
	for l in Ledger.lines:
		if str(l["kind"]) == "damage" and str(l["label"]) == label:
			n += 1
	return n


static func _ledger_text() -> String:
	var parts: PackedStringArray = []
	for l in Ledger.lines:
		parts.append("%s|%s|%d|%s|%d" % [str(l["kind"]), str(l["label"]), int(l["amount"]), str(l["who"]), int(l["floor"])])
	return "\n".join(parts)

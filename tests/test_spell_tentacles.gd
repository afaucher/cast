extends TestCase
## Tentacles: after a short telegraph everything inside a SIDEWAYS oval (heroes, caster, monsters) is shoved directly away
## from the aim point; then the tentacles stay up (4 s at minimum power, 6 s at full) and every 0.6 s on the cast's clock
## they swat everyone inside the oval out of its NEAREST edge. Monsters take a little damage at the burst and at every
## swat, heroes none. The oval lies across the caster's line of aim (depth along it, width 1.4 to 2.0 times that across
## it), an immovable actor stays put, an actor on the centre goes along its facing, and power scales the oval, the
## distances, the damage and the duration. The FX node builds and frees itself headless.

var root: Node3D


func _init() -> void:
	timeout_sec = 180.0


func _flat_map(radius: int = 12) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


func _fresh() -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, 5)


func _hero(pos: Vector3) -> Hero:
	var h := Hero.new()
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _dummy(pos: Vector3, hp: float = 1000.0) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = hp
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


func _dist(a: Node3D, center: Vector3) -> float:
	return GameWorld.flat_distance(a.global_position, center)


func _node() -> Tentacles:
	for n in root.get_children():
		if n is Tentacles and not n.is_queued_for_deletion():
			return n
	return null


## Frames from the cast (cast on frame 0) to just before swat 1: the burst's slide is over, no swat yet.
const BEFORE_SWAT := 45


func setup() -> void:
	# --- Metadata and numbers.
	check(SpellBook.SPELLS.has("tentacles"), "spell exists")
	eq(SpellBook.spell_name("tentacles"), "Tentacles")
	eq(SpellBook.word_of("tentacles"), "tentacles")
	eq(SpellBook.incantation("tentacles"), "CAST TENTACLES")
	near(SpellBook.cooldown_of("tentacles"), 10.0, 0.001)
	eq(SpellBook.desc_of("tentacles"), "Neon tentacles burst from the floor where you aim and shove EVERYONE outward.", "the desc is unchanged")
	check(SpellBook.color_of("tentacles").b > 0.9 and SpellBook.color_of("tentacles").g < 0.3, "neon purple")
	near(TentaclesSpell.tentacles_radius(1.0), 3.0, 0.001, "depth (the old radius) 2.2 + 0.8 * power")
	near(TentaclesSpell.tentacles_depth(1.0), 3.0, 0.001, "depth at full power 3.0")
	near(TentaclesSpell.tentacles_width(1.0), 6.0, 0.001, "width at full power = depth x 2.0")
	near(TentaclesSpell.tentacles_width(SpellBook.MIN_POWER) / TentaclesSpell.tentacles_depth(SpellBook.MIN_POWER), 1.4 + 0.6 * SpellBook.MIN_POWER, 0.001, "width = depth x 1.4 at minimum power")
	check(TentaclesSpell.tentacles_width(SpellBook.MIN_POWER) > 3.0 and TentaclesSpell.tentacles_width(SpellBook.MIN_POWER) < 3.3, "width about 3.1 at minimum (%.2f)" % TentaclesSpell.tentacles_width(SpellBook.MIN_POWER))
	near(TentaclesSpell.tentacles_distance(1.0), 4.0, 0.001, "burst distance 2.5 + 1.5 * power")
	near(TentaclesSpell.tentacles_damage(1.0), 6.0, 0.001, "damage 6 * power")
	near(TentaclesSpell.tentacles_duration(1.0), 6.0, 0.001, "up 6 s at full power")
	near(TentaclesSpell.tentacles_duration(SpellBook.MIN_POWER), 4.0, 0.11, "up about 4 s at minimum power")
	near(TentaclesSpell.tentacles_swat_distance(1.0), 2.0, 0.001, "a swat is 2.0 at full power")
	near(TentaclesSpell.tentacles_swat_distance(SpellBook.MIN_POWER), 1.5, 0.03, "... and about 1.5 at minimum")
	eq(TentaclesSpell.tentacles_swats(1.0), 9, "nine swats at full power (0.6 .. 5.4 s after the burst)")
	eq(TentaclesSpell.tentacles_swats(SpellBook.MIN_POWER), 6, "six at minimum power")
	for p in [SpellBook.MIN_POWER, 0.3, 0.6, 1.0]:
		check(TentaclesSpell.tentacles_width(p) > TentaclesSpell.tentacles_depth(p) * 1.39, "wider than deep at power %.2f" % p)
	var scaled := {
		"depth": func(p: float) -> float: return TentaclesSpell.tentacles_depth(p),
		"width": func(p: float) -> float: return TentaclesSpell.tentacles_width(p),
		"distance": func(p: float) -> float: return TentaclesSpell.tentacles_distance(p),
		"damage": func(p: float) -> float: return TentaclesSpell.tentacles_damage(p),
		"duration": func(p: float) -> float: return TentaclesSpell.tentacles_duration(p),
		"swat": func(p: float) -> float: return TentaclesSpell.tentacles_swat_distance(p),
	}
	for f: String in scaled:
		var v: Array[float] = []
		for p in [0.3, 0.6, 1.0]:
			v.append(float((scaled[f] as Callable).call(p)))
		check(v[0] < v[1] and v[1] < v[2], "%s grows with power %s" % [f, str(v)])
	check(TentaclesSpell.tentacles_swat_distance(1.0) < TentaclesSpell.tentacles_distance(1.0), "a swat is smaller than the burst")
	check(SpellBook.find_in_text("cast tentacles") == "tentacles", "text lookup")

	# --- The oval's geometry: the nearest edge, the inside test.
	var ax := Vector3(1, 0, 0)
	check(Tentacles.in_oval(Vector3(2.9, 0, 0), Vector3.ZERO, ax, 3.0, 6.0), "inside along the aim, short of the depth")
	check(not Tentacles.in_oval(Vector3(3.2, 0, 0), Vector3.ZERO, ax, 3.0, 6.0), "outside past the depth along the aim")
	check(Tentacles.in_oval(Vector3(0, 0, 5.8), Vector3.ZERO, ax, 3.0, 6.0), "inside across the aim, short of the width")
	check(Tentacles.in_oval(Vector3(3.2, 0, 0), Vector3.ZERO, ax, 3.0, 6.0, 0.45), "a body's radius counts")
	var e := Tentacles.edge_push(Vector3.ZERO, Vector3.ZERO, ax, 3.0, 6.0)
	check(e.dot(ax) > 0.999, "at the centre a swat goes along the aim, away from the caster (%s)" % str(e))
	e = Tentacles.edge_push(Vector3(-1.0, 0, 0.5), Vector3.ZERO, ax, 3.0, 6.0)
	check(e.x < -0.8, "on the caster's side of the middle: back toward the caster, across the oval (%s)" % str(e))
	e = Tentacles.edge_push(Vector3(0.2, 0, -5.3), Vector3.ZERO, ax, 3.0, 6.0)
	check(e.z < -0.8, "near an end of the width: out of that end (%s)" % str(e))
	var worst := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var q := Vector3(rng.randf_range(-5.9, 5.9), 0, rng.randf_range(-2.9, 2.9))
		if not Tentacles.in_oval(q, Vector3.ZERO, Vector3(0, 0, 1), 3.0, 6.0):
			continue
		var n := Tentacles.nearest_on_ellipse(6.0, 3.0, absf(q.x), absf(q.z))
		var best := INF
		for k in 1441:
			var a := PI * 0.5 * float(k) / 1440.0
			best = minf(best, Vector2(6.0 * cos(a), 3.0 * sin(a)).distance_to(Vector2(absf(q.x), absf(q.z))))
		worst = maxf(worst, Vector2(absf(q.x), absf(q.z)).distance_to(n) - best)
	check(worst < 0.002, "the nearest edge point is the nearest (worst excess %.5f)" % worst)

	# --- Everyone in the oval is pushed outward from the aim point; nothing moves before the telegraph.
	_fresh()
	var center := Vector3.ZERO
	var caster := _hero(Vector3(-7, 0, 0))                     # aims along +X: depth along X, width along Z
	var hero_a := _hero(Vector3(1.6, 0, 0))
	var hero_b := _hero(Vector3(0, 0, -1.9))
	var mon_a := _dummy(Vector3(-1.0, 0, 1.0))
	var mon_b := _dummy(Vector3(0.3, 0, 2.2))
	var side_mon := _dummy(Vector3(0.0, 0, 5.0))               # far across the aim: only the wide oval reaches it
	var far_hero := _hero(Vector3(-5, 0, -4))                 # outside the oval, off everyone's path
	var far_mon := _dummy(Vector3(6, 0, -5))
	var past_mon := _dummy(Vector3(4.2, 0, -1.6))             # along the aim past the depth: outside (off hero_a's path)
	var everyone: Array[Actor] = [hero_a, hero_b, mon_a, mon_b, side_mon]
	var before := {}
	for a in everyone + [far_hero, far_mon, past_mon]:
		before[a] = a.global_position
	var d0 := {}
	for a in everyone:
		d0[a] = _dist(a, center)
	check(SpellBook.cast("tentacles", caster, 1.0, center), "tentacles casts")
	var node := _node()
	check(node != null and node.aim.dot(Vector3(1, 0, 0)) > 0.999, "the oval lies across the caster's aim (+X)")
	await frames(10)
	for a in everyone + [far_hero, far_mon, past_mon]:
		near(a.global_position.distance_to(before[a]), 0.0, 0.0001, "nothing moves during the telegraph (%s)" % a.display_name)
		check(not a.is_shoved(), "nobody is shoved yet")
	near(mon_a.hp, mon_a.max_hp, 0.001, "and no damage yet")
	await frames(BEFORE_SWAT - 10)
	for a in everyone:
		check(_dist(a, center) > d0[a] + 3.0, "%s was pushed outward (%.2f -> %.2f)" % [a.display_name, d0[a], _dist(a, center)])
		var out: Vector3 = (before[a] - center).normalized()
		var moved: Vector3 = a.global_position - before[a]
		check(moved.normalized().dot(out) > 0.97, "directly away from the center (%s)" % a.display_name)
		near(moved.length(), TentaclesSpell.tentacles_distance(1.0), 0.45, "by about the spell distance (%s)" % a.display_name)
	for a in [far_hero, far_mon, past_mon]:
		near(a.global_position.distance_to(before[a]), 0.0, 0.0001, "outside the oval is untouched (%s at %s)" % [a.display_name, str(before[a])])
	near(hero_a.hp, hero_a.max_hp, 0.001, "heroes take no damage")
	near(hero_b.hp, hero_b.max_hp, 0.001, "heroes take no damage")
	near(mon_a.hp, mon_a.max_hp - TentaclesSpell.tentacles_damage(1.0), 0.001, "monsters take 6 * power")
	near(mon_b.hp, mon_b.max_hp - TentaclesSpell.tentacles_damage(1.0), 0.001, "monsters take 6 * power")
	near(far_mon.hp, far_mon.max_hp, 0.001, "out of range monsters are not hurt")
	near(past_mon.hp, past_mon.max_hp, 0.001, "nor one past the depth along the aim")

	# --- The oval turns with the aim: cast along +Z and the wide axis is X.
	_fresh()
	caster = _hero(Vector3(0, 0, -8))
	var x_mon := _dummy(Vector3(5.0, 0, 0))                    # across this aim: inside
	var z_mon := _dummy(Vector3(0.0, 0, 4.2))                  # along it, past the depth: outside
	SpellBook.cast("tentacles", caster, 1.0, center)
	node = _node()
	check(node != null and node.aim.dot(Vector3(0, 0, 1)) > 0.999, "aimed along +Z")
	await frames(BEFORE_SWAT)
	check(x_mon.global_position.x > 8.0, "across the +Z aim, 5 out is inside the oval and shoved (x=%.2f)" % x_mon.global_position.x)
	near(z_mon.global_position.distance_to(Vector3(0, 0, 4.2)), 0.0, 0.05, "along the +Z aim, 4.2 out is outside")

	# --- Immovable actors (Rebar) stay put but monsters still take the damage.
	_fresh()
	caster = _hero(Vector3(-7, 0, 0))
	var rebar := _hero(Vector3(1.45, 0, 0))
	rebar.shove_mult = 0.0
	var rock := _dummy(Vector3(-1.45, 0, 0))
	rock.shove_mult = 0.0
	var brute_like := _dummy(Vector3(0, 0, 1.5))
	brute_like.shove_mult = 0.4
	SpellBook.cast("tentacles", caster, 1.0, center)
	await frames(BEFORE_SWAT)
	near(rebar.global_position.x, 1.45, 0.0001, "an immovable hero stays put")
	near(rock.global_position.x, -1.45, 0.0001, "an immovable monster stays put")
	near(rock.hp, rock.max_hp - 6.0, 0.001, "but still takes the damage")
	near(brute_like.global_position.z - 1.5, 4.0 * 0.4, 0.2, "a heavy actor (0.4) goes 40% as far")

	# --- An actor exactly on the center goes along its facing; the caster counts as everyone.
	_fresh()
	var middle := _hero(Vector3.ZERO)
	middle.facing = Vector3(0, 0, 1)
	var next_to := _dummy(Vector3(1.5, 0, 0))
	# Aim at the hero standing on the spot (ally snap): the spell lands on them.
	var cast_at := _hero(Vector3(-7, 0, 5))
	cast_at.facing = Vector3.RIGHT
	SpellBook.cast("tentacles", cast_at, 1.0, Vector3(0.4, 0, 0.3))   # within 1.3 of the middle hero: snaps onto them
	await frames(BEFORE_SWAT)
	check(middle.global_position.z > 3.0, "the actor on the center is pushed along its facing (z=%.2f)" % middle.global_position.z)
	near(middle.global_position.x, 0.0, 0.2, "and not sideways")
	check(next_to.global_position.x > 4.5, "its neighbour is pushed outward from the snapped center (x=%.2f)" % next_to.global_position.x)
	near(middle.hp, middle.max_hp, 0.001, "a hero on the center takes no damage")

	# --- The caster on its own target: the oval lies across its facing.
	_fresh()
	var self_caster := _hero(Vector3(2, 0, 2))
	self_caster.facing = Vector3(0, 0, -1)
	SpellBook.cast("tentacles", self_caster, 1.0, Vector3(2, 0, 2))
	node = _node()
	check(node != null and node.aim.dot(Vector3(0, 0, -1)) > 0.999, "on its own spot the aim is the caster's facing (%s)" % (str(node.aim) if node != null else "none"))
	await frames(BEFORE_SWAT)

	# --- Power scaling is monotonic in the real effect; the WIDTH grows with it, not just the depth.
	var moved_by: Array[float] = []
	var hurt_by: Array[float] = []
	var reach_by: Array[bool] = []
	var wide_by: Array[bool] = []
	for p in [0.3, 0.6, 1.0]:
		_fresh()
		var c := _hero(Vector3(-8, 0, 0))
		var m := _dummy(Vector3(0, 0, 1.5))
		var edge := _dummy(Vector3(3.3, 0, 0))      # along the aim: inside the depth only at full power
		var wide := _dummy(Vector3(0, 0, -4.6))     # across it: inside the width at full power, not at 0.3
		SpellBook.cast("tentacles", c, p, center)
		await frames(BEFORE_SWAT)
		moved_by.append(m.global_position.z - 1.5)
		hurt_by.append(m.max_hp - m.hp)
		reach_by.append(edge.global_position.x > 3.4)
		wide_by.append(wide.global_position.z < -4.7)
	check(moved_by[0] < moved_by[1] and moved_by[1] < moved_by[2], "distance grows with power %s" % str(moved_by))
	check(hurt_by[0] < hurt_by[1] and hurt_by[1] < hurt_by[2], "damage grows with power %s" % str(hurt_by))
	check(not reach_by[0] and reach_by[2], "depth grows with power %s" % str(reach_by))
	check(not wide_by[0] and wide_by[2], "width grows with power %s" % str(wide_by))

	# --- Swats: on the tick schedule, everyone inside (monsters AND heroes) out of the nearest edge.
	_fresh()
	caster = _hero(Vector3(-9, 0, 0))                          # aim +X: depth 3 along X, width 6 along Z
	SpellBook.cast("tentacles", caster, 1.0, center)
	node = _node()
	await frames(30)                                           # the burst is over; now stand people in the oval
	var near_side := _dummy(Vector3(-1.0, 0, 2.5))             # the caster's side of the middle: back toward the caster
	var far_side := _hero(Vector3(1.0, 0, -2.0))               # a HERO beyond the middle: on away from the caster
	var end_mon := _dummy(Vector3(0.3, 0, 5.0))                # near an end of the width: out of that end
	var swatted: Array[Actor] = [near_side, far_side, end_mon]
	var at0 := {}
	var want := {}
	for a in swatted:
		at0[a] = a.global_position
		want[a] = Tentacles.edge_push(a.global_position, center, node.aim, node.depth(), node.width())
	var t_first := node.swat_time(1)
	while GameWorld.time < t_first - 0.5 / 60.0:
		for a in swatted:
			near(a.global_position.distance_to(at0[a]), 0.0, 0.0001, "nobody moves before the first swat (%s)" % a.display_name)
		await frames(1)
	await frames(30)
	for a in swatted:
		var moved: Vector3 = a.global_position - at0[a]
		moved.y = 0.0
		check(moved.normalized().dot(want[a]) > 0.97, "%s swatted out of the nearest edge (moved %s, edge %s)" % [a.display_name, str(moved), str(want[a])])
		near(moved.length(), TentaclesSpell.tentacles_swat_distance(1.0), 0.35, "by about the swat distance (%s)" % a.display_name)
	check(near_side.global_position.x < -2.0, "the caster's side goes back toward the caster (x=%.2f)" % near_side.global_position.x)
	check(far_side.global_position.x > 2.0, "the far side goes on away from it (x=%.2f)" % far_side.global_position.x)
	check(end_mon.global_position.z > 6.0, "the end goes out its end (z=%.2f)" % end_mon.global_position.z)
	near(far_side.hp, far_side.max_hp, 0.001, "a swatted hero takes no damage")
	near(near_side.hp, near_side.max_hp - TentaclesSpell.tentacles_damage(1.0), 0.001, "a swatted monster takes 6 * power")

	# --- The tick schedule and the duration: an immovable monster in the middle takes the burst and every swat, each at
	# its tick (start + TELEGRAPH + k x 0.6), and the spell frees itself after it is up 4 s (low) / 6 s (full) + retract.
	for p in [SpellBook.MIN_POWER, 1.0]:
		_fresh()
		var c := _hero(Vector3(-9, 0, 0))
		var post := _dummy(Vector3(0.5, 0, 0.5), 5000.0)
		post.shove_mult = 0.0
		SpellBook.cast("tentacles", c, p, center)
		var tn := _node()
		var start := tn.start_time
		var up := TentaclesSpell.tentacles_duration(p)
		var hits: Array[float] = []
		var last_hp := post.hp
		var alive_at_end := false
		while is_instance_valid(tn) and GameWorld.time - start < Tentacles.TELEGRAPH + up + TentaclesFx.RETRACT + 0.5:
			await frames(1)
			if post.hp < last_hp - 0.0001:
				hits.append(GameWorld.time - start)
				last_hp = post.hp
			if is_instance_valid(tn) and GameWorld.time - start > Tentacles.TELEGRAPH + up + TentaclesFx.RETRACT - 0.1:
				alive_at_end = true
		var n_swats := TentaclesSpell.tentacles_swats(p)
		eq(hits.size(), 1 + n_swats, "power %.2f: the burst and %d swats (%s)" % [p, n_swats, str(hits)])
		var sched_ok := true
		for k in hits.size():
			if absf(hits[k] - (Tentacles.TELEGRAPH + float(k) * TentaclesSpell.TENTACLES_SWAT_EVERY)) > 1.5 / 60.0:
				sched_ok = false
		check(sched_ok, "power %.2f: each on its tick, start + %.2f + k x %.1f (%s)" % [p, Tentacles.TELEGRAPH, TentaclesSpell.TENTACLES_SWAT_EVERY, str(hits)])
		near(post.max_hp - post.hp, float(1 + n_swats) * TentaclesSpell.tentacles_damage(p), 0.01, "power %.2f: damage at the burst and every swat" % p)
		check(alive_at_end, "power %.2f: still up just before %.1f s + the retract" % [p, up])
		check(not is_instance_valid(tn), "power %.2f: gone after it" % p)

	# --- The FX builds headless: tentacles spread over the oval, the rim, and the spell node frees itself.
	_fresh()
	var c2 := _hero(Vector3(-8, 0, 0))
	SpellBook.cast("tentacles", c2, 1.0, center)
	var tnode := _node()
	check(tnode != null, "spell node spawned")
	await frames(30)
	var fx: TentaclesFx = null
	for n in tnode.get_children():
		if n is TentaclesFx:
			fx = n
	check(fx != null, "fx node exists")
	var count := 0
	var max_side := 0.0
	var max_along := 0.0
	for n in fx.get_children():
		if str(n.name).begins_with("Tentacle"):
			count += 1
			var lp := Tentacles.to_local_oval(n.global_position, center, tnode.aim)
			max_side = maxf(max_side, absf(lp.x))
			max_along = maxf(max_along, absf(lp.y))
	eq(count, fx.count(), "every tentacle built (%d)" % count)
	check(count >= 12 and count <= TentaclesFx.COUNT_MAX, "more tentacles over the wide oval (%d)" % count)
	check(max_side > max_along * 1.5, "spread over the width (%.2f across, %.2f along)" % [max_side, max_along])
	check(fx.get_node_or_null("Rim") != null, "the oval's rim")
	await frames(int((Tentacles.TELEGRAPH + TentaclesSpell.tentacles_duration(1.0) + TentaclesFx.RETRACT) * 60.0) + 30)
	check(not is_instance_valid(tnode), "the spell node frees itself after the tentacles retract")
	finish()

extends MonsterTestBase
## The goo imp (docs/design/goo-imp.md, "As built"), solo:
## - in a fight it winds up (the monsters' wind-up, THROW_TELL) and lobs a ball that lands near its target after a flight
##   with a landing marker; a hit: DAMAGE and the goo slow (the "goo" modifier), and no patch;
## - a miss on dry ground leaves a patch that slows heroes and monsters alike (x SLOW) and dries up after LIFE;
## - a ball into water: a splash and nothing else;
## - the real fireball lights a patch: it burns FIRE_TIME, hurts whoever stands in it and sets nobody Burning; then it is gone;
## - the real Damp washes a patch away (its own wet floor stays);
## - it hangs back on dry ground: a hero across a channel out of range does not draw it into the water;
## - a pack's throws are spread out (the first-throw delay and the cooldown jitter).


func setup() -> void:
	await _throw_and_hit()
	await _miss_makes_patch()
	await _water_splash()
	await _fire()
	await _damp()
	await _stays_dry()
	await _pack_spread()
	await _copies()
	finish()


func _hero_at(p: Vector3) -> Actor:
	var h := add_hero(Hex.from_world(p))
	h.global_position = Vector3(p.x, 0.0, p.z)
	h.max_hp = 1000.0
	h.hp = 1000.0
	return h


## A flat map with a channel of water (cells with q in [lo, hi], one level down) running across it.
func _channel_map(radius: int, lo: int, hi: int) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		if c.x >= lo and c.x <= hi:
			var cell := m.set_cell(c, -1)
			cell.pool_mask = HexMap.ALL_KITES
			cell.pool_level = -1
		else:
			m.set_cell(c, 0)
	m.pools.append({"body": true})
	return m


func _imp_at(cell: Vector2i) -> GooImp:
	var m := MonsterFactory.spawn("goo_imp", cell) as GooImp
	return m


# --- 1. The throw and a hit --------------------------------------------------------------------------------------------

func _throw_and_hit() -> void:
	new_world(flat_map(12))
	var imp := _imp_at(Vector2i(-4, 0))
	var hero := _hero_at(Vector3(2.0, 0.0, 0.0))
	await frames(2)
	eq(imp.kind, "goo_imp", "kind")
	near(imp.max_hp, 12.0, 0.001, "the swarmer's HP (12)")
	var tells := [0]
	imp.windup_begun.connect(func(l: float) -> void:
		tells[0] += 1
		near(l, GooImp.THROW_TELL, 0.001, "the tell is the 0.7 s wind-up"))
	imp.aggro(hero)
	check(await wait_until(func() -> bool: return imp.throws >= 1, 200), "it throws")
	eq(tells[0], 1, "one tell before the throw")
	var b := imp.last_ball
	check(b != null and is_instance_valid(b), "the ball flies")
	check(GameWorld.flat_distance(b.to, hero.global_position) <= GooImp.SCATTER + 0.01, "it lands within SCATTER of where the hero stood")
	check(b.flight >= GooBall.FLIGHT_MIN and b.flight <= GooBall.FLIGHT_MAX, "about a second in the air (%.2f)" % b.flight)
	check(world.get_node_or_null("GooMarker") != null or _has_marker(), "the landing marker is on the floor")
	await frames(10)
	check(b.global_position.y > b.to.y + 1.0, "the ball is up in the air on its arc")
	var wb: WeakRef = weakref(b)
	check(await wait_until(func() -> bool: return wb.get_ref() == null or wb.get_ref().landed, 120), "the ball lands")
	near(hero.hp, 1000.0 - GooBall.DAMAGE, 0.001, "a hit: small damage (%.0f)" % GooBall.DAMAGE)
	check(hero.has_modifier(GooPatch.SLOW_ID), "... and the goo slow")
	near(hero.move_speed_mult(), GooPatch.SLOW, 0.001, "... walking at x%.2f" % GooPatch.SLOW)
	check(GooBoots.has_on(hero), "... with goo on its boots")
	eq(GooPatch.live().size(), 0, "a hit leaves no patch")
	check(not _has_marker(), "the marker is gone with the splat")


func _has_marker() -> bool:
	for n in world.get_children():
		if n.name.begins_with("GooMarker"):
			return true
	return false


# --- 2. A miss: the patch --------------------------------------------------------------------------------------------

func _miss_makes_patch() -> void:
	new_world(flat_map(12))
	var imp := _imp_at(Vector2i(-5, 0))
	var hero := _hero_at(Vector3(6.0, 0.0, 4.0))
	var g := MonsterFactory.spawn("grunt", Vector2i(4, -4))
	await frames(2)
	imp.set_physics_process(false)
	g.set_physics_process(false)
	var spot := Vector3(1.0, 0.0, 0.0)
	var b := imp.throw_at(spot)
	check(await wait_until(func() -> bool: return b.landed, 120), "the ball lands")
	check(not b.hit_any and b.patch != null, "nobody under it: a patch")
	eq(GooPatch.live().size(), 1, "one patch")
	var p := b.patch as GooPatch
	near(GameWorld.flat_distance(p.global_position, spot), 0.0, 0.01, "where the ball landed")
	near(hero.hp, 1000.0, 0.001, "the hero far off is not hit")
	var free_speed := hero.effective_speed()
	hero.global_position = spot + Vector3(0.3, 0.0, 0.0)
	near(hero.effective_speed(), free_speed * GooPatch.SLOW, 0.001, "a hero on the patch walks at x%.2f" % GooPatch.SLOW)
	var g_free := g.effective_speed()
	g.global_position = spot + Vector3(-0.4, 0.0, 0.2)
	near(g.effective_speed(), g_free * GooPatch.SLOW, 0.001, "... and so does a monster")
	hero.global_position = spot + Vector3(GooPatch.RADIUS + 0.6, 0.0, 0.0)
	near(hero.effective_speed(), free_speed, 0.001, "off the patch: full speed")
	hero.global_position = spot
	await frames(3)
	check(GooBoots.has_on(hero), "goo on the boots of whoever stands in it")
	var born := p.start_time
	var wp: WeakRef = weakref(p)
	check(await wait_until(func() -> bool: return wp.get_ref() == null, int(60 * (GooPatch.LIFE + 1.0))), "the patch dries up")
	check(GameWorld.time - born >= GooPatch.LIFE - 0.05, "... after about %.0f s (%.2f)" % [GooPatch.LIFE, GameWorld.time - born])
	near(hero.effective_speed(), free_speed, 0.001, "full speed once it is gone")
	await frames(3)
	check(not GooBoots.has_on(hero), "the goo on the boots goes with it")


# --- 3. Water: a splash and gone ------------------------------------------------------------------------------------------

func _water_splash() -> void:
	new_world(_channel_map(12, -1, 1))
	var imp := _imp_at(Vector2i(-6, 0))
	await frames(2)
	imp.set_physics_process(false)
	var spot := Hex.to_world(Vector2i(0, 2), -1.0)
	check(GameWorld.map.water_at(spot), "the spot is in the channel")
	var b := imp.throw_at(spot)
	check(await wait_until(func() -> bool: return b.landed, 120), "the ball lands in the water")
	eq(GooPatch.live().size(), 0, "a splash, and no patch (no slick)")


# --- 4. Fire on a patch ----------------------------------------------------------------------------------------------------

func _fire() -> void:
	new_world(flat_map(12))
	var imp := _imp_at(Vector2i(-6, 0))
	var wick := _hero_at(Vector3(-2.0, 0.0, 6.0))
	var g := MonsterFactory.spawn("grunt", Vector2i(5, -5))
	await frames(2)
	imp.set_physics_process(false)
	g.set_physics_process(false)
	g.aggro_range = 0.0
	var spot := Vector3(3.0, 0.0, 0.0)
	var b := imp.throw_at(spot)
	await wait_until(func() -> bool: return b.landed, 120)
	var p := b.patch as GooPatch
	if not check(p != null, "a patch to light"):
		return
	g.max_hp = 1000.0
	g.hp = 1000.0
	# the real fireball, aimed at the patch (nobody in its blast)
	var shot := FireballSpell.cast(wick, 1.0, spot, GameWorld.time, {})
	check(shot != null, "a fireball flies")
	check(await wait_until(func() -> bool: return p.is_lit(), 120), "the fireball lights the patch")
	var lit_at := p.lit_at
	# a monster and a hero walk into it just after (the blast is over: only the patch can hurt them now)
	g.global_position = spot + Vector3(0.2, 0.0, 0.0)
	var h2 := _hero_at(spot + Vector3(-0.3, 0.0, 0.0))
	var g_hp := g.hp
	var h_hp := h2.hp
	await wait_until(func() -> bool: return GameWorld.time >= lit_at + 1.05, 120)
	near(g_hp - g.hp, 2.0 * GooPatch.FIRE_DAMAGE, 0.01, "the burning patch hurts the monster in it: %.0f a tick, every %.1f s" % [GooPatch.FIRE_DAMAGE, GooPatch.FIRE_TICK])
	await wait_until(func() -> bool: return GameWorld.time >= lit_at + 2.05, 120)
	check(h2.hp < h_hp, "it hurts a hero standing in it too")
	check(not Burning.is_burning(h2), "... and never sets anyone Burning (no fire spread)")
	var wp: WeakRef = weakref(p)
	check(await wait_until(func() -> bool: return wp.get_ref() == null, int(60 * (GooPatch.FIRE_TIME + 1.0))), "it burns out")
	check(GameWorld.time - lit_at >= GooPatch.FIRE_TIME - 0.05, "... after %.0f s (%.2f)" % [GooPatch.FIRE_TIME, GameWorld.time - lit_at])
	var h_end := h2.hp
	await frames(40)
	near(h2.hp, h_end, 0.001, "burnt off: it hurts no more")


# --- 5. Damp washes a patch away -------------------------------------------------------------------------------------------

func _damp() -> void:
	new_world(flat_map(12))
	var imp := _imp_at(Vector2i(-6, 0))
	var caster := _hero_at(Vector3(-2.0, 0.0, 6.0))
	await frames(2)
	imp.set_physics_process(false)
	var b1 := imp.throw_at(Vector3(3.0, 0.0, 0.0))
	var b2 := imp.throw_at(Vector3(3.0, 0.0, -9.0))   # (far from the drizzle)
	var w1: WeakRef = weakref(b1)
	var w2: WeakRef = weakref(b2)
	await wait_until(func() -> bool: return (w1.get_ref() == null or w1.get_ref().landed) and (w2.get_ref() == null or w2.get_ref().landed), 120)
	eq(GooPatch.live().size(), 2, "two patches")
	var near_p: GooPatch = null
	for q in GooPatch.live():
		if GameWorld.flat_distance(q.global_position, Vector3(3.0, 0.0, 0.0)) < 0.1:
			near_p = q
	check(near_p != null, "the patch where the drizzle will fall")
	var wn: WeakRef = weakref(near_p)
	var d := DampSpell.cast(caster, 1.0, Vector3(3.5, 0.0, 0.5), GameWorld.time, {}) as Damp
	check(await wait_until(func() -> bool: return wn.get_ref() == null or (wn.get_ref() as GooPatch).washed, 60), "Damp washes the patch away")
	await frames(30)
	eq(GooPatch.live().size(), 1, "... only the one under the drizzle")
	check(is_instance_valid(d) and d.is_wet_at(Vector3(3.0, 0.0, 0.0)), "Damp's own wet floor is what is left")
	var walker := _hero_at(Vector3(3.0, 0.0, 0.0))
	near(GooPatch.speed_mult(walker), 1.0, 0.001, "no goo slow there any more")


# --- 6. Dry ground --------------------------------------------------------------------------------------------------------

func _stays_dry() -> void:
	new_world(_channel_map(12, -2, 1))
	var imp := _imp_at(Vector2i(-5, 0))
	var hero := _hero_at(Vector3(Hex.to_world(Vector2i(6, 0)).x, 0.0, 0.0))   # across the channel, out of its range
	await frames(2)
	var start := imp.global_position
	check(GameWorld.flat_distance(start, hero.global_position) > GooImp.THROW_RANGE, "the hero starts out of range")
	imp.aggro(hero)
	var wet_frames := 0
	for i in 240:
		await get_tree().physics_frame
		if GooImp.is_wet(imp.global_position):
			wet_frames += 1
	eq(wet_frames, 0, "it never steps into the water to get at the hero")
	check(imp.state == Monster.State.CHASE or imp.state == Monster.State.ATTACK, "it is still in the fight, waiting at the edge")
	check(GameWorld.flat_distance(imp.global_position, start) > 0.5, "it walked up to the water's edge")


# --- 7. A pack spreads its throws -------------------------------------------------------------------------------------------

func _pack_spread() -> void:
	new_world(flat_map(12))
	var imps: Array[GooImp] = []
	for c: Vector2i in [Vector2i(-5, 0), Vector2i(-5, 1), Vector2i(-4, -1)]:
		imps.append(_imp_at(c))
	var hero := _hero_at(Vector3(2.0, 0.0, 0.0))
	await frames(2)
	var times: Array[float] = []
	for m in imps:
		m.windup_begun.connect(func(_l: float) -> void: times.append(GameWorld.time))
	for m in imps:
		m.aggro(hero)
	await wait_until(func() -> bool: return times.size() >= 6, 60 * 8)
	check(times.size() >= 6, "the pack keeps throwing (%d tells)" % times.size())
	times.sort()
	var same := 0
	for i in range(1, times.size()):
		if times[i] - times[i - 1] < 0.02:
			same += 1
	check(same <= 1, "the throws come one by one, not as a volley (%d at once)" % same)


# --- 8. The rows a client builds from (obj.new, a late joiner's `new` section) -----------------------------------------------

func _copies() -> void:
	new_world(flat_map(12))
	var imp := _imp_at(Vector2i(-6, 0))
	var wick := _hero_at(Vector3(-2.0, 0.0, 6.0))
	await frames(2)
	imp.set_physics_process(false)
	var objs := NetObjects.new()   # (no session: the shared clock is this one, so stamps round-trip exactly)
	add_child(objs)
	# a ball: its copy flies to the same point and lands at the same moment
	var b := imp.throw_at(Vector3(3.0, 0.0, 0.0))
	var bc := GooBall.net_copy(b.net_spawn_row(objs), objs) as GooBall
	if check(bc != null, "a ball's row builds a copy"):
		near(GameWorld.flat_distance(bc.to, b.to), 0.0, 0.001, "... landing on the same point")
		near(bc.land_time(), b.land_time(), 0.001, "... at the same moment")
		bc.net_make_copy()
		check(Net.is_copy(bc) and bc.is_physics_processing(), "... a copy that still flies")
	var wb: WeakRef = weakref(b)
	await wait_until(func() -> bool: return wb.get_ref() == null or (wb.get_ref() as GooBall).landed, 120)
	await frames(2)
	eq(GooPatch.live().size(), 1, "only the owner's ball made a patch (the copy decides nothing)")
	var p: GooPatch = GooPatch.live()[0]
	GooPatch.fire_at(p.global_position, 1.0, wick)
	check(p.is_lit() and p.lit_by == wick, "lit (the owner decides)")
	# a late joiner: the patch, lit, rebuilt from the host's row
	NetRegistry.register(20002, wick)   # (the lighter rides the row as its net id)
	var rows := p.late_join_state(objs, 20001)
	check(rows.has("new"), "a live patch has a late-join row")
	objs.apply_late_join({"new": [rows["new"]]})   # (NetObjects.late_join_state gathers each section as a list of rows)
	var c := NetRegistry.node(20001) as GooPatch
	if check(c != null and c != p, "the late joiner builds it (as obj.new would)"):
		check(Net.is_copy(c), "... as a copy")
		near(GameWorld.flat_distance(c.global_position, p.global_position), 0.0, 0.001, "... in the same place")
		check(c.is_lit(), "... lit")
		near(c.lit_at, p.lit_at, 0.001, "... from the same moment")
		check(c.lit_by == wick, "... by the same hero")
	NetRegistry.unregister(20001)
	NetRegistry.unregister(20002)
	objs.free()

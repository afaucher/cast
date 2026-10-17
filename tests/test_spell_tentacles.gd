extends TestCase
## Tentacles: after a short telegraph everything in the radius (heroes, caster, monsters) is
## shoved directly away from the aim point. Monsters take a little damage, heroes none, an
## immovable actor stays put, an actor on the center goes along its facing, and power scales
## the radius, the distance and the damage. The FX node builds and frees itself headless.

var root: Node3D


func _flat_map(radius: int = 10) -> HexMap:
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


func setup() -> void:
	# --- Metadata and numbers.
	check(SpellBook.SPELLS.has("tentacles"), "spell exists")
	eq(SpellBook.spell_name("tentacles"), "Tentacles")
	eq(SpellBook.word_of("tentacles"), "tentacles")
	eq(SpellBook.incantation("tentacles"), "CAST TENTACLES")
	near(SpellBook.cooldown_of("tentacles"), 10.0, 0.001)
	check(SpellBook.color_of("tentacles").b > 0.9 and SpellBook.color_of("tentacles").g < 0.3, "neon purple")
	near(SpellBook.tentacles_radius(1.0), 3.0, 0.001, "radius 2.2 + 0.8 * power")
	near(SpellBook.tentacles_distance(1.0), 4.0, 0.001, "distance 2.5 + 1.5 * power")
	near(SpellBook.tentacles_damage(1.0), 6.0, 0.001, "damage 6 * power")
	check(SpellBook.tentacles_radius(0.3) < SpellBook.tentacles_radius(0.6) and SpellBook.tentacles_radius(0.6) < SpellBook.tentacles_radius(1.0), "radius monotonic")
	check(SpellBook.tentacles_distance(0.3) < SpellBook.tentacles_distance(0.6) and SpellBook.tentacles_distance(0.6) < SpellBook.tentacles_distance(1.0), "distance monotonic")
	check(SpellBook.tentacles_damage(0.3) < SpellBook.tentacles_damage(0.6) and SpellBook.tentacles_damage(0.6) < SpellBook.tentacles_damage(1.0), "damage monotonic")
	check(SpellBook.find_in_text("cast tentacles") == "tentacles", "text lookup")

	# --- Everyone is pushed outward from the aim point; nothing moves before the telegraph.
	_fresh()
	var center := Vector3.ZERO
	var caster := _hero(Vector3(-7, 0, 0))
	var hero_a := _hero(Vector3(1.6, 0, 0))
	var hero_b := _hero(Vector3(0, 0, -1.9))
	var mon_a := _dummy(Vector3(-1.0, 0, 1.0))
	var mon_b := _dummy(Vector3(0.3, 0, 2.2))
	var far_hero := _hero(Vector3(-5, 0, -4))                 # outside the radius, off everyone's path
	var far_mon := _dummy(Vector3(6, 0, -5))
	var everyone: Array[Actor] = [hero_a, hero_b, mon_a, mon_b]
	var before := {}
	for a in everyone + [far_hero, far_mon]:
		before[a] = a.global_position
	var d0 := {}
	for a in everyone:
		d0[a] = _dist(a, center)
	check(SpellBook.cast("tentacles", caster, 1.0, center), "tentacles casts")
	await frames(10)
	for a in everyone + [far_hero, far_mon]:
		near(a.global_position.distance_to(before[a]), 0.0, 0.0001, "nothing moves during the telegraph (%s)" % a.display_name)
		check(not a.is_shoved(), "nobody is shoved yet")
	near(mon_a.hp, mon_a.max_hp, 0.001, "and no damage yet")
	await frames(60)
	for a in everyone:
		check(_dist(a, center) > d0[a] + 3.0, "%s was pushed outward (%.2f -> %.2f)" % [a.display_name, d0[a], _dist(a, center)])
		var out: Vector3 = (before[a] - center).normalized()
		var moved: Vector3 = a.global_position - before[a]
		check(moved.normalized().dot(out) > 0.97, "directly away from the center (%s)" % a.display_name)
		near(moved.length(), SpellBook.tentacles_distance(1.0), 0.45, "by about the spell distance (%s)" % a.display_name)
	for a in [far_hero, far_mon]:
		near(a.global_position.distance_to(before[a]), 0.0, 0.0001, "outside the radius is untouched")
	near(hero_a.hp, hero_a.max_hp, 0.001, "heroes take no damage")
	near(hero_b.hp, hero_b.max_hp, 0.001, "heroes take no damage")
	near(mon_a.hp, mon_a.max_hp - SpellBook.tentacles_damage(1.0), 0.001, "monsters take 6 * power")
	near(mon_b.hp, mon_b.max_hp - SpellBook.tentacles_damage(1.0), 0.001, "monsters take 6 * power")
	near(far_mon.hp, far_mon.max_hp, 0.001, "out of range monsters are not hurt")

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
	await frames(70)
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
	await frames(70)
	check(middle.global_position.z > 3.0, "the actor on the center is pushed along its facing (z=%.2f)" % middle.global_position.z)
	near(middle.global_position.x, 0.0, 0.2, "and not sideways")
	check(next_to.global_position.x > 4.5, "its neighbour is pushed outward from the snapped center (x=%.2f)" % next_to.global_position.x)
	near(middle.hp, middle.max_hp, 0.001, "a hero on the center takes no damage")

	# --- Power scaling is monotonic in the real effect.
	var moved_by: Array[float] = []
	var hurt_by: Array[float] = []
	var reach_by: Array[bool] = []
	for p in [0.3, 0.6, 1.0]:
		_fresh()
		var c := _hero(Vector3(-8, 0, 0))
		var m := _dummy(Vector3(0, 0, 1.5))
		var edge := _dummy(Vector3(3.3, 0, 0))      # inside the radius only at full power
		SpellBook.cast("tentacles", c, p, center)
		await frames(70)
		moved_by.append(m.global_position.z - 1.5)
		hurt_by.append(m.max_hp - m.hp)
		reach_by.append(edge.global_position.x > 3.4)
	check(moved_by[0] < moved_by[1] and moved_by[1] < moved_by[2], "distance grows with power %s" % str(moved_by))
	check(hurt_by[0] < hurt_by[1] and hurt_by[1] < hurt_by[2], "damage grows with power %s" % str(hurt_by))
	check(not reach_by[0] and reach_by[2], "radius grows with power %s" % str(reach_by))

	# --- The FX builds headless, covers a ring of tentacles, and the spell node frees itself.
	_fresh()
	var c2 := _hero(Vector3(-8, 0, 0))
	SpellBook.cast("tentacles", c2, 1.0, center)
	var node: Tentacles = null
	for n in root.get_children():
		if n is Tentacles:
			node = n
	check(node != null, "spell node spawned")
	await frames(30)
	var fx: TentaclesFx = null
	for n in node.get_children():
		if n is TentaclesFx:
			fx = n
	check(fx != null, "fx node exists")
	var count := 0
	for n in fx.get_children():
		if str(n.name).begins_with("Tentacle"):
			count += 1
	check(count >= 6 and count <= 9, "6 to 9 tentacles (%d)" % count)
	await frames(int((Tentacles.TELEGRAPH + TentaclesFx.LIFETIME) * 60.0) + 30)
	check(not is_instance_valid(node), "the spell node frees itself after the tentacles retract")
	finish()

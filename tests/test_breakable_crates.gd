extends TestCase
## Breakable crate stacks (decor kinds RoomThemeDefs.BREAKABLE_DECOR, BreakableCrate): they join the "breakables"
## group and break to one hit of melee, arrows, a bolt, an area spell, a shove and Rebar's bowl; breaking leaves
## planks that fade at 30 s and a Grime mark, removes the model and the blocker circle (so it stops blocking), and
## it is NOT property damage and drops nothing. Shelves, racks, furniture and barrels stay solid. Also: a top box of
## a 3-stack of mail breaks to a sword swing from the floor (see test_mail_package for the rest of the mail).

var root: Node3D


func _flat_map(radius: int = 9) -> HexMap:
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
	Ledger.begin_contract(1000000)


func _hero(pos: Vector3, hero_name: String = "Wick", secondary: String = "bolt") -> Hero:
	var h := Hero.new()
	h.display_name = hero_name
	h.secondary_kind = secondary
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _dummy(pos: Vector3) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.max_hp = 1000.0
	GameWorld.spawn(d, pos)
	d.snap_to_ground()
	return d


## A decor piece the way SitePlan describes it (the blocker circles come from ThemeCtx, like the real ones).
func _decor(kind: String, pos: Vector2, yaw: float = 0.0) -> DecorProp:
	var m: Dictionary = RoomThemeDefs.decor(kind)
	var circles := ThemeCtx.blocker_circles(pos, yaw, float(m["w"]), float(m["d"]))
	var entry := {
		"kind": kind, "pos": pos, "yaw": yaw, "blocks": bool(m["blocks"]), "w": float(m["w"]), "d": float(m["d"]),
		"block_points": circles["points"], "block_radius": circles["radius"], "lift": 0.0,
	}
	return DecorProp.spawn(entry, root)


func _broke(c: Variant) -> bool:
	return not is_instance_valid(c) or (c as BreakableCrate).dead


## A mail box that broke (and may already be cleared away).
func _gone(m: Variant) -> bool:
	return not is_instance_valid(m) or (m as MailPackage).dead


func _blocked_by(prop: DecorProp) -> bool:
	## Does a body dropped on the piece get pushed out of it?
	var d := _dummy(prop.global_position + Vector3(0.15, 0.0, 0.0))
	var before := d.global_position
	d._separate()
	var moved := d.global_position.distance_to(before)
	d.free()
	return moved > 0.02


func setup() -> void:
	timeout_sec = 150.0
	_check_kinds()
	await _check_melee_and_blocking()
	await _check_hits()
	await _check_debris()
	_check_spawned_floor()
	await _check_mail_top_of_stack()
	finish()


func _check_kinds() -> void:
	check(RoomThemeDefs.is_breakable("crate_stack"), "crate_stack is a breakable decor kind")
	for k in ["barrel", "rack_cab", "specimen_shelf", "desk", "bunk_bed", "chains_cage", "tasting_table", "popcorn_machine", "dumbbell_rack"]:
		check(not RoomThemeDefs.is_breakable(k), "%s stays solid" % k)
	for k: String in RoomThemeDefs.BREAKABLE_DECOR:
		check(RoomThemeDefs.is_decor(k) and bool(RoomThemeDefs.decor(k)["blocks"]), "%s is a real blocking decor kind" % k)


# --- Melee, and the blocking going away -----------------------------------------------------

func _check_melee_and_blocking() -> void:
	_fresh()
	var crate_prop := _decor("crate_stack", Vector2(0.4, 0.0), 30.0)
	var rack_prop := _decor("rack_cab", Vector2(0.4, 3.0))
	var barrel_prop := _decor("barrel", Vector2(3.0, 3.0))
	var crate := crate_prop.breakable()
	check(crate != null, "a crate stack has a breakable part")
	check(crate.is_in_group("breakables") and crate.team == GameWorld.TEAM_NEUTRAL, "in the breakables group, neutral")
	near(crate.shove_mult, 0.0, 0.0001, "immovable")
	check(crate.max_hp <= 12.0, "low hp: one hit")
	eq(crate_prop.blockers.size(), 1, "one blocker circle")
	check(rack_prop.breakable() == null and barrel_prop.breakable() == null, "racks and barrels have no breakable part")
	check(not rack_prop.blockers[0].is_in_group("breakables") and not barrel_prop.blockers[0].is_in_group("breakables"), "and stay out of the group")
	check(_blocked_by(crate_prop), "the standing crate pushes a body out (it blocks)")
	check(_blocked_by(rack_prop), "so does a rack")
	var hero := _hero(Vector3(-1.0, 0.0, 0.0), "Wick")
	var watched := [null, 0]
	crate.broken.connect(func(_c: BreakableCrate, culprit: Node) -> void:
		watched[0] = culprit
		watched[1] = int(watched[1]) + 1)
	check(hero.melee(Vector3.RIGHT), "the swing fires")
	check(crate.dead and crate.broke, "a sword swing breaks the crate stack")
	eq(watched[0], hero, "the swinger is the culprit")
	crate.apply_damage(500.0, hero)
	crate.die()
	eq(int(watched[1]), 1, "it breaks exactly once")
	check(rack_prop.blockers[0] != null and not (rack_prop.blockers[0] as Actor).dead, "the rack is untouched")
	check(not _blocked_by(crate_prop), "the broken crate no longer blocks movement")
	check(_blocked_by(rack_prop), "the rack still does")
	check(not is_instance_valid(crate_prop.model) or crate_prop.model.is_queued_for_deletion(), "the crate model is gone")
	await frames(90)
	check(not is_instance_valid(crate), "the dead blocker is cleared away a second later")
	eq(Ledger.damages(), 0, "not property damage")
	eq(Ledger.lines.size(), 0, "no ledger line at all")
	# out of reach / behind the swing: untouched
	_fresh()
	crate = _decor("crate_stack", Vector2(2.5, 0.0)).breakable()
	hero = _hero(Vector3(-3.0, 0.0, 0.0), "Wick")
	hero.melee(Vector3.RIGHT)
	check(not crate.dead, "out of reach: not broken")
	hero.melee(Vector3.LEFT)
	check(not crate.dead, "behind the swing: not broken")


# --- Every other way to break one -------------------------------------------------------------

func _check_hits() -> void:
	# An area spell (corn hits every team).
	_fresh()
	var caster := _hero(Vector3(-4, 0, 0), "Gasket")
	var corn_prop := _decor("crate_stack", Vector2(2.0, 0.0))
	var neighbour := _decor("rack_cab", Vector2(2.0, 5.0))
	var corn := corn_prop.breakable()
	check(_blocked_by(corn_prop), "blocking before the spell")
	SpellBook.cast("corn", caster, 1.0, corn.global_position)
	await frames(int(CornStrike.DELAY * 60.0) + 25)
	check(_broke(corn), "corn breaks a crate stack")
	check(not _blocked_by(corn_prop), "and it stops blocking")
	check(not (neighbour.blockers[0] as Actor).dead, "the rack six cells away is untouched")
	eq(Ledger.damages(), 0, "corn on crates costs nothing")
	eq(Ledger.lines.size(), 0, "and adds no ledger line")
	# the fireball blast (team neutral)
	_fresh()
	caster = _hero(Vector3(-5, 0, 0), "Wick")
	var fire := _decor("crate_stack", Vector2(3.0, 0.0)).breakable()
	SpellBook.cast("fireball", caster, 1.0, fire.global_position)
	await frames(90)
	check(_broke(fire), "a fireball breaks a crate stack")
	eq(Ledger.damages(), 0, "no property damage")
	# tentacles
	_fresh()
	caster = _hero(Vector3(-5, 0, 0), "Rebar")
	var tent := _decor("crate_stack", Vector2(0.0, 0.0)).breakable()
	SpellBook.cast("tentacles", caster, 1.0, tent.global_position)
	await frames(120)
	check(_broke(tent), "tentacles break a crate stack")
	# an arrow and Wick's bolt
	_fresh()
	var wick := _hero(Vector3(-6, 0, 0), "Wick", "arrow")
	var shot := _decor("crate_stack", Vector2(0.0, 0.0)).breakable()
	check(wick.fire_arrow(Vector3.RIGHT, false), "the arrow flies")
	await frames(40)
	check(_broke(shot), "an arrow breaks a crate stack")
	_fresh()
	var bolter := _hero(Vector3(-6, 0, 0), "Wick", "bolt")
	var bolted := _decor("crate_stack", Vector2(0.0, 0.0)).breakable()
	check(bolter.shoot(Vector3.RIGHT), "the bolt flies")
	await frames(40)
	check(_broke(bolted), "Wick's bolt breaks a crate stack")
	# Gasket's spin
	_fresh()
	var gasket := _hero(Vector3(0, 0, 0), "Gasket", "spin")
	var spun := _decor("crate_stack", Vector2(1.3, 0.0)).breakable()
	check(gasket.shoot(Vector3.RIGHT), "the spin fires")
	check(_broke(spun), "Gasket's spin breaks a crate stack")
	# Rebar's bowl
	_fresh()
	var rebar := _hero(Vector3(-6, 0, 0), "Rebar", "bowl")
	rebar.shove_mult = 0.0
	var bowled := _decor("crate_stack", Vector2(-2.0, 0.1)).breakable()
	var missed := _decor("crate_stack", Vector2(-3.0, 6.0)).breakable()
	check(rebar.shoot(Vector3.RIGHT), "the bowl is thrown")
	await frames(120)
	check(_broke(bowled), "the bowl breaks the crate in its path")
	check(not _broke(missed), "off the path is untouched")
	# an actor shoved into one
	_fresh()
	var shover := _hero(Vector3(-6, 0, 3), "Rebar")
	var thug := _dummy(Vector3(0, 0, 0))
	var slammed := _decor("crate_stack", Vector2(2.0, 0.0)).breakable()
	var safe := _decor("crate_stack", Vector2(7.0, 0.0)).breakable()
	var who := [null]
	slammed.broken.connect(func(_c: BreakableCrate, culprit: Node) -> void: who[0] = culprit)
	thug.shove(Vector3.RIGHT, 2.5, shover)
	await frames(50)
	check(_broke(slammed), "a shoved actor breaks the crate stack it slams into")
	eq(who[0], shover, "the shover is the culprit")
	check(not _broke(safe), "a shove that does not reach it leaves it alone")
	eq(Ledger.damages(), 0, "not property damage")


# --- Debris, no loot ---------------------------------------------------------------------------

func _check_debris() -> void:
	_fresh()
	var pickups := get_tree().get_nodes_in_group("component_pickups").size()
	var prop := _decor("crate_stack", Vector2(0.0, 0.0))
	var crate := prop.breakable()
	var hero := _hero(Vector3(-4, 0, 0), "Wick")
	crate.apply_damage(5.0, hero)
	var spill := crate.spill
	check(spill != null and is_instance_valid(spill), "breaking leaves a spill of debris")
	check(spill.count_of("plank") >= 5, "planks (%d)" % spill.count_of("plank"))
	eq(spill.count_of("flap"), 0, "wood, not cardboard flaps")
	eq(get_tree().get_nodes_in_group(PackageSpill.GROUP).size(), 1, "one spill on the floor")
	var chips := 0
	for n in root.get_children():
		if n is PropDebris:
			chips += (n as PropDebris).shard_count()
	check(chips >= 8, "and splinters fly (%d)" % chips)
	eq(Ledger.lines.size(), 0, "no ledger line")
	eq(Ledger.earned(), 0, "no loot money")
	eq(get_tree().get_nodes_in_group("component_pickups").size(), pickups, "and no component drop")
	await frames(int(28.0 * 60.0))
	check(is_instance_valid(spill), "the planks are still there after 28 s")
	var shrinking := false
	for b in spill.bits:
		if b.node.scale.x < 0.95:
			shrinking = true
	check(shrinking, "and shrinking away near the end")
	await frames(int(3.0 * 60.0))
	check(not is_instance_valid(spill), "gone 30 s after the break")
	eq(get_tree().get_nodes_in_group(PackageSpill.GROUP).size(), 0, "no spill left")
	# the mail spills are untouched by the new kind: their flaps still come with every break
	var sp := PackageSpill.burst(Vector3.ZERO, "skulls", 3)
	eq(sp.count_of("flap"), PackageSpill.FLAPS, "a mail package spill still has its cardboard flaps")


# --- On a generated floor ----------------------------------------------------------------------

func _check_spawned_floor() -> void:
	var found := false
	for id in ClientArchetype.IDS:
		for s: int in [1, 3, 7, 42, 99, 1234]:
			if found:
				break
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.generate(run.floor_seed(f))
				var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
				var has := false
				for dc in plan.decor:
					if String(dc["kind"]) == "crate_stack":
						has = true
				if not has:
					continue
				found = true
				if root != null:
					root.free()
				root = Node3D.new()
				add_child(root)
				GameWorld.begin(map, root, 1)
				Ledger.begin_contract(1000000)
				var site := SiteBuilder.build(map, run, f)
				var crates := 0
				var solid := 0
				for n in site.decor:
					var dp := n as DecorProp
					if dp == null:
						continue
					if dp.kind == "crate_stack":
						crates += 1
						check(dp.breakable() != null and dp.breakable().is_in_group("breakables"), "a generated crate stack is breakable")
					elif dp.blockers.size() > 0:
						solid += 1
						check(dp.breakable() == null, "%s stays solid" % dp.kind)
				check(crates > 0, "the floor has crate stacks (%d)" % crates)
				break
	check(found, "found a generated floor with a crate stack")


# --- A top box of mail ---------------------------------------------------------------------------

func _check_mail_top_of_stack() -> void:
	_fresh()
	var hero := _hero(Vector3(-1.2, 0, 0), "Wick")
	var low := MailPackage.spawn(Vector2(0.2, 0.0), {"size": "medium", "seed": 41})
	var lift := PackageModels.height_of("medium")
	var mid := MailPackage.spawn(Vector2(0.2, 0.0), {"size": "medium", "lift": lift, "below": low, "stack": 1, "seed": 42})
	var top := MailPackage.spawn(Vector2(0.2, 0.0), {"size": "small", "lift": lift * 2.0, "below": mid, "stack": 2, "seed": 43})
	check(top.top_height() > 1.1, "a 3-stack stands over a metre tall (%.2f)" % top.top_height())
	hero.melee(Vector3.RIGHT)
	check(top.dead and mid.dead and low.dead, "one sword swing from the floor breaks all three, the top box included")
	# arrows take one box at a time, bottom first; every box of the stack can be hit
	_fresh()
	var wick := _hero(Vector3(-6, 0, 0), "Wick", "arrow")
	low = MailPackage.spawn(Vector2(0.0, 0.0), {"size": "medium", "seed": 51})
	mid = MailPackage.spawn(Vector2(0.0, 0.0), {"size": "medium", "lift": lift, "below": low, "stack": 1, "seed": 52})
	top = MailPackage.spawn(Vector2(0.0, 0.0), {"size": "small", "lift": lift * 2.0, "below": mid, "stack": 2, "seed": 53})
	for i in 3:
		wick.fire_arrow(Vector3.RIGHT, false)
		await frames(40)
	check(_gone(low) and _gone(mid) and _gone(top), "three arrows break the three boxes, the top one included")

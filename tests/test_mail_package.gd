extends TestCase
## Mail packages: the contents table, one hit of anything breaks a box (melee, Gasket's spin, arrows, bolts, corn,
## fireball, tentacles, Rebar's bowl, a shoved actor), breaking is NOT property damage, crypto cash lands on the
## invoice, a component drop stays out of the per-floor drop cap, decorative spills vanish after 30 s, stacks drop
## when the box below goes, and the placement on generated floors (4-6 spots, off corridors and the start / exit
## zones, deterministic, never on anything else planned).

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


func _box(pos: Vector3, opts: Dictionary = {}) -> MailPackage:
	var m := MailPackage.spawn(Vector2(pos.x, pos.z), opts)
	return m


## A box that remembers who broke it (the box itself is gone a second later).
func _watch(m: MailPackage) -> Array:
	var seen: Array = [null]
	m.broken.connect(func(_p: MailPackage, culprit: Node, _what: String) -> void: seen[0] = culprit)
	return seen


## Broken (and perhaps already cleared away: a dead box lingers a second, then frees itself).
func _broke(m: Variant) -> bool:
	return not is_instance_valid(m) or (m as MailPackage).dead


func _standing(m: Variant) -> bool:
	return is_instance_valid(m) and not (m as MailPackage).dead


func setup() -> void:
	timeout_sec = 150.0
	_check_table()
	await _check_basics()
	await _check_hits()
	await _check_contents()
	await _check_spill_lifetime()
	await _check_stack()
	_check_placement()
	await _check_spawn_on_floor()
	finish()


# --- The contents table -------------------------------------------------------------------

func _check_table() -> void:
	var sum := 0.0
	for e: Array in MailPackage.TABLE:
		sum += float(e[1])
	near(sum, 1.0, 0.0001, "the odds add up to 100%")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n := 20000
	var counts := {}
	for i in n:
		var c := MailPackage.roll_contents(rng)
		counts[c] = int(counts.get(c, 0)) + 1
	var want := {"skulls": 0.20, "yogurt": 0.20, "pickles": 0.20, "component": 0.25, "crypto": 0.15}
	eq(counts.size(), 5, "all five kinds of contents come up")
	for k: String in want:
		var got := float(counts.get(k, 0)) / float(n)
		near(got, float(want[k]), 0.015, "%s about %d%% (got %.3f)" % [k, int(float(want[k]) * 100.0), got])
	# the same seed rolls the same contents
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 9
	b.seed = 9
	var same := true
	for i in 50:
		if MailPackage.roll_contents(a) != MailPackage.roll_contents(b):
			same = false
	check(same, "roll_contents is pure: same seed, same contents")
	# crypto: $200-$2,000 in whole $10s, the whole range used
	var lo := 1 << 30
	var hi := 0
	var tens := true
	for i in 3000:
		var amt := MailPackage.roll_crypto(rng)
		lo = mini(lo, amt)
		hi = maxi(hi, amt)
		if amt % 10 != 0:
			tens = false
	check(tens, "crypto is rounded to $10")
	check(lo >= 200 and lo <= 260 and hi <= 2000 and hi >= 1940, "crypto spans $200-$2,000 (%d-%d)" % [lo, hi])
	# component picks are real, castable spells
	for i in 40:
		check(SpellBook.is_available(MailPackage.roll_component(rng)), "component drops a castable spell")


# --- The box itself ---------------------------------------------------------------------

func _check_basics() -> void:
	_fresh()
	for kind in PackageModels.KINDS:
		var m := _box(Vector3(float(PackageModels.KINDS.find(kind)) * 2.0 - 2.0, 0, 3.0), {"size": kind, "seed": 3})
		check(m != null, "%s box spawns" % kind)
		eq(m.team, GameWorld.TEAM_NEUTRAL, "%s: neutral" % kind)
		near(m.shove_mult, 0.0, 0.0001, "%s: immovable" % kind)
		check(m.max_hp <= 12.0 and m.is_in_group("breakables"), "%s: low hp, in the breakables group" % kind)
		var body := m.get_node_or_null("Model/Body") as MeshInstance3D
		check(body != null and body.mesh != null and body.mesh.get_surface_count() > 0, "%s has a model" % kind)
	var immovable := _box(Vector3(2, 0, 0))
	var at := immovable.global_position
	immovable.shove(Vector3.RIGHT, 3.0, null)
	await frames(30)
	near(immovable.global_position.distance_to(at), 0.0, 0.0001, "a box cannot be shoved")
	check(not immovable.dead, "and a shove alone does not break it")
	# any damage at all breaks it, and only once
	var hero := _hero(Vector3(-4, 0, 0))
	var weak := _box(Vector3(0, 0, -3), {"contents": "skulls"})
	var broke_count := [0]
	weak.broken.connect(func(_p: MailPackage, _c: Node, _what: String) -> void: broke_count[0] += 1)
	weak.apply_damage(0.2, hero)
	check(weak.dead and weak.broke, "even 0.2 damage breaks it")
	weak.apply_damage(500.0, hero)
	weak.die()
	eq(int(broke_count[0]), 1, "it breaks exactly once")
	eq(weak.contents, "skulls", "forced contents are honoured")
	eq(weak.last_culprit(), hero, "the hitter is the culprit")


# --- Every way to break one --------------------------------------------------------------

func _check_hits() -> void:
	# Hero melee (primary), and it still leaves priced props and employees alone.
	_fresh()
	var hero := _hero(Vector3(-1.2, 0, 0), "Wick")
	var pkg := _box(Vector3(0.3, 0, 0), {"contents": "skulls"})
	var prop := PricedProp.spawn(Hex.from_world(Vector3(0.6, 0, 1.2)), "wine_rack", {"pos": Vector2(0.6, 1.2)})
	var prop_hp := prop.hp
	check(hero.melee(Vector3.RIGHT), "the swing fires")
	check(pkg.dead, "a melee swing breaks a package")
	near(prop.hp, prop_hp, 0.0001, "melee still does not touch priced props")
	eq(Ledger.damages(), 0, "breaking mail is not property damage")
	# Out of reach / outside the arc: untouched
	_fresh()
	hero = _hero(Vector3(-4, 0, 0), "Wick")
	var far_pkg := _box(Vector3(0.5, 0, 0))
	var side_pkg := _box(Vector3(-4, 0, 1.3))
	hero.melee(Vector3.RIGHT)
	check(not far_pkg.dead and not side_pkg.dead, "out of reach, or behind the swing: not broken")
	# Gasket's spin hits all around.
	_fresh()
	var gasket := _hero(Vector3(0, 0, 0), "Gasket", "spin")
	var around_a := _box(Vector3(1.0, 0, 0))
	var around_b := _box(Vector3(-1.0, 0, 0.6))
	check(gasket.shoot(Vector3.RIGHT), "the spin fires")
	check(around_a.dead and around_b.dead, "Gasket's spin breaks the boxes around him")
	# A monster's swing breaks one too (it only strikes at heroes, the box just stands in the arc).
	_fresh()
	var victim := _hero(Vector3(0, 0, 0), "Wick")
	var grunt := MonsterFactory.spawn("grunt", Hex.from_world(Vector3(1.4, 0, 0)))
	var in_arc := _box(Vector3(0.7, 0, 0.0))
	Combat.melee_arc(grunt, Vector3.LEFT, 1.6, 100.0, 5.0)
	check(in_arc.dead, "a monster's swing breaks a box in its arc")
	check(victim.hp < victim.max_hp, "and still hits the hero")
	# Arrows (tap and drawn), the weak bolt.
	_fresh()
	var wick := _hero(Vector3(-6, 0, 0), "Wick", "arrow")
	var shot_at := _box(Vector3(0, 0, 0))
	var behind_prop := PricedProp.spawn(Hex.from_world(Vector3(3, 0, 0)), "wine_rack", {"pos": Vector2(3, 0)})
	check(wick.fire_arrow(Vector3.RIGHT, false), "the arrow flies")
	await frames(40)
	check(_broke(shot_at), "an arrow breaks a package")
	near(behind_prop.hp, behind_prop.max_hp, 0.0001, "and the arrow never reaches the prop behind it")
	eq(Ledger.damages(), 0, "no property damage from the arrow")
	_fresh()
	var bolter := _hero(Vector3(-6, 0, 0), "Wick", "bolt")
	var bolted := _box(Vector3(0, 0, 0))
	check(bolter.shoot(Vector3.RIGHT), "the bolt flies")
	await frames(40)
	check(_broke(bolted), "Wick's bolt breaks a package")
	# An area spell (corn hits every team) and the fireball blast (team neutral), then tentacles.
	_fresh()
	var caster := _hero(Vector3(-4, 0, 0), "Gasket")
	var corn_pkg := _box(Vector3(2, 0, 0))
	SpellBook.cast("corn", caster, 1.0, corn_pkg.global_position)
	await frames(int(CornStrike.DELAY * 60.0) + 25)
	check(_broke(corn_pkg), "corn breaks a package")
	eq(Ledger.damages(), 0, "corn on mail costs nothing")
	_fresh()
	caster = _hero(Vector3(-5, 0, 0), "Wick")
	var fire_pkg := _box(Vector3(3, 0, 0))
	var fire_stack_top := _box(Vector3(3.3, 0, 0.3), {"lift": 0.6})
	SpellBook.cast("fireball", caster, 1.0, fire_pkg.global_position)
	await frames(90)
	check(_broke(fire_pkg), "a fireball breaks a package")
	check(_broke(fire_stack_top), "and a second box in the blast")
	near(caster.hp, caster.max_hp, 0.001, "the caster is unhurt")
	_fresh()
	caster = _hero(Vector3(-5, 0, 0), "Rebar")
	var tent_pkg := _box(Vector3(0, 0, 0))
	SpellBook.cast("tentacles", caster, 1.0, tent_pkg.global_position)
	await frames(120)
	check(_broke(tent_pkg), "tentacles break a package")
	_fresh()
	caster = _hero(Vector3(-5, 0, 0), "Wick")
	var teeth_pkg := _box(Vector3(0, 0, 0))
	SpellBook.cast("teeth", caster, 1.0, teeth_pkg.global_position)
	await frames(240)
	check(_broke(teeth_pkg), "a teeth pop breaks a package")
	# Rebar's bowl rolls through.
	_fresh()
	var rebar := _hero(Vector3(-6, 0, 0), "Rebar", "bowl")
	rebar.shove_mult = 0.0
	var bowled := _box(Vector3(-2.0, 0, 0.1))
	var missed := _box(Vector3(-3, 0, 6.0))
	var bowl_culprit := _watch(bowled)
	check(rebar.shoot(Vector3.RIGHT), "the bowl is thrown")
	await frames(120)
	check(_broke(bowled), "the bowl breaks the package in its path")
	check(_standing(missed), "off the path is untouched")
	eq(bowl_culprit[0], rebar, "Rebar gets the credit")
	# An actor shoved into a box breaks it, credited to the shover.
	_fresh()
	var shover := _hero(Vector3(-6, 0, 3), "Rebar")
	var thug := _dummy(Vector3(0, 0, 0))
	var crate := _box(Vector3(2.0, 0, 0))
	var safe := _box(Vector3(7.0, 0, 0))
	var crate_culprit := _watch(crate)
	thug.shove(Vector3.RIGHT, 2.5, shover)
	await frames(50)
	check(_broke(crate), "a shoved actor breaks the box it slams into")
	eq(crate_culprit[0], shover, "the shover is the culprit")
	check(_standing(safe), "a shove that does not reach it leaves it alone")
	eq(Ledger.damages(), 0, "and it is not property damage")


# --- Contents and what they do ---------------------------------------------------------------

func _check_contents() -> void:
	# Crypto: earns on the invoice with the culprit, never a damage line.
	_fresh()
	var hero := _hero(Vector3(-4, 0, 0), "Wick")
	var money := _box(Vector3(0, 0, 0), {"contents": "crypto", "seed": 77})
	money.apply_damage(5.0, hero)
	check(money.crypto_amount >= 200 and money.crypto_amount <= 2000 and money.crypto_amount % 10 == 0, "crypto amount in range (%d)" % money.crypto_amount)
	eq(Ledger.earned(), money.crypto_amount, "the invoice earns exactly that")
	eq(Ledger.damages(), 0, "and no damage line")
	eq(Ledger.lines.size(), 1, "one line")
	var line: Dictionary = Ledger.lines[0]
	eq(String(line["kind"]), "earn", "an earning")
	eq(String(line["label"]), "Unclaimed crypto (intercepted mail)", "the label")
	eq(String(line["who"]), "Wick", "credited to whoever broke it")
	var pop_found := false
	for n in root.get_children():
		var lbl := n as Label3D
		if lbl != null and lbl.text.contains("crypto") and lbl.text.begins_with("+$"):
			pop_found = true
			eq(lbl.text, "+%s crypto" % PricedProp.money(money.crypto_amount), "the floating text")
	check(pop_found, "a floating '+$... crypto' pop appears")
	# A component drop: a real pickup, outside the monsters' per-floor cap.
	_fresh()
	GameWorld.floor_drops = 3
	var pickups_before := get_tree().get_nodes_in_group("component_pickups").size()
	var parcel := _box(Vector3(1, 0, 1), {"contents": "component", "seed": 5})
	parcel.apply_damage(5.0, null)
	eq(GameWorld.floor_drops, 3, "a component from mail does not count toward the drop cap")
	check(parcel.pickup != null and is_instance_valid(parcel.pickup), "a pickup was left")
	eq(get_tree().get_nodes_in_group("component_pickups").size(), pickups_before + 1, "exactly one new pickup")
	check(SpellBook.has_spell(parcel.component_id) and parcel.pickup.spell_id == parcel.component_id, "it is a real spell's component")
	eq(parcel.pickup.charges, SpellComponents.PICKUP_CHARGES, "a normal 3-charge pickup")
	eq(Ledger.lines.size(), 0, "no money for a component")
	# The cap itself still applies to monsters at the same time.
	GameWorld.floor_drops = SpellComponents.FLOOR_DROP_CAP
	var again := _box(Vector3(-1, 0, 1), {"contents": "component", "seed": 6})
	again.apply_damage(5.0, null)
	check(again.pickup != null, "even with the monster cap full, mail still drops a component")
	eq(GameWorld.floor_drops, SpellComponents.FLOOR_DROP_CAP, "and the counter is untouched")
	# Decorative contents: bits of the right kind, flaps every time, nothing on the invoice.
	_fresh()
	var skulls := _box(Vector3(-3, 0, 0), {"contents": "skulls", "seed": 1})
	var yogurt := _box(Vector3(0, 0, 0), {"contents": "yogurt", "seed": 2})
	var pickles := _box(Vector3(3, 0, 0), {"contents": "pickles", "seed": 3})
	for m in [skulls, yogurt, pickles]:
		(m as MailPackage).apply_damage(5.0, null)
	var spill_s := skulls.spill
	var spill_y := yogurt.spill
	var spill_p := pickles.spill
	check(spill_s != null and spill_y != null and spill_p != null, "each decorative break leaves a spill")
	var s_count := spill_s.count_of("skull")
	check(s_count >= 3 and s_count <= 5, "a pile of skulls (%d)" % s_count)
	var tubs := spill_y.count_of("tub")
	check(tubs >= 4 and tubs <= 6 and spill_y.count_of("lid") >= 2, "tubs of yogurt with lids (%d)" % tubs)
	var pk := spill_p.count_of("pickle")
	check(pk >= 5 and pk <= 8, "loose pickles (%d)" % pk)
	for sp in [spill_s, spill_y, spill_p]:
		eq((sp as PackageSpill).count_of("flap"), PackageSpill.FLAPS, "cardboard flaps every time")
	eq(Ledger.lines.size(), 0, "decorative contents are free and earn nothing")
	eq(get_tree().get_nodes_in_group("component_pickups").size(), pickups_before, "and drop nothing")
	await frames(240)
	for b in spill_s.bits:
		var on_floor: bool = b.rest and absf(b.node.position.y) < 0.2
		check(on_floor, "every skull and flap is lying on the floor after 4 s")
	var inside := true
	for sp in [spill_s, spill_y, spill_p]:
		for b in (sp as PackageSpill).bits:
			if GameWorld.map.get_cell(Hex.from_world(b.node.global_position)) == null:
				inside = false
	check(inside, "no bit rolled off the map")
	# Breaking is deterministic from the box's own seed: same seed, same contents when none is forced.
	_fresh()
	var rolled := {}
	for i in 12:
		var m := _box(Vector3(float(i % 6) * 1.5 - 4.0, 0, floorf(float(i) / 6.0) * 2.0 - 1.0), {"seed": 1000 + i})
		m.apply_damage(5.0, null)
		rolled[i] = m.contents
		check(["skulls", "yogurt", "pickles", "component", "crypto"].has(m.contents), "a box with no forced contents rolls one of the five")
	var first_rng := RandomNumberGenerator.new()
	first_rng.seed = 1000
	eq(String(rolled[0]), MailPackage.roll_contents(first_rng), "a box rolls from its own seed")


func _check_spill_lifetime() -> void:
	_fresh()
	var a := _box(Vector3(-2, 0, 0), {"contents": "yogurt", "seed": 8})
	var b := _box(Vector3(2, 0, 0), {"contents": "skulls", "seed": 9})
	a.apply_damage(5.0, null)
	b.apply_damage(5.0, null)
	var spills := [a.spill, b.spill]
	eq(get_tree().get_nodes_in_group(PackageSpill.GROUP).size(), 2, "two spills on the floor")
	await frames(int(28.0 * 60.0))
	check(is_instance_valid(spills[0]) and is_instance_valid(spills[1]), "still there after 28 s")
	var shrinking := false
	for bit in (spills[0] as PackageSpill).bits:
		if bit.node.scale.x < 0.95:
			shrinking = true
	check(shrinking, "and shrinking away near the end")
	await frames(int(3.0 * 60.0))
	check(not is_instance_valid(spills[0]) and not is_instance_valid(spills[1]), "gone 30 s after the break")
	eq(get_tree().get_nodes_in_group(PackageSpill.GROUP).size(), 0, "no spill left")
	check(not is_instance_valid(a) and not is_instance_valid(b), "and the dead boxes are gone too")


func _check_stack() -> void:
	_fresh()
	var hero := _hero(Vector3(-4, 0, 0), "Wick")
	var low := _box(Vector3(0, 0, 0), {"size": "medium", "seed": 21, "contents": "skulls"})
	var lift := PackageModels.height_of("medium")
	var mid := _box(Vector3(0, 0, 0), {"size": "medium", "lift": lift, "below": low, "stack": 1, "seed": 22, "contents": "skulls"})
	var top := _box(Vector3(0, 0, 0), {"size": "small", "lift": lift * 2.0, "below": mid, "stack": 2, "seed": 23, "contents": "skulls"})
	await frames(5)
	near(mid.model_lift(), lift, 0.001, "the second box rests on the first")
	near(top.model_lift(), lift * 2.0, 0.001, "and the third on the second")
	check(top.top_height() > mid.top_height() and mid.top_height() > low.top_height(), "taller with every box")
	mid.apply_damage(3.0, hero)
	check(mid.dead and not low.dead and not top.dead, "each box is its own breakable")
	await frames(40)
	near(top.model_lift(), PackageModels.height_of("medium"), 0.02, "the top box drops onto the one below (%.2f)" % top.model_lift())
	low.apply_damage(3.0, hero)
	await frames(60)
	near(top.model_lift(), 0.0, 0.02, "and falls to the floor when that goes too (%.2f)" % top.model_lift())
	check(not top.dead, "falling alone does not break it")
	# a melee swing takes the whole stack at once
	_fresh()
	var h2 := _hero(Vector3(-1.2, 0, 0), "Gasket")
	var s1 := _box(Vector3(0.2, 0, 0), {"size": "long", "seed": 31})
	var s2 := _box(Vector3(0.2, 0, 0), {"size": "small", "lift": PackageModels.height_of("long"), "below": s1, "stack": 1, "seed": 32})
	h2.melee(Vector3.RIGHT)
	check(s1.dead and s2.dead, "one swing breaks a whole stack")


# --- Placement ---------------------------------------------------------------------------------

const SEEDS: Array[int] = [1, 3, 7, 42, 99, 1234]


func _check_placement() -> void:
	var spots_seen := {}
	var stacks_seen := {}
	var sizes_seen := {}
	for id in ClientArchetype.IDS:
		for s in SEEDS:
			var run := ContractRun.make(id, s, float(s % 10) / 10.0 + 0.05)
			var catalog := ContractParts.prop_catalog(run.site_type)
			for f in range(1, ContractRun.FLOOR_COUNT + 1):
				var map := DungeonGen.generate(run.floor_seed(f))
				var plan := SiteBuilder.plan(map, run, f, catalog)
				_check_plan(map, plan, "%s/%d floor %d" % [id, s, f])
				spots_seen[plan.packages.size()] = true
				for pk in plan.packages:
					stacks_seen[int(pk["stack"])] = true
					for k: String in pk["sizes"]:
						sizes_seen[k] = true
	var lo := 99
	var hi := 0
	for n: int in spots_seen:
		lo = mini(lo, n)
		hi = maxi(hi, n)
	check(lo >= 4 and hi <= 6, "every floor has 4-6 spots (saw %d-%d)" % [lo, hi])
	check(hi > lo, "and the count varies between floors")
	check(stacks_seen.has(1) and stacks_seen.has(2) and stacks_seen.has(3), "single boxes and stacks of 2 and 3 all occur")
	eq(sizes_seen.size(), 3, "small, medium and long boxes all occur")
	# deterministic: the same (contract, floor) plans the same spots; a different contract does not
	var run2 := ContractRun.make("supervillain", 31, 0.7)
	var catalog2 := ContractParts.prop_catalog(run2.site_type)
	for f in range(1, 4):
		var a := SiteBuilder.plan(DungeonGen.generate(run2.floor_seed(f)), run2, f, catalog2)
		var b := SiteBuilder.plan(DungeonGen.generate(run2.floor_seed(f)), run2, f, catalog2)
		eq(str(a.packages), str(b.packages), "package plan for floor %d is deterministic" % f)
		eq(str([a.props, a.decor, a.gates, a.employees, a.notes, a.pack_budgets]), str([b.props, b.decor, b.gates, b.employees, b.notes, b.pack_budgets]), "and so is the rest of the plan")
	var other := ContractRun.make("supervillain", 32, 0.7)
	var pa := SiteBuilder.plan(DungeonGen.generate(run2.floor_seed(2)), run2, 2, catalog2)
	var pb := SiteBuilder.plan(DungeonGen.generate(other.floor_seed(2)), other, 2, catalog2)
	check(str(pa.packages) != str(pb.packages), "a different contract puts the mail elsewhere")


func _check_plan(map: HexMap, plan: SitePlan, tag: String) -> void:
	var n := plan.packages.size()
	check(n >= 4 and n <= 6, "%s: 4-6 package spots (got %d)" % [tag, n])
	var corridor_cells: Array[Vector2i] = []
	for cc: Vector2i in map.cells:
		if map.cells[cc].tag == "corridor":
			corridor_cells.append(cc)
	var taken: Array[Vector2i] = []
	for pk in plan.packages:
		var c: Vector2i = pk["cell"]
		var cell: HexMap.Cell = map.get_cell(c)
		check(cell != null and cell.type == HexMap.Tile.FLOOR, "%s: package %s on floor" % [tag, c])
		if cell == null:
			continue
		check(cell.tag.begins_with("room:") and cell.tag != "corridor", "%s: package %s is in a room, not a corridor" % [tag, c])
		check(plan.room_of_cell(c) == str(pk["room"]), "%s: package %s is in its room" % [tag, c])
		check(Hex.distance(c, plan.start) > SiteBuilder.START_CLEAR, "%s: package %s clear of the start" % [tag, c])
		check(Hex.distance(c, plan.exit) > SiteBuilder.EXIT_CLEAR, "%s: package %s clear of the exit" % [tag, c])
		var near_corridor := 99
		for cc in corridor_cells:
			near_corridor = mini(near_corridor, Hex.distance(c, cc))
		check(near_corridor >= SiteBuilder.PACKAGE_DOOR_MIN and near_corridor <= SiteBuilder.PACKAGE_DOOR_MAX + 1,
				"%s: package %s is %d cells from a corridor (2-7: near a door, not in it)" % [tag, c, near_corridor])
		var by_wall := false
		for d in Hex.DIRS:
			var nb: HexMap.Cell = map.get_cell(c + d)
			if nb != null and nb.type == HexMap.Tile.WALL:
				by_wall = true
		check(by_wall, "%s: package %s stands against a wall" % [tag, c])
		var st := int(pk["stack"])
		check(st >= 1 and st <= 3 and (pk["sizes"] as Array).size() == st and (pk["twists"] as Array).size() == st and (pk["shifts"] as Array).size() == st, "%s: stack %d is described level by level" % [tag, st])
		check(plan.blocked.has(c), "%s: package %s is in plan.blocked (no monster spawns inside it)" % [tag, c])
		for g in plan.gates:
			check(Hex.distance(c, g["cell"]) > 3, "%s: package %s well clear of a hellgate" % [tag, c])
		for e in plan.employees:
			check(Hex.distance(c, e["cell"]) >= 1 and c != e["cell"], "%s: package %s not on an employee" % [tag, c])
		for nt in plan.notes:
			check(c != nt["cell"], "%s: package %s not on the clue note" % [tag, c])
		for t in taken:
			check(Hex.distance(c, t) >= 2, "%s: spots %s and %s are apart" % [tag, c, t])
		taken.append(c)
		# not on top of priced props or decor
		var pos: Vector2 = pk["pos"]
		var yaw: float = pk["yaw"]
		var dims := PackageModels.size_of(String((pk["sizes"] as Array)[0]))
		for pr in plan.props:
			var foot: Vector2 = pr["foot"]
			check(not ThemeGeo.overlap(pos, yaw, dims.x, dims.z, pr["pos"], pr["yaw"], foot.x, foot.y, 0.0), "%s: package %s clear of the %s" % [tag, c, pr["kind"]])
		for dc in plan.decor:
			if bool(dc["blocks"]):
				check(not ThemeGeo.overlap(pos, yaw, dims.x, dims.z, dc["pos"], dc["yaw"], float(dc["w"]), float(dc["d"]), 0.0), "%s: package %s clear of %s" % [tag, c, dc["kind"]])


func _check_spawn_on_floor() -> void:
	var run := ContractRun.make("prepper", 3, 0.5)
	var map := DungeonGen.generate(run.floor_seed(1))
	var world := Node3D.new()
	add_child(world)
	GameWorld.begin(map, world, 1)
	var site := SiteBuilder.build(map, run, 1)
	var boxes := 0
	for pk in site.plan.packages:
		boxes += int(pk["stack"])
	eq(site.packages.size(), boxes, "every box of every stack is spawned")
	var all_ok := true
	for a in site.packages:
		var m := a as MailPackage
		if m == null or m.team != GameWorld.TEAM_NEUTRAL or not m.is_in_group("breakables"):
			all_ok = false
	check(all_ok and boxes >= 4, "they are MailPackages in the breakables group (%d boxes)" % boxes)
	var cells := {}
	for pk in site.plan.packages:
		cells[pk["cell"]] = true
	var monster_inside := false
	for mo in site.monsters:
		if cells.has(Hex.from_world(mo.global_position)):
			monster_inside = true
	check(not monster_inside, "no monster spawned on a package cell")
	# a stack's boxes sit one above the other
	for pk in site.plan.packages:
		if int(pk["stack"]) >= 2:
			var boxes_here: Array[MailPackage] = []
			for a in site.packages:
				var m := a as MailPackage
				if GameWorld.flat_distance(m.global_position, Vector3((pk["pos"] as Vector2).x, 0, (pk["pos"] as Vector2).y)) < 0.2:
					boxes_here.append(m)
			eq(boxes_here.size(), int(pk["stack"]), "the stack's boxes share its spot")
			if boxes_here.size() >= 2:
				check(boxes_here[1].model_lift() > boxes_here[0].model_lift(), "and the second sits higher")
			break
	await get_tree().physics_frame
	GameWorld.end()

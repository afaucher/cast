extends TestCase
## Priced props: neutral + immovable, one catalog table, partial damage is free and breaking costs
## the full price exactly once (culprit named), the damage sources (area / fireball / shove / bowl),
## the price tag near heroes, and the live damage ticker.

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


func _prop(kind: String, pos: Vector3, opts: Dictionary = {}) -> PricedProp:
	var cell := Hex.from_world(pos)
	var p := PricedProp.spawn(cell, kind, opts)
	# park it exactly where the test wants it
	p.global_position = Vector3(pos.x, p.global_position.y, pos.z)
	return p


func setup() -> void:
	_fresh()

	# --- Catalog: both site types, ~8 each, every entry priced and built.
	var bunker := PricedProp.catalog("bunker")
	var lair := PricedProp.catalog("lair")
	check(bunker.size() >= 7 and bunker.size() <= 10, "bunker catalog has about 8 props (%d)" % bunker.size())
	check(lair.size() >= 7 and lair.size() <= 10, "lair catalog has about 8 props (%d)" % lair.size())
	eq(PricedProp.catalog("spaceship").size(), 0, "unknown site: empty catalog")
	check("gold_toilet" in bunker and "doomsday_console" in lair, "the headline props are in")
	var names := {}
	var i := 0
	for kind: String in bunker + lair:
		check(PricedProp.price_of(kind) > 0, "%s has a price" % kind)
		var p := _prop(kind, Vector3(-9.0 + 2.2 * float(i % 9), 0, -3.0 + 6.0 * floorf(float(i) / 9.0)))
		check(p != null, "%s spawns" % kind)
		i += 1
		if p == null:
			continue
		eq(p.team, GameWorld.TEAM_NEUTRAL, "%s is neutral" % kind)
		near(p.shove_mult, 0.0, 0.0001, "%s is immovable" % kind)
		check(p.max_hp > 0.0 and p.price == PricedProp.price_of(kind), "%s hp and price from the table" % kind)
		var body := p.get_node_or_null("Model/Body") as MeshInstance3D
		check(body != null and body.mesh != null and body.mesh.get_surface_count() > 0, "%s has a model" % kind)
		check(not names.has(p.display_name), "%s: unique display name" % kind)
		names[p.display_name] = true
	check(PricedProp.spawn(Vector2i.ZERO, "no_such_prop") == null, "unknown kind spawns nothing")
	eq(PricedProp.money(4000), "$4,000", "money format")
	eq(PricedProp.money(20000), "$20,000", "money format 20k")
	eq(PricedProp.money(300), "$300", "money format 300")
	eq(PricedProp.money(1500000), "$1,500,000", "money format millions")
	eq(Ledger.lines.size(), 0, "spawning costs nothing")

	# --- Immovable: a shove does nothing; neutral team.
	_fresh()
	var rack := _prop("wine_rack", Vector3(2, 0, 0))
	var at := rack.global_position
	rack.shove(Vector3.RIGHT, 3.0, null)
	await frames(30)
	near(rack.global_position.distance_to(at), 0.0, 0.0001, "a prop cannot be shoved")
	eq(rack.team, GameWorld.TEAM_NEUTRAL, "neutral")

	# --- Partial damage is free; breaking costs the full price once, naming the culprit.
	_fresh()
	var hero := _hero(Vector3(-4, 0, 0), "Wick")
	var barrel := _prop("wine_barrel", Vector3(2, 0, 0))
	eq(barrel.display_name, "Vintage 1787 wine barrel", "barrel name")
	eq(barrel.price, 4000, "barrel price")
	barrel.apply_damage(barrel.max_hp * 0.5, hero)
	eq(Ledger.lines.size(), 0, "partial damage costs nothing")
	eq(Ledger.damages(), 0, "ledger still clean")
	check(not barrel.broke and not barrel.dead, "still standing")
	barrel.apply_damage(barrel.max_hp, hero)
	check(barrel.broke and barrel.dead, "broken")
	eq(Ledger.lines.size(), 1, "breaking records exactly one ledger line")
	var line: Dictionary = Ledger.lines[0]
	eq(String(line["kind"]), "damage", "a damage line")
	eq(int(line["amount"]), 4000, "the full price")
	eq(String(line["label"]), "Vintage 1787 wine barrel", "the display name")
	eq(String(line["who"]), "Wick", "the culprit is named")
	barrel.apply_damage(500.0, hero)
	barrel.die()
	eq(Ledger.lines.size(), 1, "never charged twice")
	await frames(5)
	check(is_instance_valid(barrel) and barrel.get_node_or_null("Rubble") != null, "a rubble remnant is left")
	check(barrel.get_node_or_null("Model") == null or barrel.get_node("Model").is_queued_for_deletion(), "the model is gone")
	# A demon as the culprit is named "demons"; no culprit stays blank.
	var lamp := _prop("crystal_lamp", Vector3(0, 0, 5))
	lamp.apply_damage(100.0, null)
	eq(String(Ledger.lines[1]["who"]), "", "unknown culprit")
	var lamp2 := _prop("crystal_lamp", Vector3(0, 0, -5))
	var imp := MonsterFactory.spawn("swarmer", Vector2i(3, 3))
	lamp2.apply_damage(5.0, imp)
	lamp2.apply_damage(100.0, null)    # a null source keeps the last known culprit
	eq(String(Ledger.lines[2]["who"]), "demons", "the last real source is blamed")

	# --- Area effects that hit team -1 break it (corn, teeth, explosions go through Combat.explode).
	_fresh()
	hero = _hero(Vector3(-6, 0, 0), "Wick")
	var bust := _prop("marble_statue", Vector3(0, 0, 0))
	var vase := _prop("crystal_lamp", Vector3(1.0, 0, 1.0))
	Combat.explode(bust.global_position, 3.0, 50.0, -1, hero, 1.0)
	check(vase.dead and not bust.dead, "explode(team -1) breaks the fragile lamp, the marble statue survives 50")
	eq(Ledger.lines.size(), 1, "one line so far")
	Combat.explode(bust.global_position, 3.0, 80.0, -1, hero, 1.0)
	check(bust.dead, "and a second blast breaks the statue")
	eq(Ledger.damages(), 600 + 8000, "lamp + statue")
	eq(String(Ledger.lines[1]["who"]), "Wick", "credited to the caster")

	# Real corn strike.
	_fresh()
	hero = _hero(Vector3(-4, 0, 0), "Gasket")
	var console := _prop("projector", Vector3(2, 0, 0))
	SpellBook.cast("corn", hero, 1.0, console.global_position)
	await frames(int(CornStrike.DELAY * 60.0) + 25)
	check(console.dead, "corn breaks a projector")
	eq(Ledger.lines.size(), 1, "corn: one line")
	eq(String(Ledger.lines[0]["who"]), "Gasket", "corn: the caster pays")

	# --- Fireball hits props but still not heroes.
	_fresh()
	hero = _hero(Vector3(-5, 0, 0), "Wick")
	var buddy := _hero(Vector3(3.2, 0, 1.2), "Rebar")
	var wine := _prop("wine_rack", Vector3(3, 0, 0))                  # 45 hp: one blast (40) dents it
	var statue := _prop("marble_statue", Vector3(3, 0, -1.4))         # 110 hp
	SpellBook.cast("fireball", hero, 1.0, wine.global_position)
	await frames(90)
	near(wine.hp, wine.max_hp - SpellBook.fireball_damage(1.0), 0.01, "fireball damages a prop")
	near(statue.hp, statue.max_hp - SpellBook.fireball_damage(1.0), 0.01, "and a second prop in the blast")
	near(buddy.hp, buddy.max_hp, 0.001, "fireball still spares heroes")
	near(hero.hp, hero.max_hp, 0.001, "and the caster")
	eq(Ledger.lines.size(), 0, "dented props cost nothing")
	SpellBook.cast("fireball", hero, 1.0, wine.global_position)
	await frames(90)
	check(wine.dead, "a second fireball breaks the rack")
	eq(Ledger.lines.size(), 1, "one line for the rack")
	eq(String(Ledger.lines[0]["who"]), "Wick", "the caster is the culprit")
	eq(int(Ledger.lines[0]["amount"]), 1200, "wine rack price")

	# --- Fireball hits every neutral actor: an Employee in the blast is hurt, a hero is not.
	_fresh()
	hero = _hero(Vector3(-5, 0, 0), "Wick")
	var bystander := _hero(Vector3(3.0, 0, 1.6), "Gasket")
	var worker := Employee.spawn(Hex.from_world(Vector3(3, 0, 0)), {"style": "staff"})
	worker.global_position = Vector3(3, worker.global_position.y, 0)
	var worker_hp := worker.hp
	SpellBook.cast("fireball", hero, 1.0, Vector3(3, 0, 0))
	await frames(90)
	check(worker.hp < worker_hp or worker.dead, "a fireball explosion damages a nearby Employee")
	near(bystander.hp, bystander.max_hp, 0.001, "and still spares the hero beside it")

	# --- An actor shoved into a prop damages it, crediting the shover.
	_fresh()
	hero = _hero(Vector3(-6, 0, 3), "Rebar")
	var thug := _dummy(Vector3(0, 0, 0))
	var crate := _prop("wine_rack", Vector3(2.4, 0, 0))
	var hp0 := crate.hp
	thug.shove(Vector3.RIGHT, 3.0, hero)
	await frames(50)
	check(crate.hp < hp0, "a shoved actor damages the prop it slams into (%.1f -> %.1f)" % [hp0, crate.hp])
	check(hp0 - crate.hp > 10.0, "damage scales with the shove (%.1f)" % (hp0 - crate.hp))
	eq(crate.last_culprit(), hero, "the shover is the culprit")
	near(thug.global_position.distance_to(crate.global_position), thug.radius + crate.radius, 0.6, "it stopped at the prop")
	# A bigger shove into a fragile prop breaks it and bills the shover.
	_fresh()
	hero = _hero(Vector3(-6, 0, 3), "Rebar")
	var thug2 := _dummy(Vector3(0, 0, 0))
	var glass := _prop("evil_portrait", Vector3(2.4, 0, 0))
	thug2.shove(Vector3.RIGHT, 5.0, hero)
	await frames(50)
	check(glass.dead, "a hard shove breaks the portrait")
	eq(Ledger.lines.size(), 1, "one line")
	eq(String(Ledger.lines[0]["who"]), "Rebar", "the shover pays")
	eq(int(Ledger.lines[0]["amount"]), 2000, "portrait price")
	# A shove that does not reach the prop leaves it alone.
	_fresh()
	var thug3 := _dummy(Vector3(0, 0, 0))
	var safe := _prop("evil_portrait", Vector3(7.0, 0, 0))
	thug3.shove(Vector3.RIGHT, 2.5, null)
	await frames(50)
	near(safe.hp, safe.max_hp, 0.0001, "no contact, no damage")

	# --- The bowl rolls through props and damages them.
	_fresh()
	var rebar := _hero(Vector3(-6, 0, 0), "Rebar", "bowl")
	rebar.shove_mult = 0.0
	var proj := _prop("projector", Vector3(-2.0, 0, 0.1))     # 35 hp: bowl does 6 x 6 = 36
	var far_prop := _prop("projector", Vector3(-3, 0, 6.5))
	var past := _prop("projector", Vector3(8.5, 0, 0))
	check(rebar.shoot(Vector3.RIGHT), "the bowl is thrown")
	await frames(150)
	check(proj.dead, "the bowl breaks the projector in its path")
	eq(String(Ledger.lines[0]["who"]), "Rebar", "Rebar pays for it")
	near(far_prop.hp, far_prop.max_hp, 0.0001, "off the path is untouched")
	near(past.hp, past.max_hp, 0.0001, "past the range is untouched")
	near(proj.global_position.x, -2.0, 0.001, "a prop does not roll away")

	# --- Price tag: only near a hero.
	_fresh()
	var statue2 := _prop("gold_toilet", Vector3(0, 0, 0))
	await frames(20)
	check(not statue2.tag_shown() and statue2.tag_alpha() < 0.01, "no hero around: no tag")
	eq(statue2.tag_text(), "Gold toilet – $15,000", "tag text")
	var walker := _hero(Vector3(2.6, 0, 0), "Wick")
	await frames(40)
	check(statue2.tag_shown() and statue2.tag_alpha() > 0.95, "a hero within 3: tag fades in (%.2f)" % statue2.tag_alpha())
	check(statue2.tag_label.visible, "and is visible")
	walker.global_position = Vector3(6.0, 0, 0)
	await frames(45)
	check(not statue2.tag_shown() and statue2.tag_alpha() < 0.01, "hero walked off: tag fades out (%.2f)" % statue2.tag_alpha())
	check(not statue2.tag_label.visible, "and is hidden")
	# A monster nearby does not show it.
	_dummy(Vector3(1.0, 0, 0))
	walker.global_position = Vector3(8.0, 0, 8.0)
	await frames(30)
	check(not statue2.tag_shown(), "a monster does not trigger the tag")

	# --- Damage ticker: live feed of Ledger damage lines only.
	_fresh()
	var ticker := DamageTicker.new()
	ticker.hold_time = 0.4
	ticker.fade_time = 0.2
	add_child(ticker)
	await frames(2)
	eq(ticker.row_count(), 0, "empty at first")
	Ledger.earn("Employee extracted", 100)
	await frames(2)
	eq(ticker.row_count(), 0, "per-employee pay does not show")
	# Objective pay does show, in green (2026-10-20: no more mid-screen "Hellgate closed +$X").
	check(DamageTicker.shows_earning({"kind": "earn", "label": "Hellgate closed", "amount": 3000}), "a closed hellgate's pay rides the ticker")
	check(not DamageTicker.shows_earning({"kind": "earn", "label": "Employee extracted", "amount": 100}), "an employee's does not")
	eq(DamageTicker.format_line({"kind": "earn", "label": "Hellgate closed", "amount": 3000, "who": ""}), "+$3,000  Hellgate closed", "earnings read +$")
	var culprit := _hero(Vector3.ZERO, "Wick")
	Ledger.damage("Wine rack", 1200, culprit)
	await frames(2)
	eq(ticker.row_count(), 1, "a damage line shows up")
	eq(ticker.row_text(0), "-$1,200  Wine rack (Wick)", "formatted line")
	Ledger.damage("Gold toilet", 15000, culprit)
	await frames(2)
	eq(ticker.row_count(), 2, "they stack")
	check(ticker.row_text(0).begins_with("-$15,000"), "newest on top: " + ticker.row_text(0))
	eq(DamageTicker.format_line({"kind": "damage", "label": "Vase", "amount": 900, "who": ""}), "-$900  Vase", "no culprit, no parens")
	for n in 8:
		Ledger.damage("Chair %d" % n, 100, culprit)
	await frames(2)
	check(ticker.row_count() <= ticker.max_rows, "capped at max_rows")
	await frames(int((ticker.hold_time + ticker.fade_time) * 60.0) + 30)
	eq(ticker.row_count(), 0, "rows fade away")
	# A broken prop feeds the ticker end to end.
	var vase2 := _prop("crystal_lamp", Vector3(3, 0, 3))
	vase2.apply_damage(999.0, culprit)
	await frames(2)
	eq(ticker.row_count(), 1, "a broken prop appears in the ticker")
	check(ticker.row_text(0).contains("Crystal lamp") and ticker.row_text(0).contains("-$600"), ticker.row_text(0))

	finish()

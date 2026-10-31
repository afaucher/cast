extends MonsterTestBase
## Ghost form (docs/design/haunted-build-plan.md, "H7 as built"; GhostSpell), solo, on a flat arena:
## - the spell: castable, "cast ghost", its component (Ectoplasm) and its prop, its numbers, its drops on haunted floors;
## - THE CAST transforms the CASTER (wherever the aim is): the ghost form status (Actor.is_ghost_form) and the whole-body look
##   (GhostForm on the model); a teammate it was aimed at is untouched;
## - IT PASSES THROUGH A MONSTER: walking into a monster, the ghost-form hero goes through it and neither pushes the other; a plain
##   hero bumps; a ghost (a Wisp) is no regular enemy and still bumps;
## - A MONSTER'S STRIKE STILL HITS IT, and its own swing still hits the monster;
## - IT ENDS after its duration (the look goes with it), and when the hero goes down;
## - THE COOLDOWN: a second cast waits for it (the held slot's shorter one);
## - THE WISP EDGE: a free ghost does not keep away from a hero in ghost form (it keeps away again once it ends), and a screen
##   whose own hero is in ghost form shows free ghosts clearly.

func _init() -> void:
	timeout_sec = 200.0


func setup() -> void:
	_numbers()
	await _cast_transforms()
	await _passes_through()
	await _still_hit()
	await _ends()
	await _cooldown()
	await _wisp_edge()
	finish()


func _hero(cell: Vector2i) -> Hero:
	var h := Hero.new()
	GameWorld.spawn(h, Hex.to_world(cell))
	h.snap_to_ground()
	return h


func _numbers() -> void:
	check(SpellBook.is_available("ghost") and SpellBook.ids().has("ghost"), "Ghost is castable and offered")
	eq(SpellBook.spell_name("ghost"), "Ghost")
	eq(SpellBook.incantation("ghost"), "CAST GHOST", "the spoken word is \"ghost\"")
	eq(SpellBook.component_name("ghost"), "Ectoplasm", "its component is Ectoplasm")
	near(SpellBook.cooldown_of("ghost"), 20.0, 0.001, "cooldown 20 s")
	check(not GhostSpell.FOLLOWS and not SpellBook.snaps_downed("ghost"), "a self-buff: it follows nobody")
	near(GhostSpell.ghost_duration(1.0), 10.0, 0.001, "10 s at full power")
	near(GhostSpell.ghost_duration(0.0), 6.0 + 4.0 * SpellBook.MIN_POWER, 0.001, "about 6 s at the least")
	eq(SpellBook.voice_aliases()["ghost"].get("ghost", 0.0), 1.0, "\"ghost\" is heard exactly")
	var p := ComponentProps.make("ghost")
	check(p != null and p.get_child_count() > 0, "the Ectoplasm prop builds")
	p.free()
	var f: Dictionary = Hero.new().net_fields()
	eq(f["_ghost_shown"], Net.LOCAL, "the look is each screen's own")
	eq(f["_modifiers"], Net.OWNER, "the status rides the owner's modifiers")
	# its component drops on haunted floors: the ghosts, the ecto blobs, the acolytes (rolled last: the older dice stay put)
	for kind in ["wisp", "ecto_blob", "acolyte"]:
		var rows: Array = SpellComponents.DROPS.get(kind, [])
		check(rows.size() > 0 and (rows[rows.size() - 1]["spells"] as Array).has("ghost"), "%s drops Ectoplasm (last)" % kind)
	var seen := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 200:
		if SpellComponents.roll_drops("wisp", rng).has("ghost"):
			seen += 1
	check(seen > 60 and seen < 140, "a ghost leaves Ectoplasm about half the time (%d of 200)" % seen)
	for kind in ["grunt", "archer", "brute", "swarmer"]:
		var rows: Array = SpellComponents.DROPS.get(kind, [])
		check(rows.all(func(r: Dictionary) -> bool: return not (r["spells"] as Array).has("ghost")), "%s (a hellgate floor's) never drops it" % kind)


func _cast_transforms() -> void:
	new_world(flat_map(10))
	var h := _hero(Vector2i(0, 0))
	var mate := _hero(Vector2i(3, 0))
	h.spell_slots = ["ghost"] as Array[String]
	h.set_charges("ghost", 5)
	await frames(2)
	check(not h.is_ghost_form() and not h.is_showing_ghost_form(), "not a ghost before the cast")
	check(h.try_cast("ghost", 1.0, mate.global_position), "cast Ghost (aimed at a teammate)")
	check(h.is_ghost_form(), "the CASTER is in ghost form")
	check(not mate.is_ghost_form(), "the teammate it was aimed at is not")
	near(h.modifier_left(GhostSpell.MOD), 10.0, 0.05, "for 10 s at full power")
	eq(h.charges_of("ghost"), 4, "a charge spent")
	await frames(2)
	check(h.is_showing_ghost_form(), "the whole-body ghost form is on the model")
	var g := GhostForm.of(h._visual)
	check(g != null and g.counts().y + g.counts().x > 0, "its parts are dressed (%s)" % str(g.counts() if g != null else Vector2i.ZERO))
	check(not mate.is_showing_ghost_form(), "the teammate looks as ever")
	# a copy shows it from the owner's announced status (NetStatus: net_set_modifiers), and drops it with it
	var copy := _hero(Vector2i(-3, 0))
	await frames(2)
	copy.net_set_modifiers({GhostSpell.MOD: [1.0, 0.5, Actor.STAT_GHOST]}, 0.0)
	await frames(2)
	check(copy.is_ghost_form() and copy.is_showing_ghost_form(), "a copy told of it shows the ghost form")
	copy.net_set_modifiers({}, 0.0)
	await frames(2)
	check(not copy.is_showing_ghost_form(), "... and drops it when the owner's status ends")


func _passes_through() -> void:
	new_world(flat_map(10))
	var m := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
	m.set_physics_process(false)   # (it stands: the hero walks into it)
	var h := _hero(Vector2i(-3, 0))
	await frames(2)
	var m0 := m.global_position
	# a plain hero bumps
	var closest := 99.0
	for i in 90:
		h.move(Vector3.RIGHT, 1.0 / 60.0)
		closest = minf(closest, fdist(h, m))
		await get_tree().physics_frame
	check(closest > h.radius + m.radius - 0.1 and h.global_position.x < m.global_position.x, "a plain hero bumps into the monster (%.2f apart at most)" % closest)
	# in ghost form it walks straight through
	h.global_position = Hex.to_world(Vector2i(-3, 0))
	GhostSpell.transform(h, 30.0)
	closest = 99.0
	for i in 90:
		h.move(Vector3.RIGHT, 1.0 / 60.0)
		closest = minf(closest, fdist(h, m))
		await get_tree().physics_frame
	check(closest < 0.15, "in ghost form it walks through the monster (%.2f apart at the closest)" % closest)
	check(h.global_position.x > m.global_position.x + 1.0, "... and out the other side (x %.2f)" % h.global_position.x)
	check(GameWorld.flat_distance(m.global_position, m0) < 0.01, "the monster was never pushed")
	# the monster's side: overlapping, its own separation leaves the ghost be (and pushes off a plain hero)
	h.global_position = m.global_position + Vector3(0.2, 0.0, 0.0)
	m._separate()
	check(GameWorld.flat_distance(m.global_position, m0) < 0.01, "a monster does not push off a ghost-form hero")
	var plain := _hero(Vector2i(4, 0))
	h.clear_modifier(GhostSpell.MOD)
	plain.global_position = m.global_position + Vector3(0.0, 0.0, 0.2)
	h.global_position = Hex.to_world(Vector2i(-5, 0))
	m._separate()
	check(GameWorld.flat_distance(m.global_position, m0) > 0.05, "... but does off a plain hero")
	# a ghost is no regular enemy: it and a ghost-form hero bump
	var w := MonsterFactory.spawn("wisp", Vector2i(5, 3)) as Wisp
	w.set_physics_process(false)
	GhostSpell.transform(h, 30.0)
	check(not h._walks_through(w, true), "a ghost-form hero bumps a ghost")
	check(h._walks_through(m, true) and not plain._walks_through(m, false), "it walks through the monster; a plain hero does not")
	check(m._walks_through(h, false) and not w._walks_through(h, false), "the monster walks through it; the ghost does not")
	check(not h._walks_through(plain, true), "teammates still bump")


func _still_hit() -> void:
	new_world(flat_map(10))
	var h := _hero(Vector2i(3, 0))
	GhostSpell.transform(h, 60.0)
	var m := MonsterFactory.spawn("grunt", Vector2i(0, 0)) as Monster
	check(await wait_until(func() -> bool: return h.hp < h.max_hp, 900), "a monster's strike still hits a hero in ghost form (%.0f HP)" % h.hp)
	check(h.is_ghost_form(), "... who is still a ghost")
	m.set_physics_process(false)
	var hp0 := m.hp
	var hit := Combat.melee_arc(h, m.global_position - h.global_position, 2.5, 160.0, 12.0)
	check(hit.has(m) and m.hp < hp0, "and its own swing still hits the monster")


func _ends() -> void:
	new_world(flat_map(10))
	var h := _hero(Vector2i(0, 0))
	GhostSpell.transform(h, 0.5)
	var t0 := GameWorld.time
	await frames(2)
	check(h.is_ghost_form() and h.is_showing_ghost_form(), "in ghost form for half a second")
	check(await wait_until(func() -> bool: return not h.is_ghost_form(), 120), "it ends")
	near(GameWorld.time - t0, 0.5, 0.05, "after its duration")
	await frames(2)
	check(not h.is_showing_ghost_form() and GhostForm.of(h._visual) == null, "the look goes with it")
	# a cast lasts its duration: a weak one about 6 s
	h.spell_slots = ["ghost"] as Array[String]
	h.set_charges("ghost", 5)
	check(h.try_cast("ghost", 0.05, h.global_position), "a weak cast")
	near(h.modifier_left(GhostSpell.MOD), GhostSpell.ghost_duration(0.05), 0.05, "lasts %.1f s" % GhostSpell.ghost_duration(0.05))
	# going down ends it
	await frames(2)
	h.die()
	await frames(2)
	check(not h.is_ghost_form() and not h.is_showing_ghost_form(), "going down ends it")


func _cooldown() -> void:
	new_world(flat_map(10))
	var h := _hero(Vector2i(0, 0))
	h.spell_slots = ["heal", "ghost"] as Array[String]   # (ghost not held: its plain cooldown)
	h.set_charges("ghost", 5)
	check(h.try_cast("ghost", 1.0, h.global_position), "the first cast")
	near(h.cooldown_left("ghost"), 20.0, 0.05, "then 20 s of cooldown")
	check(not h.try_cast("ghost", 1.0, h.global_position), "a second cast waits for it")
	eq(h.charges_of("ghost"), 4, "and spends nothing")
	h.select_slot(1)
	near(h.cooldown_total("ghost"), 20.0 / SpellComponents.HELD_COOLDOWN_DIV, 0.01, "held, it recharges 15%% more often")


func _wisp_edge() -> void:
	new_world(flat_map(14))
	var w := MonsterFactory.spawn("wisp", Vector2i(0, 0)) as Wisp
	var h := _hero(Vector2i(3, 0))
	h.is_player = true   # (this screen's own hero)
	await frames(2)
	check(not (w.model as WispModel).clear, "a free ghost is hard to see (GhostLook's soft)")
	GhostSpell.transform(h, 60.0)
	var d0 := fdist(w, h)
	await frames(240)
	check(GameWorld.flat_distance(w.global_position, w.home) < 2.6, "it does not keep away from a hero in ghost form: it drifts round where it was (%.1f -> %.1f from the hero)" % [d0, fdist(w, h)])
	check(w.state != Monster.State.ALERT, "... it drifts, unbothered")
	check((w.model as WispModel).clear, "this screen's hero is a ghost: the ghost shows clearly")
	var alpha := float(((w.model as WispModel).get("_mat") as ShaderMaterial).get_shader_parameter("alpha"))
	near(alpha, float(GhostLook.STRENGTH[WispModel.CLEAR_STRENGTH]["wisp"]), 0.001, "in the strong look")
	# another screen's ghost (not this screen's hero) does not make it clear here
	h.is_player = false
	await frames(2)
	check(not (w.model as WispModel).clear, "another player's ghost form does not show it clearly on this screen")
	# the form ends: it keeps away again
	h.clear_modifier(GhostSpell.MOD)
	var d1 := fdist(w, h)
	check(await wait_until(func() -> bool: return w.state == Monster.State.ALERT, 120), "out of ghost form: it sees the hero and keeps away")
	await frames(240)
	check(fdist(w, h) > d1 + 1.0, "away from the hero (%.1f -> %.1f)" % [d1, fdist(w, h)])

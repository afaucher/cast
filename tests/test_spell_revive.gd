extends MonsterTestBase
## Getting a downed hero back up mid-floor (docs/design/spells.md, "Revive" and "Coffee"; the user, 2026-10-27):
## - COFFEE on a downed hero stands them up as a ZOMBIE: CoffeeSpell.ZOMBIE_HP, gray (the downed look, standing), leaking
##   ZOMBIE_LEAK HP a second; heals work, and at ZOMBIE_CURE of max HP or more the curse lifts (colour back, no leak); at 0
##   HP they go down again, and another coffee makes a new zombie. The one it stood up gets no haste; the living in the splash do.
## - REVIVE stands every downed ally in its small radius up at half health, no curse; on a zombie it lifts the curse and
##   brings the HP up to half. It does nothing to a standing hero who is not a zombie.
## - both snap onto a downed teammate's body (SNAPS_DOWNED); a body left on the floor above (hidden) is not found.
## - the verb (Actor.revive) is the owner's: a copy ignores it; only a hero can get up.


func _init() -> void:
	timeout_sec = 120.0


func setup() -> void:
	_numbers()
	await _coffee_zombie()
	await _leak_and_cure()
	await _down_again()
	await _revive()
	await _targeting()
	await _the_verb()
	await _model_gray()
	finish()


func _hero(pos: Vector3, model: Node3D = null) -> Hero:
	var h := Hero.new()
	h.visual_override = model
	GameWorld.spawn(h, pos)
	h.snap_to_ground()
	return h


func _numbers() -> void:
	check(SpellBook.is_available("revive") and SpellBook.ids().has("revive"), "Revive is castable and offered")
	eq(SpellBook.spell_name("revive"), "Revive")
	eq(SpellBook.incantation("revive"), "CAST REVIVE", "the spoken word is \"revive\"")
	eq(SpellBook.component_name("revive"), "Aloe leaf", "its component is the Aloe leaf")
	eq(SpellBook.desc_of("revive"), "Stands a downed ally back up at half health. Point at them.", "the approved description")
	eq(SpellBook.desc_of("coffee"), "Everyone in a small radius gets +60% move and attack speed for six seconds, twitchy, then a crash. Monsters too. A downed ally gets up gray, leaking health, until healed past three quarters.", "coffee's approved description")
	near(SpellBook.cooldown_of("revive"), 12.0, 0.001, "cooldown 12 s")
	check(ReviveSpell.FOLLOWS, "a support spell: it follows the teammate the aim snapped onto")
	near(ReviveSpell.REVIVE_HP, 0.5, 0.0001, "half health")
	near(ReviveSpell.revive_radius(1.0), 2.0, 0.001, "a small radius (1.5 + 0.5 x power)")
	near(CoffeeSpell.ZOMBIE_HP, 10.0, 0.0001, "coffee stands you up at 10 HP")
	near(CoffeeSpell.ZOMBIE_LEAK, 1.5, 0.0001, "leaking 1.5 HP a second")
	near(CoffeeSpell.ZOMBIE_CURE, 0.75, 0.0001, "until healed to 75%")
	check(SpellBook.snaps_downed("revive") and SpellBook.snaps_downed("coffee") and not SpellBook.snaps_downed("heal"), "revive and coffee snap onto the downed, heal does not")
	eq(SpellBook.voice_aliases()["revive"].get("revive", 0.0), 1.0, "\"revive\" is heard exactly")
	var p := ComponentProps.make("revive")
	check(p != null and p.get_child_count() > 0, "the Aloe leaf prop builds")
	p.free()
	var f: Dictionary = Hero.new().net_fields()
	eq(f["zombie"], Net.OWNER, "the zombie flag is the hero owner's (it rides the snapshot)")


# --- Coffee on the downed ----------------------------------------------------------------------------------------

func _coffee_zombie() -> void:
	new_world(flat_map(10))
	var caster := _hero(Vector3(-3.0, 0.0, 0.0))
	var down := _hero(Vector3(0.0, 0.0, 0.0))
	var alive := _hero(Vector3(0.6, 0.0, 0.6))
	var ups := []
	down.revived.connect(func(cursed: bool) -> void: ups.append(cursed))
	await frames(2)
	down.die()
	check(down.dead, "the hero is down")
	check(GameWorld.downed_in_radius(Vector3.ZERO, 1.0).has(down), "the downed are found (downed_in_radius)")
	check(not GameWorld.actors_in_radius(Vector3.ZERO, 1.0).has(down), "... where the living queries drop them")
	check(SpellBook.cast("coffee", caster, 1.0, Vector3.ZERO), "coffee cast at the body")
	check(not down.dead, "coffee stood the downed hero up")
	check(down.zombie, "... as a zombie")
	near(down.hp, CoffeeSpell.ZOMBIE_HP, 0.001, "at %.0f HP" % CoffeeSpell.ZOMBIE_HP)
	eq(ups, [true], "revived fired once, cursed")
	check(not Coffee.is_hasted(down) and down.get_node_or_null("Coffee") == null, "the one it stood up gets no haste or crash")
	check(Coffee.is_hasted(alive), "a living ally in the splash is hasted as ever")
	check(down._bar.visible, "the HP bar is back")
	await frames(30)
	near(down._visual.rotation.x, 0.0, 0.01, "standing upright again (the fall undone)")
	check(down._body_mat.albedo_color.is_equal_approx(Color(0.45, 0.45, 0.48)), "but gray")
	check(down.move(Vector3.RIGHT, 1.0 / 60.0), "a zombie walks")


func _leak_and_cure() -> void:
	new_world(flat_map(10))
	var h := _hero(Vector3.ZERO)
	await frames(2)
	h.die()
	h.revive(CoffeeSpell.ZOMBIE_HP, true)
	var hp0 := h.hp
	await frames(60)
	near(hp0 - h.hp, CoffeeSpell.ZOMBIE_LEAK, 0.1, "a second leaks %.1f HP (%.2f)" % [CoffeeSpell.ZOMBIE_LEAK, hp0 - h.hp])
	check(h.zombie and not h.dead, "still a zombie")
	# Heals work; under three quarters the curse holds.
	h.heal(40.0)
	check(h.zombie and h.hp > 45.0 and h.hp < 75.0, "a heal works, and under 75%% the curse holds (%.1f)" % h.hp)
	var hp1 := h.hp
	await frames(30)
	check(h.hp < hp1, "... and it still leaks")
	# Healed to 75% or more: the curse lifts at once.
	h.heal(h.max_hp * CoffeeSpell.ZOMBIE_CURE - h.hp + 0.01)
	check(not h.zombie, "healed to 75%%: the curse lifts (%.1f)" % h.hp)
	check(h._body_mat.albedo_color.is_equal_approx(h.hero_color), "the colour is back")
	var hp2 := h.hp
	await frames(60)
	near(h.hp, hp2, 0.001, "no more leak")


func _down_again() -> void:
	new_world(flat_map(10))
	var caster := _hero(Vector3(-3.0, 0.0, 0.0))
	var h := _hero(Vector3.ZERO)
	await frames(2)
	h.die()
	h.revive(2.0, true)
	var deaths := [0]
	h.died.connect(func() -> void: deaths[0] += 1)
	check(await wait_until(func() -> bool: return h.dead, 240), "the leak takes a zombie to 0: down again")
	eq(deaths[0], 1, "it goes down once, as usual")
	check(not h.zombie, "down, it is no longer a zombie")
	await frames(30)
	near(h._visual.rotation.x, PI * 0.5, 0.01, "it lies down again")
	caster._ready_at.clear()
	check(SpellBook.cast("coffee", caster, 1.0, h.global_position), "a second coffee")
	check(not h.dead and h.zombie, "... makes a zombie again")
	near(h.hp, CoffeeSpell.ZOMBIE_HP, 0.001, "at %.0f HP" % CoffeeSpell.ZOMBIE_HP)
	# Damage takes a zombie down as usual too.
	h.apply_damage(50.0, null)
	check(h.dead and not h.zombie, "a hit at 0 HP downs a zombie as usual")


# --- Revive --------------------------------------------------------------------------------------------------------

func _revive() -> void:
	new_world(flat_map(10))
	var caster := _hero(Vector3(-3.0, 0.0, 0.0))
	var a := _hero(Vector3(0.0, 0.0, 0.0))
	var b := _hero(Vector3(0.5, 0.0, -0.4))
	var far := _hero(Vector3(5.0, 0.0, 0.0))
	await frames(2)
	for h in [a, b, far]:
		h.die()
	check(SpellBook.cast("revive", caster, 1.0, Vector3.ZERO), "revive cast at the bodies")
	check(not a.dead and not b.dead, "every downed ally in the radius stands up")
	check(far.dead, "one outside the small radius stays down")
	near(a.hp, a.max_hp * 0.5, 0.001, "at half health")
	near(b.hp, b.max_hp * 0.5, 0.001, "")
	check(not a.zombie and not b.zombie, "no zombie curse")
	var hp_a := a.hp
	await frames(60)
	near(a.hp, hp_a, 0.001, "and no leak")
	# On a zombie: the curse lifts, HP up to half.
	far.revive(CoffeeSpell.ZOMBIE_HP, true)
	check(far.zombie, "a coffee zombie")
	caster._ready_at.clear()
	SpellBook.cast("revive", caster, 1.0, far.global_position)
	check(not far.zombie, "Revive lifts the zombie's curse")
	near(far.hp, far.max_hp * 0.5, 0.001, "... and sets its HP to half")
	# A zombie already above half keeps its HP (at least 50%).
	far.die()
	far.revive(10.0, true)
	far.heal(55.0)
	check(far.zombie and far.hp > 60.0, "a zombie healed to %.0f (under 75%%)" % far.hp)
	var hp_z := far.hp
	far.revive(far.max_hp * ReviveSpell.REVIVE_HP, false)
	check(not far.zombie, "Revive lifts the curse")
	near(far.hp, hp_z, 0.001, "and keeps the HP it had above half")
	# On a standing hero who is no zombie: nothing.
	a.apply_damage(30.0, null)
	var hp_hurt := a.hp
	check(not a.revive(a.max_hp * 0.5, false), "Revive does nothing to a standing hero who is not a zombie")
	near(a.hp, hp_hurt, 0.001, "(it is not a heal)")
	check(not a.revive(10.0, true), "nor does coffee's stand-up")


func _targeting() -> void:
	new_world(flat_map(10))
	var caster := _hero(Vector3(-3.0, 0.0, 0.0))
	var down := _hero(Vector3(1.0, 0.0, 0.0))
	await frames(2)
	down.die()
	var aim := Vector3(1.6, 0.0, 0.5)
	eq(SpellBook.snap_hero(aim), null, "a living-only snap skips the body")
	eq(SpellBook.snap_hero(aim, true), down, "a downed snap finds it")
	var t := SpellBook.resolve_target(caster, aim, true)
	near(GameWorld.flat_distance(t, down.global_position), 0.0, 0.01, "the cast lands on the body")
	# A body left on the floor above (hidden on arrival: game.gd's carry) is not there to stand up.
	var gone := _hero(Vector3(-1.0, 0.0, 2.0))
	await frames(2)
	gone.die()
	gone.visible = false
	check(not GameWorld.downed_in_radius(gone.global_position, 1.0).has(gone), "a hidden body is not found")
	caster._ready_at.clear()
	SpellBook.cast("revive", caster, 1.0, gone.global_position)
	check(gone.dead, "... nor stood up")


func _the_verb() -> void:
	new_world(flat_map(10))
	var h := _hero(Vector3.ZERO)
	var d := TrainingDummy.new()
	GameWorld.spawn(d, Vector3(3.0, 0.0, 0.0))
	await frames(2)
	h.die()
	Net.make_copy(h)
	check(not h.revive(50.0), "a copy ignores revive (its owner applies it)")
	check(h.dead, "... and stays down here")
	Net.release_copy(h)
	check(h.revive(50.0), "the owner applies it")
	check(not d.revive(50.0), "only a hero can get up (anything else is gone)")


func _model_gray() -> void:
	new_world(flat_map(10))
	var model := WickModel.new()
	var h := _hero(Vector3.ZERO, model)
	await frames(2)
	near(_desat(model), 0.0, 0.001, "in colour")
	h.die()
	near(_desat(model), 0.85, 0.001, "downed: gray")
	h.revive(CoffeeSpell.ZOMBIE_HP, true)
	near(_desat(model), 0.85, 0.001, "a zombie stays gray")
	check(model.idle_enabled, "... but standing and moving (idle on)")
	h.revive(50.0, false)
	near(_desat(model), 0.0, 0.001, "the curse lifted: colour back")
	h.die()
	h.revive(50.0, false)
	near(_desat(model), 0.0, 0.001, "a Revive from downed: in colour")


## The model's gray (its material's "desat"; unset is 0).
static func _desat(model: LowPolyModel) -> float:
	var v: Variant = model._mat.get_shader_parameter("desat")
	return float(v) if v != null else 0.0

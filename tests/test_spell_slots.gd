extends TestCase
## Spell slots, the held spell, charges, material components, pickups and drops.

var root: Node3D
var casts: Array = []   ## [id, power] of every spell_cast the current hero emitted


func _flat_map(radius: int = 8) -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		m.set_cell(c, 0)
	return m


## A player hero (with a PlayerController aiming at a fixed point) holding `slots`.
func _player(cell: Vector2i, slots: Array[String], model: Node3D = null) -> Hero:
	var h := HeroFactory.spawn_hero(cell, "Aria", Color.BLUE, "sword", model)
	var pc := HeroFactory.make_player(h, slots)
	pc.aim_override = h.global_position + Vector3(3, 0, 0)
	return h


func _pc(h: Hero) -> PlayerController:
	return h.get_node("PlayerController") as PlayerController


func _pickups() -> Array[ComponentPickup]:
	var out: Array[ComponentPickup] = []
	for n in get_tree().get_nodes_in_group("component_pickups"):
		var p := n as ComponentPickup
		if p != null and not p.is_queued_for_deletion() and not p._used:
			out.append(p)
	return out


func _clear_pickups() -> void:
	for p in _pickups():
		p.free()


func setup() -> void:
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(_flat_map(), root, 7)
	InputSetup.ensure_actions()

	_test_data_and_input()
	await _test_slots_and_casting()
	await _test_pickups()
	await _test_swap()
	await _test_drop_table()
	await _test_monster_drops()
	await _test_hand_models()
	await _test_hud()
	finish()


func _test_data_and_input() -> void:
	eq(SpellComponents.SLOT_COUNT, 4, "four slots")
	eq(SpellComponents.START_CHARGES, 5, "start charges")
	eq(SpellComponents.PICKUP_CHARGES, 3, "pickup charges")
	eq(SpellComponents.MAX_CHARGES, 9, "cap")
	near(SpellComponents.HELD_COOLDOWN_DIV, 1.15, 0.0001, "held boost")
	near(SpellComponents.READIED_POWER, 0.8, 0.0001, "E power")
	for a in ["cast_slot_1", "cast_slot_2", "cast_slot_3", "cast_slot_4", "cast_readied", "swap_pickup"]:
		check(InputMap.has_action(a), "input action " + a)
	# Every castable spell names a component (teeth included since its gameplay landed).
	for id in SpellBook.ids():
		check(SpellBook.component_name(id) != "", "component for " + id)
	eq(SpellBook.component_name("heal"), "Grave moss")
	eq(SpellBook.component_name("fireball"), "Ember horn")
	eq(SpellBook.component_name("armor"), "Hide plate")
	eq(SpellBook.component_name("corn"), "Corn kernel")
	eq(SpellBook.component_name("tentacles"), "Neon ichor")
	eq(SpellBook.component_name("teeth"), "Loose teeth")
	check(SpellBook.has_spell("teeth") and SpellBook.is_available("teeth"), "teeth exists and is available")
	check(SpellBook.ids().has("teeth"), "teeth is offered by the picker")
	check(SpellBook.ids().size() == 6, "six castable spells")
	eq(SpellBook.all_ids().size(), SpellBook.ids().size(), "no unavailable spells are left")


func _test_slots_and_casting() -> void:
	var h := _player(Vector2i(0, 0), ["heal", "fireball"] as Array[String])
	h.spell_cast.connect(func(id: String, power: float) -> void: casts.append([id, power]))
	var pc := _pc(h)
	eq(h.spell_slots.size(), 2, "two picked spells")
	eq(h.slot_spell(0), "heal")
	eq(h.slot_spell(1), "fireball")
	eq(h.slot_spell(2), "", "slot 3 starts empty")
	eq(h.slot_spell(3), "", "slot 4 starts empty")
	eq(h.charges_of("heal"), 5, "5 charges at the start")
	eq(h.charges_of("fireball"), 5)
	eq(h.charges_of("corn"), 0, "unslotted spell has none")
	eq(h.held_slot, 0, "slot 1 is held at the start")
	eq(h.held_spell(), "heal")

	# Held selection: 1-4 pick a filled slot; an empty slot changes nothing.
	check(h.select_slot(1), "slot 2 can be held")
	eq(h.held_spell(), "fireball")
	check(not h.select_slot(2), "an empty slot cannot be held")
	eq(h.held_spell(), "fireball", "held unchanged by a refused selection")
	check(not h.select_slot(7), "out of range")
	check(h.select_slot(0))
	eq(h.held_spell(), "heal")

	# Cooldown: held /1.15, others normal.
	near(h.cooldown_total("heal"), 8.0 / 1.15, 0.0001, "held cooldown total")
	near(h.cooldown_total("fireball"), 5.0, 0.0001, "non-held cooldown total")

	# E casts the held spell at power 0.8.
	check(pc.cast_readied(), "E casts the held spell")
	eq(casts.size(), 1)
	eq(casts[0][0], "heal")
	near(float(casts[0][1]), 0.8, 0.0001, "E power is 0.8")
	near(h.cooldown_left("heal"), 8.0 / 1.15, 0.001, "held spell cooldown is /1.15")
	eq(h.charges_of("heal"), 4, "a cast spends one charge")

	# Voice casts a NON-held slotted spell at its own power, without changing the held slot.
	check(pc.cast_spell("fireball", 0.93), "voice casts the non-held spell")
	eq(casts[1][0], "fireball")
	near(float(casts[1][1]), 0.93, 0.0001, "voice power passes through")
	eq(h.held_spell(), "heal", "voice does not change what is held")
	near(h.cooldown_left("fireball"), 5.0, 0.001, "non-held cooldown is normal")
	eq(h.charges_of("fireball"), 4)
	# Recast refused on cooldown; no charge spent.
	check(not pc.cast_spell("fireball", 1.0), "cooldown blocks")
	eq(h.charges_of("fireball"), 4, "a refused cast spends nothing")
	# A spell that is not slotted is refused (teeth included: it has to be slotted first).
	check(not pc.cast_spell("corn", 1.0), "corn is not slotted")
	check(not pc.cast_spell("teeth", 1.0), "teeth is not slotted")
	check(not SpellBook.cast("nonsense", h, 1.0, Vector3.ZERO), "an unknown spell does not cast")

	# The held boost really shortens the wait: run the clock.
	await frames(int(5.05 * 60.0))
	check(h.cooldown_left("fireball") <= 0.0, "non-held ready after 5 s")
	check(h.cooldown_left("heal") > 0.0, "held (8/1.15 = 6.96 s) still recharging at 5 s")
	await frames(int(2.0 * 60.0))
	check(h.cooldown_left("heal") <= 0.0, "held ready after ~7 s")

	# Zero charges: the cast fizzles, spends no cooldown, tells the player.
	var hud := Hud.new()
	add_child(hud)
	pc.hud = hud
	var empties: Array = []
	h.spell_empty.connect(func(id: String) -> void: empties.append(id))
	check(h.set_charges("fireball", 0), "charges can be set")
	check(not pc.cast_spell("fireball", 1.0), "out of components fizzles (voice path)")
	near(h.cooldown_left("fireball"), 0.0, 0.0001, "a fizzle spends no cooldown")
	eq(hud._toast.text, "Out of Ember horn", "HUD says what ran out")
	check(not h.try_cast("fireball", 1.0, h.global_position), "try_cast also refuses")
	eq(empties, ["fireball"], "spell_empty emitted by the hero for a direct try_cast")
	near(h.cooldown_left("fireball"), 0.0, 0.0001, "still no cooldown")
	eq(casts.size(), 2, "no cast went off")
	h.select_slot(1)
	check(not pc.cast_readied(), "E on an empty held spell fizzles too")
	eq(hud._toast.text, "Out of Ember horn")
	hud.queue_free()
	pc.hud = null
	h.select_slot(0)
	# Last charge: spends to zero and stops there.
	h.set_charges("heal", 1)
	await frames(2)
	check(pc.cast_spell("heal", 1.0), "last charge casts")
	eq(h.charges_of("heal"), 0)
	await frames(int(7.2 * 60.0))
	check(not pc.cast_spell("heal", 1.0), "and then it is out")

	# The keyboard path: E (cast_readied) and the number keys go through the controller.
	h.set_charges("heal", 5)
	h.set_charges("fireball", 5)
	casts.clear()
	Input.action_press("cast_slot_2")
	await frames(2)
	Input.action_release("cast_slot_2")
	eq(h.held_spell(), "fireball", "key 2 readies slot 2")
	await frames(2)
	Input.action_press("cast_readied")
	await frames(2)
	Input.action_release("cast_readied")
	eq(casts.size(), 1, "E key casts once")
	if casts.size() > 0:
		eq(casts[0][0], "fireball")
		near(float(casts[0][1]), 0.8, 0.0001)
	Input.action_press("cast_slot_4")   # empty: nothing changes
	await frames(2)
	Input.action_release("cast_slot_4")
	eq(h.held_spell(), "fireball", "empty slot key does nothing")
	h.queue_free()
	await frames(2)


func _test_pickups() -> void:
	_clear_pickups()
	var h := _player(Vector2i(0, 0), ["heal", "fireball"] as Array[String])
	h.set_charges("fireball", 4)
	var collected: Array = []
	h.component_collected.connect(func(id: String, n: int, kind: String) -> void: collected.append([id, n, kind]))

	# Slotted spell: +3 charges.
	var p := ComponentPickup.drop("fireball", 3, h.global_position + Vector3(0.5, 0, 0))
	check(p != null, "pickup spawns")
	await frames(3)
	eq(h.charges_of("fireball"), 7, "+3 charges")
	check(_pickups().is_empty(), "picked up and gone")
	eq(collected, [["fireball", 3, "added"]], "collected signal")

	# The cap is 9: only 2 fit, the other 1 stays on the floor.
	p = ComponentPickup.drop("fireball", 3, h.global_position + Vector3(0.5, 0, 0))
	await frames(3)
	eq(h.charges_of("fireball"), 9, "capped at 9")
	eq(_pickups().size(), 1, "the leftover stays on the floor")
	eq(_pickups()[0].charges, 1, "with the charge that did not fit")
	await frames(3)
	eq(h.charges_of("fireball"), 9, "a capped spell takes no more")
	_clear_pickups()

	# Out of reach: not collected.
	p = ComponentPickup.drop("heal", 3, h.global_position + Vector3(2.5, 0, 0))
	await frames(3)
	eq(h.charges_of("heal"), 5, "too far away")
	_clear_pickups()

	# Unslotted spell with an empty slot: fills slot 3 with 3 charges.
	p = ComponentPickup.drop("armor", 3, h.global_position + Vector3(0.4, 0, 0.4))
	await frames(3)
	eq(h.slot_spell(2), "armor", "an empty slot is filled")
	eq(h.charges_of("armor"), 3, "with 3 charges")
	p = ComponentPickup.drop("corn", 3, h.global_position + Vector3(0.4, 0, 0.4))
	await frames(3)
	eq(h.slot_spell(3), "corn", "slot 4 fills next")
	eq(h.spell_slots.size(), 4)
	eq(collected.back(), ["corn", 3, "filled"])
	eq(h.held_slot, 0, "the held slot did not move")

	# Teeth is a real spell now: with every slot full a teeth pickup waits for an F swap.
	check(h.component_outcome("teeth") == "swap", "a teeth pickup is a swap candidate with full slots")
	h.queue_free()
	_clear_pickups()
	await frames(2)

	# Allies do not collect: only heroes with is_player.
	var ally := HeroFactory.spawn_hero(Vector2i(2, 0), "Pebble", Color.ORANGE)
	ally.spell_slots = ["heal"] as Array[String]
	ComponentPickup.drop("heal", 3, ally.global_position)
	await frames(3)
	eq(ally.charges_of("heal"), 5, "AI allies do not collect pickups")
	eq(_pickups().size(), 1, "the pickup is left for the player")
	ally.queue_free()
	_clear_pickups()
	await frames(2)


func _test_swap() -> void:
	_clear_pickups()
	var h := _player(Vector2i(0, 0), ["heal", "fireball", "armor", "corn"] as Array[String])
	h.set_charges("fireball", 4)
	var hud := Hud.new()
	add_child(hud)
	var allies: Array[Hero] = []
	hud.bind(h, allies)
	var pc := _pc(h)
	pc.hud = hud
	h.select_slot(1)   # fireball is held
	var swaps: Array = []
	h.component_swapped.connect(func(o: String, n: String, s: int) -> void: swaps.append([o, n, s]))

	# All four slots are full: the pickup stays, the prompt names the swap.
	var p := ComponentPickup.drop("tentacles", 3, h.global_position + Vector3(0.6, 0, 0))
	await frames(3)
	check(is_instance_valid(p) and not p.is_queued_for_deletion(), "a full hero leaves the pickup on the floor")
	eq(h.spell_slots.size(), 4)
	check(h.swap_candidate == p, "the pickup is offered for a swap")
	eq(hud.swap_prompt_text(), "F: swap Tentacles into slot 2 (held)", "the prompt")
	await frames(2)
	check(hud._prompt.visible and hud._prompt.text == "F: swap Tentacles into slot 2 (held)", "the prompt is on screen")
	# Out of range: no offer.
	h.global_position += Vector3(0, 0, 3.0)
	await frames(3)
	check(h.swap_candidate == null, "walk away and the offer is withdrawn")
	eq(hud.swap_prompt_text(), "")
	h.global_position -= Vector3(0, 0, 3.0)
	await frames(3)
	check(h.swap_candidate == p, "back in range")

	# F: swap into the HELD slot; the old spell drops with its remaining charges.
	check(pc.swap_pickup(), "F swaps")
	eq(h.slot_spell(1), "tentacles", "the pickup took the held slot")
	eq(h.charges_of("tentacles"), 3, "with the pickup's charges")
	eq(h.charges_of("fireball"), 0, "the old spell is out of the slots")
	eq(h.held_spell(), "tentacles", "the new spell is held")
	eq(swaps, [["fireball", "tentacles", 1]], "swap signal")
	await frames(2)
	var dropped: Array[ComponentPickup] = _pickups()
	eq(dropped.size(), 1, "the old spell was dropped as a pickup")
	if dropped.size() == 1:
		eq(dropped[0].spell_id, "fireball")
		eq(dropped[0].charges, 4, "with its remaining charges")
		check(GameWorld.flat_distance(dropped[0].global_position, h.global_position) > SpellComponents.COLLECT_RADIUS, "dropped clear of the hero")
	check(not pc.swap_pickup(), "nothing left to swap right now (or the dropped one is out of reach)")
	eq(h.spell_slots, ["heal", "tentacles", "armor", "corn"] as Array[String], "the other slots are untouched")

	# A spell with 0 charges drops nothing (an empty component is no loot).
	_clear_pickups()
	h.set_charges("armor", 0)
	h.select_slot(2)
	var q := ComponentPickup.drop("fireball", 3, h.global_position + Vector3(0.6, 0, 0))
	await frames(3)
	check(h.swap_candidate == q, "offered")
	check(pc.swap_pickup(), "swap over an empty spell")
	await frames(2)
	eq(h.slot_spell(2), "fireball")
	eq(_pickups().size(), 0, "nothing dropped for 0 charges")
	hud.queue_free()
	h.queue_free()
	_clear_pickups()
	await frames(2)


func _test_drop_table() -> void:
	var n := 4000
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var tally := {}
	for kind in ["grunt", "archer", "brute", "swarmer"]:
		tally[kind] = {}
		for i in n:
			for id in SpellComponents.roll_drops(kind, rng, true):
				tally[kind][id] = int(tally[kind].get(id, 0)) + 1
	# grunt: loose teeth 35%; brute: ember horn or hide plate 50/50, always one; archer: moss 40%;
	# swarmer: ichor 15%; corn 5% from everyone on top.
	near(float(tally["grunt"].get("teeth", 0)) / n, 0.35, 0.04, "grunt teeth 35%")
	near(float(tally["archer"].get("heal", 0)) / n, 0.40, 0.04, "archer moss 40%")
	near(float(tally["swarmer"].get("tentacles", 0)) / n, 0.15, 0.03, "swarmer ichor 15%")
	var horn := int(tally["brute"].get("fireball", 0))
	var plate := int(tally["brute"].get("armor", 0))
	eq(horn + plate, n, "a brute always drops exactly one of its two")
	near(float(horn) / n, 0.5, 0.04, "50/50 horn vs plate")
	for kind in tally:
		near(float(tally[kind].get("corn", 0)) / n, 0.05, 0.02, kind + " corn 5%")
	check(not tally["brute"].has("teeth") and not tally["archer"].has("tentacles"), "kinds only drop their own components")

	# Teeth is available, so grunts really drop it by default (an unavailable spell would be skipped).
	rng.seed = 99
	var teeth_seen := 0
	for i in n:
		if SpellComponents.roll_drops("grunt", rng).has("teeth"):
			teeth_seen += 1
	near(float(teeth_seen) / n, 0.35, 0.04, "grunts drop teeth ~35% by default")

	# Deterministic with a seeded rng.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 2024
	b.seed = 2024
	var ra: Array = []
	var rb: Array = []
	for i in 200:
		ra.append(SpellComponents.roll_drops("archer", a))
		rb.append(SpellComponents.roll_drops("archer", b))
	eq(ra, rb, "same seed, same drops")
	eq(SpellComponents.drop_charges("brute", "fireball"), 3, "default pickup charges")


func _test_monster_drops() -> void:
	_clear_pickups()
	# A killed brute always leaves a component pickup (fireball or armor) next to the corpse.
	var brute := MonsterFactory.spawn("brute", Vector2i(3, 0))
	check(brute != null, "brute spawns")
	var where := brute.global_position
	brute.apply_damage(99999.0)
	await frames(2)
	var found := _pickups()
	check(found.size() >= 1, "the brute dropped something")
	var ids: Array[String] = []
	for p in found:
		ids.append(p.spell_id)
		check(GameWorld.flat_distance(p.global_position, where) < 2.5, "next to the corpse")
	check(ids.has("fireball") or ids.has("armor"), "brute drops ember horn or hide plate: %s" % str(ids))
	_clear_pickups()
	await frames(25)


func _test_hand_models() -> void:
	# hold_item on each hero model: attaches under the model, replaces, and clears.
	for model: LowPolyModel in [PebbleModel.new(), DagnaModel.new(), LarkinModel.new()]:
		add_child(model)
		var prop := ComponentProps.make("fireball")
		model.hold_item(prop)
		check(model.held_item() == prop, "%s holds the prop" % model.name)
		check(prop.is_inside_tree(), "%s prop is in the tree" % model.name)
		check(model.is_ancestor_of(prop), "%s prop hangs under the model" % model.name)
		check(model.hold_anchor != null and model.hold_anchor.get_parent() != null, "%s has a hand anchor" % model.name)
		await frames(3)   # idle animation runs; the prop follows the hand
		var second := ComponentProps.make("heal")
		model.hold_item(second)
		check(model.held_item() == second, "%s swaps the prop" % model.name)
		eq(model.hold_anchor.get_child_count(), 1, "%s holds one prop at a time" % model.name)
		model.hold_item(null)
		check(model.held_item() == null, "%s empties the hand" % model.name)
		model.queue_free()
	# Every spell has a prop.
	for id in SpellBook.all_ids():
		var prop := ComponentProps.make(id)
		check(prop.get_child_count() == 1 and (prop.get_child(0) as MeshInstance3D).mesh != null, "prop for " + id)
		prop.free()

	# A hero shows the HELD spell's component in the hand and follows the held slot.
	var larkin := LarkinModel.new()
	var h := _player(Vector2i(0, 0), ["heal", "corn"] as Array[String], larkin)
	await frames(3)
	check(larkin.held_item() != null and larkin.held_item().name == "Component_heal", "Larkin holds grave moss")
	h.select_slot(1)
	check(larkin.held_item() != null and larkin.held_item().name == "Component_corn", "holding follows the held slot")
	var before := larkin.hold_anchor.position
	await frames(3)
	check(larkin.hold_anchor.position.length() > 0.1, "the prop sits at the free hand (%s)" % str(before))
	h.slot_in("armor", 3)
	h.queue_free()
	await frames(2)
	# The prototype capsule body holds one too.
	var proto := _player(Vector2i(1, 0), ["fireball"] as Array[String])
	await frames(2)
	check(proto._held_prop != null and proto._held_prop.name == "Component_fireball", "prototype body holds the component")
	proto.queue_free()
	await frames(2)


func _test_hud() -> void:
	var h := _player(Vector2i(0, 0), ["heal", "fireball"] as Array[String])
	var hud := Hud.new()
	add_child(hud)
	var allies: Array[Hero] = []
	hud.bind(h, allies)
	await frames(3)
	eq(hud._cards.size(), 4, "four spell cards")
	eq(hud._cards[0].spell_id(), "heal")
	eq(hud._cards[2].spell_id(), "", "slot 3 card is empty")
	check(hud._cards[0].is_held() and not hud._cards[1].is_held() and not hud._cards[2].is_held(), "only the held card is highlighted")
	h.select_slot(1)
	check(hud._cards[1].is_held() and not hud._cards[0].is_held(), "the highlight follows the held slot")
	hud.show_pickup("fireball", 3)
	eq(hud._toast.text, "+3 Ember horn", "pickup toast")
	hud.show_out_of_component("corn")
	eq(hud._toast.text, "Out of Corn kernel", "out of toast")
	# A pickup that fills a slot tells you which.
	ComponentPickup.drop("armor", 3, h.global_position + Vector3(0.3, 0, 0.3))
	await frames(3)
	eq(hud._toast.text, "+3 Hide plate  (Armor, slot 3)", "fill toast")
	eq(hud._cards[2].spell_id(), "armor", "the new card shows up")
	hud.queue_free()
	h.queue_free()
	_clear_pickups()
	await frames(2)

class_name HeroFactory
extends RefCounted
## Convenience builders so the arena, the game scene and tests assemble heroes
## the same way. Everything spawns under GameWorld.root.


## Spawn a hero standing on `cell` (needs GameWorld.begin() to have been called).
## `model` optionally replaces the prototype body (see Hero.visual_override). `kit_id` ("wick",
## "gasket", "rebar") gives it that HeroKit (HP, primary, secondary, quirks) before it enters the world.
static func spawn_hero(cell: Vector2i, hero_name: String, color: Color, weapon: String = "sword", model: Node3D = null, kit_id: String = "") -> Hero:
	var h := Hero.new()
	if kit_id != "":
		HeroKit.apply_to(h, kit_id)
	h.visual_override = model
	h.display_name = hero_name
	h.hero_color = color
	h.weapon_kind = weapon
	var level := 0.0
	if GameWorld.map != null:
		var ground := GameWorld.map.ground_level(Hex.to_world(cell))
		level = 0.0 if is_nan(ground) else ground
	GameWorld.spawn(h, Hex.to_world(cell, level))
	h.snap_to_ground()
	return h


## Make `hero` the player: slots + a PlayerController child.
static func make_player(hero: Hero, slots: Array[String]) -> PlayerController:
	hero.spell_slots = slots
	var pc := PlayerController.new()
	pc.name = "PlayerController"
	hero.add_child(pc)
	return pc


## Make `hero` an AI ally following `leader`.
static func make_ally(hero: Hero, leader: Hero, prefers_ranged: bool, formation_angle: float, formation_hexes: float = AllyBrain.FORMATION_HEX_MIN) -> AllyBrain:
	var brain := AllyBrain.new()
	brain.name = "AllyBrain"
	brain.leader = leader
	brain.prefers_ranged = prefers_ranged
	brain.formation_angle = formation_angle
	brain.formation_dist = clampf(formation_hexes, AllyBrain.FORMATION_HEX_MIN, AllyBrain.FORMATION_HEX_MAX) * AllyBrain.HEX_STEP
	hero.add_child(brain)
	return brain

class_name Wading
extends RefCounted
## Pool water (docs/design/pool-options.md, "Built"): what standing in a pool does. Pools are wading depth only
## (HexMap.WATER_DEPTH, about knee deep): nobody swims, everybody walks in and out anywhere along the rim.
##
##   - SLOW: any actor (heroes, AI allies, employees, monsters alike) walks at SPEED_MULT while its feet are in the water
##     (Actor.effective_speed asks speed_mult()). Casting, attacks and weapons are unchanged.
##   - WET: an actor in the water is soaked the whole time it is in it, and for the normal damp time after it steps out:
##     Wet.douse(actor, DampSpell.DAMP_SOAK), the Damp spell's status, refreshed while it wades and once more as it
##     leaves (so it is wet DAMP_SOAK seconds from the moment it leaves). Being soaked puts a fire out and blocks
##     ignition (Burning.soak), so wading in is the way to put out a burning hero, and a fireball fizzles on a wader.
##   - Going down in water has no consequence of its own.
##
## Networking: the soak is an owner-applied status (Net.resolves: a hero's player, the host for everything else). Each
## owner tests its own actors against the shared map every physics frame (the water cells are seed-built terrain, in
## the floor checksum, so every machine knows where the water is) and NetStatus tells the other screens ("soak"). The
## slowdown is LOCAL: derived from the position and the map wherever the actor is moved. The ripple ring round a wader
## is cosmetic and drawn on every machine from the streamed position. GameWorld calls tick() every physics frame on a
## floor with pools.

const SPEED_MULT := 0.75          ## walking speed while wading
## Re-soak a wader when its soak has run this far below the full DAMP_SOAK: about one NetStatus "soak" every 2 s per wader
## (it is topped up to the full time again as it steps out).
const REFRESH := 2.0
const META_IN := "wading"         ## LOCAL bookkeeping on the actor: it was in the water last frame
const RIPPLE_NAME := "WadeRipple"
## A hero's wading step sound (Sfx "wade_step", cosmetic) every this many units it walks in the water: about two a second
## at a wading walk (4.5 x SPEED_MULT), none while it stands.
const STEP_EVERY := 1.5
const META_STEP := "wade_step"    ## LOCAL, on a wading hero: [its position last frame, units walked since the last step]

const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")


## Walking speed multiplier for an actor at `pos` (1.0 on dry ground).
static func speed_mult(pos: Vector3) -> float:
	var map := GameWorld.map
	if map == null or map.pools.is_empty() or not map.water_at(pos):
		return 1.0
	return SPEED_MULT


## Is the actor standing in pool water (feet down: not mid-shove in the air)?
static func is_wading(a: Actor) -> bool:
	var map := GameWorld.map
	return map != null and a != null and is_instance_valid(a) and not a.dead and not a.is_airborne() \
			and map.water_at(a.global_position)


## One physics frame: soak the owner's waders, keep the ripples on every machine.
static func tick() -> void:
	var map := GameWorld.map
	if map == null or map.pools.is_empty() or GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	for a in GameWorld.actors():
		if a is DecorBlocker or a.is_in_group("breakables") or a.is_in_group("sharks"):   # (a shark is always wet: no ripple, no soak)
			continue
		var wet := is_wading(a)
		var was := a.has_meta(META_IN)
		_ripple(a, wet, map)
		if a is Hero:
			_step(a, wet)
		if wet:
			if not was:
				a.set_meta(META_IN, true)
			if Net.resolves(a) and Burning.soaked_left(a) < DampSpell.DAMP_SOAK - REFRESH:
				Wet.douse(a, DampSpell.DAMP_SOAK)
		elif was:
			a.remove_meta(META_IN)
			if Net.resolves(a) and not a.dead:
				Wet.douse(a, DampSpell.DAMP_SOAK)   # stepped out: wet for the full damp time from now


## A hero's wading steps (cosmetic, every machine, from the shown position): a soft splash every STEP_EVERY units it walks
## in the water.
static func _step(a: Actor, on: bool) -> void:
	if not on:
		if a.has_meta(META_STEP):
			a.remove_meta(META_STEP)
		return
	var w: Array = a.get_meta(META_STEP, [a.global_position, STEP_EVERY * 0.6])
	var walked := float(w[1]) + GameWorld.flat_distance(a.global_position, w[0] as Vector3)
	if walked >= STEP_EVERY:
		walked = 0.0
		Sfx.play_at("wade_step", a.global_position)
	a.set_meta(META_STEP, [a.global_position, walked])


## The ripple ring round a wader's legs on the water surface (cosmetic).
static func _ripple(a: Actor, on: bool, map: HexMap) -> void:
	var r := a.get_node_or_null(RIPPLE_NAME) as Node3D
	if not on:
		if r != null:
			r.queue_free()
		return
	if r == null:
		r = PoolProps.build("ripple", {"radius": maxf(0.38, a.radius + 0.1)})
		r.name = RIPPLE_NAME
		a.add_child(r)
	var surf := map.water_surface(a.global_position)
	if is_nan(surf):
		return
	r.global_position = Vector3(a.global_position.x, surf + 0.012, a.global_position.z)
	r.global_rotation = Vector3.ZERO
	var k := 1.0 + 0.06 * sin(GameWorld.time * 4.0 + float(a.get_instance_id() % 97))
	r.scale = Vector3(k, 1.0, k)

class_name Burning
extends Node3D
## "You are on fire": a status node that lives as a child of the burning Actor. A fireball blast
## (Burning.on_blast, called from SpellBook) gives every actor in it a chance to ignite; the fire burns
## 5-10 s and hurts a little every half second. Design record: docs/design/spells.md ("Burning").
##
##   Burning.ignite(actor, culprit, duration)   # set on fire (or refresh); null if it cannot burn
##   Burning.is_burning(actor)  /  Burning.remaining(actor)
##   Burning.extinguish(actor)                  # put it out (Damp): true if it was burning
##   Burning.extinguish_in_radius(pos, r)       # put out every fire in an area, returns how many
##   Burning.soak(actor, seconds)               # extinguish AND refuse to ignite for a while (a "damp" status)
##   Burning.set_fireproof(actor, true)         # permanent immunity (group "fireproof")
##
## Rules:
##   - Anyone near the blast rolls: monsters, heroes (friendly fire: aiming at a teammate is the game) and
##     employees. Hellgates, priced props and mail packages never burn (immovable / inanimate).
##   - It burns 5-10 s and deals TICK_DAMAGE every TICK seconds: about 15-30 HP over a full burn, so it
##     never kills a full-HP hero (Wick, the frailest, has 85) but it will finish a swarmer or an archer.
##     Armor and other damage modifiers apply (Actor.apply_damage).
##   - A hero's fire never takes a hero below 1 HP (the friendly-fire floor of the other everyone-spells).
##   - Igniting a burning actor refreshes the fire to the longer of what is left and the new duration, and
##     adopts the new culprit. It never stacks damage.
##   - The fire does NOT spread: no contact spread, no aura. Only a fireball blast ignites.
##   - It ends when it burns out, when the actor dies or is downed (the "died" signal), or on extinguish.
##     Healing does not put it out.
##   - Damage is dealt through Actor.apply_damage with the caster as the source (kill credit, ledger).
## Every live fire is in the group "burning", so Damp can find them. `ended(reason)` says why a fire
## stopped: "burnt_out", "extinguished" or "died".
##
## Visual: a few flickering faceted flames and a small warm light on the actor, and now and then a scorch
## mark on the floor (Grime, 30 s). Flames are built once per fire from shared meshes and materials; the
## flicker only edits transforms.

signal ended(reason: String)

const IGNITE_CHANCE := 0.35        ## per actor, at the blast centre of a full-power fireball
const EDGE_CHANCE_MULT := 0.6      ## ... times this at the rim of the blast
const LOW_POWER_MULT := 0.6        ## ... and times this at the minimum power (linear in between)
const DURATION_MIN := 5.0
const DURATION_MAX := 10.0
const TICK := 0.5
const TICK_DAMAGE := 1.5           ## 3 HP/s: 15 HP at 5 s, 30 HP at 10 s
const SCORCH_EVERY := 3.0
const SCORCH_SIZE := 0.45
const GROUP := "burning"
const FIREPROOF := "fireproof"
const META_SOAKED_UNTIL := "burn_soaked_until"

const FLAME_COUNT := 8
const DEFAULT_HEIGHT := 1.8
const OUTER := Color(1.0, 0.42, 0.06)
const INNER := Color(1.0, 0.86, 0.25)
const OUTLINE := Color(0.32, 0.04, 0.0)

static var _flame_meshes: Array[ArrayMesh] = []
static var _flame_mats: Array[ShaderMaterial] = []

var target: Actor = null
var _source: WeakRef = null
var _ends_at := 0.0
var _next_tick := 0.0
var _next_scorch := 0.0
var _flames: Array[MeshInstance3D] = []
var _base: Array[Vector3] = []       ## per flame: x = phase, y = base height scale, z = yaw
var _light: OmniLight3D = null
var _over := false


## Who may write each var (see Net). A fire belongs to the burning actor's owner, who ticks its damage
## (the victim decides), so it lives on the hero's machine for a hero and on the host for anyone else.
func net_fields() -> Dictionary:
	return {
		"target": Net.SPAWN,
		"_source": Net.OWNER,              # the culprit (kill credit, ledger); a refresh adopts a new one
		"_ends_at": Net.OWNER, "_over": Net.OWNER,
		"_next_tick": Net.PRIVATE,
		"_next_scorch": Net.LOCAL,         # scorch marks are cosmetic grime
		"_flames": Net.LOCAL, "_base": Net.LOCAL, "_light": Net.LOCAL,
	}


# --- Public API ---------------------------------------------------------------------------------

## A random burn length for a new fire (uses GameWorld.rng).
static func roll_duration() -> float:
	return GameWorld.rng.randf_range(DURATION_MIN, DURATION_MAX)


## Chance that an actor `dist_frac` (0 = centre .. 1 = rim) into the blast of a cast of `power` ignites.
static func ignite_chance(power: float, dist_frac: float) -> float:
	var p := clampf(power, SpellBook.MIN_POWER, 1.0)
	var power_k := lerpf(LOW_POWER_MULT, 1.0, (p - SpellBook.MIN_POWER) / (1.0 - SpellBook.MIN_POWER))
	return IGNITE_CHANCE * power_k * lerpf(1.0, EDGE_CHANCE_MULT, clampf(dist_frac, 0.0, 1.0))


## Can this actor burn right now? (Alive, flammable, not fireproof, not soaked.)
static func can_burn(a: Actor) -> bool:
	if a == null or not is_instance_valid(a) or a.dead or not a.is_inside_tree():
		return false
	if a is Hellgate or a is PricedProp or a.is_in_group("breakables"):   # (Rebar is immovable but flammable)
		return false
	return not is_fireproof(a)


## Permanently fireproof (group "fireproof"), or soaked by Burning.soak() and not yet dry.
static func is_fireproof(a: Actor) -> bool:
	if a.is_in_group(FIREPROOF):
		return true
	return a.has_meta(META_SOAKED_UNTIL) and float(a.get_meta(META_SOAKED_UNTIL)) > GameWorld.time


## Soaked by Damp and not yet dry.
static func is_soaked(a: Actor) -> bool:
	return a != null and is_instance_valid(a) and a.has_meta(META_SOAKED_UNTIL) and float(a.get_meta(META_SOAKED_UNTIL)) > GameWorld.time


## Seconds of damp left, 0 when dry.
static func soaked_left(a: Actor) -> float:
	return maxf(0.0, float(a.get_meta(META_SOAKED_UNTIL)) - GameWorld.time) if is_soaked(a) else 0.0


static func set_fireproof(a: Actor, on: bool) -> void:
	if on:
		a.add_to_group(FIREPROOF)
		extinguish(a)
	else:
		a.remove_from_group(FIREPROOF)


## Put the actor out and keep it from igniting for `seconds` (what Damp does to everyone in its area).
static func soak(a: Actor, seconds: float) -> void:
	a.set_meta(META_SOAKED_UNTIL, GameWorld.time + seconds)
	extinguish(a)
	Net.status_changed(a, "soak")   # (online, on the owner: the other screens draw it damp)


static func is_burning(a: Actor) -> bool:
	var b := _of(a)
	return b != null


## Who set `a` on fire (the fire's culprit, as its owner knows it), or null: unknown, gone, or not burning. A burning actor
## that walks into an explosive prop lights it, and the bill goes to whoever lit the walker (ExplosiveProp).
static func culprit(a: Actor) -> Node:
	var b := _of(a)
	if b == null or b._source == null:
		return null
	return b._source.get_ref() as Node


## Seconds of fire left, 0 when not burning.
static func remaining(a: Actor) -> float:
	var b := _of(a)
	return maxf(0.0, b._ends_at - GameWorld.time) if b != null else 0.0


## Set `target` on fire for `duration` seconds, blamed on `source`. A burning actor is refreshed (the longer of
## the remaining time and `duration`), never stacked. Returns the fire, or null if the actor cannot burn.
static func ignite(target: Actor, source: Node, duration: float) -> Burning:
	if not can_burn(target) or duration <= 0.0:
		return null
	var b := _of(target)
	var ends := GameWorld.time + duration
	if b != null:
		var was := b._ends_at
		b._ends_at = maxf(b._ends_at, ends)
		if source != null:
			b._source = weakref(source)
		if b._ends_at > was + 0.5:
			Net.status_changed(target, "burn")
		return b
	b = Burning.new()
	b.name = "Burning"
	b.target = target
	b._source = weakref(source) if source != null else null
	b._ends_at = ends
	b._next_tick = GameWorld.time + TICK
	b._next_scorch = GameWorld.time + 1.0
	target.add_child(b)
	Fx.attach_hit_feedback(target)
	Fx.number(target.global_position + Vector3(0, 2.4 + target.radius, 0), "FIRE!", OUTER.lightened(0.15), 0.8)
	Net.status_changed(target, "burn")   # (online, on the owner: the other screens show the flames)
	return b


## Show a fire its owner announced (NetStatus, M4) on this machine's copy of `target`: the flames for `seconds`. It
## deals nothing here (only the owner ticks a fire); the owner's "out" ends it early.
static func show_remote(target: Actor, seconds: float) -> void:
	if seconds <= 0.0:
		var b := _of(target)
		if b != null:
			b._finish("extinguished")
		return
	if not can_burn(target):
		return
	var b := _of(target)
	if b != null:
		b._ends_at = GameWorld.time + seconds
		return
	b = Burning.new()
	b.name = "Burning"
	b.target = target
	b._ends_at = GameWorld.time + seconds
	b._next_tick = GameWorld.time + TICK
	b._next_scorch = GameWorld.time + 1.0
	target.add_child(b)


## Put out the fire. True if there was one.
static func extinguish(a: Actor) -> bool:
	var b := _of(a)
	if b == null:
		return false
	b._finish("extinguished")
	return true


## Put out every fire within `radius` of `pos` (team -1 = any). Returns how many were burning.
static func extinguish_in_radius(pos: Vector3, radius: float, team: int = -1) -> int:
	var n := 0
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if Net.resolves(a) and extinguish(a):   # (online: each fire's owner puts it out; the others are told, NetStatus)
			n += 1
	return n


## A fireball exploded at `pos`: every actor in the blast rolls to ignite (GameWorld.rng, in actor order, so a
## seeded run is repeatable). Returns the actors that caught fire.
static func on_blast(pos: Vector3, radius: float, power: float, source: Node) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius):
		if not can_burn(a):
			if is_soaked(a) and not a.dead:
				_fizzle(a)   # damp: the blast hisses out on a soaked actor (no roll, so the rng stream is unchanged)
			continue
		if not Net.resolves(a):
			continue   # (online: each actor's owner rolls its own ignition, with its own GameWorld.rng)
		var frac := GameWorld.flat_distance(a.global_position, pos) / maxf(radius, 0.001)
		if GameWorld.rng.randf() < ignite_chance(power, frac):
			if ignite(a, source, roll_duration()) != null:
				out.append(a)
	return out


## A soaked actor shrugs a fireball off: a puff of steam and a word.
static func _fizzle(a: Actor) -> void:
	var steam: Array[Color] = [Color(0.85, 0.92, 0.98), Color(0.6, 0.7, 0.78)]
	Fx.burst(a.global_position + Vector3.UP * 0.9, steam, 8, 1.4, 0.16, 0.8, -1.2, Vector3.UP, 45.0, false)
	Fx.number(a.global_position + Vector3(0, 2.4 + a.radius, 0), "FIZZLE", Color(0.6, 0.88, 1.0), 0.8)


static func _of(a: Actor) -> Burning:
	if a == null or not is_instance_valid(a):
		return null
	var b := a.get_node_or_null("Burning") as Burning
	return b if b != null and not b._over else null


# --- The fire -----------------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(GROUP)
	target.died.connect(_finish.bind("died"))
	_build_flames()


func _physics_process(_delta: float) -> void:
	if _over:
		return
	var now := GameWorld.time
	if target == null or target.dead:
		_finish("died")
		return
	if Burning.is_fireproof(target):
		_finish("extinguished")
		return
	var last := minf(now, _ends_at)
	var owned := Net.owns(target)   # (online: only the burning actor's owner ticks the damage; the rest show the flames)
	while _next_tick <= last and not _over:
		_next_tick += TICK
		if owned:
			_burn()
	if _over:
		return
	if now >= _ends_at:
		_finish("burnt_out")
		return
	if now >= _next_scorch:
		_next_scorch = now + SCORCH_EVERY
		Grime.mark(Grime.SCORCH, target.global_position, SCORCH_SIZE)


func _process(_delta: float) -> void:
	if _over:
		return
	var t := GameWorld.time
	var fade := clampf((_ends_at - t) / 0.8, 0.3, 1.0)   # the flames die down over the last 0.8 s
	for i in _flames.size():
		var b: Vector3 = _base[i]
		var f := 0.75 + 0.3 * sin(t * 11.0 + b.x) + 0.15 * sin(t * 23.0 + b.x * 2.0)
		_flames[i].scale = Vector3(1.0 + 0.12 * sin(t * 9.0 + b.x), b.y * f * fade, 1.0 + 0.12 * cos(t * 9.0 + b.x))
	if _light != null:
		_light.light_energy = (1.2 + 0.5 * sin(t * 17.0)) * fade


func _burn() -> void:
	var src: Node = _source.get_ref() as Node if _source != null else null
	var amount := TICK_DAMAGE
	# A hero's fire never downs a hero.
	var src_actor := src as Actor
	if target.team == GameWorld.TEAM_HEROES and src_actor != null and src_actor.team == GameWorld.TEAM_HEROES:
		amount = minf(amount, (target.hp - 1.0) / maxf(target.damage_taken_mult(), 0.0001))
	if amount > 0.0:
		target.apply_damage(amount, src)
	if not target.dead:
		var embers: Array[Color] = [INNER, OUTER]
		Fx.burst(target.global_position + Vector3.UP * _height() * 0.8, embers, 3, 1.2, 0.05, 0.55, -1.5, Vector3.UP, 50.0)


func _finish(reason: String) -> void:
	if _over:
		return
	_over = true
	remove_from_group(GROUP)
	ended.emit(reason)
	if target != null and is_instance_valid(target) and reason != "died":
		Net.status_changed(target, "burn")   # (the owner: the fire is out on every screen)
	queue_free()


func _height() -> float:
	if target != null and "ui_height" in target:
		var h: Variant = target.get("ui_height")
		if h is float and float(h) > 0.2:
			return float(h)
	return DEFAULT_HEIGHT


# --- Flames -------------------------------------------------------------------------------------

## Two shared flame meshes (outer orange, inner yellow) and their glowing materials.
static func _ensure_assets() -> void:
	if not _flame_meshes.is_empty():
		return
	var outer := LowPoly.cylinder(0.24, 0.0, 1.0, 5, OUTER, 3, 0.04, 2)
	var inner := LowPoly.cylinder(0.15, 0.0, 0.7, 4, INNER, 5, 0.03, 2)
	_flame_meshes.append(outer.to_mesh(0.0))
	_flame_meshes.append(inner.to_mesh(0.0))
	_flame_mats.append(LowPolyMaterial.make_glow(OUTER, 0.9, 1.2, OUTLINE))
	_flame_mats.append(LowPolyMaterial.make_glow(INNER, 1.2, 0.0))


func _build_flames() -> void:
	_ensure_assets()
	var h := _height()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(target.get_instance_id() & 0xFFFF)   # cosmetic only: never touches GameWorld.rng
	for i in FLAME_COUNT:
		var ang := TAU * float(i) / FLAME_COUNT + rng.randf_range(-0.3, 0.3)
		var top := i >= FLAME_COUNT - 2          # the last two lick up from the head and shoulders
		var ring := 0.0 if top else target.radius * rng.randf_range(1.2, 1.9)
		var y := h * 0.82 if top else h * (0.08 + 0.55 * float(i % 3) / 2.0) + rng.randf_range(0.0, 0.12)
		var big := i % 3 != 2
		var m := MeshInstance3D.new()
		m.mesh = _flame_meshes[0] if big else _flame_meshes[1]
		m.material_override = _flame_mats[0] if big else _flame_mats[1]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.set_meta("no_flash", true)
		var s := (h / DEFAULT_HEIGHT) * rng.randf_range(0.9, 1.3) * (0.8 if top else 1.0)
		m.position = Vector3(cos(ang) * ring, y + 0.5 * s, sin(ang) * ring)
		m.rotation = Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.0, TAU), rng.randf_range(-0.25, 0.25))
		add_child(m)
		_flames.append(m)
		_base.append(Vector3(rng.randf_range(0.0, TAU), s, 0.0))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, h * 0.5, 0)
	add_child(_light)
	_process(0.0)

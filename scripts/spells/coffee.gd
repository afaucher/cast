class_name Coffee
extends Node3D
## The Coffee spell ("cast coffee"): haste, then a crash. A status node that lives as a child of the caffeinated
## Actor. Everyone in a SMALL radius at the aim point (heroes, monsters, employees: "caffeinate the swarmers by
## accident") gets, for CoffeeSpell.coffee_duration seconds (6 at full power):
##   +60% move speed and +60% attack speed, as two Actor modifiers (STAT_MOVE_SPEED / STAT_ATTACK_RATE) that
##   stack by multiplication with anything else (a goo slow, a second source of haste) and are clamped;
##   and the jitters: a slight aim wobble for the LOCAL PLAYER (Coffee.jitter_aim, used by PlayerController) and
##   tiny random steps for everyone else (AI allies, monsters, employees: the host rolls them).
## Then the crash: -30% to both for 2 s. Drinking again refreshes the haste and cancels the crash (no stacking).
## Design record: docs/design/spells.md ("Coffee").
##
##   Coffee.cast(caster, power, point)        # the spell: drink() for everyone in range; a downed hero gets up a zombie
##   Coffee.drink(actor, seconds)             # caffeinate one actor (or refresh); null if it can't be
##   Coffee.is_hasted(actor) / is_crashing(actor) / is_caffeinated(actor)
##   Coffee.jitter_aim(actor, aim) -> Vector3 # the aim point as a twitchy, hasted hand would place it
##
## The speed system itself is Actor.set_modifier(id, mult, duration, stat); this node only schedules the two
## phases and the twitch, and draws the steam.
##
## Networking: the speed modifiers are replicated state (`_modifiers` is OWNER on Actor). This node is the status
## driver and runs where the target's owner runs: a hero's player, the host for everyone else. The twitch is that
## owner's roll (GameWorld.rng) and its result is just motion. The aim wobble is the local player's input and
## uses no random numbers at all (a sum of sines of the game clock).

const MOD_MOVE := "coffee_move"
const MOD_RATE := "coffee_rate"
const MOD_CRASH_MOVE := "coffee_crash_move"
const MOD_CRASH_RATE := "coffee_crash_rate"

const TWITCH_MIN_GAP := 0.35       ## seconds between random steps (rolled between these)
const TWITCH_MAX_GAP := 0.8
const TWITCH_TIME := 0.1           ## a step lasts this long ...
const TWITCH_DISTANCE := 0.22      ## ... and covers about this far
const AIM_JITTER := 0.06           ## radians (about 3.4 degrees) of aim wobble at most
const RING_HASTE := Color(1.0, 0.62, 0.18, 0.75)   ## the pulsing floor ring while hasted
const RING_CRASH := Color(0.5, 0.4, 0.34, 0.4)     ## ... and the dull one in the crash

var target: Actor = null

var _haste_end := 0.0              ## GameWorld.time the haste ends
var _crash_end := -1.0             ## GameWorld.time the crash ends; -1 while still hasted
var _next_twitch := 0.0
var _twitch_left := 0.0
var _twitch_dir := Vector3.ZERO
var _steam_fx: CPUParticles3D = null      ## the wisps off the head
var _steam_body: CPUParticles3D = null    ## ... and off the shoulders
var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
## A copy's look only (M4): the target's owner runs the status; on another machine this node just draws the steam and the
## ring from the modifiers the owner announced (NetStatus), and goes when they do.
var _remote := false


## Who may write each var (see Net). A status of the target, so it lives where the target's owner runs it.
func net_fields() -> Dictionary:
	return {
		"target": Net.SPAWN,
		"_haste_end": Net.OWNER, "_crash_end": Net.OWNER,
		"_next_twitch": Net.PRIVATE, "_twitch_left": Net.PRIVATE, "_twitch_dir": Net.PRIVATE,
		"_steam_fx": Net.LOCAL, "_steam_body": Net.LOCAL, "_ring": Net.LOCAL, "_ring_mat": Net.LOCAL,
		"_remote": Net.LOCAL,
	}


# --- Public API ---------------------------------------------------------------------------------

## The spell: everyone (any team) within CoffeeSpell.coffee_radius(power) of `pos` is caffeinated, and a DOWNED hero in it
## gets up as a zombie (CoffeeSpell.ZOMBIE_HP, gray and leaking: Hero.zombie) without the haste (the living drink first, so
## the one it stood up is not caffeinated by the same cup). Each target's owner applies it (Combat). Returns who drank.
static func cast(caster: Actor, power: float, pos: Vector3) -> Array[Actor]:
	var radius := CoffeeSpell.coffee_radius(power)
	var secs := CoffeeSpell.coffee_duration(power)
	var out := Combat.each_in_radius(pos, radius, func(a: Actor) -> void: Coffee.drink(a, secs))
	Combat.revive_radius(pos, radius, -1, CoffeeSpell.ZOMBIE_HP, 0.0, true)
	CoffeeFx.splash(pos, radius)   # on EVERY cast, even one that hits nobody: the spill, steam, droplets and the radius ring
	return out


## Caffeinate `a` for `seconds` of haste (then the crash). A second drink refreshes the haste to the longer of what
## is left and `seconds`, and cancels a crash that was running. Null if it cannot be caffeinated.
static func drink(a: Actor, seconds: float) -> Coffee:
	if a == null or not is_instance_valid(a) or a.dead or not a.is_inside_tree() or seconds <= 0.0:
		return null
	if a is Hellgate or a is PricedProp or a.is_in_group("breakables"):
		return null
	var c := _of(a)
	var fresh := c == null
	if fresh:
		c = Coffee.new()
		c.name = "Coffee"
		c.target = a
		a.add_child(c)
	c._refuel(seconds)
	if fresh:
		Fx.number(a.global_position + Vector3(0, 2.4 + a.radius, 0), "COFFEE!", SpellBook.color_of("coffee").lightened(0.25), 0.8)
	return c


## In the haste phase (the +60%).
static func is_hasted(a: Actor) -> bool:
	return a != null and is_instance_valid(a) and a.has_modifier(MOD_MOVE)


## In the crash (the -30%).
static func is_crashing(a: Actor) -> bool:
	return a != null and is_instance_valid(a) and a.has_modifier(MOD_CRASH_MOVE)


static func is_caffeinated(a: Actor) -> bool:
	return is_hasted(a) or is_crashing(a)


## The aim wobble in radians (0 unless hasted): two slow sines of the game clock, so it needs no random numbers and
## is smooth enough to read as shaky hands. At most AIM_JITTER.
static func aim_jitter_angle(a: Actor) -> float:
	if not is_hasted(a):
		return 0.0
	var t := GameWorld.time
	var ph := float(a.get_instance_id() % 97)
	return AIM_JITTER * (0.6 * sin(t * 14.0 + ph) + 0.4 * sin(t * 5.3 + ph * 1.7))


## `aim` rotated about the actor by the current wobble. The local player's aim goes through this.
static func jitter_aim(a: Actor, aim: Vector3) -> Vector3:
	var ang := aim_jitter_angle(a)
	if ang == 0.0:
		return aim
	var d := aim - a.global_position
	d.y = 0.0
	d = d.rotated(Vector3.UP, ang)
	return Vector3(a.global_position.x + d.x, aim.y, a.global_position.z + d.z)


## Draw coffee on a copy whose owner announced the haste (NetStatus): steam and the ring, nothing else (no schedule, no
## twitch, no modifiers: those are the owner's).
static func show_remote(a: Actor) -> void:
	if a == null or not is_instance_valid(a) or a.dead or not a.is_inside_tree() or _of(a) != null:
		return
	if a is Hellgate or a is PricedProp or a.is_in_group("breakables"):
		return
	var c := Coffee.new()
	c.name = "Coffee"
	c.target = a
	c._remote = true
	a.add_child(c)


static func _of(a: Actor) -> Coffee:
	var c := a.get_node_or_null("Coffee") as Coffee
	return c if c != null and not c.is_queued_for_deletion() else null


# --- The status ---------------------------------------------------------------------------------

func _ready() -> void:
	if not _remote:
		_next_twitch = GameWorld.time + GameWorld.rng.randf_range(TWITCH_MIN_GAP, TWITCH_MAX_GAP)
	_build_steam()
	_build_ring()
	if not target.died.is_connected(queue_free):
		target.died.connect(queue_free)


func _refuel(seconds: float) -> void:
	var now := GameWorld.time
	if _crash_end >= 0.0:
		_crash_end = -1.0
		target.clear_modifier(MOD_CRASH_MOVE)
		target.clear_modifier(MOD_CRASH_RATE)
		_haste_end = 0.0
	_haste_end = maxf(_haste_end, now + seconds)
	var left := _haste_end - now
	target.set_modifier(MOD_MOVE, CoffeeSpell.COFFEE_MOVE_MULT, left, Actor.STAT_MOVE_SPEED)
	target.set_modifier(MOD_RATE, CoffeeSpell.COFFEE_ATTACK_MULT, left, Actor.STAT_ATTACK_RATE)
	if _steam_fx != null:
		_steam_fx.emitting = true
	if _steam_body != null:
		_steam_body.emitting = true
	if _ring_mat != null:
		_ring_mat.albedo_color = RING_HASTE


func _process(_delta: float) -> void:
	if _ring == null:
		return
	var hasted := _crash_end < 0.0
	var pulse := 1.0 + (0.12 * sin(GameWorld.time * 16.0) if hasted else 0.04 * sin(GameWorld.time * 3.0))
	_ring.scale = Vector3(pulse, 1.0, pulse)


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		queue_free()
		return
	if _remote:
		_show_remote_phase()
		return
	var now := GameWorld.time
	if _crash_end < 0.0:
		if now >= _haste_end:
			_start_crash(now)
		else:
			_twitch(now, delta)
	elif now >= _crash_end:
		queue_free()


## A copy: follow the announced modifiers (haste, then the crash, then gone).
func _show_remote_phase() -> void:
	if not Coffee.is_caffeinated(target):
		queue_free()
		return
	if Coffee.is_crashing(target) and _crash_end < 0.0:
		_crash_end = GameWorld.time
		if _steam_fx != null:
			_steam_fx.emitting = false
		if _steam_body != null:
			_steam_body.emitting = false
		if _ring_mat != null:
			_ring_mat.albedo_color = RING_CRASH


func _start_crash(now: float) -> void:
	_crash_end = now + CoffeeSpell.COFFEE_CRASH_TIME
	target.set_modifier(MOD_CRASH_MOVE, CoffeeSpell.COFFEE_CRASH_MULT, CoffeeSpell.COFFEE_CRASH_TIME, Actor.STAT_MOVE_SPEED)
	target.set_modifier(MOD_CRASH_RATE, CoffeeSpell.COFFEE_CRASH_MULT, CoffeeSpell.COFFEE_CRASH_TIME, Actor.STAT_ATTACK_RATE)
	if _steam_fx != null:
		_steam_fx.emitting = false
	if _steam_body != null:
		_steam_body.emitting = false
	if _ring_mat != null:
		_ring_mat.albedo_color = RING_CRASH
	CoffeeFx.crash(self, _head_height())
	Fx.number(target.global_position + Vector3(0, 2.4 + target.radius, 0), "crash...", Color(0.75, 0.62, 0.5), 0.7)


## Tiny random steps for everyone but the local player (who gets the aim wobble instead). A step is a short
## walk through Actor.move, so it respects walls, roots and the speed modifiers; monsters winding up an attack and
## anyone helpless stand still. Facing is put back so the twitch never turns the actor.
func _twitch(now: float, delta: float) -> void:
	var hero := target as Hero
	if hero != null and hero.is_player:
		return
	if _twitch_left > 0.0:
		_twitch_left -= delta
		if not target.is_helpless() and not target.is_rooted():
			var f := target.facing
			var speed := maxf(target.effective_speed(), 0.01)
			target.move(_twitch_dir * clampf(TWITCH_DISTANCE / (speed * TWITCH_TIME), 0.0, 1.0), delta)
			target.facing = f
		return
	if now < _next_twitch:
		return
	_next_twitch = now + GameWorld.rng.randf_range(TWITCH_MIN_GAP, TWITCH_MAX_GAP)
	var mon := target as Monster
	if mon != null and mon.state == Monster.State.ATTACK:
		return
	var ang := GameWorld.rng.randf() * TAU
	_twitch_dir = Vector3(cos(ang), 0.0, sin(ang))
	_twitch_left = TWITCH_TIME


func _head_height() -> float:
	var h := 1.6
	if "ui_height" in target:
		var v: Variant = target.get("ui_height")
		if v is float and float(v) > 0.2:
			h = float(v)
	return h


## Clearly visible steam for the whole haste: a thick plume of wisps off the head and a second one off the shoulders.
func _build_steam() -> void:
	var h := _head_height()
	var r := maxf(target.radius, 0.3)
	_steam_fx = CoffeeFx.steam(r * 0.6, 0.3, 26)
	_steam_fx.position = Vector3(0, h * 0.98, 0)
	add_child(_steam_fx)
	_steam_fx.emitting = true
	_steam_body = CoffeeFx.steam(r * 1.1, 0.24, 16)
	_steam_body.position = Vector3(0, h * 0.5, 0)
	_steam_body.initial_velocity_min = 0.5
	_steam_body.initial_velocity_max = 1.1
	add_child(_steam_body)
	_steam_body.emitting = true


## A thin glowing ring on the floor around the feet: amber and pulsing while hasted, dull in the crash.
func _build_ring() -> void:
	var tor := TorusMesh.new()
	var r := maxf(target.radius, 0.3) * 1.7
	tor.inner_radius = r - 0.05
	tor.outer_radius = r + 0.05
	tor.rings = 24
	tor.ring_segments = 5
	_ring_mat = Fx.glow_material(RING_HASTE)
	_ring = MeshInstance3D.new()
	_ring.mesh = tor
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.set_meta("no_flash", true)
	_ring.position = Vector3(0, 0.08, 0)
	add_child(_ring)

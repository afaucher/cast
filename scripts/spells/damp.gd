class_name Damp
extends Node3D
## The Damp spell ("cast damp"). After a short telegraph a wide drizzle lands at this node's position:
##   - every fire in the area goes out (Burning.extinguish_in_radius);
##   - everyone in it (any team: heroes, monsters, employees) is soaked for DampSpell.DAMP_SOAK seconds
##     (Wet.douse -> Burning.soak): they cannot ignite until dry, so a fireball blast hisses out on them;
##   - the floor gets puddles. Most hex cells in the area turn wet for DAMP_PUDDLE_LIFE seconds (drying over the
##     last DAMP_DRY_TIME), drawn as Grime decals (which fade by themselves inside the 30 s player-mark rule),
##     and a shove that starts on a wet cell slides up to DAMP_SLIDE_BONUS further (Damp.slide_mult, which
##     Actor.shove asks).
## Damage: none. Design record: docs/design/spells.md ("Damp").
##
## Networking (networking.md, "Scheduled effect"): one cast event; every machine runs this node from its SPAWN
## params and `start_time`. Which cells are wet is a pure function of (position, radius, start_time), so every
## machine agrees without sending a puddle list (`wet_cells`). The soak is a status applied by each target's
## owner; the puddles are cosmetic plus the shove factor, which each owner applies to its own shoves.

const GROUP := "damp_fields"
const TELEGRAPH := 0.2
const PUDDLE_CHANCE := 0.8         ## of the cells in the area (the middle ones always are)
const CORE_FRAC := 0.4             ## cells this close to the centre (fraction of the radius) are always wet

var power := 1.0
var source_team := GameWorld.TEAM_HEROES
var caster: Actor = null
## The cast's GameWorld.time. The Net layer stamps it so every machine runs the same schedule; -1 = start now.
var start_time := -1.0

var _burst_done := false
var _end := 0.0
var _wet: Dictionary = {}          ## Vector2i -> true, filled at the burst
var _rain: CPUParticles3D = null


## Who may write each var (see Net). A scheduled effect: params SPAWN, everything else recomputed locally.
func net_fields() -> Dictionary:
	return {
		"power": Net.SPAWN, "source_team": Net.SPAWN, "caster": Net.SPAWN, "start_time": Net.SPAWN,
		"_burst_done": Net.LOCAL, "_end": Net.LOCAL, "_wet": Net.LOCAL, "_rain": Net.LOCAL,
	}


func _ready() -> void:
	add_to_group(GROUP)
	if start_time < 0.0:
		start_time = GameWorld.time
	_end = start_time + TELEGRAPH + DampSpell.DAMP_PUDDLE_LIFE
	var col := SpellBook.color_of("damp")
	Fx.ring(global_position, DampSpell.damp_radius(power), Color(col.r, col.g, col.b, 0.7), TELEGRAPH + 0.35, 0.0, false, 0.3)


func _physics_process(_delta: float) -> void:
	var t := GameWorld.time
	if not _burst_done and t >= start_time + TELEGRAPH:
		_burst()
	if t >= _end:
		queue_free()


# --- Public API ---------------------------------------------------------------------------------

## Shove-distance multiplier for `a` from any wet floor under it (1.0 = dry): up to 1 + DAMP_SLIDE_BONUS on a
## wet cell, fading to 1 as the puddles dry. Actor.shove multiplies by this.
static func slide_mult(a: Actor) -> float:
	if not a.is_inside_tree():
		return 1.0
	var tree := a.get_tree()
	var best := 1.0
	for n in tree.get_nodes_in_group(GROUP):
		var d := n as Damp
		if d != null:
			best = maxf(best, d.slide_at(a.global_position))
	return best


## This field's shove multiplier at a world point.
func slide_at(pos: Vector3) -> float:
	if not _burst_done or not _wet.has(Hex.from_world(pos)):
		return 1.0
	return 1.0 + DampSpell.DAMP_SLIDE_BONUS * wetness()


## 1.0 while the puddles are fresh, easing to 0 over the last DAMP_DRY_TIME seconds, 0 once gone.
func wetness() -> float:
	return clampf((_end - GameWorld.time) / DampSpell.DAMP_DRY_TIME, 0.0, 1.0)


## Is the cell under `pos` wet right now?
func is_wet_at(pos: Vector3) -> bool:
	return _burst_done and wetness() > 0.0 and _wet.has(Hex.from_world(pos))


func wet_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in _wet:
		out.append(c)
	return out


## Which cells a damp cast at `centre` (radius `radius`, stamped `stamp`) wets. Pure: the same answer on every
## machine, from the cast's own numbers.
static func plan_cells(centre: Vector3, radius: float, stamp: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var key := int(roundf(stamp * 60.0))
	var home := Hex.from_world(centre)
	var span := int(ceilf(radius / (Hex.SIZE * Hex.SQRT3 * 0.5))) + 1
	for c in Hex.range_cells(home, span):
		var d := GameWorld.flat_distance(Hex.to_world(c), centre)
		if d > radius:
			continue
		if GameWorld.map != null and not GameWorld.map.is_walkable_cell(c):
			continue
		var roll := float(posmod(hash(Vector3i(c.x, c.y, key)), 1000)) / 1000.0
		if d <= radius * CORE_FRAC or roll < PUDDLE_CHANCE:
			out.append(c)
	return out


# --- The burst ----------------------------------------------------------------------------------

func _burst() -> void:
	_burst_done = true
	var radius := DampSpell.damp_radius(power)
	var pos := global_position
	var out := Burning.extinguish_in_radius(pos, radius)
	if out > 0:
		var steam: Array[Color] = [Color(0.92, 0.96, 1.0), Color(0.65, 0.74, 0.82)]
		Fx.burst(pos + Vector3.UP * 0.6, steam, 14 + 3 * out, radius * 0.8, 0.22, 1.1, -1.4, Vector3.UP, 70.0, false)
	for a in Wet.douse_in_radius(pos, radius, DampSpell.DAMP_SOAK):
		if not a.is_in_group("breakables"):
			Fx.number(a.global_position + Vector3(0, 2.4 + a.radius, 0), "DAMP", SpellBook.color_of("damp").lightened(0.2), 0.7)
	for c in plan_cells(pos, radius, start_time):
		_wet[c] = true
		Grime.mark(Grime.WET, Hex.to_world(c), Hex.INNER * 0.95)
	_make_rain(radius)
	Fx.ring(pos, radius, Color(0.5, 0.88, 1.0, 0.8), 0.6, 0.0, false, 0.2)


## The drizzle itself: droplets falling over the whole area for a moment (cosmetic).
func _make_rain(radius: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.14
	sm.radial_segments = 5
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.88, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = mat
	_rain = CPUParticles3D.new()
	_rain.amount = int(40.0 + 14.0 * radius)
	_rain.lifetime = 0.75
	_rain.one_shot = true
	_rain.explosiveness = 0.35
	_rain.direction = Vector3.DOWN
	_rain.spread = 4.0
	_rain.initial_velocity_min = 6.0
	_rain.initial_velocity_max = 9.0
	_rain.gravity = Vector3(0, -12.0, 0)
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_rain.emission_sphere_radius = radius * 0.9
	_rain.mesh = sm
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.position = Vector3(0, 3.2, 0)
	add_child(_rain)
	_rain.emitting = true

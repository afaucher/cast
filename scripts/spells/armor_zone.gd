class_name ArmorZone
extends Node3D
## Armor spell: a stationary zone. Every tick it refreshes a short-lived
## "armor" damage-taken modifier on friendly heroes inside, so the buff drops
## ~0.3 s after they step out (or the zone ends). Draws a pulsing blue hex
## dome + ground ring. Timing uses GameWorld.time.

const RADIUS := 3.0
const TICK := 0.25
const MODIFIER_DURATION := 0.3

var team := GameWorld.TEAM_HEROES
var power := 1.0
## The cast's GameWorld.time (SPAWN, from the cast event, M4a): the zone lasts armor_duration(power) from it. -1 = now.
var start_time := -1.0

var _end_time := 0.0
var _next_tick := 0.0
var _expiring := false
var _dome_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _floor_mat: StandardMaterial3D
var _visual: Node3D
var _next_pulse := 0.0


func _ready() -> void:
	if start_time < 0.0:
		start_time = GameWorld.time
	_end_time = start_time + SpellBook.armor_duration(power)
	_build_visual()
	_apply()


## Who may write each var (see Net). A scheduled effect: one cast event, then every machine runs
## the zone from team + power and GameWorld.time.
func net_fields() -> Dictionary:
	return {
		"team": Net.SPAWN, "power": Net.SPAWN, "start_time": Net.SPAWN,
		"_end_time": Net.LOCAL, "_next_tick": Net.LOCAL, "_expiring": Net.LOCAL, "_next_pulse": Net.LOCAL,
		"_dome_mat": Net.LOCAL, "_ring_mat": Net.LOCAL, "_floor_mat": Net.LOCAL, "_visual": Net.LOCAL,
	}


func _physics_process(_delta: float) -> void:
	if _expiring:
		return
	var t := GameWorld.time
	if t >= _end_time:
		_expire()
		return
	if t >= _next_tick:
		_apply()
		_next_tick = t + TICK


## Remaining lifetime in game seconds.
func time_left() -> float:
	return maxf(0.0, _end_time - GameWorld.time)


## Each hero's owner applies its own armor (Combat.modify_radius, layer 4): the zone runs on every machine.
func _apply() -> void:
	Combat.modify_radius(global_position, RADIUS, "armor", SpellBook.armor_multiplier(power), MODIFIER_DURATION, Actor.STAT_DAMAGE_TAKEN, team)


func _expire() -> void:
	_expiring = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_dome_mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(_ring_mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(_floor_mat, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(queue_free)


func _build_visual() -> void:
	var col := SpellBook.color_of("armor")
	_visual = Node3D.new()
	add_child(_visual)
	# Hex dome (a 6-sided hemisphere).
	var dome := SphereMesh.new()
	dome.radius = RADIUS
	dome.height = RADIUS * 2.0
	dome.is_hemisphere = true
	dome.radial_segments = 6
	dome.rings = 4
	_dome_mat = Fx.glow_material(Color(col.r, col.g, col.b, 0.16), false)
	_dome_mat.emission_enabled = true
	_dome_mat.emission = col
	_dome_mat.emission_energy_multiplier = 0.4
	_dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var dome_mi := MeshInstance3D.new()
	dome_mi.mesh = dome
	dome_mi.material_override = _dome_mat
	dome_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(dome_mi)
	# Hex outline on the ground.
	var tor := TorusMesh.new()
	tor.inner_radius = RADIUS - 0.07
	tor.outer_radius = RADIUS + 0.07
	tor.rings = 6
	tor.ring_segments = 6
	_ring_mat = Fx.glow_material(Color(col.r, col.g, col.b, 0.9))
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = tor
	ring_mi.material_override = _ring_mat
	ring_mi.position.y = 0.08
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(ring_mi)
	# Faint floor tint.
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.02
	disc.radial_segments = 6
	_floor_mat = Fx.glow_material(Color(col.r, col.g, col.b, 0.12))
	var disc_mi := MeshInstance3D.new()
	disc_mi.mesh = disc
	disc_mi.material_override = _floor_mat
	disc_mi.position.y = 0.06
	disc_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(disc_mi)
	for mi in [dome_mi, ring_mi, disc_mi]:
		mi.set_meta("no_flash", true)
	_visual.scale = Vector3(0.2, 0.2, 0.2)
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.ring(global_position, RADIUS, Color(col.r, col.g, col.b, 0.8), 0.5, 0.0, true, 0.3)


func _process(_delta: float) -> void:
	if _expiring or _dome_mat == null:
		return
	var t := GameWorld.time
	var wave := 0.5 + 0.5 * sin(t * 4.0)
	_dome_mat.albedo_color.a = 0.12 + 0.1 * wave
	_ring_mat.albedo_color.a = 0.65 + 0.3 * wave
	# Blink in the last second so players know it is about to end.
	if time_left() < 1.0:
		_visual.visible = int(t * 8.0) % 2 == 0
	if t >= _next_pulse:
		_next_pulse = t + 1.4
		var col := SpellBook.color_of("armor")
		Fx.ring(global_position, RADIUS, Color(col.r, col.g, col.b, 0.35), 1.0, 1.2, true, 0.3)

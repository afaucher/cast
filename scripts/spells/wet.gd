class_name Wet
extends Node3D
## "You are soggy": the status Damp gives everyone in its area. A node that lives as a child of the soaked
## Actor and only DRAWS the damp: drips falling off the body and wet footprints behind it. The rule itself
## (cannot ignite until dry) is Burning.soak, which keeps the end time on the actor, so there is one clock.
##
##   Wet.douse(actor, seconds)                 # soak (puts out a fire, no ignition until dry) and drip
##   Wet.douse_in_radius(pos, radius, seconds) # everyone in an area, returns who was doused
##   Wet.is_wet(actor) / Wet.remaining(actor)
##
## A soaked actor's blast from a fireball fizzles (Burning.on_blast), and a wet floor is Damp's job.
## Networking: the soak is a status applied by the target's owner (a hero's player, the host for the rest);
## this node is cosmetic and every machine can draw it from the soak time.

const FOOT_STEP := 0.75            ## world units walked between footprints
const FOOT_LIFE := 3.5             ## a wet footprint fades in this many seconds
const MAX_FEET := 10               ## alive footprints per actor
const DRIP := Color(0.55, 0.85, 1.0, 0.9)
const PRINT := Color(0.25, 0.55, 0.78, 0.5)

static var _drip_mesh: SphereMesh = null
static var _print_mesh: CylinderMesh = null

var target: Actor = null

var _drips: CPUParticles3D = null
var _last_pos := Vector3.ZERO
var _side := 1.0
var _feet: Array[MeshInstance3D] = []


## Who may write each var (see Net). Cosmetic: the soak time lives on the actor (Burning.soak).
func net_fields() -> Dictionary:
	return {
		"target": Net.SPAWN,
		"_drips": Net.LOCAL, "_last_pos": Net.LOCAL, "_side": Net.LOCAL, "_feet": Net.LOCAL,
	}


# --- Public API ---------------------------------------------------------------------------------

## Soak `a` for `seconds` (refreshes to the longer of what is left and the new time). Returns the Wet node, or
## null when the actor is gone or is inanimate (a hellgate, a priced prop, a mail package: they get no drips).
static func douse(a: Actor, seconds: float) -> Wet:
	if a == null or not is_instance_valid(a) or a.dead or not a.is_inside_tree() or seconds <= 0.0:
		return null
	var until := GameWorld.time + seconds
	if Burning.is_soaked(a):
		until = maxf(until, GameWorld.time + Burning.soaked_left(a))
	Burning.soak(a, until - GameWorld.time)   # puts out any fire too
	if a is Hellgate or a is PricedProp or a.is_in_group("breakables"):
		return null
	var w := a.get_node_or_null("Wet") as Wet
	if w == null:
		w = Wet.new()
		w.name = "Wet"
		w.target = a
		a.add_child(w)
	return w


## Soak everyone (any team, or `team` if >= 0) within `radius` of `pos`. Returns the actors doused.
static func douse_in_radius(pos: Vector3, radius: float, seconds: float, team: int = -1) -> Array[Actor]:
	return Combat.each_in_radius(pos, radius, func(a: Actor) -> void: Wet.douse(a, seconds), team)


static func is_wet(a: Actor) -> bool:
	return Burning.is_soaked(a)


static func remaining(a: Actor) -> float:
	return Burning.soaked_left(a)


# --- The look -----------------------------------------------------------------------------------

func _ready() -> void:
	_last_pos = target.global_position
	_build_drips()


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead or not Burning.is_soaked(target):
		queue_free()
		return
	var p := target.global_position
	if GameWorld.flat_distance(p, _last_pos) >= FOOT_STEP and not target.is_airborne():
		_last_pos = p
		_footprint(p)


func _exit_tree() -> void:
	# The footprints belong to the world, not to the actor: let them finish fading on their own.
	_feet.clear()


func _build_drips() -> void:
	if _drip_mesh == null:
		_drip_mesh = SphereMesh.new()
		_drip_mesh.radius = 0.035
		_drip_mesh.height = 0.09
		_drip_mesh.radial_segments = 5
		_drip_mesh.rings = 3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = DRIP
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_drip_mesh.material = mat
	var h := 1.5
	if "ui_height" in target:
		var v: Variant = target.get("ui_height")
		if v is float and float(v) > 0.2:
			h = float(v)
	_drips = CPUParticles3D.new()
	_drips.amount = 14
	_drips.lifetime = 0.55
	_drips.local_coords = false
	_drips.direction = Vector3.DOWN
	_drips.spread = 25.0
	_drips.initial_velocity_min = 0.1
	_drips.initial_velocity_max = 0.5
	_drips.gravity = Vector3(0, -9.0, 0)
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_drips.emission_sphere_radius = maxf(target.radius, 0.3)
	_drips.mesh = _drip_mesh
	_drips.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drips.position = Vector3(0, h * 0.62, 0)
	add_child(_drips)
	_drips.emitting = true


## A small wet print where the actor just stood, alternating left and right; it fades over a few seconds.
func _footprint(at: Vector3) -> void:
	if not Fx._world_ready():
		return
	if _print_mesh == null:
		_print_mesh = CylinderMesh.new()
		_print_mesh.top_radius = 0.17
		_print_mesh.bottom_radius = 0.17
		_print_mesh.height = 0.01
		_print_mesh.radial_segments = 8
	while _feet.size() >= MAX_FEET:
		var old: Variant = _feet.pop_front()   # (a print that faded out on its own is already freed)
		if is_instance_valid(old):
			old.queue_free()
	var mat := Fx.glow_material(PRINT, false)
	var mi := MeshInstance3D.new()
	mi.mesh = _print_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	var side := Vector3(-target.facing.z, 0.0, target.facing.x) * 0.16 * _side
	_side = -_side
	var jitter := Vector3(GameWorld.fx_rng.randf_range(-0.03, 0.03), 0.0, GameWorld.fx_rng.randf_range(-0.03, 0.03))
	mi.scale = Vector3(0.8, 1.0, 1.3)
	GameWorld.spawn(mi, Vector3(at.x, at.y + 0.035, at.z) + side + jitter)
	mi.rotation.y = atan2(target.facing.x, target.facing.z)
	_feet.append(mi)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, FOOT_LIFE).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)

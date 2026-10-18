class_name CornStrike
extends Node3D
## The joke spell. A growing target ring telegraphs the spot for DELAY seconds
## (game time), a giant corn cob drops out of the sky during the final
## FALL_TIME, slams (damaging EVERYONE in RADIUS, friend or foe) and bursts
## into popcorn with a comedic squash.

const DELAY := 1.2
const FALL_TIME := 0.45
const RADIUS := 2.5
const DAMAGE := 60.0
const DROP_HEIGHT := 18.0
const COB_HEIGHT := 3.4
const COB_RADIUS := 0.8

var power := 1.0
var source_team := GameWorld.TEAM_HEROES
var caster: Actor = null
## The cast's GameWorld.time (SPAWN): the telegraph runs from it and the cob lands DELAY after it, on every machine alike
## (M4a: the cast event carries the moment). -1 = start now.
var start_time := -1.0

## The cob hit the floor (the damage was dealt where this machine resolves it). Tests and screen effects.
signal landed(pos: Vector3)

var _slammed := false
var _telegraph: Node3D
var _disc_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _cob: Node3D


func _ready() -> void:
	if start_time < 0.0:
		start_time = GameWorld.time
	_build_telegraph()
	_build_cob()


## Who may write each var (see Net). A scheduled effect: one cast event, then every machine runs
## the strike from these parameters and GameWorld.time.
func net_fields() -> Dictionary:
	return {
		"power": Net.SPAWN, "source_team": Net.SPAWN,
		"caster": Net.SPAWN,      # travels as the caster's net id in the cast event (NetCasts)
		"start_time": Net.SPAWN,  # the cast's moment, from the cast event
		"_slammed": Net.LOCAL,
		"_telegraph": Net.LOCAL, "_disc_mat": Net.LOCAL, "_ring_mat": Net.LOCAL, "_cob": Net.LOCAL,
	}


func _physics_process(_delta: float) -> void:
	if not _slammed and GameWorld.time - start_time >= DELAY:
		_slam()


func _process(_delta: float) -> void:
	if _slammed or _telegraph == null:
		return
	var t := GameWorld.time - start_time
	var k := clampf(t / DELAY, 0.0, 1.0)
	_telegraph.scale = Vector3.ONE * lerpf(0.15, 1.0, 1.0 - pow(1.0 - k, 3.0))
	var flicker := 0.5 + 0.5 * sin(t * (6.0 + 22.0 * k))
	_disc_mat.albedo_color.a = 0.12 + 0.28 * k * (0.6 + 0.4 * flicker)
	_ring_mat.albedo_color.a = 0.5 + 0.5 * flicker
	# Cob drops during the last FALL_TIME seconds.
	var fall_k := clampf((t - (DELAY - FALL_TIME)) / FALL_TIME, 0.0, 1.0)
	_cob.visible = fall_k > 0.0
	_cob.position.y = COB_HEIGHT * 0.5 + DROP_HEIGHT * (1.0 - fall_k * fall_k)
	_cob.rotation.y = t * 6.0
	_cob.rotation.z = deg_to_rad(18.0) * (1.0 - fall_k)


func _slam() -> void:
	_slammed = true
	var pos := global_position
	var team_arg := -1  # everyone: heroes, caster and monsters alike
	for a in GameWorld.actors_in_radius(pos, RADIUS, team_arg):
		Fx.attach_hit_feedback(a)
	var src: Node = caster if is_instance_valid(caster) else null
	Combat.explode(pos, RADIUS, SpellBook.corn_damage(power), team_arg, src, 1.0)   # (each machine: what it resolves)
	landed.emit(pos)
	Fx.shake(1.0)
	_telegraph.visible = false
	# Squash, then pop into popcorn.
	_cob.visible = true
	_cob.rotation.z = 0.0
	_cob.position.y = COB_HEIGHT * 0.5
	var tw := create_tween()
	tw.tween_property(_cob, "scale", Vector3(1.6, 0.45, 1.6), 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.12)
	tw.tween_callback(_pop)


func _pop() -> void:
	var pos := global_position
	_cob.visible = false
	var white: Array[Color] = [Color(1, 1, 0.95), Color(1, 0.97, 0.8), Color(1, 0.92, 0.55)]
	Fx.burst(pos + Vector3.UP * 0.4, white, 60, 8.0, 0.16, 1.3, 16.0, Vector3.UP, 75.0, false)
	var gold: Array[Color] = [Color(1, 0.85, 0.2), Color(1, 0.95, 0.6)]
	Fx.burst(pos + Vector3.UP * 0.4, gold, 30, 5.0, 0.1, 1.0, 14.0, Vector3.UP, 90.0, false)
	Fx.ring(pos, RADIUS, Color(1.0, 0.9, 0.3, 0.9), 0.5, 0.0, false, 0.2)
	Fx.flash_sphere(pos + Vector3.UP * 0.6, 1.2, Color(1, 0.95, 0.6, 0.7), 0.25)
	Fx.number(pos + Vector3.UP * 2.8, "POP!", Color(1.0, 0.95, 0.4), 1.6)
	Grime.mark(Grime.CORN, pos, RADIUS)   # kernels + a scorch ring that fade after 30 s
	get_tree().create_timer(1.6).timeout.connect(queue_free)


# --- Visuals -----------------------------------------------------------------------------

func _build_telegraph() -> void:
	_telegraph = Node3D.new()
	add_child(_telegraph)
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.02
	disc.radial_segments = 32
	_disc_mat = Fx.glow_material(Color(1.0, 0.8, 0.15, 0.15))
	var d := MeshInstance3D.new()
	d.mesh = disc
	d.material_override = _disc_mat
	d.position.y = 0.1
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.add_child(d)
	var tor := TorusMesh.new()
	tor.inner_radius = RADIUS - 0.08
	tor.outer_radius = RADIUS + 0.08
	tor.rings = 40
	tor.ring_segments = 6
	_ring_mat = Fx.glow_material(Color(1.0, 0.9, 0.3, 0.8))
	var r := MeshInstance3D.new()
	r.mesh = tor
	r.material_override = _ring_mat
	r.position.y = 0.12
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_telegraph.add_child(r)
	d.set_meta("no_flash", true)
	r.set_meta("no_flash", true)
	_telegraph.scale = Vector3.ONE * 0.15


func _build_cob() -> void:
	_cob = Node3D.new()
	_cob.visible = false
	add_child(_cob)
	# Cob: a yellow capsule with darker kernel bands, tip pointing down.
	var body := CapsuleMesh.new()
	body.radius = COB_RADIUS
	body.height = COB_HEIGHT
	body.radial_segments = 16
	body.rings = 8
	var yellow := Fx.solid_material(Color(1.0, 0.85, 0.15), 0.5)
	_add(_cob, body, yellow, Vector3.ZERO)
	var band_mat := Fx.solid_material(Color(0.9, 0.62, 0.05), 0.6)
	for i in 5:
		var tor := TorusMesh.new()
		var y := -COB_HEIGHT * 0.32 + i * COB_HEIGHT * 0.17
		var rr := COB_RADIUS * cos(clampf(y / (COB_HEIGHT * 0.5), -1.0, 1.0) * 0.5) * 0.98
		tor.inner_radius = rr - 0.05
		tor.outer_radius = rr + 0.05
		tor.rings = 20
		tor.ring_segments = 5
		_add(_cob, tor, band_mat, Vector3(0, y, 0))
	# Husk: green leaves flaring out of the stem end (top), plus a stem nub.
	var leaf_mat := Fx.solid_material(Color(0.25, 0.65, 0.2), 0.7)
	for i in 5:
		var leaf := SphereMesh.new()
		leaf.radius = 0.5
		leaf.height = 1.0
		leaf.radial_segments = 10
		leaf.rings = 5
		var holder := Node3D.new()
		holder.position = Vector3(0, COB_HEIGHT * 0.18, 0)
		holder.rotation.y = TAU * i / 5.0
		_cob.add_child(holder)
		var mi := _add(holder, leaf, leaf_mat, Vector3(0.0, 0.65, COB_RADIUS * 0.55))
		mi.scale = Vector3(0.5, 1.5, 0.16)
		mi.rotation.x = deg_to_rad(-22)
	var stem := CylinderMesh.new()
	stem.top_radius = 0.1
	stem.bottom_radius = 0.18
	stem.height = 0.5
	_add(_cob, stem, Fx.solid_material(Color(0.4, 0.5, 0.15)), Vector3(0, COB_HEIGHT * 0.5 + 0.35, 0))
	# Cartoon eyes on the side so the cob looks smug.
	var eye_mat := Fx.solid_material(Color.WHITE, 0.3)
	var pupil_mat := Fx.solid_material(Color.BLACK, 0.3)
	for sx in [-1.0, 1.0]:
		var eye := SphereMesh.new()
		eye.radius = 0.2
		eye.height = 0.4
		var e := _add(_cob, eye, eye_mat, Vector3(0.28 * sx, 0.1, COB_RADIUS * 0.82))
		e.scale = Vector3(1, 1.2, 0.6)
		var pupil := SphereMesh.new()
		pupil.radius = 0.09
		pupil.height = 0.18
		_add(_cob, pupil, pupil_mat, Vector3(0.28 * sx, 0.05, COB_RADIUS * 0.82 + 0.1))


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

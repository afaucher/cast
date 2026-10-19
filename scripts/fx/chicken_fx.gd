class_name ChickenFx
extends RefCounted
## The Chicken spell's feathers (scripts/spells/chicken.gd). Cosmetic only: every screen plays them from what it shows (the
## cast landing, a peck, a death), nothing here decides anything, and the only randomness is the particles' own.
##
##   ChickenFx.cast_cloud(pos)          the cast lands: a burst of feathers and white fluff the flock comes out of
##   ChickenFx.peck(chicken, victim)    a peck: a "0" over whatever it pecked and a little feather puff at the beak
##   ChickenFx.feather_explosion(pos)   a chicken killed: feathers everywhere and a "BAWK!"
##   ChickenFx.poof(pos)                a chicken's time is up: a soft white puff and a few feathers drifting down
##
## Sound (not built here; a separate Sfx system is coming): a cluck would hook in cast_cloud, a peck tick in peck, a squawk
## in feather_explosion and a soft "pop" in poof.

const WHITE := Color(0.98, 0.97, 0.93)
const CREAM := Color(0.92, 0.88, 0.78)
const RUST := Color(0.85, 0.36, 0.24)
const ZERO_COLOR := Color(0.92, 0.92, 0.9)

static var _feather_mesh: Mesh = null


## The cast lands: feathers and fluff burst up where the flock appears, with a ring in the spell's colour.
static func cast_cloud(pos: Vector3) -> void:
	if not Fx._world_ready():
		return
	var col := SpellBook.color_of("chicken")
	Fx.flash_sphere(pos + Vector3.UP * 0.4, 0.9, Color(1.0, 0.98, 0.92, 0.55), 0.3)
	_fluff(pos + Vector3.UP * 0.3, 16, 2.2, 0.16, 0.8)
	feathers(pos + Vector3.UP * 0.5, 22, 3.6, 1.6)
	Fx.ring(pos, 1.3, Color(col.r, col.g, col.b, 0.7), 0.5, 0.0, false, 0.2)


## A peck: a "0" over the victim (the colour of a hit on its side, so it reads as a hit that did nothing) and a puff of a
## few feathers at the beak. `victim` may be null (a peck at the air).
static func peck(chicken: Node3D, victim: Node3D) -> void:
	if chicken == null or not is_instance_valid(chicken) or not Fx._world_ready():
		return
	var fwd := Vector3.FORWARD
	var f: Variant = chicken.get("facing")
	if f is Vector3:
		fwd = f
	var beak := chicken.global_position + fwd * 0.3 + Vector3.UP * 0.25
	feathers(beak, 6, 1.6, 0.9, 0.75)
	if victim == null or not is_instance_valid(victim) or not victim.is_inside_tree():
		return
	var r: Variant = victim.get("radius")
	var head := victim.global_position + Vector3(GameWorld.fx_rng.randf_range(-0.2, 0.2), 2.0 + (float(r) if r != null else 0.4), 0.0)
	var team: Variant = victim.get("team")
	var col := Fx.NUMBER_HERO_HIT if team != null and int(team) == GameWorld.TEAM_HEROES else Fx.NUMBER_MONSTER_HIT
	Fx.number(head, "0", col, 0.85)
	Fx.flash(victim)


## A chicken is killed: a burst of feathers everywhere, white fluff, and a squawk.
static func feather_explosion(pos: Vector3) -> void:
	if not Fx._world_ready():
		return
	Fx.flash_sphere(pos + Vector3.UP * 0.35, 0.55, Color(1.0, 1.0, 0.95, 0.75), 0.18)
	feathers(pos + Vector3.UP * 0.4, 26, 4.2, 1.8)
	_fluff(pos + Vector3.UP * 0.35, 14, 2.8, 0.12, 0.55)
	Fx.number(pos + Vector3.UP * 1.5, "BAWK!", Chicken.BAWK, 0.75)


## A chicken's time is up: it poofs into a soft white puff and a few feathers that drift down.
static func poof(pos: Vector3) -> void:
	if not Fx._world_ready():
		return
	_fluff(pos + Vector3.UP * 0.35, 18, 1.4, 0.2, 0.9)
	feathers(pos + Vector3.UP * 0.5, 10, 2.0, 1.8)
	Fx.ring(pos, 0.7, Color(1.0, 1.0, 1.0, 0.5), 0.4, 0.2, false, 0.3)


## `n` feathers burst from `pos` at up to `speed`, then flutter down, tumbling, for about `life` seconds.
static func feathers(pos: Vector3, n: int, speed: float, life: float, size: float = 1.0) -> CPUParticles3D:
	if not Fx._world_ready():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(1, n)
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -2.2, 0)
	p.damping_min = 2.5
	p.damping_max = 4.0
	p.particle_flag_rotate_y = true
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 0.7 * size
	p.scale_amount_max = 1.25 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.75, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	grad.colors = PackedColorArray([WHITE, CREAM, RUST])
	p.color_initial_ramp = grad
	p.mesh = _feather()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GameWorld.spawn(p, pos)
	p.emitting = true
	Fx._free_later(p, life + 0.4)
	return p


## White fluff (down) bursting out and hanging in the air a moment.
static func _fluff(pos: Vector3, n: int, speed: float, size: float, life: float) -> void:
	var cols: Array[Color] = [Color(1.0, 1.0, 0.98), Color(0.9, 0.88, 0.84)]
	Fx.burst(pos, cols, n, speed, size, life, -0.6, Vector3.UP, 120.0, false)


## One feather: a flat, tapering blade with a quill, lit (not glowing) so it reads as a solid thing.
static func _feather() -> Mesh:
	if _feather_mesh != null:
		return _feather_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(0, 0, -0.18), Vector3(0.06, 0, -0.07), Vector3(0.05, 0, 0.08), Vector3(0, 0, 0.18),
		Vector3(-0.05, 0, 0.08), Vector3(-0.06, 0, -0.07)]
	for i in range(1, pts.size() - 1):
		for tri in [[pts[0], pts[i], pts[i + 1]], [pts[0], pts[i + 1], pts[i]]]:   # both faces
			var n := Vector3.UP if tri[1] == pts[i] else Vector3.DOWN
			for v: Vector3 in tri:
				st.set_normal(n)
				st.add_vertex(v)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.24, 0.22)
	mesh.surface_set_material(0, mat)
	_feather_mesh = mesh
	return mesh

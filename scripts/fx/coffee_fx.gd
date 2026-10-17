class_name CoffeeFx
extends RefCounted
## The look of the Coffee spell (cosmetic only: nothing here decides play, and it uses GameWorld.fx_rng, never
## GameWorld.rng). Three pieces, all cheap (a handful of CPU particles and two or three meshes):
##
##   CoffeeFx.splash(pos, radius)   # EVERY cast, hit or miss: a dark brown spilled-coffee splat on the floor (Grime, fades
##                                  # inside the 30 s player-mark rule), a puff of steam, flying droplets and an amber
##                                  # ring burst + faint disc that show the radius. Returns the splash root (group "coffee_splash").
##   CoffeeFx.steam(radius, size, amount)  # a billboard-free CPUParticles3D of cream steam wisps (an actor's hasted steam)
##   CoffeeFx.crash(parent, height)        # the crash: a droopy grey puff and "z z Z" drifting up off the actor
##
## The wisps are translucent cream spheres whose colour ramp fades them in and out, so they read against the dark floor
## and are visible at the default zoom (the old steam was 0.11 units wide at 80% alpha: a speck).

const AMBER := Color(1.0, 0.62, 0.18)
const COFFEE_BROWN := Color(0.30, 0.16, 0.07)
const STEAM_COLOR := Color(0.97, 0.92, 0.82)
const GROUP := "coffee_splash"
const SPLASH_LIFE := 1.8          ## seconds the splash root lives (its particles last about 1.5 s)
const ZZZ := Color(0.62, 0.64, 0.7)

static var _steam_mesh: SphereMesh = null


## The splash at the aim point. A miss looks like a splash too, and its ring is the radius that was cast.
static func splash(pos: Vector3, radius: float) -> Node3D:
	Grime.mark(Grime.COFFEE, pos, radius)   # the spilled-coffee splat (no-op without a GrimeLayer)
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return null
	var root := Node3D.new()
	root.name = "CoffeeSplash"
	root.add_to_group(GROUP)
	GameWorld.spawn(root, pos)
	# the radius: a thick amber ring bursting outward, a second smaller one behind it, and a faint amber disc
	_ring(root, radius, Color(AMBER.r, AMBER.g, AMBER.b, 0.95), 0.8, 0.12)
	_ring(root, radius * 0.62, Color(1.0, 0.82, 0.45, 0.8), 0.6, 0.08)
	_disc(root, radius, Color(AMBER.r, AMBER.g, AMBER.b, 0.32), 0.7)
	# a puff of steam rising off the spill
	var puff := steam(radius * 0.45, 0.34, 14)
	puff.one_shot = true
	puff.explosiveness = 0.85
	puff.lifetime = 1.5
	puff.initial_velocity_min = 0.9
	puff.initial_velocity_max = 1.9
	puff.position = Vector3(0, 0.2, 0)
	root.add_child(puff)
	puff.emitting = true
	# flying droplets: dark coffee flung up and out, falling back
	var drops := CPUParticles3D.new()
	drops.one_shot = true
	drops.explosiveness = 1.0
	drops.amount = 16
	drops.lifetime = 0.75
	drops.direction = Vector3.UP
	drops.spread = 62.0
	drops.initial_velocity_min = 2.5
	drops.initial_velocity_max = 5.5 + radius
	drops.gravity = Vector3(0, -15.0, 0)
	drops.scale_amount_min = 0.7
	drops.scale_amount_max = 1.4
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = COFFEE_BROWN.lightened(0.1)
	dm.roughness = 0.35
	sm.material = dm
	drops.mesh = sm
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.position = Vector3(0, 0.15, 0)
	root.add_child(drops)
	drops.emitting = true
	root.get_tree().create_timer(SPLASH_LIFE).timeout.connect(root.queue_free)
	return root


## Cream steam wisps: translucent spheres that fade in, drift up and fade out. `radius` is the emitter's spread, `size`
## the wisp radius, `amount` how many are alive at once. Continuous by default (one_shot = true for a puff).
static func steam(radius: float, size: float, amount: int) -> CPUParticles3D:
	if _steam_mesh == null:
		_steam_mesh = SphereMesh.new()
		_steam_mesh.radius = 1.0
		_steam_mesh.height = 2.0
		_steam_mesh.radial_segments = 8
		_steam_mesh.rings = 4
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE
		mat.no_depth_test = false
		_steam_mesh.material = mat
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.4
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = 0.7
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, 0.5, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(radius, 0.05)
	p.mesh = _steam_mesh
	p.scale_amount_min = size * 0.8
	p.scale_amount_max = size * 1.3
	p.scale_amount_curve = _grow()
	p.color_ramp = _fade(Color(STEAM_COLOR.r, STEAM_COLOR.g, STEAM_COLOR.b, 0.9))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


## The crash: a droopy grey puff that sinks, and "z z Z" that drift up from the head. `height` is where the head is
## (local to `parent`). The labels are children of `parent` and free themselves.
static func crash(parent: Node3D, height: float) -> void:
	var puff := steam(0.3, 0.26, 8)
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.lifetime = 1.1
	puff.direction = Vector3.DOWN
	puff.spread = 70.0
	puff.initial_velocity_min = 0.3
	puff.initial_velocity_max = 0.9
	puff.gravity = Vector3(0, -1.2, 0)
	puff.color_ramp = _fade(Color(0.55, 0.57, 0.62, 0.75))
	puff.position = Vector3(0, height * 0.95, 0)
	parent.add_child(puff)
	puff.emitting = true
	parent.get_tree().create_timer(2.0).timeout.connect(puff.queue_free)
	for i in 3:
		var l := Label3D.new()
		l.text = "z" if i < 2 else "Z"
		l.modulate = Color(ZZZ.r, ZZZ.g, ZZZ.b, 0.0)
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.outline_size = 10
		l.font_size = 52 + i * 14
		l.pixel_size = 0.012
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 20
		var x := 0.25 + 0.2 * float(i) + GameWorld.fx_rng.randf_range(-0.05, 0.05)
		l.position = Vector3(x * 0.4, height + 0.25, 0)
		parent.add_child(l)
		var tw := l.create_tween()
		tw.set_parallel(true)
		tw.tween_property(l, "position", Vector3(x, height + 1.3 + 0.2 * float(i), 0), 1.5).set_delay(0.35 * float(i)).set_ease(Tween.EASE_OUT)
		tw.tween_property(l, "modulate:a", 1.0, 0.25).set_delay(0.35 * float(i))
		tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.35 * float(i) + 1.0)
		tw.chain().tween_callback(l.queue_free)


# --- Pieces ---------------------------------------------------------------------------------------

static func _ring(parent: Node3D, radius: float, color: Color, time: float, tube: float) -> void:
	var t := TorusMesh.new()
	t.inner_radius = radius - tube
	t.outer_radius = radius + tube
	t.rings = 40
	t.ring_segments = 6
	var mat := Fx.glow_material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	mi.position = Vector3(0, 0.1, 0)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, time * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, time * 0.5).set_delay(time * 0.5)


static func _disc(parent: Node3D, radius: float, color: Color, time: float) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	cyl.radial_segments = 36
	cyl.rings = 1
	var mat := Fx.glow_material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_flash", true)
	mi.position = Vector3(0, 0.07, 0)
	parent.add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)


static func _grow() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 0.45))
	c.add_point(Vector2(0.6, 1.0))
	c.add_point(Vector2(1, 1.35))
	return c


## Transparent -> `peak` -> transparent over a particle's life.
static func _fade(peak: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.65, 1.0])
	g.colors = PackedColorArray([Color(peak.r, peak.g, peak.b, 0.0), peak, Color(peak.r, peak.g, peak.b, peak.a * 0.55), Color(peak.r, peak.g, peak.b, 0.0)])
	return g

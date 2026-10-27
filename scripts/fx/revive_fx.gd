class_name ReviveFx
extends RefCounted
## The look of getting back up (cosmetic only: nothing here decides play, and it rolls nothing itself: the particles'
## own scatter is the engine's). Docs: docs/design/spells.md, "Revive" and "Coffee".
##
##   ReviveFx.cast(pos, radius)          # EVERY Revive cast, hit or miss: aloe-green leaves burst up and tumble down,
##                                       # pale motes rise, and two hex rings rise off the floor at the radius
##   ReviveFx.stand_up(hero, top, gray)  # a hero stands back up (Revive or a coffee zombie), on every screen: a puff of
##                                       # leaves (gray-green and coffee-brown for a zombie) and the hop's cue
##   ReviveFx.cured(hero, top)           # a zombie's curse lifts (healed past three quarters, or a Revive): a green sparkle
##
## Built from the shared helpers (Fx.ring, Fx.burst) plus one CPUParticles3D of flat leaf blades.

const ALOE := Color(0.42, 0.78, 0.38)
const ALOE_LIGHT := Color(0.72, 0.95, 0.55)
const ALOE_DARK := Color(0.20, 0.48, 0.26)
const MOTE := Color(0.88, 1.0, 0.78)
const ZOMBIE_GRAY := Color(0.55, 0.58, 0.52)
const COFFEE := Color(0.48, 0.30, 0.16)
const STAND_CUE := "jump"          ## the +1 hop's cue (an existing one: Revive has no sound of its own)

static var _leaf_mesh: Mesh = null


## The Revive cast at `pos` (the radius it was cast with).
static func cast(pos: Vector3, radius: float) -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	var col := SpellBook.color_of("revive")
	Fx.ring(pos, radius, Color(col.r, col.g, col.b, 0.85), 0.8, 1.6, true, 0.2)
	var tree := GameWorld.root.get_tree()
	tree.create_timer(0.16).timeout.connect(func() -> void:
		Fx.ring(pos, radius * 0.7, Color(ALOE_LIGHT.r, ALOE_LIGHT.g, ALOE_LIGHT.b, 0.7), 0.7, 1.4, true, 0.2))
	var greens: Array[Color] = [ALOE, ALOE_LIGHT, ALOE_DARK]
	leaves(pos + Vector3.UP * 0.25, greens, 22, radius)
	var motes: Array[Color] = [MOTE, col]
	Fx.burst(pos + Vector3.UP * 0.2, motes, 18, 1.2, 0.06, 1.3, -1.6, Vector3.UP, 40.0)


## A hero who stood back up (`top` the height of its head): a puff of leaves round the body and the hop's cue.
static func stand_up(hero: Node3D, top: float, gray: bool) -> void:
	if hero == null or not hero.is_inside_tree():
		return
	Sfx.play_at(STAND_CUE, hero.global_position)
	var cols: Array[Color] = [ALOE, ALOE_LIGHT, ALOE_DARK]
	var motes: Array[Color] = [MOTE, ALOE_LIGHT]
	if gray:
		cols = [ZOMBIE_GRAY, COFFEE, ALOE_DARK]
		motes = [ZOMBIE_GRAY, COFFEE]
	leaves(hero.global_position + Vector3.UP * top * 0.4, cols, 12, 0.6)
	Fx.burst(hero.global_position + Vector3.UP * 0.3, motes, 10, 1.0, 0.05, 1.0, -1.2, Vector3.UP, 30.0)


## A zombie's curse lifts: a green sparkle off the head.
static func cured(hero: Node3D, top: float) -> void:
	if hero == null or not hero.is_inside_tree():
		return
	var sparkle: Array[Color] = [MOTE, ALOE_LIGHT, ALOE]
	Fx.burst(hero.global_position + Vector3.UP * top * 0.8, sparkle, 14, 1.6, 0.06, 0.9, -0.8, Vector3.UP, 70.0)


## Flat leaf blades flung up and out from `pos`, tumbling as they fall back (`spread`: how wide the emitter is).
static func leaves(pos: Vector3, colors: Array[Color], amount: int, spread: float) -> CPUParticles3D:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return null
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(spread * 0.35, 0.1)
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.2
	p.gravity = Vector3(0, -7.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.5
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.particle_flag_rotate_y = true
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / maxf(1.0, colors.size() - 1.0))
		cols.append(colors[i])
	grad.offsets = offsets
	grad.colors = cols
	p.color_initial_ramp = grad
	p.mesh = _leaf()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	GameWorld.spawn(p, pos)
	p.emitting = true
	Fx._free_later(p, p.lifetime + 0.4)
	return p


## One leaf blade: a flat, pointed diamond (shared by every burst).
static func _leaf() -> Mesh:
	if _leaf_mesh != null:
		return _leaf_mesh
	var m := PrismMesh.new()
	m.size = Vector3(0.12, 0.26, 0.02)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material = mat
	_leaf_mesh = m
	return m

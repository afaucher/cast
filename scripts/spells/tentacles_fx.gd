class_name TentaclesFx
extends Node3D
## The look of the Tentacles spell. A purple telegraph ring and glowing floor cracks, then
## COUNT neon-purple faceted tentacles sprout from the cracks in a ring, whip outward (in sync
## with the shove), wiggle, and retract into the floor over about a second.
##
## Each tentacle is a tapered chain of SEGMENTS faceted LowPoly segments (hexagonal frusta)
## hung from joint nodes; bending the joints poses the chain. Everything is driven from
## GameWorld.time (the same clock as the spell), so it stays in step with the shove and needs
## no GPU-only features: it builds and animates headless (CPU particles only).
##
## Timeline (seconds from the cast):  0 .. telegraph   ring + cracks, tips peek out
##   telegraph + 0.0 .. 0.3   sprout and whip outward    + 0.3 .. 0.95   wiggle
##   telegraph + 0.95 .. 1.95 straighten and retract into the ground

const COUNT := 8
const SEGMENTS := 10
const SPROUT := 0.3
const WHIP := 0.42
const RETRACT_AT := 0.95
const RETRACT := 1.0
const LIFETIME := RETRACT_AT + RETRACT + 0.05

const NEON := Color(0.75, 0.2, 1.0)
const BASE_COL := Color(0.42, 0.07, 0.72)
const TIP_COL := Color(0.98, 0.42, 1.0)
const OUTLINE_COL := Color(0.09, 0.0, 0.16)

var radius := 3.0            ## the shove radius: tentacles reach about this far
var telegraph := 0.25
var power := 1.0

var _t0 := 0.0
var _burst_done := false
var _ground_y := 0.0
var _tentacles: Array[Dictionary] = []     ## {base, joints: Array[Node3D], phase, yaw, ok}
var _disc: MeshInstance3D
var _ring: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _crack_mat: StandardMaterial3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _length := 3.0


func _ready() -> void:
	_t0 = GameWorld.time
	_ground_y = global_position.y
	_length = clampf(radius * 1.4, 2.4, 5.0)
	_mat = LowPolyMaterial.make_glow(NEON, 0.55, 2.2, OUTLINE_COL)
	_build_telegraph()
	_build_tentacles()
	set_process(true)


func _process(_delta: float) -> void:
	var t := GameWorld.time - _t0
	if t < telegraph:
		_pose_telegraph(t)
		return
	if not _burst_done:
		_burst_done = true
		_on_burst()
	_pose_tentacles(t - telegraph)


# --- Build -------------------------------------------------------------------------------------

func _build_telegraph() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 32
	_disc_mat = Fx.glow_material(Color(NEON.r, NEON.g, NEON.b, 0.15))
	_disc = MeshInstance3D.new()
	_disc.mesh = disc
	_disc.material_override = _disc_mat
	_disc.position.y = 0.1
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	var tor := TorusMesh.new()
	tor.inner_radius = radius - 0.07
	tor.outer_radius = radius + 0.07
	tor.rings = 48
	tor.ring_segments = 6
	_ring_mat = Fx.glow_material(Color(NEON.r, NEON.g, NEON.b, 0.9))
	_ring = MeshInstance3D.new()
	_ring.mesh = tor
	_ring.material_override = _ring_mat
	_ring.position.y = 0.12
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_disc.scale = Vector3(0.15, 1.0, 0.15)
	_ring.scale = Vector3(0.15, 1.0, 0.15)
	_crack_mat = Fx.glow_material(Color(0.9, 0.35, 1.0, 0.0))


func _build_tentacles() -> void:
	# One mesh per chain index, shared by every tentacle.
	var meshes: Array[Mesh] = []
	var seg_len := _length / SEGMENTS
	var r_base := 0.30 + 0.1 * minf(radius / 3.0, 1.2)
	var r_tip := 0.075
	for i in SEGMENTS:
		var f0 := float(i) / SEGMENTS
		var f1 := float(i + 1) / SEGMENTS
		var col := BASE_COL.lerp(TIP_COL, f0 * f0 * 0.7 + f0 * 0.3)
		var soup := LowPoly.cylinder(lerpf(r_base, r_tip, pow(f0, 0.85)) , lerpf(r_base, r_tip, pow(f1, 0.85)),
				seg_len * 1.04, 6, col, 31 + i, 0.06, 1, 0.1)
		meshes.append(soup.to_mesh())
	var r0 := 0.8 + 0.1 * power
	for k in COUNT:
		var ang := TAU * float(k) / COUNT + 0.3 * sin(float(k) * 2.7)
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var base := Node3D.new()
		base.name = "Tentacle%d" % k
		base.rotation.y = atan2(dir.x, dir.z)
		var pos := dir * (r0 + 0.12 * sin(float(k) * 1.9))
		var gy := _ground_y
		var map: HexMap = GameWorld.map
		var ok := true
		if map != null:
			var g := map.ground_height(global_position + pos)
			if is_nan(g):
				ok = false
			else:
				gy = g
		pos.y = gy - _ground_y
		base.position = pos
		base.visible = false
		add_child(base)
		var joints: Array[Node3D] = []
		var parent: Node3D = base
		for i in SEGMENTS:
			var j := Node3D.new()
			if i > 0:
				j.position = Vector3(0, seg_len, 0)
			parent.add_child(j)
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[i]
			mi.material_override = _mat
			mi.position = Vector3(0, seg_len * 0.5, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			j.add_child(mi)
			joints.append(j)
			parent = j
		# A glowing crack in the floor under each tentacle: a short zigzag of thin bars.
		_add_crack(pos + Vector3(0, 0.07, 0), dir, k)
		_tentacles.append({"base": base, "joints": joints, "phase": float(k) * 1.3, "ok": ok, "pos": pos})
	_light = OmniLight3D.new()
	_light.light_color = NEON
	_light.light_energy = 0.0
	_light.omni_range = radius * 2.5
	_light.position = Vector3(0, 1.0, 0)
	_light.shadow_enabled = false
	add_child(_light)


func _add_crack(at: Vector3, dir: Vector3, k: int) -> void:
	var side := Vector3(-dir.z, 0, dir.x)
	var p := at - dir * 0.55
	for s in 3:
		var seg := dir * 0.42 + side * (0.2 if (s + k) % 2 == 0 else -0.2)
		var bar := BoxMesh.new()
		bar.size = Vector3(0.07, 0.02, seg.length())
		var mi := MeshInstance3D.new()
		mi.mesh = bar
		mi.material_override = _crack_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = p + seg * 0.5
		mi.rotation.y = atan2(seg.x, seg.z)
		add_child(mi)
		p += seg


# --- Animation ---------------------------------------------------------------------------------

func _pose_telegraph(t: float) -> void:
	var k := clampf(t / telegraph, 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - k, 3.0)
	_disc.scale = Vector3(lerpf(0.15, 1.0, grow), 1.0, lerpf(0.15, 1.0, grow))
	_ring.scale = _disc.scale
	var flicker := 0.5 + 0.5 * sin(t * 50.0)
	_disc_mat.albedo_color.a = 0.1 + 0.25 * k
	_ring_mat.albedo_color.a = 0.5 + 0.5 * flicker
	_crack_mat.albedo_color.a = 0.9 * k
	# The tips just break the floor.
	for tc in _tentacles:
		_apply_pose(tc, 0.0, 0.0, 0.0, 0.08 * k, 0.0)


func _on_burst() -> void:
	_disc_mat.albedo_color.a = 0.3
	_ring_mat.albedo_color.a = 0.9
	_light.light_energy = 3.5
	var hot: Array[Color] = [Color(1.0, 0.7, 1.0), NEON, Color(0.45, 0.1, 0.9)]
	for tc in _tentacles:
		if not bool(tc["ok"]):
			continue
		var at: Vector3 = global_position + (tc["pos"] as Vector3)
		Fx.burst(at + Vector3.UP * 0.1, hot, 10, 3.2, 0.07, 0.6, 5.0, Vector3.UP, 55.0)
	var dust: Array[Color] = [Color(0.55, 0.35, 0.65), Color(0.35, 0.25, 0.4)]
	Fx.burst(global_position + Vector3.UP * 0.2, dust, 18, radius * 1.4, 0.16, 0.8, 1.0, Vector3.UP, 85.0, false)
	Fx.ring(global_position, radius, Color(NEON.r, NEON.g, NEON.b, 0.9), 0.5, 0.0, true, 0.3)
	Fx.shake(0.2 + 0.1 * power)


func _pose_tentacles(tb: float) -> void:
	var retract := clampf((tb - RETRACT_AT) / RETRACT, 0.0, 1.0)
	var sprout := clampf(tb / SPROUT, 0.0, 1.0)
	var ext := _ease_out_back(sprout)
	ext = minf(ext, 1.08) * (1.0 - retract * retract)
	var whip := 1.0 - pow(1.0 - clampf(tb / WHIP, 0.0, 1.0), 3.0)
	var lean := lerpf(0.15, 1.5, whip) * (1.0 - 0.85 * retract)
	var wig := 0.55 * smoothstep(0.3, 0.55, tb) * (1.0 - retract)
	for tc in _tentacles:
		_apply_pose(tc, lean, wig, tb, ext, retract)
	# Floor glow follows the tentacles out and fades with them.
	var fade := 1.0 - clampf((tb - RETRACT_AT) / (RETRACT * 0.9), 0.0, 1.0)
	_ring_mat.albedo_color.a = 0.9 * fade
	_disc_mat.albedo_color.a = 0.3 * fade
	_crack_mat.albedo_color.a = 0.9 * fade
	_light.light_energy = 3.5 * fade * (0.8 + 0.2 * sin(tb * 30.0))
	_mat.set_shader_parameter("glow_strength", 0.55 + 0.25 * sin(tb * 14.0) )
	if tb > LIFETIME:
		visible = false


func _apply_pose(tc: Dictionary, lean: float, wig: float, tb: float, ext: float, _retract: float) -> void:
	var base: Node3D = tc["base"]
	if not bool(tc["ok"]) or ext <= 0.001:
		base.visible = false
		return
	base.visible = true
	# Sink under the floor by the missing extension (the terrain hides what is below it).
	var pos: Vector3 = tc["pos"]
	base.position.y = pos.y - (1.0 - minf(ext, 1.0)) * (_length * 0.95 + 0.2)
	var joints: Array = tc["joints"]
	var n := joints.size()
	var wsum := 0.0
	for i in n:
		wsum += pow(float(i + 1), 1.4)
	var phase: float = tc["phase"]
	for i in n:
		var w := pow(float(i + 1), 1.4) / wsum
		var f := float(i) / float(n)
		var bend := lean * (0.35 * (1.0 / n) + 0.65 * w)
		bend += wig * sin(TAU * 1.5 * tb - float(i) * 0.85 + phase) * (0.25 + f) * 0.5
		var j: Node3D = joints[i]
		j.rotation.x = bend
		j.rotation.z = wig * 0.5 * cos(TAU * 1.5 * tb - float(i) * 0.85 + phase) * f


static func _ease_out_back(u: float) -> float:
	var c1 := 1.4
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0)

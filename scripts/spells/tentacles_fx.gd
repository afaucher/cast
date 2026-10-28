class_name TentaclesFx
extends Node3D
## The look of the Tentacles spell. A purple telegraph oval and glowing floor cracks, then neon-purple faceted tentacles
## sprout from the cracks, spread over the spell's sideways oval, whip outward (in sync with the burst's shove), stay up
## waving while the spell lasts, LASH out at every swat, and retract into the floor at the end. A faint neon rim marks the
## oval's edge the whole time. The node turns so its local +Z is the caster's aim (the oval's depth axis) and local X runs
## across it (the width axis).
##
## Each tentacle is a tapered chain of SEGMENTS faceted LowPoly segments (hexagonal frusta) hung from joint nodes; bending
## the joints poses the chain. Each one leans toward the oval's nearest edge, the way the swats push. Everything is driven
## from GameWorld.time from the cast's moment (`start_time`, the spell's), so it stays in step with the shoves on every
## machine and needs no GPU-only features: it builds and animates headless (CPU particles only). Cosmetic: the jitter of
## the tentacles uses GameWorld.fx_rng and nothing here decides play.
##
## Timeline (seconds from the cast):  0 .. telegraph   oval + cracks, tips peek out
##   telegraph + 0.0 .. SPROUT     sprout and whip outward          + SETTLE   ease back to a waving stance
##   telegraph + k x swat_every    a lash outward at each swat       + up .. up + RETRACT   straighten and sink away

const SEGMENTS := 10
const SPROUT := 0.3
const WHIP := 0.42
const SETTLE := 0.9            ## by now the burst's whip has eased back to the waving stance
const RETRACT := 0.8
const LASH := 0.35             ## a swat's lash: out at the tick, back over this long
const WIND := 0.18             ## ... drawn back this long before it
## Tentacles per unit of oval area (today's ring: 8 over a radius-3 circle), and the bounds.
const PER_AREA := 8.0 / (PI * 9.0)
const COUNT_MIN := 6
const COUNT_MAX := 18
const RIM_THICK := 0.13

const NEON := Color(0.75, 0.2, 1.0)
const BASE_COL := Color(0.42, 0.07, 0.72)
const TIP_COL := Color(0.98, 0.42, 1.0)
const OUTLINE_COL := Color(0.09, 0.0, 0.16)

var depth := 3.0             ## the oval's half-axis along the aim
var width := 6.0             ## ... and across it
var aim := Vector3.FORWARD   ## the caster's line of aim (flat)
var telegraph := 0.25
var up := 6.0                ## seconds the tentacles stay up after the burst
var swat_every := 0.6
var power := 1.0
var start_time := -1.0       ## the cast's moment (GameWorld.time); -1 = now

var _burst_done := false
var _lashes := 0
var _ground_y := 0.0
var _tentacles: Array[Dictionary] = []     ## {base, joints: Array[Node3D], phase, ok, pos}
var _disc: MeshInstance3D
var _ring: MeshInstance3D
var _disc_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _crack_mat: StandardMaterial3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _length := 3.0


## Seconds from the cast until the tentacles are gone.
func lifetime() -> float:
	return telegraph + up + RETRACT


func _ready() -> void:
	if start_time < 0.0:
		start_time = GameWorld.time
	aim.y = 0.0
	if aim.length() < 0.001:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	rotation.y = atan2(aim.x, aim.z)   # local +Z along the aim, local X across it
	_ground_y = global_position.y
	_length = clampf(depth * 1.05, 2.2, 3.4)
	_mat = LowPolyMaterial.make_glow(NEON, 0.55, 2.2, OUTLINE_COL)
	_build_telegraph()
	_build_tentacles()
	set_process(true)


func _process(_delta: float) -> void:
	var t := GameWorld.time - start_time
	if t < telegraph:
		_pose_telegraph(t)
		return
	if not _burst_done:
		_burst_done = true
		_on_burst()
	_pose_tentacles(t - telegraph)


## A flat ribbon along the ellipse x^2/w^2 + z^2/d^2 = 1 (local X across, Z along), `thick` wide, at y = 0. The aim reticle
## draws the same rim.
static func oval_rim(w: float, d: float, thick: float, segments: int = 64) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var pts_in: Array[Vector3] = []
	var pts_out: Array[Vector3] = []
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var p := Vector3(w * cos(a), 0.0, d * sin(a))
		var n := Vector3(cos(a) / w, 0.0, sin(a) / d).normalized()   # (the ellipse's outward normal there)
		pts_in.append(p - n * thick * 0.5)
		pts_out.append(p + n * thick * 0.5)
	for i in segments:
		for v: Vector3 in [pts_in[i], pts_out[i], pts_out[i + 1], pts_in[i], pts_out[i + 1], pts_in[i + 1]]:
			st.add_vertex(v)
	return st.commit()


# --- Build -------------------------------------------------------------------------------------

func _build_telegraph() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 40
	_disc_mat = Fx.glow_material(Color(NEON.r, NEON.g, NEON.b, 0.15))
	_disc = MeshInstance3D.new()
	_disc.mesh = disc
	_disc.material_override = _disc_mat
	_disc.position.y = 0.1
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)
	_ring_mat = Fx.glow_material(Color(NEON.r, NEON.g, NEON.b, 0.9))
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring = MeshInstance3D.new()
	_ring.name = "Rim"
	_ring.mesh = oval_rim(width, depth, RIM_THICK)
	_ring.material_override = _ring_mat
	_ring.position.y = 0.12
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_scale_oval(0.15)
	_crack_mat = Fx.glow_material(Color(0.9, 0.35, 1.0, 0.0))


func _scale_oval(k: float) -> void:
	_disc.scale = Vector3(width * k, 1.0, depth * k)
	_ring.scale = Vector3(k, 1.0, k)


## How many tentacles: about today's density over the oval's area.
func count() -> int:
	return clampi(roundi(PER_AREA * PI * width * depth), COUNT_MIN, COUNT_MAX)


func _build_tentacles() -> void:
	# One mesh per chain index, shared by every tentacle.
	var meshes: Array[Mesh] = []
	var seg_len := _length / SEGMENTS
	var r_base := 0.30 + 0.1 * minf(depth / 3.0, 1.2)
	var r_tip := 0.075
	for i in SEGMENTS:
		var f0 := float(i) / SEGMENTS
		var f1 := float(i + 1) / SEGMENTS
		var col := BASE_COL.lerp(TIP_COL, f0 * f0 * 0.7 + f0 * 0.3)
		var soup := LowPoly.cylinder(lerpf(r_base, r_tip, pow(f0, 0.85)) , lerpf(r_base, r_tip, pow(f1, 0.85)),
				seg_len * 1.04, 6, col, 31 + i, 0.06, 1, 0.1)
		meshes.append(soup.to_mesh())
	var rng: RandomNumberGenerator = GameWorld.fx_rng
	var n := count()
	var spin := rng.randf() * TAU
	for k in n:
		# A sunflower spread over the oval (inside 75% of it), each base leaning toward the oval's nearest edge.
		var r := 0.75 * sqrt((float(k) + 0.5) / float(n))
		var ang := spin + float(k) * 2.39996 + rng.randf_range(-0.2, 0.2)
		var pos := Vector3(r * cos(ang) * width, 0.0, r * sin(ang) * depth)
		var dir := Vector3(pos.x / (width * width), 0.0, pos.z / (depth * depth))
		if dir.length() < 0.0001:
			dir = Vector3(0.0, 0.0, 1.0)
		dir = dir.normalized()
		var base := Node3D.new()
		base.name = "Tentacle%d" % k
		base.rotation.y = atan2(dir.x, dir.z)
		var gy := _ground_y
		var map: HexMap = GameWorld.map
		var ok := true
		if map != null:
			var g := map.ground_height(to_global(pos))
			if is_nan(g) or not Tentacles.reaches(map, global_position, to_global(pos)):
				ok = false   # (walls, void and the far side of a wall grow none)
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
		_tentacles.append({"base": base, "joints": joints, "phase": rng.randf() * TAU, "ok": ok, "pos": pos,
			"lag": rng.randf_range(0.0, 0.06)})
	_light = OmniLight3D.new()
	_light.light_color = NEON
	_light.light_energy = 0.0
	_light.omni_range = width * 1.8
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
	_scale_oval(lerpf(0.15, 1.0, grow))
	var flicker := 0.5 + 0.5 * sin(t * 50.0)
	_disc_mat.albedo_color.a = 0.1 + 0.25 * k
	_ring_mat.albedo_color.a = 0.5 + 0.5 * flicker
	_crack_mat.albedo_color.a = 0.9 * k
	# The tips just break the floor.
	for tc in _tentacles:
		_apply_pose(tc, 0.0, 0.0, 0.0, 0.08 * k)


func _on_burst() -> void:
	_scale_oval(1.0)
	_disc_mat.albedo_color.a = 0.3
	_ring_mat.albedo_color.a = 0.9
	_light.light_energy = 3.5
	var hot: Array[Color] = [Color(1.0, 0.7, 1.0), NEON, Color(0.45, 0.1, 0.9)]
	for tc in _tentacles:
		if not bool(tc["ok"]):
			continue
		var at := to_global(tc["pos"] as Vector3)
		Fx.burst(at + Vector3.UP * 0.1, hot, 8, 3.2, 0.07, 0.6, 5.0, Vector3.UP, 55.0)
	var dust: Array[Color] = [Color(0.55, 0.35, 0.65), Color(0.35, 0.25, 0.4)]
	Fx.burst(global_position + Vector3.UP * 0.2, dust, 22, width * 1.2, 0.16, 0.8, 1.0, Vector3.UP, 85.0, false)
	Fx.shake(0.2 + 0.1 * power)


## The swat that came last (k >= 1) and the seconds since it, or [0, tb] before the first.
func _last_swat(tb: float) -> Array:
	var k := mini(floori(tb / swat_every), _swat_count())
	return [k, tb - float(k) * swat_every]


func _swat_count() -> int:
	return floori((up - 0.001) / swat_every)


func _pose_tentacles(tb: float) -> void:
	var retract := clampf((tb - up) / RETRACT, 0.0, 1.0)
	var sprout := clampf(tb / SPROUT, 0.0, 1.0)
	var ext := _ease_out_back(sprout)
	ext = minf(ext, 1.08) * (1.0 - retract * retract)
	var whip := 1.0 - pow(1.0 - clampf(tb / WHIP, 0.0, 1.0), 3.0)
	var stance := lerpf(lerpf(0.15, 1.5, whip), 0.6, smoothstep(WHIP, SETTLE, tb))
	var wig := 0.55 * smoothstep(0.3, 0.55, tb) * (1.0 - retract)
	# The swats: wound back just before each tick, lashed out at it.
	var last := _last_swat(tb)
	var k: int = last[0]
	var since: float = last[1]
	var lash := 0.0
	if k >= 1 and since < LASH:
		lash = 1.0 * pow(1.0 - since / LASH, 2.0)
	var to_next := float(k + 1) * swat_every - tb
	if k + 1 <= _swat_count() and to_next < WIND and to_next >= 0.0:
		lash -= 0.45 * (1.0 - to_next / WIND)
	if k > _lashes:
		_lashes = k
		_on_lash()
	for tc in _tentacles:
		var l := lash
		if k >= 1 and since < float(tc["lag"]):
			l *= 0.6   # (a few lag a hair behind the rest)
		_apply_pose(tc, (stance + l) * (1.0 - 0.85 * retract), wig, tb, ext)
	# The rim stays faintly lit while they are up and flares on each swat; it all fades with the retract.
	var fade := 1.0 - clampf((tb - up) / (RETRACT * 0.9), 0.0, 1.0)
	var burst_glow := 1.0 - smoothstep(0.0, SETTLE, tb)
	var flare := maxf(lash, 0.0)
	_ring_mat.albedo_color.a = (0.4 + 0.5 * maxf(burst_glow, flare)) * fade
	_disc_mat.albedo_color.a = (0.1 + 0.2 * burst_glow + 0.08 * flare) * fade
	_crack_mat.albedo_color.a = (0.55 + 0.35 * burst_glow) * fade
	_light.light_energy = (1.6 + 1.9 * maxf(burst_glow, flare)) * fade * (0.8 + 0.2 * sin(tb * 30.0))
	_mat.set_shader_parameter("glow_strength", 0.55 + 0.25 * sin(tb * 14.0) + 0.3 * flare)
	if tb > up + RETRACT:
		visible = false


## A swat landed (cosmetic): a puff at a few tentacle tips' feet.
func _on_lash() -> void:
	var puff: Array[Color] = [Color(0.95, 0.6, 1.0), NEON]
	var i := 0
	for tc in _tentacles:
		i += 1
		if i % 3 != (_lashes % 3) or not bool(tc["ok"]):
			continue
		var at := to_global(tc["pos"] as Vector3)
		Fx.burst(at + Vector3.UP * 0.15, puff, 4, 2.2, 0.06, 0.4, 4.0, Vector3.UP, 70.0)


func _apply_pose(tc: Dictionary, lean: float, wig: float, tb: float, ext: float) -> void:
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

class_name VinesFx
extends Node3D
## The look of the Vines spell: a green telegraph ring, then COUNT thorny vines sprout from the floor across the
## area, sway while the roots hold and sink back when they let go. A variant of the tentacles kit (TentaclesFx):
## the same joint-chain posing, but short, green, curled at the tips and studded with thorns, and they STAY up for
## the whole root time instead of whipping out and back.
##
## Driven from GameWorld.time (`start_time` is the cast's stamp), so it stays in step with the root and needs no
## GPU-only features: it builds and animates headless (CPU particles only). Cosmetic: nothing here decides play.
##
## Timeline (seconds from the cast):  0 .. telegraph   ring + leaf-green disc, tips peek out
##   telegraph + 0 .. SPROUT   burst up      + SPROUT .. hold   sway      + hold .. hold + RETRACT   sink away

const COUNT := 11
const SEGMENTS := 8
const SPROUT := 0.28
const RETRACT := 0.5
const LENGTH := 1.9

const LEAF := Color(0.45, 0.78, 0.22)
const BASE_COL := Color(0.13, 0.38, 0.10)
const TIP_COL := Color(0.52, 0.88, 0.24)
const THORN_COL := Color(0.93, 0.82, 0.5)
const OUTLINE_COL := Color(0.02, 0.09, 0.02)

var radius := 3.0
var telegraph := 0.3
var hold := 2.0                ## seconds the vines stay up after the burst (the root time)
var power := 1.0
var start_time := 0.0

var _burst_done := false
var _ground_y := 0.0
var _vines: Array[Dictionary] = []     ## {base, joints: Array[Node3D], phase, ok, pos}
var _disc: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _disc_mat: StandardMaterial3D = null
var _ring_mat: StandardMaterial3D = null
var _mat: ShaderMaterial = null


## Who may write each var (see Net). Presentation only.
func net_fields() -> Dictionary:
	return {
		"radius": Net.LOCAL, "telegraph": Net.LOCAL, "hold": Net.LOCAL, "power": Net.LOCAL, "start_time": Net.LOCAL,
		"_burst_done": Net.LOCAL, "_ground_y": Net.LOCAL, "_vines": Net.LOCAL, "_disc": Net.LOCAL,
		"_ring": Net.LOCAL, "_disc_mat": Net.LOCAL, "_ring_mat": Net.LOCAL, "_mat": Net.LOCAL,
	}


func _ready() -> void:
	_ground_y = global_position.y
	_mat = LowPolyMaterial.make_glow(LEAF, 0.18, 2.2, OUTLINE_COL)
	_build_telegraph()
	_build_vines()


func _process(_delta: float) -> void:
	var t := GameWorld.time - start_time
	if t < telegraph:
		_pose_telegraph(t)
		return
	if not _burst_done:
		_burst_done = true
		_on_burst()
	_pose_vines(t - telegraph)


# --- Build -------------------------------------------------------------------------------------

func _build_telegraph() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 32
	_disc_mat = Fx.glow_material(Color(LEAF.r, LEAF.g, LEAF.b, 0.12))
	_disc = MeshInstance3D.new()
	_disc.mesh = disc
	_disc.material_override = _disc_mat
	_disc.position.y = 0.1
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc.scale = Vector3(0.15, 1.0, 0.15)
	add_child(_disc)
	var tor := TorusMesh.new()
	tor.inner_radius = radius - 0.06
	tor.outer_radius = radius + 0.06
	tor.rings = 48
	tor.ring_segments = 6
	_ring_mat = Fx.glow_material(Color(LEAF.r, LEAF.g, LEAF.b, 0.85))
	_ring = MeshInstance3D.new()
	_ring.mesh = tor
	_ring.material_override = _ring_mat
	_ring.position.y = 0.12
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(0.15, 1.0, 0.15)
	add_child(_ring)


func _build_vines() -> void:
	# One mesh per chain index, shared by every vine: a tapered segment with a pair of thorns on every other one.
	var meshes: Array[Mesh] = []
	var seg_len := LENGTH / SEGMENTS
	var r_base := 0.17
	var r_tip := 0.035
	for i in SEGMENTS:
		var f0 := float(i) / SEGMENTS
		var f1 := float(i + 1) / SEGMENTS
		var soup := LowPoly.cylinder(lerpf(r_base, r_tip, f0), lerpf(r_base, r_tip, f1), seg_len * 1.06, 5,
				BASE_COL.lerp(TIP_COL, f0), 71 + i, 0.02, 1, 0.09)
		if i % 2 == 1 and i < SEGMENTS - 1:
			for side in 2:
				var a := PI * float(side) + float(i)
				var rr := lerpf(r_base, r_tip, (f0 + f1) * 0.5) * 1.05
				var thorn := LowPoly.cylinder(0.06, 0.0, 0.22, 4, THORN_COL, 90 + i * 2 + side, 0.0, 1, 0.05)
				# The thorn cone stands along +Y: lay it over so its point faces away from the vine.
				soup.merge(thorn, LowPoly.at(Vector3(cos(a) * rr, 0.0, sin(a) * rr), Vector3(0.0, -rad_to_deg(a), -90.0)))
		meshes.append(soup.to_mesh())
	for k in COUNT:
		# Deterministic spread (a golden-angle spiral), so every machine draws the same patch.
		var u := (float(k) + 0.5) / COUNT
		var ang := float(k) * 2.39996
		var dist := radius * lerpf(0.22, 0.9, sqrt(u))
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var base := Node3D.new()
		base.name = "Vine%d" % k
		base.rotation.y = ang
		var gy := _ground_y
		var ok := true
		var map: HexMap = GameWorld.map
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
			mi.set_meta("no_flash", true)
			j.add_child(mi)
			joints.append(j)
			parent = j
		_vines.append({"base": base, "joints": joints, "phase": float(k) * 1.7, "ok": ok, "pos": pos,
			"scale": 0.75 + 0.5 * fposmod(float(k) * 0.618, 1.0)})


# --- Animation ---------------------------------------------------------------------------------

func _pose_telegraph(t: float) -> void:
	var k := clampf(t / maxf(telegraph, 0.01), 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - k, 3.0)
	_disc.scale = Vector3(lerpf(0.15, 1.0, grow), 1.0, lerpf(0.15, 1.0, grow))
	_ring.scale = _disc.scale
	_disc_mat.albedo_color.a = 0.08 + 0.2 * k
	_ring_mat.albedo_color.a = 0.4 + 0.5 * (0.5 + 0.5 * sin(t * 40.0))
	for v in _vines:
		_apply_pose(v, 0.0, 0.0, 0.06 * k)


func _on_burst() -> void:
	_ring_mat.albedo_color.a = 0.8
	var leaves: Array[Color] = [Color(0.7, 0.95, 0.35), LEAF, Color(0.25, 0.55, 0.15)]
	for v in _vines:
		if not bool(v["ok"]):
			continue
		var at: Vector3 = global_position + (v["pos"] as Vector3)
		Fx.burst(at + Vector3.UP * 0.1, leaves, 5, 2.6, 0.06, 0.55, 5.0, Vector3.UP, 50.0)
	var dust: Array[Color] = [Color(0.4, 0.34, 0.24), Color(0.3, 0.26, 0.2)]
	Fx.burst(global_position + Vector3.UP * 0.2, dust, 14, radius * 1.2, 0.14, 0.7, 1.0, Vector3.UP, 85.0, false)
	Fx.ring(global_position, radius, Color(LEAF.r, LEAF.g, LEAF.b, 0.85), 0.45, 0.0, true, 0.3)
	Fx.shake(0.1 + 0.05 * power)


func _pose_vines(tb: float) -> void:
	var retract := clampf((tb - hold) / RETRACT, 0.0, 1.0)
	var sprout := clampf(tb / SPROUT, 0.0, 1.0)
	var ext := _ease_out_back(sprout)
	ext = minf(ext, 1.1) * (1.0 - retract * retract)
	var sway := 0.35 * smoothstep(0.1, 0.6, tb) * (1.0 - retract)
	for v in _vines:
		_apply_pose(v, sway, tb, ext)
	var fade := 1.0 - clampf((tb - hold) / (RETRACT * 0.9), 0.0, 1.0)
	_ring_mat.albedo_color.a = 0.6 * fade
	_disc_mat.albedo_color.a = 0.22 * fade
	if tb > hold + RETRACT + 0.05:
		visible = false


func _apply_pose(v: Dictionary, sway: float, tb: float, ext: float) -> void:
	var base: Node3D = v["base"]
	if not bool(v["ok"]) or ext <= 0.001:
		base.visible = false
		return
	base.visible = true
	var pos: Vector3 = v["pos"]
	var sc: float = v["scale"]
	base.scale = Vector3.ONE * sc
	# Sink under the floor by the missing extension (the terrain hides what is below it).
	base.position.y = pos.y - (1.0 - minf(ext, 1.0)) * (LENGTH * sc * 0.95 + 0.1)
	var joints: Array = v["joints"]
	var n := joints.size()
	var phase: float = v["phase"]
	for i in n:
		var f := float(i) / float(n)
		var curl := 0.07 + 0.2 * f * f                      # the tips curl over
		var wob := sway * sin(2.2 * tb - float(i) * 0.7 + phase) * (0.3 + f)
		var j: Node3D = joints[i]
		j.rotation.x = curl + wob * 0.5
		j.rotation.z = sway * 0.6 * cos(1.9 * tb - float(i) * 0.6 + phase) * f


static func _ease_out_back(u: float) -> float:
	var c1 := 1.5
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(u - 1.0, 3.0) + c1 * pow(u - 1.0, 2.0)

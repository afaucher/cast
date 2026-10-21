extends LabBase
## Goo imp lab (docs/design/goo-imp.md): look-dev for a proposed sewer pest that lobs goo, its three blockouts
## (GooImpBlockouts: sac, drip, ladle) on the sewer slice's real terrain drawing (SewerLayouts.Builder, HexMapView,
## DungeonLook, SewerView in the brick look), at the REAL game camera (CameraRig: yaw 45, pitch -56, ortho 24) at 1920x1080.
## LOOK-DEV ONLY: nothing here is used by the game, nothing declares gameplay state; the goo ball, its landing marker, the
## patches and the fire are lab stand-ins. Scene: scenes/goo_imp_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/goo_imp_lab.tscn --shot <dir> [--view <name>] [--goo bile|pink|tar]
##
## The map: a cistern (room A, radius 7) with a channel across it, a 6.0 sewer main (a 3.0 channel between two 1.5 ledges)
## to a small outfall room (B). One connected body of water, like every sewer layout.
##
## --shot <dir>  renders every view into <dir>, then quits:
##   <kind>_alone.png (+ _crop 240x135 x3, _crop_gray)   the imp alone, three-quarters, on the cistern's dry deck; kind sac/drip/ladle
##   close.png, close_throw.png                  low angle (ortho 4.6): the swarmer imp and the three, at rest / winding up
##   lineup.png (+ _gray, _crop)                 Wick, the swarmer imp, a grunt and the three, named, at the game camera
##   sewer_<kind>.png (+ _gray, _crop, _crop_gray)  a pack of three on the main's far ledge, the crew wading the channel
##   throw.png (+ _crop)                         the throw mocked: a ball mid-arc, its landing marker, a fresh patch, a
##                                               hero stuck in a patch, a ball that fell in the water
##   fire.png (+ _crop)                          a fireball has lit a patch under the pack: one imp burning, one backing off
##   goo_colours.png (+ _gray, _crop)            the same imp, ball and patch in each goo colour (bile, pink, tar)
##   sheet.png                                   the comparison sheet
## --view <name>  only that view (no derived images).
## --goo <name>   the goo colour of every view but goo_colours (default bile; GooImpBlockouts.GOO).

const GooImpBlockouts := preload("res://scripts/art/lowpoly/monsters/goo_imp_blockouts.gd")
const SewerProps := preload("res://scripts/art/lowpoly/props/sewer_props.gd")

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const KINDS: Array[String] = ["sac", "drip", "ladle"]
const LOOK := "brick"
const FLOOR_Y := SewerLayouts.CH_LEVEL * Hex.LEVEL_HEIGHT     ## -0.5: the channel floor
const SURFACE := SewerLayouts.SURFACE_Y                       ## -0.14: the water surface
const D := Hex.DIRS
const FIRE_OUTER := Burning.OUTER
const FIRE_INNER := Burning.INNER

var goo_name := "bile"
var goo := Color(0.80, 1.0, 0.16)
var terrain: HexMapView
var sewer: SewerView
var env: Environment
var stage: Node3D                 ## everything one view places (cleared between views)
var a0 := Vector2i.ZERO           ## the cistern's centre
var b0 := Vector2i.ZERO           ## the outfall room's centre
var mn: Array[Vector2i] = []      ## the main's route (its near rim row), door to door
var _right := Vector3.ZERO
var _fwd := Vector3.ZERO
var _flame_meshes: Array[ArrayMesh] = []
var _flame_mats: Array[ShaderMaterial] = []


func _ready() -> void:
	goo_name = arg(args, "--goo", "bile")
	goo = GooImpBlockouts.GOO.get(goo_name, GooImpBlockouts.GOO["bile"])
	_build_sewer()
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	make_camera(220.0)
	var yaw := deg_to_rad(GAME_YAW)
	_right = Vector3(cos(yaw), 0.0, -sin(yaw))
	_fwd = Vector3(-sin(yaw), 0.0, -cos(yaw))
	if shot_path != "":
		DirAccess.make_dir_recursive_absolute(shot_path)
		_run_shots()
	else:
		_place("lineup")


# --------------------------------------------------------------------------- the sewer

func _build_sewer() -> void:
	var b := SewerLayouts.Builder.new()
	b.room(a0, 7, "room:0")
	mn = b.hall("main", a0 + D[1] * 7, 1, 12, 2)
	b0 = a0 + D[1] * 23
	b.room(b0, 4, "room:1")
	b.make_map()
	b.wet_line(a0 + D[2] + D[4] * 7, a0 + D[2] + D[1] * 7)
	b.flood_main("main", mn, 1)
	b.wet_line(b0 + D[2] + D[4] * 4, b0 + D[2] + D[1] * 4)
	b.apply_water()
	b.body_record(LOOK)
	map = b.map
	GameWorld.begin(map, self, 3)
	terrain = HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	var flow := PackedVector2Array([SewerLayouts.w(a0 + D[2] + D[4] * 7), SewerLayouts.w(b0 + D[2] + D[1] * 4)])
	sewer = SewerView.dress(self, map, terrain, LOOK, [flow])
	for c in get_children():
		if c is WorldEnvironment:
			env = (c as WorldEnvironment).environment
	var col: Color = SewerView.LOOKS[LOOK]["pipe"]
	_fixed(SewerProps.build("outfall", {"radius": 0.6, "drop": 1.0}), _w(a0 + D[2] + D[4] * 7), _yaw_to(Hex.dir_vector(1)))
	_fixed(SewerProps.build("bars", {"width": 2.8, "height": 1.3}), _w(b0 + D[2] + D[1] * 4), _yaw_to(Hex.dir_vector(1)))
	for i: int in [2, 6, 10]:
		_fixed(SewerProps.build("springer", {"height": 1.5, "col": SewerView.LOOKS[LOOK]["wall_base"]}), _w(mn[i] + D[2] * 3), _yaw_to(-_across()))
	_fixed(SewerProps.build("pipe_bundle", {"length": 4.0, "col": col}), _w(mn[8] + D[2] * 3) - _across() * 0.05, _yaw_to(-_across()))


func _fixed(n: Node3D, p: Vector3, yaw_deg: float) -> Node3D:
	add_child(n)
	n.position = Vector3(p.x, 0.0, p.z)
	n.rotation_degrees.y = yaw_deg
	return n


static func _w(c: Vector2i) -> Vector3:
	return Hex.to_world(c)


## Yaw (degrees) that turns a prop's front (+Z) onto v.
static func _yaw_to(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


## The unit vector across the main, toward its far ledge (DIRS[2]'s side).
static func _across() -> Vector3:
	var ax := Hex.dir_vector(1)
	var v := Vector3(-ax.z, 0, ax.x)
	return v if v.dot(Hex.dir_vector(2)) > 0.0 else -v


## A spot on the main's far ledge beside route cell i; the near ledge; the channel's middle.
func _far(i: int, along: float = 0.0) -> Vector3:
	return _w(mn[i] + D[2] * 2) + _across() * 0.75 + Hex.dir_vector(1) * along


func _near(i: int, along: float = 0.0) -> Vector3:
	return _w(mn[i]) - _across() * 0.75 + Hex.dir_vector(1) * along


func _chan(i: int, along: float = 0.0, off: float = 0.0) -> Vector3:
	return _w(mn[i] + D[2]) + Hex.dir_vector(1) * along + _across() * off + Vector3(0, FLOOR_Y, 0)


# --------------------------------------------------------------------------- actors (static models)

func _clear() -> void:
	for c in stage.get_children():
		stage.remove_child(c)
		c.queue_free()


func _imp(kind: String, p: Vector3, face: Vector3, pose: String = "rest", k: float = 1.0, col: Color = goo) -> GooImpBlockouts.ImpBody:
	var m: GooImpBlockouts.ImpBody = GooImpBlockouts.build(kind, col)
	_stand(m, p, face)
	m.pose_preview(pose, k)
	return m


func _mon(kind: String, p: Vector3, face: Vector3, pose: String = "rest") -> MonsterModel:
	var m := MonsterModels.make(kind)
	_stand(m, p, face)
	m.pose_preview(pose, 1.0)
	return m


func _hero(which: String, p: Vector3, face: Vector3, pose: String = "") -> LowPolyModel:
	var m: LowPolyModel
	match which:
		"wick": m = WickModel.new()
		"gasket": m = GasketModel.new()
		_: m = RebarModel.new()
	_stand(m, p, face)
	match pose:
		"cast":
			if which == "wick":
				m.call("pose_preview", "cast", 0.6)
			else:
				m.call("cast_pose")
		"shoot":
			m.call("pose_preview", "shoot", 0.6)
	return m


## Stand a model at p (y as given), its front (-Z) toward `face`; frozen.
func _stand(m: LowPolyModel, p: Vector3, face: Vector3) -> void:
	stage.add_child(m)
	m.idle_enabled = false
	m.position = p
	m.rotation = Vector3(0.0, atan2(-face.x, -face.z), 0.0)
	m.apply_idle(0.6)
	if p.y < -0.2:
		_ripple(p, 0.45)


# --------------------------------------------------------------------------- goo and fire (lab stand-ins)

func _glow_mat(c: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.render_priority = 3
	return m


func _shade_mat(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 2
	return m


func _soup_node(s: LowPoly.Soup, p: Vector3, outline: float, gain: float, yaw: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = s.to_mesh()
	var mat := MonsterMaterial.make(outline)
	mat.set_shader_parameter("glow_gain", gain)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)
	mi.position = p
	mi.rotation.y = yaw
	return mi


func _disc(center: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.01
	cm.radial_segments = 40
	mi.mesh = cm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)
	mi.position = center
	return mi


func _ring(center: Vector3, r: float, w: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = r - w
	tm.outer_radius = r
	tm.rings = 40
	mi.mesh = tm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)
	mi.position = center
	mi.scale = Vector3(1.0, 0.1, 1.0)


func _ripple(p: Vector3, r: float) -> void:
	_ring(Vector3(p.x, SURFACE + 0.01, p.z), r, 0.05, _glow_mat(Color(0.85, 0.9, 0.7), 0.5, 0.6))


func _label(text: String, p: Vector3, col: Color, size: int = 24) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = size
	l.outline_size = 10
	l.pixel_size = 0.012
	l.modulate = col
	l.outline_modulate = Color(0.05, 0.03, 0.03)
	stage.add_child(l)
	l.global_position = p


## A goo patch on the floor at p (radius r): a lumpy sheet with lobes round the edge, splats beyond it, glowing wet spots and
## bubbles. `burnt`: charred black with glowing cracks (the fire mock's bed).
func _patch(p: Vector3, r: float, col: Color, seed_value: int, burnt: bool = false) -> MeshInstance3D:
	var s := LowPoly.Soup.new(seed_value, 0.04)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := col.darkened(0.15) if not burnt else Color(0.10, 0.08, 0.06)
	var rim := GooImpBlockouts.deep(col) if not burnt else Color(0.05, 0.04, 0.03)
	MonsterModel.blob(s, Vector3(0, 0.0, 0), Vector3(r * 1.02, 0.035, r * 0.9), rim, seed_value + 1, 0.10, 1)
	MonsterModel.blob(s, Vector3(0, 0.025, 0), Vector3(r * 0.86, 0.035, r * 0.76), body, seed_value + 2, 0.10, 1)
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf_range(-0.3, 0.3)
		var d := r * rng.randf_range(0.75, 0.95)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.01, sin(a) * d), Vector3(r * 0.30, 0.03, r * 0.24), rim if i % 2 == 0 else body, seed_value + 10 + i, 0.15, 0, Vector3(0, rad_to_deg(-a), 0))
	for i in 6:
		var a := rng.randf_range(0.0, TAU)
		var d := r * rng.randf_range(1.15, 1.45)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.01, sin(a) * d), Vector3.ONE * r * rng.randf_range(0.07, 0.12) * Vector3(1, 0.4, 1), body, seed_value + 20 + i, 0.15)
	var shine := MonsterModel.glow(col) if not burnt else MonsterModel.glow(FIRE_OUTER)
	for i in 5:
		var a := rng.randf_range(0.0, TAU)
		var d := r * rng.randf_range(0.0, 0.6)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.05, sin(a) * d), Vector3(r * 0.16, 0.02, r * 0.12), shine, seed_value + 30 + i, 0.15)
	for i in 4:
		var a := rng.randf_range(0.0, TAU)
		var d := r * rng.randf_range(0.1, 0.7)
		var hb := GooImpBlockouts.hot(col) if not burnt else Color(0.25, 0.2, 0.15)
		MonsterModel.blob(s, Vector3(cos(a) * d, 0.06, sin(a) * d), Vector3.ONE * r * 0.07, MonsterModel.glow(hb) if not burnt else hb, seed_value + 40 + i, 0.1)
	return _soup_node(s, p + Vector3(0, 0.01, 0), 1.6, 1.3)


## A goo ball in flight (bigger than the one in the hand, so it reads in the air), with a drip tail along `vel`.
func _ball(p: Vector3, r: float, col: Color, vel: Vector3) -> void:
	var s := LowPoly.Soup.new(71, 0.05)
	MonsterModel.blob(s, Vector3.ZERO, Vector3.ONE * r, MonsterModel.glow(col), 72, 0.18, 1)
	MonsterModel.blob(s, Vector3(-r * 0.3, r * 0.45, -r * 0.2), Vector3.ONE * r * 0.35, MonsterModel.glow(GooImpBlockouts.hot(col)), 73, 0.1)
	var back := -vel.normalized()
	MonsterModel.limb(s, back * r * 0.6, back * r * 2.4, r * 0.45, r * 0.05, 5, MonsterModel.glow(col), 74)
	_soup_node(s, p, 2.0, 1.8)


## The throw: an arc from `from` to `to` (apex `h` over the higher end), the ball at `t`, droplets behind it, and the
## landing marker (a dark shadow and a goo ring) on the floor at `to`.
func _throw(from: Vector3, to: Vector3, h: float, t: float, col: Color, marker: bool = true) -> void:
	var top := maxf(from.y, to.y) + h
	var pts: Array[Vector3] = []
	for i in 41:
		var u := float(i) / 40.0
		var p := from.lerp(to, u)
		p.y = lerpf(from.y, to.y, u) + 4.0 * (top - maxf(from.y, to.y)) * u * (1.0 - u)
		pts.append(p)
	var bi := int(t * 40.0)
	var vel := pts[mini(bi + 1, 40)] - pts[bi]
	_ball(pts[bi], 0.26, col, vel)
	for j in range(1, 8):
		var k := bi - j * 2
		if k < 1:
			break
		var sp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var rr := 0.09 * (1.0 - 0.1 * float(j))
		sm.radius = rr
		sm.height = rr * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		sp.mesh = sm
		sp.material_override = _glow_mat(col, 0.9 - 0.1 * float(j), 2.0)
		stage.add_child(sp)
		sp.position = pts[k]
	if not marker:
		return
	var land := Vector3(to.x, to.y + 0.02, to.z)
	var dist := absf(pts[bi].y - to.y)
	_disc(land, lerpf(0.55, 0.3, clampf(dist / 4.0, 0.0, 1.0)), _shade_mat(Color(0.0, 0.0, 0.0), 0.55))
	_ring(land + Vector3(0, 0.02, 0), 0.8, 0.07, _glow_mat(col, 0.9, 1.6))


## A hero stuck in goo: blobs over the feet and shins, strands to the floor.
func _stuck(h: Node3D, col: Color) -> void:
	var s := LowPoly.Soup.new(81, 0.05)
	for x: float in [-0.17, 0.17]:
		MonsterModel.blob(s, Vector3(x, 0.10, 0.0), Vector3(0.17, 0.13, 0.20), col.darkened(0.15), 82 + int(x * 10.0), 0.18)
		MonsterModel.blob(s, Vector3(x, 0.22, -0.02), Vector3(0.12, 0.10, 0.12), MonsterModel.glow(col), 84 + int(x * 10.0), 0.18)
		for k in 3:
			var a := float(k) * 2.1 + x * 4.0
			var top := Vector3(x + cos(a) * 0.10, 0.36, sin(a) * 0.10)
			var bot := Vector3(x + cos(a) * 0.32, 0.0, sin(a) * 0.30)
			MonsterModel.limb(s, top, bot, 0.035, 0.015, 4, MonsterModel.glow(col), 86 + k + int(x * 20.0))
	var n := _soup_node(s, h.position, 1.6, 1.2)
	n.rotation = h.rotation


## Fire on a patch: flames the way Burning draws them (two cone meshes, outer orange and inner yellow, glowing), spread over
## the patch, and a warm light.
func _fire(p: Vector3, r: float, seed_value: int, count: int = 16, size: float = 1.0) -> void:
	if _flame_meshes.is_empty():
		_flame_meshes.append(LowPoly.cylinder(0.24, 0.0, 1.0, 5, FIRE_OUTER, 3, 0.04, 2).to_mesh(0.0))
		_flame_meshes.append(LowPoly.cylinder(0.15, 0.0, 0.7, 4, FIRE_INNER, 5, 0.03, 2).to_mesh(0.0))
		_flame_mats.append(LowPolyMaterial.make_glow(FIRE_OUTER, 0.9, 1.2, Burning.OUTLINE))
		_flame_mats.append(LowPolyMaterial.make_glow(FIRE_INNER, 1.2, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var a := rng.randf_range(0.0, TAU)
		var d := r * sqrt(rng.randf()) * 0.95
		var big := i % 3 != 2
		var m := MeshInstance3D.new()
		m.mesh = _flame_meshes[0] if big else _flame_meshes[1]
		m.material_override = _flame_mats[0] if big else _flame_mats[1]
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sc := rng.randf_range(0.7, 1.3) * (1.0 - 0.35 * d / r) * size
		m.scale = Vector3(1.2 * size, sc, 1.2 * size)
		m.position = p + Vector3(cos(a) * d, 0.5 * sc + 0.03, sin(a) * d)
		m.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, TAU), rng.randf_range(-0.2, 0.2))
		stage.add_child(m)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 2.5
	l.omni_range = r * 3.0 + 2.0
	l.shadow_enabled = false
	stage.add_child(l)
	l.position = p + Vector3(0, 1.0, 0)


# --------------------------------------------------------------------------- views

func _views() -> Array[String]:
	var out: Array[String] = []
	for k in KINDS:
		out.append(k + "_alone")
	out.append_array(["close", "close_throw", "lineup"])
	for k in KINDS:
		out.append("sewer_" + k)
	out.append_array(["throw", "fire", "goo_colours"])
	return out


## Where each view looks (its game-camera centre, also the crop centre).
var focus := Vector3.ZERO


func _place(view: String) -> void:
	_clear()
	if view.ends_with("_alone"):
		_place_alone(view.trim_suffix("_alone"))
	elif view.begins_with("sewer_"):
		_place_pack(view.trim_prefix("sewer_"))
	else:
		call("_place_" + view)


func _deck(off_right: float, off_fwd: float) -> Vector3:
	return _w(a0 + D[5] * 3) + _right * off_right + _fwd * off_fwd


func _place_alone(kind: String) -> void:
	focus = _deck(0.0, 0.0)
	_imp(kind, focus, -_fwd * 0.6 - _right)
	_game(focus)


func _game(at: Vector3) -> void:
	aim(GAME_YAW, GAME_PITCH, GAME_SIZE, at + Vector3(0, 0.5, 0))


## Low angle (yaw 160, pitch -18), ortho 4.6: the swarmer and the three in a row facing the camera.
func _row(pose: String) -> void:
	var yaw := 160.0
	var r := Vector3(cos(deg_to_rad(yaw)), 0.0, -sin(deg_to_rad(yaw)))
	var toward := Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))
	var base := _deck(0.0, 0.5)
	var xs := [-2.4, -0.8, 0.8, 2.4]
	_mon("swarmer", base + r * float(xs[0]), toward.rotated(Vector3.UP, 0.5), pose)
	for i in 3:
		_imp(KINDS[i], base + r * float(xs[i + 1]), toward.rotated(Vector3.UP, 0.95), pose, 1.0)
	focus = base
	aim(yaw, -18.0, 4.6, base + Vector3(0, 0.75, 0))


func _place_close() -> void:
	_row("rest")


func _place_close_throw() -> void:
	_row("windup")


func _place_lineup() -> void:
	var toward := -_fwd - _right * 0.35
	var row: Array = [["Wick", "wick"], ["Imp (swarmer)", "swarmer"], ["Grunt", "grunt"], ["Goo Sac", "sac"], ["Gloop", "drip"], ["Slinger", "ladle"]]
	var x := -6.0
	for e: Array in row:
		var p := _deck(x, 0.4)
		var k := String(e[1])
		if k == "wick":
			_hero(k, p, toward)
		elif k in KINDS:
			_imp(k, p, toward.rotated(Vector3.UP, -0.8))     # turned to show the carry
		else:
			_mon(k, p, toward)
		_label(String(e[0]), p - _fwd * 1.5 + Vector3(0, 0.05, 0), Color(0.95, 0.92, 0.84), 22)
		x += 2.4
	focus = _deck(0.0, 0.4)
	_game(focus)


## A pack of three on the main's far ledge (one winding up, one throwing, one at rest), the crew wading below and on the
## near ledge.
func _place_pack(kind: String) -> void:
	var to_crew := -_across()
	_imp(kind, _far(4, 0.2), to_crew.rotated(Vector3.UP, 0.3), "windup", 0.8)
	_imp(kind, _far(6, -0.3), to_crew, "rest")
	_imp(kind, _far(7, 0.6), to_crew.rotated(Vector3.UP, -0.3), "swing", 0.5)
	_hero("rebar", _chan(5, 0.0, -0.2), _across())
	_hero("gasket", _chan(7, 0.4, -0.6), _across().rotated(Vector3.UP, 0.4))
	_hero("wick", _near(3), _across().rotated(Vector3.UP, -0.5), "cast")
	focus = _chan(5, 0.8) - Vector3(0, FLOOR_Y, 0)
	_game(focus)


## A point in the cistern (room A): cell a0 + c, plus a world offset. Its channel is the row a0 + D[2] (along D[1]); the
## far deck is beyond it (D[2]'s side), the near deck this side (the camera sees both: the near wall is far away).
func _ac(c: Vector2i, off: Vector3 = Vector3.ZERO) -> Vector3:
	return _w(a0 + c) + off


## The throw mocked in the cistern: the pack on the far deck across the channel, one imp winding up, another's ball
## mid-arc toward Wick on the near deck with its landing marker, a fresh patch (a miss), Gasket stuck in an older patch,
## Rebar wading, and a ball that fell short into the channel.
func _place_throw() -> void:
	var to_crew := -_across()
	_imp("sac", _ac(D[2] * 3 + D[4] * 2), to_crew.rotated(Vector3.UP, 0.3), "windup", 1.0)
	var thrower := _imp("sac", _ac(D[2] * 3 + D[1]), to_crew.rotated(Vector3.UP, 0.2), "swing", 0.7)
	_imp("sac", _ac(D[2] * 4 + D[1] * 3), to_crew.rotated(Vector3.UP, -0.2), "rest")
	var wp := _ac(D[5] * 2 + D[1])
	_hero("wick", wp, _across().rotated(Vector3.UP, -0.4))
	var land := wp - _right * 0.9 + _fwd * 0.3
	_throw(thrower.global_position + Vector3(0, 1.0, 0), land, 2.0, 0.62, goo)
	var miss := _ac(D[5] + D[1] * 3, _right * 0.3)
	_patch(miss, 0.75, goo, 501)
	var gp := _ac(D[5] + D[4] * 3)
	_patch(gp, 0.8, goo, 502)
	var gas := _hero("gasket", gp, _across().rotated(Vector3.UP, 0.6))
	_stuck(gas, goo)
	_hero("rebar", _ac(D[2] + D[4], Vector3(0, FLOOR_Y, 0)), _across().rotated(Vector3.UP, 0.3))
	var slick := _ac(D[2] + D[1] * 3)
	_patch(Vector3(slick.x, SURFACE - 0.02, slick.z), 0.55, goo, 503)
	_ring(Vector3(slick.x, SURFACE + 0.01, slick.z), 0.85, 0.04, _glow_mat(Color(0.85, 0.9, 0.7), 0.35, 0.6))
	var tag := Color(0.95, 0.92, 0.84)
	_label("lands here", land - _fwd * 1.0 - _right * 0.4, tag, 20)
	_label("a miss: a patch, 5 s", miss - _fwd * 1.3, tag, 20)
	_label("stuck: slowed", gp - _fwd * 1.4, tag, 20)
	_label("in the water: a slick?", Vector3(slick.x, 0.1, slick.z) + _fwd * 1.3 + _right * 0.6, tag, 20)
	focus = _ac(D[2])
	_game(focus)


## Fire on goo: Wick's fireball has lit a patch on the far deck under the pack: the patch burns, one imp in it is on
## fire, one backs off, one keeps throwing; an unlit patch beside them.
func _place_fire() -> void:
	var to_crew := -_across()
	var fp := _ac(D[2] * 3)
	_disc(fp + Vector3(0, 0.005, 0), 1.7, _shade_mat(Color(0.05, 0.03, 0.02), 0.45))     # the blast's scorch
	_patch(fp, 1.0, goo, 601, true)
	_fire(fp, 0.95, 602, 20, 0.85)
	var burning := _imp("sac", fp + _right * 0.35 + _fwd * 0.2, to_crew.rotated(Vector3.UP, 1.4), "swing", 0.3)
	burning.set_tint(Color(1.0, 0.4, 0.1), 0.35)
	_fire(burning.position + Vector3(0, 0.3, 0), 0.32, 603, 7, 1.0)
	_imp("sac", fp - _right * 1.9 + _fwd * 0.4, (-_right).rotated(Vector3.UP, 0.4), "rest")
	_imp("sac", _ac(D[2] * 3 + D[1] * 3), to_crew.rotated(Vector3.UP, -0.2), "windup", 0.9)
	var unlit := _ac(D[2] * 2 + D[1] * 4)
	_patch(unlit, 0.65, goo, 604)
	_hero("wick", _ac(D[5] + D[4]), _across().rotated(Vector3.UP, -0.2), "cast")
	_hero("rebar", _ac(D[2] + D[4] * 3, Vector3(0, FLOOR_Y, 0)), _across())
	_label("fireball on a patch: it burns", fp + Vector3(0, 2.3, 0), Color(1.0, 0.75, 0.4), 20)
	_label("unlit patch", unlit - _fwd * 1.1, Color(0.95, 0.92, 0.84), 20)
	focus = _ac(D[2] * 2)
	_game(focus)


## The goo colours side by side on the cistern's deck: for each, the sac imp, a ball in the air and a patch.
func _place_goo_colours() -> void:
	var names: Array = GooImpBlockouts.GOO.keys()
	var x := -4.2
	for n: String in names:
		var col: Color = GooImpBlockouts.GOO[n]
		var p := _deck(x, 1.0)
		_imp("sac", p, -_fwd - _right * 0.3, "rest", 1.0, col)
		_patch(p - _fwd * 1.6 + _right * 0.3, 0.75, col, 700 + int(x * 10.0))
		_ball(p + Vector3(0, 1.9, 0) + _right * 1.1, 0.26, col, _right - Vector3(0, 0.6, 0))
		_label(n, p - _fwd * 2.9, Color(0.95, 0.92, 0.84), 24)
		x += 4.2
	focus = _deck(0.0, 0.0)
	_game(focus)


# --------------------------------------------------------------------------- shots

static func _gray(img: Image) -> Image:
	var g := img.duplicate() as Image
	g.adjust_bcs(1.0, 1.0, 0.0)
	return g


## A crop of `size` around the screen point of world position `at`, scaled by `k` (nearest: game pixels stay pixels).
func _crop(img: Image, at: Vector3, size: Vector2i, k: int) -> Image:
	var sp := camera.unproject_position(at)
	var vr := get_viewport().get_visible_rect().size
	sp = Vector2(sp.x * img.get_width() / vr.x, sp.y * img.get_height() / vr.y)
	var x := clampi(int(sp.x) - size.x / 2, 0, img.get_width() - size.x)
	var y := clampi(int(sp.y) - size.y / 2, 0, img.get_height() - size.y)
	var c := img.get_region(Rect2i(x, y, size.x, size.y))
	if k > 1:
		c.resize(size.x * k, size.y * k, Image.INTERPOLATE_NEAREST)
	return c


func _save(img: Image, name_: String) -> void:
	save_shot(img, shot_path.path_join(name_ + ".png"))


func _run_shots() -> void:
	await wait_frames(20)
	if only_view != "":
		_place(only_view)
		var one := await grab(8)
		one.convert(Image.FORMAT_RGB8)
		_save(one, only_view)
		finish()
		return
	var crops := {}
	for v in _views():
		_place(v)
		var img := await grab(8)
		img.convert(Image.FORMAT_RGB8)
		_save(img, v)
		crops[v] = img
		var mid := focus + Vector3(0, 0.6, 0)
		if v.ends_with("_alone"):
			var c := _crop(img, mid, Vector2i(240, 135), 3)
			_save(c, v + "_crop")
			_save(_gray(c), v + "_crop_gray")
			crops[v + "_crop"] = c
		elif v.begins_with("close"):
			pass
		else:
			var c2 := _crop(img, mid, Vector2i(960, 540), 2)
			_save(c2, v + "_crop")
			crops[v + "_crop"] = c2
			if v != "throw" and v != "fire":
				_save(_gray(img), v + "_gray")
				if v.begins_with("sewer_"):
					_save(_gray(c2), v + "_crop_gray")
	_sheet(crops)
	finish()


## The comparison sheet (1920 wide): the close-ups (rest beside windup, their row of models); the three alone crops in colour and in grey; the
## lineup crop in colour and grey; the three packs and their greys; the throw, the fire and the goo colours.
func _sheet(crops: Dictionary) -> void:
	var w := 1920
	var blocks: Array = []        # each: [Array of images in a row]
	var band := Rect2i(0, 340, 1920, 480)          # (the close-ups' row of models)
	blocks.append([(crops["close"] as Image).get_region(band), (crops["close_throw"] as Image).get_region(band)])
	var alone: Array = []
	var alone_g: Array = []
	for k in KINDS:
		alone.append(crops[k + "_alone_crop"])
		alone_g.append(_gray(crops[k + "_alone_crop"]))
	blocks.append(alone)
	blocks.append(alone_g)
	blocks.append([crops["lineup_crop"], _gray(crops["lineup_crop"])])
	var packs: Array = []
	var packs_g: Array = []
	for k in KINDS:
		packs.append(crops["sewer_" + k + "_crop"])
		packs_g.append(_gray(crops["sewer_" + k + "_crop"]))
	blocks.append(packs)
	blocks.append(packs_g)
	blocks.append([crops["throw_crop"], crops["fire_crop"], crops["goo_colours_crop"]])
	var rows: Array[Image] = []
	for row: Array in blocks:
		var n := row.size()
		var cw := w / n
		var src: Image = row[0]
		var ch := int(float(src.get_height()) * float(cw) / float(src.get_width()))
		var strip := Image.create(w, ch, false, Image.FORMAT_RGB8)
		strip.fill(Color(0.06, 0.05, 0.05))
		for i in n:
			var im := (row[i] as Image).duplicate() as Image
			im.convert(Image.FORMAT_RGB8)
			im.resize(cw - 4, ch - 4, Image.INTERPOLATE_BILINEAR)
			strip.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(i * cw + 2, 2))
		rows.append(strip)
	var h := 0
	for r in rows:
		h += r.get_height()
	var sheet := Image.create(w, h, false, Image.FORMAT_RGB8)
	var y := 0
	for r in rows:
		sheet.blit_rect(r, Rect2i(Vector2i.ZERO, r.get_size()), Vector2i(0, y))
		y += r.get_height()
	_save(sheet, "sheet")

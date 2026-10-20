extends Node3D
## Shark lab (docs/design/sharks.md): the three sharks (SharkModels: regular, laser, imp-ridden) in the game's REAL pools
## (PoolGeo shapes carved into a HexMap room, HexMapView's inset drawing, PoolView's water, coping and foam, DungeonLook
## and the theme's accent light), the laser's telegraph and beam, and the swim prototype (SharkSwim: continuous steering
## in the water polygon, a bending body). Look-dev only: nothing here is used by the game and nothing declares gameplay
## state. Scene: scenes/shark_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/shark_lab.tscn --case indoor --shot <png> [--view <name>]
##   godot --path . --headless -- --scene res://scenes/shark_lab.tscn --measure        (the doc's tables: SharkMeasure)
##   godot --path . --resolution 960x540 --write-movie <dir>/f.png --fixed-fps 20 --quit-after 90 -- --scene res://scenes/shark_lab.tscn --case swim_pool
##
## --case (stills)
##   indoor     the indoor pool (bunker; the 7-cell trapezoid, the biggest it deals): a regular shark mid-turn, loungers
##   moat       a 1-row moat ring round its island (lair): a regular shark in the channel, the bridge, the fin sign
##   shark_pool the moat room's shark pool (2-row, moat look): the laser shark
##   specimen   the science room's specimen pool (one row of 3 under the gantry): a regular shark, to show it is too narrow
##   lagoon     the proposed 3-row lagoon (moat look): the imp-ridden laser shark with room to turn
##   throne     the proposed throne island: a moat ring round the throne, the imp laser shark guarding the door side
##   twin       the proposed twin pools with a gangway between them, a regular shark in each
##   moat2      the proposed 2-row moat ring
##   variants   the three sharks side by side in a lagoon (views: game, close, regular, laser, imp, side_*)
##   laser      the imp laser shark in the shark pool, the crew on the deck behind cover (views: game, aim, lock, fire)
## --case (animated: run with --write-movie)
##   swim_pool  patrol and turn round in the indoor pool's 7-cell trapezoid
##   swim_lagoon patrol in the lagoon
##   swim_moat  circling a 1-row moat ring
##   swim_moat2 circling a 2-row moat ring, then turning round
##   lunge      hunt, wind-up, lunge onto the rim at Wick, slide back
##   laser_fire the laser shark turns, aims, locks and fires across the room
## --shot <png>   renders every view of the case: <base>.png (game) and <base>_<view>.png, then quits
## --view <name>  only that view, written to <png> exactly

const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")
const SharkSwim := preload("res://scripts/art/lowpoly/shark_swim.gd")
const SharkMeasure := preload("res://scripts/art/lowpoly/shark_measure.gd")
const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const LH := Hex.LEVEL_HEIGHT

var case_name := "indoor"
var shot_path := ""
var only_view := ""
var map: HexMap
var camera: Camera3D
var views := {}                     ## name -> {size, at, yaw, pitch, setup: Callable}
var view_order: Array[String] = []
var sims: Array = []                ## [SharkSwim, shark Node3D, fin ripple, bow ripple]
var fx := {}                        ## laser fx nodes
var _t := 0.0
var _script: Callable               ## an animated case's per-frame director
var _pool_recs: Array = []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.has("--measure"):
		SharkMeasure.run()
		get_tree().quit()
		return
	case_name = _arg(a, "--case", "indoor")
	shot_path = _arg(a, "--shot")
	only_view = _arg(a, "--view")
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	call("_case_" + case_name)
	if view_order.is_empty():
		_view("game", GAME_SIZE, Vector3.ZERO)
	if shot_path != "":
		_run_shots()
	else:
		_prepare(view_order[0])


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


# --------------------------------------------------------------------------- the room and its pools

## A round room (tag room:0, radius `radius`) with a wall ring and a corridor out of its `door_dir` side, its floor and
## walls in the theme's materials. Pools are carved with _pool() before _finish().
func _room(radius: int, floor_mat: int, wall_mat: int, door_dir: int = 4) -> void:
	map = HexMap.new()
	var room_mat := FloorMaterials.pack(floor_mat, wall_mat)
	var corr_mat := FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)
	var cells := {}
	for c in Hex.range_cells(Vector2i.ZERO, radius):
		cells[c] = ["room:0", room_mat]
	if door_dir >= 0:
		var d: Vector2i = Hex.DIRS[door_dir]
		var side: Vector2i = Hex.DIRS[(door_dir + 1) % 6]
		for k in range(radius + 1, radius + 5):
			for w in [0, 1]:
				var c: Vector2i = d * k + side * w - side
				if not cells.has(c):
					cells[c] = ["corridor", corr_mat]
	for c: Vector2i in cells:
		var cell := map.set_cell(c, 0)
		cell.tag = str(cells[c][0])
		cell.mat_id = int(cells[c][1])
	for c: Vector2i in cells:
		for nb in Hex.neighbors(c):
			if not cells.has(nb) and not map.has_cell(nb):
				map.set_cell(nb, 3, HexMap.Tile.WALL).mat_id = int(cells[c][1])
	map.cut_walls()


## Carve one pool of `look` (its geometry from `variant`) with its centre near `at` (X/Z). Returns its record.
func _pool(look: String, v: Dictionary, at: Vector2) -> Dictionary:
	var anchor := Hex.from_world(Vector3(at.x - (v["center"] as Vector2).x, 0.0, at.y - (v["center"] as Vector2).y))
	PoolGeo._apply(map, "room:0", look, 0, v, anchor)
	var rec: Dictionary = map.pools[map.pools.size() - 1]
	_pool_recs.append(rec)
	return rec


## The first variant of `look`'s shapes (or a given list) with `size` basin cells (or ring cells) along `axis`.
static func _variant(list: Array, size: int, axis: int = -1, wide: bool = false) -> Dictionary:
	for v: Dictionary in list:
		if int(v["size"]) != size or (axis >= 0 and int(v["axis"]) != axis):
			continue
		if wide and float(v["half_wid"]) < 2.0:
			continue
		return v
	for v: Dictionary in list:
		if int(v["size"]) == size:
			return v
	return list[0]


## Terrain, lights and the pools' dressing (PoolView, its decorative fins removed: the sharks are here).
func _finish(theme: String) -> void:
	GameWorld.begin(map, self, 1)
	var terrain := HexMapView.new()
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self, map)
	if terrain.pool_view != null:
		for f in terrain.pool_view.fins:
			f.queue_free()
		terrain.pool_view.fins.clear()
	var l: Dictionary = RoomThemeDefs.THEMES[theme]["light"]
	add_child(ThemeLight.make({"room": "room:0", "pos": Vector3(0, 2.7, 0), "color": l["color"], "energy": float(l["energy"]),
		"range": float(l["range"]), "flicker": 0.0, "pulse": 0.0}))


func _floor_y(rec: Dictionary) -> float:
	return float(rec["floor_level"]) * LH


func _deck_y(rec: Dictionary) -> float:
	return float(rec["deck_level"]) * LH


# --------------------------------------------------------------------------- placing things

func _put(node: Node3D, pos: Vector3, yaw: float = 0.0) -> Node3D:
	add_child(node)
	node.position = pos
	node.rotation_degrees.y = yaw
	return node


static func yaw_to(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


## A crew member at pos facing the X/Z direction `face` (the hero models face -Z).
func _hero(which: String, pos: Vector3, face: Vector3) -> LowPolyModel:
	var m: LowPolyModel
	match which:
		"gasket": m = GasketModel.new()
		"rebar": m = RebarModel.new()
		_: m = WickModel.new()
	add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)
	return m


## A shark of `variant` in pool `rec`, swum for `warm` seconds from `start` heading `heading` (so it lies in a natural
## bend). The sim keeps running in animated cases. Returns the SharkSwim.
func _shark(variant: String, rec: Dictionary, start: Vector2, heading: Vector2, warm: float = 0.0, loop_dir: float = 1.0) -> SharkSwim:
	var sim := SharkSwim.new()
	sim.setup(rec["outline"], rec.get("hole", []), _floor_y(rec), _deck_y(rec), start, heading)
	sim.loop_sign = loop_dir
	var t := 0.0
	while t < warm:
		sim.step(1.0 / 60.0)
		t += 1.0 / 60.0
	var shark := SharkModels.build(variant)
	add_child(shark)
	var surf := float(rec["surface_y"])
	var fin := PoolProps.build("ripple", {"radius": 0.42})
	add_child(fin)
	var bow := PoolProps.build("ripple", {"radius": 0.3})
	add_child(bow)
	var wake := MeshInstance3D.new()
	wake.mesh = ImmediateMesh.new()
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.vertex_color_use_as_albedo = true
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wm.render_priority = 2
	wake.material_override = wm
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wake)
	sims.append([sim, shark, fin, bow, surf, wake])
	_pose_sim(sims.size() - 1)
	return sim


func _pose_sim(i: int) -> void:
	var e: Array = sims[i]
	var sim: SharkSwim = e[0]
	var xf := sim.segment_transforms()
	SharkModels.pose(e[1], xf[0], xf[1], xf[2])
	var fp := sim.fin_point()
	(e[2] as Node3D).position = Vector3(fp.x, float(e[4]) + 0.012, fp.y)
	(e[2] as Node3D).scale = Vector3.ONE * (0.8 + 0.5 * clampf(sim.speed / 3.0, 0.0, 1.0))
	var head: Transform3D = xf[0]
	var nose := head * Vector3(0, 0, SharkModels.HEAD_LEN + 0.15)
	var bow := e[3] as Node3D
	bow.position = Vector3(nose.x, float(e[4]) + 0.014, nose.z)
	bow.visible = sim.telegraph > 0.0 or sim.speed > 1.2
	bow.scale = Vector3.ONE * (0.7 + 1.6 * sim.telegraph + 0.2 * clampf(sim.speed / 3.0, 0.0, 1.0))
	_wake(e[5], sim, float(e[4]) + 0.016)
	# the bite's wind-up: the monsters' orange pulse (Monster._update_visual's tint) on the shark's own segments
	var k := 0.0
	if sim.telegraph > 0.0:
		k = (0.25 + 0.4 * sim.telegraph) * (0.75 + 0.25 * sin(_t * 32.0))
	var seg := SharkModels.segments(e[1])
	for key: String in ["head", "body", "tail"]:
		var mat := (seg[key] as MeshInstance3D).material_override as ShaderMaterial
		mat.set_shader_parameter("tint_color", Color(1.0, 0.22, 0.0))
		mat.set_shader_parameter("tint_k", k)


## The fin's wake: two foam lines spreading back from the dorsal fin along the path it swam, fading (cosmetic).
func _wake(mi: MeshInstance3D, sim: SharkSwim, y: float) -> void:
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	var k_speed := clampf(sim.speed / 2.4, 0.0, 1.0)
	if k_speed < 0.05:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var prev := []
	for k in n + 1:
		var d := 0.3 + float(k) * 0.24
		var p := sim.behind(d)
		var q := sim.behind(d + 0.1)
		var t := (p - q).normalized() if p.distance_to(q) > 0.0001 else Vector2.RIGHT
		var nv := Vector2(-t.y, t.x)
		var spread := 0.18 + float(k) * 0.055
		var a := 0.75 * k_speed * (1.0 - float(k) / float(n))
		var cur := []
		for side: float in [-1.0, 1.0]:
			var c := p + nv * spread * side
			cur.append([Vector3(c.x, y, c.y), Vector3(c.x + nv.x * 0.07 * side, y, c.y + nv.y * 0.07 * side), a])
		if not prev.is_empty():
			for j in 2:
				var p0: Array = prev[j]
				var p1: Array = cur[j]
				var c0 := Color(0.88, 0.98, 1.0, float(p0[2]))
				var c1 := Color(0.88, 0.98, 1.0, float(p1[2]))
				for vv: Array in [[p0[0], c0], [p0[1], c0], [p1[1], c1], [p0[0], c0], [p1[1], c1], [p1[0], c1]]:
					im.surface_set_color(vv[1])
					im.surface_add_vertex(vv[0])
		prev = cur
	im.surface_end()


func _process(delta: float) -> void:
	if not _script.is_valid():
		return
	_t += delta
	_script.call(delta)
	for i in sims.size():
		(sims[i][0] as SharkSwim).step(delta)
		_pose_sim(i)


# --------------------------------------------------------------------------- laser fx (lab stand-ins)

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
	m.no_depth_test = false
	return m


## A box from a to b, `w` wide and `h` tall, in material m.
func _bar(a: Vector3, b: Vector3, w: float, h: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, a.distance_to(b))
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) * 0.5)
	return mi


## Where a horizontal beam from `from` along `dir` stops: the first wall (HexMap) or a listed blocker circle [center, r].
func _beam_end(from: Vector3, dir: Vector3, reach: float, blockers: Array) -> Vector3:
	var step := 0.1
	var d := 0.0
	var p := from
	while d < reach:
		d += step
		p = from + dir * d
		var c := Hex.from_world(p)
		if not map.has_cell(c) or map.cells[c].type == HexMap.Tile.WALL or map.wall_at(p):
			return p - dir * step
		for bl: Array in blockers:
			var bc: Vector3 = bl[0]
			if Vector2(p.x - bc.x, p.z - bc.z).length() <= float(bl[1]):
				return p
	return p


## The telegraph: a thin red aiming line from the lens to `to` at beam height plus its trace on the deck, a reticle
## at the end. `locked`: the last 0.4 s (solid and bright) instead of the 0.8 s tracking (dimmer, flickering).
func _aim_fx(from: Vector3, to: Vector3, deck_y: float, locked: bool) -> void:
	_clear_fx()
	var c := Color(1.0, 0.12, 0.08)
	var line := _bar(from, to, 0.05 if locked else 0.035, 0.05 if locked else 0.035, _glow_mat(c, 0.95 if locked else 0.6, 3.0 if locked else 1.6))
	var trace_a := Vector3(from.x, deck_y + 0.02, from.z)
	var trace_b := Vector3(to.x, deck_y + 0.02, to.z)
	var trace := _bar(trace_a, trace_b, 0.12 if locked else 0.08, 0.01, _glow_mat(c, 0.45 if locked else 0.25, 1.2))
	var ret := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.38
	tm.outer_radius = 0.46
	ret.mesh = tm
	ret.material_override = _glow_mat(c, 0.85, 2.0)
	add_child(ret)
	ret.position = Vector3(to.x, deck_y + 0.03, to.z)
	ret.scale = Vector3(1, 0.15, 1)
	fx = {"line": line, "trace": trace, "ret": ret}


## The beam: a hot core inside a red sheath from the lens to where it stopped, sparks there and a scorch line on the deck.
func _beam_fx(from: Vector3, to: Vector3, deck_y: float) -> void:
	_clear_fx()
	var core := _bar(from, to, 0.08, 0.08, _glow_mat(Color(1.0, 0.85, 0.75), 1.0, 6.0))
	var sheath := _bar(from, to, 0.26, 0.26, _glow_mat(Color(1.0, 0.12, 0.06), 0.7, 3.5))
	var flare := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	flare.mesh = sm
	flare.material_override = _glow_mat(Color(1.0, 0.3, 0.2), 0.8, 4.0)
	add_child(flare)
	flare.position = from
	var hit := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.4
	hm.height = 0.8
	hit.mesh = hm
	hit.material_override = _glow_mat(Color(1.0, 0.55, 0.2), 0.85, 5.0)
	add_child(hit)
	hit.position = to
	var sparks: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 9:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		sparks.append(_bar(to, to + d * rng.randf_range(0.3, 0.7), 0.04, 0.04, _glow_mat(Color(1.0, 0.8, 0.3), 1.0, 5.0)))
	var scorch_m := StandardMaterial3D.new()
	scorch_m.albedo_color = Color(0.05, 0.03, 0.02, 0.75)
	scorch_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dir := (to - from)
	dir.y = 0.0
	var s_from := to - dir.normalized() * minf(3.0, dir.length())
	var scorch := _bar(Vector3(s_from.x, deck_y + 0.015, s_from.z), Vector3(to.x, deck_y + 0.015, to.z), 0.16, 0.01, scorch_m)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.2, 0.12)
	light.light_energy = 3.0
	light.omni_range = 4.0
	add_child(light)
	light.position = (from + to) * 0.5
	fx = {"core": core, "sheath": sheath, "flare": flare, "hit": hit, "sparks": sparks, "scorch": scorch, "light": light}


func _clear_fx() -> void:
	for k: String in fx:
		var v: Variant = fx[k]
		if v is Array:
			for n: Node in v:
				n.queue_free()
		elif v is Node:
			(v as Node).queue_free()
	fx = {}


# --------------------------------------------------------------------------- cases: stills

func _case_indoor() -> void:
	_room(9, FloorMaterials.F_POOL_TILE, FloorMaterials.W_CONCRETE)
	var rec := _pool(PoolGeo.LOOK_POOL, _variant(PoolGeo.variants(PoolGeo.LOOK_POOL), 7, 1), Vector2(0.0, 0.0))
	_finish("pool")
	var c: Vector2 = rec["center"]
	_shark("regular", rec, c + Vector2(-2.0, 0.6), Vector2(1, -0.4), 2.6)
	for x: float in [-3.0, 0.0, 3.0]:
		_put(DecorModels.build("pool_lounger"), Vector3(x + 1.5, 0, -5.2 + x * 0.5), yaw_to(Vector3(-0.3, 0, 1)))
	_put(DecorModels.build("neon_sign", {"text": "POOL", "color": Color(0.3, 0.95, 1.0), "dead": []}), Vector3(-3.0, 0.3, -13.2), 0.0)
	_put(PoolProps.build("hazard_sign"), Vector3(6.0, 0, -2.0), yaw_to(Vector3(-1, 0, 1)))
	_hero("wick", Vector3(c.x + 3.8, 0, c.y + 3.0), Vector3(-1, 0, -0.6))
	_hero("gasket", Vector3(c.x - 4.6, 0, c.y + 3.4), Vector3(1, 0, -0.5))
	_hero("rebar", Vector3(c.x + 5.6, 0, c.y - 1.2), Vector3(-1, 0, 0.2))
	_view("game", GAME_SIZE, Vector3(c.x, 0, c.y + 1.0))
	_view("close", 8.0, _shark_at(0))


func _case_moat() -> void:
	_room(10, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(PoolGeo.variants(PoolGeo.LOOK_MOAT), 42), Vector2.ZERO)
	_finish("moat")
	var mid := PoolGeo.channel(rec)
	_shark("regular", rec, mid[2].lerp(mid[3], 0.3), (mid[3] - mid[2]), 1.4)
	_put(DecorModels.build("moat_bridge"), _deck_out(rec, 4, 1.6), yaw_to(_edge_n3(rec, 4) * -1.0))
	_put(PoolProps.build("hazard_sign"), _deck_out(rec, 4, 1.4) + _edge_t3(rec, 4) * 1.6, yaw_to(_edge_n3(rec, 4)))
	_put(PropModels.build("villain_throne"), Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y), yaw_to(_edge_n3(rec, 4)))
	_hero("wick", _deck_out(rec, 4, 1.1) + _edge_t3(rec, 4) * -1.4, _edge_n3(rec, 4) * -1.0)
	_hero("rebar", _deck_out(rec, 5, 1.6), _edge_n3(rec, 5) * -1.0)
	_view("game", GAME_SIZE, Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y + 1.0))
	_view("close", 8.0, _shark_at(0))


func _case_shark_pool() -> void:
	_room(9, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(PoolGeo.variants(PoolGeo.MOAT_POOL), 7, 1), Vector2.ZERO)
	_finish("moat")
	var c: Vector2 = rec["center"]
	_shark("laser", rec, c + Vector2(1.5, -0.5), Vector2(-1, 0.2), 2.0)
	_put(PoolProps.build("hazard_sign"), Vector3(c.x + 5.4, 0, c.y - 3.2), yaw_to(Vector3(-1, 0, 1)))
	_put(PropModels.build("shark_tank"), Vector3(-6.0, 0, -9.6), 15.0)
	_hero("wick", Vector3(c.x + 3.6, 0, c.y + 3.6), Vector3(-1, 0, -1))
	_hero("gasket", Vector3(c.x - 5.0, 0, c.y + 2.6), Vector3(1, 0, -0.3))
	_view("game", GAME_SIZE, Vector3(c.x, 0, c.y + 1.0))
	_view("close", 8.0, _shark_at(0))


func _case_specimen() -> void:
	_room(9, FloorMaterials.F_LAB_TILE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_SPECIMEN, _variant(PoolGeo.variants(PoolGeo.LOOK_SPECIMEN), 3, 1), Vector2.ZERO)
	_finish("science")
	var c: Vector2 = rec["center"]
	var ax: Vector2 = rec["axis"]
	_shark("regular", rec, c - ax * 1.2, ax, 0.6)
	_put(DecorModels.build("neon_sign", {"text": "SCIENCE", "color": Color(0.72, 1.0, 0.22), "dead": []}), Vector3(-3.0, 0.3, -13.2), 0.0)
	_put(PoolProps.build("lab_bench"), Vector3(-5.5, 0, 3.0), yaw_to(Vector3(1, 0, -0.3)))
	_put(PropModels.build("specimen_vat"), Vector3(6.0, 0, -5.5), yaw_to(Vector3(-1, 0, 1)))
	_hero("wick", Vector3(c.x + 1.5, 0, c.y + 3.6), Vector3(-0.3, 0, -1))
	_view("game", GAME_SIZE, Vector3(c.x, 0, c.y + 1.0))
	_view("close", 8.0, _shark_at(0))


func _case_lagoon() -> void:
	_room(10, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(SharkMeasure.lagoon_variants(), 13, 1), Vector2.ZERO)
	_finish("moat")
	var c: Vector2 = rec["center"]
	var sim := _shark("imp", rec, c + Vector2(-2.0, 1.0), Vector2(1, -0.3), 3.0)
	_aim_shark(0, Vector3(c.x + 5.5, 0, c.y + 5.0), 0.6)
	_put(PropModels.build("doomsday_console"), Vector3(-7.5, 0, -8.0), 30.0)
	_put(PropModels.build("brazier"), Vector3(4.5, 0, 6.2), 0.0)
	_hero("wick", Vector3(c.x + 5.5, 0, c.y + 5.0), Vector3(-1, 0, -1))
	_hero("rebar", Vector3(c.x + 3.4, 0, c.y + 5.6), Vector3(-0.6, 0, -1))
	_view("game", GAME_SIZE, Vector3(c.x, 0, c.y + 1.0))
	_view("close", 8.0, _shark_at(0))
	sim.reverse_every = 0.0


func _case_throne() -> void:
	_room(11, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE, 4)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(PoolGeo.variants(PoolGeo.LOOK_MOAT), 54), Vector2(0.0, -1.0))
	_finish("throne_room")
	var c: Vector2 = rec["center"]
	var mid := PoolGeo.channel(rec)
	_shark("imp", rec, mid[3].lerp(mid[4], 0.6), mid[4] - mid[3], 0.6)
	var door := Hex.to_world(Hex.DIRS[4] * 11)
	_aim_shark(0, door + Vector3(0.6, 0, -1.6), 0.7)
	var m: Array = SharkModels.muzzle(sims[0][1])
	var dv: Vector3 = m[1]
	dv.y = 0.0
	var end := _beam_end(m[0], dv.normalized(), 22.0, [[door + Vector3(0.6, 0, -1.6), 0.4]])
	_aim_fx(m[0], Vector3(end.x, (m[0] as Vector3).y, end.z), _deck_y(rec), false)
	_put(PropModels.build("villain_throne"), Vector3(c.x, 0, c.y), yaw_to(Vector3(door.x - c.x, 0, door.z - c.y)))
	_put(DecorModels.build("red_carpet"), Vector3(c.x - 0.6, 0, c.y + 1.2), yaw_to(Vector3(door.x - c.x, 0, door.z - c.y)))
	for p: Vector3 in [Vector3(-3.6, 0, 6.6), Vector3(3.4, 0, 8.4), Vector3(-7.4, 0, 1.5)]:
		_put(PropModels.build("brazier"), p, 0.0)
	_put(DecorModels.build("neon_sign", {"text": "EVIL", "color": Color(1.0, 0.2, 0.15), "dead": [3]}), Vector3(4.0, 0.3, -15.0), 0.0)
	_hero("wick", door + Vector3(0.6, 0, -1.6), Vector3(0.4, 0, -1))
	_hero("gasket", Vector3(-2.6, 0, 7.8), Vector3(0.3, 0, -1))
	_hero("rebar", Vector3(-4.2, 0, 6.0), Vector3(0.5, 0, -1))
	_view("game", GAME_SIZE, Vector3(c.x, 0, c.y + 2.0))
	_view("close", 9.0, _shark_at(0))


func _case_twin() -> void:
	_room(10, FloorMaterials.F_POOL_TILE, FloorMaterials.W_CONCRETE)
	var v := _variant(PoolGeo.variants(PoolGeo.LOOK_POOL), 7, 1)
	# two trapezoids one ROW of deck apart (their rims 1.5 apart): pool B is pool A moved 6.0 straight across its long
	# axis (the lattice step (2, 2), at right angles to the axis DIRS[1])
	var anchor_a := Vector2i(-2, -2)
	var anchor_b: Vector2i = anchor_a + Vector2i(2, 2)
	PoolGeo._apply(map, "room:0", PoolGeo.LOOK_POOL, 0, v, anchor_a)
	PoolGeo._apply(map, "room:0", PoolGeo.LOOK_POOL, 0, v, anchor_b)
	_pool_recs.append_array(map.pools)
	_finish("pool")
	var ra: Dictionary = map.pools[0]
	var rb: Dictionary = map.pools[1]
	_shark("regular", ra, (ra["center"] as Vector2) + Vector2(-1.5, 0.3), Vector2(1, -0.5), 2.2)
	_shark("regular", rb, (rb["center"] as Vector2) + Vector2(1.5, 0.0), Vector2(-1, 0.4), 1.4)
	var mid := ((ra["center"] as Vector2) + (rb["center"] as Vector2)) * 0.5
	_hero("wick", Vector3(mid.x + 0.4, 0, mid.y), Vector3(1, 0, -0.55))
	_hero("rebar", Vector3(mid.x - 4.6, 0, mid.y + 2.6), Vector3(1, 0, -0.5))
	_view("game", GAME_SIZE, Vector3(mid.x, 0, mid.y + 0.5))
	_view("close", 9.0, Vector3(mid.x, 0, mid.y))


func _case_moat2() -> void:
	_room(11, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var list := SharkMeasure.ring_variants(2)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(list, 72), Vector2.ZERO)
	_finish("moat")
	var mid := PoolGeo.channel(rec)
	if mid.is_empty():
		for i in (rec["hole"] as Array).size():
			mid.append(((rec["outline"] as Array)[i] + (rec["hole"] as Array)[i]) * 0.5)
	_shark("regular", rec, mid[2].lerp(mid[3], 0.4), mid[3] - mid[2], 1.0)
	_put(PropModels.build("villain_throne"), Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y), 30.0)
	_hero("wick", _deck_out(rec, 4, 1.1), _edge_n3(rec, 4) * -1.0)
	_view("game", GAME_SIZE, Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y + 1.0))
	_view("close", 9.0, _shark_at(0))


func _case_variants() -> void:
	_room(10, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(SharkMeasure.lagoon_variants(), 16, 1), Vector2.ZERO)
	_finish("moat")
	var c: Vector2 = rec["center"]
	var ax: Vector2 = rec["axis"]
	var perp := Vector2(-ax.y, ax.x)
	var names: Array[String] = ["regular", "laser", "imp"]
	for i in 3:
		var at := c + ax * (float(i) - 1.0) * 3.2 + perp * 0.4
		_shark(names[i], rec, at, ax.rotated(-0.35), 0.0)
	var wick_at := c + ax * 7.2 + perp * 1.0
	_hero("wick", Vector3(wick_at.x, 0, wick_at.y), Vector3(-ax.x, 0, -ax.y))
	_view("game", GAME_SIZE, Vector3(c.x, 0, c.y + 1.0))
	_view("close", 10.0, Vector3(c.x, 0, c.y))
	for i in 3:
		var at := _shark_at(i)
		_view(names[i], 4.6, at + Vector3(0, 0.4, 0))
		_view("side_" + names[i], 4.2, at + Vector3(0, 0.45, 0), _side_yaw(i), -18.0)


## A camera yaw looking at shark i's flank (the side nearer the game camera), a little from the front.
func _side_yaw(i: int) -> float:
	var body := SharkModels.segments(sims[i][1])["body"] as Node3D
	var f := body.global_transform.basis.z
	var n := Vector3(f.z, 0, -f.x).normalized()
	if n.dot(Vector3(0.707, 0, 0.707)) < 0.0:
		n = -n
	n = (n + Vector3(f.x, 0, f.z).normalized() * 0.45).normalized()
	return rad_to_deg(atan2(n.x, n.z))


func _case_laser() -> void:
	_room(9, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(PoolGeo.variants(PoolGeo.MOAT_POOL), 7, 1), Vector2(-1.0, -2.0))
	_finish("moat")
	var c: Vector2 = rec["center"]
	_shark("imp", rec, c + Vector2(1.6, -0.2), Vector2(-1, 0.5), 1.6)
	var wick_at := Vector3(c.x + 5.0, 0, c.y + 7.0)
	var reb_at := Vector3(c.x - 3.0, 0, c.y + 6.5)
	_hero("wick", wick_at, Vector3(-0.6, 0, -1))
	_hero("rebar", reb_at, Vector3(0.4, 0, -1))
	_hero("gasket", Vector3(c.x - 6.2, 0, c.y + 2.4), Vector3(1, 0, -0.3))
	# cover between the pool and the crew: a priced console (billed when the beam hits it) and a crate stack
	var console_at := Vector3(c.x + 1.2, 0, c.y + 5.0)
	_put(PropModels.build("doomsday_console"), console_at, yaw_to(Vector3(0.2, 0, -1)))
	_put(DecorModels.build("crate_stack"), Vector3(c.x - 3.4, 0, c.y + 4.4), 10.0)
	var deck := _deck_y(rec)
	var self_ref := self
	var aim := func(locked: bool, fire: bool) -> void:
		self_ref._aim_shark(0, wick_at, 1.0 if locked else 0.6)
		var m: Array = SharkModels.muzzle(self_ref.sims[0][1])
		var from: Vector3 = m[0]
		var dirv: Vector3 = m[1]
		dirv.y = 0.0
		dirv = dirv.normalized()
		var to := self_ref._beam_end(from, dirv, 20.0, [[console_at, 0.8], [wick_at, 0.4]])
		if fire:
			self_ref._beam_fx(from, to, deck)
		else:
			self_ref._aim_fx(from, Vector3(to.x, from.y, to.z), deck, locked)
	_view("game", GAME_SIZE, Vector3(c.x + 1.0, 0, c.y + 3.0), GAME_YAW, GAME_PITCH, aim.bind(false, false))
	_view("aim", 12.0, Vector3(c.x + 2.0, 0, c.y + 3.0), GAME_YAW, GAME_PITCH, aim.bind(false, false))
	_view("lock", 12.0, Vector3(c.x + 2.0, 0, c.y + 3.0), GAME_YAW, GAME_PITCH, aim.bind(true, false))
	_view("fire", 12.0, Vector3(c.x + 2.0, 0, c.y + 3.0), GAME_YAW, GAME_PITCH, aim.bind(true, true))
	_view("fire_game", GAME_SIZE, Vector3(c.x + 1.0, 0, c.y + 3.0), GAME_YAW, GAME_PITCH, aim.bind(true, true))


## Swing shark i's emitter toward a world point (the imp aims; a riderless rig stays lashed forward) and set its charge.
func _aim_shark(i: int, at: Vector3, charge: float) -> void:
	var shark: Node3D = sims[i][1]
	var seg := SharkModels.segments(shark)
	var head := seg["head"] as Node3D
	var em := seg["emitter"] as Node3D
	if em == null:
		return
	var local := head.global_transform.affine_inverse() * at
	var yaw := rad_to_deg(atan2(local.x - SharkModels.EMITTER_AT.x, local.z - SharkModels.EMITTER_AT.z)) if seg["rider"] != null else 0.0
	SharkModels.aim(shark, clampf(yaw, -110.0, 110.0), charge)
	var rider := seg["rider"] as Node3D
	if rider != null:
		rider.rotation_degrees.y = 180.0 + clampf(yaw, -110.0, 110.0) * 0.6
		SharkModels.seat(rider.get_node("Imp"), charge)


func _shark_at(i: int) -> Vector3:
	var seg := SharkModels.segments(sims[i][1])
	return (seg["body"] as Node3D).global_position if (seg["body"] as Node3D).is_inside_tree() else (seg["body"] as Node3D).position


## A deck point `out` beyond the middle of outline edge i, and that edge's outward normal / tangent (3D).
func _deck_out(rec: Dictionary, i: int, out: float) -> Vector3:
	var ol: Array = rec["outline"]
	var a: Vector2 = ol[i % ol.size()]
	var b: Vector2 = ol[(i + 1) % ol.size()]
	var n: Vector2 = PoolGeo.edge_normals(ol)[i % ol.size()]
	var p := (a + b) * 0.5 + n * out
	return Vector3(p.x, float(rec["deck_level"]) * LH, p.y)


func _edge_n3(rec: Dictionary, i: int) -> Vector3:
	var n: Vector2 = PoolGeo.edge_normals(rec["outline"])[i % (rec["outline"] as Array).size()]
	return Vector3(n.x, 0, n.y)


func _edge_t3(rec: Dictionary, i: int) -> Vector3:
	var n := _edge_n3(rec, i)
	return Vector3(-n.z, 0, n.x)


# --------------------------------------------------------------------------- cases: animated (--write-movie)

func _case_swim_pool() -> void:
	_room(9, FloorMaterials.F_POOL_TILE, FloorMaterials.W_CONCRETE)
	var rec := _pool(PoolGeo.LOOK_POOL, _variant(PoolGeo.variants(PoolGeo.LOOK_POOL), 7, 1), Vector2.ZERO)
	_finish("pool")
	var c: Vector2 = rec["center"]
	var sim := _shark("regular", rec, c + Vector2(-2.2, 0.4), Vector2(1, -0.5), 0.5)
	sim.reverse_every = 1.6
	_hero("wick", Vector3(c.x + 3.8, 0, c.y + 3.0), Vector3(-1, 0, -0.6))
	_view("game", 13.0, Vector3(c.x, 0, c.y + 0.5))
	_script = func(_d: float) -> void: pass


func _case_swim_lagoon() -> void:
	_room(10, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(SharkMeasure.lagoon_variants(), 13, 1), Vector2.ZERO)
	_finish("moat")
	var c: Vector2 = rec["center"]
	var sim := _shark("laser", rec, c + Vector2(-2.5, 0.8), Vector2(1, -0.3), 0.5)
	sim.reverse_every = 1.8
	_view("game", 14.0, Vector3(c.x, 0, c.y + 0.5))
	_script = func(_d: float) -> void: pass


func _case_swim_moat() -> void:
	_room(10, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(PoolGeo.variants(PoolGeo.LOOK_MOAT), 34), Vector2.ZERO)
	_finish("moat")
	var mid := PoolGeo.channel(rec)
	var sim := _shark("regular", rec, mid[1].lerp(mid[2], 0.2), mid[2] - mid[1], 0.3)
	sim.reverse_every = 0.0
	_put(PropModels.build("villain_throne"), Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y), 30.0)
	_hero("wick", _deck_out(rec, 4, 1.1), _edge_n3(rec, 4) * -1.0)
	_view("game", 15.0, Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y + 0.5))
	_script = func(_d: float) -> void: pass


func _case_swim_moat2() -> void:
	_room(11, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(SharkMeasure.ring_variants(2), 54), Vector2.ZERO)
	_finish("moat")
	var mid := PackedVector2Array()
	for i in (rec["hole"] as Array).size():
		mid.append(((rec["outline"] as Array)[i] + (rec["hole"] as Array)[i]) * 0.5)
	var sim := _shark("regular", rec, mid[1].lerp(mid[2], 0.2), mid[2] - mid[1], 0.3)
	sim.reverse_every = 0.0
	_put(PropModels.build("villain_throne"), Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y), 30.0)
	_view("game", 17.0, Vector3((rec["center"] as Vector2).x, 0, (rec["center"] as Vector2).y + 0.5))
	_script = func(_d: float) -> void: pass


func _case_lunge() -> void:
	_room(9, FloorMaterials.F_POOL_TILE, FloorMaterials.W_CONCRETE)
	var rec := _pool(PoolGeo.LOOK_POOL, _variant(PoolGeo.variants(PoolGeo.LOOK_POOL), 7, 1), Vector2.ZERO)
	_finish("pool")
	var c: Vector2 = rec["center"]
	# Wick on the deck by the rim nearest the camera
	var edge := 0
	var best := -INF
	var normals := PoolGeo.edge_normals(rec["outline"])
	for i in normals.size():
		var s := normals[i].dot(Vector2(0.707, 0.707)) + (rec["outline"][i] as Vector2).distance_to(rec["outline"][(i + 1) % normals.size()]) * 0.05
		if s > best:
			best = s
			edge = i
	var wick_at := _deck_out(rec, edge, 0.75)
	var wick := _hero("wick", wick_at, _edge_n3(rec, edge) * -1.0)
	var sim := _shark("regular", rec, c + Vector2(-2.0, -0.6), Vector2(1, 0.2), 0.2)
	var started := [false]
	var hit_t := [-1.0]
	var self_ref := self
	_script = func(_d: float) -> void:
		if not started[0] and self_ref._t > 0.4:
			started[0] = true
			sim.hunt(Vector2(wick_at.x, wick_at.z))
		if sim.strikes > 0 and hit_t[0] < 0.0:
			hit_t[0] = self_ref._t
		if hit_t[0] > 0.0:
			var k := clampf((self_ref._t - hit_t[0]) / 0.25, 0.0, 1.0)
			wick.position = wick_at - _edge_n3(rec, edge) * 0.55 * sin(k * PI * 0.5)
	_view("game", 11.0, Vector3(c.x + 0.5, 0, c.y + 1.0))


func _case_laser_fire() -> void:
	_room(9, FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var rec := _pool(PoolGeo.LOOK_MOAT, _variant(SharkMeasure.lagoon_variants(), 13, 1), Vector2(-1.0, -2.0))
	_finish("moat")
	var c: Vector2 = rec["center"]
	var sim := _shark("imp", rec, c + Vector2(-2.0, 0.6), Vector2(1, -0.3), 0.4)
	var wick_at := Vector3(c.x + 5.0, 0, c.y + 7.2)
	var wick := _hero("wick", wick_at, Vector3(-0.6, 0, -1))
	var deck := _deck_y(rec)
	var self_ref := self
	var wick_path := func(t: float) -> Vector3:
		return wick_at + Vector3(-1.0, 0, 0.35) * clampf((t - 0.6) * 1.6, 0.0, 2.2)
	_script = func(_d: float) -> void:
		var t := self_ref._t
		var at: Vector3 = wick_path.call(minf(t, 2.4))
		wick.position = wick_path.call(t)
		if t < 1.0:
			self_ref._aim_shark(0, wick.position, 0.0)
			self_ref._clear_fx()
		elif t < 2.6:
			var locked := t >= 2.2
			var aim_pt: Vector3 = at if locked else wick.position
			sim.aim_at(Vector2(aim_pt.x, aim_pt.z))      # the imp steers the nose round; the swivel takes up the rest
			self_ref._aim_shark(0, aim_pt, clampf((t - 1.0) / 1.2, 0.0, 1.0))
			var m: Array = SharkModels.muzzle(self_ref.sims[0][1])
			var dv: Vector3 = m[1]
			dv.y = 0.0
			var to := self_ref._beam_end(m[0], dv.normalized(), 20.0, [])
			self_ref._aim_fx(m[0], Vector3(to.x, (m[0] as Vector3).y, to.z), deck, locked)
		elif t < 2.9:
			var m: Array = SharkModels.muzzle(self_ref.sims[0][1])
			var dv: Vector3 = m[1]
			dv.y = 0.0
			var to := self_ref._beam_end(m[0], dv.normalized(), 20.0, [])
			if not self_ref.fx.has("core"):
				self_ref._beam_fx(m[0], to, deck)
		else:
			self_ref._clear_fx()
			self_ref._aim_shark(0, wick.position, 0.0)
			if sim.mode == "aim":
				sim.release()
	sim.reverse_every = 0.0
	_view("game", 15.0, Vector3(c.x + 2.0, 0, c.y + 3.4))


# --------------------------------------------------------------------------- views

func _view(view_name: String, size: float, at: Vector3, yaw: float = GAME_YAW, pitch: float = GAME_PITCH, setup: Callable = Callable()) -> void:
	views[view_name] = {"size": size, "at": at, "yaw": yaw, "pitch": pitch, "setup": setup}
	view_order.append(view_name)


func _prepare(view_name: String) -> void:
	var v: Dictionary = views[view_name]
	if (v["setup"] as Callable).is_valid():
		(v["setup"] as Callable).call()
	var yaw := deg_to_rad(float(v["yaw"]))
	var pitch := deg_to_rad(float(v["pitch"]))
	camera.size = float(v["size"])
	var tgt: Vector3 = v["at"]
	camera.global_position = tgt + Vector3(sin(yaw) * cos(-pitch), sin(-pitch), cos(yaw) * cos(-pitch)) * 60.0
	camera.look_at(tgt, Vector3.UP)


func _run_shots() -> void:
	for i in 10:
		await get_tree().process_frame
	var base := shot_path.get_basename()
	var list: Array[String] = []
	if only_view == "":
		list.append_array(view_order)
	else:
		list.append(only_view)
	for v in list:
		_prepare(v)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var out := shot_path if only_view != "" else ("%s.png" % base if v == "game" else "%s_%s.png" % [base, v])
		var img := get_viewport().get_texture().get_image()
		print("shot ", out, " ", img.save_png(out), " ", img.get_size())
	get_tree().quit()

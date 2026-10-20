extends "res://scripts/art/lowpoly/sewer_lab.gd"
## Lava cave lab (docs/design/sewer-concept.md, "Lava caves"): a LAVA CAVE on the game's real hex-height terrain (HexMap
## heights, HexMapView, DungeonLook) with the crew for scale. Not pools: the cave's floor is a LAVA PLANE far below, and
## everything you walk on is raised hex ROCK: islands (clusters of columns, rough: neighbours differ by a level now and
## then), HEX BRIDGES (one hex wide, small random steps), and the cave's edge is a RIM of tall hex columns at varied
## heights (low on the camera side, tall at the back), not midpoint walls. LOOK-DEV ONLY: nothing here is used by the
## game, nothing declares gameplay state; DungeonGen, PoolGeo and the rest are untouched.
##
## The cave is several adjacent fog SPACES (user, 2026-10-20: "the fog in a big room can be managed with multiple adjacent
## rooms"): each island or chamber is a room ("room:N") and each bridge a hall ("corridor"), so RoomFog's doorways fall at
## the bridge ends (a doorway with no door), and the cave reveals itself a section at a time.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/lava_lab.tscn --case cave --shot <png> [--look magma|hellfire|obsidian]
##
## --case
##   cave    the overview: three rock chambers / islands and an islet joined by two hex bridges (A-B straight and rough;
##           B-C kinked, with a two-level climb, and a split to the islet), views: game (24), spaces (the fog spaces and
##           their doorways drawn on it), plan (34), bridge (9: the rough straight bridge), kink (9: the kinked one)
##   cross   the crew on the A-B bridge: Rebar shoves a skeleton off the side toward the lava, a lava salamander cruising
##           the open lava beside the bridge, two imps bathing by the islet; views game, close
##   fog     the room fog, look A: the crew on island A (in view), the bridge in view through its mouth, island B one hall
##           away ("next": an outline), the far chamber and the islet unknown; views game, close
## --look    magma (black basalt, orange lava under a dark crust), hellfire (hell-red rock and lava, violet ichor glints:
##           the hellgate rooms' colours), obsidian (mostly crusted over, glowing cracks only: dark, few lights)

const LAVA_BED := -5                     ## the lava cells' level: 4+ below any rock, so nobody WALKS off an edge
const LAVA_Y := -1.0                     ## the lava surface (2 levels under the shore rock)
const SKIRT_H := 0.75                    ## the glow lapping up the rock faces over the lava

const LAVA_LOOKS := {
	"magma": {
		"rock": Color(0.2, 0.18, 0.17), "rock_corr": Color(0.17, 0.15, 0.14), "rock_wall": Color(0.15, 0.13, 0.12),
		"crust": Color(0.09, 0.06, 0.05), "hot": Color(1.0, 0.36, 0.05), "core": Color(1.0, 0.82, 0.3), "glow": 2.4,
		"crust_k": 0.55, "lights": 10, "light": Color(1.0, 0.45, 0.15), "light_e": 1.6, "ambient": Color(0.6, 0.35, 0.25),
		"ambient_k": 0.45, "key": 0.45, "seam": 0.9, "down": Color(1.0, 0.6, 0.35), "down_k": 0.35, "ember": Color(1.0, 0.55, 0.15),
		"ring": Color(1.0, 0.6, 0.2),
	},
	"hellfire": {
		"rock": Color(0.26, 0.11, 0.1), "rock_corr": Color(0.22, 0.09, 0.08), "rock_wall": Color(0.19, 0.07, 0.07),
		"crust": Color(0.12, 0.02, 0.04), "hot": Color(1.0, 0.12, 0.08), "core": Color(1.0, 0.55, 0.25), "glow": 2.4,
		"crust_k": 0.45, "lights": 10, "light": Color(1.0, 0.2, 0.15), "light_e": 1.6, "ambient": Color(0.55, 0.25, 0.35),
		"ambient_k": 0.45, "key": 0.4, "seam": 1.0, "down": Color(0.85, 0.35, 0.9), "down_k": 0.3, "ember": Color(0.95, 0.4, 1.0),
		"ring": Color(1.0, 0.3, 0.2),
	},
	"obsidian": {
		"rock": Color(0.12, 0.12, 0.14), "rock_corr": Color(0.1, 0.1, 0.12), "rock_wall": Color(0.09, 0.09, 0.11),
		"crust": Color(0.05, 0.05, 0.06), "hot": Color(1.0, 0.4, 0.08), "core": Color(1.0, 0.75, 0.3), "glow": 2.8,
		"crust_k": 0.82, "lights": 4, "light": Color(1.0, 0.45, 0.15), "light_e": 1.4, "ambient": Color(0.45, 0.42, 0.5),
		"ambient_k": 0.5, "key": 0.55, "seam": 0.7, "down": Color(0.8, 0.75, 0.9), "down_k": 0.4, "ember": Color(1.0, 0.5, 0.15),
		"ring": Color(1.0, 0.55, 0.2),
	},
}

var lava := {}                 ## Vector2i -> true: lava cells
var rng := RandomNumberGenerator.new()
var spaces_named := {}         ## room / hall tag -> a readable name for the spaces view
var _labels: Array[Node3D] = []


func _looks() -> Dictionary:
	return LAVA_LOOKS


## (No water: a hero low on the rock gets no ripple.)
func _ripple(_pos: Vector3, _radius: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	return n


# --------------------------------------------------------------------------- the cave

## Distance from p to segment a-b (cell space, world X/Z).
static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Which side of the cave's spine p is on, seen from the game camera: > 0 on the camera's side (the near rim).
static func _spine_side(p: Vector2, spine: Array[Vector2]) -> float:
	var best := INF
	var q := p
	for i in spine.size() - 1:
		var a := spine[i]
		var ab := spine[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := a + ab * t
		if p.distance_to(c) < best:
			best = p.distance_to(c)
			q = c
	return (p - q).dot(Vector2(0.707, 0.707))


static func _v2(c: Vector2i) -> Vector2:
	var w := Hex.to_world(c)
	return Vector2(w.x, w.z)


## The cave: a lava floor inside a rough outline round the chambers, rock islands and hex bridges in it, a rim of tall hex
## columns round it all (low on the camera side, tall at the back). Every rock cell is rough: its level steps a little from
## its neighbours'. Returns the layout's key cells.
func _layout_cave() -> Dictionary:
	rng.seed = 20261020
	var a := Vector2i(-9, 6)
	var b := a + Hex.DIRS[1] * 12
	var c := b + Hex.DIRS[2] * 11 + Hex.DIRS[1] * 2
	var d := b + Hex.DIRS[2] * 4 + Hex.DIRS[0] * 5
	var spine: Array[Vector2] = [_v2(a + Hex.DIRS[4] * 2), _v2(a), _v2(b), _v2(c), _v2(c + Hex.DIRS[1] * 2)]
	var side: Array[Vector2] = [_v2(b + Hex.DIRS[2] * 4), _v2(d)]
	# the cave's floor: everything within ~6.5 units of the spine (and of the islet's branch), the outline roughened
	var region := {}
	for q in range(-30, 31):
		for r in range(-30, 31):
			var cc := Vector2i(q, r)
			var p := _v2(cc)
			var dist := INF
			for i in spine.size() - 1:
				dist = minf(dist, _seg_dist(p, spine[i], spine[i + 1]))
			dist = minf(dist, _seg_dist(p, side[0], side[1]) + 1.5)
			var wob := 1.2 * sin(p.x * 0.7 + p.y * 0.3) + 0.8 * sin(p.y * 0.9 - p.x * 0.4)
			if dist < 7.2 + wob:
				region[cc] = true
	for cc: Vector2i in region:
		_cells[cc] = "lava"
		lava[cc] = true
	# rock: the entry chamber A (room:0), island B (room:1, a crag in the middle), the far chamber C (room:2), the islet D
	var levels := {}
	_rock_blob(a, 3, "room:0", 0, levels, {a + Hex.DIRS[3] * 2: 2, a + Hex.DIRS[3] * 2 + Hex.DIRS[4]: 2})
	_rock_blob(a + Hex.DIRS[4] * 2 + Hex.DIRS[3], 2, "room:0", 0, levels, {})
	_rock_blob(b, 2, "room:1", 0, levels, {b: 3, b + Hex.DIRS[2]: 2, b + Hex.DIRS[3]: 2})
	_rock_blob(b + Hex.DIRS[5] + Hex.DIRS[4], 1, "room:1", 0, levels, {})
	_rock_blob(c, 3, "room:2", 1, levels, {c + Hex.DIRS[2] * 2: 3, c + Hex.DIRS[1] * 2: 3})
	_rock_blob(d, 1, "room:3", 0, levels, {})
	# bridge A-B: straight along DIRS[1], one hex wide, small random steps (never more than one between neighbours)
	var ab: Array[Vector2i] = []
	for i in range(4, 10):
		ab.append(a + Hex.DIRS[1] * i)
	_bridge(ab, 0, levels, [0, 1, 1, 0, -1, 0, 1])
	# bridge B-C: kinked (up DIRS[2], a jog along DIRS[1], up again), a two-level climb in the middle, and a split toward
	# the islet D off its first leg
	var bc: Array[Vector2i] = []
	var cur := b + Hex.DIRS[2] * 3
	for i in 3:
		bc.append(cur)
		cur += Hex.DIRS[2]
	cur += Hex.DIRS[1] * -1 + Hex.DIRS[1]
	for i in 2:
		bc.append(cur + Hex.DIRS[1] * i)
	cur = bc[bc.size() - 1] + Hex.DIRS[2]
	for i in 2:
		bc.append(cur + Hex.DIRS[2] * i)
	_bridge(bc, 0, levels, [1, 1, 0, 0, 2, 2, 1])
	var split: Array[Vector2i] = []
	var sp := bc[1] + Hex.DIRS[0]
	for i in 3:
		split.append(sp + Hex.DIRS[0] * i)
	_bridge(split, 0, levels, [1, 0, 0])
	for cc: Vector2i in levels:
		lava.erase(cc)
	# the rim: two rings of tall columns outside the cave; low (3-5) on the camera's side, tall (6-9) at the back
	var cam := Vector2(0.707, 0.707)
	for cc: Vector2i in region:
		for nb in Hex.neighbors(cc):
			for nb2 in [nb] + Hex.neighbors(nb):
				if region.has(nb2) or _cells.has(nb2) and str(_cells[nb2]) != "rim":
					continue
				var p := _v2(nb2)
				var front := _spine_side(p, spine) > 0.0
				var lv := 3 if front else rng.randi_range(6, 9)
				_cells[nb2] = "rim"
				levels[nb2] = maxi(int(levels.get(nb2, -99)), lv)
	_make_cave_map(levels)
	spaces_named = {"room:0": "A: entry chamber", "room:1": "B: island", "room:2": "C: far chamber", "room:3": "D: islet"}
	return {"a": a, "b": b, "c": c, "d": d, "ab": ab, "bc": bc, "split": split}


## A rough rock blob: `radius` cells round `center` at `base`, each cell stepping -1..+1 from base now and then (never a
## climb between neighbours), plus fixed crags (cell -> level).
func _rock_blob(center: Vector2i, radius: int, tag: String, base: int, levels: Dictionary, crags: Dictionary) -> void:
	for cc in Hex.range_cells(center, radius):
		var roll := rng.randf()
		var lv := base + (1 if roll > 0.66 else (-1 if roll < 0.2 and Hex.distance(cc, center) == radius else 0))
		levels[cc] = lv
		_cells[cc] = tag
	for cc: Vector2i in crags:
		levels[cc] = int(crags[cc])
		_cells[cc] = tag


## A hex bridge: one hex wide along `cells`, its levels base + steps (each neighbour within one level of the last, except
## where a step of two is asked for: a climb).
func _bridge(cells: Array[Vector2i], base: int, levels: Dictionary, steps: Array) -> void:
	for i in cells.size():
		levels[cells[i]] = base + int(steps[i % steps.size()])
		_cells[cells[i]] = "corridor"


func _make_cave_map(levels: Dictionary) -> void:
	map = HexMap.new()
	var rock := FloorMaterials.pack(FloorMaterials.F_FLAGSTONE, FloorMaterials.W_STONE)
	var bridge := FloorMaterials.pack(FloorMaterials.F_CORR_STONE, FloorMaterials.W_STONE)
	for cc: Vector2i in _cells:
		var tag := str(_cells[cc])
		var lv: int = LAVA_BED if lava.has(cc) else int(levels.get(cc, 0))
		var cell := map.set_cell(cc, lv)
		cell.tag = tag      # ("lava" and "rim" are neither rooms nor halls: they take the nearest space)
		cell.mat_id = bridge if tag == "corridor" else rock


# --------------------------------------------------------------------------- the look

func _finish_cave() -> void:
	GameWorld.begin(map, self, 1)
	terrain = HexMapView.new()
	terrain.seam_gain = float(look["seam"])
	add_child(terrain)
	terrain.build(map)
	_restyle_rock()
	DungeonLook.apply(self, map)
	_relight_cave()
	_build_lava()


func _restyle_rock() -> void:
	var mesh := terrain.mesh_instance.mesh as ArrayMesh
	var tables := FloorMaterials.table_arrays()
	var base: PackedVector4Array = (tables["base"] as PackedVector4Array).duplicate()
	var par: PackedVector4Array = (tables["par"] as PackedVector4Array).duplicate()
	for pair: Array in [[FloorMaterials.F_FLAGSTONE, "rock"], [FloorMaterials.F_CORR_STONE, "rock_corr"], [FloorMaterials.WALL_OFFSET + FloorMaterials.W_STONE, "rock_wall"]]:
		var col: Color = (look[pair[1]] as Color).srgb_to_linear()
		base[int(pair[0])] = Vector4(col.r, col.g, col.b, base[int(pair[0])].w)
		par[int(pair[0])] = Vector4(0.7, 0.25, 0.0, 0.0)
	# HexMapView draws raised cells in a room (and untagged ones) as wooden CRATES and every column side as slate: in the
	# cave they are rock, so those surfaces get the lab's rock textures (a top speckle, a banded side)
	var top_tex := _rock_tex(look["rock"], false)
	var side_tex := _rock_tex(look["rock_wall"], true)
	var crate_top := HexMapView.get_texture("crate_top")
	var crate_side := HexMapView.get_texture("crate_side")
	var cliff := HexMapView.get_texture("cliff_side")
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as ShaderMaterial
		if m == null:
			continue
		var nm := m.duplicate() as ShaderMaterial
		if m.get_shader_parameter("m_base") != null:
			nm.set_shader_parameter("m_base", base)
			nm.set_shader_parameter("m_par", par)
		var tex: Variant = m.get_shader_parameter("tex")
		if tex == crate_top:
			nm.set_shader_parameter("tex", top_tex)
		elif tex == crate_side or tex == cliff:
			nm.set_shader_parameter("tex", side_tex)
		mesh.surface_set_material(i, nm)


## A small seeded rock texture: speckled (a top) or in rough strata (a side), around `col`.
static func _rock_tex(col: Color, banded: bool) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 11 if banded else 7
	var bands: Array[float] = []
	for y in 64:
		bands.append(r.randf_range(0.75, 1.2) if y % 6 == 0 or bands.is_empty() else bands[y - 1])
	for y in 64:
		for x in 64:
			var k := r.randf_range(0.82, 1.15) * (bands[y] if banded else 1.0)
			if banded and y % 16 == 0:
				k *= 0.55
			img.set_pixel(x, y, Color(col.r * k * 1.6, col.g * k * 1.6, col.b * k * 1.6, 0.0))
	return ImageTexture.create_from_image(img)


func _relight_cave() -> void:
	for ch in get_children():
		if ch is WorldEnvironment:
			var env := (ch as WorldEnvironment).environment
			env.ambient_light_color = look["ambient"]
			env.ambient_light_energy = float(look["ambient_k"])
			env.background_color = Color(0.05, 0.025, 0.02)
		elif ch.name == "KeyLight":
			(ch as DirectionalLight3D).light_energy = float(look["key"])
			(ch as DirectionalLight3D).light_color = Color(1.0, 0.75, 0.6)
		elif ch.name == "Downlights":
			for l in ch.get_children():
				if l is OmniLight3D:
					(l as OmniLight3D).light_color = look["down"]
					(l as OmniLight3D).light_energy *= float(look["down_k"])


## Crusted lava: dark plates (a cellular pattern) drifting slowly, the glow in the cracks between them and in hot patches,
## HDR emission so it blooms.
const LAVA_SHADER := """
shader_type spatial;
render_mode cull_disabled, unshaded;
uniform vec4 crust : source_color;
uniform vec4 hot : source_color;
uniform vec4 core : source_color;
uniform float glow = 3.0;
uniform float crust_k = 0.55;
varying vec3 wp;
vec2 h22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h22(i).x, b = h22(i + vec2(1, 0)).x, c = h22(i + vec2(0, 1)).x, d = h22(i + vec2(1, 1)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = TIME * 0.05 + 2.0;
	vec2 p = wp.xz * 1.5 + vec2(t, t * 0.6) + vec2(vn(wp.xz * 0.4) * 1.5);
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h22(i + g);
			float dd = length(g + o - f);
			if (dd < f1) { f2 = f1; f1 = dd; } else if (dd < f2) { f2 = dd; }
		}
	}
	float crack = 1.0 - smoothstep(0.02, 0.12, f2 - f1);
	float heat = smoothstep(crust_k - 0.25, crust_k + 0.25, vn(wp.xz * 0.35 + vec2(3.0, t)));
	float hotness = max(crack, heat * 0.32);
	vec3 plate = crust.rgb * (0.7 + 0.6 * vn(p * 3.0));
	vec3 glowc = mix(hot.rgb, core.rgb, smoothstep(0.6, 1.0, hotness) * heat);
	ALBEDO = plate * (1.0 - hotness) + glowc * glow * hotness;


}
"""


## The lava (a hex per lava cell at LAVA_Y), the glow lapping up every rock face over it, embers, and the lights the lava
## throws (LAVA "lights": farthest-point picks over the lava cells, a warm OmniLight each).
func _build_lava() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hot: Color = look["hot"]
	for cc: Vector2i in lava:
		var w := Hex.to_world(cc)
		var ctr := Vector3(w.x, LAVA_Y, w.z)
		for i in 6:
			var p0 := ctr + Hex.corner(i)
			var p1 := ctr + Hex.corner((i + 1) % 6)
			st.set_normal(Vector3.UP)
			st.add_vertex(ctr)
			st.add_vertex(p1)
			st.add_vertex(p0)
		for dd in 6:
			var nb: Vector2i = cc + Hex.DIRS[dd]
			if lava.has(nb) or not map.has_cell(nb):
				continue
			if float(map.cells[nb].level) * LH <= LAVA_Y:
				continue
			var e0 := ctr + Hex.kite_corner(posmod(dd - 1, 6))
			var e1 := ctr + Hex.kite_corner(dd)
			var inn := (Hex.to_world(Vector2i.ZERO) - Hex.to_world(Hex.DIRS[dd])).normalized() * 0.03
			var top := minf(LAVA_Y + SKIRT_H, float(map.cells[nb].level) * LH)
			var c0 := Color(hot.r, hot.g, hot.b, 0.9)
			var c1 := Color(hot.r, hot.g, hot.b, 0.0)
			_quad(skirt, e0 + inn, e1 + inn, Vector3(e1.x, top, e1.z) + inn, Vector3(e0.x, top, e0.z) + inn, [c0, c0, c1, c1])
	var mi := MeshInstance3D.new()
	mi.name = "Lava"
	mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = LAVA_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("crust", look["crust"])
	m.set_shader_parameter("hot", look["hot"])
	m.set_shader_parameter("core", look["core"])
	m.set_shader_parameter("glow", float(look["glow"]))
	m.set_shader_parameter("crust_k", float(look["crust_k"]))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var smi := MeshInstance3D.new()
	smi.name = "Skirt"
	smi.mesh = skirt.commit()
	smi.material_override = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)
	# lights over the lava: farthest-point picks, so they spread
	var cells: Array[Vector2i] = []
	for cc: Vector2i in lava:
		cells.append(cc)
	cells.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return x.x < y.x or (x.x == y.x and x.y < y.y))
	var picks: Array[Vector2i] = [cells[cells.size() / 2]]
	while picks.size() < int(look["lights"]):
		var best := cells[0]
		var best_d := -1
		for cc in cells:
			var dmin := 1 << 20
			for pk in picks:
				dmin = mini(dmin, Hex.distance(cc, pk))
			if dmin > best_d:
				best_d = dmin
				best = cc
		picks.append(best)
	for pk in picks:
		var l := OmniLight3D.new()
		l.light_color = look["light"]
		l.light_energy = float(look["light_e"])
		l.omni_range = 7.5
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		add_child(l)
		l.position = Hex.to_world(pk) + Vector3(0, LAVA_Y + 2.2, 0)
	# embers: little glowing chips drifting up over the lava (seeded)
	var es := LowPoly.Soup.new(5, 0.0)
	var erng := RandomNumberGenerator.new()
	erng.seed = 77
	for i in 110:
		var cc: Vector2i = cells[erng.randi_range(0, cells.size() - 1)]
		var p := Hex.to_world(cc) + Vector3(erng.randf_range(-0.8, 0.8), LAVA_Y + erng.randf_range(0.3, 3.2), erng.randf_range(-0.8, 0.8))
		PropModels.box(es, Vector3.ONE * erng.randf_range(0.03, 0.06), p, PropModels.glow(look["ember"]), Vector3(erng.randf() * 90.0, erng.randf() * 90.0, 0))
	var emi := MeshInstance3D.new()
	emi.mesh = es.to_mesh()
	var em := MonsterMaterial.make(0.0)
	em.set_shader_parameter("glow_gain", 2.5)
	emi.material_override = em
	emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emi)


## A glowing ring on the lava (a creature's wake, a hero's splash), flat at the surface.
func _lava_ring(pos: Vector3, radius: float) -> Node3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius
	tm.outer_radius = radius + 0.09
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = look["ring"]
	m.emission_enabled = true
	m.emission = look["ring"]
	m.emission_energy_multiplier = 3.0
	mi.material_override = m
	add_child(mi)
	mi.position = Vector3(pos.x, LAVA_Y + 0.02, pos.z)
	mi.scale = Vector3(1, 0.2, 1)
	_contents.append(mi)
	return mi


## A rock cell's top (world point at its centre).
func _top(cc: Vector2i, off: Vector3 = Vector3.ZERO) -> Vector3:
	return Hex.to_world(cc, float(map.cells[cc].level)) + off


func _salamander(pos: Vector3, yaw: float, bend: float, jaw: float = 0.0) -> Node3D:
	var s := SewerProps.build("salamander", {"bend": bend, "jaw": jaw})
	_put(s, Vector3(pos.x, LAVA_Y - 0.26, pos.z), yaw)
	s.scale = Vector3.ONE * 1.3
	var fwd := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
	_lava_ring(pos + fwd * 1.0, 0.3)
	_lava_ring(pos - fwd * 0.3, 0.6)
	_contents.append(s)
	return s


## The fog spaces drawn on the cave: a line along every hex edge between two spaces, each space's name over it, a ring on
## each doorway (bridge end: a doorway with no door).
func _draw_spaces() -> void:
	fog = RoomFog.build(map)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.3, 1.0, 1.0)
	lm.no_depth_test = true
	lm.render_priority = 10
	var soup := SurfaceTool.new()
	soup.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cen := {}
	for cc: Vector2i in map.cells:
		var s := fog.space_of_cell(cc)
		if s < 0:
			continue
		if not cen.has(s):
			cen[s] = [Vector3.ZERO, 0]
		if not lava.has(cc) and map.cells[cc].tag != "":
			cen[s][0] += Hex.to_world(cc)
			cen[s][1] = int(cen[s][1]) + 1
		for dd in 3:
			var nb: Vector2i = cc + Hex.DIRS[dd]
			if not map.has_cell(nb):
				continue
			var s2 := fog.space_of_cell(nb)
			if s2 < 0 or s2 == s:
				continue
			var y := maxf(_surf_y(cc), _surf_y(nb)) + 0.06
			var w := Hex.to_world(cc)
			var e0 := w + Hex.kite_corner(posmod(dd - 1, 6))
			var e1 := w + Hex.kite_corner(dd)
			var t := (e1 - e0).normalized()
			var n := Vector3(-t.z, 0, t.x) * 0.05
			_quad(soup, Vector3(e0.x, y, e0.z) - n, Vector3(e1.x, y, e1.z) - n, Vector3(e1.x, y, e1.z) + n, Vector3(e0.x, y, e0.z) + n, [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	var mi := MeshInstance3D.new()
	mi.mesh = soup.commit()
	mi.material_override = lm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_labels.append(mi)
	for s: int in cen:
		if int(cen[s][1]) == 0:
			continue
		var tag: String = fog.tags[s]
		var lbl := Label3D.new()
		lbl.text = "%s\n%s" % [tag, spaces_named.get(tag, "bridge (a hall)" if tag.begins_with("hall") else "")]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.font_size = 56
		lbl.outline_size = 14
		lbl.pixel_size = 0.012
		lbl.modulate = Color(0.75, 1.0, 1.0)
		lbl.render_priority = 11
		add_child(lbl)
		lbl.position = (cen[s][0] as Vector3) / float(cen[s][1]) + Vector3(0, 2.6, 0)
		_labels.append(lbl)
	for dw: Dictionary in fog.doorways:
		var mid: Vector3 = dw["mid"]
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55
		tm.outer_radius = 0.7
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1.0, 0.95, 0.3)
		rm.no_depth_test = true
		rm.render_priority = 10
		ring.material_override = rm
		add_child(ring)
		var mc := Hex.from_world(mid)
		ring.position = Vector3(mid.x, (_surf_y(mc) if map.has_cell(mc) else 0.0) + 0.1, mid.z)
		ring.scale = Vector3(1, 0.3, 1)
		_labels.append(ring)
	print("cave spaces: ", fog.tags, " doorways: ", fog.doorways.size())


func _surf_y(cc: Vector2i) -> float:
	return LAVA_Y if lava.has(cc) else float(map.cells[cc].level) * LH


func _show_labels(on: bool) -> void:
	for n in _labels:
		n.visible = on


# --------------------------------------------------------------------------- cases

func _case_cave() -> void:
	var L := _layout_cave()
	_finish_cave()
	_draw_spaces()
	var a: Vector2i = L["a"]
	var b: Vector2i = L["b"]
	var c: Vector2i = L["c"]
	var ab: Array = L["ab"]
	var bc: Array = L["bc"]
	_hero("wick", _top(ab[3]), Hex.dir_vector(1))
	_hero("gasket", _top(a + Hex.DIRS[1] * 2), Hex.dir_vector(1))
	_hero("rebar", _top(b + Hex.DIRS[2]), Hex.dir_vector(2))
	_salamander(Hex.to_world(b + Hex.DIRS[5] * 4 + Hex.DIRS[1]), yaw_to(Hex.dir_vector(2)), 35.0)
	var mid := (Hex.to_world(a) + Hex.to_world(c)) * 0.5
	var self_ref := self
	var labels_off := func() -> void: self_ref._show_labels(false)
	var labels_on := func() -> void: self_ref._show_labels(true)
	_view("game", GAME_SIZE, Hex.to_world(b) + Vector3(-1.5, 0, 1.5), GAME_YAW, GAME_PITCH, labels_off)
	_view("spaces", GAME_SIZE, Hex.to_world(b) + Vector3(-1.5, 0, 1.5), GAME_YAW, GAME_PITCH, labels_on)
	_view("plan", 34.0, mid + Vector3(0, 0, 1.5), GAME_YAW, GAME_PITCH, labels_on)
	_view("bridge", CLOSE_SIZE, _top(ab[3]), GAME_YAW, GAME_PITCH, labels_off)
	_view("kink", CLOSE_SIZE, _top(bc[3]), GAME_YAW, GAME_PITCH, labels_off)


## The crew on the A-B bridge: Wick halfway over, Gasket at A's end; at B's end Rebar has just punched a skeleton off the
## side, which tips over the edge toward the lava; a salamander cruises the open lava beside the bridge, imps bathe by the
## islet.
func _case_cross() -> void:
	var L := _layout_cave()
	_finish_cave()
	var a: Vector2i = L["a"]
	var b: Vector2i = L["b"]
	var d: Vector2i = L["d"]
	var ab: Array = L["ab"]
	var ax := Hex.dir_vector(1)
	_hero("gasket", _top(ab[0]), ax)
	_hero("wick", _top(ab[2]), ax)
	var reb_at := _top(ab[4])
	_hero("rebar", reb_at, Hex.dir_vector(5))
	# the shove: the skeleton tipping off the bridge's near side (DIRS[0] side), over the lava
	var off := Hex.dir_vector(5)
	var grunt := MonsterModels.make("grunt")
	add_child(grunt)
	var gp := reb_at + off * 2.1 + Vector3(0, -0.85, 0)
	grunt.position = gp
	grunt.rotation_degrees = Vector3(0, yaw_to(-off) + 180.0, 0)
	grunt.rotate_object_local(Vector3.RIGHT, deg_to_rad(62.0))
	_contents.append(grunt)
	# speed lines from Rebar's fist
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.95, 0.85, 0.8)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 3:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 1.1)
		bar.mesh = bm
		bar.material_override = lm
		add_child(bar)
		var p := reb_at + off * 1.0 + Vector3(0, 0.5 + 0.3 * float(i), 0) + ax * (float(i) - 1.0) * 0.3
		bar.look_at_from_position(p, p + off, Vector3.UP)
	_lava_ring(Vector3(gp.x, 0, gp.z) + off * 0.5, 0.4)
	_salamander(Hex.to_world(ab[1] + Hex.DIRS[5] * 3), yaw_to(ax) + 15.0, -30.0, 0.6)
	for i in 2:
		var imp := MonsterModels.make("swarmer")
		add_child(imp)
		imp.position = Hex.to_world(d + Hex.DIRS[5] * 2 + Hex.DIRS[0] * i) + Vector3(0.2 * float(i), LAVA_Y - 0.25, 0)
		imp.rotation_degrees.y = 200.0 + 50.0 * float(i)
		_lava_ring(imp.position, 0.35)
		_contents.append(imp)
	_view("game", GAME_SIZE, Hex.to_world(ab[3]) + Vector3(0, 0, 1.5))
	_view("close", CLOSE_SIZE, reb_at + off * 0.6 + Vector3(-0.5, 0, 0))


## Room fog, look A: the crew back on island A; the A-B bridge is seen through its mouth (in view), island B is one hall
## away (next: an outline), the far chamber C, the islet D and the B-C bridge are unknown (not drawn).
func _case_fog() -> void:
	var L := _layout_cave()
	_finish_cave()
	var a: Vector2i = L["a"]
	var b: Vector2i = L["b"]
	var ab: Array = L["ab"]
	_hero("wick", _top(a + Hex.DIRS[4] * 2 + Hex.DIRS[3]), Hex.dir_vector(1))
	_hero("gasket", _top(a + Hex.DIRS[4] * 2 + Hex.DIRS[3] * 2), Hex.dir_vector(1))
	_hero("rebar", _top(a + Hex.DIRS[4] * 3 + Hex.DIRS[3]), Hex.dir_vector(1))
	_salamander(Hex.to_world(b + Hex.DIRS[5] * 4 + Hex.DIRS[1]), yaw_to(Hex.dir_vector(2)), 35.0)
	_salamander(Hex.to_world(ab[2] + Hex.DIRS[5] * 3), yaw_to(-Hex.dir_vector(1)), -30.0)
	fog = RoomFog.build(map)
	fog_view = FogView.new()
	fog_view.name = "Fog"
	add_child(fog_view)
	fog_view.setup(map, fog, camera)
	fog_view.viewers = crew_at.duplicate()
	var self_ref := self
	var apply_fog := func() -> void:
		self_ref.fog_view.refresh_now(true)
		for n: Node3D in self_ref._contents:
			n.visible = self_ref.fog.shows_contents(n.global_position)
		print("fog states: ", self_ref.fog.tags, " ", self_ref.fog.state)
	var on_b := func() -> void:
		self_ref.fog_view.viewers = [self_ref._top(b + Hex.DIRS[4]), self_ref._top(b + Hex.DIRS[5])]
		self_ref.fog_view.refresh_now(true)
		for n: Node3D in self_ref._contents:
			n.visible = self_ref.fog.shows_contents(n.global_position)
		print("fog states (on B): ", self_ref.fog.tags, " ", self_ref.fog.state)
	_view("game", GAME_SIZE, Hex.to_world(ab[3]) + Vector3(-2.0, 0, 1.0), GAME_YAW, GAME_PITCH, apply_fog)
	_view("close", CLOSE_SIZE * 1.5, Hex.to_world(ab[1]), GAME_YAW, GAME_PITCH, apply_fog)
	_view("on_b", GAME_SIZE, Hex.to_world(b) + Vector3(-1.5, 0, 1.5), GAME_YAW, GAME_PITCH, on_b)

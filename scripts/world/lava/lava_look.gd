class_name LavaLook
extends RefCounted
## The lava cave's look (prototype, docs/design/lava-playtest.md): the "magma" look the user liked in the lava lab.
## Cosmetic only: built on every machine from the map, no state, its own seeded generators (never GameWorld.rng).
##   - the rock: HexMapView's materials recoloured to dark basalt, and the wooden CRATE texture it gives raised cells
##     (and every cliff side) swapped for rock textures;
##   - the LAVA: a hex per lava cell at LavaCave.LAVA_Y, unshaded, a dark crust over glowing cracks (HDR: it blooms);
##   - a glow SKIRT lapping up every rock face over the lava, EMBERS rising, and warm LIGHTS over the lava (farthest-point
##     picks), with DungeonLook's downlights dimmed to a warm glow.
##
##   LavaLook.dress(parent, map, terrain)       # after HexMapView.build and DungeonLook.apply, before the lava turns void

const LIGHTS := 10
const SKIRT_H := 0.75
const ROCK := Color(0.2, 0.18, 0.17)
const ROCK_CORR := Color(0.17, 0.15, 0.14)
const ROCK_WALL := Color(0.15, 0.13, 0.12)
const RIM_TOP := Color(0.07, 0.06, 0.06)
const CRUST := Color(0.09, 0.06, 0.05)
const HOT := Color(1.0, 0.36, 0.05)
const CORE := Color(1.0, 0.82, 0.3)
const GLOW := 2.4
const CRUST_K := 0.55
const LIGHT := Color(1.0, 0.45, 0.15)
const LIGHT_E := 1.6
const EMBER := Color(1.0, 0.55, 0.15)

## Crusted lava: dark plates (a cellular pattern) drifting slowly, the glow in the cracks between them and in slow hot
## patches. Unshaded and HDR. `flicker` (0..1) brightens and breaks the cracks (a damp crust about to give way).
const LAVA_SHADER := """
shader_type spatial;
render_mode cull_disabled, unshaded;
uniform vec4 crust : source_color;
uniform vec4 hot : source_color;
uniform vec4 core : source_color;
uniform float glow = 2.4;
uniform float crust_k = 0.55;
uniform float heat_k = 0.32;
uniform float flicker = 0.0;
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
	float width = 0.12 + 0.25 * flicker * (0.6 + 0.4 * sin(TIME * 22.0));
	float crack = 1.0 - smoothstep(0.02, width, f2 - f1);
	float heat = smoothstep(crust_k - 0.25, crust_k + 0.25, vn(wp.xz * 0.35 + vec2(3.0, t)));
	float hotness = max(crack, heat * heat_k);
	vec3 plate = crust.rgb * (0.7 + 0.6 * vn(p * 3.0));
	vec3 glowc = mix(hot.rgb, core.rgb, smoothstep(0.6, 1.0, hotness) * heat);
	ALBEDO = plate * (1.0 - hotness) + glowc * glow * hotness;
}
"""

## Damp CRUST: lava cooled to dark rock (playtest 2026-10-20: "showing the crust as not glowing would read better").
## Grey-black plates, faint darker cracks, lit like rock. `flicker` (0..1, the last seconds before it melts) brings the glow
## back into the cracks, pulsing, until it gives way.
const CRUST_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 rock : source_color = vec4(0.27, 0.26, 0.25, 1.0);
uniform vec4 hot : source_color;
uniform vec4 core : source_color;
uniform float flicker = 0.0;
varying vec3 wp;
vec2 h22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz * 1.5;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = h22(i + g);
			float dd = length(g + o - f);
			if (dd < f1) { f2 = f1; f1 = dd; id = i + g; } else if (dd < f2) { f2 = dd; }
		}
	}
	float width = 0.05 + 0.12 * flicker;
	float crack = 1.0 - smoothstep(0.015, width, f2 - f1);
	vec3 plate = rock.rgb * (0.75 + 0.5 * h22(id).x);
	float pulse = flicker * (0.55 + 0.45 * sin(TIME * 18.0));
	vec3 glowc = mix(hot.rgb, core.rgb, 0.4);
	ALBEDO = mix(plate, plate * 0.35, crack * (1.0 - flicker));
	EMISSION = glowc * crack * pulse * 3.0;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
"""

static var _shader: Shader
static var _crust_shader: Shader


static func crust_material() -> ShaderMaterial:
	if _crust_shader == null:
		_crust_shader = Shader.new()
		_crust_shader.code = CRUST_SHADER
	var m := ShaderMaterial.new()
	m.shader = _crust_shader
	m.set_shader_parameter("hot", HOT)
	m.set_shader_parameter("core", CORE)
	return m


static func lava_material(crust_k: float = CRUST_K, heat_k: float = 0.32) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = LAVA_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("crust", CRUST)
	m.set_shader_parameter("hot", HOT)
	m.set_shader_parameter("core", CORE)
	m.set_shader_parameter("glow", GLOW)
	m.set_shader_parameter("crust_k", crust_k)
	m.set_shader_parameter("heat_k", heat_k)
	return m


## Everything: the rock restyle, the relight, the lava, its skirt, embers and lights. Returns the node holding the lava.
static func dress(parent: Node3D, map: HexMap, terrain: HexMapView) -> Node3D:
	restyle(terrain)
	relight(parent)
	var holder := Node3D.new()
	holder.name = "Lava"
	parent.add_child(holder)
	var cells := LavaCave.lava_cells(map)
	_build_lava(holder, map, cells)
	_build_embers(holder, cells)
	_build_lights(holder, cells)
	return holder


## HexMapView's materials in the cave's colours: flagstone (rock), corridor stone (bridges) and rough stone blocks (the
## rim's wall faces) recoloured; the crate textures (raised and untagged cells) and the slate cliff texture swapped for
## a speckled rock top and a banded rock side.
static func restyle(terrain: HexMapView) -> void:
	var mesh := terrain.mesh_instance.mesh as ArrayMesh
	var tables := FloorMaterials.table_arrays()
	var base: PackedVector4Array = (tables["base"] as PackedVector4Array).duplicate()
	var par: PackedVector4Array = (tables["par"] as PackedVector4Array).duplicate()
	# (the rim's tops use the carpet row, for its dim seams: near black, so the cave's wall never reads as floor)
	for pair: Array in [[FloorMaterials.F_FLAGSTONE, ROCK], [FloorMaterials.F_CORR_STONE, ROCK_CORR], [FloorMaterials.WALL_OFFSET + FloorMaterials.W_STONE, ROCK_WALL],
			[FloorMaterials.F_CARPET, RIM_TOP]]:
		var col: Color = (pair[1] as Color).srgb_to_linear()
		base[int(pair[0])] = Vector4(col.r, col.g, col.b, base[int(pair[0])].w)
		par[int(pair[0])] = Vector4(0.7, 0.25, 0.0, 0.0)
	var top_tex := rock_tex(ROCK, false)
	var side_tex := rock_tex(ROCK_WALL, true)
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


## A small seeded rock texture: speckled (a top) or in rough strata (a side), around `col`. Alpha 0 (no glow).
static func rock_tex(col: Color, banded: bool) -> ImageTexture:
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


## DungeonLook's lighting warmed and dimmed for a cave lit by its lava.
static func relight(parent: Node3D) -> void:
	for ch in parent.get_children():
		if ch is WorldEnvironment:
			var env := (ch as WorldEnvironment).environment
			env.ambient_light_color = Color(0.6, 0.35, 0.25)
			env.ambient_light_energy = 0.45
			env.background_color = Color(0.05, 0.025, 0.02)
		elif ch.name == "KeyLight":
			(ch as DirectionalLight3D).light_energy = 0.45
			(ch as DirectionalLight3D).light_color = Color(1.0, 0.75, 0.6)
		elif ch.name == "Downlights":
			for l in ch.get_children():
				if l is OmniLight3D:
					(l as OmniLight3D).light_color = Color(1.0, 0.6, 0.35)
					(l as OmniLight3D).light_energy *= 0.35


static func _build_lava(holder: Node3D, map: HexMap, cells: Array[Vector2i]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lava_set := {}
	for c in cells:
		lava_set[c] = true
	for c in cells:
		var w := Hex.to_world(c)
		var ctr := Vector3(w.x, LavaCave.LAVA_Y, w.z)
		for i in 6:
			st.set_normal(Vector3.UP)
			st.add_vertex(ctr)
			st.add_vertex(ctr + Hex.corner((i + 1) % 6))
			st.add_vertex(ctr + Hex.corner(i))
		for d in 6:
			var nb: Vector2i = c + Hex.DIRS[d]
			if lava_set.has(nb) or not map.has_cell(nb):
				continue
			var top := minf(LavaCave.LAVA_Y + SKIRT_H, float(map.cells[nb].level) * Hex.LEVEL_HEIGHT)
			if top <= LavaCave.LAVA_Y:
				continue
			var e0 := ctr + Hex.kite_corner(posmod(d - 1, 6))
			var e1 := ctr + Hex.kite_corner(d)
			var inn := -Hex.dir_vector(d) * 0.03
			var c0 := Color(HOT.r, HOT.g, HOT.b, 0.9)
			var c1 := Color(HOT.r, HOT.g, HOT.b, 0.0)
			for v: Array in [[e0 + inn, c0], [e1 + inn, c0], [Vector3(e1.x, top, e1.z) + inn, c1],
					[e0 + inn, c0], [Vector3(e1.x, top, e1.z) + inn, c1], [Vector3(e0.x, top, e0.z) + inn, c1]]:
				skirt.set_color(v[1])
				skirt.set_normal(Vector3.UP)
				skirt.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "LavaSurface"
	mi.mesh = st.commit()
	mi.material_override = lava_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
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
	holder.add_child(smi)


static func _build_embers(holder: Node3D, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var es := LowPoly.Soup.new(5, 0.0)
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in mini(160, cells.size()):
		var c: Vector2i = cells[r.randi_range(0, cells.size() - 1)]
		var p := Hex.to_world(c) + Vector3(r.randf_range(-0.8, 0.8), LavaCave.LAVA_Y + r.randf_range(0.3, 3.2), r.randf_range(-0.8, 0.8))
		PropModels.box(es, Vector3.ONE * r.randf_range(0.03, 0.06), p, PropModels.glow(EMBER), Vector3(r.randf() * 90.0, r.randf() * 90.0, 0))
	var mi := MeshInstance3D.new()
	mi.name = "Embers"
	mi.mesh = es.to_mesh()
	var m := MonsterMaterial.make(0.0)
	m.set_shader_parameter("glow_gain", 2.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)


## Warm unshadowed omnis over the lava, spread by farthest-point picks (LIGHTS of them).
static func _build_lights(holder: Node3D, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	var picks: Array[Vector2i] = [cells[cells.size() / 2]]
	while picks.size() < mini(LIGHTS, cells.size()):
		var best := cells[0]
		var best_d := -1
		for c in cells:
			var dmin := 1 << 20
			for pk in picks:
				dmin = mini(dmin, Hex.distance(c, pk))
			if dmin > best_d:
				best_d = dmin
				best = c
		picks.append(best)
	for pk in picks:
		var l := OmniLight3D.new()
		l.light_color = LIGHT
		l.light_energy = LIGHT_E
		l.omni_range = 7.5
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		holder.add_child(l)
		l.position = Hex.to_world(pk) + Vector3(0, LavaCave.LAVA_Y + 2.2, 0)

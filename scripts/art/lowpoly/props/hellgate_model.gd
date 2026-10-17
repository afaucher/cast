class_name HellgateModel
extends Node3D
## The look of a hellgate: a demonic portal set into the hex floor, in the same faceted world as the
## heroes and monsters.
##
##   - a ring of jagged OBSIDIAN SHARDS (dark violet-black facets, ink outline, amber rim) leaning out
##     of a low obsidian lip, tall at the back (away from the iso camera) and short at the front so the
##     core stays readable. Cracks and veins in them glow red-orange: the ENEMY glow language
##     (MonsterMaterial: faces with vertex alpha 0.5 are emissive).
##   - a swirling dark-red / violet CORE disc (banded spiral, hot rim, black eye), a faint faceted
##     VORTEX cone above it, a GROUND GLOW ring, floating magma chunks, rising EMBERS and a red light.
##   - the ORIGIN gate is the same design at double size with more shards, more cracks and a slow
##     heartbeat pulse.
##
## Driven by the Hellgate through: set_active(), set_flare(0..1, the burst telegraph), pulse(), set_hurt(),
## set_phase(), telegraph_shove(), play_close(). Time comes from the model's own _process (or freeze_at()
## for the lab). No GPU-only features beyond ordinary shaders and CPUParticles3D, so it builds headless.

const R := 1.3                       ## design radius of the shard ring (world units at scale 1)
const ORIGIN_SCALE := 2.0
## The iso camera sits towards +X +Z; shards on the opposite side are tall, those facing it short.
const FRONT := Vector3(0.7071, 0.0, 0.7071)

const STONE := Color(0.15, 0.105, 0.19)
const STONE_LIGHT := Color(0.27, 0.19, 0.33)
const STONE_DARK := Color(0.08, 0.055, 0.115)
const LAVA := Color(1.0, 0.40, 0.09)
const LAVA_HOT := Color(1.0, 0.72, 0.22)
const CRACK := Color(1.0, 0.22, 0.07)
const MAGMA := Color(0.95, 0.26, 0.07)
const ORANGE := Color(1.0, 0.42, 0.10)
const VIOLET := Color(0.62, 0.12, 0.95)

const CORE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform float t = 0.0;
uniform float flare = 0.0;            // telegraph / pulse: the core flares hot
uniform float heat = 1.0;
uniform float close_k = 0.0;          // 0..1 collapse: shrinks to a point, spins up
uniform vec3 deep : source_color = vec3(0.03, 0.0, 0.07);
uniform vec3 violet : source_color = vec3(0.52, 0.07, 0.85);
uniform vec3 red : source_color = vec3(1.0, 0.07, 0.04);
uniform vec3 hot : source_color = vec3(1.0, 0.50, 0.12);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p) / max(1.0 - close_k * 0.94, 0.05);
	float a = atan(p.y, p.x);
	float spin = t * (1.5 + close_k * 7.0);
	float arms = 0.5 + 0.5 * sin(a * 3.0 + r * 6.0 - spin);
	arms = floor(arms * 3.0 + 0.5) / 3.0;
	float arms2 = 0.5 + 0.5 * sin(a * 2.0 - r * 3.5 + spin * 0.6);
	arms2 = floor(arms2 * 2.0 + 0.5) / 2.0;
	vec3 col = mix(deep, violet, arms * (0.2 + 0.8 * smoothstep(0.05, 0.75, r)));
	col = mix(col, red, smoothstep(0.42, 0.92, r) * (0.35 + 0.65 * arms2));
	float lip = smoothstep(0.78, 0.9, r) * (1.0 - smoothstep(0.93, 1.0, r));
	col += hot * lip * 1.4;
	float eye = 1.0 - smoothstep(0.0, 0.26, r);
	col = mix(col, deep * 0.35, eye * 0.9);
	float spark = 1.0 - smoothstep(0.0, 0.07, r);
	col += violet * spark * 2.2;
	float k = heat * (1.0 + flare * 1.6);
	vec3 e = col * 1.55 * k + hot * flare * 0.5 * (1.0 - eye);
	ALBEDO = e;
	ALPHA = 1.0 - smoothstep(0.93, 1.0, length(p));
}
"""

const VORTEX_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

uniform float t = 0.0;
uniform float amount = 1.0;
uniform vec3 tint : source_color = vec3(0.85, 0.18, 0.55);

void fragment() {
	float v = UV.y;                      // 0 at the base, 1 at the top (this mesh's UV runs that way)
	float fade = pow(1.0 - v, 1.4) * smoothstep(0.0, 0.05, 1.0 - v);
	float s = 0.5 + 0.5 * sin(UV.x * 6.2831 * 5.0 + v * 9.0 - t * 2.6);
	s = floor(s * 3.0) / 3.0;
	float a = clamp(fade * (0.25 + 0.75 * s) * amount, 0.0, 0.5);
	ALBEDO = tint * a * 0.9;             // never above the bloom threshold on its own
	ALPHA = 1.0;
}
"""

const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float t = 0.0;
uniform float strength = 1.0;
uniform float flare = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.18, 0.05);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.22, 0.42, r) * (1.0 - smoothstep(0.42, 1.0, r));
	ring = floor(ring * 4.0 + 0.5) / 4.0;
	float a = ring * (0.5 + 0.45 * flare) * strength;
	ALBEDO = tint * a * (1.3 + flare);
	ALPHA = 1.0;
}
"""

const WARN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float k = 0.0;                // 0..1 how far the telegraph has grown
uniform float alpha = 1.0;
uniform vec3 tint : source_color = vec3(1.0, 0.2, 0.06);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = smoothstep(k - 0.14, k - 0.015, r) * (1.0 - smoothstep(k - 0.015, k, r));
	float fill = (1.0 - smoothstep(k - 0.02, k, r)) * 0.07;
	float a = (edge * 1.5 + fill) * alpha;
	ALBEDO = tint * a * 2.0;
	ALPHA = 1.0;
}
"""

static var _core_shader: Shader
static var _vortex_shader: Shader
static var _glow_shader: Shader
static var _warn_shader: Shader

var origin := false
var ui_height := 3.0
var shard_count := 0

var _t := 0.0
var _frozen := false
var _active := false
var _active_k := 0.7
var _flare := 0.0
var _pulse := 0.0
var _hurt := 0.0
var _phase := 0
var _closing := false
var _close_t := 0.0
var _close_dur := 1.4
var _close_k := 0.0
var _close_fx_done := false
var _shove_t := -1.0
var _shove_dur := 0.9
var _shove_radius := 5.5

var _mat: ShaderMaterial
var _core_mat: ShaderMaterial
var _vortex_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
var _warn_mat: ShaderMaterial
var _body: Node3D
var _shards: Array[Dictionary] = []      ## {node, yaw, lean, h}
var _orbiters: Array[Dictionary] = []    ## {node, ang, speed, rad, y, bob}
var _core: MeshInstance3D
var _vortex: MeshInstance3D
var _glow: MeshInstance3D
var _warn: MeshInstance3D
var _lip: MeshInstance3D
var _cracks: MeshInstance3D
var _embers: CPUParticles3D
var _light: OmniLight3D


static func make(is_origin: bool = false) -> HellgateModel:
	var m := HellgateModel.new()
	m.origin = is_origin
	m._build()
	return m


# ------------------------------------------------------------------ public hooks

## The gate woke up (dormant gates burn lower).
func set_active(on: bool) -> void:
	_active = on


## Burst telegraph, 0..1 (hold it every frame; 0 = calm).
func set_flare(k: float) -> void:
	_flare = clampf(k, 0.0, 1.0)


## A one-shot flash that decays (a burst landed, a hit, a phase change).
func pulse(strength: float = 1.0) -> void:
	_pulse = maxf(_pulse, strength)


## 0 (fresh) .. 1 (nearly closed): the cracks run hotter as it weakens.
func set_hurt(k: float) -> void:
	_hurt = clampf(k, 0.0, 1.0)


## Origin gate phase 0..2: burns hotter in each.
func set_phase(p: int) -> void:
	_phase = clampi(p, 0, 2)
	pulse(2.0)


## The defensive shove is winding up: a red ring grows to `radius` over `seconds`.
func telegraph_shove(seconds: float, radius: float) -> void:
	_shove_t = 0.0
	_shove_dur = maxf(seconds, 0.05)
	_shove_radius = radius
	_warn.visible = true
	var s := radius * 2.0 / scale.x
	_warn.scale = Vector3(s, 1.0, s)


func is_closing() -> bool:
	return _closing


## True once the collapse animation has finished.
func is_closed_done() -> bool:
	return _closing and _close_t >= _close_dur


## The collapse: shards fold inward, the core spins up and shrinks to a point, a flash, then nothing.
func play_close(seconds: float = 1.4) -> void:
	if _closing:
		return
	_closing = true
	_close_t = 0.0
	_close_dur = maxf(seconds, 0.1)
	_shove_t = -1.0
	_warn.visible = false


## Lab / screenshots: freeze animation time at `seconds`, optionally holding a collapse fraction k.
func freeze_at(seconds: float, close_fraction: float = 0.0) -> void:
	_frozen = true
	_t = seconds
	if close_fraction > 0.0:
		_closing = true
		_close_dur = 1.4
		_close_t = close_fraction * _close_dur
		_close_fx_done = true
	_embers.speed_scale = 1.0
	_animate(0.0)


func triangle_count() -> int:
	var n := 0
	for mi in _meshes():
		var arrays := mi.mesh.surface_get_arrays(0)
		n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for s in _shards:
		out.append((s["node"] as Node3D).get_child(0) as MeshInstance3D)
	out.append(_lip)
	out.append(_cracks)
	return out


# ------------------------------------------------------------------ build

func _build() -> void:
	name = "OriginGateModel" if origin else "HellgateModel"
	if origin:
		scale = Vector3.ONE * ORIGIN_SCALE
	_mat = MonsterMaterial.make(2.6 if origin else 2.3)
	_mat.set_shader_parameter("glow_gain", 1.7)
	_mat.set_shader_parameter("tint_color", ORANGE)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_build_lip()
	_build_cracks()
	_build_shards()
	_build_core()
	_build_vortex()
	_build_ground_glow()
	_build_warn()
	_build_orbiters()
	_build_embers()
	_light = OmniLight3D.new()
	_light.name = "GateLight"
	_light.light_color = Color(1.0, 0.30, 0.12)
	_light.light_energy = 2.2
	_light.omni_range = 6.5
	_light.position = Vector3(0, 0.9, 0)
	_light.shadow_enabled = false
	add_child(_light)
	ui_height = 2.7 if not origin else 2.6    # in model space: multiplied by the scale below
	ui_height *= scale.x
	_animate(0.0)


func _soup(seed_value: int, vary: float = 0.08) -> LowPoly.Soup:
	return LowPoly.Soup.new(seed_value, vary)


func _mesh_node(node_name: String, soup: LowPoly.Soup, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = soup.to_mesh(0.28)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _polar(a: float, r: float, y: float = 0.0) -> Vector3:
	return Vector3(cos(a) * r, y, sin(a) * r)


## The low obsidian lip the shards stand on: a jagged ring slab with a glowing lava channel inside.
func _build_lip() -> void:
	var s := _soup(11, 0.07)
	var n := 16 if origin else 12
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var r_in := 0.86 * R
	var r_mid := 0.95 * R
	var r_out := 1.16 * R
	var r_foot := 1.34 * R
	var ys: Array[float] = []
	var rots: Array[float] = []
	for i in n:
		ys.append(rng.randf_range(0.13, 0.24))
		rots.append(rng.randf_range(-0.05, 0.05))
	for i in n:
		var j := (i + 1) % n
		var a0 := TAU * float(i) / n + rots[i]
		var a1 := TAU * float(j) / n + (rots[j] if j != 0 else rots[0]) + (TAU if j == 0 else 0.0)
		var y0 := ys[i]
		var y1 := ys[j]
		var col := STONE if i % 2 == 0 else STONE_LIGHT
		# glowing channel (slightly sunk)
		s.add_quad(_polar(a0, r_in, 0.09), _polar(a0, r_mid, 0.09), _polar(a1, r_mid, 0.09), _polar(a1, r_in, 0.09), MonsterModel.glow(LAVA))
		# raised stone top
		s.add_quad(_polar(a0, r_mid, y0), _polar(a0, r_out, y0 - 0.02), _polar(a1, r_out, y1 - 0.02), _polar(a1, r_mid, y1), col)
		# inner wall of the stone, facing the channel
		s.add_quad(_polar(a0, r_mid, y0), _polar(a1, r_mid, y1), _polar(a1, r_mid, 0.09), _polar(a0, r_mid, 0.09), STONE_DARK)
		# outer slope down to the floor
		s.add_quad(_polar(a0, r_out, y0 - 0.02), _polar(a0, r_foot, 0.0), _polar(a1, r_foot, 0.0), _polar(a1, r_out, y1 - 0.02), STONE_DARK)
	_lip = _mesh_node("Lip", s, _body)


## Glowing zigzag cracks running out across the floor from the lip.
func _build_cracks() -> void:
	var s := _soup(21, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 313
	var n := 13 if origin else 8
	for k in n:
		var a := TAU * float(k) / n + rng.randf_range(-0.2, 0.2)
		var p := _polar(a, 1.30 * R, 0.032)
		var segs := rng.randi_range(2, 4)
		var total := rng.randf_range(0.55, 1.0) * (1.2 if origin else 1.0)
		var wid := rng.randf_range(0.13, 0.18)
		for i in segs:
			a += rng.randf_range(-0.55, 0.55)
			var step := total / segs * rng.randf_range(0.7, 1.3)
			var q := p + Vector3(cos(a), 0.0, sin(a)) * step
			_crack_bar(s, p, q, wid, 100 + k * 7 + i)
			p = q
			wid *= 0.66
			# a short fork
			if i == 0 and rng.randf() < 0.75:
				var fa := a + (1.0 if rng.randf() < 0.5 else -1.0)
				_crack_bar(s, p, p + Vector3(cos(fa), 0.0, sin(fa)) * step * 0.8, wid * 0.8, 200 + k)
	_cracks = _mesh_node("Cracks", s, _body)


func _crack_bar(s: LowPoly.Soup, p: Vector3, q: Vector3, wid: float, seed_value: int) -> void:
	var d := q - p
	var l := d.length()
	if l < 0.01:
		return
	var yaw := rad_to_deg(atan2(d.x, d.z))
	var bar := LowPoly.box(Vector3(wid, 0.03, l * 1.12), MonsterModel.glow(CRACK), seed_value, 0.0, 1, 0.0)
	s.merge(bar, LowPoly.at((p + q) * 0.5, Vector3(0.0, yaw, 0.0)))


## The ring of jagged obsidian shards: tall behind, short in front, plus outer fangs.
func _build_shards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 if origin else 1717
	var n_main := 14 if origin else 9
	for i in n_main:
		var a := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / n_main
		var d := Vector3(cos(a), 0.0, sin(a))
		var back := 0.5 * (1.0 - d.dot(FRONT))
		var h := lerpf(0.62, 2.35, pow(back, 1.2)) * rng.randf_range(0.82, 1.15)
		var w := rng.randf_range(0.19, 0.27) * lerpf(1.0, 1.35, back)
		_add_shard(a, R * rng.randf_range(1.02, 1.1), h, w, rng.randf_range(0.14, 0.34), 300 + i, true)
	# outer fangs: short, splayed, a second row
	var n_fang := 12 if origin else 7
	for i in n_fang:
		var a := TAU * (float(i) + 0.5 + rng.randf_range(-0.3, 0.3)) / n_fang
		var d := Vector3(cos(a), 0.0, sin(a))
		var back := 0.5 * (1.0 - d.dot(FRONT))
		var h := lerpf(0.32, 0.95, back) * rng.randf_range(0.8, 1.2)
		_add_shard(a, R * rng.randf_range(1.38, 1.5), h, rng.randf_range(0.13, 0.18), rng.randf_range(0.45, 0.75), 500 + i, false)
	if origin:
		# a few great horns at the back
		for i in 4:
			var a := atan2(-FRONT.z, -FRONT.x) + (float(i) - 1.5) * 0.5
			_add_shard(a, R * 1.2, rng.randf_range(2.9, 3.5), rng.randf_range(0.28, 0.36), rng.randf_range(0.10, 0.2), 700 + i, true)
	shard_count = _shards.size()


func _add_shard(a: float, rr: float, h: float, w: float, lean: float, seed_value: int, veined: bool) -> void:
	var s := _soup(seed_value, 0.1)
	var body := LowPoly.cylinder(w, w * 0.05, h, 5, STONE if seed_value % 2 == 0 else STONE_LIGHT, seed_value, 0.045, 3, 0.18)
	s.merge(body, LowPoly.at(Vector3(0.0, h * 0.5, 0.0)))
	if veined:
		# glowing veins on the inner (-X) and, for some, outer face
		MonsterModel.limb(s, Vector3(-w * 1.0, 0.04, 0.0), Vector3(-w * 0.32, h * 0.74, 0.0), w * 0.2, w * 0.035, 3, MonsterModel.glow(LAVA), seed_value + 1)
		if seed_value % 3 == 0:
			MonsterModel.limb(s, Vector3(w * 0.7, 0.04, w * 0.5), Vector3(w * 0.22, h * 0.5, w * 0.12), w * 0.16, w * 0.03, 3, MonsterModel.glow(LAVA_HOT), seed_value + 2)
	var pivot := Node3D.new()
	pivot.name = "Shard%d" % _shards.size()
	pivot.position = _polar(a, rr, -0.04)
	_body.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = s.to_mesh(0.28)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(mi)
	var shard := {"node": pivot, "yaw": -a, "lean": lean, "h": h, "base_y": pivot.position.y}
	_shards.append(shard)
	pivot.basis = _shard_basis(-a, lean)


static func _shard_basis(yaw: float, lean: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), -lean)


func _build_core() -> void:
	if _core_shader == null:
		_core_shader = Shader.new()
		_core_shader.code = CORE_SHADER
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = _core_shader
	_core_mat.render_priority = -1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 18
	var rad := 0.95 * R
	for i in n:
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		for pt: Array in [[Vector2.ZERO, 0.0], [Vector2(cos(a1), sin(a1)), 1.0], [Vector2(cos(a0), sin(a0)), 1.0]]:
			var v: Vector2 = pt[0]
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5, 0.5) + v * 0.5)
			st.add_vertex(Vector3(v.x * rad, 0.0, v.y * rad))
	_core = MeshInstance3D.new()
	_core.name = "Core"
	_core.mesh = st.commit()
	_core.material_override = _core_mat
	_core.position.y = 0.075
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.set_meta("no_flash", true)
	_body.add_child(_core)


func _build_vortex() -> void:
	if _vortex_shader == null:
		_vortex_shader = Shader.new()
		_vortex_shader.code = VORTEX_SHADER
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = _vortex_shader
	var cone := CylinderMesh.new()
	cone.top_radius = 0.28 * R
	cone.bottom_radius = 0.82 * R
	cone.height = 2.5
	cone.radial_segments = 8
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	_vortex = MeshInstance3D.new()
	_vortex.name = "Vortex"
	_vortex.mesh = cone
	_vortex.material_override = _vortex_mat
	_vortex.position.y = 0.1 + cone.height * 0.5
	_vortex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortex.set_meta("no_flash", true)
	_body.add_child(_vortex)


func _build_ground_glow() -> void:
	if _glow_shader == null:
		_glow_shader = Shader.new()
		_glow_shader.code = GLOW_SHADER
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = _glow_shader
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * R * 2.0 * 2.3
	_glow = MeshInstance3D.new()
	_glow.name = "GroundGlow"
	_glow.mesh = plane
	_glow.material_override = _glow_mat
	_glow.position.y = 0.045
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.set_meta("no_flash", true)
	_body.add_child(_glow)


func _build_warn() -> void:
	if _warn_shader == null:
		_warn_shader = Shader.new()
		_warn_shader.code = WARN_SHADER
	_warn_mat = ShaderMaterial.new()
	_warn_mat.shader = _warn_shader
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	_warn = MeshInstance3D.new()
	_warn.name = "ShoveWarning"
	_warn.mesh = plane
	_warn.material_override = _warn_mat
	_warn.position.y = 0.06
	_warn.visible = false
	_warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warn.set_meta("no_flash", true)
	add_child(_warn)


## Floating chunks above the core: magma lumps and obsidian splinters, slowly orbiting.
func _build_orbiters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var n := 8 if origin else 5
	# Their own material: the chunks glow steadily, they do not flare with the gate (no white-out).
	var orb_mat := MonsterMaterial.make(2.0)
	orb_mat.set_shader_parameter("glow_gain", 1.5)
	for i in n:
		var magma := i % 2 == 0
		var col := MonsterModel.glow(MAGMA) if magma else STONE_LIGHT
		var s := LowPoly.boulder(Vector3(0.11, 0.15, 0.11) * rng.randf_range(0.8, 1.3), 0, 0.25, col, 60 + i, 0.12)
		var holder := Node3D.new()
		holder.name = "Orbiter%d" % i
		_body.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = s.to_mesh(0.28)
		mi.material_override = orb_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		_orbiters.append({"node": holder, "ang": TAU * float(i) / n, "speed": rng.randf_range(0.35, 0.7) * (1.0 if i % 2 == 0 else -1.0),
				"rad": rng.randf_range(0.28, 0.55) * R, "y": rng.randf_range(0.8, 1.7), "bob": rng.randf() * TAU})


func _build_embers() -> void:
	_embers = CPUParticles3D.new()
	_embers.name = "Embers"
	_embers.amount = 56 if origin else 26
	_embers.lifetime = 2.6
	_embers.preprocess = 2.6
	_embers.local_coords = false
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 0.75 * R
	_embers.direction = Vector3.UP
	_embers.spread = 24.0
	_embers.initial_velocity_min = 0.7 * (1.0 if not origin else 1.5)
	_embers.initial_velocity_max = 1.6 * (1.0 if not origin else 1.6)
	_embers.gravity = Vector3(0, 0.25, 0)
	_embers.damping_min = 0.2
	_embers.damping_max = 0.5
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.85, 0.35, 1.0), Color(1.0, 0.45, 0.1, 1.0), Color(0.8, 0.12, 0.08, 0.7), Color(0.4, 0.04, 0.1, 0.0)])
	_embers.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.25))
	_embers.scale_amount_curve = curve
	_embers.scale_amount_min = 0.7
	_embers.scale_amount_max = 1.3
	var sm := SphereMesh.new()
	sm.radius = 0.065
	sm.height = 0.13
	sm.radial_segments = 4
	sm.rings = 2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(2.2, 1.5, 0.8, 1.0)
	sm.material = m
	_embers.mesh = sm
	_embers.position.y = 0.25
	_embers.emitting = true
	_embers.set_meta("no_flash", true)
	add_child(_embers)


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	if _frozen:
		return
	_t += delta
	_animate(delta)


func _animate(delta: float) -> void:
	var beat_rate := 1.7 if origin else 2.6
	var beat := 0.5 + 0.5 * sin(_t * beat_rate)
	_pulse = maxf(0.0, _pulse - delta * 1.4)
	_active_k = move_toward(_active_k, 1.0 if _active else 0.72, delta * 1.5)
	var phase_heat := 0.18 * float(_phase)
	var heat := _active_k + phase_heat + 0.12 * beat * (1.5 if origin else 1.0) + _hurt * 0.25
	var flare := clampf(_flare + _pulse * 0.6, 0.0, 2.0)

	# closing: a normalised fraction drives everything
	_close_k = 0.0
	if _closing:
		if not _frozen:
			_close_t += delta
		_close_k = clampf(_close_t / _close_dur, 0.0, 1.0)
		var burst_at := 0.38
		if not _close_fx_done and _close_k >= burst_at:
			_close_fx_done = true
			_close_burst()
		flare = maxf(flare, 2.2 * sin(clampf(_close_k / 0.55, 0.0, 1.0) * PI))
		heat *= 1.0 - smoothstep(0.55, 1.0, _close_k)

	# materials
	var gain := 1.7 + 0.55 * beat * (1.0 if origin else 0.5) + _hurt * 0.9 + phase_heat * 2.0 + flare * 2.4
	_mat.set_shader_parameter("glow_gain", gain * (1.0 - 0.9 * smoothstep(0.7, 1.0, _close_k)))
	_mat.set_shader_parameter("tint_k", clampf(0.22 * flare, 0.0, 0.5))
	_core_mat.set_shader_parameter("t", _t)
	_core_mat.set_shader_parameter("flare", flare)
	_core_mat.set_shader_parameter("heat", heat)
	_core_mat.set_shader_parameter("close_k", _close_k)
	var open := 1.0 - smoothstep(0.35, 0.9, _close_k)
	_vortex_mat.set_shader_parameter("t", _t)
	_vortex_mat.set_shader_parameter("amount", (0.8 + 0.6 * flare) * _active_k * open)
	_vortex.scale = Vector3(open, open, open) if _closing else Vector3.ONE
	_glow_mat.set_shader_parameter("t", _t)
	_glow_mat.set_shader_parameter("flare", flare)
	_glow_mat.set_shader_parameter("strength", (0.75 + 0.35 * beat) * _active_k * (1.0 - smoothstep(0.5, 1.0, _close_k)))
	var l_scale := 1.0 if not origin else 1.6
	_light.light_energy = (1.5 + 1.3 * flare + 0.6 * beat) * _active_k * l_scale * (1.0 - smoothstep(0.6, 1.0, _close_k))
	_light.omni_range = 6.5 * (1.0 + 0.2 * flare)
	_embers.speed_scale = 1.0 + _phase * 0.35 + flare * 0.5

	# shove warning ring
	if _shove_t >= 0.0:
		if not _frozen:
			_shove_t += delta
		var k := clampf(_shove_t / _shove_dur, 0.0, 1.0)
		_warn_mat.set_shader_parameter("k", 0.04 + 0.96 * k)
		_warn_mat.set_shader_parameter("alpha", 0.5 + 0.5 * sin(_t * 30.0) * 0.5 + 0.2)
		if k >= 1.0:
			_shove_t = -1.0
			_warn.visible = false

	# shards: breathe a little; fold inward and sink when closing
	var ease_k := _close_k * _close_k
	for i in _shards.size():
		var sh: Dictionary = _shards[i]
		var node: Node3D = sh["node"]
		var lean: float = sh["lean"]
		var h: float = sh["h"]
		var base_y: float = sh["base_y"]
		var wob := 0.012 * sin(_t * 1.3 + float(i) * 1.7)
		if _closing:
			var lag := float(i % 5) * 0.04
			var kk := clampf((_close_k - lag) / (1.0 - 0.2), 0.0, 1.0)
			node.basis = _shard_basis(sh["yaw"], lerpf(lean, -0.7, kk * kk))
			node.position.y = base_y - h * 0.8 * kk * kk
			var sc := 1.0 - smoothstep(0.7, 1.0, kk)
			node.scale = Vector3.ONE * maxf(sc, 0.001)
		else:
			node.basis = _shard_basis(sh["yaw"], lean + wob)
	_lip.scale = Vector3.ONE * (1.0 - 0.6 * smoothstep(0.6, 1.0, ease_k * 1.2)) if _closing else Vector3.ONE
	_cracks.visible = not (_closing and _close_k > 0.8)

	# orbiters
	for o in _orbiters:
		var node: Node3D = o["node"]
		o["ang"] = float(o["ang"]) + float(o["speed"]) * delta
		var rad: float = o["rad"] * (1.0 - 0.9 * _close_k)
		var y: float = float(o["y"]) + 0.12 * sin(_t * 1.6 + float(o["bob"]))
		y = lerpf(y, 0.2, _close_k)
		node.position = _polar(float(o["ang"]), rad, y)
		node.rotation = Vector3(_t * 0.8 + float(o["bob"]), _t * 1.1, 0.0)
		node.scale = Vector3.ONE * maxf(1.0 - smoothstep(0.5, 0.9, _close_k), 0.001)

	if _closing and _close_k >= 1.0:
		_core.visible = false
		_vortex.visible = false
		_glow.visible = false
		_embers.emitting = false
	else:
		_core.visible = true
		_vortex.visible = true
		_glow.visible = true


func _close_burst() -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree() or not is_inside_tree():
		return
	var hot: Array[Color] = [Color(1.0, 0.9, 0.5), Color(1.0, 0.4, 0.1), Color(0.65, 0.12, 0.7)]
	Fx.burst(global_position + Vector3.UP * 0.4, hot, 44 if origin else 28, 6.0 * scale.x, 0.1, 0.9, 5.0, Vector3.UP, 80.0)
	var dust: Array[Color] = [Color(0.3, 0.2, 0.3), Color(0.15, 0.1, 0.18)]
	Fx.burst(global_position + Vector3.UP * 0.2, dust, 18, 3.0 * scale.x, 0.2, 1.0, -0.5, Vector3.UP, 85.0, false)
	Fx.ring(global_position, R * 1.9 * scale.x, Color(1.0, 0.45, 0.15, 0.9), 0.7, 0.0, true, 0.25)

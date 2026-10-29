class_name EctoplasmLook
extends RefCounted
## LOOK-DEV ONLY (docs/design/ectoplasm-look.md): what ECTOPLASM could look like, the haunting's infestation layer
## (new-themes.md "Ghost house", Other enemies: "like goo: it slicks or slows the floor, and Damp washes it away"). Nothing
## in the game, the contracts or the network uses it: only the gym's "ecto: <variant>" spawns and the look lab
## (ectoplasm_look_lab.gd). No HP, no slow, no collision: plain cosmetic nodes.
##
## It is built to read differently from today's goo (GooSoups: an opaque, lumpy, glowing chartreuse sheet with an ink
## outline): ectoplasm is SEE-THROUGH (the floor shows through it), SMOOTH and GLASSY (a flat sheet with a bright meniscus
## edge and a wet specular sheen, no lumps), COOL (it takes the ghosts' colour, GhostLook.colour: pale blue or ecto green),
## it has NO INK OUTLINE, its inside SWIRLS slowly (bright filaments drifting through it) and thin VAPOUR rises off it.
##
## Three variants (VARIANTS):
##   film    a thin glassy film: nearly clear in the middle, a crisp bright rim, splash droplets round it, glassy streaks
##           down a wall
##   slime   thicker and milkier: a raised meniscus, more body colour, satellite blobs, heavy strings down a wall that end
##           in hanging drops
##   mist    a pool of low, clinging fog: soft-edged, layered, more vapour; a soft seep down a wall
##
##   EctoplasmLook.puddle("film", 0.9, seed)    # a floor puddle, origin at its centre on the floor
##   EctoplasmLook.drip("slime", 2.2, seed)     # a wall drip: origin at the wall's foot on its face, up +Y, out of the wall +Z
##   EctoplasmLook.set_wash(node, 0.6)          # Damp washing it away: 0 fresh .. 1 gone
##
## Every shader runs on TIME unless `clock` is set (>= 0 freezes them: the lab's stills). The shapes' jitter comes from the
## seed (never GameWorld.rng); the gym draws its seeds from GameWorld.fx_rng.

const GROUP := &"ectoplasm_look"
const VARIANTS: Array[String] = ["film", "slime", "mist"]
const LIFT := 0.014                 ## a puddle floats this far over the floor
const WALL_OFF := 0.012             ## a drip floats this far off the wall face

## Per variant: the sheet's look (alpha in the middle and at the rim band, how wide the band is, how soft the very edge,
## glow, swirl and its scale, specular sheen), its shape (meniscus rise, edge lobes, droplets round it), its vapour wisps
## and its fog layers (mist).
const SPEC := {
	"film": {"a_mid": 0.10, "a_edge": 0.62, "edge_w": 0.16, "soft": 0.05, "glow": 0.55, "swirl": 0.45, "scale": 1.6,
			"sheen": 0.9, "body": 0.25, "rise": 0.012, "lobes": 0.24, "drops": 6, "wisps": 2, "wisp_a": 0.10, "wisp_h": 0.6,
			"layers": 0},
	"slime": {"a_mid": 0.58, "a_edge": 0.88, "edge_w": 0.30, "soft": 0.04, "glow": 0.5, "swirl": 0.35, "scale": 2.4,
			"sheen": 1.0, "body": 0.62, "rise": 0.08, "lobes": 0.16, "drops": 5, "wisps": 1, "wisp_a": 0.08, "wisp_h": 0.5,
			"layers": 0},
	"mist": {"a_mid": 0.40, "a_edge": 0.26, "edge_w": 0.35, "soft": 0.5, "glow": 0.62, "swirl": 0.85, "scale": 1.1,
			"sheen": 0.15, "body": 0.45, "rise": 0.0, "lobes": 0.10, "drops": 0, "wisps": 4, "wisp_a": 0.10, "wisp_h": 0.7,
			"layers": 3},
}

## >= 0 freezes every ectoplasm shader's clock at this time (the lab's stills); < 0 runs on TIME.
static var clock := -1.0

## The sheet: a fan or ribbon whose UV.x is 0 at its middle and 1 at its edge (the rim band and the soft edge read it),
## UV2 its position in its own plane (the swirl's noise reads it, so pieces of one puddle swirl as one).
const SHEET_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 ecto : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform vec4 water : source_color = vec4(0.42, 0.50, 0.55, 1.0);
uniform float a_mid = 0.15;
uniform float a_edge = 0.6;
uniform float edge_w = 0.15;
uniform float soft = 0.05;
uniform float glow = 0.5;
uniform float swirl = 0.4;
uniform float swirl_scale = 2.0;
uniform float sheen = 0.9;
uniform float body_k = 0.3;
uniform float wash = 0.0;
uniform float phase = 0.0;
uniform float clock = -1.0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float t = clock < 0.0 ? TIME : clock;
	float r = clamp(UV.x, 0.0, 1.0);
	vec2 p = UV2 * swirl_scale + vec2(phase, phase * 0.37);
	vec2 w = vec2(fbm(p + vec2(t * 0.10, -t * 0.07)), fbm(p + vec2(5.2 - t * 0.08, 1.3 + t * 0.06)));
	float n = fbm(p + 1.9 * w + vec2(t * 0.04, 0.0));
	float vein = pow(1.0 - abs(n * 2.0 - 1.0), 7.0);
	float band = smoothstep(1.0 - edge_w, 1.0 - edge_w * 0.2, r);
	float fade = 1.0 - smoothstep(1.0 - soft, 1.0, r);
	// Damp: it breaks up from the thin edge inward and thins to plain water
	float holes = fbm(UV2 * 3.3 + vec2(7.0, 3.0)) * 0.75 + (1.0 - r) * 0.3;
	float keep = smoothstep(wash * 1.1 - 0.06, wash * 1.1 + 0.02, holes);
	float a = mix(a_mid, a_edge, band) * (1.0 - swirl * 0.55 + swirl * 1.1 * n) + vein * swirl * 0.45;
	vec3 body = ecto.rgb * body_k;
	ALBEDO = mix(body, water.rgb * 0.35, wash);
	EMISSION = ecto.rgb * glow * (0.30 + band * 0.85 + vein * 1.3 * swirl) * (1.0 - wash);
	ROUGHNESS = mix(0.06, 0.7, 1.0 - sheen);
	SPECULAR = 0.5 * sheen;
	METALLIC = 0.0;
	ALPHA = clamp(a * fade * keep * (1.0 - 0.35 * wash), 0.0, 1.0);
}
"""

## A wisp of vapour: a camera-facing strip whose noise scrolls up, swaying, faded at its foot and top.
const WISP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 ecto : source_color = vec4(0.70, 0.86, 1.0, 1.0);
uniform float alpha = 0.18;
uniform float wash = 0.0;
uniform float phase = 0.0;
uniform float clock = -1.0;

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float t = clock < 0.0 ? TIME : clock;
	float h = 1.0 - UV.y;
	float x = UV.x - 0.5 + 0.22 * sin(h * 6.5 - t * 0.9 + phase) * h;
	float width = mix(0.12, 0.30, h);
	float shape = 1.0 - smoothstep(width * 0.3, width, abs(x));
	float n = vn(vec2(UV.x * 4.0 + phase, h * 3.0 - t * 0.6)) * 0.6 + vn(vec2(UV.x * 9.0, h * 7.0 - t * 1.1 + phase)) * 0.4;
	float env = smoothstep(0.0, 0.18, h) * (1.0 - smoothstep(0.35, 1.0, h));
	ALBEDO = ecto.rgb;
	float gone = 1.0 - smoothstep(0.0, 0.6, wash);
	ALPHA = clamp(alpha * shape * env * (0.4 + n) * gone, 0.0, 1.0);
}
"""

static var _sheet_shader: Shader
static var _wisp_shader: Shader


## The ghosts' colour now (GhostLook.colour: ectoplasm matches its ghosts).
static func color_now() -> Color:
	return GhostLook.color_now()


static func spec_of(variant: String) -> Dictionary:
	return SPEC.get(variant, SPEC["film"])


# --- the builders -------------------------------------------------------------------------------------------------------

## A floor puddle of `variant`, about `radius` across its body (its splash droplets reach a little beyond), origin at its
## centre on the floor.
static func puddle(variant: String, radius: float = 1.0, seed_value: int = 1) -> Node3D:
	var root := _root("EctoPuddle", variant)
	_puddle_into(root, variant, radius, seed_value, Vector3.ZERO)
	return root


## A wall drip of `variant`, `height` up the wall: a splash high on the face, streaks running down it, and a small puddle
## at its foot. The origin is the wall's foot on its face; the drip runs up local +Y in the local XY plane and local +Z
## points out of the wall into the room.
static func drip(variant: String, height: float = 2.2, seed_value: int = 1) -> Node3D:
	var root := _root("EctoDrip", variant)
	var spec := spec_of(variant)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 3
	var col := color_now()
	var st := _begin()
	var splash_w := 0.42 if variant != "mist" else 0.55
	var top := height * rng.randf_range(0.9, 0.97) - splash_w * 0.7 * (1.0 + float(spec["lobes"]) * 1.3)
	# the splash: a lobed blob on the face where it hit
	_fan(st, Vector3(0, top, WALL_OFF), Vector3.RIGHT, Vector3.UP, Vector3.BACK, splash_w, Vector2(1.0, 0.7),
			float(spec["rise"]) * 0.5, float(spec["lobes"]) * 1.3, rng)
	# the streaks: running down from the splash, the long ones to the floor
	var n_streaks := 5 if variant == "film" else (4 if variant == "slime" else 1)
	for i in n_streaks:
		var x := rng.randf_range(-0.05, 0.05)
		if n_streaks > 1:
			x += (float(i) / float(n_streaks - 1) - 0.5) * splash_w * 1.5
		var long := i % 2 == 0 or variant == "mist"
		var bottom := 0.0 if long else top * rng.randf_range(0.25, 0.6)
		var w := 0.0
		match variant:
			"film": w = rng.randf_range(0.035, 0.06)
			"slime": w = rng.randf_range(0.06, 0.09)
			_: w = rng.randf_range(0.34, 0.4)
		_streak(st, x, top - 0.05, bottom, w, float(spec["rise"]) * 0.6, rng)
		if variant == "slime" and not long:
			# a hanging drop at its end
			_fan(st, Vector3(x, bottom + 0.02, WALL_OFF), Vector3.RIGHT, Vector3.UP, Vector3.BACK, w * 1.25, Vector2(1.0, 1.25),
					0.05, 0.05, rng)
		elif variant == "film" and not long:
			_fan(st, Vector3(x, bottom + 0.01, WALL_OFF), Vector3.RIGHT, Vector3.UP, Vector3.BACK, w * 1.1, Vector2(1.0, 1.3),
					0.01, 0.05, rng)
	_mesh(root, st, _sheet_material(spec, col, rng.randf() * 10.0))
	# the pool at its foot
	_puddle_into(root, variant, 0.5, seed_value + 11, Vector3(0, 0, 0.45), true)
	_wisp(root, Vector3(rng.randf_range(-0.3, 0.3), 0.0, 0.3), float(spec["wisp_a"]), float(spec["wisp_h"]), col, rng)
	return root


## Damp washing `node` (a puddle or a drip) away: 0 fresh, 1 gone. It breaks up from its thin edge inward, thins to plain
## water and stops glowing; its vapour goes. The look only: nothing here slows or stops anything.
static func set_wash(node: Node3D, k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	node.set_meta("wash", k)
	for m in _materials(node):
		m.set_shader_parameter("wash", k)


## Every ectoplasm material under `node` (tests, set_wash).
static func _materials(node: Node) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		var m := (node as MeshInstance3D).material_override as ShaderMaterial
		if m.shader == _sheet_shader or m.shader == _wisp_shader:
			out.append(m)
	for c in node.get_children():
		out.append_array(_materials(c))
	return out


static func materials_of(node: Node) -> Array[ShaderMaterial]:
	return _materials(node)


# --- the pieces ---------------------------------------------------------------------------------------------------------

static func _root(nm: String, variant: String) -> Node3D:
	var root := Node3D.new()
	root.name = nm
	root.add_to_group(GROUP)
	root.set_meta("variant", variant)
	return root


## A puddle's pieces into `root` at `at`. `foot`: the pool at a drip's foot (squashed against the wall, no droplets round
## it, its vapour left to the drip), so nothing of it reaches behind the wall face.
static func _puddle_into(root: Node3D, variant: String, radius: float, seed_value: int, at: Vector3, foot: bool = false) -> void:
	var spec := spec_of(variant)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 13 + 5
	var col := color_now()
	var st := _begin()
	var c := at + Vector3(0, LIFT, 0)
	var squash := 0.6 if foot else rng.randf_range(0.75, 0.95)
	_fan(st, c, Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, radius, Vector2(1.0, squash),
			float(spec["rise"]), float(spec["lobes"]), rng)
	for i in (0 if foot else int(spec["drops"])):
		var a := rng.randf_range(0.0, TAU)
		var d := radius * rng.randf_range(1.12, 1.45)
		var r := radius * rng.randf_range(0.06, 0.15)
		_fan(st, c + Vector3(cos(a) * d, 0, sin(a) * d), Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, r, Vector2.ONE,
				float(spec["rise"]) * 0.6, 0.1, rng)
	_mesh(root, st, _sheet_material(spec, col, rng.randf() * 10.0))
	# mist: soft fog layers stacked over the pool, each smaller and fainter
	for i in int(spec["layers"]):
		var lst := _begin()
		var lr := radius * (0.9 - 0.18 * float(i))
		var jig := Vector3(rng.randf_range(-0.1, 0.1), 0.08 + 0.09 * float(i), 0.0 if foot else rng.randf_range(-0.1, 0.1))
		_fan(lst, c + jig, Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, lr, Vector2(1.0, squash * 0.9), 0.0, 0.12, rng)
		var lm := _sheet_material(spec, col, rng.randf() * 10.0)
		lm.set_shader_parameter("a_mid", float(spec["a_mid"]) * 0.55)
		lm.set_shader_parameter("a_edge", float(spec["a_edge"]) * 0.4)
		lm.set_shader_parameter("soft", 0.7)
		_mesh(root, lst, lm)
	if not foot:
		for i in int(spec["wisps"]):
			var a := rng.randf_range(0.0, TAU)
			var d := radius * rng.randf_range(0.0, 0.7)
			_wisp(root, at + Vector3(cos(a) * d, 0.0, sin(a) * d), float(spec["wisp_a"]),
					float(spec["wisp_h"]) * rng.randf_range(0.8, 1.25), col, rng)


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _mesh(root: Node3D, st: SurfaceTool, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Sheet"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


const RINGS: Array[float] = [0.0, 0.3, 0.55, 0.75, 0.88, 0.96, 1.0]
const SIDES := 40


## A lobed blob in the plane through `c` spanned by u, v (n its face normal): `radius` scaled per axis by `stretch`, rising
## `rise` along n in the middle (a meniscus), its edge wobbled by up to `lobes`. UV.x is 0 in the middle and 1 at the edge,
## UV2 the position in the plane.
static func _fan(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3, n: Vector3, radius: float, stretch: Vector2, rise: float,
		lobes: float, rng: RandomNumberGenerator) -> void:
	var k1 := rng.randi_range(2, 3)
	var k2 := rng.randi_range(4, 6)
	var p1 := rng.randf_range(0.0, TAU)
	var p2 := rng.randf_range(0.0, TAU)
	var p3 := rng.randf_range(0.0, TAU)
	var edge: Array[float] = []
	for i in SIDES:
		var a := TAU * float(i) / float(SIDES)
		edge.append(radius * (1.0 + lobes * (0.55 * sin(a * k1 + p1) + 0.3 * sin(a * k2 + p2) + 0.15 * sin(a * 9.0 + p3))))
	var pts := []          # ring -> side -> [pos, normal, t]
	for ri in RINGS.size():
		var t := RINGS[ri]
		var ring := []
		for i in SIDES:
			var a := TAU * float(i) / float(SIDES)
			var dir := u * cos(a) * stretch.x + v * sin(a) * stretch.y
			var h := rise * (1.0 - pow(t, 3.0))
			var p := c + dir * edge[i] * t + n * h
			var slope := rise * 3.0 * t * t / maxf(edge[i], 0.01)
			var nn := (n + dir.normalized() * slope).normalized()
			ring.append([p, nn, t])
		pts.append(ring)
	for ri in RINGS.size() - 1:
		for i in SIDES:
			var j := (i + 1) % SIDES
			var a: Array = pts[ri][i]
			var b: Array = pts[ri][j]
			var cc: Array = pts[ri + 1][j]
			var d: Array = pts[ri + 1][i]
			if ri == 0:
				_vert(st, a, u, v)
				_vert(st, cc, u, v)
				_vert(st, d, u, v)
			else:
				_vert(st, a, u, v)
				_vert(st, b, u, v)
				_vert(st, cc, u, v)
				_vert(st, a, u, v)
				_vert(st, cc, u, v)
				_vert(st, d, u, v)


static func _vert(st: SurfaceTool, rec: Array, u: Vector3, v: Vector3) -> void:
	var p: Vector3 = rec[0]
	st.set_normal(rec[1])
	st.set_uv(Vector2(float(rec[2]), 0.0))
	st.set_uv2(Vector2(p.dot(u), p.dot(v)))
	st.add_vertex(p)


## A streak down the wall face (the local XY plane, z = WALL_OFF): centred on x, from y0 down to y1, `w` wide, wobbling,
## narrowing toward its foot. UV.x is 0 on its centre line and 1 at its sides.
static func _streak(st: SurfaceTool, x: float, y0: float, y1: float, w: float, bulge: float, rng: RandomNumberGenerator) -> void:
	var segs := 12
	var ph := rng.randf_range(0.0, TAU)
	var rows := []
	for i in segs + 1:
		var f := float(i) / float(segs)
		var y := lerpf(y0, y1, f)
		var cx := x + 0.03 * sin(f * 7.0 + ph) * f
		var hw := w * (1.0 - 0.45 * f) * (0.8 + 0.3 * sin(f * 11.0 + ph * 2.0))
		rows.append([Vector3(cx - hw, y, WALL_OFF), Vector3(cx, y, WALL_OFF + bulge), Vector3(cx + hw, y, WALL_OFF)])
	for i in segs:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		for side in 2:
			var o0: Vector3 = r0[0] if side == 0 else r0[2]
			var o1: Vector3 = r1[0] if side == 0 else r1[2]
			var m0: Vector3 = r0[1]
			var m1: Vector3 = r1[1]
			for q: Array in [[o0, 1.0], [m0, 0.0], [m1, 0.0], [o0, 1.0], [m1, 0.0], [o1, 1.0]]:
				var p: Vector3 = q[0]
				st.set_normal(Vector3.BACK)
				st.set_uv(Vector2(float(q[1]), 0.0))
				st.set_uv2(Vector2(p.x, p.y))
				st.add_vertex(p)


## A wisp of vapour rising `h` tall from `at`.
static func _wisp(root: Node3D, at: Vector3, alpha: float, h: float, col: Color, rng: RandomNumberGenerator) -> void:
	if _wisp_shader == null:
		_wisp_shader = Shader.new()
		_wisp_shader.code = WISP_SHADER
	var mi := MeshInstance3D.new()
	mi.name = "Wisp"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.34, h)
	mi.mesh = qm
	var m := ShaderMaterial.new()
	m.shader = _wisp_shader
	m.set_shader_parameter("ecto", col.lerp(Color.WHITE, 0.35))
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("phase", rng.randf() * TAU)
	m.set_shader_parameter("clock", clock)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	mi.position = at + Vector3(0, h * 0.5, 0)


static func _sheet_material(spec: Dictionary, col: Color, phase: float) -> ShaderMaterial:
	if _sheet_shader == null:
		_sheet_shader = Shader.new()
		_sheet_shader.code = SHEET_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sheet_shader
	m.set_shader_parameter("ecto", col)
	m.set_shader_parameter("a_mid", float(spec["a_mid"]))
	m.set_shader_parameter("a_edge", float(spec["a_edge"]))
	m.set_shader_parameter("edge_w", float(spec["edge_w"]))
	m.set_shader_parameter("soft", float(spec["soft"]))
	m.set_shader_parameter("glow", float(spec["glow"]))
	m.set_shader_parameter("swirl", float(spec["swirl"]))
	m.set_shader_parameter("swirl_scale", float(spec["scale"]))
	m.set_shader_parameter("sheen", float(spec["sheen"]))
	m.set_shader_parameter("body_k", float(spec["body"]))
	m.set_shader_parameter("phase", phase)
	m.set_shader_parameter("clock", clock)
	return m

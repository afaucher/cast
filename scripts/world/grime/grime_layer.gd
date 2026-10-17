class_name GrimeLayer
extends Node3D
## One per floor. Draws the grime as flat textured quads lying just above the hex tops, batched into TWO
## MultiMeshes (one for the persistent AMBIENT marks, one pooled for the 30 s PLAYER marks), so the whole
## layer is two draw calls whatever it holds. A quad was picked over Godot's Decal node: decals go through
## the clustered renderer (a shared 512-element budget with the lights) and cost per covered pixel, a
## flat quad costs next to nothing and works the same on every renderer.
##
## All marks share one procedural atlas (GrimeAtlas) and one shader that
##   - reads the tile (per-instance custom data: tile column, row, glow, alpha) and tint (instance colour),
##   - CLIPS every mark at the hex tile edges (it rebuilds the hex grid from the world position), so a big
##     scorch stops at the seams: the glowing amber gaps and the tile bevels are never covered,
##   - adds a subtle emission for ichor / embers / glass / spills.
##
## Player marks: add_mark() (or Grime.mark()) lays a few decals, each fitted to flat ground so none floats
## over a lower tile or the void. A mark lives Grime.LIFE seconds on the layer's own clock (it stops while
## the tree is paused), fades over the last Grime.FADE and is then freed; at most Grime.MAX_LIVE are alive
## and the oldest is recycled. Visual only: nothing here touches GameWorld.rng or any gameplay state.
##
## Hooks done here, with no edits in the code that causes them: GameWorld.actor_died (a monster's death
## splat) and every actor's shove_impact (a slam / hard landing scuff). The spells call Grime.mark().

const LIVE_SLOTS := 700
const FADE_STEP := 0.1            ## seconds between fade updates
const GRID_COLS := GrimeAtlas.COLS

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D emis : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 grid = vec2(7.0, 6.0);
uniform float edge_lo = 0.80;
uniform float edge_hi = 0.885;
uniform float emis_energy = 1.0;

varying vec3 wpos;
varying vec4 icd;
varying vec3 itint;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	icd = INSTANCE_CUSTOM;
	itint = COLOR.rgb;
}

// 0 at a hex centre, 1 at its edge (pointy-top hexes, corner radius 1: the same grid as Hex.from_world).
float hex_h(vec2 p) {
	const float S3 = 1.7320508;
	vec2 ax = vec2(S3 / 3.0 * p.x - p.y / 3.0, 2.0 / 3.0 * p.y);
	vec3 cu = vec3(ax.x, ax.y, -ax.x - ax.y);
	vec3 r = round(cu);
	vec3 d = abs(r - cu);
	if (d.x > d.y && d.x > d.z) {
		r.x = -r.y - r.z;
	} else if (d.y > d.z) {
		r.y = -r.x - r.z;
	}
	vec2 centre = vec2(S3 * (r.x + r.y * 0.5), 1.5 * r.y);
	vec2 o = p - centre;
	float inner = S3 * 0.5;
	return max(abs(o.x), max(abs(0.5 * o.x + 0.8660254 * o.y), abs(0.5 * o.x - 0.8660254 * o.y))) / inner;
}

void fragment() {
	vec2 tuv = (UV + icd.xy) / grid;
	vec4 t = texture(atlas, tuv);
	vec3 e = texture(emis, tuv).rgb;
	float m = 1.0 - smoothstep(edge_lo, edge_hi, hex_h(wpos.xz));
	ALBEDO = t.rgb * itint;
	ALPHA = t.a * icd.w * m;
	EMISSION = e * icd.z * emis_energy;
	ROUGHNESS = 0.92;
}
"""

static var _shader: Shader = null

var map: HexMap = null
var seed_value := 0
var ambient: Array[GrimePlan.Mark] = []      ## the persistent marks (read-only; for tests and tools)
var amb_mmi: MultiMeshInstance3D = null
var live_mmi: MultiMeshInstance3D = null

var _mat: ShaderMaterial = null
var _live: Array[LiveMark] = []              ## oldest first
var _free: PackedInt32Array = PackedInt32Array()
var _clock := 0.0
var _fade_t := 0.0
var _rng := RandomNumberGenerator.new()
var _hooked: Dictionary = {}                 ## actor instance id -> true


## One player mark: a few decals (slots of the live MultiMesh).
class LiveMark extends RefCounted:
	var recipe := ""
	var pos := Vector3.ZERO
	var t0 := 0.0
	var slots := PackedInt32Array()
	var tiles: Array[Vector2] = []
	var glows := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	var origins: Array[Vector3] = []     ## where each decal lies (kept CPU-side: the renderer cannot be read back headless)
	var fade := 1.0


## Create a layer under `parent` and build it. `themes` (room tag -> theme id) overrides SitePlan.room_themes.
static func attach(parent: Node, floor_map: HexMap, plan: SitePlan, seed_value_: int, themes: Dictionary = {}) -> GrimeLayer:
	var l := GrimeLayer.new()
	l.name = "Grime"
	parent.add_child(l)
	l.build(floor_map, plan, seed_value_, themes)
	return l


func _enter_tree() -> void:
	Grime.register(self)


func _exit_tree() -> void:
	Grime.unregister(self)
	if GameWorld.actor_died.is_connected(_on_actor_died):
		GameWorld.actor_died.disconnect(_on_actor_died)
	if GameWorld.actor_spawned.is_connected(_hook_actor):
		GameWorld.actor_spawned.disconnect(_hook_actor)


func _ready() -> void:
	if not GameWorld.actor_died.is_connected(_on_actor_died):
		GameWorld.actor_died.connect(_on_actor_died)
	if not GameWorld.actor_spawned.is_connected(_hook_actor):
		GameWorld.actor_spawned.connect(_hook_actor)
	for a in GameWorld.actors():
		_hook_actor(a)


func _physics_process(delta: float) -> void:
	advance(delta)


# ---------------------------------------------------------------------- build

## (Re)build for a floor: place the ambient marks and set up the two MultiMeshes.
func build(floor_map: HexMap, plan: SitePlan, seed_value_: int, themes: Dictionary = {}) -> void:
	map = floor_map
	seed_value = seed_value_
	_rng.seed = seed_value_ * 31 + 977
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_live.clear()
	_clock = 0.0
	_fade_t = 0.0
	_make_material()
	var aabb := _map_aabb()
	ambient = GrimePlan.build(floor_map, plan, seed_value_, themes)
	amb_mmi = _make_mmi("Ambient", ambient.size(), aabb)
	for i in ambient.size():
		var m := ambient[i]
		_write(amb_mmi.multimesh, i, m.kind, m.variant, m.pos, m.rot, m.size, m.alpha, m.glow, m.tint)
	live_mmi = _make_mmi("Live", LIVE_SLOTS, aabb)
	_free = PackedInt32Array()
	for i in LIVE_SLOTS:
		_hide(i)
		_free.append(i)
	live_mmi.multimesh.visible_instance_count = 0


func _make_material() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("atlas", GrimeAtlas.albedo_texture())
	_mat.set_shader_parameter("emis", GrimeAtlas.emission_texture())
	_mat.set_shader_parameter("grid", Vector2(GrimeAtlas.COLS, GrimeAtlas.ROWS))
	_mat.render_priority = 1


func _make_mmi(node_name: String, count: int, aabb: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	quad.material = _mat
	mm.mesh = quad
	mm.instance_count = count
	mm.custom_aabb = aabb
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _map_aabb() -> AABB:
	if map == null or map.cells.is_empty():
		return AABB(Vector3(-200, -10, -200), Vector3(400, 40, 400))
	var lo := Vector3(1.0e9, 1.0e9, 1.0e9)
	var hi := Vector3(-1.0e9, -1.0e9, -1.0e9)
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		var w := Hex.to_world(c, float(cell.level))
		lo = Vector3(minf(lo.x, w.x), minf(lo.y, w.y), minf(lo.z, w.z))
		hi = Vector3(maxf(hi.x, w.x), maxf(hi.y, w.y), maxf(hi.z, w.z))
	lo -= Vector3(3, 3, 3)
	hi += Vector3(3, 3, 3)
	return AABB(lo, hi - lo)


func _write(mm: MultiMesh, i: int, kind: String, variant: int, pos: Vector3, rot: float, size: Vector2, alpha: float, glow: float, tint: Color) -> void:
	var tc := GrimeAtlas.tile_cell(GrimeAtlas.tile_of(kind, variant))
	var b := Basis(Vector3.UP, rot) * Basis.from_scale(Vector3(size.x, 1.0, size.y))
	mm.set_instance_transform(i, Transform3D(b, pos))
	mm.set_instance_color(i, tint)
	mm.set_instance_custom_data(i, Color(tc.x, tc.y, glow, alpha))


func _hide(slot: int) -> void:
	live_mmi.multimesh.set_instance_transform(slot, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0)))
	live_mmi.multimesh.set_instance_custom_data(slot, Color(0, 0, 0, 0))


# ---------------------------------------------------------------------- player marks

func live_count() -> int:
	return _live.size()


func clock() -> float:
	return _clock


## What is alive: [{recipe, pos, age, fade (1 = opaque), pieces: [Vector3 origin of each decal]}], oldest first.
func live_marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lm in _live:
		out.append({"recipe": lm.recipe, "pos": lm.pos, "age": _clock - lm.t0, "fade": lm.fade, "pieces": lm.origins})
	return out


## Unused slots of the live pool (all of them when nothing is alive).
func free_slot_count() -> int:
	return _free.size()


## Leave a player-caused mark. `kind` is one of the Grime recipes (SCORCH, CORN, TEETH, CRACKS, STAIN,
## SCUFF); `size` is the effect radius where that means something. True when it was laid.
func add_mark(kind: String, pos: Vector3, size: float = 1.0) -> bool:
	if live_mmi == null:
		return false
	var pieces := _pieces(kind, pos, maxf(size, 0.05))
	if pieces.is_empty():
		return false
	while not _live.is_empty() and (_live.size() >= Grime.MAX_LIVE or _free.size() < pieces.size()):
		_retire(_live.pop_front())
	if _free.size() < pieces.size():
		_refresh_visible()
		return false
	var lm := LiveMark.new()
	lm.recipe = kind
	lm.pos = pos
	lm.t0 = _clock
	for m in pieces:
		var slot := _free[0]   # the lowest free slot: used slots stay packed at the front of the pool
		_free.remove_at(0)
		lm.slots.append(slot)
		lm.tiles.append(GrimeAtlas.tile_cell(GrimeAtlas.tile_of(m.kind, m.variant)))
		lm.glows.append(m.glow)
		lm.alphas.append(m.alpha)
		lm.origins.append(m.pos)
		_write(live_mmi.multimesh, slot, m.kind, m.variant, m.pos, m.rot, m.size, m.alpha, m.glow, m.tint)
	_live.append(lm)
	_refresh_visible()
	return true


func _retire(lm: LiveMark) -> void:
	for s in lm.slots:
		_hide(s)
		_free.insert(_free.bsearch(s), s)


## Draw only the front of the pool that holds live decals (the rest is hidden anyway, but costs vertex work).
func _refresh_visible() -> void:
	var hi := 0
	for lm in _live:
		for s in lm.slots:
			hi = maxi(hi, s + 1)
	live_mmi.multimesh.visible_instance_count = hi


## Advance the layer's clock (called every physics frame; tests may call it directly).
func advance(delta: float) -> void:
	_clock += delta
	var expired := false
	while not _live.is_empty() and _clock - _live[0].t0 >= Grime.LIFE:
		_retire(_live.pop_front())
		expired = true
	if expired:
		_refresh_visible()
	_fade_t += delta
	if _fade_t >= FADE_STEP:
		_fade_t = 0.0
		_update_fade()


## Marks in the last Grime.FADE seconds of their life get their alpha eased down.
func _update_fade() -> void:
	var start := Grime.LIFE - Grime.FADE
	for lm in _live:
		var age := _clock - lm.t0
		if age < start:
			continue
		var k := 1.0 - smoothstep(0.0, 1.0, (age - start) / Grime.FADE)
		lm.fade = k
		for i in lm.slots.size():
			live_mmi.multimesh.set_instance_custom_data(lm.slots[i], Color(lm.tiles[i].x, lm.tiles[i].y, lm.glows[i], lm.alphas[i] * k))


# ---------------------------------------------------------------------- recipes

func _frand(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


## The decals of one mark recipe.
func _pieces(recipe: String, pos: Vector3, size: float) -> Array[GrimePlan.Mark]:
	var out: Array[GrimePlan.Mark] = []
	match recipe:
		Grime.SCORCH:
			_add(out, "scorch", pos, clampf(size * 0.62, 0.55, 1.5), 1.3)
			for i in 3 + int(size):
				var q := _scatter(pos, size * _frand(0.5, 0.85))
				_add(out, "scorch", q, size * _frand(0.18, 0.28), 0.8)
			for i in 3:
				_add(out, "rubble", _scatter(pos, size * 0.8), 0.34, 0.9)
		Grime.CORN:
			_add(out, "ring", pos, size * 0.78)
			_add(out, "scorch", pos, size * 0.36, 0.8)
			for i in 9:
				_add(out, "kernel", _scatter(pos, size * 0.88), _frand(0.2, 0.28))
		Grime.TEETH:
			for i in 5 + _rng.randi() % 3:
				_add(out, "tooth", _scatter(pos, 0.9 * size), _frand(0.17, 0.25))
		Grime.CRACKS:
			_add(out, "crack_ichor", pos, size * 0.55)
			for i in 3:
				_add(out, "crack_ichor", _scatter(pos, size * 0.7), size * _frand(0.22, 0.32), 0.85)
		Grime.STAIN:
			_add(out, "stain", pos, 0.5 + size * 0.7, 1.1)
			for i in 2:
				_add(out, "ichor", _scatter(pos, 0.9 + size), _frand(0.2, 0.3), 0.9)
		Grime.SCUFF:
			_add(out, "scuff", pos, 0.3 + 0.5 * size)
		Grime.PAPER:
			_add(out, "paper", pos, 0.32 + 0.3 * size, 1.0)
			for i in 2:
				_add(out, "paper", _scatter(pos, 0.45 * size), _frand(0.2, 0.3), 0.85)
	return out


## A random point within `radius` of `pos` (flat).
func _scatter(pos: Vector3, radius: float) -> Vector3:
	var o := Vector2(1.0, 0.0).rotated(_rng.randf() * TAU) * sqrt(_rng.randf()) * radius
	return Vector3(pos.x + o.x, pos.y, pos.z + o.y)


## One decal whose content reaches `radius` world units around `at`, fitted to flat ground. Skipped (nothing
## added) when the spot has no ground to lie on.
func _add(out: Array[GrimePlan.Mark], kind: String, at: Vector3, radius: float, alpha_k: float = 1.0) -> void:
	var y := _ground(at)
	if is_nan(y):
		return
	var r := _fit(Vector3(at.x, y, at.z), radius, y)
	if r < 0.1:
		return
	var m := GrimePlan.Mark.new()
	m.kind = kind
	m.variant = _rng.randi() % maxi(GrimeAtlas.variant_count(kind), 1)
	var s := r / GrimeAtlas.CONTENT
	m.size = Vector2(s, s)
	m.pos = Vector3(at.x, y + Grime.LIFT + 0.002, at.z)
	m.rot = _rng.randf() * TAU
	m.alpha = clampf(Grime.style_alpha(kind) * alpha_k * _frand(0.9, 1.0), 0.0, 1.0)
	m.glow = Grime.style_glow(kind)
	var v := _frand(0.92, 1.08)
	m.tint = Color(v, v, v, 1.0)
	out.append(m)


## Top of the ground at `p` (world Y), or NAN when a decal cannot lie there (void, wall, stairs).
func _ground(p: Vector3) -> float:
	if map == null:
		return p.y
	var cell: HexMap.Cell = map.get_cell(Hex.from_world(p))
	if cell == null or cell.type == HexMap.Tile.WALL or cell.type == HexMap.Tile.STAIRS:
		return NAN
	return float(cell.level) * Hex.LEVEL_HEIGHT


## Shrink `radius` until a decal of that reach around `c` (on a plane at height `y`) never hangs over the void
## or a lower tile. Ground that rises above the plane is fine (the terrain hides that part). 0 = no room.
func _fit(c: Vector3, radius: float, y: float) -> float:
	if map == null:
		return radius
	var r := radius
	for _try in 5:
		var ok := true
		for ring in [r, r * 0.55]:
			for i in 10:
				var a := TAU * float(i) / 10.0
				var s := Vector3(c.x + cos(a) * ring, 0.0, c.z + sin(a) * ring)
				var cell: HexMap.Cell = map.get_cell(Hex.from_world(s))
				if cell == null:
					ok = false
				elif cell.type != HexMap.Tile.WALL and map.ground_height(s) < y - 0.04:
					ok = false
		if ok:
			return r
		r *= 0.72
	return 0.0


# ---------------------------------------------------------------------- hooks

func _on_actor_died(a: Actor) -> void:
	var m := a as Monster
	if m != null and is_instance_valid(m) and m.is_inside_tree():
		add_mark(Grime.STAIN, m.global_position, m.radius)


func _hook_actor(a: Actor) -> void:
	if a == null or _hooked.has(a.get_instance_id()):
		return
	_hooked[a.get_instance_id()] = true
	a.shove_impact.connect(_on_shove_impact.bind(a))


func _on_shove_impact(kind: String, pos: Vector3, amount: float, a: Actor) -> void:
	if not is_instance_valid(a) or not a.is_inside_tree():
		return
	if kind == "slam" or (kind == "land" and amount > 0.0):
		add_mark(Grime.SCUFF, pos, 1.0)

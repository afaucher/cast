class_name PoolView
extends Node3D
## What a pool shows above its terrain (HexMapView draws the pool floor and the liner): the WATER surface, the COPING
## along the rim, a FOAM line where the water meets the liner, and the pool's dressing: a chrome ladder on the far rim of
## the indoor pool (decoration: the pool is wading depth, you step in and out anywhere), the gantry with its dangling
## cage over a specimen pool. Presentation only: built from HexMap.pools (spawn data) on every machine, no state.
##
## Corners: the rim turns only on hex centres, at 120 degrees (PoolGeo keeps every pool convex). The coping and the foam
## line are offsets of the outline with MITRED corners (PoolGeo.offset): each edge's strip is a trapezoid whose ends lie
## on the corner bisectors, so neighbouring strips share their end edge exactly. The liner faces meet on the hex centre
## under it, and the deck tiles run flush to the rim line, so the coping sits on one clean line all round. (The lab built
## the coping from overlong boxes, which crossed and stuck out at the corners.)
##
## A MOAT (PoolGeo, a record with a `hole`: the island) is one ring of water: the surface is the band between the outline
## and the island, the coping runs round the outside (on the room's deck) and round the island (on the island's deck,
## overhanging the water outward), both mitred the same way, and the foam lines follow both rims. Two shark FINS patrol
## the channel's middle line (decoration: DecorModels "shark_fin" with a DecorAnim path; the shark is not built yet).

const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")
const FIN_SPEED := 1.1          ## a moat fin's speed along the channel (world units / s)

const COPING_W := 0.34          ## the coping's width on the deck, from the rim line
const COPING_OVER := 0.05       ## ... and how far it overhangs the water
const COPING_H := 0.07          ## its top above the deck
const COPING_NOSE := 0.12       ## the depth of its front edge (the nosing over the water)
const FOAM_IN := 0.13           ## the foam line's width inside the rim
const LOOKS := {
	PoolGeo.LOOK_POOL: {
		"shallow": Color(0.3, 0.86, 0.93), "deep": Color(0.04, 0.3, 0.44), "glow": Color(0.45, 0.95, 1.0), "alpha": 0.58,
		"glow_gain": 0.4, "coping": Color(0.88, 0.86, 0.8), "coping_edge": Color(0.72, 0.7, 0.66), "foam": Color(0.85, 0.98, 1.0),
	},
	PoolGeo.LOOK_SPECIMEN: {
		"shallow": Color(0.45, 1.0, 0.35), "deep": Color(0.05, 0.3, 0.12), "glow": Color(0.5, 1.0, 0.35), "alpha": 0.68,
		"glow_gain": 0.8, "coping": Color(0.55, 0.58, 0.6), "coping_edge": Color(0.98, 0.78, 0.12), "foam": Color(0.75, 1.0, 0.6),
	},
	PoolGeo.LOOK_MOAT: {
		"shallow": Color(0.22, 0.62, 0.6), "deep": Color(0.03, 0.17, 0.2), "glow": Color(0.3, 0.85, 0.8), "alpha": 0.66,
		"glow_gain": 0.35, "coping": Color(0.56, 0.55, 0.52), "coping_edge": Color(0.4, 0.39, 0.37), "foam": Color(0.7, 0.9, 0.85),
	},
}

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;
uniform vec4 shallow_col : source_color = vec4(0.25, 0.8, 0.88, 1.0);
uniform vec4 deep_col : source_color = vec4(0.05, 0.3, 0.42, 1.0);
uniform vec4 glow_col : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float alpha = 0.6;
uniform float glow_gain = 0.5;
uniform float speed = 0.6;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float t = 1.3 + TIME * speed;
	vec2 p = wp.xz;
	float w = sin(p.x * 1.7 + t) + sin(p.y * 2.3 - t * 1.3 + p.x * 0.6) + 0.6 * sin((p.x + p.y) * 3.1 + t * 2.0);
	float band = floor(clamp(w * 0.22 + 0.5, 0.0, 0.999) * 3.0) / 2.0;
	vec3 col = mix(deep_col.rgb, shallow_col.rgb, band);
	float cz = abs(sin(p.x * 2.6 + sin(p.y * 1.9 + t) * 1.5 + t * 0.7) + sin(p.y * 2.9 + sin(p.x * 1.6 - t) * 1.4));
	float lines = 1.0 - smoothstep(0.0, 0.14, cz);
	ALBEDO = col;
	EMISSION = glow_col.rgb * glow_gain * (0.3 + 0.9 * lines);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	ALPHA = alpha;
}
"""

static var _water_shader: Shader

var waters: Array[MeshInstance3D] = []
var copings: Array[MeshInstance3D] = []
var fins: Array[Node3D] = []


## Build the dressing of every pool of `map`.
func build(map: HexMap) -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	waters.clear()
	copings.clear()
	fins.clear()
	for rec in map.pools:
		if bool(rec.get("body", false)):
			continue   # a sewer's connected water (SewerBody: not a convex pool; SewerView draws it)
		_build_pool(rec)


func _build_pool(rec: Dictionary) -> void:
	var look: Dictionary = LOOKS.get(str(rec["look"]), LOOKS[PoolGeo.LOOK_POOL])
	var outline: Array = rec["outline"]
	var hole: Array = rec.get("hole", [])
	var deck_y := float(rec["deck_level"]) * Hex.LEVEL_HEIGHT
	var water_y := float(rec["surface_y"])
	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = water_mesh(outline, water_y, hole)
	water.material_override = _water_material(look)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	waters.append(water)
	var coping := MeshInstance3D.new()
	coping.name = "Coping"
	coping.mesh = coping_mesh(outline, deck_y, look["coping"], look["coping_edge"], str(rec["look"]) == PoolGeo.LOOK_SPECIMEN, hole)
	var cm := StandardMaterial3D.new()
	cm.vertex_color_use_as_albedo = true
	cm.vertex_color_is_srgb = true
	cm.roughness = 0.55
	coping.material_override = cm
	add_child(coping)
	copings.append(coping)
	var foam := MeshInstance3D.new()
	foam.name = "Foam"
	foam.mesh = foam_mesh(outline, water_y + 0.006, look["foam"], hole)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.vertex_color_is_srgb = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.render_priority = 2
	foam.material_override = fm
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(foam)
	var ladder: Dictionary = rec.get("ladder", {})
	if not ladder.is_empty():
		var lm := PoolProps.build("ladder", {"depth": deck_y - float(rec["floor_level"]) * Hex.LEVEL_HEIGHT})
		lm.name = "Ladder"
		add_child(lm)
		var lp: Vector2 = ladder["pos"]
		lm.position = Vector3(lp.x, deck_y, lp.y)
		lm.rotation_degrees.y = float(ladder["yaw"])
	var gantry: Dictionary = rec.get("gantry", {})
	if not gantry.is_empty():
		var gm := PoolProps.build("gantry", {"span": float(gantry["span"]), "height": float(gantry["height"])})
		gm.name = "Gantry"
		add_child(gm)
		var gp: Vector2 = gantry["pos"]
		gm.position = Vector3(gp.x, deck_y, gp.y)
		gm.rotation_degrees.y = float(gantry["yaw"])
	var path := PoolGeo.channel(rec)
	if path.size() >= 3 and str(rec.get("shark", "")) == "":   # (a pool with a real shark has no decorative fins)
		# two fins patrolling the moat, half a lap apart (decoration until the shark is built)
		for i in 2:
			var fin := DecorModels.build("shark_fin", {"path": path, "phase": 0.5 * float(i), "speed": FIN_SPEED, "y": water_y})
			fin.name = "Fin%d" % i
			fin.position = Vector3(path[0].x, water_y, path[0].y)
			add_child(fin)
			fins.append(fin)

func _water_material(look: Dictionary) -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	m.set_shader_parameter("shallow_col", look["shallow"])
	m.set_shader_parameter("deep_col", look["deep"])
	m.set_shader_parameter("glow_col", look["glow"])
	m.set_shader_parameter("alpha", float(look["alpha"]))
	m.set_shader_parameter("glow_gain", float(look["glow_gain"]))
	m.render_priority = 1
	return m


# --- meshes (static: tests read them back) -----------------------------------------------------------------------

## The water surface at height y, facing up: the convex outline as a fan from its first corner, or for a moat (`hole`,
## the island, corner i one row in from outline corner i) the band between the two, one trapezoid per edge.
static func water_mesh(outline: Array, y: float, hole: Array = []) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	if hole.is_empty():
		for i in range(1, outline.size() - 1):
			_tri_up(v, n, _p3(outline[0], y), _p3(outline[i], y), _p3(outline[i + 1], y))
		return _mesh(v, n, PackedColorArray())
	var m := outline.size()
	for i in m:
		var j := (i + 1) % m
		_tri_up(v, n, _p3(outline[i], y), _p3(outline[j], y), _p3(hole[j], y))
		_tri_up(v, n, _p3(outline[i], y), _p3(hole[j], y), _p3(hole[i], y))
	return _mesh(v, n, PackedColorArray())


## The coping: a flat top from just over the water (COPING_OVER in from the rim) to COPING_W out on the deck, its front
## edge (the nosing) dropping COPING_NOSE toward the water and its back edge down to the deck. Both edges are mitred
## offsets of the outline, so every corner is one clean seam on the bisector. A specimen pool's coping is steel with a
## hazard-yellow front edge. A moat's island (`hole`) gets the same coping turned inside out: over the water OUTSIDE the
## island's rim, COPING_W in onto the island, its nosing facing out.
static func coping_mesh(outline: Array, deck_y: float, col: Color, edge: Color, hazard_edge: bool, hole: Array = []) -> ArrayMesh:
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	_coping_ring(v, nn, cc, outline, deck_y, col, edge, hazard_edge, false)
	if not hole.is_empty():
		_coping_ring(v, nn, cc, hole, deck_y, col, edge, hazard_edge, true)
	return _mesh(v, nn, cc)


## The two mitred edges of a coping ring round `rim` (counter-clockwise): [wet edge (over the water), dry edge (on the
## deck)]. Round a pool the water is inside the rim; round an island it is outside.
static func coping_edges(rim: Array, island: bool) -> Array[PackedVector2Array]:
	var s := -1.0 if island else 1.0
	return [PoolGeo.offset(rim, -COPING_OVER * s), PoolGeo.offset(rim, COPING_W * s)]


static func _coping_ring(v: PackedVector3Array, nn: PackedVector3Array, cc: PackedColorArray, rim: Array, deck_y: float,
		col: Color, edge: Color, hazard_edge: bool, island: bool) -> void:
	var edges := coping_edges(rim, island)
	var wet := edges[0]
	var dry := edges[1]
	var top := deck_y + COPING_H
	var m := rim.size()
	for i in m:
		var j := (i + 1) % m
		# the top: a trapezoid between the two mitred offsets
		_quad_up(v, nn, cc, _p3(wet[i], top), _p3(wet[j], top), _p3(dry[j], top), _p3(dry[i], top), col)
		# the nosing, facing the water
		_quad_side(v, nn, cc, wet[i], wet[j], top, top - COPING_NOSE, not island, edge if hazard_edge else col.darkened(0.08))
		# the back edge, facing the deck
		_quad_side(v, nn, cc, dry[i], dry[j], top, deck_y, island, edge.darkened(0.1) if not hazard_edge else col.darkened(0.15))


## The foam line just inside the rim (and, round a moat's island, just outside the island's rim), at height y.
static func foam_mesh(outline: Array, y: float, col: Color, hole: Array = []) -> ArrayMesh:
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	_strip(v, nn, cc, PoolGeo.offset(outline, -FOAM_IN), PoolGeo.offset(outline, -0.01), y, col)
	if not hole.is_empty():
		_strip(v, nn, cc, PoolGeo.offset(hole, 0.01), PoolGeo.offset(hole, FOAM_IN), y, col)
	return _mesh(v, nn, cc)



static func _strip(v: PackedVector3Array, nn: PackedVector3Array, cc: PackedColorArray, inner: PackedVector2Array,
		outer: PackedVector2Array, y: float, col: Color) -> void:
	var m := inner.size()
	for i in m:
		var j := (i + 1) % m
		_quad_up(v, nn, cc, _p3(inner[i], y), _p3(inner[j], y), _p3(outer[j], y), _p3(outer[i], y), col)


static func _p3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Godot's front faces wind clockwise seen from the normal side, which for a face up is a POSITIVE signed area in X/Z
## (x, z) (the same winding as HexMapView's tops).
static func _tri_up(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var area := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
	if area < 0.0:
		var t := b
		b = c
		c = t
	v.append_array([a, b, c])
	n.append_array([Vector3.UP, Vector3.UP, Vector3.UP])


static func _quad_up(v: PackedVector3Array, n: PackedVector3Array, cc: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri_up(v, n, a, b, c)
	_tri_up(v, n, a, c, d)
	cc.append_array([col, col, col, col, col, col])


## A vertical quad on the segment p -> q from y_top down to y_bot, facing toward the pool's inside (`inward`) or out.
static func _quad_side(v: PackedVector3Array, n: PackedVector3Array, cc: PackedColorArray, p: Vector2, q: Vector2, y_top: float, y_bot: float,
		inward: bool, col: Color) -> void:
	var e := q - p
	var out := Vector2(e.y, -e.x).normalized()     # (counter-clockwise outline: outward)
	var nrm2 := -out if inward else out
	var nrm := Vector3(nrm2.x, 0.0, nrm2.y)
	# clockwise seen from the normal side: walking left to right (seen from outside the face) along the top, then down
	var right := (-nrm).cross(Vector3.UP)
	var a := _p3(p, 0.0)
	var b := _p3(q, 0.0)
	if (b - a).dot(right) < 0.0:
		var t := a
		a = b
		b = t
	var at := Vector3(a.x, y_top, a.z)
	var bt := Vector3(b.x, y_top, b.z)
	var bb := Vector3(b.x, y_bot, b.z)
	var ab := Vector3(a.x, y_bot, a.z)
	v.append_array([at, bt, bb, at, bb, ab])
	for _i in 6:
		n.append(nrm)
		cc.append(col)


static func _mesh(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	if not c.is_empty():
		arrays[Mesh.ARRAY_COLOR] = c
	var mesh := ArrayMesh.new()
	if not v.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

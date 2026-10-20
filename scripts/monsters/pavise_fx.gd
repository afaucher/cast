class_name PaviseFx
extends Node3D
## The Pavise crossbowman's tells (docs/design/combat-proposals.md §2, "As built"; the read test's choices in
## docs/design/pavise-read-test.md). Cosmetic: every screen draws them from what it already shows (the aim from
## world.charge / world.lock, a block from the hit it ran), so nothing here travels.
##
##   aim line    a red line on the floor from the bow to its victim: dashed and dim while it TRACKS (the first 0.8 s), solid
##               and bright when it LOCKS (the last 0.4 s, along the locked line). No floor arc (user, 2026-10-20).
##   block()     a blocked hit on the front of the shield: a white-hot spark, a few streaks and the grey "0" (the chicken's
##               style). Static: it stands in the world, not on the monster.
##
## A child of the Pavise, top_level (world space), rebuilt only when the line moves.

const LINE_RED := Color(1.0, 0.16, 0.08)
const LINE_Y := 0.035                    ## above the floor under each end
const DASH := 0.7                        ## a dash and its gap
const LINE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.16, 0.08, 1.0);
uniform float energy = 1.5;
void fragment() {
	float e = 1.0 - abs(UV.x - 0.5) * 2.0;
	ALBEDO = color.rgb * energy * (0.35 + 0.65 * e);
	ALPHA = color.a * clamp(e * 1.6, 0.0, 1.0);
}
"""
const SPARK := Color(1.0, 0.85, 0.55)
const ZERO_GREY := Color(0.82, 0.82, 0.82)

static var _shader: Shader = null

var _strips: Array[MeshInstance3D] = []
var _key := ""


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY


static func _mat(col: Color, energy: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = LINE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("energy", energy)
	return m


## Draw the aim line from `from` to `to` (world, flat on the floor), dashed while tracking, solid when locked.
func aim(from: Vector3, to: Vector3, locked: bool) -> void:
	var a := _on_floor(from)
	var b := _on_floor(to)
	var key := "%s|%.2f,%.2f|%.2f,%.2f" % [locked, a.x, a.z, b.x, b.z]
	if key == _key:
		return
	_free_strips()
	_key = key
	if (b - a).length() < 0.3:
		return
	if locked:
		_strip(a, b, 0.20, LINE_RED, 2.2)
		_strip(a + Vector3(0, 0.004, 0), b + Vector3(0, 0.004, 0), 0.07, Color(1.0, 0.55, 0.35), 1.6)
		return
	var n := maxi(1, int((b - a).length() / DASH))
	for i in n:
		_strip(a.lerp(b, (i + 0.0) / n), a.lerp(b, (i + 0.55) / n), 0.13, Color(LINE_RED.r, LINE_RED.g, LINE_RED.b, 0.7), 1.3)


func clear() -> void:
	_free_strips()
	_key = ""


func _free_strips() -> void:
	for s in _strips:
		if is_instance_valid(s):
			s.queue_free()
	_strips.clear()


## True while a line is drawn (tests).
func showing() -> bool:
	return not _strips.is_empty()


static func _on_floor(p: Vector3) -> Vector3:
	var y := p.y
	var map := GameWorld.map
	if map != null:
		var g := map.ground_height(p)
		if not is_nan(g):
			y = g
	return Vector3(p.x, y + LINE_Y, p.z)


func _strip(a: Vector3, b: Vector3, width: float, col: Color, energy: float) -> void:
	var d := b - a
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, d.length())
	mi.mesh = pm
	mi.material_override = _mat(col, energy)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var z := d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.global_transform = Transform3D(Basis(x, z.cross(x).normalized(), z), (a + b) * 0.5)
	_strips.append(mi)


## A blocked hit at `p` on the shield's front (`face`: the way the front looks): the spark, streaks and the grey "0".
static func block(p: Vector3, face: Vector3) -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	var sparks: Array[Color] = [SPARK, Color.WHITE, Color(1.0, 0.78, 0.40)]
	Fx.burst(p + face * 0.08, sparks, 9, 3.2, 0.06, 0.28, 6.0, (face + Vector3.UP * 0.5).normalized(), 70.0)
	Fx.flash_sphere(p + face * 0.08, 0.22, SPARK, 0.12)
	Fx.number(p + Vector3(0, 0.6, 0), "0", ZERO_GREY, 0.85)

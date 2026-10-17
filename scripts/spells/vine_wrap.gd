class_name VineWrap
extends Node3D
## Thorny vines spiralling up a rooted actor's legs: the look of "you are rooted". A cosmetic child of the actor,
## built as one faceted mesh (two strands with thorns), it grows over a quarter second, sways a little and
## withers away when the actor's "vines" modifier is about to run out (or the actor dies). Any machine can draw
## it from the modifier, which is replicated state.
##
##   VineWrap.attach(actor, seconds)    # no-op on inanimate actors (hellgates, priced props, packages)

const GROW := 0.25
const WITHER := 0.4
const BASE := Color(0.15, 0.42, 0.12)
const TIP := Color(0.5, 0.85, 0.22)
const THORN := Color(0.92, 0.82, 0.52)
const OUTLINE := Color(0.03, 0.10, 0.02)
const STRANDS := 2
const SEGMENTS := 9

static var _mat: ShaderMaterial = null

var target: Actor = null

var _age := 0.0
var _mi: MeshInstance3D = null


## Who may write each var (see Net). Cosmetic only.
func net_fields() -> Dictionary:
	return {"target": Net.SPAWN, "_age": Net.LOCAL, "_mi": Net.LOCAL}


static func attach(a: Actor, _seconds: float) -> VineWrap:
	if a == null or not is_instance_valid(a) or a.dead or not a.is_inside_tree():
		return null
	if a is Hellgate or a is PricedProp or a.is_in_group("breakables"):
		return null
	var w := a.get_node_or_null("VineWrap") as VineWrap
	if w != null:
		w._age = minf(w._age, GROW)   # a second dose regrows it
		return w
	w = VineWrap.new()
	w.name = "VineWrap"
	w.target = a
	a.add_child(w)
	return w


func _ready() -> void:
	if _mat == null:
		_mat = LowPolyMaterial.make_glow(Color(0.35, 0.9, 0.2), 0.12, 2.0, OUTLINE)
	var h := 1.6
	if target != null and "ui_height" in target:
		var v: Variant = target.get("ui_height")
		if v is float and float(v) > 0.2:
			h = float(v)
	_mi = MeshInstance3D.new()
	_mi.mesh = _build(maxf(target.radius, 0.3) * 1.08, h * 0.62).to_mesh()
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.set_meta("no_flash", true)
	add_child(_mi)
	_mi.scale = Vector3(1.0, 0.01, 1.0)


func _process(delta: float) -> void:
	_age += delta
	if target == null or not is_instance_valid(target) or target.dead or not target.has_modifier("vines"):
		queue_free()
		return
	var left := target.modifier_left("vines")
	var grow := clampf(_age / GROW, 0.0, 1.0)
	var wither := clampf(left / WITHER, 0.0, 1.0)
	var k := (1.0 - pow(1.0 - grow, 3.0)) * wither
	_mi.scale = Vector3(1.0 + 0.06 * sin(GameWorld.time * 7.0), maxf(k, 0.01), 1.0 + 0.06 * cos(GameWorld.time * 6.0))
	_mi.rotation.y = 0.08 * sin(GameWorld.time * 3.0)


## Two spiral strands from the ground up to `height`, thorns every other segment.
static func _build(radius: float, height: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(811, 0.08)
	for k in STRANDS:
		var phase := PI * float(k)
		var prev := Vector3.ZERO
		for i in SEGMENTS + 1:
			var f := float(i) / SEGMENTS
			var a := phase + f * TAU * 1.6
			var r := radius * lerpf(1.05, 0.85, f)
			var p := Vector3(cos(a) * r, 0.04 + f * height, sin(a) * r)
			if i > 0:
				var d := p - prev
				var mid := (p + prev) * 0.5
				var seg := LowPoly.cylinder(lerpf(0.075, 0.04, f), lerpf(0.075, 0.04, f), d.length() * 1.15, 5, BASE.lerp(TIP, f), 820 + i + k * 20, 0.015, 1, 0.08)
				# The cylinder stands along +Y: tilt it onto the segment direction.
				var up := d.normalized()
				var axis := Vector3.UP.cross(up)
				var bs := Basis.IDENTITY
				if axis.length() > 0.0001:
					bs = Basis(axis.normalized(), Vector3.UP.angle_to(up))
				s.merge(seg, Transform3D(bs, mid))
				if i % 2 == 0:
					var out := Vector3(cos(a), 0.2, sin(a)).normalized()
					var thorn := LowPoly.cylinder(0.05, 0.0, 0.18, 4, THORN, 860 + i + k * 20, 0.0, 1, 0.05)
					var ax := Vector3.UP.cross(out)
					var tb := Basis(ax.normalized(), Vector3.UP.angle_to(out)) if ax.length() > 0.0001 else Basis.IDENTITY
					s.merge(thorn, Transform3D(tb, p + out * 0.07))
			prev = p
	return s

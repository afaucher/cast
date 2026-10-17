class_name TeethFx
extends Node3D
## "Cast teeth" visual effect: TOO MANY TEETH sprout out of a victim, swell and jitter faster and
## faster, glow a warning, then EXPLODE into a burst of tumbling teeth, sparkles and a bright floor
## flash while the victim does a comedic chomp-squash. Comedic body horror, not gore.
##
##   var fx := TeethFx.afflict(actor, 1.5, func() -> void: damage_around(actor))
##   ...
##   fx.cancel()      # a heal pulls the teeth (they shrink back with a sparkle, no pop)
##
## Visual only: it never touches stats, health or the simulation. It attaches to the target's actor
## node (so it works on every model), reads the victim's height from the first `ui_height` it finds
## (target, visual_override, model, or a model inside the Visual child; default 2.0) and scales
## everything with it. Teeth are 8-14 faceted pieces from TeethMeshes with a pink gum collar each:
## molars, a few fangs, incisors, gold fillings and exactly one gold tooth. They are placed on the
## victim's body, biased up and toward the game camera so they read from above.
##
## Timeline (t = seconds since afflict, T = grow_time):
##   0 .. T         every tooth grows 0 -> oversized on an ease-in curve (a little bud pops out
##                  first so the sprouts show early), staggered. Jitter frequency and amplitude climb.
##   T-0.4 .. T     warning: the teeth glow pale yellow, their ink outline turns bright and fat and
##                  pulses faster, a thin ring pulses on the floor.
##   T              POP: the same tooth nodes become ballistic debris (gravity, floor bounces,
##                  tumbling) plus loose chips, a floor flash ring, a flash core, sparkles, a small
##                  camera shake and a chomp squash on the victim's visual. `on_pop` fires once.
##   T + 1.5        everything is freed.
## The effect lives under the victim while it grows and moves itself to the world root at the pop,
## so the debris survives a victim that dies or is freed in `on_pop`.
##
## `manual` + `advance(dt)` let a lab or a test drive time deterministically instead of _process.

signal popped
signal cancelled

enum Phase { GROW, POP, CANCEL, DONE }

const COUNT_MIN := 8
const COUNT_MAX := 14
const WARN_TIME := 0.4
const DEBRIS_TIME := 1.5
const CANCEL_TIME := 0.32
const CANCEL_LIFE := 0.9
const GRAVITY := 26.0
const CAMERA_YAW_DEG := 45.0          ## the game camera's yaw: teeth lean toward it so they show
const DEFAULT_HEIGHT := 2.0
const WARM := Color(1.0, 0.93, 0.55)

## Labs and tests set this nonzero to make every effect reproducible (seed = seed_base * 1000 + serial).
static var seed_base := 0
static var _serial := 0
static var _star_tex: ImageTexture
static var _tori := {}

var grow_time := 1.5
var on_pop: Callable = Callable()
var target: Node3D = null
var manual := false                    ## true: only advance(dt) moves time
var phase: int = Phase.GROW
var height := DEFAULT_HEIGHT
var tooth_unit := 1.0                  ## world size of a "1.0" tooth
var seed_value := 0                    ## 0 = random

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _age := 0.0                        ## seconds since the pop / cancel
var _jit := 0.0
var _teeth: Array[Tooth] = []
var _bits: Array[Bit] = []             ## debris + sparkles
var _flashes: Array[Flash] = []
var _mat: ShaderMaterial
var _outline: ShaderMaterial
var _warn_ring: MeshInstance3D
var _warn_mat: StandardMaterial3D
var _spark_mats: Array[StandardMaterial3D] = []
var _visual: Node3D = null
var _visual_base := Vector3.ONE
var _squashing := false
var _cancel_from: Array[float] = []


## One tooth: its placement on the body and its animation state.
class Tooth extends RefCounted:
	var node: MeshInstance3D
	var kind := "molar"
	var dir := Vector3.UP
	var anchor := Vector3.ZERO
	var size := 1.0
	var delay := 0.0
	var roll := 0.0
	var wob_a := Vector3.RIGHT
	var wob_b := Vector3.FORWARD
	var phase := 0.0
	var sparkle: MeshInstance3D = null
	var gum: MeshInstance3D = null


## A flying thing (tooth debris, chip or sparkle) with simple ballistic integration.
class Bit extends RefCounted:
	var node: MeshInstance3D
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var ang := Vector3.ZERO
	var rot := Basis.IDENTITY
	var size := 1.0
	var half := 0.4                    ## centre-of-mass offset along the local up axis
	var life := 1.5
	var age := 0.0
	var gravity := 26.0
	var bounces := 0
	var spark := false
	var twinkle := 0.0


## An additive flash that scales up and fades (core, floor disc, ring).
class Flash extends RefCounted:
	var node: MeshInstance3D
	var mat: StandardMaterial3D
	var color := Color.WHITE
	var dur := 0.3
	var age := 0.0
	var from_scale := Vector3.ONE
	var to_scale := Vector3.ONE
	var power := 1.5


# ============================================================================== API

## Sprout teeth on `target_node` for `grow_seconds`, then pop. `on_pop_call` is called once, at the pop.
## Returns the effect (null for an invalid target). A second afflict on the same target replaces the first.
static func afflict(target_node: Node3D, grow_seconds: float, on_pop_call: Callable = Callable()) -> TeethFx:
	if target_node == null or not is_instance_valid(target_node):
		return null
	if target_node.has_meta("teeth_fx"):
		var old: Variant = target_node.get_meta("teeth_fx")
		if old is TeethFx and is_instance_valid(old):
			(old as TeethFx)._dismiss()
	var fx := TeethFx.new()
	fx.name = "TeethFx"
	fx.grow_time = maxf(grow_seconds, 0.2)
	fx.on_pop = on_pop_call
	fx.target = target_node
	if seed_base != 0:
		_serial += 1
		fx.seed_value = seed_base * 1000 + _serial
	target_node.set_meta("teeth_fx", fx)
	target_node.add_child(fx)
	return fx


## The dentist: the teeth shrink back with a little sparkle and the pop never happens.
## Returns false when it is too late (already popping, cancelled or done).
func cancel() -> bool:
	if phase != Phase.GROW:
		return false
	phase = Phase.CANCEL
	_age = 0.0
	_cancel_from.clear()
	for th in _teeth:
		_cancel_from.append(_grow_curve(_tooth_x(th)))
		_sparkle(th.anchor + th.dir * 0.5 * tooth_unit * th.size, 0.7 + 0.5 * _rng.randf(), _rng.randi() % 3, 0.5)
	_set_warning(0.0, 0.0)
	_release_target()
	cancelled.emit()
	return true


func is_growing() -> bool:
	return phase == Phase.GROW


## 0..1 progress toward the pop.
func progress() -> float:
	return clampf(_t / grow_time, 0.0, 1.0)


func tooth_count() -> int:
	return _teeth.size()


## Drive time by hand (labs and tests set `manual = true` first).
func advance(dt: float) -> void:
	match phase:
		Phase.GROW:
			_follow()
			_t += dt
			_update_grow(dt)
			if _t >= grow_time:
				_pop()
		Phase.POP:
			_age += dt
			_update_bits(dt)
			_update_flashes(dt)
			_update_squash()
			if _age >= DEBRIS_TIME:
				_finish()
		Phase.CANCEL:
			_follow()
			_age += dt
			_update_cancel()
			_update_bits(dt)
			if _age >= CANCEL_LIFE:
				_finish()


# ============================================================================== lifecycle

func _init() -> void:
	top_level = true


func _ready() -> void:
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	height = _find_height(target) if target != null else DEFAULT_HEIGHT
	tooth_unit = 0.32 * height + 0.3
	_visual = _find_visual(target) if target != null else null
	_make_materials()
	_build_teeth()
	_follow()
	_update_grow(0.0)


func _process(delta: float) -> void:
	if not manual:
		advance(delta)


func _exit_tree() -> void:
	_release_target()
	if target != null and is_instance_valid(target) and target.has_meta("teeth_fx") and target.get_meta("teeth_fx") == self:
		target.remove_meta("teeth_fx")


## Restore the squashed visual (used on every way out).
func _release_target() -> void:
	if _squashing and _visual != null and is_instance_valid(_visual):
		_visual.scale = _visual_base
	_squashing = false


func _dismiss() -> void:
	_release_target()
	phase = Phase.DONE
	if is_inside_tree():
		get_parent().remove_child(self)
	queue_free()


func _finish() -> void:
	_release_target()
	phase = Phase.DONE
	queue_free()


func _follow() -> void:
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		global_transform = Transform3D(Basis.IDENTITY, target.global_position)


# ============================================================================== finding things

static func _find_height(t: Node) -> float:
	var h := _height_in(t, 3)
	return h if h > 0.0 else DEFAULT_HEIGHT


static func _height_in(n: Node, depth: int) -> float:
	if "ui_height" in n:
		var v: Variant = n.get("ui_height")
		if v is float and float(v) > 0.2:
			return float(v)
	for prop in ["visual_override", "model"]:
		var o: Variant = n.get(prop)
		if o is Node and "ui_height" in (o as Node):
			var v2: Variant = (o as Node).get("ui_height")
			if v2 is float and float(v2) > 0.2:
				return float(v2)
	if depth > 0:
		for c in n.get_children():
			if c is TeethFx:
				continue
			var h := _height_in(c, depth - 1)
			if h > 0.0:
				return h
	return -1.0


## The node to chomp-squash: the actor's "Visual" child, else a visual_override / model, else the target.
static func _find_visual(t: Node3D) -> Node3D:
	var v := t.get_node_or_null("Visual") as Node3D
	if v != null:
		return v
	for prop in ["visual_override", "model"]:
		var o: Variant = t.get(prop)
		if o is Node3D:
			return o as Node3D
	return t


# ============================================================================== building

func _make_materials() -> void:
	_mat = LowPolyMaterial.make(2.2)
	_mat.set_shader_parameter("glow_color", WARM)
	_mat.set_shader_parameter("glow_strength", 0.0)
	_outline = _mat.next_pass as ShaderMaterial
	for c in [Color(1.0, 1.0, 0.95), Color(1.0, 0.85, 0.35), Color(1.0, 0.95, 0.6)]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = _star_texture()
		m.albedo_color = Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, 1.0)
		_spark_mats.append(m)
	_warn_mat = _glow_mat(Color(WARM.r, WARM.g, WARM.b, 0.0))


static func _glow_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m


static func _star_texture() -> ImageTexture:
	if _star_tex != null:
		return _star_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := absf((float(x) + 0.5) / n * 2.0 - 1.0)
			var v := absf((float(y) + 0.5) / n * 2.0 - 1.0)
			# four-point astroid star plus a hot core
			var star := clampf(1.0 - (sqrt(u) + sqrt(v)), 0.0, 1.0)
			var core := clampf(1.0 - sqrt(u * u + v * v) * 2.2, 0.0, 1.0)
			var a := clampf(pow(star, 0.7) * 1.2 + core * core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_star_tex = ImageTexture.create_from_image(img)
	return _star_tex


static func _torus(radius: float) -> TorusMesh:
	var k := "%.2f" % radius
	if _tori.has(k):
		return _tori[k]
	var t := TorusMesh.new()
	var tube := clampf(radius * 0.06, 0.05, 0.16)
	t.inner_radius = radius - tube
	t.outer_radius = radius + tube
	t.rings = 40
	t.ring_segments = 6
	_tori[k] = t
	return t


func _build_teeth() -> void:
	var n := _rng.randi_range(COUNT_MIN, COUNT_MAX)
	var plan: Array[String] = []
	for i in 2 + (1 if n >= 11 else 0):
		plan.append("fang")
	for i in 2:
		plan.append("incisor")
	for i in 1 + (1 if n >= 10 else 0):
		plan.append("molar_fill")
	while plan.size() < n - 1:
		plan.append("molar")
	plan.append("gold")
	for i in range(plan.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := plan[i]
		plan[i] = plan[j]
		plan[j] = tmp

	var rh := 0.24 * height
	var ry := 0.5 * height * 0.94
	var cy := 0.5 * height
	var cam := deg_to_rad(CAMERA_YAW_DEG)
	var dirs: Array[Vector3] = []
	for i in n:
		var best_dir := Vector3.UP
		var best_p := Vector3.ZERO
		var best_sep := -2.0
		for attempt in 28:
			var az := _rng.randf() * TAU
			if _rng.randf() < 0.62:
				az = cam + _rng.randfn(0.0, 0.95)
			var tt := lerpf(0.2, 1.0, pow(_rng.randf(), 0.7))
			var e := (tt - 0.5) * 2.0 * 0.97
			var ring := sqrt(maxf(1.0 - e * e, 0.0))
			var p := Vector3(sin(az) * ring * rh, cy + e * ry, cos(az) * ring * rh)
			var nrm := Vector3(p.x / (rh * rh), (p.y - cy) / (ry * ry), p.z / (rh * rh)).normalized()
			var d := nrm.lerp(Vector3.UP, 0.5).normalized()
			d = (d + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.13).normalized()
			var sep := 2.0
			for o in dirs:
				sep = minf(sep, 1.0 - o.dot(d))
			if sep > best_sep:
				best_sep = sep
				best_dir = d
				best_p = p
			if sep > 0.3:
				break
		dirs.append(best_dir)
		_add_tooth(plan[i], best_p * 0.94 + Vector3(0, cy, 0) * 0.06, best_dir)

	# the warning ring on the floor
	_warn_ring = MeshInstance3D.new()
	_warn_ring.mesh = _torus(0.42 * height + 0.35)
	_warn_ring.material_override = _warn_mat
	_warn_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warn_ring.position = Vector3(0, 0.07, 0)
	_warn_ring.visible = false
	add_child(_warn_ring)


func _add_tooth(kind: String, anchor: Vector3, dir: Vector3) -> void:
	var th := Tooth.new()
	th.kind = kind
	th.dir = dir
	th.anchor = anchor
	var kscale := 1.0
	match kind:
		"fang":
			kscale = 0.85
		"gold":
			kscale = 1.05
	th.size = tooth_unit * kscale * _rng.randf_range(0.82, 1.2)
	th.delay = _rng.randf_range(0.0, 0.35)
	th.roll = _rng.randf() * TAU
	th.phase = _rng.randf() * TAU
	th.wob_a = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized()
	th.wob_b = Vector3.UP.cross(th.wob_a).normalized()
	var mi := MeshInstance3D.new()
	mi.name = "Tooth_%s" % kind
	mi.mesh = TeethMeshes.mesh_for(kind)
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	th.node = mi
	var gum := MeshInstance3D.new()
	gum.name = "Gum"
	gum.mesh = TeethMeshes.mesh_for("gum")
	gum.material_override = _mat
	gum.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gum.position = Vector3(0, 0.03, 0)
	mi.add_child(gum)
	th.gum = gum
	if kind == "gold":
		var st := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 1.5
		st.mesh = q
		st.material_override = _spark_mats[1]
		st.position = Vector3(0.0, 0.8, 0.0)
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(st)
		th.sparkle = st
	_teeth.append(th)


# ============================================================================== growth

## 0..1 growth: a little bud pops out first so the sprouts show early, then an ease-in swell.
static func _grow_curve(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var bud := 0.34 * (1.0 - pow(1.0 - clampf(x / 0.1, 0.0, 1.0), 2.0))
	return bud + 0.66 * pow(x, 1.8)


func _tooth_x(th: Tooth) -> float:
	var span := grow_time * (1.0 - th.delay)
	return clampf((_t - th.delay * grow_time) / maxf(span, 0.01), 0.0, 1.0)


static func _basis_for(dir: Vector3, roll: float) -> Basis:
	var ref := Vector3.FORWARD if absf(dir.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := dir.cross(ref).normalized()
	var z := x.cross(dir).normalized()
	return Basis(dir, roll) * Basis(x, dir, z)


func _update_grow(dt: float) -> void:
	var x_all := clampf(_t / grow_time, 0.0, 1.0)
	_jit += dt * TAU * lerpf(5.0, 38.0, x_all * x_all)
	var warn_start := maxf(grow_time - WARN_TIME, 0.0)
	var warn := clampf((_t - warn_start) / maxf(grow_time - warn_start, 0.01), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * TAU * (5.0 + 8.0 * warn))
	for th in _teeth:
		var x := _tooth_x(th)
		var s := _grow_curve(x)
		var amp := x * x
		var a1 := (0.02 + 0.2 * amp) * sin(_jit + th.phase)
		var a2 := (0.02 + 0.2 * amp) * sin(_jit * 1.31 + th.phase * 1.7)
		var b := _basis_for(th.dir, th.roll).rotated(th.wob_a, a1).rotated(th.wob_b, a2)
		var swell := 1.0 + warn * 0.12 * pulse
		var shake := th.wob_a * (0.05 * amp * sin(_jit * 1.7 + th.phase)) * tooth_unit
		th.node.transform = Transform3D(b.scaled(Vector3.ONE * s * th.size * swell), th.anchor + shake)
		th.node.visible = s > 0.004
		if th.sparkle != null:
			var tw := 0.55 + 0.45 * sin(_t * 9.0)
			var k := 0.0 if x < 0.55 else tw * clampf((x - 0.55) * 3.0, 0.0, 1.0)
			th.sparkle.scale = Vector3.ONE * k
			th.sparkle.visible = k > 0.02
	_set_warning(warn, pulse)


func _set_warning(warn: float, pulse: float) -> void:
	_mat.set_shader_parameter("glow_strength", warn * (0.12 + 0.16 * pulse))
	var ink := LowPolyMaterial.INK
	var hot := Color(WARM.r * (1.3 + 0.9 * pulse), WARM.g * (1.3 + 0.9 * pulse), WARM.b * (1.2 + 0.7 * pulse))
	_outline.set_shader_parameter("outline_color", ink.lerp(hot, clampf(warn * 1.6, 0.0, 1.0)))
	_outline.set_shader_parameter("width_px", 2.2 + 3.6 * warn * (0.6 + 0.4 * pulse))
	_warn_ring.visible = warn > 0.0
	var scale_k := 1.0 + 0.1 * pulse
	_warn_ring.scale = Vector3(scale_k, 1.0, scale_k)
	_warn_mat.albedo_color = Color(WARM.r, WARM.g, WARM.b, warn * (0.25 + 0.4 * pulse))


# ============================================================================== pop

func _pop() -> void:
	phase = Phase.POP
	_age = 0.0
	_set_warning(0.0, 0.0)
	_warn_ring.visible = false
	var world: Node = null
	if GameWorld.root != null and is_instance_valid(GameWorld.root) and GameWorld.root.is_inside_tree():
		world = GameWorld.root
	elif is_inside_tree():
		world = get_tree().root
	if world != null and get_parent() != world:
		reparent(world, true)
	# the teeth become debris
	var centre := Vector3(0, 0.5 * height, 0)
	for th in _teeth:
		var b := Bit.new()
		b.node = th.node
		b.node.visible = true
		var s := th.size * 1.04
		b.size = s
		b.half = TeethMeshes.height_of(th.kind) * 0.5
		var out := th.anchor - centre
		out.y = 0.0
		var out_n := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
		if out.length() > 0.01:
			out_n = out.normalized()
		var base := _basis_for(th.dir, th.roll)
		b.rot = base
		b.pos = th.anchor + base * Vector3(0, b.half * s, 0)
		b.vel = out_n * _rng.randf_range(3.0, 6.5) * (0.7 + 0.3 * tooth_unit) + th.dir * 2.5 + Vector3.UP * _rng.randf_range(5.0, 8.5)
		b.ang = _rand_spin(7.0, 17.0)
		b.life = DEBRIS_TIME
		_bits.append(b)
		if th.sparkle != null:
			th.sparkle.queue_free()
			th.sparkle = null
		if th.gum != null:
			th.gum.queue_free()       # the gum stays behind (the victim keeps its pink collar-less body)
			th.gum = null
	_teeth.clear()
	# loose chips
	for i in _rng.randi_range(12, 17):
		var chip := Bit.new()
		var mi := MeshInstance3D.new()
		var gold := i % 5 == 0
		mi.mesh = TeethMeshes.mesh_for("chip_gold" if gold else "chip")
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		chip.node = mi
		chip.size = tooth_unit * _rng.randf_range(0.22, 0.42)
		chip.half = 0.0
		chip.pos = centre + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.8), _rng.randf_range(-1, 1)) * 0.25 * height
		var ang := _rng.randf() * TAU
		chip.vel = Vector3(sin(ang), 0, cos(ang)) * _rng.randf_range(3.5, 8.0) + Vector3.UP * _rng.randf_range(3.0, 8.0)
		chip.ang = _rand_spin(9.0, 22.0)
		chip.rot = Basis.from_euler(_rand_spin(0.0, 3.0))
		chip.life = _rng.randf_range(0.9, DEBRIS_TIME)
		_bits.append(chip)
	# sparkles
	for i in 20:
		_sparkle(centre + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.7, 0.7), _rng.randf_range(-1, 1)) * 0.3 * height,
				_rng.randf_range(0.6, 1.3), _rng.randi() % 3, 1.0)
	# flashes: bright core, floor disc, floor ring
	var rad := 0.55 * height + 0.6
	_flash("core", centre, Color(1.3, 1.15, 0.75, 0.6), 0.16, Vector3.ONE * 0.2 * height, Vector3.ONE * (0.32 * height + 0.25), 2.0)
	_flash("disc", Vector3(0, 0.06, 0), Color(1.2, 1.05, 0.6, 0.5), 0.3, Vector3(rad * 0.3, 1, rad * 0.3), Vector3(rad, 1, rad), 1.4)
	_flash("ring", Vector3(0, 0.09, 0), Color(1.8, 1.6, 1.0, 1.0), 0.5, Vector3(rad * 0.25, 1, rad * 0.25), Vector3(rad * 1.25, 1, rad * 1.25), 1.2)
	if is_inside_tree():
		get_tree().call_group("camera_rig", "shake", 0.2)
	# the chomp
	if _visual != null and is_instance_valid(_visual):
		_visual_base = _visual.scale
		_squashing = true
		_update_squash()
	popped.emit()
	if on_pop.is_valid():
		on_pop.call()


func _rand_spin(lo: float, hi: float) -> Vector3:
	var a := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	return a * _rng.randf_range(lo, hi)


func _flash(kind: String, pos: Vector3, color: Color, dur: float, from_s: Vector3, to_s: Vector3, power: float) -> void:
	var f := Flash.new()
	var mi := MeshInstance3D.new()
	match kind:
		"core":
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 10
			sm.rings = 5
			mi.mesh = sm
		"disc":
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.0
			cm.height = 0.02
			cm.radial_segments = 24
			cm.rings = 1
			mi.mesh = cm
		_:
			mi.mesh = _torus(1.0)
	f.mat = _glow_mat(color)
	f.color = color
	mi.material_override = f.mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.scale = from_s
	add_child(mi)
	f.node = mi
	f.dur = dur
	f.from_scale = from_s
	f.to_scale = to_s
	f.power = power
	_flashes.append(f)


func _sparkle(pos: Vector3, scale_k: float, mat_index: int, speed_k: float) -> void:
	var b := Bit.new()
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mi.mesh = q
	mi.material_override = _spark_mats[mat_index % _spark_mats.size()]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	b.node = mi
	b.spark = true
	b.pos = pos
	var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1.0), _rng.randf_range(-1, 1)).normalized()
	b.vel = d * _rng.randf_range(2.5, 6.5) * speed_k
	b.gravity = 5.0
	b.size = scale_k * (0.3 + 0.2 * tooth_unit)
	b.life = _rng.randf_range(0.45, 0.9)
	b.twinkle = _rng.randf() * TAU
	mi.position = pos
	mi.scale = Vector3.ONE * b.size * 0.1
	_bits.append(b)


func _update_bits(dt: float) -> void:
	var keep: Array[Bit] = []
	for b in _bits:
		b.age += dt
		if b.age >= b.life:
			b.node.queue_free()
			continue
		keep.append(b)
		b.vel.y -= b.gravity * dt
		b.pos += b.vel * dt
		var left := 1.0 - b.age / b.life
		if b.spark:
			b.vel *= maxf(1.0 - 2.5 * dt, 0.0)
			var tw := 0.65 + 0.35 * sin(b.age * 28.0 + b.twinkle)
			b.node.position = b.pos
			b.node.scale = Vector3.ONE * b.size * tw * clampf(left * 2.4, 0.0, 1.0) * clampf(b.age * 14.0, 0.2, 1.0)
			continue
		var radius := 0.28 * b.size * maxf(b.half * 2.0, 0.5)
		if b.pos.y < radius:
			b.pos.y = radius
			if b.vel.y < 0.0:
				b.vel.y = -b.vel.y * 0.36
				if b.vel.y < 1.2:
					b.vel.y = 0.0
				b.vel.x *= 0.62
				b.vel.z *= 0.62
				b.ang *= 0.5
				b.bounces += 1
		if b.pos.y <= radius + 0.001:
			b.vel.x *= maxf(1.0 - 5.0 * dt, 0.0)
			b.vel.z *= maxf(1.0 - 5.0 * dt, 0.0)
			b.ang *= maxf(1.0 - 6.0 * dt, 0.0)
		var w := b.ang.length()
		if w > 0.001:
			b.rot = (Basis(b.ang / w, w * dt) * b.rot).orthonormalized()
		var shrink := clampf(left / 0.28, 0.0, 1.0)
		var sc := b.size * shrink
		b.node.transform = Transform3D(b.rot.scaled(Vector3.ONE * sc), b.pos - b.rot * Vector3(0, b.half * sc, 0))
	_bits = keep


func _update_flashes(dt: float) -> void:
	var keep: Array[Flash] = []
	for f in _flashes:
		f.age += dt
		var k := clampf(f.age / f.dur, 0.0, 1.0)
		if k >= 1.0:
			f.node.queue_free()
			continue
		keep.append(f)
		var e := 1.0 - pow(1.0 - k, 2.5)
		f.node.scale = f.from_scale.lerp(f.to_scale, e)
		f.mat.albedo_color = Color(f.color.r, f.color.g, f.color.b, f.color.a * pow(1.0 - k, f.power))
	_flashes = keep


## The comedic chomp: squash flat for a beat, then spring back (to the exact starting scale).
func _update_squash() -> void:
	if not _squashing:
		return
	if _visual == null or not is_instance_valid(_visual):
		_squashing = false
		return
	var hold := 0.06
	if _age >= hold + 0.34:
		_visual.scale = _visual_base
		_squashing = false
		return
	var q := 1.0
	if _age < hold:
		q = clampf(_age / 0.03, 0.0, 1.0)
	else:
		var k := (_age - hold) / 0.34
		q = pow(1.0 - k, 2.0) * cos(k * 8.0)
	_visual.scale = _visual_base * Vector3(1.0 + 0.3 * q, 1.0 - 0.4 * q, 1.0 + 0.3 * q)


# ============================================================================== cancel

func _update_cancel() -> void:
	var k := clampf(_age / CANCEL_TIME, 0.0, 1.0)
	for i in _teeth.size():
		var th := _teeth[i]
		var s := _cancel_from[i] * pow(1.0 - k, 1.6)
		var b := Basis(th.dir, k * 2.4) * _basis_for(th.dir, th.roll)
		th.node.transform = Transform3D(b.scaled(Vector3.ONE * s * th.size), th.anchor)
		th.node.visible = s > 0.004
		if th.sparkle != null:
			th.sparkle.visible = false

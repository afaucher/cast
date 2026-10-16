class_name PebbleModel
extends Node3D
## Pebble, Golem Utility: a hulking FACETED low-poly sandstone golem in a hi-vis vest, tool belt and
## faded jeans, with giant leather work gloves. Built entirely in code from LowPoly soups (flat
## shaded, per-face painted colours) with the LowPolyMaterial toon + amber rim + ink outline.
##
## Faces local -Z, +X is its right. Origin is at the feet. About 2.5 units tall, ~2.1 wide with
## the gloves (the prototype hero is ~1.9 tall and 0.8 wide).
##
## Rigid named parts (all MeshInstance3D): body, head, vest, belt, arm_l, arm_r, glove_l, glove_r,
## leg_l, leg_r. head / vest / belt / arms hang under body; gloves under their arm; legs under root.
##
## Hero hooks (all optional on the hero side): attack_swing(), cast_pose(), set_downed(), ui_height.

## Rest pitch of the arms (radians, positive swings the hanging arm forward): puts the fists in front
## of the hips so they show from above and from the game camera.
const ARM_FWD := 0.30

## The model is built at ~2.4 units; this scales it up so Pebble is ~1.35x the prototype hero.
const MODEL_SCALE := 1.1

const PART_NAMES: Array[String] = ["body", "head", "vest", "belt", "arm_l", "arm_r", "glove_l", "glove_r", "leg_l", "leg_r"]

# Palette (sRGB, painted): warm sandstone, hi-vis orange with silver tape, leather, faded denim.
const STONE := Color(0.76, 0.66, 0.49)
const STONE_LIGHT := Color(0.85, 0.76, 0.58)
const STONE_DARK := Color(0.58, 0.48, 0.36)
const VEST := Color(1.00, 0.45, 0.07)
const VEST_DARK := Color(0.90, 0.36, 0.05)
const TAPE := Color(0.84, 0.86, 0.88, 1.0)      ## alpha 1 = retro-reflective
const LEATHER := Color(0.36, 0.22, 0.12)
const LEATHER_LIGHT := Color(0.50, 0.31, 0.16)
const BRASS := Color(0.78, 0.70, 0.48)
const DENIM := Color(0.30, 0.43, 0.64)
const DENIM_LIGHT := Color(0.42, 0.55, 0.74)
const GLOVE := Color(0.62, 0.46, 0.28)
const GLOVE_DARK := Color(0.42, 0.29, 0.17)
const DARK := Color(0.12, 0.08, 0.06)

## Height of the top of the head, so a hero can park its health bar above.
var ui_height := 2.5 * MODEL_SCALE

var parts: Dictionary = {}                 ## name -> MeshInstance3D
var idle_enabled := true
var outline_px := 2.4

var _mat: ShaderMaterial
var _t := 0.0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _swing_tween: Tween
var _swing_next_right := true
var _arm_kick := {"arm_l": 0.0, "arm_r": 0.0}   ## extra x rotation from swings / casts
var _body_base_y := 1.25
var _head_base_y := 1.0


func _init() -> void:
	name = "PebbleModel"
	scale = Vector3.ONE * MODEL_SCALE
	_mat = LowPolyMaterial.make(outline_px)
	_build()


func _ready() -> void:
	_last_pos = global_position


func has_part(part_name: String) -> bool:
	return parts.has(part_name)


func get_part(part_name: String) -> MeshInstance3D:
	return parts.get(part_name)


## Total triangle count over all parts (for tests / budgets).
func triangle_count() -> int:
	var n := 0
	for p: MeshInstance3D in parts.values():
		var arrays := p.mesh.surface_get_arrays(0)
		n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


# ------------------------------------------------------------------ build

func _add_part(part_name: String, soup: LowPoly.Soup, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = soup.to_mesh()
	mi.material_override = _mat
	mi.position = pos
	parent.add_child(mi)
	parts[part_name] = mi
	return mi


func _build() -> void:
	var body := _add_part("body", _body_soup(), self, Vector3(0, _body_base_y, 0))
	_add_part("head", _head_soup(), body, Vector3(0, _head_base_y, -0.07))
	_add_part("vest", _vest_soup(), body, Vector3.ZERO)
	_add_part("belt", _belt_soup(), body, Vector3(0, -0.27, 0))
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := _add_part("arm_" + side, _arm_soup(s), body, Vector3(0.78 * s, 0.66, 0.0))
		arm.rotation = Vector3(ARM_FWD, 0.0, deg_to_rad(9.0 * s))   # hangs a touch out and forward
		_add_part("glove_" + side, _glove_soup(s), arm, Vector3(0.12 * s, -1.28, -0.02))
		_add_part("leg_" + side, _leg_soup(s), self, Vector3(0.27 * s, 0.9, 0.0))


## Stone torso (hidden mostly by the vest, but the belly, the traps behind the head and the chest
## edges show) plus the jeans pelvis.
func _body_soup() -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.62, 0.50, 0.33), 0, 0.16, STONE, 11, 0.11)
	s.merge(LowPoly.boulder(Vector3(0.52, 0.34, 0.33), 0, 0.14, STONE_DARK, 12, 0.11), LowPoly.at(Vector3(0, -0.28, 0)))
	# trapezius hump behind / around the neck: reads from above as a stone yoke
	s.merge(LowPoly.boulder(Vector3(0.50, 0.28, 0.30), 0, 0.12, STONE_LIGHT, 13), LowPoly.at(Vector3(0, 0.50, 0.08)))
	# jeans pelvis under the belt
	s.merge(LowPoly.frustum(Vector2(0.98, 0.70), Vector2(0.92, 0.66), 0.34, DENIM, 14, 0.015), LowPoly.at(Vector3(0, -0.50, 0)))
	return s


func _head_soup() -> LowPoly.Soup:
	# a small blocky head with a heavy brow, sunk between the shoulders (no neck)
	var s := LowPoly.box(Vector3(0.46, 0.40, 0.44), STONE, 21, 0.045, 2)
	s.merge(LowPoly.frustum(Vector2(0.44, 0.40), Vector2(0.50, 0.40), 0.16, STONE_DARK, 22, 0.03, 1), LowPoly.at(Vector3(0, -0.24, -0.02)))   # jaw
	# heavy brow ridge, a dark shelf over the eyes
	s.merge(LowPoly.box(Vector3(0.54, 0.11, 0.17), STONE_DARK, 23, 0.025), LowPoly.at(Vector3(0, 0.08, -0.24), Vector3(12, 0, 0)))
	s.merge(LowPoly.box(Vector3(0.14, 0.17, 0.12), STONE_LIGHT, 24, 0.02), LowPoly.at(Vector3(0, -0.04, -0.26)))   # nose
	for x in [-1, 1]:
		s.merge(LowPoly.box(Vector3(0.10, 0.065, 0.05), DARK, 25 + x, 0.0, 1, 0.0), LowPoly.at(Vector3(0.11 * x, 0.0, -0.225)))
	s.merge(LowPoly.box(Vector3(0.22, 0.035, 0.04), DARK, 27, 0.0, 1, 0.0), LowPoly.at(Vector3(0, -0.19, -0.235)))
	# a couple of chipped facets on top
	s.merge(LowPoly.boulder(Vector3(0.13, 0.07, 0.12), 0, 0.2, STONE_LIGHT, 28), LowPoly.at(Vector3(0.08, 0.22, 0.02)))
	return s


## The hi-vis vest: blocky orange shell with silver reflective tape (two vertical stripes front and
## back, a horizontal band around, tape over the shoulder straps) and a pocket.
func _vest_soup() -> LowPoly.Soup:
	var y0 := -0.12     # local to body origin (body at world y 1.25): vest from y 1.13 to 1.98
	var h := 0.85
	var wb := 1.12
	var wt := 1.36
	var d := 0.82
	var cy := y0 + h * 0.5
	var s := LowPoly.frustum(Vector2(wb, d), Vector2(wt, d), h, VEST, 31, 0.03, 2, Vector2.ZERO, 0.10)
	s.merge(LowPoly.box(Vector3(1.02, 0.07, d + 0.02), VEST_DARK, 32, 0.008), LowPoly.at(Vector3(0, y0 + 0.02, 0)))   # hem
	# two vertical tape stripes front and back, standing off the surface a little
	var half := d * 0.5 + 0.012
	for sx in [-0.28, 0.28]:
		for sz in [-1.0, 1.0]:
			s.merge(LowPoly.box(Vector3(0.12, h - 0.10, 0.03), TAPE, 33, 0.0, 1, 0.03), LowPoly.at(Vector3(sx, cy - 0.02, half * sz)))
	# horizontal band wrapping the vest, at about a third up
	var by := y0 + 0.34
	var tb := (by - y0) / h
	var bw := lerpf(wb, wt, tb) + 0.045
	s.merge(LowPoly.box(Vector3(bw, 0.09, d + 0.05), TAPE, 34, 0.0, 1, 0.03), LowPoly.at(Vector3(0, by, 0)))
	# top plate: from above the vest is one big orange field with the tape stripes running over it
	s.merge(LowPoly.box(Vector3(wt - 0.10, 0.06, d - 0.02), VEST, 39, 0.012, 2, 0.10), LowPoly.at(Vector3(0, y0 + h - 0.01, 0)))
	# shoulder straps over the tops: orange with a tape stripe running over
	for sx in [-0.28, 0.28]:
		s.merge(LowPoly.box(Vector3(0.26, 0.06, d + 0.04), VEST, 35 + int(sx * 10), 0.01), LowPoly.at(Vector3(sx, y0 + h + 0.0, 0)))
		s.merge(LowPoly.box(Vector3(0.13, 0.03, d + 0.05), TAPE, 36, 0.0, 1, 0.03), LowPoly.at(Vector3(sx, y0 + h + 0.035, 0)))
	# collar plate between the straps (what shows around the head from above)
	s.merge(LowPoly.cylinder(0.30, 0.34, 0.07, 8, VEST_DARK, 37, 0.01), LowPoly.at(Vector3(0, y0 + h + 0.0, -0.02)))
	# chest pocket
	s.merge(LowPoly.box(Vector3(0.22, 0.2, 0.05), VEST_DARK, 38, 0.01), LowPoly.at(Vector3(-0.45, y0 + 0.5, -half - 0.01)))
	return s


func _belt_soup() -> LowPoly.Soup:
	var d := 0.78
	var s := LowPoly.box(Vector3(1.06, 0.14, d), LEATHER, 41, 0.01, 2)
	s.merge(LowPoly.box(Vector3(0.20, 0.13, 0.05), BRASS, 42, 0.005, 1, 0.03), LowPoly.at(Vector3(0, 0, -d * 0.5 - 0.015)))   # buckle
	s.merge(LowPoly.box(Vector3(0.10, 0.07, 0.06), LEATHER, 43, 0.0), LowPoly.at(Vector3(0, 0, -d * 0.5 - 0.02)))
	# pouches
	for p in [[-0.40, -0.31, 0.20, 0.24], [0.42, -0.30, 0.22, 0.20], [-0.22, 0.20, 0.26, 0.22]]:
		var px: float = p[0]
		var pz: float = p[1]
		var pw: float = p[2]
		var ph: float = p[3]
		var back := pz > 0.0
		var zz := d * 0.5 + 0.06 if back else -d * 0.5 - 0.06
		if absf(px) > 0.3:
			zz = zz * 0.9
		s.merge(LowPoly.box(Vector3(pw, ph, 0.12), LEATHER_LIGHT, 44 + int(px * 20), 0.012), LowPoly.at(Vector3(px, -0.14, zz)))
		s.merge(LowPoly.box(Vector3(pw + 0.02, 0.06, 0.14), LEATHER, 45, 0.008), LowPoly.at(Vector3(px, -0.14 + ph * 0.5, zz)))   # flap
	# a wrench handle sticking out of the right pouch, a hammer loop on the left hip
	s.merge(LowPoly.box(Vector3(0.05, 0.30, 0.05), Color(0.55, 0.57, 0.6), 46, 0.0), LowPoly.at(Vector3(0.45, -0.02, -0.33), Vector3(0, 0, -14)))
	s.merge(LowPoly.box(Vector3(0.07, 0.26, 0.07), LEATHER_LIGHT, 47, 0.0), LowPoly.at(Vector3(-0.56, -0.10, 0.0)))
	return s


## Shoulder boulder + upper arm + forearm, all stone. Pivot at the shoulder.
func _arm_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.42, 0.37, 0.40), 0, 0.22, STONE_LIGHT, 51 + side, 0.12)   # the big shoulder
	s.merge(LowPoly.boulder(Vector3(0.32, 0.42, 0.32), 0, 0.2, STONE, 53 + side, 0.12), LowPoly.at(Vector3(0.05 * side, -0.46, 0.0)))
	s.merge(LowPoly.boulder(Vector3(0.35, 0.40, 0.35), 0, 0.2, STONE_DARK, 55 + side, 0.12), LowPoly.at(Vector3(0.09 * side, -0.90, 0.0)))
	return s


## Giant work glove: a huge tan leather mitt with a heavy cuff, a thumb and knuckle bumps.
## Local origin is the middle of the fist.
func _glove_soup(side: int) -> LowPoly.Soup:
	var s := LowPoly.boulder(Vector3(0.47, 0.50, 0.48), 0, 0.15, GLOVE, 61 + side, 0.11)
	s.merge(LowPoly.cylinder(0.30, 0.33, 0.22, 8, GLOVE_DARK, 62, 0.025), LowPoly.at(Vector3(0, 0.44, 0.0)))   # cuff
	s.merge(LowPoly.cylinder(0.335, 0.335, 0.05, 8, LEATHER, 68, 0.0), LowPoly.at(Vector3(0, 0.40, 0.0)))   # cuff strap
	s.merge(LowPoly.boulder(Vector3(0.17, 0.26, 0.17), 0, 0.15, GLOVE, 63), LowPoly.at(Vector3(-0.38 * side, 0.08, -0.20), Vector3(0, 0, 22 * side)))   # thumb
	for i in 3:
		s.merge(LowPoly.boulder(Vector3(0.14, 0.12, 0.12), 0, 0.15, GLOVE_DARK, 64 + i), LowPoly.at(Vector3((i - 1) * 0.24, -0.04, -0.44)))   # knuckles
	return s


## Stubby leg: faded jeans, a lighter turn-up cuff, chunky stone foot. Pivot at the hip.
func _leg_soup(side: int) -> LowPoly.Soup:
	var out := LowPoly.Soup.new(73, 0.07)
	out.merge(LowPoly.frustum(Vector2(0.44, 0.46), Vector2(0.38, 0.40), 0.60, DENIM, 71 + side, 0.02, 2, Vector2.ZERO, 0.08), LowPoly.at(Vector3(0, -0.33, 0)))
	out.merge(LowPoly.frustum(Vector2(0.40, 0.42), Vector2(0.38, 0.40), 0.12, DENIM_LIGHT, 72, 0.015), LowPoly.at(Vector3(0, -0.60, 0)))
	# stone foot, pushed forward so it reads from the front and overhead
	out.merge(LowPoly.boulder(Vector3(0.27, 0.15, 0.36), 0, 0.14, STONE_DARK, 74 + side, 0.1), LowPoly.at(Vector3(0.0, -0.76, -0.08)))
	return out


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	if not idle_enabled or not is_inside_tree():
		return
	_t += delta
	var gp := global_position
	var moved := Vector2(gp.x - _last_pos.x, gp.z - _last_pos.z).length()
	_last_pos = gp
	var spd := moved / maxf(delta, 0.0001)
	_speed = lerpf(_speed, minf(spd, 6.0), clampf(delta * 10.0, 0.0, 1.0))
	apply_idle(_t, _speed)


## Pose the idle / walk cycle at time t (breathing, a slow head nod, stomping legs when moving).
func apply_idle(t: float, speed: float = 0.0) -> void:
	var walk := clampf(speed / 4.5, 0.0, 1.0)
	var breath := sin(t * 1.9)
	var stride := sin(t * 7.0)
	var body := parts["body"] as MeshInstance3D
	body.position.y = _body_base_y + breath * 0.018 - absf(stride) * 0.05 * walk
	body.scale = Vector3(1.0 + breath * 0.006, 1.0 + breath * 0.012, 1.0)
	(parts["head"] as MeshInstance3D).rotation.x = sin(t * 1.3) * 0.02 - 0.04 * walk
	(parts["leg_l"] as MeshInstance3D).rotation.x = stride * 0.5 * walk
	(parts["leg_r"] as MeshInstance3D).rotation.x = -stride * 0.5 * walk
	var sway := breath * 0.015
	(parts["arm_l"] as MeshInstance3D).rotation.x = ARM_FWD - stride * 0.28 * walk + sway + float(_arm_kick["arm_l"])
	(parts["arm_r"] as MeshInstance3D).rotation.x = ARM_FWD + stride * 0.28 * walk - sway + float(_arm_kick["arm_r"])


## A quick heavy punch with alternating arms: wind back, slam forward, recover.
func attack_swing() -> void:
	if not is_inside_tree():
		return
	var key := "arm_r" if _swing_next_right else "arm_l"
	_swing_next_right = not _swing_next_right
	_kick_arm(key, -0.6, 1.55, 0.06, 0.07, 0.30)
	var body := parts["body"] as MeshInstance3D
	var lean := create_tween()
	lean.tween_property(body, "rotation:x", 0.14, 0.07).set_trans(Tween.TRANS_SINE)
	lean.tween_property(body, "rotation:x", 0.0, 0.30).set_trans(Tween.TRANS_BACK)


## Both fists up for a cast (the hero's cast pose).
func cast_pose() -> void:
	if not is_inside_tree():
		return
	_kick_arm("arm_l", 0.0, 0.9, 0.1, 0.1, 0.5)
	_kick_arm("arm_r", 0.0, 0.9, 0.1, 0.1, 0.5)


func _kick_arm(key: String, windup: float, punch: float, t_wind: float, t_hit: float, t_back: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _arm_kick[key] = v, 0.0, windup, t_wind).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float) -> void: _arm_kick[key] = v, windup, punch, t_hit).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: _arm_kick[key] = v, punch, 0.0, t_back).set_trans(Tween.TRANS_BACK)


## Downed: greyed out; the hero lies the whole model down.
func set_downed(downed: bool) -> void:
	_mat.set_shader_parameter("desat", 0.85 if downed else 0.0)
	idle_enabled = not downed

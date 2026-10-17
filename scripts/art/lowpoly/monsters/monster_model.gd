class_name MonsterModel
extends LowPolyModel
## Shared base for the faceted monster models (GruntModel, ArcherModel, BruteModel, SwarmerModel).
## Same look as the hero models (flat facets, per-face paint, ink outline, amber rim) but with the
## ENEMY material (MonsterMaterial): ember eyes / lava cracks glow, heroes never do.
##
## Faces local -Z, +X is its right, origin at the feet. Idle / walk run by themselves from the model's
## own _process (walk speed is read from how far the model moved), exactly like the hero models.
##
## Monster hooks (all optional on the monster side):
##   windup(t)             0..1 attack telegraph pose (sword up, bow drawn, fists up, crouch). Hold it
##                         every frame from Monster._telegraph; windup(0.0) returns to the rest pose.
##   attack_swing()        the strike: a quick snap out of the telegraph and back (call at strike time).
##   set_downed(true)      death: glow off, greyed, limbs go slack (Monster still topples the Visual).
##   set_tint(colour, k)   additive hit flash / windup pulse (replaces Monster._apply_tint's materials).
##   set_fade(a)           1 -> 0 at the end of the death tween (the model shrinks away).
##   ui_height             top of the figure, for the hp bar.
##
## INTEGRATION (applied in monster.gd): Monster has a `model: MonsterModel` field, defaulted in _ready()
## from `kind` via MonsterModels.make(kind) (or set before add_child). `Monster.use_proto_visuals = true`
## (static) brings back the old primitive bodies. The hooks, all in monster.gd:
##   _ready()          model child of the Visual, bar_height = ui_height + 0.25, windup_scale = model_windup_scale
##                     (0.06, swarmer 0.12: the model's own pose does most of the telegraph)
##   _tick_attack()    model.attack_swing() right after the strike
##   _update_visual()  model.windup(_telegraph) every frame (before _pose)
##   _apply_tint()     model.set_tint(color, k) and return (the primitive _mats stay empty)
##   _set_fade()       model.set_fade(a) and return
##   _on_death()       model.set_downed(true) before the tweens (Monster still topples/sinks its Visual)
## Only Monster's _visual (never the model) is rotated / scaled / lowered by the Monster; the model owns its
## own scale (MODEL_SCALE, shrunk by set_fade). Shoves and pit falls move / spin / shrink the ACTOR node,
## so the model just rides along (its walk cycle reads the actor's motion).
##
## The kind scripts need NO change besides swarmer's model_windup_scale: their _pose() overrides are
## null-guarded (the primitive parts they animate are never built when the model is used) and
## _build_visual just is not called.

const SWING_TIME := 0.30
const GLOW_GAIN := 1.8

## Monster.kind this model is for ("grunt", "archer", "brute", "swarmer").
var monster_kind := "monster"

## How much the glow flares during the telegraph (1.0 = doubles).
var glow_flare := 0.5

var _wind := 0.0               ## windup(t), 0..1
var _swing := 0.0              ## attack_swing(): 1 right at the strike, easing to 0
var _downed := false
var _glow_now := GLOW_GAIN
var _base_scale := Vector3.ONE


func _setup_model(model_name: String, model_scale: float) -> void:
	super._setup_model(model_name, model_scale)
	_mat = MonsterMaterial.make(outline_px)
	_mat.set_shader_parameter("glow_gain", GLOW_GAIN)
	_base_scale = scale


# ------------------------------------------------------------------ monster hooks

## Attack telegraph pose, t in 0..1 (0 = rest).
func windup(t: float) -> void:
	if _downed:
		return
	_wind = clampf(t, 0.0, 1.0)
	_update_glow()
	_refresh()


## Eased windup (slow start, firm finish).
func wind_e() -> float:
	return _wind * _wind * (3.0 - 2.0 * _wind)


## The strike: snap out of the telegraph pose and settle back.
func attack_swing() -> void:
	if _downed:
		return
	if _swing_tween != null and _swing_tween.is_valid():
		_swing_tween.kill()
	_swing = 1.0
	_refresh()
	if not is_inside_tree():
		return
	_swing_tween = create_tween()
	_swing_tween.tween_method(_set_swing, 1.0, 0.0, SWING_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_swing(v: float) -> void:
	_swing = v
	_update_glow()
	_refresh()


## Eyes / cracks flare a little in the telegraph and the strike (enemy language).
func _update_glow() -> void:
	if _downed:
		return
	var g := GLOW_GAIN * (1.0 + glow_flare * wind_e() + 0.4 * _swing)
	if absf(g - _glow_now) > 0.01:
		_glow_now = g
		_mat.set_shader_parameter("glow_gain", g)


func is_downed() -> bool:
	return _downed


## Death: glow out, greyed, limbs slack. (The Monster topples and sinks its Visual itself.)
func set_downed(downed: bool) -> void:
	super.set_downed(downed)
	_downed = downed
	_glow_now = 0.0 if downed else GLOW_GAIN
	_mat.set_shader_parameter("glow_gain", _glow_now)
	if downed:
		_wind = 0.0
		_swing = 0.0
		if _swing_tween != null and _swing_tween.is_valid():
			_swing_tween.kill()
		_slump()
	else:
		apply_idle(_t, 0.0)


## Additive tint: Monster's white hit flash and orange windup pulse. k = 0 clears it.
func set_tint(color: Color, k: float) -> void:
	_mat.set_shader_parameter("tint_color", color)
	_mat.set_shader_parameter("tint_k", clampf(k, 0.0, 1.0))


## Fade-out at the end of the death: shrink away (an opaque toon shader cannot alpha-fade).
func set_fade(a: float) -> void:
	scale = _base_scale * maxf(a, 0.001)


## Frozen pose for the lab / screenshots: kind is "rest", "windup" (k = telegraph) or "swing" (k = swing).
func pose_preview(kind: String, k: float = 1.0) -> void:
	_wind = 0.0
	_swing = 0.0
	match kind:
		"windup":
			_wind = clampf(k, 0.0, 1.0)
		"swing":
			_swing = clampf(k, 0.0, 1.0)
	_update_glow()
	apply_idle(0.6, 0.0)


## When nothing drives the idle loop (frozen lab, headless test, downed) re-pose after a state change.
func _refresh() -> void:
	if not idle_enabled and not _downed:
		apply_idle(_t, _speed)


## Subclass: relax every limb (downed).
func _slump() -> void:
	pass


# ------------------------------------------------------------------ mesh helpers

## Colour for EMISSIVE faces (ember eyes, lava cracks): alpha 0.5 is what MonsterMaterial reads.
static func glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, MonsterMaterial.GLOW_ALPHA)


## A tapered bone / horn / spike from a to b (radius r_a at a, r_b at b), merged into `s`.
static func limb(s: LowPoly.Soup, a: Vector3, b: Vector3, r_a: float, r_b: float, sides: int, col: Color, seed_value: int, jit: float = 0.0, vary: float = 0.07) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.0001:
		return
	var q := Quaternion(Vector3.UP, d / length)
	s.merge(LowPoly.cylinder(r_a, r_b, length, sides, col, seed_value, jit, 1, vary), Transform3D(Basis(q), (a + b) * 0.5))


## A faceted lump (jittered icosphere) merged at `pos`.
static func blob(s: LowPoly.Soup, pos: Vector3, radii: Vector3, col: Color, seed_value: int, jit: float = 0.15, detail: int = 0, rot_deg: Vector3 = Vector3.ZERO, vary: float = 0.07) -> void:
	s.merge(LowPoly.boulder(radii, detail, jit, col, seed_value, vary), LowPoly.at(pos, rot_deg))


## A box merged at `pos` (optionally rotated, chiselled).
static func slab(s: LowPoly.Soup, pos: Vector3, size: Vector3, col: Color, seed_value: int, rot_deg: Vector3 = Vector3.ZERO, jit: float = 0.0, vary: float = 0.06) -> void:
	s.merge(LowPoly.box(size, col, seed_value, jit, 1, vary), LowPoly.at(pos, rot_deg))


## A frustum merged at `pos`: bottom (w, d), top (w, d), height h.
static func wedge(s: LowPoly.Soup, pos: Vector3, bottom: Vector2, top: Vector2, h: float, col: Color, seed_value: int, rot_deg: Vector3 = Vector3.ZERO, jit: float = 0.0, vary: float = 0.06) -> void:
	s.merge(LowPoly.frustum(bottom, top, h, col, seed_value, jit, 1, Vector2.ZERO, vary), LowPoly.at(pos, rot_deg))


## Re-aim a hanging limb part (its soup hangs down local -Y from the pivot) so its end reaches `target`
## (in the parent's space); the length is stretched a little so the hand still meets the target.
func aim_limb(limb_part: MeshInstance3D, target: Vector3, rest_len: float) -> void:
	var d := target - limb_part.position
	var l := d.length()
	if l < 0.001:
		return
	limb_part.basis = Basis(Quaternion(Vector3.DOWN, d / l)).scaled(Vector3(1.0, clampf(l / rest_len, 0.6, 1.25), 1.0))

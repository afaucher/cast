extends Node3D
## LOOK-DEV ONLY (docs/design/animation-research.md): the proposed procedural "feel" layer for a faceted hero model, used
## by the animation lab (scripts/art/lowpoly/anim_lab.gd) and NOT wired into the game. It sits between Hero._visual (the
## yaw) and the LowPolyModel, takes the model's clock over (idle_enabled = false) and adds, from nothing but the hero's
## shown position, facing and the events every screen already sees:
##
##   level 1 "grounded":  stride matched to ground speed (the model's clock runs at the speed its legs need: no skating),
##                        legs turned toward the way the hero walks (strafe, backpedal: no moonwalk), a lean that leads
##                        the velocity (springy: overshoots on a stop, banks in a turn), squash on start and stop.
##   level 2 "+ actions": a voice-cast CHANNEL (speech -> the trigger word -> the spell: the hero gathers, then releases on
##                        the spell), hit reactions (a flinch away from the blow, a 4-frame hit-stop, a shake), a
##                        strike-first melee (no wind-up after the click: the blow lands on the frame it resolves) with a
##                        lunge and an attacker hit-stop.
##
## Everything is cosmetic and derived (no new net state): velocity from the position delta works on a puppet as it does
## on the owner. No randomness.

## Per-model tuning. leg: hip-to-sole length (model units x scale); amp: the model's own stride swing (rad at walk 1);
## omega: the model's own stride rate (rad/s in its apply_idle); walk_ref: the speed its apply_idle calls walk 1;
## amp_mult: extra swing (Gasket's stubby legs); lean: speed-lean (rad per unit/s); kick: acceleration lean (rad per unit/s
## of velocity change); f / zeta: the lean spring (Hz, damping: lower f = heavier, lower zeta = more overshoot).
const TUNING := {
	"wick": {"leg": 0.92, "amp": 0.60, "omega": 9.0, "walk_ref": 4.0, "amp_mult": 1.0,
			"lean": 0.032, "kick": 0.075, "f": 2.6, "zeta": 0.42, "squash": 1.0},
	"gasket": {"leg": 0.46, "amp": 0.55, "omega": 8.0, "walk_ref": 4.0, "amp_mult": 1.45,
			"lean": 0.028, "kick": 0.065, "f": 3.2, "zeta": 0.50, "squash": 1.2},
	"rebar": {"leg": 1.17, "amp": 0.50, "omega": 7.0, "walk_ref": 4.5, "amp_mult": 1.0,
			"lean": 0.018, "kick": 0.045, "f": 1.7, "zeta": 0.65, "squash": 0.6},
}
const LEAN_MAX := 0.38
const HITSTOP_FRAMES := 4          ## a victim's freeze (~67 ms at 60 fps)
const ATTACK_HITSTOP_FRAMES := 3   ## the attacker's freeze when its blow connects (~50 ms)

var model: LowPolyModel
var hero: Hero
var kind := "wick"
var level := 1

var _tu: Dictionary
var _prev := Vector3.INF
var _v_smooth := Vector3.ZERO      ## velocity through a critically damped spring (the "body mass")
var _speed := 0.0
var _t := 0.0                      ## the model's clock (apply_idle time)
var _lean := Vector2.ZERO          ## x = pitch, y = roll (rad), and its spring velocity
var _lean_v := Vector2.ZERO
var _sq := 0.0                     ## squash (+) / stretch (-), spring
var _sq_v := 0.0
var _sq_bias := 0.0                ## a held crouch (the channel)
var _moving := false
var _leg_yaw := 0.0
var _leg_rest := {}                ## leg part -> rest position
var _head_whip := Vector2.ZERO
var _head_whip_v := Vector2.ZERO
var _freeze := 0                   ## hit-stop frames left
var _shake := 0.0
var _lunge := 0.0                  ## forward visual offset of a strike (decays)
var _frame := 0
# The voice channel: 0 idle, "listen" while the player talks, "armed" once the cast word is heard, "release" on the spell.
var _channel := 0.0
var _channel_target := 0.0
var _glow: MeshInstance3D = null
var _glow_mat: StandardMaterial3D = null
var _release_t := -1.0
var _gather: MeshInstance3D = null
var _gather_mat: StandardMaterial3D = null


func setup(h: Hero, m: LowPolyModel, k: String, lvl: int) -> void:
	hero = h
	model = m
	kind = k
	level = lvl
	_tu = TUNING[k]
	model.idle_enabled = false
	for side in ["leg_l", "leg_r"]:
		_leg_rest[side] = (model.parts[side] as Node3D).position


func _spring(x: float, v: float, target: float, f: float, zeta: float, dt: float) -> Vector2:
	var w := TAU * f
	v += (w * w * (target - x) - 2.0 * zeta * w * v) * dt
	x += v * dt
	return Vector2(x, v)


## One frame (the lab calls it after the hero moved).
func step(dt: float) -> void:
	_frame += 1
	var pos := hero.global_position
	if _prev == Vector3.INF:
		_prev = pos
	var raw := (pos - _prev) / dt
	raw.y = 0.0
	_prev = pos
	if raw.length() > 20.0:
		raw = Vector3.ZERO   # a teleport (the lab's reset)

	# --- hit-stop: everything on the model holds still (its tweens too), with a small shake ---------------------------
	if _freeze > 0:
		_freeze -= 1
		model.process_mode = Node.PROCESS_MODE_DISABLED
		model.position = Vector3(_shake * (1.0 if _frame % 2 == 0 else -1.0), 0.0, 0.0)
		return
	model.process_mode = Node.PROCESS_MODE_INHERIT
	_shake = 0.0

	# --- the body: a critically damped velocity, the lean that leads it ---------------------------------------------
	_v_smooth += (raw - _v_smooth) * clampf(dt * 9.0, 0.0, 1.0)
	_speed = lerpf(_speed, raw.length(), clampf(dt * 14.0, 0.0, 1.0))
	var yaw := (get_parent() as Node3D).rotation.y
	var local_v := _v_smooth.rotated(Vector3.UP, -yaw)
	var local_kick := (raw - _v_smooth).rotated(Vector3.UP, -yaw)
	var lean_vec := local_v * float(_tu["lean"]) + local_kick * float(_tu["kick"])   # where the head goes
	var target := Vector2(clampf(lean_vec.z, -LEAN_MAX, LEAN_MAX), clampf(-lean_vec.x, -LEAN_MAX, LEAN_MAX))
	var px := _spring(_lean.x, _lean_v.x, target.x, float(_tu["f"]), float(_tu["zeta"]), dt)
	var py := _spring(_lean.y, _lean_v.y, target.y, float(_tu["f"]), float(_tu["zeta"]), dt)
	_lean = Vector2(px.x, py.x)
	_lean_v = Vector2(px.y, py.y)

	# --- squash on start / stop ----------------------------------------------------------------------------------
	var moving := raw.length() > 0.5
	if moving != _moving:
		_sq_v += (-0.9 if moving else 1.3) * float(_tu["squash"])
		_moving = moving
	var s := _spring(_sq, _sq_v, _sq_bias, 4.5, 0.32, dt)
	_sq = clampf(s.x, -0.16, 0.2)
	_sq_v = s.y
	scale = Vector3(1.0 + _sq * 0.5, 1.0 - _sq, 1.0 + _sq * 0.5)
	rotation = Vector3(_lean.x, 0.0, _lean.y)

	# --- stride matched to the ground: run the model's clock at the rate its legs need -------------------------------
	var omega_m := float(_tu["omega"])
	var walk := clampf(_speed / float(_tu["walk_ref"]), 0.0, 1.0)
	var amp := float(_tu["amp"]) * float(_tu["amp_mult"]) * maxf(walk, 0.05)
	var omega_match := _speed / (float(_tu["leg"]) * amp)
	var rate := lerpf(omega_m, omega_match, smoothstep(0.0, 0.25, walk))
	_t += dt * rate / omega_m

	# --- the action layer drives the arm kicks it owns before the pose is built ---------------------------------------
	if level >= 2:
		_step_channel(dt)
	model.apply_idle(_t, _speed)

	# --- legs: the swing amplitude, then turned toward the way the hero walks (strafe, backpedal) ----------------------
	var a := atan2(local_v.x, -local_v.z) if _v_smooth.length() > 0.4 else 0.0
	var back := absf(a) > deg_to_rad(110.0)
	var leg_target := -(wrapf(a - PI, -PI, PI) if back else a) * 0.85
	leg_target = clampf(leg_target, -1.35, 1.35) * smoothstep(0.2, 1.2, _v_smooth.length())
	_leg_yaw = lerp_angle(_leg_yaw, leg_target, clampf(dt * 14.0, 0.0, 1.0))
	for side: String in _leg_rest:
		var leg := model.parts[side] as Node3D
		var r := leg.rotation
		r.y = 0.0   # (last frame's yaw: apply_idle rewrites only the swing)
		r.x *= float(_tu["amp_mult"]) * (-1.0 if back else 1.0)
		leg.basis = Basis(Vector3.UP, _leg_yaw) * Basis.from_euler(r)
		leg.position = Basis(Vector3.UP, _leg_yaw) * (_leg_rest[side] as Vector3)

	# --- reactions: the head whip and the strike lunge ----------------------------------------------------------------
	if level >= 2:
		var hx := _spring(_head_whip.x, _head_whip_v.x, 0.0, 3.5, 0.35, dt)
		var hy := _spring(_head_whip.y, _head_whip_v.y, 0.0, 3.5, 0.35, dt)
		_head_whip = Vector2(hx.x, hy.x)
		_head_whip_v = Vector2(hx.y, hy.y)
		var head := model.parts["head"] as Node3D
		head.rotation.x += _head_whip.x
		head.rotation.z += _head_whip.y
		_lunge = lerpf(_lunge, 0.0, clampf(dt * 10.0, 0.0, 1.0))
		model.position = Vector3(0.0, 0.0, -_lunge)


# --- Events (in the game these come from signals every screen already has) -------------------------------------------

## A blow from `from_dir` (world X/Z, pointing from the attacker to the hero) of `amount` damage.
func on_hit(from_dir: Vector3, amount: float) -> void:
	if level < 2:
		return
	var yaw := (get_parent() as Node3D).rotation.y
	var d := from_dir.rotated(Vector3.UP, -yaw)
	var k := clampf(amount / 12.0, 0.4, 1.6)
	_lean_v += Vector2(d.z, -d.x) * 9.0 * k        # the body rocks away from the blow
	_head_whip_v += Vector2(d.z, -d.x) * 14.0 * k  # the head snaps further
	_sq_v += 1.6 * k
	_freeze = HITSTOP_FRAMES
	_shake = 0.08


## The hero swung (melee): strike first (no wind-up after the click), lunge, and a short freeze when it connects.
func on_attack(connects: bool) -> void:
	if level < 2:
		return
	match kind:
		"wick":
			model._kick_arm("bash", 0.9, -1.3, 0.017, 0.05, 0.34)
		"gasket":
			model._kick_arm("weapon", 1.0, -1.35, 0.017, 0.06, 0.36)
		"rebar":
			var key := "arm_r" if model.get("_swing_next_right") else "arm_l"
			model.set("_swing_next_right", not bool(model.get("_swing_next_right")))
			model._kick_arm(key, -0.4, 1.6, 0.017, 0.05, 0.32)
	_lean_v.x -= 3.2      # pitch the head forward into the blow
	_lunge = 0.16
	_sq_v -= 0.6
	if connects:
		_freeze_later(4, ATTACK_HITSTOP_FRAMES)


func _freeze_later(frames_from_now: int, n: int) -> void:
	await get_tree().create_timer(frames_from_now / 60.0, true, false, true).timeout
	_freeze = n
	_shake = 0.02


## The player started talking (VoiceCaster.speech_started): a small "listening" gather.
func on_speech() -> void:
	if level >= 2:
		_channel_target = 0.35


## The cast word was heard (VoiceCaster.trigger_heard): the hero gathers for real.
func on_armed() -> void:
	if level >= 2:
		_channel_target = 0.75


## The spell went off (Hero.spell_cast; online, aim the peak at the cast's landing time).
func on_cast() -> void:
	if level < 2:
		return
	_channel_target = 0.0
	_channel = 0.0
	_release_t = 0.0
	match kind:
		"wick":
			model._kick_arm("cast", 0.7, 1.15, 0.017, 0.05, 0.5)
		"gasket":
			model._kick_arm("weapon", 0.7, 1.05, 0.017, 0.05, 0.5)
		"rebar":
			model._kick_arm("arm_l", 0.6, 1.1, 0.017, 0.05, 0.5)
			model._kick_arm("arm_r", 0.6, 1.1, 0.017, 0.05, 0.5)
	_sq_v -= 1.6          # stretch up and out
	_lean_v.x -= 2.6      # the body throws forward
	if _glow != null:
		Fx.flash_sphere(_glow.global_position, 0.55, Color(0.55, 0.95, 1.0, 0.9), 0.22)
		Fx.ring(hero.global_position, 1.1, Color(0.5, 0.9, 1.0, 0.7), 0.3, 0.0, false, 0.3)


## The utterance ended with no spell (a fizzle or plain talk): the gather lets go.
func on_fizzle() -> void:
	_channel_target = 0.0


func _step_channel(dt: float) -> void:
	_channel = move_toward(_channel, _channel_target, dt * (2.6 if _channel_target > _channel else 4.0))
	var c := _channel
	var tremble := sin(_t * 47.0) * 0.04 * c
	match kind:
		"wick":
			if _release_t < 0.0 or _release_t > 0.6:
				model._arm_kick["cast"] = c * 0.95 + tremble
		"gasket":
			if _release_t < 0.0 or _release_t > 0.6:
				model._arm_kick["weapon"] = c * 0.55 + tremble
		"rebar":
			if _release_t < 0.0 or _release_t > 0.6:
				model._arm_kick["arm_l"] = c * 0.75 + tremble
				model._arm_kick["arm_r"] = c * 0.75 - tremble
	_sq_bias = 0.07 * c                 # a crouch while gathering
	if _release_t >= 0.0:
		_release_t += dt
	_update_glow(c)


## A cool glow at the casting hand that swells with the channel (the only cool light in a warm room).
func _update_glow(c: float) -> void:
	if _glow == null:
		_glow = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 10
		sm.rings = 5
		_glow.mesh = sm
		_glow_mat = Fx.glow_material(Color(0.55, 0.95, 1.0, 0.85))
		_glow.material_override = _glow_mat
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow.set_meta("no_flash", true)
		var host: Node3D = model.parts["wand"] if kind == "wick" else (model.hold_anchor if model.hold_anchor != null else model.parts["body"])
		host.add_child(_glow)
		_glow.position = Vector3(0, 0.5, 0) if kind == "wick" else Vector3(0, 0.15, 0)
	var flick := 1.0 + 0.12 * sin(_t * 31.0)
	var k := (0.08 + 0.45 * c) * flick if c > 0.02 else 0.0
	_glow.visible = k > 0.0
	_glow.scale = Vector3.ONE * maxf(k, 0.001) / model.scale.x
	# the gather ring on the floor: wide and faint as the player starts talking, drawing in and brightening once the cast
	# word is heard (reads from the steep camera, where the hand is a few pixels)
	if _gather == null:
		_gather = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.92
		torus.outer_radius = 1.0
		torus.rings = 40
		torus.ring_segments = 6
		_gather.mesh = torus
		_gather_mat = Fx.glow_material(Color(0.55, 0.95, 1.0, 0.0))
		_gather.material_override = _gather_mat
		_gather.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gather.set_meta("no_flash", true)
		_gather.position = Vector3(0, 0.06, 0)
		hero.add_child(_gather)
	_gather.visible = c > 0.02
	var r := lerpf(1.6, 0.8, c)
	_gather.scale = Vector3(r, 0.12, r)
	_gather_mat.albedo_color = Color(0.55, 0.95, 1.0, 0.25 + 0.6 * c)

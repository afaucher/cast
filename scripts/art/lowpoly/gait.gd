class_name Gait
extends RefCounted
## The stride clock and the legs of a faceted hero model, driven by the ground it covers (shared by the movement feel
## and the animation research: docs/design/movement-research.md "As built" and animation-research.md §1.2 / §7).
## Lifted from anim_lab_feel.gd's level 1 (which now runs on it, so the lab's lane B and the game are the same code):
##
##   - STRIDE MATCHED TO THE GROUND: the model's apply_idle clock runs at the rate its legs need for the speed shown, so
##     the planted foot sweeps back at the ground speed (no skating at the bow's 0.5x, wading's 0.75x or coffee's 1.6x).
##     The rate is speed / (leg x amp): distance walked, not time. Standing, the clock runs at the model's own rate (the
##     idle fidget is unchanged).
##   - LEGS TOWARD THE TRAVEL: the legs turn (up to about 77 degrees) toward the way the hero walks relative to where it
##     faces (the twin-stick split: the body faces the aim), and past BACK_DEG the swing is mirrored: a backpedal.
##
## Everything is cosmetic and derived from the position every screen shows (a puppet's too); no randomness, no net state.
## The model's own _process is switched off while a Gait drives it (idle_enabled = false) and back on by release().

## Per-model tuning. leg: hip-to-sole length (model units x scale); amp: the model's own stride swing (rad at walk 1);
## omega: the model's own stride rate (rad/s in its apply_idle); walk_ref: the speed its apply_idle calls walk 1;
## amp_mult: extra swing (Gasket's stubby legs).
const TUNING := {
	"wick": {"leg": 0.92, "amp": 0.60, "omega": 9.0, "walk_ref": 4.0, "amp_mult": 1.0},
	"gasket": {"leg": 0.46, "amp": 0.55, "omega": 8.0, "walk_ref": 4.0, "amp_mult": 1.45},
	"rebar": {"leg": 1.17, "amp": 0.50, "omega": 7.0, "walk_ref": 4.5, "amp_mult": 1.0},
}
## Past this angle between the travel and the facing the stride is mirrored (a backpedal).
const BACK_DEG := 110.0
## A foot plant counts (plants, for footsteps) only above this share of a full stride.
const PLANT_WALK := 0.3

var model: LowPolyModel
var kind := "wick"
var v_smooth := Vector3.ZERO      ## velocity through a smoothing spring (X/Z), units/s
var speed := 0.0                  ## the shown speed, smoothed
var t := 0.0                      ## the model's clock (apply_idle time)
var leg_yaw := 0.0
var back := false                 ## walking backwards (the swing is mirrored)
var plants := 0                   ## foot plants so far (a footstep each)

var _tu: Dictionary
var _leg_rest := {}               ## leg part -> rest position
var _leg_rot := {}                ## leg part -> rest rotation
var _plant_idx := 0


## True when `m` is a model a Gait can drive (`kind` is the hero's kit: wick, gasket, rebar).
static func supports(m: Node, k: String) -> bool:
	var lp := m as LowPolyModel
	return lp != null and TUNING.has(k) and lp.parts.has("leg_l") and lp.parts.has("leg_r")


func _init(m: LowPolyModel, k: String) -> void:
	model = m
	kind = k if TUNING.has(k) else "wick"
	_tu = TUNING[kind]
	model.idle_enabled = false
	for side in ["leg_l", "leg_r"]:
		_leg_rest[side] = (model.parts[side] as Node3D).position
		_leg_rot[side] = (model.parts[side] as Node3D).rotation


## One frame of shown motion: `raw` is the X/Z velocity the hero showed this frame (the position change / dt).
func advance(raw: Vector3, dt: float) -> void:
	model.idle_enabled = false   # (a revival turns the model's own clock back on: this one drives it)
	raw.y = 0.0
	v_smooth += (raw - v_smooth) * clampf(dt * 9.0, 0.0, 1.0)
	speed = lerpf(speed, raw.length(), clampf(dt * 14.0, 0.0, 1.0))
	var omega_m := float(_tu["omega"])
	var walk := clampf(speed / float(_tu["walk_ref"]), 0.0, 1.0)
	var amp := float(_tu["amp"]) * float(_tu["amp_mult"]) * maxf(walk, 0.05)
	var omega_match := speed / (float(_tu["leg"]) * amp)
	var rate := lerpf(omega_m, omega_match, smoothstep(0.0, 0.25, walk))
	t += dt * rate / omega_m
	# a foot plants where sin(t * omega) peaks (the legs farthest apart)
	var idx := floori((t * omega_m - PI * 0.5) / PI)
	if idx != _plant_idx:
		_plant_idx = idx
		if walk >= PLANT_WALK:
			plants += 1


## The share of a full stride the legs swing right now (0 standing, 1 at the model's walk_ref).
func walk_amount() -> float:
	return clampf(speed / float(_tu["walk_ref"]), 0.0, 1.0)


## Pose the model: its idle / walk cycle at the matched clock, then the legs turned toward the travel. `yaw` is the
## drawn body's yaw (Hero._visual's rotation.y).
func pose(yaw: float, dt: float) -> void:
	model.apply_idle(t, speed)
	var local_v := v_smooth.rotated(Vector3.UP, -yaw)
	var a := atan2(local_v.x, -local_v.z) if v_smooth.length() > 0.4 else 0.0
	back = absf(a) > deg_to_rad(BACK_DEG)
	var leg_target := -(wrapf(a - PI, -PI, PI) if back else a) * 0.85
	leg_target = clampf(leg_target, -1.35, 1.35) * smoothstep(0.2, 1.2, v_smooth.length())
	leg_yaw = lerp_angle(leg_yaw, leg_target, clampf(dt * 14.0, 0.0, 1.0))
	for side: String in _leg_rest:
		var leg := model.parts[side] as Node3D
		var r := leg.rotation
		r.y = 0.0   # (last frame's yaw: apply_idle rewrites only the swing)
		r.x *= float(_tu["amp_mult"]) * (-1.0 if back else 1.0)
		leg.basis = Basis(Vector3.UP, leg_yaw) * Basis.from_euler(r)
		leg.position = Basis(Vector3.UP, leg_yaw) * (_leg_rest[side] as Vector3)


## Hand the model back to its own clock: legs at rest, idle on (`idle` false: a downed model stays still).
func release(idle: bool = true) -> void:
	if not is_instance_valid(model):
		return
	for side: String in _leg_rest:
		var leg := model.parts[side] as Node3D
		leg.rotation = _leg_rot[side]
		leg.position = _leg_rest[side]
	model.idle_enabled = idle

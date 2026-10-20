class_name WaterBoyModel
extends "res://scripts/art/lowpoly/monsters/cooler_carriers.gd".WaterboyModel
## The Water Boy's game model (MonsterDefs kind "water_boy", scripts/monsters/water_boy.gd; docs/design/enemy-healer-options.md
## §7, recommended and built as the default, 2026-10-20): round 2's goblin sports medic wheeling the water cooler on a hand
## truck (CoolerCarriers' "waterboy" blockout), with the monster hooks:
##   windup(t)       the pour's tell: the whistle comes up to its mouth (0.8 s)
##   attack_swing()  the pour: it rocks back blowing the whistle and the truck tips the cooler forward
## The glow stays on the water (the jug) and the monsters' small ember eyes: the tell does not flare it (glow_flare 0).

## The rigid parts the game animates (test_monster_models).
const PART_NAMES: Array[String] = ["body", "head", "ear_l", "ear_r", "arm_l", "arm_r", "leg_l", "leg_r", "truck", "jug"]


func _init() -> void:
	super()
	monster_kind = "water_boy"
	glow_flare = 0.0


func windup(t: float) -> void:
	if _downed:
		return
	heal_k = clampf(t, 0.0, 1.0)   # (the carrier's whistle pose; set_heal would also flare the whole material)
	super.windup(t)


func apply_idle(t: float, speed: float = 0.0) -> void:
	super.apply_idle(t, speed)
	if _downed:
		return
	var truck := parts["truck"] as MeshInstance3D
	truck.rotation.x = deg_to_rad(TRUCK_TILT) + 0.30 * _swing
	(parts["body"] as MeshInstance3D).rotation.x -= 0.45 * _swing
	(parts["head"] as MeshInstance3D).rotation.x -= 0.30 * _swing

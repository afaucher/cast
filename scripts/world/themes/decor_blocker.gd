class_name DecorBlocker
extends Actor
## The invisible, immovable, undamageable circle behind a walk-blocking decor piece: a neutral Actor, so the
## existing soft-circle separation (Actor._separate) keeps heroes and monsters out of it. Never targeted
## (not in the "employees" group), never hurt (area spells that hit neutral actors do nothing), never shoved.


func _init() -> void:
	team = GameWorld.TEAM_NEUTRAL
	shove_mult = 0.0
	max_hp = 1.0e9
	display_name = "Decor"


func apply_damage(_amount: float, _source: Node = null) -> float:
	return 0.0


func heal(_amount: float) -> float:
	return 0.0


func die() -> void:
	pass

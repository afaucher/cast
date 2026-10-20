class_name TentaclesSpell
extends SpellDef
## Tentacles: neon tentacles burst from the floor where you aim (Tentacles, a scheduled effect) and shove everyone outward.

const ID := "tentacles"
const FOLLOWS := false

const TENTACLES_RADIUS_BASE := 2.2
const TENTACLES_RADIUS_POWER := 0.8
const TENTACLES_SHOVE_BASE := 2.5
const TENTACLES_SHOVE_POWER := 1.5
const TENTACLES_DAMAGE := 6.0     ## monsters only, times power


static func tentacles_radius(power: float) -> float:
	return TENTACLES_RADIUS_BASE + TENTACLES_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


## World units everyone in the radius is shoved (before each actor's shove_mult).
static func tentacles_distance(power: float) -> float:
	return TENTACLES_SHOVE_BASE + TENTACLES_SHOVE_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func tentacles_damage(power: float) -> float:
	return TENTACLES_DAMAGE * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, start: float, _extra: Dictionary) -> Node:
	var t := Tentacles.new()
	t.power = clampf(power, SpellBook.MIN_POWER, 1.0)
	t.source_team = caster.team
	t.caster = caster
	t.start_time = start
	GameWorld.spawn(t, target)
	return t

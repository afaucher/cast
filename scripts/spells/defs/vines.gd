class_name VinesSpell
extends SpellDef
## Vines: thorny vines burst up where you aim (Vines, a scheduled effect) and root everyone in the area.

const ID := "vines"
const FOLLOWS := false

const VINES_RADIUS_BASE := 2.4
const VINES_RADIUS_POWER := 0.6
const VINES_ROOT_BASE := 1.6       ## seconds rooted at power ~0
const VINES_ROOT_POWER := 0.6      ## ... plus this at power 1 (2.2 s)


## Everyone (any team) within this of the aim point is rooted.
static func vines_radius(power: float) -> float:
	return VINES_RADIUS_BASE + VINES_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


## Seconds the roots hold.
static func vines_duration(power: float) -> float:
	return VINES_ROOT_BASE + VINES_ROOT_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, start: float, _extra: Dictionary) -> Node:
	var v := Vines.new()
	v.power = clampf(power, SpellBook.MIN_POWER, 1.0)
	v.source_team = caster.team
	v.caster = caster
	v.start_time = start
	GameWorld.spawn(v, target)
	return v

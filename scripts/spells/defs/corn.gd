class_name CornSpell
extends SpellDef
## Corn: a giant corn cob falls from the sky where you aim (CornStrike, a scheduled effect) and hits everyone.

const ID := "corn"
const FOLLOWS := false


static func corn_damage(power: float) -> float:
	return CornStrike.DAMAGE * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, start: float, _extra: Dictionary) -> Node:
	var strike := CornStrike.new()
	strike.power = clampf(power, SpellBook.MIN_POWER, 1.0)
	strike.source_team = caster.team
	strike.caster = caster
	strike.start_time = start
	GameWorld.spawn(strike, target)
	return strike

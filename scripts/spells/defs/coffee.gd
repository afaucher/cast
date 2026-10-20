class_name CoffeeSpell
extends SpellDef
## Coffee: everyone in a small radius gets haste, then a crash (Coffee, scripts/spells/coffee.gd). A support spell: it
## follows the teammate the aim snapped onto.

const ID := "coffee"
const FOLLOWS := true

const COFFEE_RADIUS_BASE := 1.5    ## a SMALL radius
const COFFEE_RADIUS_POWER := 0.5
const COFFEE_MOVE_MULT := 1.6      ## +60% walking speed
const COFFEE_ATTACK_MULT := 1.6    ## +60% attack speed (cooldowns divide by it)
const COFFEE_TIME_BASE := 4.5      ## seconds of haste at power ~0
const COFFEE_TIME_POWER := 1.5     ## ... plus this at power 1 (6 s)
const COFFEE_CRASH_MULT := 0.7     ## -30% move and attack speed
const COFFEE_CRASH_TIME := 2.0


static func coffee_radius(power: float) -> float:
	return COFFEE_RADIUS_BASE + COFFEE_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


## Seconds of haste before the crash.
static func coffee_duration(power: float) -> float:
	return COFFEE_TIME_BASE + COFFEE_TIME_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, _start: float, _extra: Dictionary) -> Node:
	Coffee.cast(caster, power, target)
	return null

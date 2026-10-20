class_name CoffeeSpell
extends SpellDef
## Coffee: everyone in a small radius gets haste, then a crash (Coffee, scripts/spells/coffee.gd). A support spell: it
## follows the teammate the aim snapped onto. Design record: docs/design/spells.md.

const ID := "coffee"
const FOLLOWS := true

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Coffee", "cooldown": 14.0, "color": Color(0.66, 0.43, 0.24),
	"desc": "Everyone in a small radius gets +60% move and attack speed for six seconds, twitchy, then a crash. Monsters too.", "word": "coffee",
	"component": "Coffee beans", "available": true,
}

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


# --- The component: Coffee beans (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.06
const BEAN := Color(0.48, 0.28, 0.14)
const BEAN_LIGHT := Color(0.66, 0.42, 0.22)
const BEAN_DARK := Color(0.22, 0.12, 0.06)


static func _bean(seed_value: int, size: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.07)
	s.merge(LowPoly.boulder(Vector3(0.09, 0.13, 0.075) * size, 1, 0.05, BEAN, seed_value + 1, 0.06))
	s.merge(LowPoly.boulder(Vector3(0.05, 0.07, 0.03) * size, 0, 0.10, BEAN_LIGHT, seed_value + 2, 0.05), LowPoly.at(Vector3(-0.025, 0.02, -0.05) * size))   # a glossy highlight
	s.merge(LowPoly.box(Vector3(0.016, 0.22, 0.03) * size, BEAN_DARK, seed_value + 3, 0.0, 1, 0.04), LowPoly.at(Vector3(0.0, 0.0, 0.062) * size, Vector3(0, 0, 8)))   # the groove
	return s


## Three roasted beans with their grooves.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(841, 0.05)
	s.merge(_bean(842, 1.5), LowPoly.at(Vector3(-0.1, -0.02, 0.0), Vector3(20, 15, 25)))
	s.merge(_bean(846, 1.35), LowPoly.at(Vector3(0.1, -0.04, 0.04), Vector3(-25, -20, -35)))
	s.merge(_bean(850, 1.4), LowPoly.at(Vector3(0.0, 0.05, -0.1), Vector3(60, 10, 70)))
	return s

class_name TentaclesSpell
extends SpellDef
## Tentacles: neon tentacles burst from the floor where you aim (Tentacles, a scheduled effect) and shove everyone outward.

const ID := "tentacles"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Tentacles", "cooldown": 10.0, "color": Color(0.75, 0.2, 1.0),
	"desc": "Neon tentacles burst from the floor where you aim and shove EVERYONE outward.", "word": "tentacles",
	"component": "Neon ichor", "available": true,
}

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table).
## Aliases are measured mishearings only, all below the 0.85 bare-match floor so none can fire without the trigger
## (see the TENTACLES note in Incantation's header).
const VOICE := {
	"tentacles": 1.0, "tentacle": 1.0,
	"headacles": 0.8, "headacle": 0.75, "headagle": 0.75, "acles": 0.75,
	"tenacles": 0.8, "temicals": 0.7,   # the voice log to 2026-10-24: "TENACLES" 6 misses, "TEMICALS" 1
}

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


# --- The component: Neon ichor (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.45
const ICHOR := Color(0.78, 0.22, 1.0)
const ICHOR_LIGHT := Color(0.95, 0.62, 1.0)
const ICHOR_DARK := Color(0.46, 0.10, 0.70)
const GLASS := Color(0.62, 0.40, 0.90)


## A glowing purple flask of ichor with a cork.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(751, 0.06)
	s.merge(LowPoly.boulder(Vector3(0.20, 0.19, 0.20), 1, 0.07, ICHOR, 752, 0.06), LowPoly.at(Vector3(0.0, -0.07, 0.0)))
	s.merge(LowPoly.boulder(Vector3(0.12, 0.05, 0.12), 0, 0.12, ICHOR_LIGHT, 753, 0.05), LowPoly.at(Vector3(-0.02, 0.04, -0.08)))   # glassy highlight
	s.merge(LowPoly.cylinder(0.065, 0.075, 0.13, 6, GLASS, 754, 0.008), LowPoly.at(Vector3(0.0, 0.18, 0.0)))   # neck
	s.merge(LowPoly.cylinder(0.085, 0.085, 0.03, 6, ICHOR_DARK, 755, 0.006), LowPoly.at(Vector3(0.0, 0.12, 0.0)))   # collar
	s.merge(LowPoly.cylinder(0.062, 0.075, 0.08, 6, ComponentProps.LEATHER, 756, 0.008), LowPoly.at(Vector3(0.0, 0.27, 0.0)))   # cork
	for p: Vector3 in [Vector3(0.20, 0.10, 0.04), Vector3(-0.19, 0.18, -0.03), Vector3(0.14, 0.26, 0.10)]:
		s.merge(LowPoly.boulder(Vector3(0.030, 0.038, 0.030), 0, 0.12, ICHOR_LIGHT, 757 + int(p.x * 100.0), 0.04), LowPoly.at(p))   # floating drops
	return s

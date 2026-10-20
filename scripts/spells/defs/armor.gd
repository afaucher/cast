class_name ArmorSpell
extends SpellDef
## Armor: a shielding zone where you aim (ArmorZone, a scheduled effect); allies inside take much less damage.

const ID := "armor"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Armor", "cooldown": 14.0, "color": Color(0.35, 0.6, 1.0),
	"desc": "A shielding zone where you aim: allies inside take much less damage.", "word": "armor",
	"component": "Hide plate", "available": true,
}

const ARMOR_MULT_WEAK := 0.75      ## damage multiplier at power ~0
const ARMOR_MULT_STRONG := 0.4     ## damage multiplier at power 1
const ARMOR_DURATION_BASE := 5.0
const ARMOR_DURATION_POWER := 5.0


static func armor_multiplier(power: float) -> float:
	return lerpf(ARMOR_MULT_WEAK, ARMOR_MULT_STRONG, clampf(power, 0.0, 1.0))


static func armor_duration(power: float) -> float:
	return ARMOR_DURATION_BASE + ARMOR_DURATION_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, pos: Vector3, start: float, _extra: Dictionary) -> Node:
	var zone := ArmorZone.new()
	zone.team = caster.team
	zone.power = clampf(power, SpellBook.MIN_POWER, 1.0)
	zone.start_time = start
	GameWorld.spawn(zone, pos)
	return zone


# --- The component: Hide plate (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.05
const PLATE := Color(0.32, 0.55, 0.92)
const PLATE_LIGHT := Color(0.60, 0.80, 1.0)


## A hex plate lying nearly flat so the top shows from the game camera: leather rim, a blue plate, a
## raised boss and rivets.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(731, 0.07)
	var tilt := Vector3(-22.0, 0.0, 0.0)
	var b := Basis.from_euler(Vector3(deg_to_rad(tilt.x), 0.0, 0.0))
	s.merge(LowPoly.cylinder(0.30, 0.30, 0.09, 6, ComponentProps.LEATHER, 732, 0.012, 1, 0.08), LowPoly.at(Vector3.ZERO, tilt))
	s.merge(LowPoly.cylinder(0.25, 0.23, 0.08, 6, PLATE, 733, 0.014, 1, 0.07), LowPoly.at(b * Vector3(0, 0.05, 0), tilt))
	s.merge(LowPoly.boulder(Vector3(0.12, 0.07, 0.12), 0, 0.12, PLATE_LIGHT, 734, 0.05), LowPoly.at(b * Vector3(0, 0.12, 0), tilt))
	for i in 6:
		var a := TAU * i / 6.0 + TAU / 12.0
		s.merge(LowPoly.boulder(Vector3(0.035, 0.035, 0.035), 0, 0.1, PLATE_LIGHT, 735 + i, 0.04), LowPoly.at(b * Vector3(cos(a) * 0.255, 0.1, sin(a) * 0.255)))
	return s

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

class_name DampSpell
extends SpellDef
## Damp: a wide area gets soggy where you aim (Damp, a scheduled effect): fires go out, nobody can ignite for a while, and
## shoves slide further on the puddles; it leaves a wet floor. Design record: docs/design/spells.md.

const ID := "damp"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Damp", "cooldown": 10.0, "color": Color(0.30, 0.82, 0.92),
	"desc": "A wide area gets soggy: fires go out, nobody can ignite for a while, and shoves slide further on the puddles.", "word": "damp",
	"component": "Soggy sponge", "available": true,
}

const DAMP_RADIUS_BASE := 4.0      ## a WIDE area
const DAMP_RADIUS_POWER := 1.0
const DAMP_SOAK := 15.0            ## seconds nobody in the area can ignite (Burning.soak)
const DAMP_PUDDLE_LIFE := 24.0     ## the wet floor lasts this long (Grime marks live 30 s)
const DAMP_DRY_TIME := 8.0         ## ... and dries out over the last this-many seconds
const DAMP_SLIDE_BONUS := 0.5      ## +50% shove distance on a fully wet puddle cell


static func damp_radius(power: float) -> float:
	return DAMP_RADIUS_BASE + DAMP_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, start: float, _extra: Dictionary) -> Node:
	var d := Damp.new()
	d.power = clampf(power, SpellBook.MIN_POWER, 1.0)
	d.source_team = caster.team
	d.caster = caster
	d.start_time = start
	GameWorld.spawn(d, target)
	return d

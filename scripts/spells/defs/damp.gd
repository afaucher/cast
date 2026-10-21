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

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table).
## The exact word (see the VINES / DAMP / COFFEE note in Incantation's header).
const VOICE := {
	"damp": 1.0,
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


# --- The component: Soggy sponge (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.18
const SPONGE := Color(0.95, 0.80, 0.25)
const SPONGE_DARK := Color(0.72, 0.55, 0.12)
const SPONGE_HOLE := Color(0.50, 0.36, 0.08)
const WATER := Color(0.35, 0.80, 0.98)


## A chunky yellow sponge, full of holes, with a bright drip hanging off one corner.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(821, 0.07)
	s.merge(LowPoly.box(Vector3(0.36, 0.2, 0.26), SPONGE, 822, 0.02, 2, 0.08), LowPoly.at(Vector3(0.0, 0.0, 0.0), Vector3(0, 18, 0)))
	s.merge(LowPoly.box(Vector3(0.36, 0.06, 0.26), SPONGE_DARK, 823, 0.02, 1, 0.08), LowPoly.at(Vector3(0.0, -0.08, 0.0), Vector3(0, 18, 0)))   # the scrubby underside
	for p: Vector3 in [Vector3(-0.1, 0.1, 0.04), Vector3(0.07, 0.1, -0.06), Vector3(0.12, 0.1, 0.07), Vector3(-0.03, 0.1, -0.07), Vector3(0.0, 0.1, 0.07)]:
		s.merge(LowPoly.boulder(Vector3(0.032, 0.02, 0.032), 0, 0.12, SPONGE_HOLE, 824 + int(p.x * 100.0), 0.05), LowPoly.at(p))
	s.merge(LowPoly.boulder(Vector3(0.045, 0.07, 0.045), 0, 0.10, WATER, 830, 0.05), LowPoly.at(Vector3(0.17, -0.12, 0.1)))   # the drip
	s.merge(LowPoly.boulder(Vector3(0.025, 0.035, 0.025), 0, 0.10, WATER, 831, 0.05), LowPoly.at(Vector3(0.18, -0.22, 0.1)))
	return s

class_name CornSpell
extends SpellDef
## Corn: a giant corn cob falls from the sky where you aim (CornStrike, a scheduled effect) and hits everyone.

const ID := "corn"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Corn", "cooldown": 12.0, "color": Color(1.0, 0.9, 0.25),
	"desc": "A giant corn cob falls from the sky. Hits EVERYONE. You were warned.", "word": "corn",
	"component": "Corn kernel", "available": true,
}


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


# --- The component: Corn kernel (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.10
const KERNEL := Color(1.0, 0.85, 0.15)
const KERNEL_LIGHT := Color(1.0, 0.96, 0.62)
const KERNEL_DARK := Color(0.85, 0.62, 0.08)
const HUSK := Color(0.45, 0.72, 0.30)


## One fat golden kernel on a husk leaf.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(741, 0.07)
	s.merge(LowPoly.boulder(Vector3(0.17, 0.23, 0.15), 0, 0.12, KERNEL, 742, 0.06), LowPoly.at(Vector3(0.0, 0.02, 0.0), Vector3(0, 0, 8)))
	s.merge(LowPoly.boulder(Vector3(0.10, 0.07, 0.09), 0, 0.15, KERNEL_LIGHT, 743, 0.05), LowPoly.at(Vector3(0.0, 0.17, 0.0)))   # pale cap
	s.merge(LowPoly.boulder(Vector3(0.12, 0.08, 0.11), 0, 0.15, KERNEL_DARK, 744, 0.05), LowPoly.at(Vector3(0.01, -0.17, 0.0)))   # pinched base
	# two husk leaves hugging the base
	s.merge(LowPoly.box(Vector3(0.05, 0.22, 0.13), HUSK, 745, 0.01, 1, 0.08), LowPoly.at(Vector3(-0.14, -0.10, 0.0), Vector3(0, 0, 20)))
	s.merge(LowPoly.box(Vector3(0.05, 0.20, 0.12), HUSK.darkened(0.15), 746, 0.01, 1, 0.08), LowPoly.at(Vector3(0.15, -0.11, 0.0), Vector3(0, 0, -20)))
	return s

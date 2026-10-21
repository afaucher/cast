class_name TeethSpell
extends SpellDef
## Teeth: too many teeth sprout out of everyone at the aim point, then pop (Teeth, scripts/spells/teeth.gd; design record:
## docs/design/spells.md).

const ID := "teeth"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Teeth", "cooldown": 12.0, "color": Color(0.96, 0.93, 0.8),
	"desc": "Too many teeth sprout out of EVERYONE at the aim point, then explode. Duck.", "word": "teeth",
	"component": "Loose teeth", "available": true,
}

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table).
## The exact words plus the one measured mishearing, below the 0.85 bare floor
## (see the TEETH note in Incantation's header).
const VOICE := {
	"teeth": 1.0, "tooth": 1.0,
	"ooth": 0.75,
}

const TEETH_RADIUS_BASE := 2.0
const TEETH_RADIUS_POWER := 0.6
const TEETH_GROW_SLOW := 2.0       ## grow time at power ~0 (seconds)
const TEETH_GROW_FAST := 1.0       ## grow time at power 1
const TEETH_DAMAGE := 25.0         ## the carrier, times power
const TEETH_SPLASH_DAMAGE := 10.0  ## everyone else near the carrier, times power
const TEETH_SPLASH_RADIUS := 1.5
const TEETH_SHOVE := 1.2           ## mild shove outward from the carrier


## Everyone (any team) within this of the aim point is afflicted.
static func teeth_radius(power: float) -> float:
	return TEETH_RADIUS_BASE + TEETH_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


## Seconds the teeth grow before the pop: 2.0 at the weakest, 1.0 at full power.
static func teeth_grow_time(power: float) -> float:
	return TEETH_GROW_SLOW - (TEETH_GROW_SLOW - TEETH_GROW_FAST) * clampf(power, SpellBook.MIN_POWER, 1.0)


## Damage to the carrier at the pop.
static func teeth_damage(power: float) -> float:
	return TEETH_DAMAGE * clampf(power, SpellBook.MIN_POWER, 1.0)


## Damage to everyone else near the carrier at the pop.
static func teeth_splash_damage(power: float) -> float:
	return TEETH_SPLASH_DAMAGE * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, _start: float, _extra: Dictionary) -> Node:
	Teeth.cast(caster, power, target)
	return null


# --- The component: Loose teeth (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.04
const BONE := Color(0.95, 0.92, 0.80)
const BONE_DARK := Color(0.78, 0.72, 0.58)
const BONE_LIGHT := Color(1.0, 0.98, 0.90)
const GOLD := Color(0.95, 0.76, 0.22)


static func _tooth(seed_value: int, size: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.05)
	s.merge(LowPoly.frustum(Vector2(0.15, 0.13) * size, Vector2(0.19, 0.16) * size, 0.14 * size, BONE, seed_value + 1, 0.02, 1, Vector2.ZERO, 0.04), LowPoly.at(Vector3(0.0, 0.07 * size, 0.0)))   # crown
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			s.merge(LowPoly.boulder(Vector3(0.055, 0.045, 0.05) * size, 0, 0.12, BONE_LIGHT, seed_value + 4, 0.03), LowPoly.at(Vector3(0.055 * cx, 0.15, 0.045 * cz) * size))   # cusps
	for sx: float in [-1.0, 1.0]:
		s.merge(LowPoly.cylinder(0.05 * size, 0.012 * size, 0.2 * size, 5, BONE_DARK, seed_value + 3, 0.01), LowPoly.at(Vector3(0.05 * size * sx, -0.07 * size, 0.0), Vector3(0, 0, 10.0 * sx)))   # roots
	return s


## Three white molars, one with a gold filling.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(771, 0.05)
	s.merge(_tooth(772, 1.2), LowPoly.at(Vector3(-0.12, 0.0, 0.04), Vector3(0, 20, 12)))
	s.merge(_tooth(776, 1.05), LowPoly.at(Vector3(0.12, -0.03, -0.05), Vector3(0, -15, -18)))
	s.merge(_tooth(780, 0.9), LowPoly.at(Vector3(0.0, 0.02, 0.15), Vector3(-30, 0, 4)))
	s.merge(LowPoly.box(Vector3(0.07, 0.045, 0.035), GOLD, 784, 0.0, 1, 0.03), LowPoly.at(Vector3(-0.12, 0.17, -0.06)))   # gold filling
	return s

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

class_name TentaclesSpell
extends SpellDef
## Tentacles: neon tentacles burst from the floor where you aim (Tentacles, a scheduled effect) and shove everyone outward,
## then stay up a few seconds, swatting anyone inside their sideways oval back out of it.

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

## The area is an OVAL lying sideways across the caster's line of aim (the user, 2026-10-27: "Let's consider increasing the
## width of the area but not the depth. Again with strength."): its DEPTH half-axis, along the aim, is the old radius; its
## WIDTH half-axis, across the aim, is the depth times 1.2 (minimum power) to 1.5 (full). (It was 1.4 to 2.0, 12 across at
## full power; the user, 2026-10-28: "I think we scaled it up too much. It is MUCH bigger then hallways now".) Only floor
## the centre reaches without crossing a wall counts (Tentacles.reaches).
const TENTACLES_RADIUS_BASE := 2.2       ## the depth half-axis (along the aim): 2.2 to 3.0
const TENTACLES_RADIUS_POWER := 0.8
const TENTACLES_WIDTH_BASE := 1.2        ## the width half-axis = depth x (1.2 + 0.3 x power): about 2.6 to 4.5
const TENTACLES_WIDTH_POWER := 0.3
const TENTACLES_SHOVE_BASE := 2.5        ## the burst's shove, straight out from the centre: 2.5 to 4.0
const TENTACLES_SHOVE_POWER := 1.5
const TENTACLES_DAMAGE := 6.0            ## monsters and breakables only, times power: at the burst and at every swat
## After the burst the tentacles stay up 4 s (minimum power) to 6 s (full) (the user: "Let's just increase the duration and
## that swatting behavior"), and every SWAT_EVERY seconds on the shared clock they swat everyone inside the oval out of its
## nearest edge, a smaller shove than the burst's.
const TENTACLES_UP_BASE := 4.0
const TENTACLES_UP_POWER := 2.0
const TENTACLES_SWAT_EVERY := 0.6
const TENTACLES_SWAT_BASE := 1.5         ## a swat's shove: 1.5 to 2.0
const TENTACLES_SWAT_POWER := 0.5


static func _p(power: float) -> float:
	return clampf(power, SpellBook.MIN_POWER, 1.0)


## The oval's DEPTH half-axis (along the caster's aim): the old radius.
static func tentacles_radius(power: float) -> float:
	return TENTACLES_RADIUS_BASE + TENTACLES_RADIUS_POWER * _p(power)


## The same as tentacles_radius: the oval's half-axis along the aim.
static func tentacles_depth(power: float) -> float:
	return tentacles_radius(power)


## The oval's WIDTH half-axis (across the aim).
static func tentacles_width(power: float) -> float:
	return tentacles_depth(power) * (TENTACLES_WIDTH_BASE + TENTACLES_WIDTH_POWER * _p(power))


## World units everyone in the oval is shoved by the burst (before each actor's shove_mult).
static func tentacles_distance(power: float) -> float:
	return TENTACLES_SHOVE_BASE + TENTACLES_SHOVE_POWER * _p(power)


static func tentacles_damage(power: float) -> float:
	return TENTACLES_DAMAGE * _p(power)


## Seconds the tentacles stay up after the burst (then they retract).
static func tentacles_duration(power: float) -> float:
	return TENTACLES_UP_BASE + TENTACLES_UP_POWER * _p(power)


## World units a swat shoves (before each actor's shove_mult).
static func tentacles_swat_distance(power: float) -> float:
	return TENTACLES_SWAT_BASE + TENTACLES_SWAT_POWER * _p(power)


## How many swats a cast makes: one every TENTACLES_SWAT_EVERY after the burst while the tentacles are up (6 to 9).
static func tentacles_swats(power: float) -> int:
	return floori((tentacles_duration(power) - 0.001) / TENTACLES_SWAT_EVERY)


## The line of aim the oval lies across: caster -> target, flat; the caster's facing when it stands on the target.
static func aim_dir(caster: Actor, target: Vector3) -> Vector3:
	var d := target - caster.global_position
	d.y = 0.0
	if d.length() < 0.05:
		d = caster.facing
		d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.FORWARD


## Fixed on the caster's machine and sent with the cast (NetCasts' `x`), so every machine lays the oval the same way.
static func cast_extra(caster: Actor, target: Vector3) -> Dictionary:
	return {"d": aim_dir(caster, target)}


static func cast(caster: Actor, power: float, target: Vector3, start: float, extra: Dictionary) -> Node:
	var t := Tentacles.new()
	t.power = clampf(power, SpellBook.MIN_POWER, 1.0)
	t.source_team = caster.team
	t.caster = caster
	t.start_time = start
	var d: Vector3 = extra.get("d", aim_dir(caster, target))
	d.y = 0.0
	t.aim = d.normalized() if d.length() > 0.001 else Vector3.FORWARD
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

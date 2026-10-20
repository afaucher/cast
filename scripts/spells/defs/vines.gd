class_name VinesSpell
extends SpellDef
## Vines: thorny vines burst up where you aim (Vines, a scheduled effect) and root everyone in the area. Design record:
## docs/design/spells.md.

const ID := "vines"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Vines", "cooldown": 10.0, "color": Color(0.45, 0.78, 0.22),
	"desc": "Thorny vines burst up and ROOT EVERYONE in the area for about two seconds: no walking, no shoving.", "word": "vines",
	"component": "Seed pod", "available": true,
}

const VINES_RADIUS_BASE := 2.4
const VINES_RADIUS_POWER := 0.6
const VINES_ROOT_BASE := 1.6       ## seconds rooted at power ~0
const VINES_ROOT_POWER := 0.6      ## ... plus this at power 1 (2.2 s)


## Everyone (any team) within this of the aim point is rooted.
static func vines_radius(power: float) -> float:
	return VINES_RADIUS_BASE + VINES_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


## Seconds the roots hold.
static func vines_duration(power: float) -> float:
	return VINES_ROOT_BASE + VINES_ROOT_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, start: float, _extra: Dictionary) -> Node:
	var v := Vines.new()
	v.power = clampf(power, SpellBook.MIN_POWER, 1.0)
	v.source_team = caster.team
	v.caster = caster
	v.start_time = start
	GameWorld.spawn(v, target)
	return v


# --- The component: Seed pod (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.10
const POD := Color(0.40, 0.70, 0.20)
const POD_DARK := Color(0.20, 0.45, 0.12)
const POD_LIGHT := Color(0.66, 0.90, 0.36)
const SEED := Color(0.96, 0.92, 0.62)
const THORN := Color(0.92, 0.80, 0.48)


## A fat green seed pod standing on its base, split at the top to show pale seeds, with a curled tendril and a thorn.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(791, 0.08)
	s.merge(LowPoly.boulder(Vector3(0.17, 0.21, 0.15), 1, 0.07, POD, 792, 0.07), LowPoly.at(Vector3(0.0, -0.04, 0.0)))   # the body
	s.merge(LowPoly.boulder(Vector3(0.10, 0.14, 0.09), 0, 0.10, POD_LIGHT, 793, 0.06), LowPoly.at(Vector3(-0.06, 0.0, -0.09)))   # a sunlit rib
	s.merge(LowPoly.boulder(Vector3(0.12, 0.05, 0.10), 0, 0.10, POD_DARK, 794, 0.06), LowPoly.at(Vector3(0.0, 0.15, 0.0)))   # the split rim
	for p: Vector3 in [Vector3(-0.04, 0.19, 0.01), Vector3(0.04, 0.2, -0.02), Vector3(0.0, 0.2, 0.05)]:
		s.merge(LowPoly.boulder(Vector3(0.036, 0.04, 0.036), 0, 0.10, SEED, 795 + int(p.x * 100.0)), LowPoly.at(p))
	# a curled tendril off the stem
	var pos := Vector3(0.0, -0.25, 0.0)
	var ang := 0.0
	for i in 5:
		var seg := LowPoly.cylinder(0.03 - 0.004 * i, 0.026 - 0.004 * i, 0.09, 5, POD_DARK, 800 + i, 0.004)
		var mid := pos + Vector3(sin(ang), cos(ang), 0.0) * 0.045
		s.merge(seg, LowPoly.at(mid, Vector3(0, 0, -rad_to_deg(ang))))
		pos += Vector3(sin(ang), cos(ang), 0.0) * 0.09
		ang += 0.55
	s.merge(LowPoly.cylinder(0.04, 0.0, 0.13, 4, THORN, 810, 0.0), LowPoly.at(Vector3(0.14, 0.0, 0.1), Vector3(0, 0, -80)))   # a thorn
	return s


# --- On a copy (NetStatus) ---

## The roots arrived from the owner: wrap the copy's legs once, when the root starts.
static func show_remote_mods(a: Actor, had: bool) -> void:
	if not had and a.has_modifier("vines"):
		VineWrap.attach(a, a.modifier_left("vines"))

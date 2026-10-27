class_name ReviveSpell
extends SpellDef
## Revive: stands every downed ally where you aim back up at half health, with no zombie curse; on a coffee zombie it lifts
## the curse and brings it up to half health (Actor.revive, Combat.revive_radius). A support spell aimed like heal: it
## follows the teammate the aim snapped onto, downed ones included. Design record: docs/design/spells.md ("Revive"; the
## user, 2026-10-27: "We should also have a dedicated revive spell which brings you back about half health and it doesn't
## have this zombie curse effect. The revive spells should be a plant leaf or something.").
##
## Networking (the target's owner applies it, like a heal): the cast is an event that lands on every machine at the same
## moment (SpellBook.apply); each machine stands up only the heroes it owns (Net.resolves: a player's own hero, the host's AI
## seats), and the other screens see them stand from the owner's hero snapshot (dead / hp / zombie: NetCodec).

const ID := "revive"
const FOLLOWS := true
## The aim snaps onto a DOWNED teammate too (SpellBook.snap_hero): the body is what you point at.
const SNAPS_DOWNED := true

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
## Cooldown 12 s: heal's rate of HP back (heal 35 / 8 s, revive 50 / 12 s, about 4 HP a second each), the corn and teeth
## tier, a little under coffee's 14 s.
const ROW := {
	"name": "Revive", "cooldown": 12.0, "color": Color(0.55, 0.95, 0.78),
	"desc": "Stands a downed ally back up at half health. Point at them.", "word": "revive",
	"component": "Aloe leaf", "available": true,
}

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table; the REVIVE
## note in its header has the measurements).
const VOICE := {
	"revive": 1.0, "revives": 1.0,
}

const REVIVE_HP := 0.5             ## a downed ally gets up at this fraction of max HP (a zombie is raised to it)
const REVIVE_RADIUS_BASE := 1.5    ## a SMALL radius, like coffee's: point at the body
const REVIVE_RADIUS_POWER := 0.5


static func revive_radius(power: float) -> float:
	return REVIVE_RADIUS_BASE + REVIVE_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, pos: Vector3, _start: float, _extra: Dictionary) -> Node:
	var radius := revive_radius(power)
	Combat.revive_radius(pos, radius, caster.team, 0.0, REVIVE_HP, false, true)
	ReviveFx.cast(pos, radius)   # (every cast, on every screen; whoever stood up shows it themselves: Hero._on_revived)
	return null


# --- The component: Aloe leaf (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.08
const LEAF := Color(0.36, 0.62, 0.34)
const LEAF_LIGHT := Color(0.52, 0.76, 0.44)
const LEAF_DARK := Color(0.22, 0.42, 0.24)
const TOOTH := Color(0.88, 0.90, 0.70)
const FLECK := Color(0.80, 0.88, 0.74)
const GEL := Color(0.80, 0.96, 0.78)


## A fat, fleshy aloe leaf: thick at the cut base and tapering to a point, curling a little, with pale teeth along both
## edges, pale flecks on its face and the clear gel showing at the cut.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(911, 0.06)
	var n := 6
	var pts: Array[Vector3] = []
	for i in n + 1:
		var u := float(i) / float(n)
		pts.append(Vector3(sin(u * 1.1) * 0.12 - 0.05, -0.27 + u * 0.55, -0.04 * u * u))   # it curls over to one side
	for i in n:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var mid := (a + b) * 0.5
		var tilt := -rad_to_deg(atan2(d.x, d.y))
		var u := (float(i) + 0.5) / float(n)
		var w := lerpf(0.10, 0.025, u)              # wide and fat at the base, to a point
		var t := lerpf(0.065, 0.02, u)
		var col := LEAF_LIGHT if i % 2 == 0 else LEAF
		s.merge(LowPoly.boulder(Vector3(w, d.length() * 0.62, t), 0, 0.06, col, 912 + i, 0.05), LowPoly.at(mid, Vector3(0, 0, tilt)))
		s.merge(LowPoly.boulder(Vector3(w * 0.7, d.length() * 0.55, t * 0.6), 0, 0.06, LEAF_DARK, 920 + i, 0.05),
			LowPoly.at(mid + Vector3(0, 0, -t * 0.55), Vector3(0, 0, tilt)))   # the darker back of the leaf
		if i < n - 1:
			for side: float in [-1.0, 1.0]:   # a pale tooth on each edge, pointing out and up
				var out := Vector3(cos(deg_to_rad(tilt)), sin(deg_to_rad(tilt)), 0.0) * side
				s.merge(LowPoly.cylinder(0.016, 0.0, 0.05, 4, TOOTH, 930 + i * 2 + int(side > 0.0), 0.0),
					LowPoly.at(mid + out * (w + 0.018), Vector3(0, 0, tilt - side * 70.0)))
		if i in [1, 2, 3]:   # flecks on the face
			s.merge(LowPoly.boulder(Vector3(0.016, 0.022, 0.008), 0, 0.1, FLECK, 945 + i), LowPoly.at(mid + Vector3(w * 0.3, 0.0, t * 0.85)))
			s.merge(LowPoly.boulder(Vector3(0.012, 0.016, 0.008), 0, 0.1, FLECK, 950 + i), LowPoly.at(mid + Vector3(-w * 0.35, 0.02, t * 0.8)))
	s.merge(LowPoly.boulder(Vector3(0.05, 0.035, 0.07), 0, 0.15, LEAF_DARK, 958, 0.05), LowPoly.at(pts[n] + Vector3(0.0, 0.01, 0.0)))   # the tip
	s.merge(LowPoly.boulder(Vector3(0.085, 0.02, 0.05), 0, 0.08, GEL, 960, 0.04), LowPoly.at(pts[0] + Vector3(0.0, -0.01, 0.0)))   # the cut, the gel
	return s

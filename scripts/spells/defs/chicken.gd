class_name ChickenSpell
extends SpellDef
## Chicken: four chickens scatter from the aim point and peck everything for nothing; a pecked monster chases its chicken
## (Chicken, scripts/spells/chicken.gd; decided by the user 2026-10-18, docs/design/spells.md).

const ID := "chicken"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Chicken", "cooldown": 14.0, "color": Color(0.94, 0.33, 0.27),
	"desc": "Four chickens burst out where you aim and peck EVERYONE for zero. A pecked monster forgets you and chases its chicken, which does not last long.", "word": "chicken",
	"component": "Chicken feather", "available": true,
}

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table).
## The word and its plural (see the CHICKEN note in Incantation's header).
const VOICE := {
	"chicken": 1.0, "chickens": 1.0,
}


## The flock lands (every machine, at the cast's moment): a feather cloud at the aim point on every screen, and the chickens
## from the HOST only (Net.is_host: solo too). They are host-owned actors like monsters: a client gets them from the world
## stream (NetWorld `world.spawn`), so a client's own cast never spawns any here. Power does not change the flock.
static func cast(_caster: Actor, _power: float, target: Vector3, _start: float, _extra: Dictionary) -> Node:
	ChickenFx.cast_cloud(target)
	if Net.is_host():
		Chicken.flock(target)
	return null


# --- The component: Chicken feather (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.05
const FEATHER := Color(0.97, 0.95, 0.90)
const FEATHER_SHADE := Color(0.84, 0.81, 0.76)
const FEATHER_TIP := Color(0.80, 0.30, 0.20)
const QUILL := Color(0.93, 0.84, 0.62)


## A long tail feather standing on its quill, leaning and curling over at the top: a pale quill up the middle, a white
## vane of overlapping barbs either side (shaded on one side so the shape reads), a rust-red band at the tip.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(861, 0.06)
	var pts: Array[Vector3] = []
	var n := 7
	for i in n + 1:
		var u := float(i) / float(n)
		pts.append(Vector3(sin(u * 1.25) * 0.16 - 0.04, -0.27 + u * 0.56, 0.0))   # the shaft curls over to one side
	s.merge(LowPoly.cylinder(0.022, 0.018, 0.1, 5, QUILL, 862, 0.0), LowPoly.at(Vector3(-0.04, -0.31, 0.0)))   # the bare quill end
	for i in n:
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var mid := (a + b) * 0.5
		var tilt := -rad_to_deg(atan2(d.x, d.y))
		s.merge(LowPoly.cylinder(0.016, 0.013, d.length(), 4, QUILL, 863 + i, 0.0), LowPoly.at(mid, Vector3(0, 0, tilt)))
		var u := (float(i) + 0.5) / float(n)
		var w := 0.08 + 0.09 * sin(u * PI * 0.95)                          # widest just past the middle
		var col := FEATHER_TIP if i >= n - 2 else FEATHER
		for side: float in [-1.0, 1.0]:
			var off := Vector3(cos(deg_to_rad(tilt)), sin(deg_to_rad(tilt)), 0.0) * side * w * 0.55
			var barb_col := col if side < 0.0 else (FEATHER_TIP.darkened(0.15) if i >= n - 2 else FEATHER_SHADE)
			s.merge(LowPoly.boulder(Vector3(w * 0.6, d.length() * 0.85, 0.03), 0, 0.08, barb_col, 870 + i * 2 + int(side > 0.0), 0.04),
				LowPoly.at(mid + off, Vector3(0, 0, tilt + side * 8.0)))
	s.merge(LowPoly.boulder(Vector3(0.05, 0.06, 0.03), 0, 0.12, FEATHER_TIP, 890, 0.05), LowPoly.at(pts[n] + Vector3(0.01, 0.02, 0.0)))   # the tip
	# A few loose fluffy barbs at the base.
	for k in 3:
		var a := -0.6 + 0.6 * float(k)
		s.merge(LowPoly.boulder(Vector3(0.035, 0.05, 0.02), 0, 0.15, FEATHER, 891 + k, 0.05), LowPoly.at(Vector3(-0.04 + a * 0.06, -0.22, 0.01 * float(k)), Vector3(0, 0, a * 40.0)))
	return s

class_name HealSpell
extends SpellDef
## Heal: heals every ally where you aim (a support spell: it follows the teammate the aim snapped onto).

const ID := "heal"
const FOLLOWS := true

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Heal", "cooldown": 8.0, "color": Color(0.35, 0.95, 0.5),
	"desc": "Heals every ally where you aim. Point at a friend, or at your feet.", "word": "heal",
	"component": "Grave moss", "available": true,
}

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table).
const VOICE := {
	"heal": 1.0, "heel": 1.0, "he'll": 1.0, "heals": 0.9, "healing": 0.85,
	"healer": 0.8, "eel": 0.8, "hail": 0.7, "hill": 0.6, "ill": 0.6,
}

const HEAL_RADIUS := 3.0
const HEAL_BASE := 35.0


## HP restored by Heal at a given power.
static func heal_amount(power: float) -> float:
	return HEAL_BASE * (0.4 + 0.6 * clampf(power, SpellBook.MIN_POWER, 1.0))


static func cast(caster: Actor, power: float, pos: Vector3, _start: float, _extra: Dictionary) -> Node:
	var col := SpellBook.color_of("heal")
	var amount := heal_amount(power)
	for a in GameWorld.actors_in_radius(pos, HEAL_RADIUS, caster.team):
		if Teeth.cancel_on(a):   # the dentist: a heal pulls the teeth before they pop (on every screen: the pop is off everywhere)
			Fx.number(a.global_position + Vector3(0, 3.0, 0), "DENTIST!", SpellBook.color_of("teeth"), 1.0)
		var sparkle: Array[Color] = [Color(0.7, 1.0, 0.75), col]
		Fx.burst(a.global_position + Vector3.UP * 0.2, sparkle, 12, 1.4, 0.07, 1.0, -1.5, Vector3.UP, 35.0)
	for e: Array in Combat.heal_radius(pos, HEAL_RADIUS, amount, caster.team):   # (online: each hero's owner heals it, once)
		var a: Actor = e[0]
		if float(e[1]) > 0.5:
			Fx.number(a.global_position + Vector3(0, 2.4, 0), "+%d" % int(roundf(float(e[1]))), Fx.NUMBER_HEAL, 1.1)
	# Three rising hex rings, staggered.
	Fx.ring(pos, HEAL_RADIUS, Color(col.r, col.g, col.b, 0.85), 0.9, 2.0, true, 0.2)
	var tree := GameWorld.root.get_tree()
	for i in [1, 2]:
		tree.create_timer(0.18 * i).timeout.connect(func() -> void:
			Fx.ring(pos, HEAL_RADIUS * (1.0 - 0.18 * i), Color(col.r, col.g, col.b, 0.7), 0.8, 1.8, true, 0.2))
	return null


# --- The component: Grave moss (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.12
const MOSS := Color(0.28, 0.72, 0.32)
const MOSS_LIGHT := Color(0.50, 0.92, 0.48)
const MOSS_DARK := Color(0.16, 0.45, 0.24)
const SPORE := Color(0.98, 0.95, 0.60)


## A green clump of moss with pale spore buds.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(701, 0.08)
	s.merge(LowPoly.boulder(Vector3(0.22, 0.13, 0.20), 0, 0.2, MOSS_DARK, 702, 0.08), LowPoly.at(Vector3(0.0, -0.12, 0.0)))
	s.merge(LowPoly.boulder(Vector3(0.17, 0.15, 0.16), 0, 0.2, MOSS, 703, 0.08), LowPoly.at(Vector3(-0.09, -0.03, 0.05)))
	s.merge(LowPoly.boulder(Vector3(0.15, 0.16, 0.15), 0, 0.2, MOSS_LIGHT, 704, 0.08), LowPoly.at(Vector3(0.10, 0.00, -0.04)))
	s.merge(LowPoly.boulder(Vector3(0.13, 0.12, 0.13), 0, 0.2, MOSS, 705, 0.08), LowPoly.at(Vector3(0.01, 0.06, 0.08)))
	s.merge(LowPoly.boulder(Vector3(0.11, 0.10, 0.11), 0, 0.2, MOSS_LIGHT, 706, 0.08), LowPoly.at(Vector3(-0.04, 0.11, -0.05)))
	for p: Vector3 in [Vector3(-0.07, 0.19, -0.03), Vector3(0.09, 0.15, 0.0), Vector3(0.02, 0.20, 0.08)]:
		s.merge(LowPoly.boulder(Vector3(0.035, 0.035, 0.035), 0, 0.15, SPORE, 707 + int(p.x * 100.0)), LowPoly.at(p))
	return s

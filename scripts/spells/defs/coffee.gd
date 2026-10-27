class_name CoffeeSpell
extends SpellDef
## Coffee: everyone in a small radius gets haste, then a crash (Coffee, scripts/spells/coffee.gd), and a downed hero in it
## gets up as a zombie (ZOMBIE_*, Hero.zombie). A support spell: it follows the teammate the aim snapped onto (a downed one
## too). Design record: docs/design/spells.md.

const ID := "coffee"
const FOLLOWS := true

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Coffee", "cooldown": 14.0, "color": Color(0.66, 0.43, 0.24),
	"desc": "Everyone in a small radius gets +60% move and attack speed for six seconds, twitchy, then a crash. Monsters too. A downed ally gets up gray, leaking health, until healed past three quarters.", "word": "coffee",
	"component": "Coffee beans", "available": true,
}

## Coffee's aim snaps onto a DOWNED teammate too (SpellBook.snap_hero): a cup stands them up as a zombie.
const SNAPS_DOWNED := true

## What the recognizer hears as this spell's word: heard phrase -> match quality (Incantation's spell table).
## The exact word plus the measured mishearings, all below the 0.85 bare floor
## (see the VINES / DAMP / COFFEE note in Incantation's header).
const VOICE := {
	"coffee": 1.0,
	"coughing": 0.8, "cough": 0.75,
}

const COFFEE_RADIUS_BASE := 1.5    ## a SMALL radius
const COFFEE_RADIUS_POWER := 0.5
const COFFEE_MOVE_MULT := 1.6      ## +60% walking speed
const COFFEE_ATTACK_MULT := 1.6    ## +60% attack speed (cooldowns divide by it)
const COFFEE_TIME_BASE := 4.5      ## seconds of haste at power ~0
const COFFEE_TIME_POWER := 1.5     ## ... plus this at power 1 (6 s)
const COFFEE_CRASH_MULT := 0.7     ## -30% move and attack speed
const COFFEE_CRASH_TIME := 2.0
## THE COFFEE ZOMBIE (the user, 2026-10-27: "One coffee should bring you back but leave you grayscale. With minimum health.
## And a slow health leak."): a downed hero in the radius stands up at ZOMBIE_HP, gray, losing ZOMBIE_LEAK HP a second (no
## haste for them), until healed to ZOMBIE_CURE of max HP or more (Hero.zombie). At 0 HP they go down again.
const ZOMBIE_HP := 10.0
const ZOMBIE_LEAK := 1.5           ## HP a second
const ZOMBIE_CURE := 0.75          ## the curse lifts at this fraction of max HP or more


static func coffee_radius(power: float) -> float:
	return COFFEE_RADIUS_BASE + COFFEE_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


## Seconds of haste before the crash.
static func coffee_duration(power: float) -> float:
	return COFFEE_TIME_BASE + COFFEE_TIME_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func cast(caster: Actor, power: float, target: Vector3, _start: float, _extra: Dictionary) -> Node:
	Coffee.cast(caster, power, target)
	return null


# --- The component: Coffee beans (ComponentProps.make builds it, and holds it in a hero's hand) ---

## How strongly the prop's own colour glows (the neon variant of the shared material).
const GLOW := 0.06
const BEAN := Color(0.48, 0.28, 0.14)
const BEAN_LIGHT := Color(0.66, 0.42, 0.22)
const BEAN_DARK := Color(0.22, 0.12, 0.06)


static func _bean(seed_value: int, size: float) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(seed_value, 0.07)
	s.merge(LowPoly.boulder(Vector3(0.09, 0.13, 0.075) * size, 1, 0.05, BEAN, seed_value + 1, 0.06))
	s.merge(LowPoly.boulder(Vector3(0.05, 0.07, 0.03) * size, 0, 0.10, BEAN_LIGHT, seed_value + 2, 0.05), LowPoly.at(Vector3(-0.025, 0.02, -0.05) * size))   # a glossy highlight
	s.merge(LowPoly.box(Vector3(0.016, 0.22, 0.03) * size, BEAN_DARK, seed_value + 3, 0.0, 1, 0.04), LowPoly.at(Vector3(0.0, 0.0, 0.062) * size, Vector3(0, 0, 8)))   # the groove
	return s


## Three roasted beans with their grooves.
static func component_soup() -> LowPoly.Soup:
	var s := LowPoly.Soup.new(841, 0.05)
	s.merge(_bean(842, 1.5), LowPoly.at(Vector3(-0.1, -0.02, 0.0), Vector3(20, 15, 25)))
	s.merge(_bean(846, 1.35), LowPoly.at(Vector3(0.1, -0.04, 0.04), Vector3(-25, -20, -35)))
	s.merge(_bean(850, 1.4), LowPoly.at(Vector3(0.0, 0.05, -0.1), Vector3(60, 10, 70)))
	return s


# --- On a copy (NetStatus) ---

## The haste arrived from the owner: the copy twitches and steams too (Coffee.show_remote).
static func show_remote_mods(a: Actor, _had: bool) -> void:
	if Coffee.is_hasted(a):
		Coffee.show_remote(a)

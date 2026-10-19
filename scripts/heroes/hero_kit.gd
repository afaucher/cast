class_name HeroKit
extends RefCounted
## Per-hero kits: HP, the primary (LMB / AI melee), the secondary (RMB / AI ranged) and the movement
## quirks, as plain data. HeroKit.get_kit("wick") returns the numbers; apply(hero) copies them onto a
## Hero. The numbers are the ones in docs/design/characters.md; the Hero.MELEE_* / BOLT constants stay
## as the generic "sword" defaults for a Hero that never got a kit (tests, the training arena).
##
## Primaries:
##   Wick  "Bow bash"   12 dmg / 0.4 s / reach 1.3 / 90 deg / shove 0.7
##   Gasket   "Hammer"     28 dmg / 0.65 s / reach 1.5 / 90 deg / shove 0.9
##   Rebar  "Slam fist"  15 dmg / 0.8 s / reach 1.8 / 120 deg / shove 1.6 (a tank, not the killer: user, 2026-10-19)
## Walk speeds are not part of the kit yet (everyone walks at Hero's 4.5).
## Secondaries: Wick "arrow" (tap or draw), Gasket "spin", Rebar "bowl" (the spin / bowl stats live on
## Hero as constants and are unchanged).

const WICK := "wick"
const GASKET := "gasket"
const REBAR := "rebar"

## id -> kit data. Keys not listed fall back to the defaults in `_defaults()`.
const DATA := {
	WICK: {
		"display_name": "Wick",
		"max_hp": 85.0,
		"primary_name": "Bow bash",
		"melee_damage": 12.0,
		"melee_cooldown": 0.4,
		"melee_reach": 1.3,
		"melee_arc": 90.0,
		"melee_shove": 0.7,
		"secondary_kind": "arrow",
		"shove_mult": 1.3,        # light
		"can_climb": true,
		"climb_speed_factor": 0.6,
	},
	GASKET: {
		"display_name": "Gasket",
		"max_hp": 120.0,
		"primary_name": "Hammer",
		"melee_damage": 28.0,
		"melee_cooldown": 0.65,
		"melee_reach": 1.5,
		"melee_arc": 90.0,
		"melee_shove": 0.9,
		"secondary_kind": "spin",
		"shove_mult": 0.6,        # stout
		"can_climb": true,
		"climb_speed_factor": 0.25,
	},
	REBAR: {
		"display_name": "Rebar",
		"max_hp": 160.0,
		"primary_name": "Slam fist",
		"melee_damage": 15.0,     # was 26: he carried every fight (docs/design/combat-variety-research.md)
		"melee_cooldown": 0.8,
		"melee_reach": 1.8,
		"melee_arc": 120.0,
		"melee_shove": 1.6,       # was 1.0: knocks monsters back (a wall-slam past 1.0)
		"secondary_kind": "bowl",
		"shove_mult": 0.0,        # heavy: immovable
		"can_climb": false,       # steps up +1 only
		"climb_speed_factor": 0.35,
	},
}

## Wick's arrow (the "arrow" secondary): a tap, or a drawn shot after holding RMB for draw_time.
const ARROW := {
	"tap_damage": 12.0,
	"tap_cooldown": 0.55,
	"tap_range": 14.0,
	"tap_pierce": 1,
	"draw_time": 0.7,
	"draw_damage": 28.0,
	"draw_range": 18.0,
	"draw_pierce": 3,
	"speed": 22.0,
	"draw_move_mult": 0.5,    # walking speed while the bow is drawn
}

var id := ""
var display_name := "Hero"
var max_hp := 100.0
var primary_name := "Sword"
var melee_damage := Hero.MELEE_DAMAGE
var melee_cooldown := Hero.MELEE_COOLDOWN
var melee_reach := Hero.MELEE_REACH
var melee_arc := Hero.MELEE_ARC
var melee_shove := Hero.MELEE_SHOVE
var secondary_kind := "bolt"
var shove_mult := 1.0
var can_climb := true
var climb_speed_factor := Actor.CLIMB_SPEED_FACTOR
## Arrow stats (used when secondary_kind == "arrow").
var arrow: Dictionary = ARROW.duplicate()


static func ids() -> Array[String]:
	return [WICK, GASKET, REBAR]


static func has_kit(kit_id: String) -> bool:
	return DATA.has(kit_id.to_lower())


## The kit for `kit_id` (case-insensitive: "Wick", "gasket"), or null if there is none.
static func get_kit(kit_id: String) -> HeroKit:
	var key := kit_id.to_lower()
	if not DATA.has(key):
		return null
	var kit := HeroKit.new()
	kit.id = key
	var d: Dictionary = DATA[key]
	for k: String in d:
		kit.set(k, d[k])
	return kit


## Copy this kit onto `hero`: HP (refilled), movement quirks, the primary, the secondary.
func apply(hero: Hero) -> void:
	hero.kit_id = id
	hero.max_hp = max_hp
	hero.hp = max_hp
	hero.shove_mult = shove_mult
	hero.can_climb = can_climb
	hero.climb_speed_factor = climb_speed_factor
	hero.primary_name = primary_name
	hero.melee_damage = melee_damage
	hero.melee_cooldown = melee_cooldown
	hero.melee_reach = melee_reach
	hero.melee_arc = melee_arc
	hero.melee_shove = melee_shove
	hero.secondary_kind = secondary_kind
	hero.arrow_tap_damage = float(arrow["tap_damage"])
	hero.arrow_tap_cooldown = float(arrow["tap_cooldown"])
	hero.arrow_tap_range = float(arrow["tap_range"])
	hero.arrow_draw_time = float(arrow["draw_time"])
	hero.arrow_draw_damage = float(arrow["draw_damage"])
	hero.arrow_draw_range = float(arrow["draw_range"])
	hero.arrow_draw_pierce = int(arrow["draw_pierce"])
	hero.arrow_speed = float(arrow["speed"])
	hero.draw_move_mult = float(arrow["draw_move_mult"])
	hero._refresh_bar()


## Apply the kit named `kit_id` (no-op, false, when there is none).
static func apply_to(hero: Hero, kit_id: String) -> bool:
	var kit := get_kit(kit_id)
	if kit == null:
		return false
	kit.apply(hero)
	return true

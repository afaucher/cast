class_name SpellBook
extends RefCounted
## The spells: metadata for the UI/voice layer plus the static cast()
## entry point. Each spell also names its material "component" (see SpellComponents) and may be
## "available": false while its gameplay is still to come (none right now). Power is in (0, 1] (voice confidence) and scales the effect.
## The spoken trigger word ("cast", "pickle"...) is configurable and only used
## for display: see incantation(). Cooldowns are NOT enforced here; Hero.try_cast owns them.

const SPELLS := {
	"heal": {
		"name": "Heal", "cooldown": 8.0, "color": Color(0.35, 0.95, 0.5),
		"desc": "Heals every ally where you aim. Point at a friend, or at your feet.", "word": "heal",
		"component": "Grave moss", "available": true,
	},
	"fireball": {
		"name": "Fireball", "cooldown": 5.0, "color": Color(1.0, 0.55, 0.15),
		"desc": "A fireball that explodes where you aim (or on the first thing it hits). Monsters, the client's property and bystanders (never heroes).", "word": "fireball",
		"component": "Ember horn", "available": true,
	},
	"armor": {
		"name": "Armor", "cooldown": 14.0, "color": Color(0.35, 0.6, 1.0),
		"desc": "A shielding zone where you aim: allies inside take much less damage.", "word": "armor",
		"component": "Hide plate", "available": true,
	},
	"corn": {
		"name": "Corn", "cooldown": 12.0, "color": Color(1.0, 0.9, 0.25),
		"desc": "A giant corn cob falls from the sky. Hits EVERYONE. You were warned.", "word": "corn",
		"component": "Corn kernel", "available": true,
	},
	"tentacles": {
		"name": "Tentacles", "cooldown": 10.0, "color": Color(0.75, 0.2, 1.0),
		"desc": "Neon tentacles burst from the floor where you aim and shove EVERYONE outward.", "word": "tentacles",
		"component": "Neon ichor", "available": true,
	},
	# Too many teeth on everyone at the aim point, then a pop (scripts/spells/teeth.gd, docs/design/spells.md).
	# "available": false would keep a spell out of the picker, the slots, the drop table and SpellBook.cast.
	"teeth": {
		"name": "Teeth", "cooldown": 12.0, "color": Color(0.96, 0.93, 0.8),
		"desc": "Too many teeth sprout out of EVERYONE at the aim point, then explode. Duck.", "word": "teeth",
		"component": "Loose teeth", "available": true,
	},
	# Vines root everyone in the area (scripts/spells/vines.gd); damp soaks and puts out fire and leaves a wet floor
	# (damp.gd); coffee is haste then a crash (coffee.gd). Design record: docs/design/spells.md.
	"vines": {
		"name": "Vines", "cooldown": 10.0, "color": Color(0.45, 0.78, 0.22),
		"desc": "Thorny vines burst up and ROOT EVERYONE in the area for about two seconds: no walking, no shoving.", "word": "vines",
		"component": "Seed pod", "available": true,
	},
	"damp": {
		"name": "Damp", "cooldown": 10.0, "color": Color(0.30, 0.82, 0.92),
		"desc": "A wide area gets soggy: fires go out, nobody can ignite for a while, and shoves slide further on the puddles.", "word": "damp",
		"component": "Soggy sponge", "available": true,
	},
	"coffee": {
		"name": "Coffee", "cooldown": 14.0, "color": Color(0.66, 0.43, 0.24),
		"desc": "Everyone in a small radius gets +60% move and attack speed for six seconds, twitchy, then a crash. Monsters too.", "word": "coffee",
		"component": "Coffee beans", "available": true,
	},
	# Four chickens scatter from the aim point and peck everything for nothing; a pecked monster chases its chicken
	# (scripts/spells/chicken.gd; decided by the user 2026-10-18, docs/design/spells.md).
	"chicken": {
		"name": "Chicken", "cooldown": 14.0, "color": Color(0.94, 0.33, 0.27),
		"desc": "Four chickens burst out where you aim and peck EVERYONE for zero. A pecked monster forgets you and chases its chicken, which does not last long.", "word": "chicken",
		"component": "Chicken feather", "available": true,
	},
}

# --- Targeting: every spell lands where the player aims, like the ranged bolt.
const SPELL_RANGE := Hero.BOLT_RANGE  ## same reach as the ranged attack
const ALLY_SNAP := 1.3                ## aim this close to a hero snaps onto them

# --- Damp
const DAMP_RADIUS_BASE := 4.0      ## a WIDE area
const DAMP_RADIUS_POWER := 1.0
const DAMP_SOAK := 15.0            ## seconds nobody in the area can ignite (Burning.soak)
const DAMP_PUDDLE_LIFE := 24.0     ## the wet floor lasts this long (Grime marks live 30 s)
const DAMP_DRY_TIME := 8.0         ## ... and dries out over the last this-many seconds
const DAMP_SLIDE_BONUS := 0.5      ## +50% shove distance on a fully wet puddle cell

# --- Coffee
const COFFEE_RADIUS_BASE := 1.5    ## a SMALL radius
const COFFEE_RADIUS_POWER := 0.5
const COFFEE_MOVE_MULT := 1.6      ## +60% walking speed
const COFFEE_ATTACK_MULT := 1.6    ## +60% attack speed (cooldowns divide by it)
const COFFEE_TIME_BASE := 4.5      ## seconds of haste at power ~0
const COFFEE_TIME_POWER := 1.5     ## ... plus this at power 1 (6 s)
const COFFEE_CRASH_MULT := 0.7     ## -30% move and attack speed
const COFFEE_CRASH_TIME := 2.0

const MIN_POWER := 0.05


## The castable spell ids (what the picker offers). Unavailable spells are left out.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in SPELLS:
		if is_available(k):
			out.append(k)
	return out


## Every spell id in the data, castable or not.
static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in SPELLS:
		out.append(k)
	return out


## False for a spell whose gameplay has not landed yet: it cannot be slotted or cast.
static func is_available(id: String) -> bool:
	return SPELLS.has(id) and bool(SPELLS[id].get("available", true))


## The spell's material component, e.g. "Ember horn".
static func component_name(id: String) -> String:
	return str(SPELLS[id].get("component", "component")) if SPELLS.has(id) else "component"


static func has_spell(id: String) -> bool:
	return SPELLS.has(id)


static func spell_name(id: String) -> String:
	return str(SPELLS[id]["name"]) if SPELLS.has(id) else id.capitalize()


static func cooldown_of(id: String) -> float:
	return float(SPELLS[id]["cooldown"]) if SPELLS.has(id) else 0.0


static func desc_of(id: String) -> String:
	return str(SPELLS[id].get("desc", "")) if SPELLS.has(id) else ""


static func color_of(id: String) -> Color:
	return SPELLS[id]["color"] if SPELLS.has(id) else Color.WHITE


## The spoken incantation shown on the HUD: trigger word + spell word, e.g. "PICKLE HEAL".
static func incantation(id: String, trigger: String = "cast") -> String:
	if not SPELLS.has(id):
		return ""
	return ("%s %s" % [trigger.strip_edges(), str(SPELLS[id]["word"])]).strip_edges().to_upper()


## The spell word alone ("heal").
static func word_of(id: String) -> String:
	return str(SPELLS[id]["word"]) if SPELLS.has(id) else id


## Find a known spell id mentioned in free text ("cast fireball", "Fire ball!"), or "".
static func find_in_text(text: String) -> String:
	var t := text.to_lower()
	var squashed := t.replace(" ", "")
	for id in SPELLS:
		if t.contains(id) or squashed.contains(id):
			return id
	return ""


## Support spells that follow the teammate the aim snapped onto (networking.md rule 3: the cast names the hero, and the
## effect lands where that hero's owner has it). Every other spell lands on the point (a teammate who sidestepped a corn
## is fine).
const FOLLOWS := ["coffee"]

## The spell defs (scripts/spells/defs/, SpellDef), in spell order.
const DEFS := [
	preload("res://scripts/spells/defs/heal.gd"),
	preload("res://scripts/spells/defs/fireball.gd"),
	preload("res://scripts/spells/defs/armor.gd"),
	preload("res://scripts/spells/defs/corn.gd"),
	preload("res://scripts/spells/defs/tentacles.gd"),
	preload("res://scripts/spells/defs/teeth.gd"),
	preload("res://scripts/spells/defs/vines.gd"),
]
static var _defs_by_id := _index_defs()


static func _index_defs() -> Dictionary:
	var out := {}
	for d: GDScript in DEFS:
		out[d.ID] = d
	return out


## The def script of spell `id` (a SpellDef), or null.
static func def_of(id: String) -> GDScript:
	return _defs_by_id.get(id) as GDScript


static func _follows(id: String) -> bool:
	var d := def_of(id)
	return bool(d.FOLLOWS) if d != null else FOLLOWS.has(id)


## Cast spell `id` from `caster` toward world point `aim`. Returns false for an unknown
## spell or a dead caster. Does not check slots or cooldown (see Hero.try_cast).
## Online (a crewed floor, M4a) the cast is an EVENT: the caster's machine resolves the target here and sends it, and
## every machine (this one too) applies it NetCasts.LEAD seconds later from the same numbers (apply()). Solo it lands
## at once.
static func cast(id: String, caster: Actor, power: float, aim: Vector3) -> bool:
	if caster == null or caster.dead or not is_available(id) or GameWorld.root == null:
		return false
	power = clampf(power, MIN_POWER, 1.0)
	if GameWorld.flat_distance(aim, caster.global_position) > 0.05:
		caster.face_point(aim)
	var target := resolve_target(caster, aim)
	var spec := {"spell": id, "power": power, "target": target, "follow": snap_hero(aim) if _follows(id) else null,
		"extra": _cast_extra(id, caster, target)}
	if Net.shares_cast(caster):
		Net.send_cast(caster, spec)
		return true
	apply(caster, spec, GameWorld.time)
	return true


## What a spell needs from the moment of the cast besides the target (a fireball's launch point, direction and reach),
## so every machine flies the same shot.
static func _cast_extra(id: String, caster: Actor, target: Vector3) -> Dictionary:
	var d := def_of(id)
	return d.cast_extra(caster, target) if d != null else {}


## Apply a cast (here at once when solo; online on every machine at the cast's moment, NetCasts). `spec` holds the spell,
## the power, the resolved target point, the followed hero (or null) and the extra numbers; `start` is the cast's moment
## in GameWorld.time (scheduled effects run their telegraph from it). Returns the effect node it spawned, or null.
## Every target the effect reaches is applied by the machine that resolves it (Combat, layer 4), so this runs on every
## machine without a hit landing twice.
static func apply(caster: Actor, spec: Dictionary, start: float) -> Node:
	if caster == null or not is_instance_valid(caster) or GameWorld.root == null:
		return null
	var id := str(spec.get("spell", ""))
	var power := clampf(float(spec.get("power", 1.0)), MIN_POWER, 1.0)
	var target: Vector3 = spec.get("target", caster.global_position)
	var follow := spec.get("follow") as Actor
	if follow != null and is_instance_valid(follow) and not follow.dead:
		target = Vector3(follow.global_position.x, follow.global_position.y, follow.global_position.z)   # where this screen has that teammate
	var extra: Dictionary = spec.get("extra", {})
	var d := def_of(id)
	if d != null:
		return d.cast(caster, power, target, start, extra)
	match id:
		"damp":
			return _cast_damp(caster, power, target, start)
		"coffee":
			Coffee.cast(caster, power, target)
		"chicken":
			_cast_chicken(target)
	return null


## Where a spell aimed at `aim` lands: clamped to SPELL_RANGE, snapped onto a hero
## standing near the aim point (so pointing at a teammate targets them), and pulled
## back toward the caster until it is over real ground. Y is the ground height.
static func resolve_target(caster: Actor, aim: Vector3) -> Vector3:
	var from := caster.global_position
	var hero := snap_hero(aim)
	if hero != null:
		aim = hero.global_position
	var d := aim - from
	d.y = 0.0
	if d.length() > SPELL_RANGE:
		d = d.normalized() * SPELL_RANGE
	var target := from + d
	var map := GameWorld.map
	var steps := 0
	while map != null and (is_nan(map.ground_height(target)) or map.blocks_point(target, 0.3)) and steps < 40:   # off the void and out of the wall
		target = from + (target - from) * 0.9
		steps += 1
	target.y = from.y if map == null or is_nan(map.ground_height(target)) else map.ground_height(target)
	return target


## The living hero nearest to `aim` within ALLY_SNAP, or null.
static func snap_hero(aim: Vector3) -> Actor:
	var best: Actor = null
	var best_d := ALLY_SNAP
	for a in GameWorld.team_actors(GameWorld.TEAM_HEROES):
		var d := GameWorld.flat_distance(a.global_position, aim)
		if d <= best_d:
			best = a
			best_d = d
	return best


## A sad little puff for a spell that went wrong (mumbled, wrong, etc.).
static func fizzle(caster: Actor) -> void:
	if caster and is_instance_valid(caster):
		Fx.fizzle_puff(caster.global_position)


# --- Damp ----------------------------------------------------------------------------------

static func damp_radius(power: float) -> float:
	return DAMP_RADIUS_BASE + DAMP_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


static func _cast_damp(caster: Actor, power: float, target: Vector3, start: float) -> Damp:
	var d := Damp.new()
	d.power = clampf(power, MIN_POWER, 1.0)
	d.source_team = caster.team
	d.caster = caster
	d.start_time = start
	GameWorld.spawn(d, target)
	return d


# --- Coffee --------------------------------------------------------------------------------

static func coffee_radius(power: float) -> float:
	return COFFEE_RADIUS_BASE + COFFEE_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


## Seconds of haste before the crash.
static func coffee_duration(power: float) -> float:
	return COFFEE_TIME_BASE + COFFEE_TIME_POWER * clampf(power, MIN_POWER, 1.0)


# --- Chicken -------------------------------------------------------------------------------

## The flock lands (every machine, at the cast's moment): a feather cloud at the aim point on every screen, and the chickens
## from the HOST only (Net.is_host: solo too). They are host-owned actors like monsters: a client gets them from the world
## stream (NetWorld `world.spawn`), so a client's own cast never spawns any here. Power does not change the flock.
static func _cast_chicken(target: Vector3) -> void:
	ChickenFx.cast_cloud(target)
	if Net.is_host():
		Chicken.flock(target)

class_name SpellBook
extends RefCounted
## The spell registry: every spell is a def in scripts/spells/defs/ (a SpellDef: its row, tuning, cast, component prop,
## remote status look and voice aliases), listed in DEFS, and SpellBook reads them. It holds the metadata for the UI/voice
## layer plus the static cast() entry point. Each spell also names its material "component" (see SpellComponents) and may
## be "available": false while its gameplay is still to come (none right now): that keeps a spell out of the picker, the
## slots, the drop table and SpellBook.cast. Power is in (0, 1] (voice confidence) and scales the effect.
## The spoken trigger word ("cast", "pickle"...) is configurable and only used
## for display: see incantation(). Cooldowns are NOT enforced here; Hero.try_cast owns them.

## The spell defs, in spell order: the order of ids(), the picker, the voice and the tests. A new spell is a new def here.
const DEFS := [
	preload("res://scripts/spells/defs/heal.gd"),
	preload("res://scripts/spells/defs/fireball.gd"),
	preload("res://scripts/spells/defs/armor.gd"),
	preload("res://scripts/spells/defs/corn.gd"),
	preload("res://scripts/spells/defs/tentacles.gd"),
	preload("res://scripts/spells/defs/teeth.gd"),
	preload("res://scripts/spells/defs/vines.gd"),
	preload("res://scripts/spells/defs/damp.gd"),
	preload("res://scripts/spells/defs/coffee.gd"),
	preload("res://scripts/spells/defs/chicken.gd"),
]

## spell id -> its def's ROW ({"name", "cooldown", "color", "desc", "word", "component", "available"}), in DEFS order.
## Read-only, like the const table it was.
static var SPELLS: Dictionary = _rows()
static var _defs_by_id: Dictionary = _index_defs()


static func _rows() -> Dictionary:
	var out := {}
	for d: GDScript in DEFS:
		out[d.ID] = d.ROW
	out.make_read_only()
	return out


static func _index_defs() -> Dictionary:
	var out := {}
	for d: GDScript in DEFS:
		out[d.ID] = d
	return out


## The def script of spell `id` (a SpellDef), or null.
static func def_of(id: String) -> GDScript:
	return _defs_by_id.get(id) as GDScript

# --- Targeting: every spell lands where the player aims, like the ranged bolt.
const SPELL_RANGE := Hero.BOLT_RANGE  ## same reach as the ranged attack
const ALLY_SNAP := 1.3                ## aim this close to a hero snaps onto them

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


## Cast spell `id` from `caster` toward world point `aim`. Returns false for an unknown
## spell or a dead caster. Does not check slots or cooldown (see Hero.try_cast).
## Online (a crewed floor, M4a) the cast is an EVENT: the caster's machine resolves the target here and sends it, and
## every machine (this one too) applies it NetCasts.LEAD seconds later from the same numbers (apply()). Solo it lands
## at once.
## A support spell (its def's FOLLOWS) follows the teammate the aim snapped onto (networking.md rule 3: the cast names the
## hero, and the effect lands where that hero's owner has it). Every other spell lands on the point (a teammate who
## sidestepped a corn is fine). What a spell needs from the moment of the cast besides the target (a fireball's launch
## point, direction and reach) is its def's cast_extra(), so every machine runs the same effect.
static func cast(id: String, caster: Actor, power: float, aim: Vector3) -> bool:
	if caster == null or caster.dead or not is_available(id) or GameWorld.root == null:
		return false
	power = clampf(power, MIN_POWER, 1.0)
	if GameWorld.flat_distance(aim, caster.global_position) > 0.05:
		caster.face_point(aim)
	var target := resolve_target(caster, aim)
	var d := def_of(id)
	var spec := {"spell": id, "power": power, "target": target, "follow": snap_hero(aim) if d.FOLLOWS else null,
		"extra": d.cast_extra(caster, target)}
	if Net.shares_cast(caster):
		Net.send_cast(caster, spec)
		return true
	apply(caster, spec, GameWorld.time)
	return true


## Apply a cast (here at once when solo; online on every machine at the cast's moment, NetCasts). `spec` holds the spell,
## the power, the resolved target point, the followed hero (or null) and the extra numbers; `start` is the cast's moment
## in GameWorld.time (scheduled effects run their telegraph from it). Returns the effect node it spawned, or null.
## Every target the effect reaches is applied by the machine that resolves it (Combat, layer 4), so this runs on every
## machine without a hit landing twice. The effect itself is the spell def's cast().
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
	if d == null:
		return null
	return d.cast(caster, power, target, start, extra)

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

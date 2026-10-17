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
}

# --- Targeting: every spell lands where the player aims, like the ranged bolt.
const SPELL_RANGE := Hero.BOLT_RANGE  ## same reach as the ranged attack
const ALLY_SNAP := 1.3                ## aim this close to a hero snaps onto them
# --- Heal
const HEAL_RADIUS := 3.0
const HEAL_BASE := 35.0
# --- Fireball
const FIREBALL_SPEED := 11.0
const FIREBALL_RANGE := 16.0
const FIREBALL_DAMAGE := 40.0
const FIREBALL_RADIUS_BASE := 1.4
const FIREBALL_RADIUS_POWER := 1.0
# --- Armor
const ARMOR_MULT_WEAK := 0.75      ## damage multiplier at power ~0
const ARMOR_MULT_STRONG := 0.4     ## damage multiplier at power 1
const ARMOR_DURATION_BASE := 5.0
const ARMOR_DURATION_POWER := 5.0
# --- Corn
# --- Tentacles
const TENTACLES_RADIUS_BASE := 2.2
const TENTACLES_RADIUS_POWER := 0.8
const TENTACLES_SHOVE_BASE := 2.5
const TENTACLES_SHOVE_POWER := 1.5
const TENTACLES_DAMAGE := 6.0     ## monsters only, times power

# --- Teeth
const TEETH_RADIUS_BASE := 2.0
const TEETH_RADIUS_POWER := 0.6
const TEETH_GROW_SLOW := 2.0       ## grow time at power ~0 (seconds)
const TEETH_GROW_FAST := 1.0       ## grow time at power 1
const TEETH_DAMAGE := 25.0         ## the carrier, times power
const TEETH_SPLASH_DAMAGE := 10.0  ## everyone else near the carrier, times power
const TEETH_SPLASH_RADIUS := 1.5
const TEETH_SHOVE := 1.2           ## mild shove outward from the carrier

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
static func cast(id: String, caster: Actor, power: float, aim: Vector3) -> bool:
	if caster == null or caster.dead or not is_available(id) or GameWorld.root == null:
		return false
	power = clampf(power, MIN_POWER, 1.0)
	if GameWorld.flat_distance(aim, caster.global_position) > 0.05:
		caster.face_point(aim)
	var target := resolve_target(caster, aim)
	match id:
		"heal":
			_cast_heal(caster, power, target)
		"fireball":
			_cast_fireball(caster, power, target)
		"armor":
			_cast_armor(caster, power, target)
		"corn":
			_cast_corn(caster, power, target)
		"tentacles":
			_cast_tentacles(caster, power, target)
		"teeth":
			Teeth.cast(caster, power, target)
	return true


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
	while map != null and is_nan(map.ground_height(target)) and steps < 40:
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


# --- Heal --------------------------------------------------------------------------------

## HP restored by Heal at a given power.
static func heal_amount(power: float) -> float:
	return HEAL_BASE * (0.4 + 0.6 * clampf(power, MIN_POWER, 1.0))


static func _cast_heal(caster: Actor, power: float, pos: Vector3) -> void:
	var col := color_of("heal")
	var amount := heal_amount(power)
	for a in GameWorld.actors_in_radius(pos, HEAL_RADIUS, caster.team):
		var got := a.heal(amount)
		if Teeth.cancel_on(a):   # the dentist: a heal pulls the teeth before they pop
			Fx.number(a.global_position + Vector3(0, 3.0, 0), "DENTIST!", SpellBook.color_of("teeth"), 1.0)
		if got > 0.5:
			Fx.number(a.global_position + Vector3(0, 2.4, 0), "+%d" % int(roundf(got)), Fx.NUMBER_HEAL, 1.1)
		var sparkle: Array[Color] = [Color(0.7, 1.0, 0.75), col]
		Fx.burst(a.global_position + Vector3.UP * 0.2, sparkle, 12, 1.4, 0.07, 1.0, -1.5, Vector3.UP, 35.0)
	# Three rising hex rings, staggered.
	Fx.ring(pos, HEAL_RADIUS, Color(col.r, col.g, col.b, 0.85), 0.9, 2.0, true, 0.2)
	var tree := GameWorld.root.get_tree()
	for i in [1, 2]:
		tree.create_timer(0.18 * i).timeout.connect(func() -> void:
			Fx.ring(pos, HEAL_RADIUS * (1.0 - 0.18 * i), Color(col.r, col.g, col.b, 0.7), 0.8, 1.8, true, 0.2))


# --- Fireball -----------------------------------------------------------------------------

static func fireball_radius(power: float) -> float:
	return FIREBALL_RADIUS_BASE + FIREBALL_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


static func fireball_damage(power: float) -> float:
	return FIREBALL_DAMAGE * clampf(power, MIN_POWER, 1.0)


static func _cast_fireball(caster: Actor, power: float, aim: Vector3) -> void:
	var dir := aim - caster.global_position
	dir.y = 0.0
	# Explodes at the aim point unless it hits something first.
	var reach := clampf(dir.length(), 1.0, SPELL_RANGE)
	if dir.length() < 0.05:
		dir = caster.facing
	dir = dir.normalized()
	var radius := fireball_radius(power)
	var dmg := fireball_damage(power)
	var col := color_of("fireball")
	var team := GameWorld.other_team(caster.team)
	var src_ref: WeakRef = weakref(caster)   # the caster may be gone by the time the fireball lands
	var on_hit := func(_p: Projectile, _hit: Actor, pos: Vector3) -> void:
		for a in GameWorld.actors_in_radius(pos, radius, team):
			Fx.attach_hit_feedback(a)
		var src: Node = src_ref.get_ref() as Node
		Combat.explode(pos, radius, dmg, team, src, 1.0)
		# Every neutral actor takes the blast too: priced props (breaking one costs money) and employees.
		for n in GameWorld.actors_in_radius(pos, radius, GameWorld.TEAM_NEUTRAL):
			Fx.attach_hit_feedback(n)
		Combat.explode(pos, radius, dmg, GameWorld.TEAM_NEUTRAL, src, 1.0)
		Fx.explosion(pos, radius, col)
	var size := 0.22 + 0.12 * power
	# damage 0 on the direct hit: all damage comes from the explosion (monsters only).
	var p := Fx.make_projectile(caster, Combat.chest(caster) + dir * 0.6, dir, 0.0, FIREBALL_SPEED, reach, col, size, on_hit)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 3.0
	light.omni_range = 5.0
	p.add_child(light)
	var embers := CPUParticles3D.new()
	embers.amount = 24
	embers.lifetime = 0.45
	embers.local_coords = false
	embers.direction = Vector3.UP
	embers.spread = 60.0
	embers.initial_velocity_min = 0.2
	embers.initial_velocity_max = 1.0
	embers.gravity = Vector3(0, 1.0, 0)
	var sm := SphereMesh.new()
	sm.radius = size * 0.45
	sm.height = size * 0.9
	sm.radial_segments = 6
	sm.rings = 3
	sm.material = Fx.glow_material(Color(1.0, 0.6, 0.15, 0.8))
	embers.mesh = sm
	embers.scale_amount_curve = _shrink_curve()
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(embers)
	# A little muzzle flash at the caster's hands.
	Fx.flash_sphere(Combat.chest(caster) + dir * 0.6, 0.35, Color(col.r, col.g, col.b, 0.8), 0.2)


static func _shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	return c


# --- Armor --------------------------------------------------------------------------------

static func armor_multiplier(power: float) -> float:
	return lerpf(ARMOR_MULT_WEAK, ARMOR_MULT_STRONG, clampf(power, 0.0, 1.0))


static func armor_duration(power: float) -> float:
	return ARMOR_DURATION_BASE + ARMOR_DURATION_POWER * clampf(power, MIN_POWER, 1.0)


static func _cast_armor(caster: Actor, power: float, pos: Vector3) -> void:
	var zone := ArmorZone.new()
	zone.team = caster.team
	zone.power = clampf(power, MIN_POWER, 1.0)
	GameWorld.spawn(zone, pos)


# --- Corn ---------------------------------------------------------------------------------

static func corn_damage(power: float) -> float:
	return CornStrike.DAMAGE * clampf(power, MIN_POWER, 1.0)


static func _cast_corn(caster: Actor, power: float, target: Vector3) -> void:
	var strike := CornStrike.new()
	strike.power = clampf(power, MIN_POWER, 1.0)
	strike.source_team = caster.team
	strike.caster = caster
	GameWorld.spawn(strike, target)


# --- Tentacles -----------------------------------------------------------------------------

static func tentacles_radius(power: float) -> float:
	return TENTACLES_RADIUS_BASE + TENTACLES_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


## World units everyone in the radius is shoved (before each actor's shove_mult).
static func tentacles_distance(power: float) -> float:
	return TENTACLES_SHOVE_BASE + TENTACLES_SHOVE_POWER * clampf(power, MIN_POWER, 1.0)


static func tentacles_damage(power: float) -> float:
	return TENTACLES_DAMAGE * clampf(power, MIN_POWER, 1.0)


static func _cast_tentacles(caster: Actor, power: float, target: Vector3) -> void:
	var t := Tentacles.new()
	t.power = clampf(power, MIN_POWER, 1.0)
	t.source_team = caster.team
	t.caster = caster
	GameWorld.spawn(t, target)


# --- Teeth ---------------------------------------------------------------------------------

## Everyone (any team) within this of the aim point is afflicted.
static func teeth_radius(power: float) -> float:
	return TEETH_RADIUS_BASE + TEETH_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


## Seconds the teeth grow before the pop: 2.0 at the weakest, 1.0 at full power.
static func teeth_grow_time(power: float) -> float:
	return TEETH_GROW_SLOW - (TEETH_GROW_SLOW - TEETH_GROW_FAST) * clampf(power, MIN_POWER, 1.0)


## Damage to the carrier at the pop.
static func teeth_damage(power: float) -> float:
	return TEETH_DAMAGE * clampf(power, MIN_POWER, 1.0)


## Damage to everyone else near the carrier at the pop.
static func teeth_splash_damage(power: float) -> float:
	return TEETH_SPLASH_DAMAGE * clampf(power, MIN_POWER, 1.0)

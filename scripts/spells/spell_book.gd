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

# --- Vines
const VINES_RADIUS_BASE := 2.4
const VINES_RADIUS_POWER := 0.6
const VINES_ROOT_BASE := 1.6       ## seconds rooted at power ~0
const VINES_ROOT_POWER := 0.6      ## ... plus this at power 1 (2.2 s)

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
const FOLLOWS := ["heal", "coffee"]


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
	var spec := {"spell": id, "power": power, "target": target, "follow": snap_hero(aim) if FOLLOWS.has(id) else null,
		"extra": _cast_extra(id, caster, target)}
	if Net.shares_cast(caster):
		Net.send_cast(caster, spec)
		return true
	apply(caster, spec, GameWorld.time)
	return true


## What a spell needs from the moment of the cast besides the target (a fireball's launch point, direction and reach),
## so every machine flies the same shot.
static func _cast_extra(id: String, caster: Actor, target: Vector3) -> Dictionary:
	if id != "fireball":
		return {}
	var dir := target - caster.global_position
	dir.y = 0.0
	var reach := clampf(dir.length(), 1.0, SPELL_RANGE)   # explodes at the aim point unless it hits something first
	if dir.length() < 0.05:
		dir = caster.facing
	dir = dir.normalized()
	return {"o": Combat.chest(caster) + dir * 0.6, "d": dir, "r": reach}


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
	match id:
		"heal":
			_cast_heal(caster, power, target)
		"fireball":
			return _cast_fireball(caster, power, target, extra)
		"armor":
			return _cast_armor(caster, power, target, start)
		"corn":
			return _cast_corn(caster, power, target, start)
		"tentacles":
			return _cast_tentacles(caster, power, target, start)
		"teeth":
			Teeth.cast(caster, power, target)
		"vines":
			return _cast_vines(caster, power, target, start)
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


# --- Heal --------------------------------------------------------------------------------

## HP restored by Heal at a given power.
static func heal_amount(power: float) -> float:
	return HEAL_BASE * (0.4 + 0.6 * clampf(power, MIN_POWER, 1.0))


static func _cast_heal(caster: Actor, power: float, pos: Vector3) -> void:
	var col := color_of("heal")
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


# --- Fireball -----------------------------------------------------------------------------

static func fireball_radius(power: float) -> float:
	return FIREBALL_RADIUS_BASE + FIREBALL_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


static func fireball_damage(power: float) -> float:
	return FIREBALL_DAMAGE * clampf(power, MIN_POWER, 1.0)


static func _cast_fireball(caster: Actor, power: float, aim: Vector3, extra: Dictionary) -> Projectile:
	if extra.is_empty():
		extra = _cast_extra("fireball", caster, aim)
	var dir: Vector3 = extra["d"]
	var reach := float(extra["r"])   # explodes at the aim point unless it hits something first
	var from: Vector3 = extra["o"]
	var radius := fireball_radius(power)
	var dmg := fireball_damage(power)
	var col := color_of("fireball")
	var team := GameWorld.other_team(caster.team)
	var src_ref: WeakRef = weakref(caster)   # the caster may be gone by the time the fireball lands
	var on_hit := func(_p: Projectile, _hit: Actor, pos: Vector3) -> void:
		for a in GameWorld.actors_in_radius(pos, radius, team):
			Fx.attach_hit_feedback(a)
		var src: Node = src_ref.get_ref() as Node
		MonsterSenses.fire_at(pos, radius)   # fire lights a goblin scout's rockets, before the blast's damage lands
		ExplosiveProp.fire_at(pos, radius, src)   # ... and the fuse of an explosive prop (the host lights it; a soaked one fizzles)
		Combat.explode(pos, radius, dmg, team, src, 1.0)
		# Every neutral actor takes the blast too: priced props (breaking one costs money) and employees.
		for n in GameWorld.actors_in_radius(pos, radius, GameWorld.TEAM_NEUTRAL):
			Fx.attach_hit_feedback(n)
		Combat.explode(pos, radius, dmg, GameWorld.TEAM_NEUTRAL, src, 1.0)
		Burning.on_blast(pos, radius, power, src)   # anyone near may catch fire (all teams, see burning.gd)
		MonsterSenses.noise(pos, MonsterSenses.NOISE_FIREBALL, "fireball")   # (only the monsters this machine runs hear)
		Fx.explosion(pos, radius, col)
		Grime.mark(Grime.SCORCH, pos, radius)   # a scorch that fades after 30 s (no-op without a GrimeLayer)
	var size := 0.22 + 0.12 * power
	# damage 0 on the direct hit: all damage comes from the explosion (monsters only).
	var p := Fx.make_projectile(caster, from, dir, 0.0, FIREBALL_SPEED, reach, col, size, on_hit)
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
	Fx.flash_sphere(from, 0.35, Color(col.r, col.g, col.b, 0.8), 0.2)
	return p


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


static func _cast_armor(caster: Actor, power: float, pos: Vector3, start: float) -> ArmorZone:
	var zone := ArmorZone.new()
	zone.team = caster.team
	zone.power = clampf(power, MIN_POWER, 1.0)
	zone.start_time = start
	GameWorld.spawn(zone, pos)
	return zone


# --- Corn ---------------------------------------------------------------------------------

static func corn_damage(power: float) -> float:
	return CornStrike.DAMAGE * clampf(power, MIN_POWER, 1.0)


static func _cast_corn(caster: Actor, power: float, target: Vector3, start: float) -> CornStrike:
	var strike := CornStrike.new()
	strike.power = clampf(power, MIN_POWER, 1.0)
	strike.source_team = caster.team
	strike.caster = caster
	strike.start_time = start
	GameWorld.spawn(strike, target)
	return strike


# --- Tentacles -----------------------------------------------------------------------------

static func tentacles_radius(power: float) -> float:
	return TENTACLES_RADIUS_BASE + TENTACLES_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


## World units everyone in the radius is shoved (before each actor's shove_mult).
static func tentacles_distance(power: float) -> float:
	return TENTACLES_SHOVE_BASE + TENTACLES_SHOVE_POWER * clampf(power, MIN_POWER, 1.0)


static func tentacles_damage(power: float) -> float:
	return TENTACLES_DAMAGE * clampf(power, MIN_POWER, 1.0)


static func _cast_tentacles(caster: Actor, power: float, target: Vector3, start: float) -> Tentacles:
	var t := Tentacles.new()
	t.power = clampf(power, MIN_POWER, 1.0)
	t.source_team = caster.team
	t.caster = caster
	t.start_time = start
	GameWorld.spawn(t, target)
	return t


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


# --- Vines ---------------------------------------------------------------------------------

## Everyone (any team) within this of the aim point is rooted.
static func vines_radius(power: float) -> float:
	return VINES_RADIUS_BASE + VINES_RADIUS_POWER * clampf(power, MIN_POWER, 1.0)


## Seconds the roots hold.
static func vines_duration(power: float) -> float:
	return VINES_ROOT_BASE + VINES_ROOT_POWER * clampf(power, MIN_POWER, 1.0)


static func _cast_vines(caster: Actor, power: float, target: Vector3, start: float) -> Vines:
	var v := Vines.new()
	v.power = clampf(power, MIN_POWER, 1.0)
	v.source_team = caster.team
	v.caster = caster
	v.start_time = start
	GameWorld.spawn(v, target)
	return v


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

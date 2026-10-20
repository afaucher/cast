class_name FireballSpell
extends SpellDef
## Fireball: a shot that explodes where you aim (or on the first thing it hits). Its launch point, direction and reach are
## fixed on the caster's machine (cast_extra), so every machine flies the same shot.

const ID := "fireball"
const FOLLOWS := false

## Its row in SpellBook.SPELLS (name, cooldown, colour, description, spoken word, component, available).
const ROW := {
	"name": "Fireball", "cooldown": 5.0, "color": Color(1.0, 0.55, 0.15),
	"desc": "A fireball that explodes where you aim (or on the first thing it hits). Monsters, the client's property and bystanders (never heroes).", "word": "fireball",
	"component": "Ember horn", "available": true,
}

const FIREBALL_SPEED := 11.0
const FIREBALL_DAMAGE := 40.0
const FIREBALL_RADIUS_BASE := 1.4
const FIREBALL_RADIUS_POWER := 1.0


static func fireball_radius(power: float) -> float:
	return FIREBALL_RADIUS_BASE + FIREBALL_RADIUS_POWER * clampf(power, SpellBook.MIN_POWER, 1.0)


static func fireball_damage(power: float) -> float:
	return FIREBALL_DAMAGE * clampf(power, SpellBook.MIN_POWER, 1.0)


## The shot's launch point, direction and reach, from the moment of the cast.
static func cast_extra(caster: Actor, target: Vector3) -> Dictionary:
	var dir := target - caster.global_position
	dir.y = 0.0
	var reach := clampf(dir.length(), 1.0, SpellBook.SPELL_RANGE)   # explodes at the aim point unless it hits something first
	if dir.length() < 0.05:
		dir = caster.facing
	dir = dir.normalized()
	return {"o": Combat.chest(caster) + dir * 0.6, "d": dir, "r": reach}


static func cast(caster: Actor, power: float, aim: Vector3, _start: float, extra: Dictionary) -> Node:
	if extra.is_empty():
		extra = cast_extra(caster, aim)
	var dir: Vector3 = extra["d"]
	var reach := float(extra["r"])   # explodes at the aim point unless it hits something first
	var from: Vector3 = extra["o"]
	var radius := fireball_radius(power)
	var dmg := fireball_damage(power)
	var col := SpellBook.color_of("fireball")
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

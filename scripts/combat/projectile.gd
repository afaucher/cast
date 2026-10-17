class_name Projectile
extends Node3D
## Straight-flying projectile. Hits the first actor of `target_team` it
## touches, or dies on terrain taller than its flight height / max range.
## on_hit(projectile, actor_or_null, position) lets spells add effects
## (e.g. fireball explodes on impact with terrain too).

signal impacted(pos: Vector3, hit: Actor)

var source: Actor = null
var target_team := GameWorld.TEAM_MONSTERS
var direction := Vector3.FORWARD
var speed := 14.0
var damage := 10.0
var max_range := 14.0
var hit_radius := 0.25
var color := Color(1, 0.9, 0.4)
var size := 0.15
var on_hit: Callable = Callable()   ## optional: func(p: Projectile, hit: Actor, pos: Vector3)

var _travelled := 0.0


## Convenience constructor. `from` is a world point (use the shooter's chest height).
static func fire(shooter: Actor, from: Vector3, dir: Vector3, dmg: float, spd: float = 14.0, rng: float = 14.0) -> Projectile:
	var p := Projectile.new()
	p.source = shooter
	p.target_team = GameWorld.other_team(shooter.team)
	dir.y = 0.0
	p.direction = dir.normalized()
	p.damage = dmg
	p.speed = spd
	p.max_range = rng
	GameWorld.spawn(p, from)
	return p


func _ready() -> void:
	# Deferred so callers can set color/size right after fire().
	_build_visual.call_deferred()


## Who may write each var (see Net). A scheduled effect: the shot is one broadcast event and every
## machine flies it from these parameters.
func net_fields() -> Dictionary:
	return {
		"source": Net.SPAWN,      # will travel as an entity id in the shot event
		"target_team": Net.SPAWN, "direction": Net.SPAWN, "speed": Net.SPAWN, "damage": Net.SPAWN,
		"max_range": Net.SPAWN, "hit_radius": Net.SPAWN, "color": Net.SPAWN, "size": Net.SPAWN,
		"on_hit": Net.LOCAL,      # local effects (sparks, spell follow-ups), not shipped
		"_travelled": Net.LOCAL,
	}


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	add_child(mi)


func _physics_process(delta: float) -> void:
	var step := speed * delta
	var to := global_position + direction * step
	_travelled += step
	for a in GameWorld.hittable_in_radius(to, hit_radius, target_team):   # + breakables (mail packages)
		_impact(a, to)
		return
	var map: HexMap = GameWorld.map
	var g := map.ground_height(to) if map else NAN
	if not is_nan(g) and g > to.y:
		_impact(null, global_position)
		return
	global_position = to
	if _travelled >= max_range:
		_impact(null, to)


func _impact(hit: Actor, pos: Vector3) -> void:
	if hit:
		hit.apply_damage(damage, source)
	if on_hit.is_valid():
		on_hit.call(self, hit, pos)
	impacted.emit(pos, hit)
	queue_free()

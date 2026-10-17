class_name Tentacles
extends Node3D
## The Tentacles spell. After a short TELEGRAPH (game time) neon tentacles burst from the floor
## at this node's position and shove EVERYONE within the radius directly away from the center:
## heroes, the caster and monsters alike. Distance and radius grow with power; each actor's own
## shove_mult scales how far it goes (0 = immovable). Monsters take a little damage, heroes
## none. Anyone exactly at the center is pushed along their facing.
##
## The shove goes through Actor.shove, so ledges, walls, pits, falls and the friendly-fire
## protection (a hero-caused shove never downs a hero) all apply. The visuals are a separate
## node, TentaclesFx, running on the same clock.

const TELEGRAPH := 0.25

var power := 1.0
var source_team := GameWorld.TEAM_HEROES
var caster: Actor = null

var _start := 0.0
var _burst_done := false
var _fx: TentaclesFx = null


func _ready() -> void:
	_start = GameWorld.time
	_fx = TentaclesFx.new()
	_fx.radius = SpellBook.tentacles_radius(power)
	_fx.telegraph = TELEGRAPH
	_fx.power = power
	add_child(_fx)


func _physics_process(_delta: float) -> void:
	var t := GameWorld.time - _start
	if not _burst_done and t >= TELEGRAPH:
		_burst()
	elif _burst_done and t >= TELEGRAPH + TentaclesFx.LIFETIME:
		queue_free()


func _burst() -> void:
	_burst_done = true
	var src: Node = caster if is_instance_valid(caster) else null
	var radius := SpellBook.tentacles_radius(power)
	var dist := SpellBook.tentacles_distance(power)
	var dmg := SpellBook.tentacles_damage(power)
	Grime.mark(Grime.CRACKS, global_position, radius)   # floor cracks that fade after 30 s
	for a in GameWorld.actors_in_radius(global_position, radius):
		var away := a.global_position - global_position
		away.y = 0.0
		a.shove(away if away.length() > 0.05 else a.facing, dist, src)
		if a.team == GameWorld.TEAM_MONSTERS:
			Fx.attach_hit_feedback(a)
			a.apply_damage(dmg, src)
		elif a.is_in_group("breakables"):
			a.apply_damage(dmg, src)   # mail packages burst when the tentacles come up under them

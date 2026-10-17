class_name ArrowShot
extends Projectile
## Wick's arrow: a Projectile that can pierce. `pierce` is how many actors it may hit (a tap shot 1,
## a drawn shot 3); each actor is hit once and the arrow flies on until it has used its hits, reaches
## max_range or meets terrain taller than its flight height. A drawn shot is longer, brighter and
## trails a glow.

const STEP := 0.2                  ## max distance per collision check (the arrow is fast)

var pierce := 1
var drawn := false
var hits: Array[Actor] = []        ## actors struck so far, in order (tests read this)

var _hit_ids := {}                 ## instance id -> true, so nothing is hit twice


## Fire an arrow from `shooter`'s chest toward `dir` (X/Z). `drawn` styles it as the charged shot.
static func shoot(shooter: Actor, dir: Vector3, dmg: float, spd: float, rng: float, pierce_count: int, is_drawn: bool, tint: Color) -> ArrowShot:
	var a := ArrowShot.new()
	a.source = shooter
	a.target_team = GameWorld.other_team(shooter.team)
	dir.y = 0.0
	a.direction = dir.normalized()
	a.damage = dmg
	a.speed = spd
	a.max_range = rng
	a.pierce = maxi(1, pierce_count)
	a.drawn = is_drawn
	a.color = tint
	a.size = 0.12 if is_drawn else 0.09
	a.hit_radius = 0.2
	GameWorld.spawn(a, Combat.chest(shooter) + a.direction * 0.5)
	return a


func _physics_process(delta: float) -> void:
	var left := speed * delta
	while left > 0.0001:
		var s := minf(left, STEP)
		left -= s
		var to := global_position + direction * s
		_travelled += s
		for a in GameWorld.hittable_in_radius(to, hit_radius, target_team):   # + breakables (mail packages)
			if _hit_ids.has(a.get_instance_id()):
				continue
			_strike(a, to)
			if pierce <= 0:
				_impact(null, to)
				return
		var map: HexMap = GameWorld.map
		var g := map.ground_height(to) if map else NAN
		if not is_nan(g) and g > to.y:
			_impact(null, global_position)
			return
		global_position = to
		if _travelled >= max_range:
			_impact(null, to)
			return


func _strike(a: Actor, pos: Vector3) -> void:
	_hit_ids[a.get_instance_id()] = true
	hits.append(a)
	pierce -= 1
	Fx.attach_hit_feedback(a)
	a.apply_damage(damage, source)
	var sparks: Array[Color] = [color.lightened(0.6), Color.WHITE]
	Fx.burst(pos, sparks, 10 if drawn else 6, 2.4, 0.07, 0.25, 4.0)
	if on_hit.is_valid():
		on_hit.call(self, a, pos)


## The arrow ends (range, terrain or its last hit). Hits were already dealt in _strike().
func _impact(_hit: Actor, pos: Vector3) -> void:
	impacted.emit(pos, hits.back() if not hits.is_empty() else null)
	queue_free()


func _build_visual() -> void:
	var shaft_len := 0.95 if drawn else 0.6
	var mi := MeshInstance3D.new()
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.05 if drawn else 0.035, 0.05 if drawn else 0.035, shaft_len)
	mi.mesh = shaft
	mi.material_override = Fx.glow_material(Color(color, 0.95))
	add_child(mi)
	if drawn:
		var halo := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.2
		sph.height = 0.4
		halo.mesh = sph
		halo.scale = Vector3(1.0, 1.0, 2.6)
		halo.material_override = Fx.glow_material(Color(color, 0.35))
		add_child(halo)
	# The arrow flies along its own -Z.
	if direction.length() > 0.001:
		look_at(global_position + direction, Vector3.UP)

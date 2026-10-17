class_name PropDebris
extends Node3D
## Faceted shards thrown by a breaking prop: a handful of little low-poly rocks painted in the prop's
## colours that fly out, tumble, bounce once on the floor, settle and then shrink away.
## Purely visual and deterministic enough (uses GameWorld.rng). Cleans itself up.
##
##   PropDebris.burst(pos, PropModels.palette("gold_toilet"), 14, 1.0)

const LIFE := 2.4
const SHRINK := 0.5
const GRAVITY := 16.0

class Shard extends RefCounted:
	var node: MeshInstance3D
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var bounced := false
	var rest := false
	var size := 0.1

var _shards: Array[Shard] = []
var _age := 0.0


## Spawn `amount` shards at `pos`. `scale` scales shard size and throw speed (a chip is 0.5, a
## big prop 1.2).
static func burst(pos: Vector3, colors: Array[Color], amount: int = 12, scale: float = 1.0) -> PropDebris:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree() or colors.is_empty():
		return null
	var d := PropDebris.new()
	d.name = "PropDebris"
	var rng := GameWorld.rng
	var mat := PropModels.material()
	for i in amount:
		var sh := Shard.new()
		sh.size = rng.randf_range(0.07, 0.17) * scale
		var col: Color = colors[i % colors.size()]
		var soup := LowPoly.boulder(Vector3(sh.size, sh.size * rng.randf_range(0.5, 1.0), sh.size * rng.randf_range(0.7, 1.2)),
				0, 0.2, col, 17 + i, 0.08)
		var mi := MeshInstance3D.new()
		mi.mesh = soup.to_mesh()
		mi.material_override = mat
		mi.set_meta("no_flash", true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.add_child(mi)
		sh.node = mi
		var ang := rng.randf() * TAU
		var out := Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(1.0, 3.4) * scale
		sh.vel = out + Vector3.UP * rng.randf_range(2.6, 5.4) * (0.6 + 0.4 * scale)
		sh.spin = Vector3(rng.randf_range(-9, 9), rng.randf_range(-9, 9), rng.randf_range(-9, 9))
		mi.position = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.5), rng.randf_range(-0.3, 0.3)) * scale
		d._shards.append(sh)
	GameWorld.spawn(d, pos)
	return d


func shard_count() -> int:
	return _shards.size()


func _physics_process(delta: float) -> void:
	_age += delta
	var map: HexMap = GameWorld.map
	for sh in _shards:
		if sh.rest or not is_instance_valid(sh.node):
			continue
		sh.vel.y -= GRAVITY * delta
		sh.node.position += sh.vel * delta
		sh.node.rotation += sh.spin * delta
		var wp := global_position + sh.node.position
		var floor_y := global_position.y
		if map != null:
			var g := map.ground_height(wp)
			if not is_nan(g):
				floor_y = g
		var local_floor := floor_y - global_position.y + sh.size * 0.5
		if sh.node.position.y <= local_floor and sh.vel.y < 0.0:
			sh.node.position.y = local_floor
			if not sh.bounced:
				sh.bounced = true
				sh.vel = Vector3(sh.vel.x * 0.45, -sh.vel.y * 0.3, sh.vel.z * 0.45)
				sh.spin *= 0.5
			else:
				sh.rest = true
				sh.vel = Vector3.ZERO
	if _age > LIFE:
		var k := clampf((_age - LIFE) / SHRINK, 0.0, 1.0)
		for sh in _shards:
			if is_instance_valid(sh.node):
				sh.node.scale = Vector3.ONE * (1.0 - k)
		if k >= 1.0:
			queue_free()

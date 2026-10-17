class_name PackageSpill
extends Node3D
## What spills out of a broken mail package: loose faceted bits (a few skulls, yogurt tubs with their lids
## rolling off, green pickles) and the box's flattened cardboard flaps. They fly out, bounce once on the floor,
## tumble or roll to a stop and stay put, then shrink away so the whole spill is gone LIFE seconds after the
## break (the same 30 s as the grime layer's player-caused marks). Purely visual: it uses its own seeded
## RandomNumberGenerator (never GameWorld.rng), has no collision and frees itself.
##
##   PackageSpill.burst(pos, "skulls", seed, away_dir, 0.4)    # pos = the floor under the box; contents: skulls / yogurt / pickles / "" (flaps only)

const LIFE := 30.0              ## seconds from the break until the spill is gone
const SHRINK := 4.0             ## ... it shrinks over the last SHRINK of them
const GRAVITY := 16.0
const GROUP := "package_spills"
const ROLL_DRAG := 2.4          ## per second, horizontal speed lost while a bit slides or rolls on the floor
const REST_SPEED := 0.12

## Bits per content kind: [bit kind, count min, count max]. Flaps come with every break.
const MAKEUP := {
	"skulls": [["skull", 3, 5]],
	"yogurt": [["tub", 4, 6], ["lid", 2, 4]],
	"pickles": [["pickle", 5, 8]],
}
const FLAPS := 4

class Bit extends RefCounted:
	var node: Node3D
	var kind := ""
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var bounced := false
	var rest := false
	var floor_off := 0.05      ## centre height above the floor when resting
	var rolls := false         ## tubs: roll along the floor instead of sliding

var bits: Array[Bit] = []
var age := 0.0

var _all_rest := false


## Throw a spill out of the broken box standing on the floor at `pos`; the bits start `height` above it. `away` is
## the X/Z direction the spill leans toward (away from the wall the box stood against); zero scatters it all around.
static func burst(pos: Vector3, contents: String, seed_value: int, away: Vector2 = Vector2.ZERO, height: float = 0.3) -> PackageSpill:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return null
	var sp := PackageSpill.new()
	sp.name = "PackageSpill"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var makeup: Array = MAKEUP.get(contents, [])
	var serial := 0
	for entry: Array in makeup:
		var count := rng.randi_range(int(entry[1]), int(entry[2]))
		for i in count:
			serial += 1
			sp._add(String(entry[0]), serial, rng, away, 0.9, height)
	for i in FLAPS:
		serial += 1
		sp._add("flap", serial, rng, away, 1.0, height)
	GameWorld.spawn(sp, pos)
	return sp


func _ready() -> void:
	add_to_group(GROUP)


func _add(kind: String, serial: int, rng: RandomNumberGenerator, away: Vector2, spread: float, height: float) -> void:
	var b := Bit.new()
	b.kind = kind
	b.node = PackageModels.bit(kind, serial)
	b.floor_off = PackageModels.rest_height(kind)
	b.rolls = kind == "tub"
	add_child(b.node)
	# Out of the open box: biased away from the wall, any way if there is no bias.
	var ang := rng.randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	if away.length() > 0.01:
		dir = (away.normalized() * 1.2 + dir).normalized()
	var speed := rng.randf_range(1.0, 2.7) * spread
	var up := rng.randf_range(2.2, 4.2) if kind != "flap" else rng.randf_range(3.0, 5.0)
	b.vel = Vector3(dir.x * speed, up, dir.y * speed)
	b.node.position = Vector3(rng.randf_range(-0.2, 0.2), height + rng.randf_range(-0.1, 0.15), rng.randf_range(-0.2, 0.2))
	b.node.rotation = Vector3(0.0, rng.randf() * TAU, 0.0)
	b.spin = Vector3(rng.randf_range(-7, 7), rng.randf_range(-6, 6), rng.randf_range(-7, 7))
	bits.append(b)


func bit_count() -> int:
	return bits.size()


func count_of(kind: String) -> int:
	var n := 0
	for b in bits:
		if b.kind == kind:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	age += delta
	if not _all_rest:
		_simulate(delta)
	if age >= LIFE - SHRINK:
		var k := clampf((age - (LIFE - SHRINK)) / SHRINK, 0.0, 1.0)
		for b in bits:
			if is_instance_valid(b.node):
				b.node.scale = Vector3.ONE * maxf(1.0 - k, 0.001)
	if age >= LIFE:
		queue_free()


func _simulate(delta: float) -> void:
	var map: HexMap = GameWorld.map
	var resting := 0
	for b in bits:
		if b.rest or not is_instance_valid(b.node):
			resting += 1
			continue
		b.vel.y -= GRAVITY * delta
		var from := b.node.position
		var np := from + b.vel * delta
		var wp := global_position + np
		var floor_y := global_position.y
		if map != null:
			# walls and pits stop a bit; it keeps to the floor it was thrown on
			var cell: HexMap.Cell = map.get_cell(Hex.from_world(wp))
			var g := map.ground_height(wp)
			if cell == null or cell.type == HexMap.Tile.WALL or is_nan(g) or g > global_position.y + 0.3:
				b.vel.x *= -0.2
				b.vel.z *= -0.2
				np.x = from.x
				np.z = from.z
			else:
				floor_y = g
		b.node.position = np
		var on_floor_y := floor_y - global_position.y + b.floor_off
		if b.node.position.y <= on_floor_y and b.vel.y < 0.0:
			b.node.position.y = on_floor_y
			if not b.bounced:
				b.bounced = true
				b.vel = Vector3(b.vel.x * 0.55, -b.vel.y * 0.32, b.vel.z * 0.55)
				b.spin *= 0.5
			else:
				b.vel.y = 0.0
				var flat := Vector2(b.vel.x, b.vel.z)
				flat *= exp(-ROLL_DRAG * delta)
				b.vel.x = flat.x
				b.vel.z = flat.y
				_roll_or_settle(b, delta)
				if flat.length() < REST_SPEED:
					_settle(b)
					resting += 1
					continue
		else:
			b.node.rotation += b.spin * delta
	_all_rest = resting >= bits.size()


## On the floor and still moving: tubs roll along their travel, everything else just stops spinning.
func _roll_or_settle(b: Bit, delta: float) -> void:
	var flat := Vector3(b.vel.x, 0.0, b.vel.z)
	if b.rolls and flat.length() > 0.01:
		var axis := Vector3.UP.cross(flat.normalized())
		b.node.rotate(axis.normalized(), flat.length() * delta / 0.09)
	else:
		b.spin = Vector3.ZERO


## Come to rest: everything lies flat or stands upright (a tub ends up on its side half the time).
func _settle(b: Bit) -> void:
	b.rest = true
	b.vel = Vector3.ZERO
	b.spin = Vector3.ZERO
	var yaw := b.node.rotation.y
	b.node.rotation = Vector3(0.0, yaw, 0.0)
	if b.kind == "tub" and (int(absf(yaw) * 10.0) % 2 == 0):
		b.node.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
		b.floor_off = PackageModels.rest_height("tub")
	elif b.kind == "tub":
		b.floor_off = PackageModels.rest_height("tub_up")
	_snap_to_floor(b)


func _snap_to_floor(b: Bit) -> void:
	var map: HexMap = GameWorld.map
	var g := global_position.y
	if map != null:
		var gh := map.ground_height(global_position + b.node.position)
		if not is_nan(gh):
			g = gh
	b.node.position.y = g - global_position.y + b.floor_off

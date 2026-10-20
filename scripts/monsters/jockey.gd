class_name Jockey
extends "res://scripts/monsters/swarmer.gd"
## The imp gunner riding an "imp" laser shark (docs/design/sharks.md, "The rider": user, 2026-10-19, "gunner, as you
## proposed"). An ordinary imp (kind "swarmer": it counts for "Exterminate imps" and "everything", it is free to kill)
## with JOCKEY_HP, seated in its shark's saddle while `mounted`: no AI of its own, it rides along (the shark swings the
## emitter for it, aims with its eyes and fires). It never climbs back on.
##   - knocked off: any shove of KNOCK_SHOVE or more on it (Rebar's fist, the spin, tentacles, the bowl, a blast) or a
##     daze: it tumbles into the water beside the shark and is a plain imp from then on;
##   - killed: it falls off dead (an imp kill);
##   - its shark killed: it jumps to the nearest deck and fights on foot.
## Online: `mounted` rides world.dismount {id, how, x, y, z} (NetWorld); while mounted every screen draws it in its shark's
## saddle as that screen shows the shark (LOCAL), so it never lags behind its mount.

signal dismounted(how: String)

const SharkModels := preload("res://scripts/art/lowpoly/props/shark_models.gd")
const JOCKEY_HP := 24.0
const KNOCK_SHOVE := 1.0

var mount: Node3D = null          ## its Shark (spawn data)
var mounted := true


func _init() -> void:
	super._init()
	display_name = "Imp gunner"
	max_hp = JOCKEY_HP


func _ready() -> void:
	super._ready()
	if mounted and model != null:
		model.idle_enabled = false


func net_fields() -> Dictionary:
	var f := super()
	f.merge({"mount": Net.SPAWN, "mounted": Net.OWNER})
	return f


func _physics_process(delta: float) -> void:
	if dead:
		return
	if mounted:
		if mount == null or not is_instance_valid(mount) or bool(mount.get("dead")):
			dismount("jump")
		else:
			ride()
			# its shark aiming at someone puts the gunner in the fight (the AI allies' restraint joins fights only)
			var v: Variant = mount.get("charge_victim")
			if v != null and is_instance_valid(v) and not (v as Actor).dead:
				target = v
				state = State.CHASE
			_update_visual(delta)
			return
	super._physics_process(delta)


## Sit in the saddle (every screen, each frame, from the shark as this screen shows it).
func ride() -> void:
	if not mounted or dead or mount == null or not is_instance_valid(mount):
		return
	var b: SharkBody = mount.get("body")
	if b == null or b.shark == null:
		return
	var xf := b.saddle()
	global_position = xf.origin
	var f := -xf.basis.z
	f.y = 0.0
	if f.length() > 0.001:
		facing = f.normalized()


func _update_visual(delta: float) -> void:
	super._update_visual(delta)
	if mounted and model != null and not dead:
		var lean := float(mount.get("_telegraph")) if mount != null and is_instance_valid(mount) and int(mount.get("state")) == 5 else 0.0
		SharkModels.seat(model, lean)
		_visual.position.y = 0.0   # (no walking bob in the saddle)


func net_tick(delta: float) -> void:
	if mounted:
		ride()
	super.net_tick(delta)


## A shove: a hard one knocks it off (then it slides like any imp); a light one, it hangs on.
func shove(dir: Vector3, distance: float, source: Node = null) -> void:
	if mounted and not Net.is_copy(self):
		if dead or distance < KNOCK_SHOVE:
			return
		dismount("knocked", dir)
	super.shove(dir, distance, source)


func _on_dazed(seconds: float) -> void:
	super._on_dazed(seconds)
	if mounted and not Net.is_copy(self):
		dismount("knocked")


## Off the shark for good (the host). "knocked": into the water beside it; "jump": to the nearest deck (its shark died).
func dismount(how: String, dir: Vector3 = Vector3.ZERO) -> void:
	if not mounted:
		return
	mounted = false
	var spot := global_position
	var s := mount as Shark
	if s != null and is_instance_valid(s) and s.steer != null:
		var p := Vector2(s.global_position.x, s.global_position.z)
		var out := s.steer.out_of_water(p)
		if how == "jump":
			var q := p
			for _i in 30:
				if s.steer.rim(q) < -0.7:
					break
				q += out * 0.15
			spot = Vector3(q.x, 0.0, q.y)
		else:
			var side := Vector2(dir.x, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 0.01 else Vector2(-s.facing.z, s.facing.x)
			var q := s.steer.clamp_in(p + side * 0.9)
			spot = Vector3(q.x, 0.0, q.y)
		var map := GameWorld.map
		if map != null:
			var g := map.ground_height(spot)
			spot.y = g if not is_nan(g) else s.global_position.y
	global_position = spot
	_after_dismount()
	home = global_position
	_home_set = true
	var h := _nearest_hero(aggro_range * 1.5, false)
	if h != null:
		aggro(h)
	dismounted.emit(how)


## A client: the host's world.dismount.
func net_dismount(_how: String, at: Vector3) -> void:
	if not mounted:
		return
	mounted = false
	global_position = at
	_after_dismount()


func _after_dismount() -> void:
	if model != null:
		model.idle_enabled = true
		model.apply_idle(0.0, 0.0)
	_visual.position = Vector3.ZERO

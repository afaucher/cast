class_name NecroProcession
extends Node3D
## LOOK-DEV ONLY (docs/design/necro-look.md, "The procession"): an acolyte leading a file of zombies round a loop, raising
## the downed bodies it passes, for the gym (GymSpawns "necro:procession"). Plain cosmetic nodes like NecroBody: no HP, no
## AI, no collision, nothing networked. It shows the decided behaviour (new-themes.md, "Zombies and acolytes"): acolytes
## travel the map with monsters and raise the bodies they come across.
##
## The loop: the acolyte (the cowl) walks an oval (RX by RZ round the node), its zombies GAP apart behind it and a second
## acolyte bringing up the rear (the user, 2026-10-29: the file was "Too cramped" and "Too small": wider apart, four zombies,
## "maybe with a second acolyte"). Each carries a lantern that lights the floor round it (AcolyteModel). When the leader comes
## level with a downed body beside the path it stops (the file stops with it), turns to the body and raises it (RAISE_T):
## arms up, the body pushes up on its arms, stands, and shambles to the back of the file. Each time the acolyte starts a
## new lap, the zombies past BASE fall where they are: the gym's stand-in for the crew knocking them down, so the next lap
## has bodies to raise again.

const RX := 6.0
const RZ := 3.8
const SPEED := 0.8                  ## the file's walk (a zombie's shamble is drawn for ZombieModel.WALK_SPEED 0.9)
const GAP := 1.8                    ## between walkers along the path
const BASE := 4                     ## the zombies that always walk with it
const SIDE := 0.8                   ## a downed body lies this far out from the path
const STOP_BEFORE := 0.2            ## the acolyte stops this far along the path before the body's spot
const RAISE_T := 3.4                ## arms up 0.8, the body pushes up from 0.4 to 2.4, holds, stands at 2.8, arms down
const BODIES_AT: Array[float] = [0.2, 0.42]   ## where the first lap's bodies lie (fractions of the loop), ahead of the file
const SAMPLES := 96

var acolyte: AcolyteModel                   ## the leader: it raises the dead
var rear: AcolyteModel                      ## the second acolyte, at the back of the file
var rear_d := 0.0                           ## how far behind the leader the rear acolyte walks (along the path)
var walkers: Array[ZombieModel] = []        ## the file behind the acolyte, in order
var downed: Array[Dictionary] = []          ## {model, s}: bodies lying beside the path at arc length s
var joining: Array[ZombieModel] = []        ## raised zombies walking to the back of the file
var s := 0.0                                ## the acolyte's arc length along the loop
var lap := 0
var raising: Dictionary = {}                ## {body: {model, s}, t}: the raise under way, or empty
var _pts: PackedVector3Array = []
var _cum: PackedFloat32Array = []
var length := 0.0


func _init() -> void:
	name = "NecroProcession"
	_build_path()


func _ready() -> void:
	# (each acolyte goes to its place before it enters the tree: its lantern's motes start where it is)
	acolyte = AcolyteModel.new("cowl")
	acolyte.position = point(s)["pos"]
	add_child(acolyte)
	for i in BASE:
		_add_walker(_new_zombie(i))
	for f: float in BODIES_AT:
		_lay_down(_new_zombie(walkers.size() + downed.size()), f * length)
	rear_d = _rear_target()
	rear = AcolyteModel.new("cowl")
	rear.offset_clock(1.3)
	rear.position = point(s - rear_d)["pos"]
	add_child(rear)
	_place_file(0.0)


func _new_zombie(i: int) -> ZombieModel:
	var z := ZombieModel.new("mourner" if i % 2 == 0 else "digger")
	z.offset_clock(0.37 * float(i))
	add_child(z)
	return z


func _add_walker(z: ZombieModel) -> void:
	z.idle_enabled = true
	walkers.append(z)


## Leave zombie `z` lying beside the path at arc length `at`, face down, waiting for an acolyte.
func _lay_down(z: ZombieModel, at: float) -> void:
	z.idle_enabled = false
	var p := point(at)
	z.position = p["pos"] + _outward(p) * SIDE
	# lying across the game camera's view (its screen right, either way), so it reads as down and not as standing
	z.rotation.y = deg_to_rad(-45.0 if randf_from(at) < 0.5 else 135.0) + (randf_from(at + 1.0) - 0.5) * 0.5
	z.pose_rise(0.0)
	downed.append({"model": z, "s": fposmod(at, length)})


static func randf_from(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


func _process(delta: float) -> void:
	advance(delta)


## Step the procession `dt` seconds (the gym's _process; tests call it directly).
func advance(dt: float) -> void:
	var ds := 0.0
	if raising.is_empty():
		var before := s
		ds = SPEED * dt
		s += ds
		if s >= length:
			s -= length
			lap += 1
			_drop_extras()
		var b := _body_ahead(before, s)
		if not b.is_empty():
			s = fposmod(float(b["s"]) - STOP_BEFORE, length)
			raising = {"body": b, "t": 0.0}
	else:
		_raise_step(dt)
	# the rear acolyte keeps its place behind the file: it waits while the gap to its place opens (a raised zombie joining)
	# and walks a little faster to close it (the file shortened), never backwards
	rear_d += ds
	var target := _rear_target()
	if rear_d > target:
		rear_d = maxf(target, rear_d - SPEED * 1.5 * dt)
	_place_file(dt)
	_walk_joiners(dt)


## The downed body whose stopping spot the acolyte passed going from a to b, or {}.
func _body_ahead(a: float, b: float) -> Dictionary:
	for d: Dictionary in downed:
		var stop := fposmod(float(d["s"]) - STOP_BEFORE, length)
		var passed := (a <= stop and stop < b) if b >= a else (stop >= a or stop < b)
		if passed:
			return d
	return {}


func _raise_step(dt: float) -> void:
	raising["t"] = float(raising["t"]) + dt
	var t: float = raising["t"]
	var body: Dictionary = raising["body"]
	var z: ZombieModel = body["model"]
	var arms := clampf(t / 0.8, 0.0, 1.0) * (1.0 - clampf((t - (RAISE_T - 0.6)) / 0.6, 0.0, 1.0))
	acolyte.set_raise(arms)
	_face(acolyte, z.position - acolyte.position)
	if t < 2.8:
		z.pose_rise(clampf((t - 0.4) / 2.0, 0.0, 1.0))
	elif z.is_lying():
		z.stand_up()
		z.idle_enabled = true
		downed.erase(body)
		joining.append(z)
	if t >= RAISE_T:
		acolyte.set_raise(0.0)
		raising = {}


## Where the rear acolyte belongs: GAP behind the last walker and the zombies on their way to join.
func _rear_target() -> float:
	return GAP * float(walkers.size() + joining.size() + 1)


## The acolyte at s, each walker GAP behind the one before; the joiners' slots come after them; the rear acolyte last.
func _place_file(_dt: float) -> void:
	var p := point(s)
	acolyte.position = p["pos"]
	if raising.is_empty():
		_face(acolyte, p["dir"])
	for i in walkers.size():
		var q := point(s - GAP * float(i + 1))
		walkers[i].position = q["pos"]
		_face(walkers[i], q["dir"])
	if rear != null:
		var r := point(s - rear_d)
		rear.position = r["pos"]
		_face(rear, r["dir"])


## Raised zombies shamble to the back of the file, then take their place in it.
func _walk_joiners(dt: float) -> void:
	for z: ZombieModel in joining.duplicate():
		var slot: Vector3 = point(s - GAP * float(walkers.size() + 1))["pos"]
		var to := slot - z.position
		to.y = 0.0
		if to.length() < 0.15:
			joining.erase(z)
			_add_walker(z)
			continue
		var step := minf(ZombieModel.WALK_SPEED * dt, to.length())
		z.position += to.normalized() * step
		_face(z, to)


## Each new lap: the zombies past BASE fall where they walk, as bodies for the acolyte to raise again.
func _drop_extras() -> void:
	while walkers.size() > BASE:
		var z: ZombieModel = walkers.pop_back()
		var at := s - GAP * float(walkers.size() + 1)
		_lay_down(z, at)


## Turn `m` (a model facing local -Z) to face `dir` on the floor.
static func _face(m: Node3D, dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.001:
		m.rotation.y = atan2(-dir.x, -dir.z)


# ------------------------------------------------------------------ the path

func _build_path() -> void:
	_pts.clear()
	_cum.clear()
	length = 0.0
	for i in SAMPLES + 1:
		var a := TAU * float(i) / float(SAMPLES)
		_pts.append(Vector3(cos(a) * RX, 0.0, sin(a) * RZ))
		if i > 0:
			length += _pts[i].distance_to(_pts[i - 1])
		_cum.append(length)


## The loop at arc length `at` (wrapped): {pos, dir} (dir the way the file walks).
func point(at: float) -> Dictionary:
	var u := fposmod(at, length)
	var i := 1
	while i < _cum.size() - 1 and _cum[i] < u:
		i += 1
	var seg := _cum[i] - _cum[i - 1]
	var k := (u - _cum[i - 1]) / seg if seg > 0.0 else 0.0
	return {"pos": _pts[i - 1].lerp(_pts[i], k), "dir": (_pts[i] - _pts[i - 1]).normalized()}


## Away from the loop's middle, at a point of it.
func _outward(p: Dictionary) -> Vector3:
	var d: Vector3 = p["dir"]
	return Vector3(-d.z, 0.0, d.x).normalized() * (1.0 if Vector3(-d.z, 0.0, d.x).dot(p["pos"]) > 0.0 else -1.0)

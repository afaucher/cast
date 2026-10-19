class_name ElevatorArrival
extends Node3D
## The elevator on a floor (docs/design/elevator-options.md, "Built"): the set piece (ElevatorModel in the job's look and the
## floor's form, posed from SitePlan.elevator) and the crew's ARRIVAL by it on the floors below the first.
##
## The arrival (floors 2 and 3) is a plain timeline (time = seconds since the start, advanced in _process, so pause and the
## elevator freeze stop it); every moment is a pure function of `time` (_pose), the same on every machine:
##   0.00  the crew stands in the car's front row, doors shut (sill red); the needle swings from the floor above to this one
##   0.35  the doors open (to 1.0); the sill turns green and the car light comes up
##   0.75  the heroes step out one after another (CREW_STAGGER apart, CREW_WALK each) through the doorway to their spots
##         in front, the first on the landing (the exit cell)
##   1.86  `finished`: control goes back to the player
## Skippable: skip() jumps to the end (the game calls it on any key or click, like the van's arrival).
##
## Without an arrival (floor 1, parked, after it): the doors stay shut until a living hero comes within CALL_DIST of the
## doorway (or stands in the car), then open; they shut again CLOSE_DELAY after the last one has gone. That is each machine's
## own presentation (LOCAL): collision never depends on the doors (HexMap keeps the doorway open).
##
##   var e := ElevatorArrival.spawn(plan.elevator, floor_n, crew, heroes, true)   # crew = [] on floor 1 (no arrival)
##   e.finished.connect(func() -> void: controller.enabled = true)

signal finished                      ## the crew is out and standing at its spots
signal doors_opened                  ## audio hook: the ding (the arrival's doors, and the shut doors opening for a hero)

const T_OPEN0 := 0.35
const T_OPEN1 := 1.0
const T_CREW0 := 0.75
const CREW_STAGGER := 0.18
const CREW_WALK := 0.75
const DURATION := 1.86               ## until the crew is out (T_CREW0 + 2 x CREW_STAGGER + CREW_WALK)
const NEEDLE_TIME := 0.6
const CALL_DIST := 3.0               ## a hero this close to the doorway (world units) calls the car: the doors open
const CLOSE_DELAY := 1.2
const DOOR_TIME := 0.55              ## a full open or close outside the arrival

var plan: Dictionary = {}
var floor_n := 1
var model: ElevatorModel
var crew: Array[Hero] = []           ## arriving heroes in spot order (middle, left, right); [] = no arrival
var watch: Array[Hero] = []          ## the heroes whose presence opens the doors
var time := 0.0
var playing := false                 ## the timeline is running
var done := true                     ## no arrival, or the crew is out (finished emitted)
var ground := 0.0
var _door := 0.0
var _close_t := 0.0
var _fired := false
var _hidden_brains: Array[Node] = []


## Build the elevator for `rec` (SitePlan.elevator) under `parent` (default GameWorld.root). `arriving` heroes (in spot order)
## ride it in: play = true starts the arrival, false puts them straight at their spots outside. `heroes` open the doors by
## coming near. null when the floor has no elevator.
static func spawn(rec: Dictionary, floor_number: int, arriving: Array[Hero], heroes: Array[Hero], play: bool, parent: Node = null) -> ElevatorArrival:
	var root: Node = parent if parent != null else GameWorld.root
	if root == null or rec.is_empty():
		return null
	var a := ElevatorArrival.new()
	a.plan = rec
	a.floor_n = floor_number
	a.crew = arriving
	a.watch = heroes
	root.add_child(a)
	a.setup()
	if not arriving.is_empty():
		if play:
			a.begin()
		else:
			a.park()
	return a


func _init() -> void:
	name = "Elevator"


## Co-op authority (docs/design/networking.md): the elevator is planned from the floor seed (SitePlan.elevator and its
## collision in HexMap are SPAWN); the doors, the needle and the arrival are each machine's own presentation (LOCAL). The
## arrival walks every hero on every machine, like the van's, before the hero sync starts.
func net_fields() -> Dictionary:
	return {
		"plan": Net.SPAWN, "floor_n": Net.SPAWN, "ground": Net.LOCAL, "model": Net.LOCAL, "crew": Net.LOCAL,
		"watch": Net.LOCAL, "time": Net.LOCAL, "playing": Net.LOCAL, "done": Net.LOCAL, "_door": Net.LOCAL,
		"_close_t": Net.LOCAL, "_fired": Net.LOCAL, "_hidden_brains": Net.LOCAL,
	}


func setup() -> void:
	var pos: Vector2 = plan["pos"]
	ground = float(plan.get("level", 0)) * Hex.LEVEL_HEIGHT
	global_position = Vector3(pos.x, ground, pos.y)
	rotation_degrees.y = float(plan["yaw"])
	var form := "wall" if str(plan["place"]) == ElevatorGeo.PLACE_WALL else "column"
	model = ElevatorModel.new(str(plan.get("look", "service")), form)
	add_child(model)
	model.set_indicator(risk(floor_n))
	model.set_door_open(0.0)


## The needle on the risk gauge for floor n: the first floor is the low-risk end, the last the origin's red.
static func risk(n: int) -> float:
	var span := maxf(1.0, float(ContractRun.FLOOR_COUNT - 1))
	return clampf(0.1 + 0.8 * float(n - 1) / span, 0.0, 1.0)


# --------------------------------------------------------------------------- control

## Start the arrival: the crew in the car, the doors shut, the timeline from zero.
func begin() -> void:
	time = 0.0
	playing = true
	done = false
	_fired = false
	_pause_brains(true)
	_pose(0.0)


## No animation: the crew stands at its spots outside, the doors open (they shut once everyone has walked off).
func park() -> void:
	playing = false
	time = DURATION
	_pose(DURATION)
	_finish_crew()
	done = true


## Skip to the end: the crew out, the doors open. Safe at any time (also when done).
func skip() -> void:
	if done:
		return
	playing = false
	time = DURATION
	_pose(DURATION)
	_finish_crew()
	done = true
	finished.emit()


## True while the crew is still on its way out (the player has no control yet).
func is_running() -> bool:
	return playing and not done


## The crew is out (or there was no arrival).
func is_done() -> bool:
	return done


func door_open_amount() -> float:
	return _door


func _process(delta: float) -> void:
	if not done:
		if not playing:
			return   # held at its first frame until the shared start (the game sets time and playing)
		time += delta
		_pose(time)
		if time >= DURATION:
			playing = false
			_finish_crew()
			done = true
			finished.emit()
		return
	_call_doors(delta)


## Outside the arrival: open for a hero near the doorway, shut CLOSE_DELAY after the last one went.
func _call_doors(delta: float) -> void:
	var want := false
	for h in watch:
		if is_instance_valid(h) and not h.dead:
			var p := Vector2(h.global_position.x, h.global_position.z)
			if ElevatorGeo.door_distance(plan, p) <= CALL_DIST:
				want = true
				break
	if want:
		_close_t = CLOSE_DELAY
	else:
		_close_t = maxf(0.0, _close_t - delta)
	var target := 1.0 if (want or _close_t > 0.0) else 0.0
	if is_equal_approx(_door, target):
		return
	if _door <= 0.0 and target > 0.0:
		doors_opened.emit()
	_door = move_toward(_door, target, delta / DOOR_TIME)
	model.set_door_open(_door)


func _pause_brains(on: bool) -> void:
	if on:
		_hidden_brains.clear()
		for h in crew:
			if is_instance_valid(h):
				var brain := h.get_node_or_null("AllyBrain")
				if brain != null:
					brain.set_physics_process(false)
					_hidden_brains.append(brain)
	else:
		for brain in _hidden_brains:
			if is_instance_valid(brain):
				brain.set_physics_process(true)
		_hidden_brains.clear()


func _finish_crew() -> void:
	var steps: Array = plan.get("steps", [])
	for i in crew.size():
		var h := crew[i]
		if not is_instance_valid(h) or i >= steps.size():
			continue
		h.visible = true
		_place_hero(h, steps[i])
		h.facing = _out3()
		# an AI ally re-forms round the leader out in the room, not behind it (the car): its formation trails the heading
		var brain := h.get_node_or_null("AllyBrain")
		if brain != null and brain.has_method("set_heading"):
			brain.call("set_heading", -_out3())
	_pause_brains(false)
	_door = 1.0
	_close_t = CLOSE_DELAY
	model.set_door_open(1.0)
	model.set_indicator(risk(floor_n))


func _out3() -> Vector3:
	var n: Vector2 = plan["out"]
	return Vector3(n.x, 0.0, n.y)


func _place_hero(h: Hero, spot: Vector2) -> void:
	var y := ground
	if GameWorld.map != null:
		var g := GameWorld.map.ground_height(Vector3(spot.x, 0.0, spot.y))
		if not is_nan(g):
			y = g
	h.global_position = Vector3(spot.x, y, spot.y)


# --------------------------------------------------------------------------- the timeline

static func _ease_out(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - u) * (1.0 - u) * (1.0 - u)


static func _ease_in_out(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## Everything as a function of the time since the start.
func _pose(t: float) -> void:
	model.set_indicator(lerpf(risk(floor_n - 1), risk(floor_n), _ease_in_out(t / NEEDLE_TIME)))
	_door = _ease_out((t - T_OPEN0) / (T_OPEN1 - T_OPEN0))
	model.set_door_open(_door)
	if t >= T_OPEN0 and not _fired:
		_fired = true
		doors_opened.emit()
	if done:
		return   # (once the crew is out it is theirs)
	var inside: Array = plan.get("inside", [])
	var via: Array = plan.get("via", [])
	var steps: Array = plan.get("steps", [])
	for i in crew.size():
		var h := crew[i]
		if not is_instance_valid(h) or i >= steps.size():
			continue
		h.visible = true
		var a: Vector2 = inside[i]
		var b: Vector2 = via[i]
		var c: Vector2 = steps[i]
		var u := _ease_in_out((t - (T_CREW0 + CREW_STAGGER * float(i))) / CREW_WALK)
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var s := u * (l1 + l2)
		var p := a.lerp(b, s / l1) if s < l1 and l1 > 0.0001 else b.lerp(c, clampf((s - l1) / maxf(l2, 0.0001), 0.0, 1.0))
		_place_hero(h, p)
		var d := (b - a) if s < l1 else (c - b)
		if u > 0.0 and u < 1.0 and d.length() > 0.01:
			h.facing = Vector3(d.x, 0.0, d.y).normalized()
		else:
			h.facing = _out3()

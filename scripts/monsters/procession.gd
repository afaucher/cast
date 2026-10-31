class_name Procession
extends Node
## A procession of the dead (docs/design/haunted-build-plan.md, H4; new-themes.md "Zombies and acolytes", decided; the look:
## necro-look.md "The procession", the formation the user approved in the look test, NecroProcession). An acolyte LEADS a file
## of zombies GAP apart along the way it walks, a second acolyte at the REAR, round a ROUTE between rooms of the floor (a loop
## of room spots, SitePlan.processions: ProcessionPlanner). When an acolyte comes across a zombie's body it stops (the file
## stops with it) and raises it (Acolyte); the raised zombie joins the back of the file. When the crew is seen the zombies fight
## (their own senses, or the acolyte's call: engage) and the acolytes flee (Acolyte); the file holds while any of it is away,
## and walks on when they are back in their places.
##
## THE FILE: the leader walks to the route's next spot (Monster.march_to: its own path finding) and leaves a TRAIL behind it
## (ProcessionPath, the look test's arc-length path); member i of the file stands at the trail's head arc minus GAP * (i + 1),
## the rear acolyte last. A walker never walks back along the trail: when a raised zombie joins, the ones behind it wait for
## their place to come to them (the look test's rear acolyte).
##
## Online (a host-owned group of host monsters, the new-content checklist: owned actors): every machine builds the procession
## from the seed (its members are seed-built monsters with net ids), but only the host walks it: its route, trail and file are
## PRIVATE to the host, and the members replicate as any monster does (the stream, the keyframe for a late joiner). drive() is
## called from a member's own AI (Monster._tick_idle), which runs only where the member is simulated: on a client nothing here
## ever runs. No event of its own: a raise is the acolyte's wind-up (world.windup) and the body's world.rise.

const GAP := 1.8                    ## between walkers along the trail (the look test's, the user's "Too cramped" fixed)
const FILE := 4                     ## zombies in the file as it starts (the look test's four)
const ACOLYTES := 2                 ## the leader and the rear
const MARCH_SPEED := 1.0            ## the file's walk (a zombie's shamble is drawn for ZombieModel.WALK_SPEED 0.9)
const HURRY := 1.5                  ## a walker more than HURRY_FROM behind its place walks this much faster
const HURRY_FROM := 0.8
const IN_PLACE := 0.15              ## a walker this close to its place stands
const ARRIVE := 1.2                 ## the leader is at a route spot this close
const TRAIL_STEP := 0.25            ## the trail gets a point every this far the leader walks
const TRAIL_SPARE := 6.0            ## the trail keeps this much behind the last walker's place
const REGROUP := 1.5                ## the leader walks back to the trail's head first when it is farther than this from it
const STRAGGLE := 3.0               ## a walker farther than this from its place holds the file ...
const HALT_MAX := 20.0              ## ... for at most this long while nobody fights: then the stragglers are left behind
const STUCK_SKIP := 3               ## a leader stuck this many times on a leg goes for the next spot

var rooms: Array[String] = []       ## the route's rooms, in order (the plan's; logs and tests)
var route: Array[Vector3] = []      ## the spots it walks between, in order, round and round
var leg := 0                        ## the route spot the leader walks to
var trail: ProcessionPath = ProcessionPath.new()
var acolytes: Array[Monster] = []   ## [leader, rear]: the first living one leads
var zombies: Array[Monster] = []    ## the file, in order
var halted := false                 ## the file stands this frame (an acolyte raising or away, a zombie fighting or away)
var legs := 0                       ## route spots reached (tests)
var joined := 0                     ## raised zombies that joined the file (tests)
var _target_arc := {}               ## a walker's instance id -> the arc of the place it walks to (never back)
var _halt_t := 0.0
var _frame := -1


## Who may write each var (see Net). The host walks it; a client's copy is built from the seed and never runs.
func net_fields() -> Dictionary:
	return {
		"rooms": Net.SPAWN,
		"route": Net.PRIVATE, "leg": Net.PRIVATE, "trail": Net.PRIVATE, "acolytes": Net.PRIVATE, "zombies": Net.PRIVATE,
		"halted": Net.PRIVATE, "legs": Net.PRIVATE, "joined": Net.PRIVATE, "_target_arc": Net.PRIVATE,
		"_halt_t": Net.PRIVATE, "_frame": Net.PRIVATE,
	}


## A procession round `spots` (world points), its trail laid along `trail_pts` (the way it came: the leader stands at the
## last point), walking next to spot `next_leg`.
static func make(spots: Array[Vector3], trail_pts: Array[Vector3], room_tags: Array[String] = [], next_leg: int = 0) -> Procession:
	var p := Procession.new()
	p.name = "Procession"
	p.route = spots
	p.rooms = room_tags
	p.leg = clampi(next_leg, 0, maxi(spots.size() - 1, 0))
	p.trail = ProcessionPath.through(trail_pts)
	return p


## The place in the file for walker `i` behind the leader (the zombies first, then the rear acolyte): its arc on the trail.
func slot_arc(i: int) -> float:
	return trail.head_arc() - GAP * float(i + 1)


## The file's length behind the leader (every walker's place).
func file_length() -> float:
	return GAP * float(zombies.size() + maxi(acolytes.size() - 1, 0))


## Put `m` in the procession: an acolyte (the first leads) or a zombie at the back of the file.
func add_member(m: Monster, is_acolyte: bool) -> void:
	if is_acolyte:
		acolytes.append(m)
	else:
		zombies.append(m)
	m.procession = self


## A raised zombie joins the back of the file (Acolyte, after its raise). It walks to its place from where it stood up.
func join(z: Monster) -> void:
	if z == null or zombies.has(z):
		return
	zombies.append(z)
	z.procession = self
	joined += 1


## The acolyte that leads now (the first living one), or null.
func leader() -> Monster:
	for a in acolytes:
		if _alive(a):
			return a
	return null


## Every living member (the acolytes, then the file).
func members() -> Array[Monster]:
	var out: Array[Monster] = []
	for m in acolytes + zombies:
		if _alive(m):
			out.append(m)
	return out


## Where member `m` belongs now: its place's point on the trail (the leader: the trail's head). INF when it is not a member.
func place_of(m: Monster) -> Vector3:
	var i := _file_index(m)
	if m == leader():
		return trail.head()
	if i < 0:
		return Vector3.INF
	return trail.point(maxf(float(_target_arc.get(m.get_instance_id(), slot_arc(i))), slot_arc(i)))["pos"]


## An acolyte saw the crew (or was hit): the file turns on them. Every resting zombie of it goes for `hero` (or, without one,
## walks to `at` on alert). The host's.
func engage(at: Vector3, hero: Actor = null) -> void:
	for z in zombies:
		if not _alive(z) or not Net.simulates(z) or not z.is_passive():
			continue
		if hero != null and is_instance_valid(hero) and not hero.dead:
			z.aggro(hero)
		else:
			z.alert(at)


## The host keeps the file's books every frame, even while none of it rests (the dead leave, the halt is judged). A client's
## copy does nothing.
func _physics_process(delta: float) -> void:
	if Net.is_host():
		_update(delta)


## Called by a resting member's AI (Monster._tick_idle) each frame: keep its place. True: the procession has it (it walks, or
## stands in its place), so it neither looks round nor lives idly. Only where the member is simulated (the host).
func drive(m: Monster, delta: float) -> bool:
	if m == null or m.dead or not Net.simulates(m):
		return false
	_update(delta)
	if m.procession != self:
		return false   # (left behind or out of the file this frame)
	if m == leader():
		return _lead(m, delta)
	return _follow(m, delta)


# --- The file ------------------------------------------------------------------------------------------------------------

## Once a frame: drop the dead and the gone, and judge whether the file stands.
func _update(delta: float) -> void:
	var f := Engine.get_physics_frames()
	if f == _frame:
		return
	_frame = f
	for list: Array[Monster] in [acolytes, zombies]:
		for i in range(list.size() - 1, -1, -1):
			var m: Variant = list[i]
			if _alive(m):
				continue
			list.remove_at(i)
			if is_instance_valid(m):
				_target_arc.erase((m as Monster).get_instance_id())
				if (m as Monster).procession == self:
					(m as Monster).procession = null   # (a body leaves the file: an acolyte's raise puts it back, join)
	if acolytes.is_empty():
		_disband()
		return
	var fight := false
	var hold := false
	var strays: Array[Monster] = []
	for a in acolytes:
		if a.state != Monster.State.IDLE or (a.has_method("is_raising") and bool(a.call("is_raising"))):
			hold = true
		elif a != leader() and _off_place(a):
			hold = true
	for z in zombies:
		if z.state == Monster.State.CHASE or z.state == Monster.State.ATTACK:
			fight = true
		elif z.state != Monster.State.IDLE or z.is_helpless() or _off_place(z):
			hold = true
			strays.append(z)
	halted = fight or hold
	if fight or not hold:
		_halt_t = 0.0
		return
	_halt_t += delta
	if _halt_t >= HALT_MAX and not strays.is_empty():
		# nobody fights and they have not come back: the file walks on without them (they are ordinary monsters from here)
		for z in strays:
			zombies.erase(z)
			_target_arc.erase(z.get_instance_id())
			z.procession = null
		_halt_t = 0.0


## Both acolytes are dead: the file is just zombies now, each an ordinary monster where it stands.
func _disband() -> void:
	for i in zombies.size():
		var z: Variant = zombies[i]
		if is_instance_valid(z) and (z as Monster).procession == self:
			(z as Monster).procession = null
	zombies.clear()
	halted = true


func _off_place(m: Monster) -> bool:
	var p := place_of(m)
	return p != Vector3.INF and GameWorld.flat_distance(m.global_position, p) > STRAGGLE


## The leader: back to the trail's head if it wandered (it fled, it raised a body off the path), else on to the route's next
## spot while the file walks, laying the trail behind it.
func _lead(m: Monster, delta: float) -> bool:
	if trail.is_empty():
		trail.add(m.global_position)
	var head := trail.head()
	if GameWorld.flat_distance(m.global_position, head) > REGROUP:
		m.march_to(head, delta, MARCH_SPEED * HURRY)
		return true
	if halted or route.is_empty():
		_face(m, trail.point(trail.head_arc())["dir"])
		return true
	var goal := route[leg]
	if GameWorld.flat_distance(m.global_position, goal) <= ARRIVE or m._stuck_n >= STUCK_SKIP:
		m._stuck_n = 0
		leg = (leg + 1) % route.size()
		legs += 1
		goal = route[leg]
	m.march_to(goal, delta, MARCH_SPEED)
	var at := m.global_position
	if at.distance_to(trail.head()) >= TRAIL_STEP:
		trail.add(at)
		trail.trim(trail.head_arc() - file_length() - TRAIL_SPARE)
	return true


## A walker of the file: to its place on the trail (hurrying when it is well behind), never back along it; standing in its
## place it faces the way the file walks.
func _follow(m: Monster, delta: float) -> bool:
	var i := _file_index(m)
	if i < 0:
		return false
	var key := m.get_instance_id()
	var want := slot_arc(i)
	var arc := minf(maxf(float(_target_arc.get(key, want)), want), trail.head_arc())
	_target_arc[key] = arc
	var p := trail.point(arc)
	var d := GameWorld.flat_distance(m.global_position, p["pos"])
	if d > IN_PLACE:
		m.march_to(p["pos"], delta, MARCH_SPEED * (HURRY if d > HURRY_FROM else 1.0))
	else:
		_face(m, p["dir"])
	return true


## Its index behind the leader: the zombies first (0..), then the acolytes after the leader. -1: not in the file.
func _file_index(m: Monster) -> int:
	var zi := zombies.find(m)
	if zi >= 0:
		return zi
	var lead := leader()
	var n := zombies.size()
	for a in acolytes:
		if a == lead or not _alive(a):
			continue
		if a == m:
			return n
		n += 1
	return -1


## (untyped: a member may have been freed, a dead acolyte's fade)
static func _alive(m: Variant) -> bool:
	if not is_instance_valid(m):
		return false
	var a := m as Monster
	return a != null and not a.dead and a.is_inside_tree() and not a.is_queued_for_deletion()


static func _face(m: Monster, dir: Vector3) -> void:
	dir.y = 0.0
	if dir.length() > 0.001:
		m.facing = dir.normalized()

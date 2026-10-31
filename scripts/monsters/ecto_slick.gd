class_name EctoSlick
extends Node3D
## An ecto blob's slick (docs/design/haunted-build-plan.md, "H3b as built"): one SEGMENT of the ribbon of ectoplasm a crawling
## blob leaves behind it, from `a` (the last segment's end) to `b` (where the blob was SLICK_STEP later). WIDTH across, it
## lasts LIFE seconds and:
##   SLOWS   the living whose feet are on it, the crew and the staff (heroes, employees; never a monster: the dead's own ooze),
##           walking speed x SLOW (Actor.effective_speed asks speed_mult). The goo patch's LOCAL rule: derived from where the
##           actor stands and the segments every screen has, so nothing travels for it.
##   WASHES  Damp's drizzle on it (Damp._burst -> wash_at) removes every segment it reaches; the rest of the ribbon stays.
## Fire does nothing to it (ectoplasm does not burn).
## THE LOOK: every screen draws a blob's live segments as ribbons of the ectoplasm look's film (EctoplasmLook.trail, the
## user's pick): a CHAIN (the blob's) of consecutive segments (`seq` without a gap) is one ribbon through their points,
## narrowing to a point at its old end, under its oldest segment. A segment added, washed or dried redraws its chain's
## ribbons (once a frame, _flush). A washed segment's own piece fades out with Damp's wash look (EctoplasmLook.set_wash).
##
## NETWORKING (networking.md: a host-arbitrated world object, made during play; NetObjects "RUNTIME OBJECTS", the goo patch's
## shape). Only the blob's owner (the host) lays a segment (EctoBlob._trail -> lay -> Net.announce -> obj.new {k "ecto_slick"});
## every client builds the same segment (net_copy) on its own clock. The host decides its one change, WASHED (wash_at acts
## only on segments this machine owns; Damp's burst runs on every machine) and tells everyone `obj.slick {id}` (net_link /
## net_event). The drying is scheduled from its shared start on every machine. A late joiner gets every live segment (not
## washed, not dried: late_join_state, section `new`, rebuilt as obj.new would).

signal changed

const KIND := "ecto_slick"           ## NetObjects.RUNTIME_OBJECTS
const GROUP := "ecto_slicks"
const WIDTH := 1.0                   ## across (the look test's ribbon: 1.0 at the blob)
const LIFE := 14.0                   ## a segment dries up this long after it was laid
const SLOW := 0.6                    ## walking speed on the slick (goo is 0.5, pool water 0.75)
const FEET_DY := 0.6                 ## feet this far above or below the slick are not on it
const WASH_TIME := 0.5
const STATE_SLICK := 0
const STATE_WASHED := 2
const VARIANT := "film"              ## the ectoplasm look the user picked

## The live segments on this machine (Actor.effective_speed asks every frame: an empty list costs nothing).
static var _live: Array[EctoSlick] = []
## The look: chain -> the ribbon nodes drawn for it now; chains waiting for a redraw this frame.
static var _looks := {}
static var _dirty := {}

var a := Vector3.ZERO                ## the segment's old end (world)
var b := Vector3.ZERO                ## its new end (world)
var width := WIDTH
var start_time := INF                ## its birth on this machine's clock (the host's GameWorld.time, converted on a client)
var look_seed := 1
var chain := 0                       ## its blob's chain: the segments drawn as one ribbon
var seq := 0                         ## its number in the chain (a gap breaks the ribbon)
var washed := false

var _end := 0.0
var _gone_at := INF
var _wash_look: Node3D = null


## Who may write each var (see Net). Host-arbitrated: where, when and how it looks are SPAWN (the obj.new row), its one change
## the host's (obj.slick), the rest every screen's own.
func net_fields() -> Dictionary:
	return {
		"a": Net.SPAWN, "b": Net.SPAWN, "width": Net.SPAWN, "start_time": Net.SPAWN, "look_seed": Net.SPAWN,
		"chain": Net.SPAWN, "seq": Net.SPAWN,
		"washed": Net.OWNER,
		"_end": Net.LOCAL, "_gone_at": Net.LOCAL, "_wash_look": Net.LOCAL,
	}


## A new segment from `from` to `to` (on the floor there), number `n` of chain `chain_id`, born now. The owner's: it is
## announced (Net.announce; offline nothing is sent).
static func lay(from: Vector3, to: Vector3, chain_id: int, n: int) -> EctoSlick:
	var s := make(from, to, GameWorld.time, chain_id, n)
	Net.announce(s)
	return s


## A segment born at `start` (this machine's clock), spawned under the world. The caller announces it (lay does).
static func make(from: Vector3, to: Vector3, start: float, chain_id: int, n: int, seed_value: int = 0) -> EctoSlick:
	var s := EctoSlick.new()
	s.a = from
	s.b = to
	s.start_time = start
	s.chain = chain_id
	s.seq = n
	s.look_seed = seed_value if seed_value != 0 else 1 + absi(hash([chain_id, n])) % 9973
	GameWorld.spawn(s, (from + to) * 0.5)
	return s


# --- Asking (every machine) -----------------------------------------------------------------------------------------

## Walking speed multiplier for `act` from the slick under its feet (1.0 off it). Actor.effective_speed.
static func speed_mult(act: Actor) -> float:
	if _live.is_empty() or act == null or not affects(act) or act.is_airborne():
		return 1.0
	for s in _live:
		if is_instance_valid(s) and s.covers(act.global_position, act.radius * 0.5):
			return SLOW
	return 1.0


## Who the slick holds back: the living (heroes, the staff). Never a monster, a prop or a gate.
static func affects(act: Actor) -> bool:
	return act.team == GameWorld.TEAM_HEROES or act.is_in_group("employees")


## Is `pos` (a body `slack` wide) on this segment right now?
func covers(pos: Vector3, slack: float = 0.0) -> bool:
	if washed or GameWorld.time >= _end:
		return false
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(pos.x - a.x, pos.z - a.z)
	var k := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	if (ap - ab * k).length() > width * 0.5 + slack:
		return false
	return absf(pos.y - lerpf(a.y, b.y, k)) <= FEET_DY


## Any live segment under `pos`.
static func covers_any(pos: Vector3, slack: float = 0.0) -> bool:
	for s in _live:
		if is_instance_valid(s) and s.covers(pos, slack):
			return true
	return false


## The segments on the floor now (not washed, not dried).
static func live() -> Array[EctoSlick]:
	var out: Array[EctoSlick] = []
	for s in _live:
		if is_instance_valid(s) and not s.washed and GameWorld.time < s._end:
			out.append(s)
	return out


## The flat distance from `pos` to the segment's centre line.
func line_distance(pos: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(pos.x - a.x, pos.z - a.z)
	var k := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * k).length()


func state_code() -> int:
	return STATE_WASHED if washed else STATE_SLICK


# --- What changes it (the owner decides) ----------------------------------------------------------------------------

## Damp's drizzle at `pos` (radius `r`): every segment it reaches that this machine owns is washed away. Damp's burst runs
## on every machine; only the owner's segments (the host's online) are decided here.
static func wash_at(pos: Vector3, r: float) -> int:
	var n := 0
	for s in _live.duplicate():
		if not is_instance_valid(s) or s.washed or GameWorld.time >= s._end or not Net.owns(s):
			continue
		if s.line_distance(pos) <= r + s.width * 0.5:
			s.wash()
			n += 1
	return n


## Wash it away (Damp). The owner's decision, or a client showing the host's (obj.slick).
func wash() -> void:
	if washed:
		return
	washed = true
	_gone_at = GameWorld.time + WASH_TIME
	changed.emit()
	_mark(chain)
	if is_inside_tree():
		_wash_look = _ribbon([a - (b - a) * 0.6, a, b], look_seed)
		add_child(_wash_look)
	if GameWorld.root != null and GameWorld.root.is_inside_tree():
		Sfx.play_at("goo_wash", global_position)
		var fizz: Array[Color] = [Color(0.92, 0.96, 1.0), EctoplasmLook.color_now()]
		Fx.burst(global_position + Vector3.UP * 0.2, fizz, 6, 1.2, 0.07, 0.5, -1.2, Vector3.UP, 60.0, false)


# --- Life ----------------------------------------------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(GROUP)
	if start_time == INF:
		start_time = GameWorld.time
	_end = start_time + LIFE
	_mark(chain)


func _enter_tree() -> void:
	if not _live.has(self):
		_live.append(self)


func _exit_tree() -> void:
	_live.erase(self)


func _physics_process(_delta: float) -> void:
	var t := GameWorld.time
	if t >= _gone_at or (not washed and t >= _end):
		_gone_at = minf(_gone_at, t)
		_mark(chain)
		queue_free()


func _process(_delta: float) -> void:
	if _wash_look != null and is_instance_valid(_wash_look):
		EctoplasmLook.set_wash(_wash_look, clampf(1.0 - (_gone_at - GameWorld.time) / WASH_TIME, 0.0, 1.0))


# --- The look (every screen) ---------------------------------------------------------------------------------------------

## Redraw `chain_id`'s ribbons at the end of this frame.
static func _mark(chain_id: int) -> void:
	if _dirty.is_empty():
		(func() -> void: EctoSlick._flush()).call_deferred()
	_dirty[chain_id] = true


## Every dirty chain: its old ribbons go, and each run of consecutive live segments is drawn as one ribbon under its oldest.
static func _flush() -> void:
	var chains := _dirty.keys()
	_dirty.clear()
	for c: int in chains:
		for n in (_looks.get(c, []) as Array):
			if is_instance_valid(n):
				n.queue_free()
		_looks.erase(c)
		var segs: Array[EctoSlick] = []
		for s in _live:
			if is_instance_valid(s) and s.chain == c and not s.washed and not s.is_queued_for_deletion() \
					and GameWorld.time < s._end and s.is_inside_tree():
				segs.append(s)
		if segs.is_empty():
			continue
		segs.sort_custom(func(x: EctoSlick, y: EctoSlick) -> bool: return x.seq < y.seq)
		var drawn: Array = []
		var run: Array[EctoSlick] = [segs[0]]
		for i in range(1, segs.size() + 1):
			var nxt: EctoSlick = segs[i] if i < segs.size() else null
			var prev: EctoSlick = run[run.size() - 1]
			if nxt != null and nxt.seq == prev.seq + 1 and nxt.a.distance_to(prev.b) < 0.05:
				run.append(nxt)
				continue
			drawn.append(_draw_run(run))
			if nxt != null:
				run = [nxt]
		_looks[c] = drawn


## One ribbon through a run's points (its oldest end first), a child of its oldest segment.
static func _draw_run(run: Array[EctoSlick]) -> Node3D:
	var head := run[0]
	var pts: Array[Vector3] = [head.a]
	for s in run:
		pts.append(s.b)
	var rib := head._ribbon(pts, head.look_seed)
	head.add_child(rib)
	return rib


## The film's ribbon through world points `pts`, in this segment's own space.
func _ribbon(pts: Array[Vector3], seed_value: int) -> Node3D:
	var local: Array[Vector3] = []
	for p in pts:
		local.append(p - global_position)
	return EctoplasmLook.trail(VARIANT, local, width, seed_value)


# --- The net-object contract (NetObjects) ---------------------------------------------------------------------------------

## Net ids: runtime objects are numbered as they are made (NetObjects.adopt); this only keeps NetFloor's order total.
func net_order() -> int:
	return 3


## A client's copy keeps its clock running (the drying, the look); it decides nothing.
func net_make_copy() -> void:
	set_meta(Net.COPY_META, true)


## The host: the segment washed goes to everyone as `obj.slick {id}`.
func net_link(objects: NetObjects, id: int) -> void:
	objects.link(changed, _net_changed.bind(objects, id))


func _net_changed(objects: NetObjects, id: int) -> void:
	objects.tell("obj.slick", {"id": id, "st": state_code()})
	objects.count("slick_out")


## A client: the host washed it.
func net_event(kind: String, data: Dictionary, objects: NetObjects) -> void:
	if kind != "obj.slick":
		return
	objects.count("slick_in")
	if int(data.get("st", STATE_SLICK)) == STATE_WASHED:
		wash()


## The host: what a client needs to build it (obj.new): its ends, its birth (shared clock), its width and look, its chain.
func net_spawn_row(objects: NetObjects) -> Array:
	return [a, b, objects.host_stamp(start_time), width, look_seed, chain, seq]


## A client: the host's segment from its row, on this machine's clock.
static func net_copy(row: Array, objects: NetObjects) -> Node:
	if row.size() < 7 or GameWorld.root == null:
		return null
	var s := EctoSlick.new()
	s.a = row[0]
	s.b = row[1]
	s.start_time = objects.local_stamp(float(row[2]))
	s.width = float(row[3])
	s.look_seed = int(row[4])
	s.chain = int(row[5])
	s.seq = int(row[6])
	if GameWorld.time >= s.start_time + LIFE:
		s.free()
		return null   # (dried already: a late row that arrived late)
	GameWorld.spawn(s, (s.a + s.b) * 0.5)
	return s


## The host: a late joiner's row: the segment as obj.new would build it (a washed or dried one is not sent).
func late_join_state(objects: NetObjects, id: int) -> Dictionary:
	if washed or GameWorld.time >= _end:
		return {}
	return {"new": [id, KIND, net_spawn_row(objects)]}


## The late joiner: a segment it already has (never, as built: it builds the floor fresh) has nothing to take: a live
## segment's only state is that it is there.
func apply_late_join(_section: String, _row: Array, _objects: NetObjects) -> void:
	pass

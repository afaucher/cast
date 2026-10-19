class_name OfficeDoor
extends Node3D
## OFFICE DOOR (docs/design/exploration.md, "Decisions: map information, fog and doors", 2026-10-19): a door in
## the ROOM WALL at a NARROW doorway, on Doorways' door line (the chord between the two jambs where the corridor's walls
## end at the room), filling it jamb to jamb at the wall's height. Which doorways get one is DoorPlan's. Its look is one of
## OfficeDoorModel's STYLES ("single" swing door with a wired-glass light and a lever handle, "double" doors with push
## bars and a lit sign, a frosted glass "slider" suite front with a logo band).
##
##   WALK INTO IT  a hero (or anyone who is not a monster) walking into a shut door opens it at once. A MONSTER walking
##                 into it stops for MONSTER_DELAY (rooted, the door shudders) and then opens it: pathing needs nothing
##                 new, the door is never a wall for find_path.
##   E             shuts an open door (or opens a shut one): use(). Not while a body stands in it.
##   NOISE         a HERO opening it is heard (MonsterSenses.noise, OPEN_NOISE, a "door" row in the combat log): monsters
##                 in the room behind turn toward it. A monster opening one makes no noise for the crew; a brute's
##                 smash is loud (SMASH_NOISE). The host makes it (it decides the door and runs the monsters).
##   SHUT          blocks SIGHT (HexMap blockers: line_of_sight, so monster sight and room fog) and MUFFLES noise (half a
##                 sound's reach through it: MonsterSenses.noise asks HexMap.crosses_blocker). It does not stop bodies,
##                 shoves or arrows: a body walking in opens it.
##   SMASH         a BRUTE that is chasing (CHASE / ATTACK / ALERT) walks into a shut door and slams it: its real slam (the
##                 red ring, SMASH_WINDUP, Combat.slam on whoever stands near) and the door bursts into hex rubble, a loud
##                 noise, and one Ledger damage line ("Office door", PRICE, the brute: "demons" on the invoice). Billed
##                 once: `broken` is final.
##
## NETWORKING: a host-arbitrated object (networking.md's fourth shape), like a priced prop. The HOST decides `shut` and
## `broken` (OWNER); every machine shows them and keeps its own blocker from them. Built HOST / SOLO ONLY this round
## (NETWORKED false): on a client a walk-in or E would be a request (Net.request(door, "door", {shut})) that NetObjects
## does not handle yet; until it does, the door ignores a client's push (what is left: OfficeDoor.NETWORKED, NetEvents).

signal state_changed(door: OfficeDoor)
signal smashed(door: OfficeDoor, by: Node)

const GROUP := "office_doors"
const NETWORKED := false        ## doors are host / solo only this round (see the header)
const LABEL := "Office door"
const PRICE := 900              ## the Ledger line when a brute smashes one
const DEFAULT_STYLE := "double"   ## the user's pick (2026-10-19)
const OPEN_TIME := 0.32
const SHUT_TIME := 0.45
const TOUCH := 0.5              ## a body this close to the door (past its radius) and walking toward it opens it
const USE_RANGE := 2.2          ## E reaches a door this close (and the hero is inside its width)
const MONSTER_DELAY := 0.5      ## a monster stops this long to open a shut door
const OPEN_NOISE := 7.0         ## a hero opening a door is heard this far (a fireball is 10)
const SMASH_NOISE := 12.0       ## a brute smashing one
const SMASH_WINDUP := 0.9       ## the brute's slam wind-up (Brute.WINDUP)
const SMASH_ROOT := SMASH_WINDUP + 0.35
const SCAN_MARGIN := 2.6        ## actors this far past the door's half width are not looked at

# Spawn data: from the doorway (Doorways), the same on every machine.
var doorway_id := -1
var style := DEFAULT_STYLE
var cell := Vector2i.ZERO       ## the doorway cell (the corridor's first full cell past the door)
var axis := Vector3.FORWARD     ## unit X/Z from the room into the hall
var a := Vector2.ZERO           ## world X/Z: the jambs; the door (and its sight blocker) stands on a -> b
var b := Vector2.ZERO
var height := 1.5               ## the wall height above the floor
var half := 0.16                ## how deep the door is either side of its line
var width := 3.0
# The host decides these (OWNER).
var shut := true
var broken := false
var swing := 1                  ## +1: the leaves swing toward the hall side, -1 toward the room (away from the opener)
# The host's working state (PRIVATE).
var _hold: Dictionary = {}      ## monster instance id -> GameWorld.time it started opening the door
var _last: Dictionary = {}      ## actor instance id -> last flat position in the door's frame (Vector2): who walks toward it
var _smasher: Actor = null
var _smash_t := -1.0
# Presentation (LOCAL).
var open_k := 0.0               ## 0 shut .. 1 open
var hold_k := -1.0              ## >= 0: the look stays at this open_k (the lab's "opening" shot)
var model: OfficeDoorModel = null
var frame_color := Color(0, 0, 0, 0)   ## the architrave's paint (alpha 0: OfficeDoorModel's default)
var _rattle := 0.0

static var _actors_frame := -1
static var _actors_cache: Array[Actor] = []
static var _warned := false


## Who may write each var (see Net).
func net_fields() -> Dictionary:
	return {
		"doorway_id": Net.SPAWN, "style": Net.SPAWN, "cell": Net.SPAWN, "axis": Net.SPAWN, "a": Net.SPAWN, "b": Net.SPAWN,
		"height": Net.SPAWN, "half": Net.SPAWN, "width": Net.SPAWN,
		"shut": Net.OWNER, "broken": Net.OWNER, "swing": Net.OWNER,
		"_hold": Net.PRIVATE, "_last": Net.PRIVATE, "_smasher": Net.PRIVATE, "_smash_t": Net.PRIVATE,
		"open_k": Net.LOCAL, "hold_k": Net.LOCAL, "model": Net.LOCAL, "frame_color": Net.LOCAL, "_rattle": Net.LOCAL,
	}


## A door on doorway `dw` (Doorways.find; needs dw["door_ok"]). Null when it has no door place.
static func spawn(dw: Dictionary, door_style: String = DEFAULT_STYLE, start_shut: bool = true, frame: Color = Color(0, 0, 0, 0)) -> OfficeDoor:
	if not bool(dw.get("door_ok", false)) or GameWorld.root == null:
		return null
	var d := OfficeDoor.new()
	d.doorway_id = int(dw["id"])
	d.style = door_style
	d.frame_color = frame
	d.cell = dw["cell"]
	d.axis = dw["axis"]
	d.a = dw["a"]
	d.b = dw["b"]
	# (+Z of the door's frame must point into the hall: a -> b runs so that (a -> b) x UP does)
	var t := (d.b - d.a).normalized()
	if Vector2(-t.y, t.x).dot(Vector2(d.axis.x, d.axis.z)) < 0.0:
		var tmp := d.a
		d.a = d.b
		d.b = tmp
	d.width = (d.b - d.a).length()
	d.height = _wall_height(dw)
	d.shut = start_shut
	d.open_k = 0.0 if start_shut else 1.0
	d.name = "OfficeDoor%d" % d.doorway_id
	GameWorld.spawn(d, dw["center"])
	return d


## The wall height beside the door (the band's cut cells' wall top over the floor), 1.5 by default.
static func _wall_height(dw: Dictionary) -> float:
	var map := GameWorld.map
	var best := 0.0
	if map != null:
		var lv := map.get_cell(dw["cell"]).level
		for c: Vector2i in dw.get("band", []):
			var hc: HexMap.Cell = map.get_cell(c)
			if hc != null and hc.wall_mask != 0:
				best = maxf(best, float(hc.wall_top - lv) * Hex.LEVEL_HEIGHT)
	return best if best > 0.5 else 1.5


## Every door on the floor.
static func all() -> Array[OfficeDoor]:
	var out: Array[OfficeDoor] = []
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return out
	for n in GameWorld.root.get_tree().get_nodes_in_group(GROUP):
		if n is OfficeDoor and is_instance_valid(n):
			out.append(n)
	return out


## The door E would act on for `hero` (the nearest within USE_RANGE of it, the hero inside its width), or null.
static func interact_target(hero: Actor) -> OfficeDoor:
	if hero == null:
		return null
	var best: OfficeDoor = null
	var best_d := USE_RANGE
	for d in all():
		if d.broken:
			continue
		var rel := d.local_flat(hero.global_position)
		if absf(rel.x) > d.width * 0.5 + 0.3:
			continue
		var gap := maxf(0.0, absf(rel.y) - d.half)
		if gap < best_d:
			best_d = gap
			best = d
	return best


func _ready() -> void:
	add_to_group(GROUP)
	var t := (b - a).normalized()
	var tx := Vector3(t.x, 0.0, t.y)
	global_transform = Transform3D(Basis(tx, Vector3.UP, tx.cross(Vector3.UP)), global_position)
	model = OfficeDoorModel.make(style, width, height, frame_color)
	add_child(model)
	model.set_open(open_k, float(swing))
	_apply_blocker()


func _exit_tree() -> void:
	if GameWorld.map != null:
		GameWorld.map.clear_blocker(_key())


func _key() -> String:
	return "door:%d" % doorway_id


## A world point in the door's flat frame: x along the door line (0 = its middle), y across it (+ = the hall side).
func local_flat(p: Vector3) -> Vector2:
	var q := Vector2(p.x - (a.x + b.x) * 0.5, p.z - (a.y + b.y) * 0.5)
	var t := (b - a).normalized()
	return Vector2(q.dot(t), q.dot(Vector2(-t.y, t.x)))


func center() -> Vector3:
	return global_position


## Where the use prompt floats.
func prompt_point() -> Vector3:
	return global_position + Vector3.UP * (height + 0.5)


func use_verb() -> String:
	return "Open door" if shut else "Shut door"


## Is a body standing in the door (so E cannot shut it)?
func blocked() -> bool:
	for act in _nearby():
		var rel := local_flat(act.global_position)
		if absf(rel.x) <= width * 0.5 + act.radius and absf(rel.y) <= half + act.radius + 0.05:
			return true
	return false


## E on this door by `hero`: shut it if open, open it if shut. False when nothing happened (blocked, broken, a client).
func use(hero: Actor) -> bool:
	if broken:
		return false
	if shut:
		return request(false, hero)
	if blocked():
		_rattle = 0.35
		return false
	return request(true, hero)


## Ask for a state: the host (or solo) decides; a client asks the host (not built yet: NETWORKED).
func request(want_shut: bool, by: Node) -> bool:
	if Net.owns(self):
		_decide(want_shut, by)
		return true
	if NETWORKED:
		return Net.request(self, "door", {"shut": want_shut})
	if not _warned:
		_warned = true
		push_warning("OfficeDoor: doors are host / solo only for now; a client's push is ignored (%s)" % str(by))
	return false


## The host's decision (and what every machine shows once it is told). Opening, the leaves swing away from whoever opened
## it; a hero opening it makes a noise.
func _decide(want_shut: bool, by: Node) -> void:
	if broken or want_shut == shut:
		return
	shut = want_shut
	if not want_shut:
		var side := local_flat((by as Node3D).global_position).y if by is Node3D else -1.0
		swing = -1 if side > 0.0 else 1
	_hold.clear()
	_apply_blocker()
	if not want_shut and Net.owns(self) and not (by is Monster):
		MonsterSenses.noise(global_position + Vector3.UP * 0.2, OPEN_NOISE, "door")
	state_changed.emit(self)


func _apply_blocker() -> void:
	var map := GameWorld.map
	if map == null:
		return
	if shut and not broken:
		var t := (b - a).normalized() * 0.08   # a touch into each wall face, so a line grazing the jamb is caught
		map.set_blocker(_key(), a - t, b + t, global_position.y + height)
	else:
		map.clear_blocker(_key())

# --- The host: who walks into it -------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_animate(delta)
	if broken or not Net.owns(self):
		return
	if _smash_t >= 0.0:
		_smash_tick(delta)
		return
	var seen := {}
	for act in _nearby():
		var id := act.get_instance_id()
		seen[id] = true
		var p := local_flat(act.global_position)
		var prev: Vector2 = _last.get(id, p)
		_last[id] = p
		if not shut or absf(p.x) > width * 0.5 + 0.1:
			continue
		var gap := absf(p.y) - half - act.radius
		var toward := (absf(prev.y) - absf(p.y))   # how far it moved toward the door this frame
		var held := _hold.has(id)
		if gap > TOUCH or (toward <= 0.0005 and not held):
			continue
		if act is Monster:
			_monster_at(act as Monster)
		else:
			_decide(false, act)
			return
	for id: int in _last.keys():
		if not seen.has(id):
			_last.erase(id)


## A monster walked into the shut door: a chasing brute smashes it, anyone else stops and opens it (quietly).
func _monster_at(m: Monster) -> void:
	if not Net.resolves(m):
		return
	var id := m.get_instance_id()
	if m.kind == "brute" and m.state in [Monster.State.CHASE, Monster.State.ATTACK, Monster.State.ALERT]:
		_begin_smash(m)
		return
	if not _hold.has(id):
		_hold[id] = GameWorld.time
		m.set_modifier("door_open", 1.0, MONSTER_DELAY, Actor.STAT_ROOT)
		_rattle = MONSTER_DELAY
		return
	if GameWorld.time - float(_hold[id]) >= MONSTER_DELAY - 0.02:
		_decide(false, m)


## Live actors near the door (one list per physics frame for every door).
func _nearby() -> Array[Actor]:
	var frame := Engine.get_physics_frames()
	if frame != _actors_frame:
		_actors_frame = frame
		_actors_cache = GameWorld.actors()
	var out: Array[Actor] = []
	var reach := width * 0.5 + SCAN_MARGIN
	for act in _actors_cache:
		if not is_instance_valid(act) or act.dead or act.is_in_group(PricedProp.GROUP) or act.is_in_group("breakables"):
			continue   # (furniture and mail never walk into a door)
		if GameWorld.flat_distance(act.global_position, global_position) <= reach:
			out.append(act)
	return out


# --- The brute's smash -----------------------------------------------------------------------------------------------

func _begin_smash(m: Monster) -> void:
	_smasher = m
	_smash_t = 0.0
	m.set_modifier("door_smash", 1.0, SMASH_ROOT, Actor.STAT_ROOT)
	m.face_point(global_position)
	m.set("_telegraph", 0.0)
	if m.has_method("_on_windup_begin"):
		m.call("_on_windup_begin")


func _smash_tick(delta: float) -> void:
	var m := _smasher
	if m == null or not is_instance_valid(m) or m.dead or m.is_shoved():
		if m != null and is_instance_valid(m):
			m.set("_telegraph", 0.0)
			if m.has_method("_on_windup_end"):
				m.call("_on_windup_end")
		_smasher = null
		_smash_t = -1.0
		return
	_smash_t += delta
	m.face_point(global_position)
	m.set("_telegraph", clampf(_smash_t / SMASH_WINDUP, 0.0, 1.0))
	_rattle = 0.1
	if _smash_t < SMASH_WINDUP:
		return
	# The slam lands: the real slam (Combat.slam round the brute: whoever holds the door gets it) and the door bursts.
	m.set("_telegraph", 0.0)
	if m.has_method("_on_windup_end"):
		m.call("_on_windup_end")
	if m.has_method("_strike"):
		m.call("_strike")
	m.set("strikes", int(m.get("strikes")) + 1)
	m.set("_strike_t", 1.0)
	var mm: Variant = m.get("model")
	if mm != null and (mm as Object).has_method("attack_swing"):
		(mm as Object).call("attack_swing")
	_smasher = null
	_smash_t = -1.0
	smash(m)


## The door bursts (the host decides; every machine plays it). Billed once, to `by`'s side (a monster: "demons").
func smash(by: Node) -> void:
	if broken:
		return
	broken = true
	shut = false
	_hold.clear()
	_apply_blocker()
	if Net.owns(self):
		Ledger.damage(LABEL, PRICE, by)
		MonsterSenses.noise(global_position + Vector3.UP * 0.2, SMASH_NOISE, "door_smash", [by] if by != null else [])
	var away := 1.0
	if by is Node3D:
		var side := local_flat((by as Node3D).global_position).y
		away = -signf(side) if side != 0.0 else 1.0
	if model != null:
		model.show_broken(away, GameWorld.fx_rng)
	if GameWorld.root != null and GameWorld.root.is_inside_tree():
		var n := global_transform.basis.z
		PropDebris.burst(global_position + Vector3.UP * 0.6 + n * away * 0.3, model.palette() if model != null else [Color.WHITE], 20, 1.1)
	smashed.emit(self, by)
	state_changed.emit(self)


# --- Look --------------------------------------------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if broken or model == null:
		return
	if hold_k >= 0.0:
		open_k = hold_k
	else:
		var want := 0.0 if shut else 1.0
		var rate := 1.0 / (SHUT_TIME if shut else OPEN_TIME)
		open_k = move_toward(open_k, want, rate * delta)
	_rattle = maxf(0.0, _rattle - delta)
	model.set_open(open_k, float(swing))
	if _rattle > 0.0 and open_k < 0.05:
		model.position = Vector3(sin(Time.get_ticks_msec() * 0.07), 0.0, cos(Time.get_ticks_msec() * 0.09)) * 0.03 * minf(1.0, _rattle * 4.0)
	else:
		model.position = Vector3.ZERO

class_name OfficeDoor
extends Node3D
## OFFICE DOOR (docs/design/exploration.md, "Decisions: map information, fog and doors", 2026-10-19): a door in
## the ROOM WALL at a NARROW doorway, on Doorways' door line (the chord between the two jambs where the corridor's walls
## end at the room), filling it jamb to jamb at the wall's height. Which doorways get one is DoorPlan's (SitePlan.doors);
## SiteBuilder.spawn builds them. Its look is one of OfficeDoorModel's STYLES ("single" swing door with a wired-glass light
## and a lever handle, "double" doors with push bars and a lit sign, a frosted glass "slider" suite front with a logo band).
##
## DECISIONS (user, 2026-10-19): "The double door is the feel I like." and "Gunmetal and tread plate.": the double door
## with a gunmetal frame is the default (DEFAULT_STYLE, OfficeDoorModel.FRAME), and a door's doorway gets the diamond
## tread-plate threshold on the cells its door line crosses (DoorFloors.DOOR_OPTION "c"; an open archway keeps its floors,
## "a"). After playing the fog lab: doors on EVERY narrow doorway (DoorPlan.DOOR_SHARE 1.0), they START SHUT, and a shut
## door is SOLID (bodies, shoves, arrows and projectiles stop at it, as well as sight and sound).
##
##   WALK INTO IT  a hero (or anyone who is not a monster) walking into a shut door (at WALK_MIN or faster: an idle sway
##                 is not a walk), or pressed against it still walking into it, opens it at once. A MONSTER walking
##                 into it stops for MONSTER_DELAY (rooted, the door shudders) and then opens it: pathing needs nothing
##                 new, the door is never a wall for find_path.
##   E             shuts an open door (or opens a shut one): use(). Not while a body stands in it.
##   NOISE         a HERO opening it is heard (MonsterSenses.noise, OPEN_NOISE, a "door" row in the combat log): monsters
##                 in the room behind turn toward it. A monster opening one makes no noise for the crew; a brute's
##                 smash is loud (SMASH_NOISE). The host makes it (it decides the door and runs the monsters).
##   SHUT          SOLID (a HexMap blocker: bodies stop against it like a wall face, a shove slams into it, an arrow or a
##                 projectile stops at it), blocks SIGHT (line_of_sight: monster sight and room fog) and MUFFLES noise
##                 (half a sound's reach through it: MonsterSenses.noise asks HexMap.crosses_blocker).
##   SMASH         a BRUTE that is chasing (CHASE / ATTACK / ALERT) walks into a shut door and slams it (Brute.smash_door:
##                 its real slam's wind-up, then the slam) and the door bursts: the leaves torn off, a loud noise, and one
##                 Ledger damage line ("Office door", PRICE, the brute: "demons" on the invoice). Billed once: `broken` is
##                 final.
##
## NETWORKING: a host-arbitrated object (networking.md's fourth shape), like a priced prop. The HOST decides `shut`, `swing`
## and `broken` (OWNER) and every machine keeps its own blocker (collision and sight) from them. A client's E, or its own hero
## walking into a shut door, is a request (Net.request(door, "door", {shut}) -> NetObjects "obj.req"); the host decides and
## tells everyone (`obj.door {id, s, w}`); a smash goes out as `obj.break {id, by}` (the bill as `obj.ledger`). A late joiner
## gets every door's state in the join snapshot (NetObjects.late_join_state "doors"). Net ids: after the actors (NetFloor).

signal state_changed(door: OfficeDoor)
signal smashed(door: OfficeDoor, by: Node)

const GROUP := "office_doors"
const NETWORKED := true         ## a client's push is a request the host decides (NetObjects)
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
const SCAN_MARGIN := 2.6        ## actors this far past the door's half width are not looked at
const ASK_AGAIN := 0.5          ## a client asks again this long after an unanswered push
const WALK_MIN := 0.5           ## units/s: a body coming at the door slower (an idle sway, a cowering employee) is not walking into it

# Spawn data: from the doorway (Doorways), the same on every machine.
var doorway_id := -1
var style := DEFAULT_STYLE
var cell := Vector2i.ZERO       ## the doorway cell (the corridor's first full cell past the door)
var axis := Vector3.FORWARD     ## unit X/Z from the room into the hall
var a := Vector2.ZERO           ## world X/Z: the jambs; the door (and its blocker) stands on a -> b
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
# Presentation and this machine's asking (LOCAL).
var open_k := 0.0               ## 0 shut .. 1 open
var hold_k := -1.0              ## >= 0: the look stays at this open_k (the lab's "opening" shot)
var model: OfficeDoorModel = null
var frame_color := Color(0, 0, 0, 0)   ## the architrave's paint (alpha 0: OfficeDoorModel's default)
var _rattle := 0.0
var _asked_at := -INF           ## a client: when it last asked the host to open this door

static var _actors_frame := -1
static var _actors_cache: Array[Actor] = []


## Who may write each var (see Net).
func net_fields() -> Dictionary:
	return {
		"doorway_id": Net.SPAWN, "style": Net.SPAWN, "cell": Net.SPAWN, "axis": Net.SPAWN, "a": Net.SPAWN, "b": Net.SPAWN,
		"height": Net.SPAWN, "half": Net.SPAWN, "width": Net.SPAWN,
		"shut": Net.OWNER, "broken": Net.OWNER, "swing": Net.OWNER,
		"_hold": Net.PRIVATE, "_last": Net.PRIVATE,
		"open_k": Net.LOCAL, "hold_k": Net.LOCAL, "model": Net.LOCAL, "frame_color": Net.LOCAL, "_rattle": Net.LOCAL,
		"_asked_at": Net.LOCAL,
	}


## A door on doorway `dw` (Doorways.find or a SitePlan.doors record; needs "door_ok"). Null when it has no door place.
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


## E on this door by `hero`: shut it if open, open it if shut. False when nothing happened (blocked, broken).
func use(hero: Actor) -> bool:
	if broken:
		return false
	if shut:
		return request(false, hero)
	if blocked():
		_rattle = 0.35
		return false
	return request(true, hero)


# --- E (Usable, scripts/app/usable.gd): the candidate is interact_target(hero) ------------------------------------------

func use_kind() -> String:
	return "door"


func use_score(_hero: Hero, _game: Node) -> float:
	return Usable.DOOR


func use_prompt(_hero: Hero, _game: Node) -> String:
	return use_verb()


func use_point(_hero: Hero, _game: Node) -> Vector3:
	return prompt_point()


## E shuts it (opens a shut one): use(). The press is used even when the door would not move (a body stands in it).
func use_press(hero: Hero, _game: Node) -> bool:
	use(hero)   # (a client's is a request: the host decides)
	return true


## Ask for a state: the host (or solo) decides at once; a client asks the host (obj.req "door"). True when decided or sent.
func request(want_shut: bool, by: Node) -> bool:
	if Net.owns(self):
		return host_decide(want_shut, by)
	_asked_at = GameWorld.time
	return Net.request(self, "door", {"shut": want_shut})


## The host decides (its own push, or a client's request: NetObjects). Shutting is refused while a body stands in it.
func host_decide(want_shut: bool, by: Node) -> bool:
	if broken or want_shut == shut:
		return false
	if want_shut and blocked():
		return false
	shut = want_shut
	if not want_shut:
		var side := local_flat((by as Node3D).global_position).y if by is Node3D else -1.0
		swing = -1 if side > 0.0 else 1
	_hold.clear()
	_apply_blocker()
	if not want_shut and not (by is Monster):
		MonsterSenses.noise(global_position + Vector3.UP * 0.2, OPEN_NOISE, "door")
	state_changed.emit(self)
	return true


## A client: the host's decision (obj.door), or a late joiner's snapshot.
func net_show(is_shut: bool, swing_dir: int) -> void:
	if broken:
		return
	var changed := is_shut != shut or swing_dir != swing
	shut = is_shut
	swing = 1 if swing_dir >= 0 else -1
	_asked_at = -INF
	_apply_blocker()
	if changed:
		state_changed.emit(self)


# --- The net-object contract (NetObjects) ------------------------------------------------------------------------------

## Net ids: a door's comes after every actor's, before the pickups' (NetFloor.assign_ids).
func net_order() -> int:
	return 0


## A client: the door is a copy (the host decides it), but its physics keeps running: it animates the leaves and sees this
## machine's own hero walk into it shut (a request to the host). NetFloor.freeze_copies.
func net_make_copy() -> void:
	set_meta(Net.COPY_META, true)


## Host: an opened or shut door goes to everyone as `obj.door {id, s, w}`; a brute's smash as `obj.break {id, by}` (the bill
## goes out as obj.ledger).
func net_link(objects: NetObjects, id: int) -> void:
	objects.link(state_changed, _net_changed.bind(objects, id))
	objects.link(smashed, _net_smashed.bind(objects, id))


func _net_changed(_door: OfficeDoor, objects: NetObjects, id: int) -> void:
	if broken:
		return   # (a smash is obj.break)
	objects.tell("obj.door", {"id": id, "s": shut, "w": swing})
	objects.count("doors_out")


func _net_smashed(_door: OfficeDoor, by: Node, objects: NetObjects, id: int) -> void:
	objects.tell("obj.break", {"id": id, "by": NetObjects.net_id(by)})
	objects.count("breaks")


## Client: the host's decision (obj.door) or a brute's smash (obj.break; the bill is the host's, in obj.ledger).
func net_event(kind: String, data: Dictionary, objects: NetObjects) -> void:
	match kind:
		"obj.door":
			net_show(bool(data.get("s", true)), int(data.get("w", 1)))
			objects.count("doors_in")
		"obj.break":
			smash(NetRegistry.node(int(data.get("by", 0))))
			objects.count("breaks")


## Host: a client's E on this door, or its hero walking into it shut (`door {shut}`): decided once (host_decide), and everyone
## hears of it as obj.door. The asker's hero is who opened it (the leaves swing away from it).
func net_request(what: String, data: Dictionary, peer: int, objects: NetObjects) -> void:
	if what != "door":
		return
	objects.count("door_reqs")
	if objects.active:
		host_decide(bool(data.get("shut", false)), objects.hero_of(peer))


## Host: this door for a late joiner, `doors` [id, shut, swing, broken] (an obj.door / obj.break replay).
func late_join_state(_objects: NetObjects, id: int) -> Dictionary:
	return {"doors": [id, shut, swing, broken]}


func apply_late_join(section: String, row: Array, objects: NetObjects) -> void:
	if section != "doors" or row.size() < 4:
		return
	if bool(row[3]):
		smash(null)
	else:
		net_show(bool(row[1]), int(row[2]))
	open_k = 0.0 if shut else 1.0   # (no swing on arrival: it is already where the host has it)
	objects.count("doors_in")


func _apply_blocker() -> void:
	var map := GameWorld.map
	if map == null:
		return
	if shut and not broken:
		var t := (b - a).normalized() * 0.08   # a touch into each wall face, so a line grazing the jamb is caught
		map.set_blocker(_key(), a - t, b + t, global_position.y + height)
	else:
		map.clear_blocker(_key())

# --- Who walks into it -----------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_animate(delta)
	if broken:
		return
	var host := Net.owns(self)
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
		if act.is_helpless():
			_last[id] = Vector2(p.x, INF)   # (shoved or staggered: the next frames' movement is not a walk)
			continue
		# Pressed against it and still walking into it (it walked up while the door was being shut): a push too. Facing it
		# is not enough: a body shoved against it, or standing there aiming, is not walking.
		var t := (b - a).normalized()
		var pressing := gap <= 0.06 and GameWorld.time - act._walk_at < 0.1 and act.facing.dot(Vector3(-t.y, 0.0, t.x)) * signf(p.y) < -0.7
		if gap > TOUCH or (toward < WALK_MIN * delta and not held and not pressing) or toward > 0.6:
			continue   # (a body shoved into a shut door slams into it: it does not push it open; a jump is a teleport, not a walk)
		if not host:
			# A client: only its own hero's push counts here, and it is a request (the host decides).
			if act is Hero and Net.owns(act) and GameWorld.time - _asked_at >= ASK_AGAIN:
				request(false, act)
			continue
		if act is Monster:
			_monster_at(act as Monster)
		elif Net.owns(act):
			host_decide(false, act)
			return
	for id: int in _last.keys():
		if not seen.has(id):
			_last.erase(id)


## A monster walked into the shut door: a chasing brute smashes it (Brute.smash_door), anyone else stops and opens it
## (quietly).
func _monster_at(m: Monster) -> void:
	if not Net.resolves(m):
		return
	var id := m.get_instance_id()
	if m.kind == "brute" and m.state in [Monster.State.CHASE, Monster.State.ATTACK, Monster.State.ALERT] and m.has_method("smash_door"):
		if m.call("smash_door", self):
			_rattle = 1.0
		return
	if not _hold.has(id):
		_hold[id] = GameWorld.time
		m.set_modifier("door_open", 1.0, MONSTER_DELAY, Actor.STAT_ROOT)
		_rattle = MONSTER_DELAY
		return
	if GameWorld.time - float(_hold[id]) >= MONSTER_DELAY - 0.02:
		host_decide(false, m)


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


## The door bursts (the host decides; every machine plays it: a client from obj.break). Billed once, to `by`'s side (a
## monster: "demons"), by the host.
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

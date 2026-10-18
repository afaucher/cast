class_name Employee
extends Actor
## A client's employee: a neutral, fragile civilian the crew can escort out for $100 (one left
## behind pays nothing). Team TEAM_NEUTRAL, ~30 hp, slow-ish. Area spells (corn, teeth, tentacle shoves) hit
## it like anyone else, with NO hero friendly-fire floor: protecting it is the skill test.
##
## A small deterministic state machine (timers are GameWorld.time based):
##   COWER    crouched and trembling where it hid. A "help!" bubble shows when a hero is near.
##   PANIC    a monster is within PANIC_RANGE (or something just hurt it): run away, pathing around
##            walls, arms flailing. Calms down (back to COWER) after CALM_TIME with nothing near.
##   FOLLOW   a hero recruited them with E (request_follow; with JOIN_NEEDS_E off, a hero within JOIN_RANGE (2)
##            does it just by standing there): latch on as the leader. Trails 1.5-3 behind, paths with
##            HexMap.find_path (can't climb +2 ledges, like Rebar) and sprints to catch up. If the
##            leader goes down it switches to the nearest other hero (within SWITCH_RANGE), else COWERs.
##   WAIT     the hero told them to wait (E, request_wait): crouched where they were, ignoring heroes. A monster
##            still sets off PANIC, and once calm they walk back to the spot they were told to wait at. A
##            dismissed employee never rejoins by proximity, only another E (request_follow) recruits them.
##   EXTRACT  extract() was called: a cheer, then it shrinks away and is freed.
##
## Contract flow API (agent A): spawn(), is_following(), leader(), extract(), is_extracted(), alive(),
## signals rescued(employee) and died. Group "employees" holds the living, not-yet-extracted employees.
##
## Monsters can target employees: see Monster._consider_employee (about 30% of retarget rolls, only when
## an employee is closer than every hero and inside aggro range).

## Emitted once by extract(), immediately (the fade-out plays afterwards). The employee is already out
## of the "employees" and "actors" groups by then, so it can no longer be hurt or counted as alive.
signal rescued(employee: Employee)
## A speech bubble started (say()): every screen shows it (NetWorld sends it, M3).
signal said(text: String, seconds: float)

enum State { COWER, PANIC, FOLLOW, EXTRACT, WAIT }

const MAX_HP := 30.0
const WALK_SPEED := 3.3
const RUN_SPEED := 4.0
const CATCHUP_SPEED := 5.2         ## sprint when trailing the leader by FOLLOW_MAX or more
const PANIC_RANGE := 4.0           ## a monster this close sets off a panic
const CALM_RANGE := 5.5            ## ... and it takes this much room (for CALM_TIME) to calm down
const CALM_TIME := 1.5
const JOIN_RANGE := 2.0            ## a hero this close becomes the leader
## True (the decision): joining needs E, first contact included. A hero walking past does nothing; E near a
## cowering or waiting employee recruits them, E near your follower dismisses them. False would bring back
## latching on by proximity for never-dismissed employees (and E would only dismiss and recall).
const JOIN_NEEDS_E := true
const WAIT_RANGE := 2.2            ## E tells YOUR follower to wait from this far (kept tight so E only reaches an employee who is actually beside the hero)
const RECALL_RANGE := 2.2          ## E recruits a waiting (or, with JOIN_NEEDS_E, a cowering) employee from this far
const WAIT_SLACK := 0.9            ## a waiting employee strays this far from its spot before walking back
const WAIT_ARRIVED := 0.35
const RETURN_GIVEUP := 8.0         ## seconds of trying to walk back before it waits where it stands
const FOLLOW_MIN := 1.5            ## closer than this to the leader: back off
const FOLLOW_SETTLE := 2.2         ## catching up stops here
const FOLLOW_MAX := 3.0            ## farther than this: catch up
const SWITCH_RANGE := 14.0         ## how far away another hero can be to take over as leader
const NEAR_RANGE := 7.0            ## a hero this close shows the name tag and the cower bubble
const HURT_PANIC_TIME := 2.0
const SCAN_INTERVAL := 0.2
const REPLAN_INTERVAL := 0.5
const FLEE_RINGS := 5
const PATH_MAX_NODES := 900
const WAYPOINT_REACHED := 0.35
const PROBE_STEP := 0.4
const STUCK_TIME := 0.5
const EXTRACT_TIME := 1.1
const DEATH_TIME := 0.8

const STAFF_NAMES: Array[String] = ["Reginald", "Beatrice", "Alphonse", "Mrs. Pym", "Hodges", "Dorothea"]
const HENCH_NAMES: Array[String] = ["Gary", "Steve", "Todd", "Kevin", "Dennis", "Hench #4"]
const COWER_LINES := {
	"staff": ["help!", "oh dear...", "eek!", "sir?!"],
	"henchman": ["boss?!", "help!", "I quit!", "no dental!"],
}
const PANIC_LINES := {"staff": "AAAH!", "henchman": "NOPE!"}
const LATCH_LINES := {"staff": "oh, thank you!", "henchman": "I'm with you!"}
const WAIT_LINES := {"staff": "Waiting here.", "henchman": "Waiting here, boss."}
const RECALL_LINES := {"staff": "Right behind you!", "henchman": "Right behind you, boss!"}

## "staff" (bunker) or "henchman" (lair). Set before the employee enters the tree (spawn() does).
var style := "staff"
## Picks the skin tone, the cower lines and the default name.
var variant := 0
var state: int = State.COWER
var model: EmployeeModel = null

var _leader: Actor = null
var _extracted := false
var _return_giveup := 0.0
var _returning_to_spot := false     ## walking back to the wait spot (a tick-to-tick flag, not shared)
var _dismissed := false             ## told to wait: no more auto-joining by proximity until recruited again
var _wait_spot := Vector3.ZERO      ## where a dismissed employee holds (and returns to after a scare)
var _threat := Vector3.ZERO
var _threat_valid := false
var _calm_at := 0.0
var _panic_until := 0.0
var _next_scan := 0.0
var _next_replan := 0.0
var _hero_near := false
var _hero_pos := Vector3.ZERO
var _hero_pos_valid := false
var _scared := false
var _catching := false
var _stuck_t := 0.0
var _stuck_from := Vector3.ZERO
var _path: Array[Vector2i] = []
var _path_idx := 1
var _path_goal := Vector2i(1 << 20, 1 << 20)

var _visual: Node3D = null
var _bar: HpBar = null
var _name_label: Label3D = null
var _bubble: Node3D = null
var _bubble_bg: MeshInstance3D = null
var _bubble_tail: MeshInstance3D = null
var _bubble_text: Label3D = null
var _say_text := ""
var _say_until := -1.0
var _bubble_shown := ""


## Spawn an employee standing on `cell`. opts: style ("staff" or "henchman"), name (display name; a
## style-appropriate one is picked from the cell when empty).
static func spawn(cell: Vector2i, opts: Dictionary = {}) -> Employee:
	if GameWorld.root == null:
		push_warning("Employee.spawn: no world")
		return null
	var e := Employee.new()
	e.style = str(opts.get("style", "staff"))
	if not EmployeeModel.STYLES.has(e.style):
		e.style = "staff"
	e.variant = absi(cell.x * 7 + cell.y * 13 + (3 if e.style == "henchman" else 0))
	var nm := str(opts.get("name", ""))
	if nm == "":
		var pool: Array[String] = HENCH_NAMES if e.style == "henchman" else STAFF_NAMES
		nm = pool[e.variant % pool.size()]
	e.display_name = nm
	e.name = "Employee_" + nm.replace(" ", "_").replace("#", "")
	var level := 0.0
	var map := GameWorld.map
	if map != null:
		var l := map.ground_level(Hex.to_world(cell))
		if not is_nan(l):
			level = l
	GameWorld.spawn(e, Hex.to_world(cell, level))
	return e


## Living employees that have not been extracted.
static func alive() -> Array[Employee]:
	var out: Array[Employee] = []
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return out
	for n in GameWorld.root.get_tree().get_nodes_in_group("employees"):
		var e := n as Employee
		if e != null and not e.dead and not e._extracted:
			out.append(e)
	return out


func _init() -> void:
	team = GameWorld.TEAM_NEUTRAL
	max_hp = MAX_HP
	move_speed = WALK_SPEED
	radius = 0.36
	shove_mult = 1.25
	display_name = "Employee"


func _ready() -> void:
	super._ready()
	add_to_group("employees")
	_build_visuals()
	_next_scan = GameWorld.time + float(variant % 5) * 0.04
	damaged.connect(_on_hurt)
	_set_state(State.COWER)


## Who may write each var (see Net); Actor's come from super(). Employees are host-owned: the
## host runs the scan/panic/follow logic, so the working state is PRIVATE; the state, who they
## follow, the rescue flag and the speech bubble are what every screen shows.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"style": Net.SPAWN, "variant": Net.SPAWN,
		"state": Net.OWNER,
		"_leader": Net.OWNER,           # will travel as an entity id
		"_extracted": Net.OWNER,
		"_returning_to_spot": Net.PRIVATE, "_return_giveup": Net.PRIVATE,
		"_dismissed": Net.OWNER, "_wait_spot": Net.OWNER,   # a player's E is a request; the host decides (request_wait / request_follow)
		"_say_text": Net.OWNER, "_say_until": Net.OWNER,   # events like "OW!" show on every screen
		# AI working state (threat memory, scan/replan timers, pathing, stuck detection).
		"_threat": Net.PRIVATE, "_threat_valid": Net.PRIVATE, "_calm_at": Net.PRIVATE,
		"_panic_until": Net.PRIVATE, "_next_scan": Net.PRIVATE, "_next_replan": Net.PRIVATE,
		"_hero_pos": Net.PRIVATE, "_hero_pos_valid": Net.PRIVATE, "_catching": Net.PRIVATE,
		"_stuck_t": Net.PRIVATE, "_stuck_from": Net.PRIVATE,
		"_path": Net.PRIVATE, "_path_idx": Net.PRIVATE, "_path_goal": Net.PRIVATE,
		# Each screen works these out against its own heroes and monsters (name tag, cower
		# bubble, scared pose).
		"_hero_near": Net.LOCAL, "_scared": Net.LOCAL,
		"model": Net.LOCAL, "_visual": Net.LOCAL, "_bar": Net.LOCAL, "_name_label": Net.LOCAL,
		"_bubble": Net.LOCAL, "_bubble_bg": Net.LOCAL, "_bubble_tail": Net.LOCAL,
		"_bubble_text": Net.LOCAL, "_bubble_shown": Net.LOCAL,
	})
	return f


# --- Public API -----------------------------------------------------------------------

## True while latched onto a hero and trailing them.
func is_following() -> bool:
	return state == State.FOLLOW and leader() != null


## The hero this employee follows, or null.
func leader() -> Actor:
	if _leader != null and is_instance_valid(_leader) and not _leader.dead:
		return _leader
	return null


func is_extracted() -> bool:
	return _extracted


## True while told to wait (calm and holding their spot, or scared off it and coming back).
func is_waiting() -> bool:
	return _dismissed and not _extracted and not dead


## True once the crew told them to wait and nobody has recruited them again: they ignore proximity.
func is_dismissed() -> bool:
	return _dismissed


# --- E: dismiss and recall --------------------------------------------------------------
# A player's E is a REQUEST to the employee (the host will own employees in co-op and grant it); the
# controller never writes the state itself. Both return true when the request was granted.

## Can `hero` tell this employee to wait right now? It must be following that hero (or an AI ally of the
## crew: the player may dismiss what an ally picked up) and be close enough. `reach_checked` (online, the host judging a
## player's E): the player's own machine already found it within reach on its screen, so only the state is judged here.
func can_wait(hero: Actor, at: Vector3 = Vector3.INF, reach_checked: bool = false) -> bool:
	if hero == null or not is_instance_valid(hero) or hero.dead or dead or _extracted:
		return false
	if state != State.FOLLOW or not _controlled_by(hero):
		return false
	return reach_checked or _reach(hero, at) <= WAIT_RANGE


## Can `hero` recruit this employee right now? A dismissed one always, a never-dismissed one only when
## JOIN_NEEDS_E; one following somebody else (another player) never. `reach_checked` as in can_wait.
func can_follow(hero: Actor, at: Vector3 = Vector3.INF, reach_checked: bool = false) -> bool:
	if hero == null or not is_instance_valid(hero) or hero.dead or dead or _extracted:
		return false
	if state == State.FOLLOW or not (_dismissed or JOIN_NEEDS_E):
		return false
	return reach_checked or _reach(hero, at) <= RECALL_RANGE


## "Wait here": stop following and hold this spot. Still panics if a monster comes, then returns. `at` is where the
## hero stands when another player's machine asks (online, M3: the host's picture of that hero is ~100 ms old);
## `reach_checked` (online, the host): that machine already checked the reach on its own screen (see can_wait).
func request_wait(hero: Actor, at: Vector3 = Vector3.INF, reach_checked: bool = false) -> bool:
	if not can_wait(hero, at, reach_checked):
		return false
	_dismissed = true
	_leader = null
	_wait_spot = global_position
	_catching = false
	_set_state(State.WAIT)
	say(str(WAIT_LINES[style]), 1.6)
	return true


## "Come with me": follow `hero` again (`at` and `reach_checked` as in request_wait).
func request_follow(hero: Actor, at: Vector3 = Vector3.INF, reach_checked: bool = false) -> bool:
	if not can_follow(hero, at, reach_checked):
		return false
	var line := str(RECALL_LINES[style]) if _dismissed else str(LATCH_LINES[style])   # first contact vs recalled
	_dismissed = false
	_latch(hero, line)
	return true


func _controlled_by(hero: Actor) -> bool:
	var ld := leader()
	if ld == null:
		return false
	if ld == hero:
		return true
	var ally := ld as Hero
	return ally != null and not _is_person(ally) and (hero as Hero) != null and _is_person(hero as Hero)


## A hero a person plays: this machine's player, or (online) another player's hero (it carries the player's name);
## the AI allies are neither.
static func _is_person(h: Hero) -> bool:
	return h.is_player or h.has_meta(Net.NAME_META)


func _reach(hero: Actor, at: Vector3 = Vector3.INF) -> float:
	var p := hero.global_position if at == Vector3.INF else at
	if absf(p.y - global_position.y) > 2.1 * Hex.LEVEL_HEIGHT:
		return INF
	return GameWorld.flat_distance(global_position, p)


## The employee `hero`'s E would act on: the nearest one it can tell to wait or recruit, or null.
static func interact_target(hero: Actor) -> Employee:
	if hero == null or not is_instance_valid(hero) or hero.dead:
		return null
	var best: Employee = null
	var best_d := INF
	for n in hero.get_tree().get_nodes_in_group("employees"):
		var e := n as Employee
		if e == null or not (e.can_wait(hero) or e.can_follow(hero)):
			continue
		var d := GameWorld.flat_distance(e.global_position, hero.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## The verb for what E does to the employee `e` right now: "Tell Marguerite to wait" / "Bring Marguerite".
func interact_verb(hero: Actor) -> String:
	return ("Tell %s to wait" if can_wait(hero) else "Bring %s") % display_name


## Where the use prompt floats over this employee (world): above the head, clear of the name tag.
func prompt_point() -> Vector3:
	return global_position + Vector3(0.0, model.ui_height + 0.95, 0.0)


## The E press: dismiss or recruit the nearest employee. True when it was used. Online the host owns employees: from
## a client it is a request (Net.request), and the host grants it (the employee's state comes back in the snapshot).
static func interact(hero: Actor) -> bool:
	var e := interact_target(hero)
	if e == null:
		return false
	if not Net.owns(e):
		return Net.request(e, "wait" if e.can_wait(hero) else "follow")
	return e.request_wait(hero) if e.can_wait(hero) else e.request_follow(hero)


## Contract flow calls this for followers at an exit (the drop-off, or the crew taking the elevator / van): a cheer
## and a fade-out, then the employee is freed. `line` is the bark. Emits `rescued` once, right away. Safe to call twice
## (the second call does nothing).
func extract(line: String = "thank you!") -> void:
	if _extracted or dead:
		return
	_extracted = true
	_leader = null
	_path.clear()
	remove_from_group("employees")
	remove_from_group("actors")   # no longer a target and no longer pushes anyone around
	_set_state(State.EXTRACT)
	say(line, EXTRACT_TIME)
	rescued.emit(self)
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_interval(EXTRACT_TIME * 0.65)
	tw.tween_method(model.set_fade, 1.0, 0.0, EXTRACT_TIME * 0.35)
	tw.tween_callback(queue_free)


## A speech bubble for `seconds`.
func say(text: String, seconds: float = 1.5) -> void:
	_say_text = text
	_say_until = GameWorld.time + seconds
	said.emit(text, seconds)


func state_name() -> String:
	return State.keys()[state]


# --- Main loop ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not _extracted:
		if GameWorld.time >= _next_scan:
			_next_scan = GameWorld.time + SCAN_INTERVAL
			_scan()
		if not is_helpless():
			match state:
				State.COWER:
					_tick_cower()
				State.PANIC:
					_tick_panic(delta)
				State.FOLLOW:
					_tick_follow(delta)
				State.WAIT:
					_tick_wait(delta)
	_update_visual(delta)


## Look around: the nearest monster and hero decide the state.
func _scan() -> void:
	var now := GameWorld.time
	var seen := _look_around()
	var mon_d: float = seen[0]
	var mon_pos: Vector3 = seen[1]
	var hero: Actor = seen[2]
	var hero_d: float = seen[3]
	_hero_pos_valid = hero != null
	if hero != null:
		_hero_pos = hero.global_position
	if mon_d <= CALM_RANGE:
		_threat = mon_pos
		_threat_valid = true
		if mon_d <= PANIC_RANGE:
			_calm_at = now + CALM_TIME

	var joins := hero != null and hero_d <= JOIN_RANGE and not _dismissed and not JOIN_NEEDS_E
	match state:
		State.COWER, State.WAIT:
			if joins:
				_latch(hero)
			elif mon_d <= PANIC_RANGE:
				_set_state(State.PANIC)
		State.PANIC:
			if joins:
				_latch(hero)
			elif mon_d > CALM_RANGE and now >= _calm_at and now >= _panic_until:
				_set_state(State.WAIT if _dismissed else State.COWER)
		State.FOLLOW:
			if leader() == null:
				_lose_leader()


## The nearest monster and hero: [monster distance, its position, the hero, its distance]. Also the LOCAL mood every
## screen works out for itself (the name tag, the cower bubble, the scared pose), so a client's puppet runs it too.
func _look_around() -> Array:
	var mon_d := INF
	var mon_pos := Vector3.ZERO
	for n in get_tree().get_nodes_in_group("monsters"):
		var m := n as Actor
		if m == null or m.dead:
			continue
		var d := GameWorld.flat_distance(global_position, m.global_position)
		if d < mon_d:
			mon_d = d
			mon_pos = m.global_position
	var hero_d := INF
	var hero: Actor = null
	for h in GameWorld.team_actors(GameWorld.TEAM_HEROES):
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d < hero_d and absf(h.global_position.y - global_position.y) <= 2.1 * Hex.LEVEL_HEIGHT:
			hero_d = d
			hero = h
	_hero_near = hero != null and hero_d <= NEAR_RANGE
	_scared = mon_d <= PANIC_RANGE + 1.0
	if model != null:
		model.set_scared(_scared and state != State.PANIC)
	return [mon_d, mon_pos, hero, hero_d]


# --- Puppet (M3): on a client the host's employee is SHOWN, not simulated ----------------------------------

## Show the host's state (NetWorldCodec.write_employee): HP (the bar), its state (the mood and pose follow), who it
## follows and whether it was told to wait. Speech, extraction and death are events (NetWorld).
func net_show(new_facing: Vector3, is_climbing: bool, new_hp: float, new_state: int, dismissed: bool, new_leader: Actor) -> void:
	facing = new_facing
	climbing = is_climbing
	if absf(new_hp - hp) > 0.05:
		hp = new_hp
		if _bar != null:
			_bar.visible = hp < max_hp - 0.001
			_bar.set_fraction(hp / max_hp)
	_dismissed = dismissed
	_leader = new_leader
	if new_state != state and new_state != State.EXTRACT and not _extracted:
		_set_state(new_state)


## A puppet's per-frame work: its own mood against this screen's heroes and monsters, and the look.
func net_tick(delta: float) -> void:
	if dead:
		return
	if not _extracted and GameWorld.time >= _next_scan:
		_next_scan = GameWorld.time + SCAN_INTERVAL
		var seen := _look_around()
		_hero_pos_valid = seen[2] != null
		if seen[2] != null:
			_hero_pos = (seen[2] as Actor).global_position
	_update_visual(delta)


func _latch(hero: Actor, line: String = "") -> void:
	_leader = hero
	_catching = false
	_set_state(State.FOLLOW)
	say(line if line != "" else str(LATCH_LINES[style]), 1.6)


## The leader went down (or vanished): the nearest other hero takes over, else back to hiding.
func _lose_leader() -> void:
	var old := _leader
	_leader = null
	var best: Actor = null
	var best_d := SWITCH_RANGE
	for h in GameWorld.team_actors(GameWorld.TEAM_HEROES):
		if h == old:
			continue
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d <= best_d:
			best_d = d
			best = h
	if best != null:
		_leader = best
		_path.clear()
		say("wait for me!", 1.2)
	else:
		_set_state(State.COWER)
		say("don't leave me!", 1.6)


func _set_state(s: int) -> void:
	state = s
	_path.clear()
	_path_idx = 1
	_next_replan = 0.0
	_stuck_t = 0.0
	_returning_to_spot = false
	match s:
		State.COWER:
			move_speed = WALK_SPEED
			model.set_mood("cower")
		State.WAIT:
			move_speed = WALK_SPEED
			model.set_mood("cower")
		State.PANIC:
			move_speed = RUN_SPEED
			model.set_mood("panic")
		State.FOLLOW:
			move_speed = WALK_SPEED
			model.set_mood("follow")
		State.EXTRACT:
			model.set_mood("cheer")


# --- Behaviour ticks ------------------------------------------------------------------

func _tick_cower() -> void:
	if _hero_pos_valid and _hero_near:
		face_point(_hero_pos)   # peeks out at whoever is near


## Told to wait: hold the spot. Scared off it (a panic, a shove), walk back once it is calm.
func _tick_wait(delta: float) -> void:
	move_speed = WALK_SPEED
	var to := _wait_spot - global_position
	to.y = 0.0
	var d := to.length()
	if d > WAIT_SLACK or (_returning_to_spot and d > WAIT_ARRIVED):
		if not _returning_to_spot:
			_returning_to_spot = true
			_return_giveup = GameWorld.time + RETURN_GIVEUP
			model.set_mood("follow")   # the walking pose
		if GameWorld.time >= _return_giveup:
			_wait_spot = global_position   # cannot get back (blocked): wait right here instead
			return
		var moved := _walk_toward(_wait_spot, delta)
		_check_stuck(moved, delta)
	else:
		if _returning_to_spot:
			_returning_to_spot = false
			model.set_mood("cower")
		if _hero_pos_valid and _hero_near:
			face_point(_hero_pos)


func _tick_panic(delta: float) -> void:
	move_speed = RUN_SPEED
	var now := GameWorld.time
	if now >= _next_replan:
		_next_replan = now + REPLAN_INTERVAL
		_replan_flee()
	var moved := false
	if _path.size() >= 2:
		moved = _step_along_path(delta)
	elif _threat_valid:
		var away := global_position - _threat
		away.y = 0.0
		if away.length() < 0.05:
			away = -facing
		moved = move(away.normalized(), delta)
	_check_stuck(moved, delta)


## Pick a nearby walkable cell that is farther from the threat and path to it (never climbing +2).
func _replan_flee() -> void:
	_path.clear()
	_path_idx = 1
	var map := GameWorld.map
	if map == null or not _threat_valid:
		return
	var here := current_cell()
	var cur_d := GameWorld.flat_distance(global_position, _threat)
	var scored: Array = []
	for c in Hex.range_cells(here, FLEE_RINGS):
		if c == here or not map.is_walkable_cell(c):
			continue
		var p := Hex.to_world(c)
		var dth := GameWorld.flat_distance(p, _threat)
		if dth < cur_d + 1.5:
			continue
		scored.append([dth - 0.3 * GameWorld.flat_distance(p, global_position), c])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var tried := 0
	for e: Array in scored:
		tried += 1
		if tried > 4:
			break
		var goal: Vector2i = e[1]
		var path := map.find_path(here, goal, false, 300)
		if path.size() < 2:
			continue
		# do not run THROUGH the monster: the first step must not close the gap much
		if GameWorld.flat_distance(Hex.to_world(path[1]), _threat) < minf(cur_d, 2.5) - 0.3:
			continue
		_path = path
		_path_idx = 1
		return


func _tick_follow(delta: float) -> void:
	var ld := leader()
	if ld == null:
		return
	var to := ld.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > FOLLOW_MAX:
		_catching = true
	elif d <= FOLLOW_SETTLE:
		_catching = false
	if d < FOLLOW_MIN:
		move_speed = WALK_SPEED * 0.7
		var back := -to.normalized() if d > 0.01 else -facing
		move(back, delta)
		face_point(ld.global_position)
		return
	if _catching:
		move_speed = lerpf(WALK_SPEED, CATCHUP_SPEED, clampf((d - FOLLOW_SETTLE) / (FOLLOW_MAX - FOLLOW_SETTLE), 0.0, 1.0))
		var moved := _walk_toward(ld.global_position, delta)
		_check_stuck(moved, delta)
	else:
		face_point(ld.global_position)


# --- Navigation -----------------------------------------------------------------------

## Step toward a world point: straight when the way is clear, else along an A* path.
func _walk_toward(goal: Vector3, delta: float) -> bool:
	var to := goal - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return false
	var map := GameWorld.map
	if map == null or _direct_clear(global_position, goal):
		_path.clear()
		return move(to.normalized(), delta)
	var goal_cell := Hex.from_world(goal)
	if GameWorld.time >= _next_replan or goal_cell != _path_goal or _path.size() < 2:
		_next_replan = GameWorld.time + REPLAN_INTERVAL
		_path = map.find_path(current_cell(), goal_cell, false, PATH_MAX_NODES)
		_path_goal = goal_cell
		_path_idx = 1
	if _path.size() < 2:
		return move(to.normalized(), delta)   # no known route: push toward it
	return _step_along_path(delta)


func _step_along_path(delta: float) -> bool:
	while _path_idx < _path.size() and GameWorld.flat_distance(global_position, Hex.to_world(_path[_path_idx])) < WAYPOINT_REACHED:
		_path_idx += 1
	if _path_idx >= _path.size():
		_path.clear()
		return false
	var step := Hex.to_world(_path[_path_idx]) - global_position
	step.y = 0.0
	return move(step.normalized(), delta)


## True if a straight walk is free of ledges, walls and holes (and the elevator's thin sides).
func _direct_clear(from: Vector3, to: Vector3) -> bool:
	var map := GameWorld.map
	if map == null:
		return true
	if map.crosses_solid(from, to, radius):
		return false
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var n := maxi(1, int(flat.length() / PROBE_STEP))
	var prev := from
	for i in range(1, n + 1):
		var p := from + flat * (float(i) / n)
		p.y = from.y
		if map.movement_check(prev, p) != HexMap.Move.OK:
			return false
		prev = p
	return true


## Not getting anywhere while trying to move: force a fresh plan.
func _check_stuck(moved: bool, delta: float) -> void:
	if moved:
		_stuck_t = 0.0
		return
	_stuck_t += delta
	if _stuck_t >= STUCK_TIME:
		_stuck_t = 0.0
		_next_replan = 0.0


## Employees cannot clamber up +2 ledges (like Rebar).
func _climb_allowed() -> bool:
	return false


# --- Damage / death -------------------------------------------------------------------

func _on_hurt(_amount: float, source: Node) -> void:
	if _bar != null:
		_bar.visible = not dead and hp < max_hp - 0.001
		_bar.set_fraction(hp / max_hp)
	if dead or _extracted:
		return
	var src := source as Node3D
	if src != null and src != self:
		_threat = src.global_position
		_threat_valid = true
	_panic_until = GameWorld.time + HURT_PANIC_TIME
	if state == State.COWER or state == State.WAIT:
		_set_state(State.PANIC)
	say("OW!", 0.7)


func _on_interrupted() -> void:
	_path.clear()


func _on_shove_ended() -> void:
	_path.clear()
	_next_replan = 0.0


func _on_death() -> void:
	remove_from_group("employees")
	_path.clear()
	if _bar != null:
		_bar.visible = false
	if _name_label != null:
		_name_label.visible = false
	if _bubble != null:
		_bubble.visible = false
	model.set_downed(true)
	var side := 1.0 if GameWorld.fx_rng.randf() < 0.5 else -1.0   # topple side is cosmetic
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.set_parallel(true)
	tw.tween_property(_visual, "rotation:x", -PI * 0.5 * side, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "position:y", 0.12, 0.4)
	tw.tween_method(model.set_fade, 1.0, 0.0, DEATH_TIME * 0.4).set_delay(DEATH_TIME * 0.6)
	tw.chain().tween_callback(queue_free)


# --- Visuals --------------------------------------------------------------------------

func _build_visuals() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	model = EmployeeModel.new(style, variant)
	_visual.add_child(model)
	var top := model.ui_height
	_bar = HpBar.new()
	_bar.width = 0.7
	_bar.position = Vector3(0, top + 0.25, 0)
	_bar.visible = false
	add_child(_bar)
	_name_label = Label3D.new()
	_name_label.text = display_name
	_name_label.font_size = 40
	_name_label.pixel_size = 0.008
	_name_label.outline_size = 8
	_name_label.modulate = Color(1.0, 0.93, 0.7) if style == "henchman" else Color(0.92, 0.94, 1.0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.render_priority = 5
	_name_label.position = Vector3(0, top + 0.5, 0)
	_name_label.visible = false
	add_child(_name_label)
	_build_bubble(top + 1.2)


func _build_bubble(y: float) -> void:
	_bubble = Node3D.new()
	_bubble.name = "Bubble"
	_bubble.position = Vector3(0, y, 0)
	_bubble.visible = false
	add_child(_bubble)
	_bubble_bg = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 0.5)
	_bubble_bg.mesh = quad
	_bubble_bg.material_override = _bubble_material(Color(0.98, 0.97, 0.93), 8)
	_bubble_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble_bg.set_meta("no_flash", true)
	_bubble.add_child(_bubble_bg)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p: Vector3 in [Vector3(-0.09, 0.0, 0.0), Vector3(0.09, 0.0, 0.0), Vector3(0.0, -0.16, 0.0)]:
		st.add_vertex(p)
	_bubble_tail = MeshInstance3D.new()
	_bubble_tail.mesh = st.commit()
	_bubble_tail.material_override = _bubble_material(Color(0.98, 0.97, 0.93), 8)
	_bubble_tail.position = Vector3(0.0, -0.24, 0.0)
	_bubble_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble_tail.set_meta("no_flash", true)
	_bubble.add_child(_bubble_tail)
	_bubble_text = Label3D.new()
	_bubble_text.font_size = 38
	_bubble_text.pixel_size = 0.0085
	_bubble_text.outline_size = 0
	_bubble_text.modulate = Color(0.12, 0.09, 0.14)
	_bubble_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble_text.no_depth_test = true
	_bubble_text.render_priority = 9
	_bubble_text.position = Vector3(0, 0.0, 0.0)
	_bubble.add_child(_bubble_text)


static func _bubble_material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.albedo_color = color
	m.render_priority = priority
	return m


## What the bubble says right now ("" = hidden).
func bubble_text() -> String:
	return _bubble_shown


func _wanted_bubble() -> String:
	if dead:
		return ""
	var now := GameWorld.time
	if _say_until > now:
		return _say_text
	if state == State.COWER and _hero_near:
		var lines: Array = COWER_LINES[style]
		return str(lines[(int(now / 2.5) + variant) % lines.size()])
	if state == State.PANIC and _hero_near:
		return str(PANIC_LINES[style])
	return ""


func _update_visual(delta: float) -> void:
	var yaw := atan2(-facing.x, -facing.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, clampf(12.0 * delta, 0.0, 1.0))
	if dead:
		return
	_name_label.visible = _hero_near and not _extracted
	var want := _wanted_bubble()
	if want != _bubble_shown:
		_bubble_shown = want
		_bubble.visible = want != ""
		if want != "":
			_bubble_text.text = want
			(_bubble_bg.mesh as QuadMesh).size = Vector2(maxf(0.8, 0.165 * want.length() + 0.35), 0.46)
	if _bubble.visible:
		var t := GameWorld.time
		var pulse := 1.0 + (0.08 * sin(t * 18.0) if state == State.PANIC else 0.0)
		_bubble.scale = Vector3.ONE * pulse
		_bubble.position.y = model.ui_height + 1.2 + sin(t * 5.0) * 0.04

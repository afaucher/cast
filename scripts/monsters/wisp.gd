class_name Wisp
extends Monster
## A ghost (docs/design/haunted-build-plan.md H5, "H5 networking" and "H5 as built"; new-themes.md "Ghosts", decided). The
## user: "players can hit ghosts directly but generally they won't get near you unless they are holding a body. So killing the
## body makes them run, but they get hurt in the process." No spell is needed to beat one.
##   INSIDE  it possesses a host (`host`: an ArmourHost or a BonesHost, which then fights as a monster). Hidden on every
##           screen and out of "actors" and "monsters": nothing can see, hit or find it there. The host's machine keeps it on
##           its host, so its stream entry moves with the host.
##   EJECTED the host broke (HauntHost._on_death on the owner): it pops out where the host fell, hurt (BREAK_HURT through the
##           verb, the culprit as the source: a third of its HP) and briefly helpless (EJECT_DAZE) ...
##   FREE    ... then it flies (FLY_SPEED: the crew walks faster) to the nearest dormant host within SEEK_RANGE it can reach
##           (no other wisp's claim) and possesses it when it gets there (ENTER_REACH: Wisp.possess). With none in range it
##           roams: it keeps KEEP_AWAY from the heroes (a spot away from them, picked again every FLEE_PICK s; never from a
##           hero in ghost form, GhostSpell: H7) and drifts
##           near where it is otherwise, looking again for a host every SEEK_EVERY s. It never attacks. Anyone can hit it
##           (it is a monster: a swing, an arrow, a spell) and it dies to damage (HP). Tentacles pass through it
##           (Tentacles.covers: physical only).
## Online (an owned actor, the host's): `host` is OWNER, carried by world.haunt {id, h, x, y, z} (NetWorld, from
## haunt_changed) on every possession and ejection; a client applies it in net_haunt. Free, it streams as any monster (its
## state: IDLE drifting, ALERT flying or keeping away). Its look (WispModel: the rim wisp, its light; hidden inside; clear while
## this screen's hero is in ghost form) is LOCAL.

## It entered a host (`to`) or left one (null). On the host's machine: NetWorld sends world.haunt.
signal haunt_changed(to: Node)

const GROUP := "wisps"
const HP := 36.0
const FLY_SPEED := 3.4              ## (the crew walks 4.5: a wisp can be run down)
const BREAK_HURT := 12.0            ## what its host's break costs it (a third)
const EJECT_DAZE := 0.5             ## helpless as it pops out
const SEEK_RANGE := 16.0            ## it flies to a dormant host this close (flat distance) ...
const SEEK_EVERY := 2.0             ## ... looking again this often when it has none
const SEEK_PATH := 800              ## the path finder's budget to a host
const ENTER_REACH := 0.7            ## it gets in from this close
const KEEP_AWAY := 7.0              ## with no host to go to it keeps this far from the heroes
const FLEE_PICK := 1.2
const FLEE_MIN := 3                 ## its spot away: this many cells off at least ...
const FLEE_MAX := 6                 ## ... and at most
const DRIFT := 0.45                 ## its idle drift (times its speed), round where it is

## Which wisp is flying to which host: host instance id -> wisp instance id (two never go for one host).
static var _claims := {}

var host: Monster = null            ## the host it possesses (null: free)
var entered := 0                    ## hosts it got into on this machine (tests)
var ejected := 0                    ## times it was thrown out on this machine (tests)
var _goal: Monster = null           ## the dormant host it flies to
var _seek_t := 0.0
var _flee_goal := Vector3.INF
var _flee_pick_t := 0.0
var _drift_goal := Vector3.INF
var _drift_t := 0.0
var _stuck_at := 0


func _init() -> void:
	super._init()
	kind = "wisp"
	display_name = "Ghost"
	max_hp = HP
	move_speed = FLY_SPEED
	radius = 0.3
	aggro_range = KEEP_AWAY
	attack_damage = 0.0
	attack_windup = 0.0
	attack_cooldown = 0.0
	attack_reach = 0.0
	attack_start_range = 0.0
	stop_distance = 0.5
	employee_chance = 0.0
	walk_bob = 0.0
	bar_width = 0.6
	can_climb = true


## Who may write each var (see Net); Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"host": Net.OWNER,             # world.haunt (NetWorld): possessed and ejected on the host's machine
		"entered": Net.LOCAL, "ejected": Net.LOCAL,
		"_goal": Net.PRIVATE, "_seek_t": Net.PRIVATE, "_flee_goal": Net.PRIVATE, "_flee_pick_t": Net.PRIVATE,
		"_drift_goal": Net.PRIVATE, "_drift_t": Net.PRIVATE, "_stuck_at": Net.PRIVATE,
	})
	return f


func _ready() -> void:
	if model == null and not Monster.use_proto_visuals:
		model = WispModel.new()
	super._ready()
	add_to_group(GROUP)
	if model is WispModel:
		(model as WispModel).phase = GameWorld.fx_rng.randf_range(0.0, TAU) if GameWorld.fx_rng != null else 0.0
		(model as WispModel).refresh()


func is_inside() -> bool:
	return host != null


# --- Possession ---------------------------------------------------------------------------------------------------------

## The owner: get into `h` (a dormant HauntHost). `instant`: at spawn (the floor is built with it inside, on every machine
## alike: no event). True when it took.
func possess(h: Monster, instant: bool = false) -> bool:
	if dead or host != null or h == null or not is_instance_valid(h) or h.dead or not Net.owns(self):
		return false
	if not bool(h.call("is_dormant")):
		return false
	_unclaim()
	host = h
	h.call("take_ghost", self, instant)
	entered += 1
	_hide_inside(h, not instant)
	if not instant:
		haunt_changed.emit(h)
	return true


## The owner: its host broke (HauntHost._on_death): out where it fell, hurt by the break (the verb; the culprit its source),
## helpless a moment, then off to the next host.
func eject(from: Monster, culprit: Node = null) -> void:
	if dead or host == null or not Net.owns(self):
		return
	var at := from.global_position if from != null and is_instance_valid(from) else global_position
	var map := GameWorld.map
	if map != null and is_nan(map.ground_height(at)) and from != null and is_instance_valid(from):
		at = from.home   # (its host went into a pit or the lava: the ghost comes out where the host last stood on floor)
	host = null
	ejected += 1
	_show_free(at)
	haunt_changed.emit(null)
	_seek_t = 0.0
	_goal = null
	if Net.resolves(self):
		apply_damage(BREAK_HURT, culprit)
	if not dead:
		stagger(EJECT_DAZE)


## A copy (world.haunt, or a late joiner's `haunts`): where the host's machine has it now: in `h`, or out at `at`.
func net_haunt(h: Monster, at: Vector3 = Vector3.INF) -> void:
	if dead:
		return
	if h != null and is_instance_valid(h) and not h.dead:
		if host == h:
			return
		_release_host()
		host = h
		h.call("net_take_ghost", self)
		entered += 1
		_hide_inside(h, true)
		return
	if host == null:
		return
	_release_host()
	host = null
	ejected += 1
	_show_free(at if at != Vector3.INF else global_position)


func _release_host() -> void:
	if host != null and is_instance_valid(host) and host.get("ghost") == self:
		host.call("drop_ghost")


## Inside: hidden, out of every query (`fx`: the puff of it sinking in; none at spawn).
func _hide_inside(h: Monster, fx: bool) -> void:
	if fx:
		Fx.burst(h.global_position + Vector3.UP * 1.0, [GhostLook.color_now()] as Array[Color], 14, 1.6, 0.08, 0.8, -0.6, Vector3.UP, 120.0)
	global_position = h.global_position
	state = State.IDLE
	target = null
	_telegraph = 0.0
	remove_from_group("actors")
	remove_from_group("monsters")
	visible = false
	if model is WispModel:
		(model as WispModel).set_light(false)
	reset_physics_interpolation()


## Out at `at`: shown, back in the queries.
func _show_free(at: Vector3) -> void:
	global_position = at
	if not is_in_group("actors"):
		add_to_group("actors")
	if not is_in_group("monsters"):
		add_to_group("monsters")
	visible = true
	if model is WispModel:
		(model as WispModel).set_light(true)
	reset_physics_interpolation()
	Fx.burst(at + Vector3.UP * 1.0, [GhostLook.color_now()] as Array[Color], 18, 2.4, 0.09, 0.8, -0.8, Vector3.UP, 150.0)
	home = at
	_home_set = true
	_prog_pos = at
	_clear_path()


# --- Seen by a ghost (GhostSpell): cosmetic, per screen ---------------------------------------------------------------------

## While this screen's own hero is in ghost form, a free ghost shows clearly (WispModel.set_clear: the strong look). On every
## machine (a copy's physics is off, so this is _process).
func _process(_delta: float) -> void:
	if model is WispModel:
		(model as WispModel).set_clear(seen_by_ghost())


## True when a hero this screen plays is in ghost form (GhostSpell.sees_ghosts).
func seen_by_ghost() -> bool:
	for h in heroes():
		if is_instance_valid(h) and GhostSpell.sees_ghosts(h):
			return true
	return false


# --- The free wisp's AI (the host's) ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	if host != null:
		if is_instance_valid(host) and not host.dead:
			global_position = host.global_position   # (rides its host: the stream follows it, it pops out where the host falls)
		return
	if not _home_set:
		_home_set = true
		home = global_position
		_prog_pos = global_position
	if is_helpless():
		_update_visual(delta)
		return
	_tick_free(delta)
	_update_visual(delta)


func _tick_free(delta: float) -> void:
	if _goal != null and (not is_instance_valid(_goal) or _goal.dead or not bool(_goal.call("is_dormant")) or not _claimed_by_me(_goal)):
		_unclaim()
	_seek_t -= delta
	if _goal == null and _seek_t <= 0.0:
		_seek_t = SEEK_EVERY
		var h := find_host()
		if h != null:
			_goal = h
			_claims[h.get_instance_id()] = get_instance_id()
			_stuck_at = _stuck_n
			_clear_path()
	if _goal != null:
		state = State.ALERT
		if GameWorld.flat_distance(global_position, _goal.global_position) <= ENTER_REACH + _goal.radius:
			possess(_goal)
			return
		if _stuck_n - _stuck_at >= 3:
			_unclaim()   # (it cannot get there: look again later)
			return
		_nav_to(_goal.global_position, delta)
		return
	var near := _nearest_to_flee(KEEP_AWAY) if not is_frozen() else null
	if near != null:
		state = State.ALERT
		_flee_pick_t -= delta
		if _flee_goal == Vector3.INF or _flee_pick_t <= 0.0 or GameWorld.flat_distance(global_position, _flee_goal) < 0.6:
			_flee_goal = _away_spot(near.global_position)
			_flee_pick_t = FLEE_PICK
		_nav_to(_flee_goal, delta)
		return
	state = State.IDLE
	_flee_goal = Vector3.INF
	_drift(delta)


## The nearest living hero within `r` it keeps away from: a hero in GHOST FORM is one of its own and it does not run from them
## (GhostSpell, haunted-build-plan.md "H7 as built": ghost form makes ghosts easier). The host's AI, from each hero's status
## (a player's hero: the modifier its owner announced).
func _nearest_to_flee(r: float) -> Actor:
	var best: Actor = null
	var best_d := r
	for h in heroes():
		if not is_instance_valid(h) or h.dead or h.is_ghost_form():
			continue
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d <= best_d:
			best = h
			best_d = d
	return best


## The nearest dormant host within SEEK_RANGE that no other wisp is going for and that it can reach (no dice: the host's AI).
func find_host() -> Monster:
	var map := GameWorld.map
	var cands: Array = []
	for n in get_tree().get_nodes_in_group(HauntHost.GROUP):
		var h := n as Monster
		if h == null or h.dead or not bool(h.call("is_dormant")) or not _free_host(h):
			continue
		var d := GameWorld.flat_distance(global_position, h.global_position)
		if d <= SEEK_RANGE:
			cands.append([d, NetFloor.id_of(h), h])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	for c: Array in cands:
		var h := c[2] as Monster
		if map == null or not map.find_path(current_cell(), h.current_cell(), can_climb, SEEK_PATH).is_empty():
			return h
	return null


func _free_host(h: Monster) -> bool:
	var who: Variant = _claims.get(h.get_instance_id())
	if who == null or int(who) == get_instance_id():
		return true
	var other := instance_from_id(int(who)) as Wisp
	return other == null or other.dead or other.host != null or other._goal != h


func _claimed_by_me(h: Monster) -> bool:
	return int(_claims.get(h.get_instance_id(), get_instance_id())) == get_instance_id()


func _unclaim() -> void:
	if _goal != null and is_instance_valid(_goal) and _claimed_by_me(_goal):
		_claims.erase(_goal.get_instance_id())
	_goal = null


## No host to go to and nobody near: a slow drift round where it is.
func _drift(delta: float) -> void:
	_drift_t -= delta
	if _drift_goal == Vector3.INF or _drift_t <= 0.0 or GameWorld.flat_distance(global_position, _drift_goal) < 0.4:
		_drift_t = GameWorld.rng.randf_range(2.5, 5.0)
		var a := GameWorld.rng.randf_range(0.0, TAU)
		var p := home + Vector3(cos(a), 0.0, sin(a)) * GameWorld.rng.randf_range(0.5, 2.0)
		var map := GameWorld.map
		_drift_goal = p if map == null or map.is_walkable_cell(Hex.from_world(p)) else home
	_speed_k = DRIFT
	_nav_to(_drift_goal, delta)
	_speed_k = 1.0


## A walkable cell FLEE_MIN-FLEE_MAX cells off, as far from `from` as it can find and that it can reach (the acolyte's way).
func _away_spot(from: Vector3) -> Vector3:
	var map := GameWorld.map
	if map == null:
		var away := global_position - from
		away.y = 0.0
		return global_position + (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * 4.0
	var here := current_cell()
	var cell_here := map.get_cell(here)
	var lv := cell_here.level if cell_here != null else 0
	var cands: Array = []
	for c in Hex.range_cells(here, FLEE_MAX):
		if Hex.distance(c, here) < FLEE_MIN or not map.is_walkable_cell(c) or map.is_pool_cell(c):
			continue
		var cc := map.get_cell(c)
		if absi(cc.level - lv) > 2:
			continue
		var p := Hex.to_world(c, float(cc.level))
		cands.append([GameWorld.flat_distance(p, from) - GameWorld.flat_distance(global_position, from), c, p])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for i in mini(cands.size(), 6):
		if not map.find_path(here, cands[i][1], can_climb, 300).is_empty():
			return cands[i][2]
	return global_position


# --- Never a fighter --------------------------------------------------------------------------------------------------------

## A hit, a call, a chicken: it does not fight back (its AI keeps away or makes for a host).
func aggro(_t: Actor) -> void:
	pass


func alert(_pos: Vector3) -> bool:
	return false


func hear(_pos: Vector3) -> bool:
	return false


func is_aggro() -> bool:
	return false


func _strike() -> void:
	pass


func net_strike(_victim: Actor) -> void:
	pass


func _on_death() -> void:
	_unclaim()
	if host != null and is_instance_valid(host):
		_release_host()
	host = null
	visible = true
	Fx.burst(global_position + Vector3.UP * 1.0, [GhostLook.color_now(), Color(1, 1, 1)] as Array[Color], 22, 2.8, 0.1, 0.9, -1.0, Vector3.UP, 180.0)
	super._on_death()


# --- The look without a model (Monster.use_proto_visuals) --------------------------------------------------------------------

func _build_visual(root: Node3D) -> void:
	var glow := _mat(Color(0.7, 0.86, 1.0), 1.5)
	_sphere(root, 0.27, Vector3(0, WispModel.HOVER, 0), glow)
	_sphere(root, 0.15, Vector3(0, WispModel.HOVER - 0.2, 0.25), glow)

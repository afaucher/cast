class_name Gator
extends Monster
## The sewer gator (docs/design/sewer-concept.md, "The gator" and "Shoved gators"; phase 1, "Phase 1 as built"): the
## client's property with teeth, territorial and slow to anger. It lives in a sewer's HOME REGION (the water and the dry
## cells within 2 of it, spawn data) and walks the same cells as anyone: 2.4 in the water, 1.4 on land.
##
## WHAT IT IS (user, 2026-10-20): killed and billed once, to the killer, like the shark: "Gator" $6,300 (MonsterDefs
## "gator" billed row), HP 150. Team NEUTRAL; groups "gators", "sharks" (the family of priced water creatures: monsters
## shrug off their bites, archers never practise on them, the bowl bills them, the fog hides them like any mover) and
## PricedProp.GROUP (the crew's swings, arrows and bolts hit it; the AI allies' prop care keeps it out of their swings).
## Never "monsters": never a pest, never in a pack or a gate (it has no "pack" or "gate" row), monsters never target it.
##
## BEHAVIOUR (the host's; a client shows the host's gator as a puppet, see NETWORKING below):
##   CALM    resting at its spot (eyes half lit). Every 30-45 s (rolled from its spawn seed), calm and with nobody within 6,
##           it RELOCATES: MOVE slowly (1.2 water / 0.9 land) to another bask spot within 14 (path, inside its region)
##   WATCH   anything within WATCH_R (4.5) of its head: it turns to track it, eyes bright
##   NIP     anything inside its TERRITORY (3.0; 2.0 while moving; 4.5 while riled) for DWELL (0.4 s), or touching it: the nip.
##           Wind-up NIP_WINDUP (0.5 s: the jaws gape, the orange pulse), a lunge of up to NIP_LUNGE (1.0), a bite within
##           NIP_REACH (1.4) of the snout on ONE victim: NIP_DAMAGE (10) and a NIP_SHOVE (1.6) away from the gator. Cooldown
##           1.6 s. Targets: heroes, monsters, employees, chickens; not a downed hero, another gator or a prop. The nearest to
##           the snout, those in its 120-degree front at 0.7 of their distance, the latest arrival breaking ties
##   RILED   after any hit or shove: its territory is 4.5 for 8 s and it advances up to 2.0 toward the attacker, once. A shove
##           also sends its first nip at once to the nearest body where it lands
##   MOVE    relocating, walking home, the riled advance, or running for the water (burning on land)
##   CHUM    corn in its water within 6 (Gator.corn_at from CornStrike): it noses the kernels for 4 s, no nips
##   HELD    dazed (it still turns); a root (vines) holds it in place, it still nips
## SHOVES move it like any body (Actor.shove, shove_mult 1): shoved out of its region it walks home (find_path, its walking
## speeds, nipping only what touches it); shoved within it, it settles where it lands (its new spot). With no way home it
## settles where it is (a temporary spot) and tries again at each relocation. It never teleports. Into a pit or lava (void):
## it falls and dies, and the kill bills whoever shoved it (the culprit: the last thing that hurt or shoved it).
## FIRE: in the water it can't burn (fireproof, the fire goes out); 15 s dry it can, and a burning gator runs for the water
## and doesn't nip.
## States ride the stream's 3 bits: CALM 0, RILED 1, NIP 2, MOVE 3, DEAD 4, WATCH 5, HELD 6, CHUM 7.
##
## LOOK (LOCAL, every screen; docs/design/gator-look.md, the user's pick 2026-10-20): GatorModel ("Mugger": knobbed, mossy,
## scarred, ember eyes) at GATOR_SCALE, a rigid-part rig posed every frame, toon material (MonsterMaterial: ink outline,
## amber rim), its eyes the monster glow (glow_gain by state). Cosmetic motion from what every machine sees (state, facing,
## the wind-up, its speed, the water): the body curls as it turns; an S-wave down the tail (lazy at rest, swimming in the
## water, a thrash when riled); the high walk on land (legs in diagonal pairs, the trunk and tail swaying); legs folded and
## the head up in the water; a breath; the head tracking the nearest body it watches; the jaws parting through the nip's
## wind-up to the gape and snapping shut; chewing on chum; an idle jaw twitch (GameWorld.fx_rng); a V wake and a ripple.
##
## NETWORKING (sewer phase 2, docs/design/sewer-concept.md "Phase 2 as built"): a host-owned actor in the world stream, like
## the shark. Its MONSTER entry carries its position, facing, HP, state (the 3 bits above), the wind-up (_telegraph) and its
## strikes; it has no OWNER var beyond Monster's. The nip's wind-up is `world.windup {id, s, l, v}` with l = NIP_WINDUP +
## LUNGE_T (the wind-up and the longest lunge), and each client resolves the bite on its own hero when its screen reaches
## that moment (Monster.net_strike -> _strike: the jaws where the puppet shows them, after the host's lunge); the host
## resolves monsters, employees, chickens and the AI heroes. A client's hit or shove on it is a request (Net.route_hit /
## Actor.shove on a copy -> Net.route_shove), so the riling, the slide, the walk home and the void bill are the host's; its
## death is `world.die` and its bill the host's Ledger line (every client's Ledger mirrors it). Corn's chum (corn_at) runs
## on the host only (Net.simulates). A late joiner gets it in the keyframe (a dead one is a gone id). Its spawn data (home
## region, bask spots, seed, price) is in the floor checksum (net_spawn_text, NetFloor.spawn_text_of). The rig's motion is
## LOCAL and driven from what a puppet has: its shown position (speed), facing, state, the wind-up and the water.

const PoolProps := preload("res://scripts/art/lowpoly/props/pool_props.gd")

const CALM := 0
const RILED := 1
const NIP := 2
const MOVE := 3
const DEAD_STATE := 4
const WATCH := 5
const HELD := 6
const CHUM := 7
const STATE_NAMES := ["calm", "riled", "nip", "move", "dead", "watch", "held", "chum"]

const HP := 150.0
## What killing one bills: its MonsterDefs "billed" row (user, 2026-10-20: "6300").
static var PRICES: Dictionary = MonsterDefs.prices("gator")
static var NAMES: Dictionary = MonsterDefs.bill_names("gator")
const WATER_SPEED := 2.4
const LAND_SPEED := 1.4
const MOVE_WATER_SPEED := 1.2      ## relocating
const MOVE_LAND_SPEED := 0.9
const WATCH_R := 4.5
const TERRITORY := 3.0
const TERRITORY_MOVING := 2.0
const TERRITORY_RILED := 4.5
const TOUCH := 1.3                 ## walking home it nips only what touches it (this close to its head)
const DWELL := 0.4
const NIP_WINDUP := 0.5
const NIP_LUNGE := 1.0
const LUNGE_SPEED := 9.0
const LUNGE_T := NIP_LUNGE / LUNGE_SPEED   ## the longest lunge: world.windup's length is the wind-up plus this
const NIP_REACH := 1.4
const NIP_DAMAGE := 10.0
const NIP_SHOVE := 1.6
const NIP_COOLDOWN := 1.6
const FRONT_COS := 0.5             ## its front: 120 degrees ...
const FRONT_K := 0.7               ## ... counted at this share of their distance
const RILED_T := 8.0
const RILE_ADVANCE := 2.0
const RELOCATE_MIN := 30.0
const RELOCATE_MAX := 45.0
const RELOCATE_CLEAR := 6.0        ## nobody this close, or it stays put
const RELOCATE_RANGE := 14.0       ## another spot within this much walking
const HOME_REACH := 2              ## its region: the water and the cells within this many of it
const STUCK_T := 2.0               ## no headway this long: it routes again; twice: it settles where it is
const TURN_RATE := 3.2             ## rad/s it turns to track something
const HEAD := 0.9                  ## its head joint, ahead of the body's origin
const SNOUT := 1.15                ## its jaws
const CHUM_T := 4.0
const CHUM_RADIUS := 6.0
const DRY_BURN_T := 15.0
const GATOR_SCALE := 1.3           ## GatorModel (2.3 long) at 1.3: about 3.0 snout to tail
const BENDS: Array[float] = [-44.0, -22.0, 0.0, 22.0, 44.0]   ## the curl's range (the last) and the z-fight registry's poses
const GAIT_PER_UNIT := 1.35        ## walk cycles per unit walked (the look: a stride of about 0.44 at GATOR_SCALE)
const HEAD_TURN := 35.0            ## degrees the head turns toward what it watches (the look)
const WATER_LIFT := 0.02           ## in the water: its eyes, its back and the ridge of scutes break the surface, the rest is in the murk

# --- spawn data (SewerDev, from the layout) ----------------------------------------------------------------------------
var price := 6300
var home_cells: Dictionary = {}    ## Vector2i -> true: its home region
var bask_spots: Array[Vector2] = []  ## X/Z: its spawn spot first, then the layout's bask spots
var spawn_seed := 0                ## its relocation rolls

# --- host AI ---------------------------------------------------------------------------------------------------------
var _rng := RandomNumberGenerator.new()
var _inside: Dictionary = {}       ## instance id -> seconds inside the territory (DWELL)
var _arrived: Dictionary = {}      ## instance id -> GameWorld.time it came within WATCH_R (latest arrival breaks ties)
var _nip_ready := 0.0
var _victim: WeakRef = null
var _riled_until := -INF
var _rile_by: WeakRef = null
var _advance_left := 0.0
var _nip_now := false
var _relocate_at := 0.0
var _rest := Vector2.ZERO          ## where it rests now (its spot)
var _temp_spot := false            ## _rest is a spot it settled on where no way home led
var _route: Array[Vector3] = []
var _route_i := 0
var _move_kind := ""               ## "relocate" | "home" | "advance" | "water"
var _move_tries := 0
var _prog_left := STUCK_T
var _prog_from := Vector3.ZERO
var _lunge_left := 0.0
var _lunge_dir := Vector3.ZERO
var _chum_until := -INF
var _chum_at := Vector3.ZERO
var _dry_since := 0.0
var _fireproof := true
var _last_by: WeakRef = null
var nips := 0                      ## nips landed (tests, the log)

# --- the look ----------------------------------------------------------------------------------------------------------
var body: Node3D = null            ## the model's pivot (turned to face +Z forward)
var rig: GatorModel = null          ## the rig (GatorModel), posed every frame
var _skin: ShaderMaterial = null
var _swim_k := 0.0                 ## 0 on land .. 1 swimming (legs folded, head up)
var _walk_k := 0.0                 ## how much of the walk cycle shows
var _gait := 0.0                   ## the walk cycle, 0..1
var _wave_amp := 0.0               ## the S-wave's swing (degrees at the tail tip)
var _wave_phase := 0.0
var _head_yaw := 0.0
var _head_pitch := 0.0
var _jaw_k := 0.0
var _twitch_at := 0.0              ## the next idle jaw twitch (GameWorld.time)
var _bend := 0.0
var _prev_yaw := 0.0
var _float_y := 0.0
var _wake: MeshInstance3D = null
var _wake_mat: StandardMaterial3D = null
var _ripple: Node3D = null
var _dead_k := 0.0
var _speed_seen := 0.0
var _last_pos := Vector3.ZERO
var _heard_nip := false            ## the sounds (_sounds): its state was NIP last frame
var _heard_wet := -1               ## ... it was in the water (1), on land (0), not seen yet (-1)
var _splash_t := -INF              ## ... GameWorld.time of its last splash


## A gator standing at X/Z `at`, facing `face`, home in `region`, its bask `spots` (the first is where it starts resting).
static func spawn(at: Vector2, face: Vector2, region: Dictionary, spots: Array[Vector2], seed_value: int) -> Gator:
	if GameWorld.root == null:
		return null
	var g := Gator.new()
	g.home_cells = region
	g.bask_spots = spots.duplicate()
	if g.bask_spots.is_empty() or g.bask_spots[0].distance_to(at) > 0.5:
		g.bask_spots.push_front(at)
	g.spawn_seed = seed_value
	g.facing = Vector3(face.x, 0.0, face.y).normalized() if face.length() > 0.01 else Vector3.FORWARD
	var y := 0.0
	if GameWorld.map != null:
		var gh := GameWorld.map.ground_height(Vector3(at.x, 0.0, at.y))
		y = 0.0 if is_nan(gh) else gh
	GameWorld.spawn(g, Vector3(at.x, y, at.y))
	return g


## The home region of a sewer map: every floor cell with water and every non-wall cell within HOME_REACH of one.
static func region_of(map: HexMap) -> Dictionary:
	var out := {}
	var frontier: Array[Vector2i] = []
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type != HexMap.Tile.WALL and cell.pool_mask != 0:
			out[c] = 0
			frontier.append(c)
	for step in range(1, HOME_REACH + 1):
		var next: Array[Vector2i] = []
		for c in frontier:
			for d in Hex.DIRS:
				var n: Vector2i = c + d
				var cell: HexMap.Cell = map.get_cell(n)
				if cell == null or cell.type == HexMap.Tile.WALL or out.has(n):
					continue
				out[n] = step
				next.append(n)
		frontier = next
	var region := {}
	for c: Vector2i in out:
		region[c] = true
	return region


func _init() -> void:
	super._init()
	kind = "gator"
	team = GameWorld.TEAM_NEUTRAL
	max_hp = HP
	price = int(PRICES.get("regular", 6300))
	display_name = String(NAMES.get("regular", "Gator"))
	move_speed = WATER_SPEED
	radius = 0.55
	shove_mult = 1.0
	can_climb = false
	aggro_range = WATCH_R
	attack_damage = NIP_DAMAGE
	attack_windup = NIP_WINDUP
	attack_cooldown = NIP_COOLDOWN
	attack_reach = NIP_REACH
	attack_start_range = TERRITORY
	employee_chance = 0.0
	walk_bob = 0.0
	bar_height = 1.05
	bar_width = 1.1


func _ready() -> void:
	super._ready()
	name = "Gator"
	remove_from_group("monsters")
	add_to_group("gators")
	add_to_group("sharks")
	add_to_group(PricedProp.GROUP)
	_rng.seed = spawn_seed
	_rest = Vector2(global_position.x, global_position.z)
	_relocate_at = GameWorld.time + _rng.randf_range(RELOCATE_MIN, RELOCATE_MAX)
	_dry_since = GameWorld.time
	_last_pos = global_position
	_prev_yaw = atan2(facing.x, facing.z)
	state = CALM
	_tick_water()


## Who may write each var (see Net). Monster's come from super().
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"price": Net.SPAWN, "home_cells": Net.SPAWN, "bask_spots": Net.SPAWN, "spawn_seed": Net.SPAWN,
		"_rng": Net.PRIVATE, "_inside": Net.PRIVATE, "_arrived": Net.PRIVATE, "_nip_ready": Net.PRIVATE, "_victim": Net.PRIVATE,
		"_riled_until": Net.PRIVATE, "_rile_by": Net.PRIVATE, "_advance_left": Net.PRIVATE, "_nip_now": Net.PRIVATE,
		"_relocate_at": Net.PRIVATE, "_rest": Net.PRIVATE, "_temp_spot": Net.PRIVATE, "_route": Net.PRIVATE,
		"_route_i": Net.PRIVATE, "_move_kind": Net.PRIVATE, "_move_tries": Net.PRIVATE, "_prog_left": Net.PRIVATE,
		"_prog_from": Net.PRIVATE, "_lunge_left": Net.PRIVATE, "_lunge_dir": Net.PRIVATE, "_chum_until": Net.PRIVATE,
		"_chum_at": Net.PRIVATE, "_dry_since": Net.PRIVATE, "_fireproof": Net.PRIVATE, "_last_by": Net.PRIVATE,
		"nips": Net.PRIVATE,
		"body": Net.LOCAL, "rig": Net.LOCAL, "_skin": Net.LOCAL, "_bend": Net.LOCAL, "_swim_k": Net.LOCAL,
		"_walk_k": Net.LOCAL, "_gait": Net.LOCAL, "_wave_amp": Net.LOCAL, "_wave_phase": Net.LOCAL, "_head_yaw": Net.LOCAL,
		"_head_pitch": Net.LOCAL, "_jaw_k": Net.LOCAL, "_twitch_at": Net.LOCAL,
		"_prev_yaw": Net.LOCAL, "_float_y": Net.LOCAL, "_wake": Net.LOCAL, "_wake_mat": Net.LOCAL, "_ripple": Net.LOCAL,
		"_dead_k": Net.LOCAL, "_speed_seen": Net.LOCAL, "_last_pos": Net.LOCAL,
		"_heard_nip": Net.LOCAL, "_heard_wet": Net.LOCAL, "_splash_t": Net.LOCAL,
	})
	return f


## Its spawn data for the floor checksum (NetFloor.spawn_text_of): the home region, the bask spots, the relocation seed and
## the price. Every machine builds them from the seed; one different cell or spot is a different floor.
func net_spawn_text() -> String:
	var cells: Array = home_cells.keys()
	cells.sort()
	return "region=%s|spots=%s|seed=%d|price=%d" % [NetFloor.canon(cells), NetFloor.canon(bask_spots), spawn_seed, price]


# --- queries (tests, the AI allies, the log) -----------------------------------------------------------------------------

func state_name() -> String:
	return STATE_NAMES[state] if state >= 0 and state < STATE_NAMES.size() else str(state)


func head() -> Vector3:
	return global_position + Vector3(facing.x, 0.0, facing.z).normalized() * HEAD


func jaws() -> Vector3:
	return global_position + Vector3(facing.x, 0.0, facing.z).normalized() * SNOUT


func territory() -> float:
	if state == MOVE:
		return TOUCH if _move_kind == "home" else TERRITORY_MOVING
	if is_riled():
		return TERRITORY_RILED
	return TERRITORY


func is_riled() -> bool:
	return GameWorld.time < _riled_until


func in_water() -> bool:
	return GameWorld.map != null and GameWorld.map.water_at(global_position)


func in_region(c: Vector2i) -> bool:
	return home_cells.is_empty() or home_cells.has(c)


## Where it rests now (X/Z).
func rest_spot() -> Vector2:
	return _rest


func relocate_at() -> float:
	return _relocate_at


func last_culprit() -> Node:
	return _last_by.get_ref() as Node if _last_by != null else null


## It walks; the speed is its own (in the water it swims at WATER_SPEED: no wading slow), times its modifiers.
func effective_speed() -> float:
	return 0.0 if is_rooted() else move_speed * move_speed_mult()


# --- the host's AI -----------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick_water()
	_track(delta)
	if is_helpless():
		# shoved, staggered or dazed: no steering, no nips (a daze shows as HELD)
		if is_dazed() and state != HELD:
			_drop_nip()
			state = HELD
		_update_visual(delta)
		return
	if state == HELD:
		state = RILED if is_riled() else CALM
	match state:
		CALM:
			_tick_calm(delta)
		WATCH, RILED:
			_tick_watch(delta)
		NIP:
			_tick_nip(delta)
		MOVE:
			_tick_move(delta)
		CHUM:
			_tick_chum(delta)
	_update_visual(delta)


## In the water: fireproof (a fire goes out). DRY_BURN_T dry: it can burn.
func _tick_water() -> void:
	var wet := in_water()
	if wet:
		_dry_since = GameWorld.time
	var proof := wet or GameWorld.time - _dry_since < DRY_BURN_T
	if proof != _fireproof:
		_fireproof = proof
		Burning.set_fireproof(self, proof)
	elif proof and Burning.is_burning(self):
		Burning.extinguish(self)
	var relocating := state == MOVE and _move_kind == "relocate"
	move_speed = (MOVE_WATER_SPEED if wet else MOVE_LAND_SPEED) if relocating else (WATER_SPEED if wet else LAND_SPEED)


## Who is near: the dwell inside the territory and the arrival times inside the watch.
func _track(delta: float) -> void:
	var h := head()
	var r := territory()
	var seen := {}
	for a in GameWorld.actors_in_radius(h, WATCH_R):
		if not _nippable(a):
			continue
		var id := a.get_instance_id()
		seen[id] = true
		if not _arrived.has(id):
			_arrived[id] = GameWorld.time
		if GameWorld.flat_distance(a.global_position, h) <= r + a.radius:
			_inside[id] = float(_inside.get(id, 0.0)) + delta
		else:
			_inside.erase(id)
	for id: int in _arrived.keys():
		if not seen.has(id):
			_arrived.erase(id)
			_inside.erase(id)


## Can it nip `a`: alive, not itself, not another gator, a prop, a crate, a box, a gate or a blocker, and about level.
func _nippable(a: Actor) -> bool:
	if a == null or not is_instance_valid(a) or a.dead or a == self:
		return false
	if a.is_in_group("gators") or a.is_in_group(PricedProp.GROUP) or a.is_in_group("breakables") or a is Hellgate or a is DecorBlocker:
		return false
	return absf(a.global_position.y - global_position.y) <= 1.3


## The one it nips now: inside the territory for DWELL (or touching, or right after a shove), the nearest to the snout,
## those in front at FRONT_K of their distance, the latest arrival breaking ties. Null: nobody.
func _pick(force: bool) -> Actor:
	var best: Actor = null
	var best_s := INF
	var best_t := -INF
	var j := jaws()
	var fwd := Vector2(facing.x, facing.z).normalized()
	var r := territory()
	for a in GameWorld.actors_in_radius(head(), r):
		if not _nippable(a):
			continue
		var id := a.get_instance_id()
		var d := GameWorld.flat_distance(a.global_position, j)
		var touching := GameWorld.flat_distance(a.global_position, global_position) <= radius + a.radius + 0.35
		if not force and not touching and float(_inside.get(id, 0.0)) < DWELL:
			continue
		var to := Vector2(a.global_position.x - global_position.x, a.global_position.z - global_position.z)
		var s := d * (FRONT_K if to.length() > 0.01 and fwd.dot(to.normalized()) >= FRONT_COS else 1.0)
		var t := float(_arrived.get(id, 0.0))
		if s < best_s - 0.05 or (absf(s - best_s) <= 0.05 and t > best_t):
			best = a
			best_s = s
			best_t = t
	return best


## The nearest body inside the watch (to look at), or null.
func _nearest_watched() -> Actor:
	var best: Actor = null
	var best_d := INF
	for a in GameWorld.actors_in_radius(head(), WATCH_R):
		if not _nippable(a):
			continue
		var d := GameWorld.flat_distance(a.global_position, global_position)
		if d < best_d:
			best_d = d
			best = a
	return best


func _set_state(s: int) -> void:
	state = s
	if s != NIP:
		_telegraph = 0.0


func _tick_calm(_delta: float) -> void:
	if GameWorld.time < _chum_until:
		_set_state(CHUM)
		return
	if _burning_on_land():
		_go_to_water()
		return
	if _nearest_watched() != null:
		_set_state(RILED if is_riled() else WATCH)
		return
	if GameWorld.time >= _relocate_at:
		if _anyone_within(RELOCATE_CLEAR):
			_relocate_at = GameWorld.time + 2.0
		else:
			_begin_relocation()


func _tick_watch(delta: float) -> void:
	if GameWorld.time < _chum_until:
		_set_state(CHUM)
		return
	if _burning_on_land():
		_go_to_water()
		return
	var w := _nearest_watched()
	if w != null:
		_turn_to(w.global_position, delta)
	if GameWorld.time >= _nip_ready:
		var v := _pick(_nip_now)
		if v != null:
			_begin_nip(v)
			return
	if _nip_now and w == null:
		_nip_now = false
	# the riled advance: up to RILE_ADVANCE toward the attacker, once
	if is_riled() and _advance_left > 0.05 and _rile_by != null:
		var att := _rile_by.get_ref() as Actor
		if att != null and is_instance_valid(att) and not att.dead and GameWorld.flat_distance(att.global_position, global_position) > NIP_REACH + 0.6:
			var before := global_position
			_steer_to(att.global_position, delta)
			_advance_left -= GameWorld.flat_distance(before, global_position)
			if GameWorld.flat_distance(before, global_position) < 0.0005:
				_advance_left = 0.0
		else:
			_advance_left = 0.0
		if _advance_left <= 0.05 and in_region(Hex.from_world(global_position)):
			_rest = Vector2(global_position.x, global_position.z)   # (it rests where the advance ended)
	if state == RILED and not is_riled():
		_set_state(WATCH)
	if w == null and _advance_left <= 0.05:
		_set_state(RILED if is_riled() else CALM)


func _turn_to(p: Vector3, delta: float) -> void:
	var to := p - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	var cur := Vector2(facing.x, facing.z).normalized()
	var want := Vector2(to.x, to.z).normalized()
	var ang := cur.angle_to(want)
	var step := clampf(ang, -TURN_RATE * delta, TURN_RATE * delta)
	var nf := cur.rotated(step)
	facing = Vector3(nf.x, 0.0, nf.y)


func _anyone_within(r: float) -> bool:
	for a in GameWorld.actors_in_radius(global_position, r):
		if _nippable(a):
			return true
	return false


# --- the nip ------------------------------------------------------------------------------------------------------------

func _begin_nip(v: Actor) -> void:
	_victim = weakref(v)
	target = v
	_nip_now = false
	_set_state(NIP)
	_windup_total = NIP_WINDUP
	_windup_left = NIP_WINDUP
	_telegraph = 0.0
	_lunge_left = 0.0
	windup_begun.emit(NIP_WINDUP + LUNGE_T)   # (online, world.windup: a client's bite lands after the host's lunge)


func _tick_nip(delta: float) -> void:
	var v := _victim.get_ref() as Actor if _victim != null else null
	if _lunge_left > 0.0:
		var step := minf(_lunge_left, LUNGE_SPEED * delta)
		_lunge_left -= step
		var map := GameWorld.map
		var to := global_position + _lunge_dir * step
		if map != null:
			to = map.clip_move(global_position, to, radius)
			if map.movement_check(global_position, to) == HexMap.Move.OK and not is_rooted():
				global_position = Vector3(to.x, global_position.y, to.z)
				snap_to_ground()
		if _lunge_left <= 0.0:
			_strike()
		return
	_windup_left -= delta
	_telegraph = clampf(1.0 - _windup_left / NIP_WINDUP, 0.0, 1.0)
	if v != null and is_instance_valid(v) and not v.dead and _telegraph < 0.6:
		_turn_to(v.global_position, delta * 2.0)
	if _windup_left > 0.0:
		return
	# the lunge: up to NIP_LUNGE toward the victim (as far as leaves its jaws on it)
	var reach := 0.0
	_lunge_dir = Vector3(facing.x, 0.0, facing.z).normalized()
	if v != null and is_instance_valid(v) and not v.dead:
		var to_v := v.global_position - global_position
		to_v.y = 0.0
		if to_v.length() > 0.01 and Vector2(to_v.x, to_v.z).normalized().dot(Vector2(_lunge_dir.x, _lunge_dir.z)) > 0.3:
			reach = clampf(to_v.length() - SNOUT, 0.0, NIP_LUNGE)
	if reach <= 0.01 or is_rooted():
		_strike()
	else:
		_lunge_left = reach


## The bite on its one victim. The host runs it at the end of its lunge; a client runs it on the puppet when its screen
## reaches the wind-up's moment (Monster.net_strike sets `target` to the host's victim), and Combat.bite applies it only
## where it resolves: on a client, its own hero. The bookkeeping after it is the host's (a puppet's state is streamed).
func _strike() -> void:
	var v := _victim.get_ref() as Actor if _victim != null else null
	if v == null and target != null and is_instance_valid(target):
		v = target   # (a puppet's strike from the wind-up event: Monster.net_strike sets `target`)
	var at := jaws()
	Sfx.play_at("gator_snap", at)   # (the host's bite and each client's: once per screen)
	if v != null and is_instance_valid(v) and not v.dead:
		var skip: Array = []
		for a in GameWorld.actors_in_radius(at, NIP_REACH + 1.0):
			if a != v:
				skip.append(a)
		var away := func(a: Actor) -> Vector3:
			var d := a.global_position - global_position
			d.y = 0.0
			return d if d.length() > 0.05 else Vector3(facing.x, 0.0, facing.z)
		var hit := Combat.bite(self, at, NIP_REACH, NIP_DAMAGE, NIP_SHOVE, away, skip, 1.3)
		if not hit.is_empty() and Net.simulates(self):
			nips += 1
		_inside.erase(v.get_instance_id())
	if not Net.simulates(self):
		return   # (a puppet: its state, strikes and wind-up come with the host's stream)
	_telegraph = 0.0
	strikes += 1
	_strike_t = 1.0
	_nip_ready = GameWorld.time + scaled_cooldown(NIP_COOLDOWN)
	if Net.owns(self):
		MonsterSenses.noise(global_position, MonsterSenses.NOISE_MELEE, "bite")
	_victim = null
	target = null
	_set_state(MOVE if not _route.is_empty() and _move_kind != "" else (RILED if is_riled() else WATCH))


func _drop_nip() -> void:
	if state == NIP:
		windup_dropped.emit()
	_telegraph = 0.0
	_lunge_left = 0.0
	_victim = null
	target = null


# --- moving: relocation, home, the water -------------------------------------------------------------------------------

## Off to another bask spot within RELOCATE_RANGE (walking, inside its region): MOVE, slowly. None in reach: it tries
## again at the next relocation.
func _begin_relocation() -> void:
	_relocate_at = GameWorld.time + _rng.randf_range(RELOCATE_MIN, RELOCATE_MAX)
	var here := Hex.from_world(global_position)
	var spots: Array[Vector2] = bask_spots.duplicate()
	if _temp_spot and not spots.has(_rest):
		spots.append(_rest)
	var order: Array[int] = []
	for i in spots.size():
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := order[i]
		order[i] = order[j]
		order[j] = t
	for i in order:
		var s: Vector2 = spots[i]
		if s.distance_to(_rest) < 1.0:
			continue
		var route := _region_route(here, s)
		if route.is_empty() or _route_length(route) > RELOCATE_RANGE:
			continue
		_start_move(route, "relocate")
		return
	if _temp_spot:
		# settled where no way led home: try the way home again (any path)
		_go_home()


func _route_length(route: Array[Vector3]) -> float:
	var total := 0.0
	var prev := global_position
	for p in route:
		total += GameWorld.flat_distance(prev, p)
		prev = p
	return total


func _start_move(route: Array[Vector3], what: String) -> void:
	_route = route
	_route_i = 0
	_move_kind = what
	_move_tries = 0
	_prog_left = STUCK_T
	_prog_from = global_position
	_set_state(MOVE)


func _tick_move(delta: float) -> void:
	if GameWorld.time < _chum_until and _move_kind != "water":
		_end_move(false)
		_set_state(CHUM)
		return
	# it nips what comes inside its (smaller) territory on the way, never while running for the water
	if _move_kind != "water" and GameWorld.time >= _nip_ready:
		var v := _pick(_nip_now)
		if v != null:
			_begin_nip(v)
			return
	if _route_i >= _route.size():
		_arrive()
		return
	var goal := _route[_route_i]
	if GameWorld.flat_distance(global_position, goal) < (0.25 if _route_i == _route.size() - 1 else 0.45):
		_route_i += 1
		if _route_i >= _route.size():
			_arrive()
		return
	_steer_to(goal, delta)
	_prog_left -= delta
	if _prog_left <= 0.0:
		if GameWorld.flat_distance(global_position, _prog_from) < 0.35 and not is_rooted():
			_move_tries += 1
			if _move_tries >= 2:
				_settle_here(true)   # no headway twice: it settles where it is (never stuck for good)
				return
			_reroute()
		_prog_left = STUCK_T
		_prog_from = global_position


func _reroute() -> void:
	var goal := _route[_route.size() - 1] if not _route.is_empty() else global_position
	var here := Hex.from_world(global_position)
	var g2 := Vector2(goal.x, goal.z)
	var route := _region_route(here, g2) if _move_kind == "relocate" else _any_route(here, g2)
	if route.is_empty():
		_settle_here(true)
		return
	_route = route
	_route_i = 0


func _arrive() -> void:
	var kind_was := _move_kind
	_end_move(true)
	if kind_was == "water":
		_set_state(RILED if is_riled() else CALM)
		return
	_set_state(RILED if is_riled() else CALM)


func _end_move(rest_here: bool) -> void:
	_route.clear()
	_route_i = 0
	_move_kind = ""
	if rest_here:
		_rest = Vector2(global_position.x, global_position.z)
		_temp_spot = false


## It stays where it is: its spot until the next relocation (`temp`: no way led home; it tries again then).
func _settle_here(temp: bool) -> void:
	_route.clear()
	_route_i = 0
	_move_kind = ""
	_rest = Vector2(global_position.x, global_position.z)
	_temp_spot = temp and not in_region(Hex.from_world(global_position))
	_set_state(RILED if is_riled() else CALM)


## Walk back into its region, to the nearest bask spot it can reach (any path, its walking speeds, nipping only what
## touches it). No path: it settles where it is.
func _go_home() -> void:
	var here := Hex.from_world(global_position)
	var best: Array[Vector3] = []
	var best_len := INF
	for s in bask_spots:
		var route := _any_route(here, s)
		if route.is_empty():
			continue
		var l := _route_length(route)
		if l < best_len:
			best_len = l
			best = route
	if best.is_empty():
		_settle_here(true)
		return
	_start_move(best, "home")


func _burning_on_land() -> bool:
	return Burning.is_burning(self) and not in_water()


## Burning on land: straight for the nearest water (no nips on the way).
func _go_to_water() -> void:
	var map := GameWorld.map
	if map == null:
		return
	var here := Hex.from_world(global_position)
	var best := Vector2i.ZERO
	var best_d := 1 << 20
	for c: Vector2i in home_cells:
		var cell := map.get_cell(c)
		if cell == null or cell.pool_mask != HexMap.ALL_KITES or not map.is_walkable_cell(c):
			continue
		var d := Hex.distance(c, here)
		if d < best_d:
			best_d = d
			best = c
	if best_d >= 1 << 20:
		return
	var w := Hex.to_world(best)
	var route := _any_route(here, Vector2(w.x, w.z))
	if not route.is_empty():
		_start_move(route, "water")


## A route (world points) from cell `from` to X/Z `goal` inside its home region (BFS over its walkable cells: it never
## leaves its region on a relocation). [] when there is none.
func _region_route(from: Vector2i, goal: Vector2) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var map := GameWorld.map
	if map == null:
		return out
	var goal_c := Hex.from_world(Vector3(goal.x, 0.0, goal.y))
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var qi := 0
	var found := from == goal_c
	while qi < queue.size() and not found:
		var c: Vector2i = queue[qi]
		qi += 1
		for d in Hex.DIRS:
			var n: Vector2i = c + d
			if prev.has(n) or not in_region(n):
				continue
			if n != goal_c and not map.is_walkable_cell(n):
				continue
			if map.cell_transition(c, n) != HexMap.Move.OK and n != goal_c:
				continue
			prev[n] = c
			if n == goal_c:
				found = true
				break
			queue.append(n)
	if not found:
		return out
	var cells: Array[Vector2i] = []
	var cur := goal_c
	while cur != from:
		cells.push_front(cur)
		cur = prev[cur]
	for c in cells:
		out.append(Hex.to_world(c))
	if out.is_empty():
		out.append(Vector3(goal.x, 0.0, goal.y))
	else:
		out[out.size() - 1] = Vector3(goal.x, 0.0, goal.y)
	return out


## A route over the whole floor (HexMap.find_path, no climbing), ending at `goal`. [] when there is none.
func _any_route(from: Vector2i, goal: Vector2) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var map := GameWorld.map
	if map == null:
		return out
	var goal_c := Hex.from_world(Vector3(goal.x, 0.0, goal.y))
	if from == goal_c or Hex.distance(from, goal_c) == 1 and map.cell_transition(from, goal_c) == HexMap.Move.OK:
		out.append(Vector3(goal.x, 0.0, goal.y))
		return out
	var path := map.find_path(from, goal_c, false)
	if path.size() < 2:
		return out
	for i in range(1, path.size()):
		out.append(Hex.to_world(path[i]))
	out[out.size() - 1] = Vector3(goal.x, 0.0, goal.y)
	return out


func _tick_chum(delta: float) -> void:
	if GameWorld.time >= _chum_until:
		_set_state(RILED if is_riled() else CALM)
		return
	if GameWorld.flat_distance(global_position, _chum_at) > 1.2:
		_steer_to(_chum_at, delta)
	else:
		_turn_to(_chum_at + Vector3(facing.z, 0.0, -facing.x), delta * 0.5)   # nosing round the kernels


# --- hits, shoves, corn ----------------------------------------------------------------------------------------------

## Any hit riles it (and makes it the bill's culprit if it dies of it).
func _on_damaged(_amount: float, source: Node) -> void:
	_flash_t = FLASH_TIME
	_update_bar()
	if source != null and is_instance_valid(source) and source != self:
		_last_by = weakref(source)
		_rile(source)


## Riled: the territory is TERRITORY_RILED for RILED_T, and (a new riling by a hit, `advance`) an advance of up to
## RILE_ADVANCE toward whoever did it. A shove riles it without the advance: its first nip goes to whoever is nearest where
## it lands (that is the play: shove it into the pack and it bites the pack).
func _rile(source: Node, advance: bool = true) -> void:
	var fresh := not is_riled()
	_riled_until = GameWorld.time + RILED_T
	var a := source as Actor   # (only an actor is advanced on: not a blast's prop or a spell node)
	if fresh and advance and a != null and is_instance_valid(a) and a != self:
		_rile_by = weakref(a)
		_advance_left = RILE_ADVANCE
	if state == CALM or state == WATCH:
		_set_state(RILED)


## A shove moves it like any body (decided 2026-10-20): it riles it, its next nip goes at once to the nearest body where
## it lands, and whoever shoved it is the culprit if it falls to its death.
func shove(dir: Vector3, distance: float, source: Node = null) -> void:
	if Net.is_copy(self):
		super.shove(dir, distance, source)   # (a request to the host)
		return
	if dead or distance <= 0.0:
		return
	if source != null and is_instance_valid(source) and source != self:
		_last_by = weakref(source)
	_rile(source, false)
	_advance_left = 0.0
	_nip_now = true
	super.shove(dir, distance, source)


func _on_interrupted() -> void:
	if state == NIP:
		_drop_nip()
		_set_state(RILED if is_riled() else WATCH)
	_nudge_t = 0.0
	_prog_t = 0.0


## The shove is over and it stands: out of its region it walks home; inside it, it settles where it landed.
func _on_shove_ended() -> void:
	if dead:
		return
	var c := Hex.from_world(global_position)
	if in_region(c):
		_settle_here(false)
		if state == CALM:
			_set_state(RILED if is_riled() else WATCH)
	else:
		_go_home()


## Corn in the water (CornStrike's slam, every machine; the gator's machine decides): chum for CHUM_T, no nips.
static func corn_at(pos: Vector3) -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree() or GameWorld.map == null:
		return
	if not GameWorld.map.water_at(pos):
		return
	for n in GameWorld.root.get_tree().get_nodes_in_group("gators"):
		var g := n as Gator
		if g == null or g.dead or not Net.simulates(g):
			continue
		if GameWorld.flat_distance(g.global_position, pos) > CHUM_RADIUS:
			continue
		g._chum(pos)


func _chum(pos: Vector3) -> void:
	_chum_until = GameWorld.time + CHUM_T
	_chum_at = pos
	if state == NIP:
		_drop_nip()
	if state != MOVE or _move_kind != "water":
		_end_move(false)
		_set_state(CHUM)


# --- death ------------------------------------------------------------------------------------------------------------

func _on_death() -> void:
	state = DEAD_STATE
	_telegraph = 0.0
	_drop_nip()
	remove_from_group(PricedProp.GROUP)
	if Net.owns(self):
		Ledger.damage(display_name, price, last_culprit())   # (online the host bills it; a client's Ledger mirrors it)
		MonsterSenses.noise(global_position, MonsterSenses.NOISE_DEATH, "death")
	if _bar != null:
		_bar.visible = false
	Fx.number(global_position + Vector3(0, 1.2, 0), "-" + PricedProp.money(price), PricedProp.MONEY_RED, 1.1)
	Sfx.play_at("gator_thrash", global_position)
	if _wake != null:
		_wake.visible = false
	if _skin != null:
		_skin.set_shader_parameter("glow_gain", 0.0)
		_skin.set_shader_parameter("tint_k", 0.0)
	var tw := create_tween()
	tw.tween_property(self, "_dead_k", 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(_v: float) -> void: _pose_dead(), 0.0, 1.0, 0.8)


## Belly up: rolled over on its side, a little sunk.
func _pose_dead() -> void:
	if body == null or not is_instance_valid(body):
		return
	body.rotation.z = PI * 0.92 * _dead_k
	body.position.y = _float_y + 0.28 * _dead_k


# --- the look ---------------------------------------------------------------------------------------------------------

## The model (MonsterDefs has no "model" row for it: Monster._ready calls this).
func _build_visual(root: Node3D) -> void:
	body = Node3D.new()
	body.name = "GatorBody"
	body.rotation.y = PI   # (the model's snout is +Z; Monster turns _visual for a -Z front)
	root.add_child(body)
	rig = GatorModel.new()
	rig.scale = Vector3.ONE * GATOR_SCALE
	body.add_child(rig)
	# the rig's one material (the eye glow by state, the wind-up pulse, the hit flash)
	_skin = rig.material
	_skin.set_shader_parameter("glow_gain", 1.0)
	_twitch_at = GameWorld.time + GameWorld.fx_rng.randf_range(2.0, 8.0)
	_wave_phase = GameWorld.fx_rng.randf()
	_build_wake()


## The gator model posed at one bend and jaw, unscaled (the z-fight registry's poses).
static func model_for(bend: float, jaw: float, pose: Dictionary = {}) -> Node3D:
	var m := GatorModel.new()
	m.set_pose(pose)
	m.bend = bend
	m.jaw = jaw
	m.apply()
	return m


## The V wake (two foam arms trailing back from the snout) and a ripple ring round the head, on the water's surface.
func _build_wake() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.0, 0.0, 1.3)
	for side: float in [-1.0, 1.0]:
		var n := 6
		for i in n:
			var t0 := float(i) / float(n)
			var t1 := float(i + 1) / float(n)
			var p0 := tip.lerp(Vector3(1.05 * side, 0.0, -2.0), t0)
			var p1 := tip.lerp(Vector3(1.05 * side, 0.0, -2.0), t1)
			var w0 := 0.05 + 0.13 * t0
			var w1 := 0.05 + 0.13 * t1
			var a0 := 0.85 * (1.0 - t0)
			var a1 := 0.85 * (1.0 - t1)
			var c0 := Color(0.92, 0.95, 0.88, a0)
			var c1 := Color(0.92, 0.95, 0.88, a1)
			var q := [p0 - Vector3(w0, 0, 0), p0 + Vector3(w0, 0, 0), p1 + Vector3(w1, 0, 0), p1 - Vector3(w1, 0, 0)]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(c0 if idx < 2 else c1)
				st.set_normal(Vector3.UP)
				st.add_vertex(q[idx])
	_wake = MeshInstance3D.new()
	_wake.name = "Wake"
	_wake.mesh = st.commit()
	_wake_mat = StandardMaterial3D.new()
	_wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wake_mat.vertex_color_use_as_albedo = true
	_wake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wake_mat.render_priority = 3
	_wake_mat.albedo_color = Color(1, 1, 1, 0.0)
	_wake.material_override = _wake_mat
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(_wake)
	_ripple = PoolProps.build("ripple", {"radius": 0.55})
	_ripple.name = "Ripple"
	body.add_child(_ripple)


func _apply_tint(color: Color, k: float) -> void:
	if _skin != null:
		_skin.set_shader_parameter("tint_color", color)
		_skin.set_shader_parameter("tint_k", k)


## The pose (Monster._update_visual calls it every frame): the rig (_pose_rig), the eye glow by state, standing up in the
## water, the wake.
func _pose(delta: float, _moving: bool) -> void:
	if body == null or dead:
		return
	var wet := in_water()
	var moved := GameWorld.flat_distance(global_position, _last_pos) / maxf(delta, 0.001)
	_last_pos = global_position
	_speed_seen = lerpf(_speed_seen, moved, clampf(6.0 * delta, 0.0, 1.0))
	_pose_rig(delta, wet)
	_sounds(wet)
	_float_y = lerpf(_float_y, WATER_LIFT if wet else 0.0, clampf(6.0 * delta, 0.0, 1.0))
	body.position.y = _float_y
	# eyes: half lit at rest, bright when it watches, hot when it nips
	var glow := 1.0
	match state:
		WATCH, RILED: glow = 2.6
		NIP: glow = 3.4
		MOVE, CHUM: glow = 1.6
	if _skin != null:
		_skin.set_shader_parameter("glow_gain", glow)
	# the wake: on the water, as strong as it is fast
	var surface := SewerLayouts.SURFACE_Y - global_position.y - _float_y + 0.012
	if _wake != null:
		_wake.visible = wet
		_wake.position = Vector3(0.0, surface, 0.0)
		_wake_mat.albedo_color = Color(1, 1, 1, clampf(0.25 + _speed_seen / WATER_SPEED, 0.25, 1.0) if wet else 0.0)
	if _ripple != null:
		_ripple.visible = wet
		_ripple.position = Vector3(0.0, surface, HEAD)
		var k := 1.0 + 0.08 * sin(GameWorld.time * 3.5)
		_ripple.scale = Vector3(k, 1.0, k)


## The rig's motion (cosmetic, LOCAL): from its turning, state, wind-up, speed and the water, the same on every machine. It
## reads only what a puppet has too (its shown position and facing, the streamed state and _telegraph, SPAWN data), never
## the host's AI state, so a client's gator swims, walks, thrashes and gapes as the host's does.
func _pose_rig(delta: float, wet: bool) -> void:
	if rig == null:
		return
	var t := GameWorld.time
	# the curl as it turns
	var yaw := atan2(facing.x, facing.z)
	var rate := wrapf(yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
	_prev_yaw = yaw
	var max_bend := BENDS[BENDS.size() - 1]
	_bend = lerpf(_bend, clampf(rad_to_deg(rate) * 0.45, -max_bend, max_bend), clampf(5.0 * delta, 0.0, 1.0))
	# swimming or walking
	_swim_k = move_toward(_swim_k, 1.0 if wet else 0.0, 3.0 * delta)
	var walking := not wet and _speed_seen > 0.25
	_walk_k = move_toward(_walk_k, 1.0 if walking else 0.0, 4.0 * delta)
	_gait = fposmod(_gait + delta * _speed_seen * GAIT_PER_UNIT, 1.0)
	# the S-wave: lazy at rest, swimming with the speed in the water, a thrash in bursts when riled
	var speed_k := clampf(_speed_seen / WATER_SPEED, 0.0, 1.0)
	var amp := 16.0
	var cycles := 0.12
	if wet:
		amp = lerpf(16.0, 32.0, speed_k)
		cycles = 0.12 + 0.5 * _speed_seen
	elif walking:
		amp = 6.0
	if state == RILED and int(t * 3.0) % 2 == 0:
		amp = 40.0
		cycles = 2.5
	_wave_amp = lerpf(_wave_amp, amp, clampf(4.0 * delta, 0.0, 1.0))
	_wave_phase = fposmod(_wave_phase + cycles * delta, 1.0)
	# the head: tracking the nearest body it watches, up when it watches, up through the wind-up, down to chum
	var want_yaw := 0.0
	var want_pitch := 1.5 * sin(t * 0.7)
	if state in [WATCH, RILED, NIP]:
		var a := _nearest_watched()
		if a != null:
			var local := rig.global_transform.affine_inverse() * a.global_position
			want_yaw = clampf(rad_to_deg(atan2(local.x, local.z)), -HEAD_TURN, HEAD_TURN)
		want_pitch = 6.0
	match state:
		NIP: want_pitch = 6.0 + 10.0 * _telegraph
		CHUM: want_pitch = -8.0
		HELD: want_pitch = -5.0
	_head_yaw = lerpf(_head_yaw, want_yaw, clampf(6.0 * delta, 0.0, 1.0))
	_head_pitch = lerpf(_head_pitch, want_pitch, clampf(6.0 * delta, 0.0, 1.0))
	# the jaws: parting through the wind-up to the gape, snapping shut; chewing on chum; an idle twitch now and then
	var want_jaw := 0.0
	if state == NIP:
		want_jaw = clampf((_telegraph - 0.15) / 0.7, 0.0, 1.0)   # (the streamed wind-up: wide open through the lunge too)
	elif state == CHUM:
		want_jaw = 0.3 * (0.5 + 0.5 * sin(t * TAU * 2.0))
	elif t >= _twitch_at:
		var tw := (t - _twitch_at) / 0.35
		if tw >= 1.0:
			_twitch_at = t + GameWorld.fx_rng.randf_range(6.0, 10.0)
		else:
			want_jaw = 0.18 * sin(PI * tw)
	_jaw_k = lerpf(_jaw_k, want_jaw, clampf((18.0 if want_jaw < _jaw_k else 10.0) * delta, 0.0, 1.0))
	rig.bend = _bend
	rig.wave = _wave_amp
	rig.phase = _wave_phase
	rig.gait = _gait
	rig.walk_k = _walk_k
	rig.swim_k = _swim_k
	rig.head_yaw = _head_yaw
	rig.head_pitch = _head_pitch
	rig.jaw = _jaw_k
	rig.breath = 0.5 + 0.5 * sin(t * TAU * (0.15 if state == HELD else 0.25) + float(spawn_seed % 97))
	rig.apply()


## Its sounds (cosmetic, LOCAL, every screen, from what a puppet shows too): the hiss as a nip's wind-up starts (its state
## turns NIP), a splash as it goes into or out of the water (at most one a second, so swimming along the edge is quiet).
## The bite and the death thrash play in _strike and _on_death.
func _sounds(wet: bool) -> void:
	var nip := state == NIP
	if nip and not _heard_nip:
		Sfx.play_at("gator_hiss", head())
	_heard_nip = nip
	var w := 1 if wet else 0
	if _heard_wet >= 0 and w != _heard_wet and GameWorld.time - _splash_t >= 1.0:
		_splash_t = GameWorld.time
		Sfx.play_at("gator_splash", global_position)
	_heard_wet = w


func net_show(new_facing: Vector3, _is_climbing: bool, new_hp: float, new_state: int, telegraph: float, strike_count: int) -> void:
	facing = new_facing
	if absf(new_hp - hp) > 0.05:
		if new_hp < hp:
			_flash_t = FLASH_TIME
		hp = new_hp
		_update_bar()
	state = new_state
	_telegraph = telegraph
	if strike_count != strikes:
		strikes = strike_count
		_strike_t = 1.0

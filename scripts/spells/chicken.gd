class_name Chicken
extends Actor
## The Chicken spell's bird (docs/design/spells.md, "Chicken"; decided by the user 2026-10-18): "chickens run around and do
## zero damage attacks to everything, distracting them". One cast makes FLOCK of them, scattering from the aim point. Each
## runs about erratically, pecks whatever is near (a monster within PREFER_RADIUS first, else anything within ANY_RADIUS:
## heroes, employees, props, mail, gates) for NOTHING, flaps off after every peck and comes back for more. After LIFETIME
## it puffs up and poofs into feathers, if nothing killed it first.
##
## A PECK is a hit for zero (Combat.peck -> Actor.peck): no damage, no stagger, no shove, no Ledger line, no break, no
## panic. A pecked MONSTER turns on the chicken (Monster._on_pecked: it beats the monster's hero target for
## Monster.TAUNT_TIME, each peck restarting it, or until the chicken dies), so the chicken pulls it off the crew and, being
## fragile, is usually killed for it: the distraction ends on its own. Anything else just gets the "0" and a feather puff.
##
## FRAGILE: any hit takes at least HIT_FLOOR (half its HP), so one or two hits from anything kill it: a monster's swing
## (Monster._strike_neutral), an arrow, a fireball, corn, teeth, a fire, a wall slam, and the crew's own swings and bolts
## (GameWorld.hittable_in_radius: WEAPONS_HIT). It dies in a feather explosion.
##
## NETWORKING (networking.md shape "owned actor", host-owned like a monster): the cast is an event that lands on every
## machine (NetCasts, SpellBook.apply); only the host spawns the flock (ChickenSpell.cast) and runs its AI, with its
## rolls on GameWorld.rng. It is NetWorld's first RUNTIME ACTOR (NetWorldCodec.RUNTIME_ACTORS): streamed like a monster (a
## MONSTER-format entry, net_read / net_write: state, the peck wind-up, the peck count), announced the spawn (`world.spawn`, kind "chicken") and the death (`world.die`);
## on a client it is a puppet (net_show / net_tick) that plays the same pecks, feathers and poof. A client's hit on it is a
## request the host applies (Net.route_hit). A late joiner gets it as a runtime spawn plus the keyframe (NetEvents.LATE_JOIN).
##
## CLUCKS (cosmetic, every screen from the chicken it shows; audio-plan.md "War cries"): one as it lands (CLUCK_LAND after it
## appears, so a flock's four are staggered), one on every peck (the host's, and a puppet's when its peck count moves), and
## now and then by itself (every CLUCK_IDLE_MIN..CLUCK_IDLE_MAX s, rolled on GameWorld.fx_rng). The "chicken_cluck" cue's
## voices and gap cap a whole flock, so four pecking stay a few clucks. None while it poofs.

enum State { WANDER, RUN, PECK, FLAP, POOF }

const GROUP := "chickens"
const FLOCK := 4                  ## chickens per cast
const LIFETIME := 12.0            ## seconds, then it poofs
const POOF_TIME := 0.35           ## it puffs up this long before it poofs
const MAX_HP := 20.0
const HIT_FLOOR := 10.0           ## every hit takes at least this: one or two hits kill a chicken
const SPEED := 3.6                ## a grunt walks 3.2, an imp 5.5, a hero 4.5
const RADIUS := 0.28
const SCATTER_TIME := 0.6         ## the burst out of the cast cloud ...
const SCATTER_SPEED := 1.5        ## ... at this times SPEED
const SCAN_EVERY := 0.3           ## looks for something to peck this often
const PREFER_RADIUS := 4.5        ## a monster this close is pecked first ...
const ANY_RADIUS := 2.5           ## ... else anything this close
const PECK_REACH := 0.45          ## beak reach beyond both bodies
const PECK_WINDUP := 0.22         ## the head pulls back this long, then the peck
const PECK_COOLDOWN := 0.9        ## seconds between one chicken's pecks
const FLAP_TIME := 0.45           ## after a hit it flaps off this long; after a peck a hop of PECK_HOP_MIN..FLAP_TIME (a short
const PECK_HOP_MIN := 0.15        ## hop keeps it in reach, so a slow monster gets its swing in too) ...
const FLAP_SPEED := 1.4           ## ... at this times SPEED, then comes back for more
const CHASE_GIVE_UP := 4.0        ## a target it has not reached in this long is dropped
const LEASH := 5.5                ## it wanders back toward where it was cast when it strays further
const TURN_MIN := 0.25            ## erratic: a new heading every TURN_MIN..TURN_MAX seconds
const TURN_MAX := 0.7
const PAUSE_CHANCE := 0.22        ## ... and now and then a short stop (a scratch at the floor)
## The crew's swings and shots hit chickens too (true), or only the monsters' do (false). GameWorld.hittable_in_radius.
const WEAPONS_HIT := true
const BAWK := Color(1.0, 0.93, 0.78)
const CLUCK_CUE := "chicken_cluck"
const CLUCK_LAND := Vector2(0.05, 0.45)   ## its landing cluck, this long (s, a random span) after it appears
const CLUCK_IDLE_MIN := 2.0               ## then a cluck every CLUCK_IDLE_MIN..CLUCK_IDLE_MAX s (a peck starts the wait over)
const CLUCK_IDLE_MAX := 5.0

var state: int = State.WANDER
## Pecks so far (the other screens play a peck when it moves on: NetWorldCodec, like a monster's strikes).
var pecks := 0
## 0..1 through the peck's wind-up (the head pulled back), streamed so the other screens pose it.
var _peck_t := 0.0

# The host's AI (PRIVATE): where it was cast, its burst direction, its clock and its working state.
var home := Vector3.INF
var scatter_dir := Vector3.ZERO
var born := 0.0
var _started := false
var _target: Actor = null
var _state_t := 0.0
var _scan_t := 0.0
var _next_peck := 0.0
var _heading := Vector3.ZERO
var _turn_t := 0.0
var _pause_t := 0.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _flap_len := FLAP_TIME

# Presentation (LOCAL).
var model: ChickenModel = null
var _visual: Node3D = null
var _poof_k := 0.0
var _shown := false               ## a puppet has applied its first sample (a late joiner's first peck count is not a peck)
var clucks := 0                   ## clucks this screen played or tried (Sfx may drop one to its cap; tests)
var _cluck_t := 0.0               ## seconds to its next cluck by itself (the first: the landing cluck)


## The flock (the host, or solo): FLOCK chickens around `at`, each bursting out its own way. Rolls on GameWorld.rng (only
## the machine that runs chickens spawns them). Returns them.
static func flock(at: Vector3) -> Array[Chicken]:
	var out: Array[Chicken] = []
	if GameWorld.root == null:
		return out
	var base := GameWorld.rng.randf() * TAU
	for i in FLOCK:
		var a := base + TAU * float(i) / float(FLOCK) + GameWorld.rng.randf_range(-0.35, 0.35)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var c := Chicken.new()
		c.home = at
		c.scatter_dir = dir
		c.born = GameWorld.time
		GameWorld.spawn(c, _spot(at, at + dir * 0.35))
		out.append(c)
	return out


## A chicken another machine runs (a client's puppet of the host's, NetWorld): no AI is ever started for it here.
static func make_shown(at: Vector3) -> Chicken:
	var c := Chicken.new()
	c.home = at
	GameWorld.spawn(c, at)
	return c


static func _spot(center: Vector3, p: Vector3) -> Vector3:
	var map := GameWorld.map
	if map == null:
		return p
	if map.blocks_point(p, RADIUS) or is_nan(map.ground_height(p)):
		p = center
	var g := map.ground_height(p)
	if not is_nan(g):
		p.y = g
	return p


func _init() -> void:
	team = GameWorld.TEAM_NEUTRAL
	max_hp = MAX_HP
	move_speed = SPEED
	radius = RADIUS
	shove_mult = 1.6        # light: tentacles and swings throw it about
	display_name = "Chicken"


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	model = ChickenModel.new()
	_visual.add_child(model)
	Fx.attach_hit_feedback(self)   # (a hit shows its number and the flash, like any actor's)
	damaged.connect(_on_hurt)
	_scan_t = GameWorld.fx_rng.randf() * SCAN_EVERY   # (re-rolled on the host's first frame; a puppet never scans)
	_cluck_t = GameWorld.fx_rng.randf_range(CLUCK_LAND.x, CLUCK_LAND.y)


## Who may write each var (see Net). The host runs chickens: what the other screens draw (the state, the peck's wind-up,
## the peck count) is OWNER and rides the world stream; the AI's working state is PRIVATE; the model is LOCAL.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"state": Net.OWNER, "pecks": Net.OWNER, "_peck_t": Net.OWNER,
		"home": Net.PRIVATE, "scatter_dir": Net.PRIVATE, "born": Net.PRIVATE, "_started": Net.PRIVATE,
		"_target": Net.PRIVATE, "_state_t": Net.PRIVATE, "_scan_t": Net.PRIVATE, "_next_peck": Net.PRIVATE,
		"_heading": Net.PRIVATE, "_turn_t": Net.PRIVATE, "_pause_t": Net.PRIVATE, "_stuck_t": Net.PRIVATE,
		"_stuck_pos": Net.PRIVATE, "_flap_len": Net.PRIVATE,
		"model": Net.LOCAL, "_visual": Net.LOCAL, "_poof_k": Net.LOCAL, "_shown": Net.LOCAL,
		"clucks": Net.LOCAL, "_cluck_t": Net.LOCAL,
	})
	return f


## Seconds it has been running (the host's clock).
func age() -> float:
	return GameWorld.time - born


# --- Fragile ---------------------------------------------------------------------------------------------

## Every hit takes at least HIT_FLOOR (after armor), so one or two hits from anything kill it.
func apply_damage(amount: float, source: Node = null) -> float:
	if amount > 0.0 and not dead and not Net.is_copy(self):
		amount = maxf(amount, HIT_FLOOR / maxf(damage_taken_mult(), 0.01))
	return super(amount, source)


## A hit it survived: it flaps off away from whatever did it (host).
func _on_hurt(_amount: float, source: Node) -> void:
	if dead or state == State.POOF or not Net.owns(self):
		return
	var away := Vector3.ZERO
	var s := source as Node3D
	if s != null and is_instance_valid(s):
		away = global_position - s.global_position
		away.y = 0.0
	if away.length() < 0.05:
		var a := GameWorld.rng.randf() * TAU
		away = Vector3(cos(a), 0.0, sin(a))
	_flap(away.normalized())


func _on_death() -> void:
	var at := global_position
	if _poof_k > 0.0 or state == State.POOF:
		ChickenFx.poof(at)
	else:
		ChickenFx.feather_explosion(at)
	queue_free()


# --- The host's AI ------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not _started:
		_started = true
		snap_to_ground()
		if home == Vector3.INF:
			home = global_position
		_scan_t = GameWorld.rng.randf() * SCAN_EVERY
		if scatter_dir != Vector3.ZERO:
			_flap(scatter_dir, SCATTER_TIME)   # the burst out of the cloud is a flap away from the aim point
	if state != State.POOF and age() >= LIFETIME:
		_enter(State.POOF)
	if is_helpless() and state != State.POOF:
		_look(delta)
		return
	_state_t += delta
	match state:
		State.WANDER:
			_tick_wander(delta)
		State.RUN:
			_tick_run(delta)
		State.PECK:
			_tick_peck(delta)
		State.FLAP:
			_tick_flap(delta)
		State.POOF:
			_poof_k = clampf(_state_t / POOF_TIME, 0.0, 1.0)
			if _state_t >= POOF_TIME:
				die()
				return
	_look(delta)


func _enter(s: int) -> void:
	state = s
	_state_t = 0.0
	if s != State.PECK:
		_peck_t = 0.0
	if s == State.POOF:
		_target = null


func _tick_wander(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		var t := pick_target()
		if t != null:
			_target = t
			_enter(State.RUN)
			return
	if _pause_t > 0.0:
		_pause_t -= delta
		return
	_turn_t -= delta
	if _turn_t <= 0.0 or _heading == Vector3.ZERO:
		_new_heading()
		if GameWorld.rng.randf() < PAUSE_CHANCE:
			_pause_t = GameWorld.rng.randf_range(0.2, 0.5)
			return
	if not move(_heading * 0.85, delta):
		_turn_t = 0.0   # a wall: another way next frame


func _new_heading() -> void:
	_turn_t = GameWorld.rng.randf_range(TURN_MIN, TURN_MAX)
	var to_home := home - global_position
	to_home.y = 0.0
	if to_home.length() > LEASH:
		_heading = to_home.normalized().rotated(Vector3.UP, GameWorld.rng.randf_range(-0.7, 0.7))
	else:
		var a := GameWorld.rng.randf() * TAU
		_heading = Vector3(cos(a), 0.0, sin(a))


func _tick_run(delta: float) -> void:
	if not _valid(_target) or _state_t > CHASE_GIVE_UP:
		_target = null
		_enter(State.WANDER)
		return
	var to := _target.global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > PREFER_RADIUS + 2.0:
		_target = null
		_enter(State.WANDER)
		return
	if d <= reach_to(_target):
		face_point(_target.global_position)
		if GameWorld.time >= _next_peck:
			_enter(State.PECK)
		return
	# Run at it, wobbling (a chicken never runs straight).
	var dir := to / maxf(d, 0.001)
	dir = dir.rotated(Vector3.UP, sin(age() * 11.0 + float(get_instance_id() % 7)) * 0.4)
	var before := global_position
	move(dir, delta)
	if GameWorld.flat_distance(before, global_position) < 0.002:
		_stuck_t += delta
		if _stuck_t > 0.6:
			_stuck_t = 0.0
			_target = null
			_enter(State.WANDER)
	else:
		_stuck_t = 0.0


func _tick_peck(_delta: float) -> void:
	if _valid(_target):
		face_point(_target.global_position)
	_peck_t = clampf(_state_t / PECK_WINDUP, 0.0, 1.0)
	if _state_t < PECK_WINDUP:
		return
	_peck_t = 0.0
	pecks += 1
	var victim: Actor = null
	if _valid(_target) and GameWorld.flat_distance(global_position, _target.global_position) <= reach_to(_target) + 0.3:
		victim = _target
		Combat.peck(self, victim)   # (a zero hit through the verb: a monster turns on us, everything else shrugs)
	ChickenFx.peck(self, victim)
	cluck()
	_next_peck = GameWorld.time + scaled_cooldown(PECK_COOLDOWN) * GameWorld.rng.randf_range(0.85, 1.2)
	var away := global_position - (_target.global_position if _valid(_target) else global_position + facing)
	away.y = 0.0
	var hop := GameWorld.rng.randf_range(PECK_HOP_MIN, FLAP_TIME)
	_flap(away.normalized().rotated(Vector3.UP, GameWorld.rng.randf_range(-0.9, 0.9)) if away.length() > 0.01 else -facing, hop)


func _flap(dir: Vector3, length: float = FLAP_TIME) -> void:
	_heading = dir
	_flap_len = length
	_enter(State.FLAP)


func _tick_flap(delta: float) -> void:
	var k := SCATTER_SPEED if age() < SCATTER_TIME else FLAP_SPEED
	if not move(_heading * k, delta):
		_heading = _heading.rotated(Vector3.UP, PI * 0.5 * (1.0 if GameWorld.rng.randf() < 0.5 else -1.0))
	if _state_t < _flap_len:
		return
	if _valid(_target):
		_enter(State.RUN)   # back for another go
	else:
		_target = null
		_enter(State.WANDER)


## What a chicken pecks (host): the nearest monster within PREFER_RADIUS (one that can be distracted: group "monsters", so
## not a hellgate), else the nearest anything within ANY_RADIUS (another chicken aside), on about its own level. Null when
## there is nothing.
func pick_target() -> Actor:
	var best: Actor = null
	var best_d := INF
	for a in GameWorld.actors_in_radius(global_position, PREFER_RADIUS, GameWorld.TEAM_MONSTERS):
		var d := GameWorld.flat_distance(global_position, a.global_position)
		if d < best_d and a.is_in_group("monsters") and _level_with(a):
			best = a
			best_d = d
	if best != null:
		return best
	for a in GameWorld.actors_in_radius(global_position, ANY_RADIUS):
		if a == self or a.is_in_group(GROUP):
			continue
		var d := GameWorld.flat_distance(global_position, a.global_position)
		if d < best_d and _level_with(a):
			best = a
			best_d = d
	return best


## How close it has to be to peck `a` (centre to centre).
func reach_to(a: Actor) -> float:
	return radius + a.radius + PECK_REACH


func _level_with(a: Actor) -> bool:
	return absf(a.global_position.y - global_position.y) <= 2.1 * Hex.LEVEL_HEIGHT


func _valid(a: Actor) -> bool:
	return a != null and is_instance_valid(a) and not a.dead and a.is_inside_tree()


# --- Look (every screen) ------------------------------------------------------------------------------------

func _look(delta: float) -> void:
	_tick_cluck(delta)
	if _visual == null:
		return
	var yaw := atan2(-facing.x, -facing.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, clampf(18.0 * delta, 0.0, 1.0))
	if model == null:
		return
	model.set_peck(_peck_t)
	model.set_flap(state == State.FLAP or state == State.POOF)
	model.set_swell(_poof_k)


## A cluck (the "chicken_cluck" pool at the chicken): its landing, a peck, or now and then. Cosmetic, this screen only;
## the next one by itself waits CLUCK_IDLE_MIN..CLUCK_IDLE_MAX again. None once it is dead or poofing.
func cluck() -> void:
	if dead or state == State.POOF:
		return
	clucks += 1
	_cluck_t = GameWorld.fx_rng.randf_range(CLUCK_IDLE_MIN, CLUCK_IDLE_MAX)
	Sfx.play_at(CLUCK_CUE, global_position)


func _tick_cluck(delta: float) -> void:
	_cluck_t -= delta
	if _cluck_t <= 0.0:
		cluck()
		_cluck_t = maxf(_cluck_t, CLUCK_IDLE_MIN)   # (dead or poofing: no cluck, and no retry every frame)


# --- Puppet (a client shows the host's chicken) ------------------------------------------------------------------

## Show the host's state (net_write) and play what changed: a new peck pecks (the "0" and the feathers
## land on whatever this screen shows it pecking), an HP drop flashes, the poof swells.
func net_show(new_facing: Vector3, is_climbing: bool, new_hp: float, new_state: int, peck_t: float, peck_count: int) -> void:
	facing = new_facing
	climbing = is_climbing
	if new_hp < hp - 0.05:
		Fx.flash(self)
	hp = new_hp
	if new_state != state:
		state = new_state
		_state_t = 0.0
	_peck_t = peck_t if state == State.PECK else 0.0
	if peck_count != (pecks & 255):
		pecks = peck_count
		if _shown:
			ChickenFx.peck(self, _shown_victim())
			cluck()
	_shown = true


## Host (a runtime actor, NetWorldCodec.RUNTIME_ACTORS): its own slots of the monster-format entry (the codec fills the
## position, HP, facing, climbing and helpless): its state, the peck's wind-up and its pecks.
func net_read(st: NetHeroState) -> void:
	st.mode = state
	st.telegraph = _peck_t
	st.extra = pecks & 255


## A puppet: show an (interpolated) state (the codec has placed it); net_show plays a new peck, a hit, the poof.
func net_write(st: NetHeroState) -> void:
	net_show(st.facing_vector(), st.climbing, st.hp, st.mode, st.telegraph, st.extra)


## A puppet's look each frame (on the host the physics process does it).
func net_tick(delta: float) -> void:
	if dead:
		return
	if state == State.POOF:
		_state_t += delta
		_poof_k = clampf(_state_t / POOF_TIME, 0.0, 1.0)
	_look(delta)


## A puppet (M4): this machine's player hit it (the hit is on its way to the host): flash now.
func net_flash() -> void:
	Fx.flash(self)


## What this screen shows the chicken pecking (cosmetic: the actor in front of its beak), or null.
func _shown_victim() -> Actor:
	var best: Actor = null
	var best_d := INF
	var beak := global_position + facing * (radius + PECK_REACH * 0.5)
	for a in GameWorld.actors_in_radius(beak, PECK_REACH + 0.4):
		if a == self or a.is_in_group(GROUP):
			continue
		var d := GameWorld.flat_distance(beak, a.global_position) - a.radius
		if d < best_d:
			best = a
			best_d = d
	return best

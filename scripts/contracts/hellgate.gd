class_name Hellgate
extends Actor
## A hellgate: a demonic portal set into the floor that pumps out monsters until the crew closes it
## (kills it). Team MONSTERS, so every hero attack and spell damages it like any monster. It is a
## spawner, not a fighter: it never walks or attacks and cannot be shoved (shove_mult 0).
## Design: docs/design/contracts.md. Interfaces: docs/contracts-build.md. Look: HellgateModel.
##
##   var gate := Hellgate.spawn(cell, {"difficulty": 0.6, "depth": 2, "pest": "swarmer"})
##   gate.closed.connect(func(g: Actor) -> void: ...)               # fires once, when it dies
##   HellgateEvents.hub().origin_closed.connect(...)                # the floor-3 gate (see HellgateEvents)
##
## SPAWNING. Dormant until a hero first comes within ACTIVATE_RANGE (12) of the gate, or the gate takes
## damage (a ranged opener counts). That rule is deliberate: a crew arriving on a floor is never flooded
## by gates it has not even seen yet, and a gate left alone far away never builds pressure out of sight.
## Once active it stays active. It then fires a burst every `spawn_interval` seconds: a flare on the gate
## first (TELEGRAPH_TIME), then `burst_size` monsters on free walkable cells in a ring around it, each
## aggroed toward the nearest hero. At `spawn_cap` living spawns it holds fire and tops up as soon as
## spawns die (a gate that is ignored builds up to the cap and no further).
##
## SCALING. pressure p = P_DIFFICULTY * difficulty + P_DEPTH * (depth - 1) / 2, in 0..1. Interval,
## burst size and cap are lerped on p between the EASY and HARD ends of the table below, so the spawn
## rate rises monotonically with both difficulty and depth.
##
## ORIGIN GATE (opts.origin): double size, ORIGIN_HP_MULT x the HP, a faster base rate and, by HP, three
## phases (>66%, <=66%, <=33%). Every phase spawns faster with bigger bursts and a higher cap, and every
## phase CHANGE winds up for SHOVE_WINDUP seconds (a red ring grows on the floor) and then shoves every hero
## and neutral inside SHOVE_RADIUS away with Combat.shove_radius, with a flare. Closing it stops every
## gate's spawns site-wide (HellgateEvents.stop_spawns, also Hellgate.close_all_spawns()).
##
## CLOSING. hp 0 means closed: the actor dies at once (so it leaves the target lists and the objective
## counts immediately), `closed(gate)` and HellgateEvents.gate_closed fire exactly once, the collapse
## animation plays for CLOSE_TIME and the node frees itself.

signal closed(gate: Actor)
## First time the gate woke up (a hero came near or it was hit).
signal activated
## A burst flare started: the burst follows after `delay` seconds.
signal burst_telegraphed(delay: float)
## A burst landed: the monsters it spawned.
signal burst_spawned(monsters: Array)
## Origin gate only: the HP phase went up (1, then 2).
signal phase_changed(phase: int)
## Origin gate only: the defensive shove is winding up; it fires after `delay` seconds.
signal shove_telegraphed(radius: float, delay: float)
## Origin gate only: the shove went off.
signal shove_burst(radius: float)

# ============================ TUNING TABLE (every number lives here) ============================
# Activation
const ACTIVATE_RANGE := 12.0      ## a hero this close wakes the gate (flat distance)
const SCAN_INTERVAL := 0.25       ## seconds between hero scans while dormant
# Pressure p (0..1) = P_DIFFICULTY * difficulty + P_DEPTH * (depth - 1) / 2
const P_DIFFICULTY := 0.65
const P_DEPTH := 0.35
# Spawn rate: lerped from the EASY value (p = 0) to the HARD value (p = 1)
const INTERVAL_EASY := 14.0       ## seconds between bursts
const INTERVAL_HARD := 4.5
const BURST_EASY := 1.0           ## monsters per burst
const BURST_HARD := 4.0
const CAP_EASY := 3.0             ## max living spawns per gate
const CAP_HARD := 12.0
const HP_EASY := 160.0            ## gate hit points
const HP_HARD := 260.0
# Burst timing
const TELEGRAPH_TIME := 1.0       ## flare before each burst
const FIRST_DELAY_FRAC := 0.35    ## first burst comes this fraction of the interval after waking (min TELEGRAPH_TIME + 0.4)
const CAP_RETRY := 2.0            ## at the cap: look again after this many seconds
# Where spawns appear (hex distance from the gate cell)
const RING_MIN := 2
const RING_MAX := 3
const RING_MIN_ORIGIN := 3
const RING_MAX_ORIGIN := 4
const MAX_LEVEL_DIFF := 1         ## spawn cells may differ by this many levels from the gate's cell
const CELL_CLEAR := 0.8           ## a spawn cell must have no actor within this distance
# Body
const RADIUS := 1.5               ## hit radius (heroes cannot stand inside it)
const RADIUS_ORIGIN := 3.0
# Origin gate
const ORIGIN_HP_MULT := 3.0
const ORIGIN_INTERVAL_MULT := 0.85
const ORIGIN_BURST_BONUS := 1.0
const ORIGIN_CAP_BONUS := 3.0
const PHASE_THRESHOLDS: Array[float] = [0.66, 0.33]    ## hp fraction at or below which phase 1, 2 begin
const PHASE_INTERVAL_MULT: Array[float] = [1.0, 0.7, 0.5]
const PHASE_BURST_BONUS: Array[float] = [0.0, 1.0, 2.0]
const PHASE_CAP_BONUS: Array[float] = [0.0, 2.0, 4.0]
const SHOVE_WINDUP := 0.9         ## telegraph before the phase-change shove
const SHOVE_RADIUS := 5.5
const SHOVE_DISTANCE := 3.5
# Kind mix (relative weights). Pressure shifts it a little; the phase adds brutes.
const WEIGHT_SWARMER := 5.0
const WEIGHT_GRUNT := 4.0
const WEIGHT_ARCHER := 2.0
const WEIGHT_BRUTE := 0.5
const WEIGHT_ARCHER_PER_P := 1.0
const WEIGHT_BRUTE_PER_P := 1.5
const WEIGHT_BRUTE_PER_PHASE := 0.8
const WEIGHT_SWARMER_PER_P := -1.0
# Closing
const CLOSE_TIME := 1.4           ## collapse animation length before the node frees itself
# ================================================================================================

const GROUP := "hellgates"
const BAR_SHADER_PATH := "res://scripts/monsters/hp_bar.gdshader"
const ORIGIN_NAME := "Origin Gate"

var difficulty := 0.5
var depth := 1
var origin := false
var pest := ""                    ## "" = mixed, else a monster kind
var phase := 0                    ## origin gate: 0, 1 or 2
var spawn_interval := INTERVAL_EASY
var burst_size := 1
var spawn_cap := 3
## Spawn effects (embers at the spawn cells). Tests that spawn hundreds of monsters switch it off.
var fx_enabled := true

var spawned_total := 0            ## monsters this gate has ever spawned
var model: HellgateModel = null

var _active := false
var _telegraphing := false
var _next_burst_in := 0.0
var _scan_t := 0.0
var _shove_t := -1.0
var _spawns: Array[Monster] = []
var _rng := RandomNumberGenerator.new()
var _bar: MeshInstance3D = null
var _bar_mat: ShaderMaterial = null
var _bar_width := 1.6
var _bar_height := 3.4


## Make a gate standing on `cell`. opts: difficulty 0..1, depth 1..3, origin bool, pest "" or a monster
## kind, max_hp optional override. Null without a world.
static func spawn(cell: Vector2i, opts: Dictionary = {}) -> Hellgate:
	if GameWorld.root == null:
		push_warning("Hellgate.spawn: no world")
		return null
	var g := Hellgate.new()
	g.configure(opts)
	g.name = ORIGIN_NAME.replace(" ", "") if g.origin else "Hellgate"
	var level := 0.0
	var map := GameWorld.map
	if map != null:
		var l := map.ground_level(Hex.to_world(cell))
		if not is_nan(l):
			level = l
	g._rng.seed = hash(Vector3i(cell.x, cell.y, g.depth * 7 + (1 if g.origin else 0)))
	GameWorld.spawn(g, Hex.to_world(cell, level))
	return g


## Pressure 0..1 from the contract difficulty (0..1) and the floor depth (1..3).
static func pressure(difficulty_value: float, depth_value: int) -> float:
	var d := clampf(difficulty_value, 0.0, 1.0)
	var f := clampf(float(depth_value - 1) / 2.0, 0.0, 1.0)
	return clampf(P_DIFFICULTY * d + P_DEPTH * f, 0.0, 1.0)


## The spawn numbers a gate with these settings uses: {pressure, interval, burst, cap, rate (monsters
## per second), hp}. `phase_value` only matters for the origin gate. Job boards can show it as "danger".
static func profile(difficulty_value: float, depth_value: int, is_origin: bool = false, phase_value: int = 0) -> Dictionary:
	var p := pressure(difficulty_value, depth_value)
	var interval := lerpf(INTERVAL_EASY, INTERVAL_HARD, p)
	var burst := lerpf(BURST_EASY, BURST_HARD, p)
	var cap := lerpf(CAP_EASY, CAP_HARD, p)
	var hp := lerpf(HP_EASY, HP_HARD, p)
	if is_origin:
		var ph := clampi(phase_value, 0, PHASE_INTERVAL_MULT.size() - 1)
		interval *= ORIGIN_INTERVAL_MULT * PHASE_INTERVAL_MULT[ph]
		burst += ORIGIN_BURST_BONUS + PHASE_BURST_BONUS[ph]
		cap += ORIGIN_CAP_BONUS + PHASE_CAP_BONUS[ph]
		hp *= ORIGIN_HP_MULT
	var n := maxi(1, roundi(burst))
	return {"pressure": p, "interval": interval, "burst": n, "cap": maxi(1, roundi(cap)),
			"rate": float(n) / interval, "hp": hp}


## Relative kind weights {kind: weight} at pressure p and origin phase.
static func kind_weights(p: float, phase_value: int = 0) -> Dictionary:
	return {
		"swarmer": maxf(0.5, WEIGHT_SWARMER + WEIGHT_SWARMER_PER_P * p),
		"grunt": WEIGHT_GRUNT,
		"archer": WEIGHT_ARCHER + WEIGHT_ARCHER_PER_P * p,
		"brute": WEIGHT_BRUTE + WEIGHT_BRUTE_PER_P * p + WEIGHT_BRUTE_PER_PHASE * float(phase_value),
	}


## Stop every gate's spawns in the current world (what closing the origin gate does).
static func close_all_spawns() -> void:
	HellgateEvents.stop_spawns()


static func spawns_stopped() -> bool:
	return HellgateEvents.spawns_are_stopped()


## Clear the "spawns stopped" flag (see HellgateEvents; a new root clears it by itself).
static func reset_spawn_state() -> void:
	HellgateEvents.reset()


## Gates that are still open (not yet closed) in the current world.
static func open_gates() -> Array[Hellgate]:
	var out: Array[Hellgate] = []
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return out
	for n in GameWorld.root.get_tree().get_nodes_in_group(GROUP):
		var g := n as Hellgate
		if g != null and not g.dead:
			out.append(g)
	return out


## Apply spawn() options. Called before the gate enters the tree.
func configure(opts: Dictionary) -> void:
	difficulty = clampf(float(opts.get("difficulty", 0.5)), 0.0, 1.0)
	depth = clampi(int(opts.get("depth", 1)), 1, 3)
	origin = bool(opts.get("origin", false))
	pest = str(opts.get("pest", ""))
	var prof := profile(difficulty, depth, origin, 0)
	max_hp = float(opts["max_hp"]) if opts.has("max_hp") else float(prof["hp"])
	hp = max_hp
	team = GameWorld.TEAM_MONSTERS
	shove_mult = 0.0
	radius = RADIUS_ORIGIN if origin else RADIUS
	display_name = ORIGIN_NAME if origin else "Hellgate"
	move_speed = 0.0
	_apply_profile()


func _init() -> void:
	team = GameWorld.TEAM_MONSTERS
	shove_mult = 0.0
	display_name = "Hellgate"
	move_speed = 0.0
	radius = RADIUS


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	model = HellgateModel.make(origin)
	add_child(model)
	_bar_width = 3.0 if origin else 1.6
	_bar_height = model.ui_height + 0.35
	damaged.connect(_on_damaged)
	_scan_t = _rng.randf() * SCAN_INTERVAL
	_update_bar()


## Who may write each var (see Net); Actor's come from super(). The host runs the spawner.
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		# Set by spawn() / configure() from the site plan.
		"difficulty": Net.SPAWN, "depth": Net.SPAWN, "origin": Net.SPAWN, "pest": Net.SPAWN,
		# What other screens draw: awake, the burst flare, the origin phase and shove windup.
		"phase": Net.OWNER, "_active": Net.OWNER, "_telegraphing": Net.OWNER,
		"_next_burst_in": Net.OWNER,    # the flare brightness is computed from it
		"_shove_t": Net.OWNER,
		# Only the host spawns bursts. spawn_interval/burst_size/spawn_cap are rebuilt from phase.
		"spawn_interval": Net.PRIVATE, "burst_size": Net.PRIVATE, "spawn_cap": Net.PRIVATE,
		"spawned_total": Net.PRIVATE, "_scan_t": Net.PRIVATE, "_spawns": Net.PRIVATE,
		"_rng": Net.PRIVATE,
		"fx_enabled": Net.LOCAL, "model": Net.LOCAL, "_bar": Net.LOCAL, "_bar_mat": Net.LOCAL,
		"_bar_width": Net.LOCAL, "_bar_height": Net.LOCAL,
	})
	return f


# --- Public state -----------------------------------------------------------------------------

func is_active() -> bool:
	return _active


func is_origin() -> bool:
	return origin


## Living monsters this gate spawned.
func living_spawns() -> Array[Monster]:
	_prune()
	return _spawns.duplicate()


func living_spawn_count() -> int:
	_prune()
	return _spawns.size()


## True between the flare starting and the burst landing.
func is_telegraphing() -> bool:
	return _telegraphing


## Seconds until the next burst lands (only meaningful while active).
func time_to_burst() -> float:
	return _next_burst_in


## Wake the gate (a hero came near, or it was hit). Idempotent.
func activate() -> void:
	if _active or dead:
		return
	_active = true
	_next_burst_in = maxf(TELEGRAPH_TIME + 0.4, spawn_interval * FIRST_DELAY_FRAC)
	if model != null:
		model.set_active(true)
		model.pulse(1.0)
	_update_bar()
	activated.emit()


## Spawn one burst right now, ignoring the timers and the activation rule (the lab and tests).
## Honours the cap and the site-wide stop. Returns the spawned monsters.
func spawn_burst_now() -> Array[Monster]:
	return _do_burst()


# --- Simulation ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	step(delta)


## Advance the spawner by `delta` seconds. _physics_process calls it; tests may drive it directly
## (after set_physics_process(false)) to simulate minutes in a blink.
func step(delta: float) -> void:
	if dead:
		return
	if _shove_t >= 0.0:
		_shove_t -= delta
		if _shove_t < 0.0:
			_fire_shove()
	if not _active:
		_scan_t -= delta
		if _scan_t <= 0.0:
			_scan_t = SCAN_INTERVAL
			if _hero_in_range():
				activate()
		return
	if HellgateEvents.spawns_are_stopped():
		_set_telegraph(false)
		return
	_next_burst_in -= delta
	if not _telegraphing and _next_burst_in <= TELEGRAPH_TIME:
		if _room() > 0:
			_set_telegraph(true)
			burst_telegraphed.emit(maxf(_next_burst_in, 0.0))
		else:
			_next_burst_in = TELEGRAPH_TIME + CAP_RETRY
	if _next_burst_in <= 0.0:
		_do_burst()
		_set_telegraph(false)
		_next_burst_in = spawn_interval


func _process(_delta: float) -> void:
	if model == null or dead:
		return
	var k := 0.0
	if _telegraphing:
		k = 1.0 - clampf(_next_burst_in / TELEGRAPH_TIME, 0.0, 1.0)
	model.set_flare(k)


func _hero_in_range() -> bool:
	for h in GameWorld.team_actors(GameWorld.TEAM_HEROES):
		if GameWorld.flat_distance(h.global_position, global_position) <= ACTIVATE_RANGE:
			return true
	return false


func _apply_profile() -> void:
	var prof := profile(difficulty, depth, origin, phase)
	spawn_interval = float(prof["interval"])
	burst_size = int(prof["burst"])
	spawn_cap = int(prof["cap"])


func _set_telegraph(on: bool) -> void:
	_telegraphing = on


func _prune() -> void:
	var keep: Array[Monster] = []
	for m in _spawns:
		if is_instance_valid(m) and not m.dead:
			keep.append(m)
	_spawns = keep


func _room() -> int:
	_prune()
	return maxi(0, spawn_cap - _spawns.size())


func _do_burst() -> Array[Monster]:
	var out: Array[Monster] = []
	if dead or GameWorld.root == null or HellgateEvents.spawns_are_stopped():
		return out
	var n := mini(burst_size, _room())
	if n <= 0:
		return out
	var cells := _spawn_cells(n)
	var p := pressure(difficulty, depth)
	var weights := kind_weights(p, phase)
	for c in cells:
		var kind := pest if pest != "" and MonsterFactory.SCRIPTS.has(pest) else _pick_kind(weights)
		var m := MonsterFactory.spawn(kind, c)
		if m == null:
			continue
		m.set_meta("from_gate", self)
		_spawns.append(m)
		spawned_total += 1
		out.append(m)
		var h := GameWorld.nearest_actor(m.global_position, GameWorld.TEAM_HEROES)
		if h != null:
			m.aggro(h)
		if fx_enabled:
			var embers: Array[Color] = [Color(1.0, 0.7, 0.25), Color(1.0, 0.3, 0.08), Color(0.5, 0.1, 0.12)]
			Fx.burst(m.global_position + Vector3.UP * 0.2, embers, 8, 2.6, 0.07, 0.55, 3.0, Vector3.UP, 60.0)
	if model != null:
		model.pulse(1.0)
	if fx_enabled and not out.is_empty():
		Fx.ring(global_position, radius + 0.6, Color(1.0, 0.35, 0.1, 0.8), 0.5, 0.0, true, 0.5)
	burst_spawned.emit(out)
	return out


func _pick_kind(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := _rng.randf() * total
	var last := "swarmer"
	for k in weights:
		last = k
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return last


## Free walkable cells in the spawn ring, shuffled, at most `n`.
func _spawn_cells(n: int) -> Array[Vector2i]:
	var here := Hex.from_world(global_position)
	var lo := RING_MIN_ORIGIN if origin else RING_MIN
	var hi := RING_MAX_ORIGIN if origin else RING_MAX
	var cands: Array[Vector2i] = []
	var map := GameWorld.map
	var base_level := 0
	if map != null and map.get_cell(here) != null:
		base_level = map.get_cell(here).level
	for r in range(lo, hi + 1):
		for c in Hex.ring(here, r):
			if map != null:
				var cell := map.get_cell(c)
				if cell == null or cell.type == HexMap.Tile.WALL or cell.type == HexMap.Tile.STAIRS:
					continue
				if absi(cell.level - base_level) > MAX_LEVEL_DIFF:
					continue
			cands.append(c)
	for i in range(cands.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var out: Array[Vector2i] = []
	for c in cands:
		if out.size() >= n:
			break
		if not GameWorld.actors_in_radius(Hex.to_world(c), CELL_CLEAR).is_empty():
			continue
		out.append(c)
	return out


# --- Damage / phases ----------------------------------------------------------------------------

func _on_damaged(_amount: float, _source: Node) -> void:
	if not _active:
		activate()
	_update_bar()
	if model != null:
		model.set_hurt(1.0 - hp / max_hp)
		model.pulse(0.35)
	if hp <= 0.0 or not origin:
		return
	var frac := hp / max_hp
	var target_phase := 0
	for th in PHASE_THRESHOLDS:
		if frac <= th:
			target_phase += 1
	while phase < target_phase:
		phase += 1
		_apply_profile()
		if model != null:
			model.set_phase(phase)
		# Summon soon after the shove, whatever the timer said.
		if not _telegraphing:
			_next_burst_in = minf(_next_burst_in, SHOVE_WINDUP + TELEGRAPH_TIME)
		phase_changed.emit(phase)
		_begin_shove()


func _begin_shove() -> void:
	_shove_t = SHOVE_WINDUP
	if model != null:
		model.telegraph_shove(SHOVE_WINDUP, SHOVE_RADIUS)
	shove_telegraphed.emit(SHOVE_RADIUS, SHOVE_WINDUP)


## The defensive burst: heroes and neutrals (employees, props) in range are thrown outward. Monsters
## are not.
func _fire_shove() -> void:
	_shove_t = -1.0
	Combat.shove_radius(global_position, SHOVE_RADIUS, SHOVE_DISTANCE, self, GameWorld.TEAM_HEROES)
	Combat.shove_radius(global_position, SHOVE_RADIUS, SHOVE_DISTANCE, self, GameWorld.TEAM_NEUTRAL)
	if model != null:
		model.pulse(2.5)
	if fx_enabled:
		Fx.ring(global_position, SHOVE_RADIUS, Color(1.0, 0.3, 0.08, 0.9), 0.55, 0.0, false, 0.3)
		var hot: Array[Color] = [Color(1.0, 0.85, 0.4), Color(1.0, 0.35, 0.1), Color(0.6, 0.1, 0.15)]
		Fx.burst(global_position + Vector3.UP * 0.5, hot, 36, 7.0, 0.1, 0.8, 3.0, Vector3.UP, 85.0)
		Fx.shake(0.35)
	shove_burst.emit(SHOVE_RADIUS)


# --- Closing --------------------------------------------------------------------------------------

func _on_death() -> void:
	remove_from_group(GROUP)
	_shove_t = -1.0
	_telegraphing = false
	if origin:
		HellgateEvents.stop_spawns()
	closed.emit(self)
	HellgateEvents.announce_closed(self, origin)
	if _bar != null:
		_bar.visible = false
	if model != null:
		model.play_close(CLOSE_TIME)
	if fx_enabled:
		Fx.shake(0.3 if origin else 0.15)
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_interval(CLOSE_TIME + 0.25)
	tw.tween_callback(queue_free)


# --- HP bar (the monster bar style) -----------------------------------------------------------------

func _ensure_bar() -> void:
	if _bar != null:
		return
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = load(BAR_SHADER_PATH)
	_bar_mat.render_priority = 10
	var quad := QuadMesh.new()
	quad.size = Vector2(_bar_width, 0.14 if origin else 0.1)
	_bar = MeshInstance3D.new()
	_bar.name = "HpBar"
	_bar.mesh = quad
	_bar.material_override = _bar_mat
	_bar.position = Vector3(0.0, _bar_height, 0.0)
	_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.set_meta("no_flash", true)
	add_child(_bar)


func _update_bar() -> void:
	if hp >= max_hp - 0.001 and not (origin and _active):
		if _bar != null:
			_bar.visible = false
		return
	_ensure_bar()
	_bar.visible = not dead
	_bar_mat.set_shader_parameter("fill", clampf(hp / max_hp, 0.0, 1.0))

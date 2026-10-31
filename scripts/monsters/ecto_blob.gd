class_name EctoBlob
extends Monster
## The ecto blob (docs/design/haunted-build-plan.md, H3b; its look: crypt-pests-look.md, the user's "Mass of faces"). The
## dead family's SLOW AREA DENIAL: a crawling mass of ectoplasm, one a pack at most, that leaves an ECTOPLASM SLICK behind it
## wherever it crawls (EctoSlick: the ectoplasm look's film along its path; it slows heroes and the staff, never the dead;
## Damp washes it away). It crawls after the crew in a fight and, idle with the crew near, wanders its room slowly, so the
## floor round it fills with slick before anyone gets there. Its strike is a slow lunge with a long tell (it gathers up tall
## and flares, then throws itself forward, a pseudopod out: EctoBlobModel). It is fragile: any hit kills it (HP under the
## weakest hero hit), no spell needed. It dies and is freed like any monster; its slick stays until it dries or is washed.
##
## The slick is the HOST's: only the blob's owner lays it (Net.owns), a segment every SLICK_STEP it crawls, and announces each
## (EctoSlick.lay -> Net.announce: a runtime host-arbitrated object, the goo patch's shape). A shove, a fall or a stair that
## moves it farther or higher than a crawl breaks the ribbon (a new run starts where it lands).
## Online (an owned actor, a host monster): no OWNER var of its own; its tell is world.windup; a late joiner gets it from the
## keyframe and its slick from the slicks' own late-join rows.

const HP := 10.0             ## under the weakest hero hit (12): any hit kills it
const SPEED := 0.85
const DAMAGE := 8.0
const WINDUP := 0.9          ## the gather-up: long and bright
const COOLDOWN := 2.4
const AGGRO := 7.0
const REACH := 1.25
const START_RANGE := 1.35
const ARC_DEG := 100.0
## Lay a slick segment every this far it crawls (EctoSlick's ribbon is drawn through them).
const SLICK_STEP := 0.6
## A move farther than this (or a climb or drop of more than SLICK_RISE) since the last segment is not a crawl: no segment
## across the gap (a shove, a fall), a new run of the ribbon from where it is.
const SLICK_JUMP := 1.8
const SLICK_RISE := 0.45
## Idle life (the crew near): wander its room slowly, a cell within WANDER_HEX of home, resting WANDER_REST s between.
const WANDER_HEX := 3
const WANDER_SPEED := 0.7
const WANDER_REST := Vector2(2.5, 5.0)

var slick_laid := 0                 ## segments this machine laid (the owner's; tests)
var _slick_from := Vector3.INF      ## where the current segment starts (the last one's end)
var _slick_seq := 0                 ## the next segment's number in its chain (a gap in the numbers breaks the ribbon)
var _slick_chain := 0               ## its chain id (groups its segments into one ribbon on every screen)
var _wander_goal := Vector3.INF
var _wander_t := 0.0


func _init() -> void:
	super._init()
	kind = "ecto_blob"
	display_name = "Ecto blob"
	max_hp = HP
	move_speed = SPEED
	radius = 0.55
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_reach = REACH
	attack_start_range = START_RANGE
	attack_arc_deg = ARC_DEG
	stop_distance = 1.0
	bar_width = 0.8
	walk_bob = 0.0
	model_windup_scale = 0.1


## Who may write each var (see Net); Monster's come from super(). The slick's bookkeeping and the wander are the host's AI
## (the slick itself is announced, EctoSlick).
func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"slick_laid": Net.PRIVATE, "_slick_from": Net.PRIVATE, "_slick_seq": Net.PRIVATE, "_slick_chain": Net.PRIVATE,
		"_wander_goal": Net.PRIVATE, "_wander_t": Net.PRIVATE,
	})
	return f


func _ready() -> void:
	if model == null and not Monster.use_proto_visuals:
		model = EctoBlobModel.new("faces")
	super._ready()
	_slick_chain = get_instance_id() & 0x3FFFFFFF


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not dead and Net.owns(self) and not Net.is_copy(self):
		_trail()


## The owner: a slick segment from the last one's end to here once it has crawled SLICK_STEP; a jump starts a new run.
func _trail() -> void:
	var at := global_position
	if _slick_from == Vector3.INF or is_airborne():
		_slick_from = at if not is_airborne() else _slick_from
		return
	var d := GameWorld.flat_distance(at, _slick_from)
	if d < SLICK_STEP:
		return
	if d > SLICK_JUMP or absf(at.y - _slick_from.y) > SLICK_RISE:
		_slick_seq += 2   # (a gap: the ribbon breaks here)
	else:
		EctoSlick.lay(_slick_from, at, _slick_chain, _slick_seq)
		_slick_seq += 1
		slick_laid += 1
	_slick_from = at


# --- Idle life: a slow wander round its room ---------------------------------------------------------------------------

func _idle_life(delta: float) -> bool:
	_wander_t -= delta
	if _wander_goal == Vector3.INF:
		if _wander_t > 0.0:
			return false
		_wander_goal = _pick_wander()
		if _wander_goal == Vector3.INF:
			_wander_t = WANDER_REST.x
			return false
	if GameWorld.flat_distance(global_position, _wander_goal) < 0.35 or _stuck_n >= 2:
		_stuck_n = 0
		_wander_goal = Vector3.INF
		_wander_t = GameWorld.rng.randf_range(WANDER_REST.x, WANDER_REST.y)
		return false
	_speed_k = WANDER_SPEED
	_nav_to(_wander_goal, delta)
	_speed_k = 1.0
	return true


func _pick_wander() -> Vector3:
	var map := GameWorld.map
	if map == null:
		return Vector3.INF
	var cells := Hex.range_cells(Hex.from_world(home), WANDER_HEX)
	for _i in 6:
		var c: Vector2i = cells[GameWorld.rng.randi_range(0, cells.size() - 1)]
		if map.is_walkable_cell(c) and not map.is_pool_cell(c) and MonsterSenses.room_of(c) == _room:
			return Hex.to_world(c, float(map.get_cell(c).level))
	return Vector3.INF


func _on_home() -> void:
	_wander_goal = Vector3.INF
	_wander_t = GameWorld.rng.randf_range(WANDER_REST.x, WANDER_REST.y)


# --- The look without a model (Monster.use_proto_visuals) ------------------------------------------------------------

func _build_visual(root: Node3D) -> void:
	var ecto := _mat(Color(0.7, 0.86, 1.0), 1.0)
	var hollow := _mat(Color(0.05, 0.05, 0.06))
	_sphere(root, 0.55, Vector3(0.0, 0.3, 0.0), ecto).scale = Vector3(1.1, 0.7, 1.0)
	_sphere(root, 0.3, Vector3(0.4, 0.2, 0.2), ecto)
	_sphere(root, 0.28, Vector3(-0.4, 0.2, -0.05), ecto)
	_sphere(root, 0.06, Vector3(-0.12, 0.5, -0.45), hollow)
	_sphere(root, 0.06, Vector3(0.12, 0.5, -0.45), hollow)

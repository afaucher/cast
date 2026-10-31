class_name CryptRat
extends "res://scripts/monsters/swarmer.gd"
## The crypt rat (docs/design/haunted-build-plan.md, H3b; its look: crypt-pests-look.md, the user's "Sewer brute"). The dead
## family's FAST SWARM: one pack pick is a clump of 5-6 (MonsterDefs "swarm_min" / "swarm_max"), favoured in a crypt's rooms
## (PackPlanner.CRYPT_BIAS). It is the swarmer imp's AI (it closes in, darts in for a bite when it is off cooldown and circles
## while the bite recharges; idle, a clump plays round its centre), a little slower and tougher, with a longer, readable tell:
## the POUNCE (RatModel.tell "pounce": it flattens and draws back, hind legs bunched, the head low and the jaw open, the tail up
## and lashing; the monsters' wind-up tint flashes it) and then the bite, a snap forward. The look test's rear-up was dropped:
## from the game camera a rearing rat only gets shorter.
## It dies and is freed like any monster (no body). Online: a host monster (the swarmer's shape: no OWNER var of its own; its
## tell is world.windup); a late joiner gets it from the keyframe.

const RAT_HP := 14.0
const RAT_SPEED := 5.0
const RAT_DAMAGE := 5.0
const RAT_WINDUP := 0.5      ## the pounce's tell: longer than the imp's 0.3 (a pack of six, each readable)
const RAT_COOLDOWN := 0.9
const RAT_AGGRO := 9.0
const RAT_REACH := 0.8
const RAT_START := 1.15


func _init() -> void:
	super._init()
	kind = "crypt_rat"
	display_name = "Crypt rat"
	max_hp = RAT_HP
	move_speed = RAT_SPEED
	radius = 0.3
	aggro_range = RAT_AGGRO
	attack_damage = RAT_DAMAGE
	attack_windup = RAT_WINDUP
	attack_cooldown = RAT_COOLDOWN
	attack_reach = RAT_REACH
	attack_start_range = RAT_START
	attack_arc_deg = 140.0
	stop_distance = 0.7
	bar_width = 0.55
	walk_bob = 0.06
	model_windup_scale = 0.12     # (it puffs up a little as it bunches, the imp's swell: with the tint, the tell from above)


func _ready() -> void:
	if model == null and not Monster.use_proto_visuals:
		var m := RatModel.new("sewer")
		m.tell = "pounce"
		model = m
	super._ready()


## Who may write each var (see Net): the swarmer's (Monster's and its play) cover every var; it adds none.
func net_fields() -> Dictionary:
	return super()


# --- The look without a model (Monster.use_proto_visuals) ------------------------------------------------------------

func _build_visual(root: Node3D) -> void:
	var fur := _mat(Color(0.40, 0.31, 0.23))
	var pink := _mat(Color(0.80, 0.58, 0.56))
	var eye := _mat(Color(0.1, 0.05, 0.05))
	_box(root, Vector3(0.36, 0.3, 0.7), Vector3(0.0, 0.32, 0.0), fur)
	_sphere(root, 0.15, Vector3(0.0, 0.36, -0.44), fur)
	_cone(root, 0.08, 0.16, Vector3(0.0, 0.33, -0.6), pink).rotation_degrees = Vector3(-90, 0, 0)
	_box(root, Vector3(0.05, 0.05, 0.7), Vector3(0.0, 0.2, 0.68), pink)
	_sphere(root, 0.03, Vector3(-0.07, 0.42, -0.54), eye)
	_sphere(root, 0.03, Vector3(0.07, 0.42, -0.54), eye)

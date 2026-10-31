class_name BonesHost
extends HauntHost
## A skeleton a ghost can possess (docs/design/haunted-build-plan.md, "H5 as built"; haunt-look.md: the dormant skeleton
## slumped, the risen one today's skeleton standing; BonesModel). In the mansion's, the church's and the crypt's rooms.
##   DORMANT    dead bones slumped against a wall, the skull dropped, the eyes out: set dressing.
##   POSSESSED  it gets up (BonesModel.wake) and fights as a skeleton does (the grunt's numbers: a quick cleave).
##   BROKEN     free to smash (the user, 2026-10-31: "But bones don't count"): no bill. It falls apart as a skeleton does.

const HP := 40.0                    ## a skeleton's
const SPEED := 3.2
const DAMAGE := 10.0
const WINDUP := 0.35
const COOLDOWN := 1.1
const AGGRO := 8.0
const REACH := 1.4
const START_RANGE := 1.5
const ARC_DEG := 120.0


func _init() -> void:
	super._init()
	kind = "bones"
	display_name = "Skeleton"
	price = 0
	max_hp = HP
	move_speed = SPEED
	radius = 0.38
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_reach = REACH
	attack_start_range = START_RANGE
	attack_arc_deg = ARC_DEG
	stop_distance = 1.0
	bar_width = 0.8


func _ready() -> void:
	if model == null and not Monster.use_proto_visuals:
		model = BonesModel.new()
	super._ready()


func bones() -> BonesModel:
	return model as BonesModel


func _show_dormant() -> void:
	if bones() != null:
		bones().set_dormant()


func _show_possessed(instant: bool) -> void:
	var b := bones()
	if b == null:
		return
	b.phase = phase
	b.wake(instant)
	b.set_ghost(true)

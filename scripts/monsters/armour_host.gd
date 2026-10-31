class_name ArmourHost
extends HauntHost
## A suit of armour a ghost can possess (docs/design/haunted-build-plan.md, "H5 as built"; the look: ghost-look.md's knight,
## the user's "Knight silhouette" and "Sword, not halberd"; animated: KnightModel). The mansion's.
##   DORMANT    exactly the priced "Suit of armour" (PricedProp's H1 row, which stays a plain antique beside it): the same
##              model on its plinth, the same look, the same price tag near this screen's own hero, a wobble and chips when it
##              takes a knock. Nothing tells the two apart until a ghost gets in.
##   POSSESSED  it wakes (KnightModel.wake: the guard, then the march off its plinth, which stays behind: a cosmetic node
##              left in the world) and fights: a slow, heavy two-handed chop (a long wind-up, the sword hauled over its
##              shoulder; a cone in front of it).
##   BROKEN     billed to the culprit as the antique (MonsterDefs "armour" billed: the priced suit's $6,000), possessed or not
##              (the user, 2026-10-31: "Breaking a possessed antique[:] it [bills] the crew"); the props' break (the debris,
##              the red price) and a scatter of plate left where it fell.

const HP := 90.0                    ## the priced suit's
const SPEED := 2.0                  ## a heavy march (the crew walks 4.5)
const DAMAGE := 16.0
const WINDUP := 0.8
const COOLDOWN := 1.9
const AGGRO := 8.0
const REACH := 1.7
const START_RANGE := 1.7
const ARC_DEG := 120.0
const PLINTH_STEP := 0.35           ## it is down off its plinth this far from its middle

static var PRICES: Dictionary = MonsterDefs.prices("armour")
static var NAMES: Dictionary = MonsterDefs.bill_names("armour")

var tag_label: Label3D = null
var plinth: Node3D = null           ## the plinth it stepped off (in the world; a look)
var _plinth_at := Vector3.INF       ## where it stood dormant (the plinth's middle)
var _tag_target := false
var _tag_tick := 0
var _wobble: Tween = null


func _init() -> void:
	super._init()
	kind = "armour"
	price = int(PRICES.get("regular", 6000))
	display_name = String(NAMES.get("regular", "Suit of armour"))
	max_hp = HP
	move_speed = SPEED
	radius = 0.5
	aggro_range = AGGRO
	attack_damage = DAMAGE
	attack_windup = WINDUP
	attack_cooldown = COOLDOWN
	attack_reach = REACH
	attack_start_range = START_RANGE
	attack_arc_deg = ARC_DEG
	stop_distance = 1.2
	bar_width = 1.0


func net_fields() -> Dictionary:
	var f := super()
	f.merge({
		"tag_label": Net.LOCAL, "plinth": Net.LOCAL, "_plinth_at": Net.LOCAL, "_tag_target": Net.LOCAL, "_tag_tick": Net.LOCAL,
		"_wobble": Net.LOCAL,
	})
	return f


func _ready() -> void:
	if model == null and not Monster.use_proto_visuals:
		model = KnightModel.new()
	super._ready()
	_build_tag()


func knight() -> KnightModel:
	return model as KnightModel


# --- The look ------------------------------------------------------------------------------------------------------------

func _show_dormant() -> void:
	if knight() != null:
		knight().set_dormant()


## The ghost gets in: it wakes, the possessed look goes on, and the plinth is left in the world where it stood.
func _show_possessed(instant: bool) -> void:
	var k := knight()
	if k == null:
		return
	if _plinth_at == Vector3.INF:
		_plinth_at = global_position   # (where it stood dormant: the plinth stays there)
	k.phase = phase
	k.wake(instant)
	k.set_ghost(true)
	_leave_plinth()


func _leave_plinth() -> void:
	var k := knight()
	if k == null or plinth != null or GameWorld.root == null:
		return
	var s := k.parts.get("stand") as Node3D
	if s == null or s.get_parent() != k:
		return
	var xf := s.global_transform
	plinth = Node3D.new()
	plinth.name = "Plinth"
	GameWorld.root.add_child(plinth)
	k.remove_child(s)
	plinth.add_child(s)
	s.global_transform = xf


## Each frame: the stance's height (on its plinth until it steps off it).
func _pose(_delta: float, _moving: bool) -> void:
	var k := knight()
	if k == null:
		return
	var d := GameWorld.flat_distance(global_position, _plinth_at) if _plinth_at != Vector3.INF else 0.0
	k.lift = ArmourModel.STAND_H * clampf(1.0 - (d - 0.1) / PLINTH_STEP, 0.0, 1.0)


func _process(delta: float) -> void:
	if tag_label == null:
		return
	_tag_tick += 1
	if _tag_tick % 3 == 0:
		_tag_target = _hero_near()
	var a := move_toward(tag_label.modulate.a, 1.0 if _tag_target and not dead else 0.0, PricedProp.TAG_FADE_SPEED * delta)
	tag_label.modulate.a = a
	tag_label.visible = a > 0.01


## The priced suit's tag ("Suit of armour – $6,000"), near this screen's own hero only.
func _build_tag() -> void:
	tag_label = Label3D.new()
	tag_label.name = "PriceTag"
	tag_label.text = "%s – %s" % [display_name, PricedProp.money(price)]
	tag_label.font_size = 56
	tag_label.pixel_size = 0.0075
	tag_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag_label.no_depth_test = true
	tag_label.shaded = false
	tag_label.render_priority = 15
	tag_label.modulate = Color(PricedProp.TAG_COLOR.r, PricedProp.TAG_COLOR.g, PricedProp.TAG_COLOR.b, 0.0)
	tag_label.outline_modulate = PricedProp.TAG_OUTLINE
	tag_label.outline_size = 14
	tag_label.visible = false
	tag_label.position = Vector3(0, PropModels.height("suit_of_armour") + 0.55, 0)
	add_child(tag_label)


func tag_shown() -> bool:
	return _tag_target and not dead


func _hero_near() -> bool:
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Hero
		if a != null and not a.dead and a.is_player and GameWorld.flat_distance(a.global_position, global_position) <= PricedProp.TAG_RANGE:
			return true
	return false


## A knock on the dormant antique: the priced props' wobble and chips.
func _dent(amount: float) -> void:
	Sfx.play_at("prop_dent", global_position)
	if _visual == null:
		return
	if _wobble != null and _wobble.is_valid():
		_wobble.kill()
	var tilt := deg_to_rad(clampf(amount * 0.25, 1.5, 6.0))
	_wobble = create_tween()
	_wobble.tween_property(_visual, "rotation:z", tilt, 0.05)
	_wobble.tween_property(_visual, "rotation:z", -tilt * 0.6, 0.09)
	_wobble.tween_property(_visual, "rotation:z", 0.0, 0.1)
	if amount >= 8.0:
		PropDebris.burst(global_position + Vector3.UP * 1.1, PropModels.palette("suit_of_armour"), 3, 0.5)


## Broken: the props' break (debris, dust, the red price) and the scatter of plate left behind; then the knight folds and goes.
func _break() -> void:
	var c := global_position
	Sfx.play_at("prop_break", c)
	var h := PropModels.height("suit_of_armour")
	PropDebris.burst(c + Vector3.UP * h * 0.45, PropModels.palette("suit_of_armour"), 16, 1.1)
	var dust: Array[Color] = [Color(0.8, 0.72, 0.58), Color(0.55, 0.48, 0.4)]
	Fx.burst(c + Vector3.UP * 0.4, dust, 18, 3.2, 0.17, 0.75, 1.5, Vector3.UP, 85.0, false)
	Fx.number(c + Vector3(0, h + 0.5, 0), "-" + PricedProp.money(price), PricedProp.MONEY_RED, 1.1)
	Fx.shake(0.2)
	if tag_label != null:
		tag_label.queue_free()
		tag_label = null
	if GameWorld.root != null:
		var rubble := PropModels.rubble("suit_of_armour")
		GameWorld.root.add_child(rubble)
		rubble.global_position = c
	super._break()

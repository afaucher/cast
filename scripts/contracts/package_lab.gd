extends LabBase
## Mail-package lab: the real terrain look (HexMapView + DungeonLook) with the three box sizes, stacks of 2 and
## 3, and one broken box per kind of contents (skulls, yogurt, pickles, a spell component, crypto cash) with its
## spill on the floor, plus Wick for scale. Scene: scenes/package_lab.tscn.
##
##   godot --path . -- --scene res://scenes/package_lab.tscn --shot <abs.png>
##
## --shot <png>   renders every view, then quits:  <base>_game.png, _close.png, _spills.png
## --view <name>  only that view, written to <png> exactly:
##                  game    the real game camera (yaw 45, pitch -56), everything, ortho size 15
##                  close   the stacks and the singles, ortho size 8
##                  spills  the five broken boxes, ortho size 8
##                  box     one box alone (needs --size-kind small|medium|long), ortho size 2.6; --yaw/--pitch/--size override
## No --shot: opens the lab; the broken boxes are rebuilt every 40 s so the spills can be watched.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const SPACING := 2.2
const ROW_INTACT := -2.4
const ROW_BROKEN := 2.2
const CONTENTS: Array[String] = ["skulls", "yogurt", "pickles", "component", "crypto"]

var only_kind := "medium"
var cam_yaw := NAN
var cam_pitch := NAN
var cam_size := NAN
var wick: Hero
var intact: Array[MailPackage] = []
var broken: Array[MailPackage] = []
var _cycle := 0.0
var _u_center := 0.0


func _ready() -> void:
	_parse_args()
	build_arena(20, 11, 16, 3)
	make_camera()
	Ledger.begin_contract(60000)
	if only_view == "box":
		intact.append(MailPackage.spawn(Vector2.ZERO, {"size": only_kind, "yaw": 20.0, "seed": 4}))
	else:
		_populate()
	if shot_path != "":
		_run_shots()
	else:
		aim(GAME_YAW, GAME_PITCH, 12.0, _row_pos(_u_center, 0.0) + Vector3(0, 0.4, 0))


func _parse_args() -> void:
	only_kind = arg(args, "--size-kind", "medium")
	if arg(args, "--yaw") != "":
		cam_yaw = float(arg(args, "--yaw"))
	if arg(args, "--pitch") != "":
		cam_pitch = float(arg(args, "--pitch"))
	if arg(args, "--size") != "":
		cam_size = float(arg(args, "--size"))


## World position at screen-right offset x and away-from-camera offset z (for the game yaw).
func _row_pos(x: float, z: float) -> Vector3:
	var yaw := deg_to_rad(GAME_YAW)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return right * x + fwd * z


func _populate() -> void:
	# Intact row: small, medium, long, a stack of 2, a stack of 3, a mixed stack.
	var singles: Array[String] = ["small", "medium", "long"]
	var x := -5.6
	for k in singles:
		intact.append(_box(x, ROW_INTACT, k, 20.0 + x * 3.0, 0.0, null))
		x += SPACING + (0.5 if k == "long" else 0.0)
	_stack(x, ["medium", "small"], 12.0)
	x += SPACING
	_stack(x, ["medium", "medium", "small"], -18.0)
	x += SPACING
	_stack(x, ["long", "small"], 25.0)
	_u_center = 0.0
	wick = HeroFactory.spawn_hero(Hex.from_world(_row_pos(-7.4, ROW_INTACT + 0.8)), "Wick", Color(0.3, 0.55, 0.95), "sword", WickModel.new(), HeroKit.WICK)
	_spawn_broken()


func _box(x: float, z: float, kind: String, yaw: float, lift: float, below: MailPackage) -> MailPackage:
	var at := _row_pos(x, z)
	return MailPackage.spawn(Vector2(at.x, at.z), {"size": kind, "yaw": yaw, "lift": lift, "below": below, "seed": 11 + int(x * 10.0)})


func _stack(x: float, kinds: Array[String], yaw: float) -> void:
	var below: MailPackage = null
	var lift := 0.0
	for i in kinds.size():
		var m := _box(x + 0.03 * float(i), ROW_INTACT, kinds[i], yaw + 9.0 * float(i), lift, below)
		m.stack_index = i
		intact.append(m)
		lift += PackageModels.height_of(kinds[i])
		below = m


func _spawn_broken() -> void:
	broken.clear()
	for i in CONTENTS.size():
		var at := _row_pos(-4.4 + SPACING * 1.15 * float(i), ROW_BROKEN)
		broken.append(MailPackage.spawn(Vector2(at.x, at.z), {"size": "medium", "yaw": 25.0 + 11.0 * float(i), "seed": 100 + i, "contents": CONTENTS[i]}))


## Break the boxes (the lab forces what is inside). The crypto and component boxes go last in the shots,
## so their text pop and sparkle are still in the air.
func _break(list: Array[MailPackage], only: Array[String] = []) -> void:
	for m in list:
		if is_instance_valid(m) and not m.dead and (only.is_empty() or only.has(m.forced_contents)):
			m.apply_damage(1.0, wick)


func _set_view(view: String) -> void:
	match view:
		"game":
			aim(GAME_YAW, GAME_PITCH, 15.0, _row_pos(0.0, 0.0) + Vector3(0, 0.3, 0))
		"close":
			aim(GAME_YAW, GAME_PITCH, 7.5, _row_pos(0.6, ROW_INTACT) + Vector3(0, 0.5, 0))
		"spills":
			aim(GAME_YAW, GAME_PITCH, 8.0, _row_pos(0.4, ROW_BROKEN) + Vector3(0, 0.2, 0))
		"box":
			var yaw := cam_yaw if not is_nan(cam_yaw) else GAME_YAW
			var pitch := cam_pitch if not is_nan(cam_pitch) else GAME_PITCH
			var size := cam_size if not is_nan(cam_size) else 2.6
			aim(yaw, pitch, size, Vector3(0, 0.3, 0))


# ------------------------------------------------------------------ screenshots

func _run_shots() -> void:
	await wait_physics(20)
	if only_view == "box":
		_set_view("box")
		await snap(shot_path, 20)
		finish()
		return
	var base := shot_path.get_basename()
	var views: Array[String] = ["game", "close", "spills"]
	if only_view != "":
		views = [only_view]
	# Decorative spills first so they have time to settle; the prize boxes last, caught mid-pop.
	var decorative: Array[String] = ["skulls", "yogurt", "pickles"]
	_break(broken, decorative)
	await wait_physics(110)
	_break(broken)
	await wait_physics(12)
	for v in views:
		_set_view(v)
		await snap(shot_path if only_view != "" else "%s_%s.png" % [base, v], 2)
	finish()


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_cycle += delta
	if _cycle > 40.0:
		_cycle = 0.0
		for m in broken:
			if is_instance_valid(m):
				m.queue_free()
		_spawn_broken()
	elif _cycle > 3.0 and _cycle - delta <= 3.0:
		_break(broken)

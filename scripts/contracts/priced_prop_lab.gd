extends LabBase
## Priced-prop lab: the real terrain look (HexMapView + DungeonLook) with both prop catalogs on
## slate hexes (luxury bunker row in front, villain lair row behind), two heroes so price tags fade
## in, a gold toilet mid-break with debris, and the live DamageTicker. Scene: scenes/prop_lab.tscn.
##
##   godot --path . -- --scene res://scenes/prop_lab.tscn --shot <abs.png>
##
## --shot <png>   renders every view, then quits:  <base>_game.png, _close.png, _bunker.png, _lair.png
## --view <name>  only that view, written to <png> exactly:
##                  game    the real game camera (yaw 45, pitch -56, ortho size 24), everything
##                  close   the gold toilet breaking, Wick next to it, the ticker
##                  bunker / lair   one catalog row, ortho size 12
##                  prop    one prop alone (needs --prop <kind>), ortho size 3.6; --yaw/--pitch/--size override
## --prop <kind>  with --view prop
## --decor <kind> with --view prop: a room-theme decor piece (DecorModels) instead of a priced prop
## No --shot: opens the lab; the demo toilet breaks and rebuilds every few seconds.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const SPACING := 2.45

var only_prop := ""
var only_decor := ""
var cam_yaw := NAN
var cam_pitch := NAN
var cam_size := NAN
var wick: Hero
var gasket: Hero
var demo: PricedProp
var ticker: DamageTicker
var props: Array[PricedProp] = []
var _cycle := 0.0
var _yaw := GAME_YAW
var _u_center := 0.0       ## where the rows' middle lies along the screen-right axis


func _ready() -> void:
	_parse_args()
	build_arena(26, 14, 20, 3)
	make_camera()
	Ledger.begin_contract(60000)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ticker = DamageTicker.new()
	ticker.hold_time = 600.0
	layer.add_child(ticker)
	if only_view == "prop" and only_decor != "":
		add_child(DecorModels.build(only_decor))
	elif only_view == "prop":
		var p := PricedProp.spawn(Vector2i.ZERO, only_prop if only_prop != "" else "gold_toilet", {})
		props.append(p)
	else:
		_populate()
	if shot_path != "":
		_run_shots()
	else:
		_aim(GAME_YAW, GAME_PITCH, 14.0, _row_pos(0.0, 0.0) + Vector3(0, 0.6, 0))


func _parse_args() -> void:
	only_prop = arg(args, "--prop")
	only_decor = arg(args, "--decor")
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


func _cell_at(x: float, z: float) -> Vector2i:
	return Hex.from_world(_row_pos(x, z))


func _populate() -> void:
	var bunker := PricedProp.catalog("bunker")
	var lair := PricedProp.catalog("lair")
	_place_row(bunker, -2.6)
	_place_row(lair, 2.6)
	var right := Vector3(cos(deg_to_rad(GAME_YAW)), 0.0, -sin(deg_to_rad(GAME_YAW)))
	var sum := 0.0
	for p in props:
		sum += p.global_position.dot(right)
	_u_center = sum / float(maxi(props.size(), 1))
	# Two heroes for scale; each stands next to exactly one prop so its price tag fades in.
	wick = HeroFactory.spawn_hero(_cell_at(-2.5, -5.2), "Wick", Color(0.3, 0.55, 0.95), "sword", WickModel.new(), HeroKit.WICK)
	gasket = HeroFactory.spawn_hero(_cell_at(-10.3, 3.9), "Gasket", Color(0.7, 0.4, 0.85), "sword", GasketModel.new(), HeroKit.GASKET)
	_spawn_demo()


## One catalog along a screen-horizontal row: each prop on its own cell, at least 2.3 further along
## the row than the last and as close to the row's centre line as the hex grid allows.
func _place_row(kinds: Array[String], z: float) -> void:
	var yaw := deg_to_rad(GAME_YAW)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var u_prev := -8.6 - SPACING
	for i in kinds.size():
		var want := _row_pos(u_prev + SPACING, z)
		var best := Hex.from_world(want)
		var best_score := INF
		for c in Hex.range_cells(Hex.from_world(want), 2):
			var w := Hex.to_world(c)
			var u := w.dot(right)
			var v := w.dot(fwd)
			if u - u_prev < 2.2:
				continue
			var score := absf(v - z) + 0.7 * absf(u - u_prev - SPACING)
			if score < best_score:
				best_score = score
				best = c
		u_prev = Hex.to_world(best).dot(right)
		props.append(PricedProp.spawn(best, kinds[i], {}))


func _spawn_demo() -> void:
	demo = PricedProp.spawn(_cell_at(3.5, -6.0), "gold_toilet", {})


## Earlier damage on the invoice, then the toilet goes.
func _break_demo() -> void:
	Ledger.begin_contract(60000)
	Ledger.damage("Wine rack", 1200, gasket)
	Ledger.damage("Vintage 1787 wine barrel", 4000, gasket)
	if is_instance_valid(demo) and not demo.dead:
		demo.apply_damage(demo.max_hp * 0.4, wick)    # a dent first (free), then it goes
		demo.apply_damage(demo.max_hp, wick)


func _aim(yaw_deg: float, pitch_deg: float, size: float, tgt: Vector3) -> void:
	_yaw = yaw_deg
	aim(yaw_deg, pitch_deg, size, tgt)


func _set_view(view: String) -> void:
	match view:
		"game":
			_aim(GAME_YAW, GAME_PITCH, GAME_SIZE, _row_pos(_u_center, 0.0) + Vector3(0, 0.4, 0))
		"close":
			var c := _row_pos(0.4, -5.4)
			_aim(GAME_YAW, GAME_PITCH, 8.0, c + Vector3(0, 0.6, 0))
		"bunker":
			_aim(GAME_YAW, GAME_PITCH, 15.0, _row_pos(_u_center, -2.6) + Vector3(0, 0.9, 0))
		"lair":
			_aim(GAME_YAW, GAME_PITCH, 15.0, _row_pos(_u_center, 2.6) + Vector3(0, 0.9, 0))
		"prop":
			var yaw := cam_yaw if not is_nan(cam_yaw) else GAME_YAW
			var pitch := cam_pitch if not is_nan(cam_pitch) else GAME_PITCH
			var size := cam_size if not is_nan(cam_size) else 3.6
			_aim(yaw, pitch, size, Vector3(0, 0.9, 0))


# ------------------------------------------------------------------ screenshots

func _run_shots() -> void:
	await wait_physics(30)
	var base := shot_path.get_basename()
	if only_view == "prop":
		_set_view("prop")
		await snap(shot_path, 30)
		finish()
		return
	var views: Array[String] = ["game", "close", "bunker", "lair"]
	if only_view != "":
		views = [only_view]
	# Let the hero tags fade in, then break the demo toilet and catch the debris in the air.
	await wait_physics(40)
	_break_demo()
	await wait_physics(14)
	for v in views:
		_set_view(v)
		await snap(shot_path if only_view != "" else "%s_%s.png" % [base, v], 2)
	finish()


func _process(delta: float) -> void:
	if shot_path != "":
		return
	_cycle += delta
	if _cycle > 6.0:
		_cycle = 0.0
		if is_instance_valid(demo) and not demo.dead:
			_break_demo()
		else:
			if is_instance_valid(demo):
				demo.queue_free()
			_spawn_demo()

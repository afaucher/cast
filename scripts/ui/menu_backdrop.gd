class_name MenuBackdrop
extends Node3D
## The main menu's living background: the crew's bunker GARAGE. Wick, Gasket and Rebar idle around the work van
## (the real VanModel, side door open) parked on its chalk pentagram, in a stone-block garage over the hex floor.
## Torches flicker, dusty light shafts fall from a ceiling grate, a hellgate glows red through a breach in the back
## wall behind hazard tape, and the signs tell the story ("24/7 EMERGENCY DISPATCH! WE FIX YOUR HEXES OR IT'S
## FREE!", "JOBS SINCE LAST CORN INCIDENT", a neon CAST with a dead letter). The camera drifts slowly.
## It needs none of the game systems (no GameWorld, no actors, no physics): one terrain mesh, the walls and props
## as a few meshes, three models, one van, one gate and about six lights, and nothing allocates per frame.
##
## The menu (a clipboard form) sits on the LEFT third, so the crew and the van are framed into the right two
## thirds (`FRAME_SHIFT`). The glowing hex seams are turned down (HexMapView.seam_gain / seam_near_gain) because
## bright seams under a UI are loud.
##
## CREW: the hero the local player plays (`featured_hero`, `set_featured_hero(id)`; Wick today, a character select
## later) stands in FRONT, large and turned three-quarters to the camera, left of the van's open cargo door; the other two
## stand back (one by the cab, one beyond the nose) in a loose triangle. Swapping re-poses the three in place.
##
## MOODS (`mood`, `set_mood()`):
##   dawn   cool light through the ceiling grate over warm work lights and torches (the default)
##   night  no grate light, a colour grade (cool, dark), the van's headlights on, the gate runs hotter
##   after  the morning after a bad job (scripts/ui/backdrops/after_job.gd): a giant corn cob wedged in the van roof, the hood
##          popped over a small fire and a smoke column, scorch marks on the floor and up the wall, cobs, kernels and husks
##          about, an invoice stamped PAST DUE, a failing work lamp, the crew sooty, patched and slumping
## Left empty, the mood comes from context (`pick_mood()`): `--backdrop-mood dawn|night|after` wins; otherwise
## "after" when the last finished contract went badly (LastContract.was_bad), "night" when the local clock is
## between 20:00 and 05:00, else "dawn".
##
## The shared pieces live in scripts/ui/backdrops/backdrop_kit.gd. The options lab (scenes/backdrop_lab.tscn,
## `--option garage`) shows this scene too.

const Kit := preload("res://scripts/ui/backdrops/backdrop_kit.gd")
const After := preload("res://scripts/ui/backdrops/after_job.gd")

const MOODS: Array[String] = ["dawn", "night", "after"]
const NIGHT_FROM_HOUR := 20          ## local clock: night from 20:00 ...
const NIGHT_UNTIL_HOUR := 5          ## ... until 05:00
const MOOD_FLAG := "--backdrop-mood"
const HERO_FLAG := "--backdrop-hero"
const HEROES: Array[String] = ["wick", "gasket", "rebar"]
## The hero the local player plays. game.gd still hard-codes Wick (there is no character select yet), so this is the
## default for `featured_hero`; a character select should call set_featured_hero() instead of editing this.
const PLAYER_HERO := "wick"

const WALL_Z := -5.0                 ## the back wall's front face
const WALL_X := 12.5                 ## side walls at +-this
const WALL_H := 8.0
const BREACH := Vector2(8.7, 2.1)    ## breach centre on the back wall (x, y)
const BREACH_R := Vector2(1.85, 2.3)
const GATE_AT := Vector3(8.7, 0.0, -6.9)
const VAN_AT := Vector3(1.4, 0.0, -1.2)
const VAN_YAW := -10.0
const CAM_POS := Vector3(-0.4, 5.0, 11.4)
const CAM_LOOK := Vector3(2.6, 1.5, -1.0)
const CAM_FOV := 42.0
## Crew spots, relative to the van (world X, Z), and the yaw added to "facing the camera" (degrees). The featured hero
## is the front point of a loose triangle, left of the van's open cargo door (over the slid-back door panel, so the
## door itself stays clear); the second stands by the cab, leaning toward the van with a tool; the third stands back
## beyond the nose. All three stay right of the clipboard on the left third.
const SPOT_FRONT := Vector3(-2.7, 0.0, 4.3)
const SPOT_CAB := Vector3(2.4, 0.0, 2.8)
const SPOT_BACK := Vector3(5.7, 0.0, -0.6)
const YAW_FRONT := 24.0
const YAW_CAB := -20.0
const YAW_BACK := -28.0
## Sideways nudge of the front spot per hero (world X): the short dwarf with his hammer needs to clear the clipboard.
const FRONT_NUDGE := {"gasket": 0.8}
## Which of the two supporting spots a hero prefers (the dwarf with the hammer by the cab, then Wick; Rebar stands back).
const CAB_ORDER: Array[String] = ["gasket", "wick", "rebar"]
## Camera slide (Camera3D.h_offset, world units, sideways without turning) that moves the picture toward the right so the
## clipboard on the left third does not sit on the van.
const FRAME_SHIFT := -2.7
## Roll (degrees) of each hero's slump after a bad job, so the three do not lean the same way.
const SLUMP_ROLL := {"wick": 5.0, "gasket": -4.0, "rebar": 3.0}
const SWAY_DEG := 3.2                ## the camera orbits its focus by +- this
const SWAY_SPEED := 0.12             ## rad/s: a full sway takes ~52 s

## Hex seams: calm under a menu (1 = the game's loudness).
const SEAM_GAIN := 0.35
const SEAM_NEAR_GAIN := 0.2
const SEAM_NEAR_RANGE := 18.0

const STONE: Array[Color] = [Color(0.34, 0.31, 0.29), Color(0.3, 0.28, 0.27), Color(0.38, 0.35, 0.31), Color(0.27, 0.26, 0.27)]
const TIMBER := Color(0.3, 0.19, 0.11)

## Set before add_child (or call set_mood afterwards). "" = pick from context (pick_mood).
var mood := ""
## The hero standing in front ("wick", "gasket" or "rebar"). "" = the player's hero (`--backdrop-hero` overrides).
## Change it any time with set_featured_hero().
var featured_hero := ""
## The number on the "JOBS SINCE LAST CORN INCIDENT" sign: finished contracts in a row that were not bad
## (LastContract.clean_jobs). After a bad job it is 0, and the "after" mood pastes a huge red 0 over it whatever it says.
var corn_jobs := LastContract.clean_jobs():
	set(v):
		corn_jobs = v
		if _corn_sign_label != null:
			_corn_sign_label.text = _corn_text()

var map: HexMap
var terrain: HexMapView
var camera: Camera3D
var gate: HellgateModel
var van: VanModel
var wick: WickModel
var rebar: RebarModel
var gasket: GasketModel
var key_light: DirectionalLight3D
var environment: Environment

var _t := 0.0
var _built := false
var _mood_root: Node3D                ## everything that depends on the mood (lights, shafts, smoke, mess); rebuilt by set_mood
var _torches: Array[Node3D] = []
var _breach_flicker: Kit.Flicker
var _gate_light: OmniLight3D
var _van_holder: Node3D
var _corn_sign_label: Label3D
var _corn_sign_node: Node3D
var _work_lamp: OmniLight3D            ## the overhead work lamp of the day moods (it fails after a bad job)
var _crew_extras: Array[Node] = []     ## plasters and soot smudges on the crew's faces (the after mood), freed with the mood
var _face_yaw := 0.0                  ## yaw (degrees) that turns a model to face the camera


func _ready() -> void:
	if mood == "" or not MOODS.has(mood):
		mood = pick_mood(OS.get_cmdline_user_args(), int(Time.get_datetime_dict_from_system()["hour"]))
	if not HEROES.has(featured_hero):
		featured_hero = hero_from_args(OS.get_cmdline_user_args())
	_build_map()
	terrain = HexMapView.new()
	terrain.name = "Terrain"
	terrain.seam_gain = SEAM_GAIN
	terrain.seam_near_gain = SEAM_NEAR_GAIN
	terrain.seam_near_range = SEAM_NEAR_RANGE
	add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(self)
	var we := get_node_or_null("LookEnvironment") as WorldEnvironment
	if we != null:
		environment = we.environment
	key_light = get_node_or_null("KeyLight") as DirectionalLight3D
	if key_light != null:
		# one shadow split over the crew and the van instead of the game's four: a menu does not need the range
		key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		key_light.directional_shadow_max_distance = 26.0
		key_light.shadow_enabled = false
	_build_walls()
	_build_gate()
	_build_van()
	_build_crew()
	_build_dressing()
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = CAM_FOV
	camera.near = 0.2
	camera.far = 120.0
	camera.h_offset = FRAME_SHIFT
	add_child(camera)
	camera.current = true
	_built = true
	_apply_mood()
	_place_camera(0.0)


func _process(delta: float) -> void:
	_t += delta
	_place_camera(_t)


## The mood to show: the dev flag, else the morning after a bad job, else night by the local clock, else dawn.
static func pick_mood(args: PackedStringArray, hour: int) -> String:
	var i := args.find(MOOD_FLAG)
	if i >= 0 and i + 1 < args.size() and MOODS.has(args[i + 1]):
		return args[i + 1]
	if LastContract.was_bad():
		return "after"
	if hour >= NIGHT_FROM_HOUR or hour < NIGHT_UNTIL_HOUR:
		return "night"
	return "dawn"


## Switch mood at any time (rebuilds the few mood-dependent pieces).
func set_mood(new_mood: String) -> void:
	if not MOODS.has(new_mood):
		push_warning("MenuBackdrop: unknown mood '%s'" % new_mood)
		return
	mood = new_mood
	if _built:
		_apply_mood()


## The featured hero named by `--backdrop-hero`, else the player's hero.
static func hero_from_args(args: PackedStringArray) -> String:
	var i := args.find(HERO_FLAG)
	if i >= 0 and i + 1 < args.size() and HEROES.has(args[i + 1]):
		return args[i + 1]
	return PLAYER_HERO


## Put this hero in front and step the other two back; re-poses the three models in place (no rebuild).
func set_featured_hero(id: String) -> void:
	if not HEROES.has(id):
		push_warning("MenuBackdrop: unknown hero '%s'" % id)
		return
	featured_hero = id
	if _built:
		_pose_crew()


## The model of a hero id.
func hero_model(id: String) -> LowPolyModel:
	match id:
		"wick": return wick
		"gasket": return gasket
		"rebar": return rebar
	return null


## Where a hero stands now (its position), for tests and the lab.
func hero_spot(id: String) -> Vector3:
	var m := hero_model(id)
	return m.position if m != null else Vector3.ZERO


## The camera's sway about its focus at time t (degrees): a slow drift, so the shot is never still.
static func yaw_at(t: float) -> float:
	return SWAY_DEG * sin(t * SWAY_SPEED)


## Number of positional lights (omni and spot) that are switched on: the scene's lighting cost.
func light_count() -> int:
	var n := 0
	for l in find_children("*", "Light3D", true, false):
		var light := l as Light3D
		if light.visible and light.light_energy > 0.0 and not (light is DirectionalLight3D):
			n += 1
	return n


func _place_camera(t: float) -> void:
	var offset := CAM_POS - CAM_LOOK
	offset = offset.rotated(Vector3.UP, deg_to_rad(yaw_at(t)))
	camera.position = CAM_LOOK + offset + Vector3(0.0, sin(t * 0.17) * 0.12, 0.0)
	camera.look_at(CAM_LOOK, Vector3.UP)


# --- World ------------------------------------------------------------------------------------------

func _build_map() -> void:
	map = HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 16):
		var w := Hex.to_world(c)
		var in_room := absf(w.x) <= WALL_X + 0.5 and w.z >= WALL_Z - 0.6 and w.z <= 13.0
		var in_chamber := Vector2(w.x - GATE_AT.x, w.z - GATE_AT.z).length() <= 3.6 and w.z < WALL_Z
		if in_room or in_chamber:
			map.set_cell(c, 0).tag = "room:0"


## Stone-block walls (back + sides) with a breach the hellgate leaks through, timber posts and rafters.
func _build_walls() -> void:
	var s := LowPoly.Soup.new(808, 0.1)
	var bw := 1.15
	var bh := 0.56
	var rows := int(WALL_H / bh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for r in rows:
		var y := (float(r) + 0.5) * bh
		var off := 0.0 if r % 2 == 0 else bw * 0.5
		var x := -WALL_X - off
		while x < WALL_X + bw:
			var cx := x + bw * 0.5
			x += bw
			var d := Vector2((cx - BREACH.x) / BREACH_R.x, (y - BREACH.y) / BREACH_R.y).length()
			var jag := 0.18 * sin(cx * 5.3 + y * 3.1)
			if d < 1.0 + jag:
				continue
			var col: Color = STONE[rng.randi() % STONE.size()]
			var depth := 0.55 + rng.randf() * 0.08
			var push := 0.0
			if d < 1.45:
				push = rng.randf_range(-0.12, 0.06)     # loosened blocks around the breach
				col = col.lerp(Color(0.45, 0.2, 0.15), 0.25)
			Kit.box(s, Vector3(bw - 0.05, bh - 0.05, depth), Vector3(cx, y, WALL_Z - depth * 0.5 + push), col, Vector3(0, 0, rng.randf_range(-1.0, 1.0) * (6.0 if d < 1.45 else 0.6)))
		# side walls (front face toward the room)
		for side: float in [-1.0, 1.0]:
			var zz := WALL_Z - off
			while zz < 12.0:
				var cz := zz + bw * 0.5
				zz += bw
				var col2: Color = STONE[rng.randi() % STONE.size()]
				Kit.box(s, Vector3(0.6, bh - 0.05, bw - 0.05), Vector3(side * (WALL_X + 0.3), y, cz), col2)
	# rubble from the breach
	for i in 9:
		var a := rng.randf() * PI
		var p := Vector3(BREACH.x + cos(a) * rng.randf_range(0.6, 2.0), 0.12, WALL_Z + 0.2 + sin(a) * rng.randf_range(0.2, 1.3))
		s.merge(LowPoly.boulder(Vector3(0.28, 0.18, 0.24) * rng.randf_range(0.7, 1.4), 0, 0.15, STONE[i % 4], Kit.n()), LowPoly.at(p, Vector3(0, rng.randf() * 180, 0)))
	# glowing cracks running out of the breach
	for i in 7:
		var ang := -0.4 + float(i) * 0.5
		var start := Vector3(BREACH.x + cos(ang) * BREACH_R.x * 0.95, BREACH.y + sin(ang) * BREACH_R.y * 0.95, WALL_Z + 0.02)
		var len := rng.randf_range(0.7, 1.6)
		var end := start + Vector3(cos(ang), sin(ang), 0) * len + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), 0)
		Kit.rod(s, start, end, 0.045, 0.01, 4, Kit.glow(Color(1.0, 0.3, 0.08)))
	# timber posts and rafters
	for px: float in [-8.0, -2.4, 3.6, 11.4]:
		Kit.box(s, Vector3(0.5, WALL_H, 0.5), Vector3(px, WALL_H * 0.5, WALL_Z + 0.25), TIMBER)
		Kit.rod(s, Vector3(px, WALL_H - 0.3, WALL_Z + 0.3), Vector3(px, WALL_H - 0.3, 12.0), 0.22, 0.22, 4, TIMBER)
	Kit.box(s, Vector3(WALL_X * 2.0, 0.45, 0.5), Vector3(0, WALL_H - 0.25, WALL_Z + 0.25), TIMBER)
	add_child(Kit.mesh(s, 1.8, "Walls"))


func _build_gate() -> void:
	gate = HellgateModel.make(true)
	gate.name = "Hellgate"
	add_child(gate)
	gate.set_active(true)
	gate.position = GATE_AT
	gate.rotation.y = deg_to_rad(-15.0)
	_gate_light = gate.get_node_or_null("GateLight") as OmniLight3D
	# red light spilling through the breach into the garage
	var red := Kit.omni(self, Vector3(BREACH.x - 0.3, 1.6, WALL_Z + 1.2), Color(1.0, 0.22, 0.08), 3.4, 7.5)
	red.name = "BreachLight"
	_breach_flicker = Kit.Flicker.new()
	_breach_flicker.light = red
	_breach_flicker.base = red.light_energy
	_breach_flicker.amount = 0.2
	_breach_flicker.speed = 2.2
	add_child(_breach_flicker)
	# a hot red haze behind the hole so the breach reads at a glance
	var hs := LowPoly.Soup.new(5, 0.05)
	Kit.box(hs, Vector3(BREACH_R.x * 2.6, BREACH_R.y * 2.6, 0.05), Vector3(BREACH.x, BREACH.y, GATE_AT.z - 2.2), Kit.glow(Color(0.55, 0.06, 0.03)))
	add_child(Kit.mesh(hs, 0.0, "BreachHaze"))
	var embers := Kit.motes(Vector3(1.2, 1.2, 1.0), Color(1.0, 0.45, 0.12, 0.9), 36, 0.5)
	embers.position = Vector3(BREACH.x, 1.8, WALL_Z + 0.8)
	add_child(embers)
	# hazard tape across the breach (it will totally hold)
	Kit.put(self, DecorModels.build("hazard_tape"), Vector3(BREACH.x - 0.2, 0.0, WALL_Z + 1.3), -4.0, 1.1)


## The van on its chalk pentagram, side door open. VanModel's nose is +Z and its sliding door is on -X; turned 90
## degrees the nose points to +X and the open door faces the camera.
func _build_van() -> void:
	var circle := VanCircle.new(3.2)
	circle.settle()
	circle.position = VAN_AT
	add_child(circle)
	if circle.light != null:
		circle.light.visible = false     # one light fewer: the garage lights the circle
	_van_holder = Node3D.new()
	_van_holder.name = "VanHolder"
	_van_holder.position = VAN_AT
	_van_holder.rotation.y = deg_to_rad(VAN_YAW)
	add_child(_van_holder)
	van = VanModel.new()
	van.rotation.y = deg_to_rad(90.0)
	_van_holder.add_child(van)
	van.set_door_open(1.0)


func _build_crew() -> void:
	var to_cam := CAM_POS - CAM_LOOK
	to_cam.y = 0.0
	to_cam = to_cam.normalized()
	_face_yaw = rad_to_deg(atan2(-to_cam.x, -to_cam.z))
	wick = WickModel.new()
	gasket = GasketModel.new()
	rebar = RebarModel.new()
	for m: LowPolyModel in [wick, gasket, rebar]:
		add_child(m)
	_pose_crew()


## Stand the featured hero at the front point and the other two at the supporting spots.
func _pose_crew() -> void:
	var others: Array[String] = []
	for id in HEROES:
		if id != featured_hero:
			others.append(id)
	var cab := ""
	for id in CAB_ORDER:
		if others.has(id):
			cab = id
			break
	var back := ""
	for id in others:
		if id != cab:
			back = id
	_place(featured_hero, SPOT_FRONT + Vector3(float(FRONT_NUDGE.get(featured_hero, 0.0)), 0.0, 0.0), YAW_FRONT)
	_place(cab, SPOT_CAB, YAW_CAB)
	_place(back, SPOT_BACK, YAW_BACK)


func _place(id: String, offset: Vector3, yaw: float) -> void:
	var m := hero_model(id)
	if m == null:
		return
	m.position = VAN_AT + offset
	m.rotation.y = deg_to_rad(_face_yaw + yaw)
	# after a bad job they slump: the weight forward onto the feet, a little askew
	var slump := mood == "after"
	m.rotation.x = deg_to_rad(-12.0) if slump else 0.0
	m.rotation.z = deg_to_rad(SLUMP_ROLL.get(id, 4.0)) if slump else 0.0


func _build_dressing() -> void:
	# Four torches burn (emissive flames); only two carry a light, the rest of the glow is the breach and the work lights.
	var torches: Array[Vector3] = [Vector3(-5.2, 2.9, WALL_Z), Vector3(-0.7, 2.9, WALL_Z), Vector3(11.4, 2.9, WALL_Z + 0.5), Vector3(-WALL_X, 2.9, 2.0)]
	for i in torches.size():
		var yaw := 90.0 if torches[i].x <= -WALL_X else 0.0
		var t := Kit.torch(31 + i, 2.6, i < 2)
		# the bracket's plate 2 cm proud of the stones (flush with the wall's face, it z-fought them)
		Kit.put(self, t, torches[i] + (Vector3(0.02, 0, 0) if yaw == 90.0 else Vector3(0, 0, 0.02)), yaw)
		if i < 2:
			_torches.append(t)
	# the dispatch sign and a couple of notices, tacked to the back wall
	var sign_node := Kit.paper_sign("24/7 EMERGENCY DISPATCH!\nWE FIX YOUR HEXES\nOR IT'S FREE!", Vector2(2.5, 1.35), 46)
	Kit.put(self, sign_node, Vector3(5.45, 3.15, WALL_Z + 0.04))
	sign_node.rotation.z = deg_to_rad(-2.5)
	var corn := Kit.paper_sign(_corn_text(), Vector2(1.1, 1.05), 34, Kit.PAPER_OLD)
	Kit.put(self, corn, Vector3(3.6, 3.5, WALL_Z + 0.53))
	corn.rotation.z = deg_to_rad(3.0)
	_corn_sign_node = corn
	for ch in corn.get_children():
		if ch is Label3D:
			_corn_sign_label = ch as Label3D
	var neon := Kit.neon("CAST", Color(1.0, 0.62, 0.15), 0.11, [], true)
	Kit.put(self, neon, Vector3(1.5, 5.4, WALL_Z + 0.12))
	var neon2 := Kit.neon("WE FIX HEXES", Color(1.0, 0.86, 0.6), 0.036, [7], false)
	Kit.put(self, neon2, Vector3(1.5, 4.55, WALL_Z + 0.12))
	var open_sign := Kit.neon("OPEN 24/7", Color(1.0, 0.18, 0.2), 0.06, [5], true)
	Kit.put(self, open_sign, Vector3(-WALL_X + 0.1, 3.9, 4.0), 90.0)
	# workbench with a monitor, barrels, crates, mail
	Kit.put(self, DecorModels.build("desk"), Vector3(-6.5, 0, WALL_Z + 0.7), 0.0)
	Kit.put(self, DecorModels.build("monitor", {"color": Color(0.35, 1.0, 0.6)}), Vector3(-6.8, 0.82, WALL_Z + 0.55), 10.0)
	Kit.put(self, DecorModels.build("office_chair"), Vector3(-6.2, 0, WALL_Z + 1.9), 160.0)
	for b: Vector3 in [Vector3(-3.9, 0, WALL_Z + 0.7), Vector3(-4.8, 0, WALL_Z + 1.0), Vector3(-4.2, 0, WALL_Z + 1.7)]:
		Kit.put(self, DecorModels.build("barrel"), b, b.x * 40.0)
	Kit.put(self, DecorModels.build("crate_stack"), Vector3(11.2, 0, -1.6), -80.0)
	Kit.put(self, DecorModels.build("crate_stack"), Vector3(11.0, 0, 1.2), -100.0)
	Kit.put(self, PackageModels.box("medium", 3), Vector3(-8.6, 0, 0.4), 20.0)
	Kit.put(self, PackageModels.box("small", 5), Vector3(-8.5, 0.6, 0.45), 35.0)
	Kit.put(self, PackageModels.box("long", 7), Vector3(-7.4, 0, 1.4), -15.0)
	Kit.put(self, DecorModels.build("wet_floor_sign"), Vector3(6.9, 0, 4.4), -30.0)


func _corn_text() -> String:
	return "JOBS SINCE LAST\nCORN INCIDENT\n%d" % corn_jobs


# --- Mood -------------------------------------------------------------------------------------------

## Apply the current mood: the grade, the key light, the few mood lights, torch and gate strength, the van's lights,
## and the "after" smoke and mess. Everything that only exists in one mood lives under _mood_root.
func _apply_mood() -> void:
	if _mood_root != null:
		remove_child(_mood_root)
		_mood_root.free()
	_mood_root = Node3D.new()
	_mood_root.name = "Mood"
	add_child(_mood_root)
	var night := mood == "night"
	var after := mood == "after"
	_reset_after_pieces()
	_grade(night, after)
	if key_light != null:
		key_light.light_energy = 0.22 if night else (0.38 if after else 0.5)
		key_light.light_color = Color(0.6, 0.72, 1.0) if night else Color(1.0, 0.86, 0.68)
		key_light.rotation_degrees = Vector3(-62, -20, 0)
	for t in _torches:
		var f := t.get_node_or_null("Flicker") as Kit.Flicker
		if f != null:
			f.base = 2.0 if night else (2.2 if after else 2.6)
	if _gate_light != null:
		_gate_light.light_energy = 6.0 if night else 2.2      # the portal stays the hottest thing at night
	if _breach_flicker != null:
		_breach_flicker.base = 8.0 if night else 3.4
	van.set_lights(1.0 if night else 0.0)
	var head := van.get_node_or_null("Chassis/HeadLight") as Light3D
	if head != null:
		head.visible = night
	if night:
		# night shift: the same overhead work lamp as dawn, as a warm pool of light on the crew and the van, under
		# the night ambient; no daylight through the grate. Torches, headlights and the portal do the rest.
		Kit.omni(_mood_root, VAN_AT + Vector3(-1.0, 4.4, 2.4), Color(1.0, 0.7, 0.42), 5.5, 9.5)
		Kit.omni(_mood_root, VAN_AT + Vector3(-0.6, 2.2, 3.6), Color(1.0, 0.72, 0.45), 3.0, 5.5)   # fills the crew's faces
		var lamp := SpotLight3D.new()
		lamp.position = VAN_AT + Vector3(-1.0, 6.5, 2.4)
		lamp.rotation_degrees = Vector3(-90, 0, 0)
		lamp.light_color = Color(1.0, 0.76, 0.5)
		lamp.light_energy = 24.0
		lamp.spot_range = 12.0
		lamp.spot_angle = 42.0
		lamp.spot_attenuation = 0.6
		lamp.shadow_enabled = false
		_mood_root.add_child(lamp)
		var cone := Kit.light_shaft(6.0, 0.6, 2.6, Color(1.0, 0.8, 0.55), 0.1)
		cone.position = VAN_AT + Vector3(-1.0, 3.6, 2.4)
		_mood_root.add_child(cone)
	else:
		# warm work light over the van, and a cool spot through the ceiling grate with dusty shafts
		_work_lamp = Kit.omni(_mood_root, VAN_AT + Vector3(-1.0, 4.4, 2.4), Color(1.0, 0.74, 0.46), 5.5 if not after else 4.2, 9.5)
		var sp := SpotLight3D.new()
		sp.position = VAN_AT + Vector3(-1.5, 11.0, 2.0)
		sp.rotation_degrees = Vector3(-78, 12, 0)
		sp.light_color = Color(0.72, 0.84, 1.0)
		sp.light_energy = 8.0 if not after else 5.0
		sp.spot_range = 18.0
		sp.spot_angle = 18.0
		sp.shadow_enabled = false
		_mood_root.add_child(sp)
		for i in 3:
			var shaft := Kit.light_shaft(12.0, 0.45 + 0.15 * float(i), 1.5 + 0.4 * float(i), Color(0.75, 0.86, 1.0), (0.16 + 0.04 * float(i)) * (1.0 if not after else 0.7))
			shaft.position = VAN_AT + Vector3(-1.4 + float(i) * 1.3, 6.2, 1.2 - float(i) * 0.6)
			shaft.rotation_degrees = Vector3(10, 0, -12 + float(i) * 3.0)
			_mood_root.add_child(shaft)
	var motes := Kit.motes(Vector3(5, 3, 4), Color(1.0, 0.85, 0.6, 0.7), 90, 0.12)
	motes.position = VAN_AT + Vector3(-1, 2.5, 1)
	_mood_root.add_child(motes)
	if after:
		_after_job()


## Undo what the after mood does to the pieces that outlive the mood node (the crew, the van's door, the corn sign), so
## switching back to dawn or night leaves them as built. Also repositions the crew for the mood.
func _reset_after_pieces() -> void:
	for n in _crew_extras:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_crew_extras.clear()
	After.clean_crew([wick, gasket, rebar])
	_work_lamp = null
	van.door.rotation = Vector3.ZERO
	van.set_door_open(1.0)
	if _corn_sign_node != null:
		_corn_sign_node.scale = Vector3.ONE
		_corn_sign_node.rotation.z = deg_to_rad(3.0)
	if _corn_sign_label != null:
		_corn_sign_label.modulate = Kit.INK
	_pose_crew()


## The colour grade: the Environment's own adjustments plus a 1-D lookup table (a per-channel tone curve), because
## the toon shader keeps a floor of brightness, so fewer lights alone never make a night.
func _grade(night: bool, after: bool) -> void:
	if environment == null:
		return
	var env := environment
	env.background_color = Color(0.02, 0.018, 0.02)
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.06, 0.05) if not after else Color(0.12, 0.07, 0.06)
	env.fog_density = 0.01 if not after else 0.014
	env.glow_intensity = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_brightness = 1.0
	env.adjustment_saturation = 1.08
	env.ambient_light_energy = 0.42
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.adjustment_color_correction = null
	if night:
		env.ambient_light_energy = 0.22
		env.ambient_light_color = Color(0.4, 0.5, 0.85)
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.15
		env.adjustment_saturation = 1.0
		# Darks sink to blue-black; highlights (the work lamp, torches, the portal) keep their warm colour.
		env.adjustment_color_correction = _night_curve()
	elif after:
		env.ambient_light_energy = 0.34
		env.adjustment_brightness = 0.92
		env.adjustment_saturation = 0.8
		env.adjustment_color_correction = _tone_curve(Color(1.0, 0.9, 0.8))


## Night: shadows and midtones pushed dark and blue, the top of the range left almost neutral, so point lights read
## as warm pools in a cold room instead of the whole frame being tinted blue.
static func _night_curve() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color.BLACK)
	g.set_color(1, Color(1.0, 0.97, 0.92))
	g.add_point(0.35, Color(0.12, 0.15, 0.26))
	g.add_point(0.7, Color(0.55, 0.55, 0.62))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 64
	return tex


## A per-channel tone curve from black to `top`: multiplies the image by that colour (a tint grade).
static func _tone_curve(top: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color.BLACK)
	g.set_color(1, top)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 64
	return tex


## "After a bad job" (the pieces are in after_job.gd): the corn bomb in the van roof and the popped hood over a fire, smoke
## columns, scorch marks, cobs and kernels, the invoice, the red 0, a failing lamp, the crew scuffed up.
func _after_job() -> void:
	# the van's own pieces: the side door hangs off its track
	van.door.rotation = Vector3(deg_to_rad(-5.0), 0.0, deg_to_rad(8.0))
	van.door.position += Vector3(-0.04, -0.06, 0.0)
	var vroot := Node3D.new()
	vroot.name = "VanDamage"
	vroot.transform = _van_holder.transform * van.transform
	_mood_root.add_child(vroot)
	After.van_damage(vroot)
	After.mess(_mood_root, VAN_AT, WALL_Z)
	# smoke: a thick column from under the hood, a thinner one from the hole in the roof
	var hood_smoke := After.smoke("Smoke", 70, 0.4, 1.5, 2.2, 0.8, 1.3)
	hood_smoke.position = vroot.transform * Vector3(0.0, 1.45, 1.95)
	_mood_root.add_child(hood_smoke)
	var roof_smoke := After.smoke("RoofSmoke", 14, 0.25, 0.7, 1.1, 0.4, 0.7)
	roof_smoke.position = vroot.transform * Vector3(-0.1, 2.0, -1.3)
	_mood_root.add_child(roof_smoke)
	# the fire under the hood lights the cab and the smoke
	var fire := Kit.omni(_mood_root, vroot.transform * Vector3(0.0, 1.5, 2.2), Color(1.0, 0.42, 0.1), 2.6, 4.8)
	fire.name = "HoodFire"
	var fire_flicker := Kit.Flicker.new()
	fire_flicker.light = fire
	fire_flicker.base = fire.light_energy
	fire_flicker.amount = 0.35
	fire_flicker.speed = 11.0
	_mood_root.add_child(fire_flicker)
	# the work lamp is failing: a bare bulb on a cord, swinging a little, dimmed and flickering with it
	var bulb := After.hanging_bulb(Vector3(VAN_AT.x - 1.0, 9.0, VAN_AT.z + 2.4), 4.6)
	_mood_root.add_child(bulb)
	var swing := Kit.Swing.new()
	swing.amount_deg = 1.6
	swing.speed = 0.7
	bulb.add_child(swing)
	var lamp := After.FailingLamp.new()
	lamp.light = _work_lamp
	lamp.base = 4.4
	var bm := bulb.get_node_or_null("Bulb") as MeshInstance3D
	if bm != null:
		lamp.bulb_mat = bm.material_override as ShaderMaterial
	_mood_root.add_child(lamp)
	var ash := After.ash(Vector3(7.0, 0.2, 5.0))
	ash.position = VAN_AT + Vector3(2.0, 7.0, 1.0)
	_mood_root.add_child(ash)
	# story: the invoice on the wall, the corn sign reading a huge red 0
	After.invoice(_mood_root, Vector3(5.3, 5.55, WALL_Z + 0.05))
	if _corn_sign_node != null:
		_corn_sign_node.scale = Vector3.ONE * 1.5
		_corn_sign_node.rotation.z = deg_to_rad(9.0)
		_corn_sign_label.modulate = After.SOOT_RED
		After.corn_sign_zero(_mood_root, _corn_sign_node, "0")
	_crew_extras = After.dress_crew([wick, gasket, rebar])

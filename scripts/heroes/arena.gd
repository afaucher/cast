class_name Arena
extends Node3D
## A small self-contained test arena for heroes, allies and spells: a hex disc
## with raised platforms (+1 walk, +2 climb, +3 behind stairs), walls,
## training dummies and one slow punching grunt. Everything is built in code.
##
## Run:  .\run.ps1 -- --scene res://scenes/arena.tscn [options]
##   --spells heal,fireball   skip the picker and use these two spells
##   --shot <abs png>         save a screenshot after a few frames, then quit
##   --autocast <spell>       with --shot: cast that spell first (aimed at a dummy)
##   --shot-after <seconds>   with --autocast: game seconds between cast and shot (default 0.5)
##   --show-picker            with --shot: screenshot the spell picker
## Controls: WASD move, mouse aim, LMB melee, RMB bolt, 1/2 cast slots, F6 / F7 movement feel / interpolation (MoveFeel),
## Enter = type a spell ("heal", "cast fireball"), mouse wheel zoom, F5 restart.

const ARENA_RADIUS := 8
const WALL_LEVEL := 6
const DEFAULT_SPELLS: Array[String] = ["heal", "corn"]
const SHOT_FRAME := 50
const AUTOCAST_FRAME := 40

# Terrain tint per height level (0..3), walls and stairs.
const LEVEL_COLORS: Array[Color] = [
	Color(0.36, 0.5, 0.32), Color(0.58, 0.52, 0.34), Color(0.62, 0.42, 0.3), Color(0.5, 0.4, 0.58),
]
const WALL_COLOR := Color(0.33, 0.31, 0.36)
const STAIRS_COLOR := Color(0.72, 0.66, 0.5)
const BORDER_COLOR := Color(0.1, 0.12, 0.1)
const BORDER_INSET := 0.94

var player: Hero
var allies: Array[Hero] = []
var controller: PlayerController
var hud: Hud
var rig: CameraRig
var picker: SpellPicker

var _shot_path := ""
var _autocast := ""
var _shot_after := 0.5
var _frame := 0
var _started := false
var _dummies: Array[TrainingDummy] = []


func _ready() -> void:
	InputSetup.ensure_actions()
	MoveFeel.boot()
	var args := OS.get_cmdline_user_args()
	var spells := _arg_list(args, "--spells")
	_shot_path = _arg_value(args, "--shot")
	_autocast = _arg_value(args, "--autocast")
	if _arg_value(args, "--shot-after") != "":
		_shot_after = float(_arg_value(args, "--shot-after"))
	var want_picker := args.has("--show-picker")

	var map := build_map()
	GameWorld.begin(map, self, 1234)
	_build_scenery(map)
	_spawn_heroes()

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = player
	rig.global_position = player.global_position
	controller.camera = rig.camera

	hud = Hud.new()
	add_child(hud)
	controller.hud = hud
	hud.console_submitted.connect(_on_console)
	player.died.connect(_on_player_died)

	if _shot_path != "" and not want_picker and spells.is_empty():
		spells = []
		spells.append_array(DEFAULT_SPELLS)
	if _autocast != "" and not spells.has(_autocast):
		spells = []
		spells.append(_autocast)
		spells.append("heal" if _autocast != "heal" else "fireball")
	if spells.is_empty() or want_picker:
		_show_picker()
	else:
		_start(spells)


func _exit_tree() -> void:
	if GameWorld.root == self:
		GameWorld.end()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if not _started:
		if _shot_path != "" and _frame == SHOT_FRAME:
			_take_shot()
		return
	if _autocast != "" and _frame == AUTOCAST_FRAME:
		controller.cast_spell(_autocast, 1.0)
	if _shot_path != "":
		var when := SHOT_FRAME if _autocast == "" else AUTOCAST_FRAME + int(_shot_after * 60.0)
		if _frame == when:
			_take_shot()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


# --- Flow -----------------------------------------------------------------------------------

func _show_picker() -> void:
	picker = SpellPicker.new()
	hud.add_overlay(picker)
	picker.picked.connect(func(chosen: Array[String]) -> void:
		picker.queue_free()
		picker = null
		_start(chosen))
	controller.enabled = false


func _start(slots: Array[String]) -> void:
	player.spell_slots = slots
	hud.bind(player, allies)
	hud.enable_console()
	controller.enabled = true
	_spawn_monsters()
	rig.aim_source = controller.aim_point
	MoveFeelTag.attach(self, player)   # (F6 / F7: the movement-feel A/B works here too)
	if _shot_path != "":
		controller.aim_override = _dummies[0].global_position
	_started = true


func _on_console(text: String) -> void:
	var id := SpellBook.find_in_text(text)
	if id == "":
		hud.show_fizzle(text, "that is no spell")
		SpellBook.fizzle(player)
		return
	controller.cast_spell(id, 1.0)


func _on_player_died() -> void:
	hud.show_message("You died. F5 to restart", Color(1.0, 0.4, 0.35))


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_shot_path)
	print("Arena: screenshot ", _shot_path, " err=", err)
	get_tree().quit()


# --- Spawning ---------------------------------------------------------------------------------

func _spawn_heroes() -> void:
	player = HeroFactory.spawn_hero(Vector2i(0, 0), "Aria", Color(0.3, 0.55, 0.95), "sword")
	var no_spells: Array[String] = []
	controller = HeroFactory.make_player(player, no_spells)
	var brom := HeroFactory.spawn_hero(Vector2i(-1, 1), "Brom", Color(0.85, 0.5, 0.25), "sword")
	HeroFactory.make_ally(brom, player, false, 2.4)
	var wren := HeroFactory.spawn_hero(Vector2i(1, 1), "Wren", Color(0.7, 0.4, 0.85), "staff")
	HeroFactory.make_ally(wren, player, true, 3.9)
	allies = [brom, wren]


func _spawn_monsters() -> void:
	for cell in [Vector2i(3, -3), Vector2i(-4, -3), Vector2i(4, -1), Vector2i(-1, 5)]:
		_dummies.append(_spawn_dummy(cell, TrainingDummy.Mode.STATIC))
	_dummies.append(_spawn_dummy(Vector2i(6, -5), TrainingDummy.Mode.WALKER))


func _spawn_dummy(cell: Vector2i, mode: TrainingDummy.Mode) -> TrainingDummy:
	var d := TrainingDummy.new()
	d.mode = mode
	var g := GameWorld.map.ground_level(Hex.to_world(cell))
	GameWorld.spawn(d, Hex.to_world(cell, 0.0 if is_nan(g) else g))
	d.snap_to_ground()
	return d


# --- Terrain ------------------------------------------------------------------------------------

## The arena layout: flat disc, wall ring, platforms +1/+2/+3 (the +3 one via stairs), ruins.
static func build_map() -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, ARENA_RADIUS):
		m.set_cell(c, 0)
	for c in Hex.ring(Vector2i.ZERO, ARENA_RADIUS + 1):
		m.set_cell(c, WALL_LEVEL, HexMap.Tile.WALL)
	for c in Hex.range_cells(Vector2i(4, -1), 1):      # +1: just walk up
		m.set_cell(c, 1)
	for c in Hex.range_cells(Vector2i(-5, 1), 1):      # +2: slow climb
		m.set_cell(c, 2)
	for c in Hex.range_cells(Vector2i(0, -6), 1):      # +3: too high, use the stairs
		m.set_cell(c, 3)
	m.set_stairs(Vector2i(0, -4), 0, 2, 3)             # climbs toward (0,-5)
	for c in [Vector2i(-3, 4), Vector2i(-2, 4), Vector2i(-4, 5), Vector2i(3, 2), Vector2i(4, 2)]:
		m.set_cell(c, WALL_LEVEL, HexMap.Tile.WALL)
	return m


func _build_scenery(map: HexMap) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = build_terrain_mesh(map)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	add_child(mi)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.85)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


## One mesh for the whole map: flat-shaded hex prisms with dark borders, ramps for stairs.
static func build_terrain_mesh(map: HexMap) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		var center := Hex.to_world(c)
		var top := _top_color(c, cell)
		var side := top.darkened(0.45)
		var heights: Array[float] = []
		for i in 6:
			var inner_pt := center + Hex.corner(i) * 0.98
			heights.append(map.ground_height(inner_pt) if cell.type == HexMap.Tile.STAIRS else cell.level * Hex.LEVEL_HEIGHT)
		var corners: Array[Vector3] = []
		var insets: Array[Vector3] = []
		for i in 6:
			corners.append(center + Hex.corner(i) + Vector3.UP * heights[i])
			insets.append(center + Hex.corner(i) * BORDER_INSET + Vector3.UP * heights[i])
		var ctop := center + Vector3.UP * ((heights[0] + heights[3]) * 0.5)
		# Top face (inset fan) and the border ring.
		for i in 6:
			var j := (i + 1) % 6
			var n := (insets[j] - ctop).cross(insets[i] - ctop).normalized()
			if n.y < 0.0:
				n = -n
			_tri(st, ctop, insets[i], insets[j], n, top)
			_quad(st, insets[i], corners[i], corners[j], insets[j], n, BORDER_COLOR)
		# Sides where the neighbor is lower or missing.
		for i in 6:
			var j := (i + 1) % 6
			var nb: HexMap.Cell = map.cells.get(c + Hex.DIRS[(6 - i) % 6])
			var floor_y := -1.0 if nb == null else nb.level * Hex.LEVEL_HEIGHT
			if nb != null and nb.type == HexMap.Tile.STAIRS:
				floor_y = nb.level * Hex.LEVEL_HEIGHT
			var ya := minf(floor_y, heights[i])
			var yb := minf(floor_y, heights[j])
			if heights[i] - ya < 0.01 and heights[j] - yb < 0.01:
				continue
			var out := Vector3(cos(deg_to_rad(60.0 * i)), 0, sin(deg_to_rad(60.0 * i)))
			var a := center + Hex.corner(i)
			var b := center + Hex.corner(j)
			_quad(st, a + Vector3.UP * heights[i], b + Vector3.UP * heights[j], b + Vector3.UP * yb, a + Vector3.UP * ya, out, side)
	return st.commit()


static func _top_color(c: Vector2i, cell: HexMap.Cell) -> Color:
	var base: Color
	if cell.type == HexMap.Tile.WALL:
		base = WALL_COLOR
	elif cell.type == HexMap.Tile.STAIRS:
		base = STAIRS_COLOR
	else:
		base = LEVEL_COLORS[clampi(cell.level, 0, LEVEL_COLORS.size() - 1)]
	var k := 0.93 + 0.05 * float(posmod(c.x * 7 + c.y * 13, 3))
	return Color(base.r * k, base.g * k, base.b * k)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	for p in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(st, a, b, c, n, col)
	_tri(st, a, c, d, n, col)


# --- Args ---------------------------------------------------------------------------------------

static func _arg_value(args: PackedStringArray, key: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


static func _arg_list(args: PackedStringArray, key: String) -> Array[String]:
	var out: Array[String] = []
	for s in _arg_value(args, key).split(",", false):
		if SpellBook.has_spell(s.strip_edges().to_lower()):
			out.append(s.strip_edges().to_lower())
	return out

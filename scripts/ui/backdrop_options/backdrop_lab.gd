extends Node3D
## Backdrop lab: the 3D menu backdrops on their own, with an optional mock menu panel for judging the
## composition. Scene: scenes/backdrop_lab.tscn. See docs/design/ui-theme-options.md ("As built").
##
##   godot --path . -- --scene res://scenes/backdrop_lab.tscn --option garage --shot <abs.png> --shot-after 2
##
## --option <id>     garage (default; the real MenuBackdrop) | storefront (the title-screen prototype, not used by
##                   the game yet)
## --mood <id>       garage: dawn | night | after (default: from context, as in the menu)   storefront: night | rain
## --hero <id>       garage: the hero in front, wick | gasket | rebar (default: the player's hero, Wick)
## --board           garage: lay the real JobBoard over it, as the game does (backdrop_behind), for screenshots
## --board-seed <n>  with --board: the board's seed (default 7); the offers are ContractBoard.offers(seed)
## --van <id>        storefront only: real (default) | stand-in
## --clean           no overlay (no PROTOTYPE tag, no mock menu panel): for use behind HTML mockups
## --shot <png>      save a screenshot after --shot-after seconds (default 2) and quit
## --shot-after <s>

const STOREFRONT := "res://scripts/ui/backdrop_options/storefront_backdrop.gd"
const OPTIONS: Array[String] = ["garage", "storefront"]
const TITLES := {
	"garage": "THE GARAGE",
	"storefront": "THE STOREFRONT",
}

var option := "garage"
var opts: Dictionary = {}
var backdrop: Node3D


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	option = _arg(a, "--option", "garage")
	if not OPTIONS.has(option):
		push_warning("backdrop_lab: unknown --option %s, using garage" % option)
		option = "garage"
	opts = {"mood": _arg(a, "--mood", ""), "van": _arg(a, "--van", "real")}
	if str(opts["mood"]) == "":
		opts.erase("mood")
	match option:
		"garage":
			var garage := MenuBackdrop.new()
			if opts.has("mood"):
				garage.mood = str(opts["mood"])
			garage.featured_hero = _arg(a, "--hero", "")
			backdrop = garage
		_:
			var script: GDScript = load(STOREFRONT)
			backdrop = script.new() as Node3D
			backdrop.call("setup", opts)
	backdrop.name = "Backdrop"
	add_child(backdrop)
	if option == "garage" and a.has("--board"):
		_real_board(ContractBoard.offers(int(_arg(a, "--board-seed", "7"))))
	if not a.has("--clean") and not a.has("--board"):
		_overlay()
	var shot := _arg(a, "--shot")
	if shot != "":
		_shot_later(shot, float(_arg(a, "--shot-after", "2")))


## The real job board over the garage, wired as the game wires it (board.backdrop_behind).
func _real_board(offers: Array[ContractRun]) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var board := JobBoard.new(offers)
	board.backdrop_behind = true
	layer.add_child(board)


static func _arg(a: PackedStringArray, key: String, fallback: String = "") -> String:
	var i := a.find(key)
	if i >= 0 and i + 1 < a.size():
		return a[i + 1]
	return fallback


func _shot_later(path: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[backdrop_lab] %d draw calls, %d objects, %d primitives, %.0f fps" % [
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
		int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		Engine.get_frames_per_second()])
	print("[backdrop_lab] screenshot saved: ", path)
	get_tree().quit()


## The PROTOTYPE tag and a rough paper menu block on the left third, so the composition is judged with the
## menu where it will sit. The block is a placeholder, not one of the menu style options.
func _overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var tag := Label.new()
	var mood := str(opts.get("mood", ""))
	tag.text = "BACKDROP LAB  ·  %s%s" % [str(TITLES[option]), ("  ·  " + mood) if mood != "" else ""]
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	tag.add_theme_constant_override("outline_size", 6)
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tag.position = Vector2(-420, 18)
	tag.size = Vector2(400, 30)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(tag)

	var paper := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.89, 0.77, 0.94)
	sb.border_color = Color(0.55, 0.45, 0.3, 0.9)
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(6, 8)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	paper.add_theme_stylebox_override("panel", sb)
	paper.position = Vector2(70, 120)
	paper.size = Vector2(420, 560)
	paper.rotation = deg_to_rad(-1.2)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(paper)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	paper.add_child(v)
	var ink := Color(0.13, 0.12, 0.14)
	v.add_child(_lbl("CAST", 56, ink))
	v.add_child(_lbl("LICENSED BUDGET SORCERY  ·  1-800-LOW-MANA", 14, Color(0.45, 0.2, 0.15)))
	var rule := ColorRect.new()
	rule.color = Color(0.3, 0.25, 0.2, 0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	for item: String in ["[x]  New contract", "[x]  Voice setup", "[  ]  Supply house", "[  ]  Crew locker", "[  ]  Options", "[  ]  Clock out"]:
		v.add_child(_lbl(item, 28, ink))
	v.add_child(_lbl("(mock menu, for composition only)", 13, Color(0.4, 0.36, 0.3)))


static func _lbl(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

extends Node3D
## The POC game: pick 2 spells -> procedural hex dungeon -> fight to the exit,
## casting spells by voice. Wires together DungeonGen/HexMapView (terrain),
## heroes/spells/HUD (HeroFactory, PlayerController, Hud, CameraRig),
## MonsterFactory (monsters) and VoiceCaster/VoiceDebugPanel (voice).
##
## Command line (after `--`):
##   --seed N            dungeon seed (default: random)
##   --spells a,b        skip the picker (e.g. heal,corn)
##   --no-mic            don't open the mic / load the model (typed casts only)
##   --shot <png>        save a screenshot after --shot-after game seconds (default 3) and quit
##   --autocast <id>     cast a spell once, 1 s in (for screenshots)
## Keys: F1 debug panel, F5 new dungeon, Enter = type an incantation.

const ALL_SPELLS: PackedStringArray = ["heal", "fireball", "armor", "corn"]
const PLAYER_COLOR := Color(0.3, 0.55, 0.95)
const ROOM_BUDGET_BASE := 5
const ROOM_BUDGET_PER_ROOM := 1
const ROOM_BUDGET_PER_FLOOR := 3

## Survive scene reloads (F5 / next floor).
static var _seed := -1
static var _floor := 1
static var _spells: Array[String] = []

var opts := {}
var map: HexMap
var player: Hero
var allies: Array[Hero] = []
var controller: PlayerController
var rig: CameraRig
var hud: Hud
var voice: VoiceCaster
var debug_layer: CanvasLayer
var debug_panel: Control
var game_stats: Label
var subtitle: Label
var _subtitle_tween: Tween
var _ended := false
var _stats_timer := 0.0
var _kills := 0
var _exit_cell := Vector2i(1 << 20, 1 << 20)


func _ready() -> void:
	InputSetup.ensure_actions()
	_parse_args()
	_build_world()
	_setup_voice()
	if _spells.is_empty():
		_show_picker()
	else:
		_start()


func _exit_tree() -> void:
	if GameWorld.actor_died.is_connected(_on_actor_died):
		GameWorld.actor_died.disconnect(_on_actor_died)
	if GameWorld.root != null and GameWorld.root.get_parent() == self:
		GameWorld.end()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--seed": opts["seed"] = int(nxt)
			"--spells": opts["spells"] = nxt
			"--no-mic": opts["no_mic"] = true
			"--shot": opts["shot"] = nxt
			"--shot-after": opts["shot_after"] = float(nxt)
			"--autocast": opts["autocast"] = nxt
	if _seed < 0:
		_seed = int(opts.get("seed", randi() % 100000))
	if _spells.is_empty() and opts.has("spells"):
		for s in str(opts["spells"]).split(","):
			var id := s.strip_edges()
			if id in ALL_SPELLS and not _spells.has(id):
				_spells.append(id)


# --- World --------------------------------------------------------------------

func _build_world() -> void:
	map = DungeonGen.generate(_seed)
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, _seed)
	GameWorld.actor_died.connect(_on_actor_died)

	var view := HexMapView.new()
	view.name = "Terrain"
	add_child(view)
	view.build(map)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)

	var exits := map.cells_with_tag("exit")
	if not exits.is_empty():
		_exit_cell = exits[0]

	# Heroes: player on the start cell, allies on free neighbors.
	var start: Vector2i = map.cells_with_tag("start")[0]
	player = HeroFactory.spawn_hero(start, "You", PLAYER_COLOR, "sword")
	var none: Array[String] = []
	controller = HeroFactory.make_player(player, none)
	var spots := _free_cells_near(start, 2)
	var brom := HeroFactory.spawn_hero(spots[0], "Brom", Color(0.85, 0.5, 0.25), "sword")
	HeroFactory.make_ally(brom, player, false, 2.4)
	var wren := HeroFactory.spawn_hero(spots[mini(1, spots.size() - 1)], "Wren", Color(0.7, 0.4, 0.85), "staff")
	HeroFactory.make_ally(wren, player, true, 3.9)
	allies = [brom, wren]
	player.died.connect(func() -> void: _end("You died\nF5 for a new dungeon", Color(1.0, 0.4, 0.35)))

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = player
	rig.snap()
	controller.camera = rig.camera
	var reticle := AimReticle.new()
	reticle.controller = controller
	add_child(reticle)

	hud = Hud.new()
	add_child(hud)
	controller.hud = hud
	hud.console_submitted.connect(_on_console)


func _free_cells_near(c: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var base: int = map.get_cell(c).level
	for n in Hex.range_cells(c, radius):
		var cell: HexMap.Cell = map.get_cell(n)
		if n != c and cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - base) <= 1:
			out.append(n)
	if out.is_empty():
		out.append(c)
	return out


## One pack per room except the start room; later rooms and floors get bigger budgets.
func _populate_monsters() -> void:
	var rooms := {}
	for c: Vector2i in map.cells:
		var tag: String = map.cells[c].tag
		if tag.begins_with("room:"):
			if not rooms.has(tag):
				var cells: Array[Vector2i] = []
				rooms[tag] = cells
			rooms[tag].append(c)
	var start: Vector2i = map.cells_with_tag("start")[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 31 + _floor
	var keys := rooms.keys()
	keys.sort()
	for tag: String in keys:
		var cells: Array[Vector2i] = rooms[tag]
		if _room_has_start(cells, start):
			continue
		var idx := int(tag.trim_prefix("room:"))
		var budget := ROOM_BUDGET_BASE + ROOM_BUDGET_PER_ROOM * idx + ROOM_BUDGET_PER_FLOOR * (_floor - 1)
		MonsterFactory.spawn_pack(cells, budget, rng)


func _room_has_start(cells: Array[Vector2i], start: Vector2i) -> bool:
	for c in cells:
		if Hex.distance(c, start) <= 3:
			return true
	return false


# --- Voice --------------------------------------------------------------------

func _setup_voice() -> void:
	voice = VoiceCaster.new()
	voice.name = "VoiceCaster"
	add_child(voice)
	voice.spell_spoken.connect(_on_spell_spoken)
	voice.spell_fizzled.connect(_on_spell_fizzled)
	if voice.has_signal("heard"):
		voice.connect("heard", _on_heard)
	if voice.has_signal("trigger_word_changed"):
		voice.connect("trigger_word_changed", func(w: String) -> void: hud.set_trigger_word(w))

	debug_layer = CanvasLayer.new()
	debug_layer.layer = 50
	add_child(debug_layer)
	debug_panel = VoiceDebugPanel.new()
	debug_layer.add_child(debug_panel)
	debug_panel.attach(voice)
	debug_panel.visibility_changed.connect(_fit_hud_to_panel)

	game_stats = Label.new()
	game_stats.add_theme_font_size_override("font_size", 13)
	game_stats.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	game_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if debug_panel.has_method("add_section"):
		debug_panel.add_section("GAME", game_stats)
	else:
		debug_layer.add_child(game_stats)

	# What the recognizer heard, verbatim, as a subtitle (even with the panel hidden).
	subtitle = Label.new()
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	subtitle.add_theme_constant_override("outline_size", 6)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.anchor_left = 0.15
	subtitle.anchor_right = 0.6
	subtitle.anchor_top = 0.74
	subtitle.anchor_bottom = 0.74
	hud.add_overlay(subtitle)

	_fit_hud_to_panel()
	var ok := false
	if not opts.get("no_mic", false):
		ok = voice.start(ALL_SPELLS)
	if voice.has_method("get_trigger_word"):
		hud.set_trigger_word(voice.call("get_trigger_word"))
	_log("voice: %s" % ("listening" if ok else "no mic/model - type with Enter"), Color(0.6, 0.9, 1.0))


func _fit_hud_to_panel() -> void:
	var inset := VoiceDebugPanel.PANEL_WIDTH if debug_panel.visible else 0.0
	hud.set_right_inset(inset)
	rig.right_inset_px = inset


func _on_spell_spoken(id: String, power: float, heard: String) -> void:
	_cast(id, power, heard, voice.last_cast_accidental())


func _cast(id: String, power: float, heard: String, accidental: bool = false) -> void:
	if _ended or player == null or player.dead:
		_log("ignored %s: no living player" % id.to_upper(), Color(0.7, 0.7, 0.7))
		return
	var known := player.spell_slots.has(id)
	var cd := player.cooldown_left(id) if known else 0.0
	var tag := "ACCIDENTAL " if accidental else ""
	if controller.cast_spell(id, power):
		_log("%sCAST %s %d%%  (\"%s\")" % [tag, id.to_upper(), roundi(power * 100.0), heard], Color(0.5, 1.0, 0.6))
	elif not known:
		_log("%s%s not in slots (%s)" % [tag, id.to_upper(), ", ".join(player.spell_slots)], Color(1.0, 0.6, 0.3))
	elif cd > 0.0:
		_log("%s%s recharging %.1fs" % [tag, id.to_upper(), cd], Color(1.0, 0.8, 0.4))
	else:
		_log("%s refused" % id.to_upper(), Color(1.0, 0.5, 0.5))


func _on_spell_fizzled(heard: String, reason: String) -> void:
	if player and not player.dead:
		SpellBook.fizzle(player)
	hud.show_fizzle(heard, reason)
	_log("fizzle: %s (\"%s\")" % [reason, heard], Color(1.0, 0.75, 0.4))


func _on_heard(text: String, final: bool) -> void:
	if text.strip_edges() == "":
		return
	subtitle.text = "\"%s\"" % text.to_lower()
	subtitle.modulate = Color(1, 1, 1, 1) if final else Color(0.75, 0.75, 0.8, 0.9)
	if _subtitle_tween:
		_subtitle_tween.kill()
	if final:
		_subtitle_tween = create_tween()
		_subtitle_tween.tween_interval(2.0)
		_subtitle_tween.tween_property(subtitle, "modulate:a", 0.0, 0.6)


## Typed incantations go through the voice pipeline, so typed and spoken behave the same.
func _on_console(text: String) -> void:
	if text.strip_edges() != "":
		voice.inject_text(text)


# --- Flow ---------------------------------------------------------------------

func _show_picker() -> void:
	controller.enabled = false
	var picker := SpellPicker.new()
	if voice.has_method("get_trigger_word"):
		picker.set_trigger_word(voice.call("get_trigger_word"))
	hud.add_overlay(picker)
	picker.picked.connect(func(chosen: Array[String]) -> void:
		_spells = chosen.duplicate()
		picker.queue_free()
		_start())


func _start() -> void:
	player.spell_slots = _spells.duplicate()
	hud.bind(player, allies)
	hud.enable_console()
	controller.enabled = true
	_populate_monsters()
	hud.show_center("Floor %d\nReach the magenta exit" % _floor, Color(0.8, 0.9, 1.0), 2.0)
	_log("floor %d  seed %d  spells %s" % [_floor, _seed, ", ".join(_spells)], Color(0.6, 0.9, 1.0))
	if opts.has("autocast"):
		await get_tree().create_timer(1.0).timeout
		_cast(str(opts["autocast"]), 1.0, "autocast")
	if opts.has("shot"):
		_take_shot_later(str(opts["shot"]), float(opts.get("shot_after", 3.0)))


func _on_actor_died(a: Actor) -> void:
	if a.team == GameWorld.TEAM_MONSTERS:
		_kills += 1
		_log("%s died" % a.display_name, Color(0.7, 0.7, 0.7))
	else:
		_log("%s is down!" % a.display_name, Color(1.0, 0.45, 0.45))


func _end(msg: String, color: Color) -> void:
	if _ended:
		return
	_ended = true
	hud.show_center(msg, color)


func _physics_process(_delta: float) -> void:
	if _ended or player == null or player.dead:
		return
	if player.current_cell() == _exit_cell:
		_log("exit reached", Color(0.6, 1.0, 1.0))
		_floor += 1
		_end("Exit reached!\nF5 for floor %d" % _floor, Color(0.6, 1.0, 0.9))


func _process(delta: float) -> void:
	if voice:
		hud.set_mic_level(voice.get_level())
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		_update_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		_seed = randi() % 100000
		if not _ended or player.dead:
			_floor = 1
		get_tree().reload_current_scene()
	elif event.is_action_pressed("toggle_voice_debug"):
		debug_panel.visible = not debug_panel.visible


func _update_stats() -> void:
	if game_stats == null or player == null:
		return
	var lines: Array[String] = []
	lines.append("fps %d   floor %d   seed %d" % [Engine.get_frames_per_second(), _floor, _seed])
	var c := player.current_cell()
	var cell: HexMap.Cell = map.get_cell(c)
	lines.append("you  hp %d/%d  cell %s  level %s%s" % [player.hp, player.max_hp, c,
		str(cell.level) if cell else "?", "  CLIMBING" if player.climbing else ""])
	var cds: Array[String] = []
	for s in player.spell_slots:
		var cd := player.cooldown_left(s)
		cds.append("%s %s" % [s, "ready" if cd <= 0.0 else "%.1fs" % cd])
	if not cds.is_empty():
		lines.append("spells  " + "   ".join(cds))
	if player.has_modifier("armor"):
		lines.append("armor  dmg x%.2f" % player.damage_taken_mult())
	for a in allies:
		if is_instance_valid(a):
			lines.append("%s  hp %d%s" % [a.display_name, a.hp, "  DOWN" if a.dead else ""])
	var monsters := GameWorld.team_actors(GameWorld.TEAM_MONSTERS)
	var by_kind := {}
	var active := 0
	for m in monsters:
		var mon := m as Monster
		var k: String = mon.kind if mon else m.display_name
		by_kind[k] = int(by_kind.get(k, 0)) + 1
		if mon and (mon.state == Monster.State.CHASE or mon.state == Monster.State.ATTACK):
			active += 1
	var kinds: Array[String] = []
	for k: String in by_kind:
		kinds.append("%s %d" % [k, by_kind[k]])
	lines.append("monsters %d (%d fighting)  kills %d" % [monsters.size(), active, _kills])
	if not kinds.is_empty():
		lines.append("  " + "  ".join(kinds))
	lines.append("exit %d hexes away" % Hex.distance(c, _exit_cell))
	game_stats.text = "\n".join(lines)


func _log(text: String, color: Color = Color.WHITE) -> void:
	print("[game] ", text)
	if debug_panel and debug_panel.has_method("log_game"):
		debug_panel.log_game(text, color)


func _take_shot_later(path: String, after: float) -> void:
	await get_tree().create_timer(after).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[game] screenshot saved: ", path)
	get_tree().quit()

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
##   --proto-heroes      use the old capsule prototype bodies instead of the faceted crew
##   --spawn-near k,n[,cluster]  dev: also spawn n monsters of kind k (grunt/archer/brute/swarmer) near the player;
##                       --autocast then aims at them
##   --idle-monsters     dev: --spawn-near monsters ignore heroes until hurt
##   --stage-ledge       dev: raise a 7-cell tower +5 levels near the start; --spawn-near monsters stand on it
##   --give heal:9,corn:3  dev: slot these spells (up to 4) with these charges, after the picked two
##   --hold N            dev: ready slot N (1-4) at the start
##   --zoom S            dev: camera size (default 24; 6 is a close-up of the crew)
##   --focus rebar|gasket|dev  dev: the camera follows that ally (or the --spawn-near monsters) instead of the player
##   --give-allies a,b   dev: slot spell a for Rebar and b for Gasket (they only hold the component; allies do not cast)
##   --drop-near a,b     dev: put component pickups for spells a, b on the floor just ahead of the player
##   --slay-near         dev: 1.5 s in, kill the --spawn-near monsters (to watch their drops)
##   --kit-demo draw|hammer|fist  dev: at 0.8 s Wick starts drawing his bow on the --spawn-near monsters (a drawn shot
##                       fires 1.3 s later), or Gasket (hammer) / Rebar (fist) steps up to them and swings once
## Keys: F1 debug panel, F5 new dungeon, Enter = type an incantation.

## Every castable spell, straight from SpellBook (new spells need no change here).
static func all_spells() -> PackedStringArray:
	return PackedStringArray(SpellBook.ids())
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
var _dev_monsters: Array[Monster] = []   ## --spawn-near
var _stage_center := Vector2i(1 << 20, 1 << 20)   ## --stage-ledge tower center


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
			"--proto-heroes": opts["proto_heroes"] = true
			"--spawn-near": opts["spawn_near"] = nxt
			"--stage-ledge": opts["stage_ledge"] = true
			"--idle-monsters": opts["idle_monsters"] = true
			"--give": opts["give"] = nxt
			"--hold": opts["hold"] = int(nxt)
			"--give-allies": opts["give_allies"] = nxt
			"--zoom": opts["zoom"] = float(nxt)
			"--focus": opts["focus"] = nxt
			"--drop-near": opts["drop_near"] = nxt
			"--slay-near": opts["slay_near"] = true
			"--kit-demo": opts["kit_demo"] = nxt
	if _seed < 0:
		_seed = int(opts.get("seed", randi() % 100000))
	if _spells.is_empty() and opts.has("spells"):
		for s in str(opts["spells"]).split(","):
			var id := s.strip_edges()
			if id in all_spells() and not _spells.has(id):
				_spells.append(id)


# --- World --------------------------------------------------------------------

func _build_world() -> void:
	map = DungeonGen.generate(_seed)
	if opts.has("stage_ledge"):
		_stage_plateau()
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, _seed)
	GameWorld.actor_died.connect(_on_actor_died)

	var view := HexMapView.new()
	view.name = "Terrain"
	add_child(view)
	view.build(map)

	DungeonLook.apply(self, map)

	var exits := map.cells_with_tag("exit")
	if not exits.is_empty():
		_exit_cell = exits[0]

	# The crew: the player is Wick; Rebar and Gasket are AI allies on free neighbors.
	# Faceted low-poly models by default; --proto-heroes brings back the capsule bodies.
	var faceted: bool = not bool(opts.get("proto_heroes", false))
	var start: Vector2i = map.cells_with_tag("start")[0]
	player = HeroFactory.spawn_hero(start, "Wick", PLAYER_COLOR, "sword", WickModel.new() if faceted else null, HeroKit.WICK)
	var none: Array[String] = []
	controller = HeroFactory.make_player(player, none)
	var spots := _free_cells_near(start, 2)
	# Each hero's kit (HP, primary, secondary, quirks) comes from HeroKit; --proto-heroes keeps the kits.
	var rebar := HeroFactory.spawn_hero(spots[0], "Rebar", Color(0.85, 0.5, 0.25), "sword", RebarModel.new() if faceted else null, HeroKit.REBAR)
	HeroFactory.make_ally(rebar, player, false, 2.4)
	var gasket := HeroFactory.spawn_hero(spots[mini(1, spots.size() - 1)], "Gasket", Color(0.7, 0.4, 0.85), "sword", GasketModel.new() if faceted else null, HeroKit.GASKET)
	HeroFactory.make_ally(gasket, player, false, 3.9)
	allies = [rebar, gasket]
	player.died.connect(func() -> void: _end("You died\nF5 for a new dungeon", Color(1.0, 0.4, 0.35)))

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = player
	if opts.get("focus", "") == "rebar":
		rig.target = rebar
	elif opts.get("focus", "") == "gasket":
		rig.target = gasket
	if opts.has("zoom"):
		rig._zoom_target = float(opts["zoom"])
		rig.camera.size = float(opts["zoom"])
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
		ok = voice.start(all_spells())
	if voice.has_method("get_trigger_word"):
		hud.set_trigger_word(voice.call("get_trigger_word"))
	_log("voice: %s" % ("listening" if ok else "no mic/model - type with Enter"), Color(0.6, 0.9, 1.0))


func _fit_hud_to_panel() -> void:
	var inset := VoiceDebugPanel.PANEL_WIDTH if debug_panel.visible else 0.0
	hud.set_right_inset(inset)
	rig.right_inset_px = inset


func _on_spell_spoken(id: String, power: float, heard: String) -> void:
	_cast(id, power, heard, voice.last_cast_accidental())


## A voice (or typed) cast of any slotted spell: held or not, it goes through the controller, which
## checks charges (out of components fizzles with no cooldown), the cooldown (/1.15 on the held spell)
## and spends a charge. It never changes which slot is held.
func _cast(id: String, power: float, heard: String, accidental: bool = false) -> void:
	if _ended or player == null or player.dead:
		_log("ignored %s: no living player" % id.to_upper(), Color(0.7, 0.7, 0.7))
		return
	var known := player.spell_slots.has(id)
	var cd := player.cooldown_left(id) if known else 0.0
	var empty := known and player.charges_of(id) <= 0
	var tag := "ACCIDENTAL " if accidental else ""
	if controller.cast_spell(id, power):
		_log("%sCAST %s %d%%  (\"%s\")  %d left" % [tag, id.to_upper(), roundi(power * 100.0), heard, player.charges_of(id)], Color(0.5, 1.0, 0.6))
	elif not known:
		_log("%s%s not in slots (%s)" % [tag, id.to_upper(), ", ".join(player.spell_slots)], Color(1.0, 0.6, 0.3))
	elif empty:
		_log("%s%s fizzled: out of %s" % [tag, id.to_upper(), SpellBook.component_name(id)], Color(1.0, 0.5, 0.45))
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
	_apply_dev_loadout()
	hud.bind(player, allies)
	hud.enable_console()
	controller.enabled = true
	_populate_monsters()
	_spawn_near()
	if opts.has("shot"):   # keep screenshots clear of the banner and the voice panel
		debug_panel.visible = false
	else:
		hud.show_center("Floor %d\nReach the magenta exit" % _floor, Color(0.8, 0.9, 1.0), 2.0)
	_log("floor %d  seed %d  spells %s" % [_floor, _seed, ", ".join(_spells)], Color(0.6, 0.9, 1.0))
	_drop_near()
	if opts.get("focus", "") == "dev" and _dev_centroid() != Vector3.INF:
		var marker := Node3D.new()
		GameWorld.root.add_child(marker)
		marker.global_position = _dev_centroid()
		rig.target = marker
		rig.snap()
	if opts.has("slay_near"):
		get_tree().create_timer(1.5).timeout.connect(_slay_dev_monsters)
	if opts.has("kit_demo"):
		_kit_demo(str(opts["kit_demo"]))
	if opts.has("autocast"):
		await get_tree().create_timer(1.0).timeout
		var centre := _dev_centroid()
		if centre != Vector3.INF:
			controller.aim_override = centre
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
	for i in SpellComponents.SLOT_COUNT:
		var s := player.slot_spell(i)
		if s == "":
			lines.append("slot %d  -- empty --%s" % [i + 1, "   <- held" if player.held_slot == i else ""])
			continue
		var cd := player.cooldown_left(s)
		lines.append("slot %d  %s  x%d  %s  (cd %.1fs)%s" % [i + 1, s, player.charges_of(s), "ready" if cd <= 0.0 else "%.1fs" % cd,
				player.cooldown_total(s), "   <- HELD" if player.held_slot == i else ""])
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


## Dev flag --give: "heal:9,corn:3" slots (or tops up) those spells with those charges.
func _apply_dev_loadout() -> void:
	if opts.has("give"):
		for part in str(opts["give"]).split(","):
			var bits := part.strip_edges().split(":")
			var id := bits[0].strip_edges()
			var n := int(bits[1]) if bits.size() > 1 else SpellComponents.START_CHARGES
			if SpellBook.is_available(id):
				player.slot_in(id, n)
	if opts.has("hold"):
		player.select_slot(int(opts["hold"]) - 1)
	if opts.has("give_allies"):
		var ids := str(opts["give_allies"]).split(",")
		for i in mini(ids.size(), allies.size()):
			allies[i].slot_in(ids[i].strip_edges(), SpellComponents.START_CHARGES)


## Dev flag --drop-near: pickups for the listed spells, right next to the player.
func _drop_near() -> void:
	if not opts.has("drop_near"):
		return
	var ids := str(opts["drop_near"]).split(",")
	# The first one lies just outside the collect radius but inside the swap radius, so a hero with
	# full slots is offered the swap at once; the rest follow in a row.
	var base := player.global_position + Vector3(0.9, 0.0, 0.55)
	for i in ids.size():
		var id := ids[i].strip_edges()
		var p := ComponentPickup.drop(id, SpellComponents.PICKUP_CHARGES, base + Vector3(0.0, 0.0, 1.4 * i))
		_log("drop-near: %s %s" % [id, "ok" if p != null else "no floor"], Color(0.8, 0.8, 1.0))


## Dev flag --kit-demo: show one hero's primary / secondary on the --spawn-near monsters (screenshots).
func _kit_demo(kind: String) -> void:
	for ally in allies:   # only the demo hero acts
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
	await get_tree().create_timer(0.8).timeout
	var centre := _dev_centroid()
	if centre == Vector3.INF:
		return
	if kind == "draw":
		controller.enabled = false   # no mouse button is held, so the controller would release at once
		player.face_point(centre)
		player.start_draw()
		await get_tree().create_timer(1.3).timeout
		player.release_draw(centre - player.global_position)
		return
	var hero: Hero = allies[1] if kind == "hammer" else allies[0]
	var away := (centre - player.global_position)
	away.y = 0.0
	away = away.normalized()
	var spot := centre - away * (hero.melee_reach - 0.25)
	hero.global_position = Vector3(spot.x, hero.global_position.y, spot.z)
	hero.snap_to_ground()
	hero.face_point(centre)
	hero.melee(away)


func _slay_dev_monsters() -> void:
	for m in _dev_monsters:
		if is_instance_valid(m) and not m.dead:
			m.die()


## Dev flag --spawn-near kind,n: n extra monsters of `kind` on open floor 4-5 cells from the player.
func _spawn_near() -> void:
	if not opts.has("spawn_near"):
		return
	var parts := str(opts["spawn_near"]).split(",")
	var kind := parts[0].strip_edges()
	var n := int(parts[1]) if parts.size() > 1 else 3
	if map.has_cell(_stage_center):
		for c in Hex.ring(_stage_center, 1):
			if _dev_monsters.size() >= n:
				break
			var tm := MonsterFactory.spawn(kind, c)
			if tm != null:
				_dev_monsters.append(tm)
		_log("spawn-near: %d %s on the tower" % [_dev_monsters.size(), kind], Color(0.8, 0.8, 1.0))
		return
	var here := player.current_cell()
	var base_level: int = map.get_cell(here).level
	var cands: Array[Vector2i] = []
	for c in Hex.range_cells(here, 5):
		var d := Hex.distance(c, here)
		var cell: HexMap.Cell = map.get_cell(c)
		if d >= 4 and cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - base_level) <= 1:
			cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if parts.size() > 2 and parts[2].strip_edges() == "cluster":
		# Candidates 5-7 cells out with a clear view of the player (so Rebar can bowl at them).
		cands.clear()
		for c in Hex.range_cells(here, 7):
			var cc: HexMap.Cell = map.get_cell(c)
			if Hex.distance(c, here) >= 5 and cc != null and cc.type == HexMap.Tile.FLOOR and cc.level == base_level:
				if map.line_of_sight(Combat.chest(player), Hex.to_world(c, cc.level) + Vector3.UP * 0.9):
					cands.append(c)
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if parts.size() > 2 and parts[2].strip_edges() == "cluster" and not cands.is_empty():
		# A tight clump: the n candidates nearest to the first one.
		var anchor := cands[0]
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Hex.distance(a, anchor) < Hex.distance(b, anchor))
		for c in cands:
			if _dev_monsters.size() >= n:
				break
			var cm := MonsterFactory.spawn(kind, c)
			if cm != null:
				_dev_monsters.append(cm)
	else:
		# Spread them: take every k-th candidate.
		var stride := maxi(1, cands.size() / maxi(n, 1))
		var i := 0
		while _dev_monsters.size() < n and i < cands.size():
			var m := MonsterFactory.spawn(kind, cands[i])
			if m != null:
				_dev_monsters.append(m)
			i += stride
	if opts.has("idle_monsters"):
		for im in _dev_monsters:
			im.aggro_range = 0.0
	_log("spawn-near: %d %s" % [_dev_monsters.size(), kind], Color(0.8, 0.8, 1.0))


## Average position of the living --spawn-near monsters, or Vector3.INF if none.
func _dev_centroid() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for m in _dev_monsters:
		if is_instance_valid(m) and not m.dead:
			sum += m.global_position
			count += 1
	return sum / count if count > 0 else Vector3.INF


## Dev flag --stage-ledge: a 7-cell tower 5 levels tall on the roomiest flat ground 2-5 cells from
## the start (so a shove off its edge is a 5-level fall onto open floor). --spawn-near then stands
## its monsters on top.
func _stage_plateau() -> void:
	var start: Vector2i = map.cells_with_tag("start")[0]
	var base: int = map.get_cell(start).level
	var best := Vector2i(1 << 20, 1 << 20)
	var best_score := -1
	for c in Hex.range_cells(start, 5):
		if Hex.distance(c, start) < 3:
			continue
		var ok := true
		for n in Hex.range_cells(c, 1):
			var cell: HexMap.Cell = map.get_cell(n)
			if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != base or Hex.distance(n, start) < 2:
				ok = false
				break
		if not ok:
			continue
		var score := 0
		for n in Hex.range_cells(c, 4):
			var cell: HexMap.Cell = map.get_cell(n)
			if cell != null and cell.type == HexMap.Tile.FLOOR and cell.level == base:
				score += 1
		if score > best_score:
			best_score = score
			best = c
	if best_score < 0:
		return
	_stage_center = best
	for n in Hex.range_cells(best, 1):
		map.get_cell(n).level = base + 5

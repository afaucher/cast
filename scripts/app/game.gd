extends Node3D
## The game: the dispatch JOB BOARD (3 offers) -> spell picker -> three floors of a procedural hex
## dungeon joined by the freight elevator -> the INVOICE -> back to the board. The crew casts spells by voice.
## Wires together DungeonGen/HexMapView (terrain), heroes/spells/HUD (HeroFactory, PlayerController, Hud,
## CameraRig), MonsterFactory (monsters), VoiceCaster/VoiceDebugPanel (voice) and the contract layer
## (ContractRun/ContractSession/SiteBuilder: hellgates, employees, priced props, objectives, the Ledger).
##
## Flow (docs/design/contracts.md): the elevator (the exit cell) opens a menu when the player stands on or next
## to it and presses E (a prompt says so; E never casts): go down (more pay, more
## danger) or cash out; cashing out is always allowed. HP and downed state carry between floors; a new
## contract resets everything (spells are re-picked). All heroes down ends the contract: "Crew
## incapacitated" and the invoice shows what was earned so far.
##
## Command line (after `--`):
##   --seed N            dungeon seed (default: random). Seeds the job board; with --contract N / --spells it is
##                       the contract's seed and floor 1 is exactly DungeonGen.generate(N)
##   --contract K        skip the board: take offer K (0-2) of the board, or, for K >= 3, the contract rolled from seed K
##   --floor N           start on floor N (1-3) of the contract (implies a contract; default offer from --seed)
##   --spells a,b        skip the picker (e.g. heal,corn); with no --contract it also skips the board
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
##   --to-gate           dev: put the crew 5 cells from the first hellgate of the floor (the camera follows)
##   --to-theme <id>     dev: put the crew in the middle of the first room with that theme (wine_cellar, home_cinema, spa, gym,
##                       server_room, panic_room, pool, torture_chamber, throne_room, lab, barracks, moat, service_entrance); the
##                       log lists every room's theme. Combine with --zoom 12 for a close look at the set dressing
##   --to-package        dev: put the crew two cells from the first mail package stack of the floor (zoom in with --zoom 10)
##   --to-employee       dev: put the crew 1.5 cells from the first employee (it latches on; E prompts "tell X to wait")
##   --press-e S         dev: press E (the controller's context key) S seconds in
##   --break-crates S    dev: S seconds in, hit every breakable crate stack within 9 units of the player (screenshots)
##   --to-exit           dev: put the crew on the elevator (shows "E: use elevator"; E opens the menu)
##   --demo-damage       dev: 1 s in, put two property-damage lines on the Ledger (to see the ticker and the tracker)
##   --show-panel        dev: keep the voice debug panel open in --shot screenshots
##   --hurt N            dev: every hero starts the floor N hp down (to see the HP carry over between floors)
##   --auto-elevator down|out  dev: the elevator menu opens by itself when the crew stands on the exit (no E needed) and picks
##                       that option 1.2 s later ("down" on the last floor cashes out)
##   --invoice-demo      dev: show a sample invoice (no game), for screenshots
##   --pause-demo        dev: open the pause overlay 1.5 s into the floor (screenshots)
##   --no-grime          dev: no grime / damage decal layer (scripts/world/grime)
##   --grime-demo        dev: 1 s in, cast fireball / corn / tentacles 6 cells from the crew and drop teeth / scuff marks (screenshots)
##   --no-van-intro      dev: skip the van's arrival animation (the van is still parked and the crew stands beside it). Tests (--run-test)
##                       and --shot screenshots skip it by default; --van-intro plays it anyway (--shot-after 1.2 catches the landing)
## Keys: F1 debug panel, F5 back to the job board (abandons the contract), Esc pause menu (Resume / Abandon
## contract / Main menu; Esc on the job board goes to the main menu), Enter = type an incantation.
## Reached from the main menu's Start (scenes/main_menu.tscn); Boot skips the menu when these dev flags are used.

## Every castable spell, straight from SpellBook (new spells need no change here).
static func all_spells() -> PackedStringArray:
	return PackedStringArray(SpellBook.ids())
const PLAYER_COLOR := Color(0.3, 0.55, 0.95)
const SCREEN_LAYER := 60          ## full-screen screens (board, elevator, invoice) sit above the debug panel (50)
const ELEVATOR_REARM_DIST := 2    ## --auto-elevator only: after "stay", walk this many cells off before it asks again
const ELEVATOR_USE_DIST := 1      ## the player can press E at the elevator from this many cells (on it or next to it)
const ELEVATOR_PROMPT := "E: use elevator"
const VAN_PROMPT := "E: clock out at the van"
const VAN_FLOOR := 1              ## the van parks on the top floor only; floors 2 and 3 have no van and no arrival
const VAN_USE_DIST := 2.8         ## the player can press E at the van from this far (world units) from its side door
const DROPOFF_DIST := 2.5         ## a FOLLOWING employee this close (world units) to the van door or the elevator leaves right away
const OBJECTIVE_INTERVAL := 0.25
const FOLLOW_EXTRACT_CELLS := 3   ## followers within this many cells of the elevator ride along
const INCAP_DELAY := 2.2

## Survive scene reloads (next floor, next contract, F5).
static var _run: ContractRun = null
static var _session: ContractSession = null
static var _spells: Array[String] = []
static var _dev_released := false   ## F5 pressed: the dev flags that skip the board / picker stop applying
static var _fade_in := false        ## the next scene fades in from black (arrived by elevator)
static var _board_seed := -1        ## the job board's seed while a contract is being set up, so backing out of the
                                    ## license screen shows the same three offers; -1 = deal a new board

var opts := {}
## Test seam for "Abandon contract" / "Main menu": called with "" (reload the board) or a scene path.
var scene_changer := Callable()
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
var _screen_layer: CanvasLayer     ## board / elevator / invoice
var _tracker: ObjectiveTracker
var _ticker: Control
var _banner: Label
var _banner_tween: Tween
var _site: SiteBuilder.Site
var _menu: ElevatorMenu = null
var _van_menu: VanExitMenu = null    ## the clock-out slip at the van (floor 1 only)
var _invoice: InvoiceScreen = null
var _board: JobBoard = null
var _picker: SpellPicker = null
var _pause: PauseMenu = null
var _ended := false               ## the contract is over (invoice shown or coming)
var _ending := false               ## the crew is down, the invoice is a moment away
var _leaving := false              ## a scene change is under way
var _elev_armed := true
var _objective_t := 0.0
var _stats_timer := 0.0
var _kills := 0
var _exit_cell := Vector2i(1 << 20, 1 << 20)
var _closed_gates: Dictionary = {}  ## instance id -> true, so a gate pays once
var _emp_cause: Dictionary = {}     ## employee instance id -> last culprit name
var _player_down_noted := false
var _dev_monsters: Array[Monster] = []   ## --spawn-near
var _stage_center := Vector2i(1 << 20, 1 << 20)   ## --stage-ledge tower center
var _arrival: VanArrival = null     ## the work van and its arrival sequence (null when the start room had no room for it)


func _ready() -> void:
	InputSetup.ensure_actions()
	_parse_args()
	if opts.has("invoice_demo"):
		_invoice_demo()
		return
	_resolve_run()
	if _session == null:
		_show_board()
		return
	_enter_floor()


## Forget the contract in progress (tests; F5 and "next contract" do the same inline).
static func reset_flow() -> void:
	_board_seed = -1
	_run = null
	_session = null
	_spells.clear()
	_dev_released = false
	_fade_in = false


func _exit_tree() -> void:
	if _pause != null:
		get_tree().paused = false   # never leave the next scene frozen
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
			"--contract": opts["contract"] = int(nxt)
			"--floor": opts["floor"] = clampi(int(nxt), 1, ContractRun.FLOOR_COUNT)
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
			"--to-gate": opts["to_gate"] = true
			"--to-theme": opts["to_theme"] = nxt
			"--to-exit": opts["to_exit"] = true
			"--to-package": opts["to_package"] = true
			"--to-employee": opts["to_employee"] = true
			"--press-e": opts["press_e"] = float(nxt)
			"--break-crates": opts["break_crates"] = float(nxt)
			"--demo-damage": opts["demo_damage"] = true
			"--show-panel": opts["show_panel"] = true
			"--hurt": opts["hurt"] = float(nxt)
			"--auto-elevator": opts["auto_elevator"] = nxt
			"--invoice-demo": opts["invoice_demo"] = true
			"--pause-demo": opts["pause_demo"] = true
			"--no-grime": opts["no_grime"] = true
			"--grime-demo": opts["grime_demo"] = true
			"--no-van-intro": opts["no_van_intro"] = true
			"--van-intro": opts["van_intro"] = true


# --- Contract flow: board -> contract -> floors -> invoice ------------------------------------

## Pick up the contract from an earlier floor, or (dev flags) start one directly.
func _resolve_run() -> void:
	if _session == null and not _dev_released:
		var board_seed := int(opts.get("seed", randi() % 100000))
		var run: ContractRun = null
		if opts.has("contract"):
			var k: int = opts["contract"]
			run = ContractBoard.offers(board_seed)[k] if k >= 0 and k < ContractBoard.OFFER_COUNT else ContractBoard.run_for_seed(k)
		elif opts.has("spells") or opts.has("floor"):
			run = ContractBoard.run_for_seed(board_seed)
		if run != null:
			_begin_contract(run)
	if _session != null and _spells.is_empty() and not _dev_released and opts.has("spells"):
		for s in str(opts["spells"]).split(","):
			var id := s.strip_edges()
			if id in all_spells() and not _spells.has(id):
				_spells.append(id)


## A new contract: the Ledger restarts, nothing carries over, spells are picked again.
func _begin_contract(run: ContractRun) -> void:
	_run = run
	_session = ContractSession.begin(run, int(opts.get("floor", 1)) if not _dev_released else 1)
	_spells.clear()


func _screens() -> CanvasLayer:
	if _screen_layer == null:
		_screen_layer = CanvasLayer.new()
		_screen_layer.layer = SCREEN_LAYER
		add_child(_screen_layer)
	return _screen_layer


func _show_board() -> void:
	var board_seed := _board_seed if _board_seed >= 0 else int(opts.get("seed", randi() % 100000))
	_board_seed = board_seed
	var offers := ContractBoard.offers(board_seed)
	var board := JobBoard.new(offers)
	_board = board
	# The same garage as the main menu behind the cards. The menu scene is already gone (Start changes scene), so
	# this is a fresh MenuBackdrop; it picks the same mood and featured hero itself (pick_mood, hero_from_args).
	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	board.backdrop_behind = true
	_screens().add_child(board)
	board.picked.connect(func(run: ContractRun) -> void:
		board.queue_free()
		backdrop.queue_free()
		_board = null
		_begin_contract(run)
		_enter_floor())
	if opts.has("shot"):
		_take_shot_later(str(opts["shot"]), float(opts.get("shot_after", 1.0)))


## Build the current floor of the contract (the scene is fresh: first floor, or arrived by elevator).
func _enter_floor() -> void:
	_build_world()
	_setup_voice()
	if _fade_in:
		_fade_in = false
		_fade(1.0, 0.0, 0.5)
	if _spells.is_empty():
		_show_picker()
	else:
		_start()


func _floor_n() -> int:
	return _session.floor_number


func _heroes() -> Array[Hero]:
	var out: Array[Hero] = [player]
	out.append_array(allies)
	return out


# --- World --------------------------------------------------------------------------------------

func _build_world() -> void:
	map = DungeonGen.generate(_run.floor_seed(_floor_n()))
	if opts.has("stage_ledge"):
		_stage_plateau()
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, _run.floor_seed(_floor_n()))
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
	controller.interact = _use_key
	var spots := _free_cells_near(start, 2)
	# Each hero's kit (HP, primary, secondary, quirks) comes from HeroKit; --proto-heroes keeps the kits.
	var rebar := HeroFactory.spawn_hero(spots[0], "Rebar", Color(0.85, 0.5, 0.25), "sword", RebarModel.new() if faceted else null, HeroKit.REBAR)
	HeroFactory.make_ally(rebar, player, false, 2.4, 2.6)
	var gasket := HeroFactory.spawn_hero(spots[mini(1, spots.size() - 1)], "Gasket", Color(0.7, 0.4, 0.85), "sword", GasketModel.new() if faceted else null, HeroKit.GASKET)
	HeroFactory.make_ally(gasket, player, false, 3.9, 3.3)
	allies = [rebar, gasket]

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


## Everything the contract puts on this floor: hellgates, employees, priced props, a clue note, and the
## monster packs (one per room but the start room, leaning toward the pest). Then the session starts the floor.
func _populate_site() -> void:
	_site = SiteBuilder.build(map, _run, _floor_n())
	var origin := _site.origin_gate != null
	var small := _site.gates.size() - (1 if origin else 0)
	_session.enter_floor(_floor_n(), small, origin, _site.employees.size(), _site.pest_spawned)
	for g in _site.gates:
		if g.has_signal("closed"):
			g.connect("closed", _on_gate_closed)
	for e in _site.employees:
		e.damaged.connect(func(_amount: float, source: Node) -> void: _emp_cause[e.get_instance_id()] = Ledger.culprit_name(source))
	for n in _site.notes:
		n.connect("read", _on_note_read)
	_log("site: %d gates%s, %d employees, %d props, %d monsters (%d pests: %s)" % [small, " + origin" if origin else "", _site.employees.size(),
		_site.props.size(), _site.monsters.size(), _site.pest_spawned, _run.pest], Color(0.8, 0.8, 1.0))
	_log("themes: %s  decor %d" % [str(_site.plan.room_themes), _site.plan.decor.size()], Color(0.8, 0.8, 1.0))


# --- Voice --------------------------------------------------------------------

func _setup_voice() -> void:
	voice = VoiceCaster.new()
	voice.name = "VoiceCaster"
	voice.settings_path = GameSettings.path   # the menu's voice setup writes here
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
	# Settings > "Voice debug panel visible at start" (F1 still toggles it); --show-panel always opens it.
	debug_panel.visible = opts.has("show_panel") or bool(GameSettings.load_settings()["voice_panel_visible"])
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


# --- Floor start ---------------------------------------------------------------------------------

func _show_picker() -> void:
	controller.enabled = false
	var picker := SpellPicker.new()
	_picker = picker
	if voice.has_method("get_trigger_word"):
		picker.set_trigger_word(voice.call("get_trigger_word"))
	hud.add_overlay(picker)
	picker.cancelled.connect(_back_to_board)
	picker.picked.connect(func(chosen: Array[String]) -> void:
		_board_seed = -1   # committed to this job: the next board is a new one
		_spells = chosen.duplicate()
		picker.queue_free()
		_picker = null
		_start())


func _start() -> void:
	player.spell_slots = _spells.duplicate()
	_apply_dev_loadout()
	hud.bind(player, allies)
	hud.enable_console()
	controller.enabled = true
	_apply_carry()
	if opts.has("hurt") and not _fade_in_hurt_done():
		for h in _heroes():
			h.hp = maxf(1.0, h.hp - float(opts["hurt"]))
			h._refresh_bar()
	_populate_site()
	_arrive_by_van()
	if not opts.has("no_grime"):
		GrimeLayer.attach(self, map, _site.plan, _run.floor_seed(_floor_n()))
		if opts.has("grime_demo"):
			GrimeDemo.run(self, player)
	_spawn_near()
	_build_contract_ui()
	_dev_teleports()
	if opts.has("shot") and not opts.has("show_panel"):   # keep screenshots clear of the banner and the voice panel
		debug_panel.visible = false
	else:
		hud.show_center("Floor %d of %d" % [_floor_n(), ContractRun.FLOOR_COUNT], Color(0.8, 0.9, 1.0), 2.0)
	_story_banner()
	_log("floor %d/%d  seed %d  %s  spells %s" % [_floor_n(), ContractRun.FLOOR_COUNT, _run.floor_seed(_floor_n()), _run.company, ", ".join(_spells)], Color(0.6, 0.9, 1.0))
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
	if opts.has("pause_demo"):
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if _can_pause():
				_open_pause())
	if opts.has("press_e"):
		get_tree().create_timer(float(opts["press_e"])).timeout.connect(func() -> void:
			var used := controller.press_use()
			_log("press-e: %s" % ("used" if used else "nothing"), Color(0.8, 1.0, 0.8)))
	if opts.has("break_crates"):
		get_tree().create_timer(float(opts["break_crates"])).timeout.connect(_break_crates_dev)
	if opts.has("demo_damage"):
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			Ledger.damage("Vintage 1787 wine barrel", 4000, player)
			Ledger.damage("Zen fountain", 900, allies[0]))
	if opts.has("shot"):
		_take_shot_later(str(opts["shot"]), float(opts.get("shot_after", 3.0)))


## The crew arrives in the work van on the FIRST floor only: it teleports in over a summoning circle in the start room and
## the heroes step out beside its door (docs/design/environment.md, "Van arrival"). Player control comes back when they are
## out (~2.5 s), any key or click skips ahead, and the van stays parked as solid decor (and an exit, see _use_van). Floors 2
## and 3 have no van and no arrival: the crew starts on the start cell and its free neighbours (see _build_world). Without
## room for the van the crew stays at the start too.
func _arrive_by_van() -> void:
	if _floor_n() != VAN_FLOOR or _site == null or _site.plan.van.is_empty():
		return
	var crew: Array[Hero] = [player]
	if allies.size() >= 2:
		crew.append(allies[1])   # Gasket
		crew.append(allies[0])   # Rebar
	var moved_away := opts.has("to_theme") or opts.has("to_package") or opts.has("to_gate") or opts.has("to_exit") or opts.has("to_employee")
	var play := _van_intro_enabled() and not moved_away and not player.dead
	_arrival = VanArrival.spawn(_site.plan.van, crew, play)
	if _arrival == null:
		return
	rig.snap()
	if _arrival.is_running():
		controller.enabled = false
		_arrival.finished.connect(_on_arrival_finished)


## The animation plays unless --no-van-intro; tests and screenshots skip it unless --van-intro.
func _van_intro_enabled() -> bool:
	if opts.has("no_van_intro"):
		return false
	if opts.has("van_intro"):
		return true
	return not (OS.get_cmdline_user_args().has("--run-test") or opts.has("shot"))


func _on_arrival_finished() -> void:
	if controller != null and player != null and not player.dead and not _ended and _menu == null and _van_menu == null:
		controller.enabled = true


## Heroes arrive as the previous floor left them (HP, downed). A downed player hands the camera to a living ally.
func _apply_carry() -> void:
	for h in _heroes():
		_session.apply_carry(h)
	if player.dead:
		controller.enabled = false
		_follow_living_ally()


## --hurt applies on floor 1 of a contract only (so the carry-over on later floors is visible).
func _fade_in_hurt_done() -> bool:
	return _floor_n() > 1


func _follow_living_ally() -> void:
	for a in allies:
		if not a.dead:
			rig.target = a
			return


func _build_contract_ui() -> void:
	_tracker = ObjectiveTracker.new()
	hud.add_overlay(_tracker)
	_ticker = ContractParts.make_ticker()
	if _ticker != null:
		hud.add_overlay(_ticker)
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 120
	_banner.custom_minimum_size = Vector2(500, 0)
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 7)
	_banner.modulate.a = 0.0
	hud.add_overlay(_banner)
	Ledger.line_added.connect(_on_ledger_line)
	_update_tracker()


## The story at the top of each floor: the flavour of how the incident reached here, then (floor 1) the cause.
func _story_banner() -> void:
	var notes: Array = _run.story["floor_notes"]
	var text := str(notes[_floor_n() - 1])
	if _floor_n() == 1:
		text = "%s\n%s" % [str(_run.story["event"]), text]
	_show_banner(text, 7.0)


func _show_banner(text: String, hold: float) -> void:
	if _banner == null:
		return
	if _banner_tween:
		_banner_tween.kill()
	_banner.text = text
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.8)


func _on_note_read(text: String) -> void:
	_show_banner("A note: " + text, 8.0)
	_log("note: " + text, Color(1.0, 0.95, 0.7))


# --- Objectives ------------------------------------------------------------------------------------

func _on_gate_closed(gate: Actor) -> void:
	var id := gate.get_instance_id()
	if _closed_gates.has(id) or _session == null or _ended:
		return
	_closed_gates[id] = true
	var is_origin := gate == _site.origin_gate
	var pay := _session.gate_closed(is_origin)
	if is_origin:
		hud.show_center("ORIGIN GATE CLOSED", Color(1.0, 0.85, 0.4), 2.2)
		_show_banner("The origin gate is shut. The site calms down. The invoice does not.", 6.0)
	_log("%s closed  +%s" % ["ORIGIN gate" if is_origin else "hellgate", ContractRun.money(pay)], Color(0.6, 1.0, 0.7))
	_objective_t = 0.0   # re-check cleanliness now


func _on_ledger_line(line: Dictionary) -> void:
	if str(line["kind"]) == "earn":
		var lbl := str(line["label"])
		if lbl.begins_with("Hellgate") or lbl.begins_with("Pest") or lbl.begins_with("ORIGIN"):
			hud.show_message("%s  +%s" % [lbl, ContractRun.money(int(line["amount"]))], Color(0.6, 1.0, 0.7))
	_update_tracker()


## Living monsters of the contract's pest kind on this floor ("everything": every monster).
func _pest_alive() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("monsters"):
		var m := node as Monster
		if m == null or m.dead:
			continue
		if _run.pest == "everything" or m.kind == _run.pest:
			n += 1
	return n


func _check_objectives() -> void:
	var paid := _session.check_clean(_pest_alive())
	if paid > 0:
		hud.show_center("FLOOR CLEAN", Color(0.6, 1.0, 0.8), 1.8)
		_log("floor clean: %s cleared  +%s" % [ClientArchetype.pest_name(_run.pest), ContractRun.money(paid)], Color(0.6, 1.0, 0.7))
	_update_tracker()


func _update_tracker() -> void:
	if _tracker == null or _session == null:
		return
	var st := _session.state()
	var rows: Array[Dictionary] = []
	if not st.is_empty():
		var total := int(st["gates_total"])
		if total > 0:
			var closed := int(st["gates_closed"])
			rows.append({"text": "Close hellgates", "detail": "%d / %d" % [closed, total], "state": "done" if closed >= total else ("partial" if closed > 0 else "todo")})
		if bool(st["origin"]):
			rows.append({"text": "ORIGIN gate", "detail": "closed" if bool(st["origin_closed"]) else "OPEN", "state": "done" if bool(st["origin_closed"]) else "todo"})
		var left := _pest_alive()
		var clean := bool(st["pest_paid"])
		rows.append({"text": "Exterminate %s" % ClientArchetype.pest_name(_run.pest), "detail": "clean" if clean else "%d left" % left, "state": "done" if clean else "todo"})
		var alive_here := 0
		var following := 0
		for e in _site.employees:
			if is_instance_valid(e) and not e.dead and not bool(e.call("is_extracted")):
				alive_here += 1
				if e.has_method("is_following") and bool(e.call("is_following")):
					following += 1
		var spawned := int(st["employees"])
		if spawned > 0:
			var lost := int(st["lost"])
			var rescued := int(st["extracted"])
			var parts: Array[String] = []
			if rescued > 0:
				parts.append("%d rescued" % rescued)
			parts.append("%d alive" % alive_here)
			if following > 0:
				parts.append("%d with you" % following)
			if lost > 0:
				parts.append("%d lost" % lost)
			var detail := " · ".join(parts)
			rows.append({"text": "Employees", "detail": detail, "state": "fail" if lost > 0 else ("done" if rescued > 0 and alive_here == 0 else "todo")})
	_tracker.show_state("FLOOR %d / %d" % [_floor_n(), ContractRun.FLOOR_COUNT], _run.company, rows, Ledger.payout(), Ledger.deducted())
	if _ticker != null:
		_ticker.offset_top = _tracker.offset_bottom + 10.0
		_ticker.offset_bottom = _ticker.offset_top + 220.0


func _on_actor_died(a: Actor) -> void:
	if a.team == GameWorld.TEAM_MONSTERS:
		_kills += 1
		_log("%s died" % a.display_name, Color(0.7, 0.7, 0.7))
	elif a.team == GameWorld.TEAM_HEROES:
		_log("%s is down!" % a.display_name, Color(1.0, 0.45, 0.45))
	elif _site != null and _site.employees.has(a):
		var cause: String = str(_emp_cause.get(a.get_instance_id(), "unknown"))
		_session.employee_lost(a.display_name, cause)
		_log("%s was lost (%s)" % [a.display_name, cause], Color(1.0, 0.6, 0.4))
		hud.show_message("%s lost (%s)  -$10" % [a.display_name, cause], Color(1.0, 0.55, 0.4))
		_update_tracker()


# --- The elevator ----------------------------------------------------------------------------------------

## True when the living player stands on or next to the elevator (the exit cell).
func _player_at_elevator() -> bool:
	return player != null and not player.dead and Hex.distance(player.current_cell(), _exit_cell) <= ELEVATOR_USE_DIST


## True when the van is parked on this floor (floor 1 only) and its plan is there.
func _has_van() -> bool:
	return _arrival != null and _floor_n() == VAN_FLOOR and _site != null and not _site.plan.van.is_empty()


## The floor in front of the van's sliding side door (world X/Z); INF when there is no van here.
func _van_door_pos() -> Vector2:
	if not _has_van():
		return Vector2(INF, INF)
	return _site.plan.van["door"]


## True when `pos` is within `dist` of the van's side door (always false on floors 2 and 3).
func _near_van(pos: Vector3, dist: float) -> bool:
	return _has_van() and Vector2(pos.x, pos.z).distance_to(_van_door_pos()) <= dist


## True when `pos` is within `dist` (world units) of the elevator.
func _near_elevator_world(pos: Vector3, dist: float) -> bool:
	var ex := Hex.to_world(_exit_cell)
	return Vector2(pos.x, pos.z).distance_to(Vector2(ex.x, ex.z)) <= dist


## True when the living player stands at the van's side door.
func _player_at_van() -> bool:
	return player != null and not player.dead and _near_van(player.global_position, VAN_USE_DIST)


## E (the controller calls this first; true = the press is used). Priority: the van exit (at the van), then the elevator
## (at it); otherwise false and the controller tries the employees. E never casts.
func _use_key() -> bool:
	if _menu != null or _van_menu != null or _leaving or _ended or _ending or _session == null:
		return false
	if _player_at_van():
		_open_van_exit()
		return true
	if _player_at_elevator():
		_open_elevator()
		return true
	return false


func _check_elevator() -> void:
	var slip_free := _menu == null and _van_menu == null and not _leaving
	if hud != null:
		hud.context_prompt = ""
		if slip_free and _player_at_van():
			hud.context_prompt = VAN_PROMPT
		elif slip_free and _player_at_elevator():
			hud.context_prompt = ELEVATOR_PROMPT
		elif slip_free:
			hud.context_prompt = Employee.interact_prompt(player)   # "E: tell Marguerite to wait" / "E: bring Marguerite"
	if _menu != null or _van_menu != null or _leaving or not opts.has("auto_elevator"):
		return   # without --auto-elevator the menu opens only on E (see _use_elevator_key)
	var on_exit := false
	for h in _heroes():
		if not h.dead and h.current_cell() == _exit_cell:
			on_exit = true
			break
	if not on_exit:
		if _elev_armed:
			return
		var far := true
		for h in _heroes():
			if not h.dead and Hex.distance(h.current_cell(), _exit_cell) <= ELEVATOR_REARM_DIST:
				far = false
		_elev_armed = far
		return
	if _elev_armed:
		_open_elevator()


## Employees that follow a hero and stand within a few cells of `cell` (an exit) ride out with the crew.
func _followers_near_cell(cell: Vector2i) -> Array[Actor]:
	var out: Array[Actor] = []
	if _site == null:
		return out
	for e in _site.employees:
		if is_instance_valid(e) and not e.dead and e.has_method("is_following") and bool(e.call("is_following")):
			if Hex.distance(e.current_cell(), cell) <= FOLLOW_EXTRACT_CELLS:
				out.append(e)
	return out


func _followers_near_exit() -> Array[Actor]:
	return _followers_near_cell(_exit_cell)


## The followers near the van's side door (none on floors 2 and 3).
func _followers_near_van() -> Array[Actor]:
	if not _has_van():
		var none: Array[Actor] = []
		return none
	var d := _van_door_pos()
	return _followers_near_cell(Hex.from_world(Vector3(d.x, 0.0, d.y)))


## Extract these employees now: the exit animation and bark, then $100 each in the Ledger (ContractSession.extract). An
## employee extracted here is out of the "employees" group and no longer following, so nothing counts them again (not as a
## follower at the exit, not as one of the $10 left alive at the close). Used by the drop-off and by taking an exit.
func _extract_followers(riders: Array[Actor], line: String) -> void:
	if riders.is_empty():
		return
	for e in riders:
		if e.has_method("extract"):
			e.call("extract", line)
	_session.extract(riders.size(), player)
	var pay := ContractRun.money(riders.size() * ContractRun.EMPLOYEE_EXTRACTED)
	if riders.size() == 1:
		_log("%s extracted  +%s" % [riders[0].display_name, pay], Color(0.6, 1.0, 0.7))
		hud.show_message("%s is out  +%s" % [riders[0].display_name, pay], Color(0.6, 1.0, 0.7))
	else:
		_log("%d employees extracted  +%s" % [riders.size(), pay], Color(0.6, 1.0, 0.7))
		hud.show_message("%d employees out  +%s" % [riders.size(), pay], Color(0.6, 1.0, 0.7))
	_update_tracker()


## The drop-off: an employee who is FOLLOWING the crew and gets within DROPOFF_DIST of the van's door or the elevator
## leaves right away ($100, once), whether or not the crew ever takes the exit. Waiting and cowering employees never do.
func _check_dropoffs() -> void:
	if _site == null or _session == null or _menu != null or _van_menu != null or _leaving or _ended:
		return
	for e in _site.employees:
		if not is_instance_valid(e) or e.dead or not e.has_method("is_following") or not bool(e.call("is_following")):
			continue
		var pos: Vector3 = e.global_position
		if _near_van(pos, DROPOFF_DIST) or _near_elevator_world(pos, DROPOFF_DIST):
			var one: Array[Actor] = [e]
			_extract_followers(one, "I'm out, thanks!")


func _elevator_lines() -> Array[String]:
	var lines: Array[String] = []
	var st := _session.state()
	if not st.is_empty():
		var total := int(st["gates_total"])
		if total > 0:
			lines.append("Hellgates closed on this floor: %d of %d." % [int(st["gates_closed"]), total])
		if bool(st["origin"]):
			lines.append("Origin gate: %s." % ("closed" if bool(st["origin_closed"]) else "still open (the biggest line on the invoice)"))
		lines.append("Floor %s." % ("clean" if bool(st["pest_paid"]) else "not clean: %d %s left" % [_pest_alive(), ClientArchetype.pest_name(_run.pest)]))
	lines.append("Objectives not met do not pay. Damage comes out of what you earned.")
	return lines


func _open_elevator() -> void:
	var info := {
		"floor": _floor_n(), "floor_count": ContractRun.FLOOR_COUNT,
		"payout": Ledger.payout(), "damages": Ledger.deducted(),
		"followers": _followers_near_exit().size(), "lines": _elevator_lines(),
	}
	_menu = ElevatorMenu.new(info)
	_screens().add_child(_menu)
	_freeze(true)
	_menu.go_down.connect(func() -> void: _use_elevator(true))
	_menu.cash_out.connect(func() -> void: _use_elevator(false))
	_menu.stay.connect(_close_elevator.bind(true))
	if opts.has("auto_elevator"):
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if _menu != null:
				_use_elevator(str(opts["auto_elevator"]) == "down" and _menu.can_descend()))


## The clock-out slip at the van (floor 1): the crew's other exit, the same as the elevator's "Exit".
func _open_van_exit() -> void:
	var info := {
		"floor": _floor_n(), "floor_count": ContractRun.FLOOR_COUNT,
		"payout": Ledger.payout(), "damages": Ledger.deducted(),
		"followers": _followers_near_van().size(), "lines": _elevator_lines(),
	}
	_van_menu = VanExitMenu.new(info)
	_screens().add_child(_van_menu)
	_freeze(true)
	_van_menu.clock_out.connect(_use_van)
	_van_menu.cancel.connect(_close_elevator.bind(true))


## Closes whichever exit slip is open (the elevator's or the van's).
func _close_elevator(disarm: bool) -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _van_menu != null:
		_van_menu.queue_free()
		_van_menu = null
	_freeze(false)
	if disarm:
		_elev_armed = false


## Stop (or resume) the simulation and the player's input; the HUD and menus keep running.
func _freeze(on: bool) -> void:
	if GameWorld.root != null:
		GameWorld.root.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if controller != null and not on:
		controller.enabled = not player.dead and not _ended
	elif controller != null:
		controller.enabled = false


func _use_elevator(descend: bool) -> void:
	if _leaving:
		return
	_extract_followers(_followers_near_exit(), "thank you!")
	if not descend:
		_end_contract(ContractSession.END_CASHED_OUT)
		return
	_leaving = true
	_close_elevator(false)
	_freeze(true)
	_session.save_carry(_heroes())
	_session.floor_number += 1
	_fade(0.0, 1.0, 0.45, func() -> void:
		_fade_in = true
		get_tree().reload_current_scene())


## Clock out at the van: the followers near it are extracted, then the contract ends exactly like the elevator's exit.
func _use_van() -> void:
	if _leaving or _ended:
		return
	_extract_followers(_followers_near_van(), "thank you!")
	_end_contract(ContractSession.END_CASHED_OUT)


## A full-screen black overlay that fades from alpha `a` to `b`.
func _fade(a: float, b: float, seconds: float, done: Callable = Callable()) -> void:
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, a)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screens().add_child(rect)
	var tw := create_tween()
	tw.tween_property(rect, "color:a", b, seconds)
	if done.is_valid():
		tw.tween_callback(done)
	elif b <= 0.0:
		tw.tween_callback(rect.queue_free)


# --- The end: the invoice --------------------------------------------------------------------------------

## All heroes down, or the crew cashed out: pay the employees still alive, then show the invoice.
func _end_contract(reason: String) -> void:
	if _ended:
		return
	_ended = true
	_close_elevator(false)
	_freeze(true)
	_session.finish(reason)
	var inv := ContractInvoice.build(_session)
	LastContract.record(inv)   # the main menu's garage shows the morning after a bad job
	_log("contract over (%s): earned %s, damages %s, payout %s" % [reason, ContractRun.money(int(inv["earned"])), ContractRun.money(int(inv["damages"])), ContractRun.money(int(inv["payout"]))], Color(1.0, 0.9, 0.5))
	_show_invoice(inv)


func _show_invoice(inv: Dictionary) -> void:
	if debug_panel != null:
		debug_panel.visible = false
	_invoice = InvoiceScreen.new(inv)
	_screens().add_child(_invoice)
	_invoice.next_contract.connect(_on_next_contract)
	if opts.has("shot") and _session != null:
		_take_shot_later(str(opts["shot"]), 1.5)


func _on_next_contract() -> void:
	if _leaving:
		return
	_leaving = true
	_dev_released = true
	_run = null
	_session = null
	_spells.clear()
	Ledger.end_contract()
	get_tree().reload_current_scene()


## --invoice-demo: a sample contract with a believable ledger, straight to the invoice.
func _invoice_demo() -> void:
	var run := ContractBoard.run_for_seed(int(opts.get("seed", 12)))
	var s := ContractSession.begin(run, 1)
	var wick := _demo_hero("Wick")
	var rebar := _demo_hero("Rebar")
	var gasket := _demo_hero("Gasket")
	s.enter_floor(1, run.floor_gates[0], false, run.floor_employees[0], 12)
	for _i in run.floor_gates[0]:
		s.gate_closed(false)
	s.check_clean(0)
	s.extract(2)
	Ledger.damage("Wine rack", 1200, wick)
	s.enter_floor(2, run.floor_gates[1], false, run.floor_employees[1], 14)
	for _i in run.floor_gates[1]:
		s.gate_closed(false)
	s.check_clean(0)
	Ledger.damage("Zen fountain", 900, rebar)
	Ledger.damage("Crystal lamp", 600, wick)
	Ledger.damage("Crystal lamp", 600, gasket)
	s.employee_lost("Colin (valet)", "Wick")
	s.enter_floor(3, 0, true, run.floor_employees[2], 18)
	s.gate_closed(true)
	s.check_clean(0)
	s.extract(1)
	Ledger.damage("Gold toilet", 15000, wick)
	s.finish(ContractSession.END_CASHED_OUT)
	var inv := ContractInvoice.build(s)
	for h in [wick, rebar, gasket]:
		h.free()
	_session = s
	_run = run
	_show_invoice(inv)
	_invoice.next_contract.disconnect(_on_next_contract)


func _demo_hero(hero_name: String) -> Actor:
	var a := Actor.new()
	a.display_name = hero_name
	return a


# --- Crew ------------------------------------------------------------------------------------------------

## All heroes down ends the contract (the invoice still pays what was earned). A downed player hands the
## camera to a living ally.
func _check_crew() -> void:
	var any_alive := false
	for h in _heroes():
		if not h.dead:
			any_alive = true
	if not any_alive:
		if not _ending:
			_ending = true
			controller.enabled = false
			hud.show_center("Crew incapacitated", Color(1.0, 0.4, 0.35))
			get_tree().create_timer(INCAP_DELAY).timeout.connect(func() -> void: _end_contract(ContractSession.END_INCAPACITATED))
		return
	if player.dead and not _player_down_noted:
		_player_down_noted = true
		controller.enabled = false
		_follow_living_ally()
		hud.show_message("You are down. Your crew fights on.", Color(1.0, 0.6, 0.45))


func _physics_process(delta: float) -> void:
	if _ended or _leaving or player == null or _session == null:
		return
	_check_crew()
	if _ending:
		return
	_check_elevator()
	_check_dropoffs()
	_objective_t -= delta
	if _objective_t <= 0.0:
		_objective_t = OBJECTIVE_INTERVAL
		_check_objectives()


func _process(delta: float) -> void:
	if voice:
		hud.set_mic_level(voice.get_level())
	_stats_timer -= delta
	if _stats_timer <= 0.0:
		_stats_timer = 0.25
		_update_stats()


## A fresh key / click / pad press (not Esc, which opens the pause menu) skips the van's arrival.
static func _is_skip_press(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo() or event.is_action_pressed("pause"):
		return false
	return event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton


func _unhandled_input(event: InputEvent) -> void:
	if _arrival != null and _arrival.is_running() and _is_skip_press(event):
		_arrival.skip()   # never trap the player: any key or click jumps to the end of the arrival
	if event.is_action_pressed("restart"):
		_abandon_to_board()
	elif event.is_action_pressed("pause"):
		if _board != null:
			_to_main_menu()   # Esc on the job board: back to the menu
		elif _picker != null:
			_back_to_board()  # Esc on the license checkout: back to the same three offers
		elif _can_pause():
			_open_pause()
	elif event.is_action_pressed("toggle_voice_debug") and debug_panel != null and _invoice == null:
		debug_panel.visible = not debug_panel.visible


# --- Pause (Esc) ----------------------------------------------------------------------------------------

## A contract is running and nothing else (picker, elevator, invoice, ending, scene change) holds the screen.
func _can_pause() -> bool:
	return _pause == null and _session != null and player != null and _picker == null and _menu == null and _van_menu == null \
			and _invoice == null and not _ended and not _ending and not _leaving


## The pause overlay; the whole tree stops (GameWorld's clock, actors, spells, tweens, the voice caster)
## except the overlay itself, which runs while paused.
func _open_pause() -> void:
	_pause = PauseMenu.new()
	_screens().add_child(_pause)
	get_tree().paused = true
	_pause.resume.connect(_close_pause)
	_pause.abandon.connect(_abandon_to_board)
	_pause.main_menu.connect(_to_main_menu)


func _close_pause() -> void:
	if _pause == null:
		return
	_pause.queue_free()
	_pause = null
	get_tree().paused = false
	if voice != null:
		voice.reset()   # drop audio heard while the game was stopped


## F5 and "Abandon contract": back to the job board; the contract is dropped, and the dev flags that skip
## the board stop applying.
func _abandon_to_board() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().paused = false
	_dev_released = true
	_board_seed = -1   # an abandoned job: deal a new board
	_run = null
	_session = null
	_spells.clear()
	Ledger.end_contract()
	_change_scene("")


## Back out of the license checkout (Esc or its "Back to the board" row): the job isn't started, so nothing is
## billed; the board reopens with the same three offers.
func _back_to_board() -> void:
	if _leaving:
		return
	_leaving = true
	_dev_released = true
	_run = null
	_session = null
	_spells.clear()
	Ledger.end_contract()
	_change_scene("")


## "Main menu" (pause overlay, Esc on the job board): drop the contract and open the menu scene.
func _to_main_menu() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().paused = false
	reset_flow()
	Ledger.end_contract()
	_change_scene(Boot.MENU_SCENE)


## "" reloads this scene (the job board), anything else opens that scene.
func _change_scene(path: String) -> void:
	if scene_changer.is_valid():
		scene_changer.call(path)
	elif path == "":
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(path)


func _update_stats() -> void:
	if game_stats == null or player == null:
		return
	var lines: Array[String] = []
	lines.append("fps %d   floor %d/%d   seed %d" % [Engine.get_frames_per_second(), _floor_n(), ContractRun.FLOOR_COUNT, _run.floor_seed(_floor_n())])
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
	lines.append("contract %s  pest %s  value %s" % [_run.invoice_number, _run.pest, ContractRun.money(_run.contract_value)])
	lines.append("payout %s  earned %s  damages %s" % [ContractRun.money(Ledger.payout()), ContractRun.money(Ledger.earned()), ContractRun.money(Ledger.damages())])
	lines.append("elevator %d hexes away" % Hex.distance(c, _exit_cell))
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


## Dev flags --to-gate / --to-exit: move the crew (screenshots).
func _dev_teleports() -> void:
	if opts.has("to_theme") and _site != null:
		var themed := _site.plan.rooms_with_theme(str(opts["to_theme"]))
		if not themed.is_empty():
			# the middle of the room's set dressing (the room's centre when it has none)
			var focus: Vector2i = _site.plan.centers[themed[0]]
			var sum := Vector2.ZERO
			var n := 0
			for dc in _site.plan.decor:
				if str(dc["room"]) == themed[0] and String(dc["place"]) != "ring":
					sum += dc["pos"]
					n += 1
			if n > 0:
				var mid := sum / float(n)
				focus = Hex.from_world(Vector3(mid.x, 0.0, mid.y))
				if map.get_cell(focus) == null or map.get_cell(focus).type != HexMap.Tile.FLOOR:
					focus = _site.plan.centers[themed[0]]
			_teleport_crew(focus)
			return
	if opts.has("to_employee") and _site != null and not _site.plan.employees.is_empty():
		var ec: Vector2i = _site.plan.employees[0]["cell"]
		var stand := ec
		for c in Hex.ring(ec, 1):
			var cell3: HexMap.Cell = map.get_cell(c)
			if cell3 != null and cell3.type == HexMap.Tile.FLOOR:
				stand = c
				break
		_teleport_crew(stand)
		return
	if opts.has("to_package") and _site != null and not _site.plan.packages.is_empty():
		# two cells from the first stack, toward the middle of its room
		var pk: Dictionary = _site.plan.packages[0]
		var pc: Vector2i = pk["cell"]
		var mid: Vector2i = _site.plan.centers[str(pk["room"])]
		var near := pc
		var near_d := 99
		for c in Hex.ring(pc, 2):
			var cell2: HexMap.Cell = map.get_cell(c)
			if cell2 != null and cell2.type == HexMap.Tile.FLOOR and Hex.distance(c, mid) < near_d:
				near_d = Hex.distance(c, mid)
				near = c
		_teleport_crew(near)
		return
	if opts.has("to_gate") and _site != null and not _site.gates.is_empty():
		var gc: Vector2i = _site.plan.gates[0]["cell"]
		var best := gc
		var best_d := 99
		for c in Hex.ring(gc, 5):
			var cell: HexMap.Cell = map.get_cell(c)
			if cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - map.get_cell(gc).level) <= 1:
				var d := Hex.distance(c, gc)
				if d < best_d:
					best_d = d
					best = c
		_teleport_crew(best)
	elif opts.has("to_exit"):
		_teleport_crew(_exit_cell)


## Dev flag --break-crates: hit the crate stacks around the player (screenshots of the break).
func _break_crates_dev() -> void:
	for a in GameWorld.breakables_in_radius(player.global_position, 9.0):
		if a is BreakableCrate:
			a.apply_damage(5.0, player)


func _teleport_crew(cell: Vector2i) -> void:
	var spots := _free_cells_near(cell, 2)
	var list := _heroes()
	for i in list.size():
		var c := cell if i == 0 else spots[(i - 1) % spots.size()]
		var lv := map.ground_level(Hex.to_world(c))
		list[i].global_position = Hex.to_world(c, 0.0 if is_nan(lv) else lv)
		list[i].snap_to_ground()
	rig.snap()


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

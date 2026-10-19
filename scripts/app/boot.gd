class_name Boot
extends Node
## Entry point. A plain run opens the MAIN MENU; any dev flag that implies jumping straight in opens the
## game (or the named scene) as before. Command-line options (after `--`):
##   --run-test <name>   run res://tests/<name>.gd headless-friendly and quit
##   --scene <res path>  open a specific scene instead of the menu / game
##   --menu              show the menu even when other dev flags are present (they still reach the game)
##   --menu-shot <png>   menu: save a screenshot after --menu-after seconds (default 1.5) and quit
##   --menu-screen <s>   menu: open on "main" (default), "voice" or "settings"
##   --menu-after <s>    menu: seconds before --menu-shot fires (default 1.5)
##   --menu-say <text>   menu: inject this text into the voice setup's "Try it" (screenshots)
##   --menu-void         menu: void the open sub-screen just before --menu-shot, holding the VOID stamp (screenshots)
##   --menu-hover <h>    menu: outline this hero in the garage as if the pointer were on it (screenshots)
##   --menu-focus-file   menu: open with the personnel file's NAME line in focus (screenshots)
##   --backdrop-mood <m> menu: force the garage backdrop's mood, dawn | night | after (default: from the clock and the last contract)
##   --backdrop-hero <h> menu: pick this hero for this run without saving it (it stands in front in the garage and the
##                       personnel file shows it), wick | gasket | rebar (default: the saved pick, GameSettings "character")
##   --hero <h>          game: play this hero for this run without saving it (a game flag: it skips the menu)
##   --settings-file <p> read and write the game/voice settings at this path instead of user://settings.cfg
##   --no-mic            no microphone (the menu's voice setup too); does not skip the menu
##   --net-join <ip[:port]>, --net-port <P>, --net-link <preset>, --net-name <name>
##                       online dev flags (NetSession): they show the menu, where a joiner waits with the crew.
##                       --net-host and --net-steam-probe are game flags: they host and open the job board.
## Anything else (--seed, --spells, --contract, --floor, --shot, --zoom ... every game.gd flag, and any flag
## added later) skips the menu, so every dev flow keeps working.

const GAME_SCENE := "res://scenes/game.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"
## Flags that belong to the menu and do not mean "jump into the game".
const MENU_FLAGS: Array[String] = ["--menu", "--menu-shot", "--menu-screen", "--menu-say", "--menu-after", "--menu-void", "--menu-hover", "--menu-focus-file", "--backdrop-mood", "--backdrop-hero", "--settings-file", "--no-mic",
	"--net-join", "--net-port", "--net-link", "--net-name"]


func _ready() -> void:
	InputSetup.ensure_actions()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--run-test")
	if i >= 0 and i + 1 < args.size():
		_run_test(args[i + 1])
		return
	var file := arg_value(args, "--settings-file")
	if file != "":
		GameSettings.path = file
	# Screenshots keep the window as it is; everything else gets the saved volume / window.
	var settings := GameSettings.load_settings()
	GameSettings.apply(settings, not args.has("--shot") and not args.has("--menu-shot"))
	# The hero this player plays (picked in the menu's garage), before NetSession opens a crew with it (its flags run deferred).
	Session.character_id = hero_pick(args, str(settings["character"]))
	get_tree().change_scene_to_file.call_deferred(route(args))


## The hero this run plays: `--hero` (a game flag) or `--backdrop-hero` (a menu flag) for this run only, else the saved pick.
static func hero_pick(args: PackedStringArray, saved: String) -> String:
	for flag in ["--hero", MenuBackdrop.HERO_FLAG]:
		var id := arg_value(args, flag).to_lower()
		if HeroKit.has_kit(id):
			return id
	return saved if HeroKit.has_kit(saved) else NetSession.DEFAULT_CHARACTER


## The scene a command line opens (see the header).
static func route(args: PackedStringArray) -> String:
	var explicit := arg_value(args, "--scene")
	if explicit != "":
		return explicit
	if args.has("--menu"):
		return MENU_SCENE
	for a in args:
		if a.begins_with("--") and not MENU_FLAGS.has(a):
			return GAME_SCENE
	return MENU_SCENE


## The value after `key`, or "".
static func arg_value(args: PackedStringArray, key: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return ""


func _run_test(test_name: String) -> void:
	var path := "res://tests/%s.gd" % test_name
	if not ResourceLoader.exists(path):
		push_error("No such test: " + path)
		print(">>> [TEST FAILED] %s <<<" % test_name)
		get_tree().quit(2)
		return
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		push_error("Test failed to load (parse error?): " + path)
		print(">>> [TEST FAILED] %s <<<" % test_name)
		get_tree().quit(3)
		return
	var t: Node = script.new()
	t.name = test_name
	get_tree().root.add_child.call_deferred(t)

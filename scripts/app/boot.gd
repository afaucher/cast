extends Node
## Entry point. Plain run -> the game. Command-line options (after `--`):
##   --run-test <name>   run res://tests/<name>.gd headless-friendly and quit
##   --scene <res path>  open a specific scene instead of the game

const GAME_SCENE := "res://scenes/game.tscn"


func _ready() -> void:
	InputSetup.ensure_actions()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--run-test")
	if i >= 0 and i + 1 < args.size():
		_run_test(args[i + 1])
		return
	var scene := GAME_SCENE
	i = args.find("--scene")
	if i >= 0 and i + 1 < args.size():
		scene = args[i + 1]
	get_tree().change_scene_to_file.call_deferred(scene)


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

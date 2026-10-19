extends Node
## Writes every dispatch headset line the game can show, from the game's own constants (DispatchVoice.all_lines), as JSON
## [{"key", "text", "spoken", "kind"}]. tools/render_dispatch.ps1 runs it and renders a clip per key.
##   Godot --path . --headless res://tools/dispatch_lines.tscn -- [<out.json>]
## Default output: user://dispatch_lines.json (the path is printed). A scene rather than --script so the autoloads the
## contract scripts name (GameWorld) exist when they compile.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else ProjectSettings.globalize_path("user://dispatch_lines.json")
	var lines := DispatchVoice.all_lines()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("dispatch_lines: cannot write %s" % path)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(lines, "  "))
	f.close()
	var by_kind := {}
	for l in lines:
		by_kind[l["kind"]] = int(by_kind.get(l["kind"], 0)) + 1
	print("dispatch_lines: %d lines %s -> %s" % [lines.size(), JSON.stringify(by_kind), path])
	get_tree().quit(0)

extends SceneTree
## Prints a loudness outline and a spectrum summary of recordings under assets/audio/third_party/ (or any .wav),
## to decide trims, pitch shifts and EQ.
##   Godot --path . --headless --script res://tools/sfx_proto/describe_rec.gd -- [--step 0.01] <file> ...
const Rec = preload("res://tools/sfx_proto/sfx_rec.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var step := 0.05
	if args.size() > 1 and args[0] == "--step":
		step = float(args[1])
		args = args.slice(2)
	for p in args:
		var s := Rec.load_mono(p)
		print("%s\n    %s\n    %s" % [p, Rec.describe(s, step), Rec.spectrum(s)])
	quit()

extends SceneTree
## Writes the prototype procedural sounds (tools/sfx_proto/sfx_synth.gd) as 16-bit mono .wav files to listen to.
##   Godot --path . --headless --script res://tools/sfx_proto/make_sfx.gd -- <out_dir> [cue ...]
## With no cues it writes every recipe the game uses (render_game_sfx.gd GAME_CUES). The unchosen audition rounds were
## removed (docs/history/removed-code.md, wave 2). Nothing here is loaded by the game; see docs/design/audio-plan.md.
const Synth = preload("res://tools/sfx_proto/sfx_round3.gd")   # it extends sfx_synth.gd
const Render = preload("res://tools/sfx_proto/render_game_sfx.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <out_dir> [cue ...]")
		quit(1)
		return
	var out_dir := args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var synth := Synth.new()
	var cues: Array = Array(args.slice(1)) if args.size() > 1 else Render.GAME_CUES.values()
	var failed := 0
	for cue: String in cues:
		var samples: PackedFloat32Array = synth.make(cue)
		var path := out_dir.path_join(cue + ".wav")
		var err := synth.to_wav(samples).save_to_wav(path)
		print("%-18s %5d ms  %s  %s" % [cue, int(samples.size() * 1000.0 / Synth.RATE), error_string(err), path])
		if err != OK:
			failed += 1
	quit(1 if failed > 0 else 0)

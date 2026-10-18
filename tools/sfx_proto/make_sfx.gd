extends SceneTree
## Writes the prototype procedural sounds (tools/sfx_proto/sfx_synth.gd) as 16-bit mono .wav files to listen to.
##   Godot --path . --headless --script res://tools/sfx_proto/make_sfx.gd -- <out_dir> [cue ...]
## With no cues it writes all of them; `v2` / `v4` write only round 2 / round 3. Nothing here is loaded by the game; see docs/design/audio-plan.md.
const Synth = preload("res://tools/sfx_proto/sfx_round3.gd")   # all rounds: it extends sfx_synth.gd


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <out_dir> [cue ...]")
		quit(1)
		return
	var out_dir := args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var synth := Synth.new()
	var cues: Array = Array(args.slice(1)) if args.size() > 1 else Synth.CUES
	if cues == ["v2"]:
		cues = Synth.V2
	elif cues == ["v4"]:
		cues = Synth.CUES3
	var failed := 0
	for cue: String in cues:
		var samples: PackedFloat32Array = synth.make(cue)
		var path := out_dir.path_join(cue + ".wav")
		var err := synth.to_wav(samples).save_to_wav(path)
		print("%-18s %5d ms  %s  %s" % [cue, int(samples.size() * 1000.0 / Synth.RATE), error_string(err), path])
		if err != OK:
			failed += 1
	quit(1 if failed > 0 else 0)

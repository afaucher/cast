extends SceneTree
## Renders the game's sound cues (the user's round 3 picks, 2026-10-18; docs/design/audio-plan.md "As built") into
## assets/audio/sfx/<cue>.wav, where the Sfx autoload (scripts/fx/sfx.gd) loads them. The WAVs are generated, so they
## are gitignored like models/: run this once per checkout (tools/render_sfx.ps1 also reimports them):
##   Godot --path . --headless --script res://tools/sfx_proto/render_game_sfx.gd [-- <out_dir>]
## The recordings the recipes are built from live in assets/audio/third_party/ (also untracked; SOURCES.md says where
## each came from). A cue whose recordings are missing is skipped with an error; the game then keeps it silent.

const Synth = preload("res://tools/sfx_proto/sfx_round3.gd")
const Rec = preload("res://tools/sfx_proto/sfx_rec.gd")

const OUT_DIR := "res://assets/audio/sfx"
## Game cue (Sfx.CUES, the file name) -> prototype recipe (sfx_round3.gd / sfx_synth.gd).
const GAME_CUES := {
	"cast_heard": "cast_armed_v4a2",
	"order_heard": "order_click_v1",
	"fizzle": "fizzle_pfft_v4",
	"fireball": "spell_fireball_v4b",
	"stamp": "stamp_thunk_v4",
	"elevator_ding": "elevator_ding_v4b",
	"paper": "paper_flip",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if not args.is_empty() else ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var synth := Synth.new()
	var failed := 0
	for cue: String in GAME_CUES:
		var recipe: String = GAME_CUES[cue]
		var missing := missing_sources(recipe)
		if not missing.is_empty():
			push_error("render_game_sfx: %s (%s) skipped, missing %s" % [cue, recipe, ", ".join(missing)])
			failed += 1
			continue
		var samples: PackedFloat32Array = synth.make(recipe)
		var path := out_dir.path_join(cue + ".wav")
		var err := synth.to_wav(samples).save_to_wav(path)
		print("%-14s <- %-20s %5d ms  %s  %s" % [cue, recipe, int(samples.size() * 1000.0 / Synth.RATE), error_string(err), path])
		if err != OK:
			failed += 1
	quit(1 if failed > 0 else 0)


## The third-party recordings `recipe` needs that are not on disk (empty for a pure synth recipe).
static func missing_sources(recipe: String) -> Array[String]:
	var out: Array[String] = []
	for src: String in Synth.SOURCES.get(recipe, []):
		if src != "synth" and not FileAccess.file_exists(Rec.ROOT + src):
			out.append(src)
	return out

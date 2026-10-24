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
	"fuse": "fuse_hiss_v6",
	"firework": "firework_v1",
	# sewers and lava (2026-10-21)
	"gator_hiss": "gator_hiss_v3",
	"gator_snap": "gator_snap_v1",
	"gator_splash": "gator_splash_v2",
	"gator_thrash": "gator_thrash_v4",
	"goo_throw": "goo_throw_v2",
	"goo_splat": "goo_splat_v1",
	"goo_splash": "goo_splash_v1",
	"goo_ignite": "goo_ignite_v1",
	"goo_wash": "goo_wash_v1",
	"wire_spark": "wire_spark_v1",
	"wire_shock": "wire_shock_v1",
	"wire_fizzle": "wire_fizzle_v2",
	"wade_step": "wade_step_v1",
	"lava_bubble": "lava_bubble_v1",
	"lava_crust": "lava_crust_v2",
	"lava_crack": "lava_crack_v1",
	"lava_sizzle": "lava_sizzle_v1",
	# footsteps, jumps, climbs, falls, ouch, imps, and default attacks/hits (2026-10-22)
	"step_hard": "step_hard_v1",
	"step_soft": "step_soft_v1",
	"step_wood": "step_wood_v1",
	"step_metal": "step_metal_v1",
	"land_thud": "land_thud_v1",
	"fall_heavy": "fall_heavy_v1",
	"jump": "jump_v1",
	"climb": "climb_v1",
	"ouch": "ouch_v1",
	"ouch_2": "ouch_2_v1",
	"imp_yip": "imp_yip_v1",
	"imp_chatter": "imp_chatter_v1",
	"imp_hurt": "imp_hurt_v1",
	"swing_light": "swing_light_v1",
	"swing_heavy": "swing_heavy_v1",
	"swing_spin": "swing_spin_v1",
	"bow_shot": "bow_shot_v1",
	"boulder_roll": "boulder_roll_v1",
	"slam_ground": "slam_ground_v1",
	"hit_body": "hit_body_v1",
	"hit_heavy": "hit_heavy_v1",
	"hit_arrow": "hit_arrow_v1",
	"hit_shield": "hit_shield_v1",
	"prop_dent": "prop_dent_v1",
	"prop_break": "prop_break_v1",
	"mailbox_break": "mailbox_break_v1",
	# war cries (2026-10-24): every candidate is rendered, so the gym's "War cries" picker can switch them live
	"cry_grunt_a": "cry_grunt_a",
	"cry_grunt_b": "cry_grunt_b",
	"cry_grunt_c": "cry_grunt_c",
	"cry_brute_a": "cry_brute_a",
	"cry_brute_b": "cry_brute_b",
	"cry_brute_c": "cry_brute_c",
	"cry_swarmer_a": "cry_swarmer_a",
	"cry_swarmer_b": "cry_swarmer_b",
	"cry_swarmer_c": "cry_swarmer_c",
	"cry_monster": "cry_monster",
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

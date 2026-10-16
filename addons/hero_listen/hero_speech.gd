class_name HeroSpeech
extends RefCounted
## Model presets for WordListener + a helper that makes model files usable.
##
## sherpa-onnx opens models by filesystem path, so files packed inside an
## exported game (res:// in a .pck / APK) are first copied to user://models.
## In the editor, res:// paths are used directly.

## Trimmed for Cast: only the preset whose model files were copied into
## res://models. (Hero-Reader also lists parakeet-110m-hot, zipformer20m,
## nemo80 and moonshine2-tiny; copy their model dirs and presets back from
## ../Hero-Reader/godot/addons/hero_listen/hero_speech.gd to use them.)
## The first entry is the default. Same short name as stt-eval/engines.py.
## zipformer-hot at hotword score 2 won on real (adult) voice in Hero-Reader.
## The matcher's sound-alike rule is "extra-only" unless a preset sets
## "sound_alike" ("no-onset" or the looser "any"). VoiceCaster does its own
## matching on the hypothesis text, so that rule only affects word_heard.
const PRESETS := {
	"zipformer-hot": {
		"hotwords_score": 2.0, "beam": 8,
		"kind": "streaming", "hotwords": true,
		"dir": "sherpa-onnx-streaming-zipformer-en-2023-06-26",
		"encoder": "encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
		"decoder": "decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
		"joiner": "joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx",
		"tokens": "tokens.txt",
	},
}

const FILE_KEYS := ["encoder", "decoder", "joiner", "tokens"]
const PRON_DICT := "res://data/pron_dict.txt"


## Where models live. Override with the HERO_MODELS environment variable
## (default res://models is filled by tools/setup.py).
static func models_root() -> String:
	var env := OS.get_environment("HERO_MODELS")
	if env != "":
		return env
	return "res://models"


## Build a WordListener config for a preset, copying files out of the
## package first when running an exported build.
static func config_for(preset: String, threads: int = 2) -> Dictionary:
	var p: Dictionary = PRESETS[preset].duplicate()
	var root := models_root()
	var dir := root.path_join(p["dir"])
	var cfg := {}
	for k in p:
		if k != "dir" and not (k in FILE_KEYS):
			cfg[k] = p[k]
	for k in FILE_KEYS:
		if p.has(k):
			cfg[k] = _usable_path(dir.path_join(p[k]))
	if p["kind"] == "vad_offline":
		cfg["vad_model"] = _usable_path(root.path_join("silero_vad.onnx"))
		cfg["min_silence"] = 0.2
		cfg["preroll"] = 0.25
	cfg["threads"] = threads
	cfg["pron_dict"] = _usable_path(PRON_DICT)
	return cfg


static func _usable_path(path: String) -> String:
	if not path.begins_with("res://"):
		return path
	if not OS.has_feature("template"):
		return ProjectSettings.globalize_path(path)  # editor / debug run
	# Exported build (desktop or mobile): copy once into user://.
	var dst := "user://" + path.trim_prefix("res://")
	if not FileAccess.file_exists(dst):
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var data := FileAccess.get_file_as_bytes(path)
		var f := FileAccess.open(dst, FileAccess.WRITE)
		f.store_buffer(data)
		f.close()
	return ProjectSettings.globalize_path(dst)

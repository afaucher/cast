extends Node
## The game's sound effects (autoload `Sfx`; docs/design/audio-plan.md, "As built"). Cosmetic content (AGENTS.md rule 6):
## every machine plays its own sounds from events it already has, nothing here is gameplay state, and no sound ever crosses
## the network. Callers only listen (Game, the HUD, the forms, Fx); nothing in gameplay logic waits on a sound.
##
##   Sfx.play("stamp")                    # non-positional, on the cue's bus
##   Sfx.play_at("fireball", pos)         # 3D at a world point (a non-positional cue plays flat)
##   Sfx.stop_cue("fizzle")               # cut every voice of a cue (a short fade, no click)
##   Sfx.listen_to_voice(caster)          # the voice cues: cast heard, fizzle, and the fizzle cut on new speech
##
## CUES is the table: the file under DIR, the bus (default_bus_layout.tres), volume_db, pitch_jitter (a +- fraction of
## the pitch, rolled on GameWorld.fx_rng), max_voices (the oldest voice of the cue is stolen past it), min_gap (seconds;
## a play sooner than that after the last one is dropped), positional, and for 3D cues unit_size / max_distance.
## The WAVs are rendered from the prototype recipes by tools/sfx_proto/render_game_sfx.gd and are not in git: a missing
## file keeps its cue silent with one warning, never an error.
##
## Headless (tests, the net test processes, a dedicated host) it is OFF: play() returns at once, nothing is loaded or
## built. Tests that need it call enable_for_tests().

const DIR := "res://assets/audio/sfx/"
const CUES := {
	## The recognizer armed a cast (VoiceCaster.trigger_heard). Your machine only; mic-safe by length (audio-plan.md §4).
	"cast_heard": {"file": "cast_heard.wav", "bus": "VoiceFeedback", "volume_db": -3.0, "pitch_jitter": 0.0,
		"max_voices": 1, "min_gap": 0.12, "positional": false},
	## A voice order was heard (VoiceCaster.order_spoken: "Rebar go"): a radio click-click. Your machine only, and not
	## cast_heard (that one means "a cast is armed"). Mic-safe like it: two short ticks, nothing in the speech band.
	"order_heard": {"file": "order_heard.wav", "bus": "VoiceFeedback", "volume_db": -4.0, "pitch_jitter": 0.0,
		"max_voices": 1, "min_gap": 0.15, "positional": false},
	## Your cast fizzled (VoiceCaster.spell_fizzled). Your machine only; cut the moment you start speaking again.
	"fizzle": {"file": "fizzle.wav", "bus": "VoiceFeedback", "volume_db": -2.0, "pitch_jitter": 0.04,
		"max_voices": 1, "min_gap": 0.1, "positional": false},
	## A fireball bursts (Fx.explosion), on every machine (the cast lands everywhere, M4).
	"fireball": {"file": "fireball.wav", "bus": "World", "volume_db": 0.0, "pitch_jitter": 0.06,
		"max_voices": 6, "min_gap": 0.03, "positional": true, "unit_size": 14.0, "max_distance": 70.0},
	## The red name stamp lands on a signature line (SignLine), and the VOID stamp (FormVoid).
	"stamp": {"file": "stamp.wav", "bus": "UI", "volume_db": -2.0, "pitch_jitter": 0.03,
		"max_voices": 2, "min_gap": 0.05, "positional": false},
	## Paper moving on the forms: a form sliding in or changing page, and going back (VOID). Not on focus moves.
	"paper": {"file": "paper.wav", "bus": "UI", "volume_db": -4.0, "pitch_jitter": 0.05,
		"max_voices": 2, "min_gap": 0.18, "positional": false},
	## The elevator doors open (ElevatorArrival.doors_opened).
	"elevator_ding": {"file": "elevator_ding.wav", "bus": "World", "volume_db": -2.0, "pitch_jitter": 0.0,
		"max_voices": 1, "min_gap": 1.5, "positional": true, "unit_size": 16.0, "max_distance": 80.0},
}
const POOL_2D := 8
const POOL_3D := 16
## A cut cue fades out over this long (an instant stop clicks).
const STOP_FADE := 0.025

## Sounds play (false headless until enable_for_tests()).
var enabled := false
## Where the cue files are (tests point it at an empty folder). Changing it forgets the loaded streams.
var dir := DIR:
	set(v):
		dir = v
		_streams.clear()
## Times each cue has started (tests, debug).
var played := {}

var _streams := {}       ## cue -> AudioStream, or null once found missing (warned once)
var _last := {}          ## cue -> Time.get_ticks_msec() of its last play
var _p2d: Array[AudioStreamPlayer] = []
var _p3d: Array[AudioStreamPlayer3D] = []
var _voice := {}         ## player -> [cue, started msec]
var _fades := {}         ## player -> the Tween fading it out (stop_cue)
var _listener: AudioListener3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the forms' stamps play over the pause menu too
	enabled = DisplayServer.get_name() != "headless"
	set_process(false)


## Turn sounds on in a headless test (the players exist and run against the dummy audio driver).
func enable_for_tests() -> void:
	enabled = true


## Back to the headless default: stop everything, drop the counters and any stream a test put in.
func disable_for_tests() -> void:
	for p: Node in _voice.keys():
		_halt(p)
	enabled = DisplayServer.get_name() != "headless"
	played.clear()
	_last.clear()
	dir = DIR


## Tests: play `stream` for `cue` instead of its file.
func override_stream(cue: String, stream: AudioStream) -> void:
	_streams[cue] = stream


## Play a non-positional cue. Returns the player, or null (off, unknown, missing file, too soon).
func play(cue: String) -> Node:
	return _start(cue, Vector3.INF)


## Play `cue` at a world point (a non-positional cue ignores the point). Returns the player, or null.
func play_at(cue: String, pos: Vector3) -> Node:
	return _start(cue, pos)


## Stop every voice of `cue`, fading over `fade` seconds (0: at once).
func stop_cue(cue: String, fade: float = STOP_FADE) -> void:
	if not enabled:
		return
	for p: Node in _voice.keys():
		if _voice[p][0] != cue or not p.get("playing"):
			continue
		_voice[p][0] = ""   # (a fading voice no longer counts as the cue)
		if fade <= 0.0:
			_halt(p)
			continue
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -60.0, fade)
		tw.tween_callback(_halt.bind(p))
		_fades[p] = tw


## A voice of `cue` is playing now.
func is_playing(cue: String) -> bool:
	for p: Node in _voice:
		if _voice[p][0] == cue and p.get("playing"):
			return true
	return false


## The stream for `cue`: loaded on first use; null (warned once) when the file was never rendered.
func stream_of(cue: String) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue]
	var path := dir + str(CUES[cue]["file"]) if CUES.has(cue) else ""
	var s: AudioStream = null
	if path != "" and ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		push_warning("Sfx: no sound for '%s' (%s missing: run tools/render_sfx.ps1); it stays silent" % [cue, path])
	_streams[cue] = s
	return s


## The voice cues for the local player's caster: "cast heard" when a trigger arms, "order heard" for a voice order, the fizzle (unless the player is
## already speaking again), and the fizzle cut the moment the listener hears new speech start (mic safety: a fizzle
## over the next "cast corn" broke it in the probe, audio-plan.md §4).
func listen_to_voice(caster: VoiceCaster) -> void:
	caster.trigger_heard.connect(func(_word: String) -> void: play("cast_heard"))
	caster.order_spoken.connect(func(_who: String, _order: String, _heard: String) -> void: play("order_heard"))
	caster.spell_fizzled.connect(func(_heard: String, _reason: String) -> void:
		if not caster.is_speaking():
			play("fizzle"))
	caster.speech_started.connect(func() -> void: stop_cue("fizzle"))


# --- players --------------------------------------------------------------------------------------

func _start(cue: String, pos: Vector3) -> Node:
	if not enabled or not CUES.has(cue):
		return null
	var c: Dictionary = CUES[cue]
	var now := Time.get_ticks_msec()
	if _last.has(cue) and now - int(_last[cue]) < int(float(c.get("min_gap", 0.0)) * 1000.0):
		return null
	var s := stream_of(cue)
	if s == null:
		return null
	var positional := bool(c.get("positional", false)) and pos != Vector3.INF
	var p: Node = _take(cue, positional, int(c.get("max_voices", 4)))
	_last[cue] = now
	p.set("stream", s)
	p.set("bus", StringName(str(c.get("bus", "Master"))))
	p.set("volume_db", float(c.get("volume_db", 0.0)))
	var jitter := float(c.get("pitch_jitter", 0.0))
	p.set("pitch_scale", 1.0 + (GameWorld.fx_rng.randf_range(-jitter, jitter) if jitter > 0.0 else 0.0))
	if positional:
		var p3 := p as AudioStreamPlayer3D
		p3.unit_size = float(c.get("unit_size", 10.0))
		p3.max_distance = float(c.get("max_distance", 0.0))
		p3.global_position = pos
		_follow_camera()
	_voice[p] = [cue, now]
	p.call("play")
	played[cue] = int(played.get(cue, 0)) + 1
	return p


## A free player of the kind, or the one to steal: the cue's oldest voice past its limit, else the oldest of all.
func _take(cue: String, positional: bool, max_voices: int) -> Node:
	var pool: Array = _p3d if positional else _p2d
	var oldest_cue: Node = null
	var oldest_any: Node = null
	var count := 0
	var free: Node = null
	for p: Node in pool:
		if not p.get("playing"):
			if free == null:
				free = p
			continue
		var v: Array = _voice.get(p, ["", 0])
		if oldest_any == null or int(v[1]) < int(_voice[oldest_any][1]):
			oldest_any = p
		if v[0] == cue:
			count += 1
			if oldest_cue == null or int(v[1]) < int(_voice[oldest_cue][1]):
				oldest_cue = p
	if count >= max_voices and oldest_cue != null:
		_halt(oldest_cue)
		return oldest_cue
	if free != null:
		return free
	if pool.size() < (POOL_3D if positional else POOL_2D):
		return _add_player(positional)
	_halt(oldest_any)
	return oldest_any


func _add_player(positional: bool) -> Node:
	var p: Node
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.panning_strength = 0.7
		_p3d.append(p3)
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		_p2d.append(p2)
		p = p2
	p.name = "Sfx3D%d" % _p3d.size() if positional else "Sfx2D%d" % _p2d.size()
	add_child(p)
	_voice[p] = ["", 0]
	return p


func _halt(p: Node) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw: Tween = _fades.get(p)
	if tw != null:
		_fades.erase(p)
		if tw.is_valid():
			tw.kill()   # (a stolen voice must not be faded out under its new sound)
	p.call("stop")
	_voice[p] = ["", 0]


# --- the listener ---------------------------------------------------------------------------------

## 3D sounds are heard from where the camera looks (the hero), not from the camera: the iso camera sits DISTANCE (60)
## away, which would flatten every distance. The listener takes the camera's rotation, so left and right match the screen.
func _follow_camera() -> void:
	if _listener == null:
		_listener = AudioListener3D.new()
		_listener.name = "Listener"
		add_child(_listener)
		set_process(true)
	_place_listener()


func _process(_delta: float) -> void:
	_place_listener()


func _place_listener() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	var t := cam.global_transform
	var fwd := -t.basis.z
	var focus := t.origin
	if fwd.y < -0.05:
		var ground := 0.0
		var rig := cam.get_parent() as Node3D   # (CameraRig: its origin is the followed point)
		if rig != null:
			ground = rig.global_position.y
		focus = t.origin + fwd * clampf((ground - t.origin.y) / fwd.y, 0.0, 200.0)
	_listener.global_transform = Transform3D(t.basis, focus)
	if not _listener.is_current():
		_listener.make_current()

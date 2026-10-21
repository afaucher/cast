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
## a play sooner than that after the last one is dropped), positional, and for 3D cues unit_size / max_distance. A cue
## with a duck_db (a long bed: the lava's bubbling) goes down that many dB while the local player speaks (_tick_duck).
## ear() is where 3D sounds are heard from, for placing an ambient emitter near the player.
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
	## An explosive prop's fuse is lit (FuseFx), on every machine (the host's obj.fuse); its blast is the "fireball" cue.
	## Front-loaded and above 4.5 kHz (audio-plan.md §4); a doused fuse cuts it.
	"fuse": {"file": "fuse.wav", "bus": "World", "volume_db": -3.0, "pitch_jitter": 0.06,
		"max_voices": 4, "min_gap": 0.05, "positional": true, "unit_size": 12.0, "max_distance": 60.0},
	## One goblin-scout rocket (FireworksFx: each rocket as it launches, its bang on the burst), on every machine (the
	## world.fireworks event). Wide pitch jitter so a volley reads as several rockets.
	"firework": {"file": "firework.wav", "bus": "World", "volume_db": -4.0, "pitch_jitter": 0.12,
		"max_voices": 4, "min_gap": 0.08, "positional": true, "unit_size": 14.0, "max_distance": 80.0},
	## The elevator doors open (ElevatorArrival.doors_opened).
	"elevator_ding": {"file": "elevator_ding.wav", "bus": "World", "volume_db": -2.0, "pitch_jitter": 0.0,
		"max_voices": 1, "min_gap": 1.5, "positional": true, "unit_size": 16.0, "max_distance": 80.0},
	# --- sewers and lava (2026-10-21; audio-plan.md "Sewers and lava"). Every one from events every machine already has.
	## The gator's nip wind-up starts (its state turns NIP, host or puppet: Gator._sounds). Front-loaded, the rest above 4.5 kHz.
	"gator_hiss": {"file": "gator_hiss.wav", "bus": "World", "volume_db": -6.0, "pitch_jitter": 0.06,
		"max_voices": 3, "min_gap": 0.1, "positional": true, "unit_size": 10.0, "max_distance": 50.0},
	## The gator's bite (Gator._strike: the host's at its lunge, a client's when its screen reaches the wind-up's moment).
	"gator_snap": {"file": "gator_snap.wav", "bus": "World", "volume_db": -3.0, "pitch_jitter": 0.08,
		"max_voices": 3, "min_gap": 0.05, "positional": true, "unit_size": 10.0, "max_distance": 55.0},
	## A gator goes into or out of the water (Gator._sounds, at most one a second per gator).
	"gator_splash": {"file": "gator_splash.wav", "bus": "World", "volume_db": -5.0, "pitch_jitter": 0.08,
		"max_voices": 3, "min_gap": 0.2, "positional": true, "unit_size": 10.0, "max_distance": 50.0},
	## A gator dies (Gator._on_death, every machine): the thrash.
	"gator_thrash": {"file": "gator_thrash.wav", "bus": "World", "volume_db": -3.0, "pitch_jitter": 0.05,
		"max_voices": 2, "min_gap": 0.3, "positional": true, "unit_size": 12.0, "max_distance": 60.0},
	## A goo imp's ball leaves its hand (GooBall._ready: the host's ball and every client's copy).
	"goo_throw": {"file": "goo_throw.wav", "bus": "World", "volume_db": -8.0, "pitch_jitter": 0.12,
		"max_voices": 4, "min_gap": 0.06, "positional": true, "unit_size": 8.0, "max_distance": 45.0},
	## The ball lands on the floor or on someone (GooBall._splash), or in the water (goo_splash).
	"goo_splat": {"file": "goo_splat.wav", "bus": "World", "volume_db": -5.0, "pitch_jitter": 0.12,
		"max_voices": 4, "min_gap": 0.05, "positional": true, "unit_size": 9.0, "max_distance": 50.0},
	"goo_splash": {"file": "goo_splash.wav", "bus": "World", "volume_db": -6.0, "pitch_jitter": 0.12,
		"max_voices": 4, "min_gap": 0.05, "positional": true, "unit_size": 9.0, "max_distance": 50.0},
	## A goo patch is lit (GooPatch.light: the host's decision, a client's from obj.goo): the whoomph.
	"goo_ignite": {"file": "goo_ignite.wav", "bus": "World", "volume_db": -3.0, "pitch_jitter": 0.06,
		"max_voices": 3, "min_gap": 0.08, "positional": true, "unit_size": 12.0, "max_distance": 60.0},
	## A goo patch is washed away by damp (GooPatch.wash): the fizz.
	"goo_wash": {"file": "goo_wash.wav", "bus": "World", "volume_db": -7.0, "pitch_jitter": 0.08,
		"max_voices": 3, "min_gap": 0.05, "positional": true, "unit_size": 9.0, "max_distance": 50.0},
	## The live wire's panel breaks (LiveWire._on_broken, from the panel's obj.break on every machine): sparks.
	"wire_spark": {"file": "wire_spark.wav", "bus": "World", "volume_db": -3.0, "pitch_jitter": 0.05,
		"max_voices": 2, "min_gap": 0.2, "positional": true, "unit_size": 12.0, "max_distance": 60.0},
	## (No buzz while the wire is live: every sustained buzz tried failed the mic-leak probe, audio-plan.md "Sewers and
	## lava"; the pulses' cracks carry it.)
	## Each shock and pulse of the live wire (LiveWire._shock_fx): the crack.
	"wire_shock": {"file": "wire_shock.wav", "bus": "World", "volume_db": -2.0, "pitch_jitter": 0.05,
		"max_voices": 3, "min_gap": 0.1, "positional": true, "unit_size": 14.0, "max_distance": 70.0},
	## The breaker trips: the cable dies (LiveWire, the end of PULSE_FOR).
	"wire_fizzle": {"file": "wire_fizzle.wav", "bus": "World", "volume_db": -6.0, "pitch_jitter": 0.04,
		"max_voices": 2, "min_gap": 0.3, "positional": true, "unit_size": 10.0, "max_distance": 50.0},
	## A hero's step in the water (Wading: one per STEP_EVERY units walked wading, every machine from the shown position).
	"wade_step": {"file": "wade_step.wav", "bus": "World", "volume_db": -14.0, "pitch_jitter": 0.15,
		"max_voices": 4, "min_gap": 0.07, "positional": true, "unit_size": 6.0, "max_distance": 30.0},
	## The bubbling bed near lava (LavaField: a 4 s play at one of the two lava spots nearest the ear every ~1.7 s, so plays
	## overlap). Quiet, all under 600 Hz, and ducked while you speak (duck_db).
	"lava_bubble": {"file": "lava_bubble.wav", "bus": "World", "volume_db": -16.0, "pitch_jitter": 0.08, "duck_db": -10.0,
		"max_voices": 3, "min_gap": 0.5, "positional": true, "unit_size": 6.0, "max_distance": 28.0},
	## Damp crusts the lava (LavaField._make_crust): the steam.
	"lava_crust": {"file": "lava_crust.wav", "bus": "World", "volume_db": -4.0, "pitch_jitter": 0.05,
		"max_voices": 3, "min_gap": 0.15, "positional": true, "unit_size": 12.0, "max_distance": 60.0},
	## A crust's last CRUST_WARN seconds begin (LavaField): the rock cracking.
	"lava_crack": {"file": "lava_crack.wav", "bus": "World", "volume_db": -4.0, "pitch_jitter": 0.04,
		"max_voices": 3, "min_gap": 0.2, "positional": true, "unit_size": 12.0, "max_distance": 60.0},
	## Something lands in the lava (LavaField._on_impact: a hero pulled back out, a monster sinking): the sizzle.
	"lava_sizzle": {"file": "lava_sizzle.wav", "bus": "World", "volume_db": -3.0, "pitch_jitter": 0.06,
		"max_voices": 3, "min_gap": 0.1, "positional": true, "unit_size": 12.0, "max_distance": 60.0},
}
## Cues with a "duck_db" (the long beds) go down by it while the local player speaks (audio-plan.md §4 rule 4, built for
## those cues only): down in DUCK_ATTACK, held DUCK_HOLD after the voice stops, back up over DUCK_RELEASE.
const DUCK_ATTACK := 0.03
const DUCK_HOLD := 0.3
const DUCK_RELEASE := 0.25
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
var _caster: WeakRef = null      ## the local player's VoiceCaster (listen_to_voice): the ducking listens to it
var _duck_k := 0.0               ## 0..1: how far the ducking cues are down now
var _spoke_ms := -100000         ## Time.get_ticks_msec() the local player was last heard speaking


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
	_duck_k = 0.0
	_spoke_ms = -100000
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
	_caster = weakref(caster)
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
	p.set("volume_db", float(c.get("volume_db", 0.0)) + float(c.get("duck_db", 0.0)) * _duck_k)
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


func _process(delta: float) -> void:
	_place_listener()
	_tick_duck(delta)


func _place_listener() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return
	_listener.global_transform = Transform3D(cam.global_transform.basis, _focus(cam))
	if not _listener.is_current():
		_listener.make_current()


## Where the camera looks: its view ray meeting the followed point's height (the CameraRig origin).
func _focus(cam: Camera3D) -> Vector3:
	var t := cam.global_transform
	var fwd := -t.basis.z
	if fwd.y >= -0.05:
		return t.origin
	var ground := 0.0
	var rig := cam.get_parent() as Node3D   # (CameraRig: its origin is the followed point)
	if rig != null:
		ground = rig.global_position.y
	return t.origin + fwd * clampf((ground - t.origin.y) / fwd.y, 0.0, 200.0)


## Where 3D sounds are heard from (the listener's spot: the camera's focus), for placing ambient emitters near the player
## (LavaField's bed). Vector3.INF when sounds are off or there is no camera.
func ear() -> Vector3:
	if not enabled or not is_inside_tree():
		return Vector3.INF
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return _focus(cam) if cam != null else Vector3.INF


## The ducking cues (a "duck_db" in CUES) go down while the local player speaks (VoiceCaster.is_speaking, from
## listen_to_voice), held DUCK_HOLD after, so a long bed never sits under the player's words (audio-plan.md §4 rule 4).
func _tick_duck(delta: float) -> void:
	var c: VoiceCaster = _caster.get_ref() as VoiceCaster if _caster != null else null
	var now := Time.get_ticks_msec()
	if c != null and c.is_speaking():
		_spoke_ms = now
	var want := 1.0 if now - _spoke_ms < int(DUCK_HOLD * 1000.0) else 0.0
	var k := move_toward(_duck_k, want, delta / (DUCK_ATTACK if want > _duck_k else DUCK_RELEASE))
	if is_equal_approx(k, _duck_k):
		return
	_duck_k = k
	for p: Node in _voice:
		var cue: String = _voice[p][0]
		if cue == "" or not CUES.has(cue) or not CUES[cue].has("duck_db") or _fades.has(p):
			continue
		p.set("volume_db", float(CUES[cue]["volume_db"]) + float(CUES[cue]["duck_db"]) * _duck_k)


## How far the ducking cues are down now, 0..1 (tests).
func duck_level() -> float:
	return _duck_k

extends SceneTree
## Mic stall probe: shows why VoiceCaster reads the input device directly.
##
##   godot --path . --audio-driver WASAPI --script res://tools/mic_probe.gd
##
## Two paths read the mic at once:
##   M = AudioStreamMicrophone -> muted bus -> AudioEffectCapture (what Cast used before 2026-10-17)
##   D = AudioServer.get_input_frames (what VoiceCaster uses now)
## After LIVE_SEC the input device is stopped, standing in for a mic that went to sleep or was taken
## by another app. Every loud 10 ms block is fingerprinted; real mic audio never repeats bit for bit.
## Expected: during "stalled" M keeps delivering ~48k frames/s that are almost all REPEATS (its ring
## buffer on a loop: phantom words), D delivers nothing. After the restart D resumes cleanly.
## Needs a real audio driver (not --headless) and any sound in the room.

const LIVE_SEC := 6.0          ## longer than the 4 s ring buffer: the replay needs a full ring
const STALL_SEC := 6.0
const RESTART_SEC := 4.0

var _cap: AudioEffectCapture
var _t := 0.0
var _phase := ""
var _phase_t := 0.0
var _stats := {}
var _seen := {"M": {}, "D": {}}
var _acc := {"M": PackedVector2Array(), "D": PackedVector2Array()}


func _initialize() -> void:
	print("inputs: ", AudioServer.get_input_device_list(), "  current: ", AudioServer.input_device)
	print("mix rate out %d, in %d" % [AudioServer.get_mix_rate(), AudioServer.get_input_mix_rate()])
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "ProbeMic")
	AudioServer.set_bus_mute(bus, true)
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 0.5
	AudioServer.add_bus_effect(bus, _cap)
	var player := AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = "ProbeMic"
	root.add_child.call_deferred(player)
	player.play.call_deferred()
	print("direct input: ", error_string(AudioServer.set_input_device_active(true)),
			", ring buffer ", AudioServer.get_input_buffer_length_frames(), " frames")
	_begin("live")


func _process(delta: float) -> bool:
	_t += delta
	var n := _cap.get_frames_available()
	if n > 0:
		_eat("M", _cap.get_buffer(n))
	var m := AudioServer.get_input_frames_available()
	if m > 0:
		_eat("D", AudioServer.get_input_frames(m))
	if _phase == "live" and _t > LIVE_SEC:
		_begin("stalled")
		AudioServer.set_input_device_active(false)
	elif _phase == "stalled" and _t > LIVE_SEC + STALL_SEC:
		_begin("restarted")
		AudioServer.input_device = AudioServer.input_device
		AudioServer.set_input_device_active(true)
	elif _phase == "restarted" and _t > LIVE_SEC + STALL_SEC + RESTART_SEC:
		_begin("")
		AudioServer.set_input_device_active(false)
		return true
	return false


func _begin(p: String) -> void:
	if _phase != "":
		var secs := maxf(_t - _phase_t, 0.001)
		for k: String in ["M", "D"]:
			var s: Array = _stats[k]
			print("  %-9s %s: %7d frames (%5.0f/s)  loud blocks %4d  REPEATS %4d" % [_phase, k, s[0], s[0] / secs, s[1], s[2]])
	_phase = p
	_phase_t = _t
	_stats = {"M": [0, 0, 0], "D": [0, 0, 0]}


func _eat(k: String, f: PackedVector2Array) -> void:
	_stats[k][0] += f.size()
	var acc: PackedVector2Array = _acc[k]
	acc.append_array(f)
	var pos := 0
	while acc.size() - pos >= 480:
		var b: PackedVector2Array = acc.slice(pos, pos + 480)
		pos += 480
		var e := 0.0
		for v in b:
			e += v.x * v.x
		if e / 480.0 < 1e-7:
			continue
		_stats[k][1] += 1
		var h := hash(b)
		if _seen[k].has(h):
			_stats[k][2] += 1
		_seen[k][h] = true
	_acc[k] = acc.slice(pos)

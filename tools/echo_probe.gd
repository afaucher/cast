extends SceneTree
## Echo probe: how much of what the game plays comes back in through the mic, and how late.
## A lab tool for docs/design/echo-cancellation-research.md; nothing in the game uses it.
##
##   godot --path . --display-driver headless --audio-driver WASAPI --script res://tools/echo_probe.gd -- <out_dir> [sweeps] [amp] [every_sec] [sweep_sec]
##
## Plays `sweeps` short exponential sine sweeps (200 Hz -> 8 kHz, sweep_sec long (0.25 s), one every every_sec (1.5 s),
## peak `amp`, default 0.25, about -12 dBFS) through the normal output, and records two streams at once:
##   ref = the Master bus, tapped with an AudioEffectCapture: exactly what the game mixed (what an AEC needs as its
##         reference), written at mix time, i.e. before the output latency;
##   mic = the input device, read like VoiceCaster does (AudioServer.get_input_frames).
## Writes <out_dir>/ref.f32 and mic.f32 (mono float32, the mix rate) and meta.json: rates, the driver's output latency,
## the input buffer length, and each read's (ticks_usec, frames so far) so the two sample clocks can be put on one
## time line. tools/echo_probe_analyze.py estimates the delay (GCC-PHAT per sweep), the echo level and the
## cancellation a linear filter could reach. Needs a real audio driver (not --headless). It makes sound: keep the
## volume moderate.

const LEAD_SEC := 1.0
const F0 := 200.0
const F1 := 8000.0

var _out := ""
var _sweeps := 20
var _amp := 0.25
var sweep_sec := 0.25
var every_sec := 1.5
var _cap: AudioEffectCapture
var _player: AudioStreamPlayer
var _ref := PackedFloat32Array()
var _mic := PackedFloat32Array()
var _ref_reads: Array = []
var _mic_reads: Array = []
var _t := 0.0
var _started := false
var _total := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <out_dir> [sweeps] [amp] [every_sec] [sweep_sec]")
		quit(1)
		return
	_out = args[0]
	if args.size() > 1:
		_sweeps = int(args[1])
	if args.size() > 2:
		_amp = float(args[2])
	if args.size() > 3:
		every_sec = float(args[3])
	if args.size() > 4:
		sweep_sec = float(args[4])
	DirAccess.make_dir_recursive_absolute(_out)
	var rate := int(AudioServer.get_mix_rate())
	print("output device: %s  input device: %s" % [AudioServer.output_device, AudioServer.input_device])
	print("mix rate out %d, in %d; output latency %.1f ms" % [
		rate, AudioServer.get_input_mix_rate(), AudioServer.get_output_latency() * 1000.0])
	_cap = AudioEffectCapture.new()
	_cap.buffer_length = 2.0
	AudioServer.add_bus_effect(0, _cap)   # Master: the whole mix, after its limiter
	if AudioServer.set_input_device_active(true) != OK:
		push_error("no input device")
		quit(1)
		return
	print("input ring buffer %d frames" % AudioServer.get_input_buffer_length_frames())
	_player = AudioStreamPlayer.new()
	_player.stream = _program(rate)
	root.add_child.call_deferred(_player)
	_total = LEAD_SEC + _sweeps * every_sec + 1.0


## The sweeps as one 16-bit WAV at the mix rate (no resampling between the file and the mix).
func _program(rate: int) -> AudioStreamWAV:
	var n := int(rate * _sweeps * every_sec)
	var data := PackedByteArray()
	data.resize(n * 2)
	var m := int(rate * sweep_sec)
	var k := log(F1 / F0)
	for s in _sweeps:
		var base := int(s * every_sec * rate)
		for i in m:
			var t := float(i) / rate
			var phase := TAU * F0 * sweep_sec / k * (exp(t / sweep_sec * k) - 1.0)
			var env := minf(1.0, minf(float(i) / (0.005 * rate), float(m - i) / (0.005 * rate)))
			data.encode_s16((base + i) * 2, int(clampf(_amp * env * sin(phase), -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _process(delta: float) -> bool:
	_t += delta
	var now := Time.get_ticks_usec()
	var n := _cap.get_frames_available()
	if n > 0:
		_append(_ref, _cap.get_buffer(n))
		_ref_reads.append([now, _ref.size()])
	var m := AudioServer.get_input_frames_available()
	if m > 0:
		_append(_mic, AudioServer.get_input_frames(m))
		_mic_reads.append([now, _mic.size()])
	if not _started and _t >= LEAD_SEC:
		_started = true
		_player.play()
		print("playing at ref frame %d, mic frame %d" % [_ref.size(), _mic.size()])
	if _t >= _total:
		_finish()
		return true
	return false


func _append(dst: PackedFloat32Array, frames: PackedVector2Array) -> void:
	var at := dst.size()
	dst.resize(at + frames.size())
	for i in frames.size():
		dst[at + i] = (frames[i].x + frames[i].y) * 0.5


func _finish() -> void:
	AudioServer.set_input_device_active(false)
	_write("ref.f32", _ref)
	_write("mic.f32", _mic)
	var meta := {
		"mix_rate": AudioServer.get_mix_rate(), "input_mix_rate": AudioServer.get_input_mix_rate(),
		"output_latency_s": AudioServer.get_output_latency(),
		"input_buffer_frames": AudioServer.get_input_buffer_length_frames(),
		"output_device": AudioServer.output_device, "input_device": AudioServer.input_device,
		"sweeps": _sweeps, "amp": _amp, "sweep_sec": sweep_sec, "every_sec": every_sec, "f0": F0, "f1": F1,
		"ref_reads": _ref_reads, "mic_reads": _mic_reads,
	}
	var f := FileAccess.open(_out.path_join("meta.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	print("wrote %d ref and %d mic frames to %s" % [_ref.size(), _mic.size(), _out])


func _write(file: String, a: PackedFloat32Array) -> void:
	var f := FileAccess.open(_out.path_join(file), FileAccess.WRITE)
	f.store_buffer(a.to_byte_array())
	f.close()

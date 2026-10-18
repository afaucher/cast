class_name NetLink
extends RefCounted
## The lag and loss simulator (networking.md "Day-one infrastructure" item 6). It sits on EVERY process's
## INBOUND side, inside NetWire, so with every peer running it both directions of every connection are
## simulated: a client's messages to the host are as late as the host's to the client. (Bridge delayed only
## inbound snapshots on clients, so the input path was never simulated; its own post-mortem.)
##
## - Unreliable packets are delayed by latency +- jitter (so they can arrive out of order) and dropped with
##   probability `loss`.
## - Reliable events are delayed by the same latency +- jitter but never dropped and never reordered: each
##   release time is at least the previous one, which is what an ordered reliable channel looks like after a
##   retransmit.
##
## Times are wall-clock microseconds (Time.get_ticks_usec), never game time: the link has to behave the same
## when a frame hitches. Items are released when the owner polls (every frame), so the effective resolution
## is one frame (about 16 ms at 60 fps) on top of the configured delay.
##
## Real Steam play uses Steam's own FakePacket* config values instead (M7); ENet runs use this.

const PRESETS := {
	"off": {"latency_ms": 0.0, "jitter_ms": 0.0, "loss": 0.0},
	## Coast-to-coast US through a relay: 45 ms each way (90 ms RTT), +-15 ms jitter, 1.5% loss.
	"coast": {"latency_ms": 45.0, "jitter_ms": 15.0, "loss": 0.015},
	## A bad evening: 80 ms each way, +-30 ms jitter, 4% loss.
	"rough": {"latency_ms": 80.0, "jitter_ms": 30.0, "loss": 0.04},
}

var preset := "off"
var latency_ms := 0.0
var jitter_ms := 0.0
var loss := 0.0

## Counters since configure(): unreliable packets dropped, items delayed.
var dropped := 0
var delayed := 0

var _rng := RandomNumberGenerator.new()
var _unreliable: Array = []      ## [release_usec, item], kept sorted by release time
var _reliable: Array = []        ## [release_usec, item], FIFO (release times never decrease)
var _last_reliable_usec := 0


func _init(preset_name: String = "off", rng_seed: int = 1) -> void:
	_rng.seed = rng_seed
	configure(preset_name)


## Pick a preset by name ("off", "coast", "rough"). Unknown names are refused (returns false, link off).
func configure(preset_name: String) -> bool:
	var ok := PRESETS.has(preset_name)
	var p: Dictionary = PRESETS[preset_name] if ok else PRESETS["off"]
	preset = preset_name if ok else "off"
	latency_ms = float(p["latency_ms"])
	jitter_ms = float(p["jitter_ms"])
	loss = float(p["loss"])
	dropped = 0
	delayed = 0
	return ok


func seed_with(value: int) -> void:
	_rng.seed = value


func is_active() -> bool:
	return latency_ms > 0.0 or jitter_ms > 0.0 or loss > 0.0


## Items waiting to be released (both kinds).
func held() -> int:
	return _unreliable.size() + _reliable.size()


## An inbound unreliable packet. Returns false when the link "lost" it.
func push_unreliable(now_usec: int, item: Variant) -> bool:
	if loss > 0.0 and _rng.randf() < loss:
		dropped += 1
		return false
	var at := now_usec + _delay_usec()
	# Insert sorted (the queue is short: a few frames of traffic).
	var i := _unreliable.size()
	while i > 0 and int(_unreliable[i - 1][0]) > at:
		i -= 1
	_unreliable.insert(i, [at, item])
	delayed += 1
	return true


## An inbound reliable event: delayed, never lost, never overtakes an earlier one.
func push_reliable(now_usec: int, item: Variant) -> void:
	var at := maxi(now_usec + _delay_usec(), _last_reliable_usec)
	_last_reliable_usec = at
	_reliable.append([at, item])
	delayed += 1


## Everything due by `now_usec`: reliable items first (in order), then unreliable ones in release order.
func pop_due(now_usec: int) -> Array:
	var out: Array = []
	while not _reliable.is_empty() and int(_reliable[0][0]) <= now_usec:
		out.append(_reliable.pop_front()[1])
	while not _unreliable.is_empty() and int(_unreliable[0][0]) <= now_usec:
		out.append(_unreliable.pop_front()[1])
	return out


## Drop everything still held (the session ended).
func clear() -> void:
	_unreliable.clear()
	_reliable.clear()
	_last_reliable_usec = 0


func _delay_usec() -> int:
	var ms := latency_ms
	if jitter_ms > 0.0:
		ms += _rng.randf_range(-jitter_ms, jitter_ms)
	return int(maxf(ms, 0.0) * 1000.0)

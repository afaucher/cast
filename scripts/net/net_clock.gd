class_name NetClock
extends RefCounted
## The shared session clock (networking.md "Day-one infrastructure" item 4): `host_time()`, in seconds since
## the host opened the session, on every machine.
##
## The host's clock is its own wall clock. A client runs NTP-style pings (NetSession sends one every
## PING_INTERVAL; faster for the first second). A pong that left the client at local t0, was stamped host_t
## by the host and arrived at local t2 bounds the offset (host time minus local time):
##     host_t - t2  <=  offset  <=  host_t - t0      (each leg took >= 0)
## The client keeps the last WINDOW samples and INTERSECTS their bounds: the tightest lower bound comes from
## the pong with the fastest return leg, the tightest upper bound from the ping with the fastest outbound leg,
## even when those were different round trips. The midpoint is the target, so the error is half the
## difference between the two best one-way legs (plain min-RTT needs one round trip lucky on both legs at
## once; under jitter that is rarely the same sample). If the bounds ever cross (clock drift), the min-RTT
## sample's midpoint is used. With no lag the limit is the polling: packets are only seen once per frame on
## each side, and with both sides at the same frame rate the frame phase is unobservable, so the error can sit
## anywhere within half a frame (8.3 ms at 60 fps); it shrinks when frame rates differ.
##
## The clock is SLEWED toward the target at up to SLEW (5%) instead of jumping, so host_time() never runs
## backwards and never leaps; only the very first sample (and an error over SNAP_SEC, i.e. a broken clock)
## sets it outright. Bridge adopted the host tick once and drifted; this keeps adjusting for the whole session.
##
## Measured (test_net_clock, 60 fps, one machine): about 2-8 ms of error with no link; under `coast` up to
## about one frame (17 ms) while the window still lacks a sample whose leg hit the link's minimum delay.
## Round trips come out in whole frames (100, 117, 133 ms under coast) for the same polling reason.
##
## Wall-clock microseconds (Time.get_ticks_usec), never game time, so a hitch or a paused tree can't skew it.

const PING_INTERVAL := 0.5
const FAST_PINGS := 20            ## the first pings go out every FAST_INTERVAL, so the clock settles quickly
const FAST_INTERVAL := 0.05
const WINDOW := 24                ## samples kept (about 12 s at the normal rate)
const SLEW := 0.05                ## at most 50 ms of correction per second
const SNAP_SEC := 1.0             ## an error this large is a broken clock, not drift: set it outright

var is_host := false
var synced := false               ## a client has had at least one pong (the host is always synced)
var samples := 0                  ## pongs received

var rtt_ms := 0.0                 ## the latest round trip
var rtt_min_ms := 0.0             ## the lowest round trip in the window
var jitter_ms := 0.0              ## RFC 3550-style smoothed variation between consecutive round trips

var _epoch_usec := 0              ## host: local time at host_time 0
var _offset := 0.0                ## client: host_time - local seconds, as applied (slewed)
var _target := 0.0                ## client: the offset the best sample says
var _window: Array = []           ## [rtt_sec, lower bound, upper bound] (offsets in seconds)
var _last_usec := 0               ## the last advance()
var _last_returned := 0.0
var _last_rtt := -1.0


## Host: start the clock at 0 now.
func start_host(now_usec: int) -> void:
	is_host = true
	synced = true
	_epoch_usec = now_usec
	_last_usec = now_usec
	_last_returned = 0.0


## Client: forget everything; host_time() is 0 until the first pong.
func start_client(now_usec: int) -> void:
	is_host = false
	synced = false
	samples = 0
	_window.clear()
	_offset = 0.0
	_target = 0.0
	_last_usec = now_usec
	_last_returned = 0.0
	_last_rtt = -1.0
	rtt_ms = 0.0
	rtt_min_ms = 0.0
	jitter_ms = 0.0


## Seconds since the host opened the session, as this machine best knows it. Never decreases.
func host_time(now_usec: int) -> float:
	if not synced:
		return 0.0
	var t := raw_host_time(now_usec)
	if t < _last_returned:
		t = _last_returned
	_last_returned = t
	return t


## host_time() before the never-backwards guard (tests check the slewing itself never runs backwards).
func raw_host_time(now_usec: int) -> float:
	if is_host:
		return float(now_usec - _epoch_usec) / 1e6
	return float(now_usec) / 1e6 + _offset


## A pong arrived: the ping left at local t0, the host stamped host_t, it arrived at local t2.
func add_sample(t0_usec: int, host_t: float, t2_usec: int) -> void:
	var t0 := float(t0_usec) / 1e6
	var t2 := float(t2_usec) / 1e6
	var rtt := maxf(t2 - t0, 0.0)
	_window.append([rtt, host_t - t2, host_t - t0])
	while _window.size() > WINDOW:
		_window.pop_front()
	samples += 1
	if _last_rtt >= 0.0:
		jitter_ms += (absf(rtt - _last_rtt) * 1000.0 - jitter_ms) / 16.0
	_last_rtt = rtt
	rtt_ms = rtt * 1000.0
	var best: Array = _window[0]
	var lo := -INF
	var hi := INF
	for s: Array in _window:
		if float(s[0]) < float(best[0]):
			best = s
		lo = maxf(lo, float(s[1]))
		hi = minf(hi, float(s[2]))
	rtt_min_ms = float(best[0]) * 1000.0
	_target = (lo + hi) * 0.5 if lo <= hi else (float(best[1]) + float(best[2])) * 0.5
	if not synced:
		synced = true
		_offset = _target


## Called every frame: slew the applied offset toward the target.
func advance(now_usec: int) -> void:
	var dt := maxf(float(now_usec - _last_usec) / 1e6, 0.0)
	_last_usec = now_usec
	if is_host or not synced:
		return
	var err := _target - _offset
	if absf(err) > SNAP_SEC:
		_offset = _target
		return
	var step := SLEW * dt
	_offset += clampf(err, -step, step)


## How far the applied clock still is from the best estimate, in ms (telemetry).
func pending_correction_ms() -> float:
	return (_target - _offset) * 1000.0


## Seconds until the next ping is due, given how many have been sent.
static func ping_interval(sent: int) -> float:
	return FAST_INTERVAL if sent < FAST_PINGS else PING_INTERVAL

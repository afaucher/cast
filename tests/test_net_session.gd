extends TestCase
## NetSession in ONE process (networking-build-plan.md M0a "done when"), plus the M0b building blocks:
## - offline: local_id() is 0 (multiplayer's own id is 1 offline too, the Bridge trap), Net.is_host() is
##   true, there is no roster and no clock;
## - two NetSessions under their own SceneMultiplayer roots over ENet: hello, seats, the same roster on both
##   ends, names, character ids, peer ids, the clock syncs;
## - "Different build" refusal; a client leaving; a host going silent (100% loss on the client's inbound
##   side: "The host clocked out" after HOST_SILENCE); the host leaving (its goodbye arrives at once);
## - units: u16 sequence wrap (NetWire.seq_newer), the link simulator (loss rate, delay window, reliable order),
##   the clock (interval intersection beats min-RTT, slewing never runs backwards).

const PORT := 28778
const TIMEOUT := 60.0

var _t0 := 0


func setup() -> void:
	# This test waits on the wall clock (the session's timers are wall time); --fixed-fps game time races.
	for c in get_children():
		if c is Timer:
			(c as Timer).stop()
	_t0 = Time.get_ticks_msec()
	_check_offline()
	_check_seq()
	_check_link()
	_check_clock()
	await _check_sessions()
	finish()


func _process(_delta: float) -> void:
	if _t0 > 0 and Time.get_ticks_msec() - _t0 > int(TIMEOUT * 1000.0):
		_t0 = 0
		_fail("timed out after %.0f s (wall clock)" % TIMEOUT)
		finish()


func _until(cond: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not bool(cond.call()):
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true


# --- Offline -----------------------------------------------------------------------------------------

func _check_offline() -> void:
	check(Session != null and Session is NetSession, "the Session autoload exists")
	eq(Session.local_id(), 0, "local_id() is 0 offline")
	eq(multiplayer.get_unique_id(), 1, "(the trap: the offline multiplayer id is 1, so it can't mean 'host')")
	check(not Session.online() and not Net.online(), "offline")
	check(Net.is_host() and Session.is_host(), "offline counts as the host: solo code paths don't change")
	eq(Session.host_time(), 0.0, "no session clock offline")
	check(Session.roster.is_empty() and Session.crew().is_empty(), "no roster offline")
	eq(NetSession.DEFAULT_CHARACTER, MenuBackdrop.PLAYER_HERO, "the default character id is the menu's player hero")
	eq(Session.local_character(), NetSession.DEFAULT_CHARACTER, "the hello carries the default character until one is chosen")
	check(Session.telemetry == null, "no telemetry offline")


# --- Units -------------------------------------------------------------------------------------------

func _check_seq() -> void:
	check(NetWire.seq_newer(1, 0), "1 is newer than 0")
	check(NetWire.seq_newer(0, 65535), "0 is newer than 65535 (the u16 wrap)")
	check(NetWire.seq_newer(10, 65530), "10 is newer than 65530")
	check(not NetWire.seq_newer(65535, 0), "65535 is older than 0")
	check(not NetWire.seq_newer(5, 5), "a duplicate is not newer")
	check(not NetWire.seq_newer(40000, 5), "half the ring away counts as older")


func _check_link() -> void:
	var off := NetLink.new("off")
	check(not off.is_active(), "the off link is inert")
	check(not NetLink.new().configure("bogus"), "an unknown preset is refused")
	var link := NetLink.new("coast", 7)
	check(link.is_active() and link.latency_ms == 45.0 and link.jitter_ms == 15.0 and link.loss == 0.015, "coast: 45 ms +-15, 1.5% loss")
	var n := 20000
	for i in n:
		link.push_unreliable(0, i)
	var rate := float(link.dropped) / float(n)
	check(rate > 0.011 and rate < 0.019, "coast drops about 1.5%% of unreliable packets (%.2f%%)" % (rate * 100.0))
	eq(link.pop_due(29999).size(), 0, "nothing arrives before latency - jitter (30 ms)")
	var out := link.pop_due(60000)
	eq(out.size(), n - link.dropped, "everything kept arrives by latency + jitter (60 ms)")
	var reordered := false
	for i in range(1, out.size()):
		if int(out[i]) < int(out[i - 1]):
			reordered = true
			break
	check(reordered, "jitter reorders unreliable packets")
	var rel := NetLink.new("coast", 9)
	for i in 500:
		rel.push_reliable(i * 1000, i)   # one per ms: far closer than the jitter
	var got := rel.pop_due(10_000_000)
	eq(got.size(), 500, "reliable items are never dropped")
	var ordered := true
	for i in got.size():
		if int(got[i]) != i:
			ordered = false
	check(ordered, "reliable items keep their order under jitter")


func _check_clock() -> void:
	var host := NetClock.new()
	host.start_host(1_000_000)
	near(host.host_time(3_000_000), 2.0, 1e-9, "the host clock counts from the session start")
	# Client: true offset 5 s. Two round trips with opposite asymmetry (30/60 ms and 60/30 ms legs).
	var c := NetClock.new()
	c.start_client(0)
	eq(c.host_time(1000), 0.0, "an unsynced client reads 0")
	var theta := 5.0
	c.add_sample(1_000_000, 1.0 + theta + 0.030, 1_090_000)   # out 30 ms, back 60 ms
	check(c.synced, "synced after the first pong")
	near(c.pending_correction_ms(), 0.0, 1e-6, "the first sample is adopted outright")
	near(c.raw_host_time(1_090_000) - (1.09 + theta), -0.015, 1e-6, "one asymmetric sample is 15 ms off")
	c.add_sample(2_000_000, 2.0 + theta + 0.060, 2_090_000)   # out 60 ms, back 30 ms
	near(c.pending_correction_ms(), 15.0, 1e-6, "intersecting the two samples' bounds finds the true offset (min-RTT alone would keep the 15 ms error)")
	# Slewing: at most 5% of elapsed time, never backwards.
	var prev := c.raw_host_time(2_090_000)
	var now := 2_090_000
	for i in 120:
		now += 16_667
		c.advance(now)
		var t := c.raw_host_time(now)
		check(t > prev, "the slewed clock moves forward")
		prev = t
	near(c.pending_correction_ms(), 0.0, 0.01, "the correction is done after 2 s (15 ms at 50 ms/s)")
	near(c.raw_host_time(now) - (float(now) / 1e6 + theta), 0.0, 1e-5, "the client now reads the host's clock")


# --- Two sessions in one process ------------------------------------------------------------------------

func _make(root_name: String, player: String) -> NetSession:
	var root := Node.new()
	root.name = root_name
	add_child(root)
	get_tree().set_multiplayer(SceneMultiplayer.new(), root.get_path())
	var s := NetSession.new()
	s.name = "Session"   # the same relative path under every root, so RPCs route
	s.telemetry_enabled = false
	s.player_name = player
	root.add_child(s)
	return s


func _check_sessions() -> void:
	var host := _make("HostRoot", "Hana")
	var a := _make("ClientA", "Abe")
	var joined: Array[int] = []
	var left: Array[int] = []
	host.peer_joined.connect(func(p: int) -> void: joined.append(p))
	host.peer_left.connect(func(p: int) -> void: left.append(p))
	var started: Array[bool] = []
	a.session_started.connect(func(as_host: bool) -> void: started.append(as_host))

	check(host.host_enet(PORT), "hosts on %d" % PORT)
	check(host.online() and host.hosting and host.is_host(), "the host is online at once")
	eq(host.local_id(), 1, "the host is peer 1")
	eq(host.roster.size(), 1, "the host is in its own roster")
	check(not host.host_enet(PORT + 1), "a second host() while online is refused")
	check(a.join_enet("127.0.0.1", PORT), "the client starts joining")
	check(a.busy() and not a.online(), "joining is not yet online")
	if not check(await _until(func() -> bool: return a.online() and host.roster.size() == 2, 5.0), "hello, welcome"):
		return
	eq(started, [false] as Array[bool], "session_started(false) on the client")
	check(a.is_client() and not a.is_host(), "the client is a client")
	check(a.local_id() > 1, "the client's id is above 1 (%d)" % a.local_id())
	eq(joined, [a.local_id()] as Array[int], "peer_joined once, with the client's id")
	eq(a.host_name(), "Hana", "the client knows the host's name")
	eq(_sig(a), _sig(host), "both ends list the same roster")
	eq(_sig(host), "1:1:Hana:wick;2:%d:Abe:wick" % a.local_id(), "seats, peers, names and characters")
	eq(int(a.local_entry()["seat"]), 2, "the joiner takes seat 2")
	check(await _until(func() -> bool: return a.clock.synced and a.clock.samples >= 5, 3.0), "the client's clock syncs")
	check(a.host_time() > 0.0 and absf(a.host_time() - host.host_time()) < 0.02, "both ends read about the same host_time (%.4f vs %.4f)" % [a.host_time(), host.host_time()])

	# Events in both directions.
	var at_host: Array = []
	var at_client: Array = []
	host.event_received.connect(func(from: int, kind: String, data: Dictionary, _s: float) -> void: at_host.append([from, kind, data]))
	a.event_received.connect(func(from: int, kind: String, data: Dictionary, _s: float) -> void: at_client.append([from, kind, data]))
	a.send_event(0, "t.hi", {"n": 1})
	host.send_event(0, "t.hey", {"n": 2})
	check(await _until(func() -> bool: return at_host.size() == 1 and at_client.size() == 1, 3.0), "events cross both ways")
	if at_host.size() == 1 and at_client.size() == 1:
		eq(at_host[0], [a.local_id(), "t.hi", {"n": 1}], "the host got the client's event")
		eq(at_client[0], [1, "t.hey", {"n": 2}], "the client got the host's event")

	# A different build is refused with a reason, and nothing changes for the crew.
	var b := _make("ClientB", "Bo")
	b.build = "some-other-build"
	b.join_enet("127.0.0.1", PORT)
	check(await _until(func() -> bool: return b.state == NetSession.State.OFFLINE, 5.0), "the other build's join ends")
	check(b.last_reason.begins_with(NetSession.DIFFERENT_BUILD), "refused: %s" % b.last_reason)
	eq(host.roster.size(), 2, "the crew is unchanged")
	eq(host.refusals.size(), 1, "the host recorded the refusal")

	# A client leaves.
	var a_id := a.local_id()
	a.leave()
	eq(a.last_reason, NetSession.YOU_LEFT, "leaving: 'You left the crew'")
	eq(a.local_id(), 0, "local_id() is 0 again")
	check(a.roster.is_empty(), "the leaver's roster is cleared")
	check(await _until(func() -> bool: return host.roster.size() == 1, 5.0), "the host drops the leaver")
	eq(left, [a_id] as Array[int], "peer_left fired for it")

	# The host goes silent (all the client's inbound packets lost): the client gives up after HOST_SILENCE.
	a.join_enet("127.0.0.1", PORT)
	check(await _until(func() -> bool: return a.online(), 5.0), "the client joins again")
	a.wire.link.loss = 1.0
	var t_silent := Time.get_ticks_msec()
	check(await _until(func() -> bool: return not a.online(), NetSession.HOST_SILENCE + 3.0), "a silent host is noticed")
	eq(a.last_reason, NetSession.HOST_LEFT, "silence reads as 'The host clocked out'")
	check(Time.get_ticks_msec() - t_silent >= int(NetSession.HOST_SILENCE * 1000.0) - 100, "only after HOST_SILENCE")
	a.wire.link.configure("off")
	check(await _until(func() -> bool: return host.roster.size() == 1, 5.0), "the host drops the client that gave up")

	# The host leaves: its goodbye ends the client's session at once.
	a.join_enet("127.0.0.1", PORT)
	check(await _until(func() -> bool: return a.online(), 5.0), "the client joins a third time")
	var ended: Array[String] = []
	a.session_ended.connect(func(r: String) -> void: ended.append(r))
	host.leave()
	eq(host.last_reason, NetSession.CREW_CLOSED, "the host's own reason")
	check(not host.online() and host.local_id() == 0, "the host is offline")
	check(await _until(func() -> bool: return not ended.is_empty(), 2.0), "the client hears the host leave within 2 s")
	eq(ended, [NetSession.HOST_LEFT] as Array[String], "'The host clocked out'")


static func _sig(s: NetSession) -> String:
	var parts: PackedStringArray = []
	for e: Dictionary in s.crew():
		parts.append("%d:%d:%s:%s" % [int(e["seat"]), int(e["peer"]), str(e["name"]), str(e["character"])])
	return ";".join(parts)

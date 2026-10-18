extends NetTest
## M0b, the wire under the `coast` link simulator, in BOTH directions (each process simulates its own inbound
## side, so host -> client and client -> host are both lossy and late):
## - reliable events: all EVENTS arrive, in order, exactly once; one-way delay about the link's 45 ms (plus
##   up to a frame of polling at each end);
## - unreliable sequenced packets: about the link's 1.5% loss, reordering under jitter is detected and the
##   stale packet DROPPED (an accepted packet is never older than one already accepted), and the u16
##   sequence number wraps (it starts at 65400).

const PEERS := 2
const LINKS := ["coast"]
const EVENTS := 300
const PACKETS := 3000
const BURST := 12             ## packets per frame: far closer together than the jitter, so they reorder
const FIRST_SEQ := 65400

var ev_got: Array[int] = []
var ev_delays: Array[float] = []
var pk_accepted := 0
var pk_last_i := -1
var pk_backwards := 0
var pk_high_seq := false
var pk_wrapped := false


func run_host() -> void:
	_listen()
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 15.0), "the client joins"):
		return
	var client := int(Session.crew()[1]["peer"])
	if not check(await wait_reports("ready", 1, 15.0), "the client's clock is synced"):
		return
	await _send_all(client)
	check(await wait_reports("result", 1, 30.0), "the client reports what it received")
	check(await until(func() -> bool: return ev_got.size() >= EVENTS, 10.0), "every client event reached the host (%d)" % ev_got.size())
	await sleep(1.0)   # the last packets' link delay
	var mine := _result()
	print("[NetTest] host received: ", mine)
	var theirs: Dictionary = reported(client, "result")
	print("[NetTest] client received: ", theirs)
	for side: Array in [["client -> host", mine], ["host -> client", theirs]]:
		_judge(str(side[0]), side[1] as Dictionary)
	check(Session.wire.link.preset == "coast", "the host ran the coast link")
	check(await wait_done(1), "the client is done")
	Session.leave()


func run_client() -> void:
	_listen()
	if not check(await connect_client() == "", "joined"):
		return
	check(await until(func() -> bool: return Session.clock.samples >= 8, 10.0), "the clock has samples")
	await sleep(0.5)
	report("ready", true)
	await _send_all(1)
	check(await until(func() -> bool: return ev_got.size() >= EVENTS, 15.0), "every host event reached the client (%d)" % ev_got.size())
	await sleep(1.0)
	report("result", _result())


func _listen() -> void:
	Session.event_received.connect(func(_from: int, kind: String, data: Dictionary, stamp: float) -> void:
		if kind == "t.ev":
			ev_got.append(int(data["i"]))
			ev_delays.append((Session.host_time() - stamp) * 1000.0))
	Session.packet_received.connect(func(_from: int, type: int, seq: int, _stamp_ms: int, payload: PackedByteArray) -> void:
		if type != NetWire.T_TEST:
			return
		var i := payload.decode_u32(0)
		if i <= pk_last_i:
			pk_backwards += 1
		pk_last_i = i
		pk_accepted += 1
		if seq > 65000:
			pk_high_seq = true
		elif pk_high_seq and seq < 1000:
			pk_wrapped = true)


func _send_all(to: int) -> void:
	Session.wire.set_next_seq(to, NetWire.T_TEST, FIRST_SEQ)
	var i := 0
	var p := 0
	while i < EVENTS or p < PACKETS:
		for k in 2:
			if i < EVENTS:
				Session.send_event(to, "t.ev", {"i": i})
				i += 1
		for k in BURST:
			if p < PACKETS:
				var b := PackedByteArray()
				b.resize(4)
				b.encode_u32(0, p)
				Session.send_packet(to, NetWire.T_TEST, b)
				p += 1
		await get_tree().process_frame


func _result() -> Dictionary:
	var in_order := ev_got.size() == EVENTS
	for k in ev_got.size():
		if ev_got[k] != k:
			in_order = false
			break
	var mean := 0.0
	for d in ev_delays:
		mean += d
	mean /= maxf(ev_delays.size(), 1.0)
	var ts: Array = Session.wire.type_stats.get(NetWire.T_TEST, [0, 0, 0])
	return {"events": ev_got.size(), "in_order": in_order, "delay_ms": mean,
		"accepted": pk_accepted, "stale": int(ts[1]), "backwards": pk_backwards, "wrapped": pk_wrapped,
		"link_dropped": Session.wire.link.dropped}


func _judge(dir: String, r: Dictionary) -> void:
	eq(int(r["events"]), EVENTS, "%s: every reliable event arrives" % dir)
	check(bool(r["in_order"]), "%s: reliable events arrive in order, once each" % dir)
	var delay := float(r["delay_ms"])
	check(delay > 38.0 and delay < 90.0, "%s: one-way event delay is about the link's 45 ms (%.1f ms)" % [dir, delay])
	var accepted := int(r["accepted"])
	var stale := int(r["stale"])
	var lost := PACKETS - accepted - stale
	var loss := float(lost) / float(PACKETS)
	check(loss > 0.005 and loss < 0.03, "%s: about 1.5%% of packets are lost (%.2f%%: %d accepted, %d stale, %d lost)" % [dir, loss * 100.0, accepted, stale, lost])
	check(stale > 0, "%s: jitter reorders packets and the late ones are dropped (%d stale)" % [dir, stale])
	eq(int(r["backwards"]), 0, "%s: no accepted packet is older than one accepted before it" % dir)
	check(bool(r["wrapped"]), "%s: the u16 sequence number wraps and packets keep coming" % dir)
	check(int(r["link_dropped"]) >= lost, "%s: the receiver's link dropped at least the lost packets (%d >= %d)" % [dir, int(r["link_dropped"]), lost])

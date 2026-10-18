extends NetTest
## M0b, the session clock and telemetry (networking-build-plan.md M0b "done when"), host + 2 clients, run
## under `off` and `coast`:
## - from 3 s after joining, each client's host_time() is within 10 ms (off) / 20 ms (coast) of the host's
##   real clock. (The plan said 5 ms with no link; polling once a frame on both sides makes the frame phase
##   unobservable, so the floor is half a frame, 8.3 ms at 60 fps: see NetClock.) All processes share this machine's wall clock, so the truth is known: the host sends its
##   unix time at host_time 0 in the welcome (Session.host_unix_epoch);
## - the slewed clock never runs backwards (checked on the raw value, before the never-backwards guard);
## - telemetry CSVs appear for the host and both clients; the host's file holds the clients' rows (under
##   `from`), and their RTT matches the link: about 90 ms of simulated round trip under coast (plus a frame
##   of polling at each hop), a few ms with no link.

const PEERS := 3
const SETTLE := 3.0     ## seconds after joining before the clock is judged
const MEASURE := 1.5    ## seconds of measuring after that


func run_host() -> void:
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 15.0), "both clients join"):
		return
	var limit := 10.0 if link == "off" else 20.0
	if not check(await wait_reports("clock", 2, 15.0), "both clients report their clock"):
		return
	for p in peers_with("clock"):
		var r: Dictionary = reported(p, "clock")
		print("[NetTest] peer %d clock: %s" % [p, str(r)])
		check(float(r["max_err_ms"]) < limit, "peer %d: clock error %.2f ms < %.0f ms (%s)" % [p, float(r["max_err_ms"]), limit, link])
		eq(float(r["backwards_ms"]), 0.0, "peer %d: the clock never ran backwards" % p)
		check(int(r["samples"]) >= 5, "peer %d: the clock kept pinging (%d samples)" % [p, int(r["samples"])])
		check(bool(r["telemetry"]), "peer %d: wrote its own telemetry CSV" % p)

	# The host's CSV: its own rows, plus every client's rows filed under `from`.
	var tel := Session.telemetry
	if not check(tel != null and tel.is_open(), "the host has a telemetry file"):
		return
	check(await until(func() -> bool: return tel.peer_rows >= 4 and tel.rows_written >= 2, 6.0), "the host filed client rows (%d) and its own (%d)" % [tel.peer_rows, tel.rows_written])
	var rows := _read_csv(tel.path)
	var header: PackedStringArray = rows[0] if not rows.is_empty() else PackedStringArray()
	eq(Array(header), Array(NetTelemetry.COLUMNS), "the CSV header is the column list")
	var col_from := NetTelemetry.COLUMNS.find("from")
	var col_role := NetTelemetry.COLUMNS.find("role")
	var col_rtt := NetTelemetry.COLUMNS.find("rtt_ms")
	var col_min := NetTelemetry.COLUMNS.find("rtt_min_ms")
	var rtts := {}   # from -> [[rtt, rtt_min], ...]
	for k in range(1, rows.size()):
		var row: PackedStringArray = rows[k]
		if row.size() != NetTelemetry.COLUMNS.size():
			_fail("a CSV row has %d columns" % row.size())
			continue
		if row[col_role] == "client" and float(row[col_rtt]) > 0.0:
			if not rtts.has(row[col_from]):
				rtts[row[col_from]] = []
			(rtts[row[col_from]] as Array).append([float(row[col_rtt]), float(row[col_min])])
	eq(rtts.size(), 2, "both clients' rows are in the host's file (from = %s)" % str(rtts.keys()))
	for who: String in rtts:
		var list: Array = rtts[who]
		var rtt := _median(list.map(func(r: Array) -> float: return float(r[0])))
		var rtt_min := _median(list.map(func(r: Array) -> float: return float(r[1])))
		print("[NetTest] client %s RTT median %.1f ms, window minimum %.1f ms, over %d rows" % [who, rtt, rtt_min, list.size()])
		if link == "coast":
			# 90 ms of link plus a frame of polling per leg, in whole frames: 100 / 117 / 133 / 150 ms.
			check(rtt_min >= 60.0 and rtt_min < 125.0, "client %s: minimum RTT between the link floor (2 x 30 ms) and 125 ms under coast (%.1f ms)" % [who, rtt_min])
			check(rtt > 85.0 and rtt < 170.0, "client %s: RTT about 90 ms plus jitter under coast (%.1f ms)" % [who, rtt])
		else:
			check(rtt < 40.0, "client %s: RTT is small with no link (%.1f ms)" % [who, rtt])
	check(await wait_done(2), "both clients are done")
	Session.leave()


func run_client() -> void:
	if not check(await connect_client() == "", "joined"):
		return
	var joined := wall()
	var prev_raw := -1.0
	var backwards := 0.0
	var max_err := 0.0
	var n := 0
	while wall() - joined < SETTLE + MEASURE:
		await get_tree().process_frame
		if not Session.clock.synced:
			continue
		var now := Time.get_ticks_usec()
		var raw := Session.clock.raw_host_time(now)
		if prev_raw >= 0.0 and raw < prev_raw:
			backwards = maxf(backwards, (prev_raw - raw) * 1000.0)
		prev_raw = raw
		if wall() - joined >= SETTLE:
			var truth := Time.get_unix_time_from_system() - Session.host_unix_epoch
			max_err = maxf(max_err, absf(Session.host_time() - truth) * 1000.0)
			n += 1
	check(n > 30, "measured the clock every frame (%d)" % n)
	var tel := Session.telemetry
	report("clock", {"max_err_ms": max_err, "backwards_ms": backwards, "samples": Session.clock.samples,
		"rtt_min_ms": Session.clock.rtt_min_ms, "jitter_ms": Session.clock.jitter_ms,
		"telemetry": tel != null and FileAccess.file_exists(tel.path) and tel.rows_written >= 2})


static func _median(values: Array) -> float:
	values.sort()
	return float(values[int(values.size() / 2.0)]) if not values.is_empty() else 0.0


func _read_csv(path: String) -> Array:
	var out := []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() != "":
			out.append(line.strip_edges().split(","))
	return out

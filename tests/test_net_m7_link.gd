extends NetGameTest
## M7, the in-game link simulator over ENet (three processes, the real transport, no game scene): the host's choice is the
## crew's link.
## - the crew opens on a clean line; the host picks "coast" (Settings > Diagnostics does this through Session.set_link): c1 is
##   told at once (`sys.link`) and simulates it on what IT receives, so its round trips grow to the preset's ~90 ms plus
##   polling; the host simulates it on its own side too, and its telemetry's `link` column says so;
## - a player who joins afterwards (c2) gets the crew's link in the welcome;
## - a client can't set the crew's link; an unknown preset is refused;
## - back to "off": everyone's round trip falls back to the clean line's.

const PEERS := 3
const LINKS := ["off"]


func run_host() -> void:
	clear_flag("c2_join")
	if not check(await until(func() -> bool: return Session.roster.size() == 2, 20.0), "c1 joins"):
		return
	var c1 := _peer_named("c1")
	eq(Session.link_preset, "off", "the crew opens on a clean line (the test's link)")
	check(not Session.set_link("tornado"), "an unknown preset is refused")
	var changed: Array[String] = []
	Session.link_changed.connect(func(p: String) -> void: changed.append(p))
	check(Session.set_link("coast"), "the host picks coast")
	eq(Session.wire.link.preset, "coast", "the host simulates it on what it receives")
	eq(changed, ["coast"] as Array[String], "link_changed fired")
	command(c1, "measure", {"want": "coast"})
	check(await wait_reports("coast", 1, 20.0), "c1 reports under coast")
	var r: Dictionary = reported(c1, "coast")
	eq(str(r["link"]), "coast", "c1 was told the crew's link")
	eq(str(r["wire"]), "coast", "c1 simulates it on what it receives")
	check(float(r["rtt"]) > 80.0, "c1's round trips grew to the coast link's (%.0f ms)" % float(r["rtt"]))
	check(not bool(r["could_set"]), "a client can't set the crew's link")
	check(_telemetry_link() == "coast", "the host's telemetry says the link is coast (%s)" % _telemetry_link())

	# A late joiner gets it in the welcome.
	raise_flag("c2_join")
	if not check(await until(func() -> bool: return Session.roster.size() == 3, 20.0), "c2 joins"):
		return
	var c2 := _peer_named("c2")
	command(c2, "measure", {"want": "coast"})
	check(await wait_reports("coast", 2, 20.0), "c2 reports")
	var r2: Dictionary = reported(c2, "coast")
	eq(str(r2["link"]), "coast", "a player joining later is on the crew's link from the welcome")
	check(float(r2["rtt"]) > 80.0, "... and its round trips show it (%.0f ms)" % float(r2["rtt"]))

	# Back to a clean line.
	check(Session.set_link("off"), "the host picks off")
	for p in [c1, c2]:
		command(p, "measure", {"want": "off"})
	check(await wait_reports("off", 2, 20.0), "both report under off")
	for p in [c1, c2]:
		var ro: Dictionary = reported(p, "off")
		eq(str(ro["wire"]), "off", "peer %d is back on a clean line" % p)
		check(float(ro["rtt"]) < 60.0, "peer %d's round trips fell back (%.0f ms)" % [p, float(ro["rtt"])])
	eq(changed, ["coast", "off"] as Array[String], "link_changed fired again")
	for p in [c1, c2]:
		command(p, "end")
	check(await wait_done(2, 20.0), "both clients are done")


func run_client() -> void:
	if index == 2:
		var since := Time.get_unix_time_from_system() - 1.0
		if not check(await wait_flag("c2_join", since, 40.0), "the host lets c2 join"):
			return
	if not check(await connect_client() == "", "joined"):
		return
	while true:
		var cmd := await wait_command(40.0)
		if str(cmd.get("cmd", "")) != "measure":
			return
		var want := str(cmd["want"])
		check(await until(func() -> bool: return Session.link_preset == want, 5.0), "told the crew's link is %s" % want)
		await sleep(2.5)   # (five pings under the new link)
		var could := Session.set_link("rough")
		report(want, {"link": Session.link_preset, "wire": Session.wire.link.preset, "rtt": Session.clock.rtt_ms, "could_set": could})


func _peer_named(n: String) -> int:
	for p: int in Session.roster:
		if str(Session.roster[p]["name"]) == n:
			return p
	return 0


## The `link` column of the newest row in the host's own telemetry file.
func _telemetry_link() -> String:
	var tel := Session.telemetry
	if tel == null:
		return ""
	var f := FileAccess.open(tel.path, FileAccess.READ)
	if f == null:
		return ""
	var header := f.get_csv_line()
	var col := header.find("link")
	var last := ""
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > col and col >= 0 and line[col] != "" and line[1] == "host":
			last = line[col]
	return last

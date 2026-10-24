extends NetGameTest
## M7, voice and passive data per player (three processes, `off` and `coast`):
## - VOICE DEBUG PER PLAYER: each machine's debug panel is its own recognizer. c1 speaks (types) a cast: c1's panel counts
##   it; the host's and c2's panels count nothing, although the cast lands on all three; every panel says whose mic it is.
## - THE CASTS SHEET: c1's two casts are rows in the HOST's casts sheet, sent by c1 (the transport's peer id): the voiced one
##   with its onset and end on the shared clock and its recognition latency (onset -> cast, end -> cast), the typed one
##   with none; and each cast was APPLIED exactly once on each of the three machines (their rows reach the host too).
## - THE VOICE LOG: c1's voice_log.csv rows say it is a client in seat 2 and when on the shared clock.
## - HITS PER PLAYER PER MINUTE: the host's hero and c1's hero are hit by a monster (each on its own machine, the victim
##   decides); after a window the host's hits sheet holds a row per player: the host's seat, c1's (filed from c1) and c2's
##   (no hits, but minutes on the floor), each with the hits, the monster's kind and hits per minute; the host's session
##   totals have all three.
## - PUPPET CORRECTIONS: the 1 Hz sheet's snap_m is measured on every machine on the floor (filed on the host) and small.

const PEERS := 3
const SEED := 13
const WINDOW := 1.5            ## the hits sheet's window here (a minute in play)
const RECOG_MS := 212.0
const SPEECH_MS := 655.0


func run_host() -> void:
	Session.hits_window = WINDOW
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	_freeze_world()
	check(await wait_reports("ready", 2, 30.0), "both clients are on the floor")
	var c1 := _peer_named("c1")
	var c2 := _peer_named("c2")

	# 1. c1 casts twice: a voiced heal (the recognizer's detail noted, as the game does) and a typed corn.
	command(c1, "casts", {"far": _far_point()})
	check(await wait_reports("casts", 1, 20.0), "c1 cast")
	var rc: Dictionary = reported(c1, "casts")
	check(bool(rc["heal_ok"]) and bool(rc["corn_ok"]), "both casts went out (heal %s, corn %s)" % [rc["heal_ok"], rc["corn_ok"]])
	eq(int(rc["panel_casts"]), 1, "c1's panel counted its own typed cast (the voiced one stood in for the recognizer)")
	check(str(rc["owner"]).contains("c1") and str(rc["owner"]).contains("seat 2"), "c1's panel says it is c1's mic, seat 2 (%s)" % rc["owner"])
	var log_rows: Array = rc["voice_log"]
	check(not log_rows.is_empty(), "c1's voice log has the typed cast")
	for row: Dictionary in log_rows:
		eq([str(row["net"]), str(row["seat"])], ["client", "2"], "c1's voice log rows say client, seat 2")
		check(str(row["host_time"]).is_valid_float() and float(row["host_time"]) > 0.0, "... and when on the shared clock (%s)" % row["host_time"])

	await sleep(NetCasts.LEAD + 0.6)
	eq(_panel_casts(game), 0, "the host's panel counted none of c1's casts")
	check(_panel_owner(game).contains("host") and _panel_owner(game).contains("seat 1"), "the host's panel says it is the host's mic (%s)" % _panel_owner(game))
	command(c2, "panel")
	check(await wait_reports("panel", 1, 20.0), "c2 reports its panel")
	eq(int(reported(c2, "panel")["casts"]), 0, "c2's panel counted none of c1's casts")
	check(str(reported(c2, "panel")["owner"]).contains("c2"), "c2's panel says it is c2's mic")

	# 2. The casts sheet on the host.
	var cols := NetTelemetry.CAST_COLUMNS
	var rows: Array = []
	var applied_ok := await until(func() -> bool:
		rows = _sheet_rows(Session.telemetry.casts.path)
		return rows.filter(func(r: Array) -> bool: return r[cols.find("kind")] == "applied").size() >= 6, 8.0)
	check(applied_ok, "six applied rows reached the host's casts sheet (two casts on three machines)")
	rows = _sheet_rows(Session.telemetry.casts.path)   # (a lambda assigns its own copy of `rows`)
	var sent := rows.filter(func(r: Array) -> bool: return r[cols.find("kind")] == "sent")
	eq(sent.size(), 2, "two sent rows")
	var by_spell := {}
	for r: Array in sent:
		by_spell[r[cols.find("spell")]] = r
		eq(int(r[cols.find("from")]), c1, "the cast was sent by c1 (filed under its peer id)")
		eq(r[cols.find("role")], "client", "... a client")
		eq(r[cols.find("seat")], "2", "... in seat 2")
	if by_spell.has("heal"):
		var h: Array = by_spell["heal"]
		eq(h[cols.find("source")], "voice", "the heal was spoken")
		eq([h[cols.find("recog_ms")], h[cols.find("speech_ms")]], ["212", "655"], "its recognition latency and onset-to-cast time")
		var t := float(h[cols.find("t")])
		near(float(h[cols.find("voice_end")]), t - RECOG_MS / 1000.0, 0.05, "the voice ended %d ms before the cast, on the shared clock" % int(RECOG_MS))
		near(float(h[cols.find("voice_start")]), t - SPEECH_MS / 1000.0, 0.05, "the voice began %d ms before it (the onset)" % int(SPEECH_MS))
		near(float(h[cols.find("at")]), t + NetCasts.LEAD, 0.05, "it lands LEAD after the cast")
	if by_spell.has("corn"):
		var c: Array = by_spell["corn"]
		eq(c[cols.find("source")], "typed", "the corn was typed")
		eq([c[cols.find("recog_ms")], c[cols.find("voice_start")]], ["", ""], "a typed cast has no voice timing")
	for spell: String in by_spell:
		var cid: String = (by_spell[spell] as Array)[cols.find("cast")]
		var on := rows.filter(func(r: Array) -> bool: return r[cols.find("kind")] == "applied" and r[cols.find("cast")] == cid).map(
			func(r: Array) -> int: return int(r[cols.find("from")]))
		on.sort()
		var want := [1, c1, c2]
		want.sort()
		eq(on, want, "the %s (%s) was applied exactly once on each machine" % [spell, cid])
		for r: Array in rows.filter(func(r: Array) -> bool: return r[cols.find("kind")] == "applied" and r[cols.find("cast")] == cid):
			check(int(r[cols.find("late_ms")]) < 120, "%s applied %s ms late on peer %s" % [spell, r[cols.find("late_ms")], r[cols.find("from")]])

	# 3. Hits per player per minute.
	var m := _a_monster()
	if not check(m != null, "a monster to be hit by"):
		return
	command(c1, "hit", {"by": NetFloor.id_of(m)})
	my_hero().apply_damage(3.0, m)
	my_hero().apply_damage(3.0, m)
	check(await wait_reports("hit", 1, 20.0), "c1 was hit")
	var kind := str(m.kind)
	var hcols := NetTelemetry.HIT_COLUMNS
	var seats := {}
	var got := await until(func() -> bool:
		seats.clear()
		for r: Array in _sheet_rows(Session.telemetry.hits.path):
			var key := "%s:%s" % [r[hcols.find("from")], r[hcols.find("seat")]]
			var acc: Dictionary = seats.get(key, {"hits": 0, "floor_s": 0.0, "sources": "", "who": r[hcols.find("who")], "role": r[hcols.find("role")]})
			acc["hits"] = int(acc["hits"]) + int(r[hcols.find("hits")])
			acc["floor_s"] = float(acc["floor_s"]) + float(r[hcols.find("floor_s")])
			acc["sources"] = str(acc["sources"]) + ";" + str(r[hcols.find("sources")])
			acc["per_min"] = r[hcols.find("per_min")]
			seats[key] = acc
		return int((seats.get("1:1", {}) as Dictionary).get("hits", 0)) >= 2 and int((seats.get("%d:2" % c1, {}) as Dictionary).get("hits", 0)) >= 1 \
			and seats.has("%d:3" % c2), WINDOW * 4.0 + 4.0)
	check(got, "the host's hits sheet has the host's, c1's and c2's rows (%s)" % str(seats))
	if got:
		var hs: Dictionary = seats["1:1"]
		check(int(hs["hits"]) >= 2 and str(hs["sources"]).contains(kind), "the host's seat: 2 hits by the %s (%s)" % [kind, hs["sources"]])
		eq([hs["role"], hs["who"]], ["host", "player"], "... a player on the host")
		var cs: Dictionary = seats["%d:2" % c1]
		check(int(cs["hits"]) >= 1 and str(cs["sources"]).contains(kind), "c1's seat: hit by the %s, decided on c1 and filed from c1 (%s)" % [kind, cs["sources"]])
		eq([cs["role"], cs["who"]], ["client", "player"], "... a player on a client")
		var zs: Dictionary = seats["%d:3" % c2]
		check(float(zs["floor_s"]) > 0.5, "c2's seat: time on the floor counted with no hits (%.1f s)" % float(zs["floor_s"]))
		check(float(str(cs["per_min"])) >= 0.0, "hits per minute are computed")
	print("[M7] hits sheet: %s" % str(seats))

	# 4. The 1 Hz sheet's puppet corrections on a floor: every machine shows puppets (the host: c1's and c2's heroes; a
	# client: the other heroes and the monsters), and on this link they stay on course.
	var cols1 := NetTelemetry.COLUMNS
	var snaps := {}   # from -> [m, ...]
	await until(func() -> bool:
		snaps.clear()
		for r: Array in _sheet_rows(Session.telemetry.path):
			if r.size() == cols1.size() and str(r[cols1.find("snap_m")]) != "":
				var who := str(r[cols1.find("from")])
				if not snaps.has(who):
					snaps[who] = []
				(snaps[who] as Array).append(float(str(r[cols1.find("snap_m")])))
		return [1, c1, c2].all(func(p: int) -> bool: return (snaps.get(str(p), []) as Array).size() >= 3), 6.0)
	for p in [1, c1, c2]:
		var list: Array = snaps.get(str(p), [])
		if check(list.size() >= 2, "peer %d's rows measure puppet corrections on the floor (%d rows)" % [p, list.size()]):
			list.sort()
			var med: float = list[int(list.size() / 2.0)]
			check(med < 0.5, "peer %d's puppets stay on course (median worst-of-second %.2f m, max %.2f m)" % [p, med, list[list.size() - 1]])
	for p in [c1, c2]:
		command(p, "end")
	check(await wait_done(2, 30.0), "both clients are done")


func run_client() -> void:
	Session.hits_window = WINDOW
	if not await enter_floor(SEED, 1):
		return
	if not await wait_sync():
		return
	report("ready", true)
	var running := true
	while running:
		var cmd := await wait_command(60.0)
		match str(cmd.get("cmd", "")):
			"casts":
				var voice := game.get("voice") as VoiceCaster
				var path := "user://net_tests/voice_log_%d_c%d.csv" % [port, index]
				DirAccess.remove_absolute(path)
				voice.voice_log.path = path
				voice.voice_log.enabled = true
				var c := game.get("controller") as PlayerController
				c.aim_override = cmd["far"]
				# A spoken heal: the recognizer's detail as VoiceCaster hands it to the game, then the game's own cast.
				var out0 := int(Session.casts.stats["casts_out"])
				Net.note_voice("heal", {"typed": false, "latency_ms": RECOG_MS, "speech_ms": SPEECH_MS, "accidental": false})
				game.call("_cast", "heal", 1.0, "cast heal")
				var heal_ok := await until(func() -> bool: return int(Session.casts.stats["casts_out"]) == out0 + 1, 1.0)
				my_hero()._ready_at.clear()
				# A typed corn, through the recognizer's typed path (the panel and the voice log see it).
				voice.inject_text("%s corn" % voice.get_trigger_word())
				var corn_ok := await until(func() -> bool: return int(Session.casts.stats["casts_out"]) == out0 + 2, 3.0)
				c.aim_override = Vector3.INF
				var rows := VoiceLog.read_all(path).filter(func(r: Dictionary) -> bool: return str(r["spell"]) == "corn")
				report("casts", {"heal_ok": heal_ok, "corn_ok": corn_ok, "panel_casts": _panel_casts(game),
					"owner": _panel_owner(game), "voice_log": rows})
				voice.voice_log.enabled = false
			"panel":
				report("panel", {"casts": _panel_casts(game), "owner": _panel_owner(game)})
			"hit":
				var m := NetRegistry.node(int(cmd["by"])) as Actor
				my_hero().apply_damage(2.0, m)
				report("hit", true)
			_:
				running = false


# --- Helpers ---------------------------------------------------------------------------------------------------

func _panel_casts(g: Node) -> int:
	var p: Variant = g.get("debug_panel")
	return (p as VoiceDebugPanel).cast_count() if p is VoiceDebugPanel else -1


func _panel_owner(g: Node) -> String:
	var p: Variant = g.get("debug_panel")
	return (p as VoiceDebugPanel).mic_owner_text() if p is VoiceDebugPanel else ""


func _peer_named(n: String) -> int:
	for p: int in Session.roster:
		if str(Session.roster[p]["name"]) == n:
			return p
	return 0


## Host: the floor's monsters and hellgates stand still (only the test hits anyone).
func _freeze_world() -> void:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster or n is Hellgate:
			n.set_physics_process(false)


func _a_monster() -> Monster:
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is Monster and not (n as Monster).dead:
			return n as Monster
	return null


## A spot 9 units from the host's hero (away from everyone): where the corn lands harmlessly.
func _far_point() -> Vector3:
	var base := my_hero().global_position
	return base + Vector3(9.0, 0.0, 0.0)


## A CSV's rows after the header.
static func _sheet_rows(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > 3:
			out.append(Array(line))
	return out

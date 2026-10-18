class_name NetJoin
extends Node
## Joining mid-contract (docs/design/networking-build-plan.md M6): child "Join" of the Session autoload. A player who says
## hello while the crew is on a job is admitted (NetSession) with `joining` true in the roster and takes one of the AI's seats
## on a running floor. Everything here is a reliable event, kinds "join.*"; the seat itself changes hands in SeatHandover.
##
## HOST
##   - a joiner waits (`join.wait {note, job, floor, license}`: what the crew is doing, for its "Clocking in..." form) until
##     the crew is on a running floor: CrewFlow FLOOR, the van arrival over (the hero sync is live), the job not over, no
##     exit taken. A joiner during a floor change therefore waits for the next floor to start; one on the invoice waits for
##     the next board (CrewFlow's crew.board makes it an ordinary member, and this forgets it).
##   - THE JOINER'S LICENSE (user, 2026-10-18): while the crew is on a job it can arrive on (`license` true: licenses being
##     signed, a floor loading or running), the joiner signs its own license checkout and says so (`join.signed {spells}`,
##     the same check as crew.signed). It is sent onto a floor only once it has signed. Nobody waits for it: the AI keeps
##     playing the seat until the joiner is built and ready, and the seat is handed over with the joiner's spells at fresh
##     charges (SpellComponents.START_CHARGES, as a license gives), not the AI's.
##   - then (signed, on a running floor) `join.go {ticket, job, floor, seat, seats, start_at, floor_start}`: the seat it takes (SeatHandover.choose_seat,
##     the plan's order, decided now: the roster seat follows) and the seat table the floor was built with at its barrier
##     (CrewFlow.floor_seats), so the joiner builds the SAME floor from the seed (the same checksum) with that seat as its own;
##   - the joiner reports `join.built {ticket, sums}`; a different checksum is a desync (sent out, as at a barrier); a match
##     raises built_ready(peer) and the host's game calls admit(peer, extra) at once: the late-join SNAPSHOT goes to the
##     joiner and SeatHandover.take hands the seat over (the AllyBrain stops this frame) and tells everyone else.
## THE SNAPSHOT (`join.snapshot`, one reliable event; measured in the build plan's "M6 as built")
##   the floor clock (start_at, floor_start); the seat table (owner and epoch per seat), each seat's kit and player name and
##   every other hero's state (position, facing, HP, downed, slots, charges, held slot); the seed-built ids that are GONE on
##   the host (`gone`: id -> "die" to show dead, "free" to remove); every runtime monster (a world.spawn replay); a full world
##   KEYFRAME (NetWorld.keyframe: every surviving monster, employee and hellgate); the employees' wait spots; the pickups on
##   the floor and the dents (NetObjects); the statuses (NetStatus); every Ledger line; the joiner's own `take` (seat,
##   character, epoch, the hero's state: SeatHandover.hero_state); plus what the game adds (`contract`: the objective
##   bookkeeping). Not in it (the plan): scheduled effects in flight and monsters' wind-ups (they last under 2 s), grime decals.
## JOINER
##   - shows "Clocking in..." (the game's ClockInSlip) from the first `join.wait`; with `license` the game opens the license
##     checkout in its place at once, and sign(spells) tells the host (Esc there leaves the crew, as on the form);
##   - on `join.go` the game builds the floor
##     behind its own barrier (every hero a puppet of the host's stream, its future one included), reports built, and
##     applies the snapshot when it comes: the floor clock (CrewFlow.join_floor), the game's part (snapshot_received), then
##     the world, the Ledger and finally its own seat (SeatHandover.take_local). The floor starts on the next frame.

## Joiner: the wait note, the go, or the arrival changed (the game redraws its "Clocking in..." form or builds).
signal changed()
## Host: a joiner built the floor with the right checksum; the game answers with admit(peer, {"contract": ...}).
signal built_ready(peer: int)
## Joiner: the host's snapshot arrived; the game applies its own parts (the contract, the heroes' kits) before the rest.
signal snapshot_received(data: Dictionary)

const WAIT := "wait"
const BUILD := "build"
const READY := "ready"

## Host: peer -> {state, ticket, note, license, spells (its signed license, [] until it signs), ...}.
var joiners: Dictionary = {}
## Host, tests: per admitted peer, what its snapshot held: {t, bytes, gone (ids), alive (ids), seat, take (state)}.
var admitted: Dictionary = {}

## Joiner: waiting to arrive (from the first join.wait until the snapshot is applied).
var waiting := false
var note := ""
var wait_job: Dictionary = {}
var wait_floor := 0
## The character of the AI whose seat this joiner will relieve ("" = not known yet), for its requisition form.
var wait_relieving := ""
## Joiner: the host says to sign a license now (the crew is on a job this joiner will arrive on).
var license := false
## Joiner: the spells this joiner signed for ([] until it signs; forgotten when the board comes).
var signed: Array[String] = []
## Joiner, tests: host_time when it signed.
var signed_at := 0.0
## Joiner: the host's join.go ({} until it comes).
var go: Dictionary = {}
var arrived := false
## Joiner, tests: host_time when it reported built / when it took the seat; what the snapshot did here.
var ready_at := 0.0
var taken_at := 0.0
var applied: Dictionary = {}

var _session: NetSession = null
var _ticket := 0
var _pending_sums: Dictionary = {}   ## joiner: built, waiting for the shared clock before saying so


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.event_received.connect(_on_event)
	_session.peer_joined.connect(_on_peer_joined)
	_session.peer_left.connect(func(peer: int) -> void: joiners.erase(peer))
	_session.session_started.connect(func(_as_host: bool) -> void: reset())
	_session.session_ended.connect(func(_reason: String) -> void: reset())
	if _session.flow != null:
		_session.flow.board_changed.connect(_on_board)


func reset() -> void:
	joiners = {}
	admitted = {}
	waiting = false
	note = ""
	wait_job = {}
	wait_floor = 0
	wait_relieving = ""
	license = false
	signed = []
	signed_at = 0.0
	go = {}
	arrived = false
	ready_at = 0.0
	taken_at = 0.0
	applied = {}
	_pending_sums = {}


func _hosting() -> bool:
	return _session != null and _session.hosting and _session.online()


func _now() -> float:
	return _session.host_time() if _session != null else 0.0


# --- Host ------------------------------------------------------------------------------------------------

func _on_peer_joined(peer: int) -> void:
	if not _hosting() or not CrewFlow.is_joining(_session.roster.get(peer, {}) as Dictionary):
		return
	joiners[peer] = {"state": WAIT, "ticket": 0, "note": "", "hello_t": _now(), "spells": []}
	_tell_wait(peer)


## The crew went back to the board (every member got crew.board, the joining flags are cleared): nobody is joining now.
## A joiner on this machine stops waiting.
func _on_board() -> void:
	joiners.clear()
	if waiting and not _hosting():
		waiting = false
		license = false
		signed = []   # (an ordinary member now: it signs the next job's license like everyone)
		go = {}
		changed.emit()


## Host: a running floor a joiner can arrive on right now.
func can_admit() -> bool:
	var flow := _session.flow
	return flow.phase == CrewFlow.FLOOR and not flow.job_ended and not flow.local_sums.is_empty() and not flow.floor_seats.is_empty() \
			and _session.snap != null and _session.snap.active and _session.objects != null and _session.objects.active \
			and not _session.objects.exit_taken()


## Host: the crew is on a job a joiner will arrive on, so the joiner signs its license now (licenses being signed, a floor
## loading or running). Not on the invoice, and not for a host on a job alone (they start together at the next board).
func license_open() -> bool:
	var flow := _session.flow
	return not flow.job_ended and flow.phase in [CrewFlow.LICENSE, CrewFlow.LOADING, CrewFlow.PENDING, CrewFlow.FLOOR]


## What a waiting joiner reads on its form (`has_signed`: it has signed its license).
func _wait_note(has_signed: bool) -> String:
	var flow := _session.flow
	if flow.job_ended:
		return "The crew is reading the invoice. You start with them on the next job."
	match flow.phase:
		CrewFlow.LICENSE:
			return "The crew is signing licenses. You arrive on floor 1."
		CrewFlow.LOADING, CrewFlow.PENDING:
			return "The crew is riding the elevator. You arrive on the next floor." if flow.floor_change else "The crew is heading in. You arrive on floor 1."
		CrewFlow.FLOOR:
			if not can_admit():
				return "The crew is stepping out of the van. Hold on."
			return "Building the floor..." if has_signed else "The crew is on floor %d." % flow.floor_n
	return "The host is on a job alone. You start together at the next board."


func _tell_wait(peer: int) -> void:
	var j: Dictionary = joiners[peer]
	var lic := license_open()
	var n := _wait_note(not (j["spells"] as Array).is_empty())
	if n == str(j["note"]) and lic == bool(j.get("license", false)):
		return
	j["note"] = n
	j["license"] = lic
	var seat := int((_session.roster.get(peer, {}) as Dictionary).get("seat", 0))
	var relieving := str(_session.seats.originals.get(seat, "")) if _session.seats != null else ""
	_session.send_event(peer, "join.wait", {"note": n, "job": _session.flow.job, "floor": _session.flow.floor_n, "license": lic,
		"relieving": relieving})


func _process(_delta: float) -> void:
	if not _pending_sums.is_empty() and _session != null and _session.is_client() and _session.clock.synced:
		var sums := _pending_sums
		_pending_sums = {}
		_send_built(sums)
	if not _hosting() or joiners.is_empty():
		return
	var ok := can_admit()
	for peer: int in joiners.keys():
		var j: Dictionary = joiners[peer]
		if not _session.roster.has(peer):
			joiners.erase(peer)
			continue
		if str(j["state"]) == WAIT:
			if ok and not (j["spells"] as Array).is_empty():
				_dispatch(peer)   # (signed: it arrives with its own license; until then the AI plays the seat)
			else:
				_tell_wait(peer)
		elif not ok:
			j["state"] = WAIT   # (a floor change, the end of the job: it waits for the next floor; a stale build is ignored)
			j["note"] = ""
			_tell_wait(peer)


## Host: send the joiner onto this floor: the seat it takes and the floor to build.
func _dispatch(peer: int) -> void:
	var e: Dictionary = _session.roster[peer]
	var free: Array = []
	for seat in range(1, NetSession.MAX_CREW + 1):
		var held := false
		for p: int in _session.roster:
			if p != peer and int((_session.roster[p] as Dictionary)["seat"]) == seat:
				held = true
		if not held and _session.seats.owner_of(seat) == 0:
			free.append(seat)
	var seat := _session.seats.choose_seat(str(e.get("character", NetSession.DEFAULT_CHARACTER)), free)
	if seat == 0:
		return
	if seat != int(e["seat"]):
		_session.set_members(peer, {"seat": seat})
	_ticket += 1
	var j: Dictionary = joiners[peer]
	j["state"] = BUILD
	j["ticket"] = _ticket
	j["note"] = ""
	j["go_t"] = _now()
	var flow := _session.flow
	_session.send_event(peer, "join.go", {"ticket": _ticket, "job": flow.job, "floor": flow.floor_n, "seat": seat, "seats": flow.floor_seats,
		"start_at": flow.start_at, "floor_start": flow.floor_start})
	print("[Net] %s clocks in on floor %d: seat %d (ticket %d)" % [str(e.get("name", peer)), flow.floor_n, seat, _ticket])


func _host_event(from: int, kind: String, data: Dictionary) -> void:
	if kind == "join.signed" and joiners.has(from):
		_host_signed(from, data)
		return
	if kind != "join.built" or not joiners.has(from):
		return
	var j: Dictionary = joiners[from]
	if str(j["state"]) != BUILD or int(data.get("ticket", -1)) != int(j["ticket"]):
		return   # (a build for a floor the crew has left)
	if not can_admit():
		j["state"] = WAIT
		j["note"] = ""
		_tell_wait(from)
		return
	var flow := _session.flow
	var sums := data.get("sums", {}) as Dictionary
	if str(sums.get("all", "")) != str(flow.local_sums.get("all", "")):
		var parts := NetFloor.differing_parts(flow.local_sums, sums)
		var who := str((_session.roster.get(from, {}) as Dictionary).get("name", from))
		print("[Net] DESYNC: %s (joining) built a different floor (differs: %s)" % [who, ", ".join(parts)])
		flow.desyncs.append({"peer": from, "name": who, "parts": parts})
		joiners.erase(from)
		_session.kick(from, NetSession.DESYNC)
		return
	j["state"] = READY
	j["built_t"] = _now()
	built_ready.emit(from)


## Host: a joiner signed its license while it waited (the same check as crew.signed: exactly PICK_COUNT available spells).
## Once is enough: a second signing is ignored. It is sent onto the next running floor with these (_process).
func _host_signed(from: int, data: Dictionary) -> void:
	var j: Dictionary = joiners[from]
	var who := str((_session.roster.get(from, {}) as Dictionary).get("name", from))
	if not (j["spells"] as Array).is_empty() or not license_open():
		return
	var spells: Array[String] = []
	for s: Variant in data.get("spells", []) as Array:
		if SpellBook.is_available(str(s)) and not spells.has(str(s)):
			spells.append(str(s))
	if spells.size() != SpellPicker.PICK_COUNT:
		push_warning("[Net] %s (joining) signed %d spells: ignored" % [who, spells.size()])
		return
	j["spells"] = spells
	j["signed_t"] = _now()
	print("[Net] %s (joining) signed a license: %s" % [who, ", ".join(spells)])


## The license a joiner signed, as a handed-over state's loadout: its spells at fresh charges (START_CHARGES each, what a
## license gives at a floor start), no cooldowns, the first slot held. Everything else in `state` (the AI's spot, facing,
## modifiers, fire, soak) is kept.
static func licensed_state(state: Dictionary, spells: Array) -> Dictionary:
	var out := state.duplicate(true)
	var ch := {}
	for s: Variant in spells:
		ch[str(s)] = SpellComponents.START_CHARGES
	out["sl"] = spells.duplicate()
	out["ch"] = ch
	out["cd"] = {}
	out["hs"] = 0
	return out


## Host: the joiner is ready on this floor. Send it the snapshot and hand it the seat (the game calls this from built_ready
## with what it keeps itself: `extra` = {"contract": ContractSession.mirror_state()}). False when it cannot happen now.
func admit(peer: int, extra: Dictionary = {}) -> bool:
	if not _hosting() or not joiners.has(peer) or str((joiners[peer] as Dictionary)["state"]) != READY or not can_admit():
		return false
	var e: Dictionary = _session.roster.get(peer, {})
	var seat := int(e.get("seat", 0))
	var hero := NetRegistry.hero(seat)
	if hero == null or _session.seats.owner_of(seat) != 0:
		return false
	var character := str(e.get("character", NetSession.DEFAULT_CHARACTER))
	var now := _now()
	var spells := ((joiners[peer] as Dictionary)["spells"] as Array).duplicate()
	# The AI's hero at this moment (before anything changes), with the joiner's own license on it.
	var state := licensed_state(SeatHandover.hero_state(hero), spells)
	var flow := _session.flow
	var kits := {}
	var heroes := {}
	for s in range(1, NetSession.MAX_CREW + 1):
		var h := NetRegistry.hero(s)
		if h == null:
			continue
		var owner := _session.seats.owner_of(s)
		kits[s] = [h.kit_id, str((_session.roster.get(owner, {}) as Dictionary).get("name", "")) if owner != 0 else ""]
		if s != seat:
			heroes[s] = [h.global_position, h.facing, h.hp, h.dead, Array(h.spell_slots), h._charges.duplicate(), h.held_slot]
	var gone := gone_ids()
	var jt: Dictionary = joiners[peer]
	# (M7: the join's timings, passively in the host's log: the license, the wait for a running floor, the joiner's build,
	# ready -> seated)
	var timings := {"sign_s": float(jt.get("signed_t", now)) - float(jt.get("hello_t", now)),
		"wait_s": float(jt.get("go_t", now)) - float(jt.get("hello_t", now)),
		"build_s": float(jt.get("built_t", now)) - float(jt.get("go_t", now)), "seat_ms": (now - float(jt.get("built_t", now))) * 1000.0}
	var waits := {}
	for id in NetRegistry.ids():
		var emp := NetRegistry.node(id) as Employee
		if emp != null and not emp.dead and emp.is_waiting():
			waits[id] = emp._wait_spot
	var d := {
		"ticket": int((joiners[peer] as Dictionary)["ticket"]), "at": now, "start_at": flow.start_at, "floor_start": flow.floor_start, "job": flow.job,
		"seats": _session.seats.table(), "kits": kits, "heroes": heroes, "gone": gone,
		"spawns": _session.world.runtime_spawns(), "world": _session.world.keyframe(now), "waits": waits,
		"objects": _session.objects.late_join_state(), "status": _session.status.late_join_state(),
		"ledger": {"lines": Ledger.lines.duplicate(true), "value": Ledger.contract_value, "floor": Ledger.floor_number},
		"take": {"seat": seat, "character": character, "epoch": _session.seats.epoch_of(seat) + 1, "state": state},
	}
	d.merge(extra)
	var size := var_to_bytes(d).size()
	_session.send_event(peer, "join.snapshot", d)
	admitted[peer] = {"t": now, "bytes": size, "gone": gone.keys(), "alive": living_ids(), "seat": seat, "take": state,
		"slots": (state["sl"] as Array).duplicate(), "charges": (state["ch"] as Dictionary).duplicate(),
		"ai_slots": Array(hero.spell_slots), "signed_t": float(jt.get("signed_t", 0.0)), "timings": timings}
	print("[Net] join timings for %s: signed its license after %.1f s, sent in after %.1f s, built the floor in %.1f s, seated %d ms after ready" % [
		str(e.get("name", peer)), float(timings["sign_s"]), float(timings["wait_s"]), float(timings["build_s"]), roundi(float(timings["seat_ms"]))])
	print("[Net] late-join snapshot to %s: %d bytes (%d gone, %d runtime monsters, %d Ledger lines)" % [
		str(e.get("name", peer)), size, gone.size(), (d["spawns"] as Array).size(), Ledger.lines.size()])
	joiners.erase(peer)
	_session.seats.take(seat, peer, character, state)
	_session.set_members(peer, {"joining": false, "signed": true, "ready": true, "spells": spells})
	return true


## Host: the seed-built ids that are gone on this floor: id -> "die" (show it dead or broken: a closed gate, a broken prop or
## crate, a dead employee) or "free" (remove it: a dead monster, an extracted employee, an opened mail box, a used pickup).
static func gone_ids() -> Dictionary:
	var out := {}
	for id in range(NetFloor.ID_BASE, NetRegistry.seed_top):
		var n := NetRegistry.node(id)
		if n == null:
			out[id] = "free"
		elif n is ComponentPickup:
			if (n as ComponentPickup)._used or (n as ComponentPickup).charges <= 0 or n.is_queued_for_deletion():
				out[id] = "free"
		elif n is Actor and (n as Actor).dead:
			out[id] = "free" if n is Monster or n is MailPackage else "die"
		elif n is Employee and (n as Employee).is_extracted():
			out[id] = "free"
	return out


## Every host-owned actor alive on this machine (ids from ID_BASE: monsters, gates, employees, props, crates, mail), ascending.
static func living_ids() -> Array[int]:
	var out: Array[int] = []
	for id in NetRegistry.ids():
		if id < NetFloor.ID_BASE:
			continue
		var a := NetRegistry.node(id) as Actor
		if a == null or a.dead or a.is_queued_for_deletion() or (a is Employee and (a as Employee).is_extracted()):
			continue
		out.append(id)
	return out


# --- Joiner ----------------------------------------------------------------------------------------------

## The joiner signed its license checkout (the game's SpellPicker): tell the host. It arrives in the seat with these.
func sign(spells: Array[String]) -> void:
	if _session == null or not _session.is_client() or not waiting or not signed.is_empty():
		return
	signed = spells.duplicate()
	signed_at = _now()
	_session.send_event(1, "join.signed", {"spells": signed})
	changed.emit()


## The joiner built the floor behind its barrier: tell the host (with the checksum). A joiner can be this quick: it says so
## only once the shared clock is synced (the floor clock it is about to join is on it).
func report_built(sums: Dictionary) -> void:
	if go.is_empty() or _session == null or not _session.is_client():
		return
	if not _session.clock.synced:
		_pending_sums = sums
		return
	_send_built(sums)


func _send_built(sums: Dictionary) -> void:
	if go.is_empty():
		return
	ready_at = _now()
	_session.send_event(1, "join.built", {"ticket": int(go.get("ticket", 0)), "sums": sums})


func _client_event(kind: String, data: Dictionary) -> void:
	match kind:
		"join.wait":
			_pending_sums = {}
			waiting = true
			arrived = false
			note = str(data.get("note", ""))
			wait_job = data.get("job", {}) as Dictionary
			wait_floor = int(data.get("floor", 0))
			license = bool(data.get("license", false))
			wait_relieving = str(data.get("relieving", ""))
			go = {}
			changed.emit()
		"join.go":
			_pending_sums = {}
			waiting = true
			arrived = false
			note = ""
			go = data.duplicate()
			wait_job = go.get("job", {}) as Dictionary
			wait_floor = int(go.get("floor", 0))
			changed.emit()
		"join.snapshot":
			if go.is_empty() or int(data.get("ticket", -1)) != int(go.get("ticket", 0)) or GameWorld.root == null:
				return
			_apply(data)


## The joiner: everything in the host's snapshot, in order: the floor clock first (every time in it is on that clock).
func _apply(d: Dictionary) -> void:
	_session.flow.join_floor(d.get("job", go.get("job", {})) as Dictionary, float(d.get("start_at", 0.0)), float(d.get("floor_start", 0.0)))
	_session.seats.apply_table(d.get("seats", {}) as Dictionary)
	snapshot_received.emit(d)   # (the game: the contract, the heroes' kits and names)
	var take := d.get("take", {}) as Dictionary
	var own := int(take.get("seat", 0))
	var removed: Array[int] = []
	Net.apply_begin()   # (the host's word on its own things and the other players' heroes)
	var heroes := d.get("heroes", {}) as Dictionary
	for k: Variant in heroes:
		var seat := int(k)
		var h := NetRegistry.hero(seat)
		if h == null or seat == own:
			continue
		var row := heroes[k] as Array
		var st := NetHeroState.new()
		st.seat = seat
		st.pos = row[0]
		var f: Vector3 = row[1]
		st.angle = atan2(f.z, f.x)
		st.hp = float(row[2])
		st.dead = bool(row[3])
		st.held_slot = int(row[6])
		NetCodec.write_hero(h, st)
		h.reset_physics_interpolation()
		var slots: Array[String] = []
		for s: Variant in row[4] as Array:
			slots.append(str(s))
		h.spell_slots = slots
		var ch := {}
		var src := row[5] as Dictionary
		for c: Variant in src:
			ch[str(c)] = int(src[c])
		h._charges = ch
		h._refresh_hold()
	var gone := d.get("gone", {}) as Dictionary
	for k: Variant in gone:
		var id := int(k)
		var n := NetRegistry.node(id)
		if n == null:
			continue
		removed.append(id)
		if str(gone[k]) == "die" and n is Actor:
			Net.remote_die(n as Actor)
			continue
		if n is Actor:
			(n as Actor).dead = true
			n.remove_from_group("actors")
			n.remove_from_group("monsters")
			n.remove_from_group("employees")
		n.queue_free()
		NetRegistry.unregister(id)
	# A runtime monster this machine heard spawn while it was building, but that is not in the host's list, died before the
	# snapshot (its death is on its way to a world this machine had not started showing).
	var listed := {}
	for e: Variant in d.get("spawns", []) as Array:
		listed[int((e as Array)[0])] = true
	for id in NetRegistry.ids():
		var m := NetRegistry.node(id) as Monster
		if id >= NetRegistry.RUNTIME_BASE and m != null and not listed.has(id):
			m.dead = true
			m.remove_from_group("actors")
			m.remove_from_group("monsters")
			m.queue_free()
			NetRegistry.unregister(id)
	_session.world.apply_spawns(d.get("spawns", []) as Array)
	var keys := _session.world.apply_keyframe(d.get("world", PackedByteArray()) as PackedByteArray, float(d.get("at", _now())))
	var waits := d.get("waits", {}) as Dictionary
	for k: Variant in waits:
		var emp := NetRegistry.node(int(k)) as Employee
		if emp != null:
			emp._wait_spot = waits[k]
	_session.objects.apply_late_join(d.get("objects", {}) as Dictionary)
	_session.status.apply_late_join(d.get("status", []) as Array)
	var ledger := d.get("ledger", {}) as Dictionary
	Ledger.mirror = true
	Ledger.mirror_all(ledger.get("lines", []) as Array, int(ledger.get("value", 0)), int(ledger.get("floor", 1)))
	Net.apply_end()
	_session.seats.take_local(take)
	taken_at = _now()
	removed.sort()
	applied = {"gone": removed, "keyframe": keys, "spawns": (d.get("spawns", []) as Array).size(), "bytes": var_to_bytes(d).size()}
	arrived = true
	waiting = false
	print("[Net] clocked in: seat %d, %d gone, %d keyframe entries, %.0f ms after reporting ready" % [own, removed.size(), keys, (taken_at - ready_at) * 1000.0])
	changed.emit()


func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if not kind.begins_with("join.") or _session == null:
		return
	if _session.hosting:
		_host_event(from, kind, data)
	elif from == 1:
		_client_event(kind, data)

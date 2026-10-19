class_name NetOrders
extends Node
## Voice orders online (docs/design/combat-proposals.md 1.0 and "As built"): child "Orders" of the Session autoload.
##
## An order ("Rebar go", "Hench attack", "everyone follow") is heard on the SPEAKER's machine (VoiceCaster.order_spoken),
## which resolves where it aims. The host runs the AI seats and the employees, so the order is a REQUEST to the host:
##   ord.req  client -> host   {w name key, o order, p the aim point}  (the speaker is the asker's seat)
##   ord.ok   host -> everyone {w, o, p, s speaker's seat, b [[id, bark]] the AI heroes that took it and what they say,
##                              m [seat] the human-played heroes it names (a marker on THAT player's screen), t taken, r refused}
## The host applies it once (VoiceOrders.apply: AllyBrain.give_order, Employee.order) and tells everyone; every machine shows
## its part (VoiceOrders.feedback): the AI heroes' barks and pose, the speaker's waypoint, a player's marker. Employees speak
## through their own bubble (Employee.say -> world.say), and what an order changes rides the usual streams (the AI hero's
## snapshot, the employee's state, leader and wait spot). Nothing here is gameplay state: a late joiner skips old barks and
## markers (cosmetic), and the orders themselves are the host's AI state (AllyBrain, PRIVATE) or the employee's keyframe.
## Solo (and a host alone) never comes here: VoiceOrders applies the order locally.

## Every machine, after an order is applied (host) or announced (client): the ord.ok payload. Tests.
signal shown(data: Dictionary)

var stats := {"sent": 0, "applied": 0, "shown": 0}
## Host: every order applied, {seat, w, o, took, refused, marks} (tests, logs).
var applied: Array = []

var _session: NetSession = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session = get_parent() as NetSession
	if _session != null:
		_session.event_received.connect(_on_event)


## The crew is on a running floor (ids assigned, the host's things are copies here).
func live() -> bool:
	return _session != null and _session.online() and _session.roster.size() > 1 and _session.objects != null \
			and _session.objects.active


## The speaker's machine: an order heard here. True when the net layer took it (a crewed, running floor): the host applies
## it now, a client asks the host. False offline / alone: the caller applies it locally.
func send(who: String, kind: String, speaker: Hero, point: Vector3) -> bool:
	if not live() or speaker == null:
		return false
	var d := {"w": who, "o": kind, "p": point, "s": NetFloor.id_of(speaker)}
	stats["sent"] = int(stats["sent"]) + 1
	if _session.hosting:
		_host_apply(d, 1)
	else:
		_session.send_event(1, "ord.req", d)
	return true


func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if not kind.begins_with("ord.") or _session == null:
		return
	if kind == "ord.req" and _session.hosting:
		_host_apply(data, from)
	elif kind == "ord.ok" and not _session.hosting and from == 1:
		_show(data)


## Host: apply an order from the player in `from`'s seat and tell everyone.
func _host_apply(d: Dictionary, from: int) -> void:
	if not live():
		return
	var seat := int(d.get("s", 0)) if from == 1 else (_session.seats.seat_of(from) if _session.seats != null else 0)
	var speaker := NetRegistry.hero(seat)
	if speaker == null:
		return
	var p: Vector3 = d.get("p", Vector3.INF)
	var r := VoiceOrders.apply(str(d.get("w", "")), str(d.get("o", "")), speaker, p)
	var barks: Array = []
	for e: Array in r["barks"]:
		barks.append([NetFloor.id_of(e[0]), e[1]])
	var marks: Array = []
	for h: Hero in r["marks"]:
		marks.append(NetFloor.id_of(h))
	var out := {"w": d.get("w", ""), "o": d.get("o", ""), "p": p, "s": seat, "b": barks, "m": marks,
		"t": int(r["took"]), "r": int(r["refused"])}
	stats["applied"] = int(stats["applied"]) + 1
	applied.append({"seat": seat, "w": out["w"], "o": out["o"], "took": out["t"], "refused": out["r"], "marks": marks})
	_session.send_event(0, "ord.ok", out)
	_show(out)


## Every machine: show an applied order (the barks and poses, the speaker's waypoint, this player's marker).
func _show(d: Dictionary) -> void:
	stats["shown"] = int(stats["shown"]) + 1
	var barks: Array = []
	for e: Variant in d.get("b", []) as Array:
		var row := e as Array
		var n := NetRegistry.node(int(row[0])) if row != null and row.size() >= 2 else null
		if n != null:
			barks.append([n, str(row[1])])
	var marks: Array = []
	for id: Variant in d.get("m", []) as Array:
		var h := NetRegistry.hero(int(id))
		if h != null:
			marks.append(h)
	var view := {"o": str(d.get("o", "")), "p": d.get("p", Vector3.INF), "by": NetRegistry.hero(int(d.get("s", 0))),
		"barks": barks, "marks": marks, "took": int(d.get("t", 0))}
	VoiceOrders.feedback(view, NetRegistry.hero(int(_session.local_entry().get("seat", 0))))
	shown.emit(d)

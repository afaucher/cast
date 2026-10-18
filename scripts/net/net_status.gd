class_name NetStatus
extends Node
## Statuses across machines (docs/design/networking-build-plan.md M4b): child "Status" of the Session autoload.
##
## A status (a modifier: armor, coffee, the vines' root, a crash; a fire; a soak) is applied by the TARGET'S OWNER (a hero's
## player, the host for everything else: Combat.each_in_radius / Net.resolves), which also runs it (a fire ticks there,
## coffee's schedule runs there). The other screens only need to SEE it, so the owner announces what changed:
##   st {id, k "mods", v: {modifier: [mult, seconds left, stat]}}   every live modifier, when the set changes
##   st {id, k "burn", v: seconds left (0 = out)}                   a fire starts, is refreshed or goes out
##   st {id, k "soak", v: seconds left}                             a damp soak
## client -> host -> the other clients; the host speaks for its own actors. Changes are gathered and flushed once a physics
## frame. A modifier refreshed again and again (an armor zone renews it every 0.25 s) is announced only when its end moves
## by more than MOD_SLACK, and the copies keep each one GRACE past the announced end, so it does not blink.
## On a copy: Actor.net_set_modifiers (the armor shield, the coffee steam via Coffee.show_remote, the vines' leg wraps),
## Burning.show_remote (flames that deal nothing) and Wet.douse (drips; the soak keeps a copy from showing a new fire).

const GRACE := 0.35
const MOD_SLACK := 0.2

var active := false
var stats := {}

var _session: NetSession = null
var _dirty: Dictionary = {}       ## id -> {kind: true}
var _sent_mods: Dictionary = {}   ## id -> {modifier: [mult, until (GameWorld.time), stat]} as last announced


func _ready() -> void:
	_reset_stats()
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.event_received.connect(_on_event)
	_session.session_ended.connect(func(_reason: String) -> void: end())


func _reset_stats() -> void:
	stats = {"out": 0, "in": 0, "mods_out": 0, "burn_out": 0, "soak_out": 0}


func begin() -> void:
	end()
	active = _session != null and _session.online() and _session.roster.size() > 1
	_reset_stats()


func end() -> void:
	active = false
	_dirty.clear()
	_sent_mods.clear()


## The owner: a status of `a` changed (Net.status_changed). Flushed at the next physics frame.
func changed(a: Node, kind: String) -> void:
	if not active or a == null or not Net.owns(a):
		return
	var id := NetFloor.id_of(a)
	if id == 0:
		return
	if not _dirty.has(id):
		_dirty[id] = {}
	(_dirty[id] as Dictionary)[kind] = true


func _physics_process(_delta: float) -> void:
	if not active or _dirty.is_empty() or _session == null or not _session.online():
		return
	var dirty := _dirty
	_dirty = {}
	for id: int in dirty:
		var a := NetRegistry.node(id) as Actor
		if a == null or not is_instance_valid(a) or not Net.owns(a):
			continue
		for kind: String in dirty[id]:
			match kind:
				"mods":
					_flush_mods(id, a)
				"burn":
					_send(id, "burn", Burning.remaining(a))
					stats["burn_out"] = int(stats["burn_out"]) + 1
				"soak":
					_send(id, "soak", Burning.soaked_left(a))
					stats["soak_out"] = int(stats["soak_out"]) + 1


## Announce `a`'s modifiers if they changed enough since the last announcement.
func _flush_mods(id: int, a: Actor) -> void:
	var now := GameWorld.time
	var cur := a.modifiers_snapshot()
	var last: Dictionary = _sent_mods.get(id, {})
	var differs := cur.size() != last.size()
	if not differs:
		for m: String in cur:
			var e: Array = cur[m]
			if not last.has(m):
				differs = true
				break
			var l: Array = last[m]
			if absf(float(l[0]) - float(e[0])) > 0.0001 or str(l[2]) != str(e[2]) or absf(float(l[1]) - (now + float(e[1]))) > MOD_SLACK:
				differs = true
				break
	if not differs:
		return
	var record := {}
	for m: String in cur:
		var e: Array = cur[m]
		record[m] = [float(e[0]), now + float(e[1]), str(e[2])]
	_sent_mods[id] = record
	_send(id, "mods", cur)
	stats["mods_out"] = int(stats["mods_out"]) + 1


func _send(id: int, kind: String, value: Variant) -> void:
	_session.send_event(0, "st", {"id": id, "k": kind, "v": value})
	stats["out"] = int(stats["out"]) + 1


# --- Showing what an owner announced ---------------------------------------------------------------------

func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if kind != "st" or _session == null or not active:
		return
	var id := int(data.get("id", 0))
	if _session.hosting:
		# A client speaks only for its own seat's hero; the host passes it on.
		if _session.seats == null or id != _session.seats.seat_of(from):
			return
		for p: int in _session.roster:
			if p != 1 and p != from:
				_session.send_event(p, "st", data)
	var a := NetRegistry.node(id) as Actor
	if a == null or not is_instance_valid(a) or a.dead or Net.owns(a):
		return
	stats["in"] = int(stats["in"]) + 1
	_show(a, str(data.get("k", "")), data.get("v"))


# --- M6: a late joiner sees the statuses already running -----------------------------------------------------------

## Host: every live status on the floor as the owners last announced it (the host's own actors as they are; a player's hero
## as its copy shows it): [[id, mods, burn seconds, soak seconds]] for the actors that have any.
func late_join_state() -> Array:
	var out: Array = []
	for id in NetRegistry.ids():
		var a := NetRegistry.node(id) as Actor
		if a == null or a.dead:
			continue
		var mods := a.modifiers_snapshot()
		var burn := Burning.remaining(a)
		var soak := Burning.soaked_left(a)
		if not mods.is_empty() or burn > 0.0 or soak > 0.0:
			out.append([id, mods, burn, soak])
	return out


## The late joiner: show them (each status's owner keeps announcing changes from here on, as for everyone).
func apply_late_join(list: Array) -> void:
	for e: Variant in list:
		var row := e as Array
		if row == null or row.size() < 4:
			continue
		var a := NetRegistry.node(int(row[0])) as Actor
		if a == null or not is_instance_valid(a) or a.dead or Net.owns(a):
			continue
		if not (row[1] as Dictionary).is_empty():
			_show(a, "mods", row[1])
		if float(row[2]) > 0.0:
			_show(a, "burn", row[2])
		if float(row[3]) > 0.0:
			_show(a, "soak", row[3])


func _show(a: Actor, kind: String, v: Variant) -> void:
	match kind:
		"mods":
			var had_root := a.has_modifier("vines")
			a.net_set_modifiers(v as Dictionary if v is Dictionary else {}, GRACE)
			if not had_root and a.has_modifier("vines"):
				VineWrap.attach(a, a.modifier_left("vines"))
			if Coffee.is_hasted(a):
				Coffee.show_remote(a)
		"burn":
			Burning.show_remote(a, float(v))
		"soak":
			if float(v) > 0.0:
				Wet.douse(a, float(v))

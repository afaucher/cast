class_name SeatHandover
extends Node
## Who owns each crew seat's hero, and the two handovers (docs/design/networking-build-plan.md M2b and M6): a player
## who leaves gives the seat back to the AI, and a player who joins mid-contract takes an AI's seat.
##
## owners: seat -> the peer whose machine owns that seat's hero, or 0 for an AI hero (the host owns those). The game
## fills it when the floor is built (begin()) from the roster. epoch: seat -> a counter that goes up at every handover;
## the hero snapshot carries it (NetCodec, flags bits 4-7), so everyone drops a state the seat's PREVIOUS owner sent.
##
## A PLAYER DROPS (the host sees `peer_left`):
##   1. the seat's owner becomes 0 and its epoch goes up (a stale state from the old owner is ignored);
##   2. NetSnapshot lets go of the puppet: the hero stops being a copy and stands where the last snapshot left it
##      (position, HP, downed);
##   3. `to_ai(seat, character)` fires on the host and the game re-kits that hero node in place as the seat's
##      ORIGINAL character (the Rebar or Gasket the seat started as) and attaches an AllyBrain;
##   4. the host tells every client in a reliable event (`seat.ai {seat, character, epoch}`), whose `to_ai` makes
##      the same re-kit on their screens (the hero stays a puppet there: the host streams it from now on).
## The hero node and its net id never change, so followers, HUD rows and every reference to it stay valid.
##
## A PLAYER JOINS (M6, the other direction; NetJoin runs the join, this is the seat part):
##   - which seat: choose_seat(), the plan's order: an AI already playing the joiner's character, else the LIVING AI with
##     the most HP (tie: the lower seat), a downed AI only when none is alive;
##   - the host's take(seat, peer, character, state) at the moment the joiner reports its floor built: the epoch goes up,
##     `to_player(seat, peer, character)` fires (the game re-kits the SAME hero node as the joiner's character at full
##     health and drops the AllyBrain), NetSnapshot makes the hero a puppet of the joiner's stream, and every client gets
##     `seat.take {seat, peer, character, epoch, state}`;
##   - the joiner itself takes the seat from the host's late-join snapshot (take_local: the same re-kit, then the hero is
##     live there and gets `state`: position, facing, slots, charges, cooldowns, the held slot, modifiers, fire, soak).
##   - the joiner signed its own license while it waited (NetJoin, `join.signed`): `state` carries THOSE spells with fresh
##     charges, not the AI's, and every machine puts them on the hero as the seat changes hands (apply_loadout: the host
##     in take(), the other clients from `seat.take`, the joiner from its snapshot).
##
## A player who left BEFORE the floor's barrier (during the license checkout) has no hero state to hand over: the
## game converts that seat itself when it builds the table (game.gd `_drop_departed_seats`), identically on every
## machine, so the floor checksum still agrees. The table starts at the barrier (begin()), not at the roster.

## The game re-kits `seat`'s hero as `character`. On the host it also attaches the AllyBrain (Net.is_host()).
signal to_ai(seat: int, character: String)
## M6: a joiner (`peer`) took `seat`: the game re-kits its hero as `character` at full health (and on the host drops the
## AllyBrain). Emitted before NetSnapshot changes the hero's role.
signal to_player(seat: int, peer: int, character: String)

var owners: Dictionary = {}       ## seat -> peer (0 = AI)
var originals: Dictionary = {}    ## seat -> the character an AI plays in that seat
var epoch: Dictionary = {}        ## seat -> int, up at every handover
## Every handover this machine has seen: [{kind "ai" | "player", seat, peer, character, epoch, t}] (tests and logs). For a
## drop `peer` is the player who left; for a join it is the joiner.
var history: Array = []

var _session: NetSession = null


func _ready() -> void:
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.peer_left.connect(_on_peer_left)
	_session.event_received.connect(_on_event)
	_session.session_ended.connect(func(_reason: String) -> void: reset())
	_session.session_started.connect(func(_as_host: bool) -> void: reset())


func reset() -> void:
	owners = {}
	originals = {}
	epoch = {}
	history = []


## The floor's seats: `owners` (seat -> peer, 0 for AI) and `originals` (seat -> the AI character for that seat).
func begin(new_owners: Dictionary, new_originals: Dictionary) -> void:
	owners = new_owners.duplicate()
	originals = new_originals.duplicate()
	epoch = {}
	for seat: int in owners:
		epoch[seat] = 0


## M6, a late joiner: the host's table as it is now (seat -> [owner, epoch]), over the one this machine built at its barrier.
func apply_table(table: Dictionary) -> void:
	for k: Variant in table:
		var row := table[k] as Array
		owners[int(k)] = int(row[0])
		epoch[int(k)] = int(row[1])


## The table as the late-join snapshot carries it: seat -> [owner, epoch].
func table() -> Dictionary:
	var out := {}
	for seat: int in owners:
		out[seat] = [owner_of(seat), epoch_of(seat)]
	return out


func owner_of(seat: int) -> int:
	return int(owners.get(seat, 0))


## The seat a peer's hero sits in, 0 if it has none.
func seat_of(peer: int) -> int:
	for seat: int in owners:
		if int(owners[seat]) == peer and peer != 0:
			return seat
	return 0


func epoch_of(seat: int) -> int:
	return int(epoch.get(seat, 0))


## Host: the player in `seat` is gone (also the seam tests use). Does nothing on a client or for an AI seat.
func release(seat: int) -> void:
	if _session == null or not _session.hosting or not owners.has(seat) or owner_of(seat) == 0:
		return
	var peer := owner_of(seat)
	var character := str(originals.get(seat, NetSession.DEFAULT_CHARACTER))
	owners[seat] = 0
	epoch[seat] = epoch_of(seat) + 1
	if _session.snap != null:
		_session.snap.seat_released(seat)
	history.append({"kind": "ai", "seat": seat, "peer": peer, "character": character, "epoch": epoch_of(seat), "t": _session.host_time()})
	print("[Net] seat %d: peer %d is gone, the AI plays %s (epoch %d)" % [seat, peer, character, epoch_of(seat)])
	to_ai.emit(seat, character)
	_session.send_event(0, NetEvents.KIND_SEAT_AI, {"seat": seat, "character": character, "epoch": epoch_of(seat)})


# --- M6: a joiner takes an AI's seat ---------------------------------------------------------------------

## Which AI seat a joiner playing `character` takes, out of `free` (seats nobody in the crew holds). On a running floor
## (the seats' heroes exist) the plan's order: an AI already playing that character first, then the living AI with the
## most HP (tie: the lower seat), a downed one only when none is alive. Otherwise (between floors, on the board) the lowest
## free seat. 0 when `free` is empty.
func choose_seat(character: String, free: Array) -> int:
	var info := {}
	for s: Variant in free:
		var seat := int(s)
		var h := NetRegistry.hero(seat)
		if h == null or not owners.has(seat) or owner_of(seat) != 0:
			info = {}
			break
		info[seat] = {"kit": h.kit_id, "hp": h.hp, "dead": h.dead}
	return pick_seat(character, free, info)


## The order itself, on plain data (test_net_seats): `info` is seat -> {kit, hp, dead} for every seat in `free`, or {} when
## no floor is running (then: the lowest free seat).
static func pick_seat(character: String, free: Array, info: Dictionary) -> int:
	var seats: Array[int] = []
	for s: Variant in free:
		seats.append(int(s))
	seats.sort()
	if seats.is_empty():
		return 0
	if info.size() != seats.size():
		return seats[0]
	var same: Array[int] = []
	for s in seats:
		if str((info[s] as Dictionary).get("kit", "")) == character:
			same.append(s)
	return _strongest(same if not same.is_empty() else seats, info)


## The living seat with the most HP (the lower seat on a tie), else the lowest downed one.
static func _strongest(seats: Array[int], info: Dictionary) -> int:
	var best := 0
	var best_hp := -1.0
	for s in seats:
		var d: Dictionary = info[s]
		if bool(d.get("dead", false)):
			continue
		if float(d.get("hp", 0.0)) > best_hp:
			best = s
			best_hp = float(d.get("hp", 0.0))
	return best if best != 0 else seats[0]


## What a hero hands over with its seat (the owner's word on everything the stream does not carry): position, facing, HP,
## slots, charges, cooldowns left, the held slot, modifiers, fire and soak left.
static func hero_state(h: Hero) -> Dictionary:
	var cd := {}
	for k: Variant in h._ready_at:
		var left := float(h._ready_at[k]) - GameWorld.time
		if left > 0.0:
			cd[str(k)] = left
	return {"p": h.global_position, "f": h.facing, "hp": h.hp, "d": h.dead, "sl": Array(h.spell_slots), "ch": h._charges.duplicate(),
		"cd": cd, "hs": h.held_slot, "m": h.modifiers_snapshot(), "b": Burning.remaining(h), "s": Burning.soaked_left(h)}


## The new owner: put a handed-over state on its own hero (`full`: HP is the kit's full health, the decided arrival).
static func apply_state(h: Hero, st: Dictionary) -> void:
	h.global_position = st.get("p", h.global_position)
	var f: Vector3 = st.get("f", h.facing)
	if f.length() > 0.01:
		h.facing = f.normalized()
	h.reset_physics_interpolation()
	apply_loadout(h, st)
	var cd := st.get("cd", {}) as Dictionary
	for k: Variant in cd:
		h._ready_at[str(k)] = GameWorld.time + float(cd[k])
	var mods := st.get("m", {}) as Dictionary
	for m: Variant in mods:
		var e := mods[m] as Array
		if e != null and e.size() >= 3 and float(e[1]) > 0.0:
			h.set_modifier(str(m), float(e[0]), float(e[1]), str(e[2]))
	if float(st.get("b", 0.0)) > 0.0 and Burning.can_burn(h):
		Burning.ignite(h, null, float(st["b"]))
	if float(st.get("s", 0.0)) > 0.0:
		Burning.soak(h, float(st["s"]))


## A handed-over state's slots, charges and held slot on `h` (any machine: the new owner's own hero, or its puppet
## elsewhere, which shows what its owner holds).
static func apply_loadout(h: Hero, st: Dictionary) -> void:
	if not st.has("sl"):
		return
	var slots: Array[String] = []
	for s: Variant in st.get("sl", []) as Array:
		slots.append(str(s))
	h.spell_slots = slots
	var ch := {}
	var src := st.get("ch", {}) as Dictionary
	for k: Variant in src:
		if slots.has(str(k)):
			ch[str(k)] = int(src[k])
	for s in slots:
		if not ch.has(s):
			ch[s] = 0
	h._charges = ch
	h.held_slot = clampi(int(st.get("hs", 0)), 0, maxi(0, slots.size() - 1))
	h._refresh_hold()
	h.held_changed.emit()


## Host: `peer` (a joiner, now ready on this floor) takes the AI seat `seat` as `character`. `state` is the hero's state at
## this moment (hero_state, taken by the caller before anything changed). Everyone else is told; the joiner already has
## the same take in its late-join snapshot.
func take(seat: int, peer: int, character: String, state: Dictionary) -> void:
	if _session == null or not _session.hosting or not owners.has(seat) or owner_of(seat) != 0:
		return
	owners[seat] = peer
	epoch[seat] = epoch_of(seat) + 1
	history.append({"kind": "player", "seat": seat, "peer": peer, "character": character, "epoch": epoch_of(seat), "t": _session.host_time(),
		"p": state.get("p", Vector3.ZERO)})
	print("[Net] seat %d: peer %d takes over from the AI as %s (epoch %d)" % [seat, peer, character, epoch_of(seat)])
	to_player.emit(seat, peer, character)
	var h := NetRegistry.hero(seat)
	if h != null:
		apply_loadout(h, state)   # (the joiner's license, still this machine's hero for this one call)
	if _session.snap != null:
		_session.snap.seat_taken(seat, peer)
	for p: int in _session.roster:
		if p != 1 and p != peer:
			_session.send_event(p, NetEvents.KIND_SEAT_TAKE, {"seat": seat, "peer": peer, "character": character, "epoch": epoch_of(seat), "state": state})


## The joiner: take `seat` from the host's late-join snapshot (`take` is its {seat, character, epoch, state}).
func take_local(take: Dictionary) -> void:
	if _session == null or _session.hosting:
		return
	var seat := int(take.get("seat", 0))
	var me := _session.local_id()
	owners[seat] = me
	epoch[seat] = int(take.get("epoch", epoch_of(seat) + 1))
	var character := str(take.get("character", NetSession.DEFAULT_CHARACTER))
	history.append({"kind": "player", "seat": seat, "peer": me, "character": character, "epoch": epoch_of(seat), "t": _session.host_time(),
		"p": (take.get("state", {}) as Dictionary).get("p", Vector3.ZERO)})
	Net.apply_begin()   # (the hero is still a copy of the host's here: the re-kit is the host's decision arriving)
	to_player.emit(seat, me, character)
	Net.apply_end()
	if _session.snap != null:
		_session.snap.seat_taken(seat, me)
	var h := NetRegistry.hero(seat)
	if h != null:
		apply_state(h, take.get("state", {}) as Dictionary)


func _on_peer_left(peer: int) -> void:
	if _session != null and _session.hosting:
		var seat := seat_of(peer)
		if seat != 0:
			release(seat)


func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if (kind != NetEvents.KIND_SEAT_AI and kind != NetEvents.KIND_SEAT_TAKE) or _session == null or _session.hosting or from != 1:
		return
	var seat := int(data.get("seat", 0))
	if not owners.has(seat) or int(data.get("epoch", 0)) <= epoch_of(seat):
		return
	var character := str(data.get("character", NetSession.DEFAULT_CHARACTER))
	epoch[seat] = int(data["epoch"])
	if kind == NetEvents.KIND_SEAT_AI:
		owners[seat] = 0
		history.append({"kind": "ai", "seat": seat, "peer": 0, "character": character, "epoch": epoch_of(seat), "t": _session.host_time()})
		to_ai.emit(seat, character)
		return
	var peer := int(data.get("peer", 0))
	owners[seat] = peer
	history.append({"kind": "player", "seat": seat, "peer": peer, "character": character, "epoch": epoch_of(seat), "t": _session.host_time(),
		"p": (data.get("state", {}) as Dictionary).get("p", Vector3.ZERO)})
	to_player.emit(seat, peer, character)
	var h := NetRegistry.hero(seat)
	if h != null:
		apply_loadout(h, data.get("state", {}) as Dictionary)   # (the joiner's license on its puppet here)
	if _session.snap != null:
		_session.snap.seat_taken(seat, peer)

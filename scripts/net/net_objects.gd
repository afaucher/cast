class_name NetObjects
extends Node
## Host-arbitrated world objects, pickups and the money (docs/design/networking-build-plan.md M3b/M3c): child
## "Objects" of the Session autoload. The HOST owns every priced prop, crate, mail package, component pickup and
## employee, the Ledger and the contract's bookkeeping; a player's machine only ASKS (Net.request, Net.route_hit) and
## the host decides once, then tells everyone. Every message here is a reliable event, kinds "obj.*".
##
##   HITS       a client's hit on a prop, crate or mail box (Actor.apply_damage on a copy -> Net.route_hit) is a
##              request `obj.req {what "hit", id, a, by}`; the host applies it to its own object. A prop the host
##              breaks is billed ONCE, in the host's Ledger; the break reaches everyone as `obj.break` (a mail box with
##              its contents, which only the host rolls), a dent as `obj.hurt`.
##   PICKUPS    the host gives every component pickup an id (NetRegistry, from the runtime base) and announces it
##              (`obj.pickup`); its charges and its end follow (`obj.pick`, `obj.gone`). A client walking onto one asks
##              (`collect`, with how many charges it can take and where its hero stands), F asks to `swap`; the host
##              grants the FIRST request (`obj.grant` to that player only; anyone else is told `obj.deny`), so two
##              players grabbing at once never both get it. The player's own machine then changes its own hero's
##              slots and charges (they are OWNER fields) and tells the crew (`obj.loadout`). A swapped-out spell is
##              a `drop` request: the host puts the pickup down.
##   EMPLOYEES  E on an employee from a client is `follow` / `wait` (Employee.request_follow / request_wait run on
##              the host, judged from where the client says its hero stands).
##   MONEY      every Ledger line the host writes goes to every client (`obj.ledger`), whose Ledger is a MIRROR
##              (Ledger.mirror: its own writes are dropped), and the objective bookkeeping follows
##              (`obj.contract`, ContractSession.mirror_state), so the tracker, the ticker and the invoice agree.
##   EXITS      the elevator and the van are first-to-choose: a choice is a request, the host takes the first one
##              (`obj.exit {c, seat}` to everyone) and drops the rest; a cash-out ends the job with the host's
##              invoice (`obj.end`).
##
## Trusting a client's word for where its hero stands is deliberate: friends only, no cheating concern
## (networking.md), and the host's picture of that hero is about 100 ms old.

## Client: the host's objective bookkeeping (ContractSession.mirror_state()).
signal contract_received(state: Dictionary)
## Every machine: the crew's exit was decided ("down", "out" or "van") by the player in `seat`.
signal exit_decided(choice: String, seat: int)
## Client: the host ended the job; this is its invoice.
signal end_received(invoice: Dictionary)
## This machine's player was given a pickup (kind "collect" or "swap").
signal granted(kind: String, spell: String, amount: int)

const REACH_SLACK := 0.5       ## a claimed position may be this much beyond the pickup's own radius
const REQUEST_RETRY := 0.8     ## a client asks again for a pickup after this long without an answer

var active := false
var stats := {}

var _session: NetSession = null
var _local: Hero = null
var _pickups: Dictionary = {}      ## host: id -> [ComponentPickup, charges announced]; client: id -> ComponentPickup
var _ticked: Array[Node] = []      ## client: props and mail boxes that run their local look (net_tick)
var _requested: Dictionary = {}    ## client: pickup id -> host_time asked
var _links: Array = []
var _exit_taken := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_stats()
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.event_received.connect(_on_event)
	_session.session_ended.connect(func(_reason: String) -> void:
		end()
		Ledger.mirror = false)
	Ledger.line_added.connect(_on_ledger_line)


func _reset_stats() -> void:
	stats = {"hits_out": 0, "hits_in": 0, "breaks": 0, "grants": 0, "denies": 0, "requests": 0, "pickups": 0,
		"ledger_out": 0, "ledger_in": 0, "loadouts": 0}


# --- Setup -----------------------------------------------------------------------------------------------

## The floor is built (ids assigned). `local` is the hero this machine's player controls.
func begin(local: Hero) -> void:
	end()
	if _session == null or not _session.online():
		return
	_local = local
	_exit_taken = false
	for id in NetRegistry.ids():
		var n := NetRegistry.node(id)
		if n is ComponentPickup:
			_pickups[id] = [n, (n as ComponentPickup).charges] if _session.hosting else n
		elif _session.hosting:
			if n is PricedProp:
				_link((n as PricedProp).damaged, _on_prop_hurt.bind(id))
				_link((n as PricedProp).broken, _on_broken.bind(id))
			elif n is BreakableCrate:
				_link((n as BreakableCrate).broken, _on_broken.bind(id))
			elif n is MailPackage:
				_link((n as MailPackage).broken, _on_mail_broken.bind(id))
		elif n is PricedProp or n is MailPackage:
			_ticked.append(n)
	if local != null:
		_link(local.component_collected, func(_id: String, _n: int, _r: String) -> void: send_loadout())
		_link(local.component_swapped, func(_o: String, _n: String, _s: int) -> void: send_loadout())
	_reset_stats()
	active = true


func end() -> void:
	active = false
	for l: Array in _links:
		var sig: Signal = l[0]
		if is_instance_valid(sig.get_object()) and sig.is_connected(l[1]):
			sig.disconnect(l[1])
	_links.clear()
	_pickups.clear()
	_ticked.clear()
	_requested.clear()
	_local = null


func _link(sig: Signal, c: Callable) -> void:
	if not sig.is_connected(c):
		sig.connect(c)
	_links.append([sig, c])


func _host() -> bool:
	return _session != null and _session.hosting and _session.online()


func _crewed() -> bool:
	return _session != null and _session.online() and _session.roster.size() > 1


## A client on a running shared floor: what it does to the host's things becomes a request.
func client_live() -> bool:
	return active and _session != null and _session.is_client()


func pickup_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _pickups:
		out.append(id)
	out.sort()
	return out


# --- Asking (client) ----------------------------------------------------------------------------------------

## A hit on a host-owned object from this machine (Net.route_hit). True when it was sent.
func request_hit(target: Actor, amount: float, source: Node) -> bool:
	if not client_live() or amount <= 0.0:
		return false
	var id := NetFloor.id_of(target)
	if id == 0:
		return false
	_session.send_event(1, "obj.req", {"what": "hit", "id": id, "a": amount, "by": NetFloor.id_of(source)})
	stats["hits_out"] = int(stats["hits_out"]) + 1
	return true


## Ask the host for something about `node` ("collect", "swap", "follow", "wait"). True when it was sent.
func request(node: Node, what: String, data: Dictionary = {}) -> bool:
	if not client_live():
		return false
	var id := NetFloor.id_of(node)
	if id == 0:
		return false
	if what == "collect" or what == "swap":
		var asked := float(_requested.get(id, -INF))
		if _now() - asked < REQUEST_RETRY:
			return true   # already asked; the answer is on its way
		_requested[id] = _now()
	var d := data.duplicate()
	d["what"] = what
	d["id"] = id
	if _local != null:
		d["at"] = _local.global_position
	_session.send_event(1, "obj.req", d)
	stats["requests"] = int(stats["requests"]) + 1
	return true


## A client puts a pickup down (a swapped-out spell): the host drops it and announces it.
func request_drop(spell: String, amount: int, pos: Vector3, life: float) -> void:
	if client_live():
		_session.send_event(1, "obj.req", {"what": "drop", "s": spell, "n": amount, "at": pos, "l": life})


## This machine's player chose an exit. The host decides at once; a client asks.
func choose_exit(choice: String) -> void:
	if _host():
		decide_exit(choice, 1)
	elif _session != null and _session.is_client():
		_session.send_event(1, "obj.req", {"what": "exit", "c": choice})


## Host: the first exit choice of the floor wins; false for any later one.
func decide_exit(choice: String, seat: int) -> bool:
	if not _host() or _exit_taken:
		return false
	_exit_taken = true
	_send(0, "obj.exit", {"c": choice, "seat": seat})
	exit_decided.emit(choice, seat)
	return true


func exit_taken() -> bool:
	return _exit_taken


## This machine's hero's slots and charges, to the crew (they are its OWNER fields; pickups change them).
func send_loadout() -> void:
	if _local == null or not is_instance_valid(_local) or not _crewed():
		return
	var d := {"seat": NetFloor.id_of(_local), "sl": Array(_local.spell_slots), "ch": _local._charges.duplicate()}
	_session.send_event(0, "obj.loadout", d)
	stats["loadouts"] = int(stats["loadouts"]) + 1


# --- Host: telling ----------------------------------------------------------------------------------------

## Host: the objective bookkeeping changed.
func send_contract(state: Dictionary) -> void:
	if _host() and _crewed():
		_send(0, "obj.contract", {"d": state})


## Host: the job is over; every client shows this invoice.
func send_end(invoice: Dictionary) -> void:
	if _host() and _crewed():
		_send(0, "obj.end", {"inv": invoice})


func _send(to: int, kind: String, data: Dictionary) -> void:
	if _session != null and _session.online():
		_session.send_event(to, kind, data)


func _on_ledger_line(line: Dictionary) -> void:
	if _host() and _crewed() and not Ledger.mirror:
		_send(0, "obj.ledger", {"line": line})
		stats["ledger_out"] = int(stats["ledger_out"]) + 1


func _on_prop_hurt(amount: float, _source: Node, id: int) -> void:
	var p := NetRegistry.node(id) as PricedProp
	if p != null and not p.dead and p.hp > 0.0:
		_send(0, "obj.hurt", {"id": id, "hp": p.hp, "a": amount})


func _on_broken(_obj: Node, _culprit: Node, id: int) -> void:
	_send(0, "obj.break", {"id": id})
	stats["breaks"] = int(stats["breaks"]) + 1


func _on_mail_broken(pkg: MailPackage, _culprit: Node, contents: String, id: int) -> void:
	_send(0, "obj.break", {"id": id, "c": contents, "cr": pkg.crypto_amount, "cid": pkg.component_id})
	stats["breaks"] = int(stats["breaks"]) + 1


# --- Every frame ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active or _session == null or not _session.online():
		return
	if _session.hosting:
		_host_pickups()
	else:
		for id: int in _pickups.keys():
			var p: ComponentPickup = _pickups[id] if is_instance_valid(_pickups[id]) else null
			if p == null:
				_pickups.erase(id)
				continue
			p.net_tick(delta)
		for n in _ticked:
			if is_instance_valid(n) and not (n as Actor).dead:
				n.call("net_tick", delta)


## Host: give new pickups an id and announce them; tell everyone when one's charges change or it is gone.
func _host_pickups() -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("component_pickups"):
		var p := n as ComponentPickup
		if p == null or NetFloor.id_of(p) != 0 or p._used or not GameWorld.root.is_ancestor_of(p):
			continue
		var id := NetRegistry.next_runtime_id()
		NetRegistry.register(id, p)
		_pickups[id] = [p, p.charges]
		_send(0, "obj.pickup", {"id": id, "s": p.spell_id, "n": p.charges, "at": p.global_position, "l": p.lifetime, "age": p._age})
		stats["pickups"] = int(stats["pickups"]) + 1
	for id: int in _pickups.keys():
		var e: Array = _pickups[id]
		var p: ComponentPickup = e[0] if is_instance_valid(e[0]) else null
		if p == null or p._used or p.is_queued_for_deletion():
			_pickups.erase(id)
			_send(0, "obj.gone", {"id": id})
		elif p.charges != int(e[1]):
			e[1] = p.charges
			_send(0, "obj.pick", {"id": id, "n": p.charges})


# --- Messages --------------------------------------------------------------------------------------------------

func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if not kind.begins_with("obj.") or _session == null:
		return
	if _session.hosting:
		match kind:
			"obj.req":
				_host_request(from, data)
			"obj.loadout":
				_host_loadout(from, data)
		return
	if from != 1:
		return
	match kind:
		"obj.ledger":
			if Ledger.mirror:
				Ledger.mirror_line(data.get("line", {}) as Dictionary)
				stats["ledger_in"] = int(stats["ledger_in"]) + 1
		"obj.contract":
			contract_received.emit(data.get("d", {}) as Dictionary)
		"obj.end":
			end_received.emit(data.get("inv", {}) as Dictionary)
		"obj.exit":
			exit_decided.emit(str(data.get("c", "")), int(data.get("seat", 0)))
		"obj.loadout":
			_apply_loadout(data)
	if not active:
		return
	match kind:
		"obj.break":
			_client_break(data)
		"obj.hurt":
			var p := NetRegistry.node(int(data.get("id", 0))) as PricedProp
			if p != null and not p.dead:
				p.hp = float(data.get("hp", p.hp))
				p._on_damaged(float(data.get("a", 0.0)), null)
		"obj.pickup":
			_client_pickup(data)
		"obj.pick":
			var held: Variant = _pickups.get(int(data.get("id", 0)))
			var p: ComponentPickup = held if held != null and is_instance_valid(held) else null
			if p != null:
				p.charges = int(data.get("n", p.charges))
		"obj.gone":
			var id := int(data.get("id", 0))
			var held: Variant = _pickups.get(id)
			var p: ComponentPickup = held if held != null and is_instance_valid(held) else null
			_pickups.erase(id)
			_requested.erase(id)
			if p != null and not p._used:
				p.consume()
		"obj.grant":
			_client_grant(data)
		"obj.deny":
			_requested.erase(int(data.get("id", 0)))
			stats["denies"] = int(stats["denies"]) + 1


func _host_request(from: int, data: Dictionary) -> void:
	var what := str(data.get("what", ""))
	var seat := _session.seats.seat_of(from) if _session.seats != null else 0
	var hero := NetRegistry.hero(seat)
	var at: Vector3 = data.get("at", hero.global_position if hero != null else Vector3.INF)
	stats["requests"] = int(stats["requests"]) + 1
	match what:
		"exit":
			decide_exit(str(data.get("c", "")), seat)
		"drop":
			if active:
				ComponentPickup.drop(str(data.get("s", "")), int(data.get("n", 0)), at, float(data.get("l", 0.0)))
		"hit":
			if not active:
				return
			var t := NetRegistry.node(int(data.get("id", 0))) as Actor
			if t == null or t.dead or not Net.routes_hits(t):
				return
			stats["hits_in"] = int(stats["hits_in"]) + 1
			t.apply_damage(float(data.get("a", 0.0)), NetRegistry.node(int(data.get("by", 0))))
		"collect", "swap":
			if active:
				_host_grant(from, int(data.get("id", 0)), what, int(data.get("want", 0)), at)
		"follow", "wait":
			if not active or hero == null:
				return
			var e := NetRegistry.node(int(data.get("id", 0))) as Employee
			if e == null or e.dead:
				return
			if what == "follow":
				e.request_follow(hero, at)
			else:
				e.request_wait(hero, at)


## Host: the first player to ask gets the pickup (up to what they can take); everyone after is told no.
func _host_grant(from: int, id: int, what: String, want: int, at: Vector3) -> void:
	var e: Array = _pickups.get(id, [])
	var p: ComponentPickup = e[0] if not e.is_empty() else null
	var reach := (SpellComponents.COLLECT_RADIUS if what == "collect" else SpellComponents.SWAP_RADIUS) + REACH_SLACK
	if p == null or not is_instance_valid(p) or p._used or p.charges <= 0 or at == Vector3.INF \
			or GameWorld.flat_distance(at, p.global_position) > reach:
		_send(from, "obj.deny", {"id": id})
		stats["denies"] = int(stats["denies"]) + 1
		return
	var taken := p.charges if what == "swap" else clampi(want, 1, p.charges)
	var spell := p.spell_id
	var pos := p.global_position
	p.charges -= taken
	if p.charges <= 0:
		p.consume()
	_send(from, "obj.grant", {"id": id, "k": what, "s": spell, "n": taken, "at": pos})
	stats["grants"] = int(stats["grants"]) + 1
	_host_pickups()   # the change goes out now, ahead of anything else about this pickup


func _host_loadout(from: int, data: Dictionary) -> void:
	var seat := _session.seats.seat_of(from) if _session.seats != null else 0
	if seat == 0 or int(data.get("seat", 0)) != seat:
		return
	_apply_loadout(data)
	for p: int in _session.roster:
		if p != 1 and p != from:
			_session.send_event(p, "obj.loadout", data)


## Another player's hero's slots and charges, on its copy here.
func _apply_loadout(data: Dictionary) -> void:
	var hero := NetRegistry.hero(int(data.get("seat", 0)))
	if hero == null or not Net.is_puppet(hero):
		return
	var slots: Array[String] = []
	for s: Variant in data.get("sl", []) as Array:
		slots.append(str(s))
	hero.spell_slots = slots
	var ch: Dictionary = {}
	var src := data.get("ch", {}) as Dictionary
	for k: Variant in src:
		ch[str(k)] = int(src[k])
	hero._charges = ch
	hero._refresh_hold()
	stats["loadouts"] = int(stats["loadouts"]) + 1


func _client_break(data: Dictionary) -> void:
	var n := NetRegistry.node(int(data.get("id", 0))) as Actor
	if n == null or n.dead:
		return
	if n is MailPackage:
		var m := n as MailPackage
		m.forced_contents = str(data.get("c", ""))
		m.crypto_amount = int(data.get("cr", 0))
		m.component_id = str(data.get("cid", ""))
	_ticked.erase(n)
	Net.remote_die(n)
	stats["breaks"] = int(stats["breaks"]) + 1


func _client_pickup(data: Dictionary) -> void:
	var id := int(data.get("id", 0))
	if NetRegistry.has_id(id) or GameWorld.root == null:
		return
	var p := ComponentPickup.copy_at(str(data.get("s", "")), int(data.get("n", 1)), data.get("at", Vector3.ZERO), float(data.get("l", 0.0)), float(data.get("age", 0.0)))
	if p == null:
		return
	NetRegistry.register(id, p)
	Net.make_copy(p)
	_pickups[id] = p
	stats["pickups"] = int(stats["pickups"]) + 1


func _client_grant(data: Dictionary) -> void:
	var id := int(data.get("id", 0))
	_requested.erase(id)
	var hero := _local
	if hero == null or not is_instance_valid(hero) or hero.dead:
		return
	var spell := str(data.get("s", ""))
	var n := int(data.get("n", 0))
	match str(data.get("k", "")):
		"collect":
			hero.collect_component(spell, n)
		"swap":
			hero.apply_swap(spell, n, data.get("at", hero.global_position))
	stats["grants"] = int(stats["grants"]) + 1
	granted.emit(str(data.get("k", "")), spell, n)


func _now() -> float:
	return _session.host_time() if _session != null else 0.0

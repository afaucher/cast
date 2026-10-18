class_name NetCasts
extends Node
## Casts and hero attacks across machines (docs/design/networking-build-plan.md M4a): child "Casts" of the Session
## autoload, so it survives the scene reloads.
##
## CASTS. Voice recognition stays on each player's machine. A cast on a crewed floor (SpellBook.cast, Net.shares_cast)
## is resolved ONCE, on the caster's machine (the target point, the teammate the aim snapped onto, a fireball's launch),
## and sent as a reliable event `cast {c caster id, s spell, p power, t target, h followed hero id, x extra, at, ch}`:
## client -> host -> the other clients. The caster plays the cast pose at once (Hero.try_cast); the gameplay effect lands
## at `at` = the cast's host_time + LEAD (150-250 ms, tunable) on EVERY machine, the caster's included
## (SpellBook.apply, with the cast's moment as the scheduled effect's SPAWN start time). Every target the effect reaches
## is applied by the one machine that resolves it (Combat, layer 4), so a corn hits each hero once (on its owner's
## machine, against where its owner has it) and a heal aimed at a teammate heals that teammate once. `ch` is the
## caster's charges of that spell after the spend: the other screens' copy of the hero shows them.
##
## ATTACKS. A hero this machine owns swings, shoots, bowls or spins (Hero.melee / shoot, also the host's AI heroes):
## `act {c, a kind, d direction, r drawn, t host_time}` goes to everyone, and each other machine replays it on its puppet
## of that hero when the puppet shows the moment `t` (Hero.net_act): the swing and the shot show, and a teammate's spin
## or boulder shoves THIS machine's hero if it reaches it here (the victim applies a shove on itself, rule 5). The
## attacker's machine already decided every monster (rule 2).

signal cast_applied(spell: String, caster: Actor, node: Node)

## Seconds between a cast and its effect on every machine (networking.md "Spells: show it now, resolve it on a short
## delay": 150-250 ms, tunable). Covers a client -> host -> client trip on a coast-to-coast link.
const LEAD := 0.2
## A replayed attack waits at most this long for its puppet to show the moment it happened.
const ACT_WAIT_MAX := 0.45

var active := false
var stats := {}
## Test seam: the last applied cast of each spell on this machine: {at, applied (host_time), late, caster}.
var last_applied := {}

var _session: NetSession = null
var _pending: Array[Dictionary] = []   ## casts waiting for their moment, by `at`
var _acts: Array = []                  ## [t, hero id, kind, dir, drawn, arrival]


func _ready() -> void:
	_reset_stats()
	_session = get_parent() as NetSession
	if _session == null:
		return
	_session.event_received.connect(_on_event)
	_session.session_ended.connect(func(_reason: String) -> void: end())


func _reset_stats() -> void:
	stats = {"casts_out": 0, "casts_in": 0, "applied": 0, "late": 0, "max_late": 0.0, "acts_out": 0, "acts_in": 0,
		"acts_played": 0, "dropped": 0}


## The floor is running with a crew (the game calls it with the hero sync).
func begin() -> void:
	end()
	active = _session != null and _session.online() and _session.roster.size() > 1
	_reset_stats()


func end() -> void:
	active = false
	_pending.clear()
	_acts.clear()
	last_applied.clear()


## True when a cast from `caster` travels as an event (this machine's hero, on a crewed floor).
func shares(caster: Node) -> bool:
	return active and caster is Hero and Net.owns(caster) and NetFloor.id_of(caster) != 0


# --- Casts ----------------------------------------------------------------------------------------------

## The caster's machine: send the cast and schedule it here too (SpellBook.cast built `spec`).
func send_cast(caster: Actor, spec: Dictionary) -> void:
	var spell := str(spec.get("spell", ""))
	var follow := spec.get("follow") as Node
	var hero := caster as Hero
	var d := {
		"c": NetFloor.id_of(caster), "s": spell, "p": float(spec.get("power", 1.0)), "t": spec.get("target", Vector3.ZERO),
		"h": NetFloor.id_of(follow) if follow != null and is_instance_valid(follow) else 0,
		"x": spec.get("extra", {}), "at": _now() + LEAD,
		"ch": maxi(0, hero.charges_of(spell) - 1) if hero != null else 0,   # (Hero.try_cast spends one right after)
	}
	_session.send_event(0, "cast", d)
	stats["casts_out"] = int(stats["casts_out"]) + 1
	_schedule(d)


func _schedule(d: Dictionary) -> void:
	var at := float(d.get("at", 0.0))
	var i := _pending.size()
	while i > 0 and float(_pending[i - 1].get("at", 0.0)) > at:
		i -= 1
	_pending.insert(i, d)


func _apply(d: Dictionary, now: float) -> void:
	var caster := NetRegistry.node(int(d.get("c", 0))) as Actor
	if caster == null or not is_instance_valid(caster):
		stats["dropped"] = int(stats["dropped"]) + 1
		return
	var at := float(d.get("at", now))
	var late := maxf(0.0, now - at)
	var h := int(d.get("h", 0))
	var spec := {"spell": str(d.get("s", "")), "power": float(d.get("p", 1.0)), "target": d.get("t", caster.global_position),
		"follow": NetRegistry.node(h) if h != 0 else null, "extra": d.get("x", {})}
	var node := SpellBook.apply(caster, spec, GameWorld.time - late)
	stats["applied"] = int(stats["applied"]) + 1
	if late > 1.5 / 60.0:
		stats["late"] = int(stats["late"]) + 1
	stats["max_late"] = maxf(float(stats["max_late"]), late)
	last_applied[str(spec["spell"])] = {"at": at, "applied": now, "late": late, "caster": int(d.get("c", 0))}
	cast_applied.emit(str(spec["spell"]), caster, node)


# --- Attacks --------------------------------------------------------------------------------------------

## A hero this machine owns attacked (Net.hero_acted).
func acted(hero: Hero, kind: String, dir: Vector3, drawn: bool) -> void:
	if not active or not Net.owns(hero):
		return
	var id := NetFloor.id_of(hero)
	if id == 0:
		return
	_session.send_event(0, "act", {"c": id, "a": kind, "d": Vector2(dir.x, dir.z), "r": drawn, "t": _now()})
	stats["acts_out"] = int(stats["acts_out"]) + 1


# --- Every physics frame: what is due ------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not active or _session == null or not _session.online():
		return
	var now := _now()
	while not _pending.is_empty() and float(_pending[0].get("at", 0.0)) <= now:
		_apply(_pending.pop_front(), now)
	if _acts.is_empty():
		return
	var keep: Array = []
	for e: Array in _acts:
		var hero := NetRegistry.node(int(e[1])) as Hero
		if hero == null or not Net.is_puppet(hero):
			continue   # (gone, or it is this machine's own: nothing to replay)
		var shown := _session.snap.render_time(int(e[1])) if _session.snap != null else 0.0
		if shown < float(e[0]) and now - float(e[5]) < ACT_WAIT_MAX:
			keep.append(e)
			continue
		hero.net_act(str(e[2]), e[3], bool(e[4]))
		stats["acts_played"] = int(stats["acts_played"]) + 1
	_acts = keep


# --- Messages ---------------------------------------------------------------------------------------------

func _on_event(from: int, kind: String, data: Dictionary, _stamp: float) -> void:
	if (kind != "cast" and kind != "act") or _session == null or not active:
		return
	if _session.hosting:
		# A client may only speak for its own seat's hero; the host passes it on to the other clients.
		if _session.seats == null or int(data.get("c", 0)) != _session.seats.seat_of(from):
			return
		for p: int in _session.roster:
			if p != 1 and p != from:
				_session.send_event(p, kind, data)
	if kind == "cast":
		stats["casts_in"] = int(stats["casts_in"]) + 1
		var hero := NetRegistry.node(int(data.get("c", 0))) as Hero
		if hero != null and Net.is_puppet(hero):
			var spell := str(data.get("s", ""))
			if hero.spell_slots.has(spell):
				hero._charges[spell] = int(data.get("ch", hero.charges_of(spell)))   # (the owner's count, carried by the cast)
			hero.net_act("cast", Vector3.ZERO, false)   # the cast pose, now
		_schedule(data)
	else:
		stats["acts_in"] = int(stats["acts_in"]) + 1
		var d: Vector2 = data.get("d", Vector2.ZERO)
		_acts.append([float(data.get("t", 0.0)), int(data.get("c", 0)), str(data.get("a", "")), Vector3(d.x, 0.0, d.y),
			bool(data.get("r", false)), _now()])


func _now() -> float:
	return _session.host_time() if _session != null else 0.0

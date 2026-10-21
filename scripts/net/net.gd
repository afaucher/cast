class_name Net
## Authority classes for networked state (docs/design/networking.md, "Keeping authority straight").
##
## Every class whose state matters in co-op returns `net_fields() -> {var name: Net.KIND}` covering
## EVERY script var it has, and test_net_contract fails when a var is missing or a name is stale. The
## snapshot packer and the debug write guards will be driven by the same declarations.
##
## It is also the facade gameplay code asks (it never sends anything itself; that is scripts/net/):
## `Net.is_host()`, `Net.online()`, `Net.owns(node)`, `Net.is_puppet(node)`, `Net.request(...)` (M3). The transport is
## the Session autoload (NetSession, M0).
##
## Owner: a hero's player owns that hero; the host owns everything else (monsters, hellgates,
## employees, props, pickups, the contract). "Owner" below means that machine.

enum {
	SPAWN,    ## Fixed when the thing is created (from the spawn/cast event or the seed), never written after. Same on every machine, never streamed.
	OWNER,    ## The owner writes it; everyone else receives it (snapshot or event). Non-owners never write it.
	PRIVATE,  ## The owner's working state (AI timers, slide internals). Not replicated; non-owners must not use it for gameplay.
	LOCAL,    ## Every machine keeps its own: presentation (models, visual timers, cosmetic phase) or a value recomputed from OWNER/SPAWN state and GameWorld.time.
}

const NAMES := {SPAWN: "SPAWN", OWNER: "OWNER", PRIVATE: "PRIVATE", LOCAL: "LOCAL"}


static func is_kind(v: Variant) -> bool:
	return v is int and NAMES.has(v)


## True on the host, and offline (solo is hosting with nobody joining), so solo code paths never change.
static func is_host() -> bool:
	var s := session()
	return s == null or s.is_host()


## In a crew session (hosting or joined).
static func online() -> bool:
	var s := session()
	return s != null and s.online()


## In a crew session with someone else in it (the shared-run rules apply: no local pause, no exits yet).
## A host alone in an online session is NOT crewed: solo play stays exactly as it is offline.
static func crewed() -> bool:
	var s := session()
	return s != null and s.online() and s.roster.size() > 1


## The shared-run state machine (board, job, checkout, floor barrier, floor clock), or null.
static func flow() -> CrewFlow:
	var s := session()
	return s.flow if s != null else null


# --- Who simulates what (M1: the first half; M3 builds the rest on it) ------------------------------------
# Host-owned actors (monsters, hellgates, employees, props, packages, crates, the AI heroes) are SIMULATED by
# the host only. On a client they are COPIES: built from the same seed, standing where the plan puts them, but
# with no AI, no logic and no damage taken, until M3 syncs them. `simulates(node)` is the one question every
# system asks ("do I run this?"); it is true everywhere offline and on the host, and on a client for
# everything that is not a copy (its own hero, spells it cast, effects). It never changes solo play.

const COPY_META := "net_copy"


## True when this machine simulates `node` (everything, unless it was made a copy).
static func simulates(node: Object) -> bool:
	return not is_copy(node)


## True for a non-acting copy of a host-owned thing (see above).
static func is_copy(node: Object) -> bool:
	return node != null and node.has_meta(COPY_META)


## Make `node` a copy: it stops its physics process (AI and logic) and stops taking damage and shoves.
static func make_copy(node: Node) -> void:
	node.set_meta(COPY_META, true)
	node.set_physics_process(false)


## Make a copy act again (a seat handed back to the AI: the hero was a puppet of a player who left).
static func release_copy(node: Node) -> void:
	node.remove_meta(COPY_META)
	if node.has_meta(PUPPET_META):
		node.remove_meta(PUPPET_META)
	node.set_physics_process(true)


# --- Heroes (M2): every machine owns its own seat's hero and shows the others as puppets -----------------------
# A PUPPET is a hero copy that applies the state its owner streams (NetSnapshot): it is not simulated here (no
# controller, no AI, no damage taken, no shoves) but keeps animating from the state it is shown. The local player's
# hero and, on the host, the AI heroes of empty seats are simulated here and streamed to the others.

const PUPPET_META := "net_puppet"
const NAME_META := "net_player_name"


## Make `node` a puppet: a copy that a snapshot stream moves.
static func make_puppet(node: Node) -> void:
	make_copy(node)
	node.set_meta(PUPPET_META, true)


static func is_puppet(node: Object) -> bool:
	return node != null and node.has_meta(PUPPET_META)


## True when this machine is the owner of `node` (the authority for its OWNER fields): offline, everything; online,
## whatever is not a copy of somebody else's. M3: on a client every host-owned thing (monsters, hellgates, employees,
## props, crates, mail, pickups) is a copy or a puppet, so this is false for it there and true on the host; a client's
## own hero, and what it casts, are its own.
static func owns(node: Object) -> bool:
	return simulates(node)


# --- The host-owned world (M3): verbs on things another machine owns become requests --------------------------------

## Show a death the owner decided on a copy here (the owner's death event or snapshot): `dead`, hp 0, the signals and
## the death visuals, exactly as a die() on the owner would, but without deciding anything (a monster's drops, a mail
## box's contents, a prop's bill are the owner's: the classes check Net.owns in their _on_death).
static func remote_die(a: Actor) -> void:
	if a == null or a.dead:
		return
	a.hp = 0.0
	a.dead = true
	a.died.emit()
	GameWorld.actor_died.emit(a)
	a._on_death()


## What a player's hit is sent to the host for: every host-owned actor (M3c: priced props, crates, mail boxes; M4: monsters,
## hellgates and employees too, "the attacker decides"). A hero is never routed a hit: its owner decides (rule 1).
static func routes_hits(a: Object) -> bool:
	return a is Actor and not (a is Hero)


## Actor.apply_damage on a copy: a hit this machine decided on a host-owned actor becomes a request to the host (the host
## applies it once: a monster loses the HP, a prop breaks and is billed once). A hit on a hero copy is ignored.
static func route_hit(target: Actor, amount: float, source: Node) -> void:
	var s := session()
	if s == null or s.objects == null or not routes_hits(target):
		return
	if source != null and is_instance_valid(source) and not owns(source):
		return   # (a copy never acts: only what this machine runs may hit anything)
	s.objects.request_hit(target, amount, source)


## A shove on something this machine does not own (Actor.shove on a copy): a request to its owner (rule 5). The host
## applies it to its own actors and passes a shove on a player's hero to that player's machine, which runs Actor.shove
## itself (and drops it while the hero is rooted).
static func route_shove(target: Actor, dir: Vector3, distance: float, source: Node) -> void:
	var s := session()
	if s == null or s.objects == null:
		return
	if source != null and is_instance_valid(source) and not owns(source):
		return
	s.objects.request_shove(target, dir, distance, source)


## A modifier on something this machine does not own (Actor.set_modifier on a copy): a request to its owner.
static func route_modifier(target: Actor, id: String, mult: float, duration: float, stat: String) -> void:
	var s := session()
	if s != null and s.objects != null:
		s.objects.request_modifier(target, id, mult, duration, stat)


## A host-owned object (a priced prop, a crate, a mail box) was hit by something this machine moves: a hero it owns that
## was shoved into it (the slider's owner sees the contact). The culprit is whoever caused the shove, even when another
## machine runs that actor, so this skips route_hit's "a copy never acts" check: the decision is this machine's.
static func hit_object(obj: Actor, amount: float, culprit: Node) -> void:
	if owns(obj):
		obj.apply_damage(amount, culprit)
		return
	var s := session()
	if s != null and s.objects != null and routes_hits(obj):
		s.objects.request_hit(obj, amount, culprit)


# --- Combat across owners (M4, layer 4): who applies what ---------------------------------------------------------------
# Effects (a cast, a swing, a monster's strike) may run on every machine; each machine applies only what it RESOLVES.

## Statuses (a modifier, a heal, a soak, a fire, coffee): the target's owner applies them. A hero's player, the host for
## everything else; everything offline.
static func resolves(target: Object) -> bool:
	return target != null and owns(target)


## Hits (damage, a shove): a hero is decided by its owner (the victim decides, rule 1); anything else by the attacker's
## machine, the owner of `source` (rule 2: a client's hit on the host's monster then travels as a request, route_hit); the
## host when the source is unknown or gone. Offline, everything.
static func resolves_hit(target: Object, source: Object) -> bool:
	if target is Hero:
		return owns(target)
	if source != null and is_instance_valid(source):
		return owns(source)
	return is_host()


# --- Casts and hero actions as events (M4a) -------------------------------------------------------------------------------

## True when a cast from `caster` travels as an event (a crewed floor, and the caster is this machine's hero): it lands
## NetCasts.LEAD seconds from now on every machine. False offline and solo: the cast lands at once, as ever.
static func shares_cast(caster: Node) -> bool:
	var s := session()
	return s != null and s.casts != null and s.casts.shares(caster)


## Send a cast (NetCasts): `spec` is SpellBook's cast description (spell, power, target, follow, extra).
static func send_cast(caster: Actor, spec: Dictionary) -> void:
	var s := session()
	if s != null and s.casts != null:
		s.casts.send_cast(caster, spec)


## A hero this machine owns attacked (melee, an arrow, a bolt, the bowl, the spin): the other screens replay it on its
## puppet (the swing shows, and each machine resolves its own heroes against it).
static func hero_acted(hero: Hero, kind: String, dir: Vector3, drawn: bool = false) -> void:
	var s := session()
	if s != null and s.casts != null:
		s.casts.acted(hero, kind, dir, drawn)


## A status of an actor this machine owns changed ("mods", "burn", "soak"): the other screens are told (NetStatus).
static func status_changed(a: Node, kind: String) -> void:
	var s := session()
	if s != null and s.status != null:
		s.status.changed(a, kind)


## This machine's hero took a hit (telemetry's `hits` column and, M7, the hits-per-player-per-minute sheet: how much, and
## what dealt it).
static func note_hit(a: Node, dealt: float = 0.0, source: Node = null) -> void:
	var s := session()
	if s != null and s.online() and owns(a):
		s.note_hit(a, dealt, source)


## The recognizer behind the cast about to be made (M7, the casts sheet): `info` is VoiceCaster's cast detail (latency_ms,
## speech_ms, typed, accidental). The cast event that follows on this machine carries its onset and recognition latency.
static func note_voice(spell: String, info: Dictionary) -> void:
	var s := session()
	if s != null and s.casts != null and s.online():
		s.casts.note_voice(spell, info)


# --- Runtime guard (M4c, layer 5) -----------------------------------------------------------------------------------------
# A copy's OWNER fields are written only by the net layer applying what the owner sent. Anything else that writes one is
# a machine deciding something it does not own: a silent desync. In debug builds it raises a script error (which fails
# every test); `guard_capture` (a test seam) records it instead, so a negative test can see it fire.

static var _applying := 0
## Test seam: record violations in guard_hits instead of raising.
static var guard_capture := false
## Every violation seen in this process (the message).
static var guard_hits: Array[String] = []


## The net layer starts / stops applying an owner's state to copies (events, snapshots, the world stream).
static func apply_begin() -> void:
	_applying += 1


static func apply_end() -> void:
	_applying = maxi(0, _applying - 1)


static func applying() -> bool:
	return _applying > 0


## Called by the guarded setters (Actor.hp, Actor.dead) of a copy.
static func guard_write(node: Object, field: String) -> void:
	if _applying > 0 or not is_copy(node) or not OS.is_debug_build() or not online():
		return   # (offline a copy only exists in a single-process test standing in for the net layer)
	var label := str(node.get("display_name")) if node.get("display_name") != null else str(node)
	var msg := "[Net] OWNER write on a non-owner: %s.%s (net id %d). Only its owner writes it; use a verb." % [label, field, NetFloor.id_of(node as Node)]
	guard_hits.append(msg)
	if guard_capture:
		print(msg)
		return
	push_error(msg)
	assert(false, msg)


## A client asks the host about something the host owns ("collect" / "swap" a pickup, "follow" / "wait" an employee).
## True when the request was sent (the answer comes back as an event). False offline and on the host.
static func request(node: Node, what: String, data: Dictionary = {}) -> bool:
	var s := session()
	return s != null and s.objects != null and s.objects.request(node, what, data)


## A voice order heard on this machine (VoiceOrders.give): on a crewed, running floor it goes to the host (NetOrders), which
## applies it and shows it on every screen; true when it went. False offline / alone: apply it here.
static func send_order(who: String, kind: String, speaker: Hero, point: Vector3) -> bool:
	var s := session()
	return s != null and s.orders != null and s.orders.send(who, kind, speaker, point)


## True on a client while a shared floor runs: things it would create or change that the host owns are requests.
static func world_live() -> bool:
	var s := session()
	return s != null and s.objects != null and s.objects.client_live()


## A client puts a pickup down (the spell a swap pushed out of its slot): the host drops it.
static func request_drop(spell: String, amount: int, pos: Vector3, life: float) -> void:
	var s := session()
	if s != null and s.objects != null:
		s.objects.request_drop(spell, amount, pos, life)


## A runtime object this machine made as the host (NetObjects.RUNTIME_OBJECTS: a goo imp's ball, a goo patch): on a shared
## floor it gets a net id and every client builds its copy (NetObjects.adopt: obj.new). Offline, solo or on a client:
## nothing (0). Returns its id.
static func announce(node: Node) -> int:
	var s := session()
	return s.objects.adopt(node) if s != null and s.objects != null else 0


## Where a monster should aim at `target` (M3a, networking.md "Monsters chasing non-host players"): a remote player's
## hero is where its newest snapshot says plus its velocity for that snapshot's age, not the ~100 ms old puppet the host
## draws. Everything else (and everything offline) is where it stands.
static func lead_point(target: Node3D) -> Vector3:
	if target == null:
		return Vector3.INF
	var s := session()
	if s == null or s.snap == null or not is_puppet(target) or not (target is Hero):
		return target.global_position
	var p := s.snap.lead_point(NetFloor.id_of(target))
	return target.global_position if p == Vector3.INF else p


## What to call a hero on screen: the player's roster name for a seat a person plays, else the hero's own name.
static func label_of(hero: Actor) -> String:
	return str(hero.get_meta(NAME_META, hero.display_name))


## The Session autoload, or null (a bare test tree without autoloads).
static func session() -> NetSession:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Session") as NetSession

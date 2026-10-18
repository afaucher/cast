class_name Net
## Authority classes for networked state (docs/design/networking.md, "Keeping authority straight").
##
## Every class whose state matters in co-op returns `net_fields() -> {var name: Net.KIND}` covering
## EVERY script var it has, and test_net_contract fails when a var is missing or a name is stale. The
## snapshot packer and the debug write guards will be driven by the same declarations.
##
## It is also the facade gameplay code asks (it never sends anything itself; that is scripts/net/):
## `Net.is_host()`, `Net.online()`, `Net.owns(node)`, `Net.is_puppet(node)`. The transport is the Session autoload
## (NetSession, M0); `request()` arrives with the host-owned world (M3).
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
## whatever is not a copy of somebody else's. (M3 extends this to the host-owned world.)
static func owns(node: Object) -> bool:
	return simulates(node)


## What to call a hero on screen: the player's roster name for a seat a person plays, else the hero's own name.
static func label_of(hero: Actor) -> String:
	return str(hero.get_meta(NAME_META, hero.display_name))


## The Session autoload, or null (a bare test tree without autoloads).
static func session() -> NetSession:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Session") as NetSession

class_name NetRegistry
extends RefCounted
## The id -> node registry (docs/design/networking-build-plan.md M2; M3's snapshots and events reuse it).
##
## Every networked actor has a net id (the meta "net_id", set by NetFloor.assign_ids): heroes 1-3 by seat, the
## seed-built actors from NetFloor.ID_BASE in build order, and runtime spawns (M3) from RUNTIME_BASE up, handed out
## by the host. Messages name things by id; this is how a receiver finds the node. One registry per process (a
## floor is one scene at a time): NetFloor.assign_ids clears it and fills it, runtime spawns register themselves.
##
## A lookup never returns a freed node: it checks the instance, so a message that names something already gone
## (a monster that died while the packet was in flight) finds null instead of crashing.

const RUNTIME_BASE := 10000

static var _nodes: Dictionary = {}       ## id -> Node
static var _next_runtime := RUNTIME_BASE


## Forget everything (a new floor).
static func clear() -> void:
	_nodes.clear()
	_next_runtime = RUNTIME_BASE


## Register `node` under `id` (also stamps its meta). Replaces whatever held the id.
static func register(id: int, node: Node) -> void:
	node.set_meta(NetFloor.ID_META, id)
	_nodes[id] = node


static func unregister(id: int) -> void:
	_nodes.erase(id)


## The node with this id, or null (unknown, or already freed).
static func node(id: int) -> Node:
	var n: Variant = _nodes.get(id)
	if n == null or not is_instance_valid(n):
		_nodes.erase(id)
		return null
	return n as Node


## The hero node in this seat (heroes' ids are their seats), or null.
static func hero(seat: int) -> Hero:
	return node(seat) as Hero


## The id of `node`, 0 when it has none.
static func id_of(n: Node) -> int:
	return NetFloor.id_of(n)


static func has_id(id: int) -> bool:
	return node(id) != null


## The next id for a runtime spawn. M3: the HOST hands these out and sends them in the spawn event; a client never
## calls this for something it did not see the host announce.
static func next_runtime_id() -> int:
	var id := _next_runtime
	_next_runtime += 1
	return id


## Every live id, ascending.
static func ids() -> Array[int]:
	var out: Array[int] = []
	for k: int in _nodes.keys():
		if node(k) != null:
			out.append(k)
	out.sort()
	return out


static func size() -> int:
	return ids().size()

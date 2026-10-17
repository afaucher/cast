class_name HellgateEvents
extends RefCounted
## The hellgate event hub: how the contract flow (agent A) hears about gates closing, and the
## site-wide "gate spawns are stopped" flag.
##
## GDScript has no static signals, so the signals live on one small Node (`Hub`) that hangs off the
## GameWorld autoload and is created on first use:
##
##   HellgateEvents.hub().gate_closed.connect(func(gate: Actor) -> void: ...)     # every gate, once
##   HellgateEvents.hub().origin_closed.connect(func(gate: Actor) -> void: ...)   # the origin gate only
##   HellgateEvents.hub().spawns_stopped.connect(func() -> void: ...)             # the flag below flipped
##   HellgateEvents.on_origin_closed(callable)                                    # same, shorter
##
## The gate argument is always a Hellgate (typed Actor here so this file never has to name Hellgate).
## Each gate also has its own `closed(gate)` signal, and GameWorld.actor_died fires as usual.
##
## SPAWNS STOPPED FLAG. Closing the origin gate calls HellgateEvents.stop_spawns() (also reachable as
## Hellgate.close_all_spawns()): every gate, live or created later, then refuses to spawn. The flag is
## remembered together with the id of the current GameWorld.root, so building a new floor or a new
## world (a new root node) clears it by itself. Call HellgateEvents.reset() to clear it by hand
## (a new contract that reuses the same root, a test).


## The signal holder. Never instantiate it yourself: HellgateEvents.hub().
class Hub extends Node:
	## A gate was closed (killed). Fires once per gate, before its collapse animation ends.
	signal gate_closed(gate: Actor)
	## The origin gate was closed. Fires right after gate_closed for that gate, with spawns already stopped.
	signal origin_closed(gate: Actor)
	## stop_spawns() flipped the flag from off to on.
	signal spawns_stopped

	var stopped_root_id := 0       ## instance id of the GameWorld.root the stop applies to (0 = none)


const HUB_NAME := "HellgateHub"


## The hub node (created and parented to the GameWorld autoload on first use).
static func hub() -> Hub:
	var found := GameWorld.get_node_or_null(HUB_NAME) as Hub
	if found != null:
		return found
	var h := Hub.new()
	h.name = HUB_NAME
	GameWorld.add_child(h)
	return h


static func on_gate_closed(callback: Callable) -> void:
	hub().gate_closed.connect(callback)


static func on_origin_closed(callback: Callable) -> void:
	hub().origin_closed.connect(callback)


## True while gate spawning is switched off for the current world.
static func spawns_are_stopped() -> bool:
	if GameWorld.root == null:
		return false
	return hub().stopped_root_id == GameWorld.root.get_instance_id()


## Switch gate spawning off for the current world (the origin gate does this when it closes).
static func stop_spawns() -> void:
	if GameWorld.root == null:
		return
	var h := hub()
	var id := GameWorld.root.get_instance_id()
	if h.stopped_root_id == id:
		return
	h.stopped_root_id = id
	h.spawns_stopped.emit()


## Clear the flag (a new contract that reuses the same world root, a test).
static func reset() -> void:
	hub().stopped_root_id = 0


## Called by a gate when it closes.
static func announce_closed(gate: Actor, is_origin: bool) -> void:
	var h := hub()
	h.gate_closed.emit(gate)
	if is_origin:
		h.origin_closed.emit(gate)

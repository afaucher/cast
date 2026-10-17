class_name SitePlan
extends RefCounted
## Where everything goes on one floor of a contract: pure data (cells and numbers), produced by
## SiteBuilder.plan() from a HexMap + ContractRun and consumed by SiteBuilder.spawn(). No nodes, so it
## is deterministic per (run, floor) and can be checked without a running game.

var floor_number := 1
var start := Vector2i.ZERO
var exit := Vector2i.ZERO
var start_room := ""
var exit_room := ""
var origin_room := ""                  ## the room holding the origin gate (floor 3 only)
## "room:<n>" -> cells (sorted), its centre cell, and its modal ground level.
var rooms: Dictionary = {}
var centers: Dictionary = {}
var base_levels: Dictionary = {}
## {cell: Vector2i, origin: bool, room: String}
var gates: Array[Dictionary] = []
## {cell: Vector2i, name: String, style: String, room: String}
var employees: Array[Dictionary] = []
## {cell: Vector2i, kind: String, room: String}
var props: Array[Dictionary] = []
## {cell: Vector2i, text: String}
var notes: Array[Dictionary] = []
## Rooms ordered by distance from the nearest gate, farthest first (start room left out).
var ranked_rooms: Array[String] = []
## Monster pack budget per room tag (the start room has none).
var pack_budgets: Dictionary = {}
## Cells monsters must not be placed on (gates, props, employees and a margin around them).
var blocked: Dictionary = {}


func small_gate_count() -> int:
	var n := 0
	for g in gates:
		if not bool(g["origin"]):
			n += 1
	return n


func has_origin() -> bool:
	for g in gates:
		if bool(g["origin"]):
			return true
	return false


func gate_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for g in gates:
		out.append(g["cell"])
	return out


func room_of_cell(c: Vector2i) -> String:
	for tag: String in rooms:
		if (rooms[tag] as Array[Vector2i]).has(c):
			return tag
	return ""

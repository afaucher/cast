class_name SitePlan
extends RefCounted
## Where everything goes on one floor of a contract: pure data (cells and numbers), produced by
## SiteBuilder.plan() from a HexMap + ContractRun and consumed by SiteBuilder.spawn(). No nodes, so it
## is deterministic per (run, floor) and can be checked without a running game.
##
## ROOM THEMES (scripts/world/themes/, docs/design/environment.md). Every room has a theme:
##   room_themes: Dictionary   room tag ("room:3") -> theme id (String), for EVERY room of the floor.
##     Ids: bunker  wine_cellar, home_cinema, spa, gym, server_room, panic_room, pool
##          lair    torture_chamber, throne_room, lab, barracks, moat
##          both    service_entrance (the start room: hazard tape, a WET FLOOR sign)
##     On the origin floor (3) the origin room's theme is the one the story names (RoomThemeDefs.ORIGIN_THEMES:
##     "yoga studio" -> spa, "vat room" -> lab, ...). Read it with theme_of(tag) / rooms_with_theme(id); names
##     via RoomThemeDefs.theme_name(id). The grime layer reads this to pick theme-specific marks (wine splats
##     in the cellar, scorch in the torture chamber, ...). The ids are stable; new themes only get added.
##   decor / lights / entrances / decor_report: the placed set dressing, the per-room accent lights, each
##     room's main door (world X/Z), and which recipe ops placed (diagnostics).
## Placements (priced props and decor) carry pos (world X/Z, Vector2), yaw (degrees; front = +Z, so the
## facing vector is (sin yaw, cos yaw)), the rule that placed them (wall / corner / center / floor / group /
## ring) and the rule that oriented them (away_from_wall / face_center / face_entrance / face_target / ...).

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
## Priced props: {cell: Vector2i, kind: String, room: String, pos: Vector2, yaw: float, place: String,
## orient: String, foot: Vector2}. `cell` is the wall-adjacent cell the prop stands in.
var props: Array[Dictionary] = []
## Room tag -> theme id (see the header). Includes the start room ("service_entrance").
var room_themes: Dictionary = {}
## Decor (not priced, purely decorative): {kind, pos: Vector2, yaw, cell, room, place, orient, group (-1 = alone),
## role, blocks (walk-blocking), w, d (footprint), lift, target (Vector2, what it faces), params, block_points,
## block_radius}. Group members (a table and its chairs, a screen and its recliners) share a group id.
var decor: Array[Dictionary] = []
## One accent light per themed room: {room, theme, pos: Vector3, color, energy, range, flicker, pulse}.
var lights: Array[Dictionary] = []
## Room tag -> world X/Z (Vector2) of its main door (the door cell nearest the start).
var entrances: Dictionary = {}
## {room, theme, op, ok} for every recipe op the themer ran (diagnostics, tests).
var decor_report: Array[Dictionary] = []
## {cell: Vector2i, text: String}
var notes: Array[Dictionary] = []
## Rooms ordered by distance from the nearest gate, farthest first (start room left out).
var ranked_rooms: Array[String] = []
## Monster pack budget per room tag (the start room has none).
var pack_budgets: Dictionary = {}
## Cells monsters must not be placed on (gates, props, walk-blocking decor, employees and a margin around them).
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


## The theme id of a room tag ("" if unknown).
func theme_of(tag: String) -> String:
	return str(room_themes.get(tag, ""))


## Room tags that have this theme, in room order.
func rooms_with_theme(theme_id: String) -> Array[String]:
	var out: Array[String] = []
	var tags: Array = room_themes.keys()
	tags.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("room:")) < int(b.trim_prefix("room:")))
	for tag: String in tags:
		if str(room_themes[tag]) == theme_id:
			out.append(tag)
	return out


func room_of_cell(c: Vector2i) -> String:
	for tag: String in rooms:
		if (rooms[tag] as Array[Vector2i]).has(c):
			return tag
	return ""

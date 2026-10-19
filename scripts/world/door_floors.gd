class_name DoorFloors
extends RefCounted
## The floor at a doorway, three ways (the fog lab's options; not used by the game yet). Floors are per hex cell
## (Cell.mat_id, FloorMaterials): today every cell takes its tag's floor, so the room / corridor seam runs along the hex
## edges between the room's door cells and the hall's mouth cells, zigzagging across the door line (Doorways' jamb chord).
##   "a"  today: nothing changes.
##   "b"  split on the door line: every room or hall cell near the doorway takes the room's floor if its centre is on the
##        room side of the chord, the corridor's if on the hall side. Still per cell, so the seam is the hex zigzag that
##        follows the chord most closely (a straight seam would need the terrain shader to split a cell).
##   "c"  a threshold: the cells the chord passes through get their own floor (`threshold`, e.g. diamond tread plate);
##        room floor on the room side of them, corridor floor on the hall side.
## Only the floor id changes (the wall id of each cell is kept). Pure and deterministic: a function of the map and the
## doorway, so it could be part of the floor plan (FloorMaterials.assign) and its checksum.

const REACH := 3                 ## cells this close to the doorway cell (or to the chord's middle) are looked at
const STEP := 0.08               ## the chord is sampled this finely to find the cells it crosses


## Re-floor around doorway `dw` (Doorways.find, with a door line). Returns how many cells changed.
static func apply(map: HexMap, fog: RoomFog, dw: Dictionary, option: String, threshold: int = FloorMaterials.F_DIAMOND) -> int:
	if option == "a" or not dw.has("a"):
		return 0
	var a: Vector2 = dw["a"]
	var b: Vector2 = dw["b"]
	var mid := (a + b) * 0.5
	var t := (b - a).normalized()
	var n := Vector2(-t.y, t.x)
	var axis: Vector3 = dw["axis"]
	if n.dot(Vector2(axis.x, axis.z)) < 0.0:
		n = -n   # (toward the hall)
	var room := fog.index_of(str(dw["room"]))
	var hall := fog.index_of(str(dw["hall"]))
	var room_floor := FloorMaterials.floor_of(map.get_cell((dw["door_cells"] as Array)[0]).mat_id)
	var hall_floor := FloorMaterials.floor_of(map.get_cell((dw["mouth_cells"] as Array)[0]).mat_id)
	var cross := {}
	if option == "c":
		var len := a.distance_to(b)
		var s := 0.05
		while s <= len - 0.05:
			var p := a + t * s
			var c := Hex.from_world(Vector3(p.x, 0.0, p.y))
			var cell: HexMap.Cell = map.get_cell(c)
			if cell != null and cell.type != HexMap.Tile.WALL and not map.wall_at(Vector3(p.x, 0.0, p.y)):
				cross[c] = true
			s += STEP
	var near := {}
	for c in Hex.range_cells(Hex.from_world(Vector3(mid.x, 0.0, mid.y)), REACH):
		near[c] = true
	if dw.has("cell"):
		for c in Hex.range_cells(dw["cell"], REACH):
			near[c] = true
	var changed := 0
	for c: Vector2i in near:
		var cell: HexMap.Cell = map.get_cell(c)
		if cell == null or cell.type == HexMap.Tile.WALL:
			continue
		var sp := fog.space_of_cell(c)
		if sp != room and sp != hall:
			continue
		var w := Hex.to_world(c)
		var side := (Vector2(w.x, w.z) - mid).dot(n)
		var f := threshold if cross.has(c) else (room_floor if side <= 0.01 else hall_floor)
		var id := FloorMaterials.pack(f, FloorMaterials.wall_of(cell.mat_id))
		if id != cell.mat_id:
			cell.mat_id = id
			changed += 1
	return changed

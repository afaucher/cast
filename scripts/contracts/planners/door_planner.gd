class_name DoorPlanner
extends RefCounted
## The office doors of a floor: plan() picks the doorways (SitePlan.doors) and lays their thresholds, spawn() puts the
## doors into the world, shut. SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


## Which doorways get an office door (DoorPlan: every narrow doorway but dead ends and the start / elevator rooms) and the
## diamond tread-plate threshold on the cells their door line crosses (DoorFloors; open archways keep their floors).
## A SEWER CLUSTER's flooded narrow halls (docs/design/sewer-concept.md, "Phase 3 as built"): both their doorways get a
## SLUICE GATE (SewerPlanner.sluice: the decor kind "sluice", whatever its look is, standing across the doorway with the water
## running under it) and never an office door; nothing changes on a floor without a cluster.
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var sp := Doorways.spaces(map)
	var dws := Doorways.find(map, sp)
	var sluiced := _sluiced(map, dws)
	for id in DoorPlan.choose(dws, p, run.floor_seed(floor_n)):
		if sluiced.has(id):
			continue
		var dw: Dictionary = dws[id]
		var rec := {"style": OfficeDoor.DEFAULT_STYLE}
		for k in ["id", "room", "hall", "axis", "cell", "band", "a", "b", "center", "door_cells", "mouth_cells", "door_ok"]:
			rec[k] = dw[k]
		p.doors.append(rec)
		DoorFloors.for_doorway(map, sp, dw, true)
	for id: int in sluiced:
		SewerPlanner.sluice(map, p, dws[id])


## The doorways of a sewer cluster's flooded narrow halls (narrow, water in their door or mouth cells), in doorway order.
static func _sluiced(map: HexMap, dws: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	if SewerPlanner.record(map).is_empty():
		return out
	for dw in dws:
		if not bool(dw.get("narrow", false)):
			continue
		for c: Vector2i in (dw["door_cells"] as Array) + (dw["mouth_cells"] as Array):
			var cell: HexMap.Cell = map.get_cell(c)
			if cell != null and cell.pool_mask == HexMap.ALL_KITES & ~cell.wall_mask and cell.pool_mask != 0:
				out.append(int(dw["id"]))
				break
	return out


## The planned doors, shut (user, 2026-10-19), in plan order.
static func spawn(p: SitePlan, site: SiteBuilder.Site) -> void:
	for dr in p.doors:
		var door := OfficeDoor.spawn(dr, str(dr.get("style", OfficeDoor.DEFAULT_STYLE)), true)
		if door != null:
			site.doors.append(door)

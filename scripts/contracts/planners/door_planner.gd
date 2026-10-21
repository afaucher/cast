class_name DoorPlanner
extends RefCounted
## The office doors of a floor: plan() picks the doorways (SitePlan.doors) and lays their thresholds, spawn() puts the
## doors into the world, shut. SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


## Which doorways get an office door (DoorPlan: every narrow doorway but dead ends and the start / elevator rooms) and the
## diamond tread-plate threshold on the cells their door line crosses (DoorFloors; open archways keep their floors).
## A SEWER CLUSTER's flooded narrow halls (docs/design/sewer-concept.md, "Phase 3 as built"): both their doorways get a
## SLUICE GATE (SewerPlanner.sluice: the decor kind "sluice", whatever its look is, standing across the doorway with the water
## running under it) and never an office door; nothing changes on a floor without a cluster.
## The SERVICE STAIR's head (the narrow stair down into the cluster, docs/design/sewer-concept.md "Polish as built") always
## gets a door in the "service" style (OfficeDoorModel.SERVICE: hazard stripes and a SERVICE LEVEL stencil), even in the start
## or the elevator room, where DoorPlan puts none: it marks the way down. Only its look differs from any office door.
## (The user, 2026-10-21: yes, on every stair head, the start and elevator rooms included.)
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var sp := Doorways.spaces(map)
	var dws := Doorways.find(map, sp)
	var sluiced := _sluiced(map, dws)
	var head := service_head(map, dws)
	var ids := DoorPlan.choose(dws, p, run.floor_seed(floor_n))
	if head >= 0 and not ids.has(head):
		ids.append(head)
		ids.sort()
	for id in ids:
		if sluiced.has(id):
			continue
		if LavaPlanner.doorway(map, dws[id]):
			continue   # (a lava cave's doorways are openings: LavaPlanner)
		var dw: Dictionary = dws[id]
		var rec := {"style": OfficeDoorModel.SERVICE if id == head else OfficeDoor.DEFAULT_STYLE}
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


## The doorway at the head of the sewer cluster's service stair (in the room above, on the stair's hall) when it has a door
## place (narrow, door_ok), else -1. -1 on a floor without a cluster.
static func service_head(map: HexMap, dws: Array[Dictionary]) -> int:
	var rec := SewerPlanner.record(map)
	if rec.is_empty() or (rec["stair"] as Dictionary).is_empty():
		return -1
	var st: Dictionary = rec["stair"]
	var up: Vector2i = st["door_up"]
	for dw in dws:
		if str(dw["room"]) == str(st["from"]) and (dw["door_cells"] as Array).has(up):
			return int(dw["id"]) if bool(dw.get("narrow", false)) and bool(dw.get("door_ok", false)) else -1
	return -1


## The planned doors, shut (user, 2026-10-19), in plan order.
static func spawn(p: SitePlan, site: SiteBuilder.Site) -> void:
	for dr in p.doors:
		var door := OfficeDoor.spawn(dr, str(dr.get("style", OfficeDoor.DEFAULT_STYLE)), true)
		if door != null:
			site.doors.append(door)

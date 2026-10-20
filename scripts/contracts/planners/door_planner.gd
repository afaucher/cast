class_name DoorPlanner
extends RefCounted
## The office doors of a floor: plan() picks the doorways (SitePlan.doors) and lays their thresholds, spawn() puts the
## doors into the world, shut. SiteBuilder.plan / spawn call them; moved out of SiteBuilder verbatim (refactor plan H8).


## Which doorways get an office door (DoorPlan: every narrow doorway but dead ends and the start / elevator rooms) and the
## diamond tread-plate threshold on the cells their door line crosses (DoorFloors; open archways keep their floors).
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	var sp := Doorways.spaces(map)
	var dws := Doorways.find(map, sp)
	for id in DoorPlan.choose(dws, p, run.floor_seed(floor_n)):
		var dw: Dictionary = dws[id]
		var rec := {"style": OfficeDoor.DEFAULT_STYLE}
		for k in ["id", "room", "hall", "axis", "cell", "band", "a", "b", "center", "door_cells", "mouth_cells", "door_ok"]:
			rec[k] = dw[k]
		p.doors.append(rec)
		DoorFloors.for_doorway(map, sp, dw, true)


## The planned doors, shut (user, 2026-10-19), in plan order.
static func spawn(p: SitePlan, site: SiteBuilder.Site) -> void:
	for dr in p.doors:
		var door := OfficeDoor.spawn(dr, str(dr.get("style", OfficeDoor.DEFAULT_STYLE)), true)
		if door != null:
			site.doors.append(door)

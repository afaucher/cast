class_name LavaPlanner
extends RefCounted
## A floor's LAVA CAVE in the site plan (docs/design/lava-playtest.md, "As built: caves on real floors"; the cave itself is
## DungeonGen's "cave" option, CaveGen, HexMap.cave). Every step returns at once on a floor without one, so those floors are
## planned exactly as before. Called from SiteBuilder.plan / spawn, in this order:
##   gate_room(map)   GatePlanner: the room the floor's first hellgate must go in (a GATE cave's far chamber; LavaSite)
##   theme(map, p)    after the themes are dealt: the chambers are "lava" rooms (RoomThemeDefs.LAVA), and the cave's LOOK is
##                    chosen: HELLFIRE when a hellgate stands in one of its chambers, else MAGMA (map.cave["look"])
##   materials(map,p) after FloorMaterials.assign: basalt on all the cave's rock and lava, its rim walls basalt
##   doorway(map, dw) DoorPlanner: a doorway onto a cave chamber is an opening, never an office door
##   plan(map, ...)   last: its spawn data (map.cave["archers"]: ARCHERS on the isles) and its PACKS AT THE BRIDGEHEADS (each
##                    chamber's pack, but the entry chamber's, kept to PACK_REACH of the landing of the bridge it is entered
##                    by: SitePlan.blocked; the entry chamber has no pack: its isle's archers cover it)
##   spawn(map, ...)  after the sewer's actors: the archers (the floor's last actors, so no earlier net id moves), the look
##                    (LavaLook.dress_cave: the lava, its glow, embers and lights) and the rules (LavaField, activated by the
##                    game once the fog has read the map)
## No dice: everything follows from the cave's record.

const THEME := RoomThemeDefs.LAVA
const PACK_REACH := 4
const ARCHERS_FIRST := 2           ## archers on the first isle; one on each other

static var last_usec := 0


static func record(map: HexMap) -> Dictionary:
	return map.cave


## The room the floor's first hellgate goes in ("" when the floor has no GATE cave).
static func gate_room(map: HexMap) -> String:
	if map.cave.is_empty() or not bool(map.cave.get("gate", false)):
		return ""
	return str(map.cave.get("far", ""))


## The cave's chambers are lava rooms; the look follows the gates.
static func theme(map: HexMap, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty() or not rec.has("chambers"):
		return
	var rooms: Array = rec["rooms"]
	for t: String in rooms:
		p.room_themes[t] = THEME
	var hell := false
	for g in p.gates:
		hell = hell or rooms.has(str(g["room"]))
	rec["look"] = "hellfire" if hell else "magma"
	rec["cliff"] = look_row(map)["cliff"]


## The look's row (RoomThemeDefs "lava" -> "lava" -> magma | hellfire).
static func look_row(map: HexMap) -> Dictionary:
	var looks: Dictionary = RoomThemeDefs.theme(THEME)["lava"]
	return looks.get(str(map.cave.get("look", "magma")), looks["magma"])


## Basalt on every cell of the cave (its rock, its walkways, its isles and its lava) and on the rim walls round it.
static func materials(map: HexMap, p: SitePlan) -> void:
	var rec := record(map)
	if rec.is_empty() or not rec.has("chambers"):
		return
	var mat := FloorMaterials.pack(int(look_row(map)["floor_mat"]), FloorMaterials.W_BASALT)
	for key in ["rock", "lava"]:
		for c: Vector2i in (rec[key] as Array):
			var cell: HexMap.Cell = map.get_cell(c)
			if cell != null:
				cell.mat_id = mat
	for c: Vector2i in (rec["lava"] as Array):
		for nn in Hex.neighbors(c):
			var w: HexMap.Cell = map.get_cell(nn)
			if w != null and w.type == HexMap.Tile.WALL:
				w.mat_id = mat


## Is this doorway (Doorways.find) one of the cave's (a bridge's end, a span's, the neck): an opening with no door?
static func doorway(map: HexMap, dw: Dictionary) -> bool:
	var rec := record(map)
	return not rec.is_empty() and (rec.get("rooms", []) as Array).has(str(dw.get("room", "")))


## The cave's spawn data and its packs (see the header). Last in SiteBuilder.plan.
static func plan(map: HexMap, run: ContractRun, floor_n: int, p: SitePlan) -> void:
	last_usec = 0
	var rec := record(map)
	if rec.is_empty() or not rec.has("chambers"):
		return
	var t0 := Time.get_ticks_usec()
	# archers on the isles: the isle's top first, then the cell nearest its shore
	var archers: Array = []
	for i in (rec["isles"] as Array).size():
		var isle: Dictionary = rec["isles"][i]
		var cells: Array = (isle["cells"] as Array).duplicate()
		var shore: Vector2i = isle["shore"]
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := Hex.distance(a, shore)
			var db := Hex.distance(b, shore)
			return da < db or (da == db and SiteBuilder._cell_less(a, b)))
		archers.append(isle["center"])
		if i == 0 and ARCHERS_FIRST > 1:
			for c: Vector2i in cells:
				if c != isle["center"]:
					archers.append(c)
					break
	rec["archers"] = archers
	# the packs: none in the entry chamber, the others' at the landing of the way in
	var rooms: Array = rec["rooms"]
	var entry := str((rec["entry"] as Dictionary)["room"])
	p.pack_budgets.erase(entry)
	for ri in range(1, rooms.size()):
		var tag := str(rooms[ri])
		if not p.pack_budgets.has(tag) or not p.rooms.has(tag):
			continue
		var landing: Array = []
		for br: Dictionary in rec["bridges"]:
			var a := str(br["a"])
			var b := str(br["b"])
			var other := a if b == tag else (b if a == tag else "")
			if other == "" or rooms.find(other) >= ri:
				continue
			var rows: Array = br["rows"]
			landing.append_array(rows[rows.size() - 1] if b == tag else rows[0])
		if landing.is_empty():
			continue
		for c: Vector2i in (p.rooms[tag] as Array):
			var near := false
			for l: Vector2i in landing:
				near = near or Hex.distance(c, l) <= PACK_REACH
			if not near:
				p.blocked[c] = true
	last_usec = Time.get_ticks_usec() - t0


## The cave in the world: its archers (the floor's last actors), its look and its rules (activated by the game after the fog).
static func spawn(map: HexMap, run: ContractRun, p: SitePlan, site: SiteBuilder.Site) -> void:
	var rec := record(map)
	if rec.is_empty() or not rec.has("chambers") or GameWorld.root == null:
		return
	for c: Vector2i in (rec.get("archers", []) as Array):
		var m := MonsterFactory.spawn("archer", c)
		if m == null:
			continue
		site.monsters.append(m)
		site.lava_archers.append(m)
		if run.pest == "everything" or run.pest == "archer":
			site.pest_spawned += 1
	var host := GameWorld.root.get_parent()
	if host != null:
		site.lava_look = LavaLook.dress_cave(host, map, look_row(map))
	var field := LavaField.new()
	field.name = "LavaField"
	GameWorld.root.add_child(field)
	field.setup(map)
	site.lava_field = field

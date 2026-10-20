class_name FloorMaterials
extends RefCounted
## Floor and wall MATERIALS per room theme (docs/design/environment.md, "Materials").
##
## Cell.mat_id packs two small ids: the FLOOR material (bits 0-7: what the top of the hex is made of) and the WALL
## material (bits 8-15: what its cut wall faces and caps are made of). 0 / 0 is the classic dark slate, so a map nobody
## assigned (menu garage, labs, most tests) looks exactly as before. assign() writes it for every cell of a floor from the
## room themes (SitePlan.room_themes) and the site type; the data is a pure function of the plan, so it is SPAWN data that
## every machine derives from the same seed (HexMap.net_fields lists the cells as SPAWN).
##
## HexMapView reads the id per cell into a vertex attribute (UV2.y) and the terrain shader turns it into a procedural
## pattern (planks, tiles, diamond tread, ...): no textures, one draw call per surface as before. The table below is the
## single source of the look; table_arrays() feeds the shader its uniform arrays.
##
## "seam" is how strongly the glowing amber seams and bevel glow of a floor read on that material (1 = the classic look):
## carpet and wood dim them, tile and diamond plate keep them bright.

enum Pat { NONE, CONCRETE, FLAGSTONE, CARPET, TILE, WOOD, MARBLE, RUBBER, DIAMOND, FORM_CONCRETE = 20, ASHLAR, PANELLING, MARBLE_WALL }

# Floor ids (bits 0-7 of mat_id).
const F_SLATE := 0
const F_CONCRETE := 1
const F_FLAGSTONE := 2
const F_CARPET := 3
const F_TILE := 4
const F_POOL_TILE := 5
const F_WOOD := 6
const F_MARBLE := 7
const F_RUBBER := 8
const F_DIAMOND := 9
const F_DIAMOND_DARK := 10
const F_LAB_TILE := 11
const F_CORR_CONCRETE := 12
const F_CORR_STONE := 13

# Wall ids (bits 8-15 of mat_id).
const W_CONCRETE := 1
const W_STONE := 2
const W_PANELLING := 3
const W_MARBLE := 4

const WALL_OFFSET := 16     ## shader table index of wall id 0; floors use their own id
const TABLE_SIZE := 32

## id (index) -> {name, pat, base (sRGB), alt (sRGB: grout / joints / veins / highlights), scale (pattern size in world
## units), rough, spec, seam}. Floors first, walls from WALL_OFFSET.
const FLOORS: Array[Dictionary] = [
	{"name": "slate", "pat": Pat.NONE, "base": Color(0.235, 0.285, 0.375), "alt": Color(0.1, 0.1, 0.12), "scale": 4.0, "rough": 0.78, "spec": 0.22, "seam": 1.0},
	{"name": "concrete", "pat": Pat.CONCRETE, "base": Color(0.47, 0.48, 0.49), "alt": Color(0.17, 0.17, 0.18), "scale": 3.0, "rough": 0.9, "spec": 0.1, "seam": 0.9},
	{"name": "flagstone", "pat": Pat.FLAGSTONE, "base": Color(0.40, 0.37, 0.36), "alt": Color(0.12, 0.11, 0.11), "scale": 1.5, "rough": 0.88, "spec": 0.12, "seam": 0.8},
	{"name": "carpet", "pat": Pat.CARPET, "base": Color(0.28, 0.09, 0.15), "alt": Color(0.86, 0.62, 0.28), "scale": 1.6, "rough": 1.0, "spec": 0.02, "seam": 0.3},
	{"name": "tile", "pat": Pat.TILE, "base": Color(0.50, 0.50, 0.47), "alt": Color(0.22, 0.22, 0.21), "scale": 0.8, "rough": 0.35, "spec": 0.45, "seam": 1.0},
	{"name": "pool tile", "pat": Pat.TILE, "base": Color(0.14, 0.45, 0.50), "alt": Color(0.70, 0.84, 0.84), "scale": 0.7, "rough": 0.3, "spec": 0.5, "seam": 1.0},
	{"name": "wood boards", "pat": Pat.WOOD, "base": Color(0.55, 0.32, 0.17), "alt": Color(0.08, 0.04, 0.02), "scale": 0.42, "rough": 0.6, "spec": 0.25, "seam": 0.6},
	{"name": "marble", "pat": Pat.MARBLE, "base": Color(0.30, 0.28, 0.32), "alt": Color(0.88, 0.82, 0.70), "scale": 2.0, "rough": 0.25, "spec": 0.6, "seam": 0.85},
	{"name": "rubber mats", "pat": Pat.RUBBER, "base": Color(0.20, 0.23, 0.30), "alt": Color(0.50, 0.55, 0.62), "scale": 7.0, "rough": 0.92, "spec": 0.1, "seam": 0.55},
	{"name": "diamond plate", "pat": Pat.DIAMOND, "base": Color(0.28, 0.33, 0.38), "alt": Color(0.78, 0.86, 0.92), "scale": 3.4, "rough": 0.42, "spec": 0.6, "seam": 1.0},
	{"name": "diamond plate (dark)", "pat": Pat.DIAMOND, "base": Color(0.32, 0.24, 0.22), "alt": Color(0.95, 0.65, 0.55), "scale": 3.4, "rough": 0.45, "spec": 0.55, "seam": 1.0},
	{"name": "lab tile", "pat": Pat.TILE, "base": Color(0.40, 0.50, 0.47), "alt": Color(0.62, 0.72, 0.68), "scale": 0.55, "rough": 0.3, "spec": 0.5, "seam": 1.0},
	{"name": "corridor concrete", "pat": Pat.CONCRETE, "base": Color(0.27, 0.285, 0.31), "alt": Color(0.10, 0.10, 0.12), "scale": 3.4, "rough": 0.9, "spec": 0.1, "seam": 1.0},
	{"name": "corridor stone", "pat": Pat.FLAGSTONE, "base": Color(0.26, 0.27, 0.32), "alt": Color(0.09, 0.09, 0.11), "scale": 1.5, "rough": 0.88, "spec": 0.12, "seam": 1.0},
]

const WALLS: Array[Dictionary] = [
	{"name": "slate", "pat": Pat.NONE, "base": Color(0.10, 0.11, 0.145), "alt": Color(0.04, 0.04, 0.06), "scale": 1.0, "rough": 0.78, "spec": 0.22, "seam": 0.2},
	{"name": "poured concrete", "pat": Pat.FORM_CONCRETE, "base": Color(0.36, 0.37, 0.39), "alt": Color(0.12, 0.12, 0.14), "scale": 1.0, "rough": 0.92, "spec": 0.08, "seam": 0.2},
	{"name": "rough stone blocks", "pat": Pat.ASHLAR, "base": Color(0.30, 0.28, 0.30), "alt": Color(0.07, 0.065, 0.075), "scale": 1.0, "rough": 0.9, "spec": 0.1, "seam": 0.2},
	{"name": "wood panelling", "pat": Pat.PANELLING, "base": Color(0.42, 0.23, 0.12), "alt": Color(0.07, 0.035, 0.02), "scale": 1.0, "rough": 0.6, "spec": 0.25, "seam": 0.2},
	{"name": "marble", "pat": Pat.MARBLE_WALL, "base": Color(0.27, 0.26, 0.30), "alt": Color(0.88, 0.82, 0.70), "scale": 1.7, "rough": 0.3, "spec": 0.5, "seam": 0.2},
]

## Every room theme's floor (RoomThemeDefs.THEMES; tests/test_floor_materials.gd checks none is missing).
const THEME_FLOOR := {
	"service_entrance": F_CONCRETE,
	"home_cinema": F_CARPET,
	"spa": F_TILE,
	"pool": F_POOL_TILE,
	"wine_cellar": F_WOOD,
	"throne_room": F_MARBLE,
	"gym": F_RUBBER,
	"server_room": F_DIAMOND,
	"panic_room": F_DIAMOND_DARK,
	"lab": F_LAB_TILE,
	"barracks": F_CONCRETE,
	"torture_chamber": F_FLAGSTONE,
	"moat": F_FLAGSTONE,
	"science": F_LAB_TILE,
}

## The luxury themes dress their own walls; every other room has its site's wall.
const THEME_WALL := {
	"home_cinema": W_PANELLING,
	"wine_cellar": W_PANELLING,
	"throne_room": W_MARBLE,
}

## Site type -> its corridor floor (neutral, so the rooms stand out) and its wall.
const SITE_CORRIDOR := {"bunker": F_CORR_CONCRETE, "lair": F_CORR_STONE}
const SITE_WALL := {"bunker": W_CONCRETE, "lair": W_STONE}

## Microseconds the last assign() took (a probe for tests/test_floor_materials.gd).
static var last_usec := 0

static var _tables: Dictionary = {}


static func pack(floor_id: int, wall_id: int) -> int:
	return floor_id | (wall_id << 8)


static func floor_of(mat_id: int) -> int:
	return mat_id & 0xff


static func wall_of(mat_id: int) -> int:
	return (mat_id >> 8) & 0xff


## The floor material of a room theme ("" or unknown: the classic slate).
static func floor_for_theme(theme_id: String) -> int:
	return int(THEME_FLOOR.get(theme_id, F_SLATE))


## The wall material of a room theme on a site.
static func wall_for_theme(theme_id: String, site_type: String) -> int:
	return int(THEME_WALL.get(theme_id, SITE_WALL.get(site_type, W_CONCRETE)))


static func corridor_floor(site_type: String) -> int:
	return int(SITE_CORRIDOR.get(site_type, F_CORR_CONCRETE))


static func corridor_wall(site_type: String) -> int:
	return int(SITE_WALL.get(site_type, W_CONCRETE))


## How strongly the seams / bevel glow read on this floor material (1 = classic).
static func seam_gain(floor_id: int) -> float:
	if floor_id < 0 or floor_id >= FLOORS.size():
		return 1.0
	return float(FLOORS[floor_id]["seam"])


static func floor_name(floor_id: int) -> String:
	return String(FLOORS[clampi(floor_id, 0, FLOORS.size() - 1)]["name"])


static func wall_name(wall_id: int) -> String:
	return String(WALLS[clampi(wall_id, 0, WALLS.size() - 1)]["name"])


## Write Cell.mat_id for EVERY cell of the floor: room cells from their room's theme, corridors from the site type,
## untagged floor (ledges, tiers) from the first neighbouring room or corridor, walls from the site. One pass over the
## cells, no random numbers. `plan` is the SitePlan (room_themes, start_room, exit_room).
static func assign(map: HexMap, plan: SitePlan, site_type: String) -> void:
	var t0 := Time.get_ticks_usec()
	var corr := pack(corridor_floor(site_type), corridor_wall(site_type))
	var by_room := {}   ## room tag -> packed id
	for tag: String in plan.rooms:
		var theme := String(plan.room_themes.get(tag, ""))
		by_room[tag] = pack(floor_for_theme(theme) if theme != "" else corridor_floor(site_type), wall_for_theme(theme, site_type))
	var start_mat: int = int(by_room.get(plan.start_room, corr))
	var exit_mat: int = int(by_room.get(plan.exit_room, corr))
	var loose: Array[Vector2i] = []   ## untagged floor: resolved from its neighbours afterwards
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL:
			cell.mat_id = corr
			continue
		var tag := cell.tag
		if tag == "corridor":
			cell.mat_id = corr
		elif tag == "start":
			cell.mat_id = start_mat
		elif tag == "exit":
			cell.mat_id = exit_mat
		elif by_room.has(tag):
			cell.mat_id = int(by_room[tag])
		else:
			cell.mat_id = corr
			loose.append(c)
	for c in loose:
		for d in Hex.DIRS:
			var nb: HexMap.Cell = map.cells.get(c + d)
			if nb != null and nb.type != HexMap.Tile.WALL and by_room.has(nb.tag):
				map.cells[c].mat_id = int(by_room[nb.tag])
				break
	last_usec = Time.get_ticks_usec() - t0


## The shader's material tables, in LINEAR colour: base (rgb, a = pattern id), alt (rgb, a = pattern scale),
## par (x = roughness, y = specular).
static func table_arrays() -> Dictionary:
	if not _tables.is_empty():
		return _tables
	var base := PackedVector4Array()
	var alt := PackedVector4Array()
	var par := PackedVector4Array()
	base.resize(TABLE_SIZE)
	alt.resize(TABLE_SIZE)
	par.resize(TABLE_SIZE)
	for i in TABLE_SIZE:
		var d: Dictionary = {}
		if i < FLOORS.size():
			d = FLOORS[i]
		elif i >= WALL_OFFSET and i - WALL_OFFSET < WALLS.size():
			d = WALLS[i - WALL_OFFSET]
		if d.is_empty():
			continue
		var b: Color = (d["base"] as Color).srgb_to_linear()
		var a: Color = (d["alt"] as Color).srgb_to_linear()
		base[i] = Vector4(b.r, b.g, b.b, float(int(d["pat"])))
		alt[i] = Vector4(a.r, a.g, a.b, float(d["scale"]))
		par[i] = Vector4(float(d["rough"]), float(d["spec"]), 0.0, 0.0)
	_tables = {"base": base, "alt": alt, "par": par}
	return _tables

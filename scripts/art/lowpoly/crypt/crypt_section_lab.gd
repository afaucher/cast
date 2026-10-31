extends LabBase
## Crypt section lab (docs/design/crypt-section.md): a crypt as a SECTION of a floor, the way the sewer clusters and the
## lava caves are, drawn on the game's own terrain (a HexMap with levels, stairs and midpoint walls, HexMapView,
## DungeonLook) in its two material sets (CryptLook: "vault" under a mansion, "chapel" under a church), dressed with the
## crypt kit (CryptProps: sarcophagi, ossuary walls, iron gates, candles, bones). A LAB: the game builds its crypts on
## generated haunted floors since H2 (haunted-build-plan.md: CryptCluster, CryptPlanner, the same kit, materials and
## wall-run placement, CryptProps.wall_run); this hand-made section and its relit scene are the lab's, and the monsters are
## posed models (the crypt's skeletons as possessed hosts are another test's).
##
## The layout (the same in both sets): the room above (the mansion's wood-panelled room, or a church nave with pews and an
## altar) 6 levels up at the top of the screen; a stone arch at the head of a narrow stair hall that goes down toward the
## camera in two flights with a candle-lit landing; an open iron gate at its foot into the ENTRY VAULT; to the left, through
## a half-open gate, the BURIAL CHAMBER (candle-lit: sarcophagi, candelabras, floor candles, a bone wall); to the
## right, through an arch, the OSSUARY GALLERY (unlit: bone walls down its far side) and the END VAULT (an opened
## sarcophagus, bones).
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/crypt_section_lab.tscn --shot <abs dir>/plan.png [--set vault|chapel]
##
## PNGs, next to --shot (docs/design/crypt_section/):
##   plan.png              top down over the whole section, the parts named (the vault set)
##   section_<set>.png     the game camera (yaw 45, pitch -56, size 24, 1:1): the room above, the stairs, the entry vault
##   crypt_<set>.png       the game camera over the crypt: the burial chamber, the entry vault, the ossuary gallery
##   light_dark.png        crops at the game camera: the candle-lit chamber and the dark gallery, a row per set, 1:1
##   light_dark_2x.png     the same, the middle of each crop doubled (nearest)
##   props.png             close-ups of the kit at the game angles (size 9.5), a row per set
## --set   only that set's game views (no plan, no sheets).

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const CLOSE_SIZE := 9.5
const LH := Hex.LEVEL_HEIGHT
const WALL_LEVEL := 3               ## the game's walls (DungeonGen wall_height 3)
const UP_LEVEL := 6                 ## the room above: 3.0 up
const CROP := Vector2i(620, 400)    ## a light / dark crop round its spot, 1:1 game pixels
const CLOSE_CROP := Vector2i(280, 250)
const RIGHT := Vector3(0.7071, 0.0, -0.7071)       ## the game camera's screen right on the floor
const TOWARD := Vector3(0.7071, 0.0, 0.7071)       ## toward the game camera on the floor
const DISPLAY := Vector2i(-34, 0)   ## the props' display room, well away from the section

var set_name := "vault"
var holder: Node3D
var terrain: HexMapView
var _cells := {}                    ## Vector2i -> tag ("room:N", "corridor"), before the map is made
var levels := {}                    ## Vector2i -> floor level (default 0)
var stair_of := {}                  ## Vector2i -> [dir it climbs toward, rise]
var hall_cells := {}                ## hall id -> Array[Vector2i]
var routes := {}                    ## hall id -> Array[Vector2i] (door to door)
var keys := {}                      ## name -> Vector2i: the rooms' centres
var spots := {}                     ## name -> Vector3: where the views and crops look
var crew := {}                      ## "wick", "rebar", "grunt", "grunt2" -> the posed models
var lights: Array[Light3D] = []     ## the candle lights and downlights (tests count them)
var labels: Array[Node3D] = []      ## the plan's names (hidden in the game views)
var display: Array[Node3D] = []     ## the display room's pieces, in props.png's column order
## The walls' depth look (HexMapView.wall_depth, docs/design/wall-depth.md): on, as in the game.
var wall_depth := true


func _ready() -> void:
	make_camera(260.0)
	var only := arg(args, "--set", "")
	build(only if only != "" else "vault")
	if shot_path != "":
		_run(only)


# --- the map ------------------------------------------------------------------------------------------------------

func _room(center: Vector2i, radius: int, tag: String) -> void:
	for c in Hex.range_cells(center, radius):
		if not _cells.has(c):
			_cells[c] = tag


## A straight hall cut the way DungeonGen cuts one (the sewer lab's _hall): from door cell `a` `n` steps along DIRS[dir],
## the route plus `lanes` lanes toward DIRS[dir + 1], every core cell's neighbours added (they become cut cells when the
## walls go in). lanes 0: narrow (3.0 between the wall lines), 1: wide (4.5). Remembers its cells and route.
func _hall(hall_id: String, a: Vector2i, dir: int, n: int, lanes: int) -> Array[Vector2i]:
	var before := _cells.duplicate()
	var route: Array[Vector2i] = []
	for i in n + 1:
		route.append(a + Hex.DIRS[dir] * i)
	var core: Array[Vector2i] = route.duplicate()
	for i in range(1, n):
		if not _cells.has(route[i]):
			_cells[route[i]] = "corridor"
		for k in range(1, lanes + 1):
			var lane: Vector2i = route[i] + Hex.DIRS[(dir + 1) % 6] * k
			if _cells.has(lane) and str(_cells[lane]) != "corridor":
				continue
			_cells[lane] = "corridor"
			core.append(lane)
	for k in core:
		for d in Hex.DIRS:
			if not _cells.has(k + d):
				_cells[k + d] = "corridor"
	var mine: Array[Vector2i] = []
	for c: Vector2i in _cells:
		if not before.has(c):
			mine.append(c)
	hall_cells[hall_id] = mine
	routes[hall_id] = route
	return route


## Every cell of a hall at the level of its nearest route cell (so the stair hall's cut cells follow its flights).
func _hall_levels(hall_id: String, route_levels: Array) -> void:
	var route: Array[Vector2i] = routes[hall_id]
	for c: Vector2i in hall_cells[hall_id]:
		var best := 999
		var lv := 0
		for i in route.size():
			var d := Hex.distance(c, route[i])
			if d < best:
				best = d
				lv = int(route_levels[i])
		levels[c] = lv


## The section's cells: the room above (room:0) 6 up, the stair hall down two flights, the entry vault (room:1), the burial
## chamber (room:2) through a wide hall, the ossuary gallery (a wide hall) to the end vault (room:3).
func _layout() -> void:
	var D := Hex.DIRS
	var u0 := Vector2i(0, 0)
	var e0 := u0 + D[5] * 13
	var b0 := e0 + D[4] * 9
	var k0 := e0 + D[1] * 13
	keys = {"above": u0, "entry": e0, "chamber": b0, "end": k0, "display": DISPLAY}
	_room(u0, 4, "room:0")
	_room(e0, 3, "room:1")
	_room(b0, 4, "room:2")
	_room(k0, 3, "room:3")
	_room(DISPLAY, 6, "room:9")
	for c in Hex.range_cells(u0, 4):
		levels[c] = UP_LEVEL
	var st := _hall("stair", u0 + D[5] * 4, 5, 6, 0)
	_hall("chamber", e0 + D[4] * 3, 4, 2, 1)
	_hall("gallery", e0 + D[1] * 3, 1, 7, 1)
	stair_of[st[2]] = [2, 3]
	stair_of[st[4]] = [2, 3]
	_hall_levels("stair", [6, 6, 3, 3, 0, 0, 0])


## The HexMap: every cell at its level in its material (the room above in the set's own, the crypt in CryptLook's rows),
## the stairs, and a wall WALL_LEVEL over the highest floor beside each wall cell, then the midpoint cut.
func _make_map() -> void:
	map = HexMap.new()
	var above := CryptLook.above_mat(set_name)
	for c: Vector2i in _cells:
		var tag := str(_cells[c])
		var cell := map.set_cell(c, int(levels.get(c, 0)))
		cell.tag = tag
		cell.mat_id = above if tag == "room:0" else (CryptLook.crypt_hall_mat(set_name) if tag == "corridor" else CryptLook.crypt_room_mat(set_name))
		if stair_of.has(c):
			cell.type = HexMap.Tile.STAIRS
			cell.stair_dir = int(stair_of[c][0])
			cell.stair_rise = int(stair_of[c][1])
	for c: Vector2i in _cells:
		for nb in Hex.neighbors(c):
			if _cells.has(nb) or map.has_cell(nb):
				continue
			var top := 0
			var mat := CryptLook.crypt_room_mat(set_name)
			for n2 in Hex.neighbors(nb):
				if _cells.has(n2):
					top = maxi(top, int(levels.get(n2, 0)) + (int(stair_of[n2][1]) if stair_of.has(n2) else 0))
					if str(_cells[n2]) == "room:0":
						mat = above
			map.set_cell(nb, top + WALL_LEVEL, HexMap.Tile.WALL).mat_id = mat
	# a void cell walled in on every side would draw as a pit: fill it with wall
	var holes := {}
	for c: Vector2i in map.cells:
		for nb in Hex.neighbors(c):
			if map.has_cell(nb) or holes.has(nb):
				continue
			var shut := true
			var top := 0
			for n2 in Hex.neighbors(nb):
				shut = shut and map.has_cell(n2)
				if map.has_cell(n2):
					top = maxi(top, map.cells[n2].level)
			if shut:
				holes[nb] = top
	for c: Vector2i in holes:
		map.set_cell(c, int(holes[c]), HexMap.Tile.WALL).mat_id = CryptLook.crypt_room_mat(set_name)
	map.cut_walls()


# --- building a set -----------------------------------------------------------------------------------------------

## Build the whole section in `which` set (CryptLook / CryptProps), replacing whatever was built before.
func build(which: String) -> void:
	set_name = which if CryptLook.SETS.has(which) else "vault"
	if holder != null:
		remove_child(holder)
		holder.free()
	holder = Node3D.new()
	holder.name = "Section"
	add_child(holder)
	_cells = {}
	levels = {}
	stair_of = {}
	hall_cells = {}
	routes = {}
	crew = {}
	lights = []
	labels = []
	display = []
	_layout()
	_make_map()
	GameWorld.begin(map, holder, 11)
	terrain = HexMapView.new()
	terrain.wall_depth = wall_depth
	holder.add_child(terrain)
	terrain.build(map)
	DungeonLook.apply(holder)
	CryptLook.relight(holder, set_name)
	_dress_above()
	_dress_stairs()
	_dress_crypt()
	_dress_display()
	_crew()
	_labels()
	_show_labels(false)


func _w(c: Vector2i, off: Vector3 = Vector3.ZERO) -> Vector3:
	var p := Hex.to_world(c) + off
	p.y = float(levels.get(c, 0)) * LH
	return p


func _put(node: Node3D, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	holder.add_child(node)
	node.position = pos
	node.rotation_degrees.y = yaw_deg
	for l in node.find_children("*", "Light3D", true, false):
		lights.append(l as Light3D)
	return node


static func yaw_to(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, v.z))


func _crypt(kind: String, pos: Vector3, yaw_deg: float, params: Dictionary = {}) -> Node3D:
	var p := params.duplicate()
	p["set"] = set_name
	return _put(CryptProps.build(kind, p), pos, yaw_deg)


## A piece backed onto the wall face nearest `near` (within 3): its back on the face, its front along the face's normal.
func _on_wall(kind: String, near: Vector3, params: Dictionary = {}) -> Node3D:
	var run := _wall_run(Vector2(near.x, near.z), 3.5)
	if run.is_empty():
		return null
	var a: Vector2 = run[0]
	var b: Vector2 = run[1]
	var n: Vector2 = run[2]
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	var width := minf(float(params.get("width", 3.0)), length - 0.2)
	var t := clampf((Vector2(near.x, near.z) - a).dot(along), width * 0.5 + 0.1, length - width * 0.5 - 0.1)
	var pt := a + along * t
	var pp := params.duplicate()
	pp["width"] = width
	return _crypt(kind, Vector3(pt.x, near.y, pt.y) + Vector3(n.x, 0, n.y) * 0.02, rad_to_deg(atan2(n.x, n.y)), pp)


## The straight run of wall nearest `q` (within `max_dist`): the nearest wall face's segment grown along every face that
## continues it in line, facing the same way. [a, b, normal], or [] with no wall near. (An ossuary on the nearest point
## alone sat across a corner, half in the wall.)
func _wall_run(q: Vector2, max_dist: float) -> Array:
	return CryptProps.wall_run(map, q, max_dist)


## The doorway between a hall's first route cell (a room's edge cell) and the hall, on the hall's centre line: [position,
## the hall's direction].
func _door(hall_id: String, dir: int, lanes: int, at_end: bool = false) -> Array:
	var route: Array[Vector2i] = routes[hall_id]
	var c: Vector2i = route[route.size() - 1] if at_end else route[0]
	var ax := Hex.dir_vector(dir) * (-1.0 if at_end else 1.0)
	var p := _w(c) + ax * Hex.INNER
	if lanes > 0:
		p += (Hex.to_world(Hex.DIRS[(dir + 1) % 6]) - Hex.to_world(Vector2i.ZERO)) * 0.5
	return [p, ax]


## The room above: the mansion's panelled room (a suit of armour, a statue, a lamp, a red carpet to the crypt's door) or
## a church nave (pews, an altar with candles, candelabras); a warm downlight pool either way; the stone arch at the head
## of the stairs.
func _dress_above() -> void:
	var D := Hex.DIRS
	var u0: Vector2i = keys["above"]
	var toward_stairs := Hex.dir_vector(5)
	var side := Vector3(0.866, 0, -0.5)
	var dl := CryptLook.downlight(_w(u0) + Vector3(0.0, 0, -0.5))
	holder.add_child(dl)
	lights.append(dl)
	var door: Array = _door("stair", 5, 0)
	_crypt("arch", door[0], yaw_to(toward_stairs))
	if CryptLook.look(set_name)["above"] == "church":
		var altar := _w(u0 + D[2] * 2) + Vector3(0, 0, 0)
		_crypt("altar", altar, yaw_to(toward_stairs))
		_crypt("candelabra", altar + side * 1.9, 0.0)
		_crypt("candelabra", altar - side * 1.9, 0.0)
		for row in 2:
			for s: float in [-1.0, 1.0]:
				_crypt("pew", _w(u0) + toward_stairs * (0.4 + 1.5 * float(row)) + side * s * 1.9, yaw_to(-toward_stairs))
	else:
		var armour := ArmourModel.new()
		_put(armour, _w(u0 + D[2] * 3) + toward_stairs * 0.3, yaw_to(-toward_stairs))
		_put(PropModels.build("marble_statue"), _w(u0 + D[3] * 3), yaw_to(Hex.dir_vector(0)))
		_put(PropModels.build("crystal_lamp"), _w(u0 + D[1] * 3), yaw_to(Hex.dir_vector(4)))
		_put(DecorModels.build("red_carpet"), _w(u0 + D[5] * 1) + Vector3(0, 0.01, 0), yaw_to(toward_stairs))


## The stair hall: candles on the landing between the flights, an open gate at its foot.
func _dress_stairs() -> void:
	var st: Array[Vector2i] = routes["stair"]
	var side := Vector3(0.866, 0, -0.5)
	_crypt("candles", _w(st[3]) + side * 0.85, 0.0, {"count": 5, "radius": 0.3, "seed": 8, "light": 0.8})
	var door: Array = _door("stair", 5, 0, true)
	_crypt("gate", door[0], yaw_to(Hex.dir_vector(5)), {"open": 0.85})


## The crypt: the entry vault, the candle-lit burial chamber, the dark ossuary gallery and the end vault.
func _dress_crypt() -> void:
	var D := Hex.DIRS
	var e0: Vector2i = keys["entry"]
	var b0: Vector2i = keys["chamber"]
	var k0: Vector2i = keys["end"]
	var side := Vector3(0.866, 0, -0.5)          # across the chamber, square to the camera's line
	var back := -Hex.dir_vector(5)               # away from the camera
	# the entry vault: candles by the stair gate, a skeleton
	_crypt("candles", _w(e0 + D[2] * 2) + side * 1.3, 0.0, {"count": 6, "seed": 4, "light": 0.9})
	_crypt("bones", _w(e0 + D[0]) + Vector3(0.2, 0, 0.3), 30.0, {"seed": 6})
	# the gate into the burial chamber (half open), the arch into the gallery
	var gd: Array = _door("chamber", 4, 1)
	_crypt("gate", gd[0], yaw_to(gd[1]), {"width": 4.5, "open": 0.45})
	var ad: Array = _door("gallery", 1, 1)
	_crypt("arch", ad[0], yaw_to(-(ad[1] as Vector3)), {"width": 4.5})
	# the burial chamber: three sarcophagi, candelabras at their heads, candles at their feet, a bone wall
	var bc := _w(b0) + back * 0.6
	_crypt("sarcophagus", bc, yaw_to(-back))
	_crypt("sarcophagus", bc + side * 2.0 + back * 0.2, yaw_to(-back), {"lid": "cross" if set_name == "vault" else "effigy"})
	_crypt("sarcophagus", bc - side * 2.0 + back * 0.2, yaw_to(-back), {"lid": "ajar"})
	_crypt("candelabra", bc + side * 1.0 + back * 1.25, 0.0)
	_crypt("candelabra", bc - side * 1.0 + back * 1.25, 0.0)
	_crypt("candles", bc - back * 1.75, 0.0, {"count": 7, "seed": 11})
	_crypt("candles", bc + side * 2.0 - back * 1.5, 0.0, {"count": 4, "radius": 0.3, "seed": 12, "light": 0.7})
	_on_wall("ossuary", _w(b0) + back * 5.2, {"width": 3.4})
	# the gallery: bone walls down the far side, bones on the floor; no light
	var gr: Array[Vector2i] = routes["gallery"]
	for i: int in [1, 3, 5]:
		_on_wall("ossuary", _w(gr[i] + D[2]) + Hex.dir_vector(1) * 0.85, {"width": 3.2})
	_crypt("bones", _w(gr[2]) + Vector3(0.2, 0, 0.4), 70.0, {"seed": 9})
	_crypt("bones", _w(gr[5] + D[2]), 200.0, {"seed": 10})
	# the end vault: an opened sarcophagus, bones, a bone wall
	_crypt("sarcophagus", _w(k0) + back * 0.3, yaw_to(Hex.dir_vector(4)), {"lid": "ajar"})
	_crypt("bones", _w(k0 + D[4] * 2), 140.0, {"seed": 14})
	_on_wall("ossuary", _w(k0) + back * 3.6, {"width": 3.0})
	# the chapel's pale shafts from gratings in the church floor: over the entry vault, the chamber's sarcophagi and the end
	# vault (the gallery stays dark)
	if bool(CryptLook.look(set_name)["shafts"]):
		for at: Vector3 in [_w(e0 + D[0]), bc - back * 0.9, _w(k0 + D[4])]:
			_put(CryptLook.shaft(Vector3.ZERO), at)
	spots["bright"] = bc - back * 0.4
	spots["dark"] = _w(gr[4]) + (Hex.to_world(D[2]) - Hex.to_world(Vector2i.ZERO)) * 0.5
	spots["section"] = (_w(keys["above"]) + _w(e0)) * 0.5 - Hex.dir_vector(5) * 1.5
	spots["crypt"] = (_w(b0) + _w(gr[3])) * 0.5 - TOWARD * 1.5


## The display room (far from the section, for the close-ups): each piece on its own lit spot along the screen's right.
func _dress_display() -> void:
	var c := Hex.to_world(DISPLAY)
	for i in 2:
		var l := OmniLight3D.new()
		l.position = c + RIGHT * (-3.5 + 7.0 * float(i)) + Vector3(0, 4.0, 0) + TOWARD * 1.5
		l.light_color = Color(1.0, 0.86, 0.7)
		l.light_energy = 9.0
		l.omni_range = 11.0
		l.omni_attenuation = 1.2
		l.shadow_enabled = false
		holder.add_child(l)
	var face := yaw_to(TOWARD)
	var specs := [["sarcophagus", {}], ["ossuary", {"width": 2.2}], ["gate", {"open": 0.25}], ["candles", {"count": 7, "seed": 2}],
			["candelabra", {}], ["bones", {"seed": 3}]]
	for i in specs.size():
		var at := c + RIGHT * (-7.0 + 2.8 * float(i)) - TOWARD * 0.6
		var n := _crypt(str(specs[i][0]), at, yaw_to(RIGHT) if i == 0 else face, specs[i][1])
		display.append(n)


## The crew and two grunts (today's skeleton model), posed: Wick on the stairs' landing, Rebar at the chamber's candles, a
## grunt by the sarcophagi and one in the dark gallery. `_stage_dark` moves Wick into the gallery for the dark crops.
func _crew() -> void:
	var st: Array[Vector2i] = routes["stair"]
	var gr: Array[Vector2i] = routes["gallery"]
	var bc: Vector3 = spots["bright"]
	crew["wick"] = _hero("wick", _w(st[3]) - Vector3(0.866, 0, -0.5) * 0.4, Hex.dir_vector(5))
	crew["rebar"] = _hero("rebar", bc + RIGHT * 1.4 + TOWARD * 2.4, -TOWARD - RIGHT * 0.3)
	crew["grunt"] = _monster("grunt", bc - RIGHT * 1.6 + TOWARD * 1.9, TOWARD + RIGHT * 0.5)
	crew["grunt2"] = _monster("grunt", _w(gr[5]) + Hex.dir_vector(1) * 0.3, Hex.dir_vector(4))


func _hero(which: String, pos: Vector3, face: Vector3) -> LowPolyModel:
	var m: LowPolyModel = RebarModel.new() if which == "rebar" else WickModel.new()
	holder.add_child(m)
	m.idle_enabled = false
	m.apply_idle(0.6)
	m.position = pos
	m.rotation_degrees = Vector3(0, rad_to_deg(atan2(-face.x, -face.z)), 0)
	return m


func _monster(kind: String, pos: Vector3, face: Vector3) -> MonsterModel:
	var m := MonsterModels.make(kind)
	holder.add_child(m)
	m.position = pos
	m.rotation_degrees.y = rad_to_deg(atan2(face.x, face.z))
	m.pose_preview("rest", 1.0)
	return m


## Wick on the stairs (the section views) or in the dark gallery (the crypt views and crops).
func _stage(view: String) -> void:
	var wick: Node3D = crew["wick"]
	if view == "section":
		var st: Array[Vector2i] = routes["stair"]
		wick.position = _w(st[3]) - Vector3(0.866, 0, -0.5) * 0.4
		wick.rotation_degrees.y = rad_to_deg(atan2(-Hex.dir_vector(5).x, -Hex.dir_vector(5).z))
	else:
		var d: Vector3 = spots["dark"]
		wick.position = d - RIGHT * 1.2 + TOWARD * 0.3
		var f := RIGHT + TOWARD * 0.4
		wick.rotation_degrees.y = rad_to_deg(atan2(-f.x, -f.z))


# --- the plan's names -----------------------------------------------------------------------------------------------

func _labels() -> void:
	var above := "the church above (3.0 up)" if CryptLook.look(set_name)["above"] == "church" else "the mansion room above (3.0 up)"
	var st: Array[Vector2i] = routes["stair"]
	var gr: Array[Vector2i] = routes["gallery"]
	_label3(_w(keys["above"]), above)
	_label3(_w(st[3]) - RIGHT * 4.6, "stairs down: two flights,\ncandles on the landing")
	_label3(_w(st[6]) - RIGHT * 4.4 - TOWARD * 0.2, "iron gate (open)")
	_label3(_w(keys["entry"]) + TOWARD * 2.6, "entry vault")
	_label3(_w(keys["chamber"]) + TOWARD * 5.2, "burial chamber (candle-lit),\na gate (half open) into it")
	_label3(_w(gr[4]) - TOWARD * 3.4 + RIGHT * 1.0, "ossuary gallery (no light)")
	_label3(_w(keys["end"]) + TOWARD * 4.0, "end vault (no light)")


func _label3(p: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.outline_size = 16
	l.pixel_size = 0.02
	l.modulate = Color(1.0, 0.92, 0.6)
	l.render_priority = 12
	l.outline_render_priority = 11
	holder.add_child(l)
	l.position = p + Vector3(0, 4.0, 0)
	labels.append(l)


func _show_labels(on: bool) -> void:
	for l in labels:
		l.visible = on


# --- the run --------------------------------------------------------------------------------------------------------

func _run(only: String) -> void:
	await wait_frames(10)
	var dir := shot_path.get_base_dir()
	var sets: Array[String] = CryptLook.SETS.duplicate()
	if only != "":
		sets = [only]
	var lit_crops: Array = []
	var close_rows: Array = []
	for i in sets.size():
		var s: String = sets[i]
		if s != set_name:
			build(s)
			await wait_frames(6)
		if only == "" and i == 0:
			_show_labels(true)
			# (the plan turned like the game views: screen right is RIGHT, screen down is TOWARD)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for c: Vector2i in map.cells:
				if Hex.distance(c, DISPLAY) <= 8:
					continue
				var w := Hex.to_world(c)
				var q := Vector2(w.dot(RIGHT), w.dot(TOWARD))
				lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
				hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
			var centre := RIGHT * (lo.x + hi.x) * 0.5 + TOWARD * (lo.y + hi.y) * 0.5
			aim(GAME_YAW, -89.5, maxf(hi.y - lo.y, (hi.x - lo.x) * 9.0 / 16.0) + 2.0, centre, 80.0)
			await snap(shot_path)
			_show_labels(false)
		_stage("section")
		aim(GAME_YAW, GAME_PITCH, GAME_SIZE, spots["section"])
		await snap("%s/section_%s.png" % [dir, s])
		_stage("crypt")
		aim(GAME_YAW, GAME_PITCH, GAME_SIZE, spots["crypt"])
		await snap("%s/crypt_%s.png" % [dir, s])
		var row: Array[Image] = []
		for which: String in ["bright", "dark"]:
			aim(GAME_YAW, GAME_PITCH, GAME_SIZE, (spots[which] as Vector3) + Vector3(0, 0.6, 0))
			row.append(_crop(await grab(), CROP))
		lit_crops.append(row)
		var crow: Array[Image] = []
		for n: Node3D in display:
			aim(GAME_YAW, GAME_PITCH, CLOSE_SIZE, n.global_position + Vector3(0, 0.7, 0))
			crow.append(_crop(await grab(), CLOSE_CROP))
		close_rows.append(crow)
	if only == "":
		var names: Array = []
		for s: String in sets:
			names.append(str(CryptLook.look(s)["title"]))
		await _sheet("%s/light_dark.png" % dir, "Candle light vs the dark at the game camera (size 24, 1:1)  -  docs/design/crypt-section.md",
				names, [["", ["burial chamber (candle-lit)", "ossuary gallery (no light)"]]], lit_crops, CROP, 0)
		await _sheet("%s/light_dark_2x.png" % dir, "The same, the middle of each crop at 2x (nearest)",
				names, [["", ["burial chamber (candle-lit)", "ossuary gallery (no light)"]]], lit_crops, CROP, 0, 2)
		await _sheet("%s/props.png" % dir, "The crypt kit, closer (size 9.5) at the game angles, in a lit display room",
				names, [["", ["sarcophagus", "ossuary wall", "iron gate", "floor candles", "candelabra", "bones"]]], close_rows,
				CLOSE_CROP, 0)
	finish()


func _crop(img: Image, size: Vector2i) -> Image:
	img.convert(Image.FORMAT_RGBA8)
	return img.get_region(Rect2i(img.get_width() / 2 - size.x / 2, img.get_height() / 2 - size.y / 2, size.x, size.y))


## A labelled contact sheet (the ghost look lab's): `row_names` down the left, column blocks across the top, `rows` the
## images (each `cell` big; `zoom` 2: the middle half, doubled, nearest), laid out in window pixels and grabbed.
func _sheet(path: String, title: String, row_names: Array, blocks: Array, rows: Array, cell: Vector2i, _unused: int, zoom: int = 1) -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var layer := Control.new()
	var k := get_viewport().get_visible_rect().size.x / float(get_window().size.x)
	layer.scale = Vector2(k, k)
	canvas.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.11, 0.1)
	bg.size = Vector2(1920, 1080)
	layer.add_child(bg)
	var gap := 4
	var x0 := 190
	var y0 := 80
	var head := _label(layer, title, Vector2(12, 8), 22)
	head.modulate = Color(1.0, 0.9, 0.7)
	var xs: Array[int] = []
	var x := x0
	for b: Array in blocks:
		var names: Array = b[1]
		if str(b[0]) != "":
			_label(layer, str(b[0]), Vector2(x, 38), 17).modulate = Color(1.0, 0.85, 0.4)
		for n in names:
			xs.append(x)
			_label(layer, str(n), Vector2(x + 4, 52), 16)
			x += cell.x + gap
	var right := x - gap
	for r in rows.size():
		var y := y0 + r * (cell.y + 6)
		var rl := _label(layer, str(row_names[r]).replace(": ", ":\n"), Vector2(10, y + cell.y / 2 - 24), 17)
		rl.size = Vector2(x0 - 16, 60)
		var row: Array = rows[r]
		for c in row.size():
			var img := (row[c] as Image)
			if zoom != 1:
				img = img.get_region(Rect2i((cell.x - cell.x / zoom) / 2, (cell.y - cell.y / zoom) / 2, cell.x / zoom, cell.y / zoom))
				img.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
			var tr := TextureRect.new()
			tr.texture = ImageTexture.create_from_image(img)
			tr.position = Vector2(xs[c], y)
			layer.add_child(tr)
	var bottom := y0 + rows.size() * (cell.y + 6)
	var shot := await grab(8)
	shot.convert(Image.FORMAT_RGBA8)
	save_shot(shot.get_region(Rect2i(0, 0, mini(right + 10, shot.get_width()), mini(bottom + 4, shot.get_height()))), path)
	canvas.queue_free()
	await wait_frames(2)


func _label(parent: Control, text: String, pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

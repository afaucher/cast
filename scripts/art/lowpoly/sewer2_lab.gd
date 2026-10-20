extends "res://scripts/art/lowpoly/sewer_lab.gd"
## Sewer lab, round 2 (docs/design/sewer-concept.md, "Sewer round 2: connected water, staging, fights"): POPULATED sewer
## clusters on the game's real terrain drawing. Every room's water is ONE connected body with the flooded halls: a channel
## comes in through one doorway, crosses the room and leaves through the far one (or a barred culvert at the cluster's
## edge). LOOK-DEV ONLY: nothing here is used by the game and nothing declares gameplay state. The actors are static
## models (heroes, MonsterModels, EmployeeModel, NoteModels, PropModels, the lab's SewerProps) posed where the design
## puts them; the gator is the lab model.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/sewer2_lab.tscn --case <case> --shot <png> [--view <name>]
##
## --case (layouts: views game (size 24), plan (top-down, annotated); some add game2)
##   reclaim     L1 "Reclamation run" (bunker, concrete): intake -> narrow flooded hall -> settling cistern -> ledged wide
##               hall -> pump room; views game (intake + cistern), game2 (cistern + pump room), plan
##   junction    L2 "The Y" (lair, brick): a drain junction, three flooded halls to a pump post, the aquarium overflow
##               and a storeroom
##   aquarium    L3 "Aquarium overflow" (lair, toxic): the villain's aquarium gallery leaks into a channel, a ledged hall,
##               the filtration room
##   loop        L4 "Storm-drain loop" (bunker, concrete): four rooms in a ring; two ledged wide halls (dry long way),
##               two fully flooded narrow halls (wet short way)
##   main        L5 "The sewer main" (lair, brick): a grand cistern and an outfall gallery joined by a 6.0 main with a
##               ledge each side
## --case (fight moments: views game (24) and close)
##   fight_shove    L2: a skeleton pack wades the junction; Rebar punches one into the gator's territory, the gator nips it
##   fight_wire     L3: the junction box is hit, the cable drops into the channel, the shock runs along the water
##   fight_ledge    L5: archers on the far ledge of the main; the steam vent walls one off, corn floats as the gator's chum
##
## Every grate bridge is checked to span the channel (both ends on dry floor on opposite banks): see _check_bridges().

const NAVY := Color(0.04, 0.05, 0.07)
const C_WATER := Color(0.2, 0.55, 1.0, 0.5)
const C_DECK := Color(0.45, 0.95, 0.4, 0.28)
const C_LEDGE := Color(1.0, 0.85, 0.15, 0.55)
const C_DRYHALL := Color(0.75, 0.75, 0.78, 0.3)
const C_BRIDGE := Color(1.0, 1.0, 1.0, 0.85)
const C_SLUICE := Color(1.0, 0.2, 0.15, 1.0)
const C_ARCH := Color(0.35, 1.0, 0.55, 1.0)
const C_FOG := Color(0.3, 1.0, 1.0, 1.0)
const C_GATOR := Color(1.0, 0.55, 0.1, 1.0)
const C_MON := Color(1.0, 0.35, 0.3, 1.0)
const C_CREW := Color(0.4, 1.0, 0.5, 1.0)
const C_EMP := Color(0.55, 0.8, 1.0, 1.0)
const C_NOTE := Color(1.0, 1.0, 0.92, 1.0)
const C_HAZ := Color(1.0, 0.92, 0.2, 1.0)

const TERRITORY := 3.0        ## the gator's snap radius (design)
const WATCH := 4.5            ## its watch radius: it turns to track, eyes bright

var flows: Array[PackedVector2Array] = []     ## flow polylines (world X/Z), in flow order
var hall_cells := {}                          ## hall name -> Array[Vector2i] (its cells, from _hall2)
var wet_halls := {}                           ## hall name -> true: halls under water
var plan_nodes: Array[Node3D] = []            ## the plan's overlay (hidden in the game views)
var fight_nodes: Array[Node3D] = []           ## telegraphs and arrows (fight cases: always shown)
var space_names := {}                         ## fog tag -> readable name
var room_names := {}                          ## "room:N" -> readable name
var canvas: CanvasLayer
var legend: Control
var caption: Label
var title_text := ""
var plan_size := 40.0
var wire_down := false                        ## L3: the live cable lies in the water (the fight case)
var plan_at := Vector3.ZERO
var legend_corner := "tl"                  ## where the plan legend sits: tl, tr, bl, br (the canvas is 1600 x 900)


func _ready() -> void:
	flow_of = _flow_at
	canvas = CanvasLayer.new()
	add_child(canvas)
	super._ready()


func _set_look(look_id: String) -> void:
	if _arg(OS.get_cmdline_user_args(), "--look") == "":
		look_name = look_id
		look = LOOKS[look_id]


# --------------------------------------------------------------------------- building the cluster

## _hall, remembering the hall's cells under `hall_id` (so it can be flooded, or kept dry, as a whole).
func _hall2(hall_id: String, a: Vector2i, dir: int, n: int, lanes: int) -> Array[Vector2i]:
	var before := _cells.duplicate()
	var route := _hall(a, dir, n, lanes)
	var mine: Array[Vector2i] = []
	for c: Vector2i in _cells:
		if not before.has(c):
			mine.append(c)
	hall_cells[hall_id] = mine
	return route


## A narrow hall under water wall to wall.
func _flood_hall(hall_id: String) -> void:
	wet_halls[hall_id] = true
	_flood(hall_cells[hall_id])


## A wide hall's channel: the route row and the near cut row (the far lane stays a dry ledge, the camera sees it whole).
func _flood_wide(hall_id: String, route: Array[Vector2i], dir: int) -> void:
	wet_halls[hall_id] = true
	var cells: Array[Vector2i] = []
	for i in range(1, route.size() - 1):
		var r: Vector2i = route[i]
		cells.append(r)
		cells.append(r + Hex.DIRS[(dir + 5) % 6])
		cells.append(r + Hex.DIRS[(dir + 4) % 6])
	_flood(cells)


## A 6.0 main's channel: the middle row only (lane 1); a dry ledge each side.
func _flood_main(hall_id: String, route: Array[Vector2i], dir: int) -> void:
	wet_halls[hall_id] = true
	var cells: Array[Vector2i] = []
	for i in range(0, route.size()):
		cells.append(route[i] + Hex.DIRS[(dir + 1) % 6])
	_flood(cells)


## Wet cells along a hex line a..b (inclusive).
func _wet_line(a: Vector2i, b: Vector2i) -> void:
	_flood(Hex.line(a, b))


## A flow polyline through these cells (world X/Z), in flow order.
func _flow(cells: Array) -> void:
	var pl := PackedVector2Array()
	for c: Vector2i in cells:
		var w := Hex.to_world(c)
		pl.append(Vector2(w.x, w.z))
	flows.append(pl)


## The water's flow direction at p: along the nearest flow segment.
func _flow_at(p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2(1, 0)
	for pl in flows:
		for i in pl.size() - 1:
			var a := pl[i]
			var ab := pl[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				dir = ab.normalized()
	return dir


## Point on a hex-blob room's wall side between corners d and d + 1: `t` along the side from its middle (toward corner
## d + 1 when positive), `inset` in from the wall line. Returns [position, inward yaw] (a prop's front, +Z, faces in).
func _wall_spot(c: Vector2i, radius: int, d: int, t: float, inset: float) -> Array:
	var n := (Hex.dir_vector(d) + Hex.dir_vector(d + 1)).normalized()
	var tan := (Hex.dir_vector(d + 1) - Hex.dir_vector(d)).normalized()
	var p := Hex.to_world(c) + n * (1.5 * float(radius) - inset) + tan * t
	return [p, yaw_to(-n)]


func _put_wall(node: Node3D, c: Vector2i, radius: int, d: int, t: float, inset: float) -> Node3D:
	var s := _wall_spot(c, radius, d, t, inset)
	return _put(node, s[0], s[1])


# --------------------------------------------------------------------------- actors (static models)

func _ground_y(p: Vector3) -> float:
	return FLOOR_Y if wet.has(Hex.from_world(p)) or map.water_at(Vector3(p.x, 0, p.z)) else 0.0


func _hero_at(which: String, p: Vector3, face: Vector3, pose: String = "") -> LowPolyModel:
	p.y = _ground_y(p)
	var m := _hero(which, p, face)
	match pose:
		"shoot":
			if m.has_method("pose_preview"):
				m.call("pose_preview", "shoot", 0.6)
		"cast":
			if which == "wick":
				m.call("pose_preview", "cast", 0.6)
			else:
				m.call("cast_pose")
		"swing":
			m.call("attack_swing")
		"bowl":
			if m.has_method("bowl_pose"):
				m.call("bowl_pose")
	return m


## A monster model at p facing `face`; wading (ripple) when p is in the water. pose: rest / windup / swing.
func _mon(kind: String, p: Vector3, face: Vector3, pose: String = "rest", k: float = 1.0) -> MonsterModel:
	var m := MonsterModels.make(kind)
	add_child(m)
	p.y = _ground_y(p)
	m.position = p
	m.rotation_degrees.y = rad_to_deg(atan2(face.x, face.z))
	m.pose_preview(pose, k)
	if pose == "windup":
		m.set_tint(Monster.WINDUP_TINT, 0.6 * k)
	if p.y < -0.2:
		_ripple(p, 0.4)
	_contents.append(m)
	return m


func _rats(p: Vector3, count: int, radius: float, seed_value: int) -> Node3D:
	var r := SewerProps.build("rat_swarm", {"count": count, "radius": radius, "seed": seed_value})
	p.y = _ground_y(p)
	_put(r, p, 0.0)
	if p.y < -0.2:
		r.position.y = SURFACE - 0.1
		_ripple(p, radius)
	_contents.append(r)
	return r


func _employee(style: String, variant: int, p: Vector3, face: Vector3, mood: String) -> Node3D:
	var e := EmployeeModel.new(style, variant)
	add_child(e)
	p.y = _ground_y(p)
	e.position = p
	e.rotation_degrees.y = rad_to_deg(atan2(face.x, face.z))
	e.pose_preview(mood, 0.6)
	_contents.append(e)
	return e


func _note(format: String, p: Vector3, yaw: float, lift: float = 0.0) -> Node3D:
	var n := NoteModels.build(format)
	return _put(n, Vector3(p.x, _ground_y(p) + lift, p.z), yaw)


## The gator: in the water (the round-1 placement, up on its legs in the murk) or on a dry deck (`land`).
func _gator2(p: Vector3, yaw: float, bend: float, jaw: float = 0.0, land: bool = false) -> Node3D:
	if not land:
		return _gator(p, yaw, bend, jaw)
	var gt := SewerProps.build("gator", {"bend": bend, "jaw": jaw})
	_put(gt, Vector3(p.x, 0.0, p.z), yaw)
	gt.scale = Vector3.ONE * GATOR_SCALE
	_contents.append(gt)
	return gt


func _sluice_at(door_cell: Vector2i, dir: int, open: float, width: float = 3.0) -> Node3D:
	var ax := Hex.dir_vector(dir)
	var p := Hex.to_world(door_cell) + ax * Hex.INNER
	var s := _put(SewerProps.build("sluice", {"width": width, "open": open}), Vector3(p.x, 0, p.z), yaw_to(ax))
	_plan_bar(p, ax, width + 0.4, C_SLUICE, 0.3)
	return s


func _arch_at(door_cell: Vector2i, dir: int, width: float) -> void:
	var ax := Hex.dir_vector(dir)
	_plan_bar(Hex.to_world(door_cell) + ax * Hex.INNER, ax, width, C_ARCH, 0.16)


# --------------------------------------------------------------------------- overlays

static func _unshaded(col: Color, depth_test: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = not depth_test
	m.render_priority = 6
	return m


func _mesh_node(st: SurfaceTool, mat: Material, into: Array[Node3D]) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	into.append(mi)
	return mi


## A flat band across a doorway (plan): `along` the passage axis, `width` across it.
func _plan_bar(p: Vector3, along: Vector3, width: float, col: Color, thick: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := Vector3(-along.z, 0, along.x) * width * 0.5
	var f := along * thick * 0.5
	var y := 0.9
	_quad(st, p - side - f + Vector3(0, y, 0), p + side - f + Vector3(0, y, 0), p + side + f + Vector3(0, y, 0), p - side + f + Vector3(0, y, 0), [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	_mesh_node(st, _unshaded(col, false), plan_nodes)


## A flat line strip through points (world X/Z at height y), optionally dashed, ending in an arrow head.
func _line_strip(pts: Array, col: Color, width: float, y: float, into: Array[Node3D], dashed: bool = false, head: bool = false, depth_test: bool = false) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		a.y = y
		b.y = y
		var seg := b - a
		var L := seg.length()
		if L < 0.001:
			continue
		var t := seg / L
		var n := Vector3(-t.z, 0, t.x) * width * 0.5
		if dashed:
			var s := 0.0
			while s < L:
				var e := minf(s + 0.45, L)
				var p0 := a + t * s
				var p1 := a + t * e
				_quad(st, p0 - n, p1 - n, p1 + n, p0 + n, [w, w, w, w])
				s += 0.8
		else:
			_quad(st, a - n, b - n, b + n, a + n, [w, w, w, w])
	if head and pts.size() >= 2:
		var b: Vector3 = pts[pts.size() - 1]
		var a: Vector3 = pts[pts.size() - 2]
		b.y = y
		a.y = y
		var t := (b - a).normalized()
		var n := Vector3(-t.z, 0, t.x)
		var tip := b + t * width * 2.2
		for idx in 3:
			st.set_color(w)
			st.set_normal(Vector3.UP)
			st.add_vertex([b - n * width * 1.8, tip, b + n * width * 1.8][idx])
	_mesh_node(st, _unshaded(col, depth_test), into)


func _circle(center: Vector3, radius: float, col: Color, width: float, y: float, into: Array[Node3D], dashed: bool = false) -> void:
	var pts: Array = []
	var n := 48
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector3(cos(a) * radius, 0, sin(a) * radius))
	_line_strip(pts, col, width, y, into, dashed)


func _disc(center: Vector3, radius: float, col: Color, y: float, into: Array[Node3D]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		for p: Vector3 in [center, center + Vector3(cos(a0), 0, sin(a0)) * radius, center + Vector3(cos(a1), 0, sin(a1)) * radius]:
			st.set_color(Color.WHITE)
			st.set_normal(Vector3.UP)
			st.add_vertex(Vector3(p.x, y, p.z))
	_mesh_node(st, _unshaded(col, false), into)


func _tag(p: Vector3, text: String, col: Color, into: Array[Node3D], size: int = 44, lift: float = 2.0) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = size
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.pixel_size = 0.026 if into == plan_nodes else 0.012
	lbl.modulate = col
	lbl.render_priority = 12
	lbl.outline_render_priority = 11
	add_child(lbl)
	lbl.position = p + Vector3(0, lift, 0)
	into.append(lbl)
	return lbl


## The gator's two radii round it (watch: faint, territory: the snap), drawn into `into`.
func _territory(p: Vector3, into: Array[Node3D]) -> void:
	var y := SURFACE + 0.05 if _ground_y(p) < -0.2 else 0.06
	_circle(p, TERRITORY, C_GATOR, 0.12, y, into, true)
	_circle(p, WATCH, Color(C_GATOR.r, C_GATOR.g, C_GATOR.b, 0.4), 0.06, y, into, true)


## The plan's floor fill: every kite coloured by what it is (water body, dry room deck, ledge in a wet hall, dry hall).
func _plan_fill() -> void:
	var cats := {"water": SurfaceTool.new(), "deck": SurfaceTool.new(), "ledge": SurfaceTool.new(), "dryhall": SurfaceTool.new()}
	for st: SurfaceTool in cats.values():
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wet_hall_cell := {}
	for hall_id: String in wet_halls:
		for c: Vector2i in hall_cells[hall_id]:
			wet_hall_cell[c] = true
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		if cell.type == HexMap.Tile.WALL:
			continue
		var free := HexMap.ALL_KITES & ~cell.wall_mask
		var water_m := free if wet.has(c) else (cell.pool_mask & free)
		var dry_m := 0 if wet.has(c) else (free & ~cell.pool_mask)
		var w := Hex.to_world(c)
		for k in 6:
			var cat := ""
			var y := 0.04
			if (water_m >> k) & 1 == 1:
				cat = "water"
				y = SURFACE + 0.03
			elif (dry_m >> k) & 1 == 1:
				if cell.tag == "corridor":
					cat = "ledge" if wet_hall_cell.has(c) else "dryhall"
				else:
					cat = "deck"
			if cat == "":
				continue
			var poly := _kite_poly(w, k)
			for idx: int in [0, 1, 2, 0, 2, 3]:
				(cats[cat] as SurfaceTool).set_color(Color.WHITE)
				(cats[cat] as SurfaceTool).set_normal(Vector3.UP)
				(cats[cat] as SurfaceTool).add_vertex(Vector3(poly[idx].x, y, poly[idx].y))
	var cols := {"water": C_WATER, "deck": C_DECK, "ledge": C_LEDGE, "dryhall": C_DRYHALL}
	for cat: String in cats:
		_mesh_node(cats[cat], _unshaded(cols[cat]), plan_nodes)
	for rec: Dictionary in bridges:
		var b: Node3D = rec["node"]
		var x := b.global_transform.basis.x.normalized()
		var z := b.global_transform.basis.z.normalized()
		var p := b.global_position
		var hl := float(rec["length"]) * 0.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y := Vector3(0, 0.95, 0)
		_quad(st, p - x * hl - z * 0.55 + y, p + x * hl - z * 0.55 + y, p + x * hl + z * 0.55 + y, p - x * hl + z * 0.55 + y, [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		_mesh_node(st, _unshaded(C_BRIDGE, false), plan_nodes)


## The fog spaces (RoomFog, unchanged): a cyan line on every hex edge between two spaces and each space's name.
func _plan_spaces() -> void:
	fog = RoomFog.build(map)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cen := {}
	for cc: Vector2i in map.cells:
		var s := fog.space_of_cell(cc)
		if s < 0:
			continue
		if not cen.has(s):
			cen[s] = [Vector3.ZERO, 0]
		cen[s][0] += Hex.to_world(cc)
		cen[s][1] = int(cen[s][1]) + 1
		for dd in 3:
			var nb: Vector2i = cc + Hex.DIRS[dd]
			if not map.has_cell(nb):
				continue
			var s2 := fog.space_of_cell(nb)
			if s2 < 0 or s2 == s:
				continue
			var w := Hex.to_world(cc)
			var e0 := w + Hex.kite_corner(posmod(dd - 1, 6))
			var e1 := w + Hex.kite_corner(dd)
			var t := (e1 - e0).normalized()
			var n := Vector3(-t.z, 0, t.x) * 0.08
			var y := Vector3(0, 1.0, 0)
			_quad(st, e0 - n + y, e1 - n + y, e1 + n + y, e0 + n + y, [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	_mesh_node(st, _unshaded(C_FOG, false), plan_nodes)
	for s: int in cen:
		var tag: String = fog.tags[s]
		var nm: String = room_names.get(tag, "")
		var p: Vector3 = (cen[s][0] as Vector3) / float(cen[s][1])
		if tag.begins_with("room"):
			_tag(p + Vector3(0, 0, -1.2), "%s\n%s" % [tag, nm], C_FOG, plan_nodes, 42, 2.5)
		else:
			var wet_n := 0
			var n_cells := 0
			for cc: Vector2i in fog.cell_space:
				if int(fog.cell_space[cc]) == s:
					n_cells += 1
					if wet.has(cc):
						wet_n += 1
			_tag(p, "%s (%s)" % [tag, "flooded hall" if wet_n > 0 else "dry hall"], Color(C_FOG.r, C_FOG.g, C_FOG.b, 0.8), plan_nodes, 36, 2.5)
	print("fog spaces: ", fog.tags, " doorways: ", fog.doorways.size())


func _legend(title: String) -> void:
	title_text = title
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.82)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	_corner(panel, legend_corner)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 26)
	vb.add_child(tl)
	var items := [
		[C_WATER, "water: one connected body (wading, 0.75x, soaked)"], [C_DECK, "dry room deck"],
		[C_LEDGE, "ledge (dry, in a flooded hall)"], [C_DRYHALL, "dry hall (outside the cluster)"],
		[C_BRIDGE, "grate bridge (a dry crossing)"], [C_SLUICE, "sluice gate (the sewer's door)"],
		[C_ARCH, "open arch (wide hall)"], [C_FOG, "fog-space edge (RoomFog)"],
		[C_GATOR, "gator: territory 3.0 (dashed), watch 4.5, bask spots, relocation"],
	]
	for it: Array in items:
		var hb := HBoxContainer.new()
		var sw := ColorRect.new()
		var c: Color = it[0]
		sw.color = Color(c.r, c.g, c.b, 1.0)
		sw.custom_minimum_size = Vector2(22, 14)
		hb.add_child(sw)
		var l := Label.new()
		l.text = "  " + str(it[1])
		l.add_theme_font_size_override("font_size", 18)
		hb.add_child(l)
		vb.add_child(hb)
	canvas.add_child(panel)
	legend = panel
	legend.visible = false


## Anchor a panel to a corner of the canvas (it grows away from that corner).
static func _corner(panel: Control, corner: String) -> void:
	var right := corner.ends_with("r")
	var bottom := corner.begins_with("b")
	panel.anchor_left = 1.0 if right else 0.0
	panel.anchor_right = panel.anchor_left
	panel.anchor_top = 1.0 if bottom else 0.0
	panel.anchor_bottom = panel.anchor_top
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	var m := 16.0
	panel.offset_left = -m if right else m
	panel.offset_right = panel.offset_left
	panel.offset_top = -m if bottom else m
	panel.offset_bottom = panel.offset_top


func _caption(text: String, corner: String = "tl") -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.8)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	caption = Label.new()
	caption.text = text
	caption.add_theme_font_size_override("font_size", 19)
	panel.add_child(caption)
	_corner(panel, corner)
	canvas.add_child(panel)


func _mode(plan: bool) -> void:
	for n in plan_nodes:
		n.visible = plan
	if legend != null:
		legend.visible = plan


func _views(game_at: Vector3, game2_at: Variant = null) -> void:
	var self_ref := self
	var off := func() -> void: self_ref._mode(false)
	var on := func() -> void: self_ref._mode(true)
	_view("game", GAME_SIZE, game_at, GAME_YAW, GAME_PITCH, off)
	if game2_at != null:
		_view("game2", GAME_SIZE, game2_at, GAME_YAW, GAME_PITCH, off)
	_view("plan", plan_size, plan_at, GAME_YAW, -89.5, on)


## Speed lines behind a shoved body (from `from` toward `dir`).
func _speed_lines(from: Vector3, dir: Vector3) -> void:
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.95, 0.85, 0.85)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var side := Vector3(-dir.z, 0, dir.x)
	for i in 3:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, 1.0)
		bar.mesh = bm
		bar.material_override = lm
		add_child(bar)
		var p := from + Vector3(0, 0.5 + 0.25 * float(i), 0) + side * (float(i) - 1.0) * 0.3
		bar.look_at_from_position(p, p + dir, Vector3.UP)
		fight_nodes.append(bar)


## A red slam ring (the brute's telegraph), filling.
func _slam_ring(p: Vector3, radius: float, fill: float) -> void:
	_circle(p, radius, Color(1.0, 0.15, 0.1, 1.0), 0.1, 0.05, fight_nodes)
	_disc(p, radius * fill, Color(1.0, 0.15, 0.1, 0.25), 0.04, fight_nodes)


func _glow_ball(p: Vector3, radius: float, col: Color, into: Array[Node3D]) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	add_child(mi)
	mi.position = p
	into.append(mi)
	return mi


# --------------------------------------------------------------------------- shared staging bits

func _begin(look_id: String) -> void:
	_set_look(look_id)
	flow_of = _flow_at


func _lbl(p: Vector3, text: String, col: Color, size: int = 34) -> void:
	_tag(p, text, col, plan_nodes, size, 1.4)


## A gator's plan marks: its territory and watch rings, its bask spots and the slow relocation route between them.
func _plan_gator(at: Vector3, spots: Array, route: Array) -> void:
	_territory(at, plan_nodes)
	for s: Vector3 in spots:
		_circle(s, 0.6, C_GATOR, 0.1, 1.0, plan_nodes)
	if route.size() >= 2:
		_line_strip(route, Color(C_GATOR.r, C_GATOR.g, C_GATOR.b, 0.9), 0.14, 1.0, plan_nodes, true, true)


func _plan_arrow(pts: Array, col: Color, width: float = 0.22) -> void:
	_line_strip(pts, col, width, 1.0, plan_nodes, false, true)


func _w(c: Vector2i, off: Vector3 = Vector3.ZERO) -> Vector3:
	return Hex.to_world(c) + off


func _bridge_cell(c: Vector2i, axis_dir: int, width: float = 1.3) -> Node3D:
	return _bridge_over(Hex.to_world(c), Hex.dir_vector(axis_dir), 4.2, width)


## A hero standing on a bridge deck (deck height, not in the water).
func _hero_on(which: String, p: Vector3, face: Vector3) -> LowPolyModel:
	return _hero(which, Vector3(p.x, 0.02, p.z), face)


# --------------------------------------------------------------------------- L1: the reclamation run (bunker, concrete)

## Intake (A) -> narrow flooded hall (sluice at both ends) -> settling cistern (B) -> ledged wide hall (open arches) ->
## pump room (C). The outfall in A's back corner feeds a channel that bends through A, runs the hall, crosses B through
## its sump, runs the wide hall's channel and ends in C's drain sump at the pumps. Dry halls lead in (to A, from the
## stair) and on (from C's north corner).
func _build_reclaim() -> Dictionary:
	_begin("concrete")
	var D := Hex.DIRS
	var a0 := Vector2i(0, 0)
	var b0 := a0 + D[1] * 16
	var c0 := b0 + D[1] * 16
	var s0 := a0 + D[4] * 11
	var e0 := c0 + D[2] * 11
	_room(a0, 5, "room:0")
	_room(b0, 5, "room:1")
	_room(c0, 5, "room:2")
	_room(s0, 2, "room:3")
	_room(e0, 2, "room:4")
	room_names = {"room:0": "A: intake", "room:1": "B: settling cistern", "room:2": "C: pump room", "room:3": "stair (dry)", "room:4": "way on (dry)"}
	var ab := _hall2("ab", a0 + D[1] * 5, 1, 6, 0)
	var bc := _hall2("bc", b0 + D[1] * 5, 1, 6, 1)
	_hall2("in", a0 + D[4] * 5, 4, 4, 0)
	_hall2("out", c0 + D[2] * 5, 2, 4, 0)
	_make_map()
	_wet_line(a0 + D[3] * 5, a0)
	_wet_line(a0, a0 + D[1] * 5)
	_flood_hall("ab")
	_wet_line(b0 + D[4] * 5, b0 + D[1] * 5)
	_flood(Hex.range_cells(b0, 2))
	_flood_wide("bc", bc, 1)
	_wet_line(c0 + D[4] * 5, c0 + D[1] * 2)
	_flood(Hex.range_cells(c0 + D[1] * 3, 1))
	_flow([a0 + D[3] * 5, a0, b0, c0, c0 + D[1] * 3])
	_finish()
	# --- dressing
	var into := Hex.dir_vector(0)
	var wall := Hex.to_world(a0 + D[3] * 5)
	_put(SewerProps.build("outfall", {"radius": 0.6, "drop": 1.0}), Vector3(wall.x, 0.0, wall.z) + into * 0.1, yaw_to(into))
	_put_wall(SewerProps.build("pipe_bundle", {"length": 5.0, "col": look["pipe"]}), a0, 5, 2, 0.5, 0.0)
	_put(PoolProps.build("valve_wheel"), _w(a0 + D[2] * 3 + D[1]), 0.0)
	_bridge_cell(a0 + D[1] * 3, 1)
	_bridge_cell(a0 + D[3] * 3, 0)
	_sluice_at(a0 + D[1] * 5, 1, 0.45)
	_sluice_at(b0 + D[4] * 5, 4, 0.45)
	_arch_at(b0 + D[1] * 5, 1, 4.5)
	_arch_at(c0 + D[4] * 5, 4, 4.5)
	_plan_bar(_w(a0 + D[4] * 5) + Hex.dir_vector(4) * Hex.INNER, Hex.dir_vector(4), 3.4, C_SLUICE, 0.3)
	_plan_bar(_w(c0 + D[2] * 5) + Hex.dir_vector(2) * Hex.INNER, Hex.dir_vector(2), 3.4, C_SLUICE, 0.3)
	_put(DecorModels.build("wet_floor_sign"), _w(a0 + D[4] * 4 + D[5]), 30.0)
	_shaft(_w(b0) + Vector3(0.3, FLOOR_Y, -0.2), 0.8)
	_put(SewerProps.build("duck"), Vector3(_w(b0).x - 1.0, SURFACE, _w(b0).z + 0.7), 70.0)
	_put(SewerProps.build("grate", {"size": 1.4}), _w(b0) + Vector3(0, FLOOR_Y + 0.01, 0), 15.0)
	_put(SewerProps.build("gas", {"radius": 0.8}), Vector3(_w(b0 + D[5]).x, SURFACE, _w(b0 + D[5]).z), 0.0)
	_bridge_cell(b0 + D[4] * 3, 1)
	_bridge_cell(b0 + D[1] * 3, 1)
	_put_wall(SewerProps.build("pipe_bundle", {"length": 4.0, "col": look["pipe"]}), b0, 5, 2, 0.0, 0.0)
	_put(DecorModels.build("crate_stack"), _w(b0 + D[5] * 3 + D[4]), 15.0)
	for i in [2, 4]:
		var c: Vector2i = bc[i] + D[2] * 2
		_put(SewerProps.build("springer", {"height": 1.5, "col": look["wall_base"]}), _w(c), yaw_to(-Hex.dir_vector(2) - Hex.dir_vector(1)))
	_put_wall(SewerProps.build("pump"), c0, 5, 1, -1.0, 0.6)
	_put_wall(SewerProps.build("pump", {"col": Color(0.55, 0.25, 0.2)}), c0, 5, 1, 1.0, 0.6)
	_put_wall(DecorModels.build("lab_console"), c0, 5, 2, 0.5, 0.6)
	_put_wall(SewerProps.build("junction_box", {"drop": Vector3(0.2, -1.25, 2.4)}), c0, 5, 1, -3.0, 0.0)
	_put(SewerProps.build("tool_cart"), _w(c0 + D[2] * 2 + D[1]), yaw_to(Hex.dir_vector(4)))
	_put_wall(PropModels.build("oil_drum"), c0, 5, 2, 2.6, 0.5)
	_put(SewerProps.build("grate", {"size": 1.6}), _w(c0 + D[1] * 3) + Vector3(0, FLOOR_Y + 0.01, 0), 0.0)
	_bridge_cell(c0 + D[4] * 3, 1)
	return {"a0": a0, "b0": b0, "c0": c0, "s0": s0, "e0": e0, "ab": ab, "bc": bc}


func _stage_reclaim(L: Dictionary) -> void:
	var D := Hex.DIRS
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var c0: Vector2i = L["c0"]
	var bc: Array[Vector2i] = L["bc"]
	_hero_at("gasket", _w(a0 + D[5] * 2), Hex.dir_vector(1))
	_hero_on("wick", _w(a0 + D[1] * 3), Hex.dir_vector(1))
	_hero_at("rebar", _w(a0 + D[1] * 4, Vector3(0.2, 0, 0.1)), Hex.dir_vector(1))
	_rats(_w(a0 + D[2] * 3), 8, 0.8, 4)
	_note("sign", _w(a0 + D[4] * 3 + D[5]), yaw_to(Hex.dir_vector(1)))
	_mon("grunt", _w(a0 + D[1] * 9), Hex.dir_vector(4))
	_gator2(_w(b0, Vector3(0.3, 0, 0.2)), yaw_to(Hex.dir_vector(3)), 25.0)
	_mon("grunt", _w(b0 + D[2] * 3), Hex.dir_vector(4))
	_mon("grunt", _w(b0 + D[3] * 3), Hex.dir_vector(4))
	_mon("grunt", _w(b0 + D[5] * 3), Hex.dir_vector(4))
	_mon("archer", _w(b0 + D[2] * 4), Hex.dir_vector(4))
	_mon("goblin", _ledge(bc[3]), Hex.dir_vector(1))
	_mon("brute", _w(c0 + D[3] * 2 + D[2]), Hex.dir_vector(4))
	_mon("archer", _w(c0 + D[2] * 3 + D[3]), Hex.dir_vector(4))
	_mon("archer", _w(c0 + D[3] * 3 + D[2]), Hex.dir_vector(4))
	_employee("staff", 1, _w(c0 + D[2] * 3 + D[1], Vector3(0.3, 0, -0.2)), Hex.dir_vector(4), "cower")
	_note("report", _w(c0 + D[2] * 2 + D[1]) + Vector3(0, 0.73, 0), 20.0)


func _case_reclaim() -> void:
	var L := _build_reclaim()
	_stage_reclaim(L)
	var D := Hex.DIRS
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var c0: Vector2i = L["c0"]
	var s0: Vector2i = L["s0"]
	var bc: Array[Vector2i] = L["bc"]
	_plan_fill()
	_plan_spaces()
	_plan_arrow([_w(s0), _w(a0 + D[4] * 4), _w(a0 + D[5] * 2)], C_CREW)
	_lbl(_w(s0 + D[5]), "CREW IN (dry stair)", C_CREW, 40)
	_lbl(_w(a0 + D[2] * 3), "rats (swarm) on the intake deck", C_MON)
	_lbl(_w(a0 + D[3] * 4 + D[2]), "outfall (source)", C_NOTE)
	_lbl(_w(a0 + D[4] * 3 + D[5] + D[5]), "note: RECLAIMED WATER, DO NOT DRINK", C_NOTE)
	_lbl(_w(a0 + D[1] * 9 + D[5]), "skeleton wading the hall", C_MON)
	_lbl(_w(b0 + D[2] * 4 + D[3]), "skeletons x3 on the decks, archer north", C_MON)
	_lbl(_w(b0 + D[5] * 2 + D[0]), "gas pocket (sump)", C_HAZ)
	_lbl(_w(bc[3] + D[2] * 2), "goblin scout on the ledge", C_MON)
	_lbl(_w(c0 + D[3] * 3 + D[4]), "brute + 2 archers on the pump deck", C_MON)
	_lbl(_w(c0 + D[2] * 4 + D[1]), "Stan (maintenance), cowering by the pumps", C_EMP)
	_lbl(_w(c0 + D[1] * 3 + D[0] * 2), "live wire over the drain sump\nsump pumps $3,500 x2", C_HAZ)
	_lbl(_w(c0 + D[3] * 4 + D[4]), "oil drum (north wall)", C_HAZ)
	_lbl(_w(c0 + D[2] * 1 + D[1]), "note: pump log (on the cart)", C_NOTE)
	_lbl(_w(c0 + D[5] * 3), "C's south deck: reached by the bridge", C_DECK)
	var g := _w(b0, Vector3(0.3, 0, 0.2))
	_plan_gator(g, [_w(b0 + D[5] * 3 + D[0]), _w(bc[4])], [g, _w(b0 + D[1] * 3), _w(bc[4])])
	_lbl(g + Vector3(0, 0, 1.8), "GATOR: home in the sump", C_GATOR, 40)
	plan_size = 54.0
	plan_at = (_w(a0) + _w(c0)) * 0.5 + Vector3(-1.5, 0, 1.5)
	legend_corner = "br"
	_legend("L1  Reclamation run  (bunker, concrete)")
	_views((_w(a0) + _w(b0)) * 0.5 + Vector3(0, 0, 1.0), (_w(b0) + _w(c0)) * 0.5 + Hex.dir_vector(1) * 6.0 + Vector3(0, 0, 1.0))


func _bars_at(c: Vector2i, dir: int, width: float = 2.8) -> void:
	_put(SewerProps.build("bars", {"width": width, "height": 1.3}), _w(c) + Vector3(0, FLOOR_Y, 0), yaw_to(Hex.dir_vector(dir)))


func _eel(c: Vector2i, dir: int, off: Vector3 = Vector3.ZERO, phase: float = 0.8) -> Node3D:
	var e := PoolProps.build("eel", {"phase": phase})
	_put(e, _w(c) + off + Vector3(0, SURFACE - 0.02, 0), yaw_to(Hex.dir_vector(dir)))
	_contents.append(e)
	return e


func _outfall_at(corner: Vector2i, into_dir: int, radius: float = 0.6, drop: float = 1.0) -> void:
	var into := Hex.dir_vector(into_dir)
	var wall := _w(corner)
	_put(SewerProps.build("outfall", {"radius": radius, "drop": drop}), Vector3(wall.x, 0.0, wall.z) + into * 0.1, yaw_to(into))


# --------------------------------------------------------------------------- L2: the Y junction (lair, brick)

## A drain junction (J) where three flooded narrow halls meet over a sump; each hall runs to a small room whose channel
## crosses it and leaves through a barred culvert (the pump post, the storeroom) or starts at the source (the aquarium
## overflow). The crew comes in dry, down a wide hall, onto J's south wedge.
func _build_junction() -> Dictionary:
	_begin("brick")
	var D := Hex.DIRS
	var j0 := Vector2i(0, 0)
	var e := j0 + D[0] * 13
	var n := j0 + D[2] * 13
	var w := j0 + D[4] * 13
	var s := j0 + D[5] * 10
	_room(j0, 5, "room:0")
	_room(e, 3, "room:1")
	_room(n, 3, "room:2")
	_room(w, 3, "room:3")
	_room(s, 2, "room:4")
	room_names = {"room:0": "J: drain junction", "room:1": "E: pump post", "room:2": "N: aquarium overflow", "room:3": "W: storeroom", "room:4": "landing (dry)"}
	for d: int in [0, 2, 4]:
		_hall2("h%d" % d, j0 + D[d] * 5, d, 5, 0)
	_hall2("in", j0 + D[5] * 5, 5, 3, 1)
	_make_map()
	_flood(Hex.range_cells(j0, 1))
	for d: int in [0, 2, 4]:
		_wet_line(j0, j0 + D[d] * 5)
		_flood_hall("h%d" % d)
	_wet_line(e - D[0] * 3, e + D[0] * 3)
	_wet_line(n - D[2] * 3, n + D[2] * 3)
	_wet_line(w - D[4] * 3, w + D[4] * 3)
	_flow([n + D[2] * 3, j0])
	_flow([e + D[0] * 3, j0])
	_flow([w + D[4] * 3, j0])
	_finish()
	_put(SewerProps.build("grate", {"size": 1.8}), _w(j0) + Vector3(0, FLOOR_Y + 0.01, 0), 30.0)
	_shaft(_w(j0) + Vector3(0.4, FLOOR_Y, -0.3), 0.8)
	for d: int in [0, 2, 4]:
		_bridge_cell(j0 + D[d] * 3, d)
		_sluice_at(j0 + D[d] * 5, d, 0.45)
	_sluice_at(e - D[0] * 3, 3, 0.45)
	_sluice_at(n - D[2] * 3, 5, 0.45)
	_sluice_at(w - D[4] * 3, 1, 0.45)
	_arch_at(j0 + D[5] * 5, 5, 4.5)
	_put(SewerProps.build("ladder_wall", {"height": 1.6}), _wall_spot(j0, 5, 2, 0.0, 0.05)[0], _wall_spot(j0, 5, 2, 0.0, 0.05)[1])
	_put_wall(SewerProps.build("pipe_bundle", {"length": 4.0, "col": look["pipe"]}), j0, 5, 3, 0.0, 0.0)
	_put_wall(SewerProps.build("pipe_bundle", {"length": 4.0, "col": look["pipe"]}), j0, 5, 1, 0.0, 0.0)
	_put(SewerProps.build("duck"), Vector3(_w(j0 + D[2] * 2).x, SURFACE, _w(j0 + D[2] * 2).z), 40.0)
	# E: the pump post
	_bridge_cell(e, 0)
	_bars_at(e + D[0] * 3, 0)
	_put_wall(SewerProps.build("pump"), e, 3, 1, 0.0, 0.6)
	_put_wall(PropModels.build("henchman_locker"), e, 3, 2, 0.0, 0.45)
	_put(PoolProps.build("valve_wheel"), _w(e + D[2] * 2), 0.0)
	_put(DecorModels.build("barrel"), _w(e + D[5] * 2 + D[0] * 0), 0.0)
	# N: the aquarium overflow (the source): the cracked tank pours into the channel's head
	_bridge_cell(n, 2)
	_outfall_at(n + D[2] * 3, 5, 0.5, 1.2)
	_put_wall(PropModels.build("shark_tank"), n, 3, 1, 0.9, 0.7)
	_put_wall(PropModels.build("shark_tank"), n, 3, 2, -0.9, 0.7)
	_put_wall(PropModels.build("specimen_vat"), n, 3, 3, 0.0, 0.6)
	# W: the storeroom (drums on the decks, crates)
	_bridge_cell(w, 4)
	_bars_at(w + D[4] * 3, 4)
	_put_wall(PropModels.build("oil_drum"), w, 3, 2, 0.6, 0.5)
	_put_wall(PropModels.build("oil_drum"), w, 3, 2, -0.6, 0.5)
	_put_wall(PropModels.build("gas_cylinders"), w, 3, 3, 0.4, 0.5)
	_put(DecorModels.build("crate_stack"), _w(w + D[5] * 2), 10.0)
	return {"j0": j0, "e": e, "n": n, "w": w, "s": s}


func _stage_junction(L: Dictionary) -> void:
	var D := Hex.DIRS
	var j0: Vector2i = L["j0"]
	var e: Vector2i = L["e"]
	var n: Vector2i = L["n"]
	var w: Vector2i = L["w"]
	_hero_at("rebar", _w(j0 + D[5] * 3 + D[0]), Hex.dir_vector(1))
	_hero_at("wick", _w(j0 + D[5] * 4), Hex.dir_vector(2))
	_hero_at("gasket", _w(j0 + D[5] * 3 + D[4]), Hex.dir_vector(2))
	_gator2(_w(j0, Vector3(0.2, 0, 0.1)), yaw_to(Hex.dir_vector(4)), 30.0)
	_mon("grunt", _w(j0 + D[1] * 3), Hex.dir_vector(4))
	_mon("grunt", _w(j0 + D[1] * 2 + D[2]), Hex.dir_vector(4))
	_mon("grunt", _w(j0 + D[1] * 4 + D[0]), Hex.dir_vector(4))
	_mon("grunt", _w(j0 + D[0] * 4, Vector3(0.0, 0, 0.2)), Hex.dir_vector(3))
	_mon("archer", _w(j0 + D[3] * 3 + D[2]), Hex.dir_vector(5))
	_mon("archer", _w(e + D[1] * 2), Hex.dir_vector(4))
	_mon("archer", _w(e + D[5] * 2 + D[4]), Hex.dir_vector(3))
	_employee("henchman", 2, _w(e + D[2] * 2 + D[1], Vector3(0.2, 0, 0.2)), Hex.dir_vector(4), "stand")
	_note("memo", _w(e + D[5] * 2) + Vector3(0, 0.9, 0), 15.0)
	_rats(_w(n + D[3] * 2), 9, 0.8, 7)
	_eel(n + D[5], 2, Vector3(0.2, 0, 0))
	_note("complaint", _w(n + D[0] * 2), 200.0)
	_mon("brute", _w(w + D[2] * 2), Hex.dir_vector(1))
	_note("sign", _w(j0 + D[5] * 4 + D[4]), yaw_to(Hex.dir_vector(1)))


func _case_junction() -> void:
	var L := _build_junction()
	_stage_junction(L)
	var D := Hex.DIRS
	var j0: Vector2i = L["j0"]
	var e: Vector2i = L["e"]
	var n: Vector2i = L["n"]
	var w: Vector2i = L["w"]
	var s: Vector2i = L["s"]
	_plan_fill()
	_plan_spaces()
	_plan_arrow([_w(s), _w(j0 + D[5] * 4)], C_CREW)
	_lbl(_w(s + D[0]), "CREW IN (dry wide hall)", C_CREW, 40)
	_lbl(_w(j0 + D[1] * 3 + D[2] * 2), "skeletons x3 on the NE wedge, 1 wading", C_MON)
	_lbl(_w(j0 + D[3] * 5 + D[4] * 2), "archer on the NW wedge", C_MON)
	_lbl(_w(e + D[1] * 4 + D[2]), "2 archers + Gary (Henchman 1) on pump duty", C_EMP)
	_lbl(_w(e + D[5] * 3), "memo: gator feeding rota", C_NOTE)
	_lbl(_w(n + D[2] * 4), "cracked aquarium $7,000 pours in (source)", C_HAZ)
	_lbl(_w(n + D[3] * 3), "rats + an escaped eel", C_MON)
	_lbl(_w(w + D[3] * 3), "brute by the oil drums + gas cylinders", C_HAZ)
	_lbl(_w(j0 + D[5] * 4 + D[4] * 4), "note: DO NOT FEED THE GATOR", C_NOTE)
	_lbl(_w(e + D[0] * 4 + D[1] * 2), "culvert (bars): water on", C_NOTE)
	_lbl(_w(w + D[4] * 4), "culvert (bars)", C_NOTE)
	var g := _w(j0, Vector3(0.2, 0, 0.1))
	_plan_gator(g, [_w(j0 + D[3] * 3 + D[4]), _w(j0 + D[2] * 8)], [g, _w(j0 + D[2] * 3), _w(j0 + D[2] * 8)])
	_lbl(_w(j0 + D[0] * 3 + D[5] * 2), "GATOR: home in the drain sump", C_GATOR, 40)
	plan_size = 56.0
	plan_at = _w(j0) + Vector3(-1.0, 0, -2.0)
	legend_corner = "tl"
	_legend("L2  The Y junction  (lair, brick)")
	_views(_w(j0) + Vector3(0, 0, 1.0))


# --------------------------------------------------------------------------- L3: the aquarium overflow (lair, toxic)

## The villain's aquarium gallery (A): a cracked tank pours into an overflow basin whose channel bends out through A's
## east corner into a ledged wide hall, then rings an island in the filtration room (B) and leaves down a flooded narrow
## hall to a weir. The crew comes in dry from A's south corner.
func _build_aquarium() -> Dictionary:
	_begin("toxic")
	var D := Hex.DIRS
	var a0 := Vector2i(0, 0)
	var b0 := a0 + D[1] * 17
	var s0 := a0 + D[5] * 9
	var r3 := b0 + D[1] * 10
	_room(a0, 5, "room:0")
	_room(b0, 5, "room:1")
	_room(s0, 2, "room:2")
	_room(r3, 2, "room:3")
	room_names = {"room:0": "A: aquarium gallery", "room:1": "B: filtration", "room:2": "landing (dry)", "room:3": "weir"}
	var ab := _hall2("ab", a0 + D[1] * 5, 1, 7, 1)
	_hall2("in", a0 + D[5] * 5, 5, 2, 0)
	_hall2("out", b0 + D[1] * 5, 1, 3, 0)
	_make_map()
	_flood(Hex.range_cells(a0 + D[2] * 3, 1))
	_wet_line(a0 + D[2] * 2, a0)
	_wet_line(a0, a0 + D[1] * 5)
	_flood_wide("ab", ab, 1)
	_wet_line(b0 + D[4] * 5, b0 + D[4] * 2)
	_flood(Hex.ring(b0, 2))
	_wet_line(b0 + D[1] * 2, b0 + D[1] * 5)
	_flood_hall("out")
	_flood(Hex.range_cells(r3, 1))
	_flow([a0 + D[2] * 4, a0, b0 + D[4] * 2, b0 + D[2] * 2 + D[4] * 0, b0 + D[1] * 2, r3])
	_flow([b0 + D[4] * 2, b0 + D[5] * 2, b0 + D[0] * 2, b0 + D[1] * 2])
	_finish()
	_outfall_at(a0 + D[2] * 5, 5, 0.55, 1.3)
	_put_wall(PropModels.build("shark_tank"), a0, 5, 1, 2.2, 0.7)
	_put_wall(PropModels.build("shark_tank"), a0, 5, 2, -2.2, 0.7)
	_put_wall(PropModels.build("shark_tank"), a0, 5, 2, 0.4, 0.7)
	_put_wall(PropModels.build("specimen_vat"), a0, 5, 3, 0.0, 0.6)
	_put_wall(SewerProps.build("junction_box", {"drop": Vector3(0.2, -1.25, 2.6), "dropped": wire_down}), a0, 5, 1, -2.4, 0.0)
	_bridge_cell(a0 + D[1] * 3, 1)
	_arch_at(a0 + D[1] * 5, 1, 4.5)
	_arch_at(b0 + D[4] * 5, 4, 4.5)
	_plan_bar(_w(a0 + D[5] * 5) + Hex.dir_vector(5) * Hex.INNER, Hex.dir_vector(5), 3.4, C_SLUICE, 0.3)
	_sluice_at(b0 + D[1] * 5, 1, 0.45)
	_sluice_at(r3 - D[1] * 2, 4, 0.45)
	_bars_at(r3 + D[1] * 2, 1, 2.6)
	_bridge_cell(b0 + D[2] * 2 + D[4], 1)
	_bridge_cell(b0 + D[5] * 2 + D[1], 1)
	_put(DecorModels.build("lab_console"), _w(b0, Vector3(0.0, 0, 0.0)), yaw_to(Hex.dir_vector(5)))
	_put_wall(PropModels.build("gas_cylinders"), b0, 5, 2, 1.0, 0.5)
	_put_wall(SewerProps.build("pipe_bundle", {"length": 5.0, "col": look["pipe"]}), b0, 5, 1, 0.0, 0.0)
	_put(SewerProps.build("gas", {"radius": 0.7}), Vector3(_w(b0 + D[0] * 2).x, SURFACE, _w(b0 + D[0] * 2).z), 0.0)
	for i in [2, 5]:
		_put(SewerProps.build("springer", {"height": 1.5, "col": look["wall_base"]}), _w(ab[i] + D[2] * 2), yaw_to(-Hex.dir_vector(2) - Hex.dir_vector(1)))
	return {"a0": a0, "b0": b0, "s0": s0, "r3": r3, "ab": ab}


func _stage_aquarium(L: Dictionary) -> void:
	var D := Hex.DIRS
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var ab: Array[Vector2i] = L["ab"]
	_hero_at("gasket", _w(a0 + D[5] * 3), Hex.dir_vector(2))
	_hero_at("wick", _w(a0 + D[5] * 2 + D[4]), Hex.dir_vector(2), "shoot")
	_hero_at("rebar", _w(a0 + D[0] * 2 + D[5]), Hex.dir_vector(1))
	_eel(a0 + D[1] * 2, 1, Vector3(0.1, 0, 0.1))
	_eel(a0 + D[2] * 3, 4, Vector3(0.3, 0, 0), 0.2)
	_mon("archer", _w(a0 + D[3] * 3 + D[2]), Hex.dir_vector(5))
	_mon("archer", _w(a0 + D[3] * 2 + D[4]), Hex.dir_vector(0))
	_mon("grunt", _w(a0 + D[1] * 2 + D[2], Vector3(0.0, 0, 0.0)), Hex.dir_vector(4))
	_mon("grunt", _w(a0 + D[1] * 4, Vector3(0.2, 0, 0.0)), Hex.dir_vector(4))
	_employee("henchman", 5, _w(a0 + D[3] * 4 + D[2]), Hex.dir_vector(0), "panic")
	_note("complaint", _w(a0 + D[4] * 3 + D[5]), 30.0)
	_mon("goblin", _ledge(ab[4]), Hex.dir_vector(4))
	_mon("brute", _w(b0 + D[3], Vector3(-0.2, 0, 0.1)), Hex.dir_vector(4))
	_gator2(_w(b0 + D[5] * 3 + D[4], Vector3(0.0, 0, 0.0)), yaw_to(Hex.dir_vector(1)) + 20.0, -20.0, 0.0, true)
	_rats(_w(b0 + D[2] * 3 + D[3]), 7, 0.7, 5)


func _case_aquarium() -> void:
	var L := _build_aquarium()
	_stage_aquarium(L)
	var D := Hex.DIRS
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var s0: Vector2i = L["s0"]
	var ab: Array[Vector2i] = L["ab"]
	_plan_fill()
	_plan_spaces()
	_plan_arrow([_w(s0), _w(a0 + D[5] * 3)], C_CREW)
	_lbl(_w(s0 + D[0] * 2), "CREW IN (dry)", C_CREW, 40)
	_lbl(_w(a0 + D[2] * 5 + D[3]), "cracked aquarium (source); tanks $7,000 x3", C_HAZ)
	_lbl(_w(a0 + D[3] * 4 + D[4]), "2 archers + Keith (Henchman 10), panicking", C_MON)
	_lbl(_w(a0 + D[1] * 3 + D[5] * 2), "skeleton + skeleton wading; 2 eels in the channel", C_MON)
	_lbl(_w(a0 + D[1] * 3 + D[2] * 2), "live wire: junction box over the channel", C_HAZ)
	_lbl(_w(a0 + D[4] * 4 + D[5]), "note: complaint about the gator in the tank", C_NOTE)
	_lbl(_w(ab[4] + D[2] * 2), "goblin scout on the ledge", C_MON)
	_lbl(_w(b0 + D[2] * 4), "brute on the filter island", C_MON)
	_lbl(_w(b0 + D[0] * 3), "gas pocket; gas cylinders N", C_HAZ)
	_lbl(_w(b0 + D[2] * 4 + D[3]), "rats", C_MON)
	var g := _w(b0 + D[5] * 3 + D[4])
	_plan_gator(g, [_w(b0 + D[0] * 2), _w(ab[3])], [g, _w(b0 + D[5] * 2), _w(b0 + D[0] * 2)])
	_lbl(g + Vector3(0, 0, 2.2), "GATOR: basking on the south deck (on land)", C_GATOR, 40)
	plan_size = 42.0
	plan_at = (_w(a0) + _w(b0)) * 0.5 + Vector3(1.0, 0, 2.0)
	legend_corner = "br"
	_legend("L3  Aquarium overflow  (lair, toxic)")
	_views(_w(a0) + Hex.dir_vector(1) * 9.0 + Vector3(0, 0, 1.0), _w(b0) + Vector3(-2.0, 0, 1.0))


# --------------------------------------------------------------------------- L4: the storm-drain loop (bunker, concrete)

## Four rooms in a ring. Two ledged wide halls (the dry long way round) and two fully flooded narrow halls (the wet short
## way). The water comes in at the overflow chamber's outfall (P0) and runs both ways round to the grit chamber's drain
## (P2). The gator relocates round the ring.
func _build_loop() -> Dictionary:
	_begin("concrete")
	var D := Hex.DIRS
	var p0 := Vector2i(0, 0)
	var p1 := p0 + D[1] * 14
	var p2 := p1 + D[2] * 12
	var p3 := p0 + D[2] * 12
	var s0 := p0 + D[4] * 9
	_room(p0, 4, "room:0")
	_room(p1, 4, "room:1")
	_room(p2, 4, "room:2")
	_room(p3, 4, "room:3")
	_room(s0, 2, "room:4")
	room_names = {"room:0": "P0: overflow chamber", "room:1": "P1: valve room", "room:2": "P2: grit chamber", "room:3": "P3: generator nook", "room:4": "landing (dry)"}
	var h01 := _hall2("h01", p0 + D[1] * 4, 1, 6, 1)
	var h32 := _hall2("h32", p3 + D[1] * 4, 1, 6, 1)
	var h03 := _hall2("h03", p0 + D[2] * 4, 2, 4, 0)
	var h12 := _hall2("h12", p1 + D[2] * 4, 2, 4, 0)
	_hall2("in", p0 + D[4] * 4, 4, 3, 0)
	_make_map()
	_wet_line(p0 + D[2] * 4, p0 + D[1] * 4)
	_wet_line(p0 + D[2] * 3, p0 + D[1] * 3)
	_flood_wide("h01", h01, 1)
	_flood_wide("h32", h32, 1)
	_flood_hall("h03")
	_flood_hall("h12")
	_wet_line(p1 + D[4] * 4, p1)
	_wet_line(p1, p1 + D[2] * 4)
	_wet_line(p2 + D[5] * 4, p2 + D[4] * 4)
	_wet_line(p2 + D[5] * 3, p2 + D[4] * 3)
	_wet_line(p3 + D[5] * 4, p3)
	_wet_line(p3, p3 + D[1] * 4)
	_flow([p0 + D[2] * 3 + D[0] * 1, p0 + D[1] * 3, p1, p1 + D[2] * 4, p2 + D[5] * 3, p2 + D[5] * 3 + D[3] * 1])
	_flow([p0 + D[2] * 3 + D[0] * 1, p0 + D[2] * 3, p3 + D[5] * 4, p3, p3 + D[1] * 4, p2 + D[4] * 3, p2 + D[5] * 3 + D[3] * 2])
	_finish()
	_put_wall(SewerProps.build("outfall", {"radius": 0.6, "drop": 1.0}), p0, 4, 1, 0.0, 0.0)
	_put(DecorModels.build("wet_floor_sign"), _w(p0 + D[4] * 2 + D[5]), 20.0)
	_sluice_at(p0 + D[2] * 4, 2, 0.45)
	_sluice_at(p3 + D[5] * 4, 5, 0.45)
	_sluice_at(p1 + D[2] * 4, 2, 0.45)
	_sluice_at(p2 + D[5] * 4, 5, 0.45)
	_arch_at(p0 + D[1] * 4, 1, 4.5)
	_arch_at(p1 + D[4] * 4, 4, 4.5)
	_arch_at(p3 + D[1] * 4, 1, 4.5)
	_arch_at(p2 + D[4] * 4, 4, 4.5)
	_plan_bar(_w(p0 + D[4] * 4) + Hex.dir_vector(4) * Hex.INNER, Hex.dir_vector(4), 3.4, C_SLUICE, 0.3)
	# P1: the valve room (pipes, the steam valve, a pump, the tool cart)
	_bridge_cell(p1 + D[4] * 2, 1)
	_bridge_cell(p1 + D[2] * 2, 2)
	_put_wall(SewerProps.build("pipe_bundle", {"length": 5.0, "col": look["pipe"]}), p1, 4, 0, 0.0, 0.0)
	_put_wall(SewerProps.build("pump"), p1, 4, 5, 0.6, 0.6)
	_put(SewerProps.build("tool_cart"), _w(p1 + D[0] * 2 + D[5]), yaw_to(Hex.dir_vector(3)))
	_put(PoolProps.build("valve_wheel"), _w(p1 + D[0] * 2 + D[1]), 0.0)
	# P2: the grit chamber (the drain, crates of grit)
	_put(SewerProps.build("grate", {"size": 1.6}), _w(p2 + D[5] * 3 + D[3] * 2) + Vector3(0, FLOOR_Y + 0.01, 0), 0.0)
	_put(DecorModels.build("crate_stack"), _w(p2 + D[2] * 2 + D[1]), 25.0)
	_put(DecorModels.build("crate_stack"), _w(p2 + D[1] * 2 + D[0]), -15.0)
	# P3: the generator nook
	_bridge_cell(p3 + D[5] * 2, 2)
	_bridge_cell(p3 + D[1] * 2, 1)
	_put_wall(PropModels.build("propane_tank"), p3, 4, 2, 0.6, 0.55)
	_put_wall(PropModels.build("oil_drum"), p3, 4, 3, 0.0, 0.5)
	_put_wall(DecorModels.build("rack_cab"), p3, 4, 2, -1.2, 0.45)
	return {"p0": p0, "p1": p1, "p2": p2, "p3": p3, "s0": s0, "h01": h01, "h32": h32, "h03": h03, "h12": h12}


func _stage_loop(L: Dictionary) -> void:
	var D := Hex.DIRS
	var p0: Vector2i = L["p0"]
	var p1: Vector2i = L["p1"]
	var p2: Vector2i = L["p2"]
	var p3: Vector2i = L["p3"]
	var h01: Array[Vector2i] = L["h01"]
	var h12: Array[Vector2i] = L["h12"]
	_hero_at("gasket", _w(p0 + D[0] * 1), Hex.dir_vector(1))
	_hero_at("wick", _w(p0 + D[5] * 1), Hex.dir_vector(2))
	_hero_at("rebar", _w(p0 + D[0] * 2 + D[1]), Hex.dir_vector(1))
	_note("sign", _w(p0 + D[4] * 2), yaw_to(Hex.dir_vector(1)))
	_mon("goblin", _ledge(h01[3]), Hex.dir_vector(4))
	_mon("grunt", _w(p1 + D[3] * 2), Hex.dir_vector(4))
	_mon("grunt", _w(p1 + D[3] * 2 + D[2]), Hex.dir_vector(4))
	_employee("staff", 3, _w(p1 + D[0] * 2), Hex.dir_vector(3), "panic")
	_gator2(_w(h12[2], Vector3(0.2, 0, 0)), yaw_to(Hex.dir_vector(5)), 15.0)
	_mon("brute", _w(p2 + D[1] * 2), Hex.dir_vector(4))
	_rats(_w(p2 + D[2] * 2 + D[3]), 8, 0.8, 9)
	_mon("archer", _w(p3 + D[3] * 2 + D[2]), Hex.dir_vector(0))
	_mon("archer", _w(p3 + D[3] * 2), Hex.dir_vector(0))


func _case_loop() -> void:
	var L := _build_loop()
	_stage_loop(L)
	var D := Hex.DIRS
	var p0: Vector2i = L["p0"]
	var p1: Vector2i = L["p1"]
	var p2: Vector2i = L["p2"]
	var p3: Vector2i = L["p3"]
	var s0: Vector2i = L["s0"]
	var h01: Array[Vector2i] = L["h01"]
	var h32: Array[Vector2i] = L["h32"]
	var h03: Array[Vector2i] = L["h03"]
	var h12: Array[Vector2i] = L["h12"]
	_plan_fill()
	_plan_spaces()
	_plan_arrow([_w(s0), _w(p0 + D[4] * 2 + D[5])], C_CREW)
	_lbl(_w(s0 + D[5]), "CREW IN", C_CREW, 40)
	_lbl(_w(p0 + D[1] * 4 + D[2] * 2), "outfall (source)", C_NOTE)
	_lbl(_w(p0 + D[4] * 3 + D[5] * 2), "note: LEVEL RISES WITHOUT WARNING", C_NOTE)
	_lbl(_w(h01[3] + D[2] * 3), "dry long way: ledge (goblin scout)", C_LEDGE)
	_lbl(_w(h03[2] + D[3] * 2), "wet short way (sluices)", C_WATER)
	_lbl(_w(p1 + D[3] * 3 + D[4]), "skeletons x2", C_MON)
	_lbl(_w(p1 + D[0] * 3), "Doug (pumps), panicking; steam valve on the pipes", C_EMP)
	_lbl(_w(p2 + D[1] * 3 + D[2]), "brute + rats; the drain", C_MON)
	_lbl(_w(p3 + D[2] * 3 + D[1]), "2 archers; propane tank + oil drum", C_HAZ)
	var g := _w(h12[2], Vector3(0.2, 0, 0))
	_plan_gator(g, [_w(p0 + D[2] * 3 + D[0] * 2), _w(h32[3]), _w(p1 + D[2] * 2 + D[3])], [g, _w(p2 + D[5] * 3), _w(p2 + D[4] * 3), _w(h32[3]), _w(p3), _w(h03[2]), _w(p0 + D[2] * 3 + D[0] * 2)])
	_lbl(g + Vector3(2.2, 0, 0.5), "GATOR in the wet shortcut;\nrelocates round the ring", C_GATOR, 40)
	plan_size = 48.0
	plan_at = (_w(p0) + _w(p2)) * 0.5 + Vector3(-5.6, 0, 6.6)
	legend_corner = "tl"
	_legend("L4  Storm-drain loop  (bunker, concrete)")
	_views((_w(p0) + _w(p2)) * 0.5 + Vector3(0, 0, 1.0))


# --------------------------------------------------------------------------- L5: the sewer main (lair, brick)

## A grand cistern (A) and an outfall gallery (B) joined by a 6.0 main: a 3.0 channel with a dry ledge each side and a
## grate bridge halfway. The channel runs the length of A from an outfall on A's west wall, through a big sump, along the
## main, across B and out through a barred culvert.
func _build_main() -> Dictionary:
	_begin("brick")
	var D := Hex.DIRS
	var a0 := Vector2i(0, 0)
	var b0 := a0 + D[1] * 24
	var s0 := a0 + D[5] * 10
	var e0 := b0 + D[2] * 10
	_room(a0, 6, "room:0")
	_room(b0, 5, "room:1")
	_room(s0, 2, "room:2")
	_room(e0, 2, "room:3")
	room_names = {"room:0": "A: grand cistern", "room:1": "B: outfall gallery", "room:2": "landing (dry)", "room:3": "way on (dry)"}
	var mn := _hall2("main", a0 + D[1] * 6, 1, 13, 2)
	_hall2("in", a0 + D[5] * 6, 5, 2, 0)
	_hall2("out", b0 + D[2] * 5, 2, 3, 0)
	_make_map()
	_wet_line(a0 + D[2] + D[4] * 6, a0 + D[2] + D[1] * 6)
	_flood(Hex.range_cells(a0 + D[2] + D[4] * 2, 1))
	_flood_main("main", mn, 1)
	_wet_line(b0 + D[2] + D[4] * 6, b0 + D[2] + D[1] * 4)
	_flow([a0 + D[2] + D[4] * 6, b0 + D[2] + D[1] * 4])
	_finish()
	_outfall_at(a0 + D[2] + D[4] * 6, 1, 0.65, 1.0)
	_shaft(_w(a0 + D[2] + D[4] * 2) + Vector3(0, FLOOR_Y, 0), 0.8)
	_bridge_cell(a0 + D[2] + D[1] * 3, 1)
	_bridge_cell(a0 + D[2] + D[4] * 4, 1)
	_bridge_cell(mn[7] + D[2], 1)
	_bridge_cell(b0 + D[2], 1)
	_arch_at(a0 + D[1] * 6 + D[2], 1, 6.0)
	_arch_at(b0 + D[4] * 5 + D[2], 4, 6.0)
	_plan_bar(_w(a0 + D[5] * 6) + Hex.dir_vector(5) * Hex.INNER, Hex.dir_vector(5), 3.4, C_SLUICE, 0.3)
	_plan_bar(_w(b0 + D[2] * 5) + Hex.dir_vector(2) * Hex.INNER, Hex.dir_vector(2), 3.4, C_SLUICE, 0.3)
	_bars_at(b0 + D[2] + D[1] * 4, 1, 2.8)
	for i in [2, 5, 9, 12]:
		_put(SewerProps.build("springer", {"height": 1.5, "col": look["wall_base"]}), _w(mn[i] + D[2] * 3), yaw_to(-Hex.dir_vector(2) - Hex.dir_vector(1)))
	_put(SewerProps.build("pipe_bundle", {"length": 4.0, "col": look["pipe"]}), _w(mn[10] + D[2] * 3), yaw_to(-Hex.dir_vector(2) - Hex.dir_vector(1)))
	_put_wall(PropModels.build("henchman_locker"), a0, 6, 2, -1.0, 0.45)
	_put_wall(PropModels.build("henchman_locker"), a0, 6, 2, 0.0, 0.45)
	_put_wall(PropModels.build("evil_portrait"), a0, 6, 2, 2.0, 0.15)
	_put_wall(PropModels.build("brazier"), a0, 6, 3, 1.5, 0.8)
	_put_wall(SewerProps.build("pipe_bundle", {"length": 5.0, "col": look["pipe"]}), b0, 5, 1, 0.0, 0.0)
	_put_wall(PropModels.build("oil_drum"), b0, 5, 1, 2.6, 0.5)
	_put(SewerProps.build("gas", {"radius": 0.7}), Vector3(_w(b0 + D[2] + D[1] * 2).x, SURFACE, _w(b0 + D[2] + D[1] * 2).z), 0.0)
	return {"a0": a0, "b0": b0, "s0": s0, "e0": e0, "mn": mn}


func _stage_main(L: Dictionary) -> void:
	var D := Hex.DIRS
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var mn: Array[Vector2i] = L["mn"]
	_hero_at("gasket", _near(mn[3], 1), Hex.dir_vector(1))
	_hero_at("wick", _near(mn[1], 1), Hex.dir_vector(1), "shoot")
	_hero_at("rebar", _w(a0 + D[1] * 4 + D[0]), Hex.dir_vector(1))
	_mon("archer", _farl(mn[8], 1), Hex.dir_vector(4), "windup", 0.8)
	_mon("archer", _farl(mn[10], 1), Hex.dir_vector(4))
	_gator2(_w(mn[5] + D[2], Vector3(0.0, 0, 0.0)), yaw_to(Hex.dir_vector(4)), -10.0)
	_mon("grunt", _w(a0 + D[2] * 3), Hex.dir_vector(5))
	_mon("grunt", _w(a0 + D[2] * 3 + D[3]), Hex.dir_vector(5))
	_mon("grunt", _w(a0 + D[3] * 3 + D[2]), Hex.dir_vector(0))
	_rats(_w(a0 + D[4] * 3), 8, 0.8, 2)
	_employee("henchman", 1, _w(a0 + D[3] * 4 + D[2]), Hex.dir_vector(0), "cower")
	_note("sign", _w(mn[1] + D[5] * 0, Vector3(-0.6, 0, 0.6)), yaw_to(Hex.dir_vector(1)) + 20.0)
	_mon("brute", _w(b0 + D[5] * 2), Hex.dir_vector(4))
	_mon("goblin", _w(b0 + D[2] * 3 + D[3]), Hex.dir_vector(4))


func _case_main() -> void:
	var L := _build_main()
	_stage_main(L)
	var D := Hex.DIRS
	var a0: Vector2i = L["a0"]
	var b0: Vector2i = L["b0"]
	var s0: Vector2i = L["s0"]
	var mn: Array[Vector2i] = L["mn"]
	_plan_fill()
	_plan_spaces()
	_plan_arrow([_w(s0), _w(a0 + D[5] * 4)], C_CREW)
	_lbl(_w(s0 + D[0] * 2), "CREW IN", C_CREW, 40)
	_lbl(_w(a0 + D[2] + D[4] * 6 + D[2]), "outfall (source)", C_NOTE)
	_lbl(_w(a0 + D[2] * 4 + D[3]), "skeletons x3 + rats; Dave (Henchman 4) cowering", C_MON)
	_lbl(_w(a0 + D[2] * 5 + D[1] * 2), "lockers $300 x2, portrait $2,000, brazier", C_HAZ)
	_lbl(_w(mn[9] + D[2] * 4), "2 archers on the FAR ledge; steam valve", C_MON)
	_lbl(_w(mn[4] + D[5] * 1), "near ledge (crew)", C_LEDGE)
	_lbl(_w(mn[1] + D[5] * 2), "note: GATOR CROSSING", C_NOTE)
	_lbl(_w(mn[7] + D[5] * 2), "grate bridge: the main's dry crossing", C_BRIDGE)
	_lbl(_w(b0 + D[5] * 3), "brute; gas pocket; oil drum", C_HAZ)
	_lbl(_w(b0 + D[2] + D[1] * 5), "culvert (bars)", C_NOTE)
	var g := _w(mn[5] + D[2])
	_plan_gator(g, [_w(a0 + D[2] + D[4] * 2), _w(mn[11] + D[2])], [_w(a0 + D[2] + D[4] * 2), g, _w(mn[11] + D[2])])
	_lbl(g + Vector3(0, 0, 2.6), "GATOR: the main is its lane", C_GATOR, 40)
	plan_size = 46.0
	plan_at = (_w(a0) + _w(b0)) * 0.5 + Vector3(0, 0, 1.0)
	legend_corner = "br"
	_legend("L5  The sewer main  (lair, brick)")
	_views(_w(mn[5]) + Vector3(0, 0, 1.0))


## The unit X/Z vector across a hall running along `dir`, toward its lanes (DIRS[dir + 1]'s side).
static func _across(dir: int) -> Vector3:
	var ax := Hex.dir_vector(dir)
	var v := Vector3(-ax.z, 0, ax.x)
	return v if v.dot(Hex.dir_vector(dir + 1)) > 0.0 else -v


## A spot on a 6.0 main's NEAR ledge beside route cell r (the route row is the near rim; the ledge is 0.75 toward the wall).
func _near(r: Vector2i, dir: int) -> Vector3:
	return _w(r) - _across(dir) * 0.75


## A spot on a 6.0 main's FAR ledge beside route cell r (lane 2 is the far rim).
func _farl(r: Vector2i, dir: int) -> Vector3:
	return _w(r + Hex.DIRS[(dir + 1) % 6] * 2) + _across(dir) * 0.75


func _fight_tag(p: Vector3, text: String, col: Color) -> void:
	_tag(p, text, col, fight_nodes, 30, 2.2)


## Yaw that turns a model's local +X onto the X/Z vector v.
static func _yaw_x(v: Vector3) -> float:
	return rad_to_deg(atan2(-v.z, v.x))


# --------------------------------------------------------------------------- fight moments

## L2: the skeleton pack wades in down the pump post's hall; Rebar on the bridge punches the lead skeleton back toward
## the sump, into the gator's territory; the gator's nip is winding up on it. The others keep wading in.
func _case_fight_shove() -> void:
	var L := _build_junction()
	var D := Hex.DIRS
	var j0: Vector2i = L["j0"]
	var bridge := _w(j0 + D[0] * 3)
	var reb := _hero_on("rebar", bridge + Hex.dir_vector(5) * 0.15, Hex.dir_vector(3))
	reb.call("attack_swing")
	_hero_at("wick", _w(j0 + D[5] * 3 + D[4]), Hex.dir_vector(1), "shoot")
	_hero_at("gasket", _w(j0 + D[5] * 3), Hex.dir_vector(1), "cast")
	# the lead skeleton, flung back off the bridge toward the sump (tilted, airborne)
	var fly_at := _w(j0 + D[0] * 2, Vector3(-0.3, 0, 0.0))
	var sk := _mon("grunt", fly_at, Hex.dir_vector(0))
	sk.position.y = FLOOR_Y + 1.0
	sk.rotate_object_local(Vector3.RIGHT, deg_to_rad(-55.0))
	_speed_lines(bridge + Hex.dir_vector(3) * 0.5, Hex.dir_vector(3))
	_ripple(fly_at, 0.5)
	# the gator, facing the incoming body, jaws open (the nip's 0.5 s wind-up), its territory drawn
	var gp := _w(j0, Vector3(-0.2, 0, 0.0))
	_gator2(gp, yaw_to(Hex.dir_vector(0)), 8.0, 0.95)
	_territory(gp, fight_nodes)
	_circle(gp + Hex.dir_vector(0) * 1.3, 0.55, Color(1.0, 0.45, 0.05, 1.0), 0.09, SURFACE + 0.06, fight_nodes)
	_line_strip([bridge, fly_at, gp + Hex.dir_vector(0) * 1.0], Color(1, 1, 1, 0.9), 0.1, SURFACE + 0.07, fight_nodes, true, true)
	# the rest of the pack wading in behind, an archer on the NW wedge drawing on Wick
	_mon("grunt", _w(j0 + D[0] * 5, Vector3(0.0, 0, 0.2)), Hex.dir_vector(3), "windup", 0.5)
	_mon("grunt", _w(j0 + D[0] * 6, Vector3(0.0, 0, -0.2)), Hex.dir_vector(3))
	_mon("grunt", _w(j0 + D[1] * 3), Hex.dir_vector(4))
	var arc := _mon("archer", _w(j0 + D[3] * 3 + D[2]), Hex.dir_vector(5), "windup", 0.9)
	_line_strip([arc.position + Vector3(0, 0.0, 0), _w(j0 + D[5] * 3 + D[4])], Color(1.0, 0.2, 0.15, 0.8), 0.06, 0.08, fight_nodes, true, true)
	_fight_tag(bridge + Vector3(0.4, 0, 0.6), "Rebar's fist: shove 1.6 (on the dry bridge)", C_CREW)
	_fight_tag(gp + Vector3(-2.2, 0, 1.6), "gator territory 3.0: whoever enters gets nipped\n(10 + shove 1.6, 0.5 s wind-up)", C_GATOR)
	_fight_tag(_w(j0 + D[0] * 5) + Vector3(0, 0, 0.8), "pack wading: 0.75x, soaked", C_MON)
	_caption("L2 fight: the gator between the crew and the pack. Rebar knocks the lead skeleton off the bridge into the\ngator's territory; the gator nips whatever comes close, monsters included. The crew stays on dry ground.")
	_mode(false)
	_view("game", GAME_SIZE, _w(j0) + Vector3(0.5, 0, 1.5))
	_view("close", 12.0, _w(j0 + D[0] * 2) + Vector3(0, 0, 0.5))


## L3: Wick's arrow trips the junction box; the cable is down in the aquarium channel and the shock runs along the
## connected water, as far as its reach. Waders (skeletons, an eel, Rebar) take it; Gasket on the bridge is dry.
func _case_fight_wire() -> void:
	wire_down = true
	var L := _build_aquarium()
	var D := Hex.DIRS
	var a0: Vector2i = L["a0"]
	var ab: Array[Vector2i] = L["ab"]
	var box := _wall_spot(a0, 5, 1, -2.4, 0.0)
	var box_p: Vector3 = box[0]
	var drop_end := box_p + Basis(Vector3.UP, deg_to_rad(float(box[1]))) * Vector3(0.2, 0, 2.6)
	_hero_on("gasket", _w(a0 + D[1] * 3), Hex.dir_vector(1))
	var wick := _hero_at("wick", _w(a0 + D[5] * 2 + D[0]), (box_p - _w(a0 + D[5] * 2 + D[0])).normalized(), "shoot")
	_line_strip([wick.position + Vector3(0, 0, 0), box_p + Vector3(0, 0, 0.2)], Color(1.0, 1.0, 0.85, 0.9), 0.05, 1.1, fight_nodes, true, true)
	_hero_at("rebar", _w(a0 + D[1] * 1 + D[5], Vector3(0.0, 0, 0.0)), Hex.dir_vector(2))
	# the shock: arcs along the channel from where the cable lies, both ways, to the reach limit
	var y := SURFACE + 0.05
	var pts_up: Array = [drop_end, _w(a0 + D[1] * 3), _w(a0 + D[1] * 1), _w(a0), _w(a0 + D[2] * 2), _w(a0 + D[2] * 3)]
	var pts_dn: Array = [drop_end, _w(a0 + D[1] * 5), _w(ab[1]), _w(ab[2]), _w(ab[3]), _w(ab[4])]
	for pts: Array in [pts_up, pts_dn]:
		var loc: Array = []
		for p: Vector3 in pts:
			loc.append(Vector3(p.x, y, p.z))
		var arc := SewerProps.build("shock", {"points": loc, "seed": loc.size()})
		add_child(arc)
		fight_nodes.append(arc)
	# the reach limit (8 cells along the water from the drop)
	var lim := _w(ab[5])
	_line_strip([lim - _across(1) * 1.8, lim + _across(1) * 0.6], Color(1.0, 0.95, 0.3, 1.0), 0.14, y + 0.02, fight_nodes, true)
	_fight_tag(lim + Vector3(0.5, 0, 0.6), "shock reach: 8 cells of connected water", C_HAZ)
	# the waders it hits
	for c: Vector3 in [_w(a0 + D[1] * 2, Vector3(0.0, 0, 0.0)), _w(ab[2], Vector3(0.0, 0, 0.3)), _w(a0 + D[1] * 1 + D[5])]:
		for k in 5:
			var a := TAU * float(k) / 5.0
			_glow_ball(Vector3(c.x, FLOOR_Y + 0.7 + 0.25 * sin(a * 2.0), c.z) + Vector3(cos(a), 0, sin(a)) * 0.45, 0.06, Color(1.0, 1.0, 0.6), fight_nodes)
	_mon("grunt", _w(a0 + D[1] * 2, Vector3(0.0, 0, 0.0)), Hex.dir_vector(4), "windup", 0.3)
	_mon("grunt", _w(ab[2], Vector3(0.0, 0, 0.3)), Hex.dir_vector(4))
	_eel(a0 + D[2] * 2, 4, Vector3(0.2, 0, 0), 0.4)
	_mon("archer", _w(a0 + D[3] * 3 + D[2]), Hex.dir_vector(5), "windup", 0.7)
	_mon("archer", _w(a0 + D[3] * 2 + D[4]), Hex.dir_vector(0))
	_employee("henchman", 5, _w(a0 + D[3] * 4 + D[2]), Hex.dir_vector(0), "cower")
	_fight_tag(_w(a0 + D[1] * 3) + Vector3(0.6, 0, 0.9), "Gasket on the bridge: dry, untouched", C_CREW)
	_fight_tag(_w(a0 + D[1] * 1 + D[5]) + Vector3(-1.0, 0, 1.0), "waders: 18 (soaked x1.5) + daze 0.6 s", C_HAZ)
	_fight_tag(box_p + Vector3(0, 0.5, 0), "Electrical panel $250 (Wick's arrow)", C_NOTE)
	_caption("L3 fight: Wick shoots the junction box; the live cable drops into the channel. The shock runs through the\nconnected water as far as its reach and hits every wader, both sides. Dry ground (the bridge, the decks) is safe.")
	_mode(false)
	_view("game", GAME_SIZE, _w(a0) + Hex.dir_vector(1) * 6.0 + Vector3(0, 0, 1.0))
	_view("close", 13.0, _w(a0 + D[1] * 3) + Vector3(0, 0, 0.5))


## L5: archers on the far ledge of the main; the crew on the near ledge and in the channel. The steam valve vents and
## walls off one archer's line; Wick's corn floats downstream as the gator's chum, holding it off the crew.
func _case_fight_ledge() -> void:
	var L := _build_main()
	var D := Hex.DIRS
	var mn: Array[Vector2i] = L["mn"]
	var wick := _hero_at("wick", _near(mn[4], 1), Hex.dir_vector(2), "cast")
	_hero_at("gasket", _near(mn[6], 1), Hex.dir_vector(2))
	_hero_at("rebar", _w(mn[6] + D[2], Vector3(0.0, 0, 0.0)), Hex.dir_vector(1))
	var a1 := _mon("archer", _farl(mn[5], 1), Hex.dir_vector(5), "windup", 0.9)
	var a2 := _mon("archer", _farl(mn[12], 1), Hex.dir_vector(4), "windup", 0.9)
	_line_strip([a1.position, wick.position], Color(1.0, 0.2, 0.15, 0.85), 0.06, 0.9, fight_nodes, true, true)
	# the steam valve on the far wall vents ACROSS the main (one hex wide, the main's whole width): archer 2 is walled off
	var steam_from := _farl(mn[11], 1) + _across(1) * 0.7
	var steam := SewerProps.build("steam_wall", {"length": 6.0, "seed": 4})
	add_child(steam)
	steam.position = Vector3(steam_from.x, 0.0, steam_from.z)
	steam.rotation_degrees.y = _yaw_x(-_across(1))
	fight_nodes.append(steam)
	var blocked := a2.position.lerp(wick.position, 0.12)
	_line_strip([a2.position, blocked], Color(1.0, 0.2, 0.15, 0.85), 0.06, 0.9, fight_nodes, true)
	_fight_tag(_w(mn[11] + D[2]) + Vector3(0.8, 1.2, 0), "steam wall across the main:\nblocks sight 3 s, 12/s", C_HAZ)
	var corn := SewerProps.build("corn_float", {"count": 18, "radius": 0.9})
	add_child(corn)
	var cp := _w(mn[8] + D[2])
	corn.position = Vector3(cp.x, SURFACE, cp.z)
	corn.rotation_degrees.y = _yaw_x(Hex.dir_vector(1))
	fight_nodes.append(corn)
	var gp := _w(mn[9] + D[2], Vector3(0.4, 0, 0.0))
	_gator2(gp, yaw_to(Hex.dir_vector(4)), 12.0, 0.6)
	_territory(gp, fight_nodes)
	_fight_tag(cp + Vector3(-0.5, 0, 1.4), "corn floats downstream: the gator's chum, 4 s", Color(1.0, 0.85, 0.3))
	_fight_tag(_farl(mn[5], 1) + Vector3(0, 0.6, 0), "archer on the far ledge: no dry way over but the bridge", C_MON)
	_fight_tag(_w(mn[6] + D[2]) + Vector3(0.6, 0, 1.4), "Rebar wading to the bridge: 0.75x, soaked (fireproof)", C_CREW)
	_caption("L5 fight: ranged enemies on the far ledge, the channel between. The steam valve walls one archer off; Wick's\ncorn floats down the channel and holds the gator on the kernels while Rebar wades across to the bridge.")
	_mode(false)
	_view("game", GAME_SIZE, _w(mn[8]) + Vector3(0, 0, 1.2))
	_view("close", 13.0, _w(mn[7] + D[2]) + Vector3(0, 0, 0.5))

class_name FogView
extends Node3D
## Draws ROOM FOG (RoomFog) on one machine: a SCREEN-SPACE pass (one full-screen quad on the camera that reads the depth
## buffer, rebuilds each pixel's world point, looks up the space under it and restyles the pixel) plus the CONTENTS rule
## (what moves shows only in a space in view; what stays put shows in view or seen; nothing shows in a next or unknown
## space). Cosmetic and LOCAL: the simulation never reads it; every machine draws its own from the same RoomFog rules.
##
## Nothing in the terrain changes (HexMapView builds as ever): the pass styles terrain, props, decor and everything else
## by where it stands, so a seen room's furniture dims with its floor. Three LOOKS (docs/design/exploration.md, "Fog and
## doors as built"):
##   A  BLACK VOID   unknown: not drawn (the background colour); next: a dark silhouette (floors lighter than walls, every
##                   edge traced faintly); seen: desaturated and darkened.
##   B  BLUEPRINT    unknown: not drawn; next: a cyan blueprint on navy paper (the hex grid on floors, every edge inked);
##                   seen: greyed.
##   C  SMOKE        low faceted smoke (one shade per hex kite, slowly breathing) fills what is not in view: unknown solid;
##                   next: the wall tops stand out of a thick low smoke; seen: a thin dust haze. It thins near an open
##                   doorway whose other side is in view.
##
## DATA. Two small textures: CELLS (static, one texel per hex cell: the space ids of the cell (a wall cell: up to two spaces
## around it), its floor level, its nearest doorway) and DYN (one row of per-space display levels, animated, one row of
## per-doorway smoke thinning and middle point, one static row of the cuts of long halls: axis and segments). Only DYN's
## first two rows change, and only while a level is fading (FADE_TIME).
##
## CUTS (RoomFog, LONG HALLS; user, 2026-10-20: "Turn it on"): where a hall's segment meets the next one, the levels blend
## across a feather about a hex wide on the floor and the walls (CUT_FEATHER each side of the cut's line), in every look,
## not the hex-edge step: a hall in view runs into the dark as a corridor, not into a wall. Only cells of the two segments
## (and walls beside them) take it; a cut keeps RoomFog.CUT_CLEAR steps from every real doorway, so it never draws over
## one or its door.
##
## DECISION (user, 2026-10-19): the game draws look A only (game.gd _setup_fog, every machine, fed with every seat's hero,
## puppets too); B and C stay in the fog lab. Seen rooms show their furniture live (no last-known ghosts of monsters).
##
## COST. GPU: one full-screen pass (screen copy + 5 depth reads + 4 cell / 6 level reads a pixel). CPU: a RoomFog.update
## every UPDATE_EVERY (about 0.15 ms with three heroes on a generated floor), a 2-row texture upload while fading, and a
## visibility pass over the tracked contents when the states change. `stats` holds the measured numbers.
##
##   var fv := FogView.new(); add_child(fv)
##   fv.setup(map, fog, camera)
##   fv.track_static(site.props + site.decor + ...)    # shown in view or seen
##   fv.watch_doors(OfficeDoor.all())
##   fv.look = FogView.LOOK_BLUEPRINT
##   (each frame) fv.viewers = [hero positions]     or  fv.heroes = [Hero, ...]

enum { LOOK_VOID, LOOK_BLUEPRINT, LOOK_SMOKE }

const LOOK_NAMES := ["A black void", "B blueprint", "C smoke"]
const UPDATE_EVERY := 0.1          ## seconds between RoomFog updates
const PASS_PRIORITY := 100         ## the fog's full-screen pass draws after the world; what must stay readable over it
                                   ## (the use prompt) draws above this
const FADE_TIME := 0.35            ## a space's look fades between states over this long
const THIN_CELLS := 4              ## a doorway thins the smoke this many cells deep
const DYNAMIC_GROUPS := ["monsters", "employees", "component_pickups", "chickens", "sharks"]
const LEVELS := [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]   ## display level per RoomFog state

var fog: RoomFog
var map: HexMap
var look := LOOK_VOID:
	set(v):
		look = v
		if _mat != null:
			_mat.set_shader_parameter("look", v)
var enabled := true:
	set(v):
		enabled = v
		if _quad != null:
			_quad.visible = v
		_contents_dirty = true
var heroes: Array = []             ## the crew's heroes (their positions are the viewers), or set `viewers` directly
var viewers: Array = []
var stats := {"update_us": 0.0, "upload_us": 0.0, "contents_us": 0.0, "updates": 0, "uploads": 0}

var _static: Array[Node3D] = []
var _doors: Array[OfficeDoor] = []
var _shown: PackedFloat32Array = PackedFloat32Array()   ## per space: the display level now
var _want: PackedFloat32Array = PackedFloat32Array()    ## per space: the display level it fades to
var _thin: PackedFloat32Array = PackedFloat32Array()    ## per doorway: smoke thinning 0..1
var _dyn_img: Image
var _dyn_tex: ImageTexture
var _cells_tex: ImageTexture
var _cells_img: Image
var _cells_rect := Vector4i.ZERO   ## the cell texture's first q, first r, width, height
var _mat: ShaderMaterial
var _quad: MeshInstance3D
var _t := 0.0
var _fading := false
var _contents_dirty := true
var _hidden: Dictionary = {}       ## instance id -> true: nodes the fog hid (and so may show again)

static var _shader: Shader


## Who may write each var (see Net). All of it is this machine's presentation.
func net_fields() -> Dictionary:
	return {
		"fog": Net.LOCAL, "map": Net.LOCAL, "look": Net.LOCAL, "enabled": Net.LOCAL, "heroes": Net.LOCAL, "viewers": Net.LOCAL,
		"stats": Net.LOCAL, "_static": Net.LOCAL, "_doors": Net.LOCAL, "_shown": Net.LOCAL, "_want": Net.LOCAL,
		"_thin": Net.LOCAL, "_dyn_img": Net.LOCAL, "_dyn_tex": Net.LOCAL, "_cells_tex": Net.LOCAL, "_cells_img": Net.LOCAL, "_cells_rect": Net.LOCAL,
		"_mat": Net.LOCAL,
		"_quad": Net.LOCAL, "_t": Net.LOCAL, "_fading": Net.LOCAL, "_contents_dirty": Net.LOCAL, "_hidden": Net.LOCAL,
	}


func setup(m: HexMap, f: RoomFog, camera: Camera3D) -> void:
	map = m
	fog = f
	var n := fog.space_count()
	_shown.resize(n)
	_want.resize(n)
	_thin.resize(fog.doorways.size())
	_build_cells()
	var w := maxi(1, maxi(n, fog.doorways.size()))
	_dyn_img = Image.create(w, 3, false, Image.FORMAT_RGBAF)
	for dw in fog.doorways:
		var mid: Vector3 = dw["mid"]
		_dyn_img.set_pixel(int(dw["id"]), 1, Color(0.0, mid.x, mid.z, 0.0))
		if fog.is_cut(int(dw["id"])):
			# a cut of a long hall: its axis (from its nearer segment to its farther) and the two segments (+1)
			var ax: Vector3 = dw["axis"]
			_dyn_img.set_pixel(int(dw["id"]), 2, Color(ax.x, ax.z, float(int(dw["ri"]) + 1), float(int(dw["hi"]) + 1)))
	_dyn_tex = ImageTexture.create_from_image(_dyn_img)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.render_priority = PASS_PRIORITY
	_mat.set_shader_parameter("cells", _cells_tex)
	_mat.set_shader_parameter("dyn", _dyn_tex)
	_mat.set_shader_parameter("look", look)
	_mat.set_shader_parameter("void_col", DungeonLook.BACKGROUND)
	_mat.set_shader_parameter("cells_origin", Vector2i(_cells_rect.x, _cells_rect.y))
	_mat.set_shader_parameter("cells_size", Vector2i(_cells_rect.z, _cells_rect.w))
	_quad = MeshInstance3D.new()
	_quad.name = "FogPass"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	_quad.mesh = qm
	_quad.material_override = _mat
	_quad.extra_cull_margin = 16384.0
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.position = Vector3(0.0, 0.0, -1.0)
	camera.add_child(_quad)
	_quad.visible = enabled
	fog.changed.connect(_on_fog_changed)


## Things that stay put (priced props, decor, notes, mail, gates): shown in a space in view or seen (the pass dims a seen
## room's), hidden in a next or unknown one.
func track_static(nodes: Array) -> void:
	for n: Variant in nodes:
		if n is Node3D and is_instance_valid(n):
			_static.append(n)
	_contents_dirty = true


## Doors: part of the layout (shown when either side is next or better); their shut state goes into the fog.
func watch_doors(doors: Array) -> void:
	for d: Variant in doors:
		if d is OfficeDoor and not _doors.has(d):
			_doors.append(d)
			fog.set_shut((d as OfficeDoor).doorway_id, (d as OfficeDoor).shut and not (d as OfficeDoor).broken)
			(d as OfficeDoor).state_changed.connect(_on_door)
			_door_cells(d as OfficeDoor)
	_cells_tex.update(_cells_img)
	refresh_now()


## A door and the stub of hall between it and its room are drawn with the room too (their second space): from a room in
## view its shut door shows, not a dark gap.
func _door_cells(d: OfficeDoor) -> void:
	var dw: Dictionary = fog.doorways[d.doorway_id]
	var room := int(dw["ri"])
	var hall := int(dw["hi"])
	var c0 := d.center()
	for c in Hex.range_cells(d.cell, 4):
		if fog.space_of_cell(c) != hall:
			continue
		if (Hex.to_world(c) - c0).dot(d.axis) > 1.0:   # (up to a cell past the door line: no fog seam across the door)
			continue
		var x := c.x - _cells_rect.x
		var y := c.y - _cells_rect.y
		if x < 0 or y < 0 or x >= _cells_rect.z or y >= _cells_rect.w:
			continue
		var px := _cells_img.get_pixel(x, y)
		px.g = float(room + 1) / 255.0
		_cells_img.set_pixel(x, y, px)


func _on_door(d: OfficeDoor) -> void:
	fog.set_shut(d.doorway_id, d.shut and not d.broken)
	refresh_now()


## Run the fog now (not at the next tick), and snap every level to its state (no fade): a teleport, the lab's staging.
func refresh_now(snap: bool = false) -> void:
	_update_fog()
	if snap:
		for s in _shown.size():
			_shown[s] = _want[s]
	_fading = true
	_upload(0.0)
	_apply_contents()


func _process(delta: float) -> void:
	if fog == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = UPDATE_EVERY
		_update_fog()
	if _fading:
		_upload(delta)
	_apply_contents()


func _update_fog() -> void:
	var t0 := Time.get_ticks_usec()
	var pts: Array = []
	for h: Variant in heroes:
		if h is Node3D and is_instance_valid(h):
			pts.append((h as Node3D).global_position)
	for p: Variant in viewers:
		pts.append(p)
	fog.update(pts)
	for s in fog.space_count():
		_want[s] = LEVELS[fog.state[s]]
		if _want[s] != _shown[s]:
			_fading = true
	for dw in fog.doorways:
		var id := int(dw["id"])
		var r: int = fog.state[int(dw["ri"])]
		var hh: int = fog.state[int(dw["hi"])]
		var th := 1.0 if fog.is_open(id) and (r == RoomFog.IN_VIEW) != (hh == RoomFog.IN_VIEW) else 0.0
		if th != _thin[id]:
			_thin[id] = th
			_fading = true
	stats["update_us"] = float(Time.get_ticks_usec() - t0)
	stats["updates"] = int(stats["updates"]) + 1


func _on_fog_changed() -> void:
	_contents_dirty = true


## Fade the per-space levels and upload the dynamic row.
func _upload(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var step := delta / FADE_TIME if delta > 0.0 else 0.0
	var still := true
	for s in _shown.size():
		if _shown[s] != _want[s]:
			_shown[s] = move_toward(_shown[s], _want[s], step) if step > 0.0 else _shown[s]
			if _shown[s] != _want[s]:
				still = false
		_dyn_img.set_pixel(s, 0, Color(_shown[s], 0.0, 0.0, 1.0))
	for dw in fog.doorways:
		var id := int(dw["id"])
		var c := _dyn_img.get_pixel(id, 1)
		c.r = move_toward(c.r, _thin[id], step * 1.5) if step > 0.0 else c.r
		if c.r != _thin[id]:
			still = false
		_dyn_img.set_pixel(id, 1, c)
	_dyn_tex.update(_dyn_img)
	_fading = not still
	stats["upload_us"] = float(Time.get_ticks_usec() - t0)
	stats["uploads"] = int(stats["uploads"]) + 1


## Hide what the crew can't see (cosmetic, this machine only: the host still simulates all of it).
func _apply_contents() -> void:
	var t0 := Time.get_ticks_usec()
	for n in get_tree().get_nodes_in_group("monsters") + _group_nodes():
		if n is Node3D and is_instance_valid(n):
			_show(n as Node3D, not enabled or fog.shows_contents((n as Node3D).global_position))
	if _contents_dirty:
		_contents_dirty = false
		for n in _static:
			if is_instance_valid(n):
				_show(n, not enabled or fog.shows_static(n.global_position))
		for d in _doors:
			if is_instance_valid(d):
				var dw: Dictionary = fog.doorways[d.doorway_id]
				var best := maxi(fog.state_of(int(dw["ri"])), fog.state_of(int(dw["hi"])))
				_show(d, not enabled or best >= RoomFog.NEXT)
	stats["contents_us"] = float(Time.get_ticks_usec() - t0)


## Hide a node the crew can't see; show again only what the fog hid (a node that hides itself, like a sinking hellgate
## beast or a van not popped in yet, stays as its own code has it).
func _show(n: Node3D, shown: bool) -> void:
	var id := n.get_instance_id()
	if not shown:
		if n.visible:
			n.visible = false
			_hidden[id] = true
	elif _hidden.has(id):
		_hidden.erase(id)
		n.visible = true


func _group_nodes() -> Array:
	var out: Array = []
	for g: String in DYNAMIC_GROUPS:
		if g == "monsters":
			continue
		out.append_array(get_tree().get_nodes_in_group(g))
	return out


## The static cell texture: per hex cell R = space id + 1, G = a second space (wall cells), B = floor level + 64 (255 = a
## wall cell), A = nearest doorway id + 1 within THIN_CELLS (0 = none).
func _build_cells() -> void:
	var qmin := 1 << 20
	var rmin := 1 << 20
	var qmax := -(1 << 20)
	var rmax := -(1 << 20)
	for c: Vector2i in map.cells:
		qmin = mini(qmin, c.x)
		rmin = mini(rmin, c.y)
		qmax = maxi(qmax, c.x)
		rmax = maxi(rmax, c.y)
	qmin -= 2
	rmin -= 2
	qmax += 2
	rmax += 2
	var w := qmax - qmin + 1
	var h := rmax - rmin + 1
	var data := PackedByteArray()
	data.resize(w * h * 4)
	# nearest doorway per cell (breadth first from each doorway's cells, THIN_CELLS deep, over floor cells)
	var near_dw := {}
	var near_d := {}
	for dw in fog.doorways:
		var queue: Array[Vector2i] = []
		for c: Vector2i in (dw["door_cells"] as Array[Vector2i]) + (dw["mouth_cells"] as Array[Vector2i]):
			if not near_d.has(c) or int(near_d[c]) > 0:
				near_d[c] = 0
				near_dw[c] = int(dw["id"])
			queue.append(c)
		var dist := {}
		for c in queue:
			dist[c] = 0
		var qi := 0
		while qi < queue.size():
			var cur := queue[qi]
			qi += 1
			var dc: int = dist[cur]
			if dc >= THIN_CELLS:
				continue
			for d in Hex.DIRS:
				var nb: Vector2i = cur + d
				if dist.has(nb) or not fog.cell_space.has(nb):
					continue
				dist[nb] = dc + 1
				queue.append(nb)
				if not near_d.has(nb) or int(near_d[nb]) > dc + 1:
					near_d[nb] = dc + 1
					near_dw[nb] = int(dw["id"])
	for c: Vector2i in map.cells:
		var cell: HexMap.Cell = map.cells[c]
		var i := ((c.y - rmin) * w + (c.x - qmin)) * 4
		var s := fog.space_of_cell(c)
		if cell.type == HexMap.Tile.WALL:
			var around := _spaces_near(c)
			data[i] = (around[0] + 1) if around.size() > 0 else 0
			data[i + 1] = (around[1] + 1) if around.size() > 1 else 0
			data[i + 2] = 255
		else:
			data[i] = s + 1
			var top := cell.level + (cell.stair_rise if cell.type == HexMap.Tile.STAIRS else 0)
			data[i + 2] = clampi(top + 64, 0, 254)
		data[i + 3] = int(near_dw[c]) + 1 if near_dw.has(c) else 0
		# a wall cell beside a cut of a long hall takes the cut too (its feather runs up the walls)
		if cell.type == HexMap.Tile.WALL:
			var best_d := 3
			for n in Hex.ring(c, 1):
				if near_dw.has(n) and fog.is_cut(int(near_dw[n])) and int(near_d[n]) < best_d:
					best_d = int(near_d[n])
					data[i + 3] = int(near_dw[n]) + 1
	# Pits and other holes inside the floor take a neighbour's space (two passes).
	for _pass in 2:
		var copy := data.duplicate()
		for r in range(1, h - 1):
			for q in range(1, w - 1):
				var i := (r * w + q) * 4
				if data[i] != 0 or data[i + 2] != 0:
					continue
				for d in Hex.DIRS:
					var j := ((r + d.y) * w + (q + d.x)) * 4
					if data[j] != 0 and data[j + 2] != 255:
						copy[i] = data[j]
						copy[i + 2] = data[j + 2]
						break
		data = copy
	_cells_img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	_cells_tex = ImageTexture.create_from_image(_cells_img)
	_cells_rect = Vector4i(qmin, rmin, w, h)


## The (up to two) spaces nearest a wall cell, within two rings, nearest first.
func _spaces_near(c: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for ring in [1, 2]:
		for n in Hex.ring(c, ring):
			var s := fog.space_of_cell(n)
			if s >= 0 and not out.has(s):
				out.append(s)
				if out.size() == 2:
					return out
	return out


const SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D cells : filter_nearest;
uniform sampler2D dyn : filter_nearest;
uniform ivec2 cells_origin;
uniform ivec2 cells_size;
uniform int look = 0;
uniform vec3 void_col : source_color = vec3(0.075, 0.052, 0.042);

const float SQ3 = 1.7320508;
const float INNER = 0.8660254;
const float LH = 0.5;
const float CUT_FEATHER = 0.9;   // a cut's feather runs this far each side of its line (a hex is 1.73 across)
const float CUT_REACH = 5.0;     // ... and this far along it from its middle (wider than any hall)

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

ivec2 hex_round(vec2 qr) {
	float s = -qr.x - qr.y;
	vec3 r = round(vec3(qr.x, qr.y, s));
	vec3 d = abs(r - vec3(qr.x, qr.y, s));
	if (d.x > d.y && d.x > d.z) {
		r.x = -r.y - r.z;
	} else if (d.y > d.z) {
		r.y = -r.x - r.z;
	}
	return ivec2(int(r.x), int(r.y));
}

vec2 hex_center(ivec2 c) {
	return vec2(SQ3 * (float(c.x) + float(c.y) * 0.5), 1.5 * float(c.y));
}

vec4 cell_at(ivec2 c) {
	ivec2 t = c - cells_origin;
	if (t.x < 0 || t.y < 0 || t.x >= cells_size.x || t.y >= cells_size.y) {
		return vec4(0.0);
	}
	return texelFetch(cells, t, 0);
}

float space_level(int id) {
	return id > 0 ? texelFetch(dyn, ivec2(id - 1, 0), 0).r : 0.0;
}

float level_of(vec4 cd) {
	int a = int(cd.r * 255.0 + 0.5);
	int b = int(cd.g * 255.0 + 0.5);
	return max(space_level(a), space_level(b));
}

vec3 world_at(vec2 uv, mat4 inv_proj, mat4 inv_view, out float zlin) {
	float depth = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, depth, 1.0);
	v.xyz /= v.w;
	zlin = -v.z;
	return (inv_view * vec4(v.xyz, 1.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// colours below are picked in sRGB (what the eye sees); the pass writes linear HDR like the rest of the scene
vec3 lin(vec3 s) {
	return pow(s, vec3(2.2));
}

// The look of one display state (0 unknown, 1 next, 2 seen, 3 in view) for this pixel.
vec3 state_color(int st, vec3 src, vec3 wp, float above, bool wall_part, bool top, float edge, float grid, float facet, float thin) {
	if (st >= 3) {
		return src;
	}
	float l = luma(src);
	if (look == 0) {
		if (st == 0) {
			return void_col;
		}
		if (st == 1) {
			vec3 base = wall_part ? (top ? vec3(0.085, 0.078, 0.08) : vec3(0.05, 0.046, 0.05)) : (top ? vec3(0.17, 0.155, 0.145) : vec3(0.09, 0.083, 0.08));
			return lin(base + vec3(0.16, 0.15, 0.14) * edge);
		}
		return mix(src, vec3(l), 0.8) * 0.36 + lin(vec3(0.0, 0.01, 0.03));
	}
	if (look == 1) {
		if (st == 0) {
			return void_col;
		}
		if (st == 1) {
			vec3 paper = lin(wall_part ? (top ? vec3(0.05, 0.13, 0.27) : vec3(0.035, 0.09, 0.2)) : vec3(0.08, 0.2, 0.38));
			vec3 ink = lin(vec3(0.5, 0.92, 1.0));
			float lines = max(edge, grid * (wall_part ? 0.0 : 0.45));
			if (wall_part && !top) {
				lines = max(lines, 0.25 * (1.0 - smoothstep(0.0, 0.03, abs(fract(wp.y / LH) - 0.5) - 0.44)));
			}
			return mix(paper, ink, clamp(lines, 0.0, 1.0));
		}
		return vec3(l) * vec3(0.42, 0.44, 0.48);
	}
	// look 2: smoke
	vec3 smoke = lin(vec3(0.20, 0.19, 0.21) * facet);
	vec3 dust = lin(vec3(0.42, 0.39, 0.35) * facet);
	float low = 1.0 - smoothstep(0.15, 1.95, above);
	if (st == 0) {
		// unknown: solid smoke, a shade darker where it is deep (the floor) than where walls stand out of it
		return mix(lin(vec3(0.11, 0.105, 0.115) * facet), smoke, 0.35 * (1.0 - low)) * mix(1.0, 1.6, thin);
	}
	if (st == 1) {
		// next: thick low smoke; the wall tops stand out of it, so the layout reads
		float d1 = mix(0.55, 0.93, low) * (1.0 - 0.55 * thin);
		return mix(mix(src, vec3(l), 0.6) * 0.6, smoke, d1);
	}
	float d2 = 0.6 * low * (1.0 - 0.7 * thin);
	return mix(mix(src, vec3(l), 0.5) * 0.7, dust, d2);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float zc;
	float zl;
	float zr;
	float zu;
	float zd;
	vec3 wc = world_at(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, zc);
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 src = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	if (depth <= 0.0000001) {
		ALBEDO = src;
		ALPHA = 0.0;
	} else {
		vec3 wl = world_at(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, zl);
		vec3 wr = world_at(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, zr);
		vec3 wu = world_at(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, zu);
		vec3 wd = world_at(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, zd);
		vec3 dx = abs(zr - zc) < abs(zc - zl) ? wr - wc : wc - wl;
		vec3 dy = abs(zd - zc) < abs(zc - zu) ? wd - wc : wc - wu;
		vec3 n = normalize(cross(dx, dy));
		bool top = abs(n.y) > 0.75;
		float lap = max(abs(zl + zr - 2.0 * zc), abs(zu + zd - 2.0 * zc));
		float edge = smoothstep(0.02, 0.08, lap);

		vec2 xz = wc.xz;
		vec2 qr = vec2((SQ3 / 3.0 * xz.x - xz.y / 3.0), (2.0 / 3.0) * xz.y);
		ivec2 c = hex_round(qr);
		vec4 cd = cell_at(c);
		// The nearest hex edge: soften the boundary to the cell across it.
		vec2 off = xz - hex_center(c);
		float best = -10.0;
		int bk = 0;
		ivec2 DIRS[6] = ivec2[6](ivec2(1, 0), ivec2(1, -1), ivec2(0, -1), ivec2(-1, 0), ivec2(-1, 1), ivec2(0, 1));
		vec2 DV[6] = vec2[6](vec2(1.0, 0.0), vec2(0.5, -0.8660254), vec2(-0.5, -0.8660254), vec2(-1.0, 0.0), vec2(-0.5, 0.8660254), vec2(0.5, 0.8660254));
		for (int k = 0; k < 6; k++) {
			float dd = dot(off, DV[k]);
			if (dd > best) {
				best = dd;
				bk = k;
			}
		}
		float edge_dist = INNER - best;
		vec4 nd = cell_at(c + DIRS[bk]);
		float v_own = level_of(cd);
		float v_nb = level_of(nd);
		float v = mix(v_own, v_nb, 0.5 * (1.0 - smoothstep(0.0, 0.32, edge_dist)));
		// LONG HALLS: across a cut between two segments of one hall, a soft feather about a hex wide (CUT_FEATHER each
		// side of the cut's line) instead of the hex-edge step, on its floor and walls: the hall goes on into the dark.
		int dwi = int(cd.a * 255.0 + 0.5);
		if (dwi > 0) {
			vec4 cut = texelFetch(dyn, ivec2(dwi - 1, 2), 0);
			if (cut.b > 0.5) {
				int ri = int(cut.b + 0.5);
				int hi = int(cut.a + 0.5);
				int sa = int(cd.r * 255.0 + 0.5);
				int sb = int(cd.g * 255.0 + 0.5);
				bool a_in = sa == ri || sa == hi;
				bool b_in = sb == 0 || sb == ri || sb == hi;
				if (a_in || (sb != 0 && (sb == ri || sb == hi))) {
					vec2 rel = xz - texelFetch(dyn, ivec2(dwi - 1, 1), 0).gb;
					float along = dot(rel, cut.rg);
					float across = abs(dot(rel, vec2(-cut.g, cut.r)));
					if (across < CUT_REACH) {
						float vc = mix(space_level(ri), space_level(hi), smoothstep(-CUT_FEATHER, CUT_FEATHER, along));
						float other = a_in ? 0.0 : space_level(sa);
						if (!b_in) {
							other = max(other, space_level(sb));
						}
						v = max(vc, other);
					}
				}
			}
		}

		if (v >= 0.999) {
			ALBEDO = src;
			ALPHA = 0.0;
		} else {
			int bcode = int(cd.b * 255.0 + 0.5);
			bool wall_cell = bcode == 255;
			float floor_y = wall_cell ? wc.y : float(bcode - 64) * LH;
			float above = max(0.0, wc.y - floor_y);
			bool wall_part = wall_cell || above > 0.3;
			if (wall_cell) {
				above = 1.5;
			}
			float grid = 1.0 - smoothstep(0.015, 0.045, edge_dist);
			grid *= top ? 1.0 : 0.0;
			// one shade per kite (the six triangles of a hex), breathing slowly: faceted smoke
			float ang = atan(-off.y, off.x);
			float kite = floor(mod(ang / 1.0471976 + 6.0, 6.0));
			float h = hash3(vec3(float(c.x), float(c.y), kite));
			float facet = 0.82 + 0.18 * h + 0.10 * sin(TIME * (0.35 + 0.5 * h) + h * 6.2832);
			// smoke thins near an open doorway with its other side in view
			float thin = 0.0;
			if (dwi > 0) {
				vec4 dw = texelFetch(dyn, ivec2(dwi - 1, 1), 0);
				thin = dw.r * (1.0 - smoothstep(1.0, 6.0, length(xz - dw.gb)));
			}
			float x = clamp(v, 0.0, 1.0) * 3.0;
			int s0 = int(floor(x));
			float f = x - float(s0);
			vec3 c0 = state_color(s0, src, wc, above, wall_part, top, edge, grid, facet, thin);
			vec3 c1 = state_color(min(s0 + 1, 3), src, wc, above, wall_part, top, edge, grid, facet, thin);
			ALBEDO = mix(c0, c1, f);
			ALPHA = 1.0;
		}
	}
}
"""

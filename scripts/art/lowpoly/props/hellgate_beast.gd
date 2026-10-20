class_name HellgateBeast
extends Node3D
## The monster UNDER a hellgate room. The gate is a wound in its hide; the rest of it lives under the level and grips it
## from below: long tentacles come out from UNDER the floor slab (their roots hidden by the level itself), hug the cliff
## faces and the outside of the room's walls for several hexes and lift their tips over the wall tops. Every hellgate
## room has one (the "abyss" look, chosen by the user 2026-10-19); the origin gate's is bigger.
##
## COSMETIC ONLY (networking.md: the "cosmetic" shape): no collision, no gameplay state, no net traffic. SiteBuilder.spawn
## builds it on every machine from the floor (the room's cells, a seed from the gate's cell and the floor seed), so co-op
## screens match; it never draws from GameWorld.rng (nor GameWorld.fx_rng: a seeded generator of its own, the same on every
## machine). It WATCHES its gate (watch()), on every machine from what that machine already has:
##   - HURT: the gate's HP drops (the host's own, a client's replicated puppet HP): the limbs flinch back along their
##     paths and flail, harder for a bigger hit, a little more under sustained fire, then settle; at low HP they writhe.
##   - EXIT: the gate dies (closed on the host, Net.remote_die on a client, the late-join snapshot's gone ids on a
##     joiner): every limb RETRACTS tip-first down its own path into the dark under the level (EXIT_STYLE "retract", the
##     default) or WHIPS away (snap back, one lash, a fast drop: "whip"), the thinnest first and the biggest last, then
##     the beast hides. A gate already dead or gone on the beast's FIRST frame (a late joiner applies the snapshot while
##     the world is frozen, before the floor starts) means it is gone at once: a joiner never sees a closed gate's beast.
## CLEARANCE (BeastLimbs): every limb's centreline, with an envelope covering everything the shader can do to it (the
## sway, the low-HP writhe, the hurt flail, the beat's swell, the suckers and spines), keeps MARGIN clear of the level
## (the terrain's columns, the room's props and decor, the gate), of itself and of every limb already placed on the
## floor (every gate's beast). A limb that would touch is pushed out of the level, then re-rolled with the beast's own
## seeded dice (shorter, thinner, a gentler hook, no spines) or dropped. The exits slide each vertex back along its own
## centreline with a radius no bigger than what was already there, so they stay clear too.
##
## STYLES (make(style, ...)):
##   abyss   a few huge, thick wrapping tentacles: out from under the slab, up and along the walls, tips over the top.
##           The game's look.
##   peek    (lab only, scenes/hellgate_beast_lab.tscn) one huge eye watching over the back wall, a lower jaw of fangs
##           rising from under the front edge, two giant wrapping tentacles.
## The ORIGIN gate's room gets a bigger version (more, longer and thicker tentacles, the origin gate's slower beat).
##
## PLACEMENT: rim() walks the room's boundary WALL cells; every hex edge of a wall cell that faces the VOID (no cell
## beyond it) is a rim edge (midpoint, outward normal, wall top). Wall cells within DOOR_CLEAR of anything that is not
## this room (corridors, the start / exit cells, another room) are skipped, so nothing grows by a doorway. Rim edges
## join into RUNS along the walls' outer silhouette (chains()); a tentacle takes a stretch of a run. On a stretch the
## camera sees from outside (the front and the sides: `back` low) it climbs the cliff face; on one behind the room it
## rises behind the wall and lies along the wall top. Nothing reaches past the wall band into the room.
##
## ANIMATION: one clock, the gate model's (HellgateModel._t) while the gate lives, so the beast pulses on the gate core's
## beat. Tentacles are PATH tubes (BeastFlesh.path_tube): the beat runs along them as a bulge and the free tips sway, all
## on the GPU; a frame costs a few uniform writes (plus the eye's pivot for `peek`). freeze_at(t) for screenshots.

const STYLES: Array[String] = ["abyss", "peek"]
const GROUP := &"hellgate_beasts"
## How the beast leaves when its gate closes: "retract" (down its own paths) or "whip" (snap, lash, drop). The lab
## overrides it per beast (exit_style).
const EXIT_STYLE := "retract"
const EXIT_STAGGER := 0.2                      ## seconds between one limb's exit and the next's (retract)
const WHIP_STAGGER_K := 0.45                   ## the whip's stagger, as a share of the retract's
const STILL_EXIT := 1.0                        ## seconds the still pieces (peek's eye and jaw) take, after the limbs
const SWAY := 0.18                             ## a tip's sway at rest, x its lift
const HURT_CAP := 1.8                          ## the flail stacks this high under sustained fire (it shows above 1 as time)
const ATTEMPTS := 6                            ## re-rolls before a limb that would touch something is dropped
const REGISTRY := &"hellgate_beast_limbs"      ## HexMap meta: every limb placed on the floor
const VIEW := Vector3(0.3949, 0.8290, 0.3949)  ## towards the game camera, unit (yaw 45, pitch -56)
const CAM := Vector3(0.7071, 0.0, 0.7071)      ## towards the game camera, flat
const DOOR_CLEAR := 3                          ## hex cells kept clear of a room's doors
const LH := Hex.LEVEL_HEIGHT
const CLIFF_Y := HexMapView.FLOOR_DEPTH * Hex.LEVEL_HEIGHT   ## where the terrain's columns end (the slab's underside)

const BONE := Color(0.86, 0.79, 0.62)
const BONE_DARK := Color(0.55, 0.46, 0.34)
const GUM := Color(0.17, 0.03, 0.05)
const EYE_WHITE := Color(0.70, 0.62, 0.36)      ## a sick yellow
const EYE_VEIN := Color(0.40, 0.12, 0.08)
const IRIS := Color(1.0, 0.32, 0.05)
const IRIS_HOT := Color(1.0, 0.58, 0.14)
const PUPIL := Color(0.01, 0.0, 0.01)

const Limb := BeastFlesh.Limb

## Microseconds the last for_gate() calls spent building (summed since reset_build_clock()): the floor's cost.
static var build_usec := 0
## Clearance checks on (the game). Off: the limbs are built where the placement puts them, unchecked (the lab's "before").
static var check_clearance := true
static var debug_fails := false
## Microseconds per build phase (labs: where the time goes).
static var prof := {}

var style := "abyss"
var origin := false
var gate_model: HellgateModel = null
var beat_rate := 2.6
## The gate's cell (the beast's key: the same on every machine).
var gate_cell := Vector2i.ZERO
## Build stats: tris, meshes (MeshInstance3D), nodes (every node under this one, itself included), limbs.
var stats: Dictionary = {}
## A point worth a close look (labs): the eye, the first tentacle's emergence.
var focus := Vector3.ZERO

## How it leaves: "retract" or "whip" (EXIT_STYLE unless a lab says otherwise).
var exit_style := EXIT_STYLE

var _t := 0.0
var _frozen := false
var _gate: Node = null                  ## the Hellgate it belongs to (watch())
var _watching := false
var _seen_frame := false                ## the first animated frame happened
var _exit_t := -1.0                     ## seconds since leave() (< 0: staying)
var _exit_tentacles := 0.0              ## the last limb's exit delay
var _gone := false
var _last_hp := -1.0
var _hurt := 0.0
var _jerk := 0.0
var _writhe := 0.0
var _writhe_goal := 0.0
var _rng := RandomNumberGenerator.new()
var _flesh: ShaderMaterial              ## the tentacles' material (skeletal)
var _still: ShaderMaterial = null       ## the still pieces' (peek's eye and jaw)
var _map: HexMap
var _cells: Array[Vector2i] = []
var _gate_pos := Vector3.ZERO
var _obstacles: Array[Vector4] = []
var _level: BeastLimbs.Level
var _paths: Array = []                  ## BeastLimbs.Path per placed limb
var _infos: Array[Dictionary] = []
var _rejects := 0                       ## limb tries that touched something (re-rolled)
var _dropped := 0                       ## limbs given up
var _fails := {"level": 0, "self": 0, "limbs": 0}   ## what the re-rolled tries touched
var _rim: Array[Dictionary] = []
var _runs: Array[Dictionary] = []
var _taken: Array[Vector3] = []         ## run points already used by a tentacle
var _tris := 0
var _limbs := 0
var _static := Limb.new(1)             ## every non-moving flesh piece of the style, one mesh
# peek: the eye
var _eye_root: Node3D = null
var _eye_ball: Node3D = null
var _lid_top: Node3D = null
var _lid_bot: Node3D = null
var _eye_target := Vector3.ZERO


## Build a style around `room_cells` (one room's cells, its cut border cells included). gate_pos: the gate's world
## position. obstacles: things standing in the room the limbs keep clear of, as upright cylinders (x, z, radius, top y).
static func make(style_id: String, map: HexMap, room_cells: Array[Vector2i], gate_pos: Vector3, is_origin: bool,
		seed_value: int, obstacles: Array[Vector4] = []) -> HellgateBeast:
	var b := HellgateBeast.new()
	b.style = style_id
	b.origin = is_origin
	b.beat_rate = 1.7 if is_origin else 2.6
	b.gate_cell = Hex.from_world(gate_pos)
	b._map = map
	b._cells = room_cells
	b._gate_pos = gate_pos
	b._obstacles = obstacles
	b._rng.seed = seed_value
	b._build()
	return b


## THE GAME'S HOOK (SiteBuilder.spawn): the abyss beast for one spawned gate, in the gate's room of `plan`, added to the
## world (GameWorld.root, so it freezes with the world behind a load barrier) and watching the gate. Null when the gate's
## room has no rim to grip (every wall by a door).
static func for_gate(gate: Node3D, map: HexMap, plan: SitePlan, floor_seed: int) -> HellgateBeast:
	var t0 := Time.get_ticks_usec()
	var cell := Hex.from_world(gate.global_position)
	var room := ""
	var is_origin := false
	for g in plan.gates:
		if g["cell"] == cell:
			room = str(g["room"])
			is_origin = bool(g["origin"])
	if room == "":
		room = plan.room_of_cell(cell)
	if room == "" or not plan.rooms.has(room):
		return null
	var cells: Array[Vector2i] = []
	cells.assign(plan.rooms[room])
	var seed_value := hash(Vector3i(cell.x, cell.y, floor_seed))
	var b := make("abyss", map, cells, gate.global_position, is_origin, seed_value, obstacles_of(plan, gate.global_position, is_origin))
	build_usec += Time.get_ticks_usec() - t0
	if int(b.stats.get("limbs", 0)) == 0:
		b.free()
		return null
	b.name = "Beast_%d_%d" % [cell.x, cell.y]
	var parent: Node = GameWorld.root if GameWorld.root != null else gate.get_parent()
	parent.add_child(b)
	b.watch(gate)
	return b


static func reset_build_clock() -> void:
	build_usec = 0


## What stands in a gate's room for the limbs to keep clear of, as upright cylinders (x, z, radius, top y): the priced
## props and the decor near the gate (from the plan: the same on every machine) and the gate itself.
static func obstacles_of(plan: SitePlan, gate_pos: Vector3, is_origin: bool) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var floor_y := gate_pos.y
	var reach := 16.0
	for pr in plan.props:
		if not pr.has("pos"):
			continue
		var pos: Vector2 = pr["pos"]
		if pos.distance_to(Vector2(gate_pos.x, gate_pos.z)) > reach:
			continue
		var foot: Vector2 = pr.get("foot", Vector2(1.2, 1.2))
		out.append(Vector4(pos.x, pos.y, 0.5 * maxf(foot.x, foot.y) + 0.15, floor_y + 3.0))
	for d in plan.decor:
		var pos: Vector2 = d["pos"]
		if pos.distance_to(Vector2(gate_pos.x, gate_pos.z)) > reach:
			continue
		var r := 0.5 * maxf(float(d.get("w", 1.0)), float(d.get("d", 1.0))) + 0.15
		out.append(Vector4(pos.x, pos.y, r, floor_y + 3.0 + float(d.get("lift", 0.0))))
	var k := HellgateModel.ORIGIN_SCALE if is_origin else 1.0
	out.append(Vector4(gate_pos.x, gate_pos.z, HellgateModel.R * 1.5 * k, floor_y + 3.6 * k))
	return out


## Follow a Hellgate: its model's clock (the beat) while it lives; sink away once it is dead or gone.
func watch(gate: Node) -> void:
	_gate = gate
	_watching = true
	var m: Variant = gate.get("model")
	if m is HellgateModel:
		gate_model = m


func set_gate(m: HellgateModel) -> void:
	gate_model = m


## Screenshots: hold the animation at `seconds` (the gate model should be frozen at the same time).
func freeze_at(seconds: float) -> void:
	_frozen = true
	_t = seconds
	_animate()


## "out", "leaving" or "gone" (tests and labs).
func state() -> String:
	if _gone:
		return "gone"
	return "leaving" if _exit_t >= 0.0 else "out"


## How hard it is flailing now (0 settled; tests and labs).
func flail() -> float:
	return _hurt


# ------------------------------------------------------------------ the rim

## The room's rim edges: [{mid, a, b (edge ends, at the wall top), normal (outward, horizontal), top (wall top y),
## wall (cell), back (0..1)}], in a stable order.
static func rim(map: HexMap, room_cells: Array[Vector2i]) -> Array[Dictionary]:
	var tag := ""
	for c in room_cells:
		var cell := map.get_cell(c)
		if cell != null and cell.tag.begins_with("room:"):
			tag = cell.tag
			break
	var walls := {}
	for c in room_cells:
		for d in 6:
			var n: Vector2i = c + Hex.DIRS[d]
			var cell := map.get_cell(n)
			if cell != null and cell.type == HexMap.Tile.WALL:
				walls[n] = true
	var keys: Array = walls.keys()
	keys.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.x < q.x or (p.x == q.x and p.y < q.y))
	var out: Array[Dictionary] = []
	for w: Vector2i in keys:
		var by_door := false
		for n in Hex.range_cells(w, DOOR_CLEAR):
			var cell := map.get_cell(n)
			if cell != null and cell.type != HexMap.Tile.WALL and cell.tag != tag:
				by_door = true
				break
		if by_door:
			continue
		var top := float(map.get_cell(w).level) * LH
		var cw := Hex.to_world(w)
		for d in 6:
			if map.get_cell(w + Hex.DIRS[d]) != null:
				continue
			var nrm := Hex.dir_vector(d)
			var mid := cw + Hex.edge_mid(d)
			mid.y = top
			var perp := Vector3(-nrm.z, 0.0, nrm.x)
			out.append({"mid": mid, "a": mid - perp * 0.5, "b": mid + perp * 0.5, "normal": nrm, "top": top, "wall": w,
					"back": 0.5 * (1.0 - nrm.dot(CAM))})
	return out


## Rim edges joined end to end into runs along the outer silhouette of the walls: Array of Array[Vector3] points.
static func chains(edges: Array[Dictionary]) -> Array:
	var by_end := {}
	for i in edges.size():
		for key: Vector3i in [_k(edges[i]["a"]), _k(edges[i]["b"])]:
			if not by_end.has(key):
				by_end[key] = []
			(by_end[key] as Array).append(i)
	var used := {}
	var out: Array = []
	for pass_i in 2:
		for i in edges.size():
			if used.has(i):
				continue
			var e: Dictionary = edges[i]
			var here: Vector3 = e["a"]
			if pass_i == 0:
				# first pass: start only at the open end of a run
				if (by_end[_k(e["a"])] as Array).size() == 1:
					here = e["a"]
				elif (by_end[_k(e["b"])] as Array).size() == 1:
					here = e["b"]
				else:
					continue
			var pts: Array[Vector3] = [here]
			var cur := i
			while cur >= 0:
				used[cur] = true
				var ce: Dictionary = edges[cur]
				var nxt: Vector3 = ce["b"] if _k(ce["a"]) == _k(here) else ce["a"]
				pts.append(nxt)
				here = nxt
				cur = -1
				for j: int in by_end[_k(here)]:
					if not used.has(j):
						cur = j
						break
			out.append(pts)
	return out


static func _k(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * 100.0), 0, roundi(p.z * 100.0))


## The runs, rounded off (one Chaikin pass) with an outward normal and the distance along the run at each point:
## [{pts, nrms, cum, closed}].
func _make_runs() -> void:
	for run: Array in chains(_rim):
		if run.size() < 3:
			continue
		var raw: Array[Vector3] = []
		raw.assign(run)
		var closed := _k(raw[0]) == _k(raw[raw.size() - 1])
		var pts := _chaikin(raw, closed)
		var nrms: Array[Vector3] = []
		var cum: Array[float] = [0.0]
		for i in pts.size():
			nrms.append(_outward_near(pts[i]))
			if i > 0:
				cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		_runs.append({"pts": pts, "nrms": nrms, "cum": cum, "closed": closed})


## Chaikin corner cutting (one pass): the hex corners of the rim become a rounded run.
static func _chaikin(pts: Array[Vector3], closed: bool) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := pts.size()
	if n < 3:
		return pts.duplicate()
	if not closed:
		out.append(pts[0])
	for i in n - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	if closed:
		out.append(out[0])
	else:
		out.append(pts[n - 1])
	return out


## The rim's outward normal near a point: the normals of the rim edges within reach, weighted by nearness.
func _outward_near(p: Vector3) -> Vector3:
	var sum := Vector3.ZERO
	for e in _rim:
		var d := Vector2((e["mid"] as Vector3).x - p.x, (e["mid"] as Vector3).z - p.z).length()
		if d < 1.6:
			sum += (e["normal"] as Vector3) * (1.6 - d)
	if sum.length() < 0.001:
		return Vector3.FORWARD
	return sum.normalized()


static func _back(n: Vector3) -> float:
	return 0.5 * (1.0 - n.dot(CAM))


## Farthest-point picks from `items` (each with a "mid"): the first is the best `score`, then each next maximises the
## distance to those already picked times its score. Stops at `count` or when nothing is `min_gap` away.
func _spread(items: Array[Dictionary], count: int, min_gap: float, score: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if items.is_empty():
		return out
	var jit: Array[float] = []
	for e in items:
		jit.append(_rng.randf_range(0.0, 0.15))
	while out.size() < count:
		var best := -1
		var best_v := -1.0
		for i in items.size():
			var e: Dictionary = items[i]
			var d := 1.0e9
			for o in out:
				d = minf(d, (e["mid"] as Vector3).distance_to(o["mid"]))
			if not out.is_empty() and d < min_gap:
				continue
			var v := (float(score.call(e)) + jit[i]) * (1.0 if out.is_empty() else minf(d, 12.0))
			if v > best_v:
				best_v = v
				best = i
		if best < 0:
			break
		out.append(items[best])
	return out


# ------------------------------------------------------------------ build

func _build() -> void:
	name = "HellgateBeast_" + style
	_flesh = BeastFlesh.make(2.6 if origin else 2.3)
	_still = BeastFlesh.make(2.6 if origin else 2.3)
	for m: ShaderMaterial in [_flesh, _still]:
		BeastFlesh.set_both(m, "beat_rate", beat_rate)
		BeastFlesh.set_both(m, "fade_lo", CLIFF_Y - 4.2)
		BeastFlesh.set_both(m, "fade_hi", CLIFF_Y - 0.9)
	_level = BeastLimbs.Level.new(_map)
	for o in _obstacles:
		_level.add_cylinder(Vector2(o.x, o.y), o.z, o.w)
	_rim = rim(_map, _cells)
	_make_runs()
	match style:
		"abyss":
			BeastFlesh.set_both(_flesh, "sway_rate", 0.45)
			_build_abyss()
		"peek":
			BeastFlesh.set_both(_flesh, "sway_rate", 0.35)
			_build_peek()
	_build_limbs()
	if _static.tri_count() > 0:
		_add_mesh("Flesh", _static.to_mesh(0.0), Transform3D.IDENTITY, _still)
	_animate()
	stats = {"tris": _tris, "meshes": _count_meshes(self), "nodes": _count_nodes(self), "limbs": _limbs, "rim_edges": _rim.size(),
			"rejects": _rejects, "dropped": _dropped, "fails": _fails}


func _add_mesh(node_name: String, mesh: ArrayMesh, xf: Transform3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat if mat != null else _flesh
	mi.transform = xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_tris += _mesh_tris(mesh)
	return mi


static func _mesh_tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static func _count_meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c


static func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c


# ------------------------------------------------------------------ the wrapping tentacle

## Candidate starts for wrapping tentacles: every ~0.9 along every run, with the direction that leaves the most run
## ahead: [{mid, run, i, dir, ahead, back}].
func _wrap_starts(min_ahead: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ri in _runs.size():
		var run: Dictionary = _runs[ri]
		var cum: Array[float] = run["cum"]
		var pts: Array[Vector3] = run["pts"]
		var total := cum[cum.size() - 1]
		var last := -10.0
		for i in pts.size():
			if cum[i] - last < 0.9:
				continue
			last = cum[i]
			var fwd := total - cum[i]
			var bwd := cum[i]
			if bool(run["closed"]):
				fwd = total * 0.45      # (round a closed loop: never so far that it comes back to its own root)
				bwd = 0.0
			var dir := 1 if fwd >= bwd else -1
			var ahead := maxf(fwd, bwd)
			if ahead < min_ahead:
				continue
			out.append({"mid": pts[i], "run": ri, "i": i, "dir": dir, "ahead": ahead, "back": _back(run["nrms"][i])})
	return out


## Pick `count` starts spread round the room, keeping off stretches other tentacles took.
func _pick_wraps(count: int, min_ahead: float, gap: float, score: Callable) -> Array[Dictionary]:
	var cands: Array[Dictionary] = []
	for c in _wrap_starts(min_ahead):
		var free := true
		for p in _taken:
			if p.distance_to(c["mid"]) < 1.6:
				free = false
				break
		if free:
			cands.append(c)
	return _spread(cands, count, gap, score)


## One long tentacle from a picked start: out from under the slab, along `along` of the run, tip over the wall. Its
## centreline is checked against the level, itself and every limb already on the floor (BeastLimbs); on a hit it is
## re-rolled (shorter, thinner, a gentler hook, no spines: the beast's own seeded dice) up to ATTEMPTS times, then
## dropped. r_base: its girth where it comes out; lift: how high the tip rears (1 = about a wall height). Returns
## whether it was placed.
func _wrap(start: Dictionary, along: float, r_base: float, lift: float, opts: Dictionary = {}) -> bool:
	var hook := 0.4 if check_clearance else 1.0
	var spines := float(opts.get("spines", 0.0)) > 0.0
	for attempt in ATTEMPTS:
		var tp := Time.get_ticks_usec()
		var path := _wrap_path(start, along, r_base, lift, hook)
		prof["path"] = int(prof.get("path", 0)) + Time.get_ticks_usec() - tp
		if path == null:
			return false
		if spines:
			_add_spines(path, float(opts.get("spines", 1.4)))
		if not check_clearance:
			_accept(path, start, r_base, opts)
			return true
		var tc := Time.get_ticks_usec()
		var c := BeastLimbs.clearances(path, _level, _floor_paths())
		prof["check"] = int(prof.get("check", 0)) + Time.get_ticks_usec() - tc
		if float(c["worst"]) < BeastLimbs.MARGIN and not path.spines.is_empty():
			path.spines.clear()
			path.update_box()
			c = BeastLimbs.clearances(path, _level, _floor_paths())
		if float(c["worst"]) >= BeastLimbs.MARGIN:
			_accept(path, start, r_base, opts)
			return true
		_rejects += 1
		if debug_fails:
			var at := BeastLimbs.worst_at
			var best_i := 0
			for i in path.size():
				if path.pts[i].distance_to(at) < path.pts[best_i].distance_to(at):
					best_i = i
			print("  fail %s  s %.1f / %.1f (grip %.1f)  y %.2f  sdf %.3f env %.3f  free %.2f" % [str(c), best_i * BeastLimbs.STEP,
					path.length(), path.grip_end, at.y, _level.sdf(at), path.env(best_i), path.free[best_i]])
		for key in _fails:
			if float(c[key]) < BeastLimbs.MARGIN:
				_fails[key] += 1
		# re-roll: what failed decides what gives
		if float(c["self"]) < BeastLimbs.MARGIN:
			# the tip folds into itself: first lose the hook, then rear less
			if hook > 0.0:
				hook = 0.0
			else:
				lift *= 0.8
		if float(c["limbs"]) < BeastLimbs.MARGIN or float(c["level"]) < BeastLimbs.MARGIN:
			along *= _rng.randf_range(0.7, 0.85)
			lift *= _rng.randf_range(0.8, 1.05)
		r_base *= 0.9
		if along < 2.5:
			break
	_dropped += 1
	return false


func _wrap_path(start: Dictionary, along: float, r_base: float, lift: float, hook: float) -> BeastLimbs.Path:
	var run: Dictionary = _runs[int(start["run"])]
	var pts: Array[Vector3] = run["pts"]
	var nrms: Array[Vector3] = run["nrms"]
	var n_pts := pts.size()
	var closed: bool = run["closed"]
	var dir: int = start["dir"]
	var idx: Array[int] = [int(start["i"])]
	var dist := 0.0
	var j: int = start["i"]
	# (and short of any stretch a limb already placed on this floor lies along: tentacles never queue on one wall)
	var occupied := _occupied_points() if check_clearance else PackedVector3Array()
	var keep_off := r_base * BeastLimbs.ENV_K * 2.0 + 0.9
	while dist < along:
		var nj := j + dir
		if closed:
			nj = posmod(nj, n_pts - 1)
		elif nj < 0 or nj >= n_pts:
			break
		var blocked := false
		for q in occupied:
			if Vector2(q.x - pts[nj].x, q.z - pts[nj].z).length() < keep_off and q.y > CLIFF_Y - 0.5:
				blocked = true
				break
		if blocked:
			break
		dist += pts[nj].distance_to(pts[j])
		idx.append(nj)
		j = nj
	if idx.size() < 3 or dist < 2.0:
		return null
	var k_env := BeastLimbs.ENV_K
	var gap := BeastLimbs.MARGIN + 0.05     # clearance built in (the push-out takes care of the rest)
	var lift_tip := 1.0
	if not check_clearance:
		# the unchecked placement is the one the first wired version shipped (lab: "before")
		k_env = 1.0
		gap = 0.05
		lift_tip = 0.0
	var i0 := idx[0]
	var n0 := nrms[i0]
	var t0 := (pts[idx[1]] - pts[i0]).normalized()
	var top0 := pts[i0].y
	var face := _back(n0) < 0.62          # the camera sees this stretch's cliff face: climb it; else lie on the top
	var ctrl: Array[Vector3] = []
	var rad: Array[float] = []
	# It lives under the level: the root runs in the dark under the floor slab, presses along its underside and wraps
	# round the slab's bottom edge (the game camera sees it come out from under the cliff), then climbs.
	var r := r_base
	var under := Vector3(0, CLIFF_Y - top0, 0)
	# (the root drops away steeply under the slab rather than running far in under the room, where the roots of
	# neighbouring limbs would converge)
	if check_clearance:
		ctrl.append(pts[i0] - n0 * 1.3 - t0 * 1.6 + under + Vector3(0, -3.8 - r, 0))
		ctrl.append(pts[i0] - n0 * 1.4 - t0 * 0.6 + under + Vector3(0, -r * k_env - gap - 0.5, 0))
	else:
		ctrl.append(pts[i0] - n0 * 5.2 - t0 * 1.2 + under + Vector3(0, -2.2, 0))
		ctrl.append(pts[i0] - n0 * 2.6 - t0 * 0.5 + under + Vector3(0, -r - 0.08, 0))
	ctrl.append(pts[i0] - n0 * 0.45 + under + Vector3(0, -r * k_env - gap, 0))
	ctrl.append(pts[i0] + n0 * (r * k_env + gap) + under + Vector3(0, -r * 0.3, 0))
	rad.append_array([r * 1.1, r * 1.05, r, r * 0.98])
	if not face:
		# behind the room: up the back of the wall and over its outer edge
		ctrl.append(pts[i0] + n0 * (r * k_env + gap) + Vector3(0, -0.7, 0))
		ctrl.append(pts[i0] + n0 * (r * k_env * 0.5) + Vector3(0, r * k_env + gap, 0))
		rad.append_array([r * 0.96, r * 0.94])
	var m := idx.size()
	# (a thick limb follows the wall in wider steps and a gentler wave: it can't take a bend tighter than its girth)
	var stride := 2 if r_base > 0.6 and check_clearance else 1
	var wave := 0.32 * (clampf(0.6 / r_base, 0.35, 1.0) if check_clearance else 1.0)
	for k in range(1, m):
		if k % stride != 0 and k != m - 1:
			continue
		var f := float(k) / float(m - 1)
		var p := pts[idx[k]]
		var n := nrms[idx[k]]
		var rk := lerpf(r_base * 0.92, r_base * 0.5, f)
		if face:
			var y := lerpf(CLIFF_Y + rk, p.y - rk * 0.6, smoothstep(0.0, 1.0, f))
			y += wave * sin(f * PI * 3.0 + float(start["i"])) * (1.0 - f) * f * 3.0
			ctrl.append(p + n * (rk * k_env + gap) + Vector3(0, y - p.y, 0))
		else:
			ctrl.append(p - n * 0.62 + Vector3(0, rk * k_env + gap, 0))
		rad.append(rk)
	# over the top, rear up and hook back (never past the wall band into the room)
	var je := idx[m - 1]
	var pe := pts[je]
	var ne := nrms[je]
	var te := (pts[je] - pts[idx[m - 2]]).normalized()
	var re := r_base * 0.45
	var up := Vector3.UP * lift
	var grip_idx := ctrl.size()
	if face:
		ctrl.append(pe + ne * 0.05 + te * 0.4 + Vector3(0, re * k_env + gap, 0))
	ctrl.append(pe - ne * 0.8 + te * 0.6 + Vector3(0, re * k_env + gap + 0.05, 0))
	var rise := Vector3(0, re * lift_tip, 0)
	if check_clearance:
		# (the free, moving part starts where it rears: the turn over the wall band stays still, so it can't fold)
		grip_idx = ctrl.size() - 1
		# rears up in a long diagonal along the wall: a thick limb can't turn straight up without folding into itself
		ctrl.append(pe - ne * 1.25 + te * 1.4 + up * 0.7 + rise)
		var r2 := pe - ne * 1.2 + te * 2.2 + up * 1.5 + rise
		ctrl.append(r2)
		# the tip carries on and curls only as far as `hook` says (hook 0: straight on, no hairpin at the end)
		var h1 := r2 + te * 0.5 + up * 0.45 + ne * 0.3 * hook
		ctrl.append(h1)
		ctrl.append(h1 + te * (0.35 - 0.6 * hook) + up * (0.1 - 0.35 * hook) + ne * 0.3 * hook)
	else:
		ctrl.append(pe - ne * 1.35 + te * 0.9 + up * 0.9 + rise)
		ctrl.append(pe - ne * 1.25 + te * 1.2 + up * 1.8 + rise)
		ctrl.append(pe - ne * (1.25 - 0.6 * hook) + te * (1.2 + 0.1 * hook) + up * (1.8 + 0.35 * hook) + rise)
		ctrl.append(pe - ne * (1.25 - 1.0 * hook) + te * (1.2 - 0.2 * hook) + up * (1.8 + 0.05 * hook) + rise)
	var n_tip := ctrl.size() - rad.size()
	for k in n_tip:
		var f := float(k + 1) / float(n_tip)
		rad.append(lerpf(re, 0.035, f))
	var path := BeastLimbs.from_ctrl(ctrl, rad, grip_idx, (SWAY if check_clearance else 0.3) * lift)
	# the tip sways across itself (in and out over the wall band), never along itself (that would fold it)
	var across := Vector3(-te.z, 0.0, te.x)
	path.side = across.normalized() if across.length() > 0.01 else Vector3.RIGHT
	if check_clearance:
		var tp := Time.get_ticks_usec()
		BeastLimbs.push_out(path, _level)
		prof["push"] = int(prof.get("push", 0)) + Time.get_ticks_usec() - tp
	return path


## Obsidian spines along the back of the gripping stretch (BeastLimbs checks their tips).
func _add_spines(path: BeastLimbs.Path, gap: float) -> void:
	var total := path.length()
	var at := total * 0.15
	while at < total * 0.62:
		var i := clampi(roundi(at / BeastLimbs.STEP), 0, path.size() - 1)
		var r := path.radii[i]
		var upv := path.ys[i] if path.ys[i].y >= 0.0 else -path.ys[i]
		var d := (upv - path.ts[i] * 0.55).normalized()
		path.spines.append({"i": i, "dir": d, "h": r * _rng.randf_range(1.1, 1.7), "r": r * 0.36})
		at += gap * _rng.randf_range(0.8, 1.2)
	path.update_box()


## A placed limb: kept for the mesh (built once every limb is known) and registered on the floor.
func _accept(path: BeastLimbs.Path, start: Dictionary, r_base: float, opts: Dictionary) -> void:
	_paths.append(path)
	var emerge := path.pts[mini(3, path.size() - 1)]
	var weight := clampf(1.3 - Vector2(emerge.x - _gate_pos.x, emerge.z - _gate_pos.z).length() / 14.0, 0.45, 1.0)
	_infos.append({"girth": r_base, "phase": _rng.randf() * TAU, "weight": weight, "sides": int(opts.get("sides", 7)),
			"suckers": float(opts.get("suckers", 0.55)), "seed": _rng.randi()})
	for i in path.size():
		if i % 3 == 0:
			_taken.append(path.pts[i])
	_floor_registry().append({"path": path, "owner": get_instance_id()})
	if focus == Vector3.ZERO:
		focus = path.pts[mini(3, path.size() - 1)]


## Every limb's mesh, once all are placed: one skeleton texture for the beast, the bigger limbs leaving last.
func _build_limbs() -> void:
	if _paths.is_empty():
		return
	var order: Array[int] = []
	for i in _paths.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return float(_infos[a]["girth"]) < float(_infos[b]["girth"]))
	for rank in order.size():
		_infos[order[rank]]["delay"] = float(rank) * EXIT_STAGGER + _rng.randf_range(0.0, 0.08)
	var tm := Time.get_ticks_usec()
	var tex := BeastFlesh.skeleton(_paths, _infos)
	BeastFlesh.set_both(_flesh, "skel", tex)
	BeastFlesh.set_both(_flesh, "skeletal", true)
	_exit_tentacles = 0.0
	for k in _paths.size():
		_exit_tentacles = maxf(_exit_tentacles, float(_infos[k]["delay"]))
		var inf: Dictionary = _infos[k]
		var mesh := BeastFlesh.path_tube(_paths[k], k, int(inf["seed"]), int(inf["sides"]), float(inf["suckers"]))
		_limbs += 1
		_add_mesh("Tentacle%d" % _limbs, mesh, Transform3D.IDENTITY)
	prof["mesh"] = int(prof.get("mesh", 0)) + Time.get_ticks_usec() - tm


## Score for picking wrap starts: the sides first (their climb out from under the slab reads best), then behind.
static func _wrap_score(e: Dictionary) -> float:
	var b: float = e["back"]
	return 0.6 + 0.8 * (1.0 - absf(b - 0.5) * 2.0) + 0.3 * b


# ------------------------------------------------------------------ the floor's limbs

## Every limb placed on this floor (every beast's), on the map: a beast keeps clear of its neighbours'.
func _floor_registry() -> Array:
	if not _map.has_meta(REGISTRY):
		_map.set_meta(REGISTRY, [])
	return _map.get_meta(REGISTRY)


## Every third point of every limb already on the floor.
func _occupied_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for e: Dictionary in _floor_registry():
		var p: BeastLimbs.Path = e["path"]
		for i in range(0, p.size(), 3):
			out.append(p.pts[i])
	return out


func _floor_paths() -> Array:
	var out: Array = []
	for e: Dictionary in _floor_registry():
		out.append(e["path"])
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _map != null and _map.has_meta(REGISTRY):
		var reg: Array = _map.get_meta(REGISTRY)
		var me := get_instance_id()
		for i in range(reg.size() - 1, -1, -1):
			if int((reg[i] as Dictionary)["owner"]) == me:
				reg.remove_at(i)


## The worst clearances of this beast's limbs (level, self, against the floor's other limbs): {level, self, limbs, worst}.
func clearance_report() -> Dictionary:
	var out := {"level": 1.0e9, "self": 1.0e9, "limbs": 1.0e9, "worst": 1.0e9}
	for p: BeastLimbs.Path in _paths:
		var others: Array = []
		for q in _floor_paths():
			if q != p:
				others.append(q)
		var c := BeastLimbs.clearances(p, _level, others)
		if float(c["worst"]) < float(out["worst"]):
			out["at"] = BeastLimbs.worst_at
		for key in ["level", "self", "limbs", "worst"]:
			out[key] = minf(float(out[key]), float(c[key]))
	return out


# ------------------------------------------------------------------ A. abyss

func _build_abyss() -> void:
	var count := 9 if origin else 5
	var k := 1.3 if origin else 1.0
	for st in _pick_wraps(count, 4.0, 4.0 if origin else 4.5, _wrap_score):
		var along := minf(float(st["ahead"]) - 0.6, _rng.randf_range(6.0, 9.5) * k)
		var lift := lerpf(0.6, 1.25, float(st["back"])) * _rng.randf_range(0.9, 1.1)
		_wrap(st, along, _rng.randf_range(0.8, 1.0) * k, lift, {"sides": 8, "suckers": 0.65, "spines": 1.4})


# ------------------------------------------------------------------ C. peek

func _build_peek() -> void:
	var k := 1.45 if origin else 1.0
	# the eye: behind the most "back" stretch of wall
	var eye_edges := _spread(_rim, 1, 0.0, func(e: Dictionary) -> float: return pow(float(e["back"]), 3.0) * (1.0 + _neighbours(e) * 0.3))
	if not eye_edges.is_empty():
		_build_eye(eye_edges[0], k)
		_taken.append(eye_edges[0]["mid"])
	# the lower jaw: fangs rising from under the front edge
	var front: Array[Dictionary] = []
	for e in _rim:
		if float(e["back"]) < 0.3:
			front.append(e)
	_build_jaw(front, k)
	for e in front:
		_taken.append(e["mid"])
	# two giant wrapping tentacles on the sides
	for st in _pick_wraps(3 if origin else 2, 6.0, 7.0, _wrap_score):
		var along := minf(float(st["ahead"]) - 0.6, _rng.randf_range(8.0, 11.0) * k)
		_wrap(st, along, 0.85 * k, 1.2, {"sides": 8, "suckers": 0.6, "spines": 1.2})


## How many other rim edges lie within 2.2 of this one (a long straight wall scores higher).
func _neighbours(e: Dictionary) -> float:
	var n := 0.0
	for o in _rim:
		if o != e and (o["mid"] as Vector3).distance_to(e["mid"]) < 2.2:
			n += 1.0
	return n


func _build_eye(e: Dictionary, k: float) -> void:
	var re := 2.6 * k
	var nrm: Vector3 = e["normal"]
	var top: float = e["top"]
	# behind the wall's outer edge, low enough that the wall hides its lower part: it peeks over the rim
	var c: Vector3 = (e["mid"] as Vector3) + nrm * (re + 0.25)
	c.y = top - re * 0.2
	_eye_root = Node3D.new()
	_eye_root.name = "Eye"
	_eye_root.position = c
	add_child(_eye_root)
	_level.add_cylinder(Vector2(c.x, c.z), re * 1.4, c.y + re * 1.4)
	# socket: a ring of heavy dark lumps (brow, cheek) round the ball
	var sock := Limb.new(_rng.randi())
	for i in 9:
		var a := TAU * float(i) / 9.0
		var off := Vector3(cos(a) * 1.18, sin(a) * 1.02, 0.0) * re
		var col := BeastFlesh.FLESH_DARK.lerp(BeastFlesh.FLESH, 0.55 + 0.45 * sin(a))
		var lump := LowPoly.boulder(Vector3(0.7, 0.45, 0.8) * re * _rng.randf_range(0.5, 0.62), 0, 0.2, col, _rng.randi(), 0.1)
		sock.merge(lump, Transform3D(Basis(Vector3(0, 0, 1), a + PI * 0.5), off - Vector3(0, 0, re * 0.2)))
	# obsidian growths on the brow (the gate's stone)
	for i in 3:
		var a := lerpf(0.75, 2.4, float(i) / 2.0)
		var h := re * _rng.randf_range(0.5, 0.85)
		var sp := LowPoly.cylinder(re * 0.12, re * 0.01, h, 4, BeastFlesh.OBSIDIAN if i % 2 == 0 else BeastFlesh.OBSIDIAN_LIGHT, _rng.randi(), 0.03)
		var dir := Vector3(cos(a), sin(a), 0.25).normalized()
		sock.merge(sp, Transform3D(Basis(Quaternion(Vector3.UP, dir)), Vector3(cos(a), sin(a), 0.0) * re * 1.35 + dir * h * 0.5))
	# face the camera (local +Z), so the iris shows over the wall
	_eye_root.basis = _basis_look(VIEW)
	_child_mesh(_eye_root, "Socket", sock)
	# the ball: a pivot that turns to follow the crew
	_eye_ball = Node3D.new()
	_eye_ball.name = "Ball"
	_eye_root.add_child(_eye_ball)
	var ball := Limb.new(_rng.randi())
	var sclera := LowPoly.boulder(Vector3.ONE * re, 1, 0.05, EYE_WHITE, _rng.randi(), 0.12)
	# the sclera darkens and reddens away from the front (the rim reads as a ball in a socket)
	for i in sclera.cols.size():
		var z := (sclera.verts[i * 3].z + sclera.verts[i * 3 + 1].z + sclera.verts[i * 3 + 2].z) / (3.0 * re)
		sclera.cols[i] = sclera.cols[i].lerp(EYE_VEIN, clampf(0.75 - z, 0.0, 1.0) * 0.8)
	ball.merge(sclera, Transform3D.IDENTITY)
	# iris (a glowing ring) and pupil (a black slit), on the ball's +Z
	var iris_r := re * 0.55
	for i in 12:
		var a0 := TAU * float(i) / 12.0
		var a1 := TAU * float(i + 1) / 12.0
		var p_in0 := Vector3(cos(a0) * iris_r * 0.45, sin(a0) * iris_r * 0.45, re * 1.005)
		var p_in1 := Vector3(cos(a1) * iris_r * 0.45, sin(a1) * iris_r * 0.45, re * 1.005)
		var p_out0 := Vector3(cos(a0) * iris_r, sin(a0) * iris_r, re * 0.9)
		var p_out1 := Vector3(cos(a1) * iris_r, sin(a1) * iris_r, re * 0.9)
		ball.quad(p_in0, p_out0, p_out1, p_in1, MonsterModel.glow(IRIS if i % 2 == 0 else IRIS.lerp(IRIS_HOT, 0.3)), Vector3.ZERO)
		ball.tri(Vector3(0, 0, re * 1.02), p_in0, p_in1, MonsterModel.glow(IRIS_HOT), Vector3.ZERO)
	var slit := LowPoly.boulder(Vector3(iris_r * 0.16, iris_r * 0.9, re * 0.05), 0, 0.0, PUPIL, 7, 0.0)
	ball.merge(slit, Transform3D(Basis(), Vector3(0, 0, re * 1.045)))
	_child_mesh(_eye_ball, "BallMesh", ball)
	# lids: two shells that close over the ball
	for top_lid in [true, false]:
		var pivot := Node3D.new()
		pivot.name = "LidTop" if top_lid else "LidBottom"
		_eye_root.add_child(pivot)
		var lid := Limb.new(_rng.randi())
		var rl := re * 1.07
		var sgn := 1.0 if top_lid else -1.0
		for i in 8:
			for j in 4:
				var u0 := float(i) / 8.0 * PI
				var u1 := float(i + 1) / 8.0 * PI
				var v0 := float(j) / 4.0 * PI * 0.5
				var v1 := float(j + 1) / 4.0 * PI * 0.5
				lid.quad(_lid_pt(u0, v0, rl, sgn), _lid_pt(u1, v0, rl, sgn), _lid_pt(u1, v1, rl, sgn), _lid_pt(u0, v1, rl, sgn),
						BeastFlesh.FLESH_HI if j == 0 else BeastFlesh.FLESH, Vector3.ZERO)
		_child_mesh(pivot, "Lid", lid)
		if top_lid:
			_lid_top = pivot
		else:
			_lid_bot = pivot
	_eye_target = _gate_pos + Vector3.UP * 0.8


func _child_mesh(parent: Node3D, node_name: String, lb: Limb) -> void:
	var mi := _add_mesh(node_name, lb.to_mesh(0.0), Transform3D.IDENTITY, _still)
	remove_child(mi)
	parent.add_child(mi)


## A point on a lid shell: a quarter sphere over the top (sgn 1) or bottom (-1), open towards +Z when the lid is up.
static func _lid_pt(u: float, v: float, r: float, sgn: float) -> Vector3:
	return Vector3(cos(u) * r * cos(v), sgn * sin(v) * r, -sin(u) * r * cos(v))


static func _basis_look(fwd: Vector3) -> Basis:
	var z := fwd.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


## The lower jaw: fangs rising from under the slab in front of the front walls (the room sits in the mouth), their
## tips just short of the wall top so they never cover the floor.
func _build_jaw(edges: Array[Dictionary], k: float) -> void:
	if edges.is_empty():
		return
	var s := Limb.new(_rng.randi())
	for e in _spread(edges, 9 if origin else 6, 1.6, func(_e: Dictionary) -> float: return 1.0):
		var nrm: Vector3 = e["normal"]
		var top: float = e["top"]
		var base: Vector3 = (e["mid"] as Vector3) + nrm * 0.75 + Vector3(-nrm.z, 0.0, nrm.x) * _rng.randf_range(-0.3, 0.3)
		base.y = CLIFF_Y - 1.4
		var h := (top - base.y) * _rng.randf_range(0.9, 1.05)
		var w := _rng.randf_range(0.42, 0.56) * k
		_level.add_cylinder(Vector2(base.x, base.z) - Vector2(nrm.x, nrm.z) * 0.3, w + 0.35, top + 0.4)
		var at := base
		var dir := (Vector3.UP + nrm * 0.12).normalized()
		for i in 3:
			var f0 := float(i) / 3.0
			var f1 := float(i + 1) / 3.0
			var seg_h := h / 3.0
			var cyl := LowPoly.cylinder(w * (1.0 - f0 * 0.82), w * (1.0 - f1 * 0.92), seg_h * 1.04, 6, BONE_DARK if i == 0 else BONE, _rng.randi(), 0.02, 1, 0.05)
			s.merge(cyl, Transform3D(Basis(Quaternion(Vector3.UP, dir)), at + dir * seg_h * 0.5))
			at += dir * seg_h
			dir = (dir - nrm * 0.18).normalized()       # curving back in towards the wall, like a closing jaw
		# the gum they grow from, tucked under the cliff's foot
		s.merge(LowPoly.boulder(Vector3(0.8, 0.5, 0.7) * k, 0, 0.15, GUM, _rng.randi(), 0.08), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), base + Vector3(0, 0.25, 0) - nrm * 0.3))
	_add_mesh("Jaw", s.to_mesh(0.0), Transform3D.IDENTITY, _still)


# ------------------------------------------------------------------ animation

func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if _frozen or _gone:
		return
	var live := gate_model != null and is_instance_valid(gate_model)
	if _watching:
		var dead := not is_instance_valid(_gate) or bool(_gate.get("dead"))
		if dead and _exit_t < 0.0:
			if not _seen_frame:
				_vanish()      # dead before the floor even started (a late joiner): never shown
				return
			leave()
		live = live and not dead
		if not dead:
			_watch_hp(delta)
	_t = gate_model._t if live else _t + delta
	_seen_frame = true
	_settle(delta)
	if _exit_t >= 0.0:
		_exit_t += delta
		if _exit_t >= exit_duration():
			_vanish()
			return
	_animate()


## Its gate was hit (the replicated HP dropped, on every machine): the limbs flinch back along their paths and flail,
## harder for a bigger hit and a little more under sustained fire; at low HP they never settle.
func _watch_hp(_delta: float) -> void:
	var hp := float(_gate.get("hp"))
	var max_hp := maxf(float(_gate.get("max_hp")), 1.0)
	if _last_hp < 0.0:
		_last_hp = hp
	if hp < _last_hp - 0.001:
		hurt((_last_hp - hp) / max_hp)
	_last_hp = hp
	_writhe_goal = 1.0 - smoothstep(0.12, 0.5, hp / max_hp)


## A hit of `frac` of the gate's max HP (labs and tests may call it directly).
func hurt(frac: float) -> void:
	_hurt = minf(_hurt + 0.55 + frac * 8.0, HURT_CAP)
	_jerk = minf(_jerk + 0.5 + frac * 6.0, 1.0)


func _settle(delta: float) -> void:
	_hurt = maxf(0.0, _hurt - delta * 0.85)
	_jerk = maxf(0.0, _jerk - delta * 4.5)
	_writhe = move_toward(_writhe, _writhe_goal, delta * 0.8)


## Start the exit (its gate closed): every limb retracts down its own path (or whips away: `exit_style`), the smallest
## first; the eye (peek) closes and goes last.
func leave() -> void:
	if _exit_t >= 0.0:
		return
	_exit_t = 0.0
	_hurt = 0.0
	_jerk = 0.0


## Seconds from leave() until it is hidden.
func exit_duration() -> float:
	var whip := exit_style == "whip"
	var t := _exit_tentacles * (WHIP_STAGGER_K if whip else 1.0) + (BeastFlesh.WHIP_TIME if whip else BeastFlesh.RETRACT_TIME)
	if _eye_root != null or _static.tri_count() > 0:
		t += STILL_EXIT
	return t + 0.05


func _vanish() -> void:
	_gone = true
	_exit_t = maxf(_exit_t, exit_duration())
	# fully withdrawn and hidden, whatever shows this node again later
	_animate()
	visible = false
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = false
	set_process(false)


func _animate() -> void:
	var whip := exit_style == "whip"
	BeastFlesh.set_both(_flesh, "t", _t)
	BeastFlesh.set_both(_flesh, "exit_mode", 1 if whip else 0)
	# (the delays in the skeleton are the retract's; the whip goes faster, so its stagger is compressed: delay_k)
	BeastFlesh.set_both(_flesh, "exit_t", -1.0 if _exit_t < 0.0 else _exit_t)
	BeastFlesh.set_both(_flesh, "delay_k", WHIP_STAGGER_K if whip else 1.0)
	BeastFlesh.set_both(_flesh, "hurt", _hurt)
	BeastFlesh.set_both(_flesh, "jerk", _jerk)
	BeastFlesh.set_both(_flesh, "writhe", _writhe)
	var still := 0.0
	if _exit_t >= 0.0:
		var t_still := _exit_t - (exit_duration() - STILL_EXIT - 0.05)
		still = clampf(t_still / STILL_EXIT, 0.0, 1.0)
	if _still != null:
		BeastFlesh.set_both(_still, "t", _t)
		BeastFlesh.set_both(_still, "sink", still * still)
	if _eye_ball != null:
		_animate_eye(1.0 if _exit_t >= 0.0 else 0.0)


func _animate_eye(closing: float) -> void:
	# it looks out at the camera's side of the room; the gaze drifts and glances towards the gate area
	var glance := floorf(_t / 3.7)
	var gh := fposmod(sin(glance * 12.9898) * 43758.5453, 1.0)
	var off := Vector3(cos(gh * TAU), 0.0, sin(gh * TAU)) * 3.0
	var target := _eye_target + off + Vector3(sin(_t * 0.31) * 1.5, 0.0, cos(_t * 0.23) * 1.5)
	var local := _eye_root.transform.affine_inverse() * target
	var dir := local.normalized()
	dir = Vector3(dir.x * 0.35, dir.y * 0.12, 1.0).normalized()
	# hurt: the eye darts about
	dir.x += sin(_t * 23.0) * 0.12 * minf(_hurt, 1.0)
	_eye_ball.basis = _basis_look(dir.normalized())
	# blink: every ~5.3 s, 0.28 s long; the lids close over the ball. Open, they hood it (a narrowed, watching eye).
	var bt := fposmod(_t + 1.1, 5.3)
	var shut := sin(bt / 0.28 * PI) if bt < 0.28 else 0.0
	shut = maxf(shut, closing)
	_lid_top.basis = Basis(Vector3(1, 0, 0), lerpf(1.0 - 0.3 * minf(_hurt, 1.0), PI * 0.5, shut))
	_lid_bot.basis = Basis(Vector3(1, 0, 0), lerpf(-0.8, -PI * 0.5, shut))

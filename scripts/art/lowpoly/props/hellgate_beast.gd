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
## machine). It WATCHES its gate (watch()): when the gate dies (closed on the host, Net.remote_die on a client, the
## late-join snapshot's gone ids on a joiner) it sinks back into the dark over SINK_TIME and hides. A gate already dead or
## gone on the beast's FIRST frame (a late joiner applies the snapshot while the world is frozen, before the floor starts)
## means it is gone at once: a joiner never sees a closed gate's beast.
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
const SINK_TIME := 2.6                         ## seconds the beast takes to sink away once its gate closed
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

var _t := 0.0
var _frozen := false
var _close := 0.0
var _gate: Node = null                  ## the Hellgate it belongs to (watch())
var _watching := false
var _seen_frame := false                ## the first animated frame happened
var _sinking := false
var _gone := false
var _rng := RandomNumberGenerator.new()
var _flesh: ShaderMaterial              ## the flesh material: tentacles and every still piece
var _map: HexMap
var _cells: Array[Vector2i] = []
var _gate_pos := Vector3.ZERO
var _avoid: Array[Vector2] = []
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
## position. avoid: world X/Z of things standing against the walls (priced props, decor) that pieces keep off.
static func make(style_id: String, map: HexMap, room_cells: Array[Vector2i], gate_pos: Vector3, is_origin: bool,
		seed_value: int, avoid: Array[Vector2] = []) -> HellgateBeast:
	var b := HellgateBeast.new()
	b.style = style_id
	b.origin = is_origin
	b.beat_rate = 1.7 if is_origin else 2.6
	b.gate_cell = Hex.from_world(gate_pos)
	b._map = map
	b._cells = room_cells
	b._gate_pos = gate_pos
	b._avoid = avoid
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
	var avoid: Array[Vector2] = []
	for pr in plan.props:
		if pr.has("pos"):
			avoid.append(pr["pos"])
	for d in plan.decor:
		avoid.append(d["pos"])
	var seed_value := hash(Vector3i(cell.x, cell.y, floor_seed))
	var b := make("abyss", map, cells, gate.global_position, is_origin, seed_value, avoid)
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


## 0 = out, 1 = sunk back into the dark (labs; the game's beast sinks by itself when its gate closes).
func set_close(k: float) -> void:
	_close = clampf(k, 0.0, 1.0)


## "out", "sinking" or "gone" (tests and labs).
func state() -> String:
	if _gone:
		return "gone"
	return "sinking" if _sinking else "out"


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
	BeastFlesh.set_both(_flesh, "beat_rate", beat_rate)
	BeastFlesh.set_both(_flesh, "fade_lo", CLIFF_Y - 4.2)
	BeastFlesh.set_both(_flesh, "fade_hi", CLIFF_Y - 0.9)
	_rim = rim(_map, _cells)
	_make_runs()
	match style:
		"abyss":
			BeastFlesh.set_both(_flesh, "sway_rate", 0.45)
			BeastFlesh.set_both(_flesh, "wave_k", 0.35)
			_build_abyss()
		"peek":
			BeastFlesh.set_both(_flesh, "sway_rate", 0.35)
			BeastFlesh.set_both(_flesh, "wave_k", 0.3)
			_build_peek()
	if _static.tri_count() > 0:
		_add_mesh("Flesh", _static.to_mesh(0.0), Transform3D.IDENTITY)
	_animate()
	stats = {"tris": _tris, "meshes": _count_meshes(self), "nodes": _count_nodes(self), "limbs": _limbs, "rim_edges": _rim.size()}


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
				fwd = total * 0.8
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


## One long tentacle from a picked start: out from under the slab, along `along` of the run, tip over the wall.
## r_base: its girth where it comes out; lift: how high the tip rears (1 = about a wall height).
func _wrap(start: Dictionary, along: float, r_base: float, lift: float, opts: Dictionary = {}) -> MeshInstance3D:
	var run: Dictionary = _runs[int(start["run"])]
	var pts: Array[Vector3] = run["pts"]
	var nrms: Array[Vector3] = run["nrms"]
	var n_pts := pts.size()
	var closed: bool = run["closed"]
	var dir: int = start["dir"]
	var idx: Array[int] = [int(start["i"])]
	var dist := 0.0
	var j: int = start["i"]
	while dist < along:
		var nj := j + dir
		if closed:
			nj = posmod(nj, n_pts - 1)
		elif nj < 0 or nj >= n_pts:
			break
		dist += pts[nj].distance_to(pts[j])
		idx.append(nj)
		j = nj
	if idx.size() < 3:
		return null
	for i in idx:
		_taken.append(pts[i])
	var i0 := idx[0]
	var n0 := nrms[i0]
	var t0 := (pts[idx[1]] - pts[i0]).normalized()
	var top0 := pts[i0].y
	var face := _back(n0) < 0.62          # the camera sees this stretch's cliff face: climb it; else lie on the top
	var ctrl: Array[Vector3] = []
	var rad: Array[float] = []
	var sw: Array[float] = []
	var grip := 0.03                      # sway where it grips (it breathes, it does not flap)
	# It lives under the level: the root runs in the dark under the floor slab, presses along its underside and wraps
	# round the slab's bottom edge (the game camera sees it come out from under the cliff), then climbs.
	var r := r_base
	var under := Vector3(0, CLIFF_Y - top0, 0)
	ctrl.append(pts[i0] - n0 * 5.2 - t0 * 1.2 + under + Vector3(0, -2.2, 0))
	ctrl.append(pts[i0] - n0 * 2.6 - t0 * 0.5 + under + Vector3(0, -r - 0.08, 0))
	ctrl.append(pts[i0] - n0 * 0.45 + under + Vector3(0, -r * 0.95, 0))
	ctrl.append(pts[i0] + n0 * (r * 1.05) + under + Vector3(0, -r * 0.15, 0))
	rad.append_array([r * 1.1, r * 1.05, r, r * 0.98])
	sw.append_array([0.0, 0.0, 0.0, grip])
	if not face:
		# behind the room: up the back of the wall and over its outer edge
		ctrl.append(pts[i0] + n0 * (r + 0.08) + Vector3(0, -0.7, 0))
		ctrl.append(pts[i0] + n0 * (r * 0.4) + Vector3(0, r * 0.55, 0))
		rad.append_array([r * 0.96, r * 0.94])
		sw.append_array([grip, grip])
	var m := idx.size()
	for k in range(1, m):
		var f := float(k) / float(m - 1)
		var p := pts[idx[k]]
		var n := nrms[idx[k]]
		var rk := lerpf(r_base * 0.92, r_base * 0.5, f)
		if face:
			var y := lerpf(CLIFF_Y + rk * 0.9, p.y - rk * 0.55, smoothstep(0.0, 1.0, f))
			y += 0.32 * sin(f * PI * 3.0 + float(start["i"])) * (1.0 - f) * f * 3.0
			ctrl.append(p + n * (rk + 0.05) + Vector3(0, y - p.y, 0))
		else:
			ctrl.append(p - n * 0.62 + Vector3(0, rk * 0.8, 0))
		rad.append(rk)
		sw.append(grip)
	# over the top, rear up and hook back (never past the wall band into the room)
	var je := idx[m - 1]
	var pe := pts[je]
	var ne := nrms[je]
	var te := (pts[je] - pts[idx[m - 2]]).normalized()
	var re := r_base * 0.45
	var up := Vector3.UP * lift
	if face:
		ctrl.append(pe + ne * 0.05 + te * 0.4 + Vector3(0, re * 0.9, 0))
	ctrl.append(pe - ne * 0.8 + te * 0.6 + Vector3(0, re * 0.9 + 0.06, 0))
	ctrl.append(pe - ne * 1.35 + te * 0.9 + up * 0.9)
	ctrl.append(pe - ne * 1.25 + te * 1.2 + up * 1.8)
	ctrl.append(pe - ne * 0.65 + te * 1.3 + up * 2.15)
	ctrl.append(pe - ne * 0.25 + te * 1.0 + up * 1.85)
	var n_tip := ctrl.size() - rad.size()
	for k in n_tip:
		var f := float(k + 1) / float(n_tip)
		rad.append(lerpf(re, 0.035, f))
		sw.append(lerpf(0.05, 0.3 * lift, f))
	var sm := BeastFlesh.smooth_path(ctrl, rad, sw, 0.36 if r_base > 0.4 else 0.3)
	var mesh := BeastFlesh.path_tube(sm[0], sm[1], sm[2], _rng.randi(), int(opts.get("sides", 7)),
			float(opts.get("suckers", 0.6)), float(opts.get("spines", 0.0)), _rng.randf() * TAU)
	_limbs += 1
	if focus == Vector3.ZERO:
		focus = pts[i0] + Vector3(0, CLIFF_Y - top0, 0)
	return _add_mesh("Tentacle%d" % _limbs, mesh, Transform3D.IDENTITY)


## Score for picking wrap starts: the sides first (their climb out from under the slab reads best), then behind.
static func _wrap_score(e: Dictionary) -> float:
	var b: float = e["back"]
	return 0.6 + 0.8 * (1.0 - absf(b - 0.5) * 2.0) + 0.3 * b


# ------------------------------------------------------------------ A. abyss

func _build_abyss() -> void:
	var count := 7 if origin else 5
	var k := 1.3 if origin else 1.0
	for st in _pick_wraps(count, 4.0, 4.5, _wrap_score):
		var along := minf(float(st["ahead"]) - 0.6, _rng.randf_range(6.0, 9.5) * k)
		var lift := lerpf(0.6, 1.25, float(st["back"])) * _rng.randf_range(0.9, 1.1)
		_wrap(st, along, _rng.randf_range(0.8, 1.0) * k, lift, {"sides": 8, "suckers": 0.5, "spines": 1.4})


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
	var mi := _add_mesh(node_name, lb.to_mesh(0.0), Transform3D.IDENTITY)
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
	_add_mesh("Jaw", s.to_mesh(0.0), Transform3D.IDENTITY)


# ------------------------------------------------------------------ animation

func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if _frozen or _gone:
		return
	var live := gate_model != null and is_instance_valid(gate_model)
	if _watching:
		var dead := not is_instance_valid(_gate) or bool(_gate.get("dead"))
		if dead and not _sinking:
			if not _seen_frame:
				_vanish()      # dead before the floor even started (a late joiner): never shown
				return
			_sinking = true
		live = live and not dead
	_t = gate_model._t if live else _t + delta
	_seen_frame = true
	if _sinking:
		_close = minf(1.0, _close + delta / SINK_TIME)
		if _close >= 1.0:
			_vanish()
			return
	_animate()


func _vanish() -> void:
	_gone = true
	_sinking = true
	_close = 1.0
	visible = false
	set_process(false)


func _animate() -> void:
	BeastFlesh.set_both(_flesh, "t", _t)
	BeastFlesh.set_both(_flesh, "sink", _close * _close)
	_flesh.set_shader_parameter("glow_gain", 1.9 * (1.0 - _close))
	if _eye_ball != null:
		_animate_eye()


func _animate_eye() -> void:
	# it looks out at the camera's side of the room; the gaze drifts and glances towards the gate area
	var glance := floorf(_t / 3.7)
	var gh := fposmod(sin(glance * 12.9898) * 43758.5453, 1.0)
	var off := Vector3(cos(gh * TAU), 0.0, sin(gh * TAU)) * 3.0
	var target := _eye_target + off + Vector3(sin(_t * 0.31) * 1.5, 0.0, cos(_t * 0.23) * 1.5)
	var local := _eye_root.transform.affine_inverse() * target
	var dir := local.normalized()
	dir = Vector3(dir.x * 0.35, dir.y * 0.12, 1.0).normalized()
	_eye_ball.basis = _basis_look(dir)
	# blink: every ~5.3 s, 0.28 s long; the lids close over the ball. Open, they hood it (a narrowed, watching eye).
	var bt := fposmod(_t + 1.1, 5.3)
	var shut := sin(bt / 0.28 * PI) if bt < 0.28 else 0.0
	shut = maxf(shut, _close)
	_lid_top.basis = Basis(Vector3(1, 0, 0), lerpf(1.0, PI * 0.5, shut))
	_lid_bot.basis = Basis(Vector3(1, 0, 0), lerpf(-0.8, -PI * 0.5, shut))

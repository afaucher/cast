class_name GatorModel
extends Node3D
## The sewer gator's model (docs/design/gator-look.md; the user chose V3 "Mugger", 2026-10-20): an old armoured bruiser,
## dark mossy hide under rows of pale knobs, a jagged brow hood over hot ember eyes, algae patches and a scar across the
## snout. Drawn by Gator (scripts/monsters/gator.gd) at Gator.GATOR_SCALE 1.3; the lab (gator_look_lab, GatorLooks) builds
## the other looks from the same code with another spec.
##
##   var m := GatorModel.new()            # the game's look; GatorModel.new(GatorLooks.spec("v1")) for a lab look
##   m.wave = 30.0; m.phase = 0.25; m.swim_k = 1.0
##   m.apply()                             # pose the parts
##
## A RIGID-PART RIG (the shark's way, SharkModels.pose): every part is its own MeshInstance3D with a mesh built once per
## spec (cached per process), posed every frame from a handful of numbers; no skinning, no per-frame mesh building:
##   chest, hips, tail1, tail2, tail3   the body, cut along the spine (each segment's origin on its front joint on the
##                                       floor plane, running back along -Z; each one reaches a little past its joints and
##                                       the one behind starts a little thinner, so a bend never opens a gap or z-fights)
##   head, jaw                          the skull and the lower jaw (the jaw hinged at the back of the skull)
##   upper_<leg>, lower_<leg>, paw_<leg> each leg (fr, fl, hr, hl: front / hind, right / left): the upper arm from the
##                                       shoulder, the forearm from the elbow, the paw flat on the floor
## The material is one ShaderMaterial for every part (`material`: MonsterMaterial, so Gator drives the eye glow, the wind-up
## pulse and the hit flash on it).
##
## THE POSE (all in the model's lab units: snout tip at z 1.0, tail tip at z -1.3, 2.3 long; +X its right):
##   bend         degrees the body curls over its length (Gator: from its turning)
##   wave, phase  the S-wave: degrees of heading swing at the tail tip, travelling back from the neck (phase 0..1)
##   gait, walk_k the walk cycle (0..1) and how much of it shows (0 at rest .. 1 walking): the high walk (the belly 0.1
##                up), legs in diagonal pairs, the trunk bowing and the tail swinging a beat late
##   swim_k       0 on land .. 1 swimming: the legs folded back along the flanks, the head and neck raised so the nostrils,
##                the eyes and the back break the surface
##   head_yaw     degrees the head turns toward +X (tracking), head_pitch degrees nose up
##   jaw          0..1 open (most of a gape is the skull lifting, so the chin stays off the floor)
##   breath       0..1 the chest swells

const NECK_Z := 0.55            ## the neck joint: the head runs +Z from it to the snout tip
const TAIL_Z := -1.3
const BODY_LEN := NECK_Z - TAIL_Z
const SEGMENTS := [["chest", 0.0, 0.24], ["hips", 0.24, 0.46], ["tail1", 0.46, 0.64], ["tail2", 0.64, 0.82], ["tail3", 0.82, 1.0]]
const OVERLAP := 0.035          ## (u) how far a segment reaches past its joints
const LEGS: Array[String] = ["fr", "fl", "hr", "hl"]
const N_SPINE := 24
const TOOTH := Color(0.97, 0.95, 0.86)
const MOUTH := Color(0.6, 0.2, 0.22)
const TONGUE := Color(0.84, 0.46, 0.44)
const VOID := Color(0.06, 0.05, 0.04)
const BRASS := Color(0.86, 0.68, 0.3)
const MOSS := Color(0.4, 0.46, 0.16)

var spec: Dictionary
var parts: Dictionary = {}                  ## part name -> MeshInstance3D
var material: ShaderMaterial
var bend := 0.0
var wave := 0.0
var phase := 0.0
var gait := 0.0
var walk_k := 0.0
var swim_k := 0.0
var head_yaw := 0.0
var head_pitch := 0.0
var jaw := 0.0
var breath := 0.0
var _rest_len: Dictionary = {}              ## leg -> Vector2(upper, lower) at rest

static var _cache: Dictionary = {}          ## "<spec id>|<part>" -> ArrayMesh
static var _seed := 1


## The game's look: V3 "Mugger" as chosen (moss and the scar, no property tag; the ember eyes made bigger so they read
## at size 24 from the water).
static func game_spec() -> Dictionary:
	return {
		"id": "game", "skin": Color(0.2, 0.25, 0.17), "flank": Color(0.4, 0.4, 0.27), "belly": Color(0.76, 0.7, 0.5),
		"dark": Color(0.47, 0.48, 0.38), "eye": Color(1.0, 0.42, 0.1), "claw": Color(0.86, 0.8, 0.62), "vary": 0.08,
		"prof": [Vector2(0, 1), Vector2(0.55, 0.98), Vector2(1.0, 0.5), Vector2(0.88, 0.1), Vector2(0.45, 0.0), Vector2(0, 0)],
		"body": [Vector4(0.0, 0.19, 0.08, 0.28), Vector4(0.07, 0.25, 0.03, 0.32), Vector4(0.17, 0.32, 0.01, 0.34),
			Vector4(0.28, 0.33, 0.0, 0.35), Vector4(0.38, 0.29, 0.02, 0.34), Vector4(0.47, 0.19, 0.05, 0.3),
			Vector4(0.58, 0.14, 0.07, 0.27), Vector4(0.7, 0.1, 0.09, 0.23), Vector4(0.82, 0.07, 0.1, 0.2),
			Vector4(0.92, 0.045, 0.11, 0.17), Vector4(1.0, 0.015, 0.12, 0.14)],
		"head": [Vector4(-0.12, 0.19, 0.1, 0.28), Vector4(-0.02, 0.27, 0.1, 0.31), Vector4(0.09, 0.23, 0.11, 0.27),
			Vector4(0.22, 0.17, 0.115, 0.22), Vector4(0.36, 0.15, 0.115, 0.2), Vector4(0.43, 0.135, 0.12, 0.2),
			Vector4(0.47, 0.08, 0.13, 0.18)],
		"jaw": [Vector4(-0.13, 0.18, 0.04, 0.115), Vector4(-0.02, 0.24, 0.025, 0.115), Vector4(0.2, 0.16, 0.05, 0.115),
			Vector4(0.38, 0.13, 0.06, 0.115), Vector4(0.46, 0.08, 0.075, 0.115)],
		"head_prof": [Vector2(0, 1), Vector2(0.6, 0.97), Vector2(1.0, 0.5), Vector2(0.9, 0.05), Vector2(0, 0)],
		"hinge": Vector2(-0.1, 0.115), "jaw_max": 32.0,
		"front_u": 0.08, "hind_u": 0.37, "r_front": 0.07, "r_hind": 0.085, "toes": 3, "toe_len": 0.085, "reach": 0.32,
		"eyes": "hood", "eye_size": 1.45, "scutes": "knobs", "nose": "lumps", "teeth": "ragged", "bands": true, "jit": 0.012,
		"extras": ["moss", "scar"], "sides": 5,
	}


func _init(p_spec: Dictionary = {}) -> void:
	spec = p_spec if not p_spec.is_empty() else game_spec()
	name = "GatorModel"
	material = MonsterMaterial.make(2.0)
	material.set_shader_parameter("glow_gain", 1.6)
	_build()
	apply()


## Set the pose from a dictionary (the lab's shots): the vars above by name, plus "swim" (bool: swim_k 1) and "gait"
## (-1 at rest, else the walk cycle with walk_k 1). Then apply().
func set_pose(p: Dictionary) -> void:
	bend = float(p.get("bend", 0.0))
	wave = float(p.get("wave", 0.0))
	phase = float(p.get("phase", 0.0))
	var g := float(p.get("gait", -1.0))
	swim_k = 1.0 if bool(p.get("swim", false)) else 0.0
	walk_k = 1.0 if g >= 0.0 and swim_k == 0.0 else 0.0
	gait = maxf(g, 0.0)
	head_yaw = float(p.get("head_yaw", 0.0))
	head_pitch = float(p.get("head_pitch", 0.0))
	jaw = clampf(float(p.get("jaw", 0.0)), 0.0, 1.0)
	breath = float(p.get("breath", 0.0))
	apply()


## Total triangles over every part (the budget: docs/design/gator-look.md).
func triangle_count() -> int:
	var t := 0
	for k in parts:
		var mesh := (parts[k] as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			t += (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


# --- building --------------------------------------------------------------------------------------------------------

func _build() -> void:
	# the legs' rest lengths come from the rest pose (the paws' and limbs' meshes are built to them)
	for li in LEGS.size():
		var lp := _leg_points(li, _spine(), _seg_xfs(_spine()))
		_rest_len[LEGS[li]] = Vector2(lp[0].distance_to(lp[1]), lp[1].distance_to(lp[2] + Vector3.UP * _leg_r(li) * 0.55))
	var names: Array[String] = []
	for seg: Array in SEGMENTS:
		names.append(str(seg[0]))
	names.append_array(["head", "jaw"])
	for leg in LEGS:
		names.append_array(["upper_" + leg, "lower_" + leg, "paw_" + leg])
	for part_name in names:
		var key := "%s|%s" % [str(spec.get("id", "game")), part_name]
		if not _cache.has(key):
			_seed = 1 + part_name.hash() % 997
			_cache[key] = _part_soup(part_name).to_mesh()
		var mi := MeshInstance3D.new()
		mi.name = part_name
		mi.mesh = _cache[key]
		mi.material_override = material
		add_child(mi)
		parts[part_name] = mi


func _part_soup(part_name: String) -> LowPoly.Soup:
	var s := LowPoly.Soup.new(17 + part_name.length(), float(spec["vary"]))
	for i in SEGMENTS.size():
		if str(SEGMENTS[i][0]) == part_name:
			_segment(s, i)
			return s
	match part_name:
		"head": _head(s)
		"jaw": _jaw(s)
		_:
			var leg := part_name.get_slice("_", 1)
			var li := LEGS.find(leg)
			match part_name.get_slice("_", 0):
				"upper": _upper(s, li)
				"lower": _lower(s, li)
				"paw": _paw(s, li)
	return s


static func _n() -> int:
	_seed += 1
	return _seed * 37 + 11


static func g(c: Color) -> Color:
	return MonsterModel.glow(c)


## A station list sampled at x (Vector4: x, half width, bottom y, top y).
static func st_at(list: Array, x: float) -> Vector4:
	if x <= (list[0] as Vector4).x:
		return list[0]
	for i in list.size() - 1:
		var a: Vector4 = list[i]
		var b: Vector4 = list[i + 1]
		if x <= b.x:
			return a.lerp(b, (x - a.x) / maxf(b.x - a.x, 0.0001))
	return list[list.size() - 1]


## The profile's height (0..1) at a fraction xf of the half width, on its upper half.
static func prof_y(prof: Array, xf: float) -> float:
	for k in prof.size() - 1:
		var a: Vector2 = prof[k]
		var b: Vector2 = prof[k + 1]
		if xf <= b.x:
			return lerpf(a.y, b.y, (xf - a.x) / maxf(b.x - a.x, 0.0001))
		if b.x < a.x:
			break
	return 0.5


## One ring of the section: the right half from the top centre down to the bottom centre, then the left half back up.
static func _ring(prof: Array, c: Vector3, side: Vector3, up: Vector3, w: float, yb: float, yt: float) -> PackedVector3Array:
	var r := PackedVector3Array()
	for k in prof.size():
		var q: Vector2 = prof[k]
		r.append(c + side * q.x * w + up * (yb + q.y * (yt - yb)))
	for k in range(prof.size() - 2, 0, -1):
		var q: Vector2 = prof[k]
		r.append(c - side * q.x * w + up * (yb + q.y * (yt - yb)))
	return r


static func _ring_h(prof: Array) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	for k in prof.size():
		h.append((prof[k] as Vector2).y)
	for k in range(prof.size() - 2, 0, -1):
		h.append((prof[k] as Vector2).y)
	return h


## Skin a list of rings (each segment its own little soup round its centre, so the faces wind outward), colouring each
## face by `mode` (body / head / jaw) from its station and its height in the section, capped at the ends asked for (a body
## segment's ends inside its neighbours stay open).
func _loft(s: LowPoly.Soup, rings: Array, centres: Array, us: PackedFloat32Array, hh: PackedFloat32Array, mode: String, cap_a: bool = true, cap_b: bool = true) -> void:
	var out := LowPoly.Soup.new(_n(), float(spec["vary"]))
	var m := (rings[0] as PackedVector3Array).size()
	for i in rings.size() - 1:
		var ra: PackedVector3Array = rings[i]
		var rb: PackedVector3Array = rings[i + 1]
		var c: Vector3 = ((centres[i] as Vector3) + (centres[i + 1] as Vector3)) * 0.5
		var seg := LowPoly.Soup.new(_n(), float(spec["vary"]))
		var um := (us[i] + us[i + 1]) * 0.5
		for k in m:
			var k2 := (k + 1) % m
			seg.add_quad(ra[k] - c, ra[k2] - c, rb[k2] - c, rb[k] - c, _col(mode, um, (hh[k] + hh[k2]) * 0.5))
		out.merge(seg, Transform3D(Basis.IDENTITY, c))
	var n := rings.size() - 1
	if cap_a:
		_cap(out, rings[0], centres[0], (centres[1] as Vector3) - (centres[0] as Vector3), _col(mode, us[0], 0.7))
	if cap_b:
		_cap(out, rings[n], centres[n], (centres[n - 1] as Vector3) - (centres[n] as Vector3), _col(mode, us[n], 0.7))
	if float(spec["jit"]) > 0.0:
		out.jitter(float(spec["jit"]), _n())
	s.merge(out)


func _cap(out: LowPoly.Soup, ring: PackedVector3Array, centre: Vector3, inward: Vector3, col: Color) -> void:
	var o := centre + inward.normalized() * 0.04
	var seg := LowPoly.Soup.new(_n(), float(spec["vary"]))
	for k in ring.size():
		seg.add_tri(centre - o, ring[k] - o, ring[(k + 1) % ring.size()] - o, col)
	out.merge(seg, Transform3D(Basis.IDENTITY, o))


## The colour blocking: a dark back, a pale lower flank, a cream belly; dark bands down the tail; the mouth inside.
func _col(mode: String, u: float, h: float) -> Color:
	var skin: Color = spec["skin"]
	var flank: Color = spec["flank"]
	var belly: Color = spec["belly"]
	match mode:
		"head":
			if h < 0.1:
				return MOUTH
			if h < 0.42:
				return flank.lerp(belly, 0.35)
			return skin.lightened(0.05) if h < 0.97 else skin
		"jaw":
			if h > 0.9:
				return MOUTH
			return belly.darkened(0.06) if h > 0.25 else belly.darkened(0.14)
	var col := skin
	if h < 0.25:
		col = belly
	elif h < 0.6:
		col = flank
	elif h > 0.97:
		col = skin.darkened(0.12)
	if bool(spec["bands"]) and u > 0.46 and h >= 0.25 and int((u - 0.46) / 0.07) % 2 == 1:
		col = col.darkened(0.42)
	return col


# --- the body segments -------------------------------------------------------------------------------------------------

## Segment i in its own frame: origin on its front joint (floor level), running back along -Z. It reaches OVERLAP past
## both joints; behind a joint it starts at 0.9 of its size and grows back to full at OVERLAP past it, so it stays inside
## the segment in front where they overlap.
func _segment(s: LowPoly.Soup, i: int) -> void:
	var u0 := float(SEGMENTS[i][1])
	var u1 := float(SEGMENTS[i][2])
	var a := u0 - (OVERLAP if i > 0 else 0.0)
	var b := u1 + (OVERLAP if i < SEGMENTS.size() - 1 else 0.0)
	var prof: Array = spec["prof"]
	var n := maxi(3, ceili((b - a) / 0.07))
	var rings := []
	var centres := []
	var us := PackedFloat32Array()
	for k in n + 1:
		var u := lerpf(a, b, float(k) / float(n))
		var st := st_at(spec["body"], u)
		var w := st.y
		var yb := st.z
		var yt := st.w
		if i > 0:
			var f := lerpf(0.9, 1.0, clampf((u - a) / (2.0 * OVERLAP), 0.0, 1.0))
			var mid := (yb + yt) * 0.5
			w *= f
			yb = mid + (yb - mid) * f
			yt = mid + (yt - mid) * f
		var c := Vector3(0.0, 0.0, -(u - u0) * BODY_LEN)
		rings.append(_ring(prof, c, Vector3.RIGHT, Vector3.UP, w, yb, yt))
		centres.append(c + Vector3.UP * (yb + yt) * 0.5)
		us.append(u)
	_loft(s, rings, centres, us, _ring_h(prof), "body", i == 0, i == SEGMENTS.size() - 1)
	_scutes(s, i)
	_extras(s, i)


## Where on the back (segment i's frame) a feature at u, `xf` of the half width out to side `sd` sits, rolled to the slope.
func _on_back(i: int, u: float, xf: float, sd: float) -> Transform3D:
	var st := st_at(spec["body"], u)
	var y := st.z + (st.w - st.z) * prof_y(spec["prof"], xf)
	var basis := Basis(Vector3.BACK, -sd * xf * 0.55)
	return Transform3D(basis, Vector3(sd * xf * st.y, y, -(u - float(SEGMENTS[i][1])) * BODY_LEN))


## Is u in segment i (features go to the segment that holds them)?
static func _holds(i: int, u: float) -> bool:
	return u >= float(SEGMENTS[i][1]) and (u < float(SEGMENTS[i][2]) or i == SEGMENTS.size() - 1)


func _frus_at(s: LowPoly.Soup, xf: Transform3D, bottom: Vector2, top: Vector2, h: float, col: Color, top_off: Vector2 = Vector2.ZERO, sink: float = 0.012) -> void:
	var piece := LowPoly.frustum(bottom, top, h, col, _n(), 0.0, 1, top_off, 0.05)
	s.merge(piece, Transform3D(xf.basis, xf.origin + xf.basis.y * (h * 0.5 - sink)))


func _ball_at(s: LowPoly.Soup, pos: Vector3, radii: Vector3, col: Color, basis: Basis = Basis.IDENTITY, detail: int = 0, jit: float = 0.1) -> void:
	s.merge(LowPoly.boulder(radii, detail, jit, col, _n(), 0.06), Transform3D(basis, pos))


func _scutes(s: LowPoly.Soup, i: int) -> void:
	var dark: Color = spec["dark"]
	match str(spec["scutes"]):
		"plates":
			for sd: float in [-1.0, 1.0]:
				if _holds(i, 0.035):
					_frus_at(s, _on_back(i, 0.035, 0.32, sd), Vector2(0.1, 0.1), Vector2(0.04, 0.05), 0.065, dark)
					_frus_at(s, _on_back(i, 0.035, 0.75, sd), Vector2(0.07, 0.08), Vector2(0.03, 0.04), 0.045, dark)
			for k in 8:
				var u := 0.1 + float(k) * 0.045
				for sd: float in [-1.0, 1.0]:
					if _holds(i, u):
						_frus_at(s, _on_back(i, u, 0.24, sd), Vector2(0.085, 0.075), Vector2(0.025, 0.045), 0.055, dark, Vector2(0, -0.01))
					if _holds(i, u + 0.02):
						_frus_at(s, _on_back(i, u + 0.02, 0.62, sd), Vector2(0.065, 0.06), Vector2(0.02, 0.035), 0.04, dark)
			_tail_crest(s, i, 0.09, 1.0)
		"domes":
			for k in 9:
				var u := 0.06 + float(k) * 0.045
				if not _holds(i, u):
					continue
				for sd: float in [-1.0, 1.0]:
					var xf := _on_back(i, u, 0.3, sd)
					_ball_at(s, xf.origin, Vector3(0.05, 0.03, 0.055), dark.lightened(0.08), xf.basis)
			for k in 10:
				var u := 0.47 + float(k) * 0.052
				if not _holds(i, u):
					continue
				var xf := _on_back(i, u, 0.0, 1.0)
				var kk := 1.0 - float(k) / 11.0
				_ball_at(s, xf.origin, Vector3(0.025, 0.05 * kk + 0.015, 0.045), dark, xf.basis)
		"knobs":
			# big rough osteoderms in rows, pale against the dark hide, and a tall jagged crest
			if _holds(i, 0.03):
				for sd: float in [-1.0, 1.0]:
					for xfr: float in [0.25, 0.7]:
						var xf := _on_back(i, 0.03, xfr, sd)
						_ball_at(s, xf.origin + xf.basis.y * 0.03, Vector3(0.06, 0.06, 0.06), dark, xf.basis, 0, 0.3)
			for k in 9:
				var u := 0.09 + float(k) * 0.042
				for sd: float in [-1.0, 1.0]:
					if _holds(i, u):
						_frus_at(s, _on_back(i, u, 0.22, sd), Vector2(0.08, 0.08), Vector2(0.015, 0.02), 0.08 + 0.02 * float(k % 2), dark, Vector2(0, -0.015))
					if k % 2 == 0 and _holds(i, u + 0.02):
						_frus_at(s, _on_back(i, u + 0.02, 0.6, sd), Vector2(0.06, 0.06), Vector2(0.01, 0.015), 0.06, dark.darkened(0.15))
			_tail_crest(s, i, 0.12, 1.3)


## The tail's double crest (two rows of upright keels from the hips) running into a single row near the tip.
func _tail_crest(s: LowPoly.Soup, i: int, h0: float, k: float) -> void:
	var dark: Color = spec["dark"]
	for j in 7:
		var u := 0.45 + float(j) * 0.045
		if not _holds(i, u):
			continue
		var h := lerpf(h0, h0 * 0.6, float(j) / 6.0)
		for sd: float in [-1.0, 1.0]:
			var xf := _on_back(i, u, 0.42, sd)
			xf.basis = Basis(Vector3.BACK, sd * 0.12) * xf.basis
			_frus_at(s, xf, Vector2(0.035, 0.1) * k, Vector2(0.01, 0.025) * k, h, dark, Vector2(0, -0.03))
	for j in 7:
		var u := 0.77 + float(j) * 0.035
		if not _holds(i, u):
			continue
		var h := lerpf(h0 * 0.65, h0 * 0.3, float(j) / 6.0)
		_frus_at(s, _on_back(i, u, 0.0, 1.0), Vector2(0.035, 0.08) * k, Vector2(0.01, 0.02) * k, h, dark, Vector2(0, -0.025))


func _extras(s: LowPoly.Soup, i: int) -> void:
	var ex: Array = spec["extras"]
	if ex.has("spots"):
		for e: Array in [[0.14, 0.62, 1.0], [0.21, 0.45, -1.0], [0.3, 0.7, -1.0], [0.33, 0.5, 1.0], [0.52, 0.5, 1.0], [0.6, 0.55, -1.0], [0.7, 0.4, 1.0]]:
			if _holds(i, float(e[0])):
				var xf := _on_back(i, float(e[0]), float(e[1]), float(e[2]))
				_ball_at(s, xf.origin - xf.basis.y * 0.006, Vector3(0.06, 0.012, 0.075), (spec["dark"] as Color).darkened(0.1), xf.basis)
	if ex.has("moss"):
		# algae on the back and the tail: flat yellow-green patches
		for e: Array in [[0.12, 0.45, 1.0], [0.2, 0.8, -1.0], [0.26, 0.4, -1.0], [0.36, 0.75, 1.0], [0.55, 0.3, -1.0], [0.66, 0.5, 1.0]]:
			if _holds(i, float(e[0])):
				var xf := _on_back(i, float(e[0]), float(e[1]), float(e[2]))
				_ball_at(s, xf.origin, Vector3(0.075, 0.014, 0.09), MOSS, xf.basis, 0, 0.25)
	if ex.has("tag") and _holds(i, 0.5):
		# a property tag clipped through the base of the tail (the look-dev's V3; the game's gator has none)
		var xf := _on_back(i, 0.5, 0.95, -1.0)
		var o := xf.origin + Vector3.LEFT * 0.02
		PropModels.rod(s, o + Vector3.UP * 0.02, o - Vector3.UP * 0.05, 0.016, 0.016, 5, BRASS)
		var tb := Basis(Vector3.BACK, -0.25) * xf.basis
		s.merge(LowPoly.box(Vector3(0.012, 0.09, 0.13), Color(0.98, 0.8, 0.14), _n(), 0.0, 1, 0.02), Transform3D(tb, o + Vector3.LEFT * 0.02 - Vector3.UP * 0.08))


# --- the head ----------------------------------------------------------------------------------------------------------

func _head_top(z: float, xf: float) -> float:
	var st := st_at(spec["head"], z)
	return st.z + (st.w - st.z) * prof_y(spec["head_prof"], xf)


func _head_loft(s: LowPoly.Soup, list: Array, off: Vector3, mode: String) -> void:
	var hp: Array = spec["head_prof"]
	var rings := []
	var centres := []
	var us := PackedFloat32Array()
	for st: Vector4 in list:
		var c := Vector3(0, 0, st.x) - off
		rings.append(_ring(hp, c, Vector3.RIGHT, Vector3.UP, st.y, st.z, st.w))
		centres.append(c + Vector3.UP * (st.z + st.w) * 0.5)
		us.append(st.x)
	_loft(s, rings, centres, us, _ring_h(hp), mode)


## The skull and snout in the head's frame (origin the neck joint on the floor plane, +Z the snout): eyes, nostrils, the
## upper teeth, moss and the scar.
func _head(s: LowPoly.Soup) -> void:
	_head_loft(s, spec["head"], Vector3.ZERO, "head")
	_upper_teeth(s)
	_eyes(s)
	_nose(s)
	var ex: Array = spec["extras"]
	if ex.has("moss"):
		_ball_at(s, Vector3(-0.06, _head_top(0.18, 0.3), 0.18), Vector3(0.06, 0.012, 0.07), MOSS, Basis.IDENTITY, 0, 0.25)
	if ex.has("scar"):
		var a := Vector3(-0.2, _head_top(0.05, 0.8) + 0.008, 0.02)
		var b := Vector3(0.05, _head_top(0.25, 0.2) + 0.008, 0.25)
		PropModels.rod(s, a, b, 0.014, 0.014, 4, Color(0.78, 0.68, 0.58))


## The lower jaw in its own frame: the origin on the hinge (the head's `hinge`), +Z the chin. The tongue lies in it.
func _jaw(s: LowPoly.Soup) -> void:
	var hv := _hinge()
	_head_loft(s, spec["jaw"], hv, "jaw")
	_ball_at(s, Vector3(0, 0.115, 0.12) - hv, Vector3(0.11, 0.025, 0.2), TONGUE)
	_lower_teeth(s, hv)


func _hinge() -> Vector3:
	var h: Vector2 = spec["hinge"]
	return Vector3(0, h.y, h.x)


func _upper_teeth(s: LowPoly.Soup) -> void:
	var style := str(spec["teeth"])
	if style == "toon":
		for sd: float in [-1.0, 1.0]:
			for i in 4:
				var z := 0.4 - float(i) * 0.09
				var st := st_at(spec["head"], z)
				s.merge(LowPoly.box(Vector3(0.045, 0.05, 0.05), TOOTH, _n(), 0.0, 1, 0.03), Transform3D(Basis.IDENTITY, Vector3(sd * st.y * 0.86, st.z - 0.017, z)))
		return
	var n := 7 if style == "rows" else 6
	for sd: float in [-1.0, 1.0]:
		for i in n:
			var z := 0.42 - float(i) * 0.06
			var st := st_at(spec["head"], z)
			var big := i == 1 or i == 4
			var length := 0.055 if big else 0.038
			if style == "ragged" and sd > 0.0 and i == 3:
				length = 0.015   # a broken one
			PropModels.rod(s, Vector3(sd * st.y * 0.93, st.z + 0.01, z), Vector3(sd * st.y * 0.96, st.z - length, z + 0.006), 0.02 if big else 0.016, 0.003, 3, TOOTH)


func _lower_teeth(s: LowPoly.Soup, hv: Vector3) -> void:
	if str(spec["teeth"]) == "toon":
		for sd: float in [-1.0, 1.0]:
			var jst := st_at(spec["jaw"], 0.3)
			PropModels.rod(s, Vector3(sd * (jst.y + 0.012), jst.w - 0.01, 0.3) - hv, Vector3(sd * (jst.y + 0.03), jst.w + 0.08, 0.31) - hv, 0.03, 0.006, 5, TOOTH)
		return
	var n := 7 if str(spec["teeth"]) == "rows" else 6
	for sd: float in [-1.0, 1.0]:
		for i in n - 1:
			var z := 0.39 - float(i) * 0.06
			var jst := st_at(spec["jaw"], z)
			var length := 0.075 if i == 1 else 0.04       # the fourth tooth stands up outside the upper jaw
			var xo := 1.22 if i == 1 else 0.9
			PropModels.rod(s, Vector3(sd * jst.y * xo, jst.w - 0.01, z) - hv, Vector3(sd * jst.y * xo, jst.w + length, z - 0.004) - hv, 0.022 if i == 1 else 0.017, 0.003, 3, TOOTH)


func _eyes(s: LowPoly.Soup) -> void:
	var skin: Color = spec["skin"]
	var dark: Color = spec["dark"]
	var eye: Color = spec["eye"]
	var k := float(spec.get("eye_size", 1.0))
	for sd: float in [-1.0, 1.0]:
		match str(spec["eyes"]):
			"turret":
				# a raised turret at the back of the skull, a brow wedge over it, a big glowing slit eye facing out and up
				var at := Vector3(sd * 0.135, _head_top(0.0, 0.55), 0.0)
				s.merge(LowPoly.frustum(Vector2(0.14, 0.15), Vector2(0.1, 0.1), 0.065, skin, _n(), 0.0, 1, Vector2(sd * 0.01, 0.0), 0.05), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.025, 0)))
				var eb := Basis.from_euler(Vector3(0, sd * 0.4, -sd * 0.8))
				s.merge(LowPoly.box(Vector3(0.025, 0.065, 0.095) * k, g(eye), _n(), 0.0, 1, 0.0), Transform3D(eb, at + Vector3(sd * 0.052, 0.05, 0.012)))
				s.merge(LowPoly.box(Vector3(0.028, 0.06, 0.016) * k, VOID, _n(), 0.0, 1, 0.0), Transform3D(eb, at + Vector3(sd * 0.054, 0.051, 0.016)))
				var bb := Basis.from_euler(Vector3(0.15, sd * 0.25, sd * 0.45))
				s.merge(LowPoly.frustum(Vector2(0.11, 0.1), Vector2(0.06, 0.08), 0.03, skin.darkened(0.3), _n(), 0.0, 1, Vector2(sd * 0.02, 0.0), 0.04), Transform3D(bb, at + Vector3(sd * 0.03, 0.075, 0.03)))
			"dome":
				# big round eyeballs, a wide glowing iris looking out and forward, a slit pupil, a heavy lid half down
				var at := Vector3(sd * 0.14, _head_top(-0.02, 0.5) + 0.055, -0.02)
				_ball_at(s, at, Vector3(0.11, 0.1, 0.11), skin.lightened(0.06), Basis.IDENTITY, 1, 0.04)
				var dir := Vector3(sd * 0.75, 0.45, 0.5).normalized()
				var b := Basis(Quaternion(Vector3.UP, dir))
				s.merge(LowPoly.cylinder(0.08 * k, 0.08 * k, 0.03, 8, g(eye), _n(), 0.0, 1, 0.0), Transform3D(b, at + dir * 0.092))
				s.merge(LowPoly.box(Vector3(0.024, 0.034, 0.11) * k, VOID, _n(), 0.0, 1, 0.0), Transform3D(b, at + dir * 0.11))
				var lid := Basis.from_euler(Vector3(-0.35, 0.0, -sd * 0.35))
				_ball_at(s, at + Vector3(sd * 0.005, 0.05, -0.01), Vector3(0.118, 0.065, 0.116), dark, lid, 1, 0.04)
			"hood":
				# a low socket under a jagged hood of brow, a hot ember eye with a slit pupil in its shadow (set out and up
				# so the game camera sees it over the water)
				var at := Vector3(sd * 0.15, _head_top(0.0, 0.6), 0.01)
				s.merge(LowPoly.frustum(Vector2(0.13, 0.14), Vector2(0.09, 0.1), 0.055, skin, _n(), 0.0, 1, Vector2.ZERO, 0.06), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.022, 0)))
				var eb := Basis.from_euler(Vector3(0, sd * 0.45, -sd * 0.7))
				s.merge(LowPoly.box(Vector3(0.024, 0.05, 0.09) * k, g(eye), _n(), 0.0, 1, 0.0), Transform3D(eb, at + Vector3(sd * 0.052, 0.052, 0.022)))
				s.merge(LowPoly.box(Vector3(0.027, 0.045 * k, 0.014), VOID, _n(), 0.0, 1, 0.0), Transform3D(eb, at + Vector3(sd * 0.054, 0.053, 0.026)))
				for j in 3:
					var hb := Basis.from_euler(Vector3(0.35, sd * (0.1 + 0.25 * float(j)), sd * 0.35))
					s.merge(LowPoly.frustum(Vector2(0.05, 0.06), Vector2(0.01, 0.015), 0.07, dark, _n(), 0.0, 1, Vector2(sd * 0.02, -0.02), 0.06),
						Transform3D(hb, at + Vector3(sd * 0.03 * float(j), 0.085, 0.04 - 0.05 * float(j))))


func _nose(s: LowPoly.Soup) -> void:
	var skin: Color = spec["skin"]
	var top := _head_top(0.41, 0.0)
	match str(spec["nose"]):
		"boss":
			s.merge(LowPoly.frustum(Vector2(0.12, 0.09), Vector2(0.085, 0.06), 0.045, skin.lightened(0.04), _n(), 0.0, 1, Vector2.ZERO, 0.04), Transform3D(Basis.IDENTITY, Vector3(0, top + 0.015, 0.41)))
		"ball":
			_ball_at(s, Vector3(0, top + 0.01, 0.405), Vector3(0.075, 0.045, 0.06), skin.lightened(0.04), Basis.IDENTITY, 1, 0.05)
		"lumps":
			_ball_at(s, Vector3(0, top + 0.012, 0.41), Vector3(0.07, 0.045, 0.06), skin.lightened(0.06), Basis.IDENTITY, 0, 0.3)
	for sd: float in [-1.0, 1.0]:
		s.merge(LowPoly.box(Vector3(0.025, 0.02, 0.03), VOID, _n(), 0.0, 1, 0.0), Transform3D(Basis(Vector3.UP, sd * 0.4), Vector3(sd * 0.025, top + 0.045, 0.42)))


# --- the legs ----------------------------------------------------------------------------------------------------------

func _leg_r(li: int) -> float:
	return float(spec["r_hind"]) if li >= 2 else float(spec["r_front"])


## The upper arm: a rod hanging down -Y from the shoulder, its rest length long.
func _upper(s: LowPoly.Soup, li: int) -> void:
	var r := _leg_r(li)
	PropModels.rod(s, Vector3.ZERO, Vector3.DOWN * float((_rest_len[LEGS[li]] as Vector2).x), r * 1.05, r * 0.9, 5, spec["skin"])


## The forearm: the elbow knob and a rod down -Y to the ankle.
func _lower(s: LowPoly.Soup, li: int) -> void:
	var r := _leg_r(li)
	_ball_at(s, Vector3.ZERO, Vector3.ONE * r * 0.95, spec["skin"], Basis.IDENTITY, 0, 0.08)
	PropModels.rod(s, Vector3.ZERO, Vector3.DOWN * float((_rest_len[LEGS[li]] as Vector2).y), r * 0.9, r * 0.75, 5, (spec["flank"] as Color).lerp(spec["skin"], 0.5))


## The paw at its origin, flat on the floor, the toes toward +Z: a splayed foot and chunky toes with pale claws.
func _paw(s: LowPoly.Soup, li: int) -> void:
	var r := _leg_r(li)
	s.merge(LowPoly.frustum(Vector2(r * 2.3, r * 2.1), Vector2(r * 1.5, r * 1.3), r * 0.7, spec["skin"], _n(), 0.0, 1, Vector2.ZERO, 0.05), Transform3D(Basis.IDENTITY, Vector3.UP * r * 0.35))
	var toes := int(spec["toes"])
	var tl := float(spec["toe_len"]) * (1.15 if li >= 2 else 1.0)
	for t in toes:
		var a := (float(t) - float(toes - 1) * 0.5) * (0.42 if toes < 4 else 0.32)
		var d := Vector3(sin(a), 0.0, cos(a))
		var t0 := Vector3.UP * r * 0.3 + d * r * 0.9
		var t1 := t0 + d * tl - Vector3.UP * 0.015
		PropModels.rod(s, t0, t1, r * 0.38, r * 0.22, 4, spec["skin"])
		PropModels.rod(s, t1, t1 + d * tl * 0.45 - Vector3.UP * 0.01, r * 0.2, 0.002, 3, spec["claw"])


# --- posing ------------------------------------------------------------------------------------------------------------

## The heading (radians, 0 = straight back along -Z) of the spine at u (0 the neck .. 1 the tail tip).
func _heading(u: float) -> float:
	var th := deg_to_rad(bend) * u
	if wave != 0.0:
		th += deg_to_rad(wave) * pow(u, 1.3) * sin(TAU * (phase - u * 0.85))
	if walk_k > 0.0:
		var gt := TAU * gait
		th += walk_k * deg_to_rad(11.0) * sin(gt) * clampf(u / 0.4, 0.0, 1.0)
		th -= walk_k * deg_to_rad(22.0) * smoothstep(0.38, 1.0, u) * sin(gt - 1.2 - 2.2 * (u - 0.4))
	return th


## The spine: N_SPINE + 1 positions (y 0) from the neck joint to the tail tip.
func _spine() -> PackedVector3Array:
	var pts := PackedVector3Array()
	var ds := BODY_LEN / float(N_SPINE)
	var pos := Vector3(0.0, 0.0, NECK_Z)
	for i in N_SPINE + 1:
		pts.append(pos)
		var th := _heading((float(i) + 0.5) / float(N_SPINE))
		pos += Vector3(sin(th), 0.0, -cos(th)) * ds
	return pts


static func _at(sp: PackedVector3Array, u: float) -> Vector3:
	var f := clampf(u, 0.0, 1.0) * float(N_SPINE)
	var i := mini(int(f), N_SPINE - 1)
	return sp[i].lerp(sp[i + 1], f - float(i))


## The lift of the body at u: the walk's high stance, the swim's raised neck.
func _yoff(u: float) -> float:
	return 0.1 * walk_k + 0.09 * swim_k * (1.0 - smoothstep(0.0, 0.22, u))


## Each segment's frame on the spine: its origin at its front joint, its -Z along the chord to its back joint.
func _seg_xfs(sp: PackedVector3Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for seg: Array in SEGMENTS:
		var u0 := float(seg[1])
		var u1 := float(seg[2])
		var p0 := _at(sp, u0) + Vector3.UP * _yoff(u0)
		var p1 := _at(sp, u1) + Vector3.UP * _yoff(u1)
		var fwd := (p0 - p1).normalized()
		var side := Vector3.UP.cross(fwd).normalized()
		out.append(Transform3D(Basis(side, fwd.cross(side), fwd), p0))
	return out


## The leg's shoulder, elbow and foot (model space) in the current pose, and the toes' direction.
func _leg_points(li: int, sp: PackedVector3Array, segs: Array[Transform3D]) -> Array:
	var hind := li >= 2
	var sd := 1.0 if li % 2 == 0 else -1.0
	var u := float(spec["hind_u"]) if hind else float(spec["front_u"])
	var si := 1 if hind else 0
	var sxf: Transform3D = segs[si]
	var st := st_at(spec["body"], u)
	var shoulder := sxf * Vector3(sd * st.y * 0.72, st.z + (st.w - st.z) * 0.4, -(u - float(SEGMENTS[si][1])) * BODY_LEN)
	var fwd := sxf.basis.z.normalized()
	fwd = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var reach := float(spec["reach"]) * (1.1 if hind else 1.0)
	# on land: the paw planted out from the body, stepping with the gait (diagonal pairs: the right front with the left hind)
	var base := _at(sp, u) + side * sd * (st.y + reach * 0.5) + fwd * (-0.03 if hind else 0.05)
	base.y = 0.0
	var dz := 0.0
	var fy := 0.0
	if walk_k > 0.0:
		var ph := fposmod(gait + (0.0 if (li == 0 or li == 3) else 0.5), 1.0)
		var stride := 0.17 * walk_k
		if ph < 0.6:
			dz = stride * (1.0 - 2.0 * ph / 0.6)
		else:
			var q := (ph - 0.6) / 0.4
			dz = -stride + 2.0 * stride * q
			fy = 0.08 * walk_k * sin(PI * q)
	var foot := base + fwd * dz + Vector3.UP * fy
	var elbow := shoulder.lerp(foot, 0.55) + side * sd * 0.07 + Vector3.UP * (0.075 + 0.5 * fy)
	var toe := (fwd + side * sd * (0.25 if hind else 0.45)).normalized()
	if swim_k > 0.0:
		# swimming: folded back along the flanks, the paws off the floor, the toes trailing
		var e2 := shoulder + side * sd * 0.06 - fwd * 0.12 - Vector3.UP * 0.02
		var f2 := e2 - fwd * (0.16 if hind else 0.12) + side * sd * 0.03 + Vector3.UP * 0.03
		elbow = elbow.lerp(e2, swim_k)
		foot = foot.lerp(f2, swim_k)
		toe = toe.lerp((-fwd + side * sd * 0.3).normalized(), swim_k).normalized()
	return [shoulder, elbow, foot, toe, fy]


## Pose every part from the vars.
func apply() -> void:
	var sp := _spine()
	var segs := _seg_xfs(sp)
	for i in SEGMENTS.size():
		var xf: Transform3D = segs[i]
		if i == 0 and breath != 0.0:
			xf.basis = xf.basis * Basis.from_scale(Vector3(1.0 + 0.06 * breath, 1.0 + 0.04 * breath, 1.0))
		(parts[str(SEGMENTS[i][0])] as Node3D).transform = xf
	# the head on the neck joint: turned, pitched, and lifted by the gape
	var gape := jaw * float(spec["jaw_max"])
	var fwd := segs[0].basis.z
	var n := _at(sp, 0.0) + Vector3.UP * (_yoff(0.0) + 0.0022 * gape)
	var yaw := atan2(fwd.x, fwd.z) + deg_to_rad(head_yaw)
	var pivot := Vector3(0, 0.2, 0)
	var hx := Transform3D(Basis(Vector3.UP, yaw), n) * Transform3D(Basis.IDENTITY, pivot) \
		* Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(head_pitch + 0.65 * gape)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	(parts["head"] as Node3D).transform = hx
	(parts["jaw"] as Node3D).transform = hx * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(gape)), _hinge())
	for li in LEGS.size():
		var lp := _leg_points(li, sp, segs)
		var shoulder: Vector3 = lp[0]
		var elbow: Vector3 = lp[1]
		var foot: Vector3 = lp[2]
		var toe: Vector3 = lp[3]
		var r := _leg_r(li)
		var rest: Vector2 = _rest_len[LEGS[li]]
		var ankle := foot + Vector3.UP * r * 0.55
		(parts["upper_" + LEGS[li]] as Node3D).transform = _aim(shoulder, elbow, rest.x)
		(parts["lower_" + LEGS[li]] as Node3D).transform = _aim(elbow, ankle, rest.y)
		var fb := Basis(-toe.cross(Vector3.UP).normalized(), Vector3.UP, toe)
		var lifted := swim_k > 0.0 or float(lp[4]) > 0.01
		if lifted:
			fb = Basis(fb.x, lerpf(0.25, -0.35, swim_k)) * fb
		(parts["paw_" + LEGS[li]] as Node3D).transform = Transform3D(fb, foot)


## A part hanging down its -Y from `a`, turned to reach `b` and stretched from its rest length.
static func _aim(a: Vector3, b: Vector3, rest: float) -> Transform3D:
	var d := b - a
	var l := d.length()
	if l < 0.0001:
		return Transform3D(Basis.IDENTITY, a)
	return Transform3D(Basis(Quaternion(Vector3.DOWN, d / l)) * Basis.from_scale(Vector3(1.0, l / maxf(rest, 0.001), 1.0)), a)

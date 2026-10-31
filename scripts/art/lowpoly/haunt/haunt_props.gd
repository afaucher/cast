class_name HauntProps
extends RefCounted
## The haunted rooms' props (docs/design/mansion-rooms.md, docs/design/church-rooms.md): code-built LowPoly set dressing
## for a haunted mansion (MansionProps) and a church (ChurchProps). Cosmetic models only: no HP, no collision, no
## networking of their own. The GAME uses them since haunted-build-plan.md H1: the mansion and church room themes' decor
## (RoomThemeDefs.DECOR rows with "haunt", built by DecorModels._haunt and placed by HauntVignettes; walk-blocking and
## breaking are DecorProp's, as for any decor) and the haunted sites' priced antiques (PricedProp.TABLE rows with "haunt":
## the actor is the PricedProp, this is its look). The labs and the gym put them down too; the vestry's and the bell
## tower's pieces (dropped rooms) are lab-only.
##
## Same kit as PropModels / DecorModels: LowPoly soups, MonsterMaterial (ink outline, amber rim, vertex alpha 0.5 = an
## emissive face), origin at the base centre, FRONT = +Z; a wall piece has its back at z = -depth / 2. Built to read at the
## game camera (ortho size 24): chunky shapes, nothing finer than about 0.05. Portraits and books carry no text (Cast is
## not a reading game): faces are pale ovals on dark grounds, spines are plain colours with a gilt band.
##
## A built prop is a Node3D "Model" (group HauntLook.PROPS_GROUP) with "Body" (the outlined mesh), optional "Glass" (a
## see-through mesh: the conservatory case, the mirror) and optional "Candles" (group HauntLook.CANDLES_GROUP: the flames
## mesh plus one small warm OmniLight per cluster of flames). HauntLook.apply_light lights or snuffs the candles.
##
##   var node := HauntProps.build("bookshelf")
##   HauntProps.build("dining_table", {"length": 5.2})
##   HauntProps.build("portrait", {"v": 2, "big": true})

const MansionProps := preload("res://scripts/art/lowpoly/haunt/mansion_props.gd")
const ChurchProps := preload("res://scripts/art/lowpoly/haunt/church_props.gd")

const WALNUT := Color(0.30, 0.17, 0.09)
const WALNUT_DK := Color(0.17, 0.09, 0.05)
const OAK := Color(0.55, 0.38, 0.21)
const OAK_DK := Color(0.36, 0.23, 0.12)
const GILT := Color(0.84, 0.64, 0.26)
const GILT_DK := Color(0.56, 0.40, 0.15)
const LEATHER := Color(0.45, 0.12, 0.09)
const VELVET := Color(0.55, 0.07, 0.11)
const VELVET_GREEN := Color(0.12, 0.30, 0.20)
const LINEN := Color(0.90, 0.88, 0.80)
const SILVER := Color(0.74, 0.76, 0.80)
const WAX := Color(0.95, 0.91, 0.78)
const FLAME := Color(1.0, 0.80, 0.38)
const FLAME_CORE := Color(1.0, 0.96, 0.75)
const MARBLE := Color(0.88, 0.87, 0.84)
const MARBLE_DK := Color(0.60, 0.60, 0.63)
const STONE := Color(0.56, 0.54, 0.50)
const STONE_DK := Color(0.38, 0.36, 0.34)
const IRON := Color(0.15, 0.15, 0.17)
const IRON_LT := Color(0.32, 0.32, 0.36)
const PAINT_WHITE := Color(0.86, 0.87, 0.83)
const LEAF := Color(0.22, 0.46, 0.17)
const LEAF_DK := Color(0.12, 0.30, 0.13)
const LEAF_LT := Color(0.40, 0.62, 0.24)
const SOIL := Color(0.20, 0.13, 0.08)
const TERRACOTTA := Color(0.68, 0.34, 0.19)
const BRONZE := Color(0.62, 0.43, 0.18)
const BRONZE_DK := Color(0.38, 0.25, 0.10)
const PIANO_BLACK := Color(0.07, 0.065, 0.075)
const CRYSTAL := Color(0.78, 0.88, 0.95)
const BOOKS: Array[Color] = [Color(0.45, 0.10, 0.10), Color(0.13, 0.25, 0.16), Color(0.14, 0.18, 0.34), Color(0.50, 0.32, 0.14),
	Color(0.30, 0.10, 0.22), Color(0.62, 0.50, 0.30), Color(0.20, 0.13, 0.09), Color(0.36, 0.40, 0.20)]

## The key props the gym can put down (GymSpawns group "rooms"), mansion first.
const GYM_KINDS: Array[String] = ["bookshelf", "library_ladder", "reading_chair", "portrait", "gallery_screen", "chandelier",
	"grand_piano", "dining_table", "dining_chair", "fireplace", "planter_bed", "potted_palm", "wardian_case", "candelabra",
	"pew", "altar", "stained_window", "bell_frame"]
const GYM_YAW := 45.0                   ## a free-standing piece faces the camera
const GYM_WALL_REACH := 3.5             ## a wall piece looks this far for a wall to stand its back on

## The shared lab footprint and height of every kind (w along x, d along z, h), for placement and the fit checks.
## (Wall pieces: "wall" true, back at z = -d / 2.)
static var _rows: Dictionary = {}


## Every kind's row: {set ("mansion" / "church"), w, d, h, wall, label}.
static func rows() -> Dictionary:
	if _rows.is_empty():
		for k: String in MansionProps.KINDS:
			var r: Dictionary = (MansionProps.KINDS[k] as Dictionary).duplicate()
			r["set"] = "mansion"
			_rows[k] = r
		for k: String in ChurchProps.KINDS:
			var r: Dictionary = (ChurchProps.KINDS[k] as Dictionary).duplicate()
			r["set"] = "church"
			_rows[k] = r
	return _rows


static func kinds(set_name: String = "") -> Array[String]:
	var out: Array[String] = []
	for k: String in rows():
		if set_name == "" or str(rows()[k]["set"]) == set_name:
			out.append(k)
	return out


static func row(kind: String) -> Dictionary:
	return rows().get(kind, {})


## The pieces one prop is built from: the outlined body, the flames (no outline), the see-through glass and the flame
## clusters' light points. Builders add to it through the helpers below.
class Kit extends RefCounted:
	var s := LowPoly.Soup.new(7, 0.06)      ## the body
	var f := LowPoly.Soup.new(9, 0.03)      ## flames (emissive, no outline; out in moonlight)
	var g := LowPoly.Soup.new(13, 0.0)      ## glass (see-through)
	var lights: Array[Vector3] = []         ## flame points (clustered into lights by build)
	var outline := 2.3
	var flame_k := 1.0                      ## flame size scale

	func box(size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
		PropModels.box(s, size, pos, col, rot)

	func cyl(rb: float, rt: float, h: float, sides: int, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
		PropModels.cyl(s, rb, rt, h, sides, pos, col, rot)

	func ball(radii: Vector3, pos: Vector3, col: Color, detail: int = 1, jit: float = 0.08) -> void:
		PropModels.ball(s, radii, pos, col, detail, jit)

	func rod(a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col: Color) -> void:
		PropModels.rod(s, a, b, ra, rb, sides, col)

	func frus(bottom: Vector2, top: Vector2, h: float, pos: Vector3, col: Color, off: Vector2 = Vector2.ZERO, rot: Vector3 = Vector3.ZERO) -> void:
		PropModels.frus(s, bottom, top, h, pos, col, off, rot)

	func glass_box(size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
		g.merge(LowPoly.box(size, Color(1, 1, 1), 1, 0.0, 1, 0.0), LowPoly.at(pos, rot))

	## A candle standing on `pos`: the wax in the body, the flame in the flames, its point for the lights.
	func candle(pos: Vector3, h: float = 0.2, r: float = 0.035) -> void:
		PropModels.cyl(s, r, r * 0.9, h, 6, pos + Vector3(0, h * 0.5, 0), WAX)
		flame(pos + Vector3(0, h, 0))

	## A flame (a small glowing teardrop) with its base at `pos`.
	func flame(pos: Vector3, k: float = 1.0) -> void:
		var q := k * flame_k
		f.merge(LowPoly.cylinder(0.05 * q, 0.0, 0.16 * q, 5, PropModels.glow(FLAME), 3, 0.0, 1, 0.0), LowPoly.at(pos + Vector3(0, 0.09 * q, 0)))
		f.merge(LowPoly.boulder(Vector3(0.045, 0.05, 0.045) * q, 0, 0.0, PropModels.glow(FLAME_CORE), 5, 0.0), LowPoly.at(pos + Vector3(0, 0.04 * q, 0)))
		lights.append(pos + Vector3(0, 0.12 * q, 0))


## Build one kind. Unknown kinds are a gilt box (so a typo shows).
static func build(kind: String, params: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	root.add_to_group(HauntLook.PROPS_GROUP)
	root.set_meta("haunt_kind", kind)
	var k := Kit.new()
	var r := row(kind)
	var script: GDScript = MansionProps if str(r.get("set", "")) == "mansion" else ChurchProps
	if r.is_empty() or not script.has_method("_" + kind):
		k.box(Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0), GILT)
	else:
		Callable(script, "_" + kind).call(k, params)
	if bool(r.get("flat", false)):
		k.outline = 0.0
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = k.s.to_mesh()
	var mat := MonsterMaterial.make(k.outline)
	mat.set_shader_parameter("glow_gain", 1.6)
	body.material_override = mat
	if k.outline == 0.0:
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	if k.g.tri_count() > 0:
		var gl := MeshInstance3D.new()
		gl.name = "Glass"
		gl.mesh = k.g.to_mesh(0.0)
		gl.material_override = glass_material()
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gl)
	if k.f.tri_count() > 0:
		root.add_child(_candles(k))
	return root


## The gym's spawn (GymSpawns "rooms"): `kind` built and put under GameWorld.root at `at`, facing the camera; a wall piece
## with its back on the nearest wall face within GYM_WALL_REACH when there is one. A plain cosmetic node: no collision.
static func gym_spawn(kind: String, at: Vector3) -> Node3D:
	if GameWorld.root == null:
		return null
	var m := build(kind)
	GameWorld.root.add_child(m)
	m.global_position = at
	m.rotation_degrees.y = GYM_YAW
	var r := row(kind)
	if bool(r.get("wall", false)) and GameWorld.map != null:
		var w := GameWorld.map.nearest_wall(at, GYM_WALL_REACH)
		if not w.is_empty():
			var n: Vector2 = w["normal"]
			var p: Vector2 = (w["point"] as Vector2) + n * (float(r.get("d", 0.5)) * 0.5 + 0.04)
			m.global_position = Vector3(p.x, at.y, p.y)
			m.rotation_degrees.y = rad_to_deg(atan2(n.x, n.y))
	return m


## The see-through glass: a faint cold sheen, a little specular.
static func glass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.72, 0.88, 0.92, 0.2)
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## The "Candles" node: the flames mesh and a light per cluster of flames (flames within 0.75 of each other share one).
static func _candles(k: Kit) -> Node3D:
	var c := Node3D.new()
	c.name = "Candles"
	c.add_to_group(HauntLook.CANDLES_GROUP)
	var fm := MeshInstance3D.new()
	fm.name = "Flames"
	fm.mesh = k.f.to_mesh(0.0)
	var mat := MonsterMaterial.make(0.0)
	mat.set_shader_parameter("glow_gain", 2.2)
	fm.material_override = mat
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(fm)
	for cl: Array in clusters(k.lights, 0.75):
		var l := OmniLight3D.new()
		l.name = "CandleLight"
		var sum := Vector3.ZERO
		for p: Vector3 in cl:
			sum += p
		l.position = sum / cl.size() + Vector3(0, 0.12, 0)
		l.light_color = HauntLook.CANDLE_COLOR
		l.light_energy = HauntLook.CANDLE_ENERGY * (0.7 + 0.15 * minf(cl.size(), 4.0))
		l.omni_range = HauntLook.CANDLE_RANGE
		l.omni_attenuation = 1.4
		l.light_specular = 0.15
		l.shadow_enabled = false
		c.add_child(l)
	c.visible = HauntLook.light != "moonlight"
	return c


## Greedy clusters of points no farther than `r` from their cluster's first point.
static func clusters(points: Array[Vector3], r: float) -> Array:
	var out: Array = []
	for p in points:
		var placed := false
		for cl: Array in out:
			if (cl[0] as Vector3).distance_to(p) <= r:
				cl.append(p)
				placed = true
				break
		if not placed:
			out.append([p])
	return out


# --- shared pieces -----------------------------------------------------------------------------------------------------

## A painting in a gilt frame, its back on z = `back`, its bottom edge at `y0`: `v` picks the picture (0 a gentleman in
## black, 1 a lady in crimson, 2 an old man with a white beard, 3 a moonlit landscape, 4 a child in blue). No text.
static func painting(k: Kit, v: int, w: float, h: float, y0: float, back: float, x: float = 0.0, flip: bool = false) -> void:
	var dz := -1.0 if flip else 1.0
	var fr := 0.11
	var z0 := back + dz * 0.04
	# the frame: four gilt bars, a darker inner lip, corner bosses
	k.box(Vector3(w, fr, 0.08), Vector3(x, y0 + fr * 0.5, z0), GILT)
	k.box(Vector3(w, fr, 0.08), Vector3(x, y0 + h - fr * 0.5, z0), GILT)
	k.box(Vector3(fr, h - fr * 2.0, 0.08), Vector3(x - w * 0.5 + fr * 0.5, y0 + h * 0.5, z0), GILT)
	k.box(Vector3(fr, h - fr * 2.0, 0.08), Vector3(x + w * 0.5 - fr * 0.5, y0 + h * 0.5, z0), GILT)
	for cx in [-1.0, 1.0]:
		for cy in [0.0, 1.0]:
			k.ball(Vector3(0.06, 0.06, 0.04), Vector3(x + cx * (w * 0.5 - fr * 0.5), y0 + fr * 0.5 + cy * (h - fr), z0 + dz * 0.04), GILT_DK, 0, 0.0)
	var iw := w - fr * 2.0
	var ih := h - fr * 2.0
	var cy0 := y0 + fr
	var zc := back + dz * 0.03
	var zp := back + dz * 0.045
	var zq := back + dz * 0.055
	var grounds: Array[Color] = [Color(0.16, 0.17, 0.10), Color(0.10, 0.18, 0.20), Color(0.20, 0.12, 0.08), Color(0.06, 0.08, 0.16), Color(0.22, 0.16, 0.10)]
	var ground: Color = grounds[posmod(v, grounds.size())]
	k.box(Vector3(iw, ih, 0.04), Vector3(x, cy0 + ih * 0.5, zc), ground)
	if v == 3:
		# a moonlit landscape: a dark hill line, a pale moon, a black tree
		k.box(Vector3(iw * 0.98, ih * 0.32, 0.02), Vector3(x, cy0 + ih * 0.16, zp), Color(0.08, 0.12, 0.08))
		k.box(Vector3(iw * 0.6, ih * 0.16, 0.02), Vector3(x + iw * 0.18, cy0 + ih * 0.36, zp), Color(0.12, 0.16, 0.12), Vector3(0, 0, 8))
		k.ball(Vector3(iw * 0.09, iw * 0.09, 0.01), Vector3(x - iw * 0.22, cy0 + ih * 0.74, zp), Color(0.92, 0.9, 0.78), 0, 0.0)
		k.box(Vector3(0.04, ih * 0.34, 0.02), Vector3(x + iw * 0.26, cy0 + ih * 0.42, zq), Color(0.04, 0.04, 0.04))
		k.ball(Vector3(iw * 0.13, ih * 0.12, 0.01), Vector3(x + iw * 0.26, cy0 + ih * 0.62, zq), Color(0.05, 0.07, 0.05), 0, 0.0)
		return
	var coats: Array[Color] = [Color(0.06, 0.06, 0.07), Color(0.58, 0.08, 0.12), Color(0.18, 0.12, 0.10), Color(0.1, 0.1, 0.1), Color(0.20, 0.32, 0.58)]
	var hairs: Array[Color] = [Color(0.45, 0.43, 0.42), Color(0.16, 0.09, 0.06), Color(0.88, 0.87, 0.84), Color(0.1, 0.1, 0.1), Color(0.70, 0.52, 0.22)]
	var coat: Color = coats[posmod(v, coats.size())]
	var hair: Color = hairs[posmod(v, hairs.size())]
	var skin := Color(0.88, 0.76, 0.64)
	var kid := v == 4
	var hs := 0.8 if kid else 1.0
	# shoulders and coat (a trapezoid), a white collar, the face, the hair
	k.frus(Vector2(iw * 0.82, 0.02), Vector2(iw * 0.42 * hs, 0.02), ih * 0.4, Vector3(x, cy0 + ih * 0.2, zp), coat)
	k.box(Vector3(iw * 0.14, ih * 0.1, 0.02), Vector3(x, cy0 + ih * 0.38, zq), LINEN if v != 1 else Color(0.85, 0.72, 0.5), Vector3(0, 0, 45))
	var head := Vector3(x, cy0 + ih * (0.58 if not kid else 0.54), zq)
	k.ball(Vector3(iw * 0.15, ih * 0.14, 0.015) * hs, head, skin, 0, 0.0)
	match v:
		1:   # an updo
			k.ball(Vector3(iw * 0.19, ih * 0.1, 0.012), head + Vector3(0, ih * 0.1, 0.004 * dz), hair, 0, 0.0)
			k.ball(Vector3(iw * 0.07, iw * 0.07, 0.012), head + Vector3(0, ih * 0.2, 0.004 * dz), hair, 0, 0.0)
		2:   # white hair and a beard
			k.ball(Vector3(iw * 0.17, ih * 0.07, 0.012), head + Vector3(0, ih * 0.1, 0.004 * dz), hair, 0, 0.0)
			k.ball(Vector3(iw * 0.13, ih * 0.1, 0.012), head + Vector3(0, -ih * 0.1, 0.004 * dz), hair, 0, 0.0)
		_:
			k.ball(Vector3(iw * 0.17, ih * 0.08, 0.012) * hs, head + Vector3(0, ih * 0.09 * hs, 0.004 * dz), hair, 0, 0.0)
	# the eyes: two dark dots (a haunting could light them later)
	for ex in [-1.0, 1.0]:
		k.box(Vector3(iw * 0.035, ih * 0.025, 0.01), head + Vector3(ex * iw * 0.055 * hs, ih * 0.015, 0.012 * dz), Color(0.08, 0.05, 0.04))


## A small brass candlestick at `pos` (a single candle).
static func candlestick(k: Kit, pos: Vector3, col: Color = GILT) -> void:
	k.cyl(0.07, 0.07, 0.03, 8, pos + Vector3(0, 0.015, 0), col)
	k.cyl(0.02, 0.025, 0.2, 6, pos + Vector3(0, 0.13, 0), col)
	k.cyl(0.045, 0.03, 0.03, 8, pos + Vector3(0, 0.245, 0), col)
	k.candle(pos + Vector3(0, 0.26, 0), 0.16, 0.028)


## A five-branch candelabrum at `pos`, `h` tall to its candle cups.
static func candelabrum(k: Kit, pos: Vector3, h: float, col: Color = GILT, arms: int = 5) -> void:
	k.cyl(0.12, 0.09, 0.05, 8, pos + Vector3(0, 0.025, 0), col)
	k.cyl(0.025, 0.03, h - 0.05, 6, pos + Vector3(0, h * 0.5, 0), col)
	k.ball(Vector3(0.05, 0.05, 0.05), pos + Vector3(0, h * 0.55, 0), col, 0, 0.0)
	var spread := 0.11 * float(arms)
	for i in arms:
		var t := 0.0 if arms == 1 else float(i) / float(arms - 1) * 2.0 - 1.0
		var cx := t * spread * 0.5
		var cy := h + 0.02 - absf(t) * 0.06
		if absf(t) > 0.01:
			k.rod(pos + Vector3(0, h - 0.08, 0), pos + Vector3(cx, cy - 0.02, 0), 0.015, 0.015, 4, col)
		k.cyl(0.04, 0.03, 0.04, 6, pos + Vector3(cx, cy, 0), col)
		k.candle(pos + Vector3(cx, cy + 0.02, 0), 0.16, 0.026)


## A long floor runner (a flat carpet): `length` along x, `width` along z, with a border.
static func runner(k: Kit, length: float, width: float, col: Color, border: Color, pos: Vector3 = Vector3.ZERO, rot_y: float = 0.0) -> void:
	k.box(Vector3(length, 0.02, width), pos + Vector3(0, 0.01, 0), border, Vector3(0, rot_y, 0))
	k.box(Vector3(length - 0.16, 0.024, width - 0.16), pos + Vector3(0, 0.012, 0), col, Vector3(0, rot_y, 0))


## A ladder from `foot` to `top` (rails and rungs).
static func ladder(k: Kit, foot: Vector3, top: Vector3, width: float, col: Color, rungs: int) -> void:
	var across := Vector3(width * 0.5, 0, 0)
	k.rod(foot - across, top - across, 0.035, 0.035, 4, col)
	k.rod(foot + across, top + across, 0.035, 0.035, 4, col)
	for i in rungs:
		var t := (float(i) + 0.7) / float(rungs + 0.4)
		var p := foot.lerp(top, t)
		k.rod(p - across, p + across, 0.022, 0.022, 4, col)

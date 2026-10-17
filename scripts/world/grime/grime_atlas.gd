class_name GrimeAtlas
extends RefCounted
## The grime texture atlas, painted in code (no assets): chunky faceted blobs, shards and strokes in a
## few flat colours with soft alpha edges, laid out on a COLS x ROWS grid of TILE-pixel tiles. Two
## images share one layout: the ALBEDO (RGBA, alpha = coverage) and the EMISSION mask (RGB, used by the
## ichor / ember / glass / spill kinds for a subtle glow).
##
## Every tile keeps its content inside a circle of CONTENT * TILE radius (so a quad of edge S holds marks
## up to S * CONTENT out from its centre), and is painted with a fixed per-tile seed, so the atlas is the
## same on every run.
##
## Colours are deliberately low contrast: the dungeon floor is dark slate with glowing amber seams and the
## grime must never fight them. GrimeLayer's shader also clips every mark at the hex tile edges.

const COLS := 7
const ROWS := 7
const TILE := 80
const CONTENT := 0.46

## kind -> number of variants. Insertion order fixes the tile numbers.
const VARIANTS := {
	"scorch": 2, "scratch": 2, "ichor": 3, "crack": 2, "rubble": 2, "paper": 2, "glass": 1, "wax": 2,
	"wine": 2, "popcorn": 2, "chalk": 2, "oil": 2, "rust": 2, "spill": 2,
	"kernel": 2, "tooth": 2, "ring": 1, "drag": 2, "scuff": 2, "crack_ichor": 2, "stain": 2,
	"puddle": 2,
}

static var _first: Dictionary = {}
static var _albedo: Image = null
static var _emission: Image = null
static var _albedo_tex: ImageTexture = null
static var _emission_tex: ImageTexture = null


static func kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in VARIANTS:
		out.append(k)
	return out


static func has_kind(kind: String) -> bool:
	return VARIANTS.has(kind)


static func variant_count(kind: String) -> int:
	return int(VARIANTS.get(kind, 0))


## Tile number of `kind`'s `variant` (wrapped into range), or -1 for an unknown kind.
static func tile_of(kind: String, variant: int) -> int:
	if not VARIANTS.has(kind):
		return -1
	if _first.is_empty():
		var n := 0
		for k: String in VARIANTS:
			_first[k] = n
			n += int(VARIANTS[k])
	return int(_first[kind]) + posmod(variant, int(VARIANTS[kind]))


## Grid column / row of a tile.
static func tile_cell(tile: int) -> Vector2:
	return Vector2(float(tile % COLS), float(tile / COLS))


static func tile_count() -> int:
	var n := 0
	for k: String in VARIANTS:
		n += int(VARIANTS[k])
	return n


static func albedo_texture() -> ImageTexture:
	_ensure()
	return _albedo_tex


static func emission_texture() -> ImageTexture:
	_ensure()
	return _emission_tex


## The raw images (albedo, emission), painted once per process.
static func images() -> Array[Image]:
	_ensure()
	return [_albedo, _emission]


static func _ensure() -> void:
	if _albedo != null:
		return
	_albedo = Image.create(COLS * TILE, ROWS * TILE, true, Image.FORMAT_RGBA8)
	_emission = Image.create(COLS * TILE, ROWS * TILE, true, Image.FORMAT_RGBA8)
	_albedo.fill(Color(0, 0, 0, 0))
	_emission.fill(Color(0, 0, 0, 1))
	for k: String in VARIANTS:
		for v in int(VARIANTS[k]):
			var tile := tile_of(k, v)
			var p := Painter.new()
			p.img = _albedo
			p.emi = _emission
			p.ox = (tile % COLS) * TILE
			p.oy = (tile / COLS) * TILE
			p.n = TILE
			p.rng.seed = 7919 * (tile + 1) + 104729 * v
			_paint(k, v, p)
	_albedo.generate_mipmaps()
	_emission.generate_mipmaps()
	_albedo_tex = ImageTexture.create_from_image(_albedo)
	_emission_tex = ImageTexture.create_from_image(_emission)


# ---------------------------------------------------------------------- painter

class Painter extends RefCounted:
	var img: Image
	var emi: Image
	var ox := 0
	var oy := 0
	var n := 80
	var rng := RandomNumberGenerator.new()

	## Start a tile: every pixel gets `base` with alpha 0, so filtering never bleeds a dark halo.
	func clear(base: Color) -> void:
		img.fill_rect(Rect2i(ox, oy, n, n), Color(base.r, base.g, base.b, 0.0))

	func put(x: int, y: int, c: Color, e: Color = Color(0, 0, 0, 0)) -> void:
		if x < 0 or y < 0 or x >= n or y >= n or c.a <= 0.002:
			return
		var px := ox + x
		var py := oy + y
		var d: Color = img.get_pixel(px, py)
		var a: float = c.a + d.a * (1.0 - c.a)
		var w: float = d.a * (1.0 - c.a)
		img.set_pixel(px, py, Color((c.r * c.a + d.r * w) / a, (c.g * c.a + d.g * w) / a, (c.b * c.a + d.b * w) / a, a))
		if e.a > 0.0:
			var old: Color = emi.get_pixel(px, py)
			var k: float = c.a * e.a
			emi.set_pixel(px, py, Color(old.r * (1.0 - k) + e.r * k, old.g * (1.0 - k) + e.g * k, old.b * (1.0 - k) + e.b * k, 1.0))

	static func shade(c: Color, k: float) -> Color:
		return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)

	## An irregular faceted blob: a polygon of `verts` jittered corners, each facet a slightly different shade.
	func blob(cx: float, cy: float, r: float, col: Color, e: Color = Color(0, 0, 0, 0), verts: int = 8, irr: float = 0.25, soft: float = 2.5, facet: float = 0.12, squash: float = 1.0) -> void:
		var ang := PackedFloat32Array()
		var pts := PackedVector2Array()
		var base_a := rng.randf() * TAU
		for i in verts:
			var a := base_a + TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / verts
			ang.append(a)
			var rr := r * (1.0 + rng.randf_range(-irr, irr))
			pts.append(Vector2(cos(a) * rr, sin(a) * rr * squash))
		var shades := PackedFloat32Array()
		for i in verts:
			shades.append(1.0 + rng.randf_range(-facet, facet))
		var rel := PackedFloat32Array()
		for i in verts:
			rel.append(ang[i] - ang[0])
		var reach := r * (1.0 + irr) + soft
		var x0 := int(floorf(cx - reach))
		var x1 := int(ceilf(cx + reach))
		var y0 := int(floorf(cy - reach))
		var y1 := int(ceilf(cy + reach))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var dv := Vector2(float(x) + 0.5 - cx, float(y) + 0.5 - cy)
				var dist := dv.length()
				var edge: float
				var sector := 0
				if dist < 0.001:
					edge = 1.0e9
				else:
					var th := fposmod(atan2(dv.y, dv.x) - ang[0], TAU)
					for i in verts:
						var nxt: float = rel[i + 1] if i + 1 < verts else TAU
						if th >= rel[i] and th < nxt:
							sector = i
							break
					var pa: Vector2 = pts[sector]
					var pb: Vector2 = pts[(sector + 1) % verts]
					var u := dv / dist
					var ab := pb - pa
					var den := u.x * ab.y - u.y * ab.x
					edge = (pa.x * ab.y - pa.y * ab.x) / den if absf(den) > 0.00001 else r
				var cov := clampf((edge - dist) / soft, 0.0, 1.0)
				if cov > 0.0:
					var cc := shade(col, shades[sector])
					cc.a = col.a * cov
					put(x, y, cc, e)

	## A tapered stroke from (x0,y0) to (x1,y1), full width w0 at the start and w1 at the end.
	func stroke(x0: float, y0: float, x1: float, y1: float, w0: float, w1: float, col: Color, e: Color = Color(0, 0, 0, 0), soft: float = 1.4) -> void:
		var a := Vector2(x0, y0)
		var b := Vector2(x1, y1)
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 0.0001)
		var reach := maxf(w0, w1) * 0.5 + soft + 1.0
		var xa := int(floorf(minf(x0, x1) - reach))
		var xb := int(ceilf(maxf(x0, x1) + reach))
		var ya := int(floorf(minf(y0, y1) - reach))
		var yb := int(ceilf(maxf(y0, y1) + reach))
		for y in range(ya, yb + 1):
			for x in range(xa, xb + 1):
				var p := Vector2(float(x) + 0.5, float(y) + 0.5)
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var half := lerpf(w0, w1, t) * 0.5
				var cov := clampf((half - (p - (a + ab * t)).length()) / soft + 0.5, 0.0, 1.0)
				if cov > 0.0:
					var cc := col
					cc.a = col.a * cov
					put(x, y, cc, e)

	## A jagged polyline (a crack) from `from` to `to`, optionally with side branches.
	func crack(from: Vector2, to: Vector2, w0: float, w1: float, col: Color, e: Color = Color(0, 0, 0, 0), jag: float = 4.0, steps: int = 5, soft: float = 1.2) -> Array[Vector2]:
		var pts: Array[Vector2] = [from]
		var dir := to - from
		var side := Vector2(-dir.y, dir.x).normalized()
		for i in range(1, steps):
			var t := float(i) / steps
			pts.append(from + dir * t + side * rng.randf_range(-jag, jag))
		pts.append(to)
		for i in pts.size() - 1:
			var t0 := float(i) / (pts.size() - 1)
			var t1 := float(i + 1) / (pts.size() - 1)
			stroke(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, lerpf(w0, w1, t0), lerpf(w0, w1, t1), col, e, soft)
		return pts

	## A convex polygon (any winding) with a soft edge.
	func convex(pts: PackedVector2Array, col: Color, e: Color = Color(0, 0, 0, 0), soft: float = 1.2, shade_k: float = 1.0) -> void:
		var area := 0.0
		var lo := Vector2(1.0e9, 1.0e9)
		var hi := Vector2(-1.0e9, -1.0e9)
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			area += a.x * b.y - b.x * a.y
			lo = Vector2(minf(lo.x, a.x), minf(lo.y, a.y))
			hi = Vector2(maxf(hi.x, a.x), maxf(hi.y, a.y))
		var sgn := 1.0 if area >= 0.0 else -1.0
		var c := shade(col, shade_k)
		for y in range(int(floorf(lo.y - soft)), int(ceilf(hi.y + soft)) + 1):
			for x in range(int(floorf(lo.x - soft)), int(ceilf(hi.x + soft)) + 1):
				var p := Vector2(float(x) + 0.5, float(y) + 0.5)
				var m := 1.0e9
				for i in pts.size():
					var a := pts[i]
					var b := pts[(i + 1) % pts.size()]
					var ab := b - a
					var l := ab.length()
					if l < 0.0001:
						continue
					m = minf(m, sgn * (ab.x * (p.y - a.y) - ab.y * (p.x - a.x)) / l)
				var cov := clampf(m / soft + 0.5, 0.0, 1.0)
				if cov > 0.0:
					var cc := c
					cc.a = col.a * cov
					put(x, y, cc, e)

	## A rotated rectangle (w x h) centred on (cx, cy).
	func rect(cx: float, cy: float, w: float, h: float, ang: float, col: Color, e: Color = Color(0, 0, 0, 0), soft: float = 1.0) -> void:
		var pts := PackedVector2Array()
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var q: Vector2 = Vector2(s.x * w * 0.5, s.y * h * 0.5).rotated(ang)
			pts.append(Vector2(cx, cy) + q)
		convex(pts, col, e, soft)

	func jitter(r: float) -> Vector2:
		return Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))

	func polar(r: float, a: float) -> Vector2:
		return Vector2(cos(a), sin(a)) * r


# ---------------------------------------------------------------------- recipes

static func _paint(kind: String, v: int, p: Painter) -> void:
	var c := Vector2(p.n * 0.5, p.n * 0.5)
	match kind:
		"scorch": _scorch(p, c, v)
		"scratch": _scratch(p, c, v)
		"ichor": _puddle(p, c, v, Color(0.22, 0.05, 0.38, 0.90), Color(0.37, 0.12, 0.60, 0.82), Color(0.55, 0.16, 0.95, 1.0), Color(0.72, 0.52, 0.95, 0.45))
		"crack": _crack_net(p, c, v, false)
		"rubble": _rubble(p, c, v)
		"paper": _paper(p, c, v)
		"glass": _glass(p, c)
		"wax": _wax(p, c, v)
		"wine": _wine(p, c, v)
		"popcorn": _popcorn(p, c, v)
		"chalk": _chalk(p, c, v)
		"oil": _oil(p, c, v)
		"rust": _rust(p, c, v)
		"spill": _puddle(p, c, v + 5, Color(0.12, 0.50, 0.17, 0.92), Color(0.36, 0.86, 0.30, 0.85), Color(0.30, 1.0, 0.25, 1.0), Color(0.80, 1.0, 0.70, 0.5))
		"kernel": _kernel(p, c, v)
		"tooth": _tooth(p, c, v)
		"ring": _ring(p, c)
		"drag": _drag(p, v)
		"scuff": _scuff(p, c, v)
		"crack_ichor": _crack_net(p, c, v, true)
		"stain": _stain(p, c, v)
		"puddle": _puddle(p, c, v + 2, Color(0.20, 0.42, 0.60, 0.52), Color(0.38, 0.66, 0.84, 0.46), Color(0.3, 0.7, 1.0, 1.0), Color(0.85, 0.95, 1.0, 0.45))


static func _scorch(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.04, 0.03, 0.03))
	p.blob(c.x, c.y, 33.0, Color(0.12, 0.10, 0.09, 0.26), Color(0, 0, 0, 0), 9, 0.2, 7.0, 0.08)
	for i in 8 + v * 2:   # radial blast streaks
		var a := p.rng.randf() * TAU
		p.stroke(c.x + cos(a) * 14.0, c.y + sin(a) * 14.0, c.x + cos(a) * p.rng.randf_range(28.0, 36.0), c.y + sin(a) * p.rng.randf_range(28.0, 36.0), 4.0, 0.8, Color(0.03, 0.025, 0.025, 0.5))
	p.blob(c.x, c.y, 24.0, Color(0.035, 0.028, 0.027, 0.80), Color(0, 0, 0, 0), 8, 0.25, 4.0, 0.12)
	p.blob(c.x + p.rng.randf_range(-3, 3), c.y + p.rng.randf_range(-3, 3), 13.0, Color(0.015, 0.012, 0.012, 0.75), Color(0, 0, 0, 0), 7, 0.25, 3.0, 0.1)
	for i in 6:   # a few embers still glowing in the char
		var q := c + p.polar(p.rng.randf_range(8.0, 22.0), p.rng.randf() * TAU)
		p.blob(q.x, q.y, p.rng.randf_range(1.4, 2.6), Color(1.0, 0.48, 0.12, 0.85), Color(1.0, 0.42, 0.10, 1.0), 5, 0.2, 1.0, 0.0)


static func _scratch(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.5, 0.52, 0.6))
	var base := p.rng.randf_range(-0.5, 0.5) + (0.6 if v == 1 else 0.0)
	var dir := Vector2(cos(base), sin(base))
	var side := Vector2(-dir.y, dir.x)
	var count := 4 - v
	for i in count:
		var off := (float(i) - (count - 1) * 0.5) * 9.5 + p.rng.randf_range(-1.0, 1.0)
		var len_k := p.rng.randf_range(0.78, 1.0)
		var a := c + side * off - dir * 30.0 * len_k
		var b := c + side * off + dir * 30.0 * len_k + side * p.rng.randf_range(-3.0, 3.0)
		p.stroke(a.x + 1.5, a.y + 1.5, b.x + 1.5, b.y + 1.5, 3.4, 0.8, Color(0.02, 0.02, 0.03, 0.5))
		p.stroke(a.x, a.y, b.x, b.y, 3.2, 0.7, Color(0.56, 0.58, 0.68, 0.62))
		p.stroke(a.x, a.y, a.x + (b.x - a.x) * 0.25, a.y + (b.y - a.y) * 0.25, 1.6, 0.6, Color(0.82, 0.84, 0.92, 0.4))


## A puddle with a lighter faceted core, droplets and a small highlight (ichor / green spill).
static func _puddle(p: Painter, c: Vector2, v: int, body: Color, inner: Color, glow: Color, hi: Color) -> void:
	p.clear(Color(body.r, body.g, body.b))
	var verts := 8 + (v % 3)
	p.blob(c.x, c.y, 23.0 + (v % 3) * 2.0, body, Color(0, 0, 0, 0), verts, 0.32, 3.5, 0.14)
	for i in 4 + (v % 3):
		var q := c + p.polar(p.rng.randf_range(27.0, 34.0), p.rng.randf() * TAU)
		var rr := p.rng.randf_range(2.5, 5.5)
		p.blob(q.x, q.y, rr, body, Color(glow.r, glow.g, glow.b, 0.5), 6, 0.25, 1.4, 0.1)
	p.blob(c.x + p.rng.randf_range(-3, 3), c.y + p.rng.randf_range(-3, 3), 14.0, inner, Color(glow.r, glow.g, glow.b, 1.0), 7, 0.3, 3.0, 0.1)
	p.blob(c.x - 6.0, c.y - 7.0, 4.0, hi, Color(0, 0, 0, 0), 5, 0.2, 1.5, 0.0)


static func _crack_net(p: Painter, c: Vector2, v: int, glowing: bool) -> void:
	p.clear(Color(0.02, 0.02, 0.03))
	var arms := 5 + v
	var core := Color(0.012, 0.010, 0.016, 0.9)
	for i in arms:
		var a := TAU * (float(i) + p.rng.randf_range(-0.25, 0.25)) / arms
		var from := c + p.jitter(3.0)
		var to := c + p.polar(p.rng.randf_range(30.0, 37.0), a)
		if glowing:
			var gp := p.crack(from, to, 5.5, 2.2, Color(0.55, 0.13, 0.95, 0.5), Color(0.65, 0.18, 1.0, 1.0), 4.0, 5, 1.6)
			# redraw the same path darker and thinner on top (the glow shows as a halo along it)
			for k in gp.size() - 1:
				var t := float(k) / (gp.size() - 1)
				p.stroke(gp[k].x, gp[k].y, gp[k + 1].x, gp[k + 1].y, lerpf(2.2, 0.8, t), lerpf(2.2, 0.8, t + 1.0 / (gp.size() - 1)), core)
		else:
			var path := p.crack(from + Vector2(1, 1), to + Vector2(1, 1), 3.0, 1.0, Color(0.5, 0.55, 0.65, 0.30), Color(0, 0, 0, 0), 4.0, 5)
			for k in path.size() - 1:
				var t := float(k) / (path.size() - 1)
				p.stroke(path[k].x - 1, path[k].y - 1, path[k + 1].x - 1, path[k + 1].y - 1, lerpf(2.6, 0.9, t), lerpf(2.6, 0.9, t + 1.0 / (path.size() - 1)), core)
		if i % 2 == 0:   # a short branch
			var mid := c + (to - c) * p.rng.randf_range(0.4, 0.65)
			var tip := mid + p.polar(p.rng.randf_range(8.0, 14.0), a + p.rng.randf_range(0.5, 1.0) * (1.0 if p.rng.randf() < 0.5 else -1.0))
			p.stroke(mid.x, mid.y, tip.x, tip.y, 1.8, 0.6, core)
	if glowing:
		p.blob(c.x, c.y, 4.0, Color(0.012, 0.010, 0.016, 0.9), Color(0.5, 0.1, 0.9, 0.8), 6, 0.3, 1.5, 0.0)


static func _rubble(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.3, 0.28, 0.27))
	for i in 9 + v * 3:
		var q := c + p.polar(sqrt(p.rng.randf()) * 30.0, p.rng.randf() * TAU)
		var s := p.rng.randf_range(2.0, 5.5)
		var pts := PackedVector2Array()
		var n := 4 + p.rng.randi() % 2
		var a0 := p.rng.randf() * TAU
		for k in n:
			pts.append(q + p.polar(s * p.rng.randf_range(0.65, 1.1), a0 + TAU * k / n))
		var shadow := PackedVector2Array()
		for pt in pts:
			shadow.append(pt + Vector2(1.2, 1.4))
		p.convex(shadow, Color(0.01, 0.01, 0.015, 0.45), Color(0, 0, 0, 0), 1.0)
		var g := p.rng.randf_range(0.8, 1.25)
		p.convex(pts, Color(0.30, 0.28, 0.27, 0.95), Color(0, 0, 0, 0), 0.9, g)


static func _paper(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.8, 0.77, 0.66))
	for i in 3:
		var q := c + p.jitter(15.0)
		var receipt := (i == 0 and v == 1) or i == 2
		var w := 10.0 if receipt else p.rng.randf_range(20.0, 25.0)
		var h := 36.0 if receipt else p.rng.randf_range(24.0, 29.0)
		var a := p.rng.randf_range(-1.2, 1.2)
		p.rect(q.x + 1.8, q.y + 2.2, w, h, a, Color(0.01, 0.01, 0.015, 0.4))
		var tone := p.rng.randf_range(0.88, 1.06)
		p.rect(q.x, q.y, w, h, a, Color(0.80 * tone, 0.77 * tone, 0.66 * tone, 0.93))
		var lines := 8 if receipt else 4
		for k in lines:
			var ly := (float(k) - (lines - 1) * 0.5) * (h / (lines + 0.6))
			var l0 := Vector2(-w * 0.34, ly).rotated(a) + q
			var l1 := Vector2(w * 0.34 * p.rng.randf_range(0.5, 1.0), ly).rotated(a) + q
			p.stroke(l0.x, l0.y, l1.x, l1.y, 1.5, 1.5, Color(0.34, 0.34, 0.40, 0.7), Color(0, 0, 0, 0), 0.8)


static func _glass(p: Painter, c: Vector2) -> void:
	p.clear(Color(0.7, 0.86, 0.96))
	for i in 9:
		var q := c + p.polar(sqrt(p.rng.randf()) * 28.0, p.rng.randf() * TAU)
		var s := p.rng.randf_range(3.5, 9.0)
		var a0 := p.rng.randf() * TAU
		var pts := PackedVector2Array([q + p.polar(s, a0), q + p.polar(s * 0.55, a0 + 2.3), q + p.polar(s * 0.8, a0 + 4.0)])
		p.convex(pts, Color(0.72, 0.87, 0.97, 0.70), Color(0.45, 0.65, 0.85, 0.8), 0.9, p.rng.randf_range(0.8, 1.2))
	for i in 5:   # bright glints
		var q := c + p.polar(sqrt(p.rng.randf()) * 28.0, p.rng.randf() * TAU)
		p.blob(q.x, q.y, 1.9, Color(1, 1, 1, 0.95), Color(1.0, 1.0, 1.0, 1.0), 4, 0.1, 0.9, 0.0)


static func _wax(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.78, 0.68, 0.45))
	var body := Color(0.78, 0.67, 0.44, 0.88)
	if v == 0:
		p.blob(c.x, c.y, 15.0, body, Color(0, 0, 0, 0), 8, 0.3, 2.5, 0.1)
		p.blob(c.x + 12.0, c.y - 6.0, 8.0, body, Color(0, 0, 0, 0), 7, 0.3, 2.0, 0.1)
		for i in 3:
			var q := c + p.polar(p.rng.randf_range(20.0, 30.0), p.rng.randf() * TAU)
			p.blob(q.x, q.y, p.rng.randf_range(2.5, 4.5), body, Color(0, 0, 0, 0), 6, 0.2, 1.2, 0.1)
		p.blob(c.x - 3.0, c.y - 4.0, 5.0, Color(0.95, 0.88, 0.65, 0.6), Color(0, 0, 0, 0), 5, 0.2, 1.5, 0.0)
	else:
		for i in 6:
			var q := c + p.polar(sqrt(p.rng.randf()) * 24.0, p.rng.randf() * TAU)
			p.blob(q.x, q.y, p.rng.randf_range(3.0, 8.0), body, Color(0, 0, 0, 0), 6, 0.25, 1.6, 0.12)
		p.blob(c.x, c.y, 5.0, Color(0.93, 0.86, 0.68, 0.9), Color(0, 0, 0, 0), 6, 0.1, 1.2, 0.08)


static func _wine(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.32, 0.03, 0.07))
	var body := Color(0.34, 0.025, 0.07, 0.9)
	p.blob(c.x, c.y, 17.0 + v * 3.0, body, Color(0, 0, 0, 0), 8, 0.35, 3.0, 0.14)
	for i in 8:   # a splash: spokes ending in drops
		var a := p.rng.randf() * TAU
		var r0 := p.rng.randf_range(13.0, 18.0)
		var r1 := p.rng.randf_range(24.0, 35.0)
		p.stroke(c.x + cos(a) * r0, c.y + sin(a) * r0, c.x + cos(a) * r1, c.y + sin(a) * r1, 4.0, 1.2, body)
		var q := c + p.polar(r1 + 2.0, a)
		p.blob(q.x, q.y, p.rng.randf_range(1.8, 3.6), body, Color(0, 0, 0, 0), 5, 0.2, 1.0, 0.1)
	p.blob(c.x - 2.0, c.y - 2.0, 9.0, Color(0.56, 0.07, 0.15, 0.7), Color(0, 0, 0, 0), 7, 0.3, 2.5, 0.1)
	p.blob(c.x - 5.0, c.y - 6.0, 3.0, Color(0.9, 0.5, 0.55, 0.45), Color(0, 0, 0, 0), 5, 0.2, 1.2, 0.0)


static func _popcorn(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.92, 0.86, 0.62))
	var count := 6 + v * 2
	for i in count:
		var q := c + p.polar(sqrt(p.rng.randf()) * 27.0, p.rng.randf() * TAU)
		p.blob(q.x + 1.5, q.y + 2.0, 6.0, Color(0.01, 0.01, 0.015, 0.4), Color(0, 0, 0, 0), 6, 0.2, 1.4, 0.0)
		for k in 3:
			var o := q + p.polar(3.2, p.rng.randf() * TAU)
			p.blob(o.x, o.y, p.rng.randf_range(3.2, 4.6), Color(0.95, 0.90, 0.68, 0.96), Color(0, 0, 0, 0), 6, 0.22, 1.0, 0.1)
		p.blob(q.x + 1.0, q.y, 2.0, Color(0.96, 0.74, 0.24, 0.9), Color(0, 0, 0, 0), 5, 0.2, 0.8, 0.0)


static func _chalk(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.88, 0.9, 0.95))
	var strokes := 3 + v
	for i in strokes:   # broad dusty arcs
		var a0 := p.rng.randf() * TAU
		var r := p.rng.randf_range(10.0, 24.0)
		var span := p.rng.randf_range(0.8, 1.6)
		var prev := c + p.polar(r, a0)
		for k in range(1, 6):
			var q := c + p.polar(r + p.rng.randf_range(-2.0, 2.0), a0 + span * k / 5.0)
			p.stroke(prev.x, prev.y, q.x, q.y, 9.0, 8.0, Color(0.86, 0.89, 0.95, 0.46), Color(0, 0, 0, 0), 3.0)
			p.stroke(prev.x, prev.y, q.x, q.y, 4.0, 3.5, Color(0.97, 0.98, 1.0, 0.38), Color(0, 0, 0, 0), 2.0)
			prev = q
	for i in 10:
		var q := c + p.polar(sqrt(p.rng.randf()) * 32.0, p.rng.randf() * TAU)
		p.blob(q.x, q.y, p.rng.randf_range(1.0, 2.4), Color(0.9, 0.92, 0.97, 0.55), Color(0, 0, 0, 0), 5, 0.2, 1.0, 0.0)


static func _oil(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.02, 0.02, 0.03))
	p.blob(c.x, c.y, 24.0 + v * 2.0, Color(0.14, 0.15, 0.2, 0.36), Color(0, 0, 0, 0), 9, 0.3, 3.0, 0.06)
	p.blob(c.x, c.y, 21.0 + v * 2.0, Color(0.016, 0.016, 0.022, 0.9), Color(0, 0, 0, 0), 10, 0.33, 3.0, 0.12)
	for i in 3:   # cold sheen facets
		var q := c + p.polar(p.rng.randf_range(4.0, 12.0), p.rng.randf() * TAU)
		p.blob(q.x, q.y, p.rng.randf_range(4.0, 8.0), Color(0.12, 0.16, 0.26, 0.6), Color(0, 0, 0, 0), 4 + i, 0.3, 2.0, 0.2)
	for i in 3:
		var q := c + p.polar(p.rng.randf_range(26.0, 33.0), p.rng.randf() * TAU)
		p.blob(q.x, q.y, p.rng.randf_range(2.0, 4.0), Color(0.016, 0.016, 0.022, 0.9), Color(0, 0, 0, 0), 5, 0.2, 1.0, 0.1)


static func _rust(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.40, 0.09, 0.05))
	for i in 4:
		var q := c + p.polar(p.rng.randf_range(0.0, 16.0), p.rng.randf() * TAU)
		p.blob(q.x, q.y, p.rng.randf_range(8.0, 15.0), Color(0.40, 0.085, 0.05, 0.82), Color(0, 0, 0, 0), 7, 0.4, 2.5, 0.16)
	p.blob(c.x, c.y, 9.0, Color(0.22, 0.03, 0.025, 0.88), Color(0, 0, 0, 0), 7, 0.35, 2.0, 0.12)
	for i in 3 + v:   # drips running down the tile
		var x := c.x + p.rng.randf_range(-14.0, 14.0)
		p.stroke(x, c.y, x + p.rng.randf_range(-3.0, 3.0), c.y + p.rng.randf_range(18.0, 32.0), 3.2, 1.0, Color(0.36, 0.07, 0.045, 0.75))
	for i in 7:   # orange flakes
		var q := c + p.polar(sqrt(p.rng.randf()) * 30.0, p.rng.randf() * TAU)
		p.rect(q.x, q.y, p.rng.randf_range(2.0, 4.0), p.rng.randf_range(1.6, 3.0), p.rng.randf() * PI, Color(0.58, 0.22, 0.08, 0.85), Color(0, 0, 0, 0), 0.8)


static func _kernel(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(1.0, 0.82, 0.18))
	var a := p.rng.randf_range(-0.4, 0.4)
	var w := 22.0 + v * 3.0
	var h := 28.0
	var pts := PackedVector2Array()
	for s in [Vector2(-0.55, -1.0), Vector2(0.55, -1.0), Vector2(1.0, -0.2), Vector2(0.35, 1.0), Vector2(-0.35, 1.0), Vector2(-1.0, -0.2)]:
		pts.append(c + Vector2(s.x * w * 0.5, s.y * h * 0.5).rotated(a))
	var sh := PackedVector2Array()
	for pt in pts:
		sh.append(pt + Vector2(1.6, 2.2))
	p.convex(sh, Color(0.01, 0.01, 0.015, 0.45), Color(0, 0, 0, 0), 1.2)
	p.convex(pts, Color(0.98, 0.78, 0.14, 1.0), Color(0, 0, 0, 0), 1.0)
	var lower := PackedVector2Array([c + Vector2(-w * 0.5, 0.0).rotated(a), c + Vector2(w * 0.5, 0.0).rotated(a), c + Vector2(w * 0.17, h * 0.5).rotated(a), c + Vector2(-w * 0.17, h * 0.5).rotated(a)])
	p.convex(lower, Color(0.84, 0.56, 0.06, 0.8), Color(0, 0, 0, 0), 1.0)
	var top := PackedVector2Array([c + Vector2(-w * 0.28, -h * 0.45).rotated(a), c + Vector2(w * 0.28, -h * 0.45).rotated(a), c + Vector2(w * 0.12, -h * 0.1).rotated(a), c + Vector2(-w * 0.12, -h * 0.1).rotated(a)])
	p.convex(top, Color(1.0, 0.96, 0.6, 0.85), Color(0, 0, 0, 0), 1.0)


static func _tooth(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.95, 0.92, 0.78))
	var a := p.rng.randf_range(-0.6, 0.6)
	var s := 1.0 + 0.18 * v
	var crown := PackedVector2Array([Vector2(-11, -14), Vector2(11, -14), Vector2(13, -2), Vector2(7, 10), Vector2(0, 21), Vector2(-7, 10), Vector2(-13, -2)])
	var pts := PackedVector2Array()
	var sh := PackedVector2Array()
	for q in crown:
		pts.append(c + (q * s).rotated(a))
		sh.append(c + (q * s).rotated(a) + Vector2(1.6, 2.2))
	p.convex(sh, Color(0.01, 0.01, 0.015, 0.45), Color(0, 0, 0, 0), 1.2)
	p.convex(pts, Color(0.96, 0.93, 0.80, 1.0), Color(0, 0, 0, 0), 1.0)
	var shade := PackedVector2Array()
	for q in [Vector2(2, -14), Vector2(11, -14), Vector2(13, -2), Vector2(7, 10), Vector2(0, 21)]:
		shade.append(c + (q * s).rotated(a))
	p.convex(shade, Color(0.78, 0.72, 0.55, 0.75), Color(0, 0, 0, 0), 1.0)
	var hi := PackedVector2Array([c + (Vector2(-9, -12) * s).rotated(a), c + (Vector2(-2, -12) * s).rotated(a), c + (Vector2(-3, -3) * s).rotated(a), c + (Vector2(-9, -3) * s).rotated(a)])
	p.convex(hi, Color(1.0, 1.0, 0.95, 0.7), Color(0, 0, 0, 0), 1.0)


## A scorched ring (corn): a ragged dark annulus in faceted sectors.
static func _ring(p: Painter, c: Vector2) -> void:
	p.clear(Color(0.04, 0.03, 0.03))
	var sectors := 14
	var shades := PackedFloat32Array()
	var ph := PackedFloat32Array()
	for i in 4:
		ph.append(p.rng.randf() * TAU)
	for i in sectors:
		shades.append(1.0 + p.rng.randf_range(-0.2, 0.2))
	for y in p.n:
		for x in p.n:
			var dv := Vector2(float(x) + 0.5, float(y) + 0.5) - c
			var d := dv.length()
			if d < 20.0 or d > 40.0:
				continue
			var th := atan2(dv.y, dv.x)
			var wob := 2.2 * sin(th * 3.0 + ph[0]) + 1.6 * sin(th * 7.0 + ph[1])
			var r_mid := 30.0 + wob
			var w := 5.5 + 2.0 * sin(th * 5.0 + ph[2]) + 1.5 * sin(th * 2.0 + ph[3])
			var cov := clampf((w - absf(d - r_mid)) / 2.4, 0.0, 1.0)
			if cov <= 0.0:
				continue
			var sec := int(fposmod(th, TAU) / TAU * sectors) % sectors
			var col := Painter.shade(Color(0.04, 0.032, 0.03, 0.78 * cov), shades[sec])
			var glow := 0.0
			if absf(d - r_mid) < w * 0.35 and (x * 7 + y * 13) % 29 == 0:
				glow = 1.0
			p.put(x, y, col, Color(1.0, 0.45, 0.1, glow))
	for i in 6:
		var q := c + p.polar(p.rng.randf_range(26.0, 34.0), p.rng.randf() * TAU)
		p.blob(q.x, q.y, p.rng.randf_range(1.2, 2.2), Color(1.0, 0.5, 0.12, 0.8), Color(1.0, 0.42, 0.1, 1.0), 5, 0.2, 1.0, 0.0)


## A streak along the tile's X axis (scaled non-uniformly by the layer): an ichor drag mark.
static func _drag(p: Painter, v: int) -> void:
	var body := Color(0.24, 0.045, 0.42, 0.88)
	p.clear(Color(body.r, body.g, body.b))
	var y0 := 40.0
	var prev := Vector2(5.0, y0)
	var segs := 7
	for k in range(1, segs + 1):
		var t := float(k) / segs
		var q := Vector2(5.0 + 70.0 * t, y0 + 7.0 * sin(t * 5.0 + float(v) * 1.7) + p.rng.randf_range(-2.0, 2.0))
		var w0 := lerpf(26.0, 9.0, float(k - 1) / segs)
		var w1 := lerpf(26.0, 9.0, t)
		p.stroke(prev.x, prev.y, q.x, q.y, w0, w1, body, Color(0, 0, 0, 0), 3.0)
		p.stroke(prev.x, prev.y, q.x, q.y, w0 * 0.45, w1 * 0.45, Color(0.45, 0.14, 0.72, 0.75), Color(0.6, 0.16, 1.0, 0.9), 2.5)
		prev = q
	for i in 3:
		var q := Vector2(p.rng.randf_range(12.0, 70.0), y0 + p.rng.randf_range(-24.0, 24.0))
		if absf(q.y - y0) < 12.0:
			q.y += 14.0 * signf(q.y - y0 + 0.01)
		p.blob(q.x, q.y, p.rng.randf_range(2.0, 4.2), body, Color(0.6, 0.16, 1.0, 0.5), 5, 0.2, 1.0, 0.1)


static func _scuff(p: Painter, c: Vector2, v: int) -> void:
	p.clear(Color(0.66, 0.64, 0.6))
	var base := p.rng.randf() * PI
	for i in 3 + v:
		var off := p.rng.randf_range(-12.0, 12.0)
		var dir := Vector2(cos(base), sin(base))
		var side := Vector2(-dir.y, dir.x)
		var a := c + side * off - dir * p.rng.randf_range(14.0, 26.0)
		var b := c + side * off + dir * p.rng.randf_range(14.0, 26.0)
		p.stroke(a.x + 1.2, a.y + 1.2, b.x + 1.2, b.y + 1.2, 2.6, 2.0, Color(0.02, 0.02, 0.03, 0.30))
		p.stroke(a.x, a.y, b.x, b.y, 3.4, 1.4, Color(0.70, 0.68, 0.64, 0.42), Color(0, 0, 0, 0), 2.0)
	for i in 6:
		var q := c + p.polar(sqrt(p.rng.randf()) * 28.0, p.rng.randf() * TAU)
		p.blob(q.x, q.y, p.rng.randf_range(1.0, 2.2), Color(0.72, 0.70, 0.66, 0.45), Color(0, 0, 0, 0), 5, 0.2, 1.0, 0.0)


## A fresh monster death: a dark ichor splat thrown outward.
static func _stain(p: Painter, c: Vector2, v: int) -> void:
	var body := Color(0.19, 0.05, 0.32, 0.92)
	p.clear(Color(body.r, body.g, body.b))
	p.blob(c.x, c.y, 20.0 + v * 2.0, body, Color(0, 0, 0, 0), 9, 0.34, 3.5, 0.14)
	for i in 9:
		var a := p.rng.randf() * TAU
		var r0 := p.rng.randf_range(14.0, 20.0)
		var r1 := p.rng.randf_range(24.0, 36.0)
		p.stroke(c.x + cos(a) * r0, c.y + sin(a) * r0, c.x + cos(a) * r1, c.y + sin(a) * r1, 4.4, 1.0, body)
		var q := c + p.polar(r1 + 2.0, a)
		p.blob(q.x, q.y, p.rng.randf_range(1.6, 3.4), body, Color(0.45, 0.12, 0.8, 0.4), 5, 0.2, 1.0, 0.1)
	p.blob(c.x, c.y, 11.0, Color(0.34, 0.10, 0.54, 0.85), Color(0.5, 0.13, 0.9, 0.9), 7, 0.3, 2.5, 0.1)
	p.blob(c.x - 3.0, c.y - 4.0, 3.2, Color(0.7, 0.45, 0.95, 0.5), Color(0, 0, 0, 0), 5, 0.2, 1.2, 0.0)

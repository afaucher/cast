class_name ProtoTextures
extends RefCounted
## Procedural terrain textures: dark slate stone, wooden crates, warm stair planks.
## tools/make_proto_textures.gd writes these to assets/textures/proto/*.png; HexMapView
## loads the PNGs when present and falls back to make() otherwise.
##
## The ALPHA channel is a GLOW MASK (not transparency): HexMapView's terrain shader turns
## alpha into amber emission, which is how the vertical corner seams of cliff columns glow.
## Textures are opaque in every other respect.
##
## Slate tops (floor_top / wall_top) are seamlessly tileable and sampled with world-space
## UVs (one repeat = SLATE_PERIOD world units), so neighbouring tiles never look stamped.
## crate_top covers a 2x2 world-unit square centered on the hex (the hex edge sits at
## Hex.INNER from the center). Side textures are 1 world unit wide and one height LEVEL
## tall, so every repeat is exactly one level.

const DIR := "res://assets/textures/proto/"
const NAMES: Array[String] = [
	"floor_top", "wall_top", "stairs_top", "stairs_side", "cliff_side", "wall_side",
	"crate_top", "crate_side",
]
const SLATE_PERIOD := 4.0   ## world units per repeat of the slate top textures
const MIN_ALPHA := 0.004    ## keeps the import from touching RGB of "empty" glow pixels


static func make(tex_name: String) -> Image:
	match tex_name:
		"floor_top":
			return _slate_top(Color(0.235, 0.285, 0.375), 1)
		"wall_top":
			return _slate_top(Color(0.15, 0.175, 0.23), 2)
		"stairs_top":
			return _stairs_top()
		"stairs_side":
			return _side(Color(0.50, 0.31, 0.15), Color(0.17, 0.09, 0.04), 0.14, 32, 0.0)
		"cliff_side":
			return _side(Color(0.115, 0.135, 0.175), Color(0.04, 0.045, 0.06), 0.18, 0, 0.26)
		"wall_side":
			return _side(Color(0.10, 0.11, 0.145), Color(0.04, 0.042, 0.058), 0.15, 0, 0.12)
		"crate_top":
			return _crate_top()
		"crate_side":
			return _crate_side()
	return _slate_top(Color.MAGENTA, 3)


static func _hash(x: int, y: int) -> float:
	var h: int = (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## Smooth value noise on a lattice that wraps every `period` cells (so it tiles).
static func _vnoise(x: float, y: float, period: int, salt: int) -> float:
	var xi: int = floori(x)
	var yi: int = floori(y)
	var fx: float = x - xi
	var fy: float = y - yi
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var x0: int = posmod(xi, period) + salt * 131
	var x1: int = posmod(xi + 1, period) + salt * 131
	var y0: int = posmod(yi, period)
	var y1: int = posmod(yi + 1, period)
	var a: float = lerpf(_hash(x0, y0), _hash(x1, y0), fx)
	var b: float = lerpf(_hash(x0, y1), _hash(x1, y1), fx)
	return lerpf(a, b, fy)


static func _glow_px(col: Color, glow: float) -> Color:
	col.a = clampf(glow, MIN_ALPHA, 1.0)
	return col


## Seamless dark slate: big soft blotches, medium strata, fine grain, a few pale flecks.
static func _slate_top(base: Color, salt: int) -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u: float = float(x) / n
			var v: float = float(y) / n
			var f: float = 0.45 * _vnoise(u * 4.0, v * 4.0, 4, salt) \
				+ 0.30 * _vnoise(u * 8.0, v * 8.0, 8, salt + 1) \
				+ 0.17 * _vnoise(u * 16.0, v * 16.0, 16, salt + 2) \
				+ 0.08 * _vnoise(u * 32.0, v * 32.0, 32, salt + 3)
			var g: float = (_hash(x + salt * 17, y) - 0.5) * 0.10
			var k: float = 0.78 + 0.44 * f + g
			var col := Color(base.r * k, base.g * k, base.b * k * (1.0 + 0.05 * (f - 0.5)))
			if _hash(x * 3 + salt, y * 7) > 0.9993:
				col = col.lightened(0.35)   # tiny mineral fleck
			img.set_pixel(x, y, _glow_px(col, 0.0))
	return img


## Hexagonal "distance to the hex edge" for a point in the -1..1 square (>0 inside).
static func _hex_dist(ox: float, oz: float) -> float:
	var h := 0.0
	for j in 6:
		var a: float = deg_to_rad(60.0 * j)
		h = maxf(h, ox * cos(a) + oz * sin(a))
	return Hex.INNER - h


## Crate lid: a dark frame hugging the hex edge, nailed corners, light planks across.
static func _crate_top() -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var wood := Color(0.86, 0.68, 0.45)
	var frame := Color(0.34, 0.20, 0.10)
	var plank_w := 0.37
	for y in n:
		for x in n:
			var ox: float = ((x + 0.5) / n - 0.5) * 2.0
			var oz: float = ((y + 0.5) / n - 0.5) * 2.0
			var d: float = _hex_dist(ox, oz)
			var idx: int = floori((ox + 1.0) / plank_w)
			var local: float = fposmod(ox + 1.0, plank_w) / plank_w
			var shade: float = 0.86 + 0.28 * _hash(idx, 5)
			var grain: float = _vnoise(ox * 3.0 + idx * 7.0, oz * 22.0, 4096, 9)
			var col := Color(wood.r * shade, wood.g * shade, wood.b * shade)
			col = col.darkened(0.20 * grain)
			if local < 0.035 or local > 0.965:
				col = col.darkened(0.55)     # gap between planks
			elif local < 0.09:
				col = col.lightened(0.08)
			# frame
			if d < 0.20:
				col = frame.lightened(0.10 * _hash(x / 3, y / 3))
				if d > 0.165:
					col = col.darkened(0.45)     # inner shadow line
				elif d < 0.03:
					col = col.darkened(0.5)      # outer edge
			# nails near the corners
			for i in 6:
				var a: float = deg_to_rad(60.0 * i + 30.0)
				var cx: float = cos(a) * 0.80
				var cz: float = sin(a) * 0.80
				if Vector2(ox - cx, oz - cz).length() < 0.045:
					col = Color(0.16, 0.11, 0.08)
			img.set_pixel(x, y, _glow_px(col, 0.0))
	return img


## Side of one crate tier: two boards, dark corner posts, a diagonal brace, dark joint at the level line.
static func _crate_side() -> Image:
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wood := Color(0.80, 0.62, 0.40)
	var dark := Color(0.22, 0.12, 0.06)
	for y in h:
		for x in w:
			var board: int = 0 if y < 32 else 1
			var shade: float = 0.88 + 0.22 * _hash(board, 3)
			var grain: float = _vnoise(x / 28.0, y / 2.5, 4096, 4)
			var col := Color(wood.r * shade, wood.g * shade, wood.b * shade).darkened(0.22 * grain)
			# diagonal brace across the panel
			var diag: float = absf(float(y) - h * (float(x) - 9.0) / float(w - 18)) * 0.9
			if x >= 9 and x < w - 9 and diag < 5.5:
				col = col.darkened(0.18)
				if diag > 4.2:
					col = col.darkened(0.35)
			if y == 31 or y == 32 or y == 30:
				col = col.darkened(0.45)         # joint between the two boards
			if y < 2:
				col = col.lightened(0.10)
			if y >= h - 4:
				col = dark                        # level line
			elif y >= h - 6:
				col = col.darkened(0.30)
			if x < 9 or x >= w - 9:
				col = Color(0.30, 0.17, 0.08).lightened(0.12 * _hash(x, y / 4))
				if x == 8 or x == w - 9:
					col = dark
			img.set_pixel(x, y, _glow_px(col, 0.0))
	return img


## Stair tread: v=0 is the back (low side), v=1 the nosing at the front (high side).
static func _stairs_top() -> Image:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wood := Color(0.84, 0.58, 0.32)
	for y in h:
		for x in w:
			var col := wood.darkened(0.16 * _hash(x / 2, 7) + 0.10 * _vnoise(x / 9.0, y / 40.0, 4096, 6))
			if y >= 118:
				col = Color(0.36, 0.20, 0.09)                           # dark nosing
			elif y >= 100:
				col = col.lightened(0.14)                               # lit front lip
			if x < 3 or x >= w - 3:
				col = col.darkened(0.5)
			if y < 3:
				col = col.darkened(0.35)
			img.set_pixel(x, y, _glow_px(col, 0.0))
	return img


## Side tile: 1 world unit wide, ONE height level tall. Dark line at the level boundary.
## plank_px > 0 draws vertical plank joints every plank_px pixels (stairs).
## edge_glow > 0 puts a faint amber glow mask on the left / right edges (the column corners).
static func _side(base: Color, line: Color, noise: float, plank_px: int, edge_glow: float) -> Image:
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var strata: float = _vnoise(x / 20.0, y / 6.0, 4096, 2)
			var col := base.darkened(noise * (0.6 * strata + 0.4 * _hash(x / 4, y / 4)))
			col = col.lightened(0.12 * (1.0 - float(y) / h))            # top of the tile a bit brighter
			if y >= h - 3:
				col = line
			elif y >= h - 5:
				col = col.darkened(0.25)
			if y < 2:
				col = col.lightened(0.10)
			if plank_px > 0 and x % plank_px < 2:
				col = col.darkened(0.35)
			var glow := 0.0
			if edge_glow > 0.0:
				var e: float = minf(float(x), float(w - 1 - x)) / w   # 0 at the corner
				glow = edge_glow * exp(-pow(e / 0.05, 2.0))
				col = col.darkened(0.15 * glow)
			img.set_pixel(x, y, _glow_px(col, glow))
	return img

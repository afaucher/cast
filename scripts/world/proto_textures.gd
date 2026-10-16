class_name ProtoTextures
extends RefCounted
## Procedural "dev texture" images for the terrain (grid + outline + per-type color).
## tools/make_proto_textures.gd writes these to assets/textures/proto/*.png; HexMapView
## loads the PNGs when present and falls back to make() otherwise.
##
## Top textures cover a 2x2 world-unit square centered on the hex (so the hex
## outline sits exactly on the cell border). Side textures are 1 world unit wide
## and one height LEVEL tall, so every tile repeat is exactly one level.

const DIR := "res://assets/textures/proto/"
const NAMES: Array[String] = ["floor_top", "wall_top", "stairs_top", "stairs_side", "cliff_side", "wall_side"]


static func make(tex_name: String) -> Image:
	match tex_name:
		"floor_top":
			return _top(Color(0.86, 0.89, 0.96), Color(0.30, 0.34, 0.44), 0.06, 0.05)
		"wall_top":
			return _top(Color(0.30, 0.28, 0.33), Color(0.10, 0.09, 0.12), 0.05, 0.10)
		"stairs_top":
			return _stairs_top()
		"stairs_side":
			return _side(Color(0.62, 0.34, 0.14), Color(0.30, 0.15, 0.06), 0.10, 32)
		"cliff_side":
			return _side(Color(0.62, 0.56, 0.50), Color(0.22, 0.19, 0.17), 0.12, 0)
		"wall_side":
			return _side(Color(0.30, 0.28, 0.34), Color(0.10, 0.09, 0.12), 0.10, 0)
	return _top(Color.MAGENTA, Color.BLACK, 0.05, 0.0)


static func _hash(x: int, y: int) -> float:
	var h: int = (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## Hex top: base color, dark outline hugging the cell border, faint 0.5-unit dev grid, noise.
static func _top(base: Color, outline: Color, thick: float, noise: float) -> Image:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var inner := Hex.INNER
	for y in n:
		for x in n:
			var ox: float = ((x + 0.5) / n - 0.5) * 2.0
			var oz: float = ((y + 0.5) / n - 0.5) * 2.0
			# hexagonal "norm": max projection on the six edge normals (edge j faces 60*j degrees)
			var h := 0.0
			for j in 6:
				var a := deg_to_rad(60.0 * j)
				h = maxf(h, ox * cos(a) + oz * sin(a))
			var dist := inner - h  # >0 inside
			var col := base
			col = col.darkened(noise * (_hash(x / 4, y / 4) - 0.5) * 2.0 + 0.0)
			# faint dev grid every 0.5 world units
			var gx := absf(fposmod(ox + 0.25, 0.5) - 0.25)
			var gz := absf(fposmod(oz + 0.25, 0.5) - 0.25)
			if minf(gx, gz) < 0.012:
				col = col.darkened(0.07)
			# soft inner bevel just inside the outline
			if dist < thick * 2.2:
				col = col.darkened(0.10)
			var t := clampf((thick - dist) / 0.018 + 0.5, 0.0, 1.0)
			col = col.lerp(outline, t)
			col.a = 1.0
			img.set_pixel(x, y, col)
	return img


## Stair tread: v=0 is the back (low side), v=1 the nosing at the front (high side).
static func _stairs_top() -> Image:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wood := Color(0.92, 0.54, 0.20)
	for y in h:
		for x in w:
			var col := wood.darkened(0.12 * _hash(x / 2, 7))          # grain streaks along the tread depth
			if y >= 118:
				col = Color(0.42, 0.22, 0.08)                           # dark nosing
			elif y >= 100:
				col = col.lightened(0.12)                               # lit front lip
			if x < 3 or x >= w - 3:
				col = col.darkened(0.45)
			if y < 3:
				col = col.darkened(0.3)
			img.set_pixel(x, y, col)
	return img


## Side tile: 1 world unit wide, ONE height level tall. Dark line at the level boundary.
## plank_px > 0 draws vertical plank joints every plank_px pixels (stairs).
static func _side(base: Color, line: Color, noise: float, plank_px: int) -> Image:
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var col := base.darkened(noise * _hash(x / 8, y / 8))
			col = col.lightened(0.10 * (1.0 - float(y) / h))            # top of the tile a bit brighter
			if y >= h - 4:
				col = line
			elif y >= h - 6:
				col = col.darkened(0.25)
			if x < 2 or x >= w - 2:
				col = col.darkened(0.25)
			if plank_px > 0 and x % plank_px < 2:
				col = col.darkened(0.35)
			img.set_pixel(x, y, col)
	return img

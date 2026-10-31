extends RefCounted
## The haunted mansion's props (docs/design/mansion-rooms.md; the game's mansion rooms and antiques since
## haunted-build-plan.md H1, see HauntProps). Built through HauntProps.build(kind, params);
## the kit, the shared pieces (painting, candelabrum, candle, runner, ladder) and the colours are HauntProps'. No class_name
## (HauntProps preloads it). Each builder is `static func _<kind>(k: HauntProps.Kit, p: Dictionary)`; any variation (book
## colours, leaf angles) comes from p "seed", else GameWorld.fx_rng.
##
## Rooms and their signature pieces:
##   library        bookshelf, library_ladder, reading_chair, reading_table, globe, book_stack
##   gallery        portrait (p.v 0-4, p.big), gallery_screen, bust, rope_barrier, runner
##   ballroom       chandelier, grand_piano, gilt_chair, wall_mirror, candelabra
##   dining hall    dining_table (p.length), dining_chair, sideboard, fireplace
##   conservatory   planter_bed (where the parked garden's pollen beds could go), potted_palm, fern_stand, wardian_case,
##                  garden_bench, citrus_tub
##   any room       sconce, candelabra, runner


## kind -> {w, d, h, wall (back at z = -d / 2), flat (no outline), label}
const KINDS := {
	"bookshelf": {"w": 1.8, "d": 0.5, "h": 2.45, "wall": true, "label": "bookshelf"},
	"library_ladder": {"w": 0.6, "d": 0.9, "h": 2.45, "wall": false, "label": "library ladder"},
	"reading_chair": {"w": 0.95, "d": 0.9, "h": 1.25, "wall": false, "label": "wingback chair"},
	"reading_table": {"w": 1.3, "d": 0.75, "h": 1.1, "wall": false, "label": "reading table"},
	"globe": {"w": 0.65, "d": 0.65, "h": 1.15, "wall": false, "label": "globe"},
	"book_stack": {"w": 0.5, "d": 0.4, "h": 0.4, "wall": false, "label": "book stack"},
	"portrait": {"w": 0.95, "d": 0.14, "h": 1.45, "wall": true, "label": "portrait"},
	"gallery_screen": {"w": 2.2, "d": 0.4, "h": 2.3, "wall": false, "label": "gallery screen"},
	"bust": {"w": 0.55, "d": 0.55, "h": 1.65, "wall": false, "label": "bust on a plinth"},
	"rope_barrier": {"w": 2.4, "d": 0.2, "h": 0.95, "wall": false, "label": "rope barrier"},
	"runner": {"w": 6.0, "d": 1.4, "h": 0.03, "wall": false, "flat": true, "label": "runner"},
	"chandelier": {"w": 2.7, "d": 2.7, "h": 6.5, "wall": false, "label": "chandelier"},
	"medallion": {"w": 4.4, "d": 4.4, "h": 0.03, "wall": false, "flat": true, "label": "floor medallion"},
	"grand_piano": {"w": 1.5, "d": 2.5, "h": 1.95, "wall": false, "label": "grand piano"},
	"gilt_chair": {"w": 0.5, "d": 0.5, "h": 0.95, "wall": false, "label": "gilt chair"},
	"wall_mirror": {"w": 0.95, "d": 0.12, "h": 1.45, "wall": true, "label": "wall mirror"},
	"candelabra": {"w": 0.6, "d": 0.6, "h": 1.95, "wall": false, "label": "candelabra"},
	"sconce": {"w": 0.45, "d": 0.22, "h": 1.45, "wall": true, "label": "wall sconce"},
	"dining_table": {"w": 5.0, "d": 1.3, "h": 1.35, "wall": false, "label": "dining table"},
	"dining_chair": {"w": 0.55, "d": 0.55, "h": 1.35, "wall": false, "label": "dining chair"},
	"sideboard": {"w": 2.0, "d": 0.55, "h": 1.25, "wall": true, "label": "sideboard"},
	"fireplace": {"w": 2.0, "d": 0.75, "h": 1.5, "wall": true, "label": "fireplace"},
	"planter_bed": {"w": 2.6, "d": 1.3, "h": 1.1, "wall": false, "label": "planter bed"},
	"potted_palm": {"w": 2.1, "d": 2.1, "h": 2.4, "wall": false, "label": "potted palm"},
	"fern_stand": {"w": 0.8, "d": 0.8, "h": 1.4, "wall": false, "label": "fern stand"},
	"wardian_case": {"w": 1.1, "d": 0.65, "h": 1.6, "wall": false, "label": "glass plant case"},
	"garden_bench": {"w": 1.5, "d": 0.6, "h": 0.9, "wall": false, "label": "garden bench"},
	"citrus_tub": {"w": 0.9, "d": 0.9, "h": 1.9, "wall": false, "label": "orange tree"},
}


static func _rng(p: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(p.get("seed", GameWorld.fx_rng.randi()))
	return r


# --- library -----------------------------------------------------------------------------------------------------------

static func _bookshelf(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	var hw := 0.9
	k.box(Vector3(0.09, 2.3, 0.5), Vector3(-hw + 0.045, 1.15, 0), HauntProps.WALNUT)
	k.box(Vector3(0.09, 2.3, 0.5), Vector3(hw - 0.045, 1.15, 0), HauntProps.WALNUT)
	k.box(Vector3(hw * 2.0 - 0.18, 2.3, 0.04), Vector3(0, 1.15, -0.23), HauntProps.WALNUT_DK)
	k.box(Vector3(hw * 2.0 + 0.12, 0.1, 0.6), Vector3(0, 2.35, 0.02), HauntProps.WALNUT)
	k.box(Vector3(hw * 2.0 + 0.04, 0.06, 0.55), Vector3(0, 2.27, 0.01), HauntProps.WALNUT_DK)
	k.box(Vector3(hw * 2.0 + 0.02, 0.16, 0.54), Vector3(0, 0.08, 0.01), HauntProps.WALNUT_DK)
	var levels: Array[float] = [0.16, 0.6, 1.04, 1.48, 1.92]
	for y in levels:
		k.box(Vector3(hw * 2.0 - 0.18, 0.04, 0.46), Vector3(0, y - 0.02, 0), HauntProps.WALNUT)
		var x := -hw + 0.12
		while x < hw - 0.14:
			if r.randf() < 0.07:
				x += 0.1                                                 # a gap
				continue
			if r.randf() < 0.06 and x < hw - 0.4:                        # a lying stack
				for j in 3:
					k.box(Vector3(0.26, 0.05, 0.3), Vector3(x + 0.13, y + 0.025 + j * 0.05, -0.04), HauntProps.BOOKS[r.randi() % HauntProps.BOOKS.size()], Vector3(0, r.randf_range(-8, 8), 0))
				x += 0.3
				continue
			var bw := r.randf_range(0.05, 0.09)
			var bh := r.randf_range(0.26, 0.38)
			var col: Color = HauntProps.BOOKS[r.randi() % HauntProps.BOOKS.size()]
			var lean := 0.0
			if r.randf() < 0.05:
				lean = -14.0
			k.box(Vector3(bw, bh, 0.38), Vector3(x + bw * 0.5, y + bh * 0.5, -0.01), col.lightened(0.12), Vector3(0, 0, lean))
			if bw > 0.07 and r.randf() < 0.5:
				k.box(Vector3(bw + 0.004, 0.025, 0.02), Vector3(x + bw * 0.5, y + bh * 0.72, 0.185), HauntProps.GILT_DK)
			x += bw + 0.004


static func _library_ladder(k: HauntProps.Kit, _p: Dictionary) -> void:
	# leaning back against a shelf: the foot forward, the top hooked on a brass rail
	HauntProps.ladder(k, Vector3(0, 0.0, 0.42), Vector3(0, 2.3, -0.38), 0.48, HauntProps.OAK, 8)
	k.box(Vector3(0.62, 0.04, 0.05), Vector3(0, 2.36, -0.42), HauntProps.GILT)
	for sx in [-0.24, 0.24]:
		k.cyl(0.05, 0.05, 0.04, 6, Vector3(sx, 0.05, 0.42), HauntProps.GILT_DK, Vector3(0, 0, 90))
		k.rod(Vector3(sx, 2.3, -0.38), Vector3(sx, 2.4, -0.44), 0.03, 0.03, 4, HauntProps.GILT)


static func _reading_chair(k: HauntProps.Kit, p: Dictionary) -> void:
	var col: Color = p.get("color", HauntProps.LEATHER)
	for lx in [-0.36, 0.36]:
		for lz in [-0.32, 0.32]:
			k.cyl(0.04, 0.03, 0.14, 5, Vector3(lx, 0.07, lz), HauntProps.WALNUT_DK)
	k.box(Vector3(0.9, 0.3, 0.8), Vector3(0, 0.29, 0), col)
	k.box(Vector3(0.62, 0.12, 0.62), Vector3(0, 0.49, 0.07), col.lightened(0.08))
	k.box(Vector3(0.9, 0.85, 0.18), Vector3(0, 0.82, -0.32), col)
	k.ball(Vector3(0.45, 0.12, 0.1), Vector3(0, 1.2, -0.32), col, 0, 0.0)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.14, 0.32, 0.72), Vector3(sx * 0.38, 0.6, 0.02), col)
		k.ball(Vector3(0.09, 0.09, 0.36), Vector3(sx * 0.4, 0.78, 0.04), col, 0, 0.0)
		k.box(Vector3(0.12, 0.6, 0.3), Vector3(sx * 0.42, 1.02, -0.2), col, Vector3(0, sx * -12.0, 0))
	for i in 5:
		k.ball(Vector3(0.025, 0.025, 0.02), Vector3(-0.3 + i * 0.15, 0.95, -0.22), HauntProps.GILT_DK, 0, 0.0)


static func _reading_table(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	k.box(Vector3(1.3, 0.06, 0.75), Vector3(0, 0.75, 0), HauntProps.WALNUT)
	k.box(Vector3(1.18, 0.12, 0.62), Vector3(0, 0.66, 0), HauntProps.WALNUT_DK)
	for lx in [-0.56, 0.56]:
		for lz in [-0.28, 0.28]:
			k.cyl(0.035, 0.05, 0.62, 6, Vector3(lx, 0.31, lz), HauntProps.WALNUT_DK)
			k.ball(Vector3(0.06, 0.06, 0.06), Vector3(lx, 0.3, lz), HauntProps.WALNUT, 0, 0.0)
	# an open book with blank pages, a closed one beside it
	k.box(Vector3(0.5, 0.02, 0.36), Vector3(-0.1, 0.79, 0.05), HauntProps.LEATHER)
	k.box(Vector3(0.23, 0.035, 0.32), Vector3(-0.22, 0.81, 0.05), HauntProps.LINEN, Vector3(0, 0, -5))
	k.box(Vector3(0.23, 0.035, 0.32), Vector3(0.02, 0.81, 0.05), HauntProps.LINEN, Vector3(0, 0, 5))
	k.box(Vector3(0.3, 0.07, 0.22), Vector3(0.38, 0.815, -0.15), HauntProps.BOOKS[r.randi() % HauntProps.BOOKS.size()], Vector3(0, 20, 0))
	HauntProps.candlestick(k, Vector3(0.45, 0.78, 0.18))


static func _globe(k: HauntProps.Kit, _p: Dictionary) -> void:
	for i in 3:
		var a := TAU * float(i) / 3.0
		k.rod(Vector3(cos(a) * 0.26, 0.0, sin(a) * 0.26), Vector3(cos(a) * 0.06, 0.45, sin(a) * 0.06), 0.03, 0.025, 4, HauntProps.WALNUT)
	k.cyl(0.1, 0.07, 0.12, 8, Vector3(0, 0.5, 0), HauntProps.WALNUT_DK)
	k.rod(Vector3(0, 0.55, 0), Vector3(0, 0.62, 0), 0.025, 0.025, 4, HauntProps.GILT)
	var c := Vector3(0, 0.85, 0)
	k.ball(Vector3(0.26, 0.26, 0.26), c, Color(0.32, 0.48, 0.55), 1, 0.0)
	k.ball(Vector3(0.12, 0.14, 0.06), c + Vector3(0.1, 0.06, 0.2), Color(0.66, 0.58, 0.36), 0, 0.0)
	k.ball(Vector3(0.1, 0.08, 0.06), c + Vector3(-0.16, -0.08, 0.17), Color(0.66, 0.58, 0.36), 0, 0.0)
	# the brass meridian: an arc of short rods round the ball
	var prev := c + Vector3(0, -0.31, 0)
	for i in range(1, 9):
		var a := PI * float(i) / 8.0
		var q := c + Vector3(sin(a) * 0.31 * 0.5, -cos(a) * 0.31, -sin(a) * 0.31 * 0.866)
		k.rod(prev, q, 0.018, 0.018, 4, HauntProps.GILT)
		prev = q


static func _book_stack(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	var y := 0.0
	for i in 5:
		var t := r.randf_range(0.05, 0.09)
		k.box(Vector3(r.randf_range(0.3, 0.42), t, r.randf_range(0.24, 0.3)), Vector3(r.randf_range(-0.03, 0.03), y + t * 0.5, 0), HauntProps.BOOKS[r.randi() % HauntProps.BOOKS.size()], Vector3(0, r.randf_range(-25, 25), 0))
		y += t


# --- portrait gallery -------------------------------------------------------------------------------------------------

## A wall portrait: p.v the picture (HauntProps.painting), p.big the tall frame.
static func _portrait(k: HauntProps.Kit, p: Dictionary) -> void:
	var big := bool(p.get("big", false))
	var w := 1.0 if big else 0.82
	var h := 1.22 if big else 0.98
	var y0 := 0.2 if big else 0.42
	HauntProps.painting(k, int(p.get("v", 0)), w, h, y0, -0.07)
	# the hanging cord and its rail hook above
	k.rod(Vector3(-0.2, y0 + h, -0.05), Vector3(0, 1.44, -0.06), 0.012, 0.012, 3, HauntProps.GILT_DK)
	k.rod(Vector3(0.2, y0 + h, -0.05), Vector3(0, 1.44, -0.06), 0.012, 0.012, 3, HauntProps.GILT_DK)


## A free-standing display screen: a velvet-covered panel in a walnut frame, a portrait on each face.
static func _gallery_screen(k: HauntProps.Kit, p: Dictionary) -> void:
	var col: Color = p.get("color", Color(0.36, 0.07, 0.09))
	for sx in [-1.06, 1.06]:
		k.box(Vector3(0.1, 2.2, 0.16), Vector3(sx, 1.1, 0), HauntProps.WALNUT)
		k.box(Vector3(0.14, 0.06, 0.4), Vector3(sx, 0.03, 0), HauntProps.WALNUT_DK)
		k.ball(Vector3(0.07, 0.07, 0.07), Vector3(sx, 2.25, 0), HauntProps.GILT, 0, 0.0)
	k.box(Vector3(2.02, 2.0, 0.08), Vector3(0, 1.15, 0), col)
	k.box(Vector3(2.1, 0.08, 0.14), Vector3(0, 2.17, 0), HauntProps.WALNUT)
	k.box(Vector3(2.1, 0.08, 0.14), Vector3(0, 0.13, 0), HauntProps.WALNUT)
	HauntProps.painting(k, int(p.get("v", 1)), 1.0, 1.25, 0.6, 0.04)
	HauntProps.painting(k, int(p.get("v2", 2)), 1.0, 1.25, 0.6, -0.04, 0.0, true)


static func _bust(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(0.5, 0.1, 0.5), Vector3(0, 0.05, 0), HauntProps.MARBLE_DK)
	k.cyl(0.2, 0.18, 0.86, 8, Vector3(0, 0.53, 0), HauntProps.MARBLE)
	k.box(Vector3(0.46, 0.08, 0.46), Vector3(0, 1.0, 0), HauntProps.MARBLE_DK)
	k.cyl(0.11, 0.14, 0.08, 8, Vector3(0, 1.08, 0), HauntProps.MARBLE)
	k.frus(Vector2(0.42, 0.22), Vector2(0.18, 0.14), 0.24, Vector3(0, 1.24, 0), HauntProps.MARBLE)
	k.cyl(0.06, 0.06, 0.1, 6, Vector3(0, 1.39, 0), HauntProps.MARBLE)
	k.ball(Vector3(0.12, 0.15, 0.13), Vector3(0, 1.53, 0.01), HauntProps.MARBLE, 1, 0.05)
	k.ball(Vector3(0.12, 0.06, 0.12), Vector3(0, 1.63, -0.02), HauntProps.MARBLE_DK, 0, 0.0)
	k.box(Vector3(0.04, 0.06, 0.05), Vector3(0, 1.52, 0.13), HauntProps.MARBLE)


static func _rope_barrier(k: HauntProps.Kit, p: Dictionary) -> void:
	var length := float(p.get("length", 2.4))
	var posts := 2 if length < 3.2 else 3
	var xs: Array[float] = []
	for i in posts:
		xs.append(-length * 0.5 + length * float(i) / float(posts - 1))
	for x in xs:
		k.cyl(0.13, 0.13, 0.04, 8, Vector3(x, 0.02, 0), HauntProps.GILT_DK)
		k.cyl(0.03, 0.03, 0.85, 6, Vector3(x, 0.46, 0), HauntProps.GILT)
		k.ball(Vector3(0.06, 0.06, 0.06), Vector3(x, 0.92, 0), HauntProps.GILT, 0, 0.0)
	for i in posts - 1:
		var a := Vector3(xs[i], 0.84, 0)
		var b := Vector3(xs[i + 1], 0.84, 0)
		var prev := a
		for j in range(1, 7):
			var t := float(j) / 6.0
			var q := a.lerp(b, t) + Vector3(0, -0.22 * sin(PI * t), 0)
			k.rod(prev, q, 0.035, 0.035, 5, HauntProps.VELVET)
			prev = q


static func _runner(k: HauntProps.Kit, p: Dictionary) -> void:
	HauntProps.runner(k, float(p.get("length", 6.0)), float(p.get("width", 1.4)), p.get("color", Color(0.38, 0.08, 0.1)), p.get("border", Color(0.62, 0.45, 0.2)))


# --- ballroom ----------------------------------------------------------------------------------------------------------

## A chandelier hung from the dark above: the chain from y 6.5 to its crown, two rings of candle arms round a gilt column,
## crystal drops.
static func _chandelier(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.flame_k = 1.4
	var top := 3.95
	for i in 7:
		var y := 6.5 - float(i) * 0.37
		k.box(Vector3(0.05, 0.3, 0.12), Vector3(0, y - 0.15, 0), HauntProps.GILT_DK, Vector3(0, 90.0 * float(i % 2), 0))
	k.cyl(0.26, 0.08, 0.22, 8, Vector3(0, top, 0), HauntProps.GILT)
	k.cyl(0.08, 0.08, 0.8, 6, Vector3(0, top - 0.48, 0), HauntProps.GILT)
	k.ball(Vector3(0.26, 0.2, 0.26), Vector3(0, top - 0.62, 0), HauntProps.GILT, 0, 0.0)
	k.cyl(0.05, 0.26, 0.3, 8, Vector3(0, top - 0.95, 0), HauntProps.GILT_DK)
	k.ball(Vector3(0.12, 0.2, 0.12), Vector3(0, top - 1.18, 0), HauntProps.CRYSTAL, 0, 0.0)
	# the crystal basket under the lower ring
	for i in 10:
		var a := TAU * float(i) / 10.0
		k.rod(Vector3(cos(a) * 1.0, top - 0.86, sin(a) * 1.0), Vector3(0, top - 1.12, 0), 0.016, 0.016, 3, HauntProps.CRYSTAL)
	var rings := [[10, 1.25, top - 0.8], [6, 0.7, top - 0.36]]
	for ring: Array in rings:
		var n: int = ring[0]
		var rad: float = ring[1]
		var y: float = ring[2]
		var prev := Vector3.ZERO
		for i in n:
			var a := TAU * (float(i) + 0.5) / float(n)
			var tip := Vector3(cos(a) * rad, y, sin(a) * rad)
			k.rod(Vector3(0, y - 0.1, 0), Vector3(cos(a) * rad * 0.5, y - 0.2, sin(a) * rad * 0.5), 0.035, 0.035, 4, HauntProps.GILT)
			k.rod(Vector3(cos(a) * rad * 0.5, y - 0.2, sin(a) * rad * 0.5), tip, 0.035, 0.035, 4, HauntProps.GILT)
			k.cyl(0.08, 0.05, 0.06, 6, tip + Vector3(0, 0.03, 0), HauntProps.GILT)
			k.candle(tip + Vector3(0, 0.06, 0), 0.2, 0.034)
			# a drop of crystal under each arm, a swag between them
			k.ball(Vector3(0.05, 0.1, 0.05), tip + Vector3(0, -0.15, 0), HauntProps.CRYSTAL, 0, 0.0)
			var mid := (prev + tip) * 0.5 + Vector3(0, -0.18, 0)
			if i > 0:
				k.rod(prev + Vector3(0, -0.02, 0), mid, 0.018, 0.018, 3, HauntProps.CRYSTAL)
				k.rod(mid, tip + Vector3(0, -0.02, 0), 0.018, 0.018, 3, HauntProps.CRYSTAL)
			prev = tip
		var first := Vector3(cos(TAU * 0.5 / float(n)) * rad, y, sin(TAU * 0.5 / float(n)) * rad)
		var close_mid := (prev + first) * 0.5 + Vector3(0, -0.18, 0)
		k.rod(prev + Vector3(0, -0.02, 0), close_mid, 0.018, 0.018, 3, HauntProps.CRYSTAL)
		k.rod(close_mid, first + Vector3(0, -0.02, 0), 0.018, 0.018, 3, HauntProps.CRYSTAL)


## A parquet medallion let into the ballroom floor under the chandelier (a flat decal): rings of light and dark wood round
## an eight-pointed star.
static func _medallion(k: HauntProps.Kit, p: Dictionary) -> void:
	var rad := float(p.get("radius", 2.1))
	var light := Color(0.78, 0.6, 0.36)
	var dark := Color(0.2, 0.1, 0.05)
	k.cyl(rad, rad, 0.012, 24, Vector3(0, 0.006, 0), dark)
	k.cyl(rad - 0.1, rad - 0.1, 0.016, 24, Vector3(0, 0.008, 0), light)
	k.cyl(rad - 0.26, rad - 0.26, 0.02, 24, Vector3(0, 0.01, 0), Color(0.42, 0.24, 0.12))
	k.cyl(rad * 0.62, rad * 0.62, 0.024, 24, Vector3(0, 0.012, 0), dark)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var tip := Vector3(cos(a), 0, sin(a)) * (rad - 0.34)
		var side := Vector3(-sin(a), 0, cos(a)) * rad * 0.16
		var y := 0.03
		var col := light if i % 2 == 0 else Color(0.62, 0.42, 0.22)
		k.s.add_tri(Vector3(0, y, 0) + side, tip + Vector3(0, y, 0), Vector3(0, y, 0) - side, col)
	k.cyl(rad * 0.14, rad * 0.14, 0.034, 12, Vector3(0, 0.017, 0), dark)


## A convex prism from (x, z) points between y0 and y1, merged into the body (built centred, so it winds outward).
static func _prism(k: HauntProps.Kit, pts: Array[Vector2], y0: float, y1: float, col: Color, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var c := Vector2.ZERO
	for q in pts:
		c += q
	c /= float(pts.size())
	var hy := (y1 - y0) * 0.5
	var s := LowPoly.Soup.new(PropModels._n(), 0.05)
	for i in pts.size():
		var a := pts[i] - c
		var b := pts[(i + 1) % pts.size()] - c
		s.add_quad(Vector3(a.x, -hy, a.y), Vector3(b.x, -hy, b.y), Vector3(b.x, hy, b.y), Vector3(a.x, hy, a.y), col)
		s.add_tri(Vector3(0, hy, 0), Vector3(a.x, hy, a.y), Vector3(b.x, hy, b.y), col)
		s.add_tri(Vector3(0, -hy, 0), Vector3(b.x, -hy, b.y), Vector3(a.x, -hy, a.y), col)
	k.s.merge(s, xf * Transform3D(Basis.IDENTITY, Vector3(c.x, y0 + hy, c.y)))


static func _grand_piano(k: HauntProps.Kit, _p: Dictionary) -> void:
	# the case in plan: the keyboard side at +z, the straight spine at -x, the bentside curving in to the tail at -z
	var outline: Array[Vector2] = [Vector2(-0.72, 0.62), Vector2(0.72, 0.62), Vector2(0.72, 0.1), Vector2(0.55, -0.35),
		Vector2(0.28, -0.85), Vector2(0.05, -1.08), Vector2(-0.72, -1.08)]
	_prism(k, outline, 0.62, 0.98, HauntProps.PIANO_BLACK)
	_prism(k, outline, 0.6, 0.64, Color(0.12, 0.11, 0.12))
	# the lid, propped open on the spine's hinge
	var lid := Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-38.0)), Vector3(-0.72, 0.99, 0)) * Transform3D(Basis.IDENTITY, Vector3(0.72, 0, 0))
	var lid_pts: Array[Vector2] = []
	for q in outline:
		lid_pts.append(Vector2(q.x, q.y))
	_prism(k, lid_pts, 0.0, 0.03, Color(0.1, 0.095, 0.11), lid)
	k.rod(Vector3(0.45, 0.98, -0.2), Vector3(0.38, 1.48, -0.2), 0.015, 0.015, 3, HauntProps.GILT_DK)
	# keyboard, keys, music desk
	k.box(Vector3(1.44, 0.1, 0.3), Vector3(0, 0.8, 0.76), HauntProps.PIANO_BLACK)
	k.box(Vector3(1.3, 0.04, 0.2), Vector3(0, 0.865, 0.78), Color(0.93, 0.91, 0.84))
	for i in 18:
		if i % 7 == 2 or i % 7 == 6:
			continue
		k.box(Vector3(0.035, 0.03, 0.11), Vector3(-0.6 + i * 0.07, 0.895, 0.73), Color(0.06, 0.06, 0.06))
	k.box(Vector3(0.7, 0.24, 0.03), Vector3(0, 1.1, 0.58), HauntProps.PIANO_BLACK, Vector3(-15, 0, 0))
	# legs and the pedal lyre
	for lp in [Vector3(-0.62, 0.3, 0.52), Vector3(0.62, 0.3, 0.52), Vector3(-0.5, 0.3, -0.92)]:
		k.cyl(0.07, 0.05, 0.6, 6, lp, HauntProps.PIANO_BLACK)
		k.cyl(0.05, 0.05, 0.05, 6, lp - Vector3(0, 0.28, 0), HauntProps.GILT_DK)
	k.box(Vector3(0.18, 0.5, 0.06), Vector3(0, 0.33, 0.45), HauntProps.PIANO_BLACK)
	k.box(Vector3(0.22, 0.03, 0.1), Vector3(0, 0.06, 0.5), HauntProps.GILT)
	# the bench
	k.box(Vector3(0.8, 0.1, 0.36), Vector3(0, 0.5, 1.2), HauntProps.PIANO_BLACK)
	k.box(Vector3(0.74, 0.04, 0.3), Vector3(0, 0.57, 1.2), HauntProps.LEATHER)
	for lx in [-0.34, 0.34]:
		for lz in [1.06, 1.34]:
			k.cyl(0.03, 0.025, 0.45, 5, Vector3(lx, 0.225, lz), HauntProps.PIANO_BLACK)


static func _gilt_chair(k: HauntProps.Kit, p: Dictionary) -> void:
	var col: Color = p.get("color", HauntProps.VELVET)
	for lx in [-0.2, 0.2]:
		for lz in [-0.18, 0.18]:
			k.cyl(0.025, 0.02, 0.45, 5, Vector3(lx, 0.225, lz), HauntProps.GILT)
	k.box(Vector3(0.48, 0.06, 0.46), Vector3(0, 0.46, 0), HauntProps.GILT_DK)
	k.box(Vector3(0.42, 0.06, 0.4), Vector3(0, 0.51, 0.01), col)
	for sx in [-0.19, 0.19]:
		k.rod(Vector3(sx, 0.46, -0.2), Vector3(sx * 0.9, 0.95, -0.24), 0.022, 0.022, 4, HauntProps.GILT)
	k.box(Vector3(0.36, 0.32, 0.04), Vector3(0, 0.74, -0.225), col, Vector3(-6, 0, 0))
	k.box(Vector3(0.42, 0.05, 0.05), Vector3(0, 0.93, -0.24), HauntProps.GILT)


## A tall wall mirror: a gilt frame round a silvered glass.
static func _wall_mirror(k: HauntProps.Kit, _p: Dictionary) -> void:
	var w := 0.9
	var h := 1.28
	var y0 := 0.14
	k.box(Vector3(w - 0.12, h - 0.12, 0.03), Vector3(0, y0 + h * 0.5, -0.045), Color(0.55, 0.62, 0.66))
	k.glass_box(Vector3(w - 0.14, h - 0.14, 0.01), Vector3(0, y0 + h * 0.5, -0.025))
	k.box(Vector3(w, 0.1, 0.08), Vector3(0, y0 + 0.05, -0.02), HauntProps.GILT)
	k.box(Vector3(w, 0.1, 0.08), Vector3(0, y0 + h - 0.05, -0.02), HauntProps.GILT)
	k.box(Vector3(0.1, h, 0.08), Vector3(-w * 0.5 + 0.05, y0 + h * 0.5, -0.02), HauntProps.GILT)
	k.box(Vector3(0.1, h, 0.08), Vector3(w * 0.5 - 0.05, y0 + h * 0.5, -0.02), HauntProps.GILT)
	k.ball(Vector3(0.16, 0.1, 0.05), Vector3(0, y0 + h + 0.04, -0.02), HauntProps.GILT_DK, 0, 0.0)


## A standing candelabrum (floor), five candles at the top.
static func _candelabra(k: HauntProps.Kit, _p: Dictionary) -> void:
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		k.rod(Vector3(0, 0.22, 0), Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.22), 0.03, 0.02, 4, HauntProps.GILT_DK)
	k.cyl(0.05, 0.035, 1.3, 6, Vector3(0, 0.85, 0), HauntProps.GILT)
	k.ball(Vector3(0.07, 0.07, 0.07), Vector3(0, 0.6, 0), HauntProps.GILT_DK, 0, 0.0)
	HauntProps.candelabrum(k, Vector3(0, 1.45, 0), 0.2, HauntProps.GILT)


## Two candles on a brass wall plate.
static func _sconce(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(0.16, 0.36, 0.04), Vector3(0, 1.12, -0.09), HauntProps.GILT_DK)
	k.ball(Vector3(0.07, 0.07, 0.03), Vector3(0, 1.12, -0.06), HauntProps.GILT, 0, 0.0)
	for sx in [-0.16, 0.16]:
		k.rod(Vector3(0, 1.06, -0.07), Vector3(sx, 1.08, 0.04), 0.02, 0.02, 4, HauntProps.GILT)
		k.cyl(0.05, 0.035, 0.04, 6, Vector3(sx, 1.1, 0.04), HauntProps.GILT)
		k.candle(Vector3(sx, 1.12, 0.04), 0.16, 0.026)


# --- dining hall -------------------------------------------------------------------------------------------------------

static func _dining_table(k: HauntProps.Kit, p: Dictionary) -> void:
	var length := float(p.get("length", 5.0))
	var hl := length * 0.5
	k.box(Vector3(length, 0.07, 1.3), Vector3(0, 0.76, 0), HauntProps.WALNUT)
	k.box(Vector3(length - 0.2, 0.12, 1.12), Vector3(0, 0.67, 0), HauntProps.WALNUT_DK)
	var legs := 3 if length > 3.5 else 2
	for i in legs:
		var lx := -hl + 0.25 + (length - 0.5) * float(i) / float(legs - 1)
		for lz in [-0.5, 0.5]:
			k.cyl(0.05, 0.07, 0.62, 6, Vector3(lx, 0.31, lz), HauntProps.WALNUT_DK)
			k.ball(Vector3(0.09, 0.1, 0.09), Vector3(lx, 0.36, lz), HauntProps.WALNUT, 0, 0.0)
	k.box(Vector3(length - 0.3, 0.012, 0.42), Vector3(0, 0.8, 0), HauntProps.LINEN)
	# place settings along both sides, candelabra down the middle
	var seats := int(floor((length - 0.6) / 0.85))
	for i in seats:
		var sx := -hl + 0.3 + 0.425 + float(i) * 0.85
		for sz in [-0.42, 0.42]:
			k.cyl(0.15, 0.15, 0.015, 8, Vector3(sx, 0.805, sz), HauntProps.LINEN.lightened(0.05))
			k.cyl(0.08, 0.08, 0.02, 8, Vector3(sx, 0.82, sz), Color(0.75, 0.72, 0.62))
			k.cyl(0.03, 0.04, 0.12, 5, Vector3(sx + 0.17, 0.86, sz * 0.75), HauntProps.SILVER)
	var n_c := 3 if length > 3.5 else 1
	for i in n_c:
		var cx := 0.0 if n_c == 1 else -hl * 0.6 + hl * 1.2 * float(i) / float(n_c - 1)
		HauntProps.candelabrum(k, Vector3(cx, 0.8, 0), 0.42, HauntProps.SILVER, 5 if i == 1 or n_c == 1 else 3)


static func _dining_chair(k: HauntProps.Kit, p: Dictionary) -> void:
	var col: Color = p.get("color", HauntProps.VELVET)
	for lx in [-0.22, 0.22]:
		for lz in [-0.2, 0.2]:
			k.cyl(0.03, 0.025, 0.46, 5, Vector3(lx, 0.23, lz), HauntProps.WALNUT_DK)
	k.box(Vector3(0.54, 0.07, 0.5), Vector3(0, 0.48, 0), HauntProps.WALNUT)
	k.box(Vector3(0.48, 0.06, 0.44), Vector3(0, 0.53, 0.02), col)
	for sx in [-0.23, 0.23]:
		k.box(Vector3(0.06, 0.82, 0.06), Vector3(sx, 0.9, -0.23), HauntProps.WALNUT)
		k.ball(Vector3(0.045, 0.06, 0.045), Vector3(sx, 1.34, -0.23), HauntProps.WALNUT_DK, 0, 0.0)
	k.box(Vector3(0.4, 0.5, 0.04), Vector3(0, 0.88, -0.23), col)
	k.frus(Vector2(0.52, 0.07), Vector2(0.3, 0.07), 0.16, Vector3(0, 1.26, -0.23), HauntProps.WALNUT)


static func _sideboard(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(2.0, 0.08, 0.55), Vector3(0, 0.9, 0), HauntProps.WALNUT)
	k.box(Vector3(1.9, 0.72, 0.48), Vector3(0, 0.5, -0.02), HauntProps.WALNUT_DK)
	for i in 3:
		var x := -0.62 + 0.62 * i
		k.box(Vector3(0.56, 0.56, 0.03), Vector3(x, 0.48, 0.225), HauntProps.WALNUT)
		k.ball(Vector3(0.03, 0.03, 0.02), Vector3(x + 0.18, 0.5, 0.25), HauntProps.GILT, 0, 0.0)
	for lx in [-0.9, 0.9]:
		k.cyl(0.05, 0.04, 0.14, 6, Vector3(lx, 0.07, 0.15), HauntProps.WALNUT_DK)
	# a silver tureen and a pair of candlesticks
	k.cyl(0.18, 0.13, 0.04, 8, Vector3(0, 0.96, 0), HauntProps.SILVER)
	k.ball(Vector3(0.2, 0.13, 0.15), Vector3(0, 1.07, 0), HauntProps.SILVER, 1, 0.0)
	k.ball(Vector3(0.04, 0.05, 0.04), Vector3(0, 1.21, 0), HauntProps.SILVER, 0, 0.0)
	HauntProps.candlestick(k, Vector3(-0.7, 0.94, 0.0), HauntProps.SILVER)
	HauntProps.candlestick(k, Vector3(0.7, 0.94, 0.0), HauntProps.SILVER)


## A marble fireplace: jambs, a mantel shelf with a clock and candlesticks, a dark firebox with logs and a fire (the fire is
## a candle cluster: out in moonlight).
static func _fireplace(k: HauntProps.Kit, _p: Dictionary) -> void:
	var back := -0.375
	k.box(Vector3(1.9, 1.12, 0.3), Vector3(0, 0.56, back + 0.15), HauntProps.MARBLE_DK)
	k.box(Vector3(0.95, 0.7, 0.04), Vector3(0, 0.38, back + 0.31), Color(0.05, 0.04, 0.04))
	for sx in [-0.67, 0.67]:
		k.box(Vector3(0.38, 1.1, 0.34), Vector3(sx, 0.55, back + 0.18), HauntProps.MARBLE)
	k.box(Vector3(1.1, 0.34, 0.34), Vector3(0, 0.93, back + 0.18), HauntProps.MARBLE)
	k.box(Vector3(2.1, 0.08, 0.46), Vector3(0, 1.14, back + 0.21), HauntProps.MARBLE)
	k.box(Vector3(1.6, 0.12, 0.42), Vector3(0, 1.05, back + 0.2), HauntProps.MARBLE_DK)
	k.box(Vector3(2.0, 0.05, 0.4), Vector3(0, 0.025, back + 0.55), HauntProps.MARBLE_DK)
	# grate and logs
	k.box(Vector3(0.7, 0.04, 0.22), Vector3(0, 0.12, back + 0.35), HauntProps.IRON)
	for sx in [-0.3, 0.3]:
		k.cyl(0.025, 0.025, 0.12, 4, Vector3(sx, 0.06, back + 0.42), HauntProps.IRON)
	k.cyl(0.07, 0.07, 0.62, 6, Vector3(0, 0.2, back + 0.33), Color(0.25, 0.16, 0.1), Vector3(0, 0, 90))
	k.cyl(0.06, 0.06, 0.5, 6, Vector3(0.05, 0.3, back + 0.3), Color(0.22, 0.14, 0.09), Vector3(0, 20, 90))
	for i in 4:
		k.flame(Vector3(-0.22 + 0.15 * i, 0.24, back + 0.36), 2.2 if i % 2 == 0 else 1.7)
	# the mantel clock (a face and two hands, no numerals) and candlesticks
	k.box(Vector3(0.36, 0.3, 0.16), Vector3(0, 1.33, back + 0.2), HauntProps.WALNUT_DK)
	k.ball(Vector3(0.18, 0.1, 0.08), Vector3(0, 1.48, back + 0.2), HauntProps.WALNUT_DK, 0, 0.0)
	k.cyl(0.11, 0.11, 0.02, 10, Vector3(0, 1.34, back + 0.29), HauntProps.LINEN, Vector3(90, 0, 0))
	k.box(Vector3(0.015, 0.08, 0.01), Vector3(0, 1.37, back + 0.305), Color(0.05, 0.05, 0.05))
	k.box(Vector3(0.06, 0.015, 0.01), Vector3(0.03, 1.34, back + 0.305), Color(0.05, 0.05, 0.05))
	HauntProps.candlestick(k, Vector3(-0.75, 1.18, back + 0.22))
	HauntProps.candlestick(k, Vector3(0.75, 1.18, back + 0.22))


# --- conservatory ------------------------------------------------------------------------------------------------------

## A raised bed: a stone kerb round dark soil, ferns and leafy clumps. (Where the parked garden's pollen beds could go.)
static func _planter_bed(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	var w := 2.6
	var d := 1.3
	k.box(Vector3(w, 0.42, 0.14), Vector3(0, 0.21, -d * 0.5 + 0.07), HauntProps.STONE)
	k.box(Vector3(w, 0.42, 0.14), Vector3(0, 0.21, d * 0.5 - 0.07), HauntProps.STONE)
	k.box(Vector3(0.14, 0.42, d - 0.28), Vector3(-w * 0.5 + 0.07, 0.21, 0), HauntProps.STONE)
	k.box(Vector3(0.14, 0.42, d - 0.28), Vector3(w * 0.5 - 0.07, 0.21, 0), HauntProps.STONE)
	k.box(Vector3(w + 0.06, 0.05, 0.2), Vector3(0, 0.44, -d * 0.5 + 0.07), HauntProps.STONE_DK)
	k.box(Vector3(w + 0.06, 0.05, 0.2), Vector3(0, 0.44, d * 0.5 - 0.07), HauntProps.STONE_DK)
	k.box(Vector3(w - 0.26, 0.06, d - 0.26), Vector3(0, 0.36, 0), HauntProps.SOIL)
	for i in 6:
		var c := Vector3(-w * 0.5 + 0.4 + (w - 0.8) * float(i) / 5.0 + r.randf_range(-0.1, 0.1), 0.38, r.randf_range(-0.25, 0.25))
		if i % 2 == 0:
			_fern(k, r, c, 0.55, 7)
		else:
			k.ball(Vector3(0.28, 0.24, 0.26), c + Vector3(0, 0.2, 0), HauntProps.LEAF if i % 4 == 1 else HauntProps.LEAF_LT, 1, 0.25)
			k.ball(Vector3(0.18, 0.16, 0.18), c + Vector3(0.12, 0.38, 0.05), HauntProps.LEAF_DK, 0, 0.2)


## A fern clump: drooping fronds round `c`.
static func _fern(k: HauntProps.Kit, r: RandomNumberGenerator, c: Vector3, size: float, n: int) -> void:
	for i in n:
		var a := TAU * float(i) / float(n) + r.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var mid := c + dir * size * 0.45 + Vector3(0, size * 0.55, 0)
		var tip := c + dir * size + Vector3(0, size * 0.25, 0)
		var col := HauntProps.LEAF if i % 3 else HauntProps.LEAF_LT
		k.box(Vector3(0.14, 0.02, size * 0.62), (c + mid) * 0.5, col, Vector3(-rad_to_deg(atan2(size * 0.55, size * 0.45)), rad_to_deg(atan2(dir.x, dir.z)), 0))
		k.box(Vector3(0.11, 0.02, size * 0.6), (mid + tip) * 0.5, HauntProps.LEAF_DK if i % 2 else col, Vector3(rad_to_deg(atan2(size * 0.3, size * 0.55)), rad_to_deg(atan2(dir.x, dir.z)), 0))


static func _potted_palm(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	k.frus(Vector2(0.4, 0.4), Vector2(0.62, 0.62), 0.6, Vector3(0, 0.3, 0), HauntProps.TERRACOTTA)
	k.box(Vector3(0.7, 0.08, 0.7), Vector3(0, 0.62, 0), HauntProps.TERRACOTTA.darkened(0.15))
	k.box(Vector3(0.56, 0.04, 0.56), Vector3(0, 0.62, 0), HauntProps.SOIL)
	var prev := Vector3(0, 0.62, 0)
	for i in 4:
		var q := Vector3(0.03 * i, 0.62 + 0.3 * (i + 1), 0.02 * i)
		k.rod(prev, q, 0.08 - i * 0.012, 0.07 - i * 0.012, 6, Color(0.42, 0.32, 0.2))
		prev = q
	var crown := prev
	for i in 8:
		var a := TAU * float(i) / 8.0 + r.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(a), 0, sin(a))
		var yaw := rad_to_deg(atan2(dir.x, dir.z))
		var p1 := crown + dir * 0.35 + Vector3(0, 0.2, 0)
		var p2 := crown + dir * 0.75 + Vector3(0, 0.05, 0)
		var p3 := crown + dir * 1.0 + Vector3(0, -0.35, 0)
		k.box(Vector3(0.3, 0.02, 0.44), (crown + p1) * 0.5, HauntProps.LEAF, Vector3(-30, yaw, 0))
		k.box(Vector3(0.34, 0.02, 0.44), (p1 + p2) * 0.5, HauntProps.LEAF_LT if i % 2 else HauntProps.LEAF, Vector3(20, yaw, 0))
		k.box(Vector3(0.22, 0.02, 0.48), (p2 + p3) * 0.5, HauntProps.LEAF_DK, Vector3(55, yaw, 0))


static func _fern_stand(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	for i in 3:
		var a := TAU * float(i) / 3.0
		k.rod(Vector3(cos(a) * 0.2, 0, sin(a) * 0.2), Vector3(cos(a) * 0.12, 0.85, sin(a) * 0.12), 0.025, 0.025, 4, HauntProps.WALNUT)
	k.cyl(0.2, 0.2, 0.04, 8, Vector3(0, 0.86, 0), HauntProps.WALNUT_DK)
	k.cyl(0.13, 0.17, 0.2, 8, Vector3(0, 0.98, 0), HauntProps.TERRACOTTA)
	_fern(k, r, Vector3(0, 1.06, 0), 0.45, 9)


## A Wardian case: a glass plant case on an iron stand (white glazing bars, see-through panes, ferns inside).
static func _wardian_case(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	var w := 1.0
	var d := 0.55
	for lx in [-0.45, 0.45]:
		for lz in [-0.22, 0.22]:
			k.cyl(0.025, 0.025, 0.7, 5, Vector3(lx, 0.35, lz), HauntProps.PAINT_WHITE)
	k.box(Vector3(w + 0.06, 0.16, d + 0.06), Vector3(0, 0.78, 0), HauntProps.WALNUT)
	k.box(Vector3(w - 0.06, 0.04, d - 0.06), Vector3(0, 0.87, 0), HauntProps.SOIL)
	_fern(k, r, Vector3(-0.22, 0.88, 0), 0.26, 6)
	k.ball(Vector3(0.16, 0.18, 0.14), Vector3(0.24, 1.02, 0.02), HauntProps.LEAF_LT, 0, 0.2)
	var y0 := 0.86
	var y1 := 1.36
	var top := 1.58
	# the bars: corners, a mid bar per side, the ridge
	for cx in [-w * 0.5, 0.0, w * 0.5]:
		for cz in [-d * 0.5, d * 0.5]:
			k.box(Vector3(0.03, y1 - y0, 0.03), Vector3(cx, (y0 + y1) * 0.5, cz), HauntProps.PAINT_WHITE)
	for cz in [-d * 0.5, d * 0.5]:
		k.box(Vector3(w, 0.03, 0.03), Vector3(0, y1, cz), HauntProps.PAINT_WHITE)
	for cx in [-w * 0.5, w * 0.5]:
		k.box(Vector3(0.03, 0.03, d), Vector3(cx, y1, 0), HauntProps.PAINT_WHITE)
		k.rod(Vector3(cx, y1, -d * 0.5), Vector3(cx, top, 0), 0.018, 0.018, 4, HauntProps.PAINT_WHITE)
		k.rod(Vector3(cx, y1, d * 0.5), Vector3(cx, top, 0), 0.018, 0.018, 4, HauntProps.PAINT_WHITE)
	k.box(Vector3(w + 0.04, 0.03, 0.03), Vector3(0, top, 0), HauntProps.PAINT_WHITE)
	k.ball(Vector3(0.04, 0.05, 0.04), Vector3(0, top + 0.04, 0), HauntProps.PAINT_WHITE, 0, 0.0)
	k.glass_box(Vector3(w, y1 - y0, d), Vector3(0, (y0 + y1) * 0.5, 0))
	var slope := rad_to_deg(atan2(top - y1, d * 0.5))
	var sl := Vector2(d * 0.5, top - y1).length()
	k.glass_box(Vector3(w, 0.01, sl), Vector3(0, (y1 + top) * 0.5, -d * 0.25), Vector3(slope, 0, 0))
	k.glass_box(Vector3(w, 0.01, sl), Vector3(0, (y1 + top) * 0.5, d * 0.25), Vector3(-slope, 0, 0))


static func _garden_bench(k: HauntProps.Kit, _p: Dictionary) -> void:
	var iron := Color(0.14, 0.22, 0.17)
	for sx in [-0.68, 0.68]:
		k.rod(Vector3(sx, 0.0, 0.24), Vector3(sx, 0.44, 0.2), 0.03, 0.03, 4, iron)
		k.rod(Vector3(sx, 0.0, -0.22), Vector3(sx, 0.44, -0.2), 0.03, 0.03, 4, iron)
		k.rod(Vector3(sx, 0.44, -0.2), Vector3(sx, 0.9, -0.3), 0.03, 0.03, 4, iron)
		k.rod(Vector3(sx, 0.44, 0.2), Vector3(sx, 0.62, 0.16), 0.028, 0.028, 4, iron)
		k.ball(Vector3(0.05, 0.05, 0.05), Vector3(sx, 0.64, 0.16), iron, 0, 0.0)
	for i in 4:
		k.box(Vector3(1.42, 0.035, 0.08), Vector3(0, 0.45, -0.15 + 0.1 * i), iron.lightened(0.05))
	for i in 3:
		k.box(Vector3(1.42, 0.08, 0.03), Vector3(0, 0.58 + 0.12 * i, -0.22 - 0.025 * i), iron, Vector3(-12, 0, 0))


static func _citrus_tub(k: HauntProps.Kit, p: Dictionary) -> void:
	var r := _rng(p)
	k.box(Vector3(0.62, 0.55, 0.62), Vector3(0, 0.33, 0), Color(0.22, 0.34, 0.26))
	for cx in [-0.31, 0.31]:
		for cz in [-0.31, 0.31]:
			k.box(Vector3(0.07, 0.66, 0.07), Vector3(cx, 0.33, cz), HauntProps.PAINT_WHITE)
			k.ball(Vector3(0.05, 0.05, 0.05), Vector3(cx, 0.69, cz), HauntProps.PAINT_WHITE, 0, 0.0)
	k.box(Vector3(0.54, 0.04, 0.54), Vector3(0, 0.6, 0), HauntProps.SOIL)
	k.rod(Vector3(0, 0.6, 0), Vector3(0.02, 1.2, 0), 0.05, 0.04, 5, Color(0.40, 0.30, 0.2))
	k.ball(Vector3(0.42, 0.36, 0.42), Vector3(0, 1.48, 0), HauntProps.LEAF_DK, 1, 0.22)
	k.ball(Vector3(0.3, 0.26, 0.3), Vector3(0.1, 1.66, 0.08), HauntProps.LEAF, 1, 0.22)
	for i in 7:
		var a := r.randf_range(0, TAU)
		var y := r.randf_range(1.28, 1.7)
		k.ball(Vector3(0.06, 0.06, 0.06), Vector3(cos(a) * 0.38, y, sin(a) * 0.38), Color(0.96, 0.55, 0.12), 0, 0.0)

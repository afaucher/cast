extends RefCounted
## The church's props (docs/design/church-rooms.md; the nave's are the game's since haunted-build-plan.md H1, see
## HauntProps; the vestry's and the bell tower's stay lab-only). Built through HauntProps.build(kind, params); the kit,
## the shared pieces and the colours are HauntProps'. No class_name (HauntProps preloads it). Each builder is
## `static func _<kind>(k: HauntProps.Kit, p: Dictionary)`.
##
## Rooms and their signature pieces:
##   nave         pew (p.length), altar, altar_dais, stained_window, lectern, pillar, candle_rack, font (+ a red runner)
##   vestry       vestment_wardrobe, robe_rack, vestry_table, chest
##   bell tower   bell_frame, bell_ropes, tower_ladder (+ chest)

const KINDS := {
	"pew": {"w": 2.8, "d": 0.7, "h": 1.0, "wall": false, "label": "pew"},
	"altar": {"w": 1.9, "d": 0.9, "h": 1.65, "wall": false, "label": "altar"},
	"altar_dais": {"w": 4.2, "d": 2.6, "h": 0.25, "wall": false, "label": "altar step"},
	"stained_window": {"w": 1.7, "d": 0.3, "h": 3.4, "wall": true, "label": "stained glass window"},
	"lectern": {"w": 0.6, "d": 0.6, "h": 1.3, "wall": false, "label": "lectern"},
	"pillar": {"w": 0.8, "d": 0.8, "h": 3.6, "wall": false, "label": "pillar"},
	"candle_rack": {"w": 1.0, "d": 0.45, "h": 1.2, "wall": false, "label": "votive candles"},
	"font": {"w": 0.9, "d": 0.9, "h": 1.0, "wall": false, "label": "font"},
	"vestment_wardrobe": {"w": 3.1, "d": 0.6, "h": 2.15, "wall": true, "label": "vestment wardrobe"},
	"robe_rack": {"w": 1.6, "d": 0.5, "h": 1.75, "wall": false, "label": "robe rack"},
	"vestry_table": {"w": 1.4, "d": 0.8, "h": 1.1, "wall": false, "label": "vestry table"},
	"chest": {"w": 1.0, "d": 0.55, "h": 0.62, "wall": false, "label": "iron-bound chest"},
	"bell_frame": {"w": 2.8, "d": 2.0, "h": 3.45, "wall": false, "label": "bell in its frame"},
	"bell_ropes": {"w": 2.0, "d": 2.0, "h": 6.0, "wall": false, "label": "bell ropes"},
	"tower_ladder": {"w": 0.7, "d": 0.6, "h": 5.0, "wall": true, "label": "tower ladder"},
}

const ALTAR_RED := Color(0.55, 0.08, 0.10)
const PURPLE := Color(0.32, 0.14, 0.42)
const ROPE := Color(0.72, 0.62, 0.42)
const GLASS: Array[Color] = [Color(0.85, 0.12, 0.12), Color(0.15, 0.32, 0.9), Color(0.95, 0.72, 0.18), Color(0.2, 0.62, 0.3), Color(0.55, 0.2, 0.75)]


# --- nave --------------------------------------------------------------------------------------------------------------

## A pew: a bench with a sloped back and carved ends, front (where you sit facing) +Z.
static func _pew(k: HauntProps.Kit, p: Dictionary) -> void:
	var length := float(p.get("length", 2.8))
	var hl := length * 0.5
	k.box(Vector3(length - 0.1, 0.06, 0.42), Vector3(0, 0.45, 0.06), HauntProps.OAK_DK)
	k.box(Vector3(length - 0.1, 0.5, 0.05), Vector3(0, 0.78, -0.2), HauntProps.OAK_DK, Vector3(-8, 0, 0))
	k.box(Vector3(length - 0.06, 0.05, 0.1), Vector3(0, 1.04, -0.24), HauntProps.OAK)
	k.box(Vector3(length - 0.1, 0.06, 0.18), Vector3(0, 0.12, -0.18), HauntProps.OAK_DK)
	for sx in [-hl + 0.04, hl - 0.04]:
		k.box(Vector3(0.08, 0.95, 0.62), Vector3(sx, 0.475, -0.02), HauntProps.OAK)
		k.ball(Vector3(0.06, 0.08, 0.1), Vector3(sx, 1.0, -0.22), HauntProps.OAK, 0, 0.0)


static func _altar_dais(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(4.2, 0.12, 2.6), Vector3(0, 0.06, 0), HauntProps.STONE_DK)
	k.box(Vector3(3.6, 0.12, 2.2), Vector3(0, 0.18, -0.1), HauntProps.STONE)


## An altar: a stone table under a white cloth with a red and gold frontal, two candlesticks and a plain gilt cross.
static func _altar(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(1.8, 0.86, 0.82), Vector3(0, 0.43, 0), HauntProps.STONE)
	k.box(Vector3(1.9, 0.06, 0.9), Vector3(0, 0.89, 0), HauntProps.STONE)
	k.box(Vector3(1.94, 0.04, 0.94), Vector3(0, 0.935, 0), HauntProps.LINEN)
	k.box(Vector3(1.94, 0.2, 0.02), Vector3(0, 0.84, 0.475), HauntProps.LINEN)
	k.box(Vector3(1.3, 0.62, 0.02), Vector3(0, 0.48, 0.42), ALTAR_RED)
	k.box(Vector3(1.26, 0.05, 0.025), Vector3(0, 0.76, 0.425), HauntProps.GILT)
	k.box(Vector3(0.06, 0.5, 0.025), Vector3(0, 0.46, 0.43), HauntProps.GILT)
	k.box(Vector3(0.3, 0.06, 0.035), Vector3(0, 0.56, 0.43), HauntProps.GILT)
	HauntProps.candlestick(k, Vector3(-0.68, 0.955, -0.1))
	HauntProps.candlestick(k, Vector3(0.68, 0.955, -0.1))
	k.box(Vector3(0.3, 0.06, 0.2), Vector3(0, 0.985, -0.2), HauntProps.GILT_DK)
	k.box(Vector3(0.06, 0.62, 0.05), Vector3(0, 1.32, -0.2), HauntProps.GILT)
	k.box(Vector3(0.36, 0.06, 0.06), Vector3(0, 1.45, -0.2), HauntProps.GILT)


## A tall lancet window against the wall: stone tracery round panes of coloured glass (glowing faces), no figures.
static func _stained_window(k: HauntProps.Kit, _p: Dictionary) -> void:
	var back := -0.15
	var w := 1.3
	var y0 := 0.5
	var y1 := 2.6
	var apex := 3.3
	k.box(Vector3(w + 0.4, 0.5, 0.3), Vector3(0, 0.25, 0), HauntProps.STONE)
	k.box(Vector3(w + 0.5, 0.06, 0.36), Vector3(0, 0.52, 0.02), HauntProps.STONE_DK)
	for sx in [-1.0, 1.0]:
		k.box(Vector3(0.2, y1 - y0, 0.26), Vector3(sx * (w * 0.5 + 0.1), (y0 + y1) * 0.5, 0), HauntProps.STONE)
		k.rod(Vector3(sx * (w * 0.5 + 0.1), y1 - 0.02, 0), Vector3(sx * 0.05, apex + 0.08, 0), 0.13, 0.12, 4, HauntProps.STONE)
	# the panes: a grid of small coloured diamonds of glow in two lights (a mullion between), and the arch's head
	k.box(Vector3(0.08, y1 - y0, 0.14), Vector3(0, (y0 + y1) * 0.5, back + 0.12), HauntProps.STONE)
	var rows := 9
	for side in [-1.0, 1.0]:
		for j in rows:
			for i in 2:
				var x := float(side) * (0.16 + 0.27 * i)
				var y := y0 + 0.12 + (y1 - y0 - 0.2) * float(j) / float(rows - 1)
				# a blue border column, a red and gold middle, a green band low down
				var col: Color = GLASS[1] if i == 1 else (GLASS[0] if j % 2 == 0 else GLASS[2])
				if j == 1 or j == 2:
					col = GLASS[3] if i == 0 else GLASS[1]
				k.box(Vector3(0.23, 0.23, 0.03), Vector3(x, y, back + 0.1), PropModels.glow(col.darkened(0.42)))
				k.box(Vector3(0.025, 0.25, 0.04), Vector3(x + 0.135, y, back + 0.11), Color(0.08, 0.08, 0.09))
				k.box(Vector3(0.26, 0.025, 0.04), Vector3(x, y + 0.13, back + 0.11), Color(0.08, 0.08, 0.09))
	for j in 4:
		var t := float(j) / 4.0
		var hw := (w * 0.5) * (1.0 - t * t) * 0.92
		var y := y1 + 0.1 + (apex - y1 - 0.2) * t
		k.box(Vector3(hw * 2.0, 0.12, 0.03), Vector3(0, y, back + 0.1), PropModels.glow((GLASS[1] if j % 2 == 0 else GLASS[4]).darkened(0.42)))
	k.ball(Vector3(0.14, 0.14, 0.04), Vector3(0, y1 + 0.25, back + 0.13), PropModels.glow(GLASS[2].darkened(0.2)), 0, 0.0)


static func _lectern(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(0.5, 0.08, 0.5), Vector3(0, 0.04, 0), HauntProps.OAK_DK)
	k.cyl(0.08, 0.06, 0.9, 6, Vector3(0, 0.53, 0), HauntProps.OAK)
	k.box(Vector3(0.6, 0.05, 0.42), Vector3(0, 1.08, 0), HauntProps.OAK_DK, Vector3(25, 0, 0))
	k.box(Vector3(0.56, 0.06, 0.05), Vector3(0, 0.98, 0.2), HauntProps.OAK)
	k.box(Vector3(0.46, 0.04, 0.32), Vector3(0, 1.12, 0.0), HauntProps.LINEN, Vector3(25, 0, 0))
	k.box(Vector3(0.02, 0.05, 0.32), Vector3(0, 1.14, 0.0), ALTAR_RED, Vector3(25, 0, 0))


static func _pillar(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(0.8, 0.22, 0.8), Vector3(0, 0.11, 0), HauntProps.STONE_DK)
	k.cyl(0.36, 0.32, 0.14, 8, Vector3(0, 0.29, 0), HauntProps.STONE)
	k.cyl(0.27, 0.25, 2.9, 8, Vector3(0, 1.81, 0), HauntProps.STONE)
	k.cyl(0.26, 0.4, 0.22, 8, Vector3(0, 3.37, 0), HauntProps.STONE)
	k.box(Vector3(0.86, 0.12, 0.86), Vector3(0, 3.54, 0), HauntProps.STONE_DK)


## A votive stand: an iron rack of three tiers of small candles.
static func _candle_rack(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.flame_k = 0.7
	for sx in [-0.45, 0.45]:
		k.box(Vector3(0.05, 1.0, 0.05), Vector3(sx, 0.5, 0), HauntProps.IRON)
		k.box(Vector3(0.05, 0.05, 0.4), Vector3(sx, 0.025, 0), HauntProps.IRON)
	for t in 3:
		var y := 0.62 + 0.16 * t
		var z := 0.1 - 0.1 * t
		k.box(Vector3(0.9, 0.03, 0.14), Vector3(0, y, z), HauntProps.IRON_LT)
		for i in 7:
			if (i + t) % 3 == 2:
				continue
			k.cyl(0.035, 0.035, 0.04, 6, Vector3(-0.39 + 0.13 * i, y + 0.035, z), HauntProps.LINEN)
			k.flame(Vector3(-0.39 + 0.13 * i, y + 0.055, z), 0.8)
	k.box(Vector3(0.3, 0.16, 0.16), Vector3(0, 0.35, 0.02), HauntProps.IRON)


static func _font(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.cyl(0.42, 0.42, 0.14, 8, Vector3(0, 0.07, 0), HauntProps.STONE_DK)
	k.cyl(0.18, 0.2, 0.5, 8, Vector3(0, 0.39, 0), HauntProps.STONE)
	k.cyl(0.24, 0.44, 0.3, 8, Vector3(0, 0.79, 0), HauntProps.STONE)
	k.cyl(0.36, 0.36, 0.02, 8, Vector3(0, 0.945, 0), Color(0.22, 0.32, 0.36))
	k.cyl(0.32, 0.18, 0.08, 8, Vector3(0, 1.0, 0), HauntProps.OAK_DK)


# --- vestry ------------------------------------------------------------------------------------------------------------

## A tall wardrobe with its doors open: robes (white, purple, red) hanging inside.
static func _vestment_wardrobe(k: HauntProps.Kit, _p: Dictionary) -> void:
	var back := -0.3
	k.box(Vector3(1.6, 2.0, 0.04), Vector3(0, 1.05, back + 0.02), HauntProps.OAK_DK)
	for sx in [-0.78, 0.78]:
		k.box(Vector3(0.05, 2.0, 0.6), Vector3(sx, 1.05, 0), HauntProps.OAK)
	k.box(Vector3(1.72, 0.12, 0.68), Vector3(0, 2.1, 0.01), HauntProps.OAK)
	k.box(Vector3(1.6, 0.1, 0.6), Vector3(0, 0.05, 0), HauntProps.OAK_DK)
	k.rod(Vector3(-0.75, 1.82, -0.02), Vector3(0.75, 1.82, -0.02), 0.02, 0.02, 4, HauntProps.GILT_DK)
	var robes: Array[Color] = [HauntProps.LINEN, PURPLE, ALTAR_RED, HauntProps.LINEN, Color(0.15, 0.32, 0.18)]
	for i in robes.size():
		_robe(k, Vector3(-0.56 + 0.28 * i, 1.82, -0.02), robes[i])
	# the doors, swung wide open (folded back toward the wall on their hinges at the front corners)
	for sx in [-1.0, 1.0]:
		var dir := Vector3(sx * cos(deg_to_rad(20.0)), 0, sin(deg_to_rad(20.0)))
		k.box(Vector3(0.78, 1.9, 0.05), Vector3(sx * 0.8, 1.05, 0.26) + dir * 0.4, HauntProps.OAK, Vector3(0, -sx * 20.0, 0))


## A robe on a hanger hooked at `top`.
static func _robe(k: HauntProps.Kit, top: Vector3, col: Color) -> void:
	k.rod(top, top + Vector3(0, -0.08, 0), 0.01, 0.01, 3, HauntProps.IRON)
	k.box(Vector3(0.36, 0.03, 0.04), top + Vector3(0, -0.1, 0), HauntProps.OAK)
	k.frus(Vector2(0.4, 0.2), Vector2(0.34, 0.14), 1.25, top + Vector3(0, -0.74, 0), col)
	k.box(Vector3(0.12, 0.02, 0.15), top + Vector3(0, -0.12, 0.02), col.darkened(0.2))


static func _robe_rack(k: HauntProps.Kit, _p: Dictionary) -> void:
	for sx in [-0.75, 0.75]:
		k.box(Vector3(0.06, 1.7, 0.06), Vector3(sx, 0.85, 0), HauntProps.OAK)
		k.box(Vector3(0.08, 0.06, 0.5), Vector3(sx, 0.03, 0), HauntProps.OAK_DK)
	k.rod(Vector3(-0.78, 1.66, 0), Vector3(0.78, 1.66, 0), 0.025, 0.025, 4, HauntProps.OAK_DK)
	var robes: Array[Color] = [PURPLE, HauntProps.LINEN, ALTAR_RED, HauntProps.LINEN]
	for i in robes.size():
		_robe(k, Vector3(-0.48 + 0.32 * i, 1.66, 0), robes[i])


static func _vestry_table(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(1.4, 0.06, 0.8), Vector3(0, 0.76, 0), HauntProps.OAK)
	for lx in [-0.62, 0.62]:
		for lz in [-0.32, 0.32]:
			k.box(Vector3(0.07, 0.73, 0.07), Vector3(lx, 0.365, lz), HauntProps.OAK_DK)
	k.box(Vector3(1.2, 0.05, 0.05), Vector3(0, 0.15, 0), HauntProps.OAK_DK)
	# a chalice, a closed book (a plain cover), a candlestick, a folded stole
	k.cyl(0.08, 0.08, 0.02, 8, Vector3(-0.3, 0.8, 0.05), HauntProps.GILT)
	k.cyl(0.015, 0.02, 0.12, 5, Vector3(-0.3, 0.87, 0.05), HauntProps.GILT)
	k.cyl(0.04, 0.07, 0.1, 8, Vector3(-0.3, 0.98, 0.05), HauntProps.GILT)
	k.box(Vector3(0.34, 0.08, 0.26), Vector3(0.18, 0.83, -0.12), ALTAR_RED.darkened(0.3), Vector3(0, 12, 0))
	k.box(Vector3(0.1, 0.085, 0.27), Vector3(0.1, 0.83, -0.13), HauntProps.GILT_DK, Vector3(0, 12, 0))
	k.box(Vector3(0.5, 0.03, 0.12), Vector3(0.2, 0.805, 0.22), PURPLE, Vector3(0, -8, 0))
	HauntProps.candlestick(k, Vector3(0.52, 0.79, 0.1))


static func _chest(k: HauntProps.Kit, _p: Dictionary) -> void:
	k.box(Vector3(1.0, 0.42, 0.55), Vector3(0, 0.23, 0), HauntProps.OAK_DK)
	k.cyl(0.275, 0.275, 1.0, 8, Vector3(0, 0.44, 0), HauntProps.OAK_DK, Vector3(0, 0, 90))
	for sx in [-0.4, 0.0, 0.4]:
		k.box(Vector3(0.06, 0.45, 0.57), Vector3(sx, 0.24, 0), HauntProps.IRON)
		k.cyl(0.285, 0.285, 0.06, 8, Vector3(sx, 0.44, 0), HauntProps.IRON, Vector3(0, 0, 90))
	k.box(Vector3(0.14, 0.16, 0.03), Vector3(0, 0.4, 0.285), HauntProps.IRON_LT)
	k.box(Vector3(1.0, 0.04, 0.04), Vector3(0, 0.02, 0.26), HauntProps.IRON)


# --- bell tower --------------------------------------------------------------------------------------------------------

## A bronze bell hung in a heavy timber frame: two A-frames, a headstock across them, the wheel at one side. p.lift raises
## it onto a deck of beams on four posts (the belfry above the ringing chamber), its wheel rope dropping to the floor.
static func _bell_frame(k: HauntProps.Kit, p: Dictionary) -> void:
	var timber := Color(0.34, 0.24, 0.15)
	var lift := float(p.get("lift", 0.0))
	var first := k.s.verts.size()
	for sx in [-1.15, 1.15]:
		k.box(Vector3(0.22, 0.2, 1.7), Vector3(sx, 0.1, 0), timber)
		k.rod(Vector3(sx, 0.2, -0.75), Vector3(sx, 2.55, 0), 0.1, 0.09, 4, timber)
		k.rod(Vector3(sx, 0.2, 0.75), Vector3(sx, 2.55, 0), 0.1, 0.09, 4, timber)
		k.box(Vector3(0.24, 0.24, 0.4), Vector3(sx, 2.6, 0), timber.darkened(0.15))
	k.box(Vector3(2.5, 0.16, 0.2), Vector3(0, 0.08, -0.75), timber.darkened(0.1))
	k.box(Vector3(2.5, 0.16, 0.2), Vector3(0, 0.08, 0.75), timber.darkened(0.1))
	# the headstock (the bell's yoke) on its pivots
	k.box(Vector3(1.9, 0.26, 0.3), Vector3(0, 2.62, 0), timber.darkened(0.25))
	for sx in [-1.0, 1.0]:
		k.cyl(0.06, 0.06, 0.25, 6, Vector3(sx * 1.05, 2.62, 0), HauntProps.IRON, Vector3(0, 0, 90))
	# the bell, mouth down
	var top := 2.45
	k.cyl(0.3, 0.38, 0.16, 10, Vector3(0, top - 0.08, 0), HauntProps.BRONZE)
	k.cyl(0.38, 0.46, 0.5, 10, Vector3(0, top - 0.41, 0), HauntProps.BRONZE)
	k.cyl(0.46, 0.76, 0.34, 10, Vector3(0, top - 0.83, 0), HauntProps.BRONZE)
	k.cyl(0.76, 0.8, 0.1, 10, Vector3(0, top - 1.05, 0), HauntProps.BRONZE_DK)
	k.ball(Vector3(0.11, 0.11, 0.11), Vector3(0, top - 1.16, 0), HauntProps.IRON, 0, 0.0)
	k.cyl(0.08, 0.08, 0.14, 6, Vector3(0, top + 0.05, 0), HauntProps.BRONZE_DK)
	# the wheel at the +x side (a ring of spokes) and its rope going down
	var wc := Vector3(1.32, 2.62, 0)
	var prev := wc + Vector3(0, 0.75, 0)
	for i in range(1, 13):
		var a := TAU * float(i) / 12.0
		var q := wc + Vector3(0, cos(a) * 0.75, sin(a) * 0.75)
		k.rod(prev, q, 0.035, 0.035, 4, timber)
		prev = q
		if i % 3 == 0:
			k.rod(wc, q, 0.025, 0.025, 4, timber)
	PropModels.shift(k.s, first, Vector3(0, lift, 0))
	k.rod(wc + Vector3(0.04, lift - 0.4, 0.62), Vector3(1.36, 0.6, 0.62), 0.02, 0.02, 4, ROPE)
	if lift > 0.0:
		for sx in [-1.25, 1.25]:
			for sz in [-0.85, 0.85]:
				k.box(Vector3(0.24, lift, 0.24), Vector3(sx, lift * 0.5, sz), timber.darkened(0.2))
		for sz in [-0.85, 0.85]:
			k.box(Vector3(2.8, 0.2, 0.26), Vector3(0, lift - 0.1, sz), timber.darkened(0.1))
		for sx in [-1.25, 1.25]:
			k.box(Vector3(0.26, 0.2, 1.96), Vector3(sx, lift - 0.1, 0), timber.darkened(0.1))


## Bell ropes dropping from the dark above through the ringing chamber: each with a striped woollen grip (the sally)
## and its tail looped up. `p.count` ropes on a ring of `p.radius`.
static func _bell_ropes(k: HauntProps.Kit, p: Dictionary) -> void:
	var n := int(p.get("count", 4))
	var rad := float(p.get("radius", 0.9))
	var sallies: Array[Color] = [Color(0.75, 0.1, 0.12), HauntProps.LINEN, Color(0.15, 0.25, 0.6)]
	for i in n:
		var a := TAU * float(i) / float(n) + 0.4
		var x := cos(a) * rad
		var z := sin(a) * rad
		k.rod(Vector3(x, 6.0, z), Vector3(x, 1.0, z), 0.032, 0.032, 4, ROPE)
		for j in 6:
			var y := 1.8 - 0.14 * j
			k.cyl(0.08, 0.08, 0.14, 6, Vector3(x, y, z), sallies[j % sallies.size()])
		k.rod(Vector3(x, 1.0, z), Vector3(x + 0.08, 0.7, z), 0.03, 0.03, 4, ROPE)
		k.rod(Vector3(x + 0.08, 0.7, z), Vector3(x + 0.04, 1.05, z + 0.05), 0.03, 0.03, 4, ROPE)
	# the ringing-floor boss in the middle (where the ropes would gather on a spider)
	k.cyl(0.1, 0.1, 0.06, 8, Vector3(0, 0.03, 0), HauntProps.IRON)


## A long ladder up the tower wall (to a hatch out of sight above).
static func _tower_ladder(k: HauntProps.Kit, _p: Dictionary) -> void:
	HauntProps.ladder(k, Vector3(0, 0.0, 0.25), Vector3(0, 5.0, -0.2), 0.5, HauntProps.OAK, 16)
	k.box(Vector3(0.7, 0.08, 0.1), Vector3(0, 2.4, -0.25), HauntProps.IRON)

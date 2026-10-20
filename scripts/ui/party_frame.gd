class_name PartyFrame
extends Control
## The party HUD, top left (the redesign of 2026-10-19; Hud.PARTY_LOOK picks it, "old" keeps the bars it replaces):
## one row per crew member, yours first and biggest, then the employees following you as a strip of small bubbles.
##
## A HERO ROW: a round portrait (the player's Steam avatar; without one, and for an AI seat, the hero's headshot from
## Headshots; a lettered disc while that renders or headless) in a ring of the hero's colour; the name (Steam name for a
## person, the hero's name for an AI seat) and, small under it, the character when the name is not the hero's; the HP
## bar; the ORDER CHIP (FOLLOW, GO, HOLD, ATTACK for an AI hero; on your own row GO / ATTACK, outlined and draining, while
## a crewmate's order marker stands; nothing for another person's hero). DOWN and DAZED sit on the portrait itself (a pill
## over its lower edge, a grey face for down, a throbbing yellow ring for dazed) so they read at a glance.
##
## NAMES (Steam allows 32 characters): one line. A name wider than its row first shrinks, down to NAME_MIN_SCALE of its
## size, and is then cut with an ellipsis at the row's width (fit_name; wide glyphs and other scripts measure through the
## font's system fallbacks the same way).
##
## THE FOLLOWER STRIP (show_followers): every employee following you (PartyInfo.followers), a bubble each (their model's
## headshot, or their initial), the short name ("Gary"), a tiny HP bar and the state (a red ring and FIGHT for a henchman
## you sent to fight, a plain ring while it follows). At most MAX_FOLLOWERS bubbles: past that the last one reads "+N".
##
## Two looks (`look`): CLEAN, a dark game HUD (the spell cards' family), and PAPER, crew ID cards on the crew's green carbon
## with typed names and rubber-stamp chips (the work-order slip's family). Both draw from the same views.
##
## Pure presentation: it reads PartyInfo every frame and writes nothing back.

enum Look { CLEAN, PAPER }

const MAX_FOLLOWERS := 5
const NAME_MIN_SCALE := 0.8         ## a long name shrinks to this share of its size before it is cut
const ROW_GAP := 8.0
const STRIP_GAP := 10.0
## Sizes per row kind (canvas units, 1600x900): [portrait diameter, row height, text x, name size, sub size, bar w, bar h, bar y]
const YOU := {"d": 72.0, "h": 84.0, "tx": 86.0, "name": 25, "sub": 15, "bar_w": 250.0, "bar_h": 18.0, "bar_y": 58.0, "ring": 4.0,
	"name_y": 29.0, "sub_y": 48.0}
const ALLY := {"d": 52.0, "h": 62.0, "tx": 72.0, "name": 20, "sub": 14, "bar_w": 170.0, "bar_h": 10.0, "bar_y": 46.0, "ring": 3.0,
	"name_y": 22.0, "sub_y": 39.0}
const CELL_W := 68.0
const BUBBLE_D := 36.0
const STRIP_H := 78.0

const HP_GREEN := Color(0.3, 0.85, 0.5)
const HP_LOW := Color(0.95, 0.42, 0.3)
const DOWN_GREY := Color(0.42, 0.42, 0.45)
const DAZE_YELLOW := Color(1.0, 0.82, 0.3)
const DOWN_RED := Color(0.86, 0.2, 0.16)
## Clean chips: [fill, text, outline].
const CHIP_COLORS := {
	"follow": [Color(1, 1, 1, 0.1), Color(0.86, 0.89, 0.94), Color(1, 1, 1, 0.38)],
	"go": [Color(0.13, 0.52, 0.58), Color.WHITE, Color(0.45, 0.85, 0.9)],
	"hold": [Color(0.86, 0.6, 0.14), Color(0.13, 0.09, 0.02), Color(1.0, 0.82, 0.4)],
	"attack": [Color(0.8, 0.2, 0.16), Color.WHITE, Color(1.0, 0.5, 0.42)],
	"fight": [Color(0.8, 0.2, 0.16), Color.WHITE, Color(1.0, 0.5, 0.42)],
}
## Paper stamps: ink per chip.
const STAMP_INK := {
	"follow": FormTheme.INK, "go": FormTheme.BLUE_PEN, "hold": Color(0.55, 0.36, 0.02), "attack": FormTheme.RED,
	"fight": FormTheme.RED,
}

var look: Look = Look.CLEAN
var show_followers := true
var you: Hero = null
var allies: Array[Hero] = []
var headshots: Headshots

var views: Array[Dictionary] = []          ## this frame's hero rows (PartyInfo.hero_view), yours first
var follower_list: Array[Employee] = []    ## this frame's strip
var _fighting_for_you: Dictionary = {}     ## employee instance id -> true: followed you, then went to FIGHT
var _hp_shown: Dictionary = {}             ## hero instance id -> the trailing "damage" part of the bar
var _grey: Dictionary = {}                 ## texture instance id -> its grey copy (a downed portrait)
var _circle: PackedVector2Array
var _circle_uv: PackedVector2Array


func _init() -> void:
	name = "PartyFrame"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := 48
	for i in n:
		var a := TAU * float(i) / n
		_circle.append(Vector2(cos(a), sin(a)))
		_circle_uv.append(Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))


func _ready() -> void:
	headshots = Headshots.new()
	add_child(headshots)
	headshots.rendered.connect(func(_k: String) -> void: queue_redraw())
	var s := Net.session()
	if s != null and s.avatars != null:
		s.avatars.avatar_ready.connect(func(_id: int) -> void: queue_redraw())


func bind(new_you: Hero, new_allies: Array[Hero]) -> void:
	you = new_you
	allies = new_allies
	_fighting_for_you.clear()
	refresh()


## Read everything again (every frame).
func refresh() -> void:
	views.clear()
	for h: Hero in [you] + allies:
		if h != null and is_instance_valid(h):
			views.append(PartyInfo.hero_view(h, you))
	follower_list.clear()
	if show_followers and you != null and is_instance_valid(you):
		for e in Employee.alive():
			if e.leader() == you:
				_fighting_for_you[e.get_instance_id()] = true
			elif e.state != Employee.State.FIGHT:
				_fighting_for_you.erase(e.get_instance_id())
		follower_list = PartyInfo.followers(you, _fighting_for_you)
	custom_minimum_size = Vector2(frame_width(), frame_height())
	size = custom_minimum_size
	queue_redraw()


func _process(delta: float) -> void:
	for v in views:
		var id: int = (v["hero"] as Hero).get_instance_id()
		var f := float(v["hp"]) / float(v["max_hp"])
		var shown := float(_hp_shown.get(id, f))
		_hp_shown[id] = f if f >= shown or bool(v["down"]) else maxf(f, shown - delta * 0.9)
	refresh()


# --- Geometry ------------------------------------------------------------------------------------

static func spec(is_you: bool) -> Dictionary:
	return YOU if is_you else ALLY


func row_top(i: int) -> float:
	var y := 0.0
	for k in i:
		y += float(spec(k == 0)["h"]) + ROW_GAP
	return y


func frame_width() -> float:
	return float(YOU["tx"]) + float(YOU["bar_w"]) + 18.0


func frame_height() -> float:
	var h := row_top(views.size())
	if show_followers and not follower_list.is_empty():
		h += STRIP_GAP + STRIP_H
	return h


## The share of `size` a name may shrink to and the room it has (tests read the result).
## Returns {text, size, cut}: `text` as drawn (cut with an ellipsis when even NAME_MIN_SCALE of `base` is too wide).
static func fit_name(text: String, font: Font, base: int, width: float) -> Dictionary:
	var min_size := maxi(8, int(floorf(base * NAME_MIN_SCALE)))
	for fs in range(base, min_size - 1, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
			return {"text": text, "size": fs, "cut": false}
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, min_size).x > width:
		t = t.substr(0, t.length() - 1)
	return {"text": t.strip_edges() + "…", "size": min_size, "cut": true}


func name_font() -> Font:
	return FormTheme.typed_font() if look == Look.PAPER else FormTheme.label_font(true)


## The name's room in a row (the full text column: the chip sits on the line under it).
static func name_width(is_you: bool) -> float:
	var s := spec(is_you)
	return float(s["bar_w"]) + (0.0 if is_you else 40.0)


# --- Drawing -------------------------------------------------------------------------------------

func _draw() -> void:
	for i in views.size():
		_draw_row(views[i], row_top(i))
	if show_followers and not follower_list.is_empty():
		_draw_strip(row_top(views.size()) + STRIP_GAP - ROW_GAP)


func _draw_row(v: Dictionary, top: float) -> void:
	var is_you := bool(v["you"])
	var s := spec(is_you)
	var d: float = s["d"]
	var h: float = s["h"]
	var tx: float = s["tx"]
	var bar_w: float = s["bar_w"]
	var right := tx + bar_w + (0.0 if is_you else 40.0)
	var paper := look == Look.PAPER
	var center := Vector2(d * 0.5 + (0.0 if is_you else (float(YOU["d"]) - d) * 0.5), top + h * 0.5)
	var down := bool(v["down"])
	# The plate / the card.
	if paper:
		var card := Rect2(Vector2(0, top), Vector2(right + 12.0, h))
		_paper(card, FormTheme.carbon("green"))
	else:
		var plate := StyleBoxFlat.new()
		plate.bg_color = Color(0.03, 0.04, 0.07, 0.62)
		plate.set_corner_radius_all(int(h * 0.5))
		draw_style_box(plate, Rect2(Vector2(center.x, top + 3.0), Vector2(right + 10.0 - center.x, h - 6.0)))
	_draw_portrait(v, center, d * 0.5, float(s["ring"]))
	# Name.
	var font := name_font()
	var fit := fit_name(str(v["name"]), font, int(s["name"]) - (4 if paper else 0), name_width(is_you))
	var name_y := top + float(s["name_y"])
	var name_col := Color(1, 1, 1, 0.55) if down else Color.WHITE
	if paper:
		name_col = Color(FormTheme.TYPED, 0.5) if down else FormTheme.TYPED
		if bool(v["dazed"]):
			FormTheme.draw_band(self, Rect2(tx - 4.0, name_y - fit["size"] * 0.95, minf(font.get_string_size(fit["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fit["size"]).x + 8.0, right - tx + 4.0), fit["size"] * 1.25))
		draw_string(font, Vector2(tx, name_y), fit["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fit["size"], name_col)
	else:
		_outlined(font, Vector2(tx, name_y), fit["text"], fit["size"], name_col)
	# Character (when the name is not the hero's), and the chip on the same line at the right.
	var sub_y := top + float(s["sub_y"])
	var sub_size := int(s["sub"])
	if str(v["name"]) != str(v["character"]):
		var cf := FormTheme.label_font()
		var ctext := str(v["character"]).to_upper()
		if paper:
			draw_string(cf, Vector2(tx, sub_y), ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, FormTheme.INK)
		else:
			_outlined(cf, Vector2(tx, sub_y), ctext, sub_size, (v["color"] as Color).lightened(0.35))
	var chip := str(v["order"])
	if not down and chip != "":
		var outlined := bool(v["human"])
		var cy := sub_y - sub_size * 0.36
		if paper:
			_stamp_chip(chip, Vector2(right, cy), is_you, outlined, float(v["order_left"]))
		else:
			_clean_chip(chip, Vector2(right, cy), is_you, outlined, float(v["order_left"]))
	# HP bar.
	var bar := Rect2(tx, top + float(s["bar_y"]), bar_w, float(s["bar_h"]))
	_draw_bar(v, bar, is_you, paper)
	if down and paper:   # on the card, DOWN is a big red stamp across it
		_stamp("DOWN", Vector2(tx + bar_w * 0.55, top + h * 0.5), 26 if is_you else 20, FormTheme.RED, -0.1)


func _draw_bar(v: Dictionary, bar: Rect2, is_you: bool, paper: bool) -> void:
	var f := clampf(float(v["hp"]) / float(v["max_hp"]), 0.0, 1.0)
	var trail := clampf(float(_hp_shown.get((v["hero"] as Hero).get_instance_id(), f)), f, 1.0)
	var down := bool(v["down"])
	var fill := DOWN_GREY if down else (HP_LOW if f < 0.3 else HP_GREEN)
	var num := "DOWN" if down else "%d / %d" % [int(ceilf(float(v["hp"]))), int(v["max_hp"])]
	if paper:
		draw_rect(bar, Color(1, 1, 1, 0.45))
		fill = Color(FormTheme.GREEN_INK, 0.85) if not down else Color(0.5, 0.5, 0.5, 0.5)
		if f < 0.3 and not down:
			fill = Color(FormTheme.RED, 0.85)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * trail, bar.size.y)), Color(FormTheme.RED, 0.3))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), fill)
		draw_rect(bar, FormTheme.INK, false, 1.5)
		var tf := FormTheme.typed_font()
		if is_you:
			var w := tf.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var at := Vector2(bar.position.x + (bar.size.x - w) * 0.5, bar.position.y + bar.size.y * 0.5 + 5.0)
			draw_string(tf, at, num, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE if f > 0.55 else FormTheme.TYPED)
		else:
			draw_string(tf, Vector2(bar.end.x + 6.0, bar.position.y + bar.size.y * 0.5 + 13 * 0.36), "DOWN" if down else str(int(ceilf(float(v["hp"])))), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, FormTheme.TYPED)
		return
	draw_rect(bar, Color(0, 0, 0, 0.62))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * trail, bar.size.y)), Color(1, 1, 1, 0.55))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), fill)
	draw_rect(bar, Color(1, 1, 1, 0.35), false, 1.0)
	var font := ThemeDB.fallback_font
	if is_you:
		var fs := 15
		var w := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_outlined(font, Vector2(bar.position.x + (bar.size.x - w) * 0.5, bar.position.y + bar.size.y * 0.5 + fs * 0.36), num, fs, Color.WHITE, 3)
	else:
		var short := "DOWN" if down else str(int(ceilf(float(v["hp"]))))
		_outlined(FormTheme.label_font(), Vector2(bar.end.x + 7.0, bar.position.y + bar.size.y * 0.5 + 15 * 0.36), short, 15, Color(1, 1, 1, 0.85) if not down else DOWN_RED.lightened(0.3), 3)


## The round portrait: avatar, headshot or initial; the ring; DOWN / DAZED on its lower edge.
func _draw_portrait(v: Dictionary, c: Vector2, r: float, ring: float) -> void:
	var col: Color = v["color"]
	var down := bool(v["down"])
	var dazed := bool(v["dazed"])
	var paper := look == Look.PAPER
	var tex: Texture2D = v["avatar"]
	var crop := 1.0
	if tex == null:
		tex = headshots.texture("hero:" + str(v["kit"])) if headshots != null else null
		crop = 0.92
	draw_circle(c, r, col.darkened(0.55) if not paper else col.lightened(0.45))
	if tex != null:
		_disc(tex if not down else _grey_of(tex), c, r - 1.0, crop)
	else:
		var lf := FormTheme.label_font(true)
		var letter := str(v["name"]).substr(0, 1).to_upper()
		var fs := int(r * 1.05)
		var w := lf.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(lf, c + Vector2(-w * 0.5, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))
	if down:
		draw_circle(c, r, Color(0.08, 0.0, 0.0, 0.35))
	var ring_col := col
	if down:
		ring_col = DOWN_RED
	elif dazed:
		ring_col = DAZE_YELLOW.lerp(Color.WHITE, 0.5 + 0.5 * sin(GameWorld.time * 14.0))
	if paper:
		draw_arc(c, r - ring * 0.5, 0, TAU, 48, ring_col, ring, true)
		draw_arc(c, r, 0, TAU, 48, FormTheme.INK, 1.5, true)
	else:
		draw_arc(c, r + 1.0, 0, TAU, 48, Color(0, 0, 0, 0.85), ring + 2.5, true)
		draw_arc(c, r - ring * 0.5 + 1.0, 0, TAU, 48, ring_col, ring, true)
	if down:
		_badge("DOWN", c + Vector2(0, r * 0.62), r, DOWN_RED, Color.WHITE)
	elif dazed:
		_badge("DAZED", c + Vector2(0, r * 0.62), r, DAZE_YELLOW, Color(0.15, 0.1, 0.0))


## A pill across the lower edge of a portrait (DOWN, DAZED, FIGHT); a tilted stamp on paper.
func _badge(text: String, at: Vector2, r: float, fill: Color, ink: Color) -> void:
	var fs := clampi(int(r * 0.42), 10, 16)
	if look == Look.PAPER:
		_stamp(text, at, fs + 1, fill.darkened(0.15) if fill != DAZE_YELLOW else Color(0.6, 0.4, 0.0), -0.12)
		return
	var lf := FormTheme.label_font(true)
	var w := lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 10.0
	var rect := Rect2(at - Vector2(w * 0.5, fs * 0.62), Vector2(w, fs * 1.24))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(rect.size.y * 0.5))
	sb.border_color = Color(0, 0, 0, 0.8)
	sb.set_border_width_all(1)
	draw_style_box(sb, rect)
	draw_string(lf, Vector2(rect.position.x + 5.0, rect.position.y + rect.size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## A clean order chip, right-aligned at `right_mid` (x = right edge, y = vertical middle).
func _clean_chip(kind: String, right_mid: Vector2, big: bool, outlined: bool, left: float) -> void:
	var fs := 15 if big else 13
	var lf := FormTheme.label_font(true)
	var text := kind.to_upper()
	var tw := lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var gw := fs * 0.8
	var hgt := fs + 7.0
	var w := tw + gw + 16.0
	var rect := Rect2(Vector2(right_mid.x - w, right_mid.y - hgt * 0.5), Vector2(w, hgt))
	var cols: Array = CHIP_COLORS.get(kind, CHIP_COLORS["follow"])
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(hgt * 0.5))
	sb.set_border_width_all(1 if not outlined else 2)
	sb.border_color = cols[2]
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.8) if outlined else cols[0]
	draw_style_box(sb, rect)
	if outlined and left > 0.0:   # a crewmate's order to you: the fill drains over the marker's 12 s
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(cols[0], 0.9)
		fill.set_corner_radius_all(int(hgt * 0.5))
		draw_style_box(fill, Rect2(rect.position, Vector2(maxf(hgt, w * left), hgt)).grow(-2.0))
	var ink: Color = Color.WHITE if outlined else cols[1]
	_glyph(kind, Rect2(rect.position + Vector2(7.0, (hgt - gw) * 0.5), Vector2(gw, gw)), ink)
	draw_string(lf, Vector2(rect.position.x + 9.0 + gw, rect.position.y + hgt * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## A paper order chip: a small rubber stamp, right-aligned at `right_mid`.
func _stamp_chip(kind: String, right_mid: Vector2, big: bool, outlined: bool, left: float) -> void:
	var fs := 14 if big else 12
	var sf := FormTheme.stamp_font()
	var tw := sf.get_string_size(kind.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ink: Color = STAMP_INK.get(kind, FormTheme.INK)
	_stamp(kind.to_upper(), Vector2(right_mid.x - tw * 0.5 - 8.0, right_mid.y), fs, ink, -0.05, outlined)
	if outlined and left > 0.0:
		draw_line(Vector2(right_mid.x - tw - 14.0, right_mid.y + fs * 0.85), Vector2(right_mid.x - tw - 14.0 + (tw + 12.0) * left, right_mid.y + fs * 0.85), ink, 2.0)


## A rubber stamp centred at `at`: the text in Black Ops One inside a double border, tilted by `angle`.
func _stamp(text: String, at: Vector2, fs: int, ink: Color, angle: float, single: bool = false) -> void:
	var sf := FormTheme.stamp_font()
	var tw := sf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(Vector2(-tw * 0.5 - 6.0, -fs * 0.68), Vector2(tw + 12.0, fs * 1.36))
	draw_set_transform(at, angle, Vector2.ONE)
	draw_rect(box, Color(1, 1, 1, 0.35))
	draw_rect(box, Color(ink, 0.9), false, 2.0)
	if not single:
		draw_rect(box.grow(-2.5), Color(ink, 0.6), false, 1.0)
	draw_string(sf, Vector2(-tw * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ink, 0.92))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## A tiny drawn glyph per chip: follow (two chevrons), go (an arrow), hold (a flag), attack / fight (crossed strokes).
func _glyph(kind: String, r: Rect2, ink: Color) -> void:
	var p := r.position
	var s := r.size.x
	match kind:
		"follow":
			for k in 2:
				var x := p.x + s * (0.15 + 0.4 * k)
				draw_polyline(PackedVector2Array([Vector2(x, p.y + s * 0.15), Vector2(x + s * 0.32, p.y + s * 0.5), Vector2(x, p.y + s * 0.85)]), ink, 1.8, true)
		"go":
			draw_line(Vector2(p.x + s * 0.05, p.y + s * 0.5), Vector2(p.x + s * 0.85, p.y + s * 0.5), ink, 2.0, true)
			draw_polyline(PackedVector2Array([Vector2(p.x + s * 0.5, p.y + s * 0.15), Vector2(p.x + s * 0.9, p.y + s * 0.5), Vector2(p.x + s * 0.5, p.y + s * 0.85)]), ink, 2.0, true)
		"hold":
			draw_line(Vector2(p.x + s * 0.2, p.y), Vector2(p.x + s * 0.2, p.y + s), ink, 2.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(p.x + s * 0.25, p.y + s * 0.05), Vector2(p.x + s * 0.95, p.y + s * 0.25), Vector2(p.x + s * 0.25, p.y + s * 0.5)]), ink)
		_:
			draw_line(p + Vector2(s * 0.1, s * 0.1), p + Vector2(s * 0.9, s * 0.9), ink, 2.2, true)
			draw_line(p + Vector2(s * 0.9, s * 0.1), p + Vector2(s * 0.1, s * 0.9), ink, 2.2, true)


## The employees following you: a bubble, a short name and a tiny bar each; "+N" past MAX_FOLLOWERS.
func _draw_strip(top: float) -> void:
	var n := follower_list.size()
	var shown := n if n <= MAX_FOLLOWERS else MAX_FOLLOWERS - 1
	var cells := shown + (1 if n > shown else 0)
	var paper := look == Look.PAPER
	var x0 := float(YOU["d"]) * 0.5 - CELL_W * 0.5 + 4.0
	var area := Rect2(Vector2(maxf(0.0, x0 - 4.0), top), Vector2(CELL_W * cells + 8.0, STRIP_H))
	if paper:
		_paper(area, FormTheme.carbon("canary"))
	else:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.04, 0.07, 0.5)
		sb.set_corner_radius_all(10)
		draw_style_box(sb, area)
	var nf := FormTheme.typed_font() if paper else FormTheme.label_font()
	for i in shown:
		var e := follower_list[i]
		var cx := x0 + CELL_W * (i + 0.5)
		var c := Vector2(cx, top + 6.0 + BUBBLE_D * 0.5)
		var fighting := PartyInfo.employee_state(e) == "fight"
		var r := BUBBLE_D * 0.5
		draw_circle(c, r, Color(0.2, 0.22, 0.26) if not paper else Color(1, 1, 1, 0.6))
		var tex := headshots.texture("emp:%s:%d" % [e.style, e.variant]) if headshots != null else null
		if tex != null:
			_disc(tex, c, r - 1.0, 0.9)
		else:
			var letter := PartyInfo.short_name(e.display_name).substr(0, 1).to_upper()
			var lf := FormTheme.label_font(true)
			var w := lf.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(lf, c + Vector2(-w * 0.5, 6.5), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE if not paper else FormTheme.TYPED)
		var ring := DOWN_RED if fighting else (Color(1, 1, 1, 0.55) if not paper else FormTheme.INK)
		draw_arc(c, r - 1.0, 0, TAU, 40, ring, 2.5 if fighting else 1.5, true)
		if fighting:
			_badge("FIGHT", c + Vector2(0, r * 0.75), r * 0.85, DOWN_RED, Color.WHITE)
		var fit := fit_name(PartyInfo.short_name(e.display_name), nf, 15, CELL_W - 4.0)
		var tw := nf.get_string_size(fit["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fit["size"]).x
		var at := Vector2(cx - tw * 0.5, top + BUBBLE_D + 24.0)
		if paper:
			draw_string(nf, at, fit["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fit["size"], FormTheme.TYPED)
		else:
			_outlined(nf, at, fit["text"], fit["size"], Color(1, 1, 1, 0.9), 3)
		var bar := Rect2(cx - 22.0, top + BUBBLE_D + 30.0, 44.0, 5.0)
		var f := clampf(e.hp / maxf(1.0, e.max_hp), 0.0, 1.0)
		draw_rect(bar, Color(0, 0, 0, 0.55) if not paper else Color(1, 1, 1, 0.5))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), (HP_LOW if f < 0.3 else HP_GREEN) if not paper else (FormTheme.RED if f < 0.3 else FormTheme.GREEN_INK))
		if paper:
			draw_rect(bar, FormTheme.INK, false, 1.0)
	if n > shown:
		var cx := x0 + CELL_W * (shown + 0.5)
		var c := Vector2(cx, top + 6.0 + BUBBLE_D * 0.5)
		draw_circle(c, BUBBLE_D * 0.5, Color(0.12, 0.13, 0.17) if not paper else Color(1, 1, 1, 0.6))
		draw_arc(c, BUBBLE_D * 0.5 - 1.0, 0, TAU, 40, Color(1, 1, 1, 0.45) if not paper else FormTheme.INK, 1.5, true)
		var more := "+%d" % (n - shown)
		var lf := FormTheme.label_font(true) if not paper else FormTheme.typed_font()
		var w := lf.get_string_size(more, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(lf, c + Vector2(-w * 0.5, 6.0), more, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE if not paper else FormTheme.TYPED)
		var nf2 := FormTheme.label_font() if not paper else FormTheme.typed_font()
		var tw := nf2.get_string_size("more", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(nf2, Vector2(cx - tw * 0.5, top + BUBBLE_D + 24.0), "more", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.7) if not paper else Color(FormTheme.TYPED, 0.7))


# --- Helpers -------------------------------------------------------------------------------------

## `tex` clipped to a disc at `c`; `crop` < 1 zooms in on the centre.
func _disc(tex: Texture2D, c: Vector2, r: float, crop: float = 1.0) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in _circle.size():
		pts.append(c + _circle[i] * r)
		uvs.append(Vector2(0.5, 0.5) + (_circle_uv[i] - Vector2(0.5, 0.5)) * crop)
	draw_colored_polygon(pts, Color.WHITE, uvs, tex)


## A grey copy of `tex` (a downed hero's face), made once.
func _grey_of(tex: Texture2D) -> Texture2D:
	var id := tex.get_instance_id()
	if _grey.has(id):
		return _grey[id]
	var img := tex.get_image()
	if img == null or img.is_empty():
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			var l := p.r * 0.3 + p.g * 0.59 + p.b * 0.11
			img.set_pixel(x, y, Color(l, l, l * 1.02, p.a))
	var g := ImageTexture.create_from_image(img)
	_grey[id] = g
	return g


func _paper(rect: Rect2, tint: Color) -> void:
	for i in 4:
		var g := float(i) * 2.0
		draw_rect(Rect2(rect.position + Vector2(2, 4) - Vector2(g, g) * 0.8, rect.size + Vector2(g, g) * 1.6), Color(0, 0, 0, 0.08 * (1.0 - i / 4.0)))
	draw_texture_rect(FormTheme.paper_texture(), rect, true, Color(tint, 0.97))
	draw_rect(rect, Color(0.2, 0.25, 0.15, 0.55), false, 1.0)


func _outlined(font: Font, at: Vector2, text: String, fs: int, col: Color, outline: int = 4) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.88))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

class_name PartyFrame
extends Control
## The party HUD, top left (redesigned 2026-10-19; the user picked the clean look with the employee list): one row per
## crew member, yours first and biggest, then the employees following you as a short list of smaller rows.
##
## A HERO ROW, on a dark plate with a faint edge (so it reads over a black void as well as a bright floor):
##   - a round portrait: the player's Steam avatar; without one, and for an AI seat, the hero's headshot (Headshots); a
##     lettered disc while that renders or headless. A ring in the hero's colour.
##   - the name (the Steam name for a person, the hero's name for an AI seat) and, at the right of the same line, the ORDER
##     CHIP: FOLLOW / GO / HOLD / ATTACK for an AI hero (on every machine: Hero.order_state); on your own row GO / ATTACK,
##     outlined and draining, while a crewmate's order marker stands; nothing for another person's hero.
##   - the HP bar, with no numbers (user, 2026-10-19).
##   - DOWN and DAZED on the portrait itself: a bold pill over its lower edge, a grey face and a red ring for down, a
##     throbbing yellow ring for dazed.
##
## NAMES (Steam allows 32 characters): one line. A name wider than its room (the row's text column, less the chip when
## there is one) first shrinks, down to NAME_MIN_SCALE of its size, and is then cut with an ellipsis (fit_name; wide
## glyphs and other scripts measure through the font's system fallbacks the same way).
##
## THE EMPLOYEE LIST (show_followers): every employee following you (PartyInfo.followers), one compact row each under the
## heroes: their face (their model's headshot, or their initial) on the left; on the right the short name ("Gary"), a
## FOLLOW / FIGHT chip and a thin HP bar. At most MAX_FOLLOWERS rows; past that a "+N more" line.
##
## Pure presentation: it reads PartyInfo every frame and writes nothing back.

const MAX_FOLLOWERS := 4            ## employee rows shown; more becomes "+N more"
const NAME_MIN_SCALE := 0.8         ## a long name shrinks to this share of its size before it is cut
const ROW_GAP := 8.0
const LIST_GAP := 10.0
const PAD := 12.0                   ## the follower list box's padding past its bars (a row plate's right end is its curve: plate_rect)
const CHIP_GAP := 10.0              ## between the name and the chip
## Row geometry (canvas units, 1600x900): portrait diameter, row height, text x, name size, chip size, bar width / height,
## the name's baseline and the bar's top (both from the row top), the ring width and the badge size.
const YOU := {"d": 72.0, "h": 80.0, "tx": 88.0, "name": 25, "chip": 15, "bar_w": 250.0, "bar_h": 16.0,
	"name_y": 34.0, "bar_y": 49.0, "ring": 4.0, "badge": 17}
const ALLY := {"d": 52.0, "h": 60.0, "tx": 72.0, "name": 20, "chip": 13, "bar_w": 200.0, "bar_h": 9.0,
	"name_y": 28.0, "bar_y": 38.0, "ring": 3.0, "badge": 14}
const EMP := {"d": 28.0, "h": 34.0, "tx": 56.0, "name": 16, "chip": 12, "bar_w": 150.0, "bar_h": 4.0,
	"name_y": 16.0, "bar_y": 22.0, "ring": 2.0, "badge": 11}
const MORE_H := 24.0
const PORTRAIT_X := 36.0            ## every portrait's centre x: one column of faces

const HP_GREEN := Color(0.3, 0.85, 0.5)
const HP_LOW := Color(0.95, 0.42, 0.3)
const DAZE_YELLOW := Color(1.0, 0.84, 0.2)
const DOWN_RED := Color(0.9, 0.14, 0.11)
const PLATE := Color(0.08, 0.09, 0.13, 0.8)
const PLATE_EDGE := Color(1, 1, 1, 0.2)
## Chips: [fill, text, outline].
const CHIP_COLORS := {
	"follow": [Color(1, 1, 1, 0.1), Color(0.86, 0.89, 0.94), Color(1, 1, 1, 0.38)],
	"go": [Color(0.13, 0.52, 0.58), Color.WHITE, Color(0.45, 0.85, 0.9)],
	"hold": [Color(0.86, 0.6, 0.14), Color(0.13, 0.09, 0.02), Color(1.0, 0.82, 0.4)],
	"attack": [Color(0.8, 0.2, 0.16), Color.WHITE, Color(1.0, 0.5, 0.42)],
	"fight": [Color(0.8, 0.2, 0.16), Color.WHITE, Color(1.0, 0.5, 0.42)],
}

var show_followers := true
var you: Hero = null
var allies: Array[Hero] = []
var headshots: Headshots

var views: Array[Dictionary] = []          ## this frame's hero rows (PartyInfo.hero_view), yours first
var follower_list: Array[Employee] = []    ## this frame's employees, all of them (the list shows MAX_FOLLOWERS)
var _fighting_for_you: Dictionary = {}     ## employee instance id -> true: followed you, then went to FIGHT
var _hp_shown: Dictionary = {}             ## hero instance id -> the trailing "damage" part of the bar
var _grey: Dictionary = {}                 ## texture instance id -> its grey copy (a downed portrait)
var _circle: PackedVector2Array


func _init() -> void:
	name = "PartyFrame"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 48:
		var a := TAU * float(i) / 48.0
		_circle.append(Vector2(cos(a), sin(a)))


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


## A row's plate: a pill from the portrait's centre, inset 4 from the row's top and bottom. Its round right end starts where
## the bar ends, so the square bar never runs into the curve (the user, 2026-10-28: "Stop the bar before the curve").
static func plate_rect(s: Dictionary, top: float) -> Rect2:
	var h := float(s["h"]) - 8.0
	var right := float(s["tx"]) + float(s["bar_w"]) + h * 0.5
	return Rect2(Vector2(PORTRAIT_X, top + 4.0), Vector2(right - PORTRAIT_X, h))


func row_top(i: int) -> float:
	var y := 0.0
	for k in i:
		y += float(spec(k == 0)["h"]) + ROW_GAP
	return y


## How many employee rows the list shows (the rest are "+N more").
func followers_shown() -> int:
	return mini(follower_list.size(), MAX_FOLLOWERS)


func list_height() -> float:
	if not show_followers or follower_list.is_empty():
		return 0.0
	return 8.0 + followers_shown() * float(EMP["h"]) + (MORE_H if follower_list.size() > MAX_FOLLOWERS else 0.0) + 4.0


func frame_width() -> float:
	return plate_rect(YOU, 0.0).end.x + 4.0


func frame_height() -> float:
	var h := row_top(views.size())
	if list_height() > 0.0:
		h += LIST_GAP - ROW_GAP + list_height()
	return h


## Returns {text, size, cut}: `text` as drawn at `size`, cut with an ellipsis when even NAME_MIN_SCALE of `base` is too wide.
static func fit_name(text: String, font: Font, base: int, width: float) -> Dictionary:
	var min_size := maxi(8, int(floorf(base * NAME_MIN_SCALE)))
	for fs in range(base, min_size - 1, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
			return {"text": text, "size": fs, "cut": false}
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, min_size).x > width:
		t = t.substr(0, t.length() - 1)
	return {"text": t.strip_edges() + "…", "size": min_size, "cut": true}


static func name_font() -> Font:
	return FormTheme.label_font(true)


## The name's room in a row with no chip (the bar's width: the text column).
static func name_width(is_you: bool) -> float:
	return float(spec(is_you)["bar_w"])


## A chip's size (width, height) for `kind` at `fs`.
static func chip_size(kind: String, fs: int) -> Vector2:
	var tw := FormTheme.label_font(true).get_string_size(kind.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return Vector2(tw + fs * 0.8 + 16.0, fs + 7.0)


# --- Drawing -------------------------------------------------------------------------------------

func _draw() -> void:
	for i in views.size():
		_draw_row(views[i], row_top(i))
	if list_height() > 0.0:
		_draw_list(row_top(views.size()) + LIST_GAP - ROW_GAP)


func _plate(rect: Rect2, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLATE
	sb.set_corner_radius_all(int(radius))
	sb.border_color = PLATE_EDGE
	sb.set_border_width_all(1)
	sb.anti_aliasing = true
	draw_style_box(sb, rect)


func _draw_row(v: Dictionary, top: float) -> void:
	var is_you := bool(v["you"])
	var s := spec(is_you)
	var d: float = s["d"]
	var tx: float = s["tx"]
	var bar_w: float = s["bar_w"]
	var down := bool(v["down"])
	var plate := plate_rect(s, top)
	_plate(plate, plate.size.y * 0.5)
	_draw_portrait(v, Vector2(PORTRAIT_X, top + float(s["h"]) * 0.5), d * 0.5, float(s["ring"]), int(s["badge"]))
	# The chip at the right of the name line; the name gets the rest.
	var chip := str(v["order"]) if not down else ""
	var room := bar_w
	var name_y := top + float(s["name_y"])
	if chip != "":
		var cs := chip_size(chip, int(s["chip"]))
		room -= cs.x + CHIP_GAP
		_chip(chip, Vector2(tx + bar_w, name_y - float(s["name"]) * 0.34), int(s["chip"]), bool(v["human"]), float(v["order_left"]))
	var fit := fit_name(str(v["name"]), name_font(), int(s["name"]), room)
	_outlined(name_font(), Vector2(tx, name_y), fit["text"], fit["size"], Color(1, 1, 1, 0.5) if down else Color.WHITE)
	# The HP bar: no numbers; the portrait says DOWN.
	var f := clampf(float(v["hp"]) / float(v["max_hp"]), 0.0, 1.0)
	var trail := clampf(float(_hp_shown.get((v["hero"] as Hero).get_instance_id(), f)), f, 1.0)
	_bar(Rect2(tx, top + float(s["bar_y"]), bar_w, float(s["bar_h"])), f, trail)


func _bar(bar: Rect2, f: float, trail: float = -1.0) -> void:
	draw_rect(bar, Color(0, 0, 0, 0.6))
	if trail > f:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * trail, bar.size.y)), Color(1, 1, 1, 0.5))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), HP_LOW if f < 0.3 else HP_GREEN)
	draw_rect(bar, Color(1, 1, 1, 0.28), false, 1.0)


## The round portrait: avatar, headshot or initial; the ring; DOWN / DAZED on its lower edge.
func _draw_portrait(v: Dictionary, c: Vector2, r: float, ring: float, badge: int) -> void:
	var col: Color = v["color"]
	var down := bool(v["down"])
	var dazed := bool(v["dazed"])
	var tex: Texture2D = v["avatar"]
	var crop := 1.0
	if tex == null:
		tex = headshots.texture("hero:" + str(v["kit"])) if headshots != null else null
		crop = 0.92
	draw_circle(c, r, col.darkened(0.55))
	if tex != null:
		_disc(tex if not down else _grey_of(tex), c, r - 1.0, crop)
	else:
		_initial(str(v["name"]), c, r, Color(1, 1, 1, 0.92))
	if down:
		draw_circle(c, r, Color(0.08, 0.0, 0.0, 0.35))
	var ring_col := col
	if down:
		ring_col = DOWN_RED
	elif dazed:
		ring_col = DAZE_YELLOW.lerp(Color.WHITE, 0.5 + 0.5 * sin(GameWorld.time * 14.0))
	draw_arc(c, r + 1.0, 0, TAU, 48, Color(0, 0, 0, 0.85), ring + 2.5, true)
	draw_arc(c, r - ring * 0.5 + 1.0, 0, TAU, 48, ring_col, ring, true)
	if down:
		_badge("DOWN", c + Vector2(0, r * 0.66), badge, DOWN_RED, Color.WHITE)
	elif dazed:
		_badge("DAZED", c + Vector2(0, r * 0.66), badge, DAZE_YELLOW, Color(0.08, 0.06, 0.0))


## A bold pill centred at `at` (over a portrait's lower edge): DOWN, DAZED.
func _badge(text: String, at: Vector2, fs: int, fill: Color, ink: Color) -> void:
	var lf := FormTheme.label_font(true)
	var w := lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + fs * 0.9
	var h := fs * 1.32
	var rect := Rect2(at - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(h * 0.5))
	sb.border_color = Color(0, 0, 0, 0.9)
	sb.set_border_width_all(2)
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
	var tw := lf.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(lf, Vector2(at.x - tw * 0.5, at.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


## An order or state chip, right-aligned at `right_mid` (x = right edge, y = vertical middle). `outlined`: a crewmate's
## order to you, its fill draining with `left` (the marker's 12 s).
func _chip(kind: String, right_mid: Vector2, fs: int, outlined: bool, left: float) -> void:
	var lf := FormTheme.label_font(true)
	var cs := chip_size(kind, fs)
	var gw := fs * 0.8
	var rect := Rect2(Vector2(right_mid.x - cs.x, right_mid.y - cs.y * 0.5), cs)
	var cols: Array = CHIP_COLORS.get(kind, CHIP_COLORS["follow"])
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(cs.y * 0.5))
	sb.set_border_width_all(1 if not outlined else 2)
	sb.border_color = cols[2]
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.8) if outlined else cols[0]
	sb.anti_aliasing = true
	draw_style_box(sb, rect)
	if outlined and left > 0.0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(cols[0], 0.9)
		fill.set_corner_radius_all(int(cs.y * 0.5))
		draw_style_box(fill, Rect2(rect.position, Vector2(maxf(cs.y, cs.x * left), cs.y)).grow(-2.0))
	var ink: Color = Color.WHITE if outlined else cols[1]
	_glyph(kind, Rect2(rect.position + Vector2(7.0, (cs.y - gw) * 0.5), Vector2(gw, gw)), ink)
	draw_string(lf, Vector2(rect.position.x + 9.0 + gw, rect.position.y + cs.y * 0.5 + fs * 0.36), kind.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


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


## The employees following you: one compact row each (face | name, chip, thin bar); "+N more" past MAX_FOLLOWERS.
func _draw_list(top: float) -> void:
	var shown := followers_shown()
	var rows_h := shown * float(EMP["h"])
	var more := follower_list.size() - shown
	var tx: float = EMP["tx"]
	var bar_w: float = EMP["bar_w"]
	var box := Rect2(Vector2(PORTRAIT_X - float(EMP["d"]) * 0.5 - 8.0, top), Vector2(tx + bar_w + PAD - (PORTRAIT_X - float(EMP["d"]) * 0.5 - 8.0), list_height()))
	_plate(box, 12.0)
	var y := top + 4.0
	for i in shown:
		var e := follower_list[i]
		var c := Vector2(PORTRAIT_X, y + float(EMP["h"]) * 0.5)
		var r := float(EMP["d"]) * 0.5
		var fighting := PartyInfo.employee_state(e) == "fight"
		draw_circle(c, r, Color(0.2, 0.22, 0.26))
		var tex := headshots.texture("emp:%s:%d" % [e.style, e.variant]) if headshots != null else null
		if tex != null:
			_disc(tex, c, r - 1.0, 0.9)
		else:
			_initial(PartyInfo.short_name(e.display_name), c, r, Color.WHITE)
		draw_arc(c, r, 0, TAU, 40, Color(0, 0, 0, 0.85), 3.5, true)
		draw_arc(c, r - 0.5, 0, TAU, 40, DOWN_RED if fighting else Color(1, 1, 1, 0.6), 2.0, true)
		if e.is_dazed():
			_badge("DAZED", c + Vector2(0, r * 0.7), int(EMP["badge"]), DAZE_YELLOW, Color(0.08, 0.06, 0.0))
		var state := PartyInfo.employee_state(e)
		var cs := chip_size(state, int(EMP["chip"]))
		var name_y := y + float(EMP["name_y"])
		_chip(state, Vector2(tx + bar_w, name_y - float(EMP["name"]) * 0.34), int(EMP["chip"]), false, 0.0)
		var fit := fit_name(PartyInfo.short_name(e.display_name), name_font(), int(EMP["name"]), bar_w - cs.x - CHIP_GAP)
		_outlined(name_font(), Vector2(tx, name_y), fit["text"], fit["size"], Color(1, 1, 1, 0.92), 3)
		_bar(Rect2(tx, y + float(EMP["bar_y"]), bar_w, float(EMP["bar_h"])), clampf(e.hp / maxf(1.0, e.max_hp), 0.0, 1.0))
		y += float(EMP["h"])
	if more > 0:
		_outlined(FormTheme.label_font(), Vector2(tx, top + 4.0 + rows_h + 16.0), "+%d more" % more, 15, Color(1, 1, 1, 0.75), 3)


# --- Helpers -------------------------------------------------------------------------------------

func _initial(text: String, c: Vector2, r: float, col: Color) -> void:
	var lf := FormTheme.label_font(true)
	var letter := text.substr(0, 1).to_upper()
	var fs := int(r * 1.05)
	var w := lf.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(lf, c + Vector2(-w * 0.5, fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## `tex` clipped to a disc at `c`; `crop` < 1 zooms in on the centre.
func _disc(tex: Texture2D, c: Vector2, r: float, crop: float = 1.0) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for p in _circle:
		pts.append(c + p * r)
		uvs.append(Vector2(0.5, 0.5) + p * 0.5 * crop)
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


func _outlined(font: Font, at: Vector2, text: String, fs: int, col: Color, outline: int = 4) -> void:
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.88))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

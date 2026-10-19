class_name DispatchBanner
extends Control
## Dispatch on the crew's headset (docs/design/notes-rethink.md, section 4): a canary strip at the top centre
## with a headset glyph as its frame, so no "Dispatch:" prefix is needed. Canary is dispatch's carbon
## (FormTheme.CARBONS). ONE message in dispatch's voice, one thought (floor 1 tells the incident and what it means for
## the crew; floors 2 and 3 are about that floor). Never a second line.
##
##   banner.show_line("The gates on this floor are feeding the imps problem. Close them and it stops coming.", 7.0)
##
## Pure presentation, LOCAL to each machine. The line is also SPOKEN when its clip was rendered (DispatchVoice,
## assets/audio/dispatch/<key>.ogg; tools/render_dispatch.ps1): a new line cuts the previous clip, a line without a clip
## (or sounds off, as headless) is silent. Each machine plays its own, so nothing here crosses the network.

const WIDTH := 760.0
const TOP := 112.0
const PAD := 18.0
const GLYPH_W := 64.0
const FADE := 0.8
const FONT_SIZE := 27
## The clip plays on the UI bus (Master's only slider is the player's; the clips are already mixed for the radio).
const VOICE_BUS := &"UI"
const VOICE_DB := -2.0

var line := ""
var hold := 0.0             ## seconds left at full strength
var alpha := 0.0
var voiced := 0             ## clips started on this machine (tests, debug)

var _voice: AudioStreamPlayer = null


func _init() -> void:
	name = "DispatchBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	modulate.a = 0.0


## Who may write each var (see Net). All presentation, kept per machine.
func net_fields() -> Dictionary:
	return {"line": Net.LOCAL, "hold": Net.LOCAL, "alpha": Net.LOCAL, "voiced": Net.LOCAL, "_voice": Net.LOCAL}


func show_line(text: String, seconds: float) -> void:
	line = text
	hold = seconds
	alpha = 1.0
	_relayout()
	queue_redraw()
	_speak(text)


## A clip is playing now.
func is_speaking() -> bool:
	return _voice != null and _voice.playing


## Say `text` in dispatch's voice: the previous clip is cut first, then its clip plays if there is one.
func _speak(text: String) -> void:
	if _voice != null:
		_voice.stop()
	if not Sfx.enabled or not is_inside_tree():
		return
	var clip := DispatchVoice.stream_of(text)
	if clip == null:
		return
	if _voice == null:
		_voice = AudioStreamPlayer.new()
		_voice.name = "Voice"
		_voice.bus = VOICE_BUS
		_voice.volume_db = VOICE_DB
		add_child(_voice)
	_voice.stream = clip
	_voice.play()
	voiced += 1


func _process(delta: float) -> void:
	if hold > 0.0:
		hold -= delta
	elif alpha > 0.0:
		alpha = maxf(0.0, alpha - delta / FADE)
	modulate.a = alpha


func _text_w() -> float:
	return WIDTH - GLYPH_W - PAD * 2.0


func _relayout() -> void:
	var h := PAD * 2.0
	h += FormTheme.label_font(true).get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, _text_w(), FONT_SIZE).y
	h = maxf(h, 76.0)
	size = Vector2(WIDTH, h)
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = TOP
	offset_bottom = TOP + h


func _draw() -> void:
	if line == "":
		return
	var r := Rect2(Vector2.ZERO, size)
	for i in 6:
		var g := float(i) * 3.0
		draw_rect(Rect2(Vector2(3, 8) - Vector2(g, g) * 0.8, r.size + Vector2(g, g) * 1.6), Color(0, 0, 0, 0.08 * (1.0 - float(i) / 6.0)))
	draw_texture_rect(FormTheme.paper_texture(), r, true, FormTheme.carbon("canary"))
	draw_rect(Rect2(0, 0, GLYPH_W, r.size.y), Color(FormTheme.INK, 0.92))
	_headset(Vector2(GLYPH_W * 0.5, r.size.y * 0.5))
	var x := GLYPH_W + PAD
	var lf := FormTheme.label_font(true)
	draw_multiline_string(lf, Vector2(x, PAD + lf.get_ascent(FONT_SIZE)), line, HORIZONTAL_ALIGNMENT_LEFT, _text_w(), FONT_SIZE, -1, FormTheme.INK)


## A headset: the band, two ear cups and the boom mic, in paper on the ink panel.
func _headset(c: Vector2) -> void:
	var col := FormTheme.carbon("canary")
	draw_arc(c + Vector2(0, 2), 16.0, PI * 1.08, PI * 1.92, 16, col, 4.0, true)
	draw_rect(Rect2(c + Vector2(-21, -2), Vector2(9, 15)), col)
	draw_rect(Rect2(c + Vector2(12, -2), Vector2(9, 15)), col)
	draw_polyline(PackedVector2Array([c + Vector2(-17, 13), c + Vector2(-14, 21), c + Vector2(-2, 23)]), col, 3.0, true)
	draw_circle(c + Vector2(1, 23), 3.5, col)

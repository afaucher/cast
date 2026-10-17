class_name UsePrompt
extends Node3D
## The one small prompt for everything the player can use: a billboarded slip that floats just above the thing
## itself, a cream paper keycap with the key and then a short verb ("[E] Clock out", "[F] Swap in Grave moss").
## The game owns one per key (E and F) and each frame tells it what that key would act on right now:
## show_at(world point, key, verb), or hide_prompt() when the key would do nothing. It fades in and out over
## FADE_TIME and snaps to a new spot when the target changes.
##
## Constant on-screen size: the slip is a world sprite, but every frame it is rescaled by the camera's orthographic size
## (and nudged by a screen-space offset), so it is the same size at --zoom 6 or 12 as at the default zoom; it is kept
## inside the viewport (EDGE_MARGIN) and above the HUD's spell cards, never under them.
##
## Pure presentation and LOCAL to each machine: it holds nothing the simulation reads and rolls no dice.

const FADE_TIME := 0.15
const WORLD_HEIGHT := 1.2      ## how tall the slip is in the world at the DEFAULT zoom (CameraRig.SIZE_DEFAULT; 1 unit ~ 37 px at 900p)
const EDGE_MARGIN := 12.0      ## the slip stays this far (canvas px) inside the viewport edges
const CARD_MARGIN := 10.0      ## ... and this far above the HUD's spell cards
const PX_H := 56               ## texture height; the width follows the verb
const KEY_PX := 40.0           ## the keycap is a square this big
const VERB_PX := 32
const PAD := 8.0

const SLIP_FILL := Color(0.07, 0.09, 0.1, 0.93)
const SLIP_EDGE := Color(0.96, 0.95, 0.9, 0.55)
const VERB_COLOR := Color(0.97, 0.95, 0.88)
const CAP_EDGE := Color("8a8270")

var key := ""             ## the key shown on the cap ("E", "F")
var verb := ""            ## the short verb after it
var wanted := false       ## true while the prompt is asked to be up (it may still be fading)
var alpha := 0.0          ## 0..1 fade state

var _sprite: Sprite3D
var _viewport: SubViewport
var _slip: Control


func _init() -> void:
	name = "UsePrompt"


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.size = Vector2i(96, PX_H)
	add_child(_viewport)
	_slip = _Slip.new()
	_slip.prompt = self
	_viewport.add_child(_slip)
	_sprite = Sprite3D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.pixel_size = WORLD_HEIGHT / float(PX_H)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.no_depth_test = true
	_sprite.render_priority = 20
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sprite.visible = false
	add_child(_sprite)
	_relayout()


## Who may write each var (see Net). All of it is presentation, kept per machine.
func net_fields() -> Dictionary:
	return {
		"key": Net.LOCAL, "verb": Net.LOCAL, "wanted": Net.LOCAL, "alpha": Net.LOCAL,
		"_sprite": Net.LOCAL, "_viewport": Net.LOCAL, "_slip": Net.LOCAL,
	}


## Float the prompt at `pos` (world) with this key and verb. Fades in if it was hidden.
func show_at(pos: Vector3, new_key: String, new_verb: String) -> void:
	global_position = pos
	wanted = true
	if new_key != key or new_verb != verb:
		key = new_key
		verb = new_verb
		_relayout()


## Nothing to use: fade out (the text stays until it is gone, so it does not blank mid-fade).
func hide_prompt() -> void:
	wanted = false


## True when the prompt is up or on its way up (a target is set).
func is_showing() -> bool:
	return wanted


func _process(delta: float) -> void:
	var goal := 1.0 if wanted else 0.0
	alpha = move_toward(alpha, goal, delta / FADE_TIME)
	if _sprite != null:
		_sprite.visible = alpha > 0.002
		_sprite.modulate.a = alpha
		if _sprite.visible:
			_fit_to_screen()


## The slip's height on screen in canvas pixels: the same fraction of the viewport as at the default zoom.
func screen_height() -> float:
	return get_viewport().get_visible_rect().size.y * WORLD_HEIGHT / CameraRig.SIZE_DEFAULT


## Rescale by the camera's ortho size (so the size on screen never changes with zoom), then clamp into the viewport and
## above the spell cards by shifting the sprite on screen (Sprite3D.offset, in texture pixels).
func _fit_to_screen() -> void:
	var cam := get_viewport().get_camera_3d()
	var k := 1.0
	if cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		k = cam.size / CameraRig.SIZE_DEFAULT
	_sprite.pixel_size = WORLD_HEIGHT / float(PX_H) * k
	_sprite.offset = Vector2.ZERO
	if cam == null or cam.is_position_behind(global_position):
		return
	var vp := get_viewport().get_visible_rect().size
	var tex_to_screen := screen_height() / float(PX_H)    # canvas px per texture px
	var sz := Vector2(float(_viewport.size.x), float(PX_H)) * tex_to_screen
	var at := cam.unproject_position(global_position)
	var r := Rect2(at - sz * 0.5, sz)
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud != null:
		var cards := hud.cards_rect()
		if cards.size.x > 1.0 and r.end.y > cards.position.y - CARD_MARGIN and r.position.y < cards.end.y and r.end.x > cards.position.x and r.position.x < cards.end.x:
			r.position.y = cards.position.y - CARD_MARGIN - sz.y
	r.position.x = clampf(r.position.x, EDGE_MARGIN, maxf(EDGE_MARGIN, vp.x - EDGE_MARGIN - sz.x))
	r.position.y = clampf(r.position.y, EDGE_MARGIN, maxf(EDGE_MARGIN, vp.y - EDGE_MARGIN - sz.y))
	var d := r.get_center() - at
	_sprite.offset = Vector2(d.x, -d.y) / tex_to_screen


func _relayout() -> void:
	if _viewport == null or _slip == null:
		return
	var w := int(ceilf(_Slip.measure(self)))
	_viewport.size = Vector2i(maxi(w, PX_H), PX_H)
	_slip.size = Vector2(_viewport.size)
	_slip.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The slip's picture: a dark rounded pill, the cream keycap, the verb.
class _Slip extends Control:
	var prompt: UsePrompt

	static func measure(p: UsePrompt) -> float:
		var vw := FormTheme.label_font(true).get_string_size(p.verb, HORIZONTAL_ALIGNMENT_LEFT, -1, VERB_PX).x
		return PAD * 3.0 + KEY_PX + vw + PAD

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if prompt == null:
			return
		var pill := StyleBoxFlat.new()
		pill.bg_color = SLIP_FILL
		pill.border_color = SLIP_EDGE
		pill.set_border_width_all(2)
		pill.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(pill, Rect2(Vector2.ZERO, size))
		var cap := Rect2(Vector2(PAD, (size.y - KEY_PX) * 0.5 - 1.0), Vector2(KEY_PX, KEY_PX))
		var sb := StyleBoxFlat.new()
		sb.bg_color = FormTheme.PAPER
		sb.set_corner_radius_all(7)
		sb.border_color = CAP_EDGE
		sb.border_width_bottom = 5
		draw_style_box(sb, cap)
		var kf := FormTheme.typed_font()
		var kw := kf.get_string_size(prompt.key, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		draw_string(kf, Vector2(cap.position.x + (KEY_PX - kw) * 0.5, cap.position.y + 29.0), prompt.key, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, FormTheme.TYPED)
		var lf := FormTheme.label_font(true)
		var base := size.y * 0.5 + VERB_PX * 0.3
		draw_string(lf, Vector2(PAD * 2.0 + KEY_PX, base), prompt.verb, HORIZONTAL_ALIGNMENT_LEFT, -1, VERB_PX, VERB_COLOR)

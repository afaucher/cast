class_name UsePrompt
extends Node3D
## The one small prompt for everything the player can use: a billboarded slip that floats just above the thing
## itself, a cream paper keycap with the key and then a short verb ("[E] Clock out", "[F] Swap in Grave moss").
## The game owns one per key (E and F) and each frame tells it what that key would act on right now:
## show_at(world point, key, verb), or hide_prompt() when the key would do nothing. It fades in and out over
## FADE_TIME and snaps to a new spot when the target changes.
##
## Pure presentation and LOCAL to each machine: it holds nothing the simulation reads and rolls no dice.

const FADE_TIME := 0.15
const WORLD_HEIGHT := 1.2      ## how tall the slip is in the world (the game camera is orthographic: 1 unit ~ 30 px at 720p)
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

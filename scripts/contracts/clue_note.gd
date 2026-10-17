class_name ClueNote
extends Node3D
## A note in the world (docs/design/notes-rethink.md): a pre-outbreak document the crew can snoop on. Plain
## interactable set dressing: anyone near it can read it with E ("[E] Read", "[E] Listen" for a voicemail; see
## game.gd use_target()), nothing tracks who read it, and it pays nothing. The look is per format (NoteModels);
## a small glint twinkles above it so it reads as "you can look at this" without any floating text.
##
##   var note := ClueNote.make(plan_note_entry, run.archetype_id)
##   GameWorld.spawn(note, pos)
##   ClueNote.nearest(hero.global_position)     # the note E would read, or null
##
## The text, format and header are SPAWN data planned from the floor seed (SiteBuilder._plan_notes); the model,
## the glint and reading are LOCAL presentation on each machine.

const GROUP := "clue_notes"
const READ_RANGE := 2.0          ## E reads a note whose centre is this close (flat distance)
const GLINT_PERIOD := 2.6        ## seconds between twinkles
const MODEL_SCALE := 1.2         ## a touch bigger than life, so a note reads at game zoom

var text := ""
var format := "memo"
var header := ""
var kind := "story"
var accent := Color(0.5, 0.5, 0.55)
var yaw := 0.0

var _model: Node3D
var _glint: Sprite3D
var _blink: Node3D
var _t := 0.0

static var _glint_tex: Texture2D = null


## A note node from a SitePlan.notes entry. `archetype` picks the memo's accent colour.
static func make(entry: Dictionary, archetype: String = "") -> ClueNote:
	var n := ClueNote.new()
	n.text = str(entry.get("text", ""))
	n.format = str(entry.get("format", "memo"))
	n.header = str(entry.get("header", ""))
	n.kind = str(entry.get("kind", "story"))
	n.yaw = float(entry.get("yaw", 0.0))
	if archetype != "":
		n.accent = ClientArchetype.accent_of(archetype)
	return n


## Who may write each var (see Net). The note's content comes from the seeded plan; the rest is presentation.
func net_fields() -> Dictionary:
	return {
		"text": Net.SPAWN, "format": Net.SPAWN, "header": Net.SPAWN, "kind": Net.SPAWN, "accent": Net.SPAWN, "yaw": Net.SPAWN,
		"_model": Net.LOCAL, "_glint": Net.LOCAL, "_blink": Net.LOCAL, "_t": Net.LOCAL,
	}


func _ready() -> void:
	name = "Note_%s" % format
	add_to_group(GROUP)
	_model = NoteModels.build(format, accent)
	_model.rotation_degrees.y = yaw
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	_blink = _model.get_node_or_null("Blink")
	_glint = Sprite3D.new()
	_glint.texture = _glint_texture()
	_glint.pixel_size = 0.012
	_glint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glint.shaded = false
	_glint.no_depth_test = true
	_glint.render_priority = 10
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.modulate = Color(1.0, 0.95, 0.75, 0.0)
	_glint.position = Vector3(0.0, NoteModels.height(format) * MODEL_SCALE + 0.25, 0.0)
	add_child(_glint)
	# stagger the twinkles by position, so a room with two notes does not pulse in step
	_t = fmod(absf(global_position.x * 0.37 + global_position.z * 0.61), GLINT_PERIOD)


func _process(delta: float) -> void:
	_t += delta
	var ph := fmod(_t, GLINT_PERIOD) / GLINT_PERIOD
	# a quick twinkle (grow, spin, fade) at the start of each period, then rest
	var k := clampf(ph / 0.22, 0.0, 1.0)
	var a := sin(k * PI) if ph < 0.22 else 0.0
	if _glint != null:
		_glint.modulate.a = 0.9 * a
		_glint.scale = Vector3.ONE * (0.6 + 0.6 * a)
		_glint.rotation.z = k * 0.8
	if _blink != null:
		_blink.visible = fmod(_t, 1.0) < 0.55


## Where the use prompt floats.
func prompt_point() -> Vector3:
	return global_position + Vector3(0.0, NoteModels.height(format) * MODEL_SCALE + 0.9, 0.0)


## The use prompt's verb ("Read", "Listen").
func verb() -> String:
	return NoteCopy.verb_of(format)


## The note nearest `pos` within READ_RANGE (flat distance), or null.
static func nearest(pos: Vector3, max_range: float = READ_RANGE) -> ClueNote:
	if GameWorld.root == null:
		return null
	var best: ClueNote = null
	var best_d := max_range
	for n in GameWorld.root.get_tree().get_nodes_in_group(GROUP):
		var note := n as ClueNote
		if note == null or not note.is_inside_tree():
			continue
		var d := Vector2(note.global_position.x - pos.x, note.global_position.z - pos.z).length()
		if d <= best_d:
			best_d = d
			best = note
	return best


## A soft four-point star, made once.
static func _glint_texture() -> Texture2D:
	if _glint_tex != null:
		return _glint_tex
	const N := 64
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var c := (N - 1) * 0.5
	for y in N:
		for x in N:
			var dx := absf(float(x) - c) / c
			var dy := absf(float(y) - c) / c
			var star := maxf(0.0, 1.0 - dx * 9.0 - dy * 1.1) + maxf(0.0, 1.0 - dy * 9.0 - dx * 1.1)
			var core := maxf(0.0, 1.0 - sqrt(dx * dx + dy * dy) * 2.6)
			var v := clampf(star + core * core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, v))
	_glint_tex = ImageTexture.create_from_image(img)
	return _glint_tex

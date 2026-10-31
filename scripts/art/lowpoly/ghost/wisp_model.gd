class_name WispModel
extends MonsterModel
## A free ghost in the game (docs/design/haunted-build-plan.md, "H5 as built"): the look test's wisp (ghost-look.md, GhostBody
## "wisp": a translucent head with two dark eyes and a small round mouth, a tail of puffs trailing behind it, a small light in
## its colour) in the rim look the user picked ("The rim look is really good. Especially as a wisp."), as a monster model:
## kind "wisp" (Wisp). Hard to see by design: soft strength, pale blue.
##   It hovers HOVER over the floor, bobbing; its tail trails behind it (local +Z: the Monster turns the Visual to its
##   heading), longer and flatter the faster it goes, a sideways wave running down it. It has no wind-up or strike (a wisp
##   never attacks). Downed (it dies): the tail falls in on the head, which sinks (the Wisp fades it out).
## Its material is the wisp's glow (GhostLook.WISP_SHADER) with the monsters' hooks added (a hit flash, the downed grey), so
## Monster's tint and fade work on it. Parts: head, puff_0 .. puff_4. Cosmetic only (LOCAL).

const PART_NAMES: Array[String] = ["head", "puff_0", "puff_1", "puff_2", "puff_3", "puff_4"]
const HOVER := GhostBody.HOVER
const TAIL := GhostBody.TAIL
const TAIL_STEP := GhostBody.TAIL_STEP
const MODEL_SCALE := 1.0

## The wisp shader plus the monster hooks (tint for the hit flash, desat for the downed grey, glow_gain kept for the hooks).
const _HOOKS := "uniform vec4 tint_color : source_color = vec4(1.0);\nuniform float tint_k = 0.0;\nuniform float desat = 0.0;\n" \
		+ "uniform float glow_gain = 1.0;\nvoid fragment() {"

## Seen by a hero in ghost form (GhostSpell, H7): this strength instead of GhostLook's (the look test's "strong").
const CLEAR_STRENGTH := "strong"

static var _shader: Shader

var phase := 0.0
var light: OmniLight3D
## Shown clearly (set_clear): this screen's own hero is in ghost form.
var clear := false
var _lit := true                 ## set_light: false while hidden inside a host


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = GhostLook.WISP_SHADER.replace("void fragment() {", _HOOKS).replace(
				"\tALBEDO = mix(body, vec3(0.03, 0.035, 0.05), eye);",
				"\tbody = mix(body, vec3(dot(body, vec3(0.333))), desat);\n\tALBEDO = mix(body, vec3(0.03, 0.035, 0.05), eye) + tint_color.rgb * tint_k;").replace(
				"\tALPHA = clamp(mix(", "\tALPHA = clamp(tint_k * 0.6 + mix(")
	return _shader


func _init() -> void:
	name = "WispModel"
	scale = Vector3.ONE * MODEL_SCALE
	_mat = ShaderMaterial.new()
	_mat.shader = shader()
	_mat.set_shader_parameter("glow_gain", GLOW_GAIN)
	_base_scale = scale
	monster_kind = "wisp"
	ui_height = HOVER + 0.4
	glow_flare = 0.0
	var head := MeshInstance3D.new()
	head.name = "head"
	head.mesh = GhostBody._head_soup().to_mesh(0.0)
	head.material_override = _mat
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	parts["head"] = head
	for i in TAIL:
		var p := MeshInstance3D.new()
		p.name = "puff_%d" % i
		var r := 0.2 * pow(0.8, float(i))
		p.mesh = LowPoly.boulder(Vector3(r, r * 0.9, r), 0, 0.12, GhostBody.WISP_COLOUR, 611 + i, 0.04).to_mesh(0.0)
		p.material_override = _mat
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		parts[p.name] = p
	light = OmniLight3D.new()
	light.name = "WispLight"
	light.omni_range = 2.8
	light.omni_attenuation = 1.6
	light.light_specular = 0.0
	light.shadow_enabled = false
	head.add_child(light)
	refresh()
	apply_idle(0.0)


func _ready() -> void:
	super._ready()
	add_to_group(GhostLook.GROUP)


## Dress for GhostLook's strength and colour now (CLEAR_STRENGTH while `clear`), always in the rim look (the user's pick).
func refresh() -> void:
	var was := GhostLook.look
	var was_s := GhostLook.strength
	GhostLook.look = "rim"
	if clear:
		GhostLook.strength = CLEAR_STRENGTH
	GhostLook.dress(_mat, true, phase)
	var s := GhostLook.strength_now()
	GhostLook.look = was
	GhostLook.strength = was_s
	light.light_color = GhostLook.color_now()
	light.light_energy = float(s["light"])
	light.visible = float(s["light"]) > 0.0 and not _downed and _lit


## Show it clearly (a hero on this screen is in ghost form: GhostSpell) or as GhostLook has it. Cosmetic.
func set_clear(on: bool) -> void:
	if on == clear:
		return
	clear = on
	refresh()


## The hover, the bob and the tail behind it (local +Z), stretched by its speed.
func apply_idle(t: float, speed: float = 0.0) -> void:
	if _downed:
		return
	var run := clampf(speed / 3.0, 0.0, 1.0)
	var head := parts["head"] as Node3D
	var y := HOVER + 0.10 * sin(t * 1.7) - 0.08 * run
	head.position = Vector3(0.0, y, 0.0)
	head.rotation = Vector3(-0.3 * run + 0.05 * sin(t * 1.1), 0.08 * sin(t * 0.7), 0.06 * sin(t * 1.3))
	var step := TAIL_STEP * (1.0 + 0.7 * run)
	for i in TAIL:
		var k := float(i + 1)
		var p := parts["puff_%d" % i] as Node3D
		p.position = Vector3((0.06 + 0.04 * run) * k * sin(t * 2.4 - k * 0.9), y - (0.1 + 0.08 * k) * (1.0 - 0.6 * run), 0.12 + step * k)
		p.rotation = Vector3.ZERO


## Dying: the tail falls in on the head and it sinks; the light goes out.
func _slump() -> void:
	var head := parts["head"] as Node3D
	head.position = Vector3(0.0, HOVER * 0.45, 0.0)
	head.rotation = Vector3(0.6, 0.0, 0.3)
	for i in TAIL:
		(parts["puff_%d" % i] as Node3D).position = Vector3(0.0, HOVER * 0.4 - 0.05 * float(i), 0.05 * float(i))
	light.visible = false


## A hidden wisp (inside a host) casts no light.
func set_light(on: bool) -> void:
	_lit = on
	light.visible = on and not _downed and light.light_energy > 0.0

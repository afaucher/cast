class_name NoteModels
extends RefCounted
## The in-world look of each note format (docs/design/notes-rethink.md, section 2). Same kit as DecorModels:
## LowPoly soup, MonsterMaterial (ink outline, amber rim, emissive faces = vertex alpha 0.5), origin at the base
## centre, FRONT = +Z. Each format reads as its own object at game zoom, so you can tell a voicemail from a sign
## before reading it:
##   sticky     a sticky-note cube with loose yellow squares around it
##   report     a clipboard on a bankers box
##   sign       a white A-frame floor sign with a hazard-stripe band and "NOTICE"
##   voicemail  a desk phone on a side table, its message light blinking red ("Blink" child, see ClueNote)
##   memo       a letterhead sheet on a small marble plinth, the client's accent colour on the band
##   complaint  a pink form pinned to a cork board on an easel
## Cosmetic only: no randomness (PropModels' face jitter is seeded from the format name).

const YELLOW := Color(0.98, 0.84, 0.24)
const PAPER := Color(0.95, 0.94, 0.9)
const PINK := Color(0.96, 0.66, 0.66)
const CORK := Color(0.72, 0.52, 0.32)
const CARDBOARD := Color(0.78, 0.62, 0.4)
const HAZARD := Color(0.98, 0.8, 0.1)
const INK := Color(0.12, 0.12, 0.16)
const RED := Color(1.0, 0.16, 0.12)

## Height of the model's top (the glint and the use prompt float above it).
const HEIGHTS := {"sticky": 0.3, "report": 0.55, "sign": 1.0, "voicemail": 0.8, "memo": 0.85, "complaint": 1.2}


static func height(format: String) -> float:
	return float(HEIGHTS.get(format, 0.6))


static func build(format: String, accent: Color = Color(0.5, 0.5, 0.55)) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var s := LowPoly.Soup.new(11, 0.05)
	PropModels._seed = int(format.hash() % 9973)
	match format:
		"sticky": _sticky(s)
		"report": _report(s)
		"sign": _sign(s)
		"voicemail": _voicemail(s)
		"complaint": _complaint(s)
		_: _memo(s, accent)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = s.to_mesh()
	var mat := MonsterMaterial.make(2.0)
	mat.set_shader_parameter("glow_gain", 1.5)
	mi.material_override = mat
	root.add_child(mi)
	match format:
		"sign":
			# on the face, between the band and the lines, and narrower than the panel (34 ran off its edges)
			root.add_child(_label("NOTICE", sign_front(0, 0.17, 0.023), Vector3(-SIGN_TILT, 0, 0), 22))
		"voicemail":
			var blink := MeshInstance3D.new()
			blink.name = "Blink"
			var bm := BoxMesh.new()
			bm.size = Vector3(0.08, 0.04, 0.08)
			blink.mesh = bm
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = RED
			m.emission_enabled = true
			m.emission = RED
			m.emission_energy_multiplier = 2.5
			blink.material_override = m
			blink.position = Vector3(0.12, 0.73, 0.1)
			root.add_child(blink)
	return root


static func _b(s: LowPoly.Soup, size: Vector3, pos: Vector3, col: Color, rot: Vector3 = Vector3.ZERO) -> void:
	PropModels.box(s, size, pos, col, rot)


static func _rod(s: LowPoly.Soup, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	PropModels.rod(s, a, b, r, r, 6, col)


static func _label(text: String, pos: Vector3, rot: Vector3, size: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0065
	l.shaded = false
	l.modulate = INK
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = rot
	return l


static func _sticky(s: LowPoly.Soup) -> void:
	# the pad: a cube of stacked squares, a little darker toward the bottom
	_b(s, Vector3(0.42, 0.24, 0.42), Vector3(0, 0.12, 0), YELLOW.darkened(0.12), Vector3(0, 12, 0))
	_b(s, Vector3(0.43, 0.02, 0.43), Vector3(0, 0.25, 0), YELLOW, Vector3(0, 12, 0))
	# loose squares around it, one with scribbles
	_b(s, Vector3(0.38, 0.015, 0.38), Vector3(0.42, 0.01, 0.2), YELLOW, Vector3(0, -20, 0))
	_b(s, Vector3(0.38, 0.015, 0.38), Vector3(-0.38, 0.01, 0.28), YELLOW.lightened(0.05), Vector3(0, 35, 0))
	_b(s, Vector3(0.38, 0.015, 0.38), Vector3(-0.05, 0.01, -0.45), YELLOW, Vector3(0, 5, 0))
	for i in 3:
		_b(s, Vector3(0.24 - 0.05 * i, 0.012, 0.03), Vector3(0.42 - 0.02 * i, 0.022, 0.12 + 0.08 * i), INK, Vector3(0, -20, 0))
	# a pen
	_rod(s, Vector3(-0.32, 0.03, -0.12), Vector3(0.0, 0.03, -0.28), 0.025, Color(0.15, 0.3, 0.75))


static func _report(s: LowPoly.Soup) -> void:
	# the bankers box
	_b(s, Vector3(0.66, 0.38, 0.48), Vector3(0, 0.19, 0), CARDBOARD)
	_b(s, Vector3(0.7, 0.06, 0.52), Vector3(0, 0.38, 0), CARDBOARD.darkened(0.12))
	_b(s, Vector3(0.22, 0.12, 0.02), Vector3(0, 0.2, 0.245), PAPER)      # the label on its front
	# the clipboard on top, at an angle
	var rot := Vector3(0, -14, 0)
	_b(s, Vector3(0.5, 0.03, 0.66), Vector3(0.02, 0.43, 0.0), PropModels.WOOD, rot)
	_b(s, Vector3(0.42, 0.012, 0.54), Vector3(0.02, 0.45, 0.03), PAPER, rot)
	_b(s, Vector3(0.2, 0.05, 0.08), Vector3(0.0, 0.47, -0.27), PropModels.IRON_LT, rot)
	for i in 4:
		_b(s, Vector3(0.3, 0.008, 0.025), Vector3(0.02 + 0.015 * i, 0.46, -0.1 + 0.1 * i), INK.lightened(0.25), rot)
	# a red stamp blot
	_b(s, Vector3(0.1, 0.009, 0.07), Vector3(-0.06, 0.462, 0.2), RED.darkened(0.2), rot)


## A point on the sign's tilted front face: `v` up the panel from its centre, `d` out from its mid-plane (the panel is
## 0.04 thick, so its face is at d = 0.02). Everything on the face sits on it (the band, the lines and NOTICE used to
## float in front of it: user, 2026-10-21).
static func sign_front(x: float, v: float, d: float) -> Vector3:
	var up := Vector3(0, cos(deg_to_rad(SIGN_TILT)), -sin(deg_to_rad(SIGN_TILT)))
	var out := Vector3(0, sin(deg_to_rad(SIGN_TILT)), cos(deg_to_rad(SIGN_TILT)))
	return SIGN_CENTRE + Vector3(x, 0, 0) + up * v + out * d


const SIGN_TILT := 12.0
const SIGN_CENTRE := Vector3(0, 0.48, 0.13)


static func _sign(s: LowPoly.Soup) -> void:
	var white := Color(0.96, 0.96, 0.94)
	_b(s, Vector3(0.56, 0.9, 0.04), SIGN_CENTRE, white, Vector3(-SIGN_TILT, 0, 0))
	_b(s, Vector3(0.56, 0.9, 0.04), Vector3(0, 0.48, -0.13), white.darkened(0.1), Vector3(SIGN_TILT, 0, 0))
	# the hazard band across the top of the front panel, inside its edges, on its face
	for i in 6:
		var x := -0.225 + 0.09 * float(i)
		_b(s, Vector3(0.09, 0.1, 0.012), sign_front(x, 0.34, 0.027), HAZARD if i % 2 == 0 else INK, Vector3(-SIGN_TILT, 0, 0))
	# text lines under NOTICE
	for i in 3:
		_b(s, Vector3(0.38 - 0.08 * float(i % 2), 0.035, 0.01), sign_front(0, 0.0 - 0.1 * float(i), 0.026), INK, Vector3(-SIGN_TILT, 0, 0))
	_b(s, Vector3(0.6, 0.06, 0.2), Vector3(0, 0.95, 0.0), white.darkened(0.2))
	_b(s, Vector3(0.56, 0.04, 0.4), Vector3(0, 0.02, 0.0), INK.lightened(0.15))


static func _voicemail(s: LowPoly.Soup) -> void:
	# a side table
	_b(s, Vector3(0.62, 0.05, 0.5), Vector3(0, 0.6, 0), PropModels.WOOD)
	for sx: float in [-0.25, 0.25]:
		for sz: float in [-0.19, 0.19]:
			_b(s, Vector3(0.05, 0.58, 0.05), Vector3(sx, 0.29, sz), PropModels.WOOD_DK)
	# the desk phone: body, keypad, handset
	_b(s, Vector3(0.38, 0.09, 0.3), Vector3(0, 0.67, 0.02), Color(0.16, 0.17, 0.2))
	_b(s, Vector3(0.14, 0.012, 0.12), Vector3(-0.07, 0.72, 0.07), Color(0.75, 0.76, 0.8))
	_b(s, Vector3(0.36, 0.06, 0.09), Vector3(0, 0.74, -0.08), Color(0.12, 0.13, 0.16))
	_b(s, Vector3(0.08, 0.06, 0.1), Vector3(-0.15, 0.76, -0.08), Color(0.12, 0.13, 0.16))
	_b(s, Vector3(0.08, 0.06, 0.1), Vector3(0.15, 0.76, -0.08), Color(0.12, 0.13, 0.16))
	# a little notepad beside it
	_b(s, Vector3(0.14, 0.02, 0.18), Vector3(0.21, 0.635, 0.12), PAPER, Vector3(0, 10, 0))


static func _memo(s: LowPoly.Soup, accent: Color) -> void:
	# a marble plinth
	_b(s, Vector3(0.5, 0.7, 0.4), Vector3(0, 0.35, 0), PropModels.MARBLE)
	_b(s, Vector3(0.58, 0.06, 0.48), Vector3(0, 0.03, 0), PropModels.MARBLE_DK)
	_b(s, Vector3(0.58, 0.05, 0.48), Vector3(0, 0.72, 0), PropModels.GOLD_DK)
	# the letterhead sheet, tilted toward the reader, the client's colour on its band
	var rot := Vector3(16, 0, 0)
	_b(s, Vector3(0.4, 0.012, 0.5), Vector3(0, 0.79, 0.0), PAPER, rot)
	_b(s, Vector3(0.4, 0.016, 0.1), Vector3(0, 0.81, -0.18), accent, rot)
	for i in 4:
		_b(s, Vector3(0.28 - 0.05 * float(i % 2), 0.01, 0.022), Vector3(-0.02, 0.785 + 0.025 * float(i), -0.05 + 0.08 * float(i)), INK.lightened(0.3), rot)


static func _complaint(s: LowPoly.Soup) -> void:
	# the easel
	_rod(s, Vector3(-0.32, 0.0, 0.12), Vector3(-0.08, 1.15, 0.0), 0.03, PropModels.WOOD_DK)
	_rod(s, Vector3(0.32, 0.0, 0.12), Vector3(0.08, 1.15, 0.0), 0.03, PropModels.WOOD_DK)
	_rod(s, Vector3(0.0, 0.0, -0.36), Vector3(0.0, 1.1, -0.02), 0.03, PropModels.WOOD_DK)
	_b(s, Vector3(0.72, 0.04, 0.08), Vector3(0, 0.42, 0.13), PropModels.WOOD_DK)
	# the cork board, the pink form and a couple of scraps, pinned
	var rot := Vector3(-8, 0, 0)
	_b(s, Vector3(0.74, 0.6, 0.05), Vector3(0, 0.76, 0.1), CORK, rot)
	_b(s, Vector3(0.78, 0.04, 0.07), Vector3(0, 1.07, 0.06), PropModels.WOOD, rot)
	_b(s, Vector3(0.32, 0.42, 0.012), Vector3(-0.08, 0.76, 0.135), PINK, rot)
	for i in 4:
		_b(s, Vector3(0.22, 0.025, 0.008), Vector3(-0.08, 0.88 - 0.07 * float(i), 0.143), INK.lightened(0.3), rot)
	_b(s, Vector3(0.16, 0.18, 0.012), Vector3(0.22, 0.82, 0.13), PAPER, Vector3(-8, 0, 6))
	_b(s, Vector3(0.16, 0.14, 0.012), Vector3(0.2, 0.6, 0.13), YELLOW, Vector3(-8, 0, -5))
	for p: Vector3 in [Vector3(-0.08, 0.95, 0.15), Vector3(0.22, 0.9, 0.145), Vector3(0.2, 0.66, 0.15)]:
		PropModels.ball(s, Vector3(0.025, 0.025, 0.025), p, RED, 0, 0.0)

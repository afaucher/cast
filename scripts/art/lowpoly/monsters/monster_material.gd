class_name MonsterMaterial
extends RefCounted
## The hero look (LowPolyMaterial: toon bands, amber rim, ink outline) plus the ENEMY language:
##  - faces painted with vertex alpha < 0.75 (MonsterModel.glow(colour) = alpha 0.5) are EMISSIVE
##    (ember eyes, lava cracks, glowing teeth). Heroes stay matte; only monsters glow.
##  - tint_color / tint_k: an additive hit-flash / windup pulse (Monster._apply_tint calls set_tint).
##  - glow_gain: how hot the glow runs (above 1.0 so it blooms; 0 when downed).
## The shader is the heroes' own source text with three patches, so the two stay in step.

const GLOW_ALPHA := 0.5

static var _shader: Shader


static func make(outline_px: float = 2.4) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = _code()
	var m := ShaderMaterial.new()
	m.shader = _shader
	if outline_px > 0.0:
		m.next_pass = LowPolyMaterial.outline(outline_px)
	return m


static func _code() -> String:
	var code: String = LowPolyMaterial.SHADER
	code = code.replace("varying vec3 wnormal;",
			"uniform vec4 tint_color : source_color = vec4(1.0, 0.25, 0.0, 1.0);\n"
			+ "uniform float tint_k = 0.0;         // additive flash / windup pulse\n"
			+ "uniform float glow_gain = 1.8;      // emissive faces (vertex alpha < 0.75)\n"
			+ "varying vec3 wnormal;")
	# Match the line's prefix only: LowPolyMaterial appends its own spell glow (+ glow_color * glow_strength) after it, and
	# matching the whole old line silently stopped patching once it did (the monster glow went flat).
	var at := "EMISSION = min(e, vec3(0.95))"
	assert(code.contains(at), "MonsterMaterial: LowPolyMaterial's EMISSION line moved")
	code = code.replace(at,
			"float glow_m = 1.0 - step(0.75, COLOR.a);\n"
			+ "\tEMISSION = min(e, vec3(0.95)) * (1.0 - glow_m) + c * glow_m * glow_gain + tint_color.rgb * tint_k * 0.8")
	return code

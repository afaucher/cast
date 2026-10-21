extends RefCounted
## Gator LOOK-DEV (docs/design/gator-look.md): the looks the lab compares, as GatorModel specs. "current" is the old model
## (SewerProps "gator", which the lava salamander still uses); "v1" (Plated) and "v2" (Toon) are the rebuilds not chosen;
## "v3" (Mugger) is the game's gator as built (GatorModel.game_spec(): the user's pick, 2026-10-20). LAB ONLY, no
## class_name (the lab preloads it).
##
##   const GatorLooks := preload("res://scripts/art/lowpoly/props/gator_looks.gd")
##   add_child(GatorLooks.build("v1", {"bend": 20.0, "swim": true, "wave": 30.0}))
##
## The pose keys are GatorModel.set_pose's: bend, wave, phase, gait (-1 at rest), swim, head_yaw, head_pitch, jaw, breath.

const SewerProps := preload("res://scripts/art/lowpoly/props/sewer_props.gd")

const VARIANTS: Array[String] = ["current", "v1", "v2", "v3"]
const NAMES := {"current": "Old model", "v1": "V1 Plated", "v2": "V2 Toon", "v3": "V3 Mugger (game)"}


## The look of `variant` (a GatorModel spec; see GatorModel.game_spec for the keys).
static func spec(variant: String) -> Dictionary:
	match variant:
		"v3":
			return GatorModel.game_spec()
		"v2":
			return {
				"id": "v2",
				"skin": Color(0.27, 0.46, 0.2), "flank": Color(0.55, 0.62, 0.26), "belly": Color(0.96, 0.88, 0.56),
				"dark": Color(0.16, 0.3, 0.13), "eye": Color(1.0, 0.82, 0.18), "claw": Color(0.95, 0.9, 0.72), "vary": 0.05,
				# round: 12 points round the section
				"prof": [Vector2(0, 1), Vector2(0.45, 0.96), Vector2(0.8, 0.82), Vector2(1.0, 0.52), Vector2(0.94, 0.22),
					Vector2(0.62, 0.03), Vector2(0, 0)],
				"body": [Vector4(0.0, 0.2, 0.09, 0.31), Vector4(0.07, 0.25, 0.04, 0.35), Vector4(0.17, 0.32, 0.01, 0.39),
					Vector4(0.27, 0.335, 0.0, 0.4), Vector4(0.37, 0.3, 0.02, 0.38), Vector4(0.47, 0.21, 0.06, 0.33),
					Vector4(0.58, 0.16, 0.08, 0.29), Vector4(0.7, 0.12, 0.1, 0.25), Vector4(0.82, 0.09, 0.11, 0.21),
					Vector4(0.92, 0.065, 0.12, 0.18), Vector4(1.0, 0.03, 0.13, 0.155)],
				# the big head: wide round cheeks, a short deep snout with a fat round tip
				"head": [Vector4(-0.12, 0.19, 0.1, 0.33), Vector4(-0.03, 0.285, 0.1, 0.38), Vector4(0.08, 0.27, 0.11, 0.355),
					Vector4(0.2, 0.22, 0.12, 0.28), Vector4(0.33, 0.2, 0.12, 0.25), Vector4(0.42, 0.18, 0.125, 0.24),
					Vector4(0.47, 0.11, 0.13, 0.21)],
				"jaw": [Vector4(-0.12, 0.18, 0.05, 0.12), Vector4(-0.02, 0.25, 0.03, 0.12), Vector4(0.2, 0.2, 0.05, 0.115),
					Vector4(0.38, 0.17, 0.065, 0.115), Vector4(0.46, 0.1, 0.08, 0.115)],
				"head_prof": [Vector2(0, 1), Vector2(0.5, 0.95), Vector2(0.85, 0.75), Vector2(1.0, 0.4), Vector2(0.92, 0.08), Vector2(0, 0)],
				"hinge": Vector2(-0.1, 0.12), "jaw_max": 38.0,
				"front_u": 0.09, "hind_u": 0.38, "r_front": 0.075, "r_hind": 0.09, "toes": 3, "toe_len": 0.06, "reach": 0.28,
				"eyes": "dome", "scutes": "domes", "nose": "ball", "teeth": "toon", "bands": false, "jit": 0.0,
				"extras": ["spots"], "sides": 6,
			}
	# v1 (and anything else): Plated
	return {
		"id": "v1",
		"skin": Color(0.29, 0.37, 0.19), "flank": Color(0.52, 0.53, 0.28), "belly": Color(0.88, 0.82, 0.56),
		"dark": Color(0.14, 0.18, 0.1), "eye": Color(1.0, 0.74, 0.14), "claw": Color(0.92, 0.88, 0.7), "vary": 0.05,
		# blocky: 10 points round the section, a flat belly and a flat top
		"prof": [Vector2(0, 1), Vector2(0.62, 0.97), Vector2(1.0, 0.55), Vector2(0.9, 0.12), Vector2(0.5, 0.0), Vector2(0, 0)],
		"body": [Vector4(0.0, 0.19, 0.08, 0.3), Vector4(0.07, 0.24, 0.04, 0.34), Vector4(0.17, 0.31, 0.015, 0.37),
			Vector4(0.28, 0.33, 0.01, 0.38), Vector4(0.38, 0.29, 0.03, 0.37), Vector4(0.47, 0.2, 0.06, 0.32),
			Vector4(0.58, 0.15, 0.08, 0.28), Vector4(0.7, 0.105, 0.1, 0.24), Vector4(0.82, 0.07, 0.11, 0.2),
			Vector4(0.92, 0.045, 0.12, 0.17), Vector4(1.0, 0.015, 0.13, 0.145)],
		"head": [Vector4(-0.12, 0.17, 0.1, 0.3), Vector4(-0.01, 0.245, 0.1, 0.33), Vector4(0.1, 0.22, 0.11, 0.28),
			Vector4(0.22, 0.17, 0.12, 0.225), Vector4(0.36, 0.155, 0.12, 0.205), Vector4(0.43, 0.135, 0.12, 0.2),
			Vector4(0.465, 0.085, 0.13, 0.18)],
		"jaw": [Vector4(-0.12, 0.16, 0.04, 0.12), Vector4(0.0, 0.21, 0.03, 0.118), Vector4(0.2, 0.155, 0.05, 0.112),
			Vector4(0.38, 0.13, 0.06, 0.112), Vector4(0.455, 0.08, 0.075, 0.112)],
		"head_prof": [Vector2(0, 1), Vector2(0.7, 0.96), Vector2(1.0, 0.45), Vector2(0.85, 0.0), Vector2(0, 0)],
		"hinge": Vector2(-0.1, 0.12), "jaw_max": 34.0,
		"front_u": 0.08, "hind_u": 0.37, "r_front": 0.07, "r_hind": 0.085, "toes": 4, "toe_len": 0.065, "reach": 0.3,
		"eyes": "turret", "scutes": "plates", "nose": "boss", "teeth": "rows", "bands": true, "jit": 0.0,
		"extras": [], "sides": 6,
	}


## A gator of `variant` in a pose: a GatorModel (the old model: SewerProps "gator", its bend and jaw only).
static func build(variant: String, params: Dictionary = {}) -> Node3D:
	if variant == "current" or not VARIANTS.has(variant):
		return SewerProps.build("gator", {"bend": params.get("bend", 0.0), "jaw": params.get("jaw", 0.0)})
	var m := GatorModel.new(spec(variant))
	m.set_pose(params)
	return m

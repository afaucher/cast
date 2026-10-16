class_name HeroGulp
extends RefCounted
## Gulp, the damp, unbothered frogfolk who joined for the dental plan (stretch hero). A squat
## coral body, a wide mouth, big dopey eyes on top (matte, not glowing), long hind legs, and a
## white hi-vis lanyard. The tongue is the pull ability, so it lives in the "weapon" part.


static func build(f: ToyFigure) -> void:
	var rig := f.rig
	var leg_h := 0.2 * f.lg
	var bh := 0.82 * (0.7 + 0.3 * f.tr)
	var bw := 0.95 * (0.5 + 0.5 * f.wd)
	var belly := Color(0.99, 0.84, 0.70)

	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var leg := f.add("leg_" + side, rig, CharacterKit.shifted(ArtMesh.blob(Vector3(0.28 * f.lm, leg_h + 0.12, 0.40), 2.3), Vector3(0, -leg_h * 0.4, 0.04)), CharacterKit.CORAL, Vector3(0.30 * f.wd * s, leg_h + 0.05, 0.0))
		f.add("foot_" + side, leg, ArtMesh.blob(Vector3(0.36, 0.1, 0.5), 2.4), Color(0.86, 0.38, 0.45), Vector3(0, -leg_h - 0.01, -0.12))

	var body := f.add("body", rig, ArtMesh.blob(Vector3(bw, bh, 0.82 * (0.6 + 0.4 * f.wd)), 2.5), CharacterKit.CORAL, Vector3(0, leg_h + bh * 0.5, 0))
	f.add("belly", body, ArtMesh.blob(Vector3(bw * 0.66, bh * 0.66, 0.4), 2.3), belly, Vector3(0, -bh * 0.08, -0.26))
	f.add("lanyard", body, ArtMesh.lathe(PackedVector2Array([Vector2(0.30, -0.05), Vector2(0.50, -0.05), Vector2(0.50, 0.05), Vector2(0.30, 0.05), Vector2(0.30, -0.05)]), 16),
			CharacterKit.STRIP, Vector3(0, bh * 0.12, 0.0), Vector3.ZERO, Vector3(bw / 0.95, 1.0, 0.86), CharacterKit.STRIP_OPTS)

	var h := f.hd
	var head := f.add("head", body, ArtMesh.blob(Vector3(0.90 * h, 0.52 * h, 0.72 * h), 2.4), CharacterKit.CORAL, Vector3(0, bh * 0.42, -0.10))
	f.add("mouth", head, ArtMesh.blob(Vector3(0.64 * h, 0.07, 0.10), 2.4), Color(0.45, 0.16, 0.16), Vector3(0, -0.05 * h, -0.335 * h))
	var eye := ArtMesh.blob(Vector3(0.34 * h, 0.34 * h, 0.34 * h), 2.0, 0.0, 0, 10, 7)
	f.add("eyes", head, ArtMesh.merge([eye, eye], [ArtMesh.xf(Vector3(-0.26 * h, 0.26 * h, -0.08)), ArtMesh.xf(Vector3(0.26 * h, 0.26 * h, -0.08))]), Color(0.96, 0.95, 0.88))
	var pupil := ArtMesh.blob(Vector3(0.15 * h, 0.17 * h, 0.08), 2.0, 0.0, 0, 8, 6)
	f.add("pupils", head, ArtMesh.merge([pupil, pupil], [ArtMesh.xf(Vector3(-0.26 * h, 0.27 * h, -0.235 * h)), ArtMesh.xf(Vector3(0.26 * h, 0.27 * h, -0.235 * h))]), CharacterKit.EYE)

	f.add("weapon", head, ArtMesh.tube([Vector3(0, 0, 0), Vector3(0, -0.02, -0.12), Vector3(0, -0.06, -0.26)], 0.045, 0.065, 6), Color(0.88, 0.30, 0.42), Vector3(0, -0.06 * h, -0.30 * h))
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := f.add("arm_" + side, body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.20 * f.lm, 0.50, 0.20 * f.lm), 2.3), Vector3(0, -0.20, 0)), CharacterKit.CORAL, Vector3((bw * 0.5 - 0.02) * s, bh * 0.12, -0.05), Vector3(0, 0, 14 * s))
		f.add("hand_" + side, arm, ArtMesh.blob(Vector3(0.20, 0.12, 0.22), 2.3), Color(0.86, 0.38, 0.45), Vector3(0, -0.46, 0))

	f.idle_fn = Callable(HeroGulp, "idle")
	f.pose_fn = Callable(HeroGulp, "pose")


static func idle(f: ToyFigure, t: float) -> void:
	f.rot("head", Vector3(3.0 * sin(t * 1.1), 5.0 * sin(t * 0.5), 0))
	f.rot("eyes", Vector3(0, 0, 0))
	f.shift("belly", Vector3(0, 0.015 * sin(t * 4.0), 0))


static func pose(f: ToyFigure, pose_name: StringName) -> void:
	match pose_name:
		&"melee":     # slap
			f.put("body", Vector3(-12, -15, 0))
			f.rot("arm_r", Vector3(110, 0, 10))
		&"secondary":   # tongue out
			f.put("body", Vector3(-6, 0, 0))
			f.rot("arm_r", Vector3(40, 0, 10))
			f.shift("weapon", Vector3(0, 0.0, -0.45))
			f.get_part("weapon").scale = Vector3(1, 1, 3.0)

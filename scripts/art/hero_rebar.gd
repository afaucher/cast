class_name HeroRebar
extends RefCounted
## Rebar, the foundation stone that walked off the job: a wide, lumpy PALE SANDSTONE boulder
## (never slate, which would vanish into the dark hex columns) with a moss-green cap, a tiny
## yellow hard hat and a hi-vis belt. No glowing eyes. The shoulder boulder is its Bowl ammo.


static func build(f: ToyFigure) -> void:
	var rig := f.rig
	var leg_h := 0.20 * f.lg
	var bh := 1.18 * (0.75 + 0.25 * f.tr)
	var bw := 1.42 * (0.6 + 0.4 * f.wd)
	var bd := 1.28 * (0.6 + 0.4 * f.wd)

	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		f.add("leg_" + side, rig, CharacterKit.shifted(ArtMesh.blob(Vector3(0.46 * f.lm, leg_h + 0.14, 0.52 * f.lm), 2.6, 0.08, 3 + s, 12, 8), Vector3(0, -leg_h * 0.5 + 0.04, -0.02)),
				CharacterKit.SANDSTONE_DK, Vector3(0.32 * f.wd * s, leg_h, 0))

	var body := f.add("body", rig, ArtMesh.blob(Vector3(bw, bh, bd), 2.3, 0.12, 7), CharacterKit.SANDSTONE, Vector3(0, leg_h + bh * 0.5 - 0.06, 0))
	# moss cap: the big top-visible hero-coloured shape, with soft clumps (not spikes)
	var clump := ArtMesh.blob(Vector3(0.26, 0.2, 0.26), 2.2, 0.1, 5, 9, 6)
	var moss_mesh := ArtMesh.merge([ArtMesh.blob(Vector3(bw * 0.80, 0.46, bd * 0.80), 2.2, 0.14, 11), clump, clump, clump],
			[ArtMesh.xf(Vector3.ZERO), ArtMesh.xf(Vector3(-0.34, 0.20, 0.18)), ArtMesh.xf(Vector3(0.30, 0.19, 0.30)), ArtMesh.xf(Vector3(0.02, 0.17, 0.46))])
	f.add("moss", body, moss_mesh, CharacterKit.MOSS, Vector3(0, bh * 0.43, 0.16))
	f.add("belt", body, ArtMesh.lathe(PackedVector2Array([Vector2(0.60, -0.045), Vector2(0.77, -0.045), Vector2(0.77, 0.045), Vector2(0.60, 0.045), Vector2(0.60, -0.045)]), 20),
			CharacterKit.STRIP, Vector3(0, -bh * 0.16, 0), Vector3.ZERO, Vector3(bw / 1.42, 1, bd / 1.28 * 0.97), CharacterKit.STRIP_OPTS)

	# head: bulges out of the front-top of the body
	var h := f.hd
	var head := f.add("head", body, ArtMesh.blob(Vector3(0.78 * h, 0.62 * h, 0.72 * h), 2.4, 0.07, 21), CharacterKit.SANDSTONE, Vector3(0, bh * 0.27, -0.50))
	var eye := ArtMesh.blob(Vector3(0.11, 0.14, 0.06), 2.0, 0.0, 0, 8, 6)
	f.add("eyes", head, ArtMesh.merge([eye, eye], [ArtMesh.xf(Vector3(-0.16 * h, 0.0, -0.335 * h)), ArtMesh.xf(Vector3(0.16 * h, 0.0, -0.335 * h))]), CharacterKit.EYE)
	var hat_profile := PackedVector2Array([Vector2(0, -0.02), Vector2(0.30, -0.02), Vector2(0.30, -0.02), Vector2(0.30, 0.02), Vector2(0.30, 0.02),
			Vector2(0.24, 0.06), Vector2(0.23, 0.12), Vector2(0.19, 0.20), Vector2(0.11, 0.24), Vector2(0, 0.26)])
	var hat := f.add("hat", head, ArtMesh.lathe(hat_profile, 14), CharacterKit.HARDHAT, Vector3(0, 0.27 * h, -0.02), Vector3(8, 0, 0), Vector3.ONE * (0.6 + 0.4 * h))
	f.add("hat_strip", hat, ArtMesh.lathe(PackedVector2Array([Vector2(0.243, 0.065), Vector2(0.262, 0.065), Vector2(0.252, 0.12), Vector2(0.228, 0.12), Vector2(0.243, 0.065)]), 14),
			CharacterKit.STRIP, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, CharacterKit.STRIP_OPTS)

	# arms: heavy stone limbs and fists hanging by the hips; the shoulder boulder is the "weapon"
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := f.add("arm_" + side, body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.42 * f.lm, 0.62, 0.44 * f.lm), 2.4, 0.1, 31 + s), Vector3(0, -0.20, 0)),
				CharacterKit.SANDSTONE_DK, Vector3((bw * 0.5 + 0.0) * s, bh * 0.16, 0.0), Vector3(0, 0, 12 * s))
		f.add("hand_" + side, arm, ArtMesh.blob(Vector3(0.52, 0.46, 0.52), 2.4, 0.12, 41 + s), CharacterKit.SANDSTONE, Vector3(0, -0.56, 0))
	f.add("weapon", body, ArtMesh.blob(Vector3(0.58, 0.50, 0.54), 2.3, 0.2, 51), CharacterKit.SANDSTONE_DK, Vector3(bw * 0.38, bh * 0.56, 0.04))

	f.idle_fn = Callable(HeroRebar, "idle")
	f.pose_fn = Callable(HeroRebar, "pose")


static func idle(f: ToyFigure, t: float) -> void:
	f.rot("arm_l", Vector3(4.0 * sin(t * 1.2), 0, 0))
	f.rot("arm_r", Vector3(-4.0 * sin(t * 1.2), 0, 0))
	f.rot("head", Vector3(2.0 * sin(t * 0.9), 4.0 * sin(t * 0.55), 0))
	f.rot("weapon", Vector3(0, 0, 3.0 * sin(t * 1.4)))
	f.shift("moss", Vector3(0, 0.012 * sin(t * 2.3 + 1.0), 0))


static func pose(f: ToyFigure, pose_name: StringName) -> void:
	match pose_name:
		&"melee":     # slam fist
			f.put("body", Vector3(-16, 0, 0))
			f.rot("arm_r", Vector3(125, 0, 10))
			f.rot("arm_l", Vector3(20, 0, -20))
			f.rot("head", Vector3(-6, 0, 0))
		&"secondary":   # bowl: the shoulder boulder swung out in front
			f.put("body", Vector3(-8, 0, 0))
			f.rot("arm_r", Vector3(150, 0, 0))
			f.shift("weapon", Vector3(0.1, 0.2, -0.9))
			f.rot("arm_l", Vector3(-30, 0, -10))

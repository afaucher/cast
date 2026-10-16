class_name HeroSirRattles
extends RefCounted
## Sir Rattles, an empty suit of armor honoring a 400-year-old contract. Battered steel with
## mustard pauldrons, plume, tabard and shield. VISIBLY EMPTY: the helmet floats above the
## cuirass with dark nothing between, the face is a dark void (nothing glows - glowing eyes are
## enemy-only), and the hands and legs hover with small gaps at the joints.


static func build(f: ToyFigure) -> void:
	var rig := f.rig
	var leg_h := 0.30 * f.lg
	var torso_h := 0.68 * f.tr
	var hip := leg_h + 0.07
	var arm_len := 0.46 * (0.6 + 0.4 * f.tr)

	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var leg := f.add("leg_" + side, rig, CharacterKit.shifted(ArtMesh.blob(Vector3(0.30 * f.lm, leg_h + 0.04, 0.34 * f.lm), 2.8, 0.03, 5 + s), Vector3(0, -leg_h * 0.5 + 0.0, 0)), CharacterKit.STEEL_DK, Vector3(0.17 * f.wd * s, hip - 0.04, 0))
		f.add("boot_" + side, leg, ArtMesh.blob(Vector3(0.34, 0.16, 0.50), 3.0), CharacterKit.STEEL, Vector3(0, -leg_h + 0.02, -0.07))
	f.add("pelvis", rig, ArtMesh.blob(Vector3(0.40 * f.wd, 0.22, 0.30), 2.4), CharacterKit.VOID, Vector3(0, hip + 0.02, 0))

	var body := f.add("body", rig, ArtMesh.blob(Vector3(0.80 * f.wd, torso_h, 0.60 * f.wd), 3.0, 0.035, 9), CharacterKit.STEEL, Vector3(0, hip + 0.1 + torso_h * 0.5, 0))
	f.add("tabard", body, ArtMesh.box(Vector3(0.50 * f.wd, torso_h * 0.95, 0.045)), CharacterKit.MUSTARD, Vector3(0, -torso_h * 0.28, -0.31 * f.wd), Vector3(-4, 0, 0))
	f.add("tabard_strip", body, ArtMesh.box(Vector3(0.075, torso_h * 0.7, 0.02)), CharacterKit.STRIP, Vector3(0, -torso_h * 0.20, -0.345 * f.wd), Vector3(-4, 0, 0), Vector3.ONE, CharacterKit.STRIP_OPTS)
	f.add("neck", body, ArtMesh.blob(Vector3(0.28, 0.30, 0.28), 2.0), CharacterKit.VOID, Vector3(0, torso_h * 0.5 + 0.04, 0))

	# helmet floating over the nothing where a neck would be
	var h := f.hd
	var head := f.add("head", body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.56 * h, 0.60 * h, 0.56 * h), 3.2, 0.03, 13), Vector3(0, 0.30 * h, 0)), CharacterKit.STEEL, Vector3(0, torso_h * 0.5 + 0.13, 0))
	f.add("visor", head, ArtMesh.blob(Vector3(0.38 * h, 0.22 * h, 0.12), 2.6), CharacterKit.VOID, Vector3(0, 0.27 * h, -0.255 * h))
	var plume_mesh := ArtMesh.blob(Vector3(0.14, 0.46, 0.62), 2.2)
	f.add("plume", head, CharacterKit.shifted(plume_mesh, Vector3(0, 0, 0.0)), CharacterKit.MUSTARD, Vector3(0, 0.64 * h, 0.12 * h), Vector3(28, 0, 0))

	# arms: floating pauldrons, hovering hands
	var shoulder_y := torso_h * 0.5 - 0.08
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := f.add("arm_" + side, body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.22 * f.lm, arm_len, 0.24 * f.lm), 2.8), Vector3(0, -arm_len * 0.42, 0)),
				CharacterKit.STEEL, Vector3(0.50 * f.wd * s, shoulder_y, 0), Vector3(0, 0, 8 * s))
		f.add("pauldron_" + side, arm, ArtMesh.blob(Vector3(0.50, 0.36, 0.54), 2.7, 0.04, 17 + s), CharacterKit.MUSTARD, Vector3(0.03 * s, 0.07, 0))
		var hand := f.add("hand_" + side, arm, ArtMesh.blob(Vector3(0.21, 0.21, 0.23), 2.6), CharacterKit.STEEL_DK, Vector3(0, -arm_len * 0.42 - arm_len * 0.5 - 0.1, 0))
		if s > 0:
			var sword := f.add("weapon", hand, ArtMesh.box(Vector3(0.12, 1.05, 0.03)), Color(0.88, 0.90, 0.94), Vector3(0, 0.66, 0), Vector3(-52, 0, 10))
			f.add("weapon_guard", sword, ArtMesh.box(Vector3(0.34, 0.06, 0.09)), Color(0.74, 0.58, 0.22), Vector3(0, -0.45, 0))
		else:
			var shield := f.add("shield", hand, ArtMesh.cyl(0.40, 0.40, 0.07, 18, 0.02), CharacterKit.MUSTARD, Vector3(-0.12, 0.0, -0.18), Vector3(90, 0, 0))
			f.add("shield_boss", shield, ArtMesh.blob(Vector3(0.20, 0.12, 0.20), 2.2), CharacterKit.STEEL, Vector3(0, -0.07, 0))

	f.idle_fn = Callable(HeroSirRattles, "idle")
	f.pose_fn = Callable(HeroSirRattles, "pose")


static func idle(f: ToyFigure, t: float) -> void:
	# the empty armor hovers a little and its loose parts lag the breathing
	f.shift("head", Vector3(0, 0.02 * sin(t * 2.3 - 0.6), 0))
	f.rot("head", Vector3(2.0 * sin(t * 1.0), 4.0 * sin(t * 0.6), 0))
	f.shift("hand_l", Vector3(0, 0.02 * sin(t * 2.3 + 1.0), 0))
	f.shift("hand_r", Vector3(0, 0.02 * sin(t * 2.3 + 2.0), 0))
	f.rot("weapon", Vector3(3.0 * sin(t * 1.5), 0, 0))
	f.rot("plume", Vector3(5.0 * sin(t * 2.0), 0, 3.0 * sin(t * 1.3)))


static func pose(f: ToyFigure, pose_name: StringName) -> void:
	match pose_name:
		&"melee":     # sword chop
			f.put("body", Vector3(-12, -10, 0))
			f.rot("arm_r", Vector3(120, 0, 8))
			f.rot("arm_l", Vector3(20, 0, -10))
			f.rot("weapon", Vector3(25, 0, 0))
		&"secondary":   # shield up
			f.rot("arm_l", Vector3(80, 0, -10))
			f.rot("arm_r", Vector3(15, 0, 10))
			f.rot("shield", Vector3(0, 0, 0))

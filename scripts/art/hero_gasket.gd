class_name HeroGasket
extends RefCounted
## Gasket, the demolition dwarf: stout, a denim hard hat, a beard spilling forward (it shows
## facing from above), a big sledgehammer. Denim blue is her colour; the vest straps are the
## white crew strips.


static func build(f: ToyFigure) -> void:
	var rig := f.rig
	var leg_h := 0.25 * f.lg
	var torso_h := 0.62 * f.tr
	var hip := leg_h
	var arm_len := 0.40 * (0.6 + 0.4 * f.tr)
	var legs := Color(0.16, 0.30, 0.58)

	# legs + boots
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var leg := f.add("leg_" + side, rig, CharacterKit.shifted(ArtMesh.blob(Vector3(0.31 * f.wd * f.lm, leg_h + 0.08, 0.34 * f.wd * f.lm), 2.6), Vector3(0, -leg_h * 0.5 + 0.03, 0)), legs, Vector3(0.17 * f.wd * s, hip, 0))
		f.add("boot_" + side, leg, ArtMesh.blob(Vector3(0.35 * f.wd, 0.20, 0.52 * f.wd), 2.6), CharacterKit.LEATHER, Vector3(0, -leg_h + 0.07, -0.06))

	# torso, belt, vest strips
	var body := f.add("body", rig, ArtMesh.blob(Vector3(0.82 * f.wd, torso_h, 0.66 * f.wd), 2.7), CharacterKit.DENIM, Vector3(0, hip + torso_h * 0.5 - 0.03, 0))
	f.add("belt", body, ArtMesh.cyl(0.405 * f.wd, 0.405 * f.wd, 0.10, 16, 0.02), CharacterKit.LEATHER, Vector3(0, -torso_h * 0.24, 0), Vector3.ZERO, Vector3(1, 1, 0.80))
	var strap := ArtMesh.box(Vector3(0.08, torso_h * 0.62, 0.05))
	f.add("strips", body, ArtMesh.merge([strap, strap], [ArtMesh.xf(Vector3(-0.17 * f.wd, 0.03, 0), Vector3(0, 0, -5)), ArtMesh.xf(Vector3(0.17 * f.wd, 0.03, 0), Vector3(0, 0, 5))]),
			CharacterKit.STRIP, Vector3(0, 0, -0.318 * f.wd), Vector3.ZERO, Vector3.ONE, CharacterKit.STRIP_OPTS)

	# head, face, beard, hard hat
	var h := f.hd
	var head := f.add("head", body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.58 * h, 0.52 * h, 0.54 * h), 2.4), Vector3(0, 0.21 * h, 0)), CharacterKit.SKIN, Vector3(0, torso_h * 0.5 - 0.03, 0))
	var eye := ArtMesh.blob(Vector3(0.075, 0.09, 0.05), 2.0, 0.0, 0, 8, 6)
	f.add("eyes", head, ArtMesh.merge([eye, eye], [ArtMesh.xf(Vector3(-0.125 * h, 0.22 * h, -0.25 * h)), ArtMesh.xf(Vector3(0.125 * h, 0.22 * h, -0.25 * h))]), CharacterKit.EYE)
	f.add("nose", head, ArtMesh.blob(Vector3(0.17 * h, 0.14 * h, 0.17 * h), 2.2), CharacterKit.SKIN_DK, Vector3(0, 0.14 * h, -0.275 * h))
	var beard := ArtMesh.lathe(PackedVector2Array([Vector2(0, 0.07), Vector2(0.17, 0.05), Vector2(0.27, -0.04), Vector2(0.30, -0.17),
			Vector2(0.25, -0.32), Vector2(0.16, -0.46), Vector2(0.06, -0.56), Vector2(0, -0.60)]), 14)
	var mus := ArtMesh.blob(Vector3(0.40, 0.13, 0.16), 2.4)
	f.add("beard", head, ArtMesh.merge([beard, mus], [ArtMesh.xf(Vector3(0, 0.14 * h, -0.14 * h), Vector3(14, 0, 0), Vector3(1, 1, 0.78)), ArtMesh.xf(Vector3(0, 0.115 * h, -0.235 * h))]), CharacterKit.GINGER)
	var hat_profile := PackedVector2Array([Vector2(0, -0.02), Vector2(0.37, -0.02), Vector2(0.37, -0.02), Vector2(0.37, 0.02), Vector2(0.37, 0.02),
			Vector2(0.30, 0.06), Vector2(0.30, 0.10), Vector2(0.27, 0.20), Vector2(0.20, 0.27), Vector2(0.10, 0.31), Vector2(0, 0.32)])
	f.add("hat", head, ArtMesh.lathe(hat_profile, 16), CharacterKit.DENIM_LT, Vector3(0, 0.355 * h, 0.04), Vector3(14, 0, 0), Vector3.ONE * (0.55 + 0.45 * h) * 1.0)

	# arms; the right one carries the hammer
	var shoulder_y := torso_h * 0.5 - 0.12
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := f.add("arm_" + side, body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.23 * f.lm, arm_len, 0.23 * f.lm), 2.4), Vector3(0, -arm_len * 0.45, 0)),
				CharacterKit.DENIM, Vector3(0.43 * f.wd * s, shoulder_y, 0), Vector3(0, 0, 8 * s))
		var hand := f.add("hand_" + side, arm, ArtMesh.blob(Vector3.ONE * 0.19, 2.2), CharacterKit.SKIN, Vector3(0, -arm_len * 0.92, 0))
		if s > 0:
			var handle := f.add("weapon", hand, ArtMesh.cyl(0.045, 0.045, 0.95, 8, 0.01), CharacterKit.WOOD, Vector3(0, 0.30, 0), Vector3(-12, 0, 6))
			f.add("weapon_head", handle, ArtMesh.blob(Vector3(0.66, 0.36, 0.38), 5.0), CharacterKit.STEEL_DK, Vector3(0, 0.50, 0))

	f.idle_fn = Callable(HeroGasket, "idle")
	f.pose_fn = Callable(HeroGasket, "pose")


static func idle(f: ToyFigure, t: float) -> void:
	f.rot("weapon", Vector3(0, 0, 3.0 * sin(t * 1.6)))
	f.rot("beard", Vector3(2.5 * sin(t * 2.3 + 0.8), 0, 0))
	f.rot("head", Vector3(1.5 * sin(t * 1.1), 3.0 * sin(t * 0.7), 0))
	f.rot("arm_l", Vector3(0, 0, -2.0 * sin(t * 2.3)))


static func pose(f: ToyFigure, pose_name: StringName) -> void:
	match pose_name:
		&"melee":     # hammer smash, caught mid-swing
			f.put("body", Vector3(-14, 0, 0))
			f.rot("arm_r", Vector3(115, 0, 8))
			f.rot("arm_l", Vector3(30, 0, -20))
			f.rot("weapon", Vector3(25, 0, 0))
			f.rot("head", Vector3(-8, 0, 0))
		&"secondary":   # spin: arms out, whole body turned
			f.put("body", Vector3(0, 70, 0))
			f.rot("arm_r", Vector3(0, 0, 85))
			f.rot("arm_l", Vector3(0, 0, -85))
			f.rot("weapon", Vector3(-80, 0, 0))

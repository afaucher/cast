class_name HeroLarkin
extends RefCounted
## Larkin, the wizard-school dropout who kept the hat and took up the bow: lanky, a huge crooked
## plum hat (the tallest diagonal on screen) with a headlamp, a bent-tent-pole bow, a taped-up
## wand, a quiver on the back (reads from behind), and a white bandolier strip.


static func build(f: ToyFigure) -> void:
	var rig := f.rig
	var leg_h := 0.50 * f.lg
	var torso_h := 0.74 * f.tr
	var hip := leg_h
	var arm_len := 0.62 * (0.7 + 0.3 * f.tr)
	var trousers := Color(0.30, 0.17, 0.40)

	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var leg := f.add("leg_" + side, rig, CharacterKit.shifted(ArtMesh.blob(Vector3(0.19 * f.lm, leg_h + 0.06, 0.22 * f.lm), 2.4), Vector3(0, -leg_h * 0.5 + 0.03, 0)), trousers, Vector3(0.12 * f.wd * s, hip, 0))
		f.add("boot_" + side, leg, ArtMesh.blob(Vector3(0.22, 0.17, 0.38), 2.6), CharacterKit.LEATHER, Vector3(0, -leg_h + 0.06, -0.05))

	# long coat
	var coat := PackedVector2Array([Vector2(0, -0.5), Vector2(0.27, -0.5), Vector2(0.27, -0.5), Vector2(0.255, -0.2), Vector2(0.21, 0.28), Vector2(0.17, 0.44), Vector2(0.10, 0.5), Vector2(0, 0.5)])
	var body := f.add("body", rig, CharacterKit.shifted(ArtMesh.lathe(coat, 14), Vector3.ZERO, Vector3.ZERO, Vector3(f.wd * 1.1, torso_h, f.wd * 0.92)), CharacterKit.PLUM, Vector3(0, hip + torso_h * 0.5 - 0.06, 0))
	var sash_pts: Array = []
	for i in 9:
		var u := float(i) / 8.0
		var phi := deg_to_rad(lerpf(-48.0, 48.0, u))
		var py := lerpf(0.30, -0.28, u)                    # profile units along the coat
		var rr := lerpf(0.215, 0.26, clampf((0.3 - py) / 0.8, 0.0, 1.0))
		sash_pts.append(Vector3(sin(phi) * (rr * 1.1 * f.wd + 0.01), py * torso_h / torso_h * 0.0 + py * torso_h, -cos(phi) * (rr * 0.92 * f.wd + 0.01)))
	f.add("sash", body, ArtMesh.tube(sash_pts, 0.036, 0.036, 6), CharacterKit.STRIP, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, CharacterKit.STRIP_OPTS)
	f.add("quiver", body, ArtMesh.cyl(0.085, 0.10, 0.62, 10, 0.02), CharacterKit.LEATHER, Vector3(0.10, 0.10, 0.22 * f.wd), Vector3(14, 0, -22))
	var arrow := ArtMesh.cyl(0.012, 0.012, 0.3, 5)
	f.add("arrows", body, ArtMesh.merge([arrow, arrow, arrow], [ArtMesh.xf(Vector3(-0.02, 0.0, 0.0)), ArtMesh.xf(Vector3(0.03, 0.02, 0.03), Vector3(0, 0, 8)), ArtMesh.xf(Vector3(0.0, 0.01, -0.04), Vector3(6, 0, -6))]),
			Color(0.95, 0.9, 0.78), Vector3(0.20, 0.50, 0.26 * f.wd), Vector3(14, 0, -22))

	# head
	var h := f.hd
	var head := f.add("head", body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.44 * h, 0.46 * h, 0.44 * h), 2.3), Vector3(0, 0.20 * h, 0)), CharacterKit.SKIN, Vector3(0, torso_h * 0.5 - 0.02, 0))
	var eye := ArtMesh.blob(Vector3(0.06, 0.08, 0.05), 2.0, 0.0, 0, 8, 6)
	f.add("eyes", head, ArtMesh.merge([eye, eye], [ArtMesh.xf(Vector3(-0.10 * h, 0.23 * h, -0.2 * h)), ArtMesh.xf(Vector3(0.10 * h, 0.23 * h, -0.2 * h))]), CharacterKit.EYE)
	f.add("nose", head, ArtMesh.blob(Vector3(0.10 * h, 0.12 * h, 0.2 * h), 2.2), CharacterKit.SKIN_DK, Vector3(0, 0.16 * h, -0.24 * h))
	f.add("hair", head, ArtMesh.blob(Vector3(0.50 * h, 0.34 * h, 0.40 * h), 2.4), Color(0.36, 0.22, 0.14), Vector3(0, 0.22 * h, 0.10 * h))

	# the hat: wide brim, tall cone, tip flopping back and to the right
	var hat_profile := PackedVector2Array([Vector2(0, -0.02), Vector2(0.60, -0.02), Vector2(0.60, -0.02), Vector2(0.60, 0.02), Vector2(0.60, 0.02), Vector2(0.31, 0.08),
			Vector2(0.28, 0.30), Vector2(0.21, 0.54), Vector2(0.13, 0.76), Vector2(0.06, 0.92), Vector2(0.0, 1.02)])
	var bend := func(t: float) -> Vector3:
		var k := pow(maxf(0.0, (t - 0.45) / 0.55), 2.2)
		return Vector3(0.30 * k, 0.0, 0.42 * k)
	var hs := 0.62 + 0.38 * h
	var hat := f.add("hat", head, ArtMesh.lathe(hat_profile, 18, bend), CharacterKit.PLUM, Vector3(0, 0.33 * h, 0.06), Vector3(8, 0, 5), Vector3.ONE * hs * 0.92)
	f.add("hat_band", hat, ArtMesh.lathe(PackedVector2Array([Vector2(0.3, 0.07), Vector2(0.315, 0.07), Vector2(0.30, 0.2), Vector2(0.285, 0.2), Vector2(0.3, 0.07)]), 18),
			CharacterKit.LEATHER)
	f.add("lamp", hat, ArtMesh.cyl(0.075, 0.085, 0.12, 8, 0.015), Color(0.86, 0.86, 0.80), Vector3(0, 0.16, -0.31), Vector3(90, 0, 0))

	# arms: bow in the left hand, taped-up wand in the right
	var shoulder_y := torso_h * 0.5 - 0.1
	var arm_l := f.add("arm_l", body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.15 * f.lm, arm_len, 0.15 * f.lm), 2.3), Vector3(0, -arm_len * 0.45, 0)), CharacterKit.PLUM, Vector3(-0.27 * f.wd, shoulder_y, 0), Vector3(25, 0, -10))
	var hand_l := f.add("hand_l", arm_l, ArtMesh.blob(Vector3.ONE * 0.15, 2.2), CharacterKit.SKIN, Vector3(0, -arm_len * 0.92, 0))
	var pts: Array = []
	for i in 9:
		var y := lerpf(-0.66, 0.66, float(i) / 8.0)
		pts.append(Vector3(0, y, 0.27 * pow(y / 0.66, 2.0)))
	var bow := f.add("weapon", hand_l, ArtMesh.tube(pts, 0.032, 0.02, 6), Color(0.40, 0.62, 0.58), Vector3(0, 0.02, -0.04), Vector3(0, 0, 0))
	f.add("bowstring", bow, ArtMesh.tube([Vector3(0, -0.66, 0.27), Vector3(0, 0.66, 0.27)], 0.009, 0.009, 4), Color(0.93, 0.90, 0.80), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, {"outline": false})

	var arm_r := f.add("arm_r", body, CharacterKit.shifted(ArtMesh.blob(Vector3(0.15 * f.lm, arm_len, 0.15 * f.lm), 2.3), Vector3(0, -arm_len * 0.45, 0)), CharacterKit.PLUM, Vector3(0.27 * f.wd, shoulder_y, 0), Vector3(10, 0, 12))
	var hand_r := f.add("hand_r", arm_r, ArtMesh.blob(Vector3.ONE * 0.15, 2.2), CharacterKit.SKIN, Vector3(0, -arm_len * 0.92, 0))
	var wand := f.add("wand", hand_r, ArtMesh.cyl(0.028, 0.034, 0.58, 7, 0.006), CharacterKit.WOOD, Vector3(0, 0.12, -0.08), Vector3(-65, 0, 0))
	var tape_ring := ArtMesh.cyl(0.044, 0.044, 0.05, 8, 0.008)
	f.add("wand_tape", wand, ArtMesh.merge([tape_ring, tape_ring, ArtMesh.blob(Vector3(0.11, 0.12, 0.11), 2.2)],
			[ArtMesh.xf(Vector3(0, -0.02, 0)), ArtMesh.xf(Vector3(0, 0.12, 0)), ArtMesh.xf(Vector3(0, 0.33, 0))]), Color(0.72, 0.74, 0.76))

	f.idle_fn = Callable(HeroLarkin, "idle")
	f.pose_fn = Callable(HeroLarkin, "pose")


static func idle(f: ToyFigure, t: float) -> void:
	f.rot("hat", Vector3(2.5 * sin(t * 1.3), 0, 2.5 * sin(t * 1.7 + 1.0)))
	f.rot("head", Vector3(1.5 * sin(t * 1.1), 3.0 * sin(t * 0.6), 0))
	f.rot("wand", Vector3(4.0 * sin(t * 2.0), 0, 0))
	f.rot("weapon", Vector3(0, 0, 2.5 * sin(t * 1.4)))


static func pose(f: ToyFigure, pose_name: StringName) -> void:
	match pose_name:
		&"melee":     # bow bash
			f.put("body", Vector3(-10, -15, 0))
			f.rot("arm_l", Vector3(95, 0, 20))
			f.rot("weapon", Vector3(0, 0, 70))
			f.rot("arm_r", Vector3(-20, 0, 15))
		&"secondary":   # draw: bow out front, string hand to the cheek
			f.put("body", Vector3(0, 40, 0))
			f.rot("arm_l", Vector3(88, 0, -4))
			f.rot("arm_r", Vector3(100, 0, 52))

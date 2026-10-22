extends TestCase
## The judder check (docs/design/movement-research.md gap 0 and "As built"): NOT in the suite (no test_ prefix). Walks a hero
## at full speed and records, every RENDERED frame, where the hero is drawn and where the camera is, with physics
## interpolation of the hero (MoveFeel.interp) off and on. Run it at a monitor's refresh rate:
##   Godot --path . --headless --fixed-fps 144 -- --run-test probe_move_judder
## It prints, per setting, the hero's drawn step per frame (mean, and its spread: 0 = perfectly even) and how far the hero
## jumps about on screen against the camera (the jitter you see), in world units and in pixels at the game's zoom.

const PX_PER_UNIT := 1080.0 / 24.0   ## the game camera: 24 units tall on a 1080p screen


func setup() -> void:
	timeout_sec = 60.0
	var fps := Engine.get_frames_per_second()
	for on in [false, true]:
		MoveFeel.reset()
		MoveFeel.set_mode(MoveFeel.GROUNDED)
		MoveFeel.interp = on
		var root := Node3D.new()
		add_child(root)
		var m := HexMap.new()
		for c in Hex.range_cells(Vector2i.ZERO, 14):
			m.set_cell(c, 0)
		GameWorld.begin(m, root, 1)
		var h := HeroFactory.spawn_hero(Vector2i(-8, 0), "Walker", Color.BLUE)
		var pc := HeroFactory.make_player(h, [] as Array[String])
		var rig := CameraRig.new()
		root.add_child(rig)
		rig.target = h
		rig.snap()
		pc.move_override = Vector3.RIGHT
		pc.aim_override = Vector3(30, 0, 0)
		for i in 30:
			await get_tree().process_frame
		var steps: Array[float] = []
		var screen: Array[float] = []
		var prev := Vector3.INF
		var prev_rel := Vector3.INF
		var rec := Recorder.new()
		rec.hero = h
		rec.rig = rig
		root.add_child(rec)
		for i in 241:
			await get_tree().process_frame
		for i in rec.drawn.size():
			var p: Vector3 = rec.drawn[i]
			var rel: Vector3 = p - (rec.cams[i] as Vector3)
			if prev != Vector3.INF:
				steps.append(Vector2(p.x - prev.x, p.z - prev.z).length())
				screen.append(Vector2(rel.x - prev_rel.x, rel.z - prev_rel.z).length())
			prev = p
			prev_rel = rel
		var mean := 0.0
		for s in steps:
			mean += s
		mean /= steps.size()
		var dev := 0.0
		for s in steps:
			dev += (s - mean) * (s - mean)
		dev = sqrt(dev / steps.size())
		var still := 0
		for s in steps:
			still += 1 if s < mean * 0.25 else 0
		print("[judder] %d fps (physics %d Hz), interpolation %s: drawn step %.4f u/frame (spread %.4f = %.0f%%), %d of %d frames the hero did not move; on screen vs the camera: max jump %.4f u (%.1f px)" % [
			Engine.max_fps if Engine.max_fps > 0 else int(round(1.0 / get_process_delta_time())), Engine.physics_ticks_per_second, "on " if on else "off",
			mean, dev, 100.0 * dev / maxf(mean, 1e-6), still, steps.size(), screen.max(), screen.max() * PX_PER_UNIT])
		root.queue_free()
		await get_tree().process_frame
		GameWorld.end()
	MoveFeel.reset()
	print("[judder] fps seen %s" % fps)
	finish()


## Reads, after every other _process of the frame (the hero's and the camera's), what this frame draws.
class Recorder extends Node:
	var hero: Hero
	var rig: CameraRig
	var drawn: Array = []
	var cams: Array = []

	func _ready() -> void:
		process_priority = 1000

	func _process(_delta: float) -> void:
		drawn.append(hero.global_position)
		cams.append(rig.global_position)

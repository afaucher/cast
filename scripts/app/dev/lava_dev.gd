class_name LavaDev
extends RefCounted
## The lava cave's dev flags (docs/design/lava-playtest.md, "As built: caves on real floors"). GameDev calls it:
##   --lava-floor            force a lava cave (LavaSite.force) on every floor of a job where any wing of rooms fits, whatever
##                           the site, floor or roll; the job starts on floor 2 unless --floor says otherwise (its first gate in
##                           the cave there, so the hellfire look). In a crew: every window with the flag.
##   --lava-pattern NAME     the pattern a forced cave tries first: causeway, fork, ring or gauntlet
##   --to-lava [entry|far|isle]  solo: the crew starts at the cave's entry (default), in its far chamber, or on the shore an isle
##                           is crusted from (bring damp)
##   --lava-perf             measure the cave's lights: the GPU and CPU render time looking at the cave with 10, 4 and no lava
##                           lights (prints "[lava perf] ..." and quits)
## --lava-cave N (the hand-authored prototype caves) is game.gd's own flag.

const PERF_FRAMES := 240


static func parse(args: PackedStringArray, opts: Dictionary) -> void:
	if args.has("--lava-floor"):
		LavaSite.force = true
		opts["lava_floor"] = true
		if not opts.has("floor"):
			opts["floor"] = 2
	var i := args.find("--lava-pattern")
	if i >= 0 and i + 1 < args.size():
		LavaSite.force_pattern = args[i + 1]
	var k := args.find("--to-lava")
	if k >= 0:
		opts["to_lava"] = args[k + 1] if k + 1 < args.size() and not args[k + 1].begins_with("--") else "entry"
	if args.has("--lava-perf"):
		opts["lava_perf"] = true


## Where --to-lava puts the crew on `map` (NO_CELL without a cave).
static func spot(map: HexMap, where: String) -> Vector2i:
	var rec := map.cave
	if rec.is_empty() or not rec.has("chambers"):
		return HexMap.NO_CELL
	match where:
		"far":
			for ch: Dictionary in rec["chambers"]:
				if str(ch["room"]) == str(rec["far"]):
					return _near_free(map, ch["center"])
		"isle":
			var isles: Array = rec["isles"]
			if not isles.is_empty():
				return (isles[0] as Dictionary)["shore"]
	var neck: Array = (rec["entry"] as Dictionary)["neck"]
	return neck[neck.size() - 1] if not neck.is_empty() else (rec["entry"] as Dictionary)["door"]


static func _near_free(map: HexMap, c: Vector2i) -> Vector2i:
	for r in 4:
		for x in Hex.ring(c, r):
			if map.is_walkable_cell(x):
				return x
	return c


## The light budget, measured (see the header). `game` is the running game (its camera rig); quits when done.
static func perf(game: Node, map: HexMap) -> void:
	var holder := game.get_node_or_null("LavaCave") as Node3D
	if holder == null or map.cave.is_empty():
		print("[lava perf] no generated cave on this floor")
		game.get_tree().quit()
		return
	var mid := Vector3.ZERO
	var lava: Array = map.cave["lava"]
	for c: Vector2i in lava:
		mid += Hex.to_world(c)
	mid /= float(maxi(1, lava.size()))
	mid.y = float(map.cave["lava_y"]) + 1.0
	var marker := Node3D.new()
	GameWorld.root.add_child(marker)
	marker.global_position = mid
	var rig: Node = game.get("rig")
	rig.set("target", marker)
	rig.call("snap")
	var cells: Array[Vector2i] = []
	for c: Vector2i in lava:
		cells.append(c)
	var ten := Node3D.new()
	ten.name = "PerfLights"
	holder.add_child(ten)
	LavaLook._build_lights(ten, cells, float(map.cave["lava_y"]), 10)
	var own: Array[Node] = []
	for ch in holder.get_children():
		if ch is OmniLight3D:
			own.append(ch)
	var vp := game.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var results := {}
	for mode in ["10", "4", "0"]:
		ten.visible = mode == "10"
		for l in own:
			(l as Node3D).visible = mode == "4"
		results[mode] = await _measure(game, vp)
	print("[lava perf] %d lava cells, view %s, %s: 10 lights gpu %.3f ms cpu %.3f ms | 4 lights gpu %.3f cpu %.3f | none gpu %.3f cpu %.3f" % [
		cells.size(), str(game.get_viewport().get_visible_rect().size), RenderingServer.get_video_adapter_name(),
		results["10"].x, results["10"].y, results["4"].x, results["4"].y, results["0"].x, results["0"].y])
	game.get_tree().quit()


static func _measure(game: Node, vp: RID) -> Vector2:
	for i in 30:
		await game.get_tree().process_frame
	var gpu := 0.0
	var cpu := 0.0
	for i in PERF_FRAMES:
		await game.get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	return Vector2(gpu, cpu) / float(PERF_FRAMES)

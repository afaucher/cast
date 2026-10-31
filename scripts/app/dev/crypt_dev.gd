class_name CryptDev
extends RefCounted
## The crypt's dev flags (haunted-build-plan.md, "H2 as built"). GameDev calls it:
##   --crypt-floor           force a crypt (CryptCluster.force) on every floor of a job where any wing of rooms fits, whatever
##                           the site, floor or roll (a haunted contract's: --client heir | parish; on a hellgate site it is a
##                           vault). In a crew: every window with the flag.
##   --to-crypt [head|foot|lit|dark]  solo: the crew starts at the head of the crypt's stair (default), at its foot, or in
##                           its first lit (the sarcophagi's) or dark room
##   --crypt-perf            measure the crypt's candle lights: the GPU and CPU render time looking at its first lit room
##                           with every crypt light on and off (prints "[crypt perf] ..." and quits)
## A natural crypt: --client parish --seed N --floor F (the log names the crypt's rooms, "crypt: ...").

const PERF_FRAMES := 300


static func parse(args: PackedStringArray, opts: Dictionary) -> void:
	if args.has("--crypt-floor"):
		CryptCluster.force = true
		opts["crypt_floor"] = true
	var k := args.find("--to-crypt")
	if k >= 0:
		opts["to_crypt"] = args[k + 1] if k + 1 < args.size() and not args[k + 1].begins_with("--") else "head"
	if args.has("--crypt-perf"):
		opts["crypt_perf"] = true


## Where --to-crypt puts the crew on `map` (NO_CELL without a crypt).
static func spot(map: HexMap, plan: SitePlan, where: String) -> Vector2i:
	var rec := map.crypt
	if rec.is_empty():
		return HexMap.NO_CELL
	var st: Dictionary = rec["stair"]
	match where:
		"foot":
			return st["door"]
		"lit", "dark":
			var rooms: Array = rec.get(where, [])
			if not rooms.is_empty() and plan != null and plan.centers.has(str(rooms[0])):
				return _near_free(map, plan.centers[str(rooms[0])])
	return st["door_up"]


static func _near_free(map: HexMap, c: Vector2i) -> Vector2i:
	if map.is_walkable_cell(c):
		return c
	for r in range(1, 4):
		for x in Hex.ring(c, r):
			if map.is_walkable_cell(x):
				return x
	return c


## The light budget, measured (see the header). `game` is the running game (its camera rig); quits when done.
static func perf(game: Node, map: HexMap, plan: SitePlan) -> void:
	var at := spot(map, plan, "lit")
	if at == HexMap.NO_CELL:
		print("[crypt perf] no crypt on this floor")
		game.get_tree().quit()
		return
	var marker := Node3D.new()
	GameWorld.root.add_child(marker)
	marker.global_position = Hex.to_world(at, float(map.get_cell(at).level))
	var rig: Node = game.get("rig")
	rig.set("target", marker)
	rig.call("snap")
	# every light of the crypt's decor (candles, candelabras, shafts) and the floor's other lights
	var rooms: Array = map.crypt["rooms"]
	var mine: Array[Light3D] = []
	var others := 0
	for l: Node in GameWorld.root.find_children("*", "Light3D", true, false):
		var n := l as Node3D
		var cell := map.get_cell(Hex.from_world(n.global_position))
		var dp := n.get_parent()
		while dp != null and not (dp is DecorProp):
			dp = dp.get_parent()
		if dp != null and cell != null and (rooms.has(cell.tag) or cell.tag == "corridor"):
			mine.append(l as Light3D)
		else:
			others += 1
	var vp := game.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var results := {}
	for mode in ["on", "off", "on", "off"]:
		for l in mine:
			l.visible = mode == "on"
		results[mode] = (results.get(mode, Vector2.ZERO) as Vector2) + await _measure(game, vp) * 0.5
	print("[crypt perf] %d crypt lights (%d other lights), view %s, %s: on gpu %.3f ms cpu %.3f ms | off gpu %.3f ms cpu %.3f ms | %.0f fps" % [
		mine.size(), others, str(game.get_viewport().get_visible_rect().size), RenderingServer.get_video_adapter_name(),
		results["on"].x, results["on"].y, results["off"].x, results["off"].y, Engine.get_frames_per_second()])
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

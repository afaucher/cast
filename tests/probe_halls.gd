extends TestCase
## PROBE (not part of -TestAll: it is not test_*): how long the generated floors' halls are, and what the landings do to them
## (docs/design/hallways.md). Ten contract seeds (the golden floors' 1-10) x floors 1-3, built the way the game builds them
## (DungeonGen.for_run, SiteBuilder.plan), once with the landings switch off and once on:
##   .\test_runner.ps1 -TestName probe_halls
## Per hall (DungeonGen.last_halls): door to door in a straight line and along its route (world units), which kind it is;
## per floor: the landings and their set pieces. "Stretch": the longest run of hall between two landings (or a door and a
## landing), along the route: what you walk with nothing to look at.

const SEEDS := 10
const FLOORS := 3


func setup() -> void:
	timeout_sec = 300.0
	var keep := DungeonGen.landings
	for on in [false, true]:
		DungeonGen.landings = on
		_report(on)
	DungeonGen.landings = keep
	finish()


func _report(on: bool) -> void:
	var straight: Array[float] = []
	var path: Array[float] = []
	var stretch: Array[float] = []       # every stretch of hall between landings / doors, along the route
	var longest: Array[float] = []       # per hall: its longest stretch
	var per_floor: Array[int] = []
	var pieces_floor: Array[int] = []
	var kinds := {}
	var facing_cam := 0                  # set pieces whose front turns toward the camera (their back wall on the far side)
	var halls := 0
	var with_landing := 0
	var corr_share: Array[float] = []
	var corr_units: Array[float] = []
	var eligible_long := 0
	var long_missed := 0
	var gen_usec := 0
	DungeonGen.landing_usec = 0
	for s in range(1, SEEDS + 1):
		var run := ContractBoard.run_for_seed(s)
		for f in range(1, FLOORS + 1):
			var t0 := Time.get_ticks_usec()
			var map := DungeonGen.for_run(run, f)
			gen_usec += Time.get_ticks_usec() - t0
			var rows: Array[Dictionary] = DungeonGen.last_halls.duplicate()
			var plan := SiteBuilder.plan(map, run, f, PricedProp.catalog(run.site_type))
			per_floor.append(map.landings.size())
			pieces_floor.append(plan.set_pieces.size())
			for sp in plan.set_pieces:
				var key := "%s/%s" % [run.site_type, sp["kind"]]
				kinds[key] = int(kinds.get(key, 0)) + 1
				if ThemeGeo.facing(float(sp["yaw"])).dot(ThemeGeo.CAMERA_DIR) >= 0.25:
					facing_cam += 1
			var walk := 0
			var corr := 0
			for c: Vector2i in map.cells:
				var cell: HexMap.Cell = map.cells[c]
				if cell.type == HexMap.Tile.WALL or not map.is_walkable_cell(c):
					continue
				walk += 1
				if cell.tag == "corridor":
					corr += 1
			corr_share.append(float(corr) / maxf(1.0, float(walk)))
			var units := 0.0
			for h in rows:
				halls += 1
				straight.append(float(h["straight"]))
				path.append(float(h["path"]))
				units += float(h["path"])
				var steps: Array[int] = []
				for lr in map.landings:
					var ht: Array = lr["hall"]
					if str(ht[0]) == "room:%d" % int(h["a"]) and str(ht[1]) == "room:%d" % int(h["b"]):
						steps.append(int(lr["step"]))
				steps.sort()
				if not steps.is_empty():
					with_landing += 1
				var eligible := not bool(h["stair"]) and not bool(h["special"]) and not (bool(h["narrow"]) and not bool(h["loop"]) and not bool(h["shortcut"]))
				if eligible and DungeonGen.landing_count(float(h["path"])) > 0:
					eligible_long += 1
					if steps.is_empty():
						long_missed += 1
				var last := 0
				var worst := 0.0
				for st in steps + [int(h["steps"])]:
					var seg := float(st - last) * Hex.SQRT3
					stretch.append(seg)
					worst = maxf(worst, seg)
					last = st
				longest.append(worst)
				if on and worst > 30.0:
					print("[halls]   long stretch: seed %d floor %d hall %d-%d path %.1f straight %.1f %s, landings %d of %d at %s (of %d steps)" % [
							s, f, int(h["a"]), int(h["b"]), float(h["path"]), float(h["straight"]),
							"loop" if bool(h["loop"]) else ("narrow" if bool(h["narrow"]) else ("special" if bool(h["special"]) else "tree")),
							steps.size(), DungeonGen.landing_count(float(h["path"])), str(steps), int(h["steps"])])
			corr_units.append(units)
	print("[halls] landings %s: %d floors, %d halls; generation %.1f ms a floor (the landings pass %.1f ms of it)" % ["ON" if on else "OFF",
			per_floor.size(), halls, gen_usec / 1000.0 / per_floor.size(), DungeonGen.landing_usec / 1000.0 / per_floor.size()])
	print("[halls]   straight door to door: %s" % _dist(straight))
	print("[halls]   along the route:       %s" % _dist(path))
	print("[halls]   longest stretch per hall (route): %s" % _dist(longest))
	print("[halls]   every stretch (route): %s" % _dist(stretch))
	print("[halls]   halls with a landing: %d of %d (%.0f%%); long eligible halls without one: %d of %d" % [with_landing, halls,
			100.0 * with_landing / maxf(1.0, halls), long_missed, eligible_long])
	var lf: Array[float] = []
	for v in per_floor:
		lf.append(float(v))
	var pf: Array[float] = []
	for v in pieces_floor:
		pf.append(float(v))
	print("[halls]   landings a floor: %s  %s" % [_dist(lf), str(per_floor)])
	print("[halls]   set pieces a floor: %s  %s" % [_dist(pf), str(pieces_floor)])
	print("[halls]   set piece kinds: %s; facing the camera: %d" % [str(kinds), facing_cam])
	print("[halls]   corridor share of walkable floor: %s; hall units a floor: %s" % [_dist(corr_share), _dist(corr_units)])


func _dist(v: Array[float]) -> String:
	if v.is_empty():
		return "-"
	var s := v.duplicate()
	s.sort()
	var sum := 0.0
	for x in s:
		sum += x
	return "n %d  min %.1f  median %.1f  p75 %.1f  p90 %.1f  max %.1f  mean %.2f" % [s.size(), s[0], _q(s, 0.5), _q(s, 0.75),
			_q(s, 0.9), s[s.size() - 1], sum / s.size()]


func _q(s: Array, q: float) -> float:
	return float(s[clampi(int(round(q * (s.size() - 1))), 0, s.size() - 1)])

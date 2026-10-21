extends "res://scripts/app/game.gd"
## The game's dev and screenshot drivers (docs/design/refactor-plan.md, H7 step 1), moved out of game.gd as they were
## (no behaviour change). scenes/game.tscn runs this script, so every command-line flag works as before; game.gd itself
## reads the flags (_parse_args) and calls the hooks below at the same moments it always did, where its own versions
## are no-ops. New dev drivers go here, not in game.gd.
##
## Flags this file serves (each flag's arguments: the Command line list at the top of game.gd, which parses them):
##   --spawn-near --idle-monsters --stage-ledge --slay-near --kit-demo --hazard-near --hazard-demo --to-hazard
##   --to-gate --to-theme --to-corridor --to-exit --to-pool --to-package --to-door --to-employee --to-note --to-shark
##   --shark-demo --monster-demo --give --give-allies --hold --drop-near --focus dev|elevator --tour --autocast --aim-offset
##   --pause-demo --invite-demo --invoice-demo --press-e --break-crates --demo-damage --hud-stage
## and, parsed here (SewerDev.parse): --sewer N --sewer-demo overview|gator|nip|wire|sluice[:n]|outfall[:n] (the sewer slice:
## scripts/app/dev/sewer_dev.gd, docs/design/sewer-concept.md "Phase 1 as built"; --sewer N in a crew too since "Phase 2 as
## built"); --sewer-floor --to-sewer head|foot (a generated floor's sewer cluster, forced: "Phase 3 as built").

var _dev_monsters: Array[Monster] = []   ## --spawn-near
var _dev_sharks: Array[Shark] = []        ## --to-shark (the shark the --shark-demo acts on)
var _stage_center := Vector2i(1 << 20, 1 << 20)   ## --stage-ledge tower center
var _sewer_layout: Dictionary = {}       ## --sewer: the layout being played (SewerLayouts.build)
var _sewer_view: SewerView = null         ## ... its water and look
var _sewer_staged: Dictionary = {}       ## ... what SewerDev.stage put on it (gators, wires, monsters, scout)


func _parse_args() -> void:
	super()
	SewerDev.parse(OS.get_cmdline_user_args(), opts)


## --sewer N: the sewer layout to build, or 0. In a crew (sewer phase 2) every window needs the same flag (run.ps1 -Crew
## passes it to all): each builds the layout and its staging from the seed, and the load barrier's checksum sends out a
## window that built a different floor.
func _sewer() -> int:
	return int(opts.get("sewer", 0)) if not _dev_released else 0


## The game's floor hook: --sewer swaps the generated floor for the layout's map and plan (before the world is built).
func _dev_floor() -> void:
	if _sewer() <= 0:
		return
	_sewer_layout = SewerLayouts.build(_sewer())
	map = _sewer_layout["map"]
	_plan = SewerLayouts.plan(_sewer_layout, _floor_n(), _run)
	_dress_sewer.call_deferred()


## A generated floor's sewer cluster (phase 3): say where it is, and with --to-sewer put the crew at the stair's head.
func _sewer_floor_ready() -> void:
	var rec := SewerPlanner.record(map)
	if rec.is_empty():
		return
	var st: Dictionary = rec["stair"]
	var up: Vector2i = st["door_up"]
	_log("sewer cluster: %s at level %d, down the service stair from %s (its head at %s); %d gator, %d live wire" % [
		", ".join(rec["rooms"]), int(rec["level"]), st["from"], up, (rec.get("gators", []) as Array).size(),
		_site.wires.size() if _site != null else 0], Color(0.55, 0.9, 0.75))
	if opts.has("to_sewer") and not _shared:
		_teleport_crew(st["door"] if str(opts["to_sewer"]) == "foot" else up)


## The sewer's look over the terrain HexMapView just built: the water, foam, kerbs, the channel and the light.
func _dress_sewer() -> void:
	if not is_inside_tree() or map == null or _sewer_layout.is_empty():
		return
	_sewer_view = SewerView.dress(self, map, get_node_or_null("Terrain") as HexMapView, str(_sewer_layout["look"]), _sewer_layout["flows"])
	for w: LiveWire in (_sewer_staged.get("wires", []) as Array):
		w.view = _sewer_view


## The sewer's staging (SewerDev.stage), once the plan's props, notes and employee are in the world; its pest-kind
## monsters count toward the floor's pest objective.
func _sewer_populate() -> void:
	if _sewer() <= 0 or _site == null or _sewer_layout.is_empty() or not _sewer_staged.is_empty():
		return
	_sewer_staged = SewerDev.stage(_sewer_layout, _site, map, _run.floor_seed(_floor_n()), _sewer_view)
	var pests := int(_sewer_staged["pests"])
	_site.pest_spawned += pests
	var st := _session.state()
	if not st.is_empty():
		st["pest_spawned"] = int(st["pest_spawned"]) + pests
	_log("sewer %d: %s (%s): %d monsters, %d gator, %d live wire" % [_sewer(), _sewer_layout["name"], _sewer_layout["blurb"],
		(_sewer_staged["monsters"] as Array).size(), (_sewer_staged["gators"] as Array).size(), (_sewer_staged["wires"] as Array).size()], Color(0.55, 0.9, 0.75))


func _dev_on_floor_ready() -> void:
	_sewer_floor_ready()
	if _sewer() > 0 and opts.has("sewer_demo"):
		_sewer_demo(str(opts["sewer_demo"]))
	if opts.has("tour"):
		get_tree().create_timer(1.0).timeout.connect(_dev_tour)
	if opts.has("hazard_demo"):
		_hazard_demo(str(opts["hazard_demo"]))
	if opts.has("shark_demo"):
		_shark_demo(str(opts["shark_demo"]))
	if opts.has("monster_demo"):
		_monster_demo(str(opts["monster_demo"]))
	if opts.get("focus", "") == "dev" and _dev_centroid() != Vector3.INF:
		var marker := Node3D.new()
		GameWorld.root.add_child(marker)
		marker.global_position = _dev_centroid()
		rig.target = marker
		rig.snap()
	elif opts.get("focus", "") == "elevator" and _lift != null:
		var lm := Node3D.new()   # the camera looks at the elevator's landing (screenshots of a floor-1 elevator, shut)
		GameWorld.root.add_child(lm)
		lm.global_position = Hex.to_world(_exit_cell, float(map.get_cell(_exit_cell).level))
		rig.target = lm
		rig.snap()


func _dev_after_barrier() -> bool:
	if opts.has("slay_near"):
		get_tree().create_timer(1.5).timeout.connect(_slay_dev_monsters)
	if opts.has("kit_demo"):
		_kit_demo(str(opts["kit_demo"]))
	if opts.has("autocast"):
		await get_tree().create_timer(1.0).timeout
		if _shared:
			# A shared run (M4): the world is frozen behind the barrier, so cast once the floor runs and the crew is out of
			# the van (the cast is an event that lands on every screen).
			while is_inside_tree() and not (_floor_begun and _arrivals_done()):
				await get_tree().process_frame
			await get_tree().create_timer(float(opts.get("autocast_after", 0.5))).timeout
			if not is_inside_tree() or player == null:
				return false
		var centre := _dev_centroid()
		if opts.has("aim_offset"):
			var off := str(opts["aim_offset"]).split(",")
			centre = player.global_position + Vector3(float(off[0]), 0.0, float(off[1]) if off.size() > 1 else 0.0)
		if centre != Vector3.INF:
			controller.aim_override = centre
		_cast(str(opts["autocast"]), 1.0, "autocast")
	if opts.has("pause_demo"):
		_pause_demo()
	if opts.has("invite_demo"):
		_invite_demo()
	if opts.has("press_e"):
		get_tree().create_timer(float(opts["press_e"])).timeout.connect(func() -> void:
			if opts.has("to_note") and not _site.notes.is_empty():
				# the crew settles after the teleport; step the player back up to the note's front before E
				var n: ClueNote = _site.notes[clampi(int(opts["to_note"]), 0, _site.notes.size() - 1)]
				var f := ThemeGeo.facing(n.yaw - 90.0) * 1.2
				player.global_position = n.global_position + Vector3(f.x, 0.0, f.y)
				player.snap_to_ground()
			var used := controller.press_use()
			_log("press-e: %s" % ("used" if used else "nothing"), Color(0.8, 1.0, 0.8)))
	if opts.has("break_crates"):
		get_tree().create_timer(float(opts["break_crates"])).timeout.connect(_break_crates_dev)
	if opts.has("demo_damage"):
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			Ledger.damage("Vintage 1787 wine barrel", 4000, player)
			Ledger.damage("Zen fountain", 900, allies[0]))
	if opts.has("hud_stage") or opts.has("hud_followers"):
		HudStage.run(self, str(opts.get("hud_stage", "solo")), int(opts.get("hud_followers", 0)), float(opts.get("shot_after", 3.0)))
	return true


## --tour S: walk the player along a path toward the elevator for S seconds (the controller's move_override), then stop.
func _dev_tour() -> void:
	if player == null or controller == null or map == null:
		return
	var goal_cell := _exit_cell if map.has_cell(_exit_cell) else player.current_cell()
	if opts.has("to_door") and _site != null and not _site.plan.doors.is_empty():
		goal_cell = _door_cells_dev(_site.plan.doors[clampi(int(opts["to_door"]), 0, _site.plan.doors.size() - 1)])[1]
	var path := map.find_path(player.current_cell(), goal_cell, true)
	print("[game] tour: %d cells toward %s" % [path.size(), goal_cell])
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var state := {"i": 1, "end": GameWorld.time + float(opts["tour"]), "n": 0, "cpu": 0.0, "gpu": 0.0, "fog": 0.0}
	var step := func() -> void:
		if not is_instance_valid(player) or controller == null:
			return
		var i: int = state["i"]
		if GameWorld.time > float(state["end"]) or i >= path.size():
			if controller.move_override != Vector3.INF:
				# frame cost over the walk (the fog's CPU share: FogView's last update + contents pass, sampled per tick)
				var n := maxf(1.0, float(state["n"]))
				print("[game] tour: stopped at cell %d of %d, %s; frames: process+render %.2f ms (vsync-bound), gpu %.2f ms, fog cpu %.3f ms (%s)" % [i, path.size(),
						player.current_cell(), float(state["cpu"]) / n, float(state["gpu"]) / n, float(state["fog"]) / n,
						"fog off" if fog_view == null else "fog on"])
			controller.move_override = Vector3.INF
			return
		state["n"] = int(state["n"]) + 1
		state["cpu"] = float(state["cpu"]) + RenderingServer.viewport_get_measured_render_time_cpu(vp) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		state["gpu"] = float(state["gpu"]) + RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if fog_view != null:
			state["fog"] = float(state["fog"]) + (float(fog_view.stats.get("contents_us", 0.0)) + float(fog_view.stats.get("update_us", 0.0)) / (FogView.UPDATE_EVERY * 60.0)) / 1000.0
		var d := Hex.to_world(path[i]) - player.global_position
		d.y = 0.0
		if d.length() < 0.45:
			state["i"] = i + 1
		# The path knows walls, not the van or a crate: no headway for 0.3 s and it sidesteps for 0.5 s.
		var t := GameWorld.time
		if d.length() < float(state.get("best", INF)) - 0.05:
			state["best"] = d.length()
			state["since"] = t
		elif t - float(state.get("since", t)) > 0.3:
			state["side"] = t + 0.5
			state["since"] = t + 0.5
			state["best"] = INF
		var dir := d.normalized() if d.length() > 0.01 else Vector3.ZERO
		if t < float(state.get("side", -1.0)):
			dir = (dir + Vector3(-dir.z, 0.0, dir.x) * 1.5).normalized()
		if int(state["i"]) != i:
			state["best"] = INF
		controller.move_override = dir
	get_tree().physics_frame.connect(step)


## --pause-demo: open the pause overlay 1.5 s into the floor (a shared run: 1.5 s after the shared start and the arrival).
func _pause_demo() -> void:
	if _shared:
		while is_inside_tree() and not (_floor_begun and _arrivals_done()):
			await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree() and _can_pause():
		_open_pause()


## --invite-demo: the overlay-invite question 1.5 s into the floor, as if Steam had sent one (M7 screenshots).
func _invite_demo() -> void:
	if _shared:
		while is_inside_tree() and not (_floor_begun and _arrivals_done()):
			await get_tree().process_frame
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree() and not _leaving:
		Session.pending_invite = {"lobby": 0, "inviter": str(opts["invite_demo"])}
		_on_invite(0, str(opts["invite_demo"]))


## --invoice-demo: a sample contract with a believable ledger, straight to the invoice.
func _invoice_demo() -> void:
	var run := ContractBoard.run_for_seed(int(opts.get("seed", 12)))
	var s := ContractSession.begin(run, 1)
	var wick := _demo_hero("Wick")
	var rebar := _demo_hero("Rebar")
	var gasket := _demo_hero("Gasket")
	s.enter_floor(1, run.floor_gates[0], false, run.floor_employees[0], 12)
	for _i in run.floor_gates[0]:
		s.gate_closed(false)
	s.check_clean(0)
	s.extract(2)
	Ledger.damage("Wine rack", 1200, wick)
	s.enter_floor(2, run.floor_gates[1], false, run.floor_employees[1], 14)
	for _i in run.floor_gates[1]:
		s.gate_closed(false)
	s.check_clean(0)
	Ledger.damage("Zen fountain", 900, rebar)
	Ledger.damage("Crystal lamp", 600, wick)
	Ledger.damage("Crystal lamp", 600, gasket)
	s.employee_lost("Pearl (valet)", "Wick")
	s.enter_floor(3, 0, true, run.floor_employees[2], 18)
	s.gate_closed(true)
	s.check_clean(0)
	s.extract(1)
	Ledger.damage("Gold toilet", 15000, wick)
	s.finish(ContractSession.END_CASHED_OUT)
	var inv := ContractInvoice.build(s)
	for h in [wick, rebar, gasket]:
		h.free()
	_session = s
	_run = run
	_show_invoice(inv)
	_invoice.next_contract.disconnect(_on_next_contract)


func _demo_hero(hero_name: String) -> Actor:
	var a := Actor.new()
	a.display_name = hero_name
	return a


## --to-door N: [a hall cell two back from the door's mouth, a room cell four past the door] (a straight line through it).
func _door_cells_dev(rec: Dictionary) -> Array[Vector2i]:
	var door_c: Vector2i = (rec["door_cells"] as Array)[0]
	var mouth_c: Vector2i = (rec["mouth_cells"] as Array)[0]
	var step := door_c - mouth_c
	var stand := mouth_c - step * 2
	if not map.is_walkable_cell(stand):
		stand = mouth_c
	var inside := door_c + step * 4
	if not map.is_walkable_cell(inside):
		inside = door_c + step
	return [stand, inside]


## Dev flags --to-gate / --to-exit: move the crew (screenshots).
func _dev_teleports() -> void:
	if opts.has("to_hazard") and _to_hazard(str(opts["to_hazard"])):
		return
	if opts.has("to_shark") and _to_shark(str(opts["to_shark"])):
		return
	if opts.has("to_pool") and _to_pool(str(opts["to_pool"])):
		return
	if opts.has("to_theme") and _site != null:
		var themed := _site.plan.rooms_with_theme(str(opts["to_theme"]))
		if not themed.is_empty():
			# the middle of the room's set dressing (the room's centre when it has none)
			var focus: Vector2i = _site.plan.centers[themed[0]]
			var sum := Vector2.ZERO
			var n := 0
			for dc in _site.plan.decor:
				if str(dc["room"]) == themed[0] and String(dc["place"]) != "ring":
					sum += dc["pos"]
					n += 1
			if n > 0:
				var mid := sum / float(n)
				focus = Hex.from_world(Vector3(mid.x, 0.0, mid.y))
				if map.get_cell(focus) == null or map.get_cell(focus).type != HexMap.Tile.FLOOR:
					focus = _site.plan.centers[themed[0]]
			if opts.get("focus", "") == "sign":
				# a few steps in front of the room's neon sign (screenshots of the sign)
				for dc in _site.plan.decor:
					if str(dc["room"]) == themed[0] and str(dc["kind"]) == "neon_sign":
						var front: Vector2 = (dc["pos"] as Vector2) + ThemeGeo.facing(float(dc["yaw"])) * 5.5
						var fc := Hex.from_world(Vector3(front.x, 0.0, front.y))
						if map.is_walkable_cell(fc):
							focus = fc
			_teleport_crew(focus)
			return
	if opts.has("to_corridor"):
		var corr: Array[Vector2i] = []
		for cc: Vector2i in map.cells:
			if map.cells[cc].tag == "corridor" and map.is_walkable_cell(cc):
				corr.append(cc)
		if not corr.is_empty():
			corr.sort()
			_teleport_crew(corr[int(corr.size() * 0.5)])
			return
	if opts.has("to_door") and _site != null and not _site.plan.doors.is_empty():
		# in the hall, two cells back from door N's mouth (--tour then walks through it into the room)
		var stand2 := _door_cells_dev(_site.plan.doors[clampi(int(opts["to_door"]), 0, _site.plan.doors.size() - 1)])[0]
		_teleport_crew(stand2)
		return
	if opts.has("to_note") and _site != null and not _site.plan.notes.is_empty():
		# beside note N (the story note is 0, the hint slip 1), off to its side so nobody hides it from the camera
		var nt: Dictionary = _site.plan.notes[clampi(int(opts["to_note"]), 0, _site.plan.notes.size() - 1)]
		var nc: Vector2i = nt["cell"]
		var front := ThemeGeo.world(nc) + ThemeGeo.facing(float(nt.get("yaw", 0.0)) - 90.0) * 1.5
		var stand := nc
		var stand_d := INF
		var nlevel: int = map.get_cell(nc).level
		for c in Hex.range_cells(nc, 2):
			var cell4: HexMap.Cell = map.get_cell(c)
			if c != nc and cell4 != null and cell4.type == HexMap.Tile.FLOOR and cell4.level == nlevel and not _site.plan.blocked.has(c) 					and ThemeGeo.world(c).distance_to(front) < stand_d:
				stand_d = ThemeGeo.world(c).distance_to(front)
				stand = c
		_teleport_crew(stand)
		_log("to-note: %s %s at %s, crew at %s" % [nt["kind"], nt["format"], nc, stand], Color(0.8, 0.8, 1.0))
		return
	if opts.has("to_employee") and _site != null and not _site.plan.employees.is_empty():
		var ec: Vector2i = _site.plan.employees[0]["cell"]
		var stand := ec
		for c in Hex.ring(ec, 1):
			var cell3: HexMap.Cell = map.get_cell(c)
			if cell3 != null and cell3.type == HexMap.Tile.FLOOR:
				stand = c
				break
		_teleport_crew(stand)
		return
	if opts.has("to_package") and _site != null and not _site.plan.packages.is_empty():
		# two cells from the first stack, toward the middle of its room
		var pk: Dictionary = _site.plan.packages[0]
		var pc: Vector2i = pk["cell"]
		var mid: Vector2i = _site.plan.centers[str(pk["room"])]
		var near := pc
		var near_d := 99
		for c in Hex.ring(pc, 2):
			var cell2: HexMap.Cell = map.get_cell(c)
			if cell2 != null and cell2.type == HexMap.Tile.FLOOR and Hex.distance(c, mid) < near_d:
				near_d = Hex.distance(c, mid)
				near = c
		_teleport_crew(near)
		return
	if opts.has("to_gate") and _site != null and not _site.gates.is_empty():
		var gc: Vector2i = _site.plan.gates[0]["cell"]
		var best := gc
		var best_d := 99
		for c in Hex.ring(gc, 5):
			var cell: HexMap.Cell = map.get_cell(c)
			if cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - map.get_cell(gc).level) <= 1:
				var d := Hex.distance(c, gc)
				if d < best_d:
					best_d = d
					best = c
		_teleport_crew(best)
	elif opts.has("to_exit"):
		_teleport_crew(_exit_cell)


## Dev flag --break-crates: hit the crate stacks around the player (screenshots of the break).
func _break_crates_dev() -> void:
	for a in GameWorld.breakables_in_radius(player.global_position, 9.0):
		if a is BreakableCrate:
			a.apply_damage(5.0, player)


## --to-pool: the crew at the floor's first pool (of `look`, any when ""): seat 1 wading in the middle, seat 2 on the deck at
## the camera-near rim, seat 3 wading by the far rim; at a moat all three wade along the channel nearest the camera.
## False when the floor has no such pool.
func _to_pool(look: String) -> bool:
	for rec in map.pools:
		_log("pool: %s in %s (%s), %d basin cells" % [rec["look"], rec["room"], _site.plan.theme_of(str(rec["room"])) if _site != null else "", (rec["basin"] as Array).size()], Color(0.6, 0.9, 1.0))
	for rec in map.pools:
		if look != "" and str(rec["look"]) != look:
			continue
		var c: Vector2 = rec["center"]
		var ax: Vector2 = rec["axis"]
		var n := Vector2(-ax.y, ax.x)
		if n.dot(ThemeGeo.CAMERA_DIR) < 0.0:
			n = -n   # toward the camera
		var hw := float(rec["half_wid"])
		var spots: Array[Vector2] = [c + ax * 0.6, c + n * (hw + 0.75) - ax * 0.4, c - n * (hw - 0.75) - ax * 1.2]
		var path := PoolGeo.channel(rec)
		if path.size() >= 3:
			# a moat: the whole crew wading along the channel on the side nearest the camera
			var total := 0.0
			for i in path.size():
				total += path[i].distance_to(path[(i + 1) % path.size()])
			var best_s := 0.0
			var best := -INF
			for k in 64:
				var s := total * float(k) / 64.0
				var q: Vector2 = DecorAnim.path_pose(path, total, s)[0]
				if q.dot(ThemeGeo.CAMERA_DIR) > best:
					best = q.dot(ThemeGeo.CAMERA_DIR)
					best_s = s
			spots.clear()
			if opts.get("focus", "") == "island_corner":
				best_s += total * 0.5   # (on the far side, out of the way of the island corner the camera looks at)
			for off: float in [0.0, -1.7, 1.7]:
				spots.append(DecorAnim.path_pose(path, total, best_s + off)[0])
		var list: Array[Hero] = []
		for seat in range(1, NetSession.MAX_CREW + 1):
			if heroes_by_seat.has(seat):
				list.append(heroes_by_seat[seat])
		for i in list.size():
			var p: Vector2 = spots[mini(i, spots.size() - 1)]
			list[i].global_position = Vector3(p.x, 0.0, p.y)
			list[i].snap_to_ground()
			list[i].facing = Vector3(-n.x, 0.0, -n.y) if i == 1 and path.size() < 3 else Vector3(n.x, 0.0, n.y)
			var brain := list[i].get_node_or_null("AllyBrain")
			if brain != null:
				brain.set_physics_process(false)   # (the allies hold their spots for the screenshot)
		if opts.get("focus", "") == "pool_corner":
			# the corner farthest from the camera: the liner, the coping and the deck all show there
			var best: Vector2 = (rec["outline"] as Array)[0]
			for q: Vector2 in (rec["outline"] as Array):
				if q.dot(ThemeGeo.CAMERA_DIR) < best.dot(ThemeGeo.CAMERA_DIR):
					best = q
			var mk := Node3D.new()
			GameWorld.root.add_child(mk)
			mk.global_position = Vector3(best.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, best.y)
			rig.target = mk
		elif path.size() >= 3 and not opts.has("focus"):
			# a moat: look at the whole ring, not just the player
			var mc := Node3D.new()
			GameWorld.root.add_child(mc)
			mc.global_position = Vector3(c.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, c.y)
			rig.target = mc
		elif opts.get("focus", "") == "island_corner" and not (rec.get("hole", []) as Array).is_empty():
			# a moat's island corner nearest the camera: the island's liner, its coping and the water round it show there
			var best: Vector2 = (rec["hole"] as Array)[0]
			for q: Vector2 in (rec["hole"] as Array):
				if q.dot(ThemeGeo.CAMERA_DIR) > best.dot(ThemeGeo.CAMERA_DIR):
					best = q
			var mk := Node3D.new()
			GameWorld.root.add_child(mk)
			mk.global_position = Vector3(best.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, best.y)
			rig.target = mk
		rig.snap()
		return true
	return false


func _teleport_crew(cell: Vector2i) -> void:
	var spots := _free_cells_near(cell, 2)
	# In seat order (solo that is the player, Rebar, Gasket, as before), so every machine of a crew puts every hero on the
	# same cell and the floor checksum agrees (the player is a different seat on each machine).
	var list: Array[Hero] = []
	for seat in range(1, NetSession.MAX_CREW + 1):
		if heroes_by_seat.has(seat):
			list.append(heroes_by_seat[seat])
	if list.size() != _heroes().size():
		list = _heroes()
	for i in list.size():
		var c := cell if i == 0 else spots[(i - 1) % spots.size()]
		var lv := map.ground_level(Hex.to_world(c))
		list[i].global_position = Hex.to_world(c, 0.0 if is_nan(lv) else lv)
		list[i].snap_to_ground()
	rig.snap()


## Dev flag --give: "heal:9,corn:3" slots (or tops up) those spells with those charges.
func _apply_dev_loadout() -> void:
	if opts.has("give"):
		for part in str(opts["give"]).split(","):
			var bits := part.strip_edges().split(":")
			var id := bits[0].strip_edges()
			var n := int(bits[1]) if bits.size() > 1 else SpellComponents.START_CHARGES
			if SpellBook.is_available(id):
				player.slot_in(id, n)
	if opts.has("hold"):
		player.select_slot(int(opts["hold"]) - 1)
	if opts.has("give_allies"):
		var ids := str(opts["give_allies"]).split(",")
		for i in mini(ids.size(), allies.size()):
			allies[i].slot_in(ids[i].strip_edges(), SpellComponents.START_CHARGES)


## Dev flag --drop-near: pickups for the listed spells, right next to the player.
func _drop_near() -> void:
	if not opts.has("drop_near"):
		return
	var ids := str(opts["drop_near"]).split(",")
	# The first one lies just outside the collect radius but inside the swap radius, so a hero with
	# full slots is offered the swap at once; the rest follow in a row.
	var base := player.global_position + Vector3(0.9, 0.0, 0.55)
	for i in ids.size():
		var id := ids[i].strip_edges()
		var p := ComponentPickup.drop(id, SpellComponents.PICKUP_CHARGES, base + Vector3(0.0, 0.0, 1.4 * i))
		_log("drop-near: %s %s" % [id, "ok" if p != null else "no floor"], Color(0.8, 0.8, 1.0))


## Dev flag --hazard-near kind[,kind...]: explosive props (ExplosiveProp) in a cluster on open floor 3-6 cells from seat 1's
## hero, each 2.4-3.1 units from the one before (inside its blast: they chain). Built in _start, before the barrier numbers
## the floor, so every machine of a crew builds the same ones (tests, screenshots).
func _hazard_near() -> void:
	if not opts.has("hazard_near"):
		return
	var near_hero: Hero = heroes_by_seat.get(1, player) if _shared else player
	var here := near_hero.current_cell()
	var level: int = map.get_cell(here).level
	var cands: Array[Vector2i] = []
	for c in Hex.range_cells(here, 6):
		if Hex.distance(c, here) >= 3 and map.is_walkable_cell(c) and map.get_cell(c).level == level:
			cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Hex.distance(a, here)
		var db := Hex.distance(b, here)
		return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	var placed: Array[Vector3] = []
	for k in str(opts["hazard_near"]).split(","):
		var kind := k.strip_edges()
		for c in cands:
			var w := Hex.to_world(c)
			var ok := true
			var near_last := placed.is_empty()
			for q in placed:
				var d := GameWorld.flat_distance(q, w)
				ok = ok and d >= 2.4
			if not placed.is_empty():
				var d_last := GameWorld.flat_distance(placed.back(), w)
				near_last = d_last >= 2.4 and d_last <= 3.1
			if not ok or not near_last:
				continue
			var e := PricedProp.spawn(c, kind, {})
			if e != null:
				placed.append(w)
				_dev_hazards.append(e)
			break
	_log("hazard-near: %d explosive props" % placed.size(), Color(0.8, 0.8, 1.0))


## Dev flag --to-hazard kind[:n] ("any": any kind): the crew stands a few steps beside the floor's first (n-th) explosive
## prop of that kind, and --focus dev puts the camera on it (screenshots).
func _to_hazard(want: String) -> bool:
	if _site == null:
		return false
	var skip := int(want.get_slice(":", 1)) if want.contains(":") else 0   # kind:n = the n-th of that kind
	want = want.get_slice(":", 0)
	for h in _site.hazards:
		var e := h as ExplosiveProp
		if e == null or (want != "any" and e.kind != want):
			continue
		if skip > 0:
			skip -= 1
			continue
		# off to one side of it (in front, the crew would stand between the camera and the prop)
		var f := e.facing_vector()
		var best := Hex.from_world(e.global_position)
		var best_d := INF
		for side: float in [1.0, -1.0]:
			var target := e.global_position + Vector3(f.x, 0.0, f.y) * 1.2 + Vector3(-f.y, 0.0, f.x) * 3.6 * side
			for c in Hex.range_cells(Hex.from_world(target), 2):
				var d := Hex.to_world(c).distance_to(target) + (0.0 if side > 0.0 else 0.5)
				if map.is_walkable_cell(c) and not _site.plan.blocked.has(c) and d < best_d:
					best_d = d
					best = c
		_teleport_crew(best)
		_dev_hazards.append(e)
		_log("to-hazard: %s in %s" % [e.display_name, _site.plan.theme_of(str(_site.plan.hazards[_site.hazards.find(h)]["room"]))], Color(0.8, 0.8, 1.0))
		return true
	return false


## Dev flag --to-shark [regular|laser|imp|lagoon|any] (screenshots): the crew on the deck beside the floor's first pool shark
## of that variant (lagoon: the first in a lagoon), the camera on its pool, the AI allies holding their spots. Sharks live
## from floor 2 (the log lists the floor's sharks).
func _to_shark(want: String) -> bool:
	if _site == null:
		return false
	for s in _site.sharks:
		_log("shark: %s in %s (pool %d%s)" % [s.variant, str(s.pool_record().get("room", "")), s.pool_index,
			", lagoon" if str(s.pool_record().get("shape", "")) == PoolGeo.LAGOON else ""], Color(0.6, 0.9, 1.0))
	for s in _site.sharks:
		var rec := s.pool_record()
		if want == "lagoon":
			if str(rec.get("shape", "")) != PoolGeo.LAGOON:
				continue
		elif want != "any" and want != "" and s.variant != want:
			continue
		# the rim nearest the camera: the crew stands on the deck there, the player closest
		var c: Vector2 = rec["center"]
		var ol: Array = rec["outline"]
		var normals := PoolGeo.edge_normals(ol)
		var best := 0
		for i in normals.size():
			if normals[i].dot(ThemeGeo.CAMERA_DIR) > normals[best].dot(ThemeGeo.CAMERA_DIR):
				best = i
		var a: Vector2 = ol[best]
		var b: Vector2 = ol[(best + 1) % ol.size()]
		var n: Vector2 = normals[best]
		var t := (b - a).normalized()
		var spots: Array[Vector2] = [(a + b) * 0.5 + n * 1.6, (a + b) * 0.5 + n * 2.6 + t * 2.2, (a + b) * 0.5 + n * 2.6 - t * 2.2]
		if opts.get("shark_demo", "") == "laser":
			spots[0] = (a + b) * 0.5 + n * 6.0
		var list: Array[Hero] = []
		for seat in range(1, NetSession.MAX_CREW + 1):
			if heroes_by_seat.has(seat):
				list.append(heroes_by_seat[seat])
		var deck_lv := int(rec["deck_level"])
		var room := str(rec["room"])
		for i in list.size():
			var p: Vector2 = spots[mini(i, spots.size() - 1)]
			# onto the nearest dry floor of the pool's room at deck level (a spot past the room's wall would be void)
			var wish := Vector3(p.x, 0.0, p.y)
			var best_c := Hex.from_world(wish)
			var best_d := INF
			for cc in Hex.range_cells(Hex.from_world(wish), 4):
				var cell := map.get_cell(cc)
				if cell == null or not map.is_walkable_cell(cc) or map.is_pool_cell(cc) or cell.level != deck_lv or cell.tag != room:
					continue
				var dd := Hex.to_world(cc).distance_to(wish)
				if dd < best_d:
					best_d = dd
					best_c = cc
			if best_d < INF and best_d > 0.9:
				var w := Hex.to_world(best_c)
				p = Vector2(w.x, w.z)
			list[i].global_position = Vector3(p.x, 0.0, p.y)
			list[i].snap_to_ground()
			list[i].facing = Vector3(-n.x, 0.0, -n.y)
			var brain := list[i].get_node_or_null("AllyBrain")
			if brain != null:
				brain.set_physics_process(false)
		var mk := Node3D.new()
		GameWorld.root.add_child(mk)
		var mid := c.lerp((a + b) * 0.5 + n * 2.0, 0.45)
		mk.global_position = Vector3(mid.x, float(rec["deck_level"]) * Hex.LEVEL_HEIGHT, mid.y)
		rig.target = mk
		rig.snap()
		_dev_sharks.append(s)
		return true
	return false


## Dev flag --shark-demo bite|laser|knock|kill (with --to-shark; screenshots), after --demo-after seconds (1.0):
##   bite   the player steps to the rim: the shark comes for it (its own senses)
##   laser  the shark charges at the player (who stands 6 out on the deck) and fires
##   knock  the player's shove (2.0) knocks the imp gunner off its shark
##   kill   the player's hit kills the shark (the bill)
func _shark_demo(stage: String) -> void:
	await get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
	if _dev_sharks.is_empty() or player == null:
		return
	var s: Shark = _dev_sharks[0]
	if not is_instance_valid(s) or s.dead:
		return
	match stage:
		"bite":
			var p := Vector2(player.global_position.x, player.global_position.z)
			var out := s.steer.out_of_water(p)
			var q := p
			for _i in 40:
				if s.steer.rim(q) > -0.7:
					break
				q -= out * 0.1
			player.global_position = Vector3(q.x, player.global_position.y, q.y)
			player.snap_to_ground()
		"laser":
			if s.has_laser():
				# the player steps onto the deck ahead of the shark's snout (in its nose cone), then it charges
				var rec := s.pool_record()
				var best := Vector3.INF
				var best_d := INF
				for d: float in [6.0, 5.0, 7.0, 4.5, 8.0]:
					var want_at := s.global_position + s.facing * d
					for cc in Hex.range_cells(Hex.from_world(want_at), 2):
						var cell := map.get_cell(cc)
						if cell == null or not map.is_walkable_cell(cc) or map.is_pool_cell(cc) or cell.level != int(rec["deck_level"]):
							continue
						var w := Hex.to_world(cc)
						var to := w - s.global_position
						to.y = 0.0
						var off := rad_to_deg(Vector2(s.facing.x, s.facing.z).angle_to(Vector2(to.x, to.z)))
						var score := absf(off) * 0.1 + absf(to.length() - 6.0)
						if absf(off) < 30.0 and s.steer.rim(Vector2(w.x, w.z)) < -1.4 and score < best_d:
							best_d = score
							best = w
					if best != Vector3.INF:
						break
				if best != Vector3.INF:
					player.global_position = Vector3(best.x, player.global_position.y, best.z)
					player.snap_to_ground()
				s._begin_charge(player)
		"knock":
			if s.rider != null and is_instance_valid(s.rider):
				s.rider.shove(s.rider.global_position - player.global_position, 2.0, player)
		"kill":
			s.apply_damage(s.hp + 1.0, player)


## Dev flag --monster-demo aim|pulse (with --spawn-near holding a pavise / a water boy; screenshots), after --demo-after
## seconds (1.0). The AI allies hold still; the monsters (frozen until then with --idle-monsters, so the allies leave them
## alone) wake with their own sight and run their own AI from there.
##   aim    the pavise stands 7-9 from the player (to the screen's right if it can), plants facing them and aims (the dashed line
##          tracks for 0.8 s, then the solid line locks for 0.4 s and the bolt looses)
##   pulse  the pack is roughed up (each other monster 40% down), and the water boy raises its whistle and pours (0.8 s)
##   goo    the goo imps (--spawn-near goo_imp,3) wake on the player and throw: tell 0.7 s, then about a second in the air
func _monster_demo(stage: String) -> void:
	await get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
	if player == null or not is_inside_tree():
		return
	for ally in allies:
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
	var pv: Pavise = null
	var wb: WaterBoy = null
	for m in _dev_monsters:
		if not is_instance_valid(m) or m.dead:
			continue
		if m.aggro_range <= 0.0:
			var probe: Monster = MonsterDefs.scripts()[m.kind].new()
			m.aggro_range = probe.aggro_range   # (--idle-monsters froze it: its own sight back)
			probe.free()
		if m is Pavise and pv == null:
			pv = m as Pavise
		elif m is WaterBoy and wb == null:
			wb = m as WaterBoy
	match stage:
		"aim":
			if pv == null:
				return
			var up := Vector3(cos(deg_to_rad(45.0)), 0.0, -sin(deg_to_rad(45.0)))   # (screen right, clear of the HUD and the banner)
			var placed := false
			for turn: float in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
				for d: float in [7.5, 8.5, 6.5, 9.5]:
					var at := player.global_position + up.rotated(Vector3.UP, deg_to_rad(turn)) * d
					var c := Hex.from_world(at)
					if not map.is_walkable_cell(c) or map.get_cell(c).level != map.get_cell(player.current_cell()).level:
						continue
					var w := Hex.to_world(c, float(map.get_cell(c).level))
					if map.line_of_sight(w + Vector3.UP * 1.25, player.global_position + Vector3.UP * 1.25, 0.08):
						pv.global_position = w
						placed = true
						break
				if placed:
					break
			pv.aggro(player)
			pv.set_spawn_facing(player.global_position - pv.global_position)
			pv._mark = player
			pv._mark_t = 99.0
			pv.target = player
			pv._set_shield(Pavise.Shield.PLANTED)
			pv._phase = Pavise.Phase.AIM
			pv._begin_charge(player)
		"pulse":
			if wb == null:
				return
			for m in _dev_monsters:
				if is_instance_valid(m) and not m.dead and m != wb:
					m.apply_damage(m.max_hp * 0.4, player)
			wb.aggro(player)
			wb.target = player
			wb._begin_windup(WaterBoy.POUR_TELL)
		"goo":   # (goo-imp.md: --spawn-near goo_imp,3 --idle-monsters: the goo imps wake on the player and throw)
			for m in _dev_monsters:
				if is_instance_valid(m) and not m.dead and m is GooImp:
					m.aggro(player)


## Dev flag --hazard-demo fuse|chain|invoice (with --hazard-near or --to-hazard; screenshots): after --demo-after seconds (1.0)
## the player sets off the first one. "chain" and "invoice" stand two frozen grunts beside each explosive first;
## "invoice" cashes out 2.5 s after the last blast, so the invoice shows the bill.
func _hazard_demo(stage: String) -> void:
	await get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
	var list: Array[ExplosiveProp] = []
	for h in _dev_hazards:
		if is_instance_valid(h) and h is ExplosiveProp and not h.dead:
			list.append(h as ExplosiveProp)
	if list.is_empty() or player == null:
		return
	if stage != "fuse":
		var k := 0
		for e in list:
			for a: float in [0.6, 2.4]:
				var ang := a + float(k) * 1.1
				var at := e.global_position + Vector3(cos(ang), 0.0, sin(ang)) * 1.7
				if not map.is_walkable_cell(Hex.from_world(at)):
					continue
				var m := MonsterFactory.spawn("grunt", Hex.from_world(at))
				if m != null:
					m.global_position = Vector3(at.x, m.global_position.y, at.z)
					m.snap_to_ground()
					m.set_physics_process(false)
			k += 1
	list[0].ignite(player)
	if stage != "invoice":
		return
	while list.any(func(e: ExplosiveProp) -> bool: return is_instance_valid(e) and not e.dead):
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(2.5).timeout
	_end_contract(ContractSession.END_CASHED_OUT)


## Dev flag --kit-demo: show one hero's primary / secondary on the --spawn-near monsters (screenshots).
func _kit_demo(kind: String) -> void:
	for ally in allies:   # only the demo hero acts
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
	await get_tree().create_timer(0.8).timeout
	var centre := _dev_centroid()
	if centre == Vector3.INF:
		return
	if kind == "draw":
		controller.enabled = false   # no mouse button is held, so the controller would release at once
		player.face_point(centre)
		player.start_draw()
		await get_tree().create_timer(1.3).timeout
		player.release_draw(centre - player.global_position)
		return
	var hero: Hero = allies[0]
	for h: Hero in allies:   # (by kit, not seat: the AI seats depend on the pick)
		if h.kit_id == (HeroKit.GASKET if kind == "hammer" else HeroKit.REBAR):
			hero = h
	var away := (centre - player.global_position)
	away.y = 0.0
	away = away.normalized()
	var spot := centre - away * (hero.melee_reach - 0.25)
	hero.global_position = Vector3(spot.x, hero.global_position.y, spot.z)
	hero.snap_to_ground()
	hero.face_point(centre)
	hero.melee(away)


func _slay_dev_monsters() -> void:
	for m in _dev_monsters:
		if is_instance_valid(m) and not m.dead:
			m.die()


## Dev flag --spawn-near kind,n: n extra monsters of `kind` on open floor 4-5 cells from the player. A mixed pack is
## groups joined by "+" (e.g. pavise,1+grunt,2+water_boy,1): each group as its own spawn, in order. (The game calls this
## hook once the floor's site is spawned: the --sewer staging goes in here too.)
func _spawn_near() -> void:
	_sewer_populate()
	if not opts.has("spawn_near"):
		return
	var groups := str(opts["spawn_near"]).split("+")
	if groups.size() > 1:
		var all: Array[Monster] = []
		for g in groups:
			_dev_monsters.clear()
			opts["spawn_near"] = g
			_spawn_near()
			all.append_array(_dev_monsters)
		_dev_monsters = all
		opts["spawn_near"] = "+".join(groups)
		return
	var parts := str(opts["spawn_near"]).split(",")
	var kind := parts[0].strip_edges()
	var n := int(parts[1]) if parts.size() > 1 else 3
	if map.has_cell(_stage_center):
		for c in Hex.ring(_stage_center, 1):
			if _dev_monsters.size() >= n:
				break
			var tm := MonsterFactory.spawn(kind, c)
			if tm != null:
				_dev_monsters.append(tm)
		_log("spawn-near: %d %s on the tower" % [_dev_monsters.size(), kind], Color(0.8, 0.8, 1.0))
		return
	var near_hero: Hero = heroes_by_seat.get(1, player) if _shared else player   # (a shared run: seat 1's spot on every machine)
	var here := near_hero.current_cell()
	var base_level: int = map.get_cell(here).level
	var cands: Array[Vector2i] = []
	for c in Hex.range_cells(here, 5):
		var d := Hex.distance(c, here)
		var cell: HexMap.Cell = map.get_cell(c)
		if d >= 4 and cell != null and cell.type == HexMap.Tile.FLOOR and absi(cell.level - base_level) <= 1:
			cands.append(c)
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if parts.size() > 2 and parts[2].strip_edges() == "cluster":
		# Candidates 5-7 cells out with a clear view of the player (so Rebar can bowl at them).
		cands.clear()
		for c in Hex.range_cells(here, 7):
			var cc: HexMap.Cell = map.get_cell(c)
			if Hex.distance(c, here) >= 5 and cc != null and cc.type == HexMap.Tile.FLOOR and cc.level == base_level:
				if map.line_of_sight(Combat.chest(near_hero), Hex.to_world(c, cc.level) + Vector3.UP * 0.9):
					cands.append(c)
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if parts.size() > 2 and parts[2].strip_edges() == "cluster" and not cands.is_empty():
		# A tight clump: the n candidates nearest to the first one.
		var anchor := cands[0]
		cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Hex.distance(a, anchor) < Hex.distance(b, anchor))
		for c in cands:
			if _dev_monsters.size() >= n:
				break
			var cm := MonsterFactory.spawn(kind, c)
			if cm != null:
				_dev_monsters.append(cm)
	else:
		# Spread them: take every k-th candidate.
		var stride := maxi(1, cands.size() / maxi(n, 1))
		var i := 0
		while _dev_monsters.size() < n and i < cands.size():
			if not GameWorld.actors_in_radius(Hex.to_world(cands[i]), 1.0).is_empty():
				i += 1   # (a mixed pack: an earlier group stands there)
				continue
			var m := MonsterFactory.spawn(kind, cands[i])
			if m != null:
				_dev_monsters.append(m)
			i += stride
	if opts.has("idle_monsters"):
		for im in _dev_monsters:
			im.aggro_range = 0.0
	_log("spawn-near: %d %s" % [_dev_monsters.size(), kind], Color(0.8, 0.8, 1.0))


## Average position of the living --spawn-near monsters, or Vector3.INF if none.
func _dev_centroid() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for m in _dev_monsters:
		if is_instance_valid(m) and not m.dead:
			sum += m.global_position
			count += 1
	for h in _dev_hazards:   # (--hazard-near / --to-hazard: the explosives)
		if is_instance_valid(h) and not h.dead:
			sum += h.global_position
			count += 1
	return sum / count if count > 0 else Vector3.INF


## Dev flag --stage-ledge: a 7-cell tower 5 levels tall on the roomiest flat ground 2-5 cells from
## the start (so a shove off its edge is a 5-level fall onto open floor). --spawn-near then stands
## its monsters on top.
func _stage_plateau() -> void:
	var start: Vector2i = map.cells_with_tag("start")[0]
	var base: int = map.get_cell(start).level
	var best := Vector2i(1 << 20, 1 << 20)
	var best_score := -1
	for c in Hex.range_cells(start, 5):
		if Hex.distance(c, start) < 3:
			continue
		var ok := true
		for n in Hex.range_cells(c, 1):
			var cell: HexMap.Cell = map.get_cell(n)
			if cell == null or cell.type != HexMap.Tile.FLOOR or cell.level != base or Hex.distance(n, start) < 2:
				ok = false
				break
		if not ok:
			continue
		var score := 0
		for n in Hex.range_cells(c, 4):
			var cell: HexMap.Cell = map.get_cell(n)
			if cell != null and cell.type == HexMap.Tile.FLOOR and cell.level == base:
				score += 1
		if score > best_score:
			best_score = score
			best = c
	if best_score < 0:
		return
	_stage_center = best
	for n in Hex.range_cells(best, 1):
		map.get_cell(n).level = base + 5


## --sewer-demo overview|gator|nip|wire|sluice[:n]|outfall[:n] (screenshots), after --demo-after seconds (1.0):
##   overview  the crew on the first sewer room's deck, the camera on the layout's middle; the staged monsters hold still
##   gator     the crew on the landing, the gator relocating at once with the camera on it (it swims and walks)
##   nip       the player steps into the gator's territory in front of it: it watches, gapes (the wind-up) and nips
##   wire      the crew dry by the first electrical panel, Rebar and two held skeletons wading near where its cable lands;
##             the player breaks the panel: the cable drops into the water and the shock runs through it
##   sluice[:n]  the player wading through the layout's n-th sluice doorway (0: the first), Rebar just beyond it
##   outfall[:n] the camera on the layout's n-th outfall pipe (use --zoom 10 for a close look)
func _sewer_demo(stage: String) -> void:
	for ally in allies:
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
	for m: Monster in (_sewer_staged.get("monsters", []) as Array):
		if is_instance_valid(m):
			m.aggro_range = 0.0   # (they hold still for the picture)
	var scout: Monster = _sewer_staged.get("scout")
	if scout != null and is_instance_valid(scout):
		scout.set_physics_process(false)
	match stage:
		"overview":
			_teleport_crew(_sewer_layout["crew_at"])
			_sewer_focus(Vector3(_sewer_layout["view"].x, 0.0, _sewer_layout["view"].y))
		"gator":
			# the crew back on the landing, the gator set to relocate now, the camera riding it: it swims, climbs out and
			# walks to its next bask spot (the look: docs/design/gator-look.md; pick the moment with --shot-after)
			var gators: Array = _sewer_staged.get("gators", [])
			if gators.is_empty():
				return
			_teleport_crew(_sewer_layout["landing"])
			var g: Gator = gators[0]
			for m: Monster in (_sewer_staged.get("monsters", []) as Array):
				if is_instance_valid(m) and GameWorld.flat_distance(m.global_position, g.global_position) < Gator.RELOCATE_CLEAR + 3.0:
					m.queue_free()   # (nobody near it, or it stays put; the picture only)
			g._relocate_at = GameWorld.time + 0.2
			rig.target = g
			rig.snap()
		"nip":
			await get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
			var gators: Array = _sewer_staged.get("gators", [])
			if gators.is_empty() or player == null:
				return
			var g: Gator = gators[0]
			var h := g.head()
			var fwd := Vector3(g.facing.x, 0.0, g.facing.z).normalized()
			var best := Vector3.INF
			var best_s := INF
			for c in Hex.range_cells(Hex.from_world(h), 3):
				if not map.is_walkable_cell(c):
					continue
				var w := Hex.to_world(c)
				var d := GameWorld.flat_distance(w, h)
				if d < 1.6 or d > 2.7:
					continue
				var to := (w - g.global_position).normalized()
				var s := absf(d - 2.2) - to.dot(fwd) * 1.5
				if s < best_s:
					best_s = s
					best = w
			if best == Vector3.INF:
				return
			player.global_position = Vector3(best.x, player.global_position.y, best.z)
			player.snap_to_ground()
			player.face_point(g.global_position)
			var k := 0
			for ally in allies:
				var away := (best - g.global_position).normalized() * (7.0 + 1.5 * k) + Vector3(-fwd.z, 0.0, fwd.x) * (1.5 - 3.0 * k)
				var spot := Hex.from_world(g.global_position + away)
				for c in Hex.range_cells(spot, 3):
					if map.is_walkable_cell(c) and GameWorld.flat_distance(Hex.to_world(c), h) > Gator.WATCH_R + 1.0:
						ally.global_position = Hex.to_world(c)
						ally.snap_to_ground()
						break
				k += 1
			_sewer_focus((best + g.global_position) * 0.5)
		"wire":
			var wires: Array = _sewer_staged.get("wires", [])
			if wires.is_empty() or player == null:
				return
			var w: LiveWire = wires[0]
			var pan := w.panel
			var dc := w.drop_cell
			# the player and Gasket on dry floor beside the panel, Rebar wading near the drop, two skeletons in the water
			var dry: Array[Vector2i] = []
			var wet: Array[Vector2i] = []
			for c in Hex.range_cells(dc, 4):
				if not map.is_walkable_cell(c):
					continue
				if map.get_cell(c).pool_mask == HexMap.ALL_KITES and Hex.distance(c, dc) >= 1 and Hex.distance(c, dc) <= 3:
					wet.append(c)
				elif map.get_cell(c).pool_mask == 0 and GameWorld.flat_distance(Hex.to_world(c), pan.global_position) <= 5.0:
					dry.append(c)
			dry.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return GameWorld.flat_distance(Hex.to_world(a), pan.global_position) > GameWorld.flat_distance(Hex.to_world(b), pan.global_position))
			if dry.is_empty() or wet.is_empty():
				return
			player.global_position = Hex.to_world(dry[0])
			player.snap_to_ground()
			player.face_point(pan.global_position)
			for ally in allies:
				if ally.display_name == "Rebar":
					ally.global_position = Hex.to_world(wet[0])
				else:
					ally.global_position = Hex.to_world(dry[mini(1, dry.size() - 1)])
				ally.snap_to_ground()
			for i in mini(2, wet.size() - 1):
				var sk := MonsterFactory.spawn("grunt", wet[i + 1])
				if sk != null:
					sk.aggro_range = 0.0
			_sewer_focus(w.drop_point.lerp(player.global_position, 0.35))
			await get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
			if is_instance_valid(pan) and not pan.dead:
				pan.apply_damage(5.0, player)   # (the player's arrow, say: the panel breaks, the cable drops)
		_:
			# sluice[:n] / outfall[:n]: the camera on the layout's n-th piece of that decor (0 = the first); at a sluice the
			# player wades through its doorway and Rebar stands just beyond it (does anything hang at body height?)
			var parts := stage.split(":")
			var want := parts[0]
			var nth := int(parts[1]) if parts.size() > 1 else 0
			var found: Array[Dictionary] = []
			for e: Dictionary in (_sewer_layout.get("decor", []) as Array):
				if str(e["kind"]) == want:
					found.append(e)
			if found.is_empty() or player == null:
				return
			var d: Dictionary = found[clampi(nth, 0, found.size() - 1)]
			var pos: Vector2 = d["pos"]
			var at := Vector3(pos.x, 0.0, pos.y)
			var fwd := Vector3(sin(deg_to_rad(float(d["yaw"]))), 0.0, cos(deg_to_rad(float(d["yaw"]))))
			if want == "sluice":
				player.global_position = at - fwd * 0.2
				player.snap_to_ground()
				player.face_point(at + fwd * 3.0)
				var k := 0
				for ally in allies:
					ally.global_position = at + fwd * (1.6 + 1.6 * k) + Vector3(-fwd.z, 0.0, fwd.x) * (0.6 - 1.2 * k)
					ally.snap_to_ground()
					k += 1
			_sewer_focus(at + fwd * (0.5 if want == "sluice" else 1.5))


func _sewer_focus(at: Vector3) -> void:
	var mk := Node3D.new()
	mk.name = "SewerFocus"
	GameWorld.root.add_child(mk)
	mk.global_position = at
	rig.target = mk
	rig.snap()

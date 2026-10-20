extends LabBase
## Hellgate beast lab: a REAL generated floor (DungeonGen.for_run, SiteBuilder plan + spawn, HexMapView, DungeonLook, the
## grime layer) with the crew standing in a hellgate's room and the monster under the level (HellgateBeast) built around
## that room. SiteBuilder.spawn already gives every gate its abyss beast (the game's); the lab prints what that cost and,
## unless --wired, swaps the gate's beast for its own style switcher. Monsters are removed so the room reads.
## Scene: scenes/hellgate_beast_lab.tscn.
##
##   godot --path . --resolution 1920x1080 -- --scene res://scenes/hellgate_beast_lab.tscn [--style abyss]
##         [--seed 7] [--arch guru] [--floor 1] [--gate 0] [--shot <dir/prefix>] [--styles a,b] [--views game,wide]
##         [--motion abyss] [--t 1.7] [--zfight] [--wired] [--diff 0.6] [--exit retract|whip] [--unchecked]
##         [--gif <dir/prefix> --scenario exit|hurt [--secs 4] [--fps 15] [--size 24] [--center x,z]] [--survey 1-40]
##         [--at x,y,z]
##
## --style    abyss | peek | none (interactive start style; abyss is the game's look, peek a lab-only option)
## --wired    keep the beasts SiteBuilder.spawn built (the game's path: watching their gates) instead of the lab's own
## --floor 3  the origin floor: the room of the ORIGIN gate (the bigger version of each style)
## --shot     renders and writes <prefix>_<style>_<view>.png for every style in --styles (default both) and every
##            view in --views (default game, wide), then <prefix>_<style>_motion_a/b.png for each style in --motion, and quits.
##              game    the game camera (ortho yaw 45, pitch -56, size 24 = the default zoom) on the crew
##              wide    size 36 (the farthest the player can zoom out) on the room's centre
##              close   size 14 on the gate
##              spot    size 10 on the style's focus (the eye, where the first tentacle comes out from under the slab)
##              low     a low three-quarter view (yaw 25, pitch -24, size 30) on the room: the cliffs and the tentacles
##                      climbing them from under the level
## --t        the animation time the shots are frozen at (gate and beast together; default 1.7)
## --perf     with --wired: the GPU / CPU render time (ms, 240 frames) at the default zoom on each gate of the floor, with
##            the floor's beasts and then without them
## --zfight   run ZFightCheck on every style (its own pieces, and against the real terrain) and print the findings
## --exit     how the beasts leave when their gate closes: retract (down their own paths; the game's) or whip
## --unchecked  build the limbs without the clearance pass (HellgateBeast.check_clearance off: the first wired version)
## --gif      with --wired, run Godot with --fixed-fps <fps>: capture <secs> of the game camera on the room (960 wide PNGs
##            <prefix>_0000.png ...; tools turn them into a GIF). Scenarios: exit (the gate closes 0.6 s in) or hurt (three
##            hits, sustained fire, then the gate at 12 % HP)
## --survey a-b  no window needed: every gate room of floors 1-3 of seeds a..b, built unchecked and checked, and the worst
##            clearances (at rest and in the envelope) printed, with where the worst is
## --at x,y,z   the "spot" view looks there instead of at the style's focus
## Interactive (no --shot): 1-2 pick a style, 0 none, C closes the gate (wired) or makes the beast leave, H hits the gate,
## X swaps the exit (retract / whip), Q / E zoom, WASD pan.

const GAME_YAW := 45.0
const GAME_PITCH := -56.0
const GAME_SIZE := 24.0
const WIDE_SIZE := 36.0

var seed_value := 7
var archetype := "guru"
var floor_n := 1
var gate_index := 0
var style := "abyss"
var t_shot := 1.7
var wired := false

var run: ContractRun
var plan: SitePlan
var site: SiteBuilder.Site
var view: HexMapView
var gate: Hellgate
var room_tag := ""
var room_cells: Array[Vector2i] = []
var obstacles: Array[Vector4] = []
var exit_style := HellgateBeast.EXIT_STYLE
var beast: HellgateBeast = null
var crew_center := Vector3.ZERO
var room_center := Vector3.ZERO
var _cam_target := Vector3.ZERO
var _cam_size := GAME_SIZE


func _ready() -> void:
	seed_value = int(arg(args, "--seed", "7"))
	archetype = arg(args, "--arch", "guru")
	floor_n = clampi(int(arg(args, "--floor", "1")), 1, ContractRun.FLOOR_COUNT)
	gate_index = int(arg(args, "--gate", "0"))
	style = arg(args, "--style", "abyss")
	t_shot = float(arg(args, "--t", "1.7"))
	wired = args.has("--wired")
	exit_style = arg(args, "--exit", HellgateBeast.EXIT_STYLE)
	if args.has("--unchecked"):
		HellgateBeast.check_clearance = false
	if args.has("--survey"):
		_run_survey(arg(args, "--survey", "1-20"))
		return
	_build_floor()
	make_camera(220.0)
	camera.make_current()
	_place_crew()
	_set_style(style)
	_cam_target = crew_center
	_aim(GAME_SIZE, crew_center)
	_set_exit(exit_style)
	if args.has("--gif"):
		_run_gif(args)
	elif args.has("--zfight"):
		_run_zfight()
	elif args.has("--perf"):
		_run_perf()
	elif shot_path != "":
		_run_shots(args)


func _build_floor() -> void:
	run = ContractRun.make(archetype, seed_value, float(arg(args, "--diff", "0.6")))
	map = DungeonGen.for_run(run, floor_n)
	plan = SiteBuilder.plan(map, run, floor_n, PricedProp.catalog(run.site_type))
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, run.floor_seed(floor_n))
	view = HexMapView.new()
	view.name = "Terrain"
	add_child(view)
	view.build(map)
	DungeonLook.apply(self, map)
	HellgateBeast.reset_build_clock()
	site = SiteBuilder.spawn(map, run, plan)
	var floor_tris := 0
	var beasts := get_tree().get_nodes_in_group(HellgateBeast.GROUP)
	for b: HellgateBeast in beasts:
		floor_tris += int(b.stats.get("tris", 0))
	print("floor beasts: %d for %d gates, %d tris, built in %.1f ms" % [beasts.size(), site.gates.size(), floor_tris, HellgateBeast.build_usec / 1000.0])
	if not wired:
		for b in beasts:
			b.free()
	GrimeLayer.attach(self, map, plan, run.floor_seed(floor_n))
	# no monsters: the room should read; nothing walks
	for m in site.monsters:
		if is_instance_valid(m):
			m.free()
	for m in site.scouts:
		if is_instance_valid(m):
			m.free()
	for e in site.employees:
		e.set_physics_process(false)
	for g in site.gates:
		g.set_physics_process(false)
	var gi := clampi(gate_index, 0, maxi(site.gates.size() - 1, 0))
	if floor_n >= ContractRun.FLOOR_COUNT and site.origin_gate != null:
		gate = site.origin_gate as Hellgate
		room_tag = plan.origin_room
	else:
		gate = site.gates[gi] as Hellgate
		room_tag = str(plan.gates[gi]["room"])
	gate.model.set_active(true)
	room_cells.assign(plan.rooms[room_tag])
	room_center = Hex.to_world(plan.centers[room_tag], float(plan.base_levels[room_tag]))
	obstacles = HellgateBeast.obstacles_of(plan, gate.global_position, gate.origin)
	print("lab: seed %d %s floor %d  gate %s in %s (%s, %d cells)  %d gates" % [seed_value, archetype, floor_n,
			str(Hex.from_world(gate.global_position)), room_tag, plan.theme_of(room_tag), room_cells.size(), site.gates.size()])


## The crew a few cells from the gate, on the camera's side of it, looking at it.
func _place_crew() -> void:
	var gc := Hex.from_world(gate.global_position)
	var cands: Array[Vector2i] = []
	var near := 4 if gate.origin else 3
	for c in room_cells:
		var d := Hex.distance(c, gc)
		if d >= near and d <= near + 1 and map.is_walkable_cell(c):
			cands.append(c)
	var cam := Vector3(0.7071, 0, 0.7071)
	cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return (Hex.to_world(p) - gate.global_position).normalized().dot(cam) > (Hex.to_world(q) - gate.global_position).normalized().dot(cam))
	var models: Array[LowPolyModel] = [WickModel.new(), GasketModel.new(), RebarModel.new()]
	var sum := Vector3.ZERO
	var placed := 0
	var used: Array[Vector2i] = []
	for m in models:
		var cell := gc
		for c in cands:
			var ok := true
			for u in used:
				if Hex.distance(u, c) < 2:
					ok = false
			if ok:
				cell = c
				break
		used.append(cell)
		add_child(m)
		m.idle_enabled = false
		m.apply_idle(0.6)
		var cl := map.get_cell(cell)
		m.global_position = Hex.to_world(cell, float(cl.level))
		var to_gate := gate.global_position - m.global_position
		m.rotation.y = atan2(to_gate.x, to_gate.z)
		sum += m.global_position
		placed += 1
	crew_center = sum / maxf(placed, 1) + Vector3(0, CameraRig.FOCUS_HEIGHT, 0)


func _set_exit(e: String) -> void:
	exit_style = e
	for b: HellgateBeast in get_tree().get_nodes_in_group(HellgateBeast.GROUP):
		b.exit_style = e
	print("exit: ", e)


func _set_style(s: String) -> void:
	if wired:
		return
	if beast != null:
		beast.free()
		beast = null
	style = s
	if s == "none" or not HellgateBeast.STYLES.has(s):
		return
	var t0 := Time.get_ticks_usec()
	var seed_v := hash(Vector3i(Hex.from_world(gate.global_position).x, Hex.from_world(gate.global_position).y, run.floor_seed(floor_n)))
	beast = HellgateBeast.make(s, map, room_cells, gate.global_position, gate.origin, seed_v, obstacles)
	add_child(beast)
	beast.set_gate(gate.model)
	beast.exit_style = exit_style
	print("beast %s%s: %s  built in %.1f ms" % [s, " (origin)" if gate.origin else "", str(beast.stats), (Time.get_ticks_usec() - t0) / 1000.0])


func _aim(size: float, tgt: Vector3, yaw_deg: float = GAME_YAW, pitch_deg: float = GAME_PITCH) -> void:
	aim(yaw_deg, pitch_deg, size, tgt)


func _unhandled_input(event: InputEvent) -> void:
	if shot_path != "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_set_style("abyss")
			KEY_2:
				_set_style("peek")
			KEY_0:
				_set_style("none")
			KEY_C:
				if wired:
					gate.die()
				elif beast != null:
					beast.leave()
			KEY_H:
				gate.apply_damage(gate.max_hp * 0.05, null)
				if not wired and beast != null:
					beast.hurt(0.05)
			KEY_X:
				_set_exit("whip" if exit_style == "retract" else "retract")
			KEY_Q:
				_cam_size = clampf(_cam_size * 1.1, 8.0, 48.0)
			KEY_E:
				_cam_size = clampf(_cam_size / 1.1, 8.0, 48.0)


func _process(delta: float) -> void:
	if shot_path != "":
		return
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		mv += Vector3(-1, 0, -1)
	if Input.is_key_pressed(KEY_S):
		mv += Vector3(1, 0, 1)
	if Input.is_key_pressed(KEY_A):
		mv += Vector3(-1, 0, 1)
	if Input.is_key_pressed(KEY_D):
		mv += Vector3(1, 0, -1)
	_cam_target += mv.normalized() * delta * 10.0 if mv != Vector3.ZERO else Vector3.ZERO
	_aim(_cam_size, _cam_target)


# ------------------------------------------------------------------ shots

func _freeze(t: float) -> void:
	gate.model.freeze_at(t)
	for b: HellgateBeast in get_tree().get_nodes_in_group(HellgateBeast.GROUP):
		b.freeze_at(t)


func _run_shots(a: PackedStringArray) -> void:
	for i in 10:
		await get_tree().process_frame
	var styles: Array = Array(arg(a, "--styles", ",".join(HellgateBeast.STYLES)).split(",", false))
	var views: Array = Array(arg(a, "--views", "game,wide").split(",", false))
	var motion: Array = Array(arg(a, "--motion", "").split(",", false))
	for s: String in styles:
		_set_style(s)
		_freeze(t_shot)
		for v: String in views:
			match v:
				"game":
					_aim(GAME_SIZE, crew_center)
				"wide":
					_aim(WIDE_SIZE, room_center + Vector3(0, 0.8, 0))
				"close":
					_aim(14.0, gate.global_position + Vector3(0, 1.0, 0))
				"low":
					_aim(30.0, room_center + Vector3(0, -0.5, 0), 25.0, -24.0)
				"spot":
					var focus := gate.global_position
					if beast != null and beast.focus != Vector3.ZERO:
						focus = beast.focus
					var at := arg(a, "--at")
					if at != "":
						var xyz := at.split(",")
						focus = Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
					_aim(7.0, focus)
			await snap("%s_%s_%s.png" % [shot_path, s, v])
	for s: String in motion:
		_set_style(s)
		_aim(GAME_SIZE, crew_center)
		_freeze(t_shot)
		await snap("%s_%s_motion_a.png" % [shot_path, s])
		_freeze(t_shot + 1.6)
		await snap("%s_%s_motion_b.png" % [shot_path, s])
	finish()


# ------------------------------------------------------------------ render cost

func _measure(frames: int) -> Vector2:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 30:
		await get_tree().process_frame
	var gpu := 0.0
	var cpu := 0.0
	for i in frames:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	return Vector2(gpu, cpu) / float(frames)


func _run_perf() -> void:
	shot_path = "perf"     # (the interactive camera stands still)
	var with := Vector2.ZERO
	var without := Vector2.ZERO
	var spots: Array[Vector3] = []
	for g in site.gates:
		spots.append(g.global_position + Vector3(0, 0.8, 0))
	for p in spots:
		_aim(GAME_SIZE, p)
		with += await _measure(240)
	for b in get_tree().get_nodes_in_group(HellgateBeast.GROUP):
		b.free()
	for p in spots:
		_aim(GAME_SIZE, p)
		without += await _measure(240)
	with /= float(spots.size())
	without /= float(spots.size())
	print("perf: %d gates  with beasts gpu %.3f ms cpu %.3f ms  |  without gpu %.3f ms cpu %.3f ms" % [spots.size(), with.x, with.y, without.x, without.y])
	finish()


# ------------------------------------------------------------------ z-fighting

func _run_zfight() -> void:
	await get_tree().process_frame
	for s in HellgateBeast.STYLES:
		_set_style(s)
		await get_tree().process_frame
		var own := ZFightCheck.TriSet.new()
		for ch in beast.get_children():
			if ch is Node3D:
				own.add_node(ch, own.add_item("%s/%s" % [s, ch.name]), (ch as Node3D).global_transform)
		var f_own := own.find(false)
		var ts := ZFightCheck.TriSet.new()
		ts.add_node(beast, ts.add_item("beast/" + s), beast.global_transform)
		ts.add_node(view, ts.add_item("terrain", true), view.global_transform)
		ts.trim_terrain()
		var f_ter := ts.find(true)
		print("zfight %s: %d own findings, %d against the terrain" % [s, f_own.size(), f_ter.size()])
		for f in f_own.slice(0, 6):
			print("   own  ", ZFightCheck.describe(f))
		for f in f_ter.slice(0, 6):
			print("   ter  ", ZFightCheck.describe(f))
	finish()


# ------------------------------------------------------------------ GIF frames

func _run_gif(a: PackedStringArray) -> void:
	shot_path = "gif"
	var prefix := arg(a, "--gif")
	var scenario := arg(a, "--scenario", "exit")
	var secs := float(arg(a, "--secs", "4"))
	var fps := float(arg(a, "--fps", "15"))
	var size := float(arg(a, "--size", str(GAME_SIZE)))
	var look_at := room_center + Vector3(0, 0.8, 0)
	var center := arg(a, "--center")
	if center != "":
		var xz := center.split(",")
		look_at = Vector3(float(xz[0]), look_at.y, float(xz[1]))
	_aim(size, look_at)
	for i in 20:
		await get_tree().process_frame
	var frames := int(secs * fps)
	var cell := Hex.from_world(gate.global_position)
	var hits: Array[Vector2] = []      # (time, share of max HP)
	if scenario == "hurt":
		hits.append_array([Vector2(0.5, 0.04), Vector2(1.1, 0.04), Vector2(1.6, 0.06)])
		var at := 2.2
		while at < 3.2:
			hits.append(Vector2(at, 0.015))
			at += 0.1
		hits.append(Vector2(3.4, -0.12))   # (to 12 % HP)
	for f in frames:
		var now := float(f) / fps
		if scenario == "exit" and absf(now - 0.6) < 0.5 / fps:
			gate.die()
		for h in hits:
			if absf(now - h.x) < 0.5 / fps and is_instance_valid(gate) and not gate.dead:
				var amount := gate.max_hp * h.y if h.y > 0.0 else maxf(gate.hp - gate.max_hp * -h.y, 0.0)
				gate.apply_damage(amount, null)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(960, 540, Image.INTERPOLATE_LANCZOS)
		img.save_png("%s_%04d.png" % [prefix, f])
		await get_tree().process_frame
	var b := _beast_at(cell)
	var hp := "closed" if not is_instance_valid(gate) or gate.dead else "%.0f / %.0f" % [gate.hp, gate.max_hp]
	print("gif: %d frames, gate %s, beast %s, flail %.2f" % [frames, hp, b.state() if b != null else "-", b.flail() if b != null else 0.0])
	finish()


func _beast_at(cell: Vector2i) -> HellgateBeast:
	for b: HellgateBeast in get_tree().get_nodes_in_group(HellgateBeast.GROUP):
		if b.gate_cell == cell:
			return b
	return null


# ------------------------------------------------------------------ the clearance survey

## Every gate room of floors 1-3 of the seeds: the beasts built unchecked (the first wired version) and checked; the worst
## clearances printed (rest: the tube as built; env: with every motion the shader can add).
func _run_survey(range_text: String) -> void:
	shot_path = "survey"
	HellgateBeast.debug_fails = args.has("--debug")
	BeastLimbs.debug_self = args.has("--debug")
	var ab := range_text.split("-")
	var worst := {"before_rest": [1.0e9, ""], "before_env": [1.0e9, ""], "after": [1.0e9, ""]}
	var dropped := 0
	var limbs := 0
	var fails := {"level": 0, "self": 0, "limbs": 0}
	var floors := 0
	var worst_ms := 0.0
	var sum_ms := 0.0
	var t0 := Time.get_ticks_msec()
	for sd in range(int(ab[0]), int(ab[ab.size() - 1]) + 1):
		for fl in [1, 2, 3]:
			var r := ContractRun.make("guru", sd, 0.8)
			var m := DungeonGen.for_run(r, fl)
			var pl := SiteBuilder.plan(m, r, fl, PricedProp.catalog(r.site_type))
			var root := Node3D.new()
			add_child(root)
			GameWorld.begin(m, root, r.floor_seed(fl))
			var dummies: Array[Node3D] = []
			for g in pl.gates:
				var c: Vector2i = g["cell"]
				var d := Node3D.new()
				root.add_child(d)
				d.global_position = Hex.to_world(c, float(m.get_cell(c).level))
				dummies.append(d)
			for checked in [false, true]:
				HellgateBeast.check_clearance = checked
				var built: Array[HellgateBeast] = []
				var tb := Time.get_ticks_usec()
				for d in dummies:
					var b := HellgateBeast.for_gate(d, m, pl, r.floor_seed(fl))
					if b != null:
						built.append(b)
				if checked:
					var ms := (Time.get_ticks_usec() - tb) / 1000.0
					floors += 1
					sum_ms += ms
					worst_ms = maxf(worst_ms, ms)
				for b in built:
					var tag := "seed %d floor %d gate %s" % [sd, fl, str(b.gate_cell)]
					if checked:
						var rep: Dictionary = b.clearance_report()
						_keep(worst, "after", rep, tag)
						dropped += int(b.stats["dropped"])
						for key in fails:
							fails[key] += int((b.stats["fails"] as Dictionary)[key])
						limbs += int(b.stats["limbs"])
					else:
						BeastLimbs.rest_only = true
						_keep(worst, "before_rest", b.clearance_report(), tag)
						BeastLimbs.rest_only = false
						_keep(worst, "before_env", b.clearance_report(), tag)
				for b in built:
					b.free()
			GameWorld.end()
			root.free()
	HellgateBeast.check_clearance = true
	for k in worst:
		print("survey %s: worst %.3f at %s" % [k, float(worst[k][0]), str(worst[k][1])])
	print("survey: %d limbs placed, %d dropped, %.1f s, re-roll causes %s" % [limbs, dropped, (Time.get_ticks_msec() - t0) / 1000.0, str(fails)])
	print("survey: phases (ms, both builds) ", str(HellgateBeast.prof.keys()), " ", str(HellgateBeast.prof.values().map(func(v: int) -> int: return v / 1000)))
	print("survey: checked build per floor avg %.0f ms, worst %.0f ms (%d floors)" % [sum_ms / maxf(floors, 1), worst_ms, floors])
	finish()


static func _keep(worst: Dictionary, key: String, rep: Dictionary, tag: String) -> void:
	if float(rep["worst"]) < float(worst[key][0]):
		var at: Vector3 = rep.get("at", Vector3.ZERO)
		worst[key] = [float(rep["worst"]), "%s (level %.3f self %.3f limbs %.3f) at %.2f,%.2f,%.2f" % [tag, float(rep["level"]),
				float(rep["self"]), float(rep["limbs"]), at.x, at.y, at.z]]

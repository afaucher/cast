extends Node
## Perf probe for the grime layer (needs a real renderer, so NOT --headless):
##   Godot --path . res://tools/grime_bench.tscn -- [seed] [floor]
## Builds a real floor (terrain, lighting, an iso camera over the middle of the rooms), then measures, per
## configuration, the viewport's CPU / GPU render time, the draw calls and the layer's own script time:
##   1. no grime layer           2. ambient grime only           3. ambient + 120 live marks
##   4. the same with every live mark inside its fade window (the worst case for the layer's update)
## Prints one summary line per configuration and quits.

const WARMUP := 40
const SAMPLES := 150

var _step := 0
var _frames := 0
var _cpu := 0.0
var _gpu := 0.0
var _calls := 0.0
var _script_us := 0.0
var _map: HexMap
var _plan: SitePlan
var _seed_value := 7
var _layer: GrimeLayer = null
var _cam: Camera3D
var _vp: RID
var _scene: Node3D
var _labels: Array[String] = ["no grime", "ambient only", "ambient + 120 live marks", "ambient + 120 marks fading", "layer hidden (control)", "layer shown again (fading)"]
var _results: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var board_seed := int(args[0]) if args.size() > 0 else 7
	var floor_n := int(args[1]) if args.size() > 1 else 1
	var run := ContractBoard.run_for_seed(board_seed)
	_seed_value = run.floor_seed(floor_n)
	_map = DungeonGen.generate(_seed_value)
	_plan = SiteBuilder.plan(_map, run, floor_n, PricedProp.catalog(run.site_type))
	_scene = Node3D.new()
	add_child(_scene)
	var view := HexMapView.new()
	_scene.add_child(view)
	view.build(_map)
	DungeonLook.apply(_scene, _map)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 24.0
	_cam.far = 220.0
	_scene.add_child(_cam)
	var focus := Hex.to_world(_plan.gates[0]["cell"] if not _plan.gates.is_empty() else _plan.start, 0.0)
	_cam.position = focus + Vector3(0, 60.0 * sin(deg_to_rad(56.0)), 60.0 * cos(deg_to_rad(56.0))).rotated(Vector3.UP, deg_to_rad(45.0))
	_cam.look_at(focus, Vector3.UP)
	_cam.make_current()
	print("grime bench: seed %d floor %d, %d cells, %d gates" % [_seed_value, floor_n, _map.cells.size(), _plan.gates.size()])
	_begin_step()


func _begin_step() -> void:
	_frames = 0
	_cpu = 0.0
	_gpu = 0.0
	_calls = 0.0
	_script_us = 0.0
	if _step == 1:
		var t0 := Time.get_ticks_usec()
		_layer = GrimeLayer.attach(_scene, _map, _plan, _seed_value)
		_layer.set_physics_process(false)   # the bench drives the layer's clock itself
		print("  layer build (atlas cached or painted + plan + multimeshes): %.1f ms, %d ambient marks" % [(Time.get_ticks_usec() - t0) / 1000.0, _layer.ambient.size()])
	elif _step == 2:
		var floor_cells := _map.walkable_cells()
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var kinds: Array[String] = [Grime.SCORCH, Grime.CORN, Grime.TEETH, Grime.CRACKS, Grime.STAIN, Grime.SCUFF]
		var laid := 0
		var guard := 0
		while laid < Grime.MAX_LIVE and guard < 2000:
			guard += 1
			var c: Vector2i = floor_cells[rng.randi() % floor_cells.size()]
			if _layer.add_mark(kinds[laid % kinds.size()], Hex.to_world(c, float(_map.get_cell(c).level)), 1.6):
				laid += 1
		print("  %d live marks, %d free slots of %d" % [_layer.live_count(), _layer.free_slot_count(), GrimeLayer.LIVE_SLOTS])
	elif _step == 4:
		_layer.visible = false
	elif _step == 5:
		_layer.visible = true
	elif _step == 3:
		_layer.advance(Grime.LIFE - Grime.FADE + 2.0)   # every live mark now inside its fade window


func _process(delta: float) -> void:
	if not _vp.is_valid():
		_vp = get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_vp, true)
	_frames += 1
	if _step >= 1 and _layer != null:
		var t0 := Time.get_ticks_usec()
		if _step >= 3:
			_layer._update_fade()   # the fade update on EVERY frame (the real cadence is 10 Hz)
		else:
			_layer.advance(delta)   # the layer's per-frame script work
		_script_us += Time.get_ticks_usec() - t0
	if _frames > WARMUP:
		_cpu += RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		_calls += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	if _frames >= WARMUP + SAMPLES:
		var n := float(SAMPLES)
		var line := "%-30s render CPU %.3f ms  GPU %.3f ms  draw calls %.0f  layer script %.1f us/frame" % [_labels[_step], _cpu / n, _gpu / n, _calls / n, _script_us / float(WARMUP + SAMPLES)]
		print(line)
		_results.append(line)
		_step += 1
		if _step >= _labels.size():
			get_tree().quit()
			return
		_begin_step()


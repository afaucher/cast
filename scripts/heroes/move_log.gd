class_name MoveLog
extends Node
## Passive movement numbers per profile (docs/design/movement-research.md §5.2 and "As built"; the user's data rule: no
## questions mid-play). One row to user://move_lab.csv for every stretch played on one profile (written when the gym's
## experiments switch the profile or the smoothing, and when the scene ends) and, in the lab (--move-lab), one per lap.
## Test runs don't write.
##
## Columns: time (wall clock), session (one id per run of the game), scene (lab | floor | arena), mode (today | grounded |
## grounded_anim), label (what the tag showed; the profile's name since the blind shuffle went, 2026-10-23), profile (the
## one played), interp (on | off), event (period | lap), seconds, distance (units walked), laps, lap_s (this lap, or
## the best lap of the period), hits (taken), damage (taken), edge_stops (stopped walking at a pit's or lava's edge),
## starts, stops, reversals, refresh_hz (the monitor's), fps (the average frame rate over the stretch).

const PATH := "user://move_lab.csv"
const HEADER := "time,session,scene,mode,label,profile,interp,event,seconds,distance,laps,lap_s,hits,damage,edge_stops,starts,stops,reversals,refresh_hz,fps"
const START_SPEED := 1.5
const STOP_SPEED := 0.3
const EDGE_LOOK := 0.7            ## an edge stop: void within this far ahead of where the hero was walking

static var enabled := not OS.get_cmdline_user_args().has("--run-test")
static var path := PATH
static var session_id := "%d" % int(Time.get_unix_time_from_system())

var player: Hero
## The lab's lap gates (MoveLab.gates): {start: Vector3, finish: Vector3, radius: float}; {} = no laps.
var lab: Dictionary = {}
var rows: Array[String] = []      ## every row this log made (tests read them; written to the file when enabled)
var _s := {}                      ## the stretch so far
var _profile := ""
var _label := ""
var _interp := false
var _prev := Vector3.INF
var _vs := Vector3.ZERO
var _vlag := Vector3.ZERO
var _moving := false
var _lap_from := -1.0             ## GameWorld.time the lap started, -1 when not on one
var _left_start := false
var _edge_cool := 0.0
var _frames := 0
var _wall := 0.0


func _ready() -> void:
	_begin()
	if player != null:
		player.damaged.connect(_on_damaged)


func _exit_tree() -> void:
	_row("period", -1.0)


## The profile or the interpolation changed (the gym's experiments): close the stretch and start the next.
func switched() -> void:
	_row("period", -1.0)
	_begin()


func _begin() -> void:
	_s = {"seconds": 0.0, "distance": 0.0, "laps": 0, "best": -1.0, "hits": 0, "damage": 0.0, "edge": 0, "starts": 0,
		"stops": 0, "reversals": 0}
	_profile = MoveFeel.active()
	_label = MoveFeel.label()
	_interp = MoveFeel.interp
	_frames = 0
	_wall = 0.0
	_lap_from = -1.0
	_left_start = false


func _on_damaged(amount: float, _source: Node) -> void:
	_s["hits"] = int(_s["hits"]) + 1
	_s["damage"] = float(_s["damage"]) + amount


func _process(delta: float) -> void:
	_frames += 1
	_wall += delta


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		return
	if MoveFeel.active() != _profile:
		switched()   # (a crew's profile arrived, or a test switched it)
	_s["seconds"] = float(_s["seconds"]) + delta
	var p := player.global_position
	if _prev == Vector3.INF:
		_prev = p
	var step := p - _prev
	step.y = 0.0
	_prev = p
	if step.length() > 2.0:
		return   # (a teleport)
	_s["distance"] = float(_s["distance"]) + step.length()
	var raw := step / maxf(delta, 0.0001)
	_vs = _vs.lerp(raw, clampf(delta * 20.0, 0.0, 1.0))
	_vlag = _vlag.lerp(_vs, clampf(delta * 8.0, 0.0, 1.0))
	var sp := _vs.length()
	if not _moving and sp > START_SPEED:
		_moving = true
		_s["starts"] = int(_s["starts"]) + 1
	elif _moving and sp < STOP_SPEED:
		_moving = false
		_s["stops"] = int(_s["stops"]) + 1
		_edge_check(p)
	elif _moving and sp > 2.5 and _vlag.length() > 2.5 and _vs.dot(_vlag) < 0.0:
		if _edge_cool <= 0.0:
			_s["reversals"] = int(_s["reversals"]) + 1
			_edge_cool = 0.3
	_edge_cool = maxf(0.0, _edge_cool - delta)
	_laps(p)


## Stopped: was it at a pit's or lava's edge, walking toward it?
func _edge_check(p: Vector3) -> void:
	var map: HexMap = GameWorld.map
	if map == null or _vlag.length() < 1.0:
		return
	var ahead := p + _vlag.normalized() * (player.radius + EDGE_LOOK)
	if is_nan(map.ground_height(ahead)):
		_s["edge"] = int(_s["edge"]) + 1


func _laps(p: Vector3) -> void:
	if lab.is_empty():
		return
	var r := float(lab.get("radius", 1.5))
	var at_start := GameWorld.flat_distance(p, lab["start"]) < r
	if at_start:
		_left_start = false
		_lap_from = GameWorld.time
		return
	if _lap_from >= 0.0 and not _left_start:
		_left_start = true
	if _left_start and GameWorld.flat_distance(p, lab["finish"]) < r:
		var lap := GameWorld.time - _lap_from
		_s["laps"] = int(_s["laps"]) + 1
		if float(_s["best"]) < 0.0 or lap < float(_s["best"]):
			_s["best"] = lap
		_row("lap", lap)
		_lap_from = -1.0
		_left_start = false


func _row(event: String, lap: float) -> void:
	if _s.is_empty() or (event == "period" and float(_s["seconds"]) < 0.5):
		return
	var fps := float(_frames) / _wall if _wall > 0.0 else 0.0
	var best := float(_s["best"])
	var cells: Array = [
		Time.get_datetime_string_from_system(), session_id, "lab" if not lab.is_empty() else "floor", MoveFeel.mode,
		_label, _profile, "on" if _interp else "off", event, "%.1f" % float(_s["seconds"]), "%.1f" % float(_s["distance"]),
		int(_s["laps"]), "%.2f" % lap if lap >= 0.0 else ("%.2f" % best if best >= 0.0 else ""), int(_s["hits"]),
		"%.0f" % float(_s["damage"]), int(_s["edge"]), int(_s["starts"]), int(_s["stops"]), int(_s["reversals"]),
		"%.0f" % DisplayServer.screen_get_refresh_rate() if DisplayServer.get_name() != "headless" else "", "%.0f" % fps,
	]
	var line := ",".join(cells.map(func(c: Variant) -> String: return str(c)))
	rows.append(line)
	if not enabled:
		return
	var fresh := not FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if not fresh else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	if fresh:
		file.store_line(HEADER)
	file.store_line(line)
	file.close()

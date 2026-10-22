class_name HeroGait
extends RefCounted
## What a hero's feet look and sound like under a MoveFeel profile with `gait` on (package A, "grounded":
## docs/design/movement-research.md "As built"). COSMETIC, on every screen, for every hero, from the position that screen
## shows (a puppet's streamed one too): nothing here is gameplay and nothing travels.
##
##   - the stride matched to the ground and the legs turned toward the travel: Gait (shared with the animation lab), paused
##     while the hero is being shoved;
##   - a dry footstep per foot plant on the floor's material (FloorMaterials -> step_hard / step_soft / step_wood /
##     step_metal; in pool water Wading's splash plays instead), and every STEP_EVERY units for a body with no legs to count;
##   - small dust puffs on a start, a hard stop from speed and a sharp turn or reversal (DUST_COOLDOWN apart);
##   - a landing from MoveFeel.LAND_BIG_LEVELS or more on foot: dust, a ring and a thud (a shove's landing has its own, Fx).
## The lean, squash and strike-first of animation-research.md are HeroFeel's (the grounded_anim profile, `body`), which
## also holds this stride still while the hero is shoved or airborne and through a hit-stop.

const STEP_EVERY := 1.1           ## a legless (prototype) body: a step every this many units walked
const DUST_COOLDOWN := 0.35
const DUST := [Color(0.8, 0.72, 0.58), Color(0.6, 0.52, 0.42)]
const START_SPEED := 1.5          ## the shown speed above which the hero is walking ...
const STOP_SPEED := 0.3           ## ... and below which it has stopped
const HARD_STOP := 3.5            ## a stop from at least this speed (within the last HARD_WINDOW s) puffs
const HARD_WINDOW := 0.25
const TURN_LAG := 1.0             ## a turn of TURN_DEG or more puffs while the old velocity (the lagged one) is still this fast
const TURN_DEG := 75.0

var hero: Hero
var gait: Gait = null
var steps := 0                    ## footsteps played (tests)
var puffs := 0                    ## dust puffs (tests)
var thuds := 0                    ## big landings (tests)
var _prev := Vector3.INF
var _plants := 0
var _walked := 0.0
var _vs := Vector3.ZERO           ## shown velocity, quick
var _vlag := Vector3.ZERO         ## ... and slow (the "before" of a turn)
var _moving := false
var _peak := 0.0                  ## the fastest shown speed in the last HARD_WINDOW s
var _peak_t := 0.0
var _cool := 0.0
var _grounded := true
var _air_top := 0.0
var _air_shoved := false


func _init(h: Hero = null) -> void:
	hero = h


func net_fields() -> Dictionary:
	return {
		"hero": Net.LOCAL, "gait": Net.LOCAL, "steps": Net.LOCAL, "puffs": Net.LOCAL, "thuds": Net.LOCAL,
		"_prev": Net.LOCAL, "_plants": Net.LOCAL, "_walked": Net.LOCAL, "_vs": Net.LOCAL, "_vlag": Net.LOCAL,
		"_moving": Net.LOCAL, "_peak": Net.LOCAL, "_peak_t": Net.LOCAL, "_cool": Net.LOCAL, "_grounded": Net.LOCAL,
		"_air_top": Net.LOCAL, "_air_shoved": Net.LOCAL,
	}


## One rendered frame (Hero._process, after the body's yaw).
func tick(delta: float) -> void:
	if (not MoveFeel.on("gait") and not MoveFeel.on("footsteps")) or hero.dead or not hero.is_inside_tree() or delta <= 0.0:
		stop()
		return
	var model := hero.visual_override
	if not MoveFeel.on("gait"):
		if gait != null:
			gait.release(not hero.dead)
			gait = null
	else:
		if gait != null and gait.model != model:
			stop()
		if gait == null and model != null and Gait.supports(model, hero.kit_id):
			gait = Gait.new(model as LowPolyModel, hero.kit_id)
			_plants = gait.plants
	var pos := hero.global_position
	if _prev == Vector3.INF:
		_prev = pos
	var raw := (pos - _prev) / delta
	raw.y = 0.0
	_prev = pos
	if raw.length() > 20.0 or hero.is_shoved():
		raw = Vector3.ZERO   # a teleport; or a shove: the stride pauses (animation-research.md §7)
	if MoveFeel.on("body"):
		# grounded_anim (HeroFeel): a hit-stop holds the whole pose; a shove or a hop / fall holds the stride where it is
		if hero._feel.frozen():
			return
		if gait != null and (hero.is_shoved() or not _grounded):
			gait.hold()
			gait.pose(hero._visual_yaw, delta)
			_landing(pos)
			return
	if gait != null:
		gait.advance(raw, delta)
		gait.pose(hero._visual_yaw, delta)
	_footsteps(raw, delta)
	_dust(raw, delta)
	_landing(pos)


## The model back on its own clock (the profile switched, the model changed, the hero went down).
func stop() -> void:
	if gait != null:
		gait.release(not hero.dead)
		gait = null
	_prev = Vector3.INF
	_moving = false


func _footsteps(raw: Vector3, delta: float) -> void:
	var plant := false
	if gait != null:
		plant = gait.plants != _plants
		_plants = gait.plants
	elif raw.length() > START_SPEED:
		_walked += raw.length() * delta
		if _walked >= STEP_EVERY:
			_walked = 0.0
			plant = true
	if not plant or not MoveFeel.on("footsteps") or not _grounded or hero.is_shoved():
		return
	var map: HexMap = GameWorld.map
	if map == null or map.water_at(hero.global_position):
		return   # (wading: Wading's splash)
	steps += 1
	Sfx.play_at(step_cue(map, hero.global_position), hero.global_position)


## The footstep cue for the floor under `p`.
static func step_cue(map: HexMap, p: Vector3) -> String:
	var cell := map.get_cell(Hex.from_world(p))
	if cell == null:
		return "step_hard"
	match FloorMaterials.floor_of(cell.mat_id):
		FloorMaterials.F_CARPET, FloorMaterials.F_RUBBER:
			return "step_soft"
		FloorMaterials.F_WOOD:
			return "step_wood"
		FloorMaterials.F_DIAMOND, FloorMaterials.F_DIAMOND_DARK:
			return "step_metal"
	return "step_hard"


func _dust(raw: Vector3, delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	_vs = _vs.lerp(raw, clampf(delta * 20.0, 0.0, 1.0))
	_vlag = _vlag.lerp(_vs, clampf(delta * 8.0, 0.0, 1.0))
	var sp := _vs.length()
	_peak_t += delta
	if sp >= _peak or _peak_t > HARD_WINDOW:
		_peak = sp
		_peak_t = 0.0
	if not MoveFeel.on("dust") or not _grounded or hero.is_shoved():
		_moving = sp > START_SPEED
		return
	var pos := hero.global_position
	if not _moving and sp > START_SPEED:
		_moving = true
		_puff(pos - _vs.normalized() * 0.25, -_vs.normalized(), 4, 1.2)   # a start: kicked back
	elif _moving and sp < STOP_SPEED:
		_moving = false
		if _peak >= HARD_STOP:
			_puff(pos + _vlag.normalized() * 0.3, _vlag.normalized(), 6, 1.6)   # a hard stop: skidded forward
	elif _moving and sp > START_SPEED and _vlag.length() > TURN_LAG and _vs.angle_to(_vlag) > deg_to_rad(TURN_DEG):
		_puff(pos, _vlag.normalized(), 6, 1.6)   # a sharp turn or a reversal: the old way, scuffed


func _puff(at: Vector3, dir: Vector3, n: int, speed: float) -> void:
	if _cool > 0.0:
		return
	_cool = DUST_COOLDOWN
	puffs += 1
	var d := (dir + Vector3.UP * 0.8).normalized() if dir.length() > 0.01 else Vector3.UP
	var cols: Array[Color] = [DUST[0], DUST[1]]
	Fx.burst(at + Vector3.UP * 0.06, cols, n, speed, 0.07, 0.35, 2.0, d, 55.0, false)


func _landing(pos: Vector3) -> void:
	var map: HexMap = GameWorld.map
	if map == null:
		return
	var g := map.ground_height(pos)
	var on := not is_nan(g) and pos.y - g < 0.05
	if not on:
		if _grounded:
			_air_top = pos.y
			_air_shoved = false
		_air_top = maxf(_air_top, pos.y)
		_air_shoved = _air_shoved or hero.is_shoved()
	elif not _grounded and not _air_shoved:
		var levels := (_air_top - pos.y) / Hex.LEVEL_HEIGHT
		if levels >= MoveFeel.LAND_BIG_LEVELS - 0.1:
			if MoveFeel.on("dust"):
				thuds += 1
				var cols: Array[Color] = [DUST[0], DUST[1]]
				Fx.burst(pos + Vector3.UP * 0.08, cols, 10, 2.6, 0.09, 0.45, 3.0, Vector3.UP, 85.0, false)
				Fx.ring(pos, 0.75, Color(0.9, 0.8, 0.6, 0.5), 0.3, 0.0, false, 0.3)
			Sfx.play_at("fall_heavy" if levels >= 2.8 else "land_thud", pos)
		elif levels >= 0.85:
			Sfx.play_at("land_thud", pos)
	_grounded = on

class_name MonsterSenses
extends RefCounted
## What monsters notice and how restless a floor gets (docs/design/monster-awareness.md, step 1). Static helpers only;
## the state lives on each Monster.
##
##   noise(pos, radius, kind)   a sound: every monster that hears it (within `radius`, x0.6 through walls) turns
##                              SUSPICIOUS toward `pos`. Spells, arrows, melee and deaths call it (NOISE_* below).
##   face_spawn(m, plan, seed)  spawn facing: toward the room's main door (else its centre) +/- 35 degrees, rolled on a
##                              generator seeded from the site's seed and the cell, never at a wall close ahead.
##   wall_ahead(m, dir)         is there a wall (or a rise) within 2 hexes straight ahead at chest height?
##   restlessness()             R: 0 for the first 2 minutes of the floor, 1 at 6 minutes (host clock).
##   patrol_route / visitor_point   a skeleton's patrol points in its room, and the next room through the corridor.
## Step 2 (monster-awareness.md, "Step 2 as built"):
##   alarm(f, s)                the goblin scout's fireworks at F: resting monsters near F (or whose room has a door near
##                              F) walk to the sighting point S on ALERT; a dormant hellgate near F wakes.
##   fire_at(pos, radius)       a fireball's blast: a scout's rack in it goes up (the goblin's catch_fire).
##   practice_hits / note_practice_hit   how many target-practice arrows a priced prop has taken this floor.
##
## Online: monster AI runs on the host only. A cast runs on every machine, so noise() runs everywhere, but it only
## reaches monsters this machine simulates (a client's are copies: Net.simulates is false there).

## How far each sound carries (world units; 1 hex step = 1.73).
const NOISE_CORN := 14.0
const NOISE_FIREBALL := 10.0
const NOISE_TEETH := 8.0
const NOISE_TENTACLES := 8.0
const NOISE_DEATH := 6.0
const NOISE_MELEE := 4.0
const NOISE_ARROW := 3.0
const THROUGH_WALL := 0.6         ## with no line of sight a sound carries this share of its radius
const DOOR_MUFFLE := 0.5          ## through a shut office door a sound carries half its radius (then THROUGH_WALL as usual)
const EAR_HEIGHT := 1.2           ## sounds are traced from this height above where they happen

const SPAWN_SPREAD_DEG := 35.0
const DOOR_MIN_DIST := 2.5        ## standing right at the door: face the room centre instead
const WALL_AHEAD := 3.5           ## 2 hexes

## Restlessness ramp: 0 until 2 min, full at 6 min (user, 2026-10-18).
const RESTLESS_START := 120.0
const RESTLESS_FULL := 360.0

const PATROL_MIN_HEX := 3         ## patrol points stand at least this many hexes apart
const PATROL_PATH_NODES := 150
const VISITOR_DEPTH := 40         ## how far (hex steps) a visitor looks for the next room

## The goblin scout's fireworks alarm (monster-awareness.md Option 4, goblin-scout.md §3.1).
const ALARM_RADIUS := 18.0        ## resting monsters this close to F hear the fireworks (flat, through walls) ...
const ALARM_DOOR := 24.0          ## ... and so does every resting monster whose room has a door this close to F
const ALARM_CAP := 12             ## the nearest this many, so one alarm never wakes the whole floor
const ALARM_EDGE := 60.0          ## then they stay on edge this long (after the ALERT walk)
const ALARM_GATE_RADIUS := 18.0   ## a dormant hellgate this close to F wakes (user, 2026-10-18)
const ALARM_RESTLESS := 0.25      ## each volley adds this much floor-wide restlessness (Option 3)
const NOISE_BRUTE_FIGHT := 14.0   ## a restless brute fight (Option 3: the crowd gathers to watch) ...
const WATCH_DISTANCE := 4.5       ## ... this far from the fighters (the slam ring is 2)
const ARRIVE_SLACK := 0.3

## >= 0 replaces restlessness(): tests (so they needn't wait 2 minutes of floor time), and the dev flag
## `--restless <0..1>` for a playtest of a restless floor straight away.
static var restless_override := _cmdline_restless()


static func _cmdline_restless() -> float:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--restless")
	return clampf(float(args[i + 1]), 0.0, 1.0) if i >= 0 and i + 1 < args.size() else -1.0


## A sound at `pos` that carries `radius`. `kind` names it for the combat log. `quiet` lists monsters that don't react
## (the ones making it: two brutes don't break up their own fight). `stand_off` > 0: the hearers come no closer than this
## (a crowd gathering to watch a brute fight): each one's point is on the line to it, that far from the sound.
static func noise(pos: Vector3, radius: float, kind: String = "", quiet: Array = [], stand_off: float = 0.0) -> int:
	if radius <= 0.0 or GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return 0
	var map := GameWorld.map
	var ear := pos + Vector3.UP * EAR_HEIGHT
	var heard := 0
	# Duck-typed on purpose (group "monsters" only holds Monsters; see Monster._alert_pack).
	for n in GameWorld.root.get_tree().get_nodes_in_group("monsters"):
		if n.dead or n.aggro_range <= 0.0 or not Net.simulates(n) or quiet.has(n):
			continue
		var d := GameWorld.flat_distance(n.global_position, pos)
		if d > radius:
			continue
		# A shut door between them (OfficeDoor: a HexMap sight blocker) halves the reach; the walls are judged without it.
		var reach := radius * DOOR_MUFFLE if map != null and map.crosses_blocker(pos, n.global_position) else radius
		if d > reach:
			continue
		if d > reach * THROUGH_WALL and map != null and not map.line_of_sight(ear, Combat.chest(n), 0.25, false):
			continue
		var at := pos
		if stand_off > 0.0:
			var away: Vector3 = n.global_position - pos
			away.y = 0.0
			at = pos + away.normalized() * stand_off if d > stand_off + ARRIVE_SLACK else pos.lerp(n.global_position, 0.85)
		if n.hear(at):
			heard += 1
	CombatLog.noise(kind, heard)
	return heard


## True when a wall (or ground higher than the eyes) stands within `dist` straight ahead of `a` along `dir`.
static func wall_ahead(a: Actor, dir: Vector3, dist: float = WALL_AHEAD) -> bool:
	var map := GameWorld.map
	if map == null:
		return false
	dir.y = 0.0
	if dir.length() < 0.001:
		return false
	var eye := Combat.chest(a)
	return not map.line_of_sight(eye, eye + dir.normalized() * dist)


## Floor time: seconds since this floor's world began (the first call on a new GameWorld.root starts the clock).
static func floor_seconds() -> float:
	if GameWorld.root == null:
		return 0.0
	var key := GameWorld.root.get_instance_id()
	if int(GameWorld.get_meta("awareness_floor", 0)) != key:
		GameWorld.set_meta("awareness_floor", key)
		GameWorld.set_meta("awareness_t0", GameWorld.time)
	return GameWorld.time - float(GameWorld.get_meta("awareness_t0", GameWorld.time))


## R(t) = clamp((t - RESTLESS_START) / (RESTLESS_FULL - RESTLESS_START), 0, 1) on the floor clock, plus 0.25 per fireworks volley on this floor.
static func restlessness() -> float:
	if restless_override >= 0.0:
		return clampf(restless_override, 0.0, 1.0)
	return clampf(ramp(floor_seconds()) + float(_floor_meta("restless_bonus", 0.0)), 0.0, 1.0)


## A value kept per floor (GameWorld metadata keyed by the floor's world root): a new floor starts from `default`.
static func _floor_meta(key: String, default: Variant) -> Variant:
	if GameWorld.root == null:
		return default
	var d: Dictionary = GameWorld.get_meta("awareness_floor_meta", {})
	if int(d.get("_root", 0)) != GameWorld.root.get_instance_id():
		d = {"_root": GameWorld.root.get_instance_id()}
		GameWorld.set_meta("awareness_floor_meta", d)
	return d.get(key, default)


static func _set_floor_meta(key: String, value: Variant) -> void:
	if GameWorld.root == null:
		return
	_floor_meta(key, null)   # (starts the floor's dictionary)
	var d: Dictionary = GameWorld.get_meta("awareness_floor_meta", {})
	d[key] = value


static func ramp(seconds: float) -> float:
	return clampf((seconds - RESTLESS_START) / (RESTLESS_FULL - RESTLESS_START), 0.0, 1.0)


## The room ("room:<n>") a cell belongs to, from the map's tags ("" in a corridor or an untagged test map).
static func room_of(cell: Vector2i) -> String:
	var map := GameWorld.map
	if map == null:
		return ""
	var c := map.get_cell(cell)
	return c.tag if c != null and c.tag.begins_with("room:") else ""


# --- Spawn facing ----------------------------------------------------------------------------------------------

## Turn a freshly placed pack monster toward its room's main door (SitePlan.entrances), else the room centre, +/- 35
## degrees. The roll uses a generator seeded from the site's seed and the cell, so a seed always gives the same facings
## and the plan's other rolls don't shift. A heading with a wall close ahead is swapped for the nearest clear one.
static func face_spawn(m: Monster, plan: SitePlan, site_seed: int) -> void:
	if m == null or not is_instance_valid(m):
		return
	var pos := m.global_position
	var cell := Hex.from_world(pos)
	var tag := room_of(cell)
	if tag == "" and plan != null:
		tag = plan.room_of_cell(cell)
	var goal := Vector3.INF
	if plan != null and plan.entrances.has(tag):
		var e: Vector2 = plan.entrances[tag]
		if Vector2(pos.x, pos.z).distance_to(e) > DOOR_MIN_DIST:
			goal = Vector3(e.x, pos.y, e.y)
	if goal == Vector3.INF:
		goal = _room_centre(plan, tag)
	var base := m.facing
	if goal != Vector3.INF:
		var to := goal - pos
		to.y = 0.0
		if to.length() > 0.5:
			base = to.normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([site_seed, cell.x, cell.y, "facing"])
	var dir := base.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-SPAWN_SPREAD_DEG, SPAWN_SPREAD_DEG)))
	m.set_spawn_facing(clear_heading(m, dir, base))


## `dir` if nothing blocks it close ahead, else the clear heading nearest to `base` (then to `dir`), else `dir`.
static func clear_heading(a: Actor, dir: Vector3, base: Vector3) -> Vector3:
	if not wall_ahead(a, dir):
		return dir
	for k in [0.0, 35.0, -35.0, 70.0, -70.0, 105.0, -105.0, 140.0, -140.0, 180.0]:
		var d := base.rotated(Vector3.UP, deg_to_rad(k))
		if not wall_ahead(a, d):
			return d
	return dir


static func _room_centre(plan: SitePlan, tag: String) -> Vector3:
	if tag == "":
		return Vector3.INF
	if plan != null and plan.centers.has(tag):
		return Hex.to_world(plan.centers[tag])
	var map := GameWorld.map
	if map == null:
		return Vector3.INF
	var cells := map.cells_with_tag(tag)
	if cells.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	for c in cells:
		sum += Hex.to_world(c)
	return sum / float(cells.size())


# --- Patrols ------------------------------------------------------------------------------------------------------

## Walkable full-floor cells of a room (no pools: wading is slow and looks odd for a patrol).
static func room_cells(tag: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var map := GameWorld.map
	if map == null or tag == "":
		return out
	for c in map.cells_with_tag(tag):
		var cell := map.get_cell(c)
		if cell != null and cell.type == HexMap.Tile.FLOOR and map.is_walkable_cell(c) and not map.is_pool_cell(c):
			out.append(c)
	return out


## 2-3 patrol points in the monster's room, home first, each at least PATROL_MIN_HEX hexes from the others and
## reachable by a short path. Rolled on GameWorld.rng (host AI). Empty when the room offers nothing.
static func patrol_route(m: Monster, tag: String) -> Array[Vector3]:
	var route: Array[Vector3] = [m.home]
	var map := GameWorld.map
	var cells := room_cells(tag)
	if map == null or cells.size() < 4:
		return route
	var home_cell := Hex.from_world(m.home)
	var want := GameWorld.rng.randi_range(1, 2)
	var picked: Array[Vector2i] = [home_cell]
	for _try in 24:
		if picked.size() > want:
			break
		var c := cells[GameWorld.rng.randi_range(0, cells.size() - 1)]
		var ok := true
		for p in picked:
			if Hex.distance(c, p) < PATROL_MIN_HEX:
				ok = false
				break
		if not ok:
			continue
		var path := map.find_path(picked.back(), c, m.can_climb, PATROL_PATH_NODES)
		if path.is_empty():
			continue
		picked.append(c)
		route.append(Hex.to_world(c, float(map.get_cell(c).level)))
	return route


## A point a few cells into the nearest OTHER room, reached through the corridor (breadth-first over the cells the
## monster can walk). Vector3.INF when there is none within VISITOR_DEPTH steps.
static func visitor_point(m: Monster, tag: String) -> Vector3:
	var map := GameWorld.map
	if map == null or tag == "":
		return Vector3.INF
	var start := Hex.from_world(m.home)
	var seen := {start: 0}
	var queue: Array[Vector2i] = [start]
	var found: Array[Vector2i] = []
	var other := ""
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		var depth: int = seen[c]
		if depth >= VISITOR_DEPTH:
			continue
		for nb in Hex.neighbors(c):
			if seen.has(nb) or not map.is_walkable_cell(nb):
				continue
			var mv := map.cell_transition(c, nb)
			if not (mv == HexMap.Move.OK or (mv == HexMap.Move.CLIMB and m.can_climb)):
				continue
			seen[nb] = depth + 1
			var t := room_of(nb)
			if t != "" and t != tag and (other == "" or t == other) and not map.is_pool_cell(nb):
				other = t
				found.append(nb)
				if found.size() >= 6:
					var pick: Vector2i = found.back()   # a few cells in, not in the doorway
					return Hex.to_world(pick, float(map.get_cell(pick).level))
			if other == "" or room_of(nb) == other or room_of(nb) == "":
				queue.append(nb)
	if found.is_empty():
		return Vector3.INF
	var last: Vector2i = found.back()
	return Hex.to_world(last, float(map.get_cell(last).level))


# --- Step 2: the fireworks alarm ------------------------------------------------------------------------------------

## The goblin scout's volley went up at `f`; the crew was seen at `s`. Every IDLE, SUSPICIOUS or RETURN monster within
## ALARM_RADIUS of F (flat, walls or not), or whose home room has a door within ALARM_DOOR of F, walks to S on ALERT:
## the ALARM_CAP nearest of them. They stay on edge ALARM_EDGE s after the walk. Another scout within ALARM_RADIUS runs
## to S instead of setting off his own. A dormant hellgate within ALARM_GATE_RADIUS wakes. Floor restlessness +0.25.
## Host only (Net.simulates). Returns {woken, scouts, gates}.
static func alarm(f: Vector3, s: Vector3, raiser: Node = null) -> Dictionary:
	var out := {"woken": 0, "scouts": 0, "gates": 0}
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return out
	var doors := room_doors()
	var cands: Array = []
	for n in GameWorld.root.get_tree().get_nodes_in_group("monsters"):   # (duck-typed, see Monster._alert_pack)
		if n == raiser or n.dead or not Net.simulates(n) or n.is_frozen():
			continue
		if n.kind == "goblin":
			if GameWorld.flat_distance(n.global_position, f) <= ALARM_RADIUS and n.assist(s):
				out["scouts"] = int(out["scouts"]) + 1
			continue
		if not (n.state == Monster.State.IDLE or n.state == Monster.State.SUSPICIOUS or n.state == Monster.State.RETURN):
			continue
		var d := GameWorld.flat_distance(n.global_position, f)
		var hears := d <= ALARM_RADIUS
		if not hears and n._room != "":
			for door: Vector3 in (doors.get(n._room, []) as Array):
				if GameWorld.flat_distance(door, f) <= ALARM_DOOR:
					hears = true
					break
		if hears:
			cands.append([d, n])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in mini(cands.size(), ALARM_CAP):
		var m = cands[i][1]
		m._end_suspicion(false)
		if m.alert(s):
			m.edge_until = GameWorld.time + Monster.ALERT_TIME + ALARM_EDGE
			out["woken"] = int(out["woken"]) + 1
	for g in GameWorld.root.get_tree().get_nodes_in_group(Hellgate.GROUP):
		var gate := g as Hellgate
		if gate == null or gate.dead or gate.is_active() or not Net.simulates(gate) or Hellgate.spawns_stopped():
			continue
		if GameWorld.flat_distance(gate.global_position, f) <= ALARM_GATE_RADIUS:
			gate.activate()
			out["gates"] = int(out["gates"]) + 1
	_set_floor_meta("restless_bonus", float(_floor_meta("restless_bonus", 0.0)) + ALARM_RESTLESS)
	return out


## Each room's doors on this floor: room tag -> [world points of its walkable cells that touch a corridor]. Built once
## per floor.
static func room_doors() -> Dictionary:
	var cached: Variant = _floor_meta("room_doors", null)
	if cached != null:
		return cached
	var out := {}
	var map := GameWorld.map
	if map != null:
		for c: Vector2i in map.cells:
			var cell := map.get_cell(c)
			if cell == null or not cell.tag.begins_with("room:") or not map.is_walkable_cell(c):
				continue
			for nb in Hex.neighbors(c):
				var nc := map.get_cell(nb)
				if nc != null and nc.tag == "corridor":
					if not out.has(cell.tag):
						out[cell.tag] = []
					(out[cell.tag] as Array).append(Hex.to_world(c, float(cell.level)))
					break
	_set_floor_meta("room_doors", out)
	return out


## A fireball's blast at `pos` (SpellBook, before its damage lands): a loaded scout's rack inside it goes up at once
## (goblin-scout.md §4: fire always lights fireworks). Only the monsters this machine simulates.
static func fire_at(pos: Vector3, radius: float) -> void:
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	for n in GameWorld.root.get_tree().get_nodes_in_group("monsters"):
		if n.dead or not Net.simulates(n) or not n.has_method("catch_fire"):
			continue
		if GameWorld.flat_distance(n.global_position, pos) <= radius + n.radius:
			n.catch_fire()


# --- Step 2: archer target practice ---------------------------------------------------------------------------------

## How many target-practice arrows have been loosed at `prop` this floor (every archer together).
static func practice_hits(prop: Node) -> int:
	var d: Dictionary = _floor_meta("practice_hits", {})
	return int(d.get(prop.get_instance_id(), 0))


static func note_practice_hit(prop: Node) -> void:
	var d: Dictionary = _floor_meta("practice_hits", {})
	d[prop.get_instance_id()] = int(d.get(prop.get_instance_id(), 0)) + 1
	_set_floor_meta("practice_hits", d)


## Practice arrows in flight at `prop` (loosed, not landed yet): an archer counts them before it shoots, so two archers
## never break a prop between them.
static func practice_flying(prop: Node) -> int:
	var d: Dictionary = _floor_meta("practice_flying", {})
	return int(d.get(prop.get_instance_id(), 0))


static func note_practice_flying(prop: Node, change: int) -> void:
	var d: Dictionary = _floor_meta("practice_flying", {})
	d[prop.get_instance_id()] = maxi(0, int(d.get(prop.get_instance_id(), 0)) + change)
	_set_floor_meta("practice_flying", d)

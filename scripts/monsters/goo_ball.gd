class_name GooBall
extends Node3D
## A goo imp's ball (docs/design/goo-imp.md, "As built"): lobbed on an arc from the imp's hand to a landing point fixed at
## the throw, FLIGHT seconds in the air, with a LANDING MARKER on the floor there from the throw to the splat (a dark shadow
## that grows and darkens as the ball comes down, and a bile ring the size of the patch). At the splat:
##   HIT     every hero (and chicken) whose feet are within HIT_RADIUS of the landing point takes DAMAGE and the goo slow
##           (Actor modifier GooPatch.SLOW_ID: walking speed x GooPatch.SLOW for HIT_SLOW s), applied where the hit
##           resolves (Combat.resolves: a hero's own machine). Goo on its boots shows it (GooBoots, every screen).
##   WATER   (HexMap.water_at) a splash, and the ball is gone (no slick: the user, goo-imp.md §6.5).
##   MISS    on dry ground a GooPatch, decided by the ball's OWNER (the host online) from where it has the heroes: a patch
##           only when nobody stood under the ball there.
##
## NETWORKING (networking.md: a scheduled effect the host announces; NetObjects "RUNTIME OBJECTS"). The host's imp throws
## (GooImp._strike) and the host announces the ball (Net.announce -> obj.new {k "goo_ball", r: net_spawn_row}); every client
## builds the same ball from that row (net_copy) and flies it on the shared clock, so it lands at one moment on every screen.
## Each machine resolves the hit on what it resolves (its own heroes: the victim decides); only the owner's ball makes a
## patch, and announces it the same way. Params SPAWN; the flight, the marker and the splash LOCAL. A late joiner: skipped
## (a ball lands within about a second); the patch it leaves is replayed (GooPatch).

const KIND := "goo_ball"                ## NetObjects.RUNTIME_OBJECTS
const DAMAGE := 5.0                     ## "small damage" (the swarmer's bite is 4)
const HIT_RADIUS := 0.55                ## + the victim's radius: feet this close to the landing point are hit
const HIT_DY := 1.0                     ## ... and at most this far above or below it
const HIT_SLOW := 1.5                   ## the hit's goo slow lasts this long (a short slow)
const FLIGHT_MIN := 0.85
const FLIGHT_MAX := 1.15
const FLIGHT_PER_UNIT := 0.03           ## a longer throw hangs a little longer: 0.85 s close, about 1.1 s at 9 units
const APEX := 1.4                       ## the arc's top above the higher end (+ APEX_PER_UNIT per unit thrown)
const APEX_PER_UNIT := 0.12
const LATE_SKIP := 0.25                 ## a client that hears of a ball this long after it landed skips it
const SPLAT_TIME := 0.35

var thrower: Node = null                ## the GooImp (null once gone; a copy's is the host's imp's copy)
var from := Vector3.ZERO
var to := Vector3.ZERO
## The throw's GameWorld.time on this machine (the host's, converted on a client: net_copy).
var start_time := -1.0
var flight := 1.0
var damage := DAMAGE

## This screen: true once it splatted.
var landed := false
## This screen: the actors this machine applied the hit to (tests).
var hits_applied := 0
## The owner (the host online): every hero stood under it there (no patch); the patch it made, if any (tests).
var hit_any := false
var patch: Node = null

var _ball: MeshInstance3D = null
var _marker: Node3D = null
var _shadow: MeshInstance3D = null
var _drops: Array[MeshInstance3D] = []
var _gone_at := INF


## Who may write each var (see Net). A scheduled effect the host announces: params SPAWN, the rest this screen's.
func net_fields() -> Dictionary:
	return {
		"thrower": Net.SPAWN, "from": Net.SPAWN, "to": Net.SPAWN, "start_time": Net.SPAWN, "flight": Net.SPAWN,
		"damage": Net.SPAWN,
		"landed": Net.LOCAL, "hits_applied": Net.LOCAL,
		"hit_any": Net.PRIVATE, "patch": Net.PRIVATE,   # (the owner's patch decision; the patch itself is announced)
		"_ball": Net.LOCAL, "_marker": Net.LOCAL, "_shadow": Net.LOCAL, "_drops": Net.LOCAL, "_gone_at": Net.LOCAL,
	}


## How long a ball thrown `dist` units hangs in the air.
static func flight_for(dist: float) -> float:
	return clampf(FLIGHT_MIN + FLIGHT_PER_UNIT * dist, FLIGHT_MIN, FLIGHT_MAX)


## Throw a ball now (the owner: GooImp._strike, tests). The caller announces it (Net.announce).
static func throw(by: Node, at: Vector3, land: Vector3, start: float, secs: float) -> GooBall:
	var b := GooBall.new()
	b.thrower = by
	b.from = at
	b.to = land
	b.start_time = start
	b.flight = secs
	if by != null and "attack_damage" in by:
		b.damage = float(by.get("attack_damage"))
	GameWorld.spawn(b, at)
	return b


## Where the ball is `u` (0..1) of the way along its arc.
func point_at(u: float) -> Vector3:
	u = clampf(u, 0.0, 1.0)
	var top := maxf(from.y, to.y) + APEX + APEX_PER_UNIT * GameWorld.flat_distance(from, to)
	var p := from.lerp(to, u)
	# a parabola through from (u 0) and to (u 1) peaking at `top` (a quadratic Bezier with its control point placed so)
	var c := 2.0 * top - 0.5 * (from.y + to.y)
	p.y = (1.0 - u) * (1.0 - u) * from.y + 2.0 * u * (1.0 - u) * c + u * u * to.y
	return p


func land_time() -> float:
	return start_time + flight


# --- The net contract (NetObjects, RUNTIME OBJECTS) ---------------------------------------------------------------

## The host: what a client needs to build this ball (NetObjects obj.new).
func net_spawn_row(objects: NetObjects) -> Array:
	return [NetFloor.id_of(thrower) if thrower != null and is_instance_valid(thrower) else 0, from, to,
		objects.host_stamp(start_time), flight, damage]


## A client: the host's ball from its row, on this machine's clock; null when it has already landed here.
static func net_copy(row: Array, objects: NetObjects) -> Node:
	if row.size() < 6 or GameWorld.root == null:
		return null
	var start := objects.local_stamp(float(row[3]))
	if start + float(row[4]) < GameWorld.time - LATE_SKIP:
		return null
	var b := GooBall.new()
	b.thrower = NetRegistry.node(int(row[0]))
	b.from = row[1]
	b.to = row[2]
	b.start_time = start
	b.flight = float(row[4])
	b.damage = float(row[5])
	GameWorld.spawn(b, b.point_at((GameWorld.time - start) / maxf(b.flight, 0.01)))
	return b


## A client's copy keeps flying (its physics is the flight and its own hero's hit); it only stops deciding (no patch).
func net_make_copy() -> void:
	set_meta(Net.COPY_META, true)


func net_order() -> int:
	return 3


# --- Flight -------------------------------------------------------------------------------------------------------

func _ready() -> void:
	if start_time < 0.0:
		start_time = GameWorld.time
	_ball = GooSoups.ball()
	add_child(_ball)
	var m := GooSoups.marker(GooPatch.RADIUS)
	_marker = m[0]
	_shadow = m[1]
	if GameWorld.root != null and GameWorld.root.is_inside_tree():
		GameWorld.root.add_child(_marker)   # (on the floor, not riding the ball)
	else:
		add_child(_marker)
	_marker.global_position = to
	for i in 5:
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var rr := 0.085 * (1.0 - 0.12 * float(i))
		sm.radius = rr
		sm.height = rr * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		d.mesh = sm
		d.material_override = GooSoups.glow_mat(GooSoups.BILE, 0.9 - 0.12 * float(i), 2.0)
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.top_level = true
		add_child(d)
		_drops.append(d)
	_fly(GameWorld.time)


func _exit_tree() -> void:
	if _marker != null and is_instance_valid(_marker) and _marker.get_parent() != self:
		_marker.queue_free()


func _physics_process(_delta: float) -> void:
	var t := GameWorld.time
	if landed:
		if t >= _gone_at:
			queue_free()
		return
	if t >= land_time():
		_land()
		return
	_fly(t)


func _fly(t: float) -> void:
	var u := (t - start_time) / maxf(flight, 0.01)
	var p := point_at(u)
	global_position = p
	var ahead := point_at(u + 0.03)
	if ahead.distance_to(p) > 0.001 and _ball != null:
		_ball.look_at_from_position(p, ahead, Vector3.UP if absf((ahead - p).normalized().y) < 0.98 else Vector3.RIGHT)
	for i in _drops.size():
		_drops[i].global_position = point_at(u - 0.035 * float(i + 1))
		_drops[i].visible = u - 0.035 * float(i + 1) > 0.0
	if _shadow != null:
		var k := clampf(u, 0.0, 1.0)
		var r := lerpf(0.3, 0.6, k)
		_shadow.scale = Vector3(r, 1.0, r)
		(_shadow.material_override as StandardMaterial3D).albedo_color.a = lerpf(0.25, 0.6, k)


# --- The splat ----------------------------------------------------------------------------------------------------

func _land() -> void:
	landed = true
	global_position = to
	var src: Node = thrower if thrower != null and is_instance_valid(thrower) else null
	var map := GameWorld.map
	var wet := map != null and not map.pools.is_empty() and map.water_at(to)
	for a in GameWorld.hittable_in_radius(to, HIT_RADIUS, GameWorld.TEAM_HEROES):
		if a.dead or a.is_in_group("breakables") or absf(a.global_position.y - to.y) > HIT_DY:
			continue
		hit_any = true
		GooBoots.show_on(a, HIT_SLOW)
		if not Combat.resolves(a, src):
			continue   # (another machine decides it: its own hero, or the host's chicken)
		a.apply_damage(damage, src)
		if not a.dead:
			a.set_modifier(GooPatch.SLOW_ID, GooPatch.SLOW, HIT_SLOW, Actor.STAT_MOVE_SPEED)
		hits_applied += 1
	_splash(wet)
	if not wet and not hit_any and Net.owns(self):
		patch = GooPatch.make(to, start_time)
		Net.announce(patch)
	_gone_at = GameWorld.time + SPLAT_TIME


## The splat (cosmetic): goo droplets, or a white splash and a ripple in the water. The ball and its marker go.
func _splash(wet: bool) -> void:
	if _ball != null:
		_ball.visible = false
	for d in _drops:
		d.visible = false
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
		_marker = null
	if GameWorld.root == null or not GameWorld.root.is_inside_tree():
		return
	if wet:
		var water: Array[Color] = [Color(0.85, 0.92, 0.8), Color(0.55, 0.7, 0.45)]
		Fx.burst(to + Vector3.UP * 0.1, water, 14, 2.6, 0.07, 0.5, 9.0, Vector3.UP, 35.0)
		Fx.ring(to, 0.7, Color(0.8, 0.9, 0.7, 0.6), 0.5)
		return
	var goo: Array[Color] = [GooSoups.BILE, GooSoups.hot(GooSoups.BILE)]
	Fx.burst(to + Vector3.UP * 0.15, goo, 12, 2.2, 0.07, 0.45, 9.0, Vector3.UP, 60.0)

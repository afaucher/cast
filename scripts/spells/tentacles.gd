class_name Tentacles
extends Node3D
## The Tentacles spell. After a short TELEGRAPH (game time) neon tentacles burst from the floor at this node's position and
## shove EVERYONE inside their oval directly away from the centre: heroes, the caster and monsters alike. Then they stay up
## (TentaclesSpell.tentacles_duration: 4 s at minimum power, 6 s at full) and every TentaclesSpell.TENTACLES_SWAT_EVERY
## seconds they SWAT everyone inside the oval out of its nearest edge, a smaller shove. Monsters and breakables take a
## little damage at the burst and at every swat, heroes none. Anyone exactly at the centre is pushed along their facing
## by the burst.
##
## The oval lies SIDEWAYS across the caster's line of aim (the user, 2026-10-27: "Let's consider increasing the width of
## the area but not the depth. Again with strength."): `aim` (caster -> target, flat; SPAWN, fixed on the caster's
## machine and carried by the cast event, TentaclesSpell.cast_extra) is the DEPTH axis, the old radius
## (TentaclesSpell.tentacles_depth); across it is the WIDTH axis, 1.2 to 1.5 times as long (tentacles_width).
##
## Only FLOOR counts (the user, 2026-10-28: "Maybe we can limit it to just the floor space?"): a spot in the oval is in
## the area when it is floor (not wall, not void) and the centre sees it without crossing a wall (reaches). Tentacles
## grow only there, and only bodies standing there are shoved and swatted, so nothing reaches into the next room.
##
## Every machine runs the same schedule from the cast's moment (start_time, SPAWN): the burst at TELEGRAPH, swat k at
## TELEGRAPH + k x SWAT_EVERY. Each machine applies only the hits it resolves (Combat.hits_in_radius: a hero's by its owner,
## the rest by the caster's machine), so every hit lands once. The shoves go through Actor.shove, so ledges, walls, pits,
## falls and the friendly-fire protection (a hero-caused shove never downs a hero) all apply. The visuals are a separate
## node, TentaclesFx, running on the same clock.

const TELEGRAPH := 0.25
## How high above the floor the reach test's sight line runs (reaches): over a terrace step, under a wall.
const REACH_LIFT := 0.9

var power := 1.0
var source_team := GameWorld.TEAM_HEROES
var caster: Actor = null
## The cast's GameWorld.time (SPAWN, from the cast event, M4a): the burst is TELEGRAPH after it. -1 = start now.
var start_time := -1.0
## The caster's line of aim, flat and unit length (SPAWN, the cast event's extra `d`): the oval's depth axis.
var aim := Vector3.FORWARD

var _burst_done := false
var _swats := 0             ## swats made so far
var _fx: TentaclesFx = null


func _ready() -> void:
	if start_time < 0.0:
		start_time = GameWorld.time
	aim.y = 0.0
	aim = aim.normalized() if aim.length() > 0.001 else Vector3.FORWARD
	_fx = TentaclesFx.new()
	_fx.depth = depth()
	_fx.width = width()
	_fx.aim = aim
	_fx.telegraph = TELEGRAPH
	_fx.up = TentaclesSpell.tentacles_duration(power)
	_fx.swat_every = TentaclesSpell.TENTACLES_SWAT_EVERY
	_fx.power = power
	_fx.start_time = start_time
	add_child(_fx)


## Who may write each var (see Net). A scheduled effect: one cast event, then every machine runs the burst and the swats
## from these parameters and GameWorld.time.
func net_fields() -> Dictionary:
	return {
		"power": Net.SPAWN, "source_team": Net.SPAWN,
		"caster": Net.SPAWN,      # travels as the caster's net id in the cast event (NetCasts)
		"start_time": Net.SPAWN,
		"aim": Net.SPAWN,         # travels in the cast event's extra (TentaclesSpell.cast_extra)
		"_burst_done": Net.LOCAL, "_swats": Net.LOCAL, "_fx": Net.LOCAL,
	}


func depth() -> float:
	return TentaclesSpell.tentacles_depth(power)


func width() -> float:
	return TentaclesSpell.tentacles_width(power)


## The moment (GameWorld.time) of swat `k` (1, 2, ...).
func swat_time(k: int) -> float:
	return start_time + TELEGRAPH + float(k) * TentaclesSpell.TENTACLES_SWAT_EVERY


func _physics_process(_delta: float) -> void:
	var t := GameWorld.time - start_time
	if not _burst_done:
		if t < TELEGRAPH:
			return
		_burst()
	var n := TentaclesSpell.tentacles_swats(power)
	while _swats < n and GameWorld.time >= swat_time(_swats + 1):
		_swats += 1
		_swat()
	if t >= TELEGRAPH + TentaclesSpell.tentacles_duration(power) + TentaclesFx.RETRACT:
		queue_free()


## True when `a` (its body included) is inside the oval, on floor the centre reaches.
func covers(a: Actor) -> bool:
	return in_oval(a.global_position, global_position, aim, depth(), width(), a.radius) 			and reaches(GameWorld.map, global_position, a.global_position)


func _source() -> Node:
	return caster if is_instance_valid(caster) else null


func _burst() -> void:
	_burst_done = true
	var src := _source()
	var dist := TentaclesSpell.tentacles_distance(power)
	var dmg := TentaclesSpell.tentacles_damage(power)
	_crack_floor()   # floor cracks that fade after 30 s
	MonsterSenses.noise(global_position, MonsterSenses.NOISE_TENTACLES, "tentacles")   # (only the monsters this machine runs hear)
	_feedback()
	for a in Combat.hits_in_radius(global_position, width(), src):   # (online: the victim decides a hero, the caster the rest)
		if not covers(a):
			continue   # (the circle round the oval: only its inside counts)
		if Combat.shielded(a, global_position, Combat.HIT_BLAST, src):
			continue   # (the centre in front of a pavise's planks: a bonk)
		var away := a.global_position - global_position
		away.y = 0.0
		a.shove(away if away.length() > 0.05 else a.facing, dist, src)
		if a.team == GameWorld.TEAM_MONSTERS or a.is_in_group("breakables"):
			a.apply_damage(dmg, src)   # (mail packages burst when the tentacles come up under them)


## A swat: everyone inside the oval is shoved out of its nearest edge (for this wide oval mostly across it, back toward
## the side they are on); monsters and breakables take the damage again.
func _swat() -> void:
	var src := _source()
	var dist := TentaclesSpell.tentacles_swat_distance(power)
	var dmg := TentaclesSpell.tentacles_damage(power)
	_feedback()
	for a in Combat.hits_in_radius(global_position, width(), src):   # (online: the victim decides a hero, the caster the rest)
		if not covers(a):
			continue
		var out := edge_push(a.global_position, global_position, aim, depth(), width())
		if Combat.shielded(a, a.global_position - out, Combat.HIT_BLAST, src):
			continue   # (swatted from behind its planks' side: a bonk)
		a.shove(out, dist, src)
		if a.team == GameWorld.TEAM_MONSTERS or a.is_in_group("breakables"):
			a.apply_damage(dmg, src)


## The hit flash on every monster inside the oval (every machine shows it).
func _feedback() -> void:
	for a in GameWorld.actors_in_radius(global_position, width(), GameWorld.TEAM_MONSTERS):
		if covers(a):
			Fx.attach_hit_feedback(a)


## Floor cracks over the oval: one patch in the middle and one toward each end of it.
func _crack_floor() -> void:
	var d := depth()
	var side := Vector3(-aim.z, 0.0, aim.x)
	Grime.mark(Grime.CRACKS, global_position, d)
	var reach := maxf(0.0, width() - d * 0.75)
	for s in [-1.0, 1.0]:
		Grime.mark(Grime.CRACKS, global_position + side * (s * reach), d * 0.7)


# --- The oval's geometry (static: the reticle and the tests use it too) ------------------------------------------------

## True when the tentacles can come up at `p` (world X/Z): it is floor, not wall or void, and a line REACH_LIFT above the
## floor runs to it from the centre without passing through a wall. No map (a bare test world): everywhere.
static func reaches(map: HexMap, center: Vector3, p: Vector3) -> bool:
	if map == null:
		return true
	if map.wall_at(p):
		return false
	var g := map.ground_height(p)
	if is_nan(g):
		return false
	var gc := map.ground_height(center)
	var from := Vector3(center.x, (center.y if is_nan(gc) else gc) + REACH_LIFT, center.z)
	return map.line_of_sight(from, Vector3(p.x, g + REACH_LIFT, p.z), 0.1, false)

# Local coordinates: x across the aim (the width axis, `side` = aim turned a quarter left), y along the aim (depth).

## `p` in the oval's local coordinates: x along `side`, y along `aim`.
static func to_local_oval(p: Vector3, center: Vector3, aim_dir: Vector3) -> Vector2:
	var side := Vector3(-aim_dir.z, 0.0, aim_dir.x)
	var d := p - center
	d.y = 0.0
	return Vector2(d.dot(side), d.dot(aim_dir))


## True when `p` is inside the oval of half-axes `depth` (along `aim_dir`) and `width` (across it), grown by `pad` (a body).
static func in_oval(p: Vector3, center: Vector3, aim_dir: Vector3, depth_ax: float, width_ax: float, pad: float = 0.0) -> bool:
	var q := to_local_oval(p, center, aim_dir)
	var w := width_ax + pad
	var h := depth_ax + pad
	return (q.x * q.x) / (w * w) + (q.y * q.y) / (h * h) <= 1.0


## The unit direction (flat) from `p` out of the oval's NEAREST edge: the outward normal at the edge point closest to `p`.
## At the very centre: along the aim, away from the caster.
static func edge_push(p: Vector3, center: Vector3, aim_dir: Vector3, depth_ax: float, width_ax: float) -> Vector3:
	var q := to_local_oval(p, center, aim_dir)
	var sx := -1.0 if q.x < 0.0 else 1.0
	var sy := -1.0 if q.y < 0.0 else 1.0
	var near := nearest_on_ellipse(maxf(width_ax, depth_ax), minf(width_ax, depth_ax), absf(q.x), absf(q.y)) if width_ax >= depth_ax \
			else _swap(nearest_on_ellipse(depth_ax, width_ax, absf(q.y), absf(q.x)))
	var n := Vector2(near.x / (width_ax * width_ax), near.y / (depth_ax * depth_ax))
	if n.length() < 0.000001:
		n = Vector2(0.0, 1.0)
	n = n.normalized()
	var side := Vector3(-aim_dir.z, 0.0, aim_dir.x)
	return (side * (n.x * sx) + aim_dir * (n.y * sy)).normalized()


static func _swap(v: Vector2) -> Vector2:
	return Vector2(v.y, v.x)


## The point of the ellipse x^2/e0^2 + y^2/e1^2 = 1 (e0 >= e1 > 0) nearest to (y0, y1), both >= 0 (the first quadrant).
## Eberly's robust method ("Distance from a Point to an Ellipse"): a bisection on the Lagrange multiplier.
static func nearest_on_ellipse(e0: float, e1: float, y0: float, y1: float) -> Vector2:
	if y1 > 0.0:
		if y0 > 0.0:
			var z0 := y0 / e0
			var z1 := y1 / e1
			var g := z0 * z0 + z1 * z1 - 1.0
			if absf(g) < 1e-9:
				return Vector2(y0, y1)
			var r0 := (e0 / e1) * (e0 / e1)
			var sbar := _ellipse_root(r0, z0, z1, g)
			return Vector2(r0 * y0 / (sbar + r0), y1 / (sbar + 1.0))
		return Vector2(0.0, e1)
	var numer0 := e0 * y0
	var denom0 := e0 * e0 - e1 * e1
	if numer0 < denom0:
		var xde0 := numer0 / denom0
		return Vector2(e0 * xde0, e1 * sqrt(maxf(0.0, 1.0 - xde0 * xde0)))
	return Vector2(e0, 0.0)


static func _ellipse_root(r0: float, z0: float, z1: float, g: float) -> float:
	var n0 := r0 * z0
	var s0 := z1 - 1.0
	var s1 := 0.0 if g < 0.0 else Vector2(n0, z1).length() - 1.0
	var s := 0.0
	for i in 80:
		s = 0.5 * (s0 + s1)
		if s == s0 or s == s1:
			break
		var ratio0 := n0 / (s + r0)
		var ratio1 := z1 / (s + 1.0)
		var gs := ratio0 * ratio0 + ratio1 * ratio1 - 1.0
		if gs > 0.0:
			s0 = s
		elif gs < 0.0:
			s1 = s
		else:
			break
	return s

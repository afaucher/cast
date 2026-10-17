class_name Combat
extends RefCounted
## Shared combat helpers used by heroes and monsters alike.


## Hit every actor of the other team within `reach` of the attacker and
## inside a cone of `arc_deg` around `dir`, plus any breakable (mail package, GameWorld.hittable_in_radius).
## Returns the actors hit. `shove` > 0 also pushes each target that distance directly away from the
## attacker (scaled by its shove_mult).
static func melee_arc(attacker: Actor, dir: Vector3, reach: float, arc_deg: float, damage: float, shove: float = 0.0) -> Array[Actor]:
	dir.y = 0.0
	dir = dir.normalized()
	var hit: Array[Actor] = []
	var foe := GameWorld.other_team(attacker.team)
	for a in GameWorld.hittable_in_radius(attacker.global_position, reach, foe):
		var to := a.global_position - attacker.global_position
		to.y = 0.0
		if arc_deg < 360.0 and to.length() > 0.001 and rad_to_deg(dir.angle_to(to.normalized())) > arc_deg * 0.5:   # (a full circle skips the test: a target exactly behind measured 180.0000x degrees and was missed)
			continue
		# Can't swing up/down a cliff: at most a 2-level difference.
		if absf(a.global_position.y - attacker.global_position.y) > 2.1 * Hex.LEVEL_HEIGHT:
			continue
		a.apply_damage(damage, attacker)
		if shove > 0.0:
			a.shove(to if to.length() > 0.001 else dir, shove, attacker)
		hit.append(a)
	return hit


## Push every living actor within `radius` of `pos` (all teams, or `team` only if >= 0)
## `distance` units directly away from `pos`, scaled by each one's shove_mult. An actor
## standing on the center goes along its own facing. Returns the actors pushed.
static func shove_radius(pos: Vector3, radius: float, distance: float, source: Node = null, team: int = -1, skip: Actor = null) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if a == skip:
			continue
		var away := a.global_position - pos
		away.y = 0.0
		a.shove(away if away.length() > 0.05 else a.facing, distance, source)
		out.append(a)
	return out


## Run `apply` (a Callable taking one Actor) on every living actor within `radius` of `pos` (all teams, or `team`
## only if >= 0). This is the one place an area spell applies a status to whoever stands in it (the verb it calls,
## e.g. Actor.set_modifier, is what the Net layer routes to the actor's owner). Returns the actors it reached.
static func each_in_radius(pos: Vector3, radius: float, apply: Callable, team: int = -1) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		apply.call(a)
		out.append(a)
	return out


## Give everyone within `radius` of `pos` the modifier `id` (Actor.set_modifier: `stat` says what it changes, the
## same id refreshes), e.g. vines' root. Returns the actors it reached.
static func modify_radius(pos: Vector3, radius: float, id: String, mult: float, duration: float, stat: String = Actor.STAT_DAMAGE_TAKEN, team: int = -1) -> Array[Actor]:
	return each_in_radius(pos, radius, func(a: Actor) -> void: a.set_modifier(id, mult, duration, stat), team)


## Damage everyone of `team` (-1 = everyone) within radius of pos, with
## linear falloff to `edge_mult` at the rim. Returns the actors hit.
static func explode(pos: Vector3, radius: float, damage: float, team: int, source: Node = null, edge_mult: float = 0.5) -> Array[Actor]:
	var hit: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		var d := GameWorld.flat_distance(a.global_position, pos)
		var k := lerpf(1.0, edge_mult, clampf(d / maxf(radius, 0.001), 0.0, 1.0))
		a.apply_damage(damage * k, source)
		hit.append(a)
	return hit


## Chest-height point of an actor, for launching projectiles / LOS checks.
static func chest(a: Actor) -> Vector3:
	return a.global_position + Vector3.UP * 0.9

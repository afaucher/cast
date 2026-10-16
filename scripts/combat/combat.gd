class_name Combat
extends RefCounted
## Shared combat helpers used by heroes and monsters alike.


## Hit every actor of the other team within `reach` of the attacker and
## inside a cone of `arc_deg` around `dir`. Returns the actors hit.
static func melee_arc(attacker: Actor, dir: Vector3, reach: float, arc_deg: float, damage: float) -> Array[Actor]:
	dir.y = 0.0
	dir = dir.normalized()
	var hit: Array[Actor] = []
	var foe := GameWorld.other_team(attacker.team)
	for a in GameWorld.actors_in_radius(attacker.global_position, reach, foe):
		var to := a.global_position - attacker.global_position
		to.y = 0.0
		if to.length() > 0.001 and rad_to_deg(dir.angle_to(to.normalized())) > arc_deg * 0.5:
			continue
		# Can't swing up/down a cliff: at most a 2-level difference.
		if absf(a.global_position.y - attacker.global_position.y) > 2.1 * Hex.LEVEL_HEIGHT:
			continue
		a.apply_damage(damage, attacker)
		hit.append(a)
	return hit


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

class_name Combat
extends RefCounted
## Shared combat helpers used by heroes and monsters alike.
##
## Online (docs/design/networking.md, layer 4): an effect may run on every machine (a cast, a replayed swing, a monster's
## strike on the victim's screen), so every helper here applies its verbs only to the targets THIS machine resolves:
## a hero by its owner (the victim decides), anything else by the attacker's machine (Net.resolves_hit), and statuses by
## the target's owner (Net.resolves). Offline every target resolves, so solo play is exactly as it was. An area loop
## outside this file that calls a verb asks Combat.resolves first (test_net_contract checks it).


## Does this machine decide a hit from `source` on `target`? (Net.resolves_hit: the victim for a hero, the attacker for
## anything else.)
static func resolves(target: Actor, source: Node) -> bool:
	return Net.resolves_hit(target, source)


## Hit every actor of the other team within `reach` of the attacker and
## inside a cone of `arc_deg` around `dir`, plus any breakable (mail package, GameWorld.hittable_in_radius). A hero's
## swing also hits the priced props in it (user, 2026-10-18: "let player attacks break them"); a monster's does not.
## Returns the actors hit. `shove` > 0 also pushes each target that distance directly away from the
## attacker (scaled by its shove_mult).
static func melee_arc(attacker: Actor, dir: Vector3, reach: float, arc_deg: float, damage: float, shove: float = 0.0) -> Array[Actor]:
	dir.y = 0.0
	dir = dir.normalized()
	var hit: Array[Actor] = []
	var foe := GameWorld.other_team(attacker.team)
	for a in GameWorld.hittable_in_radius(attacker.global_position, reach, foe, attacker.team == GameWorld.TEAM_HEROES):
		var to := a.global_position - attacker.global_position
		to.y = 0.0
		if arc_deg < 360.0 and to.length() > 0.001 and rad_to_deg(dir.angle_to(to.normalized())) > arc_deg * 0.5:   # (a full circle skips the test: a target exactly behind measured 180.0000x degrees and was missed)
			continue
		# Can't swing up/down a cliff: at most a 2-level difference.
		if absf(a.global_position.y - attacker.global_position.y) > 2.1 * Hex.LEVEL_HEIGHT:
			continue
		if not Net.resolves_hit(a, attacker):
			continue   # (online: another machine decides this one)
		a.apply_damage(damage, attacker)
		if shove > 0.0:
			a.shove(to if to.length() > 0.001 else dir, shove, attacker)
		hit.append(a)
	return hit


## Push every living actor within `radius` of `pos` (all teams, or `team` only if >= 0)
## `distance` units directly away from `pos`, scaled by each one's shove_mult. An actor
## standing on the center goes along its own facing. Returns the actors pushed. `max_dy` >= 0 skips anyone more than
## that far above or below `pos` (a spin can't reach up a cliff).
static func shove_radius(pos: Vector3, radius: float, distance: float, source: Node = null, team: int = -1, skip: Actor = null, max_dy: float = -1.0) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if a == skip or (max_dy >= 0.0 and absf(a.global_position.y - pos.y) > max_dy):
			continue
		if not Net.resolves_hit(a, source):
			continue
		var away := a.global_position - pos
		away.y = 0.0
		a.shove(away if away.length() > 0.05 else a.facing, distance, source)
		out.append(a)
	return out


## The living actors within `radius` of `pos` (all teams, or `team` if >= 0) whose hits from `source` this machine
## decides (Net.resolves_hit). Spells that do their own thing per target (tentacles, a teeth pop) loop over this.
static func hits_in_radius(pos: Vector3, radius: float, source: Node, team: int = -1) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if Net.resolves_hit(a, source):
			out.append(a)
	return out


## Run `apply` (a Callable taking one Actor) on every living actor within `radius` of `pos` (all teams, or `team`
## only if >= 0). This is the one place an area spell applies a status to whoever stands in it; online only to the
## actors this machine owns (Net.resolves: a hero's player, the host for the rest), so a status is applied once, by
## the target's owner. Returns the actors it reached.
static func each_in_radius(pos: Vector3, radius: float, apply: Callable, team: int = -1) -> Array[Actor]:
	var out: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if not Net.resolves(a):
			continue
		apply.call(a)
		out.append(a)
	return out


## Give everyone within `radius` of `pos` the modifier `id` (Actor.set_modifier: `stat` says what it changes, the
## same id refreshes), e.g. vines' root. Returns the actors it reached.
static func modify_radius(pos: Vector3, radius: float, id: String, mult: float, duration: float, stat: String = Actor.STAT_DAMAGE_TAKEN, team: int = -1) -> Array[Actor]:
	return each_in_radius(pos, radius, func(a: Actor) -> void: a.set_modifier(id, mult, duration, stat), team)


## Heal everyone of `team` within `radius` of `pos` by `amount` (each target's owner heals it). Returns
## [[actor, hp restored], ...].
static func heal_radius(pos: Vector3, radius: float, amount: float, team: int) -> Array:
	var out := []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if Net.resolves(a):
			out.append([a, a.heal(amount)])
	return out


## Damage everyone of `team` (-1 = everyone) within radius of pos, with
## linear falloff to `edge_mult` at the rim. Returns the actors hit.
## `shove` > 0 also pushes each one that far straight out from `pos` (falling off like the damage). `decider` (an explosive
## prop's blast: the prop) is whose machine decides the hits on everything but a hero, when that is not `source`'s: the
## blast is the host's prop, so the host applies it to monsters, props and employees even when a client's hero set it off
## (the bill and the kill credit still go to `source`). Null: `source` decides, as for every other explosion.
static func explode(pos: Vector3, radius: float, damage: float, team: int, source: Node = null, edge_mult: float = 0.5, shove: float = 0.0, decider: Node = null) -> Array[Actor]:
	var hit: Array[Actor] = []
	var judge: Node = decider if decider != null else source
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if a == decider or not Net.resolves_hit(a, judge):
			continue
		var d := GameWorld.flat_distance(a.global_position, pos)
		var k := lerpf(1.0, edge_mult, clampf(d / maxf(radius, 0.001), 0.0, 1.0))
		a.apply_damage(damage * k, source)
		if shove > 0.0 and not a.dead:
			var away := a.global_position - pos
			away.y = 0.0
			a.shove(away if away.length() > 0.05 else a.facing, shove * k, source)
		hit.append(a)
	return hit


## A ground slam (the brute): everyone of `team` within `radius` of `pos` and at most `max_dy` above or below it,
## judged by their centre, takes `damage` falling off to `edge_mult` at the rim and is shoved `shove` away. A direct hit
## (centre within `daze_radius`, the inner zone) is also dazed for `daze_time` (Actor.daze: the owner applies it, here,
## since the hit resolves on the victim's machine; shove_mult does not matter). Returns the actors hit.
static func slam(pos: Vector3, radius: float, damage: float, edge_mult: float, shove: float, max_dy: float, team: int, source: Node, daze_radius: float = 0.0, daze_time: float = 0.0) -> Array[Actor]:
	var hit: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if absf(a.global_position.y - pos.y) > max_dy:
			continue
		var d := GameWorld.flat_distance(a.global_position, pos)
		if d > radius + 0.1:
			continue   # judged by the actor's center, so the ring is honest
		if not Net.resolves_hit(a, source):
			continue
		a.apply_damage(damage * lerpf(1.0, edge_mult, clampf(d / radius, 0.0, 1.0)), source)
		a.shove(a.global_position - pos, shove, source)
		if daze_time > 0.0 and d <= daze_radius and not a.dead:
			a.daze(daze_time, source)
		hit.append(a)
	if team != -1:
		# The ground shock sets off an explosive prop in the ring (docs/design/hazards.md): a full hit, wherever it stands in
		# it. A monster's slam leaves the other priced props alone, as its swings do.
		for p in GameWorld.props_in_radius(pos, radius):
			if not (p is ExplosiveProp) or absf(p.global_position.y - pos.y) > max_dy or not Net.resolves_hit(p, source):
				continue
			p.apply_damage(damage, source)
	return hit


## A shark's bite (docs/design/sharks.md): everyone (all teams) within `reach` of `at` (the snout) and at most `max_dy`
## above or below it, but `skip` (the shark, its rider), takes `damage` and is shoved `shove` along `away.call(actor)`
## (the shark's "out of the water": back onto the deck). Applied only where the hit resolves (the victim's machine for a
## hero, the shark's for the rest). Returns the actors hit.
static func bite(attacker: Actor, at: Vector3, reach: float, damage: float, shove: float, away: Callable, skip: Array = [], max_dy: float = 1.2) -> Array[Actor]:
	var hit: Array[Actor] = []
	for a in GameWorld.actors_in_radius(at, reach):
		if a == attacker or skip.has(a) or a.is_in_group(PricedProp.GROUP) or a.is_in_group("breakables"):
			continue
		if absf(a.global_position.y - at.y) > max_dy or not Net.resolves_hit(a, attacker):
			continue
		a.apply_damage(damage, attacker)
		if shove > 0.0 and not a.dead:
			a.shove(away.call(a), shove, attacker)
		hit.append(a)
	return hit


## A beam (the laser shark's, docs/design/sharks.md): a straight horizontal line from `from` along `dir` (X/Z) for up to
## `reach`. It stops at the first thing it meets: a wall or anything taller than the beam (HexMap.line_of_sight's ground
## test), a set-piece solid, a shut door (HexMap.blocker_contact), or a body (any living actor within its radius plus
## `half_width` of the line, standing low enough to be crossed: a hero, a monster, an employee, a chicken, a priced or
## explosive prop, a crate, mail). That first body takes `damage` from `source`, applied where the hit resolves (the
## victim's machine for a hero, `source`'s for the rest), so every machine may run the beam and each applies its own.
## `skip`: actors the beam passes (the shark, its rider). Returns {end: Vector3 (where it stopped), hit: Actor or null,
## applied: bool}.
static func beam(source: Actor, from: Vector3, dir: Vector3, reach: float, damage: float, half_width: float = 0.25, skip: Array = []) -> Dictionary:
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.0001 else Vector3.FORWARD
	var map := GameWorld.map
	var stop := reach
	if map != null:
		var step := 0.1
		var d := step
		while d < reach:
			var p := from + dir * d
			var g := map.ground_height(p)
			if (not is_nan(g) and g > p.y) or map.solid_at(p):
				stop = maxf(0.0, d - step)
				break
			d += step
		var door := map.blocker_contact(from, from + dir * stop)
		if door != Vector3.INF:
			stop = minf(stop, GameWorld.flat_distance(from, door))
	var first: Actor = null
	var first_t := stop
	for a in GameWorld.actors():
		if a == source or skip.has(a):
			continue
		var to := a.global_position - from
		var t := to.x * dir.x + to.z * dir.z
		if t < 0.0 or t > first_t:
			continue
		var lateral := absf(to.x * dir.z - to.z * dir.x)
		if lateral > a.radius + half_width:
			continue
		if a.global_position.y > from.y + 0.2 or a.global_position.y < from.y - 1.8:
			continue   # (stands above the beam, or too far below it)
		first = a
		first_t = t
	var applied := false
	if first != null and Net.resolves_hit(first, source):
		first.apply_damage(damage, source)
		applied = true
	return {"end": from + dir * first_t, "hit": first, "applied": applied}


## A peck (the Chicken spell): a hit for nothing on `target`, applied where the hit resolves (Net.resolves_hit: the chicken's
## machine, the host, for everything but a hero, whose own machine decides; a peck does nothing to a hero, so nothing needs
## to travel), through the target's peck verb (Actor.peck). True if this machine applied it.
static func peck(pecker: Actor, target: Actor) -> bool:
	if target == null or not is_instance_valid(target) or target.dead or not Net.resolves_hit(target, pecker):
		return false
	target.peck(pecker)
	return true


## Chest-height point of an actor, for launching projectiles / LOS checks.
static func chest(a: Actor) -> Vector3:
	return a.global_position + Vector3.UP * 0.9

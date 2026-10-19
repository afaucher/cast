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
static func explode(pos: Vector3, radius: float, damage: float, team: int, source: Node = null, edge_mult: float = 0.5) -> Array[Actor]:
	var hit: Array[Actor] = []
	for a in GameWorld.actors_in_radius(pos, radius, team):
		if not Net.resolves_hit(a, source):
			continue
		var d := GameWorld.flat_distance(a.global_position, pos)
		var k := lerpf(1.0, edge_mult, clampf(d / maxf(radius, 0.001), 0.0, 1.0))
		a.apply_damage(damage * k, source)
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
	return hit


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

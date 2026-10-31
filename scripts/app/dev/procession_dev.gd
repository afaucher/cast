class_name ProcessionDev
extends RefCounted
## The procession's dev flags (haunted-build-plan.md, "H4 as built"; the user: "We will try it in the game when it is ready").
## GameDev calls it. A haunted contract's floors 1-2 have processions (--client heir | parish, --seed N, --floor 1 | 2); the log
## names each one's rooms ("procession: ...").
##   --to-procession [n]      solo: the crew starts a few cells ahead of procession n's leader (default 0), on its way
##   --focus procession       the camera follows that procession's leader (with the raise demo: its rear acolyte)
##   --procession-demo walk|raise|fight   after --demo-after seconds (1.0); the AI allies hold:
##        walk   every monster's senses are off (Monster.is_frozen: the procession still walks its route), so it walks past
##        raise  as walk, and the file's last two zombies drop where they walk: the rear acolyte raises them, they rejoin
##        fight  the procession turns on the player: the zombies come, the acolytes run
## No keybinding.

const NEAR_MIN := 5                 ## the crew stands this many cells from the leader at least ...
const NEAR_MAX := 8                 ## ... and at most, toward the route's next spot


static func parse(args: PackedStringArray, opts: Dictionary) -> void:
	var k := args.find("--to-procession")
	if k >= 0:
		opts["to_procession"] = int(args[k + 1]) if k + 1 < args.size() and args[k + 1].is_valid_int() else 0
	var d := args.find("--procession-demo")
	if d >= 0 and d + 1 < args.size():
		opts["procession_demo"] = args[d + 1]


## The floor's procession `n` (the last one when there are fewer), or null.
static func pick(site: SiteBuilder.Site, n: int) -> Procession:
	if site == null or site.processions.is_empty():
		return null
	return site.processions[clampi(n, 0, site.processions.size() - 1)]


## Where --to-procession puts the crew: a free cell NEAR_MIN-NEAR_MAX cells from the leader, nearest the way it walks next
## (so it walks toward the camera), in its line of sight. NO_CELL without one.
static func spot(map: HexMap, pr: Procession) -> Vector2i:
	var lead := pr.leader() if pr != null else null
	if lead == null or pr.route.is_empty():
		return HexMap.NO_CELL
	var here := lead.current_cell()
	var toward := pr.route[pr.leg] - lead.global_position
	toward.y = 0.0
	var aim := lead.global_position + (toward.normalized() if toward.length() > 0.1 else Vector3.FORWARD) * Hex.INNER * 2.0 * float(NEAR_MAX)
	var best := HexMap.NO_CELL
	var best_d := INF
	for c in Hex.range_cells(here, NEAR_MAX):
		if Hex.distance(c, here) < NEAR_MIN or not map.is_walkable_cell(c):
			continue
		var w := Hex.to_world(c, float(map.get_cell(c).level))
		if absf(w.y - lead.global_position.y) > 0.6 or not map.line_of_sight(w + Vector3.UP, lead.global_position + Vector3.UP):
			continue
		var d := GameWorld.flat_distance(w, aim)
		if d < best_d:
			best_d = d
			best = c
	return best


## Every TRACE_EVERY s for TRACE_FOR s: the file in order (kind, state, how far from its place) and whether it stands.
const TRACE_EVERY := 1.5
const TRACE_FOR := 15.0


static func _trace(game: Node, pr: Procession) -> void:
	var t := 0.0
	while t < TRACE_FOR and game.is_inside_tree() and is_instance_valid(pr):
		var rows: Array[String] = []
		var lead := pr.leader()
		for m in pr.members():
			var p := pr.place_of(m)
			rows.append("%s%s %s %.1f off @%.1f,%.1f" % [m.kind, "*" if m == lead else "", m.state_name(),
				GameWorld.flat_distance(m.global_position, p) if p != Vector3.INF else -1.0, m.global_position.x, m.global_position.z])
		print("[procession] t %.1f leg %d halted %s: %s" % [t, pr.leg, pr.halted, " | ".join(rows)])
		await game.get_tree().create_timer(TRACE_EVERY).timeout
		t += TRACE_EVERY


## The demo (see the header): the senses go off at once (walk, raise), the rest once --demo-after has passed. `game` is the
## running game (its player and allies).
static func demo(game: Node, site: SiteBuilder.Site, pr: Procession, stage: String) -> void:
	var opts: Dictionary = game.get("opts")
	if pr == null:
		return
	if stage == "walk" or stage == "raise":
		for m in site.monsters + site.acolytes:
			if is_instance_valid(m):
				m.aggro_range = 0.0
	for ally: Node in (game.get("allies") as Array):
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
	_trace(game, pr)
	await game.get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
	if not game.is_inside_tree():
		return
	match stage:
		"raise":
			for z in pr.zombies.slice(-2):
				if is_instance_valid(z) and not z.dead:
					z.die()
		"fight":
			var player := game.get("player") as Actor
			var lead := pr.leader()
			if player != null and lead != null:
				pr.engage(player.global_position, player)
				lead.aggro(player)

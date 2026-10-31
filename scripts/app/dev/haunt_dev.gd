class_name HauntDev
extends RefCounted
## The ghosts' dev flags (haunted-build-plan.md, "H5 as built"). GameDev calls it. A haunted contract's floors have ghosts in
## their hosts (--client heir | parish, --seed N, --floor 1-3); the log names every host ("haunts: ...").
##   --to-haunt [n]            solo: the crew starts NEAR_MIN-NEAR_MAX cells from possessed host n (default 0), in its sight
##   --focus haunt             the camera follows that host (and its ghost once it is thrown out)
##   --haunt-demo fight|break  after --demo-after seconds (1.0); the AI allies hold:
##        fight  the host comes at the player (it sees them: aggro)
##        break  the player breaks the host (a hit for its HP: the bill is the player's): its ghost pops out and flies off
## No keybinding.

const NEAR_MIN := 4
const NEAR_MAX := 6


static func parse(args: PackedStringArray, opts: Dictionary) -> void:
	var k := args.find("--to-haunt")
	if k >= 0:
		opts["to_haunt"] = int(args[k + 1]) if k + 1 < args.size() and args[k + 1].is_valid_int() else 0
	var d := args.find("--haunt-demo")
	if d >= 0 and d + 1 < args.size():
		opts["haunt_demo"] = args[d + 1]


## The floor's possessed host `n` (the last one when there are fewer), or null.
static func pick(site: SiteBuilder.Site, n: int) -> HauntHost:
	if site == null:
		return null
	var possessed: Array[HauntHost] = []
	for h in site.hosts:
		if h != null and is_instance_valid(h) and h.is_possessed():
			possessed.append(h)
	if possessed.is_empty():
		return null
	return possessed[clampi(n, 0, possessed.size() - 1)]


## Where --to-haunt puts the crew: a free cell NEAR_MIN-NEAR_MAX cells from the host, at its level, in its line of sight, beside
## it as the game camera sees it (across the screen, not in front of it or behind it, so neither hides the other), in front of
## the wall it stands at. NO_CELL without one.
const VIEW := Vector3(-0.7071, 0.0, -0.7071)   ## the game camera's look across the floor (its yaw, 45 degrees)


static func spot(map: HexMap, h: HauntHost) -> Vector2i:
	if h == null:
		return HexMap.NO_CELL
	var here := h.current_cell()
	var best := HexMap.NO_CELL
	var best_s := INF
	for c in Hex.range_cells(here, NEAR_MAX):
		if Hex.distance(c, here) < NEAR_MIN or not map.is_walkable_cell(c):
			continue
		var w := Hex.to_world(c, float(map.get_cell(c).level))
		if absf(w.y - h.global_position.y) > 0.6 or not map.line_of_sight(w + Vector3.UP, h.global_position + Vector3.UP):
			continue
		var to := w - h.global_position
		to.y = 0.0
		var dir := to.normalized()
		var s := absf(dir.dot(VIEW)) - 0.3 * dir.dot(h.facing)
		if s < best_s:
			best_s = s
			best = c
	return best


## The demo (see the header), once --demo-after has passed. `game` is the running game (its player and allies).
static func demo(game: Node, h: HauntHost, stage: String) -> void:
	var opts: Dictionary = game.get("opts")
	if h == null:
		return
	var player := game.get("player") as Actor
	var map := GameWorld.map
	# the allies hold a couple of steps behind the player (out of the host's way: the screenshots), the other monsters near it
	# stand still (only the host fights)
	var away := player.global_position - h.global_position if player != null else Vector3.BACK
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.BACK
	var side := Vector3(-away.z, 0.0, away.x)
	var k := 0
	for ally: Node in (game.get("allies") as Array):
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
		if player != null and map != null and ally is Actor:
			var p := player.global_position + away * 4.0 + side * (1.5 if k % 2 == 0 else -1.5)
			for c in GymSpawns.cells_near(map, p, 1):   # (the nearest free floor cell there)
				if GameWorld.flat_distance(Hex.to_world(c), h.global_position) > GameWorld.flat_distance(player.global_position, h.global_position) + 1.0:
					(ally as Actor).global_position = Hex.to_world(c, HauntPlanner.level_of(map, c))
					(ally as Actor).reset_physics_interpolation()
		k += 1
	for m in GameWorld.actors_in_radius(h.global_position, 14.0, GameWorld.TEAM_MONSTERS):
		if m != h and m is Monster and not (m is Wisp):
			m.set_physics_process(false)
	await game.get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
	if not game.is_inside_tree() or not is_instance_valid(h) or h.dead:
		return
	match stage:
		"fight":
			if player != null:
				h.aggro(player)
		"break":
			var w := h.ghost
			h.apply_damage(h.hp + 1.0, player)
			if w != null and is_instance_valid(w) and opts.get("focus", "") == "haunt":
				var rig: Variant = game.get("rig")
				if rig != null:
					rig.set("target", w)

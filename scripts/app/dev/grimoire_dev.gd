class_name GrimoireDev
extends RefCounted
## The grimoire's dev flags (haunted-build-plan.md, "H6 as built"). GameDev calls it. A haunted contract's last floor has its
## grimoire (--client heir | parish, --seed N, --floor 3); the log says where ("grimoire: in room:N, ... HP").
##   --to-grimoire                 solo: the crew starts NEAR cells from the grimoire, out of its wake range (it stays asleep)
##   --focus grimoire              the camera on it
##   --grimoire-demo hold|wake|burst|phase|shut|burn   after --demo-after seconds (1.0); the AI allies hold, the floor's
##                                 monsters stand still:
##        hold   nothing more: it sleeps (the crew stays out of its range)
##        wake   it wakes (the book flies open) and its bursts run as in play
##        burst  it wakes and a burst comes at once (the pages flare, the dead rise round it)
##        phase  it wakes, a burst lands, then a hit takes it to its last phase (the blast, the failing book)
##        shut   it wakes, then the player hits it shut (slammed shut: the eye dead, the lights out; the pay)
##        burn   it wakes, the player sets it alight, then the fire finishes it (burned: charred and smoking)
## No keybinding.

const NEAR := 9   ## cells from the grimoire (about 15 units): outside Hellgate.ACTIVATE_RANGE (12) with the allies round the player
const CLEAR := 3.5   ## the player this much beyond the wake range (the allies stand a couple of units off)


static func parse(args: PackedStringArray, opts: Dictionary) -> void:
	if args.has("--to-grimoire"):
		opts["to_grimoire"] = true
	var d := args.find("--grimoire-demo")
	if d >= 0 and d + 1 < args.size():
		opts["grimoire_demo"] = args[d + 1]


## Where --to-grimoire puts the crew: a free floor cell about NEAR from the grimoire, at its level, in its sight, as near
## the screen's bottom (the camera's side) as it can, so the altar is in the frame with the crew. NO_CELL without one.
static func spot(map: HexMap, g: Grimoire) -> Vector2i:
	if g == null:
		return HexMap.NO_CELL
	var here := g.current_cell()
	var best := HexMap.NO_CELL
	var best_s := INF
	for c in Hex.range_cells(here, NEAR + 4):
		var dc := Hex.distance(c, here)
		if dc < NEAR - 2 or not map.is_walkable_cell(c):
			continue
		var w := Hex.to_world(c, float(map.get_cell(c).level))
		if absf(w.y - g.global_position.y) > 0.6 or not map.line_of_sight(w + Vector3.UP, g.global_position + Vector3.UP * 1.5):
			continue
		if GameWorld.flat_distance(w, g.global_position) <= Hellgate.ACTIVATE_RANGE + CLEAR:
			continue
		var to := w - g.global_position
		to.y = 0.0
		var s := absf(float(dc - NEAR)) - 0.4 * to.normalized().dot(Vector3(0.7071, 0.0, 0.7071))
		if s < best_s:
			best_s = s
			best = c
	return best


## The demo (see the header), once --demo-after has passed. `game` is the running game.
static func demo(game: Node, g: Grimoire, stage: String) -> void:
	var opts: Dictionary = game.get("opts")
	if g == null:
		return
	var player := game.get("player") as Actor
	for ally: Node in (game.get("allies") as Array):
		var b := ally.get_node_or_null("AllyBrain")
		if b != null:
			b.set_physics_process(false)
	for m in GameWorld.actors_in_radius(g.global_position, 30.0, GameWorld.TEAM_MONSTERS):
		if m is Monster:
			m.set_physics_process(false)
	await game.get_tree().create_timer(float(opts.get("demo_after", 1.0))).timeout
	if not game.is_inside_tree() or not is_instance_valid(g) or g.dead or stage == "hold":
		return
	g.activate()
	match stage:
		"burst":
			g._next_burst_in = Hellgate.TELEGRAPH_TIME   # (the flare now, the burst a second later)
		"phase":
			g.spawn_burst_now()
			await game.get_tree().create_timer(1.5).timeout
			if is_instance_valid(g) and not g.dead:
				g.apply_damage(g.hp - g.max_hp * 0.3, player)
		"shut":
			await game.get_tree().create_timer(1.2).timeout
			if is_instance_valid(g) and not g.dead:
				g.apply_damage(g.hp + 1.0, player)
		"burn":
			await game.get_tree().create_timer(1.2).timeout
			if is_instance_valid(g) and not g.dead:
				Burning.ignite(g, player, Grimoire.FIRE_SECONDS)
				g.apply_damage(g.hp - 30.0, player)   # (the fire's last ticks finish it: burned)

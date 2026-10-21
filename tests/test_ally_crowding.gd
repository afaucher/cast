extends TestCase
## An AI ally never paces or shakes next to a hero that does not make room itself (AllyBrain, NO PACING; user playtest
## 2026-10-21: "Rebar on the host is vibrating violently"). In a crew the host runs the AI seats' AllyBrains, and another
## player's hero is a puppet there: it stands where its player put it and never steps aside. Parked near Rebar's formation
## slot it used to start a loop: personal space walked Rebar out past FOLLOW_SLACK, the slot called him straight back, and
## again, four 180-degree turns a second for as long as the player stood there. Flat maps, one process (the brain is the
## same on every machine; the crewmate here is a puppet as on the host, moved only by writing its position):
##   parked    a crewmate parked anywhere around the slot: the ally moves off at most once and then stands still, out of
##             the crewmate's personal space
##   walking   the leader and the crewmate walk back and forth together: the ally never reverses on consecutive frames
##   lane      a leader walking down a two-wide hall at the ally: it steps out of the lane and waits there, without stepping
##             back in and out again

const SEAT_ANGLE := 3.9    ## game.gd AI_SEATS[3]: the seat Rebar had in the playtest crew
const SEAT_HEXES := 3.3
const DT := 1.0 / 60.0

var root: Node3D


func _init() -> void:
	timeout_sec = 900.0   # (game seconds: about 550 of them, half a minute headless)


func setup() -> void:
	await _test_parked()
	await _test_walking()
	await _test_lane()
	finish()


func _world(m: HexMap) -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	GameWorld.begin(m, root, 7)


func _open_floor() -> HexMap:
	var m := HexMap.new()
	for c in Hex.range_cells(Vector2i.ZERO, 30):
		m.set_cell(c, 0)
	return m


func _hero(kit: String, cell: Vector2i) -> Hero:
	return HeroFactory.spawn_hero(cell, kit.capitalize(), Color.WHITE, "sword", null, kit)


## Another player's hero as the host holds it: a puppet (no brain, no controller, never pushed).
func _crewmate(at: Vector3) -> Hero:
	var h := _hero("gasket", Hex.from_world(at))
	Net.make_puppet(h)
	h.global_position = Vector3(at.x, h.global_position.y, at.z)
	return h


## Counts an actor's walk frame by frame: direction reversals, reversals on consecutive frames (the shake), the path.
class Track extends RefCounted:
	var a: Actor
	var prev := Vector3.INF
	var prev_d := Vector3.ZERO
	var last_rev := -100
	var frame := 0
	var reversals := 0
	var shakes := 0
	var path := 0.0

	func _init(actor: Actor) -> void:
		a = actor
		prev = actor.global_position

	func step() -> void:
		frame += 1
		var d := a.global_position - prev
		d.y = 0.0
		prev = a.global_position
		path += d.length()
		if d.length() > 0.005 and prev_d.length() > 0.005 and d.normalized().dot(prev_d.normalized()) < -0.5:
			reversals += 1
			if frame - last_rev <= 2:
				shakes += 1
			last_rev = frame
		if d.length() > 0.005:
			prev_d = d


## Rebar settled in his slot behind a standing leader; the crewmate parks at `off` from where he stands.
func _test_parked() -> void:
	var bad: Array[String] = []
	var crowded: Array[String] = []
	var n := 0
	for ox in [-3, -2, -1, 0, 1, 2, 3]:
		for oz in [-3, -2, -1, 0, 1, 2, 3]:
			_world(_open_floor())
			var leader := _hero("wick", Vector2i.ZERO)
			var rebar := _hero("rebar", Vector2i(-2, 1))
			HeroFactory.make_ally(rebar, leader, false, SEAT_ANGLE, SEAT_HEXES)
			await frames(60 * 2)
			var off := Vector3(ox, 0, oz) * 0.4
			var mate := _crewmate(rebar.global_position + off)
			var tr := Track.new(rebar)
			for i in 60 * 4:
				await get_tree().physics_frame
				tr.step()
			n += 1
			if tr.reversals > 1 or tr.path > 4.0:
				bad.append("(%.1f, %.1f): %d reversals, walked %.1f" % [off.x, off.z, tr.reversals, tr.path])
			var gap := GameWorld.flat_distance(rebar.global_position, mate.global_position)
			if gap < AllyBrain.PERSONAL_SPACE - 0.3:
				crowded.append("(%.1f, %.1f): %.2f" % [off.x, off.z, gap])
	print("parked: %d of %d spots paced" % [bad.size(), n])
	check(bad.is_empty(), "parked: a crewmate parked by the slot never sets the ally pacing (%d of %d spots: %s)" % [bad.size(), n, ", ".join(bad)])
	check(crowded.is_empty(), "parked: the ally ends out of the crewmate's personal space (%s)" % ", ".join(crowded))


## The leader and the crewmate walk +x and -x together (turning every 1.5 s), the crewmate near Rebar's slot.
func _test_walking() -> void:
	var bad: Array[String] = []
	var total := 0
	for ox in [-2, -1, 0, 1, 2]:
		for oz in [-2, -1, 0, 1, 2]:
			_world(_open_floor())
			var leader := _hero("wick", Vector2i.ZERO)
			var rebar := _hero("rebar", Vector2i(-2, 1))
			HeroFactory.make_ally(rebar, leader, false, SEAT_ANGLE, SEAT_HEXES)
			await frames(60 * 2)
			var off := Vector3(ox, 0, oz) * 0.4
			var mate := _crewmate(rebar.global_position + off)
			var tr := Track.new(rebar)
			for i in 60 * 6:
				var dir := Vector3.RIGHT if (i / 90) % 2 == 0 else Vector3.LEFT
				var before := leader.global_position
				leader.move(dir, DT)
				mate.global_position += leader.global_position - before   # (the snapshot moves a puppet)
				await get_tree().physics_frame
				tr.step()
			total += tr.reversals
			if tr.shakes > 0:
				bad.append("(%.1f, %.1f): %d shakes" % [off.x, off.z, tr.shakes])
	print("walking: %d shaking runs, %d reversals in all" % [bad.size(), total])
	check(bad.is_empty(), "walking: the ally never reverses on consecutive frames beside a walking crewmate (%s)" % ", ".join(bad))
	check(total <= 25 * 6, "walking: it turns with the crowd, not back and forth (%d reversals over 25 runs of 4 turns)" % total)


## A two-wide hall: the leader walks at the ally standing in its lane, then turns back.
func _test_lane() -> void:
	var worst := 0
	for start in [-9, -8, -7, -6, -5, -4]:
		var m := HexMap.new()
		for r in [0, 1]:
			for q in range(-20 - r, 20 - r):
				m.set_cell(Vector2i(q, r), 0)
		_world(m)
		var leader := _hero("wick", Vector2i(-12, 0))
		var rebar := _hero("rebar", Vector2i(start, 0))
		HeroFactory.make_ally(rebar, leader, false, SEAT_ANGLE, SEAT_HEXES)
		await frames(2)
		var tr := Track.new(rebar)
		for i in 60 * 6:
			leader.move(Vector3.RIGHT if i < 200 else Vector3.LEFT, DT)
			await get_tree().physics_frame
			tr.step()
		worst = maxi(worst, tr.shakes)
	print("lane: %d shakes at worst" % worst)
	check(worst == 0, "lane: stepping out of a walking leader's lane, the ally does not step back in and out again (%d shakes at worst)" % worst)

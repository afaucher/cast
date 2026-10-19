extends TestCase
## Office doors (OfficeDoor, DoorPlan, HexDoorModel; docs/design/exploration.md "Decisions: map information, fog and doors", 2026-10-19) on the row floor
## of test_room_fog with NARROW halls (one full lane, 3.0 wide): room A, a short hall, room B, a long hall, room C, a long
## hall, room D. Walking opens a door, E shuts it, a shut door blocks sight (monsters' and the fog's) and halves a sound's
## reach, a hero opening one is heard in the room behind (a monster opening one is not), monsters open it on their way
## through, a chasing brute smashes it (billed once); wide halls never get a door; the plan is seeded and keeps its share;
## all three looks block and open. Doors are host / solo only this round (OfficeDoor.NETWORKED is false): no net test yet.

const RowMap := preload("res://tests/test_room_fog.gd")

var map: HexMap
var world: Node3D
var doors: Array[OfficeDoor] = []
var dws: Array[Dictionary] = []


func setup() -> void:
	timeout_sec = 120.0
	map = RowMap.row_map(3)
	world = Node3D.new()
	add_child(world)
	GameWorld.begin(map, world, 5)
	CombatLog.enabled = false
	Ledger.begin_contract(50000)
	dws = Doorways.find(map)
	for dw in dws:
		doors.append(OfficeDoor.spawn(dw, "column", true))
	await frames(2)
	for d in doors:
		check(d != null and d.shut and not d.broken, "every doorway of the narrow row floor takes a door, shut")
	eq(map.blockers.size(), 6, "six shut doors: six sight blockers")
	_wide_never()
	_plan_rules()
	await _walk_opens()
	await _e_shuts()
	_sight_blocked()
	await _noise_muffled()
	await _open_is_heard()
	await _monster_opens()
	await _brute_smashes()
	await _styles()
	finish()


func _door(room: String, hall_cell: Vector2i) -> OfficeDoor:
	var sp := Doorways.spaces(map)
	var hall: String = sp["cell_space"][hall_cell]
	for i in dws.size():
		if dws[i]["room"] == room and dws[i]["hall"] == hall:
			return doors[i]
	return null


func _hero(cell: Vector2i) -> Hero:
	var h := HeroFactory.spawn_hero(cell, "Wick", Color(0.35, 0.8, 1.0), "bow", null, "wick")
	h.set_modifier("test_ward", 0.0, 9999.0)
	return h


func _grunt_at(p: Vector3) -> Monster:
	var m := MonsterFactory.spawn("grunt", Hex.from_world(p))
	m.global_position = Vector3(p.x, 0.0, p.z)
	m.set_spawn_facing(Vector3.BACK)
	return m


## Walk `a` toward `to` for up to `max_frames`, stopping when `done` says so.
func _walk(a: Actor, to: Vector3, max_frames: int, done: Callable) -> bool:
	for i in max_frames:
		if done.call():
			return true
		var d := to - a.global_position
		d.y = 0.0
		if d.length() > 0.1:
			a.move(d.normalized(), 1.0 / 60.0)
		await get_tree().physics_frame
	return done.call()


func _wait(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


func _clear(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()


# 0a. The user's rule: a wide hallway never has a door (only narrow ones, one full cell wide).
func _wide_never() -> void:
	var wide := Doorways.find(RowMap.row_map(4))
	for dw in wide:
		check(not DoorPlan.allowed(dw, null), "a wide hallway's doorway is never a door candidate (%d)" % int(dw["id"]))
		check(OfficeDoor.spawn(dw) == null, "... and no door can be put in it")
	eq(DoorPlan.choose(wide, null, 7).size(), 0, "a floor of wide hallways gets no doors")
	for dw in dws:
		check(DoorPlan.allowed(dw, null), "a narrow hallway's doorway may have one (%d)" % int(dw["id"]))


# 0b. The plan: the share, seeded, the dead ends, the start / elevator rooms, rooms with something to hide first.
func _plan_rules() -> void:
	var picked := DoorPlan.choose(dws, null, 11)
	eq(picked.size(), ceili(DoorPlan.DOOR_SHARE * dws.size()), "DOOR_SHARE of the allowed doorways get a door")
	eq(DoorPlan.choose(dws, null, 11), picked, "the same seed picks the same doorways")
	var plan := SitePlan.new()
	plan.start_room = "room:0"
	plan.exit_room = "room:3"
	plan.gates.append({"cell": RowMap.C, "origin": false, "room": "room:2"})
	var with_plan := DoorPlan.choose(dws, plan, 11)
	for id in with_plan:
		check(dws[id]["room"] != "room:0" and dws[id]["room"] != "room:3", "never in the start or elevator room")
	var c_doors := with_plan.filter(func(id: int) -> bool: return dws[id]["room"] == "room:2")
	eq(c_doors.size(), 2, "the hellgate's room gets its doors first")
	var dead := dws[0].duplicate()
	dead["dead_end"] = true
	check(not DoorPlan.allowed(dead, null), "never on a dead-end corridor")
	var gen_ok := true
	var counts: Array[String] = []
	for sd in [1, 2, 3, 7, 11]:
		var run := ContractRun.make("prepper", sd, 0.5)
		var gm := DungeonGen.for_run(run, 1)
		var gp := SiteBuilder.plan(gm, run, 1, ContractParts.prop_catalog(run.site_type))
		var gd := Doorways.find(gm)
		var chosen := DoorPlan.choose(gd, gp, run.floor_seed(1))
		var allowed := gd.filter(func(dw: Dictionary) -> bool: return DoorPlan.allowed(dw, gp)).size()
		var narrow := gd.filter(func(dw: Dictionary) -> bool: return bool(dw["narrow"])).size()
		for id in chosen:
			gen_ok = gen_ok and DoorPlan.allowed(gd[id], gp)
		gen_ok = gen_ok and chosen == DoorPlan.choose(Doorways.find(DungeonGen.for_run(run, 1)), gp, run.floor_seed(1))
		counts.append("seed %d: %d doorways, %d narrow, %d allowed, %d doors" % [sd, gd.size(), narrow, allowed, chosen.size()])
	check(gen_ok, "on generated floors every door is allowed and the choice repeats")
	print("door plan: " + "; ".join(counts))


# 1. A hero walking into a shut door opens it at once, and walks through.
func _walk_opens() -> void:
	var d := _door("room:0", Vector2i(8, 0))
	var h := _hero(Vector2i(3, 0))
	await frames(2)
	var through := d.center() + d.axis * 2.5
	var seen := {"opened": -1.0, "gap": -1.0}   # (a lambda captures locals by value: keep its notes in a Dictionary)
	var start := GameWorld.time
	var ok := await _walk(h, through, 300, func() -> bool:
		if float(seen["opened"]) < 0.0 and not d.shut:
			seen["opened"] = GameWorld.time
			seen["gap"] = absf(d.local_flat(h.global_position).y) - d.half - h.radius
		return d.local_flat(h.global_position).y > 2.0)
	check(ok, "the hero walked through the doorway")
	check(not d.shut, "walking into the door opened it")
	check(float(seen["opened"]) > start, "it opened during the walk")
	check(float(seen["gap"]) <= OfficeDoor.TOUCH + 0.1, "... when the hero reached it (%.2f from the door)" % float(seen["gap"]))
	check(not map.blockers.has("door:%d" % d.doorway_id), "an open door blocks no sight")
	await frames(30)
	check(d.open_k > 0.99, "it finished opening (sunk into the floor)")
	check(d.model.open_k > 0.99, "the model shows it open")
	_clear([h])
	await frames(2)


# 2. E shuts an open door; not with someone standing in it; E opens a shut one.
func _e_shuts() -> void:
	var d := _door("room:0", Vector2i(8, 0))
	var h := _hero(Vector2i(3, 0))
	var other := _hero(Vector2i(3, 1))
	h.global_position = d.center() - d.axis * 1.8
	await frames(2)
	eq(OfficeDoor.interact_target(h), d, "E's target from the room side is the door")
	eq(d.use_verb(), "Shut door", "the prompt says Shut door")
	other.global_position = d.center()
	check(d.blocked(), "a hero standing in the doorway is in its way")
	check(not d.use(h), "E does nothing while someone stands in it")
	check(not d.shut, "... the door stays open")
	other.global_position = Hex.to_world(Vector2i(2, 2))
	await frames(1)
	check(d.use(h), "E shuts it")
	check(d.shut, "shut")
	check(map.blockers.has("door:%d" % d.doorway_id), "a shut door is a sight blocker")
	eq(d.use_verb(), "Open door", "... and the prompt now opens it")
	await frames(40)
	check(d.open_k < 0.01, "it rose shut")
	check(d.use(h), "E opens a shut door")
	check(not d.shut, "open again")
	check(d.use(h), "and E shuts it once more")
	_clear([h, other])
	await frames(2)


# 3. Sight: monsters' line of sight and the room fog stop at a shut door.
func _sight_blocked() -> void:
	var d := _door("room:0", Vector2i(8, 0))
	check(d.shut, "(door A shut from the last step)")
	var room_side := d.center() - d.axis * 3.0 + Vector3.UP * 0.9
	var hall_side := d.center() + d.axis * 3.0 + Vector3.UP * 0.9
	check(not map.line_of_sight(room_side, hall_side), "a shut door blocks a monster's line of sight")
	check(map.line_of_sight(room_side, hall_side, 0.25, false), "(the walls alone would let it through)")
	check(map.crosses_blocker(room_side, hall_side), "the line crosses the door")
	var fog := RoomFog.build(map)
	fog.set_shut(d.doorway_id, true)
	var hero_at := d.center() - d.axis * 2.5
	fog.update([hero_at])
	var hall := fog.space_at(d.center() + d.axis * 3.0)
	eq(fog.state_of(hall), RoomFog.NEXT, "fog: the hall behind a shut door is not in view (layout only)")
	d.request(false, null)
	check(map.line_of_sight(room_side, hall_side), "opened: the line of sight is clear")
	fog.set_shut(d.doorway_id, d.shut)
	fog.update([hero_at])
	eq(fog.state_of(hall), RoomFog.IN_VIEW, "fog: through the open door the hall is in view")
	d.request(true, null)


# 4. Noise: a shut door halves how far a sound carries through it.
func _noise_muffled() -> void:
	var d := _door("room:0", Vector2i(8, 0))
	check(d.shut, "(door A shut)")
	var src := d.center() - d.axis * 1.5
	var radius := 10.0
	var far := _grunt_at(src + d.axis * 7.0)      # 7 from the sound: within 10, beyond 5
	var close := _grunt_at(src + d.axis * 4.0)    # 4: within 5
	await frames(2)
	eq(MonsterSenses.noise(src, radius, "test"), 1, "through the shut door only the grunt within half the radius hears it")
	check(close.state == Monster.State.SUSPICIOUS, "the near grunt turns toward the sound")
	check(far.state == Monster.State.IDLE, "the far one does not")
	_clear([far, close])
	await frames(2)
	d.request(false, null)
	var far2 := _grunt_at(src + d.axis * 7.0)
	await frames(2)
	eq(MonsterSenses.noise(src, radius, "test"), 1, "door open: the far grunt hears it too")
	check(far2.state == Monster.State.SUSPICIOUS, "... and turns")
	_clear([far2])
	d.request(true, null)
	await frames(2)


# 5. A hero opening a door is heard in the room behind it; far monsters don't react; a monster opening one is not heard.
func _open_is_heard() -> void:
	var d := _door("room:1", Vector2i(8, 0))      # room B's door onto the short hall: the hero comes from the hall
	check(d.shut, "(door B-H0 shut)")
	var near_g := _grunt_at(d.center() - d.axis * 4.5)       # in room B, 4.5 past the door
	var far_g := _grunt_at(Hex.to_world(Vector2i(19, 2)) + Vector3(0.0, 0.0, 0.0))
	check(GameWorld.flat_distance(far_g.global_position, d.center()) > OfficeDoor.OPEN_NOISE + 1.0, "(the far grunt is out of earshot)")
	var h := _hero(Vector2i(8, 0))
	h.global_position = d.center() + d.axis * 1.8
	await frames(2)
	check(near_g.state == Monster.State.IDLE and far_g.state == Monster.State.IDLE, "(both idle before)")
	check(d.use(h), "the hero opens the door")
	check(near_g.state == Monster.State.SUSPICIOUS or near_g.state == Monster.State.ALERT, "a monster in the room behind hears the door and turns to it")
	eq(far_g.state, Monster.State.IDLE, "one far across the room does not")
	_clear([near_g, far_g, h])
	await frames(2)
	# a monster opening a door makes no noise for the crew
	d.request(true, null)
	var opener := _grunt_at(d.center() - d.axis * 3.0)             # in room B, going for a hero in the hall
	var listener := _grunt_at(d.center() - d.axis * 5.5 + Vector3(0.0, 0.0, 1.7))
	listener.set_spawn_facing(-d.axis)                               # (its back to the door)
	var target := _hero(Vector2i(8, 0))
	target.global_position = d.center() + d.axis * 3.5
	opener.alert_radius = 0.0                                        # (no pack call: only the door could wake the listener)
	await frames(2)
	opener.aggro(target)
	var ok := await _wait(func() -> bool: return not d.shut, 60 * 6)
	check(ok, "(the grunt opened the door)")
	check(listener.state == Monster.State.IDLE, "a monster opening a door makes no noise for the crew")
	_clear([opener, listener, target])
	await frames(2)


# 6. A monster chasing through a shut door stops, opens it and walks on (pathing needs no change).
func _monster_opens() -> void:
	var d := _door("room:1", Vector2i(31, 0))     # B's door onto the long hall
	check(d.shut, "(door B-H1 shut)")
	var h := _hero(Vector2i(13, 1))
	var g := _grunt_at(d.center() + d.axis * 5.0)
	await frames(2)
	g.aggro(h)
	var seen := {"held": -1.0, "opened": -1.0}
	var ok := await _wait(func() -> bool:
		if float(seen["held"]) < 0.0 and g.is_rooted():
			seen["held"] = GameWorld.time
		if float(seen["opened"]) < 0.0 and not d.shut:
			seen["opened"] = GameWorld.time
		return d.local_flat(g.global_position).y < -1.5, 60 * 10)
	var held_at := float(seen["held"])
	var opened_at := float(seen["opened"])
	check(held_at > 0.0, "the grunt stopped at the shut door")
	check(opened_at > 0.0 and opened_at - held_at >= OfficeDoor.MONSTER_DELAY - 0.05, "it opened the door after its short delay (%.2f s)" % (opened_at - held_at))
	check(ok, "and came through into the room")
	_clear([h, g])
	await frames(2)


# 7. A chasing brute smashes a shut door: one slam, the door breaks, one Ledger line, a loud noise, and it walks on.
func _brute_smashes() -> void:
	var d := _door("room:2", Vector2i(31, 0))     # C's door onto the long hall
	check(d.shut, "(door C-H1 shut)")
	var lines_before := Ledger.lines.size()
	var h := _hero(Vector2i(44, 1))
	var br := MonsterFactory.spawn("brute", Hex.from_world(d.center() + d.axis * 5.0))
	var listener := _grunt_at(Hex.to_world(Vector2i(48, -2)))   # in room C, ~11 from the door: hears a smash, not an open
	await frames(2)
	br.aggro(h)
	var seen := {"tel": 0.0}
	var ok := await _wait(func() -> bool:
		seen["tel"] = maxf(float(seen["tel"]), float(br.get("_telegraph")))
		return d.broken, 60 * 10)
	check(ok, "the brute smashed the door")
	check(float(seen["tel"]) > 0.9, "with its slam's wind-up first (the red ring)")
	check(not d.shut and not map.blockers.has("door:%d" % d.doorway_id), "a smashed door blocks nothing")
	check(d.model.broken, "the model shows the rubble")
	check(listener.state != Monster.State.IDLE, "a smash is loud: a monster across the room hears it")
	var door_lines := Ledger.lines.slice(lines_before).filter(func(l: Dictionary) -> bool: return l["label"] == OfficeDoor.LABEL)
	eq(door_lines.size(), 1, "one Ledger line for the door")
	if door_lines.size() == 1:
		eq(int(door_lines[0]["amount"]), OfficeDoor.PRICE, "at the door's price")
		eq(str(door_lines[0]["kind"]), "damage", "as property damage")
		eq(str(door_lines[0]["who"]), "demons", "on the demons' account")
	d.smash(br)
	await frames(90)
	door_lines = Ledger.lines.slice(lines_before).filter(func(l: Dictionary) -> bool: return l["label"] == OfficeDoor.LABEL)
	eq(door_lines.size(), 1, "billed once: a second smash or more time adds nothing")
	check(OfficeDoor.interact_target(h) != d, "a broken door is not E's target")
	var ok2 := await _wait(func() -> bool: return d.local_flat(br.global_position).y < -0.5, 60 * 6)
	check(ok2, "the brute walks on through the broken doorway")
	_clear([h, br, listener])
	await frames(2)


# 8. The three looks: each blocks sight shut, clears it open, and breaks.
func _styles() -> void:
	for pair: Array in [["edge", 4], ["iris", 5]]:
		var i: int = pair[1]
		doors[i].queue_free()
		await frames(1)
		var d := OfficeDoor.spawn(dws[i], str(pair[0]), true)
		doors[i] = d
		await frames(2)
		var room_side := d.center() - d.axis * 3.0 + Vector3.UP * 0.9
		var hall_side := d.center() + d.axis * 3.0 + Vector3.UP * 0.9
		check(not map.line_of_sight(room_side, hall_side), "%s: shut, it blocks sight" % pair[0])
		check(d.use(_probe(d)), "%s: E opens it" % pair[0])
		await frames(30)
		check(map.line_of_sight(room_side, hall_side), "%s: open, sight is clear" % pair[0])
		check(d.model.open_k > 0.99, "%s: the model is open" % pair[0])
		d.request(true, null)
		await frames(40)
		check(d.model.open_k < 0.01, "%s: shut again" % pair[0])
		d.smash(null)
		check(d.model.broken and map.line_of_sight(room_side, hall_side), "%s: smashed, it blocks nothing" % pair[0])
	var iris := doors[5]
	check(map.solids.size() >= 2, "the iris's fixed jambs stop bodies (solids)")
	check(iris.style == "iris", "(iris)")


var _probes: Array[Hero] = []


func _probe(d: OfficeDoor) -> Hero:
	var h := _hero(Vector2i(0, 3))
	h.global_position = d.center() - d.axis * 1.8
	_probes.append(h)
	return h

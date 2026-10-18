extends MonsterTestBase
## M1 "done when" (networking-build-plan.md), single process: what the host owns is a non-acting COPY on a client.
## Net.make_copy / NetFloor.freeze_copies turn a seed-built monster, employee, hellgate, priced prop and mail
## package into a frozen standing copy: Net.simulates() is false for it, it runs no AI, takes no damage and no shove,
## and over 120 physics frames none of its PRIVATE or OWNER fields change. The same floor left alone does change
## (a control run), so the test would notice if the copies ran.

const SEED := 5
const FRAMES := 120

var _site: SiteBuilder.Site = null
var _hero: Actor = null


func setup() -> void:
	timeout_sec = 120.0
	Monster.use_proto_visuals = true
	check(Net.simulates(self) and not Net.is_copy(self), "offline, everything is simulated here")
	check(not Net.crewed(), "offline is not a crew")
	await _control_run()
	await _copy_run()
	Monster.use_proto_visuals = false
	finish()


## A real generated floor with its site, one hero standing beside the first monster so the pack wakes up.
func _build() -> void:
	var run := ContractBoard.run_for_seed(SEED)
	var map := DungeonGen.generate(run.floor_seed(1))
	if world != null:
		world.free()
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	GameWorld.begin(map, world, run.floor_seed(1))
	_site = SiteBuilder.build(map, run, 1)
	_hero = Actor.new()
	_hero.team = GameWorld.TEAM_HEROES
	_hero.max_hp = 100000.0
	_hero.display_name = "TestHero"
	var m: Monster = _site.monsters[0]
	GameWorld.spawn(_hero, m.global_position + Vector3(1.6, 0.0, 0.0))


func _watched() -> Array[Actor]:
	var out: Array[Actor] = []
	for a in _site.monsters:
		out.append(a)
	out.append_array(_site.gates)
	out.append_array(_site.employees)
	out.append_array(_site.props)
	out.append_array(_site.packages)
	return out


## Every PRIVATE and OWNER field of every watched actor, plus where it stands, as text.
func _snapshot(list: Array[Actor]) -> Array[String]:
	var out: Array[String] = []
	for a in list:
		var parts: PackedStringArray = []
		parts.append("pos %s" % str(a.global_position))
		var fields: Dictionary = a.net_fields()
		var names: Array = fields.keys()
		names.sort()
		for f: String in names:
			if int(fields[f]) == Net.PRIVATE or int(fields[f]) == Net.OWNER:
				var v: Variant = a.get(f)
				parts.append("%s=%s" % [f, str(v.get_instance_id()) if v is Object and v != null else var_to_str(v)])
		out.append("%s: %s" % [a.display_name, "; ".join(parts)])
	return out


func _changed(a: Array[String], b: Array[String]) -> int:
	var n := 0
	for i in a.size():
		if a[i] != b[i]:
			n += 1
	return n


func _control_run() -> void:
	_build()
	var list := _watched()
	check(list.size() > 30, "the floor has plenty to watch (%d actors)" % list.size())
	var before := _snapshot(list)
	var moved_before: Array = list.filter(func(a: Actor) -> bool: return a is Monster).map(func(a: Actor) -> Vector3: return a.global_position)
	await frames(FRAMES)
	var after := _snapshot(list)
	var changed := _changed(before, after)
	var moved_after: Array = list.filter(func(a: Actor) -> bool: return a is Monster).map(func(a: Actor) -> Vector3: return a.global_position)
	check(changed > 3, "control: left alone, a floor's actors DO change over %d frames (%d did)" % [FRAMES, changed])
	check(moved_before != moved_after, "control: monsters beside a hero move")


func _copy_run() -> void:
	_build()
	var list := _watched()
	var n := NetFloor.freeze_copies(world, [_hero])
	check(n >= list.size(), "freeze_copies turned %d things into copies" % n)
	check(not Net.is_copy(_hero) and Net.simulates(_hero), "the kept hero is still simulated")
	for a in list:
		check(Net.is_copy(a) and not Net.simulates(a), "%s is a copy" % a.display_name)
		check(not a.is_physics_processing(), "%s runs no AI" % a.display_name)
	var before := _snapshot(list)
	var hp_before: Array = list.map(func(a: Actor) -> float: return a.hp)
	# Hits and shoves from this machine's hero do nothing to a copy.
	for a in list:
		eq(a.apply_damage(9999.0, _hero), 0.0, "%s takes no damage" % a.display_name)
		a.shove(Vector3.RIGHT, 3.0, _hero)
		a.die()
		check(not a.dead and not a.is_shoved(), "%s neither dies nor slides" % a.display_name)
	await frames(FRAMES)
	var after := _snapshot(list)
	eq(_changed(before, after), 0, "over %d frames no PRIVATE or OWNER field and no position of any copy changed" % FRAMES)
	eq(list.map(func(a: Actor) -> float: return a.hp), hp_before, "no copy lost a point of HP")
	check(_hero.apply_damage(1.0, _site.monsters[0]) > 0.0, "the kept hero still takes damage")

extends TestCase
## The monster under a hellgate room (HellgateBeast, the "abyss" look): SiteBuilder.spawn gives every gate one, in the
## world, built from the floor alone (the same on every machine, no GameWorld.rng drawn), cheap enough for a floor.
## Its gate is hit: the limbs flail (more under sustained fire), then settle; at low HP they writhe. Its gate closes: the
## limbs retract down their own paths (EXIT_STYLE) and the beast hides once its exit time is over. A gate already closed
## before the beast's first frame (a late joiner applies the snapshot while the world is frozen) means it is never shown.

const SEED := 7
const FLOOR_TRIS := 40000        ## every beast on a floor together
const FLOOR_MS := 900.0          ## building them all, clearance checks included (headless; ~150-400 ms on the dev PC)


func setup() -> void:
	var run := ContractRun.make("guru", SEED, 0.8)
	var map := DungeonGen.for_run(run, 2)
	var plan := SiteBuilder.plan(map, run, 2, PricedProp.catalog(run.site_type))
	var world := Node3D.new()
	add_child(world)
	GameWorld.begin(map, world, run.floor_seed(2))
	HellgateBeast.reset_build_clock()
	var site := SiteBuilder.spawn(map, run, plan)
	check(site.gates.size() >= 2, "the floor has gates (%d)" % site.gates.size())
	eq(site.beasts.size(), site.gates.size(), "every gate has its beast")
	var tris := 0
	for b: Node3D in site.beasts:
		var beast := b as HellgateBeast
		check(beast.get_parent() == GameWorld.root, "%s lives in the world (it freezes with it)" % beast.name)
		check(beast.is_in_group(HellgateBeast.GROUP), "... is in the beasts group")
		check(int(beast.stats["limbs"]) >= 2, "... has its tentacles (%d)" % int(beast.stats["limbs"]))
		eq(beast.style, "abyss", "... in the chosen look")
		eq(beast.exit_style, HellgateBeast.EXIT_STYLE, "... leaving the chosen way (%s)" % beast.exit_style)
		tris += int(beast.stats["tris"])
	check(tris < FLOOR_TRIS, "the floor's beasts stay cheap (%d tris)" % tris)
	check(HellgateBeast.build_usec / 1000.0 < FLOOR_MS, "and quick enough to build (%.0f ms)" % (HellgateBeast.build_usec / 1000.0))
	print("[beast] floor 2: %d gates, %d tris, %.1f ms" % [site.gates.size(), tris, HellgateBeast.build_usec / 1000.0])
	eq(HellgateBeast.EXIT_STYLE, "retract", "the default exit retracts down the limbs' own paths (A)")

	# The same floor builds the same beast (every co-op machine builds its own), without touching the gameplay dice. (A
	# second build of a gate's beast keeps clear of the first one's limbs, so it is compared on a fresh floor registry.)
	var g0 := site.gates[0]
	var first := site.beasts[0] as HellgateBeast
	var rng_before := GameWorld.rng.state
	var map2 := DungeonGen.for_run(run, 2)
	var plan2 := SiteBuilder.plan(map2, run, 2, PricedProp.catalog(run.site_type))
	var again := HellgateBeast.for_gate(g0, map2, plan2, run.floor_seed(2))
	eq(str(again.stats), str(first.stats), "a second build of the same gate's beast is the same (%s)" % str(first.stats))
	eq(_mesh_sig(again), _mesh_sig(first), "... vertex for vertex")
	again.free()
	eq(GameWorld.rng.state, rng_before, "building the beasts drew nothing from GameWorld.rng")

	# A late joiner: the gate is closed before the beast's first frame (the snapshot lands while the world is frozen).
	var late := site.gates[1] as Hellgate
	var late_beast := site.beasts[1] as HellgateBeast
	late.die()
	await frames(2)
	eq(late_beast.state(), "gone", "a gate already closed when the floor starts: its beast is never shown")
	check(not late_beast.visible, "... hidden")

	# Hurt: the gate's HP drops (the replicated value on a client): the limbs flinch and flail, then settle.
	var gate := site.gates[0] as Hellgate
	var beast := site.beasts[0] as HellgateBeast
	eq(beast.state(), "out", "an open gate's beast is out")
	near(beast._t, gate.model._t, 0.0001, "it beats on the gate core's clock")
	near(beast.flail(), 0.0, 0.0001, "an unhurt gate's beast is calm")
	gate.apply_damage(gate.max_hp * 0.04, null)
	await frames(2)
	var one := beast.flail()
	check(one > 0.4, "a hit: its limbs flail (%.2f)" % one)
	for i in 6:
		gate.apply_damage(gate.max_hp * 0.02, null)
		await frames(6)
	check(beast.flail() > one, "sustained fire: the flail stacks (%.2f > %.2f)" % [beast.flail(), one])
	check(beast.flail() <= HellgateBeast.HURT_CAP, "... up to a cap")
	await frames(240)
	near(beast.flail(), 0.0, 0.0001, "and settles a few seconds later")
	near(beast._writhe, 0.0, 0.05, "a gate still above half HP: no writhing")
	gate.apply_damage(gate.hp - gate.max_hp * 0.1, null)
	await frames(150)
	check(not gate.dead, "(the gate is at 10 % HP)")
	check(beast._writhe > 0.8, "at low HP the limbs writhe all the time (%.2f)" % beast._writhe)

	# The gate closes: every limb retracts down its own path, then the beast hides.
	gate.die()
	await frames(3)
	eq(beast.state(), "leaving", "the gate closed: its beast is leaving")
	check(beast.visible, "... still shown while its limbs withdraw")
	var exit_s := beast.exit_duration()
	check(exit_s > 1.0 and exit_s < 4.0, "the exit takes %.1f s" % exit_s)
	await frames(int(exit_s * 60.0) + 10)
	eq(beast.state(), "gone", "and is gone once its exit is over")
	check(not beast.visible, "... hidden")
	if site.gates.size() > 2:
		eq((site.beasts[2] as HellgateBeast).state(), "out", "the other gates' beasts are still out")
	GameWorld.end()
	finish()


static func _mesh_sig(b: HellgateBeast) -> String:
	for c in b.get_children():
		if c is MeshInstance3D:
			var v: PackedVector3Array = (c as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			return "%d %s %s" % [v.size(), str(v[0]), str(v[v.size() / 2])]
	return ""

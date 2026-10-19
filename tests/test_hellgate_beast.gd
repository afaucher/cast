extends TestCase
## The monster under a hellgate room (HellgateBeast, the "abyss" look): SiteBuilder.spawn gives every gate one, in the
## world, built from the floor alone (the same on every machine, no GameWorld.rng drawn), cheap enough for a floor; it
## sinks away when its gate closes, and a gate already closed before the beast's first frame (a late joiner applies the
## snapshot while the world is frozen) means it is never shown.

const SEED := 7
const FLOOR_TRIS := 40000        ## every beast on a floor together
const FLOOR_MS := 400.0          ## building them all (headless; about 100-150 ms on the dev PC)


func setup() -> void:
	var run := ContractRun.make("guru", SEED, 0.8)
	var map := DungeonGen.for_run(run, 2)
	var plan := SiteBuilder.plan(map, run, 2, ContractParts.prop_catalog(run.site_type))
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
		check(int(beast.stats["limbs"]) >= 3, "... has its tentacles (%d)" % int(beast.stats["limbs"]))
		eq(beast.style, "abyss", "... in the chosen look")
		tris += int(beast.stats["tris"])
	check(tris < FLOOR_TRIS, "the floor's beasts stay cheap (%d tris)" % tris)
	check(HellgateBeast.build_usec / 1000.0 < FLOOR_MS, "and quick to build (%.0f ms)" % (HellgateBeast.build_usec / 1000.0))
	print("[beast] floor 2: %d gates, %d tris, %.1f ms" % [site.gates.size(), tris, HellgateBeast.build_usec / 1000.0])

	# The same floor builds the same beast (every co-op machine builds its own), without touching the gameplay dice.
	var g0 := site.gates[0]
	var rng_before := GameWorld.rng.state
	var again := HellgateBeast.for_gate(g0, map, plan, run.floor_seed(2))
	var first := site.beasts[0] as HellgateBeast
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

	# In play: the gate closes, the beast sinks away and hides.
	var gate := site.gates[0] as Hellgate
	var beast := site.beasts[0] as HellgateBeast
	eq(beast.state(), "out", "an open gate's beast is out")
	near(beast._t, gate.model._t, 0.0001, "it beats on the gate core's clock")
	gate.die()
	await frames(3)
	eq(beast.state(), "sinking", "the gate closed: its beast sinks")
	await frames(int(HellgateBeast.SINK_TIME * 60.0) + 10)
	eq(beast.state(), "gone", "and is gone %.1f s later" % HellgateBeast.SINK_TIME)
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

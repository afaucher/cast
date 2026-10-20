extends TestCase
## MonsterDefs (docs/design/refactor-plan.md, H3): every monster kind's row is whole, and the tables derived from it keep
## the exact values and orders the game had before (the floor plan, the gate rolls and the drops depend on them).


func setup() -> void:
	# Every row: a loadable Monster script; a pack kind has a model and a triangle budget.
	for k: String in MonsterDefs.DEFS:
		var s: Script = MonsterDefs.scripts()[k]
		check(s != null, "%s: its script loads" % k)
		if MonsterDefs.row(k).has("pack"):
			check(MonsterDefs.model_script(k) != null and int(MonsterDefs.row(k).get("tris", 0)) > 0, "%s: a pack kind has a model and a budget" % k)
	# The derived tables, in the order the rolls walk them.
	eq(MonsterFactory.KINDS, ["grunt", "archer", "brute", "swarmer"] as Array[String], "the pack kinds, in the pack roll's order")
	eq(MonsterFactory.COSTS, {"grunt": 2, "archer": 3, "brute": 6, "swarmer": 4}, "pack costs")
	eq(MonsterFactory.WEIGHTS, {"grunt": 5.0, "archer": 3.0, "brute": 1.5, "swarmer": 2.5}, "pack weights")
	eq(MonsterFactory.SCRIPTS.keys(), ["grunt", "archer", "brute", "swarmer", "goblin"], "the factory builds the kinds with a model")
	eq(MonsterModels.KINDS, ["grunt", "archer", "brute", "swarmer", "goblin"] as Array[String], "the modelled kinds")
	eq(MonsterDefs.is_swarm("swarmer"), true, "imps come in a swarm")
	eq(MonsterDefs.is_swarm("grunt"), false, "a grunt doesn't")
	eq(ClientArchetype.PEST_NAMES, {"grunt": "skeletons", "archer": "archers", "brute": "brutes", "swarmer": "imps", "everything": "everything"}, "pest names")
	eq(SpellComponents.DROPS.keys(), ["grunt", "archer", "brute", "swarmer"], "the kinds that drop components")
	for k: String in SpellComponents.DROPS:
		for e: Dictionary in SpellComponents.DROPS[k]:
			for sp: String in e["spells"]:
				check(SpellBook.SPELLS.has(sp), "%s drops a real spell (%s)" % [k, sp])
	eq(Shark.PRICES, {"regular": 8400, "laser": 12600, "imp": 12600}, "shark bills")
	eq(Shark.NAMES, {"regular": "Shark", "laser": "Laser shark", "imp": "Laser shark"}, "shark bill names")
	# The gate weights: the same numbers as the formulas they replaced, rolled in the same order.
	for p in [0.0, 0.3, 0.75, 1.0, 1.6]:
		for phase in [0, 1, 2]:
			var w := Hellgate.kind_weights(p, phase)
			eq(w.keys(), ["swarmer", "grunt", "archer", "brute"], "the gate roll's order")
			eq(float(w["swarmer"]), maxf(0.5, 5.0 + -1.0 * p), "swarmer weight at p %.2f" % p)
			eq(float(w["grunt"]), 4.0, "grunt weight")
			eq(float(w["archer"]), 2.0 + 1.0 * p, "archer weight at p %.2f" % p)
			eq(float(w["brute"]), 0.5 + 1.5 * p + 0.8 * float(phase), "brute weight at p %.2f, phase %d" % [p, phase])
	# The one composer: the pest bias is the only difference from an unbiased pack.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	for s in 20:
		a.seed = s
		b.seed = s
		eq(MonsterFactory.compose(14, a, {}), SiteBuilder.biased_composition(14, b, "everything"), "no bias, no difference (seed %d)" % s)
	finish()

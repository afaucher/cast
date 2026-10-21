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
	eq(MonsterFactory.KINDS, ["grunt", "archer", "brute", "swarmer", "pavise", "water_boy"] as Array[String], "the pack kinds, in the pack roll's order")
	eq(MonsterFactory.COSTS, {"grunt": 2, "archer": 3, "brute": 6, "swarmer": 4, "pavise": 4, "water_boy": 3}, "pack costs")
	eq(MonsterFactory.WEIGHTS, {"grunt": 5.0, "archer": 3.0, "brute": 1.5, "swarmer": 2.5, "pavise": 0.75, "water_boy": 2.0}, "pack weights")
	eq(MonsterFactory.SCRIPTS.keys(), ["grunt", "archer", "brute", "swarmer", "goblin", "pavise", "water_boy", "goo_imp"], "the factory builds the kinds with a model")
	eq(MonsterModels.KINDS, ["grunt", "archer", "brute", "swarmer", "goblin", "pavise", "water_boy", "goo_imp"] as Array[String], "the modelled kinds")
	eq(MonsterDefs.is_swarm("swarmer"), true, "imps come in a swarm")
	eq(MonsterDefs.is_swarm("grunt"), false, "a grunt doesn't")
	eq(ClientArchetype.PEST_NAMES, {"grunt": "skeletons", "archer": "archers", "brute": "brutes", "swarmer": "imps", "everything": "everything"}, "pest names")
	eq(SpellComponents.DROPS.keys(), ["grunt", "archer", "brute", "swarmer", "pavise", "water_boy", "goo_imp"], "the kinds that drop components")
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
	# The new kinds' gates (combat-proposals.md §2 / §3, "As built"): none on floor 1; from floor 2 at most one pavise and one
	# water boy a pack, and a water boy only after 3 other monsters (a swarm counts its SWARM_MIN imps).
	var seen := {}
	for s in 400:
		a.seed = s
		var f1 := MonsterFactory.compose(14, a, {}, 1)
		check(not f1.has("pavise") and not f1.has("water_boy"), "floor 1 deals neither new kind (seed %d)" % s)
		for fl in [2, 3]:
			a.seed = s
			var pk := MonsterFactory.compose(10 + 4 * fl, a, {}, fl)
			check(pk.count("pavise") <= 1 and pk.count("water_boy") <= 1, "at most one of each a pack (seed %d, floor %d)" % [s, fl])
			var at := pk.find("water_boy")
			if at >= 0:
				var before := 0
				for k in pk.slice(0, at):
					before += MonsterFactory.SWARM_MIN if MonsterDefs.is_swarm(k) else 1
				check(before >= 3, "a water boy comes after 3 others (seed %d, floor %d: %s)" % [s, fl, pk])
			for k in pk:
				seen[k] = true
	check(seen.has("pavise") and seen.has("water_boy"), "floors 2-3 deal both new kinds")
	# Habitats (goo-imp.md, "As built"): a habitat kind is never in a floor's pack roll or a gate's; the sewer kinds come from
	# the sewer packs only, min-max of them.
	for k: String in MonsterDefs.DEFS:
		if MonsterDefs.habitat(k) != "":
			check(not MonsterDefs.row(k).has("pack") and not MonsterDefs.row(k).has("gate") and not MonsterDefs.GATE_ORDER.has(k), "%s (habitat %s): no pack, no gate" % [k, MonsterDefs.habitat(k)])
			check(not MonsterFactory.KINDS.has(k), "%s is not a pack kind" % k)
	eq(MonsterDefs.sewer_kinds(), ["goo_imp"] as Array[String], "the sewer kinds")
	eq(MonsterDefs.habitat("goo_imp"), "sewer", "the goo imp lives in the sewer")
	for s in 200:
		a.seed = s
		for fl in [1, 2, 3, 4]:
			check(not MonsterFactory.compose(18, a, {"goo_imp": 50.0}, fl).has("goo_imp"), "no floor pack deals a goo imp (seed %d, floor %d)" % [s, fl])
	var sizes := {}
	for s in 60:
		a.seed = s
		var sp := MonsterFactory.compose_sewer(a)
		sizes[sp.size()] = true
		check(sp.size() >= GooImp.PACK_MIN and sp.size() <= GooImp.PACK_MAX and sp.count("goo_imp") == sp.size(), "a sewer pack is 3-4 goo imps (seed %d: %s)" % [s, sp])
	check(sizes.has(3) and sizes.has(4), "sewer packs of 3 and of 4 both happen")
	# Floor 1's rolls are the old ones: the same draws as a compose without the new kinds' rows.
	for s in 20:
		a.seed = s
		b.seed = s
		eq(MonsterFactory.compose(14, a, {}, 1), _old_compose(14, b), "floor 1 rolls as before the new kinds (seed %d)" % s)
	finish()


## The composer as it was before the pavise and the water boy (grunt, archer, brute, swarmer only).
static func _old_compose(budget: int, rng: RandomNumberGenerator) -> Array[String]:
	var costs := {"grunt": 2, "archer": 3, "brute": 6, "swarmer": 4}
	var wts := {"grunt": 5.0, "archer": 3.0, "brute": 1.5, "swarmer": 2.5}
	var plan: Array[String] = []
	var counts := {}
	var left := budget
	while true:
		var kinds: Array[String] = []
		var weights: Array[float] = []
		var total := 0.0
		for k: String in ["grunt", "archer", "brute", "swarmer"]:
			if int(costs[k]) > left or (k == "swarmer" and counts.get(k, 0) > 0):
				continue
			var w: float = float(wts[k]) * pow(0.5, counts.get(k, 0))
			kinds.append(k)
			weights.append(w)
			total += w
		if kinds.is_empty():
			break
		var roll := rng.randf() * total
		var pick := kinds[kinds.size() - 1]
		for i in kinds.size():
			roll -= weights[i]
			if roll <= 0.0:
				pick = kinds[i]
				break
		plan.append(pick)
		counts[pick] = counts.get(pick, 0) + 1
		left -= int(costs[pick])
	return plan

class_name ContractBoard
extends RefCounted
## The job board's generator: always 3 new offers, from 3 DIFFERENT client archetypes with a spread of
## difficulty (one easy, one middling, one hard, in a random order). Deterministic per board seed.

const OFFER_COUNT := 3


static func offers(board_seed: int) -> Array[ContractRun]:
	var rng := RandomNumberGenerator.new()
	rng.seed = board_seed * 40503 + 7
	var ids: Array[String] = ClientArchetype.IDS.duplicate()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := ids[i]
		ids[i] = ids[j]
		ids[j] = t
	var tiers: Array[float] = [rng.randf_range(0.1, 0.35), rng.randf_range(0.4, 0.65), rng.randf_range(0.7, 0.95)]
	for i in range(tiers.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tt := tiers[i]
		tiers[i] = tiers[j]
		tiers[j] = tt
	var out: Array[ContractRun] = []
	var used: Dictionary = {}
	for i in OFFER_COUNT:
		var s := ((board_seed * 31 + i * 7919 + 1) & 0x7fffffff) % 100000
		while used.has(s):
			s = (s + 1) % 100000
		used[s] = true
		out.append(ContractRun.make(ids[i], s, tiers[i]))
	return out


## A single contract straight from a seed (the --contract <seed> dev flag; floor 1 uses exactly this seed).
static func run_for_seed(run_seed: int) -> ContractRun:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7 + 3
	var id: String = ClientArchetype.IDS[absi(run_seed) % ClientArchetype.IDS.size()]
	return ContractRun.make(id, run_seed, rng.randf_range(0.2, 0.9))

class_name ContractBoard
extends RefCounted
## The job board's generator: always 3 new offers, from 3 DIFFERENT client archetypes with a spread of
## difficulty (one easy, one middling, one hard, in a random order). Deterministic per board seed.
##
## A haunted contract (ClientArchetype.HAUNTED_IDS, haunted-build-plan.md H1) takes one of the three slots on dice of its
## own (HAUNTED_CHANCE of boards): the slot keeps its seed and its difficulty tier, only the client changes. The hellgate
## offers are dealt exactly as before, so a board seed without a haunted offer shows the same three jobs it always did.

const OFFER_COUNT := 3
## The share of boards with a haunted offer in one slot (H1: half, so the new jobs are easy to find while they are reviewed).
const HAUNTED_CHANCE := 0.5


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
	_deal_haunted(board_seed, ids)
	var out: Array[ContractRun] = []
	var used: Dictionary = {}
	for i in OFFER_COUNT:
		var s := ((board_seed * 31 + i * 7919 + 1) & 0x7fffffff) % 100000
		while used.has(s):
			s = (s + 1) % 100000
		used[s] = true
		out.append(ContractRun.make(ids[i], s, tiers[i]))
	return out


## The haunted offer, on its own generator (so no hellgate offer's roll moves): on HAUNTED_CHANCE of boards, one of the
## first OFFER_COUNT slots of `ids` becomes a haunted client.
static func _deal_haunted(board_seed: int, ids: Array[String]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (board_seed * 69069 + 4111) & 0x7fffffff
	if rng.randf() >= HAUNTED_CHANCE:
		return
	var slot := rng.randi_range(0, OFFER_COUNT - 1)
	ids[slot] = ClientArchetype.HAUNTED_IDS[rng.randi_range(0, ClientArchetype.HAUNTED_IDS.size() - 1)]


## A single contract straight from a seed (the --contract <seed> dev flag; floor 1 uses exactly this seed). Always a
## hellgate client (ClientArchetype.IDS): every seed keeps the contract it always had.
static func run_for_seed(run_seed: int) -> ContractRun:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7 + 3
	var id: String = ClientArchetype.IDS[absi(run_seed) % ClientArchetype.IDS.size()]
	return ContractRun.make(id, run_seed, rng.randf_range(0.2, 0.9))


## A contract for client `id` (any of ClientArchetype.ALL_IDS) from a seed, at run_for_seed's difficulty for that seed (the
## --client <id> dev flag: a haunted contract without the board). An unknown id is a prepper's contract (ContractRun.make).
static func run_for_client(id: String, run_seed: int) -> ContractRun:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed * 7 + 3
	return ContractRun.make(id, run_seed, rng.randf_range(0.2, 0.9))

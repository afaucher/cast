class_name MonsterDefs
extends RefCounted
## Every monster kind in one place (docs/design/refactor-plan.md, H3): a row per kind. MonsterFactory, MonsterModels,
## Hellgate's spawn weights, SpellComponents' drops, ClientArchetype's pest names, the model triangle budgets and the
## sharks' bills all read it. Adding a kind is a row here, its Monster class and its model (and a test_net_contract
## REPLICATED line: the test fails without one).
##
## Row fields (all optional except "script"):
##   script     the Monster class's path (loaded on first use: a preload here would make a cycle through Monster)
##   model      the MonsterModel class's path (MonsterModels.make); none for a kind that builds its own (the sharks)
##   tris       the model's triangle budget (test_monster_models)
##   pack       {cost, weight}: the kind is dealt into room packs (MonsterFactory.KINDS / compose) at this point cost and
##              pick weight; "swarm": true means one pick is a clump of SWARM_MIN-SWARM_MAX of them (and at most one a pack)
##   gate       {w, per_p, per_phase, min}: a hellgate spawns it with weight max(min, w + per_p * pressure + per_phase *
##              origin phase). The row order of the gate kinds is the roll order (GATE_ORDER), so it stays fixed.
##   drops      component drops when one dies: [{spells, chance, charges?}] (SpellComponents.roll_drops)
##   pest       how a client names a pest of this kind ("skeletons"); the kinds with one are the contract pests
##   billed     {variant: {price, name}}: killing one bills the killer like a priced prop (the sharks)
##
## Order matters where noted: DEFS' order is the order of MonsterFactory.KINDS (the pack roll), MonsterModels.KINDS,
## the drop table and ClientArchetype.PEST_NAMES, which the floor plan and its checksum depend on.

const DEFS := {
	"grunt": {
		"script": "res://scripts/monsters/grunt.gd", "model": "res://scripts/art/lowpoly/monsters/grunt_model.gd", "tris": 1500,
		"pack": {"cost": 2, "weight": 5.0},
		"gate": {"w": 4.0},
		"drops": [{"spells": ["teeth"], "chance": 0.12}, {"spells": ["damp"], "chance": 0.06}],
		"pest": "skeletons",
	},
	"archer": {
		"script": "res://scripts/monsters/archer.gd", "model": "res://scripts/art/lowpoly/monsters/archer_model.gd", "tris": 1700,
		"pack": {"cost": 3, "weight": 3.0},
		"gate": {"w": 2.0, "per_p": 1.0},
		"drops": [{"spells": ["heal"], "chance": 0.15}, {"spells": ["vines"], "chance": 0.08}],
		"pest": "archers",
	},
	"brute": {
		"script": "res://scripts/monsters/brute.gd", "model": "res://scripts/art/lowpoly/monsters/brute_model.gd", "tris": 2600,
		"pack": {"cost": 6, "weight": 1.5},
		"gate": {"w": 0.5, "per_p": 1.5, "per_phase": 0.8},
		"drops": [{"spells": ["fireball", "armor"], "chance": 0.35}, {"spells": ["coffee"], "chance": 0.10}],
		"pest": "brutes",
	},
	"swarmer": {
		"script": "res://scripts/monsters/swarmer.gd", "model": "res://scripts/art/lowpoly/monsters/swarmer_model.gd", "tris": 1000,
		"pack": {"cost": 4, "weight": 2.5, "swarm": true},
		"gate": {"w": 5.0, "per_p": -1.0, "min": 0.5},
		## per imp (imps come in packs)
		"drops": [{"spells": ["tentacles"], "chance": 0.03}, {"spells": ["chicken"], "chance": 0.04}],
		"pest": "imps",
	},
	"goblin": {   ## the scout: never in a pack (SiteBuilder puts him in a corridor)
		"script": "res://scripts/monsters/goblin.gd", "model": "res://scripts/art/lowpoly/monsters/goblin_model.gd", "tris": 1900,
	},
	"shark": {   ## the pool sharks (docs/design/sharks.md): seed-built by SiteBuilder, never from the factory
		"script": "res://scripts/monsters/shark.gd",
		## user, 2026-10-19: the design's prices less 30 %
		"billed": {"regular": {"price": 8400, "name": "Shark"}, "laser": {"price": 12600, "name": "Laser shark"},
				"imp": {"price": 12600, "name": "Laser shark"}},
	},
	"jockey": {   ## the imp gunner riding a laser shark
		"script": "res://scripts/monsters/jockey.gd",
	},
	"gator": {   ## the sewer gator (docs/design/sewer-concept.md): seed-built (--sewer for now), never in a pack or a gate, never the pest
		"script": "res://scripts/monsters/gator.gd",
		## user, 2026-10-20: "6300", killed and billed once like the shark
		"billed": {"regular": {"price": 6300, "name": "Gator"}},
	},
}

## The hellgate roll walks its kinds in this order (a different order would spawn different kinds for the same roll).
const GATE_ORDER: Array[String] = ["swarmer", "grunt", "archer", "brute"]


static func row(kind: String) -> Dictionary:
	return DEFS.get(kind, {})


static func has(kind: String) -> bool:
	return DEFS.has(kind)


## The kinds dealt into room packs, in DEFS order.
static func pack_kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in DEFS:
		if (DEFS[k] as Dictionary).has("pack"):
			out.append(k)
	return out


## One pick of this kind is a clump (the imps).
static func is_swarm(kind: String) -> bool:
	return bool((row(kind).get("pack", {}) as Dictionary).get("swarm", false))


## {kind: value} of one pack field over the pack kinds.
static func pack_field(field: String) -> Dictionary:
	var out := {}
	for k in pack_kinds():
		out[k] = (DEFS[k]["pack"] as Dictionary)[field]
	return out


static var _scripts := {}


## {kind: Script} of every kind (loaded once).
static func scripts() -> Dictionary:
	if _scripts.is_empty():
		for k: String in DEFS:
			_scripts[k] = load(String(DEFS[k]["script"]))
	return _scripts


static var _models := {}


## The kind's MonsterModel script (loaded once), or null.
static func model_script(kind: String) -> Script:
	if not _models.has(kind):
		var path: String = row(kind).get("model", "")
		_models[kind] = load(path) if path != "" else null
	return _models[kind]


## The kinds with a MonsterModel, in DEFS order.
static func model_kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in DEFS:
		if (DEFS[k] as Dictionary).has("model"):
			out.append(k)
	return out


## A hellgate's kind weights at pressure p and origin phase, in GATE_ORDER.
static func gate_weights(p: float, phase_value: int) -> Dictionary:
	var out := {}
	for k in GATE_ORDER:
		var g: Dictionary = DEFS[k]["gate"]
		var w := float(g.get("w", 0.0)) + float(g.get("per_p", 0.0)) * p + float(g.get("per_phase", 0.0)) * float(phase_value)
		out[k] = maxf(float(g["min"]), w) if g.has("min") else w
	return out


## {kind: [drop entries]} of the kinds that drop something.
static func drops() -> Dictionary:
	var out := {}
	for k: String in DEFS:
		if (DEFS[k] as Dictionary).has("drops"):
			out[k] = DEFS[k]["drops"]
	return out


## {kind: "skeletons"} of the kinds a contract can name as its pest.
static func pest_names() -> Dictionary:
	var out := {}
	for k: String in DEFS:
		if (DEFS[k] as Dictionary).has("pest"):
			out[k] = DEFS[k]["pest"]
	return out


## {variant: price} / {variant: name} of a billed kind.
static func prices(kind: String) -> Dictionary:
	var out := {}
	var b: Dictionary = row(kind).get("billed", {})
	for v: String in b:
		out[v] = int(b[v]["price"])
	return out


static func bill_names(kind: String) -> Dictionary:
	var out := {}
	var b: Dictionary = row(kind).get("billed", {})
	for v: String in b:
		out[v] = String(b[v]["name"])
	return out

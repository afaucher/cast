class_name MonsterModels
extends RefCounted
## Factory for the faceted monster models, keyed by Monster.kind. Kept apart from MonsterModel so the
## base class never has to reference its own subclasses.
##
##   var model: MonsterModel = MonsterModels.make("grunt")      # null for an unknown kind

const KINDS: Array[String] = ["grunt", "archer", "brute", "swarmer", "goblin"]
## Models built for a design that no Monster kind uses yet (labs and tests only). The goblin scout went live in
## monster awareness step 2 (scripts/monsters/goblin.gd).
const DESIGN_KINDS: Array[String] = []


static func make(kind: String) -> MonsterModel:
	match kind:
		"grunt":
			return GruntModel.new()
		"archer":
			return ArcherModel.new()
		"brute":
			return BruteModel.new()
		"swarmer":
			return SwarmerModel.new()
		"goblin":
			return GoblinModel.new()
	return null

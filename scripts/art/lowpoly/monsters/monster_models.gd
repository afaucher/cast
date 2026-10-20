class_name MonsterModels
extends RefCounted
## Factory for the faceted monster models, keyed by Monster.kind. Kept apart from MonsterModel so the
## base class never has to reference its own subclasses.
##
##   var model: MonsterModel = MonsterModels.make("grunt")      # null for an unknown kind

## Every kind with a model (MonsterDefs rows with a "model").
static var KINDS: Array[String] = MonsterDefs.model_kinds()
## Models built for a design that no Monster kind uses yet (labs and tests only). The goblin scout went live in
## monster awareness step 2 (scripts/monsters/goblin.gd).
const DESIGN_KINDS: Array[String] = []


static func make(kind: String) -> MonsterModel:
	var model := MonsterDefs.model_script(kind)
	return model.new() as MonsterModel if model != null else null
